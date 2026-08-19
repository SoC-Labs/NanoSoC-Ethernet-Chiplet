#!/usr/bin/env python3
"""CSR / seal-ring rule-category budget RATCHET -- not a fix, a tripwire.

Copyright 2026, SoC Labs (www.soclabs.org)

WHY THIS EXISTS
----------------
Archive 2 of IMEC's padring/DRC re-check (the first full library merge -- see
docs/tapeout/53-gate-promotion-plan.md §2 and CONVERGENCE_PLAN_2026-08-18.md
§8) showed three named seal-ring rulechecks grow sharply against archive 1:

    CSR.R.2:B    104 -> 644   (+519%)
    CSR.R.2:D    91(364) -> 804(816)   (+783%)
    CSR.EN.8     28 -> 96    (+243%)

and 157 rule categories fire that never appeared in archive 1's report at
all. NONE of this is understood or fixed. What IS true is that if someone
re-runs a full-merge DRC check in the future (against IMEC, or a local
Calibre seat with real vendor geometry) and these numbers get WORSE without
anyone noticing, that is a distinct, worse problem than the one already on
record -- exactly the class of silent regression `DRC_DESIGN_BUDGET`/
`DRC_DENSITY_BUDGET` already guard against for the main `drc` stage (see
`ASIC/genus-innovus/drc_project.mk`, `scripts/ci/drc_census.py`).

This script is that same discipline, applied to a different, currently-
unfixed cluster: a CEILING, not a clean target, recorded in
`ASIC/genus-innovus/scripts/calibre/csr_ratchet_budget.yaml` -- read that
file's own header before this one; it carries the full provenance, the
staleness caveat (the baseline is against the LEGACY, 2026-08-10 reference
GDS IMEC actually checked, not the current build) and why the growth is
mostly unattributed.

WHY A STANDALONE SIBLING, NOT AN EXTENSION OF drc_census.py
--------------------------------------------------------------
drc_census.py answers a different question -- "is the DESIGN-owned bucket of
OUR OWN Calibre run clean against a budget of zero" -- over a report format
and owner-attribution model (cell-scoped waivers, io-pad/vendor-memory
buckets, density-window .density files) built entirely around runs THIS
project produces locally. The CSR ratchet answers "did a set of NAMED
rulechecks, measured on a BROKER'S report against a MERGED library we cannot
reproduce locally, get worse than the worst we've already seen" -- there is
no local run to attribute-by-cell (the corner cell IMEC attributes most of
this to, `CORNER_B`, does not exist in our own GDS at all -- see
CONVERGENCE_PLAN §8), no density windows, and no waiver-by-cell concept: a
CSR count either exceeds its ceiling or it does not. Bolting that onto
drc_census.py's owner-bucket/waiver machinery would either warp that model to
fit a shape it was not built for, or add a large parallel code path inside
one file answering two unrelated questions. This script DOES reuse
drc_census.py's `parse_summary()` (the same "RULECHECK ... TOTAL Result
Count = N (M)" parser, main-section-only, no double count) rather than
reimplementing it -- verified to work unmodified against IMEC's report format
too, which shares the same Calibre summary grammar this project's own runs
use.

WHAT THIS DOES
---------------
Given a DRC summary (a real Calibre/IMEC-format `.drc.summary` or `.rpt`):

  1. For each of the three tracked checks in the budget file, compares the
     summary's TOTAL Result Count against the recorded `ceiling`. Exceeding
     it FAILS. Matching or improving on it does not "pass" in any meaningful
     sense (these are not understood or fixed) but does not fail either --
     see the budget file's own header for why "not yet gated on the current
     build" is the honest framing today.
  2. Separately, any rulecheck FIRING (nonzero) in the summary that is not
     already named in EITHER `tracked_checks` OR `new_categories` in the
     budget file is FLAGGED (printed, and returned in the report), never
     failed on by itself -- a genuinely new category appearing is worth a
     human's attention on its own terms, distinct from a known-bad count
     growing further, per doc 53 §2's own framing.

`--self-test` re-derives the three tracked counts and the 157-entry
new-categories rollup DIRECTLY from the two archive reports on disk (when
reachable -- see ARCHIVE REACHABILITY below) and fails if the budget file has
DRIFTED from what the raw reports say, then runs a battery of synthetic
fixtures to prove the ratchet mechanism itself can discriminate a real
failure from a real pass. This is the stale/drift self-test discipline this
project already applies to `drc_waivers.yaml` (docs/tapeout/
39-po-r8-resolved.md §8's proof table; drc_census.py's `load_waivers`/
`apply_waivers` stale+drift checks) -- applied here to a budget file instead
of a waiver file, because the failure mode this exists to catch is the same
shape: a recorded number that quietly stops matching reality is worse than
no recorded number at all, because it reads as coverage it does not have.

ARCHIVE REACHABILITY
----------------------
`ASIC/imec_results` is a gitignored, host-local directory of broker
deliverables (see `.gitignore`, and `csr_ratchet_budget.yaml`'s own
provenance section) -- it will not exist on a fresh clone or most CI
runners. When the two archive reports are not reachable at
`--archives-root` (default: `ASIC/imec_results` relative to the repo root),
the drift-against-raw-archives half of `--self-test` reports SKIPPED, not a
pass: "cannot re-derive, archives not present on this host" is printed
explicitly rather than silently treated as "the file is fine". The synthetic
fixture half needs no archive and always runs.

Usage
-----
    csr_ratchet.py <drc_summary_or_rundir> [--budget PATH]
    csr_ratchet.py --self-test [--budget PATH] [--archives-root DIR] [--json OUT]

Exit status
-----------
    0  (normal mode) no tracked check exceeds its ceiling, and the budget
       file itself loaded cleanly. Untracked-new-category flags do not
       affect this.
    1  (normal mode) a tracked check exceeds its ceiling, OR the budget file
       is malformed/unreadable, OR the summary could not be parsed.
    0  (--self-test) every self-test case behaved as expected -- the ratchet
       mechanism discriminates correctly, INCLUDING the archive drift check
       when the archives are reachable.
    1  (--self-test) at least one self-test case did NOT behave as expected
       -- the ratchet itself is broken (would not have failed / would have
       falsely failed), or the recorded baseline has drifted from the raw
       archive reports.
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import sys
import tempfile
from pathlib import Path

try:
    import yaml
except ImportError:
    yaml = None

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import drc_census  # noqa: E402  -- reuse parse_summary(), see docstring above

REPO_ROOT = HERE.parent.parent
DEFAULT_BUDGET = (REPO_ROOT / "ASIC" / "genus-innovus" / "scripts" / "calibre"
                  / "csr_ratchet_budget.yaml")
DEFAULT_ARCHIVES_ROOT = REPO_ROOT / "ASIC" / "imec_results"

EXIT_OK = 0
EXIT_FAIL = 1


# ---------------------------------------------------------------------------
# Budget file loading -- same defensive shape as drc_census.load_waivers():
# a missing file is a hard usage error here (unlike a waiver file, ABSENCE OF
# A BUDGET IS NOT "NOTHING TO RATCHET", it means this check cannot run at
# all), a present-but-broken one is reported field-by-field rather than a
# bare traceback.
# ---------------------------------------------------------------------------
def load_budget(path: Path):
    """Return (tracked: {check: row}, new_categories: {check: [count, orig]},
    meta: dict, problems: [str]). `tracked`/`new_categories` are None on a
    hard failure (file missing/unparseable); problems then explains why."""
    if not path.exists():
        return None, None, {}, [f"no budget file at {path}"]
    if yaml is None:
        return None, None, {}, [f"{path} exists but PyYAML is not installed"]
    try:
        doc = yaml.safe_load(path.read_text()) or {}
    except Exception as e:                                       # noqa: BLE001
        return None, None, {}, [f"{path} is not parseable YAML: {e}"]
    if not isinstance(doc, dict):
        return None, None, {}, [f"{path} does not parse to a mapping"]

    problems = []
    meta = doc.get("applies_to") or {}

    tracked: dict[str, dict] = {}
    for i, row in enumerate(doc.get("tracked_checks") or []):
        where = f"{path} tracked_checks[{i}]"
        check = row.get("check")
        ceiling = row.get("ceiling")
        if not check:
            problems.append(f"{where}: missing `check:`")
            continue
        if not isinstance(ceiling, int) or ceiling < 0:
            problems.append(f"{where} ({check}): `ceiling:` must be a "
                             f"non-negative integer, got {ceiling!r}")
            continue
        if not row.get("justification"):
            problems.append(f"{where} ({check}): no `justification:` -- an "
                             f"unexplained ceiling is the thing this file "
                             f"exists to prevent")
            continue
        if check in tracked:
            problems.append(f"{where}: duplicate tracked check {check!r}")
            continue
        tracked[check] = row

    new_categories: dict[str, list] = {}
    for check, val in (doc.get("new_categories") or {}).items():
        if (not isinstance(val, list) or len(val) != 2
                or not all(isinstance(v, int) and v >= 0 for v in val)):
            problems.append(f"{path} new_categories[{check!r}]: expected "
                             f"[count, original] as two non-negative ints, "
                             f"got {val!r}")
            continue
        if check in tracked:
            problems.append(f"{path}: {check!r} is in BOTH tracked_checks "
                             f"and new_categories -- name it in exactly one")
            continue
        new_categories[check] = val

    if not tracked and not problems:
        problems.append(f"{path}: zero tracked_checks -- a ratchet that "
                         f"tracks nothing cannot fail, which is not this "
                         f"file's job")

    if problems:
        return None, None, meta, problems
    return tracked, new_categories, meta, []


# ---------------------------------------------------------------------------
# Summary loading. Accepts a direct file (Calibre .drc.summary, or an IMEC
# .rpt -- same grammar) or a directory to glob inside, matching drc_census's
# own rundir convention (*.drc.summary) with a *.rpt fallback for IMEC's
# naming.
# ---------------------------------------------------------------------------
def find_summary(path: Path) -> Path | None:
    """Locate the Calibre .drc.summary under a file or run directory."""
    if path.is_file():
        return path
    if path.is_dir():
        for pat in ("*.drc.summary", "*.rpt"):
            cands = sorted(path.glob(pat))
            if cands:
                return cands[0]
    return None


def load_checks(summary_path: Path) -> dict[str, int]:
    """{rulecheck_name: TOTAL Result Count (capped-display number)} -- the
    same number `ceiling`/`archive2_count` in the budget file are recorded
    against, per its own header."""
    _primary, _cap, checks, _by_cell, _estimates, _rdb_capped = \
        drc_census.parse_summary(str(summary_path))
    return checks


# ---------------------------------------------------------------------------
# The ratchet verdict itself.
# ---------------------------------------------------------------------------
def evaluate(tracked: dict, new_categories: dict, checks: dict):
    """Return (tracked_rows, untracked_new, over) -- see module docstring."""
    tracked_rows = []
    over = []
    for check, row in sorted(tracked.items()):
        ceiling = row["ceiling"]
        current = checks.get(check)
        if current is None:
            status = "ABSENT"
        elif current > ceiling:
            status = "OVER"
        else:
            status = "OK"
        entry = {"check": check, "ceiling": ceiling, "current": current,
                  "status": status,
                  "archive2_count": row.get("archive2_count")}
        tracked_rows.append(entry)
        if status == "OVER":
            over.append(entry)

    known = set(tracked) | set(new_categories)
    untracked_new = sorted(
        (name, n) for name, n in checks.items() if n > 0 and name not in known)

    return tracked_rows, untracked_new, over


def print_report(summary_path, tracked_rows, untracked_new, over, meta):
    """Print the per-check table, the untracked-category list and the verdict."""
    print(f"summary        : {summary_path}")
    print(f"budget block   : {meta.get('block', '?')}")
    print(f"baseline       : archive2 = {meta.get('archive2', '?')}  "
          f"(measured {meta.get('measured_utc', '?')}, "
          f"STALE reference GDS -- see the budget file's own header)")
    print()
    print("tracked checks (ceiling = worst seen in archive 2, NOT a clean target):")
    for r in tracked_rows:
        mark = {"OK": "ok  ", "OVER": "OVER", "ABSENT": "n/a "}[r["status"]]
        cur = "absent from this run" if r["current"] is None else str(r["current"])
        print(f"  [{mark}] {r['check']:<14} current={cur:<22} ceiling={r['ceiling']}")
    print()
    if untracked_new:
        print(f"FLAG (not gated): {len(untracked_new)} rulecheck(s) fired in this "
              f"summary that are in NEITHER tracked_checks NOR new_categories -- "
              f"a genuinely new category is worth a human's attention on its own:")
        for name, n in untracked_new[:20]:
            print(f"    {name:<28} {n}")
        if len(untracked_new) > 20:
            print(f"    ... and {len(untracked_new) - 20} more")
    else:
        print("no untracked rule categories fired in this summary.")
    print()
    if over:
        print(f"FAIL: {len(over)} tracked check(s) exceed their recorded ceiling:")
        for r in over:
            print(f"    {r['check']}: {r['current']} > ceiling {r['ceiling']}")
    else:
        print("PASS: no tracked check exceeds its recorded ceiling. This is NOT "
              "a clean bill -- see the budget file's header. It only means "
              "nothing got WORSE than the worst already on record.")


def cmd_check(args) -> int:
    """check: score this run's CSR counts against the budget. 0 within, 1 over."""
    budget_path = Path(args.budget)
    tracked, new_categories, meta, problems = load_budget(budget_path)
    if problems:
        print(f"FAIL: budget file problem(s) at {budget_path}:")
        for p in problems:
            print(f"  * {p}")
        return EXIT_FAIL

    summary_path = find_summary(Path(args.target))
    if summary_path is None:
        print(f"FAIL: no DRC summary found at/under {args.target}")
        return EXIT_FAIL
    try:
        checks = load_checks(summary_path)
    except Exception as e:                                       # noqa: BLE001
        print(f"FAIL: could not parse {summary_path}: {e}")
        return EXIT_FAIL
    if not checks:
        print(f"FAIL: {summary_path} parsed to zero rulechecks")
        return EXIT_FAIL

    tracked_rows, untracked_new, over = evaluate(tracked, new_categories, checks)
    print_report(summary_path, tracked_rows, untracked_new, over, meta)

    if args.json:
        Path(args.json).parent.mkdir(parents=True, exist_ok=True)
        Path(args.json).write_text(json.dumps({
            "summary": str(summary_path), "budget": str(budget_path),
            "tracked": tracked_rows, "untracked_new": untracked_new,
            "over_budget": over, "verdict": "FAIL" if over else "PASS",
        }, indent=2) + "\n")

    return EXIT_FAIL if over else EXIT_OK


# ---------------------------------------------------------------------------
# --self-test: (a) re-derive the recorded baseline from the raw archives on
# disk when reachable, (b) prove the mechanism can discriminate a real
# over-ceiling failure, an at-ceiling pass, and an untracked-new-category
# flag, from synthetic fixtures that need no archive at all.
# ---------------------------------------------------------------------------
def _archive_checks(archives_root: Path, archive_dirname: str, report_rel: str):
    """(checks, path) parsed from one archive's report, or (None, path) if absent."""
    p = archives_root / archive_dirname / report_rel
    if not p.is_file():
        return None, p
    return load_checks(p), p


def selftest_drift(tracked, new_categories, meta, archives_root: Path):
    """Re-derive the tracked-check counts and the new_categories set DIRECTLY
    from the two raw archive reports and compare against what the budget
    file records. Returns (results: [(name, ok, detail)], skipped: bool)."""
    a1_checks, a1_path = _archive_checks(
        archives_root, meta.get("archive1", ""), meta.get("archive1_report", ""))
    a2_checks, a2_path = _archive_checks(
        archives_root, meta.get("archive2", ""), meta.get("archive2_report", ""))

    if a1_checks is None or a2_checks is None:
        missing = a1_path if a1_checks is None else a2_path
        return [("archive-drift", None,
                 f"SKIPPED -- cannot re-derive, {missing} not present on this "
                 f"host (ASIC/imec_results is gitignored, host-local broker "
                 f"data). This is NOT a pass -- the budget file's recorded "
                 f"numbers are unverified on this host.")], True

    results = []
    for check, row in sorted(tracked.items()):
        real_a1 = a1_checks.get(check, 0)
        real_a2 = a2_checks.get(check, 0)
        ok = (real_a1 == row.get("archive1_count") and
              real_a2 == row.get("archive2_count") == row.get("ceiling"))
        detail = (f"recorded a1={row.get('archive1_count')} a2={row.get('archive2_count')} "
                  f"ceiling={row.get('ceiling')}  vs  raw a1={real_a1} a2={real_a2}")
        results.append((f"drift:{check}", ok, detail))

    real_new = sorted(n for n, c in a2_checks.items() if c > 0 and n not in a1_checks)
    recorded_new = sorted(new_categories)
    ok = real_new == recorded_new
    detail = (f"{len(real_new)} raw vs {len(recorded_new)} recorded"
              if ok else
              f"MISMATCH: {len(real_new)} raw vs {len(recorded_new)} recorded -- "
              f"missing from file: {sorted(set(real_new) - set(recorded_new))[:5]}, "
              f"stale in file: {sorted(set(recorded_new) - set(real_new))[:5]}")
    results.append(("drift:new_categories", ok, detail))
    return results, False


def _write_summary(tmpdir: str, name: str, rows: dict) -> Path:
    """rows: {check: (count, original)}. Minimal but real Calibre-grammar
    summary -- enough for drc_census.parse_summary()'s regexes."""
    lines = ["Layout Primary Cell:       synthetic_fixture", ""]
    for check, (n, orig) in rows.items():
        pad = "." * max(1, 40 - len(check))
        lines.append(f"RULECHECK {check} {pad} TOTAL Result Count = {n}   ({orig})")
    p = Path(tmpdir) / name
    p.write_text("\n".join(lines) + "\n")
    return p


def selftest_fixtures(tmpdir: str):
    """Synthetic fixtures proving the ratchet DISCRIMINATES: an over-ceiling
    case must fail, an at-ceiling case must pass, an untracked-new-category
    case must flag but not fail on its own, and a malformed budget file must
    be refused. Returns [(name, ok, detail)]."""
    results = []

    tracked = {
        "CSR.R.2:B": {"check": "CSR.R.2:B", "ceiling": 644,
                       "archive1_count": 104, "archive2_count": 644,
                       "justification": "x"},
        "CSR.R.2:D": {"check": "CSR.R.2:D", "ceiling": 804,
                       "archive1_count": 91, "archive2_count": 804,
                       "justification": "x"},
        "CSR.EN.8": {"check": "CSR.EN.8", "ceiling": 96,
                      "archive1_count": 28, "archive2_count": 96,
                      "justification": "x"},
    }
    new_categories = {"CO.EN.1": [200, 200]}

    # 1. Over-ceiling: CSR.R.2:B reports MORE than its recorded ceiling.
    #    This is the exact scenario the task's final proof step asks for --
    #    a synthetic "worse" number the ratchet must reject.
    checks = {"CSR.R.2:B": 700, "CSR.R.2:D": 804, "CSR.EN.8": 96, "CO.EN.1": 200}
    rows, untracked, over = evaluate(tracked, new_categories, checks)
    ok = len(over) == 1 and over[0]["check"] == "CSR.R.2:B" and over[0]["current"] == 700
    results.append(("fixture:over-ceiling", ok,
                     f"CSR.R.2:B=700 > ceiling 644 -- expected exactly 1 OVER "
                     f"result naming CSR.R.2:B, got {[o['check'] for o in over]}"))

    # 2. At-ceiling: exactly the recorded worst-seen value must NOT fail --
    #    the ceiling is inclusive (it records what WAS measured, not a limit
    #    strictly below it).
    checks = {"CSR.R.2:B": 644, "CSR.R.2:D": 804, "CSR.EN.8": 96, "CO.EN.1": 200}
    rows, untracked, over = evaluate(tracked, new_categories, checks)
    ok = len(over) == 0
    results.append(("fixture:at-ceiling-passes", ok,
                     f"every tracked check exactly at its ceiling -- expected "
                     f"0 OVER results, got {len(over)}"))

    # 3. Untracked new category: fires, must be FLAGGED but must NOT by
    #    itself produce an OVER/failure.
    checks = {"CSR.R.2:B": 644, "CSR.R.2:D": 804, "CSR.EN.8": 96,
              "CO.EN.1": 200, "TOTALLY.NEW.RULE": 5}
    rows, untracked, over = evaluate(tracked, new_categories, checks)
    ok = (len(over) == 0 and untracked == [("TOTALLY.NEW.RULE", 5)])
    results.append(("fixture:untracked-category-flags-not-fails", ok,
                     f"expected 0 OVER + untracked=[('TOTALLY.NEW.RULE', 5)], "
                     f"got over={[o['check'] for o in over]} untracked={untracked}"))

    # 4. Both at once: an over-ceiling tracked check AND a new category in
    #    the same run -- the two mechanisms must not mask each other.
    checks = {"CSR.R.2:B": 900, "CSR.R.2:D": 804, "CSR.EN.8": 96,
              "CO.EN.1": 200, "ANOTHER.NEW.ONE": 3}
    rows, untracked, over = evaluate(tracked, new_categories, checks)
    ok = (len(over) == 1 and over[0]["check"] == "CSR.R.2:B"
          and untracked == [("ANOTHER.NEW.ONE", 3)])
    results.append(("fixture:over-and-untracked-both-report", ok,
                     f"expected 1 OVER (CSR.R.2:B) AND 1 untracked "
                     f"(ANOTHER.NEW.ONE) simultaneously, got over="
                     f"{[o['check'] for o in over]} untracked={untracked}"))

    # 5. A tracked check ABSENT from the run (e.g. a partial/scoped re-check)
    #    must be reported n/a, never silently treated as OVER or as a pass
    #    that hides its absence.
    checks = {"CSR.R.2:D": 804, "CSR.EN.8": 96}
    rows, untracked, over = evaluate(tracked, new_categories, checks)
    absent = [r for r in rows if r["status"] == "ABSENT"]
    ok = len(over) == 0 and len(absent) == 1 and absent[0]["check"] == "CSR.R.2:B"
    results.append(("fixture:absent-check-not-silently-passed", ok,
                     f"CSR.R.2:B missing from the run -- expected status "
                     f"ABSENT not OK, got {[r['status'] for r in rows if r['check']=='CSR.R.2:B']}"))

    # 6. Malformed budget file: missing `justification:` on a tracked row
    #    must be REFUSED, the same discipline drc_waivers.yaml enforces.
    bad_yaml = tmpdir + "/bad_budget.yaml"
    Path(bad_yaml).write_text(
        "tracked_checks:\n  - check: CSR.R.2:B\n    ceiling: 644\n"
        "new_categories: {}\n")
    _t, _n, _m, problems = load_budget(Path(bad_yaml))
    ok = bool(problems) and any("justification" in p for p in problems)
    results.append(("fixture:malformed-budget-refused", ok,
                     f"a tracked row with no justification: must be refused, "
                     f"got problems={problems}"))

    # 7. Budget file naming the SAME check in both tracked_checks and
    #    new_categories must be refused -- ambiguous scoping is not allowed.
    dup_yaml = tmpdir + "/dup_budget.yaml"
    Path(dup_yaml).write_text(
        "tracked_checks:\n  - check: CSR.R.2:B\n    ceiling: 644\n"
        "    justification: x\n"
        "new_categories:\n  CSR.R.2:B: [644, 644]\n")
    _t, _n, _m, problems = load_budget(Path(dup_yaml))
    ok = bool(problems) and any("BOTH" in p for p in problems)
    results.append(("fixture:duplicate-check-refused", ok,
                     f"a check named in both sections must be refused, "
                     f"got problems={problems}"))

    return results


def cmd_selftest(args) -> int:
    """selftest: re-derive the budget from the raw archives and confirm it matches."""
    budget_path = Path(args.budget)
    tracked, new_categories, meta, problems = load_budget(budget_path)

    all_results: list[tuple[str, bool | None, str]] = []
    if problems:
        all_results.append(("budget-loads-cleanly", False,
                             "; ".join(problems)))
    else:
        all_results.append(("budget-loads-cleanly", True,
                             f"{len(tracked)} tracked check(s), "
                             f"{len(new_categories)} new_categories entries"))
        drift_results, _skipped = selftest_drift(
            tracked, new_categories, meta, Path(args.archives_root))
        all_results.extend(drift_results)

    with tempfile.TemporaryDirectory(prefix="csr_ratchet_selftest_") as tmp:
        all_results.extend(selftest_fixtures(tmp))

    print(f"{'case':<42} {'result':<10} detail")
    print("-" * 100)
    n_fail = 0
    n_skip = 0
    for name, ok, detail in all_results:
        if ok is None:
            mark, n_skip = "SKIP", n_skip + 1
        elif ok:
            mark = "ok"
        else:
            mark, n_fail = "FAIL", n_fail + 1
        print(f"{name:<42} {mark:<10} {detail}")
    print("-" * 100)
    print(f"SELFTEST: {len(all_results) - n_fail - n_skip} passed, "
          f"{n_fail} failed, {n_skip} skipped, {len(all_results)} total")

    if args.json:
        Path(args.json).parent.mkdir(parents=True, exist_ok=True)
        Path(args.json).write_text(json.dumps({
            "budget": str(budget_path),
            "cases": [{"name": n, "ok": ok, "detail": d} for n, ok, d in all_results],
            "passed": len(all_results) - n_fail - n_skip,
            "failed": n_fail, "skipped": n_skip, "total": len(all_results),
        }, indent=2) + "\n")

    return EXIT_FAIL if n_fail else EXIT_OK


def main() -> int:
    """Dispatch to check or selftest."""
    ap = argparse.ArgumentParser(description=__doc__,
                                  formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("target", nargs="?",
                     help="a DRC summary file, or a directory to find one in")
    ap.add_argument("--budget", default=str(DEFAULT_BUDGET),
                     help=f"ratchet budget YAML (default: {DEFAULT_BUDGET})")
    ap.add_argument("--archives-root", default=str(DEFAULT_ARCHIVES_ROOT),
                     help="where the two IMEC archive dirs live, for "
                          "--self-test's drift check "
                          f"(default: {DEFAULT_ARCHIVES_ROOT})")
    ap.add_argument("--self-test", action="store_true",
                     help="prove the ratchet mechanism discriminates, and "
                          "re-validate the budget file against the raw "
                          "archives when reachable; needs no `target`")
    ap.add_argument("--json", help="write a machine-readable report here")
    args = ap.parse_args()

    if args.self_test:
        return cmd_selftest(args)
    if not args.target:
        print("USAGE: csr_ratchet.py <drc_summary_or_rundir>  (or --self-test)")
        return EXIT_FAIL
    return cmd_check(args)


if __name__ == "__main__":
    sys.exit(main())
