# Chiplet Interface
create_clock -name "D2D_RX_CLK_0" -period "$EXTCLK_PERIOD"  -waveform "0 [expr $EXTCLK_PERIOD/2]" [get_ports TL_CLK_RX]

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
# -source is $WL/pad_clk_tx — the same pin D2D_TX_CLK_0 already uses, so the two
# stay phase-coherent.
set _tx_bound 0
foreach n {0 1 2 3 4 5 6 7} {
    set _pin [get_pins -quiet $GPIO/gpiotx_$n/io_link_clk]
    if {[sizeof_collection $_pin] == 0} {
        error "tidelink_constraints.sdc: D2D TX word-clock anchor\
               $GPIO/gpiotx_$n/io_link_clk matched NOTHING. The TX word domain\
               (~2k flops) would be left untimed. Refusing to continue."
    }
    create_generated_clock -name "D2D_TX_WORD_CLK_$n" \
        -source [get_pins $WL/pad_clk_tx] -divide_by 16 $_pin
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
# PAD pin cap varies only 1.53-1.59pF across the 4/8/12/16mA family) but the
# right cell is named below regardless.

# --- Constants -------------------------------------------------------------
# (a) LIBERTY — exact vendor numbers, read from
#     $TSMC_65_HOME/CMOS/LP/IO2.5V/iolib/STAGGERED/tphn65lpgv2od3_sl_210a_FE/
#     .../NLDM/tphn65lpgv2od3_sl_210a/tphn65lpgv2od3_sl{wc,tc,bc}.lib
#     pin(PAD) { capacitance : ... } of PDDW04DGZ_G, the compute die's receiver.
#     Units are pF (capacitive_load_unit (1,pf)) and constraints.sdc:18 has
#     already done `set_units -capacitance pF`, so these need no scaling.
set TL_FAR_RX_PAD_CAP_MAX 1.53 ;# PDDW04DGZ_G PAD, wc lib (1.5297) -> setup
set TL_FAR_RX_PAD_CAP_MIN 1.38 ;# PDDW04DGZ_G PAD, bc lib (1.3822) -> hold

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
#     range (index_1 = 0.1 .. 1.0ns). Sensitivity is tiny: across that WHOLE
#     range the pad's output transition moves <0.1% (0.6692 -> 0.6691ns at
#     5pF) and its delay moves 0.256ns (2.516 -> 2.772ns), which is anyway
#     common-mode between the forwarded clock and its data.
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
# below. The table floors at 5pF ("total_output_net_capacitance" index_2 =
# 5,10,25,40,70,100) so both are linear extrapolations under the floor:
#   rise: 0.6681 - (0.9452-0.6681)/5 * (5.0-3.6) = 0.59ns
#   fall: 0.6168 - (0.9091-0.6168)/5 * (5.0-3.6) = 0.53ns
# Sanity check on that result: the RECEIVING pad's PAD->C arc is characterised
# for input slews of 0.5 .. 5.0ns, so ~0.55ns lands just inside the bottom of
# the range it was characterised for. The two ends agree.
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
# 1.5928pF wc) is already in the netlist -- Innovus reports exactly that number
# on this net (pnr_m7.log:81472, "Achieved capacitance of 1.593pF"), which is
# also independent confirmation that the liberty figures used here are the ones
# the tool is actually applying. Adding it again would double count.
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
