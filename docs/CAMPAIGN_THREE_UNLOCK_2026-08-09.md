# Campaign record — the three-unlock FPGA campaign (2026-08-09)

**Repo:** `nanosoc-ethernet-chiplet` (parent) + `tidelink` submodule
**Author:** analysis/validation session `e31cf0db` · **Date:** 2026-08-09
**Status of this doc:** durable index for the next engineer/session. It *points at* the
detailed handovers and memory notes rather than duplicating them. Every git write that
would land this campaign is user-gated and staged — see
`scratchpad/COMMIT_PLAN.md` for the exact, ready-to-run sequences (nothing has been
committed or pushed).

> **Read this first if you are picking the campaign up:** the working trees have already
> drifted since the consolidation plan was written. The parent is on a concurrent ASIC
> session's branch (`fix/tag-ram-gwen`) and the `tidelink` submodule now shows many
> modified `src/rtl/*.sv` files, the **ASIC** flist, `lint/*`, and a cocotb ptp_servo
> file that are **not** part of this campaign. Re-run `git status` and stage only the
> explicit paths in `COMMIT_PLAN.md`. Never `git add -A`.

---

## 0. What was done (one paragraph)

A single converged FPGA rebuild carried all three fixes to silicon: (1) the
`tidelink_fpga_v2.flist` re-point that finally wires the TL-027 a2l CDC self-latch fix
into the build, (2) the TideChart data-mode election gate in `nanosoc_eth_chiplet.sv`,
and (3) a genuine `smoke_remap` bootrom in the packaged `eth_chiplet_ip` (replacing a
mislabelled flash-loader ROM). The full nanoSoC multicore + eth-chiplet SoC closed on
**xck26 (KR260)** through bitstream **twice** — the standard `kr260-eth-chiplet`
orientation and the `-flip` orientation — and both were exercised on the two-board rig.
Net result: the rank-1 data-plane blocker is lifted for normal traffic, the dual-root
election is RTL-fixed, and CPU0 executes on-die for the first time. Three residuals
remain, each root-caused and bounded (below).

---

## 1. The three unlocks

### UNLOCK 1 — a2l CDC reliability: **HW-PROVEN**

- **Root cause (settled).** The die_a wedge (TL-009) is an a2l ACK-pointer **CDC
  self-latch**, distinct from the TL-001 cross-die-write data-drop (which is PHY
  framing). A torn `WavMultibitSync` mailbox value latches `a2l_full` permanently
  because `w_inc` was edge-triggered; the fix is to drive `w_inc` continuously plus an
  ACK-window guard. David already root-caused and fixed this on
  `local_overrides/WlinkGenericFCReplayV2_{12,13}.v` (2026-07-07); it had **never** been
  ported to the AW/W/B AXI data nodes `_1/_3/_5`. Memory: `tl009-wedge-is-a2l-cdc-selflatch`.
- **The catch this campaign found.** tidelink `1112d63` (via `9210dc5`) *did* land the
  ported `_1/_3/_5` local_override files — but left the **FPGA flist still pointing at
  the unfixed `deps/` copies**, so every FPGA build was silently compiling the
  wedge-prone code. The fix was a no-op until the flist was re-pointed.
- **The change.** `flists/tidelink_fpga_v2.flist` — re-point `_1/_3/_5` deps →
  `src/rtl/local_overrides/` (the override targets were already tracked, so this is
  self-contained). Rebuilt the `kr260-eth-chiplet` bits (Vivado 2024.1, on this host).
- **Silicon proof (2026-08-09, KR260 pair).** `kr260_sysval` on the pair:
  **T3 delivery soak 128/128 writes byte-exact + T10 read soak 128/128 cross-die reads
  byte-exact, NO wedge** — versus the pre-fix bits, which wedged on the very first
  sustained canary. The ~6-word self-latch cap is **gone for normal sustained
  data-plane** (the rank-1 blocker for ordinary traffic).
- **Residuals (both distinct from the self-latch, both still open):**
  - **R1 — error-inject wedge.** `cov_errinject_sweep.py` still wedges die_a on the
    first AW error-inject. Root-caused: the ported window-guard is **not revert-aware**
    — a NACK-driven replay reverts the FIFO read pointer below `a2l_link_addr`, the
    guard's `off_max` wraps, every recovery ACK is rejected, and the self-latch
    re-forms through a path the fix never covered. Normal traffic never NACKs, so T3/T10
    never exercise it. **Fix in progress** (RTL, rebuild; sim-first confirmation via the
    `cocotb/tidelink_a2l_replay_cdc` bench). Full analysis: `scratchpad/plan_a2l_residuals.md` §R1.
  - **R2 — endurance wedge at beat ~1024** of a 2000-write soak (`kr260_sysval.py` T6).
    "1024" is a cumulative beat *count*, not an address boundary (the soak overwrites a
    fixed ~1 KB aperture). Most likely the already-tracked **physical eye / RX-word-clock
    reliability** item surfacing on a longer soak than T3's 128 — needs a count-vs-time
    soak sweep to discriminate from a pkt-num/credit lap. Analysis: `scratchpad/plan_a2l_residuals.md` §R2.

### UNLOCK 2 — TideChart dual-root: **FIXED (RTL-decisive) + HW**

- **Root cause (settled).** The election was gated on `link_active` (== `role_locked_o`,
  which asserts ~5 µs *before* the D2D link can carry FC/EXT words) while the correct
  gate port `tl_data_mode_o` (FCSM ≥ 4) was left **open** in the integration. Both dies
  settled their election before any claim crossed the die boundary → silent dual-root.
  The tidelink port comment self-documents the bug; the fixed wiring already existed in
  the pair testbench (`tb_tc_pair.sv:378`). Full analysis: `scratchpad/tidechart_rootcause.md`.
- **The change.** `src/rtl/nanosoc_eth_chiplet.sv` — route `tl_data_mode_o` (FCSM ≥ 4)
  to the election host shim's `.link_active` in place of the premature `tc_link_active`.
  This is byte-for-byte the sim's proven wiring. (RTL-decisive: this is the actual
  sequencing fix, not observability.)
- **Silicon.** On a good-eye bring-up the pair produces **3/3 good single-root (die_a)**.
  Straps are differentiated on silicon (die_a `random_id=0x0039`, die_b `0x0161`), so
  die_a is the rightful root and the strap tiebreak wiring works. Memory:
  `tidechart-election-not-g1-blocked`.
- **Important honesty caveat.** An earlier 2026-08-08 rig run (before this gate was on
  the bits, and on a marginal eye) still showed real dual-root via claim-exchange
  non-convergence — i.e. the data-mode gate is **necessary sequencing hygiene**, and a
  one-shot claim dropped on a marginal eye can still cause dual-root independently
  (secondary cause, folds into the eye/RX-clock work). Do not overclaim TideChart as
  fully closed on every bring-up; it is RTL-fixed and good-eye-HW-clean.
- **Supporting meta-fixes landed (submodule `coverage/`, untracked):**
  - `cov_common.py` — the **`sudo -S -p ''`** fix. The sudo prompt was prepending to the
    first stdout line of every board gate, mangling the first-read register (tidechart
    `KeyError:'STATUS'`, obs_health `KeyError:'SWI_LANE'`, regplane leak). This single
    meta-bug was behind a class of false-RED gate verdicts. Memory:
    `cov-common-sudo-prompt-meta-fix`.
  - `cov_tidechart_election.py` — assert determinism on the full claim tuple
    `{DEVICE_CLASS, RANDOM_ID}` incl. device_strap `RANDOM_ID[15:8]` (not DEVICE_CLASS
    alone); the old G1 gate keyed on DEVICE_CLASS equality and was a false-positive.
    Also hardened the STATUS-drop crash and added RANDOM_ID settle/retry (PUF reads
    `0xFFFF` transiently right after bring-up).
  - `verif/g2_soc_pair/test_g2_soc_pair.py` (parent) — first **system-level** TideChart
    Tier-1 test (TCAPB @ `0x2E04_0000`) across the two dies (+137 lines).

### UNLOCK 3 — Firmware: **CPU0 ON-DIE EXECUTION PROVEN; user-app residual**

- **The keystone blocker found.** The tracked "golden default" bootrom
  (`nanosoc-multicore-system/.../eth_ss_bootrom_default.sv`, and the packaged
  `tidelink/imp/fpga/eth_chiplet_ip/src/eth_ss_bootrom.sv` materialised from it) was
  **mislabelled** "smoke_remap Case-A" but disassembles to a **stage0 QSPI-flash
  loader**: it spins in a mailbox poll and requires a BOOT-magic flash image — so a host
  IMEM preload was moot (CPU0 just spun; ALIVE_SIG=0 on both current *and* the first
  rebuilt "default" bits). The genuine pure-REMAP+jump `smoke_remap` ROM was a different,
  smaller image at
  `nanosoc-multicore-system/build/cmake/gcc-m0plus-le/firmware/bootloader/smoke_remap/eth_ss_bootrom.sv`.
- **The change.** Rebuilt/repackaged `eth_chiplet_ip` with the **genuine** smoke_remap
  ROM (packaged bootrom slot `eth_ss_bootrom.sv`, sha256 `c95f2cff…`, 2026-08-09 10:35).
- **Silicon proof (2026-08-09, genuine bits).** CPU0 **executes on-die for the first
  time**: the smoke_remap bootrom ran end-to-end — it wrote mailbox `0x23000010 =
  0xD15C0001`, REMAP `0x50002000 = 1`, and XiP `0x21000000 = 0x100`, all read back. CPU0
  comes out of reset via the one boot-gate write (`0x4 → 0x4_2900_0000`) and runs code.
  The backdoor IMEM preload path is also proven (222/222 words byte-exact at
  `0x4_1000_0000`).
- **Residual (bounded).** The preloaded IMEM **app never executes its first
  instruction** — tried absolute-IMEM, post-REMAP, and a minimal no-CRT app; even
  retargeting the app's first write to the mailbox that CPU0 *provably* writes stayed
  `0x0`. So it is **not** a CRT/shared-sram fault — CPU0 never runs the app at all. The
  RTL is sound in the ways checked (backdoor-IMEM == CPU0-fetch-IMEM verified by the
  222/222 read-back; REMAP write took and survived CPU0 reset-release). The residual is
  bounded to a **dynamic fault-or-preload issue**: the bootrom's `remap_and_jump` does
  not land CPU0's instruction fetch in the backdoor-preloaded IMEM. Memory:
  `cpu0-firmware-backdoor-preload`. Design doc: `docs/FIRMWARE_ENABLE_DESIGN_2026-08-08.md`.
- **Next steps:** endianness check on the app image → then bake the app via
  `ETH_IMEM_MEM_FPGA_IMG` at bitstream-gen (Step0 → IMEM-bake rebuild), rather than more
  host-preload iterations. Firmware artifacts + minimal app: `scratchpad/fw_p0/`.

---

## 2. Validation state (index)

The genuine data-plane validation and its holes are catalogued in the 2026-08-08 doc set
(parent `docs/`, all currently untracked):

| Doc | What it covers |
|---|---|
| `SYSTEM_VALIDATION_HOLES_REPORT_2026-08-08.md` | 5-agent audit: only cross-die WRITE is genuinely validated; reads/PTP/TideChart/ethernet/M0-firmware untested; false-greens catalogued |
| `SYSVAL_TEST_BUILD_SPEC_2026-08-08.md` | build spec for the sysval suite |
| `VALIDATION_UNBLOCK_PLAN_2026-08-08.md` | plan to unblock the untested paths |
| `HW_LOOP_RESULTS_2026-08-08.md` | HW-loop run results |
| `SYSVAL_RUN_RESULTS_2026-08-08.md` | sysval suite run results |
| `FIRMWARE_ENABLE_DESIGN_2026-08-08.md` | CPU0 firmware enable design (backdoor preload + gate release) |

What the campaign added to coverage (submodule `pynq_host/scripts/`, untracked unless
noted):

- **sysval suite:** `eth_sysval_board.py`, `kr260_sysval.py`, `run_categoryA_goodeye.sh`,
  `kr260_recover_gate.py`, `kr260_reliability_sweep.py`, `run_ptp_pair.sh`.
- **coverage gates:** `coverage/` — 13 `cov_*.py` (incl. `cov_tidechart_election.py`),
  `cov_common.py` (the sudo meta-fix), a shell harness, a C ISR stub, plans, README.
- **hygiene on the durable regression** (`kr260_eth_regress.py`, tracked-modified): a
  **sha256 provenance gate** on `eth_sysval_board.py` (HYGIENE-2) + a **`--config-only`
  default** (HYGIENE-1) so a bare run is wedge-safe and reports delivery UNPROVEN rather
  than a false green. (Memory `system-validation-holes-2026-08` H1: the regression
  previously shipped data-plane OFF by default, so a green run moved zero bytes.)

---

## 3. Residuals / known-open (do not overclaim closed)

| Item | State | Pointer |
|---|---|---|
| **R1 — a2l error-inject wedge** | root-caused (window-guard not revert-aware); **fix in progress** (RTL, rebuild) | `scratchpad/plan_a2l_residuals.md` §R1; `tl009-wedge-is-a2l-cdc-selflatch` |
| **R2 — endurance wedge @ ~1024** | likely eye/RX-clock; needs count-vs-time soak sweep to confirm vs pkt-num lap | `scratchpad/plan_a2l_residuals.md` §R2 |
| **Firmware first-exec** | CPU0 runs bootrom on-die; preloaded app never runs — dynamic fault/preload | `cpu0-firmware-backdoor-preload` |
| **D2D RX word clock unconstrained** | 27% of chiplet untimed, no CTS clock tree; one missing `create_generated_clock`. **OPEN, resolve Mon 2026-08-10.** SDC now carries a drafted 8-lane fix on the ASIC side (concurrent session) — verify, don't re-author | `d2d-rx-word-clock-unconstrained`; `scratchpad/plan_tapeout.md` §D |
| **ASIC netlist diverges from FPGA-proven** | tapeout ships a2l on unfixed deps + FCSM recovery stripped + CRC-on-at-reset; ECC now folded (08-08). No platform has run ECC-on+CRC-on+no-watchdog | `asic-netlist-diverges-from-fpga-proven`; `scratchpad/plan_tapeout.md` |
| **PTP never synced on any board** | sim only; GM register-pinned; `phc_locked_i` tied 0 in FPGA | `system-validation-holes-2026-08` |
| **Het eth↔compute pair never run** | autoneg leaves Wlink in reset after training; no het HW run anywhere | `het-chiplet-testing-repo` |

---

## 4. Build provenance (gitignored artifacts — reproducible, not committed)

`imp/*` is gitignored (`.gitignore:98`); the bits/bin and the packaged bootrom are **not**
committed. Recorded here so they are identifiable/reproducible without a `-f` add.

| Artifact | sha256 (first 16) | Built |
|---|---|---|
| `imp/fpga/output/kr260-eth-chiplet/tidelink.bit` | `6429c072d83b3323` | 2026-08-09 11:21 |
| `imp/fpga/output/kr260-eth-chiplet/tidelink.bin` | `4863e2b10f0f45b8` | 2026-08-09 11:21 |
| `imp/fpga/output/kr260-eth-chiplet-flip/tidelink.bit` | `0274b55d1c1c6fec` | 2026-08-09 10:01 |
| `imp/fpga/output/kr260-eth-chiplet-flip/tidelink.bin` | `e0077654328d381a` | 2026-08-09 10:02 |
| `imp/fpga/eth_chiplet_ip/src/eth_ss_bootrom.sv` (genuine smoke_remap) | `c95f2cff1aec85ed` | 2026-08-09 10:35 |

Build/package scripts (scratchpad, for reproduction): `build_fw.sh`, `run_builds.sh`,
`package_fw.sh`, `gen_bootrom.bin`/`gen_bootrom.disasm.txt`, `newbits_tc_fw.sh`. Build
logs: `build_ethchip.log`, `build_ethchip_flip.log`, `build_fw.log`, `package_fw.log`.
(All paths under `scratchpad/`.)

---

## 5. Commit map & pin-bump decision

The exact staging/commit sequences are in **`scratchpad/COMMIT_PLAN.md`** (user-gated;
nothing executed). Summary of which change carries which unlock:

| Unlock | File(s) | Where committed |
|---|---|---|
| 1 (a2l wired to FPGA) | `flists/tidelink_fpga_v2.flist` | submodule (Phase A) |
| 1/2 (sysval + coverage + gate meta-fixes) | `pynq_host/scripts/**`, `coverage/**` | submodule (Phase A) |
| 2 (data-mode gate) | `src/rtl/nanosoc_eth_chiplet.sv` | parent (Phase B) |
| 2 (system TideChart test) | `verif/g2_soc_pair/test_g2_soc_pair.py` | parent (Phase B) |
| all | `tidelink` gitlink pin bump | parent (Phase B) |
| 3 (genuine bootrom) | packaged `eth_ss_bootrom.sv` | **gitignored** — provenance only (§4); the source-of-truth ROM lives in `nanosoc-multicore-system` (owned by a concurrent session — coordinate) |

**Pin-bump decision (load-bearing):** `235d758 → 1112d63` is a clean fast-forward
(verified: `235d758` is an ancestor of `1112d63`). But once Phase A creates a new tidelink
commit `X` (= `1112d63` + the FPGA flist re-point + the sysval/coverage suite), the
*meaningful* parent pin is `X`, not bare `1112d63` — pinning to `1112d63` leaves the FPGA
flist re-point (the thing that actually wires the a2l fix into FPGA) unpinned. Pinning to
`X` requires pushing `X` to the tidelink origin **first** and verifying it against the
**live** remote (cached tracking refs lie — `chiplet-pins-unpushed`,
`eth-chiplet-gpio-phy-broken-pin`). Both options and the trap are spelled out in
`COMMIT_PLAN.md` Phase B.

---

## 6. Follow-ups / open items (with owners)

1. **Firmware first-exec** — endianness check on the app image, then IMEM-bake rebuild
   via `ETH_IMEM_MEM_FPGA_IMG` (Step0 → bake). *Owner: firmware/validation session.*
2. **a2l R1 fix** (revert-aware window guard in `_1/_3/_5`, re-add the `_13` obs taps) —
   **in progress**; confirm sim-first on `cocotb/tidelink_a2l_replay_cdc`, then one
   rebuild. *Owner: this validation line.*
3. **a2l R2 soak sweep** — rig-only count-vs-time discriminator before any rebuild; folds
   into eye/RX-clock work if scattered. *Owner: this validation line.*
4. **D2D RX word clock** — **resolve Mon 2026-08-10**; verify the concurrent ASIC
   session's SDC (`create_generated_clock` ×8) via `check_timing_intent`, don't
   re-author. *Owner: ASIC/tapeout session; verification by this line.*
5. **Tapeout a2l re-point + FCSM/CRC decision** — the ASIC-V2 flist still points a2l at
   unfixed deps and strips FCSM recovery / ships CRC-on-at-reset. Re-point a2l (safe,
   port-identical, FPGA-proven); FCSM/CRC is a deliberate ship decision. *Owner: David,
   with the tapeout session.* Note: `flists/tidelink_top_full_asic_v2.flist` is **already
   showing as modified** in the working tree (a concurrent session has started this) —
   coordinate, do not stage it in this campaign's commits.
6. **Rig retests queued** — R1 sim confirm + rebuild; R2 soak sweep; firmware IMEM-bake;
   het pair. *Owner: this validation line / rig.*

---

## Appendix — source memory notes and plans

Memory (`~/.claude/projects/-home-dam1n19-SoCLabs-nanosoc-ethernet-chiplet/memory/`):
`tl009-wedge-is-a2l-cdc-selflatch`, `tidechart-election-not-g1-blocked`,
`cpu0-firmware-backdoor-preload`, `cov-common-sudo-prompt-meta-fix`,
`asic-netlist-diverges-from-fpga-proven`, `peerwrite-drop-is-phy-framing`,
`cross-die-read-more-eye-sensitive`, `d2d-rx-word-clock-unconstrained`,
`system-validation-holes-2026-08`, `chiplet-pins-unpushed`, `tidelink-two-checkouts-trap`,
`concurrent-sessions-mutate-repo`.

Scratchpad plans: `plan_consolidation.md` (commit strategy), `plan_a2l_residuals.md`
(R1/R2), `plan_tapeout.md` (ASIC fold), `tidechart_rootcause.md`. (No `plan_firmware.md`
exists; firmware detail is in the `cpu0-firmware-backdoor-preload` memory and
`docs/FIRMWARE_ENABLE_DESIGN_2026-08-08.md`.)
