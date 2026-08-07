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

## cpf-patch: repair the CPF Genus writes, so the die actually gets filled.
##
## `write_power_intent -cpf` cannot translate this design's UPF supply commands
## — the Genus log is full of "Unable to translate command 'create_supply_net'
## ... from 1801 to CPF format" — and emits a CPF whose entire content is
## `create_power_domain -name PD_TOP -default`. No power net, no ground net.
##
## Innovus reads that at 2_pnr_setup.tcl:40, and every filler pass then dies
## with "IMPSP-5110: No supply-net names for Power Domain 'PD_TOP'". add_fillers
## reports "For 0 new insts" and the die ships with ~95,568 free-site gaps
## (~5.9% of the core) — no base-layer density fill, no ANTENNA diodes. That is
## tapeout-blocking, and it is silent: the flow completes and streams a GDSII.
##
## This is NOT fixable with an Innovus command. `update_power_domain` there is
## positional and has no -primary_power_net/-primary_ground_net options at all
## (verified: IMPTCM-162 + usage string). They are CPF statements, so the file
## is what needs repairing — which is exactly what the 2026-07 operator did by
## hand mid-session, and why that run has fillers and ours did not.
##
## Idempotent: re-running on an already-patched CPF is a no-op.
.PHONY: cpf-patch
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

## syn: Genus synthesis. The `test -s` is NOT belt-and-braces: when its -f
## script fails, Genus prints "Encountered problems processing file", drops to
## its interactive prompt, reads EOF and exits ZERO. Without this check `make
## pnr_all` sails straight past a dead synthesis into place-and-route on a
## netlist that was never written.
syn: setup_dirs asic-flist romlibs-check
	cd $(WORK_DIR)/; genus -f $(ASIC_FLOWS_DIR)/1_synthesis.tcl -log $(LOG_DIR)/syn_logs
	@$(MAKE) --no-print-directory cpf-patch
	@test -s $(OUT_DIR)/$(BLOCK)_gate_power.v || { \
	    echo "FAIL: synthesis produced no netlist at $(OUT_DIR)/$(BLOCK)_gate_power.v"; \
	    echo "      Genus exits 0 on a failed script — look for the real error with:"; \
	    echo "        grep -nE 'Encountered problems|^Error|not set' $(LOG_DIR)/syn_logs.log*"; \
	    exit 1; }
	@echo "OK: netlist $(OUT_DIR)/$(BLOCK)_gate_power.v"

syn_norun:
	cd $(WORK_DIR)/; genus -log $(LOG_DIR)/syn_logs

## lec: RTL vs the SYNTHESIS netlist, using the dofile Genus generates into
## work/. TWO CAVEATS, both verified:
##   1. It compares fv_map against outputs/$(BLOCK)_gate.v. It NEVER reads
##      *_pnr.v, so the ~45,700 instances CTS/opt/hold-repair added to the
##      netlist that actually became GDS are not covered. Use lec-pnr for that.
##   2. The generated dofile ends `exit -f` and this recipe checks nothing, so a
##      NON-EQUIVALENT result still reports success. Grep the log for
##      "Compare Results:" before believing it. (lec-pnr does not have this
##      flaw — it enforces the verdict twice, independently.)
## The dofile is written BY SYNTHESIS, so this target needs `make syn` first.
lec:
	cd $(WORK_DIR)/; lec -xl -Dofile ./lec.dofile

## lec-pnr: post-P&R equivalence — outputs/$(BLOCK)_gate_power.v (synthesis)
## against outputs/$(BLOCK)_pnr.v (the netlist that becomes GDS). This is the
## check nothing in this repo previously performed. _gate_power.v is the golden
## rather than _gate.v because it shares the same boundary (27 ports) and PG
## convention; _gate.v has only 6 PG connections and would turn every leaf
## supply into a false finding. Flat compare only — CTS pushed cloned clock nets
## through module boundaries, so hierarchical compare is impossible. Hours, and
## takes a Conformal seat. Exits non-zero on abort, non-equivalence, unmapped
## points or a short log.
lec-pnr:
	$(DESIGN_DIR)/scripts/lec/run_lec.sh pnr

## lec-gate: closes the joint in the chain — _gate.v vs _gate_power.v, i.e. the
## netlist `lec` proves against RTL vs the one lec-pnr uses as its golden.
## Statically identical (319 cell types, same counts, same 55,516 flop names).
lec-gate:
	$(DESIGN_DIR)/scripts/lec/run_lec.sh gate

## lec-selftest: mutation-tests the LEC HARNESS in ~15s — proves it passes an
## equivalent pair AND fails a one-gate mutation, an extra flop, and a missing
## netlist. Run this before trusting any lec-pnr result on a new host. A check
## that cannot fail is worth nothing, and this flow has shipped several.
lec-selftest:
	$(DESIGN_DIR)/scripts/lec/run_lec.sh selftest

.PHONY: lec lec-pnr lec-gate lec-selftest

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
## -files, NOT -f. Every one of the three stage scripts carries a header saying
## "run: innovus -stylus -f <script>", and that is wrong: -f is legacy-UI only.
## Stylus/Common UI rejects it with "**ERROR: (IMPSYT-468): Unknown argument -f"
## and then, having printed a usage message, exits ZERO — so make treats the
## stage as passed and moves to the next one. Three stages "ran" in under a
## minute that way, and the only symptom was a missing GDS at the end.
INNOVUS := innovus -stylus -files

.PHONY: pnr_place pnr_cts pnr_route pnr_all
pnr_place: setup_dirs
	cd $(WORK_DIR)/; $(INNOVUS) $(ASIC_FLOWS_DIR)/2_pnr_setup.tcl
	@test -d $(WORK_DIR)/$(BLOCK) || { \
	    echo "FAIL: placement wrote no DB at $(WORK_DIR)/$(BLOCK)"; exit 1; }

pnr_cts:
	cd $(WORK_DIR)/; $(INNOVUS) $(ASIC_FLOWS_DIR)/3_pnr_clock.tcl
	@test -s $(REPORT_DIR)/timing_summary_03_cts_opt.rep || { \
	    echo "FAIL: CTS wrote no post-opt timing summary — stage did not complete."; exit 1; }

## CALIBRE_HOME IS UNSET FOR THIS STAGE, DELIBERATELY.
##
## 4_pnr_route.tcl ends with two blocks guarded on $env(CALIBRE_HOME), and BOTH
## are broken on this site — which matters because CALIBRE_HOME is always set
## here (/eda/mentor/calibre), so both always fire:
##
##   1. `source .../queryenc/cal_enc.tcl` -> IMPSE-110 "can't find package Tk 8.0"
##   2. `exec calibre -drc -hier -turbo 8 $drc_ruledeck`
##        -> ERROR: Failure to open input file GDSFILENAME for read access.
##      The rule deck expects GDSFILENAME defined in DECK syntax; the .tcl only
##      sets a *Tcl* variable of that name, so Calibre looks for a file called
##      literally "GDSFILENAME".
##
## A failing `exec` raises a Tcl error, which ABORTS the script before its final
## `exit`. Innovus then drops to an interactive prompt and sits there forever —
## holding a Cadence seat — so `make` never returns and no rc is ever written.
## Seen on BOTH the 2026-08-05 and 2026-08-06 runs (3 occurrences in the
## former's log): a completed 4.5-hour flow that looked like it had hung.
##
## Everything of value — write_stream, write_netlist, write_sdf, write_db and
## every report — happens BEFORE these blocks, so skipping them loses nothing.
## Calibre DRC has its own working entry point: the `drc` / `drc_batch` targets.
##
## Fixed project-side rather than by patching asic-flows, which is a shared
## submodule that other designs build from.
pnr_route:
	cd $(WORK_DIR)/; env -u CALIBRE_HOME $(INNOVUS) $(ASIC_FLOWS_DIR)/4_pnr_route.tcl
	@test -s $(OUT_DIR)/$(BLOCK).gds \
	    && echo "OK: GDSII $(OUT_DIR)/$(BLOCK).gds ($$(du -h $(OUT_DIR)/$(BLOCK).gds | cut -f1))" \
	    || { echo "FAIL: no GDSII at $(OUT_DIR)/$(BLOCK).gds"; \
	         echo "      innovus exits 0 on a rejected argument or a failed script;"; \
	         echo "      find the real error with:"; \
	         echo "        grep -nE '\*\*ERROR|Unknown argument' $(WORK_DIR)/innovus.log*"; \
	         echo "      if the log looks clean, check ASIC/asic-flows is at b19e784+"; \
	         echo "      (write_stream lives there; the earlier pin routes but streams nothing)."; \
	         exit 1; }

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
	@# Do NOT just test -n: a set-but-malformed DISPLAY (e.g. "12.0" with the
	@# leading colon missing) passes that and Innovus then drops to no-window
	@# mode with only a WARN, which reads as "the GUI silently didn't open".
	@# Probe the display for real instead.
	@test -n "$$DISPLAY" || { \
	    echo "FAIL: DISPLAY is not set in THIS shell."; \
	    echo "      A ThinLinc desktop's DISPLAY does NOT reach a VS Code Remote-SSH"; \
	    echo "      terminal — they are separate shells. Run make from a terminal"; \
	    echo "      INSIDE the ThinLinc desktop, or use 'ssh -X <host>'."; \
	    echo "      Text-mode session on purpose?   make pnr_setup"; \
	    exit 1; }
	@xdpyinfo >/dev/null 2>&1 || { \
	    echo "FAIL: DISPLAY is set to '$$DISPLAY' but no X server answers there,"; \
	    echo "      so Innovus would start in no-window mode (IMPSYT-1507)."; \
	    echo ""; \
	    case "$$DISPLAY" in \
	      [0-9]*) echo "      LOOK AT THE VALUE: it is missing the leading colon."; \
	              echo "      Try:  export DISPLAY=:$$DISPLAY" ;; \
	      *)      echo "      Check the session is still alive:  xdpyinfo | head -3" ;; \
	    esac; \
	    exit 1; }
	@echo "OK: DISPLAY=$$DISPLAY (X server responded)"
	@test -d $(WORK_DIR)/$(BLOCK) || { \
	    echo "FAIL: no saved DB at $(WORK_DIR)/$(BLOCK) — run 'make pnr_place' first."; exit 1; }
	@# gui_show is REQUIRED, not decoration. Launched with -files, Innovus
	@# creates its main window but never MAPS it: xwininfo reports
	@# "Map State: IsUnMapped" and xprop reports no WM_STATE at all, i.e. the
	@# window manager never took ownership. The session looks like a plain
	@# text console and the GUI appears simply not to exist — with no error,
	@# because from the tool's point of view nothing failed. An explicit
	@# gui_show maps it (IsUnMapped -> IsViewable, verified).
	@printf '%s\n' \
	    'source ../scripts/config.tcl' \
	    'read_db $(BLOCK)' \
	    'if {[catch {gui_show} e]} { puts stderr "WARNING: gui_show failed: $$e" }' \
	    'puts "== $(BLOCK) loaded, GUI shown — this is the last-written DB =="' \
	    > $(WORK_DIR)/open_db.tcl
	cd $(WORK_DIR)/; $(INNOVUS) open_db.tcl

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

## Processors for Calibre turbo. srv03335 has 16 cores; 8 leaves headroom.
DRC_CPUS ?= 8

## drc: Calibre DRC on the built GDS, headless — no X display, no GUI packages,
## no runset. This is the target that WORKS.
##
## The foundry deck (CLN65S_9M_6X1Z1U.26_2a) carries, at lines 230-231:
##     LAYOUT PATH    "GDSFILENAME"
##     LAYOUT PRIMARY "TOPCELLNAME"
## Those are LITERAL PLACEHOLDER STRINGS in SVRF, not variables. 4_pnr_route.tcl
## did `set GDSFILENAME $OUT_DIR/${block_name}.gds` — a *Tcl* variable the deck
## never sees — so Calibre looked for a file called literally "GDSFILENAME" and
## died. That is why the in-flow Calibre step has NEVER produced a result, in
## any run of this design. `calibre -drc` has no command-line layout/topcell
## override, so the overrides must come from a project-owned wrapper deck, which
## is what scripts/calibre/ provides. The foundry deck is INCLUDEd, never copied
## or patched.
##
## The wrapper needs `DRC ICSTATION YES` or SVRF rejects the duplicate spec
## statements with "Error SPC1 ... superfluous specification statement".
##
## CAVEAT ON ANY NUMBER THIS PRODUCES: the GDS carries routing, vias and memory
## macros but NO standard-cell, IO or bond-pad device geometry (10,109 OD and
## 12,854 PO shapes die-wide is a macro-only count), and no seal ring, passivation
## or metal fill. Front-end, density and seal-ring rules will fail or be
## meaningless. The back-end metal/via/antenna checks are the real signal.
.PHONY: drc
drc: drc-preflight
	DRC_GDS=$(GDS) DRC_RUNDIR=$(DRC_RUNDIR) DRC_CPUS=$(DRC_CPUS) \
	    $(DESIGN_DIR)/scripts/calibre/run_drc.sh

## drc_gui: the old interactive path, kept as a fallback. Needs a runset and X.
.PHONY: drc_gui
## lvs-preflight: does this host have what LVS needs? Seconds, no tool launched.
## Expected to FAIL today and to say exactly why: there is no transistor netlist
## for the standard cells, IO drivers or bond pads, because every TSMC package
## installed here is Front End (_FE). This is procurement, not engineering —
## Calibre nmLVS-H has 150 idle seats and the decks are on disk. It turns green
## by itself the day the _BE packages land.
## See docs/TSMC_BACKEND_PACKAGE_REQUEST.md.
lvs-preflight:
	$(DESIGN_DIR)/scripts/calibre/run_lvs.sh --check

## lvs: Calibre nmLVS over the streamed GDS against the P&R netlist. Refuses to
## run until lvs-preflight passes, so it fails with the missing-data list rather
## than an obscure tool error. NOTE the GDS is itself incomplete for the same
## reason (424 cell masters are LEF shells), so LVS and a manufacturable stream
## unblock together, not separately.
lvs: lvs-preflight
	$(DESIGN_DIR)/scripts/calibre/run_lvs.sh --run \
	    $(GDS) $(OUT_DIR)/$(BLOCK)_pnr.v $(BLOCK) $(WORK_DIR) $(LOG_DIR)

.PHONY: lvs lvs-preflight

drc_gui: drc-preflight $(DRC_RUNSET)
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