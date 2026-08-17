#!/usr/bin/env python3
"""
Signoff-STA gate for nanosoc_eth_chiplet_pads.

WHY THIS EXISTS IN THIS SHAPE
-----------------------------
Four gates were found on this project that could not fail. The failure modes
were all the same family:

  * the gate checked internal consistency and never checked COVERAGE, so it
    read 20/20 green while 16 of 33 clocks were never analysed at all;
  * the budget was set to whatever the day's number happened to be, so the
    gate could only ever confirm the present;
  * an unparseable or missing report was treated as "nothing to complain
    about" rather than as a failure.

So this gate is built to the opposite rules, and they are enforced by
`--selftest`, which mutates a known-good artefact set one property at a time
and asserts the gate rejects every mutant. A gate that has not been shown to
fail has not been shown to do anything.

RULES
  R1  Missing, empty or unparseable evidence is a FAILURE, never a pass.
  R2  Budgets come from an explicit, committed policy (--policy), never from
      the run being judged. A budget equal to the measured value is itself
      reported, because that is the signature of a budget back-fitted to the
      day's number.
  R3  Coverage is checked separately from quality. "All analysed paths pass"
      is worthless if half the design was not analysed.
  R4  The tool's exit code is never consulted. Only artefacts.

USAGE
  sta_gate.py --reports ASIC/sta/reports [--policy ASIC/sta/sta_policy.json]
  sta_gate.py --selftest
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

# ---------------------------------------------------------------------------
# Policy defaults.
#
# These are ACCEPTANCE THRESHOLDS, not observations. They are deliberately set
# to what a signed-off chip must satisfy (zero failing endpoints), NOT to the
# design's current state (setup FEP ~1429-1444). The gate is therefore
# expected to FAIL on today's design, and that is correct behaviour: the
# design does not close timing. A gate tuned to pass today would be the fifth
# gate that cannot discriminate.
# ---------------------------------------------------------------------------
DEFAULT_POLICY = {
    "setup_fep_budget": 0,
    "hold_fep_budget": 0,
    "expected_clock_count": 33,
    "require_qrc_all_rc_corners": True,
    "require_spef_min_bytes": 1_000_000,
    "require_cppr": "both",
    "require_analysis_type": "ocv",
    "require_derate": {
        "derate_data_early": 0.95,
        "derate_data_late": 1.05,
        "derate_clk_early": 0.97,
        "derate_clk_late": 1.03,
    },
    # Signing off on one setup corner and one hold corner is a decision, not a
    # default. Named here so that if the view set silently shrinks, the gate
    # notices. Empty list disables the check.
    "required_setup_views": ["default_analysis_view_setup"],
    "required_hold_views": ["default_analysis_view_hold"],
}


class Result:
    def __init__(self):
        self.failures = []
        self.warnings = []
        self.facts = {}

    def fail(self, code, msg):
        self.failures.append((code, msg))

    def warn(self, code, msg):
        self.warnings.append((code, msg))

    def fact(self, k, v):
        self.facts[k] = v

    @property
    def ok(self):
        return not self.failures


def parse_manifest(path, r):
    """Manifest is `key = value` per line. Missing file is fatal (R1)."""
    if not os.path.isfile(path):
        r.fail("MANIFEST_MISSING", f"no manifest at {path}")
        return {}
    m = {}
    with open(path, errors="replace") as fh:
        for line in fh:
            if "=" not in line:
                continue
            k, _, v = line.partition("=")
            m[k.strip()] = v.strip()
    if not m:
        r.fail("MANIFEST_EMPTY", f"manifest parsed to zero keys: {path}")
    return m


# Matches the "View : ALL   -0.715  -354.123  1429" summary rows that Innovus
# and Tempus both emit, and the "WNS (ns): / Violating Paths:" table form.
_ROW = re.compile(
    r"^\s*View\s*:\s*(?P<view>\S+)\s+"
    r"(?P<wns>-?\d+\.\d+)\s+(?P<tns>-?\d+\.\d+)\s+(?P<fep>\d+)\s*$"
)


def parse_timing_summary(path, r):
    """
    Return {'setup': (wns,fep), 'hold': (wns,fep)} or {} on failure.

    Unparseable is a FAILURE (R1). This is the exact spot where a gate can
    quietly become a no-op: if the report format shifts by one column and the
    regex stops matching, "no violations found" and "no data found" look
    identical unless you insist on positive evidence.
    """
    if not os.path.isfile(path):
        r.fail("SUMMARY_MISSING", f"no timing summary at {path}")
        return {}
    text = open(path, errors="replace").read()
    if not text.strip():
        r.fail("SUMMARY_EMPTY", f"timing summary is empty: {path}")
        return {}

    out = {}
    section = None
    for line in text.splitlines():
        s = line.strip()
        up = s.upper()
        if up.startswith("# SETUP") or up.startswith("SETUP MODE"):
            section = "setup"
            continue
        if up.startswith("# HOLD") or up.startswith("HOLD MODE"):
            section = "hold"
            continue
        if up.startswith("# DRV"):
            section = "drv"
            continue
        if section in ("setup", "hold"):
            mo = _ROW.match(line)
            if mo and mo.group("view").upper() == "ALL":
                out[section] = (float(mo.group("wns")), int(mo.group("fep")))

    for want in ("setup", "hold"):
        if want not in out:
            r.fail(
                "SUMMARY_UNPARSED",
                f"could not extract a '{want}' View:ALL row from {path}. "
                "Refusing to treat an unreadable report as a clean one.",
            )
    return out


def parse_analysis_coverage(path, r):
    """
    Tempus report_analysis_coverage: counts of Met / Violated / Untested
    checks. 'Untested' is the number that matters here — it is the direct
    measurement of the coverage hole that the in-flow gates cannot see.
    """
    if not os.path.isfile(path):
        r.fail("COVERAGE_MISSING", f"no analysis coverage report at {path}")
        return None
    text = open(path, errors="replace").read()
    if not text.strip():
        r.fail("COVERAGE_EMPTY", f"analysis coverage report is empty: {path}")
        return None

    # Tempus emits a per-check-type TABLE, not a single total:
    #
    #   Check Type            No. of   Met          Violated     Untested
    #                         Checks
    #   ClockPeriod           42       4 (9%)       0 (0%)       38 (90%)
    #   DataCheckSetup        69       0 (0%)       0 (0%)       69 (100%)
    #
    # so the untested figure is the SUM of the last column. An earlier version
    # of this parser looked for a single "Untested <n>" and matched the header
    # word instead, which would have reported 0 untested on a report showing
    # ~57,800. Sum the rows, and require at least one row to have parsed.
    row = re.compile(
        r"^\s*(?P<name>[A-Za-z][A-Za-z0-9 ()_\-]*?)\s{2,}"
        r"(?P<n>\d+)\s+"
        r"(?P<met>\d+)\s*\(\s*\d+%\s*\)\s+"
        r"(?P<vio>\d+)\s*\(\s*\d+%\s*\)\s+"
        r"(?P<unt>\d+)\s*\(\s*\d+%\s*\)\s*$"
    )
    total_unt = 0
    rows = 0
    per_type = {}
    for line in text.splitlines():
        mo = row.match(line)
        if not mo:
            continue
        rows += 1
        u = int(mo.group("unt"))
        total_unt += u
        if u:
            per_type[mo.group("name").strip()] = (u, int(mo.group("n")))

    if rows == 0:
        r.fail(
            "COVERAGE_UNPARSED",
            f"parsed zero check-type rows from {path}. A coverage report that "
            "cannot be read is not evidence of coverage.",
        )
        return None

    if per_type:
        worst = sorted(per_type.items(), key=lambda kv: -kv[1][0])[:4]
        r.fact("untested_by_type", ", ".join(f"{k}={v[0]}/{v[1]}" for k, v in worst))
    r.fact("coverage_rows", rows)
    return total_unt


def check(reports_dir, policy, r):
    man_path = os.path.join(reports_dir, "sta_manifest.txt")
    man = parse_manifest(man_path, r)

    # --- run actually completed -------------------------------------------
    if man and "sta_finished" not in man:
        r.fail(
            "RUN_INCOMPLETE",
            "manifest has no sta_finished key: the STA run did not reach the "
            "end. Partial reports must not be read as results.",
        )
    for k, v in man.items():
        if k.startswith("step.") and v == "FAILED":
            r.fail("STEP_FAILED", f"{k} = FAILED ({man.get(k + '.error', '?')})")
        if k == "fatal":
            r.fail("RUN_FATAL", v)

    # --- analysis mode ----------------------------------------------------
    if policy.get("require_cppr"):
        got = man.get("timing_analysis_cppr")
        if got != policy["require_cppr"]:
            r.fail("CPPR", f"timing_analysis_cppr = {got!r}, require {policy['require_cppr']!r}")
    if policy.get("require_analysis_type"):
        got = man.get("timing_analysis_type")
        if got != policy["require_analysis_type"]:
            r.fail("ANALYSIS_TYPE", f"timing_analysis_type = {got!r}, require {policy['require_analysis_type']!r}")

    # --- derate re-issued -------------------------------------------------
    # Not "is a derate set somewhere" but "is THIS derate set", because the
    # routed DB persists derate for typical_delay_corner only and inheriting
    # it silently drops OCV from both signoff corners.
    for key, want in (policy.get("require_derate") or {}).items():
        raw = man.get(key)
        if raw is None:
            r.fail("DERATE_MISSING", f"manifest has no {key}: OCV derate was not re-issued")
            continue
        try:
            got = float(raw)
        except ValueError:
            r.fail("DERATE_UNPARSED", f"{key} = {raw!r} is not a number")
            continue
        if abs(got - float(want)) > 1e-9:
            r.fail("DERATE_VALUE", f"{key} = {got}, require {want}")

    # --- extraction quality ----------------------------------------------
    if policy.get("require_qrc_all_rc_corners"):
        qrc_keys = {k: v for k, v in man.items() if k.startswith("extract.qrc_set.")}
        if not qrc_keys:
            r.fail("QRC_NO_EVIDENCE", "manifest records no extract.qrc_set.* keys")
        for k, v in sorted(qrc_keys.items()):
            if v != "yes":
                r.fail("QRC_MISSING", f"{k} = {v}: RC corner has no QRC deck, extraction is cap-table only")

    # --- SPEF actually written -------------------------------------------
    min_bytes = policy.get("require_spef_min_bytes", 0)
    if min_bytes:
        spef_keys = {k: v for k, v in man.items() if k.startswith("spef.") and k.endswith(".bytes")}
        if not spef_keys:
            if man.get("step.extract_parasitics") == "skipped_by_request":
                r.warn("SPEF_SKIPPED", "extraction skipped by request; SPEF not checked")
            else:
                r.fail("SPEF_NONE", "no SPEF was written for any RC corner")
        for k, v in sorted(spef_keys.items()):
            try:
                n = int(v)
            except ValueError:
                r.fail("SPEF_UNPARSED", f"{k} = {v!r}")
                continue
            if n < min_bytes:
                r.fail("SPEF_TOO_SMALL", f"{k} = {n} bytes, require >= {min_bytes}. A truncated SPEF times as an optimistic design.")

    # --- clock coverage ---------------------------------------------------
    want_clocks = policy.get("expected_clock_count")
    if want_clocks:
        raw = man.get("clock_count")
        if raw is None:
            r.fail("CLOCKS_MISSING", "manifest has no clock_count")
        else:
            try:
                got = int(raw)
            except ValueError:
                r.fail("CLOCKS_UNPARSED", f"clock_count = {raw!r}")
                got = None
            if got is not None:
                r.fact("clock_count", got)
                if got != want_clocks:
                    r.fail("CLOCK_COUNT", f"clock_count = {got}, expected {want_clocks}. A clock that vanished between P&R and STA is a whole timing domain nobody is checking.")

    # --- view set has not silently shrunk ---------------------------------
    for role, key in (("setup", "required_setup_views"), ("hold", "required_hold_views")):
        want = policy.get(key) or []
        if not want:
            continue
        raw = man.get(f"analysis_views_{role}")
        if raw is None:
            r.fail("VIEWS_MISSING", f"manifest has no analysis_views_{role}")
            continue
        got = [x for x in raw.split(",") if x]
        r.fact(f"views_{role}", got)
        for v in want:
            if v not in got:
                r.fail("VIEW_ABSENT", f"required {role} view {v!r} not active (active: {got})")

    # --- coverage ---------------------------------------------------------
    untested = parse_analysis_coverage(os.path.join(reports_dir, "analysis_coverage.rpt"), r)
    if untested is not None:
        r.fact("untested_checks", untested)
        if untested > 0:
            r.fail("UNTESTED_CHECKS", f"{untested} timing checks are UNTESTED. These are endpoints the analysis never evaluated; they cannot be assumed to pass.")

    # --- quality ----------------------------------------------------------
    summary = parse_timing_summary(os.path.join(reports_dir, "timing_summary.rpt"), r)
    for mode, bkey in (("setup", "setup_fep_budget"), ("hold", "hold_fep_budget")):
        if mode not in summary:
            continue
        wns, fep = summary[mode]
        r.fact(f"{mode}_wns", wns)
        r.fact(f"{mode}_fep", fep)
        budget = policy.get(bkey)
        if budget is None:
            continue
        if fep > budget:
            r.fail(f"{mode.upper()}_FEP", f"{mode} FEP {fep} > budget {budget} (WNS {wns})")
        # R2: a budget that exactly equals the measured value is the
        # signature of a threshold back-fitted to the day's number.
        if budget != 0 and fep == budget:
            r.warn("BUDGET_BACKFITTED", f"{bkey} ({budget}) exactly equals the measured {mode} FEP. A budget set to the day's number cannot detect a regression.")

    return r


def emit(r, fmt="text"):
    if fmt == "json":
        print(json.dumps({
            "pass": r.ok,
            "failures": [{"code": c, "message": m} for c, m in r.failures],
            "warnings": [{"code": c, "message": m} for c, m in r.warnings],
            "facts": r.facts,
        }, indent=2))
        return
    if r.facts:
        print("MEASURED")
        for k, v in r.facts.items():
            print(f"  {k:24s} {v}")
        print()
    for c, m in r.warnings:
        print(f"WARN  [{c}] {m}")
    for c, m in r.failures:
        print(f"FAIL  [{c}] {m}")
    print()
    print("GATE: PASS" if r.ok else f"GATE: FAIL ({len(r.failures)} failure(s))")


# ---------------------------------------------------------------------------
# SELF-TEST — the part that proves this gate can fail.
# ---------------------------------------------------------------------------
GOOD_MANIFEST = """\
sta_tool = tempus
sta_db = /somewhere/nanosoc_eth_chiplet_pads_routed
step.read_db = ok
step.extract_parasitics = ok
design_name = nanosoc_eth_chiplet_pads
clock_count = 33
analysis_views_setup = default_analysis_view_setup
analysis_views_hold = default_analysis_view_hold
timing_analysis_type = ocv
timing_analysis_cppr = both
derate_data_early = 0.95
derate_data_late = 1.05
derate_clk_early = 0.97
derate_clk_late = 1.03
extract.qrc_set.default_rc_corner_worst = yes
extract.qrc_set.default_rc_corner_best = yes
extract.qrc_set.default_rc_corner_typical = yes
spef.default_rc_corner_worst.bytes = 250000000
spef.default_rc_corner_best.bytes = 250000000
spef.default_rc_corner_typical.bytes = 250000000
sta_finished = 2026-08-18T02:00:00
"""

GOOD_SUMMARY = """\
# SETUP                   WNS       TNS   FEP
 View : ALL             0.012     0.000     0
# HOLD                    WNS     TNS   FEP
 View : ALL             0.004    0.000     0
"""

# Verbatim column layout of a real Tempus 21.11 report_analysis_coverage,
# with the untested column zeroed. Pinning the REAL format here means a
# future format drift breaks the selftest rather than silently turning the
# coverage check into a no-op.
GOOD_COVERAGE = """\
    -------------------------------------------------------------------------------------------
                                   TIMING CHECK COVERAGE SUMMARY
    -------------------------------------------------------------------------------------------
     Check Type                      No. of   Met              Violated         Untested
                                     Checks
    -------------------------------------------------------------------------------------------
    Clock Gating Setup             2         2 (100%)         0 (0%)           0 (0%)
    ClockPeriod                    42        42 (100%)        0 (0%)           0 (0%)
    Recovery                       43399     43399 (100%)     0 (0%)           0 (0%)
    Setup                          68318     68318 (100%)     0 (0%)           0 (0%)
    -------------------------------------------------------------------------------------------
"""

# The real thing, as measured on nanosoc_eth_chiplet_pads 2026-08-17.
MEASURED_COVERAGE = """\
     Check Type                      No. of   Met              Violated         Untested
                                     Checks
    Clock Gating Setup             2         2 (100%)         0 (0%)           0 (0%)
    ClockPeriod                    42        4 (9%)           0 (0%)           38 (90%)
    DataCheckSetup                 69        0 (0%)           0 (0%)           69 (100%)
    ExternalDelay (Late)           15        7 (46%)          0 (0%)           8 (53%)
    Library Clock Gating Setup     6004      2961 (49%)       41 (0%)          3002 (50%)
    PulseWidth                     169686    120151 (70%)     0 (0%)           49535 (29%)
    Recovery                       43399     40558 (93%)      0 (0%)           2841 (6%)
    Setup                          68318     65598 (96%)      421 (0%)         2299 (3%)
    TimeBorrow                     1         1 (100%)         0 (0%)           0 (0%)
"""


def _mk(tmp, manifest=GOOD_MANIFEST, summary=GOOD_SUMMARY, coverage=GOOD_COVERAGE):
    d = tempfile.mkdtemp(dir=tmp)
    with open(os.path.join(d, "sta_manifest.txt"), "w") as fh:
        fh.write(manifest)
    if summary is not None:
        with open(os.path.join(d, "timing_summary.rpt"), "w") as fh:
            fh.write(summary)
    if coverage is not None:
        with open(os.path.join(d, "analysis_coverage.rpt"), "w") as fh:
            fh.write(coverage)
    return d


def selftest():
    """
    Mutation test. Each case perturbs exactly one property of a known-good
    artefact set and asserts the gate rejects it with the expected code.
    If the baseline does not PASS, or any mutant does not FAIL, the gate is
    broken and this returns non-zero.
    """
    tmp = tempfile.mkdtemp(prefix="sta_gate_selftest_")
    passed = failed = 0
    try:
        # Baseline must PASS — otherwise every later "FAIL" is meaningless,
        # because a gate that fails everything is as useless as one that
        # passes everything.
        r = check(_mk(tmp), dict(DEFAULT_POLICY), Result())
        if r.ok:
            print("ok    baseline PASSES")
            passed += 1
        else:
            print(f"BROKEN baseline FAILS: {r.failures}")
            failed += 1

        cases = [
            ("missing manifest", dict(manifest=None), "MANIFEST_MISSING"),
            ("empty manifest", dict(manifest="\n\n"), "MANIFEST_EMPTY"),
            ("run did not finish",
             dict(manifest=GOOD_MANIFEST.replace("sta_finished = 2026-08-18T02:00:00", "")),
             "RUN_INCOMPLETE"),
            ("a step failed",
             dict(manifest=GOOD_MANIFEST.replace("step.read_db = ok", "step.read_db = FAILED")),
             "STEP_FAILED"),
            ("CPPR off",
             dict(manifest=GOOD_MANIFEST.replace("timing_analysis_cppr = both", "timing_analysis_cppr = none")),
             "CPPR"),
            ("analysis type not ocv",
             dict(manifest=GOOD_MANIFEST.replace("timing_analysis_type = ocv", "timing_analysis_type = single")),
             "ANALYSIS_TYPE"),
            ("derate not re-issued (the read_db trap)",
             dict(manifest=GOOD_MANIFEST.replace("derate_clk_late = 1.03", "")),
             "DERATE_MISSING"),
            ("derate silently weakened",
             dict(manifest=GOOD_MANIFEST.replace("derate_data_late = 1.05", "derate_data_late = 1.00")),
             "DERATE_VALUE"),
            ("an RC corner lost its QRC deck",
             dict(manifest=GOOD_MANIFEST.replace(
                 "extract.qrc_set.default_rc_corner_worst = yes",
                 "extract.qrc_set.default_rc_corner_worst = no")),
             "QRC_MISSING"),
            ("SPEF truncated",
             dict(manifest=GOOD_MANIFEST.replace(
                 "spef.default_rc_corner_worst.bytes = 250000000",
                 "spef.default_rc_corner_worst.bytes = 412")),
             "SPEF_TOO_SMALL"),
            ("clocks vanished between P&R and STA",
             dict(manifest=GOOD_MANIFEST.replace("clock_count = 33", "clock_count = 17")),
             "CLOCK_COUNT"),
            ("setup view silently dropped",
             dict(manifest=GOOD_MANIFEST.replace(
                 "analysis_views_setup = default_analysis_view_setup",
                 "analysis_views_setup = typical_analysis_view")),
             "VIEW_ABSENT"),
            ("untested checks present (the real measured coverage hole)",
             dict(coverage=MEASURED_COVERAGE), "UNTESTED_CHECKS"),
            ("a single check type goes untested",
             dict(coverage=GOOD_COVERAGE.replace(
                 "ClockPeriod                    42        42 (100%)        0 (0%)           0 (0%)",
                 "ClockPeriod                    42        4 (9%)           0 (0%)           38 (90%)")),
             "UNTESTED_CHECKS"),
            ("coverage report missing", dict(coverage=None), "COVERAGE_MISSING"),
            ("coverage report unreadable",
             dict(coverage="Analysis Coverage Report\n  (no data)\n"),
             "COVERAGE_UNPARSED"),
            ("coverage table format drifts (columns change)",
             dict(coverage=GOOD_COVERAGE.replace("(100%)", "pct100")),
             "COVERAGE_UNPARSED"),
            ("timing summary missing", dict(summary=None), "SUMMARY_MISSING"),
            ("timing summary format drifted",
             dict(summary="# SETUP\n  something something 0\n# HOLD\n  nothing\n"),
             "SUMMARY_UNPARSED"),
            ("setup does not close",
             dict(summary=GOOD_SUMMARY.replace(
                 " View : ALL             0.012     0.000     0",
                 " View : ALL            -0.759  -309.637  1444")),
             "SETUP_FEP"),
            ("hold does not close",
             dict(summary=GOOD_SUMMARY.replace(
                 " View : ALL             0.004    0.000     0",
                 " View : ALL            -0.021   -0.070    11")),
             "HOLD_FEP"),
        ]

        for name, kw, want_code in cases:
            kw2 = dict(kw)
            if kw2.get("manifest") is None and "manifest" in kw2:
                d = tempfile.mkdtemp(dir=tmp)  # no manifest at all
                if kw2.get("summary", GOOD_SUMMARY) is not None:
                    open(os.path.join(d, "timing_summary.rpt"), "w").write(GOOD_SUMMARY)
                if kw2.get("coverage", GOOD_COVERAGE) is not None:
                    open(os.path.join(d, "analysis_coverage.rpt"), "w").write(GOOD_COVERAGE)
            else:
                d = _mk(tmp, **kw2)
            rr = check(d, dict(DEFAULT_POLICY), Result())
            codes = [c for c, _ in rr.failures]
            if rr.ok:
                print(f"BROKEN {name!r}: gate PASSED a mutant it must reject")
                failed += 1
            elif want_code not in codes:
                print(f"BROKEN {name!r}: failed but with {codes}, expected {want_code}")
                failed += 1
            else:
                print(f"ok    rejects: {name}  [{want_code}]")
                passed += 1
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    print(f"\nSELFTEST: {passed} passed, {failed} broken")
    return 0 if failed == 0 else 1


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--reports", help="directory holding sta_manifest.txt and the reports")
    ap.add_argument("--policy", help="JSON file overriding the acceptance thresholds")
    ap.add_argument("--format", choices=("text", "json"), default="text")
    ap.add_argument("--selftest", action="store_true", help="mutation-test the gate itself")
    args = ap.parse_args()

    if args.selftest:
        return selftest()

    if not args.reports:
        ap.error("--reports is required (or use --selftest)")

    policy = dict(DEFAULT_POLICY)
    if args.policy:
        if not os.path.isfile(args.policy):
            print(f"FAIL [POLICY_MISSING] no policy file at {args.policy}")
            return 2
        policy.update(json.load(open(args.policy)))

    r = check(args.reports, policy, Result())
    emit(r, args.format)
    return 0 if r.ok else 1


if __name__ == "__main__":
    sys.exit(main())
