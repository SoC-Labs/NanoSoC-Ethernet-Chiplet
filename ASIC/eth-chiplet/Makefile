#-----------------------------------------------------------------------------
# nanosoc-ethernet-chiplet / ASIC/eth-chiplet/Makefile
#
# The nanoSoC ASIC Toolkit entry point for this design. Three lines, exactly as
# the toolkit's templates/Makefile.in specifies: everything about the design is
# in design.mk, everything about the flow is in the toolkit.
#
#     make help     targets
#     make check    validate the contract - costs no licence, run it first
#     make env      every variable the tools will see
#
# THIS IS ADDITIVE. It does not replace ../genus-innovus, which is still the
# only thing in this repository that has ever produced a GDSII, and nothing
# here is on that path. `make -C ASIC/genus-innovus pnr_all` is unchanged.
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------

ASIC_DIR := $(CURDIR)
include $(ASIC_DIR)/design.mk
include $(ASIC_FLOW_DIR)/mk/flow.mk
