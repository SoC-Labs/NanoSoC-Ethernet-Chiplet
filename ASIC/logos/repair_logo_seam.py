#!/usr/bin/env python3
"""Repair the two off-grid vertices a7b4267 left in the AP-only logo artwork.

THE DEFECT, IN ONE SENTENCE
    Commit a7b4267 ("logo: the smoothed AP artwork") fixed 20 real AP
    width/spacing violations and, in the same pass, moved one keyhole seam by
    7 nm off the foundry's 0.005 um grid.

WHAT THE ARTWORK SHOULD SAY, AND WHAT IT SAYS
    The glyph with bbox (-153.875,-151.375)-(-106.125,-84.875) um cuts its hole
    with a zero-width seam: an edge runs left-to-right at y = -97625 nm and the
    return edge runs right-to-left at the SAME y. The pre-revision artwork
    (nanosoc_eth_Logo_APonly.gds) does exactly that -- both edges at -97625.
    The revised artwork puts the return edge at y = -97632 instead, which is

      - off the 0.005 um grid (97632 is not a multiple of 5), and
      - a 7 nm-wide sliver where a zero-width seam belongs, which makes the
        outline self-overlapping.

MEASURED CONSEQUENCE (Calibre v2023.1_18.8, deck md5 e3d9a35b48ed..., 2026-08-22)
    pre-logo   ASIC/eth-chiplet/build/gdsrun-20260822-allfix/outputs/
               nanosoc_eth_chiplet_pads.gds        md5 27d7c704...   785 results
    logo       ASIC/genus-innovus/outputs/
               nanosoc_eth_chiplet_pads_logo.gds   md5 964d9f9c...   787 results
    delta      G.1:APi 0 -> 2, and nothing else. Both results are these two
               vertices. Also five "Non-simple boundary ... in cell Logo"
               runtime warnings, none on the pre-revision artwork.

WHY -97625 AND NOT THE NEAREST GRID POINT
    The nearest grid points are -97630 and -97635, and either leaves a 5 nm or
    10 nm sliver -- on-grid, but still sub-resolution geometry in a seam that is
    supposed to have no width at all. -97625 is the value the pre-revision
    artwork used, it restores the zero-width seam, and it is the only choice
    that removes the off-grid AND the self-overlap in one move.

WHY A BYTE PATCH AND NOT A REDRAW
    The artwork is binary GDS and the repository cannot carry a reviewable diff
    of it. This script is the reviewable form: it asserts the exact bytes it
    expects at the exact offsets, refuses to touch anything else, and is
    idempotent. Verify by hand with:
        xxd -s 0x2bc4 -l 24 ASIC/logos/nanosoc_eth_Logo_APonly_fixed.gds

AFTER RUNNING IT
    python3 ASIC/logos/logo_gds_lint.py ASIC/logos/nanosoc_eth_Logo_APonly_fixed.gds
    cd ASIC/genus-innovus && make logo GDS=<the signoff stream>
    ...then Calibre. Expect G.1:APi to disappear and the merged stream to score
    exactly what the un-logoed stream scores.
"""
import sys, struct, hashlib, shutil, argparse

PATH_DEFAULT = 'ASIC/logos/nanosoc_eth_Logo_APonly_fixed.gds'
WRONG = -97632
RIGHT = -97625
# (byte offset of the Y int32, expected X int32 immediately before it)
SITES = [(0x2BCA, -126375), (0x2BD2, -153875)]


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument('gds', nargs='?', default=PATH_DEFAULT)
    ap.add_argument('--check', action='store_true',
                    help='report only; change nothing')
    ap.add_argument('--no-backup', action='store_true')
    args = ap.parse_args(argv)

    buf = bytearray(open(args.gds, 'rb').read())
    print("file   : %s (%d bytes)" % (args.gds, len(buf)))
    print("md5 in : %s" % hashlib.md5(buf).hexdigest())

    wrong_b = struct.pack('>i', WRONG)
    right_b = struct.pack('>i', RIGHT)

    # Refuse to guess. Every occurrence of the bad value must be a site we know.
    seen = []
    i = 0
    while True:
        j = buf.find(wrong_b, i)
        if j < 0:
            break
        seen.append(j)
        i = j + 1
    known = [o for o, _ in SITES]
    if seen and sorted(seen) != sorted(known):
        print("ABORT: y=%d appears at %s but this script only knows %s. The artwork "
              "is not the revision this repair was written for -- re-derive the sites "
              "with logo_gds_lint.py before editing anything."
              % (WRONG, [hex(o) for o in seen], [hex(o) for o in known]))
        return 2

    todo = []
    for off, expect_x in SITES:
        got_x = struct.unpack('>i', buf[off - 4:off])[0]
        got_y = struct.unpack('>i', buf[off:off + 4])[0]
        if got_y == RIGHT and got_x == expect_x:
            print("ok     : 0x%04X already (%d,%d)" % (off, got_x, got_y))
            continue
        if got_x != expect_x or got_y != WRONG:
            print("ABORT: 0x%04X holds (%d,%d), expected (%d,%d). Wrong file or wrong "
                  "revision; nothing written." % (off, got_x, got_y, expect_x, WRONG))
            return 2
        todo.append(off)
        print("repair : 0x%04X  (%d,%d) -> (%d,%d)"
              % (off, got_x, got_y, got_x, RIGHT))

    if not todo:
        print("nothing to do - already on grid.")
        return 0
    if args.check:
        print("--check given; nothing written. %d site(s) would change." % len(todo))
        return 1

    if not args.no_backup:
        shutil.copy2(args.gds, args.gds + '.pre-seam-repair')
        print("backup : %s.pre-seam-repair" % args.gds)
    for off in todo:
        buf[off:off + 4] = right_b
    open(args.gds, 'wb').write(buf)
    print("md5 out: %s" % hashlib.md5(buf).hexdigest())
    print("wrote  : %s  (%d bytes, unchanged length)" % (args.gds, len(buf)))
    print("next   : python3 ASIC/logos/logo_gds_lint.py %s" % args.gds)
    return 0


if __name__ == '__main__':
    sys.exit(main())
