# RTL proposal — auto-arm the deskew SYNC anchor at end of bring-up

**Goal:** eliminate the manual host `force_always` pulse that the eth-chiplet currently
needs after bring-up to make cross-die data cross. Today the sequence is
`bringup_pair_release.sh` → **host writes R8 `0x2E03_2100`=`0x1C` on both dies, then `0x00`**
→ data flows. This proposal folds that pulse into the controller so it happens
automatically once the FC link is up.

## Why it's needed (root cause, silicon-confirmed 2026-08-03)
After bring-up the FC reaches LINK_DATA (fcsm=4) but the deskew corrector is **not
anchored**: `EPOCH_STATUS 0x2140 bit0 (reanchored)=0` on both dies, R8=0 (no SYNC beacon).
We ship `EPOCH_ANCHOR_EN=0 ⇒ SYNC_REANCHOR_EN=1`, which only re-anchors on a live SYNC
beacon. The winscan FSM's own anchor gate (`WS_FINALIZE`, holds `winscan_done` until
`reanchored=1`) fires **during the scan — before both dies are fully up — so it times out
and releases** (`ws_anchor_timeout_q`). Post-scan nothing emits SYNC, so `reanchored` stays
0, cross-die words never reassemble, the peer-write never lands / no B returns, and the
initiator hangs. A manual `force_always` burst *after* fcsm=4 anchors it (`reanchored 0→1`,
**latches**) and data then crosses byte-exact (300+200-beat soaks clean).

## The change — a one-shot post-link-up SYNC burst
`src/rtl/local_overrides/axi_chiplet_controller.sv`. Gated by a new parameter (default OFF ⇒
bit-identical everywhere except where opted in — same pattern as `SELF_ARM_TRAIN_EN`).

### 1. New parameter, threaded like SELF_ARM_TRAIN_EN
```verilog
// axi_chiplet_controller.sv port list
parameter bit AUTO_ANCHOR_EN = 1'b0,   // eth-chiplet: pulse SYNC once at link-up to
                                       // latch the deskew re-anchor (nego_en=0 path)
```
`tidelink_top.sv` forwards it to the controller instance; `nanosoc_eth_chiplet.sv:609`
sets `.AUTO_ANCHOR_EN(1'b1)` alongside the existing `.SELF_ARM_TRAIN_EN(1'b1)`.

### 2. The auto-anchor one-shot (place near the autonomy-retire block, ~:4753)
```verilog
localparam [15:0] ANCHOR_DWELL = 16'd256;   // link-stable cycles at fcsm=4 before pulsing
localparam [15:0] ANCHOR_LEN   = 16'd4096;  // SYNC-burst width @25MHz apb_clk (~164us) — TUNE

reg        auto_anchor_pulse_q;   // ORs into the PHY sync ports while high
reg        auto_anchor_done_q;    // sticky one-shot per training episode
reg [15:0] auto_anchor_dwell_q, auto_anchor_len_q;

always_ff @(posedge apb_clk or negedge poresetn) begin
  if (!poresetn) begin
    auto_anchor_pulse_q<=0; auto_anchor_done_q<=0; auto_anchor_dwell_q<=0; auto_anchor_len_q<=0;
  end else if (swi_training_mode_rise) begin       // re-arm on every fresh episode
    auto_anchor_pulse_q<=0; auto_anchor_done_q<=0; auto_anchor_dwell_q<=0; auto_anchor_len_q<=0;
  end else if (AUTO_ANCHOR_EN && !auto_anchor_done_q && !swi_training_mode_r) begin
    if (ws_anchor_q) begin
      auto_anchor_done_q  <= 1'b1;                  // already anchored — nothing to do
    end else if (sync_obs_fcsm_state_1 == 3'd4) begin
      if (auto_anchor_dwell_q < ANCHOR_DWELL)       auto_anchor_dwell_q <= auto_anchor_dwell_q + 1;
      else if (auto_anchor_len_q < ANCHOR_LEN) begin
        auto_anchor_pulse_q <= 1'b1;                // emit SYNC burst (insert_en+force_always+robust)
        auto_anchor_len_q   <= auto_anchor_len_q + 1;
      end else begin
        auto_anchor_pulse_q <= 1'b0;                // release — the anchor latches
        auto_anchor_done_q  <= 1'b1;
      end
    end else begin
      auto_anchor_dwell_q <= 16'd0;                 // FC dropped out of LINK_DATA — restart dwell
    end
  end
end
```

### 3. OR it into the three PHY sync ports (:6455/:6461/:6470)
```verilog
.swi_sync_insert_en_in     (swi_sync_insert_en_r    | winscan_force_sync | ws_serve_active_r | auto_anchor_pulse_q),
.swi_sync_force_always_in  (swi_sync_force_always_r | winscan_force_sync | ws_serve_active_r | auto_anchor_pulse_q),
.swi_sync_robust_detect_in (swi_sync_robust_detect_r| winscan_force_sync | ws_serve_active_r | auto_anchor_pulse_q),
```

## Safety / review points (need your eyes — this is your IP)
1. **`force_always` is a word-deleter over live data** (the R4/B→A corruptor you documented).
   The pulse fires on `fcsm==4` after `swi_training_mode` is released but **before the app's
   first cross-die transfer**. On the eth-chiplet the M0 cores gate their first D2D write on
   link-up, so there's a window — but it is a **race**. Options: (a) also gate the pulse on
   "no TX activity" (`~ll_app.sop` for the burst), or (b) keep the app's first write behind a
   `reanchored`-poll in firmware. Recommend (a) for robustness.
2. **`ANCHOR_LEN` tuning:** the manual host pulse held ~0.4 s; the deskew actually anchors on
   the first clean bilateral SYNC exchange, so a few thousand apb_clk cycles should suffice —
   but this wants a silicon sweep (start generous, shrink).
3. **One-shot re-arm** on `swi_training_mode_rise` mirrors the existing per-episode flags, so a
   retrain re-anchors.
4. **Zero-regression:** `AUTO_ANCHOR_EN` default 0 ⇒ the whole block constant-folds away; only
   the eth-chiplet instantiation opts in. KR260 bare-link / Z2 images untouched.

## Verification plan
- Sim: extend `cocotb/tidelink_top_pair_v2` — assert `reanchored` rises and `test_03` (S→M
  data) passes at fcsm=4 **without** any host R8 write, with `AUTO_ANCHOR_EN=1`; default
  (=0) path bit-identical.
- HW: build the eth-chiplet with `AUTO_ANCHOR_EN=1`, deploy, `bringup_pair_release.sh`, then
  the cross-die soak **with no manual `force_sync` step** — expect `reanchored=1` and clean
  soak (the manual-pulse result this replaces).

Host workaround meanwhile (works today): `force_sync.py arm` (R8=0x1C) → wait 0.4s →
`force_sync.py release` (R8=0) on both dies, after bring-up, before data.
