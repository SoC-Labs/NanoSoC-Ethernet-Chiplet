# =============================================================================
# g2_soc_pair — "full G2": two real `nanosoc_multicore_soc`, each behind its own
# `chiplet_d2d_decode` + `tidelink_top`, cross-wired through the PHY pads.
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
#
# Copyright 2026, SoC Labs (www.soclabs.org)
# =============================================================================
# TWO targets, one merged flist:
#
#   make          (== make elab)  structural ELABORATION of tb_g2_soc_pair under
#                                 VCS. Milestone 1: 0 errors, firmware-free. Does
#                                 NOT go through cocotb.
#   make sim                      the cocotb data-plane test (milestone 2): bring
#                                 both links up over each die's eth_ss_0 -> APB,
#                                 write die A's peer aperture, observe die B's
#                                 shared_sram_0.
#
# The merged flist is the union of THREE component flists plus the integration
# RTL, assembled exactly as the repo's top-level `make elab` does:
#
#   * the SoC's generated flist, flattened to VCS-readable absolute paths
#     (flatten_soc_flist.py — the generator emits $()-paths VCS cannot expand);
#   * TideLink's flist, resolved to ONE definition per module
#     (resolve_tidelink_flist.py — drops the shadowed deps AddrSync_18 that lacks
#     the a2l reset-skew fix, so the netlist is a property of the filelist, not
#     of VCS "last-wins");
#   * TideChart's flist;
#   * this repo's chiplet_d2d_decode / tidechart_shim / nanosoc_eth_chiplet.
#
# DUPLICATE-MODULE NOTE (pre-existing, benign): the SoC and TideLink flists both
# compile three shared Arm CMSDK cells (cmsdk_ahb_to_apb, cmsdk_ahb_to_sram,
# cmsdk_apb_slave_mux). VCS reports Warning-[OPD] and keeps the last; the copies
# are equivalent. Not an error, not introduced by this env. See
# flist/nanosoc_eth_chiplet.flist.
# =============================================================================
SHELL := /bin/bash

CHIPLET_HOME  := $(realpath $(CURDIR)/../..)
NANOSOC_MULTICORE_HOME := $(CHIPLET_HOME)/nanosoc-multicore-system
# Exported: resolve_tidelink_flist.py passes `+incdir` switches through
# UNEXPANDED (e.g. `+incdir+$${TIDELINK_HOME}/deps/tidelink-gpio-phy/rtl`, which
# holds tidelink_training_patterns.svh), so VCS must see TIDELINK_HOME in its
# environment. The repo's top-level `make elab` gets this by sourcing the env in
# VCS's own shell; here it is exported explicitly.
export TIDELINK_HOME := $(CHIPLET_HOME)/tidelink

BUILD := $(CURDIR)/build

# --- Paths the merged flist expands at VCS time (nanosoc_eth_chiplet.flist and
#     tidechart.flist reference these as ${VAR}). Exported so VCS — whether
#     invoked by `elab` or by cocotb — sees them. The SoC/TideLink env vars are
#     NOT needed at VCS time: the two prepared flists below are already
#     flattened to absolute paths. ------------------------------------------
export NANOSOC_ETH_CHIPLET_HOME := $(CHIPLET_HOME)
export TIDECHART_HOME           := $(CHIPLET_HOME)/tidechart
export CHIPLET_SOC_VCS_FLIST    := $(BUILD)/soc_vcs.f
export CHIPLET_TL_VCS_FLIST     := $(BUILD)/tidelink_vcs.f

FLIST := $(CHIPLET_HOME)/flist/nanosoc_eth_chiplet.flist

# QSPI flash VIP (unprogrammed => CPU1 halts). Same model soc_d2d_loopback uses.
AHB_QSPI_HOME := $(NANOSOC_MULTICORE_HOME)/ahb_qspi
FLASH_VIP     := $(AHB_QSPI_HOME)/verif/VIP/SST26VF064B.v
FLASH_INCDIR  := $(AHB_QSPI_HOME)/verif/VIP

# pad_skid is TideLink's, unmodified, compiled straight from the submodule.
PAD_SKID := $(TIDELINK_HOME)/cocotb/tidelink_top_pair/pad_skid.sv

TOPLEVEL = tb_g2_soc_pair
MODULE  ?= test_g2_soc_pair

SKID_BITS ?= 0
export SKID_BITS

VCS_COMMON := -full64 -sverilog -timescale=1ns/1ps

# =============================================================================
# Flist preparation. Needs the FULL component environment (the SoC flist embeds
# ETHMAC/PHC/IPC/CMSDK/tech ${VAR}s; TideLink embeds CMSDK_FPGA_SRAM_V/XHB500),
# so this recipe sources all three set_env.sh in dependency order — exactly as
# the repo's `make elab` does. Regenerated every run so both prepared flists
# track the current build_soc render and the pinned TideLink.
# =============================================================================
# Written as ONE shell command (&&-joined) so `source` and the exported vars it
# sets persist across the flatten/resolve steps — without a global `.ONESHELL:`,
# which would perturb cocotb's Makefile.sim recipes.
.PHONY: flists
flists:
	mkdir -p "$(BUILD)" && \
	source "$(CHIPLET_HOME)/set_env.sh" >/dev/null && \
	source "$(NANOSOC_MULTICORE_HOME)/set_env.sh" >/dev/null && \
	source "$(TIDELINK_HOME)/set_env.sh" >/dev/null && \
	python3 "$(CHIPLET_HOME)/flist/flatten_soc_flist.py" \
	    "$${NANOSOC_MULTICORE_HOME}/flist/nanosoc_multicore.flist" > "$(CHIPLET_SOC_VCS_FLIST)" && \
	python3 "$(CHIPLET_HOME)/flist/resolve_tidelink_flist.py" \
	    "$${TIDELINK_HOME}/flists/tidelink_fpga.flist" > "$(CHIPLET_TL_VCS_FLIST)" && \
	echo "flists: prepared $(CHIPLET_SOC_VCS_FLIST) and $(CHIPLET_TL_VCS_FLIST)"

# =============================================================================
# Milestone 1: standalone structural elaboration (no cocotb).
# =============================================================================
.PHONY: elab
elab: flists
	mkdir -p "$(BUILD)/elab" && cd "$(BUILD)/elab" && \
	echo "== vcs $(VCS_COMMON) -f $(FLIST) + tb + pad_skid + flash, -top $(TOPLEVEL) ==" && \
	vcs $(VCS_COMMON) \
	    -f "$(FLIST)" \
	    +incdir+$(FLASH_INCDIR) \
	    "$(FLASH_VIP)" \
	    "$(PAD_SKID)" \
	    "$(CURDIR)/$(TOPLEVEL).sv" \
	    -top $(TOPLEVEL) \
	    -o simv_g2 \
	    -l "$(BUILD)/elab/elab.log"

# =============================================================================
# Milestone 2: cocotb data-plane test.
# =============================================================================
SIM           = vcs
TOPLEVEL_LANG = verilog

VERILOG_SOURCES = $(CURDIR)/$(TOPLEVEL).sv $(PAD_SKID) $(FLASH_VIP)

COMPILE_ARGS += $(VCS_COMMON) -debug_access+all
COMPILE_ARGS += -f $(FLIST)
COMPILE_ARGS += +incdir+$(FLASH_INCDIR)
COMPILE_ARGS += +define+TB_TOP_SKID_BITS=$(SKID_BITS)

# The OpenCores MAC wishbone slave drives X on hrdata during APB writes; same
# workaround soc_d2d_loopback / soc_multicore_smoke use. It masks nothing this
# env asserts on (the data-plane observation reads shared SRAM through explicit
# resolvable checks).
export COCOTB_RESOLVE_X ?= ZEROS

WAVES ?= 0
ifeq ($(WAVES),1)
COMPILE_ARGS += +define+DUMP_FSDB
endif

SIM_BUILD ?= $(BUILD)/sim

# `sim` lives in cocotb's Makefile.sim; keep `elab` the default so a bare `make`
# elaborates (milestone 1) rather than launching the long cocotb run.
.DEFAULT_GOAL := elab

include $(shell cocotb-config --makefiles)/Makefile.sim

# The prepared flists must exist before VCS reads them via COMPILE_ARGS.
sim: | flists

clean::
	rm -rf "$(BUILD)" __pycache__ results.xml ucli.key novas.* verdi*
