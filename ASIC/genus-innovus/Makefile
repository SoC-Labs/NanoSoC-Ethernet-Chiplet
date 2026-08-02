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

# The design top. Everything the flow writes is named after it, so it is also
# how `status` finds out which stages have run.
BLOCK := nanosoc_eth_chiplet_pads
# `?=` so DRC can be pointed at a GDS built elsewhere (a reference run, or a
# stream handed over for checking) without touching this file.
GDS   ?= $(OUT_DIR)/$(BLOCK).gds

# Calibre DRC. Same deck the flow's own in-Innovus DRC uses; DRC_CPUS only
# affects the GUI/batch runs driven from here.
DRC_RULEDECK ?= /tsmc65pdk/65/CMOS/util/MAIN_DRC_TopMu/CLN65S_9M_6X1Z1U.26_2a
DRC_RUNSET   := $(WORK_DIR)/calibre_drc.runset
DRC_RUNDIR   := $(WORK_DIR)/drc_run

# Where `romlibs-fetch` copies the built ROM libraries FROM. They cannot be
# regenerated on srv03335 — the Arm ROM compiler starts but lists zero
# generators since the RHEL 8.8 -> 8.10 upgrade (romlibs-preflight in
# common.mk detects and explains it). This tree is the only built copy.
ROMLIBS_REF ?= /home/dwn1c21/SoC-Labs/TAPEOUT/2026july/NanoSoC-Ethernet-Chiplet/ASIC/romlibs

# Bare `make` used to run setup_dirs (just mkdir) and report success having
# done nothing recognisable. Show the flow instead.
.DEFAULT_GOAL := help

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
## pnr_route is the stage that emits the GDSII ($(GDS)). It needs asic-flows at
## b19e784 or later — the earlier revision stops after routing and writes no
## stream. It runs Calibre DRC at the end only when CALIBRE_HOME is set in the
## environment, and that in-Innovus DRC is a no-op — see the `drc` target.
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

## pnr_setup: interactive Innovus in work/, empty session.
pnr_setup:
	cd $(WORK_DIR)/; innovus -stylus

## gui: interactive Innovus with the design ALREADY LOADED — config.tcl sourced
## and the saved DB read. `pnr_setup` drops you in an empty session where
## `read_db` alone fails, because the block name and every library path live in
## config.tcl. This is the one you want for inspecting a stage.
.PHONY: gui
gui:
	@test -d $(WORK_DIR)/$(BLOCK) || { \
	    echo "FAIL: no saved DB at $(WORK_DIR)/$(BLOCK) — run 'make pnr_place' first."; exit 1; }
	@printf '%s\n' \
	    'source ../scripts/config.tcl' \
	    'read_db $(BLOCK)' \
	    'puts "== $(BLOCK) loaded — this is the last-written DB =="' \
	    > $(WORK_DIR)/open_db.tcl
	cd $(WORK_DIR)/; innovus -stylus -f open_db.tcl

#-----------------------------------------------------------------------------
# Calibre DRC
#-----------------------------------------------------------------------------
# The TSMC deck ships with placeholders --
#     LAYOUT PATH    "GDSFILENAME"
#     LAYOUT PRIMARY "TOPCELLNAME"
# -- so the layout and top cell must come from a Calibre Interactive RUNSET,
# which overrides them when the deck is expanded.
#
# Two things went wrong with that before:
#   - `make drc` ran a bare `calibre -gui` and passed NO runset at all, so it
#     opened a blank session. scripts/calibre_drc exists but never reached the
#     tool, and its paths are relative to work/ so they only resolve from there.
#   - layout and top cell were set independently and drifted apart. In the
#     reference run the expanded deck names nanosoc_eth_chiplet.gds (the
#     pre-pads stream) against top cell nanosoc_eth_chiplet_pads, which is not
#     a cell in that file -- hence its 0-byte DRC_RES.db.
#
# Generating the runset here fixes both: the runset is always passed, paths are
# absolute, and layout and top cell are derived from $(GDS)/$(BLOCK) together
# so they cannot disagree.
$(DRC_RUNSET): | setup_dirs
	@printf '%s\n' \
	    '// GENERATED by ASIC/genus-innovus/Makefile — edits will be overwritten.' \
	    'drc.rulesFile.value = "$(DRC_RULEDECK)"' \
	    'drc.runDir.value = "$(DRC_RUNDIR)"' \
	    'drc.layout.layoutFile.value = "$(GDS)"' \
	    'drc.layout.topCell.value = "$(BLOCK)"' \
	    'cmn.turboCommand.runHow.value = "multi"' \
	    > $@
	@echo "OK: wrote $@"

.PHONY: drc-preflight
drc-preflight:
	@test -s $(GDS) || { \
	    echo "FAIL: no GDSII at $(GDS) — run 'make pnr_route' first."; exit 1; }
	@test -r $(DRC_RULEDECK) || { \
	    echo "FAIL: DRC ruledeck unreadable: $(DRC_RULEDECK)"; \
	    echo "      needs the /tsmc65pdk mount and group tsmc65pdkgrp."; exit 1; }

## drc: Calibre DRC in the GUI, runset pre-loaded and pointed at the built GDS.
.PHONY: drc
drc: drc-preflight $(DRC_RUNSET)
	cd $(WORK_DIR)/; calibre -gui -drc -runset $(DRC_RUNSET)

## drc_batch: the same DRC headless. Use this for an unattended or remote run;
## results land in $(DRC_RUNDIR).
.PHONY: drc_batch
drc_batch: drc-preflight $(DRC_RUNSET)
	cd $(WORK_DIR)/; calibre -gui -drc -batch -runset $(DRC_RUNSET)
	@echo "== DRC results in $(DRC_RUNDIR) =="

#-----------------------------------------------------------------------------
# Housekeeping
#-----------------------------------------------------------------------------
## romlibs-fetch: copy the built ROM libraries from a reference tree, because
## they cannot be built here. Override the source with ROMLIBS_REF=<path>.
.PHONY: romlibs-fetch
romlibs-fetch:
	@test -d "$(ROMLIBS_REF)" || { \
	    echo "FAIL: no ROM-lib reference tree at $(ROMLIBS_REF)"; \
	    echo "      point ROMLIBS_REF at a tree holding cc_rom/ and eth_rom/."; exit 1; }
	@echo "== copying ROM libs from $(ROMLIBS_REF) =="
	mkdir -p $(ROMLIBS_DIR)
	cp -r $(ROMLIBS_REF)/cc_rom $(ROMLIBS_REF)/eth_rom $(ROMLIBS_DIR)/
	@$(MAKE) --no-print-directory romlibs-check

## status: which flow stages have actually run, from the artefacts on disk.
## Cheap, and the fastest way to see where a part-finished flow stopped.
.PHONY: status
status:
	@echo "== $(BLOCK) =="
	@printf '  %-14s %-4s %s\n' STAGE OK ARTEFACT
	@for spec in \
	    "flist:$(NANOSOC_ETH_CHIPLET_HOME)/build/chip/flist/soc.flist" \
	    "romlibs:$(ROMLIBS_DIR)/cc_rom/rom_via.lef" \
	    "syn:$(OUT_DIR)/$(BLOCK)_gate_power.v" \
	    "place:$(REPORT_DIR)/timing_summary_01_place.rep" \
	    "cts:$(REPORT_DIR)/timing_summary_03_cts_opt.rep" \
	    "route:$(REPORT_DIR)/timing_summary_05_route_opt.rep" \
	    "gds:$(GDS)" \
	    "pnr-netlist:$(OUT_DIR)/$(BLOCK)_pnr.v" \
	    "drc:$(DRC_RUNDIR)" ; do \
	    stage=$${spec%%:*}; path=$${spec#*:}; \
	    if [ -s "$$path" ] || [ -d "$$path" ]; then \
	        printf '  %-14s %-4s %s\n' "$$stage" "yes" "$$path"; \
	    else \
	        printf '  %-14s %-4s %s\n' "$$stage" "--" "$$path"; \
	    fi; \
	done

## clean: drop the rerunnable intermediates (work DB + logs). KEEPS outputs/
## and reports/ so a finished GDS and its sign-off reports survive.
.PHONY: clean
clean:
	@echo "removing $(WORK_DIR) and $(LOG_DIR) (outputs/ and reports/ kept)"
	rm -rf $(WORK_DIR) $(LOG_DIR)

## distclean: clean, plus outputs/ and reports/ — DELETES the GDS. Prints what
## it is about to destroy first.
.PHONY: distclean
distclean:
	@echo "about to remove work/ logs/ outputs/ reports/ — including:"
	@test -s $(GDS) && echo "  !! $(GDS) ($$(du -h $(GDS) | cut -f1))" || true
	@du -sh $(OUT_DIR) $(REPORT_DIR) 2>/dev/null | sed 's/^/  /' || true
	rm -rf $(WORK_DIR) $(LOG_DIR) $(OUT_DIR) $(REPORT_DIR)

.PHONY: help
help:
	@echo "nanosoc_eth_chiplet ASIC flow — Genus + Innovus + Calibre (TSMC 65nm)"
	@echo ""
	@echo "  Flow, in order:"
	@echo "    make syn           synthesis (Genus)          -> outputs/$(BLOCK)_gate*.v"
	@echo "    make pnr_place     floorplan + place          (Innovus)"
	@echo "    make pnr_cts       clock tree synthesis       (Innovus)"
	@echo "    make pnr_route     route + fill + GDSII       -> $(GDS)"
	@echo "    make drc           Calibre DRC on that GDS    (GUI; drc_batch for headless)"
	@echo ""
	@echo "    make pnr_all       all four, unattended. Multi-hour."
	@echo ""
	@echo "  The stages share a DB in work/ and MUST run in order. To resume a"
	@echo "  part-finished flow, invoke the stage you stopped at — 'make status'"
	@echo "  shows which ones have run."
	@echo ""
	@echo "  Setup / inspection:"
	@echo "    make status        which stages have run"
	@echo "    make romlibs-fetch copy the built ROM libs (they cannot be built here)"
	@echo "    make asic-flist    re-render the generated sub-flists"
	@echo "    make gui           Innovus with config + saved DB loaded"
	@echo "    make lec           Conformal LEC on the synthesis dofile"
	@echo "    make clean         drop work/ + logs/   (keeps the GDS)"
	@echo "    make distclean     also drop outputs/ + reports/  (DELETES the GDS)"
	@echo ""
	@echo "  Needs: TSMC_65_HOME=$(TSMC_65_HOME)"
	@echo "         SOCLABS_ASIC_FLOW_DIR=$(SOCLABS_ASIC_FLOW_DIR)"
	@echo "         both exported by ../common.mk; override in the environment."