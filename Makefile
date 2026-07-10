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
# TideLink's flist with the shadowed deps module removed, so exactly one
# definition of every module reaches the compiler. See resolve_tidelink_flist.py:
# relying on VCS "last declaration wins" would let a first-wins tool silently
# bind an RTL copy that lacks the a2l reset-skew fix.
export CHIPLET_TL_VCS_FLIST := $(BUILD)/tidelink_vcs.f

VCS_FLAGS    := -full64 -sverilog -timescale=1ns/1ps

.PHONY: bootstrap elab chip-boundary chip-wrapper lint check clean

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
	python3 "$(CHIPLET_HOME)/flist/resolve_tidelink_flist.py" \
	    "$${TIDELINK_HOME}/flists/tidelink_fpga.flist" > "$(CHIPLET_TL_VCS_FLIST)"
	cd "$(BUILD)"
	echo "== vcs $(VCS_FLAGS) -f $(FLIST) -top $(TOP) -o $(SIMV) =="
	vcs $(VCS_FLAGS) -f "$(FLIST)" -top $(TOP) -o "$(SIMV)" -l "$(BUILD)/elab.log"

## clean: remove elaboration artifacts.
clean:
	rm -rf "$(BUILD)"
