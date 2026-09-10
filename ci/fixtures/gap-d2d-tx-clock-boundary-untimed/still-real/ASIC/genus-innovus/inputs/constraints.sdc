# FIXTURE — constraints.sdc as it is at HEAD: the D2D transmit word clock is
# still asserted -asynchronous against the group holding the clock it is
# GENERATED FROM. The d2d-tx-clock-boundary-untimed gap's refuted_by must exit 1
# over this file (gap still real).
#
# An EXCERPT of the real ASIC/genus-innovus/inputs/constraints.sdc, cut to the
# clock-group block the probe reads. Nothing else in the real file bears on it.
#
# THREE DECOYS, all deliberate, all near-misses of the fixed string
# '-group [get_clocks $_tx_grp]':
#   * -group [get_clocks $_rx_grp]  — the RECEIVE group, which is genuinely
#     asynchronous (create_clock on a real pad) and must stay grouped out. A
#     probe that matched "-group [get_clocks" would call this gap refuted the
#     day the TX group was folded in and the RX group was not, i.e. never.
#   * $_tx_grp appears on its own set/llength/unset lines. A probe that grepped
#     for the VARIABLE rather than the -group CLAUSE would still match after
#     Option A folded the clock into _sys_grp and left the variable in place.
#   * a lone `-group [get_clocks {rmii_ref_clk mii_rx_clk mii_tx_clk}]`, a
#     fourth group with no variable at all.

set EXTCLK  clk
set SWDCLK  SWCLKTCK

set _rx_grp {D2D_RX_CLK_0}
set _tx_grp {D2D_TX_WORD_CLK_0}
foreach n {0 1 2 3 4 5 6 7} {
    lappend _rx_grp "D2D_RX_WORD_CLK_$n"
    lappend _rx_grp "D2D_RX_WORDN_CLK_$n"
}
set _sys_grp [list $EXTCLK QSPI_SCLK QSPI_SCLK_o D2D_TX_CLK_0]

if {[llength $_rx_grp] != 17 || [llength $_tx_grp] != 1 || [llength $_sys_grp] != 4} {
    error "constraints.sdc: D2D clock groups built wrong"
}

set_clock_groups -asynchronous -name eth_chiplet_cdc \
    -group [get_clocks $_sys_grp] \
    -group [get_clocks $_tx_grp] \
    -group [get_clocks $_rx_grp] \
    -group [get_clocks {rmii_ref_clk mii_rx_clk mii_tx_clk}] \
    -group [get_clocks [list $SWDCLK]]
unset _rx_grp _tx_grp _sys_grp
