#-----------------------------------------------------------------------------
# nanosoc-ethernet-chiplet / ASIC/eth-chiplet/design.mk
#
# The design manifest the nanoSoC ASIC Toolkit reads: the one file that tells the
# toolkit's engine what this chiplet is. ../Makefile is three lines (this file,
# then the engine), so everything design-specific is here.
#
# LAYOUT
#   0-0b  repo roots, then the project environment via ../common.mk
#   1     identity: block, tech pack, where the toolkit is
#   2     RTL input: flist, defines, pad-ring wrapper
#   3     where a run writes: build/$(RUN_TAG)/{work,logs,reports,outputs}
#   4-5   project-side Tcl and constraints - all LIVE files, none copied
#   6-9   environment, resources, stream expectations, signoff declarations
#   10    include the engine
#   11-12 project-side wiring below the engine: extra stage prerequisites,
#         message allowlists, the measured ratchets, the design report
#
# THE LIVE FILES ARE THE SOURCE OF TRUTH. Every path below points at the file
# ../genus-innovus uses today; nothing is copied here, because a copy is a
# snapshot that drifts silently while a pointer cannot. Consequence: this
# manifest is additive and reversible - deleting this directory changes nothing
# about `make -C ASIC/genus-innovus pnr_all`.
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------


# ── 0. REPO ROOTS ───────────────────────────────────────────────────────────
#
# DEFINED FIRST, AND THAT MATTERS: `:=` in make is IMMEDIATE, so anything a later
# `:=` dereferences must already exist. A repo root defined at the bottom expands
# to empty up here and `$(EMPTY)/flist/x.flist` becomes `/flist/x.flist` - an
# absolute path that looks plausible and does not exist.
#
# Derived from THIS FILE's location, not $(CURDIR), so `make -C ASIC/eth-chiplet`
# and `make -f ASIC/eth-chiplet/design.mk` agree.
ETH_CHIPLET_ASIC_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
export NANOSOC_ETH_CHIPLET_HOME ?= $(abspath $(ETH_CHIPLET_ASIC_DIR)/../..)


# ── 0b. THE PROJECT ENVIRONMENT, FROM ITS ONE DEFINITION ────────────────────
#
# ../common.mk defines every environment variable the flists and SDCs
# dereference - ARM_IP_LIBRARY_PATH, CMSDK_DIR, TIDELINK_HOME, TIDECHART_HOME,
# ETH_SS_HOME, PHC_AHB_HOME, SOCLABS_*, TSMC_65_HOME, PHYS_IP, DESIGN_HOME,
# CLK_PERIOD - about thirty, all `?=`.
#
# INCLUDED, NOT RETYPED. Retyping the list makes a second copy of something
# already maintained, and one missing export costs a full Genus load: it reads
# the whole SoC and only then dies on the unset variable, ten minutes in, so it
# reads as a link error.
#
# The include brings targets with it - eth-bintxt, romlibs-preflight,
# romlibs-verify, tsmc_65_romlibs, gen_memories. None collides with a toolkit
# target, and `romlibs-check` below depends on one deliberately.
include $(ETH_CHIPLET_ASIC_DIR)/../common.mk

# Where the production flow's collateral lives. Everything in section 4 and
# section 5 is under here; nothing is duplicated into this directory.
LEGACY_ASIC_DIR := $(NANOSOC_ETH_CHIPLET_HOME)/ASIC/genus-innovus


# ── 1. IDENTITY ─────────────────────────────────────────────────────────────

# The PAD RING, not the core. `nanosoc_eth_chiplet` is the inner top;
# `nanosoc_eth_chiplet_pads` wraps it in the IO ring and is what gets taped out.
# Source: ../genus-innovus/scripts/config.tcl `set block_name`, drc_project.mk BLOCK
BLOCK := nanosoc_eth_chiplet_pads

# The tech pack owns the standard cells, the IO library, the tech LEF, the cap
# tables, the layer names and the stream-out map. Its site roots come from
# ../common.mk (TSMC_65_HOME).
TECH  := tsmc65

# THE TWO SITE VARIABLES THE PACK NEEDS, AND WHY THEY LIVE HERE, NOT THERE.
#
# tech/tsmc65 declares two `tech_env` variables and defaults NEITHER:
#     TSMC_65_HOME        the TSMC PDK mount                  (../common.mk)
#     ARM_CLN65LP_TECH    ARM's cln65lp arm_tech package - the RC cap tables
#                         under cadence_captable/. A SEPARATE deliverable from
#                         the PDK, in a shared read-only IP tree. NEVER write
#                         into it (see CLAUDE.md).
#
# The pack carries no default for either, because a public repository must not
# carry one site's filesystem layout and a pack that silently defaults to a path
# the reader does not have produces a run that looks configured and is not. It
# fails at tech_load naming the variable instead - which is the correct failure,
# even though it lands after place and CTS have already been paid for. So the
# site fact lives here, with the project.
#
# `?=`, so a shell export or ci/site.env still wins. Resolved, not spelled:
# `arm_tech/<rel>` names the Arm release this site licensed and this repository
# is public, so pdk_paths.sh globs it (exactly one is installed) off $(PHYS_IP).
# `make -C .. -f common.mk pdk-paths` re-proves the selection.
export ARM_CLN65LP_TECH ?= $(shell TSMC_65_HOME='$(TSMC_65_HOME)' PHYS_IP='$(PHYS_IP)' \
                             $(PDK_PATHS_SH) arm-tech-dir 2>/dev/null)

# WHERE THE TOOLKIT IS. Two possible answers, so this resolves rather than
# asserts:
#   ASIC/asic-toolkit          the submodule
#   ../nanoSoC-ASIC-Toolkit    a sibling working clone
# Probed on mk/flow.mk, not on the directory: an uninitialised submodule is an
# empty directory that passes every `test -d`.
# Override for a one-off: make check ASIC_FLOW_DIR=/path/to/toolkit
ASIC_TOOLKIT_SUBMODULE := $(NANOSOC_ETH_CHIPLET_HOME)/ASIC/asic-toolkit
ASIC_TOOLKIT_SIBLING   := $(abspath $(NANOSOC_ETH_CHIPLET_HOME)/../nanoSoC-ASIC-Toolkit)
ASIC_FLOW_DIR ?= $(if $(wildcard $(ASIC_TOOLKIT_SUBMODULE)/mk/flow.mk),\
                     $(ASIC_TOOLKIT_SUBMODULE),$(ASIC_TOOLKIT_SIBLING))


# ── 2. RTL INPUT ────────────────────────────────────────────────────────────

# The ASIC flist, which swaps the FPGA SRAM behavioural models for the compiled
# TSMC65 macros. It -f-includes two GENERATED sub-flists under build/chip/flist/,
# so `asic-flist` below is a real prerequisite of syn, not a convenience.
#
# NAMED EXPLICITLY rather than inherited: ../common.mk also exports a bare
# `FLIST` (the SoC's own nanosoc_multicore_asic.flist) and the toolkit accepts
# FLIST as a legacy alias for RTL_FLIST. Leave RTL_FLIST empty and the toolkit
# builds the SoC instead of the chiplet, with no warning.
RTL_FLIST := $(NANOSOC_ETH_CHIPLET_HOME)/flist/nanosoc_eth_chiplet_asic.flist

# TideLink's PHY is selected by define, not by flist.
# Source: ../genus-innovus/scripts/read_flist.tcl `read_hdl -define TIDELINK_PHY_V2`
RTL_DEFINES ?= TIDELINK_PHY_V2

# The generated pad-ring wrapper (nanosoc_gen SoCPadRingBackend). Outside the
# flist, so the flow reads it last.
TOP_HDL ?= $(NANOSOC_ETH_CHIPLET_HOME)/ASIC/tech_wrappers/tsmc65/nanosoc_eth_chiplet_pads.v

# MEASURED INERT FOR THIS WRAPPER: `grep -c POWER_PINS` on it is 0, so the define
# selects nothing today. Set anyway, because the production flow sets it and
# equivalence between the two flows is the point of this directory - and a
# regenerated wrapper could start using it.
# Source: ../asic-flows/Cadence/1_synthesis.tcl `read_hdl -define POWER_PINS`
TOP_HDL_DEFINES ?= POWER_PINS


# ── 3. WHERE THE FLOW WRITES ────────────────────────────────────────────────
#
# Everything a run produces goes to $(BUILD_DIR)/$(RUN_TAG)/{work,logs,reports,
# outputs}. Deliberately NOT ../genus-innovus/{...}: a toolkit run must not be
# able to overwrite the production tree, and a `make distclean` typed in the
# wrong directory must not be able to delete the shipped GDS.
#
# Do NOT set OUT_DIR / REPORT_DIR / LOG_DIR / WORK_DIR here - the engine derives
# all four with `:=` and is included last, so anything set here is discarded.
BUILD_DIR ?= $(ETH_CHIPLET_ASIC_DIR)/build
RUN_TAG   ?= default

IN_RUN_TAG  ?= $(RUN_TAG)
SYN_RUN_TAG ?= $(RUN_TAG)


# ── 4. PROJECT-SIDE FILES - ALL OF THEM LIVE, NONE OF THEM COPIED ───────────

# The only Tcl file this directory owns. The production scripts/config.tcl cannot
# be used as DESIGN_CONFIG_TCL; see the header of config/design_config.tcl.
DESIGN_CONFIG_TCL ?= $(ETH_CHIPLET_ASIC_DIR)/config/design_config.tcl

# The live floorplan - die box, IO ring, 21 macro coordinates, ::PLACED_MACROS
# (die 1600x2000). Consumed unchanged; its one relative reference resolves
# through the `legacy-paths` bridge at the bottom of this file.
FLOORPLAN_TCL ?= $(LEGACY_ASIC_DIR)/scripts/floorplan.tcl

# The live power plan - global nets, core rings, stripes, row splitting over
# ::PLACED_MACROS, endcaps, risers. Consumed unchanged; it reads only $OUT_DIR
# and ::PLACED_MACROS from outside itself, and the engine publishes both.
POWER_PLAN_TCL ?= $(LEGACY_ASIC_DIR)/scripts/power_plan.tcl

# The live mmmc, consumed unchanged - including its
# `-sdc_files [list ../outputs/nanosoc_eth_chiplet_pads_syn.sdc]`, which is
# relative to the tool's working directory and so resolves to
# $(BUILD_DIR)/$(RUN_TAG)/outputs here, exactly as it resolves to
# ../genus-innovus/outputs in production.
#
# CAVEAT: that relative path follows RUN_TAG, not SYN_RUN_TAG, so
# `make place SYN_RUN_TAG=other` reads the netlist from `other` and the SDC from
# this run. The engine's place stage warns when the two directories differ - do
# not use SYN_RUN_TAG with this mmmc without reading that warning.
MMMC_FILE ?= $(LEGACY_ASIC_DIR)/scripts/$(BLOCK).mmmc

# The 82-pad IO placement map.
IO_FILE  ?= $(LEGACY_ASIC_DIR)/scripts/$(BLOCK).io

# THIS DESIGN HAS A PAD RING, SO SAY SO. At the default of 0 the engine treats
# IO_FILE as optional and `make check` does not assert it; the floorplan then
# fails at read_io_file, hours in.
PAD_RING ?= 1

# ── THE ONE THAT SILENTLY SCRAPS A DIE ──────────────────────────────────────
#
# READ THIS BEFORE CHANGING IT.
#
# POWER_INTENT is the ONLY variable the engine reads power intent from (mk/flow.mk
# exports it as ASIC_POWER_INTENT; flow/genus/1_synthesis.tcl is the only reader).
# `upf_file` / `cpf_file` / `cpf_patch_required` are this project's
# scripts/config.tcl spellings and have ZERO readers anywhere in flow/, mk/ or
# tech/ - setting those instead of this one sets nothing.
#
# What that costs, in order: synthesis skips section 7 and writes NO CPF; place
# skips read_power_intent and commit_power_intent; no power domains exist;
# add_fillers inserts nothing; the die streams with no filler, no base-layer
# density fill and no antenna diodes. Nothing fails. A GDS appears and it is
# scrap - this project has already shipped that stream once, 95,568 free-site
# gaps, ~5.9% of the core. See docs/tapeout/06-fill-antenna-bondpads.md.
POWER_INTENT ?= $(LEGACY_ASIC_DIR)/inputs/$(BLOCK).upf

# The bond-pad ring - 42 PAD70GU outer + 40 PAD70NU inner, created from the route
# stage on M8/M9/AP. Consumed unchanged; see overrides/filler.tcl for the
# ordering collision this creates and how it is resolved.
BONDPADS_TCL ?= $(LEGACY_ASIC_DIR)/scripts/place_bondpads.tcl

HOOKS_DIR     ?= $(ETH_CHIPLET_ASIC_DIR)/hooks
OVERRIDES_DIR ?= $(ETH_CHIPLET_ASIC_DIR)/overrides

# No scan chain is bonded on this tapeout. TEST and SE are strapped and excluded
# by set_case_analysis in the live constraints, which is the right instrument:
# turning DFT off does not stop the timer walking the scan mux inside every SDF*
# flop. Source: ../genus-innovus/scripts/config.tcl `set DFT 0`
DFT_SETUP_TCL ?=


# ── 5. CONSTRAINTS ──────────────────────────────────────────────────────────
#
# EXPLICIT AND SINGLE-ENTRY, and both halves matter. This design's constraints
# are ONE file that `source`s four interface SDCs from its middle, between the
# clock definitions above them and the asynchronous clock groups below - which
# must come after, because get_clocks cannot name a clock that does not exist.
#
# A sorted glob would be wrong twice over: it would read all five files, and it
# would read the four interface files again, alphabetically, before the clock
# groups. `read_sdc` on an already-read constraint is not idempotent.
SDC_FILES := $(LEGACY_ASIC_DIR)/inputs/constraints.sdc

# The directory the STALENESS gate watches. `make sdc-check` and the toolkit's
# place stage compare mtimes here against $(BLOCK)_syn.sdc, so pointing it at the
# live inputs directory is what makes all five files watched, not just the one
# named above.
#
# THE TRAP THIS GUARDS: place-and-route does NOT read these files. The mmmc names
# $(BLOCK)_syn.sdc - the file SYNTHESIS wrote. Edit a constraint, re-run place,
# and nothing changes.
SDC_DIR ?= $(LEGACY_ASIC_DIR)/inputs


# ── 6. ENVIRONMENT ──────────────────────────────────────────────────────────
#
# Section 0b already exported the project environment from ../common.mk. What is
# left is what the TECH PACK asks for and the project answers.

# The vendor IO driver LEF declares three pad-cell supply pins as plain signal
# pins - `PIN VDDPST / DIRECTION INOUT ;` with no `USE POWER ;` - so
# `connect_global_net -type pg_pin` cannot match them, the VDDIO/VSSIO special
# nets stay EMPTY, and the router threads the IO supplies around the periphery as
# ordinary signal nets into the bond-pad M8/M9 blockages: 76 DRC records on the
# 2026-08 reference run, all "Regular Wire", against zero for the core supplies.
# Correcting -pin_base_name alone is NOT sufficient - the LEF has to classify the
# pin as power.
#
# THE PATCHED FILE IS GENERATED, NOT COMMITTED: this repository is PUBLIC and
# TSMC's licence does not permit reproducing their collateral, so the repo
# carries the TRANSFORM and the vendor bytes are read from the read-only PDK at
# build time. PAD_LEF and the `pad-lef` target that produces it come from
# ../common.mk, and `syn` below depends on it. Never check the output in.
# Source: ../genus-innovus/scripts/config.tcl `set IO_PAD_DRIVER_LEF`
export TSMC65_IO_DRIVER_LEF ?= $(PAD_LEF)

# CLK_PERIOD comes from ../common.mk:174 (10.0 ns). Not restated here - one
# definition, and a sweep is `make syn CLK_PERIOD=8.0` either way.

# ── ANALYSIS VIEW NAMES: DELIBERATELY NOT SET ───────────────────────────────
#
# The engine defaults CTS_SETUP_VIEW / CTS_HOLD_VIEW / ROUTE_VIEWS_SETUP /
# ROUTE_VIEWS_HOLD to `default_analysis_view_setup` and
# `default_analysis_view_hold`, and this design's mmmc names its views EXACTLY
# THAT. So the correct action is to set nothing. Overriding them to view names
# this mmmc does not define aborts CTS - flow/innovus/3_cts.tcl asserts the named
# views are present - after placement has already been paid for.
#
# The mmmc also defines `typical_analysis_view`. Setting ROUTE_VIEWS_TYPICAL to
# it enables an extra typical-corner reporting pass in route; left unset that
# pass is skipped. A reporting difference, not a timing one.


# ── 7. RESOURCES ────────────────────────────────────────────────────────────
#
# 14 of this host's 16 physical cores. Licences are not the constraint:
# Innovus_CPU_Opt has 41 issued and typically 0 in use. Check your own site
# before copying the number.
#
# Distribution stays OFF: the measured inter-host link is ~25 MB/s, ~37x slower
# than local disk, so slaves spend longer fetching the design than they save.
INNOVUS_LOCAL_CPU      ?= 14
INNOVUS_DISTRIBUTED    ?= 0
INNOVUS_REMOTE_HOSTS   ?=
INNOVUS_CPU_PER_REMOTE ?= 6


# ── 8. WHAT MUST BE IN THE FINISHED STREAM ──────────────────────────────────
#
# `make gds-census` reads the GDS itself. Every cell listed here is placed by an
# operation whose failure mode is SILENCE - a skipped hook, an unset variable, a
# command whose argument shape was wrong. The log says nothing, the exit status
# is 0, the cells are simply absent, and a wire-bond die with no bond pads is
# scrap.
#
#   42 PAD70GU outer + 40 PAD70NU inner = 82 staggered bond pads
#   4 PCORNER_G, one per die corner
#   docs/tapeout/03-floorplan.md, 06-fill-antenna-bondpads.md, 21-physical-audit.md
#
# DCAP4 ENDCAPS AND ANTENNA DIODES ARE DELIBERATELY NOT GATED. Both track row
# geometry and move on legitimate floorplan edits (endcaps 4492 -> 4446, diodes
# 41,176 -> 38,290 between runs of the same design). An exact expectation on a
# number that moves legitimately trains people to ignore the gate. Both appear in
# the census output; watch them there.
GDS_EXPECT ?= PAD70GU=42 PAD70NU=40 PCORNER_G=4


# ── 9. SIGNOFF DECLARATIONS ─────────────────────────────────────────────────
#
# What follows tells the toolkit's census the design facts it cannot invent, so a
# toolkit-side census cannot silently flatter a result. Every one of these
# defaults to the CONSERVATIVE answer in the toolkit, so an omission is
# pessimistic, never flattering.
#
# DRC and LVS have working project-side flows already - see DRC_SCRIPT and
# LVS_SCRIPT below, which is where `make drc` / `make lvs` here dispatch to.

# The die box the census clips against is DERIVED from FLOORPLAN_TCL above, which
# carries `create_floorplan -site core -die_size 1600 2000`, so mk/drc.mk reads
# 1600 x 2000 with no second copy to drift. ../genus-innovus/drc_project.mk does
# the identical derivation from the identical file.

# [PDK] The foundry deck. Its path encodes the METAL STACK and is not
# interchangeable with the stream's map, so both are derived from the one
# installed tech LEF by pdk_paths.sh rather than from two hand-kept literals, and
# the deck revision is not spelled in a public file.
DRC_FOUNDRY_DECK ?= $(PDK_DRC_DECK)

# The IO row depth, from the IO cell LEF SIZE: every PDDW*_G / PVDD2*_G /
# PCORNER_G in this IO library is 135 um tall.
DRC_PAD_INSET ?= 135

# The bond pads reach further inboard than the drivers do, and only on the top
# metals: PAD70NU is 171 um deep with OBS solid over its footprint on M8 and M9.
DRC_DEEP_PAD_INSET  ?= 171
DRC_DEEP_PAD_LAYERS ?= M8. M9.

# Cell-name prefixes -> owner bucket, so a vendor-macro or pad-abstract result is
# reported rather than gated. Taken verbatim from scripts/ci/drc_census.py, so
# the toolkit's census and this project's cannot disagree.
DRC_MEMORY_PREFIXES ?= rf_ flash_cache_ rom_via eth_rom_via sram_
DRC_IOPAD_PREFIXES  ?= PAD PDDW PDUW PVDD PVSS PFILLER PCORNER

# Budgets. ZERO is the only defensible signoff value for both.
# Source: ../genus-innovus/drc_project.mk:168,172
DRC_DESIGN_BUDGET  ?= 0
DRC_DENSITY_BUDGET ?= 0

# The project's own runners, so `make drc` / `make lvs` here dispatch to the
# flows that have actually been run rather than to the toolkit's untried ones.
DRC_SCRIPT ?= $(LEGACY_ASIC_DIR)/scripts/calibre/run_drc.sh
LVS_SCRIPT ?= $(NANOSOC_ETH_CHIPLET_HOME)/ASIC/lvs-flow/run_lvs.sh

# ── THE LVS DECK AND LEAF-CELL INPUTS ───────────────────────────────────────
# These four must be set here, or the toolkit's LVS path fails honestly with
# "UNSET LVS_DECK / UNSET STDCELL_VLOG" while the legacy path - which still
# defines them - quietly grades a different, older stream.
#
# SEMANTICS CHECKED, NOT ASSUMED: same name is not same meaning. The toolkit's
# flow/verify/lvs/CONTRACT.md and this project's ASIC/lvs-flow/run_lvs.sh declare
# these four with identical wording - "standard-cell simulation Verilog
# (Front-End view)", "real transistor CDLs for hard macros" - and $(LVS_SCRIPT)
# is what actually invokes them.
#
# DERIVED, NEVER SPELLED. Every PDK path comes from pdk_paths.sh via
# ../common.mk: the release directories in those paths name which deck revision
# and which libraries this site is licensed for, and this repository is public.
# Deriving also means run_lvs.sh and this manifest cannot drift onto different
# decks.
LVS_DECK         ?= $(PDK_LVS_DECK)
LVS_SOURCE_ADDED ?= $(PDK_LVS_SOURCE_ADDED)

# THE _pwr.v SUFFIX IS THE WHOLE THING. This design's _pnr.v wires .VDD/.VSS on
# every standard-cell instance, so the leaf stubs must declare those pins too or
# Calibre rejects the entire source with "Wrong pin count" and never reaches a
# compare - measured at 256 errors on the legacy flow. TSMC ships both variants
# side by side and pdk_paths.sh keeps the basename for exactly this reason.
STDCELL_VLOG ?= $(PDK_STDCELL_VLOG)
IO_VLOG      ?= $(PDK_IO_VLOG)

# The eight hard macros this chiplet instances. These are the part of the run
# that is real verification: they are never black-boxed, and their interiors
# compare device-for-device against the macro GDS merged into the stream. A macro
# instanced but not listed gets "No matching .SUBCKT" and the compare is
# worthless, so this list must agree with the P&R GDS merge list.
#
# THE ROMs COME FROM THIS RUN, NOT THE SHARED TREE. $(ROMLIBS_DIR) is
# $(ROM_RUN_DIR) here, i.e. build/$(RUN_TAG)/romlibs - the ROMs actually built
# into THIS stream. Comparing a stream against a ROM it does not contain is
# precisely the failure the ROM gates exist to catch. A RUN_TAG whose romlibs
# were never built reports `MISS MACRO_CDLS <path>` per file in preflight.
MACRO_CDLS ?= \
    $(MEM_BASE)/rf_01k/rf_01k.cdl \
    $(MEM_BASE)/rf_08k/rf_08k.cdl \
    $(MEM_BASE)/rf_16k/rf_16k.cdl \
    $(MEM_BASE)/rf_32k/rf_32k.cdl \
    $(MEM_BASE)/flash_cache_data/flash_cache_data.cdl \
    $(MEM_BASE)/flash_cache_tag/flash_cache_tag.cdl \
    $(ROMLIBS_DIR)/cc_rom/rom_via.cdl \
    $(ROMLIBS_DIR)/eth_rom/eth_rom_via.cdl

# ── WHY DRC_DECK IS DELIBERATELY EMPTY ──────────────────────────────────────
# This is what reconciles the toolkit's drc-project recipe with this project's
# run_drc.sh. The recipe passes five things - DRC_GDS, DRC_RUNDIR, DRC_CPUS,
# DRC_DECK, BLOCK - and run_drc.sh branches on DRC_DECK:
#
#   DRC_DECK non-empty -> run THAT deck verbatim  (the wrapper / A-B path)
#   DRC_DECK empty     -> ASSEMBLE the project deck via make_project_deck.sh
#                         (derived header + verbatim foundry body: the SIGNOFF
#                         path, and the only form that can clear WLCSP_SEALRING
#                         and set the real xLB/yLB/xRT/yRT)
#
# mk/flow.mk defaults DRC_DECK to $(ASIC_DIR)/calibre/$(BLOCK).drc.rules, which
# does not exist on this project - the decks live beside their assembler in
# ../genus-innovus/scripts/calibre - so `make drc` died with "DRC_DECK
# unreadable" before Calibre started. Emptying it selects the assembling branch.
#
# `:=` AND IT MUST BE ABOVE THE include BELOW. flow.mk uses `?=`, which tests
# whether a variable is DEFINED, not whether it is non-empty, so an empty
# definition made first wins and one made afterwards is silently discarded.
# Passing a real deck path on the command line still gets the verbatim path.
DRC_DECK :=


# ── 10. THE ENGINE ──────────────────────────────────────────────────────────
# Nothing above this line knows anything about the toolkit's internals.
include $(ASIC_FLOW_DIR)/mk/flow.mk


#-----------------------------------------------------------------------------
# 11. THE PROJECT-SIDE WIRING
#
# Below the engine, deliberately: these targets need $(RUN_DIR), $(OUT_DIR) and
# $(SYN_OUT_DIR), which mk/flow.mk computes with `:=`. Nothing here ASSIGNS a
# contract variable - a `?=` after the engine would be discarded, and a `:=`
# would be worse.
#-----------------------------------------------------------------------------

# ── THE FIVE VALUES make_project_deck.sh REQUIRES FROM THE ENVIRONMENT ──────
# The other half of the DRC_DECK note above. Having selected the assembling
# branch, run_drc.sh execs make_project_deck.sh, which takes BLOCK,
# DIE_XLB/YLB/XRT/YRT and FOUNDRY_DECK from the ENVIRONMENT with no default for
# any of them - a default would be a second, uncross-checked copy of the design's
# identity. The toolkit's drc-project recipe passes BLOCK and nothing else, so
# the remaining five are exported here.
#
# These are RENAMES, not new facts: DIE_* come from $(DRC_DIE_*), which mk/drc.mk
# derives by reading `create_floorplan ... -die_size` straight out of
# $(FLOORPLAN_TCL) - the same derivation from the same file as
# ../genus-innovus/drc_project.mk, so the die box the deck checks cannot drift
# from the die P&R built.
#
# BELOW THE include, AND THAT IS LOAD-BEARING: mk/drc.mk is included last, so
# DRC_DIE_* and DRC_FOUNDRY_DECK do not exist until then. `export NAME = value`
# is recursively expanded when a recipe runs, so it places no ordering demand.
export DIE_XLB      = $(DRC_DIE_XLB)
export DIE_YLB      = $(DRC_DIE_YLB)
export DIE_XRT      = $(DRC_DIE_XRT)
export DIE_YRT      = $(DRC_DIE_YRT)
export FOUNDRY_DECK = $(DRC_FOUNDRY_DECK)

# ── THIS RUN'S BOOT ROM DIRECTORY ──────────────────────────────────────────
# The macros are compiled per run into $(RUN_DIR)/romlibs and the run is pinned
# to that build (../rom_build.mk), so a finished run under build/<RUN_TAG>/
# carries the exact .lib/.lef/.gds2 it was made from.
#
# `=`, NOT `:=` AND NOT `?=`:
#   * `?=` would be a no-op - ../common.mk reaches ../rom_build.mk, which has
#     already defaulted ROM_RUN_DIR to the shared drop, so every run would
#     quietly keep using ASIC/romlibs.
#   * `:=` would expand RUN_DIR now, and RUN_DIR does not exist yet (mk/flow.mk
#     defines it, and ../Makefile includes this file first), giving the literal
#     "/romlibs".
# Deferred expansion resolves it when a recipe runs. A command-line
# ROM_RUN_DIR= still wins over both.
ROM_RUN_DIR         = $(RUN_DIR)/romlibs

# Exported because config/design_config.tcl reads it to locate this run's ROMs.
# That one export is what makes synthesis, P&R and stream-out open one build
# rather than three reads of a shared directory.
export ROMLIBS_DIR  = $(ROM_RUN_DIR)

.PHONY: legacy-paths asic-flist romlibs-check rom-ensure cpf-patch

# ── STAGE ORDERING, AND THE ROM WRITE-WRITE RACE ────────────────────────────
#
# There is deliberately NO `.NOTPARALLEL:` here. `all` in ../asic-toolkit/mk/
# flow.mk is not a prerequisite list; it is a RECIPE of four sequential
# sub-makes (syn, place, cts, route). Recipe lines run in sequence by definition
# at every -j, so stage ordering does not depend on a directive this project has
# to remember, and unrelated targets keep their parallelism. The bare directive
# is also the only form available here - the scoped `.NOTPARALLEL: targets` is
# GNU Make 4.4 and these hosts are 4.2.1, where it serialises the WHOLE makefile.
#
# The resume model is unaffected: `make cts IN_RUN_TAG=...` still runs cts alone,
# because no stage was ever a prerequisite of another.
#
# WHAT SERIALISING THE WHOLE MAKEFILE WAS ALSO COVERING: the prerequisites WITHIN
# one stage. `syn` carries two that overlap - `rom-ensure` and `romlibs-check`
# below can each reach `rom-run`, writing the same $(ROM_RUN_DIR) and the same
# .rom_pin.json. As unordered siblings, `make -j syn` on a cold tree can start
# both, which is a write-write race on mask-programmed ROM content. That is not a
# failed build; it is a build that succeeds carrying the wrong bits into a
# reticle. The order-only barrier `romlibs-check: | rom-ensure` below closes it
# and costs nothing serially.

# ── THE LEGACY-PATH BRIDGE ──────────────────────────────────────────────────
#
# THE PROBLEM. Three of the live files this manifest points at name a sibling
# directory by a path RELATIVE to the tool's working directory:
#
#   scripts/floorplan.tcl        read_io_file ../scripts/$(BLOCK).io
#   scripts/place_bondpads.tcl   source ../scripts/filler.tcl
#   inputs/constraints.sdc       source ../inputs/{qspi,tidelink,ethernet,i2c}_constraints.sdc
#
# In production the tool runs in ../genus-innovus/work, so `../` is
# ../genus-innovus and all seven resolve. Under the toolkit it runs in
# $(BUILD_DIR)/$(RUN_TAG)/work, so `../` is the run directory and none do.
#
# THE FIX. Two symlinks in the run directory make `../scripts` and `../inputs`
# mean what they mean in production, so the live files are consumed BYTE FOR BYTE
# with no edit anywhere. Copying the files here would start them drifting;
# rewriting them to absolute paths would edit Tcl a running production flow
# depends on. The links live under BUILD_DIR, which is disposable output.
#
# `rm -rf` DOES NOT FOLLOW SYMLINKS, so `make clean` / `make distclean` remove
# the links and never the live directories. That is the one property that makes
# this safe.
#
# THIS IS A BRIDGE, NOT AN ARCHITECTURE. The end state is `$IO_FILE` in the
# floorplan and a constraints/ directory of numbered files; both are equivalence
# work, and neither can be done honestly before there is a toolkit run to be
# equivalent to.
legacy-paths:
	@mkdir -p "$(RUN_DIR)"
	@for d in scripts inputs; do \
	    link="$(RUN_DIR)/$$d"; \
	    if [ -e "$$link" ] && [ ! -L "$$link" ]; then \
	        echo "FAIL: $$link exists and is not a symlink."; \
	        echo "      The legacy-path bridge needs that name. Move it aside."; \
	        exit 1; \
	    fi; \
	    ln -sfn "$(LEGACY_ASIC_DIR)/$$d" "$$link"; \
	done
	@# Assert through the link, not beside it. A link that resolves nowhere is
	@# the failure this target exists to prevent, and it is invisible otherwise.
	@for f in "scripts/$(BLOCK).io" "scripts/filler.tcl" \
	          "inputs/constraints.sdc" "inputs/qspi_constraints.sdc" \
	          "inputs/tidelink_constraints.sdc" "inputs/ethernet_constraints.sdc" \
	          "inputs/i2c_constraints.sdc"; do \
	    test -r "$(RUN_DIR)/$$f" || { \
	        echo "FAIL: $(RUN_DIR)/$$f is not readable through the bridge."; \
	        echo "      It should resolve to $(LEGACY_ASIC_DIR)/$$f"; \
	        exit 1; }; \
	done

## Re-render the generated sub-flists, so the TideLink V2 / SoC selection cannot
## go stale. $(RTL_FLIST) -f-includes build/chip/flist/{soc,tidelink_asic}.flist,
## which this produces. Delegated to the top-level make, which sources the three
## set_env.sh scripts in dependency order.
asic-flist:
	$(MAKE) -C $(NANOSOC_ETH_CHIPLET_HOME) --no-print-directory asic-flist

## ── THE BOOT ROMs, BUILT FOR THIS RUN ──────────────────────────────────────
## Genus reads the two ROM .libs through the library search path; without them
## `syn` dies inside set_db with "Cannot open file rom_via_*.lib", ten minutes in.
##
## THIS IS A BUILD, NOT ONLY A CHECK. `rom-run` compiles both macros into THIS
## run's directory ($(ROM_RUN_DIR) = $(RUN_DIR)/romlibs) from a content-addressed
## cache, pins the run to that build, and then runs the full word-for-word gate
## against what it just built. The macros are mask programmed and the shared drop
## this target used to verify had already shipped the wrong bits twice.
##
## ROM_RUN_DIR GOES ON THE SUB-MAKE COMMAND LINE: ../common.mk assigns
## ROMLIBS_DIR with `:=`, and a makefile assignment beats an exported environment
## variable, so an export alone would have the sub-make build and verify the
## shared drop while the tools read the run.
romlibs-check:
	@$(MAKE) -C $(NANOSOC_ETH_CHIPLET_HOME)/ASIC -f common.mk --no-print-directory \
	    rom-run ROM_RUN_DIR=$(ROM_RUN_DIR) || { \
	    echo ""; \
	    echo "The boot ROMs for this run did not build or did not verify (above)."; \
	    echo "  needs: a LOCAL-DISK compiler mirror and the bootloader firmware built"; \
	    echo "     make -C ASIC -f common.mk rom-compiler-stage"; \
	    echo "  no compiler on this host? adopt a prebuilt tree, recorded as imported:"; \
	    echo "     make -C ASIC -f common.mk rom-run ROM_RUN_DIR=$(ROM_RUN_DIR) \\"; \
	    echo "          ROM_IMPORT_FROM=<a tree holding cc_rom/ and eth_rom/>"; \
	    echo "  a PIN CONFLICT is the gate working: this run is already pinned to a"; \
	    echo "  different ROM build. Start a new RUN_TAG rather than re-pinning."; \
	    exit 1; }

## The cheap per-stage guard - see ../rom_build.mk. Placement reads the ROM LEF
## and stream-out merges its GDS, hours after synthesis read the .lib; this is
## what makes those three one build. A no-op when the run is already staged.
rom-ensure:
	@$(MAKE) -C $(NANOSOC_ETH_CHIPLET_HOME)/ASIC -f common.mk --no-print-directory \
	    rom-run-ensure ROM_RUN_DIR=$(ROM_RUN_DIR)

# ── THE CPF PATCH, AND WHY IT IS HERE RATHER THAN IN hooks/ ─────────────────
#
# Genus cannot translate this design's UPF supply commands to CPF ("Unable to
# translate command 'create_supply_net' ... from 1801 to CPF format"), so the CPF
# it writes contains only
#     create_power_domain -name PD_TOP -default
# with no power net and no ground net. Innovus then fails EVERY filler pass with
# IMPSP-5110, `add_fillers` reports "For 0 new insts", and the flow completes and
# streams a GDS. The repair is not an Innovus command - `update_power_domain` in
# this build has no -primary_power_net option - so it belongs in the CPF text
# before Innovus reads it.
#
# THERE IS NO HOOK POINT FOR IT. The CPF is written between two hooks and read
# before the next:
#   flow/genus/1_synthesis.tcl   flow_hook post_synth      <- too EARLY
#   flow/genus/1_synthesis.tcl   write_power_intent -cpf   <- the CPF appears
#   (synthesis ends; no further hook)
#   flow/innovus/2_place.tcl     read_power_intent -cpf    <- reads it
#   flow/innovus/2_place.tcl     flow_hook pre_floorplan   <- too LATE
# So the patch is wired at the MAKE layer - `place: cpf-patch` below - which is
# the only layer between the two tools, and where the production flow puts it.
#
# An unpatched CPF is now a loud stop in two independent places rather than a
# silent scrap die: flow/innovus/2_place.tcl tests the CPF text for
# create_power_nets / create_ground_nets and dies if absent, and power_plan.tcl
# asserts the same three statements. This target stops it happening at all.
#
# Idempotent. Patches the SYNTHESIS run's CPF, which is where the place stage
# reads it from ($(SYN_OUT_DIR), i.e. SYN_RUN_TAG's outputs, not this run's).
cpf-patch:
	@cpf="$(SYN_OUT_DIR)/$(BLOCK)_gate1.cpf"; \
	test -s "$$cpf" || { \
	    echo "FAIL: no CPF at $$cpf"; \
	    echo "      Genus writes it during 'make syn'; the '1' in the name is"; \
	    echo "      the tool's own -base_name counter, not a typo."; \
	    echo "      If synthesis ran under a different tag, pass SYN_RUN_TAG."; \
	    exit 1; }; \
	if grep -q 'create_power_nets' "$$cpf"; then \
	    echo "OK: CPF already carries its supply nets"; \
	else \
	    grep -q 'end_design' "$$cpf" || { \
	        echo "FAIL: $$cpf has no end_design - unexpected format"; exit 1; }; \
	    sed -i 's/^end_design/create_ground_nets -nets VSS\ncreate_power_nets -nets VDD\n\nupdate_power_domain -name PD_TOP -primary_power_net VDD -primary_ground_net VSS\n\nend_design/' "$$cpf"; \
	    grep -q 'update_power_domain' "$$cpf" || { \
	        echo "FAIL: CPF patch did not apply"; exit 1; }; \
	    echo "OK: patched $$cpf with VDD/VSS supply nets (add_fillers needs them)"; \
	fi

# ── THE EXTRA PREREQUISITES ─────────────────────────────────────────────────
#
# Prerequisite-only rules: no recipe, so the engine's own recipes are untouched
# and make merges the lists. This is the whole of the consumer wiring.
#
#   every stage    the legacy-path bridge, and the patched IO-driver LEF - both
#                  before any tool opens a file. pad-lef (../common.mk) derives
#                  that LEF from the read-only PDK; it is a build product, so it
#                  must exist before the tech pack reads TSMC65_IO_DRIVER_LEF.
#                  Idempotent and licence-free, so this costs nothing.
#   syn            the generated sub-flists and the ROM libraries
#   place          the CPF patch, between the two tools
syn place cts route: legacy-paths pad-lef rom-ensure
syn:   asic-flist romlibs-check
place: cpf-patch

# The order-only barrier. `|` makes rom-ensure a prerequisite for ORDERING only:
# romlibs-check is not rebuilt when rom-ensure runs, so this adds no work on any
# path. It exists solely so the two routes to `rom-run` cannot both open
# $(ROM_RUN_DIR) under `make -j syn`.
romlibs-check: | rom-ensure

# ── CTS derate ──────────────────────────────────────────────────────────────
# The toolkit defaults CTS_DERATE to 0 and warns when it is off. The production
# flow applies all four derate arms unconditionally and the toolkit's values are
# identical, so this is the difference between a signoff run and an optimistic
# one, not a tuning choice: removing derate improves the report, not the silicon.
#
# Innovus inherits the last defined value for any arm left unspecified, so a
# partial set silently mis-derates the rest. The toolkit sets all four together.
export CTS_DERATE ?= 1

# EXPORT IS LOAD-BEARING ON EVERY LINE ABOVE. The stage scripts read their knobs
# with `opt`, which resolves from ::env(...), so a bare `CTS_DERATE = 1` here is a
# make variable the tool never sees and the knob silently keeps its default. A
# 47-minute CTS run once took the toolkit's empty allowlist and its derate-off
# default despite both being set here, because neither was exported.

# ── Diagnosed message IDs ───────────────────────────────────────────────────
# The toolkit ships an EMPTY allowlist for every stage, deliberately: a default
# that tolerates IDs would hand each new project someone else's undiagnosed
# exemptions. So the exemptions belong HERE, per design, each with the diagnosis
# that earned it. Anything NOT on the list still fails the stage.
#
#   IMPLF-223     Duplicate LEF via definitions across the LEF list; Innovus
#                 ignores the later ones. Benign, docs/tapeout/16-open-defects.md.
#   IMPMSMV-3501  The power intent defines no power_mode/power_state, so
#                 always-on buffering is unsupported. This chip has ONE core
#                 power domain (docs/tapeout/11-known-issues.md (d)) - a
#                 consequence of a single-domain design, not a defect to fix.
#
# Both are properties of this design's collateral and would recur on every run.
#
# TCLCMD-917 IS NOT ON THIS LIST AND MUST NOT BE RE-ADDED. It was 71 instances of
# a set_multicycle_path applied to pad SUPPLY pins (VDDPST / VSS), which carry no
# timing arc, so the exception had no object to attach to. The upstream fix names
# the five signal pins explicitly - {I C PAD OEN REN} - instead of a uPAD*/*
# wildcard: SDC expansion 548 -> 480 entries, PG entries 68 -> 0, TCLCMD-917
# 21 -> 0, and setup/hold UNCHANGED across all seven path groups (the
# pre-registered falsification condition - a supply pin carries no arc, so any
# timing movement would have refuted the premise). The cause is gone, so a
# recurrence would be TCLCMD-917 arriving from a DIFFERENT constraint, which is a
# finding rather than noise; re-adding the ID would re-hide the whole class.
export PLACE_ERROR_ALLOWLIST ?= IMPLF-223 IMPMSMV-3501
# CTS adds six more, and every one is a state this design chose:
#   CHKCTS-18/19/20  buffer / inverter / clock-gating cells "not specified".
#                    PERMANENT AND INTENDED: config/design_config.tcl withdraws
#                    the tech pack's CKB*/CKN*/CKLHQ* patterns so CCOpt picks its
#                    own cells, matching the production flow (3,290 BUFFD1, which
#                    a CKB* list excludes). The tool is correctly reporting a
#                    deliberate choice.
#   CHKCTS-1/-2      no CTS max-transition target, 42 = trees x corners.
#   CHKCTS-9         no clock route_type, same 42.
#                    TRACKED DEBT, not permanent: the knobs that close them are
#                    CTS_TARGET_TRAN and CTS_ROUTE_TYPE. Remove these three from
#                    the list when the knobs are set, and expect the tree to
#                    change when they are.
#
# NOT allowlisted, deliberately: IMPSP-2021 "could not legalize 1 instance". That
# is a real placement failure - a CKBD16 clock buffer 2.4 um below the core's top
# edge with no legal site within 230 um - and adding it here would bury it.
export CTS_ERROR_ALLOWLIST   ?= IMPLF-223 IMPMSMV-3501 \
                                CHKCTS-18 CHKCTS-19 CHKCTS-20 \
                                CHKCTS-1 CHKCTS-2 CHKCTS-9
export ROUTE_ERROR_ALLOWLIST ?= IMPLF-223 IMPMSMV-3501


# ── 11. THE COUNTS THIS DIE IS, AND THE RATCHETS THAT HOLD THEM ─────────────
#
# Everything below is DESIGN DATA, not toolkit policy: a pin map's pad counts and
# a power plan's measured geometry. The toolkit defaults every one of these to
# "do not gate", which is why the numbers below went unchecked for so long.
#
# ── 11a. THE PAD RING ───────────────────────────────────────────────────────
#
# READ THIS BEFORE CHANGING A NUMBER HERE.
#
# `read_io_file` handed an IO file naming instances the netlist does not contain
# DOES NOT FAIL. It emits `**WARN: (IMPFP-53): Failed to find instance ...` once
# per instance, places the rest, and returns. On this design that was 34 warnings
# - EVERY SUPPLY PAD ON THE DIE - and the resulting database went through place,
# CTS, route and stream with every gate green, across three builds. The run WITH
# the pads even scored worse, because the only gate that could see the difference
# (unrouted PG nets) was an upper bound, and losing the pads made the count go
# DOWN.
#
# Counted from scripts/nanosoc_eth_chiplet_pads.io, the file read_io_file reads:
# 12 VDDIO, 12 VSSIO, 6 VDD, 4 VSS = 34 supply pads, in a ring of 86 instances
# (82 IO + 4 corners).
export PLACE_EXPECT_PADS      ?= VDDIO=12 VSSIO=12 VDD=6 VSS=4
export PLACE_EXPECT_PAD_INSTS ?= 86

# MIND THE SEPARATOR - measured, not theorised. Against this design's 86 pad
# names:
#     uPAD_%RAIL%_*   VDD -> 6    VSS -> 4     correct
#     uPAD_%RAIL%*    VDD -> 18   VSS -> 16    VDDIO and VSSIO swallowed
# The second spelling double-counts, agrees with the expected TOTAL, and
# describes a different set of pads. The engine refuses a pattern whose rails
# overlap rather than trusting either. Left at the toolkit default deliberately:
# this note names the trap, it does not change the value.

# ── 11b. THE PG RATCHETS, FROM MEASURED VALUES ──────────────────────────────
#
# BOTH DEFAULT TO -1 IN THE TOOLKIT, WHICH MEANS DO NOT GATE, and both sat at -1
# for the whole life of this project. They are ratchets and nobody ratcheted them.
#
# THE MEASUREMENT SET IS PAD-CORRECT RUNS ONLY. Runs missing their supply pads
# have a different power grid, and pooling their geometry with a correct one is
# the mistake the provenance block exists to stop.
#
#   rv_vias_to_AP   7 on all ten pad-correct runs. FLOOR 6, one below measured.
#                   This number's failure mode is collapse toward zero (this
#                   project's own record is 14 -> 9 -> 7 across power-plan
#                   configurations), so a floor AT 7 would fire on a legal
#                   one-via change while 6 still fires on any real loss. There is
#                   no IR-drop analysis in this flow; this count is the only
#                   thing standing in for one.
#   m5_fragments    3399 max across pad-correct runs, spread 23 (0.68%).
#                   CEILING 3570 = +5%: seven times that spread, and twice the
#                   spread across every archived run. The documented failure -
#                   the grid coming apart - is a third more fragments, so it is
#                   caught with a factor of six in hand.
#
# WHAT THESE DO NOT SAY. A ratchet set from today's number reports a REGRESSION
# and nothing else. 3399 fragments is roughly 2.3x the ceiling this grid was
# suggested to have, and the structural cure named in power_plan.tcl - one M5
# ladder over the whole core instead of one per row region - is still not done.
# Do not read a green here as a verdict on the grid.
export PLACE_MIN_PG_VIAS  ?= 6
export PLACE_MAX_PG_FRAGS ?= 3570

# ── 11c. NETS WITH NO ROUTING AT ALL ────────────────────────────────────────
#
# MEASURED 2 on the pad-correct runs, 0 on the runs whose supply pads had been
# deleted. That inversion is why this knob is an EQUALITY in the toolkit rather
# than a ceiling: the broken database was the quiet one, and a ceiling cannot see
# quiet.
#
# The two are supplies distributed by ABUTMENT through the pad-ring fillers.
# check_connectivity gives up on a net with no routing at all, so nothing in this
# flow verifies that bus is continuous - and that has always been true. What is
# new is that a run which loses them now fails instead of passing.
export ROUTE_EXPECT_UNROUTED ?= 2

# ── 11d. PG STRIPES INSIDE MACRO FOOTPRINTS ─────────────────────────────────
#
# EXPECT THE FIRST RUN AFTER THIS LANDS TO FAIL HERE, AND READ THE REPORT RATHER
# THAN RAISING THE KNOB. This is a new measurement of a state this design has
# always been in, not a regression, and the count it prints is a defect list.
#
# The mechanism is written down in this project's own power_plan.tcl above the M5
# pass: `split_row -selected` gives every macro its own row region and add_stripes
# re-anchors PER REGION, so `-start_offset 8` does not mean "8um up from the
# core" - it means EVERY MACRO gets M5 straps buried 8.0-9.0 and 9.5-10.5um
# INSIDE ITS OWN FOOTPRINT, repeating every 15um. Two macros side by side anchor
# two ladders that alias: a 2.72 um macro move against 2.70 um of clearance
# overshot by 20 NANOMETRES and produced four VDD-VSS rail shorts, with four more
# macro pairs 0.41-0.45 um from the same window. Nothing in this flow asked
# whether a stripe was inside a macro at all; the shorts surfaced at check_drc,
# hours later, inside a budgeted total the same change had reduced.
#
# THREE HONEST RESPONSES, in order of preference:
#   1. the structural fix power_plan.tcl already names - one M5 ladder over the
#      whole core instead of one per row region. It closes this AND the
#      macro-blockage DRC class, and is the only one that removes the hazard.
#   2. ratchet PLACE_MAX_MACRO_STRIPES to the measured count, WITH the count and
#      this defect named beside it. A regression detector, nothing more.
#   3. set PLACE_MACRO_PG_CHECK=0, only with a written reason. It returns this
#      design to the state it was in when the shorts arrived.
#
# Left at the toolkit default of 0 deliberately: naming the knob without setting
# it is the point, since an unratcheted default is exactly how the two ratchets
# above sat inert. The NEAR-MISS arm (PLACE_MIN_MACRO_PG_GAP) stays ungated until
# it has been measured on this design - the clearances above come from
# power_plan.tcl's aliasing arithmetic, not from this census, and a floor set from
# another instrument's number is not a ratchet. The census reports the value every
# run, so a CHANGE is visible meanwhile.

# ── 11e. MISSING POWER VIAS, OVER THE WHOLE STACK ───────────────────────────
#
# Same shape, same instruction. The toolkit asks check_power_vias about
# routing_layer_bottom..top_metal_layer rather than the coarse stripe layer, and
# PARSES the answer - the report had been written into reports/ for months and
# read by no gate, no manifest line and no person.
#
# What the two ranges say about ONE database, four minutes apart:
#     {coarse stripe .. top}      4 missing
#     {bottom .. top-1}         556 missing - 452 of them in a single mid-stack
#                               layer pair, 357 on one rail and 199 on the other
#
# The full-stack range has never been run to the TOP layer here, so the true
# number is 556 plus whatever the last interface adds. Do NOT write
# ROUTE_BUDGET_PG_VIAS from arithmetic on those two: run it once, then ratchet
# with the per-layer-pair split recorded beside it.

# ── 11f. METAL DENSITY IS THE FOUNDRY'S ─────────────────────────────────────
#
# This die goes out as a shuttle submission through a broker who fills the frame
# after merging the standard-cell and IO layouts in. Filling here first would hand
# over metal that is about to be filled again, so ROUTE_METAL_FILL stays 0 and
# that is the CORRECT setting rather than a gap.
#
# METAL_FILL_OWNER changes what the run is allowed to CONCLUDE, not what it does.
# Without it an unfilled design fails the density check by construction and every
# failing window lands in the route stage's HARD list - measured at 13 hard
# failures, ALL density, on an obligation already contracted out, burying eight
# signoff budgets that ARE ours (check_drc including shorts, PG opens, dangling
# PG wires, setup and hold FEP).
#
# Setting the owner does NOT stop the measurement, does NOT waive anything, and
# does NOT cover a density report that could not be PARSED - that stays hard under
# either owner, because "who inserts the metal" and "did anyone look" are
# different questions. The count still reaches the manifest as density_windows
# alongside metal_fill_owner, and the console reads "OK, WITH n ITEM(S) DECLARED
# ELSEWHERE" rather than OK.
#
# THE HANDOFF IS WHAT THIS DEPENDS ON, and nothing in this flow re-checks it. It
# is in the submission correspondence; keep it there.
export METAL_FILL_OWNER ?= foundry


# ── 12. THE DESIGN REPORT ───────────────────────────────────────────────────
#
# What the chip IS, as opposed to whether it passed: gate count, die area,
# utilisation, memory, power. Regenerated by mk/report.mk after every stage into
# $(REPORT_DIR)/design_report.{json,md,html}. It reads report files a stage has
# already written, costs no licence and cannot fail a build.
#
# EVERYTHING BELOW IS A DESIGN FACT THE TOOLKIT CANNOT INFER. Left unset, the
# metrics that depend on it render as NOT MEASURED, never as a plausible default.

# The standard-cell library, spelled as Genus names it in syn_gates.rep.
#
# THIS IS THE NUMERATOR OF THE GATE COUNT and it is not guessable: this design
# links NINE libraries - seven memory compilers, the IO pads, and this one.
# "The one with the most instances" is right here (187,118 of 187,221) and would
# be wrong on any IO-dominated die, so the toolkit refuses to pick.
DESIGN_REPORT_STDCELL_LIB := tcbn65lpwc

# The gate-equivalent unit. Its AREA IS READ FROM THE REPORT (1.44 um2 here),
# never typed, so the ratio always uses this library's own number.
DESIGN_REPORT_NAND2_CELL := ND2D1

# Core box inset from each die edge, in um. The ONE piece of floorplan geometry
# the flow cannot derive: create_floorplan takes the core-to-IO clearance but the
# pad height comes from the IO cell's LEF.
#
#     135  the IO pad cells' LEF SIZE height
#    + 70  CORE_TO_IO, per ../genus-innovus/scripts/floorplan.tcl
#    = 205 giving a core box of (205,205)-(1395,1795) = 1190 x 1590 um
#
# KEEP THIS IN STEP WITH floorplan.tcl's CORE_TO_IO: this is a second copy that
# will not notice if that value moves again.
DESIGN_REPORT_CORE_INSET := 205

# Masthead copy.
DESIGN_REPORT_TITLE    := nanoSoC Ethernet Chiplet
DESIGN_REPORT_TECH     := TSMC 65nm LP
DESIGN_REPORT_SUBTITLE := A dual-Cortex-M0+ networking chiplet: 10/100 Ethernet with IEEE 1588 hardware timestamping, on-die SRAM and boot ROM, and an eight-lane die-to-die link for pairing with a compute die.
