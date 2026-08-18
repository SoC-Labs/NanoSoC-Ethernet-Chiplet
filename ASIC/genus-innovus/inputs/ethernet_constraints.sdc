#-----------------------------------------------------------------------------
#### ETHERNET (RMII) CLOCK DOMAINS + CDC CONSTRAINTS
#-----------------------------------------------------------------------------
# Before this block the entire ethernet clock tree was UNDEFINED in Genus, so
# every eth clock-domain-crossing (CDC) synchroniser was either unclocked or
# timed against the wrong launch clock. This section (a) creates the RMII ref
# clock + its two internally-generated MII clocks and (b) constrains the
# RMII/MII <-> system-clock (CLK) crossings.
#
# Topology  (nanosoc_chip_pads -> u_nanosoc_multicore_soc -> u_network_core):
#   RMII_REF_CLK pad -> soc_rmii_ref_clk -> u_network_core/u_rmii_to_mii, which
#   toggles the mrx_clk / mtx_clk registers every REFCLK edge => two 25 MHz MII
#   clocks (REFCLK/2). The MAC (u_ethmac_0/u_inner/u_eth_top), the RX checksum
#   snoop (u_ethmac_0/u_inner/u_eth_rx_cksum) and the PTP event detectors
#   (u_ethmac_0/u_inner/u_rx_ptp_det, u_tx_ptp_det) all run in the MII domain;
#   their register/CLK sides run in the CLK (system HCLK) domain.

set RMII_REF_PERIOD 20.0 ; # 50 MHz RMII reference (100BASE-TX); MII = REFCLK/2 = 25 MHz
set ETH_SS   "u_nanosoc_eth_chiplet_chip/u_soc/u_soc/u_network_core"
set RMII2MII "${ETH_SS}/u_rmii_to_mii"
set CKSUM    "${ETH_SS}/u_ethmac_0/u_inner/u_eth_rx_cksum"

create_clock -name "rmii_ref_clk" -period "$RMII_REF_PERIOD" -waveform "0 [expr $RMII_REF_PERIOD/2]" [get_ports RMII_REF_CLK]
# SPLIT -setup / -hold. This line used to be an unqualified
#     set_clock_uncertainty $CLK_ERROR [get_clocks rmii_ref_clk]
# which applies to BOTH checks, charging the whole RMII domain 0.35ns of HOLD
# margin — 7x what clk and swdclk are charged (0.05). $CLK_ERROR is oscillator
# JITTER: a real setup margin, but on a same-edge hold check the source jitter
# is common to launch and capture and largely cancels. constraints.sdc fixed
# exactly this for clk/swdclk and explains why at length; this file was missed.
#
# It matters here specifically: when the hold source-latency bug was fixed for
# `clk`, the worst hold path in the design relocated to rmii_ref_clk. Some of
# that is this line.
set_clock_uncertainty -setup $CLK_ERROR      [get_clocks rmii_ref_clk]
set_clock_uncertainty -hold  $CLK_HOLD_ERROR [get_clocks rmii_ref_clk]

# 25 MHz MII TX/RX clocks are generated (divide-by-2) INSIDE u_rmii_to_mii by
# toggling the mrx_clk / mtx_clk output registers -> declare them as generated
# clocks so CTS / timing see the real internal domain.
create_generated_clock -name "mii_rx_clk" -source [get_ports RMII_REF_CLK] -divide_by 2 [get_pins ${RMII2MII}/mrx_clk]
create_generated_clock -name "mii_tx_clk" -source [get_ports RMII_REF_CLK] -divide_by 2 [get_pins ${RMII2MII}/mtx_clk]

# GENERATED CLOCKS DO NOT INHERIT UNCERTAINTY. Verified empirically on the
# 2026-08-06 run: paths in these domains carry no `Uncertainty` line at all, so
# they were timed with ZERO margin on setup AND hold. Six of this design's nine
# clocks were in that state. Uncertainty must be stated per clock.
set_clock_uncertainty -setup $CLK_ERROR      [get_clocks mii_rx_clk]
set_clock_uncertainty -hold  $CLK_HOLD_ERROR [get_clocks mii_rx_clk]
set_clock_uncertainty -setup $CLK_ERROR      [get_clocks mii_tx_clk]
set_clock_uncertainty -hold  $CLK_HOLD_ERROR [get_clocks mii_tx_clk]

# RMII is source-synchronous to REFCLK at the pads. Conservative bring-up budget
# (tune for signoff); constrains the otherwise-floating RMII data pins.
# APPLIED 2026-08-07 — datasheet-correct values, replacing round placeholders.
# All four traced to Microchip LAN8720A DS00002165B Table 5-9 (RMII TIMING,
# REF_CLK OUT MODE — the governing table, since the PHY sources the 50MHz; see
# the REF_CLK DIRECTION note below).
#
# THE ONE THAT WAS A BUG, NOT JUST A PLACEHOLDER: set_output_delay -min was +2.
# `set_output_delay -min` is (board delay - far-end HOLD requirement). The PHY's
# tihold is 2.0ns and the trace delay is ~0, so the correct value is NEGATIVE.
# At +2 the tool believed we may release TX data 2ns BEFORE the capture edge,
# when the PHY needs it held 2ns AFTER — relaxing the RMII TX hold requirement
# by 4.0ns end to end, and reporting clean while doing it. Nothing errors or
# warns on a wrong-signed output delay; it just quietly hides the violation.
set_input_delay  -min  1.4 -clock [get_clocks rmii_ref_clk] [get_ports {RMII_RXD[*] RMII_CRS_DV}] ;# [DS] T5-9 tohold 1.4
set_input_delay  -max  8.0 -clock [get_clocks rmii_ref_clk] [get_ports {RMII_RXD[*] RMII_CRS_DV}] ;# [DS] T5-9 toval 5.0 + 3.0 trace
set_output_delay -min -2.0 -clock [get_clocks rmii_ref_clk] [get_ports {RMII_TXD[*] RMII_TX_EN}]  ;# [DS] T5-9 tihold 2.0, NEGATED
set_output_delay -max  8.0 -clock [get_clocks rmii_ref_clk] [get_ports {RMII_TXD[*] RMII_TX_EN}]  ;# [DS] T5-9 tsu 7.0 + 1.0 trace

#-----------------------------------------------------------------------------
#### BOARD-LEVEL I/O DRIVE + LOAD (these ports are CHIP PINS, not core ports)
#-----------------------------------------------------------------------------
# nanosoc_eth_chiplet_pads INCLUDES THE PAD RING, so every port below is a
# physical package pin. Before this block there was no set_input_transition and
# no set_load anywhere in the chiplet SDC: every RMII input was modelled with an
# INFINITELY SHARP edge and every RMII output as driving ZERO capacitance. For
# the clock pin Innovus says so out loud — IMPCCOPT-4313, "assume ... a fixed
# output slew of 0.000 and a maximum driven capacitance of 0.000" — and the
# shipped clock tree was built on exactly that assumption.
#
# set_driving_cell is deliberately NOT used: the driver is a Microchip LAN8720A
# out on the board, and set_driving_cell needs a lib_cell that exists in OUR
# libraries. set_input_transition states the arriving edge directly instead.
#
# SOURCES — every number below traces to one of these, cited inline:
#   [DS]    Microchip LAN8720A/LAN8720Ai datasheet, DS00002165B (2016)
#   [RMII]  RMII Consortium, "RMII Specification" Rev 1.2, 20-Mar-1998
#   [LIB]   tphn65lpgv2od3_slwc.lib (TSMC 65LP staggered IO, worst-case corner)
#   [BOARD] docs/KR260_BOARD_WIRING.md sec 3 "LAN8720 RMII PHY (milestone M2)"
# CONFIDENCE CLASS is marked on every value: (a) published datasheet/standard
# number, (b) engineering estimate DERIVED from datasheet facts, (c) labelled
# placeholder. Nothing below is class (b) or (c) presented as class (a).

# --- REF_CLK DIRECTION: RESOLVED — the PHY SOURCES the 50 MHz ----------------
# The LAN8720A is strappable either way (nINTSEL) and it selects which timing
# table governs, so this was checked rather than assumed:
#   * [BOARD] sec 3 "Clocking — the decision that matters most": "PHY-sourced —
#     this is what the Z2 build uses (REF_CLK_OUT mode). The module's 25 MHz
#     crystal drives an internal PLL and the nINT/REFCLKO pin outputs 50 MHz."
#   * [BOARD] sec 3 pin map: PMOD1 pin 10 = "nINT/REF_CLK (50 MHz out)"; the
#     signal-budget table lists rmii_ref_clk direction "in".
#   * docs/PIN_MAP.md sec 5d and ASIC/tech_wrappers/tsmc65/nanosoc_eth_chiplet_pads.v
#     agree: RMII_REF_CLK is `input wire`, pad PDDW04DGZ_G, tied to .PAD.
# => nINTSEL pulled LOW, REF_CLK OUT mode, so [DS] Table 5-9 "RMII TIMING VALUES
#    (REF_CLK OUT MODE)" is the governing table — NOT Table 5-10 (REF_CLK In
#    mode). This matters: the two tables disagree badly (toval 5.0 vs 14.0 ns,
#    tsu 7.0 vs 4.0 ns), so picking the wrong one mis-budgets BOTH directions.
# The 20.0 ns period in create_clock above agrees with [DS] Table 5-9 tclkp min
# 20 ns and [RMII] sec 7.4.1 "REF_CLK Frequency 50 MHz". (a)

# --- INPUT TRANSITION on the four PHY-driven pins ----------------------------
# Driver identity from the [DS] "Buffer Type" column (Table 2-1 RMII SIGNALS,
# Table 2-4 ETHERNET PINS), decoded by [DS] Table 2-9 BUFFER TYPES: REFCLKO,
# RXD0, RXD1 and CRS_DV are ALL "VO8" = "Variable voltage output with 8mA sink
# and 8mA source". One number covers all four because it is one buffer type.
#
# [DS] publishes NO digital output rise/fall time. The only "Signal Rise and
# Fall Time" in it (TRF 3.0-5.0 ns) is [DS] Table 5-5 100BASE-TX TRANSCEIVER
# CHARACTERISTICS — the ANALOG line side behind the magnetics, measured "at line
# side of transformer". That is NOT the RMII pins; do not recycle it here.
# The binding number is in the standard [DS] sec 5.5 Note 5-20 declares conformance
# to ("The RMII timing adheres to the RMII Consortium RMII Specification R1.2"):
#   [RMII] sec 7.4.3 Rise and Fall Time — "Output waveforms shall have a rise and
#   fall time between 1 and 5 ns. This shall be measured between the points on
#   the waveform which cross 0.8V and 2.0V."                              (a)
#
# THRESHOLD CONVERSION — mandatory; the two documents do not measure the same
# thing and using [RMII]'s number raw would be wrong by 2x.
#   [RMII] window = 2.0 - 0.8            = 1.2 V   (public RMII spec)
#   [LIB]  window = the .lib header's own slew-threshold percentages applied to
#          its nominal supply — read out of the header, not assumed, and wider
#          than the [RMII] window by exactly 2.0x
#     (threshold percentages and nom_voltage redacted — vendor .lib header,
#      TSMC licence forbids reproduction. Read them in tphn65lpgv2od3_sl*.lib.)
#   ratio 2.0x  =>  the RMII-legal 1-5 ns band is 2.0-10.0 ns in the
#   units this SDC is written in.
#
# ...but [LIB] CANNOT EVALUATE the top of that band. The pad-input slew axis is
# characterised over a handful of nanosecond-range points and the library
# declares a default_max_transition at its top end; a worst-case-legal RMII edge
# (10.0 ns here) sits past that last characterised point — pure extrapolation,
# i.e. a fabricated delay.
# (Liberty table name, slew-axis points and default_max_transition redacted —
# vendor characterisation data, TSMC licence forbids reproduction. Source:
# tphn65lpgv2od3_sl*.lib.) The values below are
# therefore the REALISTIC-LOAD case, with the worst case recorded as a trigger.
#
# Realistic case, derived from [DS] numbers (class (b), derivation shown so it
# can be checked): a VO8 buffer is specified at IOL/IOH = 8 mA ([DS] Table 5-4,
# "VO8 Type Buffers", VOL 0.4 V @ IOL = 8mA / VOH @ IOH = -8mA). Driving the
# light end of the load range [DS] Note 5-24 was designed for ("Timing was
# designed for system load between 10 pf and 25 pf"):
#     t(10-90%) ~ C*dV/I = 10 pF x 2.4 V / 8 mA = 3.0 ns
# Cross-check at the heavy end: 25 pF x 2.4 V / 8 mA = 7.5 ns, which lands right
# next to the 10.0 ns [RMII] ceiling — two independent documents agreeing is why
# 25 pF is the standard's design load. This uses the GUARANTEED DC current, so
# it is the slow bound; real transient drive is 2-3x higher and the true edge
# correspondingly faster. 3.0
set_input_transition -max 3.0 [get_ports {RMII_REF_CLK RMII_RXD[*] RMII_CRS_DV}] ; # (b) VO8 @8mA into 10pF, 10-90% @3.0V; = 1.5ns in [RMII] 0.8-2.0V terms, inside the 1-5ns band
# Hold direction: a FASTER input edge crosses the 50% input threshold sooner and
# so arrives earlier — the pessimistic direction for hold. 1.0 ns is 2x faster
# than any RMII-legal driver ([RMII] floor of 1 ns converts to 2.0 ns here), and
# needs no [LIB] interpolation. Deliberate pessimism: the header note above records
# that when the `clk` hold source-latency bug was fixed, the design's worst hold
# path RELOCATED INTO rmii_ref_clk. That domain should not be flattered.
set_input_transition -min 1.0 [get_ports {RMII_REF_CLK RMII_RXD[*] RMII_CRS_DV}] ; # (b) faster than RMII-legal on purpose = pessimistic for hold
#
# REVISIT TRIGGER (write it down now; it is invisible later): [RMII] sec 7.4.1
# sizes its load to accommodate "over 12 inches of PCB trace". If the RMII run
# to the PHY is long, the arriving edge degrades toward 7.5-10 ns, at which
# point this constraint is BOTH optimistic AND unrepresentable in [LIB]
# (ceiling 5.0). The remedy is a board fix, not an SDC fix — cf. [BOARD] sec 3
# gotchas, "Keep RMII leads short. 50 MHz on flying leads is already marginal".

# --- OUTPUT LOAD on the pins we drive into the PHY ---------------------------
# Receiver identity from [DS] Table 2-1 (RMII SIGNALS) and Table 2-3 (SMI PINS),
# decoded by [DS] Table 2-9: TXD0, TXD1, TXEN and MDC are all "VIS" = "Variable
# voltage Schmitt-triggered input". Their capacitance is published:
#   [DS] Table 5-4 VARIABLE I/O BUFFER CHARACTERISTICS, VIS Type Input Buffer,
#   "Input Capacitance  CIN  ...  max 2  pF"  (Note 5-14: "This specification
#   applies to all inputs and tri-stated bi-directional pins.")           (a)
# But 2 pF is the far-end receiver ALONE. set_load must carry receiver +
# package + PCB trace, and the standard states that total outright:
#   [RMII] sec 7.4.1 AC Load — "Output drivers shall be capable of meeting the
#   output requirements while driving a 25pF or greater load. This loading
#   accommodates over 12 inches of PCB trace and input capacitance of the
#   receiving device."                                                    (a)
# [DS] independently adopts the same figure for its own output specs: sec 5.5.1
# EQUIVALENT TEST LOAD, "Output timing specifications assume a 25pF equivalent
# test load" (Figure 5-1). So 25 pF is the DESIGN LOAD OF THE STANDARD, not a
# round number someone liked — and it also lands on a characterised point of
# [LIB]'s output-load axis, so no extrapolation. (Liberty table names and
# load-axis points redacted — vendor characterisation data, TSMC licence forbids
# reproduction. Read them in tphn65lpgv2od3_sl*.lib.)
# Decomposition for the record: 2 pF PHY VIS CIN (a) + ~1 pF package/bondwire
# (b — no package model exists in this repo yet) + the balance as the
# [RMII]-mandated trace headroom.
# These four pins are driven by PDDW16DGZ_G (16 mA) in
# ASIC/tech_wrappers/tsmc65/nanosoc_eth_chiplet_pads.v — already the strongest
# driver in the ring. 25 pF is the load that choice was presumably made for.
set_load -max 25.0 [get_ports {RMII_TXD[*] RMII_TX_EN RMII_MDC RMII_MDIO}] ; # (a) [RMII] 7.4.1 AC Load = 25pF; == [DS] 5.5.1 test load
# Hold uses the LIGHT load: least output delay, earliest arrival, worst hold at
# the PHY. 5 pF = 2 pF CIN (a) + package + a short trace (b).
set_load -min  5.0 [get_ports {RMII_TXD[*] RMII_TX_EN RMII_MDC RMII_MDIO}] ; # (b) light-load case for hold; 2pF CIN + package + short trace

# --- RMII_MDIO is bidirectional, and its INPUT edge is RC-LIMITED ------------
# MDIO is `inout wire` on a PDDW16DGZ_G in the pad wrapper, so it needs BOTH a
# load (above, for when we drive) and a transition (here, for when the PHY
# drives). The PHY side is [DS] Table 2-3, "MDIO ... VIS/VOD8", and [DS] Table
# 2-9 defines VOD8 as "Variable voltage OPEN-DRAIN output with 8mA sink". An
# open-drain output can only PULL DOWN: the RISING edge is manufactured by the
# external pull-up resistor, so it is an RC ramp, not a buffer edge —
#     t(10-90%) ~ 2.2*R*C :  1.5 kohm into 25 pF ~  82 ns
#                            10  kohm into 25 pF ~ 550 ns
# one to two ORDERS OF MAGNITUDE outside [LIB]'s max-transition ceiling. There is no
# honest set_input_transition for this pin. The value below is a CLAMP at the
# library maximum and is class (c) PLACEHOLDER — it is NOT the real edge and
# must not be quoted as one. It is stated only because it is strictly less wrong
# than the 0.0 (infinitely sharp) it replaces. The correct treatment is to
# declare the SMI boundary asynchronous; this file does not currently do that.
# (docs/PIN_MAP.md sec 5d already notes mdio "Typically needs external pull-up" —
# no pull-up value is fixed anywhere in this repo, hence the range above.)
set_input_transition -max 5.0 [get_ports RMII_MDIO] ; # (c) PLACEHOLDER clamped at the library max-transition ceiling; true rising edge is RC, ~82-550ns
set_input_transition -min 1.0 [get_ports RMII_MDIO] ; # (b) the FALLING edge really is buffer-driven (VOD8 sinks 8mA); pessimistic-for-hold

#=============================================================================
# SMI (RMII_MDC / RMII_MDIO)  —  THE CLOCK DECISION
#=============================================================================
# Added 2026-08-17. Finding 3 in the block below flagged that these two pins
# "carry no set_input_delay or set_output_delay at all", called them "a genuine
# candidate for an asynchronous/false-path declaration rather than a timed
# budget", and then left it — correctly, since that block's scope was drive and
# load. This is that declaration. It follows THE CLOCK DECISION in
# i2c_constraints.sdc, which argues an almost identical case at length; the
# structure below is deliberately the same so the two can be read together.
#
# WHAT WAS AND WAS NOT MISSING. Checked, because the gap is narrower than
# "unconstrained" suggests and it decides what to add:
#   * set_load              ALREADY PRESENT for both, in the block above
#                           (25 pF max / 5 pF min, [RMII] 7.4.1 AC load).
#   * set_input_transition  ALREADY PRESENT for RMII_MDIO, above.
#                           RMII_MDC needs none: it is `output wire` on the pad
#                           ring (nanosoc_eth_chiplet_pads.v:68), instantiated
#                           PDDW16DGZ_G uPAD_RMII_MDC with .C() unconnected and
#                           .OEN(tielo) — permanently driving, no input arc.
#   * ANY TIMING STATEMENT  ABSENT for both. That, and only that, is what
#                           follows.
#
# WHY "ABSENT" IS THE PROBLEM, MEASURED RATHER THAN ASSERTED. In the shipped
# run's check_timing, these two pins are indistinguishable from I2C_SCL/I2C_SDA,
# which ARE fully declared asynchronous:
#     RMII_MDIO   No input delay assertion with respect to clock   (both views)
#     RMII_MDIO   Unconstrained signal arriving at end point       (both views)
#     RMII_MDC    Unconstrained signal arriving at end point       (both views)
#       (reports/check_timing_03_cts_opt.rep:37-38, 7131-7132, 7614-7615)
#     I2C_SCL     ... the identical three entries at :5377-5380, :8097-8098
# So the timing report CANNOT TELL "deliberately not timed, here is why" from
# "nobody looked". Declaring the boundary does not change what the tool computes
# and it will not make those lines go away. It changes what the constraint set
# RECORDS, which is the whole of the difference — the same argument the i2c file
# makes, now with the measurement that proves the report is no help.
#
# NOTHING IN THIS DESIGN CLOCKS OFF MDC, AND MDC IS NOT A CLOCK — IT IS A
# REGISTER OUTPUT IN THE CLK DOMAIN. From the RTL, verified not assumed
# ($ETHMAC_IP_DIR = ${ARM_IP_LIBRARY_PATH}/OpenCores-EthMAC, rtl/verilog):
#   eth_clockgen.v   always @(posedge Clk or posedge Reset)
#                      if (CountEq0) Mdc <= ~Mdc;
#   eth_clockgen.v   assign MdcEn   = CountEq0 & ~Mdc;
#                    assign MdcEn_n = CountEq0 &  Mdc;
#   eth_top.v:376    eth_miim ... .Clk(wb_clk_i), .Divider(r_ClkDiv)
# MDC is a flop output on the WB/system clock, and MdcEn/MdcEn_n are ONE-CLK
# ENABLE PULSES, not clocks. Every `always` block in eth_miim.v is
# `posedge Clk` — all eight of them (:192, :208, :222, :257, :285, :304, :359,
# :391) — and there is not one `posedge Mdc` or `negedge Mdc` in the file. The
# two submodules that touch the wire take the same clock:
#   eth_miim.v:432   eth_shiftreg      shftrg  (.Clk(Clk), .MdcEn_n(MdcEn_n), ...)
#   eth_miim.v:438   eth_outputcontrol outctrl (.Clk(Clk), .MdcEn_n(MdcEn_n), ...)
# A create_clock on RMII_MDC would therefore be a clock with ZERO SINK
# REGISTERS: it would propagate nowhere, generate no real check, add a
# fictitious domain to MMMC, and invite CTS to build a tree backwards out of an
# output pad. That is the same conclusion, for the same reason, that
# i2c_constraints.sdc reaches for I2C_SCL.
#
# AND A create_generated_clock WOULD BE WORSE, BECAUSE THE RATIO IS SOFTWARE.
# The divider is not a constant:
#   eth_clockgen.v   TempDivider   = (Divider < 2) ? 8'h02 : Divider
#                    CounterPreset = (TempDivider >> 1) - 1      ; # half period
#   => MDC period = TempDivider Clk cycles,  Fmdc = Fclk / Divider
# `Divider` is r_ClkDiv = MIIMODER[7:0], a writable register whose POR default
# is 8'h64 = 100 (eth_defines.v:228, ETH_MIIMODER_DEF_0). At clk = 100 MHz that
# is MDC = 1 MHz, period 1000 ns — but software may write anything from 2
# upward, and a -divide_by written here would be true only at whichever value
# happened to be in the register the day it was written. THAT IS EXACTLY THE
# [C3] DEFECT DOCUMENTED IN qspi_constraints.sdc, where -divide_by 2 holds only
# at a 5-bit register's reset value. One instance of it in this constraint set
# is one too many; do not add a second.
#
# THE REAL REQUIREMENT ON THIS INTERFACE IS PROTOCOL, NOT STATIC TIMING, AND THE
# MARGIN IS THREE TO FOUR ORDERS OF MAGNITUDE. From [DS] Table 5-12 (already
# quoted in finding 3 below): MDC period min 400 ns (2.5 MHz ceiling); MDIO
# tsu 10 ns; MDIO tihold 10 ns; MDIO tval max 300 ns.
#   * MDIO OUT is launched on MdcEn_n, i.e. HALF an MDC period before the MDC
#     rising edge that the PHY captures on: 500 ns at the POR divider of 100,
#     and >= 200 ns even at the 2.5 MHz protocol ceiling. Against a 10 ns tsu
#     and a 10 ns tihold that is 20-50x margin, and it is created by the
#     divider, not by placement. Breaking it would take ~200 ns of pad-to-pad
#     skew between two pads on the same edge of a 1600x2000um die.
#   * MDIO IN is launched by the PHY off the MDC WE generate, up to 300 ns
#     later (tval), and sampled back in the Clk domain by eth_shiftreg
#     (`ShiftReg[7:0] <= {ShiftReg[6:0], Mdi}` on posedge Clk, gated by
#     MdcEn_n — eth_shiftreg.v:104,128). Its arrival is bounded relative to an
#     MDC edge whose position in clk cycles is set by a writable register.
# There is consequently NO honest clk-referenced arrival window to state, and no
# placement or routing decision that a timing constraint could usefully steer.
#
# NO set_input_delay / set_output_delay IS WRITTEN, DELIBERATELY — same reason
# as i2c_constraints.sdc. Both commands require a -clock. The only two candidates
# are a create_clock on MDC (argued above: zero sinks, software ratio, fiction)
# or `clk` itself (which would assert an arrival window measured in clk cycles
# that no document bounds and the divider makes meaningless). Writing a delay
# AND a false path on the same port would also reproduce, in a new place, the
# dead-constraint contradiction that [C5] below exists to clear out: the false
# path wins on exception priority and the delay is inert but still reads as
# intent. One mechanism.
#
# SCOPE — the exceptions are narrow on purpose, exactly as the i2c ones are.
# `-to` on RMII_MDC and RMII_MDIO selects only paths that END at the pad
# (MIIM flop -> pad). `-from` on RMII_MDIO selects only paths that START there
# (pad -> eth_shiftreg). Every Clk-to-Clk path inside eth_miim, eth_shiftreg and
# eth_outputcontrol stays fully timed by the $EXTCLK create_clock in
# constraints.sdc. Nothing here relaxes the MIIM itself.
set_false_path -to   [get_ports RMII_MDC]
set_false_path -to   [get_ports RMII_MDIO]
set_false_path -from [get_ports RMII_MDIO]
#
# WARNINGS — READ BEFORE SIGNOFF. NONE OF THESE IS FIXED BY THE LINES ABOVE.
#
# S1. THE 2.5 MHz CEILING IS ENFORCED BY SOFTWARE ONLY. The RTL clamps Divider
#     at the BOTTOM (`(Divider<2) ? 8'h02 : Divider`) and nowhere else, so a
#     write of MIIMODER[7:0] = 2 produces a 50 MHz MDC — 20x past [DS] Table
#     5-12's 400 ns minimum period, and past the point where the half-period
#     margin argument above holds. The POR value of 100 is safe (1 MHz at
#     clk = 100 MHz) and the driver must keep Divider >= 40 at this clock. Not
#     expressible in SDC; it belongs in the MIIM driver and in a bring-up check.
#
# S2. MDIO IS SAMPLED THROUGH A SINGLE FLOP, WITH NO SYNCHRONISER.
#     eth_shiftreg.v:128 shifts `Mdi` straight into ShiftReg on posedge Clk.
#     The far end is the PHY responding to our own MDC, so the exposure is a
#     turnaround-edge sample rather than a free-running asynchronous input, and
#     the ~100:1 oversampling means a metastable bit costs at most one clk of
#     edge placement. Recorded because it is a real single-stage sample on an
#     off-chip input, the false path above is what makes it invisible to STA,
#     and a CDC audit should find it declared rather than discover it. Same
#     class as WARNING 5 in i2c_constraints.sdc. RTL issue, not an SDC one.
#
# S3. UNBOUNDED ROUTE ON THE FALSE-PATHED PADS. A false path lets the router
#     take an arbitrarily long route pad-to-flop. At >= 200 ns of protocol
#     margin that is unreachable by anything this floorplan can produce. If a
#     future revision wants the router held to a number anyway, the correct tool
#     is set_max_delay on these same -from/-to sets, NOT a create_clock. Note
#     that DRV is unaffected by false paths, so the 25 pF / 5 pF set_load above
#     and the design-wide set_max_capacitance still bind on both pins.
#
# S4. THE MDIO set_input_transition ABOVE REMAINS A CLASS (c) CLAMP and these
#     exceptions do not upgrade it. With the pad-to-flop path false-pathed it
#     now feeds DRV only, which is the same position i2c_constraints.sdc reaches
#     for I2C_SCL/I2C_SDA. It is still not the real RC edge.

# --- CONSISTENCY CHECK of the EXISTING input/output delays (FLAGGED, NOT ------
# --- CHANGED) ----------------------------------------------------------------
# The four delay constraints above predate this block and are self-labelled
# "Conservative bring-up budget (tune for signoff)". They are deliberately left
# untouched. But now that the governing table is pinned down ([DS] Table 5-9,
# REF_CLK OUT mode — see the direction resolution above), two of the four are
# NOT conservative. Recorded here so the next person cannot miss it:
#
#   [DS] Table 5-9, RMII TIMING VALUES (REF_CLK OUT MODE)          (all class a)
#     toval   RXD[1:0], RXER, CRS_DV output valid from rising edge   max 5.0 ns
#     tohold  RXD[1:0], RXER, CRS_DV output hold  from rising edge   min 1.4 ns
#     tsu     TXD[1:0], TXEN setup time to rising edge               min 7.0 ns
#     tihold  TXD[1:0], TXEN input hold time after rising edge       min 2.0 ns
#     (Note 5-24: "Timing was designed for system load between 10 pf and 25 pf")
#
# INPUTS — PHY launches, we capture; required value = external Tco + trace:
#   -max 8  vs toval 5.0 + trace   -> fine, ~3 ns of trace allowance. Keep.
#   -min 2  vs tohold 1.4 + trace  -> OPTIMISTIC by ~0.6 ns. RXD/CRS_DV may
#           legally still hold the PREVIOUS cycle's value until 1.4 ns after the
#           edge; declaring 2.0 hides 0.6 ns of real hold requirement.
#
# OUTPUTS — we launch, PHY captures. This is the serious one:
#   -max 8  vs tsu 7.0 + trace     -> only ~1 ns of board allowance left. Worth
#           knowing that the PHY is far harsher than the standard here: [RMII]
#           sec 7.4.1 asks Tsu 4 ns, [DS] Table 5-9 demands 7.0 ns. Tight, not
#           wrong. Keep, but do not spend that 1 ns elsewhere.
#   -min 2  vs tihold 2.0          -> *** WRONG SIGN ***. tihold is a HOLD
#           requirement AT THE PHY PIN: TXD/TXEN must remain stable for 2.0 ns
#           AFTER the REFCLKO rising edge. An external hold requirement Th is
#           entered in SDC as set_output_delay -min -Th, i.e. -min -2.0. With
#           +2.0 the tool believes the data may change 2 ns BEFORE the edge, so
#           the RMII TX hold requirement is relaxed by 4.0 ns end to end (from
#           "hold until edge+2" to "hold until edge-2"). Nothing in the flow
#           flags this — it reports as clean hold. It is silicon risk on RMII
#           TX, and it lands precisely where the header note above says the
#           design's worst hold path relocated to.
#
# ADOPTED 2026-08-07 — the four lines below are now live above. Retained here
# as the derivation record:
#   set_input_delay  -min  1.4 -clock [get_clocks rmii_ref_clk] [get_ports {RMII_RXD[*] RMII_CRS_DV}] ; # [DS] T5-9 tohold 1.4
#   set_input_delay  -max  8.0 -clock [get_clocks rmii_ref_clk] [get_ports {RMII_RXD[*] RMII_CRS_DV}] ; # [DS] T5-9 toval 5.0 + 3.0 trace
#   set_output_delay -min -2.0 -clock [get_clocks rmii_ref_clk] [get_ports {RMII_TXD[*] RMII_TX_EN}]  ; # [DS] T5-9 tihold 2.0, NEGATED
#   set_output_delay -max  8.0 -clock [get_clocks rmii_ref_clk] [get_ports {RMII_TXD[*] RMII_TX_EN}]  ; # [DS] T5-9 tsu 7.0 + 1.0 trace

# --- Three smaller findings, none actioned here ------------------------------
# 1. $CLK_ERROR (0.35) is documented in constraints.sdc as "worst case
#    characteristics of CDCM61001 low-jitter oscillator chip at 250MHz". That
#    part does not drive this clock: rmii_ref_clk is the LAN8720A REFCLKO PLL
#    output off a 25 MHz crystal. [DS] publishes no REFCLKO output jitter; the
#    nearest figure is [DS] Table 5-11 "CLKIN Jitter ... 150 psec p-p", which is
#    what the PHY REQUIRES of an incoming REF_CLK, not what it emits. 0.35 ns is
#    >2x that, so the setup margin is conservative and is left alone — but its
#    provenance is a different part, and that should be said out loud.
# 2. create_clock above uses an ideal 50/50 waveform. Real duty is [DS] Table
#    5-9 tclkh/tclkl = tclkp*0.4 .. tclkp*0.6 (8-12 ns), and [RMII] sec 7.4.1
#    permits 35-65%. Harmless for the /2 MII generation (single-edge toggle),
#    but any negedge-triggered logic in the RMII domain is currently timed
#    against an edge that can legally move +/-2 ns.
# 3. CLOSED 2026-08-17 — see the SMI (RMII_MDC / RMII_MDIO) THE CLOCK DECISION
#    block above, which acted on this finding. The finding as written:
#    "RMII_MDC / RMII_MDIO carry no set_input_delay or set_output_delay at all.
#    SMI is slow and software-timed ([DS] Table 5-12: MDC period min 400 ns =
#    2.5 MHz max; MDIO tsu 10 ns, tihold 10 ns, tval max 300 ns), so it is a
#    genuine candidate for an asynchronous/false-path declaration rather than a
#    timed budget — but 'no constraint at all' is not the same thing as
#    'declared asynchronous'. Flagged; outside this block's drive/load scope."
#    The conclusion it reached was the right one and is the one implemented: an
#    explicit asynchronous declaration, no create_clock, no invented delays.
#    The [DS] Table 5-12 numbers quoted here are the ones that block argues from.
#-----------------------------------------------------------------------------

#############################################################################
# [C5] CDC 1 / 2 / 3 ARE DEAD CODE. NEUTRALISED 2026-08-17.
#      THE "max-robustness alternative" NOTED AT THE BOTTOM OF THIS BLOCK WAS
#      ALREADY IN FORCE — IT JUST LIVES IN constraints.sdc, NOT HERE.
#############################################################################
#
# THE DECISION: THIS CONSTRAINT SET USES set_clock_groups, NOT PER-PAIR
# EXCEPTIONS, TO DECLARE ITS ASYNCHRONOUS BOUNDARIES. ONE MECHANISM. See the
# matching [C5] block in constraints.sdc, which retires the SWD half of the same
# problem. Every clock-to-clock cut in this design is expressed once, in
# `set_clock_groups -asynchronous -name eth_chiplet_cdc`.
#
# WHY THE THREE BLOCKS BELOW ARE DEAD. constraints.sdc groups
#     -group [get_clocks [list $EXTCLK QSPI_SCLK QSPI_SCLK_o]]
#     -group [get_clocks {rmii_ref_clk mii_rx_clk mii_tx_clk}]
# so the ENTIRE RMII/MII family is cut from clk in BOTH directions, including
# the mii_rx -> clk direction CDC 1 deliberately left timed. That subsumes:
#   * CDC 1's two set_false_paths      — restatements of a cut already made.
#   * CDC 2's seven targeted exceptions — every one of them is a mii_rx -> clk
#     crossing, and every one is inside the cut.
#   * CDC 3's last_push_flags multicycle — NOT merely redundant, EXTINGUISHED.
#     set_clock_groups -asynchronous means reciprocal false paths, and false
#     path outranks multicycle at the top of the SDC exception priority ladder.
#     The 2/1 relaxation has never been what the tool applied.
#
# ORDERING IS A RED HERRING AND IT MATTERS THAT YOU KNOW. It is tempting to
# reason "constraints.sdc sources this file first, so its later group wins".
# Exception PRIORITY, not file order, is what decides this: a false path beats a
# multicycle wherever either is written. Re-ordering the source lines would
# change nothing.
#
# THIS IS THE ALTERNATIVE THIS FILE ALREADY ENDORSED. The closing note of the
# original CDC 3 block described precisely this configuration —
#   "if a name-free, guaranteed-complete cut of the mii_rx->CLK boundary is
#    preferred over the verified last_push_flags MCP, replace CDC 2+3 with a
#    single async clock group ... That is safe (last_push_flags is held stable
#    for a whole frame vs a ~2-cycle toggle resync) but converts last_push_flags
#    from a timed MCP into a false path."
# — and judged it SAFE, with the reason. That configuration has been in force
# since the group was added. The only thing that was missing was anyone saying
# so, while three blocks of live-looking constraint said otherwise.
#
# THE COMMENT THAT WAS WRONG, CORRECTED HERE RATHER THAN LEFT IN PLACE. CDC 1
# ended: "(CLK<->SWDCLK is intentionally NOT grouped so the existing SWD
# multicycle/false-path block above is preserved.)" That was wrong twice.
# First, THIS file not grouping swdclk preserves nothing, because constraints.sdc
# puts $SWDCLK in a group of its own and cuts the pair anyway. Second, even had
# the intent been achievable, ordering could not have achieved it — see above.
# The SWD block it believed it was protecting is itself dead, and is neutralised
# in constraints.sdc under the same [C5].
#
# WHAT THIS COSTS AND WHAT IT DOES NOT. For every mii_rx -> clk crossing this is
# a NO-OP against the shipped database: build/full-20260814 was placed, CTS'd
# and routed with those paths cut by the group, not by these lines.
#
# ONE HONEST CAVEAT, BECAUSE IT IS THE ONLY WAY THE NEXT RUN CAN DIFFER. Four of
# CDC 2's exceptions were written as `-to <pin>` or `-to <cell>` with NO `-from`.
# An unqualified `-to` cuts paths ENDING there from EVERY launch clock, not just
# from mii_rx — so wherever one of those synchroniser flops also has a clk-domain
# endpoint (a clear/set pin, a clock-gate enable), that clk -> clk path was being
# cut too, silently and with no stated intent. Removing them RE-TIMES those, and
# a small number of new endpoints may appear. THAT IS THE SAFE DIRECTION and
# they are real clk-domain paths that should always have been timed. If any of
# them violates, fix it or false-path it deliberately with both -from and -to;
# do not restore a blanket `-to`.
#
# IF YOU EVER DO WANT THE last_push_flags MCP BACK, the correct edit is to
# remove the {rmii_ref_clk mii_rx_clk mii_tx_clk} group from constraints.sdc's
# set_clock_groups AND re-enable CDC 1/2/3 here in the same change. The RTL
# reasoning recorded in the original CDC 3 block is preserved verbatim below and
# is still correct; it is the mechanism, not the analysis, that was retired.
#
# --- CDC 1 (retired) — wholly-asynchronous directions (RMII/MII family <-> CLK)
# The RMII ref clock and its two /2 children are MUTUALLY SYNCHRONOUS (one
# source) and stay timed relative to each other (rmii_ref->mii_rx carries the
# real mrxd/mrxdv datapath; mii_rx<->mii_tx are synchronous siblings). They are
# asynchronous to CLK. Two of the three cross-domain directions carry NO path we
# need to keep timed, so cut them wholesale by clock (robust, name-free):
#   * CLK -> family  : every system-side control synchroniser first stage
#     (eth_rx_cksum ctrl_en/ctrl_mode/rptr_gray syncs; OpenCores MAC WB->MRx/MTx
#     syncs e.g. RxAbortSyncb / WriteRxDataToFifoSync / TxStartFrm_sync).
#   * {ref,mii_tx} -> CLK : every TX/ref-side crossing (OpenCores MAC TX status
#     + TX-FIFO syncs TxRetrySync/TxAbortSync/TxDoneSync/ReadTxDataFromFifo_sync,
#     and the u_tx_ptp_det TX event strobe -> PHC).
# The mii_rx -> CLK direction was left timed here for CDC 3's sake.
# set_false_path -from [get_clocks clk] -to [get_clocks {rmii_ref_clk mii_rx_clk mii_tx_clk}]
# set_false_path -from [get_clocks {rmii_ref_clk mii_tx_clk}] -to [get_clocks clk]
#
# --- CDC 2 (retired) — mii_rx -> CLK correctly-synchronised crossings
# Cut ONLY the metastability-capture flops so the last_push_flags MCP (CDC 3)
# survives on the same clock pair. eth_rx_cksum (exact paths, RTL-verified):
# set_false_path -to [get_pins ${CKSUM}/wptr_gray_pclk_s0_reg\[*\]/D] ; # gray write-pointer sync (async FIFO)
# set_false_path -to [get_pins ${CKSUM}/ovf_tog_pclk_s0_reg/D]      ; # overflow toggle synchroniser
# set_false_path -to [get_pins ${CKSUM}/push_tog_pclk_s0_reg/D]     ; # push  toggle synchroniser
# set_false_path -from [get_cells ${CKSUM}/fifo_mem_reg*] -to [get_clocks clk] ; # async FIFO memory read (mrx write -> pclk peek/prdata)
# OpenCores MAC (u_eth_top) MRxClk->WB(CLK) crossings + PTP RX event:
# set_false_path -to [get_cells -hierarchical -filter {name =~ *RxAbortSync1_reg}]               ; # RX abort MRx->WB sync
# set_false_path -to [get_cells -hierarchical -filter {name =~ *RxStatusWriteLatched_sync1_reg}] ; # RX status/frame-done MRx->WB sync
# set_false_path -from [get_cells -hierarchical -filter {name =~ *RxDataLatched2_reg*}] -to [get_clocks clk] ; # RX data (MRx) -> bd_ram (WB)
# set_false_path -from [get_cells ${ETH_SS}/u_ethmac_0/u_inner/u_rx_ptp_det/ptp_event_reg] -to [get_clocks clk] ; # eth_rx_ptp_event -> PHC
#
# --- CDC 3 (retired) — eth_rx_cksum last_push_flags data-with-toggle
# last_push_flags_mrx[7:0] is latched in mii_rx_clk on the SAME edge that flips
# push_tog_mrx; the CLK-side counters read it only AFTER push_tog resynchronises
# through push_tog_pclk_s0/s1/s2 (edge = s1^s2), i.e. >= 2 CLK cycles later. It
# is a REAL data path (the flags are consumed) whose setup may be relaxed to 2
# destination cycles — a set_multicycle_path, NOT a false path. last_push_flags
# fans out ONLY to the five CLK-domain counters (frame_count_q / ip_good_q /
# ip_bad_q / l4_good_q / l4_bad_q), so "-to CLK" targets exactly this crossing.
# THE ANALYSIS ABOVE STANDS; only the mechanism is retired. Under the group the
# crossing is a false path instead, which the note below judged safe because
# last_push_flags is held stable for a whole frame against a ~2-cycle resync.
# set_multicycle_path 2 -setup -end -from [get_cells ${CKSUM}/last_push_flags_mrx_reg\[*\]] -to [get_clocks clk]
# set_multicycle_path 1 -hold  -end -from [get_cells ${CKSUM}/last_push_flags_mrx_reg\[*\]] -to [get_clocks clk]
#############################################################################
#
# ${ETH_SS} and ${CKSUM} are now referenced only from the retired blocks above.
# They are LEFT DEFINED at the top of this file on purpose: they document the
# hierarchy this file was written against, and re-enabling any block needs them.

