# `power_plan.tcl` — annotated reference

Block: `nanosoc_eth_chiplet_pads` · TSMC 65nm LP `9M_6X1Z1U` (+RDL) · Cadence Innovus 21.11-s130_1,
**STYLUS / Common UI**.

Subject: [`ASIC/genus-innovus/scripts/power_plan.tcl`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/power_plan.tcl)
— 169 lines, sourced by
[`asic-flows/Cadence/2_pnr_setup.tcl:47`](https://github.com/SoC-Labs/ASIC-Flow/blob/b19e7845448e641ea8353b19a59a77257907cb13/Cadence/2_pnr_setup.tcl),
immediately after `floorplan.tcl` and **before** `place_design` (line 56 of the same file).

This page annotates the script command by command against the installed Cadence manuals. It is the
*reference*; [04-power-plan](../04-power-plan.md) is the *narrative* — the traps, the history, the
sign-off checklist. Where the two overlap this page defers and links.

### Manuals cited

Only pages actually opened while writing this are cited. Paths are on this machine.

| Short form | Full title / version | Path |
|---|---|---|
| **Stylus TCR** | Innovus Stylus Common UI Text Command Reference, Product Version **21.11**, July 2021 | `/eda/cadence/innovus/doc/TCRcom/` |
| **Stylus UG** | Innovus Stylus Common UI User Guide | `/eda/cadence/innovus/doc/UGcom/` |
| **Legacy TCR** | Innovus Text Command Reference (native UI), Product Version 21.11, July 2021 | `/eda/cadence/innovus/doc/innovusTCR/` |
| **Msg Ref** | Innovus Error Message Reference, Product Version **21.10**, May 2021 | `/eda/cadence/innovus/doc/innovuserrmsg/` |
| **CPF Ref** | Common Power Format Language Reference, Product Version 2.0, October 2019 | `/eda/cadence/innovus/doc/cpf_ref/` |

> This flow is **stylus**, so every command below is cited from `TCRcom/`. The legacy `innovusTCR/`
> edition is a *different command set* (`addRing`, `addStripe`, `sroute`, `globalNetConnect`) and is
> cited here only where a legacy page is needed to prove that an option in this script exists
> **nowhere** — see §3.9. Note also that the message reference installed here is **21.10**, one
> minor version behind the tool; that gap matters in §4.

---

## Contents

- [1. The PG topology as actually built](#1-the-pg-topology-as-actually-built)
  - [1.1 Nets](#11-nets)
  - [1.2 Plan view](#12-plan-view)
  - [1.3 Cross-section](#13-cross-section)
  - [1.4 What connects to what](#14-what-connects-to-what)
- [2. Metal stack context — `9M_6X1Z1U`](#2-metal-stack-context-9m_6x1z1u)
- [3. The script, in order](#3-the-script-in-order)
  - [3.1 Lines 8–42 — the `PD_TOP` guard](#31-lines-842-the-pd_top-guard)
  - [3.2 Lines 44–49 — `connect_global_net`](#32-lines-4449-connect_global_net)
  - [3.3 Lines 50–55 — stacked-via limits and `add_rings`](#33-lines-5055-stacked-via-limits-and-add_rings)
  - [3.4 Lines 56–72 — `route_special`, pads to ring](#34-lines-5672-route_special-pads-to-ring)
  - [3.5 Lines 74–93 / 99–117 — the `add_stripes` attribute preamble](#35-lines-7493-99117-the-add_stripes-attribute-preamble)
  - [3.6 Line 94 — M8 vertical stripes](#36-line-94-m8-vertical-stripes)
  - [3.7 Lines 118–132 — M9 horizontal stripes](#37-lines-118132-m9-horizontal-stripes)
  - [3.8 Lines 136–159 — macros, `split_row`, M5 stripes](#38-lines-136159-macros-split_row-m5-stripes)
  - [3.9 Lines 163–164 — `add_endcaps`](#39-lines-163164-add_endcaps)
  - [3.10 Lines 166–168 — the closing `route_special` passes](#310-lines-166168-the-closing-route_special-passes)
- [4. The `connect_global_net` PG-pin problem](#4-the-connect_global_net-pg-pin-problem)
- [5. Why a domain with no supply nets stops filler insertion](#5-why-a-domain-with-no-supply-nets-stops-filler-insertion)
- [6. Verification — what actually proves this plan is sound](#6-verification-what-actually-proves-this-plan-is-sound)
- [7. Dependencies — what must change if…](#7-dependencies-what-must-change-if)
- [8. Defects and unverified claims found writing this page](#8-defects-and-unverified-claims-found-writing-this-page)
- [See also](#see-also)

---

## 1. The PG topology as actually built

### 1.1 Nets

`config.tcl:125-126` declares five global nets, which
[`2_pnr_setup.tcl:20-21`](https://github.com/SoC-Labs/ASIC-Flow/blob/b19e7845448e641ea8353b19a59a77257907cb13/Cadence/2_pnr_setup.tcl) feeds to
`set_db init_power_nets` / `init_ground_nets` before `init_design`:

```tcl
set power_nets  {VDD VDDACC VDDIO}
set ground_nets {VSS VSSIO}
```

What `power_plan.tcl` then does with each:

| Net | `connect_global_net` | Ring | Stripes | `route_special` | Net result |
|---|---|---|---|---|---|
| `VDD` | L46, pin `VDD` | M9 top/bot, M8 l/r | M8, M9, M5 | L56, L166, L168 | full mesh |
| `VSS` | L48, pin `VSS` | M9 top/bot, M8 l/r | M8, M9, M5 | L65, L166, L168 | full mesh |
| `VDDIO` | L47, pin `VDDPST` | — | — | — | pad-level only |
| `VSSIO` | L49, pin `VSSPST` | — | — | — | pad-level only |
| `VDDACC` | **none** | — | — | — | **declared, never used** |

Two things fall straight out of that table and are not stated in
[04-power-plan](../04-power-plan.md):

- **`VDDACC` is a dead declaration.** It is in `init_power_nets`, so a global net object exists in
  the database, but no `connect_global_net`, `add_rings`, `add_stripes` or `route_special` in this
  file names it. Its only other appearance in the repo is the Synopsys ICC2/Fusion flow
  (`asic-flows/Synopsys_DC_ICC2/2_pnr_design_setup.tcl:52-65`), where it is the supply of an `ACCEL`
  voltage area that the Cadence flow does not have. See §8.
- **`VDDIO` / `VSSIO` get a global-net rule and nothing else.** No ring, no stripe, no special
  route. That is not an oversight in the way it first looks — see §1.4.

### 1.2 Plan view

At `CORE_TO_IO 70` (`floorplan.tcl:79-81`) the die is fixed at 1600 × 2000 µm and the pad row is
135 µm tall, so the core box is inset by 135 + 70 = 205 µm on every side:

```
 die (0,0) ────────────────────────────────────────────── (1600,2000)
  ┌────────────────────────────────────────────────────────────────┐
  │  staggered bond ring (tpbn65v) — PAD70GU outer / PAD70NU inner │
  │  ┌──────────────────────────────────────────────────────────┐  │
  │  │ IO row, 135 µm tall: 34 supply pads + signal pads +      │  │
  │  │ PFILLER20/10/5/1/05_G spacers        <- pad_ring, L166   │  │
  │  │  ┌────────────────────────────────────────────────────┐  │  │
  │  │  │        VSS core ring   M9 top/bottom, M8 left/right │  │  │  w 12
  │  │  │  ┌──────────────────────────────────────────────┐  │  │  │  gap 4
  │  │  │  │      VDD core ring  M9 top/bottom, M8 l/r    │  │  │  │  w 12
  │  │  │  │  ┌────────────────────────────────────────┐  │  │  │  │  offset 2
  │  │  │  │  │ CORE  (205,205) … (1395,1795)          │  │  │  │  │
  │  │  │  │  │  1190 x 1590 µm                        │  │  │  │  │
  │  │  │  │  │                                        │  │  │  │  │
  │  │  │  │  │  │ │   │ │   │ │   │ │  <- M8 vertical │  │  │  │  │
  │  │  │  │  │  │ │   │ │   │ │   │ │     3.6 / 1.2 / │  │  │  │  │
  │  │  │  │  │ ═╪═╪═══╪═╪═══╪═╪═══╪═╪═  set-to-set 60│  │  │  │  │
  │  │  │  │  │ ═╪═╪═══╪═╪═══╪═╪═══╪═╪═                │  │  │  │  │
  │  │  │  │  │  │ │   │ │   │ │   │ │   <- M9 horiz.  │  │  │  │  │
  │  │  │  │  │ ═╪═╪═══╪═╪═══╪═╪═══╪═╪═  3.6 / 3.05 /  │  │  │  │  │
  │  │  │  │  │  │ │   │ │   │ │   │ │     s2s 60      │  │  │  │  │
  │  │  │  │  └────────────────────────────────────────┘  │  │  │  │
  │  │  │  └──────────────────────────────────────────────┘  │  │  │
  │  │  └────────────────────────────────────────────────────┘  │  │
  │  └──────────────────────────────────────────────────────────┘  │
  └────────────────────────────────────────────────────────────────┘

  ring band, per side:  offset 2 + VDD 12 + spacing 4 + VSS 12
                     =  core_edge+2 .. core_edge+30   (28 µm)
```

Ring-band arithmetic and its clearance to `PAD70NU` are owned by
[03-floorplan §2](../03-floorplan.md#2-why-the-margin-is-70-and-not-50-the-staggered-bond-ring);
do not re-derive them here.

*Inference, labelled:* the VDD-inner / VSS-outer ordering is taken from the `-nets {VDD VSS}` list
order. The Stylus TCR documents that ordering for `add_stripes` — "The first net in the name list
is created first and corresponds to the left or bottom stripe of the set" (Stylus TCR — `add_stripes`,
`TCRcom/add_stripes.html`) — but the `add_rings` page states no equivalent rule. The band *width* is
the same either way; only which ring is inner depends on it.

**Set counts are arithmetic, not measured.** At 60 µm pitch and a 39.5 µm start offset, a
1190 µm-wide core takes ≈20 M8 sets and a 1590 µm-tall core ≈26 M9 sets; the M5 set at 15 µm pitch
gives ≈105 sets over the domain. Confirm against `report_special_routes` or the DEF, not against
this paragraph.

### 1.3 Cross-section

Layer data below is read from the tech LEF named by `config.tcl:131`,
`/tsmc65pdk/65/CMOS/util/lef/PRTF_EDI_65nm_001_Cad_V24a/PRTF_EDI_N65_9M_6X1Z1U_RDL.24a.tlef`.

```
 layer  THICK   PITCH   dir   role in this power plan
 ─────────────────────────────────────────────────────────────────────────
 AP     1.450   6.500    V    bond pad / RDL. Via-stack CEILING only — no
                              ring or stripe is drawn on AP by this script.
   ── RV (cut, SPACING 3) ──  VIAGEN9AP: M9 2..12 -> AP 3..35, cuts 6 x 6
 M9     3.400   4.000    H    CORE RING top+bottom  w 12
                              STRIPES horizontal    w 3.6, gap 3.05, s2s 60
   ── VIA8 ──                 VIAGEN89: M8 0.4..12 -> M9 2..12, cuts 0.9 x 0.9
 M8     0.900   0.800    V    CORE RING left+right  w 12
                              STRIPES vertical      w 3.6, gap 1.20, s2s 60
   ── VIA7 (SPACING 0.340) ──
 M7     0.220   0.200    H    signal
 M6     0.220   0.200    V    signal
 M5     0.220   0.200    H    MACRO-FEED STRIPES    w 1, gap 0.5, s2s 15
 M4     0.220   0.200    V    signal / macro PG pins (rf_16k et al.)
 M3     0.220   0.200    H    signal / IO-pad PG plate (22.0 x 4.0)
 M2     0.220   0.200    V    signal / core-pad PG fingers
 M1     0.180   0.200    H    STD-CELL RAILS — FOLLOWPIN, 0.330 µm tall
                              on a 0.200 x 1.800 `core` site
```

The 0.330 µm rail height is not a guess: `MACRO DCAP4` in
`tcbn65lp_9lmT2.lef` has `PIN VSS … RECT 0.465 -0.165 0.800 0.165`, and the whole riser population
in [15-pg-opens-analysis §2.2](../15-pg-opens-analysis.md) is that number.

### 1.4 What connects to what

Per the Stylus UG, `route_special` produces distinct shape classes and `add_rings` / `add_stripes`
produce others (Stylus UG — Power Planning and Routing, `UGcom/Power_Planning_and_Routing.html`):

| Source | Mechanism | Shape class produced |
|---|---|---|
| core VDD/VSS pads (`PVDD1DGZ_G`, `PVSS1DGZ_G`) → core ring | `route_special -connect pad_pin`, L56 / L65 | IOWIRE |
| pad to pad along the row | `route_special -connect pad_ring`, L56 / L65 / L166 | PADRING |
| core ring | `add_rings -type core_rings`, L55 | CORERING |
| M8 / M9 / M5 stripes | `add_stripes`, L94 / L132 / L159 | STRIPE |
| 21 hard macros' PG pins → mesh | `route_special -connect block_pin`, L168 | BLOCKWIRE |
| std-cell rails → mesh | `route_special -connect core_pin`, L168 | FOLLOWPIN (in row), COREWIRE (outside) |
| every crossover | VIAGEN engine, invoked *by* those three commands | special vias |

**The IO supplies are outside all of this, and the LEF explains why.** In
`local_overrides/tphn65lpgv2od3_sl_9lm.lef`, `PVDD2DGZ_G` / `PVDD2POC_G` / `PVSS2DGZ_G` expose their
supply pin as a single 22.0 × 4.0 µm plate on M3–M7 inside a 25 µm-wide cell, and every
`PFILLER*_G` spacer is `CLASS PAD SPACER` with **no pins at all** — only a full-cell M1–M7 `OBS`.
So abutting pads leave a 3 µm gap in the pin geometry, and the LEF gives Innovus **no model of
pad-ring continuity for VDDIO/VSSIO at all**. The real bus lives inside the pad cells in GDS and
appears in the abstract only as obstruction.

Consequence, and it is visible in the reports: the two `IMPVFC-98` "no routing" records that
[15-pg-opens-analysis §7 H5](../15-pg-opens-analysis.md) counts alongside the 200 signal nets are
**VDDIO and VSSIO**. Innovus is correct that it routed nothing; whether the ring is electrically
continuous is an **LVS** question, not an Innovus one. See §8.

---

## 2. Metal stack context — `9M_6X1Z1U`

The string is a TSMC stack code: **9 metal layers**, then the thickness classes of the layers above
M1. Decoding it against the measured `THICKNESS` values in the tech LEF:

| Code | Layers | `THICKNESS` | Class |
|---|---|---|---|
| (M1) | M1 | 0.180 | bottom metal, always present, not counted in the code |
| `6X` | M2 … M7 | 0.220 each | six **1×** (thin) layers |
| `1Z` | M8 | 0.900 | one **Z**-class thick layer, ≈4× a 1× layer |
| `1U` | M9 | 3.400 | one **U**-class *ultra-thick* layer, ≈15× a 1× layer |
| `_RDL` | AP | 1.450 | aluminium pad / redistribution, above M9 through cut layer `RV` |

*Labelled inference:* the LEF does not spell out what the letters mean. The mapping above is the
conventional TSMC reading (X = 1×, Z = thick, U = ultra-thick) **checked against** the thicknesses,
and the counts match exactly — six 0.220 layers, one 0.900, one 3.400.

The tech LEF's own rule-family comments partition the stack the same three ways, independently of
the thicknesses:

```
LAYER M1        #  M1.W.1            <- its own family
LAYER M2..M7    #  Mx.W.1            <- the six "X" layers
LAYER M8, M9    #  Mz/Mr/Mu.W.1      <- the thick family: z / r / u
```

Three groups, sized 1 / 6 / 2, and the thick family's own letters (`z`, `u`) are the letters in the
stack code.

**Why the top layers carry power.** Three independent reasons, all readable from the LEF:

1. **Sheet resistance.** M9 is 3.400 µm thick against M1's 0.180 — roughly 19× the cross-section per
   unit width, so ~19× less IR drop for the same geometry. M8 at 0.900 is ~5×. *This tech LEF
   contains no `RESISTANCE` statements*, so the actual Ω/□ cannot be quoted from it; the argument
   here is cross-sectional, not measured.
2. **Allowed width.** M8 and M9 both carry `MAXWIDTH 12`, which is precisely the 12 µm ring width
   used at L55. You cannot draw a 12 µm ring and stay legal on any of these layers *above* 12 —
   the rings are at the ceiling.
3. **Opportunity cost.** M8 `PITCH 0.800` and M9 `PITCH 4.000` against 0.200 for M1–M7. M9 offers a
   twentieth of the track density of a thin layer; spending it on signals would be wasteful, so
   dedicating M8/M9 to the power mesh costs almost no routing resource.

The corollary constraints, both of which this script is shaped by:

- M9 has **no `SPACINGTABLE`** — flat `WIDTH 2 ; SPACING 2 ; AREA 9 ; MINENCLOSEDAREA 9`. That is
  what makes §3.7's `-spacing 3.05` mandatory.
- M8 and M9 both carry `MINIMUMCUT 2 WIDTH 1.800` (M9's is `FROMBELOW`), so at the 3.6 µm stripe
  width every stripe-to-stripe via must be at least a 2-cut array. `VIAGEN89` cuts are
  0.900 × 0.900 and `VIAGEN9AP` cuts are 6 × 6 — very coarse, which is why the via-generation
  attributes in §3.5 are not cosmetic.

---

## 3. The script, in order

### 3.1 Lines 8–42 — the `PD_TOP` guard

```tcl
40	if {[llength [get_db power_domains PD_TOP]] == 0} {
41	    error "power_plan: no PD_TOP power domain — check read_power_intent"
42	}
```

Lines 8–39 are the comment block explaining why. The mechanism is §5; the history, the CPF patch and
the shipped-unfilled-die incident are [04-power-plan §1](../04-power-plan.md#1-the-big-trap-pd_top-has-no-supply-nets-and-the-die-ships-unfilled).

What the guard checks is only that the *domain object exists* — not that it carries supply nets.
A stronger guard would test the nets themselves, since that is the actual failure mode. Noted in §8.

### 3.2 Lines 44–49 — `connect_global_net`

```tcl
44	### Connecting Global Nets
45	# -pin_base_name is the PIN name, not the NET name (VDDPST/VSSPST on the pads).
46	connect_global_net VDD -type pg_pin -pin_base_name VDD -inst_base_name *
47	connect_global_net VDDIO -type pg_pin -pin_base_name VDDPST -inst_base_name * 
48	connect_global_net VSS -type pg_pin -pin_base_name VSS -inst_base_name * 
49	connect_global_net VSSIO -type pg_pin -pin_base_name VSSPST -inst_base_name * 
```

Stylus TCR — `connect_global_net` (`TCRcom/connect_global_net.html`). This is the *stylus* command;
the legacy-UI equivalent is `globalNetConnect`, and the two are not interchangeable.

| Token | Manual | Meaning here |
|---|---|---|
| `VDD` (positional) | "The name of the global net to which the specified pins, modules, or nets connect." | the net; must already exist, i.e. must be in `init_power_nets`/`init_ground_nets` before `init_design` |
| `-type pg_pin` | "Specifies that the power and ground pins listed with the `-pin_base_name` parameter are to be connected." | matches only pins the database classifies as power/ground — **this is the whole of §4** |
| `-pin_base_name VDDPST` | "Specifies the pins to connect to the global net. You can use the wildcard (`*`)…" | the **pin** name on the cell master. On core cells pin and net are both `VDD`, which is why the distinction is invisible until it bites |
| `-inst_base_name *` | "Specifies the names of leaf instances for which pins are to be connected… An instance basename cannot contain the `/` character." | every leaf instance in the design. `-all` would be the more idiomatic stylus form; `-inst_base_name *` is equivalent in effect and is what the file uses |

Options deliberately **not** used, and worth knowing about:

- **`-verbose`** — "Specifies that connection statistics and warning messages are displayed in the
  console." Given §4's history, adding `-verbose` to these four lines is the cheapest possible
  regression detector for a silently-empty PG net.
- **`-auto_tie`** — would also tie tie-hi/tie-lo pins whose related power pin is this net. Not wanted
  here; `add_tieoffs` is handled elsewhere.
- **`-override` / `-netlist_override`** — not needed; nothing sets these connections earlier.

### 3.3 Lines 50–55 — stacked-via limits and `add_rings`

```tcl
50	### Top and Bottom Metal Declartions
51	set_db add_rings_stacked_via_top_layer M9
52	set_db add_rings_stacked_via_bottom_layer M1 
```

Stylus TCR — `add_rings` Category Attributes (`TCRcom/add_rings_Category_Attributes.html`):
`add_rings_stacked_via_top_layer` — "Specifies the highest layer in which vias can be stacked",
default "The highest metal layer in the design." `…_bottom_layer` is the mirror, default "The lowest
metal layer in the design."

The bottom setting (M1) restates the default. The **top setting does not**: the highest routing
layer in this design is `AP`, so `M9` deliberately stops ring vias one layer below the pad metal.
That is correct — nothing in the ring needs to reach AP, and the `VIAGEN9AP` rule has 6 × 6 µm cuts
with `SPACING 6 BY 6`, so an unnecessary M9→AP stack under a 12 µm ring would be a large,
pointless, and pad-blocking structure. Contrast §3.5, where the *stripe* stacked-via ceiling **is**
set to AP.

```tcl
55	add_rings -nets {VDD VSS} -type core_rings -follow core -layer {top M9 bottom M9 left M8 right M8} -width {top 12 bottom 12 left 12 right 12} -spacing {top 4 bottom 4 left 4 right 4} -offset {top 2 bottom 2 left 2 right 2} -center 0 -threshold 0 -jog_distance 0 -snap_wire_center_to_grid none
```

Stylus TCR — `add_rings` (`TCRcom/add_rings.html`): "Creates rings for specified nets around the
core boundary or selected blocks and groups of core rows. Use this command after creating an initial
floorplan."

| Option | Manual | Value here, and why |
|---|---|---|
| `-nets {VDD VSS}` | "the names of the nets for which power rings are to be created" (**required**) | the two core supplies. `VDDIO`/`VSSIO` are absent — §1.4 |
| `-type core_rings` | "Creates core rings that follow the contour of the core boundary or the I/O boundary. If you specify `core_rings`, then you must specify either the `-follow` parameter or the `-around user_defined` parameter." | one ring set around the whole core, not per-block |
| `-follow core` | "Specifies whether core rings are placed along the core boundary or the I/O boundary." Default `core`. | follow the **core** box, so the ring position tracks `CORE_TO_IO`. Restates the default, but stating it is required by `-type core_rings` |
| `-layer {top M9 bottom M9 left M8 right M8}` | per-side layer assignment (**required**) | matches LEF preferred directions: M9 is `DIRECTION HORIZONTAL` so it takes top/bottom; M8 is `DIRECTION VERTICAL` so it takes left/right. Getting this backwards produces legal-but-awful non-preferred-direction metal |
| `-width {… 12 …}` | ring metal width (**required**) | **exactly `MAXWIDTH`** on both M8 and M9. This is a ceiling, not a choice — see §2 |
| `-spacing {… 4 …}` | edge-to-edge gap between the two rings | 4 µm. Legal on both: M8's `SPACINGTABLE` tops out at 1.5, M9's flat `SPACING` is 2 |
| `-offset {… 2 …}` | distance from the reference boundary | 2 µm outside the core box. With `-center 0` this is the sole positional control |
| `-center 0` | "whether to center the core rings between the I/O pads and core boundaries. If you do not specify this parameter with a value of 1, you must specify the parameter `-offset`" | offsets are explicit, so centring is off. The two options are a documented either/or |
| `-threshold 0` | "the least amount of spacing allowed between ring segments of adjacent blocks before the rings are merged"; default 10 µm | 0 disables merging with anything nearby. There are no block rings here, so this is defensive |
| `-jog_distance 0` | "the least amount of jog allowed (to follow the contour of the referenced object) before a jog is removed"; default is auto-computed from worst tech spacing | 0 means no jog is ever suppressed. The core box is a rectangle, so no jogs arise |
| `-snap_wire_center_to_grid none` | "Does no snapping of the wires." Default is also no snapping. | explicit no-snap. Relevant because M9's `PITCH` is 4.0 with `OFFSET 0` — snapping a 12 µm ring to that grid would move it, and the ring position is load-bearing against `PAD70NU` |

### 3.4 Lines 56–72 — `route_special`, pads to ring

```tcl
56	route_special -connect {pad_pin pad_ring} \
57	            -layer_change_range { M1(1) AP(10) } \
58	            -block_pin_target nearest_target \
59	            -pad_pin_port_connect {all_port all_geom} \
60	            -pad_pin_target nearest_target -allow_jogging 1 \
61	            -crossover_via_layer_range { M1(1) AP(10) } \
62	            -nets { VDD } -allow_layer_change 1 \
63	            -pad_pin_width 1.63 -target_via_layer_range { M1(1) AP(10) }
```

…and the identical block at L65–72 for `VSS` with `-pad_pin_width 1.5`.

Stylus TCR — `route_special` (`TCRcom/route_special.html`): "Routes power structures. Use this
command after creating power rings and power stripes." (Legacy-UI name: `sroute`.)

| Option | Manual | Value here, and why |
|---|---|---|
| `-connect {pad_pin pad_ring}` | "Connects the specified objects to rings and stripes." | two jobs: bring each supply pad's core-side pin in to the ring (`pad_pin`, → IOWIRE), and stitch pad to pad along the row (`pad_ring`, → PADRING) |
| `-nets { VDD }` | "the names of the nets to connect… Default: … all power and ground nets in the design" | one net per pass, because `-pad_pin_width` differs per net — see below |
| `-pad_pin_width 1.63` / `1.5` | "**Routes only pad pins that have the specified width.** If no width is specified, the software automatically calculates the width… It is usually not necessary to specify a pin width." | **these are the real LEF numbers.** `PVDD1DGZ_G` `PIN VDD` presents ten M1/M2 fingers of `1.630 × 1.840` µm; `PVSS1DGZ_G` `PIN VSS` presents seven of `1.500 × 1.560` µm. That is the *only* reason the two passes are split |
| `-pad_pin_target nearest_target` | "Extends the pad pin to the nearest legal target." Default is already `nearest_target`. | the nearest legal target is the core ring 2 µm off the core edge |
| `-pad_pin_port_connect {all_port all_geom}` | `all_port`: "Routes to all ports." `all_geom`: "Routes to only one port of a pad pin if multiple ports are defined in the LEF file." | the two supply pads have three ports each (M1 fingers, M2 fingers, M3–M7 plate). The manual's wording for these two enums is internally inconsistent — see §8 |
| `-allow_layer_change 1` | "Allows connections to targets on different layers." | mandatory: the pad pin is M1/M2, the ring is M8/M9 |
| `-allow_jogging 1` | "jogs are allowed during routing to avoid DRC violations… You can use `-allow_jogging 1` and `-connect pad_ring` together to enable jog connection in pad ring connection." | explicitly the documented pairing with `-connect pad_ring` |
| `-layer_change_range { M1(1) AP(10) }` | "Allows routing between the specified bottom-most and top-most layer, inclusive." | the full stack. The `name(number)` spelling is the legacy GUI's; `AP` is layer **10**, confirming AP is a routing layer above M9. Note the TCR's argument-order text for *this one option* is `{ topLayerName bottomLayerName }` while every sibling range option is `{ bot top }` — §8 |
| `-crossover_via_layer_range { M1(1) AP(10) }` | "the highest and lowest layer that can be used for via stacking at the crossover point between power structures. Note: This parameter does not apply to T-pattern connections." | full stack |
| `-target_via_layer_range { M1(1) AP(10) }` | "the highest and lowest layer that can be used for via stacking at a target" | full stack |
| `-block_pin_target nearest_target` | extension target for block pins | **inert in this pass** — `-connect` does not include `block_pin`. Harmless carry-over from the GUI form |

### 3.5 Lines 74–93 / 99–117 — the `add_stripes` attribute preamble

The same 19 `set_db add_stripes_*` lines appear twice, verbatim, at L75–93 and L99–117. All are
Stylus TCR — `add_stripes` Category Attributes (`TCRcom/add_stripes_Category_Attributes.html`).

**Only four of the nineteen differ from the documented default.** The other fifteen are what the
Innovus "Add Stripes" GUI form writes out, defaults included. Sorting them is the fastest way to
read this block:

| Line | Attribute / value | Default | Effect |
|---|---|---|---|
| 76 | `break_at none` | `none` | — |
| 77 | `route_over_rows_only false` | `false` | — |
| 78 | `rows_without_stripes_only false` | `false` | — |
| 79 | `extend_to_closest_target none` | `none` | — |
| 80 | `stop_at_last_wire_for_area false` | `false` | — and doc says it "is only available if you specify the `-area` attribute", which is never used |
| 82 | `trim_antenna_back_to_shape none` | `none` | — |
| 83 | `spacing_type edge_to_edge` | `edge_to_edge` | — |
| 84 | `spacing_from_block 0` | `0` | — |
| 85 | `stripe_min_length stripe_width` | `stripe_width` | — |
| 86 | `stacked_via_top_layer AP` | highest layer in design = `AP` | — in effect |
| 87 | `stacked_via_bottom_layer M1` | lowest layer in design = `M1` | — in effect |
| 90 | `orthogonal_only true` | doc: value `1` is the default | — |
| 91 | `allow_jog {padcore_ring block_ring}` | `padcore_ring block_ring` | — |
| 92 | `skip_via_on_pin {standardcell}` | `Standardcell` | — |
| 93 | `skip_via_on_wire_shape {noshape}` | "vias can be generated on all wire shapes **except** no-shape wires" | — |
| **75** | **`ignore_block_check true`** | `false` | see below |
| **81** | **`ignore_non_default_domains true`** | `false` | "Creates global stripes over domains without breaking." Correct for a single-domain design and forward-compatible if a second domain is added |
| **88** | **`via_using_exact_crossover_size false`** | `true` | "A value of 1 allows partial vias to be generated. A value of 0 prevents partial vias, and the software always generates full-size vias." |
| **89** | **`split_vias false`** | `true` | "Specifies whether two or more partial vias can be created at the crossover… A value of 0 prevents multiple partial vias from being created." |

Three observations that are not in [04-power-plan](../04-power-plan.md):

- **`ignore_block_check true` is inert as written.** The manual's own note: "This attribute only
  works in conjunction with the `-break_at` attributes of the `add_stripes` command" — and L76 sets
  `break_at none`. Worse, the documented behaviour is the *opposite way round* from the name: "If
  set to `false`, when a stripe encounters a ring, the software does not check whether that ring is
  surrounding a block. If set to `true`, … the software automatically checks whether a block is
  enclosed within the ring." [04-power-plan §4](../04-power-plan.md#4-stripes) describes `true` as
  "block-check off"; per this manual page it is block-check **on**. Neither reading changes the
  outcome while `break_at` is `none`. Flagged in §8.
- **Lines 88 + 89 together forbid partial vias entirely.** Every stripe crossover must take a
  full-size via array or none. On a stack where `VIAGEN89` cuts are 0.900 × 0.900 and both M8 and
  M9 demand `MINIMUMCUT 2` at these widths, that is a real constraint, not a formality — it trades
  via count for via quality.
- **These two attributes change what `check_power_vias` measures.** Stylus TCR —
  `check_power_vias` (`TCRcom/check_power_vias.html`), under `-cut_area_ratio`: "By default, the
  metal intersection area is the metal overlap area. If `setAddStripeMode -via_using_exact_crossover_size`
  is set to `false`, the partial overlapped metal will be extended to full width intersection area."
  So a `-cut_area_ratio` check on this design is scored against the *full* crossover, which is the
  stricter reading. Relevant to §6.

The block is duplicated because L94 and L132 are independent `add_stripes` calls and the attributes
are sticky root attributes; re-asserting them is defensive rather than necessary, since nothing
between L94 and L99 changes any of them. Harmless.

### 3.6 Line 94 — M8 vertical stripes

```tcl
94	add_stripes -nets {VDD VSS} -layer M8 -direction vertical -width 3.6 -spacing 1.2 -set_to_set_distance 60 -extend_to all_domains -start_from left -start_offset 39.5 -stop_offset 0 -switch_layer_over_obs false -max_same_layer_jog_length 2 -pad_core_ring_top_layer_limit AP -pad_core_ring_bottom_layer_limit M1 -block_ring_top_layer_limit AP -block_ring_bottom_layer_limit M1 -use_wire_group 0 -snap_wire_center_to_grid none
```

Stylus TCR — `add_stripes` (`TCRcom/add_stripes.html`): "Creates power stripes within the specified
area. If the router encounters an obstruction, the stripe connects to the last stripe on the same
net. Otherwise, the stripes stop at the core row boundary."

| Option | Manual | Value here, and why |
|---|---|---|
| `-nets {VDD VSS}` | "The number of net names determines the number of stripes within each set… The first net… corresponds to the left or bottom stripe of the set." (**required**) | two stripes per set; VDD is the left one |
| `-layer M8` | "Stripes can be created on only one layer at a time." | one call per layer, hence three calls in this file |
| `-direction vertical` | "Sets the stripe direction." Default `vertical`. | matches M8's LEF `DIRECTION VERTICAL` |
| `-width 3.6` | stripe width (**required**) | 9× M8's minimum `WIDTH 0.400`, well under `MAXWIDTH 12` |
| `-spacing 1.2` | "the **edge-to-edge** spacing between stripes in each set" | legal here. M8's `SPACINGTABLE` at `WIDTH 1.500` requires at most 0.5 µm. Do not "fix" this to match M9 |
| `-set_to_set_distance 60` | "the distance (pitch) from the reference stripe of one set to the reference stripe of the next set" | 60 µm pitch. Mutually exclusive alternative is `-number_of_sets` |
| `-extend_to all_domains` | "Stripes are created over all power domains for each power and ground net within each power domain. Stripes start and stop at each power domain boundary or ring around the power domain, **and ignore the values in the `-nets` parameter**." | the stripes follow **the domain's own** PG nets, not the `-nets` list. That is a second, less obvious dependency on `PD_TOP` carrying VDD/VSS — see §5 |
| `-start_from left` | for vertical stripes, "`left` indicates that stripes should be generated from left to right, taking the left offset into account" | correct for a vertical set |
| `-start_offset 39.5` | "Specifies the starting offset value." Mutually exclusive with `-start`. | 39.5 µm in from the left reference edge. Note the manual: the *opposite* side's offset is "soft" — "could be greater than the hard values, but will never be less" |
| `-stop_offset 0` | "the exact stop coordinates that contain the set of stripes" | run to the far edge |
| `-switch_layer_over_obs false` | "Controls whether a stripe switches layers, is routed over blocks, and then continues on the original layer. Using this parameter eliminates the need for a power routing mesh layer, and avoids maximum via stack rule violations." Default 0. | off. M8 stripes stay on M8 and stop at obstructions |
| `-max_same_layer_jog_length 2` | "The maximum length, in micrometers, that a stripe can jog on the same layer before switching to an adjacent layer." Default 2. | restates the default |
| `-pad_core_ring_top_layer_limit AP` / `-pad_core_ring_bottom_layer_limit M1` | "the highest / lowest layer that stripes can switch to when encountering a pad or core ring" | unrestricted — the stripe may take any layer to reach the ring |
| `-block_ring_top_layer_limit AP` / `-block_ring_bottom_layer_limit M1` | same, for block rings | unrestricted. No block rings exist in this design, so inert |
| `-use_wire_group 0` | "If set to 1, connects multiple wires from the same net together. **Note:** For stripes to connect to rings using wire groups, you must specify `-use_wire_group` in both the `add_rings` and `add_stripes` commands." | off in both places — consistent |
| `-snap_wire_center_to_grid none` | no snapping | consistent with the ring |

L96 `deselect_obj -all` clears the selection so nothing from the floorplan stage leaks into the next
command's implicit `-selected` semantics.

### 3.7 Lines 118–132 — M9 horizontal stripes

Lines 118–131 are a 14-line comment recording an `IMPPP-136` / `IMPPP-193` defect and its fix; the
full account with log line numbers and the surviving-artefact caveats is
[04-power-plan §4.2](../04-power-plan.md#42-m9-horizontal-spacing-305-not-12). Do not duplicate it.

```tcl
132	add_stripes -nets {VDD VSS} -layer M9 -direction horizontal -width 3.6 -spacing 3.05 -set_to_set_distance 60 -extend_to all_domains -start_from left -start_offset 39.5 -stop_offset 0 -switch_layer_over_obs false -max_same_layer_jog_length 2 -pad_core_ring_top_layer_limit AP -pad_core_ring_bottom_layer_limit M1 -block_ring_top_layer_limit AP -block_ring_bottom_layer_limit M1 -use_wire_group 0 -snap_wire_center_to_grid none
```

Identical to L94 except `-layer M9`, `-direction horizontal`, `-spacing 3.05`.

**`-spacing 3.05`, in one line:** M9 has no `SPACINGTABLE`, only flat `SPACING 2 ;` and
`MINENCLOSEDAREA 9 ;`. A 1.2 µm gap between two 3.6 µm stripes violates both, and 3.05 ≈ √9 clears
the enclosed-area rule as well as the spacing rule. At a 60 µm pitch the extra 1.85 µm is absorbed
without dropping a set.

**`-start_from left` on a horizontal set is not a documented combination.** The Stylus TCR is
explicit: "For horizontal stripes: `bottom` indicates that stripes should be generated from bottom
to top… `top` indicates… **Default: `bottom`**. For vertical stripes: `left`… `right`…
**Default: `left`**." The Stylus UG's own worked examples follow the same split —
`-direction horizontal … -start_from bottom` and `-start_from left` for the vertical layer
(`UGcom/Power_Planning_and_Routing.html`). Passing `left` with `-direction horizontal` is
out-of-domain; the tool almost certainly falls back to `bottom`, in which case `-start_offset 39.5`
measures **from the bottom of the core**, not from the left. That is very likely what was intended,
so the geometry is probably right by accident. It is untested and it is a copy-paste artefact from
L94. See §8.

### 3.8 Lines 136–159 — macros, `split_row`, M5 stripes

```tcl
144	if {![info exists ::PLACED_MACROS] || [llength $::PLACED_MACROS] == 0} {
145	    error "power_plan: ::PLACED_MACROS is empty — floorplan.tcl must run first"
146	}
147	if {[llength $::PLACED_MACROS] != 21} {
148	    puts stderr "WARNING: power_plan: expected 21 macros, got [llength $::PLACED_MACROS]"
149	}
150	select_obj $::PLACED_MACROS
151	
152	split_row -selected
```

The `IMPTCM-165` stale-macro-name history is
[04-power-plan §5](../04-power-plan.md#5-macro-connection-consuming-the-resolved-macro-list).

Stylus TCR — `split_row` (`TCRcom/split_row.html`): "Cuts site rows within an area or that intersect
with the selected object(s). Use this command after rows have been created. **Note:** The default
behavior is to cut rows that intersect with placement blockages and macros."

- `-selected` — "Specifies that the rows that intersect with the selected object(s) will be cut.
  **Note:** Only supports inst, hinst, power domain, group, place blockage, route_blockage, and bump
  as selected object(s)." The 21 entries are leaf instances, which qualify.
- **No `-halo` and no `-*_gap`** — "Specifies additional space to be provided on the top, bottom,
  left, and right sides of the objects causing rows to be cut." Omitting them cuts the rows **exactly
  at the macro bounding box**. That is precisely the geometry that
  [15-pg-opens-analysis §7 H1](../15-pg-opens-analysis.md) identifies as the origin of the
  ±0.300 µm risers: the row ends flush with the macro, and `route_special -core_pin_target
  first_after_row_end` then builds a 0.330 µm riser on the first clear track. If H1 is confirmed,
  **this line is where the fix goes.**
- **No `-keep_cell`** — "Default: All cells inside the cut rows will be unplaced." Nothing is placed
  yet (`place_design` runs nine lines later in `2_pnr_setup.tcl`), so this is a no-op today. It stops
  being a no-op the moment anyone re-runs this file on a placed database.

```tcl
154	set_db add_stripes_ignore_block_check false
158	set_db add_stripes_extend_to_closest_target {ring stripe}
159	add_stripes -nets {VDD VSS} -layer M5 -direction horizontal -width 1 -spacing 0.5 -set_to_set_distance 15 -over_power_domain 1 -start_from bottom -start_offset 8 -stop_offset 0 -switch_layer_over_obs false -merge_stripes_value 500 -max_same_layer_jog_length 2 -pad_core_ring_top_layer_limit AP -pad_core_ring_bottom_layer_limit M1 -block_ring_top_layer_limit AP -block_ring_bottom_layer_limit M1 -use_wire_group 0 -snap_wire_center_to_grid none
```

The four deliberate reversals from the global sets:

| Change | Manual | Why |
|---|---|---|
| `ignore_block_check false` (L154) | see §3.5 | reverts the global setting. Still inert — `break_at` is still `none` (L155) |
| `extend_to_closest_target {ring stripe}` (L158) | "Extends the stripe to the specified target." Default `none`. | these stripes must *reach* the ring or the M8/M9 mesh, not stop at the domain boundary. This is the setting that makes them useful |
| `-over_power_domain 1` | "adds stripes **only within power domain boundaries** or the fence around a soft block… **the software issues a warning message if the specified power and ground nets do not match the power domain's power or ground nets.**" | confines the macro feed to `PD_TOP`. The warning clause is a third `PD_TOP`-supply-net dependency — see §5 |
| `-merge_stripes_value 500` | "Merges a stripe with a nearby block ring if the threshold spacing between the stripe and ring is smaller than the value… set to −1 to prevent merging." Default 10. | 500 µm is effectively "always merge". Aggressive, but there are no block rings in this design, so it has nothing to act on. If block rings are ever added, revisit this number first |
| `-start_from bottom` | correct for horizontal | contrast §3.7 |

Geometry: `-width 1 -spacing 0.5 -set_to_set_distance 15` on M5, whose `WIDTH` minimum is 0.100 and
whose `SPACINGTABLE` requires 0.120 at width 1.0 — comfortably legal. Horizontal on a horizontal
layer, matching M5's LEF `DIRECTION HORIZONTAL`.

> [15-pg-opens-analysis §6](../15-pg-opens-analysis.md) records that **0 of 560 risers align with
> the M5 stripe band** and 100 % align with the 1.8 µm row-rail grid, so this M5 set is *not* the
> source of the opens — but §4 of that page does record a separate +48 % VIA4-deletion regression
> attributable to it.

### 3.9 Lines 163–164 — `add_endcaps`

```tcl
163	# Add END CAPS
164	add_endcaps -start_row_cap DCAP4 -end_row_cap DCAP4 -prefix ENDCAP
```

Stylus TCR — `add_endcaps` (`TCRcom/add_endcaps.html`): "Places physical-only end cap cells at the
ends of the site rows. A single-height cap cell is required at the end of each row… Use
`add_endcaps` Category Attributes to specify the row-cap cells."

**`-start_row_cap` and `-end_row_cap` are not documented options of this command in either UI.** The
Stylus `add_endcaps` synopsis is `[-help] [-area …] [-core_boundary_only] [-power_domain …]
[-prefix …]` — five options, none of them a cell name. The legacy-UI page is the same five
(`innovusTCR/addEndCap.html`), with cells coming from `setEndCapMode -leftEdge/-rightEdge`
(`innovusTCR/setEndCapMode.html`). In stylus the equivalent is the attribute set —
`add_endcaps_left_edge` / `add_endcaps_right_edge` / `add_endcaps_cells`
(`TCRcom/add_endcaps_Category_Attributes.html`, where `add_endcaps_left_edge` is documented as
"Specifies the one cell that has n-well cap on its left edge when in r0 orientation… This would be
same as a post-cap, in a two well process"). A `grep` for `start_row_cap` across `TCRcom/`,
`innovusTCR/` and `UGcom/` returns nothing.

`-prefix ENDCAP` **is** documented and also happens to be the default ("Prefix Default: `ENDCAP`").

Two further notes on this line:

- **`DCAP4` is `CLASS CORE`, not `CLASS ENDCAP`.** In `tcbn65lp_9lmT2.lef`, `MACRO DCAP4` is
  `CLASS CORE ; SIZE 0.800 BY 1.800 ; SITE core` — a decoupling-capacitor filler. The `add_endcaps`
  page describes deriving caps from `MACRO CLASS ENDCAP …`; `tcbn65lp` has no such class, so using a
  decap as a row cap is a reasonable substitution, but it is a substitution.
- **Ordering.** The manual: "`add_endcaps` is always called after floorplan is done and before
  `add_well_taps`." Here it runs after the stripes and before the final `route_special`, which
  satisfies the first half. `add_well_taps` is **never called anywhere in this flow**.

Whether the command inserted anything at all is testable in one line and has never been tested —
`check_endcaps` exists in this version (`TCRcom/check_endcaps.html`). See §6 and §8, and note
[15-pg-opens-analysis §7 H3](../15-pg-opens-analysis.md), which treats DCAP4 endcaps as a
(weak, cheap-to-falsify) hypothesis for the PG opens.

### 3.10 Lines 166–168 — the closing `route_special` passes

```tcl
166	route_special -connect {pad_pin pad_ring} -layer_change_range { M1(1) AP(10) } -block_pin_target nearest_target -pad_pin_port_connect {all_port all_geom} -pad_pin_target nearest_target -allow_jogging 1 -crossover_via_layer_range { M1(1) AP(10) } -nets { VDD VSS } -allow_layer_change 1 -pad_pin_width 6 -target_via_layer_range { M1(1) AP(10) }
167	set_db route_special_via_connect_to_shape { padring stripe }
168	route_special -connect {block_pin core_pin floating_stripe} -layer_change_range { M1(1) AP(10) } -block_pin_target nearest_target -pad_pin_port_connect {all_port one_geom} -pad_pin_target nearest_target -core_pin_target first_after_row_end -floating_stripe_target {block_ring pad_ring ring stripe ring_pin block_pin followpin} -allow_jogging 1 -power_domains { PD_TOP } -crossover_via_layer_range { M1(1) AP(10) } -nets { VDD VSS } -allow_layer_change 1 -block_pin use_lef -target_via_layer_range { M1(1) AP(10) }
```

**L166 — second pad pass, both nets, `-pad_pin_width 6`.** Everything is as §3.4 except the width.
Per the manual, `-pad_pin_width` "Routes only pad pins that have the specified width." **No PG pad
pin in the IO LEF is 6 µm on any dimension.** Enumerating every `PIN VDD|VSS|VDDPST|VSSPST` `RECT`
in `local_overrides/tphn65lpgv2od3_sl_9lm.lef` gives exactly these dimensions:

```
1.500  1.560  1.630  1.840  2.505  3.000  3.700  3.725  3.750  4.000  4.500  22.000  53.000
```

So the `pad_pin` half of this pass most likely selects nothing, and only the `pad_ring` half does
work. The manual's own advice is "It is usually not necessary to specify a pin width." Flagged in
§8; this is the single most suspicious literal in the file.

**L167 — `set_db route_special_via_connect_to_shape { padring stripe }`.** Stylus TCR —
`route_special` Category Attributes (`TCRcom/route_special_Category_Attributes.html`):
"Specifies which shapes vias can connect to." Default is the full list —
`padring ring stripe blockring blockpin coverpin noshape blockwire corewire followpin iowire`.
Narrowing it to `{padring stripe}` for L168 means the block-pin and follow-pin connections may only
drop vias onto **pad-ring** and **stripe** shapes — *not* onto `ring`, `blockring`, `corewire` or
`followpin`. That is a real restriction and it is the only line in the file that touches the
`route_special` attribute category.

**L168 — the pass that ties the design together.**

| Option | Manual | Value here, and why |
|---|---|---|
| `-connect {block_pin core_pin floating_stripe}` | connect these object classes to rings and stripes | macro PG pins → BLOCKWIRE; std-cell rails → FOLLOWPIN/COREWIRE; any stripe left dangling → connected |
| `-block_pin use_lef` | "Pins are connected exactly as specified in the LEF file. For example, if the LEF file has multiple ports with one geometry connecting to each port, then one pin per port is connected." | correct for hard macros with characterised PG geometry (`rf_*`, ROMs, flash caches) |
| `-block_pin_target nearest_target` | "Extends the block pin to the nearest legal target. The block pin will be **open** if no specified target is found." | note the failure mode is a silent open, not an error |
| `-core_pin_target first_after_row_end` | "Extends the standard cell pin to the first ring or stripe outside of the row." Default is already `first_after_row_end`. | **this is the mechanism under scrutiny.** [15-pg-opens-analysis H2](../15-pg-opens-analysis.md) proposes swapping it for `stripe` as a diagnostic. Note the manual's other option, `none`: "Unconnected standard cell pins are not extended, and connections may be left open" |
| `-floating_stripe_target {block_ring pad_ring ring stripe ring_pin block_pin followpin}` | "Specifies the target shape for floating stripes." | this is verbatim the documented **default**; the explicit spelling adds nothing |
| `-power_domains { PD_TOP }` | "Restricts `route_special` activity to the specified power domains. Default: All power domains" | one domain, so equivalent to the default — but it makes a broken `PD_TOP` fatal to this pass rather than merely to filler |
| `-pad_pin_port_connect {all_port one_geom}` | `one_geom`: "Routes to one geometry per port only." | changed from `all_geom` in the pad passes. `-connect` here has no `pad_pin`, so this is inert |
| `-nets { VDD VSS }` | — | again, no `VDDIO`/`VSSIO` |
| the three `*_via_layer_range` / `-layer_change_range` options | as §3.4 | full stack |

**Ordering note, not covered elsewhere.** All three `route_special` calls run in `2_pnr_setup.tcl`
at line 47, and `place_design` runs at line 56. The whole power plan — including follow-pin
creation — is therefore built on an **unplaced** design, and `route_special` is never re-run after
placement or after routing. That is a legitimate flow (the TCR's `-core_pin_width` text explicitly
contemplates running before placement: "If `route_special -core_pin_width` is run prior to
placement, then the standard cell rails are created with the specified width"), but it means no PG
repair pass ever sees the placed cells, the CTS buffers, or the routed signals.

---

## 4. The `connect_global_net` PG-pin problem

This is the highest-value section of the page. The full remediation story with DRC counts is
[04-power-plan §2.1](../04-power-plan.md#21-the-lef-override-that-makes-this-work-at-all); what
follows is the *mechanism*, at command level, with the message IDs looked up.

### 4.1 The defect

`config.tcl:135-160` records it. The TSMC IO supply pads declare their supply pin as an ordinary
signal pin:

```lef
PIN VDDPST / DIRECTION INOUT ;      (PVDD2DGZ_G, PVDD2POC_G)
PIN VSSPST / DIRECTION INOUT ;      (PVSS2DGZ_G)
```

— with **no `USE POWER ;` / `USE GROUND ;`**, and the liberty agrees (they are `pin()` groups, not
`pg_pin()`). Line 47 and line 49 of `power_plan.tcl` ask for `-type pg_pin`. Per the Stylus TCR,
`-type pg_pin` "Specifies that the power and ground pins listed with the `-pin_base_name` parameter
are to be connected" — the classification comes from the library, not from the option. A pin with no
`USE POWER`/`USE GROUND` is not a PG pin, so the rule matches nothing and raises **IMPDB-1221**.

`config.tcl` also records the crucial negative result: fixing `-pin_base_name` alone is **not
sufficient**. Verified by running it against the real database — the pin still is not classified as
power, so the LEF is the only place the fix can live.

### 4.2 Looking the message IDs up

**IMPDB-1221 — no page exists in the installed help set.** `innovuserrmsg/` (Product Version 21.10,
May 2021) ships four pages from this band: `IMPDB-1206`, `IMPDB-1216`, `IMPDB-1220`, `IMPDB-1284`.
A recursive grep for the literal string `IMPDB-1221` across `innovuserrmsg/`, `TCRcom/`,
`innovusTCR/` and `UGcom/` returns nothing. **Do not quote a summary line for IMPDB-1221 — there
isn't one to quote.** Use `man IMPDB-1221` inside a live Innovus session to get the tool's own text.

What *is* documented is the band, and it is unambiguous — both surviving neighbours are
global-net-connection rule errors:

> **IMPDB-1216** (`innovuserrmsg/IMPDB-1216.html`) — "The global net '%s' specified in the global net
> connection(GNC) rule doesn't exist in the design." Its `DESCRIPTION` gives the stylus fix
> literally: `set_db init_power_nets {VDD}` / `set_db init_ground_nets {VSS}` / `init_design` /
> `connect_global_net VDD -type pg_pin -pin_base_name VDD`.

> **IMPDB-1220** (`innovuserrmsg/IMPDB-1220.html`) — "Unable to establish connection because the %s
> pin and the %s net are not of the same polarity. **A Global Net Connection (GNC) rule is specified
> for connecting the %s pin of the %s cell to the %s global net.** Check the imported design and
> ensure that the GNC rule is correctly specified or generated."

*Labelled inference:* IMPDB-1221 sits in the GNC-rule family and, on the evidence of the observed
behaviour, reports a GNC rule that matched no pin. The band membership is documented; the exact
wording of 1221 is not, in this install.

**NRDB-51 — this one *is* documented, and it is the whole downstream story**
(`innovuserrmsg/NRDB-51.html`):

> **SUMMARY:** "%s %s has no instance pin or special wire in its connectivity definition. %s with the
> same name will be routed but will not be connected to the empty %s."
>
> **DESCRIPTION:** "The root cause of this issue is that the net connectivity definition is
> incomplete. It may have the net name in the special net section but no instance pin or wire. If the
> net has connectivity in the regular net section it will have no target in the special net section
> and warn of the inconsistancey."

That is exactly what happened. The `SPECIAL_NET` records for `VDDIO`/`VSSIO` existed (they are in
`init_power_nets`) but were **empty**, because the GNC rules attached no instance pins. NanoRoute
therefore fell back to the identically-named *regular* nets and routed the IO supplies as ordinary
signals — around the periphery, straight into the bond-pad M8/M9 blockages. Every `VDDIO`/`VSSIO`
DRC record in the affected run is a "Regular Wire"; `VDD`/`VSS` have none. **76 violations.**

Note that NRDB-51's suggested remedies (`convertSNetToNet`, `ecoRoute` on selected nets) are the
**wrong** ones here — they would legalise the signal-net routing rather than restore PG status.

### 4.3 The remedy, at command level

The fix is not in `power_plan.tcl`. `config.tcl:160` points the LEF list at a local copy:

```tcl
set IO_PAD_DRIVER_LEF $::env(NANOSOC_ETH_CHIPLET_HOME)/ASIC/tech_wrappers/tsmc65/local_overrides/tphn65lpgv2od3_sl_9lm.lef
```

The override is **three added lines and nothing else** — verified by diffing it against the PDK
original at
`/tsmc65pdk/65/CMOS/LP/IO2.5V/iolib/STAGGERED/tphn65lpgv2od3_sl_210a_FE/TSMCHOME/digital/Back_End/lef/tphn65lpgv2od3_sl_210a/mt_2/9lm/lef/tphn65lpgv2od3_sl_9lm.lef`:

```
10102a10103
>         USE POWER ;          # PVDD2DGZ_G  PIN VDDPST
10170a10172
>         USE POWER ;          # PVDD2POC_G  PIN VDDPST
10855a10858
>         USE GROUND ;         # PVSS2DGZ_G  PIN VSSPST
```

Three lines, three macros, three pins. `PVDD1DGZ_G` `PIN VDD` and `PVSS1DGZ_G` `PIN VSS` already
carried `USE POWER ;` / `USE GROUND ;` in the vendor LEF — which is precisely why the *core*
supplies never had this problem and the *IO* supplies did.

The shared PDK under `/tsmc65pdk` is read-only and is not modified; re-copy and re-diff if the PDK
revs.

**How to prove the fix is live**, in order of cost:

1. `grep -c IMPDB-1221 work/innovus.log*` → **0**.
2. `grep -c NRDB-51 work/innovus.log*` → **0**.
3. In the DRC report, no `Regular Wire` on `VDDIO` or `VSSIO`.
4. Add `-verbose` to L47 and L49 and read the connection statistics directly.

**What the fix does *not* do.** It stops the router mis-routing the IO supplies. It does not route
them — nothing in this file ever names `VDDIO`/`VSSIO` in an `add_rings`, `add_stripes` or
`route_special` call, and per §1.4 the LEF gives the tool nothing to route them *to*. The two
`IMPVFC-98` "no routing" records for `VDDIO`/`VSSIO` in the connectivity report are the expected,
correct output of that situation. Continuity of the IO ring is an LVS check.

---

## 5. Why a domain with no supply nets stops filler insertion

The incident — a GDSII with zero filler cells and ~95,568 free-site gaps — is
[04-power-plan §1](../04-power-plan.md#1-the-big-trap-pd_top-has-no-supply-nets-and-the-die-ships-unfilled)
and is not repeated. What that page does not give is the *mechanism*.

**Filler insertion is a power-domain operation.** Stylus TCR — `add_fillers`
(`TCRcom/add_fillers.html`): "Inserts filler cell instances in the gaps between standard cell
instances. **Filler cell instances provide continuity for the power and ground rails, as well as
for n-wells.**" And `-power_domain`: "Specifies the power domain in which to add filler cells.
**Default: tries to add fillers to all power domains.**"

So the operation is per-domain by construction, and its stated purpose is *rail continuity*. To
place a filler, Innovus must know which supply nets that domain's rails carry — it has to hook the
new instance's `USE POWER` / `USE GROUND` pins onto real nets and apply the domain's GNC rules. A
domain with no primary power net and no primary ground net gives it nothing to hook to, and it
refuses:

```
**ERROR: (IMPSP-5110):  No supply-net names for Power Domain 'PD_TOP'.
For 0 new insts, *** Applied 0 GNC rules.
```

The `Applied 0 GNC rules` half of that message is the tell: the failure is on the *connection* side,
not the placement side. There is nothing wrong with the gaps.

**IMPSP-5110 has no page in the installed help set either.** `innovuserrmsg/` ships 83 `IMPSP-*`
pages; the nearest neighbours to 5110 are `IMPSP-5106` (an `addEndCap` pre-placed-cell error) and
`IMPSP-5113` (a tie-cell count error), and a grep for the literal `IMPSP-5110` across
`innovuserrmsg/`, `TCRcom/`, `innovusTCR/` and `UGcom/` returns nothing. The quoted text above is
from **this design's run log**, not from a manual. Use `man IMPSP-5110` in a live session for the
tool's own wording.

**Three commands in `power_plan.tcl` depend on the same missing information**, which is why the L40
guard exists at all:

| Line | Command / option | Manual text that depends on domain supply nets |
|---|---|---|
| 94, 132 | `add_stripes -extend_to all_domains` | "Stripes are created over all power domains **for each power and ground net within each power domain**… and ignore the values in the `-nets` parameter." |
| 159 | `add_stripes -over_power_domain 1` | "the software issues a warning message if the specified power and ground nets **do not match the power domain's power or ground nets**." |
| 168 | `route_special -power_domains { PD_TOP }` | "Restricts `route_special` activity to the specified power domains." |

**The repair is a CPF edit, not an Innovus command.** CPF Ref (`cpf_ref/reference.html`,
Common Power Format Language Reference, Product Version 2.0) documents both halves:

- `create_power_nets -nets net_list …` — "Specifies or creates a list of power nets. **Even if this
  net exists in the RTL or the netlist, it still must be declared through this command if the net is
  referenced in other CPF commands.**"
- `update_power_domain -name domain { -primary_power_net net | -primary_ground_net net | … }` —
  "Specifies implementation aspects of the specified power domain… The primary power and ground pins
  of all instances in a power domain will be connected to the primary, or equivalent power and
  ground nets of the domain." The reference's own example is `update_power_domain -name PDVDD
  -primary_power_net VDD -primary_ground_net VSS`.

`update_power_domain` in *Innovus* is a different command with the same name — it takes the domain
positionally and its option set is floorplan geometry (`core_to_*`, `row_*`, `gap_*`), with no
`-primary_power_net` at all. That is why the fix lives in the `cpf-patch` make target and not here.

---

## 6. Verification — what actually proves this plan is sound

### 6.1 The command names, checked against this version

| You might reach for | In Innovus 21.11 stylus | Evidence |
|---|---|---|
| `verify_power_via` | **does not exist.** Use **`check_power_vias`** | `TCRcom/check_power_vias.html`; the legacy-UI name is `verifyPowerVia` (`innovusTCR/verifyPowerVia.html`) |
| `check_design -type power` | **not a valid enum.** Use **`-type power_intent`** | `TCRcom/check_design.html`: the enum is `{power_intent timing hierarchical pin_assign budget assign_statements place opt cts route signoff all}`, and `power_intent` is "Checks related to MSV setup including power domain/fence checks" |
| a PG-open report | `check_connectivity` (`IMPVFC-*`) | what the flow actually runs |

Other relevant commands that exist in this version and are unused here: `check_pg_shorts`
("Checks for power and ground shorts between two geometries belonging to different nets… PG and PG
nets / PG and signal nets / PG and other special net", `TCRcom/check_pg_shorts.html`),
`check_endcaps` ("Checks whether pre/post cap cells have been inserted correctly… Inserted end cap
cell is of wrong type / End cap cell is missing", `TCRcom/check_endcaps.html`),
`check_power_domains`, `report_power_domains`, `check_filler` and `update_power_vias`.

One trap: **`report_special_routes` is not a general PG report** in this version. The TCR
(`TCRcom/report_special_routes.html`) scopes it to "the length of all RDL routes (SPECIALNETS)
created with the `route_flip_chip` command" — flip-chip RDL, which this design does not use. Do not
reach for it to audit the mesh.

### 6.2 What the flow currently runs

[`4_pnr_route.tcl:43-46`](https://github.com/SoC-Labs/ASIC-Flow/blob/b19e7845448e641ea8353b19a59a77257907cb13/Cadence/4_pnr_route.tcl) — four checks, at the
very end of the run:

```tcl
check_drc            -out_file .../${block_name}_imp_drc.rep
check_filler         -out_file .../${block_name}_imp_filler.rep
check_connectivity   -out_file .../${block_name}_imp_connectivity.rep
check_process_antenna -out_file .../${block_name}_imp_antenna.rep
```

**`check_power_vias` is never run. `check_design -type power_intent` is never run.
`check_pg_shorts` is never run.** The power plan's own dedicated verification command has, on the
evidence of the flow scripts, never been executed on this design.

That matters because of what `check_power_vias` does (`TCRcom/check_power_vias.html`): "This command
has a variety of power-rail overlap checks to look for **missing power-grid vias**. By default, it
checks that orthogonal power-routes on adjacent routing layers have a via between them at every
intersection… Violations are highlighted in the layout window, and a text report is generated with
the location of the missing vias."

Missing power-grid vias is *exactly* the failure class under investigation in
[15-pg-opens-analysis](../15-pg-opens-analysis.md).

### 6.3 What the 329 opens mean for this plan

Do not re-derive the analysis; it is [15-pg-opens-analysis](../15-pg-opens-analysis.md). The
implications *for this script* are:

1. **The number is unsafe as printed.** `check_connectivity` runs with no message-limit override, so
   it stops at 1000 messages. `core50`'s 329 is complete; today's 318 is truncated mid-VDD, and the
   true figure is estimated ≈334 — i.e. **worse**, not better.
2. **85–89 % of the opens are one defect**, a 0.330 µm riser at ±0.300 µm from a macro's left or
   right edge, centred on a standard-cell rail. Its geometry is set by `split_row -selected` (§3.8,
   no halo) and `route_special -core_pin_target first_after_row_end` (§3.10) acting together.
3. **`sroute` reports success.** The opens appear afterwards, in the shadow-via rebuild, where
   `IMPPP-570` fires — "The power planner detected cut layer obstruction(s) and cannot create via on
   the %s layer at (%f, %f) (%f, %f)… Due to cut layer related collision, tool fail to create via on
   the given spot" (`innovuserrmsg/IMPPP-570.html`). Anything that reads only `route_special`'s own
   summary will call this a clean run.
4. **The two lines to change are in this file** if H1 or H2 is confirmed: L152 (`split_row`) and
   L168 (`-core_pin_target`).

### 6.4 A verification block worth adding

Nothing below is currently in the flow. This is a proposal, not a record.

```tcl
# after the final route_special in power_plan.tcl.
# Option spellings verified against TCRcom/{check_power_vias,check_pg_shorts,check_endcaps}.html.
check_power_vias -nets {VDD VSS} \
                 -rail_layers M1 -stripe_layers {M5 M8 M9} \
                 -report $REPORT_DIR/${block_name}_pg_vias.rep

check_pg_shorts  -out_file $REPORT_DIR/${block_name}_pg_shorts.rep   ;# -net is singular

check_endcaps    -wrong_location \
                 -out_file $REPORT_DIR/${block_name}_endcaps.rep
```

and, at the point `check_connectivity` runs, an uncapped invocation so the counts mean something:

```tcl
check_connectivity -error 200000 -warning 200000 \
                   -out_file $REPORT_DIR/${block_name}_imp_connectivity.rep
```

The last of those is H0 in [15-pg-opens-analysis §8](../15-pg-opens-analysis.md), costs about a
minute, and must precede any other conclusion about the open count.

---

## 7. Dependencies — what must change if…

### 7.1 …you add a power domain

[`docs/POWER_DOMAINS.md`](../../POWER_DOMAINS.md) analyses the candidate CORE / LINK / PHY split and
recommends **one domain for v1**. If that recommendation is ever reversed, this file changes in nine
places:

| Where | Change |
|---|---|
| CPF / UPF | `create_power_domain` + `create_power_nets` + `update_power_domain -primary_power_net/-primary_ground_net` **for the new domain**. §5 applies to it independently — a second domain with no supply nets breaks filler for that domain only, which is even easier to miss |
| `config.tcl:125-126` | add the new supply to `power_nets` / `ground_nets`, so it exists before `init_design` (IMPDB-1216) |
| L40 guard | extend to check every expected domain, and check the *nets*, not just the domain object |
| L46–49 | one `connect_global_net … -power_domain <NEW>` per new supply. `-power_domain` is a documented alternative to `-inst_base_name` and is the right selector once domains exist |
| L55 `add_rings` | a domain ring: a second call with `-type block_rings -around power_domain`. The Stylus UG's worked example is exactly this (`UGcom/Power_Planning_and_Routing.html`) |
| L81 `add_stripes_ignore_non_default_domains true` | **re-examine.** It currently forces global stripes straight over non-default domains without breaking. With a real second domain that is usually wrong |
| L94 / L132 `-extend_to all_domains` | now genuinely multi-domain. Re-read the clause "ignore the values in the `-nets` parameter" — the stripes will follow each domain's own nets |
| L159 `-over_power_domain 1` | now confines the M5 feed to whichever domain is current; you will need one call per domain |
| L168 `-power_domains { PD_TOP }` | add the new domain, or drop the option to get the documented default (all domains). Also `route_special -connect secondary_power_pin` + `-secondary_pin_net` becomes relevant for level shifters |

Plus, outside this file: isolation and level-shifter insertion, `add_endcaps -power_domain`,
`add_fillers -power_domain`, and `check_design -type power_intent` becoming genuinely load-bearing.

### 7.2 …you move to a different metal stack

Anything other than `9M_6X1Z1U` invalidates specific literals here. The dependency chain is short
but every link is a hard number:

| What | Depends on | Breaks how |
|---|---|---|
| `-layer {top M9 bottom M9 left M8 right M8}` (L55) | M9 `DIRECTION HORIZONTAL`, M8 `DIRECTION VERTICAL` | on a stack with different top-layer directions, the rings land in non-preferred direction |
| `-width … 12` (L55) | `MAXWIDTH 12` on **both** M8 and M9 | on a stack whose top metals allow more (or less), 12 is either wasteful or illegal. It is currently at the ceiling |
| `-spacing 1.2` on M8 (L94) | M8 `SPACINGTABLE` requiring ≤0.5 at width 3.6 | a stack with a stricter table turns this into the M9 defect |
| `-spacing 3.05` on M9 (L132) | M9 `SPACING 2` **and** `MINENCLOSEDAREA 9` (3.05 ≈ √9) | recompute from the new layer's `MINENCLOSEDAREA`; the tool will tell you the number in `IMPPP-193` |
| `-width 3.6` (L94, L132) | `MINIMUMCUT 2 WIDTH 1.800` on M8/M9 | below 1.8 µm the 2-cut requirement lapses and the via arrays change character |
| `-layer M5` (L159) | M5 `DIRECTION HORIZONTAL` and the macros' M4 PG pins | the macro-feed layer must be orthogonal to the macro pin layer, or you get the `IMPPP-532` class of failure that [15-pg-opens-analysis H4](../15-pg-opens-analysis.md) already sees between M8 and M4 |
| `AP(10)`, `-*_layer_limit AP` | AP being routing layer **10** | a stack with a different layer count renumbers everything. Prefer the LEF names over `name(number)` |
| `add_rings_stacked_via_top_layer M9` (L51) | AP existing above M9 | on a stack with no RDL, M9 *is* the top and this restates the default |
| `-set_to_set_distance 60` / `15` | nothing in the LEF — these are IR-drop choices | not a correctness issue, but they have never been validated against a rail analysis. See §8 |

The stack string itself appears in three places that must move together: `config.tcl:131`
(`TECH_LEF`), `config.tcl:134` (`IO_PAD_LEF`, whose path contains `9M_6X1Z1U`), and
`config.tcl:209` (`drc_ruledeck`, `CLN65S_9M_6X1Z1U.26_2a`).

---

## 8. Defects and unverified claims found writing this page

Everything here is **static**: reports, logs, LEFs and Tcl. No tool was launched. Ordered by
confidence.

**Solid, and actionable:**

1. **`-pad_pin_width 6` at L166 matches no pad pin.** The complete set of PG pad-pin rect dimensions
   in the IO LEF is `{1.5 1.56 1.63 1.84 2.505 3.0 3.7 3.725 3.75 4.0 4.5 22.0 53.0}`. Per the TCR,
   the option "Routes only pad pins that have the specified width", so the `pad_pin` half of that
   pass is very likely a no-op. **Fix: delete the option** — "It is usually not necessary to specify
   a pin width."
2. **`add_endcaps -start_row_cap` / `-end_row_cap` are undocumented in both UIs.** In stylus the
   cells come from `set_db add_endcaps_left_edge` / `add_endcaps_right_edge`. Nobody has ever run
   `check_endcaps` on this design, so whether any cap was inserted is unknown. Cheap to settle.
3. **`add_stripes_ignore_block_check` is inert** while `break_at` is `none` (the manual says so
   explicitly), and its documented polarity is the reverse of its name — which means
   [04-power-plan §4](../04-power-plan.md#4-stripes)'s description of `true` as "block-check off" is
   the opposite of the manual's. No behavioural consequence today; will matter if `break_at` is ever
   set.
4. **`-start_from left` with `-direction horizontal` (L132) is out-of-domain.** The TCR documents
   `bottom`/`top` for horizontal. Almost certainly silently defaulting to `bottom`, which is what was
   wanted — but it is a copy-paste from L94 and it should say `bottom`.
5. **`VDDACC` is declared in `init_power_nets` and used nowhere in the Cadence flow.** It survives
   from the Synopsys ICC2 script's `ACCEL` voltage area. Either give it a domain and a plan, or
   remove it from `config.tcl:125` — an empty declared PG net is exactly the NRDB-51 precondition.
6. **The power plan is never verified.** `check_power_vias`, `check_pg_shorts` and
   `check_design -type power_intent` appear nowhere in the flow. §6.4 proposes the block.
7. **`route_special` never runs after placement or routing.** Everything in §3.10 is built on an
   unplaced database and never repaired.
8. **`add_well_taps` is never called.** The `add_endcaps` page names it as the next step in the
   documented sequence. Whether `tcbn65lp` needs it at 9-track is a library question this page does
   not answer.

**Documented-but-inconsistent, i.e. probably manual bugs — flagged so nobody "fixes" the script:**

9. `route_special -layer_change_range` is documented as `{ topLayerName bottomLayerName }` while
   every sibling range option (`-crossover_via_layer_range`, `-target_via_layer_range`,
   `-block_pin_layer_range`, `-pad_pin_layer_range`) is documented low-then-high. The script uses
   low-then-high consistently. Leave it.
10. `-pad_pin_port_connect` enum text is self-contradictory in the TCR: `all_geom` is glossed as
    "Routes to only one port of a pad pin if multiple ports are defined in the LEF file", which is
    what `one_port` should mean. The `{all_port all_geom}` pairing in this script is the widest
    reading of either gloss.

**Not established — do not repeat these as fact:**

11. **Stripe set counts** (≈20 M8, ≈26 M9, ≈105 M5) are arithmetic from pitch and core size, not
    measured from the database.
12. **Whether the IO supply ring is electrically continuous.** §1.4 establishes that the *LEF* does
    not model it and Innovus therefore cannot check it. It does not establish that the silicon ring
    is broken — that is an LVS result and this page has not seen one.
13. **VDD-inner / VSS-outer ring ordering** is inferred from `add_stripes`' documented net ordering;
    the `add_rings` page states no such rule.
14. **The 60 µm / 15 µm stripe pitches have never been validated against an IR-drop or EM analysis.**
    No rail analysis exists for this design. The pitches are inherited from the 2023 original.
15. **Whether `via_using_exact_crossover_size false` + `split_vias false` contributes to the PG
    opens.** These attributes govern `add_stripes` only, and
    [15-pg-opens-analysis](../15-pg-opens-analysis.md) locates the dominant defect in
    `route_special`'s core-pin path. The interaction is plausible but untested.

---

## See also

- [04-power-plan](../04-power-plan.md) — the narrative: the `PD_TOP` trap, the M9 spacing incident,
  the sign-off checklist
- [03-floorplan](../03-floorplan.md) — the core box, `CORE_TO_IO 70`, and why the 28 µm ring band
  drove it
- [06-fill-antenna-bondpads](../06-fill-antenna-bondpads.md) — what `add_fillers` does once §5 is fixed
- [14-drc-triage](../14-drc-triage.md) — the surviving violations, including the PG-vs-bond-pad class
- [15-pg-opens-analysis](../15-pg-opens-analysis.md) — the 329 opens, their geometry, and the ranked
  experiments that would settle them
- [16-open-defects](../16-open-defects.md) · [11-known-issues](../11-known-issues.md)
- [`docs/POWER_DOMAINS.md`](../../POWER_DOMAINS.md) — the CORE/LINK/PHY domain analysis behind §7.1
