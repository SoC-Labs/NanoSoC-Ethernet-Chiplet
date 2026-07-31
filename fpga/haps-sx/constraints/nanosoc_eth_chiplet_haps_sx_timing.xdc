################################################################################
# nanosoc_eth_chiplet_haps_sx_timing.xdc — timing constraints (Vivado)
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
# Appended verbatim to the generated pin XDC by scripts/fdc_to_xdc.py, so the
# design gets ONE constraint file with pins first and timing second.
#
# The Synplify-syntax sibling (.fdc) carries the same intent for the
# ProtoSynthesis flow. Keep the two in step if you change either; the pin
# assignments are shared (both derive from the .cob) but timing is duplicated
# because the two tools do not read each other's format.
#
# The MMCM outputs (sys_fclk 25 MHz, idelay_ref 200 MHz, user_ref 100 MHz) are
# derived automatically from the GCLK0 input clock — do not declare them here.
################################################################################

################################################################################
# Primary clocks
################################################################################

# GCLK0 — board PLL, 100 MHz default, LVDS pair into an IBUFDS.
create_clock -period 10.000 -name gclk0 [get_ports gclk0_p]

# RMII reference — 50 MHz sourced BY the LAN8720, asynchronous to GCLK0
# (separate crystal, no phase relationship).
create_clock -period 20.000 -name rmii_ref_clk [get_ports phy_rmii_ref_clk]

################################################################################
# TideLink GPIO-PHY generated clocks
#
# These are NOT optional, and omitting them is not merely a timing-report
# nicety. Ported from the KR260 eth-chiplet target's
# kr260_eth_chiplet_tidelink_timing.xdc, which is the only configuration this
# PHY is proven in.
#
# A build without them (2026-07-24) produced WNS -4.451 ns / TNS -494.7 ns:
# with no create_generated_clock the divided PHY domains get timed against
# their full-rate parent, which for the /16 word clock is a ~60x
# over-constraint. `report_clocks` on that build listed only gclk0,
# rmii_ref_clk and the MMCM outputs — the entire link timing island was
# invisible.
#
# [1] PHY reference /8. u_phy_clk_div is tidelink_phy_clk_div2: a 3-bit
#     free-running counter feeding a BUFG. Source on div_cnt_reg[2]'s CLOCK
#     pin — a SINGLE pin; matching div_cnt_reg[*] would hit three and trip
#     [Constraints 18-359] "can only specify one pin".
#     25 MHz / 8 = 3.125 MHz, matching KR260 exactly.
################################################################################
create_generated_clock -name user_ref_clk_div2 \
    -source [get_pins -hier -filter {NAME =~ "*phy_clk_div*div_cnt_reg[2]/C"}] \
    -divide_by 8 \
    [get_pins -hier -filter {NAME =~ "*phy_clk_div*u_div_bufg*/O"}]

################################################################################
# [2] TX word clock (gpiotx_0 = local hsclk / 16).
#
# KR260 records what happens without this, and it is a FUNCTIONAL failure, not
# a timing one: the /16 TX word clock stays an unconstrained ungated fabric
# net, so the deep Wlink a2l-read FIFO pointers and their WavResetSync never
# see a clean edge -> io_rreset never sync-deasserts -> the a2l read side is
# held in reset -> link_empty is permanently 1 -> the FCSM never drains ->
# NO DATA IS EVER TRANSMITTED. Declaring the clock makes Vivado time the
# domain and route the high-fanout net on a global buffer.
#
# Verified present in this netlist: *gpiotx_0/count_reg[3] resolves to exactly
# one pin for both /C and /Q.
################################################################################
create_generated_clock -name gpiotx0_word_clk \
    -source [get_pins -hier -filter {NAME =~ "*gpiotx_0/count_reg[3]/C"}] \
    -divide_by 16 \
    [get_pins -hier -filter {NAME =~ "*gpiotx_0/count_reg[3]/Q"}]

################################################################################
# Clock groups
#
# Four mutually asynchronous islands. Every crossing between them is 2-flop
# synchronised in RTL, so declaring them unrelated is correct rather than a way
# of hiding a real path:
#
#   * gclk0        — the SoC/AHB domain (sys_fclk and everything derived)
#   * rmii_ref_clk — PHY-sourced 50 MHz, separate crystal, no phase relation
#   * user_ref_clk_div2 — the TideLink PHY island (3.125 MHz)
#   * gpiotx0_word_clk  — the TX word domain, itself /16 of the PHY clock
#
# user_ref_clk_div2 MUST be its own group against gclk0: the crossings are
# async-synchronised, not a balanced integer-ratio crossing, and timing them as
# related produces meaningless requirements.
#
# NOTE: the d2d PHY is in INTERNAL LOOPBACK in this build (PHY_LOOPBACK=1), so
# unlike KR260 there is no pad_clk_rx PORT to constrain — pad_clk_rx is an
# internal net driven from pad_clk_tx. Vivado derives the RX capture clock
# through that path automatically. If PHY_LOOPBACK is ever set to 0 and the
# pads are promoted to real pins, port KR260's [3] source-synchronous block
# (create_clock -period 320 on pad_clk_rx, the pad_clk_tx_fwd generated clock,
# and set_max_delay -datapath_only on pad_rx[*]) as well.
################################################################################
set_clock_groups -asynchronous \
    -group [get_clocks gclk0] \
    -group [get_clocks rmii_ref_clk] \
    -group [get_clocks user_ref_clk_div2] \
    -group [get_clocks gpiotx0_word_clk]

################################################################################
# RMII I/O timing
#
# Loose on purpose: the LAN8720's RMII budget is generous at 50 MHz, and on
# this board the signals additionally pass through an external 1.8 V <-> 3.3 V
# translator (74AVC-class, t_pd ~2-3 ns) that the FPGA cannot see. Widen the
# max input delay if a slower 74LVC-class part is fitted.
################################################################################
set_input_delay  -clock rmii_ref_clk -min  2.0 [get_ports {phy_rmii_rxd[*] phy_rmii_crs_dv}]
set_input_delay  -clock rmii_ref_clk -max 14.0 [get_ports {phy_rmii_rxd[*] phy_rmii_crs_dv}]
set_output_delay -clock rmii_ref_clk -min -1.0 [get_ports {phy_rmii_txd[*] phy_rmii_tx_en}]
set_output_delay -clock rmii_ref_clk -max  5.0 [get_ports {phy_rmii_txd[*] phy_rmii_tx_en}]

################################################################################
# False paths
################################################################################

# Status LEDs — purely visual.
set_false_path -to [get_ports {led[*]}]

# 1 PPS — slow, software-visible PHC output, no setup target.
set_false_path -to [get_ports phc_pps_out]

# MDIO — 2.5 MHz management bus behind a software-rate divider and an external
# translator; not a mission-mode path.
set_false_path -to   [get_ports {phy_mdc phy_mdio phy_mdio_dir}]
set_false_path -from [get_ports {phy_mdio}]

# PHY reset — asynchronous level.
set_false_path -to [get_ports phy_nrst]

# SWD — asynchronous, probe-clocked debug interface. swd_clk lands on a
# non-clock-capable Mictor pin, which is fine at <= 10 MHz, but Vivado will
# treat it as a clock source, so waive dedicated routing.
set_false_path -from [get_ports swd_clk]
set_false_path -from [get_ports swd_dio]
set_false_path -to   [get_ports swd_dio]
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets -of_objects [get_ports swd_clk]]

# Push button — mechanical, synchronised in the board top.
set_false_path -from [get_ports pb1_rst_n]

# HOSTIO4 — fully hardware-handshaked (IOREQ1/IOREQ2 out, IOACK back), and
# IOACK is explicitly asynchronous and resynchronised inside hostio4_target_sync.
# There is no source-synchronous clock on this interface, so there is no
# meaningful setup/hold target to constrain against; the handshake sets the
# rate. Constraining it would only invent a false requirement.
set_false_path -to   [get_ports {hostio4_p1[*]}]
set_false_path -from [get_ports {hostio4_p1[*]}]

################################################################################
# Bitstream / configuration
#
# CFGBVS/CONFIG_VOLTAGE describe the FPGA's configuration bank, which on this
# board is 1.8 V.
################################################################################
set_property CFGBVS GND         [current_design]
set_property CONFIG_VOLTAGE 1.8 [current_design]
