# Tapeout fold plan — nanoSoC eth-chiplet + TideLink (2026-08-09)

Author: fold-action session (working-tree only, no commit/push/branch-change).
Scope: fold the FPGA-HW-proven fixes into the **ASIC / tapeout** netlist path, staged
so David gates every netlist-affecting decision and nothing stomps the concurrent
ASIC (`fix/tag-ram-gwen`) session mid-build.

Derived from `scratchpad/plan_tapeout.md` (read-only analysis), re-verified against the
LIVE working tree on 2026-08-09. Several memory notes were stale; corrections are inline
and summarised at the end.

---

## Legend

- **SAFE-MECH** — mechanical, low-risk, port/boundary-preserving. Can be prepared without a policy call.
- **DAVID-DECISION** — reverses a written ship decision, or commits logic/policy into the tapeout. Needs David.
- **NA** = netlist-affecting (changes the synthesised gates → owes a re-synth + LEC).
- **not-NA** = timing/verification/housekeeping only (no new gates).

## Coordination constraint (binding)

- The shared checkout is on `fix/tag-ram-gwen`; the concurrent ASIC session is editing
  **ASIC/\*\*** RIGHT NOW (working tree shows `M` on `ASIC/genus-innovus/{Makefile, inputs/*.sdc,
  scripts/*.tcl, scripts/lec/*}` plus new `?? scripts/probe_*.tcl`, `2b/3b/4b_pnr_*_eval.tcl`,
  `selftest_route_gate.tcl`, `lec_*_shadow/`). **Do not touch ASIC/\*\* or `$IP_LIBRARY_ROOT/\*\*`.**
- All folds here live in the **tidelink submodule** (`tidelink/flists/*`) or **parent `src/rtl/`** —
  never in ASIC/**, so file-level collision is avoidable.
- Per memory `concurrent-sessions-mutate-repo`: re-`git status` immediately before any stage,
  stage named paths only, **never `git add -A`**.
- **The regen step (F) rewrites a generated flist the ASIC build consumes** — it MUST be sequenced
  with the concurrent ASIC session so a mid-flight build is not fed a half-updated flist. See F.

---

## Status of the two working-tree edits this session was authorised to make

1. **A (a2l re-point) — APPLIED (uncommitted).** `tidelink/flists/tidelink_top_full_asic_v2.flist`
   was verified CLEAN (no concurrent edit) before editing, then re-pointed `_1/_3/_5`
   deps→local_overrides (+12/-3, comments only + the 3 path swaps). Left UNCOMMITTED — David gates
   the tapeout. **It is INERT until F (regen) runs** (see A + F).
2. **This doc** — new untracked file `docs/TAPEOUT_FOLD_PLAN_2026-08-09.md`.

No other working-tree file was touched by this session.

---

## The plan — ordered A–G

### A. Re-point a2l `_1/_3/_5` deps→local_override in the ASIC-V2 flist — **[SAFE-MECH, NA] — DONE (uncommitted)**

- **What:** `tidelink/flists/tidelink_top_full_asic_v2.flist` lines `:266/:277/:279` re-pointed from
  `deps/axi-chiplet-controller/logical/wlink/WlinkGenericFCReplayV2_{1,3,5}.v`
  → `src/rtl/local_overrides/WlinkGenericFCReplayV2_{1,3,5}.v`, mirroring the FPGA flist
  `tidelink_fpga_v2.flist:269/281/284`. Applied this session; diff is comment lines + the three
  path swaps only.
- **What it fixes:** the TL-027 / TL-009 a2l CDC self-latch — the ~6-word A→B replay wedge on silicon.
  The three override files carry the continuous-drive (`w_inc = 1'b1`) fix; per-node widths (`_1/_5`
  4b/8-deep, `_3` 6b/32-deep) are handled inside each override body.
- **Why ASIC-safe:** override files are committed & tracked, **port-byte-identical to deps** (LEC
  boundary unchanged, no wrapper edits), and these exact files were **FPGA-HW-proven 2026-08-09**
  (128/128 write + 128/128 read soak, no wedge).
- **Concurrent-override note:** a concurrent action agent may be adding a revert-aware guard for the
  errinject wedge to these SAME override files. That is fine and desirable — the flist re-point picks
  up whatever `local_overrides/` contains at regen time. (At the moment of this edit the three
  override files were clean.)
- **INERT until F.** The chip ASIC flist consumes the *generated* `build/chip/flist/tidelink_asic.flist`
  (`flist/nanosoc_eth_chiplet_asic.flist:60`), which is stale (Aug 8 19:59) and still points deps at
  `:124/132/134`. The source-flist edit does nothing until `make asic-flist` regenerates it (F).
- **Sign-off gate:** F (regen) → confirm regenerated flist shows local_override on the 3 nodes →
  re-synth → **run `tidelink_a2l_replay_cdc` (6/6) against the ASIC-V2 flist, not just the per-node
  unit flists** (see E — the unit flists are standalone `dut_src_*.f` envs, so a pass there is vacuous
  for the full netlist) → LEC on the three replay nodes (expect a *legitimate* non-equivalence there —
  that IS the fix, the continuous-`w_inc` tie) → David sign.
- **Highest-leverage item; separate commit; do NOT bundle with D (FCSM/CRC).**

### B. Data-mode election gate (`nanosoc_eth_chiplet.sv`) — **[NA] — DAVID-DECISION (to commit for tapeout)**

- **What:** no flist change. `src/rtl/nanosoc_eth_chiplet.sv` is compiled DIRECTLY by both the FPGA
  and ASIC chip flists (`flist/nanosoc_eth_chiplet_asic.flist:91`, same path as
  `flist/nanosoc_eth_chiplet.flist:69`) — **auto-picked-up, no ASIC flist edit needed.** But the file
  is working-tree `M` (uncommitted); it only reaches a tapeout build once committed AND re-synthesised.
- **The gate is real logic (netlist-affecting), not observability:** `:886` `.tl_data_mode_o (tc_data_mode)`,
  `:974` election-host shim `.link_active (tc_data_mode)` (was the premature `tc_link_active`), TX
  aperture `:646` `.link_active_i (tc_link_active)`, `:496` `link_active_o = tc_link_active`. In-source
  comment (`:884`): "Closes the silent dual-root sequencing race".
- **STALE-MEMORY CORRECTION:** memory `tidechart-election-not-g1-blocked` (and plan item 2's caveat)
  called the silicon dual-root "still open" and warned against representing this gate as the fix.
  **That note is now superseded:** the single-root election is **HW-PROVEN on FPGA 2026-08-09, 3/3
  good-eye** (die_a deterministic single root; no claim-exchange non-convergence). So this gate **FIXES
  the dual-root** on a good eye — it is not merely sequencing hygiene. (Remaining open question is
  marginal-eye behaviour, which is an eye/timing matter, not the gate logic.)
- **Sign-off gate:** g2_soc_pair / election sim regression + David confirms the commit is intended for
  tapeout. Coordinate ownership of the `M` edit before committing (shared branch).

### C. Verify-only — ECC alignment + RX-word-clock SDC (both stale memories, now resolved) — **[SAFE-MECH, not-NA for SDC / already-NA-folded for ECC] — verify, do not author**

Two items the memory still lists as open but the tree shows resolved. **Neither requires a working-tree
edit from the fold owner — only a verification gate.**

- **ECC (`WlinkEccSyndrome.v`) — ALREADY FOLDED.** ASIC-V2 flist `:253` points ECC at
  `src/rtl/local_overrides/WlinkEccSyndrome.v` (the real SEC decode), matching FPGA-V2 `:251`. The deps
  copy is the 2026-05-05 blanket bypass (`corrupted=0; corrected=0`); the override is the real decode.
  Folded at flist level on 2026-08-08 (`d78268a`, `cf0f1ab`). **STALE-MEMORY CORRECTION:**
  `asic-netlist-diverges-from-fpga-proven` says ECC is bypassed on the tapeout netlist — no longer
  true. Still owes: a netlist rebuild + LEC + sign-off like any other node (verify the regenerated
  flist and LEC, don't re-point).
- **RX-word-clock SDC — CONSTRAINED by the concurrent session.** `ASIC/genus-innovus/inputs/
  tidelink_constraints.sdc` now defines `:2` `create_clock D2D_RX_CLK_0` on `TL_CLK_RX` and `:80-81`
  the 8-lane loop `create_generated_clock -name D2D_RX_WORD_CLK_$n -source TL_CLK_RX -divide_by 16`
  with a pin-existence guard and per-clock uncertainty. **STALE-MEMORY CORRECTION:**
  `d2d-rx-word-clock-unconstrained` (~27% untimed) is stale — the fix is applied. **This SDC is in
  ASIC/\*\* and is a live edit owned by the concurrent session — OFF-LIMITS. Verify only.**
- **Sign-off gate (SDC):** after their SDC settles, run `scripts/1b_synthesis_eval.tcl`
  `check_timing_intent`; "Sequential clock pins without clock waveform" must drop 16,653 → ~0
  (`reports/eval/syn_timing_intent.pre.rep`). A value near ~130 means a domain was missed. The next
  timing run will look *worse* (16.5k newly-timed flops) — that is the fix working, not a regression.

### D. FCSM recovery + CRC-reset-polarity fold (deps→local_override on FCSM,\_1,\_2,\_3,\_4) — **[NA] — DAVID-DECISION (explicit)**

- **What:** in `tidelink_top_full_asic_v2.flist:299-303`, re-point `WlinkGenericFCSM{,_1,_2,_3,_4}.v`
  to `src/rtl/local_overrides/` (mirror FPGA-V2 `:304-308`). This is **coupled**: the override files
  also (a) flip the CRC reset default from **ON** to **OFF** (inside `WlinkGenericFCSM.v`), and
  (b) lower `SOCL_L7_MIN_CRACK_EMITS` 32→8. `_5` stays deps (aligned both flists); `_6` is already
  the override (L6 producer fix, `:305`).
- **The 07-29 rationale (why it is HELD on deps):** the in-flist written decision
  (`tidelink_top_full_asic_v2.flist:289-298`) states FCSM 0-4 stay on the **recovery-stripped** deps
  copies for the tapeout netlist "until a silicon ILA confirms the fix", because the recovery FSM
  change was verified only against a **MODELLED** marginal link (`cocotb/tidelink_fcsm_silicon_ratio`),
  not silicon. The deps copies have NO watchdog/recovery (`grep -c socl_l7 == 0`); the overrides carry
  Fix B/C/D watchdog recovery + the state-2 min-CRACK-emit gate.
- **What folding it entails:** (1) reverses that written ship decision; (2) a large, *legitimate* LEC
  non-equivalence across five recovery-FSM nodes; (3) couples the CRC-reset polarity flip (runtime-
  overridable via FC-node offset `0x14` bit[16] per `pynq_host/scripts/xfer_corners_lib.py`, so it is a
  ship *default*, not a hard commit — but still a deliberate choice); (4) the 2026-08-09 silicon soak
  proved the **a2l** fix, NOT the FCSM recovery path specifically — so the "silicon ILA confirms" gate
  is arguably still unmet for FCSM. **Do NOT auto-fold. David decides whether the soak/ILA evidence
  ratifies the 07-29 hold.**
- **Anti-false-green sign-off:** if taken, `tidelink_axi_datanode_recovery` cocotb is the ASIC-mirror
  env — its Makefile constructs a LOCAL_FLIST that reproduces the ASIC-V2 combination (ECC-local +
  chosen FCSM config; `Makefile:33-58`, incl. a `tidelink_fpga_v2_fcsm_local.flist` config). It MUST
  pass in the shipped-combo config, plus a combined-config elab (ECC-on + CRC-`<chosen>` + recovery-on)
  → LEC → David sign. **Its own commit, separate from A.**

### E. Anti-false-green — prove the shipped combo against the ASIC-V2 flist itself — **[DAVID-DECISION on scope]**

- **Why:** memory `system-validation-holes-2026-08` — most "recovers byte-exact" sims re-point to FPGA
  `local_overrides` (e.g. the a2l per-node envs are standalone `dut_src_*.f` unit flists), so they are
  **vacuous for the tapeout netlist**. Whatever A/B/D combination ships must be simulated on
  `tidelink_top_full_asic_v2.flist` itself.
- **Gate:** `tidelink_axi_datanode_recovery` + `tidelink_a2l_replay_cdc` + a combined-config elab, all
  `-f tidelink_top_full_asic_v2.flist`. Also close the two residual wedge modes the a2l HW run flagged
  (cov_errinject_sweep AW error-inject; T6_endurance beat ~1024) before calling recovery "done".
- No combo of "ECC-on + CRC-on + no-watchdog" has ever run on any platform — whatever ships must be
  proven against the ASIC-V2 flist, not extrapolated from FPGA-V2.

### F. Regenerate the chip ASIC flist + re-synth (makes A — and D if taken — take effect) — **[SAFE-MECH] — MUST be run by the tapeout owner, sequenced with the ASIC session**

- **What:** `make asic-flist` (Makefile `:173-185`) reruns `flist/resolve_tidelink_flist.py` on
  `tidelink_top_full_asic_v2.flist` → `build/chip/flist/tidelink_asic.flist`
  (`CHIPLET_TL_ASIC_FLIST`, Makefile `:35`). The chip ASIC flist `-f`-includes this generated file
  (`flist/nanosoc_eth_chiplet_asic.flist:60`), so **the A re-point is inert until this runs.**
- **Current state:** generated flist is stale (Aug 8 19:59), still deps at `:124/132/134`. Banner:
  `// Generated by flist/resolve_tidelink_flist.py — do not edit.` — do NOT hand-edit it.
- **This session did NOT regenerate it** (per instruction — a concurrent ASIC session may be mid-build;
  rewriting the generated flist under a running synthesis would feed it a half-updated file).
- **Sequencing requirement:** the tapeout owner must run `make asic-flist` **only when the ASIC session
  is not mid-build**, then confirm the regenerated `build/chip/flist/tidelink_asic.flist` shows
  local_override on `_1/_3/_5` before launching synthesis.
- **Gate:** post-regen grep of the generated flist for the three nodes = local_override.

### G. Housekeeping — legacy V1 flist + absent DFT/scan flist — **[SAFE-MECH]**

- **Legacy V1 (`tidelink_top_full_asic.flist`) still points deps** at `_1/_3/_5` (`:142/153/155`). It is
  NOT the ship config (Makefile ships V2; V1 and V2 carry same-named modules and cannot co-compile).
  Re-point only for consistency; not on the tapeout critical path. **Not touched this session.**
- **DFT/scan ASIC flist GAP:** there is **no `*dft*` or `*scan*` flist** in `tidelink/flists/`
  (directory listing confirmed — the only matches for "dft"/"scan" are substrings in comments, not a
  dedicated flist). If a DFT/scan flist is expected for tapeout (scan insertion, ATPG boundary), that
  is a **separate gap to raise with David** — it is not covered by any fold above.

---

## Suggested sequence (dependency-ordered)

1. **A** — a2l re-point (DONE, uncommitted). Highest leverage, safe. Separate commit when David gates.
2. **B** — commit the data-mode gate (coordinate ownership of the `M` edit).
3. **F** — `make asic-flist` regen, sequenced with the ASIC session, after A/B, before any synth.
4. **C** — verify RX-word-clock SDC (after the concurrent session's SDC settles) + verify ECC in the
   regenerated flist.
5. **E** — ASIC-V2-flist sign-off sims; gate on A/B (and D if taken).
6. **D** — FCSM recovery + CRC fold; David decision; last, own commit, fully re-signed-off.
7. **G** — V1 / DFT-scan-flist housekeeping; opportunistic + raise the DFT gap.

Coordination guard on EVERY commit: re-`git status`, stage named paths only, never `git add -A`;
keep folds out of ASIC/** (owned by `fix/tag-ram-gwen`).

---

## STALE-MEMORY corrections captured here (so the next session doesn't chase solved problems)

- `asic-netlist-diverges-from-fpga-proven` (08-07): **ECC is no longer a divergence** — ASIC-V2 points
  the real-decode override (`:253`) since 08-08. Still true: a2l *was* on deps (fixed by A this
  session, pending regen), FCSM recovery-stripped, CRC-on-at-reset.
- `d2d-rx-word-clock-unconstrained` (08-07): **SDC now carries the 8 generated clocks** (ASIC session);
  verify (C), don't re-author.
- `tidechart-election-not-g1-blocked` (dual-root "still open"): **superseded** — data-mode gate is
  HW-PROVEN single-root on FPGA 2026-08-09 (3/3 good-eye); the gate FIXES the dual-root on a good eye.
- `tl009-wedge-is-a2l-cdc-selflatch`: override files landed + FPGA flist re-pointed; **ASIC flist
  re-point now APPLIED (A, uncommitted, pending regen)** — closes the memory's open line.
