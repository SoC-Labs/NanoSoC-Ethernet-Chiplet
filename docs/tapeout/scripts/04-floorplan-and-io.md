# Script reference — floorplan, IO ring, pre/post-place

Command-level annotation of the floorplan stage of the Cadence flow, with citations to the
Innovus 21.11 manuals installed on this site.

**Files covered**

| File | Lines | Sourced by |
|---|---|---|
| [`ASIC/genus-innovus/scripts/floorplan.tcl`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/floorplan.tcl) | 209 | `2_pnr_setup.tcl:46` |
| [`ASIC/genus-innovus/scripts/nanosoc_eth_chiplet_pads.io`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/nanosoc_eth_chiplet_pads.io) | 127 | `floorplan.tcl:85` |
| [`ASIC/genus-innovus/scripts/preplace.tcl`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/preplace.tcl) | 11 | `2_pnr_setup.tcl:54` |
| [`ASIC/genus-innovus/scripts/postplace.tcl`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/postplace.tcl) | 4 | `2_pnr_setup.tcl:64` |
| [`ASIC/genus-innovus/scripts/probe_macros.tcl`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/probe_macros.tcl) | 41 | nothing — run by hand |

**Relationship to [03-floorplan](../03-floorplan.md).** That page explains *why* the floorplan is
the shape it is — the staggered bond ring, the `CORE_TO_IO` 50 → 70 decision, the DRC evidence.
This page is its mechanical companion: what each command does per the manual, every option, and
what breaks if you change it. Read 03 first. Nothing in 03 is repeated here except where a number
is needed to make a command legible.

Prev: [03-floorplan](../03-floorplan.md) · Index: [00-index](../00-index.md)

---

## Contents

- [0. Where the manuals actually are](#0-where-the-manuals-actually-are)
- [1. The geometry model](#1-the-geometry-model)
  - [1.1 Three boxes](#11-three-boxes)
  - [1.2 Rows, sites and flip](#12-rows-sites-and-flip)
  - [1.3 The picture](#13-the-picture)
- [2. floorplan.tcl, in order](#2-floorplantcl-in-order)
  - [2.1 `create_floorplan` (lines 79–81)](#21-create_floorplan-lines-7981)
  - [2.2 `delete_io_fillers` (line 84)](#22-delete_io_fillers-line-84)
  - [2.3 `read_io_file` (line 85)](#23-read_io_file-line-85)
  - [2.4 `add_io_fillers` × 24 (lines 87–115)](#24-add_io_fillers-24-lines-87115)
  - [2.5 `unplace_obj -blocks` (line 118)](#25-unplace_obj-blocks-line-118)
  - [2.6 `create_place_halo` (line 119)](#26-create_place_halo-line-119)
  - [2.7 `proc place_macro` (lines 140–187)](#27-proc-place_macro-lines-140187)
  - [2.8 What is *not* in this file](#28-what-is-not-in-this-file)
- [3. The 21 macros](#3-the-21-macros)
- [4. The `.io` file](#4-the-io-file)
- [5. preplace.tcl, postplace.tcl, probe_macros.tcl](#5-preplacetcl-postplacetcl-probe_macrostcl)
- [6. Dependency map: what moves when the geometry moves](#6-dependency-map-what-moves-when-the-geometry-moves)
- [7. Fragile or unexplained](#7-fragile-or-unexplained)
- [8. Sources](#8-sources)

---

## 0. Where the manuals actually are

This flow runs Innovus in **stylus (Common UI)** mode — `innovus -stylus`, per
`probe_macros.tcl:17` and the `2_pnr_setup.tcl` header. That matters for finding documentation,
because the two UIs ship as **separate manual sets**:

| Set | Path | UI |
|---|---|---|
| Text Command Reference | `$INNOVUS_HOME/doc/innovusTCR/` | **legacy** — `floorPlan`, `addIoFiller`, `loadIoFile` |
| Text Command Reference | `$INNOVUS_HOME/doc/TCRcom/` | **stylus** — `create_floorplan`, `add_io_fillers`, `read_io_file` |
| User Guide | `$INNOVUS_HOME/doc/innovusUG/` | legacy |
| User Guide | `$INNOVUS_HOME/doc/UGcom/` | **stylus** |

`ls $INNOVUS_HOME/doc/innovusTCR/create_floorplan.html` fails; the file you want is
`TCRcom/create_floorplan.html`. Every citation on this page is to `TCRcom` / `UGcom` and every
one was opened. Where the legacy page says something different it is called out explicitly.

The message-explanation tree `$INNOVUS_HOME/doc/innovuserrmsg/` (1,992 pages) does **not**
contain `IMPFP-325`, `IMPSP-196`, `IMPTCM-162` or `IMPTCM-165` — the only `IMPTCM` page installed
is `IMPTCM-42.html`. For those IDs, `man <MSGID>` inside a live Innovus session is the only route;
there is nothing to grep.

---

## 1. The geometry model

### 1.1 Three boxes

Innovus keeps three nested rectangles. All three are recorded verbatim in the floorplan section of
the saved database (`work/nanosoc_eth_chiplet_pads/nanosoc_eth_chiplet_pads.fp.gz`), which is the
authority used throughout this page:

```
Head Box: 0.0000 0.0000 1600.0000 2000.0000
IO Box:   135.0000 135.0000 1465.0000 1865.0000
Core Box: 205.0000 205.0000 1395.0000 1795.0000
```

- **Head box** = the die. 1600 × 2000 µm, lower-left anchored at (0,0). Anchoring at the
  lower-left is the `create_floorplan` default: `-floorplan_origin` defaults to `llcorner`
  (TCRcom/create_floorplan.html). The script never passes it.
- **IO box** = the inner edge of the IO driver ring. Inset by exactly **135 µm**, which is the
  height of every `tphn65lpgv2od3_sl` pad cell. Nothing in `floorplan.tcl` states 135 — Innovus
  derives it from the pad LEF.
- **Core box** = the placeable region. Inset a further **`CORE_TO_IO` = 70 µm** inside the IO box.

The chain is `core_edge = pad_height + CORE_TO_IO = 135 + 70 = 205`, and the manual is explicit
about which of those two numbers you supply. For `-die_size { w h left bottom right top }`:

> `left` : Specifies the margin from the outside edge of the core to the **left of the I/O
> boundary**.
> — Innovus Stylus Common UI Text Command Reference, `create_floorplan` (`TCRcom/create_floorplan.html`)

That is core-to-**IO**, not core-to-die, and it is reinforced by the `-core_margins_by {io | die}`
parameter, whose **default is `io`**. The script does not pass `-core_margins_by`, so the default
applies. This is the single most misread line in the flow and the manual settles it in one word.

### 1.2 Rows, sites and flip

`create_floorplan -site core` selects the row site, which is declared `CLASS CORE` with `SYMMETRY Y`
in the tech LEF (`PRTF_EDI_N65_<stack>_RDL.<rev>.tlef`).

> Vendor tech-LEF `SITE` geometry redacted — TSMC licence forbids reproduction. Source:
> `$TSMC_65_HOME/CMOS/util/lef/PRTF_EDI_65nm_<rev>/PRTF_EDI_N65_<stack>_RDL.<rev>.tlef`,
> `SITE core`.

The placement grid that falls out of it is **0.2 µm horizontally, 1.8 µm vertically** — the two
numbers every row-count and site-count in this flow is built on. Consequences that are worth
having in your head:

| Quantity | Value | Note |
|---|---|---|
| Core width in sites | 1190 / 0.2 = **5950** | exact |
| Core height in rows | 1590 / 1.8 = **883.33** | **not** exact |
| Rows actually created | **883** | verified: 883 distinct `DefRow` y-values in the `.fp` |
| First row y | 205.0 | flush with the core bottom |
| Last row y | 1792.6 | = 205 + 882 × 1.8 |
| Wasted strip at core top | **0.6 µm** | 1795 − (1792.6 + 1.8) |

The 0.6 µm sliver at the top of the core is unavoidable at this die size and is harmless; it is
mentioned only so that nobody re-derives it as a bug. It moves whenever `CORE_TO_IO` changes.

**Flip convention.** `create_floorplan -flip {f | s | n}` defaults to **`f`** — "the first row
flips from the bottom up" (TCRcom/create_floorplan.html). The script never passes `-flip`, so `f`
applies, and the database agrees: the row at y = 205.0 is `FS`, the row at 206.8 is `N`, and they
alternate (1,109 `FS` segments, 1,114 `N`). Standard-cell power rails therefore abut correctly
between adjacent rows. `SYMMETRY Y` on the site is what makes that legal.

**Row segmentation.** The `.fp` holds **2,223** `DefRow` segments for those 883 rows. The extra
1,340 splits are macros plus their halos carving rows into pieces. This is directly checkable —
the row at y = 205.0 is three segments:

```
DefRow: CORE_ROW_0 core  205.0000 205.0000 FS 2500 1 0.2000 0.0000   ->  205.0 .. 705.0
DefRow: CORE_ROW_1 core 1024.0000 205.0000 FS  158 1 0.2000 0.0000   -> 1024.0 .. 1055.6
DefRow: CORE_ROW_2 core 1374.6000 205.0000 FS  102 1 0.2000 0.0000   -> 1374.6 .. 1395.0
```

The first gap is 705.0 → 1024.0. QSPI `way1 word_0` sits at x = 708.6 … 1020.4, and
708.6 − 3.6 = **705.0**, 1020.4 + 3.6 = **1024.0**. The second gap 1055.6 → 1374.6 is chip imem
`rf_16k` at 1059.2 … 1371.0, again ± 3.6. That is `create_place_halo -halo_deltas {3.6 …}` from
line 119, visible in the geometry, exactly where it should be.

### 1.3 The picture

```
        x=0                                                         x=1600
  y=2000 ┌───────────────────────────────────────────────────────────────┐
         │ ┌─────┐                                             ┌─────┐   │  ← PCORNER_G 135×135
         │ │ TL  │      17 pads N, pitch 80 (25 + space 55)    │ TR  │   │    TL=R90 TR=R0
         │ │ R90 │      first at x=150, last at x=1430         │ R0  │   │    BL=R180 BR=R270
  y=1865 │ └─────┴─────────────────────────────────────────────┴─────┘   │
         │ ┌───┐                                                 ┌───┐   │
         │ │   │   IO BOX  (135,135) – (1465,1865)               │   │   │  ← 135 µm driver ring
         │ │   │ ┌─────────────────────────────────────────────┐ │   │   │
  y=1795 │ │   │ │                                             │ │   │   │
         │ │ W │ │  CORE BOX (205,205) – (1395,1795)           │ │ E │   │
         │ │   │ │  1190 × 1590 µm   883 rows of site `core`   │ │   │   │
         │ │26 │ │  (0.2 × 1.8), first row FS at y=205         │ │22 │   │
         │ │pad│ │                                             │ │pad│   │
         │ │s  │ │  21 macros, absolute coords, 3.6 µm halos   │ │s  │   │
         │ │   │ │                                             │ │   │   │
         │ │pit│ │  ← CORE_TO_IO = 70 µm on all four sides →   │ │pit│   │
         │ │ch │ │                                             │ │ch │   │
         │ │67 │ │                                             │ │80 │   │
   y=205 │ │   │ └─────────────────────────────────────────────┘ │   │   │
         │ │   │                                                 │   │   │
   y=135 │ └───┴─────────────────────────────────────────────────┴───┘   │
         │ ┌─────┬─────────────────────────────────────────────┬─────┐   │
         │ │ BL  │      17 pads S, pitch 80                    │ BR  │   │
         │ │R180 │                                             │R270 │   │
     y=0 └─┴─────┴─────────────────────────────────────────────┴─────┴───┘
        x=0    x=135                                      x=1465      x=1600

  inset chain, every side:   die edge  --135-->  IO box  --70-->  core box
                                 0        135              205

  placed LATER by place_bondpads.tcl, on M8/M9/AP, over the driver ring:
      PAD70GU  30 × 86.685   outer row, 42 insts   inboard edge never reaches the core rings
      PAD70NU  30 × 171.000  inner row, 40 insts   inboard edge at 171 / 1429 / 171 / 1829
      core ring stack occupies core_edge+2 .. core_edge+30  ->  175 / 1425 / 175 / 1825
      clearance = 4.00 µm every side.  This is why CORE_TO_IO is 70.  See 03-floorplan §2.
```

---

## 2. floorplan.tcl, in order

Line numbers are from the current file. Lines 1–78 are the header comment, covered by
[03-floorplan](../03-floorplan.md); the executable content starts at line 79.

### 2.1 `create_floorplan` (lines 79–81)

```tcl
79  set CORE_TO_IO 70
80  create_floorplan -site core -die_size 1600 2000 \
81      $CORE_TO_IO $CORE_TO_IO $CORE_TO_IO $CORE_TO_IO
```

**What it does.** Per TCRcom/create_floorplan.html, `create_floorplan` "initializes the floorplan
and calls the `add_tracks` command to create new routing tracks. By default the `add_tracks`
command calculates the optimum spacing between tracks and **ignores the pitch values in the tech
LEF**." The run log confirms both halves — `Start create_tracks` appears immediately after line
81, and nothing in this repo ever calls `add_tracks` explicitly.

**Options used.**

| Option | Meaning per the manual | Why here |
|---|---|---|
| `-site core` | "Specifies a core row site." | Picks the 0.2 × 1.8 `core` site over `bcore`/`ccore`/`dcore`/`gacore`, which are 2×/3×/4×-height variants in the same tech LEF. Without it Innovus would have to guess. |
| `-die_size w h l b r t` | die width, height, then the four **core-to-IO** margins | Fixes the die at 1600 × 2000 and the margins at 70. |

**Options deliberately not used, and their defaults** — all four matter and all four are silently
load-bearing:

| Default in force | Value | Effect here |
|---|---|---|
| `-core_margins_by` | `io` | The four 70s are core-to-IO. Passing `die` would put the core box at (70,70) and drop it straight through the pad ring. |
| `-floorplan_origin` | `llcorner` | Die anchored at (0,0). This is why the macro coordinates below are absolute-and-meaningful, and why growing the die cannot rescue a macro that has fallen out of the core. |
| `-flip` | `f` | First row flipped; rails abut. |
| `-die_size_by_io_height` | `min` | Irrelevant here — every pad in this design is 135 µm, so min = max. It would matter if a mixed-height pad were ever added. |

**Syntax note.** The manual gives `-die_size { w h left bottom right top }` with `Data_type: list`
and shows it braced. This script passes six bare words. Innovus 21.11 accepts it — the resulting
boxes in the `.fp` are exactly right — but it is not the documented form, and it is why the line
needs a backslash continuation. Brace it if you touch it.

**Warning it emits.** Every run prints, once, immediately after line 81:

```
**WARN: (IMPFP-325): Floorplan of the design is resized. All current create_floorplan objects
are automatically derived based on specified new create_floorplan. This may change blocks,
fixed standard cells, existing routes and blockages.
```

This is expected on a first floorplan (there was nothing to resize) and is the reason line 118
exists — see §2.5. There is no `IMPFP-325.html` in the installed message tree.

### 2.2 `delete_io_fillers` (line 84)

```tcl
84  delete_io_fillers
```

Per TCRcom/delete_io_fillers.html this "Deletes I/O filler cell instances from the design. Use
this command after filler cells have been added using the `add_io_fillers` command." On a fresh
run there are none, and the log says so:

```
No cell name specified, will delete physical io cells with CLASS PAD SPACER only.
Total 0 cells are deleted.
```

With no `-cell` list it deletes only `CLASS PAD SPACER` cells, so it cannot touch the 82 signal
pads or the 4 corners. **Why it is here:** idempotence. `floorplan.tcl` is sourced, and re-sourcing
it in an interactive session without this line would stack a second full set of 325 fillers on top
of the first. It is a no-op in the batch flow and insurance in the interactive one.

### 2.3 `read_io_file` (line 85)

```tcl
85  read_io_file ../scripts/nanosoc_eth_chiplet_pads.io
```

Loads the IO assignment file (format annotated in [§4](#4-the-io-file)). It places all 82 netlist
pad instances and **creates** the four corner cells.

**The trap in this line.** The manual's first note:

> By default, the `read_io_file` command will automatically adjust the die size to accommodate all
> the IOs. **If this command is used after floorplanning, it would change the die size defined in
> the floorplan file.** If you do not want the die size to be automatically adjusted, use the
> `-no_die_size_adjust` parameter.
> — TCRcom/read_io_file.html

This command *is* used after floorplanning — four lines after it. `-no_die_size_adjust` is **not**
passed. So line 85 is licensed by the manual to overwrite the 1600 × 2000 set on line 80, and the
only reason it does not is that the current pad set happens to fit. Verified: `Head Box` in the
saved `.fp` is still `0 0 1600 2000`, so on today's netlist nothing moved. Add pads to a side, or
widen `space`, and the die silently grows — and because the die is a fixed reticle commitment for
this shuttle, that is a defect that would surface as a size mismatch at submission rather than as
an error here. **`-no_die_size_adjust` belongs on this line.** (Flagged, not fixed: this page does
not modify the flow.)

Also unused: `-specified_ios_only`, which "enables you to place IO cells listed in the I/O
assignment file without deleting or moving the IO cells not listed". Not needed — the file lists
every pad.

### 2.4 `add_io_fillers` × 24 (lines 87–115)

```tcl
87  add_io_fillers -cells PFILLER20_G -prefix FILLER -side n
88  add_io_fillers -cells PFILLER20_G -prefix FILLER -side e
89  add_io_fillers -cells PFILLER20_G -prefix FILLER -side s
90  add_io_fillers -cells PFILLER20_G -prefix FILLER -side w
    …
115 add_io_fillers -cells PFILLER0005_G -prefix FILLER -side w
```

Six cell sizes × four sides. Per TCRcom/add_io_fillers.html the command "Adds I/O instances in the
I/O box. The I/O instances are added between the gap of existing I/O pad instances where the gap is
large enough for the I/O instance."

**`-side n` is undocumented.** Both the stylus page and the legacy `innovusTCR/addIoFiller.html`
document `-side {top | bottom | left | right}` and nothing else. The script passes `n`/`e`/`s`/`w`.
Innovus accepts them and maps them correctly — the log resolves the compass letter to the manual's
word in its own output:

```
@file 87: add_io_fillers -cells PFILLER20_G -prefix FILLER -side n
Added 32 of filler cell 'PFILLER20_G' on top side.
```

It works, on this version, but you are relying on an alias that appears in no manual on this
site. If a version bump ever tightens the enum, all 24 lines fail at once.

**Why largest-first, quantified.** The descending order (20 → 10 → 5 → 1 → 0.5 → 0.005 µm) is a
greedy fill: a small cell placed first fragments a gap so the large ones no longer fit. The actual
per-side arithmetic falls out exactly, and is worth showing because it also explains which of these
24 lines are dead:

| Side | pads | pad width | gap source | gap | pitch | `20` | `10` | `5` | `1` | `05` | `0005` |
|---|---|---|---|---|---|---|---|---|---|---|---|
| n (top) | 17 | 25 | per-inst `space=55` | 55 | 80 | 32 | 18 | 17 | 0 | 0 | 0 |
| e (right) | 22 | 25 | per-inst `space=55` | 55 | 80 | 42 | 23 | 22 | 0 | 0 | 0 |
| s (bottom) | 17 | 25 | per-inst `space=55` | 55 | 80 | 32 | 18 | 17 | 0 | 0 | 0 |
| w (left) | 26 | 25 | **global `space=42`** | 42 | 67 | 50 | 2 | 2 | **50** | 0 | 0 |
| | **82** | | | | | **156** | **61** | **58** | **50** | **0** | **0** |

Every number reproduces from first principles:

- 55 = 20 + 20 + 10 + 5. Top has 16 inter-pad gaps → 32 / 16 / 16, plus 15 µm before the first pad
  (x = 150 vs IO box 135) = 10 + 5, plus 10 µm after the last (1430 + 25 = 1455 vs 1465) = 10.
  Totals 32 / 18 / 17. Matches the log exactly. Right side: 21 gaps → 42 / 21 / 21, same end
  slivers → 42 / 23 / 22. Matches.
- 42 = 20 + 20 + 1 + 1. Left has 25 gaps → 50 / 0 / 0 / 50, plus 15 µm at each end = (10 + 5) × 2
  → 2 / 2. Matches.

**Total 325 fillers.** 325 + 82 pads + 4 corners = **411**, which is exactly the `#ioInst=411`
the placer reports. The IO ring is fully closed with no unfilled sliver.

**Eight of the 24 calls are dead and two more nearly so.** `PFILLER05_G` (0.5 µm) and
`PFILLER0005_G` (0.005 µm) add **zero** cells on all four sides, and `PFILLER1_G` adds zero on
three of four. They cost nothing but they are noise, and their presence implies a fill problem that
does not exist. The only reason `PFILLER1_G` is needed at all is the left side's 42 µm gap: had the
generator used `space=45` there like a 20+20+5 decomposition, or 50, the 1 µm cell would be
unnecessary. That is a property of the `.io` file, not of this script.

**A manual precondition this flow violates.** From the same page:

> **Note**: Before using `add_io_fillers`, run the `connect_global_net` command to provide
> global-net-connection rules for supply pins of the added fillers. Without these rules, the
> built-in design-rule checks of `add_io_fillers` will not be accurate.

The four `connect_global_net` calls live in `power_plan.tcl:46–49`, which `2_pnr_setup.tcl` sources
at line **47** — *after* `floorplan.tcl` at line 46. So all 24 `add_io_fillers` calls run before any
global net rule exists, and their built-in DRC is, by the manual's own statement, not accurate.
Nothing has visibly gone wrong (the fillers are geometrically correct and PG connection happens
later anyway), but the checking those 24 lines appear to be doing is not happening. *Inference:*
the fix is to move the four `connect_global_net` lines out of `power_plan.tcl` into
`2_pnr_setup.tcl` ahead of the floorplan source; not attempted here.

Options not used: `-fill_any_gap` (would force a filler into a too-small gap — correctly avoided),
`-filler_orient` (defaults `r0`; the tool orients per side anyway), `-from`/`-to` (range limiting),
`-logic`/`-derive_connectivity` (these fillers are physical-only and should not enter the netlist).

### 2.5 `unplace_obj -blocks` (line 118)

```tcl
118 unplace_obj -blocks
```

"Unplaces all blocks from the floorplan" (TCRcom/unplace_obj.html). The 21 macros arrive from
`read_netlist` unplaced anyway, so on a batch run this does nothing. It exists for two cases:
re-sourcing the file interactively, and the `IMPFP-325` resize path, where `create_floorplan`
"automatically derives" existing block positions against the new boxes rather than leaving them
where you put them. Clearing them first means every macro position below comes from this file and
only this file. Cheap, and it removes a whole class of "why is this macro 3 µm off" question.

### 2.6 `create_place_halo` (line 119)

```tcl
119 create_place_halo -halo_deltas {3.6 3.6 3.6 3.6} -all_macros
```

"A halo is an area that prevents the placement of standard cells within the specified halo distance
from the edges of a hard macro… in order to reduce congestion" (TCRcom/create_place_halo.html).
`-all_macros` = "Add halo around all hard macros" — all 21, with no name list to go stale.

`-halo_deltas` is ordered **left bottom right top**, and the manual is emphatic about a subtlety
that does not bite here:

> Halo deltas are specified in relation to a block in **R0 orientation**… For non-R0, the halo
> deltas are rotated/flipped according to the block's orientation (for block oriented MY, the left
> halo delta specifies the width of the halo along the right side of the inst in the floorplan).

Nine of the 21 macros are `MX`, `MY` or `R180`, so if the four deltas were ever made asymmetric
they would land on unexpected edges. Because all four are 3.6 the rotation is a no-op, and
`-orient` is correctly not passed. **Keep them equal, or work out the rotation per macro.**

**Why 3.6.** No comment says. *Inference, but a strong one:* 3.6 = 2 × 1.8 = exactly two core rows,
and 18 × 0.2 = exactly 18 sites. The halo is therefore commensurate with the placement grid in both
axes, so it removes whole rows and whole sites rather than leaving unusable fractions. 3.6 is also
the `bcore` double-height site's row pitch in the same tech LEF. `-snap_to_site` is not passed and
is not needed for the same reason.

Confirmed in the database: every one of the 21 `Block:` records carries
`3.6000 3.6000 3.6000 3.6000`, and the row splits in §1.2 land on macro edge ± 3.6 to the micron.

### 2.7 `proc place_macro` (lines 140–187)

The wrapper is the interesting part of this file. It is 47 lines around a single `place_inst`.

**Resolution (lines 147–156).**

```tcl
147     set hits {}
148     foreach i [get_db insts $pattern] {
149         if {[get_db $i .base_cell.base_class] eq "block"} { lappend hits $i }
150     }
151     if {[llength $hits] != 1} {
152         error "place_macro: pattern '$pattern' matched [llength $hits] instances, expected exactly 1. …"
```

`get_db insts <pattern>` glob-matches every instance, standard cells included; the
`.base_cell.base_class == block` test is what makes the "exactly 1" assertion meaningful. The
comment's reasoning — that a region glob returns the macro plus ~50 leaf cells — is sound. Note the
predicate is the same one `probe_macros.tcl:35` uses via `-if`, so the two agree by construction.

Why patterns at all is settled by the resolved names in the database, which show the ungrouping
that the header comment describes, in one screen:

```
u_nanosoc_eth_chiplet_chip_u_soc_u_soc/u_network_core/u_region_imem_0_u_mem_u_sram_gen_rf_32k.u_rf_sp_hdf
u_nanosoc_eth_chiplet_chip_u_soc_u_soc/u_chip_core_u_region_imem_0_u_mem_u_sram_gen_rf_16k.u_rf_sp_hdf
u_nanosoc_eth_chiplet_chip_u_soc_u_tidelink/u_tidelink_fifo_u_fifo_mem_u_sram_u_rf
```

`u_network_core` survives as a **hierarchy level** (`/`), `u_chip_core` has been flattened into an
underscore-joined leaf name, and `u_tidelink` sits under a different parent entirely. A path-based
list has to encode all three conventions correctly and re-encode them every time Genus changes its
mind. The globs step over `/` and `_` alike and do not care.

**Placement (lines 157–158).**

```tcl
157     place_inst $inst $x $y $orient
158     set_db [get_db insts $inst] .place_status placed
```

Per TCRcom/place_inst.html: "Places a leaf instance in the core box. Instance is snapped to the
site whose lower-left corner is the nearest to the location specified… **Instance is not checked
for legality** – it can overlap other boxes, either placed or fixed, and it can be placed within
placement blockages."

Two things follow.

*Snapping.* The manual says the coordinates are snapped. Eleven of the 21 x-coordinates are not
multiples of 0.2 off the core edge and twenty of the 21 y-coordinates are not multiples of 1.8, so
in principle the placed positions could differ from the literal numbers by up to 0.1 µm in x and
0.9 µm in y. **They do not.** Every one of the 21 `Block:` records in the saved `.fp` carries the
script's number to four decimal places — `1222.3350 735.4650`, `1059.2000 209.9500`,
`1053.8000 1117.8100`. Hard macros are not snapped to the standard-cell row grid on this tool
version. Worth knowing, because it means the `## MOVED` deltas in the file reconstruct arithmetically
and the clearances computed on paper are the real ones.

*Legality.* "Not checked for legality" is the entire justification for guard 2 below, and for the
fact that nothing else in the flow would have caught five macros hanging outside the core.

**Line 158 is the one undocumented decision in this file.** `place_inst`'s status parameter
`{-fixed | -placed | -soft_fixed}` **defaults to `-fixed`**, and the manual distinguishes them:

> `place_inst SH22/I40 1500.3 980.3 my` — The instance SH22/I40 is **fixed** by default and the
> placement program will not move this instance later.
> `place_inst SH22/I51 398.7 1480.2 -placed` — The instance SH22/I52 has 'placed' status and **it
> can be moved** during optimization, clock synthesis, or `place_detail`.

Line 158 takes each macro straight back down from `fixed` to `placed` — i.e. it explicitly hands
the 21 hand-tuned macros back to the placer as movable. There is no comment saying why, and no
other line in the flow restores `fixed`. In practice they do not move (the `.fp` written after
`place_design` still has them at the authored coordinates, marked preplaced), most likely because
`preplace.tcl` leaves `place_design_floorplan_mode` at `false` so macro placement is never invoked.
But that is an undocumented coupling between two files, protecting a floorplan that took a
17-macro manual re-place to get right. See [§7](#7-fragile-or-unexplained).

**Guard: containment (lines 168–178).**

```tcl
168     lassign [lindex [get_db current_design .core_bbox] 0] cx1 cy1 cx2 cy2
169     lassign [lindex [get_db [lindex $hits 0] .bbox] 0] mx1 my1 mx2 my2
170     if {$mx1 < $cx1 || $my1 < $cy1 || $mx2 > $cx2 || $my2 > $cy2} {
```

Reads the core box from the design and the macro's bbox from the placed instance — i.e. *after*
placement, so it sees whatever the tool actually did rather than what was asked for. This is the
right way round and it is what makes the snapping question above moot in practice. The error text
names the overhang per edge and restates the `135 + CORE_TO_IO` derivation, which is the single
highest-value line of diagnostics in the floorplan.

**Publication (line 185).**

```tcl
185     lappend ::PLACED_MACROS $inst
```

`power_plan.tcl:145` hard-errors if this list is empty. That is the whole reason
`2_pnr_setup.tcl` must source floorplan (line 46) before power plan (line 47), and it removes a
duplicated 21-path list that had already drifted. See [03-floorplan §4.3](../03-floorplan.md#43-publishing-the-resolved-macro-list).

### 2.8 What is *not* in this file

Worth stating plainly, because the absences are all deliberate or at least consistent:

| Command | Status |
|---|---|
| `create_place_blockage` / `create_route_blockage` | **Never called** — not in `floorplan.tcl` nor anywhere in `ASIC/`. The saved `.fp` contains zero `Blockage` records; the section headers are present but empty. All standard-cell exclusion comes from the 3.6 µm halos and the macro bodies themselves. |
| `snap_floorplan` | Never called. Defensible: TCRcom/snap_floorplan.html frames it around the **FinFET grid**, and this is planar 65 nm with no `PROPERTYDEFINITIONS` fin pitch. `place_inst` and `read_io_file` do their own snapping. |
| `write_floorplan` | Never called. There is **no `.fp` checkpoint artefact** in the flow. The floorplan survives only inside the `write_db` output (`work/<block>/<block>.fp.gz`, which `write_db` produces internally — that is the file quoted throughout this page). You cannot diff two floorplans without unzipping two databases. Adding `write_floorplan` after line 209 would cost seconds and make floorplan changes reviewable. |
| `add_rings` / `add_stripes` | Correctly in `power_plan.tcl`, not here. `add_rings … -follow core` tracks the core box automatically, which is why a `CORE_TO_IO` change needs no edit there — only a re-check of the bond-pad clearance. |
| `check_place` | Never called. TCRcom/place_inst.html explicitly points at it: "You can check the legality of the placed instance by the `check_place` command." The hand-rolled containment guard is stricter about the core box but says nothing about macro-on-macro overlap, which `check_place` would catch. |

---

## 3. The 21 macros

Read from `floorplan.tcl:189–209`. Instance names and orientations are the **resolved** ones from
the saved database, so the pattern → instance mapping below is observed, not guessed. Cell sizes
are from the vendor LEFs; every macro is `CLASS BLOCK`, `SYMMETRY X Y R90`.

| # | Line | Pattern | Resolved instance (parent path elided) | Master | `SIZE` µm | x | y | Orient |
|---|---|---|---|---|---|---|---|---|
| 1 | 189 | `*ethmac*bd_ram*u_rf` | `u_network_core/u_ethmac_0_…_bd_ram_u_sram_u_rf` | `rf_01k` | 177.4 × 58.99 | 1053.800 | 1117.810 | R180 |
| 2 | 190 | `*u_network_core*u_region_bootrom_0*rom_via*` | `u_network_core/u_region_bootrom_0_u_bootrom_u_rom_via` | `eth_rom_via` | 164.665 × 59.735 | 883.535 | 1538.600 | MY |
| 3 | 191 | `*u_network_core*u_region_dmem_0*rf_16k*` | `u_network_core/u_region_dmem_0_…gen_rf_16k.u_rf_sp_hdf` | `rf_16k` | 311.8 × 285.25 | 1058.600 | 1340.400 | MY |
| 4 | 192 | `*region_eth_scratch_rx_0*` | `u_network_core/u_region_eth_scratch_rx_0_…gen_rf_08k.u_rf_sp_hdf` | `rf_08k` | 311.8 × 154.09 | 590.200 | 1338.800 | R0 |
| 5 | 193 | `*region_eth_scratch_tx_0*` | `u_network_core/u_region_eth_scratch_tx_0_…gen_rf_08k.u_rf_sp_hdf` | `rf_08k` | 311.8 × 154.09 | 1049.800 | 1633.800 | MY |
| 6 | 194 | `*u_network_core*u_region_imem_0*rf_32k*` | `u_network_core/u_region_imem_0_…gen_rf_32k.u_rf_sp_hdf` | `rf_32k` | 585.38 × 285.28 | 290.800 | 1503.400 | R0 |
| 7 | 195 | `*way1_cache_ram_tag_ram_0_i` | `u_qspi_flash_0_…_way1_cache_ram_tag_ram_0_i` | `flash_cache_tag` | 135.4 × 40.51 | 911.200 | 468.690 | MX |
| 8 | 196 | `*way0_cache_ram_tag_ram_0_i` | `u_qspi_flash_0_…_way0_cache_ram_tag_ram_0_i` | `flash_cache_tag` | 135.4 × 40.51 | 898.800 | 402.090 | MX |
| 9 | 197 | `*way0_…_word_2_i` | `u_qspi_flash_0_…_way0_cache_ram_data_ram_0_word_2_i` | `flash_cache_data` | 311.8 × 36.36 | 553.800 | 480.400 | R0 |
| 10 | 198 | `*way0_…_word_3_i` | ″ `word_3_i` | `flash_cache_data` | 311.8 × 36.36 | 516.600 | 390.040 | MX |
| 11 | 199 | `*way0_…_word_0_i` | ″ `word_0_i` | `flash_cache_data` | 311.8 × 36.36 | 702.400 | 300.040 | MX |
| 12 | 200 | `*way0_…_word_1_i` | ″ `word_1_i` | `flash_cache_data` | 311.8 × 36.36 | 718.800 | 345.040 | MX |
| 13 | 201 | `*way1_…_word_2_i` | `u_qspi_flash_0_…_way1_cache_ram_data_ram_0_word_2_i` | `flash_cache_data` | 311.8 × 36.36 | 633.600 | 527.200 | R0 |
| 14 | 202 | `*way1_…_word_3_i` | ″ `word_3_i` | `flash_cache_data` | 311.8 × 36.36 | 564.400 | 435.040 | MX |
| 15 | 203 | `*way1_…_word_0_i` | ″ `word_0_i` | `flash_cache_data` | 311.8 × 36.36 | 708.600 | 210.040 | MX |
| 16 | 204 | `*way1_…_word_1_i` | ″ `word_1_i` | `flash_cache_data` | 311.8 × 36.36 | 727.800 | 255.040 | MX |
| 17 | 205 | `*u_chip_core*u_region_imem_0*rf_16k*` | `u_chip_core_u_region_imem_0_…gen_rf_16k.u_rf_sp_hdf` | `rf_16k` | 311.8 × 285.25 | 1059.200 | 209.950 | R180 |
| 18 | 206 | `*u_shared_sram_0*rf_08k*` | `u_shared_sram_0_…gen_rf_08k.u_rf_sp_hdf` | `rf_08k` | 311.8 × 154.09 | 1052.400 | 506.710 | R180 |
| 19 | 207 | `*u_chip_core*u_region_dmem_0*rf_08k*` | `u_chip_core_u_region_dmem_0_…gen_rf_08k.u_rf_sp_hdf` | `rf_08k` | 311.8 × 154.09 | 1050.400 | 953.600 | R0 |
| 20 | 208 | `*u_chip_core*u_region_bootrom_0*rom_via*` | `u_chip_core_u_region_bootrom_0_u_bootrom_u_rom_via` | `rom_via` | 164.665 × 59.735 | 1222.335 | 735.465 | R180 |
| 21 | 209 | `*u_tidelink*u_tidelink_fifo_u_fifo_mem_u_sram_u_rf` | `u_…_u_tidelink/u_tidelink_fifo_u_fifo_mem_u_sram_u_rf` | `rf_16k` | 311.8 × 285.25 | 230.600 | 1210.000 | R0 |

Total macro area 757,805 µm² = **40.1 %** of the 1,892,100 µm² core. Every orientation in use is
`R0`/`R180`/`MX`/`MY`, none of which swaps width and height, so bbox = (x, y) – (x+W, y+H)
throughout.

### 3.1 What the placement is actually doing

Three functional clusters, legible from the coordinates:

- **Top band (y > 1100), the network/Ethernet side** — macros 2–6 plus the tidelink FIFO. The
  `rf_32k` net imem (the largest macro, 585 × 285) occupies the top-left; the eth scratch RX/TX
  pair, net dmem and net bootrom fill the top-right. The tidelink FIFO at (230.6, 1210) sits
  directly under the `rf_32k`, on the left edge — the same side as all 26 TideLink pads.
- **Bottom-left cluster (y 210–563), the QSPI cache** — ten macros in a diagonal staircase, close
  to the QSPI pads on the bottom edge.
- **Right column (x ≈ 1050–1387), the chip core** — chip imem, shared SRAM, chip dmem and chip
  bootrom stacked vertically at y = 210, 507, 954, 735.

Those groupings are consistent with pad-proximity and are almost certainly why they are where they
are. **But that is inference from the coordinates, not from the file.** Say it plainly:

> **Not one of the 21 base coordinates has a recorded rationale.** The only comments on lines
> 189–209 are the seventeen `## MOVED <delta>` notes, and every one of those explains a *delta*
> applied during the `CORE_TO_IO` 50 → 70 re-place — not the position it was applied to. The
> underlying floorplan is hand-tuned, and the record of how it was arrived at does not exist in
> this repository.

That is a real gap. Four of the seventeen notes ("QSPI cache stack moves up as one block", "follows
chip imem, keeps the 11.51 gap", "follows net imem, keeps the 8.15 gap") do document a *constraint*
between macros, and those are the only inter-macro relationships written down anywhere. The 8.64 µm
inter-RAM gap in the QSPI stack (45 µm pitch, 36.36 µm tall cells) is recoverable from the numbers;
nothing else is.

### 3.2 Clearance to the core edge

Computed from the table against the core box (205, 205) – (1395, 1795). Tightest five:

| Macro | Edge | Clearance |
|---|---|---|
| chip imem `rf_16k` (#17) | bottom | **4.95 µm** |
| QSPI way1 `word_0` (#15) | bottom | **5.04 µm** |
| net imem `rf_32k` (#6) | top | **6.32 µm** |
| eth_scratch_tx (#5) | top | **7.11 µm** |
| chip bootrom `rom_via` (#20) | right | **8.00 µm** |

All five exceed the 3.6 µm halo, so no halo is clipped by the core boundary. All five are under
10 µm. A further +5 µm on `CORE_TO_IO` would put two macros outside the core immediately.

---

## 4. The `.io` file

### 4.1 What the format is

Per the Innovus Stylus Common UI User Guide, Data Preparation chapter
(`UGcom/Data_Preparation.html`, "Generating the I/O Assignment File"):

> The I/O assignment file defines the rules that determine how the I/O instances (pad cells and
> area I/O), I/O pins, bumps, and bump arrays are organized. The file is **rule-based** to specify
> exact location, global spacing, individual spacing, skip, offset, keep clear, and corner
> information. You can specify detailed rules to control the locations, or you can specify minimal
> or no rules to allow Innovus to determine the locations automatically.

It is a nested s-expression, not Tcl. The statements this file uses:

| Statement | Manual definition (UGcom/Data_Preparation.html) | Here |
|---|---|---|
| `(globals … )` | file-level defaults | lines 16–20 |
| `version = 3` | "Specifies the beginning of a new I/O format." | 3 |
| `space` (global) | "Specifies the global I/O pin spacing, in µmeters." | **42** |
| `io_order` | `clockwise` / `counterclockwise` / `default`. "The default I/O order for a **vertical edge is from the bottom to the top**, and for a **horizontal edge, it is from the left to the right**." | `default` |
| `(iopad … )` | container for the side and corner blocks | lines 21–127 |
| `(top\|bottom\|left\|right … )` | one side | 4 blocks |
| `(topleft\|topright\|bottomleft\|bottomright … )` | one corner | 4 blocks |
| `inst name=` | "Specifies the name of the I/O instance." | all 86 |
| `offset=` | "Specifies the distance in microns from the IO ring edge to the pad edge based on `io_order` constraint. Valid only for this cell." | `150`, once per side |
| `space=` (per-inst) | "Specifies the spacing, in µmeters, between the pad being defined and the previously defined pad. Overrides the global space setting." | `55` on N/E/S |
| `orientation=` | "Specifies the orientation of the I/O." | corners only |
| `place_status=` | `placed` / `covered` / `fixed`. "**Default: fixed.**" | `fixed`, all 82 |

Three consequences the manual spells out and this file leans on:

1. **`place_status=fixed` on all 82 pads is redundant** — `fixed` is already the default. Harmless,
   and arguably good documentation.
2. **Only one of `skip`, `space`, `offset` may be given per pad.** "If you specify all the three
   parameters, only the last parameter that you define is considered." This file never combines
   them: each side gives `offset=` on its first pad and `space=` on the rest (or on none, on the
   left, where the global 42 applies). Correct usage.
3. **"You must define pad cells in the order in which they appear in the design."** With
   `io_order = default`, the left and right blocks are read **bottom-to-top** and the top and
   bottom blocks **left-to-right**. So `uPAD_TL_RX_0`, listed first in `(left)`, is the
   *bottom-most* pad on the left edge — confirmed at y = 150 in the placed database.

### 4.2 The structure of this file

```
(globals space=42 io_order=default)
(iopad
  (topleft      1 × PCORNER_G  R90 )
  (top         17 pads, offset=150 then space=55 × 16)
  (bottomleft   1 × PCORNER_G  R180)
  (left        26 pads, offset=150 then global space=42 × 25)
  (bottomright  1 × PCORNER_G  R270)
  (bottom      17 pads, offset=150 then space=55 × 16)
  (topright     1 × PCORNER_G  R0  )
  (right       22 pads, offset=150 then space=55 × 21)
)
```

**`offset=150` is measured from the die edge, not the IO box.** The manual says "from the IO ring
edge", which is ambiguous with an IO box at 135. The database settles it: the first top pad sits at
x = **150.0000** exactly, i.e. 150 from x = 0, and 15 µm inboard of the `PCORNER_G` that ends at
x = 135. Same on all four sides.

**Corner cells are created by this file, not by the netlist.** The four corner entries are the only
ones carrying `cell=`:

```
(inst name="uPAD_CORNER_TL" orientation=R90 cell=PCORNER_G)
```

`grep -c PCORNER_G` on `outputs/nanosoc_eth_chiplet_pads_gate_power.v` returns **0**, while the
netlist holds exactly 82 `uPAD_*` instances. The four corners exist only because this file names a
cell for them, and `read_io_file` instantiates them. Delete those four lines and the ring opens at
the corners with no error from the netlist side. Note that `cell=` does *not* appear in the manual's
`iopad instance` attribute table (which lists `name`, `x`/`y`, `skip`, `space`, `offset`, `indent`,
`orientation`, `place_status`, `keepclear`) — it is documented for `bump` records only. It works;
it is undocumented for pads on this version.

**Corner orientation convention.** `TR = R0`, `TL = R90`, `BL = R180`, `BR = R270` — i.e. +90° of
counter-clockwise rotation (`R90` = "Rotate counter-clockwise 90 degrees",
UGcom/Floorplanning_the_Design.html "Orientation Key") for each step **clockwise** around the die
starting from the top-right. All four verified in the placed database at (1465,1865), (0,1865),
(0,0) and (1465,0), each 135 × 135.

**Pad cell inventory** (from the placed database, 82 pads + 4 corners):

| Cell | Count | Role |
|---|---|---|
| `PDDW16DGZ_G` | 36 | 16 mA bidirectional driver |
| `PVSS2DGZ_G` | 12 | VSSIO |
| `PDDW04DGZ_G` | 9 | 4 mA driver |
| `PVDD2DGZ_G` | 8 | VDDIO |
| `PVDD1DGZ_G` | 6 | VDD core |
| `PVSS1DGZ_G` | 4 | VSS core |
| `PVDD2POC_G` | 4 | VDDIO **with power-on control clamp** |
| `PCORNER_G` | 4 | corners |
| `PDUW16DGZ_G` | 2 | 16 mA with pull-up (I2C SCL/SDA) |
| `PDUW08DGZ_G` | 1 | 8 mA with pull-up (SWDIO) |

Exactly **one `PVDD2POC_G` per side**, and in every case it is the **first** pad in that side's
list (`uPAD_VDDIO_T_0`, `_L_0`, `_B_0`, `_R_0`). That is an ESD/POC ring requirement, and it means
the per-side ordering in this file is not arbitrary even where it looks it: reordering a side so
that the POC cell is no longer present is a real error that this flow will not catch.

### 4.3 How it feeds the bond ring

[`place_bondpads.tcl`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/place_bondpads.tcl) carries eight
hand-written lists (`<side>_pads_outer` / `<side>_pads_inner`) and attaches one bond pad to each
driver pad with `create_relative_floorplan`. Those lists are **derived from this file's per-side
order by strict alternation** — verified mechanically on all four sides:

| Side | `.io` pads | odd positions → `PAD70GU` (outer) | even positions → `PAD70NU` (inner) | alternates? |
|---|---|---|---|---|
| top | 17 | 9 | 8 | **yes, exactly** |
| left | 26 | 13 | 13 | **yes, exactly** |
| bottom | 17 | 9 | 8 | **yes, exactly** |
| right | 22 | 11 | 11 | **yes, exactly** |
| | 82 | **42** | **40** | |

That is what "staggered" means here: pads 1, 3, 5, … get the short outer bond pad and pads 2, 4,
6, … get the tall inner one, so the two rows interleave and the bond pitch is half the pad pitch.

**The coupling is silent and it runs in the wrong direction.** Insert one pad into a side of this
`.io` file and the alternation inverts for every pad after it, so half that side's bond pads swap
rows. `place_bondpads.tcl` would place them happily — its lists are literal names, it does not read
this file, and nothing cross-checks the two. The inner row is the one that nearly collides with the
core rings (03-floorplan §2), so a silent inversion is not cosmetic. *Inference:* the eight lists
should be generated from the `.io` per-side order at run time rather than maintained by hand; that
would make the alternation an invariant instead of a coincidence that currently happens to hold.

### 4.4 Provenance notes

- The header says `Design: nanosoc_chip_pads_tsmc65lp_multicore`. The block being implemented is
  `nanosoc_eth_chiplet_pads`. The generator's design name and the P&R block name do not match. It
  is a comment and has no effect, but it means this file was templated for a different top level.
- The header calls the `offset=` values "EVENLY-SPACED PLACEHOLDERS". That is slightly off: there
  is exactly one `offset=` per side (always 150) and the spacing is carried by `space=`. What is a
  placeholder is the **uniform 55 / 42 pitch**, not the offsets. In practice the uniform pitch has
  survived to the current database unchanged, so the "real placement is a PnR output" caveat has
  not yet come true.
- The left side is the only one using the global `space=42` rather than a per-instance `space=55`,
  because it carries 26 pads instead of 17–22 in the same 1730 µm. It is also the only side that
  needs `PFILLER1_G` (§2.4). *Inference:* the 42 is a fit constraint, not a choice.

---

## 5. preplace.tcl, postplace.tcl, probe_macros.tcl

### 5.1 `preplace.tcl` — 5 attributes, sourced at `2_pnr_setup.tcl:54`, immediately before `place_design`

```tcl
2  set_db design_process_node 65
3  set_db place_global_cong_effort auto
4  set_db place_global_timing_effort high
7  set_db place_global_uniform_density true
8  set_db place_detail_legalization_inst_gap 2
11 set_db place_design_floorplan_mode false
```

Every one of these is a **root attribute**, set with `set_db <attr> <value>` and readable with
`get_db <attr>` (TCRcom/place_Category_Attributes.html). Line by line:

**`design_process_node 65`** — "Specifies the process technology value to set for all the
applications. Units in nanometers (nm). **Default: 90**"
(TCRcom/design_Category_Attributes.html). Correct for this PDK, and it is what makes Innovus apply
its 65 nm capacitance-filtering recommendations (visible in the log immediately above this block).
**But it is already set**: `2_pnr_setup.tcl:44` runs `set_db design_process_node $process_node` with
`process_node = 65` from `config.tcl:3`. This line is a redundant re-assert of the same value.

**`place_global_cong_effort auto`** — `{low | medium | high | extreme | auto}`, **default `auto`**.
"Automatically determines whether the design is congested and performs extra congestion driven
effort for highly congested designs." **This line sets the attribute to its own default and does
nothing.**

**`place_global_timing_effort high`** — `{medium | high}`, default `medium`. "Specifies the level of
effort for timing driven global placer." Two caveats from the same page:

> **Note**: `place_global_timing_effort high` is **not recommended for congested designs**.

> This option is part of a **limited-access feature** in this release. It is enabled by a variable
> specified using the `set_limited_access_feature` command. To use this feature, contact your
> Cadence representative…

`set_limited_access_feature` appears nowhere in this repository. The attribute nevertheless takes —
the placer's own attribute dump in the log reads `place_global_timing_effort high` — so on this
version the gate is not enforced, or is satisfied by the site licence. The "not recommended for
congested designs" note is the more actionable one: the placer reports
`Density for the design = 0.807`, and [16-open-defects](../16-open-defects.md) records the
utilisation climbing to 92.2 %.

**`place_global_uniform_density true`** — default `false`. The manual's entire description is one
sentence:

> Enable even cell distribution for designs **with less than 70% utilization**.

This design is at **80.7 %** by the placer's own measure
(`stdcell_area 2366047 sites (851777 um^2) / alloc_area 2933092 sites (1055913 um^2)`), and
`Placement Density: 80.67%` post-place. The attribute is being used outside its documented
applicability range. It also has a side effect nobody asked for, which the log states explicitly:

```
**WARN: (IMPSP-196): User sets both -place_global_uniform_density and
-place_global_initial_padding_level options. Overriding -place_global_initial_padding_level to 5.
```

`place_global_initial_padding_level` is not set anywhere in this repository — setting
`uniform_density` implies it, and forces it to 5. So this one line silently adds cell padding to a
design already at 80.7 % density. There is no `IMPSP-196.html` in the message tree. **This is the
attribute in `preplace.tcl` most worth an experiment** (load the `_placed` DB, flip it, re-place,
compare congestion and density) and the least justified as written.

**`place_detail_legalization_inst_gap 2`** — "Specifies the minimum gap between instances
**(unit sites)**. Default: 0." Units are **sites, not microns**: 2 × 0.2 = **0.4 µm** minimum gap
between every adjacent pair of standard cells. The file's own comment calls this "fill gap", which
reads as though it were about filler insertion; it is not — it is a hard legalisation constraint
that costs area on every row. Combined with the forced padding level above, this design is paying
twice for cell spreading at 80.7 % density.

**`place_design_floorplan_mode false`** — default `false`. "Runs placement in the floorplan mode.
This mode is used for prototyping and runs quickly to gauge the feasibility of the netlist, but
might not place design components in legal locations." Another **no-op re-assert of the default**.

It is not entirely valueless: it is what keeps macro placement out of `place_design`, and therefore
what makes `floorplan.tcl:158`'s `place_status placed` downgrade harmless. The manual also notes
that setting it `true` "disables congestion-driven placement. Attribute `place_global_cong_effort`
is set to `low`" — i.e. it would silently override line 3. Documenting the intent explicitly is
defensible even though the value is the default; it should say so.

**Summary of `preplace.tcl`:** of six settings, two are exact no-ops (`cong_effort`,
`floorplan_mode`), one is a redundant re-assert (`process_node`), one is documented as a
limited-access feature and is not recommended at this design's congestion (`timing_effort high`),
one is documented as applying below 70 % utilisation and is used at 80.7 % with an undocumented
padding side effect (`uniform_density`), and one has a unit that the in-file comment gets wrong
(`legalization_inst_gap`). **One line of six is doing what it says without a caveat.**

### 5.2 `postplace.tcl` — sourced at `2_pnr_setup.tcl:64`, after `place_design`

```tcl
2 write_sdf design.sdf -ideal_clock_network
3 set_db add_tieoffs_max_fanout 10
4 add_tieoffs -lib_cell {TIEL TIEH} -prefix LTIE
```

**`write_sdf design.sdf -ideal_clock_network`.** `-ideal_clock_network` "Marks delays of delay arcs,
that are on the ideal clock networks, as 0 in the SDF file" (TCRcom/write_sdf.html). Correct
usage — at this point CTS has not run (it is in stage 3), so the clock network is ideal and writing
its delays would be a lie. Three problems with the line as it stands:

- The output path is a **bare relative filename**, so it lands in `work/` as `design.sdf` rather
  than in `$OUT_DIR` under `$block_name`, unlike every other artefact in the flow.
- It is **494 MB** and **nothing reads it**. `grep -rn design.sdf ASIC/` finds only this line and
  the three `innovus.cmd` echoes of it. Every baseline snapshot carries its own copy.
- It is a *pre-CTS, pre-route* SDF with zeroed clock arcs. Its analysis value is close to zero and
  it will be superseded by the post-route SDF. This looks like a debugging line that was left in.

**`set_db add_tieoffs_max_fanout 10`** — "Specifies the number of tie-pins a tie-net can drive.
A value of 0 implies no fanout constraint. Default: 0"
(TCRcom/add_tieoffs_Category_Attributes.html). So 10 tightens the default. The manual's own worked
example on that page is:

```tcl
set_db add_tieoffs_max_fanout 10
set_db add_tieoffs_max_distance 20
```

**`add_tieoffs_max_distance` is not set here**, and its default is also 0 = "no distance
constraint". The tool says so out loud:

```
Options: No distance constraint, Max Fan-out = 10.
```

With no distance cap, a tie cell may sit arbitrarily far from the pin it ties, which is a
DRV/EM concern on a 1600 × 2000 die. The counts are small enough that it is unlikely to matter here
(28 `TIEL` + 17 `TIEH` = 45 cells, and the tool reports `Re-routed 28 nets` / `Re-routed 17 nets`),
but the manual pairs the two attributes for a reason.

**`add_tieoffs -lib_cell {TIEL TIEH} -prefix LTIE`.** "Adds instances of specified tie-off cells to
the logical hierarchy of the design and connects the tie-off pins of netlist instances to the
tie-off pins of the added instances… **Use this command after placing the standard cells in the
flow**" (TCRcom/add_tieoffs.html). Placement is at `2_pnr_setup.tcl:56` and this is at line 64:
correct order.

`-lib_cell` — "You can only specify a maximum of two tie-cells, where one cell must be a tie-high
driver, and the other a tie-low driver." Two given, one of each. The manual writes the names in
quotes; braces work identically in Tcl. `-prefix LTIE` names the instances; the parameter default
would otherwise come from `add_tieoffs_prefix`.

### 5.3 `probe_macros.tcl` — diagnostic, never sourced by the flow

41 lines, 26 of them header. It exists because `place_macro`'s error message tells you to run it.

```tcl
26 source ../scripts/config.tcl
27 soclabs_setup_multi_cpu
28 set_db init_power_nets $power_nets
29 set_db init_ground_nets $ground_nets
30 read_mmmc ../scripts/${block_name}.mmmc
31 read_physical -lef $lef_file_list
32 read_netlist $OUT_DIR/${block_name}_gate_power.v
33 init_design
```

Lines 26–33 are `2_pnr_setup.tcl:14–38` with the DFT `read_def` branch dropped, stopping at
`init_design`. That is the minimum needed for `get_db insts` to return real instances: LEF gives
Innovus the cell classes (so `.base_cell.base_class` is populated), the netlist gives the instances,
`init_design` builds the database. It does not floorplan, does not read the CPF, and writes no
database — so it costs a few minutes and cannot corrupt anything.

```tcl
34 set fh [open ../logs/macro_insts.txt w]
35 foreach i [get_db insts -if {.base_cell.base_class == block}] {
36     puts $fh "[get_db $i .name]  ->  [get_db $i .base_cell.name]"
37 }
38 close $fh
39 puts "PROBE_DONE count=[llength [get_db insts -if {.base_cell.base_class == block}]]"
40 exit
```

`get_db insts -if {…}` is the stylus filter form; the predicate is the same `base_class == block`
test `place_macro` applies in Tcl. Output is `name -> master`, which is exactly the pair you need to
repair a pattern (the name to match, and the master to confirm you matched the right thing). Line 39
prints a machine-greppable sentinel so a wrapper can distinguish "ran and found N" from "died"; on
today's netlist N is 21. Line 40 `exit` is what makes the `< /dev/null` in the header advice
sufficient rather than necessary — without a fatal error the script terminates on its own.

The header's two operational warnings are both real:

- `TSMC_65_HOME` and `NANOSOC_ETH_CHIPLET_HOME` are exported by `ASIC/common.mk`, so a bare shell
  does not have them and `config.tcl` dies on `$::env(TSMC_65_HOME)`.
- `< /dev/null` — on any error before line 40, Innovus drops to its interactive prompt and holds
  the licence until killed.

**One inconsistency:** `place_macro`'s error text (line 154) says "re-run
`scripts/probe_macros.tcl`", but this script writes `../logs/macro_insts.txt` and must be run from
`work/`. The header gets it right; the error message does not say where to run it from.
`logs/macro_insts.txt` does not currently exist, so nobody has needed it since the pattern rewrite.

---

## 6. Dependency map: what moves when the geometry moves

[03-floorplan §5](../03-floorplan.md#5-worked-procedure-changing-the-core-to-io-margin) gives the
conceptual procedure and the real worked example (`CORE_TO_IO` 50 → 70, core 1230×1630 → 1190×1590,
17 of 21 macros re-placed). This is the mechanical checklist that goes with it: **for each
consumer, does it track the geometry automatically, or must a human edit it?**

`grep -rn 'CORE_TO_IO\|1600\|1395\|1795' ASIC/**/*.tcl` finds hits in **`floorplan.tcl` only** —
no other script hardcodes a die or core coordinate. That is the good news. The bad news is the list
below.

### Tracks automatically — do not touch

| Consumer | Why it is safe |
|---|---|
| Core rows / tracks | `create_floorplan` regenerates both. Row count changes (883 at margin 70); nothing references a row index. |
| `power_plan.tcl:55` `add_rings … -follow core` | `-follow core` re-derives from the current core box. The ring **geometry** needs no edit. |
| `power_plan.tcl` `split_row` / macro connection | Driven by `::PLACED_MACROS`, published by `place_macro` at run time. |
| `create_place_halo -all_macros` | No name list, no coordinates. |
| `nanosoc_eth_chiplet_pads.io` | Keyed off **die** edges and the IO box, both of which are functions of the die size and pad height, not of `CORE_TO_IO`. Unaffected by a margin change; affected by a **die-size** change. |
| `place_bondpads.tcl` | `create_relative_floorplan` positions each bond pad relative to its **driver pad**, which lives in the IO ring. Unaffected by a margin change; affected by a die-size change. |
| `filler.tcl`, `route_setup.tcl` | No geometry constants. |

### Must be edited by hand

| # | Thing | Where | What to do |
|---|---|---|---|
| 1 | `CORE_TO_IO` | `floorplan.tcl:79` | The one line you actually meant to change. |
| 2 | **All 21 macro coordinates** | `floorplan.tcl:189–209` | Absolute die coordinates. They do not track the core box, and because the die is anchored at `llcorner` the core's lower-left moves *inward* as the margin grows — so macros near the **bottom and left** fall out even though nothing about them changed. Enlarging the die does not help. |
| 3 | Ring-to-bond-pad clearance | arithmetic, not a file | `ring_outer = 135 + CORE_TO_IO + 30` (offset 2 + width 12 + spacing 4 + width 12, from `add_rings` at `power_plan.tcl:55`) vs `PAD70NU` inboard at 171 / 1429 / 171 / 1829. Require at least the M9 `SPACING` (read it from the tech LEF — not reproduced here, TSMC licence). At 70 it is 4.00. **This is the number the whole change exists to fix** — re-derive it, do not assume. |
| 4 | The header comment | `floorplan.tcl:1–78` | 78 lines of prose asserting specific values (155/1445, 175/1425, 16.00, 4.00, 580, 318, 102). Wrong prose here is worse than none — it is what the next person will trust. |
| 5 | `preplace.tcl:7` | `place_global_uniform_density` | Utilisation rises as the core shrinks. It is already used above its documented 70 % ceiling at 80.7 %; a further margin increase pushes it further out. |
| 6 | Row-sliver arithmetic | §1.2 | Only if you care. 883 rows at margin 70 leaves 0.6 µm; a different margin leaves a different sliver. |

### The order to do it in

1. Edit `floorplan.tcl:79`.
2. Recompute item 3 on paper. If the clearance is not ≥ 2 µm, stop — you have picked the wrong
   number and nothing downstream will tell you.
3. Compute the new core box: `(135+M, 135+M) – (1465−M, 1865−M)`.
4. Do **not** try to fix the macros by inspection. Run `make pnr_place` and let the containment
   assertion at `floorplan.tcl:170–178` name every macro that no longer fits, per edge, with its
   overhang — it fires at the point of placement, hours before `sroute` or DRC would.
5. Fix the named macros. Move whole clusters, not individuals — the ten QSPI cache RAMs are on a
   45 µm pitch with 8.64 µm between them and cannot move singly.
6. Annotate every move `## MOVED <delta>: <reason>`. That convention is the only reason the
   50 → 70 change is reconstructable today, and it costs nothing.
7. Re-run and expect the assertion to be silent. Then check utilisation.

### Things this checklist cannot protect you from

- **Changing the die size** rather than the margin invalidates the `.io` file's `offset=150` end
  slivers and the filler arithmetic in §2.4, and — because `read_io_file` is not passed
  `-no_die_size_adjust` — Innovus may quietly resize the die back at line 85 anyway.
- **Adding or removing a pad** re-runs the outer/inner alternation in `place_bondpads.tcl`
  (§4.3) with nothing checking it.
- **A Genus ungrouping change** breaks patterns, not coordinates; that is
  `probe_macros.tcl`'s job, and the assertion at line 151 is what makes it fail loudly.

---

## 7. Fragile or unexplained

Ranked by what would cost the most to discover late.

1. **`read_io_file` without `-no_die_size_adjust`** (`floorplan.tcl:85`). The manual says this
   command will resize the die when used after floorplanning. It runs five lines after
   `create_floorplan`. Today the die is unchanged (verified), but the guard is one flag and it is
   missing on a design whose die size is a fixed shuttle commitment.
2. **`place_status` downgraded from `fixed` to `placed`** (`floorplan.tcl:158`), with no comment.
   `place_inst` defaults to `-fixed`; this line explicitly undoes that for all 21 macros, handing a
   hand-tuned floorplan back to the placer as movable. It is only safe because `preplace.tcl:11`
   leaves macro placement off — an undocumented coupling between two files, one of which is full of
   no-ops that look deletable.
3. **The outer/inner bond-pad alternation is a coincidence, not an invariant** (§4.3). Eight
   hand-maintained lists in `place_bondpads.tcl` happen to interleave this `.io` file's per-side
   order exactly. Insert one pad and half a side swaps rows silently, and the inner row is the one
   with 4 µm of clearance to the core rings.
4. **No macro coordinate has a recorded rationale** (§3.1). Seventeen `## MOVED` notes document
   deltas; nothing documents positions. The floorplan cannot be re-derived, only preserved.
5. **`connect_global_net` runs after `add_io_fillers`**, contradicting the manual's stated
   precondition, so the fillers' built-in DRC is by definition not accurate (§2.4).
6. **`place_global_uniform_density true` at 80.7 % density** (`preplace.tcl:7`), against a
   documented 70 % ceiling, silently forcing `place_global_initial_padding_level` to 5
   (`IMPSP-196`) on a design that also carries a 2-site legalisation gap.
7. **`-side n|e|s|w` is undocumented** in both manual sets (§2.4). Works on 21.11; twenty-four
   lines depend on it.
8. **No `write_floorplan`, no `check_place`** (§2.8). The floorplan has no reviewable artefact and
   its legality is never checked by the tool that offers to check it.
9. **`design.sdf`** — 494 MB per run, written to the wrong directory, read by nothing
   (`postplace.tcl:2`).
10. **Twelve of 24 `add_io_fillers` calls place zero cells** (§2.4). Harmless; misleading.

---

## 8. Sources

Every page below was opened and read. Nothing is cited that was not.

**Innovus Stylus Common UI Text Command Reference, Product Version 21.11** — `$INNOVUS_HOME/doc/TCRcom/`

- `create_floorplan` (`TCRcom/create_floorplan.html`) — `-die_size` margin semantics, `-core_margins_by` default `io`, `-floorplan_origin` default `llcorner`, `-flip` default `f`, `add_tracks` side effect
- `read_io_file` (`TCRcom/read_io_file.html`) — automatic die-size adjustment, `-no_die_size_adjust`
- `add_io_fillers` (`TCRcom/add_io_fillers.html`) — `-side` enum, `connect_global_net` precondition
- `delete_io_fillers` (`TCRcom/delete_io_fillers.html`) — no-`-cell` behaviour
- `unplace_obj` (`TCRcom/unplace_obj.html`) — `-blocks`
- `create_place_halo` (`TCRcom/create_place_halo.html`) — `-halo_deltas` order and orientation rotation, `-all_macros`
- `place_inst` (`TCRcom/place_inst.html`) — snapping, no legality check, `-fixed` default and the fixed-vs-placed examples
- `snap_floorplan` (`TCRcom/snap_floorplan.html`) — FinFET-grid framing
- `write_floorplan` (`TCRcom/write_floorplan.html`) — `.fp` / `.fp.spr` outputs
- `add_tieoffs` (`TCRcom/add_tieoffs.html`) — `-lib_cell` two-cell limit, post-placement ordering
- `write_sdf` (`TCRcom/write_sdf.html`) — `-ideal_clock_network`
- `place` category attributes (`TCRcom/place_Category_Attributes.html`) — `place_global_cong_effort`, `place_global_timing_effort`, `place_global_uniform_density`, `place_detail_legalization_inst_gap`, `place_design_floorplan_mode`
- `design` category attributes (`TCRcom/design_Category_Attributes.html`) — `design_process_node`
- `add_tieoffs` category attributes (`TCRcom/add_tieoffs_Category_Attributes.html`) — `add_tieoffs_max_fanout`, `add_tieoffs_max_distance`

**Innovus Stylus Common UI User Guide, Product Version 21.11** — `$INNOVUS_HOME/doc/UGcom/`

- Data Preparation, "Generating the I/O Assignment File" (`UGcom/Data_Preparation.html`) — file
  template, `globals`/`iopad locals`/`iopad instance` attribute tables, `io_order = default`
  direction, `place_status` default `fixed`, skip/space/offset exclusivity
- Floorplanning the Design (`UGcom/Floorplanning_the_Design.html`) — Orientation Key, I/O SITE and
  `CLASS PAD` requirements

**Legacy Text Command Reference** — `$INNOVUS_HOME/doc/innovusTCR/`

- `addIoFiller` (`innovusTCR/addIoFiller.html`) — consulted only to confirm that `-side` is
  `{top | bottom | left | right}` in the legacy UI too

**Design data (read-only)**

- `work/nanosoc_eth_chiplet_pads/nanosoc_eth_chiplet_pads.fp.gz` — Head/IO/Core boxes, 2,223
  `DefRow` records over 883 rows, all 21 `Block:` records with resolved names, orientations,
  coordinates and halos, all 411 `IO:` records
- `logs/pnr_run_ocvfix.log` — `IMPFP-325`, `IMPSP-196`, per-side filler counts, `#ioInst=411`,
  `#block=21`, `Density for the design = 0.807`, `Options: No distance constraint, Max Fan-out = 10`
- `outputs/nanosoc_eth_chiplet_pads_gate_power.v` — 82 `uPAD_*` instances, 0 `PCORNER_G`, 21 macros
- `$TSMC_65_HOME/.../PRTF_EDI_N65_<stack>_RDL.<rev>.tlef` — `SITE core 0.200 BY 1.800`,
  `MANUFACTURINGGRID 0.005`
- Macro LEFs under `$MEM_BASE/` and `ASIC/romlibs/` — `SIZE`, `CLASS BLOCK`,
  `SYMMETRY X Y R90`

---

Prev: [03-floorplan](../03-floorplan.md) · Index: [00-index](../00-index.md) ·
Next in the flow: [04-power-plan](../04-power-plan.md)
