#-----------------------------------------------------------------------------
# NanoSoC Constraints for Synthesis 
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
#
# Contributors
#
# Daniel Newbrook (d.newbrook@soton.ac.uk)
#
# Copyright (C) 2021-3, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------

#### CLOCK DEFINITION

set EXTCLK "clk";
set SWDCLK "swdclk";
set_units -time ns;

set_units -capacitance pF;
set EXTCLK_PERIOD $::env(CLK_PERIOD);
set SWDCLK_PERIOD [expr 4*$EXTCLK_PERIOD];
set CLK_ERROR 0.35; #Error calculated from worst case characteristics of CDCM61001 low-jitter oscillator chip at 250MHz
set INTER_CLOCK_UNCERTAINTY 0.1

create_clock -name "$EXTCLK" -period "$EXTCLK_PERIOD" -waveform "0 [expr $EXTCLK_PERIOD/2]" [get_ports CLK]
create_clock -name "$SWDCLK" -period "$SWDCLK_PERIOD" -waveform "0 [expr $SWDCLK_PERIOD/2]" [get_ports SWDCK]

# NO create_clock for rtc_clk / user_ref_clk / scan_clk. None of the three is a
# pad on this chip:
#   rtc_clk, user_ref_clk : aliased onto the sys_fclk pad inside the generated
#                           wrapper (ALIASED CLOCKS in the boundary spec), so
#                           they ARE $EXTCLK -- constraining them separately
#                           would invent a clock that does not exist and cut
#                           real same-clock paths.
#   scan_clk              : tied 1'b0; the scan chain is not bonded.
# constraints/nanosoc_eth_chiplet_cdc.sdc still declares all three, because it
# describes the INNER top (nanosoc_eth_chiplet, 111 ports) where they are
# distinct ports. That file is the CDC/CLKDMN input, not this pad ring's
# constraints. Bond the clocks and both files converge.


set_clock_uncertainty $CLK_ERROR [get_clocks $EXTCLK]
set_clock_uncertainty $CLK_ERROR [get_clocks $SWDCLK]

set_clock_uncertainty -setup $INTER_CLOCK_UNCERTAINTY -rise_from [get_clocks $SWDCLK] -rise_to [get_clocks $EXTCLK]
set_clock_uncertainty -setup $INTER_CLOCK_UNCERTAINTY -rise_from [get_clocks $EXTCLK] -rise_to [get_clocks $SWDCLK]

### Multicycle path through asynchronous clock domains
set_multicycle_path 2 -setup -end -from [get_clocks $SWDCLK] -to [get_clocks $EXTCLK]
set_multicycle_path 1 -hold -end -from [get_clocks $SWDCLK] -to [get_clocks $EXTCLK]
set_multicycle_path 2 -setup -end -from [get_clocks $EXTCLK] -to [get_clocks $SWDCLK]
set_multicycle_path 1 -hold -end -from [get_clocks $EXTCLK] -to [get_clocks $SWDCLK]


set_false_path -hold -from [get_clocks $EXTCLK] -to [get_clocks $SWDCLK]

### Multicycle path through pads
set_multicycle_path 2 -from uPAD*/* -to uPAD*/*

### IP Constraints
source ../inputs/qspi_constraints.sdc

source ../inputs/tidelink_constraints.sdc

source ../inputs/ethernet_constraints.sdc

#### DELAY DEFINITION

set_input_delay -clock [get_clocks $EXTCLK] -add_delay 0.1 [get_ports NRST]
set_input_delay -clock [get_clocks $EXTCLK] -add_delay 0.1 [get_ports TEST]
set_input_delay -clock [get_clocks $EXTCLK] -add_delay 0.1 [get_ports HOSTIO4_P1]
set_input_delay -clock [get_clocks $SWDCLK] -add_delay 0.1 [get_ports SWDIO]

#### ASYNCHRONOUS CLOCK GROUPS ##############################################
# Must come AFTER the three sources above, so every generated clock they create
# already exists.
#
# This carries over the intent of constraints/nanosoc_eth_chiplet_cdc.sdc — the
# chiplet-level CDC/CLKDMN input — translated from the inner wrapper's port
# names to this pad ring's. Without it the tool sees no relationship between the
# system clock and the D2D receive clock and times straight through the link
# synchronisers, which makes every number it reports meaningless.
#
# Group membership mirrors that file, collapsed for this pad ring's clocks.
# rtc_clk / user_ref_clk / scan_clk are absent here (aliased onto $EXTCLK or
# tied), so the CDC SDC's separate groups for them fold into the $EXTCLK group:
#   sys_fclk + scan_clk + rtc_clk -> $EXTCLK (+ the QSPI clocks generated off it)
#   user_ref_clk + pad_clk_tx     -> D2D_TX_CLK_0 alone; user_ref_clk IS $EXTCLK
#                                    now, so the TX clock keeps its own group
#                                    and the $EXTCLK <-> D2D_TX cut is REAL.
#   pad_clk_rx                    -> D2D_RX_CLK_0
#   rmii_ref_clk                  -> stands alone, dragging its two divide-by-2
#                                    MII clocks with it.
#
# NOTE the consequence of aliasing user_ref_clk onto $EXTCLK: the Wlink PLL
# reference and the system clock are now the SAME net, so what used to be a
# genuine asynchronous crossing inside the Wlink controller is synchronous in
# this build. The synchronisers remain (harmless). Bond user_ref_clk separately
# and this group must split again.
#
# [OWNER] For SIGNOFF, narrow the D2D_RX_CLK_0 cut rather than leaving it a
# blanket group: TideLink's own SDC constrains that crossing instead of grouping
# it. See the note in constraints/nanosoc_eth_chiplet_cdc.sdc. This is the
# bring-up cut, and it is deliberately conservative.
set_clock_groups -asynchronous -name eth_chiplet_cdc \
    -group [get_clocks [list $EXTCLK QSPI_SCLK QSPI_SCLK_o]] \
    -group [get_clocks {D2D_TX_CLK_0}] \
    -group [get_clocks {D2D_RX_CLK_0}] \
    -group [get_clocks {rmii_ref_clk mii_rx_clk mii_tx_clk}] \
    -group [get_clocks [list $SWDCLK]]

set_max_capacitance 3 [all_outputs]
set_max_fanout 10 [all_inputs]

