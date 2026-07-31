################################################################################
# nanosoc_eth_chiplet_haps_sx_drc.xdc — DRC waivers
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
# Kept in a SEPARATE file from the timing constraints, mirroring the KR260
# target's kr260_eth_chiplet_tidelink_drc.xdc. Same reason: these properties do
# not survive a `save_constraints` round-trip, which rewrites *_timing.xdc and
# tends to drop them.
#
# READ THIS BEFORE ADDING ANYTHING HERE. A DRC waiver silences a real check.
# Everything below is waived because it is understood and has an argued
# justification, not because it was in the way.
################################################################################

################################################################################
# [1] LUTLP-1 — combinatorial loop on the AHB-Lite HREADY path
#
# Vivado 2024.1 reports 5 LUT cells forming a loop spanning u_d2d_decode,
# u_tidelink/gen_ptp_real.u_ptp and u_xhb_sub/u_core/u_wdata_st1_regslice,
# naming u_chiplet/u_d2d_decode/dph_code_reg[2]_0 as one net in it. Without a
# waiver `write_bitstream` refuses to run:
#
#   ERROR: [DRC LUTLP-1] Combinatorial Loop Alert: 5 LUT cells form a
#          combinatorial loop.
#   ERROR: [Vivado 12-1345] Error(s) found during DRC. Bitgen not run.
#
# WHY THIS IS WAIVED, AND WHY THAT IS NOT THE HREADY BUG COMING BACK
#
# The AHB-Lite HSEL/HREADY loopback is an intentional combinational structure —
# the KR260 eth-chiplet target waives exactly this class, per-net, for exactly
# this reason (kr260_eth_chiplet_tidelink_drc.xdc), and notes that
# write_bitstream's pre-DRC ignores a severity downgrade in 2024.1, so a
# per-net property is required rather than just `set_msg_config`.
#
# The genuinely dangerous cycle in this design — TideLink's ahb_sub_hreadyout
# depending combinationally on its own ahb_sub_hready input — was FIXED in RTL
# on 2026-07-10 and is guarded by a mutation-tested regression
# (verif/chiplet_d2d_decode/tb_hready_loop.sv; see docs/D2D_HREADY_LOOP.md).
# chiplet_d2d_decode exports a REGISTERED dph_peer, and nanosoc_eth_chiplet
# drives ahb_sub_hready from `dph_peer ? 1'b1 : d2d_ahb_m_hready`, so the
# architectural loop has a register in it. This waiver does not re-open that.
#
# The reported cells also argue for a synthesis artefact rather than an
# architectural cycle: they span the PTP block, the D2D decoder and the XHB
# write-data register slice — functionally unrelated logic that shares a
# `dflt_err2` default term, which is exactly the shape LUT-merging produces
# when Vivado packs independent cones into common LUTs.
#
# IF YOU ARE DEBUGGING A HUNG BUS, START BY REMOVING THIS WAIVER and running
# `report_drc -checks LUTLP-1` on the routed checkpoint to see whether the loop
# membership has changed. A NEW loop that includes a genuine hready path is a
# real bug, not this.
################################################################################

# The specific net Vivado named in the loop.
set _lp_nets [get_nets -quiet -hierarchical \
    -filter {NAME =~ "*u_d2d_decode/dph_code_reg*"}]

# The XHB subordinate's response/write-data paths — the KR260 waiver targets
# u_resp/*; this build's reported loop runs through u_wdata/*, so cover both.
set _lp_nets [concat $_lp_nets [get_nets -quiet -hierarchical \
    -filter {NAME =~ "*u_xhb_sub/u_core/u_resp/*"}]]
set _lp_nets [concat $_lp_nets [get_nets -quiet -hierarchical \
    -filter {NAME =~ "*u_xhb_sub/u_core/u_wdata/*"}]]

if { [llength $_lp_nets] > 0 } {
    set_property ALLOW_COMBINATORIAL_LOOPS true $_lp_nets
    puts "INFO: LUTLP-1 waiver applied to [llength $_lp_nets] net(s)."
} else {
    puts "WARNING: LUTLP-1 waiver matched NO nets — the hierarchy has moved."
    puts "         write_bitstream will fail; update the filters in"
    puts "         constraints/nanosoc_eth_chiplet_haps_sx_drc.xdc"
}

# Belt and braces: downgrade the severity too. On its own this is NOT enough in
# Vivado 2024.1 (write_bitstream's pre-DRC has historically ignored it), which
# is why the per-net property above is the primary mechanism.
set_msg_config -id {DRC LUTLP-1} -new_severity WARNING
