#-----------------------------------------------------------------------------
# eco.mk -- signoff artefacts from a database an ECO produced.
#
# WHY THIS FRAGMENT EXISTS. opt_signoff writes a DATABASE and stops. Every
# signoff gate -- drc, lvs, lec-pnr -- reads a stream or a netlist, so until
# those are emitted an ECO'd build cannot be signed off at all. Neither
# restream script fills the gap: the toolkit's is GDS-only and says its output
# "must be a NEW name -- never the signoff artefact", and genus-innovus's is
# wired to that flow's own work/ directory rather than to build/<tag>.
#
# AND THE NETLIST IS THE POINT. opt_signoff resizes and VT-swaps cells, so an
# ECO'd database's netlist genuinely differs from its parent's. Running lec-pnr
# or lvs against the PARENT build's netlist would compare two different designs
# and report equivalence about neither.
#
# TARGET NAMES were checked against mk/*.mk, design.mk, common.mk,
# floorplan-hazards.mk, evidence.mk and the root Makefile before being written:
# all three were free. An include guard cannot see a target collision, which is
# why this note is here and not assumed.
#
#     make eco-emit RUN_TAG=<tag>     write outputs/ from that run's ECO database
#     make eco-emit-vars RUN_TAG=...  what it would do, without doing it
#-----------------------------------------------------------------------------

ECO_EMIT_TCL     ?= $(ASIC_DIR)/../genus-innovus/scripts/eco/emit_outputs.tcl
ECO_EMIT_DB      ?= $(RUN_DIR)/work/$(BLOCK)_routed
ECO_EMIT_OUT_DIR ?= $(RUN_DIR)/outputs

.PHONY: eco-emit eco-emit-vars

eco-emit-vars:
	@echo "script : $(ECO_EMIT_TCL)"
	@echo "db     : $(ECO_EMIT_DB)"
	@echo "out    : $(ECO_EMIT_OUT_DIR)"
	@echo "block  : $(BLOCK)"
	@test -d "$(ECO_EMIT_DB)" && echo "db     : PRESENT" || echo "db     : MISSING"

# DEPENDS ON THE FLOW'S OWN INPUT CHECK, and that is not belt-and-braces.
# On 2026-09-11 this target ran without it and emitted a GDS missing both boot
# ROMs. `make check` had the answer already -- "no cc_rom macro directory at
# <run>/romlibs/cc_rom" -- and refused the very next gate for exactly that
# reason. A hand-made run directory is precisely the case where the standing
# input check earns its keep, so this target no longer steps around it.
eco-emit: check-quiet
	@test -r "$(ECO_EMIT_TCL)" || { echo "FAIL: no emitter at $(ECO_EMIT_TCL)"; exit 1; }
	@test -d "$(ECO_EMIT_DB)"  || { \
	    echo "FAIL: no ECO database at $(ECO_EMIT_DB)"; \
	    echo "      Set ECO_EMIT_DB, or run the ECO first:"; \
	    echo "        EVP_ECO_IN=<parent db> EVP_ECO_RUN=$(RUN_DIR) \\"; \
	    echo "          ASIC/genus-innovus/scripts/eco/run_opt_signoff.sh"; exit 1; }
	@mkdir -p $(ECO_EMIT_OUT_DIR)
	cd $(RUN_DIR) && \
	    EVP_EMIT_DB=$(ECO_EMIT_DB) \
	    EVP_EMIT_OUT_DIR=$(ECO_EMIT_OUT_DIR) \
	    EVP_EMIT_BLOCK=$(BLOCK) \
	    $(INNOVUS) $(ECO_EMIT_TCL) < /dev/null
	@# ARTEFACT, NOT EXIT STATUS. Innovus exits 0 having written nothing --
	@# measured on this project 2026-08-13, when read_db aborted and make still
	@# reported success. The script has its own guards, but they cannot run if
	@# it dies before reaching them.
	@test -s "$(ECO_EMIT_OUT_DIR)/$(BLOCK).gds" || { \
	    echo "FAIL: no GDS at $(ECO_EMIT_OUT_DIR)/$(BLOCK).gds"; \
	    echo "      Innovus may have exited 0 anyway -- read the log:"; \
	    echo "        grep -nE '\*\*ERROR|IMPOGDS-|IMPIMEX-' $(RUN_DIR)/logs/*.log*"; exit 1; }
	@test -s "$(ECO_EMIT_OUT_DIR)/$(BLOCK)_pnr.v" || { \
	    echo "FAIL: no netlist at $(ECO_EMIT_OUT_DIR)/$(BLOCK)_pnr.v"; \
	    echo "      lec-pnr and lvs have no input, and the parent build's"; \
	    echo "      netlist is NOT a substitute -- this ECO changed cells."; exit 1; }
	@echo "OK: emitted $$(ls -la $(ECO_EMIT_OUT_DIR)/$(BLOCK).gds | awk '{print $$5}') byte GDS + netlist"
	@echo "    next: make lec-pnr RUN_TAG=$(RUN_TAG)   (cheapest gate, ~7 min)"

#-----------------------------------------------------------------------------
# LVS ON A BUILD OF THIS FLOW.
#
# `make lvs` here CANNOT WORK, and this is not a bug in either flow. The
# toolkit's lvs-batch needs $(OUT_DIR)/$(BLOCK)_lvs.gds -- a PG-labelled
# re-stream -- and nothing in the eth-chiplet flow builds one. The thing that
# does is lvs-flow/lvs_pg_emit.tcl, reachable only through ASIC/genus-innovus,
# whose Makefile does not include eth-chiplet/design.mk. So the LVS defaults
# there are the LEGACY ones:
#
#   LVS_PG_DB       defaults to work/<block> -- the BARE name. This flow writes
#                   <block>_placed/_cts/_routed, so the default exists in NO run
#                   and the preflight MISSes even on a fully routed one.
#   ROM merge/CDL   default under genus-innovus/, not this run's romlibs. The
#                   ROMs are MASK PROGRAMMED and per-run: comparing run A's
#                   stream against run B's ROMs is a content error wearing the
#                   costume of a default.
#
# design.mk ALREADY computes all four correctly (:632, :642, :758, :792). They
# are simply invisible across the flow seam. So this forwards them rather than
# restating them -- a second copy of a ROM path is the defect above, written by
# hand.
#
# MEASURED 2026-09-14 doing this by hand on vt6opt-20260911: four overrides,
# discovered one preflight failure at a time. The preflight named every one
# without taking a licence, which is the flow working; needing them is not.
#
#     make eco-lvs-preflight RUN_TAG=<tag>   resolve inputs only, no licence
#     make eco-lvs           RUN_TAG=<tag>   PG re-stream, then full LVS

ECO_LVS_DIR ?= $(ASIC_DIR)/../genus-innovus
# An ECO run's database is <block>_eco, not <block>_routed. design.mk's
# LVS_PG_DB names the latter, which exists in no ECO run; forwarding it as-is
# made `make eco-lvs` on an ECO run preflight-MISS. Prefer the ECO database
# when this run has one.
ECO_LVS_DB  ?= $(if $(wildcard $(WORK_DIR)/$(BLOCK)_eco),$(WORK_DIR)/$(BLOCK)_eco,$(LVS_PG_DB))
ECO_LVS_FWD  = LVS_RUN='$(RUN_DIR)' \
               LVS_PG_DB='$(ECO_LVS_DB)' \
               LVS_PG_MERGE_GDS='$(LVS_PG_MERGE_GDS)' \
               ROMLIBS_DIR='$(ROMLIBS_DIR)' \
               LVS_ROM_CDL_DIR='$(LVS_ROM_CDL_DIR)'

.PHONY: eco-lvs eco-lvs-preflight

eco-lvs-preflight:
	$(MAKE) -C $(ECO_LVS_DIR) lvs-pg-preflight $(ECO_LVS_FWD)
	$(MAKE) -C $(ECO_LVS_DIR) lvs-preflight    $(ECO_LVS_FWD)

eco-lvs: eco-lvs-preflight
	$(MAKE) -C $(ECO_LVS_DIR) lvs_pg_gds $(ECO_LVS_FWD)
	@# ARTEFACT, NOT EXIT STATUS -- the standing rule in this file.
	@test -s '$(OUT_DIR)/$(BLOCK)_lvs.gds' || { \
	    echo "FAIL: no PG re-stream at $(OUT_DIR)/$(BLOCK)_lvs.gds"; exit 1; }
	@echo "OK: PG re-stream $$(stat -c%s '$(OUT_DIR)/$(BLOCK)_lvs.gds') bytes"
	$(MAKE) -C $(ECO_LVS_DIR) lvs_batch $(ECO_LVS_FWD)
