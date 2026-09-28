# rc4 DMA-250 issue timing at port switches. The DMA source set is the multicore tree's
# build_soc/flist/dma250_rendered.flist (the same 60 files, in the same order, as rc4's
# build/chip/flist/soc.flist) plus the four src/rtl wrapper/shim files.
# NOT cocotb/dma250_block: that compiles src/rtl/vendored/dma_250, which differs from the rc4
# copy in 61 files including the BIU.
include ../env.mk
SIM             = vcs
TOPLEVEL_LANG   = verilog
TOPLEVEL        = tb_top
COCOTB_TOPLEVEL = tb_top
MODULE          = test_dma_issue
COCOTB_TEST_MODULES = test_dma_issue
SIM_BUILD       = $(CURDIR)/build/sim
export COCOTB_RESULTS_FILE = $(CURDIR)/build/results.xml
VERILOG_SOURCES = $(NANOSOC_MULTICORE_HOME)/src/rtl/dma250/dma250_ahb5_to_ahbl.v \
                  $(NANOSOC_MULTICORE_HOME)/src/rtl/dma250/dma250_ctx_ahb5_sram.v \
                  $(NANOSOC_MULTICORE_HOME)/src/rtl/dma250/dma250_lpi_onctrl.v \
                  $(NANOSOC_MULTICORE_HOME)/src/rtl/wrappers/dma_250_ahb.v \
                  $(CURDIR)/tb_ahbl_sram_ws.v $(CURDIR)/tb_top.sv
COMPILE_ARGS   += -full64 -sverilog -timescale=1ns/1ps -debug_access+all \
                  -f $(NANOSOC_MULTICORE_HOME)/build_soc/flist/dma250_rendered.flist
export COCOTB_RESOLVE_X ?= ZEROS
include $(shell cocotb-config --makefiles)/Makefile.sim
clean::
	rm -rf build results.xml ucli.key __pycache__
