# `run_index.py` — one machine-readable record per ASIC run

`scripts/ci/run_index.py` reads an existing run directory and writes `RUN.json`
plus one `stage_<NN>_<name>.json` per stage into an output directory you name.
It is **read-only**: it opens reports, it writes nothing else, it renames
nothing, and it never touches `reports/`.

```sh
# index a run, writing beside it
scripts/ci/run_index.py ASIC/eth-chiplet/build/gdsrun-20260826-rc1 -o /tmp/idx

# index and print, write nothing at all
scripts/ci/run_index.py ASIC/eth-chiplet/build/<tag> --dry-run

# cross-check against numbers you already trust; exits 1 on disagreement
scripts/ci/run_index.py ASIC/eth-chiplet/build/<tag> --dry-run \
    --expect-setup-wns "04_route=-0.273,06_post_fill=0.009"
```

Default output is `<run_dir>/index/`. It refuses to write into any directory
that already holds `.rep`/`.rpt` files.

## What it is for

Two questions that currently need six directories and produce contradictory
answers.

**"What was the setup WNS at each stage?"** Three files claim to answer it and
all three disagree, because a stage manifest is written at the END of a stage
that spans several optimisation states and records the LAST one:

| file | says | actually measures |
|---|---|---|
| `reports/route_manifest.txt` | 0.009 | `06_post_fill` — two stages past route |
| `reports/cts_manifest.txt` | 0.005 | `03_cts_opt`, not `02_cts` |
| `reports/place_manifest.txt` | 0.009 | `01b_place_opt`, not `01_place` |
| `reports/design_report.json` | 0.005 | `03_cts_opt`, correctly cited — but written 4 s after CTS and never regenerated |

`RUN.json` answers it in `setup_wns_series_ns`, one row per stage with its
`file:line`, and puts the three claims side by side under
`who_claims_what_about_setup_wns` with what each one really equals.

**"Did DRC pass on the bytes we shipped?"** `reports/<block>_imp_drc.rep` reads
0 and is **Innovus on the database** — and has no `Total Violations` trailer, so
that 0 has no self-check. The Calibre run over the streamed GDS lives outside
the run under a hand-typed tag. On `gdsrun-20260826-rc1` it reads **738**. Both
appear on `stage_stream.json`, each with a `measured_over` field, and the
database one is named `drc_innovus_database_DECOY`.

## The classification rule

> A report belongs to the stage whose **output it measures**, not the stage that
> ran the command.

Where those differ, both are recorded — `located_in` and `measures_stage` — and
`mismatch: true` is raised. The value is **not** silently re-filed under the
stage it measures, because the reader's next act is to open the file, and a
re-filed value sends them to a filename that contradicts what they were told.

Seven rules, tried in order; every file records which one placed it and why.

| rule | evidence | example |
|---|---|---|
| R0 | it lives in a satellite tree or the run's `eco/` tree | `eco/reports/*` |
| R1 | numbered stage token in the filename | `timing_summary_04_route.rep` |
| R2 | named stage prefix | `cts_clock_skew.rep` |
| R2b | database name in the filename | `..._routed_reg2reg.tarpt.gz` |
| R2c | it is a GDS or a `write_stream` report | `..._stream.rep` |
| R3 | value match against the per-stage series | `route_manifest.txt` |
| R4 | the file's own cited sources | `design_report.json` |
| R5 | tool-stated `Generated on:` vs the stage clock | `<block>_imp_drc.rep` |
| R6 | file mtime vs the stage clock (`basis_strength: weak`) | `..._filler_gaps.rep` |
| R7 | by elimination, for a clockless run with one stage | an ECO or LVS scratch dir |

**The stage clock** is a ladder of tool-stated completion marks: each
`timing_summary_<NN>_<name>.rep`'s `Generated on:`, the synthesis manifest's
`date`, and a `(run start)` sentinel. A file almost never lands *on* a mark, it
lands *between two*, and that is reported as a fact: `measures_stage` is the
floor, `measures_stage_interval` names both ends, `measures_stage_exact` is
false. This is what makes this run's density reports legible — they sit between
`05_route_opt` and `06_post_fill`, so **they measure the unfilled database**.
Which end is taken is decided by the phase the file was written in, from the
stage manifests' dates.

`mismatch` and `stale` are different flags. `mismatch` is
`located_in != measures_stage`. `stale` is `measures_stage` earlier than the
last stage the run reached — `design_report.json` cites its sources correctly
and is not mismatched at all; it just describes a database three stages of work
have since replaced.

## House rules it observes

**Never a silent omission.** Absent is `{"value": null, "why_absent": "<what was
searched>"}` — never a missing key, never a zero (`evidence_report.py` RULE 1,
`flow_values.py`). `N/A` in a tool table is a *measurement outcome*, so it too
becomes an absent value quoting the literal. This is **enforced**, not intended:
`audit_no_silent_nulls` walks everything before it is written and lists any
offender in `RUN.json` under `self_audit.violations`.

**Every value carries `file:line`**, the convention `design_report.json` already
uses (`timing_summary_03_cts_opt.rep:94 [SETUP]`), relative to the run dir.

**Every timing metric carries `analysis`**, and the load-bearing member is
`parasitics`, in three states, not two:

- `none` — the header says `Parasitics Mode: No SPEF/RCDB`
- `rcdb` — parasitics present, extracted by the tool itself
- `spef` — a SPEF file was **read** (`read_spef`/`spef_file` in the manifest)

On rc1 the in-flow route WNS is `none` and the post-fill WNS is `rcdb`; Tempus
in `ASIC/sta/work/<tag>/` **extracts with Quantus and writes SPEF, it does not
read one**, so it indexes as `rcdb` with the written-SPEF byte counts recorded
separately. Its setup WNS is −0.049 against the in-flow +0.009, and
`stage_signoff-sta.json` carries both under `setup_wns_vs_in_flow` with the note
that they are not the same measurement.

**Saturation is marked.** `capped: true` rides with any count at its cap:
Calibre's `Maximum Results/RuleCheck` and its `MAXIMUM RDB limit` warnings,
Innovus's `check_drc -limit` and `check_connectivity -error`.

**Calibre's two columns are named.** `TOTAL Result Count = 691 (4282)` — the
first is hierarchical, the parenthesised second is placement-expanded. Both are
emitted, as `value`/`total_hierarchical` and `placement_expanded`, and the note
says which is which. Reading the wrong column is a recurring failure here.

**Genus reports picoseconds.** `stage_synthesis.json` uses `setup_wns_ps`, reads
the `Critical Path Slack` column (the second, not `TNS` and not `Violating
Paths`), and says in the note that it is the worst of N cost groups and is not
comparable to an Innovus WNS.

**Logs echo their own Tcl.** Every log scan drops `@file <n>:` lines and lines
beginning `#`.

## Satellites

Report trees that belong to a run but live outside it are bound by the tool's
own statement of what it read, never by a matching name:

- **Tempus** — `sta_manifest.txt`'s `sta_db` points into the run directory
- **Calibre** — the summary's `Layout Path(s)` is a GDS the run wrote

Calibre bindings also compare the GDS mtime against the run's execution time and
raise `layout_newer_than_run` when the stream was rewritten after the check.
`--md5` hashes the GDS for a definitive answer (slow, 300 MB) — note that a GDS
hash is not layout identity, since every stream embeds its own write clock.

## Validation

Run over 59 build directories under `ASIC/eth-chiplet/build/` (`rc2-20260827`
excluded — live submission candidate). No crashes, no stderr, **0 self-audit
violations**, 4286 of 4704 reports classified (91.1%).

The eight measured per-stage setup WNS values for `gdsrun-20260826-rc1` are
reproduced exactly; `--expect-setup-wns` returns 1 when they are not.

Full-flow runs classify 100% of reports. Of the 418 that were not classified:

- **406** — the run has no stage clock (no `timing_summary_<NN>_<name>.rep`, no
  dated stage manifest) and no single stage to fall back to. These are ad-hoc
  experiment trees with per-arm subdirectories, not runs of the flow:
  `derate-feas-20260826` (229), `via3nrmode-20260825` (49),
  `holdeco-20260824` (30), `via3r4-20260824` (29), `power-saif-20260827` (18),
  `ecoseek-20260825` (13), and a long tail of ≤8. Index the arms individually.
- **12** — the file predates the run's earliest mark, so no stage of this run
  produced it.

Non-report files carry their own reasons and are counted separately, since an
artefact, a log or a run-control script measures nothing: nested sub-runs
(`pgprobe/`, `probe/`) which have their own clock, and manifests belonging to
another run kept as provenance (`rc1_manifest.before`).

## What it deliberately does not do

- **It does not judge.** No pass, no fail, no budget. `signoff.py` judges.
- **It does not rename or move anything.** `ci/signoff.yaml` and the rest of
  `scripts/ci/` pin many of these filenames by literal; this tool only reads
  them.
- **It does not launch a tool** or hash a 300 MB GDS unless asked.
