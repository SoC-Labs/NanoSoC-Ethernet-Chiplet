# 03 — MMMC, SDC and power intent

[index](../00-index.md) · [04 Power plan](../04-power-plan.md) · [09 Signoff](../09-signoff-checklist.md) · [11 Known issues](../11-known-issues.md) · [16 Open defects](../16-open-defects.md)

Block: `nanosoc_eth_chiplet_pads` · TSMC 65nm LP (`9M_6X1Z1U`) · Genus 21.15-s080_1 → Innovus
21.11-s130_1 in **stylus** (Common UI) mode.

This page annotates the files that tell the tools **what "fast enough" means** and **what is
powered by what**. It is a reference, not a tutorial: every claim is tied to a line number in
this repository, a line in a real run log, or a page in the installed Cadence manuals.

**Manual citations are Common UI.** This flow runs `innovus -stylus`, so commands are cited
from `$INNOVUS_HOME/doc/TCRcom/` (Stylus Common UI Text Command Reference, product
version 21.11) and `$INNOVUS_HOME/doc/UGcom/` (Common UI User Guide). The legacy-UI
editions (`innovusTCR/`, `innovusUG/`) document a different option spelling — see
[§2.3](#24-a-note-on-option-spelling). Only pages actually opened are cited; where the manuals
say nothing, this page says so.

**Read first, do not duplicate:** [04 — Power plan](../04-power-plan.md) (the `IMPSP-5110` /
filler trap, the global-net connections and the IO LEF override) and
[`docs/POWER_DOMAINS.md`](../../POWER_DOMAINS.md) (why this chip has exactly one power
domain). This page explains the *files*; those two explain the *decisions*.

---

## Contents

- [1. What these files are, and who reads them](#1-what-these-files-are-and-who-reads-them)
- [2. MMMC primer](#2-mmmc-primer)
- [3. `nanosoc_eth_chiplet_pads.mmmc`, line by line](#3-nanosoc_eth_chiplet_padsmmmc-line-by-line)
- [4. The SDC set](#4-the-sdc-set)
  - [4.1 `constraints.sdc`](#41-constraintssdc)
  - [4.2 `qspi_constraints.sdc`](#42-qspi_constraintssdc)
  - [4.3 `tidelink_constraints.sdc`](#43-tidelink_constraintssdc)
  - [4.4 `ethernet_constraints.sdc`](#44-ethernet_constraintssdc)
  - [4.5 What is *not* constrained](#45-what-is-not-constrained)
- [5. Constraint review — what is dead, and what is suspicious](#5-constraint-review-what-is-dead-and-what-is-suspicious)
- [6. Power intent: UPF, CPF and the generated files](#6-power-intent-upf-cpf-and-the-generated-files)
  - [6.1 What power intent is](#61-what-power-intent-is)
  - [6.2 `nanosoc_eth_chiplet_pads.upf` annotated](#62-nanosoc_eth_chiplet_padsupf-annotated)
  - [6.3 `nanosoc_chip_pads.cpf` — a dead file](#63-nanosoc_chip_padscpf-a-dead-file)
  - [6.4 The generated `_gate2.upf` and `_gate1.cpf`](#64-the-generated-_gate2upf-and-_gate1cpf)
  - [6.5 `IMPSP-5110` and the `cpf-patch` repair](#65-impsp-5110-and-the-cpf-patch-repair)
  - [6.6 What `check_cpf` already told us](#66-what-check_cpf-already-told-us)
- [7. If you change X, you must also change Y](#7-if-you-change-x-you-must-also-change-y)
- [8. Manual pages cited](#8-manual-pages-cited)

---

## 1. What these files are, and who reads them

| File | Authored / generated | Read by | Where |
|---|---|---|---|
| [`inputs/constraints.sdc`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/inputs/constraints.sdc) (135 lines) | authored | Genus | `1_synthesis.tcl:47` `read_sdc $constraints_file` |
| [`inputs/qspi_constraints.sdc`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/inputs/qspi_constraints.sdc) (9) | authored | Genus, via `source` | `constraints.sdc:82` |
| [`inputs/tidelink_constraints.sdc`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/inputs/tidelink_constraints.sdc) (8) | authored | Genus, via `source` | `constraints.sdc:84` |
| [`inputs/ethernet_constraints.sdc`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/inputs/ethernet_constraints.sdc) (95) | authored | Genus, via `source` | `constraints.sdc:86` |
| `outputs/nanosoc_eth_chiplet_pads_syn.sdc` (957) | **generated** by `write_sdc` | Innovus | `1_synthesis.tcl:92` writes it; the `.mmmc` reads it |
| [`scripts/nanosoc_eth_chiplet_pads.mmmc`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/nanosoc_eth_chiplet_pads.mmmc) (198) | authored | **Innovus only** | `2_pnr_setup.tcl:24` `read_mmmc` |
| [`inputs/nanosoc_eth_chiplet_pads.upf`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/inputs/nanosoc_eth_chiplet_pads.upf) (128) | authored | Genus | `1_synthesis.tcl:31` `read_power_intent -module $block_name` |
| [`inputs/nanosoc_chip_pads.cpf`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/inputs/nanosoc_chip_pads.cpf) (39) | authored | **nobody** — see [§6.3](#63-nanosoc_chip_padscpf-a-dead-file) | — |
| `outputs/..._gate1.cpf` (21) | **generated** by `write_power_intent -cpf`, then **patched** | Innovus | `2_pnr_setup.tcl:40` |
| `outputs/..._gate2.upf` (132) | **generated** by `write_power_intent` | nobody in this flow | — |

The important structural fact: **Genus and Innovus do not read the same constraints.** Genus
reads the four hand-written SDC files; Innovus reads only the single `_syn.sdc` that Genus
wrote, through the `.mmmc`'s one constraint mode. Genus auto-ungroups hierarchy, so the
hand-written paths (`u_.../u_soc/u_soc/u_network_core/...`) are rewritten by `write_sdc` into
the flattened netlist's names (`u_nanosoc_eth_chiplet_chip_u_soc_u_soc/u_network_core/...`).
That rewrite is why editing an `inputs/*.sdc` and re-running P&R without re-running synthesis
changes nothing.

---

## 2. MMMC primer

### 2.1 The five object types

> "Multi-mode multi-corner analysis uses a tiered approach to assemble the information
> necessary for timing analysis and optimization. Each top-level definition (called an
> analysis view) is composed of a delay calculation corner and a constraint mode. The active
> analysis views defined in the software represent the different design variations that will
> be analyzed."
>
> — Innovus Common UI User Guide, "Configuring the Setup for Multi-Mode Multi-Corner
> Analysis" (`UGcom/Design_Import_and_Export_in_Stylus.html`)

| Object | Command | Holds | This design has |
|---|---|---|---|
| **library set** | `create_library_set` | a list of `.lib` timing libraries (+ `.cdb` SI libraries) treated as one entity | 3 |
| **timing condition** | `create_timing_condition` | "a set of libraries at a specific operating condition" (`TCRcom/create_timing_condition.html`) | 3 |
| **RC corner** | `create_rc_corner` | the capacitance table + R/C scaling used for parasitic extraction | 3 |
| **delay corner** | `create_delay_corner` | one or two timing conditions + an RC corner = everything needed to compute a delay | 4 |
| **constraint mode** | `create_constraint_mode` | a list of SDC files = one functional/test/DVFS mode | 1 |
| **analysis view** | `create_analysis_view` | (delay corner × constraint mode) | 5 defined |
| *(active set)* | `set_analysis_view` | which views are used for setup and for hold | 2 setup, 2 hold |

`read_mmmc` states the minimum contents explicitly:

> "At a minimum, the MMMC file must contain one each of: `create_library_set`,
> `create_rc_corner`, `create_timing_condition`, `create_delay_corner`,
> `create_constraint_mode`, `create_analysis_view`, `set_analysis_view`."
>
> — `TCRcom/read_mmmc.html`

### 2.2 Why setup and hold need different views

A setup check asks "did the data arrive **before** the capture edge?" — worst case is slow
data, so it wants the **slow** library (SS / low V / hot) and the **high-capacitance**
parasitic corner. A hold check asks "did the data stay stable **after** the capture edge?" —
worst case is fast data, so it wants the **fast** library (FF / high V / cold) and the
**low-capacitance** parasitic corner. One delay corner cannot be both, so MMMC uses separate
delay corners and the User Guide is explicit about the division of labour:

> "Use separate delay calculation corners to define major PVT operating points (for example,
> Best-Case and Worst-Case). Use the `-early_*` and `-late_*` parameters within a single delay
> calculation corner to control on-chip variation."
>
> — `UGcom/Design_Import_and_Export_in_Stylus.html`; the same sentence appears verbatim in
> `TCRcom/create_delay_corner.html`

That is exactly the split this file uses: `default_delay_corner_max` / `_min` are the two PVT
points; `default_delay_corner_ocv` is the OCV corner (early=fast, late=slow) built for
launch-vs-capture variation.

### 2.3 How Innovus picks the active views

`set_analysis_view -setup {...} -hold {...}` names the active set. Two behaviours matter here:

> "The order in which you specify the views with the `-setup` and `-hold` parameters is
> important. By default, the first views defined in the `-setup` and `-hold` lists are the
> default views."
>
> — `TCRcom/set_analysis_view.html`

and `read_mmmc` loads library data eagerly for the *first* view only:

> "The exceptions to data set load are the libraries pointed to by the first
> `set_analysis_view` command in the MMMC file. These library sets are loaded into the
> database."
>
> — `TCRcom/read_mmmc.html`

So `default_analysis_view_setup` (first in the `-setup` list) is the **default view**: any
step of the flow that is not MMMC-aware silently uses it. `read_mmmc` also warns that it
"does basic syntax checking … However, no consistency checking is performed" — a typo'd
constraint-mode name in an analysis view will not be caught at read time.

### 2.4 A note on option spelling

The Common UI uses underscore-separated option names (`-pre_route_cap`, `-post_route_res`,
`-temperature`, `-qrc_tech`). The legacy UI reference documents the same options as
`-preRoute_cap`, `-postRoute_res`, `-T`, `-qx_tech_file`. This `.mmmc` uses the **Common UI**
spelling throughout, matching `TCRcom/create_rc_corner.html`; if you are reading the legacy
page and the option names do not match the file, that is why.

Two commands used in this file exist **only** in the Common UI set:
`create_timing_condition` (there is no `innovusTCR/create_timing_condition.html`) and the
`-timing_condition` / `-early_timing_condition` / `-late_timing_condition` options of
`create_delay_corner` — the legacy page documents `-library_set` / `-early_library_set` /
`-late_library_set` instead.

---

## 3. `nanosoc_eth_chiplet_pads.mmmc`, line by line

Source: [`ASIC/genus-innovus/scripts/nanosoc_eth_chiplet_pads.mmmc`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/nanosoc_eth_chiplet_pads.mmmc).

### 3.1 Lines 1–13 — path variables

```tcl
 1  set phys_lib $PHYS_IP
 3  set base_path $::env(TSMC_65_HOME)/CMOS/LP/stclib/9-track/tcbn65lp-set/tcbn65lp_<rev>_FE/...
 4  set tech_path ${phys_lib}/arm/tsmc/cln65lp/arm_tech/<rev>
 5  set rf_32k_path $MEM_BASE/rf_32k
...
11  set bootrom_path $::env(NANOSOC_ETH_CHIPLET_HOME)/ASIC/romlibs/cc_rom
13  set IO_driver_path $::env(TSMC_65_HOME)/CMOS/LP/IO2.5V/iolib/STAGGERED/...
```

`TSMC_65_HOME` defaults to `$TSMC_65_HOME` (`ASIC/common.mk:79`). Lines 1 and 5–10 are
**absolute paths into shared, read-only lab trees** — the design is not relocatable without
these mounts. The ROM libraries (11–12) are the exception: they are inside the repo, and
`make romlibs-check` fails early if they are missing (`ASIC/genus-innovus/Makefile:73`).

### 3.2 Lines 15–58 — three library sets

```tcl
15  create_library_set -name default_libset_max\
16     -timing\
17      [list ${base_path}/.../tcbn65lpwc.lib \
18      ${rf_32k_path}/rf_32k_ss_1p08v_1p08v_125c.lib \
...
26      ${IO_driver_path}/tphn65lpgv2od3_slwc.lib] \
27     -si\
28      [list ${base_path}/Back_End/celtic/tcbn65lp_<rev>/tcbn65lpwc.cdb]
```

`create_library_set` "associates a TCL list of timing and cdB/UDN libraries with a specified
library set name" (`TCRcom/create_library_set.html`). Options used:

- **`-timing`** — the NLDM `.lib` files. The manual warns: *"The order in which you define
  timing libraries is important. The software considers the first library you specify in the
  list as the master library, with each successive library having a lower priority."* Here the
  standard-cell library is first in all three sets, which is the conventional choice.
- **`-si`** — *"Specifies cdB libraries and/or user-defined noise (UDN) models … required for
  performing signal integrity analysis."* All three sets carry a matching `.cdb`. **Note that
  SI is nonetheless off in the runs** — `reports/timing_summary_04_route.rep` reports
  `Signoff Settings: SI Off`, so these `.cdb` files are loaded but not exercised.

The PVT points, read straight out of the `operating_conditions` group of each library:

| Library set | Std cells | P / V / T | Memories | IO pads | IO P / V / T |
|---|---|---|---|---|---|
| `default_libset_max` (17–28) | `tcbn65lpwc.lib` (`WCCOM`) | SS / **1.08 V** / **125 °C** | `*_ss_1p08v_1p08v_125c` | `tphn65lpgv2od3_slwc` (`WCCOM`) | **3.0 V / 125 °C** |
| `default_libset_min` (32–43) | `tcbn65lplt.lib` (`LTCOM`) | FF / **1.32 V** / **−40 °C** | `*_ff_1p32v_1p32v_m40c` | `tphn65lpgv2od3_slbc` (`BCCOM`) | **3.6 V / 0 °C** |
| `typical_libset` (47–58) | `tcbn65lptc.lib` (`NCCOM`) | TT / **1.20 V** / **25 °C** | `*_tt_1p20v_1p20v_25c` | `tphn65lpgv2od3_sltc` (`NCCOM`) | **3.3 V / 25 °C** |

> **FINDING — the fast library set is not at a single temperature.** In
> `default_libset_min` the core and the memories are characterised at **−40 °C** while the IO
> pads are at **0 °C** (`BCCOM`). A −40 °C IO library exists in the same PDK directory —
> `tphn65lpgv2od3_sllt.lib`, `temperature : -40 ; voltage : 3.6 ;` — and is not used.
> *(Inference: this is most likely a copy of the vendor's default "bc" reference rather than a
> deliberate choice, because every other member of the set was moved to −40 °C.)* The
> consequence is confined to hold paths that pass through an IO cell — i.e. the pad-ring I/O
> paths, not the reg2reg core. **Do not "fix" this without re-running hold**; changing the IO
> min library changes every I/O hold number.

### 3.3 Lines 61–89 — three RC corners

```tcl
61  create_rc_corner -name default_rc_corner_worst\
62     -pre_route_res 1\
63     -post_route_res 1\
64     -pre_route_cap 1\
65     -post_route_cap 1\
66     -post_route_cross_cap 1\
67     -pre_route_clock_res 0\
68     -pre_route_clock_cap 0\
69     -cap_table ${tech_path}/cadence_captable/1p9m_6x2z/rcworst.captbl
```

`create_rc_corner` "provides the software with all of the information necessary to properly
extract, annotate, and use the RCs for delay calculation" (`TCRcom/create_rc_corner.html`).
Options used:

| Option | Manual | Value here |
|---|---|---|
| `-cap_table` | "Specifies the capacitance table to use for extraction when using this RC corner." | `rcworst` / `rcbest` / `typical` from the Arm `cln65lp` tech kit, `1p9m_6x2z` stack |
| `-pre_route_res` / `-pre_route_cap` | scale factors for pre-route extraction; **Default: 1.0** | `1` — i.e. explicitly the default |
| `-post_route_res` / `-post_route_cap` | scale factors for post-route extraction; **Default: 1.0** | `1` — explicitly the default |
| `-post_route_cross_cap` | "coupling capacitance scale factor … **Default: 1.0**" | `1` — explicitly the default |
| `-pre_route_clock_res` / `-pre_route_clock_cap` | "**Default: 0.** When this parameter is not specified, the value specified with the `-post_route_res`/`-post_route_cap` parameter is used for pre-route extraction." | `0` |

**Every scale factor in this file is its own default.** The three corners differ *only* in the
`.captbl`. That is fine, but it means the six scale-factor lines are decoration; do not read
them as tuning.

The `0` on the two clock parameters is the manual's documented "not specified" sentinel, and
the run confirms the tool resolves it that way — the extraction banner in
`reports/timing_summary_04_route.rep` reports, for all three corners:

```
      RC Corner Indexes            0       1       2
Capacitance Scaling Factor   : 1.00000 1.00000 1.00000
Clock Cap. Scaling Factor    : 1.00000 1.00000 1.00000
Clock Res. Scaling Factor    : 1.00000 1.00000 1.00000
```

i.e. clock nets inherit the post-route factor of 1.0, not a literal ×0.

Not used, and worth knowing about: **`-temperature`** (overrides the cap-table's temperature
for resistance derating) and **`-qrc_tech`** (a Quantus `.tch` file for signoff-grade
extraction). Without `-qrc_tech` this flow extracts with the Innovus cap-table engine only.
Consistent with that, the post-route summary reports `Parasitics Mode: No SPEF/RCDB`.

### 3.4 Lines 92–99 — three timing conditions

```tcl
92  create_timing_condition -name tc_max \
93     -library_sets {default_libset_max}
95  create_timing_condition -name tc_min \
96     -library_sets {default_libset_min}
98  create_timing_condition -name tc_typ \
99     -library_sets {typical_libset}
```

> "A timing condition is a set of libraries at a specific operating condition. Timing
> conditions are assigned to power domains or supply sets, and effectively describe the delay
> calculation requirements for the domains."
>
> — `TCRcom/create_timing_condition.html`

Only `-library_sets` is used. `-opcond` / `-opcond_library` (which would name a specific
`operating_conditions` group inside a library) are **not** used, so each library falls back to
its own default operating condition — `WCCOM`, `LTCOM`, `NCCOM` respectively, which are the
ones the table in §3.2 lists. That is the correct behaviour here, but note it means the PVT
point is implicit in the file choice, not stated in the MMMC.

Because there is one power domain and no supply-set-specific conditions, each timing condition
is a thin wrapper over one library set.

### 3.5 Lines 103–165 — the two-sided-corner comment block

63 lines of comment, and **the most important thing in the file to read before touching it**.
Summary of what it records (the full narrative is in the file and in
[`cts_setup.tcl`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/cts_setup.tcl)):

- `ccopt_design` writes the built clock tree's insertion delay back as a **negative source
  latency**, per (clock, view), emitting only the sides that view's analysis mode has.
- With OCV still off at that moment, `default_analysis_view_hold` received `-min` only:
  `set_clock_latency -source -early -min -rise -1.07637 [get_pins CLK]` and the `-late -min`
  twin, with **no `-max`**.
- Turning OCV on afterwards split min from max, the capture side of every hold check found
  nothing on the max side and used 0, and the design lost ~1.076 ns on **every** hold check.
- The measured cost: hold WNS −1.167 ns, TNS −66,212 ns, 96,545 violating paths, +37,407
  hold-repair instances.

Lines 147–165 are the correction to the correction, and the reason the two-sided form is kept
anyway:

```tcl
147  # STATUS 2026-08-07: THIS CHANGE DID NOT FIX THE HOLD PROBLEM. Recorded here so
148  # nobody spends another 5-hour run rediscovering it.
...
159  # The reason is simple in hindsight: `set_clock_latency -min/-max` is an SDC
160  # attribute of the CLOCK, not a property of the delay corner. Giving the corner
161  # two timing conditions does not give ccopt a second latency value to write.
```

That reading is consistent with the manual: `set_clock_latency` is an SDC assertion on a clock
object, and `create_delay_corner`'s early/late split governs *which libraries are used for
launch versus capture delay calculation*, not what values `ccopt` writes back. The real fix
lives in [`cts_setup.tcl:72`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/cts_setup.tcl) —
`set_db timing_analysis_type ocv` **before** `ccopt_design`. See
[16 — Open defects §1](../16-open-defects.md).

### 3.6 Lines 166–184 — four delay corners

```tcl
166  create_delay_corner -name default_delay_corner_max\
167     -early_timing_condition {tc_max}\
168     -late_timing_condition {tc_max}\
169     -rc_corner default_rc_corner_worst

171  create_delay_corner -name default_delay_corner_ocv\
172     -early_timing_condition {tc_min}\
173     -late_timing_condition {tc_max}\
174     -rc_corner default_rc_corner_typical

176  create_delay_corner -name default_delay_corner_min\
177     -early_timing_condition {tc_min}\
178     -late_timing_condition {tc_min}\
179     -rc_corner default_rc_corner_best

181  create_delay_corner -name typical_delay_corner\
182     -early_timing_condition {tc_typ}\
183     -late_timing_condition {tc_typ}\
184     -rc_corner default_rc_corner_typical
```

`-early_timing_condition` / `-late_timing_condition` each "specifies pair list of
domains/supply sets and timing conditions to associate with this delay corner object"; the
manual adds *"The `-early_timing_condition` and `-late_timing_condition` parameters should be
specified together"* (`TCRcom/create_delay_corner.html`). Both are always given here, so the
file is compliant. `-rc_corner` sets a single RC corner for both sides (the split forms
`-early_rc_corner` / `-late_rc_corner` are not used).

Decoded:

| Delay corner | early (launch) | late (capture) | parasitics | Meaning |
|---|---|---|---|---|
| `default_delay_corner_max` | SS 1.08 V 125 °C | SS 1.08 V 125 °C | `rcworst` | classic BC-WC **setup** corner |
| `default_delay_corner_min` | FF 1.32 V −40 °C | FF 1.32 V −40 °C | `rcbest` | classic BC-WC **hold** corner |
| `default_delay_corner_ocv` | FF 1.32 V −40 °C | SS 1.08 V 125 °C | `typical` | **OCV** corner: fast launch vs slow capture |
| `typical_delay_corner` | TT 1.20 V 25 °C | TT 1.20 V 25 °C | `typical` | the nominal sanity check |

`default_delay_corner_ocv` is the only corner that uses the `-early_*`/`-late_*` split as the
manual intends it ("to control on-chip variation … different conditions or libraries will be
used for the launch and capture paths of individual timing paths"). It is also, as §3.7 shows,
**not active**.

### 3.7 Lines 186–198 — constraint mode, views, active set

```tcl
186  create_constraint_mode -name default_constraint_mode\
187     -sdc_files\
188      [list ../outputs/nanosoc_eth_chiplet_pads_syn.sdc]

190  create_analysis_view -name default_analysis_view_setup -constraint_mode default_constraint_mode -delay_corner default_delay_corner_max
191  create_analysis_view -name default_analysis_view_hold  -constraint_mode default_constraint_mode -delay_corner default_delay_corner_min

193  create_analysis_view -name typical_analysis_view_setup -constraint_mode default_constraint_mode -delay_corner default_delay_corner_ocv
194  create_analysis_view -name typical_analysis_view_hold  -constraint_mode default_constraint_mode -delay_corner default_delay_corner_ocv

196  create_analysis_view -name typical_analysis_view       -constraint_mode default_constraint_mode -delay_corner typical_delay_corner

198  set_analysis_view -setup [list default_analysis_view_setup typical_analysis_view] -hold [list default_analysis_view_hold typical_analysis_view]
```

`create_constraint_mode` "associates a list of SDC constraint files with a specified
constraint mode name … A constraint mode defines one of possibly many different functional,
test, or Dynamic Voltage and Frequency Scaling (DVFS) modes of a design"
(`TCRcom/create_constraint_mode.html`). **There is one mode here.** There is no separate
test/scan mode — consistent with `DFT 0` in
[`config.tcl:123`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/config.tcl).

The path `../outputs/...` is relative to Innovus's cwd, which the Makefile sets to
`ASIC/genus-innovus/work/` (`cd $(WORK_DIR)`). It resolves correctly. It also means the
constraint mode points at a **generated** file: re-running `make syn` silently changes what
P&R will be constrained by.

`create_analysis_view` "associates a delay calculation corner with a constraint mode"
(`TCRcom/create_analysis_view.html`). Its `-power_modes` option — which would bind a view to a
power mode from the power intent file — is **not used**, which is why the CPF's single power
mode never affects delay calculation ([§6.3](#63-nanosoc_chip_padscpf-a-dead-file)).

`set_analysis_view` (line 198) selects the active set:

| View | Delay corner | setup | hold |
|---|---|---|---|
| `default_analysis_view_setup` | `..._max` (SS/rcworst) | ✅ **default view** | — |
| `default_analysis_view_hold` | `..._min` (FF/rcbest) | — | ✅ **default hold view** |
| `typical_analysis_view` | `typical` (TT/typical) | ✅ | ✅ |
| `typical_analysis_view_setup` | `..._ocv` | ❌ defined, never activated | ❌ |
| `typical_analysis_view_hold` | `..._ocv` | ❌ defined, never activated | ❌ |

> **FINDING — two views and the entire OCV delay corner are dead weight.** Lines 171–174 and
> 193–194 define `default_delay_corner_ocv` and two views on it that `set_analysis_view` never
> activates. They cost nothing at runtime (`read_mmmc` caches but does not load inactive
> views) but they are misleading: the design is **not** analysed on a fast-launch/slow-capture
> corner despite the file appearing to define one. The run confirms only three RC corners are
> live — `reports/timing_summary_04_route.rep` reports `RC Extraction called in
> multi-corner(3) mode` and lists exactly three `.cdb` files.
>
> The two views also collide semantically: `typical_analysis_view_setup` and
> `typical_analysis_view_hold` are *identical* (same corner, same mode), so activating them as
> written would not give you an OCV setup/hold pair — it would give you the same view twice.

Three active views × one constraint mode = the design is closed at SS/125 °C/rcworst for
setup, FF/−40 °C/rcbest for hold, and TT for both as a cross-check. `Analysis Mode: MMMC OCV`
in the post-route summary refers to `timing_analysis_type ocv` set in `cts_setup.tcl`, not to
the unused `..._ocv` delay corner.

---

## 4. The SDC set

`create_clock`, `set_input_delay` etc. are SDC commands, documented in the Common UI reference
alongside the native commands. Note one behaviour that shapes everything below:

> "If the input delay is not specified on an input port, it is assumed to be zero."
>
> — `TCRcom/set_input_delay.html`

Unconstrained inputs are therefore not "ignored" — they are timed with a **zero** external
budget, which is optimistic, not neutral.

### 4.1 `constraints.sdc`

#### Units and parameters (lines 14–31)

```tcl
16  set_units -time ns;
18  set_units -capacitance pF;
19  set EXTCLK_PERIOD $::env(CLK_PERIOD);
20  set SWDCLK_PERIOD [expr 4*$EXTCLK_PERIOD];
21  set CLK_ERROR 0.35; #Error calculated from worst case characteristics of CDCM61001 low-jitter oscillator chip at 250MHz
30  set CLK_HOLD_ERROR 0.05
31  set INTER_CLOCK_UNCERTAINTY 0.1
```

`CLK_PERIOD` defaults to **10.0** (`ASIC/common.mk:159`) ⇒ **100 MHz** system clock, 40 ns /
25 MHz SWD. `write_sdc` bakes the resolved numbers in (`_syn.sdc:15-16`:
`create_clock -name "clk" -period 10.0 -waveform {0.0 5.0}`) — **the environment variable does
not reach Innovus**, so a `CLK_PERIOD` change requires re-synthesis, not just a P&R re-run.

Minor inconsistency worth recording: the comment justifies 0.35 ns from an oscillator
characterised "at 250MHz", but the clock is constrained at 100 MHz. *(Inference: the margin
was carried over from a different clocking plan; it is conservative either way, so it is a
documentation issue, not a timing one.)*

#### Clock definitions (lines 33–34)

```tcl
33  create_clock -name "$EXTCLK" -period "$EXTCLK_PERIOD" -waveform "0 [expr $EXTCLK_PERIOD/2]" [get_ports CLK]
34  create_clock -name "$SWDCLK" -period "$SWDCLK_PERIOD" -waveform "0 [expr $SWDCLK_PERIOD/2]" [get_ports SWDCK]
```

`create_clock` "creates a clock object and defines its waveform in the current design … The new
clock has an ideal clock latency, and the software does not assume any propagation delay
through the clock network" (`TCRcom/create_clock.html`) — the tree is built later by CTS and
`set_propagated_clock` semantics take over. `-waveform "0 P/2"` is a 50 % duty cycle, i.e. the
default; it is written out explicitly.

Lines 36–47 document what is deliberately **not** declared: `rtc_clk` and `user_ref_clk` are
aliased onto the `sys_fclk` pad inside the generated wrapper, and `scan_clk` is tied. Verified
in the RTL — [`ASIC/tech_wrappers/tsmc65/nanosoc_eth_chiplet_pads.v:244-250`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/tech_wrappers/tsmc65/nanosoc_eth_chiplet_pads.v)
carries the comment *"Also feeds the wrapper's rtc_clk and user_ref_clk (aliased in the
spec)"* on the `uPAD_CLK_I` instance. **This aliasing is load-bearing for §5.**

#### Clock uncertainty (lines 61–67)

```tcl
61  set_clock_uncertainty -setup $CLK_ERROR      [get_clocks $EXTCLK]
62  set_clock_uncertainty -hold  $CLK_HOLD_ERROR [get_clocks $EXTCLK]
63  set_clock_uncertainty -setup $CLK_ERROR      [get_clocks $SWDCLK]
64  set_clock_uncertainty -hold  $CLK_HOLD_ERROR [get_clocks $SWDCLK]
66  set_clock_uncertainty -setup $INTER_CLOCK_UNCERTAINTY -rise_from [get_clocks $SWDCLK] -rise_to [get_clocks $EXTCLK]
67  set_clock_uncertainty -setup $INTER_CLOCK_UNCERTAINTY -rise_from [get_clocks $EXTCLK] -rise_to [get_clocks $SWDCLK]
```

`set_clock_uncertainty` "specifies the clock uncertainty (skew) on the clock network"; on
`-setup`/`-hold` the manual is unambiguous — *"Specifies whether the clock uncertainty applies
to setup or hold checks. **Default: Applies to both setup and hold check**"*
(`TCRcom/set_clock_uncertainty.html`). That default is precisely the bug lines 50–60 document
and fix, and why the split exists. Cross-reference: [11 — Known issues](../11-known-issues.md)
covers the history and the 62,729-instance hold-repair explosion it caused.

The manual also states the precedence used by lines 66–67: *"the constraints set with the
`-from*`/`-to*` parameters take precedence over simple constraints set on clock objects."*

**What each protects.** Lines 61/63 are oscillator jitter — a real setup margin. Lines 62/64
are residual non-common-mode jitter on a same-edge hold check. Lines 66/67 are an
inter-domain skew allowance between the debug and system clocks — but see §5, they are dead.

#### Cross-domain exceptions (lines 70–79)

```tcl
70  set_multicycle_path 2 -setup -end -from [get_clocks $SWDCLK] -to [get_clocks $EXTCLK]
71  set_multicycle_path 1 -hold -end -from [get_clocks $SWDCLK] -to [get_clocks $EXTCLK]
72  set_multicycle_path 2 -setup -end -from [get_clocks $EXTCLK] -to [get_clocks $SWDCLK]
73  set_multicycle_path 1 -hold -end -from [get_clocks $EXTCLK] -to [get_clocks $SWDCLK]
76  set_false_path -hold -from [get_clocks $EXTCLK] -to [get_clocks $SWDCLK]
79  set_multicycle_path 2 -from uPAD*/* -to uPAD*/*
```

`set_multicycle_path` "specifies multicycle paths between specific timing paths in the design
or between clock domains … By default, all paths are considered as one cycle paths"
(`TCRcom/set_multicycle_path.html`). Options here:

- **`-setup` / `-hold`** — *"If you do not specify `-setup` or `-hold` parameter, the software
  considers the specified multicycle value for setup check and uses 0 for the hold check."*
  This makes line 79's bare `2` **safe**: it is setup-only, and does not accidentally push the
  hold check out a cycle. (The generated SDC confirms Genus wrote it back as
  `... -setup -end 2`, `_syn.sdc:696`.)
- **`-end`** — *"Specifies whether the multicycle adjustment is to be applied relative to the
  starting clock edge for the path or relative to the ending clock edge … By default, the
  setup check is relative to the end clock and the hold check is relative to the start
  clock."* The 2/1 `-end` pairing on lines 70–73 is the standard idiom for relaxing an
  asynchronous handshake without moving the hold check.

Line 79's `uPAD*/*` pattern is already dissected in
[16 — Open defects §5](../16-open-defects.md): Genus expands it to **548 pin entries**, 68 of
which are pad **supply** pins that Innovus's `get_pins` will not return, producing 20+
`TCLCMD-917` errors against `_syn.sdc` line 696 on every P&R run. It is benign for timing but
it burns the message budget.

> *(Inference, evidence attached.)* Line 79 is also close to inert. `set_multicycle_path`'s
> `-from` requires valid path startpoints — *"Pins must be valid path startpoints such as
> sequential instance clock pins, latch data pins or pins on which input delays have been
> specified"* (`TCRcom/set_multicycle_path.html`) — and most pad pins are neither. The only
> paths it could describe are pad-to-pad, and `reports/timing_summary_04_route.rep` reports
> `Group : in2out  N/A  N/A  0`: **zero in2out endpoints in the design.** Confirm with
> `report_path_exceptions -ignored` (recommended by `UGcom/Timing_Analysis.html`) before
> deleting it.

#### Input delays (lines 90–93)

```tcl
90  set_input_delay -clock [get_clocks $EXTCLK] -add_delay 0.1 [get_ports NRST]
91  set_input_delay -clock [get_clocks $EXTCLK] -add_delay 0.1 [get_ports TEST]
92  set_input_delay -clock [get_clocks $EXTCLK] -add_delay 0.1 [get_ports HOSTIO4_P1]
93  set_input_delay -clock [get_clocks $SWDCLK] -add_delay 0.1 [get_ports SWDIO]
```

`set_input_delay` "defines the arrival time relative to a clock edge on input ports …
This input path delay models the delay from an external register to an input port of the
module" (`TCRcom/set_input_delay.html`). `-add_delay` *"adds delay information to the existing
input delay … If you do not use the `-add_delay` option, the software uses the last
`set_input_delay` related to a pin when there are multiple `set_input_delay` statements."*

Neither `-min` nor `-max` is given, so 0.1 ns applies to both. 0.1 ns on a 10 ns clock is a
token budget — these are asynchronous or slow control pins (`NRST`, `TEST`, the host-IO
bidirs, SWD data), so a nominal value is defensible; do not mistake it for a characterised
number. `get_ports HOSTIO4_P1` correctly expands to all seven bits (`_syn.sdc` carries
`HOSTIO4_P1[0]`…`[6]`).

#### Asynchronous clock groups (lines 126–131)

```tcl
126  set_clock_groups -asynchronous -name eth_chiplet_cdc \
127      -group [get_clocks [list $EXTCLK QSPI_SCLK QSPI_SCLK_o]] \
128      -group [get_clocks {D2D_TX_CLK_0}] \
129      -group [get_clocks {D2D_RX_CLK_0}] \
130      -group [get_clocks {rmii_ref_clk mii_rx_clk mii_tx_clk}] \
131      -group [get_clocks [list $SWDCLK]]
```

This is the single most consequential line in the constraint set. From
`TCRcom/set_clock_groups.html`:

> "**`-asynchronous`** — Defines clock group with asynchronous clocks. Asynchronous clocks have
> no specified phase relationship. The software considers asynchronous nets to have infinite
> timing window overlap for signal integrity considerations and **considers these as false
> paths for timing analysis**."

and, critically:

> "The software **drops any explicit false path assertions between clocks** that you have set
> as either physically or logically exclusive or asynchronous using the `set_clock_groups`
> command."

and:

> "The software **does not apply clock groupings on a master clock to the generated child
> clocks**."

That last sentence is why every generated clock is named explicitly. All nine clocks in the
design are accounted for — 4 `create_clock` + 5 `create_generated_clock` in `_syn.sdc`, and
3+1+1+3+1 = 9 across the five groups. **This is correct and non-obvious; preserve it.** Adding
a `create_generated_clock` anywhere without adding it to a group leaves it in the implicit
default group, silently synchronous with nothing.

The comment block (95–125) is honest about the rest: line 122 carries an explicit
`[OWNER] For SIGNOFF, narrow the D2D_RX_CLK_0 cut rather than leaving it a blanket group`,
which [09 — Signoff checklist](../09-signoff-checklist.md) restates as *"A blanket async group
means the tool reported nothing about that crossing."*

#### Design rule limits (lines 133–134)

```tcl
133  set_max_capacitance 3 [all_outputs]
134  set_max_fanout 10 [all_inputs]
```

`set_max_capacitance` "sets the maximum capacitance limit on the specified ports of the top
cell, the specified modules, or clock waveforms" (`TCRcom/set_max_capacitance.html`);
`set_max_fanout` likewise "on the specified input ports of the top cell and the specified
modules" (`TCRcom/set_max_fanout.html`). Both manuals note that library limits also apply and
*"the most constraining limit is applied"*.

**These apply to top-level ports only.** `write_sdc` resolved the collections and wrote out
**30** individual `set_max_capacitance` and **33** `set_max_fanout` assertions — i.e.
`all_outputs` = the 30 output and inout ports, `all_inputs` = the 33 input and inout ports.
Internal nets are governed entirely by the library's own
`max_capacitance` / `max_transition`. So the 36 `max_capacitance` and 84 `max_transition`
violations in `reports/timing_summary_04_route.rep` are almost certainly library-limit
violations, not violations of line 133. This matches
[11 — Known issues](../11-known-issues.md), which says `max_transition` comes from the library.

Units: `set_units -capacitance pF` (line 18) ⇒ the limit is **3 pF**, and `write_sdc` records
it as `set_units -capacitance 1000fF` — the same thing.

### 4.2 `qspi_constraints.sdc`

```tcl
2  create_generated_clock -name "QSPI_SCLK"   -source [get_ports CLK] -divide_by 2 [get_pins .../u_qspi_clock_div/QSPI_SCLK_i]
3  create_generated_clock -name "QSPI_SCLK_o" -source [get_pins .../u_qspi_clock_div/QSPI_SCLK_i] -divide_by 1 [get_ports QSPI_SCLK]
5  set_input_delay  -min 0  -clock "QSPI_SCLK"   [get_ports {QSPI_IO[*]}]
6  set_input_delay  -max 1  -clock "QSPI_SCLK"   [get_ports {QSPI_IO[*]}]
8  set_output_delay -min 0  -clock "QSPI_SCLK_o" [get_ports {QSPI_IO[*]}]
9  set_output_delay -max 1  -clock "QSPI_SCLK_o" [get_ports {QSPI_IO[*]}]
```

`create_generated_clock` "creates a new clock signal from the clock waveform of a given pin in
the design, and binds it with the pins or hierarchical pins in the `target_pin_list`
argument. Whenever the source clock changes, the derived clock(s) change automatically"
(`TCRcom/create_generated_clock.html`).

The two-step declaration is the right idiom for a **source-synchronous output clock**: the
internal divider output is one clock (50 MHz, `CLK`/2), and the version that appears at the
`QSPI_SCLK` pad after the pad delay is a second, `-divide_by 1` copy of it. The output data
(`QSPI_IO`) is then constrained against the *pad-side* clock, so the pad's own delay cancels
out of the data-vs-clock skew budget — which is what the flash device actually sees.

The min/max split (0 / 1 ns) is a symmetric ±1 ns window around the SCLK edge. **This protects
the QSPI flash read/write window**, which is what the boot ROM depends on. Both clocks are in
the `$EXTCLK` group (`constraints.sdc:127`), so these checks are live.

### 4.3 `tidelink_constraints.sdc`

```tcl
2  create_clock -name "D2D_RX_CLK_0" -period "$EXTCLK_PERIOD" -waveform "0 [expr $EXTCLK_PERIOD/2]" [get_ports TL_CLK_RX]
4  set_input_delay 1 -clock [get_clocks "D2D_RX_CLK_0"] [get_ports {TL_RX[*]}]
6  create_generated_clock -name "D2D_TX_CLK_0" -source [get_pins .../u_wlink/pad_clk_tx] -divide_by 1 [get_ports TL_CLK_TX]
8  set_output_delay 0.8 -clock [get_clocks "D2D_TX_CLK_0"] [get_ports {TL_TX[*]}]
```

`D2D_RX_CLK_0` is a **primary** clock because it is driven by the *far die* — this is the
source-synchronous receive clock `docs/POWER_DOMAINS.md` and `docs/RESET_ORDERING.md` describe.
Declaring it `create_clock` (not generated) is correct: nothing on this die generates it.

`D2D_TX_CLK_0` is the mirror of the QSPI idiom — the pad-side copy of the internal TX clock.
`set_output_delay` "specifies the data required time on output ports"
(`TCRcom/set_output_delay.html`); 0.8 ns on a 10 ns period is the far die's setup requirement
plus board flight time.

Neither `-min`/`-max` is given on either, so both values apply to setup and hold. **`TL_RX` /
`TL_TX` therefore have no separate hold budget** — the same value is required time for setup
and required time for hold, which for a source-synchronous DDR-free link is a coarse
approximation. See §5 for the bigger problem with line 8.

### 4.4 `ethernet_constraints.sdc`

The most carefully reasoned file of the four, and the only one that documents *which RTL
register* each exception protects.

```tcl
18  set RMII_REF_PERIOD 20.0 ; # 50 MHz RMII reference (100BASE-TX); MII = REFCLK/2 = 25 MHz
23  create_clock -name "rmii_ref_clk" -period "$RMII_REF_PERIOD" ... [get_ports RMII_REF_CLK]
24  set_clock_uncertainty $CLK_ERROR [get_clocks rmii_ref_clk]
29  create_generated_clock -name "mii_rx_clk" -source [get_ports RMII_REF_CLK] -divide_by 2 [get_pins ${RMII2MII}/mrx_clk]
30  create_generated_clock -name "mii_tx_clk" -source [get_ports RMII_REF_CLK] -divide_by 2 [get_pins ${RMII2MII}/mtx_clk]
34  set_input_delay  -min 2 -clock [get_clocks rmii_ref_clk] [get_ports {RMII_RXD[*] RMII_CRS_DV}]
35  set_input_delay  -max 8 -clock [get_clocks rmii_ref_clk] [get_ports {RMII_RXD[*] RMII_CRS_DV}]
36  set_output_delay -min 2 -clock [get_clocks rmii_ref_clk] [get_ports {RMII_TXD[*] RMII_TX_EN}]
37  set_output_delay -max 8 -clock [get_clocks rmii_ref_clk] [get_ports {RMII_TXD[*] RMII_TX_EN}]
```

The MII clocks are declared as **generated** so CTS builds a real tree for them rather than
treating the divider outputs as data. That is right and it is exactly what
`create_generated_clock` is for. The ±(2, 8) ns window on a 20 ns reference is a deliberately
conservative bring-up budget, and the file says so (line 33: *"Conservative bring-up budget
(tune for signoff)"*).

Then three CDC blocks:

- **CDC 1 (56–57)** — two blanket `set_false_path` between the `clk` domain and the
  RMII/MII family, in the two directions with no path worth keeping.
- **CDC 2 (62–72)** — seven targeted `set_false_path`, one per synchroniser first stage, so
  that the `mii_rx → clk` direction stays otherwise timed. `set_false_path` "identifies false
  paths in a design, and breaks or disables specific instance timing arcs"; the manual notes
  `-to tpin` "disables all timing paths whose sink pin is a `tpin`"
  (`TCRcom/set_false_path.html`). Cutting **to the D pin of the capture flop** is the correct
  granularity for a two-flop synchroniser — it removes the metastable arc without touching the
  rest of the domain.
- **CDC 3 (84–85)** — a `set_multicycle_path 2/1 -end` on the `last_push_flags_mrx` bus, on
  the grounds that the data is stable for ≥2 destination cycles behind a toggle handshake.
  This is the *right* answer for a data-with-toggle crossing: it keeps the path timed rather
  than deleting it.

**These are asynchronous-crossing waivers, and CDC 2/3 are the well-argued kind** — named
registers, RTL-verified, with the reason recorded. CDC 1 is the blunt kind. See §5 for what
actually happens to all three.

### 4.5 What is *not* constrained

Verified absent from all four authored SDCs **and** from the generated `_syn.sdc`:

| Command | Status | Consequence |
|---|---|---|
| `set_driving_cell` | **absent** | primary inputs are driven by an ideal zero-impedance source with zero input transition — optimistic for the first stage of every input path |
| `set_load` | **absent** | primary outputs see zero external load — optimistic for the last stage of every output path |
| `set_input_transition` | **absent** | same as `set_driving_cell` |
| `set_case_analysis` | **absent** | no mode pin is pinned; in particular `SE` (scan enable) is a live functional input |
| `set_clock_latency` | absent from the SDC | but *injected at runtime* by `ccopt_design` — see §3.5 |
| `set_disable_timing` | absent | — |

*(Partly mitigated, inference:)* on a pad-ring top the "external driver" of an input port is a
bond wire and a board trace, and the IO cell itself is inside the design, so the missing
`set_driving_cell` is less damaging than it would be on a core-only block. It is still a real
optimism, and it should be closed before signoff with a board-level RC estimate.

Ports with **no** input or output delay at all:

| Port | Dir | Note |
|---|---|---|
| `SE` | in | scan enable; the `uPAD_SE_I` pad drives `soc_sys_scanenable`. `DFT 0`, so nothing uses it — but it is neither delayed nor case-analysed |
| `RMII_MDIO`, `RMII_MDC` | inout / out | **the entire PHY management interface is unconstrained.** MDC is a real output clock (typically 2.5 MHz) with no `create_clock` and no `set_output_delay` |
| `I2C_SCL`, `I2C_SDA` | inout | the D2D sideband; unconstrained |
| `QSPI_nCS` | out | chip select; unconstrained (the data pins are) |
| `HOSTIO4_P1[6:0]` | inout | input side constrained (`constraints.sdc:92`), **output side not** |

Per `TCRcom/set_input_delay.html` these are timed with a zero external budget, so the tool
reports them clean regardless of the real board timing. `RMII_MDC` / `RMII_MDIO` is the one
worth acting on: MDIO is a genuine synchronous serial interface with a real setup/hold spec.

---

## 5. Constraint review — what is dead, and what is suspicious

The manual gives the rule that decides all of this:

> "Path Exception Priorities. The following are the path exception priorities if a path in the
> design matches more than one path exception: `set_false_path`, `set_min_delay`,
> `set_max_delay`, `set_multicycle_path`."
>
> — `UGcom/Timing_Analysis.html`

`set_false_path` wins over everything. And `set_clock_groups -asynchronous` *is* a false path
between the groups, and additionally **drops** competing explicit false paths
(`TCRcom/set_clock_groups.html`, quoted in §4.1). `constraints.sdc:126` runs **after** all
three sourced files (lines 82–86), so it has the last word on every clock pair.

### 5.1 The SWD exception block is superseded — and this is intentional but undocumented

`constraints.sdc:131` puts `$SWDCLK` in its own asynchronous group. That makes every
`clk ↔ swdclk` path a false path, which supersedes:

- lines 66–67, the ±0.1 ns inter-clock uncertainty (no path left to apply it to),
- lines 70–73, the four `set_multicycle_path` (false path outranks multicycle),
- line 76, the `set_false_path -hold` (redundant, and explicitly *dropped* per the manual).

All six statements survive into `_syn.sdc` (lines 144–147, 950–957) and all six are inert.

**They are also directly contradicted by a comment in another file.**
`ethernet_constraints.sdc:54-55` states:

```
# (CLK<->SWDCLK is intentionally NOT grouped so the existing SWD multicycle/false-path block
# above is preserved.)
```

That sentence was true when it was written. `constraints.sdc:126-131` — added later, and
below the `source` line — grouped them. Either the group is right and the SWD block should be
deleted, or the SWD block is right and `swdclk` should be merged into the `$EXTCLK` group.
**Both cannot be.** *(Recommendation: the group is right — SWD genuinely is asynchronous — so
delete lines 66–76 and correct the comment.)*

### 5.2 The ethernet CDC work is superseded too — including CDC 3, which was the good part

`constraints.sdc:130` puts `{rmii_ref_clk mii_rx_clk mii_tx_clk}` in a group asynchronous to
`{clk, QSPI_SCLK, QSPI_SCLK_o}`. Consequences, in order of severity:

1. **CDC 3's multicycle is dead.** `set_multicycle_path 2 -setup -end -from
   [get_cells .../last_push_flags_mrx_reg[*]] -to [get_clocks clk]` (lines 84–85) describes a
   `mii_rx → clk` path. The group makes that pair a false path, and false path outranks
   multicycle. The `last_push_flags` bus is **not timed at all**.
2. **CDC 2's seven targeted false paths are redundant.** Their whole purpose (lines 59–61) was
   to cut only the synchroniser first stages *"so the last_push_flags MCP (CDC 3) survives on
   the same clock pair."* With the group in place there is no pair to survive on.
3. **CDC 1's two blanket false paths are dropped** by the group, per the manual.

The file itself anticipated this outcome — as an *option*, not as the current state
(lines 87–94):

```
# NOTE (max-robustness alternative): if a name-free, guaranteed-complete cut of
# the mii_rx->CLK boundary is preferred over the verified last_push_flags MCP,
# replace CDC 2+3 with a single async clock group ...
# That is safe (last_push_flags is held stable for a whole frame vs a ~2-cycle
# toggle resync) but converts last_push_flags from a timed MCP into a false path.
```

**That alternative has already been taken, by a line in a different file, without anyone
recording the decision.** The file's own safety argument ("held stable for a whole frame")
says the outcome is acceptable — this is a bookkeeping defect, not a silicon risk. But 34
lines of carefully RTL-verified constraint are doing nothing, and the next person to read
`ethernet_constraints.sdc` will believe otherwise.

**How to confirm on a live database (one command, no re-run):**
```tcl
report_path_exceptions -ignored
```
`UGcom/Timing_Analysis.html`: *"To check for ignored path exceptions, use the
`report_path_exceptions -ignored` command."* This is not currently in the flow. It should be —
it costs seconds and it is the only thing that would have caught §5.1 and §5.2.

### 5.3 `rmii_ref_clk` still carries the un-split hold uncertainty

`ethernet_constraints.sdc:24`:

```tcl
24  set_clock_uncertainty $CLK_ERROR [get_clocks rmii_ref_clk]
```

No `-setup`, no `-hold`. Per `TCRcom/set_clock_uncertainty.html`, *"Default: Applies to both
setup and hold check."* The generated SDC confirms it, and the contrast with the fixed clocks
is stark (`_syn.sdc:950-955`):

```
950 set_clock_uncertainty -setup 0.35 [get_clocks clk]
951 set_clock_uncertainty -hold  0.05 [get_clocks clk]
952 set_clock_uncertainty -setup 0.35 [get_clocks swdclk]
953 set_clock_uncertainty -hold  0.05 [get_clocks swdclk]
954 set_clock_uncertainty -setup 0.35 [get_clocks rmii_ref_clk]
955 set_clock_uncertainty -hold  0.35 [get_clocks rmii_ref_clk]   <-- 7x the others
```

> **FINDING — this is the exact bug `constraints.sdc:50-60` documents and fixes, left
> un-fixed in the ethernet file.** Every RMII hold path is charged **0.35 ns** of
> oscillator-jitter margin instead of 0.05 ns. The 0.35 ns value is additionally borrowed from
> a *different* oscillator ("CDCM61001 … at 250MHz") than the 50 MHz RMII reference.
>
> This matters more than it looks. `cts_setup.tcl:54-57` records that when the source-latency
> defect was partially repaired, *"the worst path relocated to `rmii_ref_clk`"*. The RMII/MII
> domain is where the remaining hold pressure is, and 0.30 ns of it is this line.
>
> **Fix:** split it the same way `constraints.sdc:61-64` does. This is a signoff-margin change
> — do it deliberately, not casually.

Also note: `mii_rx_clk`, `mii_tx_clk`, `QSPI_SCLK`, `QSPI_SCLK_o`, `D2D_TX_CLK_0` and
`D2D_RX_CLK_0` have **no uncertainty at all** — only three of the nine clocks are covered.
Generated clocks do not inherit uncertainty from their master. `D2D_RX_CLK_0` is the one to
care about: it is the far die's clock, arriving over a package, with zero jitter modelled.

### 5.4 `D2D_TX_CLK_0` is grouped asynchronous to its own master

This one is a genuine risk, not bookkeeping.

**Fact 1.** `user_ref_clk` is aliased onto the `sys_fclk` pad, i.e. onto `CLK`
(`nanosoc_eth_chiplet_pads.v:137-141, 244-250`; and `constraints.sdc:109-111` says so).

**Fact 2.** Innovus resolved `D2D_TX_CLK_0`'s master accordingly — from
`reports/timing_summary_04_route.rep`:

```
Using master clock 'clk' for generated clock 'D2D_TX_CLK_0' in view 'default_analysis_view_setup'
```

**Fact 3.** `constraints.sdc:127-128` places `clk` and `D2D_TX_CLK_0` in **different**
asynchronous groups, and `TCRcom/set_clock_groups.html` says asynchronous groups are treated
"as false paths for timing analysis".

**Fact 4.** `tidelink_constraints.sdc:8` constrains the TX data against `D2D_TX_CLK_0`:
`set_output_delay 0.8 -clock [get_clocks "D2D_TX_CLK_0"] [get_ports {TL_TX[*]}]`. The
launching registers are in the `clk` domain (`clk` is the only declared clock reaching the
Wlink TX logic — `reports/probe_clk_summary.rpt` shows `u_..._u_tidelink/.../u_wlink/phy_gpio/
gpiotx_0_hs_clk_gated_wcg_latch_o_q_reg/EN` under `Clock: clk`).

> **FINDING (inference from facts 1–4, flagged for verification).** Launch clock = `clk`,
> capture reference = `D2D_TX_CLK_0`, different asynchronous groups ⇒ **the `TL_TX[*]` output
> timing check is a false path and is not being enforced.** The `set_output_delay 0.8` on the
> D2D transmit bus — the timing that determines whether the far die can sample this die's data
> — has no effect.
>
> The comment at `constraints.sdc:109-111` reasons about the *opposite* concern (that aliasing
> makes an internal crossing synchronous) and concludes *"the `$EXTCLK` <-> D2D_TX cut is
> REAL."* Internally that may be true. For the **output path** it is the wrong call: an output
> clock generated from `clk` must be in `clk`'s group for its own I/O check to survive. The
> QSPI block (§4.2) gets this right — `QSPI_SCLK_o` sits in the `clk` group and its
> `set_output_delay` is live.
>
> **Verify before acting** (one command on the existing post-route DB, no re-run needed):
> ```tcl
> report_timing -to [get_ports TL_TX[0]] -late
> report_path_exceptions -ignored
> ```
> If the first reports "no path", the finding is confirmed. **Fix:** move `D2D_TX_CLK_0` into
> the `$EXTCLK` group on `constraints.sdc:127`, leaving `D2D_RX_CLK_0` (line 129) where it is
> — the RX clock genuinely comes from the far die and is genuinely asynchronous.

For contrast, the two neighbouring I/O checks are fine: `RMII_TXD` launches on `mii_tx_clk`
and is referenced to `rmii_ref_clk`, same group (line 130) ⇒ live. `TL_RX[*]` is captured by
registers on `D2D_RX_CLK_0` and referenced to `D2D_RX_CLK_0`, same clock ⇒ live.

---

## 6. Power intent: UPF, CPF and the generated files

### 6.1 What power intent is

A netlist says which wires connect. It does not say *which supply* each cell runs from, what
voltage that supply is at, which supplies can be switched off, or where isolation and
level-shifting cells are needed. **Power intent** is a separate file that says all of that,
and the implementation tools consume it to (a) connect PG pins, (b) place special cells, and
(c) know which library to use for which region.

Two formats: **CPF** (Cadence Common Power Format) and **IEEE 1801 / UPF**. Innovus reads both
— `read_power_intent` takes `{-cpf | -1801 | -msv_db}` (`TCRcom/read_power_intent.html`) — and
`commit_power_intent` then "commits IEEE1801 power intent specifications for the design for
use in verification and implementation of the structure and behavior of the design in context
of a given power management architecture" (`TCRcom/commit_power_intent.html`).

This design has **one always-on power domain**. `docs/POWER_DOMAINS.md` explains why (the D2D
link cannot power down unilaterally, and `role_locked` couples link reset to core reset), and
records the split-domain design as deferred. So there are no switches, no isolation cells, no
retention — the power intent here is doing exactly two jobs: **name the supply nets** and
**connect macro/pad PG pins**.

### 6.2 `nanosoc_eth_chiplet_pads.upf` annotated

Source: [`ASIC/genus-innovus/inputs/nanosoc_eth_chiplet_pads.upf`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/inputs/nanosoc_eth_chiplet_pads.upf).
Read by Genus at `1_synthesis.tcl:31`:
`read_power_intent -module $block_name ../inputs/${block_name}.upf`.

#### Line 1 — the top name is wrong

```tcl
1  set_design_top nanosoc_chip_pads
```

`set_design_top` "specifies the design top module" (`IEEE1801user/set_design_top.html`). **The
design top is `nanosoc_eth_chiplet_pads`**, not `nanosoc_chip_pads` (`BLOCK` in
`ASIC/genus-innovus/Makefile:35`, and the module in
`ASIC/tech_wrappers/tsmc65/nanosoc_eth_chiplet_pads.v`). It works only because
`read_power_intent -module $block_name` overrides the scope explicitly. Genus dutifully
round-trips the wrong name into `outputs/..._gate2.upf:7`, while the CPF writer emits the
*correct* one (`_gate1.cpf:11 set_design nanosoc_eth_chiplet_pads`). Cosmetic today; a trap
the moment anyone reads `_gate2.upf` standalone.

#### Lines 7–21 — supply ports and nets

```tcl
 7  create_supply_port VDD
 8  create_supply_net  VDD
 9  connect_supply_net VDD -ports VDD
11  create_supply_port VSS   / 12 create_supply_net VSS   / 13 connect_supply_net VSS -ports VSS
15  create_supply_port VDDIO / 16 create_supply_net VDDIO / 17 connect_supply_net VDDIO -ports VDDIO
19  create_supply_port VSSIO / 20 create_supply_net VSSIO / 21 connect_supply_net VSSIO -ports VSSIO
```

`create_supply_port` — "Create a supply port on an instance in the active scope"
(`IEEE1801user/create_supply_port.html`). `create_supply_net` — "Create a supply net in the
active scope or in the scope of the specified domain"
(`IEEE1801user/create_supply_net.html`). `connect_supply_net` — "Connect a supply net to one
or more ports" (`IEEE1801user/connect_supply_net.html`). All three are listed as supported (S)
in both Genus and Innovus in the cross-platform tables on those pages.

Four supplies: **`VDD`/`VSS`** (1.2 V core) and **`VDDIO`/`VSSIO`** (3.3 V IO). This is the
canonical port→net→connect triple that makes the supply visible at the design boundary.

> Note: `config.tcl:125` declares `set power_nets {VDD VDDACC VDDIO}` — a **third** power net,
> `VDDACC`, that appears nowhere in the UPF, nowhere in the CPF, and nowhere in the netlist.
> It is a leftover from the accelerator-domain variant of this SoC. Harmless (`init_power_nets`
> for a net with no pins is a no-op) but it makes `config.tcl` disagree with the power intent.

#### Lines 26–32 — supply sets and the one power domain

```tcl
26  create_supply_set SS_TOP -function {power VDD}   -function {ground VSS}
27  create_supply_set SS_IO  -function {power VDDIO} -function {ground VSSIO}
32  create_power_domain PD_TOP -include_scope -supply {primary SS_TOP}
```

`create_supply_set` — "Create a supply set in the active scope"
(`IEEE1801user/create_supply_set.html`), a 1801-2.0 construct that bundles the power and
ground functions of one rail so a domain can reference the pair by one name.

`create_power_domain` — "Define a collection of design elements that share the same primary
power supply" (`IEEE1801user/create_power_domain.html`). Options:

- **`-include_scope`** — everything in the current scope belongs to the domain. The
  cross-platform table on that page marks it *"deprecated in IEEE 1801-2013"* but supported (S)
  by both Genus and Innovus. It is the right choice for a single-domain chip.
- **`-supply {primary SS_TOP}`** — 1801-2.0 form, supported (S) by Genus and Innovus. The
  domain's primary supply is the core rail.

`SS_IO` is created but **never bound to a domain** — the IO rail exists as a supply set with no
power domain of its own. That is deliberate for an abutted pad ring (the pads are physically
on their own rail but logically in `PD_TOP`), and it is why the IO supplies need the
`connect_global_net` treatment described in
[04 — Power plan §2](../04-power-plan.md#2-global-net-connections).

#### Lines 39–95 — macro and pad PG connections, most of which do not exist

```tcl
39  connect_supply_net VDD -ports u_nanosoc_multicore_soc/u_qspi_flash_0/.../data_ram_0_word_0_i/VDD
...
63  connect_supply_net VDD -ports u_nanosoc_eth_chiplet_chip/u_soc/u_soc/u_chip_core/u_region_bootrom_0/u_bootrom/u_rom_via/VDDE
...
92  connect_supply_net VDD   -ports {uPAD_VDD_*/VDD}
93  connect_supply_net VDDIO -ports {uPAD_VDDIO_*/VDDPST}
94  connect_supply_net VSS   -ports {uPAD_VSS_*/VSS}
95  connect_supply_net VSSIO -ports {uPAD_VSSIO_*/VSSPST}
```

Two different hierarchy roots appear here, and **only one of them exists**:

- `u_nanosoc_eth_chiplet_chip/...` (lines 63–69) — correct. The wrapper instantiates
  `nanosoc_eth_chiplet_chip u_nanosoc_eth_chiplet_chip` at
  `nanosoc_eth_chiplet_pads.v:140`.
- `u_nanosoc_multicore_soc/...` (lines 39–61 and 71–90, **24 statements**) — **does not
  exist.** `grep -c u_nanosoc_multicore_soc outputs/nanosoc_eth_chiplet_pads_gate_power.v`
  returns **0**. It is a stale root from the predecessor `nanosoc_chip_pads` design.

This is not speculation — `check_cpf` reports it as an error class
(`baseline_2026-08-05/logs/syn_cpf_check.log:1-2`):

```
1801_REF_OBJ_NOT_FOUND: Referenced power intent or design object does not exist
    Severity: Error      Occurrence: 34
    1: ../inputs/nanosoc_eth_chiplet_pads.upf:89 connect_supply_net: Supply port
       'u_nanosoc_multicore_soc/u_cpu_ss_1/u_region_dmem_0/u_mem/u_sram/gen_rf_32k.u_rf_sp_hdf/VDD'
       does not exist.
```

and the regenerated UPF proves the statements were dropped: `outputs/..._gate2.upf` lines
49–65 contain **only** the two bootrom connections and the pad connections — every SRAM,
cache-RAM and register-file line is gone.

> **FINDING — every SRAM/cache/register-file PG connection in the UPF is silently
> non-functional.** 24 of the 26 macro `connect_supply_net` statements name a hierarchy that
> does not exist in this design. Genus reported 34 errors and continued.
>
> **The macros are still powered**, by two other mechanisms: the generated CPF's
> `create_global_connection -net VDD -pins VDD` (in the *input* CPF; see §6.3) and, decisively,
> `power_plan.tcl`'s `connect_global_net VDD -type pg_pin -pin_base_name VDD -inst_base_name *`
> ([04 — Power plan §2](../04-power-plan.md#2-global-net-connections)). So this is a latent
> defect, not a dead chip. But nothing *checks* that the fallback covered every macro, and the
> UPF is actively lying about what it connects.
>
> Corroborating warning from the same run
> (`baseline_2026-08-05/logs/syn_pow_check.log:1-2`):
> `1801_SUPPLY_CSN_MISSING_FOR_MACRO … Severity: Warning  Occurrence: 38` — 38 macro supply
> pins with no explicit `connect_supply_net`, listed by full (correct) hierarchical name.
>
> **Fix:** replace the `u_nanosoc_multicore_soc/` prefix with `u_nanosoc_eth_chiplet_chip/…`
> and re-derive the paths from the warning list in `syn_pow_check.log`, or delete the 24 lines
> and rely on the global connection deliberately rather than accidentally.

Lines 92–95 use wildcards and *are* resolved (Genus expands them into explicit instance lists
in `_gate2.upf:67-77`). But they hit a second problem — from
`baseline_2026-08-05/logs/syn_pow_check.log:331-333`:

```
PG_CONN_SUPPLY_PIN_CSN_CONFLICT: Instance supply pin connection conflicts with the power
intent supply connection setting
    Severity: Error      Occurrence: 34
    1: Supply port 'uPAD_VDDIO_B_0/VDDPST' is connected to supply net 'UNCONNECTED2676',
       but power intent specifies it should be connected to 'VDDIO'
```

The supply pads are instantiated with **empty port lists** in the wrapper (e.g.
`PVSS2DGZ_G uPAD_VSSIO_R_1();`), so the netlist leaves `VDDPST`/`VSSPST` unconnected while the
UPF asserts `VDDIO`/`VSSIO`. This is the netlist-side half of the `VDDIO`/`VSSIO` story that
[04 — Power plan §2.1](../04-power-plan.md) and
[16 — Open defects §4](../16-open-defects.md) cover from the LEF and routing side.

#### Lines 100–128 — power states and the PST

```tcl
100  add_port_state VSS   -state {ON_SLOW 0.0}   ... (VSS, VSSIO: 0.0 in all three states)
107  add_port_state VDD   -state {ON_SLOW 1.08}
108  add_port_state VDD   -state {ON_TYP  1.20}
109  add_port_state VDD   -state {ON_FAST 1.32}
110  add_port_state VDDIO -state {ON_SLOW 2.97}
111  add_port_state VDDIO -state {ON_TYP  3.30}
112  add_port_state VDDIO -state {ON_FAST 3.63}
114  create_pst top_pst -supplies { VSS VSSIO VDD VDDIO }
126  add_pst_state all_on_slow -pst top_pst -state {ON_SLOW ON_SLOW ON_SLOW ON_SLOW}
127  add_pst_state all_on_typ  -pst top_pst -state {ON_TYP  ON_TYP  ON_TYP  ON_TYP }
128  add_pst_state all_on_fast -pst top_pst -state {ON_FAST ON_FAST ON_FAST ON_FAST}
```

All three commands are **legacy** in current 1801 and the manual says so on each page:
`add_port_state` — *"This command is legacy in the latest IEEE 1801 standard, and is included
for backward compatibility. Description: Specify a state for a UPF supply port."*
(`IEEE1801user/add_port_state__legacy_.html`); `create_pst` — *"Define a name for the power
state table (PST)"* (`IEEE1801user/create_pst__legacy_.html`); `add_pst_state` — *"Specify a
power state for each supply net defined in the power state table (PST)"*
(`IEEE1801user/add_pst_state__legacy_.html`). The modern equivalents are `add_power_state` /
`add_supply_state`, both present in the same manual. Legacy is supported, but a rewrite would
be a reasonable cleanup.

The three PST rows are the three corners: **slow = 1.08 V, typ = 1.20 V, fast = 1.32 V** on the
core — exactly matching `default_libset_max` / `typical_libset` / `default_libset_min` in the
`.mmmc` (§3.2). The column comment block at lines 121–125 is an ASCII diagram of the supply
ordering in `create_pst`, which is worth keeping: `add_pst_state`'s `-state` list is
**positional** and matches `create_pst -supplies` order.

Minor mismatch: the IO states are 2.97 / 3.30 / 3.63 V (±10 % of 3.3), while the IO libraries
are characterised at **3.0 / 3.3 / 3.6 V**. The slow state is below and the fast state above
what the libraries cover. It is inert here — no analysis view uses `-power_modes` (§3.7), so
the PST never drives delay calculation — but it would matter the moment anyone enables
voltage-aware analysis.

### 6.3 `nanosoc_chip_pads.cpf` — a dead file

Source: [`ASIC/genus-innovus/inputs/nanosoc_chip_pads.cpf`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/inputs/nanosoc_chip_pads.cpf), 39 lines.

**Nothing in the flow reads it.** `grep -rn nanosoc_chip_pads.cpf` over the Tcl scripts, the
Makefile and `common.mk` returns nothing; `2_pnr_setup.tcl:40` reads
`$OUT_DIR/${block_name}_gate1.cpf` — the *generated* CPF — and Genus reads the UPF, not this.
The filename is also the old design's (`nanosoc_chip_pads`, cf. §6.2 line 1).

It is still worth reading, because **it is the hand-written statement of what the generated CPF
was supposed to contain**, and it is where the `cpf-patch` repair came from:

```tcl
 5  set_cpf_version 1.1
 6  set_design nanosoc_chip_pads
11  create_power_domain -name PD_TOP -default
13  create_nominal_condition -name nom -voltage 1.08
15  create_power_mode -name PM -domain_conditions {PD_TOP@nom} -default
21  create_ground_nets -nets {VSS VSSIO}
22  create_power_nets  -nets {VDD VDDIO}
24  update_power_domain -name PD_TOP -primary_power_net VDD -primary_ground_net VSS
30  create_global_connection -net VSS -pins VSS
31  create_global_connection -net VDD -pins VDD
33  create_global_connection -net VSS -pins VSSE
34  create_global_connection -net VDD -pins VDDE
36  create_global_connection -net VSSIO -pins VSSPST
37  create_global_connection -net VDDIO -pins VDDPST
39  end_design
```

Per the CPF reference (`cpf_ref/reference.html`):

| Line | Command | Manual |
|---|---|---|
| 11 | `create_power_domain -default` | "Creates a power domain and specifies the instances and boundary ports and pins that belong to this power domain… **You must define at least one power domain for a design, and one (and only one) power domain must be specified as the default power domain.**" `-default`: "Identifies the specified domain as the default power domain. All instances of the design that were not associated with a specific power domain belong to the default power domain." |
| 13 | `create_nominal_condition` | "Creates a nominal operating condition with the specified voltage… A power domain is switched off if the voltage of its associated nominal condition is 0." |
| 21/22 | `create_ground_nets` / `create_power_nets` | "Specifies or creates a list of ground nets. **Even if this net exists in the RTL or the netlist, it still must be declared through this command if the net is referenced in other CPF commands.**" |
| 24 | `update_power_domain -primary_power_net/-primary_ground_net` | "Specifies implementation aspects of the specified power domain… The primary power and ground pins of all instances in a power domain will be connected to the primary, or equivalent power and ground nets of the domain." |
| 30–37 | `create_global_connection` | "Specifies how to connect a global net to the specified pins… `-net`: **If the specified net does not exist in the design, you must have defined it with a `create_bias_net`, `create_power_nets` or `create_ground_nets` command.**" `-pins`: "Specifies the name of the LEF pin to connect to the specified global net." |

Note the pin names: `VDD`/`VSS` for standard cells, `VDDE`/`VSSE` for the ROM macros,
`VDDPST`/`VSSPST` for the IO pads — the same three-way split that
[04 — Power plan §2](../04-power-plan.md#2-global-net-connections) explains for
`connect_global_net -pin_base_name`.

Line 13's single nominal condition at **1.08 V** (the *slow* voltage) is the only voltage the
CPF knows about, versus the UPF's three-state PST. If a future change binds analysis views to
power modes (`create_analysis_view -power_modes`), this would peg every view at 1.08 V.

### 6.4 The generated `_gate2.upf` and `_gate1.cpf`

`1_synthesis.tcl:76-77` writes both, from the post-synthesis database:

```tcl
76  write_power_intent -cpf -design $block_name -base_name $OUT_DIR/${block_name}_gate
77  write_power_intent      -design $block_name -base_name $OUT_DIR/${block_name}_gate
```

**Producer → consumer, precisely:**

```
inputs/nanosoc_eth_chiplet_pads.upf      (authored, IEEE 1801)
        |
        v  read_power_intent -module   (1_synthesis.tcl:31)
      Genus  --> apply_power_intent, check_cpf, commit_power_intent   (:37-39)
        |
        +--> write_power_intent      --> outputs/..._gate2.upf   (1801 round-trip; UNUSED)
        |
        +--> write_power_intent -cpf --> outputs/..._gate1.cpf   (translated to CPF)
                                              |
                                              v  make cpf-patch  (Makefile:104-114)
                                          patched CPF
                                              |
                                              v  read_power_intent -cpf  (2_pnr_setup.tcl:40)
                                            Innovus --> commit_power_intent (:42)
```

**`_gate2.upf`** (132 lines) is a faithful 1801 round-trip of what Genus actually resolved: the
four supply ports/nets, both supply sets, `PD_TOP`, the surviving `connect_supply_net`
statements with wildcards expanded, and the full PST. It is **not read by anything** in this
flow. Its value is diagnostic — comparing it against the input UPF is the fastest way to see
which statements were dropped (§6.2). Note the empty marker block at the end:

```
130  ## BEGIN GENERATED connect_supply_net ##
132  ## END GENERATED connect_supply_net ##
```

Genus emits this section for connections *it* inferred. It is empty, which is another way of
saying the macro PG connections came from nowhere.

**`_gate1.cpf`** is the file that matters, and as written by Genus it was almost empty. What it
contains **now** (21 lines, post-patch — lines 16, 17 and 19 are the patch):

```tcl
 7  set_cpf_version 2.0
 9  set_hierarchy_separator "/"
11  set_design nanosoc_eth_chiplet_pads
13  create_power_domain -name PD_TOP \
14       -default
16  create_ground_nets -nets VSS         <-- inserted by cpf-patch
17  create_power_nets -nets VDD          <-- inserted by cpf-patch
19  update_power_domain -name PD_TOP -primary_power_net VDD -primary_ground_net VSS   <-- inserted
21  end_design
```

Everything Genus itself wrote is lines 7–14 and 21. **No `VDDIO`, no `VSSIO`, no
`create_global_connection`, no power mode, no nominal condition.** The IO rails do not appear
in Innovus's power intent at all; they are established purely by `power_plan.tcl`'s
`connect_global_net`.

### 6.5 `IMPSP-5110` and the `cpf-patch` repair

#### What Genus could not translate

The Makefile states it (`ASIC/genus-innovus/Makefile:85-88`):

```
## `write_power_intent -cpf` cannot translate this design's UPF supply commands
## — the Genus log is full of "Unable to translate command 'create_supply_net'
## ... from 1801 to CPF format" — and emits a CPF whose entire content is
## `create_power_domain -name PD_TOP -default`. No power net, no ground net.
```

The mechanism is a direct consequence of §6.2. In 1801 the supplies are `create_supply_net` /
`create_supply_set` objects; in CPF they are `create_power_nets` / `create_ground_nets`
objects, and `update_power_domain -primary_power_net` is what binds them to a domain. The
translator did not make that mapping for this file. **I could not find a manual page in the
installed Genus documentation that describes this limitation** — `write_power_intent` appears
in `genus_comref/lps.html` but the 1801→CPF translation restrictions are not documented there,
and there is no message page for the "Unable to translate command" text in
`genus/doc/genus_messages/`. The evidence is the run log and the emitted file.

#### `IMPSP-5110`, quoted properly

**`IMPSP-5110` has no page in the installed Innovus Error Message Reference.**
`$INNOVUS_HOME/doc/innovuserrmsg/` contains 1,992 pages including `IMPSP-5101.html`,
`IMPSP-5106.html` and `IMPSP-5113.html`, but **not** `IMPSP-5110.html`. Do not go looking for
it; it is not there.

It *is* in the tool's own message database. From
`$INNOVUS_HOME/share/cdssetup/errormessages/innovus/spEms.msg`, line 1311, verbatim:

```
5110 "No supply-net names for Power Domain '%s'.\n"
```

That is the whole definition — a format string and nothing else. Messages either side of it in
the same file carry multi-paragraph `.br`/`.sp` help text (5106, 5109, 5113 all do), and those
are exactly the ones that got HTML pages. 5110 has no help text, so it has no page. That is
the complete explanation for its absence.

The surrounding block identifies the message family precisely — these are the
special-placement commands:

```
5100 "The design must be floorplanned."
5101 "The design must be completely placed before adding filler cell(s)."
5104 "Region (%d, %d) had no legal location for tie-off cell '%s'."
5105 "Could not place %d of requested %d tie-off cells."
5106 "AddEndCap cannot place end cap cells at the ends of the site rows. ..."
5108 "Added fillers still have DRC violations."
5110 "No supply-net names for Power Domain '%s'."
5113 "Maximum of only two tie-cells can only be provided."
5119 "AddEndCap is unable to add %s-cap cell (%s) at ..."
```

Filler cells, tie-off cells, end caps. Every command in that family needs to know which supply
net the cells it places should connect to — and a `create_power_domain` with no
`-primary_power_net` cannot tell it.

#### What it cost, measured

[04 — Power plan §1](../04-power-plan.md#1-the-big-trap-pd_top-has-no-supply-nets-and-the-die-ships-unfilled)
documents the filler consequence: `For 0 new insts`, 95,568 free-site gaps (~5.9 % of the
core), no base-layer density fill, no `ANTENNA` diodes, and a GDSII that streamed anyway.

**A second consequence is not recorded there — the tie cells failed too.** From
`baseline_2026-08-05/logs/pnr_stages.log:2395-2400`:

```
@file 4: add_tieoffs -lib_cell {TIEL TIEH} -prefix LTIE
Options: No distance constraint, Max Fan-out = 10.
**ERROR: (IMPSP-5110):	No supply-net names for Power Domain 'PD_TOP'.
INFO: Total Number of Tie Cells (TIEL) placed: 0 for power domain PD_TOP
**ERROR: (IMPSP-5110):	No supply-net names for Power Domain 'PD_TOP'.
INFO: Total Number of Tie Cells (TIEH) placed: 0 for power domain PD_TOP
```

Zero tie-high and zero tie-low cells. After the patch, the same step in
`logs/pnr_run_ocvfix.log:2636,2638` reports:

```
INFO: Total Number of Tie Cells (TIEL) placed: 28 for power domain PD_TOP
INFO: Total Number of Tie Cells (TIEH) placed: 17 for power domain PD_TOP
```

45 tie cells that the broken run left as direct rail connections on gate inputs — a
reliability and antenna concern in its own right, and one that no report flagged.

#### The repair

`Makefile:104-114`, `make cpf-patch`, run automatically at the end of `make syn`
(`Makefile:123`). It greps for `create_power_nets` first (idempotent), fails loudly if the CPF
is missing or has no `end_design`, and otherwise `sed`-inserts the three CPF statements before
`end_design`. It is exactly what the 2026-07 operator typed by hand mid-session.

Why the repair belongs in the CPF and not in `power_plan.tcl`: `update_power_domain` in
**Innovus** is a different command from `update_power_domain` in **CPF**. The Innovus Common UI
version takes the domain positionally and its option set is floorplan geometry
(`core_to_*`, `row_*`, `gap_*`) — it has no `-primary_power_net`/`-primary_ground_net` at all,
and calling it that way yields `IMPTCM-162` plus a usage string (verified, recorded in
`Makefile:96-98`). The `-primary_power_net` form is the **CPF** command documented in
`cpf_ref/reference.html` (quoted in §6.3). So the file is what has to be repaired.

#### Verifying it stayed fixed

```sh
grep -A2 create_power_nets ASIC/genus-innovus/outputs/nanosoc_eth_chiplet_pads_gate1.cpf
grep -c IMPSP-5110 ASIC/genus-innovus/logs/pnr_run_*.log     # expect 0 real hits
grep "new insts"   ASIC/genus-innovus/logs/pnr_run_*.log     # expect a large count
grep "Total Number of Tie Cells" ASIC/genus-innovus/logs/pnr_run_*.log   # expect non-zero
```

The current run has **one** `IMPSP-5110` string in its log
(`logs/pnr_run_ocvfix.log:1439`) and it is an echoed comment from a sourced script, not an
error. `grep -c` alone will mislead you; check the line.

### 6.6 What `check_cpf` already told us

`1_synthesis.tcl:38` runs `check_cpf -detail -license lpgxl > $LOG_DIR/syn_cpf_check.log` and
`:44` runs `check_power_structure -detail > $LOG_DIR/syn_pow_check.log`. **Nothing in the flow
reads either log or gates on it.** The 2026-08-05 run's summary:

| Class | Severity | Count | Meaning |
|---|---|---|---|
| `1801_REF_OBJ_NOT_FOUND` | **Error** | 34 | §6.2 — the stale `u_nanosoc_multicore_soc/` hierarchy |
| `PG_CONN_SUPPLY_PIN_CSN_CONFLICT` | **Error** | 34 | §6.2 — supply pads tied to `UNCONNECTED*` in the netlist while the UPF asserts `VDDIO`/`VSSIO` |
| `1801_LIB_NO_PG_PIN` | Error | 54 / 9 | library cells with no PG pin — the TSMC IO cells, cf. [04 §2.1](../04-power-plan.md) |
| `STRUCT_UNDRIVEN_PIN_MACRO` | Error | 2 / 36 | undriven macro inputs — includes the QSPI tag-RAM `GWEN` defect, [16 §3](../16-open-defects.md) |
| `1801_SUPPLY_CSN_MISSING_FOR_MACRO` | Warning | 38 | macro supply pins with no explicit connection (the other half of §6.2) |
| `1801_MACRO_PORT_ATTR_MISSING` | Warning | 274 | macro ports missing a required 1801 attribute |
| `1801_LIB_MISSING_LP_CELL` | Error | 1 | no low-power cells in the libraries — expected, there are no switches or isolation cells |

> **Recommendation.** Two of these classes (34 + 34 errors) are real defects this page has
> traced to specific lines. A `grep -c 'Severity: Error'` gate on `syn_cpf_check.log` and
> `syn_pow_check.log` in the `syn` target would have surfaced both at synthesis time instead of
> three documents later. The Makefile already uses exactly this pattern for the netlist check
> (`Makefile:124-128`).

---

## 7. If you change X, you must also change Y

### Changing the system clock frequency

`CLK_PERIOD` (`ASIC/common.mk:159`, default 10.0) is an **environment variable read by Genus
only**. Innovus never sees it.

1. **Re-run synthesis.** `write_sdc` bakes the resolved period into `_syn.sdc:15`. `make pnr`
   alone will re-use the old period. The Makefile's `syn` → `cpf-patch` → `pnr_all` chain does
   this correctly; a manual `read_db` resume does not.
2. **`SWDCLK_PERIOD` follows automatically** (`constraints.sdc:20`, `4*$EXTCLK_PERIOD`).
3. **`QSPI_SCLK` and `QSPI_SCLK_o` follow automatically** — they are `-divide_by` generated
   clocks off `CLK`.
4. **`D2D_RX_CLK_0` does *not* follow.** `tidelink_constraints.sdc:2` uses `$EXTCLK_PERIOD`,
   so it tracks in the file — but the far die's actual clock rate is a **system** decision, not
   a local one. Changing this die's core clock does not change the peer's transmit rate.
   Confirm against the peer before assuming they stay equal.
5. **`rmii_ref_clk` must NOT follow.** 20.0 ns is fixed by 100BASE-TX
   (`ethernet_constraints.sdc:18`). Leave it.
6. **Revisit `CLK_ERROR` (0.35) and `CLK_HOLD_ERROR` (0.05).** Both are absolute nanoseconds,
   not fractions of the period. At a faster clock they consume a larger fraction of the budget;
   at a slower clock they become over-conservative. The comment at `constraints.sdc:22-29`
   marks `CLK_HOLD_ERROR` as a signoff margin — treat it as one.
7. **Revisit the I/O delays.** `set_input_delay 0.1` (`constraints.sdc:90-93`) and
   `set_output_delay 0.8` (`tidelink_constraints.sdc:8`) are absolute too.
8. **Nothing in the `.mmmc` changes.** Library sets, RC corners and delay corners are
   frequency-independent.

### Adding a power domain

`docs/POWER_DOMAINS.md` is the design authority here — read its "Decision checklist" first.
The file-level consequences:

1. **UPF** (`inputs/nanosoc_eth_chiplet_pads.upf`): a second `create_power_domain` with
   `-elements`, its own supply set, `create_power_switch` if it is switchable, and
   `set_isolation` / `set_isolation_control` on every crossing
   `docs/POWER_DOMAINS.md` "the crossing" enumerates (the peer AHB path, the APB config path,
   `d2d_irq[15:0]`, the PHC servo signals, `link_active_o`). `-include_scope` on `PD_TOP`
   (line 32) becomes wrong — a second domain means `PD_TOP` needs explicit `-elements`.
2. **The libraries must contain isolation and level-shifter cells.** `check_cpf` already
   reports `1801_LIB_MISSING_LP_CELL` today; with a second domain that stops being expected.
   `1_synthesis.tcl:37-39` will need `define_isolation_cell` / `define_level_shifter_cell`
   equivalents.
3. **The `.mmmc` gains work.** `create_timing_condition` takes `-library_sets` per domain, and
   `update_delay_corner -power_domain <d> -library_set <s> -opcond <c>` is the documented way
   to give a domain its own PVT (`UGcom/Design_Import_and_Export_in_Stylus.html`, "Adding a
   Power Domain Definition to a Delay Calculation Corner"). If the domains run at different
   voltages you need a library set per (voltage × corner), not per corner.
4. **Analysis views must bind power modes.** `create_analysis_view -power_modes <list>`
   (`TCRcom/create_analysis_view.html`, *"The modes must exist in the power intent file"*) —
   currently unused (§3.7). Without it, a multi-voltage design is analysed at one voltage.
5. **The CPF translation problem gets worse, not better.** Genus already fails to translate
   `create_supply_net`; a design with switches, isolation rules and multiple modes has far more
   to translate. **Re-check `_gate1.cpf` by eye** — `cpf-patch` only repairs the specific
   missing-supply-net symptom, and it will report "OK: CPF already carries its supply nets"
   while the file is missing everything else. `power_plan.tcl`'s `PD_TOP` guard
   ([04 §1.5](../04-power-plan.md)) will need a sibling guard per domain.
6. **`power_plan.tcl` needs rings and stripes for the new rail**, and `floorplan.tcl` needs a
   `create_place_blockage`/domain region for it.

### Adding a clock

1. `create_clock` or `create_generated_clock` in the appropriate `inputs/*.sdc`.
2. **Add it to a group in `constraints.sdc:126-131`.** Generated clocks do **not** inherit
   their master's grouping (`TCRcom/set_clock_groups.html`). Missing this is silent.
3. Give it `set_clock_uncertainty -setup` **and** `-hold` — see §5.3 for what happens when you
   forget the qualifiers.
4. If it reaches a pad, give it `set_input_delay` or `set_output_delay`, and check the launch
   clock is in the same group as the reference clock (§5.4).
5. Re-run synthesis; check the new clock appears in `_syn.sdc` and in the
   `Using master clock '…' for generated clock '…'` lines of the P&R log.

### Editing an `inputs/*.sdc` without re-synthesising

Don't. Innovus reads `_syn.sdc` only. If you must patch constraints at P&R time, use
`set_interactive_constraint_modes` (`UGcom/Design_Import_and_Export_in_Stylus.html`:
*"Any constraints that you specify after this command will take effect immediately on all
active analysis views that are associated with these constraint modes"*) — and remember
`write_db` saves them into the mode's SDC, so the next resume inherits them.

---

## 8. Manual pages cited

Every page below was opened and read for this document. Paths are relative to
`$CDS_INSTALL/`.

**Innovus Stylus Common UI Text Command Reference** (`innovus/doc/TCRcom/`, product version
21.11):
`create_library_set.html`, `create_rc_corner.html`, `create_delay_corner.html`,
`create_timing_condition.html`, `create_constraint_mode.html`, `create_analysis_view.html`,
`set_analysis_view.html`, `read_mmmc.html`, `create_clock.html`,
`create_generated_clock.html`, `set_clock_uncertainty.html`, `set_input_delay.html`,
`set_output_delay.html`, `set_false_path.html`, `set_multicycle_path.html`,
`set_clock_groups.html`, `set_max_capacitance.html`, `set_max_fanout.html`,
`read_power_intent.html`, `commit_power_intent.html`

**Innovus Common UI User Guide** (`innovus/doc/UGcom/`):
`Design_Import_and_Export_in_Stylus.html` — "Configuring the Setup for Multi-Mode Multi-Corner
Analysis" (the MMMC chapter); `Timing_Analysis.html` — "Path Exception Priorities"

**CPF Reference** (`innovus/doc/cpf_ref/`): `reference.html` — `create_power_domain`,
`create_power_nets`, `create_ground_nets`, `update_power_domain`, `create_global_connection`,
`create_nominal_condition`, `create_power_switch_rule`

**IEEE 1801 Cross Platform Guide** (`innovus/doc/IEEE1801user/`, product version 21.10):
`set_design_top.html`, `create_supply_port.html`, `create_supply_net.html`,
`create_supply_set.html`, `connect_supply_net.html`, `create_power_domain.html`,
`add_port_state__legacy_.html`, `create_pst__legacy_.html`, `add_pst_state__legacy_.html`

**Innovus Error Message Reference** (`innovus/doc/innovuserrmsg/`):
`IMPSP-5101.html`, `IMPSP-5106.html`, `IMPSP-5113.html`.
**`IMPSP-5110.html` does not exist** — see §6.5.

**Innovus message database** (not documentation, but authoritative):
`innovus/share/cdssetup/errormessages/innovus/spEms.msg` — message 5110 and the surrounding
special-placement family.

**Not found in the installed manuals**, and stated as such in the text above:
a description of `write_power_intent -cpf`'s 1801→CPF translation limitations (searched
`genus/doc/genus_lowpower/`, `genus/doc/genus_comref/lps.html` and `genus/doc/genus_messages/`);
a help page for the Genus "Unable to translate command … from 1801 to CPF format" message.

---

**Legacy-UI note.** An earlier draft of this page was going to cite
`innovus/doc/innovusTCR/` and `innovus/doc/innovusUG/`. Those are the **legacy-UI** editions
and document a different option spelling (`-preRoute_cap` vs `-pre_route_cap`, `-T` vs
`-temperature`, `-library_set` vs `-timing_condition`). Since this flow runs `innovus -stylus`,
every citation here is from `TCRcom/`/`UGcom/`. If you find a legacy-UI citation anywhere in
`docs/tapeout/`, treat it as suspect.
