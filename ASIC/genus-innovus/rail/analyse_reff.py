#!/usr/bin/env python3
"""Turn a Voltus effective-resistance report into a spatial answer.

The report is a flat list of instances and ohms, sorted by resistance. That
tells you the worst number but not the thing actually worth knowing, which is
WHERE the grid is weak. Every core supply pad on this die is on the top or the
bottom edge - six VDD and four VSS, none on the left or the right - so the
prediction is that resistance rises towards mid-height, and worst of all in the
left and right corners of that band. This joins each instance's ohms to its
placement coordinate and tests that.

Usage:
  analyse_reff.py <effr-report> <inst_xy.txt> [--core x1 y1 x2 y2]
"""

import sys
import re
from collections import defaultdict


def norm(name):
    """Innovus escapes bus brackets in the .effr report (`foo_reg\\[44\\]`) and
    does not in `get_db insts .name` (`foo_reg[44]`). Joining the two raw
    dropped 58,530 of 338,903 rows - 17% - and every one of them was a bussed
    register, i.e. exactly the clustered datapath the spatial map is for. The
    loss was invisible because the join simply reported fewer instances.
    """
    return name.replace("\\", "")


def load_xy(path):
    xy = {}
    with open(path) as fh:
        for line in fh:
            parts = line.split()
            if len(parts) != 3:
                continue
            try:
                xy[norm(parts[0])] = (float(parts[1]), float(parts[2]))
            except ValueError:
                continue
    return xy


def load_reff(path):
    """Rows are '<PASS|FAIL|-> <ohms> <instance> <pin>...'.

    The instance column is taken positionally rather than by regex on the name,
    because hierarchical names here contain '/', '[', ']' and '.' and a
    name-shaped pattern would silently drop whole subtrees.

    Returns (rows, disconnected). A row whose resistance column is the literal
    "D/C" is NOT a small resistance and must never be averaged in: the report's
    own legend says it means the instance is DISCONNECTED FROM THE NET. Those
    are returned separately and counted, because an instance with no path to
    the supply is a defect and silently dropping it would hide one.
    """
    out = []
    disc = []
    with open(path) as fh:
        for line in fh:
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            if line.lstrip().startswith("NET:"):
                continue
            p = line.split()
            if len(p) < 3:
                continue
            if p[0] not in ("PASS", "FAIL", "-"):
                continue
            if p[1] == "D/C":
                disc.append(norm(p[2]))
                continue
            try:
                r = float(p[1])
            except ValueError:
                continue
            out.append((norm(p[2]), r))
    return out, disc


def pct(sorted_vals, q):
    if not sorted_vals:
        return float("nan")
    i = int(round(q * (len(sorted_vals) - 1)))
    return sorted_vals[i]


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    effr_path, xy_path = sys.argv[1], sys.argv[2]
    core = (205.0, 205.0, 1395.0, 1795.0)
    if "--core" in sys.argv:
        i = sys.argv.index("--core")
        core = tuple(float(v) for v in sys.argv[i + 1:i + 5])

    xy = load_xy(xy_path)
    rows, disc = load_reff(effr_path)
    if not rows:
        print("NO ROWS PARSED from %s - nothing was measured" % effr_path)
        return 2

    joined = [(n, r, xy[n][0], xy[n][1]) for n, r in rows if n in xy]
    missing = len(rows) - len(joined)

    vals = sorted(r for _, r in rows)
    print("=" * 74)
    print("EFFECTIVE RESISTANCE  %s" % effr_path)
    print("=" * 74)
    print("instances with a resistance : %d" % len(rows))
    print("  of which placed/joined    : %d  (%d had no coordinate)"
          % (len(joined), missing))
    print("  total instances in design : %d" % len(xy))
    print("  COVERAGE                  : %.1f%% of instances"
          % (100.0 * len(rows) / max(1, len(xy))))
    print("  DISCONNECTED (D/C)        : %d  - the report's own word for "
          "'no path to this supply'" % len(disc))
    if disc:
        dxy = [(n, xy[n]) for n in disc if n in xy]
        print("    of which placed        : %d" % len(dxy))
        for n, (x, y) in dxy[:8]:
            print("      %-10.1f %-10.1f %s" % (x, y, n))
        if len(dxy) > 8:
            print("      ... and %d more" % (len(dxy) - 8))
    print()
    print("distribution (ohms)")
    print("  min    %10.4f" % vals[0])
    print("  p50    %10.4f" % pct(vals, 0.50))
    print("  p90    %10.4f" % pct(vals, 0.90))
    print("  p99    %10.4f" % pct(vals, 0.99))
    print("  p99.9  %10.4f" % pct(vals, 0.999))
    print("  max    %10.4f" % vals[-1])
    print("  mean   %10.4f" % (sum(vals) / len(vals)))
    print()

    if not joined:
        print("No instance could be joined to a coordinate - no spatial answer.")
        return 0

    print("worst 12 instances, with position")
    print("  %-12s %-10s %-10s %s" % ("ohms", "x", "y", "instance"))
    for n, r, x, y in sorted(joined, key=lambda t: -t[1])[:12]:
        print("  %-12.4f %-10.1f %-10.1f %s" % (r, x, y, n))
    print()

    x1, y1, x2, y2 = core
    ncol, nrow = 8, 10
    grid_max = defaultdict(float)
    grid_n = defaultdict(int)
    for _, r, x, y in joined:
        c = min(ncol - 1, max(0, int((x - x1) / (x2 - x1) * ncol)))
        rw = min(nrow - 1, max(0, int((y - y1) / (y2 - y1) * nrow)))
        grid_n[(rw, c)] += 1
        if r > grid_max[(rw, c)]:
            grid_max[(rw, c)] = r

    print("WORST effective resistance by position (ohms), core box %s" % (core,))
    print("rows are Y bands, TOP of the table = TOP of the die")
    print("         " + "".join("%9s" % ("x%d" % c) for c in range(ncol)))
    for rw in range(nrow - 1, -1, -1):
        ylo = y1 + (y2 - y1) * rw / nrow
        yhi = y1 + (y2 - y1) * (rw + 1) / nrow
        cells = []
        for c in range(ncol):
            cells.append("%9.3f" % grid_max[(rw, c)] if grid_n[(rw, c)] else "        .")
        print("y%4.0f-%4.0f" % (ylo, yhi) + "".join(cells))
    print()

    # Band comparison: the specific claim under test.
    xmid, ymid = (x1 + x2) / 2.0, (y1 + y2) / 2.0
    xspan, yspan = x2 - x1, y2 - y1

    def band(pred):
        v = [r for _, r, x, y in joined if pred(x, y)]
        return (len(v), max(v) if v else float("nan"),
                sum(v) / len(v) if v else float("nan"))

    print("BAND COMPARISON - the pads are on the TOP and BOTTOM edges only")
    print("  %-34s %8s %10s %10s" % ("band", "insts", "max ohm", "mean ohm"))
    bands = [
        ("bottom 20% of core (near pads)", lambda x, y: y < y1 + 0.2 * yspan),
        ("top 20% of core (near pads)", lambda x, y: y > y2 - 0.2 * yspan),
        ("mid-height 20% (farthest in Y)",
         lambda x, y: abs(y - ymid) < 0.1 * yspan),
        ("left 20% of core", lambda x, y: x < x1 + 0.2 * xspan),
        ("right 20% of core", lambda x, y: x > x2 - 0.2 * xspan),
        ("centre 20% in X", lambda x, y: abs(x - xmid) < 0.1 * xspan),
        ("LEFT edge AND mid-height",
         lambda x, y: x < x1 + 0.2 * xspan and abs(y - ymid) < 0.1 * yspan),
        ("RIGHT edge AND mid-height",
         lambda x, y: x > x2 - 0.2 * xspan and abs(y - ymid) < 0.1 * yspan),
    ]
    for name, pred in bands:
        n, mx, mn = band(pred)
        print("  %-34s %8d %10.4f %10.4f" % (name, n, mx, mn))
    return 0


if __name__ == "__main__":
    sys.exit(main())
