# D2D Link-Rate Control — Recommended Architecture

**Repo:** `nanosoc-ethernet-chiplet` (tidelink at `./tidelink`, pinned `b8f86b88`)
**Date:** 2026-08-18
**Status:** proposal for owner decision. Nothing below is landed.

---

## 1. RECOMMENDATION

Take the **`minimal` spine** — a rate register in TideLink's genuinely-undecoded fourth APB quadrant at SoC `0x2E03_6000`, write-gated on `!role_locked_o`, feeding `u_link_clk_div.ratio_i` through a sticky source mux that leaves the existing `link_clk_div_ratio_i` port authoritative until software first writes. It is the only one of the four proposals with **zero fatal flaws**, and the only one whose safety argument survived contact with the RTL. Onto that spine graft four things: **(a)** a *bounded, arm-once, pre-lock-only POR extension* that AND-gates **only** `u_chiplet_controller.poresetn`, which converts `minimal`'s one real weakness — the write-then-ROLE_CFG adoption race — from a procedural convention into an RTL interlock, without touching `axi_chiplet_controller.sv` at all and without creating the software-reachable PHY-POR that made `firmware` fatal; **(b)** from the **`firmware` adversarial verdict**, its own prescribed repair ("delete the quiesce OR-term, use the cold POR window that is already proven"), plus its concrete fixes — the ratio clamp, the 2FF+equality readback sync, the `_PRESENT` parameter defaulted off with select *and* mux arm both inside the generate, and the `_MAP_SPAN` widening; **(c)** from **`clean`**, the signoff-honesty mechanism (an RTL `MAX_RATIO` parameter so the reachable ratio set can be tied to the ratios STA has actually certified), the one-cycle unconditional-ack contract for the new quadrant, and the observation that a POR window re-zeroes the TX word counter — which is *why* we refuse a warm path; **(d)** from **`autoneg`**, only its negative result: do not negotiate. Its own verdict proves the negotiation window does not exist on this die (`SELF_ARM_TRAIN_EN(1'b1)` at `nanosoc_eth_chiplet.sv:760` makes role-lock latch one cycle after the request, never waiting for the mask handshake) and that master election is a coin flip on identically-strapped dies. Cross-die rate agreement stays a firmware convention, stated as such.

The brief's founding premise — *"TideLink has NO FREE APB APERTURE"* — is **false**, and all four independent surveys disproved it identically. The nibble census is true but describes only one of `tidelink_top`'s four top-level quadrants.

```
  EXTERNAL AGENT                         SoC / on-die                     TideLink
  ──────────────                         ───────────                      ────────

  SWD probe (4 pads)
        │
        ▼
  ┌───────────────┐   DPRESETn = sys_poresetn (survives warm reset)
  │  SWJ-DP  +    │   nanosoc_multicore_soc.sv:1454-1457
  │  AHB-AP       │
  └───────┬───────┘
          │ dap_ss_0_m  (widest master target list in the SoC)
          │             memory_map.txt:45  → includes "d2d"
  ┌───────┴──────────────┐
  │  OR: HOSTIO4         │  nanosoc_hostio_debug_ss (u_debug_0), 7 bonded pads,
  │      debug_m         │  its own AHB master, also reaches d2d
  ├──────────────────────┤
  │  OR: CPU0 / CPU1     │  (CPU0 held in reset at POR; CPU1 needs valid QSPI
  │                      │   boot table — neither is a dependable pre-link path)
  └───────┬──────────────┘
          │  AHB, sys_hclk == sys_fclk (PRMU: assign SYS_HCLK = SYS_FCLK)
          ▼
  ┌────────────────────────────────────────┐
  │ chiplet_d2d_decode                     │  a_tlapb = in_2e & (blk==4'h3)
  │  blk = haddr[19:16]                    │  ── NOT gated by link_active_i
  │  0x2E03_xxxx → hsel_tlapb              │     (only a_tx carries tx_open)
  └───────┬────────────────────────────────┘     ⇒ writable with the LINK DOWN
          │  + NEW: qualified ~haddr[15] (kills the 0x2E03_8000 alias)
          ▼
  ┌────────────────────────────────────────┐
  │ cmsdk_ahb_to_apb #(.ADDRWIDTH(15))     │  nanosoc_eth_chiplet.sv:682-687
  │ HADDR[14:0], PCLKEN=1'b1 @ sys_hclk    │  → tlapb_paddr[14:0] = 15'h6000
  └───────┬────────────────────────────────┘
          ▼
  ┌═══════════════════════════════════════════════════════════════════════════┐
  │ tidelink_top.sv                                                            │
  │                                                                            │
  │   apb_paddr[14:13]  00→Wlink   01→config regs   10→addr-xlat   11→FREE     │
  │                                                              ╲             │
  │                                              NEW: apb_sel_rate = 2'b11     │
  │                                                              │             │
  │                              ┌───────────────────────────────▼──────────┐  │
  │                              │ tidelink_link_rate_regs  (NEW, hclk)     │  │
  │                              │  0x6000 ID   RO  magic/version           │  │
  │                              │  0x6004 CTRL RW  [2:0] ratio             │  │
  │                              │                  accept ⇔ !role_locked_o │  │
  │                              │  0x6008 STAT RO  eff/busy/settled/…      │  │
  │                              │                                          │  │
  │                              │  ratio_req_r ──┐          por_hold_n_o ──┼──┐
  │                              │  src_sticky_r ─┤                         │  │
  │                              └────────────────┼─────────────────────────┘  │
  │                                               │                            │
  │   link_clk_div_ratio_i (port, kept) ──────────┤ 2:1 sticky mux             │
  │                                               ▼                            │
  │                              ┌──────────────────────────────┐              │
  │                              │ u_link_clk_div  .ratio_i     │              │
  │                              │   rst_n = poresetn (ungated) │              │
  │                              │   .ratio_o ──────────────────┼──► STAT      │
  │                              │   clk_out ──► link_hsclk_w   │  (2FF+filter)│
  │                              └──────────────┬───────────────┘              │
  │                                             │                             │
  │   u_chiplet_controller                      ▼                             │
  │     .user_hsclk (link_hsclk_w) ◄────────────┘                             │
  │     .poresetn   (poresetn & por_hold_n_o)  ◄───── NEW, the interlock ──────┘
  │                                                                            │
  └═══════════════════════════════════════════════════════════════════════════┘
              │
              ▼   WlinkGPIOPHY_v2.v:357  gpio_io_hsclk = user_hsclk (1:1, no PLL)
              ▼   WavD2DGpioTx.v:503-526 io_pad_clk = clock-gated copy
           D2D pad clock  ──►  peer die's pad_clk_rx ──► peer's calibrator
```

---

## 2. WHAT CHANGES IN TIDELINK

### 2.1 The aperture, and the proof it is free

`tidelink_top` splits its 15-bit APB window on `apb_paddr[14:13]` into four quadrants and decodes **three**:

```
tidelink_top.sv:847-854
    //   paddr[14:13] == 00 → Wlink chiplet controller (paddr[12:0])
    //   paddr[14:13] == 01 → TideLink config registers (paddr[11:0])
    //   paddr[14:13] == 10 → Address translator config (paddr[12:0])
    //   paddr[14:13] == 11 → Reserved
    wire apb_sel_wlink     = apb_psel && !apb_paddr[14] && !apb_paddr[13];
    wire apb_sel_tidelink  = apb_psel && !apb_paddr[14] &&  apb_paddr[13];
    wire apb_sel_addr_xlat = apb_psel &&  apb_paddr[14] && !apb_paddr[13];
```

Quadrant `2'b11` has no select wire and no slave. The response mux at `:872-880` falls through to `prdata='0 / pready=1'b1 / pslverr=1'b0` — a clean OKAY, not a stall. Five independent corroborations that it is unclaimed:

| Evidence | Where |
|---|---|
| RTL labels it `Reserved`, only three sel wires exist | `tidelink/src/rtl/tidelink_top.sv:850, :852-854` |
| Register map documents `0x6000-0x7FFF` as Reserved | `tidelink/docs/REGISTER_MAP.md:18` |
| Firmware address map defines banks 0/1/2, bank 3 absent | `nanosoc-multicore-system/firmware/include/nanosoc_multicore_addrmap.h:510-517` |
| No aliasing decode reaches it — the only bare `apb_paddr[12:0]` compare (`harden_swi_addr_match`) is qualified by `apb_sel_wlink`; the translator is fed `apb_sel_addr_xlat` | `tidelink_top.sv:2685, :2748` |
| Repo-wide grep for `0x2E036`/`0x2E037` in `.c/.h/.py/.tcl/.md` returns only the addrmap window comment | verified |

It is **already routed** — no wrapper change is needed to reach it. The bridge is `ADDRWIDTH(15)` on `d2d_ahb_m_haddr[14:0]` (`nanosoc_eth_chiplet.sv:682, :687`), so `0x2E03_6000` lands on `paddr[14:13]==2'b11` today.

And it is **portable**: the compute fork reserves the same quadrant verbatim (`NanoSoC-Compute-Chiplet/tidelink/src/rtl/tidelink_top.sv:812-819`, byte-identical comment and three sel wires), so this address choice does not fork the two register maps.

> **RETRACTED IN THE RTL, 2026-08-18 — done, do not re-open.** The wrong premise had a specific source that would have kept re-seeding itself: the `[OPEN]` block in the `u_tidelink` instantiation of `src/rtl/nanosoc_eth_chiplet.sv` used to state *"must live in THIS chiplet's APB space because TideLink has no free aperture (every `paddr[8:5]` nibble is claimed)"*, a few lines above the `3'd0` tie. The parenthetical was true; the *because* was not. That comment now carries the corrected fact instead — quadrant `11` free, the census scoped to quadrant `01` — with the `tidelink_top.sv` line evidence inline (`nanosoc_eth_chiplet.sv:792-837`, tie at `:838`). Nothing in the wrapper still asserts the false claim.

### 2.2 New file: `tidelink/src/rtl/tidelink_link_rate_regs.sv`

Single-clock (`hclk`), reset `hresetn`. ~180 lines. Register map, byte offsets within the bank:

| Offset | SoC address | Name | Access | Fields |
|---|---|---|---|---|
| `0x000` | `0x2E03_6000` | `LINK_RATE_ID` | RO | `[31:0]` magic+version, e.g. `32'h4C43_4401` |
| `0x004` | `0x2E03_6004` | `LINK_RATE_CTRL` | RW | `[2:0] ratio` (0=/1 … 4=/16); `[31:3]` RAZ/WI |
| `0x008` | `0x2E03_6008` | `LINK_RATE_STAT` | RO | `[2:0] ratio_eff`, `[3] busy`, `[4] settled`, `[5] write_locked_out`, `[6] settle_timeout` (sticky), `[7] src` (0=port, 1=reg), `[11:8] max_ratio`, `[31:12]` zero |

`LINK_RATE_ID` exists so host tooling can distinguish *"bank present"* from the pre-change *"reserved quadrant returns 0"* without probing behaviour. That matters because several PS tools must run against both submodule pins during the migration.

**Decode discipline.** The bank decodes `paddr[12:4] == 9'h0` and `paddr[3:2]` for the word. Everything else in the 8 KB: `pready=1'b1`, `prdata='0`, and **`pslverr=1'b1` on write**. This deliberately breaks with the config quadrant's precedent, where `APB_ADDR_W=12` and a `paddr[8:5]`/`paddr[4:2]` decode alias the whole 512-byte map 16× across `0x2E03_2000-0x2E03_3FFF` (`tidelink_top.sv:45, :981`; `docs/STATUS_REGISTERS.md:260-262`). A clock knob should not be reachable by 2047 wrong addresses. `[from: minimal fixable flaw 8, adopted rather than declined]`

**Ack contract.** `pready` is a hard `1'b1`, unconditional, in every state; FSM progress is reported *only* through `STAT.busy`. This is load-bearing: `tidelink_top`'s bounded-stall watchdog is `wire ext_txn = apb_sel_tidelink && apb_penable` (`:911`) with `EXT_STALL_LIMIT` at `:962-978` — it covers **quadrant 1 only**. Quadrant 3 has no PS-hang protection, and the Zynq M_AXI_GP has no bus timeout. `[from: clean fixable flaw 1]`

**Clamp.** `ratio_req_r <= (pwdata[2:0] > MAX_RATIO) ? MAX_RATIO : pwdata[2:0]`. The divider already clamps `>4 → 4` internally (`tidelink_link_clk_div.sv:104-106`), but clamping *before* the register means the readback compare can never chase an unreachable target. `firmware`'s fatal flaw — an FSM waiting forever for `ratio_o == 7` — dies here. `[from: firmware adversarial verdict, fixable flaw 1]`

### 2.3 Changes to `tidelink/src/rtl/tidelink_top.sv`

| Line (current) | Change |
|---|---|
| parameter block | `parameter LINK_RATE_REGS_PRESENT = 1'b0;` and `parameter [2:0] LINK_RATE_MAX_RATIO = 3'd4;` and `parameter [11:0] LINK_RATE_SETTLE_MAX = 12'd2048;` |
| above `:852` | declare `wire [2:0] link_ratio_mux_w; wire link_rate_por_hold_n_w; wire [SYS_DATA_W-1:0] rate_prdata_w; wire rate_pready_w, rate_pslverr_w;` — **above the decode site**, because `tidelink_top` is compiled under a leaked `` `default_nettype none `` and an explicit later declaration of an earlier-referenced net is a hard error, not a warning (the file records this constraint itself at `:1762`) `[from: minimal fixable flaw 5]` |
| `:852-854` | add `wire apb_sel_rate = apb_psel && apb_paddr[14] && apb_paddr[13];` — **inside** the same `generate` as the instance |
| `:872-880` | add the fourth mux arm, also inside the generate; the `else` arm keeps its current `'0 / 1'b1 / 1'b0` for `PRESENT=0` |
| `:2827` | `.ratio_i (link_ratio_mux_w)` |
| `:2831` | `.ratio_o (link_ratio_eff_w)` — currently `/* unconnected — readback surfaced by the integration */` |
| `:2879` | `.poresetn (poresetn & link_rate_por_hold_n_w)` — **the interlock; §4** |
| new, near `:2817` | `generate if (LINK_RATE_REGS_PRESENT) … tidelink_link_rate_regs u_link_rate_regs (…) … else assign link_ratio_mux_w = link_clk_div_ratio_i; assign link_rate_por_hold_n_w = 1'b1; …` |

**No new top-level port.** `link_clk_div_ratio_i` (`:364`) stays and stays authoritative until the first accepted register write, so the port-census signoff stage is untouched and the existing 11-test `/1../16` pair suite keeps passing unmodified.

**The select and the mux arm must both be inside the generate.** This is not style. `TXGEN_PRESENT(1'b0)` on this die produces exactly the defect to avoid: `txgen_reg_sel` is computed *unconditionally* at `:1014` and still wins the response mux at `:1404-1414`, while the generate arm at `:1094-1112` ties `txgen_prdata='0` — so nibble E (`0x2E03_21C0-0x21DF`) is 32 bytes of live decode on silicon that accepts writes, reads zero, and drives nothing. Reproduce that here and quadrant 3 becomes 8 KB that `pslverr`s on every write in twenty existing testbenches. `[from: firmware fixable flaw 7 / minimal's survey]`

**`LINK_RATE_REGS_PRESENT` defaults `1'b0`** so every existing instantiation — ~20 cocotb `tb_top`s and both FPGA IP wrappers — is byte-behaviour-identical. Only the eth wrapper opts in.

### 2.4 The one change outside tidelink that belongs in this section

`src/rtl/chiplet_d2d_decode.sv:135` — qualify the tidelink APB block on `~haddr[15]`:

```verilog
wire a_tlapb = in_2e & (blk == 4'h3) & ~haddr[15];
```

The bridge takes only `d2d_ahb_m_haddr[14:0]`, so `haddr[15]` is dropped and `0x2E03_8000-0x2E03_FFFF` currently mirrors `0x2E03_0000-0x2E03_7FFF`. For the three existing banks a stray write there lands on an obs register. For a clock knob it is a rate change. Adding the qualifier routes the upper 32 KB to the existing default responder's clean two-cycle AHB ERROR. This is a strict improvement for all four banks, is landable on its own with no submodule dependency, and is step 1 of the migration. `[from: firmware fixable flaw 5]`

---

## 3. HOW THE SOC DRIVES IT

Every hop below was verified in RTL, not inferred.

| # | Hop | Evidence |
|---|---|---|
| 1 | **SWD pads → SWJ-DP.** `DPRESETn` is `sys_poresetn` while the AHB-APs run on `sys_hclk`/`sys_hresetn` — deliberately split so an SWD session survives a `sysresetreq`. | `nanosoc_multicore_soc.sv:1454-1457`; rationale `nanosoc_swj_dap_ss.v:43-49` |
| 2 | **DAP → AHB (`dap_ss_0_m`).** Widest master target list in the SoC, wider than either CPU; includes the `d2d` window `0x2E00_0000-0x2FFF_FFFF`. Nothing depends on CPU state. | `build_soc/reports/nanosoc_multicore_soc_memory_map.txt:45, :31` |
| 3 | **Reset/clock availability.** `sys_hresetn` comes from the PRMU off the `nrst` pad and `SYS_FCLK`; `sys_sysresetreq` is tied `1'b0` at the boundary; `assign SYS_HCLK = SYS_FCLK` — no gating, no divider. The whole path is live as soon as `nrst` deasserts, before any CPU fetches. | `slcorem0p_prmu.v:93, :135-155`; `sys_desc/chip_boundary/nanosoc_eth_chiplet.yaml:202` |
| 4 | **`chiplet_d2d_decode` → `hsel_tlapb`.** `a_tlapb = in_2e & (blk == 4'h3)` — **ungated by `link_active_i`**, unlike `a_tx` which carries `tx_open`. Writable with the D2D link down. | `src/rtl/chiplet_d2d_decode.sv:130-146` |
| 5 | **AHB→APB bridge.** `cmsdk_ahb_to_apb #(.ADDRWIDTH(15))`, `HADDR[14:0]`, `PCLKEN=1'b1`, `HCLK=sys_hclk`. `0x2E03_6000 → tlapb_paddr = 15'h6000`. | `src/rtl/nanosoc_eth_chiplet.sv:682-697` |
| 6 | **Quadrant select.** `apb_paddr[14:13]==2'b11 → apb_sel_rate`. | new, §2.3 |
| 7 | **Register → mux → divider.** `ratio_req_r → link_ratio_mux_w → u_link_clk_div.ratio_i`. | `tidelink_top.sv:2817-2831` |
| 8 | **Divider → PHY.** `clk_out → link_hsclk_w → u_chiplet_controller.user_hsclk`, which inside the controller has exactly **one** consumer, the PHY at `:6524`. The interlock's clock-stop therefore cannot disturb any non-PHY logic. | `tidelink_top.sv:2815, :2877`; `axi_chiplet_controller.sv:6524` |

**With CPUs halted and the link down: fully reachable.** Hops 1–5 are all in the free-running `sys_hclk` domain off the `nrst` pad, and hop 4 is explicitly not link-gated.

**Second CPU-independent master:** HOSTIO4. Seven bonded pads → `nanosoc_hostio_debug_ss` (`u_debug_0`), its own AHB master on `SYS_HCLK`/`SYS_HRESETn`, also reaching `d2d` (`nanosoc_multicore_soc.sv:1545-1548`; `memory_map.txt:46`). Not in the brief; worth knowing it exists as a fallback.

**Why firmware is *not* the path.** CPU0 is held in hardware reset at POR, gated by a bit CPU1 owns (`nanosoc_multicore_soc.sv:1387-1388`). CPU1's stage-0 ROM is mask-programmed into a compiled TSMC ROM macro (`ASIC/rom_build.mk:19-20`), touches nothing in the `0x2E` window (grep for `0x2E`/`d2d`/`tidelink` across both stage-0 sources: zero hits), and `halt()`s in a `wfi` loop if the external QSPI boot table fails CRC. Changing what runs at reset is a mask change. Firmware is a *convenience* path for a booted system, never the bring-up path.

**On KR260:** the same registers, reached PS-side over the eth_ss_0 backdoor at `0x4_2E03_6000`. This requires widening `_MAP_SPAN` from `0x4000` to `0x8000` in `tidelink/pynq_host/scripts/kr260_eth_bringup.py:130` — `0x6000` is currently outside the mapped span and a rate write would fault in Python before reaching the bus. Ten-plus host tools inherit that `Backdoor` class and all get the fix. `[from: minimal fixable flaw 4]`

---

## 4. SEQUENCING — AND WHAT ENFORCES IT

### 4.1 The correction that reframes the whole problem

The brief says *"changing the rate invalidates the phase offset the calibrator solved for"* and implies the local die must retrain. **The local calibrator is clocked by the PEER, not by the local divider.** `u_calibrator.clk = phy_link_rx_rx_link_clk_w` ← `w_lnk_clk = ~count[3]` ← `io_pad_clk_rx` ← the peer's forwarded clock (`axi_chiplet_controller.sv:6187`; `WavD2DGpio_v2.v:2036`; `WavD2DGpioRx_v2.v:548, :681-683`). The local divider reaches only `user_hsclk → gpiotx → {io_pad_clk out, io_link_tx_tx_link_clk}`.

**The die that must re-calibrate after you change a ratio is the other one.** The brief's conclusion survives; its attribution does not. This is the single most consequential fact in the design, and it is why a cold, both-dies POR is not merely convenient but *correct*.

### 4.2 The window, and why it is the only one

`wlink_por_reset = ~poresetn | ~role_locked` (`axi_chiplet_controller.sv:3154`). In that window the forwarded pad clock is **gated off**, not idle: `clk_en_qual` is async-reset by `io_reset` and drives `WavClockGate.io_enable` whose output *is* `io_pad_clk` (`WavD2DGpioTx.v:503-526`). Nothing is emitted on the clock pad. A ratio change there cannot put a runt or a frequency step on the wire even if the divider's interlock were absent.

`role_lock_reg` is W1S with POR-only clear (`:644`, `:759`), and `SYS_PORESETn` comes from a `cm0p_rst_sync` with `.RSTREQ(1'b0)` while `SYS_HRESETn` takes `SYS_HRESETREQ` (`slcorem0p_rstctrl.v:78-94`). **A CPU/DAP AIRCR soft reset cannot drop role_lock and cannot reopen the window.** One window per chip-level reset, entered from the `nrst` pad.

We deliberately **do not** offer the warm `swi_swreset` route, and the reasons are measured, not aesthetic:

1. It is the exact reset node that a Tier-2 hardening shim exists to make software-unreachable. `tidelink_top.sv:2720-2760` forces `pwdata[3]=0` on every write to `0x208` because *"if SW pulses swreset while an AHB-sub transaction is in flight … axi2wl resets mid-burst, BVALID never returns … the whole PL slave set wedges until USB power-cycle."* `HARDEN_SWI_ENABLE` defaults `1'b1` and the eth wrapper does not override it.
2. `swi_swreset` does not re-zero the gpiotx 4-bit word counter — that is reset by `io_por_reset` only. Word-phase re-establishment across a warm rate change is unproven, and `WavD2DGpioRx_v2.v:218-222` records that the free-running mod-16 count is the root cause of the *"anti-correlated lock-count lottery the HW saw 12 deploys in a row."* A POR window re-zeroes it. `[from: clean]`
3. The documented recovery from a desynchronised FCSM is the `0x208` swreset bootstrap — which that same shim masks to a no-op. There is no software path back. `[from: firmware adversarial verdict, fatal flaw 3]`

### 4.3 The RTL interlock — what makes this structural rather than procedural

`minimal`'s one real gap: gating the write on `!role_locked_o` orders the two *writes*, but nothing couples role-lock to ratio *adoption*. From an APB write, `ratio_i` must clear a 2-FF sync plus a two-consecutive-samples-equal filter (3 `clk_in` cycles, `tidelink_link_clk_div.sv:90-102`) and then the bypass↔divided interlock — 2 negedges of `clk_in` plus 2 negedges of `clkdiv_r`, so ~32 `clk_in` cycles at /16, during which `clk_out` is **dead by construction** (both enables low, `:159-190`). Write the rate and then `ROLE_CFG` within ~350 ns and the PHY leaves POR with a stopped reference or at the old rate.

**Fix — the settle-gated POR extension.** Inside `tidelink_link_rate_regs`, `hclk` domain:

```
accept = psel & penable & pwrite & sel_ctrl & ~role_locked_i

on accept:   ratio_req_r  <= clamp(pwdata[2:0], MAX_RATIO)
             src_r        <= 1'b1              // sticky: register wins from here
             hold_r       <= 1'b1
             hold_ctr_r   <= LINK_RATE_SETTLE_MAX     // 12'd2048 hclk default
             tail_ctr_r   <= 6'd63

// ratio_eff_r = 2FF sync + equality filter on u_link_clk_div.ratio_o
while hold_r:
             hold_ctr_r <= hold_ctr_r - 1
             tail_ctr_r <= (ratio_eff_r == ratio_req_r) ? tail_ctr_r - 1 : 6'd63
             if (tail_ctr_r == 0)  hold_r <= 1'b0                      // settled
             if (hold_ctr_r == 0)  begin hold_r <= 1'b0;               // fail-safe
                                         settle_timeout_r <= 1'b1; end // sticky

assign por_hold_n_o = ~hold_r;      // ANDed into u_chiplet_controller.poresetn ONLY
```

Four properties, each of which is why this is safe where `firmware`'s and `clean`'s quiesce mechanisms were not:

- **It only ever *extends* a POR already in progress.** It arms only when `role_locked_o == 0` (the same term that gates the write). It can never assert a *new* PHY POR on a live link — the failure the controller calls *"a hard, bilateral, unrecoverable dead link"* (`axi_chiplet_controller.sv:809-815`).
- **Expiry is unconditional and bounded.** No compare can hang it, unlike `firmware`'s `S_CONFIRM`. The clamp makes the compare satisfiable anyway; the counter makes it irrelevant.
- **It touches exactly one line of `axi_chiplet_controller.sv`: none.** The gate is on the *instantiation* in `tidelink_top.sv:2879`. `poresetn` has exactly three consumers in `tidelink_top` (`:2826` divider, `:2879` controller, `:3115` `idelay_rst`, unused on ASIC) — the divider keeps ungated `poresetn` so its own ratio latch and free-running counter are unaffected.
- **The readback CDC is real.** `ratio_o` is combinational from `ratio_r` in the `clk_in` domain. On the eth die that is degenerate (`user_ref_clk` aliased to `sys_fclk = sys_hclk`). On KR260 it is not — `user_ref_clk` is `clk_out1/8` while `hclk` is undivided — so the 2FF+equality filter is mandatory, mirroring what the divider already does on the forward path. `[from: firmware fixable flaw 3]`

**What this buys:** the PHY provably cannot leave POR at a stale or mid-handover rate. That is the guarantee `minimal` claimed procedurally, obtained structurally, at the cost of one AND gate and ~20 flops.

### 4.4 The procedure

Per rate change, **both dies**:

| Step | Action | Enforced by |
|---|---|---|
| 0 | Assert then deassert the `sys_sysresetn` pad on both dies. | The only source of `SYS_PORESETn` (`slcorem0p_rstctrl.v:78-86`) |
| 1 | Write `LINK_RATE_CTRL` ← ratio, at `0x2E03_6000+4`, on **both** dies. | Accepted only while `!role_locked_o` — **RTL** |
| 2 | *(none — the hardware holds)* | `por_hold_n_o` holds the controller in POR until `ratio_eff == ratio_req` + 63 hclk, or 2048 hclk — **RTL** |
| 3 | *(optional)* poll `LINK_RATE_STAT`: `busy==0`, `settled==1`, `settle_timeout==0`. | Diagnostic only; step 2 already enforced it |
| 4 | `ROLE_CFG 0x2E03_2080` ← `0x02` master / `0x03` slave. | Latches role_lock, releases `wlink_por_reset`, ungates the pad clock **at the new rate**, and raises `role_locked` → the calibrator's `role_locked_rise_eff` fires with `calibrated_once_q` clear |
| 5 | `SWI_TRAINING_MODE 0x2E03_2100` ← 1 | silicon-proven recipe, unchanged |
| 6 | Poll `WINSCAN_STAT 0x2E03_21E4` bit[6] (`in_hold`) — **not** `cal_done` | `S_HOLD → S_VALIDATE` requires `!swi_training_mode_r` (`calibrator_v2.sv:1544-1545`); polling `cal_done` is a self-deadlock enforced in RTL |
| 7 | `SWI_TRAINING_MODE` ← 0 on both | recipe |
| 8 | LL bootstrap `0x2E03_0208` ← `0x00027F08`, `0x00027F00`, `0x00027F07` | recipe |
| 9 | Poll `SWI_LANE_STATUS 0x2E03_2108` for `FCSM == 4` (LINK_IDLE) | recipe |

Steps 4–9 are `tidelink/pynq_host/scripts/kr260_eth_bringup.py:264-332` **verbatim**. This design adds steps 0–3 in front and changes nothing downstream.

**Re-calibration is guaranteed by existing hardware, not by anything new.** Both dies cold-POR ⇒ `calibrated_once_q` is cleared (its only clear is `rst = ~poresetn`, `calibrator_v2.sv:857-861`) ⇒ `role_locked_rise_eff` is ungated ⇒ the role_lock rise at step 4 triggers a full calibration at the final UI on both dies. No `recal_arm_i` port, no `SWI_FORCE_RECAL` pulse, no new trigger term. `clean`'s fatal flaw was inventing a trigger that does not exist; this design uses the one that does.

**Cross-die rate agreement is a firmware convention, and we say so.** `autoneg` tried to make it a hardware property and the attempt failed on measured facts: `SELF_ARM_TRAIN_EN(1'b1)` collapses the negotiation window, and `role_strap_i` / `nego_priority_i` are tied identically on every eth die (`chip_boundary yaml:231, :242`) so `backoff_delay` is identical to the cycle and master election is a race — already observed not to converge (TideChart dual-root). The mitigation here is **detection, not negotiation**: the bring-up script reads `LINK_RATE_STAT.ratio_eff` on both dies at step 3 and refuses to proceed to step 4 on a mismatch. That is a script-level check, and it is honest about being one.

---

## 5. WHAT THIS DOES NOT SOLVE

**5.1 The "zero netlist delta" claim is false — and backwards.** Today `link_clk_div_ratio_i` is a hard `3'd0` and `RATIO_RESET` is `3'd0`, so every flop in the divider is a sequential constant with matching reset value. Genus folds the whole module to `assign clk_out = clk_in`. `ungroup_ok=false` (`protect_link_clk_div.tcl:30-45`) preserves the *hierarchy* but not the *contents*, and `set_dont_touch` only lands at `post_synth`, after `syn_opt` — the script says so itself (*"THAT SEAM DOES NOT EXIST"*). **This change is what makes the divider physically exist for the first time** (~15 flops, a real clock mux, a free-running counter). Two consequences: (a) it *rescues* `tidelink_constraints.sdc:150-164` from a likely hard `error` — with the flops folded away, `get_cells` binds (hierarchy preserved) while `get_pins .../div_en_r*/Q` returns empty, which is exactly the bind-or-die trip; (b) it creates a new registered clock net `clkdiv_r` that clocks `div_en_meta_r`/`div_en_r` on its *negedge* and has **no `create_generated_clock` anywhere**. `set_case_analysis` stops propagation *through* those flops; it does not give their clock pin a waveform. They land in the untimed-flop population the same file records as having hidden 16,653 flops. **A `create_generated_clock` on `clkdiv_r` is a required part of this change, not an optional follow-on.**

**5.2 The ASIC SDC signs off /1 only — and today signs off nothing.** `grep -c '^module tidelink_link_clk_div' ASIC/eth-chiplet/build/default/outputs/nanosoc_eth_chiplet_pads_gate.v` returns **0** on a netlist dated 2026-08-13; the divider reached the superproject 2026-08-18. The guard has never taken its non-skip branch and `protect_link_clk_div.tcl` has never bound a cell. Both are written and unexercised. The `/1` claim is design intent, not a measurement.

Worse in one direction: today `.link_clk_div_ratio_i (3'd0)` makes `/1` a *structural* property of the netlist and the `set_case_analysis` merely restates a constant. After this change the ratio comes from a register, so **`set_case_analysis 0 div_en_r*/Q` becomes a claim software can falsify by one APB write.** Two mitigations, neither complete:

- `LINK_RATE_MAX_RATIO` (RTL, clamped in the register block) lets the reachable ratio set be tied to the ratios STA has certified — set it `3'd0` and the register exists but the ratio is pinned `/1` structurally again. `[from: clean fixable flaw 4]`
- `RATIO_RESET = /1` on `poresetn` means the signed-off configuration is *always* the power-on configuration and is restored by every chip POR. Any other ratio is a deliberately-entered, host-selected, unsigned-off mode.

Propose a CI gate (`ci/signoff.yaml`) asserting that the wrapper's `LINK_RATE_MAX_RATIO` matches the set of ratios the SDC has constraint modes for. That does not make divided modes signed off; it makes the gap *impossible to forget*.

**5.3 The 12-clock hard assertion breaks at any non-unity ratio.** `ASIC/genus-innovus/inputs/constraints.sdc:384-393` merges the 8 D2D TX word clocks + `D2D_TX_CLK_0` into `_sys_grp` with `$EXTCLK` and 2 QSPI, and `error`s if the count is not 12. That merge ([C2] Option A) is only valid because the TX clocks are 1:1 with `EXTCLK`. At `/N` they are not, and the merged group is wrong. **Signing off a divided ratio requires a second `constraint_mode`** — the eth MMMC declares exactly one today, carrying five analysis views (`nanosoc_eth_chiplet_pads.mmmc:233-243`), and the toolkit template states a second mode *"means a second SDC set and doubles the view count."* It must also survive `write_sdc`, because the constraint mode points at the SDC synthesis *wrote*, not the authored input.

**5.4 The compute die is on a divergent pin and cannot be fixed from here.** Its tidelink is `74c6777`, has **no divider**, and the two checkouts have **disjoint object stores** — neither can resolve the other's commit; 2431 lines of diff across `src/rtl`. Adoption is a merge project, not a submodule bump, and would cost **two** divider instances, two ratio sources and two register homes (compute has two links). Compute's `user_ref_clk_0/1` are also aliased onto `soc_sys_fclk` in its pad wrapper, so it has the same welding problem. Its live SDC declares D2D RX at **4 ns / 250 MHz** per link — optimistic by 2.5× against eth's present 100 MHz and by up to 40× at /16 — and its `[C2]` boundary is still cut `-asynchronous`, hiding 3,482 flops. **Slowing eth's TX is setup-conservative for compute and therefore unilateral in the safe direction, but compute's constraint set is then wrong by the ratio and nothing re-derives.**

**5.5 `TX_STALL_TIMEOUT_LOG2` does not scale — and it is not alone.** Four `hclk`-domain timers do not move with the divider:

| Timer | Value | Where |
|---|---|---|
| `TX_STALL_TIMEOUT_LOG2` | 16 (~655 µs @100 MHz) | `tidelink_fc_adapter.sv:44, :316` — not overridden at instantiation |
| `SUB_STALL_TIMEOUT_LOG2` | 16 | `tidelink_top.sv:1517` |
| `SUB_OUTSTANDING_TIMEOUT_LOG2` | 16 | `tidelink_top.sv:1526` |
| `EXT_STALL_LIMIT` | 11'd1024 | `tidelink_top.sv:962` |

What they wait on *is* link-paced — credit returns gated by the peer, XHB500 cross-link AXI round trips — so at `/N` the fixed budget effectively tightens by the ratio. The FC state machines themselves are on `io_tx_clk`/`io_rx_clk` and **do** self-scale; the non-scaling timers are all in TideLink's own AHB/APB wrappers. `tidelink_fc_adapter.sv:44` is **byte-identical on compute**, so the exposure lands on both dies and compute's copy is unreachable from this repo. **Any ratio ceiling must be documented as a cross-die ceiling, not an eth-local note.** This design deliberately does **not** re-budget those timers: they sit in the N1 / TL-037 / TL-042 backstop family and belong in a separate change with its own hazard pass. `[from: firmware fixable flaw 6, adopted as a scope exclusion]`

**5.6 Evidence for divided modes is simulation-only.** The 11-test `cocotb/tidelink_top_pair` bring-up suite passes at /1 /2 /4 /8 /16 (100 MHz → 6.25 MHz). That is a **digital go/no-go**, not an eye or BER measurement. The divider's own unit bench proves no runt on live ratio changes but asserts nothing about the clock-stop window, nothing about the PHY, and nothing about the FC/backstop machinery surviving one. KR260 cannot validate a divided ASIC ratio by analogy: the FPGA link already runs at 3.125 MHz (an FPGA-side `/8` between `clk_wiz clk_out1` and `user_ref_clk`), 1/32 of the ASIC rate — and stacking an RTL ratio underneath silently falsifies two `-divide_by 8` declarations in `kr260_eth_chiplet_tidelink_timing.xdc:178-180`.

**5.7 Also not solved:** live mid-traffic rate change (explicitly not claimed, and it intersects N1/TL-042); asymmetric-rate detection in hardware (`tidelink_clkfreq_check` is in no ASIC flist, its reference port is the link-TX clock not `hclk`, it reports edge counts not periods, its `WINDOW_BITS=16` vs `CNT_W=20` saturates at exactly the 16× asymmetry in question, and its `link_up` arming input is circular for a knob that must run with the link down); DFT (no scan inserted, `DFT 0`, `scan_mode` tied `1'b0` at the boundary — the divider's `/1` scan bypass is unreachable on this silicon, so a rate register has no ATPG implication and no pad-level escape hatch either); power intent (single always-on `PD_TOP`, no domain boundary to cross — though note the shipped UPF names the wrong design top, `set_design_top nanosoc_chip_pads`).

---

## 6. MIGRATION PATH

Each step is independently landable and leaves the repo **clonable and lint-clean**.

| # | Repo | Change | Why it is standalone |
|---|---|---|---|
| **1** | superproject | `chiplet_d2d_decode.sv`: qualify `a_tlapb` with `~haddr[15]`. Kill the 32 KB alias. | No submodule dependency. Legal addresses behave identically; illegal ones now take the existing clean AHB ERROR. |
| **2** | superproject | `kr260_eth_bringup.py:130`: `_MAP_SPAN` `0x4000 → 0x8000`. Ten-plus host tools inherit it. | Pure host tooling. Widening a map cannot break a narrower access. |
| **3** | **tidelink** | Add `tidelink_link_rate_regs.sv`; wire it into `tidelink_top.sv` with `LINK_RATE_REGS_PRESENT` default **`1'b0`**; add to flists; document bank 3 in `REGISTER_MAP.md`. **Push the branch and verify with `git ls-remote`.** | At `PRESENT=0` every existing instantiation is byte-behaviour-identical. Superproject pin unchanged ⇒ still clonable. Re-run the 11-test suite green. |
| **4** | **tidelink** | New cocotb test in `tidelink_top_pair` at `PRESENT=1`: register-driven ratio change at /1 /2 /4 /8 /16; assert the POR extension holds role_lock across the settle, that `ratio_eff` converges, that `settle_timeout` stays clear, and that an out-of-range write clamps. The bench already has a full 15-bit APB master on **both** dies (`tb_top.sv:322-323, :331-332, :533-534, :757-758`), so this needs no new infrastructure. Push. | Test-only. Closes `minimal`'s real weakness: without it, the green `/1../16` evidence covers a port that silicon cannot drive. `[from: minimal fixable flaw 7]` |
| **5** | superproject, **ONE commit** | Bump the tidelink pin **and** add `.LINK_RATE_REGS_PRESENT(1'b1)` to `nanosoc_eth_chiplet.sv:760` **and** correct the wrong comment at `:794-796` **and** add bank 3 to `nanosoc_multicore_addrmap.h`. | These **must not split**. A wrapper reference to a parameter the pinned tidelink lacks makes the superproject unelaboratable from its own pin — the wrapper's own comment at `:768-785` states the rule and the ordering (push, `ls-remote`-verify, then move pin + connection in one commit). |
| **6** | ASIC | First synthesis run with the divider **physically present**. Confirm the SDC bind-or-die guard takes its non-skip branch and `protect_link_clk_div.tcl` binds a real cell. **Add `create_generated_clock` on `clkdiv_r`.** Leave the 12-clock assertion and `set_case_analysis` alone — `/1` mode keeps both valid. | This is the first honest measurement of anything in this area. Expect surprises here, not earlier. |
| **7** | ASIC, separate | Divided constraint mode(s): second `constraint_mode` + views, re-derived `_sys_grp`, CTS/CCOpt spec for the clock mux. **Or** explicitly defer by setting `LINK_RATE_MAX_RATIO = 3'd0` at the wrapper — register present, ratio structurally pinned `/1` — if the freeze arrives first. | The escape hatch matters: it lets steps 1–6 land before freeze without shipping a reachable unsigned-off clock structure. |
| **8** | later, separate | Ratio-scale the four `hclk` backstops. | Touches the N1 / TL-042 family. Needs its own hazard pass. Until it lands, document `/8` and `/16` as no-traffic diagnosis only. |

Steps 1–2 are landable **today**, before any design decision below is made.

---

## 7. OPEN QUESTIONS FOR THE OWNER

1. **Ship `LINK_RATE_MAX_RATIO = 3'd4` (all ratios reachable, only `/1` signed off) or `3'd0` (register present, ratio structurally pinned, capability deferred)?**
   *Trade-off:* `3'd4` gives a bring-up knob that can open a marginal eye on a die you cannot re-spin, at the price of a timing signoff that describes a state software can leave. `3'd0` keeps the signoff structurally true and keeps the whole control path built, tested and ready to enable in a re-spin — but if the eye is marginal on first silicon you will have shipped the register and not the capability.

2. **Is a second constraint mode for `/2` worth the ASIC schedule before freeze, or do all divided ratios ship as unsigned-off bring-up modes?**
   *Trade-off:* `/2` is the ratio most likely to be useful (50 MHz link, 2× the UI) and one mode roughly doubles the view count for that mode's corners. Certifying just `/2` converts the most probable rescue path from "unsigned-off but exercised" to "signed off," and lets `MAX_RATIO=1` — a much narrower unsigned-off surface than `MAX_RATIO=4`.

3. **Is one chip POR per sweep point acceptable, or is a warm rate-change path worth commissioning?**
   *Trade-off:* on a bench the `nrst` pad is a wire and the cost is seconds. A warm path buys sweeps without re-running the boot, but costs the TX word-counter re-zero (the documented root cause of the 12-deploy lock-count lottery), collides with the `HARDEN_SWI` shim that exists to prevent a wedge-until-power-cycle, and has no software route back once the peer's FCSM desynchronises. **Recommendation: refuse it.** But it is your call whether the sweep ergonomics matter more than I think.

4. **What is the maximum ratio we permit under traffic, given `TX_STALL_TIMEOUT_LOG2=16` is unscalable on *both* dies and compute's copy is unreachable from this repo?**
   *Trade-off:* a documented `/2` or `/4` ceiling under load keeps the backstop budgets credible without touching the N1/TL-042 family; permitting `/8`/`/16` only with the data plane off makes them an eye-diagnosis instrument rather than an operating mode. Or accept the risk and re-budget the timers — which is step 8, a separate hazard pass on the code that N1 lives in.

5. **Do divided ratios apply to the eth↔compute pair at all before the compute merge, or are they gated to eth↔eth?**
   *Trade-off:* slowing eth's TX is setup-conservative for compute and therefore unilaterally safe in the timing direction, but compute's SDC would then be wrong by up to 40× and its `[C2]` boundary is still miscut — so a divided eth↔compute link is a configuration for which *no* die has a defensible constraint set. Gating to eth↔eth is honest and costs nothing today, since the pair has never run anywhere.

6. **Should the ratio register be peer-writable — i.e. sited in Region 4/8/C, reachable over the existing I2C sideband — instead of quadrant 3?**
   *Trade-off:* peer-writable would allow a bilateral symmetric rate change from one SWD session instead of two, using the `FINALIZE_GO` rendezvous precedent. Against it: it puts a clock knob on a bus the peer die can drive, master election is a coin flip on identically-tied straps, the I2C slave's address changes from `0x7E` to `i2c_slv_addr_reg` (POR `0x00`) the instant it role-locks, and the write window would have to fit inside a window that `SELF_ARM_TRAIN_EN(1'b1)` makes vanishingly small. **My recommendation is no, and the `autoneg` verdict is the reasoning** — but "two SWD sessions per sweep point" is a real ergonomic cost and you may weigh it differently.

7. **Does the ratio register need a write key (a magic value in a second word), or is the `!role_locked_o` gate plus the killed alias sufficient?**
   *Trade-off:* a key defends against a stray AHB write inside the `0x2E03_6xxx` page at the cost of a second register and a two-write recipe. After step 1 the 32 KB alias is gone and the write window closes permanently at role-lock, so the exposure is a genuine firmware address bug during a ~milliseconds-long window before role-lock. I lean no; the design is cheap to add a key to later, and expensive to remove one from once host tooling depends on it.

8. **Who owns "the compute chiplet gets a divider," and is it in scope before tapeout?**
   *Trade-off:* it is a merge project across two forks with disjoint object stores and 2431 lines of `src/rtl` diff, plus two instances, two ratio sources and two register homes. Deferring it means eth can only lower a rate the peer cannot follow — which is fine for the exposed eth→compute direction and useless for compute→eth. Not answering this is itself a decision.

---

## Attribution summary

| Element | Source |
|---|---|
| Quadrant-3 aperture, `!role_locked_o` write gate, sticky port-vs-register mux, cold-POR-only scope | **`minimal`** (spine; the only proposal with zero fatal flaws) |
| "Delete the quiesce, use the cold window already proven" | **`firmware` adversarial verdict** (its own prescribed repair) |
| Ratio clamp before the compare; 2FF+equality readback sync; `_PRESENT` defaulted off; select+mux both inside the generate; `_MAP_SPAN`; `haddr[15]` alias | **`firmware` fixable flaws** |
| `MAX_RATIO` tied to certified ratios; one-cycle unconditional ack (no `ext_txn` cover in quadrant 3); POR re-zeroes the TX word counter ⇒ refuse the warm path; separate-commit discipline | **`clean`** |
| Do not negotiate; rate agreement is a firmware convention with a fail-loud check | **`autoneg`** (negative result: `SELF_ARM_TRAIN_EN` collapses the window, master election is a coin flip) |
| Settle-gated POR extension on `u_chiplet_controller.poresetn` only | **new** — closes `minimal`'s adoption race without `firmware`'s post-lock reset hazard |
| "Bit-identical netlist" is false; the divider constant-folds today; `clkdiv_r` needs a `create_generated_clock` | **`minimal` adversarial verdict**, corroborated independently by three others |