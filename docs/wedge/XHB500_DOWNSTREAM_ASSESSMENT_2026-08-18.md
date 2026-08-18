# Downstream half of the TideLink D2D write wedge — assessment + completion path

**Date:** 2026-08-18 · **Scope:** analysis + isolated prototype bench only.
Nothing under `tidelink/src/rtl/`, `tidelink/cocotb/`, `$IP_LIBRARY_ROOT/**` was written.
No commits, no pushes. All artefacts are in this directory.

**Measured against:** `tidelink/src/rtl/tidelink_top.sv` md5 `d88029d98a660caeba62acbbae0d037b`,
tidelink HEAD `3620af3328cab45f6603965f1e02411976456519` (branch `fix/tag-ram-gwen` /
`integ` freeze line). Chiplet worktree, 2026-08-18 22:5x.

---

## 0. Headline

**The prototype's control experiment no longer reproduces on today's RTL, and the
architectural question has inverted.**

1. The prototype was built on a copy of `tidelink_top.sv` that **predates TL-037**
   (`imp/hw_gate/tl042_recovery_proto/tidelink_top_orig.sv`, md5 `3eb9f53d…`,
   contains **zero** occurrences of `TL-037` / `sub_mst_dphase_r`). TL-037's terminal
   timeout landed 2026-08-14 and fires under *exactly* the prototype's control
   conditions. **Measured here: today's RTL does NOT hang** — the AHB master is
   answered with a legal 2-cycle ERROR at the stall timeout, and again for every
   subsequent write. The prototype's stated purpose ("stop the permanent hang") is
   already served by landed code.

2. **What replaces it is worse and is newly proven here: once the upstream fix
   restores `awready`, today's RTL silently delivers the WRONG DATA to the peer.**

   ```
   [stale] VERDICT: intended payload 0xd0d00042, delivered 0xbad0bad0, wstrb=0xf
   ```

   Correct address (`0x4000_0100`), full byte strobes, and it will be answered
   OKAY. Two controls isolate the mechanism (§3.2).

3. Therefore: **a downstream mechanism is still required, but its job has changed.**
   It is no longer "unwedge the bridge" (the upstream fix does that, and TL-037
   already bounds the hang). It is **"make the abandoned write fail safe when the
   link comes back"**. Do not land the prototype as-is; its shape solves the wrong
   problem and its own residue is a silent *drop reported as OKAY*.

---

## 1. What the prototype actually proved

`tidelink/imp/hw_gate/tl042_recovery_proto/` — patch, two benches, clean logs,
`PROTO_RESULT.md`. Isolation is genuine (shim `\`include`s a local copy; shared file
md5 unchanged start-to-end). Its claims hold **on its own base**:

| claim | verdict |
|---|---|
| Control reproduces the AW-not-accepted wedge (`hreadyout` stuck 0 past 2^10, `sub_wr_os_ctr=0`, synth-B structurally blind) | **True on its base copy.** Does **not** reproduce on today's RTL (§3.1). |
| A **one-shot** synthetic AW accept does NOT recover; the wrapper's held `pipe_hsel_r` re-latches the same address (a phantom second AW), so the accept must be **held across the whole flush** | **True and still true.** Confirmed independently here: after TL-037's abort clears `pipe_valid_r`, the still-asserted `ext_is_nonseq` re-latches the same address one cycle later (`pipe_v` 0→1 in `log_test_today_awwedge_tl037_terminal_error.log`). This is the prototype's most durable finding and survives everything else in this document. |
| Held synthetic accept + reuse of the synth-B drain recovers with an AHB OKAY | True on its base. |
| The downstream double-accept mask holds (`*_valid_dn = *_valid & ~rec_active`) | True as a *structural* argument; still correct. |
| "Proof of mechanism, not land-ready" | **Correct, and understated** — see §2 and §4. |

Its own harness findings (cocotb `all:` goal collision; `flist_deps.mk` forcing a
recompile every run) are accurate and were re-encountered here.

---

## 2. The prototype's open items, re-checked against TODAY's RTL

### 2.1 Multi-beat bursts — **STILL REAL, and the surrounding RTL moved under it**

Only a single-beat `hsize=2, hburst=0` write was exercised. Since then the burst
path has changed: `ahb_sub_w_beat_consumed_o` was added (2026-08-18,
`tidelink_top.sv:591`) as a **per-beat** W-consumption strobe — deliberately
TL-002's `wr_hold_clr` *without* the `& s_axi_wlast` term — to re-arm the chiplet's
peer-write capture per beat. The prototype's flush accepts every presented W beat
but was never checked for `wlast` placement or B-count, and it now also has to not
perturb that new output. Open, and larger than when it was written.

### 2.2 Hazard-list leak / `sub_wr_os_ctr` drain-to-0 — **REAL, but it is the prototype's own creation, not the wedge's**

Read from the vendor source
(`tidelink/deps/xhb500/generated/…_core_addr.sv`):

```
hazard_add = … & cntrl_1_out_valid & cntrl_2_in_ready & hwrite & hprot[2] & ~hazard_full & …
```

During the wedge `cntrl_2_in_ready == 0`, so **the wedge itself adds no hazard
entry** — there is nothing to leak. The prototype's synthetic accept drives
`cntrl_2_out_ready` (= the bridge-facing `awready`) high, which *is* what makes
`cntrl_2_in_ready` rise and `hazard_add` fire. So the depth-4 hazard list is
populated **by the recovery**, and each entry is freed only by `b_done & b_ewr`
with a matching `bid`. The prototype logged `os_ctr_max=2` (the phantom re-latch),
i.e. **two** entries added and two synthetic Bs required. Fix K's `bid` correction
(`s_axi_bid = sub_wr_awid_r` whenever a real or synthetic B returns) makes the
match guaranteed, so the accounting is *probably* right — but it was never
measured, and the prototype's replacement synth-B clear (§2.3) is exactly what
would break it. Still open **for this shape only**.

### 2.3 Self-releasing `rec_active` — **REAL, and now has a NEW failure mode**

`rec_done` requires `sub_wr_os_ctr == 0`; if the drain stalls, `rec_active` latches
and the downstream stays masked forever. Unchanged. **New since the prototype:**
`rec_active` masks `s_axi_awvalid_dn`/`s_axi_wvalid_dn` away from the Wlink for its
whole duration. If the upstream replay timeout fires *while* `rec_active` is high,
the recovered `awready` sees no valid — the two recoveries actively fight, and the
upstream's one chance to drain its window is consumed by silence. A downstream
recovery that masks the link is now **incompatible by construction** with an
upstream recovery.

### 2.4 Reconciling the synth-B clear with F-1/F-2 — **NOW A HARD COLLISION with TL-043 (landed 2026-08-18)**

The prototype replaces the shipped clear
```
else if (synth_b_pending & s_axi_bready & (sub_wr_os_ctr <= 3'd1)) synth_b_pending <= 1'b0;
```
with `else if (sub_wr_os_ctr == 3'd0) synth_b_pending <= 1'b0;`.

TL-043 landed a **deliberately duplicated copy of the old predicate** at
`tidelink_top.sv:1999`:
```
wire wr_hold_drain_release = synth_b_pending & s_axi_bready & (sub_wr_os_ctr <= 3'd1);
```
with the comment *"Same predicate as the `synth_b_pending` clear at its own
always_ff below"*. That equality is load-bearing: it is TL-043's edge-qualified
replacement for the level `synth_b_pending` in `wr_hold_clr`, and it is what keeps
the TL-002 deadlock guard alive without blinding every other write.

**Landing the prototype's clear would silently decouple the two.** They are not
wired together — nothing would error, and TL-043's guard would simply stop firing
in step with the drain. Worse: because the prototype *asserts* `synth_b_pending`
during recovery, `wr_hold_drain_release` fires on the drain's last B and releases
`wr_hold_r` — the same class of harm that got the v1 candidate rejected on
hardware (`TL042_HW_RESULT_REJECTED_2026_08_13.md`: 16/16 → 0/16 byte delivery),
now edge-qualified rather than level-asserted, so milder but not gone. The
prototype's note calls this "must be reconciled"; against today's tree it is a
**blocking** two-site change with its own A/B requirement.

### 2.5 Items the prototype listed and that remain untouched

Non-bufferable (`hprot[2]=0`) path; a genuinely (not forced) wedged Wlink;
cross-die/PTP/TideChart interaction. All still open. Note the upstream survey
records that the wedge **could not be induced on the bare pair**, so "genuinely
wedged" may not be reachable without the ILA campaign.

---

## 3. New measurements (this session)

Bench: `Makefile`, `test_downstream_wedge.py`, local `tb_top.sv` copy carrying the
`TB042_WEDGE_HOOK` ready-force injector. **The DUT is the shipping V2 flist
unmodified** (`flists/tidelink_fpga_v2.flist` → `v2shims/v2_tidelink_top.sv` →
the shared `tidelink_top.sv`) — no shim swap, so there is no possibility of testing
a stale copy. `sim_build_today` was `rm -rf`'d and a full VCS recompile confirmed.
`+define+TIDELINK_SUB_STALL_TIMEOUT_LOG2=10`, `…OUTSTANDING…=12`.

Wedge construction: force the master die's downstream `s_axi_awready`/`s_axi_wready`
LOW (= the a2l AW replay window full, upstream half), present **one** bufferable/EWR
single-beat write to `0x4000_0100`.

### 3.1 Today's RTL does not hang — TL-037 answers the master

`log_test_today_awwedge_tl037_terminal_error.log` — **PASS**
```
rose_at=1028  hresp_at_rise=1  stall_ctr_max=1024 (thresh=1024)
at rise : hreadyout=1 hresp=1 raw=0 err2=1 dphase=1 wr_hold=1 os_ctr=0 sbp=0
          addr_readyout=0 write_data_valid=1 stall_writes=1 resp_fsm=SEQ_NSEQ
+200cyc : hreadyout=0 raw=0 wr_hold=1 addr_readyout=0 write_data_valid=1
```
`log_test_today_second_write_after_error.log` — **PASS**: a second write during the
same wedge is answered at **975 hclk with hresp=1**. So the port is not dead; it is
a **bounded periodic bus error**, once per stall-timeout window.

The prototype's control assertion (`rose is None`) would **FAIL** on today's RTL.
Its base copy contains no TL-037, and all three of TL-037's guards are satisfied by
this wedge: `sub_mst_dphase_r=1`, `sub_wr_os_ctr==0`, `!synth_b_pending`.

Residual after the ERROR, and this is the whole story: **`wr_hold_r` stays 1,
`xhb_sub_hreadyout_raw` stays 0, `address_readyout` stays 0, and XHB500's
`write_data_valid` stays 1** — an armed, undelivered W beat.

### 3.2 THE DECISIVE RESULT — upstream recovery delivers stale data

`log_test_today_upstream_recovery_delivers_stale_wdata.log` — **FAILS BY DESIGN**
(the assertion is the finding).

Sequence: wedge → TL-037 answers the master at c=1028 with ERROR → the master
retires (SIGBUS) and the bus carries `0xBAD0_BAD0` → **the upstream fix recovers**
(`awready`/`wready` driven HIGH) → observe `s_axi`.

```
[stale] AW handshake: (0, 1073742080)          # 0x4000_0100 — correct address
[stale] W  handshake: (1, 3134241488, 15)      # 0xBAD0_BAD0, wstrb 0xF
[stale] VERDICT: intended payload 0xd0d00042, delivered 0xbad0bad0, wstrb=0xf
```

**Controls (both PASS), which isolate the mechanism:**

| control | construction | delivered | meaning |
|---|---|---|---|
| `test_ctrl_healthy_write_delivers_correct_wdata` | no wedge at all, same stimulus | `0xD0D0_0042` | the bench driver holds HWDATA correctly — the result is not an artefact |
| `test_ctrl_wedge_then_recover_master_still_driving` | identical to the experiment **except** the master keeps driving `D1` after being answered | `0xD0D0_0042` | the wedge and the recovery are not themselves corrupting — **the release of HWDATA is** |

### 3.3 Why, from the vendor RTL

`…_core_wdata.sv`:
```
stall_writes  = ~address_readyout || pending_broken_b_resp || ~(clk_qacceptn && pwr_qacceptn);
wdata_in_valid = (write_data_valid & ~stall_writes) || write_broken;
wdata_in       = { last, strb & {4{~write_broken}}, hwdata };     // LIVE AHB HWDATA
```
`…_core_addr.sv`:
```
address_readyout  = cntrl_1_in_ready;
cntrl_1_out_ready = cntrl_2_in_ready && ~pause_addr_submit;
cntrl_2_out_ready = cntrl_2_out.hwrite ? awready : arready;
```

`awready = 0` ⇒ stage-2 fills ⇒ stage-1 fills ⇒ `address_readyout = 0` ⇒
`stall_writes = 1` ⇒ `wdata_in_valid = 0`. **The W payload is never captured.**
`write_data_valid` is a register whose only clear requires
`wdata_in_ready && ~stall_writes`, so it stays armed. `hwdata` is a **live wire**
(`tidelink_top.sv:2679 .hwdata(ahb_sub_hwdata)` — the wrapper has no write-data
register anywhere). The instant `awready` returns, `stall_writes` falls,
`wdata_in_valid` rises, and the slice samples **whatever the AHB bus is carrying at
that moment**.

`write_broken_next` — XHB500's own abandoned-write detector — is gated on the
bridge's `hreadyout`, which is stuck 0 through the wedge, so it never arms. The
bridge cannot self-protect here.

TL-002's `wr_hold_r` exists precisely to stop this, but in the mux
```
ahb_sub_hreadyout = (sub_err1_r & ~synth_b_pending) ? 0 :
                    (sub_err2_r & ~synth_b_pending) ? 1 :   // <-- TL-037 lands here
                    … : wr_hold_r ? 0 : xhb_sub_hreadyout_raw;
```
**`sub_err2_r` outranks `wr_hold_r`.** TL-037 answers the master *over the top of*
an engaged TL-002 hold. That is not a bug in TL-037 as it stands — today the link
never comes back, so nothing is delivered. It becomes a data-integrity defect the
moment the upstream fix exists.

### 3.4 Accounting for N writes issued during one wedge

The second write never reaches the bridge at all: `p_write_addr_strb_reg` and
`p_write_data_phase_reg` update on `hsel & hready`, and `xhb_sub_hready` is
`pipe_valid_r ? raw : …` = 0 throughout. So of N writes issued into a wedge:
**N−1 are dropped outright, exactly one is delivered with corrupt data, and all N
report SIGBUS.** Only one deferred beat is ever armed.

### 3.5 Is TL-042 v2 still needed? — partly measured, partly derived

TL-042 v2 (`imp/hw_gate/tl042_v2/`) is **NOT landed** (`grep -c aw_since_hold_r
src/rtl/tidelink_top.sv` → 0), and its patch **no longer applies** — hunk 3 of 4
fails, because TL-043 rewrote the same `wr_hold_clr` block on 2026-08-18.

Its §6.6 blocker — *"blocked until `wr_hold_clr`'s `synth_b_pending` term is
converted from a LEVEL to a PULSE"* — **has been removed**: that is exactly what
TL-043 did.

Its primary motivation is largely superseded. v2 exists to convert a permanent
`wr_hold_r` hang into "wedged only while XHB500 is stalled"; TL-037 already gives
the master a bounded, repeating, legal ERROR in the `raw=0` case (§3.1), which is
the case v2's own §0 derived for the silicon capture.

The residual v2 still covers is the `raw==1` state (XHB500 healthy, `wr_hold_r` the
sole low-driver, nothing outstanding on `s_axi`). **Derivation from the shipped
RTL:** `sub_ext_stalled = (sub_stall_fill || sub_stall_busy)`; with `raw==1`,
`sub_stall_busy = 0`, and with the master's address latched `sub_stall_fill = 0`,
so the per-beat timer resets every cycle and TL-037 can never fire. The I5 timer is
gated on `sub_axi_outstanding`, which is 0 with no AW accepted. **No backstop can
act ⇒ permanent hang ⇒ v2 is still needed for that state.** Partial empirical
corroboration: `osr_ctr_max=0` throughout
`log_test_today_validmask_wrhold_hang_is_tl037_blind.log`.

**Honest limitation:** my attempt to *reproduce* `raw==1` via the v2 `valid_mask`
construction did **not** succeed in this harness — forcing `s_axi_awvalid`/`wvalid`
low with `awready` high produced a **hazard-list-full** stall (`raw=0`,
`address_readyout=0`), which TL-037 answered at 1036 hclk. So §3.5's `raw==1`
conclusion is a static derivation, not a measurement. Do not quote it as measured.

---

## 4. Architectural verdict

**Question:** once the upstream replay timeout exists, does the downstream recovery
become unnecessary?

**Answer: no — but the prototype's version of it does. The requirement inverts from
liveness to data safety.**

Argued from the RTL:

1. **Liveness is already handled, twice over.** (a) The XHB500 stall chain is pure
   flow control with no latched state of its own: `address_readyout` is
   `cntrl_1_in_ready` and `cntrl_2_out_ready` is `awready`, so the instant `awready`
   returns the whole chain drains and `raw` rises — measured (`raw` 0→1, `os_ctr`
   0→1 in `log_test_today_upstream_recovery_delivers_stale_wdata.log`). The bridge
   does **not** latch a hang that outlives the upstream fix. (b) Independently,
   TL-037 already bounds the PS-facing hang without any link recovery at all
   (§3.1/§3.4). **A downstream recovery whose purpose is "unwedge the bridge" is
   redundant on both counts.**

2. **Data safety is not handled, and the upstream fix is what makes it bite.**
   §3.2/§3.3. Today the corruption is invisible because `awready` never returns
   (the upstream survey confirms: no timeout, no self-release, `a2l_full` clears
   only on a far-die ACK or a reset; recovery in the field is JTAG POR). The
   upstream fix is precisely the change that turns an inert armed beat into a
   delivered wrong-data write. **The two halves must land together, or the upstream
   fix must land behind the downstream guard.**

3. **The likely shape of the upstream fix makes this worse, not better.**
   `BUG_REGISTRY.yaml` TL-009 rejects local abandon / forge-ACK as link-desyncing,
   leaving reset-class recovery (link retrain / FC-node reset) as the live option.
   A reset **guarantees** `app_ready = ~a2l_full & enable` returns to 1 — so it
   guarantees the stale beat fires. A timeout that merely drops the AW would be
   *safer* for this defect, and is the rejected option.

4. **The prototype's shape is actively incompatible with an upstream fix.** It
   masks `awvalid`/`wvalid` from the Wlink for the whole of `rec_active` (§2.3) and
   completes the write to the PS with **OKAY** for a payload the peer never
   receives — a silent lost write reported as success. Against TL-037's honest
   SIGBUS that is a regression in reportability, and against an upstream recovery it
   is a race.

**Verdict: keep a downstream mechanism, discard the prototype's design.** The
correct downstream change is small, local, and orthogonal to the upstream work:
*neutralise the armed W beat at the moment the wrapper gives up on the transfer, so
that whatever the link does later cannot deliver a payload the master no longer
owns.*

---

## 5. Completion path

### 5.1 Land first, independently — the data-safety guard (**new work, highest value**)

**Requirement.** When the wrapper terminates a peer write that XHB500 has not yet
sampled (`sub_err1_r` fires with `wr_hold_r` still engaged), the write must be made
incapable of later delivering stale data.

**Constraints inherited from three prior rejections.** Do **not** touch
`synth_b_pending` (v1 was rejected on hardware for exactly that — it is a term of
`wr_hold_clr`). Do **not** add a rank to the `ahb_sub_hreadyout` mux (v2's own
constraint 3). Do **not** modify `$IP_LIBRARY_ROOT/**`; if the fix must reach inside
XHB500, copy the file to `tidelink/src/rtl/local_overrides/` and rewire **both**
`flists/tidelink_fpga_v2.flist` and `flists/tidelink_top_full_asic_v2.flist` —
the V2 flists are the ones that ship, and there is recorded precedent
(`DEV_MESSAGE_A2L_SELFLATCH_SILICON_2026_08_09.md`) of an override landing as a
silent no-op because only the V1 flist was updated.

**Three candidate mechanisms, in preference order.**

* **(A) Capture HWDATA in the wrapper.** Register `ahb_sub_hwdata` at
  `wr_hold_set` and present the captured value to `u_xhb_sub.hwdata` while
  `wr_hold_r` is engaged. Removes the "live wire" premise entirely, so the deferred
  sample gets the right payload and the write eventually lands **correctly** rather
  than being killed. Purely additive at module scope, no vendor change, no mux
  change, no `synth_b_pending`. **Cost:** one 32-bit register; must be proven
  transparent for the healthy path and burst-correct (per-beat capture, and it must
  not disturb `ahb_sub_w_beat_consumed_o`). This is the recommended first attempt —
  it converts the defect into correct behaviour instead of a safer failure.
* **(B) Zero the strobes on the abandoned beat.** Drive `wstrb=0` for a beat the
  master has been ERRORed off. Requires reaching `strb` inside `core_wdata` → a
  `local_overrides` copy of vendor RTL. Deliverable but heavier, and it still posts
  a phantom AW to the peer.
* **(C) Kill the armed beat.** Assert something that makes `write_broken` set (its
  own trigger is gated on the bridge's stuck-low `hreadyout`, so it cannot
  self-arm). Also a vendor-copy change; least attractive.

**Non-vacuity A/B required (the process failure that let v1 ship a regression was a
test that only asserted escape):**
- ARM A = today's RTL → `test_today_upstream_recovery_delivers_stale_wdata` **FAILS**
  with `delivered=0xBAD0_BAD0`. Already captured here; reuse verbatim.
- ARM B = guarded RTL → **PASSES** (mechanism A) or delivers `wstrb=0` / no beat
  (mechanisms B/C).
- Plus, mandatory: a **normal peer write still lands byte-exact after the guard has
  fired**, and `synth_b_pending` is untouched throughout. Both were the missing
  assertions in the v1 review.

### 5.2 Then land TL-042 v2, rebased

Its blocker is gone (TL-043 did the LEVEL→PULSE conversion). Its patch needs a
rebase — hunk 3 collides with TL-043's rewrite of the same block. Its value is now
narrower (the `raw==1` residual, §3.5), so re-justify it before spending the bench
slot, and **first reproduce `raw==1`**: my `valid_mask` attempt produced a
hazard-full stall instead. That reproduction is the prerequisite; v2's own §9 lists
the same gap ("Silicon's causal ENTRY into the deadlock is still unidentified").

### 5.3 Only then, if anything is still open, revisit a synthetic-accept recovery

If §5.1 and §5.2 land, the remaining hole is narrow: the peer still loses the write
(SIGBUS is honest but the data is gone), and the wedge still costs one stall-timeout
window per transfer until the link recovers. A synthetic-accept recovery could close
that — but it must be redesigned, not resurrected:

- **must not mask the downstream valids** (§2.3) — it has to coexist with, not
  race, the upstream recovery;
- **must not reuse `synth_b_pending`**, or must change `wr_hold_drain_release`
  at `tidelink_top.sv:1999` in the same commit and prove TL-043's guard still fires
  in step (§2.4);
- **must terminate to the master honestly** — an OKAY for a payload the peer never
  received is worse than TL-037's SIGBUS;
- **must hold the accept across the whole flush** (the prototype's one durable
  finding — keep it);
- **must be burst-proven** (`wlast`, N synthetic Bs) and **hazard-drain-proven**
  (its own `hazard_add` entries, §2.2).

Given TL-037 already provides bounded liveness, my recommendation is that §5.3 is
**not worth doing before tapeout** unless a rig measurement shows the periodic-ERROR
mode is itself harmful.

### 5.4 Simulation matrix for whatever lands

| # | test | arm A (must fail) | arm B (must pass) |
|---|---|---|---|
| 1 | wedge → TL-037 ERROR → master releases → upstream recovers → check `s_axi_wdata` | `0xBAD0_BAD0` | `0xD0D0_0042` (A) or no delivery (B/C) |
| 2 | healthy write, no wedge | — | byte-exact (regression) |
| 3 | wedge, HWDATA held, recover | — | byte-exact (control stays green) |
| 4 | **burst** (`hburst=INCR4`) through the same sequence | — | every beat correct or none delivered; `ahb_sub_w_beat_consumed_o` unchanged |
| 5 | **non-bufferable** (`hprot[2]=0`) through the same sequence | — | same |
| 6 | normal peer write **after** the guard has fired | — | byte-exact |
| 7 | `synth_b_pending` never asserts during 1–6 | — | 0 cycles |
| 8 | existing gates | — | `sim_gate_axi_datanode_recovery`, `sim_gate_axi_datanode_gaps`, `test_tl002_wrhold_drain_guard`, `test_tl021_obs` all green |

Tests 4, 5, 7 are the ones the prototype never ran and the ones the v1 review named
as the reason a passing bench still shipped a hardware regression.

---

## 6. Traps encountered (carry these forward)

- **The prototype's base is not HEAD.** `tidelink_top_orig.sv` md5 `3eb9f53d…` vs
  today's `d88029d9…`. Any "control reproduces the bug" claim from
  `imp/hw_gate/tl042_recovery_proto/` must be re-run against the shipping flist
  before being believed. Mine is (§3.1) — and it does not reproduce.
- **Compile the shipping flist, not a shim.** This bench uses
  `flists/tidelink_fpga_v2.flist` unmodified, so there is no local copy that can go
  stale. The prototype's shim approach is sound for isolation but hides exactly the
  drift that invalidated its control.
- **`tidelink/deps/xhb500/generated` is now a real directory, not the tracked
  symlink** (git shows ` D deps/xhb500/generated`; the tracked blob is mode
  `120000` → `/home/dam1n19/SoCLabs/tidelink/deps/xhb500/generated`). The vendor
  sources read here are the ones the flist compiles. Nothing under `$IP_LIBRARY_ROOT/**`
  was read or written for the bridge analysis.
- **`rm -rf` the sim_build.** Done; full VCS recompile confirmed in `run_today.log`.
- **cocotb `all:` goal collision** — the prototype's `PROTO_RESULT.md` documents it
  correctly; this Makefile uses `today:` for the same reason.

---

## 7. Files in this directory

| file | role |
|---|---|
| `ASSESSMENT.md` | this document |
| `Makefile` | bench; compiles the **shipping V2 flist unmodified** + local tb |
| `test_downstream_wedge.py` | 6 tests: 3 findings, 2 controls, 1 negative probe |
| `tb_top.sv`, `pad_skid.sv`, `err_inject.sv` | copies of the recovery-suite harness (carry `TB042_WEDGE_HOOK`) |
| `log_test_*.log` | one clean log per test, all from a single fresh build |
| `run_today.log` | the full `make today` run incl. the VCS recompile |
| `EVIDENCE.txt` | RTL md5 + tidelink HEAD the results are pinned to |
| `tl042_recovery_proto.patch.copy`, `tl042_v2_proposed.patch.copy` | reference copies of the two prior candidates |

Reproduce:
```
cd /home/dam1n19/SoCLabs/nanosoc-ethernet-chiplet/tidelink && source ./set_env.sh
export CHIPLET_HOME=/home/dam1n19/SoCLabs/nanosoc-ethernet-chiplet
export TIDECHART_HOME=$CHIPLET_HOME/tidechart
cd $CHIPLET_HOME/imp/hw_gate/wedge_downstream && make today
```
`make today` is expected to stop on
`test_today_upstream_recovery_delivers_stale_wdata` — **that failure is the
finding**, not a broken bench.
