# 15 — PG special-route opens: static analysis and ranked hypotheses

> **Status — SUPERSEDED.** The root cause this page ranks as hypotheses was found: `split_row` PG anchoring strands cells on narrow row islands ([42](42-stranded-cells-pg-islands.md), mechanism in [36](36-split-row-pg-anchoring-hazard.md)), and the feed fix is landed and screened ([47](47-pg-island-feed-fragility.md)). Read this for the method and the ruled-out hypotheses, not for a live question.

**Date:** 2026-08-06
**Scope:** `check_connectivity` IMPVFC-200 ("Special Wires: Pieces of the net are not
connected together") on nets VDD/VSS, design `nanosoc_eth_chiplet_pads`.
**Method:** static only — reports, logs, LEFs, Tcl. No tool was launched.

Inputs used:

| Label | File | What it is |
|---|---|---|
| `core50` | `ASIC/genus-innovus/baseline_2026-08-05/reports/nanosoc_eth_chiplet_pads_imp_connectivity.rep` | baseline run, `CORE_TO_IO 50` |
| `core70` | `ASIC/genus-innovus/reports/nanosoc_eth_chiplet_pads_imp_connectivity.rep` | today's run, `CORE_TO_IO 70` |
| `halotest` | `ASIC/genus-innovus/baseline_2026-08-05/reports/conn_halo_test.rep` | halo-removal experiment, run **uncapped** |
| `viatest` | `ASIC/genus-innovus/baseline_2026-08-05/reports/conn_via_test.rep` | narrowed via-layer-range experiment |
| logs | `ASIC/genus-innovus/logs/pnr_run_core70.log`, `baseline_2026-08-05/logs/pnr_all.log` | |

---

## 0. Headline results

1. **The `329 → 318` improvement is not real. Today's report is truncated mid-VDD.**
   The only sub-population that is complete in *both* reports is VSS, and VSS opens went
   **up**: 174 → 179. Today's true total is most likely ≈ **334**, i.e. today is slightly
   *worse* than baseline, not better by 11.
2. **85–89 % of all opens are a single, tightly-defined defect**: a 0.330 µm-wide riser
   sitting **exactly ±0.300 µm** from a macro's **left or right** edge, centred on a
   **standard-cell power rail**. 560/560 such risers across both runs contain a rail
   centre. Zero sit on a macro top/bottom edge.
3. **M5 is not where the problem is.** 0 of 560 risers align with an M5 stripe band
   alone; 100 % align with the 1.8 µm row rail grid. The defect is in the **`core_pin` /
   row-end** part of `route_special`, not the `block_pin`/M5 part.
4. **`IMPPP-570` is the direct cause message and it is capped at 20.** Every one of the
   20 printed boxes is exactly 0.330 × 0.330 µm and lands on the same x-coordinates as
   the opens. It fires during `route_special` **post-processing** ("viaGen is rebuilding
   shadow vias"), *after* sroute has already reported success.
5. **Unrelated but serious, and hidden by the same cap:** 200 signal nets have *no
   routing at all* (`IMPVFC-98`), mostly SRAM `wen`/`WEN32` bits. Invisible in both
   capped reports.

---

## 1. Report integrity — the counts are not what they look like

`check_connectivity` is invoked with no message-limit override
(`ASIC/asic-flows/Cadence/4_pnr_route.tcl:43`), so it stops at 1000 messages. It emits
per net, and within a net emits **all opens before any dangling**:

```
core50 : 174 VSS-open + 645 VSS-dangling + 155 VDD-open +  26 VDD-dangling = 1000
core70 :   2 no-route + 179 VSS-open + 680 VSS-dangling + 139 VDD-open +  0 = 1000
halotest (uncapped): 174 + 645 + 155 + 683 + 202 no-route                  = 1859
```

The summary block counts *printed* messages, not found ones — proven by `halotest`,
where the same database yields 1328 dangling instead of 671 while opens stay at 329.

**For `core50` the 329 is safe** (VDD dangling was still being printed when the cap hit,
so VDD opens had finished). **For `core70` it is not**: zero VDD dangling records were
printed, and the 1000th message is a VDD *open*
(`Net VDD: ... opens at (1058.135, 1349.400) (1058.465, 1349.800)`). The VDD open list
was therefore cut off part-way.

| | VSS opens | VDD opens | total |
|---|---|---|---|
| core50 | 174 (complete) | 155 (complete) | **329** |
| core70 | 179 (complete) | ≥139 (**truncated**) | ≥318, est. **≈334** |

Estimate basis: the VDD/VSS riser ratio is 0.841 in `core50`; applying it to `core70`'s
162 VSS risers predicts ≈136 VDD risers vs 120 printed, i.e. ≈334 total. Treat as
±10, not as a precise number.

> **The free experiment in §4 (50 vs 70) is therefore only valid on VSS.** On VSS the
> floorplan change made this defect *worse*, not better.

---

## 2. What the opens physically are

### 2.1 Two populations, one of them dominant

Every open record is a bounding box. Splitting by width:

| | 0.330 µm wide ("risers") | wider than 5 µm ("blocky") | whole-die net bbox |
|---|---|---|---|
| core50 | **278** (84.5 %) | 49 | 2 |
| core70 | **282** (88.7 %) | 34 | 2 |
| viatest | 6 | 676 | — |

(The 2 whole-die records — e.g. `VSS (175.000, 82.815) (1425.000, 1917.185)` — are the
per-net summary bbox, not a location. Real localised opens are 327 / 316.)

### 2.2 The 0.330 µm number is the standard-cell power rail width

Read `MACRO DCAP4` in `tcbn65lp_9lmT2.lef` — and any other core cell, they are all
built the same way. Its `PIN VSS` and `PIN VDD` are M1 abutment rails straddling the
row boundary, and each one measures **0.330 µm** across the row's short axis. That is
the number, and it is a property of the 9-track `core` site, not of this cell.

> Vendor LEF geometry redacted — TSMC licence forbids reproduction. Source:
> `$TSMC_65_HOME/CMOS/LP/stclib/9-track/tcbn65lp-set/.../lef/tcbn65lp_9lmT2.lef`,
> `MACRO DCAP4` and `SITE core`.

`route_special` propagates the source wire width up the stack, which is why the
riser is 0.330 µm wide **and** why the GUI fragment reported earlier (an M5 VSS
special wire 14.6 µm long and **0.33 µm tall**) has the same number — same mechanism,
horizontal leg instead of vertical.

Four rule families in the tech LEF (`PRTF_EDI_N65_<stack>_RDL.<rev>.tlef`) bite at
this width, and between them they set up the whole failure:

- **`MINIMUMCUT` on M1–M5.** A 0.33 µm wire is over the threshold, so every via
  landing on it must be a **≥2-cut array**. Dropping to a single small cut is not an
  option the router has.
- **The M2/M4 vertical track grid.** Routing tracks are on a fixed pitch and offset,
  so the riser cannot be nudged — it lands on a track or not at all. This is what
  §2.3 measures.
- **VIA1–VIA3 cut size, cut spacing and `ADJACENTCUTS`.** These decide how wide the
  2-cut array has to be.
- **Per-variant metal enclosure on the VIA12 cuts.** The enclosure differs between
  the `VIA12_1cut` and `VIA12_1cut_V` variants, which is what makes the outcome
  depend on which one viaGen happens to pick. §3.

> Vendor tech-LEF rule values redacted — TSMC licence forbids reproduction. Source:
> `$TSMC_65_HOME/CMOS/util/lef/PRTF_EDI_65nm_<rev>/PRTF_EDI_N65_<stack>_RDL.<rev>.tlef`.

### 2.3 Position: a delta function at ±0.300 µm from macro vertical edges

Macro bboxes were reconstructed from `scripts/floorplan.tcl` (`place_macro` x/y is the
**bbox lower-left**, verified against four independent `## MOVED` comments — e.g.
chip bootrom "7.00 past the new core right edge": 1237.335 + 164.665 − 1395 = 7.000)
and the LEF `SIZE` lines.

Signed offset of each riser's centre from the nearest macro left/right edge:

| offset | core50 | core70 |
|---|---|---|
| **−0.300 µm** | 132 | 148 |
| **+0.300 µm** | 146 | 134 |
| anything else | **0** | **0** |

There is no spread. Every riser is on the first vertical routing track that clears
the macro outline. Worked example, `chip_imem16k` (an rf_16k placed at 1059.2, 209.95;
adding its LEF width puts its right edge at **1371.000** in die coordinates):

```
M4/M2 tracks near the edge : ... 1370.900   1371.100   1371.300   1371.500 ...
0.33-wide riser at 1371.100 -> spans 1370.935..1371.265  -> OVERLAPS the macro
0.33-wide riser at 1371.300 -> spans 1371.135..1371.465  -> clears by 0.135 µm  <-- OBSERVED
0.33-wide riser at 1371.500 -> spans 1371.335..1371.665  -> clears by 0.335 µm
```

`1371.135` and `1371.465` are literally the numbers in both the connectivity report and
the `IMPPP-570` warnings.

**Zero risers sit on a macro top or bottom edge.** That alone rules out any
stripe-related mechanism and points at rows.

### 2.4 They are on standard-cell power rails, not on M5 stripes

Testing each riser bbox against (a) the 1.8 µm row-rail grid and (b) the M5 stripe
bands (`start_offset 8`, `set_to_set 15`, width 1, spacing 0.5):

| | overlaps rail | overlaps M5 band only | overlaps neither |
|---|---|---|---|
| core50 | 278 / 278 (**100 %**) | 0 | 0 |
| core70 | 282 / 282 (**100 %**) | 0 | 0 |

Fitting the row grid anchor (one free parameter) gives **278/278** and **282/282**
risers whose bbox *contains* a rail centre, at anchors 0.049 µm below `core_bottom`
mod 1.8 in **both** runs independently. The `y mod 15` histograms are flat — no M5
periodicity at all.

*Caveat:* the anchor was fitted rather than read from the DB. With 560 points and a
single shared parameter that lands at the same value in two independently-placed runs,
this is not a fitting artefact — but it should be confirmed against the real row grid
(see H0b).

### 2.5 The "blocky" minority is the same defect, seen sideways

The 34–49 wide records are horizontal fragments whose *right* edge lands on the riser
x-coordinate, e.g.

```
VSS (1039.900, 263.845) (1058.900, 264.955)   w = 19.000   h = 1.110
VSS (1034.500, 415.045) (1058.900, 416.220)   w = 24.400   h = 1.175
```

`1058.900` = 1059.200 − 0.300, i.e. exactly the riser centre at `chip_imem16k`'s left
edge. These are the M1/M3/M5 legs that reach the failed riser and stop. Same defect,
reported as the horizontal piece instead of the vertical one.

### 2.6 Per-macro-edge failure rate is roughly uniform, ~11 %

Total macro-edge rail-ends ≈ 2 × Σ(macro height / 1.8) ≈ **2600**. Observed failures
282 → ≈ **11 %**. Per edge it ranges 8–21 % with no obvious structure — the big rf_16k /
rf_32k / rf_08k macros dominate purely because they are tall. This is the signature of a
**marginal** geometric rule that trips on a minority of otherwise identical sites, not
of a categorical blocker.

---

## 3. The blocking geometry

Every memory macro obstructs **the entire cut stack over its whole footprint**, flush to
the `SIZE` box — verified on rf_16k, rf_08k, flash_cache_data. Reading the `OBS` sections
of those three LEFs:

- **M1, VIA1, M2, VIA2, M3, VIA3** are each blocked over the **complete** macro
  outline, with **zero overhang and zero inset** on the left and right edges. There is
  no sliver of unobstructed area anywhere along a vertical macro edge on any of them.
- **M4 is the single exception** — its blockage is inset from the left and right edges
  by **1.86 µm**, and it is the only layer left open.

> Vendor macro LEF geometry redacted — licence forbids reproduction. Source: the
> compiled-memory LEFs under `$MEM_BASE/<macro>/<macro>.lef`
> (ARM-confidential, TSMC 65 nm).

The macro PG pins are **M4, vertical, full macro height** (rf_08k: 158 VDD rects, 82 VSS
rects). M4 is the only layer left open.

So the riser must climb M1 → M2 → M3 → M4 → M5 within **0.135 µm** of a solid
VIA1/VIA2/VIA3/M1/M2/M3 blockage.

**Inferred** (not measured — flagged as inference): subtract the via's own M1 enclosure
from that 0.135 µm and the via's M1 shape stops **just short** of the M1 spacing
requirement that applies at this wire width. With the narrow-enclosure variant
(`VIA12_1cut_V`) it is short by **5 nm**; with `VIA12_1cut`, whose enclosure is larger in
x, it is short by **45 nm**. The `MINIMUMCUT` rule forbids escaping by dropping to a
single small cut. A 5 nm shortfall that depends on which via variant viaGen picks locally
is exactly consistent with the observed ~11 % scatter.

> The enclosure and spacing figures behind this arithmetic are vendor tech-LEF values and
> are not reproduced — TSMC licence. Re-derive from
> `PRTF_EDI_N65_<stack>_RDL.<rev>.tlef` if you need to re-check the 5 nm.

---

## 4. Mining the 50 → 70 comparison

The two open sets share **zero** coordinates — expected, since the core box moved 20 µm
on every side and 17 macros were re-placed. Comparison must be structural.

| metric | core50 | core70 | delta |
|---|---|---|---|
| VSS opens (complete in both) | 174 | **179** | **+5 worse** |
| VSS risers | 151 | **162** | **+11 worse** |
| VDD opens | 155 | ≥139 (truncated) | unknown |
| riser share of opens | 84.5 % | 88.7 % | — |
| offsets other than ±0.300 | 0 | 0 | unchanged |
| `ViaGen` deleted, final sroute | 1176 | 1177 | unchanged |
| `ViaGen` deleted, **M5 `add_stripes`** | **704** / 35392 VIA4 | **1042** / 36388 VIA4 | **+48 % worse** |
| DRC total | 580 | 102 | **−478** (the intended fix) |
| DRC `SHORT` | 379 | 1 | −378 (the bond-pad shorts) |

Two things fall out:

* The floorplan change did exactly what it was designed to do (DRC 580 → 102, i.e. the
  478 violations claimed, 378 of them bond-pad SHORTs) and did **nothing** to this
  defect — confirming independence.
* It made two things measurably worse: VSS opens (+5) and, more sharply, the VIA4
  deletions during the M5 `add_stripes` pass (704 → 1042, **+48 %**). That second number
  is a separate regression worth its own look; it is on M4→M5, the macro-feeding
  direction.

**The "11 disappeared" question has no answer, because the 11 did not disappear.**

---

## 5. Correlated log evidence

All of these are **capped at 20 printed messages** (`EMS-27`), so none of the counts
below are true counts.

| ID | printed | meaning | relevance |
|---|---|---|---|
| **IMPPP-570** | 20 (capped) | "detected cut layer obstruction(s) and cannot create via on the VIA1/VIA3 layer at …" | **direct cause.** All 20 boxes exactly 0.330 × 0.330. x-values 1371.135, 1058.735, 1014.335, 1034.335 … are the same x-values as the opens. |
| IMPPP-532 | 20 (capped) | "top and bottom layer have same direction but only orthogonal via is allowed between layer M4 & M8" | M8 (vertical) trying to via onto the macros' M4 (vertical) PG pins. Coordinates are macro pin columns, e.g. `(244.55, 1210.00) (244.90, 1495.25)` = tidelink rf_16k. Separate defect, same family. |
| IMPPP-531 | 20 (capped) | VIA7/VIA8 viaGen spacing failures | on the M8/M9 grid, not at macros. |
| IMPPP-4500 | 20 (capped) | "extended number of geometries between M4 and M9" | congestion, same region. |
| IMPSR-4058 | 6 | `padPinPortConnect/-padPinTarget` passed without `-connect padPin` | cosmetic; the final `route_special` passes pad-pin options it does not use. |

Sequence in `logs/pnr_run_core70.log` (final `route_special`, line 1923 onward):

```
Number of Block ports routed: 4143
Number of Core  ports routed: 4428          <- baseline says "4468  open: 2"
Number of Followpin connections: 2214
 Begin updating DB with routing results ...
route_special post-processing starts ...
The viaGen is rebuilding shadow vias for net VSS.
**WARN: (IMPPP-570): ... cannot create via on the VIA1 layer at (1020.53, 246.24) (1020.86, 246.57)
...
ViaGen created 113822 vias, deleted 1177 vias to avoid violation.
   VIA1 0 deleted | VIA2 0 | VIA3 0 | VIA4 253 | VIA5 232 | VIA6 258 | VIA7 332 | VIA8 101
```

Two important readings:

* **sroute itself reports success** (baseline: `Core ports routed: 4468  open: 2`). The
  opens are produced afterwards, in the **shadow-via rebuild**, where `IMPPP-570` fires.
  Anything that only inspects sroute's own summary will show a clean run.
* **Zero VIA1/VIA2/VIA3 were deleted.** They were never *created*. The 1177 deletions are
  all VIA4–VIA8 and belong to the upper grid, not to this defect.

---

## 6. What this is NOT

* **Not route halos.** `halotest` reproduces `core50` per net exactly (VSS 174 / VDD 155).
  The 24 records that differ do so by **30–65 nm** on the same physical sites — bbox
  jitter, not different opens. Correctly falsified. Consistent with the mechanism: the
  riser position is set by `split_row` cutting rows at the **macro bbox**, which
  `create_place_halo -halo_deltas 3.6` does not move.
* **Not the via layer range.** `viatest` at 682 destroyed the population structure
  (676 blocky, 6 risers, dangling collapsed 671 → 40): it converted dangling fragments
  into opens rather than fixing anything. Correctly falsified.
* **Not M5 / `add_stripes`.** 0/560 risers align with the M5 pitch; 100 % align with the
  1.8 µm rail grid. The earlier "M5 is where to look" lead is wrong for this population
  (though the +48 % VIA4 deletion regression in §4 is a genuine, separate M5 finding).
* **Not channels or macro spacing.** 88.7 % of opens are within 1 µm of a macro edge;
  0.9 % are more than 20 µm from any macro. Widening channels cannot help.
* **Not macro interiors or top/bottom edges.** Zero occurrences.
* **Not report truncation** for `core50` (329 is real). **It is** truncation for `core70`.

---

## 7. Ranked hypotheses

Every one predicts a number. Costs assume the experiment is run by restoring
`work/nanosoc_eth_chiplet_pads`, deleting VDD/VSS special routes, re-running the final
`route_special` and `check_connectivity` — *not* a full flow re-run.

---

### H0 — "318" is a truncation artefact (free; do this first)
**Prediction.** Re-running `check_connectivity` uncapped on today's *existing* database
gives **330–345** total opens, of which VSS = **exactly 179** and VDD = **130–170**.
Dangling will rise from 680 to >1300, and ~200 `IMPVFC-98` no-routing signal nets will
appear.
**Kill condition.** VDD opens come back as 139 → the truncation reading is wrong and
`core70` really is better.
**Test.**
```tcl
check_connectivity -error 200000 -warning 200000 \
    -out_file ../reports/conn_core70_uncapped.rep
```
**Cost.** ~1 min, no re-route. **This must be run before any other conclusion is drawn.**

---

### H0b — confirm the row grid (free, and it hardens §2.4)
**Prediction.** The real row grid places rail centres inside all 282 riser bboxes.
**Test.** `get_db rows .rect` / `get_db current_design .core_bbox`, compare against
`docs`-listed anchors; or `get_db [get_obj_in_area -area {1371.0 240 1371.6 260}] .layer`.
**Cost.** ~1 min.

---

### H1 — The riser is one routing track too close to the macro's cut blockage (PRIMARY)
**Mechanism.** `split_row` ends rows at the macro bbox; `route_special
-core_pin_target first_after_row_end` builds a 0.330 µm riser on the first vertical
track that clears the outline, at 0.300 µm centre offset = **0.135 µm** clearance to a
VIA1/VIA2/VIA3/M1/M2/M3 blockage that runs flush to the macro edge. Shadow-via rebuild
cannot legalise it, emits `IMPPP-570`, and abandons the stack.

**Prediction.** Forcing the riser out by **one track (0.200 µm)** raises the clearance to
0.335 µm and removes essentially the whole riser population:
* total opens **≤ 60** (from ≈334), VSS opens **≤ 30** (from 179);
* `IMPPP-570` count **→ 0** (check uncapped, not the 20-capped print);
* residual opens should be only the "blocky" class, ~30–50.

**Kill condition.** Opens stay above ~200, or `IMPPP-570` persists at the same
coordinates.

**Test.** Add a *routing* blockage — note this is **not** `create_place_halo`, which was
the thing already falsified — before the final `route_special` in `power_plan.tcl`:
```tcl
foreach m $::PLACED_MACROS {
    create_route_blockage -inst $m -layers {M1 M2 M3} -spacing 0.4
}
route_special -connect {block_pin core_pin floating_stripe} ...   ;# unchanged
check_connectivity -error 200000 -warning 200000 -out_file ../reports/conn_h1.rep
```
**Cost.** ~10 min on a restored DB (sroute is 1 min 57 s). ~4 h if run through the flow.
**Risk.** A blockage may make sroute abandon the connection outright instead of moving
it — which would show as opens *rising*. That is still a decisive result.

---

### H2 — The row-end connection is the wrong connection to be making
**Mechanism.** `-core_pin_target first_after_row_end` (`srouteFollowCorePinEnd 3`) is
what puts a via at a row end at all. Rails are horizontal and M5 stripes are horizontal,
so rails **never cross** M5 — they can only be fed by the vertical M8 stripes (60 µm
pitch) or at row ends. Row ends against macros are therefore ~11 % failure-prone by
construction.

**Prediction.** Changing `-core_pin_target` from `first_after_row_end` to `stripe`
removes the riser population entirely: total opens **≤ 60**, `IMPPP-570` **→ 0**, and
`Number of Core ports routed` drops by roughly the 2600 macro-edge row-ends (4428 →
~1800–2500). **IR drop will get worse** — this is a diagnostic, not necessarily a fix.

**Kill condition.** Opens do not drop below ~200 → the risers are not row-end
`core_pin` connections and §2.4 is wrong.

**Test.** In `power_plan.tcl:168`, swap `-core_pin_target first_after_row_end` for
`-core_pin_target stripe`, re-run `route_special` + uncapped `check_connectivity`.
**Cost.** ~10 min on a restored DB. Also produce `report_power_domain`/rail analysis
before adopting.

---

### H3 — `add_endcaps` DCAP4 at the split-row ends is the obstruction
**Mechanism.** `add_endcaps -start_row_cap DCAP4 -end_row_cap DCAP4` runs *after*
`add_stripes M5` and *before* `route_special`, and drops a 0.800 × 1.800 µm DCAP4 at
every row end — including the new ends `split_row` created at macro edges. The riser at
0.300 µm sits **inside** that cell's footprint.

**Assessment: weak, but cheap.** Against it: DCAP4's LEF has **no VIA1/VIA2/VIA3 OBS at
all**, only M1 OBS, and those M1 rects sit at y 0.345–1.390 (mid-cell), whereas the
risers are at the rails (y ≈ 0 / 1.8). The log also notes
`Minimum row-size in sites for endcap insertion = 9`, so short split rows get no endcap
at all — yet they fail at the same rate.

**Prediction.** Commenting out `add_endcaps` changes the open count by **less than 5 %**
(≈334 → 320–345). If it drops below 200, this hypothesis is right and H1 is wrong.
**Test.** Comment `power_plan.tcl:164`, re-run sroute + uncapped connectivity.
**Cost.** ~10 min. Run it only if H1 and H2 both fail — it is the cheapest way to
falsify the remaining structural candidate.

---

### H4 — Separate defect: M8 (vertical) cannot via onto M4 (vertical) macro PG pins
**Evidence.** `IMPPP-532` × 20 (capped), all at macro PG pin columns, e.g.
`(244.55, 1210.00) (244.90, 1495.25)` = tidelink rf_16k's M4 pins spanning its full
height. The M8 `add_stripes` pass is trying to reach the macro pins directly and cannot,
because both layers are vertical.
**Prediction.** Uncapping reveals **>200** `IMPPP-532` records, and they account for a
large share of the 680+ dangling wires (not of the 318 opens).
**Test.** `set_message_limit -id IMPPP-532 -limit 100000` (or `set_db message_limit`)
before `power_plan.tcl`, re-run. **Cost.** free if folded into any other re-run.
**Note.** This does not explain the opens. It is listed because it is the second-largest
capped message and is a genuine PG-integrity issue in its own right.

---

### H5 — Separate defect: 200 signal nets with no routing
**Evidence.** `conn_halo_test.rep` shows 202 `IMPVFC-98`, of which 2 are VDDIO/VSSIO and
**200 are signal nets** — `u_tidelink/..._u_sram_wen[7,15,23,31]`,
`u_region_dmem_0_u_sram_WEN32[0,8,16,24]`, `n_438`, … SRAM write-enable bits with no
global and no special routing.
**Prediction.** H0's uncapped rerun on today's DB reproduces ~200 of these.
**Test.** Same command as H0; then `get_db net <name> .num_wires`.
**Cost.** free (falls out of H0). **This is potentially tapeout-blocking and is
currently invisible in both shipped reports.**

---

## 8. Recommended order

1. **H0** (1 min) — get the true number before anything else. Everything downstream
   depends on whether today's total is 318 or ≈334.
2. **H5** (free, same run) — 200 unrouted signal nets outrank the PG opens in severity.
3. **H0b** (1 min) — harden the rail-grid claim.
4. **H1** (10 min) — the primary hypothesis, and the only one with a plausible fix.
5. **H2** (10 min) — diagnostic; confirms or destroys the row-end mechanism even if H1's
   particular remedy fails.
6. **H4 / H3** — only after the above.

## 9. Honest statement of what is not established

* The **exact** DRC rule that makes viaGen refuse is **inferred** from LEF arithmetic
  (0.085 µm achieved vs 0.090 µm required), not measured. The measured facts are the
  ±0.300 µm offset, the 0.330 µm width, the flush-to-edge VIA1–VIA3 macro OBS, and
  `IMPPP-570` naming VIA1/VIA3 and cut-layer obstruction.
* Why **~11 %** of macro-edge rail-ends fail while ~89 % succeed is **not explained**.
  The uniformity across macros argues for a marginal rule rather than a structural one,
  but the discriminator is unidentified. Locating the *successful* risers (in the DB or
  the GDS) and comparing their offsets against the failures would settle it — that is the
  single highest-value follow-up measurement, and it is static.
* The `core70` true total (≈334) is an **extrapolation** from the `core50` VDD/VSS ratio.
  Only H0 can turn it into a fact.
* No claim is made that fixing the risers fixes IR drop or EM. The riser population is a
  *connectivity* defect; its power-delivery significance has not been assessed.

---

*Analysis scripts (throwaway) lived in the session scratchpad; all numbers above are
reproducible from the four report files, the two logs, `scripts/floorplan.tcl`,
`scripts/power_plan.tcl`, the memory LEFs under `$MEM_BASE/`,
`ASIC/romlibs/*/`, and the tech/std-cell LEFs under
`ASIC/genus-innovus/work/nanosoc_eth_chiplet_pads/libs/lef/`.*
