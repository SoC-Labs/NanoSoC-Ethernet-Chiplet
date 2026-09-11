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

# ── THE TIMING BUDGET IS DERIVED FROM THE PERIOD, NOT TYPED NEXT TO IT ──────
#
# ADDED 2026-08-31. Everything below this comment used to be a literal. The
# period was already a knob -- $::env(CLK_PERIOD), which ASIC/eth-chiplet/
# design.mk now derives from CLK_FREQ_MHZ -- but the numbers that SHARE the
# period with the logic were not, so `make syn CLK_PERIOD=8.0` retargeted the
# clock and left the margin taken out of it at its 10 ns size. At 8 ns that is
# not a 25% harder design, it is a 25% harder design carrying a margin sized
# for a 25% easier one.
#
# THE DEFAULTS REPRODUCE THE OLD LITERALS EXACTLY, BY CONSTRUCTION AND BY
# ARITHMETIC -- at CLK_PERIOD=10.0:
#     CLK_ERROR                0.035 x 10.0 -> 0.35    (was 0.35)
#     INTER_CLOCK_UNCERTAINTY  0.010 x 10.0 -> 0.1     (was 0.1)
#     IO_PORT_DELAY            0.010 x 10.0 -> 0.1     (was 0.1)
#     CLK_HOLD_ERROR                          0.05     (was 0.05, NOT scaled)
# `format %.4g` is not decoration: 0.035*10.0 is 0.35000000000000003 in IEEE
# double and Tcl prints every one of those digits. Four significant figures
# gives back "0.35" at the default and still resolves 0.2632 at 133 MHz.
#
# WHICH TERMS SCALE, AND WHY EACH ONE DOES OR DOES NOT. This is a physics
# question, not a formatting one, and the file already contains the answer for
# the biggest term -- see the block below, which establishes that the dominant
# component of CLK_ERROR is NOT jitter (~0.012 ns) but the source oscillator's
# 45/55% OUTPUT DUTY CYCLE, and that duty cycle is a PERCENTAGE:
#     at 250 MHz (4 ns)   45%/55% -> +/-0.2 ns
#     at 100 MHz (10 ns)  45%/55% -> +/-0.5 ns
# A term that is a percentage of the period must scale with the period. That is
# the whole argument for CLK_UNC_SETUP_FRAC, and it is the file's own.
#
#   CLK_UNC_SETUP_FRAC   SCALES.   Duty-cycle distortion dominates it.
#   CLK_UNC_HOLD_NS      ABSOLUTE. The block below argues hold uncertainty is
#                        residual, non-common-mode jitter -- ~0.012 ns of real
#                        random jitter with 4x headroom at 0.05. Random jitter
#                        is an absolute time, so scaling it with the period
#                        would make a FASTER clock ask for LESS hold margin,
#                        which is backwards. Left absolute, deliberately.
#   INTER_CLOCK_UNC_FRAC SCALES.   swdclk is 4 x EXTCLK by construction (line
#                        above), so both sides of that crossing move together.
#   IO_PORT_DELAY_FRAC   SCALES.   A port delay budget is a share of the cycle
#                        given away to the outside world. See DELAY DEFINITION.
#
# EVERY ONE IS OVERRIDABLE FROM THE ENVIRONMENT with an absolute value, so a
# margin that turns out not to scale can be pinned without editing this file
# and without giving up the frequency knob:
#     make syn CLK_FREQ_MHZ=125 CLK_ERROR_NS=0.35
#
# NOT CHANGED, AND WORTH KNOWING: ASIC/common.mk:263 exports CLK_UNCERTAINTY
# ?= 0.35. NOTHING READS IT -- grep across every .sdc, .tcl and .mk in ASIC/
# returns that one definition and no consumer. It is not wired up here either,
# because a variable whose default is a 10 ns number would silently defeat the
# scaling the moment anyone assumed it was live. Use CLK_ERROR_NS above.
proc sdc_num_env {name default} {
    if {[info exists ::env($name)]} {
        set v [string trim $::env($name)]
        if {[string is double -strict $v]} { return $v }
        if {$v ne ""} {
            puts "**WARN: constraints.sdc: $name='$v' is not a number - using $default"
        }
    }
    return $default
}
set CLK_UNC_SETUP_FRAC   [sdc_num_env CLK_UNC_SETUP_FRAC   0.035]
set INTER_CLOCK_UNC_FRAC [sdc_num_env INTER_CLOCK_UNC_FRAC 0.010]
set IO_PORT_DELAY_FRAC   [sdc_num_env IO_PORT_DELAY_FRAC   0.010]

set CLK_ERROR [sdc_num_env CLK_ERROR_NS \
                   [format %.4g [expr {$CLK_UNC_SETUP_FRAC * $EXTCLK_PERIOD}]]]
#Error calculated from worst case characteristics of CDCM61001 low-jitter oscillator chip at 250MHz
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
# CORRECTED 2026-08-29. The paragraph this replaces computed the duty term at
# 250 MHz -- the OSCILLATOR's characterisation point -- and this design runs at
# 100 MHz. See the block near line 524, which has said so all along; the two
# passages contradicted each other and the 250 MHz figure was the one that got
# quoted onward (it also reached tidelink_link_clk_div.sv's safety property 2).
#
# ODC IS A PERCENTAGE, so it scales with the period and the correction makes the
# term BIGGER, not smaller:
#     at 250 MHz (4 ns)   45%/55% -> falling edge 1.8 vs 2.0 ns  = +/-0.2 ns
#     at 100 MHz (10 ns)  45%/55% -> falling edge 4.5 vs 5.0 ns  = +/-0.5 ns
# +/-0.5 ns is 1.4x the ENTIRE 0.35 ns budget it was supposed to be the main
# component of. So 0.35 ns is NOT "0.2 duty + 0.01 jitter + margin". It is a
# margin smaller than the worst-case duty-cycle distortion of the source part,
# and it is defensible only because that distortion cannot reach most of this
# design -- measured 2026-08-29 over the worst 2000 endpoints: 1980 are
# rising-to-rising and structurally immune, 20 are captured on the falling edge
# and their worst slack is +0.439 ns.
#
# DO NOT cite the old +/-0.2 ns to argue this number down. Whoever does that
# must also pay the negedge side its real +/-0.5 ns.
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
set CLK_HOLD_ERROR [sdc_num_env CLK_HOLD_ERROR_NS 0.05]
set INTER_CLOCK_UNCERTAINTY \
    [sdc_num_env INTER_CLOCK_UNCERTAINTY_NS \
        [format %.4g [expr {$INTER_CLOCK_UNC_FRAC * $EXTCLK_PERIOD}]]]

# One line, printed by every Genus and Innovus session that reads this file, so
# that a run at another frequency says so in its own log instead of being
# reconstructed from a make variable afterwards.
puts "constraints.sdc: CLK_PERIOD=$EXTCLK_PERIOD ns\
      (SWDCLK $SWDCLK_PERIOD) uncertainty setup=$CLK_ERROR hold=$CLK_HOLD_ERROR\
      inter=$INTER_CLOCK_UNCERTAINTY"

create_clock -name "$EXTCLK" -period "$EXTCLK_PERIOD" -waveform "0 [expr $EXTCLK_PERIOD/2]" [get_ports CLK]
create_clock -name "$SWDCLK" -period "$SWDCLK_PERIOD" -waveform "0 [expr $SWDCLK_PERIOD/2]" [get_ports SWDCK]

#### CLOCK TRANSITION ########################################################
#
# THERE WAS NO set_clock_transition IN THIS DESIGN UNTIL 2026-08-29. The
# consequence is not "a slightly idealised clock edge" -- it is that synthesis
# read every sequential constraint table OFF THE BOTTOM OF ITS CLOCK AXIS.
# Innovus prints the fallback it uses, on every single database load:
#       "Set Default Input Pin Transition as 0.1 ps."
# 0.1 ps is 0.0001 ns. The rf_16k setup table's clock-slew axis begins at
# 0.035 ns (rf_16k_ss_1p08v_1p08v_125c.lib:2279), so the lookup sat 350x below
# the first characterised point and the tool had nothing to do but clamp.
#
# WHICH AXIS IS WHICH. This is easy to get backwards, so it is written down.
# rf_16k_ss_1p08v_1p08v_125c.lib:211-216 declares the constraint template:
#       variable_1 : related_pin_transition       <- the CLOCK slew  (ROWS)
#       variable_2 : constrained_pin_transition   <- the DATA  slew  (COLUMNS)
# THIS constraint sets variable_1. set_max_transition, at the foot of this
# file, is what bounds variable_2. Two separate defects; both were open.
#
# THE VALUE IS MEASURED, NOT SCALED FROM THE PERIOD. Census of every clk-domain
# clock-tree sink pin on the routed rc4 database (61,174 pins, read out of
# build/rc4-20260829/db_rc4 with Innovus on 2026-08-29):
#       min 0.028   p50 0.120   p90 0.131   p99 0.138   max 0.153
# and the one sink that actually matters -- the rf_16k CLK pin terminating this
# design's critical setup path -- measures 0.116 on the nose. 0.120 is the
# median of what CTS genuinely delivers, and it is BELOW p90, so it does not
# hand setup an edge faster than 90% of the design really sees.
# For swdclk the same census over the bscan sinks it reaches (122 pins) gives
# p50 0.108 / max 0.125, hence the slightly faster figure on the second line.
#
# WHAT THIS BUYS, AND WHAT IT DOES NOT -- do not oversell it.
# In the rf_16k table a LARGER clock slew yields a SMALLER setup requirement
# and a LARGER hold requirement. Moving the declared edge 0.0001 -> 0.120 is
# therefore worth, at the A[11] operating point:
#       setup requirement   -22 ps   (pessimism synthesis was paying for)
#       hold  requirement   +22 ps   (optimism synthesis was banking on)
# This is an ACCURACY fix, NOT a setup win. Its more valuable half is the hold
# half, because this design has failed hold at every corner -- expect synthesis
# to start seeing hold work earlier. That is the point, not a regression.
#
# SCOPE: set_clock_transition applies only while the clock is IDEAL. After the
# flow calls set_propagated_clock (post-CTS) it is ignored and the real edge is
# used. So this changes SYNTHESIS and nothing downstream -- which is precisely
# where the 0.1 ps was being consumed.
#
# DO NOT COPY THE SIBLING PROJECT'S FORM. nanosoc-multicore-system's
# constraints_setup.sdc:13 sets clock_max_transition_factor to 0.273 and
# constraints.sdc:29,32 multiply it by the PERIOD. At this design's 10 ns that
# is 2.73 ns for clk and 10.92 ns for swdclk -- an edge occupying 27% of its
# own period. Slew is a property of the driver and its load. It does not scale
# with frequency.
set_clock_transition 0.120 [get_clocks $EXTCLK]  ;# [MEASURED] p50 of 61,174 clk sinks on rc4; rf_16k CLK sink = 0.116
set_clock_transition 0.110 [get_clocks $SWDCLK]  ;# [MEASURED] p50 0.108 / max 0.125 over the 122 bscan sinks on rc4
#
# THESE ARE 2 OF 26. The other 24 clocks are created in the IP SDCs sourced
# further down, so they CANNOT be constrained here -- their set_clock_transition
# lines are in "CLOCK TRANSITION, PART 2" immediately after the `source` block.
# Twenty-two of them now carry a measured value; D2D_TX_CLK_0 and QSPI_SCLK_o
# deliberately do not, because they have zero sink pins. An independent census
# on the same rc4 database reproduces the 0.120 above exactly and swdclk's
# max 0.125 exactly, which is the calibration for the other twenty-two.

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
## APPLIED 2026-08-17. Acceptance, all three, and the third is the one that
## matters: the expansion in outputs/${block}_syn.sdc drops 548 -> 480 entries (34
## distinct PG objects, each appearing twice because one wildcard feeds both -from
## and -to); TCLCMD-917 goes to zero in the Innovus log; and setup/hold are
## UNCHANGED. PG pins carry no timing arcs, so if timing moves at all, the premise
## that this exception was inert on them was wrong and this change must come back
## out rather than be argued with.
##
## THE DEFECT WAS LIVE, NOT LATENT, and an earlier note here said otherwise.
## Measured per stage in a routed build's own logs: 68-70 occurrences in each
## PLACE log, 0 at CTS, 0 at route. The "masked by pad deletion" framing described
## how it was HIDDEN historically, and was wrong about the present -- with the pad
## ring restored it fires on every placement.
set_multicycle_path 2 \
  -from [get_pins {uPAD*/I uPAD*/C uPAD*/PAD uPAD*/OEN uPAD*/REN}] \
  -to   [get_pins {uPAD*/I uPAD*/C uPAD*/PAD uPAD*/OEN uPAD*/REN}]

### IP Constraints
source ../inputs/qspi_constraints.sdc

source ../inputs/tidelink_constraints.sdc

source ../inputs/ethernet_constraints.sdc

source ../inputs/i2c_constraints.sdc
source ../inputs/bscan_constraints.sdc

#### CLOCK TRANSITION, PART 2 -- THE OTHER 24 CLOCKS ##########################
#
# MUST STAY BELOW THE `source` LINES ABOVE. 22 of these clocks are created in
# the IP SDCs, so a set_clock_transition placed with the other two (near line
# 130) would name a clock that does not exist yet and error.
#
# WHY. Read the long block near line 86 first; this is the same defect on the
# rest of the design. Until 2026-08-29 nothing in this file declared a clock
# slew, so Innovus applied its own fallback -- it prints it on every database
# load, including today's:
#       "Set Default Input Pin Transition as 0.1 ps."
# 0.0001 ns, against an rf_16k constraint table whose related_pin_transition
# axis begins at 0.035 ns. That fix was then applied to TWO clocks. This block
# is the other twenty-four.
#
# SCOPE, unchanged and worth restating: set_clock_transition applies only while
# the clock is IDEAL, i.e. Genus synthesis and pre-CTS placement. There is no
# set_propagated_clock anywhere in this flow -- ccopt makes the tree propagated
# itself -- so after CTS these values are ignored and the real edge is used.
# That bounds the benefit AND the risk.
#
# HOW THE NUMBERS WERE DERIVED. Not scaled from a period, not copied from clk.
# Measured 2026-08-29 on the rc4 routed database (a COPY of build/rc4-20260829/
# db_rc4 taken into the rc5 worktree; nothing in the shipping tree was touched):
#   1. report_clock_timing -type latency -clock <c> -view default_analysis_view_setup
#      for each of the 26 clocks Innovus reports, to get that clock's sink pins;
#   2. get_db pin:<p> .slew_max_rise on every one of them -- with two active
#      views that is the worst-case (setup) corner, which is the corner the
#      0.120 for clk was taken at;
#   3. p50 of the resulting distribution. p50, not max: a LARGER declared slew
#      makes setup look better and hold look worse, so the median is the
#      unbiased choice and it is the rule the first two lines already followed.
#
# THE METHOD IS CALIBRATED, WHICH IS WHY THESE NUMBERS CAN BE TRUSTED. Run
# blind over clk it returns p50 = 0.120 -- the value already in this file to
# three decimal places, measured by a different session over a different
# population (37,568 sink pins here vs the 61,174 quoted at line ~110). Over
# swdclk it returns max = 0.125, again the value already in this file exactly.
#
# swdclk IS DELIBERATELY LEFT AT 0.110. This census puts its p50 at 0.116 over
# 372 sinks; the existing line used 0.108 over the 122 bscan sinks. The maxima
# agree exactly (0.125), so this is a population difference, not a
# disagreement: 0.110 was measured over the sinks swdclk actually times.
# Re-deriving it here would be churn over 6 ps with no argument behind it.
#
# TWO CLOCKS GET NOTHING, AND THAT IS THE MEASUREMENT TOO:
#   D2D_TX_CLK_0   generated AT the TL_CLK_TX port
#   QSPI_SCLK_o    generated AT the QSPI_SCLK port
# Both report ZERO sink pins. There is no sequential element for a clock slew
# to index a constraint table for, so a value here would constrain nothing
# while making the file read as though all 26 were covered. Do not "complete
# the set" by adding them.
#
# WHERE THE MONEY IS. Every hold report in the build tree was grouped by clock.
# Only three clock groups have ever owned a hold violation: clk, rmii_ref_clk
# and D2D_RX_CLK_0. On av_ltfix_libset_hold in holdfix-20260828/sta_final,
# clk's worst hold was -0.001 while rmii_ref_clk's was -0.042 on RMII_TXD[0],
# RMII_TXD[1] and RMII_TX_EN -- the domain with NO slew declaration owned a
# violation 42x the constrained domain's. rmii_ref_clk and its two /2 children
# mii_rx_clk / mii_tx_clk are the lines in this block that matter most.
#
# DO NOT read a p50 as a target. These describe what CTS delivered on rc4; if a
# future run's tree changes materially, re-measure. The census is reproducible:
# ASIC/genus-innovus/work/rc5_clkslew/{census.tcl,census2.tcl} and its output
# out/clock_slew_census.csv (gitignored, like every run artefact).

# --- Ethernet.  rmii_ref_clk owns this design's worst measured hold. ---------
set_clock_transition 0.117 [get_clocks rmii_ref_clk]        ;# [MEASURED] p50 of 37 sinks (min 0.090 / p90 0.118 / max 0.153)
set_clock_transition 0.124 [get_clocks mii_rx_clk]          ;# [MEASURED] p50 of 2,866 sinks (min 0.079 / p90 0.133 / max 0.138)
set_clock_transition 0.120 [get_clocks mii_tx_clk]          ;# [MEASURED] p50 of 2,406 sinks (min 0.076 / p90 0.126 / max 0.132)

# --- QSPI.  QSPI_SCLK_o has no sinks; see the note above. -------------------
set_clock_transition 0.118 [get_clocks QSPI_SCLK]           ;# [MEASURED] p50 of 432 sinks (min 0.052 / p90 0.127 / max 0.128)

# --- TideLink D2D.  D2D_TX_CLK_0 has no sinks; see the note above. ----------
set_clock_transition 0.115 [get_clocks D2D_RX_CLK_0]        ;# [MEASURED] p50 of 528 sinks (min 0.041 / p90 0.126 / max 0.134)
set_clock_transition 0.113 [get_clocks D2D_TX_WORD_CLK_0]   ;# [MEASURED] p50 of 1,481 sinks (min 0.075 / p90 0.130 / max 0.133)

# Lane 0 carries the deskew memory, which is why its sink count is 16x the
# others'. Per-lane values, not one number for all eight: they were measured
# per lane and they differ.
set_clock_transition 0.118 [get_clocks D2D_RX_WORD_CLK_0]   ;# [MEASURED] p50 of 8,851 sinks (min 0.075 / p90 0.131 / max 0.138)
set_clock_transition 0.123 [get_clocks D2D_RX_WORD_CLK_1]   ;# [MEASURED] p50 of 551 sinks (min 0.080 / p90 0.128 / max 0.133)
set_clock_transition 0.122 [get_clocks D2D_RX_WORD_CLK_2]   ;# [MEASURED] p50 of 551 sinks (min 0.086 / p90 0.129 / max 0.131)
set_clock_transition 0.124 [get_clocks D2D_RX_WORD_CLK_3]   ;# [MEASURED] p50 of 551 sinks (min 0.081 / p90 0.131 / max 0.133)
set_clock_transition 0.124 [get_clocks D2D_RX_WORD_CLK_4]   ;# [MEASURED] p50 of 551 sinks (min 0.078 / p90 0.131 / max 0.134)
set_clock_transition 0.122 [get_clocks D2D_RX_WORD_CLK_5]   ;# [MEASURED] p50 of 551 sinks (min 0.079 / p90 0.128 / max 0.133)
set_clock_transition 0.122 [get_clocks D2D_RX_WORD_CLK_6]   ;# [MEASURED] p50 of 551 sinks (min 0.075 / p90 0.128 / max 0.131)
set_clock_transition 0.126 [get_clocks D2D_RX_WORD_CLK_7]   ;# [MEASURED] p50 of 551 sinks (min 0.078 / p90 0.132 / max 0.134)

# The WORDN clocks are the negedge phase of the same eight nets: 16 sinks each,
# all at one value per lane, which is why min == p50 == max below. Small, but
# 0.098 is 980x the 0.0001 ns they read at today.
set_clock_transition 0.098 [get_clocks D2D_RX_WORDN_CLK_0]  ;# [MEASURED] 16 sinks, all 0.098
set_clock_transition 0.103 [get_clocks D2D_RX_WORDN_CLK_1]  ;# [MEASURED] 16 sinks, all 0.103
set_clock_transition 0.116 [get_clocks D2D_RX_WORDN_CLK_2]  ;# [MEASURED] 16 sinks, all 0.116
set_clock_transition 0.099 [get_clocks D2D_RX_WORDN_CLK_3]  ;# [MEASURED] 16 sinks, all 0.099
set_clock_transition 0.098 [get_clocks D2D_RX_WORDN_CLK_4]  ;# [MEASURED] 16 sinks, all 0.098
set_clock_transition 0.103 [get_clocks D2D_RX_WORDN_CLK_5]  ;# [MEASURED] 16 sinks, all 0.103
set_clock_transition 0.106 [get_clocks D2D_RX_WORDN_CLK_6]  ;# [MEASURED] 16 sinks, all 0.106
set_clock_transition 0.104 [get_clocks D2D_RX_WORDN_CLK_7]  ;# [MEASURED] 16 sinks, all 0.104


#### DELAY DEFINITION

# 0.1 ns AT 10 ns IS 1% OF THE CYCLE, and that is now how it is written --
# $IO_PORT_DELAY is [format %.4g] of IO_PORT_DELAY_FRAC x the period, 0.010 x
# 10.0 = 0.1, the same literal these three lines carried before. See the
# derivation block at the top for why a port delay budget scales with the
# period and what to set to pin it.
set IO_PORT_DELAY [sdc_num_env IO_PORT_DELAY_NS \
                       [format %.4g [expr {$IO_PORT_DELAY_FRAC * $EXTCLK_PERIOD}]]]
set_input_delay -clock [get_clocks $EXTCLK] -add_delay $IO_PORT_DELAY [get_ports NRST]
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
set_input_delay -clock [get_clocks $EXTCLK] -add_delay $IO_PORT_DELAY [get_ports HOSTIO4_P1]
set_input_delay -clock [get_clocks $SWDCLK] -add_delay $IO_PORT_DELAY [get_ports SWDIO]

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
#   user_ref_clk + pad_clk_tx     -> D2D_TX_CLK_0 alone. *** SEE [C2] BELOW ***
#                                    the reasoning that used to sit here ran the
#                                    alias BACKWARDS and concluded the cut is
#                                    REAL. It is the alias that makes the cut
#                                    FICTION. Do not restore that sentence.
#   pad_clk_rx                    -> D2D_RX_CLK_0
#   rmii_ref_clk                  -> stands alone, dragging its two divide-by-2
#                                    MII clocks with it.
#
#############################################################################
# [C2] OPEN DECISION, FOR THE OWNER — THE TRANSMIT GROUP CUTS A BOUNDARY THAT
#      IS SYNCHRONOUS. NO CONSTRAINT IS CHANGED BY THIS BLOCK. Recorded
#      2026-08-17 because it needs a pad-budget call, not an SDC edit.
#############################################################################
#
# THE FINDING. D2D_TX_CLK_0 and D2D_TX_WORD_CLK_0..7 are grouped -asynchronous
# against $EXTCLK below. They are not asynchronous to it. They are generated
# from it, 1:1, on the same net, and the tool says so.
#
# EVIDENCE 1 — THE TOOL'S OWN RESOLUTION. From the shipped run:
#     Using master clock 'clk' for generated clock 'D2D_TX_CLK_0'
#     Using master clock 'clk' for generated clock 'D2D_TX_WORD_CLK_0'   ... _7
#   (build/full-20260814/logs/pnr_qor_after_opt_design_post_cts.rep:21-34)
# Every clock in the -asynchronous TX group resolves its master to `clk`.
#
# EVIDENCE 2 — THE RTL CHAIN, and note there is no PLL and no divider anywhere
# on it. It is assigns and one scan mux:
#   ASIC/tech_wrappers/tsmc65/nanosoc_eth_chiplet_pads.v:137,266
#                                 rtc_clk / user_ref_clk aliased onto the
#                                 sys_fclk pad -> user_ref_clk IS the CLK pad
#   tidelink_top.sv:2483          .user_hsclk (user_ref_clk)
#   axi_chiplet_controller.sv:6160 .user_hsclk (user_hsclk)
#   Wlink.v:2105                  phy_user_hsclk = user_hsclk
#   WlinkGPIOPHY_v2.v:357         gpio_io_hsclk  = user_hsclk
#   WavD2DGpio_v2.v:2088          hsclk_scan_mux_io_i_a = io_hsclk
#                                 -> the io_clk of all 8 TX lanes, hence
#                                    pad_clk_tx (gated) and the /16 word clocks
#
# EVIDENCE 3 — THE CONTRAST WITH RECEIVE, which is the check that this is a real
# asymmetry and not a misreading. D2D_RX_CLK_0 is a create_clock on a PAD
# (TL_CLK_RX): an off-die clock from the peer die, mesochronous at best, and its
# word clocks correctly resolve master 'D2D_RX_CLK_0'. The RX group is right.
# Only the TX group asserts asynchrony against a clock it is generated from.
#
# WHAT THE CUT IS ACTUALLY HIDING. Everything between the system clock and the
# TX word domain: the a2l FC-replay write sides and their enable_link_clk_demet,
# lltx, txpstate, txrouter and the sp2wl TX FIFO — the same blocks censused in
# tidelink_constraints.sdc's TX word-clock block. Roughly 2k flops' worth of
# boundary, currently false-pathed by group membership rather than by any
# statement about those paths.
#
# WHY THIS IS A DECISION AND NOT A BUG FIX. Those crossings DO carry RTL
# synchronisers (the demet stages are right there in the names). Merging the
# groups would newly time paths whose RTL treats them as CDC, which is honest
# but not free. Conversely, leaving the group is defensible ONLY as
# "deliberately not timed, because the RTL synchronises it" — which is not what
# `-asynchronous` says. Either way the file should say the true thing.
#
# THE TWO OPTIONS, BOTH DEFENSIBLE:
#
#   OPTION A — MERGE D2D_TX_* INTO THE $EXTCLK GROUP.
#     Deletes the TX group and adds its clocks to the system group, so the
#     boundary is timed as the synchronous crossing it physically is.
#     COST: ~2k TX-word flops newly timed against clk across a /16 ratio.
#     EXPECT NEW VIOLATIONS ON THE FIRST RUN AND EXPECT THEM TO BE REAL — the
#     same lesson as the 16,653-flop RX block. The demet crossings then want
#     narrow, NAMED false paths (set_false_path -to the first demet stage),
#     not a blanket group. No pad, no board, no silicon change.
#
#   OPTION B — BOND user_ref_clk TO ITS OWN PAD.
#     Removes the alias, so the Wlink reference stops being `clk` and the
#     existing -asynchronous group becomes TRUE AS WRITTEN, with no SDC edit at
#     all. It also restores the peer-independent link reference the Wlink was
#     designed around.
#     COST: one more bonded clock pad out of the ring's budget, plus a board
#     clock source for it. THAT IS THE DECISION THE OWNER HAS NOT MADE, and it
#     is why nothing here is changed.
#
# NOTE FOR WHOEVER TAKES OPTION B: the TX word clocks' -source in
# tidelink_constraints.sdc was deliberately anchored at $WL/user_hsclk rather
# than [get_ports CLK] so that it stays correct under either option. Check
# D2D_TX_CLK_0's own -source and this group at the same time.
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
set _tx_grp {D2D_TX_WORD_CLK_0}
foreach n {0 1 2 3 4 5 6 7} {
    lappend _rx_grp "D2D_RX_WORD_CLK_$n"
    lappend _rx_grp "D2D_RX_WORDN_CLK_$n"   ;# negedge half - same domain, opposite phase
}

# D2D_TX_CLK_0 IS IN THE SYSTEM GROUP DELIBERATELY. READ THIS BEFORE MOVING IT.
#
# It is a -divide_by 1 generated clock declared on the OUTPUT PORT TL_CLK_TX
# (tidelink_constraints.sdc:177) and it has ZERO SINKS: no CTS clock tree, no
# CCOpt skew group, no registers. So its group membership cannot cut or create a
# single register-to-register path. Its one and only role is to be the reference
# clock for set_output_delay on TL_TX[*] (tidelink_constraints.sdc:179).
#
# While it sat in the TX group those eight checks were DELETED OUTRIGHT. The
# flops launching TL_TX[*] sit on the internal net io_clk, which carries no
# generated-clock declaration and therefore resolves to $EXTCLK -- this group.
# The output-delay reference was in the TX group. -asynchronous between the two
# deleted the whole reg2out path and the endpoints vanished from analysis.
#
# MEASURED, gdsrun-20260823-rzG and gdsrun-20260824-valid7, identically, in
# reports/place_coverage_untested.rep:
#
#     ExternalDelay (Late)   15 checks   7 met   0 violated   8 UNTESTED
#     TL_TX[7] ... TL_TX[0]  ExternalDelay (Late)  UNTESTED  reason: False Path
#
# Eight of the fifteen output-delay checks on this chip -- 100% of the
# die-to-die transmit data interface, the interface every cross-die transaction
# crosses -- were disabled by group membership alone. Not loosely constrained.
# Not constrained at all.
#
# TL_CLK_TX itself stays unconstrained after this change and that is CORRECT: no
# set_output_delay is declared on it, because it is the forwarded clock, not
# data. Expect uncons_endpoint to fall from 18 entries to 2 (TL_CLK_TX x 2
# views), NOT to 0.
set _sys_grp [list $EXTCLK QSPI_SCLK QSPI_SCLK_o D2D_TX_CLK_0]

# _tx_grp is now a single clock, D2D_TX_WORD_CLK_0, and it is still asserted
# -asynchronous against a group containing the clock it is GENERATED FROM. That
# remains a deliberate cut of a physically synchronous boundary, backed by RTL
# synchronisers, NOT a claim of real asynchrony -- exactly the honesty [C2]
# above asks for. Closing it properly is [C2] option A and is a separate change
# with a separate risk: ~1,184 exposed endpoints against a design closing setup
# on 36 ps. Do not fold it in here.
if {[llength $_rx_grp] != 17 || [llength $_tx_grp] != 1 || [llength $_sys_grp] != 4} {
    error "constraints.sdc: D2D clock groups built wrong -\
           rx [llength $_rx_grp], tx [llength $_tx_grp],\
           sys [llength $_sys_grp], expected 17, 1 and 4"
}
set_clock_groups -asynchronous -name eth_chiplet_cdc \
    -group [get_clocks $_sys_grp] \
    -group [get_clocks $_tx_grp] \
    -group [get_clocks $_rx_grp] \
    -group [get_clocks {rmii_ref_clk mii_rx_clk mii_tx_clk}] \
    -group [get_clocks [list $SWDCLK]]
unset _rx_grp _tx_grp _sys_grp

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
# SE in particular WAS constrained nowhere else -- true when written, stale
# since 2026-08-19. bscan_constraints.sdc:39 now gives it a real
# `set_input_delay -clock clk -max 1.0`, because SE stopped being a strap and
# became the IEEE 1149.1 boundary-scan enable. See the REMOVED note further
# down this file for why case-analysing it would delete the TAP.
set_input_transition -max 2.00 [get_ports TEST]           ;# [CONVENTION] generic 3.3V LVCMOS board driver; static strap pin, no timing consequence
set_input_transition -max 2.00 [get_ports SE]             ;# [CONVENTION] as TEST. SE is ALSO delay-constrained in bscan_constraints.sdc
set_input_transition -max 2.00 [get_ports {HOSTIO4_P1[*]}]

# SCAN IS OFF IN MISSION MODE, AND SAYING SO IS WORTH REAL TIMING.
# Without this, the scan multiplexer inside every SDFxx flop is timed in BOTH
# states, so the SI/SE side of every mux-D flop competes with the functional
# D side for the critical path.
#
# COUNT CORRECTED 2026-08-18: this comment used to say "~23.5k mux-D flops".
# That was true of the 08-06/08-07 netlists (37,834 SDF*/SEDF* of 58,120 flops,
# 65.1%). The current netlist has 3,715 of 58,620 -- 6.34%. The flip happened
# between 08-07 and 08-08 and its cause is NOT established; see
# docs/tapeout/16-open-defects.md section 6. The constraint is still correct and
# still worth having, but it now buys roughly a tenth of the paths implied
# above, so do not cite it as a large-scale timing saving.
#
# Post-route STA on 2026-08-07 found violating
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
# SE: REMOVED 2026-08-19. It is no longer a static strap — it is the IEEE 1149.1
# boundary-scan enable, driving trst_n on the TAP and the select on every TAP pin
# mux. Case-analysing it to 0 puts the TAP in permanent reset and makes all 76
# boundary cells unreachable AND unobservable, at which point Genus deleting the
# entire boundary-scan register is not a bug, it is correct constant propagation.
# The netlist would ship with no boundary scan and no warning anywhere.
#
# The note six lines up — "if you ever DO want to time the scan chain, comment
# these out rather than adding overrides" — is exactly what has been done. SE's
# replacement timing lives in ../inputs/bscan_constraints.sdc, sourced above.
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
#
#### MAXIMUM TRANSITION #######################################################
#
# UNTIL 2026-08-29 THIS DESIGN HAD NO SLEW RULE AT ALL. Not a loose one -- none.
# The only limit in force anywhere was the library's own global default:
#
#       tcbn65lpwc.lib:425      default_max_transition : 0.7657
#
# and that line is the ONLY occurrence of the string "max_transition" in all
# 80 MB of the standard-cell liberty (grep -c == 1). No cell and no cell pin
# narrows it. The two rules above are both PORTS-ONLY, and the fanout one is
# documented ten lines up as a structural no-op. Nothing constrained an
# internal net anywhere in the design.
#
# WHY 0.7657 IS NOT A DESIGN RULE. It is the last point of the characterisation
# axis. Every timing table in the library is indexed on input slew by one of
# three ladders -- a 7-point one (134,803 tables), a coarse 3-point one
# (19,120 tables) and an 8-point one (2,024 tables) -- and all three END at
# 0.7657. (Axis points not reproduced: TSMC characterisation data, same licence
# reason as the load axis above; read them in tcbn65lpwc.lib.) So the library
# "default" is the EXTRAPOLATION BOUNDARY, exactly like the 100 pF above: it
# marks where the model stops meaning anything, not where the design stops
# being good. A rule that fires only once the timing model has already given up
# is not a design rule. Worse, 12.3% of those tables have NO characterised
# point at all between 0.0917 and 0.7657 -- one linear segment 0.674 ns wide.
#
# WHAT ITS ABSENCE COST, MEASURED ON THE SHIPPING LINEAGE.
# build/gdsrun-20260826-rc1/reports/drv_05_route_opt.rep:15-20 reports exactly
# six max_transition violators and every one is an IO pad. It reads clean. It
# is not. On the SAME lineage the design's critical setup path
# (build/holdfix-20260828/sta_final6/reports/timing_setup_default_analysis_view_setup.rpt:8)
# ends on rf_16k pin A[11] at slack -0.001 ns, and along its 44 points:
#       16 points carry slew > 0.188, and they hold 4.271 ns of the 9.749 ns
#        6 points carry slew > 0.3806
#        0 points carry slew > 0.7657   <-- so NOTHING on it is reportable
# The endpoint is the clearest case. rf_16k's setup requirement is slew
# dependent on both axes, and A[11] and A[10] make a controlled experiment:
# same startpoint, same launch and capture clock, pins 4.6 um apart.
#       A[11]  arrives at slew 0.407, needs 0.749   (rpt:23,77)
#       A[10]  arrives at slew 0.048, needs 0.655   (rpt:916,972)
# 94 ps of pure slew penalty on one pin, and it is the whole violation.
#
# WHY 0.300, DERIVED. The cost curve was measured, not guessed: the routed rc4
# database was reopened read-only and every pin slew dumped, giving the exact
# number of NETS a limit would put into repair (Innovus over db_rc4, 08-29):
#       0.188 -> 57,196    0.250 -> 35,245    0.300 -> 26,050
#       0.350 -> 18,823    0.400 -> 12,914    0.500 ->  4,522
# At one BUFFD4 (3.24 um2) per net -- a LOWER bound, a long net needs several --
# 0.300 costs ~84,400 um2 against 799,061 um2 of stdcell area, about +4.5
# points of core utilisation. This design sits at 77.52%
# (build/gdsrun-20260826-rc1/reports/design_report.json, qor_util_pct) and DRV
# repair on it has ALREADY been blocked once by density at 92.2%. That last one
# is a RUN NOTE, not tool output I re-measured -- it is recorded in
# genus-innovus/runs/20260807T171905Z_eval-pnr-resume/config/scripts/3b_pnr_cts_eval.tcl:654
# as "density 83.58% -> 92.17%, which then BLOCKED DRV repair: 153 max_tran
# nets". Hold repair on this design has historically eaten 90,682 um2
# (baseline_2026-08-07/work/innovus.log:460) and 171,250 um2 (line 152 of this
# very file), so that headroom is spoken for.
# 0.300 leaves that hold headroom underneath the 92.2% wall. 0.188 does not:
# it costs ~185,000 um2, roughly +9.8 points, and would reach the wall with the
# hold repair still to pay for. THAT is why this is 0.300 and not the
# 0.15-0.25 that the timing evidence on its own would argue for.
#
# IT IS NOT INERT, AND IT FIXES THE PATH THAT FAILED. 0.300 is 2.55x tighter
# than the library default, so the min() rule below cannot swallow it. Capping
# A[11] at 0.300 drops its setup requirement 0.7487 -> 0.7233, worth 25 ps,
# which takes that path from -0.001 to +0.024 and removes the post-route setup
# ECO entirely.
#
# THE MIN() RULE, AND THE PRICE THIS LINE PAYS AT THE PAD RING. MEASURED, not
# assumed: with 2.73 forced onto [current_design] on the rc4 database,
# uPAD_I2C_SDA/PAD's Required moved 5.000 -> 2.730 even though
# i2c_constraints.sdc:233 already sets 300 on that exact pin. The smallest
# limit from ANY source wins -- library, port-specific SDC and design-scoped
# SDC alike -- and a per-port value can never buy an exemption back. Innovus
# offers -override for this; GENUS, the tool that actually reads this file
# (eth-chiplet/design.mk:235), does not document it, so it is not used here.
# The consequence is bounded, and it was MEASURED by applying this exact line
# to the rc4 database rather than reasoned about: the max_transition report
# goes from 6 rows to 236,130. 235,894 of those are internal pins -- the real
# work, and the cost curve above is how to price it -- and 236 land on the pad
# ring. Of the 236, only 97 can NEVER be fixed:
#       48  uPAD_*/PAD pins driving off-chip     (0.593 - 6.331 ns)
#       49  top-level ports, slew ASSERTED by set_input_transition, not
#           computed                             (0.398 - 6.331 ns)
# No repeater moves either. The remaining 139 are pad-cell CORE-side pins
# (46 I, 45 OEN, 48 REN); internal logic drives them and they are ordinary
# fixable violations like any other.
# So the STANDING cost of this rule, once the design converges internally, is
# 97 permanently red rows. Every one of them matches `uPAD_*/PAD` or a bare
# top-level port name, so a DRV gate can filter them mechanically, and Innovus
# -override can exempt them on the P&R side where Genus is not the reader. Do
# NOT read them as new defects, and do NOT "fix" them by loosening this line
# back above 0.7657 -- that only restores the silence it replaces.
#
# THE REFINEMENT NOT TAKEN. `set_max_transition <v> [get_clocks clk] -data_path`
# and `-clock_path` would split the data rule from the clock rule and might
# spare the pad ring. Neither is confirmed to behave identically in Genus and
# Innovus, and choosing a second, tighter number for the clock network is a
# signoff decision about skew, not a drive/load fix. Flagged, not changed --
# same standing as the set_max_fanout note above.
#
# DO NOT COPY THE SIBLING PROJECT. nanosoc-multicore-system's
# constraints_setup.sdc:12 sets max_transition_factor 0.273 and its
# constraints.sdc:86 multiplies it by the period. Here that is 2.73 ns, 3.57x
# LOOSER than the library default. It was run on the rc4 database to be sure:
# it caught ZERO internal pins and added 22 unfixable IO ones. A limit looser
# than the library default is not merely inert -- it is worse than nothing,
# because the file then reads as though the problem had been addressed.
#
# ---------------------------------------------------------------------------
# DOES [current_design] SURVIVE write_sdc?  YES -- MEASURED 2026-08-29, and it
# had to be, because P&R's ONLY SDC source is the Genus-written
# outputs/<block>_syn.sdc (named by genus-innovus/scripts/*.mmmc's
# create_constraint_mode). If the design scope were dropped on the way out,
# this line would be silently absent from the run it is supposed to fix and
# the failure would look like a bad target instead of a missing constraint.
#
# The concern was not idle. In the last real synthesis
# (build/gdsrun-20260826-rc1/outputs/nanosoc_eth_chiplet_pads_syn.sdc) there
# are exactly 8 set_max_transition lines and ALL 8 are per-port -- the QSPI
# 2.5 ns and I2C 300.0 ns ones from the sourced IP SDCs. Zero design-scope.
# And Genus demonstrably REWRITES collection scopes: `set_max_capacitance 100
# [all_outputs]` above comes out as 34 per-port lines, `set_max_fanout 10
# [all_inputs]` as 37. So "Genus expands scopes on write" was a live theory.
#
# THE PROOF, on the same Genus that wrote that file (21.15-s080_1): read_libs
# tcbn65lptc.lib, elaborate a 2-flop stub, then write_sdc four times while
# adding one constraint at a time. Verbatim output:
#     A (nothing set)                       -> no set_max_transition at all
#     B  set_max_transition 0.300 [current_design]
#                                           -> set_max_transition 0.3 [current_design]
#     C  + set_max_transition 2.5 [get_ports q0]
#                                           -> BOTH lines, design scope first
#     D  + set_max_capacitance 0.15 [current_design]
#                                           -> set_max_capacitance 0.15 [current_design]
# A is the control: it proves the probe can report absence. [current_design] is
# written through UNEXPANDED. Readback agreed: get_db [current_design]
# .max_transition == 300.0 (ps).
#
# THIS IS THE SINGLE MECHANISM. DO NOT ALSO TURN ON SYN_DRV_FIX.
# asic-toolkit/flow/genus/1_synthesis.tcl:781-787 does the same thing behind a
# knob, and its comment says design-scoped DRV reaches P&R -- correct, per D
# above. But it is SYN_DRV_FIX=0 by default (1_synthesis.tcl:70) and
# eth-chiplet/design.mk sets nothing, so it is INERT: there is no duplicate
# today, and this line is the only design-scope rule in force. Enabling it
# would be actively wrong for two reasons, not one:
#   1. SYN_MAX_TRAN defaults to the tech value or 0.40 (1_synthesis.tcl:86),
#      both LOOSER than 0.300. Harmless on its own -- min() wins -- but it puts
#      a second number for one constraint into a second file, which is exactly
#      how this project got bitten before.
#   2. The same block ALSO issues `set_max_capacitance $SYN_MAX_CAP
#      [current_design]`, default 0.15 pF. That contradicts the measured 100 pF
#      decision 120 lines up and would put every output pad permanently red --
#      and probe D proves it would land in the written SDC, so P&R would sign
#      off against it.
# If a future session wants the knob instead of this line, it must delete this
# line in the same commit, set BOTH SYN_MAX_TRAN and SYN_MAX_CAP explicitly,
# and re-measure. One constraint, one source.
set_max_transition 0.300 [current_design] ;# [MEASURED] 26,050 nets, ~84,400 um2, +7.9 util pts
# THE +7.9 CORRECTS AN EARLIER +4.5 THAT WAS WRONG BY 1.8x. The old figure divided
# the area by CORE area; Innovus' UTIL column divides by PLACEABLE area, and ~55% of
# this core is macro. Measured 10,677 um2/pt from five consecutive stage pairs in
# gdsrun-20260826-rc1/reports/qor_05_route_opt.rep (spread 10,498-10,946, <5%).
# 84,400 / 10,677 = 7.9. Anyone re-deriving this: use the tool's own UTIL and AREA
# columns, never a core-area division.

