# One SoC variant: make -f cocotb.mk VARIANT=shipped|gated EXPECT=defect|clean
include $(dir $(lastword $(MAKEFILE_LIST)))env.mk
VARIANT         ?= shipped
export EXPECT   ?= defect
SIM             = vcs
TOPLEVEL_LANG   = verilog
TOPLEVEL        = tb_top
COCOTB_TOPLEVEL = tb_top
MODULE          = test_soc_hsel
COCOTB_TEST_MODULES = test_soc_hsel
SIM_BUILD       = $(CURDIR)/build/sim_$(VARIANT)
export COCOTB_RESULTS_FILE = $(CURDIR)/results_$(VARIANT).xml
VERILOG_SOURCES = $(CURDIR)/build/tb_top_okd2d.sv
COMPILE_ARGS   += -full64 -sverilog -timescale=1ns/1ps -debug_access+all -f $(CURDIR)/build/$(VARIANT).flist
export COCOTB_RESOLVE_X ?= ZEROS
include $(shell cocotb-config --makefiles)/Makefile.sim
