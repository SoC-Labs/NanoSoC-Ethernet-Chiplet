# 23 — P&R flow notes

Design-specific measurements and tool traps behind the three evaluation stages
`ASIC/genus-innovus/scripts/{2b_pnr_place,3b_pnr_cts,4b_pnr_route}_eval.tcl` and their
shared helper `scripts/pnr_utils.tcl`.

Those scripts are written to be read by students learning the flow, so their comments
explain *what each stage does*. This file holds the *why* — the measurements, the
one-off findings, and the tool behaviours that cost someone a day. When a script says
"see note 7", this is the file.

This is the P&R companion to [22-synthesis-flow-notes.md](22-synthesis-flow-notes.md),
which does the same job for `1b_synthesis_eval.tcl`.

Everything here was measured on `nanosoc_eth_chiplet_pads` (TSMC 65nm LP, die
1600×2000 µm, ~189k placed instances, Innovus 21.11-s130_1 stylus) unless stated
otherwise.

> **The numbers in `docs/tapeout/` pages 11–21 describe the 2026-08-06 run.** The
> 08-07 run moved on in both directions — hold closed, setup regressed. See note 1.

---

## 1. The state of the design changed on 2026-08-07, and most of these docs predate it

| post-route | 08-06 | 08-07 |
|---|---|---|
| hold WNS / TNS / violating paths | −1.167 ns / −66,212 ns / 96,545 | **−0.004 / −0.005 / 3** |
| setup WNS / TNS / FEP | +0.079 / 0 / 0 | **−0.242 / −151.803 / 1,804** |
| DRV `max_transition` / `max_capacitance` FEP | 1,243 / 618 | 30 / 15 |
| `check_drc` | 102 | 64 |

Sources: `baseline_2026-08-0{6,7}/reports/timing_summary_05_route_opt.rep` and
`baseline_2026-08-0{6,7}/work/timingReports/*_postRoute_hold.summary.gz` (`zcat` them).

The OCV-first fix (note 3) worked, and took most of the DRV blocker with it — which
supports the theory that those violations were hold-repair side-effects rather than real
ones. **The open blocker is now setup**, which `preplace.tcl` predicts as the cost of
confining signals to M1–M7. That regression is budgeted by the route stage but it is
**not explained**.

Re-measure before quoting any timing number from pages 11–21.

## 2. `report_timing_summary` emits no hold section, and says so in the report

This is [19-timing-audit.md](19-timing-audit.md) R10, and it is the reason
`pnr_utils.tcl` exists at all. The first line of every summary the production flow ever
wrote is the tool refusing:

```
**ERROR: (TCLCMD-1130): The '-late' and '-early' options to the report_timing_summary
command can only be specified together when the timing system is in simultaneous setup
and hold mode. ... Ignoring '-early' and using '-late' alone.
```

printed *into the report file*, where nobody read it. So the headline
"WNS +0.079, 0 failing endpoints" was setup-only, and the tool's own closing line is
labelled `timing.setup.wns`.

The fix is to enter the mode first:

```tcl
set_db timing_enable_simultaneous_setup_hold_mode true
report_timing_summary -checks {setup hold drv} > $summary
set_db timing_enable_simultaneous_setup_hold_mode false
```

Two caveats the reference states: all non-timing commands are disabled while the mode is
on, so it must be turned off again before any physical step; and entering it rebuilds the
timing graph, so it is not free. **The runtime cost on a design this size has not been
measured** — do that on the first run and record it here.

`pnr_hold_summary` is deliberately **not** wrapped in `try_step`. It carries the
`flow_fail` that fires when a summary comes back with no HOLD block; wrapped, a summary
command that *errored* would be downgraded to a warning and the stage would carry on with
no hold numbers at all — which downstream reads as a pass. That is the exact defect this
file exists to stop, so the gate is not allowed to be optional.

## 3. The source-latency writeback — the defect that cost 96,545 phantom hold violations

The single most valuable thing in this flow to understand.

After building the tree, `ccopt_design` writes its insertion delay back as a **negative
source latency**, so I/O constraints written against an ideal clock stay valid. It does
that per (clock, view), and it emits only the sides the analysis mode has.

With OCV still **off** at that moment, min and max are not separated, and for the hold
view it wrote the `-min` form only:

```
set_clock_latency -source -early -min -rise -1.07637 [get_pins CLK]
set_clock_latency -source -late  -min -rise -1.07637 [get_pins CLK]
```

`route_setup.tcl` then turned OCV on. Min and max separated — and a hold check needs the
launch clock's MIN path and the capture clock's MAX path. Launch found −1.076. Capture
found nothing and used **zero**:

```
                 Capture       Launch
  Src Latency:+    0.000       -1.108      Slack:= -1.086
```

Every hold check in the design lost ~1.1 ns of pure fiction. Cost: hold WNS −1.167 ns,
TNS −66,212 ns, 96,545 violating paths, +37,407 hold-repair instances and +90,682 µm²
chasing skew that was not there — which drove density 83.6% → 92.2% and then blocked DRV
repair. And it was invisible, because of note 2.

**The fix** is one line moved: `set_db timing_analysis_type ocv` now runs in
`cts_setup.tcl`, *before* `ccopt_design`, so ccopt emits both sides itself.

Writeback counts, measured on both sides of the fix. 4 clock roots × early/late ×
rise/fall = 16 lines per side per view when complete:

| view | before (08-06) | after (08-07) |
|---|---|---|
| `default_analysis_view_setup` | min 0, max 16 | min 16, max 16 |
| `default_analysis_view_hold` | **min 16, max 0** | min 16, max 16 |
| `typical_analysis_view` | min 16, max 16 | min 16, max 16 |

The hold row is the defect.

**What was tried and rejected:** two-sided delay corners in the `.mmmc` (no effect — the
writeback was byte-identical, because `set_clock_latency -min/-max` is a property of the
CLOCK, not of the delay corner); and mirroring `-min` onto `-max` after CTS (works, but
the values change with every clock tree).

**How to check it, and a correction.** `cts_setup.tcl`'s closing comment gives a log
grep, and `3b_pnr_cts_eval.tcl` implements it as a parse. Both are working around a
claim that turns out to be false: `holdexp/probe_latency_attrs.tcl` concluded the applied
source latency "is simply not readable back", having tried eleven attribute names. It
missed the right ones. `DBcom/clock.html` in the installed 21.11 reference documents
**eight** attributes on the `clock` object:

```
source_latency_early_fall_max   source_latency_early_fall_min
source_latency_early_rise_max   source_latency_early_rise_min
source_latency_late_fall_max    source_latency_late_fall_min
source_latency_late_rise_max    source_latency_late_rise_min
```

each "specified by an explicit `set_clock_latency` on the clock" — exactly what ccopt
issues — plus `view_name` (which is why the probe saw 27 per-view clock objects) and
`clock_setup_uncertainty` / `clock_hold_uncertainty`. Default is `""`, so a side never
written reads empty: the defect signature, queryable directly.

**A DB query would be strictly better than the log parse**: immune to log format, to the
`@file` echo trap (note 18), to `redirect`, and — the real prize — it works on a database
read back later, so the route stage could run the same check on its input DB. Not yet
done. `probe_latency_attrs.tcl`'s conclusion should be corrected when it is.

Note this is an **Innovus** finding. Genus has its own attribute model, so
[22](22-synthesis-flow-notes.md) note 9's claim that uncertainty is not queryable there
is a separate question and is not disproved by this.

## 4. `timing_analysis_type ocv` is not derating

Easy to conflate, and the distinction matters:

- `set_db timing_analysis_type ocv` **separates min from max**. It is what makes a hold
  check use different numbers from a setup check. It applies no margin of its own.
- `set_timing_derate` **applies the margin** — the actual ±% on cell and net delays.

19-timing-audit R1 is that this design carries **no `set_timing_derate` anywhere** — not
in any SDC, script or mmmc, and zero occurrences in the 118,671-line run log. So its
entire on-chip-variation budget is the clock uncertainty.

Both stages expose a derate knob, both default **off**, and the factors in them
(`-early 0.95 / -late 1.05` on data, `0.97 / 1.03` on clock) are **a guess** — R1 quotes
them as a 65 nm norm, not as a characterisation of `tcbn65lp`. Turning the knob on tells
you what derate costs; it does not tell you what the right derate is. That needs foundry
data.

One spelling trap: `set_timing_derate` with neither `-data` nor `-clock` sets one and
lets the other inherit — "if you specify only one of `-data` or `-clock`, the software
uses the last defined value for the other". Issue all four explicitly.

## 5. Where P&R actually gets its constraints

**Not from `inputs/*.sdc`.** The `.mmmc` file names
`../outputs/${block_name}_syn.sdc` — the SDC that **synthesis** wrote. So editing a
constraint in `inputs/` and re-running placement changes precisely nothing, with no
warning.

That is the state this tree was in on 2026-08-07: four `inputs/*.sdc` edited that
afternoon, against a `_syn.sdc` from 08-05. The Makefile's `sdc-check` target exists for
this; the place stage now asserts the same thing in-tool, because the flow is run by hand
as often as by `make`.

The in-tool version is better in one respect: it reads the SDC path **out of** the mmmc
rather than assuming it, which is the whole point — people assume `inputs/` and are wrong.

Corollary for `EVP_SYN_DIR`: pointing the netlist at `../outputs/eval` without also
supplying an `EVP_MMMC` that names the eval SDC gives you an eval netlist timed against a
production SDC. The stage detects exactly that and warns.

## 6. The CPF that cannot fill the die

Genus cannot translate this design's UPF supply commands, so the CPF it writes carries
only `create_power_domain -name PD_TOP -default` — no power net, no ground net.

Every Innovus filler pass then fails with `IMPSP-5110`, **while the flow completes and
streams a GDS**. The 2026-08 run shipped a GDSII with zero filler cells and 95,568
free-site gaps, and the only symptom was a message that reads like noise.

`make cpf-patch` repairs it and is idempotent. `power_plan.tcl` guards it too, but only
*after* the floorplan has run, so the place stage asserts it up front.

## 7. `init_design` ordering, and why it cannot be rearranged

Four constraints, each of which fails silently rather than loudly:

1. `init_power_nets` / `init_ground_nets` are consumed by `init_design`'s power-domain
   creation step. Set them later and they have no effect at all — no warning.
2. LEFs can only be read **before** `init_design`. Afterwards the door closes and adding
   one needs `-add_lefs`.
3. `commit_power_intent` **recreates the rows** by default. Move it below `floorplan.tcl`
   and the row structure is silently lost.
4. The power plan must precede placement: stripes occupy cell and routing area, and
   `split_row` runs over the placed macros.

Two orderings the production stage gets *arguably* wrong and the eval stage leaves alone
behind off-by-default knobs, because the equivalence has never been established here:
`read_power_intent` after `init_design` rather than before (the manual lists it as a
prerequisite), and `design_process_node` set after rather than before (so row and track
creation ran at the 90 nm default).

## 8. Macro names move, and `place_macro` fails quietly

Genus runs with auto-ungroup on, so macro instance names change when the RTL changes.
`place_macro` then reports "matched 0 instances" and carries on, and the macro sits at
the origin.

Worse, `place_macro` aborts on the **first** stale pattern, so a rename costs one
20-minute run per bad name to discover. The place stage resolves all 21 patterns *before*
sourcing `floorplan.tcl`, by reading the patterns out of `floorplan.tcl` itself rather
than duplicating the list.

Duplicating it is not hypothetical: `power_plan.tcl` carried its own hardcoded copy of 21
hierarchical paths, six went stale, and `split_row` silently ran on 15 of 21 macros for
months. `scripts/probe_macros.tcl` exists to dump the current names.

## 9. The PG grid, and a query that returns zero

[21-physical-audit.md](21-physical-audit.md) P1–P14 mostly live in the place stage. The
ones the flow now measures every run:

| finding | measured |
|---|---|
| P1 | core `VSS` enters on 4 bond pads, `VDD` on 6; neither rail has a pad on the left or right edge |
| P2 | the whole core PG grid reaches top metal through **8 RV vias and 5 AP shapes**, down from 14 |
| P3 | 446 of 9,013 M4→M9 via stacks never reach M9 (the true, uncapped `IMPPP-531` count — the printed 20 was the message cap) |
| P4 | 1,518 dangling PG wires, uncapped — 4.3× the 350 opens, never triaged |
| P5 | the M5 stripe grid fragmented 1,044 → 1,407 (+34.8%) on a *smaller* core |
| P9 | endcap coverage fell by 23 row-ends; 4,446 total (2,223 pre + 2,223 post) |

**The query trap.** P2's "confirming experiment" asks for `RV` in the
`.via_def.bottom_layer.name` slot. `RV` is a **cut** layer (`LAYER RV / TYPE CUT ;` in
`PRTF_EDI_N65_<stack>_RDL.<rev>.tlef`), and `DBcom/via_def.html` defines `bottom_layer`
as "the bottom **routing** layer" — M9 for a `VIA9AP_*`, never RV. So the documented query
matches nothing and returns 0, which reads as catastrophic power delivery rather than as a
typo. Use `.via_def.cut_layer.name`. P2's stated falsification criterion does not
anticipate the answer 0, so a reader would mis-diagnose it. **P2 in
[21](21-physical-audit.md) still has the wrong spelling and should be corrected.**

P8 is worth knowing when reading P1: `power_plan.tcl`'s third `route_special`
(`-pad_pin_width 6`) is a complete no-op in both runs, so the pad risers are 1.63 µm (VDD)
and 1.5 µm (VSS), not 6 µm.

## 10. Placement costs 59 ns of setup, and nothing repaired it until recently

From this design's own baselines:

| snapshot | setup WNS | TNS | FEP | max_tran FEP |
|---|---|---|---|---|
| `00_pre_place` | −126.815 | −3,830,180 | 39,526 | 11,317 |
| `01_place` | −185.650 | −5,908,965 | 57,293 | 156,197 |
| `02_cts` | +0.001 | 0 | 0 | 0 |

Placement costs 59 ns of setup and multiplies DRV endpoints 13.8×, and nothing repaired
any of it before CTS. `ccopt_design` cleans it up, which is why it went unnoticed — but
`preplace.tcl` sets `place_global_timing_effort high`, so **placement itself** is being
driven by that timing graph. At TNS −5.9e6 ns a real 10 ns path with 0.1 ns of slack is
numerically invisible: timing-driven placement was nominally on and effectively disabled.

The dominant term is one gate — an `OR2D1` on the TEST distribution net at fanout 11,009,
trans 0.692, delay 190.365 ns. The same gate is 123.870 ns at pre-place, so spreading the
cells across the core added 66.5 ns to it.

`opt_design -pre_cts` in `postplace.tcl` now repairs it, at 80.67% density rather than
post-route at 92.17% where recovery is documented to fail. Runtime cost on this design is
**not yet measured**; expect +20–45 min.

Consequence for reports: the `01_place` snapshot is taken **before** `postplace.tcl`
runs, so it describes the pre-optimisation state. That is deliberate and historical — the
opt writes its own `01b_place_opt` set. Do not "fix" the ordering; it would silently
change what every archived `01_place` report means.

## 11. Clock tree roots have no driver model

Three CTS-stage findings from [17-silent-noops.md](17-silent-noops.md), all of which ran
silently on every build:

- **IMPCCOPT-4313** ×4, one per clock tree: every root has no driver model, so CCOpt
  assumes an ideal source. Root slew comes out ≈ 0, which is unphysical (R11).
- **IMPCCOPT-1033** ×4: the max-capacitance constraint on the clock source is 0.000 pF.
- **TA-1018** ×5: five generated clocks analysed with zero source latency (R4).

The first two are fixable in the CTS stage via `cts_clock_tree_source_driver` and
`cts_clock_tree_source_max_capacitance`, and both knobs exist, defaulted **off** — a
driver model changes the tree that gets built, and 17-silent-noops prefers the SDC route
(`set_driving_cell` fixes timing analysis too, not just CTS).

TA-1018 is **not** fixable here: the cause is `create_generated_clock` declared on module
ports or hierarchical pins in `inputs/*.sdc`, and the fix is to re-declare on the driving
output pin and re-synthesise. It is counted and reported so it stays visible.

## 12. The clock tree spec file is write-only, but the command is not

`create_clock_tree_spec -out_file design_clk.spec` — nothing in this flow sources that
file, and it could only be sourced once anyway (a second attempt needs
`delete_clock_tree_spec` / `reset_cts_config`). The reference is explicit: "The file is
not executed."

The **command** is load-bearing regardless — it applies the specification to the
in-memory database, and without `-out_file` it still does. So `-out_file` buys exactly one
thing, and it is worth having: "The specification file that is generated records the
**reasons** for the constraint settings… In case the `-out_file` parameter is not
specified, no information about the reasons for constraint settings will be stored."

It is the only place the tool explains why it made each CTS decision.

Related, and left alone deliberately: `cts_buffer_cells` / `cts_inverter_cells` are
commented out in `cts_setup.tcl` with the reasoning stated there. For reference, this
design's tree used 41,228 `CKBD0`, 5,648 `CKND0`, 3,126 `CKBD1` — plus 3,290 `BUFFD1`, a
general-purpose buffer a `cts_buffer_cells` list would have excluded. The design also sets
no `cts_target_max_transition_time` anywhere; the generated spec contains zero
`cts_target_*` lines. Both are defensible gaps, but they are currently *undocumented* ones.

## 13. Filler and bond pads: the ordering, and what it was worth

Two orderings that were wrong and are now right. Neither must be undone.

**Filler runs after routing, not before.** Sourced before `route_design`,
`add_fillers -check_drc -fix_drc` had no routing to check against ("Found no DRC
violations to fix"), the ANTENNA diodes went in before any antenna existed, and post-route
hold repair had to carve ~66,000 buffers back out of filled rows. `filler.tcl` is now
sourced from `place_bondpads.tcl`, after `opt_design -post_route -hold`.

**`filler.tcl`'s own `check_drc` runs before the bond pads exist**, so the marker set
`-fix_drc` and `route_eco -target` act on describes the core only. With the pads in, the
repair would be handed a database dominated by M8/M9/AP pad-ring geometry it cannot touch.

**The measured yield, which beat the prediction.** 14-drc-triage expected "very few" of
the 38 M1 `EndOfLine` violations to clear. On 2026-08-07:

```
_imp_drc_prerepair.rep   130 violations, 66 of them EndOfLine on M1
_imp_drc.rep              64 violations,  0 of them EndOfLine
```

`route_eco -target` ran clean — no `catch` fired, exit status 0, 7 M1 `EOLSpc` violations
to 0 in 00:01:31 elapsed / 00:08:03 CPU. **That closes `filler.tcl`'s "UNVERIFIED / FIRST
PERSON TO GET A SEAT" note, and its `catch` can be deleted.**

## 14. What this GDS is not

`gds_merge_list` merges only the 8 memory macros. Standard cells, IO drivers and bond pads
are **empty references**, because this site's PDK ships LEF and liberty but no GDS or CDL
for them (`IMPOGDS-218` counts 411 unmerged masters on 08-07, 424 on 08-06).

So every DRC number this flow produces is a **routing and PG check, not signoff DRC** —
front-end, density and seal-ring rules are meaningless against this stream. LVS cannot run
here at all. Both unblock together, on procurement rather than engineering.

Also absent from the whole flow and genuinely in scope: **metal density fill**.
`add_metal_fill` appears nowhere in the production flow. The route stage now carries
`EVR_METAL_FILL` / `EVR_VIA_FILL` knobs, defaulted **off**, because fill changes coupling
capacitance and therefore timing, and the question of who does fill — us or the foundry —
is still open with the broker. Note `add_via_fill` takes its parameters from
`set_metal_fill`, which this flow does not issue, so that knob is not yet known to do
anything.

Out of scope entirely, and listed in the route stage's gate file every run so a green
board cannot be misread: cell-level GDS merge, LVS, seal ring and scribe, IR drop, foundry
antenna checks, and post-P&R LEC (`make lec-pnr` exists and is not wired into the eval
chain).

## 15. The physical checks cap themselves at 1,000 markers

`check_connectivity`, `check_drc` and `check_process_antenna` all stop creating markers at
a limit. Both baselines saturate — the connectivity report's own trailer reads
`1000 total info(s) created.` — so the familiar "318 opens / 680 dangling" figures are
**ceilings, not counts**.

Uncapped, the same defect is **350 opens and 1,518 dangling** (P4). The route stage raises
the limits to 200,000 by default. If you turn that off, the budgets no longer mean what
they say.

Do not re-run what 11-known-issues (a) already falsified for the 329 PG opens. The two
things its "what to do next" asks for and nobody had done — defeat the message cap, and
split `check_connectivity` per net — are now done every run.

`check_filler` has a second trap: the `-out_file` form is empty after its header in both
baselines, and only the redirect form prints the gap count (P11). The stage does both.

## 16. Calibre in the flow has never worked here

The production route stage ends with two `$env(CALIBRE_HOME)` blocks. Both fail on this
site: the `cal_enc.tcl` source dies with `IMPSE-110: can't find package Tk 8.0`, and the
failing `exec calibre` aborts the script **before** its `exit` — so Innovus sits at a
prompt holding a licence seat and `make` never returns.

The Makefile works around it with `env -u CALIBRE_HOME`. The eval stage does not shell out
to Calibre at all, so the trap does not exist there and no `env -u` is needed.
`make drc` is the working headless path.

## 17. Signoff budgets: ratchet or zero?

The route stage's gate has two tiers — **hard** failures (a missing artefact, a DRC
violation in a class this stage owns, an unallowlisted error) which are always fatal, and
**budgeted** signoff numbers which fail only on regression.

The budgets default to the **measured 08-07 values**, not to zero. The argument for that:
while these defects are open and owned elsewhere (the PG grid, the constraint files), a
budget of zero makes every run red and therefore ignored, and a gate everyone overrides is
worse than no gate.

**The argument against, for one of them specifically:** `EVR_BUDGET_SETUP_FEP 1804` is an
*unexplained regression from 0*, and the suspected cause — `design_top_routing_layer 7` —
is a setting this flow introduces. Ratcheting to it makes the bug the definition of pass.
Recommend setting it to **0** and letting the run report `SIGNOFF NOT CLEAN`, which is the
true state of the design and exactly what the two-tier gate exists to express. The other
budgets are long-standing, diagnosed, owned-elsewhere defects and are fair to ratchet.

Two related hazards: every budget currently sits *exactly* on the measured value with `>`
comparisons and no headroom, on quantities that multi-threaded routing can perturb — so
expect flapping; and `Status : OK - within every budget` is how a design with 1,804
failing setup endpoints ends up described as OK in a screenshot. Reserve the word
"signoff" for `EVR_SIGNOFF_STRICT=1`.

## 18. Counting messages: Innovus is better than Genus, and `grep` is worse than both

Innovus returns Tcl values where Genus prints a table:

- `report_messages -errors` → "Returns a list of issued error message IDs as a Tcl result"
- `get_message -id <ID> -count` → "the number of times this message has been issued"

These are **issue counts, not printed-line counts**, so they are immune to the display cap
below. Prefer them to any log parse.

Three traps when you do have to read a log:

1. **The 20-instance display cap.** Innovus prints at most 20 instances of any message ID
   and then goes silent. `config.tcl` now issues `set_message -no_limit`, but it was added
   at 14:12 on 2026-08-07 — *after* that day's route run, which still shows seven
   `EMS-27` cap warnings. **Every message count from either baseline is a floor, not a
   total.**
2. **`@file` echo lines.** Innovus echoes sourced Tcl, including comments, prefixed
   `@file NNN:`. A comment that quotes a message ID is counted by a naive `grep -c`. All
   three `NRDB-51` "hits" in the 08-06 log are the comment in `config.tcl`; every
   `IMPSP-9082` occurrence on 08-07 is `filler.tcl`'s own header, and the true count is 0.
   Filter `^(?:\[[^\]]*\])?@file [0-9]+:` — note the timestamp prefix, which is present in
   `innovus.logv` and absent in `innovus.log`.
3. **Multiple summary blocks.** The CTS log contains five separate "Message Summary"
   blocks, and for some IDs the tool's own count is half the raw `**WARN` line count.
   Treat the tool's count as authoritative and do not compare it against a `grep -c`.

**Error IDs this design actually raises**, per production session — the reason the three
stages carry *different* allowlists rather than one shared list:

```
2_pnr_setup : TCLCMD-917 ×20, IMPLF-223 ×20, IMPSP-9099 ×2, IMPMSMV-3501 ×1
3_pnr_clock : IMPLF-223 ×20, IMPMSMV-3501 ×1
4_pnr_route : IMPLF-223 ×20, IMPMSMV-3501 ×1
```

The SDC-load and scan-chain errors only occur at `init_design`. Do not "unify" the lists.

Each is diagnosed: `TCLCMD-917` is `constraints.sdc:79`'s `uPAD*/*` expanding to 68 pad
*supply* pins that `get_pins` never returns (16-open-defects §5); `IMPLF-223` is duplicate
LEF via definitions across the 12 LEFs; `IMPSP-9099` is a false positive from Genus mapping
load-enables onto the `SDF*` scan mux with DFT off (§6); `IMPMSMV-3501` is the power intent
defining no `power_mode`/`power_state` — benign on a single-domain chip and blocking the
moment the D2D domain split happens (11-known-issues (d)).

`IMPSP-9099` is deliberately **not** suppressed with `set_message -suppress`: a suppressed
message cannot be counted, and stable visible counts are the point.

> **⚠ Updated 2026-08-18 — `IMPSP-9099` is no longer emitted at all.** Last occurrence
> **2026-08-07 14:21**; zero in every build from 08-08 onward (positive control: nine
> other `IMPSP-*` IDs are present in the same logs). The reasoning above still stands as
> policy, but it now applies to nothing. `2b_pnr_place_eval.tcl:158` still lists
> `IMPSP-9099` in `EVP_ERROR_ALLOWLIST`; that entry is **dead but deliberately left**, so
> the allowlist still tolerates the message if a future flow change reintroduces it.
> The live scan message is `IMPSP-9025` (WARN, "No scan chain specified/traced").
> See `16-open-defects.md` §6 for the census, which also changed by ~10× and inverted.

## 19. Two helpers write production database names

`cts_setup.tcl` opens with `write_db ${block_name}_placed` and `route_setup.tcl` with
`write_db ${block_name}_cts`. Those snapshots exist so an experiment costs ~1 h instead of
a ~5 h re-run — but they are *production* names written from *configuration* files, so any
variant flow that sources those helpers (as it must, to pick up the OCV fix and
`cts_delay_cells`) would overwrite them.

Both eval stages therefore shadow `write_db` for the duration and rewrite production-named
targets into the eval namespace. That is ~25 lines of `rename` machinery in each of two
files, working around one line in each of two helpers it may not edit.

**The fix belongs in the helpers**, and it is two lines:

```tcl
if {![info exists ::cts_snapshot_db]} { set ::cts_snapshot_db ${block_name}_placed }
write_db $::cts_snapshot_db
```

Then every downstream guard disappears. Until then, note the guards currently redirect onto
each stage's *own input* DB tag, which is near-idempotent in the normal case but poisons the
namespace when resuming a production snapshot — the redirected write lands on
`${block_name}_eval_cts` carrying the *production* design.

## 20. Runtime, and what to watch

Measured stage times (`qor_0*.rep`): `place_design` 0:17:49, `ccopt_design` 0:29:01,
`opt_design -post_cts` 0:11:15, `-post_cts -hold` 0:04:26, `-post_route -hold` 0:29:01.
A full place stage is ~21 min (totcpu 1:10:50 / real 0:21:35 on 08-07).

Near-free, and worth running every time: `check_design -type cts`,
`ccopt_design -check_cts_config`, the per-net `check_connectivity` loop (~4 s each),
`check_drc` (22 s elapsed / 2:12 CPU — the marker limit bounds the report, not the check),
every log and report parse, the manifests, and the message census (a tool query).

**Not measured, and each added to a multi-hour run:** entering simultaneous setup/hold
mode (note 2), `report_analysis_coverage -verbose`, `check_metal_density -detailed`,
`check_power_vias`, and `add_metal_fill`.

**One default worth reconsidering:** `report_constraint -all_violators` at `01_place`
enumerates every violator three times, and `max_transition` FEP at that milestone is
**156,197** (note 10). That is a large report of a meaningless number — DRV before CTS
says nothing. It is useful at `03_cts_opt` and `05_route_opt`, where the counts are 0 and
45.

## 21. Smaller traps

- **`-files`, not `-f`.** `-f` is not a stylus argument: Innovus raises `IMPSYT-468`,
  prints usage and **exits zero**. Three P&R stages once "passed" in under a minute that
  way. Redirect stdin from `/dev/null` too, or a failing run sits at a prompt holding a
  seat.
- **`\b` in a Tcl regexp is a backspace, not a word boundary.** The word boundary is
  `\y`. A pattern using `\b` silently matches nothing.
- **`regexp {-...}` reads the pattern as an option.** Put `--` before any pattern that
  starts with `-`.
- **SDC commands after `init_design` need `set_interactive_constraint_modes`**, or they
  are silent no-ops (`TCLCMD-1048`).
- **`design_top_routing_layer`, not `route_design_top_routing_layer`** — the latter does
  not exist. The attribute is documented as taking a layer *name* (`M7`);
  `preplace.tcl` passes the integer `7` and whether that is accepted is **unverified**.
- **`check_cut_density` takes `-out_file`; its sibling `check_metal_density` takes
  `-report`.** Two near-identical commands, two spellings.
- **`inst` has no `.cell` attribute** — it is `.base_cell`.
- **`report_analysis_coverage -verbose` takes a status list**, e.g. `-verbose untested`.
- **`report_timing -path_type` values are `{endpoint summary full full_clock}`.**
  `full_clock_expanded` is the PrimeTime spelling.
- **`set_db information_level` is a GENUS attribute** and does not exist in Innovus.
  Copying it across from `1b_synthesis_eval.tcl` aborts the stage on its first line.
- **A bad option inside `try_step` still fails the run.** `try_step` catches the Tcl
  error, but the tool has already *issued* the message, and the end-of-stage census then
  fails on an ID that says nothing about which report caused it. Command-syntax errors are
  script defects, not design results — worth reporting separately.
