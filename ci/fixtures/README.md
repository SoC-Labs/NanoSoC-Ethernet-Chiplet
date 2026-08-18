<!--
  ci/fixtures — evidence fixtures for `scripts/ci/signoff.py prove`
  A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.

  Copyright 2026, SoC Labs (www.soclabs.org)
-->
# `ci/fixtures` — proving the signoff checks can fail

Every `check:` block in `ci/signoff.yaml` names a `check_proof:` with a
**must-pass** fixture and one or more **must-fail** fixtures.
`scripts/ci/signoff.py prove` runs each check against each of them and fails if a
check accepts evidence it is supposed to reject, or rejects evidence it is
supposed to accept.

```bash
scripts/ci/signoff.py prove            # every check, ~2 s, no licence, no design data
scripts/ci/signoff.py prove elab-strict drc
```

## Why

The manifest already mutation-tests two *tools* — `lec-selftest` feeds the LEC
harness a one-gate mutation, `rom-selftest` puts the ROM gate through 22 cases —
and says why: *"A check that cannot fail is worth nothing, and this flow has
shipped several."* Nothing tested the manifest's own `check:` blocks, and they
had the same disease. All three of these were live, blocking gates:

| gate | defect | fixture that catches it |
|---|---|---|
| `elab-strict` | asserted `Analysis complete`, a banner HAL 22.03 never prints — the gate **could not pass** | `elab-strict/pass` |
| `lec` | its `\|Equivalent` clause matched a table row label printed on every run — the gate **could not fail** | `lec/fail-no-verdict-line` |
| `rom-gds` | exited 0 when the ROM table came back empty — *"could not read"* rendered as *"both ROMs verified"* | `rom-gds/fail-no-rom-table` |

## How a fixture is applied

A fixture is a **partial repo tree**. `prove` builds a sandbox in which every
top-level entry of the repository is symlinked, except along the paths the
fixture supplies, which become real directories holding the fixture's files. The
check then runs with its working directory at the sandbox root: it reads
`scripts/` and `ASIC/` as usual, and finds the fixture's evidence where its real
evidence would be. Nothing is written back into the repository.

This is why **a `check:` must address its evidence by repo-relative path**. An
absolute path escapes the sandbox and the check silently reads real, unrelated
evidence — which looks like a passing proof and is not one.

Two directives, because an overlay can add files but cannot take the repo's away:

| marker | effect |
|---|---|
| `<name>.__absent__` | the path `<name>` must NOT exist in the sandbox — proves a check's *missing evidence* arm |
| `.__exclusive__` | nothing from the repo is symlinked into this directory, so the fixture is the only thing in it |

`.__exclusive__` matters wherever a check **globs** instead of naming a file.
`drc` takes `sorted(*.drc.summary)[0]`, so on srv03335 — where a real `drc_run`
exists — the repository's own summary would leak into the fixture directory and
decide the case. A proof that behaves differently on the machine that does the
real signoff is not a proof.

## What these fixtures do NOT prove

**They are hand-written excerpts, not captures.** They prove that a check's logic
*discriminates* — that it answers differently for two shapes of evidence. They do
**not** prove that either shape is what the tool actually emits.

The consequence is specific and worth stating plainly: a tool upgrade that
changes its wording will leave `prove` green while the real gate goes blind,
because the fixture will have drifted alongside the check rather than against it.
`prove` cannot detect that. Only re-deriving a fixture from a real log can.

**So: whenever a real log is to hand, replace the excerpt with a trimmed extract
of it and note the provenance below.** That converts a fixture from "what we
believe the tool prints" into evidence.

### Provenance, and where the risk is concentrated

| fixture set | derived from | confidence |
|---|---|---|
| `chip-boundary/` | `pass` is a **verbatim capture** of `scripts/check_chip_boundary.py` (2026-08-17, 111 ports / 23 pad cells). The failure arms use that script's own `print(...)` strings, read out of the source | high |
| `lint/` | **real Verilator 4.028 captures** from `build/lint/passes/` (2026-08-17). `fail-nonwaived-finding` is the untouched real WRAPPER log carrying the live `PINMISSING link_clk_div_ratio_i`; `fail-pass-did-not-run` is a real `--top-module ... was not found` capture; `pass` is that same real log with its one non-waived stanza removed | high — captures, not excerpts |
| `elab/` | trimmed extract of the real 155 kB `build/elab/elab.log` (VCS 2022.06-SP2); `fail-vcs-error` is a **real VCS failure captured on purpose** by elaborating a module with a missing child | high |
| `regress/` | **real cocotb `results.xml` captures**: `fail-skipped-tests` is the untouched 2026-08-08 file (5 testcases, 4 `<skipped/>`), `fail-failure-element` a real failing run of 2026-08-17 | high |
| `elab-strict/` | the documented behaviour of HAL 22.03 in `verif/elab_strict/run.sh`, plus direct measurement of three real HAL logs on this host (see the correction below) | medium — see `pass`, whose tally shape is wrong |
| `drc/` | **rebuilt 2026-08-17 from 24 real Calibre v2023.1 summaries** under `ASIC/genus-innovus/calibre_runs/` (see the correction below) | high |
| `rom-content/`, `rom-gds/`, `rom-selftest/` | the row format of `make -C ASIC -f common.mk rom-vars`, checked against its real output; the JSON keys the check actually reads | **interface high, values synthetic — and the values are now known to be wrong in two places, see below** |
| `lec/`, `lec-pnr/`, `lec-selftest/` | **RE-DERIVED 2026-08-18 from real Conformal 22.10-s200 transcripts** — `ASIC/genus-innovus/logs/lec_selftest_{equivalent,nonequivalent,extra_state}.log`, one per direction, left by `make lec-selftest` | high — captures, one labelled exception |
| `ir-drop/` | **cut down from the real artefacts of the fp1505 rail run** (Voltus 21.11 under Innovus, 2026-08-17): the `.iv` header and row format, both `*.main.rpt` summaries and the per-rail table of the implementation run's own `imp_power.rep` are the tool's own bytes | high — captures, with two documented edits, below |
| `ir-drop-selftest/` | `pass` supplies **no file at all**, so the positive control is the real battery; the three failure arms are stubs that print a tally shape and nothing else | high — the stubs are the fixture's whole subject |

#### Two edits in `ir-drop/`, stated because they are the only places the bytes are not the tool's

1. **`pass` is scaled.** The design as it stands does not pass its own mean-collapse
   budget, so a must-pass fixture built from unmodified rows would prove that the
   check rejects good evidence rather than that it accepts it. The per-instance
   values are scaled by 0.62 and **both `*.main.rpt` summaries are rewritten to
   match**, because otherwise `parity.parser_vs_tool` fires and the case would pass
   for the wrong reason. The J/Jmax field is also filled in, so the fixture is not
   quietly relying on `--tier report` to hide an unmeasured EM criterion.
2. **Every case is truncated to 3,000 rows** — the worst 1,200 plus a seeded
   uniform sample of the rest, so the distribution keeps its shape and `p99` and
   the mean stay meaningful. `db.insts_total` in each census is scaled to hold the
   real coverage fraction, so `coverage.instances` is testing what it says.

`fail-disconnected-instances` needed no invention at all: its 60 `NA` rows are
real instances from the real run, which is also the defect the stage found.

### Corrections made on 2026-08-17, and what they say about the method

Three of the rows above used to claim more than the evidence supported. Each was
found by comparing a fixture against real tool output rather than against its
own check — which is the only comparison that can find this class of defect.

**`drc/` was rated "high" on a false measurement.** The old note read *"`M6.DN.1`
saturating at 1000 is a measured value from the 2026-08-10 baseline"*. It is
not: `M6.DN.1` is a **density** check, Calibre reports one merged result for it,
and across every real summary on this host it reads `TOTAL Result Count = 1` —
never 1000. `drc_census.py`'s own docstring says so, about the same baseline.
The fixture had picked the one rulecheck name that provably *cannot* saturate.
The checks that really do saturate here are `DM9.W.1`/`DM9.S.1` (`drc_filled`),
`M1..M6.A.1`, `LOGO.S.1`/`LOGO.R.4` and `CENSUS.*`, so `fail-saturated-cap` now
uses `DM9.W.1`/`DM9.S.1` with the accompanying `Maximum result count of 1000
exceeded in DRC RuleCheck …` lines that real Calibre emits alongside them.

Two more shape errors went with it. Every fixture carried a section header
`--- RULECHECK RESULTS STATISTICS (BY RULECHECK)`, a string that occurs **0
times in 24 real summaries** — the real header has no suffix. And every result
line had one count where real Calibre prints two (`= 7    (252)`, result count
then vertex count). Both are fixed.

**`drc/pass` proved nothing about the exemption it exists to permit.** It listed
three rulechecks all at zero and an *empty* BY CELL section, so the three-way
`owner()` split — design vs io-pad-abstract vs vendor-memory, the split that
keeps ~697 real vendor results out of the gated bucket — had no test at all.
Widening `MEMORY_PREFIXES` to swallow a design cell would not have moved
`prove`. It now carries a real `PAD70GU` and a real `rf_16kCNTRL` cell row, so
PASS means "these were exempted", not "there was nothing there".

**`rom-selftest/pass` asserted a count the tool does not print.** The fixture
said `SELFTEST: 22 passed`, this manifest's description said 22, and the real
selftest runs **25** cases (23 `expect_fail` + 2 `expect_pass` in
`ROM_SELFTEST_PY`). Nothing noticed because the check matched `2[0-9]` — a
decade-wide window, so the case list could lose five cases, a fifth of the
proof, with the blocking gate still green. The check now pins 25 exactly, and
`fail-one-case-dropped` (24 of 25) is the fixture the old regex accepted.

**`elab-strict/pass` has the wrong tally shape, and this is not yet fixed.**
Guard 3 asserts a rule-tally summary block. The fixture prints one code per
line; real HAL prints them **four to a line in padded columns**, grouped under
severity headers (` Warnings : (35413)`, ` Notes    : (8326)`), and follows them
with `Analysis complete.` — measured on the only real *completed* HAL log on
this host, `build/lint/full/hal/xrun_hal.log` (34 MB, 78,742 `^halstruct:`
lines, 32 tally lines). The guard's regex happens to match the real shape via
its first column only, so anyone tightening it to anchor at end-of-line would
keep `prove` green and blind the real gate.

Note also what that log does to this manifest's stated reasoning. The
`elab-strict` comment says HAL 22.03 *"NEVER PRINTS"* `Analysis complete` — but
a completed run of the same build (`xrun 22.03-s005`) prints it exactly once,
immediately after the tally block. The elab-strict invocation differs
(`-halargs -BB_NONSYNTH`, different flist), so this does not refute the claim
for that mode; it does mean the claim is unverified for it, and that a stronger
completion marker may exist. **No completed elab-strict log exists on this host
to settle it** — every one measured was aborted or killed.

**`lec/` was the declared weak spot, and re-deriving it found the defect this
file predicted — pointing the other way.** The note here used to read *"inference
only — no Conformal transcript was available"*, and asked whoever produced the
first real `logs/lec.log` to rebuild the family. `make lec-selftest` had by then
left three real transcripts on disk, one per direction. Measured across all three:

| marker | equivalent | nonequivalent | extra_state |
|---|---|---|---|
| `Different Key Points` | 0 | 0 | 0 |
| `Abort Points` | 0 | 0 | 0 |
| `Unknown Key Points` | 0 | 0 | 0 |
| `Compare Results:  PASS` | **1** | 0 | 0 |

The fear recorded here — that those three strings are row labels printed on every
run, so the gate **could never pass** — is refuted: the passing transcript
contains none of them and does carry the verdict line. But the opposite was true
and nobody had asked. **Conformal emits none of those three strings in either
direction, so the entire negative-grep clause was dead code**: it could never
fire, on any real log. Only the `Compare Results: PASS` clause was doing work —
the same shape as the `|Equivalent` clause that was removed for being vacuous,
one line below it, undetected because `fail-different-key-points` was hand-written
to contain a string the tool does not print. A fixture invented alongside its
check will agree with it forever.

What Conformal really prints is a verdict line plus a point census
(`6. Compare Results: PASS` / `FAIL:NONEQ`, and `N Non-equivalent / Abort /
Not-compared point(s) reported`), and that is what the three LEC gates now read.
`lec/fail-abort-points` is the one fixture in these families **not** taken from a
log, and is labelled as such in the manifest: it asserts PASS over a non-zero
abort census, a shape Conformal does not currently produce, so that a future
version which did could not walk through.

### `lec/` re-derived AGAIN, 2026-08-18 — the family was proving the wrong half

The re-derivation above fixed *what strings* the gate reads. It did not ask
*which comparison* it was reading them from, and that turned out to be the
larger hole.

Genus's generated dofile performs **two** comparisons, not one — compare #1 is
`fv_map` vs `<block>_gate.v`, then `reset`, then compare #2 is **RTL** vs
`fv_map` — a structure the toolkit's own `flow/verify/lec_syn_rewrite.tcl`
documents and refuses to run without. The gate `re.search`ed the **first**
`Compare Results:` line, which is compare #1's, and every fixture in this family
was a **single-comparison extract**, so the fixtures agreed with the check about
a shape neither of them was measuring. On the real 815 KB transcript that meant
`PASS` at **58,672** compare points where the `gate` and `pnr` legs report
**61,674**: a different population, and no RTL→netlist proof at all.

Two things follow for anyone re-deriving this family again:

* **No real *passing* `syn` transcript exists to derive `lec/pass` from.**
  `grep -rl 'LEC-VERDICT: tag=syn' --include=verdict.txt .` returns nothing in
  this repository or in any archived run — the leg has never completed anywhere.
  `lec/pass` is therefore a construction and says so in its own first lines; its
  section grammar and its `LEC-VERDICT` block are copied verbatim from the real
  `logs/lec_syn.log` (compare #1) and `logs/lec_gate.log` (the appended verdict
  block), and only the point counts are small. Inventing large counts would make
  a construction look like a measurement.
* **`lec/fail-truncated-rtl-half` is real bytes** — three verbatim slices of the
  transcript that made the gate green, joined by the `...` elisions this
  directory already uses. It is the defect of record and nothing may make it
  green. `lec/fail-wrong-leg` is its complement: a complete, healthy, *passing*
  transcript of the **wrong** comparison, which must still be refused.

The paragraph further down that calls `lec/` "the weak one" and asks for
re-derivation from "the first real `logs/lec.log`" is **superseded**: the
bare-presence greps it worries about were removed on 2026-08-17, and the real
transcript it asks for arrived and is what produced this section.

One more, recorded because it wasted an hour and will waste someone else's:
`verif/elab_strict/build/xrun_hal.log` and `verif/g2_soc_pair/results.xml` are
**rewritten by concurrent runs**. Two measurements of "the same" file minutes
apart disagreed by 284,905 `halstruct` lines and looked exactly like a
`grep`-compatibility bug. Snapshot before measuring, and re-check the mtime.

**`lec/` is the weak one and should be re-derived from the first real
`logs/lec.log` anyone produces.** The check fails on the mere *presence* of
`Different Key Points`, `Abort Points` or `Unknown Key Points`. If Conformal
prints those as row labels in its compare-summary table — as it demonstrably does
for `Equivalent`, which is the whole reason that clause was removed — then the
`lec` gate **can never pass**, and `lec/pass` is wrong rather than the check.
Note that `ASIC/genus-innovus/scripts/lec/run_lec.sh`, the more mature harness,
deliberately avoids bare-presence greps and uses anchored markers plus a
by-name comparison instead. That is a hint, not a measurement.

## A must-fail fixture should trip exactly ONE clause

`prove` only asks whether a check said no. It does not ask *which guard* said
no, so a fixture that violates three conditions at once passes its case while
pinning none of them — delete two of the three guards and it still goes red.

Every fixture here has been checked against that. The discrimination matrix for
`lint` is representative:

| fixture | logs present | hard `%Error` | non-waived finding | bug-wiring UNOPTFLAT |
|---|---|---|---|---|
| `pass` | 6 | 0 | 0 | 1 |
| `fail-wrapper-skipped` | **5** | 0 | 0 | 1 |
| `fail-pass-did-not-run` | 6 | **1** | 0 | 1 |
| `fail-nonwaived-finding` | 6 | 0 | **1** | 1 |
| `fail-sanity-blind` | 6 | 0 | 0 | **0** |
| `fail-no-logs` | **0** | 0 | 0 | 0 |

One bold cell per row: each case isolates one guard. Where the tool makes that
impossible the overlap is stated rather than hidden — `chip-boundary`'s
`fail-pad-ring-mismatch` also lacks the final OK line, because the real script
exits before printing it, and `fail-zero-ports` trips both vacuity clauses
because a run that classified nothing also read no pads. In those two the
isolating case is a separate fixture (`fail-truncated`).

`elab-strict` is the worked example of guards that genuinely layer: guard 1
(aborted), guard 2 (rules never started) and guard 3 (rules cut off) each own a
distinct arm, and `fail-aborted-after-halstruct` exists precisely because it is
the only shape where guard 1 fires alone.

## Adding a check

`signoff.py lint` fails any stage that has a `check:` and no `check_proof:`, so a
new gate cannot be added without one. Keep fixtures **small** — these are
excerpts of the handful of lines a check reads, never copies of a 43 MB log.
