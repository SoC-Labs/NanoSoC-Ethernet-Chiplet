# 16 — Open defects: static triage of the 2026-08-06 run

[index](00-index.md) · [11 Known issues](11-known-issues.md) · [14 DRC triage](14-drc-triage.md)

Triage of six items carried out **entirely by static analysis** — no Innovus, Genus or
Calibre session was opened. Everything below is derived from files already on disk:

| Source | Path |
|---|---|
| Today's run (CORE_TO_IO 70) | `ASIC/genus-innovus/logs/pnr_run_core70.log`, `reports/`, `outputs/` |
| Previous run (CORE_TO_IO 50) | `ASIC/genus-innovus/baseline_2026-08-05/` |

Verdict summary, worst first:

| | Item | Verdict | Impact |
|---|---|---|---|
| [1](#1-clock-source-latency-is-asymmetric-in-the-hold-view) | Clock source latency asymmetric in `default_analysis_view_hold` | **REAL — flow defect** | injects 1.076 ns of phantom skew into *every* hold check; is the root cause of item 2 |
| [2](#2-post-route-drv-max_transition-max_capacitance) | Post-route DRV: 3,227 `max_transition` pins, 849 `max_capacitance` | **REAL — signoff blocker** | consequence of item 1; 2.6× worse than baseline |
| [3](#3-qspi-flash-cache-tag-ram-undriven-gwen) | QSPI flash-cache tag RAM `GWEN` undriven | **REAL — RTL defect** | both tag RAMs stuck in write mode; cache never reads a tag |
| [4](#4-vddio-vssio-have-no-routing) | `VDDIO` / `VSSIO` have no routing | **BENIGN, but unverified** | expected for an abutted pad ring; nothing checks the ring is continuous |
| [5](#5-tclcmd-917-20-sdc-pins-not-found) | `TCLCMD-917` ×20+ on pad supply pins | **BENIGN — with a real side effect** | timing unaffected; but it exhausts the message limit that would report genuine failures |
| [6](#6-impsp-9099-scan-chains-undefined-for-3055-of-flops) | ~~`IMPSP-9099`~~ → **`IMPSP-9025`** "No scan chain specified/traced" | **BENIGN — historical ID** | DFT is off by design. `IMPSP-9099` has not been emitted since 2026-08-07; the scan-cell census in that section is stale by ~10× and inverted — see its correction banner |

> **The headline number is setup-only.** `qor_05_route_opt.rep` and
> `timing_summary_05_route_opt.rep` report **WNS +0.079, TNS 0, FEP 0** — and both are
> `report_timing_summary -late`. The design does **not** close hold: the same run's final
> summary records hold **WNS −1.167 ns, TNS −66,212 ns, 96,545 violating paths**. See item 1.

---

## 1 — Clock source latency is asymmetric in the hold view

**REAL. This is a flow defect, it is the most consequential finding here, and it is the
cause of item 2.**

### Evidence

The same reg2reg path, reported at three points in the same run. Watch the `Src Latency`
row — capture on the left, launch on the right:

**Post-CTS-opt — clean.** `reports/timing_03_cts_opt_early.rep`
```
                       Capture       Launch
        Src Latency:+   -1.076       -1.076        <-- equal
        Net Latency:+    1.087 (P)    0.689 (P)
              Slack:=   -0.000
```

**Post-route — broken.** `reports/timing_04_route_early.rep`
```
                       Capture       Launch
        Src Latency:+    0.000       -1.076        <-- capture lost it
        Net Latency:+    1.122 (P)    1.090 (P)
              Slack:=   -1.090
```

**Post-route, typical view — still clean.** `reports/nanosoc_eth_chiplet_pads_imp_timing_typical_early.rep`
```
                       Capture       Launch
        Src Latency:+   -1.549       -1.548        <-- equal
              Slack:=   -0.116
```

Source latency is the delay from the clock definition point to the clock-tree root. It is
**common** to launch and capture on the same clock. When the capture side drops it, the
tool believes the capture clock arrives 1.076 ns later than it does, and every hold check
in the design loses 1.076 ns.

### Why the capture side loses it

`ccopt_design` ends with an automatic I/O-latency writeback ("Innovus updating I/O
latencies", `logs/pnr_run_core70.log:25857`). It converts the propagated insertion delay
into a negative source latency, **per clock, per view** — and it only writes the sides
that view has. For `clk`:

| View | Written | Log lines |
|---|---|---|
| `default_analysis_view_setup` | `-max` only | 25916–25923 |
| `typical_analysis_view` | `-min` **and** `-max` | 25924–25939 |
| `default_analysis_view_hold` | **`-min` only** | 25996–26003 |

```
logs/pnr_run_core70.log:25996
	Clock: clk, View: default_analysis_view_hold, Ideal Latency: 0, Propagated Latency: 1.07637
	 Executing: set_clock_latency -source -early -min -rise -1.07637 [get_pins CLK]
	 Executing: set_clock_latency -source -late  -min -rise -1.07637 [get_pins CLK]
	 Executing: set_clock_latency -source -early -min -fall -1.10823 [get_pins CLK]
	 Executing: set_clock_latency -source -late  -min -fall -1.10823 [get_pins CLK]
```

−1.07637 is exactly the −1.076 in the report. There is no `-max` line for this clock in
this view, so the max side defaults to 0.

This is harmless while the min/max split is inactive. The log banner at the writeback says
`Analysis Mode: MMMC Non-OCV`. Then [`scripts/route_setup.tcl`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/route_setup.tcl)
— sourced by `4_pnr_route.tcl`, i.e. **after** CTS — does:

```tcl
### Timing Analysis Type
set_db timing_analysis_type ocv
```

(echoed at `logs/pnr_run_core70.log:30274`). The split activates, the hold check starts
consulting the max-side source latency for the capture clock, finds nothing, and uses 0.

That single line is the boundary between "hold clean" and "hold catastrophic", and the
three reports above bracket it exactly.

### What it cost

`opt_design -post_route -hold` then spent five hours chasing 1.076 ns of phantom skew
across ~121,000 paths, and **still could not close it**:

| | post-CTS-hold | post-route-hold |
|---|---|---|
| hold WNS / TNS / paths | −0.000 / −0.000 / 2 | **−1.167 / −66,212 / 96,545** |
| instances | 194,143 | 231,550 (**+37,407**) |
| area (um²) | 1,640,328 | 1,731,010 (**+90,682**) |
| density | 83.58% | **92.17%** |
| DRV max_tran / max_cap | 0 / 0 | **153 nets (3,227 pins) / 213** |

That density rise is what makes item 2 unfixable. The two items are one defect.

### Not a regression

The baseline has it identically — `baseline_2026-08-05/logs/pnr_all.log:38134` gives hold
WNS −1.149, TNS −63,398, 93,078 paths, and its `imp_timing_early.rep` shows the same
`0.000 / −1.130` asymmetry. This has been true of every run.

### Fix (not applied — outside this page's write scope)

Preferred, one line moved: set the analysis type **before** CTS, so the writeback covers
both sides.

```tcl
# scripts/cts_setup.tcl  — move this here from route_setup.tcl
set_db timing_analysis_type ocv
```

Alternatives, in decreasing order of preference:
- `set_db cts_update_io_latency false` before `ccopt_design` — suppress the writeback
  entirely. The clocks are propagated post-CTS anyway, so the modelling is redundant.
- After switching to `ocv`, mirror the min values onto max by hand for every clock/view
  pair the writeback skipped. Brittle; the values change every run.

**Honest caveat.** The typical view — which *is* symmetric — still shows hold WNS −0.116.
So some genuine hold violation exists underneath the artefact and the fix will not take
hold to zero. Removing ~1.05 ns of phantom skew should, however, let hold repair converge
on the real residue with a small fraction of the 37,407 cells. **This cannot be confirmed
without a re-run**, which needs an Innovus seat.

### Verification commands (for whoever gets a seat)

```tcl
read_db nanosoc_eth_chiplet_pads
report_clock_timing -type latency -view default_analysis_view_hold
report_timing -early -path_type full_clock_expanded -max_paths 5
```

---

## 2 — Post-route DRV (`max_transition` / `max_capacitance`)

**REAL. Signoff blocker. 2.6× worse than the baseline, and a consequence of item 1.**

### The numbers, and where they come from

`reports/timing_summary_05_route_opt.rep` (View: ALL — both active setup views):

```
# DRV                           WNS        TNS   FEP
    Check : max_transition   -3.397  -3784.847  3227
    Check : max_capacitance  -0.203     -6.747   849
```

The `opt_design` table at `logs/pnr_run_core70.log:33504` resolves FEP into nets:

```
|   max_cap      |    213 (213)     |   -0.189   |
|   max_tran     |    153 (3227)    |   -3.397   |
```

So: **153 nets carrying 3,227 violating pins**, worst transition 3.397 ns *over* limit;
213 max_cap nets in the worst-case view (849 across all views — the extra ~636 come from
`typical_analysis_view`). Both columns are headed **"Real"**, not view pessimism.

3,227 pins over 153 nets is ~21 receivers per net — these are **high-fanout nets**, not
isolated stragglers.

### The 1,243 / 618 figures are the *baseline*

`baseline_2026-08-05/logs/pnr_all.log:38134` — 78 nets (1,243 pins) / 124 nets, worst
−3.035. Today is **153 nets (3,227 pins) / 213**. It got worse, not better.

### Where they appear — after hold repair, not after routing

| Stage | max_tran | max_cap | density | report |
|---|---|---|---|---|
| post-CTS-opt (03) | 0 | 0 | 83.58% | log:28865 |
| post-route setup opt (04) | 5 nets (11) | 20 | 83.58% | log:31374 |
| **after hold repair, pre-ecoRoute** | **151 nets (3,666)** | 168 | **92.16%** | log:31637 |
| after ecoRoute | 495 nets (5,120) | 1,088 | 92.16% | log:32388 |
| after DRV recovery (final) | 153 nets (3,227) | 213 | 92.17% | log:33504 |

Routing produced 5 violating nets. **Hold repair produced 151.** This is item 1's phantom
skew being paid for in silicon area.

### Why the tool gave up

`logs/pnr_run_core70.log:32564` —

```
*info: Total 219 net(s) have violations which can't be fixed by DRV optimization.
MultiBuffering failure reasons
*info:    86 net(s): Could not be fixed because the gain is not enough.
*info:    56 net(s): Could not be fixed because the location check has rejected the overall buffering solution.
*info:     2 net(s): Could not be fixed because of exceeding max local density.
```

"Location check rejected" and "max local density" are both *there is no room* — at 92.17%
density the buffers cannot be placed where the net needs them. Baseline finished at
89.45%; today's CORE_TO_IO 50→70 change removed 5.6% of the core (112,800 um²), which is
why the same defect bites harder. Note today inserted **fewer** hold cells than baseline
(37,407 vs 65,250) — it ran out of room sooner and left more DRV behind.

### Is it a signoff blocker? Yes

1. **The reported WNS is not trustworthy on those paths.** A transition 3.4 ns beyond the
   library's characterised range is extrapolated by the delay calculator. Every path
   through those 3,227 pins has an extrapolated delay, and WNS +0.079 is computed from
   them.
2. Slow edges mean crowbar current, EM and noise exposure — none of which the DRV-clean
   parts of the flow modelled.
3. 3,227 pins is not a waivable count.

### What is *not* established

**I could not identify the violating nets by name.** No `report_constraint` /
`report_max_transition` output was written by the flow, and the net list cannot be
recovered from the log or the reports. To get it:

```tcl
read_db nanosoc_eth_chiplet_pads
report_constraint -all_violators -drv_violation_type max_transition \
    -view default_analysis_view_setup > drv_tran.rpt
report_constraint -all_violators -drv_violation_type max_capacitance \
    -view default_analysis_view_setup > drv_cap.rpt
```

**Recommended flow change** (`4_pnr_route.tcl`, not edited here): add exactly those two
lines after `opt_design -post_route -hold`, so the next run triages itself.

### Fix

Fix item 1 first. Almost all of this DRV is hold-repair congestion; do not attack it
directly until hold repair has been made to stop chasing phantom skew.

---

## 3 — QSPI flash-cache tag RAM undriven `GWEN`

**REAL. RTL defect. Functional, not just structural — the tag RAMs never read.**

`check_cpf` reports (`baseline_2026-08-05/logs/syn_cpf_check.log:416`):

```
STRUCT_UNDRIVEN_PIN_MACRO: Macro cell input/inout direction pin with receiver(s) does not have an external driver
    1: '.../u_cache_subsystem/u_way0_cache_ram/tag_ram_0_i/GWEN' is undriven
    2: '.../u_cache_subsystem/u_way1_cache_ram/tag_ram_0_i/GWEN' is undriven
```

### What GWEN does

`flash_cache_tag` is a TSMC65 compiled macro built with `write_mask = on`
(`nanosoc-multicore-system/ahb_qspi/asic/TSMC65nm/flash_cache_tag.spec:32`), which is what
creates the per-bit `WEN[10:0]` **and** a separate global `GWEN`. From the macro's own
structural model, `$MEM_BASE/flash_cache_tag/flash_cache_tag.mdt`:

```
primitive = _and aWRITE0(NOT_GWEN, NOT_SPLIT_WEN[0], NOT_CEN, WRITE[0]);
primitive = _and aREAD0(NOT_CEN, BMUX_GWEN, READ[0]);
```

`GWEN` low ⇒ write, `GWEN` high ⇒ read. Active low. The behavioural model agrees: `Q` is
only updated inside the `GWEN_int === 1'b1` branch
(`flash_cache_tag.v:272–290`). **`WEN` masks which bits a write lands on; it does not
select read vs write. Only `GWEN` does.**

### What the RTL does

`nanosoc-multicore-system/ahb_qspi/logical/cache_models/tsmc65/cache_ram.v`, as committed:

```verilog
flash_cache_tag tag_ram_0_i (
    .Q(TAG_RDATA), .CLK(CLK), .CEN(~cs_tag0),
    .WEN({11{~TAG_WE}}),                       // GWEN simply absent
    .A(TAG_ADDR), .D(TAG_WDATA),
    .EMA(3'b010), .EMAW(2'b00), .RET1N(1'b1)
);
```

Genus defaulted the floating input to a constant: `outputs/nanosoc_eth_chiplet_pads_gate.v:263864`
has `.GWEN (1'b0)`, and the P&R netlist ties it to a `TIEL` cell
(`outputs/nanosoc_eth_chiplet_pads_pnr.v:597007`, `.GWEN(FE_OFN4699_LTIE_PD_TOP_LTIELO_3_NET)`).

**In silicon `GWEN = 0` permanently ⇒ the tag RAM is always in write mode ⇒ `Q` never
presents tag data ⇒ every cache lookup misses.** Nothing is corrupted (`WEN` is all-ones
during what the controller thinks is a read, so no write lands), but the flash cache is
functionally a no-op.

### It is an omission, not a tie-off

The TSMC16 variant of the *same module*
(`ahb_qspi/logical/cache_models/tsmc16/cache_ram.v:180`) drives
`.GWEN(~TAG_WE)` on the tag RAM. The TSMC65 file is the one that lost it. The data RAMs
are not a counter-example: `flash_cache_data` was compiled `write_mask = off` and has **no
`GWEN` pin at all**.

### Fix — reported, not applied (submodule is out of scope)

One line in `ahb_qspi/logical/cache_models/tsmc65/cache_ram.v`, in both tag RAM
instantiations:

```verilog
    .GWEN(~TAG_WE),
```

`cs_tag0 = TAG_CS & (TAG_WE | TAG_RD)` and `TAG_WE` is active high, so `~TAG_WE` is the
correct active-low polarity — the same expression the TSMC16 file already uses.

**Note:** this fix already exists in the `ahb_qspi` submodule **working tree**, with a
comment block diagnosing the bug — but it is **uncommitted**, so it is in no netlist and
no GDSII. Someone needs to commit it, bump the submodule pin, and re-synthesise.
`check_cpf` should then go 2 → 0.

---

## 4 — `VDDIO` / `VSSIO` have no routing

**BENIGN as far as the evidence goes — but one thing nobody checks. The `IMPDB-1221`
in the brief is stale: it does not occur in this run.**

### `IMPDB-1221` is fixed

The six `IMPDB-1221` hits in `logs/pnr_run_core70.log` are all inside **echoed comment
text** from `config.tcl` (they carry the `@file NNN:` prefix). There is not one actual
occurrence. The baseline has two real ones
(`baseline_2026-08-05/logs/pnr_all.log`):

```
**ERROR: (IMPDB-1221): A Global Net Connection (GNC) is specified to connect the power pins
with the 'VDDIO' name pattern to a global net. Unable to establish connection because the
'power' pin with the name pattern doesn't match in any cell.
```

The patched IO driver LEF (set in `config.tcl`, adding `USE POWER ;` / `USE GROUND ;` to
`VDDPST`/`VSSPST`) fixed it. Today `restorePlace` reports `*** Checked 8 GNC rules.` with
no error, and the 81 `Regular Wire of Net VDDIO/VSSIO` DRC records the old behaviour
produced are **gone** (81 → 0).

### But the nets are now unrouted

`reports/nanosoc_eth_chiplet_pads_imp_connectivity.rep`:

```
Net VDDIO: no routing
Net VSSIO: no routing
...
    2 Problem(s) (IMPVFC-98): Net has no global routing and no special routing.
```

This is expected from the scripts. [`scripts/power_plan.tcl`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/power_plan.tcl)
gives `VDDIO`/`VSSIO` a `connect_global_net` **and nothing else** — every `add_rings`,
`add_stripes` and `route_special` in the file is `-nets {VDD VSS}`. Before the LEF fix the
router treated them as ordinary signal nets and threaded them round the periphery (badly).
Now they are correctly PG nets, and NanoRoute leaves PG nets to sroute — which is never
told about them.

### Why that is almost certainly correct

- The core is VDD/VSS. **`VDDIO` powers only the pad drivers' output stage, which lives
  inside the pad ring.** Nothing in the core needs it.
- In a TSMC staggered IO ring the supply pads (`PVDD2POC_G`, `PVDD2DGZ_G`, `PVSS2DGZ_G`)
  distribute `VDDPST`/`VSSPST` **by abutment** through the IO fillers and corner cells —
  you do not route them. `floorplan.tcl` calls `add_io_fillers` for
  `PFILLER20_G`/`PFILLER10_G`/`PFILLER5_G` on all four sides.
- The netlist is correct: `outputs/nanosoc_eth_chiplet_pads_pnr.v:1524022` onwards shows
  all 12 supply pads on `.VDDPST(VDDIO)`, with `VDDIO` a top-level port
  (`:1379804  input VDDIO;`), **3 per side** — so each side is independently fed and a
  broken corner would not orphan anything.

### What is *not* established — the residual risk

`check_connectivity` gives up on a net that has no routing, so **nothing in this flow
verifies the pad-ring supply bus is continuous.** If `add_io_fillers` left a gap, or a
corner cell were missing, `VDDIO` would be broken over that arc and **no report in the run
would say so.** That is the one real exposure here.

To close it (needs a seat):

```tcl
verify_power_via -net VDDIO
report_pad_ring                     ; # confirm no gaps between IO cells
check_connectivity -type special -net {VDDIO VSSIO}
```

or, cheaper: confirm in the GDS that the `VDDPST` bus geometry is unbroken around all four
sides. Until then, treat "VDDIO is connected" as **believed, not verified**.

---

## 5 — `TCLCMD-917` ×20: SDC pins not found

**BENIGN for timing. But it has a real side effect that matches the symptom "SDC
constraints silently not applied", and it should still be fixed.**

### What line 696 is

`outputs/nanosoc_eth_chiplet_pads_syn.sdc` line 696 is the **last line** of a command that
starts at line 148 — Innovus reports the line where a command ends:

```
148: set_multicycle_path -from [list \
       ...548 [get_pins ...] entries...
696:   [get_pins uPAD_VSS_T_1/VSS] ] -setup -end 2
```

It comes from one line of hand-written SDC —
[`inputs/constraints.sdc:79`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/inputs/constraints.sdc):

```tcl
### Multicycle path through pads
set_multicycle_path 2 -from uPAD*/* -to uPAD*/*
```

`uPAD*/*` matches **every** pin on every pad instance — including the supply pads. Genus
resolves the wildcard at `write_sdc` time and bakes the expansion into the SDC, so 68 of
the 548 entries (34 unique pins × from-list and to-list) are pad **supply** pins:

```
uPAD_VDDIO_{B,L,R,T}_{0,1,2}/VDDPST   (12)
uPAD_VSSIO_{B,L,R,T}_{0,1,2}/VSSPST   (12)
uPAD_VDD_{B,T}_{0,1,2}/VDD            (6)
uPAD_VSS_{B,T}_{0,1}/VSS              (4)
```

Innovus's `get_pins` does not return supply pins, so each one raises `TCLCMD-513` (warning)
followed by `TCLCMD-917`.

### Why it does not matter for timing

- Supply pins carry no timing arcs and can never be a valid path start or endpoint. A
  multicycle exception on them is meaningless whether it applies or not.
- The failures do **not** abort the command. `get_pins` returns an empty collection, the
  empty elements are ignored, and the exception is applied to the 480 signal-pad pins that
  did resolve. Nothing in the log says otherwise.
- The `in2out` path group has **0 paths** (`timing_summary_05_route_opt.rep`), so this
  exception is close to a no-op regardless.
- It is not caused by the local-override LEF: the baseline has the same 20 messages.

### The side effect that *does* matter

Only **20** of the ≥68 failures were printed. Innovus then said:

```
(TCLCMD-917> has exceeded the message display limit of '20'.
 Use 'set_message -no_limit -id list_of_msgIDs' to reset the message limit.
```

**Every subsequent `TCLCMD-917` in the run was suppressed** — at line 696 of a 957-line
SDC. Any genuine "constraint not applied" after that point would have been silent.

I checked the rest of this SDC: lines 697–957 contain 235 object references, all
`get_ports` / `get_cells` / `get_clocks` (no `get_pins`), and every port named
(`CLK`, `QSPI_IO`, `TL_RX`, `RMII_*`, `SWDCK`, …) is a real chip port. **So nothing was
actually hidden this time.** But the hazard is live for any future SDC edit.

### Fix

Two changes, neither in this page's write scope:

1. **`inputs/constraints.sdc:79`** — stop the wildcard matching supply pads. The supply
   pads are exactly `uPAD_VDD*` and `uPAD_VSS*`; every signal pad is named for its
   function:

   ```tcl
   ### Multicycle path through pads
   # uPAD*/* matches every pin on every pad instance, including the supply pads'
   # VDDPST/VSSPST/VDD/VSS. Genus expands the wildcard into outputs/*_syn.sdc,
   # and Innovus then raises TCLCMD-917 on each because get_pins does not return
   # supply pins — 68 error-level messages that also exhaust the 20-message
   # display limit for that ID.
   set SIG_PADS [remove_from_collection [get_cells uPAD*] \
                     [get_cells {uPAD_VDD* uPAD_VSS*}]]
   set_multicycle_path 2 -from [get_pins -of_objects $SIG_PADS] \
                         -to   [get_pins -of_objects $SIG_PADS]
   ```

2. **`2_pnr_setup.tcl`**, before `read_sdc`/`init_design` — never let a constraint-read
   error class be silently truncated again:

   ```tcl
   set_message -no_limit -id {TCLCMD-917 TCLCMD-513}
   ```

---

## 6 — `IMPSP-9099`: scan chains undefined for 30.55% of flops

**BENIGN. False positive. DFT is off by design — document, do not chase.**

> ### ⚠ CORRECTED 2026-08-18 — CONCLUSION STANDS, MESSAGE ID AND CENSUS NOW STALE
>
> Everything below was **measured correctly against the 2026-08-06 / 08-07 netlists** and
> is preserved for that reason. Three facts have since changed. Do not quote the numbers
> in this section against a current build.
>
> **1. `IMPSP-9099` no longer occurs.** Innovus last emitted it on **2026-08-07 14:21**
> (`runs/20260807T150304Z_gwen-sdc-i2c-m7/prev_logs/pnr_m7.log`), at ERROR severity, ×2,
> with exactly the text quoted here. It appears **zero** times in every build from
> 2026-08-08 onward, including the current `fp1505` and `full-20260814`.
> *Positive control:* nine other `IMPSP-*` IDs do appear in those same logs
> (`9025`, `5217`, `5534`, `5110`, `2021`, `5224`, `196`, `9082`, `2040`), so this is a
> real absence and not a broken grep.
>
> **The message you will actually see today is `IMPSP-9025`, "No scan chain
> specified/traced"** — WARN, not ERROR: 52 occurrences in `full-20260814`, 23 in
> `fp1505`. It is benign for the same reason, and it is the message any future triage
> should be written against.
>
> **2. The census below is inverted for current builds.** Measured 2026-08-18:
>
> | Netlist (`..._pnr.v`) | scan-family `SDF*`/`SEDF*` | plain `DF*`/`EDF*` | total flops | scan % |
> |---|---:|---:|---:|---:|
> | `baseline_2026-08-06` | 37,834 | 20,286 | 58,120 | **65.1%** |
> | `baseline_2026-08-07` | 37,834 | 20,286 | 58,120 | **65.1%** |
> | `build/full-20260814` | 3,715 | 54,905 | 58,620 | **6.34%** |
> | `build/fp1505` (current) | 3,715 | 54,905 | 58,620 | **6.34%** |
>
> The original "37,834 `SDF*` and 20,137 `DF*`" is **exactly right for the 08-06/08-07
> netlists** — 20,137 is `DF*` excluding the 149 `EDF*`. On the current netlist the
> majority has flipped: scan-family cells are now **6.34%**, not the majority. A reader
> who took the old figure forward would conclude this design is close to scan-ready.
> **It is not — there is no chain at all**, which is precisely what `IMPSP-9025` says.
>
> The flip happened between **2026-08-07 12:27** (`baseline_2026-08-07`, 37,834) and
> **2026-08-08 12:12** (`runs/20260808T100330Z_route-setupopt`, 3,604) — the same window
> in which `IMPSP-9099` stopped being emitted, which is consistent with the two having a
> single cause.
>
> **The cause is NOT ESTABLISHED and was not determined here.** One obvious candidate was
> tested and **refuted**: the `set_case_analysis 0 [get_ports SE]` in `constraints.sdc`
> landed in commit `7510739` on **2026-08-09**, *after* the flip, and in any case the
> flop `SE` pins are driven by internal enable nets rather than by the top-level `SE`
> port, so it cannot constant-propagate them. Treat the mechanism as an open question.
>
> **3. The mechanism described below is still real, just rare.** `BlockTxDone_reg` is
> still an `SDFCNQD1` in the current netlist (now at `pnr.v:10482`, not `:2897`). Genus
> still maps some load-enables onto the scan mux; it now does so for ~3.7k flops instead
> of ~37.8k.
>
> **Line citations in this section have all drifted** and are corrected inline below.

### DFT is off

[`scripts/config.tcl:166`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/config.tcl) —

```tcl
set DFT 0
```

Every DFT branch in the flow is therefore skipped (line numbers re-measured 2026-08-18
against `ASIC/asic-flows` @ `c2a46ee`, branch `lpddr4-pll`; the previous numbers in this
table were 8–14 lines low and are given in brackets):

| Guarded by `if {$DFT == 1}` | File |
|---|---|
| `source ../scripts/dft_setup.tcl` | `asic-flows/Cadence/1_synthesis.tcl:59` *(was :50)* |
| `convert_to_scan` / `connect_scan_chains` | `1_synthesis.tcl:70–71` *(was :61)* |
| `write_scandef`, scan reports, ATPG models | `1_synthesis.tcl:97` *(was :83)* |
| `read_def $OUT_DIR/$block_name.def` (scan DEF) | `2_pnr_setup.tcl:39` *(was :33)* |
| `reorder_scan` | `2_pnr_setup.tcl:64` *(was :58)* |
| `reorder_scan -clock_aware true` | `3_pnr_clock.tcl:42` *(was :36)* |

Because these live in a submodule, re-check them against the pin you actually build with
before quoting them.

No scan insertion, no scan DEF, no chain reorder. This matches
`inputs/constraints.sdc:71` *(was cited as :43)* — *"scan_clk : tied 1'b0; the scan chain
is not bonded."*

### Why Innovus thinks chains exist anyway

The netlist is full of scan-flop cells — but their scan pins carry **functional** logic.
`outputs/nanosoc_eth_chiplet_pads_pnr.v:2897` (08-06 vintage; the same instance is at
`:10482` in the current `fp1505` netlist, still an `SDFCNQD1`):

```verilog
   SDFCNQD1 BlockTxDone_reg (.CDN(n_6),
	.CP(MTxClk),
	.D(TxCtrlStartFrm),
	.Q(...),
	.SE(n_19),
	.SI(BlockTxDone),          <-- a design signal, not a scan-chain link
```

`.SI(BlockTxDone)` is the flop's own output fed back: Genus mapped a load-enable
(`if (en) q <= d; else q <= q;`) onto the scan mux built into the `SDF*` cell, which is
standard area-efficient mapping when scan is off. Innovus's `IMPSP-9099` heuristic sees
flops with connected `SE`/`SI` pins, concludes chains exist, and complains that the
remaining plain flops are not in one.

A census of `outputs/nanosoc_eth_chiplet_pads_pnr.v` gives 37,834 `SDF*` and 20,137 `DF*`
instances (34.7% plain) against Innovus's reported 58,120 total flops — the same order as
the 30.55% in the message. **I could not reproduce 30.55% exactly**; Innovus's denominator
is its own and is not derivable from the netlist. The qualitative conclusion does not
depend on it.

> **↑ TRUE FOR 08-06/08-07 ONLY.** Re-measured 2026-08-18 the same netlist census gives
> **3,715 scan-family and 54,905 plain out of 58,620 flops — 6.34% scan.** See the
> correction banner at the top of this section for the full table. Note also that the
> netlist total *is* exactly 58,120 for the 08-06 vintage, so the "denominator is its own"
> caveat was over-cautious: 37,834 + 20,286 (`DF*` **plus** the 149 `EDF*`) = 58,120
> exactly. Innovus's total was derivable after all; only the 30.55% split was not.

### Action

None on the design. Document it as expected. Two flow notes worth logging:

- **`scripts/dft_setup.tcl` does not exist.** `1_synthesis.tcl:59` sources it whenever
  `DFT == 1`, so **DFT cannot currently be turned on** — the run would die immediately.
  If DFT is ever wanted, that file has to be written first and the whole path is untested.
  *Re-verified 2026-08-18:* still absent (`find ASIC -name dft_setup.tcl` → nothing;
  positive control: the same `find` for `1_synthesis.tcl` returns three hits).
- ~~Suppress the noise rather than re-investigating it each run:
  `set_message -suppress -id IMPSP-9099` in `preplace.tcl`~~ — **obsolete.** The message
  is no longer emitted, so there is nothing to suppress. Note that
  `scripts/2b_pnr_place_eval.tcl:158` still carries `IMPSP-9099` in
  `EVP_ERROR_ALLOWLIST`; that entry is now dead but harmless, and removing it would mean
  the allowlist no longer tolerates the message if a future flow change brings it back.
  Left alone deliberately — not a defect.

---

## Two things found in passing

Neither was in scope; both are recorded so they are not lost.

**Calibre signoff DRC did not run.** The run ended on
`IMPSYT-6692: Invalid return code while executing 4_pnr_route.tcl ... script processing
was stopped`, from the `exec calibre -drc` block at the end of that file. The underlying
cause is `IMPSE-110: can't find package Tk 8.0` while loading
`<mentor install>/calibre/shared<icv install>/tools/queryenc/encounter.tcl`. **Everything of value
was already written** — `write_stream`, `report_area`, `report_power`, `write_netlist`,
`write_sdf` and `write_db` all precede the Calibre call, and the output timestamps (GDS
17:42, netlist 17:45, SDF 17:47) confirm it. But the run's exit status is a failure and
**no signoff DRC deck was run against the GDSII.**

**60× `IMPLF-223`** — duplicate LEF via definitions (`VIA12_1cut`, `VIA12_1cut_H`, …)
across the LEF list; later definitions ignored. Worth confirming the ignored ones are
identical to the kept ones, since the message does not say.

---

## What changed in `floorplan.tcl`

Item 6 of the original brief (stale comment figures) is applied in
[`scripts/floorplan.tcl`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/floorplan.tcl) — **comments
only, no command, coordinate or value touched**:

- `539 violations` → **580** (the DRC report's own trailer says
  `Total Violations : 580 Viols.`; 539 came from a grep that missed 41 mixed-case
  `EndOfLine:` records).
- `318 PG shorts are 59% of all DRC` → **54.8%** (318/580).
- Added the result now known. Independently re-derived here:

| | baseline (CORE_TO_IO 50) | today (CORE_TO_IO 70) |
|---|---|---|
| Total violations | 580 | **102** |
| bond-pad (`BuPAD_`) blockage violations | 398 | **0** |
| PG-ring vs bond-pad shorts | 318 | **0** |
| `SHORT` records | 379 | 1 |

The `PAD70NU 366 / PAD70GU 32 / 318 PG` split already in the comment is **correct** — I
re-derived it by joining the DRC records against the bond-pad cell types in the netlist.
The fix worked.

**Do not lower `CORE_TO_IO` again to reclaim the 5.6% of core area** without first fixing
item 1 — the extra utilisation it bought (89.45% → 92.17%) is what turned item 2 from 78
violating nets into 153.

---

# ADDENDUM 2026-08-12 — item 1 is FIXED; the gate that guards it is not

> Appended, not merged into the text above. Everything before this line is the
> 2026-08-06 triage and stands as written. This section records what the same
> defect number looks like six days later, because `make pnr_route_eval` is now
> being blocked by a check that cites item 1 on a database where item 1 is
> demonstrably absent.

**Verdict: item 1 (the defect) is CLOSED. `evroute_srclat_skew`, the route-stage
gate that detects it, is MISCALIBRATED and is now a hard false positive.**

Static analysis only — no Innovus, Genus or Calibre session was opened. All
numbers below are read out of files already on disk.

## The failure being reported

`make pnr_route_eval`, run `runs/20260812T121941Z_route-corrected-map`, aborted
after 2m21s, before `route_design`, at
[`scripts/4b_pnr_route_eval.tcl`](../../ASIC/genus-innovus/scripts/4b_pnr_route_eval.tcl)
§3b:

```
EVROUTE-FAIL: clock source latency is asymmetric by 0.538 ns between the capture
and launch sides of the worst hold path. That is docs/tapeout/16-open-defects.md #1
and it makes every hold number in this run fiction. Fix CTS, not route.
```

## Item 1 is fixed, and three independent measurements say so

The one-line fix proposed above — `set_db timing_analysis_type ocv` moved from
`route_setup.tcl` into `cts_setup.tcl`, before `ccopt_design` — **was applied**.
It is [`scripts/cts_setup.tcl:72`](../../ASIC/genus-innovus/scripts/cts_setup.tcl),
under a 47-line comment reproducing the analysis above. `timing_analysis_cppr
true` and the four derate arms were added alongside it.

The CTS run that produced the database this route run consumed
(`runs/20260811T131651Z_fill-verify-eval`) proves the fix holds:

| Check | 08-06 (broken) | 08-11 (this DB) |
|---|---|---|
| `reports/eval/cts_latency_writeback.rep`, hold view | min 16 / **max 0** | **min 20 / max 20** |
| `cts_manifest.txt` `wb_hold_min` / `wb_hold_max` | 16 / 0 | **20 / 20** |
| `timing_analysis` at CTS | `default` | **`ocv`** |
| post-CTS hold WNS / TNS / FEP | −1.167 / −66,212 / 96,545 | **−0.005 / −0.074 / 59** |

The writeback is complete for all five clock roots in all three views. The route
stage's own §3a check confirms `timing_analysis_type = ocv`
(`runs/20260812T121941Z_route-corrected-map/logs/run.log:3713`), and the same
run's first QoR line reads:

```
run.log:3689  QOR post-cts (as read) | setup wns 0.005 tns 0.000 fep 0
                                     | hold wns -0.005 tns -0.074 fep 59
```

**Hold WNS −0.005 ns over 59 endpoints is the healthy signature.** Item 1's
signature is −1.167 ns over 96,545. The gate is calling item 1 on a database
whose hold view is four orders of magnitude cleaner in TNS than the defect it
names.

## Where the 0.538 ns actually comes from

Evidence: `reports/eval/nanosoc_eth_chiplet_pads_eval_srclat_precheck.rep`
(archived at
`runs/20260812T121941Z_route-corrected-map/reports/eval/`). The worst hold path
is **not a same-clock path**:

```
Path 1: VIOLATED (-0.005 ns) Hold Check          View: default_analysis_view_hold
 Startpoint: .../phy_gpio/gpiorx_2/link_data_word_reg[3]/CP   Clock: D2D_RX_CLK_0
   Endpoint: .../phy_gpio/gpiorx_2/link_data_reg_reg[3]/D     Clock: D2D_RX_WORDN_CLK_2

                    Capture       Launch
      Clock Edge:+   80.000       80.000
      Drv Adjust:+    0.059        0.016
     Src Latency:+   -0.269       -0.807     <-- the gate reads only this row
     Net Latency:+    0.227 (P)    0.704 (P)
         Arrival:=   80.017       79.913
```

Launch is the **master** clock `D2D_RX_CLK_0`, defined at the port `TL_CLK_RX`.
Capture is a **generated** clock `D2D_RX_WORDN_CLK_2`, defined at
`gpiorx_2/count_reg[3]/Q` — the /16 divider output, deep inside the die
([`inputs/tidelink_constraints.sdc:196`](../../ASIC/genus-innovus/inputs/tidelink_constraints.sdc)).

Source latency is measured from the clock's own definition point. The two
definition points are different, so the two `Src Latency` numbers are measured
from different places, and their difference is the **master-clock delay between
those two points** — not skew. From the report's own expanded clock trace:

```
uPAD_TL_CLK_RX/C            PAD->C   PDDW16DGZ_G   delay 0.426
gpiorx_2/count_reg[3]/Q     CP->Q    DFSNQD1       delay 0.112
                                                   ----------
                                                         0.538
```

**0.426 + 0.112 = 0.538, exactly the reported number, to the last digit.** The
capture side books the input pad and the divider's clock-to-Q under *source*
latency because they precede its definition point; the launch side books the
same pad under *net* latency because they follow its definition point. Nothing
is missing on either side — the writeback value is visible on both traces
(`TL_CLK_RX` arrival −0.748 late / −0.791 early), which is precisely what item 1
said would be absent.

The quantity that actually enters the hold check is total insertion delay:

| | drv | src | net | total |
|---|---|---|---|---|
| launch | +0.016 | −0.807 | +0.704 | **−0.087** |
| capture | +0.059 | −0.269 | +0.227 | **+0.017** |

Real skew **0.104 ns**, capture-late. With hold 0.021 + uncertainty 0.050 −
CPPR 0.073, that yields the −0.005 ns the report shows. The arithmetic is
self-consistent and there is no phantom term anywhere in it.

## Why this is a miscalibration and not a tolerance to tune

`EVR_SRCLAT_TOL` is 0.05 ns
([`4b_pnr_route_eval.tcl:208`](../../ASIC/genus-innovus/scripts/4b_pnr_route_eval.tcl)).
The irreducible part of the 0.538 is the `PDDW16DGZ_G` input-pad delay (~0.43 ns)
plus one flop CP→Q (~0.11 ns). Neither is a routing or CTS quantity: the pad is
vendor I/O and the divider is the clock's own generator.

**No clock tree, no CTS setting and no `cts_setup.tcl` knob can bring this number
below 0.05.** Any hold path that crosses from a master clock to a generated clock
defined at an internal divider output will trip this gate, always, on any
database, however good. That is a property of the predicate, not of the design.

## Why it started failing today and not before

The gate has passed on every prior route run. Its probe is
`report_timing -early -max_paths 1`, i.e. *the single worst hold path in the
design*, and until now that path always happened to have the same clock on both
ends:

| run | worst hold path clocks | Src Latency cap / lau | gate |
|---|---|---|---|
| 08-07 → 08-08 ×5 | `D2D_RX_CLK_0` → `D2D_RX_CLK_0` | −0.659 / −0.659 | pass |
| `20260808T174047Z` | `clk` → `clk` | −1.125 / −1.125 | pass |
| `20260808T223829Z` | `clk` → `clk` | −1.134 / −1.134 | pass |
| **`20260812T121941Z`** | **`D2D_RX_CLK_0` → `D2D_RX_WORDN_CLK_2`** | **−0.269 / −0.807** | **FAIL** |

`D2D_RX_WORDN_CLK_0..7` did not exist before 2026-08-09
(`tidelink_constraints.sdc`, "RECOVERED D2D RX WORD CLOCK, NEGATIVE PHASE"). The
last route-stage run, `20260808T223829Z_stage1b-route`, consumed a CTS database
that predates them. **`20260812T121941Z` is the first route run to see a CTS
database in which the RX word domain is constrained at all**, and the path it
trips on is the one the SDC author explicitly called out as newly visible:

> `link_data_word (D2D_RX_CLK_0, pad clock) -> link_data_reg   [a real check]`
> — `tidelink_constraints.sdc:171`
>
> "EXPECT MORE TIMING PATHS/VIOLATIONS ON THE NEXT RUN, NOT FEWER. These 16,653
> flops were previously invisible to timing; now they are timed. That is the fix
> WORKING." — `tidelink_constraints.sdc:246`

The gate is firing on the arrival of a fix it was never taught about.

## Fix — a clock-aware predicate

The check must not compare the `Src Latency` columns unless both ends are on the
same clock. When they are not, fall back to item 1's actual signature: one side
exactly `0.000` against a non-zero other side.

**Not applied here — `4b_pnr_route_eval.tcl` is outside this page's write scope.**
The change, in full:

```tcl
# --- new helper, next to evroute_srclat_skew (4b_pnr_route_eval.tcl:391) ------
# Launch and capture clock names from a report_timing path header. The first
# "Clock:" line follows Startpoint, the second follows Endpoint.
proc evroute_srclat_clocks {path} {
    if {![file exists $path]} { return [list "" ""] }
    set fh [open $path r] ; set lau "" ; set cap "" ; set seen 0
    while {[gets $fh line] >= 0} {
        if {[regexp {^\s*Clock:\s+\([RF]\)\s+(\S+)} $line -> c]} {
            if {$seen == 0} { set lau $c ; incr seen } else { set cap $c ; break }
        }
    }
    close $fh
    return [list $lau $cap]
}

# --- call site, replacing the `elseif {$skew > $EVR_SRCLAT_TOL}` arm (~:571) --
lassign [evroute_srclat_clocks $srclat_rep] lau_clk cap_clk
if {$lau_clk ne "" && $cap_clk ne "" && $lau_clk ne $cap_clk} {
    # Cross-clock worst hold path. Source latency is measured from each clock's
    # OWN definition point, so the delta is the master-clock delay between those
    # two points, not skew. For a generated clock defined at an internal divider
    # output it is structurally >= the input-pad delay and can never pass a
    # 50 ps tolerance. See docs/tapeout/16-open-defects.md, ADDENDUM 2026-08-12.
    say "worst hold path crosses clocks: $lau_clk -> $cap_clk"
    say "  Src Latency columns are not comparable across definition points;"
    say "  raw delta ${skew} ns is pad + divider CP->Q, not skew. Not gated."
    say "  The item-1 mechanism is gated at CTS instead: 3b gate 2, wb_hold_max."
    if {[evroute_srclat_zero $srclat_rep]} {
        flow_fail "one side of Src Latency is exactly 0.000 against a non-zero" \
                  "other side - that IS docs/tapeout/16-open-defects.md #1." \
                  "Evidence: $srclat_rep"
    }
} elseif {$skew > $EVR_SRCLAT_TOL} {
    ...unchanged...
}
```

`evroute_srclat_zero` is the strict signature test — the same regex as
`evroute_srclat_skew`, returning true when exactly one of the two captured
values is `0.000`.

**Do not simply raise `EVR_SRCLAT_TOL`.** It is env-overridable
(`flow_utils.tcl:110`), so `EVR_SRCLAT_TOL=0.6 make pnr_route_eval` unblocks the
run today — but it raises the floor for *every* clock pair including the
same-clock ones the gate exists to police, and 0.538 ns of genuine same-clock
asymmetry would then pass silently. Acceptable as a single supervised run with
this section cited in the run notes; not acceptable as a default.

**`3b_pnr_cts_eval.tcl` gate 3 (§13, ~line 1295) carries the identical blind
spot** and passed on 08-11 only by luck — its probe landed on a same-clock
`typical_analysis_view` path (`hold_src_capture −1.689`, `hold_src_launch
−1.689`). The same clock-name guard belongs in `evcts_hold_path_probe`
(3b:365). Not applied: the gate currently passes, no Innovus seat is available
to prove a Tcl change against a real report, and a broken gate is worse than a
latent one.

## Proving the fix

1. Patch `evroute_srclat_skew`'s call site as above.
2. Re-run `make pnr_route_eval` against the same CTS database
   (`work/nanosoc_eth_chiplet_pads_eval_cts`, also archived at
   `runs/20260811T131651Z_fill-verify-eval/work/`). **No CTS re-run is needed** —
   the input database is correct.
3. §3b should now print
   `worst hold path crosses clocks: D2D_RX_CLK_0 -> D2D_RX_WORDN_CLK_2` and
   continue. Cost to reach that point: ~2.5 minutes, the same as the abort.
4. Route then runs to completion: 30 min – 2.5 h.
5. **The number that must change is the gate's verdict, not any timing number.**
   Post-route hold WNS should land near the −0.005 / −0.074 / 59 it starts from,
   *not* near −1.167 / −66,212 / 96,545. If post-route hold blows up to the
   item-1 numbers, the gate was right and this section is wrong.

## Found in passing — a genuine item-1-class defect on the TX word clocks

`TA-1018` ×16 in this run, ×464 at CTS:

```
WARN (TA-1018): A source latency path to the generated clock D2D_TX_WORD_CLK_4
through source pin .../u_wlink/pad_clk_tx to target pin
.../phy_gpio/gpiotx_4/io_link_clk in view default_analysis_view_hold cannot be
found. Timing analysis will use 0 ns source latency for the generated clock.
```

**This is not the cause of the 0.538 ns** — that path is RX-side and both its
`Src Latency` values are non-zero. But "will use 0 ns source latency" *is* item
1's mechanism, on a different clock, and it is real.

The cause is a direction error in the SDC.
[`tidelink_constraints.sdc:231-232`](../../ASIC/genus-innovus/inputs/tidelink_constraints.sdc):

```tcl
create_generated_clock -name "D2D_TX_WORD_CLK_$n" \
    -source [get_pins $WL/pad_clk_tx] -divide_by 16 $_pin
```

with the stated rationale "the same pin `D2D_TX_CLK_0` already uses, so the two
stay phase-coherent". But `pad_clk_tx` is *downstream* — it is the clock leaving
`u_wlink` for the `TL_CLK_TX` pad (`WlinkGPIOPHY_v2.v:334`). `D2D_TX_CLK_0` is
`-source pad_clk_tx` → `[get_ports TL_CLK_TX]`, which is a forward path and
resolves. `D2D_TX_WORD_CLK_n` is `-source pad_clk_tx` → `gpiotx_n/io_link_clk`,
which is *backwards*: `io_link_clk` is generated inside `gpiotx_n`, upstream of
`pad_clk_tx`. No forward path exists, so none is found.

The correct `-source` is the clock that drives the TX divider, exactly as the RX
block does it. `cts_hold_path.rep` from the 08-11 CTS run names it: the TX
counter is `gpiotx_0/count_reg[1]/CP`, `Clock: (R) clk`.

Side effects already visible: `ccopt` reclassified `D2D_TX_WORD_CLK_0` as an I/O
clock *root* and wrote a source latency back for it — it is the fifth row in
`cts_latency_writeback.rep`, which is why that report totals 20 against a
`Reference:` line still reading "4 clock roots". And `cts_manifest.txt`
`clock_trees` lists `D2D_TX_WORD_CLK_0` only, against all eight of
`D2D_RX_WORDN_CLK_0..7`.

Out of scope to fix here (`inputs/tidelink_constraints.sdc` is not this page's
write scope) and it needs a synthesis + CTS re-run to land. Filed so it is not
lost, and so it is not confused with the gate false positive above.
