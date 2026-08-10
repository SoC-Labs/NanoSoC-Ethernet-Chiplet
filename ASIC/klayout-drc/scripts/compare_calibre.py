#!/usr/bin/env python3
# ---------------------------------------------------------------------------
# compare_calibre.py --- put the KLayout counts next to the Calibre counts.
#
#   ASIC/klayout-drc/scripts/compare_calibre.py \
#       work/<tag>/<tag>.counts \
#       ../genus-innovus/calibre_runs/drc_track2/nanosoc_eth_chiplet_pads.drc.summary
#
# WHAT THIS IS FOR
# ----------------
# The KLayout deck is a second opinion, and a second opinion is only worth
# anything once you know where it agrees with the first one. Run this after a
# Calibre run and a KLayout run over the SAME GDS. Three outcomes matter:
#
#   both non-zero   the KLayout check is tracking something real -- trust it on
#                   the laptop between Calibre runs
#   KLayout zero,   the KLayout deck does not model that rule (density, seal
#   Calibre non-zero  ring, front-end, slotting). Expected for most of them;
#                   the list is in README.md. A surprise here is a deck bug.
#   KLayout non-zero, the KLayout check over-reports, OR Calibre is not looking
#   Calibre zero      -- the AP datatype gap is a real instance of the latter.
#                     Investigate before dismissing.
#
# Comparison is BY FAMILY (<layer>.<class>), not by exact rule name. The two
# tools decompose the same constraint differently -- TSMC's M4.S.2.1 against
# this deck's M4.S.2/S.3 -- so equal totals per family is the strongest claim
# the naming can support, and a per-name diff would be noise.
# ---------------------------------------------------------------------------
"""Compare KLayout rough-DRC counts against a Calibre DRC summary."""

import argparse
import re
import sys
from collections import defaultdict

# Rule classes both decks share, in the order they are worth reading.
CLASS_ORDER = ["W", "S", "A", "G", "R", "GRID", "ANGLE", "DN", "other"]


def rule_family(name):
    """'M4.S.2.1' -> ('M4', 'S');  'VIA3.R.2:M4' -> ('VIA3', 'R')."""
    name = name.split(":")[0].split("__")[0].strip()
    parts = name.split(".")
    if len(parts) < 2:
        return (name, "other")
    layer, cls = parts[0], parts[1]
    cls = cls.rstrip("~")
    if cls not in ("W", "S", "A", "G", "R", "GRID", "ANGLE", "DN"):
        cls = "other"
    return (layer, cls)


def read_klayout(path):
    """The .counts sidecar run_drc.sh writes: '<rule>\\t<count>' per line,
    behind a '# scope:' header line. Returns (counts, scope)."""
    out, scope = {}, ""
    with open(path) as fh:
        for line in fh:
            if line.startswith("# scope:"):
                scope = line[len("# scope:"):].strip()
                continue
            if line.startswith("#") or "\t" not in line:
                continue
            rule, n = line.rstrip("\n").split("\t")
            out[rule] = int(n)
    if not out:
        sys.exit("FAIL: no counts in %s -- did the KLayout run finish?" % path)
    return out, scope


def read_calibre(path):
    """Per-rulecheck counts from a Calibre DRC summary.

    Scan ONLY the flat statistics section. The file repeats every non-zero
    check in a following '(BY CELL)' section, and counting both doubles
    everything -- the same trap ASIC/genus-innovus/scripts/calibre/run_drc.sh
    documents.
    """
    out, inside = {}, False
    with open(path) as fh:
        for line in fh:
            if line.startswith("--- RULECHECK RESULTS STATISTICS"):
                if "(BY CELL)" in line:
                    break
                inside = True
                continue
            if not inside or "TOTAL Result Count" not in line:
                continue
            f = line.split()
            if len(f) < 3 or f[0] != "RULECHECK":
                continue
            try:
                out[f[1]] = int(f[-2])
            except ValueError:
                continue
    if not out:
        sys.exit("FAIL: no RULECHECK lines in %s -- is that a Calibre DRC "
                 "summary?" % path)
    return out


def by_family(counts):
    fam = defaultdict(int)
    for rule, n in counts.items():
        fam[rule_family(rule)] += n
    return fam


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("klayout_counts")
    ap.add_argument("calibre_summary")
    ap.add_argument("--all", action="store_true",
                    help="also list families where both tools report zero")
    a = ap.parse_args()

    kl, scope = read_klayout(a.klayout_counts)
    cal = read_calibre(a.calibre_summary)
    kf, cf = by_family(kl), by_family(cal)

    print("== KLayout rough DRC vs Calibre signoff DRC ==")
    print("  klayout : %s  (%d checks, %d results)"
          % (a.klayout_counts, len(kl), sum(kl.values())))
    print("  calibre : %s  (%d checks, %d results)"
          % (a.calibre_summary, len(cal), sum(cal.values())))
    if scope:
        print("  scope   : %s" % scope)
    scoped = scope and ("clip=whole-die" not in scope
                        or "only=all-layers" not in scope)
    if scoped:
        print()
        print("  !! The KLayout run was SCOPED and the Calibre run was not. Every")
        print("     zero below is 'not checked here', not 'clean'. Re-run without")
        print("     CLIP= and ONLY= before drawing any conclusion from a zero.")
    print()

    def layer_key(layer):
        m = re.match(r"^(M|VIA)(\d+)$", layer)
        if m:
            return (0 if m.group(1) == "M" else 1, int(m.group(2)))
        return (2, 0)

    fams = sorted(set(kf) | set(cf),
                  key=lambda f: (layer_key(f[0]), f[0],
                                 CLASS_ORDER.index(f[1])
                                 if f[1] in CLASS_ORDER else 99))

    print("  %-10s %-6s %10s %10s   %s" % ("layer", "class", "klayout",
                                           "calibre", "reading"))
    print("  " + "-" * 62)
    agree = kl_only = cal_only = 0
    for f in fams:
        k, c = kf.get(f, 0), cf.get(f, 0)
        if k == 0 and c == 0 and not a.all:
            continue
        if k and c:
            note = "both flag it"
            agree += 1
        elif k:
            note = "KLAYOUT ONLY -- over-report, or Calibre is not looking"
            kl_only += 1
        else:
            note = "calibre only -- rule not modelled here (see README)"
            cal_only += 1
        print("  %-10s %-6s %10d %10d   %s" % (f[0], f[1], k, c, note))

    print()
    print("  families flagged by both      : %d" % agree)
    print("  families flagged by KLayout   : %d" % kl_only)
    print("  families flagged by Calibre   : %d" % cal_only)
    print()
    print("  Equal counts are NOT expected and are not the goal. The deck is a")
    print("  subset (see README). What matters is that nothing KLayout finds is")
    print("  invisible to Calibre without an explanation.")


if __name__ == "__main__":
    main()
