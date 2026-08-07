# 06 — CTS and route setup, annotated

`nanosoc_eth_chiplet_pads` · Cadence Innovus 21.11-s130_1 · STYLUS / Common-UI

Line-by-line reference for the two project setup scripts that configure clock tree
synthesis and routing, plus the CTS/route commands in the flow scripts that consume them.
Every claim about what a command or attribute *means* is cited to a manual page that was
actually opened; every claim about what this design *does* is cited to a file in this
repository.

[← 05 Place, CTS, route](../05-place-cts-route.md) (flow-level view) ·
[16 Open defects](../16-open-defects.md) (the hold defect, at design level) ·
[07 Reading reports](../07-reading-reports.md)

**Where the manuals are.** Two command references are installed, and they are *not*
interchangeable:

| Directory | Which UI |
|---|---|
| `/eda/cadence/innovus/doc/TCRcom/` | Innovus **Stylus Common UI** Text Command Reference — `opt_design.html`, `route_design.html`, `ccopt_design.html`, `write_db.html`, the `*_Category_Attributes.html` pages |
| `/eda/cadence/innovus/doc/UGcom/` | Innovus **Stylus Common UI** User Guide — `Clock_Tree_Synthesis.html`, `Using_the_NanoRoute_Router.html` |
| `/eda/cadence/innovus/doc/innovusTCR/` | **Legacy UI** — `optDesign.html`, `routeDesign.html`, `setAnalysisMode.html`, `setNanoRouteMode.html`, `saveDesign.html` … |
| `/eda/cadence/innovus/doc/innovusUG/` | Legacy UG, including `CCOpt_Properties.html` |

This flow runs `innovus -stylus`, so `TCRcom/` and `UGcom/` are authoritative. Searching
`innovusTCR/` for `set_route_attributes` or `create_clock_tree_spec` returns nothing —
those commands exist only in the Common UI. If a page you find uses `setNanoRouteMode` or
`optDesign`, you are in the legacy manual and the syntax will not work here.

---

## Contents

1. [The CTS model in this version of Innovus](#1-the-cts-model-in-this-version-of-innovus)
2. [`cts_setup.tcl`, annotated](#2-cts_setuptcl-annotated)
3. [`route_setup.tcl`, annotated](#3-route_setuptcl-annotated)
4. [The CTS commands in `3_pnr_clock.tcl`](#4-the-cts-commands-in-3_pnr_clocktcl)
5. [The routing commands in `4_pnr_route.tcl`](#5-the-routing-commands-in-4_pnr_routetcl)
6. [The hold defect, at command level](#6-the-hold-defect-at-command-level)
7. [Reading the clock reports](#7-reading-the-clock-reports)
8. [Citation index](#8-citation-index)

---

## 1 — The CTS model in this version of Innovus

### 1.1 CCOpt, not classic CTS

Innovus 21.11 ships two CTS engines. The User Guide's opening paragraph:

> "The Innovus™ Implementation System (Innovus) offers two commands to perform Clock Tree
> Synthesis (CTS), the `ccopt_design` command, which performs CTS with Clock Concurrent
> Optimization, and the `clock_design` command, which performs stand-alone CTS."
> — *Innovus Stylus Common UI User Guide — Clock Tree Synthesis*, Overview
> (`UGcom/Clock_Tree_Synthesis.html`)

This flow uses `ccopt_design` ([`3_pnr_clock.tcl:28`](https://github.com/SoC-Labs/ASIC-Flow/blob/b19e7845448e641ea8353b19a59a77257907cb13/Cadence/3_pnr_clock.tcl)).
`clock_design` is never called. The distinction matters because CCOpt does not attempt
global skew balancing — it treats "clock launch, clock capture, and datapath delays as
flexible parameters that can be manipulated to optimize timing" (same page). Skew is a
means, not the objective. That is why there is no `cts_target_skew` anywhere in this
project and why the tool does not complain: CCOpt "will auto-generate skew targets where
none are specified" (*UGcom/Clock_Tree_Synthesis.html*, Skew Target).

The same page also warns, in the Flow and Quick Start section:

> "In the CTS flow, post-CTS optimization is not required because `ccopt_design` includes
> post-CTS style optimization as part of CTS."

`3_pnr_clock.tcl` runs `opt_design -post_cts` and `opt_design -post_cts -hold` anyway.
See [§4.4](#44-lines-3334-opt_design-post_cts-and-post_cts-hold) — the measured cost is ~14
minutes and the measured benefit is nil on setup, so this is arguably redundant, but the
`-hold` pass is *not* redundant and must stay.

### 1.2 Two dialects for the same knobs

CCOpt configuration exists in two syntaxes and you will meet both in search results:

| Dialect | Example | Documented in |
|---|---|---|
| Stylus attribute | `set_db cts_buffer_cells {CKB*}` | `TCRcom/cts_Category_Attributes.html` |
| Legacy property | `set_ccopt_property use_inverters -clock_tree ct1 true` | `innovusUG/CCOpt_Properties.html` |

The legacy reference is still useful because it documents knobs by their bare names and
gives defaults. Two pairs verified by reading both pages:

- property `buffer_cells` ↔ attribute `cts_buffer_cells`
- property `update_io_latency` ("Determine whether to update IO latencies within
  `ccopt_design`. … Default: true", `innovusUG/CCOpt_Properties.html`) ↔ attribute
  `cts_update_io_latency`

**Inference:** the general rule appears to be *property* `X` ↔ *attribute* `cts_X`, but
only those two pairs were checked against both manuals. Do not assume it holds for a
property you have not looked up in `TCRcom/cts_Category_Attributes.html`.

The Stylus UG states the category split explicitly (*UGcom/Clock_Tree_Synthesis.html*,
Configuration and Method → Attributes): `cts` category attributes apply to core CTS and
therefore to `clock_design`, `ccopt_design` *and* `place_opt_design` early clock flow;
`ccopt` category attributes are specific to `ccopt_design`. Everything this project sets
is in the `cts` category.

### 1.3 The clock tree spec and skew groups

`create_clock_tree_spec` is the bridge between SDC and CCOpt:

> "Creates a clock tree network with associated skew groups and other clock tree synthesis
> (CTS) configuration settings such as ignore pins, case analysis, maxTrans, and so on
> based on a multi-mode timing configuration in the common timing engine (CTE). When you
> run this command, one skew group will be created for each SDC clock in each constraint
> mode."
> — *Innovus Stylus Common UI Text Command Reference — `create_clock_tree_spec`*
> (`TCRcom/create_clock_tree_spec.html`)

A **clock tree** is a physical object rooted at a clock source pin. A **skew group** is a
balancing constraint: a set of sinks whose arrival times CCOpt is asked to relate. They
are not 1:1 — this design has 4 clock trees and 14 skew groups.

### 1.4 What `work/design_clk.spec` actually is

[`3_pnr_clock.tcl:25`](https://github.com/SoC-Labs/ASIC-Flow/blob/b19e7845448e641ea8353b19a59a77257907cb13/Cadence/3_pnr_clock.tcl) writes it:

```tcl
create_clock_tree_spec -out_file design_clk.spec
```

`-out_file` "Writes this clock tree specification script file in Stylus Common UI format.
… The file is not executed." (`TCRcom/create_clock_tree_spec.html`). So `design_clk.spec`
is a **dump for inspection**, not an input. Nothing in this flow ever sources it. The
manual's note that it can only be sourced once, and that `delete_clock_tree_spec` /
`reset_cts_config` are needed before re-sourcing, is why: the spec is applied to the
in-memory database as a side effect of the same command that writes it.

`work/design_clk.spec` from the current run is 5,623 lines. What it contains:

| Content | Count | Example line |
|---|---|---|
| `create_clock_tree` | 4 | `114: create_clock_tree -name swdclk -source SWDCK -no_skew_group` |
| `create_skew_group` | 14 | `247: create_skew_group -name clk/default_constraint_mode -sources CLK -auto_sinks` |
| `.cts_sink_type ignore` pins | 31 | `set_db pin:uPAD_QSPI_SCLK/I .cts_sink_type ignore` |
| `.cts_clock_period` | 12 | `141: set_db port:CLK .cts_clock_period 10` |
| `cts_target_skew` / `cts_target_max_transition_time` | **0** | — |

The four clock trees are `swdclk` (source `SWDCK`), `rmii_ref_clk` (`RMII_REF_CLK`), `clk`
(`CLK`) and `D2D_RX_CLK_0` (`TL_CLK_RX`). Everything else in the design — `QSPI_SCLK`,
`QSPI_SCLK_o`, `mii_rx_clk`, `mii_tx_clk`, `D2D_TX_CLK_0` — is a *generated* clock and
gets a skew group but no tree of its own. The `.cts_clock_period` values are the SDC
periods in library units (ns here): `CLK` 10, `RMII_REF_CLK` 20, `SWDCK` 40,
`TL_CLK_RX` 10; generated-clock roots get `auto`.

The 31 `cts_sink_type ignore` pins carry a `cts_sink_type_reasons` annotation — either
`multiple_outputs` (inputs to multi-output cells carrying SDC clocks, e.g.
`uPAD_QSPI_SCLK/I`) or `no_sdc_clock` (pins on the boundary of the STA clock network).
These are pins CCOpt will drive but not balance.

**The absence of `cts_target_*` is the headline.** No skew target and no transition target
are set anywhere — not in `cts_setup.tcl`, not in the spec. Per
`UGcom/Clock_Tree_Synthesis.html` (Transition Target): "If a target max transition is not
specified, CTS will examine the `cts_target_max_transition_time_sdc` attribute … and if
that is not defined then an automatically generated target is chosen. It is recommended to
set a transition target unless intentionally using per settings that are to be obtained
from the SDC constraints." This design takes the automatic target. That is a deliberate
gap, not a bug, but it is a gap.

### 1.5 Where `write_db` state fits

Attributes set with `set_db` and net attributes set with `set_route_attributes` are
database state, not script state. `set_route_attributes` is explicit:

> "Attributes are persistent; that is, throughout the routing process, from global routing
> to optimization, the routers honor the attributes. The attributes are saved in the
> Innovus database. If you save the database and exit, the attributes remain attached to
> the nets when you re-import the database. **Note:** Attributes are not saved in the DEF
> file."
> — `TCRcom/set_route_attributes.html`

`route_design` says the same for its own mode settings: "the software stores the mode
settings in the `.mode` file. If you restore the design and run `route_design` again, it
honors these settings" (`TCRcom/route_design.html`).

Consequence for the snapshots this project takes: `${block_name}_placed` and
`${block_name}_cts` carry the attribute state that was live when they were written.
Resuming from `${block_name}_cts` gives you a database that *already has*
`timing_analysis_type ocv` and the route-driven-mode flags, because `route_setup.tcl`
wrote the snapshot on line 12 before setting them — but re-sourcing the setup file is
still correct and harmless.

One documented exception, relevant to [§6](#6-the-hold-defect-at-command-level):

> "The `write_db` command does not save the state of the
> `timing_enable_simultaneous_setup_hold_mode` timing attribute."
> — `TCRcom/write_db.html`

---

## 2 — `cts_setup.tcl`, annotated

[`ASIC/genus-innovus/scripts/cts_setup.tcl`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/cts_setup.tcl),
71 lines, of which **three** are executable. Sourced by
[`3_pnr_clock.tcl:22`](https://github.com/SoC-Labs/ASIC-Flow/blob/b19e7845448e641ea8353b19a59a77257907cb13/Cadence/3_pnr_clock.tcl), immediately
after `read_db $block_name` and before `create_clock_tree_spec`.

### 2.1 Line 9 — the post-place snapshot

```tcl
9  write_db ${block_name}_placed
```

Not a CTS setting at all. Every stage script ends with `write_db $block_name` — the *same*
name — so each stage overwrites the last and only the final post-route database survives.
Line 9 costs one extra DB directory and buys the ability to resume CTS experiments from
placement instead of replaying ~5 h. `write_db` "Writes the complete design database in
the native Innovus DB format if `<out_dir>` is given" and "can be used at any time after
`init_design`" (`TCRcom/write_db.html`). The header comment gives the resume recipe.

The mirror-image line is [`route_setup.tcl:12`](#31-line-12-the-post-cts-snapshot).
Both are project additions; the upstream `asic-flows` scripts have no checkpointing.

### 2.2 Lines 20 and 22 — the buffer and inverter cell lists (commented out)

```tcl
20  #set_db cts_buffer_cells {CKB*}
22  #set_db cts_inverter_cells {CKN*}
```

Both attributes are real and both patterns match this library. What they mean:

> `cts_buffer_cells buffer_cell_list` — Default: `{}` — "Specifies the buffer cells for
> CTS. **If none are specified CTS will choose buffers from the libraries.** Cell names may
> be specified as a Tcl list of names, or as a Tcl list of patterns to be expanded to match
> names. **If set explicitly, CTS will ignore any don't use settings for the cells
> specified.**"
> — `TCRcom/cts_Category_Attributes.html`

`cts_inverter_cells` is worded identically (default `{}`, patterns allowed, overrides
`dont_use`). Data type for both: `string, read/write`. There are no units.

**What the `tcbn65lp` names mean.** The 9-track TSMC 65 nm LP standard cell library uses a
`<function><drive>` naming scheme, where the trailing integer is a relative drive strength,
not a fanout or a delay:

| Prefix | Function | Drives present, per the run log |
|---|---|---|
| `CKBD` | clock buffer | `CKBD0 1 2 3 4 6 8 12 16 20 24` |
| `CKND` | clock inverter | `CKND0 1 2 3 4 6 8 12 16 20 24` |
| `BUFFD` | general-purpose buffer | `BUFFD0 1 2 3 4 6 8 12 16 20 24` |
| `INVD` | general-purpose inverter | `INVD0 1 2 3 4 6 8 12 16 20 24` |
| `GBUFFD` / `GINVD` | "guaranteed" variants | `GBUFFD1 2 3 4 8`, `GINVD1 2 3 4 8` |
| `DEL` | delay cell | `DEL0 DEL005 DEL01 DEL015 DEL02 DEL1 DEL2 DEL3 DEL4` |

Verbatim from
`logs/cts_ocvfirst.log:720–728`:

```
List of usable buffers: BUFFD1 BUFFD0 BUFFD2 BUFFD12 BUFFD16 BUFFD20 BUFFD24 BUFFD3 BUFFD4 BUFFD6 BUFFD8 CKBD1 CKBD0 CKBD2 CKBD12 CKBD16 CKBD20 CKBD24 CKBD3 CKBD4 CKBD6 CKBD8 GBUFFD1 GBUFFD3 GBUFFD2 GBUFFD4 GBUFFD8
Total number of usable buffers: 27
List of usable inverters: CKND1 CKND0 CKND2 CKND12 CKND16 CKND20 CKND24 CKND3 CKND4 CKND6 CKND8 GINVD2 GINVD1 GINVD4 GINVD3 GINVD8 INVD1 INVD0 INVD2 INVD12 INVD16 INVD20 INVD24 INVD3 INVD4 INVD6 INVD8
```

So with lines 20 and 22 commented, CCOpt picks from **27 buffers and 27 inverters**,
including the non-clock `BUFFD`/`INVD`/`GBUFFD`/`GINVD` families. Enabling `{CKB*}` and
`{CKN*}` would cut those to 11 and 11 — clock cells only. Note `{CKB*}` also matches
`CKBD*` only by luck of the naming; there is no `CKB` cell without the `D`.

The file's own note records what the unconstrained choice produced: 41,228 `CKBD0`, 5,648
`CKND0`, 3,126 `CKBD1`, and 3,290 `BUFFD1` — the last of which a `cts_buffer_cells {CKB*}`
list would have excluded. The same numbers appear in
[05-place-cts-route.md §CTS](../05-place-cts-route.md).

**Why leaving them off is defensible, and why it is still a deviation.** The manual's
recommendation is unambiguous: "Always specify library cells for buffers, inverters and
clock gating" and "Limiting the number of library cells to no more than 5 per cell type may
help reduce run time" (`UGcom/Clock_Tree_Synthesis.html`, Library Cells). It also warns
against very weak cells — "Very weak cells, for example, X3 and below in many libraries,
are usually undesirable due to poor cross-corner scaling characteristics and are sensitive
to detailed routing jogs and changes" — and this tree is built overwhelmingly from
`CKBD0`, the weakest clock buffer in the family. Against that: changing the cell list
changes the clock tree, which changes the hold profile, and the file's comment is right
that this must not be bundled into a hold-repair experiment. Treat it as a queued
experiment with a known manual-backed rationale, not as an oversight.

`cts_clock_gating_cells` — the third member of the recommended trio — is not set either,
and is not even mentioned in the file.

### 2.3 Line 24 — `cts_delay_cells`

```tcl
24  set_db cts_delay_cells {DEL*}
```

The only CTS cell attribute this project actually sets.

> `cts_delay_cells cell_list` — Default: `{}` — "Specifies the delay cells available for
> CTS. **If none are specified CTS will not use delay cells.** Setting this attribute to
> the string 'auto' means that CTS will choose delay cells from the libraries to use. Cell
> names may be specified as a Tcl list of names, or as a Tcl list of patterns to be
> expanded to match names. If set explicitly, CTS will ignore any don't use settings for
> the cells specified."
> — `TCRcom/cts_Category_Attributes.html`

The default behaviour is the asymmetric one: buffers and inverters are auto-chosen when the
list is empty, **delay cells are not used at all**. So this line is load-bearing — without
it CCOpt has no delay cells for insertion-delay padding. Its effect is visible in
`logs/cts_ocvfirst.log:728`:

```
List of identified usable delay cells: DEL0 DEL005 DEL01 DEL015 DEL02 DEL1 DEL2 DEL3 DEL4
Total number of identified usable delay cells: 9
```

Nine cells. The `DEL005`/`DEL01`/`DEL015`/`DEL02` names read as fractional-nanosecond
delays and `DEL1`…`DEL4` as integer steps; that reading is **inference** from the names —
it was not confirmed against the `.lib`, and the numbers are library units, not guaranteed
to be ns.

`{DEL*}` and `auto` are close to equivalent here (the pattern matches all nine delay cells
the tool would have auto-selected), but the explicit form is better: it is stable if the
library gains a cell family the auto-selector would rank differently.

**Do not confuse this with hold repair.** `cts_delay_cells` governs delay cells available
to *CTS*. The cells `opt_design -hold` may insert are governed by `opt_hold_cells`, a
different attribute in a different category, which this project does not set — see
[§6.3](#63-what-the-flow-sets-and-what-it-does-not).

### 2.4 Line 72 — `timing_analysis_type ocv`

```tcl
72  set_db timing_analysis_type ocv
```

Reference text, in full:

> `timing_analysis_type {single | best_case_worst_case | ocv}` — Default: `ocv` —
> "Allows you to specify the analysis type: single, best case worst case, or OCV."
> — `TCRcom/timing_Category_Attributes.html`

`ocv` = on-chip variation: min and max delay analysis are separated, so a hold check may
take the launch clock's min path and the capture clock's max path independently.

Three things are worth knowing about this one line.

**(a) Its position is the whole point.** It used to live in `route_setup.tcl`, i.e. *after*
`ccopt_design`. Moving it to `cts_setup.tcl` puts it *before*. That is the fix for the hold
defect; the mechanism, the evidence and the measured effect are in
[§6](#6-the-hold-defect-at-command-level). The 46 lines of comment above it in the file
are the diagnosis, and they are worth reading in place.

**(b) The manual endorses the placement, generically.** *UGcom/Clock_Tree_Synthesis.html*,
Flow and Quick Start:

> "It is important to apply the intended post-CTS configuration before invoking CTS but
> with clocks still in ideal timing mode. … **Post-CTS configuration** – CTS includes
> datapath optimization, replacing the need for a separate post-CTS setup timing
> optimization step. Before running CTS the session should be configured with post-CTS
> uncertainties, CPPR enabled, **OCV timing derates or AOCV enabled**, active analysis
> views, and all other settings appropriate for post-CTS optimization."

The flow was doing the opposite.

**(c) The documented default of `ocv` is not what the tool reports.** Before this line
executes, the delay-calculation banner reads `# Analysis Mode: MMMC Non-OCV`
(`baseline_2026-08-06/logs/pnr_run_core70.log:2092`),
and after it, `# Analysis Mode: MMMC OCV`
(`logs/cts_ocvfirst.log:23380`). No
other script in the flow sets `timing_analysis_type` — a grep over
`ASIC/genus-innovus/scripts/*.tcl` and `ASIC/asic-flows/Cadence/*.tcl` finds it only in
these two places. **This discrepancy with the documented default is unexplained.** Do not
rely on the default; set it explicitly, which is what line 72 does.

---

## 3 — `route_setup.tcl`, annotated

[`ASIC/genus-innovus/scripts/route_setup.tcl`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/route_setup.tcl),
44 lines, **four** executable. Sourced by
[`4_pnr_route.tcl:26`](https://github.com/SoC-Labs/ASIC-Flow/blob/b19e7845448e641ea8353b19a59a77257907cb13/Cadence/4_pnr_route.tcl), after `read_db`
and before `route_design`.

### 3.1 Line 12 — the post-CTS snapshot

```tcl
12  write_db ${block_name}_cts
```

Same rationale as [§2.1](#21-line-9-the-post-place-snapshot). 109 MB. This snapshot is
what the `holdexp/` experiments read
(`hold_experiment2.tcl:14`) —
without it those experiments would have cost a 5 h replay each instead of ~30 min.

### 3.2 Line 15 — clock net spacing — **this line is a no-op**

```tcl
15  set_route_attributes -nets clk -preferred_extra_space_tracks 2
```

What it is meant to do:

> `-preferred_extra_space_tracks integer` — "Specifies the preferred extra spacing for
> nets. Gives additional pitch spacing to the specified net. Use this attribute to give
> critical nets extra space to reduce coupling. Specify `-preferred_extra_space_tracks 1`
> to give a net 1 extra pitch spacing, compared to other nets. **This parameter creates a
> soft rule and, if the design is congested, might not give the extra space to the net.**
> Range: 0-3"
> — `TCRcom/set_route_attributes.html`

Units are **routing tracks**, so `2` asks for two extra pitches of spacing. The maximum is
3. It is a soft rule.

What actually happens, in every run on disk:

```
logs/pnr_run_ocvfix.log:30269
@file 15: set_route_attributes -nets clk -preferred_extra_space_tracks 2
#WARNING (NRDB-537) Cannot find net clk
```

Same warning at `baseline_2026-08-06/logs/pnr_run_core70.log:30262`,
`baseline_2026-08-05/logs/pnr_stages.log:30685` and
`baseline_2026-08-05/logs/pnr_all.log:34895`. **No clock net has ever received extra
spacing on this design.** (`NRDB-537` has no page in
`/eda/cadence/innovus/doc/innovuserrmsg/`; the message text is self-explanatory.)

The cause is a name-space confusion: `-nets` takes a **net** name, and `clk` is the name of
an **SDC clock**. `work/design_clk.spec:139` records `create_clock_tree -name clk -source
CLK` — the clock `clk` is defined on port `CLK`, uppercase. **Inference:** the net is
therefore almost certainly `CLK`, and `-nets clk` misses it on case alone. This was not
confirmed by querying the netlist.

The manual gives the robust form, which does not depend on guessing a net name:

> `-nets netName` — "Specifies the net for which to set attributes. Do not enter more than
> one net name. To specify more than one net, use `*` and `?` wildcard characters. To
> specify non-default rule nets, use `@RULE`. **To specify clock nets, use `@CLOCK`.** To
> specify prerouted nets, use `@PREROUTED`."
> — `TCRcom/set_route_attributes.html`

`set_route_attributes -nets @CLOCK -preferred_extra_space_tracks 2` is what the line was
trying to say. **Not applied** — this page does not change scripts. Note also that fixing
it is a physical change: it will consume routing resource on a design that already finishes
at 92 % density, so it belongs in the same queue as the CTS cell lists, after hold.

**No non-default rule is used either.** `-route_rule` — "Identifies the non-default routing
rule to use with the specified net. Use this attribute for critical nets, such as clock
nets, that might need to have wider wires or wider spacing than other nets" — is never
specified, and neither is `create_route_type`/`cts_route_type_trunk`. The UG's Routing Rule
Recommendations section asks for double-width double-spacing shielded trunks and
double-width leaves. This design routes its clock nets with the default rule. That is a
known, deliberate simplification, and at 65 nm it is survivable; it would not be at a small
node.

### 3.3 Line 18 — multi-cut via effort

```tcl
18  set_db route_design_detail_use_multi_cut_via_effort medium
```

> `route_design_detail_use_multi_cut_via_effort {low | medium | high}` — Default: `low` —
> "Specifies the effort level toward increasing the ratio of double-cut vias to single-cut
> vias concurrently with routing. Increasing the effort level increases the double-cut via
> ratio and decreases the total number of vias in the design … The lower the number of
> single-cut vias, the better the yield will be.
> `low`: Specifies normal routing, so the router uses single-cut vias only.
> `medium`: Balances the need for a high double-cut via ratio with run time and congestion.
> Specifying this parameter increases the run time somewhat compared with the `low`
> parameter. The router inserts some double-cut vias, although not as many as if the `high`
> attribute were specified.
> `high`: Specifies the highest yield possible for vias, as the router puts its best effort
> toward achieving the highest possible double-cut via ratio at the expense of run time and
> congestion."
> — `TCRcom/route_Category_Attributes.html`

Unitless enum. `medium` is the middle setting: a real yield improvement over the `low`
default, without the congestion cost of `high`. On a design that finishes routing at 83.6 %
density and only later climbs to 92 % during hold repair
(`baseline_2026-08-06/reports/qor_05_route_opt.rep`),
`high` is worth evaluating once hold is fixed — but not before, because the congestion it
adds lands on the same resource hold repair is already exhausting.

### 3.4 Lines 21 and 24 — timing-driven and SI-driven routing

```tcl
21  set_db route_design_with_timing_driven 1
24  set_db route_design_with_si_driven 1
```

> `route_design_with_timing_driven { true | false }` — Default: `false` — "Minimizes timing
> violations by analyzing the timing slack for each path, the drive strengths of each cell
> in the library, and the maximum capacitance and maximum transition limits. During
> timing-driven routing, NanoRoute routes multi-pin nets to the most critical sink first,
> performs wire optimization by reducing resistance and coupling, and continually adjusts
> detouring. When this attribute is set to `1`, the router automatically generates a timing
> information file named `.timingfile.tif` in the working directory."
> — `TCRcom/route_Category_Attributes.html`

> `route_design_with_si_driven { true | false }` — Default: `false` — "Prevents or reduces
> crosstalk. Works in conjunction with timing-driven routing. When timing-driven routing is
> specified, uses SMART routing to identify victim nets and minimize crosstalk by wire
> spacing, layer hopping, net ordering, and minimizing the use of long parallel wires. When
> timing-driven routing is not specified, uses an older signal integrity engine…"
> — `TCRcom/route_Category_Attributes.html`

Both are booleans; `1` is `true`. Set together, they select **SMART routing** — both
attribute entries say so: "Specify `route_design_with_timing_driven` and
`route_design_with_si_driven` to run SMART routing."

**These two lines are almost certainly redundant with the command that follows them.**
`TCRcom/route_design.html`:

> "`route_design` is a super command that handles the setting of NanoRoute variables so
> that it is run in timing-driven mode then sets them back postRoute. **It runs SMART
> routing by default; that is, it runs in both timing- and signal integrity-driven mode by
> default.** Note: The other routing commands are not timing- or signal-integrity driven by
> default, but you can use the following route Category Attributes to turn on timing- and
> signal-integrity-driven routing for those commands…"

The attributes exist for `route_detail` and `route_global_detail`, which this flow does not
call. Since `4_pnr_route.tcl` uses `route_design`, lines 21 and 24 restate the default.
They are harmless and self-documenting, and they do have one real effect: the mode is
stored in the `.mode` file and honoured on a later restore-and-reroute
(`TCRcom/route_design.html`). Keep them; do not expect them to change QoR.

Note the asymmetry with line 18: `route_design_detail_use_multi_cut_via_effort` is *not*
part of the SMART default (its default is `low`), so that one is doing real work.

### 3.5 Lines 26–37 — where OCV went, and lines 39–45 — where filler went

Both blocks are comments recording a change made to fix a real defect, and both belong in
the file rather than only in a commit message:

- **26–37**: `set_db timing_analysis_type ocv` used to be here. Setting it at this point —
  after `ccopt_design` had already written back its source latencies — *is* the hold
  defect. See [§6](#6-the-hold-defect-at-command-level).
- **39–45**: `filler.tcl` is deliberately *not* sourced here. This file runs before
  `route_design`, so sourcing filler here inserted filler cells before any routing existed:
  `add_fillers -check_drc -fix_drc` had nothing to check ("Found no DRC violations to fix"),
  ANTENNA diodes went in before any antenna existed, and post-route hold repair then had to
  carve ~66,000 buffers back out of filled rows. Filler now runs from `place_bondpads.tcl`,
  after `opt_design -post_route -hold`. Details on
  [06-fill-antenna-bondpads.md](../06-fill-antenna-bondpads.md).

**Nothing else is set.** In particular `route_setup.tcl` sets no layer range
(`set_max_route_layer` / `-top_preferred_routing_layer` / `-bottom_preferred_routing_layer`
appear nowhere in the project), no antenna handling
(`route_design_diode_insertion_for_clock_nets` defaults to `false`; antennas are handled
post-route by the ANTENNA diodes in `filler.tcl` and checked by `check_process_antenna`),
no shielding, no via-in-pin, no litho-driven routing. A grep for
`max_route_layer|route_rule|non_default|route_type|add_route_vias|shield` across
`ASIC/genus-innovus/scripts/*.tcl` and `ASIC/asic-flows/Cadence/*.tcl` returns only the
`add_stripes_*` power-plan settings and the filler/antenna lines. The router is left to use
all nine metals with default rules.

---

## 4 — The CTS commands in `3_pnr_clock.tcl`

[`ASIC/asic-flows/Cadence/3_pnr_clock.tcl`](https://github.com/SoC-Labs/ASIC-Flow/blob/b19e7845448e641ea8353b19a59a77257907cb13/Cadence/3_pnr_clock.tcl).
This file lives in the shared `asic-flows` submodule; the project customises it only
through `cts_setup.tcl`.

```tcl
14  source ../scripts/config.tcl
16  soclabs_setup_multi_cpu
19  read_db $block_name
20  source $env(SOCLABS_ASIC_FLOW_DIR)/Cadence/procs.tcl
22  source ../scripts/cts_setup.tcl
25  create_clock_tree_spec -out_file design_clk.spec
28  ccopt_design
30  report_intermediate_step 02_cts $REPORT_DIR
33  opt_design -post_cts
34  opt_design -post_cts -hold
36  if {$DFT == 1} { reorder_scan -clock_aware true }
40  report_end_step 03_cts_opt $REPORT_DIR
42  write_db $block_name
```

### 4.1 Line 19 — `read_db $block_name`

Reads the database `2_pnr_setup.tcl` wrote. Because the stage scripts all write the same
name, this is the *post-place* database only as long as nothing has re-run since. That
fragility is exactly what `cts_setup.tcl:9` exists to contain.

### 4.2 Line 25 — `create_clock_tree_spec -out_file design_clk.spec`

Covered in [§1.3](#13-the-clock-tree-spec-and-skew-groups) and
[§1.4](#14-what-workdesign_clkspec-actually-is). Two points about ordering:

- It runs **after** `cts_setup.tcl`, so `cts_delay_cells` is already set when the spec is
  built. Correct.
- It is not given `-views`, so it "considers all active analysis views"
  (`TCRcom/create_clock_tree_spec.html`) — all five declared in the `.mmmc`, via the
  `set_analysis_view` on `nanosoc_eth_chiplet_pads.mmmc:198`. The UG's guidance is "For
  hold fixing — all dominant hold views, which are typically one to three views"
  (`UGcom/Clock_Tree_Synthesis.html`); this design has one, `default_analysis_view_hold`,
  plus `typical_analysis_view` doing double duty on both sides.

### 4.3 Line 28 — `ccopt_design`

Invoked bare:

> `ccopt_design [-help] [-check_cts_config] [-expanded_views] [-num_paths …] [-report_dir
> out_dir] [-report_prefix …] [-timing_debug_report]` — "Performs clock concurrent
> optimization (CCOpt) on the current loaded design in Innovus. CCOpt optimizes both the
> clock tree and the datapath to meet global timing constraints."
> — `TCRcom/ccopt_design.html`

No parameters are passed, so `-report_dir` defaults to `./timingReports` and
`-report_prefix` to `DesignName_DesignStage`. That is where the post-CTS optimisation
reports land — `work/timingReports/nanosoc_eth_chiplet_pads_postCTS*` — **not** in
`$REPORT_DIR` (`../reports`). See [§6.5](#65-where-the-hold-numbers-actually-live).

`-check_cts_config` ("Checks that all the prerequisites for running clock tree synthesis
are fulfilled without actually doing CTS") is a cheap dry-run that this flow never uses. On
a design where a full CTS is ~30 minutes, running it once after any change to
`cts_setup.tcl` is close to free.

Measured cost, from
`reports/qor_03_cts_opt.rep`:
`ccopt_design` 0:28:46, density 80.67 % → 83.21 %, 184,372 → 192,607 instances, setup WNS
+0.001.

### 4.4 Lines 33–34 — `opt_design -post_cts` and `-post_cts -hold`

> `-post_cts` — "Performs timing optimization on a design whose clock tree has been created.
> **By default, `-post_cts` repairs design rule violations and setup violations.** If the
> worst negative slack does not occur on a register-to-register path, `-post_cts` performs
> an additional optimization pass on the register-to-register critical paths when clock
> domains are not set. Does not repair maximum fanout design rule violations unless you
> first specify `opt_fix_fanout_load` attribute."
> — `TCRcom/opt_design.html`

> `-hold` — "Corrects hold violations. You cannot use this parameter if you specify
> `-pre_cts`. You can specify `-include_nets` or `-include_pins` if you use this parameter.
> This parameter creates a summary file in the output directory for the design. The file is
> named `prefix_hold.summary`. Use the `-report_prefix` parameter to specify the prefix. To
> report detailed debugging information, use `set_db opt_fix_hold_verbose true`."
> — `TCRcom/opt_design.html`

So `-post_cts` alone does **setup + DRV**; `-post_cts -hold` does **hold**. They are
separate passes and both are needed. Measured, from `reports/qor_03_cts_opt.rep`:

| Snapshot | setup WNS | density | instances | wall |
|---|---|---|---|---|
| `ccopt_design` | +0.001 | 83.21 % | 192,607 | 0:28:46 |
| `opt_design_postcts` | 0.000 | 83.14 % | 192,373 | 0:09:49 |
| `opt_design_postcts_hold` | 0.000 | 83.58 % | 194,143 | 0:04:30 |

`opt_design -post_cts` removes 234 instances and moves setup WNS by 0.001 ns in ten
minutes — consistent with the UG's claim that `ccopt_design` already did that work.
`opt_design -post_cts -hold` adds 1,770 instances in four and a half minutes and takes
post-CTS hold to WNS −0.000 / 2 violating paths
(`baseline_2026-08-06/work/timingReports/nanosoc_eth_chiplet_pads_postCTS_hold.summary.gz`).
**Post-CTS hold closes.** Everything that goes wrong, goes wrong later.

`opt_design` also "Sets the minimum recommended and appropriate set of attributes in the
following categories: timing, route_trial, opt, extract_rc" (`TCRcom/opt_design.html`) —
i.e. it will silently overwrite attributes you set by hand unless you set them *before* it
runs. The manual's tip is explicit: set attributes "before using `opt_design`".

### 4.5 Lines 30 and 40 — the report checkpoints

`report_intermediate_step` and `report_end_step` are project procs, defined in
[`ASIC/asic-flows/Cadence/procs.tcl`](https://github.com/SoC-Labs/ASIC-Flow/blob/b19e7845448e641ea8353b19a59a77257907cb13/Cadence/procs.tcl):

```tcl
proc report_intermediate_step {name REPORT_DIR} {
    report_timing_summary > $REPORT_DIR/timing_summary_${name}.rep
    report_timing -late   > $REPORT_DIR/timing_${name}_late.rep
    report_timing -early  > $REPORT_DIR/timing_${name}_early.rep
}
proc report_end_step {name REPORT_DIR} {
    ... the same three, plus report_power and report_qor -format text
}
```

`report_timing -early` is the *only* place in the whole flow where a hold path is printed
into `$REPORT_DIR`, and it prints exactly one. See
[§6.4](#64-why-the-flow-cannot-see-its-own-hold-failure).

### 4.6 Line 36 — `reorder_scan -clock_aware true`

Guarded by `if {$DFT == 1}`, and `config.tcl:123` sets `DFT 0`. Dead code on this design.

---

## 5 — The routing commands in `4_pnr_route.tcl`

[`ASIC/asic-flows/Cadence/4_pnr_route.tcl`](https://github.com/SoC-Labs/ASIC-Flow/blob/b19e7845448e641ea8353b19a59a77257907cb13/Cadence/4_pnr_route.tcl).

```tcl
18  read_db $block_name
26  source ../scripts/route_setup.tcl
29  route_design -global_detail
31  report_intermediate_step 04_route $REPORT_DIR
33  opt_design -post_route -hold
35  report_end_step 05_route_opt $REPORT_DIR
37  write_db $block_name
39  source ../scripts/place_bondpads.tcl
41  check_drc / check_filler / check_connectivity / check_process_antenna
46  report_timing … (six variants, two analysis-view configurations)
60  write_stream … ; 66 report_area ; 67 report_power
70  write_netlist ; 71 write_sdf ; 73 write_db
```

### 5.1 Line 29 — `route_design -global_detail`

> `-global_detail` — "Runs timing-driven and SI-driven global and detailed routing.
> **Note:** `-global_detail` is the default value for this command."
> — `TCRcom/route_design.html`

So the flag is explicit-but-default, like lines 21/24 of `route_setup.tcl`. Four behaviours
of `route_design` are worth knowing here, all from the same page:

- **It runs a placement check first** and warns if placement is not clean.
  `-no_placement_check` disables it; this flow does not, which is correct.
- **It changes clock nets from FIXED to ROUTED** so it can modify them, "Once the status of
  the clock nets is set to ROUTED, it does not change it back to FIXED." To keep them
  fixed you would set `route_design_fix_clock_nets 1`; this flow does not, so the CCOpt
  clock routing is re-routed here. That is normal, but it means CCOpt's routing estimates
  and the final clock routing are not the same thing.
- **It routes clock nets first** unless `route_design_route_clock_nets_first 1` is set to
  stop it.
- **It honours all `route` category attributes that do not have conflicts** — which is what
  makes `route_setup.tcl` work at all.

The UG adds: "Timing-driven routing might cause longer run time and more violations than
nontiming-driven routing" (`UGcom/Using_the_NanoRoute_Router.html`, Running Timing-Driven
Routing), and describes what SI-driven mode does automatically — "the NanoRoute router
automatically prevents crosstalk problems by wire spacing, net ordering, minimizing the use
of long parallel wires, and selecting routing layers for noise-sensitive nets"
(same page, Preventing and Repairing Crosstalk Problems). That automatic wire spacing is
*not* the same thing as `-preferred_extra_space_tracks`, and does not compensate for
[§3.2](#32-line-15-clock-net-spacing-this-line-is-a-no-op).

### 5.2 Line 33 — `opt_design -post_route -hold`

> `-post_route` — "Performs timing optimization on a design whose routing is complete. **By
> default, `-post_route` repairs design rule violations, glitch Violations and setup
> violations on Base & SI Delay.** … Maximum fanout design rule violations are not repaired
> by default."
> — `TCRcom/opt_design.html`

The parameter matrix section of the same page gives the intended two-command sequence:

> "To correct setup and hold (both base & SI) violations, use the following commands:
> `opt_design -post_route` / `opt_design -post_route -hold`.
> The software repairs a hold violation only if it does not make setup slack worse than the
> setup target slack on a path. An alternative way is to run setup and hold fixing within
> one command, and this may reduce the number of ecoRoute(s): `opt_design -post_route
> -setup -hold`."
> — `TCRcom/opt_design.html`

**This flow issues only the `-hold` form.** There is no bare `opt_design -post_route` and
no `-setup -hold`. In practice this matters less than it reads, because — as
[05-place-cts-route.md §route](../05-place-cts-route.md) documents from the logs — the
single line expands into the full post-route optimisation flow internally (setup recovery,
`HoldOpt`, `DrvOpt`, `ecoRoute`). The `opt_post_route_setup_recovery` and
`opt_post_route_hold_recovery` attributes exist precisely because those recovery steps are
triggered from `opt_design -post_route -setup -hold` and `opt_design -post_route -hold`
(`TCRcom/opt_Category_Attributes.html`). Still, the documented sequence is two commands and
this is one; if post-route setup ever stops closing, that is the first thing to try.

This command is the long pole of the entire flow: 2:34:28 wall in the reference run
(`baseline_2026-08-06/reports/qor_05_route_opt.rep`), against 0:31:24 for `ccopt_design`.

### 5.3 Lines 46–56 — the timing reports, and the analysis-view switch

```tcl
46  report_timing -output_format gtd -max_paths 10000 -path_exceptions all -early > timing_full_default_early.mtarpt
48  set_analysis_view -setup [list typical_analysis_view] -hold [list typical_analysis_view]
54  set_analysis_view -setup [list default_analysis_view_setup typical_analysis_view] -hold [list default_analysis_view_hold typical_analysis_view]
```

`set_analysis_view` is the command that binds views to the setup and hold sides:

> "Defines the analysis views to use for setup and hold analysis and optimization. You must
> define at least one setup and one hold analysis view. … When the `set_analysis_view`
> command is issued, it will cause a **full timing reset**. During a timing reset, all the
> interconnect parasitics, delays, and timing slacks will be recalculated. … The
> `set_analysis_view` command does not work in an incremental manner … Each invocation of
> this command must include the full specification of all the active views required for
> analysis."
> — `TCRcom/set_analysis_view.html`

Two full timing resets at the end of a five-hour run is expensive but correct: line 48
narrows to the typical corner to produce the `_typical_` reports, and line 54 restores the
original binding from `nanosoc_eth_chiplet_pads.mmmc:198`. If you add reports here, restore
the view set afterwards or everything downstream — including `write_sdf` on line 71, which
names `default_analysis_view_hold` as its `-min_view` — is analysed against the wrong
corner.

Note that **`-hold` on `set_analysis_view` is where the hold view enters the flow at all.**
`default_analysis_view_hold` is built from `default_delay_corner_min`, which is
`tc_min`/`tc_min` over `default_rc_corner_best` (`nanosoc_eth_chiplet_pads.mmmc:176–179`).
There is exactly one dedicated hold view.

---

## 6 — The hold defect, at command level

[16-open-defects.md §1](../16-open-defects.md#1-clock-source-latency-is-asymmetric-in-the-hold-view)
is the design-level account: what is wrong, what it cost, and how it was found. This
section is the command-level companion — which commands and attributes govern hold repair
in this flow, what the flow sets, what it fails to set, and what the `holdexp/` experiments
actually measured. It does not repeat the diagnosis.

### 6.1 The one-line summary, for anyone arriving here first

Post-CTS hold closes (WNS −0.000, 2 violating paths). Post-route hold does not: **WNS
−1.167 ns, TNS −66,211.9 ns, 96,545 violating paths**. The headline "WNS +0.079, 0 failing
endpoints" is setup-only. The cause is that `ccopt_design`'s source-latency writeback
emitted only the `-min` side for `default_analysis_view_hold`, and `timing_analysis_type
ocv` was then switched on *after* CTS, splitting min from max with nothing on the max side.

### 6.2 The commands and attributes that govern hold in this flow

| Layer | Object | Set here? |
|---|---|---|
| Hold **view** exists | `create_analysis_view -name default_analysis_view_hold -delay_corner default_delay_corner_min` (`.mmmc:191`) | yes |
| Hold view is **active** | `set_analysis_view … -hold [list default_analysis_view_hold typical_analysis_view]` (`.mmmc:198`, restored at `4_pnr_route.tcl:54`) | yes |
| Min/max **separation** | `set_db timing_analysis_type ocv` (`cts_setup.tcl:72`) | yes — and its *position* is the defect |
| Hold **repair, post-CTS** | `opt_design -post_cts -hold` (`3_pnr_clock.tcl:34`) | yes |
| Hold **repair, post-route** | `opt_design -post_route -hold` (`4_pnr_route.tcl:33`) | yes |
| Hold repair **tuning** | the `opt_hold_*` attributes | **no — none of them** |
| Hold **reporting** | `report_timing -early` (one path), `*_hold.summary` (buried) | partially |

**Hold repair is enabled.** It is enabled the only way this flow enables anything — by the
`-hold` flag on `opt_design`, at both post-CTS and post-route. It has never been disabled,
skipped or guarded. The design's hold failure is not a case of hold repair being switched
off; it is a case of hold repair running for two and a half hours against a corrupted
constraint and inserting 37,407 instances chasing 1.076 ns of skew that does not exist.

### 6.3 What the flow sets, and what it does not

The prompt for this page guessed at `set_db opt_fix_hold_*` attributes. That family is
almost entirely misnamed: in 21.11 the attributes are `opt_hold_*`. Exactly one
`opt_fix_hold_*` name exists, and it is only mentioned inside another page's prose —
`set_db opt_fix_hold_verbose true`, cited by `TCRcom/opt_design.html` under `-hold` as the
way to "report detailed debugging information". A grep of `TCRcom/*.html` for
`opt_fix_hold` returns that one hit and nothing else.

The real knobs, from `TCRcom/opt_Category_Attributes.html`, with their defaults, **none of
which this project sets**:

| Attribute | Default | What it does |
|---|---|---|
| `opt_hold_target_slack` | `0.0` | "Specifies a target slack value in nanoseconds to use for hold analysis only." |
| `opt_hold_slack_threshold` | — | "Allows you to provide a hold slack threshold beyond which the hold timing violations will not be fixed. This is used to avoid fixing out of bound violations at an early stage… The slack value is specified in nano seconds (ns). … The threshold value specified is for hold WNS." |
| `opt_hold_cells` | `""` | "Allows you to force the usage of only a specific list of buffer and delay cells. … This attribute does not support wildcards." |
| `opt_hold_allow_resize` | `auto` | "When `auto` is specified, the post-CTS hold optimization resizing is set to 'on' and post-Route hold optimization resizing is set to 'off'." |
| `opt_hold_allow_overlap` | `auto` | Insert hold buffers with overlap when no legal space exists, legalising afterwards. |
| `opt_hold_allow_setup_tns_degradation` | `true` | "By default, the software allows the slack to degrade in order to fix more hold violations." |
| `opt_hold_ignore_path_groups` | — | "Specifies the clock domains or path groups that should be excluded from hold timing optimization. This attribute impacts only `opt_design -post_cts/-post_route -hold`." |
| `opt_hold_on_excluded_clock_nets` | `false` | Hold fixing on excluded clock nets. |
| `opt_post_route_hold_recovery` | `false` | "Controls the Hold Recovery step performed when `opt_design -post_route -setup -hold` and `opt_design -post_route -hold` commands have been specified." |

Three of these defaults are directly implicated in what the reference run did:

- `opt_hold_slack_threshold` unset means **no ceiling**. Every one of the 96,545 phantom
  violations was in scope. Setting it (to, say, −0.5) would have capped the damage — but it
  would also have hidden the defect, so this is a mitigation, not a fix.
- `opt_hold_allow_setup_tns_degradation` defaulting to `true` means hold repair was
  permitted to eat setup TNS to fix more hold. It did not need to; setup closed. But it is
  worth knowing the default is the permissive one.
- `opt_hold_cells` unset means the tool chose its own hold cells. It chose `DEL0` among
  others — visible in the repaired data path of
  `reports/holdexp2_after.rpt`,
  where `FE_PHC19773_rstn_shift_1/Z` is a `DEL0` contributing 0.275 ns. Note again
  ([§2.3](#23-line-24-cts_delay_cells)) that this is `opt`'s choice, not
  `cts_delay_cells`'.

The flow's MMMC also documents an attempt and its failure. `nanosoc_eth_chiplet_pads.mmmc`
lines 105–165 record that the delay corners were rewritten to name
`-early_timing_condition` **and** `-late_timing_condition` explicitly instead of a single
`-timing_condition`, in the hope of forcing a two-sided writeback. The comment's verdict,
lines 160–165: **no effect** — the writeback was byte-identical and post-CTS hold unchanged.
`set_clock_latency -min/-max` is a property of the clock, not of the delay corner. The
two-sided declarations were kept because they are more explicit, not because they fixed
anything.

### 6.4 Why the flow cannot see its own hold failure

This is the part that made the defect survive for months, and it is entirely a
command-level story.

**`report_timing_summary` degrades to setup-only.** The command *does* default to all three
check types — "`-checks {setup | hold | drv}` … Default: `setup hold drv`"
(`TCRcom/report_timing_summary.html`). But `procs.tcl` calls it bare, and the first line of
every summary this flow has ever written is:

```
reports/timing_summary_03_cts_opt.rep:1
**ERROR: (TCLCMD-1130):	The '-late' and '-early' options to the report_timing_summary
command can only be specified together when the timing system is in simultaneous setup and
hold mode. You can use 'set_global timing_enable_simultaneous_setup_hold_mode true' to
enable this mode for timing analysis only. All non-timing commands are disabled while the
system is in simultaneous setup/hold mode. Ignoring '-early' and using '-late' alone.
```

The tool tells you exactly what happened: it wanted both sides, could not have both, and
**silently kept the late (setup) side**. The report that follows has a SETUP block, a DRV
block and a Clock-checks block, and no hold block at all. `TCLCMD-1130` has no page in
`/eda/cadence/innovus/doc/innovuserrmsg/`.

The remedy the message names carries a heavy caveat, and a second one from elsewhere:
enabling `timing_enable_simultaneous_setup_hold_mode` disables all non-timing commands, and
per `TCRcom/write_db.html` the attribute's state is not saved in the database — "When the
attribute is set to `true`, various physical design functions in the system are disabled.
When the design is restored (using the `read_db` command), the physical design commands are
required to be active…". It is a report-time-only mode.

**`report_qor` has no hold columns.** The QoR table written by `report_end_step` is
`Snapshot | WNS (ns) | TNS (ns) | FEPS | WNS_R2R | TNS_R2R | FEPS_R2R | DRV(T) | DRV(C) |
POWER(L) | UTIL | INSTS | AREA | DRC | WALL`
(`reports/qor_03_cts_opt.rep`).
Those WNS/TNS/FEPS columns are setup. The row `opt_design_postroute_hold | 0.079 | 0 | 0`
in `baseline_2026-08-06/reports/qor_05_route_opt.rep` — the source of the "WNS +0.079, 0
failing endpoints" headline — is the *setup* result of the hold-repair step.

**`report_timing -early` shows one path.** `procs.tcl` writes `timing_${name}_early.rep`
with no `-max_paths`, so you get the single worst hold path. Enough to notice a problem, not
enough to size one.

Net effect: the flow writes 20+ report files into `$REPORT_DIR` and **not one of them
contains a hold WNS/TNS/FEP triple.**

### 6.5 Where the hold numbers actually live

`opt_design -hold` writes them itself, and the manual says where:

> "This parameter creates a summary file in the output directory for the design. The file
> is named `prefix_hold.summary`."
> — `TCRcom/opt_design.html`, `-hold`

With `-report_dir` defaulting to `timingReports` and `-report_prefix` to
`DesignName_DesignStage` (same page), the file is:

```
work/timingReports/<block>_postRoute_hold.summary.gz
work/timingReports/<block>_postCTS_hold.summary.gz
```

`zcat baseline_2026-08-06/work/timingReports/nanosoc_eth_chiplet_pads_postRoute_hold.summary.gz`:

```
#  Command:           opt_design -post_route -hold
     opt_design Final SI Timing Summary
+--------------------+---------+---------+---------+---------+
|     Hold mode      |   all   | reg2reg |reg2cgate| default |
+--------------------+---------+---------+---------+---------+
|           WNS (ns):| -1.167  | -1.167  | -1.086  | -0.574  |
|           TNS (ns):|-66211.9 |-66208.9 | -2.000  | -1.507  |
|    Violating Paths:|  96545  |  96536  |    2    |    8    |
|          All Paths:|1.33e+05 |1.29e+05 |    2    |  17729  |
+--------------------+---------+---------+---------+---------+
   max_cap    213 (213)   -0.189
   max_tran   153 (3227)  -3.397
Density: 92.167%
```

**This is the source of every hold number in 16-open-defects.md.** The equivalent post-CTS
file shows WNS −0.000 / TNS −0.000 / 2 violating paths. The two files, side by side, are the
whole defect in twelve lines.

Note they are `.gz`, under `work/`, and not in `$REPORT_DIR` — no make target copies them
out. The same "Hold mode" table is also echoed into the stage log (four times in
`baseline_2026-08-06/logs/pnr_run_core70.log`, the post-route one at line 33490), and that
is where [`scripts/ci/asic_stage_report.sh`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/scripts/ci/asic_stage_report.sh)
picks the hold numbers up — its own comment at line 117 says "HOLD IS NOT IN
`timing_summary_*.rep` AT ALL … The hold numbers exist only in the stage log's 'Hold mode'
table, so parse that." So CI *does* surface hold; `$REPORT_DIR` does not.

`opt_design` also offers `-hold_violation_report fileName`, which "Generates the following
report files for the violation data that remains after hold fixing: `fileName.txt` … top 50
hold violation paths (text format), `fileName.csv` … (csv format), `fileNameDetailed.txt` …
detailed information for the top 50 hold violation paths" (`TCRcom/opt_design.html`). The
flow does not use it. It is the cheapest possible improvement to hold visibility.

### 6.6 The `holdexp/` experiments — what they actually measured

Three scripts in `ASIC/genus-innovus/holdexp/`. All
three read `baseline_2026-08-06/work/nanosoc_eth_chiplet_pads_cts` — the post-CTS snapshot
that `route_setup.tcl:12` exists to produce — so none of them disturbed the live run. **Two
of the three did not do what they set out to do. Read the results, not the intentions.**

#### `hold_experiment.tcl` — FAILED, measured nothing

Intent: mirror the `-min` source latency onto `-max` on the `_cts` snapshot and re-measure
hold. Result, from
`holdexp.out:1127–1163`:

```
HOLDEXP before: slack=?   (full report ../reports/holdexp_before.rpt)
**WARN: (TCLCMD-513):	The software could not find a matching object of the specified type for the pattern 'CLK'
**ERROR: (TCLCMD-917):	Cannot find 'pins' that match 'CLK'
**ERROR: (TCLCMD-1048):	constraints are specified but no constraint mode is enabled interactively.
HOLDEXP: set_clock_latency -early -max -rise FAILED:
    ... x4, all four failed ...
HOLDEXP after: slack=?
```

Three independent faults: the target `[get_pins CLK]` does not resolve (`CLK` is a port, not
a pin); no interactive constraint mode was enabled, so any SDC command would have failed
regardless; and the slack regexp looked for `Slack Time` where the report says `Slack:=`, so
both measurements returned `?`. **This run produced no data.** Its one useful output was the
`before` report on disk, which showed the `0.000 / −1.108` asymmetry arithmetically.

#### `hold_experiment2.tcl` — RAN, and the result is partial

Two corrections: `set_interactive_constraint_modes [all_constraint_modes -active]` before
applying SDC, and `[get_clocks clk]` instead of `[get_pins CLK]`. All four
`set_clock_latency` calls then succeeded. From
`holdexp2.out:1129–1184`:

```
HOLDEXP2 before: slack=-1.086  src_latency capture=0.000 launch=-1.108
HOLDEXP2: applied -source -early -max -rise -1.07637
HOLDEXP2: applied -source -late  -max -rise -1.07637
HOLDEXP2: applied -source -early -max -fall -1.10823
HOLDEXP2: applied -source -late  -max -fall -1.10823
HOLDEXP2 after:  slack=-0.808  src_latency capture=0.000 launch=-0.808
```

**Read this carefully. The prediction was "hold WNS moves from about −1.1 to about −0.1";
the measurement was −1.086 → −0.808.** That is a 0.278 ns improvement, not the ~1.0 ns the
hypothesis predicted, and it is *not* the same path before and after:

| | before (`holdexp2_before.rpt`) | after (`holdexp2_after.rpt`) |
|---|---|---|
| check | Clock Gating Hold Check | Hold Check |
| group | `clock_gating_default` | `rmii_ref_clk` |
| clock | `clk` | `rmii_ref_clk` |
| capture / launch src latency | 0.000 / −1.108 | 0.000 / −0.808 |
| uncertainty | 0.050 | 0.350 |
| slack | −1.086 | −0.808 |

The fix was applied to `clk` **only**. The worst path relocated to `rmii_ref_clk`, which
carries the identical `-min`-only signature and was therefore untouched. Note the capture
source latency is *still* 0.000 in the "after" report — because the reported path is now on
a different clock. So the experiment confirms the **mechanism** (fixing one clock moves that
clock's paths out of the worst position) without demonstrating the **outcome** (a fixed
design). All four written-back clocks need the same treatment, and even then
[16-open-defects.md §1](../16-open-defects.md#1-clock-source-latency-is-asymmetric-in-the-hold-view)
records that the symmetric `typical_analysis_view` still shows hold WNS −0.116, so roughly
0.1 ns of hold violation is real and will still need ordinary repair.

Two command-level lessons worth keeping:

- **`set_interactive_constraint_modes` is mandatory** for any SDC command applied
  interactively to a restored database. Without it you get `TCLCMD-1048` and the command is
  a silent no-op inside a `catch`.
- **`report_timing -early` is the hold report.** Both experiments used it; it is the only
  hold view the flow offers without extra work.

#### `probe_latency_attrs.tcl` — pure discovery, mostly negative

Intent: find a reliable way to read back the `-min` source latency, so a production fix
could *derive* the mirrored `-max` instead of hardcoding numbers that change every run.
Result, from `probe.out`:

| Probe | Result |
|---|---|
| `get_db clocks` | 27 objects — clocks are **per-view**: `default_analysis_view_setup/clk`, `typical_analysis_view/clk`, `default_analysis_view_hold/clk`, … |
| `get_db $c .?` and `.??` | `FORM .? OK, 0 entries` / `FORM .?? OK, 0 entries` — no attribute listing |
| 11 candidate attribute names (`source_latency`, `latency`, `source_latency_late_rise`, `insertion_delay`, …) | **all 11** returned `IMPDBTCL-248: '<name>' is not a recognized object or attribute for object type 'clock'` |
| `report_clock_timing -type latency \| summary \| skew` | all three OK |
| `get_clock_info` | absent |
| `report_clock_latency` | absent |
| `report_clocks` | exists (not exercised) |

**No clock object attribute exposes the applied source latency.** The derivation the
production fix wanted is not available that way, which is precisely why enabling OCV before
CTS — so `ccopt_design` emits both sides itself — was chosen over mirroring after the fact.

The probe did leave the three `reports/probe_clk_*.rpt` files behind, and they contain one
more finding the probe script did not notice. See [§7](#7-reading-the-clock-reports).

### 6.7 What the fix looks like, and the evidence that it works

The fix is one line moved: `set_db timing_analysis_type ocv` from `route_setup.tcl` to
`cts_setup.tcl:72`, before `ccopt_design`. Counting `-min` and `-max` in the
`ccopt_design` I/O-latency writeback, per view — 16 lines each is the full set (4 clock
roots × early/late × rise/fall):

| View | Before (`baseline_2026-08-06/logs/pnr_run_core70.log`) | After (`logs/cts_ocvfirst.log`) |
|---|---|---|
| `default_analysis_view_setup` | `-min` 0, `-max` 16 | `-min` 16, `-max` 16 |
| `default_analysis_view_hold` | **`-min` 16, `-max` 0** | **`-min` 16, `-max` 16** |
| `typical_analysis_view` | `-min` 16, `-max` 16 | `-min` 16, `-max` 16 |

Reproduce with:

```sh
cd ASIC/genus-innovus
for v in default_analysis_view_setup default_analysis_view_hold typical_analysis_view; do
  for s in min max; do
    printf '%s %s ' "$v" "$s"
    grep -v '^@file' logs/<log> | grep -A1 "View: $v," | grep -c " -$s "
  done
done
```

That is the check `cts_setup.tcl:69–71` asks you to run after any CTS run, and it must not
regress.

**Status, and a caution.** The `logs/cts_ocvfirst.log` figures above were read from a run
that was **still executing** at the time of writing (an `innovus -stylus -files
3_pnr_clock.tcl` process started 10:52, log last written 11:20, mid-`DrvOpt` in post-CTS
optimisation). The writeback happens early in CTS and is complete and unambiguous in the
log. **The downstream numbers are not yet known**: post-CTS hold, post-route hold, cell
count and density from this configuration had not been produced when this page was written.
[16-open-defects.md](../16-open-defects.md)'s honest caveat still stands — removing ~1.05 ns
of phantom skew should let hold repair converge on the real residue with a fraction of the
37,407 cells, but that has not been demonstrated end to end. Do not report hold as fixed on
the strength of the writeback alone.

---

## 7 — Reading the clock reports

[07-reading-reports.md](../07-reading-reports.md) covers report reading generally — the
timing summary, the QoR table, `report_timing` path anatomy, power and area. It does not
cover `report_clock_timing`, which is the clock-specific family, so this is the short
addendum.

Three files exist in `ASIC/genus-innovus/reports/`, all produced by
`probe_latency_attrs.tcl:32–36`, which ran `report_clock_timing -type {latency,summary,skew}`
with no other arguments:

| File | `-type` | Shows |
|---|---|---|
| `probe_clk_latency.rpt` | `latency` | per sink pin: `Source`, `Network`, `Total` latency |
| `probe_clk_skew.rpt` | `skew` | per clock: the two pins defining worst skew, with their latencies |
| `probe_clk_summary.rpt` | `summary` | per clock: max launch latency, min capture latency, max skew |

All three are organised **per (clock, analysis view)**, with 14 blocks each. Latency and
skew are in nanoseconds. The `Source` column is the clock source latency and the `Network`
column the insertion delay from root to sink; `Total` is their sum.

**Two traps, both of which these files fall into.**

1. **They contain no hold-view data at all.** All 14 blocks in each file are
   `default_analysis_view_setup` or `typical_analysis_view`. `default_analysis_view_hold`
   appears nowhere. The manual explains why: "`-early` Uses hold skew to generate the
   report. Hold skew is the difference between minimum latency at the start point flip-flop
   and the maximum latency at the end point flip-flop. **Default: Uses the setup skew.**"
   (`TCRcom/report_clock_timing.html`). The probe passed neither `-early` nor `-view`. For
   the hold view you must ask:

   ```tcl
   report_clock_timing -type latency -view default_analysis_view_hold
   report_clock_timing -type latency -early
   ```

   which is exactly the verification command
   [16-open-defects.md §1](../16-open-defects.md#1-clock-source-latency-is-asymmetric-in-the-hold-view)
   recommends.

2. **A `redirect`-captured report carries ~190 lines of RC-extraction and delay-calculation
   noise before the first `Clock:` block** — cap tables, `IMPCTE-337`, `IMPESI-3086` noise
   warnings, "Using master clock 'rmii_ref_clk' for generated clock 'mii_tx_clk'". Grep for
   `'^  Clock: '` to find the real content.

What the setup-view latency table shows, for the record:

```
clk            default_analysis_view_setup  src=0.000     net=1.002     tot=1.002
clk            typical_analysis_view        src=0.000     net=0.648     tot=0.648
mii_tx_clk     default_analysis_view_setup  src=-0.289    net=0.307     tot=0.018
rmii_ref_clk   default_analysis_view_setup  src=0.000     net=-0.059    tot=-0.059
```

`clk` reports a source latency of 0.000 in the setup view even though the writeback wrote 16
`-max` lines for that view. **Inference:** the default (setup-skew) report is displaying the
side the setup view does *not* have. This was not confirmed — it is the obvious reading of
the numbers, and the way to settle it is `report_clock_timing -type latency -early` versus
`-late` on the same snapshot, which nobody has run.

The `report_clock_timing` command also accepts `-format {instance arc pin cell slew load}`
with `-verbose`, `-nworst`, `-greater_than` and `-cppr_relative`, all documented on
`TCRcom/report_clock_timing.html`. None have been used on this design.

The commands the CCOpt flow offers for clock-tree structure rather than clock timing —
`report_ccopt_clock_trees`, `report_ccopt_skew_groups`, `report_ccopt_clock_tree_structure`,
`report_ccopt_worst_chain` — all have pages under `TCRcom/`, and none are called anywhere in
this flow. [05-place-cts-route.md](../05-place-cts-route.md) suggests two of them.

---

## 8 — Citation index

Every manual page cited above was opened and read. Nothing here is cited from memory.

**Innovus Stylus Common UI Text Command Reference**, `/eda/cadence/innovus/doc/TCRcom/`:

| Page | Cited for |
|---|---|
| `ccopt_design.html` | command definition, `-check_cts_config`, `-report_dir`/`-report_prefix` defaults |
| `create_clock_tree_spec.html` | spec semantics, one skew group per SDC clock per constraint mode, `-out_file` is not executed, `-views` default |
| `opt_design.html` | `-post_cts`, `-post_route`, `-setup`, `-hold`, `-hold_violation_report`, `-report_dir`/`-report_prefix`, the `prefix_hold.summary` file, `opt_fix_hold_verbose`, the two-command post-route sequence |
| `route_design.html` | `-global_detail` is the default, SMART routing by default, super-command behaviour, clock nets FIXED→ROUTED, `.mode` persistence, placement check |
| `set_route_attributes.html` | `-nets` (incl. `@CLOCK`), `-preferred_extra_space_tracks` (range 0–3, soft rule), `-route_rule`, `-multi_cut_via_effort`, DB persistence, not saved in DEF |
| `set_analysis_view.html` | `-setup`/`-hold`, full timing reset, non-incremental |
| `report_timing_summary.html` | `-checks` default `setup hold drv` |
| `report_clock_timing.html` | `-type` values, `-early` = hold skew, default = setup skew, `-view`, `-format` |
| `write_db.html` | native DB format, usable after `init_design`, does not save `timing_enable_simultaneous_setup_hold_mode` |
| `cts_Category_Attributes.html` | `cts_buffer_cells`, `cts_inverter_cells`, `cts_delay_cells` — defaults, semantics, `dont_use` override |
| `route_Category_Attributes.html` | `route_design_detail_use_multi_cut_via_effort`, `route_design_with_timing_driven`, `route_design_with_si_driven` |
| `timing_Category_Attributes.html` | `timing_analysis_type` |
| `opt_Category_Attributes.html` | the `opt_hold_*` family and `opt_post_route_hold_recovery` |

**Innovus Stylus Common UI User Guide**, `/eda/cadence/innovus/doc/UGcom/`:

| Page | Cited for |
|---|---|
| `Clock_Tree_Synthesis.html` | CCOpt vs `clock_design`; why skew balancing does not close timing; the pre-CTS configuration requirement ("OCV timing derates or AOCV enabled"); Source Latency Update; `cts_update_io_latency`; Library Cells recommendations; Transition Target; Skew Target; `cts`/`ccopt` attribute categories |
| `Using_the_NanoRoute_Router.html` | SMART routing definition; timing-driven routing caveats; automatic crosstalk prevention |

**Innovus User Guide (legacy)**, `/eda/cadence/innovus/doc/innovusUG/`:

| Page | Cited for |
|---|---|
| `CCOpt_Properties.html` | `set_ccopt_property`/`get_ccopt_property` syntax; `update_io_latency` (default `true`); `force_update_io_latency`; the property↔attribute mapping |

**Not found.** `TCLCMD-1130`, `TCLCMD-1048`, `TCLCMD-917`, `IMPDBTCL-248` and `NRDB-537`
have no pages in `/eda/cadence/innovus/doc/innovuserrmsg/`. Their text is quoted from the
logs and reports in this repository, not from a manual.

**Repository evidence used.** `ASIC/genus-innovus/scripts/cts_setup.tcl`,
`route_setup.tcl`, `nanosoc_eth_chiplet_pads.mmmc`, `config.tcl`;
`ASIC/asic-flows/Cadence/3_pnr_clock.tcl`, `4_pnr_route.tcl`, `2_pnr_setup.tcl`,
`procs.tcl`; `ASIC/genus-innovus/work/design_clk.spec`;
`ASIC/genus-innovus/holdexp/{hold_experiment.tcl,hold_experiment2.tcl,probe_latency_attrs.tcl,holdexp.out,holdexp2.out,probe.out}`;
`ASIC/genus-innovus/reports/{holdexp2_before.rpt,holdexp2_after.rpt,probe_clk_*.rpt,qor_03_cts_opt.rep,timing_summary_03_cts_opt.rep}`;
`ASIC/genus-innovus/logs/{cts_ocvfirst.log,pnr_run_ocvfix.log}`;
`ASIC/genus-innovus/baseline_2026-08-06/{logs/pnr_run_core70.log,reports/qor_05_route_opt.rep,work/timingReports/*_hold.summary.gz}`;
`ASIC/genus-innovus/baseline_2026-08-05/logs/{pnr_all.log,pnr_stages.log}`.

No Innovus, Genus, Calibre or LEC session was opened to produce this page.
