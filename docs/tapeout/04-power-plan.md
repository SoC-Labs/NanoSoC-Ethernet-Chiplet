# 04 — Power Plan

Block: `nanosoc_eth_chiplet_pads` · TSMC 65nm LP (9M_6X1Z1U) · Cadence Innovus 21.11-s130_1, STYLUS/Common-UI.

Source of truth: [`ASIC/genus-innovus/scripts/power_plan.tcl`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/power_plan.tcl).
Sourced by [`2_pnr_setup.tcl`](https://github.com/SoC-Labs/ASIC-Flow/blob/b19e7845448e641ea8353b19a59a77257907cb13/Cadence/2_pnr_setup.tcl) **immediately after**
[`floorplan.tcl`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/floorplan.tcl) and before `place_design`.
That order is mandatory — this file consumes `::PLACED_MACROS`, which floorplan publishes.

Prev: [03-floorplan](03-floorplan.md) · Next: [05-place-cts-route](05-place-cts-route.md) · Index: [00-index](00-index.md)

---

## At a glance

| Element | Setting | Line |
|---|---|---|
| Power domain | `PD_TOP` (single, default) — **must carry VDD/VSS, see §1** | guard at top |
| Core nets | `VDD` / `VSS` | `connect_global_net` |
| IO nets | `VDDIO` / `VSSIO`, pins `VDDPST` / `VSSPST` | `connect_global_net` |
| Core rings | M9 top/bottom, M8 left/right, width 12, spacing 4, offset 2 | `add_rings` |
| Ring band | `core_edge+2 .. core_edge+30` | derived |
| M8 stripes | vertical, width 3.6, **spacing 1.2**, set-to-set 60 | `add_stripes` |
| M9 stripes | horizontal, width 3.6, **spacing 3.05**, set-to-set 60 | `add_stripes` |
| M5 stripes | horizontal, width 1, spacing 0.5, set-to-set 15, over power domain | `add_stripes` |
| Endcaps | `DCAP4` both ends of every row | `add_endcaps` |
| Via stack | M1 → AP (rings capped at M9 top / M1 bottom) | `set_db add_rings_stacked_via_*` |

---

## 1. THE BIG TRAP — `PD_TOP` has no supply nets, and the die ships unfilled

**Read this before anything else in the file.** It is the defect that shipped a tapeout-blocking GDSII.

### 1.1 What goes wrong

Genus's `write_power_intent -cpf` **cannot translate this design's UPF supply commands**. The synthesis
log is full of:

```
Unable to translate command 'create_supply_net' ... from 1801 to CPF format
```

and the CPF it emits contains *only*:

```tcl
create_power_domain -name PD_TOP -default
```

No power net. No ground net. `2_pnr_setup.tcl` reads that file at line 40
(`read_power_intent -cpf $OUT_DIR/${block_name}_gate1.cpf`), and Innovus then fails **every filler
pass** with:

```
**ERROR: (IMPSP-5110):  No supply-net names for Power Domain 'PD_TOP'.
For 0 new insts, *** Applied 0 GNC rules.
```

### 1.2 Why it is dangerous rather than merely broken

**The flow completes.** It streams a GDSII. Nothing aborts.

The 2026-08-03 run (`baseline_2026-08-05/logs/pnr_stages.log`, lines 2397 / 2399 / 30716 / 30734 —
the `IMPSP-5110` errors and the `For 0 new insts`) shipped a GDSII with **zero filler cells** and
**95,568 free-site gaps** (~5.9 % of the core). That means:

- **no base-layer density fill** — a foundry density-rule failure waiting to happen, and
- **no `ANTENNA` diodes** — the antenna fixes `filler.tcl` is supposed to insert never went in.

Both are tapeout-blocking, and neither is visible unless you go looking.

The 2026-07 reference run hit the **identical** error and only survived it because the operator
hand-edited the CPF mid-session and re-ran `add_fillers` at the `@innovus` prompt. An unattended flow
has nobody to do that — which is exactly why the 2026-08 run failed where the reference "passed".

### 1.3 Why the fix is not an Innovus command

The obvious instinct is to call `update_power_domain` in `power_plan.tcl`. **It does not exist in that
form in this build.** Verified by running it: `update_power_domain` takes the domain **positionally**
and has **no `-primary_power_net` / `-primary_ground_net` options at all** — its entire option set is
floorplan geometry (`core_to_*`, `row_*`, `gap_*`). You get `IMPTCM-162` plus the usage string.

Those are **CPF statements**. The repair therefore belongs in the CPF file, before Innovus reads it.

### 1.4 The fix: the `cpf-patch` make target

`make syn` now patches `outputs/${BLOCK}_gate1.cpf` automatically — see the `cpf-patch` target in
[`ASIC/genus-innovus/Makefile`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/Makefile). It inserts, before `end_design`:

```tcl
create_ground_nets -nets VSS
create_power_nets  -nets VDD

update_power_domain -name PD_TOP -primary_power_net VDD -primary_ground_net VSS
```

which is precisely what the 2026-07 operator typed by hand. The target is **idempotent** (it greps for
`create_power_nets` first) and it fails loudly if the CPF is missing or has no `end_design`.

Current state of the CPF in the tree — **verified patched**:

```tcl
create_power_domain -name PD_TOP \
	 -default

create_ground_nets -nets VSS
create_power_nets -nets VDD

update_power_domain -name PD_TOP -primary_power_net VDD -primary_ground_net VSS

end_design
```

### 1.5 The guard in `power_plan.tcl`

```tcl
if {[llength [get_db power_domains PD_TOP]] == 0} {
    error "power_plan: no PD_TOP power domain — check read_power_intent"
}
```

This is the backstop, not the fix. If the CPF patch did not happen, **fail here with a clear reason**
rather than three hours later with a silently unfilled die. Cheap, and it converts the worst failure
mode in the flow from silent to immediate.

### 1.6 How to confirm it worked

```sh
# 1. the CPF itself
grep -A2 create_power_nets ASIC/genus-innovus/outputs/nanosoc_eth_chiplet_pads_gate1.cpf

# 2. no filler refusal anywhere in the run
grep -c IMPSP-5110 ASIC/genus-innovus/work/innovus.log*        # expect 0

# 3. fillers actually went in
grep "new insts" ASIC/genus-innovus/work/innovus.log*          # expect a large count
```

For reference: the fixed 2026-08-05 run reports **`For 150592 new insts`**; the broken 2026-08-03 run
reports `For 0 new insts`. The current (margin-70) run shows **zero** `IMPSP-5110`.
See also [06-fill-antenna-bondpads](06-fill-antenna-bondpads.md) and
[09-signoff-checklist](09-signoff-checklist.md).

---

## 2. Global net connections

```tcl
connect_global_net VDD   -type pg_pin -pin_base_name VDD    -inst_base_name *
connect_global_net VDDIO -type pg_pin -pin_base_name VDDPST -inst_base_name *
connect_global_net VSS   -type pg_pin -pin_base_name VSS    -inst_base_name *
connect_global_net VSSIO -type pg_pin -pin_base_name VSSPST -inst_base_name *
```

**`-pin_base_name` is the PIN name, not the NET name.** On the core cells the pins happen to be called
`VDD`/`VSS` so the distinction is invisible; on the IO pads the pins are `VDDPST`/`VSSPST` while the
nets are `VDDIO`/`VSSIO`. Getting this wrong is silent — the net simply stays empty.

### 2.1 The LEF override that makes this work at all

Correcting `-pin_base_name` is **necessary but not sufficient**. The TSMC IO supply pads declare their
supply pins as plain signal pins:

```lef
PIN VDDPST / DIRECTION INOUT ;      (PVDD2DGZ_G, PVDD2POC_G)
PIN VSSPST / DIRECTION INOUT ;      (PVSS2DGZ_G)
```

with no `USE POWER ;` / `USE GROUND ;`. The liberty agrees — they are `pin()` groups, not `pg_pin()`.
So `connect_global_net -type pg_pin` cannot match them and the rules fail with **`IMPDB-1221`**, even
with the correct pin names, against a design loaded from the real DB.

The consequence was stated by NanoRoute itself (**`NRDB-51`**): the `VDDIO`/`VSSIO` `SPECIAL_NET`s
stayed empty, so the router treated the IO supplies as **ordinary signal nets** and threaded them
around the periphery straight into the bond-pad M8/M9 blockages. Every `VDDIO`/`VSSIO` DRC record was
a "Regular Wire"; `VDD`/`VSS` had none. **76 violations.**

The fix is a **local override** of the IO driver LEF, wired up in
[`config.tcl`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/config.tcl):

```tcl
set IO_PAD_DRIVER_LEF $::env(NANOSOC_ETH_CHIPLET_HOME)/ASIC/tech_wrappers/tsmc65/local_overrides/tphn65lpgv2od3_sl_9lm.lef
```

Copied from the PDK with `USE POWER ;` / `USE GROUND ;` inserted after `DIRECTION` on exactly those
three pins — **three added lines, nothing else**. The shared PDK under `/tsmc65pdk` is read-only and is
not modified; `diff` against the source shows only the three additions. Re-copy and re-apply if the PDK
revs.

---

## 3. Core rings

```tcl
set_db add_rings_stacked_via_top_layer M9
set_db add_rings_stacked_via_bottom_layer M1

add_rings -nets {VDD VSS} -type core_rings -follow core \
    -layer {top M9 bottom M9 left M8 right M8} \
    -width {top 12 bottom 12 left 12 right 12} \
    -spacing {top 4 bottom 4 left 4 right 4} \
    -offset {top 2 bottom 2 left 2 right 2} \
    -center 0 -threshold 0 -jog_distance 0 -snap_wire_center_to_grid none
```

Layer choice follows the tech LEF preferred directions: **M9 is `DIRECTION HORIZONTAL`** (top/bottom
rings), **M8 is `DIRECTION VERTICAL`** (left/right rings).

The two-net stack occupies a **28 µm band starting 2 µm outside the core edge**:

```
offset 2  +  VDD 12  +  spacing 4  +  VSS 12   =  core_edge+2 .. core_edge+30
```

**This band is what collides with the staggered bond pads.** `add_rings` draws geometrically and does
not honour the `PAD70NU` `OBS`, so the clearance has to come from the floorplan margin. That is the
entire reason `CORE_TO_IO` is 70 rather than 50 — the full analysis lives in
[03-floorplan §2](03-floorplan.md#2-why-the-margin-is-70-and-not-50-the-staggered-bond-ring).

> **Do not widen the rings.** Both M8 and M9 are `MAXWIDTH 12` and the rings are exactly 12. Any
> increase is illegal by construction. Any change to `-width`, `-spacing` or `-offset` also moves the
> ring outer edge and must be re-checked against the `PAD70NU` inboard edge at 171 / 1429 / 171 / 1829.

Immediately after the rings, two `route_special -connect {pad_pin pad_ring}` passes bring `VDD` and
`VSS` from the pad pins to the ring, with different pad-pin widths (**1.63** for VDD, **1.5** for VSS)
reflecting the pad geometry, over the full `M1(1)` → `AP(10)` layer range.

---

## 4. Stripes

Both global stripe sets share a long `set_db add_stripes_*` preamble (block-check off, no break-at,
edge-to-edge spacing, stacked vias M1 → AP, orthogonal only). The interesting part is the **spacing**,
which differs between the two layers *for a real reason*.

### 4.1 M8 — vertical, spacing 1.2

```tcl
add_stripes -nets {VDD VSS} -layer M8 -direction vertical \
    -width 3.6 -spacing 1.2 -set_to_set_distance 60 \
    -start_from left -start_offset 39.5 ...
```

**1.2 is legal here.** M8's `SPACINGTABLE` requires only **0.5 µm** at width 3.6:

```lef
LAYER M8
    SPACINGTABLE
    PARALLELRUNLENGTH  0.000  1.500  4.500
      WIDTH  0.000  0.400  0.400  0.400
      WIDTH  1.500  0.400  0.500  0.500
      WIDTH  4.500  0.400  0.500  1.500 ;
```

A 3.6 µm wire falls in the `WIDTH 1.500` row, so the worst-case requirement is 0.5. 1.2 clears it
comfortably. **This is not a copy-paste that survived by luck — leave it at 1.2.**

### 4.2 M9 — horizontal, spacing 3.05 (NOT 1.2)

```tcl
add_stripes -nets {VDD VSS} -layer M9 -direction horizontal \
    -width 3.6 -spacing 3.05 -set_to_set_distance 60 \
    -start_from left -start_offset 39.5 ...
```

M9 has no spacing table — it has flat rules, and they are much stricter:

```lef
LAYER M9
    WIDTH 2 ;
    MAXWIDTH 12 ;
    SPACING 2 ;
    AREA 9 ;
    MINENCLOSEDAREA 9 ;
```

A 1.2 µm gap between two 3.6 µm M9 stripes is therefore **illegal by construction**, and Innovus said
so at the time — these warnings are in `baseline_2026-08-05/logs/pnr_stages.log:1513-1514`:

```
**WARN: (IMPPP-136): The currently specified spacing 1.200000 in -spacing option is less than
                     the required spacing 2.000000 for widths specified as 3.600000 and 3.600000.
**WARN: (IMPPP-193): ... might create min enclosed area violation. The required min enclosed area
                     for layer M9 is 9.000000. If violation happens, increase the spacing to around
                     3.050000. The recommended spacing is the square root of min enclosure area.
```

The cost was **44 SPACING violations, each a full-core-width strip exactly 1.200 µm tall** — literally
the specified gap, handed back as a DRC. `3.05` clears both the `SPACING 2` rule and the
`MINENCLOSEDAREA 9` rule (3.05 ≈ √9, which is where the tool's own recommendation comes from).

Because `-set_to_set_distance` is 60 µm, the extra 1.85 µm is absorbed within the pitch and **no
stripes are dropped**.

> Two warnings, both `**WARN` rather than `**ERROR`, and the flow ran to completion regardless. This is
> the general lesson for this design: `IMPPP-*` warnings during power planning are not noise.

### 4.3 M5 — macro connection

After `split_row` (see §5), a third stripe set connects down to the macro PG pins:

```tcl
set_db add_stripes_ignore_block_check false
set_db add_stripes_extend_to_closest_target {ring stripe}
add_stripes -nets {VDD VSS} -layer M5 -direction horizontal \
    -width 1 -spacing 0.5 -set_to_set_distance 15 -over_power_domain 1 \
    -start_from bottom -start_offset 8 -merge_stripes_value 500 ...
```

Note the three deliberate reversals from the global sets: **block check is re-enabled**
(`ignore_block_check false`), stripes **extend to the closest ring or stripe**, and they are drawn
**over the power domain** rather than the whole core. These are macro-connection stripes, not a global
mesh, and they must respect the blocks they are feeding.

---

## 5. Macro connection — consuming the resolved macro list

```tcl
if {![info exists ::PLACED_MACROS] || [llength $::PLACED_MACROS] == 0} {
    error "power_plan: ::PLACED_MACROS is empty — floorplan.tcl must run first"
}
if {[llength $::PLACED_MACROS] != 21} {
    puts stderr "WARNING: power_plan: expected 21 macros, got [llength $::PLACED_MACROS]"
}
select_obj $::PLACED_MACROS
split_row -selected
```

This file used to carry its **own hardcoded copy** of the same 21 hierarchical paths that
`floorplan.tcl` carried — and it drifted. Because Genus runs with auto-ungroup on, macro names move
when the RTL changes; the **identical 6 names** that went stale in the floorplan (the ethmac RF and the
five QSPI `way1` macros that lost their `gen_way1.` prefix) were still stale here.

The failure was silent in a nastier way than the floorplan's:

- Innovus reported each miss as **`IMPTCM-165` "does not match any object ... in command `select_obj`"**
- …and **carried on**.
- So `split_row` ran on **15 of 21** macros, with no failure and no non-zero exit.

Six macros silently kept their standard-cell rows unsplit. Consuming the list that
[`floorplan.tcl` publishes](03-floorplan.md#43-publishing-the-resolved-macro-list) removes the
duplication entirely — there is now exactly one place where a macro name is resolved.

The hard `error` catches wrong source order; the soft `WARNING` catches a genuine change in macro
count (which is legitimate if the RTL really did gain or lose a memory) without blocking the run.

---

## 6. Endcaps and special routing

```tcl
add_endcaps -start_row_cap DCAP4 -end_row_cap DCAP4 -prefix ENDCAP
```

`DCAP4` decap cells terminate every standard-cell row at both ends.

Then two `route_special` passes complete the grid:

```tcl
# pads -> ring, both nets, wide pad pins
route_special -connect {pad_pin pad_ring} ... -nets { VDD VSS } -pad_pin_width 6 ...

set_db route_special_via_connect_to_shape { padring stripe }

# blocks and standard-cell rails -> the mesh
route_special -connect {block_pin core_pin floating_stripe} \
    -core_pin_target first_after_row_end \
    -floating_stripe_target {block_ring pad_ring ring stripe ring_pin block_pin followpin} \
    -power_domains { PD_TOP } -block_pin use_lef -nets { VDD VSS } ...
```

The second pass is the one that ties the 21 macros' `block_pin`s and the standard-cell `followpin`
rails into the M5/M8/M9 mesh. `-block_pin use_lef` means macro PG pin geometry is taken from the LEF
rather than inferred — correct for these hard macros. Note `-power_domains { PD_TOP }`: another place
where a `PD_TOP` that lacks supply nets would misbehave (§1).

---

## 7. Verification status

**Verified this week against the PDK LEFs, the CPF, and the run logs:**

- M9 `WIDTH 2 / SPACING 2 / MAXWIDTH 12 / AREA 9 / MINENCLOSEDAREA 9` — read from
  `PRTF_EDI_N65_9M_6X1Z1U_RDL.24a.tlef`. A 1.2 µm gap at width 3.6 is definitively illegal.
- M8 `SPACINGTABLE` maximum requirement **1.5**, and **0.5** at width 3.6 — same file. 1.2 is legal.
- `IMPPP-136` and `IMPPP-193` appear in the 2026-08-03 log with exactly the quoted text, including the
  tool's own "increase the spacing to around 3.050000" recommendation.
- `IMPSP-5110` + `For 0 new insts` in the 2026-08-03 log; **absent** from the 2026-08-05 log, which
  instead reports `For 150592 new insts`.
- The CPF in `outputs/` currently carries `create_ground_nets` / `create_power_nets` /
  `update_power_domain` before `end_design` — the patch is applied.
- The live margin-70 run shows **zero** `IMPPP-136`, `IMPPP-193`, `IMPSP-5110`, `IMPTCM-162` and
  `IMPTCM-165`.
- Ring band arithmetic (`core_edge+2 .. +30`) and its 4.00 µm clearance to `PAD70NU` — see
  [03-floorplan §2.3](03-floorplan.md#23-the-arithmetic).

**Not verified / uncertain:**

- **The "44 SPACING violations, each 1.200 µm tall" count cannot be re-checked.** The DRC report from
  the 2026-08-03 run was overwritten by the 2026-08-05 run (both write
  `reports/nanosoc_eth_chiplet_pads_imp_drc.rep`), and that log has no `Total Violations` line. The
  surviving 2026-08-05 report contains **41 M9 `SPACING` records, none of them 1.2 µm tall**, which is
  consistent with the M9 fix already being in place for that run — the M9 spacing was corrected
  *before* the floorplan margin was. The `IMPPP-136/193` warnings are solid evidence for the mechanism;
  the count of 44 and the example bounds `(171.000, 888.100) (1429.000, 889.300)` are not
  reproducible from surviving artefacts. Treat them as historical.
- **The 95,568 free-site figure is not independently reproducible** from the surviving logs. The
  `IMPSP-5110` errors and `For 0 new insts` are directly verified; the free-site count is not in the
  retained log text.
- **`check_filler` output is uninformative.** `baseline_2026-08-05/reports/*_imp_filler.rep` contains
  only its header and `Checking Power Domain: PD_TOP` — no gap census. Do not use it as the filler
  sign-off gate; use the `new insts` count and a density check instead.
- **`IMPMSMV-3501` is an unresolved residual of the minimal CPF**: *"Input power intent (CPF/UPF) does
  not define power_mode/power_state. The always-on buffering is not supported…"*. The `cpf-patch`
  target restores the supply **nets** but not power **modes**. This design is single-domain always-on,
  so the practical impact is believed nil — but that is a judgement, not a measurement. Flagged for
  [11-known-issues](11-known-issues.md).
- The claim that the fixed margin eliminates the 318 PG-to-bond-pad shorts is still a prediction; the
  margin-70 run had not reached `check_drc` when this was written.

---

## 8. Quick checklist before signing off a power plan run

1. `grep -c IMPSP-5110 work/innovus.log*` → **0**
2. `grep "new insts" work/innovus.log*` → a large count, not 0
3. `grep -cE "IMPPP-136|IMPPP-193" work/innovus.log*` → **0**
4. `grep -c IMPTCM-165 work/innovus.log*` → **0** (all 21 macros got `split_row`)
5. `grep -c IMPDB-1221 work/innovus.log*` → **0** (IO supplies really are special nets)
6. In the DRC report, no `Special Wire of Net VDD|VSS & Blockage of Cell BuPAD_*`
7. CPF still patched: `grep create_power_nets outputs/*_gate1.cpf`

Full sign-off in [09-signoff-checklist](09-signoff-checklist.md); report-reading in
[07-reading-reports](07-reading-reports.md); triage in [08-debugging](08-debugging.md).

---

## See also

- [00-index](00-index.md) · [01-flow-overview](01-flow-overview.md) · [02-innovus-basics](02-innovus-basics.md)
- [03-floorplan](03-floorplan.md) — the core box, and why the ring band drove `CORE_TO_IO` to 70
- [05-place-cts-route](05-place-cts-route.md) · [06-fill-antenna-bondpads](06-fill-antenna-bondpads.md)
- [07-reading-reports](07-reading-reports.md) · [08-debugging](08-debugging.md)
- [09-signoff-checklist](09-signoff-checklist.md) · [10-tapeout-submission](10-tapeout-submission.md) · [11-known-issues](11-known-issues.md)
