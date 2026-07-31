################################################################################
# nanosoc_eth_chiplet_haps_sx.cob — HAPS-SX VU19P symbolic pin map
#
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access
# license.
#
# Contributors
#
# David Mapstone (d.a.mapstone@soton.ac.uk)
#
# Copyright 2026, SoC Labs (www.soclabs.org)
################################################################################
# Processed by the Synopsys HAPS-SX enablement kit's cobra helper
# (haps-sx_cobutil.tcl) into an FDC file that ProtoSynthesis consumes at
# `run pre_map -fdc`. Symbolic resource names (CLK.*, DBG.*, MEM.*) are
# resolved against haps-sx_vu19p.def, so this file never names a package pin.
#
#   assignHAPSPinCob {p:<port>} HAPS_MAIN <pinType>.<group>.<name>[.<index>]
#
# Port names MUST match nanosoc_eth_chiplet_haps_sx exactly.
#
################################################################################
# I/O VOLTAGE — MEASURED ON HARDWARE 2026-07-24
#
# THE PMOD CONNECTORS RUN AT 3.3 V. The reference manual's PMOD pin table
# (p65) gives a "Bank Voltage" column reading 1.8 V for banks 83/88/93. THAT
# COLUMN IS WRONG. Measured with the pmod_vlevel probe design
# (HAPS-work/HAPS-SX/examples/pmod_vlevel), driving those pins statically with
# LVCMOS18 declared: PMOD1 pin 1 reads 3.3 V against pin 5 (GND).
#
# An FPGA output's high level IS VCCO, so a 3.3 V reading means the bank rail
# is 3.3 V regardless of what IOSTANDARD we asked for. This also makes the
# connectors spec-compliant Digilent Pmod, which is what the 3.3 V on pins
# 6/12 implied all along.
#
# CONSEQUENCES
#   * PMOD-attached pins are LVCMOS_33. Declaring LVCMOS_18 on a 3.3 V bank is
#     wrong and unsafe for INPUTS — a 1.8 V receiver on a 3.3 V rail is out of
#     spec (this design has RMII inputs there).
#   * NO external level translators are needed. A stock 3.3 V LAN8720 module or
#     USB-UART dongle plugs straight in.
#
# EVERYTHING ELSE STAYS 1.8 V, and that part is silicon-enforced:
#   * Only banks 83/88/93/98 are High-Density (3.3 V capable). They carry the
#     four PMODs and the user LEDs.
#   * Every other user connector — all 24 HapsTrak-3 slots, both Mictors, both
#     FMCs, the push buttons, the on-board SPI flash and every global clock
#     input — is on a High-Performance bank, limited to 1.8 V in SILICON.
#     LVCMOS25/33/LVTTL there fail Vivado DRC BIVB-1; no board setting changes
#     it. The HT3 "selectable I/O voltage" feature tops out at 1.8 V.
#
# So the SWD probe on the Mictor still needs to be 1.8 V-capable (J-Link,
# ST-Link V3), and the on-board QSPI flash is a native 1.8 V part on a 1.8 V
# bank. Only the PMODs are 3.3 V.
################################################################################


################################################################################
# Clock — GCLK0 differential pair, bank 23, SLR0, 100 MHz by default.
#
# GCLK0 is driven by a dedicated on-board PLL and is reconfigurable through
# ConfPro-SX (100 Hz .. 720 MHz). The design divides it down in an MMCM, so
# leave the board default at 100 MHz unless you have a reason not to.
#
# Index .0 = BN53/BN54 (bank 23, SLR0). Index .1 would be AM61/AM62 (bank 28,
# SLR1) — the second copy of the same clock. Pick .1 instead if you later
# pblock the design into SLR1.
################################################################################
assignHAPSPinCob {p:gclk0_p}            HAPS_MAIN  CLK.GCLK0.P.0
assignHAPSPinCob {p:gclk0_n}            HAPS_MAIN  CLK.GCLK0.N.0

################################################################################
# Reset — push-button PB1 (active low), bank 20, SLR0.
# PB1 can also be driven remotely by the HAPS system control tool.
################################################################################
assignHAPSPinCob {p:pb1_rst_n}          HAPS_MAIN  DBG.BUTTON.PB1_N

################################################################################
# Status LEDs — 4 red + 4 green, bank 83, SLR0.
#   led[0..3] = R0..R3  (reds: reset / lockups / watchdog)
#   led[4..7] = G0..G3  (greens: link, role, UART activity, heartbeat)
################################################################################
assignHAPSPinCob {p:led[0]}             HAPS_MAIN  DBG.LED.R.0
assignHAPSPinCob {p:led[1]}             HAPS_MAIN  DBG.LED.R.1
assignHAPSPinCob {p:led[2]}             HAPS_MAIN  DBG.LED.R.2
assignHAPSPinCob {p:led[3]}             HAPS_MAIN  DBG.LED.R.3
assignHAPSPinCob {p:led[4]}             HAPS_MAIN  DBG.LED.G.0
assignHAPSPinCob {p:led[5]}             HAPS_MAIN  DBG.LED.G.1
assignHAPSPinCob {p:led[6]}             HAPS_MAIN  DBG.LED.G.2
assignHAPSPinCob {p:led[7]}             HAPS_MAIN  DBG.LED.G.3

################################################################################
# Serial Wire Debug — PMOD2 pins 9/10, bank 88, SLR1, 3.3 V.
#
# Moved off the Mictor (2026-07-24). The Mictor is the board's ARM-conventional
# debug connector, but it is 1.8 V (HP bank 21) and fine-pitch — needing a
# 1.8 V-capable probe, a Mictor-38 adapter, and the M-SW VTref switch set. PMOD2
# pins 9/10 are free (only IODATA lanes 6/7 were spare) and 3.3 V, so ANY
# ordinary 3.3 V probe attaches with jumper wires: no adapter, no switch.
#
#   PMOD2 pin  9 (BC14) = SWCLK   PMOD2.6
#   PMOD2 pin 10 (BC15) = SWDIO   PMOD2.7
#   PMOD2 pin 11        = GND      (probe return)
#   PMOD2 pin 12        = 3.3 V    (probe VTref)
#
# A tidy 4-pin corner (9->12): both signals + GND + VTref adjacent.
#
# BC14 is NOT a clock-capable pin, so swd_clk keeps CLOCK_DEDICATED_ROUTE FALSE
# in the timing XDC — fine, SWD is slow and async and already false-pathed.
# Optional nRESET is not wired (no spare pin here; SWD SYSRESETREQ works without
# it). The Mictor remains the path if CoreSight trace (SWO/TRACEDATA) is ever
# wanted — plain halt/step/memory debug does not need it.
################################################################################
assignHAPSPinCob {p:swd_clk}            HAPS_MAIN  DBG.PMOD.PMOD2.6
assignHAPSPinCob {p:swd_dio}            HAPS_MAIN  DBG.PMOD.PMOD2.7

################################################################################
# QSPI flash — the board's ON-BOARD Winbond W25Q32FW, bank 21, SLR0.
#
# 32 Mb = 4 MB, a native 1.8 V part ("W" suffix) on a 1.8 V bank: no adapter,
# no Pmod, no level shifting. 4 MB is exactly the SoC's QSPI_FLASH_ADDR_W = 22
# aperture, so the XiP window maps the whole device.
#
# CAVEAT: the QSPI controller and the qspi_flasher firmware were written
# against a Micron N25Q256A. The Winbond command set is broadly compatible
# (0x9F JEDEC ID, 0x06 WREN, 0x02 page program, 0x20 4 KB sector erase,
# 0x03/0x0B read, 0x6B/0xEB quad read) but this has NOT been verified on
# hardware. Read the JEDEC ID first — see README.md bring-up step 4.
################################################################################
assignHAPSPinCob {p:qspi_sclk}          HAPS_MAIN  MEM.FLASH.CLK
assignHAPSPinCob {p:qspi_ncs}           HAPS_MAIN  MEM.FLASH.CS_B
assignHAPSPinCob {p:qspi_io[0]}         HAPS_MAIN  MEM.FLASH.D.0
assignHAPSPinCob {p:qspi_io[1]}         HAPS_MAIN  MEM.FLASH.D.1
assignHAPSPinCob {p:qspi_io[2]}         HAPS_MAIN  MEM.FLASH.D.2
assignHAPSPinCob {p:qspi_io[3]}         HAPS_MAIN  MEM.FLASH.D.3

################################################################################
# RMII ethernet PHY (LAN8720) — PMOD1 + PMOD2, bank 88, SLR1.
#
# 10 signals: one 8-pin PMOD is not enough, so this straddles two. Both are on
# bank 88 / SLR1, so the PHY interface stays in one bank and one SLR.
#
# phy_rmii_ref_clk is deliberately on PMOD1 pin 1 (AW16), which is a
# clock-capable (GC) pin — the 50 MHz PHY-sourced reference lands on dedicated
# clock routing, unlike the Pynq-Z2 flow which had to waive
# CLOCK_DEDICATED_ROUTE on a non-CCIO pin.
#
# NO LEVEL TRANSLATOR NEEDED. Bank 88 is 3.3 V (measured — see the header), so
# a stock 3.3 V LAN8720 breakout connects DIRECTLY: signals to PMOD1/PMOD2,
# power from PMOD pin 6/12 (3.3 V) and GND from pin 5/11.
#
# phy_mdio_dir is left assigned but is now redundant — it exists to drive a
# translator's DIR pin. Harmless as an unread output; drop it from the RTL and
# this file if you want the pin back.
#
# HISTORICAL NOTE (kept so nobody re-derives the wrong answer): the manual's
# PMOD table says 1.8 V, and on that basis this file originally required a
# 74AVC16T245 for RMII and a FET translator for MDIO. Hardware measurement
# disproved it. If you ever meet a HAPS-SX whose PMODs really are 1.8 V, that
# is the parts list — and note that auto-direction parts drive through
#     ~4 kohm with one-shot accelerators and are unfit for a 50 MHz clocked bus.
#
# SIGNAL INTEGRITY: 50 MHz across 0.1" unshielded headers with two grounds is
# marginal. Keep leads to a few cm. If the link proves flaky, move the PHY to
# an HT3 slot (length-matched, with a proper ground complement) — but note HT3
# slots are on HP banks and top out at 1.8 V, so THAT route does need the
# translators described above.
################################################################################
assignHAPSPinCob {p:phy_rmii_ref_clk}   HAPS_MAIN  DBG.PMOD.PMOD1.0
assignHAPSPinCob {p:phy_rmii_crs_dv}    HAPS_MAIN  DBG.PMOD.PMOD1.1
assignHAPSPinCob {p:phy_rmii_rxd[0]}    HAPS_MAIN  DBG.PMOD.PMOD1.2
assignHAPSPinCob {p:phy_rmii_rxd[1]}    HAPS_MAIN  DBG.PMOD.PMOD1.3
assignHAPSPinCob {p:phy_rmii_txd[0]}    HAPS_MAIN  DBG.PMOD.PMOD1.4
assignHAPSPinCob {p:phy_rmii_txd[1]}    HAPS_MAIN  DBG.PMOD.PMOD1.5
assignHAPSPinCob {p:phy_rmii_tx_en}     HAPS_MAIN  DBG.PMOD.PMOD1.6
assignHAPSPinCob {p:phy_mdc}            HAPS_MAIN  DBG.PMOD.PMOD1.7

assignHAPSPinCob {p:phy_mdio}           HAPS_MAIN  DBG.PMOD.PMOD2.0
assignHAPSPinCob {p:phy_mdio_dir}       HAPS_MAIN  DBG.PMOD.PMOD2.1
assignHAPSPinCob {p:phy_nrst}           HAPS_MAIN  DBG.PMOD.PMOD2.4

################################################################################
# Debug UART (CPU0 / network core) — PMOD2, bank 88, SLR1.
#
# Bank 88 is 3.3 V (measured), so ANY ordinary 3.3 V USB-UART dongle works
# directly — CP2102, FT232, CH340. No translator, no 1.8 V cable needed.
#
# CROSS TX<->RX at the dongle: uart_txd -> dongle RXD, uart_rxd <- dongle TXD.
# That is the single most common wiring mistake here.
#
# Do NOT connect the dongle's VCC if the board is already powered — take 3.3 V
# from PMOD pin 6/12 or leave it unconnected and share only GND (pin 5/11).
################################################################################
assignHAPSPinCob {p:uart_txd}           HAPS_MAIN  DBG.PMOD.PMOD2.2
assignHAPSPinCob {p:uart_rxd}           HAPS_MAIN  DBG.PMOD.PMOD2.3

################################################################################
# PHC 1 PPS — scope probe point, PMOD2, bank 88, SLR1.
################################################################################
assignHAPSPinCob {p:phc_pps_out}        HAPS_MAIN  DBG.PMOD.PMOD2.5

################################################################################
# HOSTIO4 — 7-pin host interface, PMOD3, bank 83, SLR0.
#
# nanosoc_ss_hostio4 is strapped FT1248MODE = 0 (EXTIO mode) at the SoC level,
# which maps the P1[6:0] tristate bundle onto the HOSTIO4 wire protocol:
#
#   PMOD3 pin   P1 bit   signal      direction
#     1           0      IOREQ1      SoC -> host   (OUTEN tied 1 in the SoC)
#     2           1      IOREQ2      SoC -> host   (OUTEN tied 1)
#     3           2      IOACK       host -> SoC   (OUTEN tied 0; asynchronous)
#     4           3      IODATA[0]   bidirectional
#     7           4      IODATA[1]   bidirectional
#     8           5      IODATA[2]   bidirectional
#     9           6      IODATA[3]   bidirectional
#     10          -      unused (spare)
#     5, 11       -      GND
#     6, 12       -      3.3 V
#
# Four 8-bit AXI streams are multiplexed over these 7 wires: channel 0 TX/RX is
# conventionally stdout/stdin, channel 1 TX/RX a bulk data stream.
#
# HOST SIDE: the validated driver is the RP2040/RP2350 PIO implementation in
# nanosoc_arch_tech/rtl/hostio4/rpi-pico-pio. A Pico is 3.3 V and PMOD3 is on
# bank 83 (measured 3.3 V), so it connects DIRECTLY — no level shifting. Take
# GND from PMOD3 pin 5 or 11. Do not back-feed the Pico's 3V3 into pin 6/12
# while the HAPS board is powered.
#
# The whole interface is on ONE connector and ONE bank, which matters: IOACK is
# asynchronous and the four IODATA lines turn around, so keeping them
# electrically together avoids skew between the request/ack handshake and the
# data nibble.
################################################################################
assignHAPSPinCob {p:hostio4_p1[0]}      HAPS_MAIN  DBG.PMOD.PMOD3.0
assignHAPSPinCob {p:hostio4_p1[1]}      HAPS_MAIN  DBG.PMOD.PMOD3.1
assignHAPSPinCob {p:hostio4_p1[2]}      HAPS_MAIN  DBG.PMOD.PMOD3.2
assignHAPSPinCob {p:hostio4_p1[3]}      HAPS_MAIN  DBG.PMOD.PMOD3.3
assignHAPSPinCob {p:hostio4_p1[4]}      HAPS_MAIN  DBG.PMOD.PMOD3.4
assignHAPSPinCob {p:hostio4_p1[5]}      HAPS_MAIN  DBG.PMOD.PMOD3.5
assignHAPSPinCob {p:hostio4_p1[6]}      HAPS_MAIN  DBG.PMOD.PMOD3.6

################################################################################
# I/O standards
#
# LVDS_18 on the clock pair (bank 23 is HP, so LVDS is the correct differential
# standard there — NOT LVDS_25, which is the HD-bank spelling and would be
# rejected). LVCMOS_18 everywhere else.
################################################################################
define_io_standard {p:gclk0_p}          syn_pad_type {LVDS_18}
define_io_standard {p:gclk0_n}          syn_pad_type {LVDS_18}

define_io_standard {p:pb1_rst_n}        syn_pad_type {LVCMOS_18} -delay_type {input}

define_io_standard {p:led[0]}           syn_pad_type {LVCMOS_33} -delay_type {output}
define_io_standard {p:led[1]}           syn_pad_type {LVCMOS_33} -delay_type {output}
define_io_standard {p:led[2]}           syn_pad_type {LVCMOS_33} -delay_type {output}
define_io_standard {p:led[3]}           syn_pad_type {LVCMOS_33} -delay_type {output}
define_io_standard {p:led[4]}           syn_pad_type {LVCMOS_33} -delay_type {output}
define_io_standard {p:led[5]}           syn_pad_type {LVCMOS_33} -delay_type {output}
define_io_standard {p:led[6]}           syn_pad_type {LVCMOS_33} -delay_type {output}
define_io_standard {p:led[7]}           syn_pad_type {LVCMOS_33} -delay_type {output}

define_io_standard {p:swd_clk}          syn_pad_type {LVCMOS_33} -delay_type {input}
define_io_standard {p:swd_dio}          syn_pad_type {LVCMOS_33} -delay_type {bidir}

define_io_standard {p:qspi_sclk}        syn_pad_type {LVCMOS_18} -delay_type {output}
define_io_standard {p:qspi_ncs}         syn_pad_type {LVCMOS_18} -delay_type {output}
define_io_standard {p:qspi_io[0]}       syn_pad_type {LVCMOS_18} -delay_type {bidir}
define_io_standard {p:qspi_io[1]}       syn_pad_type {LVCMOS_18} -delay_type {bidir}
define_io_standard {p:qspi_io[2]}       syn_pad_type {LVCMOS_18} -delay_type {bidir}
define_io_standard {p:qspi_io[3]}       syn_pad_type {LVCMOS_18} -delay_type {bidir}

define_io_standard {p:phy_rmii_ref_clk} syn_pad_type {LVCMOS_33} -delay_type {input}
define_io_standard {p:phy_rmii_crs_dv}  syn_pad_type {LVCMOS_33} -delay_type {input}
define_io_standard {p:phy_rmii_rxd[0]}  syn_pad_type {LVCMOS_33} -delay_type {input}
define_io_standard {p:phy_rmii_rxd[1]}  syn_pad_type {LVCMOS_33} -delay_type {input}
define_io_standard {p:phy_rmii_txd[0]}  syn_pad_type {LVCMOS_33} -delay_type {output}
define_io_standard {p:phy_rmii_txd[1]}  syn_pad_type {LVCMOS_33} -delay_type {output}
define_io_standard {p:phy_rmii_tx_en}   syn_pad_type {LVCMOS_33} -delay_type {output}
define_io_standard {p:phy_mdc}          syn_pad_type {LVCMOS_33} -delay_type {output}
define_io_standard {p:phy_mdio}         syn_pad_type {LVCMOS_33} -delay_type {bidir}
define_io_standard {p:phy_mdio_dir}     syn_pad_type {LVCMOS_33} -delay_type {output}
define_io_standard {p:phy_nrst}         syn_pad_type {LVCMOS_33} -delay_type {output}

define_io_standard {p:uart_txd}         syn_pad_type {LVCMOS_33} -delay_type {output}
define_io_standard {p:uart_rxd}         syn_pad_type {LVCMOS_33} -delay_type {input}

define_io_standard {p:phc_pps_out}      syn_pad_type {LVCMOS_33} -delay_type {output}

define_io_standard {p:hostio4_p1[0]}    syn_pad_type {LVCMOS_33} -delay_type {bidir}
define_io_standard {p:hostio4_p1[1]}    syn_pad_type {LVCMOS_33} -delay_type {bidir}
define_io_standard {p:hostio4_p1[2]}    syn_pad_type {LVCMOS_33} -delay_type {bidir}
define_io_standard {p:hostio4_p1[3]}    syn_pad_type {LVCMOS_33} -delay_type {bidir}
define_io_standard {p:hostio4_p1[4]}    syn_pad_type {LVCMOS_33} -delay_type {bidir}
define_io_standard {p:hostio4_p1[5]}    syn_pad_type {LVCMOS_33} -delay_type {bidir}
define_io_standard {p:hostio4_p1[6]}    syn_pad_type {LVCMOS_33} -delay_type {bidir}
