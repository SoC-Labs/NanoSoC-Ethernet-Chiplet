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
