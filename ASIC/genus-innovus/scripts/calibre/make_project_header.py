#!/usr/bin/env python3
# ---------------------------------------------------------------------------
# make_project_header.py --- derive the project DRC deck header from the
# read-only foundry deck, instead of keeping a copy of it in a public repo.
#
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access
# license.  Copyright 2026, SoC Labs (www.soclabs.org)
# ---------------------------------------------------------------------------
# WHY THIS FILE EXISTS
#
# The project deck needs its own switch block: WLCSP_SEALRING must be OFF (we
# are wire bond) and is #DEFINEd unconditionally, and xLB/yLB/xRT/yRT are
# declared unconditionally as VARIABLE -- neither is reachable from a wrapper,
# so make_project_deck.sh splices a project header in front of the foundry
# rule bodies.  See that script's header for the splice argument.
#
# The obvious way to get that header is to copy the foundry deck's switch
# block and edit it.  That is what this repository did, in
# scripts/calibre/tsmc65_minisic_header.svrf.in, and 156 of that file's 418
# non-blank lines were byte-identical to the foundry deck -- including TSMC's
# own comments.  The file even said so: "it is reproduced verbatim so this
# header stays a faithful, diffable copy of the foundry block."
#
# github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet is PUBLIC and TSMC's licence
# does not permit redistributing their collateral, so that file could not be
# committed.  This script is the same answer the repository already gave for
# the IO-driver LEF (ASIC/tech_wrappers/tsmc65/scripts/patch_pad_lef.py, commit
# bf619f1) and for the stream-out map (scripts/gdsmap_derive.py): SHIP THE
# TRANSFORM, NOT THE RESULT.  The vendor bytes are read from the read-only PDK
# at build time and written into a gitignored work directory; what is committed
# is the seventeen edits we make to them, and the reason for each.
#
# It is also better engineering than a copy, for the reason
# ASIC/asic-toolkit/tech/tsmc65/derive.tcl gives: a transcribed block is
# correct on the day it is typed and nothing checks it again.  When the deck
# revs, a copy goes quietly wrong.  This script cannot: every edit below
# asserts it matched EXACTLY ONCE, and a deck revision that renames or removes
# a switch fails the build by name instead of silently dropping the edit.
#
# WHAT IS ALLOWED TO BE IN THIS FILE
#
# Structure only, per derive.tcl: switch NAMES (WLCSP_SEALRING, ChipWindowUsed,
# LP) and rule NAMES (PO.R.8, CSR.EN.5, M6.DN.1) stay -- they appear in every
# violation report and in public literature and they reconstruct nothing.
# Foundry-derived VALUES -- GDS layer numbers and datatypes, layer/metal
# mappings, dimensions, densities -- and verbatim vendor text do not appear
# here at all, and neither do foundry deck line numbers, which are pointers
# into vendor material.  Where a note needs one, it names the vendor file to
# read it in.
#
# OUR OWN measurements are not foundry collateral and are quoted freely:
# result counts from our runs, our die box, our net names, our cell counts.
#
# Usage (normally via make_project_deck.sh, which is called by `make drc`):
#   make_project_header.py --foundry-deck <deck> -o <header.svrf.in>
#
# Emits the header with @@TOPCELL@@ / @@XLB@@ / @@YLB@@ / @@XRT@@ / @@YRT@@
# placeholders still in it: make_project_deck.sh substitutes them at splice
# time, and already refuses to emit a deck with any placeholder surviving.
# Keeping that division means this script needs no knowledge of the design.
# ---------------------------------------------------------------------------

import argparse
import re
import sys

SWITCH_START = re.compile(r"^/\* SWITCH DEFINITION START \*/")
SWITCH_END = re.compile(r"^/\* SWITCH DEFINITION END \*/")


# ---------------------------------------------------------------------------
# OUR BANNER.  Replaces TSMC's own file banner, which is not reproduced.
# ---------------------------------------------------------------------------
BANNER = """\
//****************************************************************************************
//* PROJECT-OWNED DECK HEADER --- @@TOPCELL@@
//*
//* *** GENERATED FILE --- DO NOT EDIT, AND DO NOT COMMIT. ***
//* Produced by scripts/calibre/make_project_header.py from the read-only
//* foundry deck.  Edit the generator, not this file: a change made here is
//* overwritten on the next `make drc`, and this file carries foundry text that
//* must not enter a public repository.
//*
//* *** THIS IS ALSO A TEMPLATE. IT IS NOT A RUNNABLE DECK. ***
//* Every doubled-at placeholder below is substituted by make_project_deck.sh at
//* splice time from the project manifest, ASIC/genus-innovus/drc_project.mk:
//*     @@TOPCELL@@   $(BLOCK)                       -- top cell, and every
//*                                                     result filename
//*     @@XLB@@ @@YLB@@ @@XRT@@ @@YRT@@
//*                   $(DRC_DIE_*)                   -- the ChipWindow, read in
//*                                                     turn out of
//*                                                     scripts/floorplan.tcl
//* SUBSTITUTION HAPPENS AT ASSEMBLY, NOT IN CALIBRE. It has to: SVRF expands
//* environment variables in FILE PATH strings only, never in cell-name strings
//* -- see the note at LAYOUT PRIMARY near the bottom of this file. A $VAR in a
//* cell name would be read as a literal cell called '$VAR'.
//* make_project_deck.sh refuses to emit a deck with any placeholder left in it.
//*
//* This replaces the foundry deck's banner and its whole SWITCH DEFINITION
//* block; everything after the block's END marker is spliced on verbatim from
//* the foundry file by make_project_deck.sh, so the actual rule bodies are
//* always TSMC's, always current, and never copied into this repository.
//* The foundry deck is READ-ONLY lab-wide collateral and is NOT modified.
//*
//* DESIGN CONTEXT THIS HEADER IS TUNED FOR
//*   process     CLN65LP (tcbn65lp std cells, tphn65lpgv2od3_sl IO)
//*   stack       9M 6X1Z1U, thin-AP option
//*   die         (@@XLB@@,@@YLB@@)-(@@XRT@@,@@YRT@@) um, top cell @@TOPCELL@@
//*   assembly    WIRE BOND (Europractice mini@sic --- no flip chip, no WLCSP)
//*   submission  black box: std cells / IO / bond pads are LEF abstracts,
//*               memories are real vendor GDS
//*   seal ring   NOT in our GDS (TSMC adds it)
//*   CB          the passivation-opening layer is absent from our stream
//*               entirely (it is not in tpbn65v's LEF)
//*
//* Every deviation from the foundry default is marked  [DEVIATION]  with a reason.
//* Every switch deliberately LEFT at its foundry default that someone might
//* expect us to change is marked  [KEPT]  with a reason.
//****************************************************************************************
"""


# ---------------------------------------------------------------------------
# OUR NOTES.  Each is anchored to a switch by NAME below.  This is the prose
# that used to be interleaved into the copied block; it is the part of that
# file that was actually ours, and it is the part worth keeping.
# ---------------------------------------------------------------------------
NOTE_PAD_BY_TEXT = """\
// [KEPT OFF --- and the reason is NOT the one previously written here]
// The mini@sic guide says to use this switch when you only have abstracts/LEF of
// the bond pads, which IS our situation: pads are otherwise recognised by the
// passivation-opening layer, and that layer is absent from our stream entirely
// because it is not in tpbn65v's LEF. So text is the only pad-recognition route
// we have. It still cannot be turned on, for a reason that is a property of the
// STREAM, not of the text:
//
//  1. SVRF `?` IS NOT A SINGLE-CHARACTER WILDCARD. SVRF manual, With Text, name
//     argument: "which can contain one or more question mark (?) characters. The
//     ? is a wildcard character that matches ZERO OR MORE characters."
//     (v2022.4 p.2805 and v2023.4 htmldocs Command_WithText; our Calibre
//     v2023.1_18.8 sits between them.) So the three VARIABLEs below are not
//     placeholders at all --- they are working patterns. "VDD?" already matches
//     VDD and VDDIO; "VSS?" already matches VSS and VSSIO; and "?" matches EVERY
//     text object in the design.
//
//  2. Our top cell carries 48 text labels, all on one metal's pin-name layer,
//     all of them top-level PIN names (CLK, NRST, RMII_*, TL_*, QSPI_*, SWD*,
//     HOSTIO4_P1[*]); there is no power text anywhere in the top cell. So with
//     the switch on, the deck's derived pad-by-text layer is NON-empty and the
//     GND_*/PWR_* layers are empty. Measured 2026-08-10 on the honest-full-pnr2
//     stream: off = 2,509 results with LUP.* = 0; on = 8,509 results, 6 rulechecks
//     capped at 1000, LUP.* true count 222,350.
//
//  3. The 222,350 is NOT fixed by adding power text --- it is replaced by a false
//     clean. write_stream emits LEF OBS onto the real metal layers (the foundry
//     GDS-out map routes a metal's LEFPIN, PIN, NET, SPNET, VIA *and* LEFOBS to
//     the SAME GDS layer and datatype --- row values not reproduced here, TSMC
//     licence forbids it; read them in
//     the Innovus GDS-out map for this metal option, under your own PDK
//     licence --- `pdk_paths.sh gdsout-map` prints its path) and
//     every IO cell's OBS is one full-footprint rectangle per layer,
//     so the pad ring is one polygon: merging that metal over the left 200um strip
//     of the die gives ONE shape of 291,821 um^2 containing every signal pin label
//     and every power pad location. Measured with census rulechecks that COPY the
//     deck's own derived layers (all four runs 2026-08-10, honest-full-pnr2):
//        stream                          PAD_Mxiu  PSD_PAD_TEXT  PSD_VDD_VSS  LUP.*
//        as built (48 signal labels)     176 (249)   2,396,055           0   222,350
//        + VDD/VSS on core power grid    176 (249)   2,396,055   2,396,055        0
//        + VDD/VSS/VDDIO/VSSIO on ring   176 (249)   2,396,055   2,396,055        0
//     The 2,396,055 P+ diffusion polygons reachable from the 48 SIGNAL pins are
//     the identical set reachable from the core VDD/VSS grid. Signal pads, VDD and
//     VSS are one electrical node here, so PSD_IOPAD = PSD_PAD_TEXT NOT
//     PSD_VDD_VSS_PAD_TEXT is empty, POST_DRIVER_ACT is empty and every LUP check
//     reads 0. Pad-by-text cannot separate a signal pad from a supply pad in this
//     stream, in either direction.
//
// ESD.1g additionally documents a swap that is real but inert for us: with the
// switch OFF it excludes devices connected to {PW STRAP NOT RW}; with it ON it
// excludes devices whose net carries VSS text, via
//   NET AREA RATIO ... OVER GND_M*_BY_TEXT == 0
// and `== 0` is the one constraint SVRF allows with an empty denominator (SVRF
// manual, Net Area Ratio: "Y is 0, n is 1, and the constraint is exactly
// specified as == 0"), so an empty GND set excludes nothing. It scores 0 here
// only because every HV device in the design lives in an abstract IO cell and so
// has no geometry in the stream at all.
//
// TO ACTUALLY USE IT the stream has to change, not the deck: stream LEF OBS to
// a non-metal layer (as ASIC/lvs-flow/lvs_pg_emit.tcl already does for LVS,
// moving LEFOBS to <layer>+9000) so the ring stops being one node, and add
// NAME <layer>/SPNET rows so Innovus emits the supply names as text."""

NOTE_PAD_TEXT_VARS = """\
// Set explicitly rather than inherited, so the values are reviewable. These are
// the foundry defaults and, given ? = "zero or more characters", they are already
// correct for this design's four P&R supply nets --- VDD, VSS, VDDIO, VSSIO.
// (VDDACC / VDDPST / VSSPST are RTL/pad-cell PIN names, not nets: the P&R netlist
// has only .VDD(VDD), .VSS(VSS), .VDDPST(VDDIO), .VSSPST(VSSIO).)"""

NOTE_MIXED_SCHEME = """\
// [KEPT OFF] Our stream is pure NEW scheme --- verified by a full layer/datatype
// census of the GDS: every upper-metal and via layer carries ONLY its new-scheme
// datatype, and there is no old-scheme geometry anywhere. That matches the Innovus
// stream-out map we use. Per-layer GDS layer:datatype pairs not reproduced here ---
// TSMC licence forbids it. Source: the Innovus GDS-out map for this metal
// option (`pdk_paths.sh gdsout-map` prints its path);
// re-run the census against that map before trusting this line. Turning MIXED_SCHEME
// on would additionally admit the old-scheme datatypes as real metal and as dummy,
// which for us would only widen the door for mis-mapped geometry to pass unnoticed."""

NOTE_FULL_CHIP = """\
// [KEPT ON] Chip-level design. Note this is the ONLY guard on PO.R.8 --- the deck's
// floating-gate block sits inside the #IFDEF FULL_CHIP region.
// Turning it off would indeed delete our 691 PO.R.8 results --- and with them the
// ENTIRE seal-ring and chip-corner family (every CSR.*, every SR.*), the AP/PM/CB
// far-back-end checks, all nine DM*.EN.1 / DM*.R.1 dummy-metal checks, CDU.R.1,
// the M9/OD/PO density checks and ESD.WARN.1. That is not a floating-gate switch,
// it is the difference between a chip-level and a block-level sign-off. Leave ON."""

NOTE_LP = """\
// [DEVIATION --- foundry default is OFF]
// This design is CLN65LP throughout (tcbn65lp std cells, tphn65lpgv2od3_sl IO).
// The shipped deck leaves LP commented out and never defines it itself. Without it
// the deck checks the wrong dummy-poly variants --- it UNSELECTs the general
// DPO.W.1 / DPO.S.1/2/3 and substitutes the `.A` forms only under #IFDEF LP --- and
// skips the N65LP HVD_N block entirely."""

NOTE_HALF_NODE_VAR = """\
// Kept only so the switch structure of this header still lines up with the deck's.
// Inert: HALF_NODE is off, the variable is empty, and the deck restricts it to N55
// anyway. Nothing here carries a rule value; where the deck's own values matter,
// read them in the deck -- TSMC licence forbids reproducing them in this repo."""

NOTE_28K_AP = """\
// [KEPT OFF] We use the THIN AP option; this switch selects the THICK one. It sets
// the deck's AP-thickness variable, and OFF is correct for us. Leaving it off also
// keeps the thick-AP-only rules AP.W.3.WB and the AP_S_6 family out of the run,
// which is right --- they do not apply to a thin AP.
// Vendor deck thickness values and their locations in the deck not reproduced ---
// TSMC licence forbids it. Source: the mini@sic rule deck; read them there."""

NOTE_WLCSP_SEALRING = """\
// [DEVIATION --- foundry default is ON]
// mini@sic is WIRE BOND only. There is no WLCSP structure in this design and no
// seal ring in our GDS at all (TSMC adds it). Leaving this on is not cosmetic:
//   * with it ON, the deck's seal-ring edge layer is derived by subtracting a
//     WLCSP score layer that is itself built by intersecting active with a SEALRING
//     input. We ship no SEALRING layer, so that intersection is empty, the score
//     layer is empty, and the seal-ring edge degenerates to the WHOLE CHIP. Every
//     CSR.* and SR.* check then measures against a seal-ring region that is the
//     entire die.
//   * it also swaps the CSR.EN.5 constants to their WLCSP values, which are LARGER
//     than the wire-bond ones (figures not reproduced --- TSMC licence forbids it;
//     read them in the deck).
//   * it swaps the pad-height derivation to the WLCSP form.
// With it OFF the deck takes the wire-bond branch for the seal-ring edge layer."""

NOTE_CHIPWINDOW = """\
// [DEVIATION --- foundry default is OFF]
// With it OFF, the deck derives the chip outline as the EXTENT of its drawn-layer
// union, i.e. the outline is
// whatever the union of ~110 drawn layers happens to span. For a black-box stream
// whose std cells contribute single-metal abstracts and whose corners are sparse,
// that outline is a synthetic shape, not the die --- and every boundary-derived
// check (CSR.*, SR.*, the density windows via CHIP_EDGE, EMPTY_AREA) then measures
// against it. Turning it on takes the deck's other branch, the standard chip-window
// idiom: a dedicated ChipWindow layer, a POLYGON built from the four VARIABLEs
// below, and a PUSH of that layer to form CHIP.
// The values below are SUBSTITUTED, not typed. They come, through
// drc_project.mk, from the `create_floorplan -site core -die_size <w> <h>` in
// ASIC/genus-innovus/scripts/floorplan.tcl -- the statement that actually
// creates the die. That is the one source of truth for the die box and this is
// a derived copy, regenerated on every run, so the chip window Calibre measures
// against cannot drift from the chip P&R built. Do not replace these with
// literals; edit floorplan.tcl.
//
// These four VARIABLEs are why this file has to be a splice rather than a wrapper:
// the foundry deck declares them unconditionally, so they cannot be set from
// outside without tripping Error VAR3."""

NOTE_DFM = """\
// [KEPT OFF] mini@sic sign-off does not require the DFM deck, and DFM results would
// swamp the real ones. Everything below in this DFM section is therefore inert; it
// is carried through from the foundry block unchanged so this header stays
// structurally diffable against it."""

NOTE_AU_WIREBOND = """\
// [KEPT OFF --- BUT THIS IS A BROKER QUESTION]
// The comment is the foundry's: on for Au wire bond, off for Cu wire bond, off if
// not wire bonding. We ARE wire bonding, so the correct value depends on whether
// Europractice/the assembly house uses Au or Cu wire, which we have not confirmed.
// Impact is narrow and one-directional: the switch's ONLY effect in the whole deck
// is on the derived layer that the M8 max-width check consumes. ON is the STRICTER
// setting --- it stops excluding a bond-metal width term from the checked region.
// (Deck variable names and line numbers not reproduced --- TSMC licence forbids it;
// trace the switch in the deck itself.)
// Left at the foundry default for now; flip to ON if the broker
// confirms Au wire, and re-run --- it can only add M8 width results, never remove them."""

NOTE_LAYOUT = """\
// $DRC_GDS is expanded by Calibre itself: SVRF expands environment variables in
// *file path* strings (LAYOUT PATH, INCLUDE, DRC RESULTS DATABASE) but NOT in
// cell-name strings. LAYOUT PRIMARY therefore has to arrive here as a LITERAL ---
// which is exactly why @@TOPCELL@@ is substituted by make_project_deck.sh when
// the deck is assembled, and not left as a $VAR for Calibre to expand. Calibre
// would take '$BLOCK' for the name of a cell.
//
// run_drc.sh re-reads this LAYOUT PRIMARY back out of the assembled deck and
// asserts it equals $BLOCK before starting, so a botched substitution is a
// one-line failure rather than a 400+ MB stream read ending in "Specified
// primary cell ... is not located within the input layout database"."""

NOTE_MAX_RESULTS = """\
// Cap results per check. The foundry default is ALL; on a design that has never
// been through sign-off DRC the density and seal-ring checks alone can produce
// millions of results and fill the disk. Raise to ALL once counts are known sane.
//
// NO `ESTIMATE` KEYWORD ON THIS INSTALL --- TRIED 2026-08-11, IT IS A HARD ERROR.
// A bare cap makes a saturated check indistinguishable from one that genuinely
// found exactly `maxresults`, so the obvious fix is the ESTIMATE keyword:
//     DRC MAXIMUM RESULTS [ESTIMATE] {maxresults | ALL}
// That syntax is real, but it is documented in the Calibre 2023.4 SVRF manual and
// this site runs v2023.1_18.8, whose own docs directory is a dangling symlink ---
// so the 2023.4 tree is the only one greppable here and it is NOT the installed
// version. Measured: `DRC MAXIMUM RESULTS ESTIMATE 1000` gives
//     ERROR: Error INP1 on line 414 of <deck> -
//            superfluous or invalid input object: 1000.
// and Calibre exits 0 having produced no summary at all. Do not re-add it without
// first confirming the installed version accepts it.
//
// Saturation is therefore detected downstream instead: scripts/ci/drc_census.py
// parses the summary's own "MAXIMUM RDB limit N reached for output layer X"
// warnings and fails the run, which works on every version. Note the record
// header cannot be used for this --- Calibre writes `1000 1000`, i.e. origcount
// == count, even when it truncated."""

NOTE_MAX_DENSITY = """\
// [DEVIATION] Density RDB uncapped 2026-08-11. THE RULECHECK COUNT IS NOT A
// DENSITY METRIC. Calibre reports one merged result per DENSITY check while the
// per-window detail goes to the check's own RDB file, so on this design M6.DN.1
// reported `TOTAL Result Count = 1` against 1262 genuinely failing windows and
// M7.DN.1 reported 1 against 1415. Gating on the summary count would score a
// 7006-window density failure as 72 results.
//
// This statement only supplies the default for a DENSITY operation's MAXIMUM
// keyword, so it cannot reach a rule that sets MAXIMUM itself (e.g. SRAM.WARN.1,
// which hardcodes its own MAXIMUM). Verified that the Mx.DN.* rules we care
// about do NOT: M1.DN.5 emits a bare `RDB M1.DN.5.density`. Those are
// the five checks that hit the 1000-window limit in the 2026-08-10 baseline.
// Cost is disk only, in *.density files that already exist."""


# ---------------------------------------------------------------------------
# THE EDITS.  Each entry is (kind, pattern, payload, why).
#
#   note        insert our comment block immediately BEFORE the matched line
#   comment_out the matched line is active in the deck; we turn it OFF
#   uncomment   the matched line is commented in the deck; we turn it ON
#   replace     substitute our own statement for the deck's
#   after       insert an extra statement immediately AFTER the matched line
#
# Every pattern must match EXACTLY ONCE in the deck's switch block, and the
# generator aborts naming the pattern if it does not.  That assertion is the
# whole safety argument for deriving rather than copying: a deck revision that
# renames a switch stops the build instead of silently dropping the edit.
# ---------------------------------------------------------------------------
EDITS = [
    ("note", r"^\s*//#DEFINE\s+DEFINE_PAD_BY_TEXT\b", NOTE_PAD_BY_TEXT,
     "pad-by-text cannot separate signal from supply pads in this stream"),
    ("note", r"^\s*VARIABLE\s+PAD_TEXT\b", NOTE_PAD_TEXT_VARS,
     "make the three text patterns reviewable; values are the foundry defaults"),
    ("note", r"^\s*//#DEFINE\s+MIXED_SCHEME\b", NOTE_MIXED_SCHEME,
     "our stream is pure new-scheme; MIXED would admit mis-mapped geometry"),
    ("note", r"^\s*#DEFINE\s+FULL_CHIP\b", NOTE_FULL_CHIP,
     "FULL_CHIP is the only guard on PO.R.8 and on the whole seal-ring family"),

    ("uncomment", r"^\s*//#DEFINE\s+LP\b", NOTE_LP,
     "CLN65LP throughout; without it the deck checks the wrong dummy-poly rules"),

    ("note", r"^\s*VARIABLE\s+CellsFor1nmGrid\b", NOTE_HALF_NODE_VAR,
     "inert under HALF_NODE=off; kept so the structure still lines up"),
    ("note", r"^\s*//#DEFINE\s+28K_AP\b", NOTE_28K_AP,
     "we use the thin-AP option, so the thick-AP-only rules stay out"),

    ("comment_out", r"^\s*#DEFINE\s+WLCSP_SEALRING\b", NOTE_WLCSP_SEALRING,
     "wire bond, and no seal ring in our GDS; ON degenerates the seal-ring "
     "edge to the whole chip"),

    ("uncomment", r"^\s*//#DEFINE\s+ChipWindowUsed\b", NOTE_CHIPWINDOW,
     "OFF derives the outline from the drawn-layer union, which for a "
     "black-box stream is not the die"),

    ("setvar", r"^\s*VARIABLE\s+xLB\b", "@@XLB@@", "die box, from floorplan.tcl"),
    ("setvar", r"^\s*VARIABLE\s+yLB\b", "@@YLB@@", "die box, from floorplan.tcl"),
    ("setvar", r"^\s*VARIABLE\s+xRT\b", "@@XRT@@", "die box, from floorplan.tcl"),
    ("setvar", r"^\s*VARIABLE\s+yRT\b", "@@YRT@@", "die box, from floorplan.tcl"),

    ("note", r"^\s*//#DEFINE\s+DFM\b", NOTE_DFM,
     "mini@sic does not require the DFM deck"),
    ("note", r"^\s*//#DEFINE\s+AU_WireBond\b", NOTE_AU_WIREBOND,
     "open broker question: Au or Cu wire"),

    ("note", r"^\s*LAYOUT\s+PATH\b", NOTE_LAYOUT,
     "why the cell name is substituted here and not left to Calibre"),
    ("replace", r"^\s*LAYOUT\s+PATH\b", 'LAYOUT PATH    "$DRC_GDS"',
     "the stream under test, from DRC_GDS in the environment"),
    ("replace", r"^\s*LAYOUT\s+PRIMARY\b", 'LAYOUT PRIMARY "@@TOPCELL@@"',
     "our top cell; must be a literal, SVRF does not expand vars here"),

    ("replace", r"^\s*DRC\s+RESULTS\s+DATABASE\b",
     'DRC RESULTS DATABASE "@@TOPCELL@@.drc.results" ASCII',
     "results named after the block, so runs cannot overwrite each other"),
    ("replace", r"^\s*DRC\s+SUMMARY\s+REPORT\b",
     'DRC SUMMARY REPORT   "@@TOPCELL@@.drc.summary" REPLACE HIER',
     "ditto, and HIER so the summary attributes results to cells"),
    ("after", r"^\s*DRC\s+SUMMARY\s+REPORT\b",
     "DRC CELL NAME YES CELL SPACE XFORM",
     "cell attribution in the RDB, which drc_census.py reads"),

    ("note", r"^\s*DRC\s+MAXIMUM\s+RESULTS\b", NOTE_MAX_RESULTS,
     "why the cap exists and why ESTIMATE cannot be used on this install"),
    ("replace", r"^\s*DRC\s+MAXIMUM\s+RESULTS\b", "DRC MAXIMUM RESULTS 1000",
     "cap per check; saturation detected downstream by drc_census.py"),
    ("after", r"^\s*DRC\s+MAXIMUM\s+RESULTS\b",
     NOTE_MAX_DENSITY + "\nDRC MAXIMUM RESULTS DENSITY ALL\nDRC MAXIMUM VERTEX  4096",
     "density RDB uncapped: the rulecheck count is not a density metric"),
]


def load_switch_block(deck_path):
    """Return the deck's switch block, START marker through END marker."""
    lines = []
    state = "before"
    with open(deck_path, "r", errors="replace") as fh:
        for line in fh:
            line = line.rstrip("\n")
            if state == "before":
                if SWITCH_START.match(line):
                    state = "in"
                    lines.append(line)
                continue
            lines.append(line)
            if SWITCH_END.match(line):
                state = "after"
                break
    if state != "after":
        sys.exit(
            "FAIL: no complete '/* SWITCH DEFINITION START/END */' block in\n"
            f"      {deck_path}\n"
            "      The deck format changed. Re-check the splice point by hand "
            "before trusting any DRC result from this flow."
        )
    return lines


def apply_edits(block):
    """Apply EDITS to the switch block, asserting each matched exactly once."""
    compiled = [(kind, re.compile(pat), pat, payload, why)
                for kind, pat, payload, why in EDITS]
    hits = {i: 0 for i in range(len(compiled))}

    out = []
    for line in block:
        pre, replaced, post = [], None, []
        for idx, (kind, rx, pat, payload, why) in enumerate(compiled):
            if not rx.match(line):
                continue
            hits[idx] += 1
            if kind == "note":
                pre.append(payload)
            elif kind == "comment_out":
                pre.append(payload)
                replaced = "//" + line.lstrip()
            elif kind == "uncomment":
                pre.append(payload)
                replaced = re.sub(r"^(\s*)//", r"\1", line, count=1)
            elif kind == "setvar":
                name = line.split()[1]
                replaced = (f"VARIABLE {name}   {payload}"
                            f"\t  // substituted from drc_project.mk")
            elif kind == "replace":
                replaced = payload
            elif kind == "after":
                post.append(payload)
        out.extend(pre)
        out.append(replaced if replaced is not None else line)
        out.extend(post)

    bad = []
    for idx, (kind, rx, pat, payload, why) in enumerate(compiled):
        if hits[idx] != 1:
            bad.append(f"  {kind:<12} matched {hits[idx]}x (want 1): {pat}\n"
                       f"               why we edit it: {why}")
    if bad:
        sys.exit(
            "FAIL: the foundry deck no longer matches this generator's edit list.\n"
            "      Each edit must match exactly one line of the switch block.\n\n"
            + "\n".join(bad) +
            "\n\n      DO NOT paper over this by loosening a pattern. A switch that\n"
            "      moved or was renamed changes what the deck checks, and the whole\n"
            "      reason this file derives the header instead of copying it is so\n"
            "      that shows up here rather than in a silently different sign-off.\n"
        )
    return out


def main():
    ap = argparse.ArgumentParser(
        description="Derive the project DRC deck header from the foundry deck.")
    ap.add_argument("--foundry-deck", required=True,
                    help="read-only TSMC deck to derive from")
    ap.add_argument("-o", "--output", required=True,
                    help="where to write the generated header template")
    args = ap.parse_args()

    block = load_switch_block(args.foundry_deck)
    edited = apply_edits(block)

    with open(args.output, "w") as fh:
        fh.write(BANNER)
        fh.write("\n")
        fh.write("//  OPTION SETUP\n//================\n")
        fh.write("\n".join(edited))
        fh.write("\n")

    print(f"make_project_header: wrote {args.output} "
          f"({len(edited)} switch-block lines, {len(EDITS)} edits applied)")


if __name__ == "__main__":
    main()
