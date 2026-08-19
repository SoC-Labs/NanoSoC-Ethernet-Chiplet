<!--
  ci/fixtures/boundary-scan — evidence fixtures for the `boundary-scan` signoff stage
  A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.

  Contributors

  David Mapstone (d.a.mapstone@soton.ac.uk)

  Copyright 2026, SoC Labs (www.soclabs.org)
-->
# `boundary-scan` — proving the gate can fail

The stage this proves is **not yet in `ci/signoff.yaml`**. It is written out in
[`PROPOSED_STANZA.yaml`](PROPOSED_STANZA.yaml) beside these fixtures, with the
insertion point named in its header, because `ci/signoff.yaml` is being edited by
other sessions and two concurrent writers would collide.

```bash
scripts/ci/signoff.py prove boundary-scan     # after splicing the stanza in
```

## What the gate exists to catch

The IEEE 1149.1 boundary-scan register can be **deleted by correct tool
behaviour, without any error**.

Its only stimulus is the TAP, and the TAP's enable is the `SE` pad. With
`set_case_analysis 0 [get_ports SE]` the whole register becomes unreachable and
unobservable, and at that point Genus removing all 76 boundary cells is not a
tool defect — it is proper constant propagation. There is no warning, no
non-zero exit, a green synthesis log, and no boundary scan in silicon.

Nothing in the ladder noticed. Before the proposed stanza,
`grep -ci bscan ci/signoff.yaml` returned **0** (measured 2026-08-19).

`SE` makes this worse than it sounds: the pad's output is unconnected in the
padring, so the case-analysis constrains nothing downstream and there is no scan
chain behind it. The constraint is **inert as timing and lethal as
optimisation** — it removes logic without moving a single reported number, so no
timing or area report can show its effect either.

## Where the numbers come from

`src/rtl/bscan/pad_table.json`, never a literal:

| quantity | key | eth chiplet | compute chiplet |
|---|---|---|---|
| boundary cells | `design.boundary_length` | 76 | 80 |
| pad instances | `len(pads)` | 48 | — |
| register module | `design.module` | `nanosoc_eth_chiplet_bscan` | — |

A number typed into the manifest would be right for one die and silently wrong
for the other, and this manifest is meant to be ported to the compute chiplet by
editing YAML.

## Provenance — these are captures, not inventions

Every netlist here is a trimmed extract of the **real** synthesised netlist

```
ASIC/eth-chiplet/build/bscan-probe/outputs/nanosoc_eth_chiplet_pads_gate.v
Cadence Genus(TM) Synthesis Solution 21.15-s080_1, 2026-08-19 14:06:34 BST, 35.3 MB
```

taken by extracting, **verbatim**: the whole `nanosoc_eth_chiplet_bscan` module
(972 lines, 166 sequential cells), its instantiation block, and the
instantiation block of each of the 48 pad cells the table names. The other
~575,000 lines are irrelevant to this gate and are elided. Each fixture then
carries **at most one** mutation, named in a comment at the top of its own file.
That keeps the whole set at ~330 KB instead of 8 × 35 MB.

Confidence: **high — extracts of a real Genus netlist, not hand-written text.**
The residual risk the top-level `ci/fixtures/README.md` names still applies: if a
future Genus changes how it spells a flop instantiation, the fixtures and the
check would drift together and `prove` would stay green while the real gate went
blind. The two real-artefact controls below are what stand against that.

## The two controls that are not fixtures

`prove` shows the check discriminates between two shapes of evidence. It does
not show either shape is what the tool emits. Both of these were run against
**real 35 MB netlists, unmodified**:

| control | netlist | result |
|---|---|---|
| positive | `build/bscan-probe/outputs/…_gate.v` — the run that carries boundary scan | **PASS** — module present, 972 lines, 166 sequential cells, 1 instantiation, 48/48 pads |
| negative | `build/full-20260814/outputs/…_gate.v` — the shipping tapeout netlist, which genuinely has no boundary scan | **FAIL** — `bsr mod : ABSENT`, `bsr inst : 0`, 0 sequential cells |

The negative control is the valuable one: it is a real netlist with a real
absence, and the gate calls it red without a fixture being involved.

## The cases

| fixture | expect | the single change to the design it simulates |
|---|---|---|
| `pass` | rc 0 | none — the netlist as synthesised on 2026-08-19 |
| `fail-register-deleted` | rc 1 | `set_case_analysis 0 [get_ports SE]` left in the SDC: the register is unreachable, Genus sweeps all 76 cells, and both the module and its instance are gone |
| `fail-count-short` | rc 1 | the shift path broken partway along (one `tdi`→`tdo` link dropped in the RTL), so the stages downstream of the break become unobservable and 126 of 166 flops are swept — the module survives, the register does not |
| `fail-not-instantiated` | rc 1 | the instantiation removed from the padring wrapper while the module definition is still elaborated — an unreferenced module left in the netlist is not in the chip |
| `fail-pad-deleted` | rc 1 | one pad instance (`uPAD_RMII_MDC`) dropped from the padring. 34 supply pads were once silently deleted this way; the register can be perfectly intact while the ring it observes is not |
| `fail-vacuous-table` | rc 1 | the pad table regenerated against an empty padring — `boundary_length: 0`, `pads: []` — **and** every flop swept from the register. **This is the case the gate exists for.** See below |
| `fail-no-netlist` | rc 2 | none; synthesis never ran, or the build was cleaned away. Must not be a pass |
| `fail-truncated-netlist` | rc 2 | none; Genus was killed partway through `write_hdl`. The file opens, greps, and looks like a netlist |

Exit codes: **0 pass, 1 the design is wrong, 2 the run is wrong.**

### `fail-vacuous-table` — the arm that matters most

`0 cells found >= 0 expected` is true. `0/0 pads survived` is true. A gate that
reports those as a pass has measured nothing and said so in green, which is this
project's documented characteristic failure.

The check therefore asserts its expectations are **non-vacuous before it
compares anything against them**, and refuses to grade at all if
`boundary_length <= 0` or the pad list is empty.

That arm is load-bearing, and it was mutation-tested rather than asserted.
Deleting it from the check and re-grading this same fixture gives:

```
bsr mod  : present, 525 lines, 0 sequential cells
bsr inst : 1 (expected exactly 1)
bsr cells: 0 >= 0 (boundary_length from the table)
pads     : 0/0 survived

VERDICT: PASS - nanosoc_eth_chiplet_bscan is present, instantiated once,
                holds 0 sequential cells (>= 0), and all 0 pads survived
```

A green verdict over an empty register. That is what the arm buys.

### `fail-pad-deleted` also tests the *shape* of the pad match

This fixture's header comment names the pad it deleted. That is deliberate.
`scripts/bscan_syn_verdict.py` tests pad survival with a bare substring
(`p["inst"] not in src`), and a bare substring cannot tell an instantiation from
a comment mentioning the name:

```
naive `inst in src`   : 48/48 survived  -> missing []
anchored `[ \t]inst(` : 47/48 survived  -> missing ['uPAD_RMII_MDC']
```

The stanza's check uses the anchored form. This is a latent weakness in the
existing script, not an observed failure of it — Genus netlists carry almost no
comments — but the anchored form costs nothing and the fixture keeps it honest.

## `fail-no-netlist` and the word UNVERIFIED

`prove` scores a `must_fail` case on `rc != 0`; it cannot tell rc 1 from rc 2.
So this case proves only that the check **does not fall through to green** when
there is nothing to read.

The stage's real **UNVERIFIED** verdict comes from `needs_implementation:`,
which names the netlist and the pad table by the same path the check reads.
`signoff.py run` renders the stage UNVERIFIED and never reaches `check:` at all.
The check's rc 2 arm is the backstop for `--skip-needs-implementation`, and for
a file that exists but cannot be read.

UNVERIFIED blocks signoff and is not a softer FAIL: FAIL means fix the design,
UNVERIFIED means fix the run.

`fail-no-netlist` uses the `<name>.__absent__` marker, since a fixture overlay
can add files to the sandbox but cannot take the repository's away.

## ⚠ Retagging: change the fixtures in the SAME commit

Every fixture bakes the run tag into its path:

```
<case>/ASIC/eth-chiplet/build/bscan-probe/outputs/nanosoc_eth_chiplet_pads_gate.v
```

and the stanza names that same tag in `run:`, in `check:` and in
`needs_implementation:`. This is `GDS_RUN_PLAN` **G13**, and it bites in the
direction that ships: point the check at a new tag while the fixtures still say
`bscan-probe`, and every case grades a fixture-shaped hole in the sandbox that
no longer shadows anything — the pass case reads the real netlist and passes,
the fail cases read the real netlist and *also* pass, and `prove` reports a
gate that cannot fail as eight green rows.

`git mv` the fixture directories' `build/<tag>` path in the **same commit** that
repoints the stanza.
