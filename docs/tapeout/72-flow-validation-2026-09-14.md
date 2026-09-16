# Flow validation: one CTS database, five routes and ECOs

    measured 2026-09-14, run manifests under build/vt7*-20260914 and build/vt8hold-20260914
    input    vt3pg-20260909's placed/CTS database for every run; one variable changes per run
    status   vt7flow / vt7eco / vt7high / vt7higheco measured and signed off; vt8hold pending
    reads    docs/tapeout/71 (mechanisms and the flow changes these runs test)

## 1. Route stage

| run | variable | setup WNS / TNS / EP | hold WNS / TNS / EP | max_tran nets | check_drc · PG opens · dangling | route runtime |
|---|---|---|---|---|---|---|
| vt3pg | control: setup_hold arm, tool-default extraction | -0.084 / -0.470 / 9 | 0.006 / 0 / 0 | 261 | 3 · 26 · 177 | 5662 s |
| vt7flow | `ROUTE_EXTRACT_EFFORT=medium`, set and read back | -0.084 / -0.470 / 9 | 0.006 / 0 / 0 | 261 | 3 · 26 · 177 | 6991 s |
| vt7high | `ROUTE_EXTRACT_EFFORT=high` (IQuantus) | **+0.072 / 0 / 0** | -0.036 / -0.066 / 3 | 298 | 3 · 26 · 177 | 8769 s |
| vt8hold | `CTS_OPT_HOLD_CELLS` = DEL* + BUFFD2..6 + CKBD2..6 (no CKBD0/1) | pending | pending | pending | pending | CTS 6599 s |

vt7flow reproduces vt3pg to the last digit. That is the determinism result:
`medium` was already the engine the tool chose, and the knob's read-back
(`extract_effort_read medium`) now says so in the manifest instead of a
pre-route print saying `low`.

vt7high closes setup **in the route stage** for the first time on this
design. Cost: +25 % route runtime, three hold endpoints (-0.036) and 37 more
max_transition nets. All three of those are the ECO stage's business.

vt8hold's CTS stage ends at setup +0.086 / 0 and hold -0.137 / 1 endpoint
(vt3pg's CTS: +0.078 / 0 and +0.005 / 0). The hold-cell list took
(`set_db opt_hold_cells` at 18:26 in the session log). Whether it stops the
route stage from manufacturing max_transition is measured by the routed
netlist's FE_PHC census, not yet available.

## 2. ECO stage (`make eco`, signoff parasitics)

| run | on | passes | setup Initial -> Final | hold Initial -> Final | max_tran (nets / terms) | edits | runtime |
|---|---|---|---|---|---|---|---|
| vt7eco | vt7flow | `-setup -hold` | -0.117 / -0.796 / 12 -> **-0.007 / -0.007 / 1** | 0.005 / 0 unchanged | 111 -> 92 nets | 10 inserted, 37 resized | 5326 s |
| vt7higheco | vt7high | `-setup -drv -hold` | **+0.066 / 0 / 0** -> +0.059 / 0 / 0 | -0.036 / 3 -> -0.024 / **2** | 107/299 -> 98/263 -> 99/265 | 10 inserted, 28 resized | 3358 s |

Two numbers matter:

- **The in-flow -> signoff gap depends on the engine.** vt7flow's in-flow
  -0.084 read -0.117 on qrc (33 ps). vt7high's in-flow +0.072 read +0.066
  (6 ps). `high` is the engine whose in-flow number the signoff view
  believes.
- **The DRV class does not depend on the engine.** ~100 nets / ~265 terms
  on both routes, before and after every pass; `-drv` recovered 9 nets and
  `-hold` gave one back. This is doc 68's CTS-hold-made class under the
  design's 0.300 ns limit, and only that decision moves it.

The two hold endpoints vt7higheco leaves are both in the fast-hot hold view
(`av_ml_libset_hold`): the multicore and eth_ss bus-matrix input-stage
registers (`reg_addr_reg[23]/D` -0.024, `reg_prot_reg[3]/D` -0.012). The
default and -40 C views are clean. A second `-hold` pass, or a hold margin,
is the obvious next experiment; it was not run.

## 3. Signoff on vt7eco (the stage's output, with controls)

| check | vt7eco | control | verdict |
|---|---|---|---|
| LEC (P&R netlist vs synthesis) | 61,599 equivalent, 0 non-equivalent, 0 aborted, 3 unmapped-unreachable DFF | vt6opt identical | pass |
| Calibre DRC, rulecheck section | 742 results / 36 rulechecks | vt7flow 742 / 36; vt4drv 742 / 36; vt6opt 747 / 39 | **the ECO stage added nothing** |
| Calibre LVS | INCORRECT, pad-ring class | vt6opt: same discrepancy signature line for line | unchanged |

The DRC row is the one to read. The by-hand ECO on vt4drv (vt6opt) added five
M1 results in three rulechecks at two sites (doc 70). The stage's ECO on
vt7flow, which asks `route_eco` for redundant cuts and re-fills, added none.
LVS differs from vt6opt only in net counts (12 fewer layout nets, 14 fewer
source nets, consistent with 10 inserted cells against vt6opt's 21 resizes);
the discrepancy lines are identical.

## 4. A seam the signoff run found

`make eco-lvs` died in its own preflight on vt7eco at 17:07: the LVS
preflight requires the PG-labelled re-stream, and the target's first recipe
line is the step that builds it. It had passed on vt6opt only because that
stream already existed from the hand-run. Fixed in 05b4648 (eco.mk); the
stage-order is now lvs.mk's own (`lvs_pg_gds: lvs-pg-preflight`,
`lvs_batch: lvs-preflight`) and `eco-lvs-preflight` defers the LVS half,
saying so, until the stream exists. `hooks/tests/prove_eco_lvs_order.sh`
runs the check on the live file and on a mutant with the shipped ordering
put back (5/5, ~5 s, no licence). Re-run with the fix: stream, preflight,
LVS, 4 min 40 s.

## 5. What a port should copy

    route   ROUTE_EXTRACT_EFFORT=high      setup closes in-flow; signoff agrees to 6 ps
    eco     ECO_OPT_ARGS="-setup -drv -hold"  then judge hold on all views
    cost    +25 % route wall, ~1 h ECO on this design

Not settled by these runs: the 0.300 ns transition limit (the DRV class is
that decision), the fast-hot hold residue (two endpoints; second pass
untested), and vt8hold's question.

## 6. What the ECO stage did not measure (found 20:00, fixed 20:30)

Reading vt7higheco's session log for the two residual hold endpoints found
this instead:

    -drv pass    IMPSP-2040 "no legal location" x17, IMPSP-2021 "Could not
                 legalize <17> instances", IMPSP-9022 "place_detail completed
                 with some error(s)"
    -hold pass   the same, <4> instances
    opt_signoff  returned normally both times
    the gate     HARD FAILURES: none / ADVISORY: none

The stage judged on opt_signoff's own slack lines and on the resize census
and never read the tool's errors. `unplaced` reads 0: the cells are placed,
illegally. `check_place`, run by hand on the databases (positional report
path; `-out_file` is refused):

| database | placement violations | of which bond pads outside the core | overlapping instances |
|---|---|---|---|
| vt7flow routed (parent) | 82 | 82 | 0 |
| vt7high routed (parent) | 82 | 82 | 0 |
| vt7eco (ECO on vt7flow; log has **no** IMPSP-2021) | 91 | 82 | **9** fillers |
| vt7higheco (ECO on vt7high; IMPSP-2021 twice) | 87 | 82 | **5** fillers |

Two facts. The 82 is the design's own number, present on every database,
and only a delta against the input can turn it into a measurement. And the
overlaps are not the failed legalization's alone: the medium-route ECO has a
clean log and nine overlapping fillers.

The mechanism, from the databases (20:12-20:16): every one of vt7eco's nine
is an ANTENNA-cell `FILLER_*` instance, and they sit in pairs and a triple
on one 0.4 um site each. In the parent the same nine instances sit at nine
distinct sites. opt_signoff's legalizer moved them. The project's smallest
filler is the ANTENNA diode (36,125 of them, every one fill-named); the
tech pack's `filler_cells` does not list it, so the stage's `setFillerMode`
never named it, and to `place_detail` those 36 k instances were standard
cells - moved, stacked, or "no legal location". The parent's fill stayed in
the database through every pass.

Toolkit 45abc9b: the filler cell list is derived from the database (the
base cells of every `<filler_prefix>_*` instance; tech pack as fallback;
the manifest says which), the fill is deleted before the first pass
(`ECO_DELETE_FILLERS`) and put back once after the ECO route - the
conventional ECO order. vt7higheco2 measures it under the new gate.

Toolkit 5118e17 gives the stage the three instruments the place, CTS and
route stages already had: a log scan for IMPSP-2021/9022/2040 after the
passes (`legalize_scan`), the message census against a new
`ECO_ERROR_ALLOWLIST` (unexpected error ids are HARD), and `check_place` on
the input database before the first pass and again after the ECO route,
judged as a delta (`place_viol`, `place_overlaps`, `place_unplaced` against
`base_*`). Every gate line is now also written to the session log. Two stub
scenarios prove each instrument fires (`eco_unlegalized.tcl`: both; 
`eco_place_regressed.tcl`: a clean log and a database that says otherwise).
Harness 126 / 0. Under the new gate both of today's ECO runs are HARD
failures, which is the correct reading of them.

## 7. The fixed stage, measured (vt7higheco2, 20:16-21:15)

`make eco -setup -drv -hold` on vt7high again, under toolkit 45abc9b (filler
list derived from the database, fill deleted before the first pass, one
re-fill after the ECO route) and the new gates:

| | vt7higheco (before) | vt7higheco2 (after) |
|---|---|---|
| legalization log scan (IMPSP-2021 / 9022 / 2040) | 2 / 2 / 21 | **0 / 0 / 0** |
| check_place, input -> after (overlapping) | 82 -> 87 (0 -> 5) | **82 -> 82 (0 -> 0)** |
| unexpected error ids | (not measured) | none |
| setup Initial -> Final | +0.066 -> +0.059 / 0 | +0.066 -> +0.066 / 0 |
| hold Initial -> Final | -0.036 / 3 -> -0.024 / 2 | -0.036 / 3 -> **-0.021 / 2** |
| max_transition (nets / terms) | 99 / 265 | **93 / 237** |
| edits | 10 inserted, 28 resized | 10 inserted, 30 resized |
| fillers | kept through the passes | 113,042 deleted, re-added |
| gate | green (wrongly) | green, HARD none, ADVISORY none |
| wall | 3358 s | 3455 s |

The two hold endpoints that remain are the same two (the multicore and
eth_ss bus-matrix input-stage registers, fast-hot view, -0.021 / -0.012),
and the tool's reason is now the real one: "15 net(s): could not be fixed
because of 'no legal location'" with the fill out of the way, on a die at
100.00 % placement density. That is a floorplan number, not a flow one.

One defect found by the run itself: the derived filler list matched
`*FILLER_*` anywhere in the instance name and so included the pad ring's
PFILLER cells (delete_filler left them alone; setFillerMode refused them,
IMPSP-5121 x8, and carried on). Toolkit 9429462 matches the prefix on the
leaf name and excludes the tech pack's `io_filler_cells`, recording the
exclusion.

Signoff on vt7higheco2's output, with controls (21:18-21:53):

| check | vt7higheco2 | control | verdict |
|---|---|---|---|
| LEC | 61,599 equivalent, 0 non-equivalent, 0 not-compared, 0 aborted | vt7eco / vt6opt identical | pass |
| Calibre DRC, rulecheck section | 742 results / 36 rulechecks, no per-rule difference | vt7high 742 / 36 | **the fixed stage added nothing** |
| Calibre LVS | INCORRECT, pad-ring class, discrepancy lines identical to vt7eco's | vt7eco, vt6opt, rc4 | unchanged |

That is the state a port should expect from `make route` at `high` followed
by `make eco -setup -drv -hold`: setup closed at signoff, hold and
max_transition down to what the floorplan allows (section 8), placement
legal, and nothing added to the DRC or LVS that the parent did not have.

## 8. vt8hold: the hold-cell lever, and what it is really made of

Same CTS input, vt7flow's route knobs, one change: `CTS_OPT_HOLD_CELLS`
restricted to DEL005..DEL4, BUFFD2..6, CKBD2..6 (no CKBD0 / CKBD1). CTS
6599 s, route 21:26.

| | vt7flow (all cells) | vt8hold (no CKBD0/1) |
|---|---|---|
| hold cells inserted (FE_PHC) | 34,736, 29 k of them CKBD0/1 | 20,709: BUFFD2 5827, DEL005 5636, DEL01 4608, BUFFD3 1230, DEL015 901, CKBD2 869 |
| max_transition nets / worst / TNS | 261 / -0.180 / -8.298 | **69 / -0.063 / -0.865** |
| setup after route (in-flow) | -0.084 / 9 | **+0.053 / 0** |
| hold after CTS | +0.005 / 0 | -0.161 / 1 |
| hold after route_design | +0.005 / 0 | -0.160 / 1 |
| hold after post-route opt | +0.006 / 0 | **-0.337 / -8.1 / 83** |
| check_drc · PG opens · dangling | 3 · 26 · 177 | 3 · 26 · 177 |

The max_transition class is the hold-cell choice: three-quarters of it goes
when the two weakest buffers are withheld, and setup closes in-flow at
`medium` because 14,000 fewer weak cells load the data paths. But the
post-route hold repair then cannot place what it needs: the tool's own
reasons are "642 net(s): no legal loc" for buffering, "335: no legal loc"
and "194: all the cells are filtered" for resizing. CKBD0 fits where a
DEL005 or a BUFFD2 does not. The die is at 85.5 % utilisation before fill
and 100.00 % placement density after it.

So the three residues that survived every flow change today have one
cause: the ~100 max_transition nets (weak hold cells chosen because they
fit), vt7higheco2's two fast-hot hold endpoints ("no legal location"), and
vt8hold's 84 (the same, with larger cells). That is a floorplan number, not
a flow knob. For a port: leave the hold-cell list alone and leave room -
utilisation in the 60s or 70s - so hold repair can use cells that do not
manufacture transition violations. On this die the trade stands as
measured, and the ECO stage on the `high` route is the best result of the
day: setup +0.066 / 0, hold 2 endpoints, max_tran 93, placement legal.

## 9. Correction (2026-09-16): rc4 was timed on parasitics

Section 3 and the artifact of 2026-09-14 said signoff STA had never run on
parasitics. Wrong, and the mistake was reading the wrong run:
`ASIC/sta/work/rc4probe-untested` in this tree is a wire-free probe made to
look at the untested-check census; its Tempus log has no extraction at all.
rc4's real evidence run is in the frozen tree at
`build/evidence/rc4-20260829/evidence/sta/sta_manifest.txt`: started
2026-08-29 11:27, `step.extract_parasitics = ok`, coupled, three Quantus
SPEFs of about 323 MB, setup +0.015 / 0 endpoints and hold +0.003 / 0 on
every view. A fresh, independent re-extraction on 2026-09-16 reproduced it.

What that changes: rc4 is closed on hold at signoff and today's best ECO
output is not (−0.021 / 2 endpoints in the fast-hot view). rc4's lineage
closed hold with 2,245 inserted repeaters, 1,891 of them CKBD0, at an
Innovus density of about 78 % during the ECO, and met "no legal location"
once. Our ECO pass ran with the same cell list on a de-filled database and
met it for 15 nets. The two endpoints are therefore a parity gap the flow
must close, not a floorplan note, and are added to the closure plan as
such. The setup comparison stands: both numbers are on parasitics, and
today's has 51 ps more margin.

Class of error: a verdict read from the wrong stream. The probe directory
is named for what it is; it should not have been the only thing I opened.
