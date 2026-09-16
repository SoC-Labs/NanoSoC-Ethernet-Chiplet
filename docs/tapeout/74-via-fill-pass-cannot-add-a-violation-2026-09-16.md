# The via-fill pass cannot add a DRC violation

    measured 2026-09-16, run vt9b-20260916 (place -> cts -> route -> Calibre DRC)
    inputs   synthesis vt1-20260902 (SYN_RUN_TAG), live floorplan and power plan
    reads    docs/tapeout/72 (vt7high, the route stream this one is compared to)
    status   RUN IN PROGRESS -- the numbers marked [pending] are filled in as
             each stage lands

## 1. The defect

`power_plan.tcl`'s marker-driven via-fill pass (`EVP_PG_ADD_VIAS=markers`,
added 2026-09-01) buys 371 -> 23 missing-via markers, 25 fewer PG opens and
551 fewer dangling PG wires. It also creates three vias the signoff deck does
not accept, and nothing downstream repaired them. On the route stream
build/vt7high-20260914 Calibre reads 36 non-zero rulechecks (742 results)
against rc4's 32 (737); three of the four extra rulechecks are this pass's:

| Calibre rulecheck | result bbox | net | Innovus check_drc record at power-plan time |
|---|---|---|---|
| VIA4.R.4:M4 | (877.220,254.150)-(877.320,254.250) | VSS | `MINCUT: Special Wire of Net VSS (M4)`, same bounds |
| VIA4.R.2__VIA4.R.3 | (1024.540,254.640)-(1024.640,254.740) | VDD | `MINCUT: Special Wire of Net VDD (M5)`, same bounds |
| M5.A.2 | (553.605,425.975)-(553.725,426.225) | VDD | `MINHOLE: Special Wire of Net VDD (M5)`, same bounds |

The control is inside our own tree: build/vt3pg-20260909 (pass on) ends the
power plan with 6 check_drc violations in `reports/pg_post_drc_edits.rep`;
build/vt2ctl-20260908 (pass off, every other pinned byte identical) ends
with 3. The 3 both carry are vendor MINCUT markers on an ethmac rf_01k pin,
present in rc4's lineage too. Innovus sees all three of the pass's
violations at power-plan time, at byte-identical coordinates to Calibre's,
so the gate can be in-flow, in the place stage, ten hours before the stream.

Why nothing repaired them: `fix_via -min_cut` walks all three sub-areas and
leaves the markers (vt3pg's log: "No minimum cut violation markers found on
special net vias" after visiting each box); the VIA4.R.4 seek in
`pg_drc_post_route_edits.tcl` (`_pg_v4r4_seek`) searches only the M5 arm
(`.top_rects`, `pgg_layer_rects $box M5`), so the M4-plate site at 877.27 is
invisible to it; there is no seek for the R.2/R.3 shape and none for MINHOLE.

## 2. The mechanism: a delta gate, not another seek

`ASIC/genus-innovus/scripts/power_plan.tcl` (the procs above the pass,
`_pgav_drc_read` .. `_pgav_drc_gate`) and
`ASIC/eth-chiplet/hooks/post_powerplan.tcl` (the call, in the PG DRC edits
block).

1. **BEFORE.** Immediately before `update_power_vias -add_vias 1`,
   `check_drc -limit 200000 -out_file $REPORT_DIR/pg_addvias_drc_before.rep`.
   The report is parsed on the spot (`_pgav_drc_read`); a report that cannot
   be read or attested stops the pass before it edits the grid. The path is
   published as `::EVP_PGAV_DRC_BEFORE_FILE`.
2. **AFTER.** The hook's own artefact, `pg_post_drc_edits.rep`, written after
   every PG repair in the flow has run: the fix_via pass (136 -> 16 on
   vt3pg), the residue cleanup (16 -> 12), the VIA4.R.4 prune and re-cut and
   the M8.S.3 trim (12 -> 6). Gating earlier would delete ~100 vias fix_via
   was about to make legal.
3. **The contract.** AFTER minus BEFORE, records keyed by type, object,
   layer and bounds verbatim from the report, must be EMPTY. A record in
   both is pre-existing; only in BEFORE is a repair; only in AFTER is the
   pass's, and the gate owns it.
4. **The repair.** For each new record, the vias the pass added
   (`::EVP_PGAV_ADDED`, the same key contract the prune uses) that have
   geometry on the record's layer, on the record's net, within 0.100 um of
   its bounds -- a marker is drawn ON the offending geometry, so the via's
   face touches it. A via whose cut sits inside the marker (a MINCUT is
   drawn on the cut) outranks a stacked neighbour that merely shares the
   face. One via per record per round is deleted -- which restores the grid
   rc4 routed with at that point, nothing more -- then check_drc re-runs
   into the same artefact file, so `pg_post_drc_edits.rep` is always the
   final state. Up to 12 rounds; more than 20 deletions is a step change
   and a refusal.
5. **Refusals, never advisory.** A new record with no added via in reach; a
   record that survives the rounds; an unattested, truncated or missing
   report; `EVP_NO_PG_DRC_EDITS=1` after the pass ran. Each aborts the place
   stage naming the type, net, layer and coordinates.
6. **Evidence.** `reports/pg_addvias_gate.rep` (before/after counts, every
   NEW record, every DELETED via with its master and point, the verdict) and
   three rows in `place_manifest.txt` / `place_pg_audit.rep`:
   `pg_addvias_new_viol_before`, `pg_addvias_new_viol_after`,
   `pg_addvias_repaired` (count + keys). The hook's post-gate
   `check_power_vias` / `check_connectivity` measure what the deletions
   cost.

The seek was NOT extended to the M4 arm. The delta gate covers that arm by
construction (the 877.27 site's Innovus record is on M4 and is in the delta),
and a widened seek feeding the literal `PG_V4R4_EXPECT {0 2}` could refuse a
run for sites the deck's escape clause allows, which no run has measured.

## 3. The proof (no licence)

`ASIC/eth-chiplet/hooks/tests/prove_addvias_drc_gate.sh` lifts the real
procs out of power_plan.tcl (tclsh, stubbed tool) and asserts the joins in
the hook by position. 30 checks:

- REALISM: fixtures are the real report bytes of vt2ctl (`pg_pre_fixvia.rep`,
  20 records: the pre-pass state, byte-identical inputs) and vt3pg
  (`pg_post_drc_edits.rep`, 6) and vt2ctl (3), site paths redacted; each
  parses to its own trailer; the stub check_drc's causal model is asserted
  EQUAL to the vt3pg capture before it is used.
- NAMES THREE: AFTER(vt3pg) minus BEFORE is exactly the three records above.
  CONTROL: AFTER(vt2ctl) minus BEFORE is empty.
- REPAIRS: on the model, one via per site, the cut-bearing one; the stacked
  neighbour, a not-ours bystander touching the marker, the hole's second
  wall and a far via survive; the final AFTER file holds only the 3 vendor
  records.
- CAN FAIL: with `_pgav_drc_new` mutated to return nothing the gate PASSES
  vt3pg's 6-record report -- the delta is the guard. With `delete_obj`
  mutated to a silent no-op the re-check refuses after the round cap,
  naming (1024.540,254.640), and the via is charged every round rather
  than blamed on its neighbour.
- REFUSES: no added via in reach (877.220 named); deletion cap; unattested,
  truncated, missing report; the clean sentence parses as the empty set.
- JOINED: snapshot before `update_power_vias`; gate between the check_drc
  artefact and the census; skip branch refuses; rows on both branches.

## 4. The run: vt9b-20260916

[pending] place: `pg_addvias_drc_before.rep` N records; `pg_post_drc_edits.rep`
6 -> 3; `pg_addvias_gate.rep` 3 NEW, 3 DELETED, 0 SURVIVE; post-gate census.

[pending] cts / route manifests: setup, hold, max_tran, conn rows against
vt7high (+0.072/0/0; -0.036/3; 298; 26 / 177 / 27).

[pending] Calibre on the route stream: 36 -> ? non-zero rulechecks, per-rule
diff against vt7high.

## 5. Also in this change

`ASIC/eth-chiplet/design.mk`: `PLACE_EXPECT_MACROS ?= 21` -- the toolkit
gate on the macro count defaulted off and the demonstrator never set it;
21 measured on every run since vt1-20260902.
