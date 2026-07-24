# KR260 Board Wiring — LAN8720, UART Console, SWD Debugger

Bench wiring guide for the `kr260-eth-chiplet` target (die_a / die_b). Covers
**where** to land each interface on the KR260 and **what** to change in RTL /
block design / XDC to make it real.

> **Status legend used throughout:**
> **[BUILT]** — in the current bitstream, pin assignment DRC-checked by a passing
> `build_design`. **[PROPOSED]** — pin choice is sound but not yet built; needs a
> build to confirm placement.

---

## 0. Read this first — voltage domains

The KR260 PMOD connectors are **not all the same voltage.** This was proven the
hard way: putting SWD on PMOD4 at `LVCMOS33` failed placement with
`DRC BIVB-1 — LVCMOS33 is not supported for banks of type High Performance`.

| Connector | Package balls (pins 1,2,3,4 / 7,8,9,10) | Bank type | **Vcco** |
|---|---|---|---|
| **PMOD1** | H12, E10, D10, C11 / B10, E12, D11, B11 | HD | **3.3 V** |
| **PMOD2** | J11, J10, K13, K12 / H11, G10, F12, F11 | HD | **3.3 V** |
| **PMOD3** | AE12, AF12, AG10, AH10 / AF11, AG11, AH12, AH11 | HD | **3.3 V** |
| **PMOD4** | L2, T7, AF7, AF6 / AD7, W10, Y10, AB10 | **HP (64/65)** | **1.8 V** |
| **J21 RPi header** | see §3 ribbon map | HDIO bank 44 | **3.3 V** |

Standard Pmod 2×6 numbering: top row `1 2 3 4 5=GND 6=VCC`, bottom row
`7 8 9 10 11=GND 12=VCC`. The eight signal pins are physical 1–4 and 7–10.

**Consequences**
- A **3.3 V** peripheral (LAN8720 module, most USB-UART dongles, most SWD probes)
  belongs on **PMOD1/2/3**, never PMOD4 without a level shifter.
- Driving 3.3 V into a PMOD4 (HP, 1.8 V) pin **can damage the SOM**. Do not do it.

---

## 1. SWD debugger

### Current state — **PMOD2, 3.3 V** *(applied; build in flight to validate placement)*

SWD was **moved off PMOD4**. PMOD4 sits on HP banks 64/65 (1.8 V) and rejected
`LVCMOS33` outright (`DRC BIVB-1`), which would have forced a 1.8 V-only probe.
PMOD2 is a 3.3 V HD bank, so an ordinary ST-Link / DAPLink works directly.

| Signal | PMOD2 pin | Ball | Direction |
|---|---|---|---|
| `SWCLK` | 1 | J11 | probe → FPGA |
| `SWDIO` | 2 | J10 | bidirectional |
| `SWD_NPORESETN` | 3 | K13 | probe → FPGA (optional) |
| GND | 5 / 11 | — | probe return |
| VCC (**3.3 V**) | 6 / 12 | — | probe VREF sense |

`SWCLK` also carries `set_property CLOCK_DEDICATED_ROUTE FALSE` on its **net**
(it may land on a clock-capable pin; it's a slow debug clock so dedicated
routing is waived — note this is a *net* property, applying it to a port throws
`Netlist 29-69` and fails the message gate).

**PMOD4 is now free** — and should stay clear of 3.3 V peripherals.

### Probe wiring

```
  Probe            KR260 PMOD2  (3.3 V)
  ---------------------------------------
  SWCLK    ------> pin 1   (J11)
  SWDIO    <-----> pin 2   (J10)
  nRESET   ------> pin 3   (K13)  (optional; SWD SYSRESETREQ works without it)
  GND      ------- pin 5 or 11
  VREF/VTG <------ pin 6 or 12    (reads 3.3 V)
```

Keep `SWCLK` short. If the probe is flaky, drop the adapter speed first
(`adapter speed 1000`) — a long flying-lead SWCLK is the usual culprit.

### Driving it

No host-side changes: this reuses the PYNQ-Z2 OpenOCD flow verbatim.

```bash
# on the machine with the probe attached
openocd -f nanosoc-multicore-system/pynq/scripts/openocd/nanosoc_multicore.cfg
# default SWD_INTERFACE=interface/stlink.cfg; override for DAPLink/J-Link:
#   -c "set SWD_INTERFACE interface/cmsis-dap.cfg"
```

The SoC is strapped **SWD-only** (`dap_swj_enable=1`, JTAG TAP tied off), so
`transport select swd` is the only valid transport. The board's own micro-USB
JTAG reaches the **ZynqMP/PL config TAP only** — it cannot debug the soft M0.

---

## 2. UART console

### The micro-USB reality — read before wiring

The KR260 micro-USB is an FTDI bridge whose UART channel is wired to the **PS
(ZynqMP MIO)** and carries the **Linux console** (`/dev/ttyPS0`). It is **not
connected to PL pins**, so the nanoSoC's UART — which is PL logic — *cannot*
drive that micro-USB port directly. There is no XDC constraint that makes a PL
signal appear on it.

You therefore have three real options.

### Option A — EMIO UART1 → `/dev/ttyPS1` **(recommended; proven on PYNQ-Z2)**

Route the nanoSoC UART into the **PS UART1 via EMIO**. The PS then exposes it as
a second tty on the board, and you reach it over the *same* USB/SSH session as
the Linux console. This is exactly what the multicore PYNQ-Z2 flow does — see
`nanosoc-multicore-system/pynq/SMOKE.md` (the EMIO UART1 device-tree overlay and
the `/dev/ttyPS1` troubleshooting rows).

Block-design change (in `tidelink_design.tcl`):

```tcl
# enable PS UART1 on EMIO
set_property -dict [list \
    CONFIG.PSU__UART1__PERIPHERAL__ENABLE {1} \
    CONFIG.PSU__UART1__PERIPHERAL__IO     {EMIO} \
] $ps
# cross-connect: SoC TX -> PS RX, PS TX -> SoC RX
connect_bd_net [get_bd_pins $soc/uart_txd]  [get_bd_pins $ps/emio_uart1_rxd]
connect_bd_net [get_bd_pins $ps/emio_uart1_txd] [get_bd_pins $soc/uart_rxd]
```

Then **delete** the `uart_txd`/`uart_rxd` external BD ports and their XDC lines
(§2 "current state" below) — the signals no longer leave the chip.

On the board:

```bash
sudo screen /dev/ttyPS1 115200      # nanoSoC console
# /dev/ttyPS0 remains the Linux console on the micro-USB
```

Needs the device-tree overlay applied at deploy (the Z2 flow's `deploy-auto`
does the DTBO + SLCR pulse chain; port the same step for KR260).

### Option B — USB-UART dongle on a 3.3 V PMOD **[PROPOSED]**

If you want a genuine second COM port on your workstation, hang a 3.3 V USB-UART
dongle (CP2102 / FT232 / CH340) off PMOD3:

| Signal | PMOD3 pin | Ball | Dongle pin |
|---|---|---|---|
| `uart_txd` (SoC → host) | 7 | AF11 | dongle **RXD** |
| `uart_rxd` (host → SoC) | 8 | AG11 | dongle **TXD** |
| GND | 11 | — | dongle GND |

> PMOD3 pins 3–4 hold the status LEDs once the PHY takes PMOD1 (§3), so the
> dongle uses the lower row.

**Cross TX↔RX** — the single most common wiring mistake here. Do **not** connect
the dongle's VCC if the board is already powered.

```tcl
set_property -dict { PACKAGE_PIN AF11 IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 4 } [get_ports uart_txd]
set_property -dict { PACKAGE_PIN AG11 IOSTANDARD LVCMOS33 }                    [get_ports uart_rxd]
```

### Current state **[BUILT]**

Today the UART is brought out on two **spare J21 RPi pins**, which works but
needs flying leads to a dongle and occupies ribbon-adjacent pins:

| Signal | J21 | Ball |
|---|---|---|
| `uart_txd` | BCM20 (phys 38) | W12 |
| `uart_rxd` | BCM21 (phys 40) | W11 |

Move to Option A (preferred) or Option B before the two-board demo — the J21
pins are better kept clear of the ribbon.

---

## 3. LAN8720 RMII PHY (milestone M2)

### Current state — **tied off**

The M1 build deliberately idles the PHY inside
`tidelink/fpga/vivado_ip/nanosoc_eth_chiplet_vivado_wrapper.v`:

```verilog
wire        rmii_ref_clk_idle = 1'b0;
wire  [1:0] rmii_rxd_idle     = 2'b00;
wire        rmii_crs_dv_idle  = 1'b0;
...
.rmii_txd   (),   .rmii_tx_en (),   .md_pad_i (1'b0),
.mdc_pad_o  (),   .md_pad_o   (),   .md_padoe_o ()
```

Wiring a real LAN8720 means **undoing these tie-offs** and promoting the signals
to IP ports → BD ports → XDC. That is the bulk of the work; the pin choice is
the easy part.

### Signal budget

| Chiplet port | Dir | LAN8720 pin | Notes |
|---|---|---|---|
| `rmii_ref_clk` | in | REF_CLK (nINT/REFCLKO) | 50 MHz — see clocking below |
| `rmii_txd[0]` | out | TXD0 | |
| `rmii_txd[1]` | out | TXD1 | |
| `rmii_tx_en` | out | TXEN | |
| `rmii_rxd[0]` | in | RXD0 / PHYAD1 | strap pin — see gotchas |
| `rmii_rxd[1]` | in | RXD1 / PHYAD2 | strap pin |
| `rmii_crs_dv` | in | CRS_DV / MODE0 | strap pin |
| `mdc_pad_o` | out | MDC | |
| `md_pad_{i,o,oe}` | bidir | MDIO | one pin + IOBUF |

**9 PL pins.** A Pmod carries 8 signals, so the module fills one connector and
**TX1 is the single overflow** — one flying lead, nothing more.

### Pin map — module plugs into PMOD1, TX1 overflows to PMOD2 **[PROPOSED]**

The Waveshare LAN8720 is a **plug-in Pmod module**, so its pinout is fixed by the
board — do not re-order it. The PYNQ-Z2 build
(`nanosoc-multicore-system/pynq/targets/pynq-z2/nanosoc_multicore.xdc`) plugs it
into PMODB and uses exactly 8 pins; **TX1 is the one signal that does not fit**
and needs a single flying lead. (On the Z2 it lands on an Arduino pin only
because PMODA was already full — nothing about TX1 requires that connector.)

Module pinout, in Pmod pin numbers — identical on Z2 and KR260:

| Pmod pin | LAN8720 signal | Chiplet port |
|---|---|---|
| 1 | RX1 | `rmii_rxd[1]` |
| 2 | TX0 | `rmii_txd[0]` |
| 3 | CRS_DV | `rmii_crs_dv` |
| 4 | MDC | `mdc_pad_o` |
| 7 | TX_EN | `rmii_tx_en` |
| 8 | RX0 | `rmii_rxd[0]` |
| 9 | MDIO | `md_pad_*` (IOBUF) |
| 10 | nINT/REF_CLK (50 MHz out) | `rmii_ref_clk` |
| — | **TX1** *(overflow)* | `rmii_txd[1]` |

On the KR260: **plug the module into PMOD1**, and run TX1 to **PMOD2 pin 4
(K12)** — the nearest free pin, since SWD only takes PMOD2 pins 1-3.

| Signal | Connector | Pin | Ball |
|---|---|---|---|
| `rmii_rxd[1]` | PMOD1 | 1 | H12 |
| `rmii_txd[0]` | PMOD1 | 2 | E10 |
| `rmii_crs_dv` | PMOD1 | 3 | D10 |
| `mdc_pad_o` | PMOD1 | 4 | C11 |
| `rmii_tx_en` | PMOD1 | 7 | B10 |
| `rmii_rxd[0]` | PMOD1 | 8 | E12 |
| `MDIO` (bidir) | PMOD1 | 9 | D11 |
| `rmii_ref_clk` | PMOD1 | 10 | B11 |
| **`rmii_txd[1]` (TX1)** | **PMOD2** | **4** | **K12** |
| 3.3 V / GND | PMOD1 | 6,12 / 5,11 | module power |

> **The status LEDs must move off PMOD1** (they currently sit on pins 1-2,
> H12/E10 — the module's RX1/TX0). Move them to PMOD3 pins 3-4 (AG10/AH10).
> There is no `phy_nrst`: the Waveshare module self-resets, and the Z2 build
> drives no reset pin.

```tcl
# LAN8720 module on PMOD1 (fixed module pinout — do not re-order)
set_property -dict { PACKAGE_PIN H12 IOSTANDARD LVCMOS33 } [get_ports {rmii_rxd[1]}]
set_property -dict { PACKAGE_PIN D10 IOSTANDARD LVCMOS33 } [get_ports rmii_crs_dv]
set_property -dict { PACKAGE_PIN E12 IOSTANDARD LVCMOS33 } [get_ports {rmii_rxd[0]}]
set_property -dict { PACKAGE_PIN C11 IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8 } [get_ports mdc_pad_o]
set_property -dict { PACKAGE_PIN D11 IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8 PULLUP true } [get_ports MDIO]

# RMII TX: SLEW FAST + DRIVE 16 (+ IOB) is the Z2-validated source-synchronous
# config. NOTE: verify IOB TRUE is accepted on the KR260 HD bank — the TideLink
# pad_rx path needed IOB FALSE on this device, so do not assume it packs.
set_property -dict { PACKAGE_PIN E10 IOSTANDARD LVCMOS33 SLEW FAST DRIVE 16 } [get_ports {rmii_txd[0]}]
set_property -dict { PACKAGE_PIN B10 IOSTANDARD LVCMOS33 SLEW FAST DRIVE 16 } [get_ports rmii_tx_en]
# TX1 overflow -> PMOD2 pin 4 (SWD occupies pins 1-3 only)
set_property -dict { PACKAGE_PIN K12 IOSTANDARD LVCMOS33 SLEW FAST DRIVE 16 } [get_ports {rmii_txd[1]}]

# 50 MHz REF_CLK from the PHY, on a non-clock-capable pin (as on the Z2, V12).
create_clock -period 20.000 -name rmii_ref_clk -waveform {0.000 10.000} -add [get_ports rmii_ref_clk]
set_property -dict { PACKAGE_PIN B11 IOSTANDARD LVCMOS33 } [get_ports rmii_ref_clk]
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets -of_objects [get_ports rmii_ref_clk]]
```

### Clocking — the decision that matters most

`rmii_ref_clk` is an **input** to the SoC, so by default the LAN8720 sources the
50 MHz. Two ways to do it:

- **PHY-sourced — this is what the Z2 build uses (REF_CLK_OUT mode).** The module's 25 MHz crystal drives an
  internal PLL and the `nINT/REFCLKO` pin outputs 50 MHz into the FPGA. Simplest
  to wire, but 50 MHz arriving on a non-clock-capable PMOD pin is the weak point
  — hence the `CLOCK_DEDICATED_ROUTE FALSE` above. Verify the ball you pick; if
  timing is unhappy, relocate `rmii_ref_clk` to a clock-capable J21 pin.
- **FPGA-sourced (cleaner, needs a module that supports it).** Add a 50 MHz
  `clk_wiz` output, drive it *out* to the PHY's REF_CLK **and** feed the same net
  to `rmii_ref_clk` internally. No clock-capable input pin needed and the whole
  RMII domain is synchronous to the FPGA. Requires the module strapped for
  REF_CLK-**in** (often means lifting the on-board oscillator) — check your
  specific board before committing.

### RTL / BD changes required

1. **IP wrapper** (`nanosoc_eth_chiplet_vivado_wrapper.v`): delete the three
   `*_idle` constants, promote `rmii_ref_clk`, `rmii_txd[1:0]`, `rmii_tx_en`,
   `rmii_rxd[1:0]`, `rmii_crs_dv`, `mdc_pad_o` and the MDIO trio
   (`md_pad_i`/`md_pad_o`/`md_padoe_o`) to **module ports**, and connect them to
   `u_chiplet` instead of tying them off. Re-run `make package_eth_chiplet_ip`.
2. **BD** (`tidelink_design.tcl`): `create_bd_port` for each, and connect to the
   eth-chiplet cell. MDIO stays as the three discrete signals at BD level.
3. **Board wrapper** (`tidelink_design_wrapper.v`): add the MDIO IOBUF, mirroring
   the existing SWDIO one:
   ```verilog
   IOBUF u_mdio_iobuf (
       .IO (MDIO), .I (md_pad_o_int), .O (md_pad_i_int), .T (~md_padoe_o_int)
   );
   ```
   (`md_padoe_o` is active-high output-enable; Vivado `T` is active-high tristate,
   so invert — same convention as `dap_swdoen`.)
4. **XDC**: the block above.
5. **Firmware**: MAC out of internal loopback, MDIO PHY discovery, then link-up.

### LAN8720 gotchas

- **Strap pins.** `RXD0/RXD1/CRS_DV` double as `PHYAD[2:1]`/`MODE0` and are
  sampled at reset. FPGA pull-ups/pull-downs on those nets change the PHY address
  the MDIO scan must use. Most breakouts fix the straps with their own resistors —
  if MDIO reads all-ones or all-zeros, suspect PHY address before anything else.
- **`nINT/REFCLKO` dual function** — the same pin is the interrupt and the 50 MHz
  output. Confirm which mode your module ships in.
- **Power.** Feed the module from a PMOD 3.3 V pin (6/12) and GND (5/11). Don't
  back-feed 3.3 V from an external supply while the board is powered.
- **Keep RMII leads short.** 50 MHz on flying leads is already marginal; a PMOD
  ribbon of a few cm is fine, 20 cm of loose jumper wire is not.

---

## 4. Summary — what goes where

| Interface | Connector | Voltage | Status |
|---|---|---|---|
| TideLink die-to-die ribbon | **J21** (RPi 40-pin), 18 signals + 2 I²C + GNDs | 3.3 V | **[BUILT]** — straight-through, `BCM_n ↔ BCM_n`; **never bridge the +3V3/+5V rails** |
| SWD debugger | **PMOD2** (pins 1-3) | 3.3 V | applied; build validating placement |
| UART console | EMIO → `/dev/ttyPS1` (**recommended**), or dongle on **PMOD3** pins 7–8 | — / 3.3 V | currently on spare J21 pins **[BUILT]** |
| LAN8720 RMII | **PMOD1** (module plugs in) + **PMOD2 pin 4** for TX1 | 3.3 V | **[PROPOSED]** — RTL tie-offs must be undone first |
| Status LEDs | PMOD1 pins 1–2 → **must move to PMOD3** pins 3–4 when the PHY plugs into PMOD1 | 3.3 V | **[BUILT]** |
| *(free)* | **PMOD4** — 1.8 V, keep clear of 3.3 V parts | 1.8 V | unused |

### Pre-power checklist
1. Ribbon is **straight-through**, power rails stripped, die_a image on one board
   and the **`-flip`** image on the other (same image on both shorts every lane).
2. Nothing 3.3 V is touching **PMOD4** (it is now unused — keep it that way).
3. SWD probe VREF reads **3.3 V** on PMOD2 pin 6/12.
4. UART dongle TX↔RX crossed, VCC not connected.
5. LAN8720 module powered from the same PMOD it is signalling to.

---

## References
- Pin/bank data: Vivado 2024.1 `kr260_som` / `kr260_carrier` board files, and
  `nanosoc-multicore-system/nanosoc_arch_tech/fpga/fpga/targets/pynq_kr260/fpga_pinmap.xdc`.
- Ribbon map: `tidelink/fpga/targets/kr260-eth-chiplet/kr260_eth_chiplet_tidelink.xdc`
  and the bare-link `ribbon_wiring.md`.
- Build + current status: `tidelink/fpga/targets/kr260-eth-chiplet/BUILD_NOTES.md`.
- OpenOCD/SWD flow: `nanosoc-multicore-system/pynq/scripts/openocd/nanosoc_multicore.cfg`,
  `pynq/SMOKE.md`.
