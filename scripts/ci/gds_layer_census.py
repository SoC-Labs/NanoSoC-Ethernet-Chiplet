#!/usr/bin/env python3
"""
Count GDSII records per (layer, datatype), separating geometry from text.

WHY THIS EXISTS
---------------
"Did the map change do what we intended?" is a question about record counts on
specific layers, and nothing in the flow answered it. write_stream's own
-report_file is a header in this tool version -- it records the command line and
no per-layer inventory -- so a map edit could previously only be judged by
opening the stream in a viewer and squinting.

This parses the GDSII record stream directly. No geometry is constructed and no
layout database is built, so a 316 MB stream takes about a minute and needs no
KLayout or Calibre licence.

THE TRAP THIS AVOIDS, and it is easy to hit if you write your own: an SREF/AREF
element carries no LAYER record. If the parser does not reset its "current
layer" when it sees one, every instance placement inherits the previous
element's layer and gets tallied -- as TEXT, if that is the fallback branch. On
this design that inflated the top cell from 50 text records to 2,362,294, an
error large enough to invert the conclusion being drawn. Measured 2026-08-13.
The guard is the `cur='ref'` arm below; do not simplify it away.

USAGE
    gds_layer_census.py <file.gds> [--per-structure] [--match REGEX] [--json OUT]

Cross-check when changing this file: the 2026-08-12 tapeout stream totals
349,274 text records. If a refactor moves that number, the refactor is wrong.
"""
import argparse
import json
import re
import struct
import sys
from collections import Counter, defaultdict

# GDSII record types we care about.
BOUNDARY, PATH, SREF, AREF, TEXT = 0x08, 0x09, 0x0A, 0x0B, 0x0C
LAYER, DATATYPE, ENDEL, NODE, BOX = 0x0D, 0x0E, 0x11, 0x15, 0x2D
BOXTYPE, TEXTTYPE, STRNAME, ENDSTR = 0x2E, 0x16, 0x06, 0x07


def parse(path):
    """Return (order, per_struct) where per_struct[name] = {'g':C,'t':C,'r':int}."""
    geo = defaultdict(Counter)
    txt = defaultdict(Counter)
    refs = Counter()
    order = []
    cur = None
    lay = dt = None
    sname = None

    with open(path, "rb") as fh:
        while True:
            head = fh.read(4)
            if len(head) < 4:
                break
            length = struct.unpack(">H", head[:2])[0]
            rtype = head[2]
            body = fh.read(length - 4) if length > 4 else b""

            if rtype == STRNAME:
                sname = body.rstrip(b"\x00").decode("ascii", "replace")
                order.append(sname)
                geo[sname], txt[sname] = geo[sname], txt[sname]
            elif rtype == ENDSTR:
                sname = None
            elif rtype in (BOUNDARY, PATH, BOX, NODE):
                cur, lay, dt = "geo", None, None
            elif rtype == TEXT:
                cur, lay, dt = "txt", None, None
            elif rtype in (SREF, AREF):
                # See the header: reset, and never tally. An instance is not a shape.
                cur, lay, dt = "ref", None, None
                refs[sname] += 1
            elif rtype == LAYER:
                lay = struct.unpack(">h", body[:2])[0]
            elif rtype in (DATATYPE, BOXTYPE, TEXTTYPE):
                dt = struct.unpack(">h", body[:2])[0]
            elif rtype == ENDEL:
                if sname is not None and lay is not None:
                    if cur == "geo":
                        geo[sname][(lay, dt)] += 1
                    elif cur == "txt":
                        txt[sname][(lay, dt)] += 1
                cur = None

    per = {s: {"g": geo[s], "t": txt[s], "r": refs.get(s, 0)} for s in order}
    return order, per


def totals(per):
    g, t = Counter(), Counter()
    for v in per.values():
        g.update(v["g"])
        t.update(v["t"])
    return g, t


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("gds")
    ap.add_argument("--per-structure", action="store_true")
    ap.add_argument("--match", help="regex; with --per-structure, report only matching structures")
    ap.add_argument("--json", help="write the full per-structure census here")
    a = ap.parse_args()

    order, per = parse(a.gds)
    g, t = totals(per)

    print(f"# {a.gds}")
    print(f"# structures={len(order):,d}  geometry={sum(g.values()):,d}  text={sum(t.values()):,d}")
    print("\n### TEXT records by layer/datatype")
    for (l, d), c in sorted(t.items()):
        print(f"  {l:5d}/{d:<5d} {c:>12,d}")
    print("\n### GEOMETRY records by layer/datatype")
    for (l, d), c in sorted(g.items()):
        print(f"  {l:5d}/{d:<5d} {c:>12,d}")

    if a.per_structure:
        pat = re.compile(a.match) if a.match else None
        print("\n### PER STRUCTURE")
        for s in order:
            if pat and not pat.search(s):
                continue
            v = per[s]
            gl = ",".join(f"{x}/{y}" for x, y in sorted(v["g"]))
            tl = ",".join(f"{x}/{y}" for x, y in sorted(v["t"]))
            print(f"  {s}")
            print(f"    refs={v['r']:,d}  geom={sum(v['g'].values()):,d} [{gl or '-'}]")
            print(f"                text={sum(v['t'].values()):,d} [{tl or '-'}]")

    if a.json:
        out = {s: {"g": {f"{x}/{y}": c for (x, y), c in per[s]["g"].items()},
                   "t": {f"{x}/{y}": c for (x, y), c in per[s]["t"].items()},
                   "r": per[s]["r"]} for s in order}
        json.dump({"order": order, "d": out}, open(a.json, "w"))
        print(f"\n# per-structure census -> {a.json}", file=sys.stderr)


if __name__ == "__main__":
    main()
