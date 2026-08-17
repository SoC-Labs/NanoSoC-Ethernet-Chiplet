# 07 — Reading the reports

Every report this flow writes, what command produced it, what "good" looks like, and what
to grep for. All excerpts below are copied verbatim from
`ASIC/genus-innovus/baseline_2026-08-05/reports/` — a complete real run of
`nanosoc_eth_chiplet_pads` on `srv03335`, 2026-08-05.

Prev: [06 — Fill, antenna, bond pads](06-fill-antenna-bondpads.md) ·
Next: [08 — Debugging](08-debugging.md) ·
[Index](00-index.md)

> **Before you trust a single number on this page**, read
> [The DRC numbers are not signoff DRC](#the-drc-numbers-are-not-signoff-drc). It applies
> to `check_drc`, to Calibre, and to anything anyone calls "our DRC count".

---

## Where reports come from

Two files generate essentially all of them.

`ASIC/asic-flows/Cadence/procs.tcl` — 12 lines, and worth reading in full, because it
defines the entire per-stage report set:

```tcl
proc report_intermediate_step {name REPORT_DIR} {
    report_timing_summary > $REPORT_DIR/timing_summary_${name}.rep
    report_timing -late   > $REPORT_DIR/timing_${name}_late.rep
    report_timing -early  > $REPORT_DIR/timing_${name}_early.rep
}

proc report_end_step {name REPORT_DIR} {
    report_timing_summary > $REPORT_DIR/timing_summary_${name}.rep
    report_timing -late   > $REPORT_DIR/timing_${name}_late.rep
    report_timing -early  > $REPORT_DIR/timing_${name}_early.rep
    report_power          > $REPORT_DIR/power_${name}.rep
    report_qor -format text -out_file $REPORT_DIR/qor_${name}.rep
}
```

So: **`timing_summary_*` / `timing_*` exist at every stage; `power_*` and `qor_*` only at
"end" stages** (`01_place`, `03_cts_opt`, `05_route_opt`). If you are looking for
`qor_02_cts.rep`, it was never written — that is not a failure.

`ASIC/asic-flows/Cadence/4_pnr_route.tcl` writes the design-level checks, after
`place_bondpads.tcl` has run:

```tcl
source ../scripts/place_bondpads.tcl

check_drc             -out_file $REPORT_DIR/${block_name}_imp_drc.rep
check_filler          -out_file $REPORT_DIR/${block_name}_imp_filler.rep
check_connectivity    -out_file $REPORT_DIR/${block_name}_imp_connectivity.rep
check_process_antenna -out_file $REPORT_DIR/${block_name}_imp_antenna.rep
```

The ordering matters when you read the DRC report: **bond pads are placed before
`check_drc` runs**, which is why pad blockages dominate the violation list.

### The two naming conventions

| Pattern | Meaning |
|---|---|
| `<something>_NN_<stage>.rep` | per-stage, from `procs.tcl`. `NN` orders them: `00_pre_place`, `01_place`, `02_cts`, `03_cts_opt`, `04_route`, `05_route_opt` |
| `nanosoc_eth_chiplet_pads_imp_<check>.rep` | end-of-flow design check, written once by `4_pnr_route.tcl` |
| `syn_*.rep` | Genus, not Innovus — written by the `syn` stage |

All commands used here are **proven in Innovus 21.11-s130_1**: `report_timing_summary`,
`report_timing -late` / `-early`, `report_power`, `report_qor -format text -out_file`,
`report_area`, `check_drc`, `check_connectivity`, `check_process_antenna`, `check_filler`.
They are all invoked by the flow every run, so none of them is a guess.

---

## Start here: the one-command summary

Do not read 40 files by hand. `scripts/ci/asic_stage_report.sh` already extracts the
fields that decide whether a run is worth continuing, and prints a markdown table:

```bash
cd /home/dam1n19/SoCLabs/nanosoc-ethernet-chiplet
scripts/ci/asic_stage_report.sh route
```

It is **report-only and never gates** — every extractor tolerates a missing or truncated
file and prints `n/a`. Stage pass/fail is the Makefile's job (see
[08 — Debugging](08-debugging.md)).

It also auto-diffs against the newest `ASIC/genus-innovus/baseline_*` directory, which is
exactly why one is kept:

```bash
BASELINE_DIR=ASIC/genus-innovus/baseline_2026-08-05 scripts/ci/asic_stage_report.sh route
BASELINE_DIR= scripts/ci/asic_stage_report.sh route     # disable the diff
```

Read the script before trusting it. It is the best available worked example of parsing
these formats, and its comments record the traps — but it has one known undercount, noted
under [`check_drc`](#check_drc-_imp_drcrep) below.

---

## `report_timing_summary` → `timing_summary_NN_<stage>.rep`

The headline timing number for a stage.

```
# SETUP                  WNS    TNS   FEP
#------------------------------------------
 View : ALL            0.068  0.000     0
    Group : Async      2.398  0.000     0
    Group : ClockGate  6.800  0.000     0
    Group : in2out       N/A    N/A     0
    Group : reg2out    8.062  0.000     0
    Group : in2reg     0.807    0.0     0
    Group : reg2reg    0.068    0.0     0
```

**Good** = WNS positive, TNS `0.000`, FEP `0`. The baseline closes setup at **+0.068 ns**
with zero failing endpoints.

Further down the same file:

```
# DRV                           WNS        TNS   FEP
#-----------------------------------------------------
 View : ALL
    Check : max_transition   -3.035  -1032.060  1243
    Check : min_transition      N/A        N/A     0
    Check : max_capacitance  -0.173     -2.361   618
    Check : min_capacitance     N/A        N/A     0
```

**This is not clean and never has been.** 1243 max-transition and 618 max-capacitance
violations survive to the end of the flow. Timing closes; design rule *value* checks do
not. Treat any claim of "timing clean" that quotes only the SETUP block as incomplete.

```
# Clock checks                              WNS    TNS   FEP
#-------------------------------------------------------------
 View : ALL
    Check : min_pulse_width (clocktree)     N/A    N/A     0
    Check : min_pulse_width (endpoints)   5.823  0.000     0
    Check : max_skew                        N/A    N/A     0
    Check : min_period                    7.045  0.000     0
```

### Trap 1 — `View : ALL` appears three times, twice with blank columns

```bash
$ grep -n 'View : ALL' timing_summary_05_route_opt.rep
11: View : ALL            0.068  0.000     0
23: View : ALL
35: View : ALL
```

Lines 23 and 35 are the DRV and Clock-checks sections, whose per-view rows carry **no
numbers at all**. Any extractor that takes the last match, or scans for the first line
containing the string, reads a blank and reports nothing. **Anchor on the `# SETUP`
banner.** `asic_stage_report.sh` does exactly that:

```awk
/^# SETUP/       { in_setup = 1; next }
in_setup && /^ *View : ALL/ {
    if (NF >= 3 + n && $(3 + n) != "") { print $(3 + n); exit }
}
```

Note the belt-and-braces `$(3 + n) != ""` field check as well as the anchor. Copy the
whole idiom, not half of it.

### Trap 2 — every one of these files opens with an `**ERROR`

All six `timing_summary_*.rep` files begin with:

```
**ERROR: (TCLCMD-1130):	The '-late' and '-early' options to the report_timing_summary
command can only be specified together when the timing system is in simultaneous setup
and hold mode. ... Ignoring '-early' and using '-late' alone.
```

**This one is benign.** `report_timing_summary` asks for both internally, the tool
declines, falls back to `-late`, and produces a complete and correct report. It is the
only `**ERROR` that appears in any report file in the baseline run:

```bash
$ grep -hoE '\*\*ERROR: \([A-Z]+-[0-9]+\)' reports/* | sort | uniq -c
      6 **ERROR: (TCLCMD-1130)
```

Learn to recognise it so it does not blunt your instinct to grep for `**ERROR` everywhere
else. See [08 — Debugging](08-debugging.md#3-warnings-are-where-the-bodies-are).

### Reading the pre-CTS stages

`timing_summary_01_place.rep` shows large negative slack and that is expected, not
alarming — there is no clock tree yet, so every path is timed against an ideal-network
estimate. The header says so explicitly:

```
# Design Stage: PreRoute
# Analysis Mode: MMMC Non-OCV
# Parasitics Mode: No SPEF/RCDB
# Signoff Settings: SI Off
```

Compare that against the post-route file's header — `PostRoute`, `MMMC OCV`,
`SPEF/RCDB`, `SI On`. **Different analysis, different numbers.** The number worth reading
at `place` is the delta against the same stage of a previous run, not the absolute value.

---

## `report_timing -late` / `-early` → `timing_NN_<stage>_{late,early}.rep`

The single worst path, in full. `-late` is setup, `-early` is hold.

```
Path 1: MET (0.068 ns) Setup Check with Pin u_..._u_qspi_apb_bridge_rwdata_reg_reg[22]/CP->D
               View: default_analysis_view_setup
              Group: clk
         Startpoint: (R) u_..._qspi_n_rw_bytes_latched_reg[2]/CP
              Clock: (R) QSPI_SCLK
           Endpoint: (F) u_..._u_qspi_apb_bridge_rwdata_reg_reg[22]/D
              Clock: (R) clk

                       Capture       Launch
         Clock Edge:+   10.000        0.000
        Src Latency:+    0.000       -2.619
        Net Latency:+    2.668 (P)    2.892 (P)
            Arrival:=   12.668        0.273

              Setup:-   -0.023
        Uncertainty:-    0.350
      Required Time:=   12.341
       Launch Clock:=    0.273
          Data Path:+   12.000
              Slack:=    0.068
```

**Good** = the first word after `Path 1:` is `MET`. `VIOLATED` means negative slack.

```bash
grep -m1 '^Path 1:' reports/timing_05_route_opt_late.rep      # verdict in one line
grep -c '^Path [0-9]' reports/timing_05_route_opt_late.rep    # how many paths reported
```

The worst path here is a **clock-domain crossing** — launched on `QSPI_SCLK`, captured on
`clk`. Worth knowing before you try to fix it as a normal datapath.

Below the summary is the per-point table (`Timing Point / Flags / Arc / Edge / Cell /
Fanout / Trans / Delay / Arrival`). Read the `Delay` column to find the offender; in this
path three `DEL2`/`DEL005` delay cells contribute 2.762 + 3.115 + 0.115 ns of the 12 ns
data path, i.e. the path is intentionally delay-padded, not accidentally slow.

### The three view flavours at the end of the flow

`4_pnr_route.tcl` re-times the design under different analysis views and writes three
pairs. They are **not** interchangeable:

| File | View set |
|---|---|
| `..._imp_timing_typical_{late,early}.rep` | `typical_analysis_view` only |
| `..._imp_timing_{late,early}.rep` | `default_analysis_view_setup` + `typical_analysis_view` (setup), `default_analysis_view_hold` + `typical_analysis_view` (hold) |
| `timing_05_route_opt_{late,early}.rep` | whatever was active during `report_end_step` |

Quote the filename whenever you quote a slack number.

The same script also writes four `.mtarpt` files (`timing_full_*_{early,late}.mtarpt`,
`-output_format gtd -max_paths 10000`) into `work/`, not `reports/`. Those are for
loading into a timing debugger, not for reading.

---

## `report_qor` → `qor_NN_<stage>.rep`

The best single-screen view of a run, and the file to diff between runs.

`qor_05_route_opt.rep`, in full:

```
| Snapshot                     | WNS (ns) | TNS (ns) | FEPS | ... | UTIL        | INSTS  | AREA (um^2) | DRC | WALL (s) |
|                              |          |          |      |     | Density (%) |        |             |     |          |
|------------------------------+----------+----------+------+-----+-------------+--------+-------------+-----+----------|
| place_design                 |          |          |      |     |       72.72 | 184372 |     1609582 |     | 0:18:35  |
| CCOpt::Phase::Initialization |          |          |      |     |       72.72 |        |             |     | 0:01:36  |
| ccopt_design                 |    0.001 |        0 |    0 |     |       75.01 | 192952 |     1636409 |   0 | 0:32:24  |
| opt_design_postcts           |    0.001 |        0 |    0 |     |       74.95 | 192790 |     1635758 |     | 0:10:34  |
| opt_design_postcts_hold      |    0.003 |        0 |    0 |     |       75.52 | 194869 |     1642351 |     | 0:04:59  |
| opt_design_postroute_hold    |    0.068 |        0 |    0 |     |       89.45 | 260119 |     1805556 |   0 | 3:06:20  |
```

Read it as a **history**: WNS improves 0.001 → 0.068 as optimisation proceeds, density
climbs 72.72 → 89.45 %, and instance count grows 184,372 → 260,119 (post-route hold repair
alone inserts ~65,000 buffers). `WALL` tells you where the five hours went —
`opt_design_postroute_hold` is 3h06 of it.

### Trap — `report_qor` is cumulative, so phase-match your comparisons

`qor_01_place.rep` contains exactly **one** row:

```
| place_design | | | | | 72.72 | 184372 | 1609582 | | 0:18:35 |
```

`qor_05_route_opt.rep` contains **six**, including that same `place_design` row. So a
comparison that takes "the density from `qor_01_place`" (72.72) and "the density from
`qor_05_route_opt`" (89.45, the last row) is comparing a placement number against a
post-route number and will show a spurious 16.7-point regression. **Match on the snapshot
name, not on the file.**

```bash
# right: same phase, two runs
for d in reports baseline_2026-08-05/reports; do
    awk -F'|' '/opt_design_postroute_hold/ {print FILENAME": "$8}' \
        ASIC/genus-innovus/$d/qor_05_route_opt.rep
done
```

This is principle 6 in [08 — Debugging](08-debugging.md#6-compare-like-with-like), and it
has already caused one wrong conclusion on this project.

The `DRC` column is populated only for some snapshots (blank elsewhere). Do not read a
blank as zero.

---

## `report_power` → `power_NN_<stage>.rep` and `..._imp_power.rep`

The first ~300 lines are delay-calculation and SI-iteration chatter. Skip to `Total
Power`:

```
Total Power
-----------------------------------------------------------------------------------------
Total Internal Power:       88.00698891 	   72.1584%
Total Switching Power:      33.55561837 	   27.5128%
Total Leakage Power:         0.40099102 	    0.3288%
Total Power:               121.96359830
-----------------------------------------------------------------------------------------

Group                           Internal   Switching     Leakage       Total  Percentage
-----------------------------------------------------------------------------------------
Sequential                         40.02       4.058      0.1215        44.2       36.24
Macro                              14.38      0.2199      0.1642       14.77       12.11
IO                                 19.67       1.478    0.001046       21.15       17.34
Physical-Only                          0           0   5.229e-05   5.229e-05   4.287e-05
Combinational                      11.72       20.14      0.1094       31.97       26.21
Clock (Combinational)              2.213       7.656    0.004824       9.874       8.096
Clock (Sequential)                     0           0           0           0           0
-----------------------------------------------------------------------------------------
Total                              88.01       33.56       0.401         122         100
```

```bash
grep -A6 '^Total Power$' reports/nanosoc_eth_chiplet_pads_imp_power.rep
```

**Units are mW.** Total 122 mW at the post-route corner.

**Read this as a relative/sanity number, not a datasheet figure.** There is no activity
file (no VCD/SAIF) in this flow, so switching activity is the tool's default propagated
estimate. `Physical-Only` reading ~0 is the fingerprint of the zero-filler defect
described under [`check_filler`](#check_filler-_imp_fillerrep) — in a properly filled
design that row carries the filler leakage.

Also verify which view produced it. The file's first line is
`Using Power View: default_analysis_view_setup.` — the worst-case corner, not typical.

---

## `report_area` → `..._imp_area.rep`

Hierarchical instance count and area. Very wide, heavily padded with spaces; the top-level
is the **first data row**:

```
nanosoc_eth_chiplet_pads                     260283          2396728.890
 u_nanosoc_eth_chiplet_chip_u_soc_u_soc      127186          1154583.560
  u_..._u_cc_periph_0                          6935            30407.400
  u_..._u_dmac_0                              10948            39463.560
  u_..._u_network_core                        56338           593194.090
```

Last two fields: **instance count, then total area in µm²**.

```bash
awk '$1=="nanosoc_eth_chiplet_pads" {print "insts="$(NF-1), "area="$NF; exit}' \
    reports/nanosoc_eth_chiplet_pads_imp_area.rep
# insts=260283 area=2396728.890
```

Field-position parsing (`$(NF-1)`, `$NF`) is mandatory. Column positions are not fixed —
module names in this design run to 400+ characters (`u_network_core`'s parameterised
module name is one unbroken 380-character identifier).

**Sanity check against `qor`:** `report_area` says 260,283 instances / 2,396,729 µm²;
`qor_05_route_opt.rep` says 260,119 / 1,805,556. They disagree because they count
different things — `report_area` includes IO and pad cells, `qor`'s AREA column is the
standard-cell/core figure. Neither is wrong; quote the source.

`report_area` runs **after** `write_stream` in `4_pnr_route.tcl`, so it describes the
design that was actually streamed.

---

## `check_drc` → `..._imp_drc.rep`

### Format

```
SHORT: ( Metal Short ) Special Wire of Net VSS & Blockage of Cell BuPAD_VDD_T_2  ( AP )
Bounds : ( 1368.100, 1832.000 ) ( 1374.100, 1844.000 )

SHORT: ( Metal Short ) Special Wire of Net VDD & Blockage of Cell BuPAD_HOST_IO_6  ( M9 )
Bounds : ( 1429.000, 1827.500 ) ( 1429.000, 1828.000 )

SPACING: ( ParallelRunLength Spacing ) Special Wire of Net VDD & Special Wire of Net VSS  ( M9 )
Bounds : ( 1347.500, 1828.000 ) ( 1377.500, 1829.000 )

EndOfLine: ( EndOfLine Spacing ) Regular Wire of Net u_..._n_9331 & Pin of Cell u_..._g469274  ( M1 )
Bounds : ( ... )
```

Each violation is a **type line** plus a `Bounds :` line giving the violation rectangle.
The trailing parenthesised token is the layer. Feed the `Bounds` coordinates to the GUI to
look at one — see [08](08-debugging.md#inspecting-one-violation-in-the-gui).

The file ends with the tool's own total:

```
  Total Violations : 580 Viols.
```

### Counting them — and a correction

The obvious recipe **undercounts**:

```bash
$ grep -cE '^[A-Z]+:' nanosoc_eth_chiplet_pads_imp_drc.rep
539          # but the file says 580
```

The 41 missing violations are the `EndOfLine:` category, whose keyword is **mixed case**
and so fails `^[A-Z]+:`. 539 + 41 = 580.

```bash
# correct: matches every type line, including EndOfLine
$ grep -cE '^[A-Za-z]+: \(' nanosoc_eth_chiplet_pads_imp_drc.rep
580

# always cross-check against the tool's own total
$ grep 'Total Violations' nanosoc_eth_chiplet_pads_imp_drc.rep
  Total Violations : 580 Viols.
```

> **This bit the CI extractor** (fixed 2026-08-06). `scripts/ci/asic_stage_report.sh`'s
> `drc_total()` used `grep -cE '^[A-Z]+:'` and reported **539 where the truth is 580** —
> a 7% error that also shifted every derived percentage. It now reads the report's own
> trailer and only falls back to a case-insensitive count if the trailer is missing:
>
> ```bash
> t=$(grep -oE 'Total Violations[ ]*:[ ]*[0-9]+' "$f" | tail -1 | grep -oE '[0-9]+$')
> if [ -n "$t" ]; then echo "$t"
> else grep -cE '^[A-Za-z]+:' "$f" || echo "n/a"; fi
> ```
>
> **Prefer the tool's own trailer to any count you compute.** It cannot be wrong about a
> violation class you have not thought of. `ASIC/genus-innovus/scripts/floorplan.tcl`
> still carries the old 539 figure in its header comment (and derives "59% of all DRC"
> from it, where the true share is 55%) — the design decision it justifies is unaffected,
> but do not copy the number forward.

### Baseline breakdown (measured)

```bash
$ grep -oE '^[A-Za-z]+:' nanosoc_eth_chiplet_pads_imp_drc.rep | sort | uniq -c | sort -rn
    379 SHORT:
    108 SPACING:
     41 EndOfLine:
     28 MINSTEP:
     14 MINHOLE:
      7 NSMETAL:
      2 MINCUT:
      1 MINWIDTH:
```

| Slice | Count | Recipe |
|---|---|---|
| Total | **580** | `grep -cE '^[A-Za-z]+: \('` |
| Involving a bond-pad blockage | **398** | `grep -c 'Blockage of Cell BuPAD'` |
| VDD/VSS special wire vs bond-pad blockage | **318** | `grep -cE 'Special Wire of Net (VDD\|VSS) & Blockage of Cell BuPAD'` |
| Involving a macro blockage | 47 | `grep -c 'Blockage of Cell u_nanosoc'` |

**318 of 580 — 55% of all DRC — is one defect**: the PG ring shorting into bond-pad
blockages. By layer:

```bash
$ grep -oE '\( (AP|M[0-9]) \)$' nanosoc_eth_chiplet_pads_imp_drc.rep | sort | uniq -c | sort -rn
    264 ( M8 )
    156 ( M9 )
     71 ( M4 )
     41 ( M1 )
     38 ( M5 )
      4 ( M6 )
      4 ( AP )
      2 ( M7 )
```

M8+M9 = 420 of 580 (72%), consistent with the top-layer PG mesh running into the pad ring.
The 41 M1 violations are exactly the 41 `EndOfLine` signal-routing violations — a
genuinely separate, and much smaller, problem. See
[04 — Power plan](04-power-plan.md) and [06 — Fill, antenna, bond pads](06-fill-antenna-bondpads.md).

**Good** would be `Total Violations : 0`. This design has never achieved that.

---

## The DRC numbers are not signoff DRC

This applies to `check_drc` above **and** to `make drc` below. It is the single most
important caveat on this page.

`gds_merge_list` in `ASIC/genus-innovus/scripts/config.tcl` is eight entries long:

```tcl
set gds_merge_list [list \
    ${RF32_GDS} ${RF16_GDS} ${RF8_GDS} ${RF1_GDS} \
    ${CC_ROM_GDS} ${ETH_ROM_GDS} ${FLASH_DATA_GDS} ${FLASH_TAG_GDS} \
]
```

Those are the **8 memory macros — and nothing else**. Standard cells (`tcbn65lp`), IO
drivers (`tphn65lpgv2od3_sl`) and bond pads (`tpbn65v`) are streamed as **empty cell
references**, because this site's PDK ships LEF, liberty and Milkyway for them but **no
GDS and no CDL**.

Consequences, stated plainly:

- Every DRC number this flow produces is a **routing / PG / blockage check**. It says
  nothing about anything inside a standard cell, an IO driver, or a bond pad.
- A clean run would mean "the wires I routed do not break rules against each other or
  against macro blockages". It would **not** mean the layout is manufacturable.
- **LVS cannot run here at all** — no CDL means no source netlist for the cells.
- Cell-level GDS merge has to happen at the foundry or via the broker. See
  [10 — Tapeout submission](10-tapeout-submission.md).

Say this out loud every time someone quotes a DRC count, including when the count is zero.
A zero here is not a pass; it is a smaller question answered.

---

## Calibre DRC — `make drc`

Run from `ASIC/genus-innovus/`:

```bash
make drc          # headless — no X display, no GUI packages
```

Ruledeck: `/tsmc65pdk/65/CMOS/util/MAIN_DRC_TopMu/CLN65S_9M_6X1Z1U.26_2a`. Results land in
`work/drc_run/`.

`scripts/calibre/run_drc.sh` preflights and fails loudly if there is no licence, no GDS,
or an unreadable deck (the last needs the `/tsmc65pdk` mount and group `tsmc65pdkgrp`).

The TSMC deck ships with `LAYOUT PATH "GDSFILENAME"` / `LAYOUT PRIMARY "TOPCELLNAME"`
placeholders, and `calibre -drc` has no command-line override for them, so layout and top
cell come from the project's own wrapper deck, `scripts/calibre/nanosoc_eth_chiplet_pads.drc.rules`,
which `INCLUDE`s the foundry deck untouched. Layout and top cell are set there together so
they cannot drift apart — an earlier reference run named `nanosoc_eth_chiplet.gds` (the
pre-pads stream) against top cell `nanosoc_eth_chiplet_pads`, which is not a cell in that
file, and produced a 0-byte `DRC_RES.db`.

Point it at someone else's stream without editing anything:

```bash
make drc GDS=/path/to/other.gds
```

### The in-Innovus Calibre call is a no-op — use the Makefile

`4_pnr_route.tcl` ends with:

```tcl
if {[info exists ::env(CALIBRE_HOME)]} {
    exec calibre -drc -hier -turbo 8 $drc_ruledeck
}
```

It only fires when `CALIBRE_HOME` is set, and it passes **no runset**, so the deck's
placeholders are never overridden. The companion `source .../cal_enc.tcl` at the top of
the same script fails outright in the baseline log:

```
**ERROR: (IMPSE-110):	File '/eda/mentor/calibre/shared/pkgs/icv/tools/queryenc/encounter.tcl'
line 47: can't find package Tk 8.0.
```

**The Makefile target is the one that works.** Ignore the in-Innovus path.

---

## `check_connectivity` → `..._imp_connectivity.rep`

### Format

```
Net VSS: has special routes with opens at (1034.500, 419.435) (1058.900, 421.355)
Net VSS: has special routes with opens at (1034.500, 405.845) (1058.900, 408.765)
...
Net VDD: dangling Wire at (1371.300, 379.400) (1371.300, 379.400) on layer: M1
```

and ends with a summary block:

```
Begin Summary
    329 Problem(s) (IMPVFC-200): Special Wires: Pieces of the net are not connected together.
    671 Problem(s) (IMPVFC-94): The net has dangling wire(s).
    1000 total info(s) created.
End Summary
```

**Good** = a summary with no `IMPVFC-200` line. The baseline has **329 PG opens**, cause
unknown, two hypotheses already falsified — see
[11 — Known issues](11-known-issues.md).

### The cap trap — read this before comparing two runs

`check_connectivity` **caps its message list at 1000 by default**. Look at the summary
again: 329 + 671 = **exactly 1000**. That is not a coincidence, it is saturation. The tool
stopped emitting once it hit the limit.

**Detection rule: if `N total info(s) created` is exactly 1000, every count in that file
is a lower bound.**

How badly does it matter? The same design re-checked with the cap raised:

```bash
# what the experiment runs actually used (from conn_halo_test.rep's own header)
check_connectivity -type special -error 200000 -warning 200000 -out_file ../reports/conn_halo_test.rep
```

| | baseline (capped) | uncapped rerun |
|---|---|---|
| `IMPVFC-98` no routing at all | *(absent)* | **202** |
| `IMPVFC-200` special-wire opens | 329 | 329 |
| `IMPVFC-94` dangling wires | 671 | **1328** |
| total | 1000 | 1859 |

Two lessons, both concrete:

1. **A whole category was invisible.** 202 `IMPVFC-98` problems ("Net has no global
   routing and no special routing") do not appear in the default report *at all*.
2. **Truncation is not proportional.** The opens count happened to be complete (329 = 329)
   because those messages were emitted first; the dangling count was truncated by half.
   You cannot tell which from the capped file alone.

A previous analysis on this project compared "171 vs 298" opens across two runs and drew a
conclusion. That comparison was meaningless — both files were saturated. **Always re-run
with the limits raised before comparing.**

```bash
# count opens — a LOWER BOUND unless you have checked the total
grep -c 'has special routes with opens' reports/..._imp_connectivity.rep

# check for saturation FIRST
sed -n '/Begin Summary/,/End Summary/p' reports/..._imp_connectivity.rep
```

`asic_stage_report.sh` labels this row **"PG opens (lower bound)"** for exactly this
reason. Keep the label if you touch that script.

---

## `check_process_antenna` → `..._imp_antenna.rep`

The whole file, when clean:

```
###############################################################
#  Generated by:      Cadence Innovus 21.11-s130_1
#  Design:            nanosoc_eth_chiplet_pads
#  Command:           check_process_antenna -out_file ../reports/nanosoc_eth_chiplet_pads_imp_antenna.rep
###############################################################

No Violations Found
```

**Good** = the literal string `No Violations Found`.

```bash
grep -q 'No Violations Found' reports/..._imp_antenna.rep && echo clean || echo VIOLATIONS
```

**Read this one sceptically in the baseline.** That run shipped with zero `ANTENNA` diodes
inserted (next section), so a clean antenna report there means the router's own diode-free
routing passed the LEF antenna rules — not that the design's antenna protection works. In
a run where filler *did* insert, a clean report means what you want it to mean.

---

## `check_filler` → `..._imp_filler.rep`

**This report is not a verdict, and mistaking it for one hid a tapeout-blocking defect.**

The entire baseline file:

```
###############################################################
#  Generated by:      Cadence Innovus 21.11-s130_1
#  Design:            nanosoc_eth_chiplet_pads
#  Command:           check_filler -out_file ../reports/nanosoc_eth_chiplet_pads_imp_filler.rep
###############################################################

Checking Power Domain: PD_TOP
```

That is all of it. No count, no total, no pass, no fail. The redirected variant that
`scripts/filler.tcl` writes to `work/check_filler.log` is barely better:

```
*INFO: Total number of padded cell violations: 0
*INFO: Total number of gaps found: 0
```

`0 gaps found` reads like success. The design it describes contains **zero filler cells**:

```bash
$ grep -c FILLER ASIC/genus-innovus/baseline_2026-08-05/outputs/nanosoc_eth_chiplet_pads_pnr.v
0
```

The cause is upstream — `IMPSP-5110: No supply-net names for Power Domain 'PD_TOP'` makes
every `add_fillers` pass insert nothing and report `For 0 new insts`. `check_filler` then
finds no gaps *because it cannot evaluate the domain either*.

**Do not verify filler from this report. Verify it from the netlist:**

```bash
grep -c FILLER outputs/${BLOCK}_pnr.v          # must be a large number, not 0
grep -c 'IMPSP-5110' logs/pnr_all.log          # must be 0
grep 'new insts' logs/pnr_all.log              # add_fillers must not say "For 0 new insts"
```

`scripts/ci/asic_stage_report.sh` guards the root cause at the `syn` stage instead:

```
row "CPF supply-net patch" \
    "$(grep -q 'update_power_domain' "$OUT/${BLOCK}_gate1.cpf" && echo 'present' \
       || echo 'MISSING — add_fillers will insert nothing')"
```

Full account in [04 — Power plan](04-power-plan.md) and
[06 — Fill, antenna, bond pads](06-fill-antenna-bondpads.md).

---

## Genus reports — `syn_*.rep`

Written by `make syn`, and generated by **Genus 21.15-s080_1**, not Innovus. Same
directory, different tool, different formats.

| File | Contents |
|---|---|
| `syn_area.rep` | post-synthesis area, plus the resolved technology library list |
| `syn_gates.rep` | gate-level cell inventory |
| `syn_timing.rep` | worst paths, in a Genus variant of the `report_timing` layout |
| `syn_power.rep` | synthesis power estimate |

`syn_area.rep`'s header is the fastest way to confirm which libraries were actually
resolved — a frequent source of confusion when a corner or a ROM library is missing:

```
  Generated by:           Genus(TM) Synthesis Solution 21.15-s080_1
  Module:                 nanosoc_eth_chiplet_pads
  Library domain:         domain1
    Technology libraries: tcbn65lpwc 200
                          RF_LIB_16K_ss_1p08v_1p08v_125c 1.1
                          RF_LIB_08K_ss_1p08v_1p08v_125c 1.1
                          RF_LIB_01K_ss_1p08v_1p08v_125c 1.1
                          RF_LIB_32K_ss_1p08v_1p08v_125c 1.1
                          tphn65lpgv2od3_slwc 210a
```

`syn_timing.rep` reports `Path 1: MET (1 ps)` in the baseline — synthesis closes with
1 ps of margin under `WCCOM`, wireload mode `segmented`. That is a **pre-layout estimate
with no placement**; it is not comparable to any Innovus number.

The synthesis logs (`logs/syn_logs.log*`, `syn_lib_check.log`, `syn_cpf_check.log`,
`syn_pow_check.log`) are rotated per run with a numeric suffix — `syn_logs.log7` is the
seventh. `ls -t` to find the current one.

---

## Grep cheat-sheet

From `ASIC/genus-innovus/`, with `R=reports B=nanosoc_eth_chiplet_pads`:

```bash
R=reports; B=nanosoc_eth_chiplet_pads

# setup WNS / TNS / FEP, correctly anchored
awk '/^# SETUP/{s=1;next} s&&/^ *View : ALL/&&$4!=""{print "WNS="$4" TNS="$5" FEP="$6;exit}' \
    $R/timing_summary_05_route_opt.rep

# DRV violations (never clean on this design)
sed -n '/^# DRV/,/^#---.*---$/p' $R/timing_summary_05_route_opt.rep

# worst path verdict
grep -m1 '^Path 1:' $R/timing_05_route_opt_late.rep

# QoR history
cat $R/qor_05_route_opt.rep

# power total
grep -A6 '^Total Power$' $R/${B}_imp_power.rep

# instances + area
awk -v b=$B '$1==b{print $(NF-1), $NF; exit}' $R/${B}_imp_area.rep

# DRC: tool total, my count, breakdown
grep 'Total Violations' $R/${B}_imp_drc.rep
grep -cE '^[A-Za-z]+: \(' $R/${B}_imp_drc.rep
grep -oE '^[A-Za-z]+:' $R/${B}_imp_drc.rep | sort | uniq -c | sort -rn
grep -c 'Blockage of Cell BuPAD' $R/${B}_imp_drc.rep

# connectivity: SATURATION CHECK FIRST, then counts
sed -n '/Begin Summary/,/End Summary/p' $R/${B}_imp_connectivity.rep
grep -c 'has special routes with opens' $R/${B}_imp_connectivity.rep

# antenna
grep -q 'No Violations Found' $R/${B}_imp_antenna.rep && echo clean || echo VIOLATIONS

# filler — NOT from the filler report
grep -c FILLER outputs/${B}_pnr.v

# everything at once
../../scripts/ci/asic_stage_report.sh route
```

---

## What "good" looks like, end to end

| Report | Good | Baseline 2026-08-05 |
|---|---|---|
| `timing_summary_05_route_opt` SETUP | WNS > 0, TNS 0, FEP 0 | **+0.068 / 0.000 / 0** ✅ |
| `timing_summary_05_route_opt` DRV | FEP 0 | 1243 transition, 618 capacitance ❌ |
| `timing_05_route_opt_late` | `Path 1: MET` | **MET (0.068 ns)** ✅ |
| `qor_05_route_opt` | density < ~90%, WNS improving | 89.45%, 0.001 → 0.068 ✅ |
| `..._imp_drc` | `Total Violations : 0` | **580** ❌ (318 = PG vs bond pad) |
| `..._imp_connectivity` | no `IMPVFC-200` | **329 opens**, file saturated at 1000 ❌ |
| `..._imp_antenna` | `No Violations Found` | **clean** ⚠️ (no diodes were inserted) |
| `..._imp_filler` | *no useful verdict — check the netlist* | **0 filler cells** ❌ |
| Calibre `make drc` | clean deck run | not signoff — cells are empty references ⚠️ |

Even a fully green column is **not** a signoff. Work through
[09 — Signoff checklist](09-signoff-checklist.md), which covers the checks this flow does
not run at all: metal fill, LVS, seal ring. Logical equivalence is a fourth case and no
longer belongs in that list — post-P&R LEC ran clean on 2026-08-08, but against a `_pnr.v`
that has since been superseded, and the RTL → synthesised leg has never completed. See
[13 §7](13-lec.md).

---

## Verified vs uncertain

**Verified** — read directly out of `baseline_2026-08-05/` this week:

- every excerpt quoted above, character for character
- DRC totals 580 / 539 / 41 `EndOfLine`, and the 398 / 318 / 47 blockage slices
- the layer histogram (264 M8, 156 M9, …)
- `check_connectivity` saturation at exactly 1000, and the uncapped 202 / 329 / 1328
- zero `FILLER` instances in the shipped baseline netlist
- `TCLCMD-1130` in all six timing summaries and no other `**ERROR` in any report
- `IMPSE-110` proving the in-Innovus Calibre path is dead
- `gds_merge_list` containing exactly the 8 memory macros

**Uncertain / not verified:**

- **What a clean `check_filler` looks like.** Every report available is from a run where
  filler insertion failed, so the "good" output format is unknown. Verify against the
  first successful run and update this page.
- **The exact default cap value.** 1000 is inferred from the summary landing on exactly
  1000, and from raising `-error`/`-warning` to 200000 producing more. The tool's
  documented default has not been confirmed with `check_connectivity -help`.
- **Whether `-error 200000 -warning 200000` is the intended way to lift the cap**, or
  merely one that works. It is what the project's own experiment runs used.
- **Calibre output formats.** No completed Calibre run exists in `baseline_2026-08-05/`,
  so this page describes how to launch it but not how to read its results database.
- **The DRV violation counts have not been triaged.** 1243 max-transition violations are
  reported as a fact, not as an understood problem.

---

Prev: [06 — Fill, antenna, bond pads](06-fill-antenna-bondpads.md) ·
Next: [08 — Debugging](08-debugging.md) ·
[Index](00-index.md)
