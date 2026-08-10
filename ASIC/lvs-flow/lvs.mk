#-----------------------------------------------------------------------------
# lvs.mk — includable GNU Make fragment: Calibre nmLVS targets + env plumbing.
# A joint work commissioned on behalf of SoC Labs, under Arm Academic
# Access license.
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# This file is PROJECT-AGNOSTIC and PDK-AGNOSTIC on purpose: it holds the flow
# logic (targets, the environment contract, the checks) and nothing else. No
# design name, no site path, no PDK path appears below. Your project supplies
# the values; see project.mk.example for a fully worked one.
#
# Everything is `?=`, so any default here can be overridden from the project
# makefile, the environment, or the make command line.
#
#   include ../lvs-flow/lvs.mk
#
# ONE RULE: **assign first, include last.** `?=` only takes effect on a
# variable that is still undefined, so a project assignment placed AFTER this
# include is silently ignored. Putting the include at the end of the variable
# section also stops `lvs-preflight` from stealing .DEFAULT_GOAL.
#
# Targets (see CONTRACT.md for the pipeline they drive):
#   lvs-preflight   resolve inputs, then delegate to run_lvs.sh --check
#   lvs_source      v2lvs + SPICE source assembly only  (LVS_SOURCE_ONLY=1)
#   lvs_batch       the full headless run               (alias: lvs)
#   lvs-report      where the artefacts are + the verdict out of the report
#   lvs-rve         open the Calibre results viewer on the svdb
#   lvs-clean       delete the run directory
#   lvs-help        targets + every resolved value
#
# THIS FILE DOES NOT VALIDATE INPUTS ITSELF. It resolves them — turning
# LVS_RUN into a layout/netlist pair and a run directory — and then hands the
# finished environment to `run_lvs.sh --check`, whose exit status is the
# verdict. Two preflights would drift, and the checks worth having (foundry
# deck placeholder integrity, rundir writability) belong next to the code that
# depends on them. See the lvs-preflight comment for the split.
#
# NO SENTINEL FILES, and no timestamp dependencies on the GDS. An earlier take
# on this flow gated the run on `work/.lvs.done`. It is the wrong shape here:
# the sentinel is touched whether the comparison came back CORRECT or
# INCORRECT, so a failed run reads as up-to-date, and `make` then refuses to
# re-run the one thing you need to re-run. The verdict lives in the report, not
# in the filesystem — so every target below is .PHONY and re-runs when asked.
#-----------------------------------------------------------------------------

# Where this fragment lives, resolved at include time — the runner is its
# sibling. Must be `:=` and must be the first thing here: MAKEFILE_LIST grows
# with every later include.
LVS_FLOW_MK_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))

#-----------------------------------------------------------------------------
# Project context. All `?=`: if your makefile already defines these (house
# names in the SoC Labs flows), they are used untouched. The fallbacks only
# exist so lvs.mk is usable standalone.
#-----------------------------------------------------------------------------
DESIGN_DIR ?= $(CURDIR)
OUT_DIR    ?= $(DESIGN_DIR)/outputs
WORK_DIR   ?= $(DESIGN_DIR)/work
LOG_DIR    ?= $(DESIGN_DIR)/logs
# Defined-but-empty rather than left undefined, so `--warn-undefined-variables`
# stays quiet and an unset top cell fails with a sentence instead of a path
# like `work/lvs_run/.lvs.rep` that reads like a tool bug.
BLOCK      ?=

#-----------------------------------------------------------------------------
# §1 Required inputs — the contract. No defaults for the two that cannot be
# guessed; preflight names them.
#-----------------------------------------------------------------------------
## Top cell name. Must exist in BOTH the GDS and the netlist, and every
## artefact is named after it.
LVS_TOP ?= $(BLOCK)

## Foundry LVS rule deck. Read-only — the flow copies and rewrites it, never
## edits it in place.
LVS_DECK ?=

# INPUT RESOLUTION. The layout and the schematic must come from the SAME P&R
# database, so they are resolved together out of one directory. A flow that
# archives each run to a timestamped directory leaves the live outputs/ empty,
# which is why this is a knob and not a constant:
#
#   make lvs_batch LVS_RUN=20260810T065131Z_my-run   # a name under runs/
#   make lvs_batch LVS_RUN=/abs/path/to/some/run     # or an absolute path
#   make lvs_batch LVS_IN_DIR=/somewhere/else        # or skip the layout rule
#
# Each run gets its own LVS_RUNDIR, so results from two P&R runs cannot
# overwrite each other and be compared by mistake.
LVS_RUN      ?=
LVS_RUNS_DIR ?= $(DESIGN_DIR)/runs
LVS_IN_DIR   ?= $(if $(LVS_RUN),$(if $(filter /%,$(LVS_RUN)),$(LVS_RUN),$(LVS_RUNS_DIR)/$(LVS_RUN))/outputs,$(OUT_DIR))

## The layout: streamed GDSII.
LVS_GDS ?= $(LVS_IN_DIR)/$(LVS_TOP).gds
## The schematic: the POST-P&R netlist (write_netlist), not the synthesis
## netlist — only the post-P&R one shares a database with the GDS.
LVS_SRC_V ?= $(LVS_IN_DIR)/$(LVS_TOP)_pnr.v
## Run directory. The runner cd's into it and every artefact lands there.
LVS_RUNDIR ?= $(WORK_DIR)/lvs_run$(if $(LVS_RUN),_$(notdir $(LVS_RUN)))

#-----------------------------------------------------------------------------
# §1 Leaf-cell resolution. Space-separated lists.
#-----------------------------------------------------------------------------
## Standard-cell simulation Verilog (Front-End view) -> v2lvs `-e` stubs.
STDCELL_VLOG ?=
## IO-driver simulation Verilog. Empty is legitimate for a padless macro.
IO_VLOG ?=
## Real transistor CDLs for hard macros (SRAM, ROM). These are NEVER boxed —
## they compare to transistors, which is the part of the run that is real
## verification rather than connectivity checking.
MACRO_CDLS ?=

#-----------------------------------------------------------------------------
# §1 Optional inputs — defaults per CONTRACT.md.
#-----------------------------------------------------------------------------
## Foundry primitive stubs, passed to `v2lvs -lsp`.
LVS_SOURCE_ADDED ?=
## Supply net names, substituted for the deck's POWER_NAME/GROUND_NAME literals.
LVS_POWER  ?= VDD
LVS_GROUND ?= VSS
## Pin-less bump/pad cells: LEF-only, no model at all, so they need an empty
## .SUBCKT or the SPICE source will not even read.
BONDPAD_CELLS ?=
## 1 = black-box the Front-End-only leaves (the load-bearing idea; CONTRACT §4).
## 0 = raw compare, diagnostic only — expect the digital fabric to mis-compare.
LVS_BOX_LEAF ?= 1
## Physical-only cells (fill, decap, antenna diodes) are in the GDS but not in
## write_netlist output. Leave them UNBOXED so their frames auto-flatten and
## match the netlist's absence of them.
LVS_BOX_EXCLUDE_RE ?= ^(ANTENNA|DCAP|GDCAP|GFILL|OD25DCAP)
## Calibre -turbo CPU count.
LVS_TURBO ?= $(shell nproc 2>/dev/null || echo 4)
## 1 = stop after source prep. No Calibre, no licence.
LVS_SOURCE_ONLY ?= 0
## 1 = give up immediately when no Calibre licence is free (`-nowait`), 0 =
## queue for one. Default 0 matches the DRC flow: an overnight batch should
## wait rather than lose hours of setup to a busy pool. Set 1 in CI, where a
## job blocked on a licence is worse than one that fails fast and retries.
## NOT YET IN CONTRACT.md §1 — the runner added it; the spec needs a row.
LVS_NOWAIT ?= 0

## Tool binaries — override for a site install that is not on PATH.
V2LVS   ?= v2lvs
CALIBRE ?= calibre

## The runner. Sibling of this file by default; CONTRACT.md is its spec.
LVS_RUNNER ?= $(LVS_FLOW_MK_DIR)/run_lvs.sh

## Results-viewer command. `calibre -rve -lvs <svdb>`; some sites prefer
## `calibredrv -m -64 -rve -lvs`.
LVS_RVE_CMD ?= $(CALIBRE) -rve -lvs

## What to tell someone whose GDS/netlist is missing. Project-specific, because
## only the project knows what its P&R stage is called.
LVS_INPUT_HINT ?= run the P&R route stage that streams the GDS and writes the post-P&R netlist

#-----------------------------------------------------------------------------
# §2 Artefacts. Named here so lvs-report and lvs-rve agree with the runner
# without either guessing.
#-----------------------------------------------------------------------------
LVS_LIBS_CDL   ?= $(LVS_RUNDIR)/$(LVS_TOP)_libs.cdl
LVS_DESIGN_CDL ?= $(LVS_RUNDIR)/$(LVS_TOP)_design.cdl
LVS_SRC_CDL    ?= $(LVS_RUNDIR)/$(LVS_TOP)_lvs_src.cdl
LVS_BOX_SVRF   ?= $(LVS_RUNDIR)/$(LVS_TOP)_lvs_box.svrf
LVS_RUN_DECK   ?= $(LVS_RUNDIR)/$(LVS_TOP)_calibre_lvs.deck
LVS_REPORT     ?= $(LVS_RUNDIR)/$(LVS_TOP).lvs.rep
LVS_LOG        ?= $(LVS_RUNDIR)/calibre_lvs.log
LVS_SVDB       ?= $(LVS_RUNDIR)/svdb
# v2lvs writes this into its working directory, which the runner makes
# LVS_RUNDIR. Multi-MB and the first place to look when a leaf cell will not
# resolve — enumerate it so nobody goes hunting for it in the source tree.
LVS_V2LVS_LOG  ?= $(LVS_RUNDIR)/v2lvs.log

#-----------------------------------------------------------------------------
# The environment contract handed to the runner (CONTRACT.md §1). One
# definition, shared by every target that launches it — so source-prep and the
# full run cannot drift apart and produce different SPICE.
#-----------------------------------------------------------------------------
LVS_ENV = \
	V2LVS='$(V2LVS)' CALIBRE='$(CALIBRE)' \
	LVS_DECK='$(LVS_DECK)' LVS_SOURCE_ADDED='$(LVS_SOURCE_ADDED)' \
	LVS_GDS='$(LVS_GDS)' LVS_SRC_V='$(LVS_SRC_V)' LVS_TOP='$(LVS_TOP)' \
	LVS_RUNDIR='$(LVS_RUNDIR)' \
	STDCELL_VLOG='$(STDCELL_VLOG)' IO_VLOG='$(IO_VLOG)' MACRO_CDLS='$(MACRO_CDLS)' \
	LVS_POWER='$(LVS_POWER)' LVS_GROUND='$(LVS_GROUND)' \
	BONDPAD_CELLS='$(BONDPAD_CELLS)' \
	LVS_BOX_LEAF='$(LVS_BOX_LEAF)' LVS_BOX_EXCLUDE_RE='$(LVS_BOX_EXCLUDE_RE)' \
	LVS_TURBO='$(LVS_TURBO)' LVS_SOURCE_ONLY='$(LVS_SOURCE_ONLY)' \
	LVS_NOWAIT='$(LVS_NOWAIT)'

# Guard used by every target. An unset top cell is the one mistake that
# produces plausible-looking paths instead of an error.
lvs_need_top = test -n '$(LVS_TOP)' || { echo "FAIL: LVS_TOP is empty — set BLOCK (or LVS_TOP) BEFORE including lvs.mk. Every LVS artefact is named after the top cell."; exit 1; }

.PHONY: lvs-preflight lvs_source lvs lvs_batch lvs-report lvs-rve lvs-clean lvs-help

#-----------------------------------------------------------------------------
# Preflight
#-----------------------------------------------------------------------------
## lvs-preflight: TWO LAYERS, because they know different things. Neither takes
## a licence or launches a tool, so this is safe to run while P&R still holds
## the work directory, and safe as a prerequisite of everything else.
##
##   layer 1 — make, here. Input RESOLUTION: what LVS_RUN selected, which make
##     VARIABLE produced which path, and — when the layout/netlist pair is
##     absent — which archived P&R runs could supply it, as literal commands.
##     This has to live in make: run_lvs.sh is handed finished paths and has no
##     idea a runs/ directory exists, or that a variable named LVS_RUN chose it.
##
##   layer 2 — `run_lvs.sh --check`. Input VALIDATION: tools on PATH, foundry
##     deck placeholder integrity, run-directory writability, leaf-cell data.
##     DELEGATED, not reimplemented, so "is this deck still substitutable" has
##     exactly one implementation and it sits beside the code that does the
##     substituting. Its exit status IS the verdict; make only adds diagnosis.
##
## The layers overlap on plain file existence. That is deliberate and cheap:
## layer 1 attributes a missing file to the make variable you have to edit,
## which layer 2 cannot do — it only ever sees the resolved path.
lvs-preflight:
	@$(lvs_need_top)
	@test -r '$(LVS_RUNNER)' || { \
	    echo "FAIL: no runner at $(LVS_RUNNER)."; \
	    echo "      make delegates the tool/deck/rundir checks it does not own —"; \
	    echo "      set LVS_RUNNER, or check out the lvs-flow directory properly."; \
	    exit 1; }
	@echo "== LVS preflight — $(LVS_TOP)  (no licence taken, no tool launched) =="
	@echo "-- layer 1/2: make — input resolution (which variable points where) --"
	@printf '  %-5s %-17s %s\n' 'sel' 'LVS_RUN' '$(if $(LVS_RUN),$(LVS_RUN),(empty — using OUT_DIR))'
	@printf '  %-5s %-17s %s\n' 'sel' 'LVS_IN_DIR' '$(LVS_IN_DIR)'
	@chk() { \
	    var=$$1; shift; \
	    if [ $$# -eq 0 ]; then printf '  %-5s %-17s %s\n' '--' "$$var" '(empty — optional)'; return 0; fi; \
	    for f in "$$@"; do \
	        if [ -r "$$f" ] && [ -s "$$f" ]; then printf '  %-5s %-17s %s\n' 'OK' "$$var" "$$f"; \
	        else printf '  %-5s %-17s %s\n' 'MISS' "$$var" "$$f"; fi; \
	    done; }; \
	req() { \
	    var=$$1; shift; \
	    if [ $$# -eq 0 ]; then printf '  %-5s %-17s %s\n' 'MISS' "$$var" '(not set — REQUIRED, see CONTRACT.md §1)'; return 0; fi; \
	    chk "$$var" "$$@"; }; \
	req LVS_GDS          $(LVS_GDS); \
	req LVS_SRC_V        $(LVS_SRC_V); \
	req LVS_DECK         $(LVS_DECK); \
	req STDCELL_VLOG     $(STDCELL_VLOG); \
	chk IO_VLOG          $(IO_VLOG); \
	chk MACRO_CDLS       $(MACRO_CDLS); \
	chk LVS_SOURCE_ADDED $(LVS_SOURCE_ADDED); \
	if [ -d '$(LVS_RUNDIR)' ]; then printf '  %-5s %-17s %s\n' 'OK' 'LVS_RUNDIR' '$(LVS_RUNDIR)'; \
	else printf '  %-5s %-17s %s\n' 'new' 'LVS_RUNDIR' '$(LVS_RUNDIR) (will be created)'; fi
	@echo ''
	@echo "-- layer 2/2: run_lvs.sh --check — tools, deck placeholders, rundir, leaf data --"
	@$(LVS_ENV) bash $(LVS_RUNNER) --check; rc=$$?; \
	if [ $$rc -ne 0 ]; then \
	    echo ''; \
	    if [ ! -s '$(LVS_GDS)' ] || [ ! -s '$(LVS_SRC_V)' ]; then \
	        echo "  layer 1 adds: the layout/netlist pair is P&R output — $(LVS_INPUT_HINT)."; \
	        echo "  Both are resolved from LVS_IN_DIR = $(LVS_IN_DIR)"; \
	        printed=0; \
	        for d in $$(ls -1dt $(LVS_RUNS_DIR)/*/ 2>/dev/null); do \
	            [ -s "$$d/outputs/$(LVS_TOP).gds" ] || continue; \
	            [ $$printed -eq 0 ] && echo "  Archived runs that DO carry a GDS — pick one:"; \
	            printed=$$((printed+1)); [ $$printed -gt 5 ] && break; \
	            echo "      make lvs_batch LVS_RUN=$$(basename $$d)"; \
	        done; \
	    fi; \
	    echo "LVS PREFLIGHT: FAIL — rejected by layer 2 (run_lvs.sh --check exit $$rc)"; \
	    exit $$rc; \
	fi; \
	echo "LVS PREFLIGHT: OK — both layers clean ($(LVS_TOP))"

#-----------------------------------------------------------------------------
# The runs
#-----------------------------------------------------------------------------
## lvs_source: v2lvs two-pass + SPICE source assembly, and STOP. No Calibre, so
## no licence seat — this is how you iterate on the source deck (missing
## .SUBCKTs, pin order, bond-pad stubs) while someone else has the tool.
##
## `override` on purpose: `make lvs_source LVS_SOURCE_ONLY=0` would otherwise
## take a licence from a target whose whole point is not taking one.
lvs_source: override LVS_SOURCE_ONLY := 1
lvs_source: lvs-preflight
	@mkdir -p $(LVS_RUNDIR)
	$(LVS_ENV) bash $(LVS_RUNNER)
	@echo "OK: SPICE source $(LVS_SRC_CDL)"

## lvs_batch: the full headless run — v2lvs -> deck rewrite -> LVS BOX splice ->
## calibre -lvs -hier -64 -turbo. Takes a Calibre licence and hours. Gated on
## preflight so a missing input fails in seconds with a list, not deep inside
## the tool.
lvs_batch: lvs-preflight
	@mkdir -p $(LVS_RUNDIR)
	$(LVS_ENV) bash $(LVS_RUNNER)
	@echo "== LVS results in $(LVS_RUNDIR) — 'make lvs-report' for the verdict =="

## lvs: alias for lvs_batch, so `make lvs` does the obvious thing.
lvs: lvs_batch

#-----------------------------------------------------------------------------
# Reporting
#-----------------------------------------------------------------------------
## lvs-report: where the artefacts are, and the verdict lifted out of the
## report. Calibre's EXIT STATUS IS NOT A VERDICT — it exits 0 on a clean run
## that compared INCORRECT — so the report is the only place to read it.
lvs-report:
	@$(lvs_need_top)
	@echo "== $(LVS_TOP) LVS artefacts ($(LVS_RUNDIR)) =="
	@printf '  %-4s %-9s %s\n' OK ARTEFACT PATH
	@for spec in \
	    "libs:$(LVS_LIBS_CDL)" \
	    "design:$(LVS_DESIGN_CDL)" \
	    "source:$(LVS_SRC_CDL)" \
	    "box:$(LVS_BOX_SVRF)" \
	    "deck:$(LVS_RUN_DECK)" \
	    "report:$(LVS_REPORT)" \
	    "v2lvs:$(LVS_V2LVS_LOG)" \
	    "log:$(LVS_LOG)" \
	    "svdb:$(LVS_SVDB)" ; do \
	    name=$${spec%%:*}; path=$${spec#*:}; \
	    if [ -s "$$path" ] || [ -d "$$path" ]; then printf '  %-4s %-9s %s\n' 'yes' "$$name" "$$path"; \
	    else printf '  %-4s %-9s %s\n' '--' "$$name" "$$path"; fi; \
	done
	@echo ''
	@if [ -s '$(LVS_REPORT)' ]; then \
	    verdict=$$(awk '/^ *Result +Layout +Source/ {b=1; next} \
	                    b && /^ *-/ {next} \
	                    b && NF>=2 {print $$1; exit}' '$(LVS_REPORT)'); \
	    echo "  VERDICT: $${verdict:-<none — the run never reached the comparison; read the log>}"; \
	    sed -n '/OVERALL COMPARISON RESULTS/,/CELL  SUMMARY/p' '$(LVS_REPORT)' \
	        | grep -E '^ +(Error|Warning): ' || true; \
	    echo ''; \
	    echo "  A boxed run proves CONNECTIVITY, not cell interiors — never quote it as signoff."; \
	else \
	    echo "  (no report yet — run 'make lvs_batch')"; \
	fi

## lvs-rve: open the Calibre results viewer on the run's database. GUI, so it
## needs a real X display; a stale/unset DISPLAY otherwise drops the tool into
## a mode where it looks like it did nothing.
lvs-rve:
	@$(lvs_need_top)
	@test -d '$(LVS_SVDB)' || { \
	    echo "FAIL: no Calibre database at $(LVS_SVDB) — run 'make lvs_batch' first."; exit 1; }
	@test -n "$$DISPLAY" || { \
	    echo "FAIL: DISPLAY is unset in THIS shell, and RVE is a GUI."; \
	    echo "      Run make from a terminal inside the desktop session, or 'ssh -X <host>'."; \
	    exit 1; }
	$(LVS_RVE_CMD) $(LVS_SVDB)

#-----------------------------------------------------------------------------
# Housekeeping
#-----------------------------------------------------------------------------
## lvs-clean: drop the run directory. Deletes the report and the svdb with it.
lvs-clean:
	@case '$(LVS_RUNDIR)' in ''|/) echo "FAIL: refusing to remove LVS_RUNDIR='$(LVS_RUNDIR)'"; exit 1;; esac
	@echo "removing $(LVS_RUNDIR) (report, log and svdb go with it)"
	rm -rf $(LVS_RUNDIR)

## lvs-help: the targets, and every value they will actually run with. Print
## this before a long run — it is cheaper than discovering an hour in that
## LVS_GDS pointed at last week's stream.
lvs-help:
	@echo "Calibre nmLVS — ASIC/lvs-flow (contract: CONTRACT.md)"
	@echo ''
	@echo "  make lvs-preflight   resolve inputs, then run_lvs.sh --check (no licence)"
	@echo "  make lvs_source      v2lvs + SPICE source assembly only (no licence)"
	@echo "  make lvs_batch       full headless LVS            (alias: make lvs)"
	@echo "  make lvs-report      artefact paths + the verdict from the report"
	@echo "  make lvs-rve         Calibre results viewer on the svdb (needs DISPLAY)"
	@echo "  make lvs-clean       delete $(LVS_RUNDIR)"
	@echo ''
	@echo "  Layout / schematic must come from ONE P&R database:"
	@echo "    LVS_TOP         $(LVS_TOP)"
	@echo "    LVS_IN_DIR      $(LVS_IN_DIR)"
	@echo "    LVS_GDS         $(LVS_GDS)"
	@echo "    LVS_SRC_V       $(LVS_SRC_V)"
	@echo "    LVS_RUNDIR      $(LVS_RUNDIR)"
	@echo "    pick a run      make lvs_batch LVS_RUN=<dir under $(LVS_RUNS_DIR)>"
	@echo ''
	@echo "  PDK:"
	@echo "    LVS_DECK        $(LVS_DECK)"
	@echo "    LVS_SOURCE_ADDED $(LVS_SOURCE_ADDED)"
	@echo "    STDCELL_VLOG    $(STDCELL_VLOG)"
	@echo "    IO_VLOG         $(IO_VLOG)"
	@echo "    MACRO_CDLS      $(MACRO_CDLS)"
	@echo ''
	@echo "  Comparison:"
	@echo "    LVS_POWER       $(LVS_POWER)"
	@echo "    LVS_GROUND      $(LVS_GROUND)"
	@echo "    BONDPAD_CELLS   $(BONDPAD_CELLS)"
	@echo "    LVS_BOX_LEAF    $(LVS_BOX_LEAF)   (0 = raw compare, diagnostic only)"
	@echo "    LVS_BOX_EXCLUDE_RE $(LVS_BOX_EXCLUDE_RE)"
	@echo ''
	@echo "  Tools:  V2LVS=$(V2LVS)  CALIBRE=$(CALIBRE)  LVS_TURBO=$(LVS_TURBO)"
	@echo "          LVS_NOWAIT=$(LVS_NOWAIT)   (0 = queue for a licence, 1 = fail fast)"
	@echo "  Runner: $(LVS_RUNNER)   (owns preflight layer 2, and the whole run)"
