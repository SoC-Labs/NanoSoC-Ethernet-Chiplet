#!/usr/bin/env python3
"""gds_canonical_hash.py - hash a GDSII stream's LAYOUT, not its write event.

    python3 scripts/ci/gds_canonical_hash.py <file.gds> [--json]
    python3 scripts/ci/gds_canonical_hash.py --selftest

THE PROBLEM THIS SOLVES, MEASURED ON THIS PROJECT'S OWN STREAMS.

Every GDSII file records the wall-clock at which it was written, in its BGNLIB
record, and repeats a per-structure timestamp in every BGNSTR -- 2,573 of them
in this design, roughly 62 KB of pure timestamp. `write_stream`
(asic-toolkit/flow/innovus/4_route.tcl) sets no date suppression, so:

    candidate   BGNLIB timestamp      equals
    _pgfix      2026-08-23 03:19:32   mtime of ..._pgfix_logo.gds
    _armA2      2026-08-23 15:01:23   mtime of ..._armA2_logo.gds
    _rzG        2026-08-23 19:24:05   mtime of ..._rzG_logo.gds

So `md5(gds)` -- the identity `ASIC/submissions/*.md` records, and the identity
a foundry cites back at us -- fingerprints THE WRITE EVENT. Two bit-identical
layouts written a second apart hash differently. The raw digest answers "is
this the file I shipped", which is necessary and is not the same question as
"is this the layout I shipped".

Until now the store recorded the second answer as the literal string
`UNVERIFIED-gds-canonical-not-implemented`, on every published stream. Honest,
and useless for the one comparison anyone actually wants to make.

WHAT "CANONICAL" MEANS HERE, EXACTLY.

Walk the record stream. Hash the record TYPE and the record BODY of every
record, in order -- except BGNLIB (0x01) and BGNSTR (0x05), whose bodies are
replaced by zeros of the same length. Nothing else is touched. In particular
this does NOT reorder structures, normalise coordinates, canonicalise cell
names or resolve references: it neutralises timestamps and asserts nothing
else. A canonical hash match therefore means "the same records in the same
order with the same contents", which is a strictly stronger and much simpler
claim than layout equivalence.

WHAT IT IS NOT. It is not a geometric comparison. Innovus RE-ENCODES records
when it merges a macro GDS (see gds_census.py's note 4: byte comparison reports
0 of 126 structures identical on a CORRECT chip). Two streams that describe the
same polygons through different encodings will NOT match here, and that is the
honest behaviour -- a mismatch means "these differ somewhere other than the
clock", which is a prompt to run the KLayout XOR arbiter, not a verdict.

THE DIRECTION OF THE CLAIM, AND THE 26-AUGUST FINDING THAT PINS IT DOWN.

This digest is ONE-DIRECTIONAL and must be quoted that way:

    a MATCH     is a strong identity claim. Same records, same order, same
                contents implies the same layout, trivially.
    a MISMATCH  MEANS NOTHING ON ITS OWN. It does not imply a different
                layout, and the record order it is sensitive to is not a
                property `write_stream` preserves.

That last sentence is measured, not argued. Two things, both on this
project's own 300 MB streams:

  1. Re-streaming the very database that wrote the shipped _pgeco bytes
     produced a DIFFERENT canonical hash at identical byte count and identical
     record count -- 26,842 differing bytes, 12,600 of them BGNLIB/BGNSTR
     clocks and 14,242 decoding as padring filler SREFs (PFILLER5_G,
     PFILLER20_G, PCORNER_G) emitted in a different order in the top cell.
  2. KLayout's geometric XOR over the 26-Aug _rc1v3r4 and _v3r4 candidates
     reports NO DIFFERENCES on all 49 layer/datatype pairs -- see
     scripts/ci/gds_xor_arbiter.py, whose selftest proves it both directions.

So `layout.canonical_hash`, the Artifactory property this feeds, is NOT a
"same layout?" test and must not be read as one. THE ARBITER IS
gds_xor_arbiter.py, wired into the evidence flow as the `gds-layout-identity`
gate. This tool remains useful and correct for what it does measure: a cheap
streaming change-detector over the record sequence, and the raw md5/sha256 a
foundry cites back. `selftest` proves the order sensitivity in a fixture so
nobody has to rediscover it on a 300 MB file.

Copyright (C) 2026, SoC Labs (www.soclabs.org)
"""

import argparse
import hashlib
import json
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gds_census import RecordReader  # noqa: E402

# The two records that carry a clock. BGNLIB holds 12 INT2: last-modified and
# last-accessed, each y/m/d/h/m/s. BGNSTR holds the same 12 for one structure.
BGNLIB, BGNSTR = 0x01, 0x05
TIMESTAMPED = (BGNLIB, BGNSTR)


def canonical(path):
    """-> dict. One pass, streaming; a 300 MB file never lands in memory."""
    raw256, raw5, canon = hashlib.sha256(), hashlib.md5(), hashlib.sha256()
    n_rec = n_stamp = 0
    rd = RecordReader(path)
    try:
        for rtype, body in rd:
            n_rec += 1
            # Length is hashed alongside the body so that a record whose body
            # is a prefix of another's cannot collide with it by concatenation.
            head = struct.pack(">BH", rtype, len(body))
            if rtype in TIMESTAMPED:
                n_stamp += 1
                canon.update(head)
                canon.update(b"\x00" * len(body))
            else:
                canon.update(head)
                canon.update(body)
    finally:
        rd.close()
    # The raw digests are taken separately, over the file as it sits on disk,
    # because that is what a foundry report cites and it must not be affected
    # by anything above.
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            raw256.update(chunk)
            raw5.update(chunk)
    return {
        "path": path,
        "bytes": os.path.getsize(path),
        "raw_sha256": raw256.hexdigest(),
        "raw_md5": raw5.hexdigest(),
        "canonical_sha256": canon.hexdigest(),
        "records": n_rec,
        "timestamp_records_neutralised": n_stamp,
        "method": "gdsii-record-walk; BGNLIB(0x01)+BGNSTR(0x05) bodies zeroed; "
                  "no reordering, no coordinate normalisation",
        # Carried in the dict so every consumer -- report row, store property,
        # backfill -- has the direction of the claim next to the number, and
        # cannot quote the number as a layout comparison by accident.
        "claim": "ONE-DIRECTIONAL. A canonical_sha256 MATCH implies the same "
                 "layout. A MISMATCH implies nothing: write_stream is not "
                 "order-deterministic (MEASURED 2026-08-26 -- a re-stream of "
                 "one database differed in 14,242 top-cell bytes that decode "
                 "as padring filler SREFs in another order). The geometric "
                 "arbiter is scripts/ci/gds_xor_arbiter.py.",
    }


# ---------------------------------------------------------------------------

def _min_gds(when=(2026, 8, 25, 12, 0, 0), x=1000):
    """A smallest-possible valid GDSII, for the selftest.

    Built rather than borrowed: a fixture that depends on a 300 MB stream in a
    gitignored build tree is a fixture that does not run on a fresh clone."""
    def rec(rtype, dtype, payload=b""):
        return struct.pack(">HBB", 4 + len(payload), rtype, dtype) + payload
    stamp = struct.pack(">12h", *(list(when) + list(when)))
    out = b""
    out += rec(0x00, 0x02, struct.pack(">h", 600))            # HEADER
    out += rec(BGNLIB, 0x02, stamp)                           # BGNLIB
    out += rec(0x02, 0x06, b"PROBE\x00")                      # LIBNAME
    out += rec(0x03, 0x05, b"\x3e\x41\x89\x37\x4b\xc6\xa7\xf0"
                           b"\x39\x44\xb8\x2f\xa0\x9b\x5a\x54")  # UNITS
    out += rec(BGNSTR, 0x02, stamp)                           # BGNSTR
    out += rec(0x06, 0x06, b"TOP\x00")                        # STRNAME
    out += rec(0x08, 0x00)                                    # BOUNDARY
    out += rec(0x0D, 0x02, struct.pack(">h", 1))              # LAYER
    out += rec(0x0E, 0x02, struct.pack(">h", 0))              # DATATYPE
    out += rec(0x10, 0x03, struct.pack(">10i", 0, 0, x, 0, x, x, 0, x, 0, 0))  # XY
    out += rec(0x11, 0x00)                                    # ENDEL
    out += rec(0x07, 0x00)                                    # ENDSTR
    out += rec(0x04, 0x00)                                    # ENDLIB
    return out + b"\x00" * (2048 - (len(out) % 2048))


def _two_boxes(when=(2026, 8, 25, 12, 0, 0), swap=False):
    """One structure, two rectangles on two layers -- the SAME layout either
    way, written in one order or the other. The fixture behind the order
    sensitivity arm of the selftest."""
    def rec(rtype, dtype, payload=b""):
        return struct.pack(">HBB", 4 + len(payload), rtype, dtype) + payload

    def box(lay, x):
        return (rec(0x08, 0x00) + rec(0x0D, 0x02, struct.pack(">h", lay))
                + rec(0x0E, 0x02, struct.pack(">h", 0))
                + rec(0x10, 0x03, struct.pack(">10i", x, 0, x + 100, 0,
                                              x + 100, 100, x, 100, x, 0))
                + rec(0x11, 0x00))
    stamp = struct.pack(">12h", *(list(when) + list(when)))
    out = rec(0x00, 0x02, struct.pack(">h", 600))
    out += rec(BGNLIB, 0x02, stamp)
    out += rec(0x02, 0x06, b"ORDER\x00")
    out += rec(0x03, 0x05, b"\x3e\x41\x89\x37\x4b\xc6\xa7\xf0"
                           b"\x39\x44\xb8\x2f\xa0\x9b\x5a\x54")
    out += rec(BGNSTR, 0x02, stamp)
    out += rec(0x06, 0x06, b"TOP\x00")
    a, b = box(31, 0), box(32, 500)
    out += (b + a) if swap else (a + b)
    out += rec(0x07, 0x00) + rec(0x04, 0x00)
    return out + b"\x00" * (2048 - (len(out) % 2048))


def selftest():
    """Both directions, and the limit.

    A hash that ignores timestamps is only useful if it still notices geometry
    -- a canonicaliser that returns a constant would pass every same-layout
    test ever written. And a hash whose mismatches are quoted as verdicts is
    worse than none, so the order sensitivity that makes a mismatch
    uninformative is proved here rather than left in a docstring."""
    import tempfile
    ok = True

    def say(name, good, detail=""):
        nonlocal ok
        print("  %-46s %s   %s" % (name, "ok" if good else "FAIL", detail))
        if not good:
            ok = False

    d = tempfile.mkdtemp(prefix="gds-canon-selftest-")
    a = os.path.join(d, "a.gds")
    b = os.path.join(d, "b.gds")
    c = os.path.join(d, "c.gds")
    open(a, "wb").write(_min_gds(when=(2026, 8, 25, 12, 0, 0)))
    open(b, "wb").write(_min_gds(when=(2019, 1, 1, 3, 4, 5)))   # SAME layout, other clock
    open(c, "wb").write(_min_gds(when=(2026, 8, 25, 12, 0, 0), x=1001))  # same clock, other geometry
    try:
        ra, rb, rc = canonical(a), canonical(b), canonical(c)

        say("the raw digests DIFFER on a clock change",
            ra["raw_sha256"] != rb["raw_sha256"],
            "which is exactly why md5 cannot answer 'same layout?'")
        say("the canonical digest MATCHES on a clock change",
            ra["canonical_sha256"] == rb["canonical_sha256"],
            ra["canonical_sha256"][:16])
        say("the canonical digest DIFFERS on a geometry change",
            ra["canonical_sha256"] != rc["canonical_sha256"],
            "one XY coordinate moved by 1 dbu -- a canonicaliser that "
            "missed this would be a constant")
        say("both timestamp records were found and neutralised",
            ra["timestamp_records_neutralised"] == 2,
            "%d (expect BGNLIB + one BGNSTR)" % ra["timestamp_records_neutralised"])
        say("the raw md5 is the file on disk, untouched",
            ra["raw_md5"] == hashlib.md5(open(a, "rb").read()).hexdigest(),
            "a foundry cites THIS number and it must survive canonicalisation")
        say("record count is plausible", ra["records"] == 12,
            "%d records" % ra["records"])

        # THE LIMIT, PROVED RATHER THAN ASSERTED. Two files holding the SAME
        # two rectangles in the OPPOSITE order are the same layout and must
        # hash differently here -- that is the whole reason a mismatch cannot
        # be read as a verdict, and it is why gds_xor_arbiter.py exists.
        o1 = os.path.join(d, "o1.gds")
        o2 = os.path.join(d, "o2.gds")
        open(o1, "wb").write(_two_boxes(swap=False))
        open(o2, "wb").write(_two_boxes(swap=True))
        r1, r2 = canonical(o1), canonical(o2)
        say("ORDER SENSITIVITY: the same layout in another record order "
            "MISmatches",
            r1["canonical_sha256"] != r2["canonical_sha256"]
            and r1["records"] == r2["records"]
            and r1["bytes"] == r2["bytes"],
            "identical byte and record counts, different digest -- so a "
            "MISMATCH is not evidence of a different layout")
        say("...and the dict says so, next to the number",
            "ONE-DIRECTIONAL" in ra.get("claim", ""),
            "consumers get the direction with the value")
        # A truncated stream must RAISE, not quietly hash a prefix -- a short
        # read that returns a digest is the failure this project keeps finding.
        open(os.path.join(d, "t.gds"), "wb").write(_min_gds()[:60])
        try:
            canonical(os.path.join(d, "t.gds"))
            say("a truncated stream raises", False,
                "it returned a digest -- a partial hash that looks like a whole one")
        except (ValueError, struct.error) as e:
            say("a truncated stream raises", True, type(e).__name__)
    finally:
        import shutil
        shutil.rmtree(d, ignore_errors=True)

    print("\ngds_canonical_hash selftest: %s" % ("OK" if ok else "FAILED"))
    return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0],
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("gds", nargs="?")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    if a.selftest:
        return selftest()
    if not a.gds:
        ap.error("give a .gds, or --selftest")
    r = canonical(a.gds)
    if a.json:
        print(json.dumps(r, indent=2))
    else:
        for k in ("path", "bytes", "records", "timestamp_records_neutralised",
                  "raw_md5", "raw_sha256", "canonical_sha256"):
            print("%-30s %s" % (k, r[k]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
