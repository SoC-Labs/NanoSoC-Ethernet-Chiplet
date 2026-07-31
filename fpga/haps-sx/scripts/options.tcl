################################################################################
# options.tcl — ProtoSynthesis device and compile options for the HAPS-SX
#
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access
# license.
#
# Contributors
#
# David Mapstone (d.a.mapstone@soton.ac.uk)
#
# Copyright 2026, SoC Labs (www.soclabs.org)
################################################################################
# Sourced by common.tcl AFTER `database load`. Options apply to the active
# database state, so this must run before `run compile`.
################################################################################

# Single-FPGA synthesis flow (ProtoSynthesis, not ProtoCompiler system-route).
# There is one VU19P on this board, so there is nothing to partition.
option set design_flow synthesis
option set technology  Virtex-UltraScalePlus-FPGAs

################################################################################
# DEVICE — AMD/Xilinx XCVU19P-FSVA3824 on the HAPS-SX 1F module.
#
# Speed grade depends on the fitted SKU (visible in ConfPro-SX board info):
#     20 G    SKU -> -1-e
#     28/32 G SKU -> -2-e      <- the "1F 32G" board in the lab
#
# Verified against Vivado 2024.1: xcvu19p-fsva3824-2-e resolves, and reports
# 4,085,760 LUTs / 8,171,520 FF / 2,160 BRAM36 / 320 URAM / 4 SLRs.
################################################################################
option set part        XCVU19P
option set package     FSVA3824
option set speed_grade -2-e

# If protocompiler_s rejects the split part/package/speed form, fall back to one
# of these single-token equivalents (all name the same silicon):
#   option set part xcvu19p-fsva3824-2-e     ;# full AMD part string
#   option set part VU19P-32G                ;# HAPS-SX composite device token

################################################################################
# Compile behaviour
################################################################################

# Error out on an undefined module rather than silently black-boxing it. A
# black box here means a whole subsystem quietly vanishes from the netlist and
# the board does nothing — with no error until bring-up. Set to 1 only when
# deliberately stubbing something out.
option set auto_infer_blackbox 0

# Keep going past a non-syntax error so one bad file yields a full error list
# instead of one error per iteration.
option set continue_on_error 1

# Prototyping-oriented compile: skips the deep optimisation passes. The design
# is tiny relative to a VU19P (two Cortex-M0+ cores in a 4 M-LUT part), so
# runtime matters far more than QoR here. Drop this line if timing gets tight.
option set synthesis_strategy fast

# Parallelism for the compile phase. Override on the command line if the
# machine is shared.
if { ![info exists ::env(HAPS_SX_JOBS)] } {
    option set max_parallel_jobs 4
} else {
    option set max_parallel_jobs $::env(HAPS_SX_JOBS)
}
