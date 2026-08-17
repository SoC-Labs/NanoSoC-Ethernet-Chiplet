#-----------------------------------------------------------------------------
# Common ASIC synthesis definitions for nanosoc-multicore-system
# A joint work commissioned on behalf of SoC Labs, under Arm Academic
# Access license.
#
# Contributors
#
# David Mapstone (d.a.mapstone@soton.ac.uk)
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# Included by all flow Makefiles under ASIC/

# This file was copied here from nanosoc-multicore-system/syn/asic/common.mk,
# where it sat TWO levels below the repo root — hence the old `/../..`. It now
# lives at ASIC/common.mk, ONE level down, and the chiplet repo is not the SoC:
# the SoC is a submodule of it. So both the depth and the target changed.
#
# `?=`, not `:=`: set_env.sh is the authority. The old `:=` won over a correctly
# sourced environment, silently retargeting every derived path below (ETH_SS_HOME,
# PHC_AHB_HOME, CMSDK_DIR, the ROM specs, the firmware build dir) at
# /home/dam1n19/SoCLabs — a directory that just happens to exist, so nothing
# failed loudly.
CHIPLET_HOME_DEFAULT := $(realpath $(dir $(lastword $(MAKEFILE_LIST)))/..)
export NANOSOC_ETH_CHIPLET_HOME ?= $(CHIPLET_HOME_DEFAULT)

# THIS file, by absolute path, captured before any include{} of ours can move
# $(lastword $(MAKEFILE_LIST)) off it. Recipes that re-enter this makefile must
# use $(COMMON_MK), never $(lastword $(MAKEFILE_LIST)): that spelling is
# evaluated when the RECIPE runs, by which time it names whatever file was
# included LAST. Under ASIC/genus-innovus/Makefile that is already
# drc_project.mk (Makefile:36), so `make -C genus-innovus tsmc_65_romlibs` used
# to re-enter the wrong makefile and die claiming there was no such target.
COMMON_MK := $(abspath $(lastword $(MAKEFILE_LIST)))
export NANOSOC_MULTICORE_HOME   ?= $(NANOSOC_ETH_CHIPLET_HOME)/nanosoc-multicore-system

# ── DESIGN_HOME: the design-agnostic spelling of "the repo root" ────────────
# The flow scripts used to read $::env(NANOSOC_ETH_CHIPLET_HOME) directly, which
# bakes THIS design's name into files that are otherwise portable (config.tcl,
# pnr_utils.tcl, the stage scripts). DESIGN_HOME is the same directory under a
# name a second chiplet can use unchanged.
#
# BOTH NAMES STAY LIVE. Every Tcl call site resolves DESIGN_HOME first and falls
# back to NANOSOC_ETH_CHIPLET_HOME, so a shell that sourced set_env.sh (which
# exports only the old name) still runs, and so does a half-migrated tree. Drop
# the fallback only once set_env.sh exports DESIGN_HOME too.
#
# `?=` for the same reason as everything else here: a sourced set_env.sh or a CI
# export wins.
export DESIGN_HOME ?= $(NANOSOC_ETH_CHIPLET_HOME)

# ── Project / submodule / IP env (mirrors set_env.sh) ──────────────────────
# The flists reference these via ${VAR}; export them here so the ASIC flows
# resolve every RTL path WITHOUT requiring `source set_env.sh` first. All
# `?=` so a sourced set_env.sh (or CI env) still wins. Derived from
# NANOSOC_MULTICORE_HOME exactly as set_env.sh derives them.
export ARM_IP_LIBRARY_PATH       ?= /research/AAA/ip_library
export SOCLABS_PROJECT_DIR       ?= $(NANOSOC_MULTICORE_HOME)
export SOCLABS_NANOSOC_SOC_DIR   ?= $(NANOSOC_MULTICORE_HOME)
export SOCLABS_NANOSOC_ARCH_TECH_DIR ?= $(NANOSOC_MULTICORE_HOME)/nanosoc_arch_tech
export SOCLABS_NANOSOC_GEN_DIR   ?= $(SOCLABS_NANOSOC_ARCH_TECH_DIR)/nanosoc_gen
export ETH_SS_HOME               ?= $(NANOSOC_MULTICORE_HOME)/ethernet-subsystem-ahb
export ETHMAC_AHB_HOME           ?= $(ETH_SS_HOME)/ethernet-mac-ahb
export ETHMAC_IP_DIR             ?= $(ARM_IP_LIBRARY_PATH)/OpenCores-EthMAC
export HA1588_IP_DIR             ?= $(ARM_IP_LIBRARY_PATH)/OpenCores-HA1588
# Cortex-M0+ processor IP — both cores are full RTL in the base flist
# (logical/cortexm0plus/verilog/...). Required by every ASIC flow; without
# this export the flist parser silently drops the cores when set_env.sh has
# not been sourced. Value mirrors set_env.sh.
export ARM_CORTEXM0PLUS_IP_PATH  ?= $(ARM_IP_LIBRARY_PATH)/Cortex-M0-plus/AT590-BU-50000-r0p1-01rel1
export AHB_BRIDGES_HOME          ?= $(ETHMAC_AHB_HOME)/amba_wb_bridges
export PHC_AHB_HOME              ?= $(NANOSOC_MULTICORE_HOME)/ptp-hardware-clock-ahb
export PHC_HOME                  ?= $(PHC_AHB_HOME)
export AHB_QSPI_HOME             ?= $(NANOSOC_MULTICORE_HOME)/ahb_qspi
export SOCLABS_AHB_QSPI_DIR      ?= $(AHB_QSPI_HOME)
export IPC_MAILBOX_HOME          ?= $(NANOSOC_MULTICORE_HOME)/inter-processor-communications-ahb
# The two chiplet-level components. The ASIC flist -f-includes
# ${TIDECHART_HOME}/flist/tidechart.flist, and the generated tidelink sub-flist
# is written entirely in ${TIDELINK_HOME} paths. Without these exports Genus
# reads the whole SoC, then dies at the END of read_flist.tcl with
# "Environment variable TIDELINK_HOME is not set" — ~10 minutes in, after every
# other file has loaded, so it reads as a link-stage problem rather than a
# missing export. set_env.sh defines them; the ASIC flows do not source it.
export TIDELINK_HOME             ?= $(NANOSOC_ETH_CHIPLET_HOME)/tidelink
export TIDECHART_HOME            ?= $(NANOSOC_ETH_CHIPLET_HOME)/tidechart

# ── CMSDK path ─────────────────────────────────────────────────────────────
# ARM Cortex-M System Design Kit (required for cmsdk_ahb_to_sram / AHB fabric)
export CMSDK_DIR ?= $(ARM_IP_LIBRARY_PATH)/BP210/BP210-BU-00000-r1p1-00rel0

# ── TSMC65 PDK roots (needed by genus-innovus/scripts/config.tcl) ───────────
# config.tcl references $::env(TSMC_65_HOME) (TSMC TSMCHOME staggered IO lib +
# tcbn65lp standard-cell NLDM) and $::env(PHYS_IP) (Arm cln65lp sc12 base-cell
# LEF/DB). set_env.sh does NOT export these, so the Genus flow (which includes
# this common.mk) resolves them here. Both `?=` so a site/CI export wins.
#   TSMC_65_HOME is the GROUP-shared PDK (/tsmc65pdk, group tsmc65pdkgrp), not a
#   per-user tree: the previous default (/home/dwn1c21/SoC-Labs/phys_ip/TSMC/65)
#   is readable only to members of group `tsmc65`, which excludes CI and most
#   hosts. /tsmc65pdk/65 carries the same CMOS/ + iolib/ layout — every path
#   config.tcl builds off TSMC_65_HOME resolves identically under it, and it is
#   the tree the hardcoded DRC ruledeck / GDS-out map in the flow already use.
#   PHYS_IP is the shared read-only Arm phys-IP library.
export TSMC_65_HOME ?= /tsmc65pdk/65
export PHYS_IP      ?= /research/AAA/phys_ip_library

# Which absolute prefixes scripts/ci/run_provenance.py should record as EXTERNAL
# (read-only, hashed in place, never copied). Built from the variables above
# rather than respelled, so this file stays the single place that names a site
# mount and run_provenance.py - which is published - names none of them. Add a
# prefix here, not there.
#
# The EDA install root is deliberately ABSENT rather than spelled: a tool mount
# is the same inventory-shaped disclosure as a PDK mount, and it does not need to
# be here. run_provenance.py falls through to repo_of() for any path it does not
# recognise, that returns None for anything outside a git repository, and the
# result is "external" either way. The prefixes below buy the same answer one
# step earlier for the trees we do already name; they are not load-bearing.
export PROVENANCE_EXTERNAL_PREFIXES ?= $(TSMC_65_HOME):$(PHYS_IP):$(ARM_IP_LIBRARY_PATH)

# ── Foundry collateral — RESOLVED HERE ONCE, SPELLED NOWHERE ───────────────
# Paths under the PDK end in a component that names the DECK REVISION and the
# IP RELEASE this site bought. The family spelling is public; the revision
# suffix is purchase information, and this repository is published. Those
# suffixes used to appear ~65 times across ~30 files.
#
# pdk_paths.sh resolves each one by globbing the installed PDK, anchored on the
# single routing tech LEF whose own filename carries the metal stack — so the
# stack is read OUT of the PDK rather than typed into a public file, and every
# glob is exact-one-match-or-fail. Its header carries the full reasoning.
#
# THE VALUES ARE UNCHANGED. Each resolves byte-identically to the literal it
# replaced; `pdk_paths.sh --verify` re-proves that on demand. This is a
# redaction of the SPELLING, never of the SELECTION — a wrong deck or a wrong
# stream-out map changes what the GDS *is*, which is far worse than the
# disclosure being fixed.
#
# RESOLVED IN THIS FILE, NOT IN EACH CONSUMER, so the Innovus flow, the DRC
# flow, the LVS flow and the KLayout deck generator cannot drift onto different
# foundry collateral from each other — a class of bug that reads as clean on
# both sides right up until the GDS is wrong.
PDK_PATHS_SH := $(NANOSOC_ETH_CHIPLET_HOME)/ASIC/tech_wrappers/tsmc65/scripts/pdk_paths.sh

# Resolve $(1) from key $(2), but only if it is not already set: an explicit
# environment or command-line value still wins, exactly as the `?=` it replaces.
#
# THE ROOTS ARE PASSED EXPLICITLY, AND MUST BE. `export` in a makefile puts a
# variable into the environment of RECIPE commands only — GNU make does NOT put
# it into the environment of a `$(shell ...)` expanded while the makefile is
# being read. Relying on the `export` above would hand pdk_paths.sh an empty
# TSMC_65_HOME, it would exit 1, `2>/dev/null` would swallow the reason, and
# every path below would silently become the empty string. Verified against GNU
# Make 4.2.1: a plain `$(shell echo $$FOO)` after `export FOO ?= ...` prints
# nothing. Do not "simplify" this by dropping the assignments.
#
# stderr is dropped only so that a host with no PDK (CI, a laptop) parses
# quietly; absence is a legitimate state there. It is NOT a pass — run
# `make pdk-paths` to see what actually resolved, and note the consumers below
# keep their own `test -r` guards for the empty case.
define pdk_resolve
  ifeq ($$(origin $(1)),undefined)
    export $(1) := $$(shell TSMC_65_HOME='$$(TSMC_65_HOME)' PHYS_IP='$$(PHYS_IP)' \
                            $$(PDK_PATHS_SH) $(2) 2>/dev/null)
  endif
endef

$(eval $(call pdk_resolve,PDK_TECH_LEF,tech-lef))
$(eval $(call pdk_resolve,PDK_GDSMAP,gdsout-map))
$(eval $(call pdk_resolve,PDK_DRC_DECK,drc-ruledeck))
$(eval $(call pdk_resolve,PDK_BASE_LEF,base-lef))
$(eval $(call pdk_resolve,PDK_IO_PAD_LEF,io-pad-lef))
$(eval $(call pdk_resolve,PDK_STDCELL_VLOG,stdcell-vlog))
$(eval $(call pdk_resolve,PDK_IO_VLOG,io-vlog))
$(eval $(call pdk_resolve,PDK_LVS_DECK,lvs-deck))
$(eval $(call pdk_resolve,PDK_LVS_SOURCE_ADDED,lvs-source-added))
$(eval $(call pdk_resolve,PDK_METAL_STACK,metal-stack))
$(eval $(call pdk_resolve,PDK_METAL_OPTION,metal-option))

## Prove the resolver still selects what the literals used to select.
.PHONY: pdk-paths
pdk-paths:
	@$(PDK_PATHS_SH) --verify

# ── ASIC flow toolkit root ─────────────────────────────────────────────────
# The Innovus stage scripts (2_pnr_setup / 3_pnr_clock / 4_pnr_route) do
# `source $env(SOCLABS_ASIC_FLOW_DIR)/Cadence/procs.tcl` internally, so passing
# them by path with `innovus -f` is NOT enough — without this export stage 2
# aborts on the very first source. Nothing else in the repo sets it.
export SOCLABS_ASIC_FLOW_DIR ?= $(NANOSOC_ETH_CHIPLET_HOME)/ASIC/asic-flows

# ── Target module ──────────────────────────────────────────────────────────
export MODULE ?= nanosoc_multicore_soc

# ── Module-to-top mapping ──────────────────────────────────────────────────
# Flist basename maps to elaboration top module name. Where the flist name
# matches the top module the mapping is redundant, but kept for clarity.
TOP_nanosoc_multicore       = nanosoc_multicore_soc
TOP_nanosoc_multicore_soc   = nanosoc_multicore_soc
TOP_ethmac_subsystem_apb    = ethmac_subsystem_apb
TOP_phc_ahb                 = phc_ahb
TOP_top_ahb_qspi            = top_ahb_qspi
TOP_sldma230                = sldma230
export TOP := $(or $(TOP_$(MODULE)),$(MODULE))

# ── File lists ─────────────────────────────────────────────────────────────
# Use ASIC-specific flist if it exists (swaps FPGA SRAM for compiled macro),
# otherwise fall back to the generic flist.
ASIC_FLIST_PATH := $(NANOSOC_MULTICORE_HOME)/flist/$(MODULE)_asic.flist
export FLIST := $(if $(wildcard $(ASIC_FLIST_PATH)),$(ASIC_FLIST_PATH),$(NANOSOC_MULTICORE_HOME)/flist/$(MODULE).flist)
# Top-level ASIC flist (full SoC with compiled memories)
export ASIC_FLIST := $(NANOSOC_ETH_CHIPLET_HOME)/flist/nanosoc_eth_chiplet_asic.flist

# ── Cell libraries (TSMC 65nm — matches tidelink) ──────────────────────────
# Target library (.db) — used for mapping and optimization.
# Resolved, not spelled: the Arm RELEASE directory under sc12_base_rvt is
# purchase information. Exactly one is installed, so the glob selects the same
# tree the hardcoded release code did. The .db BASENAME is kept — it carries no
# revision, only the public library/variant/corner spelling.
$(eval $(call pdk_resolve,TARGET_LIB,arm-target-lib))

# ── Memory macro libraries (compiled register file) ────────────────────────
# TODO: confirm memory macro sizing for IMEM (64 KB), DMEM (16 KB), BOOTROM (8 KB)
# and eth scratch SRAMs (16 KB each). Current default uses the 16 KB RF macro.
export MEM_PATH       ?= /research/precompiled_mems/TSMC65/rf_16k
# The library ROOT, DERIVED from MEM_PATH rather than spelled a second time, so
# this file names that mount exactly once. config.tcl reads MEM_LIB_ROOT for its
# six macro directories instead of respelling the site path six times over.
export MEM_LIB_ROOT   ?= $(patsubst %/,%,$(dir $(MEM_PATH)))
export MEM_DB_SS      ?= $(MEM_PATH)/rf_16k_ss_1p08v_1p08v_125c.db
export MEM_DB_FF      ?= $(MEM_PATH)/rf_16k_ff_1p32v_1p32v_m40c.db

# Link libraries — target + any additional macro/IP libs
export LINK_LIBS      ?= $(TARGET_LIB) $(MEM_DB_SS)

# TF/Milkyway — physical reference for floorplan estimation.
# Derived from PHYS_IP rather than respelling the mount. `cln65lp` is a public
# process-family spelling and carries no revision, so it stays.
export PHYS_IP_PATH   ?= $(PHYS_IP)/arm/tsmc/cln65lp

# Standard cell Verilog simulation models (for gate-level simulation), and the
# Milkyway physical references. Each resolves the Arm RELEASE directory by glob
# instead of naming it. The Milkyway METAL OPTION is not derivable — six ship
# side by side — so it lives in ARM_MILKYWAY_STACK inside pdk_paths.sh, flagged
# there as a maintainer decision. Nothing in this project currently consumes
# TF_FILE or MW_REF_LIB: they feed a Synopsys flow this repository does not run.
$(eval $(call pdk_resolve,STDCELL_VERILOG,arm-stdcell-verilog-dir))
$(eval $(call pdk_resolve,TF_FILE,arm-tf-file))
$(eval $(call pdk_resolve,MW_REF_LIB,arm-mw-ref-lib))

# ── RTLA Reference Methodology ────────────────────────────────────────────
# EDA_TOOLS_ROOT is a named site mount for the same reason the others are. The
# RTLA-RM release directory is globbed: a tool VERSION is the same
# inventory-shaped disclosure as a PDK revision, and this file's own policy note
# above says an EDA install root should not be spelled out.
export EDA_RESEARCH_ROOT ?= /research/synopsys
export RTLA_RM_PATH   ?= $(firstword $(wildcard $(EDA_RESEARCH_ROOT)/RTLA-RM_*))

# ── Multi-corner .db libraries (for RTLA CLIB on-the-fly creation) ────────
$(eval $(call pdk_resolve,DB_PATH,arm-db-dir))
export DB_SS          ?= $(DB_PATH)/sc12_cln65lp_base_rvt_ss_typical_max_1p08v_125c.db
export DB_FF          ?= $(DB_PATH)/sc12_cln65lp_base_rvt_ff_typical_min_1p32v_m40c.db

# ── TLU+ parasitic extraction models ──────────────────────────────────────
# Release directory globbed; the metal option is ARM_MILKYWAY_STACK inside
# pdk_paths.sh, flagged there as a maintainer decision.
$(eval $(call pdk_resolve,TLUPLUS_PATH,arm-tluplus-dir))
export TLUPLUS_MAP    ?= $(TLUPLUS_PATH)/tluplus.map

# ── Design constraints ────────────────────────────────────────────────────
# THIS DESIGN RUNS AT 100 MHz. CLK_PERIOD below is 10.0 ns.
#
# This comment previously read "4 ns period (250 MHz) — matches tidelink",
# which contradicted the export 13 lines below it and was wrong about this
# design. Verified three ways before correcting it:
#   ASIC/common.mk:183                     export CLK_PERIOD ?= 10.0
#   inputs/constraints.sdc:19              set EXTCLK_PERIOD $::env(CLK_PERIOD)
#   the elaborated SDC of the last full run (runs/20260813T231658Z_fullrun-
#   scratch-padfix/outputs/*_syn.sdc:17)   create_clock -period 10.0 ... CLK
#
# WHERE THE 250 MHz CAME FROM, so nobody "restores" it: 4 ns is TideLink's
# OWN standalone SDC (tidelink/syn/asic/fusion-compiler/inputs/constraints.sdc,
# set T_UI_NS 4.0), which this chiplet flow does not use. It is that block's
# target in isolation, never this chip's operating point.
#
# WHY IT MATTERED: at 100 MHz there is 2.5x margin to the CDCM61001's LVCMOS
# fOUT ceiling, and every timing number in docs/tapeout is a 10 ns number.
# Anyone sizing margin against a believed 250 MHz would have been out by 2.5x.
#
# NOTE the D2D link rate inherits this variable too — inputs/tidelink_constraints.sdc
# does `set D2D_LINK_PERIOD $EXTCLK_PERIOD` — so a sweep here silently retargets
# the die-to-die link as well. See that file's header.
#
# Primary clock/reset are MODULE-dependent. The SoC top's free-running
# clock is sys_fclk and its async reset is sys_sysresetn (hclk/hresetn are
# internal/output nets on the top, NOT input ports — a create_clock on
# hclk would find no port). Per-block synthesis targets keep hclk/hresetn.
ifeq ($(filter $(MODULE),nanosoc_multicore nanosoc_multicore_soc),)
export CLK_NAME        ?= hclk
export RST_NAME        ?= hresetn
else
export CLK_NAME        ?= sys_fclk
export RST_NAME        ?= sys_sysresetn
endif
export CLK_PERIOD      ?= 10.0
export CLK_UNCERTAINTY ?= 0.35

# ── Available modules ─────────────────────────────────────────────────────
# MODULE=<name> selects the flist and TOP module. The full-SoC default is
# nanosoc_multicore_soc; the others are per-block synthesis targets.
MODULES = nanosoc_multicore nanosoc_multicore_soc ethmac_subsystem_apb phc_ahb top_ahb_qspi sldma230

#=============================================================================
# soclabs-asic-flow toolkit contract (Fusion Compiler flat flow)
#=============================================================================
# Design-scoped variables consumed by the toolkit (syn/asic/_flow). These
# are plain data vars — safe to define here for the shared DC/RTLA flows,
# which ignore them. The toolkit itself is included by the per-flow Makefile
# (syn/asic/fusion-compiler/Makefile), NOT here, so DC/RTLA Makefiles that
# `include ../common.mk` do not pick up the toolkit's stage targets.

# Filelist contract: the toolkit reads FLIST_ASIC (and FLIST_SIM); reuse the
# project's ASIC_FLIST (the fpga->asic memory-swap overlay flist).
export FLIST_ASIC := $(ASIC_FLIST)
export FLIST_SIM  ?= $(ASIC_FLIST)

# Block-handoff / macro mode + sc12 (ARM cln65lp RVT) PDK pack.
export DESIGN_MODE ?= macro
export PDK_PACK    ?= sc12

# ── Memory macro libraries (TSMC65 precompiled mems) ───────────────────────
# Flat SoC hardens the rf_* macros the asic_lib sl_sram binding selects by
# RAM_ADDR_W (see flist/nanosoc_multicore_asic.flist + sl_sram.v):
#   rf_08k (AW=13,  8 KB): CPU1 DMEM + shared cross-core SRAM
#   rf_16k (AW=14, 16 KB): CPU1 IMEM + eth DMEM + eth scratch RX/TX
#   rf_32k (AW=15, 32 KB): eth (CPU0) IMEM
# (CPU1 IMEM/DMEM were rf_32k/rf_32k before the 2026-07-04 reduction to the
# measured firmware demand; rf_08k is added here for CPU1 DMEM + the shared
# SRAM, which already selected rf_08k. The old comment's "eth IMEM -> rf_16k"
# was stale — eth IMEM is AW=15 -> rf_32k.) Each ships ss + ff .db so the FC
# fast scenario (scen_fast) works out of the box.
export MEM_BASE   ?= /research/precompiled_mems/TSMC65

MEM_RF08K_DB_SS := $(MEM_BASE)/rf_08k/rf_08k_ss_1p08v_1p08v_125c.db
MEM_RF08K_DB_FF := $(MEM_BASE)/rf_08k/rf_08k_ff_1p32v_1p32v_m40c.db
MEM_RF16K_DB_SS := $(MEM_BASE)/rf_16k/rf_16k_ss_1p08v_1p08v_125c.db
MEM_RF16K_DB_FF := $(MEM_BASE)/rf_16k/rf_16k_ff_1p32v_1p32v_m40c.db
MEM_RF32K_DB_SS := $(MEM_BASE)/rf_32k/rf_32k_ss_1p08v_1p08v_125c.db
MEM_RF32K_DB_FF := $(MEM_BASE)/rf_32k/rf_32k_ff_1p32v_1p32v_m40c.db

export MEM_LEFS    := $(MEM_BASE)/rf_08k/rf_08k.lef $(MEM_BASE)/rf_16k/rf_16k.lef $(MEM_BASE)/rf_32k/rf_32k.lef
export MEM_DBS_SS  := $(strip $(wildcard $(MEM_RF08K_DB_SS)) $(wildcard $(MEM_RF16K_DB_SS)) $(wildcard $(MEM_RF32K_DB_SS)))
export MEM_DBS_FF  := $(strip $(wildcard $(MEM_RF08K_DB_FF)) $(wildcard $(MEM_RF16K_DB_FF)) $(wildcard $(MEM_RF32K_DB_FF)))
GDS_MEM_FILES      := $(MEM_BASE)/rf_08k/rf_08k.gds2 $(MEM_BASE)/rf_16k/rf_16k.gds2 $(MEM_BASE)/rf_32k/rf_32k.gds2

# ── Flat floorplan — generous starting die (2 CPUs + ethernet SS + 6 macros
#    + interconnect). Tune after the first fc_init place. ────────────────────
export FC_DIE_WIDTH   ?= 3000
export FC_DIE_HEIGHT  ?= 3000
export FC_CORE_OFFSET ?= 10

# ── Arm memory compiler (ROM/RF .lib/.lef/.db generators) ───────────────────
# Overridable so a site/EDA-host export wins.
#
# The shared tree is COMPLETE and the compiler RUNS on this host. Two earlier
# notes here were wrong and each sent people down a dead end; both are corrected
# below, and the correction is measured, not argued.
#
# WRONG #1: "the /research copy is view-less". It is not. r0p0/views holds every
# generator and its .info, byte-for-byte identical to the copy inside the
# per-user arm_tsmc65_memcomp.tar.gz (diff -rq: no differences).
#
# WRONG #2: "it fails everywhere, including on local disk, so this is an OS
# regression for the PIP admin and cannot be fixed in the project tree." It is
# not an OS regression, and it IS fixable here. Measured 2026-08-14, srv03335,
# RHEL 8.10, same binaries, same bytes:
#     compiler run straight out of /research  -> "Available generators are:" EMPTY
#     same tree copied to local disk, re-run  -> 15 generators, no warnings
#
# The difference is the FILESYSTEM, not the install. /research is NFS (Isilon)
# and hands out inode numbers around 1.8e10; local xfs here is about 2.4e9. The
# compiler enumerates its own data directory from a 32-bit helper binary, whose
# non-LFS readdir() cannot represent an inode >= 2^32 and fails the directory
# scan outright (EOVERFLOW). The compiler sees zero views, therefore zero
# generators, therefore emits nothing. It is the classic 32-bit-binary-on-a
# -big-inode-filesystem failure and it has nothing to do with 8.8 -> 8.10, the
# JRE, licensing, or missing packages (ksh, glibc.i686 and ld-linux.so.2 are all
# present and every helper resolves cleanly under ldd).
#
# So: MEM_COMPILER_DIR names the AUTHORITATIVE shared install (read-only, never
# written), and the flow MIRRORS it to local disk before invoking it. Do not
# "fix" this by pointing at somebody's home directory: the previous default,
# /home/dwn1c21/SoC-Labs/phys_ip, has no arm/tsmc/cln65lp/ subtree at all, so
# $(ROM_COMPILER) resolved to a file that does not exist.
MEM_COMPILER_DIR ?= $(PHYS_IP)

# Local-disk mirror of the compiler. Required — see above. Must NOT be on
# /research or any other NFS mount. Cheap to keep: ~90 MB, and rsync makes the
# refresh a no-op once populated.
ROM_COMPILER_LOCAL ?= $(if $(TMPDIR),$(TMPDIR),/tmp)/armmemcomp-$(USER)
# RELATIVE on purpose - it is joined onto both MEM_COMPILER_DIR and the local
# rsync copy below. The Arm release directory is globbed, not spelled.
$(eval $(call pdk_resolve,ROM_COMPILER_REL,arm-rom-compiler-rel))
# Likewise for the register-file compiler used by the mem targets.
$(eval $(call pdk_resolve,RF_COMPILER_REL,arm-rf-compiler-rel))
ROM_COMPILER_SRC   := $(MEM_COMPILER_DIR)/$(ROM_COMPILER_REL)

ROM_65nm_SPEC_FILE :=

# ── ROM-lib generation, made turn-key for an EDA host ───────────────────────
#   make -f ASIC/common.mk tsmc_65_romlibs
# It mirrors the compiler to local disk, regenerates the eth code_file,
# preflight-checks everything, compiles both ROM libs into ASIC/romlibs/, and
# then verifies the compiled contents against the firmware before it will claim
# success. The shared install is only ever READ.
ROM_COMPILER  := $(ROM_COMPILER_LOCAL)/$(ROM_COMPILER_REL)/bin/rom_via_hdd_rvt_rvt
FW_BUILD_DIR  ?= $(NANOSOC_MULTICORE_HOME)/build/cmake/gcc-m0plus-le
BOOTROM_GEN   := $(SOCLABS_NANOSOC_ARCH_TECH_DIR)/firmware/testcodes/bootloader/bootrom_gen.py
ETH_ROM_DIR   := $(FW_BUILD_DIR)/firmware/bootloader/stage0_bootrom
CC_ROM_DIR    := $(FW_BUILD_DIR)/firmware/bootloader/stage0_bootrom_chip_core
ETH_HEX       := $(ETH_ROM_DIR)/stage0_bootrom.hex
ETH_BINTXT    := $(ETH_ROM_DIR)/eth_ss_bootrom.bintxt
CC_HEX        := $(CC_ROM_DIR)/stage0_bootrom_chip_core.hex
CC_BINTXT     := $(CC_ROM_DIR)/nanosoc_bootrom_chip_core.bintxt
# Specs come from THIS repo's tech_wrappers (byte-identical to the SoC
# submodule's copies today, but the chiplet owns its own pad/ROM collateral).
ETH_ROM_SPEC  := $(NANOSOC_ETH_CHIPLET_HOME)/ASIC/tech_wrappers/tsmc65/eth_rom.spec
CC_ROM_SPEC   := $(NANOSOC_ETH_CHIPLET_HOME)/ASIC/tech_wrappers/tsmc65/nanosoc_rom.spec

# Where the compiled ROM libs must LAND. This is not a free choice: it is the
# path genus-innovus/scripts/config.tcl adds to lib_search_path_list
# ($bootrom_dir / $eth_rom_dir) and reads $ROM_LIB / $ETH_ROM_LIB from. The
# recipe below used to write into $(NANOSOC_MULTICORE_HOME)/syn/asic/romlibs —
# a directory Genus never looks in — so even a successful ROM build left `syn`
# failing with the same "Cannot open file 'rom_via_ss_...lib'".
ROMLIBS_DIR   := $(NANOSOC_ETH_CHIPLET_HOME)/ASIC/romlibs

# Mirror the shared compiler onto local disk. NOT an optimisation — the compiler
# cannot enumerate its own views from NFS (see the MEM_COMPILER_DIR note), so a
# run straight out of $(MEM_COMPILER_DIR) silently produces nothing. rsync makes
# this a no-op once populated. The shared tree is the source and is never
# written; -L dereferences so the mirror is self-contained.
.PHONY: rom-compiler-stage
rom-compiler-stage:
	@test -d "$(ROM_COMPILER_SRC)" || { echo "FAIL: no ROM compiler at $(ROM_COMPILER_SRC)"; exit 1; }
	@mkdir -p $(ROM_COMPILER_LOCAL)/$(ROM_COMPILER_REL)
	@rsync -rlptL --delete "$(ROM_COMPILER_SRC)/" "$(ROM_COMPILER_LOCAL)/$(ROM_COMPILER_REL)/"
	@# The mirror is worthless if it landed somewhere with >=2^32 inodes, which is
	@# the exact failure being worked around. Refuse rather than emit junk.
	@bad=$$(find $(ROM_COMPILER_LOCAL)/$(ROM_COMPILER_REL)/views -maxdepth 1 -printf '%i\n' \
	        | awk '$$1 >= 4294967296' | head -1); \
	if [ -n "$$bad" ]; then \
	    echo "FAIL: $(ROM_COMPILER_LOCAL) is on a filesystem with 64-bit inode numbers."; \
	    echo "      The compiler's 32-bit helper cannot scan it and will report no generators."; \
	    echo "      Set ROM_COMPILER_LOCAL to a path on local disk."; exit 1; \
	fi
	@echo "OK: compiler mirrored to $(ROM_COMPILER_LOCAL)"

# Regenerate the ROM code_files from the already-built hex (deterministic; no
# cmake reconfigure). BOTH are regenerated, not just the eth one: the chip-core
# macro shipped stale precisely because nothing re-derived its code file, and a
# code file that is merely PRESENT is not a code file that is CURRENT.
# Writes only into the build tree — NOT src/rtl/bootrom/*.sv.
#
# ── REGENERATION IS CONTENT-PRESERVING, AND THAT IS LOAD-BEARING ────────────
#
# These targets used to write the .bintxt unconditionally, so every invocation
# gave the code file a NEW mtime whether or not the program had changed. That
# breaks the one piece of provenance these artefacts have.
#
# ASIC/romlibs is gitignored with no tracked files, so there is no VCS record of
# a ROM. rom_verify.py's `provenance` check therefore reasons from mtimes and
# from the compiler's internal creation stamp: a macro whose code file is NEWER
# than the macro was not built from that code file. That check is what caught
# two macros seven weeks older than their own firmware, and it must stay sharp.
#
# An unconditional rewrite makes it fire on correct artefacts — touch the code
# file and every previously-built ROM is retrospectively "stale" — which is both
# a false alarm and, worse, the kind of false alarm that gets a real check
# switched off. It also defeats any reuse of a previous build: ASIC/rom_build.mk
# treats a cache entry older than its code file as a miss, precisely so it never
# stages a macro that would fail provenance, so a spurious mtime bump costs a
# full recompile of both ROMs.
#
# So: generate into a temporary directory, compare, and replace the real file
# ONLY if the bytes differ. mtime then means what the checker assumes it means —
# when the contents last changed.
.PHONY: eth-bintxt cc-bintxt rom-bintxt

# $(1)=hex  $(2)=bintxt out  $(3)=sv out  $(4)=module name
define rom_bintxt_regen
	@test -f "$(1)" || { echo "FAIL: $(1) not built — build firmware first (make firmware)."; exit 1; }
	@# The result is REPORTED PER FILE, not as one verdict for both. The .bintxt
	@# is the code file the ROM is burned from; the .sv beside it is a byproduct
	@# that no ASIC stage reads. A shared "changed" flag makes a stale .sv report
	@# the CODE FILE as updated — alarming, wrong, and it hides the one line that
	@# matters.
	@tmp=$$(mktemp -d) || exit 1; trap 'rm -rf "$$tmp"' EXIT; \
	python3 $(BOOTROM_GEN) -i $(1) -a $(ROM_ADDR_BITS) -t gcc \
	    -v "$$tmp/$(4).sv" -b "$$tmp/$(4).bintxt" -m $(4) > "$$tmp/gen.log" 2>&1 \
	  || { echo "FAIL: bootrom_gen.py failed for $(4):"; cat "$$tmp/gen.log"; exit 1; }; \
	test -s "$$tmp/$(4).bintxt" || { \
	    echo "FAIL: bootrom_gen.py exited 0 and wrote no code file for $(4)."; \
	    cat "$$tmp/gen.log"; exit 1; }; \
	if cmp -s "$$tmp/$(4).bintxt" "$(2)"; then \
	    echo "OK: $(4) code file unchanged, mtime preserved ($$(wc -l < $(2)) words)"; \
	else \
	    cp "$$tmp/$(4).bintxt" "$(2)"; \
	    echo "OK: $(4) CODE FILE UPDATED — $(2) ($$(wc -l < $(2)) words)"; \
	fi; \
	if cmp -s "$$tmp/$(4).sv" "$(3)"; then :; else \
	    cp "$$tmp/$(4).sv" "$(3)"; \
	    echo "    (also refreshed the generated $(4).sv beside it — not read by any ASIC stage)"; \
	fi
endef

eth-bintxt:
	$(call rom_bintxt_regen,$(ETH_HEX),$(ETH_BINTXT),$(ETH_ROM_DIR)/eth_ss_bootrom.sv,eth_ss_bootrom)

cc-bintxt:
	$(call rom_bintxt_regen,$(CC_HEX),$(CC_BINTXT),$(CC_ROM_DIR)/nanosoc_bootrom_chip_core.sv,nanosoc_bootrom_chip_core)

rom-bintxt: eth-bintxt cc-bintxt

.PHONY: romlibs-preflight
romlibs-preflight:
	@echo "== ROM-lib preflight =="
	@test -x "$(ROM_COMPILER)" || { echo "FAIL: ROM compiler missing/not executable: $(ROM_COMPILER)"; exit 1; }
	@# Probe what the compiler can actually DO, rather than guessing from its
	@# path. A working install lists its generators; a broken one lists none and
	@# would otherwise fail later, silently leaving stale/absent .libs. See the
	@# MEM_COMPILER_DIR note above.
	@#
	@# THE GENERATOR NAMES ARE ON THE LINES AFTER THE HEADING, ONE PER LINE — not
	@# on the heading line. This check used to read them with
	@#     sed -n 's/^Available generators are: *//p'
	@# which returns the empty remainder of the heading, so it declared a PERFECTLY
	@# WORKING COMPILER broken and then explained the NFS-inode failure at length.
	@# Measured 2026-08-14: the local-disk mirror lists 15 generators and compiles
	@# both ROMs, while this gate refused to let it start. A false negative here is
	@# expensive in a specific way — it sends you to fix an install that is fine,
	@# and it is why `tsmc_65_romlibs` was believed unrunnable on this host.
	@gens=$$("$(ROM_COMPILER)" -help < /dev/null 2>/dev/null | awk '\
	    /Available generators are:/ { \
	        sub(/.*Available generators are:[[:space:]]*/, ""); \
	        f = 1; if ($$0 != "") print $$0; next } \
	    f { if ($$0 ~ /^[[:space:]]*$$/ || $$0 ~ /^(You can also|Options)/) exit; \
	        if ($$0 ~ /^[[:space:]]*[A-Za-z0-9_.-]+[[:space:]]*$$/) print $$1; else exit }' \
	    | tr '\n' ' '); \
	if [ -z "$$(echo $$gens | tr -d ' .')" ]; then \
	    echo "FAIL: $(ROM_COMPILER)"; \
	    echo "      starts but lists NO generators ('Available generators are: $$gens')."; \
	    echo "      It cannot emit a .lib, and would otherwise leave stale/absent libs."; \
	    echo "      This is almost always the filesystem, not the install: the compiler"; \
	    echo "      scans its own views/ from a 32-bit helper whose readdir() cannot"; \
	    echo "      represent an inode >= 2^32, so on NFS it sees no views and no"; \
	    echo "      generators. Check that ROM_COMPILER_LOCAL ($(ROM_COMPILER_LOCAL))"; \
	    echo "      is on LOCAL disk and re-run 'make rom-compiler-stage'."; \
	    exit 1; \
	fi; \
	echo "OK: generators   = $$gens"
	@test -f "$(ETH_BINTXT)" || { echo "FAIL: missing eth code_file $(ETH_BINTXT) (run: make -f common.mk eth-bintxt)"; exit 1; }
	@test -f "$(CC_BINTXT)"  || { echo "FAIL: missing cc code_file $(CC_BINTXT) (build firmware first)"; exit 1; }
	@test -f "$(ETH_ROM_SPEC)" || { echo "FAIL: missing spec $(ETH_ROM_SPEC)"; exit 1; }
	@test -f "$(CC_ROM_SPEC)"  || { echo "FAIL: missing spec $(CC_ROM_SPEC)"; exit 1; }
	@echo "OK: compiler      = $(ROM_COMPILER)"
	@echo "OK: eth code_file = $(ETH_BINTXT)"
	@echo "OK: cc  code_file = $(CC_BINTXT)"
	@# `test -f` above is not enough, and its insufficiency is the whole defect:
	@# handed an EMPTY, SHORT or MALFORMED code file the Arm ROM compiler does
	@# not fail — it substitutes contents and emits a well-formed macro that
	@# nothing downstream questions. rom_gate.mk's static checks are what refuse
	@# that, and they also refuse to rebuild from a spec whose depth disagrees
	@# with the macro already placed in the floorplan.
	@$(MAKE) -f $(COMMON_MK) --no-print-directory romlibs-verify-static

# ── WHY THIS RECIPE DOES NOT USE THE COMPILER'S `all` TARGET ────────────────
#
# `all` runs every generator, and one of them is `testcode`. `testcode` is the
# SYNTHETIC-PATTERN generator: -code_file is its OUTPUT, not its input. Run it
# and it overwrites the file you named with a pattern chosen by the spec's
# `mode` key. Measured 2026-08-14, both macros: after `all`, the firmware
# code_file in the build tree had been replaced (with zeros under mode=zeros;
# it would be random noise under the mode=random these specs used to carry).
#
# Worse than the collateral damage: generators are sequenced WITHIN `all`, so
# the ones that run after `testcode` read the clobbered file. That is the whole
# explanation for the five content views splitting into two families that share
# no data — masis/fastscan/logicvision/cdl/gds2 (before) hold the firmware,
# verilog/tmax (after) hold the substituted pattern. The Verilog model is the
# one every RTL simulation loads, so simulation and silicon ran different
# programs and nothing complained.
#
# So: enumerate the generators explicitly and never invoke `testcode`. The real
# code file is passed by its own path, not a copy — the macro records the name
# it was compiled from, and that stamp is how romlibs-verify proves the macro
# belongs to the firmware the spec names. A renamed copy defeats that check.
# The build snapshots the code file and fails if any generator wrote to it.
#
# ── WHERE THAT LOGIC NOW LIVES ─────────────────────────────────────────────
# All of it — the generator list, the never-`testcode` rule, the per-generator
# integrity guard — moved to scripts/ci/rom_cache.py, driven by rom_build.mk.
# There was a `rom_compile` shell macro here that did the same job; two
# implementations of "how to run the ROM compiler safely" is exactly one too
# many when the thing they protect against is a silent content substitution, so
# this file no longer carries its own. ROM_GENERATORS is defined once, in
# ASIC/rom_build.mk.

# `tsmc_65_romlibs` — the historical entry point, kept because docs, CI messages
# and muscle memory all name it. It now delegates to the per-run machinery with
# the run pointed at the LEGACY SHARED DIRECTORY, so it does what it always did
# while going through one build implementation, one cache and one gate.
#
# Prefer `rom-run ROM_RUN_DIR=<run>`: a macro in ASIC/romlibs is shared by every
# run in the checkout and can be replaced between two stages of the same flow,
# which is the property that let a wrong ROM survive months of synthesis.
tsmc_65_romlibs:
	@echo "note: tsmc_65_romlibs builds into the SHARED $(ROMLIBS_DIR)."
	@echo "      For a run that owns its ROMs: make -f common.mk rom-run ROM_RUN_DIR=<run>"
	@$(MAKE) -f $(COMMON_MK) --no-print-directory rom-run ROM_RUN_DIR=$(ROMLIBS_DIR)

# ── romlibs-verify lives in ASIC/rom_gate.mk (included at the end of this file)
# It used to be HERE, and it used to check only that four files existed and were
# non-empty. It passed every day while both compiled ROMs held contents that are
# not this firmware — eth_rom random, cc_rom a DIFFERENT PROGRAM (only ~135 of
# its 512 words coincide with the image its spec names). The name stayed; the
# body is now an exact, word-for-word comparison against the firmware code
# files. See ASIC/rom_gate.mk for what it asserts and why each assertion is
# there.


gen_memories: bootrom
	@mkdir -p $(MEMORIES_DIR)
	@mkdir -p $(RF_16K_DIR)
	@mkdir -p $(RF_08K_DIR)
	@mkdir -p $(ROM_DIR)
	cp $(BOOTROM_BIN_FILE_IN) $(BOOTROM_BIN_FILE)
	echo "Generating register file memory libraries"
	echo "16K RF"
	cd $(RF_16K_DIR); $(MEM_COMPILER_DIR)/$(RF_COMPILER_REL)/bin/rf_sp_hdf_hvt_rvt all -spec $(RF_16K_65nm_SPEC_FILE);
	cd $(RF_16K_DIR); $(MEM_COMPILER_DIR)/$(RF_COMPILER_REL)/bin/rf_sp_hdf_hvt_rvt liberty -spec $(RF_16K_65nm_SPEC_FILE);
	echo "8K RF"
	cd $(RF_08K_DIR); $(MEM_COMPILER_DIR)/$(RF_COMPILER_REL)/bin/rf_sp_hdf_hvt_rvt all -spec $(RF_08K_65nm_SPEC_FILE);
	cd $(RF_08K_DIR); $(MEM_COMPILER_DIR)/$(RF_COMPILER_REL)/bin/rf_sp_hdf_hvt_rvt liberty -spec $(RF_08K_65nm_SPEC_FILE);
	cd $(ROM_DIR)
	echo "Generating ROM Libraries"
	cd $(ROM_DIR); $(MEM_COMPILER_DIR)/$(ROM_COMPILER_REL)/bin/rom_via_hdd_rvt_rvt liberty -spec $(ROM_65nm_SPEC_FILE) -code_file $(BOOTROM_BIN_FILE);
	cd $(ROM_DIR); $(MEM_COMPILER_DIR)/$(ROM_COMPILER_REL)/bin/rom_via_hdd_rvt_rvt all -spec $(ROM_65nm_SPEC_FILE) -code_file $(BOOTROM_BIN_FILE);
	echo "Finished generating memory libraries"


# ── THE PATCHED IO-DRIVER LEF ───────────────────────────────────────────────
#
# WHY THIS IS GENERATED AND NOT COMMITTED.
#
# `tphn65lpgv2od3_sl_9lm.lef` is TSMC foundry collateral and this repository is
# PUBLIC. The tree used to carry a 414 kB copy of it at
# ASIC/tech_wrappers/tsmc65/local_overrides/ — a verbatim vendor file with three
# lines changed — which published vendor IP the licence does not permit us to
# reproduce. What is committed now is the TRANSFORM (scripts/patch_pad_lef.py:
# three lines of project-owned intent, plus the code to apply them); the vendor
# bytes are read from the read-only PDK at build time and land here, gitignored.
#
# Same problem and same shape of fix as the stream-out map — see
# genus-innovus/scripts/gdsmap_derive.py and its `gdsmap` target.
#
# WHY IT LIVES IN common.mk RATHER THAN IN ONE FLOW'S Makefile: BOTH flows read
# it. genus-innovus/scripts/config.tcl sets IO_PAD_DRIVER_LEF from it, and
# eth-chiplet/design.mk exports it as TSMC65_IO_DRIVER_LEF for the toolkit tech
# pack. Generating it into either flow's work/ would make the other flow depend
# on that flow's build tree. So it goes in a flow-neutral generated directory,
# reached through NANOSOC_ETH_CHIPLET_HOME exactly as ASIC/romlibs is.
#
# The patch itself is a vendor defect workaround: three supply pads declare
# their supply pin with no `USE POWER ;` / `USE GROUND ;`, so Innovus will not
# match them with `connect_global_net -type pg_pin`, the VDDIO/VSSIO special
# nets stay empty, and the router threads the IO supplies around the periphery
# as ordinary signal nets. 76 DRC records on the 2026-08 reference run. The
# script's docstring carries the full argument.
PAD_LEF_GEN_DIR := $(NANOSOC_ETH_CHIPLET_HOME)/ASIC/tech_wrappers/tsmc65/generated
PAD_LEF         := $(PAD_LEF_GEN_DIR)/tphn65lpgv2od3_sl_9lm.patched.lef
PAD_LEF_GEN     := $(NANOSOC_ETH_CHIPLET_HOME)/ASIC/tech_wrappers/tsmc65/scripts/patch_pad_lef.py

## make pad-lef — regenerate the patched IO-driver LEF from the read-only PDK.
## Idempotent and cheap (no licence, ~0.01s): safe to hang off every stage.
##
## It also restores a symlink at the file's OLD committed path. That is a
## compatibility shim for ARCHIVED INNOVUS DATABASES, and it is load-bearing:
## a saved database populates its own libs/lef/ with ABSOLUTE symlinks into the
## project tree, and 78 saved databases under ASIC/genus-innovus/runs/ and
## ASIC/eth-chiplet/build/ point at local_overrides/. Without the shim every one
## of them fails to open --
##     ERROR (IMPIMEX-7023): The file .../libs/lef/tphn65lpgv2od3_sl_9lm.lef
##     inside the saved design directory was deleted.
## -- which kills re-streaming, ECOs and any re-check of work already done. The
## same trap is recorded for the mmmc symlinks in docs/tapeout/26 s5.
##
## A SYMLINK, not a copy: one source of truth, so the shim cannot drift from the
## generated file. Both paths are gitignored, so no vendor bytes reach the index.
PAD_LEF_COMPAT := $(NANOSOC_ETH_CHIPLET_HOME)/ASIC/tech_wrappers/tsmc65/local_overrides/tphn65lpgv2od3_sl_9lm.lef
.PHONY: pad-lef
pad-lef:
	@python3 $(PAD_LEF_GEN) -o $(PAD_LEF)
	@mkdir -p $(dir $(PAD_LEF_COMPAT))
	@ln -sfn $(PAD_LEF) $(PAD_LEF_COMPAT)
	@test -e $(PAD_LEF_COMPAT) || { \
	  echo "pad-lef: FAILED to restore the archived-database compatibility link"; \
	  echo "         at $(PAD_LEF_COMPAT) -- saved databases will not open."; \
	  exit 1; }

## make pad-lef-verify — the acceptance test. Proves the transform still
## reproduces the exact file it replaced, without writing anything. This is what
## catches a PDK bump changing the LEF under us: the script pins BOTH the vendor
## input's SHA-256 and the patched output's, and fails rather than absorbing a
## change silently.
.PHONY: pad-lef-verify
pad-lef-verify:
	@python3 $(PAD_LEF_GEN) -o $(PAD_LEF) --check || exit 1
	@python3 $(PAD_LEF_GEN) --print-delta

# ── ROM content verification ───────────────────────────────────────────────
# romlibs-verify / romlibs-verify-static / romlibs-verify-content /
# romlibs-verify-gds / romlibs-selftest. Kept in its own fragment because it is
# the one part of this file with real logic in it, and because it is the part
# that STAYS project-side when the flow moves to the asic-toolkit (the toolkit
# owns stage scripts; ROM generation and its verification do not move).
#
# LAST, deliberately: it reads ROMLIBS_DIR, ETH_BINTXT, CC_BINTXT and the two
# spec paths defined above. Anything that re-enters this makefile from a recipe
# must use $(COMMON_MK) — see the note beside its definition at the top.
include $(dir $(COMMON_MK))rom_gate.mk

# ── Per-run ROM generation ─────────────────────────────────────────────────
# rom-run / rom-run-stage / rom-run-status / rom-cache-clean. AFTER rom_gate.mk
# because it consumes that file's ROM table ($(ROMS), ROM_LABEL_*, ROM_SPEC_*,
# ROM_CODE_*, ROM_INST_*) — one description of which ROMs this die has, used
# both to build them and to judge them. It also drives the gate, pointed at the
# run it has just populated.
include $(dir $(COMMON_MK))rom_build.mk
