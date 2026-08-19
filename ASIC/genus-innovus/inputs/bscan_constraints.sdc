#-----------------------------------------------------------------------------
# bscan_constraints.sdc — IEEE 1149.1 boundary-scan register
#
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access
# license.
#
# Contributors
#
# David Mapstone (d.a.mapstone@soton.ac.uk)
#
# Copyright 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
#
# THE ONE THING THIS FILE EXISTS TO PREVENT
#
# `set_case_analysis 0 [get_ports SE]` used to sit in constraints.sdc. SE is now
# the boundary-scan enable: it drives `trst_n` on the TAP and the select on every
# TAP pin mux. Constant-propagating SE=0 puts the TAP in permanent reset, holds
# `mode` and `highz` low for all time, and makes the entire boundary register
# unobservable and unreachable — at which point Genus is not merely ALLOWED to
# delete all 76 cells, the TAP and the instruction register, it is CORRECT to.
# The netlist would come out with no boundary scan and no error anywhere.
#
# That constraint has been removed. This file replaces the timing it used to
# provide, without the constant. Do not put it back.
#
# WHY SE AND NOT TEST. TEST is left case-analysed to 0 and is untouched by the
# boundary-scan work. It drives CGBYPASS/RSTBYPASS on the clock and reset
# controllers, and coupling test access to it would change functional reset
# behaviour in mission mode. SE was chosen precisely because it was bonded,
# dangling (`UNCONNECTED2828` in the shipping netlist) and therefore free.
#-----------------------------------------------------------------------------

# ── 1. SE is a static mode pin, but it must remain a real net ────────────────
#
# Give it an input delay so it is timed rather than unconstrained, and a
# generous transition — this is a strapped pin driven by a board-level source or
# a bond option, not a signal with a budget.
set_input_delay  -clock clk -max 1.0 [get_ports SE]
set_input_delay  -clock clk -min 0.0 [get_ports SE]
set_input_transition -max 2.00 [get_ports SE]

# ── 2. The TAP's asynchronous reset arc ──────────────────────────────────────
#
# SE reaches the TAP state flops and the instruction register as `trst_n`, an
# asynchronous active-low reset. Its DE-assertion is a recovery/removal arc with
# no defined relationship to TCK, so the timer would otherwise report it as
# unconstrained-or-failing depending on the corner.
#
# SE is static for an entire test session — it is strapped before TCK is applied
# and does not move again — so the recovery/removal check has no physical
# meaning here. This is the standard treatment, stated rather than left implicit.
#
# IF SE EVER BECOMES DYNAMIC, delete this and put a two-flop de-assertion
# synchroniser on trst_n instead. A false path on a reset that really can move
# asynchronously is how metastability reaches a state machine.
set_false_path -from [get_ports SE]

# ── 3. TCK ───────────────────────────────────────────────────────────────────
#
# TCK is not a new pin. It is the SWDCK pad, re-purposed while SE is high, and
# `create_clock -name swdclk` in constraints.sdc already covers that port at 4x
# the core period. The boundary-scan flops are therefore already clocked by a
# defined clock and NO second create_clock is added here — two create_clocks on
# one port is how a clock silently stops being propagated.
#
# Timing the chain at the SWD period is the conservative direction: the tester
# will drive TCK slower than SWD, never faster. If a dedicated, faster TCK is
# ever wanted, it needs its own port, not an override here.
#
# The register contains negedge-triggered flops by design (the 43 update stages,
# the TDO output stage and the held instruction — see INTERFACE_CONTRACT.md §2).
# STA handles both edges of one clock without help; this note exists so nobody
# "fixes" the negedge population by adding a shifted generated clock.

# ── 4. The boundary register is not on any functional path ───────────────────
#
# Shifting happens only while SE is high and the chip is on a tester. The shift
# path (cell to cell around the ring) must not be timed against the functional
# clock, and the capture path is timed by TCK.
#
# Scoped to the register's own instance so this cannot leak into functional
# logic if the hierarchy is ever flattened differently.
if {[llength [get_cells -quiet u_nanosoc_eth_chiplet_bscan]]} {
    set_multicycle_path -setup 2 -from [get_pins -quiet u_nanosoc_eth_chiplet_bscan/*] \
                                 -to   [get_pins -quiet u_nanosoc_eth_chiplet_bscan/*]
    set_multicycle_path -hold  1 -from [get_pins -quiet u_nanosoc_eth_chiplet_bscan/*] \
                                 -to   [get_pins -quiet u_nanosoc_eth_chiplet_bscan/*]
} else {
    puts "WARNING: \[bscan\] u_nanosoc_eth_chiplet_bscan not found — boundary-scan\
          constraints did NOT apply. If the pad ring is spliced, something deleted\
          the register."
}
