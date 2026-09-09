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

# The bond-pad ring - 42 PAD70GU_SL outer + 40 PAD70NU_SL inner, created from the route
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
#   42 PAD70GU_SL outer + 40 PAD70NU_SL inner = 82 staggered bond pads
#   4 PCORNER_G, one per die corner
#   docs/tapeout/03-floorplan.md, 06-fill-antenna-bondpads.md, 21-physical-audit.md
#
# DCAP4 ENDCAPS AND ANTENNA DIODES ARE DELIBERATELY NOT GATED. Both track row
# geometry and move on legitimate floorplan edits (endcaps 4492 -> 4446, diodes
# 41,176 -> 38,290 between runs of the same design). An exact expectation on a
# number that moves legitimately trains people to ignore the gate. Both appear in
# the census output; watch them there.
GDS_EXPECT ?= PAD70GU_SL=42 PAD70NU_SL=40 PCORNER_G=4

## BONDPAD_CELLS -- SET 2026-08-20. Without this, LVS cannot reach a verdict.
##
## The tpbn65v bond pads (PAD70GU_SL x42, PAD70NU_SL x40) are CLASS BLOCK, pin-less,
## and that library is FRONT-END ONLY on this site -- there is no CDL for them
## anywhere. `write_netlist` still emits the instances (`XBuPAD_HOST_IO_6
## PAD70NU_SL`), so the LVS netlist compiler hits 82 x
##     Error: No matching ".SUBCKT" statement for "PAD70NU_SL"
## and stops before the comparison. The run then ends "NO VERDICT -- report has a
## comparison section but no CORRECT/INCORRECT", which is what every LVS attempt
## on this chiplet has produced. MEASURED on gdsrun-20260819: 82 compiler errors,
## all of this one class, nothing else in the design unresolved.
##
## ASIC/lvs-flow/lvs.mk:143 already anticipates exactly this -- "Pin-less bump/pad
## cells: LEF-only, no model at all, so they need an empty .SUBCKT or the SPICE
## source will not even read" -- and defaults it EMPTY.
##
## WHY IT LOOKED SET: ASIC/genus-innovus/lvs_project.mk:212 carries
## `BONDPAD_CELLS ?= PAD70GU_SL PAD70NU_SL`, but that file is included by the LEGACY
## genus-innovus Makefile only. The toolkit's `lvs-batch` runs from
## ASIC/eth-chiplet, which never sees it:
##     make -C ASIC/genus-innovus  -> [PAD70GU_SL PAD70NU_SL]
##     make -C ASIC/eth-chiplet    -> []
## So the knob was right and unreachable. Setting it here puts it on the live path.
##
## The IO DRIVERS do not need this. CORRECTED 2026-08-20: an earlier revision of
## this comment said "tphn65lpgv2od3_sl ships a CDL". It does NOT -- there is no
## tphn65*.cdl anywhere on this site (MEASURED: 0 hits under $TSMC_65_HOME). It ships
## a VERILOG model, `Front_End/verilog/.../tphn65lpgv2od3_sl.v`, from which v2lvs
## synthesises a port-bearing stub: `.SUBCKT PDDW04DGZ_G I OEN REN PAD C`. The
## bond pads ship no Verilog either, which is the ONLY reason they alone need a
## hand-written empty .SUBCKT. Conclusion unchanged, stated reason was wrong. So
## PDDW*/PVDD*/PVSS* are boxed AND modelled. Only the bond pads are model-less.
BONDPAD_CELLS ?= PAD70GU_SL PAD70NU_SL

## LVS SUPPLY NAMES -- SET 2026-08-20, same class of bug as BONDPAD_CELLS above.
##
## ASIC/genus-innovus/lvs_project.mk carries these and is included ONLY by the
## LEGACY genus-innovus Makefile. The toolkit's `lvs-batch` runs from
## ASIC/eth-chiplet and never sees it, so the flow defaults took over:
##     legacy                          live (before this)
##     LVS_POWER       VDD VDDIO       VDD
##     LVS_GROUND      VSS VSSIO       VSS
##     LVS_GLOBAL_NETS VDD VDDIO VSSIO VDD VSS
## Confirmed in the deck that actually ran: `LVS POWER NAME VDD`, `LVS GROUND
## NAME VSS`. VDDIO and VSSIO were never declared as supplies at all.
##
## WHY `.GLOBAL VSS` IS ACTIVELY HARMFUL AND IS OMITTED BELOW. The boot ROM's
## real supplies are VDDE/VSSE; `VSS` is an INTERNAL node inside rom_via, used
## ~1040 times, and the power-gate footer sits drain-on-VSS source-on-VSSE.
## `.GLOBAL VSS` merges the two and FABRICATES A SHORT ACROSS THE POWER GATE,
## source side only. Measured consequence in the 2026-08-20 run: 390 of 396
## incorrect nets and all 62 property errors inside the two ROMs, 32 unmatched
## NPGEN* power-gate enable nets, and the matcher losing the ability to tell the
## two ROM instances apart (1,003 arbitrary matches). lvs_project.mk:187-193
## predicted this exactly, before it was measured.
##
## THE DISCLOSED COST of omitting VSS, stated so nobody rediscovers it: it leaves
## ~16.8k floating <inst>/VSS source nets, which inflates source-side Net VSS and
## MASKS the VSS half of any real PG open. The clean fix is project-local ROM CDL
## copies with the internal VSS renamed, after which VSS can go back into
## .GLOBAL -- see lvs_project.mk:197-204. Not done here; this is the cheap half.
LVS_POWER       ?= VDD VDDIO
LVS_GROUND      ?= VSS VSSIO

## VSS IS BACK IN .GLOBAL -- 2026-09-09, and it is safe ONLY because of the ROM
## CDL rename in section 9. The two land together or not at all; VSS here without
## that rename fabricates a short across both boot ROMs' power gates, source-side
## only, and is strictly worse than the omission it replaces.
##
## WHY THE OMISSION HAD TO GO. It was not merely lossy -- it INVERTED THE CHECK'S
## SIGN. Without VSS in .GLOBAL, ~18k phantom one-pin /VSS source nets appear; a
## STRANDED ground pin then matches a phantom net exactly while a CORRECTLY
## CONNECTED one mismatches. Measured on a deliberately stranded DB: the gate
## returned PASS and the affected cell vanished from the report entirely.
## Breaking a power pin made LVS look cleaner, so LVS could not detect a stranded
## PG pin at all. It also produced false positives -- Calibre pairs stray layout
## nets with arbitrary orphans ("1036 nets ... matched arbitrarily"), one of which
## flipped a gate FAIL on rc2 by binding a QSPI_SCLK pad port to a CKND1's phantom
## /VSS 800um away.
##
## SEVENTH INSTANCE OF THE UNREACHABLE-KNOB CLASS. The root fix landed 2026-08-27
## in ../genus-innovus/lvs_project.mk:261, which ONLY the legacy Makefile
## includes, so the toolkit path -- the one that builds the shipping GDS -- kept
## running the inverted check for thirteen days.
LVS_GLOBAL_NETS ?= VDD VDDIO VSS VSSIO

## THE PG-LABELLED LVS STREAM -- SET 2026-08-21. Fourth and fifth instance of the
## same unreachable-knob class as BONDPAD_CELLS and LVS_POWER above: all four are
## set in ../genus-innovus/lvs_project.mk:264-293, which ONLY the legacy
## genus-innovus Makefile includes. Measured on the live path before this:
##     make -C ASIC/eth-chiplet lvs-pg-preflight   -> PG PREFLIGHT: FAIL
##     LVS_PG 0   LVS_PG_PIN_TEXT 0   LVS_PG_MAP_IN (unset)   LVS_PG_MERGE_GDS (empty)
##
## THE FOUR ARE NOT ONE DECISION. Two were deliberate, two were missed:
##   LVS_PG / LVS_PG_PIN_TEXT   deferred on purpose, documented as "the coverage
##                              gap" in docs/plans/POST_STREAM_TEST_PROCEDURE.md
##                              7a. Turning them on here makes the covered run the
##                              DEFAULT rather than an opt-in flag; `?=` keeps the
##                              per-invocation opt-out that 7a relies on.
##   LVS_PG_MAP_IN / _MERGE_GDS never spotted (LVS owner, 2026-08-21).
##
## WHAT THE TWO ZEROS COST, quoted from lvs_project.mk:288-293 (measured
## 2026-08-10, NOT re-measured here): "boxed cells extract with ZERO pins so ~633k
## routed nets are dropped and no standard-cell routing is checked at all. With
## both on: nets reconciled 62,483 -> 268,171, arbitrary matches 1,014 -> 44."
## Independently required by IMEC app note FS_AN_017 step 2, which says a boxed
## cell needs "metal surfaces AND labels" in the layout: ours streamed the metal
## and no labels, so EP=0 on both sides and boxed leaves matched on NAME AND COUNT
## ONLY -- a cell census, not a netlist comparison.
##
## THE PASS CRITERION IS `nets reconciled`, NEVER THE VERDICT. Coverage arriving
## makes the verdict WORSE: INCORRECT(82) -> INCORRECT(thousands) is 203 unmatched
## layout and 16,848 unmatched source nets becoming VISIBLE, not a regression.
##
## VERIFY ON A ROUTED TAG. build/default stops at CTS, so its `LVS_PG_DB MISS` is
## not a config fault and no reconciliation number can be demonstrated there.
##
## THE COLON TRAP, if pin text ever lands on a multi-port pin: write_stream
## appends ':' to the label of any pin owning MULTIPLE PORTS
## (write_stream_virtual_connection defaults true), and `VDD:` matches no source
## `VDD`. lvs_pg_emit.tcl measured this library at 855 macros / 5,603 pins / ZERO
## multi-port, so LEFPIN is clear TODAY -- a regenerated LEF could change that
## silently. Assert the exact label string, never the count.
LVS_PG           ?= 1
LVS_PG_PIN_TEXT  ?= 1

## THE ROUTED DATABASE, AND WHY THE DEFAULT CANNOT FIND IT. lvs.mk:210 defaults
##     LVS_PG_DB ?= $(LVS_PG_WORK_DIR)/$(LVS_TOP)
## -- the BARE block name. That is the LEGACY genus-innovus naming, whose stages
## assert on `work/nanosoc_eth_chiplet_pads`. THIS flow names its databases
## $(BLOCK)_placed / _cts / _routed (mk/flow.mk:105, and GUI_DB at :604), so the
## bare name exists in NO run and the preflight MISSes even on a fully routed one.
## Migration residue, same class as the four knobs above: a default that was right
## for the flow it was written for and was never adapted when it moved.
##
## MEASURED 2026-08-21, and it corrects an earlier reading of mine: I first put
## the MISS down to build/default stopping at CTS. That was plausible and wrong --
## full-20260814 is fully routed, holds _routed, and MISSed identically. The
## symptom had a second cause and the first one explained it away.
LVS_PG_DB        ?= $(LVS_PG_WORK_DIR)/$(LVS_TOP)_routed

## The foundry GDS-out map -- the SAME one P&R streams with, shared as one value
## rather than two hand-kept release-coded copies. Resolved by ../common.mk.
LVS_PG_MAP_IN    ?= $(PDK_GDSMAP)

## Hard-macro layout, one-for-one with MACRO_CDLS: a macro that is NOT boxed
## compares to real transistors, so an empty frame on the layout side mis-compares
## its whole interior. $(ROMLIBS_DIR) is re-pointed at $(RUN_DIR)/romlibs below,
## so this picks up THIS RUN's ROMs, never the shared drop.
LVS_PG_MERGE_GDS ?= \
    $(MEM_BASE)/rf_32k/rf_32k.gds2 \
    $(MEM_BASE)/rf_16k/rf_16k.gds2 \
    $(MEM_BASE)/rf_08k/rf_08k.gds2 \
    $(MEM_BASE)/rf_01k/rf_01k.gds2 \
    $(MEM_BASE)/flash_cache_data/flash_cache_data.gds2 \
    $(MEM_BASE)/flash_cache_tag/flash_cache_tag.gds2 \
    $(ROMLIBS_DIR)/cc_rom/rom_via.gds2 \
    $(ROMLIBS_DIR)/eth_rom/eth_rom_via.gds2


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
# metals: PAD70NU_SL is 171 um deep with OBS solid over its footprint on M8 and M9.
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

# The project's own runners, so `make drc` here dispatches to the flow that has
# actually been run rather than to the toolkit's untried one.
DRC_SCRIPT ?= $(LEGACY_ASIC_DIR)/scripts/calibre/run_drc.sh

## LVS_SCRIPT IS DELIBERATELY NOT SET -- REMOVED 2026-08-21. It used to name
## ASIC/lvs-flow/run_lvs.sh, and that made `make lvs` HARD-BROKEN:
##
##   mk/flow.mk:761   lvs: $(if $(wildcard $(LVS_SCRIPT)),lvs-project,lvs-batch)
##   mk/flow.mk:766   $(LVS_SCRIPT) $(GDS) ..._pnr.v $(BLOCK) $(WORK_DIR) $(LOG_DIR)
##
## `lvs-project` is the escape hatch for a project shipping the SCAFFOLDED runner,
## which takes five POSITIONAL arguments and no environment. Ours is not that
## runner -- it is the same flag-driven one the toolkit ships (run_lvs.sh:81-84
## accepts only --check | --source-only | --pg-check | --help), so the GDS path
## arrives as $1, hits the catch-all, and the run dies with usage text and rc=2.
## It also passes NO environment, so every knob above would be invisible to it
## even if the argument contract matched.
##
## Unset, the wildcard is empty and `make lvs` falls through to `lvs-batch`, which
## is the target that applies LVS_ENV -- i.e. the one that can actually see
## LVS_PG, LVS_POWER, BONDPAD_CELLS and the rest. DRC_SCRIPT above stays: drc-project
## is a real, working, project-side runner and `make drc` depends on it.
##
## Do not "restore" this line. If a project-side LVS runner is ever wanted here, it
## must first accept the five positional arguments mk/flow.mk:766 passes.

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
    $(LVS_ROM_CDL_DIR)/cc_rom/rom_via.cdl \
    $(LVS_ROM_CDL_DIR)/eth_rom/eth_rom_via.cdl

## ── THE ROM CDLs ARE DERIVED, NOT READ DIRECTLY ────────────────────────────
## The two ROMs above are the ONLY entries not read from their source tree. They
## are copies whose macro-internal virtual ground `VSS` is renamed
## `VSS_ROMVIRT`, which is what makes `.GLOBAL VSS` in section 8 safe: the ROMs'
## real supplies are VDDE/VSSE and their `VSS` is the SWITCHED ground on the far
## side of the power-gate footers, so an unscoped .GLOBAL would merge it with the
## chip ground and fabricate a short across the switch. CONTRACT.md 6d prescribes
## exactly this -- derive a project-local copy, never edit vendor collateral.
##
## PER-RUN, AND THAT IS THE ONE THING THIS MUST NOT COPY FROM THE LEGACY PATH.
## ../genus-innovus uses a single shared outputs/lvs_rom_cdl, which is correct
## THERE because its ROMLIBS_DIR is also single. Here $(ROMLIBS_DIR) is
## $(RUN_DIR)/romlibs -- the ROMs are per-run and MASK PROGRAMMED -- so a shared
## derived directory would let run A's renamed ROM be consumed by run B's compare
## with nothing to say so. That is a content error of exactly the class the ROM
## gates exist to catch, wearing the costume of a caching optimisation.
## IT FOLLOWS LVS_RUN, NOT RUN_TAG. lvs.mk:104-105 lets LVS select a DIFFERENT
## run's outputs from the one RUN_TAG names, and the tool recommends that form
## ("pick a run: make lvs-batch LVS_RUN=<dir>"). Tie the ROM CDLs to RUN_TAG and
## an LVS_RUN invocation compares one run's STREAM against another run's ROMS --
## the wrong-stream class, in the one place where the content is mask programmed.
## Measured 2026-09-09: with LVS_RUN=gdsrun-20260823-rzG the rule went looking in
## build/default/romlibs. Same resolution idiom as LVS_IN_DIR, deliberately.
LVS_RUN_ROOT     ?= $(if $(LVS_RUN),$(if $(filter /%,$(LVS_RUN)),$(LVS_RUN),$(LVS_RUNS_DIR)/$(LVS_RUN)),$(RUN_DIR))
LVS_ROM_CDL_DIR  ?= $(LVS_RUN_ROOT)/lvs_rom_cdl
LVS_ROM_SRC_DIR  ?= $(LVS_RUN_ROOT)/romlibs

## The rename rule itself lives BELOW the engine include -- see section 11. It
## cannot live here: a pattern rule's target and prerequisites are expanded when
## the makefile is READ, and $(RUN_DIR) is not defined until flow.mk is included
## 35 lines further down. Defined here, the rule's target becomes the literal
## `/lvs_rom_cdl/%.cdl` and matches nothing, while $(LVS_ROM_CDL_DIR) above --
## being a recursive variable expanded at USE time -- resolves perfectly. So
## `make lvs-help` prints the right path and the build then fails with "No rule
## to make target". Measured 2026-09-09, and the split is the whole trap.

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

## ---------------------------------------------------------------------------
## POST-ROUTE SIGNOFF REPORT -- ADDED 2026-08-20.
##
## `make design-report` stops before Calibre; it reads the Innovus database and
## says nothing about the signoff decks. The broker's CheckAll+ return is almost
## entirely rulecheck tables, so there was nothing on our side to set beside it,
## and the DRC evidence sat in $(RUN_DIR)/work/drc_run/ -- OUTSIDE the outputs/
## and reports/ that package_submission.sh collects.
##
## This writes $(RUN_DIR)/reports/signoff_report.{txt,json}: stream identity and
## md5, every non-zero rulecheck grouped by family with vendor-macro attribution
## and saturation flags, the per-window density tables, POST-ROUTE timing (the
## last QoR snapshot, not the CTS one design_report quotes), ROM verdicts, and --
## the part a broker report cannot give you -- an explicit NOT RUN list.
##
## It also prints the DERIVED-LAYER WITNESSES (CHIP / CHIP_NOSR / EMPTY_AREA /
## SEALRING / SR_EDGE). Those are what separate "checked and clean" from "had
## nothing to check": with a seal ring in the stream EMPTY_AREA collapses and
## every CSR.R.1 subrule is vacuous while still reporting zero.
##
## Read-only over artefacts already on disk. No licence, seconds to run, safe to
## invoke on a finished run at any time.
SIGNOFF_REPORT_SCRIPT ?= $(DESIGN_HOME)/scripts/ci/signoff_report.py

.PHONY: signoff-report
signoff-report:
	@test -d "$(RUN_DIR)" || { \
	    echo "FAIL: no run at $(RUN_DIR) -- set RUN_TAG to a build that exists."; \
	    exit 1; }
	@test -r "$(SIGNOFF_REPORT_SCRIPT)" || { \
	    echo "FAIL: $(SIGNOFF_REPORT_SCRIPT) is not readable."; exit 1; }
	python3 "$(SIGNOFF_REPORT_SCRIPT)" --run "$(RUN_DIR)" --json

## ---------------------------------------------------------------------------
## POST-ROUTE OPTIMISATION MODE -- STATED HERE BECAUSE THE DEFAULT IS NOT WHAT
## THIS DESIGN NEEDS, AND NOTHING ELSE RECORDED IT.
##
## The toolkit defaults ROUTE_OPT_MODE to `hold` (flow/innovus/4_route.tcl:126,
## unchanged since the toolkit's first commit). On THIS design that means route
## never runs post-route setup optimisation, and the design does not close setup
## without it. MEASURED 2026-08-25 across all 14 runs that left a route
## manifest, with no exceptions in either direction:
##
##     opt_mode=hold              setup FEP 1166 1193 1429 1444 1496 1789 1791
##     opt_mode=setup_then_hold   setup FEP    0    0    0    0    0    3  101
##
## Until now the good runs got `setup_then_hold` FROM THE COMMAND LINE, by hand.
## It was never written down: it is not in design.mk, not in common.mk, and --
## the part that actually bit -- NOT IN A RUN'S OWN pins.mk, which is what
## LAUNCH.sh and RESUME.sh rebuild their `make` arguments from. So a run started
## by hand closed setup and the same run RESUMED by script silently did not.
## gdsrun-20260825-resynth is exactly that: 871 failing endpoints, WNS -0.577,
## from a route that was never asked to fix setup.
##
## Setting it here makes the intent survive the transport. Override on the
## command line for a deliberate hold-only ECO pass.
##
## ---- UPDATED 2026-08-29: setup_then_hold -> hold_then_setup ----------------
##
## READ EVERYTHING ABOVE FIRST. IT IS STILL TRUE AND IT IS NOT A MISTAKE BEING
## CORRECTED. setup_then_hold beat the toolkit's `hold` default 0-vs-1166
## failing setup endpoints, on fourteen runs, and that measurement is the entire
## reason this variable is written down at all. Nothing below retracts it.
##
## What changed is that the OTHER half of the choice finally got measured.
## setup_then_hold has a structural weakness that was always there and that the
## 2026-08-25 census could not see, because every run in it had the same
## weakness: THE HOLD PASS RUNS LAST, so whatever setup margin the first pass
## bought, the second pass is free to spend. build/derate-feas-20260826 ran both
## orders on ONE database (RESULTS.md:416-417):
##
##   D  setup then hold   the hold pass eats the setup gain -- 14 failing setup
##                        endpoints where the setup pass had left 0
##   E  hold then setup   both survive, AND the setup pass repairs the DRVs the
##                        hold pass introduced (real max_cap 6 -> 0,
##                        real max_tran 2 -> 0)
##
## At signoff -- Tempus 21.11, unmodified mmmc_sta.tcl, same derate, same
## extraction, only the database differs (RESULTS.md:423-433):
##
##   control (= the stream that shipped)  setup 4 + hold 415 = 419 failing EPs
##   E       (hold then setup)            setup 1 + hold   2 =   3 failing EPs
##
## and all three survivors are exactly 12 ps short. Combined TNS -2.519 ns ->
## -0.035 ns. Cost: 13,002 instances touched, all buffers and no delay cells,
## +0.76% area, check_drc still "No DRC violations were found", 20 min 32 s of
## optimisation (RESULTS.md:435-441).
##
## THE ORDER ON ITS OWN IS NOT WHAT DID IT, AND THIS LINE ON ITS OWN IS NOT E.
## E ran with both optimisation targets raised as well. Those are the block
## immediately below; setting this line without them is a configuration nobody
## has measured. The two changes are one change.
##
## Override on the command line for a deliberate single-direction ECO pass:
##     make route ROUTE_OPT_MODE=hold IN_RUN_TAG=<the run to ECO>
ROUTE_OPT_MODE ?= hold_then_setup
export ROUTE_OPT_MODE

## ---------------------------------------------------------------------------
## THE POST-ROUTE PASSES ARE ASKED FOR POSITIVE MARGIN, NOT FOR ZERO.
##
## THE DEFECT THIS CLOSES. Nothing in this flow ever set an optimisation target,
## in place, CTS or route -- grep opt_setup_target_slack and
## opt_hold_target_slack across ASIC/asic-toolkit/flow/ and
## ASIC/genus-innovus/scripts/ before 2026-08-29 and there are no hits. Both
## attributes default to 0.0 (confirmed by get_db on Innovus 21.11-s130_1), so
## every stage was driven to exactly zero -- and every stage duly landed within
## 10 ps of zero. From gdsrun-20260826-rc1's own reports, "View : ALL":
##
##   01b_place_opt  setup +0.009  hold -0.322 / 439   timing_summary_01b_place_opt.rep:94,106
##   03_cts_opt     setup +0.005  hold -0.003 /  43   timing_summary_03_cts_opt.rep:94,106
##   05_route_opt   setup +0.010  hold -0.005 /  13   timing_summary_05_route_opt.rep:466,478
##   06_post_fill   setup +0.009  hold -0.012 /  16   timing_summary_06_post_fill.rep:465,477
##
## Landing at +0.009 is not closure. It is closure ACCORDING TO THE P&R ENGINE,
## and the P&R engine is not the one that signs the design off.
##
## WHY ZERO IS THE WRONG TARGET, MEASURED RATHER THAN ASSUMED.
## hooks/pre_route.tcl:87-96 measured the two engines against each other on ONE
## database, the filled routed one:
##
##                       setup WNS        hold WNS
##   P&R,     no derate  +0.236           -0.004
##   P&R,     derated    +0.010           -0.012
##   signoff, no derate  +0.287           -0.014
##   signoff, derated    -0.049           -0.053
##
## Two readings come out of that, and they are different numbers:
##
##   the DERATE-SENSITIVITY gap  the same four derate factors are worth 226 ps
##     of setup to Innovus and ~332 ps to Tempus -- Innovus applies about 68% of
##     the signoff setup effect and 21% of its hold effect, so ~106 ps of setup
##     and ~31 ps of hold go unseen by the optimiser. This is the number the
##     hook quotes.
##   the END-TO-END gap          what actually matters to a target: closing at
##     +0.010 in P&R IS -0.049 at signoff, i.e. 59 ps of setup and 41 ps of
##     hold, on this database. It is SMALLER than the derate-sensitivity gap
##     because P&R is ~51 ps MORE pessimistic than signoff before any derate is
##     applied, and the two errors partly cancel. Quoting 106 as the end-to-end
##     disagreement double-counts.
##
## hooks/pre_route.tcl:100-103 names these two attributes as the remedy and says
## explicitly that the hook itself does not fix it. This is that fix.
##
## HOW THE VALUES WERE SIZED -- THREE ROUTES, AND WHY THE ANSWER IS NOT 0.075.
## The only operating point ever RUN on this design is experiment E's
## setup 0.075 / hold 0.050. It left setup at -0.012 / 1 failing endpoint at
## signoff, so 0.075 is measured to be 12 ps SHORT. Three ways to size the
## replacement, none of them taste:
##
##   1. E's own residual        0.075 + 0.012 = 0.087, if the extra ask converts
##                              1:1 into delivered slack.
##   2. under-delivery ratio    E ASKED for 0.075 and the optimiser DELIVERED
##                              +0.025 (RESULTS.md:407) -- one third of the ask.
##                              To deliver the 0.037 that would put signoff at
##                              zero it must be asked for ~0.111.
##   3. derate-sensitivity gap  ~0.106 (above).
##
## Three independent routes give 0.087 / 0.106 / 0.111. TAKE THE LARGEST: an
## over-constrained run costs runtime and area, an under-constrained one costs a
## respin, and route 1 is the only one that assumes the optimiser hits what it
## is asked for -- which route 2 measured that it does not.
##
##   ROUTE_OPT_SETUP_TARGET = 0.110   covers all three; 47% above the largest
##                                    value ever run on this design, so the
##                                    increment above 0.075 IS AN EXTRAPOLATION
##                                    and the first run at it must be compared
##                                    against E for cell count and runtime.
##   ROUTE_OPT_HOLD_TARGET  = 0.050   NOT extrapolated. This is exactly B's and
##                                    E's value, the one that took hold from 415
##                                    failing endpoints to 2 at signoff. It
##                                    already exceeds both the 41 ps end-to-end
##                                    and the 31 ps derate-sensitivity hold gap.
##                                    Raising it is the lever for the last two
##                                    12-ps hold endpoints, and the measured
##                                    price of 0.050 was 12,831 buffers -- price
##                                    the next increment before paying it.
##
## WHAT THESE DO NOT DO. They are OPTIMISATION targets, not reporting offsets:
## report_timing_summary prints actual slack either way, and a database
## snapshotted at hold target 0.050 is bit-identical to the same database
## snapshotted back at 0.0 (RESULTS.md:119-124). So the route gate's
## ROUTE_BUDGET_*_FEP counts stay honest and cannot be flattered by this block.
##
## To sweep, set them in the ENVIRONMENT for one run -- they are read by `opt`,
## so an environment value wins and route_manifest.txt records what was used:
##     ROUTE_OPT_SETUP_TARGET=0.075 make route RUN_TAG=t075 IN_RUN_TAG=main
export ROUTE_OPT_SETUP_TARGET ?= 0.110
export ROUTE_OPT_HOLD_TARGET  ?= 0.050

## ---------------------------------------------------------------------------
## SETUP RECOVERY AFTER HOLD REPAIR -- `auto` MEANS OFF ON A DESIGN THIS TIGHT.
##
## opt_post_route_setup_recovery is the step Innovus runs INSIDE a post-route
## hold pass to give back setup that the hold repair just took. Verbatim from
## <INNOVUS_DOC>/TCRcom/opt_Category_Attributes.html:
##
##   "Controls the Setup Recovery step performed when opt_design -post_route
##    -setup -hold and opt_design -post_route -hold commands have been
##    specified. ... auto: Allows the software to determine when to trigger
##    setup recovery. Here recovery will be triggered if WNS or TNS degrade
##    beyond a certain margin. true: Always triggers setup recovery if timing is
##    not met, irrespective of the gain/degradation in post-route timing."
##
## It defaults to auto and it is set NOWHERE in this flow -- get_db on an
## untouched Innovus 21.11-s130_1 session returns `auto`, and there is no
## set_db for it anywhere in ASIC/asic-toolkit/flow/ or
## ASIC/genus-innovus/scripts/. ON THIS DESIGN, auto HAS NOT BEEN ENOUGH.
##
## Both hold-repair experiments ran at the default `auto` -- neither run.tcl
## touches the attribute -- and both came out of the hold pass with setup
## degraded (Innovus's own numbers):
##
##   B  hold pass alone      setup +0.010 -> -0.023   33 ps lost, 10 failing EPs
##                                          (RESULTS.md:113-116)
##   D  setup, then hold     setup +0.047 -> -0.020   67 ps lost, 14 failing EPs
##                                          (RESULTS.md:247-253)
##
## What auto left behind was cheap to pick up: E ran an explicit setup pass on
## B's output and got setup to +0.025 -- 48 ps better than where auto's hold
## pass left it -- in 8 min 15 s for 12 cells (RESULTS.md:405-412). So whatever
## auto did or did not trigger, it stopped well short of what was recoverable,
## and `true` is the setting whose documented behaviour is to keep going:
## "Always triggers setup recovery if timing is not met, irrespective of the
## gain/degradation".
##
## HOW MUCH OF THIS IS MEASURED, EXACTLY -- because the next reader will want to
## cite experiment E for it and E does not say this.
##   MEASURED: recovering setup on a hold-repaired database works on this
##     design, is cheap, and does not give the hold repair back -- 8 min 15 s,
##     12 cells, setup +0.025 and hold still 1 endpoint (RESULTS.md:399-412).
##   MEASURED: this attribute exists in this tool version, is settable, and
##     reads back `true` -- get_db/set_db on the rc4 routed database, 2026-08-29.
##   NOT MEASURED: E did that recovery as an EXPLICIT SECOND
##     `opt_design -post_route`, which is what ROUTE_OPT_MODE=hold_then_setup
##     above now issues. This attribute is the in-pass twin of the same idea and
##     runs inside the -hold pass. Its INCREMENTAL effect on top of the explicit
##     pass is unmeasured; the expectation is that the hold pass hands the setup
##     pass a better starting point and the run finishes sooner, not that the
##     final numbers change. Do not quote E as proof of this line.
##
## THE ATTRIBUTE THAT LOOKS LIKE IT BELONGS BESIDE THIS ONE, AND DOES NOT.
## opt_post_route_allow_setup_tns_degradation guards setup TNS -- "ensure that
## the setup total negative slack is maintained" -- not WNS. This design's whole
## margin is WNS and its setup TNS is already 0.000 at every stage in the table
## above, so the guard is vacuous here; its Tempus twin was set false in every
## shipped ECO and still leaked 5 ps of WNS. It is also NOT AN INNOVUS ATTRIBUTE
## AT ALL: get_db and set_db both return **ERROR (IMPDBTCL-247) "not a
## recognized object or root attribute" on 21.11-s130_1 -- without raising a Tcl
## error, so a script that sets it exits 0 having done nothing. Measured
## 2026-08-29. Do not add it.
export ROUTE_OPT_SETUP_RECOVERY ?= true

## ---------------------------------------------------------------------------
## RUN REPORT -- every stage's VALUES, in four renderings.
##
## FOUR DOCUMENTS DESCRIBE A RUN AND NONE OF THEM IS THIS ONE:
##
##   ci/collect-results.py     DID each check run, and did it pass?  STATUS
##   asic-flow-design-report   what IS this design?                  METRICS
##   evidence_flow.py          can this STREAM be bound to a run?    GDS EVIDENCE
##   run_report.py             what NUMBER did each check produce?   VALUES
##
## The gap it closes: a reader handed `drc: pass` cannot tell 0 from
## 12-under-a-budget-of-12, and this project has shipped both. It reads the
## stage manifests, the stage gate files and the tools' OWN message summaries --
## never a grep over a tool log, because Genus and Innovus both echo their own
## Tcl source and a grep for an error ID matches the flow's comments.
##
## Writes $(RUN_DIR)/reports/run_report.{json,yaml,html,md}. The JSON is the
## document; the other three are rendered FROM it and read nothing else, so they
## cannot disagree with it or with each other.
##
## IT CANNOT FAIL A BUILD -- `|| true`, same contract as design-report. `make`
## decides whether a run was good; this says what the run WAS. Two verdicts on
## one run disagree eventually and the fuzzier one gets quoted.
##
## Read-only, no licence, seconds to run, safe on a finished run at any time.
RUN_REPORT_SCRIPT ?= $(DESIGN_HOME)/scripts/ci/run_report.py

## Set to 0 to stop the route stage regenerating it. `make run-report` still works.
RUN_REPORT_AUTO ?= 1

.PHONY: run-report run-report-auto run-report-publish
run-report:
	@test -d "$(RUN_DIR)" || { \
	    echo "FAIL: no run at $(RUN_DIR) -- set RUN_TAG to a build that exists."; \
	    exit 1; }
	@python3 "$(RUN_REPORT_SCRIPT)" --root "$(DESIGN_HOME)" --run-dir "$(RUN_DIR)"

## The route stage's hook. Silent when disabled, and incapable of failing.
run-report-auto:
	@if [ "$(RUN_REPORT_AUTO)" = "1" ] && [ -d "$(RUN_DIR)" ]; then \
	    python3 "$(RUN_REPORT_SCRIPT)" --root "$(DESIGN_HOME)" \
	        --run-dir "$(RUN_DIR)" --quiet || true; \
	fi

## PUBLISHING IS A CLAIM, so it is never fired by a build. The report goes to
## asic-record; --klass names the stream repo a matching evidence publish would
## use and is recorded as a property so the two can be joined later.
## Measured 2026-08-25: asic-release is EMPTY -- no release has ever been made.
run-report-publish:
	@python3 "$(RUN_REPORT_SCRIPT)" --root "$(DESIGN_HOME)" --run-dir "$(RUN_DIR)" \
	    --publish --klass "$(or $(RUN_REPORT_KLASS),candidate)"

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

# The derived ROM CDLs, before anything reads MACRO_CDLS. Without this the rename
# is never run and preflight stops with `MISS MACRO_CDLS <path>` -- loud, but a
# step no operator should have to take by hand.
#
# HYPHENATED, unlike lvs_project.mk:364's `lvs_batch`: the toolkit spells these
# targets with hyphens and the underscore forms do not exist here. That drift is
# the same one that makes POST_STREAM_TEST_PROCEDURE.md 7a's `make lvs_pg_gds`
# fail with "No rule to make target".
lvs-preflight lvs-source lvs-batch: $(filter $(LVS_ROM_CDL_DIR)/%,$(MACRO_CDLS))

# The rename, with its acceptance test inline: no bare VSS may survive, and VSSE
# must be untouched. Ported from lvs_project.mk:196 -- a rename that silently
# half-applied would be indistinguishable from the bug it fixes.
#
# HERE, NOT IN SECTION 9, because a pattern rule is expanded at READ time and
# $(RUN_DIR) only exists after the engine include above.
$(LVS_ROM_CDL_DIR)/%.cdl: $(LVS_ROM_SRC_DIR)/%.cdl
	@mkdir -p $(dir $@)
	@sed -E 's/\bVSS\b/VSS_ROMVIRT/g' $< > $@.tmp
	@test "$$(grep -coE '\bVSS\b' $@.tmp)" = 0 || { \
	    echo "LVS ROM CDL: bare VSS survived the rename in $@"; rm -f $@.tmp; exit 1; }
	@test "$$(grep -coE '\bVSSE\b' $@.tmp)" = "$$(grep -coE '\bVSSE\b' $<)" || { \
	    echo "LVS ROM CDL: the rename altered VSSE in $@"; rm -f $@.tmp; exit 1; }
	@mv $@.tmp $@
	@echo "LVS ROM CDL: $< -> $@ (internal VSS renamed VSS_ROMVIRT)"
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

# ── ROUTE derate ────────────────────────────────────────────────────────────
# CTS_DERATE above covers everything up to the clock tree. The toolkit's route
# stage has NO derate knob at all - grep flow/innovus/4_route.tcl, it contains
# no set_timing_derate - so route_design and both opt_design -post_route passes
# run on whatever derate the input database happens to carry.
#
# Measured on this design, that inheritance is partial: report_timing_derate on
# the route_preopt database names default_delay_corner_max and
# typical_delay_corner and NOT default_delay_corner_min, which is the corner
# hold signs off on. hooks/pre_route.tcl re-states the derate at the route seam,
# explicitly and per active corner, and records it in route_manifest.txt. Read
# that file's header before changing anything here.
export ROUTE_DERATE ?= 1

# THE FOUR FACTORS ARE DELIBERATELY NOT SET HERE. hooks/pre_route.tcl resolves
# them tech-pack-first (derate_data_early/late, derate_clock_early/late) and
# falls back to 0.95/1.05/0.97/1.03 only when the pack registers none - which is
# the case today. Pinning them in this file would make that fallback dead code
# and hide the day the pack finally carries the foundry's OCV table.
#
# To sweep, set them in the ENVIRONMENT for one run - they are read by `opt`, so
# an environment value wins and the manifest records what was used:
#   ROUTE_DERATE_DATA_E=0.92 ROUTE_DERATE_DATA_L=1.08 \
#   ROUTE_DERATE_CLK_E=0.95  ROUTE_DERATE_CLK_L=1.05  \
#       make route RUN_TAG=ocv_108 IN_RUN_TAG=main
# and set the matching STA_DERATE_* for ASIC/sta/run_signoff_sta.tcl, or the
# route run and the signoff that judges it sit at different derate points.

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
# The two were VDDIO and VSSIO - supplies distributed by ABUTMENT through the
# pad-ring fillers. check_connectivity gives up on a net with no routing at all,
# so nothing in this flow verified that bus was continuous.
#
# 2 -> 0, 2026-08-22. THE DESIGN CHANGED UNDER THE EXPECTATION; the expectation
# did not go stale on its own. c7e488f ("power_plan: route VDDIO/VSSIO, which
# were registered but never given geometry") added the route_special
# {pad_pin pad_ring} pass those two nets never had. They now carry real special
# wires, so they are no longer "no routing at all" and IMPVFC-98 is legitimately
# 0. Named nets, measured, not inferred:
#     build/fp1505 (pre-c7e488f)    "Net VDDIO: no routing"  "Net VSSIO: no routing"
#                                   IMPVFC-98 = 2, VDDIO/VSSIO opens = 0
#     build/gdsrun-20260822-allfix  12 special-route pieces on each
#                                   IMPVFC-98 = 0, VDDIO/VSSIO opens = 12 + 12
# The finding did not disappear, it MOVED: those 24 pieces are per-pad stubs with
# no VDDIO/VSSIO ring to join, so they now report as IMPVFC-200 opens and are
# inside conn_opens (51 = VDD 14 + VSS 13 + VDDIO 12 + VSSIO 12). The IO supply
# buses are still NOT verified continuous - that is now a PG-opens question, not
# an unrouted-net one.
#
# SETTING THIS TO 0 DOES NOT GIVE THE QUIET FAILURE BACK. The mode the equality
# stood in for - supply pads deleted from the netlist - is checked directly and
# by name at the place stage by PLACE_EXPECT_PADS (11a below / design.mk:961,
# 2_place.tcl:1017), which is a hard flow_fail on a per-rail count and is
# currently passing at VDDIO=12 VSSIO=12 VDD=6 VSS=4. That check is strictly
# stronger than inferring pad loss from a net count, because it names the rail.
# If PLACE_EXPECT_PADS is ever unset, put this back to an equality that means
# something or the pad-loss mode is unguarded again.
export ROUTE_EXPECT_UNROUTED ?= 0

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
# CORRECTED 2026-08-19, SAME DAY: the paragraph above (mechanism, the four real
# shorts) is still true. What follows it in every prior version of this section
# was NOT - the CROSSINGS ceiling itself was the defect, not the crossings. Kept
# here rather than deleted because the reasoning that reached the wrong ceiling
# is exactly the reasoning someone will reach for again.
#
# THE CROSSINGS ARM IS RETIRED. Four independent findings, two of them checked
# directly against source rather than taken on report:
#   1. PHYSICS, decisive, verified against the LEF: every macro's OBS block
#      (eth_rom_via, flash_cache_data, flash_cache_tag, rf_01k/08k/16k/32k,
#      rom_via) lists M1-M4 and VIA1-VIA3 and NOTHING above M4. No macro
#      obstructs M5. An M5 stripe running THROUGH a macro footprint violates
#      nothing - the toolkit comment this ceiling was built on ("M5 is a layer a
#      mesh pass is meant to cut at a macro boundary") describes a tech this
#      library is not.
#   2. ARITHMETIC. Sum of macro heights / the 15um set-to-set pitch x 2 stripes
#      predicts 278 crossings for an UNCUT UNIFORM ladder; 300 was measured, 8%
#      over from partial-overlap boundary effects. 300 is what the mesh looks
#      like built exactly as power_plan.tcl specifies it - not a defect count.
#   3. PROVENANCE, verified against the commit: PLACE_MAX_MACRO_STRIPES 0
#      landed inside the toolkit's c66522c, a 4,465-line commit ABOUT METAL
#      DENSITY whose message never mentions macro stripes once, confirmed by
#      grep. The stated reason at the site was process hygiene ("a ratchet
#      nobody ratchets is the defect this file is full of"), never achievability.
#   4. NO REFERENCE. No census manifest, on either chiplet, has ever recorded
#      macro_pg_crossings at 0. The one number anyone has ever cited as a
#      reference - 306/300 from the toolkit fix's own live-verification commit -
#      was measured on THIS design, not an independent one.
# A 0 ceiling would additionally have been ACTIVELY HARMFUL if enforced by
# cutting M5 at every macro: M5 is add_stripes_stacked_via_bottom_layer for the
# M8/M9 passes above, and M4 is the only macro-pin layer, so cutting M5 at the
# boundary removes the M8/M9 mesh's only landing point over every macro in the
# design - manufacturing the exact supply hole the grid exists to prevent.
# One supporting signature, independently noticed before the measurement
# confirmed it: the crossings were uniform across all 21 macros at EXACTLY the
# M5 ladder's own design spacing (-width 1 -spacing 0.5, power_plan.tcl:890),
# not a scatter of near-collisions - systematic mesh geometry, not a stochastic
# alias. `PLACE_MAX_MACRO_STRIPES` is retired to its toolkit default; do not
# ratchet a ceiling now known to have no achievable value.
#
# ── SET 2026-08-21, and this closes the "REQUIRED BEFORE THE NEXT CANDIDATE
# RUN" item recorded below ──────────────────────────────────────────────────
#
# The crossings arm fired for the FIRST TIME on 2026-08-21 at 300, not because
# anything regressed but because the census could not previously count. Both
# reads in pnr_macro_stripe_census fed a NESTED get_db return straight into a
# `llength == 4` test (.bbox for the macro, .rect for the wire), so c(wires)
# was always 0 and this ceiling passed on every run that has ever been made,
# having examined nothing. Fixed in toolkit 5f0eab1 / a776532.
#
# PLACE_MAX_MACRO_STRIPES: 330, i.e. 300 measured + 10% headroom. The analysis
# below establishes 300 as the mesh built exactly as power_plan.tcl specifies
# it, and a 0 ceiling as both unachievable and actively harmful. A ceiling
# still earns its place as a REGRESSION detector - 330 catches a real change in
# the ladder without flagging the nominal grid.
export PLACE_MAX_MACRO_STRIPES ?= 330
#
# PLACE_MIN_MACRO_PG_GAP: 11d sets 0.155 and notes it had no measured spread to
# size a margin from. The grounding it wanted is not in this design's arithmetic
# -- it is in the M5 wide-metal spacing table of the tech LEF (the parallel-run
# table for that layer). Read it there; those numbers are vendor data and are
# deliberately not reproduced anywhere in this repository.
#
# What that table says, in words: the M5 PG ladder is 1.0um wide
# (power_plan.tcl:890, -width 1), which selects a wide-metal row rather than the
# narrow-line row, and a stripe running past a macro has a parallel run long
# enough to land in the saturated right-hand column of it. The required spacing
# there is STRICTLY GREATER than the 0.155 this knob is set to.
#
# NOTE FOR WHOEVER OWNS 11d: 0.155 is therefore below the manufacturing limit for
# the case it is meant to guard, and a gap a few nm above 0.155 would pass this
# gate and still violate M5 spacing. The defensible floor is the table's value
# for that row and column. Left unchanged here because it is 11d's number and
# the difference does not fire on this design -- measured min_gap is 0.5000um,
# more than 3x either candidate. To confirm, read the WIDTH row that 1.0um
# selects in $(TECH_LEF) and compare its long-parallel-run entry against 0.155.
#
# It sits BELOW the 0.5um nominal grid spacing exactly as the note requires, so
# it does not flag the 300 healthy crossings - the census measures 0.5000um on
# all 42 macro/net rows. It fires only when two ladders actually close toward
# the manufacturing limit, which IS the four-short hazard the crossings arm
# could never see.
# (NO ASSIGNMENT HERE -- 11d below already sets it. This block is the tech-LEF
# evidence for that value, nothing more: a duplicate ?= earlier in the file
# would silently win over 11d's derivation.)
#
# THE ORIGINAL HAZARD IS STILL REAL AND IS NOT COVERED BY ANY OF THIS. The
# crossings arm never would have caught the four shorts - that was a min_gap ->
# 0 event between two DIFFERENT macros' ladders, not a stripe crossing one
# macro's own footprint. The arm that answers this is PLACE_MIN_MACRO_PG_GAP,
# and it is currently -1 (UNGATED - see 2_place.tcl:1174-1195, which warns
# "NOT GATED" at that value on every run). Retiring the crossings ceiling
# WITHOUT gating this leaves the real hazard uncovered, which is worse than
# today's state, not better. REQUIRED BEFORE THE NEXT CANDIDATE RUN: derive a
# real floor for PLACE_MIN_MACRO_PG_GAP. VERIFIED WRONG, do not reuse: the
# 2.70um clearance figure above is `(S+2W) - (D mod P)` from the PHASE-OVERLAP
# formula - how much room a macro had to MOVE before its ladder aliased a
# neighbour's, not an edge-to-edge PG gap. The census already measures 0.5000um
# on all 42 macro/net rows on a HEALTHY grid (power_plan.tcl:890's own
# -spacing 0.5) - so a floor at 2.70 would fire on every one of the 300
# crossings at nominal spacing, look authoritative because it is a real number
# from this design's own history, and be wrong for exactly that reason. The
# floor wants to come from the M5 SPACINGTABLE for the relevant width and
# parallel-run length in the TECH LEF, not this design's own arithmetic, and it
# must sit BELOW 0.5um or it flags the nominal grid too. Set it, with the
# derivation and the date, in the same style as every other budget in this
# file. Left unset here deliberately: naming the requirement is the point,
# exactly as an unratcheted default sat inert twice already in this section.
#
# set PLACE_MACRO_PG_CHECK=0 remains forbidden for the reason the mechanism
# paragraph above still states - it silences BOTH arms, including the one
# (min_gap) that is the actual live hazard once gated. A run that did this
# anyway on 2026-08-19 (RUN_TAG gdsrun-20260819) is carried as a baseline with
# this blind spot named, not as a signoff candidate.
#
# DERIVED 2026-08-20: THE FLOOR, FROM THE TECH LEF, NOT FROM THIS DESIGN'S
# OWN HISTORY. Source is LAYER M5's SPACINGTABLE PARALLELRUNLENGTH rule in the
# installed TSMC 65LP routing tech LEF (resolve it with
# `ASIC/tech_wrappers/tsmc65/scripts/pdk_paths.sh tech-lef` under
# TSMC_65_HOME - the install path and revision are deliberately not repeated
# here, per that script's own header, since this repo is public). M5 carries
# no SAMENET override in this LEF, so this table is the ONLY spacing rule
# governing two M5 shapes on different nets - exactly what min_gap measures.
#
# The table is two-dimensional: WIDTH buckets and PARALLELRUNLENGTH (PRL)
# buckets, five breakpoints each. This design's M5 PG stripes are `-width 1`
# (power_plan.tcl:890) - 1.000um falls in the WIDTH bucket covering [0.4,
# 1.5)um, not the narrowest (signal-routing) row. Two aliasing PG stripes run
# parallel for a macro's height or more, tens of um - and in that WIDTH row
# the required spacing already reaches its maximum well under PRL 1um and
# does not increase for any longer overlap, so the geometry here sits at the
# row's SATURATED, worst-case entry, not some lower default. THE ENTRY'S
# VALUE IS DELIBERATELY NOT REPEATED HERE, per VENDOR_COLLATERAL.md ("when
# you need foundry numbers, write a program that reads them at runtime -
# never a file that contains them") - re-derive it with the same method
# (`pdk_paths.sh tech-lef`, LAYER M5, SPACINGTABLE, the WIDTH/PRL bucket
# above) rather than trust a transcribed digit. It is the bare DRC minimum
# edge-to-edge spacing between two different-net M5 shapes of this width: at
# or above it the gap is legal, below it is an actual foundry-rule spacing
# violation - which is what "danger of a short" means for this layer. It
# sits well under the 0.500um this grid actually runs at (power_plan.tcl:890)
# - confirmed by the exported floor below still landing with better than 3x
# headroom under the grid the retraction above already measured at 0.5000um
# on all 42 macro/net rows.
#
# MARGIN ADDED, STATED EXPLICITLY: the floor below is ONE
# MANUFACTURINGGRID STEP - this tech LEF's own drawing grid, also not
# repeated here for the same reason - under the bare SPACINGTABLE minimum
# above, not a round number and not a percentage pad. This follows the
# toolkit's own instruction at the knob's definition (2_place.tcl: "set it
# in design.mk to just under the smallest clearance the design is known to
# be safe at") and this file's own idiom for every other ratchet in this
# section: PLACE_MIN_PG_VIAS in 11b is "one below measured", an integer
# floor one quantum inside its boundary; a continuous micron value has no
# integer quantum, so the process's own manufacturing grid is the smallest
# legitimate step to use instead. No larger margin is added: min_gap has
# never been gated before tonight, so unlike 11b's two ratchets - which had
# TEN pad-correct runs of measured spread to size a margin from - there is
# no measured healthy-spread data for this metric to derive a bigger one from,
# and inventing one would repeat the 2.70um mistake this section already made
# once: a plausible number with no grounding in what it is gating.
export PLACE_MIN_MACRO_PG_GAP ?= 0.155

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
# UPDATE 2026-08-20: the layer-range half of this is closed, the budget half
# is still not answerable, and it took two more runs to tell those apart.
#
# {M1 AP} genuinely IS the full stack including the top interface -
# routing_layer_bottom is M1 and top_metal_layer has been AP in this tech pack
# since the toolkit's own import (tech/tsmc65/tech.tcl:505, commit eddaf0c),
# so the route gate has always defaulted to the full range. No special command
# is needed; `make route` already asks the right question every time it runs.
# Two real runs confirm this rather than assert it:
#   fp1505           build/fp1505/reports/..._power_vias.rep,   Aug-19 00:17
#                    `check_power_vias -layer_range {M1 AP}` -> 575 missing
#                    (M4->M5 475; full by-pair split in that report's Summary)
#   gdsrun-20260819  build/gdsrun-20260819/reports/..._power_vias.rep, 18:47,
#                    same command -> 520 missing (M4->M5 415), also recorded
#                    at reports/route_manifest.txt:185 `pg_via_missing 520`
#
# NEITHER CLOSES THE BUDGET, for three separate reasons - do not reach for
# either number:
#   1. gdsrun-20260819 is the exact RUN_TAG 11d (above) already disqualifies:
#      built with `PLACE_MACRO_PG_CHECK=0` (reconfirmed here directly from its
#      own reports/place_manifest.txt:103), which 11d calls "carried as a
#      baseline with this blind spot named, not as a signoff candidate." One
#      run, one database - that verdict was reached about min_gap and applies
#      here unchanged.
#   2. Both fp1505 and gdsrun-20260819 record `prov.design.git_dirty yes` in
#      their own manifests (gdsrun-20260819's git_describe:
#      `pgfix-island-feed-20260818-48-g4ddf4be-dirty`) - neither is
#      reproducible from a clean HEAD, the same disqualifier this project
#      applies to the shipping stream elsewhere.
#   3. fp1505 is additionally stale on its own terms: its power_plan.tcl was
#      36,789 bytes at the time it ran versus 60,858 at HEAD now - it predates
#      the PG island feed and the VDDIO/VSSIO route_special, so it measures a
#      grid that no longer exists (docs/plans/GDS_RUN_PLAN_2026-08-19.md: "Any
#      re-run produces a different power grid and every number above must be
#      re-measured").
#
# ALL THREE NUMBERS ON RECORD ARE DIFFERENT DATABASES - say so, do not
# arithmetic across them. 575 (fp1505) and 520 (gdsrun-20260819) cannot be the
# same lineage as each other (they disagree, and neither run's own history
# derives from the other); and neither can be "556 (bottom..top-1) plus
# whatever AP adds" from the ONE DATABASE the 4/556 pair above was measured
# on, because 520 < 556 and adding layers to a range can only ADD missing
# vias, never remove them. Three builds, three counts - 556-ish, 575, 520 -
# none of them the answer for a budget derived from a current, clean HEAD.
#
# WHAT WOULD ACTUALLY CLOSE THIS: the same `-layer_range {M1 AP}` command
# (free - it is what `make route` already runs), taken from a build that is
# BOTH clean and reproducible (`git_dirty no` against a committed HEAD, not a
# worktree scratch state) AND NOT run with `PLACE_MACRO_PG_CHECK=0` (i.e.
# built after PLACE_MIN_MACRO_PG_GAP above is gated at 0.155, not the
# forbidden knob that produced gdsrun-20260819). That run does not exist yet.
# Do NOT write ROUTE_BUDGET_PG_VIAS from any run on record: run the clean one,
# then ratchet with the per-layer-pair split recorded beside it, same as
# always intended.

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

#-----------------------------------------------------------------------------
# EVIDENCE, AFTER THE STAGE'S OWN VERDICT EXISTS
#
# The toolkit's route recipe calls these targets once 4_route.tcl has exited,
# route_gate.txt has been written AND PARSED, the manifest exists and
# design-report-auto has run. Not at the post_route Tcl hook: that fires 554
# lines before the verdict exists, so anything there would have to report
# "verdict unknown" for every gate the stage owns.
#
# NON-FATAL TO THE BUILD, FATAL TO THE CLAIM: a store outage must not destroy a
# four-hour route, but the run is then not an evidenced run. See ASIC/evidence.mk
# and mk/flow.mk's `post_stage_targets`.
#
# Publishing is deliberately NOT enabled from the flow. Set EVIDENCE_PUBLISH=1
# to push, or run `make evidence-publish` when the bundle has been looked at.
ROUTE_POST_TARGETS = evidence run-report-auto

# SIGNOFF STA IS DELIBERATELY NOT IN THAT LIST, and the reason is measured, not
# a preference. Asked and answered 2026-08-26.
#
# The case FOR putting it here is strong: STA needs a routed database and
# parasitics, this hook fires exactly once a route has finished and its verdict
# exists, and 12 minutes on a 4-hour route is 5%. Every route would then be
# timed automatically, which is the whole point.
#
# It cannot go here as the harness stands. ASIC/sta/run_sta.sh:83-87 refuses a
# database whose files changed in the last 20 minutes -- a guard that exists
# because reading a half-written route produces a corrupt-DB report that reads
# like a design defect. This hook fires SECONDS after the route wrote that
# database, so the guard would fire on every single invocation and STA would
# never run. The only way to make it run from here is STA_FORCE, i.e. switching
# off the guard for the one caller most likely to trip it legitimately, which
# is papering over rather than plumbing.
#
# So it is a signoff STAGE instead -- ci/signoff.yaml's sta-signoff, in the
# physical phase, with needs_implementation naming this build's routed database
# AND its route_manifest.txt. That encodes "the route must have FINISHED"
# declaratively, which is the property the 20-minute wall clock was
# approximating, and it does it without a timer. The blocking half is
# sta-binding: a candidate with no timing result of its own fails signoff.
#
# WHAT WOULD CHANGE THIS. Give run_sta.sh a route_manifest.txt test in place of
# (or ahead of) the mtime test -- the manifest is written at the END of the
# route, so its presence answers "is this database finished" exactly, with no
# window to be wrong about. Then this line can gain `sta` and every route gets
# timed with no operator step at all. That change belongs in ASIC/sta/, not
# here.
