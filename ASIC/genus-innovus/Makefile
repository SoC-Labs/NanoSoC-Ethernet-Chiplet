#-----------------------------------------------------------------------------
# nanosoc-ethernet-chiplet / ASIC/genus-innovus/Makefile
# A joint work commissioned on behalf of SoC Labs, under Arm Academic
# Access license.
#
# Contributors
#
# Daniel Newbrook (d.newbrook@soton.ac.uk)
# David Mapstone (d.a.mapstone@soton.ac.uk)
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# Genus -> Innovus -> Conformal/Calibre for nanosoc_eth_chiplet_pads (TSMC 65nm).
# The stage scripts live in ../asic-flows/Cadence; this Makefile drives them,
# adds the result checks they omit, and owns the project-side workarounds.
# `make help` for targets, `make status` for progress.
#
# Rationale and failure modes: docs/tapeout/, esp. 08-debugging and
# 17-silent-noops — both Genus and Innovus exit 0 after failing.
#-----------------------------------------------------------------------------

DESIGN_DIR := $(CURDIR)
include $(CURDIR)/../common.mk

ASIC_FLOWS_DIR := $(DESIGN_DIR)/../asic-flows/Cadence
REPORT_DIR := $(DESIGN_DIR)/reports
LOG_DIR    := $(DESIGN_DIR)/logs
OUT_DIR    := $(DESIGN_DIR)/outputs
WORK_DIR   := $(DESIGN_DIR)/work

# Design top; everything the flow writes is named after it.
BLOCK := nanosoc_eth_chiplet_pads
# `?=`: DRC/LVS can be pointed at a stream built elsewhere.
GDS   ?= $(OUT_DIR)/$(BLOCK).gds

DRC_RUNDIR := $(WORK_DIR)/drc_run
DRC_CPUS   ?= 8

# Source for `romlibs-fetch`. The ROM libs cannot be rebuilt on srv03335 — the
# Arm compiler lists zero generators since RHEL 8.10 (romlibs-preflight in
# common.mk explains it) — so this tree is the only built copy.
ROMLIBS_REF ?= /home/dwn1c21/SoC-Labs/TAPEOUT/2026july/NanoSoC-Ethernet-Chiplet/ASIC/romlibs

.DEFAULT_GOAL := help

.PHONY: setup_dirs asic-flist romlibs-check romlibs-fetch cpf-patch sdc-check \
        syn syn_norun syn_eval syn_compare \
        lec lec-pnr lec-gate lec-selftest \
        pnr_place pnr_cts pnr_route pnr_all pnr_setup gui \
        drc lvs lvs-preflight \
        status clean distclean help

setup_dirs:
	mkdir -p $(REPORT_DIR) $(LOG_DIR) $(OUT_DIR) $(WORK_DIR)

## Re-render the generated sub-flists every run, so the TideLink V2 / SoC
## selection cannot go stale. Delegated: the top-level make sources the three
## set_env.sh scripts in dependency order.
asic-flist:
	$(MAKE) -C $(NANOSOC_ETH_CHIPLET_HOME) --no-print-directory asic-flist

## Genus reads the ROM .libs via config.tcl's lib_search_path_list; without them
## `syn` dies inside set_db with "Cannot open file rom_via_*.lib".
romlibs-check:
	@$(MAKE) -C $(DESIGN_DIR)/.. -f common.mk --no-print-directory romlibs-verify || { \
	    echo ""; \
	    echo "The ROM libraries are not built. Build them with:"; \
	    echo "    make -C $(DESIGN_DIR)/.. -f common.mk tsmc_65_romlibs MEM_COMPILER_DIR=PATH_TO_COMPLETE_PHYS_IP"; \
	    echo "This needs (a) the bootloader firmware built, for the ROM code_files, and"; \
	    echo "(b) a WORKING Arm mem compiler — see the MEM_COMPILER_DIR note in common.mk."; \
	    exit 1; }

## Repair the CPF Genus writes, so the die actually gets filled. Genus cannot
## translate this design's UPF supply commands and emits a power domain with no
## power or ground net; every Innovus filler pass then dies with IMPSP-5110
## while the flow still completes and streams a GDS. Not fixable from Innovus —
## these are CPF statements. Idempotent. See 06-fill-antenna-bondpads.md.
cpf-patch:
	@cpf=$(OUT_DIR)/$(BLOCK)_gate1.cpf; \
	test -s "$$cpf" || { echo "FAIL: no CPF at $$cpf — did synthesis run?"; exit 1; }; \
	if grep -q 'create_power_nets' "$$cpf"; then \
	    echo "OK: CPF already carries its supply nets"; \
	else \
	    grep -q 'end_design' "$$cpf" || { echo "FAIL: $$cpf has no end_design — unexpected format"; exit 1; }; \
	    sed -i 's/^end_design/create_ground_nets -nets VSS\ncreate_power_nets -nets VDD\n\nupdate_power_domain -name PD_TOP -primary_power_net VDD -primary_ground_net VSS\n\nend_design/' "$$cpf"; \
	    grep -q 'update_power_domain' "$$cpf" || { echo "FAIL: CPF patch did not apply"; exit 1; }; \
	    echo "OK: patched $$cpf with VDD/VSS supply nets (add_fillers needs them)"; \
	fi

#-----------------------------------------------------------------------------
# Synthesis
#-----------------------------------------------------------------------------
## The artefact test is not belt-and-braces: Genus exits ZERO on a failed script,
## so without it `pnr_all` runs P&R on a netlist that was never written.
syn: setup_dirs asic-flist romlibs-check
	cd $(WORK_DIR)/; genus -f $(ASIC_FLOWS_DIR)/1_synthesis.tcl -log $(LOG_DIR)/syn_logs
	@$(MAKE) --no-print-directory cpf-patch
	@test -s $(OUT_DIR)/$(BLOCK)_gate_power.v || { \
	    echo "FAIL: synthesis produced no netlist at $(OUT_DIR)/$(BLOCK)_gate_power.v"; \
	    echo "      find the real error with:"; \
	    echo "        grep -nE 'Encountered problems|^Error|not set' $(LOG_DIR)/syn_logs.log*"; \
	    exit 1; }
	@echo "OK: netlist $(OUT_DIR)/$(BLOCK)_gate_power.v"

## Interactive Genus in work/; reloads the saved syn session.
syn_norun:
	cd $(WORK_DIR)/; genus -log $(LOG_DIR)/syn_logs

## A/B variant of synthesis, via scripts/1b_synthesis_eval.tcl. Writes to
## logs|reports|outputs/eval, so it cannot clobber the baseline P&R inputs.
## Each behaviour change is a knob, so it can be isolated:
##     make syn_eval EVAL_ISPATIAL=1        # physical synthesis
##     make syn_eval EVAL_DRV_FIX=1 EVAL_MAX_TRAN=0.60   # tighten DRV; see the
##                                          # CONFIGURATION block before trusting
##     make syn_eval EVAL_COST_GROUPS=0
## To promote a result, redirect it at the real output dir — P&R takes its
## constraints from outputs/$(BLOCK)_syn.sdc, which an eval run never writes:
##     make syn_eval EVAL_OUT_DIR=$(OUT_DIR) && make cpf-patch
##
## THE OVERRIDE MUST BE ABSOLUTE. This line used to read `EVAL_OUT_DIR=../outputs`
## and that is a TRAP, because the variable is consumed in TWO DIFFERENT working
## directories: genus runs under `cd $(WORK_DIR)` (so ../outputs = the right
## place) but the mkdir and the netlist assertion below run in $(DESIGN_DIR)
## (so ../outputs = ASIC/outputs, one level too high). The 2026-08-07 eval run
## synthesised for 1h38m, wrote a perfectly good netlist, then failed its own
## "produced no netlist" assertion against an empty directory it had just
## created in the wrong place — and took the whole P&R chain down with it.
## The guard below turns that silent hour into an immediate error.
EVAL_LOG_DIR    ?= $(LOG_DIR)/eval
EVAL_REPORT_DIR ?= $(REPORT_DIR)/eval
EVAL_OUT_DIR    ?= $(OUT_DIR)/eval

EVAL_RELDIRS := $(filter-out /%,$(EVAL_LOG_DIR) $(EVAL_REPORT_DIR) $(EVAL_OUT_DIR))
ifneq ($(EVAL_RELDIRS),)
$(error EVAL_*_DIR must be ABSOLUTE, got: $(EVAL_RELDIRS). \
  genus runs in $(WORK_DIR) but the assertions run in $(DESIGN_DIR), so a \
  relative path names two different directories. Use EVAL_OUT_DIR=$(OUT_DIR))
endif

syn_eval: setup_dirs asic-flist romlibs-check
	mkdir -p $(EVAL_LOG_DIR) $(EVAL_REPORT_DIR) $(EVAL_OUT_DIR)
	cd $(WORK_DIR)/; \
	    EVAL_LOG_DIR=$(EVAL_LOG_DIR) \
	    EVAL_REPORT_DIR=$(EVAL_REPORT_DIR) \
	    EVAL_OUT_DIR=$(EVAL_OUT_DIR) \
	    genus -f $(DESIGN_DIR)/scripts/1b_synthesis_eval.tcl \
	          -log $(EVAL_LOG_DIR)/syn_logs
	@test -s $(EVAL_OUT_DIR)/$(BLOCK)_gate_power.v || { \
	    echo "FAIL: eval synthesis produced no netlist at $(EVAL_OUT_DIR)/$(BLOCK)_gate_power.v"; \
	    echo "      grep -nE 'EVAL-FAIL|Encountered problems|^Error' $(EVAL_LOG_DIR)/syn_logs.log*"; \
	    exit 1; }
	@echo "OK: eval netlist $(EVAL_OUT_DIR)/$(BLOCK)_gate_power.v — now: make syn_compare"

## Side-by-side metrics for the baseline and eval runs. Override either side.
SYN_CMP_A ?= $(DESIGN_DIR)/baseline_2026-08-05/reports
SYN_CMP_B ?= $(EVAL_REPORT_DIR)

syn_compare:
	@$(DESIGN_DIR)/scripts/compare_syn.sh $(SYN_CMP_A) $(SYN_CMP_B)

#-----------------------------------------------------------------------------
# Equivalence checking (Conformal) — see 13-lec.md
#-----------------------------------------------------------------------------
## RTL vs the SYNTHESIS netlist, via the dofile synthesis writes into work/ (so
## run `make syn` first). Two flaws to know: it reads only _gate.v, never the
## post-P&R netlist, and its dofile ends `exit -f`, so a NON-EQUIVALENT result
## still exits 0 — grep the log for "Compare Results:". lec-pnr has neither.
lec:
	cd $(WORK_DIR)/; lec -xl -Dofile ./lec.dofile

## Post-P&R equivalence: _gate_power.v (golden — it shares _pnr.v's 27-port
## boundary and PG convention, _gate.v does not) vs _pnr.v, the netlist that
## becomes GDS. Flat compare only, hours, holds a Conformal seat. Exits non-zero
## on abort, non-equivalence, unmapped points or a short log.
lec-pnr:
	$(DESIGN_DIR)/scripts/lec/run_lec.sh pnr

## Closes the joint in the chain: _gate.v (what `lec` proves against RTL) vs
## _gate_power.v (what lec-pnr uses as golden).
lec-gate:
	$(DESIGN_DIR)/scripts/lec/run_lec.sh gate

## Mutation-tests the LEC harness itself in ~15s. Run before trusting any
## lec-pnr result on a new host.
lec-selftest:
	$(DESIGN_DIR)/scripts/lec/run_lec.sh selftest

#-----------------------------------------------------------------------------
# Place and route (Innovus)
#-----------------------------------------------------------------------------
## -files, NOT -f (despite the stage-script headers): Stylus rejects -f with
## IMPSYT-468, prints usage, and exits ZERO.
INNOVUS := innovus -stylus -files

## The three stages share one DB in work/ and must run in order; resume a
## part-finished flow by invoking the stage you stopped at.
##   pnr_place : floorplan + power plan + place + tie-offs   (2_pnr_setup)
##   pnr_cts   : clock tree synthesis + post-CTS opt         (3_pnr_clock)
##   pnr_route : route + filler + bondpads + GDS + reports   (4_pnr_route)
## Refuse to place against constraints synthesis has never seen. P&R does NOT
## read inputs/*.sdc: scripts/$(BLOCK).mmmc feeds it outputs/$(BLOCK)_syn.sdc,
## the SDC that SYNTHESIS writes. So editing a constraint and re-running
## pnr_place changes precisely nothing, with no warning — which is the state
## this tree was in on 2026-08-07 (four inputs/*.sdc edited that afternoon
## against a _syn.sdc from 08-05). Override with SDC_STALE_OK=1.
sdc-check:
	@syn_sdc=$(OUT_DIR)/$(BLOCK)_syn.sdc; \
	test -s "$$syn_sdc" || { \
	    echo "FAIL: no $$syn_sdc — P&R takes its constraints from that file."; \
	    echo "      Run 'make syn' first."; exit 1; }; \
	newer=$$(find $(DESIGN_DIR)/inputs -name '*.sdc' -newer "$$syn_sdc" -printf '  inputs/%P\n' 2>/dev/null); \
	if [ -n "$$newer" ] && [ "$(SDC_STALE_OK)" != "1" ]; then \
	    echo "FAIL: these constraints are NEWER than the SDC place-and-route will use:"; \
	    echo "$$newer"; \
	    echo "      P&R reads $$syn_sdc (via scripts/$(BLOCK).mmmc), not inputs/."; \
	    echo "      Re-run 'make syn' to regenerate it, or pass SDC_STALE_OK=1."; \
	    exit 1; \
	fi; \
	echo "OK: $(BLOCK)_syn.sdc is at least as new as every inputs/*.sdc"

## cpf-patch is idempotent and cheap; running it here means a hand-run or
## resumed placement cannot proceed on an unpatched CPF. See power_plan.tcl.
pnr_place: setup_dirs sdc-check cpf-patch
	cd $(WORK_DIR)/; $(INNOVUS) $(ASIC_FLOWS_DIR)/2_pnr_setup.tcl
	@test -d $(WORK_DIR)/$(BLOCK) || { \
	    echo "FAIL: placement wrote no DB at $(WORK_DIR)/$(BLOCK)"; exit 1; }

pnr_cts:
	cd $(WORK_DIR)/; $(INNOVUS) $(ASIC_FLOWS_DIR)/3_pnr_clock.tcl
	@test -s $(REPORT_DIR)/timing_summary_03_cts_opt.rep || { \
	    echo "FAIL: CTS wrote no post-opt timing summary — stage did not complete."; exit 1; }

## CALIBRE_HOME is unset deliberately. 4_pnr_route.tcl's two trailing
## $env(CALIBRE_HOME) blocks both fail on this site, and the failing `exec`
## aborts the script before its `exit` — Innovus then sits at a prompt holding a
## seat, so make never returns. Everything of value is written before them, and
## `make drc` is the working Calibre path. Fixed here rather than in asic-flows,
## which other designs share.
pnr_route:
	cd $(WORK_DIR)/; env -u CALIBRE_HOME $(INNOVUS) $(ASIC_FLOWS_DIR)/4_pnr_route.tcl
	@test -s $(OUT_DIR)/$(BLOCK).gds \
	    && echo "OK: GDSII $(OUT_DIR)/$(BLOCK).gds ($$(du -h $(OUT_DIR)/$(BLOCK).gds | cut -f1))" \
	    || { echo "FAIL: no GDSII at $(OUT_DIR)/$(BLOCK).gds"; \
	         echo "      grep -nE '\*\*ERROR|Unknown argument' $(WORK_DIR)/innovus.log*"; \
	         echo "      if the log looks clean, check ASIC/asic-flows is at b19e784+"; \
	         echo "      — write_stream lives there; the earlier pin streams nothing."; \
	         exit 1; }

## syn -> place -> CTS -> route -> GDSII, unattended. Multi-hour.
pnr_all: syn pnr_place pnr_cts pnr_route

## Interactive Innovus in work/, empty session — no config, no design.
pnr_setup:
	cd $(WORK_DIR)/; innovus -stylus

## Interactive Innovus with config.tcl sourced and the saved DB read — the one
## for inspecting a stage. In pnr_setup a bare read_db fails, because the block
## name and every library path live in config.tcl.
gui:
	@# Probe the display for real: a malformed DISPLAY ("12.0", no leading colon)
	@# passes `test -n`, and Innovus then falls back to no-window mode with a WARN.
	@test -n "$$DISPLAY" || { \
	    echo "FAIL: DISPLAY is not set in THIS shell. A ThinLinc desktop's DISPLAY"; \
	    echo "      does not reach a VS Code Remote-SSH terminal — run make from a"; \
	    echo "      terminal inside the desktop, or 'ssh -X <host>'."; \
	    echo "      Text-mode session on purpose?   make pnr_setup"; \
	    exit 1; }
	@xdpyinfo >/dev/null 2>&1 || { \
	    echo "FAIL: DISPLAY='$$DISPLAY' but no X server answers there, so Innovus"; \
	    echo "      would start in no-window mode (IMPSYT-1507)."; \
	    case "$$DISPLAY" in \
	      [0-9]*) echo "      It is missing the leading colon. Try: export DISPLAY=:$$DISPLAY" ;; \
	      *)      echo "      Check the session is still alive: xdpyinfo | head -3" ;; \
	    esac; \
	    exit 1; }
	@echo "OK: DISPLAY=$$DISPLAY (X server responded)"
	@test -d $(WORK_DIR)/$(BLOCK) || { \
	    echo "FAIL: no saved DB at $(WORK_DIR)/$(BLOCK) — run 'make pnr_place' first."; exit 1; }
	@# gui_show is required, not decoration: launched with -files, Innovus creates
	@# its main window but never maps it, so the GUI appears not to exist at all.
	@printf '%s\n' \
	    'source ../scripts/config.tcl' \
	    'read_db $(BLOCK)' \
	    'if {[catch {gui_show} e]} { puts stderr "WARNING: gui_show failed: $$e" }' \
	    'puts "== $(BLOCK) loaded, GUI shown — this is the last-written DB =="' \
	    > $(WORK_DIR)/open_db.tcl
	cd $(WORK_DIR)/; $(INNOVUS) open_db.tcl

#-----------------------------------------------------------------------------
# Physical verification (Calibre) — see 12-calibre-drc.md, 14-drc-triage.md
#-----------------------------------------------------------------------------
## Calibre DRC on the built GDS, headless. The foundry deck's LAYOUT PATH /
## LAYOUT PRIMARY are literal placeholders with no command-line override, so both
## come from the project wrapper deck in scripts/calibre/, which INCLUDEs the
## foundry deck untouched. run_drc.sh does its own preflight.
##
## CAVEAT ON ANY NUMBER THIS PRODUCES: the GDS carries routing, vias and macros
## but no standard-cell, IO or bond-pad geometry, no seal ring and no fill, so
## front-end, density and seal-ring rules are meaningless here. The back-end
## metal/via/antenna checks are the real signal.
drc:
	DRC_GDS=$(GDS) DRC_RUNDIR=$(DRC_RUNDIR) DRC_CPUS=$(DRC_CPUS) \
	    $(DESIGN_DIR)/scripts/calibre/run_drc.sh

## Does this host have what LVS needs? Seconds, no tool launched. Expected to
## FAIL today and to say why: every TSMC package installed here is Front End
## (_FE), so there is no transistor netlist for cells, IO or pads. Procurement,
## not engineering. See docs/TSMC_BACKEND_PACKAGE_REQUEST.md.
lvs-preflight:
	$(DESIGN_DIR)/scripts/calibre/run_lvs.sh --check

## Calibre nmLVS, gated on lvs-preflight so it fails with the missing-data list
## rather than an obscure tool error. The GDS is incomplete for the same reason
## (424 cell masters are LEF shells), so both unblock together.
lvs: lvs-preflight
	$(DESIGN_DIR)/scripts/calibre/run_lvs.sh --run \
	    $(GDS) $(OUT_DIR)/$(BLOCK)_pnr.v $(BLOCK) $(WORK_DIR) $(LOG_DIR)

#-----------------------------------------------------------------------------
# Housekeeping
#-----------------------------------------------------------------------------
## Copy the built ROM libraries from a reference tree; override with ROMLIBS_REF.
romlibs-fetch:
	@test -d "$(ROMLIBS_REF)" || { \
	    echo "FAIL: no ROM-lib reference tree at $(ROMLIBS_REF)"; \
	    echo "      point ROMLIBS_REF at a tree holding cc_rom/ and eth_rom/."; exit 1; }
	@echo "== copying ROM libs from $(ROMLIBS_REF) =="
	mkdir -p $(ROMLIBS_DIR)
	cp -r $(ROMLIBS_REF)/cc_rom $(ROMLIBS_REF)/eth_rom $(ROMLIBS_DIR)/
	@$(MAKE) --no-print-directory romlibs-check

## Which flow stages have actually run, from the artefacts on disk.
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

## Drop the rerunnable intermediates; keeps outputs/ and reports/, so a finished
## GDS and its sign-off reports survive.
clean:
	@echo "removing $(WORK_DIR) and $(LOG_DIR) (outputs/ and reports/ kept)"
	rm -rf $(WORK_DIR) $(LOG_DIR)

## clean, plus outputs/ and reports/ — DELETES the GDS.
distclean:
	@echo "about to remove work/ logs/ outputs/ reports/ — including:"
	@test -s $(GDS) && echo "  !! $(GDS) ($$(du -h $(GDS) | cut -f1))" || true
	@du -sh $(OUT_DIR) $(REPORT_DIR) 2>/dev/null | sed 's/^/  /' || true
	rm -rf $(WORK_DIR) $(LOG_DIR) $(OUT_DIR) $(REPORT_DIR)

help:
	@echo "nanosoc_eth_chiplet ASIC flow — Genus + Innovus + Calibre (TSMC 65nm)"
	@echo ""
	@echo "  Flow, in order:"
	@echo "    make syn           synthesis (Genus)          -> outputs/$(BLOCK)_gate*.v"
	@echo "    make pnr_place     floorplan + place          (Innovus)"
	@echo "    make pnr_cts       clock tree synthesis       (Innovus)"
	@echo "    make pnr_route     route + fill + GDSII       -> $(GDS)"
	@echo "    make drc           Calibre DRC on that GDS    (headless)"
	@echo ""
	@echo "    make pnr_all       syn + all three P&R stages, unattended. Multi-hour."
	@echo ""
	@echo "  The stages share a DB in work/ and MUST run in order. To resume a"
	@echo "  part-finished flow, invoke the stage you stopped at — 'make status'"
	@echo "  shows which ones have run."
	@echo ""
	@echo "  Verification:"
	@echo "    make lec           Conformal: RTL vs synthesis netlist"
	@echo "    make lec-pnr       Conformal: synthesis vs post-P&R netlist"
	@echo "    make lec-selftest  mutation-test the LEC harness (~15s)"
	@echo "    make lvs           Calibre LVS   (lvs-preflight says what is missing)"
	@echo ""
	@echo "  Synthesis A/B:"
	@echo "    make syn_eval      variant run   -> outputs/eval/"
	@echo "    make syn_compare   diff syn vs syn_eval metrics"
	@echo ""
	@echo "  Setup / inspection:"
	@echo "    make status        which stages have run"
	@echo "    make romlibs-fetch copy the built ROM libs (they cannot be built here)"
	@echo "    make asic-flist    re-render the generated sub-flists"
	@echo "    make gui           Innovus with config + saved DB loaded"
	@echo "    make clean         drop work/ + logs/   (keeps the GDS)"
	@echo "    make distclean     also drop outputs/ + reports/  (DELETES the GDS)"
	@echo ""
	@echo "  Needs: TSMC_65_HOME=$(TSMC_65_HOME)"
	@echo "         SOCLABS_ASIC_FLOW_DIR=$(SOCLABS_ASIC_FLOW_DIR)"
	@echo "         both exported by ../common.mk; override in the environment."
