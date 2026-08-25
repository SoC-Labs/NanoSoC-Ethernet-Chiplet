<!--
  ci/fixtures/floorplan-hazards — fixtures for scripts/ci/check_floorplan_hazards.py
  A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.

  Copyright 2026, SoC Labs (www.soclabs.org)
-->
# `ci/fixtures/floorplan-hazards`

Fixtures for `scripts/ci/check_floorplan_hazards.py --selftest`, which is the
ground-truth validation for the pre-P&R floorplan hazard checker.  Two kinds:

**A pinned arm carries its OWN power plan.**  A pinned floorplan read against
the live `power_plan.tcl` is not a pinned arm — every class-1/2 number is
anchored on the M9 band grid, and that grid would drift out from under the
fixture the next time somebody edits the stripes.  Each directory below holds
both files from the same revision, and `--selftest` reads them as a pair.

## must-flag — the known-bad floorplans

| fixture | what it is | what the checker must say |
|---|---|---|
| `baseline-78dac42/floorplan.tcl` | `git show 78dac42^:ASIC/genus-innovus/scripts/floorplan.tcl` — the placement before "floorplan: phase-align the flash_cache macros (nx01gSX)" | class 1 on **exactly** `way0_..._word_3_i` and `way1_..._word_0_i`; class 2 on **exactly** the network-core `rf_32k` and `rf_16k`, with clearing moves −1.100 and −1.150 to the micron; class 3 covering all four macros that carried the 22 M4.S.2.1 markers; class 4a **clear on both cache macros** |
| `baseline-78dac42/power_plan.tcl` | the same revision's power plan | the band grid must come out `244.5 + 60k`, band height 3.6 |
| `class4a-2cd12a4/floorplan.tcl` | `git show 2cd12a4^:...floorplan.tcl` — the placement that hard-failed `gdsrun-20260825-resynth` one hour into a 2h38m route | class 4a on **both** `way0_..._word_3_i` and `way1_..._word_0_i`, each exactly half an M3 track pitch off grid, each with a first-track clearance below the cut rule, and each prescribing **+0.100** — which is the move commit 2cd12a4 actually applied |
| `class4a-2cd12a4/power_plan.tcl` | the same revision's power plan (byte-identical to HEAD's) | the band grid must come out `244.6 + 60k` |

Those two grids are **0.1 apart**, and that is the concrete reason each arm pins
its own power plan rather than borrowing the live one: the M9 ladder's start
offset moved between the two revisions.  A pinned floorplan read against
today's stripes would be measured against bands that did not exist when it was
written, and every class-1/2 number on that arm would be quietly wrong.

### why the class-2 arm moved off the worktree

It used to read *"current floorplan must flag net imem rf_32k and net dmem
rf_16k"*, checking the **worktree**.  Commit 93ec57d fixed both macros, and from
that day the selftest printed five `[FAIL]` lines — for a repair.  An
expectation that goes red when the defect it describes is **fixed** is not
ground truth, it is a countdown, and a selftest that is red for a known-benign
reason gets ignored exactly like a gate that is.

The arm now sits on the pinned revision that carries the defect, and the
worktree gets the opposite assertion: *class 2 is 0, the fix landed and has
stayed landed*.  Both directions, neither of them rotting.

### the class-4a ground truth

`flash_cache_data` obstructs its cut layers over 100 % of its footprint, so a
pin is reachable only planar and the first layer change must sit **outside** the
footprint — on a track of the escape metal, with its cut clear of the macro's
own cut obstruction.  The macro's height is not an integer number of escape
pitches, so a mirrored placement inverts the pin-edge phase, and at `2cd12a4^`
two macros sat exactly half a pitch off.  The first track outside was then too
close for the cut, the cheapest legal escape cost an extra track, and two pins
took the last track *inside* the footprint instead: five stage-owned DRC
violations, all on cache data bit 123.

Every operand of that arithmetic — track pitch, track origin, cut extent, cut
spacing — is read from the technology LEF at run time, so none of it is written
into the fixture or into the checker.

The assertions are **by macro, never by total**.  A total would rot the moment
an unrelated macro is fixed or added — and it would have rotted immediately:
the `78dac42^` arm carries one further class-4a flag (`eth_scratch_tx`'s
`rf_08k`) that predates every macro move in this history, and the worktree
carries three.  Those are reported as information, not asserted.

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

`baseline-78dac42/` and `class4a-2cd12a4/` must NOT be regenerated — they are
pinned historical revisions, and they are the only things proving the checker
catches defects that really happened.  Regenerating one would replace the
recorded defect with today's floorplan and leave a selftest that passes because
it no longer tests anything.
