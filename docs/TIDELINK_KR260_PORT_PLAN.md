# TideLink KR260 Two-Board Port Plan (nanosoc-ethernet-chiplet)

> **Status:** PLAN, not implementation (branch `feat/tidelink-chiplet-port`).
> Companion to the tidelink architecture doc
> `tidelink/docs/ETHERNET_CHIPLET_INTEGRATION.md`. This file says how *this*
> repo's integration maps onto a two-board KR260 FPGA build of the ethernet
> chiplet over TideLink, and what the ethernet path still needs.

## 0. What this repo already is (verified on disk, HEAD e809fbf)

`nanosoc_eth_chiplet.sv` is a **pure structural integration top** — it forks
nothing, it instantiates three blocks side by side:

- `u_soc` = `nanosoc_multicore_soc` (from the `nanosoc-multicore-system`
  submodule). **It already contains the ethernet subsystem** —
  `build_soc/rtl/nanosoc_multicore_soc.sv` instantiates `ethernet_ss_ahb_rmii`
  → `ethmac_subsystem_ahb` (OpenCores MAC + HA1588). The chiplet top re-exports
  the ethernet boundary 1:1: `rmii_*` (100–104), MDIO (106–109), `eth_irq`
  (476), `ha1588_servo_locked` (480).
- `u_d2d_decode` = `chiplet_d2d_decode` (in `src/rtl/`) — sub-decodes the SoC's
  `d2d_ahb_m` 32 MB window `0x2E00_0000..0x2FFF_FFFF` into TideLink's four AHB
  subordinates + two APB bridges, with a hard-ERROR default responder and a TX
  wedge gate keyed on `link_active_i`.
- TideLink (`tidelink/`, pinned `v2026.07.16-chiplet-verified`) and TideChart
  (`tidechart/`) submodules, plus `local_overrides/tidelink_top.sv` and the
  deskew/autoneg overrides.

The cross-die inbound path is already wired: `tidelink_top.ahb_mng` →
`d2d_ahb_s` (the SoC's **6th matrix initiator**) → the SoC AHB matrix. The PHC
grandmaster source is wired: `d2d_phc_*` = PHC servo source 0. `d2d_irq[15:0]`
splits [7:0]→CPU0, [15:8]→CPU1.

**So the ethernet-over-TideLink datapath, the MAC, HA1588, and the PHC servo
already exist structurally in this repo.** The port is about *building it for
KR260 FPGA* and *closing the loop in sim*, not about adding blocks.

## 1. Reusable-vs-ASIC-only split of `nanosoc_eth_chiplet.sv`

| Element | FPGA (KR260 two-board) | ASIC-only | Notes |
|---|---|---|---|
| `u_soc` (multicore + ethernet) | **reuse** | — | needs an FPGA build of the multicore SoC (BRAM for scratch/imem, MMCM clocks). Utilisation/timing on `xck26` is the open question. |
| `chiplet_d2d_decode` | **reuse as-is** | — | pure RTL, board-agnostic; already lint/sim-clean (`docs/LINT_FINDINGS.md`, `docs/G2_PAIR_SIM.md`). |
| `tidelink_top` + GPIO-PHY | **reuse** (V2, `TIDELINK_PHY_V2=1`) | shares RTL | FPGA uses the GPIO-PHY on J21 pads; KR260 needs `USE_IDELAY=0` (HDIO bank 44 can't host IDELAY) + `IOB FALSE` on `pad_rx`. See tidelink `docs/KR260_PORT.md`. |
| `local_overrides/*` (deskew/autoneg) | **reuse** | — | the content-anchored deskew is FPGA-flist; the ASIC flist needs it added before tapeout (known gap). |
| Pad ring / boundary (`docs/PIN_POLICY.md`, `PIN_MAP.md`, unbond pads, `POWER_DOMAINS.md`) | **not used** (FPGA drives real device I/O via XDC) | **ASIC-only** | the 23-pad budget, tie/open policy, power domains are tapeout concerns. |
| `tidechart_shim.sv` / TideChart | reuse if the demo wants congestion telemetry; **optional for M1** | shares RTL | co-sim smoke passed (W2b) but carries the dual-root election finding G1. |
| RMII pins at the boundary | **reuse for M2** (PMOD), tie-off for M1 | maps to ASIC bond pads | M1 leaves `rmii_rxd/crs_dv` tied, `rmii_txd/tx_en` unconnected. |

**ASIC-only, do not port to the FPGA target:** the pad-ring boundary
implementation, power-domain wiring, unbond-pad handling, and the SDC pad-ring
gates. Everything in the *logical* integration (SoC + decode + link + PHC + IRQ)
is FPGA-reusable.

## 2. How it maps onto a two-board KR260 build

**Two bitstreams, one per board** (mirrors the existing tidelink `kr260-pair-*`
straight-through ribbon convention):

- **die_a bitstream** = `nanosoc_eth_chiplet` with the TideLink role strap = 0
  (master), TX/RX balls per `fpga/targets/kr260-pair-nptp/kr260_tidelink.xdc`.
- **die_b bitstream** = same top with strap = 1 (flip) and TX/RX balls swapped
  (the `-flip` XDC). Ribbon is straight-through (BCM_n ↔ BCM_n); always pair a
  die_a image with a flip image or you short two drivers.

The difference from the *existing* bare tidelink `kr260-pair-*` targets: those
instantiate `tidelink_top` with `ahb_mng` terminating in
`tidelink_ahb_mng_bram.v` (a 4 KB scratch). The eth-chiplet target instantiates
`nanosoc_eth_chiplet` instead, so `ahb_mng` reaches the **SoC + ethernet
scratch**, and the PS (devmem) reaches the SoC's ethernet registers through the
peer/data windows.

Address consistency (see the tidelink arch doc §2): PS ctrl `0x8000_0000`, data
`0xA400_0000`, APB `0x8403_xxxx`; nanoSoC D2D window `0x2E00_0000` (tx/fifo/ptp/
tlapb/tcapb) + `0x2F00_0000` peer; far-die reach via the peer window into the
remote SoC's eth-scratch range.

## 3. What the ethernet-subsystem addition still needs (the gaps)

Even though the subsystem is instantiated, these must be closed for the KR260
two-board ethernet demo:

1. **FPGA build of the full multicore+ethernet SoC on `xck26`.** The tidelink
   `kr260-pair-*` targets have only ever built the *bare link*. The multicore SoC
   + ethernet + link is a much larger PL design; **timing closure and BRAM/LUT
   utilisation on `xck26` are unproven.** *Action:* a scoping synth of
   `nanosoc_eth_chiplet` for KR260 (W1 lane), before committing to M1.
2. **`ahb_mng`→SoC terminus in the FPGA target.** The chiplet top wires it, but
   the FPGA target TCL/BD must instantiate `nanosoc_eth_chiplet` and honour the
   `d2d_ahb_s` HREADY-loop discipline (`docs/D2D_HREADY_LOOP.md`) rather than the
   old BRAM loopback.
3. **`eth_irq` NVIC hookup — verify.** `eth_irq` reaches the chiplet boundary as
   an output. Confirm whether `nanosoc_multicore_soc` already lands the MAC
   `int_o` on `cpu_0_irq` internally, or whether a one-line NVIC connection is
   needed. (Boundary re-export ≠ interrupt delivery.)
4. **PHY provisioning for M1 (none) vs M2 (PMOD RMII).** For M1, tie
   `rmii_ref_clk/rmii_rxd/rmii_crs_dv` to a benign idle and leave `rmii_txd/
   rmii_tx_en` unconnected; put the MAC in internal loopback if HA1588 timestamps
   are wanted. For M2, add a PMOD LAN8720 adapter + `rmii_to_mii` bridge + XDC.
5. **PTP grandmaster role pinning (finding G1).** The dual-root election
   (`nanosoc_eth_chiplet.sv:357`, `link_active` precedes data-mode) must be
   resolved or the grandmaster pinned by strap. For the demo, pin die_a as
   grandmaster; do not rely on auto-election.
6. **Firmware.** The multicore build has `*_eth_ss_*` linker scripts and a
   `soc_eth_ping` sim; a two-board demo needs firmware that (a) stages a frame in
   eth_scratch_tx, (b) pushes it across the peer window into the far die's
   eth_scratch_rx, (c) drives the PTP Sync/Delay-Req exchange. This is new
   firmware on top of the existing PicoTCP stack.

## 4. Milestone mapping (to the tidelink arch doc)

- **M0 (sim smoke):** best executed in the **tidelink** repo's cocotb harness
  (extend `tidelink_top_pair_v2`) — no chiplet-repo change needed. Alternatively
  a `nanosoc_eth_chiplet` pair sim here (this repo already has `docs/G2_PAIR_SIM.md`
  / `docs/G2_SOC_PAIR_STATUS.md` for a SoC-pair TB — the natural home for a
  full-chiplet two-die sim).
- **M1 (KR260 no-PHY):** new tidelink FPGA target `kr260-eth-chiplet`
  instantiating this repo's `nanosoc_eth_chiplet`. This repo supplies the RTL;
  the target/XDC/TCL live in tidelink (W1 lane).
- **M2 (physical PHY):** PMOD RMII, both repos (XDC in tidelink, `rmii_to_mii`
  from the eth repo).
- **M3 (ASIC alignment):** fold the FPGA-proven attach + PHC servo back here;
  ensure the ASIC flist carries the deskew override and closes finding G1;
  re-run this repo's pad-ring / power-domain gates.

## 5. Constraints honoured

- No pushes to any remote (local branch/commits only).
- MAC upstream (`/research/AAA/ip_library/OpenCores-EthMAC`) is read-only,
  flist-reference only — never copied or modified.
- This repo's submodules (`tidelink`, `tidechart`, `nanosoc-multicore-system`)
  are not edited by this plan; only this `docs/` file is added.
- Pad ring / power domains / unbond pads are ASIC concerns and are out of scope
  for the FPGA two-board build.
