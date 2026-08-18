# TideLink AW write-wedge — periodic re-ACK + data-safety guard: DESIGN

**Status:** design only. No shared RTL modified, nothing committed, nothing pushed, no hardware touched.
**Date:** 2026-08-18. **Scope dir:** `imp/hw_gate/wedge_timeout_design/` (mine alone).

**Isolation proof.** `git -C tidelink status --porcelain -- src/rtl/` is empty.
`tidelink/src/rtl/tidelink_top.sv` md5 `d88029d98a660caeba62acbbae0d037b` — the
same vintage `imp/hw_gate/wedge_downstream/ASSESSMENT.md` pinned, so the two
documents describe the same RTL.

> ⚠ **This document is gitignored.** `.gitignore:259` ignores `/imp/`, so this
> design, the downstream `ASSESSMENT.md`, and the earlier TL-042 prototype are
> all **host-only and would not be collected by any submission bundle**. If
> either deliverable here is landed, its design record needs a home outside
> `imp/` (e.g. `docs/`) or it will not survive.

**Revision history of this document** — it has been re-framed twice, and both
re-framings came from other workstreams' measurements rather than from me:

1. Originally: "design a timeout, the link hangs forever."
2. Then `imp/hw_gate/wedge_downstream/ASSESSMENT.md` proved **liveness is already
   bounded** by TL-037, and that **restoring `awready` silently delivers wrong
   data**.
3. Now the root cause is **found and proven**: a latching defect in the Fix E
   periodic re-ACK. A generic timeout is no longer the right answer.

This version delivers the two pieces requested, kept strictly separable:

* **Deliverable 1 — make Fix E genuinely periodic** (§4). The in-protocol fix.
* **Deliverable 2 — the data-safety guard** (§5). An independently severe defect.

**Before either: §3 is a blocking finding.** Fix E does not exist in the shipping
ASIC netlist at all. Deliverable 1 cannot reach silicon on the AXI path as the
flists stand. That has to be resolved before this is called a silicon fix.

---

## 1. The closed loop, verified

`send_ack_req` has exactly three sources — verified at
`tidelink/src/rtl/local_overrides/WlinkGenericFCSM.v:1002-1016`:

```verilog
always @(posedge io_tx_clk or posedge io_tx_reset) begin
  if (io_tx_reset)              send_ack_req <= 1'h0;
  else if (_ack_seen_before_T)  send_ack_req <= send_ack_req | (isExpPacket | l2a_fifo_raddr_txclk_update);
  else if (state == 3'h1)       send_ack_req <= send_ack_req | (isExpPacket | l2a_fifo_raddr_txclk_update);
  else if (state == 3'h2)       send_ack_req <= send_ack_req | (isExpPacket | l2a_fifo_raddr_txclk_update);
  else if (state == 3'h3)       send_ack_req <= send_ack_req | (isExpPacket | l2a_fifo_raddr_txclk_update);
  else                          send_ack_req <= _GEN_178 | socl_reack_rearm; // SoC Labs Fix E re-ACK re-arm
end
```

There is **no free-running ACK heartbeat**. The loop closes on itself: ACKs stop →
the a2l window fills (`WlinkGenericFCReplayV2_1.v:75`) → `app_ready` drops (`:121`)
→ this die stops emitting → the peer sees no new data → `isExpPacket` never
asserts → the peer never ACKs again. The first two sources die exactly when they
are needed. `socl_reack_rearm` is the only source that is supposed to survive —
and it is the one that latches off.

---

## 2. The root cause, verified line by line

### 2.1 Defect A — `socl_reack_fired` can never clear

`WlinkGenericFCSM.v:1082-1091`:

```verilog
// SoC Labs (Fix E): "refresh fired this idle window" sticky (io_tx_clk).
always @(posedge io_tx_clk or posedge io_tx_reset) begin
  if (io_tx_reset)                                    socl_reack_fired <= 1'h0;
  else if (socl_reack_fresh_data | (state < 3'h4))    socl_reack_fired <= 1'h0;
  else if (socl_reack_rearm)                          socl_reack_fired <= 1'h1;
end
```

with `socl_reack_fresh_data = isExpPacket | l2a_fifo_raddr_txclk_update` (`:343`).
During the wedge both terms are dead, and the FSM sits in state 4, so
`state < 3'h4` is false. **Both clear terms are unreachable. Fix E fires once,
latches, and is permanently disarmed.** It was specified as periodic
(`WlinkGenericFCSM_6.v:666-671`: *"Periodically RE-EMIT the cumulative last_good
ACK…"*); it is implemented as a hard one-shot.

### 2.2 The counter compounds it — it saturates, it does not wrap

`WlinkGenericFCSM.v:1072-1081`:

```verilog
if (io_tx_reset)                                                  socl_reack_idle_cnt <= 16'h0;
else if (socl_reack_fresh_data | (state != 3'h4 & state != 3'h5)) socl_reack_idle_cnt <= 16'h0;
else if (socl_reack_idle_cnt != SOCL_REACK_THRESHOLD)             socl_reack_idle_cnt <= socl_reack_idle_cnt + 16'h1;
```

The final `else if` **saturates** at `SOCL_REACK_THRESHOLD`. So during the wedge
the counter parks at 256 and `socl_reack_rearm` (`:364-370`) is left with only
`~socl_reack_fired` varying — and that is stuck at 1. This matters for the fix:
§4.2 shows that the obvious one-line fix interacts badly with the saturation.

### 2.3 Defect B — the `have_rx` arming hole is worse than "bring-up only"

`:342` `wire socl_reack_have_rx = (last_good_pkt_from_rx != 8'h0);`

and the register it tests, `:1092-1100`:

```verilog
if (io_tx_reset)            last_good_pkt_from_rx <= 8'h0;
else if (_fe_rx_ptr_in_T)   last_good_pkt_from_rx <= 8'h0;      // ~en_ff2_tx_demet_io_out
else if (isExpPacket)       last_good_pkt_from_rx <= ack_nack_fifo_io_rdata[7:0];
```

It takes the **received packet number verbatim**. So it is 0 (i) before the first
packet, (ii) whenever the enable demet drops, and (iii) **whenever the peer's
8-bit packet numbering is itself at 0**. Since packet numbers are 8-bit, case
(iii) recurs — Fix E is disarmed for a window once per numbering lap, not only at
bring-up. *(I did not confirm whether the peer's `exp_pkt_num` skips 0 on wrap; if
it does, case (iii) does not occur. §8.3.)*

Either way the predicate is testing the wrong thing: the intent is *"this receiver
has accepted in-order data it can re-ACK"*, which is a **latched fact**, not a
property of the current packet number.

### 2.4 Present in all six variants

```
                       local_overrides   deps/
WlinkGenericFCSM.v            21           0
WlinkGenericFCSM_1.v          21           0
WlinkGenericFCSM_2.v          21           0
WlinkGenericFCSM_3.v          21           0
WlinkGenericFCSM_4.v          21           0
WlinkGenericFCSM_6.v          30           0
```
(`grep -c socl_reack`, run in `tidelink/`.) Both defects are in all six overrides.
**The right-hand column is §3.**

---

## 3. BLOCKING FINDING — Fix E is not in the shipping ASIC netlist

`grep -c socl_reack` over `deps/axi-chiplet-controller/logical/wlink/` returns **0
for all six FCSM variants**. Fix E is a SoC Labs addition that exists only in the
`local_overrides/` copies. And the shipping tapeout flist sources five of the six
from `deps/`:

```
tidelink/flists/tidelink_top_full_asic_v2.flist
  :315  deps/.../WlinkGenericFCSM.v      <- wlink_axiawFC   (AW)   ** the wedged node **
  :316  deps/.../WlinkGenericFCSM_1.v    <- wlink_axiwFC    (W)
  :317  deps/.../WlinkGenericFCSM_2.v    <- wlink_axibFC    (B)
  :318  deps/.../WlinkGenericFCSM_3.v    <- wlink_axiarFC   (AR)
  :319  deps/.../WlinkGenericFCSM_4.v    <- wlink_axirFC    (R)
  :321  src/rtl/local_overrides/WlinkGenericFCSM_6.v        <- TideLink data node
```

(node identities from `deps/.../AXI4ToWlink.v:529,567,605,643,681` and
`local_overrides/TideLinkToWlink.v:86`.)

> **Therefore: on the tapeout netlist there is no periodic re-ACK on any of the
> five AXI flow-control nodes — including `wlink_axiawFC`, the node this wedge
> is on. Making Fix E periodic fixes a mechanism that is absent from silicon on
> the path that needs it.** Only `_6`, the TideLink data node, gets the fix.

And the re-point is explicitly blocked. `tidelink_top_full_asic_v2.flist:309-314`:

> *"FCSM 0-4 HELD on deps for the TAPEOUT netlist … Per decision 2026-07-29 these
> ASIC/tapeout flists stay on the recovery-stripped deps copies until a silicon
> ILA confirms the fix; re-point to local_overrides (as fpga_v2) ONLY after that
> ratification."*

because the local copies caused a **link-down** regression on the FPGA
(`docs/I1_FCSM_BRINGUP_REGRESSION.md`: `cr_seen=0 crack_seen=0`, both dies).

**What this means in practice**

* Deliverable 1 is correct and worth landing — but as it stands it is an
  **FPGA-path fix plus the `_6` data node**, not a silicon fix for the AXI wedge.
* Calling it a silicon fix requires re-pointing FCSM 0-4 in the ASIC flist, which
  drags in the *entire* SoC Labs hardening set (L6/L7 gates, state-7 watchdog,
  TL-033, Fix E) — the set that caused the link-down regression. That is a much
  larger change than the one-bit fix, with its own gate.
* The flist is under human-sign-off change control
  (`tidelink/scripts/git_merge_flist.sh:118-119`).
* This is also why the observability item in the Appendix still has value: it
  lives in `tidelink_top.sv`, so it is the **only** part of this workstream that
  reaches silicon as the flists stand.

**Also carried forward, per instruction:** the root-cause sims ran against
`tidelink_fpga_v2_fcsm_local.flist`, not the shipping ASIC V2 combination.
Everything in §4 is therefore **FPGA-config-proven only** and needs an
ASIC-mirror re-run (`ASIC_MIRROR=1` in
`cocotb/tidelink_axi_datanode_recovery/Makefile:47-51`) before being called
silicon-exact — and on that mirror Fix E is absent, so the expected result there
is *"still wedged"*, which is itself the demonstration of §3.

---

## 4. Deliverable 1 — make Fix E genuinely periodic

### 4.1 Requirement

One re-ACK emission per `SOCL_REACK_THRESHOLD` idle window, indefinitely, for as
long as the node is in a data state with no fresh RX activity — instead of exactly
one ever.

### 4.2 Shape (b) — "add the counter term to the clear" — REJECT AS STATED

Adding `| (socl_reack_idle_cnt == SOCL_REACK_THRESHOLD)` to the `socl_reack_fired`
clear, **without** changing the counter, does not give a periodic re-ACK. Because
the counter **saturates** at `SOCL_REACK_THRESHOLD` (§2.2) rather than wrapping,
that term is true *every cycle* once reached. So:

* `socl_reack_fired` is held at 0 permanently;
* `socl_reack_rearm` then asserts whenever its other terms allow — throttled only
  by its own `~send_ack_req` term and the ACK emit loop;
* result: a **continuous ACK stream**, not a periodic one, on **every idle link**,
  healthy or wedged (the counter's clear condition `socl_reack_fresh_data |
  (state != 4 & state != 5)` means a genuinely idle healthy link also parks at
  threshold).

That is a behaviour change on the common case to fix the rare one. Reject.

### 4.3 Shape (a) — wrap the counter — RECOMMENDED

Two edits, both inside the existing Fix E blocks, no new module, no port change.

```verilog
// (1) counter: WRAP instead of saturate, so `== THRESHOLD` is a one-cycle tick.
//     WlinkGenericFCSM.v:1072-1081
if (io_tx_reset)                                                  socl_reack_idle_cnt <= 16'h0;
else if (socl_reack_fresh_data | (state != 3'h4 & state != 3'h5)) socl_reack_idle_cnt <= 16'h0;
else if (socl_reack_idle_cnt != SOCL_REACK_THRESHOLD)             socl_reack_idle_cnt <= socl_reack_idle_cnt + 16'h1;
else                                                              socl_reack_idle_cnt <= 16'h0;   // NEW: wrap

// (2) fired: also clear on the tick.  WlinkGenericFCSM.v:1082-1091
if (io_tx_reset)                                                  socl_reack_fired <= 1'h0;
else if (socl_reack_fresh_data | (state < 3'h4)
         | (socl_reack_idle_cnt == SOCL_REACK_THRESHOLD))         socl_reack_fired <= 1'h0;   // NEW term
else if (socl_reack_rearm)                                        socl_reack_fired <= 1'h1;
```

**Why this is periodic and not continuous.** With the wrap, `idle_cnt ==
SOCL_REACK_THRESHOLD` is true for exactly **one cycle per window**. On that cycle
the clear arm of `socl_reack_fired` wins over the set arm (it is earlier in the
`else if` chain), so `fired` is 0 entering the next window; `socl_reack_rearm`
also requires `idle_cnt == SOCL_REACK_THRESHOLD`, so it too is a one-cycle pulse
per window. One arm, one ACK, one window.

**⚠ An ordering subtlety I could not resolve on paper, and it must be simulated
before this is believed.** `socl_reack_rearm` and the new clear term are both
gated on `idle_cnt == THRESHOLD` in the *same* cycle, while `socl_reack_rearm`
also reads `~socl_reack_fired` — the *current*, not the next, value. If `fired`
is still 1 on the tick cycle (set during the previous window), `rearm` is
suppressed that cycle, `fired` clears at the end of it, and the counter has
already wrapped to 0 — so the arm is missed and the period doubles, or, if the
same race repeats, never fires again. **Two safe resolutions, either of which
removes the race:**

* **(a1)** clear `fired` one cycle early, at `idle_cnt == SOCL_REACK_THRESHOLD -
  16'h1`, so `fired` is already 0 when the tick arrives. Minimal, keeps `fired`'s
  meaning intact. **This is my recommendation.**
* **(a2)** drop `~socl_reack_fired` from `socl_reack_rearm` entirely and let the
  wrap provide the one-shot. Fewer terms, but it retires a signal and changes
  `rearm`'s expression, so it is a larger diff for review.

I have **not** simulated either. §7 test 3 is written specifically to
discriminate them, and it must be run before this is landed — the whole point of
the defect being a latch is that latch-ordering is where this family of bugs
lives.

### 4.4 Closing the `have_rx` hole — a dedicated latched flag

Replace the packet-number test with the fact it was meant to express. A **new
dedicated 1-bit register** (in preference to reusing anything):

```verilog
// NEW: "this receiver has accepted at least one in-order packet since reset",
// which is what Fix E's arming condition was always trying to express. Set once
// on the first isExpPacket; cleared only by reset and by the same enable-demet
// term that zeroes last_good_pkt_from_rx, so it can never claim a re-ACK is
// meaningful across an enable drop.
reg socl_reack_rx_seen;
always @(posedge io_tx_clk or posedge io_tx_reset) begin
  if (io_tx_reset)           socl_reack_rx_seen <= 1'h0;
  else if (_fe_rx_ptr_in_T)  socl_reack_rx_seen <= 1'h0;   // same clear as last_good_pkt_from_rx
  else if (isExpPacket)      socl_reack_rx_seen <= 1'h1;
end

wire socl_reack_have_rx = socl_reack_rx_seen;   // was: (last_good_pkt_from_rx != 8'h0)
```

This closes the bring-up hole and, if packet numbers do reach 0 (§2.3), the
recurring hole too. It cannot make Fix E arm when it should not: it is strictly
implied by the old condition being true at least once.

### 4.5 Threshold — keep `16'h0100`, and here is why it cannot fire when healthy

**No change to the value is proposed.** The defect is periodicity, not the
threshold, and re-tuning a shipped constant in the same commit would confound the
gate.

The safety argument, with the as-built numbers (provenance in §6):

* The counter's clear term is `socl_reack_fresh_data | (state != 3'h4 & state !=
  3'h5)`. So it counts **only** while the node is in a data state **and** nothing
  has been received and no l2a read pointer has moved. **Under any load at all it
  is reset continuously and can never reach threshold.** This is the same
  clear-on-progress discipline as `sub_stall_ctr_r` (`tidelink_top.sv:1707-1709`)
  and `dbg_a2l_stall_cnt_q` (`axi_chiplet_controller.sv:2140-2145`).
* Margin over the healthy ACK cadence: the RTL's own figure is *"~tens of
  io_tx_clk cycles between data"* (`WlinkGenericFCSM_6.v:196`), so 256 is roughly
  **6–25×** the healthy inter-ACK gap.
* Absolute period on the as-built part: `io_tx_clk` = D2D bit clock ÷ 16 = 160 ns
  (`tidelink_constraints.sdc:478-479`; bit clock = `EXTCLK` = 10 ns at `:38-39`).
  256 × 160 ns = **41 µs**, i.e. ~24 kHz. Against a 6.25 MW/s word rate that is a
  **0.4 % duty** of single-word ACK traffic on an otherwise idle link — the cost
  of periodicity, and it is negligible.
* At the slowest divider ratio (`/16`) the period becomes 655 µs; the counter is
  in `io_tx_clk` so it **self-scales** and needs no correction. (Contrast the
  wrapper's `hclk`-counted budgets, which do not — Appendix.)

### 4.6 Every signal Deliverable 1 touches

| Signal | Change | What else depends on it | Why this is safe |
|---|---|---|---|
| `socl_reack_idle_cnt` | saturate → wrap | only `socl_reack_rearm` (`:365`) and the new clear term | sole consumers are inside Fix E; grep-confirmed no other reader |
| `socl_reack_fired` | one new clear term (a1: at `THRESHOLD-1`) | only `socl_reack_rearm` (`:367`) | same |
| `socl_reack_have_rx` | re-expressed over a new latched flag | only `socl_reack_rearm` (`:366`) | strictly implied by the old condition having been true once |
| `socl_reack_rx_seen` | **NEW register** | nothing | new dedicated signal, no fan-in to anything existing |
| `socl_reack_rearm` | **unchanged** (shape a1) | `send_ack_req` (`:1015`) | unchanged expression; still `& ~send_nack_req & ~send_ack_req & (state >= 3'h4)` |
| `send_ack_req` | **unchanged logic**, fires more often | the state-4→6 ACK emit path | the *only* behavioural delta: an idle link emits one ACK per 41 µs instead of one ever |
| `synth_b_pending` | **NOT TOUCHED** | `wr_hold_clr` (TL-002/TL-043), `s_axi_bresp` OKAY mux `:2057`, hreadyout/hresp masks, TL-037 gate | not referenced. Asserting it is what got TL-042 v1 rejected on hardware (`tidelink_top.sv:1758-1763`) |
| `socl_l7_wdog_cnt` / TL-033 | **NOT TOUCHED** | state-7 backstop | separate mechanism, separate state |
| module port lists | **UNCHANGED** | LEC comparison boundary | preserves the house rule at `tidelink_top_full_asic_v2.flist:272-273` (*"byte-identical … so the LEC comparison boundary is unchanged"*) |

No new ports, no new instances, no flist change — so Deliverable 1 does not fork
the flist chain (`tidelink_top_full_asic_v2.flist:167-174`).

---

## 5. Deliverable 2 — the data-safety guard

### 5.1 The defect (measured by the downstream workstream, not by me)

```
[stale] VERDICT: intended payload 0xd0d00042, delivered 0xbad0bad0, wstrb=0xf
```

Correct address, full byte strobes, answered OKAY.
`imp/hw_gate/wedge_downstream/ASSESSMENT.md §3.2-3.3`. Mechanism:

1. During the wedge `stall_writes = ~address_readyout` holds `wdata_in_valid`
   low, so XHB500 **never captures** the W payload; `write_data_valid` stays
   armed.
2. `wdata_in = {last, strb, hwdata}` reads a **live wire** —
   `tidelink_top.sv:2679 .hwdata(ahb_sub_hwdata)`, confirmed: the wrapper has no
   write-data register anywhere.
3. TL-037's `sub_err2_r` **outranks** `wr_hold_r` in the readyout mux
   (`tidelink_top.sv:2081-2087`, `sub_err2_r` at `:2082` above `wr_hold_r` at
   `:2085`), so the master is answered over the top of an engaged TL-002 hold and
   releases HWDATA.
4. When the link returns, the armed capture samples whatever the bus carries.

**This is why Deliverable 1 cannot land alone.** Deliverable 1's whole purpose is
to make `app_ready` come back — which is precisely the trigger.

### 5.2 Mechanism: register HWDATA in the wrapper

Preferred option (A) from `ASSESSMENT.md §5.1`: no vendor change, no mux change,
no `synth_b_pending`. It converts the defect into *correct* behaviour rather than
a safer failure.

### 5.3 THE TIMING REQUIREMENT — arm on the address phase, capture the NEXT cycle

`wr_hold_set = ext_is_nonseq & ahb_sub_hwrite & ~pipe_valid_r`
(`tidelink_top.sv:1996`) is **address-phase** recognition: `ext_is_nonseq =
ext_addr_phase & (ahb_sub_htrans == 2'b10)` (`:1528`). On standard AHB pipelining
the write data for that address appears in the **following** cycle and is held
while HREADY is low.

> **Sampling `ahb_sub_hwdata` in the same cycle as `wr_hold_set` captures
> address-phase garbage — the previous transfer's data, or nothing.** The design
> must ARM on `wr_hold_set` and CAPTURE ON THE NEXT CYCLE. §7 test 6 is a
> mutation test that checks *which cycle* was captured, not merely that a capture
> happened.

```verilog
// ── DATA-SAFETY GUARD: hold the peer write's HWDATA across the wrapper's hold ──
// The wrapper drives u_xhb_sub.hwdata from a LIVE wire (:2679). If the master is
// answered while wr_hold_r is engaged -- which TL-037's sub_err2_r does, it
// outranks wr_hold_r at :2082 vs :2085 -- the master releases HWDATA while
// XHB500's write_data_valid is still armed, and the deferred sample takes
// whatever the bus then carries. Measured: intended 0xD0D0_0042, delivered
// 0xBAD0_BAD0 (imp/hw_gate/wedge_downstream/ASSESSMENT.md Sec 3.2).
//
// TIMING: wr_hold_set is the ADDRESS phase. AHB write data is on the bus the
// NEXT cycle. Arm here, capture there. Sampling on wr_hold_set itself captures
// address-phase garbage -- that is the mutation test in the bench.
logic                    hwdata_cap_arm_r;
logic [SYS_DATA_W-1:0]   hwdata_cap_r;
logic                    hwdata_cap_valid_r;

always_ff @(posedge hclk or negedge hresetn) begin
    if (!hresetn) begin
        hwdata_cap_arm_r   <= 1'b0;
        hwdata_cap_r       <= '0;
        hwdata_cap_valid_r <= 1'b0;
    end else begin
        hwdata_cap_arm_r <= wr_hold_set;               // ARM in the address phase
        if (hwdata_cap_arm_r) begin                    // CAPTURE in the data phase
            hwdata_cap_r       <= ahb_sub_hwdata;
            hwdata_cap_valid_r <= 1'b1;
        end
        if (wr_hold_clr) hwdata_cap_valid_r <= 1'b0;   // the W beat landed: release
    end
end

// Transparent when not holding: bit-identical to today on the healthy path.
wire [SYS_DATA_W-1:0] xhb_sub_hwdata = hwdata_cap_valid_r ? hwdata_cap_r
                                                          : ahb_sub_hwdata;
// and at :2679 change   .hwdata(ahb_sub_hwdata)   ->   .hwdata(xhb_sub_hwdata)
```

Prototype copy: `hwdata_hold_guard.sv` in this directory.

### 5.4 Every signal Deliverable 2 touches

| Signal | Use | What else depends on it | Why safe |
|---|---|---|---|
| `ahb_sub_hwdata` | **read**; re-driven **into XHB500 only** via a new mux | today wired straight to `u_xhb_sub.hwdata` `:2679` and nothing else | the top-level input port is unchanged; only the bridge's view is muxed, and it is transparent whenever `hwdata_cap_valid_r == 0` |
| `wr_hold_set` | **read** | sets `wr_hold_r` `:2022` | read-only; a read adds no fan-in |
| `wr_hold_clr` | **read** | clears `wr_hold_r` `:2021` | read-only. **Note it is TL-043's edge-qualified expression** (`:2010-2013`), deliberately equal to the `synth_b_pending` clear predicate at `:1999`. This guard **reads** it and must never redefine it — a change there is a two-site change |
| `hwdata_cap_arm_r`, `hwdata_cap_r`, `hwdata_cap_valid_r`, `xhb_sub_hwdata` | **NEW** | nothing | dedicated new signals |
| `synth_b_pending` | **NOT TOUCHED** | as §4.6 | not referenced |
| `sub_err1_r` / `sub_err2_r` and the `ahb_sub_hreadyout` mux | **NOT TOUCHED** | the 2-cycle ERROR sequencer; `sub_err2_r` outranks `wr_hold_r` | **no new rank is added to that mux** — TL-042 v2's own constraint 3. The guard fixes the *data*, not the *priority*, deliberately: re-ranking the mux would change TL-037's timing |
| `ahb_sub_w_beat_consumed_o` | **NOT TOUCHED** | `= s_axi_wvalid & s_axi_wready` `:638`; the chiplet's per-beat peer-write capture | the guard drives no `s_axi` signal, so the strobe is bit-identical. Must still be asserted cycle-by-cycle in the bench (§7 test 8) |
| XHB500 internals (`stall_writes`, `wdata_in_valid`, `write_data_valid`, `address_readyout`, `write_broken`) | **NOT TOUCHED** | vendor flow control | no vendor file copied or edited — the guard is entirely wrapper-side, so `$IP_LIBRARY_ROOT/**` and `deps/xhb500` are untouched and no flist changes |

### 5.5 Known limitation — bursts

`wr_hold_set` keys on `ext_is_nonseq`, which is NONSEQ only, so it pulses on the
**first** beat of a burst. The single register above is correct for the
single-beat case — which is the case the defect was measured on — and is **not
yet correct for a multi-beat INCR burst**, where each beat needs its own capture.
I am not proposing a burst design without a bench: `ahb_sub_w_beat_consumed_o`
(`:638`) is the natural per-beat qualifier, but wiring capture to it has to be
proven not to perturb it. **Open, and §7 test 7 is the gate.** Stating this
plainly matters: the prototype that preceded this work was also single-beat-only,
and that was the first item on its own "not covered" list.

---

## 6. Landing order and separability — answered explicitly

**They are separable, and they must be separate commits** (`CONTRIBUTING.md §4.4`:
*"A fix and its guard are separate commits, each gated on its own — AND the
combined state gets its own gate run before either is called done."*). But they
are **ordered**:

1. **Deliverable 2 (the guard) lands FIRST, alone, gated alone.** It is a
   standalone data-integrity fix: today's RTL already fails
   `test_today_upstream_recovery_delivers_stale_wdata` without any of my work.
2. **Deliverable 1 (periodic re-ACK) lands SECOND, gated alone.** It is the change
   that makes `app_ready` return, i.e. that arms the defect the guard stops.
3. **A third gate run on the combination**, before either is called done.

Landing 1 before 2 converts a bounded, reported SIGBUS into a silent wrong-data
write. That is the one ordering that must not happen.

---

## 7. What must be simulated

Nothing here has been run by me. **Build hygiene first:** this bench compiles into
`build/` as well as `sim_build*` — `rm -rf build sim_build*`, confirm
`recompiling module` in the log, and treat `up to date` on the simulator binary as
a **failed clean** (`CONTRIBUTING.md §4.1`).

**Deliverable 1 — periodic re-ACK**

| # | Test | Must show |
|---|---|---|
| 1 | **Control (red).** H1 repro, unfixed. | wedge holds; `socl_reack_fired` latched at 1; `socl_reack_idle_cnt` parked at `0x100`; `a2l_full=1 app_ready=0`. |
| 2 | **Fix (green).** Same stimulus, shape (a1). | `a2l_full 1→0`, `app_ready 0→1`, `a2l_link_addr` advances, writes flow. Red-to-green in one session on one build (`CONTRIBUTING §4.3`). |
| 3 | **Periodicity, ≥3 windows — the test that discriminates (a1) from the naive (a).** Hold the wedge and count re-ACK emissions over ≥3 × `SOCL_REACK_THRESHOLD`. | **exactly one** `socl_reack_rearm` pulse per window, at a constant period. Catches both failure modes of §4.3: the missed-arm race (period doubles or stops) and shape (b)'s continuous stream. |
| 4 | **No-fire under load.** Sustained traffic, healthy link. | `socl_reack_idle_cnt` never reaches threshold; zero re-ACK emissions. |
| 5 | **`have_rx` hole closed.** Force `last_good_pkt_from_rx` to 0 with `socl_reack_rx_seen` set, then wedge. | Fix E still arms. Control with the old predicate must **fail**. |

**Deliverable 2 — data-safety guard**

| # | Test | Must show |
|---|---|---|
| 6 | **Cycle-accurate capture — the mutation test the brief demands.** Drive a *distinct* value on `ahb_sub_hwdata` in the address cycle (`0xADDR_ADDR`) and the real payload (`0xD0D0_0042`) in the following data cycle. **Arm A:** a mutant that captures on `wr_hold_set` itself → must deliver `0xADDR_ADDR` and **FAIL**. **Arm B:** the +1-cycle design → delivers `0xD0D0_0042` and passes. | this asserts *which cycle* was captured, not merely that a capture occurred. |
| 7 | **Burst.** `hburst=INCR4` through the same sequence. | every beat correct, or none delivered. `ahb_sub_w_beat_consumed_o` bit-identical to control. **Expected to fail on the §5.5 design — that failure is the scope boundary, not a regression.** |
| 8 | **Non-interference, white-box.** Across the whole wedge assert `synth_b_pending`, `wr_hold_r`, `wr_hold_clr`, `wr_hold_drain_release`, `sub_wr_os_ctr`, `sub_err1_r/2_r`, `ahb_sub_w_beat_consumed_o` bit-identical to control. | zero divergence. This is the TL-042 v1 regression test. |
| 9 | **Healthy-path transparency.** No wedge, same stimulus. | byte-exact `0xD0D0_0042`; `hwdata_cap_valid_r` never asserts. |
| 10 | **Non-bufferable** (`hprot[2]=0`). | same as 6. |
| 11 | **Normal peer write after the guard has fired.** | byte-exact. |
| 12 | **Baseline reproduction.** `wedge_downstream`'s `test_today_upstream_recovery_delivers_stale_wdata`. | fails at `0xBAD0_BAD0` before the guard, passes after. |

**Combined, and the §3 question**

| # | Test | Must show |
|---|---|---|
| 13 | **Combination gate.** Both landed; full default `MODULE` set on a verified-clean rebuild; plus `test_tl002_wrhold_drain_guard.py` incl. its `TIDELINK_WR_HOLD_CLR_LEVEL_MUTANT` build. | green; mutant still fails (guard not made vacuous). Whoever lands runs it (`CONTRIBUTING §4.6`). |
| 14 | **ASIC-mirror re-run.** `ASIC_MIRROR=1` (`cocotb/tidelink_axi_datanode_recovery/Makefile:47-51`) = the shipping FCSM-on-`deps` combination. | **Deliverable 1 has no effect** (Fix E absent, §3) — and *that result is the deliverable*: it is the measurement that decides whether the ASIC flist must be re-pointed. Deliverable 2 must still pass, since it is wrapper-side. |
| 15 | **Elaboration of the shipping config**, `flists/tidelink_top_full_asic_v2.flist`. | elaborates. Neither deliverable adds a port. |

**Harness premises to declare** (`CONTRIBUTING §4.5`): the H1 stimulus `Force`s
`link_ack_update` **and** the `a2l_link_addr` register
(`test_h1_a2l_full_no_crc.py:127-137`); both bypass TL-027's window guard and
TL-032's revert rewind. The root-cause sims ran on
`tidelink_fpga_v2_fcsm_local.flist`, not the ASIC combination (§3). Deliverable 2
depends on `ahb_sub_hwdata` remaining otherwise unregistered (`:2679`) and on
`sub_err2_r` keeping its rank above `wr_hold_r` (`:2082` vs `:2085`) — if either
changes, re-run 6 and 8.

---

## 8. Risks and uncertainties

| Risk | Mitigation |
|---|---|
| Deliverable 1 lands before Deliverable 2 ⇒ silent wrong-data write | the ordering gate in §6 |
| The §4.3 latch-ordering race makes the re-ACK fire once per two windows, or not at all | test 3 discriminates; shape (a1) is chosen specifically to avoid it. **Not simulated by me** |
| Shape (b) taken as-is ⇒ continuous ACK on every idle link | §4.2; reject that shape |
| Burst writes not covered by the guard | §5.5 declared as a scope boundary; test 7 is the gate |
| Re-pointing FCSM 0-4 to make Deliverable 1 reach silicon re-introduces the I1 link-down regression | §3; that re-point is a separate decision with its own gate and human sign-off |

**Uncertainties, stated rather than papered over**

1. **§4.3 is unsimulated.** Two of the three shapes I analysed have subtle latch
   ordering hazards; I resolved them on paper, and paper is exactly what produced
   the original defect. Test 3 exists because I do not trust §4.3 without it.
2. **The `have_rx` recurrence (§2.3)** depends on whether the peer's `exp_pkt_num`
   ever presents 0. I did not confirm the wrap behaviour. If it skips 0, Defect B
   is bring-up-only; the proposed fix is correct either way.
3. **`socl_reack_*` grep scope.** I confirmed the only consumers of the three Fix E
   signals are within Fix E itself, by grep over the six FCSM overrides. I did not
   check the UVM copy at `tidelink/uvm/tidelink_top_system/i1fix_fcsm/`.
4. **The link-rate story is stated inconsistently across the tree.** The as-built
   SDC is unambiguous (10 ns `hclk`, 10 ns D2D bit clock, /16 word clock = 160 ns:
   `ASIC/common.mk:304`, `ASIC/genus-innovus/inputs/constraints.sdc:61`,
   `tidelink_constraints.sdc:38-39,478-479`, as-built
   `ASIC/eth-chiplet/build/resyn-20260818/outputs/nanosoc_eth_chiplet_pads_syn.sdc:19,23,25-48`).
   But `local_overrides/WlinkGenericFCSM.v:66` asserts a *"~40 ns silicon link:app
   clock ratio"* — and the AW node's `SOCL_L7_MIN_CRACK_EMITS` 32→8 retune was made
   against that assumption. `ARCHITECTURE_PHY_LINK.md:289` separately asserts an
   "ASIC 250 MHz / ÷16 model" that `constraints.sdc:484-489` explicitly refutes
   without deleting the older text. I used the SDC.
5. **`WlinkGenericFCSM_6.v:153-154` mis-states the state-7 threshold** as "~660 µs
   @ 100 MHz". 16384/100 MHz = 164 µs, and the counter is on `io_tx_clk`
   (`WlinkGenericFCSM_6.v:1633-1642`), so the correct as-built figure is **2.62 ms**.
   Unrelated to these deliverables; worth a separate comment fix.
6. **I did not verify the `BUG_REGISTRY.yaml` TL-009 entry** quoted by
   `ASSESSMENT.md §4.3` (rejecting local abandon / forge-ACK as link-desyncing); my
   grep of `docs/BUG_REGISTRY.yaml` returned nothing. It is now moot for the chosen
   design — the periodic re-ACK is in-protocol and forges nothing — but it should be
   confirmed before anyone revisits a force-advance option.

---

## Appendix — the wedge detector, demoted but not withdrawn

The earlier revision of this document designed a generic timeout at the
`s_axi_awvalid`/`s_axi_awready` seam in `tidelink_top.sv`. **With the root cause
found, it is no longer the fix**, and it should not be landed as one. Prototype:
`tl_link_stall_backstop.sv` in this directory.

It retains a narrower value, for three reasons:

1. **§3.** Fix E does not exist on the tapeout netlist for any of the five AXI FC
   nodes. The detector lives in `tidelink_top.sv`, which is unconditionally in
   every flist — so it is the only part of this workstream that reaches silicon as
   the flists stand.
2. **Reporting.** The no-silent-data-loss property needs a channel. The bus
   response is unavailable (a posted write's master has retired — F-1,
   `tidelink_top.sv:2032-2035`; and SLVERR is ILA-proven to cause a PS write-retry
   loop — `:2057`). A sticky bit in the **spare [23:12] of `xhb_sub_obs_word`**
   (`:1878`, today hard `12'h0`, no consumer) plus a dedicated interrupt —
   precedented by `train_fail_irq` (`:547-553`), kept separate from
   `nego_error_irq` *"so existing handlers don't get re-routed"* — is additive and
   functionally inert.
3. **Precedent.** `dbg_a2l_wedged` (`axi_chiplet_controller.sv:2140-2162`) already
   implements this counter shape for the TideLink data node as an ILA trigger. The
   detector is that, promoted to the AXI node and given a report.

If it is built, it must remain **detection-and-reporting only**: it must never
restore `awready` (§5.1), never assert `synth_b_pending`, and never add a rank to
the `ahb_sub_hreadyout` mux.
