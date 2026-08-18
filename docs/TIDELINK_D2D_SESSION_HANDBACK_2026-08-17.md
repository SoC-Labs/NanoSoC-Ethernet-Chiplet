# TideLink D2D silicon-bug validation — session handback (2026-08-17)

Durable consolidation of the TideLink die-to-die (D2D) validation thread: what was
found, what is **closed and verified**, what is **held by design**, and what is
**still open** — with the exact commits/pins so none of it evaporates. Two distinct
bugs came out of this campaign: **N1** (closed) and the **D2D write-wedge** (root-caused,
partially fixed).

---

## 1. N1 — read-backstop suppression  ·  STATUS: CLOSED + VERIFIED (both vehicles)

**Defect.** In `tidelink/src/rtl/tidelink_top.sv`, a coincident stuck **read** + stuck
**write** lets the write's `synth_b_pending` mask the read's AHB-ERROR backstop
(`~synth_b_pending` gates the err mux at ~:1898/:1906) while `sub_rd_os_r` is cleared
unconditionally and the re-fire sites are `if (sub_rd_os_r)` — so the read ERROR can
**never re-fire** → a real AHB master on that read hangs forever. Reachable from ordinary
**cross-page** traffic (the XHB500 hazard list is 4 KB-page-granular, so a read and a write
on different pages are not serialized). On the ASIC the FCSM recovery is stripped, so these
`tidelink_top` backstops are the **only** recovery — a masking bug that disables the read
escape has no fallback there. **Tapeout blocker.**

**Fix — `e008c58`** (`fix(tidelink_top): N1 — do not abandon a timed-out read whose ERROR
is masked`). Gates the read-backstop abandon on `(sub_wr_os_ctr == 0) && !synth_b_pending`:
a timed-out read whose ERROR is currently masked is **deferred one timeout window** (keeps
`sub_rd_os_r` set) instead of abandoned. Defer-not-ungate — the same shape as the correct
TL-042 fix.

**Verification (why this is closed, not just believed):**
- Defect reproduced **cycle-exact** by two *independent* sim attempts (no mid-flight
  exchange). N1 is a pure synchronous-digital bug → **sim is authoritative** (sim==silicon
  for this class), so no HW repro is required.
- Fix **sim-validated as recovering**: defer @expiry1 → drain → deliver ERROR @expiry2; the
  no-fix control hangs.
- Full `make sim_gate` **55 PASS / 0 FAIL / 3 XFAIL** with `CHIPLET_HOME`/`TIDECHART_HOME`
  set correctly (the 5 "fails" in the default submodule layout are a false-red harness
  artifact — see the memory note).
- **ASIC precondition verified implemented** (not just intended): the read-backstop
  self-heal at `ctr==1` needs `bready`, which depends on the XHB500 Q-channel being inactive.
  The eth-chiplet ASIC flist compiles this `tidelink_top.sv`; both XHB500 instances tie
  `clk_qreqn`/`pwr_qreqn = 1'b1` (`:2548/2552` sub-face, `:2569/2573` mng-face); **no** UPF
  or synth SDC in the eth-chiplet ASIC flow drives `qreqn` → the RTL tie is authoritative.
  Durable tapeout check: re-run that grep on the *shipping* build (a future different-top or
  a UPF that wires the Q-channel would re-open it).

**Landed.** `e008c58` is on `origin/main` (= `origin/integ/tidelink-consolidated-2026-08-07`
= `2c2f8d4`; the branch→main push was David's, done). It reaches the **parent** build via
the submodule-pointer bump below.

---

## 2. D2D write-wedge (TL-002 / TL-042)  ·  STATUS: root-caused; v2 = PARTIAL fix, held

**Symptom.** Injecting a cross-die peer-write wedges the initiator die (rc=124 hang).

**Root cause — TWO independent co-holds** on the `ahb_sub_hreadyout` priority override mux
in `tidelink_top.sv` (~:1890-1915), both driving HREADYOUT low on the `u_xhb_sub` side:
1. **rank5 `wr_hold_r`** — a tidelink-level data-phase latch. It sets on the injected write
   and sticks because the write's AW never accepts onto `s_axi`, so both of its clears
   (`W-last | synth_b_pending`) are dead.
2. **rank6 `xhb_sub_hreadyout_raw`** — the RAW HREADYOUT straight out of the XHB500
   `u_xhb_sub` bridge, measured **also 0** at the wedge (round-2 ILA), with `sub_stall_ctr_r`
   ramping 0→65536 and `ext_is_nonseq=0`. This is an **XHB500-internal** co-hold.

**v2 fix** removes the `wr_hold_r` latch. Reviewed sound + sim-validated (recovers the
`wr_hold` path) + gate-clean. **But it is NECESSARY-BUT-NOT-SUFFICIENT:** it does not touch
the rank6 XHB500 raw co-hold, so **a v2 build will STILL wedge on an inject.** That is
expected, not a failed fix.

**Held by design.** The v2 fix is **uncommitted** —
`tidelink/imp/hw_gate/tl042_v2/tl042_v2_proposed.patch` (clean-applies at the pinned commit).
It is both a partial fix and the v2-arm ingredient for the HW no-harm campaign; it is
deliberately NOT landed until the raw co-hold is understood and it has a full `sim_gate`.

**CHARACTERIZED (2026-08-17) — the raw co-hold is now understood.** Full trace in
`docs/DIAGNOSE_XHB500_RAW_HREADYOUT_LOW.md`: the XHB500 RESP FSM combinationally forces
`hreadyout=0` in state `SEQ_NSEQ` while `address_readyout=0`, which itself stays 0 because the
stage-1 AW register slice cannot drain until `awready` asserts — **there is no timeout, so it
hangs** until `awready` finally comes or the bridge is reset. The existing synth-B backstop is
**blind** to it: it arms on `sub_wr_os_ctr != 0` (= *accepted* AWs), and an AW whose `awready`
never asserts never increments that counter (verified against the RTL). A full fix must (i)
detect an AW presented-but-not-accepted (broaden arming ~`tidelink_top.sv:1878`) and (ii) act on
the s_axi side — force a synthetic AW/W accept and reuse the synth-B drain (hooks `:2512/:2532/:1894`),
or flush-reset just `u_xhb_sub` (needs a NEW gated reset off `:2479`, which today carries shared
`hresetn`) — paired with a legal AHB termination to the PS. **Still OPEN:** the *real* root — why
the downstream Wlink target stops asserting `awready` (the D2D link bug, upstream of the XHB500) —
and implementing + sim-validating the chosen wrapper recovery. XHB500 RTL is vendor read-only; the
wrapper fix goes through the local-override route, never the upstream IP.

**PROTOTYPED (2026-08-17) — Option 1 recovers in sim (proof-of-mechanism, NOT land-ready).** Isolated scratch
bench `tidelink/imp/hw_gate/tl042_recovery_proto/` (8-hunk patch vs a HEAD copy; shared `tidelink_top.sv`
md5-proven untouched). Control reproduces the hang; the fix recovers with a legal AHB **OKAY** termination
(`rose_at=966`, synth-AW@963, non-vacuous); the double-accept edge is masked (`dbl_aw=0 dbl_w=0`). **KEY
refinement for the owner:** a *one-shot* synthetic accept re-wedges — the wrapper's own address pipe
(`pipe_valid_r`/`pipe_hsel_r` holding `xhb_sub_hsel` high) re-latches the address into a phantom second AW, so
the accept must be **held across the whole flush** (`rec_active`). Before landing, close: multi-beat bursts,
the hazard-list `sub_wr_os_ctr` drain-to-0 (phantom-AW leak → make `rec_active` self-releasing), reconciling
the prototype's simplified synth-B clear with the shipped F-1/F-2 (`os<=1 & bready`) semantics, the
non-bufferable path, and an *organically* (not force-) wedged link. Approach confidence HIGH; current RTL LOW.

---

## 3. v2 HW no-harm campaign  ·  STATUS: queued, execution-ready

Plan: `docs/HW_VALIDATION_PLAN_TL042_V2.md`; the turnkey harness is delivered under `scripts/rig/`
(`run_tl042_v2_noharm.sh` one-command interleaved driver + `tl042_v2_arm.sh` + `tl042_v2_report.py` +
`TL042_V2_NOHARM_CHECKLIST.md`; reuses the existing `kr260_eth_*` rig scripts; §2b EPOCH step already landed
per `8d71ee2` — verify not edit; David owns the bitstream builds + md5 pins + leases). Gated on
David scheduling the KR260 pair. Design essentials (do not re-derive):
- **Acceptance = no-harm**: v2 delivers byte-exact at the **same rate as baseline** on
  anchor-good runs. **NOT** "does die_a survive an inject" — a v2 build still wedges by design.
- Interleaved arms (baseline, v2, …), **n ≥ 6/arm**; **stratify on the ANCHOR PAIR**
  (`die_a=YES ∧ die_b=NO → expect 0/16`, report separately), **not** on `SWI_LANE_STATUS`.
- **Delivery truth = LOCALMEM byte-exact** (the Region-F sampler is unreliable).
- First setup step: drop the `& 1` mask at `kr260_eth_bringup.py:258,261` to log
  `EPOCH_STATUS[6:1]` skew span (deferred to rig-time to avoid colliding with live agents).
- Do **not** run a beacon-retire A/B on this vehicle — `nego_en=0` on eth-chiplet makes it an
  A/A (branch-2 is live only on `kr260-pair-*`).

---

## 4. Verified vs open — at a glance

| Verified | How |
|---|---|
| N1 defect real (cycle-exact) | two independent sims |
| N1 fix recovers | directed sim (defer→drain→deliver) |
| N1 gate-clean 55/0/3 | `sim_gate` with CHIPLET_HOME set |
| N1 ASIC Q-channel tie implemented | flist + qreqn ties + no UPF/SDC override |
| Wedge = dual co-hold (wr_hold_r + XHB500 raw) | round-2 / raw-probe ILAs vs RTL |
| v2 removes the wr_hold latch | review + sim |
| Fusion-compiler re-land (`9d1b2ea`) moot for the parent | two independent repo derivations |

| Raw co-hold mechanism characterized (RESP-FSM hang; synth-B blind) | static RTL trace + wrapper-side re-check |
| Option-1 recovery proven-in-mechanism (control hangs, fix recovers, edge masked) | isolated cocotb scratch bench |

| Open | Owner |
|---|---|
| The *real* root: why the Wlink target stops asserting `awready` (upstream link bug) | peer / rig |
| Harden the Option-1 prototype to land-ready (bursts, hazard drain, self-release `rec_active`, F-1/F-2 reconcile) | peer / TL-042 owner |
| v2 HW no-harm on silicon | gated on rig (David) |
| v2 full `sim_gate` before any land | — |

---

## 5. Repo state / provenance (as of 2026-08-17)

- **Submodule** `tidelink` branch `integ/tidelink-consolidated-2026-08-07` = `origin/main`
  = **`2c2f8d4`**. N1 fix = **`e008c58`**. v2 fix = uncommitted patch (above).
- **Parent** `nanosoc-ethernet-chiplet` on `fix/tag-ram-gwen`: submodule pointer bumped
  `d317c98 → e21e274` in commit **`cd8b47d`** (local, **not pushed**) so the parent build
  carries the N1 fix as its sole build-RTL delta. Pin deliberately stops **before** `9d1b2ea`
  (fusion-compiler re-land, moot here) and before the v2 patch.
  - Revert if needed: reset `fix/tag-ram-gwen` to `cd8b47d`'s parent `5de5db5` (+ index re-sync).
- **Traps to remember:** the tidelink two-checkouts trap (only the submodule builds);
  concurrent sessions mutate both trees continuously (never `git add -A`; the submodule's live
  checkout sits *ahead* of the pin by other sessions' unpushed work — that's theirs to
  reconcile); `sim_gate` false-red in the default submodule layout.

## 6. See also
- `docs/DIAGNOSE_HREADYOUT_LOW_u_xhb_sub.md` — the wr_hold wedge handback (round-2 resolution).
- `docs/DIAGNOSE_XHB500_RAW_HREADYOUT_LOW.md` — the raw co-hold characterization (in progress).
- `docs/HW_VALIDATION_PLAN_TL042_V2.md` — the v2 no-harm campaign design.
- Memory: `n1-readbackstop-suppression-tapeout-blocker`, `tl009-wedge-is-a2l-cdc-selflatch`,
  `peerwrite-drop-is-phy-framing`, `sim-gate-false-red-submodule-layout`.
