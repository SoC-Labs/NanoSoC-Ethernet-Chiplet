# The 330 instances with no supply path: what they are, and why the gate is right

**Date: 2026-08-18. Verdict: REAL. Not an extraction artefact.**
**Severity: 55 functional cells with no metal supply path, on every build in the
tree including the shipping one. Cause is understood, fix is a P&R change.**

This closes the one HARD failure holding `ASIC/genus-innovus/rail/work/fp1505/verdict.json`
at `FAIL_HARD`: `pg.disconnected = 330`. It answers the five questions that were
asked of it — what, where, real-or-artefact, other builds, silicon — and it names
the fix and the stage that has to re-run.

Method note: everything below is arithmetic over artefacts already on disk.
**No P&R run was launched, no database was modified, no threshold was edited, and
no EDA licence was taken.** The one tool-run result quoted (the Voltus solve) is
the existing `fp1505` run from 2026-08-17 23:26.

---

## 0. The answer in five lines

1. **What:** 275 physical-only cells (DCAP4 / FILL* / ANTENNA) and **55 functional
   cells** — 30 clock/buffer cells, 4 flip-flops, 21 combinational gates — almost
   all in the QSPI flash cache, two in the ethernet scratch-TX path.
2. **Where:** five sites, all of them **narrow standard-cell row islands cut by
   `split_row` around three SRAM macros**. Not scattered: **53 row segments, every
   one of them 100% disconnected.**
3. **Real or artefact: REAL.** Innovus `check_connectivity -type special`
   independently reports PG opens whose boxes contain **100.0% (330/330)** of them.
   Three controls below refute the artefact hypotheses.
4. **Other builds:** the same five sites, at the same coordinates, on **six
   databases** spanning two floorplans, two M5 offsets and five days. The *count*
   moves (466 → 330); the *geometry* does not.
5. **Silicon: yes, on the current shipping build.** `full-20260814` carries
   **328** stranded instances, 55 of them functional, measured by a predictor
   validated exactly against Voltus on `fp1505`.

---

## 1. WHAT they are

From `results/PD_TOP_125C_avg_1/Reports/VDD_VSS_div.iv`, the 330 rows whose
`PWR_IVD` or `GND_IVB` field is `NA`.

| | count | note |
|---|---|---|
| `DCAP4` (used as `ENDCAP_PD_TOP_*`) | 106 | decap that decouples nothing |
| `FILL1/2/4/8/16/32/64` | 133 | inert |
| `ANTENNA` | 36 | antenna diodes that do not protect |
| **functional cells** | **55** | **these do not power up** |

Split by net: **87 have no VDD path, 176 no VSS path, 67 have neither.**
(No row has `DIVD = NA` with both rails numeric, on either database examined, so
the gate's `NA in f[1:-1]` test counts exactly "no path to VDD or no path to VSS"
and is not inflated by the derived column.)

The 55 functional cells are **30 buffer/clock-buffer cells** (CKBD0/1/2 ×25,
CKND1/CKND2D1 ×2, BUFFD1/D6 ×3), **4 flip-flops** (DFCNQD1 ×3, DFCNQD4 ×1) and
**21 combinational gates**.

> **Correction to `32-ir-drop-stage.md` §2b**, which says "26 clock buffers … and
> 25 combinational gates". The counts are **30** and **21**. The totals (55, 275,
> 330) and the site table there are correct.

### The 55, by name

| x | y | master | lost | instance |
|---|---|---|---|---|
| 881.4 | 439.0 | `AO222D1` | VSS | `g90538` |
| 883.8 | 439.0 | `DFCNQD1` | VSS | `QSPI$CTL$reg_early_rdata_mux_reg[31]` |
| 888.2 | 439.0 | `BUFFD1` | VSS | `FE_PHC15648_QSPI$RAMCLD0WDATA_121` |
| 889.6 | 439.0 | `AO221D2` | VSS | `g107986` |
| 892.0 | 439.0 | `AO221D2` | VSS | `g107984` |
| 883.4 | 440.8 | `CKBD2` | VSS | `FE_PHC16046_QSPI$RAMTAG0ADDR_0` |
| 884.6 | 440.8 | `CKBD2` | VSS | `FE_PHC13281_QSPI$RAMTAG0ADDR_4` |
| 885.8 | 440.8 | `CKBD2` | VSS | `FE_PHC11576_QSPI$RAMTAG0ADDR_4` |
| 887.0 | 440.8 | `CKBD2` | VSS | `FE_PHC11575_QSPI$RAMTAG0ADDR_2` |
| 888.2 | 440.8 | `AO221D2` | VSS | `g107985` |
| 890.6 | 440.8 | `NR2D2` | VSS | `g108226` |
| 892.0 | 440.8 | `AO221D2` | VSS | `g107983` |
| 870.0 | 489.4 | `CKBD1` | VSS | `FE_OFC2370_QSPI$RAMCLD0WDATA_80` |
| 870.8 | 489.4 | `BUFFD1` | VSS | `FE_PHC9884_QSPI$RAMCLD0WDATA_104` |
| 871.6 | 489.4 | `CKBD1` | VSS | `FE_PHC15600_FE_OFN2370_QSPI$RAMCLD0WDATA_80` |
| 872.4 | 489.4 | `DFCNQD1` | VSS | `QSPI$CTL$reg_linefill_buf_reg[80]` |
| 876.8 | 489.4 | `CKBD1` | VSS | `FE_PHC12230_QSPI$RAMCLD0WDATA_89` |
| 877.6 | 489.4 | `CKBD1` | VSS | `FE_PHC12210_QSPI$RAMCLD0WDATA_95` |
| 878.4 | 489.4 | `CKBD1` | VSS | `FE_PHC11995_QSPI$RAMCLD0WDATA_88` |
| 879.6 | 489.4 | `AOI22D1` | VSS | `g87800` |
| 881.0 | 489.4 | `CKBD1` | VSS | `FE_PHC12202_QSPI$RAMCLD0WDATA_94` |
| 881.8 | 489.4 | `CKBD1` | VSS | `FE_PHC13519_QSPI$RAMCLD0WDATA_94` |
| 883.0 | 489.4 | `AN2XD1` | VSS | `g87761` |
| 884.6 | 489.4 | `CKBD1` | VSS | `FE_PHC12172_QSPI$RAMCLD0WDATA_92` |
| 885.4 | 489.4 | `AO221D0` | VSS | `g87867` |
| 887.8 | 489.4 | `CKND1` | VSS | `g40562` |
| 888.4 | 489.4 | `AO211D2` | VSS | `g87864` |
| 890.2 | 489.4 | `MOAI22D1` | VSS | `g192005` |
| 891.8 | 489.4 | `CKBD1` | VSS | `FE_PHC12150_QSPI$RAMCLD0WDATA_91` |
| 892.6 | 489.4 | `CKBD1` | VSS | `FE_PHC13484_QSPI$RAMCLD0WDATA_91` |
| 893.4 | 489.4 | `DFCNQD1` | VSS | `QSPI$CTL$rd_hit_dphase_prefetching_miss_reg` |
| 897.8 | 489.4 | `CKBD0` | VSS | `FE_PHC12931_QSPI$CTL$line_fill_aphase` |
| 899.6 | 489.4 | `CKBD0` | VSS | `FE_PHC11567_n_103035` |
| 900.4 | 489.4 | `CKBD0` | VSS | `FE_PHC15944_QSPI$CTL$line_fill_aphase` |
| 901.6 | 489.4 | `INR4D0` | VSS | `g190670` |
| 903.2 | 489.4 | `CKND2D1` | VSS | `g112120` |
| 905.0 | 489.4 | `ND2D2` | VSS | `g107945` |
| 870.4 | 491.2 | `AO222D1` | VSS | `g87986` |
| 872.8 | 491.2 | `AO22D0` | VSS | `g87972` |
| 874.8 | 491.2 | `CKBD1` | VSS | `FE_PHC13546_QSPI$RAMCLD0WDATA_93` |
| 876.6 | 491.2 | `CKBD1` | VSS | `FE_PHC15711_QSPI$RAMCLD0WDATA_120` |
| 877.4 | 491.2 | `CKBD1` | VSS | `FE_PHC13690_QSPI$RAMCLD0WDATA_89` |
| 878.2 | 491.2 | `CKBD1` | VSS | `FE_PHC13489_QSPI$RAMCLD0WDATA_95` |
| 881.6 | 491.2 | `AOI222D0` | VSS | `g87909` |
| 884.2 | 491.2 | `CKBD1` | VSS | `FE_PHC13517_QSPI$RAMCLD0WDATA_92` |
| 885.0 | 491.2 | `CKBD1` | VSS | `FE_PHC12181_QSPI$RAMCLD0WDATA_90` |
| 885.8 | 491.2 | `CKBD1` | VSS | `FE_OFC6857_QSPI$RAMTAG1ADDR_0` |
| 887.2 | 491.2 | `INVD1` | VSS | `FE_OFC2316_n_84887` |
| 887.8 | 491.2 | `ND2D3` | VSS | `g87760` |
| 890.0 | 491.2 | `BUFFD6` | VSS | `FE_OFC7202_n_84925` |
| 893.4 | 491.2 | `DFCNQD4` | VSS | `QSPI$CTL$line_fill_aphase_delayed_reg` |
| 901.6 | 491.2 | `AOI22D1` | VSS | `g193951` |
| 905.2 | 491.2 | `INVD2` | VSS | `g111205` |
| 1053.4 | 1546.0 | `CKBD0` | VDD+VSS | `u_network_core/FE_PHC11618_u_region_eth_scratch_tx_0_u_sram_wdata_30` |
| 1053.0 | 1547.8 | `OAI21D1` | VDD | `u_network_core/g436171` |

`QSPI$` abbreviates
`u_qspi_flash_0_u_top_ahb_qspi_u_cache_subsystem_`, `CTL$` abbreviates
`u_cache_controller_u_p_flash_cache_f0_core_`, and every instance is under
`u_nanosoc_eth_chiplet_chip_u_soc_u_soc/`.

**What that list is, functionally.** The `FE_PHC*_QSPI$RAMCLD0WDATA_*` and
`FE_PHC*_QSPI$RAMTAG*ADDR_*` cells are placement-driven buffers on the QSPI flash
cache's **RAM write-data and tag-address busses**; the four flops are cache
controller state (`CTL$reg_early_rdata_mux_reg[31]`, `CTL$reg_linefill_buf_reg[80]`,
`CTL$rd_hit_dphase_prefetching_miss_reg`, `CTL$line_fill_aphase_delayed_reg`). The
two at y≈1546 are on the **ethernet scratch-TX SRAM write path**. If these cells
do not switch, the QSPI flash cache mis-addresses and mis-writes its tag and data
RAMs. That is the external-flash boot path.

---

## 2. WHERE they are — and why it is exactly there

### 2a. Five sites, and they are row islands

Single-linkage clustering at 40 µm over `inst_xy.txt`:

| site | x | y | instances | functional |
|---|---|---|---|---|
| A | 1034.2 – 1054.8 | 352.6 – 493.0 | 158 | 0 |
| D | 869.2 – 906.8 | 489.4 – 491.2 | 76 | **41** |
| B | 1051.8 – 1054.2 | 1544.2 – 1592.8 | 44 | **2** |
| C | 1043.2 – 1054.8 | 262.6 – 280.6 | 30 | 0 |
| D′ | 879.8 – 894.4 | 439.0 – 440.8 | 22 | **12** |

Read those x-extents against the **`DefRow:` records in the database's own
floorplan file** (`work/nanosoc_eth_chiplet_pads_routed/nanosoc_eth_chiplet_pads.fp.gz`):

| row y | row segments at that y |
|---|---|
| 262.6 | `[205.0, 724.2]` `[1043.2, 1055.6]` `[1374.6, 1395.0]` |
| 352.6 | `[205.0, 715.2]` `[1034.2, 1055.6]` `[1374.6, 1395.0]` |
| 439.0 | `[205.0, 560.8]` `[879.8, 895.2]` `[1037.8, 1055.6]` `[1374.6, 1395.0]` |
| 489.4 | `[205.0, 550.2]` `[869.2, 907.6]` `[1050.2, 1055.6]` `[1374.6, 1395.0]` |
| 1544.2 | `[205.0, 287.2]` `[1051.8, 1055.0]` `[1374.0, 1395.0]` |

**Every site is a row segment, to 0.1 µm.** These are the slivers `split_row
-selected` (`power_plan.tcl:198`) leaves between macro halos. Site B's island is
**3.2 µm wide** — a couple of cell widths — and 39 rows tall.

The macros bounding them are named in the same file, and the arithmetic closes on
the project's own 3.6 µm `InstHalo`:

| island right edge | + halo | macro at that x |
|---|---|---|
| 1055.6 | 1059.2 | `u_chip_core_u_region_imem_0_…rf_16k…` @ (1059.20, 209.95) |
| 1055.0 | 1058.6 | `u_network_core/u_region_dmem_0_…rf_16k…` @ (1058.60, 1340.40) |
| 907.6 | 911.2 | `…u_way1_cache_ram_tag_ram_0_i` @ (911.20, 468.69) |
| 895.2 | 898.8 | `…u_way0_cache_ram_tag_ram_0_i` @ (898.80, 402.09) |

### 2b. The signature that decides everything: 53 rows, all 100%

Assigning every one of the 351,211 placed instances to its `DefRow` segment:

```
        island        rows with a disconnected cell : 53
        rows where SOME cells are disconnected      :  0
```

**Not one row is mixed.** Where a row is affected, every cell on it is affected.
That is what an isolated M1 follow-pin rail segment looks like and nothing else
does.

The VDD/VSS split is likewise geometric, not random. Taking site B's island
`[1051.8, 1055.0]`, three consecutive rows:

| row | orient | loses |
|---|---|---|
| 1544.2 | FS | VSS |
| 1546.0 | N | VDD **and** VSS |
| 1547.8 | FS | VDD |

Standard-cell rows abut on shared rails at a 1.8 µm pitch. The unique solution is
that **exactly two rails are broken — VSS at y = 1546.0 and VDD at y = 1547.8** —
and those three rows are the three that touch them. An extraction artefact does
not respect the library's rail-sharing geometry.

### 2c. Cross-reference to the four rail-to-rail shorts

`32-macro-placement-pg-short-window.md` records the four VDD–VSS M5 shorts at
**x = 844.500 → 912.900, y = 1546.600 / 1561.600 / 1576.600 / 1591.600**, from the
network bootrom `rom_via` at (883.535, 1538.600). **Site B occupies y 1544.2 –
1592.8** — the same four-stripe band of the same `split_row` region, one macro to
the east. They are two symptoms of one mechanism: the M5 ladder re-anchored per
row region. `fp1505` closes the shorts (by phase luck, per `36-…`) and does *not*
close this.

---

## 3. IS IT REAL — three controls, and an independent tool

This is the question the brief said decides everything, so it is answered by
measurement in four independent ways, not by argument.

### 3a. A second tool, on the same database, agrees instance-for-instance

`build/fp1505/reports/nanosoc_eth_chiplet_pads_conn_{VDD,VSS}.rep` —
Innovus `check_connectivity -type special`, run at 21:28 by the P&R flow, two
hours before the rail solve and with no knowledge of it — reports **35 VDD + 29
VSS `IMPVFC-200`** "pieces of the net are not connected together", each with a
bounding box.

```
  no-VDD-path instances within 5 µm of a localised IMPVFC-200 VDD box : 154 / 154  (100.0%)
  no-VSS-path instances within 5 µm of a localised IMPVFC-200 VSS box : 243 / 243  (100.0%)
```

And the boxes are *the island rails themselves*. Four examples, verbatim:

```
  VSS  865.735  490.505   45.165 x 1.390   <- site D  island [869.2, 907.6]
  VSS  876.335  440.210   22.330 x 1.390   <- site D' island [879.8, 895.2]
  VDD 1030.735  368.800   28.330 x 2.530   <- site A  island [1034.2, 1055.6]
  VDD 1048.335 1547.070   10.130 x 1.460   <- site B  island [1051.8, 1055.0]
```

**37 of the 62 localised opens strand cells — 34 rail-class boxes and 3 of the
0.330 µm risers — and 25 strand nobody** (risers and stripe fragments of
`15-pg-opens-analysis.md`, in wide rows where the rail is fed from elsewhere). That asymmetry is itself the
mechanism: *one failed riser is harmless on a 500 µm row and fatal on a 3.2 µm island.*

### 3b. A third method, on the 08-12 database, gives the same numbers

`rail/work/disconnected_instances.txt` was produced from `report_resistance`
D/C rows — a different Voltus command — and records **255 VDD + 302 VSS**. The
`.iv` from that same database (`rail/work/rail2/…/VDD_VSS_div.iv`, 338,897
instances) gives **255 no-VDD and 302 no-VSS**. Exact agreement between
`report_rail` and `report_resistance`.

### 3c. Control 1 — the same island, both answers

Island `[1050.2, 1055.6]` holds **100 instances across 20 rows**. **55 are
disconnected on 11 rows; 45 are analysed and given numbers on the other 9.** Same
island, same width, same PGV, same solve, same run.

**"A narrow island cannot show a supply path by construction" is refuted by the
run's own output.** So is "the LEF frame has no path": these are the same masters,
in the same sliver, metres of nothing between them, and half of them solve.

### 3d. Control 2 — the same masters, everywhere else on the die

| master | instances in design | disconnected | rate |
|---|---|---|---|
| `DCAP4` | 4,446 | 106 | 2.38% |
| `FILL4` | 32,510 | 15 | 0.05% |
| `DFCNQD1` | 35,809 | 3 | **0.008%** |
| `CKBD1` | 3,510 | 17 | 0.48% |
| all | 350,718 | 330 | 0.094% |

34 masters are affected out of 387 present, and **not one of them is affected at a
rate above 3.7%.** A LEF-frame or PGV defect is a property of a *master* and would
read 100%. This reads 0.008%. **The disconnected set is a function of location,
not of cell.**

### 3e. Control 3 — a narrower island with zero

| island | width | rows | instances | disconnected |
|---|---|---|---|---|
| `[1051.8, 1055.0]` (site B) | **3.2 µm** | 39 | 127 | 44 |
| `[1390.6, 1395.0]` | **4.4 µm** | 38 | 190 | **0** |
| `[1024.0, 1055.6]` | 31.6 µm | 25 | 179 | **0** |
| `[205.0, 227.0]` | 22.0 µm | 163 | 1,344 | **0** |

Narrowness is not sufficient. The design contains 18 row islands under 60 µm and
only 7 of them strand anything.

### 3f. And the alternative reading of `NA` is excluded

The `.iv` legend offers two meanings: *"disconnected from the net **or** the
instance does not have timing/switching window"*. This run is `-method static`,
`WINDOW NA` in the header — **no** instance has a switching window. If the second
clause were operating, all 350,718 rows would read `NA`. 330 do.

### The `838 !POWER && !GROUND` comparison, settled

Those are Calibre LVS `ERC PATHCHK` soft-check nets, and they *are* a
black-boxing artefact — the cell interiors are not in the layout, so no path can
be traced through them. **That mechanism cannot produce this result.** The rail
solve never enters a cell: its path is pad → ring → M8/M9 → M5 ladder → risers →
M1 follow-pin → the cell's PG pin, and every metre of it is drawn special routing
in the database. The discriminating measurement is §3d: an artefact of the cell
abstraction is constant per master; this is 0.008% on one master and 2.4% on
another, and 0% on the same master 20 µm away.

---

## 4. OTHER BUILDS — the geometry is fixed, the count is not

| database | instances | disconnected | how measured |
|---|---|---|---|
| `build/fp1505` (2026-08-17 21:32) | 350,718 | **330** | Voltus `.iv` |
| `runs/…20260812…route-baseline` | 338,897 | **466** | Voltus `.iv` (`work/rail2`) |
| `build/full-20260814` **(shipping)** | 339,390 | **328** | predictor, §5 |

Clustering the 08-12 set gives **the same five sites at the same coordinates**:

| site | fp1505 box | 08-12 box | fp1505 n | 08-12 n |
|---|---|---|---|---|
| A | 1034.2–1054.8 × 352.6–493.0 | **identical** | 158 | 328 |
| B | 1051.8–1054.2 × 1544.2–1592.8 | **identical** | 44 | 42 |
| D | 869.2–906.8 × 489.4–491.2 | **identical** | 76 | 36 |
| C | 1043.2–1054.8 × 262.6–280.6 | **identical** | 30 | 30 |
| D′ | 879.8–894.4 × 439.0–440.8 | **identical** | 22 | 30 |

Only 87 of the 330 are the *same instances* — the re-route moved the cells, not
the sites. **That is the important shape of this result.** An identical count
across builds would have suggested a fixed-size tool artefact; an identical
*geometry* with a moving count says the defect is in the floorplan's row
structure, which those two builds share, and the population is whatever the
placer put in the islands that day.

Counting the rail-class open boxes directly, over every build in `build/`:

| build | rail-class `IMPVFC-200` boxes |
|---|---|
| `fp1505` | 34 |
| `full-20260814` | 34 |
| `knobs-live` | 34 |
| `macro-move` | 34 |
| `m5off5` (M5 offset 5) | 36 |
| `m5off6` (M5 offset 6) | 42 |

The first four agree on **every box's x-origin and width**, and several are
identical in all four fields — `VDD 1030.735 368.800 28.330 × 2.530` appears
verbatim in all four. What varies between them is the y-extent of a box by tenths
of a micron, i.e. which rails inside a site broke, not where the sites are. `m5off5` and `m5off6` hold the same five
sites with the y-coordinates moved — which is the causal link to the M5 ladder,
free: **change the M5 start offset and the broken rails move in y.**

`full-20260814`'s *rail* run cannot corroborate this: its extraction aborted on
the `VOLTUS_EXTR-1223` VDD/VSS M5 short (`32-ir-drop-stage.md` §5), so it has no
`.iv` at all. Its verdict is `FAIL_HARD` on `no_rail_artefact`, **not** a measured
zero. §5 measures it another way.

---

## 5. WOULD IT REACH SILICON — yes, and here is the measurement

The shipping database has no rail solve, so a predictor was built from the one
thing both builds have — `check_connectivity` — and **validated against Voltus on
the build where Voltus ran.**

**Rule** (from §2b): a cell is stranded on net N if it lies inside a rail-class
`IMPVFC-200` box for net N, extended one row pitch downward.

**Validation on `fp1505`, against the 330 Voltus `NA` rows:**

```
  VDD : predicted 154   Voltus 154   agree 154   false pos 0   false neg 0
  VSS : predicted 248   Voltus 243   agree 243   false pos 5*  false neg 0
  union: predicted 330  Voltus 330   agree 330
```

\* the five are instances Voltus had already flagged on VDD; the union is exact.
**Zero false negatives, and the union is 330 of 330.**

**Applied to `build/full-20260814`, the shipping database:**

```
  stranded instances : 328   (no VDD 153, no VSS 247, neither 72)
  physical-only      : 273
  FUNCTIONAL         :  55
```

Among that 55: five flip-flops
(`CTL$reg_inv_addr_reg[4]`, `[6]`, `CTL$reg_linefill_buf_reg[81]`, `[83]`,
`[114]`), 19 QSPI cache `RAMCLD0WDATA`/`RAMTAG1ADDR` buffers,
`u_network_core/FE_PHC13878_u_region_eth_scratch_tx_0_u_sram_u_ahb_to_sram_buf_we_0`
(a scratch-TX SRAM **write-enable** buffer), and
`u_network_core/FE_OFC9101_u_ethmac_0_u_inner_ha_rst` (an ethernet MAC **reset**
buffer).

### Which of the three possible classes is it?

The brief offered three. Taking them in turn:

- **"Connectivity-extraction gap (analysis noise)."** Excluded by §3a — a second
  tool, a different command, a different session, agrees on 100.0% of them and
  places the boxes on the rails themselves; and by §3c–3e, which show the effect
  tracks location, not master, tool or geometry class.
- **"Artefact of the black-boxed cell layout (unmeasurable here)."** Excluded by
  §3d and by the path argument: no part of the traced supply path is inside a
  cell. This is the `838 !POWER && !GROUND` mechanism and it does not apply.
- **"A real unpowered cell (functional failure)."** This one. The metal path from
  the pad to these cells' PG pins is absent in the database, and the database is
  what streams out.

**One honest limit on the strength of the claim.** What is proven is that **the
drawn metal contains no path.** Whether an isolated *VSS* rail is nonetheless
pulled toward ground through the substrate taps sitting on it is a device-level
question this site cannot answer — there is no cell GDS and no cell SPICE here
(the same limit that black-boxes LVS and forbids dynamic rail analysis). It would
not rescue the cells: a substrate return is not a supply, it carries no switching
current, and no signoff accepts one. But it is the reason the failure mode on
silicon is "wrong behaviour under load", not necessarily "dead output", and it is
why the honest severity statement is **functional defect, mechanism proven,
device-level consequence not simulated.**

**What would settle even that:** a gate-level simulation of the QSPI cache path
with these 55 instances forced to X, or an SDF/GLS run on the routed netlist. GLS
is possible on this site (`tcbn65lp.v` ships with the `.lib`). It is not needed to
decide whether to fix.

---

## 6. THE FIX

### 6a. The mechanism, in the tool's own words

`power_plan.tcl:616` ends with

```tcl
route_special -connect {block_pin core_pin floating_stripe} \
    ... -core_pin_target first_after_row_end ...
```

Innovus 21.11 `TCRcom/route_special.html`, on `-core_pin_target`:

> `first_after_row_end` : **Extends the standard cell pin to the first ring or
> stripe outside of the row.**
> … *Note: Followpin wire can be targets for stripe and secondary pin connection,
> but not for followpin connection.*

On a 500 µm row that is harmless: the follow-pin crosses dozens of M5 stripes and
is stitched at every crossing anyway. **On a 3.2 µm island it is the whole
supply**, and the extension has to reach past a macro halo to a stripe outside the
row. Where that extension fails — and `15-pg-opens-analysis.md` §2.2 already
established *why* it fails, a 0.330 µm rail-width riser that must carry a
`MINIMUMCUT` 2-cut via array onto a fixed M2/M4 track grid — the island rail has
no second chance and every cell on it is stranded. Both failure shapes are visible
in the fp1505 boxes: the risers (`VDD 1058.735 475.000  0.330 × 0.800`, 0.135 µm
from the imem macro edge) and the orphaned rail pieces they were meant to feed.

### 6b. The candidate fixes, ranked, each with a falsifiable prediction

**None of these has been tested. They are named with their tests, not asserted.**

| | change | prediction to falsify | cost |
|---|---|---|---|
| **1** | Add stripe targets to the followpin extension: `-core_pin_target {stripe ring block_ring}` (the list form) in place of the bare `first_after_row_end` enum, so the M5/M8 stripes **crossing** an island are legal targets rather than only whatever lies beyond its end. | The 34 rail-class boxes at the five sites go to 0. The 28 riser/fragment boxes need not move. | PG probe first (3 min, no P&R licence), then a full P&R. |
| **2** | Structural, and **already owned by `36-split-row-pg-anchoring-hazard.md` §7**: give the M5 `add_stripes` call a single explicit `-area` over the core so one continuous ladder is generated instead of 21 re-anchored ones. | `36-…` §7's own test — anchor count drops to 1 — **plus** the five sites clearing. Would close the four VDD–VSS shorts and this defect together. | Full P&R. |
| **3** | Belt and braces: a **hard placement blockage** over any row island that cannot be fed, so no cell can land where no supply reaches. | Zero functional cells at the five sites; the 275 physical cells become irrelevant. | Floorplan change → full P&R. |
| **4** | `-core_pin_check_stdcell_geometry` on a post-route `route_special` pass — trims via arrays to repair the DRC that is making the risers fail. | Riser-class opens fall; **does not by itself feed an island whose only target is outside the row.** Complementary to 1, not a substitute. | Post-route ECO. |

**Fix 1 is the one to try first** because it addresses the documented cause
directly and is the smallest edit. `power_plan.tcl` is under another session's
ownership right now, so this document names the change and does not make it.

### 6c. What stage has to re-run

`power_plan.tcl` runs **before placement**, and `split_row` is a *row* operation
(`36-…` §7 warns explicitly that removing it changes the row structure the placer
later sees). So:

- **Cheap screen, no P&R licence, ~3 min:** `scripts/probe_pg_build.tcl` — floorplan
  + power_plan only. It can show whether the five sites' rail-class open boxes
  clear. **Caveat, stated because it will otherwise mislead:** the probe's absolute
  open count is ~337, against 64 on the routed database, so **only the presence or
  absence of boxes at these five coordinate ranges is comparable**, never the total.
- **The real answer: `floorplan → power_plan → place → cts → route`.** A full P&R.
  There is no shortcut; the defect is built before placement and the population it
  strands is decided by placement.
- **Then re-run `make -C ASIC/genus-innovus rail RAIL_RUN_TAG=<new>`** (~25 min) and
  read `metrics.iv_disconnected`. The predictor in §5 gives the same answer from
  `check_connectivity` alone, so the rail solve is confirmation, not the gate.

---

## 7. WHAT THE GATE SHOULD COUNT

`pg.disconnected` is **correct, it is firing on a real defect, and its threshold
of 0 is right.** `cov.disconnected_max_source` says it best already: *"an instance
with no path to VDD or VSS does not power up. No non-zero value is defensible, so
this one is not a budget at all."* Nothing here argues for changing it, and
nothing in `rail_budgets.txt` was changed.

But the brief's warning applies to the **headline**, not the threshold. The
verdict currently reads:

> `330 instances have NO PATH to a supply rail (limit 0). This is a functional
> defect, not a margin: those cells do not power up.`

**83% of that 330 is fill, decap and antenna diodes.** The next person to meet
this check will discover that within ten minutes, and a check whose headline
over-claims by a factor of six is a check that gets waived. Two changes would fix
that without weakening anything — both are reporting, neither is a threshold:

1. **Report the split in the metric, and lead with the functional count.**
   `iv_disconnected_functional` (55) and `iv_disconnected_physical` (275) beside
   the existing `iv_disconnected` (330). Gate on **both** at 0 — a disconnected
   DCAP is decoupling that does not decouple and a disconnected ANTENNA is a diode
   that does not protect, so neither is waivable either — but say which is which,
   because they are different repairs and different severities.
2. **Report the site count, not just the instance count.** 330 instances is 53
   rail segments in 5 sites bounded by 4 named macros. The instance count moves
   with every re-route (466 → 330 → 328) and reads like noise; **the site count has
   not moved in five days, two floorplans and six builds**, and it is the number
   that says "unfixed defect" rather than "today's placement".

A third, smaller, worth doing while there: the census already records
`solve.currentnote.*` ("Note: 201 current sources are disconnected", "…79…").
Those two lines are the same defect seen from the demand side and are currently
inert text. They do not reconcile to 330 by any obvious arithmetic, and until
someone reconciles them they should not be quoted as a second measurement.

---

## 8. Provenance

Every number above is reproducible with no licence from files already on disk:

| claim | source |
|---|---|
| the 330 rows | `rail/work/fp1505/results/PD_TOP_125C_avg_1/Reports/VDD_VSS_div.iv` |
| coordinates | `rail/work/fp1505/inst_xy.txt` |
| row islands | `build/fp1505/work/nanosoc_eth_chiplet_pads_routed/nanosoc_eth_chiplet_pads.fp.gz`, `DefRow:` records |
| macro origins / halo | same file, `<inst …>` and `InstHalo` records |
| the independent opens | `build/fp1505/reports/nanosoc_eth_chiplet_pads_conn_{VDD,VSS}.rep` |
| the 08-12 comparison | `rail/work/rail2/PD_TOP_125C_avg_1/Reports/VDD_VSS_div.iv`, `rail/work/inst_xy.txt` |
| the third method | `rail/work/disconnected_instances.txt` (255 VDD / 302 VSS) |
| the shipping-build result | `build/full-20260814/reports/…conn_*.rep` + `rail/work/full-20260814/inst_xy.txt`, `instance.rpt` |
| `-core_pin_target` semantics | `TCRcom/route_special.html` in the installed Innovus 21.11 reference (the doc root is inherited from the site's Cadence install and is not spelled in this repository) |

No vendor geometry is quoted. Cell-master *names* and the project's own placement
coordinates are design data; macro dimensions, rail widths and rule values are not
reproduced here — read them at the paths named in `15-pg-opens-analysis.md` §2.2.

## 9. See also

- `32-ir-drop-stage.md` §2b — where this defect was first localised (§1 correction above)
- `15-pg-opens-analysis.md` — the riser mechanism, 2026-08-06, static analysis only
- `36-split-row-pg-anchoring-hazard.md` — the `split_row` per-region anchoring cause, and fix 2
- `32-macro-placement-pg-short-window.md` — the four VDD–VSS shorts in the same band as site B
