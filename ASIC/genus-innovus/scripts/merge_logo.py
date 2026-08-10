#!/usr/bin/env klayout -b -r
# -----------------------------------------------------------------------------
# merge_logo.py - drop a foundry-style logo cell into a streamed GDS.
#
#   klayout -b -r scripts/merge_logo.py -rd chip=<in.gds> -rd logo=<logo.gds> \
#           -rd out=<out.gds> [-rd x=800.0] [-rd y=1000.0] [-rd cell=Logo]
#
# WHY A SCRIPT AND NOT A ONE-OFF. Two dies go to the same shuttle and every
# stream gets re-cut whenever timing or the power grid moves, so "merge the
# logo" happens many times, by more than one person, under deadline. A manual
# klayout session is the step someone forgets on the stream that ships.
#
# WHY NOT write_stream -merge. The flow already merges the eight memory macros
# that way (config.tcl:190-199) and adding the logo there would work - but it
# would put the logo in EVERY stream, including the ones used for signoff
# comparison. Keeping it a separate, explicit step means the signoff artefact
# and the submission artefact are different files and nobody has to remember
# which is which.
#
# WHAT IT CHECKS BEFORE IT WRITES. A logo is drawn geometry on real mask layers;
# it can break the same rules as any other polygon. This refuses to place one
# that lands somewhere it must not:
#   - the four 74um chip-corner triangles (CSR.R.1 - the one rejection-grade
#     rule this project has; the pad ring already violates it and there is no
#     reason to add to that)
#   - the pad-ring band at the die edge
#   - off the die entirely
# It does NOT check AP width/spacing/density - that is Calibre's job, and
# run_drc.sh on the merged stream is how you find out.
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
# -----------------------------------------------------------------------------
import sys

def need(name):
    v = globals().get(name)
    if v is None:
        raise RuntimeError("missing -rd %s=..." % name)
    return v

chip_f = need("chip")
logo_f = need("logo")
out_f  = need("out")
logo_cell = globals().get("cell", "Logo")
# Die and keep-out geometry. Defaults match nanosoc_eth_chiplet_pads; override
# for the compute chiplet rather than editing them.
die_w   = float(globals().get("die_w", 1600.0))
die_h   = float(globals().get("die_h", 2000.0))
corner  = float(globals().get("corner", 74.0))    # CSR.R.1 empty triangle leg
padband = float(globals().get("padband", 135.0))  # IO cell height at the edge

ly = pya.Layout()
ly.read(chip_f)
top = ly.top_cell()
dbu = ly.dbu
print("chip : %s  top=%s  dbu=%g" % (chip_f, top.name, dbu))

lg = pya.Layout()
lg.read(logo_f)
src = None
for c in lg.each_cell():
    if c.name == logo_cell:
        src = c
        break
if src is None:
    raise RuntimeError("no cell '%s' in %s (have: %s)"
                       % (logo_cell, logo_f, [c.name for c in lg.each_cell()]))

# Copy the logo hierarchy into the chip layout.
dest = ly.create_cell(src.name)
dest.copy_tree(src)
bb = dest.bbox()
lw, lh = bb.width() * dbu, bb.height() * dbu
print("logo : %s cell=%s  %.3f x %.3f um" % (logo_f, src.name, lw, lh))
for li in ly.layer_indexes():
    info = ly.get_info(li)
    n = dest.shapes(li).size()
    if n:
        print("       layer %s : %d shapes" % (info, n))

# Placement is by the logo's CENTRE, because this cell is drawn centred on its
# own origin - placing by corner would silently offset it by half its size.
cx = float(globals().get("x", die_w / 2.0))
cy = float(globals().get("y", die_h / 2.0))
x0, y0 = cx - lw / 2.0, cy - lh / 2.0
x1, y1 = cx + lw / 2.0, cy + lh / 2.0
print("place: centre (%.1f, %.1f) -> bbox (%.1f, %.1f) - (%.1f, %.1f)"
      % (cx, cy, x0, y0, x1, y1))

bad = []
if x0 < 0 or y0 < 0 or x1 > die_w or y1 > die_h:
    bad.append("logo falls outside the die (0,0)-(%g,%g)" % (die_w, die_h))
# Pad-ring band. AP is where the bond pads live (PAD70GU/NU stream on 74/0), so
# a logo on AP in this band is a real collision, not a cosmetic one.
if x0 < padband or y0 < padband or x1 > die_w - padband or y1 > die_h - padband:
    bad.append("logo enters the %gum pad-ring band - AP there holds the bond pads"
               % padband)
# The four corner triangles: x/y measured from each corner, keep-out is x+y<leg.
for (ox, oy, sx, sy) in ((0, 0, 1, 1), (die_w, 0, -1, 1),
                         (0, die_h, 1, -1), (die_w, die_h, -1, -1)):
    for (px, py) in ((x0, y0), (x1, y0), (x0, y1), (x1, y1)):
        dx, dy = (px - ox) * sx, (py - oy) * sy
        if 0 <= dx and 0 <= dy and (dx + dy) < corner:
            bad.append("logo corner (%.1f,%.1f) is inside the %gum chip-corner "
                       "keep-out at (%g,%g) - that is CSR.R.1" % (px, py, corner, ox, oy))
            break

if bad:
    for b in bad:
        print("FAIL: %s" % b)
    raise RuntimeError("placement rejected - move it with -rd x= -rd y=")

top.insert(pya.CellInstArray(dest.cell_index(),
                             pya.Trans(pya.Point(int(round(cx / dbu)),
                                                 int(round(cy / dbu))))))
ly.write(out_f)
print("OK   : wrote %s" % out_f)
print("       now run Calibre on it - this script checks WHERE the logo is,")
print("       never whether its own geometry passes AP width/spacing/density.")
