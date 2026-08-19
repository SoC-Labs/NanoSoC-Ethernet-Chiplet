# TL-042 v2 NO-HARM — rig pre-flight checklist

Turnkey harness for `docs/bringup/HW_VALIDATION_PLAN_TL042_V2.md`. Read the plan §0 first:
this is **v2 NO-HARM, not v2-fixes-the-wedge**. Acceptance = v2 delivers
byte-exact at the **same rate as baseline on anchor-good runs**. A v2 build
**will still wedge on an inject — that is EXPECTED**, and this harness injects
nothing.

Runner: `scripts/rig/run_tl042_v2_noharm.sh` (one command once md5s are pinned).
Per-arm body: `scripts/rig/tl042_v2_arm.sh`. Report: `scripts/rig/tl042_v2_report.py`.

---

## A. Build + stage the two bitstreams (NOT automated — do before rig time)

The runner **selects and md5-pins** pre-built images; it never builds one.

1. [ ] `git -C tidelink fetch` and check out the pinned build line
       (`origin/integ/tidelink-consolidated-2026-08-07`, plan §5). Confirm the
       submodule is clean.
2. [ ] **baseline image** = pristine submodule HEAD. Build `tidelink.bin`
       (normal) and its `-flip` variant.
3. [ ] **v2 image** = HEAD **+** `tidelink/imp/hw_gate/tl042_v2/tl042_v2_proposed.patch`.
       `git -C tidelink apply --check imp/hw_gate/tl042_v2/tl042_v2_proposed.patch`
       (must clean-apply at the pinned commit), apply, build normal + `-flip`,
       then **`git -C tidelink checkout -- src/rtl/tidelink_top.sv`** to restore
       pristine before the baseline build (or build in separate worktrees).
4. [ ] Stage on the boards, per board, so the arm script can select them:
       - die_a (kr260-01, 10.22.24.159): `td/tl_arm_baseline.bin` (normal),
         `td/tl_arm_v2.bin` (normal)
       - die_b (kr260-02, 10.22.24.153): `td/tl_arm_baseline.bin` (**-flip**),
         `td/tl_arm_v2.bin` (**-flip**)
5. [ ] `md5sum` each staged file and record the **four** pins (die_a and die_b
       run DIFFERENT images, so A != B per arm):
       `MD5_BASELINE_A MD5_BASELINE_B MD5_V2_A MD5_V2_B`.
       (Optional provenance: `make_bitstream_manifest.sh` alongside each `.bin`.)

> The arm script re-verifies md5 **every run** and aborts on mismatch — this is
> the plan's "md5-pin both bitstreams per run", and it catches a board image a
> concurrent session swaps mid-campaign.

## B. Lease discipline (human/rig session only — the harness NEVER touches leases)

Both boards, plan §4: `show` first, `acquire` **as its own command, never
chained** with a board op, release with the token at the end.

6. [ ] `fpgahub pair lease show kr260_01` and `... kr260_02` — confirm free (or
       that a "leased by dam1n19" lease is actually **yours**, not a concurrent
       agent's; do NOT force-revoke — memory: shared-user lease revoke trap).
7. [ ] Acquire, one command each, capture the token:
       `fpgahub pair lease acquire kr260_01 --ttl <sec> --json`
       `fpgahub pair lease acquire kr260_02 --ttl <sec> --json`
       (Budget the TTL for the whole campaign: ~3–11 min/run x 2 arms x n, plus
       slack. n=6/arm ~ allow 90+ min.)
8. [ ] Export `KR260_PASSWORD` in the rig shell.

## C. Deferred EPOCH_STATUS span instrument (plan §2b) — VERIFY, likely already landed

The plan says to drop the `& 1` mask at `kr260_eth_bringup.py:258,261` so each
run logs `sr_span_meas` next to the binary anchor bit.

9. [ ] **Check first — do not blind-edit.** The deployed recipe already prints
       `EPOCH_STATUS = 0x.. (reanchored=%d sr_span_meas=%d)` (bring-up script
       lines ~376–383; `anchor_pair_gate.py` confirms this landed in commit
       `8d71ee2`). Lines **258/261 are now the CRC-readback print**, not an
       EPOCH mask. So this edit appears to be a **no-op already applied**:
       `grep -n sr_span_meas tidelink/pynq_host/scripts/kr260_eth_bringup.py`.
       - If `sr_span_meas` is present → nothing to do; the harness already
         captures the span into `span_a/span_b` in RUNS.tsv.
       - If it is somehow absent on the deployed board copy → make the one-liner
         edit to keep the full EPOCH word, redeploy the recipe, and note it.
       Either way, **do not** collide with a live peer agent editing this shared
       file — coordinate before touching it.

## D. ssh-poll spacing (plan §3)

10. [ ] Leave `SSH_GAP` (arm) and `RUN_GAP` (driver) at defaults. ~25
        back-to-back ssh sessions trip sshd's rate limiter and the `rc=2` looks
        identical to a wedge. This NO-HARM harness deliberately **omits** the
        25-poll Region F liveness loop entirely and spaces every discrete
        session. Don't add ad-hoc ssh loops during the run.

## E. LOCALMEM is the only delivery truth (plan §3)

11. [ ] Delivery pass/fail = die_b `VERIFY n/16 byte-exact` (a LOCAL SRAM read,
        cannot wedge). The Region F / `OBS_AXI_NODES 0x21E0` word is logged
        **informational only** — **no `0xad800000` "ALL CLEAN" means anything**.
        Do not override a LOCALMEM fail with a green Region F word.

## F. Run the campaign (one command)

12. [ ] Dry-run the plan (touches nothing):
        `DRY_RUN=1 KR260_PASSWORD=… MD5_BASELINE_A=… MD5_BASELINE_B=… MD5_V2_A=… MD5_V2_B=… \`
        `  bash scripts/rig/run_tl042_v2_noharm.sh 6`
13. [ ] Launch (interleaved baseline,v2,…, n>=6/arm, never blocked):
        `KR260_PASSWORD=… MD5_BASELINE_A=… MD5_BASELINE_B=… MD5_V2_A=… MD5_V2_B=… \`
        `  bash scripts/rig/run_tl042_v2_noharm.sh 6`
        Knobs: `SOAK_N` (default 16, matches the n=20 campaign window),
        `BRINGUP_TRIES` (link-up retry budget, anchor NOT gated), `RUN_GAP`,
        `OUTROOT`.

## G. During the run

14. [ ] Watch `driver.log`. Each run appends a row to `RUNS.tsv`. A run that
        never links up records `linkup=0 delivery_pass=VOID` (excluded, not a
        failure). A md5 mismatch aborts that arm — **stop and re-stage**, don't
        let it pool.
15. [ ] Sanity: `anchor pair` should vary across runs (the lottery). If every
        run shows the same pair, suspect a stuck rig, not a real signal.

## H. Read out + tear down

16. [ ] The driver prints the stratified table and writes `REPORT.txt`. Re-run
        any time: `python3 scripts/rig/tl042_v2_report.py <OUTROOT>/RUNS.tsv`.
        Read §5 NO-HARM verdict; heed the small-n caveat if the anchor-good
        population is thin after exclusions.
17. [ ] **Release both leases with their tokens** (plan §4):
        `fpgahub pair lease release kr260_01 --token <TOK_A>`
        `fpgahub pair lease release kr260_02 --token <TOK_B>`

---

## Plan-step → script/CLI map (what exists vs. new glue)

| Plan item | Where it lives | Status |
|---|---|---|
| Interleave baseline/v2, n>=6/arm, never blocked | `run_tl042_v2_noharm.sh` | **NEW glue** (no interleaved baseline-vs-v2 *delivery* runner existed; the n=20 overnight was baseline-only, and `imp/hw_gate/repeat_ab.sh` is errinject/signature-focused) |
| Per-arm POR→md5-load→AFI→bring-up→delivery | `tl042_v2_arm.sh` | **NEW glue** (adapted from `imp/hw_gate/tl035_ab.sh`, stripped of the errinject/Region-F path) |
| md5-pin both bitstreams per run | `tl042_v2_arm.sh` step 2 (pins passed by driver) | Existing idiom (`run_arm.sh`/`tl035_ab.sh`); md5 values = **your TODO** |
| Concurrent pair bring-up + link-up retry | `kr260_eth_bringup_pair.sh` (ANCHOR_GATE_MODE=off) | **Exists** — reused as-is |
| Anchor-pair latch (reanchored + sr_span) | `anchor_pair_gate.py` + `kr260_eth_bringup.py` EPOCH log | **Exists** — reused; span already logged (see §C) |
| Stratify on anchor pair; YES/NO cell separate | `tl042_v2_report.py` | **NEW glue** |
| Delivery truth = LOCALMEM byte-exact | `kr260_eth_soak_fwd.py` (`soak_write`/`soak_verify` via `kr260_eth_run.sh`) | **Exists** — reused as the verdict |
| Region F untrusted / informational only | `tl042_v2_arm.sh` step 7b (logged, never scored) | Honored |
| ssh-poll spacing | `SSH_GAP`/`RUN_GAP`; 25-poll loop omitted | Honored |
| EPOCH span instrument (drop `& 1`) | checklist §C | **Appears already landed** — verify, do not blind-edit |
| Build the two bitstreams | — | **NOT automated** (Vivado, hours) — checklist §A prerequisite |
| Lease show/acquire/release | checklist §B/§H | **Human only** — encoded as steps, not in the harness |
