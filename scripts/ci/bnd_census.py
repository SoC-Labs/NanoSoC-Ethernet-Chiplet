#!/usr/bin/env python3
"""
Parse a Calibre BND (bond-pad / seal-ring BEOL) run directory and report it in
a form a signoff gate can act on. Sibling to scripts/ci/drc_census.py, same
pattern, same self-test discipline (docs/tapeout/53-gate-promotion-plan.md §1,
row 4: "Census-style script over the BND summary, cell-scoped waiver for any
residual known-artefact, same stale/drift self-test as `drc`").

WHY A SEPARATE SCRIPT, NOT A drc_census.py FLAG
------------------------------------------------
`make bnd` runs a DIFFERENT foundry Calibre deck (CN65_WIRE_BOND_<stack>, see
docs/tapeout/50-bnd-and-logo-checks.md Part A) against a DIFFERENT rule
namespace (PM/AP/CB/CB2/RV/seal-ring, not M1-M9/VIA/OD/PO). The summary FILE
FORMAT is identical Calibre output, so parse_summary()/load_waivers()/
apply_waivers() below are deliberately near-identical to drc_census.py's --
this is the "reuse the pattern" doc 53 asks for. They are NOT imported from
drc_census.py: that script is the `check:` for the block-gated `drc` stage in
ci/signoff.yaml with its own fixture-proven history
(ci/fixtures/drc/fail-waiver-stale et al.) -- refactoring it to share a module
with a brand-new, unpromoted script risks the ALREADY-BLOCKING gate for a
sibling that has not earned that risk yet. Duplication here is the deliberate,
lower-risk choice; if `bnd` promotes to block and this drifts from
drc_census.py's proven behaviour, THEN factor the shared engine out.

WHAT MAKES BND DIFFERENT FROM DRC, MEASURED NOT ASSUMED (2026-08-18 real run)
------------------------------------------------------------------------------
Running `make bnd` against the exact GDS IMEC checked
(md5 7f6214965501c911bd65069378ae911d,
runs/20260811T103338Z_fill-verify/prev_outputs/nanosoc_eth_chiplet_pads_logo_full_L300.gds)
reproduces docs/tapeout/50-bnd-and-logo-checks.md's numbers exactly: 18 raw
results (12 AP.W.1 + 2 AP.W.2 + 4 AP.S.1), 0 PM.W.1, 0 AP.S.4. That 0 is not
"clean" -- LAYER PMi/CBi/CB2i all read 0 original geometry in this stream
(no dummy fill or seal ring merged locally), so PM.*/CB.*/CBVIA*.*/CBM*.*/
CUPCB.*/CUPVIAT.* and AP.S.4 (space *to* PM/CB2) cannot fire against geometry
that is not there. This script reports that bucket SEPARATELY, the same
discipline drc_census.py uses for front-end (OD/PO) density: unmeasurable is
not passing and not failing, and folding it into "0 violations" would be a
manufactured green.

A GENUINE, NOT-YET-EXPLAINED FINDING: by-cell attribution puts 12 AP.W.1 + 4
AP.S.1 = 16 results in the LAYOUT PRIMARY CELL ITSELF (nanosoc_eth_chiplet_pads),
not in a pad or corner abstraction -- i.e. this is OUR OWN top-level AP
routing, and it is an EXACT match against IMEC's independently-run count on
the same file. Pulling coordinates out of the .bnd.results database
(calibre_runs/bnd_postfix_check/nanosoc_eth_chiplet_pads.bnd.results, this
pass) shows every one of the 16 polygons sits well inside the core
(x 314-1006um, y 872-1125um on a 1600x2000um die with a 135um pad row) --
this is real AP-layer redistribution routing, not a pad-ring/seal-ring
artefact, and docs/tapeout/50-bnd-and-logo-checks.md's "exact match" framing
never asked whether these 16 are ACCEPTABLE, only whether they reproduce.
They do not have a mechanism argument the way PO.R.8 does (no black-boxing
story explains a real width/spacing violation in metal WE drew), so they are
NOT waived here -- see the "DELIBERATELY NOT WAIVED" block in
bnd_waivers.yaml. This is exactly why `bnd` is NOT promoted to a zero-budget
block gate by this pass; see docs/tapeout/50-bnd-and-logo-checks.md Part A.1.

AP.W.2 (2 results, in PAD70GU/PAD70NU) IS waived: it is the TSMC reference
bond-pad cell's own AP redistribution plate, deliberately wider than the
35um max (it is the bond-wire landing target), and IMEC's real submission
--- with THEIR OWN independently-added dummy fill and seal ring merged in ---
reports the identical count in the identical cells on BOTH archives. Same
corroboration shape as the PO.R.8 waiver: a vendor-authored cell's own
geometry, confirmed inherent by an independent run, not introduced by this
design and not fixable here short of choosing different foundry pad cells.

Usage:  bnd_census.py <rundir> [--budget N] [--waivers PATH | --no-waivers]
Env:    BND_DESIGN_BUDGET, BND_WAIVERS  (command line wins)
"""

import argparse
import glob
import os
import re
import sys

# Same shape as drc_census.py's owner split, generalised for the BND rule
# family. No MEMORY bucket: rf_*/flash_cache_*/rom_via* cells structurally
# cannot carry PM/AP/CB geometry (established docs/tapeout/50, doc39's
# mechanism), so a BND result attributed to one would be a genuine surprise,
# not an expected bucket -- left DESIGN so it cannot vanish unnoticed.
# CORNER/UCSRN added for BND specifically: IMEC's own by-cell breakdown
# attributes results to CORNER_B and UCSRN_NOVIA, real vendor seal-ring/corner
# cells this design cannot see locally (no Back-End PDK) -- see
# docs/tapeout/39-po-r8-resolved.md's "needs-vendor-data" class.
IOPAD_PREFIXES = ("PAD", "PDDW", "PDUW", "PVDD", "PVSS", "PFILLER", "PCORNER",
                   "CORNER", "UCSRN")

DESIGN, IOPAD = "design", "io-pad-abstract"

# Rule families that CANNOT fire in a local, un-merged run: this design's own
# GDS carries zero PM/CB/CB2 geometry (LAYER PMi/CBi/CB2i all "Original
# Geometry Count = 0" in every local BND summary, docs/tapeout/50 Part A "The
# two deltas"). Reporting these as "0 violations" would be indistinguishable
# from a real clean pass; reporting them here, separately, is not. A NONZERO
# result here is a genuine anomaly (the absent-geometry assumption no longer
# holds for this run) and IS flagged as one.
ABSENT_GEOMETRY_PREFIXES = (
    "PM.", "CB.", "CBVIA", "CBM", "CUPCB.", "CUPVIAT.", "RV.",
    "AP.S.4",   # space TO PM/CB2 -- needs the same absent geometry
)

# A SEPARATE failure mode: not absent geometry but SPARSE geometry, where
# neither a zero nor a nonzero result is trustworthy either way, so this
# family is never gated AND never flagged as an anomaly regardless of value
# -- same discipline drc_census.py already applies to front-end (OD/PO)
# density. Measured 2026-08-18 against ASIC/eth-chiplet/build/fp1505 (the
# toolkit-lineage stream this design's `bnd` CI stage actually runs
# against): LAYER APi carries only 7 (12) shapes there, against 40 (285) in
# the legacy pad-ring-merged reference stream, and AP.DN.1.L (density < 0.1)
# fires a spurious single result purely because there is almost no AP
# content to measure a density from. See docs/tapeout/
# 50-bnd-and-logo-checks.md Part A.2.
SPARSE_DENSITY_PREFIXES = ("AP.DN.1",)

STRUCTURALLY_UNMEASURABLE_PREFIXES = ABSENT_GEOMETRY_PREFIXES + SPARSE_DENSITY_PREFIXES

DEFAULT_WAIVERS = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
    "ASIC", "genus-innovus", "scripts", "calibre", "bnd_waivers.yaml")


def load_waivers(path):
    """Identical contract to drc_census.py's load_waivers -- see there for why
    each branch is shaped this way. Kept as a literal copy rather than an
    import; see the module docstring for why."""
    if not os.path.exists(path):
        return [], []
    try:
        import yaml
    except ImportError:
        return [], [f"{path} exists but PyYAML is not installed, so its waivers "
                    f"cannot be read. Install pyyaml or pass --no-waivers "
                    f"deliberately."]
    try:
        with open(path) as fh:
            doc = yaml.safe_load(fh) or {}
    except Exception as e:                                   # noqa: BLE001
        return [], [f"{path} is not parseable YAML: {e}"]
    if not isinstance(doc, dict):
        return [], [f"{path} does not parse to a mapping — expected a document "
                    f"with `applies_to:` and `waivers:` at the top level."]

    applies = (doc.get("applies_to") or {}).get("block")
    out, problems = [], []
    for i, w in enumerate(doc.get("waivers") or []):
        where = f"{path} waivers[{i}]"
        check = w.get("check")
        cells = w.get("cells") or {}
        if not check or not isinstance(cells, dict) or not cells:
            problems.append(f"{where}: needs a `check:` and a non-empty `cells:` "
                            f"map. A rule-scoped waiver is not expressible here "
                            f"on purpose.")
            continue
        if not w.get("justification") or not w.get("evidence"):
            problems.append(f"{where} ({check}): no `justification:`/`evidence:`. "
                            f"A waiver without a stated, checkable reason is the "
                            f"thing this file exists to prevent.")
            continue
        bad = {c: n for c, n in cells.items() if not isinstance(n, int) or n < 0}
        if bad:
            problems.append(f"{where} ({check}): expected counts must be "
                            f"non-negative integers: {bad}")
            continue
        out.append({"id": w.get("id") or check, "check": check,
                    "cells": dict(cells), "block": applies,
                    "expect_total": w.get("expect_total")})
    return out, problems


def apply_waivers(waivers, by_cell, checks, primary):
    """Identical contract/guarantee to drc_census.py: a waiver may never name
    the layout primary cell, whatever the yaml says -- enforced here, not by
    convention. See that script for the full rationale of each branch."""
    waived_total, rows, problems = 0, [], []
    for w in waivers:
        check, want = w["check"], w["cells"]
        if w.get("block") and w["block"] != primary:
            rows.append({"id": w["id"], "check": check, "waived": 0,
                         "dormant": False, "miss": [], "drift": {},
                         "uncovered": {c: n for c, n in
                                       ((c, r.get(check, 0)) for c, r
                                        in by_cell.items()) if n},
                         "cells": 0,
                         "n_a": f"declared for {w['block']}, this run is {primary}"})
            continue
        run_total = checks.get(check, 0)
        got = {c: r.get(check, 0) for c, r in by_cell.items() if r.get(check, 0)}

        for cell in sorted(want):
            if cell == primary:
                problems.append(
                    f"waiver {w['id']}: refuses to waive {check} in the layout "
                    f"primary cell {primary!r}. Results attributed to the top "
                    f"cell are OUR geometry; they are never waivable here.")
        hit = {c: n for c, n in want.items() if c != primary and got.get(c, 0)}
        miss = [c for c in sorted(want) if c != primary and not got.get(c, 0)]
        drift = {c: (want[c], got[c]) for c in hit if got[c] != want[c]}

        n = sum(got[c] for c in hit)
        waived_total += n
        uncovered = {c: v for c, v in got.items() if c not in want}
        rows.append({"id": w["id"], "check": check, "waived": n,
                     "dormant": run_total == 0, "miss": miss, "drift": drift,
                     "uncovered": uncovered, "cells": len(hit)})

        if run_total == 0:
            continue
        if miss:
            problems.append(
                f"waiver {w['id']}: {check} produced {run_total} results in this "
                f"run, but these waived cells matched NOTHING: "
                f"{', '.join(miss)}. Fix the file; do not widen it.")
        if drift:
            d = ", ".join(f"{c} expected {e} got {g}" for c, (e, g) in
                          sorted(drift.items()))
            problems.append(
                f"waiver {w['id']} ({check}): waived counts MOVED -- {d}. "
                f"Re-establish it before updating the expected count.")
        if w["expect_total"] is not None and n != w["expect_total"]:
            problems.append(
                f"waiver {w['id']} ({check}): waived {n}, file says "
                f"expect_total {w['expect_total']}.")
    return waived_total, rows, problems


def owner(cell, primary):
    if cell == primary:
        return DESIGN
    if cell.startswith(IOPAD_PREFIXES):
        return IOPAD
    return DESIGN


def parse_summary(path):
    """Same Calibre summary grammar as drc_census.py's parse_summary -- BND
    and DRC summaries are the same file format, different rule namespace."""
    txt = open(path, errors="replace").read()

    m = re.search(r"^Layout Primary Cell:\s*(\S+)", txt, re.M)
    primary = m.group(1) if m else ""
    m = re.search(r"^Maximum Results/RuleCheck:\s*(\d+)", txt, re.M)
    cap = int(m.group(1)) if m else None

    split = re.search(r"RULECHECK RESULTS STATISTICS\s*\(BY CELL\)", txt)
    main_txt = txt[: split.start()] if split else txt
    cell_txt = txt[split.start():] if split else ""

    line_re = re.compile(
        r"^\s*RULECHECK\s+(\S+)\s*\.*\s*TOTAL Result Count\s*=\s*(\d+)", re.M)
    checks = {c: int(n) for c, n in line_re.findall(main_txt)}

    estimates = re.findall(r"^.*[Ee]stimated.*$", txt, re.M)

    by_cell = {}
    cur = None
    for ln in cell_txt.splitlines():
        mc = re.match(r"^CELL\s+(\S+)\s*\.*\s*TOTAL Result Count\s*=\s*(\d+)", ln)
        if mc:
            cur = mc.group(1)
            by_cell.setdefault(cur, {})
            continue
        mr = re.match(
            r"^\s+RULECHECK\s+(\S+)\s*\.*\s*TOTAL Result Count\s*=\s*(\d+)", ln)
        if mr and cur:
            by_cell[cur][mr.group(1)] = int(mr.group(2))
    return primary, cap, checks, by_cell, estimates


def _matches(check, prefixes):
    return any(check == p or check.startswith(p) for p in prefixes)


def is_absent_geometry(check):
    return _matches(check, ABSENT_GEOMETRY_PREFIXES)


def is_sparse_density(check):
    return _matches(check, SPARSE_DENSITY_PREFIXES)


def is_unmeasurable(check):
    return is_absent_geometry(check) or is_sparse_density(check)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("rundir")
    ap.add_argument("--budget", type=int,
                    default=int(os.environ.get("BND_DESIGN_BUDGET", "0")))
    ap.add_argument("--waivers",
                    default=os.environ.get("BND_WAIVERS", DEFAULT_WAIVERS),
                    help="cell-scoped waiver file (default: %(default)s)")
    ap.add_argument("--no-waivers", action="store_true",
                    help="count every result, waived or not.")
    a = ap.parse_args()

    rundir = a.rundir
    if not os.path.isdir(rundir):
        print(f"FAIL: no BND run directory at {rundir} — Calibre did not run")
        return 1
    cands = sorted(glob.glob(os.path.join(rundir, "*.bnd.summary")))
    if not cands:
        print(f"FAIL: no *.bnd.summary in {rundir} — Calibre produced no result.")
        return 1
    summary = cands[0]

    primary, cap, checks, by_cell, estimates = parse_summary(summary)
    if not checks:
        print(f"FAIL: {summary} parsed to zero rulechecks — truncated or not a "
              f"Calibre summary")
        return 1

    nonzero = {c: n for c, n in checks.items() if n > 0}
    total = sum(nonzero.values())
    saturated = sorted(c for c, n in nonzero.items() if cap and n >= cap)

    absent_checks = sorted(c for c in checks if is_absent_geometry(c))
    sparse_checks = sorted(c for c in checks if is_sparse_density(c))
    unmeasurable = sorted(absent_checks + sparse_checks)
    # Only the ABSENT-geometry half can be an anomaly: it is expected to be
    # exactly zero, so nonzero is a surprise worth stopping for. The SPARSE
    # half (AP.DN.1) is never trustworthy in either direction on a
    # thin-AP-content stream, so it is excluded here, not flagged.
    unmeasurable_nonzero = [c for c in absent_checks if checks.get(c, 0) > 0]
    sparse_nonzero = [c for c in sparse_checks if checks.get(c, 0) > 0]

    # Sparse-density results are excluded from the owner split entirely --
    # same reasoning drc_census.py uses to pull front-end (OD/PO) density out
    # of its gated total: a count that is not trustworthy in either direction
    # must not silently count toward a budget either way.
    buckets = {DESIGN: 0, IOPAD: 0}
    for cell, rules in by_cell.items():
        gated_sum = sum(n for chk, n in rules.items() if not is_sparse_density(chk))
        buckets[owner(cell, primary)] += gated_sum
    attributed = sum(buckets.values()) + sum(checks.get(c, 0) for c in sparse_nonzero)

    if a.no_waivers:
        waivers, wv_problems, waived, wv_rows = [], [], 0, []
    else:
        waivers, wv_problems = load_waivers(a.waivers)
        waived, wv_rows, apply_problems = apply_waivers(
            waivers, by_cell, checks, primary)
        wv_problems += apply_problems

    print(f"summary        : {summary}")
    print(f"primary cell   : {primary}")
    print(f"result cap     : {cap}")
    print(f"rulechecks >0  : {len(nonzero)}")
    print(f"TOTAL results  : {total}   (raw, exactly what Calibre reported)")
    if waived:
        print(f"  less waived  : {waived}")
        print(f"  REPORTED     : {total - waived}   <- the number to work from")
    elif not a.no_waivers and waivers:
        print(f"  waived       : 0 — every waiver in {a.waivers} is dormant")
    print()
    if wv_rows:
        print(f"waivers ({a.waivers}):")
        for r in wv_rows:
            if r.get("n_a"):
                state = f"NOT APPLICABLE — {r['n_a']}"
            elif r["dormant"]:
                state = "DORMANT (check absent from this run)"
            else:
                state = f"{r['waived']} results across {r['cells']} cells"
            print(f"  {r['id']:<28} {r['check']:<22} {state}")
            if r["miss"]:
                print(f"    STALE, matched nothing: {', '.join(r['miss'])}")
            if r["drift"]:
                print("    DRIFT: " + ", ".join(
                    f"{c} {e}->{g}" for c, (e, g) in sorted(r["drift"].items())))
            if r["uncovered"]:
                print("    NOT waived (no entry — counted above): " + ", ".join(
                    f"{c}={n}" for c, n in sorted(r["uncovered"].items())))
        print()
    print("owner split (by owning cell, from the summary's BY CELL section):")
    for k in (DESIGN, IOPAD):
        print(f"  {k:<16} {buckets[k]}")
    if attributed != total:
        print(f"  NOTE: BY CELL sums to {attributed}, main section to {total}")
    print()
    print(f"structurally unmeasurable in a local, un-merged run "
          f"({len(unmeasurable)} rulechecks: PM.*/CB.*/CBVIA*.*/CBM*.*/"
          f"CUPCB.*/CUPVIAT.*/RV.*/AP.S.4 — this stream carries no PM/CB/"
          f"CB2/seal-ring geometry, docs/tapeout/50-bnd-and-logo-checks.md "
          f"Part A):")
    if unmeasurable_nonzero:
        print(f"  ANOMALY: {len(unmeasurable_nonzero)} of them are NONZERO — "
              f"this run is NOT the geometry-absent case this bucket assumes:")
        for c in unmeasurable_nonzero:
            print(f"    {c:<28} {checks[c]}")
    else:
        print(f"  all {len(absent_checks)} absent-geometry checks read 0, "
              f"consistent with absent PM/CB/seal-ring geometry. Read this as "
              f"UNMEASURED, not CLEAN — a full-library-merge stream could "
              f"make any of them fire for the first time (docs/tapeout/"
              f"48-imec-signoff-results-analysis.md).")
    if sparse_nonzero:
        print(f"  {len(sparse_nonzero)} SPARSE-density result(s), reported not "
              f"gated (thin AP content, neither a zero nor a nonzero here is "
              f"trustworthy — docs/tapeout/50-bnd-and-logo-checks.md Part A.2):")
        for c in sparse_nonzero:
            print(f"    {c:<28} {checks[c]}")
    print()
    per_check_waived = {}
    for r in wv_rows:
        per_check_waived[r["check"]] = per_check_waived.get(r["check"], 0) + r["waived"]
    ranked = {c: n - per_check_waived.get(c, 0) for c, n in nonzero.items()}
    ranked = {c: n for c, n in ranked.items() if n > 0}
    print("rulechecks, waived results excluded (raw in brackets):")
    for c, n in sorted(ranked.items(), key=lambda kv: -kv[1]):
        mark = f"   [raw {nonzero[c]}, {per_check_waived[c]} waived]" \
            if per_check_waived.get(c) else ""
        print(f"  {c:<28} {n}{mark}")
    gone = sorted(c for c in nonzero if c not in ranked)
    if gone:
        print(f"  (fully waived, 0 remaining: {', '.join(gone)})")

    rc = 0
    if wv_problems:
        print()
        print(f"FAIL: {len(wv_problems)} waiver problem(s):")
        for p in wv_problems:
            print(f"  * {p}")
        rc = 1
    if saturated:
        print()
        print(f"FAIL: {len(saturated)} rulecheck(s) SATURATED the {cap}-result "
              f"cap, so their true counts are unknown: {', '.join(saturated[:10])}")
        rc = 1
    if unmeasurable_nonzero:
        print()
        print(f"FAIL: {len(unmeasurable_nonzero)} rulecheck(s) presumed "
              f"structurally-unmeasurable are actually nonzero — the geometry "
              f"assumption behind that bucket no longer holds for this run; "
              f"re-classify before trusting this report.")
        rc = 1
    # No waiver may ever cover the primary cell (enforced in apply_waivers),
    # so buckets[DESIGN] is already the true, un-waivable design-owned count.
    if buckets[DESIGN] > a.budget:
        print()
        print(f"FAIL: {buckets[DESIGN]} design-owned results > budget "
              f"{a.budget}.")
        rc = 1
    if rc == 0:
        print()
        print(f"PASS: design-owned results {buckets[DESIGN]} <= {a.budget}, "
              f"no check saturated, no unmeasurable-bucket anomaly.")
        print(f"      {buckets[IOPAD]} io-pad-abstract results remain, "
              f"reported not gated (vendor pad/corner/seal-ring cell content).")
        if waived:
            print(f"      {waived} of those are WAIVED and excluded above; "
                  f"Calibre still reported all {total}.")
    return rc


if __name__ == "__main__":
    sys.exit(main())
