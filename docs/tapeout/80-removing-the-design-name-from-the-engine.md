# 80 — Removing the design's name from the engine (2026-09-22)

**What this is:** the record of making the toolkit port-ready for a second die
by deleting five places where its *active code* spelled this design's pad
conventions, and by replacing the worked example — which was a hand
transcription its own README said must not be built — with one that is
generated from `templates/`.

**Toolkit side:** `ASIC/asic-toolkit` (`main`). **Project side:** two knob
declarations in `ASIC/eth-chiplet/design.mk` and this file.

---

## The shape of the bug, once, because all five were the same one

A value only a project can know, defaulted in the engine.

That is not a cosmetic complaint about naming. The failure mode is specific and
this repository has already paid for it: **a wrong pad pattern is silent.** The
floorplan's `read_io_file`, handed an IO file naming instances the netlist does
not contain, does not fail — it emits one `IMPFP-53 Failed to find instance` per
pad, places the rest and returns. On this design that was 34 warnings, every
supply pad on the die, and the resulting database passed place, CTS, route and
stream-out **three builds running**. It scored *better* than the correct
database, because losing the pads lost their nets, and the only gate that could
see a difference was an upper bound on unrouted nets.

The default that was in the engine until today produced exactly the same zero on
any *other* design: a glob shaped like this project's generator output matches
nothing on a die whose pads are named differently, and a census that matches
nothing is indistinguishable in every artefact from a die whose pads were
deleted.

So the fix is not "change the default". It is **remove the default and judge all
three states.**

## The five, and what each became

| # | was | now |
|---|---|---|
| 1 | `2_place.tcl` defaulted `PLACE_PAD_PATTERN` to this project's glob | no default; `flow_pad_pattern` / `flow_pad_census_pattern` in `flow/common/flow_utils.tcl` are the single reader |
| 2 | the same string spelled again in `1_synthesis.tcl`, `3_cts.tcl`, `4_route.tcl` — **four copies, change one and miss three** | all four call the one reader |
| 3 | `tech/tsmc65/tech.tcl` set `bondpad_prefix {BuPAD_ PAD70}` — an instance prefix inside a **tech pack** | split: `bondpad_cell_prefix {PAD70}` stays (it is the IO library's), the instance half is the project knob `ROUTE_BONDPAD_PREFIX`, and `flow_bondpad_globs` joins them for all three readers |
| 4 | `1_synthesis.tcl` suggested `set DONT_TOUCH_PATTERNS {uPAD_*}` in a fatal message | the message now quotes **this design's own IO file** — three real instance names and their longest common prefix |
| 5 | `ci/fixtures/equivalence/{derive,prove}.sh` defaulted `PROJ` to a home-directory path and hardcoded four memory prefixes | both take the project root as `$1` or `ASIC_REFERENCE_PROJECT` with no default; the prefixes come from `ASIC_CENSUS_MEMORY_PREFIXES` and the census step SKIPs loudly without them |

`grep -rniE 'uPAD|BuPAD|nanosoc.eth|eth_chiplet|rf_32k|flash_cache' flow/ mk/
tech/` still returns lines. **Every one is a comment, a doc, or an LEC self-test
netlist fixture** — the reference design cited as evidence, which is what it is
for. No active statement in the engine names it.

## The three states, and the new refusals

`PLACE_PAD_PATTERN` now has three meanings and the place stage tells them apart:

| value | what happens |
|---|---|
| a glob | censused; the stage **prints what it matched**, per rail and in total, gated or not |
| *(unset)* | `PLACE-FAIL: PLACE_PAD_PATTERN IS NOT DECLARED` — a finding, not a skip |
| `none` | the design has declared it has no pad ring; recorded as `supply_pad_census = DECLINED` |

and a fourth refusal that is the one that matters:

> `PLACE-FAIL: PLACE_PAD_PATTERN MATCHED NOTHING.`

A declared pattern that finds zero instances is now a hard finding. That is the
arm that turns the original three-build silence into a message; before today no
state of any knob could produce it.

Three cases were added to `test/stage/run.sh` so none of this is asserted
without being seen: `place.pads.undeclared`, `place.pads.matches-nothing`, and
`place.pads.declined` (the positive control — a hard macro with no ring must
still pass, or the refusals above would have made the knob unsatisfiable).

## What this project had to do, and why it is one line each

Nothing about this design changed. Two values moved from the engine, where they
were wrong for everyone else, to `ASIC/eth-chiplet/design.mk`, where they are
right for us:

```make
export PLACE_PAD_PATTERN    ?= uPAD_%RAIL%_*
export ROUTE_BONDPAD_PREFIX ?= BuPAD_
```

Verified exported: `make -f <probe> ` prints both. `make check` on
`ASIC/eth-chiplet` reaches the same single pre-existing failure as before (this
run tag's ROM libs are not built), so the reference design still builds.

**Mind the trailing separator.** `uPAD_%RAIL%_*` gives VDD 6 and VSS 4;
`uPAD_%RAIL%*` gives 18 and 16, having swallowed VDDIO and VSSIO — a census that
double-counts agrees with the expected total while describing a different set of
pads. The engine tests for the overlap rather than trusting the spelling.

## The example

`examples/nanosoc_eth_chiplet/` is retired. It was a transcription: every
project-side file copied once from a live design, with the reasoning written in.
Measured at the end, its power plan was 17,227 B against the live 38,257 B — and
it used a variable contract the engine had stopped reading (`FLIST`,
`TOP_LEVEL_HDL`, `CLK_PERIOD`), a different directory layout, six misspelt
library-list names, three config variables with **no reader anywhere** in
`flow/`, `mk/` or `tech/`, and none of the hooks this design depends on.

Its own README carried a boxed "read it, do not build it", and `mk/flow.mk` grew
a guard because the example's directory names are the exact paths the engine
defaults to, so pointing the flow at it *succeeded* and built a different chip.
**A warning label is not a fix.** An example that must not be built is a decoy
with a sign on it.

What replaces it:

- `examples/scaffold/` — exactly what `scripts/asic-flow-init --block example_top
  --tech tsmc65` writes, committed. A **correctly-incomplete skeleton**, not a
  buildable project: `make check` on a fresh copy names 109 unfilled
  placeholders and 2 missing inputs, and exits non-zero.
- `examples/verify.sh` — regenerates into a temp directory and diffs. It also
  runs `make check` there and treats a **pass** as the failure, since a scaffold
  the contract accepts has answered design questions for the reader. Proven able
  to fail: a one-line edit to the committed tree turns it red, naming the file.
  Wired into `ci/static-checks.sh` as `static.example-generated`, blocking.
- `examples/ci/` — the caller-side CI workflows, kept. They are not a
  transcription of a moving design and do not rot the same way.

The maintained filled-in reference is this project's own `ASIC/eth-chiplet/`
tree, read in place at a commit. Copying it into the toolkit is the defect above.

## What is still open

- `mk/flow.mk:62`, `STATUS.md` and two engine comments still name
  `examples/nanosoc_eth_chiplet` in prose about what happened. Accurate as
  history, but the path no longer exists; whoever owns those files should say
  "the example that used to be at …".
- The LEC self-test netlists under `tech/tsmc65/lec/selftest/` still use
  `BuPAD_a` / `BuPAD_b` as instance names. They are fixtures, not engine, and
  nothing reads the renamed tech key through them.
