#-----------------------------------------------------------------------------
# Makefile — nanoSoC ethernet chiplet on HAPS-SX via the ProtoCompiler
#            "export-netlist" flow (protocompiler100 UC front end + Vivado).
#
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access
# license.  Copyright 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
#   make filelist    assemble the VCS filelist for Unified Compile
#   make pcnetlist   ProtoCompiler UC compile -> export netlist @ c0 (.vm)
#   make bitstream   Vivado: wrap the .vm in the board top -> .bit
#   make all         pcnetlist then bitstream
#   make clean       remove build/
#
# HOW THIS DIFFERS FROM ../haps-sx (the direct-Vivado flow)
#
# ../haps-sx synthesises everything from RTL in Vivado. This project runs the
# chiplet through ProtoCompiler's licensed Unified-Compile front end (VCS
# elaboration + HAPS transforms), exports a clean generic-Verilog netlist at
# state c0, and lets Vivado map/P&R that. It REUSES ../haps-sx's board top,
# .cob/XDC, DRC waiver and firmware, so the only thing unique here is the PC
# leg. See scripts/pc_common.tcl and the haps-sx-protocompiler project note.
#
# TOOLS
#   module load protocompiler   # protocompiler100 + the bundled VCS W-2024.09
#   module load haps-sx-tools    # vivado + confpro_sx + COBRA_PATH
#-----------------------------------------------------------------------------

SHELL := /bin/bash
.ONESHELL:

PC_DIR       := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
CHIPLET_HOME := $(abspath $(PC_DIR)/../..)
HSX_DIR      := $(CHIPLET_HOME)/fpga/haps-sx
BUILD        := $(PC_DIR)/build
SCRIPTS      := $(PC_DIR)/scripts

CHIPLET_TOP  := nanosoc_eth_chiplet
BOARD_TOP    := nanosoc_eth_chiplet_haps_sx
FLIST        := $(CHIPLET_HOME)/flist/nanosoc_eth_chiplet.flist

# The two flattened component flists the chiplet flist -f-includes. Shared with
# `make elab` and the ../haps-sx flow so all three use one render.
ELAB_BUILD                    := $(CHIPLET_HOME)/build/elab
export CHIPLET_SOC_VCS_FLIST  := $(ELAB_BUILD)/soc_vcs.f
export CHIPLET_TL_VCS_FLIST   := $(ELAB_BUILD)/tidelink_vcs.f

# The ProtoCompiler-bundled VCS. UC rejects the module-default 2022.06
# ("Un-supported version ... supported is U-2023.03"); vcs_cmd.csh honours
# UC_VCS_HOME, so we point it at the -PC build.
export UC_VCS_HOME := /apps/synopsys/vcs/W-2024.09-SP2-3-PC

UC_FILELIST  := $(BUILD)/chiplet_uc.f

.PHONY: all filelist pcnetlist gui firmware xdc bitstream clean help

all: pcnetlist bitstream

define LOAD_ENV
	source "$(CHIPLET_HOME)/set_env.sh" > /dev/null
	source "$(CHIPLET_HOME)/nanosoc-multicore-system/set_env.sh" > /dev/null
	source "$(CHIPLET_HOME)/tidelink/set_env.sh" > /dev/null
endef

## filelist: render the component flists and assemble one VCS -f file for UC.
## The chiplet flist already carries +incdir+ and the integration RTL with
## nanosoc_eth_chiplet as top; we expand its -f includes and env vars so
## vlogan gets a self-contained list.
filelist:
	$(LOAD_ENV)
	mkdir -p "$(ELAB_BUILD)" "$(BUILD)"
	python3 "$(CHIPLET_HOME)/flist/flatten_soc_flist.py" \
	    "$${NANOSOC_MULTICORE_HOME}/flist/nanosoc_multicore.flist" > "$(CHIPLET_SOC_VCS_FLIST)"
	python3 "$(CHIPLET_HOME)/flist/resolve_tidelink_flist.py" \
	    "$${TIDELINK_HOME}/flists/tidelink_fpga.flist" > "$(CHIPLET_TL_VCS_FLIST)"
	# Expand the chiplet flist's -f includes and ${VARs} into one flat file,
	# so UC's vlogan needs no environment of its own.
	python3 "$(SCRIPTS)/assemble_uc_filelist.py" "$(FLIST)" > "$(BUILD)/chiplet_uc_body.f"
	# PREPEND the local RTL overrides (see vsrc_override/): dedup keeps the
	# FIRST definition of a module, so a copy listed before the submodule's wins
	# and the submodule stays untouched. sl_fpga_rom_word.v: single memory init,
	# for UC's MULTI-MEM-INIT strictness.
	printf '%s\n' "$(PC_DIR)/vsrc_override/sl_fpga_rom_word.v" > "$(BUILD)/chiplet_uc_raw.f"
	cat "$(BUILD)/chiplet_uc_body.f" >> "$(BUILD)/chiplet_uc_raw.f"
	# UC's vlogan does a two-step analyze and treats a duplicate module as an
	# ERROR (MPD), unlike `make elab`'s single-step vcs which tolerates it as a
	# last-wins warning (OPD). The repo's dedup tool drops the pure-duplicate
	# files (the local override's target, shared CMSDK cells, XHB500 generic
	# cells across the mst/slv trees) so exactly one definition survives.
	python3 "$(CHIPLET_HOME)/flist/dedup_merged_flist.py" "$(BUILD)/chiplet_uc_raw.f" > "$(UC_FILELIST)"
	@echo "[filelist] $$(grep -cvE '^\s*(#|//|\+|-|$$)' "$(UC_FILELIST)") source files -> $(UC_FILELIST)"

## gui: open the ProtoCompiler GUI on the compiled database (needs an X session).
## Inspect the c0 netlist / HDL Analyst schematic, or re-run from the Tcl console.
gui:
	source /etc/profile.d/modules.sh 2>/dev/null || source /usr/share/Modules/init/bash
	module use /research/CAD/EDA-Modulefiles/tools 2>/dev/null || true
	module load protocompiler
	$(LOAD_ENV)
	cd "$(BUILD)"
	protocompiler -tcl "$(SCRIPTS)/setup_gui.tcl"

## pcnetlist: ProtoCompiler Unified Compile + export netlist @ c0.
pcnetlist: filelist
	source /etc/profile.d/modules.sh 2>/dev/null || source /usr/share/Modules/init/bash
	module use /research/CAD/EDA-Modulefiles/tools 2>/dev/null || true
	module load protocompiler
	$(LOAD_ENV)
	cd "$(BUILD)"
	echo "[pcnetlist] UC_VCS_HOME=$(UC_VCS_HOME)"
	protocompiler -batch -tcl "$(SCRIPTS)/build_pc.tcl" -log "$(BUILD)/build_pc.log"

## firmware / xdc: delegate to the direct flow so there is ONE definition.
firmware:
	$(MAKE) -C "$(HSX_DIR)" firmware
	cp -f "$(HSX_DIR)/build/image.hex" "$(BUILD)/image.hex"

xdc:
	$(MAKE) -C "$(HSX_DIR)" xdc

## bitstream: Vivado wraps the exported .vm in the board top -> .bit.
bitstream: firmware xdc
	source /etc/profile.d/modules.sh 2>/dev/null || source /usr/share/Modules/init/bash
	module use /research/CAD/EDA-Modulefiles/tools 2>/dev/null || true
	module load haps-sx-tools
	$(LOAD_ENV)
	cd "$(BUILD)"
	test -f "$(BUILD)/exported/synvcs/$(CHIPLET_TOP)_compile.vm" || { \
	    echo "bitstream: no exported netlist — run 'make pcnetlist' first"; exit 1; }
	vivado -mode batch -notrace -source "$(SCRIPTS)/build_vivado_pc.tcl" \
	    -log "$(BUILD)/build_vivado_pc.log" -journal "$(BUILD)/build_vivado_pc.jou"

clean:
	rm -rf "$(BUILD)"

help:
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/^## /  /'
