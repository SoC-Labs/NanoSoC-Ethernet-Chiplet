# HANDBACK — `ahb_sub_hreadyout` frozen at 0: the holder is `wr_hold_r`, starved by the **W-channel** FC node

**To:** the rig/dev session that filed `BUGREPORT_AHB_SUB_HREADYOUT_HOLD_2026_08_19.md`.
**From:** diagnose-bug loop (static RTL grounding + adversarial refutation + cocotb unit repro).
**Date:** 2026-08-19.
**Subsystem:** `tidelink_0` (die_a) `u_xhb_sub` AHB→AXI subordinate bridge + its `tidelink_top` wrapper,
and the per-channel `AXI4ToWlink` FC replay nodes behind it. Target `kr260-pair-onchip`.
**Bitstream RTL = tidelink `f3857392`** (NOT the working tree `3620af33` — see §6, this is load-bearing).
**Capture:** `tidelink/imp/hw_gate/awready_ila_capture/results_2026_08_19/ila_awready_wedge_2026_08_19.csv`
(re-decoded hex-first, independently, from the raw CSV; every count in your report reproduces exactly).

---

## 1. Verdict (one line)

**Rank-5 `wr_hold_r` (`tidelink_top.sv@f3857392:1982`) is the operative holder of `ahb_sub_hreadyout=0`, it
never clears because the `wvalid & wready & wlast` term of `wr_hold_clr` (`:1906`) never completes on the
*separate, unprobed, depth-32* W-channel FC node `wlink_axiwFC` (`AXI4ToWlink.v:432,567`) while the AW node
stays healthy — REPRODUCED in cocotb, where the missing term measures as `s_axi_wready`.**

This is exactly the hazard the built RTL names by name in its own comment at `f3857392:1891-1897`.

---

## 2. LEADING MECHANISM, and the frozen values that ground it

### 2.1 The mechanism, in one paragraph

`ahb_sub_hreadyout` is a 6-way priority mux (`f3857392:1978-1983`). Under the wedge the master-facing ready
is held by a **two-term relay**: rank-3 `(ext_is_nonseq && !pipe_valid_r)` (`:1980`) masks the single
`pipe_valid_r=0` cycle of each iteration, and rank-5 `wr_hold_r` (`:1982`) masks every other cycle. Between
them the mux covers 100% of cycles and **never emits a 1**, even though XHB500 itself is making progress and
offers `xhb_sub_hreadyout_raw=1` on some cycles. `wr_hold_r` cannot clear because `wr_hold_clr` (`:1906`,
built = the **pre-TL-043 LEVEL guard** `(s_axi_wvalid & s_axi_wready & s_axi_wlast) | synth_b_pending`)
requires a `wlast`-qualified W handshake that never happens, and its only other escape, `synth_b_pending`,
is produced by backstops that are **starved, not saturated** (§2.4).

### 2.2 Rank-6 (`xhb_sub_hreadyout_raw` stuck low) is REFUTED by the frozen state — so rank-5 is forced

This is the step that promotes the mechanism from hypothesis to deduction, and it is the correction that
matters most to your report's "either rank-5 or rank-6" framing.

- `s_axi_awvalid = 1` at **exactly** samples 2234, 3002, 3770 (col15), with `s_axi_awready = 1 x4096`
  (col34) and `ahb_sub_hreadyout = 0 x4096` (col22).
- XHB500's address path stores **one entry, total**: `cntrl_1` = `xhb500_reverse_regd_slice_rst_empty`
  (`ready_src = ~buffer_full[0]`, `:69`; `valid_dst = valid_src | buffer_full[0]`, `:72`); `cntrl_2` =
  `xhb500_bypass_regd_slice`, three wires and **zero storage** (`:37-39`). `awvalid = cntrl_2_out_valid &
  hwrite` (`core_addr.sv:278`), `cntrl_2_out_ready = awready` (`core_addr.sv:206`) = 1 always.
- Three consumed addresses with at most one resident at sample 0 ⇒ **≥2 fresh `cntrl_1` entries inside
  [1,4095]**. Entry needs `cntrl_1_in_valid = hsel & hready & ~hmastlock & NONSEQ`
  (`core_addr.sv:162-166`), and the wrapper drives `xhb_sub_hready = pipe_valid_r ? raw : (ext_is_nonseq ?
  1'b0 : raw)` (`:1831-1832`) — **every arm that can yield 1 requires `raw = 1`**.
- ⇒ **`xhb_sub_hreadyout_raw` was HIGH on ≥2 in-window cycles. Rank-6 cannot be the sustained holder.**

On those raw-high cycles `ahb_sub_hreadyout` was measured 0, so a higher-priority term masked it. Term by
term, on exactly those cycles: rank-1 `sub_err1_r` is masked only when `synth_b_pending=1`, which would force
`wr_hold_clr=1` (`:1907`) → `wr_hold_r=0` → fall-through to rank-6 = raw = **1**, contradicting col22;
rank-2 emits 1, not 0; rank-3 is impossible there (it would force the middle arm of `:1832` to 0, so no
`cntrl_1` entry could have occurred); rank-4 `rd_pipe_r` is impossible (set only on
`ext_is_nonseq && !ahb_sub_hwrite && !pipe_valid_r`, `:1851`, so the pipe payload is a READ and would yield
ARVALID, not the observed AWVALID). **Only rank-5 survives.**

### 2.3 Non-release, from the same zero

A `wr_hold_clr` at cycle D drives `wr_hold_r<=0` at D+1 (`:1914-1918`, clear-wins). `pipe_valid_r` only
clears on a raw-high (`:1606`), so at D+1 the mux falls to rank-6 = raw = 1 — **a captured high sample**.
Sampling is verified contiguous (`Sample in Buffer` == `Sample in Window` == 0..4095, single TRIGGER at 512),
so a 1-cycle pulse anywhere would have been caught. **0 high samples in 4096 ⇒ no `wvalid & wready & wlast`
and no `synth_b_pending` occurred in-window.**

### 2.4 Both AHB backstops are STARVED, not saturated

`sub_stall_busy = !xhb_sub_hreadyout_raw` (`:1551`); `sub_ext_stalled = (sub_stall_fill||sub_stall_busy) &&
!err` (`:1550-1557`); `if (!sub_ext_stalled) sub_stall_ctr_r <= '0` (`:1642`). **Each raw-high re-zeroes the
counter against a 2^16 threshold** (`SUB_STALL_TIMEOUT_LOG2 = SUB_OUTSTANDING_TIMEOUT_LOG2 = 16`,
`:1499,:1508`). Likewise `sub_osr_ctr_r <= '0` on `!sub_axi_outstanding || sub_axi_progress` (`:1726`,
`:1582`). The loop's **own partial progress** keeps its own recovery timers at zero.

> This **refutes your report's reading** that the backstops "fired thousands of times over ≥76 s without
> clearing the wedge". They almost certainly never reached threshold at all. Corollary from the same zero:
> had one expired with `sub_wr_os_ctr != 0`, `synth_b_pending` would set (`:1937,:1945`) → `wr_hold_clr`
> (`:1907`) → rank-6 passes raw → a captured 1. None seen.

### 2.5 The link side is healthy — which is why the *W node* is the only place left

`wlink_axiawFC a2l_full = 0 x4096` (col60); AW ACK ptr 7→8@2636, 8→9@3788 (col28); `isAckPacket` high in 384
samples in three 128-sample bursts; no NACK/CRC (col49/58); FCSM state ∈ {4,5} (col18); `socl_l7_wdog_cnt =
0x0000` (col46); die_b idle-and-healthy and **actively ACKing** (`send_ack_req = 1 x2560`, col9).
`AXI4ToWlink` instantiates **five independent FC nodes** (`:529,567,605,643,681`); **the capture probes
exactly one**. `s_axi_awready` = `wlink_axiawFC` app_ready (`:430`, node = `WlinkGenericFCReplayV2_1`, 4-bit
ptr, depth 8); `s_axi_wready` = `wlink_axiwFC` app_ready (`:432`, node = `WlinkGenericFCReplayV2_3`, **6-bit
ptr, depth 32**) — a different module, never probed.

### 2.6 What the capture does NOT determine

`wr_hold_clr`'s W handshake has **three** terms and they are indistinguishable in this capture. Your report
framed the open question as a binary about `s_axi_wready`; it is **three-way** — `wready` (W node starved),
`wvalid` (XHB500 presenting no data), `wlast` (multi-beat never reaching its last beat) — and **they have
different fixes**. The unit bench (§4) resolves it, with the honest caveats stated there.

---

## 3. What the capture KILLED

| Mechanism | Killed by |
|---|---|
| **Rank-6 / XHB500 RESP-FSM hang** in `RESP_FSM_SEQ_NSEQ` (either the `~address_readyout` arm, `core_resp.sv:181-183`, or `beat_done` never asserting, `:188`) | `s_axi_awvalid`=1 at samples **2234/3002/3770** (col15) + `awready`=1 x4096 (col34) through a 1-deep `cntrl_1` (`reverse_regd_slice:69,72`) and zero-storage `cntrl_2` (`bypass_regd_slice:37-39`) ⇒ ≥2 cycles of `raw=1` (§2.2). **Also refutes the standing memory note `tidelink-d2d-wedge-xhb500-respfsm-hang` for this capture** — XHB500 is progressing on its own AHB port. |
| **H1 on the AW channel** (a2l window fills on peer-ACK silence → `app_ready` → `awready` dies) | `s_axi_awready` = **1 x4096** (col34) and `wlink_axiawFC a2l_full` = **0 x4096** (col60). Premise also false: AW ACK ptr advances twice (col28), `isAckPacket` high 384 (col59), die_b `send_ack_req`=1 x2560 (col9). **Scoping correction to your report: this kills H1 on the AW channel ONLY — the W/B/AR/R nodes are unmeasured, and H1's mechanism on the W node is now the LEADING suspect.** |
| **H2** (`swi_enable` / `enable_app_clk_demet` deassert) | `swi_enable`=1 x4096 (col43), `enable_app_clk_demet_io_out`=1 x4096 (col36/37) on **both** dies. `Wlink.v` fans one `swi_enable` into all five FCSMs ⇒ H2 dies **globally**, not just on the probed node. |
| **FCSM state-7 / watchdog starvation** | state ∈ {4,5} only (col18); `socl_l7_wdog_cnt = 0x0000 x4096` (col46). |
| **Sideband / FCSM_6 involvement** | `u_fc_adapter/dbg_tx_hreadyout` = 1 x4096. |
| **Link integrity** (NACK / CRC / ACK-fifo backup) | `isNackPacket`=0, `crcCorruptSeen`=0, `ack_nack_fifo_io_wfull`=0, each x4096. |
| **die_b as the stalling party** | every probed die_b signal healthy/idle: `hreadyout`=1 x4096, `awvalid`=0 x4096, occupancy 0. *(Caveat: this does NOT show die_a's writes ARRIVED — die_b's wl2axi side is unprobed.)* |
| **"TL-037 fired during the wedge"** (your report option **b**) | `ahb_sub_hreadyout` = 0 in **4096 contiguous** samples. A TL-037 fire (`:1702-1704`) is gated on `sub_wr_os_ctr == 3'd0`, which forces `sub_wr_stuck_fire`=0 that cycle (`:1937`), so `synth_b_pending` is still 0 next cycle when `sub_err2_r`=1 selects **rank-2** (`:1979`) and drives `hreadyout=1` for exactly one sample. Contiguity means it would have been captured. **Zero highs ⇒ no fire in-window.** (A fire strictly *before* the window is not excluded by this capture.) |
| **"The backstops fired thousands of times without clearing the wedge"** | Refuted from RTL, not a probe: `:1642` + `:1551` (§2.4). Report option **(a) "never armed"** is right, with two independent reasons — TL-037 is nested under `else if (sub_stall_expired)` which never triggers, **and** its `sub_wr_os_ctr == 3'd0` gate is defeated by the very AWs the loop generates (`:1644`, `:1720-1722`). |
| **"AW occupancy caps at 7 and never 8 — cause unknown"** (an open item) | **Dissolved, not diagnosed.** Per-sample re-derivation: `wbin_ptr` 0xc/0xd/0xe/0xf with 3 transitions (2235/3003/3771), ACK ptr 7/8/9 with 2 (2636/3788), occupancy 5 x2602 / 6 x1477 / 7 x17 with only 5 transitions — it touches 7 once for 17 samples and drops back when an ACK lands. Depth is **8** (`WlinkGenericFCReplayV2_1.v:54`), so 7 is simply one-below-full. A histogram was read as a saturating counter. **Close this item.** |
| **The "phase-masking livelock" KILL** (i.e. the kill is itself killed) | **Kill REVERSED, on an RTL error not a frozen value.** It argued each round must emit one rank-6 high "because `wr_hold_set` cannot re-arm while `pipe_valid_r` is high" — but **rank-3 at `:1980` outranks rank-5 at `:1982`** and covers exactly the `pipe_valid_r=0` cycle. Cycle trace on the built source: pv=0 → rank-3 masks *and* `wr_hold_set` arms (`:1905`, same qualifier as the pipe re-latch `:1596`) → pv=1 → rank-5 masks. No 1 emitted. **The mechanism is restored as the leading one.** |

**Weakened, not killed:** "the a2l path is healthy because pointers advance." Measured rate is 3 pushes /
2 pops per 4096 cycles with occupancy **net rising** 5→6 (touching 7 of 8). Advancing is true; *healthy* is
not established — the AW window is drifting toward full over a directional trend of only 5 transitions.

---

## 4. UNIT VERDICT — **REPRODUCED** (with the circularity stated plainly)

**Bench:** `tidelink/cocotb/tidelink_axi_datanode_recovery/test_tl0xx_wnode_starvation_wrhold.py` (new, 471
lines; env ADAPTED, not new). Targets `wstarve_a / wstarve_b / wstarve_ctrl / wstarve_neg`
(`SIM_BUILD=sim_build_wstarve`, `sim_build_wstarve_neg`). VCS T-2022.06-SP2, TIDELINK_PHY_V2 pair,
hclk 20 ns, CRC off, injector not armed. **No RTL changed.**

**Build provenance (load-bearing).** Compiled with `+define+TIDELINK_WR_HOLD_CLR_LEVEL_MUTANT`, which
recreates the `f3857392` **pre-TL-043 level guard** `wr_hold_clr = (wvalid&wready&wlast) | synth_b_pending`
byte-for-byte. `f3857392..HEAD` on `tidelink_top.sv` was diffed: the only `wr_hold`-relevant delta is TL-043;
the rest is `tidelink_link_clk_div`/`link_rate_regs` behind `LINK_RATE_REGS_PRESENT=0` (inert) plus one debug
output. **So the mutant build is the silicon semantics.** Backstops scaled to 2^13 (not 2^16), per this
suite's convention — every counter number below is scaled by 8.

**A new AHB master was required and written** (`FaithfulPipelinedWriter`): all three existing masters in this
suite (`test_axi_datanode_recovery.py:89`, `test_axi_datanode_gaps.py:236`,
`test_axi_datanode_writehold.py:63`) drop HTRANS to IDLE one cycle after the address phase **regardless of
HREADY**, which kills `ext_is_nonseq`, stops `wr_hold_set` re-arming and stops rank-3 masking — the relay
could not form and the run would have been vacuous. With the new master, `ext_is_nonseq` = 30000/30000 in
every arm.

### 4.1 Result — all four arms pass, 30000 monitored hclk each

**ARM A — hard W-node a2l ACK freeze (the repro).**

| measure | value | vs silicon |
|---|---|---|
| `ahb_sub_hreadyout` HIGH | **5 / 30000 (0.017%)**; longest zero-run **25431** hclk | col22 = 0 x4096 (0.017% ⇒ ~0.7 expected in a 4096 window) |
| `wr_hold_r` HIGH | 21770/30000, latched high at end | the deduced holder, measured |
| `xhb_sub_hreadyout_raw` | rises **28x**, high 38 cycles; **raw=1 & `wr_hold_r`=1 on 30**, raw=1 & hreadyout=1 on only 4 | rank-5 is the operative holder of the ready cycles the bridge offers |
| `s_axi_awready` HIGH | **29338/30000 = 97.79%** | col34 = 1 x4096 — **MATCH** |
| `wlink_axiawFC a2l_full` | 662/30000 (low) | col60 = 0 — **MATCH** (control node healthy) |
| `wlink_axiwFC a2l_full` | **21074/30000**, app_addr lapped to 32 vs link_addr 0 | the starved depth-32 node |
| `s_axi_awvalid` | **33 discrete pulses** in 30000 | col15 dribble — **MATCH** |

Terminal state @29760: `wapp=32 wlink=0 wfull=1 wready=0 hrdyo=0 wrhold=1`. Far-side BRAM[OFF_FILL] =
`0xA5A50000` — the first write **did** land, which is exactly the partial progress that starves the backstops.

**The decisive three-way measurement (Arm A):** `s_axi_wvalid` HIGH 20978/30000, 32 pulses → **PRESENT**.
`s_axi_wlast` HIGH 29994/30000 → **PRESENT**. `s_axi_wready` HIGH 8926/30000 and **0 for the whole tail** →
**THIS IS THE MISSING TERM.** Arm B agrees (wvalid 14816, wlast 29994, wready 15090, 0 in tail).

**ARM B — paced drain, 1 W entry per 768 hclk (the measured col15/col3 cadence).** `hreadyout` HIGH 24/30000,
longest zero-run 15374. `wr_hold_r` HIGH 29836/30000; raw rises 67x, raw&`wr_hold_r` on 49. **Backstop
starvation confirmed exactly as predicted:** `sub_stall_ctr_r` **sawtooths, max 1235 against an 8192
threshold, re-zeroed 67 times** by the loop's own raw-highs (`:1642`); `synth_b_pending` = 0 cycles,
`sub_err1_r` = 0, `sub_err2_r` = 0. Arm A by contrast let the counter reach 8192 **once** → `synth_b_pending`
pulsed 2 cycles → one HRESP=ERROR → the single `hreadyout` blip at 25442 → then `wr_hold_r` re-latched and the
port re-wedged. **Bounded single blip, then permanent.**

**NEGATIVE CONTROL** (`+define+TIDELINK_DISABLE_WR_HOLD`, Arm-A stimulus): `wr_hold_r` HIGH = 0 (tied off);
raw&hreadyout goes **4 → 33** of the same 38 raw-high cycles; AHB address phases accepted **5 → 34**. The
bench sees the hold — the run is not vacuous.

**DISCRIMINATION CONTROL** (freeze the **AW** node instead): `s_axi_awready` collapses to **1405/30000 =
4.68%**, `wlink_axiawFC a2l_full` HIGH 28595/30000, `wlink_axiwFC a2l_full` = 0, `s_axi_wready` = 30000/30000.
That is the **mirror image** of the frozen state (col34=1 x4096, col60=0). The bench can tell the two nodes
apart, and only the W-node freeze matches silicon.

### 4.2 Stated honestly — what is established vs what is circular

1. **Not circular. `s_axi_wlast` is ELIMINATED.** Under single-beat bufferable traffic `wlast` is high
   29994/30000 in every arm including both controls. A missing-`wlast` wedge (branch B) cannot be the
   mechanism for single-beat traffic, and nothing in the 67 captured columns suggests multi-beat. If PS
   traffic is ever shown to be multi-beat, re-run with a withheld last beat — the bench takes it.
2. **Not circular. The AW node is ELIMINATED as the starved node** — CTRL-AW is a real discriminator and
   produces the opposite of the frozen state (§4.1).
3. **Partly circular, plainly:** `wready` was *made* low by freezing the W node's ACK pointer, so "wready is
   the missing term" is partly a consequence of the stimulus. What is **not** circular is that this is the
   only one of the three stimuli that reproduces **every other silicon column simultaneously** (awready high,
   AW a2l_full low, awvalid dribbling, hreadyout pinned 0, `wr_hold_r` latched, stall counter sawtoothing);
   the alternative "wvalid missing" route constructible here (AW backpressure) contradicts col34.
   **A `wvalid`-missing wedge from an internal XHB500 cause (branch C) is NOT excluded by this bench** — it
   needs a silicon probe on `s_axi_wvalid`/`wready` to separate. That probe is cheap (§5).
4. **NEW FINDING the mechanism statement did not contain, and it changes the fix (§6): removing `wr_hold_r`
   does NOT unwedge the port.** In the negative control the master still sees a **16387-hclk** contiguous
   `hreadyout=0` run and completes only 34 writes in 30000 cycles. Rank-5 is the operative holder of the
   *raw-high* cycles (33 of 38 blocked) — the deduction stands — but ~99.9% of the stall is XHB500's own
   `xhb_sub_hreadyout_raw` low because the W path is backed up **inside** the bridge (`stall_writes` high
   9943, `wdata_in_ready` low ~21000 cycles). **A wrapper-only fix converts a hard wedge into a 6.8x-slower
   wedge.**
5. **Scale caveat.** Backstops ran at 2^13. Arm A's single recovery blip at 25442 would land at ~8x depth on
   shipping RTL. Arm B's starvation verdict is *more* decisive at 2^16, not less (the sawtooth peak is set by
   the 768-cycle pacing, not the threshold). **Arm B's 24 blips are spaced at exactly 768 — an artefact of
   the pacing imposed by hand, not an independent finding**; the spec's "sharpest outcome" test is confounded
   there and must not be read as localising a silicon-only delta. **Arm A is the arm that matches silicon**,
   and it needs no pacing to produce the AW dribble.
6. **Disclosed divergence.** Sim AW cadence is 96/96/128/928 in a ~1248-cycle super-period (4 pushes), not
   silicon's 768 spacing with 3 pushes. The link ratio differs; the 768 cadence had to be imposed and does
   not emerge.

---

## 5. NEXT RIG EXPERIMENT

The sim resolves the three-way question **as far as a bench can**. One silicon capture closes branch C
outright. Three bits are the whole experiment; everything else is context and control.

### 5.1 Probe set

**Decisive (3):**
- `tidelink_0/inst/u_tidelink_top/s_axi_wready` — = `wlink_axiwFC` app_ready (`AXI4ToWlink.v:432`)
- `tidelink_0/inst/u_tidelink_top/s_axi_wvalid`
- `tidelink_0/.../axi2wl/wlink_axiwFC/a2l_fc_replay/a2l_full` — depth-32 node (`WlinkGenericFCReplayV2_3.v:54`)

**Confirming the deduction (measure what was inferred):**
- `s_axi_wlast`; `wr_hold_r`; `pipe_valid_r`; `xhb_sub_hreadyout_raw`; `synth_b_pending`; `sub_wr_os_ctr[2:0]`
- `sub_stall_ctr_r[16]` **and** `[13]` — starvation vs saturation, as high bits not as a wait
- `sub_err1_r`, `sub_err2_r`
- `wlink_axiwFC/a2l_fc_replay/fifo_io_wbin_ptr[5:0]` and `link_addr_to_app_clk_r_addr[5:0]`

**The never-measured premise:**
- `ahb_sub_htrans[1:0]`, `ahb_sub_hsel`, `ahb_sub_hwrite` — "the master holds NONSEQ" is an AHB-protocol
  *inference*, never a measurement
- `ahb_sub_hprot[2]` (EWR/bufferable) — selects which `beat_done_w` branch is live
  (`core_wdata.sv:316` vs `:317`); not among the 67 captured columns
- `u_xhb_sub` `core_addr` `address_readyout` (`:229`) and `pause_addr_submit` (`:151`); `s_axi_bvalid/bready`

**Anchors/controls, keep from the old set:** `ahb_sub_hreadyout`, `s_axi_awvalid`, `s_axi_awready`,
`wlink_axiawFC a2l_full`.

**MANDATORY NEW CONTROL:** one bit of a known-period free-running counter on the ILA clock.
`ila_arm.log` records **no ILA clock frequency**, so the report's `163.8 us` is decode-unverified — every
statement in this handback is deliberately in **cycles**.

### 5.2 Trigger

1. **Primary:** `(ahb_sub_hreadyout == 0) && (s_axi_awvalid == 1)`, trigger position **50%** (2048/4096), so a
   raw-high cycle sits mid-window with ~2048 cycles of context each side. Arm as on 2026-08-19 (wedge already
   established; `ila_arm.log` shows DO_CAPTURE forced after 76 s).
2. **Second capture, same probes:** rising edge of `s_axi_wready` — the only way to see the drain event and
   the cycle immediately after it.
3. **Third, if depth allows:** 8192 samples, no trigger condition, to hold ≥10 AW iterations at the observed
   768-cycle cadence. Depth still cannot reach 2^16, so `sub_stall_ctr_r[16]` is read as a bit, never waited on.

### 5.3 Pre-registered decision tree — branch on (`wready`, `wvalid`, `wlast`, `wlink_axiwFC a2l_full`)

- **(A) `wready`=0 x4096 AND W `a2l_full`=1 x4096** → **the sim's answer confirmed on silicon.** H1's
  mechanism is real, on the **W** channel: the split-FC-node signature the built RTL predicts at
  `:1891-1897` / `AXI4ToWlink.v:430` vs `:432`. Go to §6 fix (1)+(2).
- **(B) `wready` pulses ≥1 AND `wlast`=0 on every (`wvalid & wready`)** → multi-beat write never reaching its
  last beat; `wr_hold_clr`'s `wlast` term structurally unreachable. Fix: hold must key on per-beat
  completion. *(The sim disfavours this for single-beat traffic — §4.2(1).)*
- **(C) `wready` pulses AND `wvalid`=0 on those cycles** → XHB500 produces no write data. **This is the branch
  the bench cannot exclude.** Read `stall_writes = ~address_readyout || pending_broken_b_resp || ~qaccept`
  (`core_wdata.sv:251`) and `pause_addr_submit`'s hazard_full arm (`core_addr.sv:155-159`). Cause is
  XHB500-side, same family as the Fix-K bid-corruption note at `:1955-1965`. **The fix is NOT in `wr_hold_r`.**
- **(D) `wready`=1 x4096 AND `a2l_full`=0 AND (`wvalid & wlast`) pulses** → `wr_hold_clr` **did** fire, so
  `wr_hold_r` must have cleared. If `wr_hold_r` still reads 1 x4096, **the leading mechanism is REFUTED**;
  re-open rank-1/rank-2 via `sub_err1_r`/`sub_err2_r`/`synth_b_pending`.
- **(E) `ahb_sub_htrans != 2'b10` for most samples** → the "master holds NONSEQ" premise fails; `ext_is_nonseq`=0,
  `wr_hold_set` never re-arms, rank-3 never masks ⇒ `wr_hold_r` was set **before** the window: a
  set-once-never-cleared static hold, not a relay. Same fix site, different narrative — and it kills the
  "re-submission loop" reading entirely.
- **(F) `ahb_sub_hprot[2]`=0 (non-bufferable)** → `beat_done_w`'s first branch is unreachable
  (`(~last || ewr)`, `core_wdata.sv:316`), so every raw-high came via `~ewr & bvalid & bready` (`:317`) ⇒ the
  **B returned** ⇒ the write completed end-to-end and the wrapper alone is withholding the answer. Strongest
  possible case for a wrapper-only fix.
- **(G) `sub_stall_ctr_r[13]` toggles but `[16]` never sets, sawtoothing with the AW cadence** → **backstop
  starvation confirmed on silicon** (`:1642`), matching Arm B. If instead `[16]` sets and the counter rolls,
  starvation is refuted, your report's "fired thousands of times" reading is right, and the failure is that
  `synth_b_pending` fires and still does not release ⇒ level-vs-edge guard.
- **(H) `synth_b_pending`=1 anywhere while `ahb_sub_hreadyout`=0** → the synth-B drain runs and the master is
  still not answered ⇒ the built **level** guard `| synth_b_pending` (`:1907`) is inert in silicon ⇒ escalate
  directly to TL-043's edge-qualified `wr_hold_drain_release`, which exists **only** in the working tree
  (`3620af33:2009`) and is **not in the bitstream**.
- **(I) Any `ahb_sub_hreadyout`=1 sample at all** → check `sub_err2_r` on that sample (rank-2, `:1979`): either
  a backstop fired, or the release path works and the wedge is intermittent rather than static.

---

## 6. FIX direction, and which prior fixes are implicated

**If the mechanism holds (branch A or G), the fix is two-part, and part 2 is not optional.**

1. **The real fix is at the W-channel credit return, not in the wrapper.** `wlink_axiwFC` is a separate
   depth-32 replay node (`AXI4ToWlink.v:432,567`; `WlinkGenericFCReplayV2_3.v:44,54`) whose window laps and
   never drains. §4.2(4) is the evidence that this is where the fix must land: with `wr_hold_r` compiled out
   entirely, the port is **still** wedged (16387-hclk zero-run, 34 writes in 30000 cycles) because
   `xhb_sub_hreadyout_raw` sits low on XHB500's own backed-up W path (`stall_writes` high 9943,
   `wdata_in_ready` low ~21000). **A wrapper-only fix turns a hard wedge into a 6.8x-slower wedge.**
2. **`wr_hold_r` needs an escape that does not depend on the W handshake.** Its only exits today
   (`:1906-1907`) are the W handshake itself and `synth_b_pending`, and §2.4/Arm B show `synth_b_pending` is
   starved by the loop's own partial progress. Give `wr_hold_r` an **independent** timeout, or make the
   stall counter immune to re-zeroing by raw-highs that belong to a stalled transfer (`:1642` + `:1551`).

### Prior fixes — implicated, exonerated, or absent

- **TL-043 — ABSENT FROM THE BITSTREAM. This is the single most important provenance fact in this handback.**
  Built `f3857392:1906-1907` carries the **pre-TL-043 LEVEL guard** `wr_hold_clr = (wvalid&wready&wlast) |
  synth_b_pending`. The edge-qualified `wr_hold_drain_release` exists **only** in the working tree
  (`3620af33:2009`). **Any diagnosis reasoning from the working-tree `wr_hold_clr` is reasoning about RTL
  that is not on the FPGA**, and any bench built from the worktree tests RTL that silicon does not have. It
  is *not implicated as a cause* here — but branch (H) is exactly the state that would escalate to it, and
  even then it would only address part 2 above, never part 1.
- **TL-037 — NOT IMPLICATED, and it did not fire.** Provably no fire in-window (§3), and dead **twice over**:
  nested under `else if (sub_stall_expired)` which never triggers, and gated on `sub_wr_os_ctr == 3'd0` which
  the loop's own 3 AW accepts defeat (`:1644`, `:1720-1722`). **Your report's three-way question answers as
  (a) "never armed".** TL-037 is not the bug and needs no change for this wedge — but note its gate is
  structurally defeated by *any* traffic pattern that keeps a write outstanding, which is worth a separate item.
- **N1 read-backstop fix — NOT IMPLICATED.** Same `!synth_b_pending` gating argument rules it out in-window.
- **TL-002 / `wr_hold_r` itself — IMPLICATED AS THE HOLDER, NOT AS THE ROOT.** The latch is doing what it was
  written to do; the built RTL's own comment at `f3857392:1891-1897` predicted this exact failure by name.
  The root is the split AW/W FC nodes. **Do not "fix" this by deleting `wr_hold_r`** — the negative control
  shows that leaves the wedge in place.

### Corrections to the report worth carrying forward

- RTL anchors: the `hreadyout` mux is **`:1978-1983`** (report says ~`:1909`); `sub_wr_os_ctr` is declared at
  **`:1526`** (report says `:1592`); `s_axi_awready` is at **`:2965`** (report says `:2882`). Only the TL-037
  anchors `:1654`/`:1704` were correct.
- The `163.8 us` window figure assumes the ILA clock is hclk at 25.011 MHz, which `ila_arm.log` does not
  record. **Decode-unverified** — hence cycles throughout, and hence the clock-rate control probe in §5.1.

---

### Artifacts

- New test: `/home/dam1n19/SoCLabs/nanosoc-ethernet-chiplet/tidelink/cocotb/tidelink_axi_datanode_recovery/test_tl0xx_wnode_starvation_wrhold.py`
- Modified (additive only): `/home/dam1n19/SoCLabs/nanosoc-ethernet-chiplet/tidelink/cocotb/tidelink_axi_datanode_recovery/Makefile`
  (`wstarve_a`/`wstarve_b`/`wstarve_ctrl`/`wstarve_neg`, own `sim_build_wstarve*` dirs — honour the stale-build trap, `rm -rf` before first compile)
- **No RTL was changed.** Source the env first: `source /home/dam1n19/SoCLabs/nanosoc-ethernet-chiplet/tidelink/set_env.sh`
