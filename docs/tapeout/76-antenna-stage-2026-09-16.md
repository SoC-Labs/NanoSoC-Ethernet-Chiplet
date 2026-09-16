# The foundry antenna check is a flow stage — `make antenna`

    measured 2026-09-16, all numbers from artefacts in this repository
    subject   ASIC/eth-chiplet/build/vt7higheco2-20260914  (the best ECO output, ROMs merged)
    control   vt7high-20260914 (its parent route stream)
    toolkit   ASIC/asic-toolkit mk/antenna.mk, flow/verify/calibre/{antenna_census.py,run_antenna.sh}

## What existed, and what did not

The project has had a complete foundry antenna runner since 2026-08-26:
`ASIC/genus-innovus/scripts/calibre/run_ant.sh`, driven by the legacy
`make -C ASIC/genus-innovus ant`, assembling the project wrapper deck plus the
`ANTCTL.*` coverage control into the rundir, writing `ant_manifest.txt` last, and
graded out of band by `scripts/ci/evidence_flow.py`'s `antenna-foundry-deck`
gate. What did not exist was a **toolkit** stage: `grep -nE '^antenna' ASIC/
asic-toolkit/mk/*.mk` returned nothing, `ci/signoff.yaml`'s `antenna-signoff`
row still read "no stage in this manifest runs or gates on a foundry antenna
check", and a run of the toolkit flow (`make route`, `make eco`) produced a
stream nothing antenna-checked unless somebody remembered the legacy target.

This closes that. `make antenna RUN_TAG=<tag>` from `ASIC/eth-chiplet` now
dispatches — exactly as `make drc` does through `DRC_SCRIPT` — to the project's
existing `run_ant.sh` (`ANTENNA_SCRIPT` in `design.mk`; **not a second copy of
the runner**), lands the run in `build/<tag>/work/antenna_run/`, and then runs
`make antenna-census`, which writes `reports/antenna_manifest.txt` and
`reports/antenna_gate.txt` and fails unless the gate reads `VERDICT: PASS`.

## The two streams

    stream                    executed   foundry   control   results   non-zero   wall clock   verdict
    vt7higheco2-20260914      @@E_EXEC@@   @@E_FOUNDRY@@   @@E_CTL@@   @@E_TOTAL@@   @@E_NZ@@   @@E_WALL@@ s   @@E_VERDICT@@
    vt7high-20260914 (parent) @@H_EXEC@@   @@H_FOUNDRY@@   @@H_CTL@@   @@H_TOTAL@@   @@H_NZ@@   @@H_WALL@@ s   @@H_VERDICT@@

Both at `ANTENNA_CPUS=8`, in parallel, on a host already at load 60 from other
work; the rc4 run of 2026-08-29 took 1,357 s at 16 CPUs on a quiet box.

Coverage control (the population every antenna ratio divided by), both streams:

    @@CTL_LINE@@

Every control row is non-empty; five sit at the 1000 result cap, which is a
floor by design (they answer "non-empty?", not "how many").

Deck identity: `foundry_deck_md5 @@DECK_MD5@@` in both rundirs' `ant_manifest.txt`
— the same foundry file the rc4 run used (`84a852ace8dc0ffb5fd1113eedc364cb`
in `calibre_runs/ant_rc4_0829/ant_manifest.txt` of the frozen tree), so the
714 foundry rulechecks are the same 714. Stream md5s: `f3e1c9c01b24a368cf0b9d22034ed3bd`
(vt7higheco2, 341,205,708 bytes) and `0bad54e812d7b4a0c6d7c824f3a15b4c`
(vt7high, 346,693,336 bytes).

## Whose 714 it is

The rc4 dry-run report's line "foundry antenna 0 on every one of 714
rulechecks, 7 population controls all non-empty" sits under **"Measured
elsewhere on these same bytes"** — it is *this project's* run of the foundry
deck (`calibre_runs/ant_rc4_0829`), rendered by the evidence flow's
`antenna-foundry-deck` gate. It is not imec's count. imec's own antenna archive
for this design is a different deck run (204 rulechecks on the retired
2026-08-10 build, `docs/tapeout/48`; zero on every submission including the
78,698-DRC-result one, `docs/tapeout/65`), and its count is not comparable.

So `ANTENNA_EXPECT_RULECHECKS ?= 721` in `design.mk` pins **the local deck to
itself**: 714 foundry + 7 control, the number this deck has executed on every
run since 2026-08-17 (`ant_toolkit_20260817` executed 714 with no control). A
different count is a deck revision, an unset process switch or a partial run,
and the gate turns HARD on it.

## What the gate can refuse — proven by mutation, not asserted

`ASIC/asic-toolkit/test/shell/t_antenna.sh` (93 assertions, no tool, ~5 s)
plants each fault in a copy of a **real capture** — the vt7higheco2 summary
above, scrubbed of site paths and trimmed (`test/fixtures/antenna/PROVENANCE.md`)
— and shows the census refusing it:

| planted fault | gate says | exit |
|---|---|---|
| one result added to `A.R.1:POLY` (row and declared total moved together) | `A.R.1:POLY=1 > budget 0`, VERDICT: FAIL; under `ANTENNA_BUDGET=1` PASS with an ADVISORY naming it | 1 / 0 |
| the row edited without its declared total | `declared vs counted` | 1 |
| `--- SUMMARY` block truncated (721 zero rows survive) | `antenna UNMEASURED - not a pass`, `antenna_rulechecks_executed = UNREADABLE` | 2 |
| the same truncated file through a **mutant** census that counts rows in place of the missing block | VERDICT: PASS — the fixture carries the defect; the gate is what refuses it | 0 |
| `ANTENNA_EXPECT_RULECHECKS=720` against 721 executed | `rulechecks executed 721 != ANTENNA_EXPECT_RULECHECKS 720` | 1 |
| SUMMARY block declaring 720 over 721 rows | `declared vs counted` | 1 |
| one rulecheck removed **and** the declaration lowered to 720 (a consistent, smaller deck) | PASS unpinned; HARD with the knob at 721 | 0 / 1 |
| `ANTCTL.GATE.POPULATION` at zero | `coverage control EMPTY on ANTCTL.GATE.POPULATION`, UNMEASURED | 2 |
| every control row removed | ADVISORY by default; HARD under `ANTENNA_REQUIRE_CONTROL=1` (which `design.mk` sets) | 0 / 1 |
| a foundry rulecheck at the 1000 cap | `a floor, not a count`, refused even inside a budget of 5000 | 1 |
| summary about another top cell / no summary / two summaries and no deck | refused, naming the reason | 1 / 2 / 2 |

`make antenna-census` itself has two guards (the census's exit status and a
grep for `VERDICT: PASS`); three mutant toolkits show each alone still refuses
the truncated run and only both removed lets it through.

## Scope — read before quoting a zero

Unchanged from `run_ant.sh`'s header and `docs/tapeout/65`: the stream carries
LEF abstracts for every standard cell, IO cell and bond pad, so the deck's
antenna denominator (GATE = OD AND POLY) exists only inside the merged memory
macros. The zero is real over that population — the control proves the
population is there — and it is **not** the population the foundry's merged run
measures. Report it as "no violation found within a stated scope".

## What changed, where

Toolkit (`ASIC/asic-toolkit`, commit @@TK_SHA@@):

- `mk/antenna.mk` (new): `antenna`, `antenna-project`, `antenna-toolkit`,
  `antenna-census`, `antenna-vars`; `mk/flow.mk`: one include line beside
  `drc.mk`.
- `flow/verify/calibre/antenna_census.py` (new): the parser and gate.
- `flow/verify/calibre/run_antenna.sh` + `antenna_wrapper.svrf.in` (new): the
  toolkit runner for a project without one — wrapper, generated-from-template
  or spliced deck, coverage control appended after the foundry body, then
  `run_drc.sh` for the launch. `run_drc.sh` gained `DRC_KIND` / `DRC_LOG_NAME`
  so the antenna log is `calibre_antenna.log`; DRC's behaviour is unchanged.
- `test/shell/t_antenna.sh` + `test/fixtures/antenna/` (new).
- `docs/source/reference/knobs.md` (Antenna section), `make-targets.md`,
  `STATUS.md`.

Project (this branch, commit @@PJ_SHA@@): `ASIC/eth-chiplet/design.mk` gains
`ANTENNA_SCRIPT`, `ANTENNA_FOUNDRY_DECK`, `ANTENNA_DECK :=`,
`ANTENNA_EXPECT_RULECHECKS ?= 721`, `ANTENNA_REQUIRE_CONTROL ?= 1`,
`ANTENNA_BUDGET ?= 0`; the toolkit pin moves; this note.

## Left open

- `ci/signoff.yaml`'s `antenna-signoff` row still declares the gap ("no stage
  in this manifest runs or gates on a foundry antenna check"). It is now false
  for the toolkit flow; retiring it means adding the stage to the manifest that
  row inspects, which is that file's owner's change, not this one.
- The evidence flow's `antenna_run` spec key can point at
  `ASIC/eth-chiplet/build/<tag>/work/antenna_run` unchanged — `run_ant.sh`
  writes the same `ant_manifest.txt` there — so the out-of-band gate and the
  in-flow one read one run.
- `make help-all` lists targets from a fixed file list in `mk/help.mk` that does
  not include `mk/antenna.mk`; one line there, not made here.
