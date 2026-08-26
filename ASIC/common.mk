#-----------------------------------------------------------------------------
# ASIC/common.mk — shared environment for every ASIC flow in this repo
# A joint work commissioned on behalf of SoC Labs, under Arm Academic
# Access license.
#
# Contributors
#
# David Mapstone (d.a.mapstone@soton.ac.uk)
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# Included by ASIC/eth-chiplet/design.mk (the toolkit flow that builds the chip)
# and by ASIC/genus-innovus/Makefile (the frozen legacy flow). It declares no
# implementation stage: it resolves paths, exports the environment the flists
# and Tcl scripts dereference, and includes the two ROM fragments at the end.
#
# THIS IS WHERE A PROJECT CONSTANT GOES — clock period, die size, memory macros,
# library and PDK roots, ROM specs.
#
# Everything is `?=`, and that is load-bearing: a sourced set_env.sh, a site
# export or a command-line assignment must win. A `:=` here overrides a correct
# environment and silently retargets every derived path below at a directory
# that merely happens to exist, so nothing fails loudly.
CHIPLET_HOME_DEFAULT := $(realpath $(dir $(lastword $(MAKEFILE_LIST)))/..)
export NANOSOC_ETH_CHIPLET_HOME ?= $(CHIPLET_HOME_DEFAULT)

# This file's own absolute path, captured before any include below can move
# $(lastword $(MAKEFILE_LIST)) off it. A recipe that re-enters this makefile
# MUST use $(COMMON_MK): $(lastword ...) is expanded when the RECIPE runs, by
# which time it names whichever file was included last, and the re-entry lands
# in the wrong makefile.
COMMON_MK := $(abspath $(lastword $(MAKEFILE_LIST)))
export NANOSOC_MULTICORE_HOME   ?= $(NANOSOC_ETH_CHIPLET_HOME)/nanosoc-multicore-system

# ── DESIGN_HOME: the design-agnostic spelling of "the repo root" ────────────
# The same directory as NANOSOC_ETH_CHIPLET_HOME under a name a second chiplet
# can reuse unchanged, so portable Tcl (config.tcl, pnr_utils.tcl, the stage
# scripts) never has to name this design.
#
# BOTH NAMES STAY LIVE: every Tcl call site resolves DESIGN_HOME first and falls
# back to NANOSOC_ETH_CHIPLET_HOME, so a shell that sourced set_env.sh — which
# exports only the old name — still runs. Drop the fallback only once set_env.sh
# exports DESIGN_HOME too.
export DESIGN_HOME ?= $(NANOSOC_ETH_CHIPLET_HOME)

# ── Project / submodule / IP env (mirrors set_env.sh) ──────────────────────
# The flists reference these as ${VAR}, so exporting them here lets the ASIC
# flows resolve every RTL path WITHOUT `source set_env.sh` first. Derived from
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
# Cortex-M0+ processor IP. Both cores are full RTL in the base flist
# (logical/cortexm0plus/verilog/...); without this export the flist parser
# silently drops them when set_env.sh has not been sourced.
export ARM_CORTEXM0PLUS_IP_PATH  ?= $(ARM_IP_LIBRARY_PATH)/Cortex-M0-plus/AT590-BU-50000-r0p1-01rel1
export AHB_BRIDGES_HOME          ?= $(ETHMAC_AHB_HOME)/amba_wb_bridges
export PHC_AHB_HOME              ?= $(NANOSOC_MULTICORE_HOME)/ptp-hardware-clock-ahb
export PHC_HOME                  ?= $(PHC_AHB_HOME)
export AHB_QSPI_HOME             ?= $(NANOSOC_MULTICORE_HOME)/ahb_qspi
export SOCLABS_AHB_QSPI_DIR      ?= $(AHB_QSPI_HOME)
export IPC_MAILBOX_HOME          ?= $(NANOSOC_MULTICORE_HOME)/inter-processor-communications-ahb
# The two chiplet-level components. The ASIC flist -f-includes
# ${TIDECHART_HOME}/flist/tidechart.flist and the generated tidelink sub-flist
# is written entirely in ${TIDELINK_HOME} paths. Unset, Genus reads the whole
# SoC and only then dies at the END of read_flist.tcl — ~10 minutes in — with
# "Environment variable TIDELINK_HOME is not set", which reads like a link-stage
# fault rather than a missing export.
export TIDELINK_HOME             ?= $(NANOSOC_ETH_CHIPLET_HOME)/tidelink
export TIDECHART_HOME            ?= $(NANOSOC_ETH_CHIPLET_HOME)/tidechart

# ── CMSDK path ─────────────────────────────────────────────────────────────
# ARM Cortex-M System Design Kit (required for cmsdk_ahb_to_sram / AHB fabric)
export CMSDK_DIR ?= $(ARM_IP_LIBRARY_PATH)/BP210/BP210-BU-00000-r1p1-00rel0

# ── TSMC65 PDK roots (needed by genus-innovus/scripts/config.tcl) ───────────
# config.tcl reads $::env(TSMC_65_HOME) (TSMC staggered IO library + tcbn65lp
# standard-cell NLDM) and $::env(PHYS_IP) (Arm cln65lp sc12 base-cell LEF/DB).
# set_env.sh exports neither, so they are resolved here.
#   TSMC_65_HOME must be the GROUP-shared PDK mount: a per-user tree is readable
#   only to its own group, which excludes CI and most hosts. Every path config.tcl
#   builds off this root, plus the DRC ruledeck and GDS-out map, resolve under it.
#   PHYS_IP is the shared read-only Arm phys-IP library.
export TSMC_65_HOME ?= /tsmc65pdk/65
export PHYS_IP      ?= /research/AAA/phys_ip_library

# Which absolute prefixes scripts/ci/run_provenance.py records as EXTERNAL
# (read-only, hashed in place, never copied). Built from the variables above
# rather than respelled, so this file stays the single place naming a site mount
# and run_provenance.py — which is published — names none. Add a prefix here.
#
# The EDA install root is deliberately absent: a tool mount is the same
# inventory-shaped disclosure as a PDK mount. run_provenance.py falls through to
# repo_of() for any unrecognised path and returns "external" anyway, so these
# prefixes are a shortcut, not a requirement.
export PROVENANCE_EXTERNAL_PREFIXES ?= $(TSMC_65_HOME):$(PHYS_IP):$(ARM_IP_LIBRARY_PATH)

# ── Foundry collateral — RESOLVED HERE ONCE, SPELLED NOWHERE ───────────────
# Paths under the PDK end in a component naming the DECK REVISION and the IP
# RELEASE this site bought. The family spelling is public; the revision suffix is
# purchase information, and this repository is published.
#
# pdk_paths.sh resolves each one by globbing the installed PDK, anchored on the
# single routing tech LEF whose filename carries the metal stack — so the stack
# is read OUT of the PDK rather than typed into a public file — and every glob is
# exact-one-match-or-fail. `pdk_paths.sh --verify` re-proves that each resolves
# byte-identically to the literal it replaced.
#
# This is a redaction of the SPELLING, never of the SELECTION: a wrong deck or a
# wrong stream-out map changes what the GDS IS.
#
# RESOLVED IN THIS FILE, NOT IN EACH CONSUMER, so the Innovus, DRC, LVS and
# KLayout flows cannot drift onto different foundry collateral from one another —
# a class of bug that reads clean on both sides until the GDS is wrong.
PDK_PATHS_SH := $(NANOSOC_ETH_CHIPLET_HOME)/ASIC/tech_wrappers/tsmc65/scripts/pdk_paths.sh

# Resolve $(1) from key $(2), but only if it is not already set: an explicit
# environment or command-line value still wins, exactly as the `?=` it replaces.
#
# THE ROOTS ARE PASSED EXPLICITLY, AND MUST BE. `export` in a makefile only
# populates the environment of RECIPE commands; GNU make does NOT put it into
# the environment of a `$(shell ...)` expanded while the makefile is being read.
# Relying on the `export` above hands pdk_paths.sh an empty TSMC_65_HOME, it
# exits 1, `2>/dev/null` swallows the reason, and every path below silently
# becomes the empty string. Do not "simplify" by dropping the assignments.
#
# stderr is dropped only so a host with no PDK (CI, a laptop) parses quietly.
# That is not a pass — run `make pdk-paths` to see what resolved, and note the
# consumers below keep their own `test -r` guards for the empty case.
define pdk_resolve
  ifeq ($$(origin $(1)),undefined)
    export $(1) := $$(shell TSMC_65_HOME='$$(TSMC_65_HOME)' PHYS_IP='$$(PHYS_IP)' \
                            $$(PDK_PATHS_SH) $(2) 2>/dev/null)
  endif
endef

$(eval $(call pdk_resolve,PDK_TECH_LEF,tech-lef))
$(eval $(call pdk_resolve,PDK_GDSMAP,gdsout-map))
$(eval $(call pdk_resolve,PDK_DRC_DECK,drc-ruledeck))
$(eval $(call pdk_resolve,PDK_BND_DECK,bnd-ruledeck))
$(eval $(call pdk_resolve,PDK_ANT_DECK,ant-ruledeck))
$(eval $(call pdk_resolve,PDK_BASE_LEF,base-lef))
$(eval $(call pdk_resolve,PDK_IO_PAD_LEF,io-pad-lef))
$(eval $(call pdk_resolve,PDK_STDCELL_VLOG,stdcell-vlog))
$(eval $(call pdk_resolve,PDK_IO_VLOG,io-vlog))
$(eval $(call pdk_resolve,PDK_LVS_DECK,lvs-deck))
$(eval $(call pdk_resolve,PDK_LVS_SOURCE_ADDED,lvs-source-added))
$(eval $(call pdk_resolve,PDK_METAL_STACK,metal-stack))
$(eval $(call pdk_resolve,PDK_METAL_OPTION,metal-option))

## pdk-paths: prove the resolver still selects what the literals used to select.
.PHONY: pdk-paths
pdk-paths:
	@$(PDK_PATHS_SH) --verify

# ── ASIC flow toolkit root ─────────────────────────────────────────────────
# The Innovus stage scripts (2_pnr_setup / 3_pnr_clock / 4_pnr_route) source
# $env(SOCLABS_ASIC_FLOW_DIR)/Cadence/procs.tcl internally, so passing them by
# path with `innovus -f` is not enough: unset, stage 2 aborts on its first
# source. Nothing else in the repo sets it.
export SOCLABS_ASIC_FLOW_DIR ?= $(NANOSOC_ETH_CHIPLET_HOME)/ASIC/asic-flows

# ── Target module ──────────────────────────────────────────────────────────
export MODULE ?= nanosoc_multicore_soc

# ── Module-to-top mapping ──────────────────────────────────────────────────
# Flist basename -> elaboration top module. Kept even where the two match.
TOP_nanosoc_multicore       = nanosoc_multicore_soc
TOP_nanosoc_multicore_soc   = nanosoc_multicore_soc
TOP_ethmac_subsystem_apb    = ethmac_subsystem_apb
TOP_phc_ahb                 = phc_ahb
TOP_top_ahb_qspi            = top_ahb_qspi
TOP_sldma230                = sldma230
export TOP := $(or $(TOP_$(MODULE)),$(MODULE))

# ── File lists ─────────────────────────────────────────────────────────────
# Prefer the ASIC flist if one exists (it swaps the FPGA SRAM behavioural models
# for the compiled macros), else the generic flist.
ASIC_FLIST_PATH := $(NANOSOC_MULTICORE_HOME)/flist/$(MODULE)_asic.flist
export FLIST := $(if $(wildcard $(ASIC_FLIST_PATH)),$(ASIC_FLIST_PATH),$(NANOSOC_MULTICORE_HOME)/flist/$(MODULE).flist)
# Top-level ASIC flist (full SoC with compiled memories)
export ASIC_FLIST := $(NANOSOC_ETH_CHIPLET_HOME)/flist/nanosoc_eth_chiplet_asic.flist

# ── Cell libraries (TSMC 65nm — matches tidelink) ──────────────────────────
# Target library (.db) for mapping and optimisation. Resolved, not spelled: the
# Arm RELEASE directory under sc12_base_rvt is purchase information and exactly
# one is installed. The .db BASENAME stays — it carries only the public
# library/variant/corner spelling.
$(eval $(call pdk_resolve,TARGET_LIB,arm-target-lib))

# ── Memory macro libraries (compiled register file) ────────────────────────
# TODO: confirm macro sizing for IMEM (64 KB), DMEM (16 KB), BOOTROM (8 KB) and
# the eth scratch SRAMs (16 KB each). The default below is the 16 KB RF macro.
export MEM_PATH       ?= /research/precompiled_mems/TSMC65/rf_16k
# The library ROOT, DERIVED from MEM_PATH so this file names that mount once.
# config.tcl reads MEM_LIB_ROOT for its six macro directories.
export MEM_LIB_ROOT   ?= $(patsubst %/,%,$(dir $(MEM_PATH)))
export MEM_DB_SS      ?= $(MEM_PATH)/rf_16k_ss_1p08v_1p08v_125c.db
export MEM_DB_FF      ?= $(MEM_PATH)/rf_16k_ff_1p32v_1p32v_m40c.db

# Link libraries — target + any additional macro/IP libs
export LINK_LIBS      ?= $(TARGET_LIB) $(MEM_DB_SS)

# TF/Milkyway physical reference for floorplan estimation. Derived from PHYS_IP
# rather than respelling the mount; `cln65lp` is a public process-family name.
export PHYS_IP_PATH   ?= $(PHYS_IP)/arm/tsmc/cln65lp

# Standard-cell Verilog simulation models (gate-level sim) and the Milkyway
# physical references. Each globs the Arm RELEASE directory instead of naming
# it. The Milkyway METAL OPTION is not derivable — six ship side by side — so it
# is ARM_MILKYWAY_STACK inside pdk_paths.sh, flagged there as a maintainer
# decision. Nothing in this project consumes TF_FILE or MW_REF_LIB: they feed a
# Synopsys flow this repository does not run.
$(eval $(call pdk_resolve,STDCELL_VERILOG,arm-stdcell-verilog-dir))
$(eval $(call pdk_resolve,TF_FILE,arm-tf-file))
$(eval $(call pdk_resolve,MW_REF_LIB,arm-mw-ref-lib))

# ── RTLA Reference Methodology ────────────────────────────────────────────
# EDA_TOOLS_ROOT is a named site mount for the same reason the PDK roots are,
# and the RTLA-RM release directory is globbed: a tool VERSION is the same
# inventory-shaped disclosure as a PDK revision.
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
# THIS DESIGN RUNS AT 100 MHz — CLK_PERIOD is 10.0 ns, and every timing number
# in docs/tapeout is a 10 ns number. TideLink's own standalone SDC targets 4 ns
# (250 MHz) in isolation; that flow is not used here, so do not import it.
#
# The D2D link rate INHERITS this variable: inputs/tidelink_constraints.sdc does
# `set D2D_LINK_PERIOD $EXTCLK_PERIOD`, so changing CLK_PERIOD silently
# retargets the die-to-die link as well.
#
# Primary clock/reset are MODULE-dependent. The SoC top's free-running clock is
# sys_fclk and its async reset sys_sysresetn; hclk/hresetn are internal or output
# nets there, NOT input ports, so a create_clock on hclk would find no port.
# Per-block synthesis targets keep hclk/hresetn.
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
# nanosoc_multicore_soc; the rest are per-block synthesis targets.
MODULES = nanosoc_multicore nanosoc_multicore_soc ethmac_subsystem_apb phc_ahb top_ahb_qspi sldma230

#=============================================================================
# soclabs-asic-flow toolkit contract (Fusion Compiler flat flow)
#=============================================================================
# Design-scoped variables the toolkit consumes (syn/asic/_flow). Plain data, so
# they are safe here for the shared DC/RTLA flows, which ignore them. The
# toolkit itself is included by syn/asic/fusion-compiler/Makefile, NOT here, so
# a DC/RTLA Makefile that includes this file does not inherit its stage targets.

# Filelist contract: the toolkit reads FLIST_ASIC (and FLIST_SIM); reuse the
# project's ASIC_FLIST, the fpga->asic memory-swap overlay flist.
# project's ASIC_FLIST (the fpga->asic memory-swap overlay flist).
export FLIST_ASIC := $(ASIC_FLIST)
export FLIST_SIM  ?= $(ASIC_FLIST)

# Block-handoff / macro mode + sc12 (ARM cln65lp RVT) PDK pack.
export DESIGN_MODE ?= macro
export PDK_PACK    ?= sc12

# ── Memory macro libraries (TSMC65 precompiled mems) ───────────────────────
# The flat SoC hardens the rf_* macros that the asic_lib sl_sram binding selects
# by RAM_ADDR_W (flist/nanosoc_multicore_asic.flist + sl_sram.v):
#   rf_08k (AW=13,  8 KB): CPU1 DMEM + shared cross-core SRAM
#   rf_16k (AW=14, 16 KB): CPU1 IMEM + eth DMEM + eth scratch RX/TX
#   rf_32k (AW=15, 32 KB): eth (CPU0) IMEM
# Each ships ss + ff .db so the FC fast scenario (scen_fast) works unmodified.
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
# MEM_COMPILER_DIR names the AUTHORITATIVE shared install, which is read-only
# and complete. THE FLOW MUST MIRROR IT TO LOCAL DISK BEFORE INVOKING IT — see
# rom-compiler-stage below.
#
# WHY: the compiler enumerates its own views/ directory from a 32-bit helper
# binary whose non-LFS readdir() cannot represent an inode >= 2^32. The shared
# tree is on NFS, which hands out inode numbers above that, so the scan fails
# with EOVERFLOW, the compiler sees zero views, reports zero generators and
# emits nothing — silently. The same bytes on local disk list 15 generators and
# compile both ROMs. It is a filesystem property, not a broken install, and not
# an OS, JRE, licence or missing-package problem.
#
# Do not "fix" this by pointing at a home directory: a tree without an
# arm/tsmc/cln65lp/ subtree makes $(ROM_COMPILER) a path that does not exist.
MEM_COMPILER_DIR ?= $(PHYS_IP)
# Local-disk mirror of the compiler. Required, not an optimisation — see above.
# Must NOT be on NFS. ~90 MB, and rsync makes the refresh a no-op once populated.
ROM_COMPILER_LOCAL ?= $(if $(TMPDIR),$(TMPDIR),/tmp)/armmemcomp-$(USER)
# RELATIVE on purpose: it is joined onto both MEM_COMPILER_DIR and the local
# rsync copy below. The Arm release directory is globbed, not spelled.
$(eval $(call pdk_resolve,ROM_COMPILER_REL,arm-rom-compiler-rel))
# Likewise for the register-file compiler used by the mem targets.
$(eval $(call pdk_resolve,RF_COMPILER_REL,arm-rf-compiler-rel))
ROM_COMPILER_SRC   := $(MEM_COMPILER_DIR)/$(ROM_COMPILER_REL)

ROM_65nm_SPEC_FILE :=
# ── ROM-lib generation, made turn-key for an EDA host ───────────────────────
#   make -f ASIC/common.mk tsmc_65_romlibs
# Mirrors the compiler to local disk, regenerates the eth code_file, preflights,
# compiles both ROM libs into ASIC/romlibs/, then verifies the compiled contents
# against the firmware before claiming success. The shared install is only READ.
ROM_COMPILER  := $(ROM_COMPILER_LOCAL)/$(ROM_COMPILER_REL)/bin/rom_via_hdd_rvt_rvt
FW_BUILD_DIR  ?= $(NANOSOC_MULTICORE_HOME)/build/cmake/gcc-m0plus-le
BOOTROM_GEN   := $(SOCLABS_NANOSOC_ARCH_TECH_DIR)/firmware/testcodes/bootloader/bootrom_gen.py
ETH_ROM_DIR   := $(FW_BUILD_DIR)/firmware/bootloader/stage0_bootrom
CC_ROM_DIR    := $(FW_BUILD_DIR)/firmware/bootloader/stage0_bootrom_chip_core
ETH_HEX       := $(ETH_ROM_DIR)/stage0_bootrom.hex
ETH_BINTXT    := $(ETH_ROM_DIR)/eth_ss_bootrom.bintxt
CC_HEX        := $(CC_ROM_DIR)/stage0_bootrom_chip_core.hex
CC_BINTXT     := $(CC_ROM_DIR)/nanosoc_bootrom_chip_core.bintxt
# Specs come from THIS repo's tech_wrappers — byte-identical to the SoC
# submodule's copies today, but the chiplet owns its own pad/ROM collateral.
ETH_ROM_SPEC  := $(NANOSOC_ETH_CHIPLET_HOME)/ASIC/tech_wrappers/tsmc65/eth_rom.spec
CC_ROM_SPEC   := $(NANOSOC_ETH_CHIPLET_HOME)/ASIC/tech_wrappers/tsmc65/nanosoc_rom.spec
# Where the compiled ROM libs must LAND. Not a free choice: this is the path
# genus-innovus/scripts/config.tcl adds to lib_search_path_list ($bootrom_dir /
# $eth_rom_dir) and reads $ROM_LIB / $ETH_ROM_LIB from. Build them anywhere else
# and `syn` still fails with "Cannot open file 'rom_via_ss_...lib'".
ROMLIBS_DIR   := $(NANOSOC_ETH_CHIPLET_HOME)/ASIC/romlibs

# Mirror the shared compiler onto local disk. NOT an optimisation — a run
# straight out of $(MEM_COMPILER_DIR) silently produces nothing (see the
# MEM_COMPILER_DIR note). rsync makes it a no-op once populated; the shared tree
# is the source and is never written, and -L dereferences so the mirror is
# self-contained.
.PHONY: rom-compiler-stage
rom-compiler-stage:
	@test -d "$(ROM_COMPILER_SRC)" || { echo "FAIL: no ROM compiler at $(ROM_COMPILER_SRC)"; exit 1; }
	@mkdir -p $(ROM_COMPILER_LOCAL)/$(ROM_COMPILER_REL)
	@rsync -rlptL --delete "$(ROM_COMPILER_SRC)/" "$(ROM_COMPILER_LOCAL)/$(ROM_COMPILER_REL)/"
	@# The mirror is worthless if it landed on a filesystem with >=2^32 inode
	@# numbers, which is the exact failure being worked around. Refuse, not emit junk.
	@bad=$$(find $(ROM_COMPILER_LOCAL)/$(ROM_COMPILER_REL)/views -maxdepth 1 -printf '%i\n' \
	        | awk '$$1 >= 4294967296' | head -1); \
	if [ -n "$$bad" ]; then \
	    echo "FAIL: $(ROM_COMPILER_LOCAL) is on a filesystem with 64-bit inode numbers."; \
	    echo "      The compiler's 32-bit helper cannot scan it and will report no generators."; \
	    echo "      Set ROM_COMPILER_LOCAL to a path on local disk."; exit 1; \
	fi
	@echo "OK: compiler mirrored to $(ROM_COMPILER_LOCAL)"

# Regenerate the ROM code_files from the already-built hex (deterministic; no
# cmake reconfigure). BOTH are regenerated: the chip-core macro shipped stale
# precisely because nothing re-derived its code file, and a code file that is
# merely PRESENT is not one that is CURRENT. Writes only into the build tree,
# never into src/rtl/bootrom/*.sv.
#
# REGENERATION IS CONTENT-PRESERVING, AND THAT IS LOAD-BEARING. ASIC/romlibs is
# gitignored with no tracked files, so a ROM has no VCS record and
# rom_verify.py's `provenance` check reasons from mtimes: a macro whose code file
# is NEWER than the macro was not built from that code file. An unconditional
# rewrite bumps the mtime on every invocation, so every previously-built ROM
# becomes retrospectively "stale" — a false alarm on correct artefacts, and the
# kind that gets a real check switched off. It also costs a full recompile,
# because rom_build.mk treats a cache entry older than its code file as a miss.
#
# So: generate into a temporary directory, compare, and replace the real file
# ONLY if the bytes differ.
.PHONY: eth-bintxt cc-bintxt rom-bintxt

# $(1)=hex  $(2)=bintxt out  $(3)=sv out  $(4)=module name
define rom_bintxt_regen
	@test -f "$(1)" || { echo "FAIL: $(1) not built — build firmware first: make -C $(NANOSOC_MULTICORE_HOME) firmware"; exit 1; }
	@# The result is REPORTED PER FILE. The .bintxt is the code file the ROM is
	@# burned from; the .sv beside it is a byproduct no ASIC stage reads. One
	@# shared "changed" flag would make a stale .sv report the CODE FILE as
	@# updated, hiding the only line that matters.
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

# --- the eth SIMULATION boot-ROM slot ----------------------------------------
# src/rtl/bootrom/eth_ss_bootrom.sv is a GITIGNORED MUTABLE SLOT (submodule
# .gitignore:179). The submodule materialises it from the tracked
# eth_ss_bootrom_default.sv via scripts/ensure_bootrom.sh, and submodule commit
# f4793b6 hooked that into the submodule's OWN set_env.sh, reasoning that
# set_env.sh is "the one thing EVERY flow sources".
#
# THAT PREMISE IS FALSE FOR THIS FLOW, and it is why a clean clone cannot pass
# the ROM gate. ../Makefile:59 states the opposing convention outright — "THE
# ENVIRONMENT IS ASSEMBLED IN THE RECIPES, not by one set_env.sh" — and this
# file re-derives everything itself. `make -C ASIC/eth-chiplet all` therefore
# sources no set_env.sh, the slot is never materialised, and the gate fails on a
# MISSING FILE while reporting it as wrong bits. `make elab` works in the same
# clean clone precisely because it DOES source set_env.sh.
#
# Idempotent, and it never overwrites an installed variant: install_bootrom.sh
# still owns which variant a simulation environment gets. This only guarantees
# the TRACKED DEFAULT is present when nothing has installed anything.
#
# Deliberately NOT `|| true` — set_env.sh:153 swallows a failed materialisation
# and that is how this stayed invisible.
BOOTROM_ENSURE ?= $(NANOSOC_MULTICORE_HOME)/scripts/ensure_bootrom.sh

.PHONY: bootrom-slot-ensure
bootrom-slot-ensure:
	@test -r "$(BOOTROM_ENSURE)" || { \
	    echo "FAIL: no $(BOOTROM_ENSURE)"; \
	    echo "      The sim boot-ROM slot is materialised from the tracked default by"; \
	    echo "      that script. Without it a fresh clone has no sim boot ROM."; \
	    echo "      Try: git submodule update --init nanosoc-multicore-system"; exit 1; }
	@bash "$(BOOTROM_ENSURE)"

.PHONY: romlibs-preflight
romlibs-preflight:
	@echo "== ROM-lib preflight =="
	@test -x "$(ROM_COMPILER)" || { echo "FAIL: ROM compiler missing/not executable: $(ROM_COMPILER)"; exit 1; }
	@# Probe what the compiler can DO rather than guessing from its path: a
	@# working install lists its generators, a broken one lists none and would
	@# otherwise fail later, silently leaving stale or absent .libs. See the
	@# MEM_COMPILER_DIR note above.
	@#
	@# THE GENERATOR NAMES ARE ON THE LINES AFTER THE HEADING, ONE PER LINE, not
	@# on the heading line itself. Parsing the heading's remainder returns the
	@# empty string and declares a perfectly working compiler broken.
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
	@# `test -f` above is not enough: handed an EMPTY, SHORT or MALFORMED code
	@# file the Arm ROM compiler does not fail — it substitutes contents and emits
	@# a well-formed macro nothing downstream questions. rom_gate.mk's static
	@# checks refuse that, and refuse to rebuild from a spec whose depth disagrees
	@# with the macro already placed in the floorplan.
	@$(MAKE) -f $(COMMON_MK) --no-print-directory romlibs-verify-static

# ── NEVER RUN THE COMPILER'S `all` TARGET ──────────────────────────────────
#
# `all` runs every generator, including `testcode` — the SYNTHETIC-PATTERN
# generator, for which -code_file is the OUTPUT, not the input. It overwrites the
# file you named with a pattern chosen by the spec's `mode` key, and because
# generators are sequenced within `all`, every generator after it reads the
# clobbered file. That is how the five content views split into two families
# sharing no data: masis/fastscan/logicvision/cdl/gds2 hold the firmware,
# verilog/tmax hold the substituted pattern. The Verilog model is the one every
# RTL simulation loads, so simulation and silicon ran different programs and
# nothing complained.
#
# So: enumerate the generators explicitly and never invoke `testcode`. Pass the
# real code file by its own path, not a copy — the macro records the name it was
# compiled from, and that stamp is how romlibs-verify proves the macro belongs to
# the firmware the spec names. The build snapshots the code file and fails if any
# generator wrote to it.
#
# All of that lives in scripts/ci/rom_cache.py, driven by rom_build.mk, which is
# also where ROM_GENERATORS is defined — once. Two implementations of "how to run
# the ROM compiler safely" is one too many when what they protect against is a
# silent content substitution.

# `tsmc_65_romlibs` — the historical entry point, kept because docs, CI messages
# and muscle memory name it. It delegates to the per-run machinery with the run
# pointed at the legacy SHARED directory, so it does what it always did through
# one build implementation, one cache and one gate.
#
# Prefer `rom-run ROM_RUN_DIR=<run>`: a macro in ASIC/romlibs is shared by every
# run in the checkout and can be replaced between two stages of one flow, which
# is the property that let a wrong ROM survive months of synthesis.
tsmc_65_romlibs:
	@echo "note: tsmc_65_romlibs builds into the SHARED $(ROMLIBS_DIR)."
	@echo "      For a run that owns its ROMs: make -f common.mk rom-run ROM_RUN_DIR=<run>"
	@$(MAKE) -f $(COMMON_MK) --no-print-directory rom-run ROM_RUN_DIR=$(ROMLIBS_DIR)

# ── romlibs-verify lives in ASIC/rom_gate.mk, included at the end of this file.
# It is an exact, word-for-word comparison of each compiled macro against the
# firmware code file. An existence-and-non-empty check is not enough: that
# version passed every day while both compiled ROMs held contents that were not
# this firmware. See ASIC/rom_gate.mk for what it asserts and why.


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
# GENERATED, NOT COMMITTED. `tphn65lpgv2od3_sl_9lm.lef` is TSMC foundry
# collateral and this repository is PUBLIC, so what is committed is the TRANSFORM
# (scripts/patch_pad_lef.py: three lines of project-owned intent plus the code to
# apply them). The vendor bytes are read from the read-only PDK at build time and
# land here, gitignored. Same shape of fix as the stream-out map — see
# genus-innovus/scripts/gdsmap_derive.py and its `gdsmap` target.
#
# IT LIVES IN common.mk BECAUSE BOTH FLOWS READ IT: genus-innovus/scripts/
# config.tcl sets IO_PAD_DRIVER_LEF from it and eth-chiplet/design.mk exports it
# as TSMC65_IO_DRIVER_LEF for the toolkit tech pack. Generating it into either
# flow's work/ would make the other flow depend on that flow's build tree, so it
# goes in a flow-neutral generated directory, like ASIC/romlibs.
#
# The patch is a vendor defect workaround: three supply pads declare their supply
# pin with no `USE POWER ;` / `USE GROUND ;`, so Innovus will not match them with
# `connect_global_net -type pg_pin`, the VDDIO/VSSIO special nets stay empty, and
# the router threads the IO supplies around the periphery as ordinary signal nets
# (76 DRC records on the 2026-08 reference run). The script's docstring carries
# the full argument.
PAD_LEF_GEN_DIR := $(NANOSOC_ETH_CHIPLET_HOME)/ASIC/tech_wrappers/tsmc65/generated
PAD_LEF         := $(PAD_LEF_GEN_DIR)/tphn65lpgv2od3_sl_9lm.patched.lef
PAD_LEF_GEN     := $(NANOSOC_ETH_CHIPLET_HOME)/ASIC/tech_wrappers/tsmc65/scripts/patch_pad_lef.py

## pad-lef: regenerate the patched IO-driver LEF from the read-only PDK.
## Idempotent and cheap — no licence, ~0.01 s — so it is safe to hang off any stage.
##
## It also restores a SYMLINK at the file's old committed path. That shim is
## load-bearing for ARCHIVED INNOVUS DATABASES: a saved database populates its
## libs/lef/ with ABSOLUTE symlinks into the project tree, and 78 saved databases
## under ASIC/genus-innovus/runs/ and ASIC/eth-chiplet/build/ point at
## local_overrides/. Without the shim each fails to open with
##     ERROR (IMPIMEX-7023): The file .../libs/lef/tphn65lpgv2od3_sl_9lm.lef
##     inside the saved design directory was deleted.
## killing re-streaming, ECOs and any re-check of finished work. The same trap is
## recorded for the mmmc symlinks in docs/tapeout/26 s5.
##
## A symlink and not a copy, so the shim cannot drift from the generated file.
## Both paths are gitignored, so no vendor bytes reach the index.
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

## pad-lef-verify: acceptance test for that transform — proves it still
## reproduces the exact file it replaced, writing nothing. This is what catches a
## PDK bump changing the LEF underneath: the script pins BOTH the vendor input's
## SHA-256 and the patched output's and fails rather than absorbing the change.
.PHONY: pad-lef-verify
pad-lef-verify:
	@python3 $(PAD_LEF_GEN) -o $(PAD_LEF) --check || exit 1
	@python3 $(PAD_LEF_GEN) --print-delta

# ── ROM content verification ───────────────────────────────────────────────
# romlibs-verify / -verify-static / -verify-content / -verify-gds / -selftest.
# Its own fragment because it is the one part of this file with real logic, and
# because it STAYS project-side when the flow moves to the asic-toolkit: the
# toolkit owns stage scripts, ROM generation and verification do not move.
#
# LAST, deliberately: it reads ROMLIBS_DIR, ETH_BINTXT, CC_BINTXT and the two
# spec paths defined above. Anything re-entering this makefile from a recipe must
# use $(COMMON_MK) — see the note at its definition.
include $(dir $(COMMON_MK))rom_gate.mk

# ── Per-run ROM generation ─────────────────────────────────────────────────
# rom-run / rom-run-stage / rom-run-status / rom-cache-clean. AFTER rom_gate.mk
# because it consumes that file's ROM table ($(ROMS), ROM_LABEL_*, ROM_SPEC_*,
# ROM_CODE_*, ROM_INST_*) — one description of which ROMs this die has, used both
# to build them and to judge them. It also drives the gate over the run it has
# just populated.
include $(dir $(COMMON_MK))rom_build.mk
