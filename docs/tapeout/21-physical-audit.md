# 21 — Physical implementation audit: floorplan, PG, vias, rows, fill, pad ring

**Scope.** Everything physical that the DRC and connectivity *reports* do not capture but
the *logs* do. Sources are the completed `CORE_TO_IO 70` run
(`baseline_2026-08-06/logs/pnr_run_core70.log`, 119,859 lines), the previous floorplan
(`baseline_2026-08-05/logs/pnr_all.log`), the full 08-06 report set, and the
floorplan/power/fill/bondpad scripts.

**What this page does not re-litigate.** The 350 PG opens and the 0.330 µm riser at
±0.300 µm from macro edges are [15](15-pg-opens-analysis.md). The 424-master GDS merge
hole is [00 §3](00-index.md) and [`scripts/07`](scripts/07-filler-and-bondpads.md §6). The
unrouted `VDDIO`/`VSSIO` nets are [16 §4](16-open-defects.md). The Calibre
`GDSFILENAME`-not-`$GDSFILENAME` abort is [12](12-calibre-drc.md). Absent metal fill is
[00](00-index.md). Where this page touches those, it is adding a *number* they do not
have.

---

## 0. Method, and one correction to the premise

Innovus echoes every sourced script line as `@file NNN:`. All counts below are taken from
a stream filtered with `grep -vE '^@file [0-9]+:'`, and message-ID counts are of
`**WARN: (ID)` / `**ERROR: (ID)` lines, never of raw ID occurrences.

**`IMPPP-570` fires 20 times, not 41.** The brief for this audit says 41×. That is the
same double-count trap `filler.tcl`'s header documents for `IMPSP-5217`: every warning is
followed by its own `Type 'man IMPPP-570' for more detail.` line, plus one `EMS-27`
mentioning the ID.

```
WARN lines: 20      man lines: 20      EMS-27 lines: 1      raw grep -c: 41
```

[15 §5](15-pg-opens-analysis.md) already has this right (`20 (capped)`). The true
underlying count is unknown from the log — which is the point of §3 below.

**Eleven message classes are truncated at 20 in this run.** All `EMS-27` lines:

```
IMPLF-119   IMPLF-223   IMPPP-532   IMPPP-531   IMPPP-4500  IMPPP-570
IMPESI-3086 IMPCCOPT-2406 IMPCCOPT-2169 IMPCCOPT-2171 IMPCCOPT-2332
IMPESI-3095 IMPOGDS-4004 IMPOGDS-217
```

Four of those (`IMPPP-531/532/570/4500`) are power-grid via failures. Nothing in the flow
calls `set_message -no_limit`; `grep -rn set_message` over `scripts/` and `asic-flows/`
returns nothing.

---

## 1. VERIFIED findings, ranked by risk to silicon

### P1 — Core `VSS` enters the die on 4 bond pads; `VDD` on 6; neither rail has a single pad on the left or right edge

This is a pin-map property, not a P&R one, and it is not recorded anywhere in `docs/`.

From `scripts/nanosoc_eth_chiplet_pads.io`, the complete set of *core* supply pads:

```
top    : uPAD_VDD_T_0  uPAD_VDD_T_1  uPAD_VDD_T_2    uPAD_VSS_T_0  uPAD_VSS_T_1
bottom : uPAD_VDD_B_0  uPAD_VDD_B_1  uPAD_VDD_B_2    uPAD_VSS_B_0  uPAD_VSS_B_1
left   : (none)
right  : (none)
```

VDD 6, VSS 4. The left and right sides carry only `VDDIO`/`VSSIO` (6 each). The tool's own
pad-ring routing reproduces the ratio exactly, in **both** runs:

```
routeSelectNet set to "VDD"      Number of IO ports routed: 120   Pad Ring connections: 30
routeSelectNet set to "VSS"      Number of IO ports routed:  56   Pad Ring connections: 20
```

30:20 = 6:4. VSS also gets the narrower riser — `power_plan.tcl` uses
`-pad_pin_width 1.63` for VDD and `1.5` for VSS.

**Why this is P1.** 188,797 standard cells on a 1600×2000 die, all core current entering
and returning through the top and bottom edges only. The left edge is where TideLink's
`phy_gpio` sits (86,959 µm², the largest single leaf block in the area report), and it is
the furthest point from any core supply pad. `check_connectivity` also finds *more* VSS
opens than VDD opens (179 vs 171) on the rail that has fewer pads.

**No IR-drop analysis has ever been run on this design** ([09 item 19](09-signoff-checklist.md)),
so the margin is not merely unknown — it is unmeasured on the rail with the 33 % deficit.

**Confirming experiment.** None needed for the arithmetic; it is the `.io` file. The
decision needed is a pin-map one. If a seat is available, `report_power_domain` /
`analyze_rail` on the final DB would put a number on it; failing that, the cheap
diagnostic is total VIA8 count per rail into the pad ring — already in the log at 60
(VDD) vs 28 (VSS).

---

### P2 — The whole core PG grid reaches top metal through **8 RV vias and 5 AP shapes**, and that dropped 14 → 8 between the two runs

`RV` is the M9→AP via in `PRTF_EDI_N65_<stack>_RDL`. Every ViaGen table in both runs,
`RV`/`AP` rows only:

| pass | 08-05 RV created/deleted | 08-05 AP | 08-06 RV created/deleted | 08-06 AP |
|---|---|---|---|---|
| M8 `add_stripes` | 5 / 0 | 3 | **7 / 0** | **4** |
| final `route_special` | 10 / 1 | 2 | **2 / 1** | **1** |
| **net total** | **14** | **5** | **8** | **5** |

Independently confirmed by the stream-out inventory, which reconciles *exactly* against
the per-pass tables for the upper layers:

```
Special Nets                       16257
    metal layer M7                    51      = 41 (sroute) + 6 (VDD pad) + 4 (VSS pad)
    metal layer M8                    51      = 41 (M8 stripes) + 4 (ring) + 6 (sroute)
    metal layer M9                    59      = 52 (M9 stripes) + 4 (ring) + 1 (M8 pass) + 2 (sroute)
    metal layer AP                     5      =  4 (M8 pass) + 1 (sroute)
```

(M1 6611 = 6523+60+28, M2 506 = 418+60+28, M3 116 = 106+6+4 — all exact. Only M4/M5/M6
differ, by 3/10/8 shapes.)

**Why this matters.** AP is the layer the bond pads live on. Eight RV vias is the
narrowest point in the entire supply path, it is a 43 % reduction from the previous
floorplan, and nothing in the flow checks it — `check_connectivity` reports opens and
dangling wires, not via-count-per-layer.

**Confirming experiment** (~1 min, needs a seat, read-only on the final DB):

```tcl
read_db nanosoc_eth_chiplet_pads
foreach n {VDD VSS} {
  puts "$n RV: [llength [get_db [get_db nets $n .special_vias] -if {.via_def.bottom_layer.name == RV}]]"
  puts "$n AP: [llength [get_db [get_db nets $n .special_wires] -if {.layer.name == AP}]]"
}
```

**Predicts** RV = 8 total across both nets, AP = 5 total. If it returns 14/5 the tables
are being misread and P2 is dead.

---

### P3 — 446 of 9,013 M4→M9 via stacks never reach M9. This is the true, uncapped count of the `IMPPP-531` class

[15 §5](15-pg-opens-analysis.md) records `IMPPP-531` as "20 (capped) … VIA7/VIA8 viaGen
spacing failures" with no count. **The count is in the log, uncapped, in the ViaGen table
of the same `add_stripes` call.** M9 `add_stripes`, verbatim:

```
                                   08-06                          08-05
add_stripes created 52 wires.                    add_stripes created 54 wires.
ViaGen created 44235 vias, deleted 0             ViaGen created 46953 vias, deleted 0
+--------+----------------+---------+            +--------+----------------+---------+
|  VIA4  |      9013      |    0    |            |  VIA4  |      9575      |    0    |
|  VIA5  |      9013      |    0    |            |  VIA5  |      9575      |    0    |
|  VIA6  |      9013      |    0    |            |  VIA6  |      9575      |    0    |
|  VIA7  |      8629      |    0    |            |  VIA7  |      9200      |    0    |
|  VIA8  |      8567      |    0    |            |  VIA8  |      9028      |    0    |
```

`Deleted` is 0 on every row, so the VIA7/VIA8 shortfall is not deletion — it is **failure
to generate**, which is exactly what `IMPPP-531` reports, and all 20 printed `IMPPP-531`
lines fall inside this `add_stripes` block (log lines 1685–1786).

| | 08-05 | 08-06 |
|---|---|---|
| stacks started (VIA4=VIA5=VIA6) | 9,575 | 9,013 |
| fail at VIA7 (M7→M8) | 375 (3.92 %) | **384 (4.26 %)** |
| further fail at VIA8 (M8→M9) | 172 (1.80 %) | 62 (0.72 %) |
| **never reach M9** | **547 (5.71 %)** | **446 (4.95 %)** |
| per M9 stripe | 10.13 | 8.58 |
| VIA7 failures per M9 stripe | 6.94 | **7.38 (+6.3 %)** |

Each of those 446 is a PG column that climbs from M4 and dead-ends at M6 or M7 — metal
that costs area and capacitance and delivers nothing. The absolute total improved with the
smaller core, but **the VIA7 failure rate got worse in both relative and per-stripe terms**,
which no one has noticed because the message is capped at 20.

**Confirming experiment** (~5 min from the post-floorplan DB):

```tcl
set_message -no_limit -id {IMPPP-531 IMPPP-532 IMPPP-570 IMPPP-4500}
source ../scripts/power_plan.tcl
```

**Predicts** exactly **446** `**WARN: (IMPPP-531)` lines between `Begin add_stripes` and
`End add_stripes` of the M9 pass, of which **384 name VIA7** and **62 name VIA8**.
**Kill condition:** any other total means the ViaGen table deficit and `IMPPP-531` are
different populations, and the table needs re-interpreting before it is quoted again.

---

### P4 — 1,518 dangling PG wires, uncapped. 4.3× the 350 opens, and never triaged

`reports/conn_uncapped.rep` (the run that produced the 350 figure) also contains:

```
Begin Summary
    2 Problem(s) (IMPVFC-98): Net has no global routing and no special routing.
    350 Problem(s) (IMPVFC-200): Special Wires: Pieces of the net are not connected together.
    1518 Problem(s) (IMPVFC-94): The net has dangling wire(s).
    1870 total info(s) created.
End Summary
```

838 VDD + 680 VSS. The signoff report
(`nanosoc_eth_chiplet_pads_imp_connectivity.rep`) caps at 1,000 and shows 680, which is
where every previous count came from. **The real magnitude of this defect is 1,868 markers,
not 350.**

Layer histogram — new, and it changes the diagnosis:

| layer | VDD | VSS | total |
|---|---|---|---|
| M2 | 306 | 328 | **634** |
| M1 | 243 | 223 | **466** |
| M5 | 239 | 108 | **347** |
| M3 | 31 | 21 | 52 |
| M7 | 9 | 0 | 9 |
| M8 | 6 | 0 | 6 |
| M6 | 2 | 0 | 2 |
| M4 | 2 | 0 | 2 |

**76 % (1,152) are on M1/M2/M3** — the standard-cell-level risers built by the final
`route_special -connect {block_pin core_pin floating_stripe} … -block_pin use_lef`, not by
`add_stripes`.

Position: only **72 distinct x-values** across all 1,518 records, and every high-frequency
one is exactly ±0.300 µm from a macro's *vertical* edge. Cross-checked against
`floorplan.tcl` placements and the LEF `SIZE` lines:

| x | count | macro edge |
|---|---|---|
| 230.300 | 123 | tidelink `rf_16k` left = 230.600 |
| 290.500 | 122 | net imem `rf_32k` left = 290.800 |
| 1058.900 | 113 | chip imem `rf_16k` left = 1059.200 |
| 1371.300 | 106 | chip imem `rf_16k` right = 1059.200+311.8 = 1371.000 |
| 1058.300 | 103 | net dmem `rf_16k` left = 1058.600 |
| 1370.700 | 94 | net dmem `rf_16k` right = 1058.600+311.8 = 1370.400 |
| 1362.500 | 71 | chip dmem `rf_08k` right = 1050.400+311.8 = 1362.200 |
| 542.700 | 66 | tidelink `rf_16k` right = 230.600+311.8 = 542.400 |
| 589.900 | 53 | eth scratch rx left = 590.200 |
| 1231.500 | 21 | ethmac `rf_01k` right = 1053.800+177.4 = 1231.200 |

Same signature as the opens in [15 §2.3](15-pg-opens-analysis.md) — **one defect, and the
dangling population is the larger half of it.** Any fix proposed in [15 §7](15-pg-opens-analysis.md)
must be scored against 1,868, not 350, or it will look better than it is.

**Confirming experiment.** Free — it is already in the report. What is *worth* running is
the uncapped check on the 08-05 database, which was never done:

```tcl
read_db <core50 db>
check_connectivity -type special -error 200000 -warning 200000 -out_file ../reports/conn_uncapped_core50.rep
```

**Predicts** dangling in the 1,300–1,400 range (the 08-05 `conn_halo_test.rep`, taken at a
different flow stage on the same floorplan, shows 1,328). If it comes back near 1,518 the
CORE_TO_IO change is neutral on this defect; if it comes back materially lower, the macro
re-place made it worse and that belongs in [03](03-floorplan.md).

---

### P5 — The M5 stripe grid fragmented by +34.8 % on a *smaller* core. This is the mechanism behind the unexplained +48 % VIA4 deletion regression

[15 §4](15-pg-opens-analysis.md) records "704 → 1042 VIA4 deletions, **+48 % worse**" as
"a genuine, separate M5 finding" with no cause. The cause is in the same two lines of log.

M5 `add_stripes`, both runs:

```
08-05:  add_stripes created 1044 wires.   ViaGen created 41685 vias, deleted  704 vias
        | VIA4 | 35392 | 704 |  | M5 | 1044 |  | VIA5 | 2107 |  | VIA6 | 2093 |  | VIA7 | 2093 |

08-06:  add_stripes created 1407 wires.   ViaGen created 42745 vias, deleted 1042 vias
        | VIA4 | 36388 | 1042 |  | M5 | 1407 |  | VIA5 | 2119 |  | VIA6 | 2119 |  | VIA7 | 2119 |
```

| | 08-05 | 08-06 | Δ |
|---|---|---|---|
| core height | 1630 µm | 1590 µm | −2.5 % |
| M5 stripe rows (`start_offset 8`, pitch 15, ×2 nets) | 218 | 212 | −2.8 % |
| **M5 wire segments** | **1,044** | **1,407** | **+34.8 %** |
| fragments per stripe | 4.79 | **6.64** | **+38.6 %** |
| VIA4 attempted (created+deleted) | 36,096 | 37,430 | +3.7 % |
| VIA4 deletion rate | 1.950 % | **2.784 %** | **+42.8 %** |
| up-vias (VIA7) per M5 fragment | 2.005 | **1.506** | **−24.9 %** |

The core got smaller and the stripe grid got *more* fragmented. `power_plan.tcl` L154 sets
`add_stripes_ignore_block_check false` for this pass only, so every M5 stripe is cut into
segments at macro boundaries, and each segment must then find its own way up via
`-extend_to_closest_target {ring stripe}`. Fragment count is therefore a function of where
the 15 µm stripe grid lands *relative to macro top/bottom edges* — and both moved:

* the grid moved +20 µm (core bottom 185→205; `-start_from bottom -start_offset 8`), and
  20 mod 15 = **5**, so the grid shifted 5 µm in phase;
* 17 of 21 macros moved by −20, −15, −10, +6 or +20 µm — none a multiple of 15.

The consequence that matters: **each M5 fragment now has 1.51 connections upward instead
of 2.01**, and 347 of the 1,407 fragments (24.7 %) carry a dangling end (P4's M5 row). The
1,042 deleted VIA4s are downward links lost on top of that.

**Confirming experiment — cheap and decisive** (`add_stripes` on this design is 7 s):
from a post-`split_row` DB, sweep the M5 stripe phase and record two numbers per point.

```tcl
foreach off {0 1 2 3 4 5 6 7 8 9 10 11 12 13 14} {
    # ... restore DB, re-issue power_plan.tcl L159 with -start_offset $off ...
    # record "add_stripes created N wires" and "deleted D vias"
}
```

`-start_offset 3` is the interesting point: `205 + 3 + 15k = 208 + 15k`, which is a subset
of the 08-05 grid `185 + 8 + 15k = 193 + 15k`. It puts the M5 stripes back on the exact
absolute y-coordinates the previous run used, so the four macros that did *not* move see
an identical phase.

**Predicts:** N varies by more than 20 % across the sweep with a clear minimum, D tracks N
(correlation > 0.8), and at `-start_offset 3` N ≲ 1,270 and D ≲ 900.
**Kill condition:** N stays within ±2 % of 1,407 at every offset → phase is irrelevant, the
fragmentation is caused by the macro y-moves alone, and the lever is
`floorplan.tcl`'s coordinates rather than the stripe offset.

---

### P6 — The M8 grid makes **zero** connection to macro M4 PG pins, and in 08-06 the M8 pass created no VIA7 at all

`IMPPP-532` ×20 (capped), verbatim, all inside the M8 `add_stripes` block:

```
**WARN: (IMPPP-532): ViaGen Warning: The top layer and bottom layer have same direction
  but only orthogonal via is allowed between layer M4 & M8 at (244.55, 1210.00) (244.90, 1495.25).
```

The y-range `1210.00 … 1495.25` is precisely the tidelink `rf_16k` — placed at 230.6, 1210.0,
and its LEF height carries the top edge to 1495.25. `1503.40 … 1788.68` is the net imem
`rf_32k`, placed at 290.8, 1503.4, the same way. (Macro dimensions not reproduced —
vendor LEF, licence.) The x-values 244.55/246.30, 305.10/307.55,
365.30/367.76, 425.55/426.55 sit on the 60 µm M8 set pitch (244.5, 304.5, 364.5, 424.5).
So: **every M8 vertical stripe column that crosses a macro's M4 vertical PG pin.**

The ViaGen table corroborates it — the M8 `add_stripes` pass has **no VIA4 row at all**,
and 08-06 lost the two VIA7 that 08-05 managed:

```
08-05  | M7 | 1 | VIA7 | 2 | 0 | M8 | 42 | VIA8 | 81 | 4 | M9 | 1 | RV | 5 | AP | 3 |
08-06  |                        | M8 | 41 | VIA8 | 81 | 1 | M9 | 1 | RV | 7 | AP | 4 |
```

**Consequence.** The M8 grid cannot feed the macros. The M5 grid cannot either — P5's pass
runs with `ignore_block_check false`, so M5 stripes stop *at* macro boundaries rather than
crossing them. **Macro supply therefore depends entirely on the final
`route_special -connect {block_pin …} -block_pin use_lef` pass — the same pass whose risers
produce the 1,868 opens-plus-dangling markers of P4.** That is a single point of failure
for 21 memory macros, and it is not stated in that form anywhere in `docs/`.

**Confirming experiment.** Uncap `IMPPP-532` as in P3 and replay `power_plan.tcl`. The
count equals the number of (M8 stripe column × macro M4 pin) overlaps. The invariant to
assert is stronger than the count: **the M8 `add_stripes` ViaGen table must continue to
show no VIA4 row.** If a fix ever produces VIA4 > 0 there, the M8→macro path exists.

---

### P7 — Signal routing is unconstrained on M8/M9; NanoRoute put 35,937 µm of signal wire on the vertical PG stripe layer

`grep -rniE 'top_routing_layer|bottom_routing_layer|max_route_layer'` over
`asic-flows/Cadence/*.tcl` and `genus-innovus/scripts/*.tcl` returns **nothing**.
`route_setup.tcl` sets multi-cut effort, timing-driven and SI-driven, and no layer range.

```
#Total wire length on LAYER M8 = 35937 um.
#Total wire length on LAYER M9 = 1679 um.
#Total wire length on LAYER AP = 0 um.
```

M8 carries the 41 vertical PG stripes and the left/right core rings; M9 carries the 52
horizontal stripes and the top/bottom rings; and M8/M9 are the two layers the staggered
bond pads blanket with solid `OBS` (`floorplan.tcl` header). Routing signals there is what
`CORE_TO_IO 70` was raised to make room for.

**Risk.** Post-route DRC is clean today (`#Total number of DRC violations = 0` from
NanoRoute; 102 from `check_drc`, 64 of them Special Wire). But nothing *constrains* this —
the next netlist change can put more signal on M8/M9, into the same band that produced 318
PG-ring shorts at margin 50, with no guard rail.

**Confirming experiment / fix.** Add to `route_setup.tcl`:

```tcl
set_db route_design_top_routing_layer 7
```

**Predicts** M8 and M9 signal wire length → 0 µm, total wire length up by roughly the
37,616 µm currently on M8+M9 plus detour (estimate < 0.5 % of the 9,371,010 µm total), and
`check_drc` Special Wire count unchanged at 64. **Kill condition:** routing fails to
converge or DRC rises — in which case M7 is genuinely needed and the limit belongs at 8
with M9 reserved.

---

### P8 — `power_plan.tcl` L166 is a complete no-op, in both runs

```
routeSelectNet set to "VDD VSS"
  Number of IO ports routed: 0
  Number of Pad ports routed: 0
route_special created 0 wire.
ViaGen created 0 via, deleted 0 via to avoid violation.
```

That is the third `route_special -connect {pad_pin pad_ring} … -pad_pin_width 6` call.
`sroutePreserveExistingRoutes` is `true` and the two earlier per-net calls (widths 1.63 and
1.5) already routed everything, so the width-6 call has nothing to do. It is harmless, but
anyone reading the script will believe the pad connections are 6 µm wide. **They are 1.63 µm
(VDD) and 1.5 µm (VSS)** — which is also the mechanism behind P1's rail asymmetry.

---

### P9 — Endcap coverage fell by 23 row-ends, and all six endcap slots resolve to the same `DCAP4`

```
08-05:  Inserted 2246 pre-endcap <DCAP4> cells      Inserted 2246 post-endcap <DCAP4> cells
08-06:  Inserted 2223 pre-endcap <DCAP4> cells      Inserted 2223 post-endcap <DCAP4> cells
```

```
**WARN: (IMPSP-5534): 'add_endcaps_left_edge' and 'add_endcaps_right_edge' are using the same endcap cells
**WARN: (IMPSP-5534): 'add_endcaps_left_bottom_corner' and 'add_endcaps_right_bottom_corner' are using the same endcap cells
**WARN: (IMPSP-5534): 'add_endcaps_left_top_corner' and 'add_endcaps_right_top_corner' are using the same endcap cells
**WARN: (IMPSP-5224): Option '-preCap' for command add_endcaps is obsolete …
**WARN: (IMPSP-5224): Option '-postcap' for command add_endcaps is obsolete …
```

`power_plan.tcl` passes only `-start_row_cap DCAP4 -end_row_cap DCAP4`, so Innovus fills
the four corner slots with the same cell. `Minimum row-size in sites for endcap insertion = 9`
means any row fragment shorter than 9 sites (1.8 µm) gets **no endcap at all** — and
`split_row` on 21 macros plus the new macro positions is what produced 23 fewer of them.

**Assessment: low risk, but unquantified.** `tcbn65lp` is a self-tapping library (P12) so
the endcaps here are decoupling/edge-fill, not well-tie continuity. The 46 missing cells
are 46 row-ends with no `DCAP4`.

The total is already confirmed in the log, immediately after `add_endcaps`:

```
1858: For 4446 new insts, *** Applied 6 GNC rules
```

2223 + 2223 = 4446 ✓. What is *not* known is which row-ends went bare.
**Confirming experiment** (free, on the final DB): `get_db rows` and count rows whose
start or end has no `ENDCAP_*` abutting — **predicts 46**, i.e. 23 rows losing both ends
or 46 losing one.

---

### P10 — `floorplan.tcl`'s utilisation numbers are wrong, and understate the cost of `CORE_TO_IO 70`

The header says the change cost "5.6 % area loss" and utilisation "89.5 % → 92.2 %". The
log says:

```
08-05:  Density for the design = 0.727.   Placement Density: 72.72% (851826/1171312)
08-06:  Density for the design = 0.807.   Placement Density: 80.67% (851826/1055913)
```

The 5.6 % is the *core box* shrink (1230×1630 → 1190×1590). The **placeable-site** loss is
1,171,312 → 1,055,913 sites = **−9.85 %**, because the macro re-placement also consumed
rows. Utilisation went 72.72 % → 80.67 %, not 89.5 % → 92.2 %. Documentation defect, not a
silicon one, but it is the number anyone will use to decide whether there is room for the
next change.

---

### P11 — The signoff filler report contains no gap count

`reports/nanosoc_eth_chiplet_pads_imp_filler.rep`, in full after the header:

```
Checking Power Domain: PD_TOP
```

That is the *post-repair* report, written by `4_pnr_route.tcl` after
`add_fillers -fix_drc`, and `filler.tcl`'s header calls it "the authoritative post-repair
one". It states no number. The *pre*-repair snapshot does:

```
work/check_filler.log:
*INFO: Total number of padded cell violations: 0
*INFO: Total number of gaps found: 0
```

`add_fillers -fix_drc` is documented to "leave a gap" when it cannot substitute a legal
filler, so the one measurement that would show whether it did is the one not captured.

**Confirming experiment.** Change `4_pnr_route.tcl` to `check_filler > <file>` (redirect,
not `-out_file`), or run `check_filler` at the prompt on the final DB.
**Predicts 0 gaps** — the M1 EndOfLine violation `filler.tcl` names
(`FILLER_PD_TOP_T_14_3927` & `u_tidelink/g72197` @ 484.860, 873.210) is still in the 08-06
DRC report, which means `-fix_drc` left the filler in place rather than removing it. A
non-zero result would be the first evidence that the 2026-08-06 `-fix_drc` change did
anything.

---

### P12 — Row / site integrity: clean, and the "missing well taps" question is closed

Recorded so nobody chases it again.

* **There are no tap cells, and there cannot be.** `grep -icE 'welltap|tapcell|well_tap|FILLTIE|latchup'`
  over the log returns **0**, and the reason is the library. Enumerate every filler-class
  master in `tcbn65lp_9lmT2.lef` (`grep -oE '^MACRO (FILL[A-Z0-9]*|.*TAP.*|.*TIE.*|ANTENNA[A-Z0-9]*|DCAP[0-9]*)' … | sort -u`)
  and you get exactly three families — the `FILL*` fillers, the `DCAP*` decaps, the one
  `ANTENNA` diode — plus the `TIEH`/`TIEL`/`GTIEH`/`GTIEL` logic tie-offs. **No tap or
  well-tie master of any name.** `tcbn65lp` 9-track is a self-tapping library. `TIEH`/`TIEL`
  are logic tie-offs (28 TIEL + 17 TIEH placed by `postplace.tcl`), not substrate ties.
* **Placement is legal and rows are intact.** `*info: Placed = 188863 (Fixed = 4467) / Unplaced = 0`.
  The 4,446 endcaps plus 21 macros account for the fixed count. One placement-blockage
  violation was found and repaired during clock refine (a single `LNQD1` moved 2.20 µm).
* **`split_row` ran on all 21 macros** — `power_plan.tcl` now consumes `::PLACED_MACROS`
  and asserts `llength == 21`; no `IMPTCM-165` appears in this log.
* **`IMPFP-3961` ×33** ("techSite `corner` / `pad` / `dcore` has no related standard cells")
  is benign: those SITEs are all declared in the tech LEF, on their own dimensions, and this
  design instantiates only `core`. Nothing is missing. (Site dimensions not reproduced —
  vendor tech LEF, licence.)
* Unexplained: the sroute reader says **`Read in 22 blockages`** in both runs, against
  21 `create_place_halo` halos. Cheap check: `get_db place_blockages` +
  `get_db route_blockages` on the post-floorplan DB. Predicts 21 place halos + 1 other; if
  the 22nd is a route blockage nobody created, it wants explaining.

---

### P13 — IO ring: VERIFIED CLOSED on all four sides, with zero residual gap

[16 §4](16-open-defects.md) says the abutment-continuity argument for `VDDIO`/`VSSIO` is
"not established". **It can be established from arithmetic**, and it checks out exactly.

`add_io_fillers` results, and the cell widths (20/10/5/1/0.5/0.005 µm):

| side | ×20 | ×10 | ×5 | ×1 | filler total | pads | pad width | pads + filler |
|---|---|---|---|---|---|---|---|---|
| top | 32 | 18 | 17 | 0 | 905.0 | 17 | 25 | 425 + 905 = **1330** |
| bottom | 32 | 18 | 17 | 0 | 905.0 | 17 | 25 | 425 + 905 = **1330** |
| left | 50 | 2 | 2 | 50 | 1080.0 | 26 | 25 | 650 + 1080 = **1730** |
| right | 42 | 23 | 22 | 0 | 1180.0 | 22 | 25 | 550 + 1180 = **1730** |

Die 1600×2000, four `PCORNER_G` at 135 µm:

* top/bottom available = 1600 − 2×135 = **1330** ✓
* left/right available = 2000 − 2×135 = **1730** ✓

Pad width 25 µm is the tool's own figure (`IMPCCOPT-2406`: *"Physical cell width =
'25.000um' and height = '135.000um'"*). The per-gap decomposition also closes: top/bottom/right
gaps are `space=55` = 2×20 + 10 + 5; left gaps are the global `space=42` = 2×20 + 2×1;
each side's leftover 25 µm (30 µm on the left) is the two end gaps set by `offset=150`
(150 − 135 = 15 = 10+5).

**`PFILLER05_G` and `PFILLER0005_G` added 0 on every side** — the ring is exactly full,
to 5 nm resolution. There is no gap for the `VDDPST`/`VSSPST` abutment bus to fall through.

**The one asymmetry**, undeclared: the left side omits `space=55` and so inherits the
global `space=42`. Left pads are on a 67 µm pitch; top/bottom/right on 80 µm. It closes
correctly, but it is an accident of the generator template, not a decision — and the left
side is the TideLink PHY side.

---

### P14 — Bond-pad ring: VERIFIED complete, and the stagger alternates perfectly

Cross-checking `place_bondpads.tcl`'s eight lists against the `.io` order, per side:

| side | `.io` pads | outer+inner | O/I alternation |
|---|---|---|---|
| top | 17 | 9 + 8 | O I O I O I O I O I O I O I O I O ✓ |
| left | 26 | 13 + 13 | O I × 13 ✓ |
| bottom | 17 | 9 + 8 | O I O I O I O I O I O I O I O I O ✓ |
| right | 22 | 11 + 11 | O I × 11 ✓ |

**82 of 82 IO drivers get a bond pad; no pad is listed twice; no pad is missed; the
outer/inner alternation is exact on all four sides.** Corroborated by the sroute reader:
`407 pad components: 325 placed, 82 fixed` (325 = 156+61+58+50 fillers, 82 = drivers) plus
`4 other components: 4 fixed` (the corners).

No overlap risk: `PAD70GU`/`PAD70NU` are 30 µm along the ring direction against a 67 µm
(left) or 80 µm (other sides) driver pitch.

---

## 2. SUSPECTED — plausible, not established

### S1 — The 1,868 riser markers may be starving the macros, not merely wasting metal

**What is established:** P6 (M8 cannot reach macro M4 pins), P5 (M5 stops at macro
boundaries), P4 (76 % of dangling wires are M1/M2/M3 risers at ±0.300 µm from macro
edges), and `Number of Block ports routed: 4143` (08-06) vs `4163` (08-05).

**What is not:** whether the surviving connections are sufficient. The riser population is
a *fraction* of block-port connections, not all of them, and 4,143 ports were reported
routed. [15 §2.6](15-pg-opens-analysis.md) puts the per-macro-edge failure rate at ~11 %,
which would leave ~89 % intact.

**Cheapest decisive test:** for one macro, dump the special wires actually touching its PG
pins and count them against the LEF pin count.

```tcl
set m [get_db insts *u_tidelink*u_rf]
foreach p [get_db $m .pg_pins] { puts "[get_db $p .name] : [llength [get_db $p .net.special_wires]]" }
```

If any macro PG pin resolves to zero special wires, S1 is promoted to a P1-class defect. If
every pin has ≥ 1, the risers are waste and EM/IR degradation only.

### S2 — The 08-06 dangling regression may be a `CORE_TO_IO` cost

08-05 has no uncapped connectivity report at the same flow stage, so 1,518 cannot be
compared. The two 08-05 experiment reports are at a *different* stage (both carry 202
`IMPVFC-98`, i.e. pre-signal-route) and disagree with each other (1,328 vs 40 dangling).
See P4's experiment. Until that runs, "the opens got worse, 329 → 350" is the only
defensible cross-run statement, and it is a 6 % change on a capped-vs-uncapped comparison
that [15 §1](15-pg-opens-analysis.md) already flags as unsafe.

### S3 — `-unit 1000` rounding on the stream-out

```
**WARN: (IMPOGDS-250): Specified unit is smaller than the one in db. You may have rounding problems
```

`write_stream … -unit 1000` writes 1 nm resolution. The database carries sub-nanometre
coordinates — the DRC report has bounds like `(1214.490, 1624.500) (1214.705, 1625.650)`
and `IMPPP-570` prints `(1020.534973, 246.235001)`. Every geometry is snapped on the way
out. On a design whose smallest IO filler is 5 nm wide this is probably immaterial, but it
is unquantified, it is a signoff stream, and no one has diffed streamed geometry against
the DB. Cheapest check: stream a second GDS with `-unit 2000` and compare file size and
`Stream Out Information Processed` shape counts. Predicts identical shape counts; a
difference means shapes are merging under rounding.

---

## 3. Checked and found sound

Recorded to stop them being re-investigated.

| Area | Result | Evidence |
|---|---|---|
| Antenna | Genuinely clean | `No Violations Found`; 41,217 `ANTENNA` diodes inserted; `MACRO ANTENNA` carries an `ANTENNADIFFAREA` value on pin `I` (figure not reproduced — vendor LEF). The `IMPLF-200` warning about missing `ANTENNAGATEAREA` on that pin is benign — a diode has no gate. |
| Filler insertion | 102,760 cells, 0 gaps, 0 padded-cell violations at the pre-repair snapshot | `work/check_filler.log` |
| Well taps / latch-up | Not applicable — library ships no tap cell | P12 |
| Row legality | 188,863 placed, 0 unplaced, 1 blockage violation auto-repaired | log 22,138 / 24,397 |
| IO filler ring | Closed exactly, all four sides, no residual | P13 |
| Bond-pad ordering | 82/82, perfect stagger | P14 |
| Special-net shape accounting | Reconciles exactly against the stream-out inventory on M1, M2, M3, M7, M8, M9, AP | P2 |
| Multi-cut vias | 39.3 % of 2,482,746 signal vias | log 33,294 |

---

## 4. Experiment queue, cheapest first

| # | Experiment | Cost | Predicts | Kills |
|---|---|---|---|---|
| 1 | `get_db` RV/AP counts on final DB (P2) | 1 min | RV = 8, AP = 5 | ≠ 8 → tables misread |
| 2 | `get_db rows`, count bare row-ends (P9) | 5 min | 46 bare ends | — |
| 3 | `get_db place_blockages` / `route_blockages` (P12) | 1 min | 21 + 1 | — |
| 4 | Macro PG-pin special-wire count, one macro (S1) | 5 min | ≥ 1 per pin | 0 on any pin → promote S1 |
| 5 | `set_message -no_limit`, replay `power_plan.tcl` (P3, P6) | 5 min | **446** `IMPPP-531`: 384 VIA7 + 62 VIA8 | ≠ 446 → re-interpret ViaGen tables |
| 6 | M5 `-start_offset` sweep 0…14 (P5) | 15 × 7 s | N spans > 20 %; at offset 3, N ≲ 1,270 and D ≲ 900 | N flat ±2 % → cause is macro moves, not phase |
| 7 | `check_filler` redirected, post-repair (P11) | 5 min | 0 gaps | > 0 → first evidence `-fix_drc` acted |
| 8 | Uncapped `check_connectivity` on the core50 DB (P4/S2) | 20 min | dangling 1,300–1,400 | ≈ 1,518 → CORE_TO_IO neutral |
| 9 | `route_design_top_routing_layer 7`, re-route (P7) | ~2 h | M8/M9 signal → 0 µm; wirelength +< 0.5 %; Special Wire DRC still 64 | DRC rises → M7 limit too tight |
| 10 | `-unit 2000` second stream (S3) | 10 min | identical shape counts | difference → rounding merges shapes |

Experiments 1–5 and 7 are read-only or replay-only and do not disturb a live P&R seat's
database. 6 needs a post-`split_row` snapshot. 9 is the only one that costs a full route.

---

## 5. One-line summary for the index

The pad ring and the bond ring are sound; the row grid is sound; there are no missing tap
cells because the library has none. The unexamined risks are all in the **supply path**:
core VSS enters on four pads and neither core rail has a pad on the left or right edge; the
whole PG grid reaches top metal through eight RV vias, down from fourteen; 446 M4→M9 via
stacks dead-end below M9; the M8 grid cannot touch a single macro PG pin; and the
riser defect that everyone has been counting as "350 opens" is really 1,868 markers.
