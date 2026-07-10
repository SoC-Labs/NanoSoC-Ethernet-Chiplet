#-----------------------------------------------------------------------------
# nanosoc_eth_chiplet_cdc.sdc — clock + async-group constraints for the
# integrated ethernet chiplet. Feeds CDC sign-off (Cadence HAL / SpyGlass) and is
# the starting point for the ASIC STA SDC.
#
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
# Copyright 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# STATUS: STARTING POINT, not sign-off. The clock DOMAINS and the async cuts at
# the integration boundary (the load-bearing part for CDC) are declared here. The
# items marked [OWNER] need the clock-tree owner: exact generated-clock ratios,
# the SoC-internal MAC/PTP clock structure, and the real I/O delays. Composed from:
#   - nanosoc-multicore-system/build_soc/constraints/nanosoc_multicore_soc_constraints.sdc
#   - tidelink/syn/asic/fusion-compiler/inputs/constraints.sdc  (the refined D2D cut)
# Port names are the nanosoc_eth_chiplet top ports (see PIN_MAP.md).
#-----------------------------------------------------------------------------

set_units -time ns
set_units -capacitance pF

#### PRIMARY CLOCKS (chiplet input ports) ####################################
# sys_fclk: the SoC free-running clock. The SoC SDC pins this at 100 MHz (10 ns).
# sys_hclk (the AHB fabric clock, and the whole wrapper's clock: chiplet_d2d_decode,
# both APB bridges, tidechart_shim, tidelink.hclk) is GENERATED from sys_fclk inside
# the SoC's PRMU — see [OWNER] below.
create_clock -name sys_fclk -period 10.000 -waveform {0 5.000} [get_ports sys_fclk]
set_clock_uncertainty 0.35 [get_clocks sys_fclk]

# user_ref_clk: the Wlink PLL reference. ASYNCHRONOUS to sys_hclk. [OWNER] period
# is the D2D unit interval; TideLink's SDC parameterises it as T_UI_NS. Placeholder
# 8 ns (125 MHz) matches the sim ref; confirm against the PHY.
create_clock -name user_ref_clk -period 8.000 -waveform {0 4.000} [get_ports user_ref_clk]
set_clock_uncertainty 0.35 [get_clocks user_ref_clk]

# pad_clk_rx: the FAR die's forwarded clock, recovered at the RX pads. A real
# primary clock, ASYNCHRONOUS to everything on this die (RESET_ORDERING.md 2).
# Same nominal UI as user_ref_clk. [OWNER] confirm period.
create_clock -name pad_clk_rx -period 8.000 -waveform {0 4.000} [get_ports pad_clk_rx]
set_clock_uncertainty 0.35 [get_clocks pad_clk_rx]

# rtc_clk: RTC / PTP reference. Asynchronous to sys_hclk. [OWNER] period.
create_clock -name rtc_clk -period 30.518 -waveform {0 15.259} [get_ports rtc_clk]

# rmii_ref_clk: 50 MHz RMII reference. Asynchronous to sys_hclk. [OWNER] confirm.
create_clock -name rmii_ref_clk -period 20.000 -waveform {0 10.000} [get_ports rmii_ref_clk]

# swd_clk: CoreSight SWJ-DP clock. Asynchronous to sys_hclk (the SoC SDC treats
# swdclk<->sys_fclk as an async handoff).
create_clock -name swd_clk -period 40.000 -waveform {0 20.000} [get_ports swd_clk]
set_clock_uncertainty 0.35 [get_clocks swd_clk]

# scan_clk: DFT shift clock. Test-mode only; grouped async for functional CDC.
create_clock -name scan_clk -period 10.000 -waveform {0 5.000} [get_ports scan_clk]

# idelay_ref_clk: FPGA IDELAYCTRL reference only (tied off on ASIC, USE_IDELAY=0).
# No clock on ASIC — leave undeclared for the ASIC flow.

#### GENERATED CLOCKS ########################################################
# pad_clk_tx: the forwarded TX clock, GENERATED from user_ref_clk (source-sync TX).
# TideLink's SDC divides user_ref_clk by 1 into pad_clk_tx_fwd. Declared here so the
# async groups below can reference it. [OWNER] confirm the divide + the launch pin.
create_generated_clock -name pad_clk_tx -source [get_ports user_ref_clk] -divide_by 1 \
    [get_ports pad_clk_tx]

# [OWNER] sys_hclk is generated from sys_fclk inside the SoC PRMU. Declare it as a
# generated clock on the internal net once the netlist name + divide ratio are
# known, e.g.:
#   create_generated_clock -name sys_hclk -source [get_ports sys_fclk] \
#       -divide_by <N> [get_pins <prmu>/<hclk_net>]
# Until then STA/CDC treat the fabric as sys_fclk-domain, which is correct for the
# DOMAIN grouping below (sys_hclk is synchronous to sys_fclk).
#
# [OWNER] the ethernet MAC has its own RX/TX/host/PTP clocks and the HA1588 PTP
# timestamp unit its own — these are the component-internal multi-clock instances
# HAL's MCKDMN already flags (CDC_FINDINGS.md). They are handled inside the eth
# subsystem; add their generated-clock definitions from the eth-subsystem SDC.

#### ASYNCHRONOUS CLOCK GROUPS — the D2D CDC boundary ########################
# This is the load-bearing declaration for CDC. Each group is its own domain; STA
# ignores paths BETWEEN groups (they must cross through a synchroniser). The
# genuine crossings the integration owns are sys_hclk <-> {user_ref_clk, pad_clk_rx}
# — the SoC-core <-> D2D-link boundary. TideLink's own SDC narrows the pad_clk_rx
# <-> hclk cut rather than blanket-grouping it; carry that intent into signoff.
set_clock_groups -asynchronous -name eth_chiplet_cdc \
    -group {sys_fclk scan_clk} \
    -group {user_ref_clk pad_clk_tx} \
    -group {pad_clk_rx} \
    -group {rtc_clk} \
    -group {rmii_ref_clk} \
    -group {swd_clk}

#### I/O DELAYS #############################################################
# [OWNER] real source-synchronous I/O delays for the D2D ribbons are the make-or-
# break for a working link — copy TideLink's symmetric set_input_delay on pad_rx[*]
# vs pad_clk_rx and set_output_delay on pad_tx[*] vs pad_clk_tx, and the SoC SDC's
# input delays on the functional pads. Not reproduced here to avoid stale values.
#-----------------------------------------------------------------------------
