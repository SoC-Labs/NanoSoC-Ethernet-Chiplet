# rc4 issue register — what is wrong with the taped-out eth die, and what it costs

    status     REGISTER. Read-only audit, 2026-09-23. No tool was run and no build
               directory was written; every claim below is read from a file already
               on disk, a netlist grep, or a ROM stream extraction, and cited to it.
    design     rc4-20260829 — ASIC/eth-chiplet/build/rc4-20260829/outputs/
               nanosoc_eth_chiplet_pads_rc4_logo.gds
               md5 6b0833c4216bdb683ed2427cd0deba75, 303,996,534 B
    submitted  Europractice / imec, 1 September 2026
    lineage    rc4 = rc3fix routed DB + 3 cell resizes (ECO). Synthesis is
               gdsrun-20260826-rc1: eth 4b625c4 (dirty tree), nanosoc-multicore-system
               f60449b, tidelink 5e8bdb5a (v0.90), axi-chiplet-controller efe5623
               (gdsrun-20260826-rc1/PRE_RUN_MANIFEST.txt). None of build/gls-netlist/
               {gdsrun_cc,rzg_cc,fp1505_cc} is the rc4 netlist.
    method     Four independent audits (D2D link; SoC/debug/DFT; timing/CDC/LEC;
               physical/foundry/provenance). Each checked the flagged claim against
               rc4's own netlist (build/rc4-20260829/outputs/*_rc4_pnr.v), its ROM
               stream, or its reports — a fix that landed in RTL after 08-26 is NOT
               in silicon.

---

## 0. The answer

**Nothing found stops the die from being brought up, but three things stop it from
bringing ITSELF up.** Every bring-up blocker below has a post-silicon route —
flash firmware, a debugger/HOSTIO write, or a slower board oscillator. None needs a
respin.

**The real cost is reliability of the D2D link.** Once the link is up, a single lost
response or lost ACK wedges the peer port until the die is power-on reset, and
nothing in silicon recovers it. That cannot be fixed without a respin; it can only
be made rarer (good eye, lower clock) and survived (POR + re-train).

**The foundry never checked the IO supply/ESD network on this stream.** ERC bailed
on every submission including rc4, and PadShorts never ran on rc4. Low probability
of a real defect (the pad netlist did not change since the last PadShorts pass), but
it is unmeasured, and it is the one item imec can still answer from the GDS they
hold.

**imec graded the exact rc4 bytes on 31 Aug. No acceptance is recorded anywhere
reachable** — broker mail is untracked (doc 58), and the rc4 return
(`ASIC/imec_results/Archive_..._rc4_logo_merged_dummyWithSealRing_31Aug26_17u35/`)
was downloaded 1 Sep and never analysed until this audit.

---

## 1. Register, most severe first

| # | Issue | Class | Respin needed? | Workaround |
|---|---|---|---|---|
| B1 | No resident `ROLE_CFG` writer — the D2D pair never trains on its own | BRING-UP BLOCKER | no | flash image, debugger or host writes `0x2E032080` |
| B2 | QSPI boots at SCLK = 50 MHz, never characterised | BRING-UP BLOCKER (risk) | no | slower board oscillator; HOSTIO loader |
| B3 | HOSTIO/ADP monitor can hang the die until power cycle | BRING-UP BLOCKER (procedural) | no | address blocklist; `IOACK` pull-up |
| B4 | CPU firmware comes only from flash; no UART/JTAG; SWD has never answered | BRING-UP LIMITATION | no | see §3 (boot without flash) |
| R1 | A stall on the peer port is terminal — POR only | RELIABILITY | **yes** | POR + re-train |
| R2 | AXI flow-control nodes have no re-ACK/watchdog — a lost ACK wedges a channel | RELIABILITY | **yes** | clean eye, lower clock, POR |
| R3 | AR/R replay nodes lack the TL-027 self-heal | RELIABILITY | **yes** | as R2 |
| F1 | ERC never executed; PadShorts never run on rc4 | UNCHECKED (foundry) | no | ask imec to run on the GDS they hold |
| P1 | Static IR drop not in timing; setup margin +15 ps | MARGIN | no | run at 1.2 V; V/f shmoo |
| P2 | EM over limit on VSS pad feeds (rc3fix) | RELIABILITY (probably false red) | no | Voltus with SAIF on `db_rc4` |
| S1 | Debug permanently unlocked | SECURITY (deliberate) | yes, to change | none; correct the docs |
| T1 | No scan, no MBIST, ICG `TE` tied low | TEST COVERAGE | yes | none |
| N2 | D2D pad interface timed against placeholder delays | UNQUANTIFIED — most likely link fault | no | CLK = 50 MHz for bring-up |
| N1 | Raw NRST async-resets ~4,027 flops, no synchroniser | UNQUANTIFIED | no | release NRST with CLK stopped; re-init PHC |
| N3-N7 | Single RC corner, FF-only hold, 20 % checks untested, no CDC on shipped RTL, no LEC of rc4 | MARGIN / PAPER GAP | no | ~95 MHz on slow parts; VDD ≤ 1.2 V |
| V1 | Shipped link configuration has never carried traffic on any platform | VERIFICATION GAP | no | V2 ASIC-flist traffic regression |
| X1 | rc4 cannot be rebuilt or diffed | PROVENANCE | no | archive `db_rc4` + ECO scripts now |
| M1 | Two SRAM macros ship with EMA = 000 (minimum read margin): TideLink FIFO rf_16k and MAC BD RAM rf_01k | MARGIN / YIELD (unquantified) | yes, to change | run at VDD ≥ 1.2 V; end-to-end data checks; BD RAM march test |
| D2D-DMA | DMA-250 copies to or from the D2D window 0x2E–0x2F corrupt data silently and report DONE (added 2026-10-05) | FUNCTIONAL (silent corruption) | yes, to fix | **never point the DMA-250 at `0x2E00_0000–0x2FFF_FFFF`**; M0+ LDR/STR for peer data |

The full entry for each follows. Minor functional limitations are in §4.

---

## 2. D2D link (TideLink)

### B1 — No resident `ROLE_CFG` writer; the pair never trains on its own

- **In silicon: CONFIRMED.** Both ROMs extracted from the rc4 GDS
  (`build/rc4-20260829/reports/rom/{cc,eth}_gds.bits`) contain no `0x2E03xxxx`
  literal. The writer (`7f17cbc`, multicore submodule branch
  `park/resident-role-writer-2026-09-23`) was written after submission. Netlist
  module name carries `SELF_ARM_TRAIN_EN1`, `NEGO_CFG_RESET0`, so autoneg is dormant
  and `role_lock` is set only by a software W1S. `role_strap_i` is unconnected
  (`rc4_pnr.v:1200755`).
- **On silicon:** `wlink_por_reset = ~poresetn | ~role_locked`
  (`tidelink/src/rtl/local_overrides/axi_chiplet_controller.sv:3154`) holds the link
  in reset, so `pad_clk_tx` stays gated. The compute die's RX clock *is* that
  signal. Neither die trains.
- **Recovery (no respin):** write `0x03` (die_b) to `0x2E032080` from a CPU1
  application image in QSPI flash, a debugger, or a host. The value must be a
  constant — the strap reads 0 on both dies. The V2 sim (09-23, calibrator bypass
  off, ideal pads, one seed) shows that write alone trains both dice to FCSM==4.
- **Open:** `docs/bringup/D2D_PAIRING_DECISION.md` §2 is blank. Compute holds
  die_a/master, so die_b is the zero-change choice for eth. That doc says §2 must be
  filled "before the 2026-09-24 submission" — rc4 went on 1 Sep, so that date needs
  confirming (it may refer to the compute die). The J21 ball-map orientation
  (`docs/design/CHIPLET_ALIGNMENT.md:151`) is unconfirmed and presents as the same
  "link is dead" symptom.

### R1 — A stall on the peer port is terminal: POR only

- **In silicon: CONFIRMED** (shipped RTL documents it). `tidelink_top.sv@5e8bdb5a:1720-1770`:
  after a lost R response XHB500's `read_counter` stays non-zero and every later peer
  access stalls. The TL-037 backstop returns ERROR but "CLEARS NOTHING".
  `wr_hold_clr` (`:2008`) has no pre-accept abort (TL-042 never landed). Both
  backstops are aggregate-progress timers (`:1712`, `sub_axi_progress`), not
  per-transaction. Warm reset is tied off (`docs/TAPEOUT_LIMITATION_D2D_PEER_WRITE.md`).
  FPGA at the same freeze: a failed read left `0x21F8` bit0 stuck and the next write
  hung (n=1).
- **On silicon:** after one lost response, every peer access hangs or bus-errors
  after ~655 µs (2^16 hclk at 100 MHz) until die POR. POR drops the link; both dice
  re-train. CPU0 has no watchdog.
- **Implication:** every transient on the link becomes a system reset. Firmware must
  treat a peer bus error as "POR and re-train", not "retry".

### R2 — AXI flow-control nodes have no ACK recovery

- **In silicon: CONFIRMED.** All 54 `socl_*` recovery registers sit under the
  sideband node `tl2wl_wlink_tidelinktl_`; zero under `axi2wl_wlink_axi{aw,w,b,ar,r}FC`.
  The ship flist takes FCSM 0-5 from `deps/` (`:309-321`), whose ACK sources are
  `isExpPacket | l2a_fifo_raddr_txclk_update` only. ACK packets carry no CRC and no
  sequence number and ride lanes 0-1 only. The sideband node's NACK watchdog is
  disarmed by the first CRC error (TL-036, `socl_l7_real_crc_seen` in netlist).
- **On silicon:** lost ACKs while a node's window is full (≥2-bit header error or a
  framing slip on lanes 0/1) stop that channel permanently → R1. ECC is active in
  rc4, which should make this rarer.
- **Caveat:** mechanism sim-proven on the FPGA-v2 flist only, never on the ASIC mirror.

### R3 — Read-path replay nodes lack the TL-027 self-heal

- **In silicon: CONFIRMED as structure.** Flist `:306/:308` takes deps `_7`/`_9`
  (`w_inc = a2l_link_addr != a2l_link_addr_in`, `:116`); the AW/W/B override `_1`
  has `w_inc = 1'b1` (`:143`). No override for `_7`/`_9`.
- **On silicon:** a torn ACK-pointer sample can permanently false-full AR or R → R1.
  Probably rarer on ASIC (TX word clock and hclk share the CLK pad) — inference.
  Cross-die read failures seen earlier were an ssh artefact, so reads are not known
  to be broken.

### V1 — The shipped link configuration has never carried traffic

- CRC is ON at reset on all 7 FC nodes (async-clear flops, `rc4_pnr.v:951139-956593`),
  ECC on, AXI FCSMs without recovery. The FPGA runs CRC off with recovery on; the g2
  bench runs the V1 PHY with the calibrator bypass. The only V2 no-bypass run is the
  09-23 bring-up sim (ideal pads, one seed).
- CRC can be disabled at runtime (FC base + `0x14`, bit 16) but that permits silent
  payload corruption (`docs/verification/CDC_AND_CRC_ASSESSMENT_2026-08-17.md` §5.1).
  **Keep it on.**

### D2D limitations with a firmware workaround

- **Link rate fixed at /1.** `u_link_clk_div.ratio_i` unconnected, tied `3'd0`;
  `LINK_RATE_REGS_PRESENT=0`. TX runs at the CLK rate (10 ns). The only rate lever
  is the board CLK, which slows the whole die. Eth TX clock-to-data skew has never
  been measured (~20 min on a copy of `db_rc4`, method in the notes).
- **Peer writes are single-beat.** `HPROT[3:2]` tied `00`. ~224 hclk per word on
  FPGA, 75-100× slower than posted writes. By design.
- **Peer-aperture hazards.** `hsel_peer` not gated on `link_active`
  (`chiplet_d2d_decode.sv:200`); the CAM at `0x2E034000` must be programmed; apps
  `default_slave_error_walk` and `busfault_irq_route` poke `0x2E`/`0x2F` believing
  them unmapped; `0x21AC/0x21B0/0x21B4` hard-stall the CPU. Any of these parks the
  port (R1). Firmware discipline only.
- **TideChart can elect two roots** (FPGA 08-08, cause open, UNVERIFIED on rc4).
  Pin roles via `ROLE_CFG` and the PTP grandmaster by register.
- **T6 endurance wedge at beat 1024** (FPGA, n=2, UNVERIFIED). May be R2.

### D2D-DMA — The DMA-250 must never target the D2D window (added 2026-10-05)

- **In silicon: CONFIRMED on the shipped RTL in simulation** (pre-silicon closure item 11 follow-up,
  `docs/chip-reference-manual/review/closure/item11-tl053.md` §"Follow-up 2026-10-04"). Bench: g2 pair,
  generated ASIC `tidelink_asic.flist` at `785daee` (= rc4 `5e8bdb5a` in src/deps/flists), calibrator bypass
  off; die A's DMA-250 channel 0 programmed over eth_ss_0 with the `dma250_driver.c` layout (1D, 32-bit,
  16 words). The DMA master decode reaches `0x2E–0x2F` (`multicore_matrix_decode_DMAC_0_M.v`).
  - **Peer→peer** (`0x2F001100 → 0x2F001200`): DONE, err = 0, but all 16 destination words read back 0x0
    and **every destination word was written twice** at die B; the d2d monitor saw a write NONSEQ during a
    stalled peer read on 7,866 cycles. This is TL-053 on every beat. Deterministic; independent of order.
  - **Local→peer** (source DMEM `0x1800_0400`): 32 peer write address phases for 16 words; each word written
    **2 or 3 times** at die B; destination ≠ source. The duplicated-write class (M4DUP), fixed by tidelink
    `b08145a`, which the eth pin lacks.
  - **Peer→local**: 31 peer read address phases for 16 words; destination ≠ source.
  - All three report DONE with err = 0: **silent corruption**.
- **Why DSB does not help:** the hazard is inside the DMA's own pipelined AHB stream; only a DMA-side rule
  works. The eth Cortex-M0+ does **not** trigger TL-053 (4 LDR→STR shapes clean, same item), so DSB before a
  peer store stays advisory for M0+ code.
- **Rule (firmware):** **never point the DMA-250 at `0x2E00_0000–0x2FFF_FFFF`, as source or destination.**
  Move peer data with M0+ LDR/STR. `dma250_mem2mem_1d()` should refuse D2D-window addresses on the eth die.
  Shared SRAM `0x2D…` is outside the DMA's decode (STAT_ERR), so local buffers must be in DMEM/IMEM.
- **Fix for a re-spin:** take tidelink `b08145a` (TL-053/M4DUP), then re-run `item07/g2/test_tl053_dma.py`.

---

## 3. SoC, boot, debug, DFT

### B2 — The boot ROMs read flash at SCLK = CLK/2 and never set the divider

- **In silicon: CONFIRMED.** `CLK_DIV` (`0x21000034`, `reg13`) resets to 1
  (`apb_qspi_regs.v:181` at ahb_qspi `e908ac8`; netlist `reg13_reg[0]` is a set flop
  `DFSNQD1`). `qspi_clock_div.v` toggles SCLK every HCLK at DIV=1, so SCLK = CLK/2 =
  50 MHz at a 100 MHz board clock. Neither ROM writes `0x34`: the cc ROM touches only
  `0x21000008–0x21000030` (`stage0_bootrom_chip_core.lst`), and the eth ROM
  deliberately does not reprogram the controller. Both shipped ROM images are
  byte-identical to those ELFs (checked 2026-09-23: 443 and 320 words, rest zero).
- **Why STA never saw it:** `qspi_constraints.sdc:87-88` models the flash return as
  `set_input_delay -max 1` against the *rising* edge of the internal `QSPI_SCLK`.
  The RTL launches and captures on the **falling** edge (`qspi_controller.sv`
  `always @(negedge QSPI_SCLK_i)`, capture at `:624-627`), and a mode-0 flash
  launches on the pad's falling edge. The check that ran has no relation to the real
  path.
- **Hand budget from the RTL (estimate, not measured):** the controller samples, at
  each internal falling edge, the bit the flash launched one full SCLK period
  earlier. At CLK = 100 MHz that is **20 ns** for SCLK pad-out + flash clock-to-output
  (~5-7 ns for an N25Q-class part) + board + input pad — plausibly 8-13 ns in total.
  **So 50 MHz probably works**, but no measurement or valid STA says so, and two
  in-tree FPGA notes contradict each other (`ahb_qspi/sw/qspi_regs.h:142` vs
  `firmware/apps/qspi_selftest/main.c:158`).
- **On silicon if it fails:** every flash read returns garbage, CPU1 finds no valid
  table, releases CPU0, and parks. CPU0 finds nothing and halts. No firmware runs.
- **Workarounds:** see §3.1. The cheapest is a slower board clock — there is no PLL
  (`SYS_HCLK` = CLK pad).
- **Decision owed:** the bring-up board oscillator frequency.

### B3 — The HOSTIO/ADP monitor can hang the die

- **In silicon: CONFIRMED.** The ADP FSM has no HREADY timeout; `ADP_UPLOAD_TIMEOUT`
  is not compiled in (0 netlist hits). A fill (`F`) or upload (`U`) whose only error
  is on the last beat reports clean. All seven HOSTIO pads plus NRST and CLK have
  `REN` tied high — no on-die keeper.
- **On silicon:** touching a stalling address (HZ-1/-2/-3/-6: XiP `0x24…`,
  `0x2E0321A0–B8`, `0x2F…`) wedges the port until power cycle; a truncated `U`
  parks the monitor; a floating-low `IOACK` sticks the FSM in `TXC1`.
- **Procedure:** follow the blocklist in `docs/bringup/ASIC_FIRST_SILICON_HOSTIO_PROCEDURE.md`,
  pull `IOACK` high on the board, read back the last word of every fill/upload.

### B4 — Firmware only from flash; the MAC is reachable only through firmware

- **In silicon: CONFIRMED.** No UART, 1PPS or JTAG pads (netlist top ports).
  `debug_m` (HOSTIO master) has no window onto the MAC (`0x40000000`), eth-SS APB
  (`0x50000000`) or per-core debug (`0xA0`/`0xB0`)
  (`f60449b:sys_desc/nanosoc_multicore_soc.yaml:2347`). SWD has never returned a
  DPIDR on any board. The path flash → firmware → MAC has never run on any vehicle.
- See §3.1 for what can and cannot be done with no flash.

### 3.1 Booting without flash, and workarounds for B2

Everything here is read from the shipped ROM listings, the ahb_qspi RTL at the
synthesised pin (`e908ac8`), the rc4 netlist, and the generated bus-matrix decoders
(`nanosoc-multicore-system/build_soc/rtl/multicore_ahb_interconnect/`, dated 08-18,
gitignored — cross-check against the `f60449b` YAML before relying on an address).
**None of it has been run on a die.**

#### What the die does at power-up with NO flash fitted

This **contradicts** `docs/bringup/ASIC_FIRST_SILICON_HOSTIO_PROCEDURE.md` §0.3,
which predicts "CPU1 HardFaults at `0x080001CE`, CPU0 stays in reset".

1. **CPU1's XiP read does not error.** The QSPI engine's state machine is purely
   counter-driven. Flash data (`QSPI_IO_i`) only feeds the shift register
   (`qspi_controller.sv:624-627`), so an absent device cannot stall it, and the
   16-bit watchdog in `ahb_qspi_interface.sv` never fires. The read returns
   whatever the pins float to. The HZ-6 watchdog hazard needs a wedged engine, not a
   missing chip.
2. **CPU1 then fails every boot table, releases CPU0 (`0x29000000 = 4`,
   `0x08000528`), and parks in `wfi` (`0x08000534`).**
3. **CPU0 finds no table either, and parks** in `halt()` — `wfi`, after writing
   `'X'` to the internal UART at `0x50001000` (no pad).
4. **The catch — CPU1 may take seconds to get there.** Before XiP, the ROM programs
   a boot-attempt counter byte and polls the flash busy bit up to **16,777,216 times**
   (`0x080003A6–0x080003B4`, limit `0x01000000`). `QSPI_IO1-3` pads have `REN` tied
   high (no pull; `rc4_pnr.v:1321689-1321699`), so with no flash IO1 floats.
   Reading as 1s, the poll runs to its limit — roughly 10-30 s depending on CLK
   (estimate, ~80 HCLK per poll). Reading as 0s, the counter step is skipped and
   the boot takes microseconds.
   - **Board fix: a pull-down on `QSPI_IO1`** makes the no-flash boot fast and
     deterministic.
   - **Bench consequence:** `0x29000000 == 0` may just mean "still polling". Re-read
     after 60 s before classifying it.

#### Can either CPU boot without flash?

| | Verdict | How |
|---|---|---|
| **CPU1** | **Yes, over HOSTIO** (never run on a die) | Upload an image to CPU1 IMEM at `0x90000000`; set `0x29000000` bit 0 (CPU1 REMAP — write-1-set, clears only at power-on); pulse `CPU1_SWRST` (`0x2A000020 = 2`). CPU1 then fetches its vectors from IMEM and never runs its ROM. `CPU1_SWRST` resets the whole fabric including HOSTIO, so the link drops and must be re-entered (procedure §5.3, §6.3). Settle the conflicting `fw_abi.h` note first with the four commands in §6.3.1. |
| **CPU0** | **No, except over SWD** | CPU0 always starts in its ROM, which overwrites eth IMEM from flash and halts without a CRC-valid image. The register that would skip the ROM — eth `sys_remap_ctrl` at `0x50002000` — is decoded **only** by the DAP (`multicore_matrix_decode_DAP_SS_0_M.v`, region `0x50000000-0x5fffffff`). HOSTIO (`DEBUG_M`) and CPU1 (`CPU_SS_1_M`) stop at `0x2FFFFFFF` / `0x80000000-0x9FFFFFFF`. So neither HOSTIO nor CPU1 code can redirect CPU0. SWD could, but has never returned a DPIDR on any board. |

**Consequence:** with no flash and no SWD, CPU0 never runs code — so the Ethernet
MAC (reachable only from CPU0 or the DAP) is unreachable.

**The one flash-free route to CPU0 is at board level:** an SPI-NOR emulator (an
FPGA or MCU answering reads on the QSPI pins) or a socketed flash programmed
off-board.

#### Workarounds for B2, cheapest first

1. **Slower board clock.** CLK = 50 MHz gives SCLK = 25 MHz, doubling the read
   budget to 40 ns. It is also what the D2D link wants for bring-up (N2). Costs: the
   CPUs run at 50 MHz; `NS_INCR` must be 20, not 10. No procedure, no firmware.
2. **Full-speed clock, re-boot CPU0 only, over HOSTIO.** Needs provisioned flash and
   no firmware:
   1. Let both ROMs park (`0x29000000` reads `0x4`).
   2. Write `CLK_DIV`: `A x21000034 ; Wx00000002` (or 4).
   3. Prove flash reads are now correct over the APB command path. Use a
      JEDEC-ID or boot-table-magic read through `0x21000008`/`0x21000010`, never the
      XiP aperture (HZ-6).
   4. Pulse `CPU0_SWRST`: `A x2a000020 ; Wx00000001`. CPU0's ROM re-runs, finds
      `XIP_ACTIVE` still set (CPU1's ROM set it), and loads its image at the slower
      SCLK.
   - Unverified: that `CPU0_SWRST` leaves the QSPI registers alone (the procedure
     doc's HIO-503 assumes so), and whether the CG092 XiP cache (APB `0x21001000`,
     never written by either ROM) holds lines filled at the bad rate.
3. **Full-speed clock, both CPUs, via a CPU1 shim.** Upload a small image to CPU1
   IMEM. The image:
   1. sets `CLK_DIV`, `AHB_SETUP = 0x800B` and `XIP_ACTIVE`;
   2. publishes `0xD15C0001` to IPC mailbox slot 1;
   3. copies CPU1's application from flash, or is the application;
   4. pulses `CPU0_SWRST`.

   Enter it with REMAP bit 0 + `CPU1_SWRST`, as in the table above. This is also the
   natural home for the `ROLE_CFG` write (B1), `NS_INCR` (§4) and a safe `CLK_DIV`
   on every later boot. About half a day to write and sim.
4. **Reprogram the flash from HOSTIO** through the QSPI APB command aperture
   (`0x21000000`). Possible, but listed as not-for-first-silicon (procedure §10.1
   row 6). It fixes contents, not the SCLK rate.

### S1 — Debug is permanently unlocked

- **In silicon: CONFIRMED.** `DEBUG_UNLOCK_DEFAULT = 1'b1`
  (`tidelink/src/rtl/tidelink_top.sv:187`); the ASIC DFT wrapper that would clear it
  is in no flist and the chip instantiates `tidelink_top` directly
  (`src/rtl/nanosoc_eth_chiplet.sv:925`); netlist module name has no unlock
  override. `dbgen`/`spiden` tied 1.
- **On silicon:** any SWD host gets full debug of both cores unauthenticated; local
  software or HOSTIO can write Wlink configuration while in slave role.
- **This was deliberate** (DECISION #2, 2026-07-19, `tidelink_top.sv:161-187`: driving
  unlock to 0 stalled both dies at fcsm=2 on 07-24). Low exposure for a research die.
  **`docs/design/PIN_MAP.md:164-188` says "locked" and is wrong.**

### Debug AHB bridge defects

- **In silicon: CONFIRMED.** At synthesis, `nanosoc_dbg_ahb_bridge.v:176` drives
  `HRESP = 1'b0` and `ST_DONE → ST_IDLE` unconditionally; the fix `e51be17` is dated
  09-18. A failed core-debug access returns OKAY with stale data; 15/16 of each 16 MB
  window aliases; back-to-back accesses drop. Use single accesses and verify by
  read-back.

### T1 — No scan, no MBIST, clock gates cannot be forced on

- **In silicon: CONFIRMED.** 3,007 `CKL*QD*` gates, all `.TE` tied low;
  `sys_scanenable` unconnected; the 3,761 `SDF*` cells are functional load-enable
  flops, not a chain. No ATPG, no production structural test; a stuck enable leaves
  its bank unclocked with no override.

### Boundary scan — limited

- IDCODE `0x10001001`. All 33 `*_core_in` outputs unconnected (no INTEST — the input
  cells are observe-only by design). HIGHZ not implemented. SE is the TAP reset;
  TDI/TDO share `HOSTIO[0:1]`, so boundary scan and HOSTIO are exclusive, and driving
  TDI before SE is high fights a 16 mA pad driver.

---

### 3.2 Memories

### M1 — Two SRAM macros ship with EMA = 000 (minimum read margin)

- **In silicon: CONFIRMED** (rc4 netlist `nanosoc_eth_chiplet_pads_rc4_pnr.v`; every EMA pin traced to its tie cell):
  - `u_tidelink_fifo_u_fifo_mem_u_sram_u_rf` (rf_16k, TideLink packet FIFO): EMA[2:0] = `FE_OFN101_…LTIELO` ×3 ← `CKBD1` ← `TIEL` = **000**.
  - `u_ethmac_0_u_inner_u_eth_top_wishbone_bd_ram_u_sram_u_rf` (rf_01k, MAC buffer descriptors): EMA[2:0] = `FE_OFN79_…LTIELO` ×3 ← `CKBD4` ← `TIEL` = **000**.
  - Control: the other 7 macros (imem/dmem, scratch rx/tx, shared, rf_32k) read **010**; their bit 1 traces `BUFFD8` ← `TIEH`.
  - RTL sources: tidelink `5e8bdb5a` `src/rtl/fifo/asic/tidelink_sram.sv:56` (`.EMA(3'b000)  // Default extra margin`); nanosoc-multicore-system `ethernet-mac-ahb/src/rtl/asic/ethmac_sram.v:59` (`.EMA(3'b000)`). Both comments say "default", but the compiler default is **2** (`rf_16k.v`/`rf_01k.v` print "Set Value for EMA doesn't match Default value 2"). `sl_sram.v:40` uses `TIE_EMA = 3'b010`, which is why the other 7 are correct.
- **What EMA does:** EMA delays the sense-amp enable to give the bitline more time to develop. The rf_16k Liberty has a separate CLK→Q arc for each setting. At min slew/load: ss 1.08 V 125 °C, 2.28 ns at 000 vs 2.72 ns at 010; tt 1.20 V 25 °C, 1.35 ns vs 1.60 ns. STA times whichever arc applies, so **timing is not the issue**. The issue is the read margin the 0.4 ns buys against weak bitcells, which STA does not model. Whether 000 is yield-safe at ss / 1.08 V / hot is **unquantified**: there is no Monte Carlo or margin data for it in the kit.
- **On silicon:** the failure mode is a wrong bit read back, random and data-dependent, worst at low VDD, slow corner and high or low temperature extremes. There is no parity or ECC on either memory.
  - **TideLink FIFO:** the link CRC covers the wire, not the SRAM. A misread payload word is delivered to the AHB reader with no flag. A misread length/header word misframes the packet (clamped length), shifts later reads, and may set the sticky UNDERRUN/OVERRUN bits. The symptom looks like a link problem but isn't one: CRC/ECC counters stay at 0.
  - **MAC BD RAM:** a misread descriptor means a wrong buffer pointer, length or status. Effects are DMA to the wrong address, dropped or truncated frames, or a hung ring.
- **How bring-up can see it** (T1: there is no MBIST):
  - BD RAM: the CPU can read and write the descriptor area through the MAC registers (OpenCores ethmac maps BDs at offset 0x400–0x7FF; confirm on the eth address map). Run a march test (0/1/checkerboard/address-in-data) from firmware with the MAC idle. This is a direct test of the macro.
  - TideLink FIFO: no direct port. Test it end to end: a peer-write soak with unique per-word tags and a checksum, swept across VDD (1.08 → 1.32 V) and temperature. A TideLink FIFO fault shows up as a data mismatch with **zero** link CRC/ECC counts and no FCSM change. That distinguishes it from a wire fault, which raises CRC counts or causes a replay.
  - Run both at the lowest VDD the board allows first. A clean result at 1.08 V hot is the evidence that 000 is acceptable on the part.
- **Mitigation:** operate at nominal 1.2 V or above for read margin. N3 caps VDD at 1.2 V for hold, so the window is "1.2 V, not lower". Use end-to-end checksums on TideLink payloads in firmware. Re-initialise the MAC on a BD-ring hang.
- **Fix for a re-spin:** tidelink `328214b` (branch `eth/ema-default`, parent `785daee`; md5 `e7b55710…`) sets 3'b010, verified against the rf_16k model and in 4 gate targets. The pin stays at the rc4 lineage; take this commit only before a re-synthesis. `ethmac_sram.v` needs the same one-line change in nanosoc-multicore-system; it has **not** been made.
- **Same defect on compute:** compute had the identical TideLink tie (2 FIFO macros) and fixed it by physical ECO on its RC (LEC golden tidelink `837c747`).

## 4. Minor functional limitations (firmware fixes them)

| Issue | Evidence | Fix on silicon |
|---|---|---|
| PHC `NS_INCR` resets to 4 → PTP time runs at 0.4× at 100 MHz, silently | `apb_regs_ns_incr_r_reg[2]` is a set flop | write `NS_INCR` = 10 (at 100 MHz) to `0x22000008` |
| CoreSight system ROM table absent | `systable` 0 netlist hits; `ROMTABLE_BASE32he00ff003` | none; debugger cannot read part identity |
| QSPI `/1` clock-mux leg built, no block-level LEC of its ICGs | write clamp at `apb_qspi_regs.v:198` makes it unreachable | not needed |
| Power intent (UPF) describes another design; CLP 138 errors | single-commit UPF copied from another project | no silicon effect — rail finds 0 functional cells disconnected |

---

## 5. Timing, CDC, equivalence

**rc4's closure is real but narrower than "setup and hold close" implies.** Setup:
+0.015 ns at ONE corner (SS/1.08 V/125 °C) on a typical-only RC deck. Hold: +0.003 ns
at FF corners only. 20 % of checks never evaluated. No CDC tool has run on the RTL
that taped out; nothing has equivalence-checked rc4's own netlist.

Paths: `B = ASIC/eth-chiplet/build`, `STA = $B/setupclose-20260829/sta_rc3setup/reports`,
SDC = `$B/holdeco-20260827/work/nanosoc_eth_chiplet_pads_routed_src/mmmc/modes/default_constraint_mode/default_constraint_mode.sdc`
(the SDC rc4 was timed with).

### N1 — Raw NRST pad async-resets ~4,027 flops with no synchroniser (NEW)

- **In silicon: CONFIRMED.** In `rc4_pnr.v` the buffer tree on `bsp_nrst_i_in`
  drives 4,004 `.CDN` + 23 `.SDN` pins — `u_phc_0` (899 flops) and
  `u_ctrl_dbg_group` (perf probes ~1,670, bus_dbg, `spinlock_owner_q`, ETC FIFOs).
  RTL connects both blocks' `.HRESETn(sys_sysresetn)`. The SDC treats NRST as
  synchronous to `clk` (`set_input_delay 0.1`, SDC :290), so rc4's Async hold of
  +0.011 rests on that assumption. At SS/1.08 V/−40 °C, rc2 fails Async removal at
  **−1.057 ns on 1,113 endpoints**
  (`$B/coldcorner-20260827/reports/timing_summary_hold_ALL_cold.rpt:37`). SS hold was
  never run on rc4. Not covered by `docs/verification/CDC_RESET_DOMAIN_ANALYSIS.md`.
- **On silicon:** if NRST releases near a CLK edge, flops leave reset on different
  cycles or go metastable. Matters only where D ≠ reset value at release:
  free-running PHC and perf counters start inconsistent; a self-advancing FSM could
  land in an illegal state.
- **Mitigation:** release NRST with CLK stopped (or clear of CLK rising edges);
  firmware re-initialises PHC and debug counters after boot.
- **Retire it:** audit which of these flops have D ≠ reset value at idle; Tempus
  removal from NRST at SS views on `db_rc4`.

### N2 — D2D pad interface timed against placeholder numbers

- **CONFIRMED.** RX: `set_input_delay 1` on `TL_RX[*]` with no `-min`/`-max`
  (SDC :282-304); compute measured D_min 0.352 ns, so RX hold is ~0.65 ns optimistic.
  TX: `set_output_delay 0.8` on `TL_TX[*]` with no `-min` (:312-333). The
  `set_driving_cell` on `TL_CLK_RX`/`TL_RX` (:161-176) is dropped in all three hold
  views (IMPCTE-290 ×108 in `tempus_sta.log`). No lane-skew `set_data_check` /
  `set_bus_skew`. Link divider forced to bypass by `set_case_analysis` (:276-278).
- **On silicon:** calibration failures, bit-slips, CRC/replay storms — especially
  eth→compute at 100 MHz (compute's RX word domain has no constraints). **The most
  likely functional problem on the link**, and it feeds R1/R2.
- **Mitigation:** bring the link up at CLK = 50 MHz (the only rate knob; slows the
  CPU too).
- **Retire it (~20 min each on a DB copy):** `report_timing -early` from `TL_RX*` with
  `-min` 0.35 and −0.4; `TL_CLK_TX` vs `TL_TX[*]` pad skew.

### N3 — RC corners, IR drop and noise not covered

- **CONFIRMED.** All four RC corners use one typical-ICT `qrcTechFile`
  (`$B/setupclose-20260829/mmmc/mmmc_rc3setup_union.tcl`); worst and best SPEFs
  differ by 11 bytes of 323 MB. One setup view. No IR in STA (P1). Flat derate only
  (data 0.95/1.05, clock 0.97/1.03), no AOCV/POCV — none exists in the kit. SI delay
  on (coupled SPEF); glitch/noise off (`si_noise_libs = stripped`).
- **On silicon:** slow hot parts miss setup at 100 MHz; fast parts with cbest RC
  could fail hold — which cannot be fixed after the fact.
- **Mitigation:** ~5 % lower clock on slow parts. For hold, keep VDD at or below
  nominal 1.2 V, never 1.32 V. There is no clock-based fix for hold.

### N4 — 57,955 checks never evaluated, and some hide real paths

- **CONFIRMED** (`$STA/analysis_coverage.rpt`): 57,955 of 287,086 (20.2 %; 7.2 %
  excluding PulseWidth). PulseWidth 49,466 (reset nets, uncomputable); library
  clock-gating 3,007 (TE tied, benign); Setup 2,377; Recovery 2,998; DataCheck 69 of 69;
  ClockPeriod 38. `check_timing` also reports 8,398 unconstrained endpoints.
- The D-pin and async endpoints are real clock-domain crossings cut by one
  `set_clock_groups -asynchronous` (SDC :392). Whether they work depends on
  synchronisers nothing has verified (N5).
- **Retire it:** `report_analysis_coverage -verbose untested` on `db_rc4` (done on
  rc5vt only).

### N5 — No CDC signoff on the taped-out configuration

- **CONFIRMED.** The only SpyGlass run is 2026-08-17 (`build/cdc/b7`), before the
  08-26 synthesis: 139 unsynchronised crossings, 155 errors, and
  `axi_chiplet_controller` excluded (`stop_module`) — the whole D2D controller was
  never analysed. Known RED rows in `docs/verification/CDC_STA_CROSSING_REGISTER.md`:
  `eth_registers.v:1023` vendor "synchroniser" is one flop; PTP queue `aclr` pulse;
  MAC loopback; a 6-bit binary deskew index through a plain 2-flop sync.
- **On silicon:** intermittent Ethernet IRQ or PTP timestamp faults; D2D controller
  CDC unknown.
- **Mitigation:** don't toggle LOOPBCK/TXEN mid-traffic; poll rather than rely on
  the TxC IRQ.
- **Retire it now:** SpyGlass on rc1's flist without the `stop_module`.

### N6 — rc4's netlist has never been equivalence-checked

- **CONFIRMED.** RTL→gate on rc1 `gate.v`: harness says FAIL, Conformal says 42/42
  modules equivalent (the 96 dead enum-cursor flops are proven safe; the
  unreachable-point asymmetry 446 vs 319 is unexplained; boundary scan is
  black-boxed, `$B/lec-rc1-0826/logs/lec_syn_tool.log`). Post-P&R LEC passed on rc1's
  `_pnr.v` only — rc2 (+292 instances), rc3fix (+1,504 ECO cells) and rc4 were never
  compared. No GLS on rc1-rc4 (last was rzG, 08-23, zero-delay).
- **Paper gap** — ECO cells are buffers and resizes; boundary scan is the weak spot.
- **Retire it:** LEC golden rc1 `gate_power.v` vs revised `rc4_pnr.v` (~1-2 h); GLS
  with the rc4 signoff SDF already at `$B/setupclose-20260829/sta_rc3setup/outputs/`.

### N7 — Hold checked at FF corners only

- rc4 hold views: FF/−40 °C (two IO libraries), FF/125 °C. TT hold +0.012 on rc4's
  parent (`$B/typ-rc3-20260828`). SS/125 °C hold never run on any lineage; SS/−40 °C
  reg2reg +0.007 on rc2. ~10-minute Tempus run on `db_rc4` retires it.

### What frequency to trust

- **Core:** 100 MHz is fine on typical parts (TT setup +2.264 ns). Budget ~95 MHz for
  worst-case slow hot parts. Hold does not improve at lower frequency.
- **D2D:** bring up at CLK = 50 MHz. Treat 100 MHz eth→compute as unproven.
- **Closed before rc4:** D2D TX word clocks now sourced from `user_hsclk` (SDC :34), no
  TA-1018; SPEFs are coupled (the "zero parasitics" note is superseded); TL_TX
  outputs timed (15/15 met).

---

## 6. Physical, power, foundry

### F1 — ERC never executed; PadShorts never run on rc4

- **CONFIRMED.** imec's rc4 Final Report (`…31Aug26_17u35/design/reports/Final_Report_*.rpt`,
  md5 line 57 = `6b0833c4…`) bails ERC at line 931: `No labels found in topcell`.
  The only PadShorts delivery (`ASIC/imec_results/PadShorts/`, 24 Aug) graded rzG,
  not rc4. rc4's own LVS lists 11 of 12 VDDIO/VSSIO pads as "missing connection"
  (abutment-bus black-box artefact, `lvs_run/*.lvs.rep:2029-2058`).
- **Mitigating:** on rzG all 12 VDDIO pads formed one short group (ring continuous),
  and the pad netlist/floorplan did not change 22-29 Aug.
- **Failure mode if real:** a gap in the VDDPST/VSSPST bus leaves IO cells unpowered
  (pads don't drive); a missing clamp path gives ESD damage at bonding/handling.
- **Retire it:** ask imec to run PadShorts / ERC on the merged rc4 GDS they already
  hold. At bring-up, diode-check every pin to VDDIO/VSSIO and measure IO supply
  current before applying core power.

### P1 — Static IR drop is not in timing; setup margin is 15 ps

- Measured on rc3fix, not re-run on rc4: worst effective collapse 1.336 % (~14 mV),
  97 % of it at M7 and above; all 10 core supply pads on top/bottom edges only.
  Signoff is SS/1.08 V with +15 ps. Two of the three rc4 resizes step drive *up*.
- **On silicon:** at 1.08 V, droop plus hot silicon can consume the 15 ps → setup
  misses at 100 MHz. **Run bring-up at nominal 1.2 V** and shmoo V against f.

### P2 — EM over limit on VSS pad feeds

- rc3fix: 49 elements over, worst J/Jmax 1.437, all M1/M2 stubs under the four VSS
  pads, none in the core (`ASIC/genus-innovus/rail/work/rc3fix-20260829/verdict.json`).
  Computed at default toggle rates, 125 °C. The SAIF study (`build/power-saif-20260827`)
  puts real workload at 0.10-0.19× → ~0.15-0.27 J/Jmax. **Probably a false red.**
  Lifetime risk only. Retire with Voltus + SAIF on `db_rc4` (~1 day).

### Other physical items

- **LVS is blind at the pad boundary and inside cells** — every pad extracts with
  "missing pin". Only `check_connectivity` (0 open) covers core-to-pad. Exercise
  every pin at bring-up.
- **Wire-bond P60 rules never run** — imec used `PITCH_80_STAGGER` again on rc4; the
  4 `CB.W` results are that wrong switch. Our 66×58 µm opening passes P60 on paper
  by 5 µm. Ask imec to re-run BND at `PITCH_60_STAGGER`.
- **Foundry residuals**, all identical across archives and inside TSMC/imec cells:
  ESD.21g/22g/23g, RM.WARN.2, PM.W.1 893, AP.S.4 46, IM.POLYIMIDE.1 82,
  IM.FLOAT.AP 91 (all 91 inside the logo box). Get written broker confirmation.

---

## 7. Provenance — rc4 cannot be rebuilt or diffed

- Evidence provenance block: tree DIRTY, all four stage manifests missing, no
  `ARMS.txt`. The rc1 base was built dirty at every stage. The recorded
  `toolkit_git_sha ffc345e` is the superproject's sha, not the toolkit's.
- ECO scripts under `build/setupclose-20260829/` are gitignored. The 80 MB `db_rc4`
  exists on this host's disk only; the artifact store holds the stream and evidence,
  not the database.
- `rc4-20260829/outputs/*_rc4_pnr.v` is byte-identical to `setupclose-20260829/*_rc3setup_pnr.v`
  (md5 `1899a304`) — the written netlist does not carry the three ECO resizes, though
  the GDS does (flat geometries 178,282,662 vs 178,282,660). Functionally irrelevant;
  it means the netlist file and the stream are not a matched pair.
- IM.FLOAT.AP reads 91 on rc1 and rc4 but 87 on rc2 — the logo artwork, read from the
  worktree, varied between candidates.
- **What it prevents:** proving an rc5 differs only by intended changes; a metal-only
  ECO or failure analysis if this disk is lost.
- **Do now:** archive `db_rc4`, `setupclose-20260829`, `gdsrun-20260826-rc1/pinned/`
  and `romlibs/` to the artifact store with sha256.

---

## 8. Checked and closed — NOT issues on rc4

Each was flagged at some point and verified against rc4's netlist, ROM stream or
imec report.

- **Boot ROM content** — the rom gate ran on the shipped `rc4_logo.gds`: eth and cc
  ROM bits match firmware 512/512, each macro placed once (`logs/rom_driver.log`).
- **TideLink ECC bypassed** — fixed; flist `:253` uses the local override and
  `llrx_io_ecc_corrupted` is driven.
- **Peer-write burst corruption (`cap_done_r`)** — fixed; `w_beat_consumed` in netlist.
- **XHB500 hazard-list / EWR wedge; cacheable-burst AW doubling** — fixed by the
  tie-down; zero `hazard` names in netlist.
- **N1 read-backstop suppression** — fixed (`tidelink_top.sv:1799-1822`).
- **"Every CPU store to 0x2F HardFaults"** — EWR guard removed at `4b625c4`.
- **TL-001 framing drop; AW/W/B self-latch; AUTO_ANCHOR deleting writes** — fixes are
  ancestors of `5e8bdb5a` / present in netlist.
- **TX output interface unconstrained / spurious TX word clocks** — fixed in rc1's SDC.
- **QSPI cache tag `GWEN` tied** — fixed `a4ae480` (08-07); netlist drives `GWEN` from
  logic. Docs 11, 16 and 61 are stale on this.
- **IDCODE impersonating Neterion** — fixed 08-19.
- **PVDD2POC 4→1** — netlist has 1 PVDD2POC; imec padring 0/0.
- **14 post-merge floating gates / PO.R.8** — imec reports PO.R.8 = 0 on rc4 bytes;
  macro pins 0 bare of 748; 0 open nets.
- **Stranded functional cells** — rc3fix has 0 functional, 18 FILL/DCAP.
- **LVS `.GLOBAL VSS` inversion** — rc4 LVS source has `.GLOBAL VDD VDDIO VSS VSSIO`.
- **Seal-ring CSR, density, fill keep-out, `_SL` bond pads, logo keep-out, antenna** —
  all 0 or identical on imec's rc4 run.
- **Cross-die read failures** — ssh artefact. **eth_ss "safe read" wedge, gpio-phy
  pin, MDIO noise** — FPGA-only artefacts.

---

## 9. Open decisions

1. **Eth D2D role** — fill `docs/bringup/D2D_PAIRING_DECISION.md` §2 (die_b is the
   zero-change choice). Confirm what the "2026-09-24 submission" in that file refers to.
2. **Bring-up oscillator frequency** — decides whether B2 is a risk at all.
3. **Ask imec** for ERC / PadShorts on rc4, BND at `PITCH_60_STAGGER`, and written
   acceptance of md5 `6b0833c4…`.
4. **Archive `db_rc4`** and the ECO inputs before anything else touches this host.
5. **Who writes the CPU1 image** (flash app, or the HOSTIO shim of §3.1 workaround 3)
   that sets `ROLE_CFG`, `NS_INCR` and a safe `CLK_DIV`.
6. **Bring-up board: pull-down on `QSPI_IO1`**, so a no-flash power-up parks in
   microseconds instead of a multi-second busy-bit poll (§3.1).
7. **Correct `ASIC_FIRST_SILICON_HOSTIO_PROCEDURE.md` §0.3 / HIO-106.** The RTL says a
   missing flash does not HardFault CPU1. A zero at `0x29000000` needs a timed
   re-read, not a "benign HardFault" diagnosis.
