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
