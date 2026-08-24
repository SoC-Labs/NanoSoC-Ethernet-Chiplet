#-----------------------------------------------------------------------------
# ASIC/evidence.mk - the ONE documented entry point for the evidence flow
#
#     make evidence                     run every gate, bundle, report
#     make evidence EVIDENCE_PUBLISH=1  ...and publish it to the artifact store
#     make evidence-render              re-render the HTML from an existing JSON
#     make evidence-publish             publish an already-collected bundle
#     make evidence-selftest            prove the gates and the five rules
#     make evidence-vars                what this will do, without doing it
#
# Included from ASIC/eth-chiplet/Makefile AFTER the toolkit's mk/flow.mk, and
# hooked into the flow by design.mk's
#
#     ROUTE_POST_TARGETS = evidence
#
# which the toolkit's route recipe calls once the stage has EXITED and its own
# route_gate.txt has been written and parsed. Not at the post_route Tcl hook:
# that fires 554 lines before the stage's verdict exists. See mk/flow.mk's
# `post_stage_targets` comment for the full reasoning.
#
# WHAT PROBLEM THIS SOLVES. Everything the flow proves is written into a
# gitignored directory (.gitignore:207 `build/`, :112 `ASIC/*/calibre_runs`),
# so a CI clone, a reviewer without a shell on this box, and the owner in three
# weeks on a different machine all find NOTHING. On 23 August an LVS report
# found the defect that reached the foundry, one day early, correct and
# complete, in an ephemeral scratchpad -- while a submission record written
# eleven minutes earlier said "LVS has NEVER RUN on this design".
#
# WALL CLOCK, measured 2026-08-24 on the pinfix candidate (a 302 MB stream):
#
#     route-message-census      ~40 s   (four session logs, one of them 213 MB)
#     macro-pin-connected      ~6-9 min (a full GDSII record walk, 2.6M PATHs
#                                        and 2.3M SREFs; this dominates)
#     signal-net-connectivity     <1 s
#     lvs-missing-connection      <5 s
#     stream-identity-published   ~2 s   (two HTTP round trips)
#     drc-tiers                  ~10 s
#     report + bundle             ~3 s
#     ------------------------------------------------------------------
#     collect + render         ~7-10 min
#     publish                  +~4 min  (zstd -19 of 302 MB, then the upload)
#
# A couple of extra hours on a build is explicitly acceptable to the owner; a
# flow that silently skips stages is not. Nothing here is skipped on cost.
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------

# The repo root, from THIS file, not from CURDIR: the target is reachable from
# ASIC/eth-chiplet (where the flow runs) and from the repo root (where a human
# runs it), and those have different CURDIRs.
EVIDENCE_MK_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
REPO_ROOT       ?= $(patsubst %/,%,$(dir $(EVIDENCE_MK_DIR)))

EVIDENCE_FLOW   ?= $(REPO_ROOT)/scripts/ci/evidence_flow.py

# WHICH BUILD IS BEING EVIDENCED. A spec, not an inference. This project's
# candidates are not all flow runs -- the current one came out of a four-arm
# experiment tree with no route_manifest.txt, and inferring its lineage is
# exactly the guess that got two arms confused on 2026-08-24. Default follows
# RUN_TAG so an in-flow call needs no argument; override for a one-off.
EVIDENCE_SPEC   ?= $(REPO_ROOT)/ASIC/eth-chiplet/evidence/$(RUN_TAG).json
EVIDENCE_OUT    ?= $(REPO_ROOT)/build/evidence/$(notdir $(basename $(EVIDENCE_SPEC)))

# Publishing is OPT-IN from the flow. A route that finishes at 03:00 should not
# push 300 MB to a store nobody has looked at yet; and a publish is a claim.
EVIDENCE_PUBLISH ?=

.PHONY: evidence evidence-collect evidence-render evidence-publish \
        evidence-selftest evidence-vars

## Run every gate, bundle the evidence, emit one report. ~7-10 min.
## Exit 5 means the report is REAL and does not say signed off - that is a
## working flow reporting an honest verdict, not a broken flow.
evidence:
	@test -f $(EVIDENCE_SPEC) || { \
	    echo "FAIL: no evidence spec at $(EVIDENCE_SPEC)"; \
	    echo "      A run is described by a spec, never inferred. Write one"; \
	    echo "      (see ASIC/eth-chiplet/evidence/pinfix-20260824.json) or"; \
	    echo "      point at one:  make evidence EVIDENCE_SPEC=<file>"; \
	    exit 1; }
	python3 $(EVIDENCE_FLOW) run --spec $(EVIDENCE_SPEC) --out $(EVIDENCE_OUT) \
	    $(if $(EVIDENCE_PUBLISH),--publish,)

## Gates and bundle only; no HTML, no publish.
evidence-collect:
	python3 $(EVIDENCE_FLOW) collect --spec $(EVIDENCE_SPEC) --out $(EVIDENCE_OUT)

## Re-render the HTML from the JSON already collected. The HTML is generated
## FROM the JSON so the two can never disagree.
evidence-render:
	python3 $(EVIDENCE_FLOW) render --out $(EVIDENCE_OUT)

## Publish an already-collected bundle: the stream WITH its raw md5 as an
## Artifactory property, the report, and every cited artefact.
evidence-publish:
	python3 $(EVIDENCE_FLOW) publish --spec $(EVIDENCE_SPEC) --out $(EVIDENCE_OUT) \
	    $(if $(EVIDENCE_FORCE),--force,)

## Prove the gates and the five report rules, in BOTH directions. Costs no
## licence, no PDK and no network except the store selftest. Run this first.
evidence-selftest:
	python3 $(EVIDENCE_FLOW) selftest
	python3 $(REPO_ROOT)/scripts/ci/route_message_census.py --selftest
	python3 $(REPO_ROOT)/scripts/ci/artifactory.py selftest
	@if [ -f $(REPO_ROOT)/scripts/ci/lvs_missing_connection.py ]; then \
	    python3 $(REPO_ROOT)/scripts/ci/lvs_missing_connection.py --selftest; \
	 else \
	    echo "NOT-MEASURED: scripts/ci/lvs_missing_connection.py is absent, so"; \
	    echo "  the LVS gate's proof did not run. That is a gap, not a pass."; \
	 fi
	cd $(REPO_ROOT)/ASIC/asic-toolkit && tclsh test/run-tests.tcl common/router_message_gate.test

## What the targets above will do, without doing any of it.
evidence-vars:
	@echo "REPO_ROOT        $(REPO_ROOT)"
	@echo "EVIDENCE_FLOW    $(EVIDENCE_FLOW)"
	@echo "EVIDENCE_SPEC    $(EVIDENCE_SPEC)"
	@echo "EVIDENCE_OUT     $(EVIDENCE_OUT)"
	@echo "EVIDENCE_PUBLISH $(if $(EVIDENCE_PUBLISH),yes,no)"
	@echo "RUN_TAG          $(RUN_TAG)"
	@# NO BACKTICKS. `make evidence` inside a double-quoted shell word is
	@# COMMAND SUBSTITUTION, and this line ran the whole evidence flow the
	@# first time it was tested -- from the target whose entire job is to
	@# report what WOULD happen without doing any of it. Same family as
	@# `make -n` not being a target-existence probe.
	@if [ -f $(EVIDENCE_SPEC) ]; then \
	    echo "spec             present"; \
	 else \
	    echo "spec             ABSENT - 'make evidence' will refuse"; \
	 fi
