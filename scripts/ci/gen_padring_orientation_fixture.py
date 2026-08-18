#!/usr/bin/env python3
"""Generate the tiny synthetic GDSII fixtures under
ci/fixtures/padring-orientation/, used to prove scripts/check_padring_gds.py's
STRANS/ANGLE-reading orientation check against REAL GDSII BYTES rather than a
hand-typed JSON report -- the strongest form of proof available for this
check, because it exercises the actual record-level parser (scan_gds() /
_gds_real8()), not just the post-condition logic that reads its output.

Copyright 2026, SoC Labs (www.soclabs.org)

Why a generator script, not hand-authored binary fixtures checked in cold
-----------------------------------------------------------------------
Every other fixture family in ci/fixtures/ is text (log excerpts, JSON), and
ci/fixtures/README.md's own discipline is "small, and the provenance is
stated" -- a raw .gds with no generator would be exactly the kind of opaque
binary blob nobody can review or regenerate. This script IS the provenance:
re-run it and the fixture bytes are reproduced exactly.

What it builds
---------------
A minimal GDSII stream containing the design's top cell
(nanosoc_eth_chiplet_pads) with:
  * 4 PCORNER_G placements, one per die corner, at the corners of a
    1,600,000 x 2,000,000 (nm) box -- the real die size
    (ASIC/genus-innovus/scripts/floorplan.tcl's create_floorplan, also
    reproduced in docs/tapeout/52-padring-gds-check.md Section 5).
  * 8 dummy PDDW16DGZ_G placements (2 per edge), purely so
    classify_sides()'s >=8-point self-calibration threshold is met and the
    corner-bucketing logic in classify_corner() runs for real. These are NOT
    a full padframe -- running the real checker against this fixture also
    reports real (and correct) name-or-count problems for every other
    expected cell family, which does not interfere with the orientation
    proof this fixture exists for.

Two variants:
  fail-corner-180/corner_test.gds  -- ANGLE values R90/R180/R270/R0 for
                                       TL/BL/BR/TR, i.e. exactly the values
                                       this design's .io file carried at
                                       commit 9f57214 before today's fix
                                       (all four corners rotated 180 degrees
                                       from correct).
  pass-corner-fixed/corner_test.gds -- ANGLE values R270/R0/R90/R180, i.e.
                                       exactly EXPECTED_ORIENTATION in
                                       scripts/check_padring_gds.py today.

Usage
-----
    python3 scripts/ci/gen_padring_orientation_fixture.py
"""
from __future__ import annotations

import struct
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent.parent
OUT_DIR = HERE / "ci" / "fixtures" / "padring-orientation"

TOP_NAME = "nanosoc_eth_chiplet_pads"
W = 1_600_000   # die width, nm  (1600 um, floorplan.tcl create_floorplan)
H = 2_000_000   # die height, nm (2000 um)

# rec-type/data-type pairs this generator needs. Mirrors the R_* constants in
# scripts/check_padring_gds.py -- kept as a separate, deliberately small list
# here rather than importing that module, so this generator has no
# dependency on the script it is testing.
HEADER, BGNLIB, LIBNAME, UNITS = 0x00, 0x01, 0x02, 0x03
ENDLIB, BGNSTR, STRNAME, ENDSTR = 0x04, 0x05, 0x06, 0x07
BOUNDARY, SREF = 0x08, 0x0A
LAYER, DATATYPE, XY, ENDEL, SNAME = 0x0D, 0x0E, 0x10, 0x11, 0x12
STRANS, ANGLE = 0x1A, 0x1C

DT_NONE, DT_BITARRAY, DT_INT2, DT_INT4, DT_REAL8, DT_STR = 0, 1, 2, 3, 5, 6


def rec(rtype: int, dtype: int, payload: bytes = b"") -> bytes:
    length = 4 + len(payload)
    if length % 2:
        raise ValueError("GDSII records must be even length")
    return struct.pack(">HBB", length, rtype, dtype) + payload


def rec_str(rtype: int, s: str) -> bytes:
    b = s.encode("ascii")
    if len(b) % 2:
        b += b"\x00"
    return rec(rtype, DT_STR, b)


def rec_int2(rtype: int, *vals: int) -> bytes:
    return rec(rtype, DT_INT2, struct.pack(">%dh" % len(vals), *vals))


def encode_real8(value: float) -> bytes:
    """Encode a float as an 8-byte GDSII REAL (excess-64, base-16 exponent).

    The exact inverse of _gds_real8() in scripts/check_padring_gds.py --
    written independently (not by importing that module) so this generator
    cannot share a bug with the code it is meant to test.
    """
    if value == 0.0:
        return b"\x00" * 8
    sign = 0x80 if value < 0 else 0x00
    v = abs(value)
    exponent = 0
    while v >= 1.0:
        v /= 16.0
        exponent += 1
    while v < 1.0 / 16.0:
        v *= 16.0
        exponent -= 1
    mantissa = round(v * (1 << 56))
    if mantissa >= (1 << 56):          # rounding pushed it back up to 1.0
        mantissa >>= 4
        exponent += 1
    byte0 = sign | ((exponent + 64) & 0x7F)
    return bytes([byte0]) + mantissa.to_bytes(7, "big")


def rec_real8(rtype: int, *vals: float) -> bytes:
    return rec(rtype, DT_REAL8, b"".join(encode_real8(v) for v in vals))


def rec_xy(x: int, y: int) -> bytes:
    return rec(XY, DT_INT4, struct.pack(">ii", x, y))


ZERO_DATE = (0, 0, 0, 0, 0, 0)  # BGNLIB/BGNSTR want 2x6 shorts (mod+access)


def structure(name: str, boundary_layer: int | None = None) -> bytes:
    """A minimal structure definition -- a small square BOUNDARY on
    boundary_layer if given (purely cosmetic, mirrors the real script's
    'geometry content, informational only' census), else empty (like
    PAD70GU/PAD70NU/PCORNER_G in every real build measured so far -- see
    docs/tapeout/52-padring-gds-check.md Section 5)."""
    body = rec_int2(BGNSTR, *ZERO_DATE, *ZERO_DATE) + rec_str(STRNAME, name)
    if boundary_layer is not None:
        body += (rec(BOUNDARY, DT_NONE)
                 + rec_int2(LAYER, boundary_layer)
                 + rec_int2(DATATYPE, 0)
                 + rec(XY, DT_INT4, struct.pack(">10i", 0, 0, 0, 100, 100, 100,
                                                 100, 0, 0, 0))
                 + rec(ENDEL, DT_NONE))
    body += rec(ENDSTR, DT_NONE)
    return body


def sref(sname: str, x: int, y: int, angle_deg: float | None = None) -> bytes:
    body = rec(SREF, DT_NONE) + rec_str(SNAME, sname)
    if angle_deg is not None:
        body += rec(STRANS, DT_BITARRAY, b"\x00\x00")  # no mirror
        body += rec_real8(ANGLE, float(angle_deg))
    body += rec_xy(x, y)
    body += rec(ENDEL, DT_NONE)
    return body


def build(corner_angles: dict[str, int]) -> bytes:
    """corner_angles: {'topleft': deg, 'topright': deg, 'bottomleft': deg,
    'bottomright': deg}."""
    out = rec_int2(HEADER, 600)
    out += rec_int2(BGNLIB, *ZERO_DATE, *ZERO_DATE)
    out += rec_str(LIBNAME, "PADRING_FIXTURE.DB")
    out += rec_real8(UNITS, 0.001, 1e-9)   # 1 database unit = 1 nm

    out += structure("PCORNER_G", boundary_layer=31)
    out += structure("PDDW16DGZ_G", boundary_layer=70)

    placements = (
        sref("PCORNER_G", 0, H, corner_angles["topleft"])
        + sref("PCORNER_G", 0, 0, corner_angles["bottomleft"])
        + sref("PCORNER_G", W, 0, corner_angles["bottomright"])
        + sref("PCORNER_G", W, H, corner_angles["topright"])
        # 2 dummy pads per edge, purely to clear classify_sides()'s >=8-point
        # self-calibration threshold -- see the module docstring.
        + sref("PDDW16DGZ_G", int(W * 0.33), H, None)
        + sref("PDDW16DGZ_G", int(W * 0.66), H, None)
        + sref("PDDW16DGZ_G", int(W * 0.33), 0, None)
        + sref("PDDW16DGZ_G", int(W * 0.66), 0, None)
        + sref("PDDW16DGZ_G", 0, int(H * 0.33), None)
        + sref("PDDW16DGZ_G", 0, int(H * 0.66), None)
        + sref("PDDW16DGZ_G", W, int(H * 0.33), None)
        + sref("PDDW16DGZ_G", W, int(H * 0.66), None)
    )
    out += rec_int2(BGNSTR, *ZERO_DATE, *ZERO_DATE) + rec_str(STRNAME, TOP_NAME)
    out += placements
    out += rec(ENDSTR, DT_NONE)

    out += rec(ENDLIB, DT_NONE)
    return out


# The two cases this generator exists to produce -- see the module docstring
# for exactly where each set of numbers comes from.
PRE_FIX_9F57214 = {"topleft": 90, "bottomleft": 180, "bottomright": 270, "topright": 0}
POST_FIX_TODAY = {"topleft": 270, "bottomleft": 0, "bottomright": 90, "topright": 180}


def main() -> int:
    cases = [
        ("fail-corner-180", PRE_FIX_9F57214,
         "all four corners rotated 180deg from correct -- the exact values "
         "ASIC/genus-innovus/scripts/nanosoc_eth_chiplet_pads.io carried at "
         "commit 9f57214, before the 2026-08-18 fix"),
        ("pass-corner-fixed", POST_FIX_TODAY,
         "the corrected values nanosoc_eth_chiplet_pads.io carries today"),
    ]
    for name, angles, note in cases:
        d = OUT_DIR / name
        d.mkdir(parents=True, exist_ok=True)
        gds_path = d / "corner_test.gds"
        gds_path.write_bytes(build(angles))
        (d / "PROVENANCE.txt").write_text(
            "Generated by scripts/ci/gen_padring_orientation_fixture.py -- "
            "do not hand-edit corner_test.gds; re-run the generator instead.\n\n"
            f"corner angles (GDSII ANGLE, degrees CCW): {angles}\n\n{note}\n")
        print(f"wrote {gds_path} ({gds_path.stat().st_size} bytes)  {angles}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
