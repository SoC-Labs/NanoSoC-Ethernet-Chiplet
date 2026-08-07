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
| [6](#6-impsp-9099-scan-chains-undefined-for-3055-of-flops) | `IMPSP-9099` scan chains undefined for 30.55% of flops | **BENIGN — false positive** | DFT is off by design; message is a misreading of functional mux use |

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
structural model, `/research/precompiled_mems/TSMC65/flash_cache_tag/flash_cache_tag.mdt`:

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

The local-override LEF (`config.tcl:135–160`, adding `USE POWER ;` / `USE GROUND ;` to
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

### DFT is off

[`scripts/config.tcl:123`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/config.tcl) —

```tcl
set DFT 0
```

Every DFT branch in the flow is therefore skipped:

| Guarded by `if {$DFT == 1}` | File |
|---|---|
| `source ../scripts/dft_setup.tcl` | `asic-flows/Cadence/1_synthesis.tcl:50` |
| `convert_to_scan` / `connect_scan_chains` | `1_synthesis.tcl:61` |
| `write_scandef`, scan reports, ATPG models | `1_synthesis.tcl:83` |
| `read_def $OUT_DIR/$block_name.def` (scan DEF) | `2_pnr_setup.tcl:33` |
| `reorder_scan` | `2_pnr_setup.tcl:58` |
| `reorder_scan -clock_aware true` | `3_pnr_clock.tcl:36` |

No scan insertion, no scan DEF, no chain reorder. This matches
`inputs/constraints.sdc:43` — *"scan_clk : tied 1'b0; the scan chain is not bonded."*

### Why Innovus thinks chains exist anyway

The netlist is full of scan-flop cells — but their scan pins carry **functional** logic.
`outputs/nanosoc_eth_chiplet_pads_pnr.v:2897`:

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

### Action

None on the design. Document it as expected. Two flow notes worth logging:

- **`scripts/dft_setup.tcl` does not exist.** `1_synthesis.tcl:50` sources it whenever
  `DFT == 1`, so **DFT cannot currently be turned on** — the run would die immediately.
  If DFT is ever wanted, that file has to be written first and the whole path is untested.
- Suppress the noise rather than re-investigating it each run:
  `set_message -suppress -id IMPSP-9099` in `preplace.tcl`, with a comment pointing here.

---

## Two things found in passing

Neither was in scope; both are recorded so they are not lost.

**Calibre signoff DRC did not run.** The run ended on
`IMPSYT-6692: Invalid return code while executing 4_pnr_route.tcl ... script processing
was stopped`, from the `exec calibre -drc` block at the end of that file. The underlying
cause is `IMPSE-110: can't find package Tk 8.0` while loading
`/eda/mentor/calibre/shared/pkgs/icv/tools/queryenc/encounter.tcl`. **Everything of value
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
