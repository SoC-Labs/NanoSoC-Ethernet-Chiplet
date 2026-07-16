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

syn: setup_dirs
	cd $(WORK_DIR)/; genus -f $(ASIC_FLOWS_DIR)/1_synthesis.tcl -log $(LOG_DIR)/syn_logs

syn_norun:
	cd $(WORK_DIR)/; genus -log $(LOG_DIR)/syn_logs

lec:
	cd $(WORK_DIR)/; lec -xl -Dofile ./lec.dofile

pnr_setup:
	cd $(WORK_DIR)/; innovus -stylus 
