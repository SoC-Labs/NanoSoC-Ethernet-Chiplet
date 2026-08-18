# 48 — `pgfix-A`: the provenance set, stated before the run

**Status:** staged, not launched. Two invocations sit on permission denials
(`SDC_STALE_OK=1` for the place stage; the tag push). This page exists so the run's
identity is fixed *before* it produces anything, because "which inputs were in this GDS"
is a question this project has repeatedly failed to answer afterwards.

---

## 1. The provenance set

Recorded 2026-08-18, before launch. Machine-readable block at the end for the per-run
verdict artefact.

| input | value |
|---|---|
| superproject HEAD | `b19e871` (5 commits ahead of `origin/fix/tag-ram-gwen` at `bfbccf6`) |
| `tidelink` pin | `aaa62ed8` — **1 behind** tidelink HEAD `0a5857e4` |
| `ASIC/asic-toolkit` pin | `6d21f83` |
| `SYN_RUN_TAG` | `full-20260814` — synthesis **reused, not re-run** |
| source netlist | `…/full-20260814/outputs/…_gate.v`, 35,133,748 B, 2026-08-14 13:56, sha256 `074ab30e…` |
| `constraints.sdc` worktree | `d05ce849` |
| `constraints.sdc` HEAD | `265bda64` — **these diverge, deliberately recorded** |
| the change under test | `bfbccf6` — the derived PG island feed, and nothing else |

## 2. The one change, and what it is expected to do

Stated before the run so the result is falsifiable rather than interpreted afterwards.
These are probe-screened numbers; the run either reproduces them on a placed and routed
database or it does not.

```
FP-ISLAND at post_powerplan     8 at risk by the M8 grid alone  ->  0 after the feed
functional stranded             55 -> 0
total stranded                  330 -> 30   (all residual fill/decap/antenna)
shorts                          0 -> 0
check_drc                       65 -> 69    RECORDED, NOT RANKED - in-tool DRC has been
                                            measured disagreeing IN SIGN with Calibre here
```

`FP_PG_ISLAND_MAX=0` is armed, so a non-zero island count **aborts the place stage** about
fifteen minutes in rather than after five hours.

## 3. Two changes deliberately NOT folded in

**Metal fill / the 6,149 density windows.** Proposed on the grounds that route must re-run
anyway. **Declined.** Attribution was the entire argument for reusing synthesis; a second
change costs exactly what the first decision bought. If the PG result and a fill result
arrive together and one is wrong, neither is trustworthy.

**The `tidelink` pin bump to `0a5857e4`** (the D2D divider CDC fix). Declined for this run
— see §4. It is a follow-up run once b4's C2 synthesis fix lands, not a rider.

## 4. THE CAVEAT — read this before quoting the result

**This stream is built from an 08-14 netlist.** The D2D link-clock divider, its CDC fix,
and every RTL change since 2026-08-14 are **not in it**. That is the correct configuration
for evaluating the PG fix — it is what makes the delta attributable — and it is **not** the
same claim as "validated on current RTL".

Nobody should later read *"the PG fix was validated"* as the stronger statement. The
honest form is: **the PG island feed was validated against the 08-14 netlist, with the
power plan as the only variable.**

Evidence that the divider is genuinely absent, with its own control — the naive probe for
this is dead, see `47` §4:

```
netlist dated              2026-08-14        divider RTL first appeared 2026-08-17
grep -c 'ratio_hold_r'     0                 grep -c 'rate_regs'   0
143 unrelated clk_div hits (QSPI, stclkctrl) — the search space IS populated
```

## 5. Machine-readable

```yaml
run_tag: pgfix-A
staged_utc: 2026-08-18
launched: false
blocked_on: [SDC_STALE_OK, tag-push]
superproject_sha: b19e8714daae2d6d52e5e04fb73dfa795895067d
tidelink_pin: aaa62ed8a1f949fbbe275984f516b2e478d55954
tidelink_head_at_stage: 0a5857e4144c90564600d651e8a1844e284215f3
toolkit_pin: 6d21f83f805226c219350fb660b62396834eccde
syn_run_tag: full-20260814
syn_netlist_sha256: 074ab30e908d93ec0b84f447
constraints_sdc_worktree: d05ce849edca9ee59c6f3c090f751e8f7bc413a6
constraints_sdc_head: 265bda64d32a014f01423eef8027b029a681b91d
change_under_test: bfbccf6
changes_declined: [metal-fill, tidelink-pin-bump]
predicted:
  fp_island_after_feed: 0
  functional_stranded: 0
  total_stranded: 30
  shorts: 0
  check_drc: 69   # recorded, not ranked
rtl_currency: STALE_BY_DESIGN   # 08-14 netlist; divider and CDC fix absent
```
