# 05 — Placement, CTS and Routing

`nanosoc_eth_chiplet_pads` · Cadence Innovus 21.11-s130_1 · STYLUS / Common-UI

Covers everything from the floorplanned, power-planned database through to a
routed, hold-repaired design. Filler, antenna diodes and bond pads are the next
page — [06-fill-antenna-bondpads.md](06-fill-antenna-bondpads.md) — even though
they are sourced from inside the same route stage.

Prerequisites: [03-floorplan.md](03-floorplan.md) and
[04-power-plan.md](04-power-plan.md) must have run; both are sourced from
`2_pnr_setup.tcl` before placement.

---

## 1. The three stages and what invokes them

All three run out of `ASIC/genus-innovus/`, with `work/` as the cwd.

```sh
cd ASIC/genus-innovus
make pnr_place     # -> innovus -stylus -files ../asic-flows/Cadence/2_pnr_setup.tcl
make pnr_cts       # -> innovus -stylus -files ../asic-flows/Cadence/3_pnr_clock.tcl
make pnr_route     # -> innovus -stylus -files ../asic-flows/Cadence/4_pnr_route.tcl
make pnr_all       # syn -> place -> cts -> route -> GDSII, unattended, multi-hour
```

Each `make` target has a post-condition check after it, because **Innovus exits 0
on a rejected argument or a failed script**. `pnr_place` asserts a DB directory
appeared, `pnr_cts` asserts a post-opt timing summary was written, `pnr_route`
asserts a GDSII exists. Do not remove those checks; they are the only thing
distinguishing "finished" from "died quietly two hours ago".

| Flow script | Project scripts it sources | Ends with |
|---|---|---|
| [`2_pnr_setup.tcl`](../../ASIC/asic-flows/Cadence/2_pnr_setup.tcl) | `floorplan.tcl`, `power_plan.tcl`, [`preplace.tcl`](../../ASIC/genus-innovus/scripts/preplace.tcl), [`postplace.tcl`](../../ASIC/genus-innovus/scripts/postplace.tcl) | `write_db $block_name` |
| [`3_pnr_clock.tcl`](../../ASIC/asic-flows/Cadence/3_pnr_clock.tcl) | [`cts_setup.tcl`](../../ASIC/genus-innovus/scripts/cts_setup.tcl) | `write_db $block_name` |
| [`4_pnr_route.tcl`](../../ASIC/asic-flows/Cadence/4_pnr_route.tcl) | [`route_setup.tcl`](../../ASIC/genus-innovus/scripts/route_setup.tcl), [`place_bondpads.tcl`](../../ASIC/genus-innovus/scripts/place_bondpads.tcl) (→ `filler.tcl`) | `write_db $block_name` |

Full ordering inside `4_pnr_route.tcl`, verified against two runs:

```
read_db  ->  route_setup.tcl  ->  route_design -global_detail
         ->  opt_design -post_route (setup recovery)
         ->  opt_design -post_route -hold      <- HoldOpt, the long pole
         ->  DrvOpt  ->  EcoRoute
         ->  place_bondpads.tcl  (which sources filler.tcl FIRST, then bond pads)
         ->  check_drc / check_filler / check_connectivity / check_process_antenna
         ->  report_timing x N, set_analysis_view, write_stream
         ->  report_area / report_power / write_netlist / write_sdf / write_db
```

Note that the single script line `opt_design -post_route -hold` expands into the
whole post-route optimisation flow — setup recovery, `HoldOpt`, `DrvOpt`,
`EcoRoute`. Those are Innovus's own internal phase banners in the log, not
separate commands in the script.

---

## 2. Snapshots — read this before you experiment

**Every stage script ends with `write_db $block_name`, the same name.** Each
stage overwrites the previous one, so by default only the final post-route
database survives. Two extra snapshots exist purely to make experiments
affordable:

| Snapshot | Written by | State captured |
|---|---|---|
| `${block_name}_placed` | [`cts_setup.tcl`](../../ASIC/genus-innovus/scripts/cts_setup.tcl) line 9 | post-place (sourced right after `3_pnr_clock.tcl`'s `read_db`) |
| `${block_name}_cts` | [`route_setup.tcl`](../../ASIC/genus-innovus/scripts/route_setup.tcl) line 12 | post-CTS (sourced right after `4_pnr_route.tcl`'s `read_db`) |

Each is roughly 109 MB. Disk is not the constraint; a re-run is. Without them,
any change to routing or hold repair costs a full replay from placement (about
five hours) instead of a resume (about one).

```sh
cd ASIC/genus-innovus/work && innovus -stylus
```
```tcl
source ../scripts/config.tcl
read_db nanosoc_eth_chiplet_pads_cts      ;# or ..._placed
```

`make gui` does the same thing with the design already loaded — use it rather
than `make pnr_setup`, which drops you into an empty session where a bare
`read_db` fails because the block name and every library path live in
`config.tcl`.

---

## 3. Placement

### What runs

[`preplace.tcl`](../../ASIC/genus-innovus/scripts/preplace.tcl), in full:

```tcl
set_db design_process_node 65
set_db place_global_cong_effort auto
set_db place_global_timing_effort high
set_db place_global_uniform_density true
set_db place_detail_legalization_inst_gap 2
set_db place_design_floorplan_mode false
```

then `place_design`, then
[`postplace.tcl`](../../ASIC/genus-innovus/scripts/postplace.tcl):

```tcl
write_sdf design.sdf -ideal_clock_network
set_db add_tieoffs_max_fanout 10
add_tieoffs -lib_cell {TIEL TIEH} -prefix LTIE
```

`place_global_uniform_density true` plus `legalization_inst_gap 2` is what keeps
gaps available in the rows for later hold-buffer insertion. On a design that
finishes hold repair above 90% density, that is not cosmetic — see §7.

`DFT` is `0` in [`config.tcl`](../../ASIC/genus-innovus/scripts/config.tcl), so
the `read_def`/`reorder_scan` branches are dead on this build. The scan chain is
not bonded.

### What it produces

- `reports/timing_summary_00_pre_place.rep`, `timing_00_pre_place_{late,early}.rep`
- `reports/timing_summary_01_place.rep`, `timing_01_place_{late,early}.rep`,
  `power_01_place.rep`, `qor_01_place.rep`
- `work/design.sdf` (ideal-clock, ~494 MB — it is a byproduct, not a deliverable)
- `work/nanosoc_eth_chiplet_pads/` (the DB)

### What to check

```tcl
report_qor -format text            ;# UTIL / INSTS / AREA / WALL for place_design
check_place                        ;# unplaced or illegally placed instances
get_db current_design .core_bbox   ;# confirms the core box the floorplan gave you
```

Measured `place_design`, both runs on srv03335 at `-local_cpu 14`:

| Run | Core | `place_design` UTIL | Insts | Wall |
|---|---|---|---|---|
| `baseline_2026-08-05` (CORE_TO_IO 50) | 1230 × 1630 | 72.72 % | 184 372 | 0:18:35 |
| current (CORE_TO_IO 70) | 1190 × 1590 | 80.67 % | 184 372 | 0:18:39 |

Same netlist, same cell count, 8 points of density — that is entirely the 5.6%
core-area loss from raising `CORE_TO_IO`. See
[04-power-plan.md](04-power-plan.md) for why it had to be raised.

### What goes wrong

- **Macros outside the core box.** `place_inst` takes absolute die coordinates
  and does not complain when the result straddles the core edge; the first
  symptom is an `sroute` mess hours later. `floorplan.tcl`'s `place_macro`
  proc now asserts containment at the point of placement. Covered in
  [03-floorplan.md](03-floorplan.md).
- **`IMPTCM-162 ... does not match any object in design`** during floorplan —
  a macro instance was renamed by Genus auto-ungroup. Also
  [03-floorplan.md](03-floorplan.md).
- **Density too high to place.** If `place_design` starts failing, the cause on
  this design is almost certainly the core shrink, not the netlist.

---

## 4. Clock tree synthesis

### What runs

[`cts_setup.tcl`](../../ASIC/genus-innovus/scripts/cts_setup.tcl) writes the
`_placed` snapshot and then sets exactly one thing:

```tcl
set_db cts_delay_cells {DEL*}
```

`cts_buffer_cells {CKB*}` and `cts_inverter_cells {CKN*}` are present but
**commented out deliberately**. The attributes are real and the patterns do
match `tcbn65lp` (it has `CKBD0..CKBD24`, `CKND0..CKND24`), but enabling them
constrains CCOpt's cell choice, which changes the clock tree and therefore the
whole hold profile. That is a physical change to evaluate on its own, not
something to bundle into a hold-repair experiment. For reference, the reference
run's clock tree used 41 228 `CKBD0`, 5 648 `CKND0`, 3 126 `CKBD1` — plus 3 290
`BUFFD1`, a general-purpose buffer that a `cts_buffer_cells {CKB*}` list would
have excluded.

Then [`3_pnr_clock.tcl`](../../ASIC/asic-flows/Cadence/3_pnr_clock.tcl):

```tcl
create_clock_tree_spec -out_file design_clk.spec
ccopt_design
opt_design -post_cts
opt_design -post_cts -hold
```

### What it produces

`work/design_clk.spec`, plus `reports/timing_summary_02_cts.rep`,
`timing_summary_03_cts_opt.rep` and the `03_cts_opt` power/QoR pair.

### What to check

```tcl
report_ccopt_clock_trees
report_ccopt_skew_groups
report_qor -format text
```

Measured, current run (CORE_TO_IO 70):

| Snapshot | WNS | UTIL | Insts | Wall |
|---|---|---|---|---|
| `CCOpt::Phase::Initialization` | — | 80.67 % | — | 0:01:40 |
| `ccopt_design` | +0.001 | 83.21 % | 192 607 | 0:31:24 |
| `opt_design_postcts` | 0.000 | 83.14 % | 192 373 | 0:10:48 |
| `opt_design_postcts_hold` | 0.000 | 83.58 % | 194 143 | 0:05:02 |

CTS plus post-CTS optimisation is therefore about 48–53 minutes end to end.
Density climbs only ~3 points across the whole of CTS. That is the healthy
picture; contrast it with §7.

---

## 5. Clock uncertainty — the classic that costs you three hours

This belongs on the CTS page because it is where the damage first shows, but it
lives in [`inputs/constraints.sdc`](../../ASIC/genus-innovus/inputs/constraints.sdc).

```tcl
set CLK_ERROR      0.35   ;# oscillator jitter, CDCM61001 worst case at 250 MHz
set CLK_HOLD_ERROR 0.05

set_clock_uncertainty -setup $CLK_ERROR      [get_clocks $EXTCLK]
set_clock_uncertainty -hold  $CLK_HOLD_ERROR [get_clocks $EXTCLK]
set_clock_uncertainty -setup $CLK_ERROR      [get_clocks $SWDCLK]
set_clock_uncertainty -hold  $CLK_HOLD_ERROR [get_clocks $SWDCLK]
```

**An unqualified `set_clock_uncertainty` applies to both setup and hold.** These
two clocks previously carried neither `-setup` nor `-hold`, so every hold check
in the design was charged the full 0.35 ns of oscillator jitter.

Why that is wrong: `$CLK_ERROR` is source jitter. For a setup check the launch
and capture edges are a period apart and the jitter is a legitimate margin. For
a same-edge hold check the source jitter is largely **common-mode** between
launch and capture and cancels. Charging hold 0.35 ns asks every hold path in
the design for delay it does not physically need — and the only way the tool can
supply delay is to insert cells.

Measured cost of the unqualified form:

- post-CTS hold repair inserted **62 729 instances** (+171 250 µm², utilisation
  75.0 % → 89.6 %)
- it drove setup WNS from +0.001 to **−0.729** doing it
- roughly 30 000 of the inserted cells were `DEL0`/`DEL005`/`DEL01`/`DEL015`
  delay cells — pure padding
- the worst hold violation entering repair was −0.726 ns, about half of which
  was this margin rather than real skew
- the 2026-07 reference run had the identical bug (+148 558 µm² of hold repair);
  it simply had less logic to apply it to

`0.05` covers residual non-common-mode jitter and PLL/duty-cycle effects. **It
is a signoff margin.** Revisit it against the clocking spec, not casually.

Two more things in that file that change what CTS and routing see, both
documented in place:

- **No `create_clock` for `rtc_clk` / `user_ref_clk` / `scan_clk`.** None is a
  pad on this chip: the first two are aliased onto the `sys_fclk` pad inside the
  generated wrapper, and `scan_clk` is tied `1'b0`. Constraining them separately
  would invent clocks that do not exist and cut real same-clock paths.
- **`set_clock_groups -asynchronous -name eth_chiplet_cdc`**, five groups, placed
  *after* the three IP SDC sources so every generated clock already exists.
  Without it the tool sees no relationship between the system clock and the D2D
  receive clock and times straight through the link synchronisers, which makes
  every number it reports meaningless. It is flagged `[OWNER]` as the
  deliberately conservative bring-up cut: for signoff, narrow the
  `D2D_RX_CLK_0` group rather than leaving it blanket.

---

## 6. Routing

### What runs

[`route_setup.tcl`](../../ASIC/genus-innovus/scripts/route_setup.tcl), after
writing the `_cts` snapshot:

```tcl
set_route_attributes -nets clk -preferred_extra_space_tracks 2
set_db route_design_detail_use_multi_cut_via_effort medium
set_db route_design_with_timing_driven 1
set_db route_design_with_si_driven 1
set_db timing_analysis_type ocv
```

then, in [`4_pnr_route.tcl`](../../ASIC/asic-flows/Cadence/4_pnr_route.tcl):

```tcl
route_design -global_detail
report_intermediate_step 04_route $REPORT_DIR
opt_design -post_route -hold
report_end_step 05_route_opt $REPORT_DIR
write_db $block_name
```

Reading of those five settings, stated conservatively — confirm any option
semantics you intend to change with `set_route_attributes -help` /
`get_db -help route_design_*` rather than trusting this summary:

- `-preferred_extra_space_tracks 2` on `clk` asks the router to leave two extra
  tracks of space beside clock wiring, reducing crosstalk-induced jitter on the
  tree CCOpt just built.
- `multi_cut_via_effort medium` trades runtime for double-cut vias — an EM and
  yield lever.
- `timing_driven` and `si_driven` make NanoRoute respect timing and
  signal-integrity costs rather than pure wirelength.
- `timing_analysis_type ocv` puts the timer into on-chip-variation mode. The
  post-route reports confirm this: `Analysis Mode: MMMC OCV`.

`filler.tcl` is **deliberately not sourced here** — see
[06-fill-antenna-bondpads.md](06-fill-antenna-bondpads.md) §2, which is the
single most useful "why" comment in the whole flow.

### What it produces

`reports/timing_summary_04_route.rep` and the `04_route` timing pair, then after
optimisation the `05_route_opt` summary/power/QoR set.

### What to check

```tcl
report_qor -format text
check_drc -out_file /dev/stdout        ;# 4_pnr_route.tcl already does this later
check_connectivity
report_route -summary                  ;# confirm with `report_route -help`
```

In the reference run global route reported `Overflow after Early Global Route
0.00% H + 0.00% V` at every checkpoint and detail route reported
`#Total number of DRC violations = 0` repeatedly, with final routed wirelength
around 10 084 000 µm. Congestion is not this design's problem. Density is.

Detail route takes about 18 minutes (baseline: `timing_03_cts_opt` reports at
14:09, `timing_04_route` at 14:27; current run 14:48 → 15:07).

---

## 7. Post-route optimisation — the long pole

This is where 2–3 hours of a 5-hour run goes. Baseline QoR row:

```
| opt_design_postroute_hold | WNS 0.068 | TNS 0 | FEPS 0 | UTIL 89.45 | INSTS 260119 | AREA 1805556 | WALL 3:06:20 |
```

Insts go from 194 869 to 260 119 — over 65 000 cells inserted post-route, almost
all of it hold repair. The current (denser) run's `HoldOpt` phase alone took
`real = 1:41:16` and added 33 666 cells while resizing 59 955.

Phase banners you will see, in order, inside that one command:

```
*** BuildHoldData #1 ...
*** HoldOpt #1 [begin] ...
*** Starting Core Fixing (fixHold) ... density=83.579% ***
    Phase I   : ECO Safe Resize, then AddBuffer + LegalResize   (~28 iterations)
    Phase II  : AddBuffer
    Phase III : AddBuffer + LegalResize
*** Finished Core Fixing (fixHold) ... density=91.720% ***
*** HoldOpt #1 [finish] ...
Running postRoute recovery in preEcoRoute mode
*** DrvOpt #1 [begin] ...
```

At the end of `Core Fixing`, Innovus prints a **cell-type histogram** of what it
inserted. Read it. In the current run: 18 380 `CKBD0`, 1 952 `CKBD1`, 4 185
`DEL005`, 2 317 `DEL2`, 1 757 `DEL1` … A histogram dominated by `DEL*` delay
cells is the fingerprint of an over-constrained hold check (§5).

It also prints **why it gave up**, which is the single most diagnostic block in
the log:

```
*info: 155965 net(s): Could not be fixed because of no legal loc.
*info:    692 net(s): Could not be fixed because of routing congestion.
*info:    589 net(s): Could not be fixed because of setup WNS degradation ...
```

`no legal loc` dominating means the rows are full — a density problem, not a
timing problem. Fix it with floorplan area, not with optimisation effort.

### Density: transient vs settled — compare like with like

Two different density figures appear in the log and **they are not the same
measurement**:

| Figure | Where | Meaning |
|---|---|---|
| `Density` column in the per-iteration opt tables | inside `Phase I/II/III` | **transient** — mid-optimisation, before legalisation has settled |
| `*** Starting Core Fixing (fixHold) ... density=NN% ***` | phase banner | **settled**, post-legalisation |
| `UTIL Density (%)` in `report_qor` | `reports/qor_*.rep` | settled, at the snapshot boundary |

Measured on the two runs:

| Run | Core | Entering fixHold (banner) | Opt-table peak (transient) | Leaving fixHold (banner) |
|---|---|---|---|---|
| `baseline_2026-08-05` | 1230 × 1630 | 75.518 % | 89.1 – 89.6 % | **89.143 %** |
| current | 1190 × 1590 | 83.579 % | 92.2 % | **91.720 %** |

Both banner columns above are `Starting`/`Finished Core Fixing (fixHold)` from the
two logs, so they are directly comparable — the smaller core lands **+2.6 points**
denser leaving hold repair. (`report_qor` reports its own `UTIL Density` at the
snapshot boundary, 89.45 % for the baseline; do not mix that with a banner figure,
which is exactly the mistake this section warns about.)

Quoting the opt-table peak of one run against the banner of the other is how you
convince yourself a run got 17 points worse when it got 8. Compare banner to
banner, or `report_qor` row to `report_qor` row.

**Survivability:** hold repair on this design ran to completion with the
opt tables sitting at 92.16–92.20 %, so ~92 % is demonstrably survivable. Above
roughly 95 % you start seeing legalisation fail to find sites for hold buffers
at all, and the `no legal loc` count above stops being a tail and becomes the
whole story.

### The per-iteration WNS/TNS are NOT the signoff numbers

This is the one that generates false alarms, so it is worth stating flatly.

The current run's post-route hold opt table **ends** at:

```
|  27|  -1.130|-71297.00|  100681|          0|       0(     0)|   91.87%| ...
```

WNS −1.130, TNS −71 297. The baseline run ended its equivalent table at
**WNS −1.156** and its final signed-off report was:

```
# SETUP                  WNS    TNS   FEP
 View : ALL            0.068  0.000     0
    Group : reg2reg    0.068    0.0     0
```

**+0.068 ns, TNS 0, FEP 0.** Not a contradiction and not luck. The opt tables
are printed against whatever view the optimiser is driving at that moment
(`default_analysis_view_setup` in the `Worst View` column). The final
`report_timing_summary` uses the analysis views selected at the end of
[`4_pnr_route.tcl`](../../ASIC/asic-flows/Cadence/4_pnr_route.tcl):

```tcl
set_analysis_view -setup [list typical_analysis_view] -hold [list typical_analysis_view]
# ... typical reports ...
set_analysis_view -setup [list default_analysis_view_setup typical_analysis_view] \
                  -hold  [list default_analysis_view_hold  typical_analysis_view]
```

The view definitions are in
[`nanosoc_eth_chiplet_pads.mmmc`](../../ASIC/genus-innovus/scripts/nanosoc_eth_chiplet_pads.mmmc):
`default_analysis_view_setup` is `tc_max` (wc lib) on `rcworst`;
`default_analysis_view_hold` is `tc_min` (lt lib) on `rcbest`;
`typical_analysis_view` is `tc_typ` on `typical`. So **do not raise an alarm off
an opt-table row.** Read `reports/${block}_imp_timing_late.rep` and
`reports/timing_summary_05_route_opt.rep`, and read
[07-reading-reports.md](07-reading-reports.md) first.

What *did* end badly in the baseline run, and is real, is DRV:

```
# DRV                           WNS        TNS   FEP
    Check : max_transition   -3.035  -1032.060  1243
    Check : max_capacitance  -0.173     -2.361   618
```

1 243 max-transition and 618 max-cap endpoints. That is a genuine open item, not
a reporting artefact — see [11-known-issues.md](11-known-issues.md).

---

## 8. Measured timings — budget your run

srv03335, `-local_cpu 14` (16 physical cores, 4×4, no SMT; distribution off by
default because the measured inter-host link is ~25 MB/s, ~37× slower than local
disk — see [`config.tcl`](../../ASIC/genus-innovus/scripts/config.tcl)).

| Stage | Wall |
|---|---|
| `place_design` | ~20 min |
| CTS + post-CTS opt (`ccopt_design` + two `opt_design -post_cts`) | ~53 min |
| detail route (`route_design -global_detail`) | ~18 min |
| **post-route opt + hold** | **~2–3 h** ← the long pole |
| filler + bond pads + checks + `write_stream` | ~20–30 min |

Override CPU allocation per run from the environment rather than editing scripts:

```sh
INNOVUS_LOCAL_CPU=8 make pnr_route
INNOVUS_DISTRIBUTED=1 INNOVUS_REMOTE_HOSTS=srv04936 make pnr_route   # rarely worth it
```

---

## 9. Failure modes, in the order you will meet them

| Symptom | Cause | Fix |
|---|---|---|
| `make pnr_route` says `FAIL: no GDSII` but the log looks clean | Innovus exits 0 on a rejected argument | `grep -nE '\*\*ERROR\|Unknown argument' work/innovus.log*`; check `ASIC/asic-flows` is at `b19e784+` |
| Hold repair inserts tens of thousands of `DEL*` cells | unqualified `set_clock_uncertainty` (§5) | qualify `-setup` / `-hold` |
| `no legal loc` dominates the hold-failure reasons | rows are full | more core area, not more effort |
| Density looks 15 points worse than last run | comparing an opt-table row to a banner | compare like with like (§7) |
| Opt table ends at WNS −1.1, panic | wrong analysis view | read the final `report_timing_summary` (§7) |
| `TCLCMD-1130` at the top of every `timing_summary_*.rep` | `report_timing_summary -late -early` needs simultaneous setup/hold mode | harmless; the tool falls back to `-late`. See [07-reading-reports.md](07-reading-reports.md) |
| Experiment costs a 5-hour replay | you did not resume from a snapshot | §2 |

---

## Related pages

[00-index.md](00-index.md) ·
[01-flow-overview.md](01-flow-overview.md) ·
[02-innovus-basics.md](02-innovus-basics.md) ·
[03-floorplan.md](03-floorplan.md) ·
[04-power-plan.md](04-power-plan.md) ·
**05-place-cts-route** ·
[06-fill-antenna-bondpads.md](06-fill-antenna-bondpads.md) ·
[07-reading-reports.md](07-reading-reports.md) ·
[08-debugging.md](08-debugging.md) ·
[09-signoff-checklist.md](09-signoff-checklist.md) ·
[10-tapeout-submission.md](10-tapeout-submission.md) ·
[11-known-issues.md](11-known-issues.md)
