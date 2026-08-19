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

# ── 4. THE REGISTER MUST EXIST. This is an assertion, not a constraint. ──────
#
# Constraints are read AFTER elaborate, so by this point
# `u_nanosoc_eth_chiplet_bscan` either resolves or the boundary-scan register is
# NOT IN THE DESIGN. There is no third reading. That is precisely the failure
# removing `set_case_analysis 0 [get_ports SE]` exists to prevent: with SE held
# constant the register is unreachable and unobservable, Genus deletes all 76
# cells as correct constant propagation, and synthesis reports success.
#
# An earlier version of this block printed a WARNING here. A warning in a
# 3000-line Genus log that already carries 163 of them is not a response to
# silently shipping a chip with no boundary scan. It is an error.
if {![llength [get_cells -quiet u_nanosoc_eth_chiplet_bscan]]} {
    error "bscan: u_nanosoc_eth_chiplet_bscan does not exist in the elaborated\
           design. The boundary-scan register has been optimised away or was\
           never read. Check that SE has no set_case_analysis and that\
           src/rtl/bscan/*.sv are in the flist."
}

# NO MULTICYCLE ON THE SHIFT CHAIN, deliberately.
#
# An earlier version carried:
#     set_multicycle_path -setup 2 -from [get_pins u_nanosoc_eth_chiplet_bscan/*] ...
# It was removed after its first run through Genus, for two reasons.
#
# It did not do what it looked like. `get_pins <inst>/*` expands to the
# instance's hierarchical BOUNDARY pins, and most of those are not valid timing
# start/endpoints -- Genus accepted the command and then reported TIM-316/317
# ("provided from_point is 'hpin:.../u_nanosoc_eth_chiplet_bscan/tck'"), applying
# the exception to some points and silently skipping others. This is the same
# root as the C2 `set_max_delay -from [get_cells .../fifo/mem]` block that cost
# this project 21 hours: a hierarchical object expanded to pins that cannot carry
# an exception. C2's form FAILED outright and left a row in the read_sdc
# statistics table. This form SUCCEEDS and leaves only a warning -- the more
# dangerous of the two, because nothing counts it.
#
# And it was never needed. TCK is the SWDCK pad and `swdclk` is already 4x the
# core period, so a single-cycle check on the shift chain has ~40 ns to make. The
# measured result on the first probe: r2r_swdclk slack +17838 ps with ZERO
# failing endpoints, i.e. 17.8 ns of margin without any exception at all.
#
# If a real exception is ever needed here, the valid forms are
# `-from [get_clocks swdclk]` or the leaf flop clk pins -- never `<inst>/*`.
