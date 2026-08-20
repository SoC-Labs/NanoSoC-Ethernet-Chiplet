# Two gates for one defect class

*A joint work commissioned on behalf of SoC Labs, under Arm Academic Access
license. Contributors: David Mapstone (d.a.mapstone@soton.ac.uk).
Copyright 2026, SoC Labs (www.soclabs.org).*

Written 2026-08-20 against `feat/padring-boundary-scan`. **Nothing in
`ASIC/asic-toolkit` was modified** — the submodule is dirty with several
sessions' work and a peer owns tonight's EDA scheduling. This is a reviewable
patch set.

| file | what it is |
|---|---|
| `PATCHSET.md` | every hunk, with anchor text |
| `survival.tcl` | **gate 1** — the declared-logic survival engine |
| `survival_manifest.eth-chiplet.tcl` | gate 1, project side |
| `prov_closure.tcl` | **gate 2** — the transitive input fingerprint |
| `demo_survival_gate.py` | gate 1's evidence, against the two real netlists |
| `demo_prov_closure.sh` | gate 2's evidence, against the two real SDC sets |
| `stage_test/t_survival.tcl` | the Tcl, executed under `tclsh` |
| `stage_test/scenarios.md` | the toolkit stage-test cases |
| `sdc_assertion_rewrite.md` | the SDC assertion's comment, rewritten |

**Related documents in this directory, written concurrently by other sessions.**
`DELETION_ROOTCAUSE.md`, `DELETION_BISECT_PLAN.md` and `RUN_INPUT_DIFF.md`
establish *what happened* — independently reaching the same verdict as §0 below.
`TOOLKIT_PROMOTION_PLAN.md` covers promoting the boundary-scan *flow* into the
toolkit, which is adjacent to but distinct from the design-agnostic *gates*
proposed here. This document is the only one that proposes the two gates.

---

## The theme, stated once

> **The flow asserts on what it was told to look at. This class of failure lives
> in what it was not.**

Three instances, same shape:

| | what vanished | what could not see it |
|---|---|---|
| 2026-06 | 34 supply pads | nothing declared pads must survive → **§13a was written** |
| 2026-08 | 4 boundary-scan update flops | nothing declared *anything else* must survive → **gate 1** |
| 2026-08 | the constraint edit that caused it | only the *named* SDC is hashed, not what it `source`s → **gate 2** |

§13a is a special case with the general mechanism missing behind it. Gate 1 is
that mechanism, with §13a as its first entry. Gate 2 is the same principle
applied to inputs rather than logic.

---

## 0. The alarm was false, and that sharpens the brief

The brief reported **117 of 119 boundary-scan cells deleted**. Three agents
independently established that the register was never deleted. Measured here:

| | `bscan-probe` | `bscan-probe2` |
|---|---|---|
| `module nanosoc_eth_chiplet_bscan` | present | **auto-ungrouped into the parent** |
| boundary flops, statement-aware count | 119 | **115** |
| all 76 shift stages | present | **present** |
| TAP / IR / IDCODE / bypass / TDO | 4 / 10 / 32 / 1 / 2 | 4 / 10 / 32 / 1 / 2 |
| `GLO-51` "hierarchical instance automatically ungrouped" | ×45 | **×47** |

Four update flops went, all on pads the TAP itself borrows
(`u_bsc_05_SWDIO_IO_oe`, `u_bsc_23_HOST_IO_1_oe`, `u_bsc_24_HOST_IO_1_data`,
`u_bsc_26_HOST_IO_0_oe` — `pad_table.json` gives `tms`=SWDIO, `tdi`=HOST_IO_0,
`tdo`=HOST_IO_1). Still worth failing a run over: those are the control cells
EXTEST needs to drive those pins. Not the annihilation reported.

**Where "117" came from, reproduced exactly.** `write_hdl` wraps at a column.
Once the module ungrouped, every instance name gained a 28-character prefix
(`u_nanosoc_eth_chiplet_bscan_`) and wrapped past the wrap column, putting cell
type and instance name on **separate lines**:

```
kept:       SDFCNQD1 u_bsc_00_NRST_I_obs_dr_q_reg(.CDN (trst_n), .CP
ungrouped:  SDFCNQD1
                 u_nanosoc_eth_chiplet_bscan_u_bsc_00_NRST_I_obs_dr_q_reg(.CDN
```

A line-oriented scan then sees only the cells whose names stayed short enough.
Running one against both netlists yields **119** and **2** — and the two
survivors are precisely the two shortest pad names, `CLK` and `SE`.

### Requirement, promoted to first-class

> **A survival check MUST be statement-aware, never line-oriented.**

Otherwise the sensitivity of the measurement is a function of a tool decision
that has nothing to do with the defect — name length, set by ungrouping, which
is the very thing under investigation.

**The in-flow gate is immune by construction**: it queries database objects,
which have no line breaks. That is a structural argument for putting the gate
inside Genus rather than downstream of `write_hdl`, independent of the "before
hours of P&R" argument. Every *text*-based checker in this repository is
vulnerable and must normalise whitespace across the whole file before matching
— `scripts/bscan_syn_verdict.py` (**already fixed by another session, whose new
comment reads "*it had deleted 4*"**), and
`ci/fixtures/boundary-scan/PROPOSED_STANZA.yaml` (**not yet fixed**).

---

## 1. Why every existing guard missed

### 1.1 `bscan_constraints.sdc` §4 — right check, wrong point in the flow

```tcl
if {![llength [get_cells -quiet u_nanosoc_eth_chiplet_bscan]]} { error ... }
```

Constraints are read at §8, after `elaborate`, before `syn_generic`. Everything
the guard exists to catch happens **after** this line has passed. It proves the
RTL was read and the filelist was right; it cannot prove anything about
optimisation.

It has a second, quieter fault: it resolves a **module instance**. On
`bscan-probe2` that instance does not exist, because Genus ungrouped it — so
even relocated later in the flow it would report total deletion where four
cells went. Rewritten comment in `sdc_assertion_rewrite.md`.

### 1.2 `scripts/bscan_syn_verdict.py` — catches it, runs never

Correct in intent, and it produced the red. Two defects, one of each kind:
**not wired to anything** (it must be typed, so it is absent on the day it
matters), and **module-anchored + line-oriented**, which is why the red was 30×
too large. Now fixed by another session; left alone.

### 1.3 `PROPOSED_STANZA.yaml` — right stage, wrong era

A good signoff stage — eight fixtures, a vacuity arm, `UNVERIFIED` separated
from `FAIL`, expectations derived from the pad table. But it is **not spliced
into `ci/signoff.yaml`**, so today it checks nothing; and signoff runs *after*
place, CTS and route, so it cannot stop hours being spent on a dead netlist. It
is the right backstop and the wrong tripwire. It also inherits the
module-anchored, line-oriented count and would produce the same wrong red.

### 1.4 §13a, the pad-ring check — the model

`flow/genus/1_synthesis.tcl:1019`. Gets the four hard things right: runs
**inside the tool, after `syn_opt`, before `write_hdl`**; **derives** its
expectation from the design's own `.io` file; **absent means not applicable**;
uses **`syn_hard`**. It is also, verbatim, a special case — it knows what a pad
is, and nothing else can borrow it.

---

## 2. Gate 1 — declared-logic survival

```tcl
survive <label> -pattern <glob> | -names <list>
                ?-min <n>? ?-source <text>? ?-baseline? ?-advice <text>?
```

### 2.1 How a design declares, and how the toolkit stays ignorant

**The manifest is Tcl, and it is sourced.** The engine parses nothing and knows
nothing about pad tables; the project computes its own floors and calls
`survive` with integers. `survival_manifest.eth-chiplet.tcl` reads
`pad_table.json` with a `regexp` (no `package require json` — tcllib is not part
of a tool installation) and derives 76 shift + 43 control = **119**, plus **4**
TAP state bits and **48** pads. **No number is typed in that file**; the compute
chiplet's 80 falls out of the same code.

### 2.2 Two count sources, because neither is sufficient

A pre-optimisation headcount needs no manifest and is what §13a effectively
does. **It is not enough**: with the enable pad case-analysed, the register dies
in `syn_generic`, *before any post-mapping baseline could have counted it*.

| | catches | cannot catch | gives you |
|---|---|---|---|
| `-min` + `-source` | deletion at **any** stage; RTL never generated; file missing from the flist | drift nobody re-derived | a number |
| `-baseline` | deletion after mapping, with **no number at all** | anything gone before mapping | **which** instances went |

`-source` is mandatory with `-min`: a floor with no stated provenance is a
literal, and the engine refuses it.

### 2.3 Instance names, and why the leading `*` is load-bearing

Genus ungroups **selectively** — ×45 and ×47 on two runs of the same RTL one day
apart. Instance names survive (they are built from the hierarchical path);
module names do not survive at all. Hence patterns over instance names, with a
leading `*` to absorb the prefix. Three defences against a missing one:

1. `survive` **warns at registration** (a warning, not an error — a top-level
   pad name is legitimately unprefixed).
2. `syn_survive_count` tries four query spellings and takes the **maximum**, not
   the first non-empty: when the hierarchy is kept only a hierarchical form
   finds the flops; when it is ungrouped the same flops are top-level. **Both
   occurred on this design.** Every form's count is printed.
3. Before accusing the design, the gate **re-counts with `*` prepended** and, if
   higher, says so — turning the likeliest false-fail into a self-diagnosing
   message rather than a morning spent hunting a missing asterisk.

### 2.4 Where it runs

| point | section | why there |
|---|---|---|
| read manifest | end of **§0 input contract** (~:215) | a malformed manifest costs nothing here, a licence-hour later |
| **baseline** | end of **§11 mapping** (~:981), after `syn_map`, before §12 | before `syn_generic` the mapped flops do not exist; after `syn_opt` it is too late. **This seam is reachable only from inside the engine** — project hooks are `pre_synth` (before `syn_generic`) and `post_synth` (after `syn_opt`). The single strongest argument for the toolkit over a project hook. |
| **assert** | new **§13b**, after §13a (~:1057) | after `flow_hook post_synth` and the pad-ring check, ~70 lines before `write_hdl` |

The baseline precedes §12's scan insertion, so a scan-sensitive claim should use
`-min`/`-source`, not `-baseline`. Stated in the hunk.

### 2.5 Absent means not applicable

Modelled on `BONDPADS_TCL` (`flow/innovus/4_route.tcl:1002`):

| state | behaviour |
|---|---|
| `SURVIVAL_MANIFEST` empty | one `say` line, no gate. **The default for every consumer.** |
| empty, but `$ASIC_DIR/survival.tcl` exists | `warn` — a lost variable must not read as "no claims". Mirrors §13a's `PAD_RING=1` + unreadable `IO_FILE` arm. |
| set, unreadable | `flow_assert_input` → hard input-contract failure |
| readable, **0 claims registered** | `die`. "No claims" is spelled by having no manifest. |
| `-min <= 0`, or `-min` with no `-source` | refused at registration |
| `-baseline` claim matching **0** after mapping | `syn_hard` — a zero baseline cannot detect a deletion, so the claim would be green whatever optimisation does |

### 2.6 `syn_hard`, not `flow_fail`

**`flow_fail`** (`flow_utils.tcl:92`) prints and stops *only* under strict; §16
builds its verdict from Genus **message IDs**, which `flow_fail` does not
produce — so under `SYN_STRICT=0` a run already told it was broken writes a
netlist and reports `Status : OK`. **`syn_hard`** (`1_synthesis.tcl:178`)
records into `::SYN_HARD` *and* calls `flow_fail`; §16 turns that into `die`
(`:1379`) whatever `SYN_STRICT` says.

**Caveat, not glossed.** Under `SYN_STRICT=0` the run continues from §13b, so
§15 still **writes the dead netlist** before §16 kills the stage. `make` sees a
non-zero exit and P&R does not start, but the artefact is on disk with a fresh
mtime, and this repository has a documented history of consumers keying on file
existence. **Run tapeout synthesis with `SYN_STRICT=1`.**

### 2.7 Does it subsume §13a?

**Yes** — `-names $::SYN_IO_INSTS -baseline`, with the pad-ring diagnosis kept as
`-advice`; the two-fault split (absent at §7 = naming mismatch; present then and
absent now = optimisation) survives as the baseline-set diff. **Land it
separately and later** (Patch B): §13a is the only thing standing between this
flow and a defect that has shipped three times, and rewriting it in the same
change means that if the mechanism is wrong §13a is wrong too — invisibly,
because §13a passes silently on a healthy design either way.

---

## 3. Gate 2 — the transitive input fingerprint

### 3.1 The hole

`provenance.tcl` records `flist.sha256` for the file named by `ASIC_FLIST`, and
nothing for what that flist pulls in with `-f`. The stage records `SDC_FILES` by
name and nothing for what those pull in with `source`. **The manifest
fingerprints the entry points only.**

Measured, and the reason a day was spent:

```
ASIC/genus-innovus/inputs/constraints.sdc        44270 B   IDENTICAL
ASIC/genus-innovus/inputs/bscan_constraints.sdc   5255 B -> 6724 B   CHANGED
```

`constraints.sdc` `source`s five sub-SDCs (`qspi`, `tidelink`, `ethernet`,
`i2c`, `bscan`) at lines 241–248. Only the parent is named to the flow, so the
manifest showed **no input change at all** while the constraint set had
materially restructured the netlist hierarchy. Same hole one layer over:
`build/chip/flist/{soc,tidelink_asic}.flist` are regenerated before every
synthesis and are reached only through `-f`.

### 3.2 And the snapshot does not save you

```
ASIC/eth-chiplet/build/bscan-probe/inputs  -> .../ASIC/genus-innovus/inputs
ASIC/eth-chiplet/build/bscan-probe2/inputs -> .../ASIC/genus-innovus/inputs
```

`build/<tag>/inputs` is a **symlink to the live tree**, not a copy. Both runs
point at the same directory, so after an in-place edit the earlier run's bytes
are gone. (Here git happened to hold the old version, because the sub-SDC was
committed between the runs; an uncommitted edit — the normal state of this tree
— would be unrecoverable.) **Hence: fingerprint at READ TIME.** It cannot be
reconstructed at §16, and the callers are placed accordingly:

| closure | taken at | why not later |
|---|---|---|
| flist | §6, immediately after `read_filelist` | `build/chip/flist/*.flist` are regenerated before every synth |
| SDC | §8, immediately after `foreach s $SDC_FILES { read_sdc $s }` (`:764`) | `inputs/` is a live symlink; §16 would hash whatever is there *then* |

### 3.3 It records; it does not judge

There is deliberately **no pass/fail criterion**. Changing constraints is normal
work, and a gate that reddens on every legitimate SDC edit is switched off
within a day. The gate *is* the record: the manifest carries one aggregate
digest per closure, and a sidecar `syn_inputs.sha256` carries the per-file
listing a human diffs. Unresolved includes are recorded as
`UNVERIFIED:<reason>`, never skipped — a silent omission is indistinguishable
from "there was nothing to find".

`read_flist.tcl` **already** walks `-f`/`-F` recursively in both passes; it just
does not record which flists it visited. The patch is one `lappend` — a second
implementation of a traversal is a second thing to be wrong, which is the
reasoning `provenance.tcl` already applies to ROM hashes.

### 3.4 The SDC scanner's honest limits

An SDC is Tcl, so a `source` can be computed and no static scanner is complete.
This one handles literal paths, strips comments and options, follows
recursively, guards cycles, and resolves relative paths against **both** the
process CWD (which is how Tcl actually behaves, and what
`source ../inputs/qspi_constraints.sdc` relies on) and the sourcing file's
directory — recording which resolved. A path containing `$` or `[` is recorded
as `computed`, not guessed at.

---

## 4. Evidence

### 4.1 The wrapping requirement, reproduced

```
expectation source : src/rtl/bscan/pad_table.json
design             : block=nanosoc_eth_chiplet_pads module=nanosoc_eth_chiplet_bscan boundary_length=76 pads=48
claims             : 2 (no count below is written in this file)

==============================================================================
REQUIREMENT CHECK: statement-aware vs line-oriented counting
==============================================================================
    bscan-probe    hierarchy kept       line-oriented 119   statement-aware 119
    bscan-probe2   hierarchy UNGROUPED  line-oriented   2   statement-aware 115
                   the 2 the line-oriented scan kept are the SHORTEST names only:
                     u_nanosoc_eth_chiplet_bscan_u_bsc_02_CLK_I_obs_dr_q_reg
                     u_nanosoc_eth_chiplet_bscan_u_bsc_04_SE_I_obs_dr_q_reg

    A line-oriented scan reports the healthy-but-ungrouped netlist as
    catastrophic. That is the origin of the '117 of 119 deleted' alarm.

```

### 4.2 Gate 1 against the two real netlists

`python3 docs/bscan/demo_survival_gate.py` — derivation, comparison, vacuity
arms and verdict, substituting a netlist parse for the `get_db` query.

```
==============================================================================
RUN bscan-probe
    ASIC/eth-chiplet/build/bscan-probe/outputs/nanosoc_eth_chiplet_pads_gate.v
    193770 instances parsed, 35.3 MB

    [ok  ] boundary-scan shift and update flops       119 / 119
             derived from src/rtl/bscan/pad_table.json: boundary_length=76 + control cells=43 (out 15 + 2*bidir 13 + od 2)
    [ok  ] pad instances named by the pad table       48 / 48
             derived from src/rtl/bscan/pad_table.json: 48 entries in `pads`

    VERDICT: PASS
==============================================================================
RUN bscan-probe2
    ASIC/eth-chiplet/build/bscan-probe2/outputs/nanosoc_eth_chiplet_pads_gate.v
    192896 instances parsed, 35.6 MB

    [FAIL] boundary-scan shift and update flops       115 / 119
             derived from src/rtl/bscan/pad_table.json: boundary_length=76 + control cells=43 (out 15 + 2*bidir 13 + od 2)
    [ok  ] pad instances named by the pad table       48 / 48
             derived from src/rtl/bscan/pad_table.json: 48 entries in `pads`

    VERDICT: FAIL -- 1 hard failure(s)
      - boundary-scan shift and update flops: 115 instance(s) present, at least 119 required (src/rtl/bscan/pad_table.json: boundary_length=76 + control cells=43 (out 15 + 2*bidir 13 + od 2))
==============================================================================
EXPECTED: bscan-probe PASS (rc 0), bscan-probe2 FAIL (rc 1)
ACTUAL  : bscan-probe rc=0, bscan-probe2 rc=1
DEMONSTRATION: the gate discriminates
```

### 4.3 Mutation proofs — can each arm be made to fire?

`--selftest`. A gate seen to fail once has been seen to fail on one axis.

```
==============================================================================
MUTATION PROOFS
    [ok  ] M1 vacuous expectation (boundary_length=0) must NOT pass       0/0
             VACUOUS: minimum=0
    [ok  ] M2 pattern that matches nothing must NOT pass                  0/119
    [ok  ] M3 non-ungroup-tolerant pattern still passes the INTACT netlist 119/119
    [ok  ] M3 non-ungroup-tolerant pattern on the UNGROUPED netlist self-diagnoses 0/119
             PATTERN IS NOT UNGROUP-TOLERANT: 0 matched as written, 115 matched with a leading `*`. Genus ungrouped the enclosing hierarchy and prefixed every instance name with its path. Fix the pattern, not the design.
    [ok  ] M4 a pad the table names but the netlist lacks must NOT pass   48/49
             missing: uPAD_DOES_NOT_EXIST
    [ok  ] M5 CONTROL: the real claim on the real intact netlist passes   119/119

    6/6 mutation proofs behaved as specified
```

**M3 is the important one**: the same 119 flops, and a module-boundary-anchored
pattern reads **0** on the ungrouped run against **115** with a leading `*`.

### 4.4 The Tcl itself, executed

Parsing is not running. `tclsh docs/bscan/stage_test/t_survival.tcl` sources the
proposed engine with every Genus query stubbed:

```
SURVIVAL GATE -- executed in tclsh 8.6.8

  1. healthy design: 8 declared, 8 present
    [ok  ] no hard failure on an intact design

  2. optimisation deleted 4 of 8
    [ok  ] one hard failure recorded
    [ok  ] the summary names 4 of 8

  3. THE UNGROUP CASE: every flop present, but renamed by the ungroup
    [ok  ] an ungroup-tolerant pattern does NOT false-fail

  4. the same design with a pattern that is NOT ungroup-tolerant
    [ok  ] it fails (correctly loud, wrongly accused)
    [ok  ] and the message says the PATTERN is at fault, not the design
    [ok  ] and it was warned about at registration time

  5. vacuity: a floor of 0 is refused at registration
    [ok  ] -min 0 raises
    [ok  ] and says why a zero floor measures nothing

  6. a floor with no provenance is refused
    [ok  ] -min without -source raises
    [ok  ] and names the literal problem

  7. a claim that asserts nothing is refused
    [ok  ] neither -min nor -baseline raises

  8. a baseline that matches nothing is a hard failure, not a green skip
    [ok  ] zero baseline fails rather than passing vacuously

  9. explicit names: one pad deleted after mapping
    [ok  ] the missing pad fails the gate
    [ok  ] and is attributed to optimisation, not to a naming mismatch

 10. no manifest at all is not applicable, not a failure
    [ok  ] returns 0 claims
    [ok  ] and records no failure

  17 passed, 0 failed
```

This test earned its keep: case 4 initially **failed**, because the
ungroup-tolerance warning lived in `syn_survive_read_manifest` and so fired only
for claims registered through the manifest reader. It was moved into `survive`
itself. Neither a design review nor the stage harness would have caught that.

### 4.5 Gate 2 — does the closure discriminate?

`sh docs/bscan/demo_prov_closure.sh`, reconstructing both constraint sets from
git:

```

==================================================================
VERDICT
==================================================================
  entry-point hash : SAME       (constraints.sdc, 44270 B, both revisions)
  closure hash     : DIFFERENT
  files the closure names as changed: 4
    Files bscan_constraints.sdc and  differ
    Files ethernet_constraints.sdc and  differ
    Files i2c_constraints.sdc and  differ
    Files qspi_constraints.sdc and  differ

  READ THAT NUMBER HONESTLY. 4 files moved between these two COMMITS, not
  one - the commits are a stand-in for the two constraint sets, because the
  bytes the two RUNS actually read are unrecoverable (build/<tag>/inputs is
  a symlink to the live tree, so an in-place edit leaves no snapshot). That
  irrecoverability is the argument for fingerprinting AT READ TIME, and it
  is why this demo has to reconstruct from git at all.

  The point stands regardless: the entry point names ZERO changed files and
  the closure names 4, one of which is bscan_constraints.sdc, 5255 -> 6724 B,
  the edit that restructured the netlist hierarchy.
```

---

## 5. How these guards can still be fooled

1. **The query spelling is unverified against real Genus.** `get_db insts -if
   {.name == …}` and `get_cells -hierarchical -filter {name =~ …}` differ across
   versions in whether `.name` is the leaf or the full path — this project's own
   `protect_link_clk_div.tcl` says so out loud. `max`-over-four-forms makes an
   undercount unlikely and the printed per-form table makes disagreement
   visible, but **the first real run must be read, not assumed.**
2. **A pattern that matches too much.** `*u_bsc_*_reg` is satisfied by 119
   instances of anything named that way. Nothing checks the cells are
   sequential, clocked by TCK, or wired **in a chain**. 119 disconnected flops
   pass.
3. **The floor derives from an artefact that could itself be wrong.**
   `pad_table.json` and the RTL come from the same generator, so a generator bug
   moves both together and the gate agrees with itself.
4. **`-baseline` cannot see `syn_generic`.** By construction; it is why `-min`
   exists, and why a `-baseline`-only claim is weaker than it looks.
5. **A project can weaken its own manifest.** Lowering `-min` or deleting a
   claim is a review control, not a technical one.
6. **`SYN_STRICT=0` still writes the netlist** (§2.6).
7. **The demonstration is not the gate.** `demo_survival_gate.py` parses text;
   the gate queries a database. Same population — the gate runs before
   `write_hdl` — but not the same measurement.
8. **Nothing here checks the register *works*.** Every claim is a headcount.
   Whether the surviving 115 form a shiftable chain EXTEST can load is a
   question for a JTAG simulation this project does not have.
9. **Gate 2's SDC scanner cannot follow a computed `source`.** It records it as
   `computed` rather than resolving it, so the closure is honestly incomplete
   rather than silently so.
10. **Gate 2 records; it cannot recover.** A file regenerated or edited between
    two runs is unrecoverable if the earlier run predates the gate. The
    fingerprint only helps from the first run that takes it.

---

## 6. What to do next, in order

1. Review and land **Patch A + A'** (gate 1) and **Patch C** (gate 2). All
   additive; gate 1 is inert for any design declaring nothing, gate 2 adds
   fields to a manifest.
2. Run one `make syn` with `SYN_STRICT=1`. **Read the per-form count table**
   (§5.1) before trusting any verdict.
3. Land the stage tests — six reds and two greens.
4. Then, separately, **Patch B** (§13a on the mechanism).
5. Independently: fix the module-anchored, line-oriented count in
   `ci/fixtures/boundary-scan/PROPOSED_STANZA.yaml`. It would produce the same
   wrong red that started this.
