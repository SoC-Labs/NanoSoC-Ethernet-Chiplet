# Cortex-M0+ / AHB-HREADY timing closure — constraint proposal

> **Vendor-path note.** Paths here are given via the variables `ASIC/common.mk`
> defines (`$ARM_IP_LIBRARY_PATH`, `$CMSDK_DIR`, `$ARM_CORTEXM0PLUS_IP_PATH`)
> and vendor bundles by their ROLE rather than their revision-coded release
> name, per `ASIC/asic-toolkit/VENDOR_COLLATERAL.md`. Resolve them with
> `ASIC/tech_wrappers/tsmc65/scripts/pdk_paths.sh`.


**Status: PROPOSAL. Nothing here has been applied.** No SDC, floorplan, flow script or
RTL file was modified in producing this document. Every number below is quoted from a
file on disk, with the path given, or is a derived quantity with its arithmetic shown.

Written 2026-08-19/20 against the Arm Cortex-M0+ Cadence reference implementation flow
(`the M0+ Cadence reference-methodology bundle`), which this project uses none of.

---

## 0. Ranking, up front

| # | Proposal | Expected gain on WNS | Risk | Reversible | Verdict |
|---|---|---|---|---|---|
| **1** | **Diagnostic re-measure**: STA at Arm's uncertainty + path grouping on the HREADY loop. Ship nothing. | 0 (measures, does not fix) | **none** | n/a | **Do this first, today** |
| **2** | **Setup uncertainty 0.35 → 0.20 on `clk` only**, paired with enabling SI analysis | +0.150 ns (21% of −0.715) | medium — see §4.4 | yes, one line | Defensible *only* with the SI pairing |
| **3** | **`set_max_transition` / `set_max_fanout` on `[current_design]`** (Arm ships both; we ship neither) | +0.05…0.15 ns, unmeasured | low | yes | Cheap, Arm-sanctioned, modest |
| **4** | **Soft placement guide around each CPU** (Arm IIM §6.3) | ≤ +0.03 ns on the measured path | medium — PG re-phase | yes | Low leverage *on this path*; may help the aggregate |
| **5** | **CMSDK `hreadyout → HREADY` `set_max_delay`** | n/a | **high** | — | **Do not apply.** It is a block-IO artefact, not a real budget. §5 |
| **6** | **SPECHTRANS** | **zero** | high | — | **Refuted.** `fault_q` is in both cones. §6 |

The single most useful thing in this document is not a constraint. It is §2: **47 of the
50 worst paths launch at one flop and 33 of the 50 end in one register file.** The TNS is
not diffuse. Treat it as two cones, not as "the design is 7% slow".

---

## 1. Corrections to the brief this work was commissioned from

Five of the premises are wrong or attributed to the wrong run. They do not invalidate the
task, but three of them change the answer.

### 1.1 The `gdsrun-20260819` P&R reports are not in this repository

`ASIC/eth-chiplet/build/gdsrun-20260819/` in this tree contains **six GLS files and
nothing else**. The strings `0.746` and `1678` appear nowhere in this working tree. The
real reports are in a sibling worktree:

```
/home/dam1n19/SoCLabs/gds-run-20260819/ASIC/eth-chiplet/build/gdsrun-20260819/reports/
    timing_summary_05_route_opt.rep        <- WNS -0.746 / TNS -378.163 / FEP 1678
    timing_05_route_opt_late.rep           <- the 50 worst paths
    cts_uncertainty.rep  cts_derate.rep  cts_clock_skew.rep
```

Anyone re-deriving these numbers inside this repo will find nothing and conclude the run
did not happen.

### 1.2 The quoted path-group split belongs to `full-20260814`, not to `gdsrun-20260819`

| Group | quoted in brief | `full-20260814` (actual) | `gdsrun-20260819` (actual) |
|---|---|---|---|
| ALL | −0.746 / −378 / 1678 | −0.715 / −354.123 / 1429 | −0.746 / −378.163 / 1678 |
| reg2reg | −0.715 / 1299 | **−0.715 / 1299** | −0.746 / 1546 |
| ClockGate | −0.654 / 130 | **−0.654 / 130** | −0.674 / 132 |
| in2reg | +2.435 / 0 | **+2.435 / 0** | +2.398 / 0 |
| reg2out | +5.039 / 0 | **+5.039 / 0** | +4.954 / 0 |

The headline triple is gdsrun's; the four group rows are `full-20260814`'s, five days
older. Source: `ASIC/eth-chiplet/build/full-20260814/reports/timing_summary_05_route_opt.rep`.

### 1.3 `core_fault_q` is not `gdsrun-20260819`'s launch flop

`core_fault_q` occurs **zero times** in any gdsrun-20260819 path report. That run's worst
path launches at `..._u_top_u_sys_u_core_iaex_q_reg[6]/CP` and ends at a QSPI APB register
`u_qspi_flash_0_u_top_ahb_qspi_u_apb_qspi_regs_reg13_reg[0]/D`.

The `core_fault_q` story is `full-20260814`'s, and it is correct there — see §2. Both
statements are true about different runs. **This document analyses the `core_fault_q`
population, because that is the one that was characterised, and says so.** If the decision
is to be made against gdsrun, §2 must be repeated on gdsrun's report; the *method* carries
over, the *numbers* do not.

### 1.4 "42 of 50 end outside the CPU" — measured, and the real distribution is far more useful

Classified from `full-20260814/reports/timing_05_route_opt_late.rep`:

| Endpoint | count |
|---|---|
| **`u_tidechart/u_tidechart_controller/u_apb_regs/cost_rf_r_reg[N][15]/D`** | **33** |
| inside CPU0 (`u_chip_core_u_cpu_0/...`) | 7 |
| `u_tidelink/...` | 5 |
| an ICG enable (`cg_RC_CG_HIER_INST138/RC_CGIC_INST/E`) | 3 |
| DMA-250 | 2 |

Two thirds of the worst 50 land in **one 32×16 register file**, always on **bit 15**. Its
RTL is `tidechart/src/rtl/tidechart_apb_regs.sv:307`, written from two sources — a hardware
update at :476 and an APB write at :573 whose *write address is taken from the write data*
(`cost_rf_r[apb_pwdata[20:16]] <= apb_pwdata[15:0]`). That structure puts a 32-way decode
of the data bus in front of every entry's next-state mux. It is worth an RTL look
independent of anything in this document.

### 1.5 "Posedge-only design" — **false**, and this is the correction that matters most

`ASIC/genus-innovus/inputs/constraints.sdc` hedges its own uncertainty argument:

> "If this design is genuinely posedge-only, most of the 0.35 ns is buying margin against a
> mechanism that cannot reach it"

It is not. Enumerating every negative-edge cell in `tcbn65lpwc.lib` (`clocked_on : "(!CPN)"`
— 28 cell types) and counting instances in
`ASIC/genus-innovus/baseline_2026-08-07/outputs/nanosoc_eth_chiplet_pads_pnr.v`:

> **⚠ COUNT CORRECTION, measured 2026-08-20 by the coordinator.** The figure
> "5,251 negedge flops" below does NOT reconcile. Counting `.CPN` instantiations
> — the negative-edge clock pin, which is what actually makes a flop negedge in
> `tcbn65lp` — gives **182** in `full-20260814/..._gate.v`, **185** in
> `gdsrun-20260819/..._pnr.v`, and **237** in `bscan-probe/..._pnr.v` (the extra
> ~50 being this branch's boundary-scan update stages). That is ~25x smaller.
>
> **The structural conclusion survives and is the part that matters:** negedge
> flops DO exist, none of them are on `clk`, and `$CLK_ERROR` is shared across
> `clk`/QSPI/RMII/D2D — so a global edit to it is still the wrong move and any
> uncertainty change must be per-clock. But the MAGNITUDE claims built on 5,251
> (and the 4,892-in-`u_deskew` split) are not established and must not be quoted.
> Re-measure by `.CPN` before relying on any number in this section.

```
total negedge-triggered flops: 5,251
  SDFND1   4,096      DFNCND1    929      DFND1  168      DFNSND1  45      SDFNCND1  13
```

Attribution:

| Where | count | clock | RTL |
|---|---|---|---|
| `u_deskew_*` (D2D RX lane deskew FIFO) | 4,892 | D2D RX word clocks | — |
| `u_qspi_flash_0_.../u_qspi_controller_*` | 174 | **`negedge QSPI_SCLK_i`** | `tidelink/imp/fpga/eth_chiplet_ip/src/qspi_controller.sv:427,517` |
| TideLink lane sync/debug (`dbg_raw_word_q`, `sync_lane_live_q`, …) | 185 | D2D RX domain | — |

**None of them is on `clk`.** So the duty-cycle-distortion argument survives — *for `clk`
only*, which is exactly where 100 % of the failing endpoints are. But it dies for
`QSPI_SCLK` and for the D2D RX word clocks, which today are charged the same 0.35 by the
same variable. Any uncertainty change must therefore be **per-clock**, never a global edit
to `$CLK_ERROR`. The brief's framing invited exactly the global edit.

---

## 2. The measured shape of the problem

All from `ASIC/eth-chiplet/build/full-20260814/reports/timing_05_route_opt_late.rep`,
Path 1 (WNS −0.715).

**Control row first** (per the "report-column misread" lesson): summing the *Delay* column
gives **11.233 ns** against the header's `Data Path: + 11.230`, and the last row's arrival
is **10.329**, matching the endpoint row. The columns are read correctly. (A first pass
summed the *Fanout* column and produced "sum 300.000, max 25.000" — the launch flop's
fanout is 25, which is what gave it away.)

```
cell stages          : 95
sum of stage delays  : 11.233 ns   (header: 11.230)
mean stage delay     : 0.118 ns
largest single stage : 0.362 ns    <- the launch flop's own CP->Q (SDFCNQD1, fanout 25)
transition: median 0.095, p90 0.196, max 0.470;  26 of 96 above 0.15 ns
```

**Delay attribution by block:**

| Block | stages | delay | share |
|---|---|---|---|
| named CPU0 cells | 2 | 0.362 ns | **3.2 %** |
| `u_network_core` (hinst) | 11 | 1.089 ns | 9.7 % |
| `u_tidelink` (hinst) | 5 | 0.308 ns | 2.7 % |
| flat SoC glue (`u_soc/gNNNNN`, no hierarchy) | 77 | 9.474 ns | **84.3 %** |

**Launch flops across all 50 paths:** 47 × `..._u_top_u_sys_u_core_fault_q_reg/CP`,
3 × `..._u_top_u_sys_u_core_state_q_reg[0]/CP`. All in **CPU0**
(`u_chip_core_u_cpu_0_...`), not the network core's M0+.

**Slack spread of the 50:** −0.715 to −0.631. A flat plateau, not one outlier.

**The mechanism** is the AHB address-phase HREADY loop, and it is genuinely single-cycle:
`fault_q` → the core's `ls_trans` → `HTRANS[1]` → address decode → each slave's `HSEL` →
each slave's combinational `HREADYOUT` → the fabric's `HREADY` mux → back into every
master and into every register whose write-enable is `HREADY`-qualified. Path 1 crosses
`u_network_core` twice and `u_tidelink` once, which is what that loop looks like when the
interconnect is flattened. The `hreadyout` pin on Path 1 is
`u_soc/u_network_core/FE_OFC2097_eth_ss_slave_hreadyout/ZN` at arrival 6.935 ns.

**What this arithmetic rules out.** 95 stages at 0.118 ns each is a *logic-depth* limit,
not a wire or a drive limit. To recover 0.715 ns you must delete ~6 of the 95 stages, or
take 6.4 % off every one of them. No margin edit, no placement guide and no single cell
upsize reaches that alone. The honest framing is that **items 2–4 below buy 0.2–0.3 ns
between them; the remaining ~0.45 ns has to come from the RTL of the HREADY loop or from
accepting a lower `CLK_PERIOD`.**

---

## 3. Rules for writing any of the constraints below (read before editing an SDC)

These cost this project 21 hours once. They are restated here because every proposal in
§4–§7 trips over at least one.

1. **`get_cells` / `get_pins` on a *hierarchical* object expands to boundary pins that are
   not valid timing start- or endpoints.** Genus then either rejects the command
   (SDC-202) or applies it partially and only reports TIM-316/TIM-317, which is worse.
2. **Valid startpoints** are: input ports; the **clock pin** of a sequential cell; and pins
   carrying a `set_input_delay`. **Valid endpoints** are: output ports; and data/enable
   input pins of sequential cells (`/D`, `/E`, `/SI`). Anything mid-cone must be expressed
   with **`-through`**, never `-from`/`-to`.
3. **This netlist is *partially* flattened, with two different separators.** `/` separates
   surviving module boundaries (real `hinsts`); `_` is the fossil of a hierarchy Genus
   auto-ungrouped and is just part of a flat leaf-instance name string. So
   `u_soc/u_network_core/` is addressable, but
   `u_chip_core_u_cpu_0_u_slcorem0p_integration_...` **is not an hinst** — CPU0 has no
   surviving hierarchy at all. `ASIC/eth-chiplet/hooks/pre_synth.tcl:21` confirms
   auto-ungroup is live and selective.
4. **Optimisation renames net segments.** `u_chip_core_i_cpu_0_hready` exists in the
   routed netlist under **13 distinct names** — the base name plus twelve
   `FE_OFC*_`/`FE_OFN*_` prefixed segments. A `-through [get_nets u_chip_core_i_cpu_0_hready]`
   catches **1 of 13**. Always lead with a wildcard: `[get_nets *u_chip_core_i_cpu_0_hready]`.
   The `FE_` numbers are **run-specific** — never hard-code one.
5. **The flow is Innovus 21.11 Stylus (Common UI).** `createGuide`, `createRegion`,
   `floorPlan`, `loadFPlan`, `setPlaceMode` do not exist here. Use `create_group` /
   `update_group` / `create_floorplan`. (`docs/tapeout/scripts/00-index.md:27`.)
6. **How to verify a constraint actually bound**, in this order, before believing any
   number it produces:
   - `set n [llength [get_pins <pattern>]]` — print it, and **fail the script** if it is
     not the expected count. A silent zero-match is the default failure mode.
   - grep the stage log for `SDC-202`, `TIM-316`, `TIM-317`, `TCLCMD-917`. Filter out
     `@file|^#|puts` first — Innovus logs echo their own Tcl source and produce phantom
     hits.
   - `report_timing -path_group <name> -max_paths 1` must return a path. Zero paths means
     the group is empty, not that it passed.
   - Check the expansion that Genus actually writes into
     `outputs/${block}_syn.sdc` — that, not your input file, is what Innovus reads.

---

## 4. Proposal 1 + 2 — the clock-uncertainty question

### 4.1 What is charged today

`ASIC/genus-innovus/inputs/constraints.sdc:21,58,88-91`:

```tcl
set CLK_ERROR      0.35
set CLK_HOLD_ERROR 0.05
set_clock_uncertainty -setup $CLK_ERROR      [get_clocks $EXTCLK]
set_clock_uncertainty -hold  $CLK_HOLD_ERROR [get_clocks $EXTCLK]
```

`$CLK_ERROR` is then reused verbatim for `swdclk`, `QSPI_SCLK`, `QSPI_SCLK_o`,
`rmii_ref_clk`, `mii_rx_clk`, `mii_tx_clk`, `D2D_RX_CLK_0`, `D2D_TX_CLK_0`, and all 24 D2D
word clocks. `gdsrun-20260819/reports/cts_uncertainty.rep` confirms the result: **all 33
clocks, 0.35 setup / 0.05 hold, flat, with no per-clock note.**

There is no post-CTS incremental SDC anywhere in this flow. The 0.35 is charged at
synthesis, at CTS, at route, and at Tempus signoff, unchanged, on top of propagated clocks.

The SDC's own commentary decomposes it as **~0.2 ns duty-cycle distortion + ~0.012 ns
random jitter + margin**, and explicitly flags that the TI CDCM61001's RMS phase jitter is
0.85 ps — 1/29th of the number — so jitter is not where 0.35 comes from.

### 4.2 What Arm charges

From `.../CM0PINTEGRATION_cadence/scripts/technology.tcl`:

```tcl
set clock_period                20.0
set clock_period_jitter         0.050
set clock_dutycycle_jitter      0.000
set setup_margin                0.050
set hold_margin                 0.050
set pre_cts_clock_skew_estimate 0.100
set ocv_derate_factor           0.00     ;# <- zero derate
```

`constraints_clocks.sdc` (pre-CTS) → `setup_margin + jitter + pre_cts_skew` = **0.200 ns**.
`constraints_post_cts.sdc` → `reset_clock_uncertainty`, `set_propagated_clock`, then
`setup_margin + jitter` = **0.100 ns**.

| | Arm reference | this design |
|---|---|---|
| process / period | 180 nm / 20.0 ns | 65 nm / 10.0 ns |
| pre-CTS setup uncertainty | 0.200 ns (1.0 % of T) | 0.350 ns (3.5 % of T) |
| post-CTS setup uncertainty | 0.100 ns (0.5 % of T) | 0.350 ns — **never reduced** |
| OCV derate | **1.00 / 1.00** (none) | 0.97/1.03 clock, 0.95/1.05 data |
| CPPR | — | `both` |
| SI / crosstalk analysis | — | **off** |

### 4.3 Proposal 1 (rank 1) — diagnostic re-measure. Ship nothing.

The highest value-per-risk action available. It is free, it is reversible by definition
because nothing is written, and it answers the question the ranking actually turns on:
*how much of the TNS is margin policy and how much is silicon?*

Run in a scratch Tempus/Innovus session against the existing routed database. **Do not
save the database.**

```tcl
# --- scratch session, read-only. Nothing is written. ---

# (a) Re-price the existing timing at Arm's post-CTS uncertainty.
#     This does not "fix" anything - it partitions the failing population.
reset_clock_uncertainty -setup [get_clocks clk]
set_clock_uncertainty   -setup 0.100 [get_clocks clk]
report_timing -max_paths 1 -path_type summary
report_constraint -all_violators -check_type setup

# (b) Attribute the TNS to the AHB HREADY loop.
#     NOTE the leading wildcard - see rule 4 in section 3. Without it this
#     matches 1 of 13 net segments and under-reports by an order of magnitude.
set hr [get_nets *u_chip_core_i_cpu_0_hready]
puts "HREADY net segments matched: [llength $hr]"     ;# expect ~13, NOT 1
if {[llength $hr] < 5} { error "hready glob is stale - do not trust the next report" }
report_timing -through $hr -max_paths 5000 -nworst 1 \
              -path_type summary > hready_loop.rpt

# (c) Same for the dominant endpoint class (33 of the worst 50).
report_timing -to [get_pins *u_tidechart_controller_u_apb_regs_cost_rf_r_reg*/D] \
              -max_paths 5000 -nworst 1 -path_type summary > cost_rf.rpt
```

**What it is expected to change:** nothing physical. It produces three numbers that do not
exist today: (i) how many of the 1299/1546 reg2reg endpoints are inside 0.25 ns of closing,
(ii) what fraction of TNS flows through the CPU0 `HREADY` net, and (iii) what fraction ends
in `cost_rf_r`. If (i) is most of them, margin policy is the story and proposal 2 is worth
its risk. If (i) is a small minority, proposal 2 is cosmetic and the effort belongs in RTL.

**How to measure whether it helped:** it cannot "help". Success is the three reports
existing and being cited in the closure decision.

**Argument against:** none, beyond an hour of tool time and the standing rule that a
scratch session must not write the database. The one real trap is (b)'s wildcard; the
`if {... < 5} error` guard above is there because a silent zero-match would produce a
confident, clean, meaningless report.

### 4.4 Proposal 2 (rank 2) — reduce setup uncertainty on `clk` only, 0.35 → 0.20

**Exact text.** In `ASIC/genus-innovus/inputs/constraints.sdc`, at lines 88–91, replacing
only the `$EXTCLK` setup line. **`$CLK_ERROR` itself must not be edited** — it is consumed
by four other SDCs for clocks that this argument does not cover (§1.5).

```tcl
# SETUP uncertainty for the system clock ONLY.
#
# $CLK_ERROR (0.35) stays as-is and remains the value used by
# qspi_constraints.sdc, ethernet_constraints.sdc and tidelink_constraints.sdc.
# Those domains are NOT covered by the argument below.
#
# WHY THIS CLOCK IS DIFFERENT. The 0.35 is ~0.2 ns of CDCM61001 duty-cycle
# distortion + ~0.012 ns jitter + margin. Duty-cycle distortion moves the
# FALLING edge; it cannot reach a posedge->posedge setup check. Measured, not
# assumed: of the 5,251 negative-edge flops in the routed netlist, 4,892 are in
# u_deskew (D2D RX word clocks), 174 are in the QSPI controller on
# `negedge QSPI_SCLK_i` (qspi_controller.sv:427,517) and 185 are TideLink lane
# sync/debug. ZERO are on `clk`.
#
# WHY 0.20 AND NOT ARM'S 0.100. Arm's post-CTS number
# (the M0+ Cadence reference-methodology bundle/.../technology.tcl: setup_margin 0.050 +
# clock_period_jitter 0.050) comes from a 180 nm, 20 ns, single-block reference
# with ocv_derate_factor = 0.00. This is 65 nm at 10 ns with SI analysis OFF
# (ASIC/sta/reports/sta_manifest.txt: "si_analysis = off"). 0.20 is Arm's
# PRE-CTS composite and leaves ~0.15 ns standing against crosstalk-induced
# delay, which nothing in this flow measures.
set CLK_SETUP_ERROR_SYS 0.20
set_clock_uncertainty -setup $CLK_SETUP_ERROR_SYS [get_clocks $EXTCLK]
set_clock_uncertainty -hold  $CLK_HOLD_ERROR      [get_clocks $EXTCLK]
```

**Where it goes:** `ASIC/genus-innovus/inputs/constraints.sdc`, replacing line 88 only.
Lines 89–91 (`-hold` on `$EXTCLK`, and both lines for `$SWDCLK`) are untouched.

**What it is expected to change:** every `clk`-domain setup check gains exactly 0.150 ns.
WNS −0.715 → −0.565 (`full-20260814`), or −0.746 → −0.596 (gdsrun). FEP count falls by
however many endpoints sit in the 0.000…0.150 ns band — unknown until proposal 1 is run,
which is why proposal 1 is ranked above this one. Nothing physical changes; the tool
simply optimises against a different target, so a re-run from place is required for the
number to mean anything.

**How to measure whether it helped:**
- `reports/cts_uncertainty.rep` must show `clk 0.20 / 0.05` and **every other clock still
  at 0.35**. If any other clock moved, `$CLK_ERROR` was edited by mistake — revert.
- WNS must improve by 0.150 ± 0.005 on a **CTS-only re-price** (same database, uncertainty
  changed, no re-optimisation). If it moves by anything other than 0.150 the constraint
  did not bind where you think it does.
- Then, and only then, a full re-run from `place`, comparing TNS and FEP. A re-run that
  improves WNS by *more* than 0.150 is the tool spending the freed margin elsewhere — that
  is the desired outcome, but record it separately from the arithmetic 0.150.
- Hold must be re-checked: `full-20260814` hold WNS is −0.006/35 endpoints. Lowering setup
  uncertainty gives placement/CTS a different objective and can move hold. Do not report
  setup without hold.

**Argument against — and it is a serious one.**

1. **The 0.35's *function* today is not what its comment says it is.**
   `ASIC/sta/reports/sta_manifest.txt:6` reads `si_analysis = off (mmmc -si stripped for
   IMPESI-3490)`. There is no crosstalk delay analysis anywhere in the signoff chain, no
   IR-drop-aware timing, and only flat OCV (0.95/1.05 data, 0.97/1.03 clock — no AOCV, no
   SOCV). Whatever the comment says, **the 0.35 is the only budget this design holds
   against crosstalk-induced delay and supply-induced jitter at 65 nm.** Spending it while
   those remain unmeasured is a margin raid, and it is the precise shape of raid this
   project has been burned by before.
2. **Arm's 0.100 is not transferable and quoting it as a target is the trap.** 180 nm,
   20 ns period, one 4,000-instance block, zero OCV derate, one power domain. This is
   65 nm, 10 ns, ~200,000 instances, 1.6 × 2.0 mm, 92 % utilisation, with real derates.
   The ratio 0.5 % of period is a reference-flow artefact, not a physical constant.
3. **`route_design_with_si_driven 1` is not SI analysis.** (`ASIC/genus-innovus/scripts/route_setup.tcl:75`.)
   It biases the router. It does not report a single crosstalk-induced delay number, and
   it does not let you subtract one from the uncertainty budget.
4. **The DCD claim is verified for `clk` but not exhaustively.** I enumerated negedge
   *flip-flops*. I did **not** enumerate latches, and I did not check whether
   `QSPI_SCLK`'s divider can be configured to ratio 1 — if it can, the 174 QSPI negedge
   flops become `clk`-negedge flops in all but name and DCD reaches them through a
   `clk → QSPI_SCLK` half-cycle relationship. That check is listed as open in §8.

**Therefore:** do **not** take 0.35 → 0.10. Take 0.35 → 0.20 **only in the same change
that restores SI analysis** (i.e. resolves IMPESI-3490 rather than stripping `-si`), or
else run proposal 1 and leave the shipped constraint at 0.35. I would not sign a stream
that spent this margin without an SI number to point at.

---

## 5. Proposal 5 — the CMSDK `hreadyout → HREADY` treatment, re-expressed at this hierarchy

### 5.1 What CMSDK actually does, and why

`$CMSDK_DIR/implementation_tsmc_ce018fg/cortex_m0_mcu_system_synopsys/scripts/cmsdk_mcu_system_constraints.tcl:141-145`:

```tcl
# Combinatorial path from flash_hreadyout, sram_hreadyout, boot_hreadyout to HREADY
set_max_delay [expr $cycle80 + $clock_uncertainty + 2.0] -from [get_ports flash_hreadyout] -to [get_ports HREADY]
set_max_delay [expr $cycle80 + $clock_uncertainty + 2.0] -from [get_ports sram_hreadyout]  -to [get_ports HREADY]
set_max_delay [expr $cycle80 + $clock_uncertainty + 2.0] -from [get_ports boot_hreadyout]  -to [get_ports HREADY]
```

Read the surrounding lines before reading these. `flash_hreadyout` carries
`set_input_delay $cycle40`; `HREADY` carries `set_output_delay $cycle30`. The default
budget for that port-to-port combinational path is therefore `T − 0.4T − 0.3T = 0.3T`
= 6 ns at `clock_period` 20. The `set_max_delay` replaces it with ~18.15 ns.

**It is a relaxation, and what it relaxes is an artefact.** `flash_hreadyout` and `HREADY`
are *ports of a block being synthesised standalone*, with IO budgets Arm invented so the
block could be constrained at all. The memories are outside `cmsdk_mcu_system`. The
`set_max_delay` says "this is a wire through a mux, do not let my own arbitrary IO
partitioning make you burn effort on it".

### 5.2 Why it does not transfer to this design

Here there is no block boundary at that point. The equivalent nets are internal:
`u_chip_core_i_cpu_0_hready`, `eth_ss_slave_hreadyout`, `i_network_core_hready`,
`cpu_ss_1_slave_hreadyout` — all inside the flattened `nanosoc_multicore_soc`. The path
they sit on is a **true single-cycle flop-to-flop path**: `core_fault_q_reg/CP` →
… → `nvic_event_q_reg/E`, 95 stages, 11.230 ns against a 10.000 ns period, with no
artificial IO budget anywhere on it.

There is nothing to relax. **A `set_max_delay` larger than the clock period on that path
is a multicycle declaration with no protocol behind it.** AHB gives no second cycle: the
address phase and the `HREADY` it produces are the same cycle by definition. Applying the
CMSDK number here would turn 1299 real violations into 0 reported violations and change
nothing in silicon. That is the worst outcome available from this whole document.

**Do not apply it.** If someone insists, the literal translation is written below *only*
so that it can be recognised and rejected on sight:

```tcl
# DO NOT APPLY. Recorded for recognition only.
# 0.8*10 + 0.35 + 2.0 = 10.35 ns > the 10.000 ns clock period.
# This declares a single-cycle AHB address-phase path to be multicycle.
# set_max_delay 10.35 -from [get_pins *_u_core_fault_q_reg/CP] \
#                     -to   [get_pins *_u_nvic_event_q_reg/E]
```

### 5.3 What *does* transfer — the same mechanism, as a measurement

The CMSDK constraint's *diagnosis* is right even though its *treatment* is not. Express it
as a path group so the HREADY loop can be tracked as a first-class number across runs.
This is scoping, not relaxation: `group_path` changes nothing about what must be met.

```tcl
# Innovus 21.11 Stylus. Place in a scratch session, or in a report-only hook.
# It does not relax anything - a path group only changes how paths are reported
# and, in the optimiser, how effort is weighted.
set hr [get_nets *u_chip_core_i_cpu_0_hready]
if {[llength $hr] < 5} {
    error "AHB_HREADY_LOOP: glob matched [llength $hr] segments, expected ~13.\
           The FE_* opt-buffer names are run-specific; re-derive before trusting."
}
group_path -name AHB_HREADY_LOOP -through $hr
report_timing -path_group AHB_HREADY_LOOP -max_paths 200 -path_type summary
```

**Validity of the object forms used above, and how it was established.** `-through` on a
`get_nets` collection is legal for any net, which is why this form is used rather than
`-from`/`-to`: the `hready` nets are mid-cone and are **not** valid startpoints or
endpoints (§3 rule 2). By contrast `-from [get_pins *_u_core_fault_q_reg/CP]` *is* valid —
it names the clock pin of a sequential cell — and `-to [get_pins *_reg/D]` and
`-to [get_pins *_reg/E]` are valid endpoints. Every object in §4.3 and §5.3 is of one of
those three kinds. What is deliberately **absent** everywhere in this document is
`-from`/`-to` on a hierarchical instance or on a mid-cone pin, which is the form that
produces SDC-202 or a silent partial application with only TIM-316/317 in the log.

I have **not** executed any of these commands — that would require a tool session against
the routed database, which is outside the "apply nothing" scope. The verification ladder in
§3 rule 6 is what should be run before any number they produce is quoted.

---

## 6. Proposal 6 — SPECHTRANS. Refuted on three independent grounds.

### 6.1 It is not wired, and that is legal

| Level | File | Status |
|---|---|---|
| Arm core drives it | `CORTEXM0PLUS.v:180`, `:312` (`spec_htrans_o`) | present |
| SoC Labs wrapper propagates it | `nanosoc-multicore-system/nanosoc_arch_tech/rtl/slcorem0p_tech/src/verilog/slcorem0p_integration.v:111,264` | present |
| CPU wrapper terminates it | `.../slcorem0p.v:406` → `.SPECHTRANS ( ),` | **dangled** |
| `slcorem0p` module port list | `.../slcorem0p.v:35-105` | **no SPECHTRANS port at all** |
| AHB fabric / decoder | anywhere in design RTL | **zero references** |

Confirmed independently by the checked-in lint output
(`build/lint/full/verilator/lint.log`, `PINCONNECTEMPTY` at `slcorem0p.v:406`) and by four
`.waive` files that switch the `UNCONN`/`UNCONO` check off for it — so this was a decision,
not an oversight. Arm's IIM §4.4.2 blesses it: *"If this interface is not in use, you can
leave it unconnected."* Arm's own integration kit dangles it too
(`cm0p_ik_sys.v:253`). There is no `SPECHTRANSEN` signal in this IP release; that name is
fictional.

### 6.2 It cannot help a path that launches at `fault_q` — the decisive objection

Both signals are produced from the same upstream term. From
`tidelink/imp/fpga/eth_chiplet_ip/src/cm0p_core.v`:

```
:3655   ls_trans        = (run_exe & exe_ls_trans | run_irq & irq_ls_trans |
                           run_ldm & ldm_ls_trans | run_rfe & rfe_ls_trans |
                           run_rst & rst_ls_trans | run_stm & stm_ls_trans) & ...
:2378   rst_ls_trans    = rst_cyc_2 | rst_cyc_3 & ~fault_q          <-- fault_q
:2622   stm_ls_trans    = (~list_empty & ~fault_q) | atomic_q       <-- fault_q
:5331   spec_trans      = ls_trans | fetch_seq | fetch_force
:6622   cpu_spec_htrans_o = spec_trans                              --> SPECHTRANS
:5515   ahb_attempt     = fetch | (ls_trans & ~io_match)
:5516   ahb_trans       = ahb_attempt & ~kill_ahb & ~align_fault
:6624   cpu_trans_o     = ahb_trans                                 --> HTRANS[1]
```

`fault_q` reaches `ls_trans`, and `ls_trans` is in **both** cones. SPECHTRANS removes only
`~kill_ahb` (MPU fault / XN / PPB decode), `~align_fault` and `~io_match` — the *downstream
address checks*. It removes nothing upstream of `ls_trans`. The saving is bounded by those
three gates, and this design instantiates the core with **`MPU = 0`**
(`nanosoc-multicore-system/nanosoc_arch_tech/rtl/slcorem0p_tech/src/verilog/slcorem0p_integration.v:81`,
passed through at `:235`), so `mpu_fault_a_i` is inert and `kill_ahb` degenerates further
(`cm0p_core.v:5472` — `kill_ahb = spec_trans & mpu_fault_a_i`).

Arm's Table I-2 constraint of 80 % for SPECHTRANS versus 50 % for `HTRANS[1]` is real, but
it is an aggregate *port* budget measured from the core's internal launch. It does not
describe a path whose launch flop is `fault_q` specifically.

### 6.3 The endpoint class forbids it anyway

IIM §4.4.2, Table 4-11, verbatim:

> "This signal indicates the processor is ready to do a transaction, but does not take into
> account suppression of `HTRANS[1]`. … **If you use SPECHTRANS, be sure to maintain AHB
> compliance. For example, it is not acceptable to introduce an `HREADY` wait-state in
> response to a SPECHTRANS for which `HTRANS[1]` does not also become asserted.**"

SPECHTRANS is for **read-invariant** slaves starting a side-effect-free lookup early. The
failing population here is 33 APB register-file *writes* (`cost_rf_r_reg[N][15]/D`), plus
an NVIC event enable and an ICG enable. All are state. And the mechanism on the path *is*
the `HREADY` loop — precisely the thing the compliance rule forbids SPECHTRANS from
influencing.

### 6.4 Cost, for completeness

Adding the port to `slcorem0p`'s port list, replacing the `.SPECHTRANS ( )` dangle, and
threading it to a consumer, in **three byte-identical duplicated copies** of both wrapper
files (`nanosoc_arch_tech/`, `ethernet-subsystem-ahb/nanosoc_arch_tech/`,
`tidelink/imp/fpga/eth_chiplet_ip/`), plus writing the consumer, plus re-running LEC and
the whole P&R flow — for a gain that §6.2 shows is structurally near zero on this path.

**Verdict: do not pursue.** Note also the incidental finding at
`slcorem0p_integration.v:229`, `assign CODEHINTDE = 3'b000;` — a constant-zero output
masquerading as a real one because the M0+ release in use exposes `CODEHINT[3:0]` rather than
`CODEHINTDE[2:0]`. Harmless while nothing consumes it, but it is a liar rather than an
honest dangle, and worth a comment in the RTL.

---

## 7. Proposal 4 — soft placement guide around each CPU

### 7.1 What Arm does and says

`.../CM0PINTEGRATION_cadence/floorplan/cm0pintegration_fp.fp:448-451`:

```
Guide: u_imp/u_cortexm0plus/u_top/u_sys 1.1200 1.1200 599.0550 573.4400 0
Fence: PD_SYS 1.1200 1.1200 599.0550 573.4400 0
Fence: PD_DBG 600.3200 1.1200 800.8700 395.9250 0
Guide: TOP 1.1200 1.1200 801.1200 701.1200 0
```

A soft **Guide** on `u_top/u_sys` — the same hierarchy that holds `fault_q`
(`cm0p_top_sys.v:340` instantiates `u_core`, and `cm0p_core.v:318` declares
`reg fault_q`). The **Fences** in the same file are power-domain boundaries (CPF), a
separate concern.

IIM §6.3, verbatim:

> "You must minimize the paths from the processor to your memory blocks and the paths from
> your memory blocks to the processor. **You must also ensure that the standard cells for
> the processor are grouped together to ensure good timing performance.** A poor floorplan
> or incorrectly grouped standard cells reduce the timing performance.
>
> ARM does not expect you to perform hierarchical floorplanning of the processor."

That last sentence matters: a soft guide is exactly the level Arm applies to itself, and no
fence or partition is required.

### 7.2 What this design has

`ASIC/genus-innovus/scripts/floorplan.tcl` (406 lines) creates **no** region, guide, fence,
group or place blockage — grepped across the whole `ASIC/` tree, zero hits for the entire
keyword set. The only placement-adjacent constraints are macro halos and *route* blockages.
Standard-cell placement is unconstrained across the whole 1190 × 1590 µm core at 92.2 %
utilisation. It is the shipping floorplan: `ASIC/eth-chiplet/design.mk:165` →
`FLOORPLAN_TCL ?= $(LEGACY_ASIC_DIR)/scripts/floorplan.tcl`, sourced unchanged at
`ASIC/asic-toolkit/flow/innovus/2_place.tcl:806`.

### 7.3 The obstacle: there is no CPU hinst to name

Arm could write `Guide: u_imp/u_cortexm0plus/u_top/u_sys` because their hierarchy survived.
Here it did not. CPU0 has **no** surviving hinst — it is fully dissolved into
`nanosoc_multicore_soc`. CPU1's only enclosing hinst is `u_network_core`, which is the
entire Ethernet subsystem: 40,919 instances / 552,022 µm², about 10× the CPU. The only two
surviving CM0+ sub-hinsts are two small debug blocks of the network CPU (67 and 169
instances).

So the guide must be built from a **glob-resolved leaf-instance list**. `update_group -objs`
accepts a list form, documented as being *"used for instances only and NOT for group or
hierarchical instances"* — which is exactly the case here.

### 7.4 Exact text

New file `ASIC/eth-chiplet/hooks/pre_place.tcl`. The hook fires at
`ASIC/asic-toolkit/flow/innovus/2_place.tcl:1307`, three lines before `place_design`. This
is additive — it does not touch the frozen `floorplan.tcl`, and the project already ships
three hooks in that directory.

```tcl
# Soft placement guides for the two Cortex-M0+ cores.
# Arm IIM (DIT0032B) S6.3: "the standard cells for the processor are grouped
# together"; Arm's own reference does this with a soft Guide on u_top/u_sys
# (cm0pintegration_fp.fp:448) and explicitly does NOT require a fence:
# "ARM does not expect you to perform hierarchical floorplanning of the processor."
#
# A guide, NOT a region and NOT a fence. At 92.2% utilisation a hard boundary
# risks IMPSP-2021 "Could not legalize" - floorplan.tcl:56-59 records that
# raising utilisation already provoked exactly that.
#
# NEITHER CPU HAS A SURVIVING HINST (Genus auto-ungroup), so these are resolved
# by instance-name glob. The patterns key on RTL-derived fragments, but they are
# still a function of ungrouping decisions and WILL move when the RTL changes -
# same fragility floorplan.tcl:238-248 documents for the macro globs. Hence the
# count guard: a stale pattern must abort the stage, never silently guide nothing.

foreach {grp pat expect} {
    CPU0_GUIDE  *u_chip_core_u_cpu_0_u_slcorem0p_integration_*   3984
    CPU1_GUIDE  *u_network_core_u_slcorem0p_integration_*        4243
} {
    set insts [get_db insts $pat]
    set n     [llength $insts]
    if {$n < [expr {$expect * 3 / 4}]} {
        error "pre_place: $grp matched $n instances, expected ~$expect.\
               The glob is stale - fix the pattern, do not lower the guard."
    }
    puts "pre_place: $grp -> $n instances"
    create_group -name $grp -type guide
    update_group -name $grp -add -objs $insts
}
```

**Deliberately omitted: the `-rects` box.** Picking a box blind would be worse than no
guide. Derive it from the *current* placement's CPU centroid before the first real run:

```tcl
# scratch session on the existing routed DB - produces the box, changes nothing
foreach pat {*u_chip_core_u_cpu_0_u_slcorem0p_integration_*
             *u_network_core_u_slcorem0p_integration_*} {
    set xs {}; set ys {}; set a 0
    foreach i [get_db insts $pat] {
        set b [get_db $i .bbox]
        lappend xs [lindex $b 0] ; lappend ys [lindex $b 1]
        set a [expr {$a + [get_db $i .area]}]
    }
    puts "$pat  n=[llength $xs]  area=${a}um2 \
          x=[lindex [lsort -real $xs] 0]..[lindex [lsort -real $xs] end] \
          y=[lindex [lsort -real $ys] 0]..[lindex [lsort -real $ys] end]"
}
```

Size it for ~80 % local density. Extrapolating from the two surviving CM0+ debug hinsts
(254.52 µm² / 67 insts and 412.92 µm² / 169 insts → 2.4–3.8 µm²/inst), each ~4,000-instance
CPU is roughly 10,000–16,000 µm², i.e. **0.6–0.8 % of the 1,892,100 µm² core** — a box of
about 150 × 100 µm each. There is un-macro'd core around x ≈ 250–550, y ≈ 600–1200, but
that must be re-checked against the live macro map rather than taken from this document.

**Expected change:** on the *measured* critical path, at most **0.362 ns → something
smaller**, because only 2 of 95 stages (3.2 % of the delay) are in named CPU cells. On the
aggregate it may do better — 47 of the 50 worst paths launch from the same CPU0 flop, and
tightening that flop's fanout cone shortens the first few stages of all of them.

**How to measure whether it helped:**
- The `pre_place` log must print two non-zero instance counts. Zero or a guard abort means
  it did nothing.
- Compare `reports/timing_summary_05_route_opt.rep` WNS/TNS/FEP against the same build
  without the hook, everything else identical.
- Compare the CPU bounding-box span before and after with the centroid script above. If
  the span did not shrink, the guide did not bind and the WNS delta is noise.
- **Mandatory PG re-check.** Any change that moves standard cells re-phases the PG mesh.
  `ASIC/genus-innovus/scripts/floorplan.tcl:255-273` is unambiguous that a placement change
  can short VDD to VSS elsewhere on the die with nothing reporting it. Run
  `ASIC/genus-innovus/scripts/probe_pg_build.tcl` and read the **rail-to-rail short count**, plus
  `check_connectivity`, before believing any timing number. ~3 minutes, no P&R licence.
  Background: `docs/tapeout/36-split-row-pg-anchoring-hazard.md`.

**Argument against:**
1. **The leverage is 3.2 %.** §2's attribution says 84 % of the path is flat SoC glue that
   carries no CPU name at all and cannot be selected by any glob. A guide cannot touch it.
2. **It can make this path worse.** 16 of the 95 stages are in `u_network_core` and
   `u_tidelink`. Pulling CPU0's cells into a tight cluster necessarily lengthens the
   CPU0 → network_core → tidelink → back excursion. Net effect is genuinely ambiguous and
   only a run will settle it.
3. **The 711 `FE_*` opt cells** (319 CPU0 + 392 CPU1) carry the CPU prefix but are
   optimisation buffers named after the net they repair, not processor logic. The glob above
   includes them. Decide that deliberately; excluding them is a `-if {.is_physical == false}`
   filter away.
4. **PG risk is real and silent** — see the mandatory check above.
5. **The alternative is cheaper if you are re-synthesising anyway:** set `ungroup_ok false`
   on the CM0+ integration wrapper in `hooks/pre_synth.tcl` — which that file already does
   for `tidelink_link_clk_div` via `protect_link_clk_div.tcl` — restoring a real hinst you
   can name the way Arm does. It changes synthesis QoR and forces a re-run from `syn`.

---

## 8. Proposal 3 — the design-rule gap (not in the brief; found while measuring)

Arm's `constraints_design.sdc` opens with two lines this design does not have:

```tcl
set_max_fanout 32 [current_design]
set_max_transition $max_transition($pvt) [current_design]     ;# 1.80 ns at 180nm/20ns
```

This design has **no `set_max_transition` on `[current_design]` at all**. The only ones in
the whole constraint set are on the two I2C pads. The sole transition limit in force is the
library's own `default_max_transition : 0.7657` from `tcbn65lpwc.lib` — which is the
*ceiling of the NLDM characterisation table*, not a design target. `set_max_fanout 10
[all_inputs]` is present at line 727 and the SDC's own comment at line 717 correctly
identifies it as a no-op, since every top-level input port drives exactly one pad pin.

Scaled to this node and period, Arm's 1.80 ns at 20 ns → about **0.35–0.40 ns at 10 ns**,
roughly half the library default.

```tcl
# ASIC/genus-innovus/inputs/constraints.sdc, in the DESIGN RULE CHECKS block,
# after the existing set_max_capacitance line.
#
# The only transition limit in force today is tcbn65lpwc.lib's
# default_max_transition = 0.7657 ns, which is the top of the characterisation
# table, not a target. Arm's reference sets a design-wide rule
# (AT590 constraints_design.sdc); this design sets none.
# 0.35 ns is ~half the library default and scales Arm's 1.80 ns @ 20 ns to 10 ns.
set_max_transition 0.35 [current_design]
set_max_fanout     32   [current_design]
```

**Expected change:** on the measured path, the transition distribution is already
reasonable — median 0.095 ns, p90 0.196 ns — with only **4 of 96** stages above 0.25 ns and
one outlier at 0.470 ns. So the direct gain on Path 1 is small, plausibly 0.05–0.15 ns.
The value is broader and unmeasured: a design-wide slew target improves the *input slew*
of every downstream stage, which on 95-stage paths compounds.

**How to measure:** compare `reports/drv_05_route_opt.rep` violator counts before and after
(today it is near-clean against 0.766 — a handful of internal pins at 0.81–0.85, plus the
I2C and QSPI pads which are external and unfixable), and compare instance count and area in
`design_report.json`. If area rises more than ~2 % for less than 0.05 ns, back it out.

**Argument against:** it costs area and leakage at 92.2 % utilisation, which is already
where `IMPSP-2021 Could not legalize` lives. `set_max_fanout 32 [current_design]` in
particular changes optimisation targets across the entire design and is a signoff decision,
not a tidy-up — the SDC's existing comment on `set_max_fanout` says exactly this and it is
right. And a tighter rule may simply buffer the 95-stage path into an equally slow but
better-slewed 95-stage path.

---

## 9. What I could not establish

1. **None of this was run.** Every expected gain is arithmetic or structural inference. No
   tool session was opened. The verification ladder in §3 rule 6 is what converts these
   into facts.
2. **Whether the `full-20260814` population is still the right target.** §1.3: gdsrun's
   worst path is a different flop and a different endpoint. §2's attribution must be
   repeated on gdsrun's `timing_05_route_opt_late.rep` before any of this is costed against
   that run. I chose to characterise the run that was already characterised rather than
   silently substitute one for the other.
3. **Latches, and the `clk → QSPI_SCLK` half-cycle question.** §1.5 enumerates negedge
   *flip-flops*. I did not enumerate latch cells, and I did not determine whether the QSPI
   clock divider can be configured to ratio 1 — if it can, the 174 negedge QSPI flops
   become `clk`-negedge captures in all but name and the DCD argument in §4.4 weakens. This
   is the single check that most directly threatens proposal 2 and it should be closed
   before proposal 2 is applied.
4. **The split between cell delay and net delay on the critical path.** Innovus collapses
   both into one `Delay` column at this report detail. Without that split I cannot say
   whether the path is cell-limited or wire-limited, which is precisely the number that
   would settle proposal 4. `report_timing -path_type full_clock_expanded -net_delay`
   would produce it.
5. **Why `core_fault_q_reg` is an `SDFCNQD1` (drive 1) with fanout 25 and a 0.362 ns
   CP→Q**, the largest single stage on the path. Post-route opt should have upsized it.
   Whether something blocks that (a `dont_touch`, the scan-cell mapping, or opt effort
   exhaustion) is unresolved. If nothing blocks it, this is an ECO-scale gain that none of
   the six proposals above captures. Worth ten minutes with `get_db` on the routed DB.
6. **Whether the 33 `cost_rf_r_reg[N][15]/D` paths are functionally sensitizable.** A
   95-stage combinational path from a CPU fault register to a TideChart APB register file,
   crossing four blocks in one cycle, is the shape that is sometimes logically false. I did
   not attempt to prove it either way, and it must not be false-pathed on suspicion.

---

## 10. If only one thing is done

Run §4.3. It costs an hour of tool time, writes nothing, risks nothing, and produces the
three numbers on which every other decision in this document depends.
