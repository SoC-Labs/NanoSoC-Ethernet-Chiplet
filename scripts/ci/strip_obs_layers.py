#!/usr/bin/env python3
"""
Remove the LEF-obstruction scratch layers from a GDSII stream.

WHY THIS EXISTS
---------------
The stream-out map moves LEF obstruction to <layer>+9000 rather than dropping
it (ASIC/genus-innovus/scripts/gdsmap_derive.py, --lefobs=move). That keeps the
geometry inspectable, which is what you want internally -- but a SUBMISSION
stream arguably should carry no layer absent from the foundry layer table, and
a recipient has no way to know what layer 9031 is: GDSII has no concept of a
layer NAME, only a number.

So the removal is a step at the END, on the copy that ships, and this is it.

DELIBERATELY NOT A KLAYOUT SCRIPT. This is a plain GDSII record filter in the
standard library: no KLayout, no Calibre, no licence, no install. Hand it to a
broker or a foundry with the GDS and they can run it on anything with python3.
It also never builds a layout database, so a 316 MB stream costs about 90
seconds and a few MB of RAM.

WHAT IT TOUCHES: element records (BOUNDARY / PATH / BOX / NODE / TEXT) whose
LAYER is >= --base. Everything else -- structure headers, SREF/AREF placements,
the library header, units -- is copied through byte for byte. Structures are NOT
removed even if they end up empty, because an empty structure that is still
referenced is valid and removing it would break the reference.

VERIFY AFTER RUNNING: scripts/ci/gds_layer_census.py on both files. Every layer
below --base must be identical; every layer at or above it must be gone.

    strip_obs_layers.py in.gds out.gds [--base 9000] [--dry-run]
"""
import argparse
import struct
import sys
from collections import Counter

# Element-start records, and the records that end one.
ELEM_START = {0x08: "BOUNDARY", 0x09: "PATH", 0x0A: "SREF", 0x0B: "AREF",
              0x0C: "TEXT", 0x2D: "BOX", 0x15: "NODE"}
LAYER, DATATYPE, BOXTYPE, TEXTTYPE, ENDEL = 0x0D, 0x0E, 0x2E, 0x16, 0x11
# SREF/AREF carry no LAYER and must always be kept.
LAYERLESS = {0x0A, 0x0B}
ENDLIB    = 0x04   # last record of a well-formed stream


def block_padding(head, fh):
    """The rest of the file if it is nothing but zero bytes, else None.

    GDSII is a TAPE format and a stream is conventionally padded with zeros to a
    2048-byte block. Those zeros parse as a record of declared length 0, which
    the truncation guards refuse — and would refuse on a perfectly good file.
    Measured on ASIC/romlibs/eth_rom/eth_rom_via.gds2, a memory-compiler output
    this project ships: 7,170,048 bytes = 2048 x 3501, ENDLIB at offset
    7,168,934, then 1,110 zeros. This filter called it corrupt and exited 1.

    PADDING ONLY COUNTS AFTER ENDLIB, and the caller enforces that. Zeros before
    the end of the library are a truncated stream however round the file size is,
    which is the distinction that keeps this from re-opening the hole the guards
    were added to close.
    """
    tail = head + fh.read()
    return tail if not any(tail) else None


def strip(src, dst, base, dry_run):
    """Copy `src` to `dst`, dropping every element on a layer at or above `base`."""
    kept = Counter()
    removed = Counter()
    placements = [0]    # SREF/AREF: no layer, never removed, counted apart
    buf = []            # records of the element currently being read
    in_elem = False
    saw_endlib = False
    elem_rt = None
    lay = dt = None
    out = None if dry_run else open(dst, "wb")

    def flush(drop):
        """Emit the buffered element unless `drop`; SREF/AREF are counted, never dropped."""
        nonlocal buf
        if not drop and out is not None:
            for rec in buf:
                out.write(rec)
        buf = []

    with open(src, "rb") as fh:
        while True:
            head = fh.read(4)
            if not head:
                break                       # clean end of file
            # `saw_endlib and` first, deliberately: this runs per record on a
            # stream with millions of them, and before ENDLIB there is nothing
            # to test.
            if saw_endlib and (len(head) < 4
                               or struct.unpack(">H", head[:2])[0] < 4):
                pad = block_padding(head, fh)
                if pad is not None:
                    if out is not None:
                        out.write(pad)
                    break
            if len(head) < 4:
                # A stream that runs out mid-record is not a stream that ended.
                # Breaking here would copy a truncated input and report a
                # successful filter, so the caller ships a short GDS whose only
                # symptom is its size.
                sys.exit(f"strip_obs_layers: FATAL: {len(head)} trailing byte(s) "
                         f"at offset {fh.tell() - len(head)} - too few for a "
                         f"record header. {src} is truncated or corrupt; refusing "
                         f"to present a partial copy as a filtered one.")
            length = struct.unpack(">H", head[:2])[0]
            rtype = head[2]
            if length < 4:
                sys.exit(f"strip_obs_layers: FATAL: bad record length {length} "
                         f"at offset {fh.tell() - 4}. Not a well-formed GDSII.")
            body = fh.read(length - 4) if length > 4 else b""
            if len(body) != length - 4:
                sys.exit(f"strip_obs_layers: FATAL: record at offset "
                         f"{fh.tell() - 4 - len(body)} declares {length} bytes "
                         f"but only {len(body) + 4} remain. {src} is truncated.")
            if rtype == ENDLIB:
                saw_endlib = True
            rec = head + body

            if rtype in ELEM_START:
                in_elem, elem_rt, lay, dt = True, rtype, None, None
                buf = [rec]
                continue

            if in_elem:
                buf.append(rec)
                if rtype == LAYER:
                    lay = struct.unpack(">h", body[:2])[0]
                elif rtype in (DATATYPE, BOXTYPE, TEXTTYPE):
                    dt = struct.unpack(">h", body[:2])[0]
                elif rtype == ENDEL:
                    drop = (elem_rt not in LAYERLESS
                            and lay is not None and lay >= base)
                    if elem_rt in LAYERLESS or lay is None:
                        # SREF/AREF placements carry no layer. Counted apart so
                        # the layer tallies stay comparable with a layer census,
                        # and so the final assertion is never handed a None.
                        placements[0] += 1
                    else:
                        (removed if drop else kept)[(lay, dt)] += 1
                    flush(drop)
                    in_elem = False
                continue

            if out is not None:
                out.write(rec)

    if out is not None:
        out.close()
    # An element left open at EOF, or a library with no ENDLIB, means the walk
    # ended somewhere other than the end of a well-formed stream.
    if in_elem:
        sys.exit(f"strip_obs_layers: FATAL: {src} ends inside an element - no "
                 f"ENDEL. Truncated or corrupt.")
    if not saw_endlib:
        sys.exit(f"strip_obs_layers: FATAL: {src} has no ENDLIB record. It is "
                 f"not a complete GDSII stream.")
    return kept, removed, placements[0]


def main():
    """Strip obstruction layers from one GDS, or with --dry-run just report them."""
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--base", type=int, default=9000,
                    help="remove elements on layers >= this (default 9000, the "
                         "obstruction scratch base used by gdsmap_derive.py)")
    ap.add_argument("--dry-run", action="store_true",
                    help="report what would go, write nothing")
    a = ap.parse_args()

    if not a.dry_run and a.src == a.dst:
        sys.exit("strip_obs_layers: FATAL: refusing to write over the input.")

    kept, removed, placements = strip(a.src, a.dst, a.base, a.dry_run)

    print(f"# {a.src}")
    print(f"# layers >= {a.base} {'would be' if a.dry_run else 'were'} removed\n")
    if removed:
        print("### REMOVED")
        for (l, d), c in sorted(removed.items()):
            print(f"  {l:6d}/{d:<5d} {c:>10,d}")
    else:
        print("### REMOVED: nothing — no layer at or above the base was present.")
    print(f"\n  removed {sum(removed.values()):,d} elements on {len(removed)} layer(s)")
    print(f"  kept    {sum(kept.values()):,d} elements on {len(kept)} layer(s)")
    print(f"  kept    {placements:,d} SREF/AREF placements (no layer; never removed)")
    if any(l >= a.base for (l, _d) in kept):
        sys.exit("strip_obs_layers: FATAL: an element at or above the base survived.")
    if not a.dry_run:
        print(f"\n  wrote {a.dst}")


if __name__ == "__main__":
    main()
