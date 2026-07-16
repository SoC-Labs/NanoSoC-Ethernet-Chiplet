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

pnr_setup:
	cd $(WORK_DIR)/; innovus -stylus 
