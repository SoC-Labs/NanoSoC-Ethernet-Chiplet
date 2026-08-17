#-----------------------------------------------------------------------------
# rail_project.mk — static rail (IR-drop) analysis, as a flow stage.
# A joint work commissioned on behalf of SoC Labs, under Arm Academic
# Access license.
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# WHAT THIS ADDS THAT THE FLOW DID NOT HAVE
#
#   Until now nothing in this pipeline computed a VOLTAGE. The nearest thing was
#   pg_capacity, which rates the grid's EM CEILING in milliamps — a different
#   quantity entirely — and `2b_pnr_place_eval.tcl` §12, which halts the run on
#   an RV-VIA COUNT. That count is not a margin in any units: it was derived
#   from one day's tool configuration, and net VDD turns out to have no RV via
#   at top level at all, so the floor was guarding a plane the core supply does
#   not cross. This stage replaces a count with a measurement.
#
# EVERY LINE IS TAGGED — same convention as drc_project.mk and lvs_project.mk
#   [PROJECT] this design. Changes when the design changes.
#   [PDK]     this process / library release.
#   [SITE]    where things are installed on this machine.
#   [FLOW]    a flow default. You will rarely touch these.
#
# WHY `?=` EVERYWHERE: so every value can be overridden on the command line
# without editing the file —
#     make rail RAIL_RUN_TAG=full-20260814
#     make rail-gate RAIL_TIER=report
#
# LICENCE POOLS. The solve runs UNDER INNOVUS, not under the `voltus` binary:
# that binary aborts on this database with IMPESI-3490 ("cdB based analysis is
# not supported with CMMMC configuration"), while the identical rail commands
# resolve inside the Innovus Stylus shell and read the database without
# complaint. So `rail` takes an Innovus seat plus a Voltus_Power_Integrity seat
# on demand. `rail-gate` and `rail-selftest` take NEITHER and need no database.
#-----------------------------------------------------------------------------

# TRAILING `# [TAG]` COMMENTS ARE NOT USED HERE, and that is deliberate rather
# than a style choice: make keeps the whitespace between a value and the `#`,
# so `RAIL_RUN_TAG ?= fp1505    # [PROJECT]` sets the value to "fp1505" plus
# five spaces, and every path built from it acquires a space in the middle.
# Written that way first, it produced a database path that printed correctly in
# a status line and did not exist. The tags go above the assignment, which is
# also the convention drc_project.mk already uses.

# [FLOW]
RAIL_DIR        ?= $(DESIGN_DIR)/rail
# [PROJECT]
RAIL_BUILD_ROOT ?= $(abspath $(DESIGN_DIR)/../eth-chiplet/build)

# [PROJECT] WHICH BUILD. There is deliberately no "latest" symlink chase here.
# Two sessions on this project have reached stale conclusions by pointing at the
# directory with the obvious name, and a rail number quoted against a database
# nobody meant to analyse is worse than no rail number. Name the run.
RAIL_RUN_TAG    ?= fp1505
# [FLOW]
RAIL_DB_STAGE   ?= routed
RAIL_DB         ?= $(RAIL_BUILD_ROOT)/$(RAIL_RUN_TAG)/work/$(BLOCK)_$(RAIL_DB_STAGE)

# [FLOW] Outputs. Under rail/work/, which is GITIGNORED ON PURPOSE: the
# pg_capacity report beside it prints per-layer current-density limits read
# straight out of the vendor tech LEF, and this repository is public.
RAIL_WORK       ?= $(RAIL_DIR)/work
RAIL_TAG        ?= $(RAIL_RUN_TAG)
RAIL_OUT        ?= $(RAIL_WORK)/$(RAIL_TAG)
# [PROJECT]
RAIL_BUDGETS    ?= $(RAIL_DIR)/rail_budgets.txt
# [SITE]
RAIL_CPU        ?= 4

# [PROJECT] The analysis voltage. NOT the 1.20 V process nominal: this is the voltage the
# design is actually analysed at (mmmc default_libset_max resolves to the
# ss/125C/-10% corner) and the one report_power prices it at. The stage RE-READS
# it out of report_power's own rail table and the gate fails if the two
# disagree, because with four contradictory supply voltages on record the wrong
# divisor scales every percentage while leaving every number plausible.
RAIL_VCORE      ?= 1.08
RAIL_TEMP       ?= 125

# [FLOW] signoff = blocking, and EM must have been analysed. report = measure
# and print.
RAIL_TIER       ?= report

RAIL_ENV = TSMC_65_HOME=$(TSMC_65_HOME) \
           RAIL_DB=$(RAIL_DB) RAIL_WORK=$(RAIL_WORK) RAIL_TAG=$(RAIL_TAG) \
           RAIL_VCORE=$(RAIL_VCORE) RAIL_TEMP=$(RAIL_TEMP) RAIL_CPU=$(RAIL_CPU)

.PHONY: rail rail-gate rail-selftest rail-status rail-clean

## rail: static IR-drop analysis on $(RAIL_DB), then judge it.
##   The `< /dev/null` is NOT decoration. An uncaught Tcl error leaves Innovus
##   sitting at an interactive prompt holding an Innovus AND a Voltus licence
##   indefinitely, and nothing in the log says so.
##   The `-log` name must not collide with a DIRECTORY: `-log foo` where foo/ is
##   a directory silently becomes foo/innovus.log, and a stale foo.log from the
##   previous failed run is then read as this run's verdict. That has happened
##   here, producing two contradictory verdicts that were both real files.
rail:
	@test -d "$(RAIL_DB)" || { \
	  echo "FAIL: no database at $(RAIL_DB)"; \
	  echo "  Set RAIL_RUN_TAG=<build> (looked under $(RAIL_BUILD_ROOT))."; \
	  echo "  Available:"; ls -1 $(RAIL_BUILD_ROOT) 2>/dev/null | sed 's/^/    /'; \
	  exit 1; }
	@mkdir -p $(RAIL_WORK)
	@echo "rail: analysing $(RAIL_DB)"
	@cd $(RAIL_WORK) && env $(RAIL_ENV) \
	    innovus -stylus -nowin -files $(RAIL_DIR)/rail_run.tcl \
	            -log rail_$(RAIL_TAG) -overwrite < /dev/null \
	            > rail_$(RAIL_TAG).console 2>&1 || true
	@$(MAKE) --no-print-directory rail-gate

## rail-gate: recompute the verdict from the artefacts. No licence, no database.
##   Separate from `rail` on purpose. The tools in this family PRINT `**ERROR`
##   AND RETURN SUCCESS — report_rail, report_resistance and set_power_pads have
##   all been observed doing it — so the stage script's exit code is worthless
##   and the verdict must be recomputable from the files alone, by anyone,
##   months later, without a seat.
rail-gate:
	@test -f "$(RAIL_OUT)/census.txt" || { \
	  echo "FAIL: no census at $(RAIL_OUT)/census.txt — the stage did not run."; \
	  echo "  Run: make rail RAIL_RUN_TAG=$(RAIL_RUN_TAG)"; exit 1; }
	@python3 $(RAIL_DIR)/rail_gate.py \
	    --census  $(RAIL_OUT)/census.txt \
	    --budgets $(RAIL_BUDGETS) \
	    --tier    $(RAIL_TIER) \
	    --json    $(RAIL_OUT)/verdict.json

## rail-selftest: can the gate actually FAIL? A mutation battery of runs that
##   are broken in each of the specific ways this project has already been
##   bitten by. Needs no licence, no database and no PDK, so CI can run it.
rail-selftest:
	@python3 $(RAIL_DIR)/rail_gate.py --selftest

## rail-status: what has been analysed, and against which database.
rail-status:
	@echo "rail db      : $(RAIL_DB)"
	@echo "rail out     : $(RAIL_OUT)"
	@echo "rail budgets : $(RAIL_BUDGETS)"
	@echo "rail tier    : $(RAIL_TIER)"
	@for d in $(RAIL_WORK)/*/census.txt; do \
	  [ -f "$$d" ] || continue; \
	  printf '  %-28s %s\n' "$$(basename $$(dirname $$d))" \
	    "$$(grep -m1 '^db.path=' $$d | cut -d= -f2-)"; \
	done

## rail-clean: remove this tag's results only. Never the whole work tree — the
##   resistance and pad-geometry runs beside it cost hours.
rail-clean:
	rm -rf $(RAIL_OUT) $(RAIL_WORK)/rail_$(RAIL_TAG).log \
	       $(RAIL_WORK)/rail_$(RAIL_TAG).logv $(RAIL_WORK)/rail_$(RAIL_TAG).console
