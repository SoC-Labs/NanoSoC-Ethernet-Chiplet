# Fixtures for `scripts/ci/lvs_missing_connection.py`

## What the gate asserts, so the arms make sense

**Zero `** missing connection **` discrepancies on nets below the top level.**
Not the LVS verdict — that stays `INCORRECT` on this design permanently
(`.GLOBAL VSS` floods ~17,233 unmatched source nets, the pad ring has no LEF
PINs), and a permanently red gate is a gate its reader learns to skip. On
23 August the reader skipped it, and the one line that mattered went with it.

Three verdicts, always: **PASS / FAIL / NOT-MEASURED**. NOT-MEASURED is never a
pass.

## Four arms are EXTRACTS of real reports. Eight are DERIVED and say so.

Every line in an EXTRACT arm was produced by Calibre on this site and is copied
verbatim, with three transformations, all of them stated in the fixture's own
first lines:

1. absolute site paths → `${CHIPLET_HOME}` / `${SITE_PATH_WITHHELD}`;
2. `USER NAME:` → `${USER}`;
3. lines the gate does not read are dropped, so **line numbers inside a fixture
   are not the source's line numbers**.

The repository is public and its vendor guard rejects absolute site paths in
tracked content, which is what (1) and (2) are for.

A **DERIVED** arm is assembled rather than observed. Each one carries
`*** THIS FIXTURE IS DERIVED, NOT OBSERVED. ***` in its own first five lines,
names exactly what was changed, and isolates ONE guard. A fixture must never
pass itself off as observed.

## The sources, and where they live

| source | lines | on disk |
|---|---|---|
| `lvs_run_pintext` | 20,030 | `ASIC/genus-innovus/runs/20260811T103338Z_fill-verify/prev_work/lvs_run_pintext/nanosoc_eth_chiplet_pads.lvs.rep` |
| `lvs_run` | 50,002 | `.../prev_work/lvs_run/nanosoc_eth_chiplet_pads.lvs.rep` |
| `lvs_run_nopadbox` | 21,316 | `.../prev_work/lvs_run_nopadbox/nanosoc_eth_chiplet_pads.lvs.rep` |
| `erc_allfix_logo` | 968 | `ASIC/genus-innovus/erc_runs/erc_allfix_logo/nanosoc_eth_chiplet_pads.lvs.rep` |

All four are Calibre `v2023.1_18.8`. The first three are 10 August 2026 runs;
the ERC one is 22 August.

**None of them is the shipping lineage, and that is a finding rather than an
oversight.** Every LVS report of a 22–24 August stream — rzG's included — was
written to a session scratch path and is gone. See the `fail-derived-rzg-entry62`
arm.

## The arms

| arm | kind | lines | expected | what it proves |
|---|---|---|---|---|
| `pass-observed-toplevel-only` | EXTRACT `lvs_run_pintext` | 213 | **PASS** | a measured zero: 23 missing-connection rows present, none on a sub-top net. Also the M9 control |
| `pass-observed-no-net-section` | EXTRACT `lvs_run_nopadbox` | 85 | **PASS** | a *consistent* absence: no `Connectivity errors.` declared and no INCORRECT NETS section |
| `fail-observed-subtop` | EXTRACT `lvs_run` | 216 | **FAIL** | real sub-top discrepancies (DISC 7, 8, 9) alongside the top-level VSS flood |
| `not-measured-not-compared` | EXTRACT `erc_allfix_logo` | 64 | **NOT-MEASURED** | a real run that compared nothing and has zero findings for free |
| `fail-derived-rzg-entry62` | DERIVED | 153 | **FAIL** | the 23-August defect, one sub-top entry among top-level noise |
| `fail-beats-vacuity` | DERIVED | 103 | **FAIL** | a finding is not suppressed by a failed coverage control |
| `not-measured-not-compared-only` | DERIVED | 117 | **NOT-MEASURED** | control N3 alone |
| `not-measured-truncated` | DERIVED | 110 | **NOT-MEASURED** | control N4 alone — the report never reaches its SUMMARY |
| `not-measured-no-coverage` | DERIVED | 104 | **NOT-MEASURED** | control N5 alone — the population control |
| `not-measured-blind-parser` | DERIVED | 96 | **NOT-MEASURED** | control N6 alone — the tool declares connectivity errors, the parser finds none |
| `not-measured-disc-list-saturated` | DERIVED | 134 | **NOT-MEASURED** | control N7 alone — discrepancy count equals `LVS REPORT MAXIMUM` |
| `pass-toplevel-row-saturated` | DERIVED | 123 | **PASS** | the other side of N7: a truncated *row* list inside one top-level discrepancy is recorded, not laundered and not over-read |

## The defect arm, in detail — because the report it came from is GONE

`fail-derived-rzg-entry62` reconstructs the finding this whole gate exists for.

**The report is not on disk.** Searched 2026-08-24 across the filesystem: no
`.rep` file anywhere contains `RAMCLD0RDATA` or `g87561`. It lived in an
ephemeral session scratchpad. What survives is the entry as transcribed at the
time into two tracked documents:

    docs/tapeout/EVENING_REPORT_2026-08-24_pinfix.md:121-125

        62  Net X99/6106   Xu_..._u_cache_subsystem_RAMCLD0RDATA[123]
            --- 1 Connections ---        --- 2 Connections ---
            ** missing connection **     Xu_..._u_soc/Xg87561:B2

    docs/plans/BLACKBOX_DETECTION_2026-08-24.md:63-64

        RAMCLD0RDATA[123]  line 3612  ** missing connection **  Xg87561:B2

What is **real**: the discrepancy number 62, the layout name `X99/6106`, the net
`RAMCLD0RDATA[123]`, the stranded load `Xg87561` pin `B2`, the 1-vs-2 connection
counts, and which side the marker is on.

What is **reconstructed**: the `Xu_..._` elisions. They are expanded to the
hierarchy this site's surviving reports actually print
(`Xu_nanosoc_eth_chiplet_chip_u_soc_u_soc/`) and to the flat net name the CDL
actually carries,
`u_qspi_flash_0_u_top_ahb_qspi_u_cache_subsystem_RAMCLD0RDATA[123]` — confirmed
in `.../lvs_run/nanosoc_eth_chiplet_pads_lvs_src.cdl:227465` (a macro drives it
on `Q[27]`) and `:229215`, where an `AOI22D1` takes it on pin `B2`. That is the
same load in a different lineage's netlist, under a different gate name, which
is as close as the surviving evidence gets. Column alignment and every
surrounding line are verbatim from `lvs_run_pintext`.

What is **not verifiable**: the exact spelling Calibre printed in the rzG
report. The file is gone. That absence is itself the point of the work item
these fixtures belong to.

## Derivation, arm by arm

Reproducible from the sources above while they survive. Discrepancies are
identified by their DISC number in the source report.

- **`pass-observed-toplevel-only`** — `lvs_run_pintext` header (banner, paths,
  `OVERALL COMPARISON RESULTS`, error list), the `LVS REPORT MAXIMUM` line, the
  `INCORRECT NETS` banner and column ruler, then DISC 1 (VDD) and DISC 2 (VSS)
  with their row lists **trimmed to 6 rows each** (the source prints 81 and
  1,000), DISC 3–7 whole, DISC 49/50/56/62/65 whole (the ones with `/` in the
  LAYOUT column), DISC 249/250 whole (`** no similar net **`), then the
  `INCORRECT INSTANCES` banner with six real connection lines carrying the
  coverage token, then the `SUMMARY`. The row trim is why this arm does not
  trip the row-truncation note that the full source does.
- **`fail-observed-subtop`** — same shape from `lvs_run`: DISC 1 (VSS) trimmed
  to 5 rows, then DISC 7, 8 and 9 whole. Those three are real sub-top
  discrepancies on `Xu_..._u_soc/Xu_network_core/i_bootrom_0_hrdata[*]`.
- **`pass-observed-no-net-section`** — `lvs_run_nopadbox` header, parameters,
  the `INCORRECT INSTANCES` banner, six real lines carrying the coverage token,
  and the `SUMMARY`. The source genuinely has no `INCORRECT NETS` section and
  genuinely does not declare `Connectivity errors.`
- **`not-measured-not-compared`** — `erc_allfix_logo` header through
  `Error: Nothing in source.`, the parameters, and the `SUMMARY`.
- **`not-measured-not-compared-only`** — DERIVED. The pass arm with the verdict
  word changed to `NOT COMPARED` and the error list replaced by the one a real
  `NOT COMPARED` run prints. The combination (a `NOT COMPARED` box above a
  populated `INCORRECT NETS` section) is contradictory and Calibre does not
  produce it; that is the price of isolating one guard.
- **`fail-beats-vacuity`** — DERIVED. The pass arm's header plus one invented
  sub-top discrepancy, and no coverage-token lines. Run at `--coverage-min 400`
  so the control fails while the finding stands.
- **`not-measured-truncated`** — DERIVED. The pass arm cut off mid-line before
  its `SUMMARY`.
- **`not-measured-no-coverage`** — DERIVED. The pass arm with the
  coverage-token lines removed.
- **`not-measured-blind-parser`** — DERIVED. The pass arm with its whole
  `INCORRECT NETS` section removed and the error list left untouched, so the
  tool still declares `Connectivity errors.`
- **`not-measured-disc-list-saturated`** and **`pass-toplevel-row-saturated`** —
  DERIVED. Real top-level discrepancies under an `LVS REPORT MAXIMUM` of **4**.
  The real cap on every run on this site is **1000**; it is lowered so the arms
  are ~130 lines instead of 20,000. That substitution is the only invention in
  either file.

## Two shapes in here that no real run on this site produces

Flagged rather than passed off as observed:

1. `LVS REPORT MAXIMUM 4`. Every real run reads `1000`.
2. A `NOT COMPARED` verdict above a populated `INCORRECT NETS` section.

Everything else in every arm is real Calibre output.

## Coverage-control numbers, for calibration

The gate counts a token (`u_cache_subsystem` by default) and refuses to call a
zero clean if the token is absent. Recorded values:

| report | mentions |
|---|---|
| rzG (gone) | 388 |
| the fixed stream (gone) | 384 |
| `lvs_run` | 360 |
| `lvs_run_pintext` | 408 |
| `lvs_run_nopadbox` | 482 |
| `lvs_run_20260810T065131Z_honest-full-pnr2` | 482 |
| `erc_allfix_logo` | 0 |
| `gdsrun-20260824-valid4/erc_run` | 0 |

The default `--coverage-min` is 1. In CI, set it near the observed band.

## Fixture header lines are invisible to the gate

Every fixture starts with `#`-prefixed provenance lines. The parser drops any
line beginning with `#` at column 0 and counts how many it dropped. **Measured
2026-08-24: zero lines begin with `#` at column 0 in any of the six real
Calibre LVS reports on this site** — the report's ASCII-art boxes are all
indented — so the rule can only ever drop a comment. Without it, a provenance
note that quotes a discrepancy would become one.

## Mutation result

**9 mutations, 9 caught.** The table is in the script's own header so it travels
with the code. Round 1 caught 8 of 9: **M4 survived**, because the only observed
`NOT COMPARED` report also has zero coverage and so was proving two rules at
once. `not-measured-not-compared-only` exists because of that round.

Re-run it whenever a rule changes. A fixture set that catches fewer than all of
them is a fixture set that has stopped proving something it used to.

## Regenerating

The fixtures were cut from the sources by a short extraction pass (keep the
lines the gate reads, scrub site paths, trim long row lists). If a source is
still on disk the extraction is reproducible from the ranges above; if it has
been cleaned up, the fixture here is the only surviving copy, which is the
point — the sources under `ASIC/eth-chiplet/build/` are gitignored and the
`runs/` tree is not published either.

Do not hand-edit a fixture to make the gate pass. If the gate needs to change,
change the gate and re-cut the fixture from a real report that exhibits the new
shape.
