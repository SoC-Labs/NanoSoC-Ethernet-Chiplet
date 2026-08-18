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

# Per-design identity for physical verification: top cell, die box, foundry
# deck, rundir, census budgets. ONE file to edit to point this flow at another
# chiplet. Included HERE rather than beside lvs_project.mk at the bottom because
# everything below consumes $(BLOCK), and a `?=` manifest read after its first
# consumer is silently discarded — drc_project.mk's own header explains it.
include $(DESIGN_DIR)/drc_project.mk

# Design top; everything the flow writes is named after it. $(BLOCK) comes from
# drc_project.mk above — deliberately not restated here, so there is one name.
# `?=`: DRC/LVS can be pointed at a stream built elsewhere.
GDS   ?= $(OUT_DIR)/$(BLOCK).gds

# Source for `romlibs-fetch`, which is now a LAST RESORT — see that target.
#
# The comment that used to sit here said the ROM libs "cannot be rebuilt on
# srv03335" because "the Arm compiler lists zero generators since RHEL 8.10".
# That is false, and it was false because of a parsing bug in the check that
# reported it: `romlibs-preflight` read the generator names off the wrong line
# of the compiler's own help output and therefore found none, on an install that
# lists fifteen and compiles both ROMs in under three minutes each. Fixed in
# ../common.mk on 2026-08-14. Rebuilding here is the normal path now.
ROMLIBS_REF ?= /home/dwn1c21/SoC-Labs/TAPEOUT/2026july/NanoSoC-Ethernet-Chiplet/ASIC/romlibs

# ── THIS RUN'S BOOT ROMs ────────────────────────────────────────────────────
# The macros are compiled per run into $(OUT_DIR)/romlibs and the run is pinned
# to that build (../rom_build.mk). $(OUT_DIR) is where the netlist, the CPF and
# the GDS already live and is what gets archived into runs/, so the ROMs travel
# with the results they produced — a finished run describes its own silicon.
#
# ROMLIBS_DIR is EXPORTED because it is read by scripts/config.tcl, which every
# Genus and Innovus stage sources. That single export is what makes synthesis,
# P&R and stream-out open one build: they resolve $bootrom_dir/$eth_rom_dir to
# this run's directory rather than to a shared drop that may have been replaced
# between two stages that are hours apart.
#
# `:=`, NOT `?=`. ../rom_build.mk (reached through the common.mk include above)
# has already given ROM_RUN_DIR a default of the shared drop, so a `?=` here
# would be a silent no-op and every run would keep using ASIC/romlibs. A command
# line `make syn ROM_RUN_DIR=...` still wins — command-line variables beat any
# makefile assignment.
ROM_RUN_DIR       := $(OUT_DIR)/romlibs
export ROMLIBS_DIR := $(ROM_RUN_DIR)

.DEFAULT_GOAL := help

.PHONY: setup_dirs asic-flist romlibs-check romlibs-gds-check romlibs-fetch cpf-patch _cpf-patch-one sdc-check \
        syn syn_norun syn_eval syn_compare \
        lec lec-pnr lec-gate lec-selftest route-gate-selftest \
        pnr_place pnr_cts pnr_route pnr_all pnr_setup gui \
        pnr_place_eval pnr_cts_eval pnr_route_eval pnr_all_eval \
        gdsmap gdsmap-parity restream restream-census \
        drc drc-census logo drc-logo \
        status clean distclean help

# `pad-lef` (../common.mk) derives the patched TSMC IO-driver LEF from the
# read-only PDK into a gitignored build directory. config.tcl:187 reads it as
# IO_PAD_DRIVER_LEF, so it must exist before any stage opens a tool. It is
# hung off setup_dirs because every stage already depends on setup_dirs, and
# the generator is idempotent and needs no licence (~0.01s).
setup_dirs: pad-lef
	mkdir -p $(REPORT_DIR) $(LOG_DIR) $(OUT_DIR) $(WORK_DIR)

## Re-render the generated sub-flists every run, so the TideLink V2 / SoC
## selection cannot go stale. Delegated: the top-level make sources the three
## set_env.sh scripts in dependency order.
asic-flist:
	$(MAKE) -C $(NANOSOC_ETH_CHIPLET_HOME) --no-print-directory asic-flist

## Genus reads the ROM .libs via config.tcl's lib_search_path_list; without them
## `syn` dies inside set_db with "Cannot open file rom_via_*.lib".
##
## SINCE 2026-08-14 THIS IS ALSO A CONTENT GATE, and it is the reason `syn` can
## refuse to start. ../rom_gate.mk compares both compiled ROMs word for word
## against the firmware code files. It costs ~1.5 s; a synthesis run that
## discovers a dead ROM (if it ever did) costs a licence hour and finds nothing,
## because nothing downstream of here reads ROM contents at all.
##
## The message below no longer says "not built": a ROM that is present, valid,
## loadable by Genus and FULL OF THE WRONG BITS is the failure that actually
## happened, and it reads as a build problem only if the gate says so.
##
## AND SINCE 2026-08-14 IT ALSO BUILDS THEM. `rom-run` compiles both macros for
## THIS run into $(ROM_RUN_DIR) — from a content-addressed cache, so an
## unchanged firmware costs seconds and a changed one costs ~3 min per ROM — and
## then runs the gate against what it just built, not against a shared drop. A
## firmware change can no longer reach the .bintxt without reaching the macro,
## which is the failure this whole gate exists because of.
##
## ROM_RUN_DIR is passed on the SUB-MAKE COMMAND LINE, not left to the exported
## environment: ../common.mk assigns ROMLIBS_DIR with `:=`, and a makefile
## assignment beats an environment variable. Exported-only, the sub-make would
## cheerfully build and verify the shared drop while Genus read the run.
romlibs-check:
	@$(MAKE) -C $(DESIGN_DIR)/.. -f common.mk --no-print-directory \
	    rom-run ROM_RUN_DIR=$(ROM_RUN_DIR) || { \
	    echo ""; \
	    echo "SYNTHESIS REFUSED: the boot ROMs did not pass verification (above)."; \
	    echo ""; \
	    echo "  * COULD NOT BUILD        -- the compiler could not run. It needs a"; \
	    echo "      LOCAL-DISK mirror (make -C $(DESIGN_DIR)/.. -f common.mk rom-compiler-stage)"; \
	    echo "      and the bootloader firmware built, for the code files."; \
	    echo "      On a host with no compiler at all, adopt a prebuilt tree instead:"; \
	    echo "        make -C $(DESIGN_DIR)/.. -f common.mk rom-run ROM_RUN_DIR=$(ROM_RUN_DIR) \\"; \
	    echo "             ROM_IMPORT_FROM=$(ROMLIBS_REF)"; \
	    echo "      That is recorded as origin=imported and still has to pass this gate."; \
	    echo "  * CONTENT MISMATCH       -- the macros exist and are wrong. Do NOT proceed."; \
	    echo "      These ROMs are mask programmed; wrong bits are a dead die, and no later"; \
	    echo "      stage of this flow looks at them. Read $(ROM_RUN_DIR)/verify/*.log."; \
	    echo "  * DEPTH/ADDRESS DISAGREEMENT -- spec, wrapper and macro do not agree."; \
	    echo "      512 words / A[8:0] is the RTL wrapper, the HADDR[10:2] decode and the"; \
	    echo "      2 KB linker cap. Settle the depth BEFORE recompiling — an 11-bit macro"; \
	    echo "      matches neither the wrapper nor the placed abstract."; \
	    echo "  * PIN CONFLICT           -- this run is already pinned to a different ROM"; \
	    echo "      build. That is the gate working: synthesis, P&R and stream-out must see"; \
	    echo "      ONE build. Start a new run rather than re-pinning this one."; \
	    echo ""; \
	    echo "  This gate is mutation-tested: make -C $(DESIGN_DIR)/.. -f common.mk romlibs-selftest"; \
	    exit 1; }

## The SAME question, asked of the streamed GDS — because a ROM that was correct
## when Genus read its .lib proves nothing about the bits that reached the mask.
## The macro is merged into the stream by write_stream, from a hand-maintained
## $gds_merge_list in scripts/config.tcl: a dropped entry, a stale path or a
## substituted macro all produce a GDS that opens cleanly and boots nothing.
##
## Called with ROM_GDS=<stream> after `pnr_route` and after `restream`. It fires
## AFTER the GDS artefact assertion, so a failure here always leaves the stream
## on disk to inspect.
##
## It extracts the programmed words from the merged stream and compares them to
## the firmware code file. With no extractor installed it reports UNVERIFIED and
## FAILS — "we could not check" must never render as a pass. Override with
## ROM_GDS_GATE=report to downgrade UNVERIFIED only; a DETECTED mismatch fails
## in every mode.
romlibs-gds-check:
	@$(MAKE) -C $(DESIGN_DIR)/.. -f common.mk --no-print-directory \
	    romlibs-verify-gds ROM_GDS=$(ROM_GDS) ROM_GDS_GATE=$(ROM_GDS_GATE)

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

## ── rom-ensure — WHY EVERY P&R STAGE DEPENDS ON IT ─────────────────────────
## Innovus reads this run's ROM LEF at placement and its GDS at stream-out,
## hours after Genus read its .lib. Those three must be ONE build; a run whose
## netlist and whose mask describe different programs is undetectable by every
## other check in this flow, because nothing downstream reads ROM contents.
##
## `rom-run-ensure` (../rom_build.mk) is the guard, and it is deliberately the
## CHEAP one rather than `rom-run`: if this run's macros are staged and pinned it
## prints one line and returns, touching no compiler and needing no firmware
## checkout. It only falls through to a real build when the run has none — a
## resumed run, or a cleaned outputs/ — and then it re-materialises the SAME
## cache entry rather than inventing a new one. A CHANGED key is refused by the
## pin, which is the case worth failing on.
.PHONY: rom-ensure
rom-ensure:
	@$(MAKE) -C $(DESIGN_DIR)/.. -f common.mk --no-print-directory \
	    rom-run-ensure ROM_RUN_DIR=$(ROM_RUN_DIR)

## cpf-patch is idempotent and cheap; running it here means a hand-run or
## resumed placement cannot proceed on an unpatched CPF. See power_plan.tcl.
pnr_place: setup_dirs rom-ensure sdc-check cpf-patch
	$(call legacy_notice,pnr_place,place)
	cd $(WORK_DIR)/; $(INNOVUS) $(ASIC_FLOWS_DIR)/2_pnr_setup.tcl
	@test -d $(WORK_DIR)/$(BLOCK) || { \
	    echo "FAIL: placement wrote no DB at $(WORK_DIR)/$(BLOCK)"; exit 1; }

pnr_cts: rom-ensure
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
##
## gdsmap: 4_pnr_route.tcl's write_stream takes -map_file from $gds_layer_map,
## which scripts/config.tcl points at the DERIVED map — a build product, not a
## committed file. Without this prerequisite the stage routes for hours and then
## dies at write_stream having written no GDS (measured 2026-08-14). Same
## dependency `pnr_route_eval` already carries; the two stages stream the same
## map on purpose.
pnr_route: rom-ensure gdsmap
	@# Cheap, licence-free, and BEFORE Innovus starts. `gdsmap` above should have
	@# just produced this; if it did not, say so now rather than at hour six.
	@test -r $(GDSMAP) || { \
	    echo "FAIL: no GDS stream-out map at $(GDSMAP)"; \
	    echo "      'make gdsmap' should have derived it — re-run it and read its output."; \
	    exit 1; }
	$(call legacy_notice,pnr_route,route)
	cd $(WORK_DIR)/; env -u CALIBRE_HOME $(INNOVUS) $(ASIC_FLOWS_DIR)/4_pnr_route.tcl
	@test -s $(OUT_DIR)/$(BLOCK).gds \
	    && echo "OK: GDSII $(OUT_DIR)/$(BLOCK).gds ($$(du -h $(OUT_DIR)/$(BLOCK).gds | cut -f1))" \
	    || { echo "FAIL: no GDSII at $(OUT_DIR)/$(BLOCK).gds"; \
	         echo "      grep -nE '\*\*ERROR|Unknown argument' $(WORK_DIR)/innovus.log*"; \
	         echo "      if the log looks clean, check ASIC/asic-flows is at b19e784+"; \
	         echo "      — write_stream lives there; the earlier pin streams nothing."; \
	         exit 1; }
	@$(MAKE) --no-print-directory romlibs-gds-check ROM_GDS=$(OUT_DIR)/$(BLOCK).gds

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

pnr_route_eval: setup_dirs gdsmap
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
	@# The eval streams are what the tapeout evaluation actually reads, so they
	@# get the same ROM content gate as the production one. ~46 s against hours.
	@$(MAKE) --no-print-directory romlibs-gds-check ROM_GDS=$(EVAL_OUT_DIR)/$(BLOCK).gds

## place -> CTS -> route, all three eval stages. Multi-hour.
pnr_all_eval: pnr_place_eval pnr_cts_eval pnr_route_eval

#-----------------------------------------------------------------------------
# Stream-out map, and re-streaming without a P&R run
#
# The map used to be a committed hand-edit of the read-only PDK file. It is now
# DERIVED at build time from two foundry inputs, so there is no fork to drift
# and every deviation is argued in one place (scripts/gdsmap_derive.py).
#
# `gdsmap-parity` is the acceptance test: in strict-parity mode the generator
# must reproduce TSMC's own row set exactly. It is cheap, needs no licence, and
# it is what catches a PDK bump changing the map under us.
#-----------------------------------------------------------------------------
# PDK_GDSMAP and PDK_TECH_LEF are resolved by ASIC/common.mk (included at the
# top of this file) via ASIC/tech_wrappers/tsmc65/scripts/pdk_paths.sh, which
# globs the installed PDK instead of spelling the deck/map release codes into a
# public repository. Values are unchanged — `make pdk-paths` re-proves it.
#
# GDSMAP IS OUR OWN BUILD PRODUCT that merely inherited the vendor filename, so
# it is found BY GLOB, not by name: nothing about the foundry release is
# disclosed and the same file is selected. The exact-one check below matters
# more here than anywhere else in the flow — this is the file whose identity
# decides what the streamed GDS *is*, and a silent first-match would swap the
# derived map (57 rows) for something else without a word. If it is not yet
# built the glob is empty and the `gdsmap` target below creates it, which is the
# same bootstrap the hardcoded name had.
GDSMAP_GLOB  := $(WORK_DIR)/tech/*.derived.map
GDSMAP_FOUND := $(wildcard $(GDSMAP_GLOB))
ifneq ($(words $(GDSMAP_FOUND)),1)
  ifneq ($(words $(GDSMAP_FOUND)),0)
    $(error GDSMAP is AMBIGUOUS - $(words $(GDSMAP_FOUND)) files match \
      $(GDSMAP_GLOB), expected exactly 1: $(GDSMAP_FOUND). Refusing to guess: \
      picking the first would silently change which layer map the GDS is \
      streamed with. Remove the stale one, or set GDSMAP explicitly)
  endif
endif
# 0 matches -> the canonical name the `gdsmap` target will create.
GDSMAP       ?= $(if $(GDSMAP_FOUND),$(GDSMAP_FOUND),$(WORK_DIR)/tech/$(notdir $(PDK_GDSMAP:.map=.derived.map)))
GDSMAP_GEN   := $(DESIGN_DIR)/scripts/gdsmap_derive.py
GDS_CENSUS   := $(DESIGN_DIR)/../../scripts/ci/gds_layer_census.py

## make gdsmap        — derive the stream-out map (pnr_route_eval depends on it)
gdsmap:
	@mkdir -p $(dir $(GDSMAP))
	@rm -f $(GDSMAP)
	python3 $(GDSMAP_GEN) --pdk-map $(PDK_GDSMAP) --tech-lef $(PDK_TECH_LEF) -o $(GDSMAP)

## make gdsmap-parity — prove the generator still reproduces the vendor row set.
## Compares canonically: object-type lists sorted, LEFOBS removed from both
## sides (we never emit it), comments and whitespace ignored. The only rows
## allowed to differ are TSMC's two dead M10/M11 entries, which this stack
## cannot use — anything else is a real divergence and fails the target.
gdsmap-parity:
	@mkdir -p $(WORK_DIR)/tech
	@python3 $(GDSMAP_GEN) --pdk-map $(PDK_GDSMAP) --tech-lef $(PDK_TECH_LEF) \
	    --strict-parity -o $(WORK_DIR)/tech/parity.map >/dev/null
	@canon() { python3 -c "import sys;\
	  [print(' '.join([f.split()[0], ','.join(sorted(x for x in f.split()[1].split(',') if x!='LEFOBS')), f.split()[2], f.split()[3]])) \
	   for f in (l.strip() for l in open(sys.argv[1])) if f and not f.startswith('#')]" "$$1" | sort; }; \
	 canon $(WORK_DIR)/tech/parity.map > $(WORK_DIR)/tech/.gen.txt; \
	 canon $(PDK_GDSMAP)               > $(WORK_DIR)/tech/.pdk.txt; \
	 same=$$(comm -12 $(WORK_DIR)/tech/.gen.txt $(WORK_DIR)/tech/.pdk.txt | wc -l); \
	 extra=$$(comm -23 $(WORK_DIR)/tech/.gen.txt $(WORK_DIR)/tech/.pdk.txt); \
	 missing=$$(comm -13 $(WORK_DIR)/tech/.gen.txt $(WORK_DIR)/tech/.pdk.txt | grep -vE "NAME M1[01]/PIN" || true); \
	 echo "gdsmap-parity: $$same rows identical to the vendor map"; \
	 if [ -n "$$extra" ];   then echo "FAIL: rows we emit that TSMC does not:"; echo "$$extra"; exit 1; fi; \
	 if [ -n "$$missing" ]; then echo "FAIL: vendor rows we dropped:";          echo "$$missing"; exit 1; fi; \
	 echo "gdsmap-parity: OK (only TSMC's dead M10/M11 rows differ, by design)"

## make restream — write a new GDS from the EXISTING routed database, with the
## current derived map. Minutes, not hours: a map change cannot alter placement
## or routing, so re-running P&R to test one would prove nothing and produce a
## different database to compare against. Override RESTREAM_MAP to A/B a map.
RESTREAM_DB       ?= $(WORK_DIR)/$(BLOCK)_eval_route
RESTREAM_MAP      ?= $(GDSMAP)
RESTREAM_GDS_OUT  ?= $(EVAL_OUT_DIR)/$(BLOCK)_restream.gds
## rom-ensure: restream MERGES the ROM GDS in (config.tcl's $gds_merge_list), so
## it needs this run's macros present exactly as route did — and the stream it
## writes is checked by romlibs-gds-check at the end of this recipe.
restream: gdsmap rom-ensure
	@test -d $(RESTREAM_DB) || { \
	    echo "FAIL: no routed database at $(RESTREAM_DB)"; \
	    echo "      run 'make pnr_route_eval', or set RESTREAM_DB to a saved run's."; exit 1; }
	@mkdir -p $(EVAL_OUT_DIR)
	@# RESTREAM_MERGE is deliberately NOT set here. restream.tcl sources
	@# scripts/config.tcl and takes $gds_merge_list from it — the same eight
	@# files 4b_pnr_route_eval.tcl streams with. Listing them again here would
	@# be a second copy that drifts, and a short merge list produces a smaller
	@# GDS that reads as a map regression.
	@# $(INNOVUS) already carries `-stylus -files`; do not repeat them.
	cd $(WORK_DIR)/; \
	    RESTREAM_DB=$(RESTREAM_DB) \
	    RESTREAM_MAP=$(RESTREAM_MAP) \
	    RESTREAM_GDS_OUT=$(RESTREAM_GDS_OUT) \
	    $(INNOVUS) $(DESIGN_DIR)/scripts/restream.tcl < /dev/null
	@# INNOVUS EXITS 0 AFTER FAILING. Measured 2026-08-13: read_db aborted with
	@# IMPIMEX-7023 (a library file inside the saved DB had been deleted), the
	@# script never reached its own write_stream guard, and `make` still reported
	@# success. Without this check the target is a silent no-op — the exact
	@# failure mode docs/tapeout/17-silent-noops exists to stamp out. The
	@# script's internal guard is not enough: it cannot run if the script dies
	@# before it.
	@test -s $(RESTREAM_GDS_OUT) || { \
	    echo "FAIL: restream wrote no GDS at $(RESTREAM_GDS_OUT)"; \
	    echo "      Innovus may have exited 0 anyway — read the log, do not trust the exit code:"; \
	    echo "        grep -nE '\*\*ERROR|IMPIMEX-|IMPSYT-' $(WORK_DIR)/innovus.log*"; \
	    echo "      A deleted file inside the saved DB (libs/lef/*, libs/mmmc/*) is the usual cause."; \
	    exit 1; }
	@echo "OK: restream wrote $(RESTREAM_GDS_OUT)"
	@$(MAKE) --no-print-directory romlibs-gds-check ROM_GDS=$(RESTREAM_GDS_OUT)

## make restream-census — per-layer record counts for the re-streamed GDS.
## This is how you check a map change did what it claimed, and it is the ONLY
## check that catches the failure that matters: a map row silently skipped, no
## error raised, and the labels simply absent. "Innovus did not complain" is not
## a verification.
##
## REFERENCE NUMBERS, measured 2026-08-13 on the routed DB of
## runs/20260812T144334Z_route-baseline-gds-nonstrict, current default map
## (LEFOBS moved to +9000, LEFPIN text on, NAME rows combined).
##
## These are counts of OUR geometry, so they are quoted by the METAL they sit
## on, not by GDS layer number: the number/datatype table is TSMC's, it is not
## reproduced in this repository, and `make gdsmap` derives it into $(GDSMAP)
## where the reader can resolve any row against their own PDK licence. The
## census script prints the numeric layers at runtime — read them there.
##
##     structures 2,579   geometry 3,587,844   text 351,775
##
##     pin-name text, by metal:  M1 11,826   M2 163,663   M3 65,616
##                               M4  89,580  M5      25   M6     25
##                               M7      25  M9       2
##     obstruction (LEFOBS, re-mapped to base layer + 9000 — OBS_LAYER_BASE in
##     scripts/gdsmap_derive.py), over the routing and via layers this stack
##     uses:  6,631 records
##
## M5, M6 and M7 carry exactly 25 pin-name records each: one label per pin shape
## on those metals in the pad drivers. If those come back 0, the NAME
## <layer>/LEFPIN rows are not being honoured — that is the regression this
## target exists to catch. (An earlier revision of this comment paired those
## three counts with M7/M6/M5, in that order; the mapping is ascending, and the
## count is 25 on each of the three, so nothing downstream was affected.)
##
## Takes the same RESTREAM_GDS_OUT as `make restream`, so overriding one and not
## the other censuses the wrong file. Pass both or neither.
restream-census:
	@test -s $(RESTREAM_GDS_OUT) || { \
	    echo "FAIL: no GDS at $(RESTREAM_GDS_OUT)"; \
	    echo "      run 'make restream' first, or pass the SAME RESTREAM_GDS_OUT"; \
	    echo "      you passed to it — the two targets share that variable."; exit 1; }
	python3 $(GDS_CENSUS) $(RESTREAM_GDS_OUT)

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
## Calibre DRC on the built GDS, headless. run_drc.sh assembles the PROJECT deck
## first (scripts/calibre/make_project_deck.sh: tsmc65_minisic_header.svrf.in,
## with $(BLOCK) and the die box substituted in, + the foundry rule bodies below
## the foundry's own /* SWITCH DEFINITION END */), drops it in the rundir as
## deck.svrf and runs that. The read-only foundry deck is never modified; the
## spliced body is md5-checked against it on every run.
## Splicing rather than INCLUDEing is required: WLCSP_SEALRING must be OFF (we
## are wire bond) and it is #DEFINEd unconditionally, and xLB/yLB/xRT/yRT must be
## the real die box and are declared unconditionally as VARIABLE -- neither is
## reachable from a wrapper. Those four numbers are not written down here: they
## are read out of scripts/floorplan.tcl's create_floorplan by drc_project.mk,
## which is the whole point. `make -n drc` prints the resolved values.
## For the foundry-default A/B, set
##   DRC_DECK=$(DESIGN_DIR)/scripts/calibre/$(BLOCK).drc.rules
## run_drc.sh does its own preflight.
##
## CAVEAT ON ANY NUMBER THIS PRODUCES: the GDS carries routing, vias and macros
## but no standard-cell, IO or bond-pad geometry, no seal ring and no fill, so
## front-end, density and seal-ring rules are meaningless here. The back-end
## metal/via/antenna checks are the real signal.
## Everything the deck assembler needs, in one place, so `drc` and `drc-logo`
## cannot drift apart and so the values are visible at the call site rather than
## smuggled in by a global `export`. All of it comes from drc_project.mk.
## DECK_HEADER is deliberately NOT set here — it is the switch-experiment escape
## hatch, and pushing a value every run would defeat it.
DRC_DECK_ENV = BLOCK=$(BLOCK) FOUNDRY_DECK=$(DRC_FOUNDRY_DECK) \
               DIE_XLB=$(DRC_DIE_XLB) DIE_YLB=$(DRC_DIE_YLB) \
               DIE_XRT=$(DRC_DIE_XRT) DIE_YRT=$(DRC_DIE_YRT)

drc:
	DRC_GDS=$(GDS) DRC_RUNDIR=$(DRC_RUNDIR) DRC_CPUS=$(DRC_CPUS) \
	$(DRC_DECK_ENV) \
	    $(DESIGN_DIR)/scripts/calibre/run_drc.sh

## Count and gate what the DRC run produced. Calibre exits 0 whether or not it
## found violations, so `make drc` alone is not a verdict — this is. Same script
## and same budgets the CI signoff stage uses (ci/signoff.yaml, id: drc), so a
## local run and the gate cannot disagree.
drc-census:
	DRC_DESIGN_BUDGET=$(DRC_DESIGN_BUDGET) DRC_DENSITY_BUDGET=$(DRC_DENSITY_BUDGET) \
	    python3 $(DESIGN_HOME)/scripts/ci/drc_census.py $(DRC_RUNDIR)

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
	DRC_CPUS=$(DRC_CPUS) $(DRC_DECK_ENV) \
	    $(DESIGN_DIR)/scripts/calibre/run_drc.sh

## Calibre nmLVS, from the portable flow in ../lvs-flow. lvs_project.mk holds
## this design's values and includes ../lvs-flow/lvs.mk, which supplies the
## targets: lvs-preflight, lvs_source, lvs_pg_gds, lvs_batch (alias lvs),
## lvs-report, lvs-rve, lvs-clean, lvs-help. `make lvs-help` prints every
## resolved value.
##
## A Front-End-only PDK is NOT a blocker: LVS_BOX_LEAF=1 black-boxes the
## model-less leaves on both sides and compares them as instances. That proves
## connectivity, NOT cell interiors and NOT the pad ring -- always say
## "clean modulo black boxes and modulo the pad ring". CONTRACT.md 5, 6c.
##
## Two things this design needs, both learned the hard way (CONTRACT.md 6a/6b):
##   * the layout must be the PG-labelled stream, not the signoff GDS
##       make lvs_pg_gds && make lvs_batch LVS_PG=1
##   * outputs/ carries only logo-merged streams, so the GDS and its matching
##     _pnr.v come from a timestamped run dir -- switch with one variable:
##       make lvs_batch LVS_RUN=20260810T092257Z_derate-check3
include $(DESIGN_DIR)/lvs_project.mk

## Static rail (IR-drop) analysis: rail_project.mk supplies `rail`, `rail-gate`,
## `rail-selftest`, `rail-status`, `rail-clean`. It is pure data plus five
## targets and includes no flow, so it can go last beside lvs_project.mk rather
## than early beside drc_project.mk.
##
## `rail` takes an Innovus seat and a Voltus_Power_Integrity seat on demand —
## the `voltus` binary itself cannot read this database (IMPESI-3490, CMMMC),
## while the identical rail commands resolve inside the Innovus Stylus shell.
## `rail-gate` and `rail-selftest` take NEITHER and need no database: the
## verdict is recomputed from the artefacts a run left behind, because
## report_rail prints `**ERROR` and returns SUCCESS and its exit code decides
## nothing here.
include $(DESIGN_DIR)/rail_project.mk

#-----------------------------------------------------------------------------
# Housekeeping
#-----------------------------------------------------------------------------
## Adopt ROM macros from a reference tree instead of compiling them. LAST
## RESORT — override the tree with ROMLIBS_REF.
##
## THIS USED TO BE A BARE `cp -r` INTO ASIC/romlibs, and that is the mechanism
## the whole per-run ROM build exists to replace: an untracked binary drop with
## no recorded relationship to any firmware. It is how both macros came to hold
## the wrong program, and nothing could tell afterwards where they came from.
##
## It now goes through the SAME cache and the SAME pin as a compiled ROM
## (../rom_build.mk's ROM_IMPORT_FROM). The difference is one recorded field:
## origin=imported, with the tree it was taken from, in this run's
## .rom_build.json. It still faces the full word-for-word gate — importing
## asserts nothing whatever about contents.
##
## Prefer `make syn`, which compiles them: the compiler works on this host
## (~3 min per ROM, and seconds on a cache hit).
romlibs-fetch:
	@test -d "$(ROMLIBS_REF)" || { \
	    echo "FAIL: no ROM-lib reference tree at $(ROMLIBS_REF)"; \
	    echo "      point ROMLIBS_REF at a tree holding cc_rom/ and eth_rom/."; exit 1; }
	@echo "== adopting ROM macros from $(ROMLIBS_REF) into $(ROM_RUN_DIR) =="
	@echo "   (recorded as origin=imported — they still have to pass the content gate)"
	@$(MAKE) -C $(DESIGN_DIR)/.. -f common.mk --no-print-directory \
	    rom-run ROM_RUN_DIR=$(ROM_RUN_DIR) ROM_IMPORT_FROM=$(ROMLIBS_REF)

## Which flow stages have actually run, from the artefacts on disk.
status:
	@echo "== $(BLOCK) =="
	@printf '  %-14s %-4s %s\n' STAGE OK ARTEFACT
	@for spec in \
	    "flist:$(NANOSOC_ETH_CHIPLET_HOME)/build/chip/flist/soc.flist" \
	    "romlib-files:$(ROMLIBS_DIR)/cc_rom/rom_via.lef" \
	    "rom-verified:$(ROM_VERIFY_DIR)/last_pass.txt" \
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
	@echo "    make lvs_pg_gds    PG-labelled stream for LVS (run this first)"
	@echo "    make lvs           Calibre LVS   (add LVS_PG=1 to use that stream)"
	@echo "    make lvs-preflight assert every LVS input is readable (no licence)"
	@echo "    make lvs-report    LVS artefact paths + the verdict from the report"
	@echo "    make lvs-help      every value the LVS run will use"
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
	@echo "  Boot ROM contents — mask programmed, so wrong bits are a dead die:"
	@echo "    make romlibs-check      the gate \`syn\` runs first (~2 s, no licence)"
	@echo "    make romlibs-gds-check ROM_GDS=<stream>   the same, on a merged GDS"
	@echo "    make -C .. -f common.mk romlibs-selftest  prove the gate can fail"
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
