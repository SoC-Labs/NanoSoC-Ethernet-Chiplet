# 03 — Floorplan

Block: `nanosoc_eth_chiplet_pads` · TSMC 65nm LP (9M_6X1Z1U) · Cadence Innovus 21.11-s130_1, STYLUS/Common-UI.

Source of truth: [`ASIC/genus-innovus/scripts/floorplan.tcl`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/floorplan.tcl).
Sourced by [`2_pnr_setup.tcl`](https://github.com/SoC-Labs/ASIC-Flow/blob/b19e7845448e641ea8353b19a59a77257907cb13/Cadence/2_pnr_setup.tcl) immediately after `commit_power_intent`, and immediately before [`power_plan.tcl`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/power_plan.tcl). That ordering is load-bearing — see [Publishing the resolved macro list](#43-publishing-the-resolved-macro-list).

Prev: [02-innovus-basics](02-innovus-basics.md) · Next: [04-power-plan](04-power-plan.md) · Index: [00-index](00-index.md)

---

## At a glance

| Quantity | Value | Source |
|---|---|---|
| Die | 1600 × 2000 µm, anchored at (0,0) | `create_floorplan -die_size 1600 2000` |
| IO driver pad height | 135.000 µm | `tphn65lpgv2od3_sl` LEF, every `PDDW*_G` / `PVDD2*_G` / `PCORNER_G` |
| `CORE_TO_IO` | **70** (was 50) | `floorplan.tcl:60` |
| Core box | (205, 205) – (1395, 1795) = 1190 × 1590 µm | 135 + 70 inset per side |
| Core area | 1,892,100 µm² (was 2,004,900 at margin 50) | −112,800 µm², −5.63 % |
| Macros | 21, placed by absolute die coordinates | `place_macro` calls |
| Total macro area | ≈ 757,805 µm² ≈ 40.1 % of the core | derived from LEF `SIZE` × inventory |
| Macro halo | 3.6 µm all round, all macros | `create_place_halo -halo_deltas {3.6 3.6 3.6 3.6}` |
| Bond pads | 42 × `PAD70GU` (outer) + 40 × `PAD70NU` (inner) = 82 | [`place_bondpads.tcl`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/place_bondpads.tcl) |

---

## 1. The die and the core box

```tcl
set CORE_TO_IO 70
create_floorplan -site core -die_size 1600 2000 \
    $CORE_TO_IO $CORE_TO_IO $CORE_TO_IO $CORE_TO_IO
```

**The four trailing numbers are core-to-IO clearances, not core-to-die.** This is the single most
misread line in the flow. Innovus insets the core by the *IO row height plus* the number you give:

```
core_edge = pad_height + CORE_TO_IO = 135 + 70 = 205
core box  = (205, 205) – (1600-205, 2000-205) = (205,205)–(1395,1795)
```

The 135 µm comes straight out of the pad LEF — every `PDDW*_G`, `PVDD2*_G` and `PCORNER_G` in
`tphn65lpgv2od3_sl` is that tall, which is what makes it the IO row height. (The LEF statements
themselves are not reproduced here — TSMC licence.) Verified against the placed database at both
margins:

| `CORE_TO_IO` | Core box | Core size |
|---|---|---|
| 50 (old) | (185,185)–(1415,1815) | 1230 × 1630 |
| 70 (current) | (205,205)–(1395,1795) | 1190 × 1590 |

**The die is fixed at 1600 × 2000 and anchored at (0,0).** Every micron added to `CORE_TO_IO` comes
directly out of the core. You cannot grow the die to buy the clearance back — and even if you could,
it would not help, because the macro coordinates in this file are absolute and the core's *lower-left*
corner moves inward regardless. That dependency is the whole subject of
[section 5](#5-worked-procedure-changing-the-core-to-io-margin).

---

## 2. Why the margin is 70 and not 50 — the staggered bond ring

This is the subtle part of the floorplan, and it is worth understanding rather than memorising.

### 2.1 The bond ring is staggered, and it is invisible to the margin calculation

The design uses a **staggered** bond pad ring from `tpbn65v`, placed by
[`place_bondpads.tcl`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/place_bondpads.tcl) with
`create_relative_floorplan` against each driver pad:

| Cell | Role | Height (µm) — the dimension the margin must clear | Count |
|---|---|---|---|
| `PAD70GU` | outer row | 86.685 | 42 |
| `PAD70NU` | inner row | **171.000** | 40 |

The inner row is 84.3 µm taller, so it reaches **36 µm further inboard** than the driver pads do
(171 − 135). And here is the trap:

> Both `PAD70GU` and `PAD70NU` are **`CLASS BLOCK`**, not `CLASS PAD`.

Consequence: `create_floorplan -core_margins_by io` **does not see them**. It insets the core by the
135 µm driver height and stops. Nothing in the margin computation knows the inner bond pads exist,
let alone that they overhang. The clearance has to be added by hand, which is exactly what
`CORE_TO_IO` is doing.

Verified directly in the PDK LEF (read-only, `.../tpbn65v_200b/cup/9m/9M_6X1Z1U/lef/tpbn65v_9lm.lef`):
`MACRO PAD70NU` is declared `CLASS BLOCK`, 171 µm tall — the number the floorplan has to clear.

> Vendor LEF geometry redacted — TSMC licence forbids reproduction. Source:
> `$TSMC_65_HOME/iolib/tpbn65v_200b_FE/.../lef/tpbn65v_9lm.lef`, `MACRO PAD70NU`.

### 2.2 `PAD70NU` blocks M8 and M9 solidly — the core-ring layers

The same macro's `OBS` section blocks **both M8 and M9 solidly over the pad's entire footprint**
(there are additional "wing" polygons either side, but the body blockage alone is what matters
here — see [scripts/07 §4.5](scripts/07-filler-and-bondpads.md) for the correction). Those are precisely the
core-ring layers — `add_rings` uses left/right M8 and top/bottom M9, see [04-power-plan](04-power-plan.md#3-core-rings).

`add_rings` draws **geometrically**. It does not honour OBS. So the rings were simply drawn straight
through the bond pads, symmetrically on all four sides.

### 2.3 The arithmetic

The ring stack occupies `core_edge+2 .. core_edge+30` (offset 2, then 12 wide + 4 spacing + 12 wide).
Measured from the routed database, `PAD70NU` reaches inboard to **171 / 1429 / 171 / 1829** on
left / right / bottom / top.

| Margin | Ring outer edge (L/R/B/T) | vs `PAD70NU` at 171/1429/171/1829 | Result |
|---|---|---|---|
| 50 | 155 / 1445 / 155 / 1845 | | **16.00 µm overlap, every side** |
| **70** | 175 / 1425 / 175 / 1825 | | **4.00 µm clear, every side** |

4 µm clears both wide-metal rules, confirmed against the tech LEF
(`PRTF_EDI_N65_9M_6X1Z1U_RDL.24a.tlef`):

- **M8** — its `SPACINGTABLE` requirement, at its very worst width band, is well under 4 µm.
- **M9** — a single flat `SPACING` rule, also under 4 µm.

Both layers' `MAXWIDTH` limit is **exactly the 12 µm the rings already use**. **Legal, but on the
limit — do not widen the rings.** (Rule values not reproduced — TSMC licence; read them from the
tech LEF above.)

### 2.4 The evidence

This was measured, not assumed. From the 2026-08-05 baseline run
(`ASIC/genus-innovus/baseline_2026-08-05/reports/nanosoc_eth_chiplet_pads_imp_drc.rep`), which ran at
`CORE_TO_IO=50`:

| Cell class | Total DRC records naming its blockage | of which VDD/VSS **special wire** |
|---|---|---|
| `PAD70NU` (inner, 40 insts) | 366 | **318** |
| `PAD70GU` (outer, 42 insts) | 32 | **0** |

**Zero PG shorts on the outer pad is the control.** `PAD70GU`'s inboard edge never reaches the ring
band, and sure enough it is never hit by a power wire. The overlap is specific to the inner,
taller pad — exactly as the geometry predicts. 398 of the run's bond-pad blockage violations come from
these two rows combined.

> **Correction to the in-script comment.** `floorplan.tcl` says the report has "539 violations".
> The report's own trailer says **`Total Violations : 580 Viols.`**, and an independent parse of the
> file agrees: 580 records (379 SHORT, 108 SPACING, 41 EndOfLine, 28 MINSTEP, 14 MINHOLE, 7 NSMETAL,
> 2 MINCUT, 1 MINWIDTH). The difference is exactly the 41 `EndOfLine:` records — the likely cause is a
> case-sensitive count that skipped the only violation keyword containing lower-case letters.
> The **318 / 366 / 32 / 0 breakdown is exactly right**; only the denominator is off. So the PG shorts
> are **54.8 %** of all DRC on that run, not the 59 % the comment claims. Still the largest single
> category by a wide margin.

---

## 3. IO pads and IO fillers

```tcl
delete_io_fillers
read_io_file ../scripts/nanosoc_eth_chiplet_pads.io
```

[`nanosoc_eth_chiplet_pads.io`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/nanosoc_eth_chiplet_pads.io) is
generated by `nanosoc_gen SoCPadRingBackend`. Per-side instance **order** is faithful to the pin-map;
the `offset=` values are evenly-spaced placeholders. Every pad is `place_status=fixed`.
Four `PCORNER_G` corners, then 17 top / 26 left / 17 bottom / 22 right = 82 signal+supply pads.

Those per-side counts are the reason the bond-pad lists work out:

| Side | `.io` pads | outer (`PAD70GU`) | inner (`PAD70NU`) |
|---|---|---|---|
| top | 17 | 9 | 8 |
| left | 26 | 13 | 13 |
| bottom | 17 | 9 | 8 |
| right | 22 | 11 | 11 |
| **total** | **82** | **42** | **40** |

IO fillers are then added **largest-first** — `PFILLER20_G`, `10`, `5`, `1`, `05`, `0005` — each on all
four sides in turn. The descending order matters: a greedy pass with a small cell first leaves gaps
too fragmented for the large ones, and the smallest (`PFILLER0005_G`) exists only to close the final
sub-micron slivers.

Bond pads themselves are **not** placed here. They are placed much later, from
[`place_bondpads.tcl`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/place_bondpads.tcl), sourced by
`4_pnr_route.tcl` after routing — see [06-fill-antenna-bondpads](06-fill-antenna-bondpads.md).
Their geometry nonetheless constrains *this* file, which is precisely what makes the trap in
[section 2](#2-why-the-margin-is-70-and-not-50-the-staggered-bond-ring) so easy to miss.

---

## 4. Macro placement

```tcl
unplace_obj -blocks
create_place_halo -halo_deltas {3.6 3.6 3.6 3.6} -all_macros
```

### 4.1 Why macros are resolved by pattern, not by path

Genus runs with **auto-ungroup ON** (`set_db auto_ungroup none` is left commented out in
`1_synthesis.tcl`). A macro's hierarchical name is therefore a function of the tool's ungrouping
decisions, and it **moves when the RTL changes**.

This file used to hardcode 21 full paths captured from one netlist. After an unrelated RTL change,
6 of them no longer existed — the ethmac RF, and the five QSPI `way1` macros, which lost their
`gen_way1.` generate-block prefix.

The failure mode is what makes this worth fixing properly:

- `place_inst` reports **`IMPTCM-162` "does not match any object in design"**.
- That reads as a *stale floorplan*, not as a *renamed instance*.
- It aborts `2_pnr_setup.tcl` on the **first** bad name — so you fix them one slow Innovus run at a time.

The patterns key on RTL-derived fragments (region names, cache way/word indices, macro type), which are
stable, and ignore separators and prefixes, which are not.

If a pattern does go stale, **do not guess** — dump the current names with
[`probe_macros.tcl`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/probe_macros.tcl), which replicates
`2_pnr_setup.tcl` up to `init_design`, writes `logs/macro_insts.txt`, and exits without writing a DB:

```sh
cd ASIC/genus-innovus/work
TSMC_65_HOME=/tsmc65pdk/65 NANOSOC_ETH_CHIPLET_HOME=<repo> \
  innovus -stylus -files ../scripts/probe_macros.tcl < /dev/null
```

Both the env vars and the `< /dev/null` matter: `common.mk` normally exports the former, and without
the latter Innovus drops to its prompt on any error and sits there until killed.

### 4.2 The two guards inside `place_macro`

**Guard 1 — exactly one match, and it must be a macro.**

```tcl
foreach i [get_db insts $pattern] {
    if {[get_db $i .base_cell.base_class] eq "block"} { lappend hits $i }
}
if {[llength $hits] != 1} { error ... }
```

`get_db insts <pattern>` matches **every** instance, standard cells included. A region-scoped glob
like `*region_eth_scratch_rx_0*` returns the macro **plus roughly 50 leaf cells in the same region**.
Without the `base_class == block` filter the "exactly 1" test would be meaningless — it would fail on
patterns that are perfectly correct. The filter is done in Tcl rather than with `-if` so there is no
ambiguity about how a pattern and a predicate combine in this Innovus version.

**Guard 2 — the containment assertion.**

```tcl
lassign [lindex [get_db current_design .core_bbox] 0] cx1 cy1 cx2 cy2
lassign [lindex [get_db [lindex $hits 0] .bbox] 0] mx1 my1 mx2 my2
if {$mx1 < $cx1 || $my1 < $cy1 || $mx2 > $cx2 || $my2 > $cy2} { error ... }
```

`place_inst` takes **absolute die coordinates** and does not object when the result straddles or clears
the core boundary. It places the macro and says nothing. The first symptom is a power/route mess
hundreds of lines later, which reads as an `sroute` problem rather than a floorplan one.

The error message names the overhang **per edge** and restates what `CORE_TO_IO` is currently doing —
so the next person to change the margin gets told, at the point of placement, exactly which macros no
longer fit and by how much.

### 4.3 Publishing the resolved macro list

```tcl
lappend ::PLACED_MACROS $inst
```

`power_plan.tcl` used to carry its **own hardcoded copy** of the same 21 hierarchical paths — and it
drifted. The identical 6 names that went stale here were still stale there, so `split_row` silently ran
on **15 of 21** macros, producing six `IMPTCM-165` "does not match any object" warnings that nobody was
reading. Publishing the resolved names removes the duplication entirely, and `power_plan.tcl` now hard-
errors if the list is missing or empty. This is why floorplan must be sourced before power plan.

### 4.4 Macro inventory (verified)

All 21 patterns resolve to exactly one macro each, all 21 macros are placed, and all 21 lie inside the
`CORE_TO_IO=70` core box. Bounding boxes below are computed as `(x, y) – (x+W, y+H)` from the LEF
`SIZE` — correct here because every orientation in use is `R0`/`R180`/`MX`/`MY`, none of which swaps
width and height.

| Macro cell | `SIZE` (µm) | Qty | Area each (µm²) |
|---|---|---|---|
| `rf_32k` | 585.38 × 285.28 | 1 | 166,997 |
| `rf_16k` | 311.8 × 285.25 | 3 | 88,941 |
| `rf_08k` | 311.8 × 154.09 | 4 | 48,045 |
| `rf_01k` | 177.4 × 58.99 | 1 | 10,465 |
| `flash_cache_data` | 311.8 × 36.36 | 8 | 11,337 |
| `flash_cache_tag` | 135.4 × 40.51 | 2 | 5,485 |
| `rom_via` / `eth_rom_via` | 164.665 × 59.735 | 2 | 9,836 |
| | | **21** | **757,805 total ≈ 40.1 % of core** |

Placed positions:

| Pattern | Cell | bbox (µm) |
|---|---|---|
| `*ethmac*bd_ram*u_rf` | rf_01k | (1053.8,1117.8)–(1231.2,1176.8) |
| `*u_network_core*u_region_bootrom_0*rom_via*` | eth_rom_via | (883.5,1538.6)–(1048.2,1598.3) |
| `*u_network_core*u_region_dmem_0*rf_16k*` | rf_16k | (1058.6,1340.4)–(1370.4,1625.7) |
| `*region_eth_scratch_rx_0*` | rf_08k | (590.2,1338.8)–(902.0,1492.9) |
| `*region_eth_scratch_tx_0*` | rf_08k | (1049.8,1633.8)–(1361.6,1787.9) |
| `*u_network_core*u_region_imem_0*rf_32k*` | rf_32k | (290.8,1503.4)–(876.2,1788.7) |
| `*way1_cache_ram_tag_ram_0_i` | flash_cache_tag | (911.2,468.7)–(1046.6,509.2) |
| `*way0_cache_ram_tag_ram_0_i` | flash_cache_tag | (898.8,402.1)–(1034.2,442.6) |
| `*way0_cache_ram_data_ram_0_word_2_i` | flash_cache_data | (553.8,480.4)–(865.6,516.8) |
| `*way0_cache_ram_data_ram_0_word_3_i` | flash_cache_data | (516.6,390.0)–(828.4,426.4) |
| `*way0_cache_ram_data_ram_0_word_0_i` | flash_cache_data | (702.4,300.0)–(1014.2,336.4) |
| `*way0_cache_ram_data_ram_0_word_1_i` | flash_cache_data | (718.8,345.0)–(1030.6,381.4) |
| `*way1_cache_ram_data_ram_0_word_2_i` | flash_cache_data | (633.6,527.2)–(945.4,563.6) |
| `*way1_cache_ram_data_ram_0_word_3_i` | flash_cache_data | (564.4,435.0)–(876.2,471.4) |
| `*way1_cache_ram_data_ram_0_word_0_i` | flash_cache_data | (708.6,210.0)–(1020.4,246.4) |
| `*way1_cache_ram_data_ram_0_word_1_i` | flash_cache_data | (727.8,255.0)–(1039.6,291.4) |
| `*u_chip_core*u_region_imem_0*rf_16k*` | rf_16k | (1059.2,209.9)–(1371.0,495.2) |
| `*u_shared_sram_0*rf_08k*` | rf_08k | (1052.4,506.7)–(1364.2,660.8) |
| `*u_chip_core*u_region_dmem_0*rf_08k*` | rf_08k | (1050.4,953.6)–(1362.2,1107.7) |
| `*u_chip_core*u_region_bootrom_0*rom_via*` | rom_via | (1222.3,735.5)–(1387.0,795.2) |
| `*u_tidelink*u_tidelink_fifo_u_fifo_mem_u_sram_u_rf` | rf_16k | (230.6,1210.0)–(542.4,1495.2) |

Tightest remaining clearances to the core edge: **4.95 µm** (chip imem `rf_16k`, bottom), **5.00 µm**
(QSPI way1 word_0, bottom), **6.31 µm** (network imem `rf_32k`, top), **7.10 µm** (eth_scratch_tx, top),
**8.00 µm** (chip bootrom, right). The 3.6 µm halo still fits inside the core at every one of these.

---

## 5. Worked procedure: changing the core-to-IO margin

This is the most recent real change to the floorplan (50 → 70) and it exercises the entire dependency
chain. Follow it in order; steps 3–4 are the ones people skip.

### Step 1 — understand what moves

Changing `CORE_TO_IO` by Δ moves **all four core edges inward by Δ**:

```
core_lower_left  += Δ        core_upper_right -= Δ
core size        -= 2Δ  in each dimension
```

The die does **not** change (it is fixed at 1600 × 2000, anchored at (0,0)). Macro coordinates are
absolute and do **not** track the core box. So a macro near the bottom or left edge can fall outside
the core even though nothing about it changed — this is the counter-intuitive part, and it is why you
cannot "just make the die bigger".

### Step 2 — edit the one line

```tcl
set CORE_TO_IO 70          ;# floorplan.tcl:60
```

Nothing else in the file references the old value; the ring/pad clearance note in the header comment
should be updated to match.

### Step 3 — recompute the ring-to-bond-pad clearance

This is *why* you are changing the margin, so check it explicitly. With
`add_rings -width 12 -spacing 4 -offset 2`, the ring stack spans `core_edge+2 .. core_edge+30`:

```
ring outer edge  =  core_edge + 30
                 =  (135 + CORE_TO_IO) + 30        [left/bottom: measured inward from 0]
clearance        =  PAD70NU_inboard_edge - ring_outer_edge
```

with `PAD70NU` inboard at **171 / 1429 / 171 / 1829** (L/R/B/T). Require the clearance to meet the
M9 `SPACING` rule, which is the binding one here — M8's requirement is looser. Read the value from
`LAYER M9` in the tech LEF; it is not reproduced here, TSMC licence forbids it. At `CORE_TO_IO=70`
the clearance is 4.00 µm, which clears the rule with room to spare.
If you ever change the ring width, offset or spacing, redo this — see
[04-power-plan §3](04-power-plan.md#3-core-rings).

### Step 4 — re-place every macro that no longer fits

Compute the new core box, then for each of the 21 macros check
`(x, y) – (x+W, y+H)` against it. At 50 → 70 this put **five** macros outside:

| Macro | Overhang | Fix applied |
|---|---|---|
| QSPI way1 `word_0` | 14.96 below core bottom | `+20` y |
| `eth_scratch_tx` | 12.89 above core top | `−20` y |
| chip `bootrom` (`rom_via`) | 7.00 past core right | `−15` x |
| network imem `rf_32k` | 3.68 above core top | `−10` y |
| chip imem `rf_16k` | 1.05 below core bottom | `+6` y |

Each of these reproduces **exactly** from the current coordinate minus its `## MOVED` delta, so the
notes in the file are trustworthy and you can reconstruct the previous floorplan from them.

**Seventeen** macros were re-placed in total — the five offenders plus twelve neighbours that would
otherwise have been collided into. Two constraints governed the choice:

1. **The ten QSPI cache RAMs move as one rigid block.** They sit on a 45 µm pitch and are 36.36 µm
   tall, leaving **8.64 µm** between them. Nothing in that stack can move alone.
2. **Every tight inter-macro gap is unchanged from the as-built floorplan.** The 28 µm of vertical
   compression came out of the slack bands, not the channels. Spot-check: the `rf_32k` ↔ tidelink
   `rf_16k` gap is still 8.15 µm; the chip imem `rf_16k` ↔ `shared_sram` gap is still 11.51 µm. Both
   are called out in the `## MOVED` notes and both verify.

Annotate every move with a `## MOVED <delta>` comment. That convention is what made the five overhangs
above reconstructable, and it is cheap.

### Step 5 — let the assertion be your check

You do **not** need to get step 4 right by inspection. Re-run placement; the containment assertion in
`place_macro` fires at the point of placement and names every macro that no longer fits, per edge,
with the overhang. That is hours earlier than the alternative, which is discovering it as `sroute`
damage or as bond-pad shorts in a DRC report.

```sh
cd ASIC/genus-innovus && make pnr_place
```

### Step 6 — watch for the second-order effect

Core area falls by 5.63 % (112,800 µm²) at 50 → 70, so **utilisation rises correspondingly**. Macro
area alone is now ≈ 40.1 % of the core. If placement starts failing or congestion worsens after a
margin change, this is why — it is not a placer regression.

---

## 6. Verification status

**Verified this week against the real database, the PDK LEFs and the run logs:**

- IO row height 135, `PAD70GU` 86.685 tall, `PAD70NU` 171.000 tall, both `CLASS BLOCK` — read from
  `tpbn65v_9lm.lef`. These three heights are the only vendor dimensions this floorplan depends on.
- `PAD70NU` `OBS` solid on M8 **and** M9 over its full footprint — read from the same LEF.
- M9's flat spacing/area rules and M8's `SPACINGTABLE` were both read from
  `PRTF_EDI_N65_9M_6X1Z1U_RDL.24a.tlef`, and 4 µm clears both. (Values not reproduced — TSMC
  licence.)
- 42 `PAD70GU` + 40 `PAD70NU`, matching the `.io` per-side counts exactly.
- 366 / 318 / 32 / **0** DRC breakdown across the two bond-pad rows — independently parsed from the
  baseline DRC report.
- All 21 `place_macro` patterns resolve to exactly one macro; all 21 macros lie inside the
  `CORE_TO_IO=70` core box; the placed set is a bijection with the 21 macros in the netlist.
- All five claimed overhangs reproduce exactly from the `## MOVED` deltas.
- The live `2_pnr_setup` log shows **zero** `IMPTCM-162` and **zero** `IMPTCM-165` — no stale macro
  names on the current netlist.

**Corrected:**

- The "539 violations" in the `floorplan.tcl` header comment is **580** (the report's own trailer).
  PG shorts are 54.8 % of DRC, not 59 %. See the note in [§2.4](#24-the-evidence).

**Not verified / uncertain:**

- The claim that the 318 PG shorts "should disappear" at margin 70 is a **prediction**, not yet a
  measurement. The margin-70 run was still in route when this was written and has produced no
  `check_drc` report. Confirm against the next `*_imp_drc.rep` before treating it as closed —
  see [09-signoff-checklist](09-signoff-checklist.md).
- Post-change core utilisation is not quoted here. The `*_imp_area.rep` "Total Area" column
  (2,396,728.89 µm² over a 1,892,100 µm² core) appears to double-count hierarchy and cannot be read
  as a utilisation figure. The 40.1 % macro fraction above is derived from LEF sizes and is sound;
  the standard-cell fraction is not established.
- The 43 `**ERROR` lines in the placement log are 20 × `IMPLF-223` (duplicate LEF via definitions,
  benign), 20 × `TCLCMD-917` (SDC referencing `uPAD_*/VDDPST` pins), 2 × `IMPSP-9099` (scan chains
  undefined for 30.55 % of flops; `DFT=0`), and 1 × `IMPMSMV-3501` (CPF defines no power_mode/
  power_state). None are floorplan defects; all are pre-existing. See
  [11-known-issues](11-known-issues.md).

---

## See also

- [00-index](00-index.md) · [01-flow-overview](01-flow-overview.md) · [02-innovus-basics](02-innovus-basics.md)
- [04-power-plan](04-power-plan.md) — rings, stripes, and the `PD_TOP` CPF trap
- [05-place-cts-route](05-place-cts-route.md) · [06-fill-antenna-bondpads](06-fill-antenna-bondpads.md)
- [07-reading-reports](07-reading-reports.md) · [08-debugging](08-debugging.md)
- [09-signoff-checklist](09-signoff-checklist.md) · [10-tapeout-submission](10-tapeout-submission.md) · [11-known-issues](11-known-issues.md)
