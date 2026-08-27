# Fixtures for `scripts/ci/lvs_missing_connection.py`

## What the gate asserts, so the arms make sense

**Zero `** missing connection **` discrepancies on nets below the top level.**
Not the LVS verdict — that stays `INCORRECT` on this design permanently (tens of
thousands of unmatched source nets; the pad ring has no LEF PINs), and a
permanently red gate is a gate its reader learns to skip. On 23 August the
reader skipped it, and the one line that mattered went with it.

> **CORRECTION, 2026-08-27 — the mechanism above used to be stated backwards.**
> This file said "`.GLOBAL VSS` floods ~17,233 unmatched source nets".
> MEASURED at
> `ASIC/eth-chiplet/build/rc2-20260827/lvs_run/nanosoc_eth_chiplet_pads_lvs_src.cdl:1`,
> the line reads **`.GLOBAL VDD VDDIO VSSIO`** — **VSS is not in it.** It is that
> *absence* that produces the flood: every instance that does not pass VSS
> explicitly gets its own one-pin dangling `<inst>/VSS` source net with no layout
> counterpart. **18,321** of that report's `** no similar net **` entries are
> exactly those. Making VSS global is the *fix* being trialled in
> `ASIC/eth-chiplet/build/lvsroot-20260827/`, not the cause.

Three verdicts, always: **PASS / FAIL / NOT-MEASURED**. NOT-MEASURED is never a
pass.

## Two things a PASS from this gate does NOT mean

1. **It is not evidence that the power grid is connected.** The sign is
   inverted: because VSS is not global, a *stranded* layout VSS pin is an exact
   match for the source's one-pin phantom while a *connected* one is a mismatch,
   so breaking the connection removes the discrepancy. MEASURED 2026-08-27 —
   `ASIC/eth-chiplet/build/lvsadv-20260827/break_pg5.tcl` islanded the VSS pin of
   `…/u_network_core/FE_DBTC206_network_core_dbgahb_slvaddr_2` with ≥1.4 µm
   clearance, and this gate scores the resulting run **PASS** — under both
   decks, and identically to its intact control:
   `build/lvsadv-20260827/fals5` (shipping deck, broken database) does not
   mention the stranded cell **at all**, while `…/fals` (same deck, intact
   database) mentions it three times; `build/lvsroot-20260827/B_broken5`
   (root-fix deck) does show it, but as one row under DISC 2 `Net VSS / VSS`,
   a top-level net, which the per-net classification rule excludes. There is no
   fixture arm for this because there is no verdict to assert yet; it is stated
   at length in the script's own header.
2. **On a *capped* report it is not a statement about the whole list.** Three
   of the four numerically-capped reports that have an `INCORRECT NETS` section
   — `lvs_run_pintext`, `gdsrun-20260823-rzG` and `pinfix-20260824/work/lvs_run`
   — are truncated at exactly 1,000 discrepancies, and control N7 cannot
   presently see it because the parser counts only the `Net `-form subset (268,
   263 and 255 of the 1,000). See the script header's `KNOWN DEFECT`.

## Six arms are EXTRACTS of real reports. Thirteen are DERIVED and say so.

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
| `gdsrun-20260823-rzG` | 19,806 | `ASIC/eth-chiplet/build/gdsrun-20260823-rzG/work/lvs_run/nanosoc_eth_chiplet_pads.lvs.rep` |
| `rc2-20260827` | 266,206 | `ASIC/eth-chiplet/build/rc2-20260827/lvs_run/nanosoc_eth_chiplet_pads.lvs.rep` |

All six are Calibre `v2023.1_18.8`. The first three are 10 August 2026 runs;
the ERC one is 22 August; rzG is 23 August and rc2 is 27 August. The last two
were added on 2026-08-27 and are the two load-bearing arms of the
vacuous-pairing rule: rzG carries the real defect (1 shared connection, so the
rule must never touch it) and rc2 carries the only zero-overlap pairing on the
estate.

**None of them is the shipping lineage** — but the reports that ARE it have
since been **RECOVERED**, and the claim that they were gone was wrong.

> **CORRECTION, 2026-08-25.** This file previously stated six times that every
> LVS report of a 22–24 August stream, rzG's included, "is gone". They were not
> gone: they were in a *different session's* scratchpad, which the 2026-08-24
> search did not reach. They are now in the repo tree:
>
> | run | recovered to | verdict under this gate |
> |---|---|---|
> | rzG | `ASIC/eth-chiplet/build/gdsrun-20260823-rzG/work/lvs_run/` | **FAIL** — 1 sub-top missing connection |
> | pinfix (capped) | `ASIC/eth-chiplet/build/pinfix-20260824/work/lvs_run/` | **PASS** — 0 |
> | pinfix (uncapped control) | `ASIC/eth-chiplet/build/pinfix-20260824/work/lvs_run_uncapped/` | **PASS** — 0, 18,214 rows scanned |
>
> Each carries a `RECOVERED_FROM.txt` naming its source and the stream it
> graded. The identification is not by filename: the coverage counts below —
> **388 for rzG and 384 for the fixed stream** — match this file's own recorded
> values exactly, and the rzG report contains both `RAMCLD0RDATA` and `g87561`.
>
> **The lesson is not "the search was sloppy".** It is that a provenance file
> which records evidence as DESTROYED stops anyone looking for it, and is
> therefore worse than one that records it as merely unreachable. An absence
> asserted in a tracked file outlives the search that produced it.

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
| `fail-observed-rzg-entry62` | EXTRACT `gdsrun-20260823-rzG` | 134 | **FAIL** | **added 2026-08-27.** THE defect, in real Calibre output: DISC 62, cache data bit 123, **1 shared connection**. The primary discrimination proof for the vacuous-pairing rule — it fails before the widening and after it. Answers this file's own standing request to re-base the derived rzG arm |
| `pass-observed-vacuous-pairing` | EXTRACT `rc2-20260827` | 144 | **PASS** | **added 2026-08-27.** DISC 43: a pair sharing **0** of its 1/1 connections, so the header is not a correspondence and its source name is not this net's hierarchy. Mutation M10's catcher — the unwidened gate reports FAIL on it. Also M15's only catcher (`LVS REPORT MAXIMUM ALL`) |
| `fail-vacuous-but-layout-is-a-path` | DERIVED | 138 | **FAIL** | **added 2026-08-27.** the widening withdraws the source name, it does not grant amnesty: a vacuous pair whose LAYOUT name is a hierarchy path is still a sub-top finding. M11 |
| `fail-vacuous-counts-unreadable` | DERIVED | 137 | **FAIL** | **added 2026-08-27.** the rule fires only when BOTH connection counts parsed; an unreadable count never buys a pass. M12 |
| `not-measured-vacuous-flood` | DERIVED | 177 | **NOT-MEASURED** | **added 2026-08-27.** control N10 — the widening has a ceiling (`--max-vacuous`, default 3) and the ceiling is a control. Run at `--max-vacuous 3` with four vacuous pairs. M13 |
| `fail-derived-disc-number-4-digits` | DERIVED | 4,096 | **FAIL** | **added 2026-08-27.** 1,001 discrepancies, so DISC numbers reach four digits and Calibre's 7-wide DISC# field leaves only a 3-space gap. The defect is DISC 1001. With the old hardcoded ` {4}` the parser stops at DISC 999 and returns **PASS on a report containing the defect**. M14 |
| `not-measured-derived-no-report-maximum` | DERIVED | 95 | **NOT-MEASURED** | **added 2026-08-27.** control N11 — an *unstated* cap is not an *absent* cap, so N7 could not be evaluated. Also the discriminator that gives `ALL` a distinct meaning. M16 |

## The defect arm, in detail — and the report it came from is BACK

`fail-derived-rzg-entry62` reconstructs the finding this whole gate exists for.

> **CORRECTED 2026-08-25. The report IS on disk**, at
> `ASIC/eth-chiplet/build/gdsrun-20260823-rzG/work/lvs_run/nanosoc_eth_chiplet_pads.lvs.rep`.
> It contains `RAMCLD0RDATA` (2 hits) and `g87561` (2 hits), and the real entry
> reads, at line 3616:
>
> ```
>      ** missing connection **        Xu_nanosoc_eth_chiplet_chip_u_soc_u_soc/Xg87561:B2
> ```
>
> The gate run against it returns **FAIL, required 0 got 1**, naming
> `…u_qspi_flash_0_u_top_ahb_qspi_u_cache_subsystem_RAMCLD0RDATA[123]` at
> DISC 62 — while the pinfix stream returns **PASS, 0**. So the derived arm no
> longer stands alone: the observed pair now exists and proves the same thing
> the reconstruction was built to assert. **The derived arm should be re-based
> on the real report, or retired in favour of an observed pair.**
>
> **DONE, 2026-08-27.** The observed pair now exists: arm
> `fail-observed-rzg-entry62` is an EXTRACT of the recovered report, DISC 62
> verbatim. `fail-derived-rzg-entry62` is KEPT rather than retired, because the
> two now discriminate differently — the derived one puts the entry among
> synthetic top-level noise, the observed one puts it among the real VDDIO/pad
> population — and because a reconstruction that has since been checked against
> its original is worth more as a record than as a deletion.
>
> The 2026-08-24 search that concluded otherwise did not reach the scratchpad of
> a different session.

The paragraph below is the ORIGINAL text, kept because the reasoning it records
is still worth reading — it is what a careful reconstruction looks like when the
source really is unavailable. **Its factual premise is now false.**

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

> **CORRECTED 2026-08-25.** It is verifiable now — see the recovered report
> named above. Compare the derived arm against line 3616 before trusting its
> column alignment.

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
  The real numeric cap on every capped run on this site is **1000**; it is
  lowered so the arms are ~130 lines instead of 20,000. That substitution is the
  only invention in either file.
- **`fail-observed-rzg-entry62`** — EXTRACT. The rzG report's header, its
  `OVERALL COMPARISON RESULTS` box and error list, the `LVS PARAMETERS` line,
  the `INCORRECT NETS` banner and ruler, then DISC 1 (VDDIO) with its row list
  intact, a fragment of the bscan entry, DISC 61 and **DISC 62 whole**, one
  `PROPERTY ERRORS` row, and the `SUMMARY`. No line edited.
- **`pass-observed-vacuous-pairing`** — EXTRACT. The rc2 report's header
  through its error list, `LVS REPORT MAXIMUM ALL`, the `INCORRECT NETS` banner
  and ruler, DISC 41, 42, **43 whole**, 44 and 62, then the real
  `DETAILED INSTANCE CONNECTIONS` and `UNMATCHED OBJECTS` fragments and the
  `SUMMARY`. No line edited.
- **`fail-vacuous-but-layout-is-a-path`** — DERIVED from the arm above by
  changing **one span**: DISC 43's layout name `Net 25087` → `Net X99/6106`,
  the real layout-path form, taken verbatim from the rzG report's DISC 62.
- **`fail-vacuous-counts-unreadable`** — DERIVED from the same arm by rewording
  DISC 43's count heading (`Connections On This Net` → `Connections on this
  net`), which is what a Calibre upgrade that moved the wording would do.
- **`not-measured-vacuous-flood`** — DERIVED from the same arm by **copying**
  DISC 43 three times under fresh discrepancy and net numbers, giving four
  vacuous pairs against a ceiling of three. The copies are the invention.
- **`fail-derived-disc-number-4-digits`** — DERIVED, generated. 1,000 filler
  entries in the compact `Net <n>` / `** no similar net **` form Calibre prints
  for an unmatched layout net (shape copied from
  `build/rc1eco-20260826/lvs_run`, DISC 103–105; the net numbers are the
  invention), then **DISC 1001**, which is the rzG DISC 62 entry copied from
  `fail-observed-rzg-entry62`. `LVS REPORT MAXIMUM ALL`, so N7 cannot fire and
  mask the point. At 4,096 lines it is by far the largest arm; 1,000 entries is
  the minimum that produces a four-digit discrepancy number, and a four-digit
  discrepancy number is the whole assertion.
- **`not-measured-derived-no-report-maximum`** — DERIVED from
  `pass-observed-no-net-section` by **deleting one line**, its
  `LVS REPORT MAXIMUM` line. Nothing else differs.

## Shapes in here that no real run on this site produces

Flagged rather than passed off as observed:

1. `LVS REPORT MAXIMUM 4`. Every real *capped* run reads `1000` — and 16 of the
   24 reports on this site are not capped at all, reading `ALL`. (Until
   2026-08-27 the parser could not read `ALL`; see control N11.)
2. A `NOT COMPARED` verdict above a populated `INCORRECT NETS` section.
3. A report with more than 999 `Net `-form net discrepancies. The largest here
   has 417. `fail-derived-disc-number-4-digits` invents one, because the bug it
   proves is unreachable below 1,000 and Calibre numbers discrepancies
   sequentially — you cannot have a DISC 1000 without 999 before it. Five-digit
   DISC numbers *inside* `INCORRECT NETS` are NOT invented: rc2-20260827 numbers
   that section 1 to 18,600.
4. A report with no `LVS REPORT MAXIMUM` line. All 24 here have one.

Everything else in every arm is real Calibre output.

## Coverage-control numbers, for calibration

The gate counts a token (`u_cache_subsystem` by default) and refuses to call a
zero clean if the token is absent. Recorded values:

| report | mentions |
|---|---|
| rzG (**recovered**, `build/gdsrun-20260823-rzG/work/lvs_run/`) | 388 |
| the fixed stream (**recovered**, `build/pinfix-20260824/work/lvs_run/`) | 384 |
| the fixed stream, uncapped control (`…/lvs_run_uncapped/`) | 3835 |
| `lvs_run` | 360 |
| `lvs_run_pintext` | 408 |
| `lvs_run_nopadbox` | 482 |
| `lvs_run_20260810T065131Z_honest-full-pnr2` | 482 |
| `erc_allfix_logo` | 0 |
| `gdsrun-20260824-valid4/erc_run` | 0 |
| `rc2-20260827` (**added 2026-08-27**) | 4781 |

The default `--coverage-min` is 1. In CI, set it near the observed band.

## Fixture header lines are invisible to the gate

Every fixture starts with `#`-prefixed provenance lines. The parser drops any
line beginning with `#` at column 0 and counts how many it dropped. **Measured
2026-08-24 over the six real Calibre LVS reports then on this site, and
re-measured 2026-08-27 over all 24: zero lines begin with `#` at column 0 in
any of them** — the report's ASCII-art boxes are all indented — so the rule can
only ever drop a comment. Without it, a provenance note that quotes a
discrepancy would become one.

## Mutation result

**16 mutations, 16 caught, 0 survivors — re-run 2026-08-27 over all 19 arms.**
The table is in the script's own header so it travels with the code. Round 1
(9 mutations) caught 8 of 9: **M4 survived**, because the only observed
`NOT COMPARED` report also has zero coverage and so was proving two rules at
once. `not-measured-not-compared-only` exists because of that round.

Re-run it whenever a rule changes. A fixture set that catches fewer than all of
them is a fixture set that has stopped proving something it used to.

### Whole-report regression, 2026-08-27

The mutation suite proves the arms discriminate; it does not prove the change is
safe on real reports. That is a separate run: the gate, before and after, over
**every `.lvs.rep` on this site (24)**. **Exactly three verdicts moved**, and
all three are runs of the *same* rc2 layout:

| report | before | after |
|---|---|---|
| `build/rc2-20260827/lvs_run` | FAIL, 2 | **PASS, 0** |
| `build/lvsbisect-20260827/p4_rc2/lvs_run` | FAIL, 2 | **PASS, 0** |
| `build/lvsbisect-20260827/p5_via3r4_replay/lvs_run` | FAIL, 2 | **PASS, 0** |
| `build/gdsrun-20260823-rzG/work/lvs_run` | FAIL, 1 | FAIL, 1 — unchanged |
| `…/prev_work/lvs_run` | FAIL, 857 | FAIL, 857 — unchanged |
| the other 19 | PASS ×17, NOT-MEASURED ×2 | unchanged |

The widening does not reach a real defect. The two parser fixes moved nothing
here: no report on this site has a `Net `-form discrepancy numbered past 999,
and `ALL` was already being treated as uncapped — by accident, which is the bug.

### The census the widening rests on

Independently re-measured 2026-08-27 across all 24 reports, parsing the DISC
headers width-agnostically and taking the column split from each report's own
ruler:

- **1,516** paired discrepancies carry missing-connection rows.
- On **1,512** of them the identity `connections_layout − missing_source_side ==
  connections_source − missing_layout_side` holds exactly. The **4** exceptions
  are all row-list truncations at `LVS REPORT MAXIMUM 1000`, and the rule
  declines to apply the model whenever the two sides disagree — which is why
  those four are set aside rather than mis-scored.
- **3** have zero shared connections, and they are the *same* DISC 43 in the
  three runs of the rc2 layout. **One object on the whole estate.**
- rzG's genuine defect has **shared = 1**. The 857-row report's **390** sub-top
  findings have shared between **1** and **192**; the minimum is 1.

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
