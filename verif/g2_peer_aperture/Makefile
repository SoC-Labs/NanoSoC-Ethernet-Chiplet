# =============================================================================
# g2_peer_aperture — does a transaction actually cross the die boundary?
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
#
# Copyright 2026, SoC Labs (www.soclabs.org)
# =============================================================================
# Everything else we have proves the *port*. `soc_d2d_loopback` in the SoC drives
# `d2d_ahb_m` against a memory model; `verif/chiplet_d2d_decode` proves the
# sub-decode. Neither has ever put a transaction on a link with another die at
# the far end. This does.
#
# Two cross-wired `tidelink_top` instances, PHY pads joined through `pad_skid`,
# exactly as `tidelink/cocotb/tidelink_top_pair` does — except that testbench
# TIES OFF `ahb_sub` and `ahb_mng`, which are the two ports the peer aperture
# lives on. So the harness is copied, not reused, and the data plane is wired up.
#
# What it asserts (docs/G2_PAIR_SIM.md):
#   1. a write into die A's peer aperture (0x2F......) emerges on die B's
#      `ahb_mng` at 0x2D...... — i.e. the CAM's replaced upper byte SURVIVES the
#      packetiser. This is the simulation counterpart of the RTL reading in
#      docs/PEER_APERTURE_PROGRAMMING.md §8.1.
#   2. a doorbell rung on die A raises `doorbell_irq` on die B.
#   3. with the far die held in reset, a TX-aperture write on die A FAULTS
#      promptly instead of wedging the bus.
#
# NOT the full G2. Assertion 1 in the plan says "CPU0 on die A" — here an AHB
# master model stands in for CPU0. Swapping in two real `nanosoc_multicore_soc`
# instances is the next step; the addressing and the bring-up are identical.
#
#   source ../../set_env.sh && make
#   make MODULE=test_peer_aperture WAVES=1
# =============================================================================
SIM             = vcs
TOPLEVEL_LANG   = verilog

CHIPLET_HOME  ?= $(realpath $(CURDIR)/../..)
TIDELINK_HOME ?= $(CHIPLET_HOME)/tidelink
export TIDELINK_HOME

# cocotb invokes VCS directly, so it never sources tidelink/set_env.sh — and the
# TideLink flist embeds ${CMSDK_FPGA_SRAM_V} literally. Resolve it here the same
# way that script does. `?=` so a sourced environment still wins.
# These point into the shared, READ-ONLY lab IP library. Never write there.
export CMSDK_DIR         ?= $(ARM_IP_LIBRARY_PATH)/BP210/BP210-BU-00000-r1p1-00rel0
export CMSDK_FPGA_SRAM_V ?= $(CMSDK_DIR)/logical/models/memories/cmsdk_fpga_sram.v

BUILD := $(CURDIR)/build
# TideLink's own flist compiles two disagreeing copies of
# WlinkGenericFCReplayAddrSync_18 and leans on VCS "last declaration wins". A
# first-wins tool binds the deps/ copy, which lacks the a2l ACK-ptr reset-skew
# fix — invisible in sim, a 6-word false-FULL wedge on silicon. Resolve it so the
# netlist is a property of the filelist, not of the compiler.
TL_FLIST := $(BUILD)/tidelink_vcs.f

# `pad_skid` is TideLink's, unmodified, compiled straight from the submodule.
# The tb is ours because theirs ties off the ports under test.
VERILOG_SOURCES = $(CURDIR)/tb_pair.sv \
                  $(TIDELINK_HOME)/cocotb/tidelink_top_pair/pad_skid.sv

TOPLEVEL = tb_pair
MODULE  ?= test_peer_aperture

SKID_BITS ?= 0
export SKID_BITS

# -kdb needs Verdi, which is not installed here; -debug_access+all is what cocotb
# needs to poke the calibrator bypass and read the FCSM sticky bits.
COMPILE_ARGS += -full64 -sverilog -timescale=1ns/1ps -debug_access+all
COMPILE_ARGS += -f $(TL_FLIST)
COMPILE_ARGS += +define+TB_TOP_SKID_BITS=$(SKID_BITS)

# Autoneg parks in ST_BYPASS at POR unless the tb forces the nego config, and
# NEGO_CFG_RESET is 7'h00 — not the 7'h61 the integration guide claims. Drive the
# link from software (APB ROLE_CFG), same as the doorbell test does.
BYPASS_AUTONEG ?= 1
COMPILE_ARGS += +define+TB_TOP_BYPASS_AUTONEG=$(BYPASS_AUTONEG)

WAVES ?= 0
ifeq ($(WAVES),1)
COMPILE_ARGS += +define+DUMP_FSDB
endif

SIM_BUILD ?= $(BUILD)/sim

# `sim` lives in cocotb's Makefile.sim, so this must come before the include or
# the flist rule below silently becomes make's default goal and nothing runs.
.DEFAULT_GOAL := sim

# Regenerate the resolved flist so it always tracks the pinned TideLink.
.PHONY: tl-flist
tl-flist:
	@mkdir -p $(BUILD)
	@python3 $(CHIPLET_HOME)/flist/resolve_tidelink_flist.py \
	    $(TIDELINK_HOME)/flists/tidelink_fpga.flist > $(TL_FLIST)

include $(shell cocotb-config --makefiles)/Makefile.sim

# Order-only: the flist must exist before VCS reads it via COMPILE_ARGS.
sim: | tl-flist

clean::
	rm -rf $(BUILD) __pycache__ results.xml ucli.key novas.* verdi*
