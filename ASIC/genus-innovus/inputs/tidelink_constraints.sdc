# Chiplet Interface
#
# THE D2D LINK RATE IS NOT OUR CLOCK — IT IS THE PEER DIE'S.
# TL_CLK_RX is the OTHER chiplet's forwarded transmit clock arriving on a pad:
#   pad_clk_tx <- gpio_io_pad_clk_tx   (WlinkGPIOPHY_v2.v:334)
#                <- gpiotx_0_io_pad_clk (WavD2DGpio_v2.v:1966)
# and axi_chiplet_controller.sv:805 states the relationship outright — this die's
# forwarded pad_clk_tx "IS the peer's pad_clk_rx". So writing $EXTCLK_PERIOD here
# is an assertion about a DIFFERENT CHIP, and until 2026-08-10 it was an
# inheritance from our own build variable with nothing recording that.
#
# IT IS CORRECT, AND HERE IS WHY (confirmed 2026-08-10):
#   1. Both chiplets — this one and the compute chiplet — run from the SAME
#      clock source.
#   2. Both instantiate the SAME TideLink PHY configuration, so whatever ratio
#      the PHY applies between SoC clock and pad clock applies IDENTICALLY on
#      both sides. Our own TX is create_generated_clock ... -divide_by 1 on
#      TL_CLK_TX (below), so the relationship is symmetric by construction —
#      not a guess that the peer happened to choose 100 MHz.
#
# MESOCHRONOUS, NOT SYNCHRONOUS. A shared source fixes the FREQUENCY and says
# nothing about PHASE: the two dies have independent clock trees and there is
# package flight time between them, so TL_CLK_RX arrives at an arbitrary phase.
# That is why u_deskew and the calibrator exist, and why the D2D clocks stay in
# a -asynchronous group in constraints.sdc rather than being timed against clk.
#
# WHY THIS MATTERS MORE THAN IT LOOKS. Every one of the 24 D2D word clocks below
# is -divide_by 16 off this period, so this single number is the timing
# reference for ~16,600 flops — 27% of the design — that were untimed until
# 2026-08-09. If the two dies ever diverge in rate or PHY config, STA here still
# reports clean and the part fails on silicon.
#
# KNOWN RISK, deliberately not closed for this tapeout: there is no D2D link
# budget. $CLK_ERROR below is the SYSTEM OSCILLATOR jitter standing in for
# recovered-clock uncertainty. A shared source means common-mode jitter largely
# cancels, so the real terms are the two dies' independent clock-tree jitter,
# pad/package flight variation and the deskew FIFO's own tolerance.
set D2D_LINK_PERIOD $EXTCLK_PERIOD
create_clock -name "D2D_RX_CLK_0" -period "$D2D_LINK_PERIOD"  -waveform "0 [expr $D2D_LINK_PERIOD/2]" [get_ports TL_CLK_RX]

set_input_delay 1 -clock [get_clocks "D2D_RX_CLK_0"] [get_ports {TL_RX[*]}]

create_generated_clock -name "D2D_TX_CLK_0" -source [get_pins u_nanosoc_eth_chiplet_chip/u_soc/u_tidelink/u_chiplet_controller/u_wlink/pad_clk_tx] -divide_by 1 [get_ports TL_CLK_TX]

set_output_delay 0.8 -clock [get_clocks "D2D_TX_CLK_0"] [get_ports {TL_TX[*]}]

# CLOCK UNCERTAINTY — was ABSENT for both D2D clocks, so they were timed with
# ZERO margin on setup and hold. Verified on the 2026-08-06 run: paths in these
# domains carry no `Uncertainty` line at all.
#
# D2D_RX_CLK_0 is the worst case in the design to leave unmargined: it is an
# EXTERNAL, OFF-DIE clock arriving over the die-to-die link, driving 528 sinks,
# and its achieved skew (0.116ns) already exceeds its CTS target (0.097ns).
#
# THE SETUP VALUES BELOW ARE PLACEHOLDERS. $CLK_ERROR is the CDCM61001
# oscillator's jitter figure for the SYSTEM clock (see constraints.sdc:21); it
# is not a characterisation of the D2D link, which has its own source jitter
# plus package and channel skew. Someone with the link budget should replace
# these with real numbers. Using the system figure is strictly more
# conservative than the zero that was here, which is the only claim being made.
# $CLK_HOLD_ERROR is on-die skew margin and applies uniformly.
set_clock_uncertainty -setup $CLK_ERROR      [get_clocks D2D_RX_CLK_0]
set_clock_uncertainty -hold  $CLK_HOLD_ERROR [get_clocks D2D_RX_CLK_0]
set_clock_uncertainty -setup $CLK_ERROR      [get_clocks D2D_TX_CLK_0]
set_clock_uncertainty -hold  $CLK_HOLD_ERROR [get_clocks D2D_TX_CLK_0]

# ===========================================================================
# RECOVERED D2D RX WORD CLOCK (/16) — THE 16,653 UNCLOCKED FLOPS
# ===========================================================================
# Added 2026-08-08. Before this block the recovered RX WORD clock was never
# declared, so check_timing_intent reported 16,653 sequential clock pins
# "without clock waveform" (reports/eval/syn_timing_intent.pre.rep:17779) — the
# ENTIRE D2D RX word domain, timed against nothing and un-balanceable by CTS.
# That is the marginal-die_a RX-eye reliability gap: a recovered-clock domain
# with no clock tree.
#
# WHAT THE CLOCK IS, FROM THE RTL (verified, not assumed):
#   Each per-lane WavD2DGpioRx derives a /16 word clock and drives it out on its
#   io_link_clk port. The generator is a free-running 4-bit counter `count`
#   (tidelink/src/rtl/local_overrides/WavD2DGpioRx_v2.v:400, +1 every capture
#   clock, init 0xF); io_link_clk = ~count[3] (line 595 via io_link_clk_mux).
#     * NOTE it is ~count[3], NOT ~adj_count[3] — the SoC Labs glitch fix of
#       2026-06-09 (same file, lines 572-595) moved the divide OFF the
#       phase-adjusted count and ONTO the free-running one, so the word clock is
#       phase-INDEPENDENT of data alignment. Same /16 ratio; all 8 lanes share
#       one capture clock and one POR, so the 8 word clocks are phase-aligned.
#   count itself IS already clocked (its clk pin is NOT in the pre-report): the
#   capture clock w_cnt_clk = io_pad_clk = io_pad_clk_rx = TL_CLK_RX at 1:1 in
#   functional mode (WavD2DGpioRx_v2.v:665; the pad_clk scan mux passes the
#   functional leg — proven by count_reg being clocked). So the divider path
#   TL_CLK_RX -> count -> io_link_clk is OPEN and -source TL_CLK_RX resolves.
#
# HIERARCHY (verified against reports/eval/syn_hierarchy.rep and the RTL):
#   u_wlink (Wlink) -> phy (WlinkGPIOPHY, Wlink.v:1389)
#                   -> gpio (WavD2DGpio,  WlinkGPIOPHY*.v:117/248)
#                   -> gpiorx_<0..7> (WavD2DGpioRx) . io_link_clk
#   gpiorx_0/io_link_clk also leaves gpio as io_link_rx_rx_link_clk
#   (WavD2DGpio_v2.v:1965) and is the deskew read/out_clk + the domain the whole
#   framer / axi2wl / gb2wl / tl2wl / sp2wl / llrx / calibrator / lane_checker
#   run in (the bulk of the 16,653). lanes 1-7 clock the per-lane deskew write
#   side (WavD2DGpio_v2.v:899-902 lane_clk) + their own leaf link_data_reg.
#   All 8 pins are defined so every flop in the domain gets a waveform + CTS.
#
# Defining the generated clock AT the io_link_clk pin (after the mux) asserts
# the /16 waveform forward regardless of the scan-mux constant-propagation that
# labelled these pins "Case constant(0)"; -source TL_CLK_RX / -divide_by 16
# gives period 16*EXTCLK_PERIOD with a 50% duty cycle (~count[3] = 8 hi / 8 lo).
set GPIO u_nanosoc_eth_chiplet_chip/u_soc/u_tidelink/u_chiplet_controller/u_wlink/phy/gpio
set WL   u_nanosoc_eth_chiplet_chip/u_soc/u_tidelink/u_chiplet_controller/u_wlink
set _rx_bound 0
foreach n {0 1 2 3 4 5 6 7} {
    set _pin [get_pins -quiet $GPIO/gpiorx_$n/io_link_clk]
    # `error`, NOT `continue`. A skipped lane leaves ~1.8k flops with no waveform
    # and no clock tree while the run completes and reports success - which is
    # exactly how this hole survived the whole project. Measured 2026-08-09: all
    # 8 pins resolve at read time (post-elaborate, pre-map), so a miss here means
    # the hierarchy moved and the constraint must not be silently dropped.
    if {[sizeof_collection $_pin] == 0} {
        error "tidelink_constraints.sdc: D2D RX word-clock anchor\
               $GPIO/gpiorx_$n/io_link_clk matched NOTHING. The recovered RX word\
               domain (~14.7k flops) would be left untimed and CTS would build no\
               tree for it. Refusing to continue."
    }
    create_generated_clock -name "D2D_RX_WORD_CLK_$n" \
        -source [get_ports TL_CLK_RX] -divide_by 16 $_pin
    # Mirror D2D_RX_CLK_0: never time these newly-clocked flops at ZERO margin.
    # PLACEHOLDER values, same caveat as the D2D_RX_CLK_0 block above — $CLK_ERROR
    # is the system oscillator jitter, not the D2D link budget. Replace with the
    # real recovered-clock jitter when the link budget exists.
    set_clock_uncertainty -setup $CLK_ERROR      [get_clocks "D2D_RX_WORD_CLK_$n"]
    set_clock_uncertainty -hold  $CLK_HOLD_ERROR [get_clocks "D2D_RX_WORD_CLK_$n"]
    incr _rx_bound
}
if {$_rx_bound != 8} {
    error "tidelink_constraints.sdc: bound $_rx_bound/8 RX word clocks"
}

# ===========================================================================
# RECOVERED D2D RX WORD CLOCK, NEGATIVE PHASE (/16) — THE RESIDUAL 128
# ===========================================================================
# The block above took untimed sequential clock pins 16,653 -> 128
# (runs/20260809T133739Z_wordclk-gateA). The 128 that remain are NOT the divider
# counters — those are already covered by D2D_RX_CLK_0 (their CP is io_pad_clk)
# and appear nowhere in the report. The report's columns are (Pin | Source |
# Reason), and reading Source as Pin is what made them look like the counters:
#
#   {gpiorx_0/link_data_reg_reg[0]/CP} {gpiorx_0/count_reg[3]/Q} {Disabled timing*}
#      ... x16 bits x 8 lanes = 128     (reports/eval/syn_timing_intent.rep:17-144)
#
# The unclocked PIN is link_data_reg_reg[15:0]/CP. count_reg[3]/Q is where clock
# propagation STOPPED. The reason is {Disabled timing}, NOT the Case constant(0)
# that accounted for 16,634 of the original 16,653 — different failure, different
# fix.
#
# WHY. WavD2DGpioRx_v2.v:1053 captures the recovered word on the FALLING edge:
#     always @(negedge w_lnk_clk or posedge io_por_reset) link_data_reg <= ...
# and io_link_clk == w_lnk_clk (:548). Genus takes that negedge off the divider's
# COMPLEMENTARY output, so in the gate netlist (gate.v:341339, :340902):
#     DFSND1  count_reg[3]         (.CP (io_pad_clk), .Q (count[3]), .QN (io_link_clk))
#     DFCNQD1 link_data_reg_reg[0] (.CP (count[3]), ...)                x16
# count[3] and io_link_clk are THE SAME CLOCK IN OPPOSITE PHASE on two different
# PINS of one cell. A clock declared on QN cannot reach Q — no combinational path
# exists, and clock does not propagate through a flop's CP->Q arc. So the negedge
# half needs its own declaration. Measured: `CP (count[3])` occurs EXACTLY 128
# times across the eight WavD2DGpioRx modules.
#
# WHAT IS UNTIMED WITHOUT THIS, and why it is not cosmetic. link_data_reg IS the
# RX datapath — the whole 128-bit recovered word, the last register before the
# deskew FIFO (WavD2DGpio_v2.v:899 wires u_deskew.lane_clk to the eight
# gpiorx_N_io_link_clk). Unconstrained today in BOTH directions:
#   link_data_word (D2D_RX_CLK_0, pad clock) -> link_data_reg   [a real check]
#   link_data_reg -> u_deskew write side (D2D_RX_WORD_CLK_n)    [80 ns, half word]
# And CCOpt does not see count[3] as a clock at all: it is routed as data, with
# no skew target and no balancing against the pad clock tree — on the one
# interface with a known marginal-eye data-drop failure mode.
#
# -invert, with the SAME -source and -divide_by as the positive-phase clock, so
# the two are 180 degrees apart BY CONSTRUCTION, exactly as Q and QN of one flop
# are. Do NOT give this its own -source or a hand-written -edges.
#
# ANCHOR count_reg[3]/Q. Measured 2026-08-09 by read-only probe: Q resolves 8/8
# at read time, QN resolves 0/8, and this block binds 8/8 and takes
# check_timing_intent's untimed count 128 -> 0 with multiple-waveform pins
# unchanged at 496. That Q/QN asymmetry (Q pre-map, QN post-map only) is the only
# reason this is expressible in SDC at all.
set _rxn_bound 0
foreach n {0 1 2 3 4 5 6 7} {
    set _pin [get_pins -quiet $GPIO/gpiorx_$n/count_reg\[3\]/Q]
    if {[sizeof_collection $_pin] == 0} {
        error "tidelink_constraints.sdc: D2D RX negedge word-clock anchor\
               $GPIO/gpiorx_$n/count_reg\[3\]/Q matched NOTHING. The 16 recovered\
               data-capture flops of lane $n (the RX word itself) would be left\
               untimed and CTS would build no tree for their clock. Refusing to\
               continue."
    }
    create_generated_clock -name "D2D_RX_WORDN_CLK_$n" \
        -source [get_ports TL_CLK_RX] -divide_by 16 -invert $_pin
    set_clock_uncertainty -setup $CLK_ERROR      [get_clocks "D2D_RX_WORDN_CLK_$n"]
    set_clock_uncertainty -hold  $CLK_HOLD_ERROR [get_clocks "D2D_RX_WORDN_CLK_$n"]
    incr _rxn_bound
}
if {$_rxn_bound != 8} {
    error "tidelink_constraints.sdc: bound $_rxn_bound/8 RX negedge word clocks"
}

# ---------------------------------------------------------------------------
# D2D TX RECOVERED WORD CLOCK (/16) — the other half of the domain.
#
# Measured 2026-08-09 with a read-only Genus probe (elaborate -> read_sdc ->
# check_timing_intent): with the RX block above ALONE, untimed sequential clock
# pins fall 16,653 -> 1,979, and every one of the remaining 1,979 is TX-side:
#   lltx 154, txpstate 21, txrouter 5, sp2wl/tx_fifo 14, plus the TX halves of
#   the four axi2wl FC-replay blocks (enable_link_clk_demet, a2l_fc_replay write
#   side). The gpiotx leaf count in the residual is ZERO — the TX *leaves* are
#   fine; it is the TX word *domain* that has no waveform.
#
# `gpiotx_$n/io_link_clk` is measured to resolve 8/8 at read time, same as RX.
# Do NOT anchor on count_reg[3]/QN: QN exists only post-map, and an SDC is read
# after elaborate and before mapping, so it would match nothing here.
#
# ---------------------------------------------------------------------------
# -source WAS $WL/pad_clk_tx. IT COULD NEVER RESOLVE, FOR ANY LANE, AND THE
# 2026-08-14 RUN SAYS SO 24 TIMES. CORRECTED 2026-08-17.
# ---------------------------------------------------------------------------
# The evidence, before the mechanism:
#
#   **WARN: (TA-1018): A source latency path to the generated clock
#   D2D_TX_WORD_CLK_3 through source pin .../u_wlink/pad_clk_tx to target pin
#   .../u_wlink/phy_gpio/gpiotx_3/io_link_clk in view default_analysis_view_hold
#   cannot be found. Timing analysis will use 0 ns source latency for the
#   generated clock and will interpret the master clock based on the polarity
#   at the master clock source pin.
#     (build/full-20260814/logs/pnr_qor_after_opt_design_post_cts.rep:113)
#
# 8 clocks x 3 analysis views = 24 TA-1018, and check_timing counts the same
# defect from the other end — "master_clk_edge_not_reaching  Master clock edge
# does not reach the generated clock target  16" (8 clocks x the 2 setup views,
# reports/check_timing_03_cts_opt.rep:15). NOT ONE of the 24 names an RX clock.
# The RX blocks above are clean, which is the control experiment: the shape they
# use works and the shape this block used did not.
#
# WHY IT COULD NEVER RESOLVE — pad_clk_tx AND io_link_clk ARE SIBLINGS, NOT
# PARENT AND CHILD. Both descend from ONE common high-speed net, and neither
# descends from the other. From the RTL, verified not assumed:
#
#   WavD2DGpio_v2.v:2088    hsclk_scan_mux_io_i_a = io_hsclk
#   WavD2DGpio_v2.v:1978++  gpiotx_<0..7>_io_clk  = hsclk_scan_mux_io_o_z
#       -> ONE ungated high-speed net feeds the io_clk of ALL EIGHT lanes.
#
#   WavD2DGpioTx.v:332      count <= count + 1 on posedge io_clk (free-running,
#                           4 bits, reset 4'hf)
#   WavD2DGpioTx.v:330      io_link_clk_mux_io_i_a = ~count[3]
#   WavD2DGpioTx.v:320      io_link_clk = io_link_clk_mux_io_o_z
#       -> the WORD clock is io_clk/16, taken off the UNGATED clock. Same /16,
#          same free-running-counter idiom as the RX side.
#
#   WavD2DGpioTx.v:326      hs_clk_gated_wcg_io_clk_in = io_clk
#   WavD2DGpioTx.v:322      io_pad_clk = hs_clk_gated_wcg_io_clk_out
#   WavD2DGpio_v2.v         io_pad_clk_tx = gpiotx_0_io_pad_clk
#       -> the PAD clock is a WavClockGate on that same io_clk, lane 0 only.
#
# So io_clk forks into (a) a clock GATE, giving pad_clk_tx, and (b) a /16
# DIVIDER, giving io_link_clk. There is no combinational path from (a) to (b),
# and clock does not propagate backwards out of an ICG, so NO -source expressed
# on pad_clk_tx can ever be found — not even for lane 0, whose own gate it is.
# This was never a hierarchy typo, and no amount of re-spelling the same pin
# would have fixed it.
#
# WHAT 0 ns SOURCE LATENCY COSTS, so this is not filed as a warning-count fix.
# The TX word domain is the ~2k flops censused above. With the source latency
# forced to zero, every one of them is timed against a clock the tool believes
# arrives instantly, while the real insertion delay through the pad, the SoC and
# the lane divider is order-of-nanoseconds — for scale, the measured RX-side
# figure is 1.09ns (pnr_m7.log:81871). Those same clocks are then handed to
# CCOpt. This is the third run to ship that way.
#
# THE FIX: SOURCE AT THE COMMON ANCESTOR, $WL/user_hsclk. That is the Wlink port
# the high-speed net enters on, three assigns above the lane mux:
#   Wlink.v:2105            phy_user_hsclk = user_hsclk
#   WlinkGPIOPHY_v2.v:357   gpio_io_hsclk  = user_hsclk
#   WavD2DGpio_v2.v:2088    hsclk_scan_mux_io_i_a = io_hsclk
# so user_hsclk -> hsclk mux -> gpiotx_$n/io_clk -> count_reg -> io_link_clk is
# ONE OPEN PATH. That is precisely the shape the RX blocks already prove works
# (TL_CLK_RX -> pad clock -> count_reg -> io_link_clk, zero TA-1018), and it is
# what the "mirror the RX pattern" instruction actually means: anchor where the
# divider's clock COMES FROM, not on a neighbouring branch of it.
#
# WHY THIS PIN AND NOT [get_ports CLK], WHICH WOULD ALSO RESOLVE. Two reasons,
# both about what the constraint is allowed to assert.
#   1. THE /16 CLAIM STAYS LOCAL. -divide_by 16 is a statement about the lane
#      divider and nothing else, and sourced here it is checkable in one file
#      (WavD2DGpioTx.v, quoted above). Sourced at CLK it would ALSO silently
#      assert that CLK -> user_hsclk is 1:1 — a claim spanning the pad wrapper,
#      the SoC, tidelink_top.sv:2483 and axi_chiplet_controller.sv:6160. That
#      chain is 1:1 today (pure assigns plus one scan mux, no PLL, no divider),
#      and it is still not this constraint's business to assert it.
#   2. IT SURVIVES THE user_ref_clk PAD DECISION EITHER WAY. See the [C2] block
#      in constraints.sdc: bonding user_ref_clk to its own pad is a live option
#      with pad-budget implications. If it is ever taken, -source [get_ports CLK]
#      becomes a lie that still elaborates and still reports clean; -source
#      $WL/user_hsclk simply picks up whatever master then feeds the link.
#
# D2D_TX_CLK_0 (top of this file) KEEPS -source $WL/pad_clk_tx AND IS CORRECT.
# There the source really is an ancestor of the target: pad_clk_tx drives the
# TL_CLK_TX pad. It draws no TA-1018. Do not "fix" it to match this block. The
# two clocks stay phase-coherent regardless, because the gate and the divider
# hang off the same io_clk.
#
# THE PIN EXISTS AND SURVIVES write_sdc — CHECKED AT BOTH ENDS:
#   * gate netlist: user_hsclk and pad_clk_tx are adjacent ports on the SAME
#     Wlink module header (outputs/nanosoc_eth_chiplet_pads_gate.v:387000).
#   * the previous run's WRITTEN SDC already carries a -source on
#     .../u_wlink/pad_clk_tx through write_sdc intact
#     (outputs/nanosoc_eth_chiplet_pads_syn.sdc:39), i.e. a port pin on this
#     exact instance round-trips. user_hsclk is its sibling on that header.
#   DO NOT be tempted by $GPIO/hsclk_scan_mux/io_o_z, which is nearer still:
#   `hsclk_scan_mux` does not appear ANYWHERE in the gate netlist (grep returns
#   nothing) because Genus dissolves the WavClockMux. That anchor would bind at
#   read time and then evaporate at write_sdc — the exact silent-drop failure
#   the guards in this file exist to prevent.
#
# WHAT AN SDC CANNOT CHECK, AND WHERE THE REAL GATE IS. The guards below prove a
# pin MATCHES. Nothing expressible in SDC proves a source latency path is
# REACHABLE, which is exactly how a block that binds 8/8 and errors loudly on a
# miss still shipped a whole domain with zero source latency. THE GATE IS THE
# TA-1018 / master_clk_edge_not_reaching COUNT IN THE NEXT RUN, AND IT MUST BE 0.
set _tx_src [get_pins -quiet $WL/user_hsclk]
if {[sizeof_collection $_tx_src] == 0} {
    error "tidelink_constraints.sdc: D2D TX word-clock SOURCE $WL/user_hsclk\
           matched NOTHING. Refusing to fall back to $WL/pad_clk_tx: that pin is\
           a SIBLING of the target (both hang off io_clk, one through a clock\
           gate and one through the /16 divider), so it can never resolve -- it\
           produced 24 TA-1018 'source latency path ... cannot be found' on\
           2026-08-14 and left ~2k TX flops on 0 ns source latency."
}
set _tx_bound 0
foreach n {0 1 2 3 4 5 6 7} {
    set _pin [get_pins -quiet $GPIO/gpiotx_$n/io_link_clk]
    if {[sizeof_collection $_pin] == 0} {
        error "tidelink_constraints.sdc: D2D TX word-clock anchor\
               $GPIO/gpiotx_$n/io_link_clk matched NOTHING. The TX word domain\
               (~2k flops) would be left untimed. Refusing to continue."
    }
    create_generated_clock -name "D2D_TX_WORD_CLK_$n" \
        -source $_tx_src -divide_by 16 $_pin
    set_clock_uncertainty -setup $CLK_ERROR      [get_clocks "D2D_TX_WORD_CLK_$n"]
    set_clock_uncertainty -hold  $CLK_HOLD_ERROR [get_clocks "D2D_TX_WORD_CLK_$n"]
    incr _tx_bound
}
if {$_tx_bound != 8} {
    error "tidelink_constraints.sdc: bound $_tx_bound/8 TX word clocks"
}

# THE CONSTRAINT BINDING HERE IS NOT THE SAME AS IT REACHING P&R.
# scripts/nanosoc_eth_chiplet_pads.mmmc:186-188 gives Innovus exactly ONE sdc
# file — outputs/${block_name}_syn.sdc, written by Genus. This file is read by
# GENUS ONLY. So these 16 clocks reach CTS only if `write_sdc` re-expresses them
# onto post-map pins (Genus merges seven of the eight RX dividers). That has
# never been demonstrated. 1b_synthesis_eval.tcl asserts 16/16 in the written
# SDC immediately after write_sdc for exactly this reason — if that gate fires,
# the fallback is a second -sdc_files entry in the mmmc, not a hand edit.
# EXPECT MORE TIMING PATHS/VIOLATIONS ON THE NEXT RUN, NOT FEWER. These 16,653
# flops were previously invisible to timing; now they are timed. That is the fix
# WORKING. The success metric is check_timing_intent "Sequential clock pins
# without clock waveform" collapsing from 16,653 toward 0 -- NOT the violation
# count. FOLLOW-UP (separate change, out of scope here): the lane_deskew is an
# async FIFO, so the lane<->lane and word<->capture (D2D_RX_CLK_0) crossings are
# CDC and want set_clock_groups -asynchronous / set_false_path once these clocks
# exist; without that the crossings will be timed and report spurious violations.

# ===========================================================================
# I/O DRIVE AND LOAD FOR THE DIE-TO-DIE LINK
# ===========================================================================
# Added 2026-08-07. Before this block the D2D ports had NO drive and NO load
# characterisation, so every TL_RX*/TL_CLK_RX input was timed with an
# infinitely sharp edge and every TL_TX*/TL_CLK_TX output drove nothing.
# Innovus says so explicitly for the clock (pnr_m7.log:81278):
#   **WARN: (IMPCCOPT-4313): Innovus cannot determine the drive strength of
#   TL_CLK_RX ... assume ... a fixed output slew of 0.000 and a maximum
#   driven capacitance of 0.000.
#
# WHY THIS INTERFACE CAN BE EXACT AND THE BOARD-LEVEL ONES CANNOT.
# The top (nanosoc_eth_chiplet_pads) includes the pad ring, so these ports are
# physical chip pins. For RMII / QSPI / HOSTIO the far-end driver is some
# external device with no model in our libraries, and any set_driving_cell
# there is a stand-in. NOT HERE: the far end of this link is the compute
# chiplet, built from the SAME TSMC pad library (tphn65lpgv2od3_sl). The
# driving cell is a real cell in our .lib, so `set_driving_cell` names the
# actual transistors and the far-end pin capacitance is a vendor number, not
# an estimate. Only the interconnect between the two dies is assumed.
#
# THE PARTNER'S PAD CELLS — VERIFIED, NOT ASSUMED. Read out of the compute
# chiplet's own pad wrapper,
#   ~/SoCLabs/NanoSoC-Compute-Chiplet/ASIC/chiplet-pads/tech_wrappers/tsmc65/
#   nanosoc_compute_chiplet_pads.v
# which instantiates, identically on both of its links (lines 334-351, 355-372):
#   D2D_TX_*/D2D_CLK_TX_*  ->  PDDW16DGZ_G   (16mA)  drives OUR TL_RX/TL_CLK_RX
#   D2D_RX_*/D2D_CLK_RX_*  ->  PDDW04DGZ_G   ( 4mA)  loads  OUR TL_TX/TL_CLK_TX
#
# NOTE THE LINK IS NOT SYMMETRIC. This die uses PDDW16DGZ_G on BOTH directions
# (ASIC/tech_wrappers/tsmc65/nanosoc_eth_chiplet_pads.v:460-584); the compute
# die uses PDDW16 to transmit but PDDW04 to receive. So the cell that loads our
# TX is NOT a mirror of our own RX pad. It barely matters for capacitance (the
# PAD pin cap varies very little across the 4/8/12/16mA family) but the
# right cell is named below regardless.

# --- Constants -------------------------------------------------------------
# (a) LIBERTY — exact vendor numbers, read from
#     $TSMC_65_HOME/CMOS/LP/IO2.5V/iolib/STAGGERED/tphn65lpgv2od3_sl_210a_FE/
#     .../NLDM/tphn65lpgv2od3_sl_210a/tphn65lpgv2od3_sl{wc,tc,bc}.lib
#     pin(PAD) { capacitance : ... } of PDDW04DGZ_G, the compute die's receiver.
#     Units are pF (capacitive_load_unit (1,pf)) and constraints.sdc:18 has
#     already done `set_units -capacitance pF`, so these need no scaling.
set TL_FAR_RX_PAD_CAP_MAX 1.53 ;# PDDW04DGZ_G PAD, wc lib -> setup
set TL_FAR_RX_PAD_CAP_MIN 1.38 ;# PDDW04DGZ_G PAD, bc lib -> hold

# (b) ASSUMPTION — the die-to-die interconnect. THIS IS THE ONLY NUMBER HERE
#     THAT IS NOT MEASURED, and it is the one to challenge first.
#     Assembly assumed: WIREBOND, both dies co-packaged / on a common carrier,
#     consistent with the bond pads this flow places (PAD70GU / PAD70NU, see
#     scripts/place_bondpads.tcl) and with a 1600x2000um MPW die whose whole
#     TL_* group sits on one edge (scripts/nanosoc_eth_chiplet_pads.io:50-75).
#     Budget, from published wirebond/MCM conventions (industry convention,
#     class (b) — not measured on this assembly):
#       bond wire  ~1 pF per wire including its landing pad (the commonly
#                  quoted figure; the wire itself is ~0.1-0.2 pF/mm, its
#                  inductance 0.5-1.0 nH/mm is the parameter that actually
#                  dominates a wirebond and STA cannot see it at all)
#       MCM/substrate trace ~2 pF/cm
#     MAX 2.0pF = two bond wires (die->substrate->die) + <=5mm of substrate
#                 trace. Pessimistic end of a co-packaged wirebond channel.
#     MIN 0.5pF = one short direct die-to-die bond wire, no substrate hop.
#
#     ASSEMBLY CONFIRMED CO-PACKAGED (project decision, 2026-08-07). The
#     budget below therefore STANDS and is no longer provisional. The paragraph
#     that follows is retained as the reason it mattered, and as the trigger to
#     revisit if that decision ever changes.
#
#     [WAS THE OPEN QUESTION] IF THE TWO DIES WERE NOT CO-PACKAGED — i.e. two
#     separately packaged parts wired on a PCB, which is how the FPGA-based
#     pair bring-up is done today — THIS WOULD BE WRONG BY AN ORDER OF MAGNITUDE.
#     Add package pin (1-3pF each) and PCB trace (2-3 pF/cm, so 6-30pF over
#     3-10cm) and the far-end load is 10-30pF, not 3.5pF. Silicon interposer
#     would be the other way, well under 1pF. Get the assembly drawing and
#     replace these two numbers; everything else in this block stands.
set TL_D2D_CHANNEL_CAP_MAX 2.0
set TL_D2D_CHANNEL_CAP_MIN 0.5

# (c) ASSUMPTION, low impact — the slew the compute die's core logic presents
#     to the I pin of its TX pad. 0.2ns sits inside the arc's characterised
#     slew range. Sensitivity is tiny: across that WHOLE range the pad's output
#     transition moves <0.1% and its delay moves by roughly a quarter of a
#     nanosecond, which is anyway common-mode between the forwarded clock and
#     its data. (Characterised axis endpoints, and the delay/transition figures
#     read off them, are vendor .lib data — TSMC licence forbids reproduction.
#     Source: tphn65lpgv2od3_sl*.lib.)
set TL_FAR_CORE_SLEW 0.2

# --- Inputs: TL_CLK_RX, TL_RX[7:0] -----------------------------------------
# Driven by the compute die's PDDW16DGZ_G TX pads, arc I -> PAD. PAD is
# declared `direction : inout` in the liberty (it is a bidir pad with
# function "I" and three_state "OEN"), which is the normal shape for this
# use; if a tool version refuses an inout as a driving pin the catch below
# substitutes the equivalent transition rather than silently leaving the port
# at slew 0.000, which is the bug being fixed.
#
# No -library qualifier ON PURPOSE: the MMMC setup carries three IO libraries
# (tphn65lpgv2od3_sl{wc,lt->bc,tc}, see scripts/nanosoc_eth_chiplet_pads.mmmc:26,
# 41, 56) and the cell must resolve per analysis view.
#
# Fallback values are the same arc's rise/fall_transition read at the load
# below. Our 3.6pF load sits UNDER the table's non-zero capacitance floor, so
# both are linear extrapolations below that floor, taken through the two lowest
# characterised load points:
#   rise -> 0.59ns
#   fall -> 0.53ns
# (The characterised transition values, and the load-axis points the
# extrapolation was taken through, are vendor .lib data — TSMC licence forbids
# reproduction. Re-derive from tphn65lpgv2od3_sl*.lib before changing these.)
# Sanity check on that result: ~0.55ns lands just inside the bottom of the input
# slew range the RECEIVING pad's PAD->C arc is characterised for. The two ends
# agree.
if {[catch {
    set_driving_cell -lib_cell PDDW16DGZ_G -pin PAD -from_pin I \
        -input_transition_rise $TL_FAR_CORE_SLEW \
        -input_transition_fall $TL_FAR_CORE_SLEW [get_ports TL_CLK_RX]
    set_driving_cell -lib_cell PDDW16DGZ_G -pin PAD -from_pin I \
        -input_transition_rise $TL_FAR_CORE_SLEW \
        -input_transition_fall $TL_FAR_CORE_SLEW [get_ports {TL_RX[*]}]
} tl_drive_err]} {
    puts "**WARN: tidelink_constraints.sdc: set_driving_cell rejected on the D2D"
    puts "**WARN: RX ports -- '$tl_drive_err'. Falling back to set_input_transition."
    set_input_transition -max 0.59 [get_ports TL_CLK_RX]
    set_input_transition -min 0.53 [get_ports TL_CLK_RX]
    set_input_transition -max 0.59 [get_ports {TL_RX[*]}]
    set_input_transition -min 0.53 [get_ports {TL_RX[*]}]
}

# Interconnect only. Our own receiving pad's PAD pin capacitance (PDDW16DGZ_G,
# worst-case lib) is already in the netlist -- Innovus reports exactly that
# figure back on this net (pnr_m7.log:81472, "Achieved capacitance of ..."),
# which is also independent confirmation that the liberty figures used here are
# the ones the tool is actually applying. Adding it again would double count.
# (Liberty pin capacitances redacted -- vendor characterisation data, TSMC
# licence forbids reproduction. Source: the tphn65lpgv2od3_sl*.lib files named
# in the constants block above.)
set_load -max $TL_D2D_CHANNEL_CAP_MAX [get_ports TL_CLK_RX]
set_load -min $TL_D2D_CHANNEL_CAP_MIN [get_ports TL_CLK_RX]
set_load -max $TL_D2D_CHANNEL_CAP_MAX [get_ports {TL_RX[*]}]
set_load -min $TL_D2D_CHANNEL_CAP_MIN [get_ports {TL_RX[*]}]

# --- Outputs: TL_CLK_TX, TL_TX[7:0] ----------------------------------------
# Far-end load = the compute die's PDDW04DGZ_G receiving pad (liberty, exact)
# + the interconnect allowance (assumed, see above).
set TL_TX_LOAD_MAX [format %.2f [expr {$TL_FAR_RX_PAD_CAP_MAX + $TL_D2D_CHANNEL_CAP_MAX}]] ;# 3.53pF
set TL_TX_LOAD_MIN [format %.2f [expr {$TL_FAR_RX_PAD_CAP_MIN + $TL_D2D_CHANNEL_CAP_MIN}]] ;# 1.88pF
set_load -max $TL_TX_LOAD_MAX [get_ports TL_CLK_TX]
set_load -min $TL_TX_LOAD_MIN [get_ports TL_CLK_TX]
set_load -max $TL_TX_LOAD_MAX [get_ports {TL_TX[*]}]
set_load -min $TL_TX_LOAD_MIN [get_ports {TL_TX[*]}]

# THIS LOAD IS AN ORDER OF MAGNITUDE SMALLER THAN THE OTHER INTERFACES', AND
# THAT IS CORRECT — DO NOT "CORRECT" IT UPWARD TO MATCH THEM. QSPI and Ethernet
# declare 11-20pF because they drive a board: package pin, PCB trace, and a
# receiver metres of copper away. This link drives across a wirebond gap to a
# die in the same assembly. If the two ever do end up as separate packaged
# parts on a PCB then they become board interfaces and their loads converge
# on those numbers — that is the same call flagged under (b) above, and it is
# the assembly drawing that decides it, not consistency with the neighbours.
#
# Headroom check against the design-wide rule: constraints.sdc carries
# `set_max_capacitance 100 [all_outputs]` (the largest load any driver in
# tphn65lpgv2od3 is characterised for). 3.53pF sits far inside it. Note that
# these ports are pad nets — Innovus flags them "internal don't touch reasons:
# {is_pad_net}" — so had the ceiling stayed at the 3pF it once was, these 9
# ports would have carried permanent, unfixable violations.
#
# [OWNER — scripts/cts_setup.tcl, NOT THIS FILE] set_driving_cell fixes the
# slew half of IMPCCOPT-4313. The warning also asks for the CCOpt clock-tree
# source driver on D2D_RX_CLK_0 ("set the cts_clock_tree_source_driver
# attribute on this clock tree"), which is a CCOpt property and not an SDC
# command. Point it at the same cell: PDDW16DGZ_G, arc I -> PAD. Note the
# "maximum driven capacitance of 0.000" half will persist regardless: the IO
# liberty declares no max_capacitance on ANY cell (grep -c max_capacitance
# over tphn65lpgv2od3_slwc.lib returns 0), so that ceiling can only ever come
# from an explicit constraint.

# --- Sanity check on the existing delays (VALUES DELIBERATELY UNCHANGED) ----
# $EXTCLK_PERIOD is $::env(CLK_PERIOD), default 10.0ns (ASIC/common.mk:159).
# Against that period the two delays above are exactly 10.0% and 8.0% of the
# cycle. THEY ARE ROUND PLACEHOLDERS, not a link budget, and nothing in this
# block changes them -- but here is what the pad numbers now say about them:
#
#   set_output_delay 0.8 -- the compute die's PDDW04DGZ_G RX pad alone burns
#   0.675ns on its PAD->C arc (wc, 0.5ns input slew, 0.05pF core load). That
#   leaves 0.125ns for the far die's pad-to-flop routing AND its flop setup,
#   which is not physical on a 1600x2000um die. It is only survivable because
#   the link is source-synchronous: TL_CLK_TX crosses an IDENTICAL PDDW04DGZ_G
#   pad, so the ~0.68ns is common-mode and cancels, and the real quantity is
#   (far data route - far clock insertion delay) + setup. On THIS die the
#   equivalent insertion delay is 1.09ns (pnr_m7.log:81871), i.e. large enough
#   to swing the correct number either side of 0.8. It cannot be settled from
#   inside this repo -- it needs the compute die's CTS report.
#
#   set_input_delay 1 -- carries NEITHER -max NOR -min, so SDC applies 1.0ns
#   to both. The tool therefore believes D2D data arrives at exactly +1.000ns
#   after the RX clock edge with ZERO valid-window uncertainty. For a
#   forwarded-clock source-synchronous interface the window IS the
#   constraint, and a min equal to the max is optimistic for hold: it asserts
#   the data can never arrive early. The launch pads are the same cell for
#   clock and data on both dies, so the residual is clock-to-Q + pad-to-pad
#   mismatch + channel skew, which is where a real -min belongs.
#
# For scale: at the load set above, the far TX pad's own I->PAD delay is
# ~2.4-2.9ns worst case -- roughly a quarter of the 10ns period spent in one
# pad. That is normal for a 3.0V I/O pad in this library and is common-mode,
# but it is why pad-to-pad MISMATCH, not pad delay, is the thing a real link
# budget has to bound.
#
# NOTE this block does NOT resolve the $CLK_ERROR placeholder flagged above.
# Drive and load are electrical characterisation; the setup uncertainty needs
# the far die's source jitter plus package and channel skew, which is a
# different measurement.
