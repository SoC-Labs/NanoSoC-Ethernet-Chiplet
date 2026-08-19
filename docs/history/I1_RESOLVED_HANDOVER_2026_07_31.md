# I1 eth-chiplet bring-up regression — RESOLVED on silicon (2026-07-31)

**TL;DR:** The I1 regression is **fixed on hardware with the recovery FCSM in place** (no
deps-revert). The eth-chiplet KR260 pair brings up **`cal_done=1 fcsm=4 cr_seen=1
crack=1` on both dies**, from cold (POR→deploy→bring-up), and the link **carries D2D
traffic byte-exact (6/6, including the isolated doorbell `0x00000001`)**. The prior
"below-RTL / timing-wall" verdict is **overturned**: I1 was **two bring-up *sequencing*
bugs**, not a footprint/timing effect. No netlist timing change was needed.

---

## Root cause — two stacked sequencing bugs (neither is timing)

1. **Calibrator never armed on the override.** `role_lock`/`training` never asserted, so
   the winscan calibrator never started (`fcsm=0`). Fixed by **`SELF_ARM_TRAIN_EN`** (RTL,
   default-off, `local_overrides/axi_chiplet_controller.sv`): latch role-lock on the SW
   `ROLE_CFG` write. Silicon-proven — advances `fcsm 0→1`, calibrator runs to S_HOLD.
   Sim regression `i1_selfarm_rolelock` **PASS**.

2. **Training-hold self-deadlock (the real "cr_seen=0").** `S_HOLD(6)→S_VALIDATE(9)` is
   gated at `tidelink_phy_align_calibrator_v2.sv:1499` on
   `hold_ctr >= HOLD_MAX && !swi_training_mode_r` — **NOT `cr_seen`, NOT full lane-lock.**
   The bring-up recipe **held `SWI_TRAINING_MODE=1` while polling `cal_done`**, but
   `cal_done` needs `S_HOLD→S_VALIDATE→S_DONE`, which needs training **released**. So the
   die parked in S_HOLD forever (`cal_state=6 fcsm=1 cr_seen=0`). This *masqueraded* as a
   "sideband CR won't capture" timing wall. It is a PS-side ordering bug.

**FIX-E recipe:** arm → poll winscan `in_hold` (S_HOLD reached) → **bilaterally release
`SWI_TRAINING_MODE=0`** → `S_VALIDATE` (hold_ctr already expired) → `VAL_TIMEOUT_TO_DONE=1`
forces `S_DONE` → `cal_done=1` → `fcsm=4`. `cr_seen`/`crack` go `0→1` the instant the link
enters data mode — exactly as the clean-link sim predicted.

### Why the prior investigation was misled
- `cr_seen` is a **pure sideband-RX capture sticky** (`WlinkGenericFCSM_6`, matches
  `data_id==0x44`, the *correct* sideband CR id). It was read as "the CR can't capture →
  below-RTL margin." In fact the calibrator never *reached* the state where the CR is
  evaluated, because training was held.
- The `L6=32`/emit-gate hypothesis is **refuted 4 ways** (structural, clean-sim state=4,
  trust-gate, and tonight's fcemit obs showing emit fully healthy). It gates AXI-node TX,
  not the sideband RX sticky — irrelevant to `cr_seen`.
- The clean-link sim (`cocotb/tidelink_fcsm_silicon_ratio`) reached `state=4` because it
  **never modeled the `swi_training_mode` hold** — so it was blind to this deadlock. That
  blindness is the direct cause of the "below-RTL" misdiagnosis. A new regression closes
  the gap (see below).

---

## Evidence (KR260 eth-chiplet pair, recovery FCSM override, gate=32)

| Check | Result |
|---|---|
| Cold repro POR→deploy→orchestrated bring-up | **both dies `cal_done=1 fcsm=4 cr_seen=1`**, `SWI_LANE=0x05890000`, stable |
| `kr260_eth_regress` | **link PASS (FCSM=4 both)**, role PASS, tidechart PASS |
| D2D data plane | **6/6 byte-exact** isolated crossings incl `0x00000001` (T2 doorbell) |
| SELF_ARM sim | `i1_selfarm_rolelock` **PASS** (113s) |

**Not I1 (pre-existing, flagged separately):** `kr260_eth_regress` **backdoor FAIL** — the
PS→`eth_ss_0` boot-ROM backdoor drops **bit 27** on the reset/NMI/HardFault vectors
(reads `0x000001xx`, expects `0x080001xx`; init-MSP reads clean). This is the eth
subsystem's PS backdoor aperture, **orthogonal to the TideLink link** (fails link-up or
link-down), untouched by this work.

---

## Artifacts

- **eth-chiplet `tidelink` submodule branch `fix/i1-selfarm+obs` @ `a04a194`** (NO push):
  - `pynq_host/scripts/kr260_eth_bringup.py` — step 2 now polls `in_hold`, not `cal_done`
    (+ FIX-E release + 1s bilateral settle).
  - `pynq_host/scripts/bringup_pair_release.sh` — dev-host **S_HOLD-barrier bilateral
    orchestrator** (the robust bring-up: arm both → wait BOTH in_hold → release both →
    poll fcsm=4). This is the recommended standard recipe.
  - `pynq_host/scripts/tl_pair_step.py` — single-die primitive (arm|wait_hold|release|
    poll_up|status).
  - `pynq_host/scripts/release_training.py` — live FIX-E poke (for an already-armed pair).
  - `pynq_host/scripts/fcemit_read.py` — FC-emit/CR observability reader.
  - SELF_ARM RTL + winscan/fcemit obs already on this branch (`34b006c` and earlier).
- **New sim regression** `sim_gate_i1_fixe_training_release` @ `test/i1-fixe-training-release`
  `2d2209a` (worktree `tidelink-fixe`) — **DONE & discriminating**: a unit TB wrapping the
  deployed override calibrator holds `swi_training_mode` through S_HOLD and asserts the
  deadlock (state stays 6, `cal_done=0`), then releases and asserts `S_DONE`/`cal_done`.
  Default PASS 2/2; `FIXE_INVERT=1` (skip release) FAILs exactly as silicon did. Wired
  blocking into `make sim_gate`. Closes the sim blind spot that produced the "below-RTL"
  misdiagnosis. NOT pushed.

### Exit gates — all met
- **SIM:** `i1_selfarm_rolelock` PASS · isolated-write (T2) PASS · `i1_fixe_training_release`
  PASS (discriminating).
- **HW:** cold-repro `fcsm=4` both dies · `kr260_eth_regress` link/role/tidechart PASS ·
  6/6 byte-exact D2D crossings.

## What needs David
1. **Push** `fix/i1-selfarm+obs` (@`a04a194`) and land the **SELF_ARM RTL** into the main
   `tidelink` repo (it currently lives only on the eth-chiplet submodule branch).
2. **Bump the eth-chiplet `tidelink` submodule pin** to include this fix — **the recovery
   FCSM now works; the deps-revert workaround is no longer required.**
3. **Ratify the FIX-E bring-up recipe** (`bringup_pair_release.sh`) as the standard
   eth-chiplet bring-up; the old cal_done-first recipe self-deadlocks.
4. **Pre-existing:** the eth_ss_0 boot-ROM backdoor **bit-27 drop** (separate eth-chiplet
   item, not TideLink).
5. **Converge the three sim branches** and land into `sim_gate` on main:
   `fix/i1-selfarm-rolelock` (+`test/i1-selfarm-regression`), `fix/tidelink-isolated-write-dataloss`
   (`fda8288`), `test/i1-fixe-training-release` (`2d2209a`). All three regressions pass;
   they currently live on separate branches/worktrees.

*SoC Labs — TideLink chiplet interconnect. Autonomous overnight session, 2026-07-31.*
