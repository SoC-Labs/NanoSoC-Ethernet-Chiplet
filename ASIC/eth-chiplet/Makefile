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
