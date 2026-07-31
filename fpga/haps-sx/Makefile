#-----------------------------------------------------------------------------
# Makefile — nanoSoC ethernet chiplet on the Synopsys HAPS-SX VU19P
#
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access
# license.
#
# Contributors
#
# David Mapstone (d.a.mapstone@soton.ac.uk)
#
# Copyright 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
#   make srclist     regenerate the source list from the repo's own flists
#   make xdc         regenerate pin constraints from the .cob (via the kit)
#   make bitstream   Vivado synth + place + route + .bit          [DEFAULT FLOW]
#   make gui         open the design in the Vivado GUI
#   make program     upload a bitstream over ConfPro-SX
#   make clean       remove build/
#
#   make ps-build    ProtoSynthesis flow — LICENCE-BLOCKED HERE, see below
#   make ps-gui      ProtoCompiler GUI    — LICENCE-BLOCKED HERE, see below
#
# WHICH FLOW
#
# The SX-native path is ProtoSynthesis driven from the ProtoCompiler GUI. It
# does not run at this site: `protocompiler_s` needs the FlexNet feature
# `ProtoCompilerS`, which the licence server does not carry, and the licensed
# `protocompiler` product offers only HAPS BOARD technologies (HAPS-200/100/
# SA3/80D/80/70/DX7/ZSA) — no FPGA technology, no HAPS-SX. So the default flow
# here is Vivado, which handles the VU19P natively and needs no Synopsys
# licence. ConfPro-SX only consumes a .bit and does not care what produced it.
#
# The ProtoSynthesis scripts are kept and share the .cob, the board top and the
# generated source list, so they are ready if the licence is obtained.
# Synplify Premier DP is a licensed middle option (it has HAPS-SX-VU19P
# targets built in) if a Synopsys front end is wanted.
#
# TOOLS
#   module load haps-sx-tools     # vivado + confpro_sx + COBRA_PATH (+ protocompiler)
#-----------------------------------------------------------------------------

SHELL := /bin/bash
.ONESHELL:

HSX_DIR      := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
CHIPLET_HOME := $(abspath $(HSX_DIR)/../..)
BUILD        := $(HSX_DIR)/build
SCRIPTS      := $(HSX_DIR)/scripts
VSRC         := $(HSX_DIR)/vsrc
CONSTR       := $(HSX_DIR)/constraints

TOP          := nanosoc_eth_chiplet_haps_sx
FLIST        := $(CHIPLET_HOME)/flist/nanosoc_eth_chiplet.flist
BOARD_TOP    := $(VSRC)/$(TOP).sv

# TideLink GPIO-PHY reference divider (/8), REUSED from the KR260 target rather
# than copied. The PHY is only proven at 25 MHz/8 = 3.125 MHz; feeding it the
# MMCM output directly (100 MHz) fails place & route. The timing XDC matches on
# this module's internal names (div_cnt_reg[2], u_div_bufg), so a renamed local
# copy would silently leave the clock underived.
PHY_CLK_DIV  := $(CHIPLET_HOME)/tidelink/fpga/targets/kr260-eth-chiplet/tidelink_phy_clk_div2.v

# The two generated component flists the chiplet flist `-f`-includes. Same
# paths the parent Makefile's `elab` uses, so both flows share one render.
ELAB_BUILD                    := $(CHIPLET_HOME)/build/elab
export CHIPLET_SOC_VCS_FLIST  := $(ELAB_BUILD)/soc_vcs.f
export CHIPLET_TL_VCS_FLIST   := $(ELAB_BUILD)/tidelink_vcs.f

# HAPS-SX enablement kit (Synopsys proprietary, not vendored). The
# haps-sx-tools modulefile sets COBRA_PATH; this is the fallback.
COBRA_PATH ?= /home/dam1n19/SoCLabs/HAPS-work/HAPS-SX/haps-sx_helper
export COBRA_PATH

CONFPRO_BOARD ?= ecshaps.ecs.soton.ac.uk
BITFILE       ?= $(BUILD)/vivado_out/$(TOP).bit

# ── Firmware preload ──────────────────────────────────────────────────────
# The SoC's IMEM is a $readmemh-preloaded BRAM (RAM_PRELOAD). Its filename
# parameter defaults to the bare relative name "image.hex", and
# nanosoc_eth_chiplet instantiates nanosoc_multicore_soc with NO parameter
# overrides — so there is no way to point it elsewhere without forking the
# submodule. $readmemh resolves a relative path against Vivado's working
# directory, and `bitstream` runs Vivado from $(BUILD), so we simply place the
# image there.
#
# WITHOUT THIS the IMEM comes up empty, Vivado constant-folds it away (you see
# `CRITICAL WARNING [Synth 8-4445] could not open $readmem data file` and a
# suspiciously small BRAM count), and both cores HardFault on their first
# instruction fetch. The board looks dead with no other symptom.
#
# NOTE: ETH_IMEM_MEM_FPGA_IMG and CC_IMEM_MEM_FPGA_IMG BOTH default to
# "image.hex", so CPU0 and CPU1 preload the SAME image. Fine for bring-up.
# Distinct images need parameter passthrough added to nanosoc_eth_chiplet.
APP           ?= hello_uart
CMAKE_PRESET  ?= gcc-m0plus-le
# Must match the board top's MMCM output, or UART baud and systick are wrong.
FPGA_CLK_HZ   ?= 25000000
SOC_DIR       := $(CHIPLET_HOME)/nanosoc-multicore-system
FW_HEX        := $(SOC_DIR)/build/cmake/$(CMAKE_PRESET)/firmware/apps/$(APP)/$(APP).hex
HEX2WORD      := $(SOC_DIR)/ethernet-subsystem-ahb/fpga/scripts/hex_byte_to_word.py
IMAGE_HEX     := $(BUILD)/image.hex

.PHONY: all srclist xdc firmware bitstream gui program clean help ps-build ps-gui

all: bitstream

## Assemble the full environment (this repo + SoC + TideLink), in order.
define LOAD_ENV
	source "$(CHIPLET_HOME)/set_env.sh" > /dev/null
	source "$(CHIPLET_HOME)/nanosoc-multicore-system/set_env.sh" > /dev/null
	source "$(CHIPLET_HOME)/tidelink/set_env.sh" > /dev/null
endef

## srclist: render the component flists, then convert to source lists for both
## Vivado and ProtoSynthesis. Regenerated every time, so a submodule roll is
## picked up with no edits — that is why there is no hand-written filelist.tcl.
srclist:
	$(LOAD_ENV)
	mkdir -p "$(ELAB_BUILD)" "$(BUILD)"
	python3 "$(CHIPLET_HOME)/flist/flatten_soc_flist.py" \
	    "$${NANOSOC_MULTICORE_HOME}/flist/nanosoc_multicore.flist" > "$(CHIPLET_SOC_VCS_FLIST)"
	python3 "$(CHIPLET_HOME)/flist/resolve_tidelink_flist.py" \
	    "$${TIDELINK_HOME}/flists/tidelink_fpga.flist" > "$(CHIPLET_TL_VCS_FLIST)"
	python3 "$(SCRIPTS)/flist_to_sfl.py" "$(FLIST)" \
	    --out "$(BUILD)/chiplet" \
	    --extra "$(PHY_CLK_DIV)" \
	    --extra "$(BOARD_TOP)" \
	    --define ETH_WISHBONE_B3=1 --define RAM_PRELOAD=1

## xdc: resolve the .cob to package pins with the Synopsys kit helper, then
## convert its FDC to valid Vivado XDC and append the timing constraints.
xdc:
	mkdir -p "$(BUILD)"
	if [ ! -f "$(COBRA_PATH)/haps-sx_cobutil.tcl" ]; then
	    echo "xdc: HAPS-SX kit not found at COBRA_PATH=$(COBRA_PATH)"
	    echo "     run 'module load haps-sx-tools' or set COBRA_PATH"
	    exit 1
	fi
	tclsh <<-EOF
		set ::env(COBRA_PATH) "$(COBRA_PATH)"
		source "$(COBRA_PATH)/haps-sx_cobutil.tcl"
		processCobFile "$(CONSTR)/$(TOP).cob" fdc "$(BUILD)/$(TOP)_pins.fdc"
	EOF
	python3 "$(SCRIPTS)/fdc_to_xdc.py" "$(BUILD)/$(TOP)_pins.fdc" \
	    -o "$(BUILD)/$(TOP).xdc" \
	    --extra "$(CONSTR)/$(TOP)_timing.xdc"

## firmware: build the preload image and stage it as build/image.hex.
## Override the app with APP=<name> (see nanosoc-multicore-system/firmware/apps).
firmware:
	mkdir -p "$(BUILD)"
	cd "$(SOC_DIR)"
	cmake --preset $(CMAKE_PRESET) \
	    -DNANOSOC_SYS_CLK_FREQ_HZ=$(FPGA_CLK_HZ) \
	    -DCMAKE_C_FLAGS="-DNANOSOC_SYS_CLK_FREQ_HZ=$(FPGA_CLK_HZ)u" \
	    -DCMAKE_ASM_FLAGS="-DNANOSOC_SYS_CLK_FREQ_HZ=$(FPGA_CLK_HZ)u" > /dev/null
	cmake --build --preset $(CMAKE_PRESET) --target $(APP)
	# objcopy emits BYTE-format verilog hex; sl_fpga_rom_word wants 32-bit WORDS.
	python3 "$(HEX2WORD)" "$(FW_HEX)" "$(IMAGE_HEX)"
	@echo "[firmware] $(APP) @ $(FPGA_CLK_HZ) Hz -> $(IMAGE_HEX)"

## bitstream: Vivado synth + place + route + .bit  (the default flow here)
bitstream: srclist xdc firmware
	$(LOAD_ENV)
	cd "$(BUILD)"
	# Guard: a missing image.hex silently yields a dead bitstream.
	test -s "$(IMAGE_HEX)" || { echo "bitstream: $(IMAGE_HEX) missing/empty — run 'make firmware'"; exit 1; }
	vivado -mode batch -notrace -source "$(SCRIPTS)/build_vivado.tcl" \
	    -log "$(BUILD)/vivado_build.log" -journal "$(BUILD)/vivado_build.jou"

## gui: open the routed design in the Vivado GUI (after `make bitstream`).
gui:
	$(LOAD_ENV)
	cd "$(BUILD)"
	if [ -f "$(BUILD)/vivado_out/post_route.dcp" ]; then
	    vivado -mode gui "$(BUILD)/vivado_out/post_route.dcp"
	else
	    echo "gui: no routed checkpoint yet — run 'make bitstream' first."
	    exit 1
	fi

## program: upload a bitstream over ConfPro-SX (board port 18000).
program:
	if [ ! -f "$(BITFILE)" ]; then
	    echo "program: no bitstream at $(BITFILE) — run 'make bitstream' first,"
	    echo "         or pass BITFILE=/path/to/design.bit"
	    exit 1
	fi
	echo "== programming $(CONFPRO_BOARD) with $(BITFILE) =="
	confpro-program -p "$(CONFPRO_BOARD)" -f "$(BITFILE)"

## ps-build: ProtoSynthesis headless build. LICENCE-BLOCKED at this site.
ps-build: srclist
	$(LOAD_ENV)
	cd "$(BUILD)"
	echo "NOTE: needs the ProtoCompilerS licence feature, absent here — see the"
	echo "      header of this Makefile. Expect a licence error."
	protocompiler_s -batch -tcl "$(SCRIPTS)/build_haps_sx.tcl" \
	    -log "$(BUILD)/build_haps_sx.log"

## ps-gui: ProtoCompiler GUI, build staged. LICENCE-BLOCKED at this site.
ps-gui: srclist
	$(LOAD_ENV)
	cd "$(BUILD)"
	echo "NOTE: needs the ProtoCompilerS licence feature, absent here — see the"
	echo "      header of this Makefile. Expect a licence error."
	protocompiler_s -tcl "$(SCRIPTS)/setup_gui.tcl"

clean:
	rm -rf "$(BUILD)"

help:
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/^## /  /'
