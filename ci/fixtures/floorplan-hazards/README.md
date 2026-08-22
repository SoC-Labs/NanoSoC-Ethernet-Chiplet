<!--
  ci/fixtures/floorplan-hazards — fixtures for scripts/ci/check_floorplan_hazards.py
  A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.

  Copyright 2026, SoC Labs (www.soclabs.org)
-->
# `ci/fixtures/floorplan-hazards`

Fixtures for `scripts/ci/check_floorplan_hazards.py --selftest`, which is the
ground-truth validation for the pre-P&R floorplan hazard checker.  Two kinds:

## must-flag — the known-bad floorplan

| fixture | what it is | what the checker must say |
|---|---|---|
| `baseline-78dac42/floorplan.tcl` | `git show 78dac42^:ASIC/genus-innovus/scripts/floorplan.tcl` — the placement before "floorplan: phase-align the flash_cache macros (nx01gSX)" | class 1 on **exactly** `way0_..._word_3_i` and `way1_..._word_0_i`; class 3 covering all four macros that carried the 22 M4.S.2.1 markers |
| `baseline-78dac42/power_plan.tcl` | the same revision's power plan (byte-identical to HEAD's — the M9 ladder did not move) | the band grid must come out `244.5 + 60k`, band height 3.6 |

The class-1 expectation is 78dac42's own measurement: *"Exactly two did:
way0_word_3 (top 426.40 vs 424.500) and way1_word_0 (top 246.40 vs 244.500)."*

The class-3 expectation is
`ASIC/genus-innovus/calibre_runs/drc_toolkit_20260817/nanosoc_eth_chiplet_pads.drc.results`:
28 `M4.S.2.1` markers, of which the 22 that are exactly **0.155 um** wide sit on
`way1_word_1` x13, `way1_word_3` x6, `way0_word_2` x2, `way1_word_2` x1.  That
0.155 is not a coincidence — it is the gap from a 0.35 um M4 PG pin to the
macro's own internal M4 obstruction column, straight out of
`flash_cache_data.lef`, and the checker prints that census next to the flags.

## must-refuse — vacuity guards

A check that measures nothing must exit **2**, not 0.  Each of these is the live
`floorplan.tcl` with one thing broken:

| fixture | mutation | guard it must trip |
|---|---|---|
| `vacuity-no-macros/` | every `place_macro` commented out | "zero place_macro lines parsed" |
| `vacuity-stale-pattern/` | one pattern renamed `word_3` -> `word_9` so it resolves to 0 instances | "place_macro pattern(s) did not resolve" — the same failure that made `power_plan.tcl`'s `split_row` silently run on 15 of 21 macros |
| `vacuity-wrong-die/` | `-die_size 1600 2000` -> `1700 2000` | derived core box != the measured `(205,205)-(1395,1795)`, so every band would be anchored wrong |

Regenerate the vacuity fixtures after a legitimate `floorplan.tcl` change:

```bash
cd ci/fixtures/floorplan-hazards
FP=../../../ASIC/genus-innovus/scripts/floorplan.tcl
sed 's/^place_macro/## place_macro/'                       $FP > vacuity-no-macros/floorplan.tcl
sed 's/word_3_i}/word_9_i}/'                               $FP > vacuity-stale-pattern/floorplan.tcl
sed 's/-die_size 1600 2000/-die_size 1700 2000/'           $FP > vacuity-wrong-die/floorplan.tcl
```

`baseline-78dac42/` must NOT be regenerated — it is a pinned historical
revision, and it is the only thing proving the checker catches a defect that
really happened.
