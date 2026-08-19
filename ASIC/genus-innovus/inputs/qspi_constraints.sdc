#############################################################################
# [C3] OPEN DECISION, FOR THE OWNER — `-divide_by 2` IS TRUE ONLY AT A
#      REGISTER'S RESET VALUE, AND ANOTHER IN-TREE CONSTRAINT SET CONTRADICTS
#      THIS ONE OUTRIGHT. NO CONSTRAINT IS CHANGED BY THIS BLOCK.
#      Recorded 2026-08-17.
#############################################################################
#
# FINDING 1 — THE RATIO IS SOFTWARE, NOT SILICON. `-divide_by 2` below describes
# the divider at its power-on value and at no other. From the RTL
# (nanosoc-multicore-system/ahb_qspi/logical/...):
#
#   qspi_clock_div.v:10   assign QSPI_SCLK_i = (QSPI_CLK_DIV==5'h00) ? HCLK
#                                                                    : QSPI_SCLK_reg;
#   qspi_clock_div.v:18     if (QSPI_CLK_DIV==5'h01) QSPI_SCLK_reg <= ~QSPI_SCLK_reg;
#   qspi_clock_div.v:20-26  else if (QSPI_CLK_DIV!=5'h00)
#                             toggle QSPI_SCLK_reg every QSPI_CLK_DIV HCLKs
#
#   => QSPI_CLK_DIV = 1        toggle every HCLK          -> HCLK/2   [the SDC]
#      QSPI_CLK_DIV = N >= 2   toggle every N HCLKs       -> HCLK/2N
#      QSPI_CLK_DIV = 0        pass-through               -> HCLK/1
#
# QSPI_CLK_DIV is reg13[4:0] of the APB register block, and it is WRITABLE:
#   apb_qspi_regs.v:168   assign QSPI_CLK_DIV = reg13;
#   apb_qspi_regs.v:181   reg13 <= 5'h01;                       ; # POR default
#   apb_qspi_regs.v:198   10'h00D: reg13 <= (PWDATA[4:0]==5'h00) ? 5'h01
#                                                               : PWDATA[4:0];
# Note the write path COERCES 0 to 1, so the /1 pass-through leg at line 10 is
# unreachable through software and the real range is /2 (reset) to /62
# (reg13 = 31) — a 31x span. The RTL states the far end itself:
# ahb_qspi_interface.sv:241-242, "at the slowest practical QSPI_SCLK_i
# (CLK_DIV=31 -> QSPI_SCLK_i = HCLK/62)".
#
# THIS FILE ALREADY CONTEMPLATES CHANGING IT. WARNING 2 below says opcode 03H
# Read Memory is limited to 40 MHz and that "any silicon use of 03H needs the
# divider dropped (e.g. /4=25MHz via reg13)". reg13 = 2 gives exactly that — and
# the moment it is written, QSPI_SCLK's declared waveform is wrong by 2x, and
# QSPI_SCLK_o and both set_input_delay/set_output_delay budgets go with it.
# The tool cannot notice; it reports clean against the waveform it was given.
#
# WHY THIS IS NOT SIMPLY "FIX THE NUMBER". Every candidate is a choice:
#   * KEEP /2. Correct at POR and at the FAST_READ boot path this part actually
#     boots from. Optimistic-in-frequency for any slower setting, but a SLOWER
#     real clock against a FASTER declared one is the conservative direction for
#     setup — the risk is not that /2 under-constrains, it is that the
#     input/output delays (WARNING 1) are budgeted against the wrong period.
#   * DECLARE THE SLOWEST (/62). Safe for the flash, but it would relax the
#     whole QSPI domain by 31x and hide real logic failures at the boot rate.
#   * DECLARE BOTH AND SWITCH BY MODE. The honest answer for a software-ratio
#     clock, and it needs an MMMC mode per divider setting — a flow change, not
#     an SDC edit.
# The choice depends on which divider values silicon is committed to using,
# which is a software/bring-up decision that has not been made.
#
# FINDING 2 — TWO IN-TREE CONSTRAINT SETS SAY OPPOSITE THINGS ABOUT THIS CLOCK.
#   nanosoc-multicore-system/ahb_qspi/cdc/top_ahb_qspi.sgdc declares three
#   domains and puts the QSPI serial clock in its own:
#       clock -name HCLK        -domain hclk_domain  -period 10.0
#       clock -name QSPI_SCLK_i -domain qspi_domain  -period 40.0
#   with the reason stated in its header: "For CDC analysis we treat it as a
#   separate asynchronous domain since the divider ratio is software-programmable
#   and the phase relationship is not guaranteed."
#   constraints.sdc says the opposite. It puts $EXTCLK, QSPI_SCLK and
#   QSPI_SCLK_o in ONE group of `set_clock_groups -asynchronous`, and
#   set_clock_groups cuts only BETWEEN groups — so at the chip level these three
#   are declared MUTUALLY SYNCHRONOUS and every HCLK <-> QSPI_SCLK_i crossing is
#   fully timed.
#
#   BOTH CANNOT BE RIGHT, AND THEY ARE NOT TRIVIALLY RECONCILABLE. Note also the
#   sgdc's 40.0 ns period is a third number, matching neither /2 (20 ns) nor any
#   other single setting. The chip-level view is arguably the defensible one —
#   QSPI_SCLK_reg is a flop on HCLK, so the divided clock IS phase-related to
#   HCLK by construction whatever the ratio, and a generated clock is the right
#   way to say so. But the sgdc is what CDC signoff was run against, and the
#   crossings it treats as CDC (and waives as quasi_static) are being timed here.
#   Whoever resolves this should make the two files agree explicitly rather than
#   let one silently overrule the other per tool.
#
# NOTHING BELOW IS CHANGED BY THIS BLOCK. See also the same class of defect
# argued in ethernet_constraints.sdc's SMI section, where a software-programmable
# MDC divider is the reason NOT to write a create_generated_clock at all.
#############################################################################

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
#    it's inferred from the verif models and bench Pmod. docs/design/PIN_MAP.md still
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
