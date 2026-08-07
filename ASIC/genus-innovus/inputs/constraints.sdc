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

source ../inputs/i2c_constraints.sdc

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
#   set_units above declares ns and pF, matching tphn65lpgv2od3_slwc.lib
#   (time_unit "1ns", capacitive_load_unit (1,pf), nom_voltage 3, WCCOM).
#   The IO liberty measures slew between 10% and 90%:
#       slew_lower_threshold_pct_rise/fall : 10.00
#       slew_upper_threshold_pct_rise/fall : 90.00
#       slew_derate_from_library           : 1.00   (no derate)
#   Datasheets almost always quote 20%-80%. EVERY datasheet number below is
#   therefore scaled to the library's thresholds by the linear-ramp factor
#       (90-10)/(80-20) = 80/60 = 4/3
#   before being written into a constraint. An unconverted 20%-80% number would
#   under-state the real edge by 25%.
#
# WHAT THE PADS ARE ACTUALLY CHARACTERISED FOR (tphn65lpgv2od3_slwc.lib):
#   input  (PAD->C, IO_SLEW2CORE_LOAD_5x6):  input_net_transition
#                                            index_1 = 0.5 .. 5.0 ns
#   output (I->PAD, CORE_SLEW2IO_LOAD_*_5x6): total_output_net_capacitance
#                                            index_2 = 5 .. 100 pF
#                                            (all of 04/08/12/16 mA; OSC pads
#                                             are 5..30 pF)
#   Note the OUTPUT floor: 5 pF. With set_load absent (= 0 pF) every output
#   timing arc in this design was being EXTRAPOLATED off the bottom of its own
#   NLDM table. The library's default_max_transition of 5.0 ns is the CEILING of
#   the input table, not a target.
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
# too-slow -min flatters hold. 0.50 ns is used instead: it is the FASTEST edge
# the pad is characterised for (index_1 floor), so it is simultaneously the most
# pessimistic hold assumption that remains on-table.
set_input_transition -min 0.50 [get_ports CLK] ;# [PLACEHOLDER] no max-slew-rate spec exists in SCAS869F; 0.5ns = pad NLDM index_1 floor

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
# The pad's input table stops at 5.0 ns, which is also the library's
# default_max_transition. Declaring 8.0 ns would extrapolate off the top of the
# NLDM table AND create a permanent, unfixable max_transition violation on an
# input port -- nothing inside the chip can sharpen an externally-driven edge.
# So the value below is CLAMPED to 5.0 ns, the largest characterised slew.
#
# BE CLEAR ABOUT THE DIRECTION OF THE RESULTING ERROR: 5.0 ns is FASTER than the
# probe's real ~8 ns edge, so SWD input timing here is OPTIMISTIC BY
# CONSTRUCTION. That is tolerable, and only because SWD has enormous native
# margin -- the same document notes the debugger "will produce a setup (Tsetup)
# and hold time (Thold) of half the cycle time (Tclock) of SWCLK", i.e. the
# protocol budgets half a clock period, and the SWDCLK <-> EXTCLK crossings
# already carry the multicycle paths declared above. Do NOT reuse this clamping
# argument on a performance-critical interface.
set_input_transition -max 5.00 [get_ports SWDCK] ;# [PLACEHOLDER] clamp. Real: Lauterbach Trf 6ns@10pF,20-80% => 8.0ns@10-90%, exceeds lib ceiling 5.0
set_input_transition -min 0.50 [get_ports SWDCK] ;# [PLACEHOLDER] pad NLDM index_1 floor; no fast-edge bound published for any probe
set_input_transition -max 5.00 [get_ports SWDIO] ;# [PLACEHOLDER] as SWDCK -- probe drives SWDIO on the falling SWCLK edge
set_input_transition -min 0.50 [get_ports SWDIO] ;# [PLACEHOLDER] pad NLDM index_1 floor
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
set_input_transition -min 0.50 [get_ports NRST] ;# [PLACEHOLDER] pad NLDM index_1 floor

### --- TEST / SE / HOSTIO4_P1 : generic board-level 3.3 V CMOS ---------------
#
# No datasheet applies: these are driven by whatever the board puts there (a
# strap/jumper for TEST and SE, an FPGA or host adapter for HOSTIO4_P1). The
# value below is the CONVENTIONAL figure for a 3.3 V LVCMOS driver into a short
# PCB trace: 2.0 ns at 10%-90%, equivalent to 1.5 ns at 20%-80%, i.e. ~1.3 V/ns
# on a 3.3 V rail. That is a typical FPGA/MCU LVCMOS33 output at moderate drive.
# It is also exactly an index_1 point in the pad table, so no interpolation.
#
# TEST and SE are STATIC configuration pins -- strapped, and never toggling in
# mission mode -- so their slew has no timing consequence whatsoever. They are
# constrained only so that no top-level input is left on the 0 ns default.
# SE in particular is constrained NOWHERE ELSE: it is absent from this file's
# delay section and from all three sourced IP SDCs. See the report.
set_input_transition -max 2.00 [get_ports TEST]           ;# [CONVENTION] generic 3.3V LVCMOS board driver; static strap pin, no timing consequence
set_input_transition -max 2.00 [get_ports SE]             ;# [CONVENTION] as TEST. NOTE: SE is otherwise unconstrained in every SDC
set_input_transition -max 2.00 [get_ports {HOSTIO4_P1[*]}] ;# [CONVENTION] generic 3.3V LVCMOS driver (FPGA / host adapter) over a short trace

### --- OUTPUT LOADING : package + board + far-end receiver -------------------
#
# set_load on these ports models everything BEYOND the pad: package parasitics,
# the PCB trace, and the input capacitance of whatever receives the signal. The
# pad cell's own PAD-pin capacitance (1.5297 pF on PDDW04DGZ_G, 1.5928 pF on
# PDDW16DGZ_G) is already inside the liberty model and must NOT be added here.
#
# BUDGET [CONVENTION] -- the components, so the total can be argued with:
#     package (wire-bond + lead/ball)                    ~1 pF
#     PCB trace, short microstrip (~0.5-1 pF/cm)         ~2-4 pF
#     far-end 3.3 V CMOS receiver input capacitance      ~4-5 pF
#                                                    --------------
#                                                        ~8-10 pF
# 10 pF is the round figure and is an exact index_2 point in the pad's output
# table. Two independent corroborations that this is the right order of
# magnitude: SCAS869F characterises its own LVCMOS output into "CL = 5 pF", and
# the Lauterbach table above quotes probe loads of 10/22/33 pF.
#
# ANYTHING IS BETTER THAN THE 0 pF THIS REPLACES: 0 pF is below the 5 pF floor
# of every output NLDM table in the IO library, so it was extrapolation.
set_load 10 [get_ports {HOSTIO4_P1[*]}] ;# [CONVENTION] package ~1pF + short trace ~2-4pF + CMOS receiver ~4-5pF
#
# SWDIO carries more: a debug connector, then a ribbon cable to the probe. The
# Lauterbach table characterises Trf at 10/22/33 pF, which is a direct statement
# of the load range that probe expects to see. 20 pF sits in that range and
# between index_2 points 10 and 25 pF, so it interpolates cleanly.
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
# 100 pF is not arbitrary and it is not slack: it is the largest
# total_output_net_capacitance any IO driver in tphn65lpgv2od3 is CHARACTERISED
# for (index_2 of CORE_SLEW2IO_LOAD_{04,08,12,16}_5x6 = 5, 10, 25, 40, 70, 100).
# Beyond 100 pF the NLDM tables extrapolate and the reported delay stops meaning
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

