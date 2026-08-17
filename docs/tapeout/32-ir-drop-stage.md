# The IR-drop stage: what it measures, what it refuses, and what it cannot see

Date: 2026-08-17. Status: **wired into the flow and running.**

This is the stage description and the operator's page. The measurement record —
every number, every trap, and the history of how the pads question was settled —
is `31-power-delivery-measured.md`, and the paper design that preceded both is
`30-ir-drop-gate-design.md`.

---

## 0. What changed

Before tonight this pipeline had **never computed a voltage.** The two things
nearest to a power-delivery check were:

- `pg_capacity`, which rates the grid's **electromigration ceiling** in
  milliamps. A capacity is not a voltage, and the report says nothing about
  whether any cell on the die actually receives its supply.
- `2b_pnr_place_eval.tcl` §12, which halts the run on an **RV-via count** with a
  floor of 8. That floor was derived from one day's tool configuration, and net
  VDD has no RV via at top level at all — so the count was guarding a plane the
  core supply does not cross.

There is now a measured voltage, a stage that produces it, and a gate that
decides whether it may be believed.

| piece | path | needs a licence? |
|---|---|---|
| the stage | `ASIC/genus-innovus/rail/rail_run.tcl` | yes — Innovus + Voltus |
| inputs, resolved once | `ASIC/genus-innovus/rail/rail_env.tcl` | no |
| the gate | `ASIC/genus-innovus/rail/rail_gate.py` | **no** |
| the supply contract | `ASIC/genus-innovus/rail/rail_budgets.txt` | no |
| the make targets | `ASIC/genus-innovus/rail_project.mk` | — |
| the manifest rows | `ci/signoff.yaml`: `ir-drop`, `ir-drop-selftest` | — |

```bash
make -C ASIC/genus-innovus rail            # solve, then judge   (~25 min)
make -C ASIC/genus-innovus rail RAIL_RUN_TAG=full-20260814
make -C ASIC/genus-innovus rail-gate       # judge only, no licence, no database
make -C ASIC/genus-innovus rail-selftest   # can the gate fail?  (~1 s)
make -C ASIC/genus-innovus rail-status
```

---

## 1. The result

**Database: `ASIC/eth-chiplet/build/fp1505/work/nanosoc_eth_chiplet_pads_routed`.**

Run 2026-08-17 23:26–23:50, Voltus rail commands under Innovus 21.11, `-method
static`, `techonly` PGV, 125 °C, 10 voltage sources at the ten core supply pads.
Verdict artefact: `ASIC/genus-innovus/rail/work/fp1505/verdict.json`.

### The completeness assertions, which come first

| assertion | required | measured |
|---|---|---|
| instance coverage | ≥ 99% | **350,718 of 351,211 = 99.86%** |
| voltage sources in circuit | = the 10 core supply pads in the database | **10** (6 VDD + 4 VSS) |
| current accounting, solver vs demand file | 0.90 – 1.10 | **0.9975** |
| **demand file vs the implementation run's own rail table** | ≤ 1% | **0.0011%** — 54.5906 mW against `imp_power.rep`'s `VDD 1.08 … 54.59` |
| parser vs tool worst drop | ≤ 1 mV | **0.32 mV** (6.320 recomputed vs 6.000 printed; the tool prints 3 d.p.) |
| divisor | agrees with `report_power` | **1.08 V = 1.08 V** |
| method | `static`, no ERA, no `-stream_file` | as declared |

The fourth row is the one worth pausing on. The current-accounting check compares
the solver against the file it was handed, which is close to an identity. The
demand-vs-flow check compares that file against `report_power`'s **own per-rail
attribution**, computed in a different session by a different code path for a
different purpose, and it agrees to four decimal places. That is what makes the
core-box filter a measurement rather than an assumption.

### The voltages

| | VDD (6 pads) | VSS (4 pads) |
|---|---|---|
| worst deviation from nominal | **6.32 mV droop** | **8.89 mV rise** |
| average deviation | 5.32 mV | 7.22 mV |
| total current | 50.420 mA | 50.528 mA |
| per-pad current | 7.89 – 8.97 mA (±6.4% about 8.40) | 12.07 – 13.12 mA (±4.2% about 12.63) |

**Worst effective collapse = 15.00 mV = 1.389% of 1.08 V**, VDD droop and VSS
rise **at the same instance**.

Note what that is *not*: the two worst maxima sum to **15.21 mV**, and quoting
that would be both pessimistic and uninformative — it says nothing about whether
the two worsts are co-located, which is the only version of the question that
matters. `31-power-delivery-measured.md` quotes 15.3 mV for the 08-12 database on
exactly that arithmetic; the co-located figure is the one to use, and the gate
reports both so the difference stays visible.

**Every pad carries current, and no pad is doing double duty.** VSS is the worse
half, which is what four supply pads against six should give.

### The distribution — and the real shape of this grid

| p50 | p95 | p99 | p99.9 | max | mean |
|---|---|---|---|---|---|
| 1.240% | 1.340% | 1.357% | 1.372% | **1.389%** | 1.180% |

**max / p50 = 1.12.** This grid has essentially no tail. It does not have
hotspots; it sags almost uniformly, and every instance on the die sits within
15% of every other. Zero instances exceed the 3% worst-collapse budget, so the
hotspot-versus-grid classifier has nothing to classify.

That flatness is also why one budget binds — see below.

### Where the droop happens

| layer | VDD droop | VSS rise |
|---|---|---|
| metal9 | 3.79 mV | 4.48 mV |
| metal8 | 3.84 mV | 4.56 mV |
| metal7–3 | 6.11 mV | 8.49 mV |
| metal2 | 6.12 mV | 8.89 mV |
| metal1 | **6.32 mV** | **8.89 mV** |

**60% of the VDD droop has already happened by the time current reaches M8** —
in the rings and the pad connections — and the entire descent from M7 to the cell
rail adds 2.5 mV more. If metal is to be spent on this problem, it belongs at the
top of the stack, not at the taps.

### The verdict: **FAIL_HARD**

Two criteria are not met, and neither is the headline voltage.

1. **`pg.disconnected` — HARD. 330 instances have no path to a supply rail.**
   Not a margin: those cells do not power up. Detailed in §2b below.
2. **`budget.eff_mean_pct` — BUDGET. Mean collapse 1.180% against a 1.0%
   budget.** Every other budget passes with room: worst 1.389% of 3.0%, p99
   1.357% of 2.0%, VDD droop 0.585% of 2.0%, VSS rise 0.823% of 2.0%.

**On that second one, read the shape before reading the number.** The mean
budget was written at 1.0% against a 3.0% peak, which presumes a distribution
with a tail — the usual case, where the typical instance sits well below the
worst. This grid has no tail, so its mean is 85% of its maximum and a
peak-versus-mean ratio of 3:1 is simply the wrong model for it. **The threshold
has deliberately NOT been changed.** Editing a budget after seeing the number it
judges is the exact ratchet `rail_budgets.txt` refuses, and the refusal is
worth more than the green tick. It is flagged here as the one calibration
question for the chip owner: either the mean budget is re-derived from the
supply contract (not from this result), or the flatness is accepted as a
property of a ring-fed grid and the criterion is retired in favour of p99.

Also recorded, and **not** a pass: **`em.current_density` = NOT_ANALYSED.**

### 2b. The defect this found: 330 instances with no path to a supply

They are not scattered. At 40 µm linkage they resolve into five sites:

| site | x | y | instances |
|---|---|---|---|
| A | 1034.2 – 1054.8 | 352.6 – 493.0 | 158 |
| D | 869.2 – 906.8 | 489.4 – 491.2 | 76 |
| B | 1051.8 – 1054.2 | 1544.2 – 1592.8 | 44 |
| C | 1043.2 – 1054.8 | 262.6 – 280.6 | 30 |
| D′ | 879.8 – 894.4 | 439.0 – 440.8 | 22 |

**These are the same coordinates that `31-power-delivery-measured.md` recorded on
the 08-12 database.** The floorplan changed, five days passed, and the sites did
not move. This is a reproducible, unfixed defect, not a one-run artefact — which
also means it is not going to be fixed by the next re-route on its own.

Split by net: **87 instances have no VDD path, 176 no VSS path, and 67 have
neither.**

Split by what they are — and this changes the severity, so it is stated rather
than left as one number:

| | count | what it means |
|---|---|---|
| physical-only (FILL, DCAP, ANTENNA) | **275** | not a logic failure. But a disconnected DCAP is decoupling capacitance that does nothing for droop, and a disconnected ANTENNA diode is an antenna diode that does not protect — both are silent losses of exactly the mitigations they were placed for. |
| **functional cells** | **55** | these do not power up. |

Of the 55: **26 clock buffers** (CKBD0/1/2, CKND1/2, BUFFD1/6), **4 flip-flops**
(DFCNQD1/D4), and 25 combinational gates. They sit in the QSPI flash cache
subsystem, the ethernet scratch-TX path and the network core.

**Two independent tools agree, on this same database.** The flow's own
`check_connectivity` reports **35 VDD and 30 VSS** `IMPVFC-200` "pieces of the
net are not connected together" — but reports them as informational lines among
hundreds, never places them on the die, and does not fail the run. The rail solve
is what turns those pieces into a list of named cells with coordinates. That is
the argument for this stage in one sentence: the evidence was already in the
flow's output and nothing was reading it.


---

## 2. Which database, and why — a correction to the record

`31-power-delivery-measured.md` §1 opens by saying that the only databases in
the tree carrying all 34 supply pads are under `ASIC/genus-innovus/runs/`, and
that *"everything under `ASIC/eth-chiplet/build/` is pad-less: synthesis deleted
the supply pads because they are instantiated with empty port lists"*, so
*"no power-delivery question can be asked of those builds."*

**That is no longer true, and the whole measurement below rests on it not being
true.** Read out of the databases themselves:

| database | routed at | `PVDD1DGZ_G` | `PVSS1DGZ_G` |
|---|---|---|---|
| `build/fp1505/…_routed` | 2026-08-17 21:32 | **6** | **4** |
| `build/full-20260814/…_routed` | 2026-08-17 13:52 | **6** | **4** |
| `runs/20260812T133501Z_route-baseline-gds/…_eval_route` | 2026-08-12 | 6 | 4 |

Same masters, same ten instances, same coordinates. The pad-less builds were the
ones that predate the pad fix — the `padfix` run directory in the same tree is
where it landed — and the sentence in §1 was written against those and never
re-checked. **The archived route-baseline database is no longer the only place
this question can be asked, and it should no longer be the place it is asked**,
because it carries three known liabilities the current builds do not: its
`libs/lef/` entries are symlinks into the live tree, both ROM LEFs were rebuilt
two days after it was saved, and it therefore needs `read_db_file_check false`
and cannot be shown byte-identical to what was saved.

A warning for whoever checks this next: **the pads are not in
`nanosoc_eth_chiplet_pads.place.gz`.** Grepping that file returns zero on the
pad-correct archived database too, which is how a first pass at this concluded
the build databases were still pad-less. They are in
`nanosoc_eth_chiplet_pads.fp.gz`, as `IO:` records. A test that returns the same
answer on a database known to be correct is not measuring what it claims to.

`fp1505` was chosen over `full-20260814` because it is the more recent route
(21:32 against 13:52 the same day) and carries the 1505.60 floorplan. Both were
run, so the choice does not have to be taken on trust — see §5.

---

## 3. What the gate asserts, and why each one exists

The gate is `rail_gate.py`. It reads the run's census and the run's artefacts and
recomputes the verdict; **it never consults an exit code**, not the tool's and
not the stage script's. On this design `report_rail`, `report_resistance` and
`set_power_pads` have all been observed printing `**ERROR` and returning
success.

**The failure mode it exists for is not a large IR drop.** A large drop
announces itself. The dangerous case is a run that analysed a fraction of the
design, or was handed no current at all, **completing successfully and reporting
a small drop** — the best possible result produced from no data. Every
completeness assertion below is there because some version of that has already
happened on this design.

### HARD — the run is broken or unverified, and no number may be quoted

| assertion | the specific event it stands for |
|---|---|
| `method.static` / `method.no_era` | ERA's grid-completion engine invents virtual follow-pins and vias. On a design with real PG opens it bridges exactly the defects worth finding. |
| `method.no_stream` | `set_rail_analysis_config` has first-class `-stream_file` support, so it is an attractive wrong turn — and because LEF obstruction streams as conductor it fails in the **flattering** direction. |
| `divisor.agrees` | Four contradictory records of the core supply voltage exist in this project. 1.20 against 1.08 is 11.1% — the width of a ±10% acceptance band — and every number stays plausible. The stage re-reads the voltage out of `report_power`'s own rail table and the gate fails on disagreement. |
| `vsrc.count` | *"Voltage Source Added/Total: 6/6 (100.00%)"* is printed on runs that end with **zero** sources in the circuit. That cost a week and a dead-chip scare. The count is compared against the pad count **measured in the same session**, never a hardcoded 10 — a hardcoded number cannot notice a pad that was deleted. |
| `coverage.instances` | A solve covering 10% of the design reports a small drop. |
| `coverage.current` | Catches an empty, truncated or mis-scaled demand file. |
| `coverage.demand_vs_flow_power` | The check above compares the solver against the file it was handed, which is close to an identity. **This one compares the demand file against the implementation run's own per-rail power table** — a different code path, a different session, an artefact this stage cannot influence. |
| `coverage.nets` | A domain run that solved VDD and quietly skipped VSS must not yield a VSS verdict. |
| `parity.parser_vs_tool` | The worst drop recomputed from the per-instance report against the tool's own summary, within 1 mV. Disagreement means trust neither. |
| `pg.disconnected` | Instances with **no path to a supply rail**. Not a margin — those cells do not power up. |
| `em.current_density` | In static mode, with no `-em_models` and no `-process_techgen_em_rules`, the tool **disables** current-density analysis and the run still succeeds with the report simply absent. Recorded as `NOT_ANALYSED`; hard at `--tier signoff`. |
| `spatial.classification` | Over-budget instances spread across many tiles are grid inadequacy, which no local repair addresses. Promoted from BUDGET. An exceedance with **no coordinates** is treated as distributed: an unprovable "it is only a hotspot" is not a mitigation. |

### BUDGET — measured, and over a threshold

Worst effective collapse, its p99 and its mean, plus VDD droop and VSS rise
separately. All as a fraction of the **analysis voltage**, and the gate refuses
to run at all if that voltage has no recorded provenance.

**Effective collapse is the VDD droop and the VSS rise at the *same instance*,**
taken from the combined per-instance report. Never the sum of two independent
maxima: that is pessimistic *and* it hides the case where the two worsts are
co-located, which is the dangerous one. On this design the two differ, and §5
gives the numbers.

### The anti-ratchet rule

Every threshold in `rail_budgets.txt` carries a `_source` string.
`rail_gate.py` **refuses to run — before judging anything** — if a source is
missing, empty, or matches
`previous_run|last_run|as_measured|measured|today|observed|baseline`. A budget
set to the day's measured number cannot fail: it is a record of what happened
wearing the costume of a requirement, and this project has written one before.
Enforced at load time, not at review time.

---

## 4. Proving the gate can fail

This project found four gates in one week that could not fail. This one is
demonstrated failing in **four independent ways**, three of them automated and
runnable by anyone.

### (a) The mutation battery — 22 cases, `make -C ASIC/genus-innovus rail-selftest`

Each case is a rail run broken in one specific way this project has *already*
been misled by, not an invented mutation. It runs in about a second, needs no
licence, no database and no PDK, and is wired in as its own manifest row
(`ir-drop-selftest`, `gate: block`) so it runs before the row it guards.

```
[ok] baseline_healthy            expect PASS         got PASS
[ok] no_voltage_sources          expect FAIL_HARD    got FAIL_HARD   via vsrc.count
[ok] too_few_sources             expect FAIL_HARD    got FAIL_HARD   via vsrc.count
[ok] too_many_sources            expect FAIL_HARD    got FAIL_HARD   via vsrc.count
[ok] era_method                  expect FAIL_HARD    got FAIL_HARD   via method.static
[ok] stream_derived_grid         expect FAIL_HARD    got FAIL_HARD   via method.no_stream
[ok] wrong_divisor               expect FAIL_HARD    got FAIL_HARD   via divisor.agrees
[ok] low_instance_coverage       expect FAIL_HARD    got FAIL_HARD   via coverage.instances
[ok] empty_demand                expect FAIL_HARD    got FAIL_HARD   via coverage.current
[ok] inflated_demand             expect FAIL_HARD    got FAIL_HARD   via coverage.current
[ok] missing_iv                  expect FAIL_HARD    got FAIL_HARD   via artefact.iv
[ok] parser_tool_disagree        expect FAIL_HARD    got FAIL_HARD   via parity.parser_vs_tool
[ok] disconnected_instances      expect FAIL_HARD    got FAIL_HARD   via pg.disconnected
[ok] run_did_not_complete        expect FAIL_HARD    got FAIL_HARD   via run.completed
[ok] distributed_exceedance      expect FAIL_HARD    got FAIL_HARD   via spatial.classification
[ok] em_not_analysed_at_signoff  expect FAIL_HARD    got FAIL_HARD   via em.current_density
[ok] em_analysed_at_signoff      expect PASS         got PASS
[ok] over_worst_budget           expect FAIL_BUDGET  got FAIL_BUDGET
[ok] over_p99_only               expect FAIL_BUDGET  got FAIL_BUDGET
[ok] vss_worse_than_vdd          expect FAIL_BUDGET  got FAIL_BUDGET
[ok] anti_ratchet                expect GATE_ERROR   got GATE_ERROR
[ok] missing_provenance          expect GATE_ERROR   got GATE_ERROR
22 passed, 0 failed
```

Two of those cases carry more weight than the rest. **`baseline_healthy` is the
positive control**: without it, a gate that rejects everything would score 21/22
and look excellent — and the `ir-drop-selftest` row asserts that this specific
line reads PASS, precisely so that a battery of all-negative cases cannot pass
its own tally. **`em_analysed_at_signoff`** is the same idea one level down: a
parser that always answered NOT_ANALYSED would satisfy the case above it.

### (b) `signoff.py prove` — real artefacts, in the tool's own format

The `ir-drop` row carries `check_proof`, and the fixtures are **cut down from
the real fp1505 artefacts** rather than written by hand:

```
ir-drop  must_pass:pass                            ok  rc=0
ir-drop  must_fail:fail-no-voltage-sources         ok  rc=2
ir-drop  must_fail:fail-low-coverage               ok  rc=2
ir-drop  must_fail:fail-era-method                 ok  rc=2
ir-drop  must_fail:fail-disconnected-instances     ok  rc=2
ir-drop  must_fail:fail-over-budget                ok  rc=2
ir-drop  must_fail:fail-no-census                  ok  rc=1
0 problem(s)
```

`fail-disconnected-instances` needed nothing invented: its `NA` rows are real
instances from the real run. `fail-no-census` proves the arm that matters most in
CI — **an absent result is a failure, not a pass.**

### (c) Live fault injection into the real pipeline

Two faults planted against the **real fp1505 census**, then removed. The budgets
file was never modified — each fault was a copy, so there is no window in which a
weakened contract existed on disk (`diff` against a pre-injection copy confirms
it byte-identical afterwards).

| fault | expected | gate said | exit |
|---|---|---|---|
| worst-collapse budget cut 3.0% → 0.1% | reject | `FAIL_HARD` — budget exceeded, and *promoted* because the exceedance covers 544 tiles, i.e. distributed | **2** |
| budget provenance rewritten to *"set from the value measured on the previous run"* | refuse to judge at all | `RAIL GATE REFUSED TO JUDGE … A threshold set from what was measured cannot fail.` | **3** |
| (control) the real budgets | reject on the real defect | `FAIL_HARD` via `pg.disconnected` | **2** |

The first is worth reading twice: dropping the threshold did not merely flip a
BUDGET row, it changed the *classification* from "nothing over budget" to
"distributed" and promoted the failure to HARD — the spatial logic operating, not
just a comparison.

### (d) A deliberately broken real tool run

`rail_negative_control.tcl` runs the identical solve on the identical database
with **one option removed** — `-short_pin_nodes true`, whose default is FALSE.
Everything the fixtures cannot show, this does: Voltus itself completes, writes
its artefacts, and reports success.

```
NEGCTL this run is DELIBERATELY BROKEN: -short_pin_nodes is omitted.
CENSUS solve.voltage_sources=0
NEGCTL voltage sources in circuit: 0 (the real run has 10)

$ rail_gate.py --census work/fp1505-negctl/census.txt
  [FAIL] HARD  vsrc.count    0 voltage sources in the circuit vs 10 core supply
                             pads in the database.
  [FAIL] HARD  artefact.iv   no non-empty per-instance voltage report
  VERDICT: FAIL_HARD                                            exit 2
```

The fault is one word. It is not a knob in `rail_run.tcl`: a production stage
that can be told to produce a wrong answer is one environment variable away from
producing one by accident, and the accident would look exactly like a passing
run. The fault lives in its own file, writes to its own tag, and is never on the
path `make rail` takes.

### (e) And one unplanned demonstration

The `full-20260814` run failed for a reason nobody arranged — see §5 — and the
gate rejected it correctly and for the right reasons, on a database that was
never prepared as a test case.

### A false green found in this gate, by this gate's own contact with real data

Worth recording, because it is the disease this stage exists to treat and it
appeared *inside the cure*. The EM check first read

```python
re.search(r"Minimum, Average, Maximum J/Jmax:\s*(.*)", txt)
```

`\s*` matches a **newline**. On the real report the J/Jmax field is empty and the
next line is `Number of Violations: 0`, so the regex captured that next line and
the gate reported EM as **analysed** — a false green, in the one check whose
entire subject is not reporting false greens. The synthetic fixtures did not
catch it because they had been built with the same shape and no case asserted
the EM verdict. Both were fixed: the field must now stay on its own line **and**
contain a digit, and two EM cases were added to the battery in opposite
directions.

The lesson is the fixtures' own README's: a fixture derived from a real artefact
is evidence; one derived from what we believe the tool prints is a second copy
of our belief.

---

## 5. Both candidate databases

Both were run to completion, on the same night, with the same script. They did
not produce the same kind of result.

| | `fp1505` | `full-20260814` |
|---|---|---|
| routed | 2026-08-17 21:32 | 2026-08-17 13:52 |
| core supply pads | 6 VDD + 4 VSS | 6 VDD + 4 VSS |
| PG extraction | completed | **aborted** |
| rail artefacts | 341 written | **none** |
| gate verdict | `FAIL_HARD` (330 PG opens) | `FAIL_HARD` (`no_rail_artefact`) |

**`fp1505` is the database used, and the reason is stronger than "it is newer".**
The `full-20260814` run did not fail for want of setup. Voltus's extractor
stopped on it:

```
** ERROR: (VOLTUS_EXTR-1223): Detected a short between "VDD" and "VSS" nets
   at (845.075,1546.72) resulting in net, "VDD" being merged into "VSS".
   This short is observed during the geometry merge operation on the current
   processing layer, metal5.
** ERROR: (VOLTUS_EXTR-1281): voltus_extractor could not find any net shape
   data to extract.
** ERROR: (PRL-387): "Rail Analysis" failed to finish successfully.
```

`fp1505` produces **no** `EXTR-1223` message at all.

### The short is real, and confirmed without the extractor

A tool refusing to run is not by itself proof of a design defect, and a VDD/VSS
short is a dead die — too serious to assert on one tool's word. Two further
readings were taken.

**The flow's own `check_connectivity` says nothing about it.** That is not a
contradiction and must not be read as one: `check_connectivity` asks whether a
net hangs together, net by net. It is never asked, and cannot answer, whether two
*different* nets touch. The two tools are silent about different questions.

**So the geometry was read directly.** `pgshort.tcl` pulls the special-route
rectangles out of the database within 3 µm of the reported coordinate and prints
them — no checker involved, no extraction, just what is drawn:

```
VDD M5 stripe   844.5  1546.60  -> 1088.1  1547.60
VSS M5 stripe   249.3  1545.62  ->  912.9  1546.62
```

Those two rectangles **overlap**: in y from 1546.60 to 1546.62, and in x from
844.5 to 912.9. A VDD stripe and a VSS stripe, on the same layer, sharing
**68.4 µm × 20 nm of metal.** It is a thin overlap, which is exactly why it is
easy to miss and exactly what a geometry-merge engine notices first.

(`verify_pg_short` and `verifyPGShort` do not exist as commands in this Innovus
build — the probe reports that it did not run rather than reporting no shorts,
which is the distinction that matters. The arithmetic above needed no checker.)

### Why this matters more than the abort

The abort is the lucky outcome. **Had the short been between two shapes the
extractor could merge without giving up, the run would have completed and
reported an IR drop for a design in which VDD and VSS are the same net** — which
is to say, a very small and very reassuring number. A separate session working
the shipping stream reports **four** VDD-to-VSS shorts on it; this stage found
one of them from a standing start, by trying to solve for a voltage.

That is the argument for measuring a voltage rather than counting vias, made
without anybody planning it: the stage's first contact with the shipping database
found a supply short that DRC-facing and connectivity-facing checks had not
surfaced.

**Handover:** the short is DRC/LVS territory and is not chased further here. What
this stage contributes is the coordinate, the layer, the two overlapping
rectangles and the overlap arithmetic. `fp1505` is clean of it, so a re-route
based on that floorplan is not carrying this defect.

---

## 6. The coverage limit, stated plainly

**The IR result covers 69.35% of chip power. 30.65% cannot be attributed to any
analysed rail, and no number in §1 says anything about it.**

That is measured, not estimated — it is `report_power`'s own per-rail table for
this database, in `ASIC/eth-chiplet/build/fp1505/reports/imp_power.rep`:

| rail | priced at | power | share of chip | in this analysis? |
|---|---|---|---|---|
| **VDD** | 1.08 V | **54.59 mW** | **69.35%** | **yes** |
| `Default` | 1.08 V | 16.33 mW | 20.74% | no — see below |
| (unallocated remainder) | — | 7.80 mW | 9.91% | no |
| chip total | | 78.72 mW | 100% | |

Cross-cut the same total by cell group and the missing part has a name: the **IO
group is 24.11 mW, 30.63% of chip power** — which matches the 24.13 mW this
stage measured *outside* the core box to two decimal places. Two independent
slicings of the same report agree that the unattributable third is the IO ring.

**Why it cannot be attributed, and why analysing it anyway would be worse than
not.** The CPF the flow actually reads —
`build/*/outputs/nanosoc_eth_chiplet_pads_gate1.cpf` — declares only
`create_power_nets -nets VDD` and `create_ground_nets -nets VSS`. VDDIO/VSSIO
exist in the design but in no power domain, so `report_power` cannot bill the IO
group to them and files it on an unnamed `Default` rail **at the core voltage**,
1.08 V, when the IO supply is nominally 2.5 V. Meanwhile the IO supply is
distributed by **abutment inside the pad cells**, so there is no top-level PDN
for the extractor to see.

Put those together: a rail run that *included* VDDIO/VSSIO would find nets with
no routing and no attributed demand, and would return **~0 mV**. It would look
excellent. **That is a false green by construction, and it is the single most
likely way for someone to produce a reassuring power-delivery number for this die
that means nothing.** So the two nets are excluded **by name**, the exclusion and
its reason are written into every run's census, and the gate never reports a
verdict for them. An unexplained absence would eventually be read as a pass.

The prerequisite for ever closing this is not a tool or a licence. It is the
power intent: VDDIO/VSSIO have to be declared before there is anything to
analyse. That is now `io-rail-ir-drop` in `ci/signoff.yaml`, with a refutation
that tests the generated CPF.

### The other limits on what 1.389% means

Stated on the same page as the number, because none of them is visible in it:

- **static only**, at an **assumed switching activity** — no SAIF or VCD exists
  anywhere in this flow;
- **die-only** — no package model, so no bond-wire or package drop;
- **to the cell's PG pin**, not to its transistors — a `techonly` grid library;
- **EM not analysed** — the J/Jmax field is empty;
- and it is one corner: ss / 125 °C / 1.08 V.

---

## 7. What this does not cover

Stated as limits, not as work not yet done. Three of these are now declared in
`ci/signoff.yaml` as coverage gaps with refutations that cannot succeed today —
`dynamic-ir-drop`, `io-rail-ir-drop`, `em-current-density` — replacing the
single `power-signoff` entry, which this stage closed.

- **Dynamic droop: unreachable here, not unrun.** A cell-accurate power grid
  library needs cell SPICE netlists or cell GDS, and this site has LEF abstracts
  and `.lib` timing only — the same root cause that black-boxes full-chip LVS.
  Only `techonly` can be built. Static at an assumed activity is the strongest
  claim this site supports, and it should be handed to the recipient as a
  limitation alongside LVS and metal fill.
- **No switching activity anywhere in this flow.** No SAIF, no VCD. Every
  current here descends from `report_power`'s default activity assumption. The
  relative map is dominated by the grid and is sound; the absolute millivolts
  inherit the assumption entirely, and must never be quoted without it on the
  same line.
- **Die-only.** No package model, so bond-wire and package drop are excluded.
  Add them before comparing against any system-level budget.
- **Cell internals are not modelled.** The drop reported is to each cell's PG
  pin, not to its transistors.
- **EM is not analysed** by this stage. `pg_capacity` computes a DC-average
  capacity margin from the tech LEF instead, which assumes perfect current
  sharing across every via on a plane; the ten-pad current spread measured here
  is the first check on how good that assumption is.
- **VDDIO/VSSIO carry no verdict**, by name, and the exclusion is recorded in
  the census so that an absence can never be read as a pass. See §6.

---

## 7b. The redaction, and its acceptance test

Six files in `rail/` each carried the same line —

```tcl
set QRC /<the site's PDK mount>/CMOS/LP/pdk/Assura/online/1p9m_6X1Z1U/qrcTechFile
```

— and one (`pgcap.tcl`) also wrote out an Arm release identifier and this
checkout's absolute path. That is a site constant copied six times into a
public repository, and the repo's own vendor gate says exactly why it must not
be: *"THE PDK MOUNT IS INHERITED, NOT NAMED HERE … a default spelled here would
be a second copy of a site constant, and the kind of copy this very script
exists to find."*

All of it now resolves in one place, `rail_env.tcl`, from `TSMC_65_HOME` and
`PHYS_IP` — which `ASIC/common.mk` exports and which are the only places in this
repository that name a mount. The Arm release code is resolved **by glob**, and
`::rail::glob_one` **refuses, naming the candidates, unless exactly one matches**:
writing the code in reproduces a vendor identifier, and globbing and silently
taking the first of two would be worse than either.

**The acceptance test is not that a gate went green.** It is that the spelling
changed and the *selection* did not — every resolved value byte-compared against
the literal it replaced:

| value | resolves to | identical to the old literal? |
|---|---|---|
| extraction deck (`QRC`) | `$TSMC_65_HOME/CMOS/LP/pdk/Assura/online/1p9m_6X1Z1U/qrcTechFile` | **yes** |
| the legacy scripts' database | archived route-baseline, via `$::RAIL(repo)` | **yes** |
| repository root | derived from the script's own location | **yes** |
| Arm `cln65lp arm_tech` | `$PHYS_IP/arm/tsmc/cln65lp/arm_tech/*`, 1 candidate | **yes** |
| toolkit root | `$::RAIL(repo)/ASIC/asic-toolkit` | **yes** |

The database default matters as much as the vendor paths: the diagnostic scripts
(`reff`, `padgeom`, `pgcap`, `recon`) still measure exactly what they measured
before, through `::rail::db_or_default`, so redacting their paths did not quietly
re-point them at a different design. `RAIL_DB` overrides it. The **stage**
(`rail_run.tcl`) calls `::rail::require_db` and has no default at all.

The vendor-collateral gate passes on the staged content, and a pre-commit hook
separately rejected the first attempt for two things worth recording: five
fixture `.iv` files over the 256 kB threshold (cut to 600 rows, re-proved), and
one absolute site path still sitting in `31-power-delivery-measured.md`.

---

## 8. Traps, for whoever runs this next

Every one produces a result that looks fine.

1. **`-short_pin_nodes` defaults to FALSE.** Without it, `set_power_pads -format
   padcell` reports 100% and attaches nothing. A `techonly` PGV gives a pad cell
   no internal nodes at all; its only nodes are the interface nodes where its PG
   pin meets the grid, and the default asks for a source on a node such a model
   never builds.
2. **`report_rail` needs the domain name LAST, and rejects the documented
   `ALL`.** Both wrong forms print `**ERROR` and return success.
3. **A threshold is mandatory** before `report_rail` will run (VOLTUS-1246 — and
   it returns success while refusing). It is a **reporting filter**: it sets the
   pass/fail column and the plot range and changes no computed millivolt. The
   pass/fail decision is the gate's.
4. **A PGV library is a DIRECTORY.** `file size` on it returns 4096 whether or
   not anything was built. Count what is inside it.
5. **`-log <name>` becomes `<name>/innovus.log` if `<name>` is a directory**, and
   a stale `<name>.log` from the previous failed run is then read as this run's
   verdict.
6. **`get_db … .core_bbox` and `get_db <shape> .rect` return LISTS OF
   RECTANGLES.** A guard of `llength != 4` is true for a *correct* answer. That
   exact bug silently skipped `pg_capacity`'s lateral scan on every run it ever
   made.
7. **The `.iv` report escapes bus brackets and `get_db insts .name` does not.**
   Joining them raw drops 17% of this design — all of it bussed registers — and
   the only symptom is a smaller row count.
8. **Trailing `# [TAG]` comments in a makefile keep the whitespace before the
   `#`.** `RAIL_RUN_TAG ?= fp1505    # [PROJECT]` sets the value to `fp1505`
   plus five spaces, and every path built from it acquires a space in the
   middle. It printed correctly in a status line and did not exist on disk.
9. **`< /dev/null` is not optional.** An uncaught Tcl error leaves Innovus at an
   interactive prompt holding an Innovus *and* a Voltus licence indefinitely.
10. **The `voltus` binary cannot read this database** (`IMPESI-3490`, CMMMC).
    The identical rail commands resolve inside the Innovus Stylus shell. All
    rail work here runs under Innovus and checks out Voltus features on demand.
