# FIXTURE — the day the gap closes, by Option A of
# docs/asic/C2_TRANSMIT_GROUP_OPTIONS.md: the D2D transmit word clock is folded
# into the system group, so the clk <-> TX boundary is TIMED and no longer
# false-pathed by a declaration that is not true of the netlist. The
# d2d-tx-clock-boundary-untimed gap's refuted_by must exit 0 over this file,
# which makes `signoff.py lint` go red and forces the declaration to be
# rewritten or deleted.
#
# WHY THIS SHAPE AND NOT "delete the line". Option A does not remove a group, it
# MOVES A CLOCK. D2D_TX_WORD_CLK_0 joins _sys_grp beside the clock it is
# generated from; the exceptions the first timed run names would then be written
# per path, which is why the placeholder set_multicycle_path block is here. The
# RX group is untouched, because that boundary IS asynchronous.
#
# THE DECOYS SURVIVE THE CHANGE, ON PURPOSE. `$_tx_grp` is still set, still
# length-checked and still unset at the end, and the file still carries four
# `-group [get_clocks ...]` clauses. Only the ONE fixed string the probe names
# is gone. A probe keyed on the variable, on the word "asynchronous", or on the
# group count would report this gap still real over a file in which it has
# closed — which is the failure mode `sta-signoff` was deleted for.

set EXTCLK  clk
set SWDCLK  SWCLKTCK

set _rx_grp {D2D_RX_CLK_0}
set _tx_grp {D2D_TX_WORD_CLK_0}
foreach n {0 1 2 3 4 5 6 7} {
    lappend _rx_grp "D2D_RX_WORD_CLK_$n"
    lappend _rx_grp "D2D_RX_WORDN_CLK_$n"
}
# OPTION A: the transmit word clock joins the group holding its master.
set _sys_grp [list $EXTCLK QSPI_SCLK QSPI_SCLK_o D2D_TX_CLK_0 $_tx_grp]

if {[llength $_rx_grp] != 17 || [llength $_tx_grp] != 1 || [llength $_sys_grp] != 5} {
    error "constraints.sdc: D2D clock groups built wrong"
}

set_clock_groups -asynchronous -name eth_chiplet_cdc \
    -group [get_clocks $_sys_grp] \
    -group [get_clocks $_rx_grp] \
    -group [get_clocks {rmii_ref_clk mii_rx_clk mii_tx_clk}] \
    -group [get_clocks [list $SWDCLK]]
unset _rx_grp _tx_grp _sys_grp

# The ~1184 endpoints the group cut used to delete are now analysed. Per-path
# exceptions for the synchronised crossings go here, named by the first timed
# run, not blanket-cut.
set_multicycle_path -setup 2 -from [get_clocks clk] -to [get_clocks D2D_TX_WORD_CLK_0]
set_multicycle_path -hold  1 -from [get_clocks clk] -to [get_clocks D2D_TX_WORD_CLK_0]
