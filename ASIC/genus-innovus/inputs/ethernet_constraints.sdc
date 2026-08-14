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
# correspondingly faster. 3.0 ns also needs no interpolation in [LIB].
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
set_load -max 25.0 [get_ports {RMII_TXD[*] RMII_TX_EN RMII_MDC RMII_MDIO}] ; # (a) [RMII] 7.4.1 AC Load = 25pF; == [DS] 5.5.1 test load; needs no [LIB] interpolation
# Hold uses the LIGHT load: least output delay, earliest arrival, worst hold at
# the PHY. 5 pF = 2 pF CIN (a) + package + a short trace (b); low end of [LIB].
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
# 3. RMII_MDC / RMII_MDIO carry no set_input_delay or set_output_delay at all.
#    SMI is slow and software-timed ([DS] Table 5-12: MDC period min 400 ns =
#    2.5 MHz max; MDIO tsu 10 ns, tihold 10 ns, tval max 300 ns), so it is a
#    genuine candidate for an asynchronous/false-path declaration rather than a
#    timed budget — but "no constraint at all" is not the same thing as
#    "declared asynchronous". Flagged; outside this block's drive/load scope.
#-----------------------------------------------------------------------------

### CDC 1 — wholly-asynchronous directions (RMII/MII family <-> CLK)
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
# The mii_rx -> CLK direction is deliberately LEFT TIMED here because it carries
# the eth_rx_cksum last_push_flags data-with-toggle path we want to keep as a
# (relaxed) multicycle — see CDC 3. Its correctly-synchronised crossings are cut
# individually in CDC 2. (CLK<->SWDCLK is intentionally NOT grouped so the
# existing SWD multicycle/false-path block above is preserved.)
set_false_path -from [get_clocks clk] -to [get_clocks {rmii_ref_clk mii_rx_clk mii_tx_clk}]
set_false_path -from [get_clocks {rmii_ref_clk mii_tx_clk}] -to [get_clocks clk]

### CDC 2 — mii_rx -> CLK correctly-synchronised crossings (targeted false paths)
# Cut ONLY the metastability-capture flops so the last_push_flags MCP (CDC 3)
# survives on the same clock pair. eth_rx_cksum (exact paths, RTL-verified):
set_false_path -to [get_pins ${CKSUM}/wptr_gray_pclk_s0_reg\[*\]/D] ; # gray write-pointer sync (async FIFO)
set_false_path -to [get_pins ${CKSUM}/ovf_tog_pclk_s0_reg/D]      ; # overflow toggle synchroniser
set_false_path -to [get_pins ${CKSUM}/push_tog_pclk_s0_reg/D]     ; # push  toggle synchroniser
set_false_path -from [get_cells ${CKSUM}/fifo_mem_reg*] -to [get_clocks clk] ; # async FIFO memory read (mrx write -> pclk peek/prdata)
# OpenCores MAC (u_eth_top) MRxClk->WB(CLK) crossings + PTP RX event. Leaf names
# are RTL-verified; deep hierarchy is matched with -hierarchical (confirm the
# set is complete post-elaboration — see review note):
set_false_path -to [get_cells -hierarchical -filter {name =~ *RxAbortSync1_reg}]               ; # RX abort MRx->WB sync
set_false_path -to [get_cells -hierarchical -filter {name =~ *RxStatusWriteLatched_sync1_reg}] ; # RX status/frame-done MRx->WB sync
set_false_path -from [get_cells -hierarchical -filter {name =~ *RxDataLatched2_reg*}] -to [get_clocks clk] ; # RX data (MRx) -> bd_ram (WB), gated by the synced write enable
set_false_path -from [get_cells ${ETH_SS}/u_ethmac_0/u_inner/u_rx_ptp_det/ptp_event_reg] -to [get_clocks clk] ; # eth_rx_ptp_event (mii_rx) -> PHC eth_rx_capture (CLK)

### CDC 3 — eth_rx_cksum last_push_flags data-with-toggle (MULTICYCLE, not cut)
# last_push_flags_mrx[7:0] is latched in mii_rx_clk on the SAME edge that flips
# push_tog_mrx; the CLK-side counters read it only AFTER push_tog resynchronises
# through push_tog_pclk_s0/s1/s2 (edge = s1^s2), i.e. >= 2 CLK cycles later. It
# is a REAL data path (the flags are consumed) whose setup may be relaxed to 2
# destination cycles — a set_multicycle_path, NOT a false path. last_push_flags
# fans out ONLY to the five CLK-domain counters (frame_count_q / ip_good_q /
# ip_bad_q / l4_good_q / l4_bad_q), so "-to CLK" targets exactly this crossing.
# Multiplier 2/1 mirrors the toggle's >=2-cycle handshake and the SWDCK->CLK
# idiom above (-end = relax on the capturing CLK).
set_multicycle_path 2 -setup -end -from [get_cells ${CKSUM}/last_push_flags_mrx_reg\[*\]] -to [get_clocks clk]
set_multicycle_path 1 -hold  -end -from [get_cells ${CKSUM}/last_push_flags_mrx_reg\[*\]] -to [get_clocks clk]

# NOTE (max-robustness alternative): if a name-free, guaranteed-complete cut of
# the mii_rx->CLK boundary is preferred over the verified last_push_flags MCP,
# replace CDC 2+3 with a single async clock group and drop the -to clk direction
# from CDC 1:
#   set_clock_groups -asynchronous \
#     -group [get_clocks {rmii_ref_clk mii_rx_clk mii_tx_clk}] -group [get_clocks clk]
# That is safe (last_push_flags is held stable for a whole frame vs a ~2-cycle
# toggle resync) but converts last_push_flags from a timed MCP into a false path.

