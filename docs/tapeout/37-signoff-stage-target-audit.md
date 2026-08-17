# 37 — Signoff stage/target audit: what `ci/signoff.yaml` actually invokes

Audited 2026-08-17 against `HEAD=de8f985` (first run at `31c6af1`; re-confirmed at
`de8f985`, finding unchanged). Every make target named by a stage in
`ci/signoff.yaml`, resolved and probed for existence.

**Result: 14 stages, 17 make-target invocations, exactly one undefined —
`rom-gds` → `romlibs-gds-check`, absent at HEAD.**

---

## Read this first

**NO PHYSICAL GATE IS MEASURING ANYTHING TODAY.**

Four of the six physical-phase stages short-circuit before they run. `signoff.py`
evaluates each stage's `needs_implementation:` list *before* `run:`
(`scripts/ci/signoff.py:373-386`), and where a declared artefact is absent the
stage is recorded UNVERIFIED and skipped. Measured now:

| stage | declared artefact | present? |
|---|---|---|
| `rom-gds` | `ASIC/genus-innovus/outputs/nanosoc_eth_chiplet_pads.gds` | **absent** |
| `lec` | `ASIC/genus-innovus/work/lec.dofile` | **absent** |
| `lec` | `ASIC/genus-innovus/work/fv` | present |
| `lec-pnr` | `…/outputs/nanosoc_eth_chiplet_pads_gate_power.v` | **absent** |
| `lec-pnr` | `…/outputs/nanosoc_eth_chiplet_pads_pnr.v` | **absent** |
| `drc` | `…/outputs/nanosoc_eth_chiplet_pads.gds` | **absent** |

This is not a false green — UNVERIFIED sets `passed: false` and a `block` stage
still fails the pipeline (`signoff.py:382-385`). The manifest is honest about it.
But it means **`gate1` will be the first run in which `rom-gds`, `lec`, `lec-pnr`
and `drc` execute at all**, and their first execution is not the moment to
discover a broken invocation. That is what this audit is for.

---

## The table

Two independent probes, because they answer different questions:

* **WORKTREE** — `make -q` in the resolved directory. No recipe is ever run.
  `rc 0|1` = defined, `rc 2` + `No rule to make target` = undefined. Authoritative
  for "does this work on this disk right now".
* **HEAD** — the committed text of the makefile and its whole include chain.
  Authoritative for **CI**, which clones HEAD and never sees anyone's
  uncommitted edits.

| stage | gate | key | invokes | WORKTREE | HEAD |
|---|---|---|---|---|---|
| `chip-boundary` | block | run | `make chip-boundary` | defined | defined |
| `lint` | block | run | `make lint` | defined | defined |
| `elab` | block | run | `make elab` | defined | defined |
| `elab-strict` | block | run | `make elab-strict` | defined | defined |
| `cdc` | report | run | `make cdc` | defined | defined |
| `regress` | block | run | `make regress` | defined | defined |
| `rom-selftest` | block | run | `make -C ASIC -f common.mk romlibs-selftest` | defined | defined |
| `rom-selftest` | block | check | `make -C ASIC -f common.mk romlibs-selftest` | defined | defined |
| `rom-content` | block | run | `make -C ASIC/genus-innovus romlibs-check` | defined | defined |
| `rom-content` | block | check | `make -C ASIC -f common.mk rom-vars` | defined | defined |
| **`rom-gds`** | **block** | **run** | **`make -C ASIC/genus-innovus romlibs-gds-check`** | defined | **UNDEFINED** |
| `rom-gds` | block | check | `make -C ASIC -f common.mk rom-vars` | defined | defined |
| `lec` | block | run | `make -C ASIC/genus-innovus lec` | defined | defined |
| `lec-selftest` | block | run | `make -C ASIC/genus-innovus lec-selftest` | defined | defined |
| `lec-pnr` | block | run | `make asic-lec-pnr` | defined | defined |
| `lvs-preflight` | report | run | `make asic-lvs-pre` | defined | defined |
| `drc` | block | run | `make asic-drc` | defined | defined |

Two of these (`rom-vars`, twice) are invoked from inside `python3 - <<'EOF'`
heredocs as `subprocess.run(["make", "-C", "ASIC", …])` argv lists. A shell-level
scan of the YAML does not see them. They are fine, but any future sweep of this
file has to look inside the heredocs.

A related count exists: **11 of 12** distinct *block-tier* targets from `run:`
lines only. Same defect, narrower denominator — that count excludes `check:`
blocks, the heredoc calls, and the two report-tier stages.

---

## `rom-gds`: undefined at HEAD, and why it has never fired

`romlibs-gds-check` does not exist at HEAD. Measured with a control, because an
empty result from a broken probe looks identical to a true negative:

    git grep -l romlibs-gds-check HEAD -- '*Makefile' '*.mk'   ->  0 files
    git grep -l romlibs-check     HEAD -- '*Makefile' '*.mk'   ->  3 files   (control)
        ASIC/eth-chiplet/design.mk, ASIC/genus-innovus/Makefile, ASIC/rom_gate.mk

It exists **only in an uncommitted edit** to `ASIC/genus-innovus/Makefile:165`,
which also adds three internal callers (`:401`, `:498`, `:588`). So a `make -q`
in this checkout says "defined" and CI would say `No rule to make target`.

**It is not a false green, and not the `elab-strict` class.** `signoff.py:415-427`
sets FAIL on any nonzero rc and blocks, so `rc=2` would go red. The reason it has
never fired is the `needs_implementation:` short-circuit above: the legacy GDS it
declares is absent, so the stage is marked UNVERIFIED and `run:` is never reached.
**Unreachable, not silently passing** — and a hard red the moment a GDS lands at
that legacy path, which is what `gate1` is meant to produce.

The fix already exists in the parked caller-rewiring worktree (`fd3085b`): the real
extractor is `romlibs-verify-gds` in `ASIC/rom_gate.mk`, and that commit also moves
the `needs_implementation:` and `artifacts:` paths onto the toolkit's
`build/$RUN_TAG/` tree. If that lane does not land before `gate1`, `rom-gds` wants
a two-line cherry-pick, not a rewrite.

> Note the coupling: after the toolkit migration, a physical stage whose `run:` has
> moved to `ASIC/eth-chiplet` but whose `needs_implementation:` still names
> `ASIC/genus-innovus/…` would go UNVERIFIED **forever** — the legacy tree never
> gets populated again. `fd3085b` handles this. Any partial cherry-pick must move
> both halves together.

---

## `lint`: a real false-green mechanism, now fixed

`ci/signoff.yaml:41` ends its pipeline with `exit ${PIPESTATUS[0]}`. That is a
bashism, and `signoff.py` ran stage commands through `Popen(shell=True)` with no
`executable=`, i.e. `/bin/sh`. Measured on this host:

| shell | `false \| true; exit ${PIPESTATUS[0]}` | |
|---|---|---|
| `/bin/sh` → bash 4.4.20 | `rc=1` | correct |
| `bash --posix` | `rc=1` | correct |
| `/usr/bin/ksh` | **`rc=0`** | **silent pass** |

ksh has no `PIPESTATUS`, so the expansion is empty and bare `exit` takes the last
pipeline command's status — `tee` — which is always 0. A failing `make lint` would
report PASS on a `block` gate. Never live here (`/bin/sh` is bash on this host),
but one runner image away, and it fails **green**, which is the direction that
ships.

Fixed at `67a157e`: `executable="/bin/bash"` on the Popen (`signoff.py:124`). That
was the right shape of fix — it covers every stage's `run`, `pre` and `check` at
once, and six stages have `check:` blocks carrying bashisms. The `run:` line was
left as-is, which is now correct rather than merely lucky.

Risk called by f9 from static reading; shell measurement and direction from this
audit; fix and its own reproduction by 48.

---

## Method: two traps that will mis-score this audit if you redo it

**1. `make -n` is not a target-existence probe in this repo.** GNU make executes
recipe lines containing `$(MAKE)` *even under `-n`*. The legacy flow is full of
them, so on a clean tree:

    make -C ASIC/genus-innovus -n syn        rc=2
    make -C ASIC/genus-innovus -n pnr_place  rc=2
    make -C ASIC/genus-innovus -n pnr_all    rc=2

All three targets are fine. They die for real inside `cpf-patch`, which demands a
CPF that synthesis has not written yet. The toolkit side has no such prerequisite
and looks clean, so the two flows score differently for a reason unrelated to
target names. Use `make -q` — no recipe runs at all. Verified it discriminates in
both directions in both flows: `pnr_all` `rc=2` in `ASIC/eth-chiplet`,
`place`/`route`/`all` `rc=2` in `ASIC/genus-innovus`, every real target `rc=1`, and
a `definitely-not-a-target-xyz` control `rc=2` in both.

This matters beyond this page: `fd3085b`'s commit message offers "every rewritten
make target passes `make -n`" as its evidence. That is valid for the toolkit half
only.

**2. A working-tree read is not a property of the commit — and a dead probe looks
exactly like a true negative.** Five levels disagree here (main working tree, main
HEAD, a `.claude/worktrees/*` working dir, its index, its commit); CI clones HEAD.
Two sessions probed the live tree, reported `romlibs-gds-check` "exists", and
concluded CI was wrong.

The first HEAD scan written for *this* audit was itself broken — a `\b`-anchored
ERE that matched nothing in the working tree either, where the rule demonstrably is
at `Makefile:165`. It printed a clean "not found" for HEAD and was one step from
being reported as confirmation. **Carry a known-good control as well as a
known-bad one:** the known-bad shows the probe can say no, the known-good shows it
can say yes, and only the second detects a probe that has died. See
`docs/tapeout/33-toolkit-legacy-decoupling.md` for the full tree-level taxonomy.

---

## Re-running it

    python3 scripts/ci/audit_signoff_targets.py

Prints **15 of the 17 rows** above and writes JSON with `--json <path>`. It
re-derives every invocation from `ci/signoff.yaml`, so it stays true as stages are
added. Two known gaps, both deliberate rather than fixed, because pretending to
parse Python out of YAML is worse than saying you do not:

* the two `rom-vars` calls are inside `python3` heredocs as argv lists, not shell
  words, so the scanner does not see them. They were resolved by hand and are in
  the table above. **Any future sweep must read the heredocs too.**
* the `CHAINS` dict maps each `(dir, -f file)` to the include chain used for the
  HEAD scan. A new `include` line in a makefile has to be added there or that
  file's targets will read as UNDEFINED at HEAD. The WORKTREE column needs no
  such map — that half is always correct.

**Re-run this after `gate1` produces artefacts.** Every UNVERIFIED stage in the
table at the top will execute for the first time, and this audit only proves the
targets resolve — not that they reach a correct verdict.
