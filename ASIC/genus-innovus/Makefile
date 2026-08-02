#-----------------------------------------------------------------------------
# nanosoc-multicore-system / syn/asic/genus_innovus/Makefile
# A joint work commissioned on behalf of SoC Labs, under Arm Academic
# Access license.
#
# Contributors
#
# Daniel Newbrook (d.newbrook@soton.ac.uk)
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# Flat Fusion Compiler P&R flow for the multicore SoC top. All stage logic
# (fc_init -> fc_synth -> fc_cts -> fc_route -> fc_signoff -> fc_drc ->
# fc_abstract, + fusion_lib / fc / fc_all / gui) lives in the
# soclabs-asic-flow toolkit (syn/asic/_flow). This Makefile is a thin shim:
# it sets DESIGN_DIR, pulls in the project's design-scoped common.mk, then
# includes the toolkit.
#
# Usage:
#   make syn                  
#   make help                        # toolkit target list
#-----------------------------------------------------------------------------

DESIGN_DIR := $(CURDIR)
include $(CURDIR)/../common.mk

ASIC_FLOWS_DIR:= $(DESIGN_DIR)/../asic-flows/Cadence
REPORT_DIR := $(DESIGN_DIR)/reports
LOG_DIR := $(DESIGN_DIR)/logs
OUT_DIR := $(DESIGN_DIR)/outputs
WORK_DIR := $(DESIGN_DIR)/work

setup_dirs:
	mkdir -p $(REPORT_DIR)
	mkdir -p $(LOG_DIR)
	mkdir -p $(OUT_DIR)
	mkdir -p $(WORK_DIR)

## The two generated sub-flists the ASIC flist `-f`-includes. Rendered by the
## top-level `make asic-flist` (which sources the three set_env.sh scripts in
## dependency order — this Makefile deliberately does not try to reproduce that).
## Regenerated every run so the TideLink V2 / SoC selection can never go stale.
.PHONY: asic-flist
asic-flist:
	$(MAKE) -C $(NANOSOC_ETH_CHIPLET_HOME) --no-print-directory asic-flist

## Genus reads the ROM .libs via config.tcl's lib_search_path_list. Without them
## `syn` dies ~immediately inside set_db with "Cannot open file
## 'rom_via_ss_1p08v_1p08v_125c.lib'". Check up front and say why.
.PHONY: romlibs-check
romlibs-check:
	@$(MAKE) -C $(DESIGN_DIR)/.. -f common.mk --no-print-directory romlibs-verify || { \
	    echo ""; \
	    echo "The ROM libraries are not built. Build them with:"; \
	    echo "    make -C $(DESIGN_DIR)/.. -f common.mk tsmc_65_romlibs MEM_COMPILER_DIR=PATH_TO_COMPLETE_PHYS_IP"; \
	    echo "This needs (a) the bootloader firmware built, for the ROM code_files, and"; \
	    echo "(b) a WORKING Arm mem compiler — see the MEM_COMPILER_DIR note in common.mk."; \
	    exit 1; }

syn: setup_dirs asic-flist romlibs-check
	cd $(WORK_DIR)/; genus -f $(ASIC_FLOWS_DIR)/1_synthesis.tcl -log $(LOG_DIR)/syn_logs

syn_norun:
	cd $(WORK_DIR)/; genus -log $(LOG_DIR)/syn_logs

lec:
	cd $(WORK_DIR)/; lec -xl -Dofile ./lec.dofile

## The three Innovus stages, in order. Each reads the DB the previous one wrote
## (`read_db $block_name` / `write_db $block_name` inside work/), so they must be
## run in sequence and CANNOT be parallelised. Resume mid-flow by invoking the
## stage you want — the DB in work/ carries the state.
##
##   pnr_place : floorplan + power plan + place_design + tie-offs   (2_pnr_setup)
##   pnr_cts   : clock tree synthesis + post-CTS opt                (3_pnr_clock)
##   pnr_route : route + filler + bondpads + GDS + reports + DRC    (4_pnr_route)
##
## pnr_route is the stage that emits the GDSII ($(OUT_DIR)/$(BLOCK).gds). It
## needs asic-flows at b19e784 or later — the earlier revision stops after
## routing and writes no stream. It runs Calibre DRC at the end only when
## CALIBRE_HOME is set in the environment.
BLOCK := nanosoc_eth_chiplet_pads

.PHONY: pnr_place pnr_cts pnr_route pnr_all
pnr_place: setup_dirs
	cd $(WORK_DIR)/; innovus -stylus -f $(ASIC_FLOWS_DIR)/2_pnr_setup.tcl

pnr_cts:
	cd $(WORK_DIR)/; innovus -stylus -f $(ASIC_FLOWS_DIR)/3_pnr_clock.tcl

pnr_route:
	cd $(WORK_DIR)/; innovus -stylus -f $(ASIC_FLOWS_DIR)/4_pnr_route.tcl
	@test -s $(OUT_DIR)/$(BLOCK).gds \
	    && echo "OK: GDSII $(OUT_DIR)/$(BLOCK).gds ($$(du -h $(OUT_DIR)/$(BLOCK).gds | cut -f1))" \
	    || { echo "FAIL: no GDSII at $(OUT_DIR)/$(BLOCK).gds"; \
	         echo "      check ASIC/asic-flows is at b19e784+ (write_stream lives there)"; exit 1; }

## pnr_all: syn -> place -> CTS -> route -> GDSII, unattended. Multi-hour.
pnr_all: syn pnr_place pnr_cts pnr_route

## pnr_setup: interactive Innovus in work/, for debugging a stage by hand.
pnr_setup:
	cd $(WORK_DIR)/; innovus -stylus

drc:
	cd $(WORK_DIR)/; calibre -gui