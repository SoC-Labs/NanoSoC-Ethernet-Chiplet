# HW validation plan — TL-042 v2 NO-HARM (KR260 two-board rig)

**Status:** QUEUED — awaiting David scheduling rig time. Peer is staying off the boards (uncontended).
**Owner:** this session (David's direct go via AskUserQuestion, 2026-08-14).

## 0. The claim under test — read this first
This is **v2 NO-HARM, NOT v2-fixes-the-wedge.** The round-2 + raw-probe ILAs proved the wedge has a
**second, independent hold** (`xhb_sub_hreadyout_raw = 0`, XHB500-internal) beneath `wr_hold_r`. v2 clears
only the `wr_hold_r` latch. So **a v2 bench run WILL still wedge on an inject — that is EXPECTED, not a
failed fix.** Do NOT run "does die_a survive errinject" as the acceptance test; signing v2 off on that would
reject a correct patch, and blaming a wedge on v2 would repeat v1's post-mortem error in reverse.

**Acceptance = v2 delivers byte-exact at the SAME rate as baseline on anchor-good runs.** That is the whole
claim v2 makes: it removes one latch and harms nothing.

## 1. Design
- **Interleave arms** — `baseline, v2, baseline, v2, …`. Never block them (v1's confound came from an n=1
  baseline vs an n=2 fix run back-to-back).
- **n ≥ 6 per arm minimum.** Baseline delivery-failure rate is ~15% (3/20), so anything smaller cannot
  separate a real regression from the baseline mode.
- **v2 arm build:** apply `imp/hw_gate/tl042_v2/tl042_v2_proposed.patch` (UNCOMMITTED; clean-applies to the
  submodule at the pinned commit). Baseline arm = pristine HEAD. md5-pin both bitstreams per run.

## 2. STRATIFICATION — the make-or-break variable (corrected 2026-08-14)
**Stratify on the ANCHOR PAIR, latched, printed by the bring-up script:**
- **`die_a re-anchored == YES AND die_b re-anchored == NO` → expect 0/16.** Exclude/report these runs
  separately — they fully determine delivery (Y/N was exactly runs 09/15/19; `N/N`×8 and `N/Y`×4 all
  delivered). If you don't stratify on this, the A/B measures the anchor lottery, not the patch.
- ⚠ **Do NOT stratify on `SWI_LANE_STATUS`** (the `0x2200_0000` mask). Those bits are `llrx_valid` [29] =
  `is_short_pkt` [25] delayed one clock (RX packet-classification, ECC-bypassed → a raw range test), and are
  **free-running / no stickiness** — a snapshot, not a verdict. Proof it misleads: run_06 PASSED showing the
  "bad" word `0x27890000` at bring-up, and all three real failures showed the "good" word at bring-up. Use
  the mask only as *secondary* corroboration, sampled at the *same* point as the original campaign.
- **The 15% baseline failure IS beacon starvation** (a positive-control sim reproduces the exact HW
  signature: die_a `reanchored=1`, die_b `reanchored=0`, `rx=[0,0,0,0]`). But the earlier `autonomy_retire_q`
  branch-2 hypothesis for *why* the beacon drops is **REFUTED on this vehicle** — branch-2's SET needs
  `nego_en`, and `nego_en=0` on kr260-eth-chiplet (`NEGO_CFG_RESET=7'h00` default, not overridden at
  `nanosoc_eth_chiplet.sv:760`; verified). ⚠ **Do NOT run a beacon-retire A/B on this rig — it would be an
  A/A.** (Branch-2 IS live on the standalone `kr260-pair-*` vehicle, which bakes `0x61` — do not conflate
  vehicles.) Current best directional candidate: **`reanchored` is a WITNESS that skew exists this power-up,
  not the cause** (`reanchored=1` + all-zero `lane_off` is datapath-bit-identical to `reanchored=0`) — it
  accounts for all four cross-tab cells including why `N/N` and `N/Y` pass. Unproven; not on the v2 path.

## 2b. Pre-campaign INSTRUMENT step (one-liner, do at campaign setup)
Log the FULL `EPOCH_STATUS 0x2140` word — bits `[6:1]` are `sr_span_meas` (the skew span), currently
discarded by the `& 1` mask at `kr260_eth_bringup.py:258,261`. Dropping that mask lets each run capture the
skew *span* alongside the binary anchor pair, so the stratifier can begin to explain itself (does a larger
span predict the Y/N failure?). NOT done now (avoid a dangling edit to the shared bring-up script + collide
with live peer agents) — do it as the first setup step when the rig is allocated.
**UPDATE 2026-08-17: ALREADY LANDED.** Commit `8d71ee2` made `kr260_eth_bringup.py` log the full word
(`sr_span_meas` at `:369`/`:382`), so this is now a *verify-don't-edit* no-op — the harness already captures
`span_a`/`span_b`. The old `:258,261 & 1` mask is gone; do not blind-edit those lines.

## 3. Delivery truth + harness gotchas (will corrupt the numbers if unfixed)
- **Delivery truth = LOCALMEM byte-exact verify.** The Region F sampler (`OBS_AXI_NODES 0x21E0`) was dead in
  all 20 overnight runs — **no `0xad800000` "ALL CLEAN" word means anything.**
- **Space the step-6c ssh polls.** ~25 back-to-back ssh sessions trip sshd's rate limiter right before the
  step-7 FCSM gate needs ssh; the resulting `rc=2` is **indistinguishable from a wedge** (18/20 errinject
  steps produced no data overnight for exactly this reason).
- **Decide vacuity from CSV CONTENT, never from harness status** (a never-triggered ILA core logs "no data"
  but the old flow printed "TRIGGER FIRED").

## 4. Lease discipline
`lease show` first; `lease acquire <board> --ttl N` as its **own** command, never chained with board ops;
release with the token at the end.

## 5. Prereqs
- Pull `origin/integ/tidelink-consolidated-2026-08-07` (@`7701335`) for the registry/build line.
- (David's to run, separately) `git push origin integ/tidelink-consolidated-2026-08-07:main` — clean FF.
