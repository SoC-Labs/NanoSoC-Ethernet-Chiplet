#!/usr/bin/env python3
# ---------------------------------------------------------------------------
# gen_deck.py --- build a KLayout DRC deck from the TSMC tech LEF + GdsOutMap.
#
#   ASIC/klayout-drc/scripts/gen_deck.py [-o decks/tsmc65_6X1Z1U.drc]
#
# WHY A GENERATOR AND NOT A HAND-WRITTEN DECK
# -------------------------------------------
# Two reasons, and the second is the load-bearing one.
#
# 1. The numbers stay honest. Every constraint in the emitted deck is read out
#    of the same tech LEF Innovus routed against, so this deck asks "did the
#    router obey its own tech file", not "does this match what someone typed
#    into a .drc six months ago". If the metal stack changes, regenerate.
#
# 2. NO FOUNDRY NUMBERS ARE COMMITTED. /tsmc65pdk is NDA collateral. The
#    generated deck contains TSMC dimensions and is therefore written to
#    decks/, which is .gitignore'd. The generator itself holds no rule values
#    -- it is pure structure and is safe to commit and to review in a diff.
#
#    Corollary you must decide on before copying anything to a laptop: the
#    generated deck IS foundry-derived data. It is no more (and no less)
#    carryable off a licensed machine than the GDS itself. That is a call for
#    you and the broker, not for this script. See README.md.
#
# The foundry tech LEF is READ-ONLY and is never copied, patched or sed-ed.
# ---------------------------------------------------------------------------
"""Emit a KLayout DRC deck from the TSMC 65nm tech LEF and Innovus GdsOutMap."""

import argparse
import os
import re
import sys
from pathlib import Path

# Defaults match ASIC/genus-innovus/scripts/config.tcl:123 and the -map_file
# argument of write_stream in asic-flows/Cadence/4_pnr_route.tcl:61. Keep these
# three in step: a deck generated against a different metal option than the one
# write_stream used is silently wrong.
DEF_TLEF = ("/tsmc65pdk/65/CMOS/util/lef/PRTF_EDI_65nm_001_Cad_V24a/"
            "PRTF_EDI_N65_9M_6X1Z1U_RDL.24a.tlef")
DEF_MAP = ("/tsmc65pdk/65/CMOS/util/lef/PRTF_EDI_65nm_001_Cad_V24a/PR_tech/"
           "Cadence/GdsOutMap/PRTF_EDI_N65_gdsout_6X1Z1U.24a.map")
DEF_TOP = "nanosoc_eth_chiplet_pads"


# ---------------------------------------------------------------------------
# LEF parsing
# ---------------------------------------------------------------------------
class Layer:
    def __init__(self, name):
        self.name = name
        self.type = None
        self.direction = None
        self.width = None          # W.1   minimum width
        self.maxwidth = None       # W.3   (informational; needs slot rules)
        self.area = None           # A.1   minimum area
        self.min_encl_area = None  # A.2   minimum enclosed area
        self.minstep = None        # G.4
        self.eol = None            # S.5   (space, within) from LEF57_SPACING
        self.spacing = None        # plain SPACING (cut layers, AP)
        self.prl = None            # [(width, [(runlength, space), ...]), ...]

    def min_space(self):
        """Spacing at minimum width and zero run length -- the S.1 entry."""
        if self.prl:
            return self.prl[0][1][0][1]
        return self.spacing


class Via:
    """One VIARULE GENERATE: cut layer, the two metals, and their enclosures."""

    def __init__(self, name):
        self.name = name
        self.cut = None
        self.lower = None
        self.upper = None
        self.encl = {}   # metal name -> (overhang, other-direction overhang)


def parse_lef(path):
    layers, vias, grid = {}, {}, None
    cur = curvia = None
    prl_widths = None       # pending SPACINGTABLE state
    prl_runlengths = None
    vialayer = None

    with open(path) as fh:
        for raw in fh:
            line = raw.split("#")[0].strip()
            if not line:
                continue

            m = re.match(r"^MANUFACTURINGGRID\s+([\d.]+)", line)
            if m:
                grid = float(m.group(1))
                continue

            # A layer DEFINITION is `LAYER <name>` with no trailing semicolon.
            # `LAYER M1 ;` is a layer REFERENCE and appears inside VIARULE, VIA
            # and PROPERTYDEFINITIONS blocks -- matching those too would let the
            # fixed VIA definitions at the end of the file overwrite every
            # routing layer with an empty one. (It did. That is why this regex
            # is anchored at end of line.)
            m = re.match(r"^LAYER\s+(\S+)\s*$", line)
            if m and curvia is None:
                cur = Layer(m.group(1))
                layers[cur.name] = cur
                prl_widths = prl_runlengths = None
                continue

            m = re.match(r"^VIARULE\s+(\S+)\s+GENERATE", line)
            if m:
                curvia = Via(m.group(1))
                vias[curvia.name] = curvia
                cur = vialayer = None
                continue

            # ---- inside a VIARULE ------------------------------------------
            if curvia is not None:
                if re.match(r"^END\b", line):
                    # A GENERATE rule names three layers: metal, metal, cut.
                    # The cut is the one with a RECT; order in the file is
                    # lower, upper, cut, but do not rely on it -- classify by
                    # what statements each layer block carried.
                    curvia = None
                    vialayer = None
                    continue
                m = re.match(r"^LAYER\s+(\S+)\s*;", line)
                if m:
                    vialayer = m.group(1)
                    continue
                m = re.match(r"^ENCLOSURE\s+([\d.]+)\s+([\d.]+)", line)
                if m and vialayer:
                    curvia.encl[vialayer] = (float(m.group(1)), float(m.group(2)))
                    if curvia.lower is None:
                        curvia.lower = vialayer
                    else:
                        curvia.upper = vialayer
                    continue
                if re.match(r"^RECT\b", line) and vialayer:
                    curvia.cut = vialayer
                continue

            if cur is None:
                continue

            # ---- inside a LAYER --------------------------------------------
            if re.match(r"^END\b", line):
                cur = None
                continue

            m = re.match(r"^TYPE\s+(\S+)", line)
            if m:
                cur.type = m.group(1)
                continue
            m = re.match(r"^DIRECTION\s+(\S+)", line)
            if m:
                cur.direction = m.group(1)
                continue
            m = re.match(r"^WIDTH\s+([\d.]+)\s*;", line)
            if m and prl_widths is None:
                cur.width = float(m.group(1))
                continue
            m = re.match(r"^MAXWIDTH\s+([\d.]+)", line)
            if m:
                cur.maxwidth = float(m.group(1))
                continue
            m = re.match(r"^AREA\s+([\d.]+)", line)
            if m:
                cur.area = float(m.group(1))
                continue
            m = re.match(r"^MINENCLOSEDAREA\s+([\d.]+)", line)
            if m:
                cur.min_encl_area = float(m.group(1))
                continue
            # Plain SPACING. Take only the unqualified form: the ADJACENTCUTS
            # and PARALLELOVERLAP variants are separate rules with separate
            # semantics and folding them into one number would be wrong.
            m = re.match(r"^SPACING\s+([\d.]+)\s*;", line)
            if m:
                if cur.spacing is None:
                    cur.spacing = float(m.group(1))
                continue
            m = re.search(r'LEF57_MINSTEP\s+"MINSTEP\s+([\d.]+)', line)
            if m:
                cur.minstep = float(m.group(1))
                continue
            m = re.search(r'LEF57_SPACING\s+"SPACING\s+([\d.]+)\s+ENDOFLINE\s+'
                          r'([\d.]+)\s+WITHIN\s+([\d.]+)', line)
            if m:
                cur.eol = (float(m.group(1)), float(m.group(2)), float(m.group(3)))
                continue

            # ---- SPACINGTABLE PARALLELRUNLENGTH ----------------------------
            if line.startswith("SPACINGTABLE"):
                prl_widths, prl_runlengths = [], None
                continue
            if prl_widths is not None:
                m = re.match(r"^PARALLELRUNLENGTH\s+(.*)", line)
                if m:
                    prl_runlengths = [float(v) for v in m.group(1).split()]
                    continue
                m = re.match(r"^WIDTH\s+(.*)", line)
                if m and prl_runlengths is not None:
                    vals = [float(v) for v in m.group(1).rstrip(";").split()]
                    w, spaces = vals[0], vals[1:]
                    prl_widths.append((w, list(zip(prl_runlengths, spaces))))
                    if line.rstrip().endswith(";"):
                        cur.prl = prl_widths
                        prl_widths = prl_runlengths = None
                    continue

    return layers, vias, grid


# ---------------------------------------------------------------------------
# GdsOutMap parsing
# ---------------------------------------------------------------------------
def parse_map(path):
    """LEF layer name -> sorted list of (gds layer, datatype) it streams to."""
    out = {}
    with open(path) as fh:
        for raw in fh:
            line = raw.split("#")[0].strip()
            if not line:
                continue
            f = line.split()
            if len(f) < 4:
                continue
            name, purposes, num, dt = f[0], f[1], f[2], f[3]
            if not num.isdigit() or not dt.isdigit():
                continue
            # NAME rows are text labels for pin names, not geometry.
            if name == "NAME":
                continue
            out.setdefault(name, set()).add((int(num), int(dt)))
    return {k: sorted(v) for k, v in out.items()}


# ---------------------------------------------------------------------------
# deck emission
# ---------------------------------------------------------------------------
def layer_expr(specs):
    return " + ".join("input(%d, %d)" % (n, d) for n, d in specs)


HEADER = '''# ===========================================================================
# KLayout rough DRC deck --- GENERATED, DO NOT EDIT, DO NOT COMMIT
#
#   generated by : ASIC/klayout-drc/scripts/gen_deck.py
#   tech LEF     : {tlef}
#   GdsOutMap    : {gmap}
#
# CONTAINS FOUNDRY-DERIVED DIMENSIONS. /tsmc65pdk is NDA collateral; this file
# inherits that status. It is .gitignore'd. Treat it exactly as you treat the
# GDS when deciding what may leave a licensed machine.
#
# THIS IS NOT SIGNOFF. It is a fast, laptop-runnable second opinion on the
# back-end geometry P&R produced. What it does and does not cover is in
# ASIC/klayout-drc/README.md -- read that before quoting a number from it.
#
# Run with:
#   klayout -b -r <this file> -rd in=<gds> -rd report=<out.lyrdb>
# Optional -rd knobs:
#   flat=1              disable hierarchical mode (slower, more memory, but a
#                       useful cross-check if a deep-mode result looks odd)
#   threads=N           default 4
#   clip=x1,y1,x2,y2    check only this window, in um
#   only=M4,VIA3        check only these layers (comma separated)
#   wide=0              skip the width-dependent spacing checks
# ===========================================================================

$in     || raise("gen_deck: -rd in=<gds> is required")
report_file = $report || "klayout_drc.lyrdb"

# Unbuffered, and `puts` rather than KLayout's `info`. info() goes through the
# C++ logger, which block-buffers through a pipe -- measured: nothing at all
# appears until the process exits, so a two-hour run is indistinguishable from a
# hung one. puts honours this sync flag and streams.
$stdout.sync = true

source($in)
report("KLayout rough DRC ({top})", report_file)

if $flat == "1"
  # flat is the reference behaviour; deep is an optimisation that must agree
  # with it. If the two disagree, the deep result is the one to distrust.
else
  deep
end
threads(($threads || "4").to_i)

# Clip at the SOURCE, not by intersecting each layer afterwards. Intersecting
# afterwards still makes deep mode walk the whole 312 MB hierarchy first, which
# defeats the point -- measured: minutes for a 150 um window, versus seconds
# this way.
$guard = nil
if $clip
  c = $clip.split(",").collect {{ |v| v.to_f }}
  c.size == 4 || raise("gen_deck: -rd clip needs x1,y1,x2,y2 in um")
  source.inplace_clip(RBA::DBox::new(c[0], c[1], c[2], c[3]))
  puts("clip: #{{c.inspect}} um")

  # Clipping CUTS wires, and a cut wire has a raw end: it is narrow, it is
  # small in area, and the via that used to sit under a metal that continued
  # past the window now has no enclosure. Every one of those is an artefact of
  # the window, not a defect in the design. Drop markers that touch a frame
  # just inside the clip edge; the width of that frame is the largest distance
  # any check in this deck reaches across, so nothing real is lost more than
  # that far from the boundary. Move the window rather than trusting an edge
  # marker.
  #
  # The frame is derived from `extent` -- the clipped source's own bounding box
  # -- and NOT from a freshly inserted polygon_layer. In deep mode a layer built
  # outside the clipped source lives in a different shape store, and every
  # boolean against it dies with "deep shape store isn't singular".
  gw = ($guardwidth || "2.0").to_f
  if gw > 0
    $guard = extent - extent.sized(-gw)
    puts("clip guard: #{{gw}} um frame -- markers touching it are dropped")
  end
end

$only_set = $only ? $only.split(",").collect {{ |s| s.strip.upcase }} : nil
def want?(name)
  $only_set.nil? || $only_set.include?(name.upcase)
end

# Every check funnels through here so that a) the rule name in the report is
# the TSMC-style name and matches what the Calibre summary calls it, and b) a
# check that produces nothing still gets counted, so "0 violations" and "check
# never ran" are distinguishable in the log.
$counts = []
def check(name, desc, layer)
  # Normalise to polygons first. Checks return three different marker kinds
  # (Region, Edges, EdgePairs) and the clip guard below, the marker browser and
  # the count all want one kind. Zero-area markers get one dbu of body so they
  # are visible when you zoom to them.
  case layer.data
  when RBA::EdgePairs then layer = layer.polygons(0.001)
  when RBA::Edges     then layer = layer.extended_out(0.001)
  end
  # Subtract the clip frame rather than dropping markers that merely touch it:
  # after `source.inplace_clip` in deep mode, the interaction predicates
  # (not_interacting, inside, ...) all raise "deep shape store isn't singular",
  # while plain booleans go through. Verified against the real stream. A marker
  # straddling the frame therefore survives as a fragment instead of vanishing,
  # which is the safe direction to err.
  layer = layer - $guard if $guard
  n = layer.count
  $counts << [name, n]
  layer.output(name, desc)
  puts("  %-22s %8d   %s" % [name, n, desc])
end

t_start = Time.now
puts("=== KLayout rough DRC: {top} ===")

'''

FOOTER = '''
puts("")
puts("=== totals ===")
total = $counts.inject(0) {{ |s, c| s + c[1] }}
nz = $counts.select {{ |c| c[1] > 0 }}.sort {{ |a, b| b[1] <=> a[1] }}
nz.each {{ |c| puts("  %-22s %8d" % c) }}
puts("  %-22s %8d" % ["CHECKS RUN", $counts.size])
puts("  %-22s %8d" % ["CHECKS WITH RESULTS", nz.size])
puts("  %-22s %8d" % ["TOTAL RESULTS", total])
puts("elapsed: %.1f s" % (Time.now - t_start))

# Machine-readable sidecar. The .lyrdb is for the Marker Browser; this is what
# compare_calibre.py reads, because parsing counts back out of XML is silly.
if $counts_out
  File.open($counts_out, "w") do |f|
    # Record the SCOPE. A run restricted to one window and two layers produces
    # a counts file that looks exactly like a clean full-die run, and compare
    # against Calibre would then read every unchecked rule as "not modelled".
    f.puts("# scope: clip=%s only=%s mode=%s" %
           [$clip || "whole-die", $only || "all-layers",
            $flat == "1" ? "flat" : "deep"])
    f.puts("# rule\\tcount")
    $counts.each {{ |c| f.puts("%s\\t%d" % c) }}
  end
  puts("counts: #{{$counts_out}}")
end
'''


def emit(layers, vias, grid, gmap, top, tlef, gmap_path, wide_default=True):
    o = []
    o.append(HEADER.format(tlef=tlef, gmap=gmap_path, top=top))

    routing = [n for n, l in layers.items() if l.type == "ROUTING" and n in gmap]
    cuts = [n for n, l in layers.items() if l.type == "CUT" and n in gmap]

    # ---- layer inputs ------------------------------------------------------
    o.append("# ---- layers (GdsOutMap) ---------------------------------------------------")
    o.append("# Loaded LAZILY and memoised. Reading and merging a layer of this design")
    o.append("# is the expensive part -- M2 alone is 1.4M shapes -- so a run scoped with")
    o.append("# `only=M4,VIA3` must not pay for the other seventeen. Doing that turns the")
    o.append("# recommended per-layer sweep from nineteen full loads into one each.")
    o.append("#")
    o.append("# Lambdas, not a `def`: `input` is a method on the DRC engine, and a lambda")
    o.append("# built here closes over that binding. A `def` body would not resolve it.")
    o.append("# Each merges once -- every geometric check below wants the merged view.")
    o.append("$defs = {}")
    for n in routing + cuts:
        o.append('$defs["%s"] = lambda { (%s).merged }' % (n, layer_expr(gmap[n])))
    o.append("")
    o.append("$cache = {}")
    o.append("def L(name)")
    o.append("  $cache[name] ||= begin")
    o.append('    t = Time.now')
    o.append('    r = $defs[name].call')
    o.append('    puts("  load %-5s %8d polygons  %.1f s" % [name, r.count, Time.now - t])')
    o.append("    r")
    o.append("  end")
    o.append("end")
    o.append("")

    # ---- routing layers ----------------------------------------------------
    for n in routing:
        l = layers[n]
        v = 'L("%s")' % n
        o.append("# ---------------------------------------------------------------------------")
        o.append("# %s  (%s, min width %s, min space %s)"
                 % (n, l.direction or "?", l.width, l.min_space()))
        o.append("# ---------------------------------------------------------------------------")
        o.append('if want?("%s")' % n)
        o.append('  puts("%s")' % n)

        if l.width:
            o.append('  check("%s.W.1", "min width %s um", %s.width(%s).polygons)'
                     % (n, l.width, v, l.width))
        s1 = l.min_space()
        if s1:
            o.append('  check("%s.S.1", "min space %s um", %s.space(%s).polygons)'
                     % (n, s1, v, s1))

        # The rest of the PARALLELRUNLENGTH table. A cell says: two shapes whose
        # wider one is >= W and which run parallel for >= RL must be S apart.
        # Both conditions matter -- dropping the run length turns "two 5 um
        # stripes side by side" into "any two shapes within 1.5 um of each
        # other", which on a power grid over-reports by an order of magnitude
        # (measured: 175 markers in one 150 um window, against 84 die-wide from
        # Calibre for the whole M4 spacing family).
        #
        # STILL MARKED `~`: EVEN WITH BOTH CONDITIONS THIS OVER-REPORTS.
        # Measured on a guarded 50 um window: this deck's M1.S.2 = 82, against
        # Calibre's M1.S.2 = 0 DIE-WIDE on the same stream. The width condition
        # is evaluated against the merged layer, so a shape that is wide
        # somewhere appears to be wide where it faces its neighbour, and the
        # per-edge-pair width TSMC actually measures is narrower. Treat these
        # as "look here", not as a count. Unresolved -- see README.
        #
        # Each (run length, spacing) pair is emitted once, at the SMALLEST width
        # class that demands it -- the wider rows repeat the narrower rows'
        # entries and emitting those again would double-count.
        if wide_default and l.prl and len(l.prl) > 1:
            base = l.prl[0][1][0][1]
            # One check per distinct spacing value, anchored at the (width, run
            # length) corner where that value first becomes required. The table
            # is monotonic in both axes, so everything above and right of that
            # corner needs at least that spacing -- which makes the single
            # `width > W and run >= RL` test exact, not conservative.
            cells = {}
            for w, row in l.prl:
                for rl, s in row:
                    if s <= base:
                        continue
                    if s not in cells or (w, rl) < cells[s]:
                        cells[s] = (w, rl)
            for idx, (s, (w, rl)) in enumerate(sorted(cells.items()), start=2):
                o.append("  # PRL: width >= %s um, parallel run >= %s um -> %s um space"
                         % (w, rl, s))
                o.append('  check("%s.S.%d~", "space %s um for width >= %s um, '
                         'run >= %s um [approx]", '
                         '%s.drc((space(projection, projection_limits(%s, nil)) < %s) '
                         '& (width(projection) > %s)))'
                         % (n, idx, s, w, rl, v, rl, s, w))

        if l.eol:
            sp, eol, within = l.eol
            o.append("  # LEF57 end-of-line: an edge shorter than %s um needs %s um"
                     % (eol, sp))
            o.append("  # clearance. The WITHIN/PARALLELEDGE qualifiers are NOT modelled,")
            o.append("  # so this over-reports -- see README.")
            o.append('  check("%s.S.EOL~", "end-of-line space %s um [approx]", '
                     '%s.edges.with_length(nil, %s).separation(%s.edges, %s).polygons)'
                     % (n, sp, v, eol, v, sp))

        if l.area:
            o.append('  check("%s.A.1", "min area %s um2", %s.with_area(nil, %s))'
                     % (n, l.area, v, l.area))
        if l.min_encl_area:
            o.append('  check("%s.A.2", "min enclosed area %s um2", '
                     '%s.holes.with_area(nil, %s))'
                     % (n, l.min_encl_area, v, l.min_encl_area))
        if l.minstep:
            ms = l.minstep
            o.append("  # MINSTEP %s MAXEDGES 1: illegal iff TWO edges shorter than the" % ms)
            o.append("  # rule are consecutive. Widen each short edge outwards into a thin")
            o.append("  # band, lengthened by one dbu at each end; two consecutive bands")
            o.append("  # then overlap at their shared corner and nowhere else, so")
            o.append("  # merged(2) -- the doubly-covered area -- is exactly one marker")
            o.append("  # per illegal step. A lone short edge (an ordinary min-width wire")
            o.append("  # end) produces no overlap and is correctly not flagged.")
            o.append('  short = %s.edges.with_length(nil, %s)' % (v, ms))
            o.append('  check("%s.G.4", "min step %s um", '
                     'short.extended(0.001, 0.001, 0.001, 0.0).merged(2))' % (n, ms))
        if grid:
            o.append('  check("%s.GRID", "off manufacturing grid %s um", %s.ongrid(%s))'
                     % (n, grid, v, grid))
        o.append('  check("%s.ANGLE", "non-orthogonal edge", '
                 '(%s.edges - %s.edges.with_angle(0) - %s.edges.with_angle(90))'
                 '.extended_out(0.001))' % (n, v, v, v))
        o.append("end")
        o.append("")

    # ---- cut layers --------------------------------------------------------
    via_by_cut = {}
    for vr in vias.values():
        if vr.cut:
            via_by_cut[vr.cut] = vr

    for n in cuts:
        l = layers[n]
        v = 'L("%s")' % n
        vr = via_by_cut.get(n)
        o.append("# ---------------------------------------------------------------------------")
        o.append("# %s  (cut, min space %s)" % (n, l.spacing))
        o.append("# ---------------------------------------------------------------------------")
        o.append('if want?("%s")' % n)
        o.append('  puts("%s")' % n)
        if l.spacing:
            o.append('  check("%s.S.1", "cut space %s um", %s.space(%s).polygons)'
                     % (n, l.spacing, v, l.spacing))
        if vr and vr.lower and vr.upper:
            for mname in (vr.lower, vr.upper):
                if mname not in gmap:
                    continue
                m = 'L("%s")' % mname
                e = vr.encl.get(mname, (0.0, 0.0))[0]
                o.append('  check("%s.R.0:%s", "cut not covered by %s", %s.not_inside(%s))'
                         % (n, mname, mname, v, m))
                o.append("  # LEF says ENCLOSURE %s 0 -- the overhang is required on ONE"
                         % e)
                o.append("  # pair of opposite sides only, so a cut is legal if it clears in")
                o.append("  # x OR in y. Shrinking the metal anisotropically and asking for")
                o.append("  # containment in either shrunk layer is exactly that test; a")
                o.append("  # plain all-round enclosure check would flag every legal via.")
                o.append('  encl_x = %s.sized(%s, 0.0)' % (m, -e))
                o.append('  encl_y = %s.sized(0.0, %s)' % (m, -e))
                o.append('  check("%s.R.2:%s", "%s enclosure %s um", '
                         '%s.not_inside(encl_x).not_inside(encl_y))'
                         % (n, mname, mname, e, v))
        if grid:
            o.append('  check("%s.GRID", "off manufacturing grid %s um", %s.ongrid(%s))'
                     % (n, grid, v, grid))
        o.append("end")
        o.append("")

    o.append(FOOTER.format())
    return "\n".join(o)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("-l", "--tlef", default=DEF_TLEF)
    ap.add_argument("-m", "--map", dest="gmap", default=DEF_MAP)
    ap.add_argument("-t", "--top", default=DEF_TOP)
    ap.add_argument("-o", "--out", default=None,
                    help="default: <repo>/ASIC/klayout-drc/decks/tsmc65_rough.drc")
    ap.add_argument("--no-wide", action="store_true",
                    help="omit the width-dependent spacing checks")
    a = ap.parse_args()

    for p in (a.tlef, a.gmap):
        if not os.access(p, os.R_OK):
            sys.exit("FAIL: unreadable: %s\n      needs the /tsmc65pdk mount and "
                     "membership of group tsmc65pdkgrp." % p)

    layers, vias, grid = parse_lef(a.tlef)
    gmap = parse_map(a.gmap)

    routing = [n for n, l in layers.items() if l.type == "ROUTING" and n in gmap]
    cuts = [n for n, l in layers.items() if l.type == "CUT" and n in gmap]
    if not routing:
        sys.exit("FAIL: no ROUTING layer in %s also appears in %s -- the LEF and "
                 "the map file do not describe the same metal stack."
                 % (a.tlef, a.gmap))
    if grid is None:
        sys.exit("FAIL: no MANUFACTURINGGRID in %s" % a.tlef)

    out = a.out
    if out is None:
        here = Path(__file__).resolve().parent.parent
        out = here / "decks" / "tsmc65_rough.drc"
    out = Path(out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(emit(layers, vias, grid, gmap, a.top, a.tlef, a.gmap,
                        wide_default=not a.no_wide))

    print("== gen_deck ==")
    print("  tech LEF : %s" % a.tlef)
    print("  map      : %s" % a.gmap)
    print("  grid     : %s um" % grid)
    print("  routing  : %s" % " ".join(sorted(routing, key=lambda n: gmap[n][0])))
    print("  cuts     : %s" % " ".join(sorted(cuts, key=lambda n: gmap[n][0])))
    print("  viarules : %d" % len([v for v in vias.values() if v.cut]))
    print("  deck     : %s (%d lines)" % (out, len(out.read_text().splitlines())))
    print()
    print("  NDA: the deck carries foundry dimensions. decks/ is gitignored.")


if __name__ == "__main__":
    main()
