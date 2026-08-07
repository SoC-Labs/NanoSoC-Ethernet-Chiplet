# 06 — Filler, Antenna Diodes and Bond Pads

`nanosoc_eth_chiplet_pads` · Cadence Innovus 21.11-s130_1 · STYLUS / Common-UI

The last three physical operations before `write_stream`. All three happen
inside the route stage, after hold repair has finished, and all three are
sourced from one file:
[`place_bondpads.tcl`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/place_bondpads.tcl).

Read [05-place-cts-route.md](05-place-cts-route.md) first — the ordering here
only makes sense against the post-route optimisation flow described there.

---

## 1. What runs, and where it is invoked from

[`4_pnr_route.tcl`](https://github.com/SoC-Labs/ASIC-Flow/blob/b19e7845448e641ea8353b19a59a77257907cb13/Cadence/4_pnr_route.tcl):

```tcl
opt_design -post_route -hold
report_end_step 05_route_opt $REPORT_DIR
write_db $block_name

source ../scripts/place_bondpads.tcl      ;# <- filler, diodes, THEN bond pads

check_drc              -out_file $REPORT_DIR/${block_name}_imp_drc.rep
check_filler           -out_file $REPORT_DIR/${block_name}_imp_filler.rep
check_connectivity     -out_file $REPORT_DIR/${block_name}_imp_connectivity.rep
check_process_antenna  -out_file $REPORT_DIR/${block_name}_imp_antenna.rep
```

and the first executable line of
[`place_bondpads.tcl`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/place_bondpads.tcl) is

```tcl
source ../scripts/filler.tcl
```

Note the `write_db` **before** `place_bondpads.tcl` — that DB is your last
pre-fill checkpoint, but it is written under the same `$block_name` and will be
overwritten by the final `write_db` at the end of the script. If you want to
keep a pre-fill state, snapshot it under a different name yourself.

---

## 2. Why filler runs here and not in `route_setup.tcl`

This is the most instructive comment in the flow. It is at the top of both
[`route_setup.tcl`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/route_setup.tcl) (lines
29–35) and [`place_bondpads.tcl`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/place_bondpads.tcl)
(lines 1–6), and it exists because filler used to be sourced from
`route_setup.tcl`, which runs **before** `route_design`.

Three separate things went wrong in that order, all of them silent:

1. **`-check_drc` / `-fix_drc` had nothing to check.** There was no routing yet,
   so the DRC check ran against an empty routing database and reported
   *"Found no DRC violations to fix"*. The option was doing nothing and looking
   like it had passed.
2. **The `ANTENNA` diodes went in before any antenna existed.** Antenna
   violations are a property of routed metal. Inserting the diodes first means
   they are placed blind, with no relationship to the charge-collecting geometry
   they are supposed to protect.
3. **Post-route hold repair then had to carve its buffers back out of filled
   rows** — roughly 66 000 of them on this design. Every one of those insertions
   is a filler deletion plus a legalisation, on a design already running above
   90 % density.

The correct order — and the one in the tree now — is: route, optimise, repair
hold, *then* fill. The rows have stopped changing, so `-check_drc` has real
routing to check and the diodes see real antennas.

**If you are ever tempted to move it back, don't.** If you must reorder
anything in this region, re-read those two comment blocks first; they were
written by the engineer who fixed the bug.

---

## 3. Filler and antenna-diode insertion

### The script

[`filler.tcl`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/filler.tcl), in full:

```tcl
add_filler_gaps 0.2 -effort high

add_fillers -base_cells [list FILL64 FILL32 FILL16 FILL8 FILL4 FILL2 FILL1 ANTENNA] \
    -prefix FILLER -fill_gap -merge true -check_drc true

add_filler_gaps 0.2 -effort high

check_filler > check_filler.log

add_fillers -base_cells [list FILL64 FILL32 FILL16 FILL8 FILL4 FILL2 FILL1 ANTENNA] \
    -prefix FILLER -check_drc true -fix_drc
```

The cell list is largest-first: `FILL64 FILL32 FILL16 FILL8 FILL4 FILL2 FILL1`
from `tcbn65lp`, plus `ANTENNA`, the antenna-diode cell. `ANTENNA` is in the
same list as the fill cells because it is inserted the same way — it occupies a
row site like any filler, it just also has a diode on it.

`add_filler_gaps 0.2 -effort high` is a refine-place pass run before and after
filling; in the reference run it reported `Instances move: 0 (out of 259478
movable)` both times, i.e. it had nothing to do. Treat the `0.2` as a gap
threshold and **confirm its exact meaning and units with
`add_filler_gaps -help`** before changing it — that is not verified here.

Likewise, do not assume the semantics of `-fill_gap` and `-merge true` from this
page. Run `add_fillers -help` in a live session. What *is* verified is the
observed result, below.

### What a good run produces

From `baseline_2026-08-05/logs/pnr_all.log`, the first `add_fillers`:

```
*INFO: Adding fillers to module u_nanosoc_eth_chiplet_chip_u_soc_u_soc.
*INFO:   Added   674 filler insts (cell FILL64  / prefix FILLER_PD_TOP).
*INFO:   Added    93 filler insts (cell FILL32  / prefix FILLER_PD_TOP).
*INFO:   Added   379 filler insts (cell FILL16  / prefix FILLER_PD_TOP).
*INFO:   Added  1194 filler insts (cell FILL8   / prefix FILLER_PD_TOP).
*INFO:   Added 18391 filler insts (cell FILL4   / prefix FILLER_PD_TOP).
*INFO:   Added 50274 filler insts (cell ANTENNA / prefix FILLER_PD_TOP).
*INFO:   Added 27799 filler insts (cell FILL2   / prefix FILLER_PD_TOP).
*INFO:   Added 51788 filler insts (cell FILL1   / prefix FILLER_PD_TOP).
*INFO: Total 150592 filler insts added - prefix FILLER_PD_TOP (CPU: 0:00:39.2).
For 150592 new insts, *** Applied 6 GNC rules (cpu = 0:00:00.1)
```

Round numbers to remember: **~150 000 filler instances, of which ~50 000 are
`ANTENNA` diodes**, inserted in about 40 seconds of CPU. The dominance of
`FILL1`/`FILL2` (79 587 combined) is what a 92 %-density design looks like —
the gaps left are single- and double-site slivers.

Note the instance prefix is **`FILLER_PD_TOP`**, not `FILLER`: Innovus appends
the power-domain name to the `-prefix` you gave. Search for `FILLER_PD_TOP`, not
`FILLER`, when you go looking for these instances. (`FILLER` on its own also
matches the *IO* fillers `PFILLER*_G` placed back in
[03-floorplan.md](03-floorplan.md), which are a different thing entirely.)

The `check_filler` between the two `add_fillers` calls, and the final one from
`4_pnr_route.tcl`, both reported:

```
*INFO: Total number of padded cell violations: 0
*INFO: Total number of gaps found: 0
```

Down from **95 568 free-site gaps (~5.9 % of the core)** in the failed run
described in §4. That drop from ~95 500 to zero is the number that tells you
fill actually happened.

---

## 4. THE TRAP: a die with zero fill and zero diodes

**This has happened on this design and it is tapeout-blocking.**

`2_pnr_setup.tcl` reads `outputs/${block_name}_gate1.cpf`, which Genus wrote
with `write_power_intent -cpf`. Genus cannot translate the UPF supply commands —
the synthesis log is full of `Unable to translate command 'create_supply_net'
... from 1801 to CPF format` — and the CPF it emits contains only

```
create_power_domain -name PD_TOP -default
```

with **no power net and no ground net**. Innovus then fails every filler pass
with:

```
IMPSP-5110: No supply-net names for Power Domain 'PD_TOP'
```

and `add_fillers` reports **`For 0 new insts`**. That is the whole signal.
`IMPSP-5110` is the only warning. The script does not abort, the run does not
fail, `write_stream` runs happily, and you get a GDSII with **zero filler cells,
zero `ANTENNA` diodes and 95 568 free-site gaps**. The 2026-08 run shipped
exactly that. The 2026-07 reference run hit the identical error and only
survived because the operator hand-edited the CPF mid-session and re-ran
`add_fillers` at the `@innovus` prompt — an unattended flow has nobody to do
that.

### The fix, and why it is not an Innovus command

`update_power_domain` in this Innovus build takes the domain **positionally**
and has no `-primary_power_net` / `-primary_ground_net` options at all — its
entire option set is floorplan geometry (`core_to_*`, `row_*`, `gap_*`).
Verified by running it: `IMPTCM-162` plus the usage string.

Those are **CPF statements**, so the repair belongs in the CPF file before
Innovus reads it. `make syn` now patches `gate1.cpf` (the `cpf-patch` target in
[`ASIC/genus-innovus/Makefile`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/Makefile)), inserting
before `end_design`:

```
create_ground_nets -nets VSS
create_power_nets  -nets VDD
update_power_domain -name PD_TOP -primary_power_net VDD -primary_ground_net VSS
```

which is exactly what the 2026-07 operator typed by hand. You will see it
confirmed in the log as:

```
OK: patched .../nanosoc_eth_chiplet_pads_gate1.cpf with VDD/VSS supply nets (add_fillers needs them)
```

[`power_plan.tcl`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/power_plan.tcl) lines 40–42
are the backstop — if the patch did not happen, fail *there* with a clear reason
rather than three hours later with a silently unfilled die:

```tcl
if {[llength [get_db power_domains PD_TOP]] == 0} {
    error "power_plan: no PD_TOP power domain — check read_power_intent"
}
```

### How to confirm it did not happen to you

Three independent checks, all cheap:

```sh
# 1. the insertion counts, straight from the log
grep -n "filler insts\|IMPSP-5110\|For 0 new insts" ASIC/genus-innovus/logs/*.log

# 2. the check_filler report written by 4_pnr_route.tcl
cat ASIC/genus-innovus/reports/nanosoc_eth_chiplet_pads_imp_filler.rep
```

A clean filler report is short and says nothing beyond its header and
`Checking Power Domain: PD_TOP`. A report that lists gaps is the failure.
In a live session:

```tcl
check_filler
get_db insts FILLER_PD_TOP* -if {.base_cell.name == ANTENNA}   ;# should be ~50k
```

---

## 5. Antenna

Antenna is confirmed by `check_process_antenna`, which
[`4_pnr_route.tcl`](https://github.com/SoC-Labs/ASIC-Flow/blob/b19e7845448e641ea8353b19a59a77257907cb13/Cadence/4_pnr_route.tcl) runs into
`reports/${block_name}_imp_antenna.rep`. The only acceptable content is:

```
No Violations Found
```

The log shows it walking every net:

```
5000 nets processed: 0 violations
...
280000 nets processed: 0 violations
Verification Complete: 0 Violations
```

Two caveats, both verified and both worth knowing before you trust that clean
report too far:

- **`IMPLF-200`, 15 occurrences.** Pins on the analogue/ESD IO macros
  (`PVSS3A_G/TAVSS`, `PVDD2ANA_G/AVDD`, `PCLAMPA_G/VSSESD`, …) — and, notably,
  **`ANTENNA/I` itself** — have no `ANTENNAGATEAREA` defined. The tool says so
  plainly: *"The library data is incomplete and some process antenna rules will
  not be checked correctly."* `check_process_antenna` is a LEF-based check; it
  can only be as complete as the LEF. Signoff antenna is Calibre's job. See
  [09-signoff-checklist.md](09-signoff-checklist.md).
- **`IMPLF-119`** for `PO`, `CO`, `M1`…`M9`, `RV` — *"content except ANTENNA*
  data will be ignored"* when reading `nanosoc_eth_chiplet_pads.antenna.lef`.
  That is expected: the file is generated by Innovus purely to carry antenna
  data for the check.

---

## 6. Two honest caveats about the current `filler.tcl`

Both are things the tool told us in the reference run. Neither is fixed in the
tree today; both should be resolved before signoff.

**(a) The `-fix_drc` pass is currently a no-op.** The second `add_fillers` call
in [`filler.tcl`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/filler.tcl) uses
`-check_drc true -fix_drc`, and the log answers:

```
**WARN: (IMPSP-9082): verifyGeometry needs to be executed before -fixDRC option
could be used. If verifyGeometry has been executed, then there is no DRC
violation to fix.
```

`check_drc` (`verifyGeometry`) runs in `4_pnr_route.tcl` *after*
`place_bondpads.tcl`, so at the moment `-fix_drc` executes there is no DRC
marker database for it to work from. This is the same class of mistake the
ordering fix in §2 was meant to cure, one level down. The obvious remedy is a
`check_drc` immediately before that second `add_fillers` — but that is a change
to a live flow, so it is recorded here rather than made. See
[11-known-issues.md](11-known-issues.md).

**(b) `eco_route -target` is recommended and not run.** Both `add_fillers` calls
emit:

```
**WARN: (IMPSP-5217): add_fillers command is running on a postRoute database.
It is recommended to be followed by eco_route -target command to make the DRC clean.
```

Nothing in the flow calls `eco_route`. Running filler post-route is correct
(§2) — this is the price of that correctness, and it is a real recommendation
from the tool, not noise.

---

## 7. Bond pads

### The ring

82 bond pads in a **staggered** two-row ring, created and placed by
[`place_bondpads.tcl`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/place_bondpads.tcl):

| Row | Cell | Height | Count |
|---|---|---|---|
| outer | `PAD70GU` | 86.685 µm | 42 |
| inner | `PAD70NU` | 171.000 µm | 40 |

Per side: top 9 outer / 8 inner, left 13 / 13, bottom 9 / 8, right 11 / 11. The
pad name lists at the top of the file are in ring order and are the authoritative
record of which signal lands on which row — cross-check against
[`docs/PIN_MAP.md`](../PIN_MAP.md) and [10-tapeout-submission.md](10-tapeout-submission.md)
before release.

### How they are placed

Each bond pad is created as a new instance and then positioned **relative to its
IO driver cell**, not at an absolute coordinate:

```tcl
foreach pads $left_pads_outer {
    create_inst -cell PAD70GU -inst B$pads -ori R270
    create_relative_floorplan -place B$pads -orient R270 -ref_type object -ref $pads \
        -horizontal_edge_separate {0 -2.5 0} -vertical_edge_separate {0 0 0}
}
```

The instance name is the IO cell's name with a `B` prefix — `uPAD_TL_RX_0`
becomes `BuPAD_TL_RX_0`. That naming is how you read the DRC report (§8).

Orientation and edge separations, per side, exactly as in the file:

| Side | Orient | `-horizontal_edge_separate` | `-vertical_edge_separate` |
|---|---|---|---|
| left (outer + inner) | `R270` | `{0 -2.5 0}` | `{0 0 0}` |
| top (outer + inner) | `R180` | `{1 0 1}` | `{2 2.5 2}` |
| bottom (outer + inner) | `R0` | `{0 0 0}` | `{0 -2.5 0}` |
| right (outer + inner) | `R90` | `{1 2.5 1}` | `{2 0 2}` |

Outer and inner rows on a given side share the same orientation and the same
separations; the stagger comes from the two cells' different heights (86.685 vs
171.000), not from different placement arguments. The `2.5` appears on every
side with the sign and axis that pushes the pad *outward*.

The three-element form of `-horizontal_edge_separate` / `-vertical_edge_separate`
is `{<left/bottom> <centre> <right/top>}` in this usage, but **confirm with
`create_relative_floorplan -help`** before changing any of these numbers; the
semantics are not documented here from first principles, only observed.

### Why after routing

`PAD70GU` and `PAD70NU` sit on **M8 / M9 / AP**. They do not occupy core rows
and therefore do not compete with standard cells, filler or hold buffers for
sites. There is no reason to place them before routing, and one good reason not
to — they are `CLASS BLOCK`, so their `OBS` blockages would constrain the router
for the whole run. Placing them last is deliberate.

### The clearance problem they cause

`PAD70NU`'s `OBS` is solid over its entire footprint on both M8 and M9:

```
OBS LAYER M8 ; RECT 0 0 30 171 ; LAYER M9 ; RECT 0 0 30 171 ;
```

Those are exactly the core-ring layers (`add_rings`: left/right M8, top/bottom
M9). And because both bond-pad cells are `CLASS BLOCK` rather than `CLASS PAD`,
`create_floorplan -core_margins_by io` **does not see them** — it insets the core
by the 135 µm IO-driver height only. Nothing in the margin computation knows the
inner bond pads reach 36 µm further inboard.

At `CORE_TO_IO 50` the rings were drawn straight through the inner bond pads, 16
µm of overlap on all four sides. `CORE_TO_IO 70` gives 4 µm of clearance.
**The full derivation, the wide-metal rules it has to satisfy, and the 5.6 %
core-area cost are in [04-power-plan.md](04-power-plan.md) and
[03-floorplan.md](03-floorplan.md) — read those before touching `CORE_TO_IO`.**

---

## 8. What to check after this stage

`4_pnr_route.tcl` runs all four checks for you. Read all four.

| Report | Expected | Reference-run result |
|---|---|---|
| `reports/*_imp_filler.rep` | header + `Checking Power Domain: PD_TOP`, nothing else | clean; `0 gaps`, `0 padded cell violations` |
| `reports/*_imp_antenna.rep` | `No Violations Found` | `No Violations Found` (280 000 nets, 0 violations) |
| `reports/*_imp_drc.rep` | ideally 0 | **580 violations** — see below |
| `reports/*_imp_connectivity.rep` | 0 | **1 000** (hit the error limit); `VSS`/`VDD` special routes with opens and dangling wire |

### The DRC signature you should expect to see change

`baseline_2026-08-05` (built at `CORE_TO_IO 50`) ended with 580 violations:

```
	          Short   MetSpc   EOLSpc   MinStp   MinEnc    NSMet   MinCut   MinWid   Totals
	M1            0        0       41        0        0        0        0        0       41
	M4            1       54        0       14        0        0        2        0       71
	M5            2        7        0       13       14        2        0        0       38
	M6            0        0        0        1        0        3        0        0        4
	M7            0        0        0        0        0        2        0        0        2
	M8          258        6        0        0        0        0        0        0      264
	M9          114       41        0        0        0        0        0        1      156
	AP            4        0        0        0        0        0        0        0        4
	Totals      379      108       41       28       14        7        2        1      580
```

M8 + M9 + AP account for 424 of 580, and the individual records read:

```
SHORT: ( Metal Short ) Special Wire of Net VSS & Blockage of Cell BuPAD_VDD_T_2  ( M9 )
SHORT: ( Metal Short ) Special Wire of Net VDD & Blockage of Cell BuPAD_HOST_IO_6 ( M8 )
```

`Special Wire of Net VDD/VSS` against `Blockage of Cell BuPAD_*` — that is the
power ring shorting to a bond-pad blockage, i.e. exactly the overlap the
`CORE_TO_IO` change was made to eliminate. Grep for it:

```sh
grep -c "BuPAD" ASIC/genus-innovus/reports/nanosoc_eth_chiplet_pads_imp_drc.rep
grep -n "SHORT" ASIC/genus-innovus/reports/nanosoc_eth_chiplet_pads_imp_drc.rep | head
```

**A `CORE_TO_IO 70` run should show that M8/M9 short population collapse.** If it
does not, the clearance fix did not take and you should go back to
[04-power-plan.md](04-power-plan.md) rather than chasing router settings.

The M1 `EOLSpc` (41), M4 `MetSpc` (54) and `MinStp` (28) populations are a
separate, core-side problem and will not be touched by the pad clearance — see
[08-debugging.md](08-debugging.md) and [11-known-issues.md](11-known-issues.md).

---

## 9. Failure modes

| Symptom | Cause | Fix |
|---|---|---|
| `add_fillers` reports `For 0 new insts`, `IMPSP-5110` is the only warning | CPF has no supply nets for `PD_TOP` | `make syn` cpf-patch (§4); `power_plan.tcl`'s guard should have caught it |
| GDSII has no `ANTENNA` cells | same as above | same as above |
| `add_fillers` says `Found no DRC violations to fix` | filler ran before routing | it must be sourced from `place_bondpads.tcl`, not `route_setup.tcl` (§2) |
| `IMPSP-9082 verifyGeometry needs to be executed` | no `check_drc` before `-fix_drc` | known, §6(a) |
| `IMPSP-5217 ... followed by eco_route -target` | filler on a post-route DB | expected consequence of correct ordering, §6(b) |
| Hundreds of M8/M9 shorts to `BuPAD_*` blockages | core ring overlaps `PAD70NU` OBS | raise `CORE_TO_IO`; [04-power-plan.md](04-power-plan.md) |
| `create_relative_floorplan` places a pad in the wrong place | wrong `-ref` — the reference is the IO cell, resolved by exact name | check the name lists at the top of `place_bondpads.tcl` |

---

## Related pages

[00-index.md](00-index.md) ·
[01-flow-overview.md](01-flow-overview.md) ·
[02-innovus-basics.md](02-innovus-basics.md) ·
[03-floorplan.md](03-floorplan.md) ·
[04-power-plan.md](04-power-plan.md) ·
[05-place-cts-route.md](05-place-cts-route.md) ·
**06-fill-antenna-bondpads** ·
[07-reading-reports.md](07-reading-reports.md) ·
[08-debugging.md](08-debugging.md) ·
[09-signoff-checklist.md](09-signoff-checklist.md) ·
[10-tapeout-submission.md](10-tapeout-submission.md) ·
[11-known-issues.md](11-known-issues.md)
