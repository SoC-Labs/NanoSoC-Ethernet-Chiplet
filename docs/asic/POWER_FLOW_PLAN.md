# Activity-annotated power as a permanent part of the ASIC flow

Status: PROPOSAL. Nothing here is landed. Written 2026-08-27 against the working
prototype at `ASIC/eth-chiplet/build/power-saif-20260827/`, which is real,
reproducible, and is the thing this document proposes to productise.

Every number in this document was measured. Where a number is a projection it is
labelled PROJECTION and the thing that would replace it with a measurement is
named. Where I am uncertain I say so.

---

## 0. Summary of recommendations

| # | Question | Recommendation |
|---|---|---|
| 1 | Where in the flow | A post-stage make target at ROUTE-STAGE EXIT, not a Tcl hook. `ROUTE_POST_TARGETS`, same seam as `ASIC/evidence.mk`. |
| 2 | Opt-in or always-on | **Capture always-on** (measured marginal cost ~6 min on a 4-hour route). **Publish opt-in**, inheriting `EVIDENCE_PUBLISH`. A deliberate half-departure from the evidence.mk precedent, argued in §3. |
| 3 | Window policy | A window is a pair of **named bench events** resolved from the run's own event log, plus a settle offset. Never a literal time. Four interlocks make a reset-window structurally impossible, and the strongest one is free. |
| 4 | The coverage gap | **Extend the gate bench for RMII (cheap, ~2 min/run). Do NOT map an RTL SAIF. Do NOT put a D2D-active vector on this flow's critical path** — it is a peer/firmware problem, not a bench edit. Bound the residue instead and declare it. |
| 5 | Rail/IR handoff | Feasible with **zero additional simulation** — byte-identical database, proven. But it is **not a one-line edit and not in the file the task named**: four coupled changes in `rail_run.tcl` and `rail_gate.py`, one of which fixes a live defect. Use the **W3 rated-clock arm, not W2** — reasoning in §6.2. |
| 6 | Gate | **Two rows.** `power-activity` (block) asserts that a real activity file was used and what it covered — never a budget, because this project has no budget with a defensible source. `power-delta` (report) asserts the number did not move. |
| 7 | Publish/size | Publish gzipped, cited artefacts only: **7.7 MiB per run**, not 497 MB. The binding constraint is not file size — it is that the destination repository is exempt from retention and grows forever. |

---

## 1. The evidence base

All measured on the shipping candidate `gdsrun-20260826-rc1`, on its own routed
database, with the shipped gate bench unmodified and zero bench forces.

### 1.1 The headline and its control

| arm | total mW | internal | switching | leakage | annotation coverage |
|---|---|---|---|---|---|
| `A_default` (tool default toggles) | 80.65738667 | 54.74304043 | 25.53960018 | 0.37474606 | none |
| `W2_ethimemcopy` (200 us) | 8.34211789 | 5.95609264 | 2.02449080 | 0.36153445 | 209738/209738 |
| `W3_dualcore_full` (1090 us) | 7.69174581 | 5.52555920 | 1.80466377 | 0.36152285 | 209738/209738 |
| `W3_dualcore_full_x2rate` (rated clock) | 15.02196878 | 11.05111839 | 3.60932754 | 0.36152285 | 209738/209738 |

**The control holds to the last digit.** `A_default` reproduces the candidate's
own `reports/imp_power.rep` exactly on all four figures — verified again while
writing this document. The two arms therefore differ in the activity and in
nothing else. That control is the single most load-bearing fact in this plan and
the gate in §7 makes it mandatory rather than incidental.

**Annotation is total.** 209738/209738 = 100%, on every SAIF arm. Not one net
fell back to a default toggle rate.

### 1.2 The rail split, which is what §6 turns on

Rail analysis excludes VDDIO/VSSIO **by name** (`io-rail-ir-drop` in
`ci/signoff.yaml`), so the only quantity it solves is the VDD rail row:

| arm | Default rail (IO pads) mW | VDD rail mW | VDD as % | VDD demand at 1.08 V |
|---|---|---|---|---|
| `A_default` | 17.83 | **54.26** | 67.27% | **50.24 mA** |
| `W2_ethimemcopy` | 1.244 | 6.61 | 79.23% | 6.12 mA |
| `W3_dualcore_full` | 0.3527 | 7.225 | 93.94% | 6.69 mA |
| `W3_dualcore_full_x2rate` | 0.7007 | **14.09** | 93.82% | **13.05 mA** |

The chain reconciles end to end: 54.26 / 1.08 = 50.24 mA, and the rc1 rail
census records `demand_current_ma=50.2419`. The default-activity IO bucket
(26.397 mW in the block breakdown) equals the census's
`coverage.power_unattributed_mw=26.3988`. Nothing here is inferred.

### 1.3 What the vector does not exercise

Measured inside the SAIF itself, over the 1090 us primary window:

| port | direction | toggle count | why |
|---|---|---|---|
| `CLK` | input | 109000 | 50 MHz, running |
| `RMII_MDC` | output | 1090 | 500 kHz, CPU0 doing MDIO |
| `QSPI_SCLK` | output | 0 in W3, 9190 in W2 | flash boot over by W3 |
| `RMII_REF_CLK` | **input** | 0 | **bench ties it low** |
| `TL_CLK_RX` | **input** | 0 | **bench ties it low** |
| `TL_CLK_TX` | **output** | 0 | **the design never brings the link up** |
| `SWDCK` | input | 0 | bench ties it low |

**Correction to the prototype's own summary.** `TL_CLK_TX` is a top-level
**output** and does not appear in the bench spec at all — it is not tied, and no
bench edit can light it. It reads zero because the D2D transmitter never runs.
That distinction is the whole cost argument in §5.

### 1.4 Cost, measured

| step | wall | note |
|---|---|---|
| strip + PG-complete + census + bench gen | 19 s | |
| VCS compile + elaborate + link | 80 s | 64.4 + 9.6 + 0.8 s CPU |
| **build total** | **99 s** | |
| simulate, no SAIF | 53 s | the existing gate's cost |
| simulate, 200 us window | 97–142 s | |
| simulate, 1090 us window | 152 s | |
| Innovus power, 6 arms, one database load | ~9 min | |
| Innovus power, 2 arms | ~3 min | estimated from the above |

The five-window exploratory campaign — build plus six simulations — took 13 min
21 s wall. **The premise that this is expensive does not survive measurement**,
and §3 takes that seriously rather than restating the premise.

---

## 2. Where in the flow

### 2.1 The seams, at their current line numbers

Measured against the pinned toolkit at `ASIC/asic-toolkit`, `flow/innovus/4_route.tcl`,
2788 lines:

| line | event |
|---|---|
| 881 | `flow_hook pre_route` |
| 1483 | `imp_power.rep {report_power}` — the 80.657 mW number is born here |
| 1485 | `warn "report_power has no switching activity (no SAIF anywhere in this flow)"` |
| 1749 | `pnr_write_db routed` — **the database every power and rail stage reads** |
| 1877 | `write_stream` |
| 1956 | `write_netlist -include_pg` — **the netlist GLS simulates** |
| 2031 | `flow_hook post_route` |
| 2679 | `route_gate.txt` written — the stage's verdict |

Three places in the repo quote stale numbers for these: `design.mk` says the
post_route hook is 554 lines before the verdict, `mk/flow.mk` says the hook is at
1903, and `hooks/post_route.tcl` says 1735 with `write_stream` at 1637. The
current figures are hook 2031, verdict 2679, gap 648 lines. Worth correcting
when those files are next touched; it changes no conclusion.

### 2.2 Why not before route

A SAIF needs a netlist, so post-synth is the earliest arithmetic possibility.
It is also structurally wrong, and the measurement says by how much:

- **The clock network is 37.58% of the measured power** (2.891 mW of 7.692), of
  which 2.863 mW is the single domain `clk`. **That network does not exist
  before CTS.** A post-synth SAIF would annotate a design missing 38% of its
  own power and the missing part is the part most sensitive to activity.
- Switching power is 23.5% of the total and is parasitic-dominated. Before
  route there are no parasitics.
- Post-CTS is arithmetically defensible and I reject it anyway: route
  optimisation renames and restructures, so a post-CTS SAIF's names drift
  against the database that ships, and the value — an early warning — does not
  justify a second GLS build and a second Innovus session on every run.

**Post-route is not a preference. It is the first seam at which the answer is not
structurally wrong.**

### 2.3 Why not a Tcl hook

Both inputs exist by line 2031, so `post_route` is the earliest Tcl seam that
could work. It should still not be used:

1. **The work is not Innovus work.** SAIF capture is a VCS compile plus a
   simulation. A Tcl hook that shells out to VCS holds the route's Innovus seat
   for the entire simulation — 99 s of build plus 53–152 s per window — for no
   benefit, on a site where seats are contended and another agent is routinely
   mid-P&R.
2. **The power report needs its own session anyway.** The prototype's Tcl does
   `read_db`, `set_pg_nets`, `set_db power_method static`, then six arms. That
   is a clean-slate database read with its own supply declarations, not a
   continuation of the route session's state.
3. **The verdict does not exist yet.** A SAIF from a route that HARD-FAILED its
   gate is a power number for a netlist that will not ship. `ASIC/evidence.mk`'s
   header already argues this at length for publishing and the argument
   transfers without modification.

### 2.4 Recommendation

**A post-stage make target, hooked exactly where `evidence` is hooked.**

```make
# ASIC/eth-chiplet/design.mk
ROUTE_POST_TARGETS = power evidence run-report-auto
```

`mk/flow.mk`'s `post_stage_targets` calls the stage after `4_route.tcl` has
exited, `route_gate.txt` has been written and parsed, and the manifest exists.
It is non-fatal to the build and fatal to the claim, which is the right failure
mode for a four-hour route.

**ORDERING IS A REAL HAZARD HERE, not a style point.** `post_stage_targets`
passes all the targets as goals to *one* recursive make. Goals are ordered only
in serial make. `power` must complete before `evidence`, because `evidence`
collects gates and bundles the artefacts they cite (RULE 5), and a power gate
whose report is not yet on disk renders NOT-MEASURED. So the ordering must be
expressed as a **prerequisite** — `evidence: power` in `design.mk` — or as a
single ordering target, and never relied on from the list order. This is the
same class as the `all:` target's own comment in `mk/flow.mk` about `-j`.

**No toolkit change is required and none is proposed.** In particular, adding a
SAIF to `4_route.tcl:1483` so that `imp_power.rep` is annotated in-flow would be
a pin roll, and it is the wrong design anyway: `imp_power.rep` is written before
the routed database exists at 1749, so it cannot be the same measurement.
`imp_power.rep` should stay what it is — a default-activity relative comparison,
which its own warning at 1485 already says — and the annotated number should be
a separate artefact that never overwrites it. That way the control in §1.1 stays
available forever.

---

## 3. Opt-in or always-on

### 3.1 The precedent and what it actually argues

`ASIC/evidence.mk`:

> Publishing is OPT-IN from the flow. A route that finishes at 03:00 should not
> push 300 MB to a store nobody has looked at yet; and a publish is a claim.

That is two arguments, not one: a **size** argument and a **claim** argument.
They separate here, and separating them is the whole of this section.

### 3.2 Capture: always-on

The size argument does not apply and the cost argument does not survive
measurement.

- Marginal cost of capture over the existing `gls-netlist` stage: the sim is
  already being built and run for the signoff gate. The extra is one compiled
  source (free), the SAIF-window re-runs (+45 s to +100 s each over the 53 s
  baseline), and a two-arm Innovus power run (~3 min). **Call it 6 minutes on a
  four-hour route: 2.5%.**
- For comparison, `evidence.mk` already accepts 7–10 minutes unconditionally,
  and `macro-pin-connected` alone is 6–9 minutes of that. **Power costs less
  than a gate this flow already runs on every route without asking.**
- The failure mode of not capturing is the one this project has been living in:
  a 10x-wrong number quoted for months because nothing ever produced the right
  one.

So: capture runs on every route. It is skippable with an explicit `POWER_SKIP=1`
and **a skip must leave a marker** — `POWER-NOT-MEASURED.txt`, mirroring
`NOT-PUBLISHED.txt` — that the signoff pipeline reads as NOT-MEASURED. A silent
absence is the one outcome that is forbidden.

### 3.3 Publish: opt-in, and for a different reason than evidence.mk's

Publishing stays behind `EVIDENCE_PUBLISH=1`, inheriting the existing mechanism
rather than adding a second switch.

But the reasoning is **not** the size reasoning, and this needs saying in the
plan so that nobody later "optimises" it back to always-on by pointing at the
file sizes. At the sizes in §8 (7.7 MiB gzipped), size is not the objection. Two
things are:

1. **A power number is a claim in the strongest sense available here.** The
   entire point of this work is that the project has been quoting 80.657 mW.
   Replacing that with 7.692 mW, published, is a claim about the die that people
   will act on — including, immediately, a pad-count decision. `evidence.mk`'s
   "a publish is a claim" applies more forcefully to power than to anything else
   it currently gates.
2. **The destination is exempt from retention.** `scripts/ci/artifactory_retention.py`
   holds `asic-record` in `PROTECTED` and absent from `POLICY`, so nothing can
   ever prune it. It holds 31.28 MB today. Publishing power on every route grows
   it by ~25% per route, forever. That is a real constraint and it is a stronger
   argument for opt-in than the byte count is.

**Uncertain:** whether the right long-run answer is to bring `asic-record` under
a retention policy rather than to keep publishing opt-in. I have not designed
that and it is out of scope here. Note that `artifactory_retention.py` **aborts
the entire run** if a repository appears in both `POLICY` and `PROTECTED`, so
this is not a one-line change either.

---

## 4. Window selection, as policy

### 4.1 The requirement

A production flow cannot hand-pick 5.300–6.390 ms off a timeline somebody read.
The window must be derived, must move when the firmware moves, and — the hard
part — **the flow must be incapable of silently producing a SAIF over reset.**

### 4.2 The mechanism that already exists

The generated bench emits a named, machine-readable timeline. From the run's own
simulation log:

```
GLSN-EVENT: 0 simulation start
GLSN-EVENT: 1270000 reset NRST released
GLSN-EVENT: 1490000 expect cc_rom_msp_on_Q satisfied
...
GLSN-EVENT: 5731830000 expect eth_sysctrl_remap_set satisfied
GLSN-EVENT: 6399990000 run complete
```

Those names come from the `expects` array in the bench spec — nine of them
today, each a signal/value (optionally clocked) predicate. So there is already a
reproducible vocabulary of named instants, it is declared in a tracked file, and
it moves with the firmware because the predicates are about what the firmware
does.

### 4.3 The policy

**A window is declared as a pair of named events plus offsets, and resolved to
picoseconds from the run's own event log at capture time. A literal time is never
written down.**

```json
{ "name":        "W3_dualcore",
  "from":        "eth_sysctrl_remap_set",
  "from_settle_ns": 50000,
  "to":          "$run_complete",
  "to_margin_ns":   10000,
  "why":         "both CPUs executing from IMEM; CPU0's REMAP store is the
                  last named event before steady state" }
```

Two tiers, because the second needs a firmware change and the first does not:

- **Tier 1, available now, no firmware change.** Anchor on the last named event
  plus a settle offset, close at `run_complete` minus a margin. For today's run
  that resolves to 5.782–6.390 ms — inside the dual-core steady state, fully
  reproducible, and it re-resolves automatically if the firmware timing changes.
  Note this is *not* today's hand-picked 5.300–6.390 ms; it is a slightly later,
  slightly shorter window, and the numbers will differ a little. That is correct
  behaviour, not a regression.

- **Tier 2, the target.** The firmware writes a magic word to a known address at
  the start and end of the region it wants measured; the bench declares two
  `expects` on those writes named `power_window_open` and `power_window_close`;
  the window is exactly those two events. This is the "named marker the firmware
  toggles" and it is the right long-run answer, because it puts the choice of
  what to measure in the hands of the person who wrote the workload. Cost: a few
  lines in stage-0 plus two entries in the bench spec.

The declared window set lives in a tracked file beside the bench spec, not in a
Makefile variable and not on a command line.

### 4.4 The four interlocks

All computed **from the produced SAIF**, never from the request. A SAIF that
fails any of them is not a weak result; it is not a result.

1. **Post-reset.** `window_start` must exceed the timestamp of
   `reset NRST released` (1270000 ps today) by a declared margin. The event log
   supplies the timestamp; nothing is hard-coded.

2. **The clock-count interlock — the strongest one, and free.** The primary
   clock's toggle count in the SAIF must equal `2 x duration_ns / period_ns`.
   Verified on all five windows the prototype produced:

   | window | duration | CLK toggles | expected | match |
   |---|---|---|---|---|
   | W1 | 200000 ns | 20000 | 20000 | yes |
   | W2 | 200000 ns | 20000 | 20000 | yes |
   | W3 | 1090000 ns | 109000 | 109000 | yes |
   | W4 | 200000 ns | 20000 | 20000 | yes |
   | probe | 20000 ns | 2000 | 2000 | yes |

   This catches a window over reset, a window the simulation never reached, a
   truncated dump, a clock-gated interval, and a `-scale_time` applied twice. It
   costs one pass over the activity file and needs no licence. The prototype's
   `saif_census.py` already parses exactly the fields required.

3. **Named witnesses toggled.** A declared set of witness signals must be
   non-zero: the primary clock, at least one core memory clock, and the CPU0 and
   CPU1 execution witnesses the bench's `expects` already name. This is
   deliberately a *named set*, not a "fraction of nets toggling" floor. A
   fraction floor would have to be calibrated against today's measurement
   (4.58% of nets for W3, 3.37% for W4), and `rail_budgets.txt`'s anti-ratchet
   rule is right that a threshold set to the day's number is a record wearing
   the costume of a requirement.

4. **The dump is what was asked for.** The SAIF's `DURATION` must equal the
   requested window; the file must exist, be non-empty, and be scoped to the
   DUT. `$toggle_report` is not a command whose return code means anything.

### 4.5 Two defects in the prototype's window handling to fix on the way

- **The SAIF filename is hard-coded** (`$toggle_report("activity.saif", ...)`),
  so window *N+1* overwrites window *N* in the run directory. The prototype
  worked around this by copying files out between runs. Productised, the
  filename must come from a plusarg alongside the window bounds.

- **`GLSN_EVIDENCE_FILES += strip_leaf_defs.txt activity_window.txt` names a
  file that does not exist.** The toolkit's publish loop is
  `[ -s "$f" ] && cp ... || :` — a named evidence file that is absent is
  **silently skipped**. So the prototype declares that it publishes a window
  record and publishes nothing, and no error is raised. That is precisely the
  absent-renders-as-clean failure, inside the thing being productised. The
  window record must actually be written, and its absence must be an error.

---

## 5. The coverage gap and the worst-case-vector question

### 5.1 What is actually dark, and what that costs

The number in §1.1 is a booted, running part with the network link and the D2D
link down. Five blocks are at their clock-pin and leakage floor. Comparing the
default-toggle price against the measured link-down price for exactly those
blocks brackets what a link-active vector could add:

| block | instances | default-toggle mW | measured W3 mW | ratio |
|---|---|---|---|---|
| eth MAC (ethmac core) | 17588 | 4.4214 | 0.7192 | 6.1x |
| TideLink: top + AHB/FIFO | 16492 | 6.5624 | 0.6634 | 9.9x |
| TideLink: chiplet controller | 17343 | 3.4434 | 0.8048 | 4.3x |
| TideLink: Wlink link layer | 35963 | 3.0878 | 0.3709 | 8.3x |
| TideLink: D2D PHY | 16244 | 1.5971 | 0.1324 | 12.1x |
| **five blocks** | **103630** | **19.112** | **2.691** | **7.1x** |

103,630 instances — 41.7% of the design — are priced 7.1x apart by the two
assumptions. A link-active vector lands somewhere between, and the honest
statement is that **the headline power number is not defensible as a worst case
until it is measured**.

### 5.2 The two halves cost completely different amounts

**RMII: cheap, and should be done.**
`RMII_REF_CLK` is a top-level **input** currently in the bench spec's `tie0`
list. Making it free-running is a spec edit: move the string out of `tie0` and
append `{"port": "RMII_REF_CLK", "period_ns": 20.0}` to `clocks`. Two constraints
from the generator, both real:

- It must be **moved, not duplicated** — the generator has no duplicate-port
  refusal and would emit both a `reg` and a `wire` for the same name, which is a
  compile error.
- It must be **appended, never prepended** — `clocks[0]` is load-bearing three
  times over (reference period, reset-release loop, force-delay loop), so a new
  clock in first position silently reinterprets `run_cycles` and the reset
  length.

Cost: one extra build (99 s) and one extra simulation (~2 min) per run, plus one
Innovus arm (~2 min). It lights the `mii_rx_clk` and `mii_tx_clk` trees, which
today contribute **leakage only** — and since clock networks are 37.6% of this
design's measured power, that is the single largest identifiable missing term.
`TL_CLK_RX` can be freed the same way and is worth doing in the same edit, but
see below for why it buys less.

**D2D: expensive, and should not be on this flow's critical path.**
`TL_CLK_TX` is an output. There is no tie to remove. It is dark because the link
never trains, and the link never trains because there is no peer answering on
`TL_RX`. Bringing it up needs a peer model and a bring-up sequence — and the
bench spec has **no stimulus primitive at all**: `forces` applies one static
value once after reset and cannot walk symbols, and the `devices` primitive was
built, measured and deliberately removed. So a D2D-active gate vector is a bound
peer model through `GLSN_COMPILE_ARGS`, i.e. the het-chiplet pairing problem,
which this project's own record says has never been run anywhere and where the
two dies do not share an address map. **Weeks, not hours.** Do not couple the
power flow to it.

Freeing `TL_CLK_RX` alone gives the receive clock trees but not the transmit
side and not the datapath, so it is a partial measure — worth taking because it
is free, not worth mistaking for D2D coverage.

### 5.3 An RTL SAIF is not worth it, and the reason is not marginal

Assessed honestly, because the option is superficially attractive: RTL benches
exist that drive RMII (twelve of them) and D2D (twenty), all of them VCS, so
`$toggle_start` and `$toggle_report` are available in every one.

It still does not work, for four reasons, in descending order of severity:

1. **No bench elaborates the chip top.** The nearest D2D bench is one level down
   (die level, no pads, no chip wrapper) *and instantiates two dies*, so even
   that scope is not 1:1. Every RMII-driving bench is two levels down. A SAIF can
   only be re-scoped **below** the matching instance.

2. **The clock network cannot be annotated at all.** Clock-tree cells are
   created by CTS and do not exist in RTL. That is 31.9% of the measured power
   (clock combinational 21.51% + clock sequential 10.42%) which would have to be
   inferred by propagation from the annotated clock root — which is exactly the
   default propagation this whole exercise exists to eliminate.

3. **The reachable coverage is a minority and the remainder falls back
   silently.** A `nanosoc_multicore_soc`-rooted SAIF could at best reach the chip
   core (30.33%) plus the eth subsystem (15.64%) = 45.97%, omitting the IO pads
   (6.07%) and every top-level cell (5.82%) outright — and only if the RTL
   instance names below that point survived synthesis, which for the TideLink
   blocks they demonstrably did not. Whatever misses reverts to default toggles
   and reintroduces the 10x error on that fraction, quietly.

4. **It is not needed**, because the cheap half of the coverage gap is fixable
   in the gate bench, where annotation is 100%.

**Recommendation: do not build an RTL-SAIF path.** If someone wants to test the
premise anyway, the cheapest decisive experiment is one `read_activity_file` at
the remapped scope and read the `Total Design annotation coverage:` line — the
same line `summarise.sh` already extracts. One Innovus session, ~3 minutes. I
expect it to come back well under 50% and I would want to be shown wrong before
any effort is spent.

### 5.4 Declare the residue so it cannot rot

Add an `unsupported:` entry `d2d-link-active-power` whose `refuted_by` tests for
a bench spec that actually drives `TL_CLK_RX`/`TL_RX`, so the gap self-retires
the day someone closes it.

**And amend `dynamic-ir-drop`.** Its `reason:` string currently ends:

> There is also no switching activity anywhere in this flow — no SAIF, no VCD —
> so even the static currents are a default-activity estimate

Landing this work makes that clause **false**, and its `refuted_by` tests only
the *other* clause (cell SPICE or cell GDS on the host), so nothing in the
pipeline would ever notice. That is the stale-waiver failure the `refuted_by`
mechanism was added to prevent, reproduced by a reason with two load-bearing
clauses and one falsifier. Split it into two entries, or rewrite the reason down
to the surviving clause.

---

## 6. The rail / IR handoff

### 6.1 The feasibility question is already settled

The power prototype and the rail stage read **the same database directory**:

| | power prototype | rc1 rail census |
|---|---|---|
| database | `ASIC/eth-chiplet/build/gdsrun-20260826-rc1/work/nanosoc_eth_chiplet_pads_routed` | same string |
| instances | 365998 | 365998 |
| top | `nanosoc_eth_chiplet_pads` | `nanosoc_eth_chiplet_pads` |

The SAIFs on disk today annotate that database at 100%. **The rail handoff needs
zero additional simulation.** It is a matter of reading a file the flow already
has.

### 6.2 Which arm — and this is a correction

The brief says to use W2 because it is the higher window. That is true of
**total chip power** (8.342 vs 7.692 mW). It is not true of the quantity rail
analysis solves.

Rail excludes VDDIO/VSSIO by name, so the demand is the **VDD rail row**, and
there W3 is higher: **7.225 mW against W2's 6.61**. W2 looks higher only because
QSPI is active in W2 and loads the IO pads, which the rail domain throws away.
At the rated clock the measured arm gives **VDD 14.09 mW = 13.05 mA**.

**Use `W3_dualcore_full_x2rate`.** The rated-clock instruction in the brief is
right and important — dynamic power does double at 100 MHz, and the x2 arm
returns exactly 2.000x internal and 2.000x switching with leakage unchanged,
which is the arithmetic that had to hold.

### 6.3 It is four coupled changes, not one line — and not in the file named

**`ASIC/genus-innovus/rail/rail_static.tcl` is dead code.** Nothing invokes it:
`make -C ASIC/genus-innovus rail` runs `rail_run.tcl`, and `rail_static.tcl` is
referenced only by its successor's header explaining that it was replaced. The
live `report_power -rail_analysis_format VS` call is `rail_run.tcl:179`.

I have not edited either file, as instructed. The proposed change is:

**(a) `rail_run.tcl` section 3 — read the activity file, and die rather than fall
back.** When `RAIL_SAIF` is set: the file must be readable, `read_activity_file
-reset -format saif -scope <scope>` must run, `report_unannotated_nets` must be
written, and coverage must be asserted against a floor. If any of that fails the
run must **abort**, never continue to a default-activity report. `read_activity_file`
prints `**ERROR` and returns success, so every assertion is on an artefact.

**(b) `rail_run.tcl:62` — the census key must stop being a literal.** Today:

```tcl
cen method.activity            assumed_tool_default_no_saif_no_vcd
```

It should be computed: `saif:<basename>:<sha256-12>:<coverage>` or the existing
string when no SAIF was given. Plus new keys the gate can grade:
`activity.saif_path`, `activity.saif_sha256`, `activity.window_ns`,
`activity.scope`, `activity.annotated_nets`, `activity.total_nets`,
`activity.scale_time`.

**(c) `rail_run.tcl:178-181` — the `instance.rpt` reuse clause. This is a live
defect and it is not hypothetical.** The code reuses an existing non-empty
`instance.rpt` rather than re-running `report_power`. On the shipping
candidate's own graded rail run it **fired**:

```
instance.rpt   written 11:25:38
census.txt     written 13:33:23
```

and the run log carries, with no `@file` prefix and therefore not a Tcl echo:

```
RAIL reusing existing .../gdsrun-20260826-rc1/instance.rpt (34081166 bytes)
```

So rc1's rail verdict was computed from a power report written two hours and
five minutes earlier by a different invocation. Today that is merely untidy.
**With a SAIF in play it becomes a false-claim generator**: annotate the
database, silently reuse the stale default-activity report, and the census
declares an annotated run while every millivolt is a default-toggle number. Fix
before anything else: write an activity fingerprint beside the report and reuse
only on an exact match.

**(d) `rail_gate.py` — the verdict currently cannot tell the two apart.**
`method.activity` is *recorded* (`M["activity"]`) and never graded, and the
verdict's `scope_note` is a **hard-coded string** asserting "STATIC rail analysis
at an ASSUMED switching activity (no SAIF, no VCD exists anywhere in this
flow)". After a SAIF run that sentence is a lie printed in the report. Two
changes: derive the note from the census, and add a HARD check
`activity.declared_and_consistent` that fails when `method.activity` claims a
SAIF but the coverage keys are absent or below floor. Add
`activity.annotation_coverage` to `rail_budgets.txt` with a completeness-style
source, alongside the existing `cov.*` family.

### 6.4 What the handoff is projected to do

PROJECTION, not a measurement. IR drop through a fixed resistive grid with
per-instance current sources is linear in current, so the scale factor is
13.05 / 50.24 = **0.2597**.

| metric | budget | measured (default activity) | projected (W3 rated clock) |
|---|---|---|---|
| `ir.eff_collapse_pct_max` | 3.0 | 1.3315 | ~0.346 |
| `ir.eff_collapse_p99_pct_max` | 2.0 | 1.3046 | ~0.339 |
| `ir.eff_collapse_mean_pct_max` | 1.0 | **1.1486 — OVER** | ~0.298 |
| `ir.vdd_droop_pct_max` | 2.0 | 0.5537 | ~0.144 |
| `ir.vss_rise_pct_max` | 2.0 | 0.7806 | ~0.203 |
| EM worst J/Jmax (VSS) | <1.0 | **1.432 — OVER** | ~0.372 |
| EM elements over limit | 0 | **49 — OVER** | expected 0 |
| VSS pad current, mean | — | 12.56 mA | ~3.26 mA |

**Do not ship this table as a result.** Run it. The whole argument of this
document is that a computed number is not a measured one.

### 6.5 The fifth VSS pad

The pending decision is whether the die needs a fifth VSS pad. Four VSS pads
against six VDD pads is why VSS carries 1.5x the per-pad current and why VSS
rise is 1.41x VDD droop.

**What the measurement will support:** at a real operating point the four VSS
pads carry ~3.3 mA each instead of 12.6, VSS rise is ~0.2% instead of 0.78%, and
the EM exceedance in the pad-feed stripes disappears.

**Is that conclusion robust to the coverage gap in §5?** Yes, and this is the
useful part. Take a deliberately pessimistic link-active vector — **double** the
measured rated-clock demand, 26.1 mA. Two independent derivations agree on
roughly that figure: simple doubling, and substituting the default-toggle price
for all five dark blocks into the measured total (giving 25.9 mA). At 26.1 mA:

- `eff_mean_pct` → 0.597, inside the 1.0 budget
- EM worst J/Jmax → 0.744, under the limit
- `eff_worst_pct` → 0.692, well inside 3.0

**So even a 2x-pessimistic link-active vector clears both currently-failing
checks, and the recommendation is that the die does not need a fifth VSS pad.**
The margin does not depend on closing the coverage gap.

**What must not be skipped:** it must be **measured**, not projected. One rail
run, ~7–10 minutes plus an Innovus and a Voltus seat.

**The two checks this would clear are the only two failing.** rc1's rail verdict
is `FAIL_HARD` on exactly two of its 29 checks, and both are in the table above:

```
em.current_density     ok=False   49 grid elements over the derated limit
                                  (budget 0), worst VSS J/Jmax 1.432
budget.eff_mean_pct    ok=False   mean effective collapse 1.1486% (budget 1.0%)
```

**And the EM number is properly derated, which I initially assumed it was not.**
The metric `em_temp_out_of_range_nets = VSS VDD` looks alarming, but the gate has
already diagnosed it: `em.derate_applied` is **true** — every current-carrying
layer was analysed with an explicit derate at 125 C (0.358 on the metals), and
the solver's out-of-range warning concerns only device layers that carry no EM
model and have no grid elements in this design. So it does not qualify any
reported number.

That is worth stating plainly because it changes the sequencing: **there is no
ICT prerequisite blocking this.** The 1.432 is a real, correctly-derated
current-density figure computed at a demand of 50.24 mA that the design does not
draw. Rescaling that demand to a measured operating point is the *only* thing
standing between it and a pass — which makes the rail handoff the direct route
to clearing both failures, not a contribution toward clearing them.

Recommended order: re-run rail with the W3 rated-clock SAIF; then decide the pad.

---

## 7. The gate

### 7.1 Two rows, and the discriminating one is not the number

**Row A — `power-activity`**, `gate: block`, `phase: physical`, `label: soclabs-pdk`.

It does **not** assert a budget. It asserts that a real activity file was used
and what it covered:

1. an activity file was read, named, with its sha256;
2. annotation coverage is 100%, or above a declared floor with the shortfall
   enumerated by name — **the anti-fallback assertion**;
3. the window passes all four interlocks in §4.4;
4. **the control arm ran and reproduced the run's own `imp_power.rep`** — this is
   what proves the pipeline measured the same design the flow reported on, and
   it is cheap because it is the same Innovus session;
5. **the dark-signal census is published**: every top-level clock port with zero
   toggles across the window, listed by name in the artefact. So the coverage gap
   of §5 travels with every quoted number and can never be silently omitted.

**Why no budget, stated so it is a decision and not an oversight.** This project
has no power budget with a defensible source. `rail_budgets.txt`'s anti-ratchet
rule refuses any threshold whose source matches `previous_run|last_run|
as_measured|measured|today|observed|baseline`, and `power.total_mw_max 8.0`
would have exactly that source. Setting it would be "a record of what happened,
wearing the costume of a requirement". **The condition for adding a budget is a
package or thermal limit, or a system power specification, from outside this
repository.** Until then the absence is correct and should be stated in the row.

**Row B — `power-delta`**, `gate: report`.

Asserts this build's annotated total against the previous build's, same window
name and same arm, flagging movement beyond a declared band. A delta *is*
defensible where an absolute is not: its source is "the previous measurement of
the same workload on the same design", which does not claim the number is
acceptable — only that it did not move. It catches what a budget would catch
anyway (a lost clock gate, a CTS blow-up). With no previous build it renders
NOT-MEASURED, never PASS.

### 7.2 How it cannot silently fall back

The evidence framework already enforces most of this, and the design should lean
on it rather than reinvent it. `evidence_report.py`'s `Gate` constructor:

```python
if self.verdict == PASS and not self.measured_over:
    raise ValueError("gate %s PASSES and does not say what it measured over. ...")
```

So a PASS is structurally required to name what it measured over — the SAIF
sha256, the window and the arm. A gate that fell back to default toggles has
nothing to put there.

The four states must render differently:

| state | verdict | why |
|---|---|---|
| stage did not run | NOT-MEASURED | with the skip marker as the reason |
| ran, no activity file | NOT-MEASURED | reason: "default toggles" — **never PASS** |
| ran, coverage below floor | FAIL | an annotated fraction is not an annotated design |
| ran, coverage 100%, window valid | PASS | `measured_over` names SAIF, window, arm |

The verdict vocabulary is exactly `PASS`, `FAIL`, `NOT-MEASURED`, `KNOWN-BAD`;
anything else raises. And `signed_off()` is `FAIL == 0 and NOT-MEASURED == 0`,
so adding this gate makes every run not-signed-off until it measures. That is
the intent.

### 7.3 `check_proof` fixtures — each one a way this project has already been misled

- no activity file, but a number reported
- coverage 89% with the shortfall not enumerated
- a SAIF whose window straddles reset
- a SAIF whose clock-toggle count disagrees with its own duration
- a stale `instance.rpt` reused across an activity change (§6.3c — this one
  actually happened)
- a control arm that does **not** reproduce `imp_power.rep`
- an empty dark-clock census because the parser matched nothing (the
  a-zero-that-measured-nothing shape)
- must_pass: the real prototype output

### 7.4 Wiring notes that will bite

- **Gates are hand-registered.** There is no gate table or plugin mechanism in
  `evidence_flow.py`; registration is a function plus a call block in
  `collect()`, plus a `SPEC_FIELDS` entry. **Unknown spec keys are fatal**, so
  the spec field must land before any spec names a power run. Follow the
  `clp_runs` precedent — `power_runs: {arm: dir}` — rather than a single dir.
- **The `_now_gated` collision.** Three of the four evidence specs currently
  declare `ir-drop` under `not_measured`. If the §6 handoff makes `ir-drop` real,
  those declarations must be removed or `load_spec` dies with an explicit
  message. `power-activity` is a new id and does not collide today.
- **RULE 5 does the size policy for free.** The report refuses to build citing a
  file the bundle does not carry, so "publish what a gate cites" is already the
  rule — see §8.

---

## 8. Publish and size policy

### 8.1 Measured compression

Measured with `gzip -9` on the real artefacts while writing this:

| artefact | raw | gzip -9 | ratio |
|---|---|---|---|
| `*_summary.rpt` | 11,891 | 2,053 | 5.8x |
| `*_hier.rpt` | 579,579 | 25,695 | 22.5x |
| `*_clock.rpt` | 924,074 | 39,449 | 23.4x |
| `*_insts.rpt` | 51,833,937 | 1,605,342 | **32.3x** |
| SAIF (1090 us window) | 34,113,327 | 933,934 | **36.5x** |

The `insts.rpt` is 99.5% of each arm's report volume, and it is also the most
compressible thing in the tree.

### 8.2 The policy

**One arm, everything gzipped: 3.87 MiB. Two arms — control plus workload:
7.73 MiB.** Against 497 MB of reports and 162 MB of SAIF raw.

- **Publish:** per arm, gzipped — summary, hier, clock, insts, and the SAIF.
- **Do not publish:** the exploratory probe arm (192 MB), the GLS build tree
  (369 MB), the `simv`, and any arm no gate row cites.
- **The rule is RULE 5, unchanged:** an artefact is published if and only if a
  gate row cites it. The 497 MB exists because the prototype ran six arms
  exploratively; a production run publishes two.

### 8.3 Three mechanism facts that constrain the implementation

1. **Nothing in the publish path compresses the bundle.** `zstd -19` is applied
   to the GDS stream only; the evidence bundle is walked and uploaded **raw,
   one file at a time**. So the power stage must write `*.rpt.gz` into its
   evidence directory. Compressing after the fact is not an option.

2. **Properties are matrix parameters at deploy time only.** `setprops` is
   Artifactory Pro and is dead on this instance, and the code says so. So
   `power.window`, `power.saif_sha256`, `power.arm`, `power.total_mw` and
   `power.annotation_coverage` must be in the props dict at PUT time or they can
   never be attached to those bytes. Note the matrix encoder replaces `;` and
   `|`, which none of these values contain.

3. **Each file is one PUT plus one properties GET.** Ten files per run is twenty
   extra round trips — negligible. The cost is not transfer, it is §3.3's
   retention point: today `asic-record` holds 31.28 MB in total, the largest
   single artefact ever pushed to it is 24.3 MB, and nothing can prune it.

Skipping or failing to publish must leave `POWER-NOT-PUBLISHED.txt`, mirroring
the existing marker.

---

## 9. Phased implementation

Effort is my estimate for one engineer already familiar with this tree.

### Phase 0 — freeze the prototype as a first-class item (0.5 day)

No behaviour change; make today's result reproducible from tracked files.

- Move `gls_saif_dump.sv` into a tracked location beside the existing flash
  attach module, and the Tcl/Python into a tracked `power/` directory.
- Add a fifth GLS item: a clone of the shipping-lineage item plus the SAIF
  module on `GLSN_COMPILE_ARGS`.
- Parameterise the SAIF output filename (§4.5).
- **Confirmed: no toolkit pin roll is needed.** `GLSN_SIM_ARGS_<item>` already
  delivers plusargs to an already-built `simv`, and the prototype's own
  `run.cmd` proves it drove five windows off one build. The only toolkit-side
  wrinkles are cosmetic (the run target does not publish, and the project
  already has a publish-only target for exactly that).
- **Coordination risk:** `ASIC/gls-netlist/Makefile` is tracked and other
  sessions have owned it recently. Either coordinate, or add the item through a
  separate included fragment — noting that a shared fragment can silently
  replace a project recipe if its target names collide.

Exit: `make -C ASIC/gls-netlist power RUN_TAG=... WINDOW=...` reproduces today's
numbers.

### Phase 1 — window policy and interlocks (1 day)

- `power_window.py`: resolve a named window from the run's event log, write the
  window record (fixing §4.5's silent-skip), and run the four interlocks against
  the produced SAIF.
- A selftest battery with fixtures: a SAIF over reset, a truncated SAIF, one
  whose clock count disagrees with its duration, one with a witness dark.
- No licence, no database, no PDK. Runs in seconds.

### Phase 2 — the rail handoff (1 day, plus one rail run)

- **Fix the `instance.rpt` reuse fingerprint first** (§6.3c). It is a live defect
  independent of everything else here.
- The other three coupled changes. Propose as a patch and get it reviewed — that
  tree is active.
- Re-run rail on rc1 with the W3 rated-clock SAIF. ~7–10 min, one Innovus and
  one Voltus seat.
- **Nothing blocks this.** The EM derate is already correctly applied (§6.5), so
  there is no ICT prerequisite. The two failing rail checks are both demand-
  driven and this phase is the direct route to both.

Exit: a measured rail result at a real operating point; `FAIL_HARD` resolved or
shown not to be; and the fifth-VSS-pad decision made on evidence.

### Phase 3 — the RMII-active arm (1–2 days)

- A second bench spec with `RMII_REF_CLK` free-running, observing both generator
  constraints in §5.2.
- Confirm the MAC clock trees light up; re-measure; compare.
- Then decide whether RMII *traffic* (a bound stimulus module) is warranted, on
  the evidence of whether the clock-only arm leaves the MAC still obviously
  under-exercised.

### Phase 4 — gate and evidence wiring (1 day)

- `gate_power_activity()`, the `SPEC_FIELDS` entry, the call block.
- The two `ci/signoff.yaml` rows with their fixtures.
- Remove the `ir-drop` `not_measured` declarations if Phase 2 landed (§7.4).
- Amend `dynamic-ir-drop`'s reason and add `d2d-link-active-power` (§5.4).

### Phase 5 — publish and size (0.5 day)

- gzip before bundling; extend the publish props; the not-published marker.

**Total ~5–6 days. Phases 0–2 (~2.5 days) deliver the decision-relevant result.**

---

## 10. What I am uncertain about, and what would settle it

1. **Whether the demand rescaling is exactly linear through the rail solver.**
   It should be — a linear resistive solve with per-instance current sources —
   but "should be" is not a measurement and the projection table in §6.4 is the
   one place this document computes rather than measures. *Settled by:* running
   Phase 2. ~10 minutes.

2. **What an RMII-active arm actually adds.** No measurement of this netlist with
   a free-running `RMII_REF_CLK` exists anywhere. The clock-tree contribution of
   the currently-dark domains is the specific quantity I cannot bound from the
   data on disk. *Settled by:* Phase 3, ~10 minutes of compute once the spec
   variant exists.

3. **Whether the EM exceedance clears.** The derate is known and correct
   (§6.5), so this reduces to whether the demand rescales as projected — i.e. to
   uncertainty 1. I expect 49 elements to go to 0, because the worst is 1.432
   against a projected 3.85x reduction and the population average is 0.008, but
   the 21 elements in the near-limit band are the ones to look at. *Settled by:*
   Phase 2.

4. **Whether an RTL SAIF's remapped coverage is as bad as I claim.** I predict
   well under 50%. *Settled by:* one `read_activity_file` at the remapped scope
   and reading the coverage line. ~3 minutes. Worth doing only if somebody
   disputes §5.3.

5. **Whether `asic-record` should come under retention** rather than power
   staying publish-opt-in for that reason. Out of scope here, and not a one-line
   change — the retention script aborts if a repository is in both the policy
   and the protected set.

6. **IO pad power is priced at the wrong supply** — the power intent the flow
   reads puts the IO rail in the core domain and the pads resolve to the core
   voltage rather than their real supply. Worth noting that the SAIF makes this
   *smaller*, not larger: the IO bucket falls from 26.4 mW at default toggles to
   0.35 mW at W3. It barely affects the core rail conclusion. It is already
   declared as `io-rail-ir-drop` and this work neither fixes nor worsens it.

---

## Appendix — corrections to premises this plan was started from

Recorded because each one changes a decision, not to score points.

1. **`rail_static.tcl` is dead code.** Nothing invokes it. The live consumer is
   `rail_run.tcl:179`. The prose about "no SAIF, no VCD anywhere in this flow"
   appears in **eight places across six files** and all of them go stale
   together.
2. **The rail handoff is not a one-line edit.** Four coupled changes, one of
   which (§6.3c) fixes a defect that already fired on the shipping candidate.
3. **W2 is not the higher window for rail.** It is higher on total chip power
   and lower on the core VDD rail, which is the only thing rail solves. Use W3
   at the rated clock.
4. **`TL_CLK_TX` is not tied by the bench.** It is a top-level output, absent
   from the bench spec entirely. It is dark because the design never brings the
   link up — which is why the D2D half of the coverage gap costs weeks and the
   RMII half costs minutes.
5. **There is no 256 KB gzip threshold in the publish path.** That figure is a
   git pre-commit fixture limit from an unrelated document. The bundle is
   published raw and uncompressed, one PUT per file, so compression has to
   happen before bundling. The measured ratios in §8.1 are new.
6. **The post_route hook line numbers quoted in three files are all stale.**
   Current: hook 2031, verdict 2679.
7. **No toolkit pin roll is needed** for runtime plusargs; the mechanism already
   exists and the prototype already used it.
8. **The prototype has one absent-renders-as-clean defect of its own** — it
   declares that it publishes a window record and publishes nothing (§4.5).
