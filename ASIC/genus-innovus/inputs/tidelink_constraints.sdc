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
