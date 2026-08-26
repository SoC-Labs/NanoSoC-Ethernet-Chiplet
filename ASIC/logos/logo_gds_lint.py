#!/usr/bin/env python3
"""Geometry lint for the chip-logo artwork. No EDA licence, no KLayout, seconds.

WHY THIS EXISTS, AND WHY logo_ap_drc.drc COULD NOT CATCH IT
------------------------------------------------------------
`logo_ap_drc.drc` is the fast inner loop for the logo and it checks exactly two
things: AP width (AP_W_1 = 3um) and AP space (AP_S_1 = 2um). It was written on
2026-08-21 after a regex mis-count declared a 20-violation logo clean, and it
did its job -- the artwork revision in a7b4267 took AP.W.1.WB 12 -> 0,
AP.S.1.WB 4 -> 0, AP.S.1.FC 4 -> 0, and Calibre confirms that still holds on the
merged chip (calibre_runs/drc_allfix_logo_0822, 2026-08-22).

The SAME revision silently introduced a defect neither rule can see, because it
is neither a width nor a space:

  TWO OFF-GRID VERTICES. Polygon 13 -- the glyph with bbox
  (-153.875,-151.375)-(-106.125,-84.875) um -- carries y = -97632 nm at two
  vertices where the pre-revision artwork had -97625 nm and where every other
  coordinate in the file is a multiple of 1250 nm. The foundry deck is
  PRECISION 1000 / RESOLUTION 5, i.e. a 0.005 um grid, so those two vertices are
  real DRC results:

      Calibre G.1:APi ........ 0 on the pre-logo stream -> 2 on the merged one
      runtime warning ........ "OFFGRID vertex on layer APi at location
                                (-153.875,-97.632) in cell Logo."  x2

  The seven-nanometre slip also turns what should be a zero-width keyhole seam
  into a self-overlapping outline: Calibre additionally prints "Non-simple
  boundary ... in cell Logo on layer 74 datatype 0" five times on the revised
  artwork and none at all on the pre-revision one.

Everything the inner loop measures is still clean. That is exactly the failure
mode: a check that measures the wrong thing reads like a check that passed.

WHAT IS A HARD FAILURE HERE, AND WHAT IS ONLY A WARNING -- CALIBRATED, NOT GUESSED
---------------------------------------------------------------------------------
OFFGRID is exact. On nanosoc_eth_Logo_APonly_fixed.gds this lint reports 2 and
Calibre reports G.1:APi = 2, same two coordinates. It is a hard failure.

NONSIMPLE is a SUPERSET of whatever Calibre v2023.1 actually flags, and is
reported as a warning for that reason. The artwork legitimately cuts holes in
glyphs with zero-width keyhole seams -- a pair of collinear edges traversed in
OPPOSITE directions -- and Calibre accepts those (the pre-revision artwork has
nine and was never flagged). This lint reports only SAME-direction collinear
overlaps, which is closer, but still not identical: run against the
pre-revision artwork it names polygons 17 and 27, which Calibre accepts. So use
it as a REGRESSION detector with --baseline, not as a rule of record. Calibre
remains the authority; this is the loop you run 50 times before spending a seat.

USAGE
    python3 ASIC/logos/logo_gds_lint.py <logo.gds>
    python3 ASIC/logos/logo_gds_lint.py <new.gds> --baseline <old.gds>
    exit 0 = no hard failure, 1 = findings, 2 = the lint measured nothing

CONTROL, ON PURPOSE
    CTRL.POLYGONS prints before any verdict. A lint that read zero polygons
    prints "clean" for the same reason a broken one does; the count is what
    separates them. Same discipline as count_rdb.py in this directory.
"""
import sys, struct, argparse


def read_boundaries(path, layer, datatype):
    """Return [(cell, [(x,y), ...]), ...] for every BOUNDARY on layer/datatype."""
    out, cur, el, lay, dt, xy = [], None, None, None, None, None
    with open(path, 'rb') as f:
        while True:
            head = f.read(4)
            if len(head) < 4:
                break
            ln, rt = struct.unpack('>HH', head)
            if ln < 4:
                break
            data = f.read(ln - 4) if ln > 4 else b''
            if rt == 0x0606:                                    # STRNAME
                cur = data.rstrip(b'\x00').decode('latin1')
            elif rt in (0x0800, 0x0900, 0x0A00, 0x0B00, 0x0C00, 0x2D00):
                el, lay, dt, xy = rt, None, None, None
            elif rt == 0x0D02:                                  # LAYER
                lay = struct.unpack('>h', data[:2])[0]
            elif rt == 0x0E02:                                  # DATATYPE
                dt = struct.unpack('>h', data[:2])[0]
            elif rt == 0x1003:                                  # XY
                xy = struct.unpack('>%di' % (len(data) // 4), data)
            elif rt == 0x1100:                                  # ENDEL
                if el == 0x0800 and xy and lay == layer and dt == datatype:
                    out.append((cur, [(xy[i], xy[i + 1])
                                      for i in range(0, len(xy), 2)]))
                el, xy = None, None
    return out


def bbox(pts):
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    return (min(xs), min(ys), max(xs), max(ys))


def offgrid(pts, grid):
    return [p for p in pts if p[0] % grid or p[1] % grid]


def same_direction_overlaps(pts):
    """Collinear axis-aligned edge pairs traversed the SAME way.

    Opposite-direction pairs are legal zero-width keyhole seams and are
    deliberately NOT reported -- see the module docstring.
    """
    e = [(pts[i], pts[i + 1]) for i in range(len(pts) - 1)]
    hits = []
    for a in range(len(e)):
        (x1, y1), (x2, y2) = e[a]
        for b in range(a + 1, len(e)):
            (x3, y3), (x4, y4) = e[b]
            if x1 == x2 == x3 == x4 and y1 != y2 and y3 != y4:
                lo, hi = sorted((y1, y2))
                lo2, hi2 = sorted((y3, y4))
                ov = min(hi, hi2) - max(lo, lo2)
                if ov > 0 and (y2 > y1) == (y4 > y3):
                    hits.append(('V', x1, max(lo, lo2), min(hi, hi2), ov))
            elif y1 == y2 == y3 == y4 and x1 != x2 and x3 != x4:
                lo, hi = sorted((x1, x2))
                lo2, hi2 = sorted((x3, x4))
                ov = min(hi, hi2) - max(lo, lo2)
                if ov > 0 and (x2 > x1) == (x4 > x3):
                    hits.append(('H', y1, max(lo, lo2), min(hi, hi2), ov))
    return hits


def non_orthogonal(pts):
    return [(pts[i], pts[i + 1]) for i in range(len(pts) - 1)
            if pts[i][0] != pts[i + 1][0] and pts[i][1] != pts[i + 1][1]]


def um(v):
    return v / 1000.0


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument('gds')
    ap.add_argument('--grid', type=int, default=5,
                    help='grid in database units; the TSMC65 deck is RESOLUTION 5')
    ap.add_argument('--layer', default='74/0')
    ap.add_argument('--baseline', help='an earlier artwork revision, to separate '
                                       'NEW non-simple outlines from pre-existing ones')
    ap.add_argument('--strict', action='store_true',
                    help='make NONSIMPLE a hard failure too')
    args = ap.parse_args(argv)
    lay, dt = (int(v) for v in args.layer.split('/'))

    polys = read_boundaries(args.gds, lay, dt)
    print("CTRL.POLYGONS  %d   (layer %d/%d in %s)" % (len(polys), lay, dt, args.gds))
    if not polys:
        print("FAIL: read zero polygons - this lint measured nothing. Wrong layer, "
              "wrong file, or a parse failure. That is NOT a clean result.")
        return 2

    base = {}
    if args.baseline:
        bp = read_boundaries(args.baseline, lay, dt)
        print("CTRL.BASELINE  %d polygons in %s" % (len(bp), args.baseline))
        if not bp:
            print("FAIL: baseline read zero polygons - cannot classify regressions.")
            return 2
        for _, pts in bp:
            base[bbox(pts)] = len(same_direction_overlaps(pts))

    n_offgrid = n_nonsimple = n_new_nonsimple = n_angled = 0
    for i, (cell, pts) in enumerate(polys):
        og = offgrid(pts, args.grid)
        if og:
            n_offgrid += len(og)
            print("OFFGRID     poly %d cell=%s: %d vertices off the %dnm grid: %s"
                  % (i, cell, len(og), args.grid,
                     ', '.join('(%g,%g)um' % (um(p[0]), um(p[1])) for p in og)))
        ov = same_direction_overlaps(pts)
        if ov:
            n_nonsimple += 1
            tag = ''
            if args.baseline:
                was = base.get(bbox(pts))
                tag = (' [NEW since baseline]' if was is None or len(ov) > was
                       else ' [pre-existing, baseline had %d]' % was)
                if was is None or len(ov) > was:
                    n_new_nonsimple += 1
            print("NONSIMPLE   poly %d cell=%s: %d same-direction collinear overlap(s), "
                  "worst %dnm%s" % (i, cell, len(ov), max(h[4] for h in ov), tag))
            for d, c, lo, hi, o in ov[:3]:
                print("              %s at %s=%gum spanning %g..%gum, overlap %dnm"
                      % (d, 'x' if d == 'V' else 'y', um(c), um(lo), um(hi), o))
        no = non_orthogonal(pts)
        if no:
            n_angled += len(no)
            print("ANGLED      poly %d cell=%s: %d non-orthogonal edge(s)"
                  % (i, cell, len(no)))

    print()
    print("SUMMARY  polygons=%d  offgrid_vertices=%d  nonsimple_polygons=%d%s  angled_edges=%d"
          % (len(polys), n_offgrid, n_nonsimple,
             (" (of which NEW: %d)" % n_new_nonsimple) if args.baseline else "",
             n_angled))
    hard = n_offgrid + n_angled + (n_nonsimple if args.strict else 0)
    if not hard and not n_nonsimple:
        print("PASS: all vertices on the %dnm grid, no self-overlapping outlines, "
              "all edges orthogonal." % args.grid)
        return 0
    if n_offgrid:
        print("FAIL: %d off-grid vertices. Calibre will report these as G.1:APi results "
              "and as 'OFFGRID vertex on layer APi' runtime warnings." % n_offgrid)
    if n_angled:
        print("FAIL: %d non-orthogonal edges. Calibre G.3:APi." % n_angled)
    if n_nonsimple:
        print("%s: %d self-overlapping outlines. Calibre prints these as 'Non-simple "
              "boundary' runtime warnings, NOT as rulecheck results -- so they do not "
              "move the DRC count. They still matter, because how a self-overlapping "
              "outline resolves is tool-dependent, and the importer at the other end "
              "is not this Calibre." % ('FAIL' if args.strict else 'WARN', n_nonsimple))
    return 1 if hard else (1 if args.strict else 0)


if __name__ == '__main__':
    sys.exit(main())
