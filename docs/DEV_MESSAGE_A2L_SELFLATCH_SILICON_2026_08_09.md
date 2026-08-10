# To the TideLink dev — the a2l self-latch fix is silicon-proven for normal traffic, but `1112d63` never wired it; + where the residual wedges actually live

**From:** nanoSoC eth-chiplet integration (two-board KR260 FPGA silicon).
**Date:** 2026-08-09.
**Continues** the `AXIREC_RECONCILE` thread (your 08-04 reply closed AXI data-node recovery and
handed the residual wedge to the anchor/eye-margin workstream). Since then the **a2l ACK-pointer
CDC self-latch (TL-009)** turned out to be a *second, distinct* bug from the anchor lottery — and
it's now the one with the cleanest silicon result.
**TL;DR:** Your `_1/_3/_5` a2l override files landed in `1112d63` but **the FPGA flist still
compiles the unfixed `deps/` copies, so the fix ships as a no-op.** Once actually wired, it's
silicon-proven (128/128 writes + 128/128 reads, no wedge). Two residual wedge modes remain and
**neither is a2l RTL** — R1 (errinject) is silicon-only (doesn't repro in *any* sim), R2
(endurance) is eye-drift. TL-032/TL-033 are staged but **defensive — do not merge blind.**

Rig map (unchanged): die_a = kr260_01 = 10.22.24.159 (initiator); die_b = kr260_02 = 10.22.24.153 (target).

---

## MUST-FIX #1 — `1112d63` shipped the override files but left the flist on `deps/` (silent no-op)

This is the important one. The TL-009 self-latch fix (continuous `w_inc=1` + the `a2l_ack_valid`
window guard, ported from `_12/_13` to the AW/W/B data-plane nodes) is present as:

```
tidelink/src/rtl/local_overrides/WlinkGenericFCReplayV2_{1,3,5}.v
```

…but `flists/tidelink_fpga_v2.flist` (lines ~259/270/272) still points `_1/_3/_5` at the
**unfixed** `deps/…/WlinkGenericFCReplayV2_{1,3,5}.v`. So a clean build from `1112d63` compiles
the old edge-triggered `w_inc` and **the wedge is unchanged** — the fix is inert.

I re-pointed the flist locally (`deps/` → `src/rtl/local_overrides/` for all three) to prove it on
silicon. **That re-point currently lives only in my working tree** (`M tidelink` in the parent's
git status) — it is not committed anywhere. If you don't land it your side, the next clean checkout
regresses. Please fold the re-point into the repo (or move the fixed files so the `deps/` path is
correct — your call on which is canonical).

Note the per-node widths differ, so the guard bound was **re-derived, not copied**: `_1/_5` = 4-bit/
8-deep, `_3` = 6-bit/32-deep (`_13` was 5-bit/16-deep). Worth a sanity check on your side that the
bounds I derived match your intent.

## MUST-FIX #2 — the ASIC tapeout flist needs the same re-point, and it's owner-gated

`flists/tidelink_top_full_asic_v2.flist` (lines ~246/257/259) has the identical `deps/` problem for
`_1/_3/_5`. I edited it to point at `local_overrides/`, **but that change is INERT** — the tapeout
build consumes the *generated* `tidelink_asic.flist`, which the tapeout owner regenerates. Until
that regen runs, the ASIC netlist still carries the unfixed a2l nodes. Flagging so it doesn't fall
through the crack between "edited the source flist" and "regenerated the derived one."

## VALIDATED — the fix works on silicon (good news)

Once the flist actually pointed at the fixed files, rebuilt (Vivado 2024.1, this host) and ran
`kr260_sysval` on the pair:

- **T3 delivery soak: 128/128 cross-die writes byte-exact, no wedge.**
- **T10 read soak: 128/128 cross-die reads byte-exact, no wedge.**

vs. the pre-wire bits, which wedged on the very first sustained canary at the ~6-word self-latch
cap. **The self-latch cap is gone for normal sustained data-plane traffic** — the rank-1 blocker is
cleared. Your `_12/_13` approach is confirmed correct in kind on the data-plane nodes.

## RESIDUAL R1 — errinject wedge is SILICON-ONLY; do not chase it in sim

`cov_errinject_sweep` still wedges die_a on the first AW error-inject (good eye, CPU0 gated). I ran
this down hard:

- It does **NOT reproduce in the a2l unit bench** (`tidelink_a2l_replay_cdc`) —
- nor in the **fuller FCSM recovery env** (`cocotb/tidelink_axi_datanode_recovery`, which *does*
  instantiate the FCSM). Every AW inject recovers **byte-exact across 4 configs**: all-fixes CRC×4,
  byte-0 ECC on/off, persistent, **and `ASIC_MIRROR=1`** (recovery-stripped `deps/` + TL-032).

So it's a **silicon-only phenomenon** (async clock ratio / physical eye / shipped-bits ECC-FCSM
provenance), not a cleanly sim-reproducible RTL bug — **off-rig fix-and-prove cannot close it.**
Please don't burn cycles reproducing it in simulation; it won't.

**One real secondary gap surfaced by the deep-dive** (independent of whether it's *the* wedge): the
**state-7 NACK watchdog is dead after the first CRC error** — sticky `socl_l7_real_crc_seen` in
`WlinkGenericFCSM_4.v` pins `wdog_cnt=0`, so the backstop never fires again. That's a genuine defect
worth fixing regardless.

**Correct next step (attended):** silicon ILA on die_b's AW-FCSM during the inject dwell — capture
`state`, `send_nack_req`, `socl_l7_wdog_cnt`, `auto_tx_out_advance`. If `auto_tx_out_advance` is
flat-0 through the dwell → it's an emit-starvation stall → needs the §6 state-exit change (below).
If it pulses → TL-033 alone suffices. Needs an ILA build + a rig session; not autonomous.

## STAGED — TL-032 and TL-033 are DEFENSIVE, not proven wedge fixes — do not ship blind

- **TL-032** (revert-aware a2l guard: `else if (link_revert) a2l_link_addr <= link_revert_addr` in
  `_1/_3/_5`) is **sim-proven in the a2l unit bench** (before-FAIL / after-PASS) and confirmed in
  the built bits — but the silicon errinject wedge is **unchanged**, so it's necessary-hygiene, not
  a wedge fix.
- **TL-033** (revives the state-7 watchdog via an instantaneous `auto_tx_out_advance` forward-
  progress proxy, in `local_overrides/WlinkGenericFCSM{,_1,_2,_3,_4}.v`) is **sim-proven no-
  regression** — but it is **DEFENSIVE only, not yet silicon-tested** (needs a converged rebuild +
  retest). A pure emit-starvation stall *also* needs the state-7 exit to fire on
  `(auto_tx_out_advance | wdog_force_clear)` — the full spec is `scratchpad/plan_a2l_r1_fcsm.md §6`.
  **Do not merge TL-033 blind** — decide after the ILA tells us stall vs. pulse.

## RESIDUAL R2 — endurance wedge is eye-drift, not a2l RTL

`T6_endurance` wedged at **beat 768** this run vs. **~1024** before. A variable wedge beat rules out
a fixed RTL wrap/boundary — it tracks the marginal physical eye / unconstrained RX word clock (the
missing `create_generated_clock` on the /16 recovered RX clock). This belongs to the eye/SDC
workstream, not your a2l queue. Delivery (128) + reads (128) still pass on the same bits.

## Net / what I need from you

1. **Land the FPGA-flist re-point** (MUST-FIX #1) so the a2l fix stops shipping as a no-op. This is
   the one that changes correctness today.
2. **Get the ASIC-flist re-point into the regenerated `tidelink_asic.flist`** (MUST-FIX #2, tapeout
   owner).
3. **Fix the sticky-`real_crc_seen` watchdog death** in `WlinkGenericFCSM_4.v` regardless of R1.
4. **Don't chase R1 in sim, don't merge TL-033 blind** — the next real move is an attended die_b
   AW-FCSM ILA.

## Rig / artifacts

Boards clean (die_a POR-recovered by the harness), leases released. Built bits =
`1112d63` + the flist re-point + `local_overrides` (a2l self-latch, TL-032, plus the data-mode
election gate and the CPU0 firmware IMEM-bake for the other two unlocks). Supporting material:
`scratchpad/plan_a2l_r1_fcsm.md` (§6 state-exit spec + suggested TL-033 registry entry),
`docs/CAMPAIGN_THREE_UNLOCK_2026-08-09.md`. Happy to rebuild and run any specific
anchored/errinject/endurance sequence on the pair on your word.
