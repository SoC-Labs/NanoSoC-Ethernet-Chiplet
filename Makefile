#-----------------------------------------------------------------------------
# Makefile — nanoSoC ethernet chiplet integration
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
#
# Copyright 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# `make elab` structurally elaborates nanosoc_eth_chiplet under VCS — the proof
# that the wrapper wires the three components together consistently.
#
# The three components each own their environment, and sourcing three set_env.sh
# scripts by hand is exactly what the wrapper's own set_env.sh refuses to do.
# So the ENVIRONMENT is assembled HERE, in the recipe, in dependency order:
#   1. this repo's set_env.sh   — component roots + sys_desc lib dirs
#   2. the SoC's set_env.sh      — ETHMAC/PHC/IPC/CMSDK/tech dirs the SoC flist needs
#   3. TideLink's set_env.sh     — CMSDK_FPGA_SRAM_V + XHB500 (generated on first run)
# Order matters: TideLink defaults CMSDK_DIR with `:=`, so the SoC's choice wins.
#-----------------------------------------------------------------------------

SHELL := /bin/bash
.ONESHELL:

CHIPLET_HOME := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
FLIST        := $(CHIPLET_HOME)/flist/nanosoc_eth_chiplet.flist
TOP          := nanosoc_eth_chiplet
SIMV         := simv_chiplet
BUILD        := $(CHIPLET_HOME)/build/elab
# VCS-readable, flattened copy of the SoC's generated flist (see the recipe).
export CHIPLET_SOC_VCS_FLIST := $(BUILD)/soc_vcs.f
export CHIPLET_SOC_ASIC_FLIST := $(CHIPLET_HOME)/build/chip/flist/soc.flist
# TideLink's flist with the shadowed deps module removed, so exactly one
# definition of every module reaches the compiler. See resolve_tidelink_flist.py:
# relying on VCS "last declaration wins" would let a first-wins tool silently
# bind an RTL copy that lacks the a2l reset-skew fix.
export CHIPLET_TL_VCS_FLIST := $(BUILD)/tidelink_vcs.f
export CHIPLET_TL_ASIC_FLIST := $(CHIPLET_HOME)/build/chip/flist/tidelink_asic.flist

VCS_FLAGS    := -full64 -sverilog -timescale=1ns/1ps

ASIC_DIR     := $(CHIPLET_HOME)/ASIC/genus-innovus
TOOLKIT_DIR  := $(CHIPLET_HOME)/ASIC/asic-toolkit

.PHONY: bootstrap elab chip-boundary chip-wrapper lint check regress cdc elab-strict clean
.PHONY: vendor-check hooks
.PHONY: help asic asic-status asic-syn asic-pnr asic-gds asic-drc

# Bare `make` used to run `bootstrap` — a 42-submodule fetch — because it was
# the first target in the file. Show what is available instead.
.DEFAULT_GOAL := help

## help: the targets in this Makefile, grouped by what they are for.
help:
	@echo "nanosoc_eth_chiplet — integration top"
	@echo ""
	@echo "  Setup:"
	@echo "    make bootstrap     fetch all 42 submodules (see scripts/bootstrap.sh)"
	@echo "    make hooks         install the pre-commit / pre-push vendor guards"
	@echo ""
	@echo "  Gates (what CI runs nightly — .github/workflows/nightly.yml):"
	@echo "    make check         vendor-check + chip-boundary + Verilator lint. No EDA licence."
	@echo "    make elab          VCS structural elaboration"
	@echo "    make elab-strict   xrun -hal; fails on a synthesis-blocking multi-driver"
	@echo "    make regress       every data-plane sim proof (ARGS=--quick to skip the long pole)"
	@echo "    make cdc           structural CDC pass (Cadence HAL)"
	@echo ""
	@echo "  Individual checks:"
	@echo "    make chip-boundary every RTL port classified exactly once"
	@echo "    make chip-wrapper  ...and emit build/chip/rtl/nanosoc_eth_chiplet_chip.v"
	@echo "    make lint          Verilator structural lint"
	@echo "    make vendor-check  no TSMC collateral tracked in this PUBLIC repo."
	@echo "                       Both scanners, the same two the PR gate runs."
	@echo ""
	@echo "  ASIC implementation (delegates to ASIC/genus-innovus):"
	@echo "    make asic-status   which flow stages have run"
	@echo "    make asic-syn      synthesis (Genus)"
	@echo "    make asic-pnr      place + CTS + route -> GDSII (Innovus). Multi-hour."
	@echo "    make asic-gds      syn + pnr, unattended, end to end"
	@echo "    make asic-drc      Calibre DRC on the built GDS"
	@echo "    make asic          the ASIC flow's own help, with every target"
	@echo ""
	@echo "    make asic-flist    re-render the generated ASIC sub-flists"
	@echo "    make clean         remove build/elab"

#-----------------------------------------------------------------------------
# ASIC pass-throughs
#-----------------------------------------------------------------------------
# So the implementation flow is reachable from the repo root like every other
# gate, instead of requiring a cd into a directory you have to know about.
# ASIC/genus-innovus/Makefile is the authority; these only forward.
asic:        ; @$(MAKE) -C $(ASIC_DIR) --no-print-directory help
asic-status: ; @$(MAKE) -C $(ASIC_DIR) --no-print-directory status
asic-syn:    ; $(MAKE) -C $(ASIC_DIR) syn
asic-pnr:    ; $(MAKE) -C $(ASIC_DIR) pnr_place pnr_cts pnr_route
asic-gds:    ; $(MAKE) -C $(ASIC_DIR) pnr_all
## scripts/calibre/run_drc.sh is the maintained headless harness behind `drc`,
## and is what the signoff pipeline calls.
asic-drc:     ; $(MAKE) -C $(ASIC_DIR) drc
asic-lvs:     ; $(MAKE) -C $(ASIC_DIR) lvs
asic-lvs-pre: ; $(MAKE) -C $(ASIC_DIR) lvs-preflight
asic-lec-pnr: ; $(MAKE) -C $(ASIC_DIR) lec-pnr

## bootstrap: fetch all 42 submodules. Not `git clone --recursive` — see the script.
bootstrap:
	"$(CHIPLET_HOME)/scripts/bootstrap.sh"

## lint: structural lint (Verilator) over the wrapper RTL. Catches the class of
## defect `elab` cannot see (combinational loops, latches, width/undriven). See
## docs/LINT_FINDINGS.md.
lint:
	"$(CHIPLET_HOME)/scripts/lint.sh"

## vendor-check: no TSMC foundry collateral is TRACKED. This repository is
## PUBLIC and the PDK licence does not permit reproducing vendor files; the tree
## carried a 414 kB copy of TSMC's IO-driver LEF for months. Costs nothing and
## needs no tool, so it runs first in `check`. See the scripts for the full
## argument and for the "ship the transform, not the result" pattern.
##
## TWO SCANNERS, THE SAME TWO THE PR GATE RUNS, IN THE SAME ORDER. That is the
## whole reason this target changed shape:
##
##   check_no_vendor_collateral.sh    tracked *.lef by content SHA and by size,
##   (scripts/ci/)                    plus — only where a PDK is readable — runs
##                                    of VERBATIM vendor text in a file of any
##                                    type. The verbatim half is the only control
##                                    anywhere here that catches copying without
##                                    somebody first guessing which values are
##                                    the secret ones.
##
##   check-vendor-collateral.sh       extension (~20 collateral suffixes), size,
##   (ASIC/asic-toolkit/ci/)          content SHA, and seven text rules for
##                                    values, GDS layer/datatype pairs,
##                                    revision-coded release names, absolute site
##                                    paths and captured licence output. No PDK,
##                                    no licence, no tool.
##
## Neither is a superset of the other. The first cannot see a tracked .tlef at
## all — its corpus is the pathspec `*.lef`, which does not match .tlef and never
## looks at .lib, .captable, .map or .gds. Measured on a scratch tree of three
## ~244 kB invented vendor-shaped files under those suffixes: the first exits 0,
## the second exits 1.
##
## AND THIS TARGET RUNS BOTH BECAUSE CI DOES. A local gate that is greener than
## the PR check is worse than no local gate: it sends people to a red PR having
## already been told they were clean, and the second time that happens they stop
## running the local one. If the two ever need to differ, change CI first.
vendor-check:
	@set -uo pipefail
	rc=0
	echo "== scanner 1/2: scripts/ci/check_no_vendor_collateral.sh =="
	"$(CHIPLET_HOME)/scripts/ci/check_no_vendor_collateral.sh" || rc=1
	echo
	echo "== scanner 2/2: ASIC/asic-toolkit/ci/check-vendor-collateral.sh =="
	tk="$(TOOLKIT_DIR)/ci/check-vendor-collateral.sh"
	if [ ! -r "$$tk" ]; then
	    echo "make vendor-check: the toolkit content scanner is not present." >&2
	    echo >&2
	    if [ ! -d "$(TOOLKIT_DIR)/.git" ] && [ ! -f "$(TOOLKIT_DIR)/.git" ]; then
	        echo "  ASIC/asic-toolkit is not checked out. Run: make bootstrap" >&2
	    else
	        echo "  ASIC/asic-toolkit is checked out but has no" >&2
	        echo "  ci/check-vendor-collateral.sh — the submodule pin predates it." >&2
	        echo "  Roll the pin forward: git -C ASIC/asic-toolkit log --oneline -5" >&2
	    fi
	    echo >&2
	    echo "  THIS IS A FAILURE, NOT A SKIP. Scanner 1 above cannot see a" >&2
	    echo "  tracked .tlef, .lib, .captable, .map or .gds, so a green run" >&2
	    echo "  without scanner 2 would mean less than it looks like — which is" >&2
	    echo "  exactly what the PR gate was doing before both were wired in." >&2
	    exit 1
	fi
	# Run from CHIPLET_HOME: the scanner takes its corpus from `git ls-files` in
	# whatever repository it is invoked FROM, not from where the script lives.
	# Invoked from inside the submodule it would faithfully scan the toolkit.
	cd "$(CHIPLET_HOME)"
	bash "$$tk" < /dev/null || rc=1
	if [ $$rc -ne 0 ]; then
	    echo >&2
	    echo "== vendor-check FAILED — see the findings above ==" >&2
	    exit 1
	fi
	echo
	echo "== vendor-check OK: both scanners clean =="

## hooks: install the toolkit's pre-commit / pre-push guards into THIS clone.
## CI catches vendor collateral after it is pushed; a hook catches it before it
## leaves the machine, which for licensed foundry data is the difference that
## matters. The hooks and their installer are the TOOLKIT's — ASIC/asic-toolkit
## is a submodule, so they are reachable from here — and this target only calls
## the installer. It deliberately does NOT reimplement it: two copies of an
## install routine drift, and the one in this repo would be the stale one.
## Override the path with `make hooks HOOK_INSTALLER=/path/to/installer`.
HOOK_INSTALLER ?=
HOOK_ARGS      ?=
hooks:
	@set -uo pipefail
	inst="$(HOOK_INSTALLER)"
	if [ -z "$$inst" ]; then
	    # Candidate paths, in the order the toolkit is most likely to use.
	    # First hit wins; if the toolkit lands the installer somewhere else,
	    # add it here rather than copying its logic into this file.
	    for c in "$(TOOLKIT_DIR)/hooks/install.sh" \
	             "$(TOOLKIT_DIR)/hooks/install-hooks.sh" \
	             "$(TOOLKIT_DIR)/scripts/asic-flow-install-hooks" \
	             "$(TOOLKIT_DIR)/ci/install-hooks.sh"; do
	        if [ -x "$$c" ]; then inst="$$c"; break; fi
	    done
	fi
	if [ -z "$$inst" ]; then
	    echo "make hooks: no hook installer found in the toolkit." >&2
	    echo >&2
	    if [ ! -d "$(TOOLKIT_DIR)/.git" ] && [ ! -f "$(TOOLKIT_DIR)/.git" ]; then
	        echo "  ASIC/asic-toolkit is not checked out. Run: make bootstrap" >&2
	    else
	        echo "  ASIC/asic-toolkit is checked out, but none of these exist" >&2
	        echo "  and are executable:" >&2
	        echo "      ASIC/asic-toolkit/hooks/install.sh" >&2
	        echo "      ASIC/asic-toolkit/hooks/install-hooks.sh" >&2
	        echo "      ASIC/asic-toolkit/scripts/asic-flow-install-hooks" >&2
	        echo "      ASIC/asic-toolkit/ci/install-hooks.sh" >&2
	        echo >&2
	        echo "  The hooks may not have landed upstream yet, or the submodule" >&2
	        echo "  pin predates them: git -C ASIC/asic-toolkit log --oneline -5" >&2
	        echo "  Point this target at it directly with:" >&2
	        echo "      make hooks HOOK_INSTALLER=<path>" >&2
	    fi
	    echo >&2
	    echo "  UNTIL THEN THERE IS NO LOCAL GUARD. Run \`make vendor-check\`" >&2
	    echo "  by hand before every commit that adds a file; CI's vendor-guard" >&2
	    echo "  workflow is the backstop, and it only fires after you push." >&2
	    exit 1
	fi
	echo "== installing git hooks via $$inst =="
	cd "$(CHIPLET_HOME)"
	"$$inst" $(HOOK_ARGS) || exit $$?
	# Report what actually landed. This is confirmation, not installation --
	# the installer above owns where the hooks go and what they contain.
	hookdir=$$(git rev-parse --git-path hooks)
	echo
	echo "hooks now present in $$hookdir:"
	found=0
	for h in pre-commit pre-push; do
	    if [ -x "$$hookdir/$$h" ]; then echo "  $$h"; found=1; fi
	done
	if [ $$found -eq 0 ]; then
	    echo "  (none) — the installer exited 0 but installed no pre-commit or" >&2
	    echo "  pre-push hook. Treat this as a failure, not a clean run." >&2
	    exit 1
	fi

## check: the fast, EDA-license-free gates a fresh clone can run — licence
## hygiene, boundary coverage, structural lint. `make elab` and the verif/ envs
## need VCS on top.
check: vendor-check chip-boundary lint
	@echo "== check OK: vendor-check + chip-boundary + lint clean =="

## regress: the DYNAMIC gate — every simulation proof of the data plane, one
## pass/fail table (decode tx-gate + hready-loop guards, g2_peer_aperture, and
## the two-real-SoC g2_soc_pair write+read+burst). Needs VCS. `--quick` via
## `make regress ARGS=--quick` skips the two-SoC long pole. See scripts/regress.sh.
regress:
	"$(CHIPLET_HOME)/scripts/regress.sh" $(ARGS)

## cdc: first structural CDC pass over the integrated top (Cadence HAL via
## xrun -hal). ~25 min; needs an Xcelium/HAL license. See docs/CDC_FINDINGS.md.
cdc:
	"$(CHIPLET_HOME)/verif/cdc/run.sh"

## elab-strict: STRICT ASIC-elaboration gate — catches the synthesis blockers a
## simulator hides, above all a same-clock procedural MULTI-DRIVER (fc_shell/Genus
## reject it; VCS + Verilator pass it). xrun -hal, gates on MLTDRV in authored RTL.
## ~25 min; needs an Xcelium/HAL license. See docs/ELAB_STRICT_FINDINGS.md.
elab-strict:
	"$(CHIPLET_HOME)/verif/elab_strict/run.sh"

## chip-boundary: check the chip-boundary spec covers every RTL port, exactly once.
## Fails on an unclassified port, a stale name, or a direction/width mismatch.
## An unclassified port is silently dropped from the wrapper and its inputs float.
chip-boundary:
	python3 "$(CHIPLET_HOME)/scripts/check_chip_boundary.py"

## chip-wrapper: check, then emit build/chip/rtl/nanosoc_eth_chiplet_chip.v
chip-wrapper:
	python3 "$(CHIPLET_HOME)/scripts/check_chip_boundary.py" --emit "$(CHIPLET_HOME)/build/chip/rtl"

## elab: assemble the environment and run the VCS structural elaboration.
elab:
	source "$(CHIPLET_HOME)/set_env.sh"
	source "$(CHIPLET_HOME)/nanosoc-multicore-system/set_env.sh"
	source "$(CHIPLET_HOME)/tidelink/set_env.sh"
	mkdir -p "$(BUILD)"
	# Flatten the SoC's in-sync generated flist into a VCS-readable one (the
	# generator emits $()-syntax paths VCS cannot expand; regenerated each run
	# so it tracks the current build_soc).
	python3 "$(CHIPLET_HOME)/flist/flatten_soc_flist.py" \
	    "$${NANOSOC_MULTICORE_HOME}/flist/nanosoc_multicore.flist" > "$(CHIPLET_SOC_VCS_FLIST)"
	# Resolve TideLink's filelist to one definition per module (tool-independent).
	# V2, to match `asic-flist` — V2 IS THE SHIP CONFIGURATION. This gate used to
	# resolve the V1 tidelink_fpga.flist, so it structurally elaborated a PHY
	# configuration the chip does not ship, and it BROKE outright once the shared
	# local_overrides/Wlink.v began instantiating tidelink_fcemit_obs and
	# tidelink_winscan_obs: both are listed only in the V2 flist, so V1 failed
	# with `Error-[CFCILFBI] Cannot find cell in liblist`. No define change is
	# needed — the V2 flist carries TIDELINK_PHY_V2 via per-file shims rather
	# than a +define+.
	python3 "$(CHIPLET_HOME)/flist/resolve_tidelink_flist.py" \
	    "$${TIDELINK_HOME}/flists/tidelink_fpga_v2.flist" > "$(CHIPLET_TL_VCS_FLIST)"
	cd "$(BUILD)"
	echo "== vcs $(VCS_FLAGS) -f $(FLIST) -top $(TOP) -o $(SIMV) =="
	vcs $(VCS_FLAGS) -f "$(FLIST)" -top $(TOP) -o "$(SIMV)" -l "$(BUILD)/elab.log"

## asic-flist: render the two generated sub-flists the ASIC flist `-f`-includes.
## TIDELINK V2 IS THE SHIP CONFIGURATION: we resolve tidelink_top_full_asic_v2
## (the shared deps/tidelink-phy GPIO-PHY, +define+TIDELINK_PHY_V2), NOT the V1
## tidelink_top_full_asic. The two carry same-named modules and can never
## co-compile, so this line alone selects which PHY reaches synthesis.
## V2 needs the deps/tidelink-phy submodule (SSH remote, not fetched by a plain
## `git submodule update --init` over https) — `make bootstrap` covers it.
asic-flist:
	source "$(CHIPLET_HOME)/set_env.sh"
	source "$(CHIPLET_HOME)/nanosoc-multicore-system/set_env.sh"
	source "$(CHIPLET_HOME)/tidelink/set_env.sh"
	mkdir -p "$(BUILD)" "$(dir $(CHIPLET_SOC_ASIC_FLIST))"
	test -d "$${TIDELINK_HOME}/deps/tidelink-phy/rtl" || { \
	    echo "asic-flist: MISSING $${TIDELINK_HOME}/deps/tidelink-phy — the V2 PHY."; \
	    echo "            run: git -C $${TIDELINK_HOME} submodule update --init deps/tidelink-phy"; \
	    exit 1; }
	python3 "$(CHIPLET_HOME)/flist/flatten_soc_flist.py" \
	    "$${NANOSOC_MULTICORE_HOME}/flist/nanosoc_multicore_asic.flist" > "$(CHIPLET_SOC_ASIC_FLIST)"
	python3 "$(CHIPLET_HOME)/flist/resolve_tidelink_flist.py" \
	    "$${TIDELINK_HOME}/flists/tidelink_top_full_asic_v2.flist" > "$(CHIPLET_TL_ASIC_FLIST)"

## clean: remove elaboration artifacts.
clean:
	rm -rf "$(BUILD)"
