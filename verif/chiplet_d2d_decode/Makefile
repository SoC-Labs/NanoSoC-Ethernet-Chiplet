#-----------------------------------------------------------------------------
# TX-aperture wedge-gate check for chiplet_d2d_decode.
# Copyright 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# TideLink's integration guide marks ahb_tx_* a WEDGE HAZARD: a write with the
# link down never completes and hangs the bus. The gate lives in the decoder
# because only it owns the sub-decode and the default responder.
#
# This proves the gate fires, that it does NOT close any other region (you must
# still be able to reach the APB banks to bring the link up), and that the fault
# is a proper two-cycle AHB ERROR rather than a silent OKAY.
#
#   source ../../set_env.sh && make
#-----------------------------------------------------------------------------
VCS ?= vcs
RTL := ../../src/rtl/chiplet_d2d_decode.sv

.PHONY: all clean
all:
	$(VCS) -full64 -sverilog -timescale=1ns/1ps -q $(RTL) tb_tx_gate.sv -top tb -o simv_tx_gate
	./simv_tx_gate

clean:
	rm -rf simv_tx_gate simv_tx_gate.daidir csrc ucli.key *.log
