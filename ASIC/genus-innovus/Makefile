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

#-----------------------------------------------------------------------------
# DEPRECATED: syn / pnr_place / pnr_cts / pnr_route -- the LEGACY ENGINE
#
# Those four targets, and only those four, drive $(ASIC_FLOWS_DIR) -- the
# ../asic-flows submodule, which is lab-shared and pinned. They are Step 3 of
# docs/tapeout/41-retiring-asic-flows.md: FROZEN, NOT DELETED. They still run.
#
# WHAT REPLACES THEM (../asic-toolkit/mk/flow.mk):
#
#     make syn        ->  make -C ASIC/eth-chiplet syn      (flow.mk syn)
#     make pnr_place  ->  make -C ASIC/eth-chiplet place    (flow.mk place)
#     make pnr_cts    ->  make -C ASIC/eth-chiplet cts      (flow.mk cts)
#     make pnr_route  ->  make -C ASIC/eth-chiplet route    (flow.mk route)
#     make pnr_all    ->  make -C ASIC/eth-chiplet all      (flow.mk all)
#
# BE ACCURATE ABOUT WHAT THIS FALLBACK IS. It is a second ENGINE. It is not a
# second OPINION, and it never has been: ../eth-chiplet/design.mk defines
# LEGACY_ASIC_DIR as THIS directory and takes ten design inputs from it --
# floorplan.tcl, power_plan.tcl, the .mmmc, the .io, the .upf power intent,
# place_bondpads.tcl, every inputs/*.sdc, SDC_DIR and the Calibre run_drc.sh.
# Both flows have therefore always read ONE copy of every design file. Running
# the legacy path and the toolkit path over the same design and comparing tells
# you about the two engines and NOTHING about the design data, so a legacy run
# must never be quoted as corroborating a toolkit result. There is no control
# here to lose, which is also why deleting these four targets loses no control.
#
# WHY THEY ARE STILL HERE. Not because they are a check -- see above -- but
# because the four things that would actually justify deleting them are not yet
# true. 41-retiring-asic-flows.md section 4 lists them; re-measure before
# quoting it, the doc is dated.
#
# WHAT IS *NOT* DEPRECATED IN THIS DIRECTORY: everything else. drc, lec*, rail,
# romlibs*, the *_eval stages, gdsmap, restream and lvs* are owned here, are
# what CI invokes, and none of them touches ../asic-flows. Retiring asic-flows
# and retiring genus-innovus are different changes with different blast radii;
# this notice is only about the first.
#-----------------------------------------------------------------------------
define legacy_notice
@printf '  %s\n' \
  "" \
  "-- DEPRECATED ------------------------------------------------------------" \
  "'make $(1)' drives the LEGACY engine: $(ASIC_FLOWS_DIR)" \
  "Replacement:  make -C $(abspath $(DESIGN_DIR)/../eth-chiplet) $(2)" \
  "" \
  "It still runs, and it is NOT a second opinion. ../eth-chiplet/design.mk" \
  "points the toolkit at THIS directory for the floorplan, power plan, mmmc," \
  "io, upf, bondpads, every SDC and the DRC deck, so both flows read ONE copy" \
  "of every design file. A legacy run cannot corroborate a toolkit run." \
  "" \
  "Every shipping artefact is under ../eth-chiplet/build/. This tree's" \
  "outputs/ holds no netlist and no GDS." \
  "docs/tapeout/41-retiring-asic-flows.md" \
  "--------------------------------------------------------------------------" \
  ""
endef

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

.PHONY: setup_dirs asic-flist romlibs-check romlibs-fetch cpf-patch _cpf-patch-one sdc-check \
        syn syn_norun syn_eval syn_compare \
        lec lec-pnr lec-gate lec-selftest route-gate-selftest \
        pnr_place pnr_cts pnr_route pnr_all pnr_setup gui \
        pnr_place_eval pnr_cts_eval pnr_route_eval pnr_all_eval \
        drc lvs lvs-preflight logo drc-logo \
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
## PATCHES EVERY CPF, NOT JUST $(OUT_DIR)'s. syn_eval writes its outputs to
## $(OUT_DIR)/eval, and pnr_place_eval depends on this target — so patching only
## $(OUT_DIR) left the eval CPF untouched. Measured 2026-08-10: every gate1.cpf
## under outputs/ is 730 b and patched; every one under outputs/eval/ is 591 b
## and is not. power_plan.tcl:49 then aborts with "is UNPATCHED — no
## create_power_nets", so NO POWER GRID IS BUILT — and because the PG probe's
## step wrapper swallowed the error, the probe still reached its summary and
## exited 0, reporting numbers for a design that had no special routing at all.
## A missing supply net must never be a silent pass.
cpf-patch:
	@for cpf in $(OUT_DIR)/$(BLOCK)_gate1.cpf $(EVAL_OUT_DIR)/$(BLOCK)_gate1.cpf; do \
	    test -s "$$cpf" || continue; \
	    $(MAKE) --no-print-directory _cpf-patch-one CPF="$$cpf" || exit 1; \
	done; \
	test -s $(OUT_DIR)/$(BLOCK)_gate1.cpf -o -s $(EVAL_OUT_DIR)/$(BLOCK)_gate1.cpf || { \
	    echo "FAIL: no CPF at $(OUT_DIR) or $(EVAL_OUT_DIR) — did synthesis run?"; exit 1; }

_cpf-patch-one:
	@cpf=$(CPF); \
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
	$(call legacy_notice,syn,syn)
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

## Mutation-tests the route gate's report parsers. Seconds, plain tclsh, no EDA
## licence. It existed untracked with no way to run it, which is how the census
## hole below survived: a DRC record naming only "Blockage of Cell" - no Wire,
## no Pin - matched no class, so the gate printed "HARD FAILURES: none" on a
## 265-violation run. pnr_route_eval depends on this: a gate nobody has seen
## fail is not evidence.
route-gate-selftest:
	tclsh $(DESIGN_DIR)/scripts/selftest_route_gate.tcl

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
	$(call legacy_notice,pnr_place,place)
	cd $(WORK_DIR)/; $(INNOVUS) $(ASIC_FLOWS_DIR)/2_pnr_setup.tcl
	@test -d $(WORK_DIR)/$(BLOCK) || { \
	    echo "FAIL: placement wrote no DB at $(WORK_DIR)/$(BLOCK)"; exit 1; }

pnr_cts:
	$(call legacy_notice,pnr_cts,cts)
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
	$(call legacy_notice,pnr_route,route)
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

#-----------------------------------------------------------------------------
# P&R evaluation flow — scripts/{2b,3b,4b}_*_eval.tcl + scripts/pnr_utils.tcl
#-----------------------------------------------------------------------------
## A/B variants of the three P&R stages, the way syn_eval is to syn. Each writes
## to logs|reports|outputs/eval and to the $(BLOCK)_eval_* DB namespace, so an
## eval run CANNOT disturb work/$(BLOCK), the production snapshots, or the
## shipped GDS. Every behavioural difference is one knob.
##
## The stages share the eval DB and run in order, but each takes its INPUT DB
## from a knob — so the usual mode is to resume a production snapshot rather
## than re-run hours of upstream work:
##     make pnr_cts_eval   EVC_IN_PREFIX=$(BLOCK)   # resume the real placement
##     make pnr_route_eval EVR_IN_PREFIX=$(BLOCK)   # resume the real CTS run
##
## Knob prefixes are per stage: EVP_ (place), EVC_ (CTS), EVR_ (route).
## Every knob lands in the stage manifest automatically, so a result can always
## be traced back to the settings that produced it.
##
## No `env -u CALIBRE_HOME` on pnr_route_eval: unlike 4_pnr_route.tcl, the eval
## script does not shell out to Calibre at all, so the trap that makes the
## production stage hang on a held licence seat does not exist here.
pnr_place_eval: setup_dirs cpf-patch
	mkdir -p $(EVAL_LOG_DIR) $(EVAL_REPORT_DIR) $(EVAL_OUT_DIR)
	cd $(WORK_DIR)/; \
	    EVP_LOG_DIR=$(EVAL_LOG_DIR) \
	    EVP_REPORT_DIR=$(EVAL_REPORT_DIR) \
	    EVP_OUT_DIR=$(EVAL_OUT_DIR) \
	    $(INNOVUS) $(DESIGN_DIR)/scripts/2b_pnr_place_eval.tcl < /dev/null
	@# Artefact assertions, never $?. Three of them, because any one alone can
	@# exist for the wrong reason. The manifest is written in the LAST section,
	@# so its presence is what proves the script reached the end.
	@test -d $(WORK_DIR)/$(BLOCK)_eval_placed || { \
	    echo "FAIL: eval placement wrote no DB at $(WORK_DIR)/$(BLOCK)_eval_placed"; \
	    echo "      grep -nE 'EVPLACE-FAIL|\*\*ERROR' $(WORK_DIR)/innovus.log*"; \
	    exit 1; }
	@test -s $(EVAL_REPORT_DIR)/timing_summary_01_place.rep || { \
	    echo "FAIL: no 01_place timing summary — stage stopped before placement"; exit 1; }
	@test -s $(EVAL_REPORT_DIR)/place_manifest.txt || { \
	    echo "FAIL: no manifest — the script did not reach its final section"; exit 1; }
	@echo "OK: eval placement $(WORK_DIR)/$(BLOCK)_eval_placed"
	@echo "    read $(EVAL_REPORT_DIR)/place_manifest.txt, then place_pg_audit.rep"

pnr_cts_eval: setup_dirs
	mkdir -p $(EVAL_LOG_DIR) $(EVAL_REPORT_DIR) $(EVAL_OUT_DIR)
	cd $(WORK_DIR)/; \
	    EVC_LOG_DIR=$(EVAL_LOG_DIR) \
	    EVC_REPORT_DIR=$(EVAL_REPORT_DIR) \
	    EVC_OUT_DIR=$(EVAL_OUT_DIR) \
	    $(INNOVUS) $(DESIGN_DIR)/scripts/3b_pnr_cts_eval.tcl < /dev/null
	@test -d $(WORK_DIR)/$(BLOCK)_eval_cts || { \
	    echo "FAIL: no eval CTS database at $(WORK_DIR)/$(BLOCK)_eval_cts"; \
	    echo "      grep -nE 'EVCTS-FAIL|\*\*ERROR' $(WORK_DIR)/innovus.log*"; \
	    exit 1; }
	@# The source-latency census must have RUN. A missing census is not a pass.
	@test -s $(EVAL_REPORT_DIR)/cts_latency_writeback.rep || { \
	    echo "FAIL: no source-latency census — this run is UNVERIFIED, not passing."; exit 1; }
	@# ...and must have PASSED: the hold view needs -max, and -max must match -min.
	@# Deliberately duplicated outside the tool, so it survives the script being
	@# edited. This is the 2026-08-06 defect: 96,545 phantom hold violations.
	@awk '$$1=="default_analysis_view_hold" && $$2=="TOTAL" { \
	        if ($$4+0 > 0 && $$4+0 == $$3+0) ok=1 } END { exit !ok }' \
	    $(EVAL_REPORT_DIR)/cts_latency_writeback.rep || { \
	    echo "FAIL: hold-view source-latency writeback is missing its -max side."; \
	    echo "      scripts/cts_setup.tcl must set timing_analysis_type ocv BEFORE ccopt."; \
	    echo "      $(EVAL_REPORT_DIR)/cts_latency_writeback.rep"; exit 1; }
	@echo "OK: eval CTS $(WORK_DIR)/$(BLOCK)_eval_cts"
	@echo "    read $(EVAL_REPORT_DIR)/cts_latency_writeback.rep"

pnr_route_eval: setup_dirs
	mkdir -p $(EVAL_LOG_DIR) $(EVAL_REPORT_DIR) $(EVAL_OUT_DIR)
	cd $(WORK_DIR)/; \
	    EVR_LOG_DIR=$(EVAL_LOG_DIR) \
	    EVR_REPORT_DIR=$(EVAL_REPORT_DIR) \
	    EVR_OUT_DIR=$(EVAL_OUT_DIR) \
	    $(INNOVUS) $(DESIGN_DIR)/scripts/4b_pnr_route_eval.tcl < /dev/null
	@# The script's own gate is the verdict; these catch the case where it never
	@# reached the gate at all.
	@test -s $(EVAL_REPORT_DIR)/route_gate.txt || { \
	    echo "FAIL: no gate verdict at $(EVAL_REPORT_DIR)/route_gate.txt —"; \
	    echo "      the stage did not reach its final section."; \
	    echo "      grep -nE 'EVROUTE-FAIL|\*\*ERROR' $(WORK_DIR)/innovus.log*"; \
	    exit 1; }
	@test -s $(EVAL_OUT_DIR)/$(BLOCK).gds || { echo "FAIL: no GDSII at $(EVAL_OUT_DIR)/$(BLOCK).gds"; exit 1; }
	@test -s $(EVAL_OUT_DIR)/$(BLOCK)_pnr.v || { \
	    echo "FAIL: no post-P&R netlist — lec-pnr and LVS would have no input"; exit 1; }
	@grep -q '^HARD FAILURES: none' $(EVAL_REPORT_DIR)/route_gate.txt || { \
	    echo "FAIL: hard failures — see $(EVAL_REPORT_DIR)/route_gate.txt"; \
	    sed -n '/^HARD FAILURES/,/^$$/p' $(EVAL_REPORT_DIR)/route_gate.txt; exit 1; }
	@echo "OK: eval GDSII $(EVAL_OUT_DIR)/$(BLOCK).gds ($$(du -h $(EVAL_OUT_DIR)/$(BLOCK).gds | cut -f1))"
	@sed -n '/^SIGNOFF BUDGETS/,/^$$/p' $(EVAL_REPORT_DIR)/route_gate.txt

## place -> CTS -> route, all three eval stages. Multi-hour.
pnr_all_eval: pnr_place_eval pnr_cts_eval pnr_route_eval

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

#-----------------------------------------------------------------------------
# Logo merge (klayout — no EDA licence)
#-----------------------------------------------------------------------------
## Merges the shuttle logo into a streamed GDS. Deliberately a SEPARATE step
## from write_stream, not an entry in gds_merge_list: the un-logoed stream stays
## the signoff artefact and the logoed one is the submission artefact, so a DRC
## count can never be quoted against the wrong file.
##
## STRIP THE JACK BY DEFAULT. The broker requires the 158/LOGO marker, and in
## the foundry deck 158 is NOT passive:
##     LOGO.S.1  min clearance LOGO -> OD/PO/M1..M9 = 10.0um   (deck :20450)
##     LOGO.R.4  OD/PO/M1x..M9x CUT LOGO is not allowed        (deck :20498)
## The full 727.75x320.25um logo therefore needs 747.75x340.25um clear of ALL
## routing. Measured 2026-08-10: dropped at die centre it cost >= 2020 extra DRC
## results (2509 -> 4529), with LOGO.S.1 and LOGO.R.4 both SATURATED at the
## 1000-result cap, landing on an rf_01k register file. Text-only is
## 360.25x290.25um and needs 380.25x310.25um — a keep-out a floorplan can host.
LOGO_GDS        ?= $(DESIGN_DIR)/logos/nanosoc_eth_Logo.gds
LOGO_STRIP_JACK ?= 0
## PLACEMENT. LOGO_X is the logo's bbox CENTRE, not its left edge — the cell is
## drawn centred on its own origin, so anchoring by corner would silently offset
## it by half its width. 663.875 puts the FULL logo (727.75x320.25um) at
## (300.0,839.9)-(1027.8,1160.1), i.e. left edge exactly x=300, chosen off the
## AP view as the gap between the upper and lower block clusters.
##   leftmost legal centre with the jack kept = 135 + 363.875 = 498.875
##   anything below that is rejected by merge_logo.py: at LOGO_X=300 the left
##   edge lands at -63.9, off the die and inside the pad band.
##
## STRIP_JACK defaults OFF: the pictures are wanted. Keeping them costs a bigger
## LOGO.S.1 keep-out (747.75x340.25um vs 380.25x310.25 text-only), which the
## floorplan must reserve rather than the merge step avoid.
LOGO_X          ?= 663.875
LOGO_Y          ?= 1000.0
LOGO_SRC        := $(if $(filter 1,$(LOGO_STRIP_JACK)),$(OUT_DIR)/logo_text.gds,$(LOGO_GDS))
LOGO_GDS_OUT    ?= $(OUT_DIR)/$(BLOCK)_logo.gds

## make logo                 — merge into the current $(GDS)
## make logo LOGO_X=700      — move it
## make logo LOGO_STRIP_JACK=0 — keep the ethernet jack (expect LOGO.S.1 to fire)
logo:
	@test -s $(GDS) || { echo "FAIL: no GDS at $(GDS) — run 'make pnr_route' first."; exit 1; }
	@test -s $(LOGO_GDS) || { echo "FAIL: no logo GDS at $(LOGO_GDS)"; exit 1; }
	@mkdir -p $(OUT_DIR)
ifeq ($(LOGO_STRIP_JACK),1)
	klayout -b -r $(DESIGN_DIR)/scripts/strip_logo_jack.py \
	    -rd inp=$(LOGO_GDS) -rd out=$(LOGO_SRC) < /dev/null
endif
	klayout -b -r $(DESIGN_DIR)/scripts/merge_logo.py \
	    -rd chip=$(GDS) -rd logo=$(LOGO_SRC) -rd out=$(LOGO_GDS_OUT) \
	    -rd x=$(LOGO_X) -rd y=$(LOGO_Y) < /dev/null
	@test -s $(LOGO_GDS_OUT) || { echo "FAIL: no merged GDS at $(LOGO_GDS_OUT)"; exit 1; }
	@echo "OK: $(LOGO_GDS_OUT)"
	@echo "    signoff artefact stays $(GDS) — DRC that one too, and quote them separately"

## DRC the SUBMISSION artefact. Own rundir, so it never overwrites the signoff
## run's results and the two counts can be compared.
drc-logo: logo
	DRC_GDS=$(LOGO_GDS_OUT) DRC_RUNDIR=$(WORK_DIR)/../calibre_runs/drc_logo_flow \
	DRC_CPUS=$(DRC_CPUS) $(DESIGN_DIR)/scripts/calibre/run_drc.sh

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
	    "drc:$(DRC_RUNDIR)" \
	    "place-eval:$(EVAL_REPORT_DIR)/place_manifest.txt" \
	    "cts-eval:$(EVAL_REPORT_DIR)/cts_latency_writeback.rep" \
	    "route-eval:$(EVAL_REPORT_DIR)/route_gate.txt" ; do \
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
	@echo "  Those five are DEPRECATED — they drive the legacy ../asic-flows"
	@echo "  engine. Replacement (make -C ../eth-chiplet <target>):"
	@echo "    syn -> syn   pnr_place -> place   pnr_cts -> cts"
	@echo "    pnr_route -> route                pnr_all  -> all"
	@echo "  They still run, but they are NOT a second opinion — ../eth-chiplet/"
	@echo "  design.mk takes ten design inputs from THIS directory (floorplan,"
	@echo "  power plan, mmmc, io, upf, bondpads, every SDC, the DRC deck), so"
	@echo "  both flows read ONE copy of every design file. Nothing else in this"
	@echo "  directory is deprecated.  docs/tapeout/41-retiring-asic-flows.md"
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
	@echo "  P&R A/B — knob-driven, self-checking, isolated to the _eval_* DBs:"
	@echo "    make pnr_place_eval   floorplan + power plan + place  (EVP_ knobs)"
	@echo "    make pnr_cts_eval     clock tree synthesis            (EVC_ knobs)"
	@echo "    make pnr_route_eval   route + fill + GDSII + signoff  (EVR_ knobs)"
	@echo "    make pnr_all_eval     all three, unattended. Multi-hour."
	@echo ""
	@echo "    Each stage takes its INPUT database from a knob, so the usual mode"
	@echo "    is to resume a production snapshot instead of re-running upstream:"
	@echo "      make pnr_cts_eval   EVC_IN_PREFIX=$(BLOCK)   # resume real placement"
	@echo "      make pnr_route_eval EVR_IN_PREFIX=$(BLOCK)   # resume real CTS"
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
