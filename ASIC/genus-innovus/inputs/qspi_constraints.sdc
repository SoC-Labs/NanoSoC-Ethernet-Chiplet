# QSPI CLocks
create_generated_clock -name "QSPI_SCLK" -source [get_ports CLK] -divide_by 2 [get_pins u_nanosoc_eth_chiplet_chip/u_soc/u_soc/u_qspi_flash_0/u_top_ahb_qspi/u_qspi_clock_div/QSPI_SCLK_i]
create_generated_clock -name "QSPI_SCLK_o" -source [get_pins u_nanosoc_eth_chiplet_chip/u_soc/u_soc/u_qspi_flash_0/u_top_ahb_qspi/u_qspi_clock_div/QSPI_SCLK_i] -divide_by 1 [get_ports QSPI_SCLK]

set_input_delay -min 0  -clock "QSPI_SCLK" [get_ports {QSPI_IO[*]}]
set_input_delay -max 1  -clock "QSPI_SCLK" [get_ports {QSPI_IO[*]}]

set_output_delay -min 0 -clock "QSPI_SCLK_o" [get_ports {QSPI_IO[*]}]
set_output_delay -max 1 -clock "QSPI_SCLK_o" [get_ports {QSPI_IO[*]}]

# CLOCK UNCERTAINTY — generated clocks don't inherit the master's uncertainty,
# so it must be set explicitly here for both QSPI clocks.
set_clock_uncertainty -setup $CLK_ERROR      [get_clocks QSPI_SCLK]
set_clock_uncertainty -hold  $CLK_HOLD_ERROR [get_clocks QSPI_SCLK]
set_clock_uncertainty -setup $CLK_ERROR      [get_clocks QSPI_SCLK_o]
set_clock_uncertainty -hold  $CLK_HOLD_ERROR [get_clocks QSPI_SCLK_o]

#=============================================================================
# BOARD-LEVEL I/O CHARACTERISATION  —  QSPI NOR FLASH INTERFACE
#=============================================================================
# QSPI_SCLK/nCS/IO[3:0] are physical chip pins (top-level includes the pad
# ring), so this section characterises the BOARD — the flash device, package
# and trace — not the TSMC PDK. Previously unconstrained (zero load/slew).
#
# Target device: Microchip SST26VF064B, 64 Mbit SQI flash (DS20005119J), the
# part modelled in verif/VIP and used on the bench Pmod SF3. Not yet recorded
# in any board/BOM doc — see WARNING 4. Supply range 2.3-3.6V covers our 3.0V
# nominal IO library.
#
# Number tags: [DATASHEET] = spec'd limit, [DERIVED] = arithmetic/convention
# on a datasheet number, [BUDGET] = board/package allowance, not measured.
#
# Units are ns/pF throughout (matches set_units in constraints.sdc and the IO lib).


#-----------------------------------------------------------------------------
# OUTPUT LOAD  —  what our pads actually drive
#-----------------------------------------------------------------------------
# Flash pin capacitance [DATASHEET Table 7-2]: CIN = 6 pF max (SCK, CE#),
# COUT = 8 pF max (SIO[3:0], bidirectional so use the larger figure).
# Plus 5 pF [BUDGET] for package/bond wire + a short (~2-3 inch) FR4 trace,
# not measured — no board exists yet.
#
#   SCLK, nCS :  6 + 5 = 11 pF
#   IO[3:0]   :  8 + 5 = 13 pF
#
# Sanity check: datasheet TV is 8 ns @ 30 pF and 5 ns @ 10 pF [Table 8-1 note
# 4]; our 13 pF sits inside that characterised range.
set_load 11 [get_ports QSPI_SCLK]
set_load 11 [get_ports QSPI_nCS]
set_load 13 [get_ports {QSPI_IO[*]}]

#-----------------------------------------------------------------------------
# INPUT TRANSITION  —  the flash driving into our pads
#-----------------------------------------------------------------------------
# Using set_input_transition, not set_driving_cell, since the flash die isn't
# in our library. Max 3.0 ns [DERIVED] from the datasheet's AC test condition
# (rise/fall 10%-90% < 3 ns, Fig 8-5) — thresholds match our IO lib's 10/90
# settings, so no conversion needed. Min 0.5 ns [BUDGET] is a conventional
# fast-corner CMOS edge; the datasheet sets no floor of its own.
set_input_transition -max 3.0 [get_ports {QSPI_IO[*]}]
set_input_transition -min 0.5 [get_ports {QSPI_IO[*]}]

#-----------------------------------------------------------------------------
# OUTPUT TRANSITION CEILING  —  what the flash requires of US
#-----------------------------------------------------------------------------
# The same <3 ns 10%-90% AC condition [Fig 8-5] is a REQUIREMENT on our outputs
# too — every Table 8-1 timing number assumes it. The library's default 5.0 ns
# ceiling is looser than that, so it's constrained explicitly here to 2.5 ns
# at the pin (0.5 ns headroom for board degradation) [DERIVED].
#
# SCK also has a slew floor (TSCKR/TSCKF = 0.1 V/ns min), but that only
# requires <24 ns at 3.0V — far looser than the 3 ns AC condition, which binds.
#
# In practice this is expected to be slack: all QSPI pads are the strongest
# 16 mA cell driving ~11-13 pF, giving sub-ns edges — see WARNING 3.
set_max_transition 2.5 [get_ports QSPI_SCLK]
set_max_transition 2.5 [get_ports QSPI_nCS]
set_max_transition 2.5 [get_ports {QSPI_IO[*]}]


#=============================================================================
# WARNINGS — READ BEFORE SIGNOFF. NONE OF THESE IS FIXED BY THIS FILE.
#=============================================================================
#
# 1. THE input/output_delay VALUES AT THE TOP (-max 1 / -min 0) ARE
#    OPTIMISTIC PLACEHOLDERS, not derived from the datasheet. Against Table
#    8-1: input -max should be ~5-8 ns (TV, Output Valid from SCK) not 1 ns;
#    output -max should be ~3 ns+flight (TDS) not 1 ns. Input -min (0, TOH=0)
#    is fine; output -min (TDH=4 ns min) needs review against the actual
#    capture scheme (SCLK falling launch / rising capture). Left unchanged
#    since it affects a design mid-P&R — belongs to the QSPI capture owner.
#    Input-side margin is the tight path: at 50 MHz only ~10 ns is available
#    between flash launch and our capture, most of it consumed by TV.
#
# 2. FREQUENCY: 50 MHz (CLK/2, CLK=100MHz) is fine for the 0x0B FAST_READ boot
#    path (spec limit 104/80 MHz) but VIOLATES the 40 MHz limit for opcode 03H
#    Read Memory [Table 5-1]. 0x03 is exposed in sw/qspi_driver.h and used in
#    test, so any silicon use of 03H needs the divider dropped (e.g. /4=25MHz
#    via reg13). Software/system issue, not fixable from this SDC.
#
# 3. [OWNER: constraints.sdc] `set_max_capacitance 3 [all_outputs]` (line 133)
#    conflicts with the 11-13 pF set_load values above on these pad-ring pins,
#    and will report a permanent max_cap violation. Must be scoped to internal
#    nets or exempted for pad outputs — cannot be fixed from this file since
#    that rule is applied globally after this file is sourced.
#
# 4. NO BOARD EXISTS YET, AND SST26VF064B IS NOT A RECORDED BOARD DECISION —
#    it's inferred from the verif models and bench Pmod. docs/PIN_MAP.md still
#    marks the QSPI pad cell "[TEAM DECISION]". If the part changes, the
#    loads, edge budget and WARNING 1 all need rework. Pin this down before
#    tapeout.
#
# 5. THE 5 pF PACKAGE+TRACE BUDGET IS A BUDGET, NOT A MEASUREMENT — it must be
#    given to the board designer as a requirement (~2-3" point-to-point,
#    single load, no stubs).
#
# 6. SIGNAL INTEGRITY RISK: all QSPI pads are the strongest 16 mA cell driving
#    a light ~11-13 pF load, giving sub-ns edges — fine for STA, but risks
#    overshoot/ringing on an unterminated board trace. The pad cell has no
#    slew/drive select, so this can't be tuned post-tapeout; needs a weaker
#    pad cell or board-side series termination.
#=============================================================================
