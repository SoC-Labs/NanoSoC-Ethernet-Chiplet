# System-Level Validation Test — BUILD SPEC (2026-08-08)

> Produced by an 8-agent workflow (4 proposers -> 3 second-opinion reviewers -> synthesis).
> Companion to `SYSTEM_VALIDATION_HOLES_REPORT_2026-08-08.md`. Implementation tracked separately.

---

# BUILD SPEC — eth-chiplet KR260 pair: new silicon tests (2026-08-08)

Synthesis of Proposals 1–4 with Reviews 1–3 applied. READ-ONLY session for spec authoring; the edits below are to be implemented in a follow-on write session. All addresses are SoC-internal; **PS-phys = `0x4_0000_0000 + addr`**. TLAPB base `0x2E03_0000`.

## Corrections applied globally (from the second opinions — non-negotiable)

- **CC-1 eye register:** the eye observable is **`0x21E8`** (`WINSCAN_EYE`, marker `0x25`, `best_run=[5:0]`, `lane_passed=bit13`, `lane_sel=[16:14]`), decoded by `winscan_read.py`. **`0x2150` is `SWI_FORCE_PHASE_EN` (a control reg) — never use it as an eye observable.** Fix in R2 and HYGIENE-1.
- **CC-2 `0x21F8` witness has no reader in the tree.** Every 0x21F8-keyed verdict must first read the reg and assert marker `(v>>24)&0xFF == 0xB5`; if absent emit `WITNESS-ABSENT`/`INCONCLUSIVE`, never PASS/FAIL on bits. This reader is net-new (built in the Phase-0 obs probe). `do_soak` does **not** sample 0x21F8 today.
- **CC-3 `regf_present` in every Region-F predicate.** `health_ok()` returns green when the Region-F marker `0xAD` is absent. Any "data_healthy=1" criterion must AND `regf_present`.
- **CC-4 metrics ≠ gates.** `writes-to-wedge`, `recovery_latency_s`, `MWTW`, Spearman ρ are report-only. Gating half must be a pre-registered threshold.
- **CC-5 chunk all read-soaks.** The board `/dev/mem` read has no internal timeout; a wedged peer read hangs the whole ssh invocation (backstop = `T_STREAM=120`). Break read loops into small board-side invocations (≤50 reads) with a Region-F gate **between** chunks from the dev host. "Per-read timeout" is not achievable.
- **CC-6 realistic thresholds:** `SOAK_FLOOR ≤ 2576` (demonstrated best), `LAND_FLOOR` pre-registered from the good-eye baseline, eye-floor a numeric `best_run` on `0x21E8`.
- **C1 injector-liveness method is broken as CRC-rise.** AXI-data FCSM nodes default `disable_crc=1` (`WlinkGenericFCSM*.v:713`), so an RX CRC counter will not rise even with a live injector. Use the **CRC-free proof**: inject a **data byte (byte>0)** on the W node, observe corruption via die_b-LOCAL `soak_fwd verify` mismatch. (byte0 flips are ECC-corrected + CRC-off ⇒ invisible.)
- **Dedupes:** P1-T5 ≡ P4-T2-2 (one ASIC negctrl sim gate). P1-T1 is the HW sibling of P4-T2-1 (sim burst read) — different tiers. P2 R-series ≡ P4 "adjacent TIER-1" — P4 Part A is the home for the TIER-1 recovery/reliability versions.

---

## TIER 1 — build + run THIS session (ranked, dependency-ordered)

Structural/hygiene gates first (make the suite honest), then wedge-safe write-plane, then injector precondition, then error path, then the wedge-prone read path, then recovery/reliability. All coverage orchestrators run on **mapstone-dev only**, drive boards over timeout-wrapped ssh, call `require_pair_fcsm4()` first, and stage JTAG-POR (`weekend/por_recover.sh` → fpgahub socket) on wedge. Every new board mode must emit a **distinct, collision-free `RESULT:` token** (regress parses by substring).

`SCR/` = `/home/dam1n19/SoCLabs/nanosoc-ethernet-chiplet/tidelink/pynq_host/scripts/`.

### 1. HYGIENE-2 — on-board script provenance gate `t_provenance`  *(gating, default-ON, run FIRST)*
- **Exercises:** detects stale/missing/orphan on-board scripts under `~/td/scripts/` — the confirmed cause of the "soak_fwd verify prints nothing" false result (repo `SCR/kr260_eth_soak_fwd.py:64` DOES print `VERIFY N/N`; drift is board-side).
- **Pass/fail:** for every repo `pynq_host/scripts/**/*.py` + `coverage/*.py`, dev-host `sha256sum` == board `sha256sum ~/td/scripts/...`. PASS ⇔ all MATCH. FAIL on any STALE/MISSING/EXTRA, listing filenames + hashes, exit non-zero.
- **Wedge-safety:** pure ssh + sha256, RO, cannot wedge.
- **Integration:** new mode `scripts_provenance` in `SCR/kr260_eth_run.sh` (near the `soak_write|soak_verify` case); `--scripts` section in `SCR/verify_deployed.sh`; new gating row `t_provenance` at top of `Suite.run()` in `SCR/kr260_eth_regress.py`, **before `t_link_*`**. Optionally `kr260_deploy.sh` writes `scripts.manifest.json` at stage time.
- **Sketch:** `ssh die sha256sum ~/td/scripts/*.py coverage/*.py` → diff against local `sha256sum`; emit `RESULT: PROVENANCE MATCH|STALE`.

### 2. Obs-plane presence probe `obs_probe`  *(new RO precondition, non-gating characterization)*
- **Exercises:** establishes which observables downstream tests are allowed to gate on. Builds the missing marker-gated readers.
- **Pass/fail (3-outcome per reg):** bring pair up, `require_pair_fcsm4`, then `poke read`:
  - Region-F `0x21E0` → marker `(v>>24)==0xAD` ⇒ `regf_present`.
  - Witness `0x21F8` → marker `==0xB5` ⇒ `witness_present` (gates all synth-B/stall legs).
  - Eye `0x21E8` → marker `==0x25` ⇒ `eye_present` (gates eye-floor / correlation).
  Emit a JSON of {present flags, decoded fields}. This is characterization, not a gate; but downstream gates consult its flags.
- **Wedge-safety:** RO config-plane; cannot wedge.
- **Integration:** new `SCR/eth_obs_probe.py` (reuse `eth_tlapb_poke.py read`, `winscan_read.py` decoder, `cov_common.decode_regf`); mode `obs_probe` in `kr260_eth_run.sh`. **Ships the marker-gated `0x21F8` reader** consumed by tests 7, 10, R1/R2/R3.

### 3. HYGIENE-3 — delivery-key the durable regression `t_soak`/`t_soak_rev`  *(gating, default-ON)*
- **Exercises:** re-keys soak verdicts on **bytes-landed**, not link health. Today `do_soak` gates FCSM/sticky/credit with readback off, so `mism=0` never enters the verdict (`kr260_eth_xfer.py:300`) — "PASS" means N writes were *issued*, not *arrived*.
- **Pass/fail:** sender runs `soak_write` (N distinct words → N offsets, CAM `0x2F→0x2D`), verifier runs `soak_verify` (die_b **LOCAL** read of all N, byte-check). PASS ⇔ `VERIFY N/N byte-exact` (rc 0) AND post-soak `xfer_health` Region-F clean **with `regf_present`**. Both directions (roles swapped). Add a **summary delivery-interlock**: top-line PASS requires ≥1 die-local delivery witness (`sram_fwd`/`soak_verify`/`mbox_recv`); else report `CONFIG-ONLY (delivery UNPROVEN)`, never bare green.
- **Wedge-safety:** all verdicts die_b-LOCAL reads (no link traversal on read) ⇒ verify cannot wedge.
- **Integration:** `SCR/kr260_eth_regress.py` `t_soak`/`t_soak_rev` (:232-237) and `summary()` (:287-295); reuses `kr260_eth_run.sh` modes `soak_write`/`soak_verify`.

### 4. HYGIENE-1 — invert regress to data-plane-ON by default  *(gating, default-ON, land LAST of the hygiene block)*
- **Exercises:** kills H1, the worst false-green — a bare `python3 kr260_eth_regress.py` runs config-plane-only and returns green moving zero bytes (`data_plane=False` at :110-111, gated block :272-283).
- **Pass/fail:** flip `data_plane=True`; replace `--data-plane` with `--config-only` (or `BooleanOptionalAction`→`--no-data-plane`). Keep `--include-peer-read` OFF (wedge-prone `sram_rtt` stays opt-in). **Safety interlock (mandatory):** before any peer traffic, gate on (a) `t_link_verify` FCSM=4 both dies, (b) **eye-gate reading `0x21E8` best_run** (NOT `0x2150`) against a pinned numeric floor + one `xfer_fc_health`. Below floor or dirty ⇒ auto-downgrade to config-only with a **loud WARN** (never silent green, never traffic onto a marginal eye). Gating data-plane set = wedge-safe only: `t_sram_fwd`, delivery soak (test 3), `t_mailbox`/`t_mailbox_rev`. On any wedge signature print the staged JTAG-POR block (`cov_common.por_stage`) and FAIL — no blind retry.
- **Wedge-safety:** the eye-gate + auto-downgrade is the interlock that legitimizes the flip; without it the default flip trades false-green for brick risk on a bad-eye POR.
- **Integration:** `SCR/kr260_eth_regress.py` `Suite.__init__` (:110), `run()` gate (:272-283), `main()` argparse (:300-315). **Depends on tests 1+3 landing first.**

### 5. P3-T3 — mailbox doorbell + interrupt-SOURCE latch `cov_mbox_irq_source`  *(gating, opt-in coverage, attended)*
- **Exercises:** first genuine interrupt-source latch on silicon. die_b `arm` (deassert MSG_VALID + W1C IRQ_STATUS, LOCAL) → die_a `send` (CAM `0x2F→0x23`, 4 payload words + MSG_VALID doorbell, peer WRITES only) → die_b `recv`/`clear` (LOCAL).
- **Pass/fail:** PASS ⇔ die_b `IPC_IRQ_STATUS[0]` at `0x2300_0028` reads **1** (latched from far MSG_VALID rising edge) AND the 4 slot words match AND W1C drops it 1→0. Self-diagnosing: `data_ok ∧ ¬irq_src` = a real edge-detect finding (or skipped `arm`).
- **Wedge-safety:** only `send` crosses (peer writes, HREADY return); arm/recv/clear die-local. FCSM=4-gated, POR-staged. MED.
- **Integration:** exists never-run: `SCR/coverage/cov_mbox_irq_source.py` + `cov_mbox_doorbell_irq.py`; host orchestrator sequences arm→send→recv→clear over timeout-wrapped ssh (`cov_common`).

### 6. P2-R3 — bounded delivery endurance soak `soak_endurance`  *(gating under --data-plane once floor pinned; else opt-in)*
- **Exercises:** endurance regression tripwire on the "genuinely good" write path (2576/2576 this session).
- **Pass/fail:** on a good-eye bring-up (pre-soak `0x21F8 stall==0` **if witness_present**, else skip that clause), run `soak_fwd write`+local verify in 200-beat chunks to `MAX_BEATS`(10000)/`MAX_WALL_S`/STOP. PASS ⇔ ≥ `SOAK_FLOOR` (**default 2576, not 5000**) byte-exact at 100%, zero Region-F fault (`regf_present`), stall==0 across all flight-recorder samples. If wedge before floor: no PASS, emit `beats_to_wedge` (report-only). Flight-recorder line per chunk {health, 0x21F8, 0x21E0, credit min/max}.
- **Wedge-safety:** write + die_b-LOCAL verify, bounded, FCSM=4-gated, timeout-wrapped, POR-on-wedge, no live-link re-bring-up. Lowest-risk of the endurance/recovery set.
- **Integration:** bounded wrapper over `SCR/kr260_eth_soak_fwd.py` + `campaign_iter` flight recorder; mode `soak_endurance` in `kr260_eth_run.sh`; feeds `weekend/dashboard.py`.

### 7. P3-T1 — prove-injector-live (CRC-free) `cov_injector_liveness`  *(gating precondition for the error family, attended, MED-HIGH)*
- **Exercises:** proves `0x003C` is a real corruptor, not RAZ/no-op — the un-vacuum-er. Without it, `cov_errinject_sweep` PASS and the DECERR-with-injection legs are **non-probative** (a no-op injector satisfies "die_a alive + die_b byte-exact").
- **Pass/fail (CORRECTED, C1):** arm TX-side injector on die_a for the **W node (id 0x81)** with **byte>0** (a data byte, `0x003C`: [24]=1 en, [7:0]=0x81, [15:8]=byte>0, [18:16]=bit); fire ONE peer write to `0x2F001000` with known payload; die_b **LOCAL** `soak_fwd verify` of that word. PASS ⇔ die_b read shows the corrupted (mismatched-at-byte>0) value ⇒ injector LIVE. FAIL/no-op ⇔ die_b byte-exact ⇒ injector not in bitstream ⇒ **declare `cov_errinject_sweep` + all injection-propagation legs vacuous and stop that branch.** (Do NOT use RX CRC-rise — AXI nodes default `disable_crc=1` at `WlinkGenericFCSM*.v:713`.)
- **Wedge-safety:** exactly one beat on a recovery-stripped AXI node (MED-HIGH); verdict is a die_b-LOCAL read (verifier can't wedge); refuse unless both FCSM=4; single-shot; POR-staged.
- **Integration:** new `SCR/coverage/cov_injector_liveness.py` beside `cov_errinject_sweep.py`, reuse `cov_common` (`inject`/`inject_off`, `require_pair_fcsm4`, `por_stage`). **Also fix or retire `do_errinject` (`kr260_eth_xfer.py:548-561,743`)** — it reads `fc_crc_of` on the injecting die (CRC rises at RX) and defaults `--node B` on die_a (which never TX's B) ⇒ structural false-`INCONCLUSIVE`.

### 8. P3-T2 — DECERR inbound confinement `cov_decerr_confine`  *(gating, opt-in coverage, attended, MED)*
- **Exercises:** malformed-target peer write is confined and doesn't corrupt legal region.
- **Pass/fail:** die_a seeds sentinel via `0x2F→0x2D`; reprogram CAM replace-byte to an EXCLUDED byte {0x2A,0x2C,0x2E}; fire poison peer write; die_b LOCAL-reads `0x2D001000`. PASS ⇔ access RETURNS (no hang) AND link healthy (`regf_present` ∧ data_healthy ∧ no wedge-sticky) AND die_b still reads the **sentinel** (never `0xDEADBEEF`). **Add the die_b reached-and-errored witness** (RX pkt-count delta or default-slave/AHB-error counter across the poison write) — without it this is a *non-corruption* check, not a *confinement* proof.
- **Wedge-safety:** single malformed write, die_b-local verdict, `require_pair_fcsm4`, POR-staged.
- **Integration:** exists never-run `SCR/coverage/cov_decerr_confine.py` orchestrating `kr260_eth_xfer.py --mode decerr/decerr_verify` (:398-460); add the witness read before the PASS.

### 9. P1-T4(write) — error-response propagation, write vector  *(gating on Region-F asymmetry, opt-in, attended, MED)*
- **Exercises:** far-slave BRESP=DECERR/SLVERR must **surface at die_a**, not be swallowed by the local synth backstop (§2.3, never tested).
- **Pass/fail:** die_a seeds sentinel via `0x2F→0x2D`, retargets CAM to an excluded byte (no inbound target), peer-writes POISON → die_b default slave DECERRs. PASS ⇔ access returns AND Region-F `tgt_resperr[20]` latches (far target saw error) AND `ini_resperr[21]` latches (die_a received it) — with `regf_present` — AND legal `0x2D` uncorrupted. **FAIL ⇔ `tgt_resperr` latches but `ini_resperr` never does** (far error swallowed = the exact hole). synth-B `0x21F8[8]==0` is a best-effort secondary leg, gated on `witness_present`; primary gate is the resperr asymmetry (already in `snap_health`).
- **Wedge-safety:** single bounded write, timeout-wrapped, FCSM=4-gated, Region-F fail-fast, POR-staged.
- **Integration:** extend `do_decerr` in `kr260_eth_xfer.py` to sample+assert `tgt_resperr`/`ini_resperr`; extend `cov_decerr_confine.py` to gate on propagation bits.

### 10. P1-T1 — cross-die READ soak, die_b-seeded `cov_cross_die_read_soak`  *(gating, opt-in coverage, attended, HIGH brick-risk — run in the wedge-prone block)*
- **Exercises:** first gated AR/R read-return on silicon (closes H2). die_b seeds its OWN SRAM (LOCAL write, safe); die_a programs CAM `0x2F→0x2D` and READS peer aperture `0x2F001000+k*4` over the link, byte-checking each returned word vs `golden(seed,k)`.
- **Pass/fail:** PASS ⇔ (a) die_b LOCAL pre-verify byte-exact all `win` words, AND (b) all N cross-die reads byte-exact, AND (c) Region-F healthy every sample (`regf_present` ∧ data_healthy ∧ no wedge/resperr), AND (d) no chunk timeout. FAIL ⇔ any mismatch / fault / timeout(=WEDGE). `reads-to-first-wedge` report-only (CC-4).
- **Wedge-safety:** seed+die_b pre-check truly safe; read loop is the wedge-prone half (the AR/R path that hung both boards 2026-07-29). **Chunk into ≤50-read board invocations with a Region-F gate between chunks** (CC-5); FCSM=4 guard; `gate_or_ladder()`/`recovery_ladder()`; bounded N; POR staged. Detect-and-stage, not wedge-proof.
- **Integration:** new board modes `seed_local` (die_b) + `read_soak` (die_a) in `kr260_eth_xfer.py` (reuse `golden`/`rd`/`program_cam_rule`); `kr260_eth_run.sh` cases `xfer_seed_local`/`xfer_read_soak`; new `SCR/coverage/cov_cross_die_read_soak.py` mirroring `cov_decerr_confine`.

### 11. P1-T3(word) — XHB read-window contract corners `read_corners`  *(gating, opt-in, attended, wedge-prone)*
- **Exercises:** read-side contract corners: (a) read-after-write same far word (RAW across link — read returns just-written value, proving B retired before R), (b) 8KB-fold alias (`0x2F000000` vs `0x2F002000` read equal), (c) unwritten far word == die_b-LOCAL read of same addr (self-consistent, not bus echo).
- **Pass/fail:** PASS ⇔ RAW read == last write AND aliased offsets read equal AND unwritten-word read == die_b-local read of that address, all with Region-F healthy (`regf_present`). Sub-word `hsize` and INCR burst reads are TIER-2 (backdoor is AHB-SINGLE-word).
- **Wedge-safety:** single bounded peer reads, each in its own timeout-wrapped invocation (CC-5); same guards as test 10.
- **Integration:** `read_corners` mode in `kr260_eth_xfer.py` (mirror `do_boundary` on the read side, reuse `_BOUNDARY_OFFS`/fold constants) + die_b `seed_local` precondition; orchestrate alongside test 10.

### 12. P1-T4(read) — error-response, read vector  *(gating on Region-F asymmetry, opt-in, run LAST — highest wedge risk)*
- **Exercises:** die_a peer-READs an undecoded far address → die_b returns RRESP=DECERR/SLVERR on R channel; assert it surfaces at die_a.
- **Pass/fail:** same `tgt_resperr[20]` vs `ini_resperr[21]` asymmetry (with `regf_present`); FAIL ⇔ tgt latches but ini never does (swallowed) OR hang/wedge.
- **Wedge-safety:** peer read to an undecoded addr = the brick core; single bounded, timeout-wrapped, POR staged. HIGH.
- **Integration:** `read_decerr` variant in `kr260_eth_xfer.py`.

### 13. P2-R1 — recovery-after-wedge gate `cov_recover_after_wedge`  *(gating, opt-in coverage, attended, `COV_AUTO_POR=1`, deliberately induces a wedge — run in a dedicated block)*
- **Exercises:** the missing §2.8 loop-closure: wedge → JTAG-POR → re-bring-up → data flows again.
- **Pass/fail:** drive wedge-safe soak to `WEDGE_CAP`(3000) or detected wedge (chunk timeout / `0x21F8 bit10`/`bit8` **if witness_present** / `health_snapshot` FAULT); if none, escalate a known fast-wedge inducer. Then: `por_recover.sh` the wedged die → wait ping+ssh → bilateral `bringup_pair_release.sh` on fresh dies → `soak_fwd write M`(512)+LOCAL verify → `health_snapshot`. PASS ⇔ (1) POR recovers (no PARK) AND (2) FCSM=4 both dies AND (3) M/M byte-exact AND (4) post-soak HEALTHY (`regf_present`, stall==0, data_healthy, no latched sticky). `recovery_latency_s` report-only.
- **Wedge-safety:** deliberately wedges but recovers via the documented JTAG-POR (`por_recover.sh` — flock, `MAX_POR`, PARK; `unjam_fc_node.sh` correctly refuses on KR260). Local-verify only, every access timeout-wrapped, single pair on mapstone-dev, never re-bring-up a live link. Net brick-risk LOW (POR always available).
- **Integration:** new `SCR/kr260_eth_recover_gate.py` (reuse `weekend/por_recover.sh` + `bringup_pair_release.sh` + `soak_fwd` + `health_snapshot`); mode `recover` in `kr260_eth_run.sh`; gating row `t_recover` (opt-in only).

### 14. P2-R2 — delivery-keyed reliability sweep `kr260_eth_delivery_reliability`  *(gating on land-rate floor, opt-in, attended, longest wall-time)*
- **Exercises:** quantifies the bring-up lottery as land-rate + MWTW and tests whether eye predicts it. Replaces the wrong-rig/wrong-metric Z2 `bringup_reliability.sh` (lock popcount).
- **Pass/fail:** N≥8 (default 12) independent bring-ups (`por_both→deploy→bringup_pair_release`); per fresh link capture pre-soak {**eye `0x21E8` best_run via lane-select + marker `0x25`** (NOT 0x2150), `0x21F8` if witness_present, `0x2108` fcsm/cal, Region-F} then fixed-budget `soak_fwd write K`(512)+LOCAL verify; classify LAND (≥`LAND_K` byte-exact, no wedge) vs DROP/WEDGE. PASS ⇔ land-rate ≥ `LAND_FLOOR` (**pre-registered from the good-eye baseline**, CC-6) AND N completed no PARK. Eye↔drop Spearman ρ + p emitted **report-only** (CC-4) with decision rule (|ρ|≥0.5 @ p<0.05 ⇒ eye predictive, else report the 0x21F8-witness classifier).
- **Wedge-safety:** each bring-up on fresh POR'd dies; per-access timeout=wedge; bounded soak; POR between; PARK after `MAX_POR`.
- **Integration:** standalone loop reusing campaign helpers; emit `reliability.jsonl` + `sweep.csv` → `weekend/dashboard.py`.

---

## TIER 2 — backlog (needs rebuild / firmware / re-strap / PHY / sim flist)

| Item | Exercises | Blocker |
|---|---|---|
| **ASIC-config negctrl sim** (P1-T5 ≡ P4-T2-2) | Run T1/T2/T4 sim analogues against the ASIC-V2 flist (recovery-STRIPPED, `socl_l7=0`) and assert they WEDGE/drop/swallow, while FPGA-V2 (with `local_overrides`) recovers. The H3 credibility gate; gates tapeout. | Sim only — parametrize `tidelink_axi_datanode_recovery/Makefile` with `BASE_FLIST`, drop the `sed` override (`:35-37`), invert expected verdict to an explicit cocotb timeout/assertion. **No silicon — actionable immediately in parallel.** |
| **TideChart Tier-1 sim** (P4-T2-4 sim half) | Deterministic root election → enum → route → role-consistency (root==master==GM). | Sim; **also fix the inverted "higher wins" expectation in `cov_tidechart_election.py`** (RTL: lower wins). No silicon — actionable now. |
| Cross-die READ-burst (P4-T2-1) | AR/R under INCR/WRAP bursts; fills the 32-deep `rFC_47x32` replay FIFO. | Backdoor is AHB-SINGLE-word; needs a burst-capable master (firmware/DMA) or a sim build. Sim half doable now via `verif/g2_soc_pair`. |
| PTP two-die link sync (P4-T2-3) | Clock-discipline servo across the real FC link; measure the convergence floor to retire the uncalibrated `PTP_TOL_NS=12000`. | `-ptp` bitstream rebuild + `phc_locked` un-tied. |
| TideChart HW election (P4-T2-4 HW half) | Root election / route / IRQ on silicon. | DEVICE_CLASS re-strap + rebuild; `force_root` not consumed in silicon RTL; G1 dual-root. |
| Ethernet MAC frame, integrated (P4-T2-5) | Real ARP/UDP frame through the assembled MAC. | Physical LAN8720 fit + RMII un-tie + rebuild (M2). |
| On-die M0 firmware bring-up (P4-T2-6) | Alive-signature `0xD00DFEED` at `0x2D00_1F08`. **Keystone** — unblocks T2-1(HW)/T2-7. | Firmware-load/SWD path + boot-gate release (rebuild). |
| Cross-die IRQ→ISR delivery (P4-T2-7) | die_a doorbell → die_b CPU1 ISR increments `RUN_COUNT` at `0x2D00_1F00`. | Firmware (T2-6) + boot-gate release + NVIC ISER. `COV_ISR_FORCE=1` dry-run validates wiring pre-firmware. |
| P1-T4 RTL byte-intact response | Actual RRESP/BRESP==2/3 arrives byte-intact on die_a `ahb_sub`. | Sim (hierarchical read of response code); PS plane can only infer via resp-err bits. |

**Dependency spine:** T2-6 (firmware) is the keystone. The two sim gates (ASIC negctrl, TideChart Tier-1) need no silicon — do them in parallel this session.

---

## Regression integration plan (`kr260_eth_regress.py`)

Concrete edits, in landing order:

1. **`t_provenance` (new, gating, default-ON)** — first row in `Suite.run()` before `t_link_*`. FAIL aborts the data plane. (HYGIENE-2, test 1.)
2. **Delivery-key `t_soak`/`t_soak_rev` (:232-237)** — re-key on `soak_write`→`soak_verify` (die_b LOCAL). Add the `summary()` (:287-295) **delivery-interlock**: top-line PASS requires ≥1 die-local delivery witness, else `CONFIG-ONLY (delivery UNPROVEN)`. (HYGIENE-3, test 3.)
3. **Invert the default (:110-111, :272-283, :300-315)** — `data_plane=True`; `--data-plane`→`--config-only`/`--no-data-plane`; add the FCSM=4 + **`0x21E8` eye-floor** pre-flight with loud auto-downgrade. Land LAST of the three, after 1+2. (HYGIENE-1, test 4.)
4. Add `regf_present` to every Region-F pass predicate the suite consults (CC-3).

**Gate policy per Tier-1 test:**

| Test | Default-ON gate | Opt-in gate | Rationale |
|---|---|---|---|
| 1 provenance | ✅ | | RO, cannot wedge; protects every other verdict |
| 2 obs_probe | (characterization, non-gating) | | RO; feeds present-flags |
| 3 delivery soak | ✅ | | die_b-LOCAL verify, wedge-safe |
| 4 data-plane-ON default | ✅ (with interlock) | | the flip itself; eye-gate legitimizes it |
| 5 mbox IRQ source | | ✅ (attended) | only writes cross; clean but attended |
| 6 endurance soak | ✅ once `SOAK_FLOOR≤2576` pinned | else opt-in | write-only + local verify |
| 7 injector-live | | ✅ (attended precondition) | one beat on recovery-stripped node |
| 8 DECERR confine | | ✅ (attended) | malformed-target write |
| 9 error-resp write | | ✅ (attended) | malformed write, resperr asymmetry gate |
| 10 read soak | | ✅ (attended, wedge-prone) | AR/R path, chunked, POR-ready |
| 11 read corners | | ✅ (attended, wedge-prone) | peer reads |
| 12 error-resp read | | ✅ (attended, run last) | undecoded peer read = brick core |
| 13 recover-after-wedge | | ✅ (attended, `COV_AUTO_POR=1`) | deliberately wedges |
| 14 reliability sweep | | ✅ (attended, long) | N≥8 POR cycles |

**Never** wire as gates: P1-T2 B-return and any 0x21F8-only leg (blocked until `witness_present` confirmed on the live bitstream — build as opt-in characterization); P3-T4 PS-GIC observe (3-outcome probe: moved=PASS / none=INCONCLUSIVE / error=FAIL; cannot PASS on this bitstream — only `tidechart_irq_o` is firmware-free and it's G1-blocked).

---

## Recommended run order this session (on a good-eye link)

**Phase 0 — preconditions, zero wedge risk (must pass before trusting any HW result):**
1. Build + run **test 1 provenance** — refuse to proceed on any STALE/MISSING.
2. Bring pair up (`bringup_pair_release.sh`), `require_pair_fcsm4`, run **test 2 obs_probe** — record `regf_present`/`witness_present`/`eye_present`. These flags gate what downstream tests may assert on.

**Phase 1 — sim credibility gates, no rig (in parallel, any time):**
3. **ASIC negctrl sim** (T2 item) — the H3 tapeout gate.
4. **TideChart Tier-1 sim** + inverted-expectation fix.

**Phase 2 — wedge-safe write plane (die_b-LOCAL verdicts, verify cannot wedge):**
5. Land **tests 3 → 4** (delivery-key, then flip default) into the regression; run `python3 kr260_eth_regress.py` — must now require bytes landed.
6. **Test 6 endurance soak** (SOAK_FLOOR≤2576) — write-path tripwire.
7. **Test 5 mbox IRQ source** — only `send` crosses.

**Phase 3 — injector precondition (attended, MED-HIGH, single-shot, POR-staged):**
8. **Test 7 prove-injector-live (CRC-free)**. If it cannot show liveness ⇒ mark `cov_errinject_sweep` + all injection-propagation legs **non-probative** and skip them.

**Phase 4 — attended error path (MED):**
9. **Test 8 DECERR confine** (with die_b reached-and-errored witness).
10. **Test 9 error-response write vector** (Region-F resperr asymmetry).

**Phase 5 — wedge-prone peer-READ return path (HIGH brick risk, dedicated attended block, JTAG-POR ready, chunked):**
11. **Test 10 read soak** → **test 11 read corners** → **test 12 error-response read vector** (last). Never LL-swreset one side of a live link (2026-07-29 self-deadlock); recover = JTAG-POR **both** via `por_recover.sh` then `bringup_pair_release.sh`.

**Phase 6 — recovery/reliability (deliberately wedges; safest recovery envelope; separate attended block on mapstone-dev, fpgahub socket reachable):**
12. **Test 13 recover-after-wedge** (`COV_AUTO_POR=1`) → **test 14 reliability sweep** (N≥8 POR cycles, longest wall-time).

Between every attended test: `health_snapshot.py` + `xfer_health` (fc_health) to pin the wedging node. All `coverage/*.py` run on **mapstone-dev only**, never on the boards.
