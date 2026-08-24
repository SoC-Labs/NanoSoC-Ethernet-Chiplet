# IR-drop plan — 2026-08-24

State of static rail analysis on `nanosoc_eth_chiplet_pads`, what it actually
measured, and what to do in the eight days before the 1 September submission.

Author: dam1n19, srv03335. Every number below is read from a file on disk; the
provenance is given inline. Findings from a five-lens audit run 2026-08-24;
load-bearing claims independently re-verified before being written here.

---

## 0. The short version

* **IR drop has been run: once, on `fp1505`, 2026-08-17.** Worst effective
  collapse **15.0 mV = 1.389 % of 1.08 V** against a 3 % budget. On voltage this
  design is comfortable and never looked otherwise.
* **The gate returns FAIL_HARD, and its headline reason is already fixed.**
  The "330 instances with no path to a supply rail" is the island-feed defect,
  closed by `0c8b3e7` on 2026-08-18 — *the day after* fp1505 ran. The current
  lineage measures 2 island rails against fp1505's 34.
* **The number is stale in two directions at once.** Seven complete route runs
  and six power-plan commits newer; and stale *inside its own tag* — the census
  records `db.mtime=2026-08-17T21:32` while fp1505's routed database is
  2026-08-19 00:22.
* **EM analysis is reachable.** The standing "no EM rules for 9M 6X1Z1U" claim is
  wrong. Proven below by exact numeric identity against TSMC's own volcano rules.
* **The physics is not what the fix-list assumes.** The drop is **pad-entry
  limited**. From M7 down the mesh is an equipotential to 0.00 mV. 94.4 % of the
  missing power vias sit where there are no volts to recover.
* **There is a real, unmeasured regression** in the layers that *do* carry the
  drop: VIA7 −16.3 %, VIA8 −53.1 % between fp1505 and rzG.

**Item 1 in §7 is DONE — see §0b.** The design measures better than fp1505 on
every IR metric, the functional stranding is closed (55 → 0), and the one
remaining hard failure is 18 filler cells that defect D4 mis-reports. The
highest-value action is now **D4** (§5), which is licence-free.

---

## 0b. RESULT — rail run on `gdsrun-20260823-rzG`, 2026-08-24 10:11-10:18

**Ran in 6m40s. Completed with full artefacts (341). Every completeness assertion
passed.** It got past the exact point where `full-20260814` died: extraction built
206,534 nets with **0 incomplete routes** and no `VOLTUS_EXTR-1223` short.

Preflight `rail-selftest`: **29 passed, 0 failed**, both directions — so the gate
could have failed and did not for want of trying.

| metric | fp1505 (08-17) | **rzG (08-23)** | |
|---|---|---|---|
| worst effective collapse | 15.0 mV (1.3889 %) | **14.28 mV (1.3222 %)** | better |
| p99 effective collapse | 1.3574 % | **1.3009 %** | better |
| mean effective collapse | 1.1797 % | **1.1442 %** | better, still over 1.0 % |
| VDD worst droop | 6.32 mV | **5.93 mV** | better |
| VSS worst rise | 8.89 mV | **8.35 mV** | better |
| **stranded instances** | **330** | **18** | **−95 %** |
| — of which FUNCTIONAL | **55** (25 clock buffers) | **0** | **closed** |
| disconnected current sources | 201 + 79 = 280 | **8 + 6 = 14** | −95 % |
| instance coverage | 99.8596 % | 99.8655 % | — |
| solver / demand current ratio | 0.9975 | 0.9975 | — |

**VERDICT: FAIL_HARD**, now on `pg.disconnected` alone (18 > 0). At `--tier report`
`em.current_density` is ADVISORY and does not drive the verdict.

### The predicted regression is REFUTED

§3 predicted the VIA7 −16.3 % / VIA8 −53.1 % loss would widen the M8→M7 descent.
Measured, it did not:

| leg | VDD fp1505 → rzG | VSS fp1505 → rzG |
|---|---|---|
| pad → M9 | 3.79 → **3.54 mV** | 4.48 → **4.15 mV** |
| **M8 → M7 descent** | 2.26 → **2.22 mV** | 3.93 → **3.97 mV** |
| M7…M3 | 0.00 | 0.00 |
| total | 6.32 → **5.93 mV** | 8.89 → **8.35 mV** |

The descent leg is flat to ±0.04 mV across a 53 % via reduction. **Those vias were
redundancy, not conductance** — 4,070 VIA8 still carries a ~2,200× EM margin. The
improvement instead came from the *pad-entry* leg (−0.25 / −0.33 mV), consistent
with the M9 stripe offset and the padring ring-spacing change in `dd78a50`.

This is the second time on this design that a via population has been read as an
electrical deficit when it was lost redundancy. The lesson generalises: **rank a
via finding by the measured gradient across its layer pair, not by its count.**

### The one remaining hard failure is 100 % filler

Decomposed from the `.iv`: all **18** are FILL/ANTENNA/DCAP class; **zero**
functional logic. The gate's text — "those cells do not power up" — is now
describing 18 filler cells. This is exactly defect **D4** in §5: with the
population split by cell class, this design passes the connectivity criterion
outright and the remaining item is orphaned decap, which is a different (and much
smaller) conversation.

**Action:** D4 moves from "cheap fix" to **the thing standing between this design
and a clean rail verdict.** Do it before quoting the verdict anywhere.

### What did NOT improve

`coverage.power_attributed_frac` fell 0.6935 → **0.6727** — 26.29 mW now
unattributable against 24.13 mW. The IO-liberty `pg_pin` gap (§9) is a fixed
fraction of a design that grew (`db.insts_total` 351,211 → 366,446,
`power.total_mw` 78.72 → 80.31). Not a regression in the PDN; a reminder that the
broker ask is load-bearing.

The mean budget is unchanged in character: 1.1442 % against 1.0 %, on a
distribution that is still flat. §2a's conclusion stands — **no via, open or
dangling-wire fix will clear it; it is a pad-count problem.**

---

## 0c. GATE FIXES APPLIED — 2026-08-24, verdict FAIL_HARD -> FAIL_BUDGET

Defects D1, D4 and G4 from §5 are fixed in `rail_gate.py`. Working tree only,
**not committed** — this repo has concurrent sessions sharing an index.

| check | before | after |
|---|---|---|
| `divisor.agrees` | read `power.voltage_agrees`, a boolean the run wrote about itself | recomputed from both raw voltages **plus** the tool's own `Voltage:` field — three independent witnesses |
| `pg.disconnected` | 18 raw NA rows, "those cells do not power up" | **0 FUNCTIONAL**; 18 fillers reported via a new non-gating `pg.disconnected_filler`, split further into 6 reaching neither rail and 12 reaching one |
| `parity.parser_vs_tool_vss` | **did not exist** — the regex could not parse `8.893mV` | **passes at delta 0.003 mV**, a genuinely tight independent cross-check of the larger half of the collapse |

**VERDICT: FAIL_HARD -> FAIL_BUDGET.** Every hard completeness and functional
check now passes on `gdsrun-20260823-rzG`. The sole remaining failure is
`budget.eff_mean_pct` 1.1442 % against the 1.0 % convention — which §2a shows is
a pad-count property, not a grid defect.

**The fixes are mutation-proven, not merely green.** The battery went 29 -> 32
cases. Three are new and each is a shape measured on a real artefact today:

* `disconnected_all_filler` (expect PASS) — the rzG shape, 300 fillers and no
  logic. **Reverting the split to the raw count flips this case to FAIL**, so it
  discriminates; verified against a deliberately mutated copy of the gate.
* `disconnected_functional_under_filler` (expect FAIL_HARD) — the fp1505 shape,
  25 clock buffers under 275 fillers. The logic must be found under the fill.
* `disconnected_unknown_master` (expect FAIL_HARD) — a master the filler pattern
  does not recognise is **gated, not waved through**. Unrecognised fails safe.

The fixture generator was also corrected: it wrote VDD and VSS with the *same*
shape, which is why a parser that could not read VSS at all went unnoticed. It
now renders VSS as the tool really does — `Voltage: 0.000` and millivolts.

**Still open from §5 at the time of writing:** D2, D3, D5, G1, G3. All five are
now closed — see §0e.

## 0e. THE REMAINING SIX — 2026-08-24, verdict FAIL_BUDGET -> FAIL_HARD

D2, D3, D5, G1, G3 and the EM wiring are done. Working tree only, **not
committed**. The battery went **32 -> 47 cases**, every one of the fifteen new
ones mutation-proven against a reverted copy of the gate.

| defect | what changed |
|---|---|
| **D2** `vsrc.count`'s two sides were one query | new `vsrc.count_per_net`: `Total Static Current Loaded / average Vsrc Current` reconstructs the count **per net** from the solver's own arithmetic. Measures **6.000000** and **4.000000** against 6 and 4 pads. Independent of the `get_db` selector, and per-net, so 9+1 can no longer pass as 6+4 |
| **G2** pad current balance | new `budget.pad_current_spread` — VDD 7.738/8.316/8.783 mA (12.56% of the mean), VSS 11.952/12.505/13.144 mA (9.53%), limit **40%**. Each VSS pad carries **1.5038x** a VDD pad and the VSS rise is **1.4081x** the VDD droop — the pad-count story in two independent numbers |
| **G3** the layer report was a path, never opened | `parity.layer_vs_iv_{vdd,vss}` reconcile the layer stack against the per-instance report: **delta 0.000 mV on both nets**. Per-leg contributions are now metrics, and so is the headline — **97.64% (VDD) / 98.20% (VSS) of the drop is spent at or above metal7** |
| **G1** Reff | `-enable_reff_analysis true` added to `rail_run.tcl`'s `set_rail_analysis_mode`. `reff_status` is a recorded metric |
| **EM** | `-process_techgen_em_rules true -ict_em_models <file> -em_temperature 125`, with the model built on demand by `gen_em_ict.py` and the run **dying** rather than solving without one. New `method.em_models` check refuses a J/Jmax number whose ruleset is not named |
| **D5** `RAIL_TIER` | **deleted**, not fixed. See below |
| **D3** a failing ADVISORY | new outcome **`PASS_DEGRADED`, exit 4**, and a `NOT MEASURED (n): ...` line in `emit()` |

**Why D5 was resolved by deleting the knob and not by making `report`
non-blocking.** The second option means "always exit 0", and `rail_project.mk`
defaulted `RAIL_TIER` to `report` — so the default invocation of the stage would
have become incapable of failing. That is the exact class of defect this gate
exists to catch, installed in the gate. The blocking decision already had a
home: the `gate:` field on the `ci/signoff.yaml` row. It now has only that one.
`rail_gate.py` still *accepts* `--tier` and refuses with an explanation and
exit 3, because the string outlives the change in shell histories.

**The verdict moved FAIL_BUDGET -> FAIL_HARD, and that is the honest number.**
`--tier report` was the only thing making `em.current_density` advisory. EM has
never been analysed on this design; the budget file's own words are "an
unmeasured signoff criterion is not a pass". §0c's FAIL_BUDGET was a verdict
obtained by asking for a softer one. What clears it is the next *run* of the
stage, now that the EM flags are in `rail_run.tcl` — not an edit anywhere.

Everything else on rzG is unchanged: 14.28 mV worst, 1.3222% / 1.3009% / 1.1442%,
0 functional PG opens, and `budget.eff_mean_pct` still the one real budget
failure.

### CI fixtures repaired at the same time

`ci/fixtures/ir-drop/` had rotted against the 08-24 morning's gate fixes and
`signoff.py prove ir-drop` would have reported `must_pass` BROKEN:

* **`pass`** was failing HARD on `parity.parser_vs_tool_vss` — its `VSS.main.rpt`
  still carried fp1505's full-design `8.893mV` while its `.iv` had been cut down
  to 600 instances whose worst is 5.51 mV. The VDD half of the same file had
  been tuned that way and the VSS half had not, which is the same asymmetry that
  hid the unit-blind regex.
* **`fail-disconnected-instances`** is 60 `DCAP4` and not one functional cell, so
  since the `FILLER_RE` split it no longer trips `pg.disconnected` at all — it
  was passing `must_fail` on `em.current_density` instead. Ten rows are now
  `CKBD1` clock buffers, which is the shape the real artefact had.
* **`fail-over-budget`**'s summaries were never rescaled when its `.iv` was, so
  it was tripping both parity checks as well as the budget it is named for.

All six now carry layer reports and the `pass` fixture carries the EM model
declaration. `signoff.py prove ir-drop` and `prove ir-drop-selftest`: **0
problems**.

---

## 0d. EM MODEL FILE BUILT

`ASIC/genus-innovus/rail/gen_em_ict.py` derives a Voltus ICT-EM file from data
already on disk. Selftest **6/6**: the three via identities against the volcano
file, both derate curves, and the M1 wire identity. Output covers 10 routing and
9 cut layers, full stack to AP.

Two design points worth keeping: the generator **refuses to run** if the copper
derate curve differs between M1, M8 and M9, because metallurgy-invariance is the
entire justification for transferring the curve to this stack; and RV is
classified as **aluminium** (it lands on the Al RDL) so it derates x0.671, not
x0.358 — getting that backwards would misprice the design's narrowest plane by
1.9x.

**The generated `.ict` is gitignored** (`.gitignore:108`). Its contents reproduce
TSMC current-density values verbatim, so it is vendor collateral by the same
argument that already ignores `rail/work/`. The generator is tracked; its output
is rebuilt. `check_no_vendor_collateral.sh` passes **with `TSMC_65_HOME` set** —
run without it, its verbatim-text check silently skips and still returns 0.

**WIRED IN 2026-08-24** — `rail_run.tcl` resolves it through
`::rail::ensure_em_ict`, builds it if absent, and refuses to solve without it.
The volcano glob matches **four** per-library copies and `glob_one` would refuse
all four; generating the model from each in turn gives **byte-identical** output
once the source-naming header is discarded, and `--selftest` passes 6/6 against
every one, so one is taken deterministically and the one used is written into
the census.

---

## 0e. THE 96 DROPPED FLOPS — SETTLED **SAFE**, 2026-08-24

Synthesis deleting all 96 flops of `root_port_cursor_r` does **not** change behaviour
in the shipping `NUM_PORTS=1` configuration. Proven by simulation, with a control.

**The obvious hypothesis was wrong.** "It is safe because every parent is visited
once" is false — parents ARE revisited: `p_id = root_parent_id[c_id-1]`, so a
parent with N children is visited N times. The bench shows one parent visited
**6 times**, gold cursor climbing 0 -> 2 -> 3 -> 4 -> 5 -> 6.

It is safe for a different reason, in two parts:

1. **For any non-root parent the guard is combinationally unsatisfiable at
   `NUM_PORTS_V==1`.** The uplink-skip at line 1130 reads
   `if (p_id != 0 && cursor == UPLINK_PORT_ASSUMED) assign_port = cursor + 1;
   else assign_port = cursor;` with `UPLINK_PORT_ASSUMED == 0`. So for
   `p_id != 0`, `assign_port` is **never 0** — it is 1 when the cursor is 0 and
   the cursor value otherwise. The guard `assign_port < 1` therefore never
   passes, on any visit, including after the 3-bit cursor wraps. Confirmed in the
   trace: every `p_id != 0` step shows `write=0` in both gold and mutant.
2. **The root is the only parent whose guard can pass, and it is visited exactly
   once**, structurally — `RST_IDLE` loads `cur_port_count_r <= NUM_PORTS`, so at
   `NUM_PORTS=1` the root's scan covers port 0 only. Re-enumeration is covered
   too: phase 0 (line 1096) re-zeroes all 32 entries on every entry to
   `RST_SUBTREE_WALK`, so nothing accumulates across runs.

**The control is what makes the zeros mean something.**

| expt | config | topology | result |
|---|---|---|---|
| A | NUM_PORTS=1 | parent visited 2x | 0 mismatch cycles |
| C | NUM_PORTS=1 | 3-level, 3x and 2x | 0 mismatch cycles |
| D | NUM_PORTS=1 | widest legal, 6x | 0 mismatch cycles |
| **B** | **NUM_PORTS=2 (control)** | **root visited 2x** | **DIVERGENT, 2 cycles** |

At `NUM_PORTS=2` removal corrupts the result concretely: gold emits
`subtree_wr[port=0]=0x04` and `[port=1]=0x02`; the mutant writes both children
onto port 0, so `port=0` gets `0x02` and `port=1` stays `0x00` — the enumeration
would report that port 1 reaches nothing. **That defect is real, and it is latent:
it appears the moment this IP is instantiated with more than one port.** Worth a
comment in the RTL, because nothing currently warns the next integrator.

**Why Conformal could not prove it dead.** Its only live-looking fan-out needs a
two-step chain its dead-code pass did not compose: the guard is satisfiable only
when `p_id==0`, and in that branch it writes `root_own_port_subtree_r` — which
Conformal *did* prove dead (it is among the 446 unreachable). Each step alone
leaves the cursor looking live; only the composition kills it.

**Bench:** `scratchpad/cursor_proof/run.sh` (~30 s, VCS). Regenerates gold and
mutant from the LIVE RTL each run and aborts if the mutation fails to apply, so
it cannot silently test a stale or unmutated build. Source pinned at md5
`885145580439395ebc592bb326a5a0e3`. Re-verified from scratch before this was
written; mutation confirmed present at line 1128.

### Secondary, and worth knowing separately

The same removal cluster shows that **Phase-P4 per-port subtree distribution is
dead silicon on this die** — deliberately. `nanosoc_eth_chiplet.sv:648` names the
TC->IRQC stream `tc_to_irqc_*_nc` and leaves it dangling with the inputs tied
idle (the RTL comment says so), and `APB_ADDR_W=8` puts the 0x100+ subtree region
out of APB reach. Verified in the shipping netlist: `tidechart_irqc_burst_fsm` 0
hits, `uplink_subtree_r` 0, `local_subtree_r` 0. `root_port_subtree_r` survives
only because it feeds `PUSH_SUBTREE` packets out over the link.

**Consequence for signoff:** nobody should expect to read `TC_PORT_SUBTREE_*` on
the ASIC. If any bring-up plan does, it is testing something that was removed on
purpose.

**Consequence for `lec`:** the RESULT=FAIL on the 08-21 synthesis is a benign
unmapped-point class, not lost logic. But the LEC gate cannot currently tell that
from a real loss, and this took a simulation to establish — so the right fix is to
record the finding against these specific points, not to relax the gate.

---

## 1. What was measured, and what it says

`rail_gate.py` recomputed 2026-08-24 from the 08-17 artefacts (at what was then
`--tier signoff`; the flag no longer exists — see §0e).
Licence-free — it reads files, deliberately.

| metric | value | budget | |
|---|---|---|---|
| worst effective collapse (co-located) | **15.0 mV** = 1.389 % | 3.0 % | pass |
| p99 effective collapse | 1.357 % | 2.0 % | pass |
| **mean effective collapse** | **1.180 %** | 1.0 % | **FAIL** |
| VDD worst droop | 6.32 mV = 0.585 % | 2.0 % | pass |
| VSS worst rise | 8.89 mV = 0.823 % | 2.0 % | pass |
| instance coverage | 99.8596 % (350,718 / 351,211) | ≥ 99 % | pass |
| solver current / demand | 0.9975 | 0.9–1.1 | pass |
| demand vs `imp_power.rep` | 0.0011 % apart | < 1 % | pass |

**VERDICT: FAIL_HARD** on `pg.disconnected` (330), `em.current_density`
(NOT_ANALYSED) and `budget.eff_mean_pct`.

### 1a. The 330 is three populations, and 275 of them are not a defect

Decomposed from the Voltus `.iv` directly:

| population | count |
|---|---|
| FILL / ANTENNA / DCAP class | **275** |
| **functional logic** | **55** — of which **25 clock buffers** (`CKBD1`×17, `CKBD0`×4, `CKBD2`×4), 3 flops |

176 of the 330 have a path to VSS and only their VDD open, so the gate's text
("NO PATH to a supply rail … those cells do not power up") is false for most of
them. The 55 independently reproduces the project's standing stranded-cell
record from a different artefact. **Remedy implied by 330** (rebuild the PG)
**differs from the remedy implied by 25 unpowered clock buffers.** See D4 in §5.

---

## 2. THE PHYSICS — this reframes the whole fix list

`results/PD_TOP_125C_avg_1/{VDD,VSS}/Reports/*.layerbased_ir.rpt`, cumulative
worst drop down the current path. Voltage sources sit on **metal7 at the pad
pins** (`VDD_vsrcs.rpt`), so "pad → M9" is the entry path up and back down.

| leg | VDD | share | VSS | share |
|---|---|---|---|---|
| pad (M7) → M9 | **3.79 mV** | 60.0 % | **4.48 mV** | 50.4 % |
| M9 → M8 | 0.05 | 0.8 % | 0.08 | 0.9 % |
| **M8 → M7** (the via descent) | **2.26 mV** | 35.8 % | **3.93 mV** | 44.2 % |
| M7 → M6 → M5 → M4 → M3 | **0.00–0.01** | 0.2 % | **0.00** | 0.0 % |
| M3/M2 → M1 | 0.20 | 3.2 % | 0.40 | 4.5 % |
| **total** | **6.32 mV** | | **8.89 mV** | |

These totals equal the gate's `vdd_droop_worst_mv 6.32` and
`vss_rise_worst_mv 8.89` exactly, so the decomposition is arithmetic.

**M7 = M6 = M5 = M4 = M3 to five decimals. The core mesh is one node.**
95.8 % of the VDD drop and 94.6 % of the VSS drop is spent above M7.

**Implied per-pad series resistance:** VDD 6.32 mV / 8.40 mA = 0.752 Ω;
VSS 8.89 mV / 12.61 mA = 0.705 Ω — agreeing to 6.3 %. The drop is
(per-pad current) × (a fixed ~0.73 Ω entry path). **Pad-count limited, not grid
limited.**

### 2a. Why the mean fails, and what cannot fix it

Distribution: worst 1.3889 %, p99 1.3574 %, p50 1.2398 %, mean 1.1797 %.
p50 → worst is **1.61 mV across 350,388 instances**. There is no tail.

A via/open population produces *outliers* — a right tail. This is the opposite
shape: a hard floor everywhere with almost no spread, the signature of a series
resistance shared by every instance. **The failing mean does not point at the
vias. It points at the pad entry.**

Clearing 1.180 % → 1.0 % needs ~15 % off the total. With ~55 % of the drop being
per-pad entry, **adding 2 VDD + 2 VSS core supply pads gets ~16 % and lands it.**
Nothing in `power_plan.tcl` can do that — all 6 VDD and 4 VSS pads are on the top
and bottom edges. That is a padring change eight days out, so it is a
next-revision item. **It is worth saying plainly that no via, open or
dangling-wire fix will ever clear this budget.**

### 2b. Where the missing vias actually are

| pair | missing | present | fraction | measured gradient there |
|---|---|---|---|---|
| M3→M4 | 13 | 15,158 | 0.086 % | 0.00 mV |
| M4→M5 | 192 | 57,522 | 0.33 % | 0.00 mV |
| M5→M6 | 109 | 21,465 | 0.51 % | 0.00 mV |
| M6→M7 | 37 | 20,633 | 0.18 % | 0.00 mV |
| M7→M8 | 1 | 20,358 | 0.005 % | in the 2.26 / 3.93 mV leg |
| M8→M9 | 3 | 4,070 | 0.074 % | 0.05 / 0.08 mV |
| **M9→AP + stacked** | **4** | **7 RV** | **~13 %** | **not modelled — §4** |

**351 of 372 (94.4 %) are in M3↔M7 where the gradient is 0.00 mV.** Fixing all of
them moves IR by well under 0.1 mV.

Counter-direction, for honesty: connecting the 330 stranded cells *adds* load.
The solver loaded 50.4197 mA against a demand of 50.5469 mA; the 0.127 mA gap is
their current. Fixing them raises IR by ~+0.03 mV.

---

## 3. The regression nobody has measured

PG special-via population, die-wide, from `pg_capacity_*.rep`:

| cut layer | fp1505 | rzG | Δ |
|---|---|---|---|
| VIA1/2/3 | 14,429 / 14,105 / 14,090 | 15,385 / 15,152 / 15,158 | +6.6 / +7.4 / +7.6 % |
| VIA4 | 61,618 | 57,522 | −6.6 % |
| VIA5 | 25,233 | 21,465 | −14.9 % |
| VIA6 | 24,749 | 20,633 | −16.6 % |
| **VIA7** | 24,310 | 20,358 | **−16.3 %** |
| **VIA8** | 8,683 | 4,070 | **−53.1 %** |
| RV | 7 | 7 | unchanged, margin 1.52× → 1.54× |

Localised to the final `route_special` at `power_plan.tcl:1161`: 142,980 vias
created in fp1505 (VIA8 7,633) against 124,286 in rzG (VIA8 2,814), for
essentially the same wire count. Every earlier pass is identical between builds.
The macro M4 keep-out is in force for exactly that command.

**VIA7/VIA8 are the M8→M7 descent, which carries 36–44 % of the measured drop.**
Upper-bound estimate (1/N overstates a parallel network): a 16 % VIA7 loss takes
that leg 2.26 → 2.70 mV (VDD) and 3.93 → 4.69 mV (VSS), eff_worst 15.0 → ~16.2 mV
(1.39 % → 1.50 %), mean 1.18 % → ~1.27 %. Worst and p99 would still pass; the
mean gets worse.

**This is unmeasured. There is no rail run on rzG.** It is the reason §7 item 1
outranks everything else.

---

## 4. RV — the narrowest plane, short one via, and invisible to the analysis

`place_pg_audit.rep` (both builds): `pg_vias_to_AP 7`, `AP_shapes 5`.
`pg_capacity_*.rep`: `RV 7 vias, 99.000 µm² cut, TOTAL 77.0 mA, margin 1.54×` —
flagged `WORST PLANE`, against a demand the same report labels *"NO SWITCHING
ACTIVITY — a guess"*. The flow's own floor `EVP_MIN_RV_VIAS` is **8**.

`check_power_vias` names five records at one site, all net VSS, x 249.30–252.90:
a missing VIA8, a missing RV, and three M1→AP stacks. Adding it takes RV 7 → 8
and 77 → 88 mA.

**The rail analysis cannot see this plane.** All ten voltage sources sit on
metal7 at the pad pins — *below* AP/RV. If RV is the real package entry, the
whole IR result is measured from the wrong node.

---

## 5. Defects in the gate itself

Verified against the code and the artefacts, not the comments.

**D1 — `divisor.agrees` trusts a boolean the run wrote about itself.**
`rail_gate.py:538` reads `cen.get("power.voltage_agrees") == "true"`. Both raw
voltages are in hand at line 535 and never compared. Fixture-proven: identical
millivolts flip **FAIL_BUDGET → PASS** on a mis-stamped divisor — the 11 % swing
between 1.08 V and 1.20 V that the budget file's own header calls "the most
dangerous single mistake available here." **Fix:** recompute
`abs(configured − rail) ≤ 0.001`, and cross-assert against the tool's own
`Voltage:` field and the `.iv` header's `NOMINAL_VOLTAGE` — both already parsed
and discarded.

**D2 — FIXED 2026-08-24. `vsrc.count`'s two sides descend from the same selector.** Expectation and
measurement are the same `get_db` query, so a pad master matching a subset passes
with full marks. **Fix, free:** `Total Static Current Loaded / average Vsrc
Current` reconstructs the per-net source count exactly from the solver's own
arithmetic — measured 6.000000 for VDD, 4.000000 for VSS.

**D3 — FIXED 2026-08-24 (`PASS_DEGRADED`, exit 4). A failing ADVISORY is invisible to the verdict.** `status` looks only at
HARD and BUDGET, so `coverage.demand_vs_flow_power` — the only check reading an
artefact the rail stage did not write — degrades to "skipped, treated as passed"
whenever `reports/` is absent.

**D4 — the blocking number is three populations added together.** See §1a.
**Fix:** split into `pg.floating` (all-NA) and `pg.single_rail_open`, classify by
cell master, keep the zero limit on the functional population.

**D5 — RESOLVED 2026-08-24 by DELETING the knob. `RAIL_TIER` is cosmetic.** It changes one label. Measured: `--tier
signoff` → FAIL_HARD exit 2; `--tier report` → FAIL_HARD exit 2. Three files
claim otherwise, including the signoff manifest's note that promoting is "a
one-word edit plus `RAIL_TIER=signoff`". That edit would change no exit code.

**G4 — VSS parity cannot run.** The regex requires `…V` three times;
`VSS.main.rpt` prints `0.000V 7.215mV 8.893mV` and the `m` breaks the match.
Confirmed live: VDD parses, VSS returns nothing. **The larger half of the
collapse has no parser-vs-tool cross-check at all.**

**G1 — FIXED 2026-08-24. Reff is NA for one missing flag.** `rail_run.tcl:311` omits
`-enable_reff_analysis true`; `reff.tcl:111` has it. This matters more than it
sounds: every millivolt here inherits an assumed switching activity (no SAIF, no
VCD anywhere). **Effective resistance is a property of the drawn metal alone** —
one flag converts an unfalsifiable millivolt into an ohm that any future activity
assumption can be re-priced against, without re-solving.

**G3 — FIXED 2026-08-24. The per-layer breakdown was recorded as an artefact
path and never opened.** It is §2 of this document: the entire engineering
answer, thrown away. It now reconciles against the per-instance report at
**delta 0.000 mV on both nets** — two different reductions of the same solve,
one over grid elements by layer and one over instances.

Also: seven scripts in the directory hardcode `1.08` and ignore `$::RAIL(vcore)`,
so `RAIL_VCORE=1.10` would move the solve and silently leave the PGV behind.

---

## 6. Flow and process findings

**6a. The stage exists in signoff and is pinned to the stale build.**
`ci/signoff.yaml:1930` `ir-drop` (`gate: report`), `:2120` `ir-drop-selftest`
(`gate: block`), both committed at HEAD. It is pinned by name to `fp1505` and
will re-analyse it indefinitely. It is also the **only physical stage with no
`needs_implementation:`**, so an absent build renders FAIL — an indictment of the
design — rather than UNVERIFIED, an indictment of the run.

The working invocation is `make -C ASIC/genus-innovus rail RAIL_RUN_TAG=<tag>`.
**Not** `make -f .../rail_project.mk` — that fragment defines neither
`DESIGN_DIR` nor `BLOCK`, so `RAIL_DB` resolves to a path that cannot exist.

**6b. Every physical stage in the manifest is stale — no exceptions.** All 15
are pinned to `full-20260814` (8 runs old), `fp1505` (7), or an 08-10 legacy
stream. The driver's staleness logic compares `repo_sha` against git HEAD and has
**no notion of build staleness at all**, so a stage pinned to fp1505 re-run today
renders green and "measured at HEAD".

**6c. The design was re-synthesised on 08-21 and `lec` was told not to follow.**

```
full-20260814      gate.v  md5 f567c9c0…  2026-08-14 13:56
gdsrun-20260821-slpads     md5 a7076071…  2026-08-21 21:11
gdsrun-20260823-rzG        md5 a7076071…  2026-08-21 21:11
```

`lec` is pinned to `full-20260814` with an emphatic comment justifying it: *"the
synthesised netlist under signoff IS full-20260814's, unchanged."* That is now
false. And the 08-21 synthesis **has already been LEC'd against RTL and failed** —
`slpads/reports/lec/syn/verdict.txt`: 5,433/5,433 equivalent but
`unmapped_extra_golden=96`, `tool_exit_code=40`, **RESULT=FAIL**; 96 RTL flops
(`u_tidechart/…/root_port_cursor_r_reg[*][*]`) with no counterpart in the gate
netlist. rzG has a **clean** post-P&R LEC (61,599 points, RESULT=PASS) that
`lec-pnr` does not read because it is pinned to fp1505.

**Outside the scope of this plan, and more urgent than anything in it.**

**6d. The shipping GDS is not reproducible from the published toolkit.**
`ASIC/asic-toolkit` HEAD `3ca1160` is stamped into rzG's route manifest with
`toolkit_git_dirty yes`. Measured: **13 ahead of / 23 behind `origin/main`**,
diverged at `55eb607` (08-19), and **`3ca1160` is not an ancestor of
`origin/main`**. This is a private fork, not a checkout.

**6e. The route gate's via breakdown is short by 16.** `4_route.tcl:409`'s regex
does not match `Missing 13 Stacked Via(s)` — `Stacked` sits between the count and
`Via(s)`. Verified: the per-pair breakdown sums to **356** against a stated total
of **372**, and the 16 dropped records are exactly the two stacked classes —
**including the RV-plane stack from §4, the ones that matter most.**

**6f. `pg_capacity.tcl` reports a 110 °C ceiling; the rail flow analyses at
125 °C.** Every Cu limit derates ×0.358 there (Al ×0.671), so the published PG
capacity margins are **~2.8× optimistic**. A live error in a shipped report,
independent of whether Voltus EM ever runs.

**6g. `voltage_io` is 2.50 V in the tech pack and the real supply is 3.3 V.** It
derives from a glob on the library *directory* name `IO2.5V`, which names the
gate-oxide class; `od3` in the same cell name means over-drive 3.3 V. The liberty
says `nom_voltage : 3.3` and the UPF says 3.30. Blast radius is zero today —
`voltage_io` has no functional consumer — but `tech_validate` never cross-checks a
declared voltage against the `nom_voltage` of the libraries the same pack points
at, so 2.50 against a 3.3 V library validates clean.

---

## 7. What to do, in order

### 1. Run the stage on `rzG`. ~30 min, 1 Voltus seat, no P&R. Do this first.

```
make -C ASIC/genus-innovus rail-selftest                                  # gate can still fail?
make -C ASIC/genus-innovus rail RAIL_RUN_TAG=gdsrun-20260823-rzG RAIL_TIER=report
```

**Why it outranks everything:** §3's −16 %/−53 % VIA7/VIA8 loss sits in the layers
carrying 36–44 % of the drop and is entirely unmeasured, and §1a's 330 is expected
to fall to ~20–30. Every other item below is currently ranked on a six-day-old
measurement of a different database.

Pre-flight: do **not** run while `gdsrun-20260824-valid7` is mid-place — two
Innovus sessions against one build root is how a half-written DB gets graded.
Acceptance: `result.completed=true`, coverage ≥ 99 %, current ratio 0.9–1.1,
10 sources against 10 pads. Miss any and the numbers are not quoted.

### 2. Fix the gate's four cheap defects — no licence, no run. **DONE — §0c and §0e.**
D1 (recompute the divisor), G4 (unit-aware regex + VSS parity), D4 (split the
330 by cell class), D2 (source count from `total / average`). Then re-cut the
selftest's `MAIN_RPT` fixture from the real 90-line report — it is a 9-line stub
whose shape signature does not match, which is *why* G2/G4/G8 are invisible to a
green battery.

### 3. Turn on Reff. One flag, `rail_run.tcl:311`. **DONE — §0e.**
`-enable_reff_analysis true`. The only activity-independent measurement available
on this site. `reff.tcl` already proves it works here (338,648 instances, p50
5.99 Ω, p99 9.40 Ω) — but on a *different build*, joined to nothing.

### 4. Enable EM. Reachable, and the standing claim is wrong. **WIRED — §0e; still needs one run.**

The tech LEF for exactly this stack carries 19 `DCCURRENTDENSITY AVERAGE` tables
and 39 `ACCURRENTDENSITY` entries, covering **the full stack including M8, M9,
VIA8, RV and AP**. It *is* TSMC's volcano ruleset delivered in LEF form — proven
by exact identity against the 9lm6X2Z volcano file:

| via | LEF J × cut area | volcano |
|---|---|---|
| VIA1–6 | 15.800000 × 0.01 µm² = 0.158 mA | 0.00015800 A |
| VIA7/8 | 23.742284 × 0.1296 µm² = 3.077 mA | 0.00307700 A |
| RV | 0.777778 × 9.0 µm² = 7.000 mA | 0.00700000 A |

Exact to every digit. TSMC's own `NoEM_readme.txt` in that directory says only
`EM not support metal scheme : *3Z` — ours is 6X1Z1U.

Voltus doc (`SSV_21.11.000/doc/voltustxtcmdref/set_rail_analysis_mode.html`):
*"In the static mode, if `–em_models` is not specified, or if
`-process_techgen_em_rules` is not set to true, current density (RJ) analysis
will be disabled due to lack of EM models."* — which exactly explains the empty
J/Jmax and its false `Number of Violations: 0`.

Route: author an ICT-EM model file (it carries `jmax_factor`, which the
`-em_models` format does not, so the 110 °C data derates correctly to the 125 °C
run) and add `-process_techgen_em_rules true -ict_em_models <file>
-em_temperature $::RAIL(temp)`. Do **not** set the first without the second — the
doc says it would then read the qrcTechFile, which has zero EM rules.

Reachable: **DC average**, which is the correct check for a unidirectional PG
grid. RMS/peak need a current waveform and are not reachable without SAIF/VCD —
which costs nothing that matters.

Timebox to one run. Expect **RV to light up first**: 7.8e4 A/cm² against
6.9–8.8e5 for every Cu layer, an order of magnitude down.

### 5. Recover the RV via. One site, net VSS, x 249.30–252.90.
Takes RV 7 → 8 (the flow's own floor) and 77 → 88 mA on the design's narrowest
plane. Touches no signal route; needs a DRC pass because M9/AP is where the
bond-pad clearance fight lives.

### 6. A/B the via regression without reverting anything.
`EVP_MACRO_M4_KEEPOUT=0` is a one-variable experiment that edits no file
(`power_plan.tcl:1122`). Run it on `scripts/probe_pg_build.tcl` — minutes, no
route — and diff the ViaGen tables. If the keep-out is the agent, the answer is a
*narrower* keep-out (`EVP_MACRO_M4_KEEPOUT_INSET` up to 0.3, the file's own
ceiling) or a per-macro exemption — not turning it off, which re-opens 22
VIA3/M4.S signoff results.

### 7. Repoint the manifest and stop this recurring.
Repoint `ir-drop` off `fp1505`; add `needs_implementation:` (both
`work/*_routed` **and** `reports/route_manifest.txt` — the manifest is written at
the end, so its presence is the proof the route finished) and a `timeout_s:`.
Keep `gate: report`. Then add the stage the manifest does not have: a cheap
`block` build-freshness gate — no PDK, no seat — that resolves every run tag the
manifest names and fails if any is not the newest build carrying a route
manifest. Repointing eleven tags by hand is what produced §6b once already.

### 8. Fix the two reporting errors that mislead readers.
`4_route.tcl:409`'s regex (§6e) and `pg_capacity.tcl`'s temperature basis (§6f).
Neither changes the design; both change what people believe about it.

### 9. Re-run on the shipping stream when `valid7` (or its successor) lands.
`make -C ASIC/genus-innovus rail RAIL_RUN_TAG=gdsrun-20260824-valid7`.
The rzG result becomes the control — the first chance this design has had to see
whether a PG change moves the voltage in the direction intended.

### Explicitly NOT worth doing for IR reasons
The 711 dangling PG wires (all zero-area stub tips on wires that *are* connected)
and the 351 M3–M7 missing vias (where the mesh is an equipotential to 0.00 mV).
They are DRC/antenna work and are already being handled as such.

---

## 8. Cost

| item | wall | licence | blocks on |
|---|---|---|---|
| 1 — rail on rzG | ~30 min | 1 Voltus | valid7's place finishing |
| 2 — gate defects | ~half day | none | — |
| 3 — Reff flag | +0 (next run) | — | — |
| 4 — EM enable | ~1 h authoring + 1 run | 1 Voltus | — |
| 5 — RV via | ~1 h + DRC | Innovus | — |
| 6 — keep-out A/B | ~15 min | Innovus | — |
| 7 — manifest + freshness gate | ~2 h | none | — |
| 8 — reporting fixes | ~1 h | none | — |
| 9 — rail on valid7 | ~30 min | 1 Voltus | valid7 route |

Voltus has 41 idle seats; licence contention is not a constraint. The real
constraint is Innovus sessions against the build root.

---

## 9. Scope — what this will still not tell us

Carry verbatim into signoff prose. Each is a property of the site.

* **STATIC only, at assumed switching activity.** No SAIF, no VCD anywhere.
* **`techonly` PGV.** No cell SPICE or GDS on site: models the grid *between*
  cells, not inside them. Typically within 10–20 % of GDS-based.
* **Die-only, no package model** — and per §4, the sources sit on M7, *below* the
  AP/RV plane that is the real package entry.
* **VDDIO/VSSIO excluded by name.** Absent from the CPF, no top-level PDN, IO
  supply cells have no internal power table. Including them returns ~0 mV by
  construction — a false green. IO supply integrity is asserted by pad-abutment
  construction and is not independently verified.
* **69.35 % of chip power attributable.** TSMC's IO liberty has zero `pg_pin`
  groups; nothing in tool setup fixes it.
* **The divisor is 1.08 V (`ss` corner), not the 1.20 V tech nominal.** Mixing
  them moves every percentage by 11.1 %.

**Broker asks this plan adds:** a `pg_pin` liberty for `tphn65lpgv2od3_sl`. The
EM-rules ask is **withdrawn** — the data is on disk (§7 item 4).
