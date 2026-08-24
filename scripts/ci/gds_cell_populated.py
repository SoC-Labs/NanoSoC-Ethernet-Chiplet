#!/usr/bin/env python3
"""
Assert that named GDS structures actually CONTAIN geometry.

WHY THIS EXISTS
---------------
Our stream ships the IO, pad and standard-cell masters as EMPTY SHELLS on
purpose: `write_stream -merge` lists memories and ROMs only, because the
back-end views for those libraries are the broker's to merge. That is correct,
and it is also indistinguishable -- from any check we can run locally -- from a
merge that silently did not happen.

The failure mode is specific and it is quiet. If the broker's library does not
contain a master we instantiate (live example: we renamed the bond pads to
PAD70GU_SL / PAD70NU_SL, and their CompareCells lists those only under "Similar
cell names"), the merge completes, the archive comes back, and every
pad-dependent check -- BND PM.*/CB.*, AP.EN.2, PM.EN.1, Padringcheck, LVS --
reports zero. Zero because there was nothing there to measure. See the note
"a zero that measured nothing".

So: run this on the MERGED gds the broker returns, not on ours.

    gds_cell_populated.py merged.gds --require PAD70NU_SL PAD70GU_SL
    gds_cell_populated.py ours.gds   --report  'PAD70|PCORNER|PFILLER'

--require NAME...   exit 1 unless every named structure exists AND has geometry
--report  REGEX     census only, always exit 0

DELIBERATELY DEPENDENCY-FREE. A plain GDSII record walk in the standard library:
no KLayout, no Calibre, no licence, no install, and it never builds a layout
database. A 300 MB stream costs about 90 seconds and a few MB of RAM, so it can
be handed to the broker to run on their side of the merge.
"""
import argparse, re, struct, sys
from collections import defaultdict

# Element-start records whose LAYER record we want to attribute to a structure.
ELEM = {0x08: "BOUNDARY", 0x09: "PATH", 0x0C: "TEXT", 0x2D: "BOX", 0x15: "NODE"}
REC_BGNSTR, REC_STRNAME, REC_ENDSTR, REC_LAYER = 0x05, 0x06, 0x07, 0x0D


def census(path, keep):
    """-> ({struct: {layer: count}}, {all struct names})   keep(name)->bool"""
    per, seen, cur, pend = defaultdict(lambda: defaultdict(int)), set(), None, False
    with open(path, "rb") as f:
        while True:
            head = f.read(4)
            if len(head) < 4:
                break
            ln, rt, _dt = struct.unpack(">HBB", head)
            if ln < 4:                       # malformed; stop rather than guess
                break
            body = f.read(ln - 4)
            if rt == REC_BGNSTR:
                cur = None
            elif rt == REC_STRNAME:
                cur = body.rstrip(b"\x00").decode("ascii", "replace")
                seen.add(cur)
            elif rt == REC_ENDSTR:
                cur = None
            elif rt in ELEM:
                pend = True
            elif rt == REC_LAYER and pend and cur and keep(cur):
                per[cur][struct.unpack(">h", body[:2])[0]] += 1
                pend = False
    return per, seen


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("gds")
    ap.add_argument("--require", nargs="+", default=[],
                    help="structures that MUST exist and carry geometry")
    ap.add_argument("--report", default=None, help="regex; census only")
    a = ap.parse_args()
    if not a.require and not a.report:
        ap.error("give --require or --report")

    if a.require:
        want = set(a.require)
        per, seen = census(a.gds, lambda n: n in want)
    else:
        rx = re.compile(a.report)
        per, seen = census(a.gds, lambda n: bool(rx.search(n)))

    print(f"file: {a.gds}")
    print(f"structures: {len(seen)}")

    names = sorted(a.require) if a.require else sorted(
        n for n in seen if re.search(a.report, n))
    missing, empty = [], []
    for n in names:
        if n not in seen:
            print(f"  {n:28s} ABSENT")
            missing.append(n)
            continue
        d = per.get(n, {})
        tot = sum(d.values())
        detail = " ".join(f"{k}:{v}" for k, v in sorted(d.items()))
        print(f"  {n:28s} geom={tot:<7d} {detail if detail else '<EMPTY SHELL>'}")
        if tot == 0:
            empty.append(n)

    if not a.require:
        return 0
    if missing or empty:
        print()
        if missing:
            print(f"FAIL: {len(missing)} structure(s) absent: {' '.join(missing)}")
        if empty:
            print(f"FAIL: {len(empty)} structure(s) present but EMPTY: {' '.join(empty)}")
            print("      On a merged stream that means the merge did not populate them,")
            print("      and every check over that geometry measured nothing.")
        return 1
    print(f"\nOK: all {len(names)} required structure(s) carry geometry")
    return 0


if __name__ == "__main__":
    sys.exit(main())
