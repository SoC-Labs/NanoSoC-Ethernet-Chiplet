#!/usr/bin/env python3
"""Check the padframe INSIDE A STREAMED GDSII against the pad-ring's own sources.

Copyright 2026, SoC Labs (www.soclabs.org)

Why
---
IMEC's signoff report on this GDS came back with two related surprises we had
no local way to predict:

    CompareCells:    "No identical cell names found!"
        (comparing our GDS's cell names against TSMC's real pad library,
        tpbn65v.gds)
    Padringcheck:    "Design does not contain any TSMC IO cells or bondpads."

Both tools are looking at the same thing from two angles: does this stream
actually carry a recognisable TSMC pad ring, by NAME? `check_chip_boundary.py`
already answers the NETLIST-side version of that question -- its
`check_pad_ring()` proves every bonded chip-boundary port reaches a real
pad-cell instance in `ASIC/tech_wrappers/tsmc65/nanosoc_eth_chiplet_pads.v`.
What it cannot see is what actually got STREAMED. A cell can be named
correctly in the Verilog and still arrive at the broker under the wrong name,
missing outright, or duplicated, because of something that happens between
`write_stream` and the tarball -- a merge-list omission, a LEF/GDS library
swap, a case change. That gap is exactly the class of surprise IMEC hit, and
until this script existed nothing in this repo ever opened the actual GDS to
look at it.

What "padframe" and "black-box submission" mean, for anyone new here
---------------------------------------------------------------------
The physical bond pads and ESD/IO driver cells that sit around the outside
edge of the die -- the "padframe" -- are licensed TSMC IP
(the tphn65lpgv2od3 IO-driver family and the tpbn65v staggered-bond-pad
family). We do not hold usable rights to redistribute their real transistor
and metal geometry, so our own GDS deliverable references them **by cell name
only**: `ASIC/genus-innovus/scripts/place_bondpads.tcl` creates instances
named e.g. `PAD70GU`/`PAD70NU`, `ASIC/tech_wrappers/tsmc65/
nanosoc_eth_chiplet_pads.v` instantiates `PDDW16DGZ_G`, `PVDD1DGZ_G`, etc.,
and the LEF abstracts (pin/obstruction shapes only, no real layout) stand in
for the cells during our own place-and-route. This is DELIBERATE and BY
DESIGN, not a bug -- see `ci/signoff.yaml`'s `gds-completeness` waiver, which
documents that 424 cell masters in the shipped stream have LEF-abstract
geometry only ("PAD70GU is AP/RDL only").

The foundry's own merge tooling is expected to substitute the REAL vendor
geometry back in by matching cell NAME at import time. That is exactly why
name correctness is not a formality here: if our name for a cell does not
match the name the foundry's tool is keying its substitution on, the
substitution silently does nothing -- no error, no missing-cell warning, just
a design that "resolves" locally (every name we used, we defined SOMETHING
for) and then arrives at the broker with a padframe their tools cannot find.
That is a plausible, and on the evidence below not yet ruled out, explanation
for what IMEC saw.

What this script CAN and CANNOT tell you
-----------------------------------------
GDSII has no concept of an instance NAME -- a placement (SREF/AREF) carries
only a reference to a STRUCTURE name and a transform. So this cannot ask "is
uPAD_TL_RX_0 physically in the right spot" (there is no "uPAD_TL_RX_0" anywhere
in the stream to look for). What it CAN do, and what IMEC's own CompareCells
does too (a cell-NAME diff, not a geometry diff):

  * NAME + COUNT: does every expected pad/corner/bond-pad STRUCTURE NAME
    appear in the stream, referenced (and ideally defined) the expected
    number of times, derived fresh from the same three sources
    `check_chip_boundary.py` already trusts (pads.v, the .io floorplan file,
    place_bondpads.tcl) -- never a hand-copied list that can go stale.
  * MISNAMED / EXTRA: any defined structure that starts with one of our pad
    library prefixes (PAD7, PCORNER, PDDW, PDUW, PVDD, PVSS) but is not one of
    the exact names we expect -- a version-suffix or case drift would show up
    here.
  * PADFRAME ORDER, as far as anonymous geometry allows: using the 4
    corner-cell placements to self-calibrate the die's four edges (never a
    hard-coded floor-plan size), every OTHER padframe-family placement is
    bucketed to an edge by nearest-edge distance, and the per-edge CELL-TYPE
    SEQUENCE (ranked by position along that edge) is compared against the
    sequence the same three sources say the floorplan intended -- accepting
    either direction, since geometry alone does not say which physical
    direction the source list's "first" entry corresponds to. This catches a
    shuffled, missing, extra, or substituted pad-TYPE in the ring; it CANNOT
    tell two same-typed adjacent pads apart (e.g. it cannot prove TL_RX_2 in
    particular is not swapped with TL_RX_3 -- both are `PDDW16DGZ_G`).
  * ORIENTATION, for the 4 corner cells only: each corner placement's live
    STRANS/ANGLE transform, read directly from the GDS, diffed against a
    reviewed `EXPECTED_ORIENTATION` table (see Section 1a below) -- this is
    what catches a corner cell placed at the right SPOT with the right NAME
    but rotated the wrong way, the exact defect class IMEC's Padringcheck
    caught 2026-08-18 that nothing else here can see (name/count/order all
    stayed clean throughout that bug -- see docs/tapeout/52-padring-gds-
    check.md Section 7). It is intentionally NOT extended to the 82 ordinary
    IO/power pads: `nanosoc_eth_chiplet_pads.io` declares no `orientation=`
    for them (their rotation is a PnR placement OUTPUT, not a floorplan
    INPUT), so there is no sourceable "expected" value to check them against
    -- see EXPECTED_ORIENTATION's own docstring for why guessing one would be
    exactly the mistake this check exists to prevent.
  * GEOMETRY CONTENT, informationally only: whether each expected structure's
    own definition carries any BOUNDARY/PATH/BOX geometry at all, and on how
    many distinct layers -- a coarse, uninterpreted signal for "is this a
    real multi-layer cell or a thin LEF-abstract stub", printed for
    visibility but never gated on (we have no real tpbn65v.gds/tphn65lpgv2od3
    geometry on this machine to say what a "real" cell should look like, so a
    pass/fail threshold here would be invented, not measured).

What it flatly CANNOT do: prove the padframe is DRC-clean, prove the streamed
geometry electrically matches the real vendor cell, or substitute for
IMEC/the foundry's own CompareCells and Padringcheck. A clean run of this
script is "our own names, counts, order and corner orientation are internally
consistent, and present in the stream" -- not "this pad ring will clear the
broker's tools." See the docstring section "VALIDATION RESULT" recorded in
docs/tapeout for what running this against the exact GDS IMEC saw found.

Usage
-----
    check_padring_gds.py --gds <file.gds> [--top NAME] [--json OUT]

Exit status
-----------
    0  every expected pad/corner/bond-pad name, count, per-side type order
       and corner orientation matches what the sources intend
    1  a mismatch was found (missing, extra, misnamed, out-of-order, or
       wrongly rotated)
    2  usage / internal error (bad arguments, sources unreadable, GDS
       unreadable or not GDSII)
"""
from __future__ import annotations

import argparse
import json
import os
import re
import struct
import sys
from collections import Counter, defaultdict
from pathlib import Path

EXIT_OK = 0
EXIT_MISMATCH = 1
EXIT_USAGE = 2

HERE = Path(__file__).resolve().parent.parent
PADS_V = HERE / "ASIC" / "tech_wrappers" / "tsmc65" / "nanosoc_eth_chiplet_pads.v"
IO_FILE = HERE / "ASIC" / "genus-innovus" / "scripts" / "nanosoc_eth_chiplet_pads.io"
BONDPAD_TCL = HERE / "ASIC" / "genus-innovus" / "scripts" / "place_bondpads.tcl"
CONFIG_TCL = HERE / "ASIC" / "genus-innovus" / "scripts" / "config.tcl"

SIDES = ("top", "left", "bottom", "right")
CORNER_SIDES = {"topleft", "topright", "bottomleft", "bottomright"}
SIDE_KEYWORDS = ("topleft", "topright", "bottomleft", "bottomright",
                  "top", "bottom", "left", "right")

# Structure-name prefixes the TSMC pad/corner/bond-pad libraries this design
# uses are drawn from (tphn65lpgv2od3 IO drivers PDDW*/PDUW*/PVDD*/PVSS*, the
# tpbn65v staggered bond pads PAD70*, and the corner cell PCORNER_G). Any
# DEFINED structure starting with one of these that is not one of our exact
# expected names is a "misnamed / unexpected" flag -- the kind of drift a
# version suffix or a case change would produce.
WATCH_PREFIXES = ("PAD7", "PCORNER", "PDDW", "PDUW", "PVDD", "PVSS")

# ---------------------------------------------------------------------------
# 1a. Expected corner orientation -- A REVIEWED, HAND-WRITTEN TABLE, NOT A
#     VALUE RE-READ FROM THE .io FILE AT RUNTIME, AND NOT A DERIVED FORMULA.
#     BOTH alternatives were considered and rejected. Read this before editing.
#
#     WHY NOT "just re-parse .io's orientation= like Expected already does
#     for names/counts/order": because that field is EXACTLY what was wrong.
#     The bug this table exists to catch is that
#     ASIC/genus-innovus/scripts/nanosoc_eth_chiplet_pads.io itself carried
#     four wrong `orientation=` values for months (all four PCORNER_G corners
#     rotated 180 degrees from correct, introduced whenever this
#     hand-maintained file was last edited -- commit 9f57214, "ASIC Cadence
#     PnR up to routing complete" -- and never touched again until IMEC's
#     Padringcheck caught it 2026-08-18: "Design does not contain any TSMC IO
#     cells or bondpads" was the visible symptom on THAT run, but the
#     corner-rotation finding is the one this table addresses). If this
#     check's "expected" value were sourced by re-reading that same .io file
#     every run, a future re-introduction of the identical bug (someone edits
#     orientation= back to wrong) would make "expected" drift in lockstep
#     with "wrong" -- the two would always agree with each other and this
#     check would never fire. A trip-wire cannot be wired to the thing it is
#     guarding.
#
#     WHY NOT a derived formula (e.g. "each corner is +90 degrees from the
#     last, walking the ring"): this exact mistake has already been made once
#     in this repo. docs/tapeout/04-floorplan-and-io.md Section 4.2 (commit
#     b5d249c8) *asserted* a "verified" +90-degrees-per-step rotational
#     pattern around the four corners, stated with confidence, and it was
#     WRONG -- PCORNER_G is rotation-symmetric for CSR.R.1 (ESD ruling)
#     purposes, which is a completely different question from which of the
#     four TL/TR/BL/BR *positions* a given rotation belongs in relative to
#     the pad rows that corner must abut. A formula that looks plausible from
#     symmetry alone re-encodes exactly the kind of unreviewed guess that
#     produced the original bug, just with extra indirection.
#
#     SO: this table was built by a human reading the CORRECTED
#     nanosoc_eth_chiplet_pads.io on 2026-08-18 (post-fix; verified against
#     the file, not against memory -- see docs/tapeout/52-padring-gds-check.md
#     Section 7 for the before/after values, sourced from git history at
#     commit 9f57214 for "before" and the working tree as corrected today for
#     "after") and is pinned here as an independent, static reference. If
#     `nanosoc_eth_chiplet_pads.io` is ever deliberately re-floorplanned (a
#     real design change, not a bug fix), this table must be updated BY HAND,
#     by a human re-deriving what "correct" means for the new floorplan --
#     never by re-pointing it at the .io file's own field.
#
#     Each entry: the .io file's own instance name -> {gds cell, expected
#     rotation in degrees (0/90/180/270, GDSII ANGLE convention: degrees
#     counter-clockwise), expected mirror bit, WHY}. "WHY" names the die
#     corner and the two pad-ring edges that corner must abut -- so a future
#     editor can sanity-check a change against the physical floorplan, not
#     just against this table's own past self.
#
#     GDSII's `orientation=` string (R0/R90/R180/R270, as .io/place_io write
#     it) maps onto STRANS/ANGLE as: R<N> -> ANGLE=<N> degrees, no reflection
#     (STRANS bit 15 clear). This design's floorplan never uses a mirrored
#     ("MX"/"MY"-style) corner orientation, so `mirror: False` throughout --
#     recorded explicitly rather than assumed, so a future corner placement
#     that DOES need a mirror shows up as a table gap, not a silent pass.
# ---------------------------------------------------------------------------
EXPECTED_ORIENTATION: dict[str, dict] = {
    "uPAD_CORNER_TL": {
        "cell": "PCORNER_G",
        "corner": "topleft",
        "angle_deg": 270,
        "mirror": False,
        "why": ("Top-left die corner: this corner's pad ring must abut the "
                "TOP edge (running right, toward uPAD_VDDIO_T_0) and the "
                "LEFT edge (running down, toward uPAD_TL_RX_0). R270 is the "
                "rotation that faces PCORNER_G's ESD/guard geometry into "
                "that top+left pairing."),
    },
    "uPAD_CORNER_BL": {
        "cell": "PCORNER_G",
        "corner": "bottomleft",
        "angle_deg": 0,
        "mirror": False,
        "why": ("Bottom-left die corner: abuts the LEFT edge (running up, "
                "toward uPAD_TL_TX_7) and the BOTTOM edge (running right, "
                "toward uPAD_VDDIO_B_0). R0 is this design's reference "
                "(unrotated) corner orientation, assigned to bottom-left."),
    },
    "uPAD_CORNER_BR": {
        "cell": "PCORNER_G",
        "corner": "bottomright",
        "angle_deg": 90,
        "mirror": False,
        "why": ("Bottom-right die corner: abuts the BOTTOM edge (running "
                "left, toward uPAD_VDDIO_B_2) and the RIGHT edge (running "
                "up, toward uPAD_VDDIO_R_0). R90 continues the "
                "counter-clockwise progression from the bottom-left "
                "reference around to bottom-right."),
    },
    "uPAD_CORNER_TR": {
        "cell": "PCORNER_G",
        "corner": "topright",
        "angle_deg": 180,
        "mirror": False,
        "why": ("Top-right die corner: abuts the RIGHT edge (running down, "
                "toward uPAD_HOST_IO_6) and the TOP edge (running left, "
                "toward uPAD_VSSIO_T_2). R180 -- the corner diagonally "
                "opposite bottom-left's R0 reference, which is exactly the "
                "180-degree relationship the shipped bug got wrong on ALL "
                "FOUR corners at once (see the header comment above)."),
    },
}


class SourceError(Exception):
    """The pad-ring's own sources (pads.v / .io / place_bondpads.tcl) do not
    agree with each other, or are missing. Fix the sources; this is not a GDS
    problem."""


class GdsError(Exception):
    """The GDSII stream itself is missing, unreadable, or corrupt."""


# ---------------------------------------------------------------------------
# 1. Parse the sources check_chip_boundary.py already trusts, to build the
#    EXPECTED padframe inventory fresh every run. Never hand-copy this list --
#    it is exactly the trap chip_boundary.py's own docstring warns about: a
#    list that only CLAIMS to track the source rots the day the source moves.
# ---------------------------------------------------------------------------
def parse_pads_verilog(path: Path) -> dict[str, str]:
    """Return {instance_name: cell_type} for every uPAD_* instantiation in the
    hand-written TSMC65 pad ring (the synthesis top)."""
    if not path.is_file():
        raise SourceError(f"pad ring not found at {path}")
    src = path.read_text()
    src = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
    src = re.sub(r"//[^\n]*", "", src)
    out: dict[str, str] = {}
    for m in re.finditer(r"^\s*([A-Za-z_]\w*)\s+(uPAD_\w+)\s*\(", src, re.M):
        out[m.group(2)] = m.group(1)
    if not out:
        raise SourceError(f"parsed zero uPAD_* instances from {path} -- the regex is stale")
    return out


def parse_io_file(path: Path) -> tuple[list[dict], dict[str, list[str]]]:
    """Return (corners, sides).

    corners: one dict per corner -- {name, cell, orientation, corner-side}.
    sides:   side -> [uPAD_* names] IN THE FILE'S OWN ORDER -- this file's own
             header says that order "is faithful to the pin-map ring/side
             data", so it is the floorplan's intended per-side sequence.
    """
    if not path.is_file():
        raise SourceError(f".io floorplan file not found at {path}")
    side_re = re.compile(
        r"^\s*\(\s*(topleft|topright|bottomleft|bottomright|top|bottom|left|right)\s*$")
    inst_re = re.compile(r"\(inst\b([^)]*)\)")
    corners: list[dict] = []
    sides: dict[str, list[str]] = {s: [] for s in SIDES}
    cur = None
    for line in path.read_text().splitlines():
        m = side_re.match(line)
        if m:
            cur = m.group(1)
            continue
        m = inst_re.search(line)
        if not m or cur is None:
            continue
        attrs = m.group(1)
        name_m = re.search(r'name="([^"]+)"', attrs)
        if not name_m:
            continue
        cell_m = re.search(r"cell=(\S+)", attrs)
        orient_m = re.search(r"orientation=(\S+)", attrs)
        entry = {
            "name": name_m.group(1),
            "cell": cell_m.group(1) if cell_m else None,
            "orientation": orient_m.group(1) if orient_m else None,
        }
        if cur in CORNER_SIDES:
            entry["corner"] = cur
            corners.append(entry)
        elif cur in sides:
            sides[cur].append(entry["name"])
    if len(corners) != 4:
        raise SourceError(f"{path} defines {len(corners)} corner insts, expected 4 "
                           f"(topleft/topright/bottomleft/bottomright)")
    if not any(sides.values()):
        raise SourceError(f"parsed zero per-side pad names from {path} -- the parser is stale")
    return corners, sides


def parse_bondpad_tcl(path: Path) -> dict[str, list[str]]:
    """Return {'<side>_pads_<outer|inner>': [uPAD_* names]} exactly as
    place_bondpads.tcl's own `set ... [list ...]` blocks declare them -- this
    is what decides PAD70GU (outer ring) vs PAD70NU (inner ring) per pad, and
    the instance-naming convention (B<name>), for the staggered bond-pad cell
    the actual TSMC tpbn65v library places on top of/beside each IO cell.
    """
    if not path.is_file():
        raise SourceError(f"place_bondpads.tcl not found at {path}")
    text = path.read_text()
    groups: dict[str, list[str]] = {}
    for m in re.finditer(r"set\s+(\w+_pads_(?:outer|inner))\s+\[list(.*?)\]", text, re.S):
        groups[m.group(1)] = re.findall(r"uPAD_\w+", m.group(2))
    expected_keys = {f"{s}_pads_{k}" for s in SIDES for k in ("outer", "inner")}
    missing = expected_keys - groups.keys()
    if missing:
        raise SourceError(f"{path}: missing bond-pad list(s) {sorted(missing)} -- "
                           f"the regex is stale or the file was restructured")
    return groups


class Expected:
    """The padframe this design's own sources say should exist, built fresh
    from pads.v + the .io floorplan file + place_bondpads.tcl every run."""

    def __init__(self) -> None:
        self.pads_v = parse_pads_verilog(PADS_V)
        self.corners, self.io_sides = parse_io_file(IO_FILE)
        self.bondpads = parse_bondpad_tcl(BONDPAD_TCL)

        self.cross_check_errors: list[str] = []
        # side -> ordered list of (uPAD name, functional cell type or None,
        #                          staggered cell type or None)
        self.side_seq: dict[str, list[tuple[str, str | None, str | None]]] = {}

        for side in SIDES:
            outer = set(self.bondpads[f"{side}_pads_outer"])
            inner = set(self.bondpads[f"{side}_pads_inner"])
            seq = []
            for name in self.io_sides[side]:
                fcell = self.pads_v.get(name)
                if fcell is None:
                    self.cross_check_errors.append(
                        f"{name}: on {side} in {IO_FILE.name} but "
                        f"{PADS_V.name} has no instance of that name")
                if name in outer and name in inner:
                    self.cross_check_errors.append(
                        f"{name}: place_bondpads.tcl lists it in BOTH "
                        f"{side}_pads_outer and {side}_pads_inner")
                    scell = "PAD70GU"
                elif name in outer:
                    scell = "PAD70GU"
                elif name in inner:
                    scell = "PAD70NU"
                else:
                    scell = None
                    self.cross_check_errors.append(
                        f"{name}: on {side} in {IO_FILE.name} but "
                        f"place_bondpads.tcl assigns it to neither "
                        f"{side}_pads_outer nor {side}_pads_inner")
                seq.append((name, fcell, scell))
            self.side_seq[side] = seq

            io_names = set(self.io_sides[side])
            for kind in ("outer", "inner"):
                for name in self.bondpads[f"{side}_pads_{kind}"]:
                    if name not in io_names:
                        self.cross_check_errors.append(
                            f"{name}: place_bondpads.tcl's {side}_pads_{kind} names it, "
                            f"but {IO_FILE.name} has no {side}-side entry for it")

        # Every uPAD_* pads.v defines should show up on exactly one side.
        placed = {n for seq in self.side_seq.values() for n, _, _ in seq}
        for name in self.pads_v:
            if name not in placed:
                self.cross_check_errors.append(
                    f"{name}: instantiated in {PADS_V.name} but not placed on any "
                    f"side in {IO_FILE.name}")

        self.corner_cells = {c["cell"] for c in self.corners if c["cell"]}

        # Expected instance counts, by structure name -- corners + every
        # functional pad cell type + every staggered bond-pad cell type.
        self.counts: Counter[str] = Counter()
        for c in self.corners:
            if c["cell"]:
                self.counts[c["cell"]] += 1
        for seq in self.side_seq.values():
            for _name, fcell, scell in seq:
                if fcell:
                    self.counts[fcell] += 1
                if scell:
                    self.counts[scell] += 1

        self.watch_exact = set(self.counts) | self.corner_cells

        # Cross-check the REVIEWED orientation table (above) against what the
        # .io file's corner block names TODAY -- not to source values from it
        # (see the table's own docstring for why not), but so a corner
        # renamed/added/removed in a future floorplan revision is caught as a
        # SourceError rather than the table silently going stale and checking
        # nothing. This is the same "both directions matter" discipline
        # already applied to pads.v/io_file/place_bondpads.tcl above.
        io_corner_names = {c["name"] for c in self.corners}
        table_names = set(EXPECTED_ORIENTATION)
        if io_corner_names != table_names:
            only_io = sorted(io_corner_names - table_names)
            only_table = sorted(table_names - io_corner_names)
            detail = []
            if only_io:
                detail.append(f"{IO_FILE.name} names corner(s) {only_io} that "
                               f"EXPECTED_ORIENTATION does not cover")
            if only_table:
                detail.append(f"EXPECTED_ORIENTATION covers corner(s) {only_table} "
                               f"that {IO_FILE.name} no longer names")
            self.cross_check_errors.append(
                "orientation table is out of step with the floorplan's own corner "
                "list -- " + "; ".join(detail) + " (update the reviewed table by "
                "hand; see its docstring)")


def read_top_cell_name(path: Path) -> str | None:
    if not path.is_file():
        return None
    m = re.search(r"set\s+block_name\s+(\S+)", path.read_text())
    return m.group(1) if m else None


# ---------------------------------------------------------------------------
# 2. GDSII stream parsing. Stdlib only -- no gdstk/gdspy/klayout python module
#    is installed here (checked; only the KLayout GUI binary + a Ruby macro
#    interpreter are on PATH, and this needs to run on plain EDA hosts with no
#    pip). The record-type constants and the "only read a record's body when
#    you are actually going to use it" discipline follow scripts/ci/
#    rom_gds_bits.py and scripts/ci/gds_layer_census.py, the two GDSII
#    stream-readers already in this tree -- a merged tapeout stream is ~300 MB
#    of mostly BOUNDARY/XY data belonging to standard cells and macros that
#    have nothing to do with the padframe, and paying to read all of it here
#    would make this check unusably slow for no benefit.
#
#    THE ONE FACT THIS WHOLE SCRIPT IS BUILT AROUND: GDSII has no instance-
#    name field. An SREF/AREF carries a referenced STRUCTURE name (SNAME) and
#    a transform, nothing else -- confirmed empirically too: `strings` over
#    the reference GDS in this investigation found zero occurrences of any
#    "uPAD_*" instance name anywhere in the file. So every check below is
#    necessarily about structure NAMES, COUNTS, GEOMETRIC POSITION and (for
#    the 4 corners) TRANSFORM -- never about a specific net's identity.
#
#    STRANS/ANGLE/MAG, added alongside XY/COLROW: a GDSII SREF/AREF element's
#    body is, in file order, [ELFLAGS] [PLEX] SNAME [STRANS [MAG] [ANGLE]] XY
#    [COLROW for AREF] {property records} ENDEL -- i.e. the transform record
#    group always comes AFTER SNAME and BEFORE XY, exactly where pend_sname is
#    already known and pend_xy has not been read yet. STRANS is a 2-byte
#    bit-array; bit 15 (0x8000, the MSB) is the reflection ("mirror about X
#    before rotating") flag and is the only STRANS bit this script reads --
#    bits 13/14 (absolute mag/angle) do not change what "the cell's own
#    rotation" means for a comparison against EXPECTED_ORIENTATION. ANGLE is
#    an 8-byte GDSII REAL8 (not IEEE 754): sign in bit 0 of byte 0, a 7-bit
#    excess-64 base-16 exponent, and a 56-bit unsigned mantissa -- decoded by
#    _gds_real8() below. A watched instance with NO STRANS record at all is
#    orientation R0/unmirrored (GDSII's own default for an absent STRANS).
# ---------------------------------------------------------------------------
R_HEADER = 0x00
R_ENDLIB = 0x04
R_BGNSTR = 0x05
R_STRNAME = 0x06
R_ENDSTR = 0x07
R_BOUNDARY = 0x08
R_PATH = 0x09
R_SREF = 0x0A
R_AREF = 0x0B
R_TEXT = 0x0C
R_LAYER = 0x0D
R_XY = 0x10
R_ENDEL = 0x11
R_SNAME = 0x12
R_COLROW = 0x13
R_NODE = 0x15
R_STRANS = 0x1A
R_MAG = 0x1B
R_ANGLE = 0x1C
R_BOX = 0x2D

_GEOM_RTYPES = (R_BOUNDARY, R_PATH, R_BOX, R_NODE)

# Instances this run should try to read a live orientation transform for.
# Restricted to the 4 corner names, deliberately: they are the only
# placements this script can uniquely identify (one PCORNER_G per die
# corner, self-calibrated the same way classify_sides() calibrates edges),
# so they are the only ones an EXPECTED_ORIENTATION entry can be diffed
# against without guessing which of several same-typed placements on an edge
# a given transform belongs to.
ORIENTATION_WATCH_CELLS = {v["cell"] for v in EXPECTED_ORIENTATION.values()}


def _gds_real8(b: bytes) -> float:
    """Decode an 8-byte GDSII REAL8 (excess-64, base-16 exponent) to float.

    Not IEEE 754 -- GDSII's own float format, used by ANGLE and MAG. Only
    values this script needs to compare are whole degrees (0/90/180/270), so
    precision beyond that is not a concern, but the decode itself must be
    exact or a real ANGLE=180.0 could misread as e.g. 179.99999.
    """
    if len(b) != 8:
        return 0.0
    sign = -1.0 if (b[0] & 0x80) else 1.0
    exponent = (b[0] & 0x7F) - 64
    mantissa = int.from_bytes(b[1:8], "big")
    if mantissa == 0:
        return 0.0
    return sign * (mantissa / (1 << 56)) * (16.0 ** exponent)


class GdsFindings:
    def __init__(self) -> None:
        self.defined: set[str] = set()
        self.near_miss: set[str] = set()
        # watched structure's OWN definition: layer -> geometry record count
        self.geom_layers: dict[str, Counter[int]] = defaultdict(Counter)
        self.nested_refs: Counter[str] = Counter()
        # every direct (top-cell) placement of a watched cell:
        # {cell, x, y, kind, colrow, angle_deg, mirror}
        self.top_children: list[dict] = []
        self.top_child_total = 0
        self.aref_watched = 0
        self.seen_header = False
        self.seen_endlib = False
        self.top_found = False


def scan_gds(path: Path, top_name: str, watch_exact: set[str]) -> GdsFindings:
    f = GdsFindings()
    size = os.path.getsize(path)

    cur_struct: str | None = None
    in_top = False
    in_watched_def: str | None = None
    elem_kind: str | None = None  # 'geo' | 'txt' | None, for the OPEN element

    pend_kind: int | None = None
    pend_sname: str | None = None
    pend_xy: tuple[int, int] | None = None
    pend_colrow: tuple[int, int] | None = None
    pend_mirror: bool = False
    pend_angle: float = 0.0

    with open(path, "rb", buffering=1 << 20) as fh:
        while True:
            head = fh.read(4)
            if len(head) < 4:
                break
            length = struct.unpack(">H", head[:2])[0]
            rtype = head[2]
            if length < 4:
                raise GdsError(f"corrupt GDSII in {path}: record at byte "
                                f"{fh.tell() - 4} declares length {length} "
                                f"(minimum is 4)")
            if length % 2:
                raise GdsError(f"corrupt GDSII in {path}: record at byte "
                                f"{fh.tell() - 4} declares an odd length {length}")
            body_len = length - 4

            if rtype == R_HEADER:
                f.seen_header = True

            need_sname = (rtype == R_SNAME and pend_kind is not None
                          and (in_top or in_watched_def is not None))
            need_xy = (rtype == R_XY and in_top and pend_kind is not None
                       and pend_sname in watch_exact)
            need_colrow = (rtype == R_COLROW and in_top and pend_kind == R_AREF
                           and pend_sname in watch_exact)
            need_layer = (rtype == R_LAYER and in_watched_def is not None
                          and elem_kind == "geo")
            # STRANS/ANGLE come after SNAME, before XY -- read them only for
            # the orientation-watched cells (corners), and only under the top
            # cell, same scoping as need_xy.
            need_strans = (rtype == R_STRANS and in_top and pend_kind is not None
                           and pend_sname in ORIENTATION_WATCH_CELLS)
            need_angle = (rtype == R_ANGLE and in_top and pend_kind is not None
                          and pend_sname in ORIENTATION_WATCH_CELLS)
            need_body = body_len > 0 and (
                rtype == R_STRNAME or need_sname or need_xy or need_colrow
                or need_layer or need_strans or need_angle)

            if need_body:
                body = fh.read(body_len)
                if len(body) != body_len:
                    raise GdsError(f"truncated GDSII in {path}: a record near byte "
                                    f"{fh.tell()} claims {body_len} bytes of payload "
                                    f"and the file ends after {len(body)}")
            else:
                body = b""
                if body_len:
                    fh.seek(body_len, os.SEEK_CUR)

            if rtype == R_STRNAME:
                name = body.rstrip(b"\x00").decode("ascii", "replace")
                cur_struct = name
                f.defined.add(name)
                if name.startswith(WATCH_PREFIXES) and name not in watch_exact:
                    f.near_miss.add(name)
                in_top = (name == top_name)
                if in_top:
                    f.top_found = True
                in_watched_def = name if name in watch_exact else None
                pend_kind = pend_sname = pend_xy = pend_colrow = None
                pend_mirror, pend_angle = False, 0.0
                elem_kind = None

            elif rtype == R_ENDSTR:
                cur_struct = None
                in_top = False
                in_watched_def = None
                pend_kind = pend_sname = pend_xy = pend_colrow = None
                pend_mirror, pend_angle = False, 0.0
                elem_kind = None

            elif rtype == R_ENDLIB:
                f.seen_endlib = True
                break

            elif rtype in (R_SREF, R_AREF):
                pend_kind = rtype
                pend_sname = None
                pend_xy = None
                pend_colrow = None
                pend_mirror, pend_angle = False, 0.0

            elif rtype == R_SNAME:
                if need_sname:
                    pend_sname = body.rstrip(b"\x00").decode("ascii", "replace")

            elif rtype == R_STRANS and need_strans:
                if body_len >= 2:
                    bits = struct.unpack(">H", body[:2])[0]
                    pend_mirror = bool(bits & 0x8000)

            elif rtype == R_ANGLE and need_angle:
                if body_len >= 8:
                    pend_angle = _gds_real8(body[:8])

            elif rtype == R_XY and need_xy:
                if body_len == 8:
                    pend_xy = struct.unpack(">ii", body)
                elif body_len >= 8:
                    # AREF's XY carries 3 points (origin + 2 axis corners);
                    # the origin is enough to bucket it to an edge.
                    pend_xy = struct.unpack(">ii", body[:8])

            elif rtype == R_COLROW and need_colrow:
                if body_len == 4:
                    pend_colrow = struct.unpack(">hh", body)

            elif rtype in _GEOM_RTYPES:
                elem_kind = "geo"
            elif rtype == R_TEXT:
                elem_kind = "txt"

            elif rtype == R_LAYER and need_layer:
                if body_len >= 2:
                    lay = struct.unpack(">h", body[:2])[0]
                    f.geom_layers[in_watched_def][lay] += 1

            elif rtype == R_ENDEL:
                if in_top and pend_kind is not None:
                    f.top_child_total += 1
                    if pend_sname in watch_exact:
                        if pend_kind == R_AREF:
                            f.aref_watched += 1
                        f.top_children.append({
                            "cell": pend_sname,
                            "xy": pend_xy,
                            "kind": "aref" if pend_kind == R_AREF else "sref",
                            "colrow": pend_colrow,
                            "angle_deg": (round(pend_angle) % 360
                                          if pend_sname in ORIENTATION_WATCH_CELLS
                                          else None),
                            "mirror": (pend_mirror
                                       if pend_sname in ORIENTATION_WATCH_CELLS
                                       else None),
                        })
                elif in_watched_def is not None and pend_kind is not None:
                    f.nested_refs[in_watched_def] += 1
                pend_kind = pend_sname = pend_xy = pend_colrow = None
                pend_mirror, pend_angle = False, 0.0
                elem_kind = None

    if not f.seen_header:
        raise GdsError(f"{path} does not begin with a GDSII HEADER record -- "
                        f"it is not a GDSII stream, or not the one intended")
    if not f.seen_endlib:
        raise GdsError(f"{path} ends without an ENDLIB record ({size} bytes read). "
                        f"The stream is truncated.")
    return f


# ---------------------------------------------------------------------------
# 3. Compare: names + counts, then per-side order, then corner orientation.
# ---------------------------------------------------------------------------
def classify_sides(top_children: list[dict]):
    """Self-calibrate the die's 4 edges from the padframe placements THEMSELVES
    (never from a hard-coded floorplan size), then bucket every placement to
    its nearest edge. Returns (side_of_fn, notes) where
    side_of_fn(x, y) -> 'top'|'left'|'bottom'|'right', or (None, notes) if
    there are not enough placements with a usable XY to calibrate from.

    Deliberately NOT calibrated from the 4 corner-cell (PCORNER_G) placements
    alone: measured on the reference GDS, PCORNER_G's own placement origin
    sits ~135um INSET from the true die edge on both axes (its LEF origin is
    not at the cell's outer corner), while the ordinary pad cells sit exactly
    on the edge (x=0/x=die_width, y=0/y=die_height). Calibrating from corners
    alone put every edge ~135um in the wrong place and misclassified pads
    near a corner onto the wrong side -- a bug in this heuristic, not a
    defect in the chip. Calibrating from the full population of padframe
    placements (all ~164 pad-cell instances, corners included) is immune to
    one cell family's origin convention being different from the rest.
    """
    pts = [c["xy"] for c in top_children if c["xy"] is not None]
    if len(pts) < 8:
        return None, [f"only {len(pts)} padframe placement(s) with a usable XY were "
                       f"found directly under the top cell -- cannot self-calibrate "
                       f"the die edges to check padframe order"]
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    left_x, right_x = min(xs), max(xs)
    bottom_y, top_y = min(ys), max(ys)
    notes = []

    def side_of(x: int, y: int) -> str:
        d = {
            "left": abs(x - left_x),
            "right": abs(x - right_x),
            "bottom": abs(y - bottom_y),
            "top": abs(y - top_y),
        }
        return min(d, key=d.get)

    return side_of, notes


def classify_corner(x: int, y: int, left_x: int, right_x: int,
                     bottom_y: int, top_y: int) -> str:
    """Which of the 4 die corners (topleft/topright/bottomleft/bottomright)
    an (x, y) placement is nearest -- same bounding-box calibration
    classify_sides() uses, just resolving to a CORNER instead of an EDGE, so
    a PCORNER_G placement can be matched to its EXPECTED_ORIENTATION entry
    without depending on GDSII instance names (which do not exist -- see the
    module docstring)."""
    candidates = {
        "topleft": (left_x, top_y),
        "topright": (right_x, top_y),
        "bottomleft": (left_x, bottom_y),
        "bottomright": (right_x, bottom_y),
    }
    return min(candidates, key=lambda k: (x - candidates[k][0]) ** 2
                                          + (y - candidates[k][1]) ** 2)


def sequences_match(observed: list[str], expected: list[str]) -> bool:
    """Accept either direction: geometry alone does not say which physical
    direction the source list's "first" entry corresponds to."""
    return observed == expected or observed == list(reversed(expected))


def run_check(gds_path: Path, top_override: str | None) -> tuple[int, dict]:
    exp = Expected()
    report: dict = {"gds": str(gds_path), "problems": [], "info": []}

    if exp.cross_check_errors:
        report["problems"].append(
            {"kind": "source-inconsistency",
             "detail": exp.cross_check_errors})

    top_name = top_override or read_top_cell_name(CONFIG_TCL)
    if not top_name:
        raise SourceError(f"could not determine the design's top-cell name -- "
                           f"no 'set block_name ...' in {CONFIG_TCL}, and no --top given")
    report["top_cell"] = top_name

    findings = scan_gds(gds_path, top_name, exp.watch_exact)
    if not findings.top_found:
        report["problems"].append(
            {"kind": "no-top-cell",
             "detail": [f"no structure named '{top_name}' is DEFINED anywhere in "
                        f"{gds_path} -- wrong --top, or this stream is not (or no "
                        f"longer contains) this design's top cell"]})
        return EXIT_MISMATCH, report

    # ---- name + count -----------------------------------------------------
    observed_counts: Counter[str] = Counter(c["cell"] for c in findings.top_children)
    name_problems = []
    for cell, want in sorted(exp.counts.items()):
        got = observed_counts.get(cell, 0)
        defined = cell in findings.defined
        entry = {"cell": cell, "expected": want, "observed": got, "defined": defined}
        if got != want or not defined:
            reasons = []
            if got == 0:
                reasons.append("never placed under the top cell")
            elif got != want:
                reasons.append(f"placed {got} time(s), expected {want}")
            if not defined:
                reasons.append("no structure with this name is DEFINED anywhere in "
                                "the stream (a dangling/absent reference, or the "
                                "structure was dropped by the merge)")
            entry["problem"] = "; ".join(reasons)
            name_problems.append(entry)
    if name_problems:
        report["problems"].append({"kind": "name-or-count", "detail": name_problems})
    report["counts"] = {cell: {"expected": want, "observed": observed_counts.get(cell, 0),
                                "defined": cell in findings.defined}
                         for cell, want in sorted(exp.counts.items())}

    if findings.near_miss:
        report["problems"].append(
            {"kind": "misnamed-or-unexpected",
             "detail": sorted(findings.near_miss)})

    if findings.aref_watched:
        report["problems"].append(
            {"kind": "aref-placement",
             "detail": [f"{findings.aref_watched} padframe-family placement(s) were "
                        f"made via AREF (array reference), not SREF -- this decode "
                        f"only resolves one representative point per AREF and cannot "
                        f"confirm the array's per-cell count or position"]})

    # ---- per-side order -----------------------------------------------------
    side_of, calib_notes = classify_sides(findings.top_children)
    report["info"].extend(calib_notes)
    if side_of is None:
        report["problems"].append({"kind": "order-uncheckable", "detail": calib_notes})
    else:
        for side in SIDES:
            expected_seq = exp.side_seq[side]
            exp_fcells = [f for _n, f, _s in expected_seq if f]
            exp_scells = [s for _n, _f, s in expected_seq if s]

            bucketed = [c for c in findings.top_children
                        if c["xy"] is not None and side_of(*c["xy"]) == side]
            fcell_types = {f for _n, f, _s in expected_seq if f}
            scell_types = {s for _n, _f, s in expected_seq if s}
            obs_f = sorted((c for c in bucketed if c["cell"] in fcell_types),
                            key=lambda c: c["xy"])
            obs_s = sorted((c for c in bucketed if c["cell"] in scell_types),
                            key=lambda c: c["xy"])
            obs_f_types = [c["cell"] for c in obs_f]
            obs_s_types = [c["cell"] for c in obs_s]

            side_problems = []
            if len(obs_f_types) != len(exp_fcells):
                side_problems.append(
                    f"{side}: {len(obs_f_types)} functional pad cell(s) found on this "
                    f"edge, expected {len(exp_fcells)}")
            elif not sequences_match(obs_f_types, exp_fcells):
                side_problems.append(
                    f"{side}: functional pad cell-type sequence does not match the "
                    f"floorplan's intended order (forward or reversed)\n"
                    f"    expected: {exp_fcells}\n"
                    f"    observed: {obs_f_types}")
            if len(obs_s_types) != len(exp_scells):
                side_problems.append(
                    f"{side}: {len(obs_s_types)} staggered bond-pad cell(s) found on "
                    f"this edge, expected {len(exp_scells)}")
            elif not sequences_match(obs_s_types, exp_scells):
                side_problems.append(
                    f"{side}: staggered bond-pad cell-type sequence does not match "
                    f"the floorplan's intended order (forward or reversed)\n"
                    f"    expected: {exp_scells}\n"
                    f"    observed: {obs_s_types}")
            if side_problems:
                report["problems"].append({"kind": "padframe-order", "detail": side_problems})

        # ---- corner orientation ---------------------------------------------
        # Only possible once side_of's bounding box exists -- classify_corner()
        # reuses the same calibration. Every watched-cell placement whose type
        # is one of ORIENTATION_WATCH_CELLS (today: just PCORNER_G) is matched
        # to its nearest die corner, and diffed against EXPECTED_ORIENTATION.
        pts = [c["xy"] for c in findings.top_children if c["xy"] is not None]
        xs, ys = [p[0] for p in pts], [p[1] for p in pts]
        left_x, right_x = min(xs), max(xs)
        bottom_y, top_y = min(ys), max(ys)

        by_name = {v["cell"]: {} for v in EXPECTED_ORIENTATION.values()}
        for c in findings.top_children:
            if c["cell"] not in ORIENTATION_WATCH_CELLS or c["xy"] is None:
                continue
            corner_pos = classify_corner(c["xy"][0], c["xy"][1],
                                          left_x, right_x, bottom_y, top_y)
            by_name[c["cell"]].setdefault(corner_pos, []).append(c)

        orient_problems = []
        orient_report = {}
        for inst_name, exp_entry in sorted(EXPECTED_ORIENTATION.items()):
            cell = exp_entry["cell"]
            corner_pos = exp_entry["corner"]
            placements = by_name.get(cell, {}).get(corner_pos, [])
            key = f"{inst_name} ({cell} @ {corner_pos})"
            if not placements:
                # Already reported under name-or-count / padframe-order if the
                # cell is simply missing altogether; here specifically no
                # placement landed in the EXPECTED corner bucket, which is a
                # distinct fault (e.g. two corners swapped positions).
                orient_problems.append(
                    f"{key}: no {cell} placement found nearest the {corner_pos} "
                    f"die corner -- cannot check its orientation")
                orient_report[inst_name] = {"expected_angle": exp_entry["angle_deg"],
                                             "expected_mirror": exp_entry["mirror"],
                                             "observed": None}
                continue
            if len(placements) > 1:
                orient_problems.append(
                    f"{key}: {len(placements)} {cell} placements bucket to this "
                    f"corner (expected exactly 1) -- orientation check is on the "
                    f"first by placement order, but this is itself a padframe-order "
                    f"defect")
            p = placements[0]
            got_angle = p["angle_deg"] if p["angle_deg"] is not None else 0
            got_mirror = bool(p["mirror"])
            orient_report[inst_name] = {"expected_angle": exp_entry["angle_deg"],
                                         "expected_mirror": exp_entry["mirror"],
                                         "observed_angle": got_angle,
                                         "observed_mirror": got_mirror}
            if got_angle != exp_entry["angle_deg"] or got_mirror != exp_entry["mirror"]:
                orient_problems.append(
                    f"{key}: placed at ANGLE={got_angle} mirror={got_mirror}, "
                    f"expected ANGLE={exp_entry['angle_deg']} "
                    f"mirror={exp_entry['mirror']} -- {exp_entry['why']}")
        report["corner_orientation"] = orient_report
        if orient_problems:
            report["problems"].append({"kind": "orientation-mismatch",
                                        "detail": orient_problems})

    # ---- geometry content, informational only --------------------------------
    geom_info = {}
    for cell in sorted(exp.watch_exact):
        layers = findings.geom_layers.get(cell)
        nested = findings.nested_refs.get(cell, 0)
        geom_info[cell] = {
            "geometry_records": sum(layers.values()) if layers else 0,
            "distinct_layers": sorted(layers) if layers else [],
            "nested_refs": nested,
        }
    report["geometry"] = geom_info

    report["top_child_total"] = findings.top_child_total
    ok = not report["problems"]
    return (EXIT_OK if ok else EXIT_MISMATCH), report


# ---------------------------------------------------------------------------
# 4. Reporting
# ---------------------------------------------------------------------------
def print_report(report: dict) -> None:
    print(f"padring_gds '{report.get('top_cell', '?')}' <- {report['gds']}")
    counts = report.get("counts", {})
    n_ok = sum(1 for v in counts.values() if v["expected"] == v["observed"] and v["defined"])
    print(f"  cell families checked : {len(counts)}  ({n_ok} name+count OK)")
    print(f"  top-cell placements   : {report.get('top_child_total', 0)} total "
          f"(all cell types, direct children only)")

    orient = report.get("corner_orientation", {})
    if orient:
        n_orient_ok = sum(1 for v in orient.values()
                           if v.get("observed_angle") == v.get("expected_angle")
                           and v.get("observed_mirror") == v.get("expected_mirror"))
        print(f"  corner orientation    : {len(orient)} corner(s) checked "
              f"({n_orient_ok} OK)")
        for name in sorted(orient):
            v = orient[name]
            if "observed_angle" not in v:
                print(f"    {name:18s} UNRESOLVED -- {v}")
                continue
            mark = "OK" if (v["observed_angle"] == v["expected_angle"]
                             and v["observed_mirror"] == v["expected_mirror"]) else "MISMATCH"
            print(f"    {name:18s} expected ANGLE={v['expected_angle']:>3d} "
                  f"mirror={v['expected_mirror']!s:<5s}  observed ANGLE="
                  f"{v['observed_angle']:>3d} mirror={v['observed_mirror']!s:<5s}  {mark}")

    empty = [c for c, g in report.get("geometry", {}).items() if g["geometry_records"] == 0]
    nonempty = [c for c, g in report.get("geometry", {}).items() if g["geometry_records"] > 0]
    print(f"  geometry (informational, not gated): {len(nonempty)} watched structure(s) "
          f"carry BOUNDARY/PATH/BOX geometry, {len(empty)} are entirely empty")
    for c in sorted(nonempty):
        g = report["geometry"][c]
        print(f"    {c:14s} {g['geometry_records']:6d} geometry record(s) on "
              f"{len(g['distinct_layers'])} layer(s) {g['distinct_layers']}"
              + (f", {g['nested_refs']} nested ref(s)" if g["nested_refs"] else ""))
    if empty:
        print(f"    empty (no own geometry at all): {sorted(empty)}")

    for note in report.get("info", []):
        print(f"  note: {note}")

    if not report["problems"]:
        print(f"  OK -- every expected pad/corner/bond-pad name, count, per-side "
              f"type order and corner orientation matches the floorplan sources")
        return

    print(f"\npadring_gds: {len(report['problems'])} problem group(s):", file=sys.stderr)
    for grp in report["problems"]:
        print(f"  [{grp['kind']}]", file=sys.stderr)
        for line in grp["detail"]:
            for sub in str(line).splitlines():
                print(f"    {sub}", file=sys.stderr)


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                  formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--gds", required=True, help="the streamed GDSII to check")
    ap.add_argument("--top", help="override the design top-cell name "
                                   "(default: config.tcl's block_name)")
    ap.add_argument("--json", help="also write the full machine-readable report here")
    args = ap.parse_args(argv)

    gds_path = Path(args.gds)
    if not gds_path.exists():
        print(f"padring_gds: no GDSII at {gds_path}", file=sys.stderr)
        return EXIT_USAGE
    if gds_path.stat().st_size == 0:
        print(f"padring_gds: {gds_path} is empty (0 bytes)", file=sys.stderr)
        return EXIT_USAGE

    try:
        code, report = run_check(gds_path, args.top)
    except SourceError as exc:
        print(f"padring_gds: source error: {exc}", file=sys.stderr)
        return EXIT_USAGE
    except GdsError as exc:
        print(f"padring_gds: GDS error: {exc}", file=sys.stderr)
        return EXIT_USAGE

    print_report(report)

    if args.json:
        with open(args.json, "w") as fh:
            json.dump(report, fh, indent=2, default=list)
        print(f"\n# full report -> {args.json}", file=sys.stderr)

    return code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
