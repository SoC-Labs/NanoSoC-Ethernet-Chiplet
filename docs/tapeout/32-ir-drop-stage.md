# The IR-drop stage: what it measures, what it refuses, and what it cannot see

Date: 2026-08-17. Status: **wired into the flow and running.**

This is the stage description and the operator's page. The measurement record —
every number, every trap, and the history of how the pads question was settled —
is `31-power-delivery-measured.md`, and the paper design that preceded both is
`30-ir-drop-gate-design.md`.

---

## 0. What changed

Before 2026-08-17 this pipeline had **never computed a voltage.** The two things
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

**max / p50 = 1.12.** This grid has essentially no tail: no hotspot stands out
above the population. Zero instances exceed the 3% worst-collapse budget, so
the hotspot-versus-grid classifier has nothing to classify.

> **[2026-08-18] CORRECTION.** This paragraph previously continued *"it sags
> almost uniformly, and every instance on the die sits within 15% of every
> other."* **That is false, and it is the wrong lesson to draw from max/p50.**
> The field spans **0.638% to 1.389% — a factor of 2.18** — and p50/min is
> 1.94. What is compressed is not the field, it is the *population*: 62% of the
> instances sit in the middle third of the die, which is the worst-supplied
> third, so the count distribution piles up against its own maximum. Read
> §1b before quoting "flat" as a property of this grid; the distinction decides
> which of the three options in §1c is the right one.

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

**Read the column correctly**: it is the *spread* of node deviations on that
layer, not a per-path increment. On VSS the report prints the range explicitly
and the arithmetic is visible — M9 `0.00399 → 0.00847`, M8 `0.00392 → 0.00848`,
M7–M3 `0 → 0.00849`, M2/M1 `→ 0.00889`. The zeros on M7–M1 are the pad cells'
own PG-pin ports, which sit at the source. Two things fall out: **M8 and M9 have
the same range**, so the top plane is well stitched to itself; and **no layer
below M7 develops more than 0.40 mV of new drop** (0.22 mV on VDD). That
0.6 mV, out of 15.00 mV, is the entire budget available to any repair in the
mesh, the M4→M5 vias or the cell taps. It is the number §1c(c) turns on.

---

## 1b. The shape of this grid, measured — because one budget turns on it

Recomputed from the run's own `VDD_VSS_div.iv` (350,388 rows) joined to
`inst_xy.txt`. Everything here is arithmetic on artefacts already on disk; no
re-solve was needed and none was run.

### It is not a uniform sag. It is a clean vertical gradient.

Mean effective collapse by 160 µm band in Y (core is y 205–1795; all ten core
supply pads are on the **top and bottom** edges):

| y band | instances | mean | min | max |
|---|---|---|---|---|
| 160–320 (at the bottom pads) | 18,809 | **0.798%** | 0.645% | 1.008% |
| 320–480 | 26,555 | 0.960% | 0.803% | 1.080% |
| 480–640 | 36,506 | 1.124% | 0.983% | 1.194% |
| 640–800 | 54,732 | 1.233% | 1.131% | 1.312% |
| 800–960 | 66,498 | 1.308% | 1.242% | 1.388% |
| **960–1120 (mid-height)** | 42,013 | **1.320%** | 1.256% | **1.389%** |
| 1120–1280 | 55,700 | 1.264% | 1.170% | 1.341% |
| 1280–1440 | 24,783 | 1.175% | 1.053% | 1.239% |
| 1440–1600 | 9,527 | 1.013% | 0.897% | 1.102% |
| 1600–1760 | 12,793 | 0.850% | 0.697% | 0.982% |
| 1760–1920 (at the top pads) | 2,472 | **0.728%** | 0.638% | 0.783% |

In X the same table is nearly flat — 1.098% to 1.261% across eight bands — which
is the four-sided core ring doing its job, exactly as `31-power-delivery-measured.md`
§4b-bis predicted from the ring geometry and measured on effective resistance.

**So the die has a textbook two-edge-fed profile: best at the pad rows, worst at
mid-height, symmetric, monotone.** The M8 stripes are vertical on a 60 µm pitch
and the M9 stripes horizontal on the same pitch; the current's long journey is
the vertical one, away from the top and bottom rings, and that is where the
gradient is.

### Why the *distribution* nevertheless looks flat

The three Y bands from 640 to 1280 hold **219,000 of 350,000 instances (62%)**
and are the three worst-supplied bands. The population is concentrated where the
supply is weakest, so a histogram of per-instance drop piles up against its own
maximum and reports max/p50 = 1.12. **The flatness is a property of the
placement, not of the grid.**

### The decomposition that decides what can be fixed

| term | value | share of the 12.741 mV mean |
|---|---|---|
| **floor** — the minimum over every instance on the die | **6.890 mV** | **54.1%** |
| vertical traverse — between-band swing, best band to worst | 8.11 mV | the whole gradient |
| local spread — within the worst Y band, min to max | 1.44 mV | ≤ 12% |

No instance anywhere escapes 6.890 mV, so **54% of the mean is set before the
current reaches the mesh at all** — in the pads, the rings and the top of the
stripe network. Of the 5.851 mV that does vary, the between-band swing is
8.11 mV and the within-band spread is ~1.5 mV, so roughly **six sevenths of the
variation is the vertical traverse and one seventh is everything local** — mesh,
taps, macro shadows and all.

To bring the mean to 1.0% requires removing **1.941 mV, which is 33% of the
entire varying part of the mean.**

### Two objections tested and dismissed

The mean is a per-instance count mean over a population that is 43% filler, so
two obvious complaints have to be answered before it is quoted:

| statistic | value | verdict |
|---|---|---|
| mean over all 350,388 instances | 1.1797% | the gate's number |
| mean over the 200,917 **functional** cells only (FILL/ANTENNA excluded) | **1.1911%** | worse, not better |
| **current-weighted** mean (weighted by each instance's own demand) | **1.1858%** | worse, not better |

Neither correction rescues the number. **The exceedance is not an artefact of
counting fill cells, and it is not an artefact of ignoring where the current
is.** Whatever else is wrong with the mean criterion, the measurement behind it
is sound.

---

## 1c. The mean budget: the calibration question, worked

`budget.eff_mean_pct` is the only budget this design fails, and it is the one
budget in `rail_budgets.txt` whose number is not derived from anything. This
section is the evidence for the chip owner's decision. **No threshold has been
changed, and none should be changed on the strength of this run.**

### (1) Is 1.0% defensible on its own terms? No — and its own source string shows why.

Its provenance reads:

> `convention: the typical instance's share of the budget. If the MEAN reaches
> the peak budget the grid is inadequate everywhere and no local repair helps.`

That is an argument for **having** a mean criterion. It is not a derivation of
**1.0**. The sentence's own logic sets the alarm at the *peak* budget — 3.0% —
and the threshold written is a third of that. Nothing in the file connects the
two. Compare its siblings:

| threshold | does the source derive the number? |
|---|---|
| `eff_collapse_pct_max` 3.0% | **yes** — names an external convention (1–3% static; 5–10% static+dynamic) *and* argues for the choice within it |
| `eff_collapse_p99_pct_max` 2.0% | no — argues that a population statistic is needed, not that it is 2.0 |
| `eff_collapse_mean_pct_max` 1.0% | **no** |
| `vdd_droop_pct_max` / `vss_rise_pct_max` 2.0% | **no, and inconsistently** — the source says *"half the combined allowance to each net"*; half of 3.0% is 1.5%, not 2.0% |

The only visible pattern across 3.0 / 2.0 / 1.0 is a 3:2:1 ladder. **A ladder is
a distribution-shape assumption, not an allowance.**

**What is externally fixed, and what the mean does not derive from.** The file's
own header states it: TSMC specifies no permitted IR drop for a digital design.
What is fixed is (a) EM current-density limits per layer — which this run does
not measure at all (`em.current_density` = NOT_ANALYSED) — and (b) the voltages
the libraries are characterised at. **The mean budget derives from neither.** It
is a convention, correctly labelled as one, with an underived number.

**The one externally anchored derivation actually available here** comes from
(b), and it is worth putting on the record because it is the only frame in this
project that is not somebody's convention:

- The process nominal is **1.20 V** (tech pack, UPF `ON_TYP`).
- The signoff libraries are characterised at **1.08 V** — 1.20 V minus 10% —
  and that is the divisor every percentage on this page uses.
- The 120 mV between them is the supply-collapse allowance the library set
  itself already grants: regulator tolerance, package and board drop, static IR
  and dynamic IR, together.
- Against that band, **worst 15.00 mV = 12.5%** of it and **mean 12.74 mV =
  10.6%** of it.

That framing is a defensible source string. Whether one tenth of the
characterisation band is the right share for on-die static collapse is a
judgement — but it is a judgement about an externally fixed 120 mV, not about a
ratio invented to sit under 3.0%.

### (2) Is the measurement sound? Yes. Is the criterion independent of the dynamic gap? No.

The measurement stands: 99.86% instance coverage, current accounting 0.9975,
demand-vs-flow agreement 0.0011%, parser-vs-tool 0.32 mV, and both corrections
in §1b make the number worse rather than better.

**The criterion is a different matter.** The 3.0% peak budget explicitly spends
its provenance on the missing dynamic coverage: the static-only convention is
1–3%, static+dynamic is 5–10%, and 3.0% was chosen so that the unmeasured
dynamic component keeps the rest. **The mean budget makes no such argument, and
does not need to — it is not an independent allowance.** At 3.0/3 it is the peak
budget with a shape assumption applied, so it inherits that dynamic reservation
already made, once, upstream. It does not double-count a margin. What it does
instead is impose an unstated 3:1 peak-to-mean model, and this die's
population-weighted ratio is 1.18:1.

There is a second, sharper reason to distrust a *mean* criterion specifically on
this flow. §1b shows the mean is 54% floor — the shared pad-and-ring term — and
that term scales linearly with **total die current**. Every ampere here comes
from `report_power`'s default activity assumption; there is no SAIF and no VCD
anywhere in this flow. **The mean is therefore the statistic most exposed to the
one input that has never been validated**, and the peak and p99 are only
marginally better off. That is an argument about which criterion to gate on, and
it is independent of the shape argument.

### (3) What would actually reduce the mean?

Measured first, guesses labelled.

| candidate | effect on the mean | confidence |
|---|---|---|
| **43,091 vias deleted by the `stacked_via_bottom_layer M5` ordering bug** | **≈ 0** | **measured** |
| **921 missing power vias M1→M9, 889 of them M4→M5** | **≈ 0** | **measured** |
| **M5 per-region anchoring** (owned by another session) | **≈ 0**, on IR-drop grounds | **measured** |
| denser M8/M9 stripes (60 µm pitch today) | plausibly **−2 to −3 mV** | **estimate** |
| more core supply pads, VSS first (4 against VDD's 6) | plausibly **−1 to −1.5 mV** | **estimate** |
| repairing the 330 PG opens | **≈ 0** on the mean | measured (they carry no current today) |

**Why the first three are ruled out, and it is not a guess.** All three live at
or below M5. The layer report says no layer below M7 develops more than 0.40 mV
of new drop on VSS and 0.22 mV on VDD — **0.6 mV of the 15.00 mV total, against
the 1.94 mV that has to come off the mean.** Shorting the entire mesh, every via
and every tap to zero ohms would not reach a third of the requirement. §1b's
independent decomposition agrees from the other direction: within-band spread,
which is where all local effects show up, is ~1.5 mV against a between-band
swing of 8.11 mV.

This says nothing about whether those defects matter. **43,091 missing vias is
an EM and current-crowding question, and EM is NOT_ANALYSED on this run.** The
claim here is narrow and it is the one that was asked for: *they do not move this
distribution's mean.*

**What does have reach is the vertical traverse.** The gradient in §1b is the
current's journey along the M8 vertical stripes away from the top and bottom
rings. Halving the effective resistance of that network — the obvious lever is
the 60 µm stripe pitch — would roughly halve the 5.851 mV varying part of the
mean, which is about 2.9 mV and more than the 1.94 mV required. **That number is
an estimate from a linear-network argument, not a measurement**; nothing in this
project has solved a modified grid, and the honest way to get it is to re-run
this stage on a re-routed database, which is a P&R run and was not taken.

**The floor is the other half and it is harder.** 6.890 mV that no instance
escapes, incurred in the pads and rings. VSS is the worse net by construction —
four pads against VDD's six, and it carries 12.6 mA per pad against VDD's
8.4 mA, giving mean rise 7.53 mV against VDD's 5.21 mV. Equalising the pad
counts is the direct attack and it is a floorplan and IO-ring change.

### (c) The three options

| | option | cost | what would prove it |
|---|---|---|---|
| **(a)** | **Re-derive the mean budget from the characterisation band.** Replace the underived 1.0% with a share of the 120 mV between the 1.20 V process nominal and the 1.08 V signoff characterisation, and say which share and why. Fix the `vdd`/`vss` source strings at the same time — they say "half the combined allowance" over a number that is two thirds of it. | An afternoon of writing and one review. No tool, no licence, no re-route. | The source string must name the 1.20/1.08 pair and the share, and survive the anti-ratchet unchanged. The gate re-run must then be the *only* thing that changed — verdict still FAIL_HARD on `pg.disconnected`, which is the real blocker. |
| **(b)** | **Accept the grid on the record.** Keep 1.0% exactly as written, record the 1.180% exceedance as a documented deviation with §1b as its justification, and gate on p99 (1.357% of 2.0%) as the population statement. | Free, and honest, provided the exceedance is written where a reader meets it — not retired quietly. | Nothing to prove; it is a decision. But it must be re-taken whenever the activity assumption changes, because §1c(2) shows the mean is the statistic most exposed to it. |
| **(c)** | **Change the grid: halve the M8/M9 stripe pitch.** The only candidate with the reach to move a 1.94 mV mean. | A P&R re-route plus a re-run of this stage (~25 min). M8/M9 routing overflow is near zero so the metal is likely available, but the M8 stripe DRC history in `power_plan.tcl` says assume nothing. | Re-run `make rail RAIL_RUN_TAG=<new>` on the re-routed database and compare the §1b decomposition, not just the headline. The prediction to falsify is specific: **the floor (6.890 mV) should barely move and the between-band swing (8.11 mV) should roughly halve.** If the floor moves instead, the model in §1b is wrong and the estimate with it. |

**None of these is urgent, because the mean is not what is blocking this
database.** `pg.disconnected` is: 330 instances with no path to a supply, 55 of
them functional, at coordinates that have not moved in five days. The verdict
would be FAIL_HARD with the mean budget deleted entirely.

---

### The verdict: **FAIL_HARD**

Two criteria are not met, and neither is the headline voltage.

1. **`pg.disconnected` — HARD. 330 instances have no path to a supply rail.**
   Not a margin: those cells do not power up. Detailed in §2b below.
2. **`budget.eff_mean_pct` — BUDGET. Mean collapse 1.180% against a 1.0%
   budget.** Every other budget passes with room: worst 1.389% of 3.0%, p99
   1.357% of 2.0%, VDD droop 0.585% of 2.0%, VSS rise 0.823% of 2.0%.

**On that second one, read the shape before reading the number — and read §1b
before believing the shape.** The mean budget was written at 1.0% against a
3.0% peak, which presumes a distribution with a tail; this design's
population-weighted mean is 85% of its maximum, so a 3:1 peak-to-mean model does
not fit it. **The threshold has deliberately NOT been changed.** Editing a
budget after seeing the number it judges is the exact ratchet
`rail_budgets.txt` refuses, and the refusal is worth more than the green tick.
**§1c works the calibration question in full** — where 1.0% came from (nowhere),
whether it double-counts the missing dynamic coverage (no; it is the peak budget
with a shape assumption on top), what could actually move it (nothing below M5,
measured), and three named options with their costs. It is the chip owner's
decision, and the mean is not what is blocking this database.

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

### (a) The mutation battery — 26 cases, `make -C ASIC/genus-innovus rail-selftest`

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
[ok] over_p99_only               expect FAIL_BUDGET  got FAIL_BUDGET  p99 AND mean
[ok] flat_grid_mean_over_budget  expect FAIL_BUDGET  got FAIL_BUDGET  via budget.eff_mean_pct
[ok] flat_grid_within_budget     expect PASS         got PASS
[ok] demand_vs_flow_agrees       expect PASS         got PASS
[ok] demand_vs_flow_disagrees    expect FAIL_HARD    got FAIL_HARD    via coverage.demand_vs_flow_power
[ok] vss_worse_than_vdd          expect FAIL_BUDGET  got FAIL_BUDGET
[ok] anti_ratchet                expect GATE_ERROR   got GATE_ERROR
[ok] missing_provenance          expect GATE_ERROR   got GATE_ERROR
26 passed, 0 failed
```

(The real output also annotates every line with `via
coverage.demand_vs_flow_power,em.current_density`, because on a fixture with no
`reports/` beside its database those two degrade to ADVISORY. Four of the cases
above exist precisely because that degradation was hiding something — see the
subsection below.)

**Four cases added 2026-08-18, and the reason is a hole this battery could not
see.** Until then every fixture was built by the same linear ramp from
`0.33 × worst` up to `worst`, which fixes mean/max at 0.665 and p99/mean at
1.494 **for every case in the battery**. The real fp1505 result has mean/max
0.849 and p99/mean 1.151. The consequence was exact and serious: **no fixture
could fail the MEAN budget while passing p99** — which is the real design's
situation, and the only criterion currently blocking it. Demonstrated rather
than argued, by mutating the gate and re-running the OLD battery:

| mutation | old battery (22 cases) | now (26 cases) |
|---|---|---|
| `ir.eff_collapse_mean_pct_max` relaxed 1.0% → 9.0% | **22 passed, 0 failed** | 24 passed, **2 failed** |
| `eff_mean_pct` metric hard-wired to 0 | **22 passed, 0 failed** | 24 passed, **2 failed** |
| `coverage.demand_vs_flow_power` tolerance 1% → 1000% | **22 passed, 0 failed** | 25 passed, **1 failed** |
| `parse_rail_table` made to return nothing | **22 passed, 0 failed** | 25 passed, **1 failed** |
| the new fixtures' shape knob reverted to the old ramp | — | 25 passed, **1 failed** |

The last two are a second, independent hole: **every** fixture pointed `db.path`
at a directory with no `reports/` two levels up, so `find_flow_power_report`
returned `None` and `coverage.demand_vs_flow_power` — documented in §3 as HARD,
and the only genuinely independent check on the demand file — degraded to
ADVISORY on every case. Its HARD arm had never been exercised in either
direction. `demand_vs_flow_agrees` / `demand_vs_flow_disagrees` now build a fake
run tree with a rail table **cut from the real `imp_power.rep`**, per the
fixtures' own rule.

Two mechanical changes made those cases possible, and both are worth having on
their own: `make_fixture` gained a `floor_frac` knob (default 0.33, so every
existing case is byte-identical) so the *distribution shape* is expressible; and
each case may now name the checks it must trip and must not trip, because a
status-only comparison lets a case pass for the wrong reason. It already had:
`over_p99_only` is named for p99 and in fact breaks the mean as well.

Two of those cases carry more weight than the rest. **`baseline_healthy` is the
positive control**: without it, a gate that rejects everything would score 25/26
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
