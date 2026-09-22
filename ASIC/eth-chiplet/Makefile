#-----------------------------------------------------------------------------
# nanosoc-ethernet-chiplet / ASIC/eth-chiplet/Makefile
#
# The nanoSoC ASIC Toolkit entry point for this design, and the flow that builds
# the shipping GDS and netlist. Three lines, exactly as the toolkit's
# templates/Makefile.in specifies: everything about the DESIGN is in design.mk,
# everything about the FLOW is in the toolkit.
#
#     make help     every stage this design offers
#     make check    validate the design contract - costs no licence, run it first
#     make env      every variable the tools will see
#
# Stages write into build/$(RUN_TAG) (default `default`), so
#     make syn RUN_TAG=<name>
# keeps a run's netlist, reports, romlibs and GDS together in one directory.
#
# The root Makefile forwards here: `make asic-syn`, `make asic-pnr`, and so on.
# ../genus-innovus is the frozen legacy flow and is not on this path.
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------

ASIC_DIR := $(CURDIR)
include $(ASIC_DIR)/design.mk
include $(ASIC_FLOW_DIR)/mk/flow.mk

# The pre-P&R floorplan hazard gate. After flow.mk, because it APPENDS a
# prerequisite to the toolkit's `place` target and an included fragment can only
# do that once the target exists. Its four target names were checked against
# mk/*.mk, design.mk, common.mk, evidence.mk and the root Makefile first; an
# include guard cannot see a target collision.
#
#     make floorplan-hazards            ~3 s, no licence, also runs before place
#     make floorplan-hazards-selftest   prove every class BOTH directions
#     make floorplan-hazards-vars       what it will do, without doing it
include $(ASIC_DIR)/../floorplan-hazards.mk

# The evidence flow: gates, one report, publish. LAST, and after flow.mk on
# purpose - an include earlier would let a name here silently REPLACE a toolkit
# recipe, and an include guard cannot see a target collision. Every target it
# defines was checked against mk/*.mk, design.mk, common.mk and the root
# Makefile before it was written; all six were free.
#
#     make evidence            run it
#     make evidence-selftest   prove the gates BOTH directions, no licence
#     make evidence-vars       what it will do, without doing it
include $(ASIC_DIR)/../evidence.mk

# Signoff artefacts from a database an ECO produced. LAST, for the same reason
# the two includes above are: an include cannot see a target collision, and all
# three of its names were checked against mk/*.mk, design.mk, common.mk,
# floorplan-hazards.mk, evidence.mk and the root Makefile before being written.
#
#     make eco-emit RUN_TAG=<tag>      GDS + netlist from that run's ECO database
#     make eco-emit-vars RUN_TAG=<tag> what it would do, without doing it
include $(ASIC_DIR)/../eco.mk

# Signoff STA. THE STAGE IS THE TOOLKIT'S since 2026-09-22 (mk/sta.mk, included
# by mk/flow.mk above); this file now carries one line, STA_DIR, naming where
# this die keeps its policy, its site.env and its runs. LAST, for the reason the
# three includes above are: an include cannot see a target collision, and here
# it is also load-bearing in the other direction -- the toolkit's STA_DIR is a
# `?=`, so the override has to come after it.
#
#     make sta RUN_TAG=<tag> [IN_DB=<db>]   run and grade
#     make sta-gate RUN_TAG=<tag>           grade an existing run, no licence
#     make sta-vars RUN_TAG=<tag>           what it would do, without doing it
#     make sta-selftest                     the graders' own mutation batteries
include $(ASIC_DIR)/../sta.mk
