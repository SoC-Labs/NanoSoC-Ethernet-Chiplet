#!/usr/bin/env python3
"""Cross-check a DB-derived pad table against the SHIPPING GDS bytes.

Copyright 2026, SoC Labs (www.soclabs.org)

scripts/dump_io_file.tcl reads an Innovus DB. What actually goes to the broker
is the stream. Those are two different artefacts and this repo has a documented
habit of reading the wrong one -- so before anyone draws a bond diagram from
as_built_pads.csv, prove the table describes the bytes being shipped.

The comparison is the multiset of (cell, x, y, orientation), which is
everything GDSII can express about a placement. It cannot compare instance
NAMES, because GDS has none -- an SREF carries a structure name and a transform
and nothing else. That is precisely why the table has to come from the DB.

Reference-point note: Innovus .location is the lower-left of the placed bbox,
the GDS SREF XY is the cell origin AFTER transform. The two differ by up to a
full cell height on a rotated pad. as_built_pads.csv carries both; this script
compares in GDS convention.

    python3 scripts/xcheck_io_vs_gds.py <stream.gds> <as_built_pads.csv>

Exit 0 on an exact match, 1 on any difference.
"""
import csv, os, sys, collections
from pathlib import Path
sys.path.insert(0, "/home/dam1n19/SoCLabs/nanosoc-ethernet-chiplet/scripts")
import check_padring_gds as cpg
from check_padring_gds import scan_gds

GDS = Path(sys.argv[1])
CSV = Path(sys.argv[2])

rows = list(csv.DictReader(CSV.open()))
cells = {r["cell"] for r in rows}
top = os.environ.get("XCHECK_TOP", "nanosoc_eth_chiplet_pads")
print(f"gds        {GDS.name}")
print(f"top cell   {top}")
print(f"watching   {len(cells)} pad masters")

# The repo scanner only records angle/mirror for ORIENTATION_WATCH_CELLS
# (today: PCORNER_G alone). Widen it for this cross-check so orientation is
# compared on every pad, not just the four corners.
cpg.ORIENTATION_WATCH_CELLS = set(cells)
f = scan_gds(GDS, top, cells)
print(f"top-cell placements (all)     {f.top_child_total}")
print(f"top-cell placements (watched) {len(f.top_children)}")
print(f"AREF placements of watched    {f.aref_watched}")

# GDS ints are database units. Corner uPAD_CORNER_BL sits at (0,0) and the die
# is 1600x2000um, so infer the scale from the observed extent rather than
# assuming it.
xs = [c["xy"][0] for c in f.top_children]
ys = [c["xy"][1] for c in f.top_children]
print(f"raw extent  x {min(xs)}..{max(xs)}   y {min(ys)}..{max(ys)}")
scale = 1000.0   # 1 dbu = 1nm  -> um
print(f"assuming {scale:g} dbu/um -> x {min(xs)/scale}..{max(xs)/scale} um")

def orient_from(angle, mirror):
    a = int(round(angle)) % 360
    return ("m" if mirror else "r") + str(a)

gds_ms = collections.Counter(
    (c["cell"], round(c["xy"][0]/scale, 3), round(c["xy"][1]/scale, 3),
     orient_from(c["angle_deg"], c["mirror"]))
    for c in f.top_children)

# Innovus .location and the GDS SREF point are NOT the same reference.
# .location is the lower-left of the PLACED bbox; the SREF XY is the cell's
# own origin AFTER the transform, i.e. whichever bbox corner the unrotated
# lower-left lands on:
#     r0   -> (llx, lly)      r90  -> (urx, lly)
#     r180 -> (urx, ury)      r270 -> (llx, ury)
# Map the DB side into GDS convention before comparing.
def gds_point(r):
    llx, lly = float(r["bbox_llx"]), float(r["bbox_lly"])
    urx, ury = float(r["bbox_urx"]), float(r["bbox_ury"])
    return {"r0":   (llx, lly),
            "r90":  (urx, lly),
            "r180": (urx, ury),
            "r270": (llx, ury)}[r["orient"]]

db_ms = collections.Counter()
for r in rows:
    x, y = gds_point(r)
    db_ms[(r["cell"], round(x, 3), round(y, 3), r["orient"])] += 1

print(f"\nDB  rows {sum(db_ms.values())}   GDS placements {sum(gds_ms.values())}")
only_db  = db_ms  - gds_ms
only_gds = gds_ms - db_ms
if not only_db and not only_gds:
    print("MATCH: every pad placement in the DB appears in the stream, and vice versa.")
    sys.exit(0)

print(f"\nin DB but NOT in GDS: {sum(only_db.values())}")
for k, n in list(only_db.items())[:15]:
    print("   ", k, "x", n)
print(f"\nin GDS but NOT in DB: {sum(only_gds.values())}")
for k, n in list(only_gds.items())[:15]:
    print("   ", k, "x", n)
sys.exit(1)
