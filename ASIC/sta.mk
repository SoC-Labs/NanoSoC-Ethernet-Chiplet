#-----------------------------------------------------------------------------
# sta.mk -- signoff STA (Tempus + standalone Quantus) on a build of this flow.
#
# WHY THIS FRAGMENT EXISTS. ASIC/sta/ has carried a mutation-proven signoff STA
# harness since August and, until 2026-09-16, no make target called it: every
# run was a hand-typed shell line, which is how six runs in August timed a
# stale build without anyone noticing. This target names the build, writes
# everything under ASIC/sta/work/<tag>/, and then GRADES the run -- binding
# first (which build is this, did it finish), timing second -- and refuses to
# report success unless both graders' verdict files say so.
#
# ARTEFACT, NOT EXIT STATUS. Tempus exits 0 after errors; run_sta.sh does not
# trust its exit code and neither does this. The graders write their verdicts
# to files and the recipe asserts on the files.
#
# TARGET NAMES were checked against mk/*.mk, design.mk, common.mk,
# floorplan-hazards.mk, evidence.mk, eco.mk and the root Makefile before being
# written: sta, sta-gate and sta-vars were all free. An include guard cannot
# see a target collision, which is why this note is here and not assumed.
#
#     make sta       RUN_TAG=<tag> [IN_DB=<db>]   run Tempus on the build, then grade
#     make sta-gate  RUN_TAG=<tag>                grade an existing run, no licence
#     make sta-vars  RUN_TAG=<tag>                what it would do, without doing it
#
# IN_DB defaults to the ECO database when the run has one, else the routed
# one: an ECO run's signoff database is <block>_eco (eco.mk makes the same
# choice for LVS). scripts/ci/sta_binding.py accepts the ECO database only
# through the run's eco_manifest.txt and its recorded, finished parent route.
#-----------------------------------------------------------------------------

STA_ROOT        ?= $(ASIC_DIR)/../sta
STA_TAG         ?= $(RUN_TAG)
IN_DB           ?= $(if $(wildcard $(WORK_DIR)/$(BLOCK)_eco),$(WORK_DIR)/$(BLOCK)_eco,$(WORK_DIR)/$(BLOCK)_routed)
STA_RUN_DIR      = $(STA_ROOT)/work/$(STA_TAG)
STA_REPORTS      = $(STA_RUN_DIR)/reports
STA_MANIFEST     = $(STA_REPORTS)/sta_manifest.txt
STA_GATE_OUT     = $(STA_REPORTS)/sta_gate.txt
STA_BINDING_OUT  = $(STA_REPORTS)/sta_binding.txt
STA_POLICY      ?= $(STA_ROOT)/sta_policy.json
STA_CPUS        ?= 8
STA_CI_DIR      ?= $(ASIC_DIR)/../../scripts/ci

.PHONY: sta sta-gate sta-vars

sta-vars:
	@echo "tag      : $(STA_TAG)"
	@echo "db       : $(IN_DB)"
	@test -d "$(IN_DB)" && echo "db       : PRESENT" || echo "db       : MISSING"
	@echo "run dir  : $(STA_RUN_DIR)"
	@echo "policy   : $(STA_POLICY)"
	@echo "cpus     : $(STA_CPUS)"
	@echo "graders  : $(STA_CI_DIR)/sta_binding.py, $(STA_ROOT)/sta_gate.py"
	@test -r "$(STA_ROOT)/site.env" && echo "site.env : present" || \
	    echo "site.env : MISSING -- cp $(STA_ROOT)/site.env.example $(STA_ROOT)/site.env and edit"

sta:
	@test -d "$(IN_DB)" || { \
	    echo "FAIL: no database at $(IN_DB)"; \
	    echo "      Set IN_DB, or route/ECO the build first (make route RUN_TAG=$(RUN_TAG))"; exit 1; }
	@mkdir -p $(STA_RUN_DIR)/reports $(STA_RUN_DIR)/outputs
	python3 $(STA_ROOT)/make_sta_mmmc.py --db $(IN_DB) --out $(STA_RUN_DIR)/mmmc_sta.tcl < /dev/null
	cd $(STA_RUN_DIR) && STA_TAG=$(STA_TAG) STA_CPUS=$(STA_CPUS) \
	    $(STA_ROOT)/run_sta.sh $(IN_DB) < /dev/null
	$(MAKE) --no-print-directory sta-gate STA_TAG=$(STA_TAG)

# The verdicts. Both graders print their verdict line last; both files are
# kept beside the reports they judge. `| tee` would hide the exit status and
# the exit status is not what is asserted anyway -- the verdict line is.
sta-gate:
	@test -s "$(STA_MANIFEST)" || { \
	    echo "FAIL: no manifest at $(STA_MANIFEST) -- the run never started, or STA_TAG is wrong"; exit 1; }
	@grep -q '^sta_finished = ' "$(STA_MANIFEST)" || { \
	    echo "FAIL: $(STA_MANIFEST) has no sta_finished row -- the run did not reach its last line"; exit 1; }
	-python3 $(STA_CI_DIR)/sta_binding.py --reports $(STA_REPORTS) \
	    --build-tag $(STA_TAG) --build-root $(BUILD_DIR) < /dev/null > $(STA_BINDING_OUT) 2>&1
	-python3 $(STA_ROOT)/sta_gate.py --reports $(STA_REPORTS) \
	    --policy $(STA_POLICY) < /dev/null > $(STA_GATE_OUT) 2>&1
	@cat $(STA_BINDING_OUT)
	@cat $(STA_GATE_OUT)
	@test -s "$(STA_GATE_OUT)" && test -s "$(STA_BINDING_OUT)" || { \
	    echo "FAIL: a grader wrote nothing -- see $(STA_GATE_OUT) and $(STA_BINDING_OUT)"; exit 1; }
	@grep -q '^BINDING: PASS' "$(STA_BINDING_OUT)" || { \
	    echo "FAIL: the run is not bound to build $(STA_TAG) -- $(STA_BINDING_OUT)"; exit 1; }
	@grep -q '^GATE: PASS' "$(STA_GATE_OUT)" || { \
	    echo "FAIL: signoff STA gate -- $(STA_GATE_OUT)"; exit 1; }
	@echo "OK: signoff STA $(STA_TAG) passes binding and gate ($(STA_GATE_OUT))"
