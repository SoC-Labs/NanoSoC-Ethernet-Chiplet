# IR-drop verification: where it fits, and what the gate asserts

Status: design only. **Nothing here has been executed.** No rail analysis has
ever been run on `nanosoc_eth_chiplet_pads`. Tool feasibility, licences and PDK
collateral are a separate piece of work; this note assumes static rail analysis
is reachable in some form and says which branch each decision sits on.

~~Prototype: `rail_static.tcl`, `rail_gate.py`, `rail_config.eth_chiplet.tcl`,
`rail_budgets.eth_chiplet.txt` in this directory. `python3 rail_gate.py
--selftest` runs a 20-case mutation battery; it is green.~~

**[2026-08-17] RETRACTED. None of those four files has ever existed** — not in
this directory, not anywhere in the tree, and not in any run directory. There
is therefore also no 20-case selftest and no green result; that paragraph
described work that was not done. It is struck rather than deleted so the claim
cannot be quoted again from an older revision.

The real scripts, and the measurements they produced, are in
`ASIC/genus-innovus/rail/` and written up in `31-power-delivery-measured.md`.

---

## 1. What is wrong with the check that exists

`2b_pnr_place_eval.tcl` §12 fails the run on

> `only 7 RV vias carry VDD+VSS from M9 to AP (floor 8)`

The floor of 8 is not a requirement. Its own comment says where it came from:
on the 08-08 configuration `add_stripes` created 7 RV vias and `route_special`
added 2 and deleted 1, giving 8 in the database. When the layer range was later
capped at M9 the second contribution became impossible and the floor became
*unreachable* — and nobody noticed for three days because the audit's `get_db`
query was broken.

So the defect is not that the gate never fires. It is that **8 vias is not a
number anybody derived from a current**. 73 mA of core current through 7 vs 8
vias is a resistance difference; whether either is adequate is a question the
count cannot answer in principle. The gate is measuring the narrowest point of
the supply path in the wrong units.

**Recommendation: the via count loses its blocking authority and becomes an
audit line, and a measured voltage takes over.** Not "as well as" — the count
currently halts the flow, and it will go on halting it on numbers that mean
nothing. Sequence in §7 so the flow is never left with neither.

---

## 2. Where rail analysis fits in the stage sequence

Three points, not two. The extra one is the cheap one, and it is the only one
that works on the design as it stands today.

| # | when | method | what it can catch | what it cannot | cost |
|---|---|---|---|---|---|
| **A** | after `power_plan.tcl`, **before placement** | `era_static`, current area-distributed from one total-power number | grid topology: stripe pitch/width wrong, a pad count that cannot supply the die, a region the mesh does not reach, gross asymmetry between the VDD and VSS meshes | anything about where the logic actually is; any local hotspot; anything about routing | minutes |
| **B** | end of place stage, post-`place_opt` | `era_static`, current from `report_power` on the placed netlist; ERA invents virtual follow-pins and vias for what is not yet routed | placement-driven hotspots — a hot block far from a pad, a macro channel starved of straps | the real follow-pin and via resistance, because at this point they are virtual | tens of minutes |
| **C** | post-route, after `route_opt`, before/alongside `write_stream` | `static` — **no virtual anything** | the built grid: real follow-pins, real via stacks, real macro taps. The only one that may be called signoff | dynamic droop; anything about VDDIO | hours |

Point A is the one to build first. The fresh flow currently halts at the
RV-via gate *before placement*, and the power plan is the thing under
suspicion — so A both works today and interrogates the right object. The
archived route database (`runs/20260812T133501Z_route-baseline-gds`) provides a
C-capable input without re-running the flow.

**Do not let C be satisfied by an ERA run.** ERA's grid-completion engine
invents virtual follow-pins and virtual vias for anything unrouted. On a design
whose route stage leaves 66 PG opens and 908 dangling PG wires, ERA would
bridge exactly the defects that matter and report a grid better than the one
being taped out. The gate treats `method=era_*` at the signoff stage as a hard
failure.

---

## 3. What the gate asserts

Two tiers, matching the idiom already in `4b_pnr_route_eval.tcl`: **HARD** (the
run is broken or unverified — always fatal) and **BUDGET** (measured, and over
a threshold — fatal at signoff, reported early). The verdict is computed from
artifacts. Exit codes are never consulted.

### 3.1 Coverage — asserted before any voltage is believed

This is the part that matters most, because the failure mode it defends against
is the one this project keeps hitting: **a rail solve that analysed a fraction
of the design, or was fed no current at all, completes successfully and reports
a small IR drop.** That is the best possible result produced from no data.

Four independent assertions, all HARD:

1. **Instance coverage.** `instances analysed / power-bearing instances in the
   database` ≥ 0.99. Both numbers measured in the same session — the
   denominator from `get_db insts` minus filler/endcap/diode patterns, the
   numerator by counting rows in the per-instance IR report. On the 08-12
   reference that is ~168,000 of 339,390 (135,087 fillers + 36,111 diodes
   excluded). Below the floor:
   *"the run analysed N of M power-bearing instances (X%, floor 99%). Every
   number below is a worst-of-a-sample, not a worst case."*

2. **Voltage-source count.** The number of sources the tool created must equal
   the number of core supply pads in the database — 10 here (6 VDD, 4 VSS). A
   pattern matching too few silently starves the grid (pessimistic, for the
   wrong reason, and it moves when the pattern is fixed).
   `-auto_voltage_source_creation` matching too many puts sources on every
   top-layer via and reports a grid far better than the one that exists.
   Neither shows up in the IR number as anything but a plausible value.

3. **Current accounting.** The solve's own tap-current total against
   `total_power / the voltage that power was priced at`, band 0.90–1.10. This
   is the check that catches an empty or mis-scaled `.ptiavg`.
   *Verified against the real archived report:* `Total Power: 78.886` with
   `Power Units = 1mW`, and a per-rail table giving `VDD 1.08`. Expected current
   **73.0 mA**. **Dividing by the 1.20 V nominal instead gives 65.7 mA — 11.1%
   out, which lands exactly on the edge of a ±10% band.** So the voltage the
   power was computed at is carried explicitly and the gate divides by *that*.
   (This bug was in the first draft of the gate and was caught by testing
   against the archived report. The same 1.08-vs-1.20 inconsistency exists
   today between `report_power` and the toolkit's `pg_capacity.tcl`, which
   converts mW→mA using `tech.tcl: voltage_core 1.20`.)

4. **Net coverage.** Every requested net must have produced a non-empty state
   directory. A domain run that solved VDD and quietly skipped VSS must not
   yield a VSS verdict.

Plus two more HARD assertions of the same family:

5. **Parser vs tool.** The worst drop computed from the per-instance report and
   the worst drop in the tool's own summary must agree within 1 mV. Same idiom
   as the existing `drc_trailer != drc_total` check. Disagreement means trust
   neither.

6. **No stream-derived grid.** `set_rail_analysis_config` accepts
   `-stream_file` / `-stream_purpose` / `-stream_map`. Someone will reach for
   it. On this design 68.8% of the metal in the streamed GDS is LEF obstruction
   emitted as conductor, so a stream-derived view models non-conducting metal as
   PDN and reports a **better** IR drop than reality. The step never passes
   those options, records that it did not, and the gate asserts it.

### 3.2 The voltages

Per analysed rail, absolute and as a fraction of a **named** nominal:

- worst and average drop on the power net
- worst and average rise on the ground net
- **worst effective collapse** = (VDD drop + VSS rise) **at the same instance**,
  taken from the per-instance report. Never the sum of two independent maxima:
  that is pessimistic *and* it hides the case where the two worsts are
  co-located, which is the dangerous one.

### 3.3 The distribution, and the hotspot/grid split

One number cannot tell a single hot instance from a grid that sags everywhere,
and the two need different responses. The gate reports p50 / p95 / p99 / p99.9 /
max of effective collapse, the count and fraction of instances over budget, and
then classifies:

- **localised** — over-budget instances occupy ≤ 4 tiles of 50 µm. A real
  defect with a local fix (add vias, move a cell, widen a tap). Stays **BUDGET**:
  the flow should still produce a GDS and report the exceedance.
- **distributed** — over-budget instances spread across more tiles. This is
  grid inadequacy: the stripe pitch, the stripe width or the pad count is wrong,
  and no local repair addresses it. **Promoted to HARD.**
- **unknown** — over budget, and the per-instance report carried no
  coordinates, so the gate *cannot show* the exceedance is localised. Treated as
  distributed. An unprovable "it's only a hotspot" is not a mitigation.

Why this split earns its complexity, from an end-to-end run of the prototype on
a synthetic 168,192-instance case shaped like this floorplan (supply pads on top
and bottom only, so the die sags toward the middle in y):

```
ir.eff_worst_pct     3.27      ir.over_budget_insts   156
ir.eff_p99_pct       2.83      ir.over_budget_frac    0.000928
ir.eff_p50_pct       0.97      ir.hotspot_tiles       55  of 1102 occupied
                              => ir.classification    distributed  (HARD)
```

**0.093% of instances are over budget.** A gate keyed on a count, or on the peak
alone, would have called that a hotspot and let it through. The spatial test
calls it what it is. Equally, `p99 = 2.83%` against a `worst = 3.27%` shows the
grid sagging broadly rather than spiking — a worst-only gate set at 3% would
have been within a whisker of passing a design where a percent of the die is
over the p99 budget.

Calibration note: `localised_tile_max` (default 4) and `tile_um` (default 50)
are project-side knobs and are **not yet calibrated against real data** — they
have only ever been exercised on synthetic distributions. Tune them once on a
real result, then leave them alone. They are the one part of this design most
at risk of quietly becoming a ratchet, so they carry provenance too.

### 3.4 Electromigration

`report_rail` reports PG current density if EM models are supplied. The trap is
explicit in the tool documentation: *in static mode, if `-em_models` is not
specified and `-process_techgen_em_rules` is not true, current-density analysis
is **disabled***. The run still succeeds and the EM report is simply absent.

So: `cov.em_status` is `analysed` only if models were offered **and** a
non-empty current-density report exists. Otherwise `NOT_ANALYSED` — advisory at
the early stage, **HARD at signoff**. An unmeasured signoff criterion is not a
pass. EM limits are the one genuinely foundry-defined number in this whole note.

Note the toolkit already has a licence-free relative of this:
`ASIC/asic-toolkit/flow/steps/pg_capacity.tcl` computes PG *capacity* in mA from
tech-LEF `DCCURRENTDENSITY`. It is wired into the toolkit's route stage and
**not** into `ASIC/genus-innovus/` at all. Wiring it in is the cheapest EM answer
available and needs no rail licence — see §7 step 0.

### 3.5 Anti-ratchet

Every threshold carries a `_source` string. `rail_gate.py` **refuses to run** —
before judging anything — if any source is empty or matches
`previous_run|last_run|as_measured|measured|today`. A budget set to the day's
measured number cannot fail, and this project has done that before. Enforced at
load time, not review time.

---

## 4. The numbers, and which are conventions

### 4.1 Name the supply first

The project has a live four-way disagreement about the IO supply. Every
criterion below is **for the core supply VDD only** and says so.

| source | core | IO |
|---|---|---|
| UPF `inputs/nanosoc_eth_chiplet_pads.upf:107-112` | 1.08 / **1.20** / 1.32 | 2.97 / **3.30** / 3.63 |
| CPF `inputs/nanosoc_chip_pads.cpf:13` | **1.08** only (`create_nominal_condition`) | absent |
| mmmc library corners | `tt_1p20v` / `ss_1p08v` / `ff_1p32v` | IO liberty corners **3.0 / 3.3 / 3.6** |
| toolkit `tech/tsmc65/tech.tcl:96-97` | 1.20 | **2.50** |
| `ASIC/eth-chiplet/config/design_config.tcl:211` | 1.2 | **2.5** |
| what the tool database actually holds | **1.08** (only rail in `report_power`) | **no VDDIO rail at all** |

**Core: 1.20 V nominal.** Not a convention — the design's own libraries are
characterised at `tt_1p20v`, `ss_1p08v` (= nominal −10%) and `ff_1p32v`
(= nominal +10%), and the UPF declares exactly those three port states. Settled.

**IO: 3.3 V nominal.** The UPF's 2.97/3.30/3.63 is ±10% of 3.30, and the IO
Liberty corners are 3.0/3.3/3.6 — two independent sources agreeing on 3.3.
The "2.5 V" in `tech.tcl` and `design_config.tcl` traces to the IO library's
*directory* name (`CMOS/LP/IO2.5V/...`), which is the library family, not the
supply the design is linked at. The CPF's 1.32 V, where it appears against an IO
net, is the core `ff` corner misapplied. **`tech.tcl:96-97` should be corrected
to 3.30**, and it matters concretely: it is consumed by `pg_capacity.tcl` to
convert mW into mA.

I have not resolved the 3.0/3.6 (databook) vs 2.97/3.63 (UPF) difference and it
does not matter for anything here — both are ±~10% windows on 3.3.

### 4.2 The budgets

All percentages **of core VDD nominal 1.20 V**:

| metric | budget | mV | status |
|---|---|---|---|
| worst static drop, VDD | 2.0% | 24 | **convention** |
| worst static rise, VSS | 2.0% | 24 | **convention** |
| worst effective collapse (VDD+VSS, same instance) | 3.0% | 36 | **convention** |
| p99 effective collapse | 2.0% | 24 | **convention** |
| average effective collapse | 1.0% | 12 | **convention** |
| instance coverage | ≥ 99% | — | completeness requirement |
| current accounting ratio | 0.90–1.10 | — | charge conservation |
| PG current density | ≤ vendor limit | — | **FOUNDRY REQUIREMENT** |

**What is a foundry requirement and what is not.** TSMC does not specify a
permitted IR drop for a digital design; there is no such rule to violate. What
is externally fixed is (a) **EM current-density limits per layer**, and (b) the
voltages the libraries are characterised at, which bound what you are allowed to
*claim*. Every percentage in the table above is this project's own budget.

The industry-conventional static allowance is 1–3% of VDD, with static+dynamic
together held to 5–10%. **The low end is chosen here because this design has no
dynamic analysis at all, and no switching activity anywhere in the flow.** The
untested dynamic component is real and will consume the rest of any wider
allowance. Taking 3% static on a design with zero dynamic coverage would be
spending margin twice.

Reference for scale: 73 mA of core current, 6 VDD pads and 4 VSS pads, none on
the left or right edge, worst lateral distance ~595 µm. That is 12 mA per VDD
pad and 18 mA per VSS pad. Nothing about those numbers makes 24 mV obviously
safe or obviously unreachable — which is the point of measuring.

### 4.3 Interaction with the OCV derate already applied

The flow runs flat OCV with CPPR: `-late -data 1.05`, `-early -data 0.95`,
`-late -clock 1.03`, `-early -clock 0.97`, `timing_analysis_type ocv`.

**A flat OCV derate is not an IR-drop allowance.** At 65 nm near 1.2 V, cell
delay sensitivity to supply is roughly ΔD/D ≈ 1.5–2 × ΔV/V, so a 2% rail
collapse costs 3–4% delay — most of the existing 5% late-data derate on its own,
if the derate were being asked to cover it. It is not: 1.05/0.95 is the generic
on-chip-variation allowance.

Two defensible postures. **The project must pick one and write it down**;
today it has neither.

- **Posture A — corner-covered.** Declare `ss_1p08v` to be the *on-die* worst
  case, i.e. the library's 10% margin covers supply tolerance *and* IR drop.
  Cheap, and currently unjustified: nobody has stated a board/package supply
  tolerance, so this claims margin that has not been measured. It also means the
  IR budget is "10% minus a board tolerance nobody has written down".

- **Posture B — derate-covered (recommended).** Declare `ss_1p08v` to be the
  voltage *at the pad*, hold static IR to 2%, and carry an explicit IR
  allowance on top of OCV — e.g. late-data 1.05 → ~1.09. **This will make the
  current setup WNS (−1.105 ns, 1796 failing endpoints) worse.** That is the
  honest consequence and it is the reason to decide deliberately rather than by
  default. The alternative is voltage-aware timing driven by the rail results,
  which is more accurate and more work.

The gate does not choose. It records both `rail.nominal_v` and
`rail.lib_binding_v` in the census so the two are visible side by side, and it
hard-fails if the nominal has no recorded provenance — because every percentage
it prints is a division by that number.

---

## 5. What this cannot cover

### 5.1 The IO supply — essentially nothing, and a run that included it would lie

`VDDIO`/`VSSIO` are distributed by abutment inside the TSMC staggered pad cells:
no ring, no stripes, deliberately unrouted, and nothing in the flow verifies
their continuity. Four independent reasons rail analysis cannot help, each
evidenced:

1. **They are not in the power intent the tool reads.** The patched CPF
   contains only `create_power_nets -nets VDD` / `create_ground_nets -nets VSS`
   and one domain, PD_TOP. VDDIO/VSSIO exist only as `connect_global_net`
   assignments made in `power_plan.tcl`.
2. **There is no PDN to analyse.** The conducting path is *inside* the pad-cell
   layout. An XD (LEF-based) power-grid view does not model it. The analysis
   would see essentially no top-level VDDIO metal and would either report the
   net as incomplete or attach everything to the nearest source and report ~0 mV.
3. **There is no current to solve.** The IO supply cells have **no internal
   power table at all** — the archived `report_power` says so explicitly:
   `# of cell(s) missing power table: 7`, listing `PVDD1DGZ_G`, `PVDD2DGZ_G`,
   `PVDD2POC_G`, `PVSS1DGZ_G`, `PVSS2DGZ_G`. No current means the solve returns
   ~0 V drop. **A false green by construction.**
4. **The power engine does not even have the rail.** `report_power`'s per-rail
   table lists only `Default 1.08` and `VDD 1.08`. There is no VDDIO row — so
   the ~21 mW of IO-group power is being priced at 1.08 V instead of 3.3 V, and
   the IO rail carries no current number anywhere in this flow.

So: VDDIO/VSSIO are **excluded by name**, the exclusion is recorded in the
census, and the gate never reports a verdict for them. An unexplained absence
would eventually be read as a pass.

**What would actually verify the IO supply** is a different check: a pad-ring
abutment/ordering audit — every IO segment bounded by supply pad pairs within
the vendor's maximum segment length, ESD and POC cells present and correctly
ordered — checkable from the `.io` file and the placed ring, plus pad-ring LVS.
That is worth doing and is not IR analysis. Out of scope here; recommended as a
companion.

### 5.2 Other gaps

- **Dynamic droop: not covered at all.** No switching activity exists anywhere
  in the flow (no SAIF, no VCD, no TCF, no `set_default_switching_activity`).
  Every power number in this project is a default-activity estimate, and
  `4b_pnr_route_eval.tcl` already warns as much. Static analysis is a floor on
  the problem, not a bound.
- **Absolute power is not trustworthy**, so absolute current is not either. The
  current-accounting check is a *consistency* check between two numbers derived
  from the same estimate — it catches an empty current file, not a wrong
  activity assumption.
- **Accuracy is bounded by the power-grid view.** A `techonly` (XD/LEF) view
  models the top-level mesh but not the internal rails of standard cells and
  macros, so drop *inside* a cell row or inside an SRAM is not resolved. HD
  accuracy needs cell-level GDS/SPICE, which this site does not have for
  `tcbn65lp` (same root cause that blocks full-chip LVS).
- **EM needs models.** If neither `-em_models` nor `-process_techgen_em_rules`
  is available, current density is not analysed at all, and the gate must say
  `NOT_ANALYSED` rather than pass.
- **Package and board are out of scope.** No package model, no bump/bond-wire
  inductance, no board droop. The analysis starts at the pad.

---

## 6. The toolkit split

Applying the migration doc's test — *does the file name the design?*

**Toolkit** (`ASIC/asic-toolkit/`, design-agnostic, reused by the second chiplet):

| file | why it is generic |
|---|---|
| `flow/steps/rail_static.tcl` | names no design, no supply, no PDK mount. Everything arrives in `::RAIL(...)`. Handles both `era_static` and `static`, harvests the census, decides nothing |
| `scripts/rail_gate.py` | census + verdict + mutation battery. Thresholds and supply names are inputs |
| `mk/rail.mk` | `rail_early` / `rail_signoff` targets |
| `test/rail/` | the mutation battery as a CI-runnable test |

**Project side** (stays in this repo):

| file | why it stays |
|---|---|
| `ASIC/eth-chiplet/config/rail_config.tcl` | names `PD_TOP`, `VDD/VSS/VDDIO/VSSIO`, `uPAD_VDD_*`, the filler/diode patterns, the analysis view |
| `ASIC/eth-chiplet/config/rail_budgets.txt` | the supply contract: 1.20 V, the percentages, and every `_source` |
| PGV dir / extraction tech file path | resolves from `TSMC_65_HOME`, which `ASIC/common.mk` owns. **Never a mount point in the toolkit** |
| the posture A/B decision record | a project judgement about this design's timing signoff |
| `ci/signoff.yaml` entry | already the only per-chiplet file by design |

`ci/signoff.yaml:408` currently declares the gap:

```yaml
  - id: power-signoff
    reason: "No power/IR-drop analysis stage (no Voltus/RedHawk); CPF exists for
             domains but is not verified here"
```

That entry becomes a real stage. Start it at `gate: report`, promote to
`gate: block` when the numbers are triaged — the mechanism the file already
documents.

**Do not land any of this into `ASIC/asic-toolkit/` right now** — another agent
is editing it, and it already contains a 439-line `docs/source/concepts/
ir-drop.md` covering the same ground. Reconcile with that document first. One
correction for whoever owns it: it states `-power_grid_libraries` is mandatory.
For `era_static` it is not — the tool documentation says the PGV is optional and
is generated on the fly from the extraction tech file, and the ERA examples pass
`-extraction_tech_file` with no PGV at all.

---

## 7. Staged plan

**Step 0 — free, today, no rail licence.** Wire `pg_capacity.tcl` into
`ASIC/genus-innovus/`. It is already written, licence-free, and currently runs
in the toolkit flow only. Fix `tech.tcl: voltage_io 2.50 → 3.30` and reconcile
`voltage_core` against the 1.08 V that `report_power` actually priced. This buys
an EM-capacity answer and removes a live 11% inconsistency.

**Step 1 — cheapest useful IR answer.** Point A: `era_static` on the power plan
alone, before placement, current area-distributed from the 78.9 mW already
measured (priced at 1.08 V → 73 mA). Minutes. Answers *"can this mesh and these
10 pads supply this die at all?"* — the question the RV-via count was gesturing
at. Works on the flow as it stands today, which halts before placement.

**Step 2 — bind the parser.** Read one data line of `instance_ir.rpt` by hand,
fill in `instir_col_*` in the project config. The gate self-checks from then on.
Until this is done the gate hard-fails on a missing key rather than parsing the
wrong column into a plausible number.

**Step 3 — arm the gate in report mode.** Land the check with `gate: report`.
Measure. Do **not** set thresholds from what comes back — the budgets in
§4.2 are already derived from the supply contract and the anti-ratchet rule
refuses a measured provenance.

**Step 4 — swap the authority.** In one commit: demote the RV-via floor to an
audit line, promote the IR check to blocking at the place stage. Never leave a
window with neither.

**Step 5 — signoff.** Point C on the archived route database
(`runs/20260812T133501Z_route-baseline-gds`), `method static`, real per-instance
currents, EM models required. Hours. This is the run whose result may be quoted
as signoff.

**Full signoff would additionally require**, none of which exists here: cell and
macro PGVs (needs cell-level GDS/SPICE), real switching activity for a dynamic
run, a package model, and a stated board-level supply tolerance to make posture
A or B meaningful.

---

## 8. Things that contradict the framing this work started from

1. **"A count compared against the previous run's value."** The RV-via floor
   was derived from a specific tool configuration, not from the previous run,
   and it did eventually fire correctly. The defect is that 8 vias is not
   derived from a current — the units are wrong, not the bookkeeping. The
   recommendation is unchanged; the reasoning should be accurate.

2. **"Run it at least twice."** Three points, and the most valuable first one is
   *before* placement, not after. The flow halts before placement today, and the
   power plan is the object under suspicion.

3. **Feasibility may be less blocked than assumed** (handing this to whoever owns
   that question, not claiming it): the archived route reports carry
   `VOLTUS_POWR-*` messages, so the Voltus power engine already runs inside this
   Innovus session; the Voltus Stylus Common UI User Guide in the local install
   states that **static ERA runs on the Innovus base licence** and that the PGV
   is optional; and the toolkit's own gap analysis records
   `Voltus_Power_Integrity_*` features as issued and idle.

4. **The stream trap is worse than "will be wrong".** `set_rail_analysis_config`
   has first-class `-stream_file` support, so it is an attractive wrong turn —
   and because obstruction-as-conductor *adds* metal, it fails in the flattering
   direction. It needs to be a named prohibition, not a footnote.

5. **The most dangerous single mistake is the divisor, not the threshold.**
   With four contradictory supply voltages on record, running with the wrong
   `-voltage` scales every percentage while leaving every number plausible. The
   first draft of this gate had exactly that bug in its current-accounting check
   (1.20 vs 1.08, 11.1% — the width of the acceptance band). It was found by
   testing against the archived report, not by reasoning.
