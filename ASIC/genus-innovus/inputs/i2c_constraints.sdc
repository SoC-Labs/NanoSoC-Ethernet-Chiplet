#=============================================================================
# I2C SIDEBAND  —  I2C_SCL / I2C_SDA
#=============================================================================
# Added 2026-08-07. Before this file, I2C_SCL and I2C_SDA had NO constraint of
# any kind in any of the four SDCs: no clock, no input/output delay, no drive,
# no load, no exception. They were the last interface on the chip in that
# state — QSPI, RMII, SWD, the D2D link and the system clock all have
# characterisation blocks. An unconstrained bidirectional pad is timed with an
# infinitely sharp input edge and a zero output load, and Innovus says so
# explicitly for ports in this state (see the IMPCCOPT-4313 quote in
# tidelink_constraints.sdc).
#
# Number tags used below:
#   [SPEC]    published number — NXP UM10204 or the TSMC IO .lib. Quoted, not
#             derived.
#   [RTL]     read directly out of this design's source, file:line given.
#   [DERIVED] arithmetic on a [SPEC] or [RTL] number, working shown.
#   [CLAMP]   deliberately NOT a characterisation. A bound chosen because the
#             library cannot represent the real value. Read the reasoning
#             before trusting it.
#   [BUDGET]  allowance, not measured. No board or interposer extraction exists.
#
# Units are ns / pF / ohms throughout (set_units in constraints.sdc declares
# ns and pF, and tphn65lpgv2od3_slwc.lib agrees: time_unit "1ns",
# capacitive_load_unit (1,pf)).
#
# Primary reference:
#   NXP UM10204, "I2C-bus specification and user manual", Rev. 6 — 4 April
#   2014. Tables 9 and 10. This is the revision that was actually retrieved and
#   read while writing this file; every [SPEC] number below was transcribed
#   from it. Rev. 7.0 (1 October 2021) is the current revision. Its Table 10 is
#   NOT believed to change any Standard-mode number used here, but that was not
#   verified against the document — see WARNING 6.


#=============================================================================
# WHAT THIS INTERFACE ACTUALLY IS  —  established, not assumed
#=============================================================================
#
# PORTS. Both are real top-level chip pins. The synthesis/P&R top is
# nanosoc_eth_chiplet_pads, which contains the pad ring, so these are physical
# balls, not RTL boundary nets:
#   ASIC/tech_wrappers/tsmc65/nanosoc_eth_chiplet_pads.v:79-80
#     inout wire I2C_SCL;
#     inout wire I2C_SDA;
#
# PAD CELL. Both use PDUW16DGZ_G (pads .v:593-606; the pad census in
# docs/tapeout/scripts/04-floorplan-and-io.md:713 counts exactly 2 of them and
# attributes them to I2C SCL/SDA). READ WARNING 1 — THIS PAD IS NOT AN
# OPEN-DRAIN CELL.
#
# MASTER OR SLAVE? BOTH, on the same two pads, selected by role_strap at POR.
# axi_chiplet_controller.sv instantiates both cores and wired-ANDs their
# outputs onto the shared pads:
#   :3270  i2c_master_axil u_i2c_master  (.clk(apb_clk), ...)
#   :3332  i2c_slave_axil_master u_i2c_slave (.clk(apb_clk), ...)
# So SCL is an output in master mode and an input in slave mode, and which one
# this die is is not known until the strap is sampled. That fact alone rules
# out a single fixed create_clock direction — see THE CLOCK DECISION below.
#
# WHAT IS ON THE OTHER END. The peer die, not a board peripheral. This is the
# TideLink sideband: the autoneg FSM claims its peer by driving a START and
# writing a claim byte over this bus (pads .v:76-78), and the G2 testbench
# models it as a "wired-AND pull-up bus across both dies"
# (docs/G2_TB_ARCHITECTURE.md:357). The far end is the compute chiplet, built
# from the SAME TSMC pad library:
#   ~/SoCLabs/NanoSoC-Compute-Chiplet/ASIC/chiplet-pads/tech_wrappers/tsmc65/
#   nanosoc_compute_chiplet_pads.v:327-330
#     PDUW08DGZ_G uPAD_SCL0 / uPAD_SDA0 / uPAD_SCL1 / uPAD_SDA1   (8 mA)
# so the far-end pin capacitance is a vendor number rather than an estimate:
# 1.5509 pF [SPEC, PDUW08DGZ_G pin(PAD) capacitance]. Ours is 1.5928 pF
# [SPEC, PDUW16DGZ_G]. No board I2C peripheral is documented anywhere — see
# WARNING 4 for the pull-up resistors, which nobody has specified.
#
# BUS SPEED: STANDARD-MODE, 100 kHz. Not assumed — computed from the RTL:
#   prescale = Fclk / (FI2Cclk * 4)          [RTL] i2c_master.v:140-141
#   POR prescale = 16'd125                   [RTL] axi_chiplet_controller.sv:775
#   apb_clk = 50 MHz                         [RTL] axi_chiplet_controller.sv:760
#   => FI2C = 50e6 / (125 * 4) = 100 kHz     [DERIVED]
# The RTL comment at axi_chiplet_controller.sv:768-772 states the same
# conclusion in words ("100 kHz — the I2C standard bus rate") and records why:
# the POR default of prescale=1 gave ~12.5 MHz SCL, which the slave's bit
# detector could not track (Bug N1 second cause). The autoneg FSM writes this
# same prescaler into the master's PRESCALE register before the first CLAIM
# transaction, so the bus runs at 100 kHz from cold boot. Standard-mode is
# therefore the mode to constrain against, and every [SPEC] number below is
# taken from the Standard-mode column of UM10204 Table 10.
#
# IO RAIL: 3.0 V. [SPEC] tphn65lpgv2od3_slwc.lib:44,57 — power_rail
# (IO_VOLTAGE, 3), operating_conditions "WCCOM" voltage 3. (The library lives
# under an .../IO2.5V/... path; the path is not the rail. The .lib is
# authoritative and says 3.)


#=============================================================================
# THE CLOCK DECISION  —  why there is NO create_clock in this file
#=============================================================================
# THIS IS THE LOAD-BEARING JUDGEMENT IN THIS FILE. It would have been easy to
# write `create_clock -period 10000 [get_ports I2C_SCL]` and call the interface
# constrained. That would be fabrication. Here is the evidence against it.
#
# NOTHING IN THIS DESIGN CLOCKS OFF SCL. Both I2C cores are fully synchronous
# to apb_clk and treat SCL as an oversampled DATA input. The master samples it
# through a plain flop and does edge detection combinationally:
#   i2c_master.v:862      scl_i_reg <= scl_i;        (inside always @(posedge clk))
#   i2c_master.v:290-291  wire scl_posedge = scl_i_reg & ~last_scl_i_reg;
# and the slave does the same behind a 4-deep digital filter:
#   i2c_slave.v:199,468   reg [FILTER_LEN-1:0] scl_i_filter;  FILTER_LEN = 4
#   i2c_slave.v:239-240   assign scl_posedge = scl_i_reg && !last_scl_i_reg;
# There is not one `always @(posedge scl)` or `@(negedge scl)` in either core.
# A create_clock on I2C_SCL would therefore be a clock with ZERO sink
# registers. It would propagate nowhere, generate no real setup or hold check,
# and add a fictitious domain to MMMC — while inviting CTS to try to build a
# clock tree backwards out of a bidirectional pad.
#
# THE OVERSAMPLING RATIO MAKES A STATIC CHECK MEANINGLESS ANYWAY.
#   SCL bit period at 100 kHz            = 10 us          [DERIVED]
#   apb_clk period at 50 MHz             = 20 ns          [RTL]
#   => 500 apb_clk samples per SCL bit                    [DERIVED]
#   tLOW min (Standard-mode)              = 4.7 us  [SPEC, Table 10]
#   tHIGH min (Standard-mode)             = 4.0 us  [SPEC, Table 10]
#   tSU;DAT min (Standard-mode)           = 250 ns  [SPEC, Table 10]
# Against that, the whole pad round trip is single-digit nanoseconds: the
# PDUW16DGZ_G I->PAD arc is 2.5-5.8 ns across its entire characterised load
# range [SPEC, .lib cell_rise/cell_fall tables]. The tightest published
# requirement on this bus, tSU;DAT at 250 ns, has ~50x margin to that; tLOW has
# ~1000x. There is no physical implementation of this pad path that fails a
# 100 kHz I2C timing requirement, and no placement or routing decision that a
# timing constraint could usefully steer.
#
# THE CROSSING IS GENUINELY ASYNCHRONOUS. In slave mode SCL is generated by the
# peer die off its own clock. In master mode we generate SCL, but we read it
# back to detect the peer stretching it — and the peer's stretch is timed by
# the peer's clock. Either way the edge arriving at our pad has no phase
# relationship to apb_clk. That is a clock-domain crossing, correctly handled
# in RTL by the synchroniser/filter logic quoted above. Applying a
# clock-relative static check across a CDC is meaningless by construction.
#
# CONCLUSION: the honest constraint is an explicit asynchronous declaration —
# set_false_path in both directions — plus real electrical characterisation of
# the pins. That is what this file does. The false path is not laziness: it is
# the difference between "this path is deliberately not timed, here is why" and
# the silence that was here before, which reads identically in a timing report
# but records no intent and no review.


#=============================================================================
# OUTPUT LOAD  —  what our pad drives when it pulls the bus low
#=============================================================================
# THE SPEC LIMIT IS 400 pF. Cb, capacitive load for each bus line,
# Standard-mode max = 400 pF [SPEC, UM10204 Table 10, symbol Cb]. That is the
# largest load this pin may see and still be a conforming I2C bus.
#
# THE VALUE CONSTRAINED IS 100 pF, AND THAT IS A DELIBERATE COMPROMISE BETWEEN
# TWO CEILINGS THAT ARE NOT THE SPEC. Both are hard limits of our own flow:
#
#   (a) THE LIBRARY. The PDUW16DGZ_G output tables run to 100 pF
#       (.lib CHAR_LIB_TABLE_CORE_SLEW2IO_LOAD_16_5x6, index_2 max 100.0000).
#       At 400 pF the tool extrapolates 4x off the end of the NLDM table; at
#       100 pF it reads an exact characterised index point, no interpolation
#       and no extrapolation.
#
#   (b) THE DESIGN-WIDE DRV RULE. constraints.sdc declares
#       `set_max_capacitance 100 [all_outputs]` AFTER the source lines, and
#       all_outputs includes these two inout ports. Anything declared here is
#       overridden by that later rule, so a 400 pF set_load would produce a
#       guaranteed max_capacitance violation (400 > 100) that no tool can fix
#       — a pad cannot shrink its off-chip load. That is precisely the class of
#       permanent unfixable red entry the max_capacitance comment in
#       constraints.sdc exists to prevent, and this file will not reintroduce
#       it from the other direction.
#
# NOTHING IS HIDDEN BY THE CHOICE, and that is checkable rather than asserted.
# The only check set_load feeds here is output transition (the timing paths are
# false-pathed below), and the pad has overwhelming margin at BOTH loads:
#     at 100 pF: fall_transition = 6.2 ns   [SPEC, .lib, on-table]
#     at 400 pF: ~25 ns                     [DERIVED, linear extension]
#     limit    : 300 ns                     [SPEC, UM10204 Table 10, tf]
# The pad passes tf with ~12x margin even at the full 400 pF spec load. Moving
# the constrained figure from 400 to 100 pF therefore changes no conclusion
# about whether this pin works — it only stops the flow reporting a violation
# against its own extrapolated arithmetic. See WARNING 8.
#
# For scale, the load actually built is far below either number: our pad
# (1.5928 pF) + the compute chiplet's pad (1.5509 pF) + a few pF of substrate
# routing = well under 10 pF [DERIVED / BUDGET]. 100 pF remains ~10x
# pessimistic against the real chiplet-to-chiplet interposer.
set_load 100 [get_ports I2C_SCL]
set_load 100 [get_ports I2C_SDA]


#=============================================================================
# OUTPUT TRANSITION CEILING  —  the spec limit, not the library default
#=============================================================================
# tf, fall time of both SDA and SCL, Standard-mode max = 300 ns
# [SPEC, UM10204 Table 10, symbol tf].
#
# THIS LINE EXISTS TO PREVENT A FALSE DRV FAILURE, AND IT IS STILL NEEDED AFTER
# THE LOAD WAS REDUCED TO 100 pF. The library's default_max_transition is 5.0 ns
# (.lib:424). At the 100 pF load set above the pad's fall_transition is 6.2 ns
# [SPEC, .lib] — already over that default, so without this line signoff would
# report a max_transition violation. It would be a violation nobody can fix, a
# pad cell cannot be upsized, and it is not real: I2C permits 300 ns.
# Constraining the port to the actual protocol requirement replaces an
# arbitrary library default with the number the interface is really held to.
# (No later [all_outputs] rule overrides this: constraints.sdc sets
# max_capacitance and max_fanout design-wide, but no max_transition.)
#
# Note the related output-stage number in UM10204 Table 9: tof max = 250 ns for
# Standard-mode, tighter than the 300 ns bus-line figure. Table 9 note [5]
# explains the gap — the 50 ns difference is headroom for series protection
# resistors between the pin and the bus. We have 6.2 ns at the constrained
# 100 pF load and ~25 ns even at the full 400 pF spec load, so we meet the
# tighter Table 9 figure as well, with 10x to spare in the worst case.
#
# THIS APPLIES TO THE FALLING EDGE ONLY, IN REALITY. See the next block: the
# rising edge is not driven by this pad at all. The tool has no way to express
# a per-edge output slew limit tied to a Hi-Z release, so this ceiling is
# written once and is only physically meaningful for the pull-down.
set_max_transition 300 [get_ports I2C_SCL]
## The 5.0ns violations are reported on uPAD_I2C_SCL/PAD and uPAD_I2C_SDA/PAD -
## the pad INSTANCE pin, which a port constraint does not cover, so the library's
## own 5.0ns limit applied. Constrain the pin too. Note a design constraint can
## only ever TIGHTEN a library limit, so this documents intent rather than
## relaxing it; the real resolution is a waiver citing UM10204 open-drain rise
## times against a 100pF bus.
set_max_transition 300 [get_pins uPAD_I2C_SCL/PAD]
set_max_transition 300 [get_pins uPAD_I2C_SDA/PAD]
set_max_transition 300 [get_ports I2C_SDA]


#=============================================================================
# INPUT TRANSITION  —  A CLAMP, NOT A CHARACTERISATION. READ THIS.
#=============================================================================
# I2C is an open-drain wired-AND bus. THE RISING EDGE IS NOT DRIVEN BY ANY
# DEVICE. Every device releases to Hi-Z and an external pull-up resistor charges
# the bus capacitance through an RC ramp:
#
#     tr = 0.8473 * R_pullup * C_bus        [DERIVED]
#
# where 0.8473 = ln(0.7/0.3), because UM10204 measures tr between 0.3*VDD and
# 0.7*VDD (Table 10 note [1], referred to VIL(max) and VIH(min) from Table 9).
#
# The magnitude of the problem, at the spec's 400 pF max bus capacitance:
#     R = 1.5 kohm  ->  tr = 0.8473 * 1500  * 400e-12 = 508 ns   [DERIVED]
#     R = 2.2 kohm  ->  tr = 0.8473 * 2200  * 400e-12 = 746 ns   [DERIVED]
#     R = 10  kohm  ->  tr = 0.8473 * 10000 * 400e-12 = 3.39 us  [DERIVED]
# and the spec's own ceiling is tr max = 1000 ns for Standard-mode
# [SPEC, UM10204 Table 10, symbol tr].
#
# NOW THE LIBRARY. The input_net_transition axis of tphn65lpgv2od3_slwc.lib
# ends at 5.0 ns:
#     index_1( "0.5000, 1.0000, 2.0000, 3.0000, 5.0000" )    [SPEC, .lib]
# A conforming Standard-mode rising edge is up to 1000 ns. That is 200x beyond
# the last characterised point, and a real 10 kohm/400 pF edge at 3.39 us is
# ~680x beyond it — two to three ORDERS OF MAGNITUDE outside anything this
# .lib can represent. There is no value of set_input_transition that
# characterises an I2C rising edge, because the NLDM model has no room for one.
# Anything past 5.0 ns is pure extrapolation of a table into a region where its
# curve fit means nothing.
#
# SO THE VALUE BELOW IS A CLAMP, NOT A MEASUREMENT. 5.0 ns is chosen because it
# is exactly the library's last characterised index point — the slowest edge the
# model can describe without inventing data. It is knowingly ~200x optimistic
# against the spec's tr. It is NOT presented as the real edge rate.
#
# WHY A CLAMP IS STILL BETTER THAN THE ZERO THAT WAS HERE:
#   - Unconstrained, the tool assumes a 0.000 ns input slew — an infinitely
#     sharp edge. That is not merely wrong, it is wrong in the OPTIMISTIC
#     direction on every input path, and it is silent. 5.0 ns is also
#     optimistic, but it is bounded, it is on-table, and it is written down.
#   - It removes these two ports from the class Innovus warns about with
#     IMPCCOPT-4313 ("cannot determine the drive strength ... assume a fixed
#     output slew of 0.000"), so the remaining warnings in that class point at
#     ports that genuinely still need work.
#   - The optimism is harmless HERE, and that is checkable rather than hoped:
#     the only paths this figure feeds are the pad-to-synchroniser paths, and
#     those are declared false below. It affects no timing conclusion. It is a
#     DRV and modelling-hygiene number, not a timing number.
#   - The real defence against a multi-microsecond edge is not static timing at
#     all. It is the receiver: a Schmitt-trigger pad input plus 500x
#     oversampling plus the slave's 4-deep digital filter. A slow edge on this
#     bus is a functional/analogue concern, and it is answered by choosing the
#     pull-up correctly — see WARNING 4 — not by an SDC line.
#
# The falling edge, by contrast, IS driven (open-drain pull-down) and could be
# characterised normally; at ~25 ns into 400 pF it is also off the top of the
# same 5.0 ns axis. Both edges therefore clamp to the same ceiling, so they are
# not split with -rise/-fall: doing so would add syntax without adding
# information.
#
# The -min figure is the library's FIRST index point, 0.5 ns [CLAMP], for the
# same on-table reason. No I2C edge is ever this fast; it is a floor for the
# fast-corner hold calculation, and it too is nullified by the false paths.
set_input_transition -max 5.0 [get_ports I2C_SCL]
set_input_transition -max 5.0 [get_ports I2C_SDA]
set_input_transition -min 0.5 [get_ports I2C_SCL]
set_input_transition -min 0.5 [get_ports I2C_SDA]


#=============================================================================
# TIMING EXCEPTIONS  —  the explicit asynchronous declaration
#=============================================================================
# Argued at length under THE CLOCK DECISION above. In short: no register in
# this design clocks off SCL; the bus is oversampled 500:1 by apb_clk-domain
# logic; the arriving edges are asynchronous to apb_clk in both master and
# slave roles; and the crossing is handled structurally in RTL by a
# synchroniser and a 4-deep filter. There is no clock here to create, and no
# meaningful clock-relative check to perform.
#
# NO set_input_delay / set_output_delay IS WRITTEN, DELIBERATELY. Both require
# a -clock argument. Supplying one would mean inventing the clock this file
# has just argued does not exist, and every delay number referenced to it would
# inherit that fiction. An interface that is genuinely asynchronous should be
# declared asynchronous.
#
# SCOPE — these exceptions are narrow on purpose. `-from` on a bidirectional
# port selects only paths that START there (pad -> synchroniser flop); `-to`
# selects only paths that END there (flop -> pad). All internal apb_clk-to-
# apb_clk logic inside u_i2c_master and u_i2c_slave stays fully timed by the
# $EXTCLK create_clock in constraints.sdc. Nothing here relaxes the I2C
# controllers themselves.
set_false_path -from [get_ports I2C_SCL]
set_false_path -from [get_ports I2C_SDA]
set_false_path -to   [get_ports I2C_SCL]
set_false_path -to   [get_ports I2C_SDA]


#=============================================================================
# WARNINGS — READ BEFORE SIGNOFF. NONE OF THESE IS FIXED BY THIS FILE.
#=============================================================================
#
# 1. THE PAD IS A PUSH-PULL CELL, NOT AN OPEN-DRAIN CELL. THIS IS THE MOST
#    IMPORTANT LINE IN THIS FILE.
#
#    PDUW16DGZ_G is a 16 mA CMOS tristate bidirectional pad with a weak
#    pull-up keeper. From tphn65lpgv2od3_slwc.lib:4546+, pin(PAD):
#        function : "I" ;  three_state : "OEN" ;  drive_current : 16 ;
#        output_voltage : cmos ;  pull_up_function : "!REN" ;
#    When OEN=0 it actively drives BOTH levels. It has no open-drain mode.
#
#    Nor could it: the entire tphn65lpgv2od3_sl library contains no open-drain
#    digital pad. Every PDDW*/PDUW* cell is a DGZ tristate variant. The
#    requirement was recorded — docs/PIN_MAP.md:113-114 and :288-290 say the
#    cell "must be a true open-drain / open-collector cell (drive low or Hi-Z,
#    never drive high)" and left the choice as [TEAM DECISION] — and the
#    library then had nothing to satisfy it with.
#
#    OPEN-DRAIN IS EMULATED IN RTL, AND CURRENTLY IT IS CORRECT. The trick is
#    that the output data and the output enable are the SAME NET:
#        i2c_master.v:283-286   assign scl_o = scl_o_reg;  assign scl_t = scl_o_reg;
#                               assign sda_o = sda_o_reg;  assign sda_t = sda_o_reg;
#        i2c_slave.v:230-233    identical
#    and the wrapper maps OEN to _t with NO inversion (pads .v:593-606, and the
#    comment at :589-592 warns explicitly against "fixing" it to .OEN(~t)).
#    So OEN == I: to send a 1 the core sets both, OEN=1 tristates the pad, and
#    the external pull-up makes the high; to send a 0, OEN=0 and the pad drives
#    a strong low. The pad never drives high. Wired-AND arbitration and slave
#    clock-stretching work. The compute chiplet does the same thing with
#    PDUW08DGZ_G. This is a legitimate and common technique.
#
#    BUT THE SAFETY IS AN RTL INVARIANT, NOT A CELL PROPERTY, AND NOTHING
#    CHECKS IT. The bus is safe only while o == t holds all the way to the pad
#    pin. If synthesis, an ECO, scan insertion, or a future revision ever
#    drives _o from anything other than _t, the cell becomes exactly what it
#    physically is — a 16 mA push-pull driver on a wired-AND bus — and the
#    first time we drive high while the peer drives low, that is a 16 mA short
#    across two dies. An SDC cannot enforce this. SOMEONE MUST ADD A
#    POST-SYNTHESIS / POST-P&R NETLIST CHECK that the nets reaching
#    uPAD_I2C_SCL/.I and .OEN (and the SDA pair) are the same net. This is a
#    two-line LEC or netlist-grep assertion and it is the only thing standing
#    between this design and a bus-contention failure. It belongs in the
#    signoff checklist, not in this file.
#
#    SCAN/TEST MODE IS THE OTHER EXPOSURE. In scan shift, .I and .OEN are
#    driven independently from the chain, so the o == t invariant does not
#    hold and the pad CAN drive high. The current wrapper does not mux scan
#    onto functional pads (pads .v header, "a later revision can mux the scan
#    chain onto functional pads"), so this is a future hazard rather than a
#    present one — but on the bench it means: do not enter scan with a live
#    I2C bus attached to another device.
#
# 2. THE ON-DIE PULL-UP KEEPER IS ARMED, AND ITS VALUE IS UNKNOWN. The wrapper
#    ties .REN(tielo) on both pads (pads .v:595,602), and pull_up_function is
#    "!REN", so REN=0 ENABLES the keeper. This is benign-to-helpful: it holds
#    the bus high if the board pull-ups are absent, which prevents a floating
#    input and helps bring-up. It is NOT a substitute for the external
#    resistors — a keeper of this type is tens of kohms, far too weak to meet
#    tr. The actual resistance is not published in the NLDM view: the .lib
#    declares pulling_resistance_unit "1kohm" (:64) but gives no value for any
#    cell. If the pull-up budget ever needs to be exact, the number has to come
#    from the tphn65lpgv2od3_sl databook, not from this library.
#
# 3. UNBOUNDED ROUTE ON THE FALSE-PATHED PADS. A false path means the router is
#    free to take an arbitrarily long route from pad to synchroniser. At 100
#    kHz with 4.7 us of tLOW that is unreachable in practice — it would take a
#    route three orders of magnitude worse than anything this floorplan can
#    produce. If a future revision raises this bus to Fast-mode Plus, or if
#    someone simply wants the router held to something, the correct tool is
#    set_max_delay on the same -from/-to sets, NOT a create_clock. Note that
#    max_transition and max_capacitance DRV checks are unaffected by the false
#    paths, so the set_load and set_max_transition above still bind.
#
# 4. NO PULL-UP RESISTOR IS SPECIFIED ANYWHERE, BY ANYONE. Searched docs/ and
#    the board notes: docs/KR260_BOARD_WIRING.md does not mention I2C at all,
#    and docs/PIN_MAP.md:297 still carries this as an open checklist item
#    ("consider pull-ups for mdio, I2C"). The pads assume external pull-ups;
#    nobody has sized them. THE BUS WILL NOT WORK WITHOUT THEM. The window,
#    derived here so the board team has a starting point rather than nothing:
#
#      UPPER BOUND, from rise time. R <= tr_max / (0.8473 * Cb)
#        = 1000e-9 / (0.8473 * 400e-12) = 2951 ohm  ->  ~2.95 kohm  [DERIVED]
#        (tr max 1000 ns and Cb max 400 pF both [SPEC, Table 10])
#
#      LOWER BOUND, from sink current. R >= (VDD - VOL) / IOL
#        = (3.0 - 0.4) / 3 mA = 867 ohm  [DERIVED]
#        (IOL = 3 mA at VOL = 0.4 V, Standard-mode [SPEC, Table 9]; VDD = 3.0 V
#        [SPEC, .lib IO_VOLTAGE]. Our pad sinks 16 mA and is not the limit —
#        the 3 mA figure is the spec's conformance floor, and honouring it
#        keeps the bus interoperable with any conforming device.)
#
#      SUGGESTION: 2.2 kohm (E24 standard value) [DERIVED]. At the 400 pF worst
#      case tr = 746 ns, inside the 1000 ns limit; sink current
#      (3.0-0.4)/2200 = 1.18 mA, comfortably under 3 mA. At the realistic
#      chiplet-to-chiplet load of <10 pF, tr is under 20 ns.
#
#      This is guidance for the board/interposer team. It is deliberately not
#      an SDC constraint — SDC cannot express a resistor — and it must be
#      recorded in a board document, not left to live only in this comment.
#
# 5. THE MASTER SAMPLES SCL/SDA THROUGH A SINGLE FLOP. i2c_master.v:862-863 is
#    `scl_i_reg <= scl_i; sda_i_reg <= sda_i;` with no filter and no second
#    synchroniser stage. The slave is better protected — it has FILTER_LEN=4
#    (i2c_slave.v:199-200). In master mode the incoming edge is mostly our own
#    SCL echoed back, so the exposure is limited to a peer's clock-stretch
#    release, and 500x oversampling means a metastable sample costs at most one
#    apb_clk of edge-detection jitter out of 500. It is not believed to be a
#    silicon risk. It is recorded here because it is a real single-stage
#    synchroniser on an asynchronous input, the false paths above are what make
#    it invisible to STA, and a CDC audit should see it declared rather than
#    discover it. RTL issue, not fixable from an SDC.
#
# 6. SPEC REVISION. Every [SPEC] I2C number here was transcribed from UM10204
#    Rev. 6 (4 April 2014), Tables 9 and 10, which was fetched and read. The
#    current revision is Rev. 7.0 (1 October 2021); the canonical NXP URL
#    (nxp.com/docs/en/user-guide/UM10204.pdf) returned HTTP 404 at the time of
#    writing. The Standard-mode column is long-stable and no change is
#    expected, but this was NOT verified against Rev. 7.0. Anyone doing final
#    signoff should re-check tr, tf, Cb, tSU;DAT and IOL against the current
#    revision. All five are quoted with their symbol names above, so the check
#    is mechanical.
#
# 7. MODE IS SOFTWARE-CHANGEABLE, AND THIS FILE IS NOT. The 100 kHz figure
#    comes from the POR prescaler, but PRESCALE is a writable register
#    (I2C_PRESCALE at 0x208C, tidelink_chiplet_ctrl.h:46). Software can move
#    this bus to Fast-mode or beyond at runtime. If it ever does, the
#    Standard-mode [SPEC] numbers above stop applying: Fast-mode tightens tr
#    from 1000 ns to 300 ns and tSU;DAT from 250 ns to 100 ns, which changes
#    the pull-up window in WARNING 4 far more than it changes anything in this
#    file. The false-path argument survives — the crossing is still
#    asynchronous and still oversampled, 125x rather than 500x at 400 kHz —
#    but the board-level analysis does not.
#
# 8. THIS FILE CANNOT CONSTRAIN THE FULL 400 pF THE SPEC ALLOWS, BECAUSE A
#    LATER DESIGN-WIDE RULE OVERRIDES IT. constraints.sdc declares
#    `set_max_capacitance 100 [all_outputs]` after all four `source` lines, and
#    all_outputs includes I2C_SCL and I2C_SDA. Ordering means the global rule
#    wins over anything this file could say, so the load above is constrained
#    at 100 pF rather than at Cb max = 400 pF [SPEC, Table 10]. See the
#    reasoning in the OUTPUT LOAD block: the pad meets tf with ~12x margin even
#    at 400 pF, so this is a flow limitation and not a masked risk.
#
#    IT BECOMES A REAL PROBLEM ONLY IF THE BUS IS EVER BUILT WITH Cb > 100 pF —
#    which the chiplet-to-chiplet interposer will not do (<10 pF), but a bench
#    setup with cabling to an FPGA peer might. In that case the correct fix is
#    NOT to raise set_load here, because the global rule would still override
#    it. It is to exempt these two ports from the design-wide rule, i.e. add
#    `set_max_capacitance 400 [get_ports {I2C_SCL I2C_SDA}]` AFTER the
#    set_max_capacitance [all_outputs] line in constraints.sdc. That is an edit
#    to a file this change does not own, so it is written down here rather than
#    made. Flagged for whoever owns the design-wide DRV rules.
