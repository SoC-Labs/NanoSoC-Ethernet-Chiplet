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
| `elab-strict/` | the documented behaviour of HAL 22.03 in `verif/elab_strict/run.sh`, whose comments record both the absent `Analysis complete` banner and the `^halstruct:` line count (60,493) from a real 43 MB run | high — the runner was written against the real log |
| `drc/` | the Calibre summary grammar parsed by `scripts/ci/drc_census.py`, which was itself written against real runs (`M6.DN.1` saturating at 1000 is a measured value from the 2026-08-10 baseline) | high |
| `rom-content/`, `rom-gds/`, `rom-selftest/` | the row format of `make -C ASIC -f common.mk rom-vars`, checked against its real output; the JSON keys the check actually reads | high for the interface, synthetic for the values |
| `lec/` | **inference only — no Conformal transcript was available** | **low, see below** |

**`lec/` is the weak one and should be re-derived from the first real
`logs/lec.log` anyone produces.** The check fails on the mere *presence* of
`Different Key Points`, `Abort Points` or `Unknown Key Points`. If Conformal
prints those as row labels in its compare-summary table — as it demonstrably does
for `Equivalent`, which is the whole reason that clause was removed — then the
`lec` gate **can never pass**, and `lec/pass` is wrong rather than the check.
Note that `ASIC/genus-innovus/scripts/lec/run_lec.sh`, the more mature harness,
deliberately avoids bare-presence greps and uses anchored markers plus a
by-name comparison instead. That is a hint, not a measurement.

## Adding a check

`signoff.py lint` fails any stage that has a `check:` and no `check_proof:`, so a
new gate cannot be added without one. Keep fixtures **small** — these are
excerpts of the handful of lines a check reads, never copies of a 43 MB log.
