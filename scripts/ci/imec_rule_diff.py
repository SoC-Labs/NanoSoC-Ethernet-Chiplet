#!/usr/bin/env python3
"""
Rule-by-rule diff engine against IMEC's real Calibre reports -- a real script,
not the manual eyeballing docs/tapeout/50-bnd-and-logo-checks.md and
docs/tapeout/48-imec-signoff-results-analysis.md did the first time.

WHY THIS EXISTS
---------------
docs/tapeout/53-gate-promotion-plan.md §1 row 4 requires "the rule-by-rule
diff against IMEC's report closed" as `bnd` promotion evidence. Doc 50 did
that diff once, by hand, reading two report files side by side. That is not
repeatable, not testable, and cannot be re-run against a NEW archive (there
are now two: the 17Aug pad-ring-only merge and the 18Aug full std-cell +
seal-ring merge, ASIC/imec_results/Archive_*) without doing the by-hand
comparison over again.

WHAT MAKES THIS POSSIBLE
-------------------------
IMEC's `.rpt` files ARE Calibre summary reports -- same grammar as our own
`*.bnd.summary`/`*.drc.summary` (`Layout Primary Cell:`, `RULECHECK <name>
... TOTAL Result Count = N (M)`, an optional `(BY CELL)` section). So the
exact same parser reads both sides; there is no IMEC-specific format to
special-case. reuses bnd_census.py's parse_summary()/owner() rather than
re-implementing them -- see that script's module docstring for why this repo
duplicates rather than shares the DRC-gate-critical parser instead.

WHAT THIS DOES
---------------
Given N labelled reports (any mix of local *.summary files and IMEC archive
*.rpt/*.txt files -- same parser, same grammar) and a rule-name list, prints
a rule x report matrix of (true, capped-display) counts and classifies each
rule EXACT_MATCH / DELTA / ONLY-IN-<label> / ABSENT-EVERYWHERE. Also supports
--by-cell to break a rule down per owning cell, which is what actually
confirms "same finding" rather than "same total by coincidence" (doc 50's
by-cell table; docs/tapeout §8's CORNER_B byte-identical-across-archives
claim).

USAGE
-----
  # bnd promotion evidence: our local run vs both real IMEC archives
  imec_rule_diff.py --rules PM.W.1,AP.W.1,AP.W.2,AP.S.1,AP.S.4 \\
      --report local=calibre_runs/bnd_postfix_check/nanosoc_eth_chiplet_pads.bnd.summary \\
      --report archive1=ASIC/imec_results/Archive_..._17Aug26_15u14/bnd/*.rpt \\
      --report archive2=ASIC/imec_results/Archive_..._18Aug26_19u28/bnd/*.rpt \\
      --by-cell

  # archive-1 vs archive-2 only, no local run needed (CONVERGENCE_PLAN §8
  # extension) -- exit nonzero if this design's own AP.W.1/S.1 (the
  # un-waived finding) drifted between the two archives, which would mean
  # the corner-rotation-fixed geometry is NOT immaterial to BND as assumed.
  imec_rule_diff.py --rules AP.W.1,AP.S.1 --fail-on-delta \\
      --report archive1=.../17Aug.../bnd/*.rpt --report archive2=.../18Aug.../bnd/*.rpt
"""

import argparse
import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bnd_census import parse_summary        # noqa: E402  (reuse, see docstring)


def resolve(spec):
    """`label=path-or-glob` -> (label, resolved single path)."""
    if "=" not in spec:
        sys.exit(f"--report needs LABEL=PATH, got: {spec!r}")
    label, pattern = spec.split("=", 1)
    cands = sorted(glob.glob(pattern)) if any(c in pattern for c in "*?[") \
        else ([pattern] if os.path.exists(pattern) else [])
    if not cands:
        sys.exit(f"--report {label}: no file matches {pattern!r}")
    return label, cands[0]


def fmt(n, cap_n):
    if n is None:
        return "     -"
    return f"{n:>4} ({cap_n})" if cap_n != n else f"{n:>4}"


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                  formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--rules", required=True,
                    help="comma-separated rule names to compare, e.g. "
                         "PM.W.1,AP.W.1,AP.W.2,AP.S.1,AP.S.4")
    ap.add_argument("--report", action="append", required=True, default=[],
                    metavar="LABEL=PATH",
                    help="a labelled report to compare; repeat 2+ times. PATH "
                         "may be a glob (first match wins).")
    ap.add_argument("--by-cell", action="store_true",
                    help="also break down each rule by owning cell")
    ap.add_argument("--fail-on-delta", action="store_true",
                    help="exit 1 if any rule differs (true count) across "
                         "reports that both have it. Off by default: most "
                         "uses of this tool are diagnostic, and a delta "
                         "between an un-merged local run and a full-merge "
                         "archive is often EXPECTED, not a failure — see "
                         "docs/tapeout/48-imec-signoff-results-analysis.md.")
    a = ap.parse_args()

    rules = [r.strip() for r in a.rules.split(",") if r.strip()]
    reports = [resolve(spec) for spec in a.report]
    if len(reports) < 2:
        sys.exit("need at least 2 --report entries to diff anything")

    parsed = {}
    for label, path in reports:
        primary, cap, checks, by_cell, estimates = parse_summary(path)
        parsed[label] = {"path": path, "primary": primary, "cap": cap,
                         "checks": checks, "by_cell": by_cell}
        print(f"# {label:<10} {path}")
        print(f"#   primary cell: {primary or '(none found)'}   cap: {cap}")
    print()

    # A rule is "capped display" when Calibre's parenthesised true count is
    # larger than the number before it; parse_summary only keeps the
    # DISPLAYED (possibly-capped) count today, so re-read the raw text once
    # per report to recover the true (parenthesised) count per rule.
    true_counts = {}
    for label, path in reports:
        txt = open(path, errors="replace").read()
        split = re.search(r"RULECHECK RESULTS STATISTICS\s*\(BY CELL\)", txt)
        main_txt = txt[: split.start()] if split else txt
        true_counts[label] = {
            m.group(1): int(m.group(3))
            for m in re.finditer(
                r"^\s*RULECHECK\s+(\S+)\s*\.*\s*TOTAL Result Count\s*=\s*(\d+)\s*\((\d+)\)",
                main_txt, re.M)
        }

    labels = [l for l, _ in reports]
    col_w = max(12, max(len(l) for l in labels) + 2)
    header = f"{'rule':<22}" + "".join(f"{l:>{col_w}}" for l in labels) + "   verdict"
    print(header)
    print("-" * len(header))

    any_delta = False
    for rule in rules:
        row = []
        trues = []
        present = []
        for label in labels:
            disp = parsed[label]["checks"].get(rule)
            true_n = true_counts[label].get(rule)
            if disp is None:
                row.append("     -")
                present.append(False)
            else:
                row.append(fmt(disp, true_n if true_n is not None else disp))
                trues.append(true_n if true_n is not None else disp)
                present.append(True)
        if not any(present):
            verdict = "ABSENT-EVERYWHERE"
        elif not all(present):
            missing = [l for l, p in zip(labels, present) if not p]
            verdict = f"ONLY-IN-{'+'.join(l for l, p in zip(labels, present) if p)} " \
                      f"(absent: {','.join(missing)})"
            any_delta = True
        elif len(set(trues)) == 1:
            verdict = "EXACT_MATCH"
        else:
            verdict = f"DELTA ({min(trues)}..{max(trues)})"
            any_delta = True
        print(f"{rule:<22}" + "".join(f"{c:>{col_w}}" for c in row) + f"   {verdict}")

        if a.by_cell:
            cells = set()
            for label in labels:
                for cell, rr in parsed[label]["by_cell"].items():
                    if rr.get(rule, 0):
                        cells.add(cell)
            for cell in sorted(cells):
                crow = []
                for label in labels:
                    n = parsed[label]["by_cell"].get(cell, {}).get(rule)
                    crow.append(f"{n:>{col_w}}" if n is not None else f"{'-':>{col_w}}")
                print(f"    {cell:<18}" + "".join(crow))

    print()
    if a.fail_on_delta and any_delta:
        print("FAIL: --fail-on-delta set and at least one rule differs or is "
              "not present in every report above.")
        return 1
    print("(diagnostic run — see --fail-on-delta to turn a DELTA into a "
          "nonzero exit code)" if not a.fail_on_delta else "PASS: all rules "
          "present and identical across every report.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
