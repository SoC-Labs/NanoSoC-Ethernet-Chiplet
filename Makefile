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

.PHONY: bootstrap elab chip-boundary chip-wrapper lint check regress cdc elab-strict clean
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
	@echo ""
	@echo "  Gates (what CI runs nightly — .github/workflows/nightly.yml):"
	@echo "    make check         chip-boundary + Verilator lint. No EDA licence."
	@echo "    make elab          VCS structural elaboration"
	@echo "    make elab-strict   xrun -hal; fails on a synthesis-blocking multi-driver"
	@echo "    make regress       every data-plane sim proof (ARGS=--quick to skip the long pole)"
	@echo "    make cdc           structural CDC pass (Cadence HAL)"
	@echo ""
	@echo "  Individual checks:"
	@echo "    make chip-boundary every RTL port classified exactly once"
	@echo "    make chip-wrapper  ...and emit build/chip/rtl/nanosoc_eth_chiplet_chip.v"
	@echo "    make lint          Verilator structural lint"
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
asic-drc:    ; $(MAKE) -C $(ASIC_DIR) drc_batch

## bootstrap: fetch all 42 submodules. Not `git clone --recursive` — see the script.
bootstrap:
	"$(CHIPLET_HOME)/scripts/bootstrap.sh"

## lint: structural lint (Verilator) over the wrapper RTL. Catches the class of
## defect `elab` cannot see (combinational loops, latches, width/undriven). See
## docs/LINT_FINDINGS.md.
lint:
	"$(CHIPLET_HOME)/scripts/lint.sh"

## check: the fast, EDA-license-free gates a fresh clone can run — boundary
## coverage + structural lint. `make elab` and the verif/ envs need VCS on top.
check: chip-boundary lint
	@echo "== check OK: chip-boundary + lint clean =="

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
