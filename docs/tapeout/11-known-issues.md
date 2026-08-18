# 11 — Known issues

[← 10 Tapeout submission](10-tapeout-submission.md) · [index](00-index.md)

The live open items on `nanosoc_eth_chiplet_pads`. Each entry says **what is known**,
**what has already been tried and ruled out** — so nobody spends a five-hour run
re-falsifying a hypothesis — and **what to do next**.

Numbers come from the 2026-08-05 baseline unless stated otherwise:
`ASIC/genus-innovus/baseline_2026-08-05/reports/`.

| | Issue | Severity | State |
|---|---|---|---|
| [a](#a-329-pg-opens-reported-by-check_connectivity) | 329 PG opens (`check_connectivity`) | **blocking** | root cause **unknown**; 2 hypotheses falsified |
| [b](#b-bond-pad-obs-drc-318-pg-shorts) | Bond-pad OBS DRC, 318 PG shorts | **blocking** | root-caused; fix in flight |
| [c](#c-qspi-flash-cache-tag-rams-have-an-undriven-gwen) | QSPI tag RAM `GWEN` undriven | medium | real RTL defect, present in the reference GDSII too |
| [d](#d-power-intent-defines-no-power_modepower_state-impmsmv-3501) | No `power_mode`/`power_state` (`IMPMSMV-3501`) | low here | architectural; blocks always-on buffering |
| [e](#e-clk_hold_error-005-is-an-unconfirmed-signoff-margin) | `CLK_HOLD_ERROR = 0.05` unconfirmed | medium | needs an owner decision, not a run |
| [f](#f-check_cpf-errors-tolerated-by-a-wrapper-in-configtcl) | `check_cpf` errors tolerated by a wrapper | low | deliberate; conditions stated below |
| [g](#g-1243-max_transition-618-max_capacitance-violations-post-route) | 1,243 `max_transition` + 618 `max_capacitance` | **high** | observed, **never triaged** |
| [h](#h-filler-runs-post-route-and-nothing-cleans-up-after-it) | Filler post-route, no `eco_route` after | medium | two tool warnings, one silent no-op |
| [i](#i-post-pr-logical-equivalence-is-stale-not-absent) | Post-P&R LEC is stale, not absent | medium | ran clean 2026-08-08, on a superseded netlist |

---

## a) 329 PG opens reported by `check_connectivity`

### What is known

```
Net VSS: has special routes with opens at (155.000, 82.815) (1445.000, 1917.185)
Net VSS: has special routes with opens at (1034.500, 419.435) (1058.900, 421.355)
…
Begin Summary
    329 Problem(s) (IMPVFC-200): Special Wires: Pieces of the net are not connected together.
    671 Problem(s) (IMPVFC-94): The net has dangling wire(s).
    1000 total info(s) created.
End Summary
```

`reports/nanosoc_eth_chiplet_pads_imp_connectivity.rep`. Every open is on `VDD` or `VSS`;
there are none on signal nets.

> **The report caps at 1,000 messages.** `1000 total info(s) created` means the list
> saturated, so **329 is a lower bound** and so is 671. Two runs that both report 329 have
> not necessarily got the same number of opens — a fact that made the first experiment
> below much less informative than it looked.

**A candidate fragment has been located but not explained.** An M5 `VSS` special-wire
fragment at `(1058.3, 1594.035)–(1072.9, 1594.365)` sits adjacent to a macro edge. The
connectivity report's nearest corresponding entry is
`Net VSS: has special routes with opens at (1048.500, 1593.845) (1058.300, 1594.955)`, and
there are dangling `VSS` wires at `(1058.300, 1594.400)` on both M1 and M2. **Whether that
fragment is a missing via (a real power-delivery defect) or stray metal that `sroute`
started and abandoned is UNRESOLVED.** The two have opposite consequences, so the
distinction is the whole question.

Note the geometry: the M5 stripes are added `-over_power_domain 1` with
`-extend_to_closest_target {ring stripe}` at 15 µm pitch
([`power_plan.tcl`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/power_plan.tcl)), and `split_row` runs
over the 21 placed macros. Most of the reported open coordinates cluster along macro edges
(x ≈ 1058.9, x ≈ 589.9, x ≈ 1058.3), which is consistent with either explanation.

### Already tried — do not repeat

| Hypothesis | Experiment | Result |
|---|---|---|
| Macro **route halos** are blocking the stripe-to-ring connection | re-ran connectivity with halo settings changed | **FALSIFIED.** Open count **unchanged at 329**. Evidence: `reports/conn_halo_test.rep` — 329 `IMPVFC-200`, and a *different* dangling count (1,328 vs 671) plus 202 `IMPVFC-98`, confirming the design did change and the opens did not. |
| The **via layer range** on `route_special` is too wide, producing bad crossovers | narrowed the via layer range | **FALSIFIED — and it made things worse.** `reports/conn_via_test.rep`: **682** `IMPVFC-200`, up from 329. Dangling wires fell to 40, so the change was real and the opens more than doubled. |

Both experiment reports are kept in the baseline reports directory precisely so this is not
re-run from scratch.

### What to do next

1. **Resolve the M5 fragment first — it is one query, not a run.** Load the post-route DB
   and ask the tool what is at that location:
   ```
   make gui                        # from ASIC/genus-innovus/, needs a real DISPLAY
   # then, at the @innovus prompt:
   get_db [get_obj_in_area -area {1055 1592 1076 1597} -obj_type special_wire] .layer.name
   ```
   If there is M5 metal with no via down to the M1 followpin, it is a missing via. If the
   fragment connects to nothing at either end, it is abandoned `sroute` metal.
2. **Defeat the message cap before measuring anything again.** Raise the limit (Innovus:
   `set_message_limit` / `-max_message`) or the counts are not comparable between runs.
   Every conclusion drawn from "329 did not move" is weak until this is done.
3. **Separate the two nets.** Run `check_connectivity` for `VDD` and `VSS` independently.
   If the opens are all on one net, that points at one of the two `route_special` calls
   (`-pad_pin_width 1.63` for `VDD`, `1.5` for `VSS`) rather than at the stripe geometry.
4. **Check whether the `CORE_TO_IO = 70` run changes it.** That run is in flight for
   issue (b) and it moved every ring by 20 µm; its connectivity report is free evidence.
5. **Do not submit without an answer.** PG opens are the one class of defect on this page
   that silicon will show as a functional failure under load rather than a yield loss.

---

## b) Bond-pad OBS DRC — 318 PG shorts

### What is known

539 total `check_drc` violations, of which **398 involve a bond-pad blockage** and **318
are `VDD`/`VSS` special wires shorting into one** — 59 % of all DRC on this design.

```
SHORT: ( Metal Short ) Special Wire of Net VSS & Blockage of Cell BuPAD_VDD_T_2  ( M9 )
Bounds : ( 1333.750, 1832.000 ) ( 1391.250, 1844.000 )
```

Split by pad type:

| Pad | Violations | of which PG special wire |
|---|---|---|
| `PAD70NU` (inner, 171 µm tall) | 366 | **318** |
| `PAD70GU` (outer, 86.685 µm tall) | 32 | **0** |

**Root cause — measured, not assumed.** `PAD70NU`'s `OBS` is solid over its whole
footprint on **M8 and M9** — read the `MACRO PAD70NU` `OBS` section of the vendor bond-pad
LEF, `$TSMC_65_HOME/iolib/tpbn65v_<rev>_FE/.../lef/tpbn65v_9lm.lef` (geometry not reproduced
here, TSMC licence). Those are exactly the core-ring layers (`add_rings … -layer {top M9 bottom M9 left M8
right M8}`). `add_rings` draws geometrically and **does not honour `OBS`**, so at
`CORE_TO_IO = 50` the rings were drawn straight through the inner bond pads on all four
sides symmetrically:

```
ring stack occupies  core_edge+2 .. core_edge+30   (offset 2, then 12+4+12)
CORE_TO_IO 50 -> ring outer edge 155 / 1445 / 155 / 1845
                 PAD70NU inner edge 171 / 1429 / 171 / 1829   = 16.00 um OVERLAP every side
CORE_TO_IO 70 -> ring outer edge 175 / 1425 / 175 / 1825      =  4.00 um CLEAR
```

The outer pad is the control: `PAD70GU`'s inboard edge (1513.3 on the right) never reaches
the ring band, and it has **zero** PG shorts. That is what makes this a root cause rather
than a correlation.

Why nothing caught it: both pad cells are `CLASS BLOCK`, not `CLASS PAD`, so
`create_floorplan -core_margins_by io` **does not see them** and insets the core by the
135 µm IO-driver height only. Nothing in the margin computation knows the inner bond pads
reach 36 µm further inboard.

### Already done

- `CORE_TO_IO` raised **50 → 70** in
  [`floorplan.tcl`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/floorplan.tcl), giving 4 µm clearance.
  4 µm clears both wide-metal rules — M8's `SPACINGTABLE` and M9's flat `SPACING` both ask
  for less. Both layers also carry a `MAXWIDTH` limit, and the 12 µm ring width was chosen
  against it — legal as it stands. **Do not widen the rings** without re-reading that rule
  in the tech LEF first. (Rule values not reproduced — TSMC licence.)
- The cost was taken out of the core, which is fixed inside a fixed die: 1230 × 1630 →
  **1190 × 1590**, a 5.6 % area loss (112,800 µm²).
- **17 of the 21 macros were re-placed.** Raising the margin moved the core box inward and
  silently put five macros outside it (`way1_word_0` by 14.96, `eth_scratch_tx` by 12.89,
  chip bootrom by 7.00, net imem `rf_32k` by 3.68, chip imem `rf_16k` by 1.05). Each moved
  macro carries a `## MOVED` note with its delta; the ten QSPI cache RAMs move as one rigid
  block because they sit on a 45 µm pitch with 8.64 µm between them.
- A **containment assertion** was added inside `place_macro`, so changing this number again
  names every macro that no longer fits **at the point of placement** instead of surfacing
  as `sroute` damage hours later.

### What was ruled out

- **Widening the rings, or moving them to other layers.** M8/M9 are what the pads block,
  and the rings are already at `MAXWIDTH`.
- **Fixing it in `add_rings`.** It draws geometrically and has no `OBS` awareness; there is
  no option that makes it avoid a `CLASS BLOCK` blockage.
- **Letting `create_floorplan` compute the margin.** It cannot: the bond pads are not
  `CLASS PAD`.

### What to do next

1. **The verification run is in flight.** When it lands, compare:
   ```bash
   scripts/ci/asic_stage_report.sh route     # diffs against baseline_2026-08-05 automatically
   grep -c 'Special Wire of Net V.* & Blockage of Cell BuPAD' \
        ASIC/genus-innovus/reports/nanosoc_eth_chiplet_pads_imp_drc.rep
   ```
   **Expected: 318 → 0.** Anything else means the geometry argument above is wrong
   somewhere and should be re-derived from the LEF, not patched.
2. **Expect ~48 to remain.** The 366 − 318 = **48 non-PG `PAD70NU` violations are signal
   routing into the same blockages**, and `CORE_TO_IO` does not move signal routes — the
   router is free to go there. **These may not clear.** If they do not, the options are a
   routing blockage over the inner pad footprints, or accepting them and declaring them to
   the broker.
3. **Re-check placement.** At 89.45 % post-hold-repair utilisation on a core that just lost
   5.6 % of its area, placement failure is a live risk. If `place_design` starts failing,
   this is why.

---

## c) QSPI flash-cache tag RAMs have an undriven `GWEN`

### What is known

`check_cpf` reports it as `2x STRUCT_UNDRIVEN_PIN_MACRO` (Severity: Error):

```
STRUCT_UNDRIVEN_PIN_MACRO: Macro cell input/inout direction pin with receiver(s)
                           does not have an external driver
    Severity: Error      Occurrence: 2
    1: 'u_nanosoc_eth_chiplet_chip/u_soc/u_soc/u_qspi_flash_0/u_top_ahb_qspi/
        u_cache_subsystem/u_way0_cache_ram/tag_ram_0_i/GWEN' is undriven
    2: '…/u_way1_cache_ram/tag_ram_0_i/GWEN' is undriven
```

`logs/syn_cpf_check.log`. This is the **one genuinely real** finding among the tolerated
`check_cpf` errors (see [f](#f-check_cpf-errors-tolerated-by-a-wrapper-in-configtcl)) —
the other three blocks are library/UPF modelling noise, this one is a floating input on a
hard macro.

**It is present in the 2026-07 reference GDSII too.** It is not a regression, and it is not
caused by anything in the current flow.

`GWEN` is the global write-enable on the `flash_cache_tag` RAM. Undriven means it floats:
in silicon that is an indeterminate input on a memory control pin.

### What has been ruled out

- **Not a flow or constraint problem.** It reports identically under Genus with the
  `check_cpf` wrapper in place and with it removed; the wrapper only stops the abort, it
  changes nothing about the finding.
- **Not fixable in the physical flow.** There is no tie-off to insert without deciding
  what the correct value is, which is an RTL question about the cache's write path.

### What to do next

1. **Fix it in `ahb_qspi`**, not here. Trace `u_cache_subsystem/u_way{0,1}_cache_ram` in
   the QSPI submodule and drive `tag_ram_0_i.GWEN` from the same logic that drives the
   per-bit write enable — or tie it to its inactive level if the design never uses the
   global write.
2. **Until then, tie it off explicitly** so the value is a decision rather than an
   accident, and record which way.
3. **Re-check after the fix:** the occurrence count in `logs/syn_cpf_check.log` must go
   `2 → 0`. That is the only clean regression test available for it.
4. **Declare it if it ships unfixed.** A floating control pin on a macro is exactly the
   kind of thing a foundry or a bring-up engineer wants told, not discovered.

---

## d) Power intent defines no `power_mode`/`power_state` (`IMPMSMV-3501`)

### What is known

```
**ERROR: (IMPMSMV-3501): Input power intent (CPF/UPF) does not define power_mode/power_state.
The always-on buffering is not supported since the tool needs the power_mode/power_state
information to calculate the domain coverage.
```

Raised by Innovus while reading the power intent (`logs/pnr_run_core70.log`, and again in
the baseline `pnr_all.log`). Alongside it:

```
INFO: Power domain of power net VDDIO is set to PD_TOP.
    To fix this in IEEE1801, specify a supply_set of this power net and a ground net
    so that an internal power domain will be created for this power net
INFO: Power domain of power net VDDACC is set to PD_TOP.
```

So all four supplies (`VDD`, `VDDACC`, `VDDIO`, plus `VSS`/`VSSIO`) collapse into the
single default domain `PD_TOP`.

**Consequence:** **always-on buffering is unsupported.** The tool cannot compute domain
coverage, so it cannot decide which buffers must stay powered across a domain boundary.

**Why it is low severity *today*:** this chip has exactly one core power domain. There is
nothing to be always-on *relative to*. Everything in `PD_TOP` is powered together, so the
unsupported feature is not currently needed.

**Why it will not stay low severity:** [`docs/POWER_DOMAINS.md`](../POWER_DOMAINS.md)
analyses splitting the D2D link into its own domain, and
[`docs/PHYSICAL_HANDOFF.md` §5](../PHYSICAL_HANDOFF.md) records the gap plainly — *"the
SoC's UPF has no D2D domain — the generator residual reads `domain ACCEL omitted`"*, gap
**C3**. **The moment anyone acts on that recommendation, this error becomes blocking**:
you cannot have an isolated, retainable link PHY without `power_state` definitions, and
without isolation an unpowered link can corrupt the SoC's fabric.

### What has been ruled out

- **Patching it in Innovus.** `update_power_domain` there is positional and has no
  `-primary_power_net`/`-primary_ground_net` options at all — verified by running it
  (`IMPTCM-162` plus the usage string). These are CPF/UPF statements; the input file is
  what has to change. (This is the same finding that forced the `cpf-patch` Makefile target
  — see [04](04-power-plan.md).)
- **Ignoring the `VDDIO`/`VDDACC` messages.** They are consequences of the same missing
  `supply_set`, not independent problems.

### What to do next

1. **For this tapeout: accept and record it.** One domain, no always-on requirement. Say so
   in the hand-off rather than leaving an `ERROR` in the log unexplained.
2. **For the next revision**, add `add_power_state` / `create_power_state_group` (1801) or
   `create_power_mode` (CPF) to
   [`inputs/nanosoc_eth_chiplet_pads.upf`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/inputs/nanosoc_eth_chiplet_pads.upf),
   and give `VDDIO`/`VDDACC` their own `supply_set` so they stop being folded into
   `PD_TOP`.
3. **Do that before splitting the D2D domain**, not after. Read
   [`docs/POWER_DOMAINS.md`](../POWER_DOMAINS.md) §"Decision checklist for the team" first
   — the domain split is still an open architectural decision, and the power-intent work
   depends on which way it goes.

---

## e) `CLK_HOLD_ERROR = 0.05` is an unconfirmed signoff margin

### What is known

[`inputs/constraints.sdc`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/inputs/constraints.sdc):

```tcl
set CLK_ERROR 0.35       ;# oscillator jitter, CDCM61001 worst case at 250 MHz
set CLK_HOLD_ERROR 0.05
set_clock_uncertainty -setup $CLK_ERROR      [get_clocks $EXTCLK]
set_clock_uncertainty -hold  $CLK_HOLD_ERROR [get_clocks $EXTCLK]
```

**The reasoning, as recorded in the file:** `CLK_ERROR` is oscillator jitter — a legitimate
*setup* margin. For a same-edge *hold* check the source jitter is largely common-mode
between launch and capture and cancels, so charging hold the full 0.35 ns asks every hold
path for delay it does not need. 0.05 ns is intended to cover residual (non-common-mode)
jitter plus PLL/duty-cycle effects.

**Why it was changed, and what it cost before.** The two `set_clock_uncertainty` lines
previously carried **neither** `-setup` nor `-hold`, and SDC then applies the value to
*both* checks — so hold was charged the full 0.35 ns on every path in the design. That was
the dominant cause of the hold-buffer explosion: post-CTS hold repair inserted **62,729
instances** (+171,250 µm², utilisation 75.0 % → 89.6 %) and drove setup WNS from +0.001 to
**−0.729** doing it. Roughly **30,000** of the inserted cells were `DEL0`/`DEL005`/`DEL01`/
`DEL015` delay cells. The 2026-07 reference run had the same bug (+148,558 µm² of hold
repair) — it simply had less logic to apply it to.

So the change is well-motivated and demonstrably paid for itself. **What is missing is
confirmation that 0.05 ns is the right number**, and the file says so in as many words:

> `THIS IS A SIGNOFF MARGIN — revisit it with the clocking spec, not casually.`

**Nobody has revisited it.** There is no clocking-spec document in this repo that derives
0.05 ns from the CDCM61001 datasheet, from a jitter budget, or from an OCV analysis.

### What has been ruled out

- **Reverting to 0.35 ns for hold.** Measured: it produces 62,729 hold-repair instances and
  −0.729 ns setup WNS. It is not a safe default, it is a different failure.
- **Leaving the qualifiers off.** That is the original bug.

### What to do next

1. **Derive the number.** Needed: CDCM61001 period jitter at the operating frequency, the
   common-mode fraction across the clock tree's insertion delay, and PLL duty-cycle
   distortion. **This is an owner decision with a paper trail, not a tool run.**
2. **Bracket it cheaply.** Re-run `opt_design -post_route -hold` from the `_cts` snapshot
   (`read_db ${block_name}_cts`, ~1 h, not a 5 h flow re-run — see
   [`route_setup.tcl`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/route_setup.tcl)) at 0.05 / 0.10 /
   0.15 and record instance count and setup WNS at each. That gives a cost curve to argue
   from.
3. **Read hold from the right file.** `timing_summary_05_route_opt.rep` is **setup only** —
   `report_timing_summary` rejected `-early`/`-late` together with `TCLCMD-1130`. Use
   `reports/nanosoc_eth_chiplet_pads_imp_timing_early.rep`.
4. **Record whatever is chosen in the hand-off.** A hold margin nobody can justify is a
   hold margin nobody can defend if the part fails.

---

## f) `check_cpf` errors tolerated by a wrapper in `config.tcl`

### What is known

[`config.tcl`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/config.tcl) renames `check_cpf` and wraps
it in a `catch`, so a rule-check failure cannot kill the `-f` script. Four error blocks are
tolerated, all pre-existing:

| Count | ID | What it is |
|---|---|---|
| **34** | `1801_REF_OBJ_NOT_FOUND` | UPF `connect_supply_net` naming macro PG ports (`rf_sp_hdf` / cache RAM `VDD`,`VSS`) that the liberty models do not expose |
| **54** | `1801_LIB_NO_PG_PIN` | Library cells with no PG pin — `PCLAMP*_G`, `PDB3*_G`, `PDDW*_G` … i.e. the entire TSMC IO driver library |
| **1** | `1801_LIB_MISSING_LP_CELL` | No low-power cells in the library database |
| **1** | `1801_SUPPLY_CSN_MISSING_FOR_MACRO` / `1801_MACRO_PORT_ATTR_MISSING` | macro PG pin with no `connect_supply_net` |
| **2** | `STRUCT_UNDRIVEN_PIN_MACRO` | **REAL** — see [c](#c-qspi-flash-cache-tag-rams-have-an-undriven-gwen) |

### Why tolerating them is defensible

Four independent reasons, in descending order of strength:

1. **They are properties of the vendor libraries, not of our design.** 54 of them say TSMC
   ships its 2.5 V IO liberty without `pg_pin()` groups — which is true, and is also why
   [`config.tcl`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/config.tcl) carries a three-line LEF
   override adding `USE POWER ;` / `USE GROUND ;`. We cannot fix a vendor liberty, and
   `$TSMC_65_HOME` is a read-only, lab-shared mount that must not be edited in place — the
   deviation is applied to a copy the build generates from it
   (`ASIC/tech_wrappers/tsmc65/generated/`, produced by `patch_pad_lef.py`; formerly a
   committed copy under `local_overrides/`, changed in `bf619f1`). 34 more say the memory
   liberty models do not expose PG ports our UPF names.
2. **The alternative is worse and was measured.** `check_cpf` raises `RCLP-203`, which
   **aborts the `-f` script**. Genus then drops to its interactive prompt and, with stdin
   on `/dev/null`, **exits 0 having written no netlist**. Without the wrapper,
   `1_synthesis.tcl` has never once completed unattended — the 2026-07 reference run
   produced a netlist only because an operator typed `commit_power_intent` and
   `set_dont_touch` at the `@genus:root:` prompt after the abort.
3. **The remedy Cadence names does not work here.** `clp_treat_errors_as_warnings` is
   accepted by Genus but **verified not to stop `check_cpf` raising on this design** — a
   run that set it aborted at the same line with the same four `Severity: Error` blocks.
   It is also a Genus-only root attribute, and `config.tcl` is sourced by **both** tools,
   so under Innovus it fails with `IMPDBTCL-247` and takes the whole file down.
4. **Nothing is hidden.** `check_cpf` still runs, still writes full detail to
   `logs/syn_cpf_check.log`, and the wrapper echoes the failure to **stderr** (not stdout,
   which the call site redirects into that log — a `puts` there would be buried in the one
   file you would only open if you already knew to look). The counts are stable and
   *identical* to the 2026-07 reference run: 34 / 1 / 54 / 2.

### What would make it stop being defensible

Any of these turns "tolerated" into "ignored", and each is a reason to look again:

- **The counts change.** 34 / 1 / 54 / 2 is the signature. A different count means a new
  finding is being swallowed by a wrapper written for the old ones.
- **A new error class appears** that is not one of the four above.
- **`STRUCT_UNDRIVEN_PIN_MACRO` goes above 2**, or a second genuinely structural class
  shows up. Block (c) is proof this check *does* find real defects.
- **The power intent gains a second domain** (see [d](#d-power-intent-defines-no-power_modepower_state-impmsmv-3501)).
  Once isolation and retention matter, `check_cpf` findings stop being modelling noise.

### What to do next

1. **Pin the counts.** Add a post-condition asserting `34 / 1 / 54 / 2` in
   `logs/syn_cpf_check.log`, so a change is a build failure rather than something nobody
   notices:
   ```bash
   grep -c 'Severity: Error' ASIC/genus-innovus/logs/syn_cpf_check.log
   grep -A1 -E '^(1801|STRUCT)_[A-Z_]+:' ASIC/genus-innovus/logs/syn_cpf_check.log \
     | grep -oE 'Occurrence: [0-9]+'
   ```
   This is the single highest-value follow-up on this entry.
2. **Fix (c)**, which takes `STRUCT_UNDRIVEN_PIN_MACRO` to 0 and removes the only real
   finding from the tolerated set.
3. **Leave the wrapper.** It is the scripted equivalent of what the reference run's
   operator did by hand, and it lives in the project's own config rather than in the shared
   `asic-flows` `1_synthesis.tcl` that other designs use.

---

## g) 1,243 `max_transition` + 618 `max_capacitance` violations post-route

**Observed in the baseline reports and, as far as this repo records, never triaged.**
Listed here because it is measurable, it is in the final report, and nothing in the flow
gates on it.

### What is known

`reports/timing_summary_05_route_opt.rep`, the **final** post-route summary:

| Check | WNS | TNS | FEP |
|---|---|---|---|
| `max_transition` | −3.035 | −1032.060 | **1,243** |
| `max_capacitance` | −0.173 | −2.361 | **618** |
| `min_transition` / `min_capacitance` / fanout | N/A | N/A | 0 |

`qor_05_route_opt.rep` agrees: `DRV(T) Tran -1032`, `DRV(C) Load -2` at
`opt_design_postroute_hold`. These are **not** present at `ccopt_design` or
`opt_design_postcts` (both report `0` / `-0`), so **they appear during post-route hold
repair** — the same phase that inserted 65,250 instances and took utilisation from 75.5 %
to 89.45 %.

Constraints in play: `set_max_capacitance 3 [all_outputs]` and
`set_max_fanout 10 [all_inputs]` in `constraints.sdc`; `max_transition` comes from the
libraries.

**Why it matters and is not cosmetic:** a −3 ns transition violation means the delay model
used to compute the headline "setup WNS +0.068 ns" is being extrapolated outside its
characterised range. The timing number is only as good as the slews it was computed from.
Slow slews are also a crowbar-current and hot-carrier concern the foundry may ask about.

### What has been ruled out

Nothing — **this has not been investigated at all.** Do not read the empty column as
"already checked".

### What to do next

1. **Find out what they are.** Cheap, from the post-route DB:
   ```
   make gui
   # @innovus:
   report_constraint -drv_violation_type max_transition -all_violators > /tmp/tran.rpt
   report_constraint -drv_violation_type max_capacitance -all_violators > /tmp/cap.rpt
   ```
   The first question is whether they cluster on one net class. Two likely candidates given
   this design: the hold-repair `DEL*` delay-cell chains, and the pad/IO nets covered by
   `set_multicycle_path 2 -from uPAD*/* -to uPAD*/*`.
2. **Check whether they are on real signal nets at all.** If they are on clock nets, the
   CTS spec in [`cts_setup.tcl`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/cts_setup.tcl) is where
   to look; if on the D2D pad interface, they may be constraint artefacts of the blanket
   async clock group (see [09 item 3](09-signoff-checklist.md)).
3. **Then decide: fix or waive.** `opt_design -post_route -drv` is the tool's answer, but
   at 89.45 % utilisation there may not be room, which loops back to (b)'s core-area cost.
4. **Either way, record the count in the hand-off.** 1,243 + 618 is not a number to
   discover for the first time in a broker's acceptance report.

---

## h) Filler runs post-route and nothing cleans up after it

### What is known

Filler now runs from
[`place_bondpads.tcl`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/place_bondpads.tcl) — **after**
`route_design` and `opt_design -post_route -hold` — which is deliberate and correct: it was
moved out of `route_setup.tcl` because running it *before* routing meant
`add_fillers -check_drc -fix_drc` had nothing to check against, the `ANTENNA` diodes went
in before any antenna existed, and hold repair had to carve ~66,000 buffers back out of
filled rows.

The side effects of that placement are two tool warnings and one silent no-op:

```
**WARN: (IMPSP-5217): add_fillers command is running on a postRoute database.
        It is recommended to be followed by eco_route -target command to make the DRC clean.
**WARN: (IMPSP-9082): verifyGeometry needs to be executed before -fixDRC option could be used.
        If verifyGeometry has been executed, then there is no DRC violation to fix.
```

1. **`eco_route -target` is never run.** `4_pnr_route.tcl` goes straight from
   `place_bondpads.tcl` to `check_drc`. Cadence's own recommendation for post-route filler
   is not followed.
2. **The second `add_fillers` pass in [`filler.tcl`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/filler.tcl)
   is a no-op.** It is invoked `-check_drc true -fix_drc`, but `verifyGeometry` has not run
   at that point, so it has nothing to fix. The line executes and does nothing.

**What is not affected:** insertion itself is healthy — 150,592 fillers, 50,274 `ANTENNA`
diodes, and `work/check_filler.log` reports `Total number of gaps found: 0` and
`Total number of padded cell violations: 0`.

### What has been ruled out

- **Moving filler back before routing.** Measured and reverted; the reasons are recorded in
  the comment at the end of `route_setup.tcl`.
- **Assuming the `-fix_drc` pass is doing something.** `IMPSP-9082` says explicitly that it
  is not.

### What to do next

1. **Add `eco_route -target` after filler**, before `check_drc`, in the route stage. Then
   re-measure the DRC count — some of the 141 non-bond-pad violations (539 − 398) may be
   filler-adjacent and may simply disappear.
2. **Or reorder to make `-fix_drc` real**: run `check_drc`/`verifyGeometry` *first*, then
   the second `add_fillers -fix_drc` pass. Either fixes the no-op; do not leave a line in
   the flow that the tool has told you is inert.
3. **Sequence this after (b).** The `CORE_TO_IO = 70` verification run is the current
   DRC baseline; changing two things at once makes neither measurable.

---

## i) Post-P&R logical equivalence is stale, not absent

> **Rewritten 2026-08-17, and downgraded from high to medium.** This issue was titled "No
> post-P&R logical equivalence exists" and asserted that *"nothing anywhere in this
> repository compares anything to the post-P&R netlist"*. False since 2026-08-08. Full
> account: [13 §7 item 1](13-lec.md).

A coverage gap rather than a defect, and now a *narrower* one than this entry used to
claim. Kept at the top of the list because the failure class behind it is still the worst
one on these pages.

### What is known

- **Post-P&R LEC exists and has run clean.** `make lec-pnr`
  (`ASIC/genus-innovus/scripts/lec/`) compared `outputs/*_gate_power.v` against
  `outputs/*_pnr.v` on 2026-08-08: **61,375 compare points, 61,375 equivalent, 0
  non-equivalent, 0 abort, 0 not-compared**, with Conformal's own `Compare Results: PASS`.
  412 s CPU, 874 MB. `ci/signoff.yaml` now carries a `lec-pnr` stage and the `post-pnr-lec`
  entry has been removed from its `unsupported:` list.
- **It does not cover the netlist we would ship.** The compared `_pnr.v` is sha1
  `45a6c089…`; `runs/latest/outputs/` holds `7a8d6cdb…` (2026-08-10). *That* netlist is
  unverified. This is now the whole of the gap on the P&R side.
- **The archived verdict says `RESULT=FAIL` and does not mean it.** The dofile's
  unreachable rule fired on 34 supply pads per side whose golden and revised name sets are
  identical. Repaired in `run_lec.sh` on 2026-08-09, in the runner rather than the dofile —
  so on an accepted-exception pass `verdict.txt` still reads
  `LEC-VERDICT: RESULT=FAIL` and the verdict is the `LEC-RUNNER: RESULT=PASS` line beneath
  it. Do not gate on the wrong line.
- **The RTL → synthesised leg has still never completed.** The single attempt aborted on a
  hardcoded path (`runs/20260808T185931Z_stage1a-syn-place-cts/logs/eval/lec.log`, FIL1.2 at
  dofile line 104). So the `GLO-34` class below is the part that remains genuinely
  unevidenced — not the P&R half.
- **`lec.dofile` ends `exit -f`, returning 0 even on non-equivalence**, and the Makefile
  adds no check. The `check:` block on the `lec` stage in `ci/signoff.yaml` is the only
  thing that turns *that* Conformal run into a verdict. `run_lec.sh` (the `lec-pnr` /
  `lec-gate` path) does not have this defect — it asserts its own verdict twice, from two
  independent sources.

**Why this is high severity.** A previous build silently lost TideLink's **entire TX
datapath** to Genus `GLO-34` unused-logic removal, and the July reference GDSII shipped
hollow — no TX datapath, no PTP seconds counter, no timestamps. **Every physical check
passed on that GDS**, because DRC and connectivity do not care whether the logic is there.
LEC is the check that sees that class of defect, and the half of the flow it currently does
not cover — CTS, post-route hold repair, filler, bond pads — added **65,250 instances** to
the design between post-CTS and post-route.

### What to do next

1. **Get the RTL → synthesised leg to complete.** This is the one that catches `GLO-34`,
   and it has never produced a verdict. The blocker is a path, not the tool: Genus's
   generated dofile hardcodes an absolute path into `outputs/` that the run archiver moves.
   Either run it before archiving or drive it from `run_lec.sh`, which takes its netlists as
   arguments.
2. **Re-run `make lec-gate` and `make lec-pnr` against a single `outputs/`.** Both passed on
   2026-08-08 but against *different* `_gate_power.v` files (sha1 `431c06a5…` vs
   `664d76d7…`), so `A ≡ B` and `B ≡ C` do not compose. About seven minutes of Conformal
   each. Read the `LEC-RUNNER:` verdict line, not `LEC-VERDICT:`.
3. **Record the netlist sha1 beside the GDS sha1** in the covering note, so "LEC passed" can
   never be read as applying to a netlist it never saw — see
   [10 §2](10-tapeout-submission.md) and
   [26 §A1](26-plan-to-submittable-gds.md). Do not let silence imply coverage.

---

[← 10 Tapeout submission](10-tapeout-submission.md) · [index](00-index.md)
