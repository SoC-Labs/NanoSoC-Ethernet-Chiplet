# 08 — Debugging

A way of working, illustrated entirely by real defects found in `nanosoc_eth_chiplet_pads`
during 2026-07 and 2026-08. Every example below cost somebody hours, and every one of them
would have been cheap under the discipline this page describes.

Prev: [07 — Reading reports](07-reading-reports.md) ·
Next: [09 — Signoff checklist](09-signoff-checklist.md) ·
[Index](00-index.md)

The seven principles, in the order you will need them:

1. [Exit status lies](#1-exit-status-lies)
2. [Ask the tool before theorising](#2-ask-the-tool-before-theorising)
3. [Warnings are where the bodies are](#3-warnings-are-where-the-bodies-are)
4. [Make hypotheses predict a number](#4-make-hypotheses-predict-a-number)
5. [Model offline before you re-run](#5-model-offline-before-you-re-run)
6. [Compare like with like](#6-compare-like-with-like)
7. [Preserve a baseline](#7-preserve-a-baseline)

Then the two mechanics that make all of this affordable:
[resuming from a snapshot](#resuming-from-a-snapshot-db) and
[inspecting a violation in the GUI](#inspecting-one-violation-in-the-gui).

---

## 1. Exit status lies

**Genus and Innovus both exit `0` after printing an error and doing nothing.** This is not
an edge case. It is the normal behaviour of both tools, and it is the single most expensive
fact on this page.

### The defect

Every stage script in `ASIC/asic-flows/Cadence/` carries a header saying
`run: innovus -stylus -f <script>`. That is wrong — `-f` is legacy-UI only. In stylus mode:

```
$ innovus -stylus -f open_db.tcl
Version:	v21.11-s130_1, built Thu Aug 19 16:59:56 PDT 2021
Options:	-stylus -f open_db.tcl
...
		invs	Innovus Implementation System	21.1	checkout succeeded

**ERROR: (IMPSYT-468):	Unknown argument -f
Usage: innovus
 	[-abort_on_error]
 	[-batch]
 	...
 	[-files <in_file_list>]
 	...
$ echo $?
0
```

The tool checked out a licence, rejected the argument, printed 60 lines of usage, and
exited **zero**. `make` treated the stage as passed and ran the next one, which did the
same thing. **Three P&R stages "passed" in under a minute.** The only symptom was a missing
GDS at the end of what should have been a five-hour run.

The full log is preserved at
`ASIC/genus-innovus/baseline_2026-08-05/work/innovus.log6` — 60 lines, all of them usage
text, zero lines of design work.

### The discipline

**Assert on artefacts, never on `$?`.** Every stage target in
`ASIC/genus-innovus/Makefile` does this:

```make
INNOVUS := innovus -stylus -files

pnr_place: setup_dirs
	cd $(WORK_DIR)/; $(INNOVUS) $(ASIC_FLOWS_DIR)/2_pnr_setup.tcl
	@test -d $(WORK_DIR)/$(BLOCK) || { \
	    echo "FAIL: placement wrote no DB at $(WORK_DIR)/$(BLOCK)"; exit 1; }

pnr_cts:
	cd $(WORK_DIR)/; $(INNOVUS) $(ASIC_FLOWS_DIR)/3_pnr_clock.tcl
	@test -s $(REPORT_DIR)/timing_summary_03_cts_opt.rep || { \
	    echo "FAIL: CTS wrote no post-opt timing summary — stage did not complete."; exit 1; }
```

Note what each assertion picks:

- **The last thing the stage writes**, not the first. `timing_summary_03_cts_opt.rep` comes
  from `report_end_step` at the very bottom of `3_pnr_clock.tcl`, so its existence proves
  the script ran to completion.
- **`test -s`, not `test -f`.** A zero-byte file is the signature of a tool that opened
  an output and then died.

The `pnr_route` assertion goes further and tells the next person where to look:

```make
	@test -s $(OUT_DIR)/$(BLOCK).gds \
	    && echo "OK: GDSII ..." \
	    || { echo "FAIL: no GDSII at $(OUT_DIR)/$(BLOCK).gds"; \
	         echo "      innovus exits 0 on a rejected argument or a failed script;"; \
	         echo "      find the real error with:"; \
	         echo "        grep -nE '\*\*ERROR|Unknown argument' $(WORK_DIR)/innovus.log*"; \
	         exit 1; }
```

**Write the diagnosis into the failure message.** You already know why it failed; the
person who hits it at 2am does not.

### Corollaries

- `make status` reads the artefacts on disk, not any record of what "ran". It is the
  fastest way to see where a part-finished flow actually stopped:

  ```bash
  cd ASIC/genus-innovus && make status
  ```

- **`-files`, not `-f`.** If you copy a command line out of a script header, check it
  against `innovus -help` first (see [principle 2](#2-ask-the-tool-before-theorising)).
- The same applies to a script that *did* run. `4_pnr_route.tcl` ends with `exit`, so a
  Tcl error partway through still lands you at exit 0 with a partial report set — which is
  precisely why [principle 7](#7-preserve-a-baseline) matters.

---

## 2. Ask the tool before theorising

Innovus documents itself, thoroughly, and almost nobody asks it. Three commands:

```tcl
<command> -help          # real usage for THIS build, including every option
help <pattern>           # find commands by name
man <MSGID>              # explain any message, e.g.  man IMPSP-5110
```

The logs literally tell you to run `man` on their message IDs. See
[02 — Innovus basics](02-innovus-basics.md) for the full treatment.

### The defect

`add_fillers` was inserting nothing, because power domain `PD_TOP` had no supply nets. The
confident hypothesis was: *fix it with `update_power_domain -primary_power_net VDD
-primary_ground_net VSS` in `power_plan.tcl`.* It is a plausible command name, it reads
like the right fix, and it is wrong.

Two minutes at the prompt killed it:

```tcl
@innovus> update_power_domain -help
```

**In this build `update_power_domain` takes the domain positionally and has no
`-primary_power_net` / `-primary_ground_net` options at all** — its entire option set is
floorplan geometry (`core_to_*`, `row_*`, `gap_*`). Running the guessed form returns
`IMPTCM-162` plus the usage string.

`create_power_nets`, `create_ground_nets` and `update_power_domain -primary_power_net` are
**CPF statements**, not Innovus commands. The repair therefore belongs in the CPF file
*before* Innovus reads it, which is a completely different fix in a completely different
file. `make syn` now patches `outputs/${BLOCK}_gate1.cpf` before `end_design`:

```
create_ground_nets -nets VSS
create_power_nets  -nets VDD
update_power_domain -name PD_TOP -primary_power_net VDD -primary_ground_net VSS
```

A hypothesis that would have cost a multi-hour re-run to disprove cost two minutes
instead. `ASIC/genus-innovus/scripts/power_plan.tcl` records the whole episode in its
header comment — including the words *"Verified by running it: IMPTCM-162 plus the usage
string."* Write that down when you do it.

### The discipline

Before you edit a script to use a command or an option:

```tcl
<command> -help                    # does this option exist in THIS build?
man <MSGID>                        # what does the tool think went wrong?
get_db <object> .??                # what attributes does this object actually have?
```

"I'm fairly sure that's the option" is a hypothesis, and it is a **free** one to test.
Never spend a five-hour run on an unchecked option name.

---

## 3. Warnings are where the bodies are

Grep for `**ERROR` first — then read every warning you do not recognise. On this design the
errors were mostly harmless and the warning was tapeout-blocking.

### The defect

```
IMPSP-5110: No supply-net names for Power Domain 'PD_TOP'
```

Reads like noise. It meant:

- every `add_fillers` pass reported `For 0 new insts`
- the 2026-08 GDSII shipped with **zero filler cells** and 95,568 free-site gaps (~5.9% of
  the core)
- **no base-layer density fill and no ANTENNA diodes**

Verifiable in the shipped netlist:

```bash
$ grep -c FILLER ASIC/genus-innovus/baseline_2026-08-05/outputs/nanosoc_eth_chiplet_pads_pnr.v
0
```

And `check_filler` reported it as **fine** — `Total number of gaps found: 0` — because it
could not evaluate the broken domain either. See
[07](07-reading-reports.md#check_filler-_imp_fillerrep).

The 2026-07 reference run hit the identical error and only survived because the operator
hand-edited the CPF mid-session and re-ran `add_fillers` at the prompt. **An unattended
flow has nobody to do that.**

### The errors, meanwhile, were mostly noise

The baseline run produced a working GDSII while emitting 92 `**ERROR` lines:

```bash
$ grep -hoE '\*\*ERROR: \([A-Z]+-[0-9]+\)' logs/pnr_all.log | sort | uniq -c | sort -rn
     60 **ERROR: (IMPLF-223)
     20 **ERROR: (TCLCMD-917)
      3 **ERROR: (IMPSE-110)
      3 **ERROR: (IMPMSMV-3501)
      2 **ERROR: (IMPSP-9099)
      2 **ERROR: (IMPDB-1221)
      1 **ERROR: (IMPSYT-6693)
      1 **ERROR: (IMPSYT-6692)
```

Triaged:

| ID | ×  | Message | Verdict |
|---|---|---|---|
| `IMPLF-223` | 60 | `The LEF via 'VIA12_1cut' definition already exists ... will be ignored` | benign — duplicate LEF, first definition wins |
| `TCLCMD-917` | 20 | `Cannot find 'pins' that match 'uPAD_VDD_B_0/VDD' (File ..._syn.sdc, Line 696)` | **worth chasing** — 20 SDC constraints are silently not applied |
| `IMPSE-110` | 3 | `can't find package Tk 8.0` | explains why the in-Innovus Calibre call is dead ([07](07-reading-reports.md#the-in-innovus-calibre-call-is-a-no-op-use-the-makefile)) |
| `IMPMSMV-3501` | 3 | `Input power intent (CPF/UPF) does not define power_mode/power_state` | same root cause as `IMPSP-5110` |
| `IMPSP-9099` | 2 | `Scan chains exist ... but are not defined for 30.55% flops` | ~~**worth chasing**~~ → **BENIGN, and now RETIRED (2026-08-18).** DFT is off by design. The message has not been emitted since **2026-08-07 14:21** and is absent from every build from 08-08 onward; today's equivalent is `IMPSP-9025` (WARN) "No scan chain specified/traced". Do not spend time chasing it. See `16-open-defects.md` §6. |
| `IMPDB-1221` | 2 | `GNC ... 'VDDIO' name pattern ... Unable to establish connection` | **worth chasing** — a power connection did not happen |

Three of six categories are real problems that no one has closed. None of them stopped the
run, and none of them would have been noticed by watching exit status.

### The discipline

```bash
L=ASIC/genus-innovus/logs/pnr_all.log

# 1. errors first — by ID, deduplicated, so 60 copies of one thing read as one thing
grep -hoE '\*\*ERROR: \([A-Z]+-[0-9]+\)' $L | sort | uniq -c | sort -rn

# 2. one example of each, with enough context to judge it
for m in $(grep -hoE '\*\*ERROR: \(([A-Z]+-[0-9]+)\)' $L | sort -u); do
    grep -m1 -F "$m" $L
done

# 3. now the warnings, same treatment — this is the step people skip
grep -hoE '\*\*WARN: \([A-Z]+-[0-9]+\)' $L | sort | uniq -c | sort -rn

# 4. anything you cannot name, ask the tool
#    @innovus> man IMPSP-5110
```

**Deduplicate by message ID before you judge severity.** 60 `IMPLF-223`s are one benign
fact; 1 `IMPSP-5110` is a blocking defect. Raw line counts invert the priority.

One known-benign `**ERROR` lives in the *report* files rather than the log: `TCLCMD-1130`
heads all six `timing_summary_*.rep`. Learn it so it does not blunt your instinct.

---

## 4. Make hypotheses predict a number

**A hypothesis that predicts nothing measurable cannot be tested, and will absorb
unlimited time.** Before you change anything, write down the number you expect to see and
the threshold that would falsify you.

### The defect

`check_connectivity` reports **329 PG opens** on the power nets. Cause unknown. Two
hypotheses were proposed, and both were phrased as predictions:

**Hypothesis A — the routing halos around the macros are blocking the PG stitching.**
> *Prediction: remove the halos and the open count drops below 329.*

Result, from `reports/conn_halo_test.rep`:

```
Begin Summary
    202 Problem(s) (IMPVFC-98): Net has no global routing and no special routing.
    329 Problem(s) (IMPVFC-200): Special Wires: Pieces of the net are not connected together.
    1328 Problem(s) (IMPVFC-94): The net has dangling wire(s).
    1859 total info(s) created.
End Summary
```

**329, unchanged. Dead, cleanly, in one run.**

**Hypothesis B — the via range for the PG stripes is too wide.**
> *Prediction: narrow it and the open count drops.*

Result, from `reports/conn_via_test.rep`:

```
    682 Problem(s) (IMPVFC-200): Special Wires: Pieces of the net are not connected together.
```

**682 — more than twice as bad. Dead, and informative:** the via range is not merely
irrelevant, narrowing it actively breaks connections. That is a stronger result than "no
change" and it came from the same one-run experiment.

Both hypotheses are now recorded as falsified in
[11 — Known issues](11-known-issues.md), so nobody re-tries them.

### The discipline

Write the experiment down in this shape before you run it:

```
HYPOTHESIS: <mechanism>
PREDICTS:   <metric> <goes which way> <past what threshold>
MEASURED BY: <exact command>
BASELINE:   <number, from a preserved run>
RESULT:     <number>  ->  CONFIRMED / FALSIFIED
```

If you cannot fill in `PREDICTS`, you do not have a hypothesis — you have a hunch, and a
multi-hour run is the wrong way to explore it.

Note also what both experiments did to make the measurement valid: they raised the message
cap.

```bash
# from conn_halo_test.rep's own header line
check_connectivity -type special -error 200000 -warning 200000 -out_file ../reports/conn_halo_test.rep
```

Without that, both runs would have saturated at 1000 messages and the comparison would
have been worthless — which is exactly the mistake described next.

---

## 5. Model offline before you re-run

**A run costs five hours. Python costs ninety seconds.** When a change is geometric,
arithmetic, or combinatorial, do it in a script first.

### The case

`CORE_TO_IO` had to rise from 50 to 70 µm to clear the inner staggered bond pads. The die
is fixed at 1600×2000 and anchored at (0,0), so **the core box moves inward and the macro
coordinates in `floorplan.tcl` are absolute** — they do not track it. Raising the number
silently pushes macros outside the core.

The naive approach is to change the number, launch, wait, read the failure, move one
macro, launch again. With 21 macros and a five-hour loop, that is a week.

Instead: all 21 macro bounding boxes were modelled in ~90 lines of Python and checked for

1. **core containment** — every macro fully inside the new `(175,175)-(1425,1825)` box, and
2. **pairwise overlap** — no macro colliding with any other after being moved.

The model found five macros outside the new core, with exact overhangs:

```
way1_word_0      14.96 um over
eth_scratch_tx   12.89
chip bootrom      7.00
net imem rf_32k   3.68
chip imem rf_16k  1.05
```

and showed that fixing those five required moving **twelve neighbours** as well — including
ten QSPI cache RAMs on a 45 µm pitch with only 8.64 µm between them, which can only move as
one rigid block. Seventeen moves in total, each verified against both constraints before
Innovus was launched once.

**One verified edit replaced a multi-hour trial-and-error loop.** The result is in
`ASIC/genus-innovus/scripts/floorplan.tcl`, where every moved macro carries its delta:

```tcl
place_macro {*region_eth_scratch_tx_0*} 1049.8 1633.8 MY  ;## MOVED -20 y: was 12.89 over the new core top
place_macro {*u_network_core*u_region_imem_0*rf_32k*} 290.8 1503.4 R0  ;## MOVED -10 y: was 3.68 over the new core top
```

### Then encode the model as an in-flow assertion

The offline model is a one-off. Make it permanent so the next person cannot repeat the
mistake. `place_macro` now ends with a containment check that runs at placement time:

```tcl
lassign [lindex [get_db current_design .core_bbox] 0] cx1 cy1 cx2 cy2
lassign [lindex [get_db [lindex $hits 0] .bbox] 0] mx1 my1 mx2 my2
if {$mx1 < $cx1 || $my1 < $cy1 || $mx2 > $cx2 || $my2 > $cy2} {
    error "place_macro: '$inst' at ($mx1,$my1)-($mx2,$my2) lies outside the core box ..."
}
```

`place_inst` takes absolute die coordinates and **does not object** when the result
straddles the core boundary — it places it and says nothing. The first symptom is a
power/route mess hundreds of lines later that reads as an `sroute` problem rather than a
floorplan one. The assertion moves the failure to the point of the mistake and names the
macro and the overhang.

Same pattern in `power_plan.tcl`, as a backstop for the CPF defect:

```tcl
if {[llength [get_db power_domains PD_TOP]] == 0} {
    error "power_plan: no PD_TOP power domain — check read_power_intent"
}
```

**Fail HERE with a clear reason rather than 3 hours later with a silently unfilled die.**

### When you need real data, probe cheaply

`scripts/probe_macros.tcl` replicates `2_pnr_setup.tcl` up to `init_design`, dumps every
macro's resolved hierarchical name, and **stops without writing a DB**:

```bash
cd ASIC/genus-innovus/work
TSMC_65_HOME=$TSMC_65_HOME \
NANOSOC_ETH_CHIPLET_HOME=/home/dam1n19/SoCLabs/nanosoc-ethernet-chiplet \
  innovus -stylus -files ../scripts/probe_macros.tcl < /dev/null
# -> ../logs/macro_insts.txt
```

Two details worth stealing:

- **The env vars matter.** `ASIC/common.mk` exports them; a bare shell does not have them,
  and `config.tcl` dies on `$::env(TSMC_65_HOME)`.
- **`< /dev/null` matters.** On any error Innovus drops to its interactive prompt and will
  sit there holding a licence until killed. Redirect stdin on every batch invocation.

This exists because Genus runs with auto-ungroup ON, so macro instance names move when the
RTL changes. When `place_macro` reports "matched 0 instances", probe for the real names
rather than guessing at the pattern.

---

## 6. Compare like with like

Two numbers from the same design at different *phases* are not comparable, and the report
files make it very easy to mix them up.

### The defect

A density comparison between two runs concluded that density had regressed. It had not.
The comparison had taken one run's **post-route** table against the other's **placement**
table.

`report_qor` is **cumulative**. `qor_01_place.rep` holds exactly one row:

```
| place_design | ... | 72.72 | 184372 | 1609582 | | 0:18:35 |
```

`qor_05_route_opt.rep` holds six, *including that same row*, and ends at:

```
| opt_design_postroute_hold | 0.068 | 0 | 0 | ... | 89.45 | 260119 | 1805556 | 0 | 3:06:20 |
```

72.72 vs 89.45 is a 16.7-point "regression" that is entirely phase. The design gains ~65,000
hold-repair buffers between those two rows; density is *supposed* to rise.

### The discipline

**Match on the snapshot name, not on the file.**

```bash
# right
for d in reports baseline_2026-08-05/reports; do
    awk -F'|' -v d=$d '/opt_design_postroute_hold/ {print d": "$8}' \
        ASIC/genus-innovus/$d/qor_05_route_opt.rep
done
```

The same trap has three other faces on this design:

- **Timing.** `timing_summary_01_place.rep` is `PreRoute / MMMC Non-OCV / No SPEF / SI Off`;
  `timing_summary_05_route_opt.rep` is `PostRoute / MMMC OCV / SPEF-RCDB / SI On`. The
  headers say so. Different analysis, incomparable slack.
- **Analysis view.** The end of `4_pnr_route.tcl` writes three pairs of timing reports under
  three different view sets. Always quote the filename alongside the number.
- **Truncated reports.** Two saturated `check_connectivity` files are not comparable at all —
  see below.

`scripts/ci/asic_stage_report.sh` gets this right structurally: it picks the report file
*by stage* and diffs it against **the same filename** in the baseline directory.

```bash
case "$STAGE" in
  place) T=timing_summary_01_place.rep ;;
  cts)   T=timing_summary_03_cts_opt.rep ;;
  route) T=timing_summary_05_route_opt.rep ;;
esac
```

### The truncation trap, specifically

`check_connectivity` caps its message list at 1000 by default. A previous analysis compared
**"171 vs 298" opens** across two runs and drew a conclusion. **Both files were saturated,
so the comparison was meaningless.**

The saturation signature is arithmetic — the category counts sum to exactly the cap:

```
    329 Problem(s) (IMPVFC-200): Special Wires: Pieces of the net are not connected together.
    671 Problem(s) (IMPVFC-94): The net has dangling wire(s).
    1000 total info(s) created.          <-- 329 + 671 = 1000 exactly
```

And truncation is **not proportional**. Re-run uncapped, the same design gives 329 opens
(unchanged — those messages were emitted first) but **1328** dangling wires, plus **202**
`IMPVFC-98` problems that do not appear in the capped report *at all*.

```bash
# ALWAYS check for saturation before quoting or comparing
sed -n '/Begin Summary/,/End Summary/p' reports/${BLOCK}_imp_connectivity.rep
```

Full treatment in [07](07-reading-reports.md#the-cap-trap-read-this-before-comparing-two-runs).

### Numbers propagate — re-derive them

A related failure mode: a number, once written into a comment, gets copied forward and
nobody re-measures it.

The baseline DRC total was recorded as **539**, from `grep -cE '^[A-Z]+:'`. The report's
own footer says:

```
  Total Violations : 580 Viols.
```

The grep misses the 41 mixed-case `EndOfLine:` violations. The true total is 580 and the
true share of PG-vs-bond-pad shorts is 55%, not the 59% that was derived from 539. The 539
was self-consistent between runs so the *deltas* were never wrong — but the absolute
figure propagated into `scripts/ci/asic_stage_report.sh`, into
`ASIC/genus-innovus/scripts/floorplan.tcl`'s header, and into the reasoning behind a
floorplan change.

`asic_stage_report.sh` was fixed on 2026-08-06 to read the trailer and fall back to a
case-insensitive count. `floorplan.tcl` still carries 539 and 59%; the decision it
justifies is unaffected, but the numbers are stale.

**When a report prints its own total, prefer it to any count you compute** — it cannot be
wrong about a violation class you have not thought of. And when you copy a number into a
comment, write down the command that produced it, so the next person can re-derive it
instead of trusting it.

---

## 7. Preserve a baseline

**Stage assertions test for artefacts BY NAME.** That is the right design
([principle 1](#1-exit-status-lies)) and it has one failure mode: a stale report left in
place from a previous run lets a FAILED stage report success.

`pnr_cts` passes if `reports/timing_summary_03_cts_opt.rep` exists and is non-empty. If CTS
dies in the first minute but yesterday's report is still sitting there, the assertion
passes, the flow continues, and route runs on a stale DB.

### The discipline

**Move the previous run aside before you start a new one.** Do not delete it, and do not
leave it in place.

```bash
cd ASIC/genus-innovus
mv reports outputs logs work baseline_$(date +%F)/     # or a named directory
mkdir -p reports outputs logs work
```

This buys two things at once:

1. **Every assertion becomes honest.** No artefact can survive from a run that did not
   produce it.
2. **You keep a diff baseline.** `asic_stage_report.sh` auto-discovers the newest
   `baseline_*` directory and diffs against it with no configuration:

   ```bash
   BASELINE_DIR=$(ls -d "$ASIC_DIR"/baseline_* 2>/dev/null | sort | tail -1)
   ```

`ASIC/genus-innovus/baseline_2026-08-05/` is that directory today, and every number in
[07](07-reading-reports.md) and on this page came out of it. Keep it. It is the only
complete record of a run that produced a GDSII.

### Know what `clean` does

```bash
make clean       # removes work/ and logs/ — KEEPS outputs/ and reports/
make distclean   # removes work/ logs/ outputs/ reports/ — DELETES the GDS
```

`make clean` deliberately preserves reports, which is convenient and is **exactly the
condition that makes a stale report pass an assertion**. If you `clean` and re-run, be
aware that `reports/` is now a mixture of two runs. `distclean` prints what it is about to
destroy first:

```
about to remove work/ logs/ outputs/ reports/ — including:
  !! outputs/nanosoc_eth_chiplet_pads.gds (442M)
```

Prefer moving a run aside to cleaning it.

---

## Resuming from a snapshot DB

The flow writes intermediate databases **specifically so you can test a fix cheaply.** Use
them. A full re-run from placement is ~5 hours; resuming from post-CTS is ~1 hour, and
resuming from post-place skips the 18-minute placement plus everything before it.

### The problem they solve

Every stage script ends with `write_db $block_name` — **the same name** — so each stage
overwrites the last and only the final post-route DB survives. Two extra snapshots are
written under distinct names to break that:

| DB in `work/` | Written by | State |
|---|---|---|
| `${block_name}_placed` | `scripts/cts_setup.tcl` | post-placement, pre-CTS |
| `${block_name}_cts` | `scripts/route_setup.tcl` | post-CTS, pre-route |
| `${block_name}` | every stage | whatever ran last |

`route_setup.tcl` is sourced by `4_pnr_route.tcl` immediately after its `read_db`, so
`_cts` is exactly the post-CTS state. 109 MB per snapshot; disk is not the constraint.

### How to resume

```bash
cd ASIC/genus-innovus/work
innovus -stylus
```

```tcl
@innovus> source ../scripts/config.tcl
@innovus> read_db nanosoc_eth_chiplet_pads_cts
```

`config.tcl` first is **not optional** — the block name and every library path live there,
and `read_db` alone fails without it.

Now test one thing:

```tcl
@innovus> source ../scripts/route_setup.tcl     ;# or just the setting you want to change
@innovus> route_design -global_detail
@innovus> check_connectivity -type special -error 200000 -warning 200000 \
              -out_file ../reports/conn_myexperiment.rep
```

That is how `conn_halo_test.rep` and `conn_via_test.rep` were produced — two falsified
hypotheses ([principle 4](#4-make-hypotheses-predict-a-number)) for the cost of two partial
runs rather than two full ones.

**Write experimental reports under distinct names** (`conn_halo_test.rep`, not
`..._imp_connectivity.rep`). Overwriting a flow report destroys the artefact a stage
assertion depends on, and contaminates your baseline.

### Resuming a whole stage

The three Innovus stages read the DB the previous one wrote and **cannot be
parallelised**. To resume a part-finished flow, invoke the stage you stopped at:

```bash
make status      # which stages have actually run
make pnr_cts     # resume from there
```

---

## Inspecting one violation in the GUI

Counting violations tells you how many. Looking at one tells you why. A single DRC line
gives you everything you need to find it:

```
SHORT: ( Metal Short ) Special Wire of Net VDD & Blockage of Cell BuPAD_HOST_IO_6  ( M9 )
Bounds : ( 1429.000, 1827.500 ) ( 1429.000, 1828.000 )
```

Net, cell, **layer**, and a coordinate rectangle.

### Open the design with the GUI

```bash
cd ASIC/genus-innovus
make gui
```

Use `make gui`, not `make pnr_setup`. `pnr_setup` drops you in an **empty** session where
`read_db` alone fails; `gui` sources `config.tcl`, reads the saved DB, and calls
`gui_show`.

Two non-obvious things that target handles for you, both worth understanding because they
fail *silently*:

- **`DISPLAY` is probed, not just tested for non-emptiness.** A malformed value (e.g.
  `12.0` with the leading colon missing) passes `test -n` and Innovus then drops to
  no-window mode with only a `WARN` — which reads as "the GUI didn't open". `make gui` runs
  `xdpyinfo` and, if the value looks like a bare number, tells you to
  `export DISPLAY=:$DISPLAY`.
  A ThinLinc desktop's `DISPLAY` does **not** reach a VS Code Remote-SSH terminal — they
  are separate shells.
- **`gui_show` is required, not decoration.** Launched with `-files`, Innovus creates its
  main window but never *maps* it: `xwininfo` reports `Map State: IsUnMapped` and `xprop`
  reports no `WM_STATE`. The session looks like a plain text console and the GUI appears
  simply not to exist, with no error, because from the tool's point of view nothing failed.
  An explicit `gui_show` maps it (`IsUnMapped` → `IsViewable`, verified).

### Navigate to the violation and interrogate it

From the DRC line above, zoom to the `Bounds` rectangle, click the offending shape, then
ask the tool what you selected:

```tcl
@innovus> get_db selected
@innovus> get_db selected .obj_type
@innovus> get_db selected .??              ;# every attribute this object has
```

`get_db selected` closes the loop between *"the GUI is showing me a shape"* and *"I have a
scriptable handle on it"*. Once you have the object, `.bbox`, `.layer`, `.net` and friends
tell you what it really is — which is usually the point, because a "Special Wire of Net
VDD" and a "Blockage of Cell BuPAD_HOST_IO_6" look identical on screen.

The programmatic counterpart, used by `power_plan.tcl` in this flow, is
`select_obj` / `deselect_obj -all` — select by name from a script, then look at what you
selected. Useful when the violating object has a hierarchical name too long to click
accurately.

### What this bought on this design

Looking at the actual geometry, rather than the counts, is what produced the diagnosis in
`floorplan.tcl`:

```
PAD70NU's OBS is solid over its whole footprint on M8 AND M9
  (vendor LEF geometry not reproduced -- TSMC licence),
which are exactly the core-ring layers (add_rings: left/right M8, top/bottom M9).
    margin 50 -> ring outer edge 155/1445/155/1845 vs PAD70NU at
                 171/1429/171/1829  = 16.00um OVERLAP every side
    margin 70 -> ring outer edge 175/1425/175/1825  =  4.00um clear
```

Note the **control** in that analysis: `PAD70GU`, the outer pad, has 32 violations and
**zero** PG shorts, because its inboard edge never reaches the ring band. A hypothesis that
explains the failures *and* correctly predicts where there are no failures is much stronger
than one that only explains the failures. Look for the control.

---

## Quick reference

```bash
cd ASIC/genus-innovus
L=logs/pnr_all.log; R=reports; B=nanosoc_eth_chiplet_pads

# where did the flow actually get to?
make status

# did the tool reject its own arguments and exit 0?
grep -nE '\*\*ERROR|Unknown argument' work/innovus.log*

# error triage, deduplicated by message ID
grep -hoE '\*\*ERROR: \([A-Z]+-[0-9]+\)' $L | sort | uniq -c | sort -rn
grep -hoE '\*\*WARN: \([A-Z]+-[0-9]+\)'  $L | sort | uniq -c | sort -rn

# the two silent killers
grep -c 'IMPSP-5110' $L                    # must be 0
grep -c FILLER outputs/${B}_pnr.v          # must NOT be 0

# is my connectivity report truncated?
sed -n '/Begin Summary/,/End Summary/p' $R/${B}_imp_connectivity.rep

# does my DRC grep agree with the tool's own total?
grep 'Total Violations' $R/${B}_imp_drc.rep
grep -cE '^[A-Za-z]+: \(' $R/${B}_imp_drc.rep

# stage summary + auto-diff against the newest baseline_*
../../scripts/ci/asic_stage_report.sh route
```

In the tool:

```tcl
<command> -help            # does this option exist in THIS build?
help <pattern>             # find a command
man <MSGID>                # explain a message
get_db selected .??        # what did I just click on?
get_db current_design .core_bbox
```

---

## Verified vs uncertain

**Verified** — reproduced from the repository and `baseline_2026-08-05/` this week:

- the `IMPSYT-468` / exit-0 failure, log preserved at `work/innovus.log6`
- the `**ERROR` inventory and every quoted message text, from `logs/pnr_all.log`
- zero `FILLER` instances in `outputs/nanosoc_eth_chiplet_pads_pnr.v`
- the halo experiment (329 → 329) and via experiment (329 → 682), including the
  `-error 200000 -warning 200000` command lines in the reports' own headers
- `check_connectivity` saturation: 329 + 671 = exactly 1000; uncapped 202 / 329 / 1328
- the cumulative `report_qor` phase mismatch, 72.72 vs 89.45
- the 539 vs 580 DRC discrepancy and its cause (41 mixed-case `EndOfLine:` lines)
- every Makefile and Tcl excerpt, quoted from the files as they stand

**Reported in-repo, not independently re-run here** (the flow's own comments are the
source, and they state they were measured):

- `update_power_domain -help` behaviour and `IMPTCM-162` — recorded in `power_plan.tcl`
  as *"Verified by running it"*
- the 95,568 free-site gap figure (~5.9% of core)
- the `IsUnMapped` → `IsViewable` `gui_show` observation
- the PAD70NU/PAD70GU overlap arithmetic in `floorplan.tcl`

**Uncertain:**

- **`get_db selected` has not been exercised in this build during this work.**
  `select_obj` / `deselect_obj` are used by sibling `power_plan.tcl` scripts in the same
  tool family, and `get_db` is used throughout this flow, but the specific
  `get_db selected` idiom is documented here as method rather than as a measured result.
  Confirm with `get_db -help` on first use.
- **The ~90-line Python macro model is not in the repository.** Its conclusions are
  preserved in `floorplan.tcl`'s comments and in the `## MOVED` annotations; the script
  itself was not committed. Anyone repeating the exercise will have to rewrite it.
- **Three `**ERROR` categories are open and untriaged**: `TCLCMD-917` (20 SDC constraints
  not applied), `IMPSP-9099` (scan chains undefined for 30.55% of flops), `IMPDB-1221`
  (a `VDDIO` global net connection not established). They are listed above as "worth
  chasing" on the strength of their message text, not on any analysis.
- **The 329 PG opens remain unexplained.** Two hypotheses falsified; no third proposed.
  See [11 — Known issues](11-known-issues.md).

---

Prev: [07 — Reading reports](07-reading-reports.md) ·
Next: [09 — Signoff checklist](09-signoff-checklist.md) ·
[Index](00-index.md)
