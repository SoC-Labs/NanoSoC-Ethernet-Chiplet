# 02 — Innovus Basics

**What this page is for.** How to actually drive Innovus on *this* design: get an
interactive session with the database loaded, ask the database questions with `get_db`,
open a snapshot so an experiment costs an hour instead of five, make the tool document
itself, get the GUI to appear, and write things out. It assumes you know what
place-and-route is; it does not assume you have used this flow, Stylus, or `get_db`
before. For what the stages *are*, read [01-flow-overview](01-flow-overview.md) first.

Tool here is **Innovus `v21.11-s130_1`** in **STYLUS / Common UI** mode, block
`nanosoc_eth_chiplet_pads`.

Sibling pages: [00-index](00-index.md) ·
[01-flow-overview](01-flow-overview.md) ·
[03-floorplan](03-floorplan.md) ·
[04-power-plan](04-power-plan.md) ·
[05-place-cts-route](05-place-cts-route.md) ·
[06-fill-antenna-bondpads](06-fill-antenna-bondpads.md) ·
[07-reading-reports](07-reading-reports.md) ·
[08-debugging](08-debugging.md) ·
[09-signoff-checklist](09-signoff-checklist.md) ·
[10-tapeout-submission](10-tapeout-submission.md) ·
[11-known-issues](11-known-issues.md)

---

## Starting a session and loading the design

```sh
cd ASIC/genus-innovus/work
innovus -stylus
```
```tcl
source ../scripts/config.tcl
read_db nanosoc_eth_chiplet_pads
```

Three things about that, in order of how often they catch people:

**1. `cd` into `work/` first.** Not optional.
[`config.tcl`](../../ASIC/genus-innovus/scripts/config.tcl) sets `LOG_DIR ../logs`,
`REPORT_DIR ../reports`, `OUT_DIR ../outputs` as *relative* paths, and every stage script
starts with `source ../scripts/config.tcl`. The databases also live in `work/`. Start
anywhere else and either the source fails or your outputs land somewhere you will not
look.

**2. `source ../scripts/config.tcl` BEFORE `read_db`.** A bare `read_db` in a fresh
session fails, and the reason is worth internalising: `config.tcl` is where the block name
and *every library path* live. It sets

- `set block_name nanosoc_eth_chiplet_pads` — so `read_db $block_name` works at all
- `lib_search_path_list`, `syn_lib_list` — the `.lib` timing libraries
- `lef_file_list` — tech LEF, `tcbn65lp` std cells, TSMC IO, the local-override IO driver
  LEF, and the six RF/ROM/flash-cache macro LEFs
- `gds_merge_list`, `drc_ruledeck`, `power_nets` / `ground_nets`, `process_node`
- `soclabs_setup_multi_cpu` — the CPU/distribution proc every stage calls

`config.tcl` also needs `TSMC_65_HOME` and `NANOSOC_ETH_CHIPLET_HOME` in the environment
(it dereferences `$::env(...)` directly and dies without them). Those are exported by
[`ASIC/common.mk`](../../ASIC/common.mk), which means a shell that ran `make` has them and
a bare login shell does not. If `source ../scripts/config.tcl` dies on `$::env`, that is
what happened.

**3. `config.tcl` is sourced by BOTH tools.** Genus reads it in `1_synthesis.tcl`;
Innovus reads it in all three P&R stages. Anything tool-specific added to it must be
guarded, or it takes the other tool down. The file's `check_cpf` wrapper is guarded
exactly this way, and there is a long note in it explaining why a Genus-only root
attribute (`clp_treat_errors_as_warnings`) cannot go there — under Innovus it fails with
`IMPDBTCL-247`.

### The two Makefile shortcuts

| command | what you get |
|---|---|
| `make gui` | **Innovus with `config.tcl` sourced and the DB read, GUI shown.** This is the one you want for inspecting a stage. |
| `make pnr_setup` | Innovus interactive in `work/`, **empty session** — no config, no libraries, no design. `read_db` alone here fails. |

`make gui` writes a small `work/open_db.tcl` and runs it; that loader is exactly the three
lines above plus `gui_show` (see [the GUI section](#the-gui-and-why-it-looks-like-it-did-not-open)).

<a id="loading-a-snapshot"></a>
## Loading a snapshot instead of the final DB

All three P&R stages write the same DB name, so the "current" DB is whatever ran last.
Two snapshots are taken by the flow so you can go back without re-running:

```tcl
source ../scripts/config.tcl

read_db nanosoc_eth_chiplet_pads_placed    ;# post-place, before CTS
read_db nanosoc_eth_chiplet_pads_cts       ;# post-CTS, before routing
read_db nanosoc_eth_chiplet_pads           ;# whatever the last stage left
```

`_placed` is written by the first line of
[`cts_setup.tcl`](../../ASIC/genus-innovus/scripts/cts_setup.tcl); `_cts` by the first
line of [`route_setup.tcl`](../../ASIC/genus-innovus/scripts/route_setup.tcl). Both are
sourced by their consuming stage immediately after `read_db`, so they hold the clean
hand-off state.

This is the difference between a one-hour experiment and a five-hour one. Want to try
different routing attributes or a different hold-repair approach? Load `_cts`, change the
attribute, run `route_design` yourself — you skip synthesis, placement and CTS entirely.
The rationale is written into `route_setup.tcl`'s own header. See
[01-flow-overview](01-flow-overview.md#the-snapshot-dbs-and-why-they-exist) for the
timings and sizes.

---

## Stylus, not legacy Common UI

**This flow is Stylus.** The tool is always launched `innovus -stylus`, and Stylus is a
different command language from the legacy UI — not a skin on it. Practically:

- Commands are **`snake_case`**: `place_inst`, `get_db`, `set_db`, `add_stripes`,
  `route_design`, `opt_design`, `write_db`, `create_floorplan`, `add_fillers`.
- The legacy camelCase names (`placeInstance`, `dbGet`, `addStripe`, …) are **not** what
  this flow uses. Vendor docs, forum answers and older SoC Labs scripts are full of them;
  translate before pasting.
- Attributes are set with `set_db <attr> <value>` and read with `get_db <attr>`, rather
  than the legacy `setXxxMode` family. You can see this all over the project scripts —
  `set_db place_global_timing_effort high`,
  `set_db route_design_with_si_driven 1`,
  `set_db add_stripes_stacked_via_top_layer AP`.

The one command-line consequence, repeated here because it is the most expensive mistake
in the flow: **`innovus -stylus -files <script>`, never `-f`.** Stylus rejects `-f` with
`**ERROR: (IMPSYT-468): Unknown argument -f`, prints usage, and **exits 0**. Full detail
in [01-flow-overview](01-flow-overview.md#read-this-first-both-tools-exit-0-on-failure).

---

## `get_db` — the introspection language

`get_db` is how you ask the loaded database anything. Learning it is the difference
between guessing at the floorplan and measuring it. All of the following are verified
working on this design.

### Design-level geometry

```tcl
get_db current_design .core_bbox
# -> {205.0 205.0 1395.0 1795.0}

get_db current_design .bbox
# -> {0.0 0.0 1600.0 2000.0}
```

Read those together and you have the whole floorplan story: the die is fixed at
1600 × 2000, anchored at the origin, and the core is inset 205 µm on every side — 135 µm
of IO-driver height plus the `CORE_TO_IO 70` set in
[`floorplan.tcl`](../../ASIC/genus-innovus/scripts/floorplan.tcl). (At the earlier
`CORE_TO_IO 50` the same query returned a core of 185…1415 / 185…1815; the 20 µm per side
came straight out of the core, because the die is fixed. See
[03-floorplan](03-floorplan.md).)

### The `.bbox` gotcha — a rect inside a list

**`.bbox` and `.core_bbox` return a LIST CONTAINING ONE RECT, not a rect.** This is real
and it will silently give you wrong numbers if you ignore it:

```tcl
# WRONG — lassign sees a single-element list and llx gets the whole rect
lassign [get_db current_design .core_bbox] llx lly urx ury

# RIGHT — unwrap the outer list first
lassign [lindex [get_db current_design .core_bbox] 0] llx lly urx ury
puts "core is [expr {$urx-$llx}] x [expr {$ury-$lly}]"
```

The failure is not an error — `lassign` succeeds, `llx` ends up holding
`205.0 205.0 1395.0 1795.0`, and any arithmetic on it fails much later or produces
nonsense. Get into the habit of `[lindex [get_db ...] 0]` for every bbox/rect query.

### Object queries with predicates

```tcl
# every hard macro in the design
get_db insts -if {.base_cell.base_class == block}

# how many
llength [get_db insts -if {.base_cell.base_class == block}]
```

That exact query is the whole point of
[`probe_macros.tcl`](../../ASIC/genus-innovus/scripts/probe_macros.tcl), the flow's
diagnostic for `place_macro` patterns that stop matching (Genus runs with auto-ungroup on,
so macro instance names move when the RTL changes):

```tcl
foreach i [get_db insts -if {.base_cell.base_class == block}] {
    puts "[get_db $i .name]  ->  [get_db $i .base_cell.name]"
}
```

Note the two-level form: once you hold an object, `get_db <obj> .attr` reads an attribute
off it, and attributes chain through references — `.base_cell.base_class` walks from the
instance to its cell and reads the cell's class.

### Attributes you will use constantly

| attribute | on | gives |
|---|---|---|
| `.name` | any object | its name (hierarchical, for insts) |
| `.bbox` | inst, cell, design | bounding box — **list-of-one-rect** |
| `.rect` | a shape / wire | its rectangle |
| `.layer.name` | a shape / wire | the layer it is on |
| `.net.name` | a pin / term / wire | the net it belongs to |
| `.obj_type` | anything | what kind of object you are actually holding |
| `.place_status` | inst | `placed` / `fixed` / `unplaced` / … |
| `.base_cell.name` | inst | the library cell it is an instance of |
| `.base_cell.base_class` | inst | `block` for macros, `core` for std cells, `pad`, … |

`.obj_type` is the one to reach for when a query returns something you did not expect.
Confusion in `get_db` almost always comes from holding a different kind of object than you
assumed.

### `get_db selected` — the GUI/Tcl bridge

```tcl
get_db selected
get_db selected .name
get_db selected .obj_type
foreach o [get_db selected] { puts "[get_db $o .obj_type] [get_db $o .name]" }
```

Click something in the GUI — a stripe, a macro, a violation marker — then run this in the
console. This is by far the fastest way to answer "what *is* that thing" and to find the
attribute names for a class of object you have not queried before. It is the standard loop
for debugging a floorplan or power-plan problem: see it, select it, interrogate it, then
write the `get_db … -if {…}` predicate that finds all of them.

---

## Make the tool document itself

The highest-value habit on this page. Innovus ships its own reference and almost nobody
uses it.

```tcl
<command> -help          ;# full option list for that command
```
```tcl
help *stripe*            ;# find commands whose name contains "stripe"
help *filler*
help *bbox*
```
```tcl
man IMPSP-5110           ;# explain a message ID
man IMPSYT-468
man IMPLF-119
```

`man <MSGID>` is the one to build a reflex around. **The logs literally tell you to do
it** — the current run's log contains hundreds of lines reading
`Type 'man IMPLF-119' for more detail.` — and almost nobody does. When a stage emits a
message ID you have not seen, `man` it before searching the web: the answer is local,
version-correct for `v21.11-s130_1`, and instant.

Three IDs that already matter on this design, as a taste of what the habit buys:

| ID | meaning here |
|---|---|
| `IMPSP-5110` | `No supply-net names for Power Domain 'PD_TOP'` — the broken CPF; every filler pass silently inserts nothing. Fixed by `make cpf-patch`. |
| `IMPSYT-468` | `Unknown argument -f` — Stylus rejecting the legacy flag, then exiting 0. |
| `IMPSYT-1507` | the display is invalid, starting in no-window mode — see below. |

`-help` is worth using even on commands you think you know. `update_power_domain` under
Innovus, for instance, is positional and has **no** `-primary_power_net` /
`-primary_ground_net` options at all — its usage string is how that was established, and
it is why the CPF had to be repaired as a file rather than patched with a Tcl command.

---

<a id="the-gui-and-why-it-looks-like-it-did-not-open"></a>
## The GUI, and why it looks like it did not open

```sh
make gui
```

This does the `cd`, checks the display, writes a loader, sources `config.tcl`, reads the
DB, and shows the window. Two traps are baked into it, both of which have burned time:

### Trap 1: `-files` creates the window but never maps it

Innovus launched with `-files <script>` **creates its main window and never maps it**.
Measured: `xwininfo` reports `Map State: IsUnMapped`, and `xprop` reports no `WM_STATE` at
all — the window manager never took ownership. The session looks like a plain text
console and the GUI appears simply not to exist, with **no error**, because from the
tool's point of view nothing failed.

The fix is an explicit `gui_show` in the loader script:

```tcl
source ../scripts/config.tcl
read_db nanosoc_eth_chiplet_pads
if {[catch {gui_show} e]} { puts stderr "WARNING: gui_show failed: $e" }
```

That takes it `IsUnMapped` → `IsViewable` (verified). `gui_show` here is required, not
decoration — if you write your own `-files` loader and the GUI "does not open", this is
why.

### Trap 2: a malformed `DISPLAY` fails silently

`DISPLAY` must be **valid**, not merely set. A malformed value — `12.0` with the leading
colon missing is the one that actually happened — passes a `test -n "$DISPLAY"` check, and
Innovus then drops to no-window mode with only:

```
**WARN: (IMPSYT-1507):	The display is invalid and will start in no window mode
```

A `WARN`, mid-banner, in a log you are not reading yet. `make gui` therefore probes the
display for real with `xdpyinfo` instead of testing for non-emptiness, and if the value
looks like a bare number it tells you to `export DISPLAY=:$DISPLAY`.

Related, and a genuinely separate shell problem: **a ThinLinc desktop's `DISPLAY` does not
reach a VS Code Remote-SSH terminal.** They are different shells. Run `make gui` from a
terminal *inside* the ThinLinc desktop, or use `ssh -X <host>`. If you want a text session
on purpose, use `make pnr_setup`.

---

## Writing things out

```tcl
write_db  nanosoc_eth_chiplet_pads_myexperiment
write_netlist  ../outputs/nanosoc_eth_chiplet_pads_pnr.v
write_stream   ../outputs/nanosoc_eth_chiplet_pads.gds \
    -map_file $env(TSMC_65_HOME)/CMOS/util/lef/PRTF_EDI_65nm_001_Cad_V24a/PR_tech/Cadence/GdsOutMap/PRTF_EDI_N65_gdsout_6X1Z1U.24a.map \
    -lib_name DesignLib -merge $gds_merge_list \
    -output_macros -unit 1000 -mode all
write_sdf -min_view default_analysis_view_hold \
          -typical_view typical_analysis_view \
          -max_view default_analysis_view_setup \
          ../outputs/nanosoc_eth_chiplet_pads_pnr.sdf
```

| command | writes | notes |
|---|---|---|
| `write_db <name>` | a directory `work/<name>/` | the full design state. **Give experiments their own name** — the flow's stages all write `nanosoc_eth_chiplet_pads`, so a bare `write_db $block_name` from an interactive session overwrites the flow's DB. |
| `write_netlist <path>` | post-P&R Verilog | the flow writes `outputs/..._pnr.v` |
| `write_stream <path>` | GDSII | needs the TSMC GDS-out map file **and** `-merge $gds_merge_list` (the RF/ROM/flash-cache macro GDS2s from `config.tcl`), or the macros come out empty. The exact invocation the flow uses is in [`4_pnr_route.tcl`](../../ASIC/asic-flows/Cadence/4_pnr_route.tcl). |
| `write_sdf <path>` | back-annotation timing | the flow writes two: `work/design.sdf` at post-place with `-ideal_clock_network` (from [`postplace.tcl`](../../ASIC/genus-innovus/scripts/postplace.tcl)), and the three-view `outputs/..._pnr.sdf` at the end of routing |

The analysis-view names above (`default_analysis_view_setup`, `default_analysis_view_hold`,
`typical_analysis_view`) are defined in
[`scripts/nanosoc_eth_chiplet_pads.mmmc`](../../ASIC/genus-innovus/scripts/nanosoc_eth_chiplet_pads.mmmc)
and read in at stage 2 by `read_mmmc`. If a `write_sdf` or `report_timing` complains about
an unknown view, that file is where the real names are.

**Safety note for an interactive session on a live design:** the flow's DBs and the two
snapshots all live in `work/`. Nothing stops an interactive `write_db nanosoc_eth_chiplet_pads`
from clobbering the running flow's state. Name your experiments, and prefer reading a
snapshot (`read_db ..._cts`) over reading the live DB while a stage is executing.

---

## A worked mini-session

Putting it together — "is every macro inside the core box?", answered without running
anything:

```tcl
source ../scripts/config.tcl
read_db nanosoc_eth_chiplet_pads_placed

lassign [lindex [get_db current_design .core_bbox] 0] cx1 cy1 cx2 cy2
puts "core: $cx1 $cy1 $cx2 $cy2"

foreach i [get_db insts -if {.base_cell.base_class == block}] {
    lassign [lindex [get_db $i .bbox] 0] x1 y1 x2 y2
    if {$x1 < $cx1 || $y1 < $cy1 || $x2 > $cx2 || $y2 > $cy2} {
        puts "OUTSIDE CORE: [get_db $i .name]  ($x1 $y1 $x2 $y2)"
    }
}
```

Note both `[lindex … 0]` unwraps. That check is the scripted form of the containment
backstop discussed in [`floorplan.tcl`](../../ASIC/genus-innovus/scripts/floorplan.tcl) —
raising `CORE_TO_IO` shrinks the core while the macro coordinates stay absolute, so macros
fall out of the core silently and only surface as `sroute` damage hours later.

Next: [03-floorplan](03-floorplan.md) for the die/core/macro geometry, or
[08-debugging](08-debugging.md) for what to do when a stage misbehaves.
