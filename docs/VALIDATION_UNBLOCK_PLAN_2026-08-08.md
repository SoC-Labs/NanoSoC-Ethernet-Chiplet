# Plan — unblock the remaining hardware validation

Companion to `docs/SYSTEM_VALIDATION_HOLES_REPORT_2026-08-08.md`, `docs/HW_LOOP_RESULTS_2026-08-08.md`,
`docs/SYSVAL_TEST_BUILD_SPEC_2026-08-08.md`. Principle: **unblock the root blockers, not the tests
one-by-one, and bundle RTL/strap changes into a single rebuild** so one build cycle unlocks a whole
wave.

## Blocker → tests map

| Root blocker | Tests unblocked | Work | Owner | Rebuild |
|---|---|---|---|---|
| Eye lottery / link reliability | cross-die READ, endurance, mailbox-data, injector→errinject, reliability land-rate, recover-after-wedge | a2l CDC port (survivable bad eye) + RX-word-clock SDC | tidelink agent + ASIC | yes (1, shared) |
| DEVICE_CLASS strap (G1 dual-root) | TideChart HW election | re-strap die_b / device_strap-from-role | eth-chiplet | same build |
| `-ptp` bitstream + `phc_locked` | PTP two-die sync (servo) | deploy existing `-ptp` + run PTP demo | eth-chiplet | no (exists) |
| Firmware-load path + boot-gate | M0 execution, cross-die IRQ→ISR, AXI bursts, error-resp propagation | SWD/boot-gate RTL + firmware | eth-chiplet + fw | yes (big) |
| Physical PHY / het | ethernet MAC frame (M2), eth↔compute | LAN8720 fit; F6 fix | eth-chiplet / tidelink | yes |

## Waves

**Wave 0 — no rebuild (do now; rig items queue for a free board):**
- 0.1 Good-eye harness: bounded re-bring-up until a good-eye draw (canary lands), then run the full
  Category-A battery (reads/endurance/mailbox-data/injector→errinject) on that draw. Validates the
  reliability-gated tests without any RTL fix — needs only a good-eye draw (morning-class).
- 0.2 Config-plane FAIL triage: root-cause `cov_regplane_sweep` + `cov_obs_health_gate` (eye-
  independent → possibly real bugs).
- 0.3 Sim gates: land Agent C ASIC-negctrl (no rig); Agent D TideChart Tier-1 already PASS.

**Wave 1 — the converged rebuild (critical path):** bundle a2l CDC port + DEVICE_CLASS re-strap
[+ RX-word-clock SDC] into ONE build → one bench unlocks reliable Category A AND TideChart HW election.

**Wave 2 — PTP:** deploy the timing-clean `kr260-pair-ptp` bits, un-tie `phc_locked` (or `force_en`),
run the PTP demo → two-die sync / servo offset convergence. Better: fold PTP-enable into Wave 1.

**Wave 3 — firmware path:** SWD/firmware-load + boot-gate release RTL + firmware → M0 execution,
cross-die IRQ→ISR, and (via DMA/burst master) AXI bursts + error-response propagation.

**Wave 4 — physical/het:** LAN8720 fit + RMII un-tie (M2); F6 fix + compute bitstream (het pair).

## Action RESULTS (agents, 2026-08-08 late) + corrections
Rig was in use by the tidelink agent → all HW execution QUEUED; the five agents actioned off-rig:
- **A — TideChart root: NO re-strap needed.** The device-strap tiebreak is wired in RTL (`640b700`,
  `nanosoc_eth_chiplet.sv:880` → `election_fsm:310`) AND in the deployed `2c249ec` bits — die_a is the
  deterministic root by design (both dies keep `DEVICE_CLASS=0x0001`; die_a's `random_id` is lower).
  The HW "G1" is a **gate false-positive** (`cov_tidechart_election.py:254` keys on `DEVICE_CLASS`
  equality). **Unblock = patch the gate to assert on `TC_RANDOM_ID[15:8]` + a rig check that
  `role_strap` differs on the two boards. No rebuild.** (elab clean.)
- **B — RX-word-clock SDC: APPLIED** to `ASIC/genus-innovus/inputs/tidelink_constraints.sdc` (8
  phase-aligned generated clocks; git-clean file, edited directly; parent `constraints.sdc` left to the
  ASIC session). syn_eval verification deferred (Genus-license contention) — predicted 16,653→~0;
  follow-up `set_clock_groups -asynchronous` for the lane↔lane / word↔capture CDC. **NB this is the
  ASIC-tapeout timing fix; the FPGA rig eye needs the *FPGA-XDC* equivalent (+rebuild) as a follow-up.**
- **C — Config triage:** `cov_obs_health_gate` = **FALSE FAIL** (gate crash from the `sudo -S` prompt
  corrupting its parse; fix `cov_common.py`→`sudo -S -p ''`; obs was healthy). `cov_regplane_sweep` =
  **real, transient** config-write PS-bus wedge (TL-026 ruled out); offset lost in the log — full-
  capture re-test recipe provided.
- **D — Harness BUILT:** `run_categoryA_goodeye.sh` (Wave-0) + `run_ptp_pair.sh` (Wave-2), both
  `bash -n` clean, wedge-safe, token-scoped release. **PTP correction:** the `kr260-pair-ptp` `.bin`
  does NOT exist (only `-nptp` output) → **Wave 2 needs a BUILD**, not a no-rebuild deploy.
- **E — Firmware UPGRADE:** on-die **CPU0** M0 firmware likely runs on the **current bits, no rebuild**
  — backdoor-preload CPU0 IMEM (`0x4_1000_0000`) + release the gate (`0x4 → 0x4_2900_0000`) + read back
  `0xD00DFEED` (sim-proven mechanism). Cores are asymmetric (CPU1 always-on, only CPU0 gated); cross-die
  ISR path = CPU0 mailbox slot1 (not CPU1). Design: `docs/FIRMWARE_ENABLE_DESIGN_2026-08-08.md`.

## Meta-finding: harden the test layer (kill false verdicts)
Three independent **false-verdict gate bugs** surfaced — the TideChart `DEVICE_CLASS` false-positive,
the obs-health `sudo`-prompt parse crash, and the HW-loop classifier's LAND-substring false-PASS
(already fixed). Systemic fix: `cov_common.py` → `sudo -S -p ''` + prefix-tolerant gate parsers. This
is the same "no false green/red" discipline as H1, one layer up.

## Corrected build dependencies
- **TideChart HW election:** no rebuild (gate patch + strap-diff rig check).
- **Firmware P0–P2 (M0 alive → gate release → cross-die ISR):** no rebuild (backdoor preload), modulo a
  one-time CPU0-bootrom-style check.
- **Reliable Category A:** needs the **a2l CDC port** (tidelink) → one converged FPGA build (+ optionally
  the FPGA-XDC RX-clock constraint). TideChart no longer rides this build.
- **PTP:** needs a **`-ptp` FPGA build** first, then the run.

## Queued rig sequence (token-scoped lease only — never `board lease revoke` on shared `dam1n19`)
1. `run_categoryA_goodeye.sh` — Wave-0 reads/endurance/mailbox/injector→errinject on a good-eye draw.
2. Firmware **P0** (no rebuild): backdoor-preload CPU0 alive app → gate release → read `0xD00DFEED`.
3. `cov_regplane_sweep` full-capture re-test — pin the wedge offset.
4. `cov_tidechart_election` with the corrected gate — confirm die_a root + strap differentiation.
5. After the a2l port + one converged build: Wave-1 reliable Category-A bench.
6. After a `-ptp` build: `run_ptp_pair.sh` (Wave-2 PTP sync).

## Ownership
tidelink agent: a2l CDC port, F6. ASIC session: RX-word-clock SDC close. eth-chiplet (me): re-strap,
converged-build orchestration, harness, PTP deploy, config triage, benching, firmware path.
