# System-level bug report — ahb_sub_hreadyout held low with awready HIGH and a2l NOT full

> Rig side of the loop. Every line below is a MEASURED value from one ILA capture unless marked (INFERENCE).

## 1. Provenance
- **Build:** isolated worktree `scratchpad/worktrees/awready-ila`, branch `awready-ila-2026-08-18`,
  HEAD `f3857392` = `origin/main` (`2c2f8d43`) + cherry-pick `8895e567` ("fix(tl037): close ahb_sub
  terminal-timeout dead gate", content of `2ce60c2`) + `f3857392` (N3/Hazard-4, content of `be26f51`).
  **TL-037 IS PRESENT in the built RTL** — verified in the built source: `src/rtl/tidelink_top.sv:1654`
  ("TL-037 FIX (2026-08-14, sim-reproduced)") and `:1704` (`sub_err1_r <= 1'b1; // 2-cycle ERROR: terminal timeout`).
  Bitstream: 166 debug nets, setup MET WNS +13.837 ns. Target `kr260-pair-onchip` (BOTH dies in ONE
  xck26; `tidelink_0`=die_a, `tidelink_1`=die_b; on-chip link, no PHY/ribbon).
- **Rig:** kr260-01 @ 10.22.24.159. Link state immediately BEFORE induce (measured, tl39 probe):
  `cal=1 fcsm=4 cr=1 ck=1 llv=0 a2l=0 full=0 anc=1 obs=0x05890000`.
  Immediately AFTER induce: `cal=1 fcsm=4 cr=1 ck=1 llv=1 a2l=0 full=0 obs=0x27890000`.
- **Capture modality:** JTAG ILA (Vivado 2025.2 hw_manager on mapstone-dev), core `hw_ila_1`,
  64 probe groups / 166 net bits, 4096 samples @ hclk 25.011 MHz = **163.8 us window**.
  All 13 checked probes reported ILA_PROBE_OK. Trigger armed on `(awvalid==1 & awready==0)`.
- **Liveness (proves the capture is NOT a dead/all-zero read):** multiple probes span distinct values
  within the window — `fifo_io_wbin_ptr` = c/d/e/f, `link_addr_to_app_clk_r_addr` = 7/8/9,
  `state` = 4/5, `isAckPacket` = 0/1, `ack_nack_fifo_io_rempty` = 0/1.
- **Control:** an earlier armed capture on a HEALTHY link returned TRIGGERED=0 with the same trigger
  (no false-fire), and PS-store traffic produced no wedge — so the trigger and instrument were
  exercised against a known-good state before this run.

## 2. Trigger
- **Kind:** deliberate, authorized induction (single run).
- **Inject params:** ZynqMP **ADMA ch0** (`0xFFA80000`), **write-only** mode (`CTRL0=0x10`,
  pattern 0xDEADBEEF), `AWLEN=0` (single-beat), `AWBURST=INCR`, `AWCACHE=0x3` (bufferable/posted),
  dst = **`0x80000000`** (die_a `ahb_sub` aperture, HPM0_LPD), size 65536 B → ~8192 short transactions.
  Tool `verif/g2_soc_pair/zdma_induce.c --induce 65536 --timeout 3000`.
- **Symptom:** DMA engine **STALLED**: `ISR=0x000`, `STS=0x2` (busy), `TOTAL_BYTE` frozen at
  **8208 of 65536** across three consecutive reads (drain-check 8208→8208→8208).
  Board remained ssh-reachable (APB obs still readable on a separate aperture). Recovered by JTAG-POR.
- **Prior negative control (measured):** 65536 *PS blocking stores* to the same address
  COMPLETED in 16.890 s with `a2l=0` — no wedge. PS stores serialize (1 AW outstanding).

## 3. FROZEN SIGNAL STATE — die_a (`tidelink_0`), counts over 4096 samples
| signal | value | meaning (as read) |
|---|---|---|
| `ahb_sub_hreadyout` | **0 × 4096/4096** | **← WEDGE WITNESS: the AHB subordinate is held, entire window** |
| `s_axi_awready` | **1 × 4096** | AXI AW accept is HIGH — never stalls |
| `s_axi_awvalid` | 0 × 4093, 1 × 3 | almost no AW offered (AHB side is held upstream) |
| `(awvalid=1 & awready=0)` | **0 samples** | the H1 signature NEVER occurs |
| `a2l_fc_replay/a2l_full` | **0 × 4096** | replay window NEVER full |
| `fifo_io_wbin_ptr` (app ptr) | c×2235, d×768, e×768, f×325 | app pointer advancing |
| `link_addr_to_app_clk_r_addr` (ACK ptr) | 7×2636, 8×1152, 9×308 | **ACK pointer ADVANCING — peer ACKs arriving** |
| occupancy `(wbin−link_ack) mod16` | **5×2602, 6×1477, 7×17 — never 8** | window loaded but capped at 7 |
| `ack_nack_fifo_io_rempty` | 1×3712, 0×384 | ACK fifo receiving |
| `ack_nack_fifo_io_wfull` | 0 × 4096 | ACK fifo never full |
| `isAckPacket` | 0×3712, 1×384 | ACKs actively received |
| `isNackPacket` | 0 × 4096 | no NACKs |
| `crcCorruptSeen` | 0 × 4096 | no CRC errors |
| `swi_enable` | 1 × 4096 | link enabled |
| `enable_app_clk_demet_io_out` | 1 × 4096 | FC node enabled |
| `state[2:0]` | 4×3127, 5×969 | normal running; **state 7 never entered** |
| `socl_l7_wdog_cnt` | 0x0000 × 4096 | watchdog flat (consistent: counts only in state 7) |
| `auto_tx_out_advance` | 0×3712, 1×384 | TX advancing |
| `dbg_tx_hreadyout` (fc_adapter/sideband) | **1 × 4096** | the SIDEBAND path is NOT held |

**die_b (`tidelink_1`), same window:** `awvalid=0`, `awready=1`, `ahb_sub_hreadyout=1`,
`a2l_full=0`, `wbin=0`, `link_ack=0`, `swi_enable=1`, `state`=4×3584/6×512 → **die_b entirely idle/healthy**.

- **Raw CSV:** `tidelink/imp/hw_gate/awready_ila_capture/results_2026_08_19/ila_awready_wedge_2026_08_19.csv`
  (4097 data rows × 64 probe groups, both dies). Arm log alongside it.

## 4. What the capture ESTABLISHES (measured, direct)
- The AHB subordinate port of die_a is **held** (`ahb_sub_hreadyout=0`) for the whole window.
- The hold is **NOT** at the AXI AW handshake: `s_axi_awready=1` in every sample.
- The a2l replay window is **NOT** full and **is being ACKed** (`a2l_full=0`; ACK ptr 7→8→9; `isAck` pulsing).
- The link is **up and healthy** during the wedge (`swi_enable=1`, `enable=1`, no CRC, no NACK, FSM in 4/5).
- **die_b is not involved** — it is idle with every relevant signal in the healthy state.
- A **posted-burst master CAN** induce this; a **serialized PS store stream CANNOT** (negative control above).

## 5. What the capture REFUTES
- **H1** ("a2l window fills on peer-ACK silence → app_ready→0 → s_axi_awready dies permanently")
  — **killed** by `s_axi_awready=1 ×4096`, `a2l_full=0 ×4096`, and an ACK pointer that keeps advancing.
  (H1 remains REAL in RTL — dynamically sim-confirmed by forcing the ACK pointer — but it is NOT this wedge.)
- **H2** (`swi_enable` level deassert) — **killed** by `swi_enable=1` and `enable_app_clk_demet_io_out=1`.
- **FCSM state-7 / watchdog starvation** — **killed** by `state`∈{4,5} and `socl_l7_wdog_cnt=0`.
- **Sideband/FCSM_6 involvement** — `dbg_tx_hreadyout=1` (that path is not held).

## 6. Cross-observations (flag: DIFFERENT runs — reconciliation is INFERENCE)
- Earlier same-session run, healthy link, same trigger armed: `TRIGGERED=0` (no false-fire).
- Earlier same-session run: 65536 PS blocking stores → `COMPLETED_NO_WEDGE ... 16.890s`, `a2l=0`.
- ZDMA `--selftest` (DDR→DDR) initially FAILED with `TOTAL_BYTE=0`; root cause measured as Linux
  runtime PM clock-gating the channel (`power/runtime_status=suspended`); after
  `echo on > /sys/devices/platform/axi/ffa80000.dma-controller/power/control` → **SELFTEST PASS** (dst==src,
  which also demonstrates no SMMU remap). Induce was run only AFTER that gate passed.

## 7. The OPEN QUESTION
**What holds `ahb_sub_hreadyout` low when `s_axi_awready` is high and the a2l window is neither full
nor starved of ACKs — and, since TL-037 IS in this build, why is the hang still unbounded at the time
of capture?** Specifically: did TL-037's terminal timeout (a) never arm, (b) arm and fire before the
capture window opened and the ZDMA immediately re-wedged it, or (c) arm but never reach its threshold?

### CRITICAL LIMITATIONS OF THIS CAPTURE (do not over-read it)
1. **The window is 163.8 us of a wedge that persisted for seconds**, and was force-captured LATE
   (~1–2 min after induction, on the `/tmp/do_capture` handshake). It shows **steady state, NOT onset.**
   Nothing here can say what happened at the moment the hold began.
2. The edge trigger **did not fire** (`TRIGGERED=0`) — expected, since its condition
   (`awvalid & ~awready`) never occurs. All data is from the **forced** capture.
3. **NOT PROBED — and these are exactly the TL-037-family signals:** `wr_hold_r`, `synth_b_pending`,
   `sub_err1_r`/`sub_err2_r`, `xhb_sub_hreadyout_raw` (the rank-6 raw term), `pipe_valid_r`,
   `sub_wr_os_ctr`, `write_broken`/`pending_broken_b_resp`. Their state during this wedge is UNKNOWN.
4. Occupancy capping at 7 (never 8) is measured; its CAUSE is not. Peer analysis states
   `sub_wr_os_ctr` is a passive saturating monitor, not an admission gate (`tidelink_top.sv:1592`,
   inc/dec :1787-1788, reads at :1768/:1818/:1868-1870/:1999) — so the cap's origin is OPEN
   (XHB500-internal AW-outstanding limit is an unverified candidate).

## 8. Known-relevant RTL anchors
- `src/rtl/tidelink_top.sv:1654,:1671-1672,:1704,:1988` — TL-037 terminal-timeout fix + `sub_err1_r` 2-cycle ERROR
- `src/rtl/tidelink_top.sv:1592,:1787-1788,:1768,:1818,:1868-1870,:1999` — `sub_wr_os_ctr` and its readers
- `src/rtl/tidelink_top.sv:~1909` — the `ahb_sub_hreadyout` override mux (rank5 `wr_hold_r` / rank6 raw)
- `src/rtl/tidelink_top.sv:2882` — `s_axi_awready` driver
- XHB500 `core_resp.sv:181-183` (SEQ_NSEQ forces hreadyout=0), `core_wdata.sv:253-255` (`write_broken_next`)

---

## 9. POST-SUBMISSION CORRECTION (2026-08-19, measured from the built RTL) — READ THIS FIRST

**The capture window is structurally too short to observe the backstops at all. Section 7's phrasing
("why is the hang still unbounded at the time of capture") is NOT supported by this capture, and is withdrawn.**

Measured from the built source (`src/rtl/tidelink_top.sv:1499,:1508`):
- `SUB_STALL_TIMEOUT_LOG2       = 16` → `sub_stall_expired` fires after 2^16 = **65536 hclk = 2620.3 us**
- `SUB_OUTSTANDING_TIMEOUT_LOG2 = 16` → `sub_osr_expired`   fires after 2^16 = **65536 hclk = 2620.3 us**
- **ILA window = 4096 samples @ 25.011 MHz = 163.8 us = 1/16th of ONE backstop period.**

So `ahb_sub_hreadyout = 0` across all 4096 samples is **fully consistent with a backstop that is working
correctly and simply had not reached its threshold within the observed window.** This capture can neither
confirm nor refute that TL-037 or the synth-B drain fired. Any claim about backstop behaviour from this
data is unsupported.

**What remains SOLID from this capture (window-independent, because these are steady-state levels):**
- `s_axi_awready = 1` and `a2l_full = 0` with the ACK pointer advancing → **H1 refuted** as this wedge's cause.
- `swi_enable = 1`, `enable_app_clk_demet_io_out = 1` → **H2 refuted**.
- `state` ∈ {4,5}, `socl_l7_wdog_cnt = 0` → **state-7/watchdog path refuted**.
- `dbg_tx_hreadyout = 1` → sideband/FCSM_6 path not involved.
- die_b idle/healthy throughout.
- The hold is on the **`ahb_sub`/XHB500 side**, downstream of a healthy AW handshake.

**Still genuinely open (and NOT answered by this capture):** the DMA remained stuck for *seconds*
(≫ many 2.62 ms backstop periods) yet made no progress. So either a backstop fires and does not
unstick this traffic class, or its fire condition is never met. Distinguishing these needs new data.

### Backstop arm conditions (traced in the built RTL, for the next experiment)
- `sub_wr_stuck_fire = (sub_osr_expired | sub_stall_expired) & (sub_wr_os_ctr != 3'd0)`  (`:1937-1938`)
  → sets `synth_b_pending`, which injects a synthetic **OKAY** B and drains until `sub_wr_os_ctr <= 1` (`:1945,:1950,:1953-1954`).
- TL-037 ERROR requires the **complementary** case: `sub_mst_dphase_r && (sub_wr_os_ctr == 3'd0) && !synth_b_pending` (`:1654+`).
  (Per peer RTL read: TL-037 is deliberately the `os_ctr == 0` backstop — a posted burst with several
  writes counted outstanding is the synth-B drain's territory, not TL-037's. TL-037 not firing here is
  therefore expected-by-design, **not** evidence of a defect.)
- Counter gating: `sub_ext_stalled = (sub_stall_fill || sub_stall_busy) && !sub_err1_r && !sub_err2_r` (`:1557`),
  where `sub_stall_busy = !xhb_sub_hreadyout_raw` (`:1551`). The counter **re-zeroes on any completed beat**
  (`:1642-1643`) — so an intermittently-progressing stream can hold it off indefinitely.

### RECOMMENDED NEXT EXPERIMENT (cheap, decisive — makes the mechanism fit the instrument)
1. **Shrink the timeout in a debug bitstream.** Both constants are already `ifdef`-overridable
   (`:1494-1508`): build with `TIDELINK_SUB_STALL_TIMEOUT_LOG2=10` / `TIDELINK_SUB_OUTSTANDING_TIMEOUT_LOG2=10`
   → fire every 2^10 hclk = **41 us**, i.e. **~4 complete fire cycles inside the existing 163.8 us window.**
   This converts an unobservable mechanism into a directly observable one with no ILA depth change.
2. **Probe the backstop family** (absent from this build): `xhb_sub_hreadyout_raw`, `wr_hold_r`,
   `synth_b_pending`, `sub_err1_r`, `sub_err2_r`, `sub_wr_os_ctr[2:0]`, `sub_mst_dphase_r`, `sub_rd_os_r`,
   `sub_stall_ctr_r[MSB]`, and XHB500 `write_broken`/`pending_broken_b_resp`.
3. **Trigger on the fire, not the symptom:** arm on `synth_b_pending` rising (or `sub_err1_r` rising) with
   ~1/2 pre-trigger, so the window brackets the backstop event and its aftermath — does the bus release,
   and does the ZDMA resume or immediately re-wedge?
4. Keep the ZDMA induction identical (ADMA ch0, write-only, AWLEN=0, 65536 B) so the traffic class is
   unchanged, and remember `power/control=on` before any DMA run.

---

## 10. FINDING B (independent of the capture) — BOTH local backstops are aggregate-progress timers,
## so a partially-draining stream starves them structurally

Raised by the tidelink session and **independently verified here against the built RTL**. This is a
*static RTL* finding — it needs no capture, and it is separate from the TL-037 scope note in §9.

Both of `tidelink_top`'s local backstops reset on **ANY** completion in the outstanding set, with **no
transaction identity and no per-transaction age**:

| backstop | reset condition | identity-aware? |
|---|---|---|
| per-beat stall (`sub_stall_ctr_r`) | `if (!sub_ext_stalled) sub_stall_ctr_r <= '0;` (`:1642-43`), and `sub_stall_busy = !xhb_sub_hreadyout_raw` (`:1551`) — i.e. **any** beat completing drives raw high and re-zeroes it | **NO** |
| I5 outstanding-response (`sub_osr_ctr_r`) | `if (!sub_axi_outstanding \|\| sub_axi_progress) sub_osr_ctr_r <= '0;` (`:1726-27`) where `sub_axi_progress = sub_r_done \| sub_b_done` (`:1582`) — a bare OR of **any** B or R handshake | **NO** |

`sub_r_done`/`sub_b_done` (`:1579-80`) carry no ID comparison, so neither timer can distinguish
"the stream is healthy" from "one specific item has been stuck for seconds while other items keep retiring."

**Consequence:** a stream that drains *intermittently* holds BOTH counters below threshold indefinitely.
Since `sub_wr_stuck_fire = (sub_osr_expired | sub_stall_expired) & (sub_wr_os_ctr != 0)` (`:1937-38`),
starving both expiries also **disables the synth-B drain** — so the entire local-backstop family
(TL-037's terminal timeout AND the synth-B/I5 drain) shares one starvation mode.

This matches the observed rig behaviour: 1026 beats landed, ~7000 still queued, stuck for **seconds**
(≫ many 2620 us periods) with no recovery — consistent with timers repeatedly re-zeroed by partial progress.
**Status: structurally established in RTL; NOT yet proven to be the operative cause of this wedge**
(that is what the §9 debug-bitstream experiment is for — a `sub_stall_ctr_r` that visibly re-zeroes
instead of climbing would be the smoking gun).

**Fix direction (design-level, not threshold tuning):** age the *oldest outstanding transaction*
(per-ID age/timestamp, or a "no progress on the OLDEST item" watchdog) rather than resetting a shared
timer on aggregate progress. Raising `*_TIMEOUT_LOG2` does **not** fix this — the counters never reach
any threshold, however large.
