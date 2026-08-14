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
#   lvs-pg-preflight  resolve the PG re-stream's inputs (no licence)
#   lvs_pg_gds      re-stream a PG-LABELLED GDS from the routed database
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

## 1 = compare against the PG-LABELLED re-stream from `make lvs_pg_gds` rather
## than the plain signoff GDS. Default 0, so nothing existing changes; but read
## the power/ground section below before assuming 0 is the right answer — a
## signoff stream usually carries no supply names at all, and a comparison
## without them is not a comparison.
LVS_PG ?= 0
## The layout: streamed GDSII. Follows LVS_PG; still overridable outright.
LVS_GDS ?= $(if $(filter 1,$(LVS_PG)),$(LVS_PG_GDS_OUT),$(LVS_IN_DIR)/$(LVS_TOP).gds)
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
## The `.GLOBAL` list emitted into the assembled SPICE source. Defaults to the
## supplies — which is what a netlist with no explicit power/ground needs, so
## nothing changes for a project that never sets this — but it is a SEPARATE
## knob because the two answer different questions. LVS_POWER/LVS_GROUND say
## which nets Calibre should treat as supplies; `.GLOBAL` merges every net of
## that NAME in every .SUBCKT of the source into one. A hard macro that uses a
## supply name for an INTERNAL node (a power-gated virtual ground, a second
## domain) then has that node shorted to the chip supply — in the source only,
## so the layout is the correct side and every symptom appears inside the macro.
## `run_lvs.sh` preflight scans MACRO_CDLS for exactly that and names the macro.
## EMPTY = emit no `.GLOBAL` at all, which is right when the post-P&R netlist
## wires .VDD/.VSS on every instance and on the macros themselves.
LVS_GLOBAL_NETS ?= $(LVS_POWER) $(LVS_GROUND)
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

#-----------------------------------------------------------------------------
# POWER/GROUND-LABELLED RE-STREAM (lvs_pg_gds)
#
# A GDS carries geometry, not connectivity: a net name reaches the layout side
# of LVS only as GDS *text*, and whether the supply grid gets any is decided
# entirely by the P&R GDS-out map. Foundry maps commonly have
# `NAME <layer>/PIN` rows and NO `NAME <layer>/SPNET` rows, so the special-route
# (power) grid streams out UNNAMED — Calibre then has no POWER net and no
# GROUND net, ERC goes vacuous, and supply-dependent device recognition stops
# working. That is a broken input, not a design defect, and it is why
# run_lvs.sh exits 6 rather than 1 when it sees it.
#
# The fix is NOT to re-route. `make lvs_pg_gds` re-opens the SAME routed
# database read-only and streams a SECOND GDS, under a new name, through a
# locally extended copy of the foundry map. No write_db, no edit to the foundry
# map, no change to the tapeout deliverables — the two streams differ only by
# the added text. Then: `make lvs_batch LVS_PG=1`.
#
# All paths are project-supplied, as everywhere else here. LVS_PG_LAYERS is
# normally left EMPTY: the script derives the metal stack from the map itself,
# which is what makes it survive a move to a different PDK or metal option.
#-----------------------------------------------------------------------------
## The re-stream script. Sibling of this file; its header is its spec.
LVS_PG_SCRIPT ?= $(LVS_FLOW_MK_DIR)/lvs_pg_emit.tcl
## P&R tool launch. `-stylus` selects the Common UI the script is written in;
## `-files` (not `-f`, which is legacy-UI only) sources a script and exits.
LVS_PG_CMD ?= innovus -stylus -files
## Where the routed database lives. Parallels LVS_IN_DIR — same LVS_RUN
## selection — but a database is a DIRECTORY under work/, not a file in outputs/.
LVS_PG_WORK_DIR ?= $(if $(LVS_RUN),$(if $(filter /%,$(LVS_RUN)),$(LVS_RUN),$(LVS_RUNS_DIR)/$(LVS_RUN))/work,$(WORK_DIR))
## The routed database itself. READ-ONLY input: the script never writes it back.
LVS_PG_DB ?= $(LVS_PG_WORK_DIR)/$(LVS_TOP)
## The foundry GDS-out map. Read-only lab collateral — copied, never edited.
LVS_PG_MAP_IN ?=
## The PG-labelled stream. A NEW name beside the signoff GDS, never over it.
LVS_PG_GDS_OUT ?= $(LVS_IN_DIR)/$(LVS_TOP)_lvs.gds
## The generated map, kept beside the stream it produced so the two are
## auditable together ("which map made this GDS?").
LVS_PG_MAP_OUT ?= $(basename $(LVS_PG_GDS_OUT))_pg_text.map
## Layers to add SPNET text on. EMPTY = derive from the map (recommended).
LVS_PG_LAYERS ?=
## Map purpose whose text layer/datatype is reused for the PG names.
LVS_PG_TEXT_PURPOSE ?= PIN
## Hard-macro GDS to merge in. Must match what the SIGNOFF stream merged, or
## the macros arrive as empty frames and cannot compare to their CDLs.
LVS_PG_MERGE_GDS ?=
## Stream-out settings. Match the signoff stream so the ONLY difference between
## the two files is the added text.
LVS_PG_UNIT ?= 1000
LVS_PG_LIB_NAME ?= DesignLib
LVS_PG_MODE ?= all
## Optional stream-out inventory report — per-layer shape counts, which is how
## you prove the re-stream added text and changed nothing else.
LVS_PG_REPORT ?=
## Optional PG-explicit netlist (`write_netlist -include_pwr_gnd -phys`), the
## mirror-image change on the SOURCE side. Left empty on purpose: changing both
## sides at once makes a residual failure hard to attribute.
LVS_PG_NETLIST_OUT ?=
## Supplies you expect to come out LABELLED. Each one that will not be gets a
## loud warning before the stream is written -- minutes earlier, and one licence
## cheaper, than finding out from the LVS report. Defaults to the supplies the
## project already declares for Calibre, because expecting those exact names to
## be labelled is what makes the two halves of the flow agree. This only ever
## warns; it never changes what is streamed.
LVS_PG_EXPECT_NETS ?= $(LVS_POWER) $(LVS_GROUND)

## LEF OBSTRUCTION HANDLING. A LEF `OBS` is a routing blockage, not
## manufactured metal, but foundry GDS-out maps put it on the SAME GDS layer as
## real metal. With macro output enabled, a Front-End-only library's abstracts
## then FABRICATE connectivity: pad spacers that are nothing but obstruction
## tile into a continuous sheet and short every net reaching a pad. 1 = move it
## to a scratch layer the LVS deck never reads. Set 0 only to reproduce the bug.
LVS_PG_STRIP_OBS ?= 1
## Obstruction is remapped to <gds layer> + this, so it is preserved and still
## inspectable rather than dropped. Collision with a real layer is asserted.
LVS_PG_OBS_LAYER_BASE ?= 9000
## The map purpose meaning "routing blockage".
LVS_PG_OBS_PURPOSE ?= LEFOBS

## LEF MACRO PIN NAMING — the knob that decides what LVS actually CHECKS.
## A black-boxed Front-End-only leaf has no devices and no text inside it, and
## Calibre netlists a box cell's unnamed pins only when it has one or the
## other. So its pins are ALL DROPPED: layout `.SUBCKT INVD1` with zero pins
## against a source `.SUBCKT INVD1 I ZN VDD VSS`, and the cell then matches on
## NAME AND COUNT ONLY — the routing between standard cells is not verified.
## 1 = also stream each LEF macro pin's NAME as text, onto the same text layer
## the PG names use, so the pins become named and the fabric is really
## compared. This ADDS verification; it is not a suppression. Off by default
## because it changes what a run measures and needs a deliberate re-stream.
LVS_PG_PIN_TEXT ?= 0
## The map purpose meaning "LEF macro pin". Must differ from LVS_PG_OBS_PURPOSE.
LVS_PG_PIN_PURPOSE ?= LEFPIN

## Where the P&R tool runs, and so where its own log/cmd files land.
LVS_PG_RUNDIR ?= $(LVS_RUNDIR)

# The environment contract handed to lvs_pg_emit.tcl — one definition, so the
# preflight and the run cannot report different values than they use.
LVS_PG_ENV = \
	LVS_PG_DB='$(LVS_PG_DB)' LVS_PG_MAP_IN='$(LVS_PG_MAP_IN)' \
	LVS_PG_GDS_OUT='$(LVS_PG_GDS_OUT)' LVS_PG_MAP_OUT='$(LVS_PG_MAP_OUT)' \
	LVS_PG_LAYERS='$(LVS_PG_LAYERS)' LVS_PG_TEXT_PURPOSE='$(LVS_PG_TEXT_PURPOSE)' \
	LVS_PG_MERGE_GDS='$(LVS_PG_MERGE_GDS)' \
	LVS_PG_UNIT='$(LVS_PG_UNIT)' LVS_PG_LIB_NAME='$(LVS_PG_LIB_NAME)' \
	LVS_PG_MODE='$(LVS_PG_MODE)' LVS_PG_REPORT='$(LVS_PG_REPORT)' \
	LVS_PG_NETLIST_OUT='$(LVS_PG_NETLIST_OUT)' \
	LVS_PG_EXPECT_NETS='$(LVS_PG_EXPECT_NETS)' \
	LVS_PG_STRIP_OBS='$(LVS_PG_STRIP_OBS)' \
	LVS_PG_OBS_LAYER_BASE='$(LVS_PG_OBS_LAYER_BASE)' \
	LVS_PG_OBS_PURPOSE='$(LVS_PG_OBS_PURPOSE)' \
	LVS_PG_PIN_TEXT='$(LVS_PG_PIN_TEXT)' \
	LVS_PG_PIN_PURPOSE='$(LVS_PG_PIN_PURPOSE)'

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
	LVS_GLOBAL_NETS='$(LVS_GLOBAL_NETS)' \
	BONDPAD_CELLS='$(BONDPAD_CELLS)' \
	LVS_BOX_LEAF='$(LVS_BOX_LEAF)' LVS_BOX_EXCLUDE_RE='$(LVS_BOX_EXCLUDE_RE)' \
	LVS_TURBO='$(LVS_TURBO)' LVS_SOURCE_ONLY='$(LVS_SOURCE_ONLY)' \
	LVS_NOWAIT='$(LVS_NOWAIT)'

# Guard used by every target. An unset top cell is the one mistake that
# produces plausible-looking paths instead of an error.
lvs_need_top = test -n '$(LVS_TOP)' || { echo "FAIL: LVS_TOP is empty — set BLOCK (or LVS_TOP) BEFORE including lvs.mk. Every LVS artefact is named after the top cell."; exit 1; }

.PHONY: lvs-preflight lvs_source lvs lvs_batch lvs-report lvs-rve lvs-clean lvs-help
.PHONY: lvs-pg-preflight lvs_pg_gds

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
# PG re-stream
#-----------------------------------------------------------------------------
## lvs-pg-preflight: layer 1 for the re-stream — the same split as
## lvs-preflight. Make resolves and attributes (which variable produced which
## path); lvs_pg_emit.tcl validates and derives (does the map actually describe
## a routable stack?), because only the script can read the map. Neither takes a
## P&R licence. Layer 2 is not delegable here without launching the tool, so
## make checks a little more of it than it does for Calibre: the script's own
## checks still run, and they are the backstop.
lvs-pg-preflight:
	@$(lvs_need_top)
	@echo "== PG re-stream preflight — $(LVS_TOP)  (no licence taken, no tool launched) =="
	@printf '  %-5s %-18s %s\n' 'sel' 'LVS_RUN' '$(if $(LVS_RUN),$(LVS_RUN),(empty — using WORK_DIR))'
	@rc=0; \
	if [ -r '$(LVS_PG_SCRIPT)' ]; then printf '  %-5s %-18s %s\n' 'OK' 'LVS_PG_SCRIPT' '$(LVS_PG_SCRIPT)'; \
	else printf '  %-5s %-18s %s\n' 'MISS' 'LVS_PG_SCRIPT' '$(LVS_PG_SCRIPT)'; rc=1; fi; \
	if [ -d '$(LVS_PG_DB)' ]; then printf '  %-5s %-18s %s\n' 'OK' 'LVS_PG_DB' '$(LVS_PG_DB)'; \
	else printf '  %-5s %-18s %s\n' 'MISS' 'LVS_PG_DB' '$(LVS_PG_DB) (a database is a DIRECTORY)'; rc=1; fi; \
	if [ -z '$(LVS_PG_MAP_IN)' ]; then \
	    printf '  %-5s %-18s %s\n' 'MISS' 'LVS_PG_MAP_IN' '(not set — REQUIRED: the foundry GDS-out map)'; rc=1; \
	elif [ -r '$(LVS_PG_MAP_IN)' ]; then printf '  %-5s %-18s %s\n' 'OK' 'LVS_PG_MAP_IN' '$(LVS_PG_MAP_IN)'; \
	else printf '  %-5s %-18s %s\n' 'MISS' 'LVS_PG_MAP_IN' '$(LVS_PG_MAP_IN)'; rc=1; fi; \
	if command -v $(firstword $(LVS_PG_CMD)) >/dev/null 2>&1; then \
	    printf '  %-5s %-18s %s\n' 'OK' 'LVS_PG_CMD' "$$(command -v $(firstword $(LVS_PG_CMD))) $(wordlist 2,99,$(LVS_PG_CMD))"; \
	else printf '  %-5s %-18s %s\n' 'MISS' 'LVS_PG_CMD' '$(firstword $(LVS_PG_CMD)) not on PATH'; rc=1; fi; \
	if [ -z '$(LVS_PG_MERGE_GDS)' ]; then \
	    printf '  %-5s %-18s %s\n' 'warn' 'LVS_PG_MERGE_GDS' '(empty — hard macros will stream as EMPTY frames)'; \
	else for f in $(LVS_PG_MERGE_GDS); do \
	    if [ -s "$$f" ]; then printf '  %-5s %-18s %s\n' 'OK' 'LVS_PG_MERGE_GDS' "$$f"; \
	    else printf '  %-5s %-18s %s\n' 'MISS' 'LVS_PG_MERGE_GDS' "$$f"; rc=1; fi; done; fi; \
	printf '  %-5s %-18s %s\n' '->' 'LVS_PG_GDS_OUT' '$(LVS_PG_GDS_OUT)'; \
	printf '  %-5s %-18s %s\n' '->' 'LVS_PG_MAP_OUT' '$(LVS_PG_MAP_OUT)'; \
	printf '  %-5s %-18s %s\n' '--' 'LVS_PG_LAYERS' '$(if $(LVS_PG_LAYERS),$(LVS_PG_LAYERS),(empty — derived from the map))'; \
	printf '  %-5s %-18s %s\n' '--' 'LVS_PG_PIN_TEXT' '$(if $(filter 1,$(LVS_PG_PIN_TEXT)),1 — LEF macro pin names streamed; boxed leaves get NAMED pins,0 — boxed leaves extract with NO pins: matched on name and count only)'; \
	if [ '$(LVS_PG_PIN_TEXT)' = '1' ] && [ '$(LVS_PG_PIN_PURPOSE)' = '$(LVS_PG_OBS_PURPOSE)' ]; then \
	    printf '  %-5s %-18s %s\n' 'MISS' 'LVS_PG_PIN_PURPOSE' 'same as LVS_PG_OBS_PURPOSE ($(LVS_PG_OBS_PURPOSE)) — pin names would land on stripped geometry'; rc=1; fi; \
	if [ $$rc -ne 0 ]; then \
	    echo ''; \
	    echo "PG PREFLIGHT: FAIL — fix the MISSING entries above."; \
	    echo "  The database is P&R output: it is the directory write_db left in work/,"; \
	    echo "  named after the top cell. LVS_PG_MAP_IN is the same GDS-out map the"; \
	    echo "  signoff stream_out used — read-only, and copied rather than edited."; \
	    exit 1; fi; \
	echo "PG PREFLIGHT: OK ($(LVS_TOP))"

## lvs_pg_gds: re-stream a PG-labelled GDS from the routed database. Takes a
## P&R licence, minutes not hours (no place/route/opt). READ-ONLY on the
## database — the script issues read_db + write_stream and no write_db — so it
## is safe to run against a signoff database that is already archived.
lvs_pg_gds: lvs-pg-preflight
	@mkdir -p $(dir $(LVS_PG_GDS_OUT)) $(LVS_PG_RUNDIR)
	cd $(LVS_PG_RUNDIR) && $(LVS_PG_ENV) $(LVS_PG_CMD) $(LVS_PG_SCRIPT)
	@test -s '$(LVS_PG_GDS_OUT)' || { \
	    echo "FAIL: no PG-labelled GDS at $(LVS_PG_GDS_OUT)."; \
	    echo "      The P&R tool can exit 0 on a failed script — find the real error in"; \
	    echo "      the tool log under $(LVS_PG_RUNDIR)."; \
	    exit 1; }
	@echo "OK: PG-labelled GDS $(LVS_PG_GDS_OUT) ($$(du -h '$(LVS_PG_GDS_OUT)' | cut -f1))"
	@echo "    map used  : $(LVS_PG_MAP_OUT)"
	@echo "    compare it: make lvs_batch LVS_PG=1"

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
	@echo "  make lvs-pg-preflight  resolve the PG re-stream's inputs   (no licence)"
	@echo "  make lvs_pg_gds      re-stream a PG-LABELLED GDS from the routed DB"
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
	@echo "  Power/ground-labelled re-stream (a signoff GDS usually has NO supply"
	@echo "  names in it; without them the comparison is not meaningful — exit 6):"
	@echo "    LVS_PG          $(LVS_PG)   (1 = point LVS_GDS at LVS_PG_GDS_OUT)"
	@echo "    LVS_PG_SCRIPT   $(LVS_PG_SCRIPT)"
	@echo "    LVS_PG_CMD      $(LVS_PG_CMD)"
	@echo "    LVS_PG_DB       $(LVS_PG_DB)   (read-only; no write_db)"
	@echo "    LVS_PG_MAP_IN   $(LVS_PG_MAP_IN)"
	@echo "    LVS_PG_GDS_OUT  $(LVS_PG_GDS_OUT)"
	@echo "    LVS_PG_MAP_OUT  $(LVS_PG_MAP_OUT)"
	@echo "    LVS_PG_LAYERS   $(if $(LVS_PG_LAYERS),$(LVS_PG_LAYERS),(empty — derived from the map))"
	@echo "    LVS_PG_TEXT_PURPOSE $(LVS_PG_TEXT_PURPOSE)"
	@echo "    LVS_PG_MERGE_GDS $(if $(LVS_PG_MERGE_GDS),$(LVS_PG_MERGE_GDS),(empty))"
	@echo "    LVS_PG_UNIT     $(LVS_PG_UNIT)   LVS_PG_LIB_NAME $(LVS_PG_LIB_NAME)   LVS_PG_MODE $(LVS_PG_MODE)"
	@echo "    LVS_PG_REPORT   $(if $(LVS_PG_REPORT),$(LVS_PG_REPORT),(empty — no stream-out inventory))"
	@echo "    LVS_PG_NETLIST_OUT $(if $(LVS_PG_NETLIST_OUT),$(LVS_PG_NETLIST_OUT),(empty — source side unchanged))"
	@echo "    LVS_PG_EXPECT_NETS $(if $(LVS_PG_EXPECT_NETS),$(LVS_PG_EXPECT_NETS),(empty — no expectation checked))"
	@echo "    LVS_PG_STRIP_OBS $(LVS_PG_STRIP_OBS)   (1 = LEF obstruction off the metal layers -> +$(LVS_PG_OBS_LAYER_BASE))"
	@echo "    LVS_PG_PIN_TEXT $(LVS_PG_PIN_TEXT)   (1 = stream LEF macro pin NAMES as $(LVS_PG_PIN_PURPOSE) text; 0 = boxed leaves have NO pins)"
	@echo "    LVS_PG_WORK_DIR $(LVS_PG_WORK_DIR)"
	@echo "    LVS_PG_RUNDIR   $(LVS_PG_RUNDIR)"
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
	@echo "    LVS_GLOBAL_NETS $(if $(strip $(LVS_GLOBAL_NETS)),$(LVS_GLOBAL_NETS),(empty — no .GLOBAL line emitted))"
	@echo "                    (the .GLOBAL list in the SPICE source. Drop a name here when a"
	@echo "                     hard macro uses it as an INTERNAL net — .GLOBAL would merge that"
	@echo "                     node with the chip supply and fabricate a short, source-side"
	@echo "                     only. 'make lvs-preflight' scans MACRO_CDLS and names the macro.)"
	@echo "    BONDPAD_CELLS   $(BONDPAD_CELLS)"
	@echo "    LVS_BOX_LEAF    $(LVS_BOX_LEAF)   (0 = raw compare, diagnostic only)"
	@echo "    LVS_BOX_EXCLUDE_RE $(LVS_BOX_EXCLUDE_RE)"
	@echo ''
	@echo "  Tools:  V2LVS=$(V2LVS)  CALIBRE=$(CALIBRE)  LVS_TURBO=$(LVS_TURBO)"
	@echo "          LVS_NOWAIT=$(LVS_NOWAIT)   (0 = queue for a licence, 1 = fail fast)"
	@echo "  Runner: $(LVS_RUNNER)   (owns preflight layer 2, and the whole run)"
