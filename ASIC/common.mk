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
# Included by all flow Makefiles under syn/asic/

export NANOSOC_MULTICORE_HOME := $(realpath $(dir $(lastword $(MAKEFILE_LIST)))/../..)

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

# ── CMSDK path ─────────────────────────────────────────────────────────────
# ARM Cortex-M System Design Kit (required for cmsdk_ahb_to_sram / AHB fabric)
export CMSDK_DIR ?= $(ARM_IP_LIBRARY_PATH)/BP210/BP210-BU-00000-r1p1-00rel0

# ── TSMC65 PDK roots (needed by genus-innovus/scripts/config.tcl) ───────────
# config.tcl references $::env(TSMC_65_HOME) (TSMC TSMCHOME staggered IO lib +
# tcbn65lp standard-cell NLDM) and $::env(PHYS_IP) (Arm cln65lp sc12 base-cell
# LEF/DB). set_env.sh does NOT export these, so the Genus flow (which includes
# this common.mk) resolves them here. Both `?=` so a site/CI export wins.
#   NOTE: TSMC_65_HOME currently points at a per-user tree — the ONLY copy that
#   carries the STAGGERED IO2.5V lib (no /research/AAA copy exists). Override on
#   any other host. PHYS_IP is the shared read-only Arm phys-IP library.
export TSMC_65_HOME ?= /home/dwn1c21/SoC-Labs/phys_ip/TSMC/65
export PHYS_IP      ?= /research/AAA/phys_ip_library

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
# Target library (.db) — used for mapping and optimization
export TARGET_LIB     ?= /research/AAA/phys_ip_library/arm/tsmc/cln65lp/sc12_base_rvt/r0p0/db/sc12_cln65lp_base_rvt_ss_typical_max_1p08v_125c.db

# ── Memory macro libraries (compiled register file) ────────────────────────
# TODO: confirm memory macro sizing for IMEM (64 KB), DMEM (16 KB), BOOTROM (8 KB)
# and eth scratch SRAMs (16 KB each). Current default uses the 16 KB RF macro.
export MEM_PATH       ?= /research/precompiled_mems/TSMC65/rf_16k
export MEM_DB_SS      ?= $(MEM_PATH)/rf_16k_ss_1p08v_1p08v_125c.db
export MEM_DB_FF      ?= $(MEM_PATH)/rf_16k_ff_1p32v_1p32v_m40c.db

# Link libraries — target + any additional macro/IP libs
export LINK_LIBS      ?= $(TARGET_LIB) $(MEM_DB_SS)

# TF/Milkyway — physical reference for floorplan estimation (TSMC 65nm, 1p9m_6x2z)
export PHYS_IP_PATH   ?= /research/AAA/phys_ip_library/arm/tsmc/cln65lp

# Standard cell Verilog simulation models (for gate-level simulation)
export STDCELL_VERILOG ?= $(PHYS_IP_PATH)/sc12_base_rvt/r0p0
export TF_FILE        ?= $(PHYS_IP_PATH)/arm_tech/r2p0/milkyway/1p9m_6x2z/sc12_tech.tf
export MW_REF_LIB     ?= $(PHYS_IP_PATH)/sc12_base_rvt/r0p0/milkyway/1p9m_6x2z/sc12_cln65lp_base_rvt

# ── RTLA Reference Methodology ────────────────────────────────────────────
export RTLA_RM_PATH   ?= /research/synopsys/RTLA-RM_U-2022.12

# ── Multi-corner .db libraries (for RTLA CLIB on-the-fly creation) ────────
export DB_PATH        ?= $(PHYS_IP_PATH)/sc12_base_rvt/r0p0/db
export DB_SS          ?= $(DB_PATH)/sc12_cln65lp_base_rvt_ss_typical_max_1p08v_125c.db
export DB_FF          ?= $(DB_PATH)/sc12_cln65lp_base_rvt_ff_typical_min_1p32v_m40c.db

# ── TLU+ parasitic extraction models ──────────────────────────────────────
export TLUPLUS_PATH   ?= $(PHYS_IP_PATH)/arm_tech/r2p0/synopsys_tluplus/1p9m_6x2z
export TLUPLUS_MAP    ?= $(TLUPLUS_PATH)/tluplus.map

# ── Design constraints ────────────────────────────────────────────────────
# 4 ns period (250 MHz) — matches tidelink.
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
# Overridable so a site/EDA-host export wins. PORTABILITY + INSTALL LANDMINE:
#   * The default per-user tree carries a COMPLETE compiler (generator views).
#   * The shared read-only /research/AAA/phys_ip_library copy has the binaries
#     but is VIEW-LESS: `rom_via_hdd_rvt_rvt liberty` reports "Available
#     generators are: ." and exits 1 — it cannot emit .lib on that install.
#   So `tsmc_65_romlibs` only succeeds where a fully-installed compiler is
#   reachable (typically the EDA host). Override MEM_COMPILER_DIR there.
MEM_COMPILER_DIR ?= /home/dwn1c21/SoC-Labs/phys_ip

ROM_65nm_SPEC_FILE :=

# ── ROM-lib generation, made turn-key for an EDA host ───────────────────────
# One command on a host with a COMPLETE mem-compiler:
#   make -C syn/asic -f common.mk tsmc_65_romlibs MEM_COMPILER_DIR=/path/to/phys_ip
# It regenerates the eth code_file, preflight-checks everything (and refuses the
# view-less /research copy with a clear message), then compiles both ROM libs
# into syn/asic/romlibs/{eth_rom,cc_rom} — the project tree only, never /research.
ROM_COMPILER  := $(MEM_COMPILER_DIR)/arm/tsmc/cln65lp/rom_via_hdd_rvt_rvt/r0p0/bin/rom_via_hdd_rvt_rvt
FW_BUILD_DIR  ?= $(NANOSOC_MULTICORE_HOME)/build/cmake/gcc-m0plus-le
BOOTROM_GEN   := $(SOCLABS_NANOSOC_ARCH_TECH_DIR)/firmware/testcodes/bootloader/bootrom_gen.py
ETH_ROM_DIR   := $(FW_BUILD_DIR)/firmware/bootloader/stage0_bootrom
CC_ROM_DIR    := $(FW_BUILD_DIR)/firmware/bootloader/stage0_bootrom_chip_core
ETH_HEX       := $(ETH_ROM_DIR)/stage0_bootrom.hex
ETH_BINTXT    := $(ETH_ROM_DIR)/eth_ss_bootrom.bintxt
CC_BINTXT     := $(CC_ROM_DIR)/nanosoc_bootrom_chip_core.bintxt
ETH_ROM_SPEC  := $(NANOSOC_MULTICORE_HOME)/syn/asic/tech_wrappers/tsmc65/eth_rom.spec
CC_ROM_SPEC   := $(NANOSOC_MULTICORE_HOME)/syn/asic/tech_wrappers/tsmc65/nanosoc_rom.spec

# Regenerate the eth ROM code_file from the already-built hex (deterministic; no
# cmake reconfigure). The chip_core bintxt IS built by the default firmware build;
# the eth one is opt-in (see firmware/bootloader/stage0_bootrom/CMakeLists.txt).
# Writes only into the build tree — NOT src/rtl/bootrom/eth_ss_bootrom.sv.
.PHONY: eth-bintxt
eth-bintxt:
	@test -f "$(ETH_HEX)" || { echo "FAIL: $(ETH_HEX) not built — build firmware first (make firmware)."; exit 1; }
	python3 $(BOOTROM_GEN) -i $(ETH_HEX) -a 9 -t gcc -v $(ETH_ROM_DIR)/eth_ss_bootrom.sv -b $(ETH_BINTXT) -m eth_ss_bootrom
	@echo "OK: regenerated $(ETH_BINTXT) ($$(wc -l < $(ETH_BINTXT)) words)"

.PHONY: romlibs-preflight
romlibs-preflight:
	@echo "== ROM-lib preflight =="
	@case "$(MEM_COMPILER_DIR)" in \
	  /research/AAA/phys_ip_library*) \
	    echo "FAIL: MEM_COMPILER_DIR=$(MEM_COMPILER_DIR) is the VIEW-LESS shared copy"; \
	    echo "      ('Available generators are: .' -> exit 1; cannot emit .lib)."; \
	    echo "      Override with a COMPLETE install, e.g. on the EDA host:"; \
	    echo "      make ... tsmc_65_romlibs MEM_COMPILER_DIR=/path/to/complete/phys_ip"; \
	    exit 1;; \
	esac
	@test -x "$(ROM_COMPILER)" || { echo "FAIL: ROM compiler missing/not executable: $(ROM_COMPILER)"; exit 1; }
	@test -f "$(ETH_BINTXT)" || { echo "FAIL: missing eth code_file $(ETH_BINTXT) (run: make -f common.mk eth-bintxt)"; exit 1; }
	@test -f "$(CC_BINTXT)"  || { echo "FAIL: missing cc code_file $(CC_BINTXT) (build firmware first)"; exit 1; }
	@test -f "$(ETH_ROM_SPEC)" || { echo "FAIL: missing spec $(ETH_ROM_SPEC)"; exit 1; }
	@test -f "$(CC_ROM_SPEC)"  || { echo "FAIL: missing spec $(CC_ROM_SPEC)"; exit 1; }
	@echo "OK: compiler      = $(ROM_COMPILER)"
	@echo "OK: eth code_file = $(ETH_BINTXT)"
	@echo "OK: cc  code_file = $(CC_BINTXT)"

# eth-bintxt first (produces the code_file), then preflight validates all inputs.
tsmc_65_romlibs: eth-bintxt romlibs-preflight
	mkdir -p $(NANOSOC_MULTICORE_HOME)/syn/asic/romlibs/eth_rom
	mkdir -p $(NANOSOC_MULTICORE_HOME)/syn/asic/romlibs/cc_rom
	@echo "Generating Bootroms"
	@echo "Gen Ethernet ROM"
	cd $(NANOSOC_MULTICORE_HOME)/syn/asic/romlibs/eth_rom; $(ROM_COMPILER) liberty -spec $(ETH_ROM_SPEC) -code_file $(ETH_BINTXT);
	cd $(NANOSOC_MULTICORE_HOME)/syn/asic/romlibs/eth_rom; $(ROM_COMPILER) all     -spec $(ETH_ROM_SPEC) -code_file $(ETH_BINTXT);
	@echo "Gen CC ROM"
	cd $(NANOSOC_MULTICORE_HOME)/syn/asic/romlibs/cc_rom; $(ROM_COMPILER) liberty -spec $(CC_ROM_SPEC) -code_file $(CC_BINTXT)
	cd $(NANOSOC_MULTICORE_HOME)/syn/asic/romlibs/cc_rom; $(ROM_COMPILER) all     -spec $(CC_ROM_SPEC) -code_file $(CC_BINTXT)
	@echo "Done: ROM libs in syn/asic/romlibs/{eth_rom,cc_rom}"


gen_memories: bootrom
	@mkdir -p $(MEMORIES_DIR)
	@mkdir -p $(RF_16K_DIR)
	@mkdir -p $(RF_08K_DIR)
	@mkdir -p $(ROM_DIR)
	cp $(BOOTROM_BIN_FILE_IN) $(BOOTROM_BIN_FILE)
	echo "Generating register file memory libraries"
	echo "16K RF"
	cd $(RF_16K_DIR); $(MEM_COMPILER_DIR)/arm/tsmc/cln65lp/rf_sp_hdf_hvt_rvt/r0p0/bin/rf_sp_hdf_hvt_rvt all -spec $(RF_16K_65nm_SPEC_FILE);
	cd $(RF_16K_DIR); $(MEM_COMPILER_DIR)/arm/tsmc/cln65lp/rf_sp_hdf_hvt_rvt/r0p0/bin/rf_sp_hdf_hvt_rvt liberty -spec $(RF_16K_65nm_SPEC_FILE);
	echo "8K RF"
	cd $(RF_08K_DIR); $(MEM_COMPILER_DIR)/arm/tsmc/cln65lp/rf_sp_hdf_hvt_rvt/r0p0/bin/rf_sp_hdf_hvt_rvt all -spec $(RF_08K_65nm_SPEC_FILE);
	cd $(RF_08K_DIR); $(MEM_COMPILER_DIR)/arm/tsmc/cln65lp/rf_sp_hdf_hvt_rvt/r0p0/bin/rf_sp_hdf_hvt_rvt liberty -spec $(RF_08K_65nm_SPEC_FILE);
	cd $(ROM_DIR)
	echo "Generating ROM Libraries"
	cd $(ROM_DIR); $(MEM_COMPILER_DIR)/arm/tsmc/cln65lp/rom_via_hdd_rvt_rvt/r0p0/bin/rom_via_hdd_rvt_rvt liberty -spec $(ROM_65nm_SPEC_FILE) -code_file $(BOOTROM_BIN_FILE);
	cd $(ROM_DIR); $(MEM_COMPILER_DIR)/arm/tsmc/cln65lp/rom_via_hdd_rvt_rvt/r0p0/bin/rom_via_hdd_rvt_rvt all -spec $(ROM_65nm_SPEC_FILE) -code_file $(BOOTROM_BIN_FILE);
	echo "Finished generating memory libraries"
