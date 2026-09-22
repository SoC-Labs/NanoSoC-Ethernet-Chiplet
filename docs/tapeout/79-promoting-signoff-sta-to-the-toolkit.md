# 79 — Promoting signoff STA into the toolkit (2026-09-22)

`make sta` is now an **engine** stage. A second die gets Tempus, standalone
Quantus parasitics, the MMMC derivation, the extraction log scan and both
graders from `ASIC/asic-toolkit`, and supplies only its own policy, its own
`site.env`, and its own fixtures.

## The split, in lines

| | before | after |
|---|---|---|
| project **logic** | 3,740 | **94** |
| project **data** | 80 + fixtures | 80 + fixtures (unchanged) |
| toolkit | 0 | 4,044 code + 128 doc/template |

Before, the project carried `ASIC/sta/{run_sta.sh 137, run_signoff_sta.tcl 656,
make_sta_mmmc.py 181, sta_gate.py 1416, sta_extract_evidence.py 434,
qrc_layer_map.ccl 86}`, `ASIC/sta.mk 86` and `scripts/ci/sta_binding.py 744`.

After, it carries `ASIC/sta.mk` (**29 lines, one of them an assignment**) and
`scripts/ci/sta_binding.py` (**65 lines, a forwarding shim** — see below). The
data is `ASIC/sta/sta_policy.json`, `ASIC/sta/site.env.example`, the gitignored
`ASIC/sta/site.env`, and `ci/fixtures/sta-signoff/**` with its `regen.py`.

The toolkit's 4,044 is 304 more than the 3,740 it replaces. That delta is the
generalisation itself: the knobs, the tech-pack lookup, `REQUIRED_POLICY_KEYS`,
the new refusal arm and the comments that explain each.

## Where it lives now

| | |
|---|---|
| `ASIC/asic-toolkit/flow/verify/sta/` | `run_sta.sh`, `run_signoff_sta.tcl`, `make_sta_mmmc.py`, `sta_extract_evidence.py`, `sta_gate.py`, `sta_binding.py`, `site.env.example`, `README.md` (the contract) |
| `ASIC/asic-toolkit/mk/sta.mk` | `sta`, `sta-gate`, `sta-vars`, `sta-selftest`. Included by `mk/flow.mk`, one line |
| `ASIC/sta.mk` | `STA_DIR := $(ASIC_DIR)/../sta`. That is all of it |

Laid out to match `flow/verify/lvs/`: the fragment lives with the engine it
drives, `mk/flow.mk` includes it unconditionally and last, and a project that
owns the target names itself puts `sta` in `ASIC_FLOW_SKIP_MK`.

## Every eth-specific thing found in the engine half

Nine, and what each became:

1. **`sta_binding.py` — the two database names.** `ROUTED_DB_NAME =
   "nanosoc_eth_chiplet_pads_routed"` and `ECO_DB_NAME =
   "…_eco"`, as string literals. A design-agnostic check usable by exactly one
   design. Now `db_names(block)` derives them from `--block` and two suffix
   constants that name where the convention comes from: `mk/flow.mk`'s
   `$(BLOCK)_routed` and `5_eco.tcl`'s `write_db <block>_eco`. `--block` is
   **required**, with no default, because a wrong one does not fail loudly — it
   makes `DB_NOT_ROUTED` fire on a good run, which reads as a design finding and
   is a wiring one. `--routed-db` / `--eco-db` remain for a project off the
   toolkit's naming.
2. **`sta_binding.py` — `--build-root` defaulted to
   `ASIC/eth-chiplet/build`.** Now `build`; `mk/sta.mk` passes `$(BUILD_DIR)`.
3. **`sta_gate.py` — five per-die numbers sat in `DEFAULT_POLICY`**:
   `expected_sdc_clock_count` (26), `expected_clock_count` (104),
   `required_setup_views`, `required_hold_views` (naming
   `av_ml_libset_hold` / `av_ltfix_libset_hold`) and
   `untested_budget_by_reason`. Each is now empty in the engine and listed in
   `REQUIRED_POLICY_KEYS`. **This is the one place a copy would have been
   dangerous rather than merely untidy.** Every one of the five guards an arm
   that goes *quiet* rather than red when it is absent — `if n_sdc or
   want_abs:`, `for v in want:` over `[]`, `if table is not None:` — so a second
   die inheriting an empty default would have had four of this gate's checks
   silently stop existing, and a die inheriting *this* die's numbers would have
   gone red for reasons about the wrong project. So absence is now a FAILURE:
   `POLICY_INCOMPLETE`, naming the key and what it is.
4. **`sta_gate.py` — `--policy` was optional.** Now mandatory, as an argparse
   error. Without it the gate ran on defaults whose clock, view and untested
   arms did not run; nobody should have to read a report to discover that.
5. **`run_signoff_sta.tcl` — the QRC layer map was a project copy.**
   `ASIC/sta/qrc_layer_map.ccl`, whose body was **byte-identical** to
   `tech/tsmc65/qrc_layer_map.ccl` and whose comments had already drifted. The
   session now reads `tech_get qrc_layer_map` — the same file the route and ECO
   stages extract with. `STA_QRC_LAYER_MAP` overrides. The project copy is
   deleted.
   *Measured while wiring it:* a bare `tech_load` of the pack dies on
   `ARM_CLN65LP_TECH`, an RC cap-table package this session never opens, so the
   load is made `TECH_ALLOW_MISSING_ENV`-tolerant and the **answer** is then
   checked on its own merits (exists, readable, or the run stops).
6. **`run_signoff_sta.tcl` — `STA_DB` defaulted to
   `…/build/full-20260814/work/nanosoc_eth_chiplet_pads_routed`.** That default
   is why six signoff runs on 17–18 August timed a fortnight-stale build. It is
   gone from both the Tcl and `run_sta.sh`; both now refuse to start, naming the
   history.
7. **`run_signoff_sta.tcl` — `STA_BLOCK` defaulted to the eth top cell**, and
   `STA_OUT` / `STA_REP` / `STA_MMMC` defaulted **beside the script**. In the
   toolkit that would write into the shared checkout and let two builds
   overwrite each other's evidence. All four are now required (`envreq`), and
   `run_sta.sh` requires `STA_WORK`.
8. **`run_signoff_sta.tcl` / `run_sta.sh` — `REPO` was derived as
   `$STA_ROOT/../..`,** which in the toolkit resolves to the wrong tree. Now
   `STA_REPO`, defaulting to `$(PROJECT_ROOT)`; it is the prefix stripped from
   paths recorded in the manifest so a committed fixture carries no site path.
   Empty is tolerated and no longer crashes the `string first` guard.
9. **Prose throughout** naming `nanosoc_eth_chiplet_pads`, D2D word clocks, RMII
   transmit endpoints, `ASIC/genus-innovus/inputs/constraints.sdc:706`,
   `scripts/ci/sta_untested_reasons.tcl` and "this design". Rewritten to *the
   reference project*, keeping every measurement. The selftest fixtures now name
   `example_top`, `fast_hot_hold_view` and `cold_io_hold_view` — a fixture that
   only works for one top cell cannot prove `--block` is wired through.

`make_sta_mmmc.py` and `sta_extract_evidence.py` needed **no** functional
change: both were already design-agnostic.

## Why `scripts/ci/sta_binding.py` is still there

`ci/signoff.yaml`'s **`sta-binding`** stage — a different stanza from
`sta-signoff` — runs the grader by path twice, and in its second call names
neither the block nor the build root. Those two values are data about this die,
so they are the whole content of a 65-line shim that `os.execv`s the toolkit
copy with everything else forwarded untouched, exit status and output included.
The stage's `check:` greps that output; a wrapper that reformatted it would
break the assertion it is read for.

## What was verified

| | |
|---|---|
| `sta_gate.py --selftest` | **55 / 0** (was 54; +1, see below) |
| `sta_binding.py --selftest` | 20 / 0 |
| `sta_extract_evidence.py --selftest` | 20 / 0 |
| `ci/fixtures/sta-signoff/regen.py --selftest` | 6 / 0 |
| `regen.py --verify` | 13 fixtures, 0 mismatches |
| `signoff.py prove sta-signoff` | 13 cases, **0 problems** |
| `signoff.py prove sta-binding` | 6 cases, 0 problems (through the shim) |
| `signoff.py lint` | clean; every declared gap still real |
| toolkit `test/shell/t_mutation_inventory.sh` | 11 / 0 |
| toolkit `test/stage/run.sh` | verdict set **identical** to clean HEAD (see below) |
| toolkit `ci/check-vendor-collateral.sh --staged` | 5 passed, 0 failed, 1 warn — the warn is pre-existing prose at `mk/flow.mk:656`, not mine |

**54 → 55.** One arm was added, and it is the negative control on item 3: the
good artefact set graded against `DEFAULT_POLICY` alone must be **refused**
with `POLICY_INCOMPLETE`. Without it, "the per-die keys are empty in the
engine" would be a claim rather than a proof, and the failure it guards
against is precisely a gate that stops existing quietly.

**The stage suite.** The live toolkit tree currently carries another agent's
in-flight edits to `flow/innovus/{2_place,3_cts,4_route}.tcl` and `tech/*`, and
`test/stage/run.sh` is red on them. So the comparison was made in isolation:
`git archive HEAD` into two scratch trees, my work overlaid on one. Both report
**141 passed / 1 failed**, and the per-case verdict lines differ only in the
random scratch-directory name. The single failure is `compare.admits-real`,
which needs `git describe` and so cannot pass in a `git archive` export — it is
the 142nd case, green in a real checkout.

### The re-grade — the cheap equivalence check

`make sta-gate RUN_TAG=vt9par-20260916` against the **existing** reports, with
no Tempus re-run:

```
BINDING: PASS
GATE: PASS
setup_wns 0.07 / setup_fep 0    hold_wns 0.007 / hold_fep 0
clock_count 104 over 4 active views
```

`sta_gate.txt` is **byte-identical** to the copy taken before the move.
`sta_binding.txt` differs by exactly two lines: a new `block` fact row, and a
`reports_dir` that is now the absolute path rather than the `…/eth-chiplet/../sta/…`
spelling the old `STA_ROOT` produced.

## What was NOT verified with a real tool run

State plainly:

- **No Tempus run was made.** Nothing here has driven `read_db`,
  `extract_parasitics`, `update_timing` or any `report_*` under the promoted
  script. The re-grade above reads reports produced by the **pre-move** engine.
- So the following are unproven end to end, though each was exercised as far as
  it can be without a licence:
  - the **tech-pack layer map** actually reaching Quantus as
    `extract_rc_lef_tech_file_map`. What *was* proven: `tech_get qrc_layer_map`
    resolves to a readable file under `tclsh`, and the promoted Tcl parses
    (`info complete`) and runs its whole environment section under stubbed tool
    commands — writing the manifest, resolving the map, and refusing when
    neither `STA_TECH_DIR` nor `STA_QRC_LAYER_MAP` is set.
  - `run_sta.sh`'s Tempus invocation, the PATH assembly from `site.env`, and the
    20-minute staleness refusal.
  - `make_sta_mmmc.py` against a real `viewDefinition.tcl` under the new path
    (its logic is unchanged and its self-check still runs).
  - that a fresh run's manifest still satisfies `sta_binding.py` — the
    **binding** half was re-run against a real manifest and passes, so only the
    *production* of that manifest is untested.
- The box was at load ~13 when this was done, i.e. a run would have been
  allowed; it was skipped as optional, not blocked. **The next real `make sta`
  is the acceptance test**, and the first thing to read in its manifest is
  `extract.layer_map_path` — it should now name `ASIC/asic-toolkit/tech/tsmc65/
  qrc_layer_map.ccl`, not a path under `ASIC/sta/`.
- No second die was configured. The generalisation is argued from the code and
  from the fixtures' synthetic block name, not from a second project building.

## For the second die

1. `STA_DIR` in the project's `design.mk` or a two-line fragment, if `sta/` is
   not beside `asic/`.
2. `sta_policy.json` with the five required keys. `make sta-vars` says whether
   it is found; `sta_gate.py` says exactly which key is missing.
3. `site.env` from `flow/verify/sta/site.env.example`, gitignored.
4. `make sta RUN_TAG=<tag>`.

Nothing else. The tech pack already carries `qrc_layer_map`.
