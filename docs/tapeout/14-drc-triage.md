# 14 — DRC triage (2026-08-06 run) and the fill-stage ordering fix

[index](00-index.md) · [11 Known issues](11-known-issues.md) · [06 Fill, antenna, bond pads](06-fill-antenna-bondpads.md)

Two things, in the order they matter:

1. **the triage** of the 102 DRC violations that survived the 2026-08-06 P&R run, and
2. **the fill-stage ordering fix** that closes `IMPSP-9082` and `IMPSP-5217`
   ([11 h](11-known-issues.md#h-filler-runs-post-route-and-nothing-cleans-up-after-it)).

They are in that order deliberately. The ordering fix is correct and worth making, but
**it addresses at most 38 of the 102 violations and provably addresses exactly one of
them today.** The other 64 are power-grid geometry that neither `add_fillers` nor
`route_eco` can touch. Anyone who ships the fix expecting the count to collapse will be
disappointed, and that expectation is written into
[11 h](11-known-issues.md#h-filler-runs-post-route-and-nothing-cleans-up-after-it) —
"some of the 141 non-bond-pad violations may be filler-adjacent and may simply
disappear". They will not.

Sources: `reports/nanosoc_eth_chiplet_pads_imp_drc.rep`
and `logs/pnr_run_core70.log`, against
`baseline_2026-08-05/`.

---

## 0. How to count them

`grep -cE '^[A-Z]+:' report` returns **64**, not 102. `EndOfLine:` is mixed case and is
silently dropped. Use the report's own trailer, or a case-tolerant pattern:

```
grep -cE '^[A-Za-z]+:' reports/nanosoc_eth_chiplet_pads_imp_drc.rep   # 102
tail -1                reports/nanosoc_eth_chiplet_pads_imp_drc.rep   # Total Violations : 102 Viols.
```

The same trap applies to the log: `grep -c IMPSP-5217 logs/pnr_run_core70.log` returns
**4**, but there are only **2** warnings — each is followed by its own
`Type 'man IMPSP-5217' for more detail.` line. Count `WARN: (IMPSP-5217)`.

---

## 1. Headline

| | 2026-08-05 baseline | 2026-08-06 run | Δ |
|---|---:|---:|---:|
| **Total** | **580** | **102** | −478 |
| SHORT | 379 | 1 | −378 |
| SPACING | 108 | 44 | −64 |
| EndOfLine | 41 | 38 | −3 |
| MINSTEP | 28 | 10 | −18 |
| MINHOLE | 14 | 6 | −8 |
| NSMETAL | 7 | 3 | −4 |
| MINCUT | 2 | 0 | −2 |
| MINWIDTH | 1 | 0 | −1 |

The `CORE_TO_IO 50 → 70` floorplan change did what
[`floorplan.tcl`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/floorplan.tcl) predicted and more:
**376 of the baseline's 379 shorts named a `BuPAD_*` bond-pad blockage, and zero do now.**
The prediction in that header was 318; the delivered number is 376. Every other class also
roughly halved, because the whole grid was redrawn on a smaller core.

Coordinates are **not** comparable between the two runs — the core box moved and placement
was redone, so **zero** violations share a coordinate across the runs. Compare by class and
by root cause only.

### The split that decides what to do

| | count | share | who can fix it |
|---|---:|---:|---|
| `Special Wire` — power grid (`add_stripes` / `route_special`) | **64** | 63 % | [`power_plan.tcl`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/power_plan.tcl) only |
| `Regular Wire` / `Pin` — signal routing and cell pins | **38** | 37 % | `route_eco`, `add_fillers -fix_drc` |

Baseline was 457/580 (79 %) special wire. The residue is getting *more* power-grid
dominated, not less.

---

## 2. The single SHORT — name it and fix it first

```
SHORT: ( Metal Short ) Special Wire of Net VDD & Blockage of Cell
       u_nanosoc_eth_chiplet_chip_u_soc_u_soc/u_network_core/u_region_dmem_0_u_sram_u_sram_gen_rf_16k.u_rf_sp_hdf  ( M4 )
Bounds : ( 1214.490, 1624.500 ) ( 1214.705, 1625.650 )
```

A **VDD M4 special wire overlapping the M4 obstruction of the network-core DMEM 16 K
SRAM**, 1.15 µm inboard of the macro's top edge.

The geometry checks out exactly:

| | value | source |
|---|---|---|
| macro | `rf_16k`, `311.8 × 285.25` µm | `/research/precompiled_mems/TSMC65/rf_16k/rf_16k.lef` |
| placement | `place_macro {*u_network_core*u_region_dmem_0*rf_16k*} 1058.6 1340.4 MY` | [`floorplan.tcl:172`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/floorplan.tcl) |
| macro bbox | `(1058.6, 1340.4) – (1370.4, 1625.65)` | 1340.4 + 285.25 = **1625.65** |
| short | `y 1624.500 – 1625.650` | ends **on** the macro top edge |
| macro OBS | `LAYER M1 M2 M3 M4` over the footprint | `rf_16k.lef` |

It is reported twice, once as a short and once as a spacing violation, because the two
halves of the same stripe land differently:

```
SPACING: ... Special Wire of Net VDD & Blockage of Cell ...region_dmem_0...  ( M4 )
Bounds : ( 1214.330, 1624.500 ) ( 1214.485, 1625.650 )     <- 0.005 µm left of the short
```

**Root cause is not filler and not `add_stripes`.** There are no M4 stripes — `add_stripes`
draws M5, M8 and M9 only. Every M4 special wire in this design comes from the second
`route_special` in [`power_plan.tcl`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/power_plan.tcl):

```tcl
route_special -connect {block_pin core_pin floating_stripe} \
    -layer_change_range { M1(1) AP(10) } -block_pin_target nearest_target \
    -allow_jogging 1 -allow_layer_change 1 -block_pin use_lef ...
```

sroute is reaching each macro's PG **block pins**, which sit under an OBS that covers M1–M4
across the whole footprint, and its M4 approach stub abuts or overlaps that OBS. It is a
`route_special` problem and the fix belongs in `power_plan.tcl`.

> **Not fixed here.** `power_plan.tcl` is outside this change's file ownership. See §6.

---

## 3. Family A — 44 SPACING + 1 SHORT: M4 power routing into macro obstructions

45 violations, 44 % of the total. All `Special Wire`, all `ParallelRunLength Spacing`
except the one short, 43 on M4 and one on M8. **40 of them name a macro blockage by
instance** (39 SPACING plus the SHORT).

| macro instance (suffix) | viols | placement (`floorplan.tcl`) | where the violations sit |
|---|---:|---|---|
| `way1_cache_ram_data_ram_0_word_1_i` | 13 | `727.8 255.04 MX` | `y 279.45–289.76`, inside the footprint |
| `way0_cache_ram_data_ram_0_word_3_i` | 10 | `516.6 390.04 MX` | `y 424.50`, ~2 µm under the top edge |
| `way1_cache_ram_data_ram_0_word_3_i` | 6 | `564.4 435.04 MX` | `y 459.45–469.76`, inside |
| `way0_cache_ram_data_ram_0_word_2_i` | 3 | `553.8 480.4 R0` | `y 480.4–488.1`, on the bottom edge |
| `region_dmem_0` `rf_16k` | 2 | `1058.6 1340.4 MY` | top edge — **includes the SHORT** |
| `region_eth_scratch_tx_0` `rf_08k` | 2 | `1049.8 1633.8 MY` | `y 1633.80`, exactly the bottom edge |
| `way1_cache_ram_data_ram_0_word_2_i` | 1 | `633.6 527.2 R0` | `y 528.84`, just above the bottom edge |
| `way0_cache_ram_tag_ram_0_i` | 1 | `898.8 402.09 MX` | `y 402.09`, exactly the bottom edge |
| `way1_cache_ram_tag_ram_0_i` | 1 | `911.2 468.69 MX` | `y 468.69`, exactly the bottom edge |
| `u_shared_sram_0` `rf_08k` | 1 | `1052.4 506.71 R180` | `y 506.71`, exactly the bottom edge |

**Clustering: 35 of the 45 are inside the QSPI flash-cache macro stack**, the bbox
`x 656.3–994.6, y 279.4–536.2`. That is the block `floorplan.tcl` describes as moving "up
as one rigid block ... a 45 µm pitch with only 8.64 µm between them". The violation
y-coordinates land on macro edges to three decimal places, which is the signature of
`route_special` stopping at a block pin rather than of anything random.

The remaining 5 name no macro:

| | bounds | layer | note |
|---|---|---|---|
| VDD vs **VSS** | `(899.795, 244.500)–(899.930, 248.100)` | M4 | **supply-to-supply, 0.135 µm** |
| VSS vs **VDD** | `(740.055, 458.040)–(740.195, 471.400)` | M4 | **supply-to-supply, 0.140 µm** |
| VDD vs **VSS** | `(689.805, 480.400)–(689.945, 488.100)` | M4 | **supply-to-supply, 0.140 µm** |
| VDD (single object) | `(721.040, 527.135)–(721.050, 527.200)` | M4 | 0.010 µm sliver |
| VDD (single object) | `(1188.955, 191.000)–(1190.450, 203.000)` | M8 | **the only violation outside the core box** |

The three VDD-against-VSS M4 spacings are the same severity class as the short — a
sub-spec gap between opposite supplies — and should be triaged with it, not with the
macro-abutment cases. Treat them as four near/actual PG shorts, not one.

The M8 one at `y 191.000–203.000` sits in the **inner bottom core ring**
(core edge 205, `add_rings -offset 2 -width 12` ⇒ 191–203). Everything else in the report
is inside the core box `(205,205)–(1395,1795)`.

**Verdict: not fixable by fill or ECO route.** These wires are created at floorplan time,
before placement, before routing and before any filler exists. `route_eco` does not touch
special wires; `add_fillers -fix_drc` repairs filler cells only.

---

## 4. Family B — 38 EndOfLine on M1: the only class the ordering fix can reach

All 38 are `EndOfLine Spacing`, all on **M1**, and 35 of the 38 are the identical
`0.090 × 0.100` µm footprint — the standard-cell pin-access geometry, not a routing
blow-out. 37 are `Regular Wire of Net … & Pin of Cell …`; **one is `Pin & Pin`.**

Spread across the core (`x 459–1192`, `y 610–1394`), nowhere near the pad ring, and
grouped by the block that owns the net:

| owning block | viols |
|---|---:|
| d2d PHC `seconds[…]` / `nanoseconds[…]` bus | 10 |
| TideLink (servo, `xhb_sub`, `chiplet_controller/axil2apb`) | 10 |
| TideChart `apb_regs_cost_rf_r[…][…]` | 9 |
| `u_soc` misc | 4 |
| QSPI flash controller | 3 |
| network core | 1 |
| DMAC | 1 |

Baseline had 41 of exactly this class. **38 vs 41 across a floorplan change is a flat
line**, which is the important negative result: this family is not filler fallout, it is a
standing pin-access congestion signature in three register-file-shaped blocks. Do not
expect `route_eco -target` to clear it — `-target` only works on nets NanoRoute has marked
as ECO nets, and 37 of these nets are untouched by fill.

### The one that IS filler's fault — and the one `-fix_drc` exists for

```
EndOfLine: ( EndOfLine Spacing )
  Pin of Cell u_nanosoc_eth_chiplet_chip_u_soc_u_soc/FILLER_PD_TOP_T_14_3927
& Pin of Cell u_nanosoc_eth_chiplet_chip_u_soc_u_tidelink/g72197  ( M1 )
Bounds : ( 484.860, 873.210 ) ( 484.950, 873.310 )
```

Both objects are **cell pins**, one of them a filler instance. `man add_fillers` on
`-fix_drc`: *"Corrects DRC violations reported by `verify_drc` **between filler cells and
adjacent standard cells**."* This is that, verbatim.

It is in the baseline too, same shape, different filler and different neighbour:

```
2026-08-05  FILLER_PD_TOP_T_12_6626 & u_tidelink/u_chiplet_controller/g258041
            @ ( 344.860, 540.010 )
```

**One violation, in both runs, of exactly the class the disabled `-fix_drc` pass was
supposed to repair.** That is the entire measurable payload of Gap 1 — and it is a real
payload, because it is the only violation in this report that is unambiguously created by
the fill stage.

---

## 5. Family C — 19 power-grid geometry defects

| class | count | layers | net | shape |
|---|---:|---|---|---|
| MINSTEP | 10 | M5 ×9, M4 ×1 | VDD ×7, VSS ×3 | notches `0.010–0.090 × 0.015–0.090` µm |
| MINHOLE | 6 | M5 | VDD | enclosed holes `0.230–0.480 × 0.325–0.835` µm |
| NSMETAL | 3 | M6 ×2, M7 ×1 | VDD ×2, VSS ×1 | overlaps `0.055–0.100 × 0.060–0.095` µm |

All `Special Wire`. All sub-0.1 µm artefacts, i.e. residue rather than structure.

They pair up, which tells you where they come from:

- MINSTEP `(866.310, 291.400)` and `(866.310, 291.175)` — same x, 0.225 µm apart.
- MINSTEP `(903.110, 246.465)` and `(903.110, 246.120)`; `(701.705, 433.115)` and
  `(701.705, 432.765)`; `(564.600, 426.465)` and `(564.600, 426.120)` — three more pairs.
- MINHOLE `(1050.925, 1745.965)` and `(1360.245, 1745.965)` — same y, 309 µm apart;
  `(1060.325, 367.165)` and `(1369.645, 367.165)` — same y again.
- NSMETAL `(964.475, 368.040)` M7 and `(964.450, 368.040)` M6 — **one physical via stack,
  flagged on two layers.**

Same-y pairs at 309 µm spacing on M5 are stripe-to-stripe repeats; same-x pairs a fraction
of a micron apart are the two sides of one jog. Both point at the M5 stripe pass:

```tcl
add_stripes -nets {VDD VSS} -layer M5 -direction horizontal -width 1 -spacing 0.5 \
    -set_to_set_distance 15 -max_same_layer_jog_length 2 -merge_stripes_value 500 \
    -switch_layer_over_obs false ...
set_db add_stripes_extend_to_closest_target {ring stripe}
```

`-max_same_layer_jog_length 2` with `-merge_stripes_value 500` and
`extend_to_closest_target` is a jog-and-merge recipe, and jogs plus merges on a 1 µm wire
are exactly what produces sub-minimum steps and enclosed holes at the junctions. The three
NSMETAL are the M6/M7 legs of the M1→AP stacked vias at those same junctions.

Baseline had 28 + 14 + 7 = 49 of these against today's 19. The class did not change
character, only quantity, with the grid.

**Verdict: not fixable by fill or ECO route.** `power_plan.tcl`.

---

## 6. What to change, and where

Ordered by violations closed per unit of risk.

| # | change | file | closes | status |
|---|---|---|---|---|
| 1 | keep `route_special` off macro M4 obstructions | `power_plan.tcl` | up to **45** (Family A, incl. the SHORT) | **not made** — outside this change's ownership |
| 2 | tame the M5 jog/merge geometry | `power_plan.tcl` | up to **19** (Family C) | **not made** — same reason |
| 3 | make `-fix_drc` real; add `route_eco` | `filler.tcl`, `place_bondpads.tcl` | **1** measured, up to 38 in scope | **made**, §7 |

### Requested changes to files not owned here

**(a) `power_plan.tcl` — the M4 sroute stubs (Family A, 45 violations).** The second
`route_special -connect {block_pin core_pin floating_stripe}` uses `-block_pin use_lef` and
`-block_pin_target nearest_target`, and its M4 approach to each macro's PG block pin lands
on the macro's own M1–M4 OBS. Options, in increasing order of intrusiveness — **all
unverified, none run**:

- constrain the sroute layer range so macro block pins are reached from above M4 rather
  than on M4 (`-layer_change_range` / `-crossover_via_layer_range` currently
  `M1(1) AP(10)`);
- give the macros a block ring on a layer the OBS does not cover, so sroute has a legal
  target;
- widen `create_place_halo -halo_deltas {3.6 3.6 3.6 3.6}`
  ([`floorplan.tcl`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/floorplan.tcl)) — but note the QSPI
  stack has only 8.64 µm between macros, so there is very little room.

Do **not** simply re-enable `add_stripes_ignore_block_check` reasoning here: it is already
`false` for the M5 pass and the M4 wires are not stripes.

**(b) `power_plan.tcl` — M5 jog residue (Family C, 19 violations).** Try
`-max_same_layer_jog_length` and the merge value; measure, do not guess.

**(c) Out of scope but seen while reading the log — `check_connectivity` is truncated.**
The 2026-08-06 run reports `1000 total info(s) created` and
`**WARN: (IMPVFC-3): Verify Connectivity stopped: Number of errors exceeds the limit 1000`
— 318 `IMPVFC-200` PG opens + 680 `IMPVFC-94` dangling wires + 2 `IMPVFC-98`. **The true
count is unknown, not 1000.** [11 a](11-known-issues.md#a-329-pg-opens-reported-by-check_connectivity)
quotes 329 opens from the baseline under the same truncation. Re-run with `-limit` raised
before treating either number as a measurement.

---

## 7. The ordering fix (Gaps 1 and 2)

### What was wrong

[`filler.tcl`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/filler.tcl) inserted 102,760 filler
instances into a fully routed design and stopped. Innovus objected twice per run and was
ignored twice per run:

```
**WARN: (IMPSP-5217): add_fillers command is running on a postRoute database.
        It is recommended to be followed by eco_route -target command to make the DRC clean.
**WARN: (IMPSP-9082): verifyGeometry needs to be executed before -fixDRC option could be
        used. If verifyGeometry has been executed, then there is no DRC violation to fix.
```

`add_fillers -fix_drc` reads the violation-marker database. The flow's only `check_drc`
runs in [`4_pnr_route.tcl`](https://github.com/SoC-Labs/ASIC-Flow/blob/b19e7845448e641ea8353b19a59a77257907cb13/Cadence/4_pnr_route.tcl) **after**
`place_bondpads.tcl` returns. So the marker database was empty when `-fix_drc` executed,
on both runs, and the line did nothing.

The two messages ask for **two different repairs**, and each tool can only do one
(`man add_fillers`):

> *"This command resolves only filler-related violations; it cannot resolve net-based
> violations. To repair net-based violations, reroute the violated net(s)."*

| violation | repaired by | precondition |
|---|---|---|
| filler cell vs adjacent **cell** | `add_fillers -fix_drc` | markers must exist |
| filler cell vs **net** routing | `route_eco` | a router pass |

### Stylus spelling — verified, not guessed

Both message texts use legacy-UI names. The installed Innovus 21.11 reference carries both
spellings in separate manuals, which settles it:

| message says | Stylus command | evidence |
|---|---|---|
| `verifyGeometry` / `verify_drc` | **`check_drc`** | `doc/innovusTCR/verify_drc.html` (legacy) vs `doc/TCRcom/check_drc.html` (Stylus Common UI); `check_drc` "creates violation markers in the design database" |
| `eco_route` | **`route_eco`** | `doc/innovusTCR/ecoRoute.html` (legacy) vs `doc/TCRcom/route_eco.html` (Stylus Common UI) |

`route_eco -target` is documented as *"Enables NanoRoute to work on only eco nets
identified by NanoRoute to route. In this mode, the router ignores the already existing DRC
violation markers that are not on the ECO nets."* `-target`, `-fix_drc` and `-prototype`
are **mutually exclusive** in `route_eco`'s synopsis; do not combine them. `-target` is
both Cadence's recommendation in IMPSP-5217 and the conservative choice — it will not go
re-routing the 64 power-grid markers `check_drc` has just written.

### The new order

Made in [`filler.tcl`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/filler.tcl). The two new lines are
marked:

```tcl
add_filler_gaps 0.2 -effort high

# pass 1 — insert. -check_drc true is filler-vs-ROUTING only:
# "It does not check versus adjacent cells."
add_fillers -base_cells [list FILL64 FILL32 FILL16 FILL8 FILL4 FILL2 FILL1 ANTENNA] \
    -prefix FILLER -fill_gap -merge true -check_drc true

add_filler_gaps 0.2 -effort high
check_filler > check_filler.log                                   # pre-repair snapshot

check_drc -out_file $REPORT_DIR/${block_name}_imp_drc_prerepair.rep   # NEW — closes IMPSP-9082

# pass 2 — repair, now non-inert
add_fillers -base_cells [list FILL64 FILL32 FILL16 FILL8 FILL4 FILL2 FILL1 ANTENNA] \
    -prefix FILLER -check_drc true -fix_drc

route_eco -target                                                 # NEW — closes IMPSP-5217
```

Four decisions worth recording:

1. **`check_drc` goes *between* the two `add_fillers` passes, not before both.** The
   violations `-fix_drc` repairs are the ones pass 1 creates; marking before pass 1 would
   mark nothing useful. `man add_fillers`: *"Use this parameter in subsequent runs of the
   `add_fillers` command, after adding filler cells and checking for violations with
   `verify_drc`."*
2. **It writes to `${block_name}_imp_drc_prerepair.rep`.** `${block_name}_imp_drc.rep` is
   the signoff report and belongs to `4_pnr_route.tcl`. Do not clobber it from here.
3. **No final `check_drc` was added.** `4_pnr_route.tcl` already runs one after
   `place_bondpads.tcl` returns; it will simply now describe the repaired database. Same
   for `check_filler`.
4. **`filler.tcl` stays sourced before the bond-pad loops** in
   [`place_bondpads.tcl`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/place_bondpads.tcl). That keeps
   the marker set core-only. Move it below the pad loops and the repair passes would be
   handed a database dominated by M8/M9/AP pad-ring geometry they cannot touch — the class
   that was 376 of 379 shorts in the baseline. A note to that effect has been added to the
   `place_bondpads.tcl` header, alongside the existing one.

The existing ordering rationale in `place_bondpads.tcl` and `route_setup.tcl` is
**unchanged and still correct**. Filler still runs post-route. Nothing moves back before
`route_design`.

### Cost

`check_drc` on this design is **22 s elapsed / 2:12 CPU on 8 threads**
(`*** End Verify DRC (CPU: 0:02:12 ELAPSED TIME: 22.00 …) ***`). Against a 4.5-hour run
that is free. It is deliberately **not** scoped with `-check_only`: narrowing the check
risks failing to mark the very violations `-fix_drc` needs, which is the bug being fixed.
`route_eco` runtime on this design is unmeasured.

### What could not be verified

No Innovus seat was available (licence-constrained, and one seat stuck) and the task
forbade launching the tool. Everything above is from the installed 21.11 command
reference and the two run logs. Specifically unverified:

- **`route_eco -target` actually running here.** The option is documented and spelled
  correctly, but `route_eco`'s own reference says *"You must first run the `place_eco`
  command before you use this command"* — written for the netlist-ECO flow, where
  `eco_read_def` leaves cells unplaced. `add_fillers` leaves nothing unplaced, so
  `place_eco` should be unnecessary, but that is reasoning, not evidence. **Run
  `route_eco -help` on the first available seat.** Until then the call is wrapped in a
  `catch` that prints four `ERROR:` lines and lets the run finish rather than losing the
  bond pads, the stream and every report; a comment in `filler.tcl` says to delete the
  `catch` once one run has proven the command. A caught error in a signoff flow is a
  temporary measure, not a design.
- **How many of the 38 M1 EndOfLine `route_eco -target` will close.** Predicted: very few,
  because `-target` restricts itself to ECO nets and 37 of the 38 are on nets fill never
  touched. Predicted floor: the one `Pin & Pin` filler violation, which `add_fillers
  -fix_drc` should take instead.
- **Whether `-fix_drc` finds a legal swap.** *"If it cannot replace a violating filler cell
  without causing another violation, it leaves a gap."* A gap is an acceptable outcome and
  a *visible* one — diff `work/check_filler.log` (pre-repair) against
  `reports/…_imp_filler.rep` (post-repair, written by the flow). Today both report
  `Total number of gaps found: 0`.
- **`add_fillers -check_different_cells true`** would prevent the filler-vs-neighbour
  violation instead of repairing it. The option is real (`man add_fillers`, default
  `false`, *"Using this feature will increase the runtime"*), but changing pass 1 changes
  the fill itself, so it was **not** enabled. Consider it only after the repair path has
  been proven on one run.
- **`setFillerMode -enableLeglizer false`**, offered by `man IMPSP-5217` as an alternative,
  is a legacy-UI command with no counterpart in the Stylus `add_fillers` attribute list.
  It also only *silences* the warning. Not pursued.

### How to tell it worked

On the next run, in order:

1. `grep -c 'WARN: (IMPSP-9082)' logs/…` → **0** (was 1).
2. `grep -c 'WARN: (IMPSP-5217)' logs/…` → still **2**. That warning fires *at*
   `add_fillers`, before `route_eco` runs; it is expected to persist and is not a
   regression.
3. `grep -c FILLER_PD_TOP reports/…_imp_drc.rep` → **0** (was 1).
4. `diff` the violation counts of `…_imp_drc_prerepair.rep` and `…_imp_drc.rep`. The
   difference is the repair's entire measured yield. **Expect it to be small.**
5. Total still ≈ 100. That is Families A and C, and it is a `power_plan.tcl` problem.
