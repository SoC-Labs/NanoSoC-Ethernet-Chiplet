#-----------------------------------------------------------------------------
# ASIC/floorplan-hazards.mk - the pre-P&R floorplan hazard gate, wired in
#
#     make floorplan-hazards            run it (this is also a prerequisite of
#                                       `place`, so it runs by itself)
#     make floorplan-hazards-strict     ...and fail on the advisories too
#     make floorplan-hazards-selftest   prove every class BOTH directions
#     make floorplan-hazards-vars       what it will do, without doing it
#
# WHY THIS FILE EXISTS. scripts/ci/check_floorplan_hazards.py has been in the
# tree since 22 August, it is fixture-validated in both directions, it runs in
# about three seconds and it needs no licence and no tool. Nothing invoked it.
# Not a make target, not a `.mk`, not a workflow -- measured by grep on
# 2026-08-25, the only references to it anywhere in the tree were a comment in
# floorplan.tcl, a vendor-guard allowlist entry and its own fixture README.
#
# In that time it would have caught, in seconds each:
#
#   * two macro edges inside an M9 stripe band, found by a metal short after a
#     place run (class 1 / class 2, 2026-08-21)
#   * two macro pin edges half a track pitch off the escape-layer grid, found
#     by five stage-owned DRC violations ONE HOUR into a 2h38m route
#     (class 4a, 2026-08-25, commit 2cd12a4)
#
# A gate nothing calls is a document. This is the wiring.
#
# WHERE IT IS HOOKED, AND WHY THERE. `place` is the stage that sources
# FLOORPLAN_TCL and POWER_PLAN_TCL, so it is the last moment the answer is free
# and the first moment it matters. The gate is added as a PREREQUISITE of
# `place` rather than as a line inside the recipe, because the recipe belongs to
# the toolkit submodule and a project must not edit it -- appending a
# prerequisite from an included fragment is the supported way to do this and
# collides with nothing.
#
# It is deliberately NOT hooked at post-stage the way `evidence` is (see
# evidence.mk and mk/flow.mk's `post_stage_targets`). That hook exists so a
# report can read a stage's own verdict AFTER the stage exits. This gate is the
# opposite shape: its whole value is being wrong-answer-cheap BEFORE the stage
# starts.
#
# TARGET NAMES. Checked against ASIC/asic-toolkit/mk/*.mk, ASIC/eth-chiplet/
# design.mk, ASIC/common.mk, ASIC/evidence.mk and the root Makefile before they
# were written; all four were free. An include guard cannot see a target
# collision -- a name defined here that already exists upstream would silently
# REPLACE that recipe -- so the check is the only protection and it has to be
# redone whenever a target is added.
#
# WHAT FAILS THE BUILD. The script splits its classes by what a flag MEANS:
#
#   HARD      class 1, class 2, class 4a - exact arithmetic, each reproduces a
#             defect that really happened, each prints the move that clears it.
#             These fail `place` before Innovus is launched.
#   ADVISORY  class 3 - over-approximating by its own header, currently sitting
#             at 8 on a clean floorplan. Printed and counted, does not fail.
#             `make floorplan-hazards-strict` gates on it as well.
#   CENSUS    class 4b - never a pass or a fail.
#
# The advisory count is in the verdict line and in the JSON, so a run record
# cannot quote a PASS without also carrying what it passed with.
#
# Exit 2 from the script means it COULD NOT MEASURE - a missing input, a census
# row at zero, a cross-check that failed. That fails `place` too, and on purpose:
# this repository's recurring defect is a check that measured nothing and
# reported success.
#
# WALL CLOCK, measured 2026-08-25 on this design (21 placed macros):
#
#     floorplan-hazards            ~3 s     no licence, no tool, no PDK read
#     floorplan-hazards-selftest   ~52 s    24 scratch re-runs, still no licence
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------

# The repo root, from THIS file rather than from CURDIR, for the same reason
# evidence.mk does it: the targets are reachable from ASIC/eth-chiplet (where
# the flow runs) and from the repo root (where a human runs them), and those
# have different CURDIRs.
FPHZ_MK_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
REPO_ROOT   ?= $(patsubst %/,%,$(dir $(FPHZ_MK_DIR)))

FPHZ        ?= $(REPO_ROOT)/scripts/ci/check_floorplan_hazards.py

# THE GATE READS THE FILES THE STAGE WILL READ, not the script's own defaults.
# design.mk owns both paths and either can be overridden per invocation; a gate
# checking a different floorplan from the one Innovus is about to source would
# be worse than no gate.
FPHZ_FLOORPLAN  ?= $(FLOORPLAN_TCL)
FPHZ_POWER_PLAN ?= $(POWER_PLAN_TCL)

# The netlist resolves each place_macro pattern to exactly one instance -- the
# same rule place_macro itself enforces, and the reason the checker can refuse a
# stale pattern instead of silently measuring 15 macros out of 21.
#
# RECURSIVE `=`, not `:=`: the wildcard has to be evaluated when the recipe
# runs, not when this file is read. At read time a syn that is about to write
# the netlist has not written it yet.
FPHZ_NETLIST_CANDIDATES = $(OUT_DIR)/$(BLOCK)_gate_power.v \
                          $(SYN_OUT_DIR)/$(BLOCK)_gate_power.v \
                          $(BUILD_DIR)/$(IN_RUN_TAG)/outputs/$(BLOCK)_gate_power.v
FPHZ_NETLIST = $(firstword $(wildcard $(FPHZ_NETLIST_CANDIDATES)))

FPHZ_JSON ?= $(REPORT_DIR)/floorplan_hazards.json
FPHZ_ARGS ?=

.PHONY: floorplan-hazards floorplan-hazards-strict \
        floorplan-hazards-selftest floorplan-hazards-vars

## Pre-P&R floorplan hazard gate. Seconds, no licence, no tool. Runs as a
## prerequisite of `place`; run it by hand any time you move a macro.
floorplan-hazards:
	@test -r $(FPHZ) || { \
	    echo "FAIL: the floorplan hazard gate is missing:"; \
	    echo "      $(FPHZ)"; \
	    echo "      A required gate whose detector is absent must FAIL, never skip."; \
	    exit 1; }
	@# THE ENVIRONMENT IS CHECKED HERE AS WELL AS IN THE SCRIPT, and the
	@# duplication is deliberate. The script refuses cleanly without these two
	@# and says what they are; what it cannot say is which file in THIS project
	@# is supposed to have set them. ../common.mk exports both, so an empty
	@# value here means the include chain is broken, not that the caller forgot.
	@if [ -z "$(MEM_BASE)" ] || [ -z "$(TSMC_65_HOME)" ]; then \
	    echo "FAIL: the floorplan hazard gate needs MEM_BASE and TSMC_65_HOME."; \
	    echo "      MEM_BASE        $(if $(MEM_BASE),set,EMPTY)"; \
	    echo "      TSMC_65_HOME    $(if $(TSMC_65_HOME),set,EMPTY)"; \
	    echo "      ASIC/common.mk exports both and design.mk includes it, so an"; \
	    echo "      empty value means this make was not entered through"; \
	    echo "      ASIC/eth-chiplet/Makefile. Either enter through it, or pass the"; \
	    echo "      libraries directly:  FPHZ_ARGS='--lef <macro.lef> --tech-lef <t.tlef>'"; \
	    echo "      NOT SKIPPED. A gate that cannot read its inputs has not passed."; \
	    exit 1; \
	 fi
	@if [ -z "$(FPHZ_NETLIST)" ]; then \
	    echo "FAIL: no gate netlist, so place_macro patterns cannot be resolved to"; \
	    echo "      instances and the gate would measure nothing. Looked in:"; \
	    for f in $(sort $(FPHZ_NETLIST_CANDIDATES)); do echo "        $$f"; done; \
	    echo "      Run syn first, point SYN_RUN_TAG at the run that has one, or"; \
	    echo "      name it:  make floorplan-hazards FPHZ_NETLIST=<path>"; \
	    exit 1; \
	 fi
	@mkdir -p $(dir $(FPHZ_JSON))
	python3 $(FPHZ) \
	    --floorplan  $(FPHZ_FLOORPLAN) \
	    --power-plan $(FPHZ_POWER_PLAN) \
	    --netlist    $(FPHZ_NETLIST) \
	    --json       $(FPHZ_JSON) \
	    $(FPHZ_ARGS)

## The same, with the class-3 advisories gating as well. Not what `place` runs:
## class 3 flags pairs that produced no marker, so gating on it by default would
## make this permanently red for a reason everybody already knows is benign --
## which is exactly how the last gate here stopped being read.
floorplan-hazards-strict:
	@$(MAKE) --no-print-directory floorplan-hazards FPHZ_ARGS="$(FPHZ_ARGS) --strict"

## Prove every class in BOTH directions against pinned fixtures: a revision that
## carries each defect must FAIL on it, the revision that fixed it must PASS,
## every prescribed move must actually clear the finding it was prescribed for,
## and a mutilated input must exit 2 rather than 0. Costs no licence.
floorplan-hazards-selftest:
	python3 $(FPHZ) --selftest \
	    --floorplan $(FPHZ_FLOORPLAN) --power-plan $(FPHZ_POWER_PLAN) \
	    $(if $(FPHZ_NETLIST),--netlist $(FPHZ_NETLIST),)

## What the gate will read and write, without reading or writing any of it.
floorplan-hazards-vars:
	@echo "FPHZ             $(FPHZ)"
	@echo "FPHZ_FLOORPLAN   $(FPHZ_FLOORPLAN)"
	@echo "FPHZ_POWER_PLAN  $(FPHZ_POWER_PLAN)"
	@echo "FPHZ_NETLIST     $(if $(FPHZ_NETLIST),$(FPHZ_NETLIST),NONE FOUND - the gate will refuse)"
	@echo "FPHZ_JSON        $(FPHZ_JSON)"
	@echo "FPHZ_ARGS        $(FPHZ_ARGS)"
	@echo "MEM_BASE         $(if $(MEM_BASE),set,EMPTY - the gate will refuse)"
	@echo "TSMC_65_HOME     $(if $(TSMC_65_HOME),set,EMPTY - the gate will refuse)"
	@echo "hooked as        a prerequisite of 'place'"

# THE HOOK. A prerequisite line with NO recipe, which APPENDS to the toolkit's
# `place: dirs check-quiet sdc-check`. Appending is the only form that is safe
# here: a second recipe for `place` would replace the toolkit's, and make says
# so only as a warning.
#
# Prerequisites of one target may run in any order under -j, so nothing here may
# assume `dirs` has run; the recipe above makes its own output directory.
place: floorplan-hazards
