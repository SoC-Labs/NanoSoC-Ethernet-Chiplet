# Diagnosis: why `xhb_sub_hreadyout_raw` stays LOW under the D2D write-wedge

READ-ONLY static-RTL analysis. No RTL/sim was modified. Vendor IP was read, never
written.

**Scope.** Trace, inside the XHB500 AHB-to-AXI bridge instance `u_xhb_sub`
(`tidelink/src/rtl/tidelink_top.sv:2477`), the exact internal mechanism that
holds the bridge HREADYOUT (`xhb_sub_hreadyout_raw`) low when an outbound
write's AW is presented on `s_axi` but never accepted (`awready` stuck low), and
say what a full wedge fix must do beyond removing the tidelink `wr_hold_r` latch
("v2").

## 0. Configuration that fixes which RTL is built

`u_xhb_sub` is generated from config `chiplet_slv`
(`tidelink/deps/xhb500/configs/cfg_xhb_ahb_to_axi.cfg`):

- `REGISTER_AHB_CNTRL: OFF`, `REGISTER_AHB_RDATA: OFF` (cfg lines 90-91)
- `REGISTER_AXI_AW/AR/W/R/B: BYPASS` (cfg lines 100-104)

So HREADYOUT is the **combinational RESP-FSM variant** (not the registered
`REGISTER_AHB_RDATA=ON` path), the stage-2 address register slice is a pure
**bypass** (combinational), and there is **no AXI-side register slice** on AW.
All citations below are to the *generated* sources under
`tidelink/imp/fpga/tidelink_ip/src/` (byte-generated from the vendor templates
in `$IP_LIBRARY_ROOT/ip_library/XHB-500/<product>-<rev>/.../verilog/`).

## (a) The mechanism — signal path and root condition

### The direct driver of HREADYOUT = 0

Module `xhb500_ahb_to_axi_bridge_chiplet_slv_core_resp`, the RESP FSM
(`resp_fsm_comb`), state `RESP_FSM_SEQ_NSEQ`:

```
core_resp.sv:180  RESP_FSM_SEQ_NSEQ : begin
core_resp.sv:181    if (~address_readyout)
core_resp.sv:182      begin
core_resp.sv:183        hreadyout = 1'b0;      <-- HREADYOUT forced LOW here
core_resp.sv:184        hresp     = RSP_OKAY;
core_resp.sv:185      end
core_resp.sv:186    else
core_resp.sv:188      hreadyout = beat_done & ~axi_err;
...
core_resp.sv:195    else if (hreadyout & (~hsel | ~htrans[1]))   <-- only non-error exit
core_resp.sv:196      resp_fsm_next = RESP_FSM_IDLE_BUSY;
```

Two facts lock the wedge:

1. `~address_readyout` **unconditionally** drives `hreadyout = 0`
   (core_resp.sv:181-183). The `beat_done`/`ewr` fast-path (line 188) is in the
   `else` arm and never even evaluated while `address_readyout` is low. So no
   amount of W-data, B-response, bufferable/EWR completion, hazard state, etc.
   can raise HREADYOUT while `address_readyout==0`.
2. The FSM cannot leave `SEQ_NSEQ`: the error exits need `axi_err`
   (a returning B/R error) *and* `address_readyout` (line 191); the only
   non-error exit (line 195) requires `hreadyout==1`. With `hreadyout` pinned
   at 0 the state is **latched in SEQ_NSEQ**.

### Why `address_readyout` is 0 — the AW back-pressure path

`address_readyout` is the ready-back of the stage-1 address register slice:

```
core_addr.sv:229  assign address_readyout = cntrl_1_in_ready;
```

`cntrl_1_in_ready` is `ready_src` of the reverse register slice
`u_ctrl_st1_regslice_rst` (`xhb500_reverse_regd_slice_rst_empty`):

```
reverse_regd_slice_rst_empty.sv:69  assign ready_src = ~buffer_full[0];
reverse_regd_slice_rst_empty.sv:50  wire buffer_en = (valid_src & ~buffer_full[0] & ~ready_dst);
reverse_regd_slice_rst_empty.sv:59  wire buffer_full_en = (buffer_en | ready_dst);
reverse_regd_slice_rst_empty.sv:66      buffer_full <= {NUM_SEL_LINES+1{buffer_en}};
```

Its downstream ready (`ready_dst`) is, for a write:

```
core_addr.sv:186  assign cntrl_1_out_ready = cntrl_2_in_ready && ~pause_addr_submit;
core_addr.sv:206  assign cntrl_2_out_ready = cntrl_2_out.hwrite ? awready : arready;
```

Stage 2 is a **bypass** slice, so `cntrl_2_in_ready == cntrl_2_out_ready == awready`
(bypass_regd_slice.sv:38). Therefore for the write beat:

```
ready_dst(stage1) = awready & ~pause_addr_submit
```

Cycle-accurate fill (single write, `awready` stuck 0, `pause_addr_submit`=0
because the AW *is* being presented — `awvalid = cntrl_2_out_valid & hwrite`,
core_addr.sv:278):

- **Cycle 0** (AHB address phase, hready=1): `buffer_full[0]=0` so
  `ready_src=1` → `address_readyout=1` → the AHB address **is accepted**;
  `ready_dst = awready(0) = 0` so `buffer_en=1` → the AW payload is latched and
  `buffer_full` will be set next cycle. `valid_dst=1` → `awvalid` asserted.
  RESP FSM: `ahb_trans=1` in `IDLE_BUSY` → next `SEQ_NSEQ`.
- **Cycle 1+**: `buffer_full[0]=1` → `ready_src=0` → **`address_readyout=0`**.
  `buffer_full_en = buffer_en | ready_dst = 0 | awready(0) = 0` → `buffer_full`
  **holds** (cannot clear) until `ready_dst=1`, i.e. until `awready=1`.
  `valid_dst` stays 1 → `awvalid` stays asserted. RESP FSM in `SEQ_NSEQ`,
  `~address_readyout=1` → `hreadyout=0`, latched.

So the chain is:

```
awready stuck 0
  -> cntrl_2_out_ready = 0  (core_addr.sv:206)
  -> cntrl_1_out_ready = 0  (core_addr.sv:186)
  -> stage-1 reverse slice cannot drain, buffer_full[0] pinned 1  (reverse_regd_slice_rst_empty.sv:59-66)
  -> address_readyout = ready_src = 0  (core_addr.sv:229 / slice :69)
  -> RESP_FSM_SEQ_NSEQ forces hreadyout = 0, FSM latched  (core_resp.sv:181-183, exit :195 blocked)
  -> hreadyout (= xhb_sub_hreadyout_raw) LOW indefinitely
```

The HREADYOUT drops one-plus cycles *after* the address-accept (raw was HIGH in
cycle 0), which is exactly the "raw HIGH at its ADDRESS-accept, then holds 0"
picture noted at `tidelink_top.sv:1802`. This is legal AHB (the bridge is
inserting data-phase wait states); it simply never terminates them.

### Relation to the tidelink observations

- **`sub_stall_ctr_r` 0 -> 65536.** This is a *tidelink wrapper* counter, not an
  XHB500 counter. It increments while `sub_ext_stalled` (`tidelink_top.sv:1549`),
  whose write term is `sub_stall_busy = !xhb_sub_hreadyout_raw`
  (`tidelink_top.sv:1543`). It ramps to the `2^16` timeout precisely because the
  bridge holds `hreadyout` low as traced above. `SUB_STALL_TIMEOUT_LOG2=16`
  (`tidelink_top.sv:1499`), so 65536 == the expiry threshold, not a bridge limit.
- **`ext_is_nonseq = 0`.** No new NONSEQ is being presented; the AHB master
  (FPGA loopback) has dropped to IDLE after its single write beat was accepted in
  cycle 0. The bridge is mid-transaction inside `SEQ_NSEQ`, waiting internally on
  `awready` — not stalled because of a fresh incoming transfer. This is why the
  wedge is invisible to the "`ext_is_nonseq && !pipe_valid_r`" rank-3 path of the
  hreadyout mux (`tidelink_top.sv:1921`) and is seen only through rank-6 raw.
- **There is no XHB500 stall counter or outstanding-limit involved.** The only
  counters in the bridge are `read_counter`, `write_counter`, hazard-list
  `list_pointer` (depth 4), none of which force `hreadyout` high. `hazard_full`
  and the EWR/`pending_broken_b_resp` machinery act through `pause_addr_submit`
  (core_addr.sv:151-159) — a *different* upstream cause that would keep `awvalid`
  *de-asserted*; in this wedge `awvalid` is asserted, so that path is not the
  trigger. The trigger is squarely the AW handshake (`awready`) not completing.

## (b) Self-clear vs. hang — verdict: HANGS

The bridge holds `hreadyout` low **indefinitely until `awready` is asserted**
(or `resetn` is deasserted). Evidence from the RTL:

- `buffer_full` in the stage-1 reverse slice clears only when `ready_dst=1`,
  i.e. `awready & ~pause_addr_submit` (reverse_regd_slice_rst_empty.sv:59-66).
  No timer, no self-flush.
- The RESP FSM has no timeout leg out of `SEQ_NSEQ` (core_resp.sv:180-197). All
  exits require either a returning AXI error response (which itself needs
  `address_readyout`, i.e. the AW already drained) or `hreadyout==1`.
- There is **no watchdog, no configurable timeout, and no "abandon transfer"
  knob** anywhere in the AHB-to-AXI bridge. `AHB_LOCK_RESP`, the Q-channel
  logic, and the IRQ path do not release a stuck AW.

So: recovers **only** when the downstream AXI slave finally asserts `awready`
for that beat, or on reset of the bridge. It does **not** self-clear.

## (c) What a FULL wedge fix must address (beyond v2's `wr_hold_r` removal)

**Why v2 alone is insufficient (confirmed).** The tidelink hreadyout mux
(`tidelink_top.sv:1919-1924`) has `wr_hold_r` at rank 5 (line 1923) and
`xhb_sub_hreadyout_raw` at rank 6 (line 1924). v2 removes the `wr_hold_r` latch
(lines 1845-1860), but rank 6 raw is **also 0** during this wedge, per section
(a). Removing rank 5 just exposes rank 6, which is stuck low. No change.

**Why the existing synth-B backstop does not cover this wedge.** The F-1/F-2
synthetic-B machinery (`tidelink_top.sv:1867-1917`) only arms via
`sub_wr_stuck_fire = (sub_osr_expired | sub_stall_expired) & (sub_wr_os_ctr != 0)`
(line 1878). `sub_wr_os_ctr` counts **accepted** AWs (`sub_aw_accept =
s_axi_awvalid & s_axi_awready`, line 1570; increment at line 1662). In the
AW-not-accepted wedge `awready` never pulses, so `sub_wr_os_ctr` stays 0 and
`sub_wr_stuck_fire` is permanently 0 — synth-B never fires. The read/ERROR
backstop is read-only (`if (sub_rd_os_r) sub_err1_r<=1`, line 1645), so it never
fires for a write either. Net: on `sub_stall_expired` the counter just resets
(line 1637) and re-ramps — matching the ILA "ramp to 65536, no recovery". The
current wrapper is **structurally blind** to an AW that is issued but never
accepted.

The root fact a full fix must confront: **only `awready=1` (or bridge reset)
drains the stage-1 reverse slice and lets `address_readyout` rise.** A fix that
only forces the PS-facing `ahb_sub_hreadyout` high (e.g. a new override rank)
would unblock the die_a PS but leave `u_xhb_sub` internally latched in
`SEQ_NSEQ` with its slice full — the next AHB transfer to the bridge then
collides with the stuck state. So the cure must act on the **XHB500 s_axi side**,
not just the mux. Concrete options I can see, with hooks:

**Option 1 — Synthetic AW-accept + drain (preferred; extends the existing
synth-B).** On a write-stuck timeout, have the wrapper complete the s_axi write
handshake itself: pulse a synthetic `awready` into the bridge, spoof `wready`
for the W beat(s), then return the synthetic B (which already exists). This
drains `buffer_full`, `address_readyout` rises, the FSM leaves `SEQ_NSEQ`, and
raw goes high the natural way.
  - New arming term: broaden the stuck detector to include "AW presented, not
    accepted" — e.g. add `(s_axi_awvalid & !s_axi_awready)` persistence to
    `sub_axi_outstanding`/`sub_wr_stuck_fire` (`tidelink_top.sv:1573`, 1878-1879)
    so the `sub_stall_expired` timer (already ramping) can arm recovery even when
    `sub_wr_os_ctr==0`.
  - AW hook: the bridge's `awready` port is `.awready(s_axi_awready)`
    (`tidelink_top.sv:2512`), and `s_axi_awready` is driven by the downstream
    Wlink target at `tidelink_top.sv:2882`. Insert a wrapper mux so the bridge
    sees `s_axi_awready | synth_aw_accept`, and **mask the downstream awready for
    that beat** to avoid a later double-accept if the link revives.
  - W hook: `.wready(s_axi_wready)` (`tidelink_top.sv:2532`), driven at
    `tidelink_top.sv:2894`; same synthetic-OR + mask.
  - B hook: already present — `s_axi_bvalid = s_axi_bvalid_ctrl | synth_b_pending`
    (`tidelink_top.sv:1894`), with `s_axi_bid`/`s_axi_bresp` spoofing at
    1916/1895. Reuse it.
  - Risk to handle: this asserts a *phantom* downstream write acceptance; it is
    only safe once the link is declared wedged (past the ~2^16 timeout) and the
    real downstream `awready`/`wready` are masked so the same AW is not accepted
    twice.

**Option 2 — Local bridge flush-reset.** Gate a wrapper-generated synchronous
reset into *only* `u_xhb_sub` on the write-stuck timeout. The stage-1 slice
`buffer_full` is async-reset (`reverse_regd_slice_rst_empty.sv:61-66`) → clears
to empty → `address_readyout` returns to 1 and the RESP FSM returns to
`IDLE_BUSY` (core_resp.sv:155-156). Clean, self-contained recovery of the bridge
itself.
  - Hook: `.resetn(hresetn)` at `tidelink_top.sv:2479` — replace with
    `hresetn & ~sub_bridge_flush`.
  - Cost: drops any genuinely in-flight sub transaction (acceptable once wedged);
    must be paired with an AHB ERROR/OKAY termination to the PS so the CPU's
    outstanding beat retires (reuse the `sub_err1_r/sub_err2_r` 2-cycle sequencer,
    `tidelink_top.sv:1919-1927`, this time allowed to fire for writes).

**Option 3 — Prevent the unaccepted-AW upstream: NOT feasible in the bridge.**
There is no XHB500 config or timeout that releases an unaccepted AW (verified:
no watchdog anywhere in `core`/`core_addr`/`core_wdata`/`core_resp`/`hazard_list`;
`REGISTER_AXI_AW=BYPASS`, so not even a register-slice skid buffer is present to
absorb it). The only bridge-internal release is `awready=1` or reset. So
"prevention" would have to live entirely downstream (guarantee the Wlink target
always eventually accepts an AW), which is the real silicon bug, not a wrapper
change.

**Bottom line for the fix:** v2 (drop `wr_hold_r`) is necessary but does nothing
for this co-hold. A full fix must (i) make the wrapper *detect* an AW that is
presented but never accepted (broaden the arming condition around
`tidelink_top.sv:1878`), and (ii) act on the XHB500 s_axi side — either force the
AW/W handshake to complete and reuse the synth-B drain (Option 1, hooks at
:2512/:2532/:1894) or flush-reset the bridge instance (Option 2, hook at :2479) —
paired with a legal AHB termination to the PS. Forcing only the PS-facing hready
mux is not a cure because the bridge's own slice/FSM stay latched.

## (d) Confidence and what could NOT be determined statically

**High confidence** on the mechanism (a) and the hang verdict (b): the config is
pinned (`REGISTER_AHB_RDATA=OFF`, AW `BYPASS`), and the generated RTL was read
directly (not the parameterized templates), so the exact `hreadyout`, slice, and
back-pressure equations are unambiguous. The AW back-pressure chain
`awready -> ready_dst -> buffer_full -> ready_src -> address_readyout ->
hreadyout` is fully combinational/one-register and self-consistent with the
"raw HIGH at accept, then 0" ILA note.

**What static RTL cannot settle:**
- **Why `awready` is stuck** — this analysis proves the bridge *response* to a
  stuck `awready`; it does not identify why the downstream Wlink target
  (`tidelink_top.sv:2882`) stops asserting `awready`. That is upstream of this
  IP (the D2D/link wedge itself) and is out of the XHB500's control.
- **`ewr` value of the injected write** — whether the peer-write is bufferable
  (`hprot[2] & ~hprot[6]`, giving `ewr=1`) or not changes the `beat_done_w`/B
  behaviour *once the AW is accepted*, but is **irrelevant to this wedge**: the
  `~address_readyout` guard (core_resp.sv:181) dominates before `beat_done` is
  evaluated. So the hang is `ewr`-independent by construction.
- **`pause_addr_submit` corner** — I inferred `pause_addr_submit=0` during the
  wedge from `awvalid` being asserted (AW issued). If a capture ever shows
  `awvalid` low with `hreadyout` low, the cause would instead be
  `pause_addr_submit` (hazard-full / `pending_broken_b_resp` / `ready_for_read`,
  core_addr.sv:151-159) rather than `awready`; that is a distinct sub-case with
  the same core_resp.sv:181-183 endpoint. The task's premise (AW issued,
  `awready` never comes) selects the `awready` root.
- **Exact synth-AW handshake ordering** (how many W beats to spoof, wlast
  timing) for Option 1 needs a bench to pin down; the hook points are certain,
  the beat-count sequencing is not derivable from static RTL alone.

## (e) Independent wrapper-side verification (2026-08-17)

The load-bearing wrapper-side claims in (c) were re-checked directly against
`tidelink/src/rtl/tidelink_top.sv` (working checkout):

- **synth-B is blind to an unaccepted AW — CONFIRMED.** `sub_wr_stuck_fire` arms on
  `(sub_osr_expired | sub_stall_expired) & (sub_wr_os_ctr != 3'd0)` (inline at :1745,
  declared ~:1851); `sub_wr_os_ctr` increments only on the accepted-write `2'b10` case
  (:1662), so an AW whose `awready` never asserts leaves it at 0 and `sub_wr_stuck_fire`
  is permanently 0. Matches (c).
- **Fix hooks exist where cited — CONFIRMED.** `u_xhb_sub` :2477; `.awready(s_axi_awready)`
  :2512; `.wready(s_axi_wready)` :2532; `.resetn(hresetn)` :2479; synth-B `s_axi_bvalid`
  path ~:1894.
- **Option-2 nuance:** `.resetn` at :2479 is the *shared* `hresetn`. A per-instance flush
  therefore needs a NEW gated reset net (`hresetn & ~sub_bridge_flush`), not merely a driver
  on the existing port — the Option-2 hook text implies this; calling it out so the
  implementer doesn't expect a spare per-instance reset input.

Confidence in the wrapper-side fix path is HIGH. The XHB500-internal trace in (a) is cited to
the generated bridge sources and is self-consistent, but was not independently re-read
line-by-line by the verifying session.

## (f) Silicon corroboration (independent, 2026-08-17)

An independent TL-042 investigation (session tidelink-63) reports a pre-registered **silicon ILA
probe** — `imp/hw_gate/ila_raw_probe/RAW_HREADYOUT_RESULT_2026_08_13.md` (off-repo clone) — that
**measured `xhb_sub_hreadyout_raw == 0` across the entire held wedge, and continuing for ~3582 cycles
*after* `wr_hold_r`'s own release.** That is hardware confirmation, from a completely different angle
(silicon ILA vs. the static `core_resp.sv:181-183` / `SEQ_NSEQ` trace in (a)), of the central claim
here: **rank6 raw stays low independently of `wr_hold_r`, so v2 alone cannot clear the wedge.** The
~3582-cycle post-release window is also the interval in which any recovery (or the upstream root fix)
must act. (Relayed by tidelink-63, not personally read — the probe doc lives in an off-repo clone.)
