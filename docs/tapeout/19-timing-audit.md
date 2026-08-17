# 19 — Timing and Constraint Integrity Audit

**Date:** 2026-08-07
**Design:** `nanosoc_eth_chiplet_pads`, TSMC 65 nm LP, Innovus 21.11-s130_1 / Genus 21.15-s080_1
**Scope:** constraint coverage, exceptions, clock definitions, uncertainty/derate, DRV.
**Reference run:** `ASIC/genus-innovus/baseline_2026-08-06/` (complete: place → CTS → route → post-route hold).

Trigger: on 2026-08-06 a defect was found in which every hold check in the design lost
1.076 ns to a clock source-latency asymmetry, hidden because `report_timing_summary`
prints no hold section. This audit assumed more was hidden. It was.

**Everything below labelled VERIFIED was reproduced from files on disk.** No EDA tool was
invoked — a P&R run holds the seats. Each finding carries the command that would confirm
or close it in a tool session.

---

## Summary of results

| # | Finding | Status | Risk |
|---|---|---|---|
| R1 | No `set_timing_derate` anywhere; OCV enabled with zero derating | VERIFIED | **Blocker** |
| R2 | 6 of 9 clocks carry zero clock uncertainty, setup *and* hold | VERIFIED | **Blocker** |
| R3 | `rmii_ref_clk` still has the unqualified-uncertainty bug that was fixed for `clk`/`swdclk` | VERIFIED | **High** |
| R4 | Generated-clock source latency broken on all 5 generated clocks (same failure class as the 08-06 defect) | VERIFIED | **High** |
| R5 | Signoff is single-corner: one setup view, one hold view | VERIFIED | **High** |
| R6 | 13 top-level port directions carry no I/O delay, including `QSPI_nCS` | VERIFIED | **High** |
| R7 | Scan network is timed as functional logic and is unreachable in silicon | VERIFIED | **High** |
| R8 | Pad multicycle is setup-only with no paired hold | VERIFIED | Medium |
| R9 | `check_timing` / `report_analysis_coverage` have never been run | VERIFIED | Medium |
| R10 | `report_timing_summary` hold suppression has a named root cause and a one-line fix | VERIFIED | Medium |
| R11 | No drive/load models on any port; clock tree root slew ≈ 0 | VERIFIED | Medium |
| R12 | 153 max_tran nets are a hold-repair side-effect, not a routing problem | VERIFIED | Medium |
| R13 | The `last_push_flags` CDC multicycle is dead — overridden by a clock group | VERIFIED | Low (safe outcome, misleading source) |
| R14 | Power intent defines no power_state; IO/core level-shift boundary unmodelled | VERIFIED | Low (timing), refer to power owner |
| — | Clock groups, clock periods, SWDCLK multicycle block, setup closure | **CLEAN** | — |

Two corrections to the briefing this audit was given:
`constraints.sdc` sets `CLK_ERROR` to **0.35**, not 0.25 (`inputs/constraints.sdc:21`,
confirmed in `outputs/nanosoc_eth_chiplet_pads_syn.sdc:950`). And hold numbers are *not*
only in the log — `report_timing -early` runs at every stage and writes
`reports/timing_*_early.rep`; those files are correct and were used here.

---

## R1 — No OCV derating exists anywhere in the flow (VERIFIED, blocker)

`scripts/cts_setup.tcl:72` enables OCV:

```
set_db timing_analysis_type ocv
```

There is **no `set_timing_derate` command anywhere**: not in `inputs/*.sdc`, not in
`scripts/*.tcl`, not in `scripts/nanosoc_eth_chiplet_pads.mmmc`, not in the Genus-emitted
`outputs/nanosoc_eth_chiplet_pads_syn.sdc`, and **zero occurrences in the 118,671-line run
log**. No AOCV/SOCV tables are loaded either.

Turning OCV on without derate factors only separates min from max delay calculation. It
applies **no variation margin**. The entire on-chip-variation budget of this tapeout is
therefore the clock uncertainty numbers — which, per R2, six of nine clocks do not have.

A 65 nm design normally carries at minimum a flat cell+net derate of roughly
`-early 0.95 / -late 1.05` on the data path and a tighter pair on the clock network, per
delay corner. There is nothing here.

```
# confirm (read-only, in any Innovus session on the DB)
report_timing_derate
report_analysis_views -view default_analysis_view_setup
```

```
# confirm from disk, no tool needed
grep -rn "set_timing_derate" ASIC/genus-innovus/{inputs,scripts,outputs}
grep -v '^@file' ASIC/genus-innovus/baseline_2026-08-06/logs/pnr_run_core70.log | grep -ci derate
```

---

## R2 — Six of nine clocks carry zero uncertainty, setup and hold (VERIFIED, blocker)

`outputs/nanosoc_eth_chiplet_pads_syn.sdc:950-957` contains the *complete* set of
uncertainty statements Innovus reads:

```
950 set_clock_uncertainty -setup 0.35 [get_clocks clk]
951 set_clock_uncertainty -hold 0.05 [get_clocks clk]
952 set_clock_uncertainty -setup 0.35 [get_clocks swdclk]
953 set_clock_uncertainty -hold 0.05 [get_clocks swdclk]
954 set_clock_uncertainty -setup 0.35 [get_clocks rmii_ref_clk]
955 set_clock_uncertainty -hold 0.35 [get_clocks rmii_ref_clk]
956 set_clock_uncertainty -rise_from [get_clocks swdclk] -rise_to [get_clocks clk] -setup 0.1
957 set_clock_uncertainty -rise_from [get_clocks clk] -rise_to [get_clocks swdclk] -setup 0.1
```

Three clocks are named. The other six — `QSPI_SCLK`, `QSPI_SCLK_o`, `D2D_RX_CLK_0`,
`D2D_TX_CLK_0`, `mii_rx_clk`, `mii_tx_clk` — get nothing. Generated clocks do **not**
inherit uncertainty from their master in SDC; they are separate clock objects.

This is not inference. Extracting the `Uncertainty` line from every path in the two
10,000-path exception dumps written by `4_pnr_route.tcl:46-47`:

```
HOLD  (timing_full_default_early.mtarpt)
  clk           uncertainty=0.050    9905
  QSPI_SCLK     uncertainty=(none)     95     <-- no Uncertainty line at all

SETUP (timing_full_default_late.mtarpt)
  clk           uncertainty=0.350    9936
  D2D_RX_CLK_0  uncertainty=(none)     43     <-- no Uncertainty line at all
  QSPI_SCLK     uncertainty=(none)     21
```

The worst case is **`D2D_RX_CLK_0`**. It is an *external, off-die* 100 MHz clock arriving
from the paired chiplet across a D2D link — the single highest-jitter clock in the system —
driving a 528-sink domain whose CCOpt-achieved skew is 0.116 ns against a 0.097 ns target
(`IMPCCOPT-1023`). It is being timed with **zero jitter and zero skew margin, on both
setup and hold**.

`mii_rx_clk` / `mii_tx_clk` are also material: 5,281 sinks between them.

```
# confirm
report_clocks
foreach c [all_clocks] { puts "$c [get_property $c uncertainty]" }
report_timing -late -to [get_clocks D2D_RX_CLK_0] -max_paths 5
```

---

## R3 — `rmii_ref_clk` still carries the exact bug that was fixed for `clk`/`swdclk` (VERIFIED, high)

`inputs/constraints.sdc:61-64` was deliberately corrected so hold gets `CLK_HOLD_ERROR`
(0.05) rather than the full oscillator-jitter `CLK_ERROR` (0.35), with a long comment
explaining that charging hold the full setup jitter caused the hold-buffer explosion.

`inputs/ethernet_constraints.sdc:24` was not:

```
24  set_clock_uncertainty $CLK_ERROR [get_clocks rmii_ref_clk]
```

No `-setup`, no `-hold`. SDC therefore applies it to both, and Genus emits it as such
(`syn.sdc:954-955`, above): **0.35 ns of hold uncertainty on the whole RMII domain — 7×
what `clk` is charged.**

`scripts/cts_setup.tcl:56-57` already recorded the consequence without connecting it to
this line: after hand-patching `clk`, *"the worst path relocated to `rmii_ref_clk`"*.

Fix is one line, mirroring the `clk` treatment:

```tcl
set_clock_uncertainty -setup $CLK_ERROR      [get_clocks rmii_ref_clk]
set_clock_uncertainty -hold  $CLK_HOLD_ERROR [get_clocks rmii_ref_clk]
```

Note this must also be decided for `mii_rx_clk` / `mii_tx_clk`, which today get zero (R2).

---

## R4 — Generated-clock source latency is broken on all five generated clocks (VERIFIED, high)

This is the **same failure class as the 2026-08-06 defect**: CTS builds a tree to one
insertion delay, STA measures the path against a different one.

Innovus says so directly, five times (`TA-1018`), once for each generated clock:

> A source latency path to the generated clock **D2D_TX_CLK_0** through source pin
> `.../u_wlink/pad_clk_tx` to target pin `TL_CLK_TX` **cannot be found. Timing analysis will
> use 0 ns source latency** for the generated clock and will interpret the master clock
> based on the polarity at the master clock source pin.

Same message for `QSPI_SCLK`, `QSPI_SCLK_o`, `mii_rx_clk`, `mii_tx_clk`.

And three of them are defined on **module ports**, which CCOpt does not support
(`IMPCCOPT-2248`, ×3):

> Clock **mii_tx_clk** has a source defined at module port
> `.../u_rmii_to_mii/mtx_clk`. CCOpt does not support module port clocks and will consider
> the clock to be sourced at `.../u_rmii_to_mii/mtx_clk_reg/Q`. **This may lead to clock
> latency differences between CCOpt and timing analysis.** Consider changing the clock
> source in the SDC file.

Note the detail in the `mii_rx_clk` instance of that message: CCOpt re-sources
**`mii_rx_clk`** at **`mtx_clk_reg/Q`** — the *TX* register, not the RX one. Worth an
explicit check that this is a message-formatting artefact and not a real mis-attribution.

Root cause is the SDC form. `inputs/ethernet_constraints.sdc:29-30` and
`inputs/qspi_constraints.sdc:2-3` define generated clocks on hierarchical module ports
rather than on the output pin of the cell that actually drives them, which also raises
`TCLCMD-1531` ×15 (*"'create_generated_clock' has been applied on hierarchical pin"*).

Suggested form (names to be confirmed against the netlist):

```tcl
create_generated_clock -name mii_rx_clk -source [get_ports RMII_REF_CLK] -divide_by 2 \
    [get_pins ${RMII2MII}/mrx_clk_reg/Q]
```

Two further clock-definition warnings in the same family, both benign but worth knowing:
`IMPCCOPT-4144` — `D2D_TX_CLK_0` and `QSPI_SCLK_o` have source pins (`TL_CLK_TX`,
`QSPI_SCLK`) that are *input* pins, so CCOpt defines their trees under the corresponding
output pins instead.

```
# confirm
report_clock_trees -list_special_pins
report_clock_timing -type latency
grep -v '^@file' <pnr log> | grep -E "TA-1018|IMPCCOPT-2248|IMPCCOPT-4144"
```

---

## R5 — Signoff is single-corner (VERIFIED, high)

`scripts/nanosoc_eth_chiplet_pads.mmmc:198`:

```tcl
set_analysis_view -setup [list default_analysis_view_setup typical_analysis_view] \
                  -hold  [list default_analysis_view_hold  typical_analysis_view]
```

- **Setup** is checked at exactly one signoff corner: `tcbn65lpwc` (SS, 1.08 V, 125 °C) + `rcworst`.
- **Hold** is checked at exactly one signoff corner: `tcbn65lplt` (FF, 1.32 V, −40 °C) + `rcbest`.
  Confirmed by the dump banner: `{PVT Mode} {min} {Voltage} {1.320} {Temperature} {-40.000}`.
- `typical_analysis_view` (TT/1.20 V/25 °C) is present in both lists but is not a signoff corner.

Missing, all of which are standard for a 65 nm production signoff:

- **Hold at the slow corner** (SS libs + rcworst/rcbest). Hold is not a fast-corner-only
  check once clock skew is real — a slow, high-skew corner can hold-fail where the fast
  corner passes.
- **Setup at rcbest** (clock reconvergence / useful-skew inversion).
- **`tcbn65lpwcl`** (SS, 1.08 V, −40 °C). TSMC ships it for this library precisely because
  temperature inversion is not zero at 65 nm LP. Not currently loaded anywhere.

Also dead code worth cleaning: `.mmmc:193-194` creates `typical_analysis_view_setup` and
`typical_analysis_view_hold` on `default_delay_corner_ocv` (early = `tc_min`, late =
`tc_max`) — the only genuinely two-sided delay corner in the file — and then never
references them in `set_analysis_view`. The one corner set up to do split min/max analysis
is unused.

```
# confirm
report_analysis_views
```

---

## R6 — Thirteen top-level port directions carry no I/O delay (VERIFIED, high)

Cross-referencing the top module declaration
(`outputs/nanosoc_eth_chiplet_pads_gate.v:596229`) against every `set_input_delay` /
`set_output_delay` in `syn.sdc`:

**Inputs with no `set_input_delay`:** `SE`, `I2C_SCL`, `I2C_SDA`, `RMII_MDIO`
**Outputs with no `set_output_delay`:** `QSPI_nCS`, `RMII_MDC`, `RMII_MDIO`, `I2C_SCL`,
`I2C_SDA`, `SWDIO`, `HOSTIO4_P1[6:0]`

Ranked by what it costs in silicon:

- **`QSPI_nCS` — the boot-flash chip select.** `QSPI_IO[3:0]` is fully constrained against
  `QSPI_SCLK` / `QSPI_SCLK_o` (min 0 / max 1 ns, `syn.sdc:719-750`), but the chip select
  that frames every one of those transfers is timed against nothing. Flash devices specify
  nCS setup/hold to SCLK. This path is currently unbudgeted and unoptimised. If the boot
  flash interface fails at speed, this is the first place to look.
- **`SWDIO` and `HOSTIO4_P1[6:0]` output directions.** Both are `inout` and both received
  an `set_input_delay` only (`constraints.sdc:92-93`). The core→pad direction — SWD read
  data back to the debugger, and the host I/O outbound path — is entirely untimed. SWD is
  the bring-up path for this chiplet.
- `RMII_MDC` / `RMII_MDIO` (MDIO management, 2.5 MHz) and `I2C_SCL` / `I2C_SDA`
  (open-drain, ≤400 kHz) are low-speed enough that the practical risk is small, but they
  are genuinely unconstrained and should be given a nominal budget so they appear in
  coverage.
- `SE` — see R7.

```
# confirm
check_timing -verbose            # reports unconstrained endpoints directly
report_analysis_coverage -status untested -verbose
report_timing -late -to [get_ports QSPI_nCS]
```

---

## R7 — The scan network is timed as functional logic, and it is unreachable in silicon (VERIFIED, high)

This is where the area and density went, and density is what blocked DRV repair (R12).

**The netlist is full of scan flops.** From `outputs/nanosoc_eth_chiplet_pads_gate.v`:

```
15,096  SDFCNQD1        6,826  SDFQD0
 4,096  SDFND1            370  SDFSNQD1     = 26,388 scan flops
```

with `.SI` and `.SE` wired to real nets, e.g.
`SDFCNQD1 Pause_reg(.CDN (n_19), .CP (MTxClk), .D (Pause), .SI (n_38), .SE (n_99), .Q (Pause));`

Innovus flags it at ERROR severity (`IMPSP-9099`, ×2):

> Scan chains exist in this design but are not defined for 30.55% flops. **Placement and
> timing QoR can be severely impacted in this case!**

**But scan enable reaches nothing.** The SE pad's core-side output is unconnected:

```
PDDW04DGZ_G uPAD_SE_I(.REN (1'b0), .I (1'b0), .OEN (1'b1), .PAD (SE), .C (UNCONNECTED6082));
```

and the scan-enable input is unconnected at every hierarchy level examined —
`.sys_scanenable (UNCONNECTED_HIER_Z994)` on the SoC instance (line 600280),
`.sys_scanenable (UNCONNECTED_HIER_Z94)` on `u_network_core` (line 197897). By contrast
`TEST` *is* connected: `uPAD_TEST_I(... .PAD (TEST), .C (soc_sys_testmode))`.

**And there is no `set_case_analysis` anywhere** — 0 occurrences across `inputs/`,
`scripts/`, `asic-flows/`, and `syn.sdc`.

So both the `D→Q` and the `SI→Q` arc of all 26,388 scan flops are timed, and the scan-shift
paths — short, hold-critical, flop-to-adjacent-flop — are being repaired as if functional.
Endpoint census of the two 10,000-path dumps:

```
SETUP worst 10,000:   D 4,612  |  SE 3,152  |  SI 1,826      -> 49.8% scan-related
HOLD  worst 10,000:   D 7,223  |  SI 2,523  |  SE   121      -> 26.4% scan-related
```

**Half the setup-critical population and a quarter of the hold-critical population is scan
logic that cannot be exercised on this die.** The design paid for it in area and density:
231,550 instances and 92.17% utilisation at the end of post-route hold repair.

The remedy is a `set_case_analysis` pinning the scan-enable net to its functional value.
Because the SE port is disconnected, it must be applied to the internal net, not the port —
and the DFT owner should confirm whether the disconnection is intentional (the comment at
`constraints.sdc:43` says *"scan_clk: tied 1'b0; the scan chain is not bonded"*, which is
consistent, but `SE` is nonetheless a bonded pad going nowhere).

```
# confirm
report_scan_chains
get_property [get_pins <soc>/sys_scanenable] net
report_timing -early -to [get_pins -hierarchical */SI] -max_paths 20    # SI endpoints
report_analysis_coverage -status untested
```

---

## R8 — The pad multicycle is setup-only with no paired hold (VERIFIED, medium)

`inputs/constraints.sdc:79`:

```tcl
set_multicycle_path 2 -from uPAD*/* -to uPAD*/*
```

Genus emits it (`syn.sdc:148-696`, a single 548-object statement) as:

```
set_multicycle_path -from [list <274 pad pins>] -to [list <274 pad pins>] -setup -end 2
```

**`-setup -end 2` with no companion `-hold ... 1`.** Compare the SWDCLK block immediately
above it, which is correct:

```
144 set_multicycle_path -from [get_clocks swdclk] -to [get_clocks clk] -setup -end 2
145 set_multicycle_path -from [get_clocks swdclk] -to [get_clocks clk] -hold  -end 1
```

A setup multiplier of 2 without a hold multiplier of 1 leaves the hold check one cycle
after the launch edge — it demands the data be held for a **full clock period (10 ns)**
rather than the normal same-edge hold. That is the classic multicycle mistake, and it
manufactures hold violations rather than hiding them.

Breadth: 96 pad instances × 5 pins (`C`, `I`, `OEN`, `REN`, `PAD`) on **both** `-from` and
`-to`, plus 68 supply pins (`VDD`/`VSS`/`VDDPST`/`VSSPST`) that have no timing arcs at all —
`TCLCMD-917` ×20 and `TCLCMD-513` ×20 (*"could not find a matching object ...
'uPAD_VDDIO_B_0/VDDPST'"*).

**Currently mitigated by accident.** `reports/timing_summary_05_route_opt.rep` shows
`Group : in2out  N/A  N/A  0` — there are zero input-to-output paths in this design, so the
exception's intended target set is empty and it is a no-op today. It should still be
deleted or rewritten narrowly and paired, because it is a live hold trap the moment any
pad-to-pad feedthrough is added, and because `-from` on a clock-network pad pin
(`uPAD_CLK_I/C`) is a breadth the author almost certainly did not intend.

```
# confirm the exception is inert
report_timing_summary                       # Group : in2out must stay N/A
report_timing -early -from [get_pins uPAD_*/C] -to [get_pins uPAD_*/I] -max_paths 50
```

---

## R9 — Constraint coverage has never been machine-checked (VERIFIED, medium)

`check_timing`, `report_analysis_coverage` and `report_constraint` appear **nowhere**: not
in `asic-flows/Cadence/{1_synthesis,2_pnr_setup,3_pnr_clock,4_pnr_route,procs}.tcl`, and
zero occurrences in the run log.

`check_timing` is the single command that would have surfaced R6 (unconstrained ports) and
R7 (unconstrained scan enable) on the first run, in seconds. Its absence is the reason a
manual audit was needed to find them.

Recommend adding to `procs.tcl` alongside the existing reports:

```tcl
check_timing -verbose                 > $REPORT_DIR/check_timing_${name}.rpt
report_analysis_coverage -verbose     > $REPORT_DIR/coverage_${name}.rpt
```

---

## R10 — `report_timing_summary` drops hold: named cause, one-line fix (VERIFIED, medium)

The 08-06 defect was invisible because `report_timing_summary` emits no hold section. That
is not a tool quirk — Innovus says exactly why, and it is the first line of **all six**
`reports/timing_summary_*.rep` files:

> **ERROR: (TCLCMD-1130):** The `-late` and `-early` options to the `report_timing_summary`
> command can only be specified together when the timing system is in simultaneous setup
> and hold mode. You can use `set_global timing_enable_simultaneous_setup_hold_mode true`
> to enable this mode for timing analysis only. All non-timing commands are disabled while
> the system is in simultaneous setup/hold mode. **Ignoring `-early` and using `-late`
> alone.**

Because `set_analysis_view` declares both a setup list and a hold list (`.mmmc:198`),
`report_timing_summary` attempts to report both, is refused, and silently degrades to setup
only — then labels its closing line `timing.setup.wns`. Hence "WNS +0.079, 0 failing
endpoints" reading as a green board while hold sat at −1.167 / −66,212 ns.

Fix, in `procs.tcl`, noting the mode disables non-timing commands so it must be turned back
off:

```tcl
set_global timing_enable_simultaneous_setup_hold_mode true
report_timing_summary > $REPORT_DIR/timing_summary_${name}.rep
set_global timing_enable_simultaneous_setup_hold_mode false
```

The per-stage `report_timing -early` files (`reports/timing_*_early.rep`) are and were
correct — `timing_05_route_opt_early.rep` shows the defect plainly. The summary was the
only lying report.

---

## R11 — No drive or load model on any port; clock tree root slew ≈ 0 (VERIFIED, medium)

`syn.sdc` contains **zero** `set_driving_cell`, `set_input_transition`, `set_drive` and
`set_load` statements. Innovus reports the consequence itself (`IMPCCOPT-4313`):

> Innovus cannot determine the drive strength of **CLK**, which drives the root of
> clock_tree `clk`. To time this clock tree, Innovus will assume that it is driven by a
> driver cell with **a fixed output slew of 0.000 and a maximum driven capacitance of
> 0.000.** It is recommended that you set the `cts_clock_tree_source_driver` attribute…

Same for `RMII_REF_CLK`. Visible in the real path — the launch clock path of the worst hold
path in `timing_full_default_early.mtarpt`:

```
PORT {} {CLK} {R} ... slew {0.004} load {1.382} arrival {-1.076}
INST {uPAD_CLK_I} {PAD}->{C} {PDDW04DGZ_G} delay {0.366} slew {0.030}
```

A 2.5 V IO pad receiving a board-level oscillator sees a slew in the hundreds of
picoseconds to nanoseconds, not 4 ps. The 0.366 ns pad delay — and every input pad delay in
the design — is computed at an unphysical input slew, and is therefore optimistic. On the
output side, `set_max_capacitance 3 [all_outputs]` (`constraints.sdc:133`) is effectively
vacuous because no `set_load` gives the ports any external capacitance to violate.

Related, same root cause: `IMPCCOPT-1033` — *"Did not meet the max_capacitance constraint
of 0.000 pF below the root driver"* for `clk`, `rmii_ref_clk`, `swdclk`, `D2D_RX_CLK_0`.

Separately and benignly, the four top-level clock port nets (`CLK`, `SWDCK`,
`RMII_REF_CLK`, `TL_CLK_RX`) are unrouted at CTS time and their RC cannot be extracted
(`IMPCCOPT-2276`, `IMPCCOPT-2169`, `IMPCCOPT-2171`, `IMPCCOPT-1304`) — expected for a
pad-ring top level, but it does mean the clock source segment is estimated, not extracted.

---

## R12 — The 153 max_tran nets are a hold-repair side-effect, and are a signoff blocker as they stand (VERIFIED, medium)

Final state: **153 max_tran nets / 3,227 pins, worst −3.397 ns**; 213 max_cap nets, worst
−0.189 pF; density 92.167%.

The log dates their arrival precisely:

| Stage | log line | max_tran nets (terms) | worst |
|---|---|---|---|
| post-CTS opt / hold | 27610, 27820, 28029 | 0 (0) | 0.000 |
| after route | 30278 | 5 (11) | −0.086 |
| **after "Finish Post Route Hold Fixing"** (94,228 insts touched) | 30541 | **151 (3,666)** | **−3.736** |
| mid DRV recovery | 31292 | 495 (5,120) | −3.397 |
| final | 32408 | 153 (3,227) | −3.397 |

The DRV recovery table at line 30456 shows it starting from **4,919 nets / 64,961 terms** —
i.e. post-route hold repair broke DRV on ~5,000 nets and recovery clawed back all but 153.
Recovery then hit the density wall: *"44 net(s): Could not be fixed because of exceeding max
local density"* (plus 6, 2, and more), at 92.17% utilisation.

Two structural facts about what can never be fixed here:
`Info: 601 clock nets excluded from IPO operation` and `Info: 48 io nets excluded` — DRV
optimisation does not touch clock or IO nets at all.

**They are not on the critical paths.** Scanning every `INST` slew field in the 10,000
worst setup paths finds only 3 pins above 1.0 ns, worst 1.859 ns at
`u_tidelink/u_chiplet_controller/u_wlink/g559692/Z` (OR2D1, fanout 47). So the 153 nets are
off-critical, high-fanout nets (3,227 pins / 153 nets ≈ 21 pins per net).

**Assessment:** a 65 nm signoff requires max_transition clean, so 153 nets is a blocker in
its current state — but it is a *derived* blocker. The causal chain is
fictitious-hold-violations → 37,407 hold buffers → 92% density → DRV repair blocked, and it
is already documented in `scripts/cts_setup.tcl:46-50`. Fixing R2/R3/R7 should collapse the
hold repair, drop density, and unblock DRV repair without any DRV-specific work. Re-measure
before treating this as an independent problem.

```
# confirm / characterise (which nets, clock or data)
report_constraint -drv_violation_type max_transition -all_violators
get_property [get_nets <net>] num_terminals
```

---

## R13 — The `last_push_flags` CDC multicycle is dead code (VERIFIED, low risk / high confusion)

`inputs/ethernet_constraints.sdc:74-85` builds a careful, RTL-verified argument for keeping
the `mii_rx_clk → clk` crossing **timed** as a 2-cycle multicycle rather than cutting it:

> The `mii_rx` → CLK direction is deliberately **LEFT TIMED** here because it carries the
> `eth_rx_cksum last_push_flags` data-with-toggle path we want to keep as a (relaxed)
> multicycle — see CDC 3.

`inputs/constraints.sdc:126-131` then cuts it anyway:

```tcl
set_clock_groups -asynchronous -name eth_chiplet_cdc \
    -group [get_clocks [list $EXTCLK QSPI_SCLK QSPI_SCLK_o]] \
    ...
    -group [get_clocks {rmii_ref_clk mii_rx_clk mii_tx_clk}] \
```

`clk` and `mii_rx_clk` are in different asynchronous groups, so **all** paths between them
are false. Clock groups outrank multicycle paths in SDC precedence, so the CDC-3 multicycle
(`syn.sdc:697-710`) never applies, and the CDC-2 targeted false paths (`syn.sdc:25-31`) are
redundant.

The *outcome* is safe — `ethernet_constraints.sdc:87-94` analyses this exact alternative and
concludes it is fine because "last_push_flags is held stable for a whole frame vs a
~2-cycle toggle resync". The design is in fact running that alternative. The problem is
purely that the source says the opposite: anyone reading `ethernet_constraints.sdc` will
believe a path is timed that is not. Either delete CDC 2+3 and the CDC-1 `-to clk`
direction as that note instructs, or split the clock group so the MCP lives.

The same precedence point applies to CDC 1 (`ethernet_constraints.sdc:56-57`) — both of
those `set_false_path` statements are subsumed by the clock group.

---

## R14 — Power intent incomplete across the 2.5 V IO / 1.2 V core boundary (VERIFIED, low for timing)

Reported for completeness; belongs to the power-intent owner rather than the timing owner.

- `IMPMSMV-3501` (ERROR): *"Input power intent (CPF/UPF) does not define
  power_mode/power_state. The always-on buffering is not supported since the tool needs the
  power_mode/power_state information to calculate the domain coverage."*
- `IMPTS-282` (×6): `PCLAMP1ANA_G`, `PCLAMPAC_G` and others *"have 'input_signal_level' and
  'output_signal_level' specified on pins … To mark this cell as level shifter, use
  'is_level_shifter' attribute."*

Together these mean the IO↔core level-shifting boundary is not modelled as such. Whether
that changes any timing arc needs the power owner's judgement; it is noted here because it
is the one remaining ERROR-severity class in the run that touches the timing engine.

---

## Clean bills

> ### ⚠ SUPERSEDED — the clock set has changed from 9 to 33 (noted 2026-08-17)
>
> **The clock-related clean bills below were correct when written and are correct
> about the run they name. They no longer describe the design.** The audit's
> reference run is `baseline_2026-08-06`; the current build is
> `ASIC/eth-chiplet/build/full-20260814/`, and between them the clock set nearly
> quadrupled.
>
> ```sh
> S=ASIC/eth-chiplet/build/full-20260814/outputs/nanosoc_eth_chiplet_pads_syn.sdc
> grep -c '^create_clock'            $S     # 4
> grep -c '^create_generated_clock'  $S     # 29   -> 33 total
> ```
>
> **This is not a case of the audit having been wrong.** The 08-07-era SDC
> (`ASIC/genus-innovus/runs/20260807T211107Z_route-eval-audit/outputs/`) carries
> 4 + 5 = **exactly the 9 clocks this section names**. The audit is a faithful
> dated record. It has been overtaken, and the delta is specific:
>
> **+24 generated clocks, all D2D word clocks** — `D2D_RX_WORD_CLK_0..7`,
> `D2D_RX_WORDN_CLK_0..7`, `D2D_TX_WORD_CLK_0..7` — which entered between
> 2026-08-07 17:48 and 2026-08-09 19:37 (mtimes of the two `*_syn.sdc`).
>
> Sink counts have moved by more than an order of magnitude on the D2D side
> (`build/full-20260814/reports/cts_clock_trees.rep`, "Clock Sink Summary",
> posedge-flop column):
>
> | Clock | This audit (08-06) | Current (08-14) |
> |---|---|---|
> | `clk` | 37,625 | **39,458** |
> | `D2D_RX_CLK_0` | 528 | **13,452** — ×25 |
> | `rmii_ref_clk` | 37 | **5,314** — ×144 |
> | `mii_rx_clk` | 5,281 (shared with `mii_tx_clk`) | **5,278** |
> | `swdclk` | 326 | **206** |
> | `QSPI_SCLK` | 433 | split across `clk_generator_for_QSPI_SCLK<1..6>`, 258 posedge + 173 negedge each |
> | `D2D_RX_WORDN_CLK_0` | *did not exist* | **8,963** |
> | `D2D_TX_WORD_CLK_0` | *did not exist* | **1,495** |
>
> **Do not quote the two clock clean bills below as current.** Specifically:
>
> - **"All 9 clocks appear in exactly one group"** — untested against 33. The
>   grouping was verified against a 9-clock set; 24 clocks have been added since
>   and their group membership is not established by anything in this document.
>   The conclusion that drew its force from it — *"no asynchronous crossing is
>   being timed as synchronous"* — is therefore **unverified for the current
>   build**, not disproven.
> - **"All 9 clock definitions are self-consistent"** — the 9 named are still
>   internally consistent; the 24 word clocks are unexamined here.
>
> One further caveat for anyone re-deriving this: only **21 of the 33** clocks
> get a CTS tree in `cts_clock_trees.rep`. `D2D_RX_WORD_CLK_0..7` and
> `D2D_TX_WORD_CLK_1..7` appear in the SDC but draw no tree, so a census taken
> from the CTS report alone will silently miss them — the "none is zero, no clock
> is defined on a pin with no fanout" check below needs redoing against the SDC,
> not the CTS report.
>
> **R2 in the summary table ("6 of 9 clocks carry zero clock uncertainty") rests
> on the same stale denominator and needs re-measuring against 33.**
>
> Everything below this banner is preserved unaltered as the 2026-08-07 record.

Areas checked and found sound. These are results, not gaps.

**Clock grouping is correct and correctly ordered.** The 5-group
`set_clock_groups -asynchronous` (`constraints.sdc:126-131`) is placed *after* the three
sourced IP SDCs, so every generated clock exists when it runs — a real ordering hazard,
handled. All 9 clocks appear in exactly one group (`syn.sdc:711-717`). **No asynchronous
crossing is being timed as synchronous**, which was the specific worry. The `$EXTCLK` ↔
`D2D_TX_CLK_0` cut is defensible given the `user_ref_clk` aliasing documented at
`constraints.sdc:99-120`, and the `D2D_RX_CLK_0` cut is flagged in-source as the
conservative bring-up cut to narrow at signoff.

**All 9 clock definitions are self-consistent.** `clk` 10.0 ns; `swdclk` 40.0 ns (4×);
`rmii_ref_clk` 20.0 ns (50 MHz RMII); `mii_rx_clk`/`mii_tx_clk` = ÷2 = 25 MHz — matching
100BASE-TX; `D2D_RX_CLK_0` 10.0 ns; `QSPI_SCLK` = clk÷2; `QSPI_SCLK_o` = ÷1 at the pad. Every
generated clock names a master that resolves (`Using master clock 'rmii_ref_clk' for
generated clock 'mii_tx_clk'`, etc.). Sink counts are plausible and none is zero:
`clk` 37,625 · `mii_rx_clk`/`mii_tx_clk` 5,281 shared · `D2D_RX_CLK_0` 528 · `QSPI_SCLK` 433 ·
`swdclk` 326 · `rmii_ref_clk` 37. No clock is defined on a pin with no fanout.
(The *latency modelling* of the generated clocks is broken — R4 — but the definitions
themselves are right.)

**Clock-domain checks pass.** `min_period` worst 6.903 ns against a 10 ns period,
`min_pulse_width (endpoints)` worst 5.762 ns, both 0 failing endpoints.

**The SWDCLK ↔ CLK exception block is textbook** (`constraints.sdc:70-76`,
`syn.sdc:144-147`): 2-setup paired with 1-hold in both directions, plus a deliberate
`-hold` false path one way. This is the correct pattern that R8 lacks.

**No exception silently failed to match.** Every one of the ethernet CDC-2 targeted false
paths resolved through Genus's hierarchy flattening and is present in `syn.sdc:25-31` and
`32+` with correct post-flattening names. The only unmatched-object warnings in the run
(`TCLCMD-513`, `TCLCMD-917`) come from the pad wildcard of R8.

**Setup is genuinely closed** at the corner it is checked at: WNS +0.079 ns, TNS 0.000, 0
failing endpoints, reg2reg WNS +0.079 — on wc libs + rcworst. That number is real; it is
just not the whole story, and it was never a hold number.

**The hold defect is fully characterised and is a single mechanism, not a population of
problems.** Of the 10,000 worst hold paths, **9,999 carry launch-side Source Insertion
Delay −1.076 ns and one carries −1.108 ns, with the capture side 0.000 in every single
case**; 9,904 are `clk→clk`. Backing the asymmetry out of the reported worst path
(−1.167) leaves ≈ −0.09 ns, consistent with the −0.116 ns that `typical_analysis_view`
reports. So roughly 0.1 ns of hold violation is real and needs ordinary repair; the rest
was never there.

---

## Status of the in-flight fix (VERIFIED — mechanism yes, outcome unknown)

`scripts/cts_setup.tcl:72` moves `set_db timing_analysis_type ocv` to *before* `ccopt_design`.
The documented regression check now passes:

```
$ grep -v '^@file' logs/cts_ocvfirst.log | grep -A1 'View: default_analysis_view_hold' | grep -c ' -max '
16
$ ... same on baseline_2026-08-06/logs/pnr_run_core70.log
0
```

ccopt now writes both `-min` and `-max` source latency for `swdclk`, `D2D_RX_CLK_0`, `clk`
and `rmii_ref_clk` in the hold view. **The mechanism is fixed.**

The outcome is not yet known. `logs/cts_hold_compare.txt` shows post-CTS hold essentially
unchanged (−0.581 / 6,110 paths vs −0.577 / 5,963) — which is *expected*, because the old
flow only enabled OCV after routing, so post-CTS was never where the 1.076 ns appeared.
`logs/route_ocvfirst.log` contains no Hold mode table yet; the route stage is still running.

**Do not record this fix as validated until a post-route Hold mode table exists.** The check
to run on the finished log:

```bash
grep -v '^@file' logs/route_ocvfirst.log | grep -A8 'Hold mode'
# expect WNS to move from -1.167 toward ~-0.1, and violating paths from 96,545 to ~10^3
```

---

## Recommended order of work

1. **R2 + R3** — clock uncertainty. One-line-per-clock edits in
   `inputs/ethernet_constraints.sdc`, `inputs/qspi_constraints.sdc`,
   `inputs/tidelink_constraints.sdc`. Largest correctness gain per character changed, and
   `D2D_RX_CLK_0` at zero margin is the single most exposed number in the build.
2. **R7** — `set_case_analysis` on the scan enable. Removes ~50% of the setup-critical and
   ~26% of the hold-critical population, which should collapse density and unblock R12.
3. **R10 + R9** — make the reports honest before the next 5-hour run, so the next defect is
   not found by hand.
4. **R1** — add derates. This will *reopen* setup, so sequence it after 1–3 and budget for it.
5. **R4** — re-source the generated clocks onto driver output pins.
6. **R6** — `QSPI_nCS` first, then the remaining 12 port directions.
7. **R5** — add the missing corners. This is the largest amount of runtime and should be
   scheduled, not squeezed in.
8. **R8, R13** — exception hygiene. No silicon risk today; both are traps for the next
   engineer.

Items 1–3 and 8 are constraint-file edits with no runtime cost beyond the re-run. Items 4–7
change the answer and need a full run each to evaluate.

---

*Audit performed read-only against files on disk. No EDA tool was invoked and nothing under
`work/`, `outputs/`, `reports/`, `logs/` or `baseline_*/` was modified.*
