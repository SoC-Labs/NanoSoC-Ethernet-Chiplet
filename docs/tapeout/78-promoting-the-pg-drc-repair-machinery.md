# Promoting the power-grid DRC repair machinery into the toolkit

    date     2026-09-22
    scope    ASIC/genus-innovus/scripts/pg_drc_*.tcl, power_plan.tcl,
             ASIC/eth-chiplet/hooks/post_powerplan.tcl and its two proof scripts
    engine   asic-toolkit flow/power/{pg_drc_geom_lib,pg_drc_delta_gate,pg_drc_branch_seek}.tcl
    verdict  the project layer is 636 lines smaller and is now DATA; no EDA run
             was made, and this file says exactly what that leaves unproven

## THE PIN MUST MOVE BEFORE THE NEXT RUN

`power_plan.tcl` and `pg_drc_post_route_edits.tcl` now SOURCE engine files, and
they refuse rather than guess if they are not there. Until the submodule pin
reaches the toolkit commit that carries `flow/power/pg_drc_*.tcl`, a place
stage stops with "the PG DRC delta gate is not at …". That is deliberate — an
add-vias pass with no gate is how three Calibre rulechecks reached the stream —
but it means the pin bump and this commit are one change, not two.

## Why

The second die gets the mechanism, not a copy of it. Everything below was
written for this die and none of it is about this die: a set difference over
two `check_drc` reports, a search for a single-cut via in a wide plate's
shadow, and 22 rectangle primitives. What IS about this die — the coordinates,
the macro cell names, the deck constants, the tolerances — stayed here.

## What moved, and what each side keeps

| | before (project) | after |
|---|---|---|
| `pg_drc_geom_lib.tcl` | 305 lines here | **0** — engine, byte-identical bodies |
| `pg_drc_post_route_edits.tcl` | 1031 | **902** |
| `power_plan.tcl` | 3089 | **2856** |
| `pg_drc_v3r4_census.tcl` | 328 | 343 *(+15: it resolves the engine library)* |
| `pg_drc_via3r4_m4_narrow.tcl` | 680 | 695 *(+15, same)* |
| `hooks/post_powerplan.tcl` | 527 | 528 |
| **project total** | **5960** | **5324** (−636) |
| engine added | — | 1000 lines of logic + 588 of unit test |

The three engine files:

* `flow/power/pg_drc_geom_lib.tcl` — the `pgg_*` primitives, moved wholesale.
  The proc bodies are byte-identical to the ones this project shipped; only the
  header is new. Every consumer here now sources the engine copy, resolved from
  `ASIC_FLOW_DIR` and falling back to the toolkit submodule so a hand run on a
  routed database still works.
* `flow/power/pg_drc_delta_gate.tcl` — the delta gate. Snapshot `check_drc`
  before an operation, require AFTER minus BEFORE to be empty once everything
  that legitimately repairs has run, delete the object THE OPERATION ADDED at
  each survivor, re-check, refuse what is left.
* `flow/power/pg_drc_branch_seek.tcl` — the VIA4.R.4 search, generalised: the
  cut layer, the plate layer, the arming width and the branch depth are
  arguments. The two prune invariants travel with it.

What deliberately did NOT move:

* `PG_V3R4_MERGED_CELLS` — eight macro cell names. Real die data.
* `PG_LINEAGE_V4R4` / `PG_LINEAGE_M8S3` — the 24-Aug lineage coordinates. They
  are report-only (they decorate a log line with `MATCHES-LINEAGE`), and they
  are this die's history.
* The `PGD` deck-constant table. The engine takes the two lengths it needs as
  arguments and quotes no rule value of its own.
* The recipe scalars' VALUES: they stay in `design.mk`, where they are now
  joined by the gate's four.
* `pg_drc_via3r4_m4_narrow.tcl` stays project-side. It is already reachable
  through the toolkit's `ECO_MARKER_REPAIR_TCL` hook, which is the right seam
  for a repair that reads a Calibre results file: the engine calls it, the
  project owns it.

## One class of defect is now impossible rather than guarded

`power_plan.tcl` and `pg_drc_post_route_edits.tcl` each had their own function
for keying a via (`_pgav_via_key`, `_pg_v4_key`), with a comment in both saying
the formats were a CONTRACT, and a guard that fired if the added-set matched
nothing. Both now call the engine's `pgdg_via_key`. The guard stays — it still
catches a set recorded against a different database — but it can no longer be
tripped by the two halves disagreeing, because there is one half.

## Knobs

`EVP_PG_ADD_VIAS_GATE_{ROUNDS,REACH,MAX_DEL}` became
`PG_DRC_GATE_{ROUNDS,REACH,MAX_DEL}` plus `PG_DRC_GATE_LIMIT`, read through the
engine's own registry so they reach the run manifest. The `EVP_` spellings are
honoured when the new name is unset and print a deprecation line; the new name
wins when both are set. `design.mk` now sets all four explicitly, each with the
measurement behind it.

## What was verified, and how

| | |
|---|---|
| toolkit unit suite | **582 passed, 0 failed**, from 542 at HEAD: +26 delta gate, +14 branch seek. Measured on a tree carrying HEAD plus only this change |
| toolkit stage harness | **146 passed, 1 failed** on that tree, from 142 at HEAD: +5 for the gate. The one failure is `compare.admits-real`, which needs `git describe` and the tree it ran in is a tar extraction, not a checkout — the same case passes in the real checkout, where the harness reads **150 passed, 0 failed** (142 + my 5 + another workstream's 3) |
| `t_mutation_inventory.sh` | **11 passed, 0 failed**; `stage-scenarios` 43 → 45 with the review note the file demands |
| `prove_addvias_drc_gate.sh` | **29 checks + the join block**, now lifting the procs from the ENGINE file and asserting the project's joins to it |
| `prove_v4r4_prune.sh` | **20 checks**, lifting five procs from the engine and refusing if the project re-grows a private copy |
| every other project proof | `prove_eco_lvs_order` 5, `prove_filler_route_eco_gate` 12, `prove_opt_signoff_setup` 20, `prove_post_cts_guard` 16, `prove_pre_cts_gen_skew` 33 — unchanged |
| equivalence of the moved library | the code region of `pg_drc_geom_lib.tcl` is **byte-identical** (md5 `d250b55c…`) to the file this project shipped |

Each new gate was shown to FAIL, by mutation, before being counted:

* added-set filter removed from `pgdg_candidates` → the stage case
  `pg.gate.new-unowned` PASSES (the gate deletes a bystander) and the harness
  goes red; the unit case `gate-refuses-a-violation-it-did-not-cause` fails too.
* `delete_obj` removed from `pgdg_repair` → `pg.gate.repairs` goes red with the
  violation surviving twelve rounds.
* `pgdg_drc_new` stubbed to "nothing is new" → the gate passes a report with a
  real new violation, which is what makes the set difference the gate.
* `pgg_conn_of` removed from the seek (the branch need not touch the plate) →
  the disconnected-plate control fails; the GoodBranch escape removed → the
  multi-cut control fails.

A harness defect was found on the way and fixed: `prove_addvias_drc_gate.sh`
wrote its join failures without a trailing newline, and `while read` does not
run its body for an unterminated last line — so the LAST join failure was
dropped silently. It had been hiding one: the assertion "the BEFORE snapshot is
taken before `update_power_vias`" was comparing against a sentence in a comment
400 lines above the call, and had been red and invisible since it was written.

## WHAT IS NOT VERIFIED

**No EDA tool was run.** Not Innovus, not Calibre, not Tempus. There is no
place, cts, route or ECO run behind this change, and the eight hours one costs
were not spent. Specifically unproven:

1. That the promoted procs behave identically **inside Innovus** on the real
   database. The evidence is textual and structural: byte-identical geometry
   bodies, the same logic renamed, the real vt2ctl/vt3pg report bytes through
   the gate, and the stub harness. None of that is a tool.
2. That `power_plan.tcl` and `pg_drc_post_route_edits.tcl` still SOURCE cleanly
   under Innovus. Both parse (`info complete`) and both are exercised by the
   proof scripts, which lift real procs out of them — but nothing sourced them
   in a tool session.
3. That the resolution of `ASIC_FLOW_DIR → flow/power/…` finds the engine files
   in a PINNED run, where the hooks are copied into the run directory. The
   fallback climbs from `[info script]`, which is the same idiom the prove
   scripts use and which has been wrong here once before (2026-08-25).
4. That the run's numbers are unchanged. The claim is that nothing about the
   decisions changed; the only way to confirm it is a place stage and a
   `pg_addvias_gate.rep` that still reads `new_before_repair 3, repaired 3`.

The cheapest real check is a **place stage alone** on the current floorplan:
it reaches the gate in minutes, writes `pg_addvias_gate.rep` and
`pg_v4r4_sites.rep`, and settles 1, 2 and 4 together.
