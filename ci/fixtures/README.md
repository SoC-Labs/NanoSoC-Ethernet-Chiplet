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

Three directives. The first two exist because an overlay can add files but
cannot take the repo's away; the third exists because there are filenames this
repository is not allowed to track.

| marker | effect |
|---|---|
| `<name>.__absent__` | the path `<name>` must NOT exist in the sandbox — proves a check's *missing evidence* arm |
| `.__exclusive__` | nothing from the repo is symlinked into this directory, so the fixture is the only thing in it |
| `<name>.__fixture__.txt` | the file is staged in the sandbox as `<name>`, suffix stripped — for a `<name>` the vendor guard refuses to let anybody track |

`.__exclusive__` matters wherever a check **globs** instead of naming a file.
`drc` takes `sorted(*.drc.summary)[0]`, so on srv03335 — where a real `drc_run`
exists — the repository's own summary would leak into the fixture directory and
decide the case. A proof that behaves differently on the machine that does the
real signoff is not a proof.

### `.__fixture__.txt` — staging a filename the repository may not contain

**The collision.** Three gap probes search the PDK **by extension**:

    find ${TSMC_65_HOME} -maxdepth 6 -size +1k -name 'tcbn65lp*.cdl' ... | grep -q .

so the refuting half of their fixture has to contain a file whose name ends
`.cdl` — the probe matches on the name and nothing else. The pre-commit vendor
guard (`ASIC/asic-toolkit/ci/check-vendor-collateral.sh`, rule `file.ext`)
refuses any tracked file with that extension, and refuses it **without reading
it**: *"a tracked .cdl - foundry collateral by its nature"*. That rule is
extension-keyed **on purpose**, precisely so that *"but this one is synthetic,
read its first line"* — which is exactly what these fixtures say, in their first
line — is not an argument it can be talked out of. A guard that can be argued
with by inspecting content is a guard that eventually lets content through.

Both positions are right and **neither is bent**. The suffix moves the collision
from **commit time** to **materialisation time**:

| | on disk / in git | in the prove sandbox |
|---|---|---|
| refuting CDL | `.../cdl/tcbn65lp.cdl.__fixture__.txt` | `.../cdl/tcbn65lp.cdl` |

The tracked tree contains no `.cdl`, `.lef`, `.lib` or `.sp`; the guard stays
exactly as strict; the probe still finds the name it greps for. **Measured
2026-09-11**: `vendor.untracked.file.ext` went from **14 finding(s)** to the
gate not firing at all, with no allowlist entry, no waiver and no change to the
guard.

**Adding one is the whole procedure.** Name the file
`<the name the check reads>.__fixture__.txt` and stop. There is nothing to
declare — not in `ci/signoff.yaml`, not here. `prove` strips it. It composes
with the other two directives (`x.cdl.__fixture__.txt.__absent__` declares
`x.cdl` absent; `.__absent__` is stripped first, being the outer suffix), and
it is not limited to the PDK fixtures — any fixture that must stage a name the
guard forbids uses it.

**The `.txt` is load-bearing; do not shorten the suffix to `.__fixture__`.**
`file.ext` keys on the *last* extension, so any non-collateral tail would dodge
it — but the guard's VALUE rules (`value.lef`, `value.lefwin`, `value.map`,
`value.libtag`, `ident`, `path`, `licence`) read only files inside a text corpus
that is *also* keyed by extension, and `.cdl`, `.lef`, `.lib` and `.sp` are all
in it. A basename ending `.__fixture__` matches none of those globs and drops
out of the value scan entirely — which would trade an honest block for a silent
hole, one in which these fixtures could later acquire real foundry numbers with
no rule left looking at them. **Measured, not reasoned**: the guard's own corpus
line reads

| suffix | files scanned for values |
|---|---|
| `.__fixture__.txt` | **909** |
| `.__fixture__` | **895** — all 14 fixture files silently outside the value rules |

So only the rule about a file's KIND is sidestepped. Every rule about its
CONTENT still reads these files, which is the half that matters for a public
repository whose fixtures are *about* foundry collateral.

### A rename that quietly did nothing would be worse than the block it lifts

If the strip fails to happen, the file sits in the sandbox under its tracked
name, `find ... -name 'tcbn65lp*.cdl'` matches nothing and exits **1** — and 1
is exactly the exit code `gap:still-real` is waiting for. The `refuted` half
would go BROKEN, but the `still-real` half would print `ok` while measuring an
empty directory, and `lint` would go on reporting "still real" for a reason that
has nothing to do with the PDK. **A permanent false verdict is worse than an
uncommitted fixture**, so the mechanism is not allowed to no-op quietly. Three
layers, in `scripts/ci/signoff.py`:

1. **`_assert_materialised()`** — after the overlay, every `.__fixture__.txt`
   file must exist in the sandbox under its stripped name, must not have come
   back under its tracked name, and no two fixture files may claim one sandbox
   name (which `shutil.copy2` would otherwise resolve by silent overwrite).
   Failure raises `FixtureError`, naming the file.
2. **The arming block** — `prove` refuses to run **any** case until it has
   staged an invented specimen (`specimen_arming.cdl.__fixture__.txt`), watched
   it materialise as `specimen_arming.cdl`, **and** watched `_assert_materialised`
   *fire* on a sandbox where the strip was skipped. A guard nobody has watched
   fail is not known to work. Same doctrine, and same shape, as the vendor
   guard's own SECTION 1: *"every rule must fire on an invented specimen"* before
   the script is entitled to say anything about the repository. It prints one
   line and exits **2** — a broken run, not a failed gate — if either half is
   inert.
3. **`UNSTAGED`** — a per-case verdict distinct from BROKEN, counted as a
   problem, for a fixture that could not be staged. "The check was never asked
   the question" is not "the check answered no".

**Measured, by mutation, 2026-09-11** — the counterfactual, with the strip, the
assert and the arming all disabled:

    lvs              gap:still-real   ok       rc=1
    lvs              gap:refuted      BROKEN   rc=1, wanted 0
    dynamic-ir-drop  gap:still-real   ok       rc=1
    dynamic-ir-drop  gap:refuted      BROKEN   rc=1, wanted 0

Both `still-real` halves read **ok** over sandboxes holding nothing but
`tcbn65lp.cdl.__fixture__.txt` — green, and measuring nothing. With the guard in
place, disabling the strip and disabling the assert each stop `prove` dead at
the arming line with the file named. That is the difference the three layers buy.

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
| `sta-signoff/`, `sta-binding/` | **cut down from the two real Tempus 21.11 report sets on this host** (`ASIC/sta/work/gdsrun-20260826-rc1/reports/`, 2026-08-26, and the 2026-08-18 run). The `sta_manifest.txt` key set, the `Signoff Settings:` banner and the coverage-table column layout are the tool's own; `fail-untested-checks` is the current candidate's real coverage table with four rows kept. Three edits, all stated below | high — captures, three documented edits |
| `gap-sta-hold-coverage/` | the artefact the `report_analysis_coverage -check_type hold` step would leave behind, and its absence. Two files, one directory marker each | high — the fixture's subject is presence vs absence |

#### Three edits in `sta-signoff/` and `sta-binding/`, stated because they are the only places the bytes are not the tool's

1. **`sta_db` names a synthetic root.** The real manifests record an absolute
   path under one engineer's home directory. A fixture carrying that would make
   `sta_binding.py`'s realpath arm compare a synthetic path against *this*
   machine's build tree, so the case would pass or fail depending on which host
   ran it. The fixtures use an obviously-invented root instead, and each one
   carries `.__exclusive__` on `ASIC/eth-chiplet/build/<tag>/` so the real build
   tree is not visible in the sandbox at all. The realpath arm is therefore
   **not** proved by these fixtures — it is proved by `sta_binding.py --selftest`,
   which builds real directories in a temporary tree.

2. **`pass` closes timing, and the real design does not.** The current candidate
   fails on setup (WNS -0.049, 4 endpoints), hold (WNS -0.053, 394) and coverage
   (57,955 untested). A must-pass fixture built from unmodified rows would prove
   that the check rejects good evidence rather than that it accepts it. The WNS
   and FEP fields of `pass` are the only numbers changed; `fail-violating`
   carries the candidate's real setup row verbatim.

3. **`clock_count` tracks `ASIC/sta/sta_policy.json`, not a captured run.** The
   fixtures carry 52 because that is the committed tripwire; a fixture written to
   any other number would fail the must-pass case for a reason unrelated to the
   arm under test. The tripwire was re-pinned from 66 to 52 on 2026-08-26 after
   the 33-vs-66 question was resolved (`get_db clocks` returns one object per
   active analysis view, and this MMMC activates two, so the database number is
   always twice the SDC's). **If that policy value moves again, these fixtures
   must move with it** — `signoff.py prove` will go red on `sta-signoff/pass`
   the moment they disagree, which is the intended coupling and not a defect.

`fail-wrong-build` needed no invention: it is `pass` with the build tag replaced
by the one all six historical runs actually read. It is the load-bearing case —
`sta_gate.py` grades it **clean**, and only `sta_binding.py` says no.

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

## Gap fixtures — proving a REFUTATION can succeed

`ci/signoff.yaml` declares nine `unsupported:` coverage gaps, and `signoff.py
lint` executes each one's `refuted_by:` on every invocation, reading exit 1 as
"the gap is still real". That is worth exactly as much as the probe's ability to
have exited 0. A refutation attempt nobody has shown capable of SUCCEEDING is
the same shape as a gate that cannot fail, wearing the opposite label — and this
pipeline has already shipped one: `sta-signoff` declared "No Tempus or PrimeTime
installed" behind `command -v tempus`, which tests PATH rather than
installation, while Tempus was installed and had run six times.

So a gap probe gets the same treatment as a `check:`, by convention rather than
by manifest declaration (`GAP_KEYS` stays `{id, reason, refuted_by}`):

| directory | probe must exit |
|---|---|
| `ci/fixtures/gap-<id>/still-real/` | **1** — the gap is real over this evidence |
| `ci/fixtures/gap-<id>/refuted/` | **0** — the gap has closed over this evidence |

**BEFORE 2026-09-09 EIGHT OF THE NINE HAD NO FIXTURE.** `prove` reported them
`NO FIXTURE ... executed by lint but has never been shown to discriminate` and
did not count them as problems. They are precisely the rows that stay
NOT-MEASURED forever in a graded evidence report, so "the refutation was
attempted and failed" was carrying the entire weight of eight permanent
exemptions. All nine now have both halves; `prove` reports 9 gap probe(s).

### The refuting artefact, per gap

The question a gap fixture answers is not "how would this be worded differently"
but **what concrete thing arriving would make the claim false**. Four of these
are about collateral this site does not have, and the answer is that collateral
appearing.

| gap | what actually refutes it | staged as |
|---|---|---|
| `d2d-tx-clock-boundary-untimed` | the SDC stops declaring the D2D transmit group asynchronous — Option A folds it into `clk`, or Option B gives it its own pad | two `constraints.sdc` excerpts, the second with the TX clock moved into `_sys_grp` and per-path exceptions in place of the group cut |
| `sta-hold-coverage` | `report_analysis_coverage -check_type hold` stops raising TCLCMD-1056 and writes a report | *(pre-existing)* presence vs absence of `analysis_coverage_hold.rpt` |
| `antenna-signoff` | a stage **in this manifest** runs the foundry deck. Not a tool, not a licence, not a deck — all three are already here | two manifests, the second carrying an `antenna-foundry-deck` stage |
| `metal-density-fill` | `EVR_METAL_FILL` stops defaulting to 0 | two excerpts of `4b_pnr_route_eval.tcl` differing in one digit |
| `gds-completeness` | a `*_BE` package directory appears in the PDK — the Back-End collateral whose absence empties 424 cell masters | synthetic PDK stand-in trees, the second with a `..._BE` directory |
| `lvs` | transistor-level CDL over 1 kB for the standard-cell, IO or bond-pad libraries appears | synthetic PDK stand-in trees, the second with a `tcbn65lp*.cdl` — tracked as `tcbn65lp.cdl.__fixture__.txt`, see the suffix convention above |
| `dynamic-ir-drop` | cell SPICE or cell GDS appears, so a cell-accurate power grid library becomes buildable | synthetic PDK stand-in trees, the second with a `tcbn65lp*.sp` — tracked as `tcbn65lp.sp.__fixture__.txt`, see the suffix convention above |
| `io-rail-ir-drop` | the **generated** CPF — the one Innovus reads — declares VDDIO/VSSIO | two `*_gate1.cpf` files differing in one line at column 1 |
| `full-design-lint-gating` | a stage's `run:` invokes `verif/lint/full/run.sh` | two manifests, the second carrying a `lint-full` stage |

### Provenance and confidence

| fixture set | derived from | confidence |
|---|---|---|
| `gap-d2d-tx-clock-boundary-untimed/` | an excerpt of the real `ASIC/genus-innovus/inputs/constraints.sdc` clock-group block (the `set_clock_groups` call and the `_rx_grp`/`_tx_grp`/`_sys_grp` construction are the file's own text); the `refuted` half is that block with Option A applied, which has never been run | high for still-real, **medium for refuted — Option A is a design change nobody has made, so its shape is inferred from `docs/asic/C2_TRANSMIT_GROUP_OPTIONS.md`, not captured** |
| `gap-antenna-signoff/`, `gap-full-design-lint-gating/` | hand-written miniature manifests, same method as the pre-existing `gap-sta-signoff/`. The probes read only `stages[].id` and `stages[].run`, so the rest is scaffolding | high — the subject is the manifest's own schema, not a tool's output |
| `gap-metal-density-fill/` | an excerpt of the real `4b_pnr_route_eval.tcl` option block (lines 128-146); the `opt EVR_METAL_FILL` line and the `set_metal_fill`/`add_metal_fill` call site are the file's own text | high |
| `gap-io-rail-ir-drop/` | modelled on the shape of the real 21-line generated `*_gate1.cpf` (`set_cpf_version` / `set_design` / `create_power_domain` / `create_ground_nets` / `create_power_nets`). **Values synthetic** | medium-high — interface captured, values invented |
| `gap-gds-completeness/`, `gap-lvs/`, `gap-dynamic-ir-drop/` | **wholly synthetic, deliberately and permanently.** Marker files and invented netlists; device models named `SYNTH_NMOS`/`SYNTH_PMOS` and cells `CELL_SYNTHETIC_*`, corresponding to nothing in any process or library | the shape is the subject; see the two limits below |

**NO VENDOR COLLATERAL, EVER, IN THESE THREE.** This is a public repository and
these three gaps are *about* vendor collateral. The library prefixes in the
filenames are the ones already written in `ci/signoff.yaml`; nothing else comes
from a PDK. If real collateral ever lands on this site the gap closes by `lint`
going red against the real PDK — **never** by a fixture acquiring real content.

**`gap-lvs/` and `gap-dynamic-ir-drop/` are tracked under the
`.__fixture__.txt` suffix**, documented above: their probes search by extension,
so their evidence files have to be named `*.cdl`, `*.lef`, `*.lib` and `*.sp`,
and the vendor guard refuses to let any of those four be tracked whatever they
contain. The suffix is stripped when `prove` stages the sandbox. Nothing else
about either fixture changes — same bytes, same directory depths, same decoys.

### Two limits these three fixtures do not close

**1. They pin the name, size, type and depth clauses. They cannot pin the
PLACE.** All three probes are `find ${TSMC_65_HOME} ...`, and `prove` runs them
with `TSMC_65_HOME=.` inside the sandbox (`_sandbox_env()` in
`scripts/ci/signoff.py`) so the fixture is authoritative on every host —
including srv03335, where the real PDK is installed and would otherwise decide
the case. The cost is that nothing proves the probe looks at the right root.
A real PDK root is not stageable here, and that is the residual risk.

**2. An unset `${TSMC_65_HOME}` makes those probes search the working tree, and
`lint` calls the result "still real".** Empty expansion, GNU `find` falls back
to `.`, and on any host with no PDK the verdict is a statement about this
repository offered as a statement about the PDK. **This bit on the day the
fixtures were written**: the first cut put `gap-dynamic-ir-drop`'s synthetic
`.sp` at repo depth 7, inside that probe's `-maxdepth 8`, and lint reported
`dynamic-ir-drop STALE — refuted_by SUCCEEDED` over a gap that is wide open. The
three PDK fixtures are now held clear by DEPTH, per-gap arithmetic recorded in
each `FIXTURE_NOTE.md`:

| gap | probe `-maxdepth` | depth in the sandbox | depth from the repo root |
|---|---|---|---|
| `gap-gds-completeness` | 4 | **3** (inside) | **7** (outside) |
| `gap-lvs` | 6 | **4** (inside) | **8** (outside) |
| `gap-dynamic-ir-drop` | 8 | **6** (inside) | **10** (outside) |

Moving or adding anything under `pdk-stand-in/` means redoing that arithmetic
and running **both** `prove` and `lint` — `prove` alone cannot see this failure,
because it never runs the probe from the repository root.

Since 2026-09-11 there is a second, independent reason those two fixtures cannot
refute their own gaps from the repository root: **their tracked names no longer
match the probes at all** — `tcbn65lp.cdl.__fixture__.txt` is not
`-name 'tcbn65lp*.cdl'`. **That does not retire the depth rule.**
`gap-gds-completeness` refutes on a DIRECTORY name (`*_BE`), which carries no
suffix and never will, so depth is the only thing holding it clear; and the next
fixture written may not need the suffix either. Belt and braces, both kept. The real fix is a
probe that exits 2 (UNVERIFIABLE) when the variable is unset instead of silently
searching the tree; the replacement text is in
`ci/fixtures/PROPOSED_GAP_PROBES.yaml`, unapplied because `ci/signoff.yaml` is
written by other sessions.

### Probes that discriminate but measure a proxy

Recorded here rather than silently strengthened: tightening a probe is a
decision about what closing the gap *means*, and belongs to whoever owns the
entry. All four are written up with replacement text in
`ci/fixtures/PROPOSED_GAP_PROBES.yaml`.

* **`d2d-tx-clock-boundary-untimed` reports the gap CLOSED if `constraints.sdc`
  is missing.** `! grep -qF ... file` maps grep's error status 2 onto 0 exactly
  as it maps 1 onto 0, so an unreadable file prints `STALE — refuted_by
  SUCCEEDED`. Measured. The `prove` harness offers two cases per gap and both
  must supply the file, so no fixture here can catch it.
* **`metal-density-fill` tests a default in a script; the claim is about a
  stream.** A run invoked with `-EVR_METAL_FILL 1` fills a stream while the
  probe still exits 1; flipping the default refutes the gap before any filled
  stream exists.
* **`gds-completeness` tests the root cause, not the consequence.** BE packages
  arriving does not by itself put transistors in the stream — the design would
  have to be re-streamed. Over-eager in the STALE direction, which a human reads.
* **`antenna-signoff` and `full-design-lint-gating` test a NAME, not a
  behaviour**, and a crash in either reads as "still real". `s['id']` raises
  KeyError on a stage with no id; `s.get('run','')` raises TypeError on `run:`
  written with no value; CPython exits 1 on both, and 1 is the one status `lint`
  reads as "asked, and not refuted". Measured against a three-line malformed
  manifest.
* **`dynamic-ir-drop`'s reason makes two claims and the probe tests one.** The
  collateral half is probed; *"no switching activity anywhere in this flow — no
  SAIF, no VCD"* is not, so cell SPICE arriving would refute the whole entry
  while the activity half stayed true.

### Adding a gap fixture

`prove` finds them by convention — no manifest entry, so nothing forces one to
exist. Build `still-real/` from the site AS IT IS (never a synthetic
impossibility; the still-real half is the one an auditor will read as a
description of this project), build `refuted/` by changing **one** thing, and
put near-miss decoys in both so the pair isolates a single clause. Then run
`signoff.py prove` **and** `signoff.py lint`.
