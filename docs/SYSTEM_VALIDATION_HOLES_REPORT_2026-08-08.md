# System-Validation Holes — nanoSoC eth-chiplet / TideLink / PHC / TideChart

**Date:** 2026-08-08. **Method:** five parallel read-only evaluation agents (verification + design)
across: HW+sim test-suite coverage, AXI-channel coverage, PTP+servos, TideChart system-level, and
system integration (with sub-probes on M0 firmware, ethernet MAC path, and the het eth↔compute pair).
**Scope:** what is actually validated vs. what is assumed, on the two-die KR260 pair.

---

## 0. Executive summary

The link's **cross-die WRITE path is genuinely good** (2576/2576 byte-exact this session on a
good-eye bring-up). **Almost everything else in the system is unvalidated or only paper-tested.** The
evaluation surfaced a consistent pattern: *the config-plane and the write data-path are exercised;
the return paths, the error paths, the time/identity layers, real software, and real I/O are not —
and several "gates" are green for reasons that don't move a byte.*

**The load-bearing holes (fix these first):**

| # | Hole | Why it matters |
|---|---|---|
| **H1** | The durable HW regression (`kr260_eth_regress.py`) ships with its **data-plane teeth OFF by default** (`--data-plane`/`--include-peer-read` opt-in) | A default "green" run verifies link/role/backdoor **config-plane only** — a data-drop (TL-001) regression passes without moving a byte. The most dangerous false-green. |
| **H2** | **No gated cross-die READ on silicon** | We've soaked writes; the read-return path is only a wedge-prone attended probe (hung both boards 2026-07-29). Read-return has ~zero silicon assurance. |
| **H3** | **The tapeout ASIC netlist ships the AXI FC nodes recovery-STRIPPED** (`socl_l7`=0) while every sim "recovers byte-exact" validates the *FPGA* recovery config | The recovery coverage is **vacuous for silicon** — the exact structural reason the B-return/read wedge survives on the die. |
| **H4** | **PTP has never synchronized on any board**; GM is register-pinned (no election); the strongest 2-die sim proof has no archived verdict | The entire time-transfer function is unproven on silicon and shaky in sim. |
| **H5** | **TideChart has never been driven at system level**; the one HW gate has never run; root==link-master==grandmaster is convention-only, asserted nowhere | The identity/routing layer is unverified in the assembled system. |
| **H6** | **Ethernet MAC never driven in the integrated chiplet; no LAN8720 ever fitted**; **M0 firmware has never executed integrated** (all testing is the PS backdoor) | "Ethernet chiplet" has never moved an ethernet frame or run on-die software as an assembled part. |

Everything validated so far is via the **PS `0x4_0000_0000` backdoor**, on the **write** channel, on
a **good-eye** bring-up. That is a narrow slice of the system.

---

## 1. What IS validated (the honest positives)

- **Bring-up / PHY calibration / eye-centering servo** — sim (extensive) + HW (the *only* HW-proven
  servo; link reaches FCSM=4 on KR260, per-lane eye-width readable at `0x2150`).
- **Cross-die WRITE (AW/W)** — sim (`g2_soc_pair`, `top_pair_v2`) + HW (2576/2576 byte-exact,
  eye-gated).
- **FC credit / backpressure** — sim + HW (credits close on KR260).
- **Config plane / observability / reg sweeps** — sim + HW (`cov_regplane`, `health_snapshot`).
- **Error confinement in SIM** — strong: `axi_datanode_recovery/gaps`, F-1/F-2/I5 backstops, synth-B.
- **PHC block + HA1588→PHC servo in SIM** — pass (block level, loopback).
- **AXI-node recovery fixes (Fix K / F-1 / F-2 / synth-B)** — sim + partial HW (write path).

## 2. The holes, by theme (prioritized)

### 2.1 Data-plane regression is default-blind (P0 — H1)
`kr260_eth_regress.py:277-282` skips sram/mbox/soak without `--data-plane`; readback needs
`--include-peer-read` (`:110,190`). The one durable regression can go green having moved **zero
bytes**. **Fix:** invert the defaults (data-plane ON, `--no-data-plane` to opt out). Lowest effort,
highest value.

### 2.2 Return paths untested on silicon (P0 — H2 + AXI audit)
- **Cross-die READ (AR/R):** sim covers a single word on the XHB AXI window only; the FIFO/mailbox
  `PKT_RD_REQ→RD_RSP` read engine is exercised **nowhere**. On HW it's wedge-prone/opt-in/non-gating
  (`kr260_eth_xfer.py:216`, `--soak-readback` off). **No gated read-return on silicon, ever.**
- **B-return** (the channel implicated in the die_a wedge) is only confirmed via die_b **local**
  reads; the B actually crossing back to die_a is never asserted on HW.
- The two-real-SoC `g2_soc_pair` sim is effectively **write-only** — its read-back and
  W-backpressure-drop tests were **skipped** in the last run, and there is no true cross-die read
  (die_a reading die_b's memory over the link).

### 2.3 Only single writes — bursts / errors / interleave / sub-word absent (P1 — AXI audit)
- **AXI bursts (AWLEN/ARLEN>0): never, anywhere.** All stimulus is AHB SINGLE, so the 32-deep W/R
  replay FIFOs (`wFC_37x32`, `rFC_47x32`) and the replay-across-burst path are completely unexercised.
- **SLVERR/DECERR propagated over the link (B/RRESP=2/3): never** — sim "ERROR" is the *local* I5
  backstop, HW DECERR is *local* decode confinement.
- **Interleaved/concurrent multi-channel (AW+AR, outstanding AR/R, ID interleave): never.**
- **Sub-word/unaligned reads: never.**
- **Verdict:** the suite would **not** catch a read-path, burst-path, error-path, or per-channel
  replay/CDC regression.

### 2.4 Sim recovery coverage doesn't match the tapeout netlist (P0 — AXI audit)
FC-replay node → channel map: **AW=`_1`, W=`_3`, B=`_5`** (a2l/TX), AR=`_7`, R=`_9`; TideLink
sideband/PTP=`_12/_13`. **Local overrides touch only `_12/_13`** — every AXI-channel replay node is
the pristine deps copy. Worse: **FPGA-V2** wraps FCSM 0-4 in `local_overrides` *with* watchdog/
recovery; **ASIC/tapeout-V2** ships FCSM 0-4 from **deps, recovery-STRIPPED** (`socl_l7`=0). Every
sim "recovers byte-exact" pass re-points to the FPGA config → **vacuous for the die**. (This is also
exactly where the a2l CDC wedge fix must land — see the a2l-port handover.)

### 2.5 PTP — never on silicon (P0 — PTP audit)
- **Link PTP has never synchronized on any board.** A timing-clean `-ptp` bitstream exists but the
  run has never been executed. `PTP_TOL_NS=12000` is an uncalibrated sim guess.
- The **strongest 2-die sim proof** (`test_ptp_link_sync.py`) has **no archived verdict**; the only
  *stored* link-PTP artifact is a **FAIL** (predecessor "Bug B"). UVM 3-chiplet chain compiles but
  never demonstrably passed.
- **No automatic grandmaster election** — GM/Sub is `SERVO_CTRL`-pinned. HA1588→PHC servo is sim-only
  (loopback; disciplines the RTC, not the timestamped MII event). `phc_locked_i` is tied 0 in every
  FPGA bitstream (HW can only run `force_en`). `docs/PTP_HW_TEST_PLAN.md` is referenced but **does not
  exist**.

### 2.6 TideChart — never system-tested (P0 — TideChart audit)
- The two-die `g2_soc_pair` harness is wired and role-strapped for TideChart but **never drives it**
  (0 references in the test). The one cross-die HW gate (`cov_tidechart_election.py`) has **never run**
  (blocked on a `DEVICE_CLASS` re-strap + rebuild; silicon still shows G1 dual-root; and the gate
  carries an **inverted** "higher wins" expectation vs the RTL where lower wins).
- **Role consistency (routing-root == link-master == PTP grandmaster) is asserted nowhere** — it's a
  strap convention, not enforced or tested. Multi-hop (≥3-node) enum/route/hop-count: entirely
  unverified. `tidechart_system` UVM env is a stub.

### 2.7 Ethernet + firmware — never integrated (P1 — system integration)
- **Ethernet MAC datapath** (frame TX/RX, DMA, MII/RMII) is proven at IP + standalone-subsystem level
  (sim, PHY model + PicoTCP, ARP/UDP echo in CI) — but in the **integrated chiplet it is never
  driven**: RMII tied off in every TB, HW uses `eth_ss_0` only as the AHB backdoor. **No LAN8720 ever
  fitted or driven.** Ethernet is a deferred milestone (M2).
- **On-die M0 firmware has never executed in the integrated eth-chiplet** — both cores boot-gated in
  sim and HW, no firmware-load/SWD path in the bitstream. Firmware ran only on the *bare* nanoSoC.
  **Consequence:** cross-die IRQ→ISR delivery, mailbox-driven IPC, and any software-in-the-loop
  behaviour are entirely unvalidated in the assembled system.
- **Het eth↔compute pair has never brought itself up anywhere** — the one green sim deliberately steps
  over the bring-up defect (F6: autoneg leaves Wlink held in reset after training); no two-board HW
  run has happened. (F6 is *not* a heterogeneity bug — it reproduces on the homogeneous pair the
  moment autoneg is armed. Compute now has a receive-only PS backdoor; address maps differ but are
  CAM-translated.)

### 2.8 No recovery/endurance gate; reliability measures the wrong thing (P1 — test-suite audit)
- **No recovery-after-wedge GATE** — `por_recover.sh`/`unjam_fc_node.sh` are tools; nothing asserts
  "wedge → recover → data plane works again." Given TL-009 wedges within ~4–50 writes on a bad eye,
  this is the missing endurance gate.
- **Reliability harnesses measure LOCK, not DELIVERY, on the wrong rig** (`bringup_reliability.sh`,
  `eye_toolkit` are R1/Z2 lane-lock; the actual R2 data-drop/wedge lottery is quantified only by the
  `weekend/` campaign). No eye-width↔drop-rate correlation; no delivery-keyed reliability gate.

### 2.9 HW corner-case gates never executed; false-green machinery (P1/P2 — test-suite audit)
- Every `coverage/` gate (DECERR confinement, error-injection, mailbox/doorbell IRQ **source**,
  cross-die ISR) was **written + syntax-checked on the dev host only — nothing run against the
  boards** (zero result artifacts in the tree). The error injector **may be a no-op** → vacuous
  "survive." **No interrupt has ever been observed on HW.**
- **False-green hazards:** `make -n sim_gate` can **fabricate PASS `.status` files** (a mixed-SHA
  "Frankenstein cohort" was reproduced); `test_04_descriptor_round_trip` is named "read round-trip"
  but is **two plain writes**; several `test_ei_*` are log-only probes mislabeled as coverage;
  silent-corruption asserts are env-neuterable with CRC off by default.
- **Deployed-board script drift:** the on-board `kr260_eth_soak_fwd.py` verify prints nothing (stale
  copy) — I had to read die_b SRAM directly this session. No on-board script provenance check.

---

## 3. Direct answers to the questions asked

**Have we tested the link PTP yet?** No — **never on silicon**, on any board. Sim only, and even the
best 2-die sim proof has no archived verdict (the only stored link-PTP run is a FAIL). A timing-clean
`-ptp` bitstream exists, unused.

**Have we exercised all channels properly?** No. **Writes (AW/W) only.** Cross-die reads (AR/R) are
wedge-prone and never gated on silicon; B-return is only checked via die_b-local reads; bursts,
error-response propagation, interleaved multi-channel, and sub-word/unaligned are untested anywhere.
And the tapeout netlist ships the FC nodes recovery-stripped, so the sim channel-recovery coverage
does not apply to the die.

**What system-validation holes with TideLink + the servos are untested?** Of the servos: the **link
PTP clock-discipline servo** (never on silicon; last integrated sim FAILED), the **HA1588→PHC servo**
(sim loopback only, tracks RTC not TSU, never crosses a real link/PHY), and the **PHC 2-source servo**
(block-only) are all HW-unproven; only the **PHY eye-centering servo** is HW-validated. System holes:
read-return, error propagation, recovery-after-wedge, IRQ-over-link delivery, mailbox IPC, and the
whole time layer.

**How should TideChart be tested at the system level?** Two tiers (the harness already exists for
Tier 1): **Tier 1 — two-die RTL sim** in `g2_soc_pair` (deterministic election → assert single root =
die_a; dual-root negative control; `force_root`; enum + distinct IDs over the real FC link; route to
peer; congestion telemetry crossing the link; IRQ edges; **and a role-consistency assertion that the
elected root == link-master == PTP grandmaster** — the property nothing tests today). **Tier 2 — the
HW gate** `cov_tidechart_election.py` (unblock: rebuild with the `device_strap`/`force_root` RTL, fix
the inverted expectation, run on both boards). **Multi-node** (≥3) sim for DFS enum recursion, LCA hop
counts, and transit forwarding — none of which a 2-die pair exercises.

---

## 4. Recommended roadmap (prioritized)

**Quick wins (days, high ROI):**
1. **Invert `kr260_eth_regress.py` to data-plane-ON by default** (H1) — the single most valuable fix.
2. **On-board script provenance check** in `verify_deployed.sh` (hash `~/td/scripts/*.py`) (H8/2.9).
3. **Run the existing `coverage/` gates on the boards**, after first proving the error injector is
   live (CRC-rise check) so DECERR/errinject aren't vacuous (H3/2.9).

**Silicon coverage (needs rig time):**
4. **Wedge-safe HW cross-die READ soak** (die_b seeds its local SRAM; die_a reads back over the link,
   byte-checks; Region-F fail-fast + JTAG-POR staging) — first gated read-return on silicon (H2).
5. **Recovery-after-wedge gate** — induce/await wedge → recover → re-verify byte-exact delivery;
   report mean-writes-to-wedge + recovery rate (H4, quantifies TL-009).
6. **Delivery-keyed reliability sweep** — N≥8 bring-ups, land-rate + eye-width↔drop-rate correlation
   (turns the eye lottery into a measured number) (H5).
7. **Execute the first-silicon PTP run** (`kr260-pair-ptp`), N≥8 bring-ups, and **measure the real
   convergence floor** to replace the sim-guess tolerance; author the missing `PTP_HW_TEST_PLAN.md`.

**Sim coverage (close credibility gaps):**
8. **ASIC-config recovery sim** — run `tidelink_axi_datanode_recovery` against the *ASIC-V2* flist
   (recovery-stripped) and expect the read/B tests to WEDGE — makes 2.4 explicit and gates tapeout.
9. **Cross-die READ + burst + error-response + interleaved tests** in `g2_soc_pair`/`top_pair_v2`
   (AR→R round-trip; AHB INCR/WRAP bursts to fill the 32-deep FIFOs; far-slave SLVERR/DECERR
   returning intact; concurrent AW+AR) (2.3).
10. **TideChart Tier-1 two-die sim** incl. the role-consistency assertion (2.6/§3).
11. **Archive `test_ptp_link_sync.py` + UVM chain verdicts**; wire **TideChart election → PTP GM** so
    the grandmaster is elected, not hand-pinned (2.5/2.6).
12. **Retire the false-green machinery** — kill the fabricated-`.status` path, rename/replace
    `test_04_descriptor_round_trip`, promote log-only EI probes to gates or out of "coverage" (2.9).

**Deferred but flagged:** ethernet M2 (real LAN8720 + firmware), on-die M0 firmware bring-up
(unblocks IRQ/ISR + mailbox validation), het eth↔compute F6 fix, PHY BIST wiring (TL-011), ASIC ECC
bypass (TL-006).

---

## 5. Appendix — reference maps

**FC-replay node → AXI channel** (both flists): AW `_1`(a2l)/`_?`(l2a), W `_3`/`_2`, B `_5`/`_4`,
AR `_7`/`_6`, R `_9`/`_8`, GeneralBus(AXIL) `_11`/`_10`, TideLink sideband/PTP `_13`/`_12`. Overrides
only on `_12/_13`. `_14/_15` compiled but unused in this config.

**Servos:** (1) link PTP clock-discipline `tidelink_ptp_servo.sv` — HW-unproven; (2) HA1588→PHC
`ha1588_servo.sv` — sim loopback only; (3) PHC 2-source MUX `phc.sv` — block only; (4) PHY
eye-centering calibrator — **the only HW-validated servo**; (5) FC-credit loop — closes on KR260.

**Companion handovers (tidelink/docs/):** `HANDOVER_RELIABILITY_EYE_GATED_2026-08-08.md`,
`HANDOVER_A2L_CDC_PORT_WEDGE_FIX_2026-08-07.md`, `HANDOVER_HW_RESULTS_FRAMING_WEDGE_2026-08-07.md`.
Bug registry: `tidelink/docs/BUG_REGISTRY.yaml`.
