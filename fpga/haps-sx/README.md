# nanoSoC ethernet chiplet on the HAPS-SX VU19P

FPGA target for the **single-die** `nanosoc_eth_chiplet` on a Synopsys
**HAPS-SX VU19P 1F** (XCVU19P-FSVA3824).

> **Flow note.** The intended path was the **ProtoCompiler GUI**
> (ProtoSynthesis). That is **not runnable at this site** — `protocompiler_s`
> needs the FlexNet feature `ProtoCompilerS`, which the licence server does not
> carry, and the licensed `protocompiler` product exposes only HAPS *board*
> technologies (no FPGA technology, no HAPS-SX entry). **The default flow here
> is therefore Vivado**, which handles the VU19P natively and needs no Synopsys
> licence. See §6. The ProtoSynthesis scripts are kept and share the `.cob`,
> the board top and the generated source list, ready if the licence appears.

> **Status: builds to a bitstream (2026-07-24). Not yet run on hardware.**
>
> | | |
> |---|---|
> | Bitstream | `build/vivado_out/nanosoc_eth_chiplet_haps_sx.bit` (199 MB) |
> | Setup | **WNS +2.650 ns, TNS 0.000** |
> | Hold | WHS −0.078 ns — one reset-removal path, see §8 |
> | Utilisation | 1.37% LUT, 0.59% FF, 32.5 BRAM tiles, 40 IOB |
> | DRC | clean apart from one waived `LUTLP-1`, see §8 |
>
> The toolchain path is proven end to end: a probe design (`pmod_vlevel`) went
> RTL → Vivado → bitstream → **programmed on the board**, and its measurement
> is what settles §3. What has **not** happened is running the chiplet itself
> on hardware — no LED, UART, SWD, ethernet, HOSTIO4 or d2d result exists yet.
> Sections marked **[UNVERIFIED]** are documentation or desk checks. Walk §7
> before trusting this as a runbook.

---

## 1. What this builds

`nanosoc_eth_chiplet` = `nanosoc_multicore_soc` (two Cortex-M0+ cores, ethernet
subsystem with HA1588, PHC/PTP, QSPI, IPC mailbox) + `tidelink_top` (die-to-die
link) + a TideChart shim. One die. The die-to-die PHY is **looped back inside
the FPGA**, so the link trains against itself and TideLink/TideChart are
exercised without a peer, a ribbon or a second board.

```
                  HAPS-SX VU19P  (XCVU19P, 4 SLRs)
  ┌──────────────────────────────────────────────────────────────┐
  │  nanosoc_eth_chiplet_haps_sx        (fpga/haps-sx/vsrc/)      │
  │                                                              │
  │  GCLK0 100M ─IBUFDS─MMCM─┬─ 25 MHz  sys_fclk                  │
  │                          ├─200 MHz  idelay_ref_clk            │
  │                          └─100 MHz  user_ref_clk (Wlink PLL)  │
  │                                                              │
  │  ┌────────────────────────────────────────────────────────┐  │
  │  │            nanosoc_eth_chiplet                         │  │
  │  │   SoC (2x CM0+) + tidelink_top + tidechart_shim        │  │
  │  │                                                        │  │
  │  │   pad_tx/pad_clk_tx ──┐                                │  │
  │  │   pad_rx/pad_clk_rx ◄─┘  internal loopback             │  │
  │  └────────────────────────────────────────────────────────┘  │
  │       │        │        │         │          │               │
  └───────┼────────┼────────┼─────────┼──────────┼───────────────┘
        RMII     UART      SWD      QSPI       LEDs
      PMOD1/2   PMOD2    Mictor A  on-board    8x
       3.3 V     3.3 V    1.8 V     W25Q32FW   3.3 V
                                    1.8 V
```

Voltages measured, not taken from the manual — see §3.

Why a fresh board top rather than
`tidelink/fpga/vivado_ip/nanosoc_eth_chiplet_vivado_wrapper.v`: that wrapper is
a Vivado IP-Integrator boundary (X_INTERFACE_INFO attributes, `eth_ss_0` as a
PS backdoor) and hard-codes the KR260 "M1" posture — RMII idle, MAC in internal
loopback, QSPI/SPI/hostio tied off. HAPS-SX has no PS, ProtoSynthesis needs no
IPI metadata, and the point of this target is to bring the real pads out.
Neither submodule is forked or modified.

---

## 2. Layout

```
fpga/haps-sx/
├── Makefile                     srclist / gui / build / bitstream / program
├── README.md                    this file
├── vsrc/
│   └── nanosoc_eth_chiplet_haps_sx.sv    board top: clocks, reset, IOBUFs, LEDs
├── scripts/
│   ├── flist_to_sfl.py          VCS flist  ->  ProtoSynthesis source list
│   ├── common.tcl               shared setup (database, options, .cob -> FDC)
│   ├── options.tcl              device + compile options
│   ├── setup_gui.tcl            stage the GUI and stop
│   └── build_haps_sx.tcl        headless full run
├── constraints/
│   ├── nanosoc_eth_chiplet_haps_sx.cob   symbolic pin map (kit resolves to pins)
│   └── nanosoc_eth_chiplet_haps_sx.fdc   clocks, groups, false paths
└── build/                       generated; not in git
```

### The source list is generated, not hand-written

The Pynq-Z2 flow hand-maintains `pynq/filelist.tcl` — ~400 lines of Vivado
`read_verilog` that duplicate what the repo's flists already say, and which
drift (it still carried a PL230 include-inlining hack for a DMA since replaced
by the rendered DMA-250).

This target instead consumes the repo's **existing** flist machinery:

```
flist/flatten_soc_flist.py       SoC generated flist   -> absolute paths
flist/resolve_tidelink_flist.py  TideLink flist        -> one def per module
flist/nanosoc_eth_chiplet.flist  three components + integration RTL
                                       │
              scripts/flist_to_sfl.py  ▼
                       build/chiplet.sfl       (-vlog_std sysv <abs path>)
                       build/chiplet_inc.tcl   (option set include_path {...})
```

`make srclist` re-renders all of it, so a submodule roll is picked up with no
edits here. **Currently generates 585 sources / 19 include dirs, with zero
unresolved variables and zero missing files.** The converter fails loudly on
either, because a silently-short source list shows up as a black box forty
minutes later.

---

## 3. I/O voltage — MEASURED, not inferred

**The PMOD connectors run at 3.3 V. The reference manual is wrong.**

Measured on hardware 2026-07-24 with the `pmod_vlevel` probe design
(`HAPS-work/HAPS-SX/examples/pmod_vlevel`), which drives the PMOD pins to
static known levels: **PMOD1 pin 1 reads 3.3 V** against pin 5 (GND).

An FPGA output's high level *is* VCCO, so a 3.3 V reading means the bank rail
is 3.3 V — regardless of the `LVCMOS18` we had declared. The manual's PMOD pin
table (p65) carries a "Bank Voltage" column reading **1.8 V** for banks
83/88/93. **That column is wrong.**

This also makes the connectors spec-compliant Digilent Pmod, which is exactly
what the 3.3 V on pins 6/12 implied all along.

### What this changes

- **PMOD-attached pins are `LVCMOS_33`.** Declaring `LVCMOS_18` on a 3.3 V bank
  is wrong, and for **inputs** it is out of spec — this design has RMII inputs
  (`phy_rmii_ref_clk`, `crs_dv`, `rxd[1:0]`) on bank 88.
- **No external level translators.** A stock 3.3 V LAN8720 breakout and any
  ordinary 3.3 V USB-UART dongle (CP2102 / FT232 / CH340) connect **directly**.
  Power from PMOD pin 6/12, GND from pin 5/11.
- `phy_mdio_dir` is now redundant (it existed to drive a translator's DIR pin).
  Harmless as an unread output; delete it if you want the pin back.

### What is unchanged, and is silicon-enforced

Only banks **83, 88, 93, 98** are High-Density and therefore 3.3 V-capable.
They carry the four PMODs and the user LEDs. Everything else is
High-Performance and **limited to 1.8 V in silicon** — `LVCMOS25/33/LVTTL`
there fail Vivado DRC **BIVB-1**, and no board setting changes it (verified
with `link_design` + `report_drc` on `xcvu19p-fsva3824-2-e`):

| Connector | Bank | Type | Max VCCO | Used for |
|---|---|---|---|---|
| PMOD1 / PMOD2 | 88 | **HD** | 3.3 V | RMII PHY, UART, MDIO, PPS |
| PMOD3 | 83 | **HD** | 3.3 V | free |
| PMOD4 | 93 | **HD** | 3.3 V | free |
| User LEDs | 83 | HD | 3.3 V | status |
| Mictor1 / Mictor2 | 21 / 22 | HP | **1.8 V** | SWD |
| Push buttons | 20 | HP | **1.8 V** | reset |
| On-board SPI flash | 21 | HP | **1.8 V** | QSPI boot |
| GCLK0 | 23 / 28 | HP | **1.8 V** | system clock |
| **All 24 HT3 slots** | HP | HP | **1.8 V** | — |
| FMC1 / FMC2 HPC | 28/32/33 | HP | **1.8 V** | — |

Consequences that survive the measurement:

- **The SWD probe must still be 1.8 V-capable** (J-Link, ST-Link V3, CMSIS-DAP
  with VTref sensing). Mictor bank 21 is HP. **Do not attach a fixed-3.3 V
  ST-Link V2 clone.** Set M-SW 5-6 (or 7-8) to `on-off` so Mictor A pin 12 (or
  14) presents 1.8 V as VTref — the default is floating and a probe will refuse
  to attach.
- **The on-board QSPI flash is a native 1.8 V part** (W25Q32FW, "W" suffix) on
  a 1.8 V bank — no adapter, no translation.
- **HT3 is not a 3.3 V escape route.** Its "selectable I/O voltage" tops out at
  1.8 V (ConfPro-SX offers exactly `POWER OFF, 0.9, 1.0, 1.1, 1.2, 1.35, 1.5,
  1.8 V`). If RMII signal integrity ever forces the PHY off the 0.1" headers
  onto a length-matched HT3 slot, *that* route needs translators — a
  `74AVC16T245` for the data and a FET part (`LSF0102`) for MDIO.

### Method note

This was argued from documentation for several rounds and the documentation
lost. The manual never states a connector-side voltage; its only voltage column
is about the FPGA bank, and it is wrong for PMOD. If you are ever unsure about
a rail on this board, build a probe design and measure it — it took under an
hour end to end and `pmod_vlevel` is now sitting there to be reused.

## 4. Pin map

All symbolic — `constraints/*.cob` names board resources, and the kit's cobra
helper resolves them to package pins against `haps-sx_vu19p.def`. No package
pin is hard-coded in this repo.

| Function | Resource | Pin | Bank / SLR |
|---|---|---|---|
| `gclk0_p` / `gclk0_n` | `CLK.GCLK0.P.0` / `.N.0` | BN53 / BN54 | 23 / SLR0 |
| `pb1_rst_n` | `DBG.BUTTON.PB1_N` | BK44 | 20 / SLR0 |
| `led[0..3]` | `DBG.LED.R.0..3` | BE13 BD13 BH13 BG13 | 83 / SLR0 |
| `led[4..7]` | `DBG.LED.G.0..3` | BF14 BE14 BH14 BG14 | 83 / SLR0 |
| `swd_clk` | `DBG.MICTOR1.SWDCLK_TCK` | BV55 | 21 / SLR0 |
| `swd_dio` | `DBG.MICTOR1.SWDIO_TMS` | BY50 | 21 / SLR0 |
| `qspi_sclk` / `qspi_ncs` | `MEM.FLASH.CLK` / `.CS_B` | CA49 / CB49 | 21 / SLR0 |
| `qspi_io[0..3]` | `MEM.FLASH.D.0..3` | CC49 CC50 CA51 CB51 | 21 / SLR0 |
| `phy_rmii_ref_clk` | `DBG.PMOD.PMOD1.0` | AW16 (**GC**) | 88 / SLR1 |
| `phy_rmii_crs_dv` | `DBG.PMOD.PMOD1.1` | AW15 | 88 / SLR1 |
| `phy_rmii_rxd[0..1]` | `DBG.PMOD.PMOD1.2/.3` | AY14 AY13 | 88 / SLR1 |
| `phy_rmii_txd[0..1]` | `DBG.PMOD.PMOD1.4/.5` | AV16 AV15 | 88 / SLR1 |
| `phy_rmii_tx_en` | `DBG.PMOD.PMOD1.6` | AU17 | 88 / SLR1 |
| `phy_mdc` | `DBG.PMOD.PMOD1.7` | AU16 | 88 / SLR1 |
| `phy_mdio` / `phy_mdio_dir` | `DBG.PMOD.PMOD2.0/.1` | BA15 AY15 | 88 / SLR1 |
| `uart_txd` / `uart_rxd` | `DBG.PMOD.PMOD2.2/.3` | BB16 BB17 | 88 / SLR1 |
| `phy_nrst` | `DBG.PMOD.PMOD2.4` | BB14 | 88 / SLR1 |
| `phc_pps_out` | `DBG.PMOD.PMOD2.5` | BA14 | 88 / SLR1 |
| `hostio4_p1[0..6]` | `DBG.PMOD.PMOD3.0..6` | BE18 BE19 BG19 BF19 BG16 BF17 BG17 | 83 / SLR0 |

### Ethernet — LAN8720 on PMOD1 + PMOD2

Bank 88 is 3.3 V (measured), so a stock LAN8720 breakout connects **directly**:
signals to PMOD1/PMOD2, power from PMOD pin 6/12, GND from pin 5/11.

The chiplet boundary is **RMII, not MII** — the RMII↔MII bridge lives inside
the ethernet subsystem (`build_soc/rtl/ethernet_ss_ahb_rmii.sv` instantiates
`rmii_to_mii`, already in the SoC flist). The board top wires the pads straight
through. The older Pynq-Z2 flow instantiated `rmii_to_mii` in its *board*
wrapper; copying that here would put two bridges back to back.

`phy_rmii_ref_clk` is on PMOD1 pin 1 (AW16), a **clock-capable (GC) pin**, so
the PHY-sourced 50 MHz lands on dedicated clock routing — an improvement on the
Pynq-Z2 flow, which had to waive `CLOCK_DEDICATED_ROUTE` on a non-CCIO pin.

`phy_mdio_dir` is vestigial — it existed to drive a level translator's DIR pin
and is unnecessary now. Harmless as an unread output.

**LAN8720 gotchas:** `RXD0`/`RXD1`/`CRS_DV` double as `PHYAD[2:1]`/`MODE0` and
are sampled at reset, so FPGA pull-ups/downs on those nets change the PHY
address the MDIO scan must use — if MDIO reads all-ones or all-zeros, suspect
the PHY address first. `nINT/REFCLKO` is dual-function; confirm your module
ships in REF_CLK-**out** mode. Keep the 50 MHz leads to a few cm.

### HOSTIO4 — 7-pin host interface on PMOD3

`nanosoc_ss_hostio4` is strapped `FT1248MODE = 0` (EXTIO mode) at the SoC
level, which maps the uniform `P1[6:0]` tristate bundle onto the HOSTIO4 wire
protocol:

| PMOD3 pin | `P1` bit | Signal | Direction |
|---|---|---|---|
| 1 | 0 | `IOREQ1` | SoC → host (OUTEN tied 1) |
| 2 | 1 | `IOREQ2` | SoC → host (OUTEN tied 1) |
| 3 | 2 | `IOACK` | host → SoC (OUTEN tied 0; **asynchronous**) |
| 4 | 3 | `IODATA[0]` | bidirectional |
| 7 | 4 | `IODATA[1]` | bidirectional |
| 8 | 5 | `IODATA[2]` | bidirectional |
| 9 | 6 | `IODATA[3]` | bidirectional |
| 10 | — | spare | |

Four 8-bit AXI streams are multiplexed over those seven wires — channel 0 TX/RX
is conventionally stdout/stdin, channel 1 TX/RX a bulk data stream. Every pin
gets an IOBUF because the SoC drives a per-bit output enable and four of the
seven genuinely turn around. The SoC's `OUTEN` is **active high**; Vivado's
IOBUF `T` is active-high tristate, hence the inversion in the board top.

**Host side:** the validated driver is the RP2040/RP2350 PIO implementation in
`nanosoc_arch_tech/rtl/hostio4/rpi-pico-pio`. A Pico is 3.3 V and PMOD3 is on
bank 83 (3.3 V), so it connects directly — share GND on pin 5/11, and don't
back-feed the Pico's 3V3 into pin 6/12 while the HAPS board is powered.

Keeping the whole interface on one connector and one bank is deliberate: `IOACK`
is asynchronous and the four `IODATA` lines turn around, so electrical
proximity keeps handshake and data nibble skew together. The interface is fully
hardware-handshaked with no source-synchronous clock, so it is false-pathed —
there is no meaningful setup/hold target to constrain against.

Notes:

- **The RMII reference clock lands on a clock-capable (GC) pin** — an
  improvement on the Pynq-Z2 flow, which had to waive
  `CLOCK_DEDICATED_ROUTE` on a non-CCIO pin.
- **QSPI needs no daughterboard.** The board carries a Winbond **W25Q32FW**
  (32 Mb = 4 MB, natively 1.8 V) on user FPGA pins. 4 MB is exactly the SoC's
  `QSPI_FLASH_ADDR_W = 22` aperture. *Caveat:* the controller and
  `qspi_flasher` firmware were written for a Micron N25Q256A — the Winbond
  command set is broadly compatible but **[UNVERIFIED]**; read the JEDEC ID
  first.
- **SWD on Mictor A needs the M-SW switch.** Set positions 5-6 (or 7-8) to
  `on-off` so pin 12 (or 14) presents 1.8 V as the probe's VTref. Default is
  **floating** and a probe will refuse to attach. You also need a Mictor-38 →
  ARM 20-pin/10-pin adapter.
- **The design straddles SLR0 and SLR1.** Harmless for a design this small and
  slow. If placement complains, either pblock into one SLR or switch the clock
  to `CLK.GCLK0.P.1` (AM61/AM62, bank 28, SLR1) — the same clock's SLR1 copy.

---

## 5. Clocking

`GCLK0` arrives at 100 MHz from a dedicated board PLL (reconfigurable
100 Hz–720 MHz through ConfPro-SX). The board top divides it in one MMCM:

| Output | Divider | Frequency | Use |
|---|---|---|---|
| `CLKOUT0` | 48 | **25 MHz** | `sys_fclk` — the SoC clock |
| `CLKOUT1` | 6 | 200 MHz | `idelay_ref_clk` (IDELAYCTRL) |
| `CLKOUT2` | 12 | 100 MHz | `user_ref_clk` (Wlink PLL reference) |

25 MHz is deliberate: it matches the frequency the Pynq-Z2 firmware is built
and proven at, so the first bring-up changes one variable (the board), not two.
Raise `SYS_CLK_DIV` to `24.000` for 50 MHz once it works — **and rebuild the
firmware with a matching `NANOSOC_SYS_CLK_FREQ_HZ`**, or UART baud and systick
will both be wrong.

The RMII reference (50 MHz, sourced by the PHY) is a separate asynchronous
domain, declared as such in the FDC.

---

## 6. Building

```sh
module load haps-sx-tools           # vivado + confpro_sx + COBRA_PATH

make -C fpga/haps-sx srclist        # source list, from the repo's own flists
make -C fpga/haps-sx xdc            # pin constraints, from the .cob via the kit
make -C fpga/haps-sx bitstream      # Vivado synth + place + route + .bit
make -C fpga/haps-sx gui            # open the routed design in the Vivado GUI
make -C fpga/haps-sx program        # upload over ConfPro-SX
```

`bitstream` depends on `srclist` and `xdc`, so it is the only one you normally
need. ConfPro-SX consumes a `.bit` and does not care which tool produced it, so
the programming step is unchanged from the ProtoSynthesis plan.

### Why not the ProtoCompiler GUI

```
$ protocompiler_s -batch -tcl ...
No such feature exists.
Feature:       ProtoCompilerS
License path:  27020@synopsyslm2:
```

and the licensed `protocompiler` product reports:

```
valid_technologies = HAPS-200 HAPS-100 HAPS-SA3 HAPS-80D HAPS-80 HAPS-70
                     HAPS-DX7_S4 HAPS-DX7_S6 HAPS-ZSA HAPS-ZSA2
```

— no FPGA technology and no HAPS-SX. Forcing `-licensetype ProtoCompiler` onto
`protocompiler_s` lets it start but does not change that list, so it is not a
way in. `make ps-build` / `make ps-gui` keep the ProtoSynthesis path wired up
and will work unchanged if a `ProtoCompilerS` licence is obtained.

**Middle option:** Synplify Premier DP **is** licensed here (100 seats) and
carries `HAPS-SX-VU19P-{20G,28G,32G}` targets natively
(`xilinx_parts.txt:5116`). That keeps a Synopsys front end and Identify
instrumentation, with Vivado still doing P&R.

### Constraints are generated, not hand-written

The `.cob` is the single source of pin truth. `make xdc` runs the Synopsys kit
helper to resolve symbolic resources (`DBG.PMOD.PMOD1.0`, `MEM.FLASH.CLK`, …)
to package pins against `haps-sx_vu19p.def`, then `scripts/fdc_to_xdc.py`
converts the result to valid XDC and appends the timing constraints.

That converter exists because the kit's own XDC mode is unusable: it emits bus
bits unbraced (`[get_ports pmod1[0] ]`, where Tcl evaluates `[0]` as a command)
and drops `define_io_standard` entirely, so pins arrive unconstrained and fail
DRC. The pin data is still Synopsys's; only the syntax is ours.

---

## 7. Bring-up sequence

Do these in order. Each step isolates one variable; skipping ahead turns a
five-minute diagnosis into an afternoon.

0. **Smoke-test the flow, not the design.** Build and run
   `HAPS-work/HAPS-SX/examples/hello_sx` first. It proves licence checkout, the
   device string, `.cob` → FDC, the Vivado handoff and `confpro-program` in
   isolation, with an RTL design small enough that nothing else can be at
   fault.
1. **Measure the PMOD voltage** (§3.2) before connecting a PHY or a dongle.
2. **Recover the XVC server.** Port 2542 on `ecshaps` is single-client and was
   previously wedged by a stray byte; it needs a board reset. Confirm with the
   `getinfo:` handshake before relying on Identify or Vivado hardware manager.
3. **LEDs + heartbeat.** `led[7]` blinks whenever `sys_fclk` is alive — this
   separates "not configured" from "configured but stuck".
4. **UART banner.** Proves CPU0, the IMEM `$readmemh` preload and the clock
   frequency all agree. If the LEDs live but the UART is silent, suspect
   `RAM_PRELOAD` or a clock-frequency mismatch before anything else.
5. **SWD.** Halt, CPUID readback, DMEM round-trip on both APs, using the
   existing `nanosoc-multicore-system/pynq/scripts/openocd/` configs unchanged
   — the SoC is strapped SWD-only, so `transport select swd`.
6. **QSPI.** Read the JEDEC ID *first* and confirm the Winbond part answers,
   then try `qspi_flasher`.
7. **D2D loopback.** `led[4]` (link active) and `led[5]` (role locked) should
   assert. TideLink registers are reachable at `0x2E03_0000` through the D2D
   window.
8. **HOSTIO4.** Attach a Pico running the `rpi-pico-pio` driver to PMOD3.
   Quiescent state first: with both requests de-asserted the target drives
   per-channel ready status on the 4-bit bus, so a scope on `IODATA[3:0]`
   should show a stable pattern rather than floating. Then a channel-0 byte
   round-trip (stdout/stdin). If it hangs, check `IOACK` (PMOD3 pin 3) before
   anything else — it is the one asynchronous line and the only input of the
   seven.
9. **Ethernet + PTP.** MDIO PHY ID first — that is the step that catches a
   wrong PHY address from the `RXD0`/`RXD1`/`CRS_DV` strapping. Then MAC
   loopback, then a live link, then `ptp4l`.

### Debug with Identify

Instrumentation is built into this flow: set `ENABLE_DBG`, add
`run pre_instrument` and `run compile -idc debug.idc`. Use
`device jtagport builtin` so the IICE sits on the VU19P's own BSCAN and is
reachable through the board's XVC server on `ecshaps:2542`. Use the **2025**
bundled `identify_debugger` — do not mix it with the 2022.09 instrumentor.

---

## 8. Known risks

### Three things found by building it, worth knowing before you change anything

**1. The TideLink PHY runs at 3.125 MHz, not the MMCM rate.** An earlier
revision fed `user_ref_clk` 100 MHz straight from the MMCM. Place & route could
not close: **WNS −4.451 ns, TNS −494.7 ns**, concentrated in the link domain.
The KR260 target — the only configuration this PHY is proven in — takes a
25 MHz clock through a /8 counter to give **3.125 MHz**. We now reuse its
`tidelink_phy_clk_div2` module (not a copy: the timing constraints match on
that module's *internal* names). After the fix, **WNS +2.650 ns**. If you
re-time the PHY, expect to re-close timing.

**2. Two TideLink generated clocks must be declared.** `user_ref_clk_div2`
(÷8) and `gpiotx0_word_clk` (÷16). Without them `report_clocks` lists only
`gclk0`, `rmii_ref_clk` and the MMCM outputs — the whole link-timing island is
invisible and gets timed against its full-rate parent. KR260 records that the
word clock is a **functional** requirement, not just a timing one: without it
`io_rreset` never sync-deasserts, `link_empty` stays 1, and no data is ever
transmitted.

**3. One `LUTLP-1` combinatorial-loop DRC is waived**, or `write_bitstream`
refuses to run. See `constraints/*_drc.xdc` for the full argument. Short
version: KR260 waives the same class for the intentional AHB-Lite HREADY
loopback; the genuinely dangerous cycle was fixed in RTL on 2026-07-10 with a
mutation-tested guard (`docs/design/D2D_HREADY_LOOP.md`); and the reported cells span
functionally unrelated blocks sharing a `dflt_err2` term, which is the
signature of LUT merging rather than an architectural cycle. **The waiver
currently matches 490 nets** — broader than ideal, because it covers whole
`u_xhb_sub/u_core/{u_resp,u_wdata}` subtrees. If you are debugging a hung bus,
remove it and re-run `report_drc -checks LUTLP-1` on the routed checkpoint
first.

| Risk | Status / mitigation |
|---|---|
| Hold: WHS −0.078 ns | ONE path, a *removal* check: the reset synchroniser deasserting into the QSPI controller's async CLR, across a very large die. Not a data path; happens once at startup. Acceptable for a prototype. To clean it, replicate the reset synchroniser output or drive it on a global buffer. |
| `LUTLP-1` waiver breadth | 490 nets. Tighten to the specific loop nets once the hierarchy is stable. |
| ~~PMOD connector voltage~~ | **RESOLVED 2026-07-24 by measurement: 3.3 V.** The manual's PMOD "Bank Voltage" column is wrong. Constraints updated; no translators needed. See §3. |
| Split `option set part/package/speed_grade` form | **[UNVERIFIED]** on `protocompiler_s`. Fallbacks in `options.tcl`. |
| `(* ram_style = "block" *)` is a Vivado attribute | Synplify wants `syn_ramstyle="block_ram"`; it infers BRAM by default anyway. Check the map report for the IMEM/DMEM. |
| `$readmemh` path resolution | Pass absolute paths via the `*_IMEM_MEM_FPGA_IMG` parameters. |
| W25Q32FW ≠ N25Q256A command set | Read the JEDEC ID before trusting the boot path. |
| Memory sizing | 2,160 BRAM36 ≈ 9.7 MB + 320 URAM ≈ 11.5 MB. A byte-enabled memory of *B* bytes costs ≈ *B*/4096 BRAM36, so 1 MB ≈ 256. The ASIC's 16 MB IMEM + 16 MB DMEM will **not** fit; ~4 MB each is the ceiling and needs URAM steering. |
| XVC server wedges easily | Single-client; recover by board reset. |
| SLR0/SLR1 straddle | Only slow signals cross. Pblock into SLR1 if placement complains. |
| ProtoSynthesis licence feature | Server shows `ProtoCompiler` ×100 free; `protocompiler_s` has run before on this install. `-licensetype` available if it picks wrong. |

---

## 9. References

- Board: `HAPS-work/HAPS-SX/docs/cd_sx_haps-sx_vu19p_1f_32g_ref_man_v1.3.pdf`
  (pin tables p25–65, clocks p49, Mictor p64, PMOD p65, M-SW p19/22).
- Kit + pin-assignment app note: `HAPS-work/HAPS-SX/haps-sx_helper/`,
  `docs/cd_sx_appnotes_haps-sx_vu19p_fpga_pin_assignment.pdf`.
- Working minimal example: `HAPS-work/HAPS-SX/examples/hello_sx/`.
- Board/tool runbook: `HAPS-work/README.md`.
- Sibling FPGA targets: `nanosoc-multicore-system/pynq/` (Pynq-Z2, proven on
  silicon), `tidelink/fpga/targets/kr260-eth-chiplet/` (KR260),
  `docs/bringup/KR260_BOARD_WIRING.md`.
- OpenOCD/SWD: `nanosoc-multicore-system/pynq/scripts/openocd/`.
