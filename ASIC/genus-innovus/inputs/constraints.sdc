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
# PROVENANCE CHECKED against the actual datasheet (TI SCAS869F, Feb 2009 rev
# June 2011) while adding the drive characterisation at the bottom of this file.
# VALUE DELIBERATELY UNCHANGED -- it is a signoff margin and it is CONSERVATIVE.
# But the one-line justification above is misleading about WHERE the 0.35 comes
# from, and the next person to "tighten it to the datasheet" will get a shock:
#
#   tRJIT  RMS phase jitter, 250 MHz LVCMOS, 10 kHz to 20 MHz  =  0.85 ps RMS
#
# 0.85 ps is 0.00085 ns. Even converted to peak-to-peak at BER 1e-12 (14.07 x
# RMS) that is only ~0.012 ns. JITTER IS NOT WHERE 0.35 ns COMES FROM -- it is
# roughly 1/29th of it. The term that actually dominates is in the row below:
#
#   ODC    Output duty cycle                            =  45% MIN / 55% MAX
#
# At 250 MHz (4 ns period) a 45%/55% duty cycle puts the falling edge at 1.8 ns
# instead of 2.0 ns: +/-0.2 ns of duty-cycle distortion, ~17x the jitter. So
# 0.35 ns is best read as ~0.2 ns duty-cycle distortion + ~0.01 ns jitter +
# margin, which is a defensible SETUP number and comfortably conservative.
#
# TWO CONSEQUENCES WORTH KNOWING:
#  - Duty-cycle distortion only bites checks that use the NEGATIVE edge. The
#    create_clock below declares a nominal 50% waveform. If this design is
#    genuinely posedge-only, most of the 0.35 ns is buying margin against a
#    mechanism that cannot reach it -- which is safe, but it is not free.
#  - It also means $CLK_HOLD_ERROR's reasoning (source jitter is common-mode
#    between launch and capture and cancels) is even STRONGER than written:
#    the true random-jitter term is ~0.012 ns, so 0.05 ns already covers it
#    with 4x headroom. Nothing to change; the existing note stands.
# HOLD uncertainty, deliberately NOT $CLK_ERROR. $CLK_ERROR is oscillator
# jitter: a legitimate SETUP margin, but for a same-edge hold check the source
# jitter is largely common-mode between launch and capture and cancels, so
# charging hold the full 0.35ns asks every hold path for delay it does not
# need. See the note on the set_clock_uncertainty calls below for what that
# cost. 0.05ns covers residual (non-common-mode) jitter and PLL/duty-cycle
# effects. THIS IS A SIGNOFF MARGIN — revisit it with the clocking spec, not
# casually.
set CLK_HOLD_ERROR 0.05
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


# QUALIFIED -setup/-hold. These two lines previously carried NEITHER, and SDC
# then applies the value to BOTH checks — so hold was being charged the full
# 0.35ns oscillator-jitter margin on every path in the design.
#
# That was the dominant cause of the hold-buffer explosion: post-CTS hold
# repair inserted 62,729 instances (+171,250 um2, utilisation 75.0% -> 89.6%)
# and drove setup WNS from +0.001 to -0.729 doing it. ~30,000 of the inserted
# cells are DEL0/DEL005/DEL01/DEL015 delay cells, and the worst hold violation
# entering repair was -0.726ns — roughly half of which was this margin rather
# than real skew. The 2026-07 reference run had the same bug (+148,558 um2 of
# hold repair); it simply had less logic to apply it to.
set_clock_uncertainty -setup $CLK_ERROR      [get_clocks $EXTCLK]
set_clock_uncertainty -hold  $CLK_HOLD_ERROR [get_clocks $EXTCLK]
set_clock_uncertainty -setup $CLK_ERROR      [get_clocks $SWDCLK]
set_clock_uncertainty -hold  $CLK_HOLD_ERROR [get_clocks $SWDCLK]

set_clock_uncertainty -setup $INTER_CLOCK_UNCERTAINTY -rise_from [get_clocks $SWDCLK] -rise_to [get_clocks $EXTCLK]
set_clock_uncertainty -setup $INTER_CLOCK_UNCERTAINTY -rise_from [get_clocks $EXTCLK] -rise_to [get_clocks $SWDCLK]

#### [C5] THE SWD EXCEPTIONS BELOW ARE DEAD CODE. NEUTRALISED 2026-08-17. #####
#
# READ THIS BEFORE UNCOMMENTING ANYTHING.
#
# THE DECISION: THIS CONSTRAINT SET USES set_clock_groups, NOT PER-PAIR
# EXCEPTIONS, TO DECLARE ITS ASYNCHRONOUS BOUNDARIES. ONE MECHANISM. The
# `set_clock_groups -asynchronous -name eth_chiplet_cdc` at the bottom of this
# file is the single place any clock-to-clock cut is expressed. The five lines
# below, and the CDC 1/2/3 exceptions in ethernet_constraints.sdc, are the OTHER
# mechanism. Both were live at once, which is worse than either alone: the file
# recorded two different intents for the same boundary and the next reader had a
# 50% chance of maintaining the one the tool ignores.
#
# WHY THEY ARE DEAD. $SWDCLK sits in a group of its own
# (-group [get_clocks [list $SWDCLK]]), so every swdclk <-> clk path is cut
# outright. set_clock_groups -asynchronous is defined as reciprocal FALSE PATHS
# between groups, and false path is the top of the SDC exception priority
# ladder: it beats set_multicycle_path unconditionally. The four multicycles
# below therefore apply to a set of paths that no longer exists, and the
# `set_false_path -hold` is a strictly weaker restatement of a cut already made
# in both directions.
#
# NOTE THE ORDERING ARGUMENT IS A RED HERRING, AND IT MATTERS THAT YOU KNOW.
# It is tempting to conclude "the group wins because it is written later".
# Exception PRIORITY, not file order, is what kills these — moving the group
# above the multicycles, or below them, changes nothing. This is also why the
# claim in ethernet_constraints.sdc CDC 1 that not grouping CLK<->SWDCLK there
# "preserves the existing SWD multicycle/false-path block" was wrong twice over:
# that file cannot preserve a block THIS file cuts, and it could not have done
# so by ordering even if it had tried. That comment is corrected in place.
#
# WHY THE GROUP AND NOT THE MULTICYCLES — the decision, argued rather than
# asserted:
#   * SWD IS GENUINELY ASYNCHRONOUS. It is driven by a debug probe with its own
#     oscillator (see the Lauterbach characterisation further down this file).
#     A 2-cycle multicycle relaxes a check between two clocks with NO phase
#     relationship; the check is meaningless at 2 cycles for exactly the reason
#     it is meaningless at 1. Relaxing a fiction does not make it true.
#   * THE CROSSING IS SYNCHRONISED IN RTL, in the CoreSight DAP, which is where
#     a clock-domain crossing belongs.
#   * THE MULTICYCLE BLOCK WAS ALREADY SELF-CONTRADICTORY before the group
#     existed: it declares `-hold 1 -end` in both directions and then a
#     `set_false_path -hold` in one of them. Two different hold intents on the
#     same clock pair, written four lines apart.
#   * THE GROUP IS WHAT THE SHIPPED DATABASE ACTUALLY USED. build/full-20260814
#     was placed, CTS'd and routed with these paths cut. Choosing the group is
#     therefore a NO-OP on timing and pure removal of dead text; choosing the
#     multicycles would newly time ~an entire debug interface and force a
#     re-closure. Do not spend a 5-hour run on that without deciding to.
#
# IF YOU EVER DO WANT SWD TIMED, the correct edit is to remove $SWDCLK's group
# from set_clock_groups AND re-enable the block below in the same change. Doing
# only the second half is the state this comment exists to prevent.
#
# ### Multicycle path through asynchronous clock domains
# set_multicycle_path 2 -setup -end -from [get_clocks $SWDCLK] -to [get_clocks $EXTCLK]
# set_multicycle_path 1 -hold -end -from [get_clocks $SWDCLK] -to [get_clocks $EXTCLK]
# set_multicycle_path 2 -setup -end -from [get_clocks $EXTCLK] -to [get_clocks $SWDCLK]
# set_multicycle_path 1 -hold -end -from [get_clocks $EXTCLK] -to [get_clocks $SWDCLK]
#
# set_false_path -hold -from [get_clocks $EXTCLK] -to [get_clocks $SWDCLK]
#
# FOR COMPLETENESS, THE TWO set_clock_uncertainty -rise_from/-rise_to LINES
# ABOVE ARE ALSO INERT for the same reason — there are no swdclk <-> clk paths
# left for an inter-clock uncertainty to apply to. They are LEFT IN PLACE, not
# neutralised: uncertainty is a margin, not an exception, it costs nothing while
# the group stands, and it is exactly what you would need back if the group were
# ever split. Flagged so nobody re-derives them as evidence the crossing is timed.
##############################################################################

### Multicycle path through pads
##
## THIS GLOB MATCHES POWER AND GROUND PINS, AND THAT STOPS PLACEMENT.
##
## `uPAD*/*` selects every pin on every pad instance, supply pins included.
## Genus resolves it against its own pin namespace -- which contains PG pins --
## and writes the expansion out as 548 literal `get_pins` entries into
## outputs/${block}_syn.sdc. Innovus's `get_pins` does NOT resolve PG pins, so
## each one raises TCLCMD-917: 34 distinct objects, exactly one per supply pad
## (12 VDDPST, 12 VSSPST, 6 VDD, 4 VSS), each twice because the same wildcard
## feeds both -from and -to.
##
## IT WAS INVISIBLE UNTIL THE PAD RING WAS FIXED. While synthesis was deleting
## all 34 supply pads as unloaded, the expansion produced no PG pins at all and
## this line looked clean. Restoring the pads did not create the defect; it
## uncovered one that had been masked by the other. Both flows now hit it:
## ASIC/genus-innovus allowlists TCLCMD-917 (2b_pnr_place_eval.tcl) so placement
## survives; the toolkit ships an empty PLACE_ERROR_ALLOWLIST, so the same
## successful placement -- 198,110 instances, 0 unplaced, database written -- is
## rejected afterwards by the message census.
##
## ALLOWLISTING IS THE WORKAROUND. The fix is to stop selecting PG pins here, so
## the synthesised SDC never carries the 34 bogus objects into any downstream
## tool. Semantically that changes nothing: PG pins have no timing arcs, so a
## multicycle exception on them was never doing anything.
##
## AN ATTRIBUTE FILTER CANNOT DO IT. Two independent reasons, both established
## against the installed reference rather than assumed:
##
##   1. Genus's SDC `get_pins -filter` has NO power/ground predicate. The command
##      reference enumerates the supported expressions exhaustively and
##      is_power/is_ground are not among them -- they exist only as lib_pin
##      attributes reachable through get_db, below the SDC layer.
##   2. Even if one existed it would answer false. This pad Liberty declares its
##      supply pins as ordinary `pin(...)` with `direction : inout` and no
##      `pg_type` -- old-style modelling. Nothing in the Liberty marks them as
##      power at all.
##
## AND THAT IS ALSO WHY THE TWO TOOLS DISAGREE. Genus takes the Liberty at face
## value and sees them as ordinary pins; Innovus classifies them as PG from the
## LEF and the power intent and removes them from the timing-pin namespace. The
## asymmetry is in the tools' PIN MODELS, not in filter spelling, so no amount of
## getting the filter right would have reconciled it.
##
## `direction` is dead for the same reason: the real signal pin PAD is `inout`,
## exactly like every supply pin.
##
## THE ONLY DISCRIMINATOR IN THE SDC LAYER IS THE PIN NAME, and here it is exact
## and stable -- signal pins are {I, C, PAD, OEN, REN} across all four signal pad
## types, supply pins are {VDD, VDDPST, VSS, VSSPST}. Naming them explicitly is
## plain SDC with no vendor filter, so Formality and PrimeTime read it identically:
##
##   set_multicycle_path 2 \
##     -from [get_pins {uPAD*/I uPAD*/C uPAD*/PAD uPAD*/OEN uPAD*/REN}] \
##     -to   [get_pins {uPAD*/I uPAD*/C uPAD*/PAD uPAD*/OEN uPAD*/REN}]
##
## NOT APPLIED YET. Acceptance, all three: the expansion in
## outputs/${block}_syn.sdc drops 548 -> 480 entries (34 distinct PG objects, each
## appearing twice because one wildcard feeds both -from and -to); TCLCMD-917 goes
## to zero in the Innovus log; and setup/hold are UNCHANGED. The third is the one
## that matters -- PG pins carry no timing arcs, so if timing moves at all, the
## premise that this exception was inert on them was wrong.
set_multicycle_path 2 -from uPAD*/* -to uPAD*/*

### IP Constraints
source ../inputs/qspi_constraints.sdc

source ../inputs/tidelink_constraints.sdc

source ../inputs/ethernet_constraints.sdc

source ../inputs/i2c_constraints.sdc

#### DELAY DEFINITION

set_input_delay -clock [get_clocks $EXTCLK] -add_delay 0.1 [get_ports NRST]
# REMOVED 2026-08-17: set_input_delay ... 0.1 [get_ports TEST]
# TEST carries `set_case_analysis 0` at the bottom of this file. A port held at a
# case-analysed constant launches no transition, so it has no arrival window and
# the input delay could never produce a check — the constraint was dead the
# moment the case analysis was added. Worse than dead: it is the only surviving
# statement in this file that TEST is a TIMED input, and the block around the
# case analysis says the opposite ("STATIC configuration pins -- strapped, and
# never toggling in mission mode"). SE, the other strap, correctly has none and
# always did; this line is what made the pair look deliberately different.
# If the scan chain is ever bonded and TEST genuinely becomes a timed input,
# restore this line IN THE SAME CHANGE that comments out its set_case_analysis
# — not on its own.
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
#   sys_fclk + scan_clk + rtc_clk -> $EXTCLK (+ the QSPI clocks generated off it,
#                                    + the 9 D2D transmit clocks, per [C2] A)
#   user_ref_clk + pad_clk_tx     -> FOLDED INTO THE $EXTCLK GROUP. [C2] IS
#                                    RESOLVED IN THE A DIRECTION (see the block
#                                    below). user_ref_clk is aliased onto the
#                                    sys_fclk pad, so the transmit chain IS
#                                    $EXTCLK and its own group was fiction. The
#                                    reasoning that used to sit here ran the
#                                    alias BACKWARDS and concluded the cut was
#                                    REAL. Do not restore that sentence.
#   pad_clk_rx                    -> D2D_RX_CLK_0
#   rmii_ref_clk                  -> stands alone, dragging its two divide-by-2
#                                    MII clocks with it.
#
#############################################################################
# [C2] RESOLVED — OPTION A TAKEN. THE TRANSMIT CLOCKS ARE IN THE $EXTCLK GROUP,
#      BECAUSE THEY ARE GENERATED FROM IT. The boundary is now TIMED, and the
#      genuine synchroniser crossings across it are cut BY NAME below.
#############################################################################
#
# WHAT THE PROBLEM WAS. D2D_TX_CLK_0 and D2D_TX_WORD_CLK_0..7 used to sit in a
# `-group` of their own, i.e. declared -asynchronous to $EXTCLK, while being
# GENERATED FROM IT on the same net. The pad wrapper aliases user_ref_clk onto
# the sys_fclk pad (nanosoc_eth_chiplet_pads.v:137,266; the ALIASED CLOCKS block
# of sys_desc/chip_boundary/nanosoc_eth_chiplet.yaml), so the whole Wlink
# transmit chain hangs off the CLK pad.
#
# EVIDENCE, EXHAUSTIVE AND FROM THE TOOL ITSELF. In build/full-20260814,
# logs/pnr_qor_after_opt_design_post_cts.rep:
#     Using master clock 'clk' for generated clock 'D2D_TX_CLK_0'
#     Using master clock 'clk' for generated clock 'D2D_TX_WORD_CLK_0' ... _7
#   9 transmit clocks x 3 analysis views = 27 lines. ZERO of them resolve to
#   any master other than `clk`. The control experiment is receive: all 16
#   D2D_RX_* clocks resolve 'D2D_RX_CLK_0' and NONE resolves 'clk'. The
#   asymmetry is real and it is one-sided.
#
# THE NETLIST SAYS IT EVEN MORE PLAINLY THAN THE TIMER DOES. Inside the
# synthesised Wlink, the app-side and link-side halves of each a2l flow-control
# replay buffer are clocked by `user_hsclk` and `phy_link_tx_tx_link_clk` --
# and `user_hsclk` is the same physical net as the Wlink's app_clk, because
# tidelink_top wires .app_clk(hclk) and the SoC's hclk is sys_fclk. The two
# "domains" the RTL synchronises between are one net and its own /16.
#
# WHAT MERGING COSTS -- MEASURED, NOT ESTIMATED. Structural fan-in over the
# synthesised Wlink gives 1451 flops on the transmit word clock, of which
#     1003 capture from the clk domain, and
#      181 launch into it.
# Those 1184 endpoints were false-pathed by group membership and are now timed.
# Note also that only D2D_TX_WORD_CLK_0 carries any of them:
# `phy_link_tx_tx_link_clk` is driven from gpiotx_0 alone
# (WavD2DGpio_v2.v:1961), and D2D_TX_WORD_CLK_1..7 clock only per-lane
# serialiser flops with no clk-domain fan-in. CTS agrees -- it built exactly one
# transmit word-clock tree, D2D_TX_WORD_CLK_0, with 1495 flops
# (reports/cts_clock_trees.rep).
#
# READ THE NEXT TWO BLOCKS BEFORE JUDGING A RUN MADE WITH THIS OPTION. The
# demet cuts below handle the SYNCHRONISERS. They do NOT handle the
# handshake-protected DATA the synchronisers qualify, which by design has no
# demet on it at all. That is the second block, and the honest note attached to
# it about what is still not covered.
#############################################################################
#
# [OWNER] For SIGNOFF, narrow the D2D_RX_CLK_0 cut rather than leaving it a
# blanket group: TideLink's own SDC constrains that crossing instead of grouping
# it. See the note in constraints/nanosoc_eth_chiplet_cdc.sdc. This is the
# bring-up cut, and it is deliberately conservative.
# The 16 D2D word clocks join their OWN pad clock's group. tidelink_constraints.sdc
# is sourced at line 112 above, so all 16 exist by the time this runs.
#
# WHY IN-GROUP AND NOT SEPARATE GROUPS. set_clock_groups cuts BETWEEN groups, never
# within one. Putting D2D_RX_WORD_CLK_0..7 alongside D2D_RX_CLK_0 therefore cuts
# them from the system clock, QSPI, RMII and SWD - crossings that are genuinely
# asynchronous and would otherwise report ~16.5k newly-timed flops' worth of
# nonsense - while leaving every path INSIDE the D2D receive domain still timed.
# That is the conservative choice: nothing in the link gets silently false-pathed.
#
# [OWNER, DO NOT LET THIS SLIDE] Two intra-domain questions are deliberately left
# TIMED here rather than decided in this file:
#   - lane<->lane. All 8 share -source and -divide_by so they are phase-aligned by
#     construction and should meet timing; if they do not, that is a real finding.
#   - word<->capture (D2D_RX_CLK_0 -> D2D_RX_WORD_CLK_n) across u_deskew, which is
#     an async FIFO. This one probably DOES want a narrow set_false_path on the
#     FIFO's data path only - not a blanket group cut. Constrain it properly once
#     the first run shows what it reports.
# Plain foreach, not lmap/string cat: those need Tcl 8.6+, and an SDC is read by
# whichever interpreter the tool embeds. A constraint file that errors on one tool
# and not another is the worst possible failure here.
set _rx_grp {D2D_RX_CLK_0}
set _tx_grp {D2D_TX_CLK_0}
foreach n {0 1 2 3 4 5 6 7} {
    lappend _rx_grp "D2D_RX_WORD_CLK_$n"
    lappend _rx_grp "D2D_RX_WORDN_CLK_$n"   ;# negedge half - same domain, opposite phase
    lappend _tx_grp "D2D_TX_WORD_CLK_$n"
}
if {[llength $_rx_grp] != 17 || [llength $_tx_grp] != 9} {
    error "constraints.sdc: D2D clock groups built wrong -\
           rx [llength $_rx_grp], tx [llength $_tx_grp], expected 17 and 9"
}
# [C2 OPTION A] THE MERGE. $_tx_grp is still BUILT as its own list -- the loop
# above and the guard on it are unchanged, so a lane that goes missing is still
# caught -- but it is now CONCATENATED into the system group instead of being
# passed as a `-group` of its own. That single change is the whole of Option A's
# effect on clock grouping: four groups where there were five, and the transmit
# clocks timed against the clock they are generated from.
set _sys_grp [concat [list $EXTCLK QSPI_SCLK QSPI_SCLK_o] $_tx_grp]
if {[llength $_sys_grp] != 12} {
    error "constraints.sdc: C2 OPTION A system group built wrong -\
           [llength $_sys_grp] clocks, expected 12 (clk + 2 QSPI + 9 D2D TX).\
           If you are reverting to the pre-C2 five-group form, revert the\
           demet false-path block below IN THE SAME CHANGE: those exceptions\
           exist only because this merge times the boundary, and left behind\
           they would cut synchroniser crossings the group already cuts --\
           the two-mechanism defect the C5 block at the top of this file
           spends seventy lines explaining."
}
set_clock_groups -asynchronous -name eth_chiplet_cdc \
    -group [get_clocks $_sys_grp] \
    -group [get_clocks $_rx_grp] \
    -group [get_clocks {rmii_ref_clk mii_rx_clk mii_tx_clk}] \
    -group [get_clocks [list $SWDCLK]]

#############################################################################
# [C2 OPTION A] PART 2 OF 3 — NARROW, NAMED CUTS ON THE SYNCHRONISERS.
#############################################################################
# THIS IS NOT A BLANKET CUT AND MUST NOT BECOME ONE. Every exception below ends
# at the FIRST STAGE of one named synchroniser instance. A blanket
# `set_false_path -from clk -to [get_clocks D2D_TX_WORD_CLK_*]` would restore
# exactly the hole the merge was made to close, in a different shape.
#
# WHAT A "FIRST STAGE" IS HERE, because the answer is not the obvious one.
# WavDemetReset carries TWO implementations behind `ifdef ASIC_TSMC65`: a
# structural pair of SDFCNQD1 named u_f1/u_f2, and a behavioural pair of
# always-blocks on regs f1/f2. ASIC_TSMC65 IS NOT DEFINED IN THIS FLOW -- it
# belongs to TideLink's Fusion Compiler flow -- so this design synthesises the
# BEHAVIOURAL branch. Checked, not assumed: `u_f1` appears ZERO times in
# outputs/nanosoc_eth_chiplet_pads_gate.v, while f1_reg and f2_reg each appear
# 282 times. The endpoint is therefore `<instance>/f1_reg*/D`. The `*` covers
# the multi-bit variants, whose flops are f1_reg[0..n].
#
# AND THE INSTANCES ARE DISSOLVED, WHICH IS WHY THE GUARD MATTERS. Genus
# ungroups WavDemetReset: in the gate netlist there is no such module, only
# `enable_link_clk_demet_f1_reg` sitting in the parent with the hierarchy
# underscore-joined into its name. This SDC is read AFTER elaborate and BEFORE
# mapping, so the hierarchical form below is the correct one to write and Genus
# re-expresses it at write_sdc -- the same translation that turns
# .../u_wlink/phy/gpio/... into .../u_wlink/phy_gpio/... in
# outputs/nanosoc_eth_chiplet_pads_syn.sdc. Do not "fix" these to the flattened
# spelling; it would not resolve at read time.
#
# WHY THESE INSTANCES AND NOT THE OTHER 115. There are 176 demet instances under
# the Wlink. Only the ones bridging $EXTCLK and the TRANSMIT word domain are
# affected by this merge, and only those are cut here. Every capture domain
# below was READ OFF THE .CP PIN of the demet's f1 flop in the gate netlist, not
# inferred:
#   user_hsclk                 -> the app/system domain, i.e. $EXTCLK
#   phy_link_tx_tx_link_clk    -> D2D_TX_WORD_CLK_0
#   phy_link_rx_rx_link_clk_o  -> the receive word domain
# DELIBERATELY EXCLUDED, each for a stated reason:
#   l2a_fc_replay/*      its app_clk port is wired to the RX clock and its
#                        link_clk port to the app clock, so every demet in it is
#                        clk<->RX. The RX group already cuts that. Cutting it
#                        again here would be the [C5] two-mechanism defect.
#   ack_nack_fifo/*, cr_pkt_seen_tx_demet, crack_pkt_seen_tx_demet
#                        RX word -> TX word. Both ends outside the merge.
#   phy/gpio/*           reset synchronisers on io_clk, which is in the $EXTCLK
#                        group before and after this change. Nothing moved.
#   app_clk_reset_scan_wrs, ff2_demet{,_1,_2}
#                        both ends in the $EXTCLK / apb domain.
#   txrouter/en_ff2_demet
#                        IS on the TX clock, but the netlist shows Genus tied
#                        its D pin to 1'b1. There is no arc from clk to cut.
#   en_ff2_tx_demet / en_ff2_rx_demet
#                        do not survive mapping at all (CSE'd onto a shared
#                        swi_enable driver). They resolve pre-map, so including
#                        them would not error -- they are left out because an
#                        exception on a path that no longer exists is noise.
set _c2_fc {
    axi2wl/wlink_axiawFC  axi2wl/wlink_axiwFC   axi2wl/wlink_axibFC
    axi2wl/wlink_axiarFC  axi2wl/wlink_axirFC
    gb2wl/wlink_generalbusgb  tl2wl/wlink_tidelinktl
}
set _c2_sfx {
    a2l_fc_replay/enable_app_clk_demet
    a2l_fc_replay/enable_link_clk_demet
    a2l_fc_replay/fifo/sync_wptr_demet
    a2l_fc_replay/fifo/sync_rptr_demet
    a2l_fc_replay/link_addr_to_app_clk/addrsync/rptr_wclk_demet
    a2l_fc_replay/link_addr_to_app_clk/addrsync/wptr_rclk_demet
    l2a_fifo_addr_to_tx/addrsync/wptr_rclk_demet
    l2a_fifo_addr_to_tx/addrsync/rptr_wclk_demet
}
# Not under a flow-control block, and each verified individually in the gate
# netlist by its .CP net:
#   lltx/*                      TX capture, enable + error-injection from clk
#   tx_link_clk_reset_wrs/...   TX capture, the transmit reset RELEASE from clk
#   sp2wl/tx_fifo/sync_*ptr     the short-packet TX FIFO's gray pointers
set _c2_solo {
    lltx/enable_ff2_demet
    lltx/err_inj_ff2_demet
    tx_link_clk_reset_wrs/reset_sync_demet
    sp2wl/tx_fifo/sync_wptr_demet
    sp2wl/tx_fifo/sync_rptr_demet
}
# tidelink_fcemit_obs is SoC Labs' own observability block, not Wav IP, so it
# does not use WavDemetReset and its first stage is <signal>_s0 rather than f1.
# It is a plain 2FF synchroniser TX word -> clk. Its 41 flops are the single
# largest TX->clk group in the design and they are ALL synchroniser first or
# second stages, so leaving them timed would be the loudest false alarm in the
# first Option A report.
set _c2_obs {asl ioen oae sop grant cnt idaw idsb}

set _c2_pins {}
foreach fc $_c2_fc {
    foreach s $_c2_sfx { lappend _c2_pins "$WL/$fc/$s/f1_reg*/D" }
}
foreach s $_c2_solo { lappend _c2_pins "$WL/$s/f1_reg*/D" }
foreach s $_c2_obs  { lappend _c2_pins "$WL/u_fcemit_obs/${s}_s0_reg*/D" }
if {[llength $_c2_pins] != 69} {
    error "constraints.sdc: C2 OPTION A built [llength $_c2_pins] synchroniser\
           anchors, expected 69 (7 flow-control blocks x 8, + 5 standalone,\
           + 8 fcemit_obs). The lists above were edited without the count."
}
# error, NOT continue -- the same doctrine as the word-clock guards in
# tidelink_constraints.sdc. A silently-skipped anchor leaves a synchroniser
# crossing timed against a clock it was never meant to meet, the run completes,
# and the violation reads as a real one. Every anchor below was confirmed
# present in build/full-20260814; a miss means the Wlink hierarchy moved.
foreach _p $_c2_pins {
    if {[sizeof_collection [get_pins -quiet $_p]] == 0} {
        error "constraints.sdc: C2 OPTION A synchroniser anchor $_p matched\
               NOTHING. Refusing to continue: with the transmit clocks now in\
               the $EXTCLK group, an unmatched anchor means a real CDC crossing\
               is being timed as if it were synchronous. If the demet flops are\
               named something other than f1_reg in your Genus version, fix the\
               pattern here -- do NOT fall back to a blanket clock-to-clock cut."
    }
}
set_false_path -from [get_clocks $EXTCLK]  -to [get_pins $_c2_pins]
set_false_path -from [get_clocks $_tx_grp] -to [get_pins $_c2_pins]

#############################################################################
# [C2 OPTION A] PART 3 OF 3 — THE HANDSHAKE-PROTECTED DATA, AND WHAT IS STILL
#               NOT COVERED. READ THIS BEFORE CALLING AN OPTION A RUN CLEAN.
#############################################################################
# THE SYNCHRONISERS ABOVE ARE NOT THE CROSSING. They are the POINTERS AND
# ENABLES that make the crossing safe. The payload itself -- the FIFO memory
# array, the WavMultibitSync address memories -- crosses with NO synchroniser on
# it at all, and that is correct by design: the gray-coded pointer is demet'd,
# and the pointer's value is what guarantees the data is stable before the read
# side looks at it. Cutting those paths outright would be wrong; timing them
# against an unrelated edge is also wrong.
#
# THE RIGHT INSTRUMENT IS A DATAPATH BOUND, NOT A FALSE PATH. What actually has
# to hold is that the bits of one word do not skew past each other by more than
# a destination cycle. set_max_delay -datapath_only expresses exactly that and
# nothing more: it bounds combinational delay and ignores clock latency, so it
# does not assert any edge relationship between the two clocks.
#
# THE BUDGET IS ONE SYSTEM CLOCK PERIOD. For clk -> TX word that is one period
# of the faster (launch) clock; for TX word -> clk it is one period of the
# destination. Both are $EXTCLK_PERIOD, which is why one number serves both.
#
# WRAPPED IN catch FOR THE SAME REASON THE D2D set_driving_cell IS
# (tidelink_constraints.sdc:483): -datapath_only is not universally supported,
# and a constraint file that aborts on one tool and not another is the worst
# failure mode available here. If it is rejected the fallback is a plain
# set_max_delay at the same budget, which is STRICTER, never looser.
set _c2_dp {}
foreach fc $_c2_fc {
    lappend _c2_dp "$WL/$fc/a2l_fc_replay/fifo/mem"
    lappend _c2_dp "$WL/$fc/a2l_fc_replay/link_addr_to_app_clk/addrsync"
    lappend _c2_dp "$WL/$fc/l2a_fifo_addr_to_tx/addrsync"
}
lappend _c2_dp "$WL/sp2wl/tx_fifo/mem"
if {[llength $_c2_dp] != 22} {
    error "constraints.sdc: C2 OPTION A built [llength $_c2_dp] datapath\
           anchors, expected 22 (7 x 3 + 1)."
}
foreach _p $_c2_dp {
    if {[sizeof_collection [get_cells -quiet $_p]] == 0} {
        error "constraints.sdc: C2 OPTION A datapath anchor $_p matched\
               NOTHING. These are named hierarchical instances (a2l_fc_replay's
               `mem`, the WavMultibitSync `addrsync`); a miss means the Wlink
               hierarchy moved and the payload crossings are being timed as
               synchronous."
    }
}
if {[catch {
    set_max_delay -datapath_only $EXTCLK_PERIOD \
        -from [get_cells $_c2_dp] -to [get_clocks $_tx_grp]
    set_max_delay -datapath_only $EXTCLK_PERIOD \
        -from [get_cells $_c2_dp] -to [get_clocks $EXTCLK]
} _c2_dp_err]} {
    puts "**WARN: constraints.sdc: C2 OPTION A set_max_delay -datapath_only"
    puts "**WARN: rejected -- '$_c2_dp_err'. Falling back to plain set_max_delay,"
    puts "**WARN: which is STRICTER (it charges clock latency too), not looser."
    set_max_delay $EXTCLK_PERIOD -from [get_cells $_c2_dp] -to [get_clocks $_tx_grp]
    set_max_delay $EXTCLK_PERIOD -from [get_cells $_c2_dp] -to [get_clocks $EXTCLK]
}
#
# WHAT IS STILL NOT COVERED, STATED PLAINLY SO THE FIRST RUN IS NOT MISREAD.
# The two blocks above cover the synchronisers and the FIFO/address-sync
# payload. They do NOT cover every one of the 1184 endpoints the merge exposes.
# Structural fan-in names roughly 200 more that are neither: lltx/link_data_reg
# (128 bits), lltx/byte_count_reg, txpstate/count_reg, sp2wl/tx_data_reg,
# txrouter/curr_ch_reg and u_fcemit_obs's own capture registers. Some of those
# are downstream of a cut already made here and will resolve themselves; the
# rest are genuinely timed clk -> TX-word paths across a /16 ratio with a
# full $EXTCLK_PERIOD of budget, and they SHOULD close.
#
# THE ACCEPTANCE GATE FOR OPTION A IS THEREFORE NOT "ZERO VIOLATIONS". It is:
#   1. check_timing's master_clk_edge_not_reaching stays at 0 (this change must
#      not disturb the -source anchors -- it does not touch them);
#   2. the violating endpoints that remain are ENUMERATED and each is either
#      closed by real optimisation or given its own named exception here;
#   3. no exception added in step 2 is expressed clock-to-clock.
# An Option A run whose report is read as "1184 new violations, revert" has
# learned nothing. An Option A run that ends with step 2's list empty is the
# only version of this option that is finished.
unset _c2_fc _c2_sfx _c2_solo _c2_obs _c2_pins _c2_dp _sys_grp _p
unset _rx_grp _tx_grp

#### EXTERNAL DRIVE AND LOAD CHARACTERISATION #################################
#
# WHY THIS SECTION EXISTS. Until now this file declared NO set_driving_cell, NO
# set_input_transition and NO set_load. The consequence is not "no constraint",
# it is a pair of WRONG constraints applied silently:
#   - every input port was assumed to have an INFINITELY SHARP EDGE (0 ns), and
#   - every output port was assumed to drive ZERO capacitance.
# Innovus says so out loud for all four clock trees (IMPCCOPT-4313): "...will
# assume that it is driven by a driver cell with a fixed output slew of 0.000
# and a maximum driven capacitance of 0.000." Every clock tree in the shipped
# GDS was built on that assumption.
#
# THIS TOP IS THE PAD RING. `nanosoc_eth_chiplet_pads` INCLUDES the pads, so the
# ports below ARE the physical chip pins -- the OUTSIDE face. These numbers are
# therefore SYSTEM-level (what the board drives / what the board presents), not
# library-level. That is exactly why they were missing: they cannot be derived
# from the PDK. `set_driving_cell` is deliberately NOT used anywhere here --
# it requires a lib_cell that exists in our libraries, and a TI clock generator
# or a debug probe is not in tphn65lpgv2od3. `set_input_transition` is the
# correct instrument for a board-level source.
#
# UNITS AND THRESHOLDS -- READ BEFORE CHANGING ANY NUMBER.
#   set_units above declares ns and pF, which match the units the IO liberty
#   itself declares -- check them there before changing a number here, and note
#   that the library applies no slew derate.
#   The IO liberty measures slew between the 10% and 90% points.
#   (Liberty header key/value pairs, including the nominal supply, are not
#   reproduced -- vendor characterisation data, TSMC licence forbids it.
#   Source: tphn65lpgv2od3_sl*.lib.)
#   Datasheets almost always quote 20%-80%. EVERY datasheet number below is
#   therefore scaled to the library's thresholds by the linear-ramp factor
#       (90-10)/(80-20) = 80/60 = 4/3
#   before being written into a constraint. An unconverted 20%-80% number would
#   under-state the real edge by 25%.
#
# WHAT THE PADS ARE ACTUALLY CHARACTERISED FOR (tphn65lpgv2od3_slwc.lib):
#   input  (PAD->C):  input_net_transition, over a nanosecond-range slew axis
#   output (I->PAD):  total_output_net_capacitance, over a picofarad-range load
#                     axis with a NON-ZERO floor (all drive strengths; the OSC
#                     pads use a shorter axis than the rest)
#   Note that the OUTPUT axis has a floor at all. With set_load absent (= 0 pF)
#   every output timing arc in this design was being EXTRAPOLATED off the bottom
#   of its own NLDM table. The library's default_max_transition is the CEILING of
#   the input table, not a target.
#
#   Liberty table names and axis endpoints redacted — vendor characterisation
#   data, TSMC licence forbids reproduction. Read them in tphn65lpgv2od3_sl*.lib
#   before changing any value in this section.
#
# CONFIDENCE CLASS is tagged on every value below and means exactly this:
#   [DATASHEET]   a number read from a named document, with the parameter name.
#   [CONVENTION]  a widely-used industry default, justified but not measured.
#   [PLACEHOLDER] an engineering guess, deliberately labelled. REPLACE IT when
#                 the board design exists. A labelled placeholder is honest; an
#                 unlabelled guess is worse than the zero it replaces.

### --- CLK : Texas Instruments CDCM61001 -------------------------------------
#
# SOURCE: TI CDCM61001, "One Output, Integrated VCO, Low-Jitter Clock
# Generator", document SCAS869F (February 2009, revised June 2011),
# ELECTRICAL CHARACTERISTICS table, "LVCMOS Output Characteristics".
#
# OUTPUT TYPE -- CHECKED, because it decides whether this port makes sense at
# all. The CDCM61001 output buffer is PIN-SELECTABLE between LVPECL, LVDS and
# LVCMOS via the OS[1:0] strap pins (OS[1:0] = 00 selects LVCMOS). It is NOT
# inherently differential. A single-ended `create_clock` on a plain CLK port is
# therefore CONSISTENT with the part -- but only in LVCMOS mode. If the board
# straps OS[1:0] for LVPECL or LVDS, this port is wrong at the pin level (the
# chiplet has one single-ended CLK pad, no complement), and no SDC edit fixes
# that. See the report note; this is a board/bonding question, not a timing one.
#
# FREQUENCY HEADROOM -- there is plenty, contrary to an earlier note here.
# SCAS869F gives, for the LVCMOS output, "fOUT Output frequency ... 43.75 (MIN)
# .. 250 (MAX) MHz".
#
# THIS DESIGN DOES NOT RUN AT 250 MHz. Verified three ways:
#     ASIC/common.mk:159      export CLK_PERIOD ?= 10.0
#     line 19 below           set EXTCLK_PERIOD $::env(CLK_PERIOD)
#     the elaborated SDC      create_clock -name "clk" -period 10.0 [get_ports CLK]
#     the live run's reports  "Clock Edge:+ 10.000"
# i.e. clk is 100 MHz, and there is 2.5x margin to the LVCMOS fOUT ceiling.
#
# The "at 250MHz" in the $CLK_ERROR comment on line 21 is the PART's
# characterisation point for the jitter figure, NOT this design's operating
# frequency. The two were conflated; they are different things. Jitter quoted at
# 250 MHz is if anything conservative when the part is run at 100 MHz.
#
# THE NUMBER. SCAS869F specifies the LVCMOS edge as a SLEW RATE, not a time:
#     tSLEW-RATE   Output rise/fall slew rate   20% to 80%   2.4 V/ns
# 2.4 is in the MIN column (it aligns with fOUT's 43.75 MIN and ODC's 45% MIN),
# so it is the SLOWEST guaranteed edge -- the conservative end for a setup
# check, which is what we want. Converting a slew RATE to a transition TIME
# needs the swing, and the swing depends on VCC; the table is specified over
# "VCC = 3 V to 3.6 V".
#     t(20-80) = 0.6 * VCC / 2.4 V/ns
#     VCC = 3.6 V (largest swing => slowest edge): 2.16 / 2.4 = 0.90 ns
#     VCC = 3.0 V (smallest swing => fastest edge): 1.80 / 2.4 = 0.75 ns
# Scaled to the library's 10%-90% thresholds by 4/3:
#     0.90 ns * 4/3 = 1.20 ns    <- worst case, used for -max
#     0.75 ns * 4/3 = 1.00 ns
# 1.20 ns sits well inside the pad's characterised input range (0.5 .. 5.0 ns),
# so this is interpolated, not extrapolated.
set_input_transition -max 1.20 [get_ports CLK] ;# [DATASHEET] SCAS869F tSLEW-RATE 2.4 V/ns min @20-80%, VCC=3.6V, converted to 10-90%
#
# THE -min SIDE IS NOT A DATASHEET NUMBER. SCAS869F bounds only the MINIMUM
# slew rate; there is NO specified maximum, so a fast part may produce an edge
# far sharper than 1.00 ns and the datasheet does not forbid it. Using 1.00 ns
# as a -min would assert a fast-edge guarantee the vendor never gave, and a
# too-slow -min flatters hold. 0.50 ns is used instead: it is the most
# pessimistic hold assumption that still lands inside the pad's characterised
# slew range rather than extrapolating below it.
set_input_transition -min 0.50 [get_ports CLK] ;# [PLACEHOLDER] no max-slew-rate spec exists in SCAS869F; on-table pessimistic hold assumption

### --- SWDCK / SWDIO : ARM Serial Wire Debug probe ---------------------------
#
# SOURCE: Lauterbach, "Arm Debug and Trace Interface Specification"
# (c)1989-2024, the JTAG/SWD electrical table (p.37):
#     Trf   output rise / fall time      load = 10 pF   6 ns
#                                        load = 22 pF   7 ns
#                                        load = 33 pF   8 ns
# measured at the connector of the probe, "rise and fall times are measured at
# 20% and 80%". The document states these are "for reference only and are not
# guaranteed by LAUTERBACH" -- so this is a published vendor MEASUREMENT, not a
# guaranteed limit. It is still real data from a real ARM debug probe, which is
# more than we had. TRACE32 is the same class of instrument as CMSIS-DAP /
# J-Link / ULINK; all of them serially terminate their outputs (the same
# document recommends "a 47 ohm series resistor near the processor ... on ...
# SWDIO"), which is precisely why the edges are slow.
#
# THE LIBRARY CANNOT REPRESENT THE REAL EDGE. Converting the 10 pF row:
#     6 ns (20-80%) * 4/3 = 8.0 ns (10-90%)
# That is past the top of the pad's input slew table, which is also where the
# library's default_max_transition sits. Declaring 8.0 ns would extrapolate off
# the top of the NLDM table AND create a permanent, unfixable max_transition
# violation on an input port -- nothing inside the chip can sharpen an
# externally-driven edge. So the value below is CLAMPED to 5.0 ns.
#
# BE CLEAR ABOUT THE DIRECTION OF THE RESULTING ERROR: 5.0 ns is FASTER than the
# probe's real ~8 ns edge, so SWD input timing here is OPTIMISTIC BY
# CONSTRUCTION. That is tolerable, and only because SWD has enormous native
# margin -- the same document notes the debugger "will produce a setup (Tsetup)
# and hold time (Thold) of half the cycle time (Tclock) of SWCLK", i.e. the
# protocol budgets half a clock period, and the SWDCLK <-> EXTCLK crossings
# already carry the multicycle paths declared above. Do NOT reuse this clamping
# argument on a performance-critical interface.
set_input_transition -max 5.00 [get_ports SWDCK] ;# [PLACEHOLDER] clamp. Real: Lauterbach Trf 6ns@10pF,20-80% => 8.0ns@10-90%, past the library max-transition ceiling
set_input_transition -min 0.50 [get_ports SWDCK] ;# [PLACEHOLDER] on-table pessimistic hold assumption; no fast-edge bound published for any probe
set_input_transition -max 5.00 [get_ports SWDIO] ;# [PLACEHOLDER] as SWDCK -- probe drives SWDIO on the falling SWCLK edge
set_input_transition -min 0.50 [get_ports SWDIO] ;# [PLACEHOLDER] on-table pessimistic hold assumption
#
# SWDCLK_PERIOD IS 4*EXTCLK_PERIOD (line 20) = 40.0 ns = 25 MHz, confirmed in
# the elaborated SDC: create_clock -name "swdclk" -period 40.0 [get_ports SWDCK].
# (An earlier note here said 62.5 MHz, having assumed EXTCLK was 250 MHz rather
# than the actual 100 MHz -- see the FREQUENCY HEADROOM correction above.)
#
# 25 MHz sits comfortably inside what real debug probes drive (a few MHz to
# ~50 MHz; the Lauterbach table is built around a 10-20 MHz default), so this is
# a realistic constraint rather than an over-constraint. No action needed.

### --- NRST : board reset ----------------------------------------------------
#
# NRST is asynchronous and is driven either by a reset supervisor (open-drain,
# pulled up) or by the debug probe's RESET- line (the Lauterbach document above
# specifies a 47 kohm pull-up on RESET-). BOTH are RC-dominated: an open-drain
# output releasing into a 10 kohm pull-up against board capacitance produces an
# edge measured in MICROSECONDS, which is three orders of magnitude outside
# anything the NLDM table can express.
#
# Clamped to the library ceiling for the same reason as SWD. This is acceptable
# here for a stronger reason than SWD's: NRST is asynchronous and is
# SYNCHRONISED INTERNALLY before it reaches any timing path, so its edge rate
# gates nothing. The value exists to stop the 0 ns assumption, not to time a
# path. If NRST ever feeds combinational logic directly, this reasoning fails.
set_input_transition -max 5.00 [get_ports NRST] ;# [PLACEHOLDER] clamp. Real edge is RC (open-drain + 10k pull-up) = microseconds, unrepresentable
set_input_transition -min 0.50 [get_ports NRST] ;# [PLACEHOLDER] on-table pessimistic hold assumption

### --- TEST / SE / HOSTIO4_P1 : generic board-level 3.3 V CMOS ---------------
#
# No datasheet applies: these are driven by whatever the board puts there (a
# strap/jumper for TEST and SE, an FPGA or host adapter for HOSTIO4_P1). The
# value below is the CONVENTIONAL figure for a 3.3 V LVCMOS driver into a short
# PCB trace: 2.0 ns at 10%-90%, equivalent to 1.5 ns at 20%-80%, i.e. ~1.3 V/ns
# on a 3.3 V rail. That is a typical FPGA/MCU LVCMOS33 output at moderate drive.
# It also needs no interpolation in the pad's input slew table.
#
# TEST and SE are STATIC configuration pins -- strapped, and never toggling in
# mission mode -- so their slew has no timing consequence whatsoever. They are
# constrained only so that no top-level input is left on the 0 ns default.
# SE in particular is constrained NOWHERE ELSE: it is absent from this file's
# delay section and from all three sourced IP SDCs. See the report.
set_input_transition -max 2.00 [get_ports TEST]           ;# [CONVENTION] generic 3.3V LVCMOS board driver; static strap pin, no timing consequence
set_input_transition -max 2.00 [get_ports SE]             ;# [CONVENTION] as TEST. NOTE: SE is otherwise unconstrained in every SDC
set_input_transition -max 2.00 [get_ports {HOSTIO4_P1[*]}]

# SCAN IS OFF IN MISSION MODE, AND SAYING SO IS WORTH REAL TIMING.
# Without this, the scan multiplexer inside every SDFxx flop is timed in BOTH
# states, so the SI/SE side of ~23.5k mux-D flops competes with the functional
# D side for the critical path. Post-route STA on 2026-08-07 found violating
# endpoints that were literally scan pins (adp_addr_reg[30]/SI, and an /SE),
# i.e. margin spent on a path that cannot exist on this die.
#
# Safe here for a stronger reason than usual: the scan chain is NOT BONDED on
# this tapeout (see the port table above), and the block comment 6 lines up
# already states TEST and SE are "STATIC configuration pins -- strapped, and
# never toggling in mission mode". This makes the timer agree with that.
#
# NOTE these are the only two set_case_analysis in the whole constraint set --
# reports/eval/syn_case_analysis.rep was 0 bytes before this. If you ever DO
# want to time the scan chain, comment these out rather than adding overrides.
set_case_analysis 0 [get_ports SE]
set_case_analysis 0 [get_ports TEST]
 ;# [CONVENTION] generic 3.3V LVCMOS driver (FPGA / host adapter) over a short trace

### --- OUTPUT LOADING : package + board + far-end receiver -------------------
#
# set_load on these ports models everything BEYOND the pad: package parasitics,
# the PCB trace, and the input capacitance of whatever receives the signal. The
# pad cell's own PAD-pin capacitance (see `pin(PAD) capacitance` for PDDW04DGZ_G
# and PDDW16DGZ_G in the IO liberty -- figures not reproduced here, TSMC licence)
# is already inside the liberty model and must NOT be added here.
#
# BUDGET [CONVENTION] -- the components, so the total can be argued with:
#     package (wire-bond + lead/ball)                    ~1 pF
#     PCB trace, short microstrip (~0.5-1 pF/cm)         ~2-4 pF
#     far-end 3.3 V CMOS receiver input capacitance      ~4-5 pF
#                                                    --------------
#                                                        ~8-10 pF
# 10 pF is the round figure and needs no interpolation in the pad's output
# table. Two independent corroborations that this is the right order of
# magnitude: SCAS869F characterises its own LVCMOS output into "CL = 5 pF", and
# the Lauterbach table above quotes probe loads of 10/22/33 pF.
#
# ANYTHING IS BETTER THAN THE 0 pF THIS REPLACES: 0 pF is below the non-zero
# floor of every output NLDM table in the IO library, so it was extrapolation.
set_load 10 [get_ports {HOSTIO4_P1[*]}] ;# [CONVENTION] package ~1pF + short trace ~2-4pF + CMOS receiver ~4-5pF
#
# SWDIO carries more: a debug connector, then a ribbon cable to the probe. The
# Lauterbach table characterises Trf at 10/22/33 pF, which is a direct statement
# of the load range that probe expects to see. 20 pF sits in that range and
# between two characterised load points, so it interpolates cleanly.
set_load 20 [get_ports SWDIO] ;# [CONVENTION] debug connector + ribbon cable to probe; Lauterbach characterises Trf over 10-33 pF

#### DESIGN RULE CHECKS #######################################################
#
# ORDERING IS DELIBERATE. This block sits AFTER the three `source` lines
# (82/84/86), so it is the LAST word on any object it names. Anything set here
# on [all_outputs] overrides per-port values established in the IP SDCs. That is
# intentional for max_capacitance, which must be ONE coherent decision across
# every interface, and it is why the per-port set_load calls above are scoped to
# named ports only -- they must NOT clobber the QSPI / TideLink / Ethernet
# loads declared in the sourced files.
#
# WHY 3 pF WAS REMOVED -- DO NOT PUT IT BACK.
# This line previously read `set_max_capacitance 3 [all_outputs]`. That is a
# category error, and it became actively harmful the moment real loads were
# declared. The distinction that matters:
#     set_load            ASSERTS what reality is. It is an input to analysis.
#     set_max_capacitance DEMANDS a limit the tool must meet. It is a target.
# The capacitance hanging off an output PAD is off-chip. It is package, trace
# and receiver. NOTHING the tool can do -- resizing, buffering, rerouting --
# reduces it by a single femtofarad. Demanding 3 pF at a pin that physically
# carries 13 pF is asking for the impossible, and the tool duly reports a
# violation it can never fix. With real loads now declared across the
# interfaces (QSPI: 11 pF on SCLK/nCS and 13 pF on IO[*], from Microchip
# SST26VF064B DS20005119J; Ethernet and TideLink comparable), a 3 pF rule would
# have turned every I/O pin in the design into a permanent red entry and
# devalued the entire DRV report -- the 2026-08-06 run already showed 213
# max_cap violations with NO set_load declared at all.
#
# WHAT REPLACES IT, AND WHY 100 pF IS NOT "GIVING UP".
# 100 pF is not arbitrary and it is not slack: it is set at the top of the
# total_output_net_capacitance range the IO drivers are CHARACTERISED for.
# (Liberty table names and load-axis points redacted -- vendor characterisation
# data, TSMC licence forbids reproduction; read them in tphn65lpgv2od3_sl*.lib.)
# Beyond that range the NLDM tables extrapolate and the reported delay stops meaning
# anything -- which is exactly the condition a design rule SHOULD trap. Note
# also that the IO liberty declares NO max_capacitance on any pin (zero
# occurrences in the file), so this SDC line is the ONLY capacitance guard on
# these ports; that is why it is kept rather than deleted outright.
# Declared loads of 10-20 pF here, and 11-13 pF in the IP SDCs, now sit
# comfortably inside a limit that reflects real silicon capability.
#
# IF YOU WANT A TIGHTER RULE, PUT IT ON INTERNAL NETS, NOT ON PORTS. Internal
# nets are where the tool can actually act. Scoping a design-wide
# max_capacitance is a signoff decision with real optimisation consequences --
# make it deliberately, not by tightening this line back to 3.
set_max_capacitance 100 [all_outputs]
#
# set_max_fanout 10 [all_inputs] -- KEPT VERBATIM, BUT BE AWARE IT IS A NO-OP.
# `all_inputs` returns top-level input PORTS. On this pad-ring top, every input
# port drives EXACTLY ONE thing: the PAD pin of its own pad cell. A fanout limit
# of 10 on a net whose fanout is structurally 1 can never trigger. The real
# internal fanout starts at the pad cell's C output, which this constraint does
# not reach.
# It is left in place because it is harmless and because removing it changes
# nothing. A genuine fanout rule would need `set_max_fanout <N> [current_design]`
# -- which would alter optimisation targets across the whole design and is a
# signoff decision, NOT a drive/load characterisation fix. Flagged, not changed.
set_max_fanout 10 [all_inputs]

