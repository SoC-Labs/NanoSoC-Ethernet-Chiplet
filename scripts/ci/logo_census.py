#!/usr/bin/env python3
"""
Census over a `make drc-logo-check` run (docs/tapeout/50-bnd-and-logo-checks.md
Part B) -- the gate-facing sibling to bnd_census.py, reusing its parser and
owner-classification (imported, not copied: this script and bnd_census.py are
both new, unpromoted work, so the "duplicate to protect the promoted gate"
argument in bnd_census.py's docstring does not apply between the two of them).

WHAT THIS REPLACES
-------------------
`make drc-logo-check`'s own Makefile recipe (ASIC/genus-innovus/Makefile,
target `drc-logo-check`) already greps LOGO.S.1/LOGO.R.4/LOGO.O.1 out of the
summary with inline awk and prints PASS/FAIL on the raw (possibly-capped)
count. That is real, but it is (a) awk embedded in a Makefile recipe, not a
tested, importable, `--no-waivers`-style script, and (b) blind to the CAPPED
distinction that matters most: `TOTAL Result Count = 1000 (1199)` and
`= 0 (0)` both look like "not obviously PASS" to a naive grep unless you
specifically read the parenthesised true count, which is exactly the mistake
docs/tapeout/50 Part B and CONVERGENCE_PLAN_2026-08-18.md §8 warn about
("LOGO.S.1 is capped at 1000/1000 ... Calibre's DRC MAXIMUM RESULTS 1000
means the true count for that rule was never measured, only bounded below").

WHAT THIS DOES
---------------
Parses a *.drc.summary from `make drc-logo-check`, reports LOGO.S.1/LOGO.R.4/
LOGO.O.1's TRUE (uncapped) counts, and separately reports the IMEC-only
informational pair IM.LOGO.R.1:WARN / IM.FLOAT.AP -- which this design has NO
local deck for (docs/tapeout/53-gate-promotion-plan.md §4: "custom_drc
(MINIASIC) ... approximated via the main deck + mini@sic header, not the
literal foundry file", and §4's recommendation is explicitly NOT to chase a
literal custom_drc deck). Those two are reported as "no local equivalent",
never silently treated as zero.

THE FULL-MERGE QUESTION THIS SCRIPT CANNOT ANSWER, AND DOES NOT PRETEND TO
----------------------------------------------------------------------------
LOGO_AP_ONLY's real-zero has only ever been measured against LOCAL, un-merged
runs (this design's own routed stream, with or without real pad-ring
content -- neither carries IMEC's real standard-cell/seal-ring library, which
this project structurally does not hold, docs/tapeout/53 §4). Neither IMEC
archive ever checked the AP-only artefact -- both ran the ORIGINAL,
158-marked, full-pictorial logo (CONVERGENCE_PLAN_2026-08-18.md §8 "LOGO --
unchanged, still open"). This script can prove AP-only is a real zero on
whatever local stream you point it at; it CANNOT prove that survives a real
full-library merge, and its own output says so. See
docs/tapeout/50-bnd-and-logo-checks.md Part B.4 for the mechanism argument
(the rule is defined purely against the 158/LOGO marker's bounding box, and
LOGO_AP_ONLY drops that marker; growth measured on the MARKED logo across the
two archives -- LOGO.R.4 true count 1000 -> 1199, +19.9%, via
scripts/ci/imec_rule_diff.py -- cannot apply to a stream with no marker to
grow around) and why that argument, not another local run, is the actual
evidence for the "report, not block" gate decision.

Usage: logo_census.py <drc-logo-check rundir, e.g. calibre_runs/drc_logo_flow>
"""

import glob
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bnd_census import parse_summary        # noqa: E402  (reuse, see docstring)

LOGO_RULES = ("LOGO.S.1", "LOGO.R.4", "LOGO.O.1")
IMEC_ONLY_INFORMATIONAL = ("IM.LOGO.R.1:WARN", "IM.FLOAT.AP")


def true_count(path, rule):
    """The parenthesised TRUE count, not the possibly-capped displayed one --
    the exact distinction the Makefile's inline awk does not make."""
    import re
    txt = open(path, errors="replace").read()
    m = re.search(
        rf"^\s*RULECHECK\s+{re.escape(rule)}\s*\.*\s*TOTAL Result Count\s*=\s*(\d+)\s*\((\d+)\)",
        txt, re.M)
    if not m:
        return None, None
    return int(m.group(1)), int(m.group(2))


def main():
    """Report the LOGO rules' true (uncapped) counts for one drc-logo-check run."""
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <drc-logo-check rundir>")
        return 2
    rundir = sys.argv[1]
    if not os.path.isdir(rundir):
        print(f"FAIL: no run directory at {rundir} — Calibre did not run")
        return 1
    cands = sorted(glob.glob(os.path.join(rundir, "*.drc.summary")))
    if not cands:
        print(f"FAIL: no *.drc.summary in {rundir}")
        return 1
    summary = cands[0]

    primary, cap, checks, by_cell, estimates = parse_summary(summary)
    if not checks:
        print(f"FAIL: {summary} parsed to zero rulechecks")
        return 1

    print(f"summary      : {summary}")
    print(f"primary cell : {primary}")
    print(f"result cap   : {cap}")
    print()
    print("LOGO rules (this design's own deck — real, not approximated):")
    rc = 0
    any_nonzero_true = False
    for rule in LOGO_RULES:
        disp, true_n = true_count(summary, rule)
        if disp is None:
            print(f"  {rule:<20} ABSENT from this summary — rule not in this "
                  f"deck/config, treat as UNKNOWN, not zero")
            continue
        capped = " CAPPED, true count >= this" if disp < true_n else ""
        print(f"  {rule:<20} displayed {disp:>5}   true {true_n:>5}{capped}")
        if true_n > 0:
            any_nonzero_true = True

    print()
    print("informational pair from IMEC's real custom_drc deck — NO LOCAL "
          "EQUIVALENT (docs/tapeout/53-gate-promotion-plan.md §4: not worth "
          "chasing the literal foundry file). Reported for context only, "
          "never gated, never assumed zero locally:")
    for rule in IMEC_ONLY_INFORMATIONAL:
        print(f"  {rule:<20} not measurable locally — see IMEC archive "
              f"reports directly (scripts/ci/imec_rule_diff.py)")

    print()
    if any_nonzero_true:
        print("FAIL: at least one LOGO.* rule has a nonzero TRUE count in "
              "this deck. If this is the AP-only artefact, the fix has "
              "regressed — re-check LOGO_AP_ONLY=1 was actually used to "
              "build the merged stream this rundir graded.")
        rc = 1
    else:
        print("PASS (on THIS local stream only): every measured LOGO.* rule "
              "is a real zero, not a cap. This does NOT establish the result "
              "under a full standard-cell/seal-ring library merge — see this "
              "script's module docstring and docs/tapeout/"
              "50-bnd-and-logo-checks.md Part B.4.")
    return rc


if __name__ == "__main__":
    sys.exit(main())
