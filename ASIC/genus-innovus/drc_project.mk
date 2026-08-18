#-----------------------------------------------------------------------------
# drc_project.mk — this design's identity, for the Calibre DRC flow.
# A joint work commissioned on behalf of SoC Labs, under Arm Academic
# Access license.
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# WHAT THIS IS FOR
#   Before this file existed, three files each carried a private, uncross-checked
#   copy of the same facts:
#       scripts/calibre/run_drc.sh              BLOCK, and the summary filename
#       scripts/calibre/make_project_deck.sh    the foundry deck path
#       scripts/calibre/tsmc65_minisic_header.svrf
#                                               top cell, two result filenames,
#                                               and the four die-box numbers
#   Nothing compared them. A die resize or a top-cell rename landed in one, two
#   or three of them depending on who was editing, and the failure mode was a
#   DRC run that completed and reported a number against the wrong chip window.
#
#   Now they are here, once, and the deck is a TEMPLATE those values are
#   substituted into at splice time. Porting the DRC flow to a second chiplet is
#   editing this file.
#
# EVERY LINE IS TAGGED — same convention as lvs_project.mk
#   [PROJECT] this design. Changes when the design changes.
#   [PDK]     this process / library release. Same for every design on it.
#   [SITE]    where things are installed on this machine.
#   [FLOW]    a flow default. You will rarely touch these.
#
# WHY `?=` EVERYWHERE
#   `?=` only assigns to a still-undefined variable, so every value here can be
#   overridden on the command line without editing the file:
#       make drc DRC_CPUS=32
#       make drc-census DRC_DESIGN_BUDGET=5
#
# WHY THE INCLUDE IS **EARLY**, UNLIKE lvs_project.mk
#   lvs_project.mk goes LAST because it ends by including lvs.mk, the flow
#   itself — assign first, pull in the flow after. This file is the opposite
#   shape: it is pure data with no flow to include, and the Makefile below it
#   consumes $(BLOCK) in a dozen places. A `?=` manifest read AFTER its first
#   consumer is silently discarded, so this one is included immediately after
#   the directory variables and before anything reads them.
#
#   (Live example of exactly that trap: lvs_project.mk:57 sets `BLOCK ?=`, but
#   the Makefile had already fixed BLOCK with `:=` several hundred lines above,
#   so that assignment has never once taken effect. It is harmless only because
#   both spell the same name.)
#-----------------------------------------------------------------------------

#-----------------------------------------------------------------------------
# 1. The design
#-----------------------------------------------------------------------------
# [PROJECT] The top cell. Must be the name that appears in the GDS — for a
#           padded chiplet that is the PAD WRAPPER, not the core. Everything the
#           DRC flow writes is named after it, and run_drc.sh now asserts that
#           the assembled deck's `LAYOUT PRIMARY` really is this name before it
#           spends 400+ MB of stream read finding out otherwise.
#
#           This is also the name the LVS flow uses (lvs_project.mk §1). Because
#           this file is included first, its value is the one that takes effect
#           and lvs_project.mk's `BLOCK ?=` is a no-op. One name, one place.
BLOCK ?= nanosoc_eth_chiplet_pads

#-----------------------------------------------------------------------------
# 2. The die box — DERIVED, NOT TYPED
#
# THE SINGLE SOURCE OF TRUTH FOR THE DIE IS scripts/floorplan.tcl.
#
# That file's `create_floorplan -site core -die_size <w> <h>` is the statement
# that actually creates the die; every other copy of those numbers is a
# description of it. Descriptions drift, so this file does not keep one — it
# reads the width and height straight out of floorplan.tcl at make time, and
# make_project_deck.sh substitutes them into the deck on every run. The deck is
# regenerated per run, so a die resize propagates to Calibre's chip window with
# no second edit and no opportunity to disagree.
#
# Direction of derivation matters and is not arbitrary: DRC's ChipWindow must
# describe what P&R built. Deriving the other way (deck authoritative, floorplan
# following) would let a deck edit silently claim a die the design does not have
# — and would mean touching the Tcl that a running P&R depends on, to fix a
# problem that only exists in the deck.
#
# Why the lower-left is a constant rather than an extraction: `-die_size` takes
# a WIDTH and a HEIGHT, and Innovus anchors the resulting die at the origin.
# floorplan.tcl says so itself, at the macro-coordinate note: "the die is
# anchored at (0,0)". There is no lower-left corner to read.
#-----------------------------------------------------------------------------
# [FLOW] Where to read the die from. Anchored to a real `create_floorplan`
#        command at the start of a line, so the two COMMENTS in floorplan.tcl
#        that also mention `-die_size 1600 2000` cannot be picked up instead.
DRC_FLOORPLAN_TCL ?= $(DESIGN_DIR)/scripts/floorplan.tcl
DRC_DIE_SIZE := $(shell sed -n \
    's/^[[:space:]]*create_floorplan .*-die_size[[:space:]]\{1,\}\([0-9.]\{1,\}\)[[:space:]]\{1,\}\([0-9.]\{1,\}\).*/\1 \2/p' \
    $(DRC_FLOORPLAN_TCL) 2>/dev/null | head -1)

ifeq ($(strip $(DRC_DIE_SIZE)),)
$(error drc_project.mk: could not read `-die_size` out of $(DRC_FLOORPLAN_TCL). \
        The die box is derived from that file, so DRC cannot be set up without \
        it. Either the file moved (set DRC_FLOORPLAN_TCL) or create_floorplan \
        was rewritten (fix the sed above) — do NOT paper over it by typing the \
        numbers here, that is the duplication this file exists to remove)
endif

# [FLOW] Keep a bare integer looking like the decimal the hand-written deck
#        used (`VARIABLE xRT 1600.0`), so the generated deck stays diffable
#        against the one it replaced. SVRF treats 1600 and 1600.0 alike.
drc_dec = $(if $(findstring .,$(1)),$(1),$(1).0)

# [FLOW] The four numbers the deck's ChipWindow needs. Override only to check a
#        stream that is not this design's die (e.g. a shuttle-frame experiment).
DRC_DIE_XLB ?= 0.0
DRC_DIE_YLB ?= 0.0
DRC_DIE_XRT ?= $(call drc_dec,$(word 1,$(DRC_DIE_SIZE)))
DRC_DIE_YRT ?= $(call drc_dec,$(word 2,$(DRC_DIE_SIZE)))

#-----------------------------------------------------------------------------
# 3. The rule deck
#-----------------------------------------------------------------------------
# [PDK] The foundry DRC deck. Its path encodes the METAL STACK, so it is not
#       interchangeable: this must be the stack the Innovus GdsOutMap streams
#       with (9M 6X1Z1U — see scripts/4b_pnr_route_eval.tcl, EVR_GDS_MAP_FILE).
#       Run a 6X1Z1U stream against a different deck and every via-stack and
#       thick-metal rule is checked against the wrong geometry.
#
#       RESOLVED, NOT SPELLED. The deck's last path component names the deck
#       revision this site licensed, and this repository is public. ASIC/common.mk
#       resolves PDK_DRC_DECK through pdk_paths.sh, which globs the installed
#       PDK and derives the stack from the one installed tech LEF — i.e. from the
#       SAME anchor the GdsOutMap is chosen by, so the "must match the stream"
#       requirement above is now structural rather than a hand-kept coincidence.
#       Selection is unchanged; `make pdk-paths` re-proves it. The tree is
#       READ-ONLY lab collateral: the flow copies the deck's rule bodies and
#       never writes to it.
DRC_FOUNDRY_DECK ?= $(PDK_DRC_DECK)

# [PDK] The foundry BND (wire-bond pad-ring / BEOL) deck — a SEPARATE rule
#       family from DRC_FOUNDRY_DECK above, not an alternative name for it. See
#       docs/tapeout/50-bnd-and-logo-checks.md for what BND checks that the
#       core DRC deck does not (PM/AP/CB2 pad-ring and RDL rules) and why the
#       two are run and gated separately rather than merged.
#
#       Same anchor, same stack derivation as DRC_FOUNDRY_DECK — resolved by
#       the same pdk_paths.sh off the one installed tech LEF, just a different
#       foundry directory (bnd-ruledeck vs drc-ruledeck). Never spelled here
#       for the same public-repository reason as DRC_FOUNDRY_DECK.
#
#       Unlike DRC_FOUNDRY_DECK, this needs no make_project_deck.sh splice: the
#       project wrapper (scripts/calibre/nanosoc_eth_chiplet_pads.bnd.rules)
#       sets no foundry default this design must override, so a plain
#       `INCLUDE "$BND_FOUNDRY_DECK"` wrapper is sufficient. See run_bnd.sh.
BND_FOUNDRY_DECK ?= $(PDK_BND_DECK)

# The project-owned switch/environment block that replaces the foundry deck's
# own is NOT a variable here, on purpose. It lives beside its assembler as
#     scripts/calibre/tsmc65_minisic_header.svrf.in
# and is flow machinery, not design identity: it is a TEMPLATE into which
# make_project_deck.sh substitutes $(BLOCK) and the die box above, refusing to
# emit a deck with any placeholder left unfilled. Substitution has to happen at
# splice time rather than Calibre runtime because SVRF expands environment
# variables in FILE PATH strings only, never in cell-name strings — the template
# says so in as many words at its LAYOUT PRIMARY line.
#
# Naming it here would also cost the DECK_HEADER escape hatch: make_project_deck.sh
# honours $DECK_HEADER for switch experiments, and a value pushed from the
# Makefile on every run would override it.

#-----------------------------------------------------------------------------
# 4. Where the run happens
#-----------------------------------------------------------------------------
# [FLOW] Signoff rundir. `make drc-logo` deliberately uses a different one, so
#        the submission artefact's count can never overwrite the signoff one's.
DRC_RUNDIR ?= $(WORK_DIR)/drc_run

# [FLOW] BND rundir. Separate from DRC_RUNDIR for the same reason drc-logo's
#        is separate from drc's: two Calibre decks writing into one directory
#        would each overwrite pieces of the other's results/summary/log.
BND_RUNDIR ?= $(WORK_DIR)/bnd_run

# [SITE] Calibre -turbo processor count. Lower it on a shared host or where the
#        site licence caps parallel CPUs.
DRC_CPUS ?= 8
BND_CPUS ?= 8

#-----------------------------------------------------------------------------
# 5. Census budgets — what counts as a pass
#
# scripts/ci/drc_census.py reads these from the environment (command line wins).
# It gates on design-owned results and on CORE-ONLY failing density windows, and
# fails outright on any SATURATED check — a check capped at 1000 has an unknown
# true count, so the run is not a measurement and cannot be signed off either
# way. io-pad-abstract and vendor-memory results are reported, not gated.
#-----------------------------------------------------------------------------
# [PROJECT] Design-owned results permitted. ZERO is the only defensible signoff
#           value; raise it only to characterise a known, written-down set, and
#           put the reason next to it.
DRC_DESIGN_BUDGET ?= 0

# [PROJECT] Failing CORE-ONLY density windows permitted. Also zero: metal fill
#           is the fix for density, not a budget.
DRC_DENSITY_BUDGET ?= 0
