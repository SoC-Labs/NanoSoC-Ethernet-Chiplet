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

# Source: ../common.mk:94  TSMC_65_HOME=/tsmc65pdk/65, and every library path in
# scripts/config.tcl. The pack owns the standard cells, the IO library, the tech
# LEF, the cap tables, the layer names and the stream-out map.
TECH  := tsmc65

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
# flop. Source: ../genus-innovus/scripts/config.tcl:136  `set DFT 0`
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

# [PDK] The foundry deck. Its path encodes the METAL STACK (9M 6X1Z1U) and is
# not interchangeable with the stream's map.
# Source: ../genus-innovus/drc_project.mk:129
DRC_FOUNDRY_DECK ?= $(TSMC_65_HOME)/CMOS/util/MAIN_DRC_TopMu/CLN65S_9M_6X1Z1U.26_2a

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
# NOTE, and it is a real gap: the toolkit's `drc-project` recipe passes only
# DRC_GDS / DRC_RUNDIR / DRC_CPUS / DRC_DECK / BLOCK, while this project's
# run_drc.sh also needs FOUNDRY_DECK and the four DIE_* values to assemble its
# spliced deck. Until that is reconciled, use `make -C ASIC/genus-innovus drc`.
DRC_SCRIPT ?= $(LEGACY_ASIC_DIR)/scripts/calibre/run_drc.sh
LVS_SCRIPT ?= $(NANOSOC_ETH_CHIPLET_HOME)/ASIC/lvs-flow/run_lvs.sh


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

.PHONY: legacy-paths asic-flist romlibs-check cpf-patch

# STAGES RUN IN ORDER, ALWAYS. `all: syn place cts route` has no ordering
# barrier, so `make -j all` is free to start place while syn is still elaborating
# - and `place` depends on `cpf-patch`, which reads a file `syn` has not written
# yet. The stages share one database and cannot be parallel anyway, so there is
# nothing to lose.
.NOTPARALLEL:

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

## Genus reads the two ROM .libs through the library search path; without them
## `syn` dies inside set_db with "Cannot open file rom_via_*.lib", ten minutes in.
## They cannot be rebuilt on this host - the Arm compiler has listed zero
## generators since the RHEL 8.10 upgrade (../common.mk explains it at length) -
## so this is a check, not a build.
## Source: ../genus-innovus/Makefile:69-76
romlibs-check:
	@$(MAKE) -C $(NANOSOC_ETH_CHIPLET_HOME)/ASIC -f common.mk --no-print-directory romlibs-verify || { \
	    echo ""; \
	    echo "The ROM libraries are not built. On a host with a working Arm mem"; \
	    echo "compiler:  make -C ASIC -f common.mk tsmc_65_romlibs"; \
	    echo "Otherwise: make -C ASIC/genus-innovus romlibs-fetch"; \
	    exit 1; }

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
syn place cts route: legacy-paths pad-lef
syn:   asic-flist romlibs-check
place: cpf-patch

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
#
# NEITHER is a licence or an environment artefact -- both are properties of this
# design's collateral, and both would recur on every run forever. Anything NOT
# on this list still fails the stage, which is the point.
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
