#-----------------------------------------------------------------------------
# nanosoc-ethernet-chiplet / ASIC/eth-chiplet/design.mk
#
# The design manifest the nanoSoC ASIC Toolkit reads. It is the ONE file that
# tells the toolkit's engine what this chiplet is.
#
# ── THE RULE THIS FILE IS BUILT ON ─────────────────────────────────────────
#
# THE LIVE FILES ARE THE SOURCE OF TRUTH. Every path below points at the file
# ../genus-innovus actually uses today. Nothing has been copied here, because a
# copy is a snapshot: the toolkit's own worked example harvested five of these
# files and every one of them has since drifted 169-540 lines from its live
# counterpart, silently. A pointer cannot drift.
#
# Consequence: this manifest is ADDITIVE and reversible. Deleting this whole
# directory changes nothing about `make -C ASIC/genus-innovus pnr_all`, which
# remains the only path that has produced a GDSII.
#
# ── WHAT THIS FILE IS NOT ──────────────────────────────────────────────────
#
# It is not evidence that the toolkit can build this chip. No toolkit-produced
# netlist or GDSII exists, here or anywhere. What it IS: the consumer wiring,
# checkable without a licence, so that when a seat is available the first run
# fails (if it fails) on something real rather than on a path.
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------


# ── 0. REPO ROOTS ───────────────────────────────────────────────────────────
#
# DEFINED FIRST, AND THAT MATTERS. `:=` in make is IMMEDIATE, so anything a
# later `:=` line dereferences must already exist. A repo root defined at the
# bottom expands to empty up here and `$(EMPTY)/flist/x.flist` becomes
# `/flist/x.flist` - an absolute path that looks plausible and does not exist.
#
# Derived from THIS FILE's own location rather than from $(CURDIR), so
# `make -C ASIC/eth-chiplet` and `make -f ASIC/eth-chiplet/design.mk` agree.
ETH_CHIPLET_ASIC_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
export NANOSOC_ETH_CHIPLET_HOME ?= $(abspath $(ETH_CHIPLET_ASIC_DIR)/../..)


# ── 0b. THE PROJECT ENVIRONMENT, FROM ITS ONE DEFINITION ────────────────────
#
# ../common.mk is where this repository defines every environment variable the
# flists and the SDCs dereference: ARM_IP_LIBRARY_PATH, CMSDK_DIR, TIDELINK_HOME,
# TIDECHART_HOME, ETH_SS_HOME, PHC_AHB_HOME, SOCLABS_*, TSMC_65_HOME, PHYS_IP,
# DESIGN_HOME, CLK_PERIOD - about thirty of them, all `?=`.
#
# INCLUDED, NOT RETYPED. The toolkit's worked example retypes fourteen of them
# into its design.mk, which is a second copy of a list that already exists and
# is already maintained. The example's copy is ALREADY WRONG in one place: it
# omits ETHMAC_IP_DIR, HA1588_IP_DIR, AHB_BRIDGES_HOME, IPC_MAILBOX_HOME,
# SOCLABS_NANOSOC_*, and the flist tree dereferences several of them. Genus
# reads the whole SoC and only then dies on the first unset variable - about ten
# minutes in, after every other file has loaded, so it reads as a link error.
#
# ../common.mk is also where TSMC_65_HOME, DESIGN_HOME and SOCLABS_ASIC_FLOW_DIR
# are defined, which is what the brief for this manifest points at. One include
# is the whole of section 6 of the toolkit's template.
#
# It brings targets with it - eth-bintxt, romlibs-preflight, romlibs-verify,
# tsmc_65_romlibs, gen_memories. None collides with a toolkit target, and
# `romlibs-check` below depends on one of them deliberately.
include $(ETH_CHIPLET_ASIC_DIR)/../common.mk

# Where the production flow's collateral lives. Everything in section 4 and
# section 5 is under here; nothing is duplicated into this directory.
LEGACY_ASIC_DIR := $(NANOSOC_ETH_CHIPLET_HOME)/ASIC/genus-innovus


# ── 1. IDENTITY ─────────────────────────────────────────────────────────────

# The PAD RING, not the core. `nanosoc_eth_chiplet` is the inner top;
# `nanosoc_eth_chiplet_pads` wraps it in the IO ring and is what gets taped out.
# Source: ../genus-innovus/scripts/config.tcl:127  `set block_name ...`
# and     ../genus-innovus/drc_project.mk:62       `BLOCK ?= ...`
BLOCK := nanosoc_eth_chiplet_pads

# Source: ../common.mk  TSMC_65_HOME (the site PDK mount, named there and only
# there), and every library path in
# scripts/config.tcl. The pack owns the standard cells, the IO library, the tech
# LEF, the cap tables, the layer names and the stream-out map.
TECH  := tsmc65

# THE TWO SITE VARIABLES THE PACK NEEDS, AND WHY THEY LIVE HERE AND NOT THERE.
#
# tech/tsmc65 declares exactly two `tech_env` variables and defaults NEITHER:
#
#     TSMC_65_HOME        the TSMC PDK mount            (../common.mk:94)
#     ARM_CLN65LP_TECH    ARM's cln65lp arm_tech package -- the RC cap tables
#                         under cadence_captable/. A SEPARATE deliverable from
#                         the PDK, installed separately, in a shared read-only
#                         IP tree. NEVER write into it (see CLAUDE.md).
#
# ARM_CLN65LP_TECH used to fall back to this lab's mount inside the pack. That
# default was removed on 2026-08-13 when the toolkit was cleared for publication:
# a public repository must not carry one site's filesystem layout, and a pack
# that silently defaults to a path the reader does not have produces a run that
# looks configured and is not. The pack now fails at load naming the variable.
#
# THAT CHANGE BROKE A RUN, WHICH IS THE POINT. `make route RUN_TAG=m5off6` died
# at tech_load with "environment variable ARM_CLN65LP_TECH is not set" after
# place and CTS had already completed -- loudly, at the first stage that needed
# it, instead of quietly using someone else's cap tables. This block is the fix,
# and the site fact now lives with the project instead of inside the toolkit.
#
# `?=`, so a shell export or ci/site.env still wins.
# Resolved, not spelled: `arm_tech/<rel>` names the Arm release this site
# licensed, and this repository is public. pdk_paths.sh globs it (exactly one
# is installed) off $(PHYS_IP), which ../common.mk already names. Same tree as
# before -- `make -C .. -f common.mk pdk-paths` re-proves it.
export ARM_CLN65LP_TECH ?= $(shell TSMC_65_HOME='$(TSMC_65_HOME)' PHYS_IP='$(PHYS_IP)' \
                             $(PDK_PATHS_SH) arm-tech-dir 2>/dev/null)

# WHERE THE TOOLKIT IS. Two answers, and which one is right changes on the day
# the submodule swap lands - so this resolves rather than asserts.
#
#   ASIC/asic-toolkit          the submodule, once `git submodule add` has run
#   ../nanoSoC-ASIC-Toolkit    the sibling working clone, which is where the
#                              toolkit is being developed today
#
# Probed on mk/flow.mk rather than on the directory: an uninitialised submodule
# is an empty directory that passes every `test -d`.
#
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
# Source: ../common.mk:124  `export ASIC_FLIST := .../nanosoc_eth_chiplet_asic.flist`
# Named explicitly rather than inherited, because ../common.mk ALSO exports a
# bare `FLIST` (the SoC's own flist, nanosoc_multicore_asic.flist) and the
# toolkit accepts FLIST as a legacy alias for RTL_FLIST. Leave RTL_FLIST empty
# and the toolkit would build the SoC instead of the chiplet, with no warning.
RTL_FLIST := $(NANOSOC_ETH_CHIPLET_HOME)/flist/nanosoc_eth_chiplet_asic.flist

# TideLink's PHY is selected by define, not by flist.
# Source: ../genus-innovus/scripts/read_flist.tcl:38
#         `read_hdl -define TIDELINK_PHY_V2 -language sv $file`
RTL_DEFINES ?= TIDELINK_PHY_V2

# The generated pad-ring wrapper (nanosoc_gen SoCPadRingBackend). It is outside
# the flist, so the flow reads it last.
# Source: ../genus-innovus/scripts/config.tcl:133  `set top_level_hdl ...`
TOP_HDL ?= $(NANOSOC_ETH_CHIPLET_HOME)/ASIC/tech_wrappers/tsmc65/nanosoc_eth_chiplet_pads.v

# Source: ../asic-flows/Cadence/1_synthesis.tcl:35
#         `read_hdl -define POWER_PINS $top_level_hdl`
#
# MEASURED INERT FOR THIS WRAPPER: `grep -c POWER_PINS` on the wrapper above is
# 0, so the define selects nothing today. Set anyway, because the production
# flow sets it and equivalence between the two flows is the whole point of this
# directory - and because a regenerated wrapper could start using it.
TOP_HDL_DEFINES ?= POWER_PINS


# ── 3. WHERE THE FLOW WRITES ────────────────────────────────────────────────
#
# Everything a run produces goes to $(BUILD_DIR)/$(RUN_TAG)/{work,logs,reports,
# outputs}. Deliberately NOT ../genus-innovus/{work,logs,reports,outputs}: while
# the two flows are being compared, a toolkit run must not be able to overwrite
# the production tree, and a `make distclean` typed in the wrong directory must
# not be able to delete the shipped GDS.
#
# Do NOT set OUT_DIR / REPORT_DIR / LOG_DIR / WORK_DIR here - the engine derives
# all four with `:=` and is included last, so anything set here is discarded.
# (The toolkit's worked example sets all four. They have no effect.)
BUILD_DIR ?= $(ETH_CHIPLET_ASIC_DIR)/build
RUN_TAG   ?= default

IN_RUN_TAG  ?= $(RUN_TAG)
SYN_RUN_TAG ?= $(RUN_TAG)


# ── 4. PROJECT-SIDE FILES - ALL OF THEM LIVE, NONE OF THEM COPIED ───────────

# NEW, and the only Tcl file this directory owns. The production
# scripts/config.tcl cannot be used as DESIGN_CONFIG_TCL: see the header of
# config/design_config.tcl for the four specific reasons, each measured.
DESIGN_CONFIG_TCL ?= $(ETH_CHIPLET_ASIC_DIR)/config/design_config.tcl

# The live floorplan - die box, IO ring, 21 macro coordinates, ::PLACED_MACROS.
# Source: ../genus-innovus/scripts/floorplan.tcl (die 1600x2000, line 104).
# Consumed unchanged. Its one relative reference resolves through the
# `legacy-paths` bridge at the bottom of this file.
FLOORPLAN_TCL ?= $(LEGACY_ASIC_DIR)/scripts/floorplan.tcl

# The live power plan - global nets, core rings, stripes, row splitting over
# ::PLACED_MACROS, endcaps, risers. Consumed unchanged; it reads only $OUT_DIR
# and ::PLACED_MACROS from outside itself, and the engine publishes both.
POWER_PLAN_TCL ?= $(LEGACY_ASIC_DIR)/scripts/power_plan.tcl

# The live mmmc. Consumed unchanged - including its
# `-sdc_files [list ../outputs/nanosoc_eth_chiplet_pads_syn.sdc]`, which is
# relative to the tool's working directory and therefore resolves to
# $(BUILD_DIR)/$(RUN_TAG)/outputs under the toolkit, exactly as it resolves to
# ../genus-innovus/outputs under the production flow. Checked, not assumed.
#
# CAVEAT, and it is the one thing this file's structure cannot express: that
# relative path follows RUN_TAG, not SYN_RUN_TAG. `make place SYN_RUN_TAG=other`
# would read the netlist from `other` and the SDC from this run. The engine's
# own place-stage check (2_place.tcl:382) warns when the two directories differ,
# so the state is announced rather than silent - but do not use SYN_RUN_TAG with
# this mmmc without reading that warning.
MMMC_FILE ?= $(LEGACY_ASIC_DIR)/scripts/$(BLOCK).mmmc

# The 82-pad IO placement map.
IO_FILE  ?= $(LEGACY_ASIC_DIR)/scripts/$(BLOCK).io

# THIS DESIGN HAS A PAD RING, SO SAY SO. With PAD_RING at its default of 0 the
# engine treats IO_FILE as optional and `make check` does not assert it - which
# is how the toolkit's worked example ships: a padded design declared as though
# it had no pads. The floorplan then fails at read_io_file, hours in.
PAD_RING ?= 1

# ── THE ONE THAT SILENTLY SCRAPS A DIE ──────────────────────────────────────
#
# READ THIS BEFORE CHANGING IT.
#
# POWER_INTENT is the ONLY variable the engine reads power intent from
# (mk/flow.mk:319 exports it as ASIC_POWER_INTENT; flow/genus/1_synthesis.tcl:135
# is the only reader). The toolkit's worked example DOES NOT SET IT. Its
# config/design_config.tcl instead sets `upf_file` / `cpf_file` /
# `cpf_patch_required`, which are this project's scripts/config.tcl spellings
# carried over unconverted and have ZERO readers anywhere in flow/, mk/ or tech/.
#
# What that costs, in order: synthesis skips section 7 and writes NO CPF; place
# skips read_power_intent and commit_power_intent; no power domains exist;
# add_fillers inserts nothing; the die streams with no filler, no base-layer
# density fill and no antenna diodes. Nothing fails. A GDS appears and it is
# scrap. This project has already shipped that stream once - 95,568 free-site
# gaps, ~5.9% of the core - see docs/tapeout/06-fill-antenna-bondpads.md.
#
# The real file is in ../genus-innovus/inputs. There is no ASIC/power/ directory
# in this repository; the example points at one.
# Source: ../genus-innovus/inputs/nanosoc_eth_chiplet_pads.upf
POWER_INTENT ?= $(LEGACY_ASIC_DIR)/inputs/$(BLOCK).upf

# The bond-pad ring - 42 PAD70GU outer + 40 PAD70NU inner, created from the
# route stage on M8/M9/AP. Consumed unchanged; see `overrides/filler.tcl` for
# the ordering collision this creates and how it is resolved.
BONDPADS_TCL ?= $(LEGACY_ASIC_DIR)/scripts/place_bondpads.tcl

HOOKS_DIR     ?= $(ETH_CHIPLET_ASIC_DIR)/hooks
OVERRIDES_DIR ?= $(ETH_CHIPLET_ASIC_DIR)/overrides

# No scan chain is bonded on this tapeout. TEST and SE are strapped and excluded
# by set_case_analysis in the live constraints, which is the right instrument -
# turning DFT off does not stop the timer walking the scan mux inside every SDF*
# flop. Source: ../genus-innovus/scripts/config.tcl:166  `set DFT 0`
DFT_SETUP_TCL ?=


# ── 5. CONSTRAINTS ──────────────────────────────────────────────────────────
#
# EXPLICIT AND SINGLE-ENTRY, and both parts of that matter.
#
# This design's constraints are ONE file that `source`s four interface SDCs from
# its middle (constraints.sdc:110-116), between the clock definitions above and
# the asynchronous clock groups below - which must come after, because
# get_clocks cannot name a clock that does not exist yet.
#
# So the sorted glob the toolkit prefers is WRONG here, twice over: it would
# read all five files, and it would read the four interface files a second time,
# in alphabetical order, before the clock groups. `read_sdc` on an already-read
# constraint is not idempotent. The explicit single-entry list is the only
# correct answer for this file layout.
SDC_FILES := $(LEGACY_ASIC_DIR)/inputs/constraints.sdc

# The directory the STALENESS gate watches. `make sdc-check` and the toolkit's
# place stage compare mtimes here against $(BLOCK)_syn.sdc, so pointing it at
# the live inputs directory is what makes all five files watched, not just the
# one named above.
#
# THE TRAP THIS GUARDS, and it is the most expensive cheap mistake in this flow:
# place-and-route does NOT read these files. The mmmc names $(BLOCK)_syn.sdc -
# the file SYNTHESIS wrote. Edit a constraint, re-run place, and nothing changes.
# On 2026-08-07 four of these files were edited against a _syn.sdc from 08-05 and
# nothing said so.
SDC_DIR ?= $(LEGACY_ASIC_DIR)/inputs


# ── 6. ENVIRONMENT ──────────────────────────────────────────────────────────
#
# Section 0b already exported the whole project environment from ../common.mk.
# What is left is what the TECH PACK asks for and the project answers.

# The vendor IO driver LEF declares three pad-cell supply pins as plain signal
# pins - `PIN VDDPST / DIRECTION INOUT ;` with no `USE POWER ;` - so
# `connect_global_net -type pg_pin` cannot match them, the VDDIO/VSSIO special
# nets stay EMPTY, and the router threads the IO supplies around the periphery
# as ordinary signal nets into the bond-pad M8/M9 blockages. 76 DRC records on
# the 2026-08 reference run, every one a "Regular Wire", against zero for the
# core supplies. Correcting -pin_base_name alone is NOT sufficient - verified,
# not assumed. The LEF has to classify the pin as power.
#
# The tech pack asks for the patched copy through THIS variable and reads the
# vendor file when it is unset, which is the honest default. The PDK under
# /tsmc65pdk is a shared read-only mount and is never modified.
#
# THE PATCHED FILE IS GENERATED, NOT COMMITTED. It used to be a committed 414 kB
# copy of the vendor LEF under tech_wrappers/tsmc65/local_overrides/; this
# repository is PUBLIC and TSMC's licence does not permit reproducing their
# collateral, so the repo now carries the TRANSFORM (three lines of intent plus
# the code to apply them) and the vendor bytes are read from the PDK at build
# time. PAD_LEF comes from ../common.mk, which also defines the `pad-lef` target
# that produces it; `syn` below depends on it. Never check the output in.
# Source: ../genus-innovus/scripts/config.tcl:187  `set IO_PAD_DRIVER_LEF`
export TSMC65_IO_DRIVER_LEF ?= $(PAD_LEF)

# CLK_PERIOD comes from ../common.mk:174 (10.0 ns). Not restated here - one
# definition, and a sweep is `make syn CLK_PERIOD=8.0` either way.

# ── ANALYSIS VIEW NAMES: DELIBERATELY NOT SET ───────────────────────────────
#
# The engine defaults CTS_SETUP_VIEW / CTS_HOLD_VIEW / ROUTE_VIEWS_SETUP /
# ROUTE_VIEWS_HOLD to `default_analysis_view_setup` and
# `default_analysis_view_hold`, and this design's mmmc names its views EXACTLY
# THAT (scripts/$(BLOCK).mmmc:237-238). So the correct action is to set nothing.
#
# The toolkit's worked example overrides all four to `view_setup` / `view_hold` /
# `view_typ`. No such view exists in this mmmc, and flow/innovus/3_cts.tcl:518
# asserts the named views are present - so the example's design.mk aborts CTS on
# this design, after placement has already been paid for. Do not copy those four
# lines back in.
#
# The mmmc DOES additionally define `typical_analysis_view`. Setting
# ROUTE_VIEWS_TYPICAL to it enables an extra typical-corner reporting pass in the
# route stage; left unset (the engine default) that pass is skipped. It is a
# reporting difference, not a timing one, and it is left at the default until an
# equivalence run says otherwise.


# ── 7. RESOURCES ────────────────────────────────────────────────────────────
#
# 14 of srv03335's 16 physical cores (4 sockets x 4, no SMT). Licences are not
# the constraint here: Innovus_CPU_Opt has 41 issued and typically 0 in use.
# Check your own site before copying the number.
#
# Distribution stays OFF. Measured srv03335<->srv04936 is ~25 MB/s, ~37x slower
# than local disk, so slaves spend longer fetching the design than they save.
# Source: ../genus-innovus/scripts/config.tcl:239-250
INNOVUS_LOCAL_CPU      ?= 14
INNOVUS_DISTRIBUTED    ?= 0
INNOVUS_REMOTE_HOSTS   ?=
INNOVUS_CPU_PER_REMOTE ?= 6


# ── 8. WHAT MUST BE IN THE FINISHED STREAM ──────────────────────────────────
#
# `make gds-census` reads the GDS itself. Every cell listed here is placed by an
# operation whose failure mode is SILENCE - a skipped hook, an unset variable, a
# command whose argument shape was wrong. The log says nothing and the exit
# status is 0; the cells are simply absent, and a wire-bond die with no bond pads
# is scrap.
#
#   42 PAD70GU outer + 40 PAD70NU inner = 82 staggered bond pads
#      docs/tapeout/03-floorplan.md:72-73, docs/tapeout/06-fill-antenna-bondpads.md:326
#   4 PCORNER_G, one per die corner
#      docs/tapeout/21-physical-audit.md:542
#
# DCAP4 ENDCAPS ARE DELIBERATELY NOT GATED, and this is where this manifest
# departs from the toolkit's worked example. The example asserts DCAP4=4446. That
# count is real (2223 pre + 2223 post, the 08-06 run) but it MOVED: the 08-05 run
# inserted 2246+2246=4492, a 23-row-end difference from an honest floorplan change
# (docs/tapeout/21-physical-audit.md:413-443). An exact expectation on a number
# that tracks row geometry fails on every legitimate edit, which trains people to
# ignore the gate. Endcaps appear in the census output; watch them there.
#
# Antenna diodes are excluded for the same reason - 41,176 -> 38,290 between two
# runs of the same design.
GDS_EXPECT ?= PAD70GU=42 PAD70NU=40 PCORNER_G=4


# ── 9. SIGNOFF DECLARATIONS ─────────────────────────────────────────────────
#
# The implementation flow above is what this manifest is for. DRC and LVS have
# working, proven project-side flows already - `make -C ASIC/genus-innovus drc`
# and `... lvs` - and those remain the path to a signoff number. What follows
# tells the toolkit's census the design facts it cannot invent, so that a
# toolkit-side census cannot silently flatter a result.
#
# Every one of these defaults to the CONSERVATIVE answer in the toolkit, so an
# omission is pessimistic, never flattering.

# The die box the census clips against is DERIVED from the floorplan, and
# FLOORPLAN_TCL above is already the live file that carries `create_floorplan
# -site core -die_size 1600 2000` - so mk/drc.mk reads 1600 x 2000 with no
# second copy to drift. Stated here only to record where it comes from:
#   ../genus-innovus/scripts/floorplan.tcl:104
#   ../genus-innovus/drc_project.mk:92-114 does the identical derivation

# [PDK] The foundry deck. Its path encodes the METAL STACK and is not
# interchangeable with the stream's map -- so both are now derived from the one
# installed tech LEF by pdk_paths.sh rather than from two hand-kept literals,
# and the deck revision is no longer spelled in a public file.
# Source: ../common.mk (PDK_DRC_DECK), ../genus-innovus/drc_project.mk
DRC_FOUNDRY_DECK ?= $(PDK_DRC_DECK)

# The IO row depth, from the IO cell LEF SIZE. Every PDDW*_G / PVDD2*_G /
# PCORNER_G in tphn65lpgv2od3_sl is 135 um tall.
# Source: docs/tapeout/03-floorplan.md:17, and scripts/ci/drc_census.py:307
DRC_PAD_INSET ?= 135

# The bond pads reach further inboard than the drivers do, and only on the top
# metals. PAD70NU is 171 um deep with OBS solid over its whole footprint on M8
# and M9. Source: docs/tapeout/03-floorplan.md:73,88-93
DRC_DEEP_PAD_INSET  ?= 171
DRC_DEEP_PAD_LAYERS ?= M8. M9.

# Cell-name prefixes -> owner bucket, so a vendor-macro or pad-abstract result is
# reported rather than gated. Taken verbatim from this project's own census, so
# the toolkit's census and scripts/ci/drc_census.py cannot disagree.
# Source: scripts/ci/drc_census.py:63-64
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

# ── WHY DRC_DECK IS DELIBERATELY EMPTY ──────────────────────────────────────
# [2026-08-17] This is what reconciles the toolkit's drc-project recipe with
# this project's run_drc.sh. The recipe passes exactly five things -- DRC_GDS,
# DRC_RUNDIR, DRC_CPUS, DRC_DECK, BLOCK -- and run_drc.sh branches on DRC_DECK:
#
#   DRC_DECK non-empty -> run THAT deck verbatim  (the wrapper/A-B path)
#   DRC_DECK empty     -> ASSEMBLE the project deck via make_project_deck.sh
#                         (derived header + verbatim foundry body: the SIGNOFF
#                         path, and the only form that can clear
#                         WLCSP_SEALRING and set the real xLB/yLB/xRT/yRT)
#
# mk/flow.mk defaults DRC_DECK to $(ASIC_DIR)/calibre/$(BLOCK).drc.rules, which
# on THIS project does not exist -- there is no ASIC/eth-chiplet/calibre/ at
# all, the decks live beside their assembler in ../genus-innovus/scripts/calibre.
# The result was `make drc` dying with "DRC_DECK unreadable" before Calibre ever
# started. Emptying it here selects the assembling branch instead.
#
# `:=` AND IT MUST BE ABOVE THE include BELOW. flow.mk uses `?=`, which tests
# whether a variable is DEFINED, not whether it is non-empty -- so an empty
# definition made first wins, and one made afterwards would be silently
# discarded. Setting it to a real deck path (command line or here) still gets
# the verbatim path, unchanged.
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
# [2026-08-17] The other half of the DRC_DECK note above. Having selected the
# assembling branch, run_drc.sh execs make_project_deck.sh, which takes BLOCK,
# DIE_XLB/YLB/XRT/YRT and FOUNDRY_DECK from the ENVIRONMENT and has no default
# for any of them on purpose (a default would be a second, uncross-checked copy
# of the design's identity). The toolkit's drc-project recipe passes BLOCK and
# nothing else, so the remaining five are exported here.
#
# These are RENAMES, not new facts: every value is the toolkit's own, computed
# in mk/drc.mk. DIE_* come from $(DRC_DIE_*), which mk/drc.mk derives by
# reading `create_floorplan ... -die_size` straight out of $(FLOORPLAN_TCL) --
# identical derivation, identical source file, as ../genus-innovus/drc_project.mk.
# So the die box the deck checks still cannot drift from the die P&R built.
#
# BELOW THE include, AND THAT IS LOAD-BEARING: mk/drc.mk is included by
# mk/flow.mk LAST, so DRC_DIE_* and DRC_FOUNDRY_DECK do not exist until the line
# above has run. `export NAME = value` is recursively expanded and evaluated
# when a recipe runs, so this places no ordering demand of its own.
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
# `=`, NOT `:=` AND NOT `?=`, and both halves of that matter:
#   * `?=` would be a no-op. ../common.mk is included above and reaches
#     ../rom_build.mk, which has already defaulted ROM_RUN_DIR to the shared
#     drop. A conditional assignment here would never fire and every run would
#     quietly keep using ASIC/romlibs.
#   * `:=` would expand RUN_DIR NOW, and RUN_DIR does not exist yet: the
#     toolkit's mk/flow.mk defines it, and Makefile includes this file FIRST.
#     ROM_RUN_DIR would become the literal "/romlibs".
# Deferred expansion resolves it when a recipe runs, by which time flow.mk has
# set RUN_DIR. A command-line ROM_RUN_DIR= still wins over both.
ROM_RUN_DIR         = $(RUN_DIR)/romlibs

# Exported because config/design_config.tcl reads it to locate this run's ROMs;
# see the ROMLIBS_DIR block there. That one export is what makes synthesis, P&R
# and stream-out open one build rather than three reads of a shared directory.
export ROMLIBS_DIR  = $(ROM_RUN_DIR)

.PHONY: legacy-paths asic-flist romlibs-check rom-ensure cpf-patch

# ── WHERE THE `.NOTPARALLEL` WENT (removed 2026-08-17) ──────────────────────
#
# There was a bare `.NOTPARALLEL:` here, and it was correct when it was written.
# The toolkit's `all` was `all: syn place cts route` -- four prerequisites and NO
# ordering between them. Serial make happens to run a prerequisite list left to
# right, so it looked right until somebody passed -j; under `make -j all` make
# was free to start `place` while `syn` was still elaborating, and `place`
# depends on `cpf-patch` below, which reads a CPF that `syn` has not written yet.
# A bare `.NOTPARALLEL` was the only fix available: the SCOPED form that names
# its targets is GNU Make 4.4, and the sites this flow runs on are 4.2.1, where
# the directive takes no arguments and serialises THE ENTIRE MAKEFILE.
#
# STAGE ORDERING IS NOW THE TOOLKIT'S JOB, AND IT IS STRUCTURAL RATHER THAN
# DECLARED. `all` in ../asic-toolkit/mk/flow.mk is no longer a prerequisite list
# at all; it is a RECIPE of four sequential sub-makes:
#
#     all:
#             @$(MAKE) syn
#             @$(MAKE) place
#             @$(MAKE) cts
#             @$(MAKE) route
#
# Recipe lines run in sequence by definition, in every make, at every -j -- so
# the ordering no longer depends on a directive this project has to remember to
# set, and every unrelated target here keeps its parallelism. See the commentary
# above that target (flow.mk, `## THE ORDER IS IN THE RECIPE`) for the full
# argument. The resume model is unaffected: `make cts IN_RUN_TAG=...` still runs
# cts alone, because no stage was ever a prerequisite of another.
#
# WHAT THE BARE DIRECTIVE WAS ALSO COVERING, INCIDENTALLY. Serialising the whole
# makefile also serialised the prerequisites WITHIN one stage, and `syn` carries
# two that overlap: `rom-ensure` and `romlibs-check` (both below) can each reach
# `rom-run`, writing the same $(ROM_RUN_DIR) and the same .rom_pin.json. They are
# unordered siblings, so on a COLD run -- no staged ROMs -- `make -j syn` can
# start both. Ordered, they are merely redundant; concurrent, they are a
# write-write race. `make all` is ordered by construction, so this was written up
# as a hazard for whoever first adds -j rather than a live defect.
#
# THE BARRIER IS NOW APPLIED (see `romlibs-check: | rom-ensure` beside the stage
# prerequisites below) rather than left as a note, for two reasons. It costs
# exactly nothing serially -- an order-only prerequisite adds no work and no
# rebuild -- so there is no trade to weigh. And the condition the note deferred
# to has effectively arrived: removing the bare directive is what makes `-j`
# usable here at all, so the gap between "not a live defect" and "a live defect"
# is now one person typing -j on a cold tree.
#
# What that race would cost is the reason it is not being left to that person:
# the contended file is mask-programmed ROM content, and this project has already
# taped out random data into one ROM once (docs, and scripts/ci/rom_gds_bits.py,
# which exists because of it). A corrupted .rom_pin.json is not a failed build --
# it is a build that succeeds carrying the wrong bits into a reticle.

# ── THE LEGACY-PATH BRIDGE ──────────────────────────────────────────────────
#
# THE PROBLEM, stated exactly. Three of the live files this manifest points at
# name a sibling directory by a path RELATIVE to the tool's working directory:
#
#   scripts/floorplan.tcl:109       read_io_file ../scripts/$(BLOCK).io
#   scripts/place_bondpads.tcl:29   source ../scripts/filler.tcl
#   inputs/constraints.sdc:110-116  source ../inputs/{qspi,tidelink,ethernet,i2c}_constraints.sdc
#
# Under the production flow the tool runs in ../genus-innovus/work, so `../` is
# ../genus-innovus and all seven resolve. Under the toolkit the tool runs in
# $(BUILD_DIR)/$(RUN_TAG)/work, so `../` is the run directory and none of them do.
#
# THE CHOICE. Copying the four files here and editing seven lines is what the
# toolkit's worked example did, and it is why every example file has since
# drifted 169-540 lines from the file it was copied from. Rewriting the live
# files to absolute paths would edit the Tcl a running production flow depends
# on, to fix a problem that only exists in the new flow.
#
# So neither. Two symlinks in the run directory make `../scripts` and `../inputs`
# mean what they mean in production, and the live files are consumed BYTE FOR
# BYTE with no edit anywhere. The links live under BUILD_DIR, which is disposable
# output - the toolkit's rule 4 (never write into the source tree) is kept.
#
# `rm -rf` DOES NOT FOLLOW SYMLINKS, so `make clean` / `make distclean` remove
# the links and never the live directories. Verified on this filesystem, not
# assumed - it is the one property that makes this safe.
#
# THIS IS A BRIDGE, NOT AN ARCHITECTURE. It exists so the two flows can be
# compared while they are both alive. The end state is `$IO_FILE` in the
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
## Source: ../genus-innovus/Makefile:64-65
asic-flist:
	$(MAKE) -C $(NANOSOC_ETH_CHIPLET_HOME) --no-print-directory asic-flist

## ── THE BOOT ROMs, BUILT FOR THIS RUN ──────────────────────────────────────
## Genus reads the two ROM .libs through the library search path; without them
## `syn` dies inside set_db with "Cannot open file rom_via_*.lib", ten minutes in.
##
## THIS IS NOW A BUILD, NOT ONLY A CHECK. The comment here used to say the ROMs
## "cannot be rebuilt on this host - the Arm compiler has listed zero generators
## since the RHEL 8.10 upgrade". That was never true of the compiler: the check
## that reported it read the generator names off the wrong line of the
## compiler's own help output. Corrected in ../common.mk on 2026-08-14; the
## install lists fifteen generators and compiles each ROM in under three
## minutes.
##
## So `rom-run` compiles both macros into THIS run's directory
## ($(ROM_RUN_DIR) = $(RUN_DIR)/romlibs) from a content-addressed cache, pins
## the run to that build, and then runs the full word-for-word gate against
## what it just built. The macros are mask programmed and the shared drop this
## target used to verify had already shipped the wrong bits twice.
##
## ROM_RUN_DIR goes on the SUB-MAKE COMMAND LINE: ../common.mk assigns
## ROMLIBS_DIR with `:=`, and a makefile assignment beats an exported
## environment variable, so an export alone would have the sub-make build and
## verify the shared drop while the tools read the run.
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
# Genus cannot translate this design's UPF supply commands to CPF - the synthesis
# log fills with "Unable to translate command 'create_supply_net' ... from 1801
# to CPF format" - so the CPF it writes contains only
#     create_power_domain -name PD_TOP -default
# with no power net and no ground net. Innovus then fails EVERY filler pass with
# IMPSP-5110, `add_fillers` reports "For 0 new insts", and the flow completes and
# streams a GDS. The repair is not an Innovus command: `update_power_domain` in
# this build has no -primary_power_net option at all. These are CPF STATEMENTS,
# so the repair belongs in the CPF text before Innovus reads it.
#
# WHERE IT BELONGS IN THE TOOLKIT'S HOOK MODEL: NOWHERE. That is a measured
# answer, not a shrug. The engine has ten hook points and the CPF is written
# between two of them:
#
#   flow/genus/1_synthesis.tcl:825   flow_hook post_synth      <- too EARLY
#   flow/genus/1_synthesis.tcl:944   write_power_intent -cpf   <- the CPF appears
#   (synthesis ends; no further hook)
#   flow/innovus/2_place.tcl:320     the CPF input contract    <- reads it
#   flow/innovus/2_place.tcl:519/544 read_power_intent -cpf    <- reads it
#   flow/innovus/2_place.tcl:720     flow_hook pre_floorplan   <- too LATE
#
# There is no hook after the CPF is written and before it is read, in either
# stage. So the patch is wired at the MAKE layer, which is the only layer that
# sits between the two tools - `place: cpf-patch` below. That is not a
# workaround; it is where the production flow puts it too
# (../genus-innovus/Makefile:254).
#
# TWO THINGS THE TOOLKIT ALREADY DOES BETTER, and they are worth knowing:
# flow/innovus/2_place.tcl:329-337 tests the CPF TEXT for create_power_nets /
# create_ground_nets and DIES if they are absent, and power_plan.tcl (the live
# file, which this manifest points at) asserts the same three statements. So an
# unpatched CPF is now a loud stop in two independent places rather than a
# silent scrap die. This target is what stops it happening at all.
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
# and make simply merges the lists. This is the whole of the consumer wiring.
#
#   every stage    the legacy-path bridge, and the patched IO-driver LEF -- both
#                  before any tool opens a file. pad-lef (../common.mk) derives
#                  that LEF from the read-only PDK; it is a build product, not a
#                  committed file, so it must exist before the tech pack reads
#                  TSMC65_IO_DRIVER_LEF. Idempotent and licence-free, so hanging
#                  it off every stage costs nothing.
#   syn            the generated sub-flists and the ROM libraries, the two
#                  project-side gates the toolkit's worked example only assumes
#   place          the CPF patch, between the two tools
syn place cts route: legacy-paths pad-lef rom-ensure
syn:   asic-flist romlibs-check
place: cpf-patch

# The order-only barrier argued for above. `|` makes rom-ensure a prerequisite
# for ORDERING only: romlibs-check is not rebuilt when rom-ensure runs, so this
# adds no work on any path, serial or parallel. It exists solely so that the two
# routes to `rom-run` cannot both open $(ROM_RUN_DIR) under `make -j syn`.
romlibs-check: | rom-ensure

# ── CTS derate ──────────────────────────────────────────────────────────────
# The toolkit defaults CTS_DERATE to 0 and warns when it is off. The production
# flow applies all four derate arms UNCONDITIONALLY
# (../genus-innovus/scripts/cts_setup.tcl), and the values the toolkit would use
# are identical -- the pack supplies the same four numbers. So this is the
# difference between a signoff run and an optimistic one, not a tuning choice:
# removing derate improves the report, not the silicon.
#
# Innovus inherits the last defined value for any arm left unspecified, so a
# partial set silently mis-derates the rest. The toolkit sets all four together.
export CTS_DERATE ?= 1

# EXPORT IS LOAD-BEARING ON EVERY LINE ABOVE. The stage scripts read their knobs
# with `opt`, which resolves from ::env(...) -- so a bare `CTS_DERATE = 1` in
# this file is a make variable the tool never sees, and the knob silently keeps
# its default. Measured the hard way: a 47-minute CTS run took the toolkit's
# empty allowlist and its derate-off default despite both being set here,
# because neither was exported. That is precisely the failure this flow says it
# exists to stamp out -- a setting that did nothing and said nothing.

# ── Diagnosed message IDs ───────────────────────────────────────────────────
# The toolkit ships an EMPTY allowlist for every stage, deliberately: a default
# that tolerates IDs would hand each new project someone else's undiagnosed
# exemptions. So the exemptions belong HERE, per design, each with the diagnosis
# that earned it. Both of these are carried by the production flow for this same
# design (../genus-innovus/scripts/4b_pnr_route_eval.tcl:210-218).
#
#   IMPLF-223     Duplicate LEF via definitions across the LEF list; Innovus
#                 ignores the later ones. 60 in the 2026-08-06 log, 20 shown in
#                 2026-08-07 (message-capped). Recorded as benign in
#                 docs/tapeout/16-open-defects.md.
#   IMPMSMV-3501  The power intent defines no power_mode/power_state, so
#                 always-on buffering is unsupported. Accepted for this tapeout:
#                 the chip has ONE core power domain (docs/tapeout/
#                 11-known-issues.md (d)). It is not a defect to fix here, it is
#                 a consequence of a single-domain design.
#   TCLCMD-917    Added 2026-08-14. 71 instances, one class, all of the form
#                 "Cannot find 'pins' that match 'uPAD_VDDIO_B_0/VDDPST'" from
#                 _syn.sdc:789 -- a set_multicycle_path (-setup -end 2) applied
#                 to pad SUPPLY pins (VDDPST / VSS). A supply pin is not a timing
#                 pin, so the exception has no object to attach to and can never
#                 apply; timing is unaffected either way. Recorded benign in
#                 docs/tapeout/16-open-defects.md item 5. It stopped the
#                 2026-08-14 full run at the post-place message census, after
#                 placement itself had already succeeded.
#
#                 THIS ONE IS TRACKED DEBT, NOT A PERMANENT STATE. The exemption
#                 tolerates a symptom; the defect is upstream, in whichever input
#                 constraint emits timing exceptions against supply pins. Fixing
#                 it there removes all 71 rather than excusing them, and reclaims
#                 the message budget doc 16 item 5 notes these consume -- the
#                 budget that would otherwise report a genuine failure. Remove
#                 this line when the constraints stop naming supply pins.
#
#                 REMOVED 2026-08-17, on that condition being met. The upstream
#                 fix landed in f8df605: the pad multicycle now names the five
#                 signal pins explicitly -- {I C PAD OEN REN} -- instead of the
#                 uPAD*/* wildcard that swept up supply pins. Measured from SDC
#                 written by a restored session either side of the swap:
#
#                     expansion    548 -> 480 entries, PG entries 68 -> 0
#                     TCLCMD-917   21 -> 0
#                     setup/hold   UNCHANGED  (setup 0.008 = 0.008,
#                                  hold -0.462 = -0.462, all seven path
#                                  groups identical)
#
#                 The third line was the PRE-REGISTERED falsification condition:
#                 a supply pin carries no timing arc, so if timing had moved at
#                 all the premise was wrong and the fix came back out. It did not
#                 move. The pin list is exhaustive rather than a guess -- all
#                 nine instantiated pad masters were enumerated, the four signal
#                 masters expose exactly {C,I,OEN,PAD,REN} and all five supply
#                 masters exactly one PG pin. An attribute filter was ruled out
#                 at the tool, not inferred: Genus answers `'is_power' is not a
#                 recognized attribute for object 'pin' [TUI-183]`.
#
#                 DO NOT RE-ADD IT. The cause is gone, so a recurrence would be
#                 TCLCMD-917 arriving from a DIFFERENT constraint, and that is a
#                 finding rather than noise. Re-adding the ID would re-hide the
#                 whole class to excuse a symptom nothing is producing.
#
# The two that remain are neither a licence nor an environment artefact -- both
# are properties of this design's collateral, and both would recur on every run
# forever. Anything NOT on this list still fails the stage, which is the point.
export PLACE_ERROR_ALLOWLIST ?= IMPLF-223 IMPMSMV-3501
# CTS adds six more, and every one is a state this design chose:
#   CHKCTS-18/19/20  buffer / inverter / clock-gating cells "not specified".
#                    PERMANENT and INTENDED: config/design_config.tcl withdraws
#                    the tech pack's CKB*/CKN*/CKLHQ* patterns so CCOpt picks
#                    its own cells, matching the production flow. The shipped
#                    tree uses 3,290 BUFFD1, which a CKB* list excludes. The
#                    tool is correctly reporting a deliberate choice.
#   CHKCTS-1/-2      no CTS max-transition target, 42 = trees x corners.
#   CHKCTS-9         no clock route_type, same 42.
#                    Both are documented gaps with knobs that close them
#                    (CTS_TARGET_TRAN, CTS_ROUTE_TYPE). TRACKED DEBT, not
#                    permanent -- remove them from this list when the knobs are
#                    set, and expect the tree to change when they are.
#
# NOT allowlisted, deliberately: IMPSP-2021 "could not legalize 1 instance".
# That is a real placement failure -- a CKBD16 clock buffer at (649.8, 1792.6),
# 2.4 um below the core's top edge, with no legal site within 230 um. The
# production flow does not report it. A defect, not a configuration state, and
# adding it here would bury it.
export CTS_ERROR_ALLOWLIST   ?= IMPLF-223 IMPMSMV-3501 \
                                CHKCTS-18 CHKCTS-19 CHKCTS-20 \
                                CHKCTS-1 CHKCTS-2 CHKCTS-9
export ROUTE_ERROR_ALLOWLIST ?= IMPLF-223 IMPMSMV-3501


# ── 11. THE COUNTS THIS DIE IS, AND THE RATCHETS THAT HOLD THEM ─────────────
#
# Everything below is DESIGN DATA, not toolkit policy: a pin map's pad counts and
# a power plan's measured geometry. The toolkit defaults every one of these to
# "do not gate", and that default is why the numbers below were never checked.
#
# ── 11a. THE PAD RING ───────────────────────────────────────────────────────
#
# READ THIS BEFORE CHANGING A NUMBER HERE.
#
# `read_io_file` handed an IO file naming instances the netlist does not contain
# DOES NOT FAIL. It emits `**WARN: (IMPFP-53): Failed to find instance
# 'uPAD_VDDIO_T_0'` once per instance, places the rest, and returns. On this
# design that was 34 warnings - EVERY SUPPLY PAD ON THE DIE - and the resulting
# database went through place, CTS, route and stream with every gate green, three
# builds running. The counts are still in the logs:
#
#     build/default/work/innovus.log        34 x IMPFP-53
#     build/m5off5, build/m5off6            34 x IMPFP-53
#     build/full-20260814                    0
#
# and the run with the pads got a WORSE score than the runs without them, because
# the only gate that could see the difference - unrouted PG nets - was an upper
# bound and losing the pads made the count go DOWN (2 with pads, 0 without).
#
# Counted from scripts/nanosoc_eth_chiplet_pads.io, which is the file
# read_io_file reads: 12 VDDIO, 12 VSSIO, 6 VDD, 4 VSS = 34 supply pads, in a
# ring of 86 instances (82 IO + 4 corners).
export PLACE_EXPECT_PADS      ?= VDDIO=12 VSSIO=12 VDD=6 VSS=4
export PLACE_EXPECT_PAD_INSTS ?= 86

# MIND THE SEPARATOR - measured, not theorised. Against this design's 86 pad
# names:
#     uPAD_%RAIL%_*   VDD -> 6    VSS -> 4     correct
#     uPAD_%RAIL%*    VDD -> 18   VSS -> 16    VDDIO and VSSIO swallowed
# The second spelling double-counts, agrees with the expected TOTAL, and
# describes a different set of pads. The engine now refuses a pattern whose rails
# overlap rather than trusting either. Left at the toolkit default deliberately -
# this line is here to name the trap, not to change the value.
# export PLACE_PAD_PATTERN ?= uPAD_%RAIL%_*

# ── 11b. THE PG RATCHETS, FROM MEASURED VALUES ──────────────────────────────
#
# BOTH OF THESE DEFAULT TO -1 IN THE TOOLKIT, WHICH MEANS DO NOT GATE, and both
# have defaulted to -1 for the whole life of this project. They are ratchets and
# nobody ratcheted them.
#
# THE MEASUREMENT SET IS PAD-CORRECT RUNS ONLY. Five other runs in build/ report
# these same quantities and are excluded, because three of them are the 34-x-
# IMPFP-53 runs above - a die with no supply pads has a different power grid, and
# pooling its geometry with a correct one is the mistake the new provenance block
# exists to stop - and one (build/macro-move) aborted before its power plan.
#
#   rv_vias_to_AP   7 on all ten pad-correct runs: the eight
#                   runs/20260814T072716Z_lef-patch-replacement arms, the
#                   20260811T121335Z fill-verify run, and build/full-20260814.
#                   FLOOR 6, one below the measured value. The failure mode of
#                   this number is collapse toward zero (this project's own
#                   record is 14 -> 9 -> 7 across power-plan configurations), so
#                   a floor AT 7 would fire on a legal one-via change while a
#                   floor of 6 still fires on any real loss. There is no IR-drop
#                   analysis in this flow; this count is the only thing standing
#                   in for one.
#   m5_fragments    3399 on the nine 08-14 pad-correct runs, 3376 on 08-11.
#                   Max 3399, spread 23 (0.68%). CEILING 3570 = +5%, which is
#                   seven times the spread between two pad-correct runs and twice
#                   the spread across every run in the archive including the
#                   pad-less ones (3362..3450, 2.6%). The documented failure -
#                   the grid coming apart - is a third more fragments, so it is
#                   caught with a factor of six in hand.
#
# WHAT THESE DO NOT SAY. A ratchet set from today's number can report a
# REGRESSION and nothing else. It does not say 3399 fragments is an acceptable
# number: it is roughly 2.3x the ceiling this grid was suggested to have, and the
# structural cure named in power_plan.tcl - one M5 ladder over the whole core
# instead of one per row region - is still not done. Do not read a green here as
# a verdict on the grid.
export PLACE_MIN_PG_VIAS  ?= 6
export PLACE_MAX_PG_FRAGS ?= 3570

# ── 11c. NETS WITH NO ROUTING AT ALL ────────────────────────────────────────
#
# MEASURED 2 on the pad-correct runs (build/full-20260814/reports/route_manifest
# .txt, and runs/20260808T223829Z_stage1b-route), 0 on the runs whose supply pads
# had been deleted. That inversion is the whole reason this knob is now an
# EQUALITY in the toolkit rather than a ceiling: the broken database was the
# quiet one, and a ceiling cannot see quiet.
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
# The mechanism is written down in this project's own power_plan.tcl, above the
# M5 pass:
#
#     `split_row -selected` above gives every macro its own row region, and
#     add_stripes re-anchors PER REGION. So `-start_offset 8` does not mean
#     "8um up from the core"; it means EVERY MACRO gets M5 straps buried
#     8.0-9.0 and 9.5-10.5um INSIDE ITS OWN FOOTPRINT, repeating every 15um.
#
# and its consequence is written down twenty lines further on: two macros side by
# side anchor two ladders that alias, and a 2.72 um macro move against 2.70 um of
# clearance overshot by 20 NANOMETRES and produced four VDD-VSS rail shorts. Four
# more macro pairs sit 0.41-0.45 um from the same window. Until 2026-08-17
# NOTHING IN THIS FLOW ASKED WHETHER A STRIPE WAS INSIDE A MACRO AT ALL; the
# shorts were found by check_drc, at the route stage, hours later, inside a
# budgeted total that the same floorplan change had simultaneously reduced.
#
# THREE HONEST RESPONSES, in order of preference:
#   1. the structural fix power_plan.tcl already names - one M5 ladder over the
#      whole core instead of one per row region. It closes this AND the
#      macro-blockage DRC class, and it is the only one that removes the hazard.
#   2. ratchet PLACE_MAX_MACRO_STRIPES to the measured count, WITH the count and
#      this defect named beside it. That buys a regression detector and nothing
#      more; it does not make the grid safe.
#   3. set PLACE_MACRO_PG_CHECK=0. Only with a written reason. It is the option
#      that returns this design to the state it was in when the shorts arrived.
#
# Left at the toolkit default of 0 deliberately. Naming the knob here without
# setting it is the point: `-1` and an unratcheted ceiling are how
# PLACE_MIN_PG_VIAS and PLACE_MAX_PG_FRAGS above sat inert for the life of this
# project.
# export PLACE_MAX_MACRO_STRIPES ?= <measured count>   # see 1/2/3 above
#
# The NEAR-MISS arm stays ungated until it has been measured once on this design:
# the clearances quoted above (0.41, 0.45 um) come from the aliasing arithmetic in
# power_plan.tcl, not from this census, and a floor set from a number a different
# instrument produced is not a ratchet. The census reports the value every run and
# the manifest carries it, so a CHANGE is visible meanwhile.
# export PLACE_MIN_MACRO_PG_GAP ?= <measured min, less a stated margin>

# ── 11e. MISSING POWER VIAS, OVER THE WHOLE STACK ───────────────────────────
#
# Same shape, same instruction. The toolkit now asks check_power_vias about
# routing_layer_bottom..top_metal_layer instead of the coarse stripe layer, and
# PARSES the answer - the report has been written into reports/ for months and
# read by no gate, no manifest line and no person.
#
# What the two ranges say about ONE database, four minutes apart
# (runs/20260812T144334Z_route-baseline-gds-nonstrict vs build/full-20260814):
#
#     {coarse stripe .. top}      4 missing
#     {bottom .. top-1}         556 missing - 452 of them in a single mid-stack
#                               layer pair, 357 on one rail and 199 on the other
#
# The full-stack range has never been run to the TOP layer here, so the true
# number is 556 plus whatever the last interface adds (4 in the run above). Do
# not write a budget from arithmetic on those two: run it once, then ratchet with
# the per-layer-pair split recorded beside it.
# export ROUTE_BUDGET_PG_VIAS ?= <measured count>   # with pg_via_by_pair quoted

# ── 11f. METAL DENSITY IS THE FOUNDRY'S ─────────────────────────────────────
#
# This die goes out as a mini@sic shuttle submission through eptsmc@imec.be, and
# the broker fills the frame after it merges the standard-cell and IO layouts in.
# Filling here first would hand over metal that is about to be filled again, so
# ROUTE_METAL_FILL stays 0 and that is the CORRECT setting rather than a gap.
#
# What this line changes is not what the run does, but what the run is allowed
# to conclude. Until the toolkit had METAL_FILL_OWNER, an unfilled design failed
# the density check by construction and every failing window landed in the route
# stage's HARD list. Measured on build/full-20260814: 13 hard failures, ALL of
# them density, on an obligation already contracted out - and underneath them
# eight signoff budgets that ARE ours (68 check_drc including 4 shorts, 65 PG
# opens, 886 dangling PG wires, setup FEP 1429 at WNS -0.715, hold FEP 7). The
# gate could not go green, and the 13 buried the 8.
#
# Setting the owner does NOT stop the measurement, does NOT waive anything, and
# does NOT cover a density report that could not be parsed - that stays hard
# under either owner, because "who inserts the metal" and "did anyone look" are
# different questions. The count still reaches the manifest as density_windows,
# alongside metal_fill_owner, and the verdict still lists it under DECLARED
# ELSEWHERE. The console status line reads "OK, WITH n ITEM(S) DECLARED
# ELSEWHERE" rather than OK, deliberately.
#
# THE HANDOFF IS THE THING THIS DEPENDS ON, and nothing in this flow re-checks
# it. It is in the submission correspondence; keep it there.
export METAL_FILL_OWNER ?= foundry
