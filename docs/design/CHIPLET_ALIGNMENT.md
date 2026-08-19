# Chiplet alignment — eth ↔ compute, and the cross-die interrupt/debug plane

**Purpose.** A single handover for bringing the NanoSoC **Ethernet** chiplet (this
repo, silicon-proven on KR260) and the NanoSoC **Compute** chiplet
(`~/SoCLabs/NanoSoC-Compute-Chiplet`, RTL-complete + synthesised, no board flow)
into a runnable pair — *plus* the cross-die interrupt and single-probe-debug plane,
which the pair bring-up docs don't yet cover.

> **This doc is a synthesis and an overlay, not the master gap list.** The
> authoritative, RTL-grounded gap analysis is
> **`~/SoCLabs/NanoSoC-Hetrogeneous-Chiplet-Testing/docs/BRINGUP_GAPS.md`**
> (G1–G17, per-gap owner + size). Read that first. This doc records the
> reconciliation, the deltas since it was written, and adds the interrupt/debug
> layer (G18/G19 below). Do not duplicate G1–G17 here — defer to it.

---

## 1. Reconciliation verdict

`BRINGUP_GAPS.md` (het repo, committed `cb72ddd` 2026-07-29 12:26, author `dam1n19`)
was independently re-verified against the two repos' RTL/YAML by two review passes on
2026-07-29. **Findings agree with G1–G17** — same critical path, same evidence, same
owners. Treat G1–G17 as load-bearing.

### Deltas since `BRINGUP_GAPS.md` was written (12:26)

| Gap | What changed | Effect |
|---|---|---|
| **G3** (TideLink pin skew) | This repo's tidelink pin moved `884c4a8` → **`809f038`** (`freeze-2026-07-22-63-g809f038`, batch-prep 2026-07-29 11:58, still `phy_marker V2`). | G3's ETH pin ref is 2 commits stale. **Substance unchanged** — compute's `3f3de09` is still a strict ancestor (~299 behind now) and still needs the roll-forward + rebuild. |
| **G11** (DEVICE_CLASS coin-flip) | This repo now straps **DEVICE_CLASS at build time**: top param (`src/rtl/nanosoc_eth_chiplet.sv:47`), threaded to the shim (`:804`), set per target — **die_a=1** (`kr260-eth-chiplet/tidelink_design.tcl:155`), **die_b=2** (`-flip/…:155`). | G11 is **half-closed on the eth side**. Distinct classes now win a deterministic root *between two eth dies*. Still open: (a) it's **build-time** (eth `TC_DEVICE_CLASS` is RO); (b) **compute still defaults `0x0001`** with no override. See §5 below — pin die_a via `ROLE_CFG` master-lock remains the belt-and-braces regardless. |

No other G1–G17 item has moved. In particular **G1** (no compute FPGA flow),
**G2** (no compute PS-backdoor), **G12** (data-plane wedge) are unchanged and remain
the hard stops.

---

## 2. The two chiplets at a glance

Complementary, non-overlapping maturity — this is the real shape of the problem:

| | ETH (this repo) | COMPUTE (`~/SoCLabs/NanoSoC-Compute-Chiplet`) |
|---|---|---|
| SoC wrapped | `nanosoc_multicore_soc` — dual Cortex-M0 (`network_core`+`chip_core`) | `nanosoc_compute_soc` — **heterogeneous**: Cortex-M0+ manager + **Cortex-M4** compute |
| TideLinks | **1** | **2** (per-link `_0`/`_1`) |
| Top RTL | complete, wired | complete, wired (docs say "not written" — **stale**, G17) |
| Synthesis | **none** (ASIC outputs empty) | **gate netlist** `nanosoc_compute_chiplet_gate.v` (2026-07-28, 0 violating paths) |
| KR260 bitstream | **2, on a bench, working** (link + data plane) | **none** (no `fpga/`, no target — G1) |
| PS backdoor | `eth_ss_0` AHB target → PS phys `0x4_0000_0000+A` | **absent** (G2) |
| DEVICE_CLASS | **build-time strap** 1/2 (see §1) | defaults `0x0001` (RW reg, can be set at runtime) |

**One has hardware and no synthesis; the other has synthesis and no hardware.** "Silicon"
in both repos means the KR260 FPGA — neither is fabricated ASIC.

---

## 3. Critical path (from `BRINGUP_GAPS.md` — reference only)

**G1 → G2 → G3 → G4 → G5.** Nothing is bench-testable on a compute board until these
five land; G12 blocks the *homogeneous* pair too and is inherited.

- **G2 PS backdoor** is upstream of everything — it's a `nanosoc_compute_soc`
  `sys_desc` change (new AHB target, re-exported through the chiplet top), and the
  FPGA BD (G1) cannot be wired without it. **First PR.**
- **G4 address map** — compute's D2D window is based at `0x40`/`0x60` (256 MB) vs eth's
  `0x2E` (32 MB), and `chiplet_d2d_decode.sv` is byte-identical but hard-wired to the
  eth map → compute's `0x4000_0100` **mis-decodes to the TX aperture** (a real defect,
  not just an offset). Rebase or parameterise the decoder, re-verify *with the decoder
  in path*.
- **G7 mailbox byte** (`0x2A` compute vs `0x23` eth) — small, but it **is the interrupt
  path** (§4). Encode per-direction CAM rules, not one constant.

See `BRINGUP_GAPS.md` for the full list, evidence, and sizes.

---

## 4. Interrupt & debug alignment overlay (NET-NEW — not in `BRINGUP_GAPS.md`)

`BRINGUP_GAPS.md` covers pair *bring-up*. The cross-die *interrupt* and *single-probe
debug* planes are additional alignment work, tracked here as G18/G19. Grounding docs in
this repo: [`CROSS_DIE_INTERRUPTS.md`](CROSS_DIE_INTERRUPTS.md),
[`CROSS_DIE_DEBUG_PLAN.md`](CROSS_DIE_DEBUG_PLAN.md),
[`CROSS_DIE_DEBUG_0C_GATE_SPEC.md`](CROSS_DIE_DEBUG_0C_GATE_SPEC.md).

### Cross-die interrupts — two tiers

**Near-term (silicon-proven): the IPC mailbox doorbell.** A far-die write to a mailbox
slot + `MSG_VALID` latches `irq_status` → NVIC. Source generation is **proven on eth
silicon** (`mbox_recv`). To reach the *compute* die's mailbox this is gated on **G7** —
eth→compute must rewrite the CAM byte to **`0x2A`**, not `0x23`. So G7 is not a nicety;
it is the near-term cross-die interrupt. Keep this path; it is the demo mechanism.

**Medium-term (the scalable plane): `ahb-chiplet-interrupt-controller` (IRQC).**
Your own IP at `~/SoCLabs/ahb-chiplet-interrupt-controller` (sim-only, lint-clean,
DC-closed 250 MHz, 110 cocotb + UVM). It is the right long-term routing layer — it
delivers what the mailbox fundamentally cannot: up to 64 tagged sources/die, **per-source
routing** (target type core/DMAC/debug + index + dest chiplet), **remote set *and clear***
over the bridge (ASSERT/DEASSERT), broadcast IPIs with receiver opt-out, and a
**dedicated 64-bit Wlink FC node `0xa3`** that bulk traffic can't starve. It is a
**parallel plane, not a drop-in** for the mailbox.

> **G18 — adopt the IRQC as the scalable cross-die interrupt plane (shared, medium-term).**
> The eth side is already half-wired: `tidechart_shim.sv` exposes the exact
> `tc_to_irqc_*`/`irqc_to_tc_*` ports (currently tied off in `nanosoc_eth_chiplet.sv`),
> `~/SoCLabs/tidechart` is on the required branch `add-subtree-and-irqc-axis`, and
> TideLink reserves `0xa3`. **Blockers/sequence:** (1) land `strip-generalbus-irq`
> (TideLink) + `add-subtree-and-irqc-axis` (TideChart); (2) the `0xa3` FC node is **not
> instantiated in either chiplet's Wlink** → build it, bring it up on FPGA in **loopback
> first** (it has never run on HW); (3) add a two-chiplet FC sim (doesn't exist); (4) fix
> the IRQC's stubbed diagnostic tie-offs + the 48-vs-64-bit spec/RTL doc bug + plan the
> B6/B7 latch-table → SRAM-backing (area: ~18.4k FF local_deliver, ~8.8k FF regs); (5)
> *then* un-tie the shim ports and wire `core_irq_o` onto **spare NVIC vectors**
> (`d2d_irq[15:0]` is already full). For a het pair the `0xa3` node must be added on
> **both** dies. **This rides the same TideChart cross-die fix as G11, so it sequences
> after G11/G12, not before.** Owner: shared (TideLink/TideChart branches) + both integrations.

### Single-probe cross-die debug (SWD over d2d) — G19

Goal: one SWD probe in deployment, debug both dies' cores over the bridge. Status on the
eth side: **`0b` sim-proven** (far-core `CPUID 0x410CC601` read over `d2d_m`);
**`0c` `REMOTE_DBG_EN` security gate spec'd** (default-closed, locally-set inbound
firewall — see `CROSS_DIE_DEBUG_0C_GATE_SPEC.md`); **host `dbg_gate`/`dbg_halt`/`dbg_resume`
modes ready** in `kr260_eth_xfer.py` (batch-prep). Caveat: the far-core PPB polling
crosses the flaky AXI FC nodes, so a dependable session needs **G12** (the FCSM fix).

> **G19 — mirror `0b`/`0c` on the compute die.** For single-probe debug of the compute
> chiplet, the compute SoC needs the same debug windows added to its `d2d` inbound target
> list (`0b`) behind the same `REMOTE_DBG_EN` gate (`0c`). This is symmetric to the eth
> work and depends on G2 (backdoor, to set the gate PS-side) and G4 (address map, for the
> debug-window CAM rules). Owner: compute integration, mirroring the eth specs.

---

## 5. Recommended unified sequencing

1. **Keep the homogeneous eth↔eth pair green** as the control (L1–L3, `[PROVEN]`) — it
   tells you whether any future het failure is bench or design.
2. **TideLink team, shared critical path:** the silicon FCSM wedge (**G12**), the het-sim
   FCSM-stall-at-1, *and* the IRQC's `strip-generalbus-irq` branch all sit with them.
   Bundle as one coherent request (`../history/TIDELINK_SILICON_FEEDBACK.md`).
3. **Compute die, in gap order:** **G2** backdoor (first PR, gates all) → **G3** roll
   TideLink to the V2 line → **G4** rebase/parameterise the D2D window + fix the
   `chiplet_d2d_decode` mis-decode → **G1** build `kr260-compute-chiplet{,-flip}` (specify
   the J21 ball map to **match eth die_b now**, before the XDC is written — free today,
   expensive later).
4. **Address-map conventions once (G4/G5/G7):** window base, TideLink APB base, and
   **per-direction CAM mailbox rules** (`0x2A`/`0x23`) — write them into the het repo's
   target registry (`host/hetsoc/targets.py`), not hard-coded scripts.
5. **DEVICE_CLASS / root election (G11):** give compute a distinct class (its
   `TC_DEVICE_CLASS` is RW — can be set at runtime, or add the eth-style build strap), and
   **pin die_a grandmaster via `ROLE_CFG` master-lock** as belt-and-braces (the link does
   not depend on TideChart).
6. **Interrupts:** mailbox doorbell near-term (needs G7's `0x2A` rule); **G18** IRQC
   medium-term, sequenced after G11/G12 and the two branches.
7. **Debug:** **G19** mirror `0b`/`0c` on compute after G2/G4.

---

## 6. Handover pointers (for the compute-chiplet agent)

- **Master gap list:** `~/SoCLabs/NanoSoC-Hetrogeneous-Chiplet-Testing/docs/BRINGUP_GAPS.md`
  (G1–G17). Also in that repo: `SIM_PLAN.md` (address maps §6, findings §8a),
  `BOARD_WIRING.md` (J21 map to match), `SAFETY.md` (wedge hazards H1/H3).
- **Het sim harness (exists, partially closes G13):**
  `~/SoCLabs/NanoSoC-Hetrogeneous-Chiplet-Testing/sim/het_pair/` — real eth + real compute
  in one VCS sim; elaborates (302 modules, 0 err), smoke passes, role negotiation resolves
  oppositely with zero compute-side pokes. **Open blocker F6:** Wlink FCSM stalls at state 1
  on both dies — suspect `tidelink_top` hard-coding `apb_debug_unlock_i`/`mask_hs_bypass_i`
  to `1'b1` (consistent with the G3 skew). Fixing this is the gate on the sim data plane.
- **Interrupt/debug specs (this repo):** `CROSS_DIE_INTERRUPTS.md`,
  `CROSS_DIE_DEBUG_PLAN.md`, `CROSS_DIE_DEBUG_0C_GATE_SPEC.md`, `../bringup/CROSS_DIE_TEST_BACKLOG.md`.
- **IRQC IP:** `~/SoCLabs/ahb-chiplet-interrupt-controller` (`docs/REGISTER_MAP.md`,
  `SPEC`, `USER_GUIDE`; `cocotb/cross_ip_irqc_tidechart/` is single-chiplet only).
- **Eth reference for the backdoor (G2 model):** `src/rtl/nanosoc_eth_chiplet.sv:60-70`
  (`eth_ss_0_*` target), landing at PS phys `0x4_0000_0000+A` (read the built `.hwh`, **not**
  the `tidelink_design.tcl:233` `0x8000_0000` claim — that's the board-wedging doc bug, G17).
- **Safety invariants:** never drive a chiplet board with the compute repo's bare-link
  `tl3x` scripts (they poke `0x8403`/`0xA400` → wedge, JTAG-POR-only recovery). All host
  access goes through the backdoor (`0x4_0000_0000+A`).
