# Tapeout punchlist — eth chiplet, 24 August 2026

TSMC65 / imec mini@sic MPW / project TMWB45_10042. **Submission 1 September 2026** —
seven days. This is the document the project works from until then.

**Primary evidence.** `ASIC/imec_results/Archive_nanosoc_eth_chiplet_pads_DRYRUN_20260823_rzG_merged_dummyWithSealRing_24Aug26_14u27/`
— the first imec run against our real shipping lineage. Its
`design/reports/Final_Report_*.rpt:47` records md5 `41a0baee…`, which is exactly
`ASIC/submissions/nanosoc_eth_chiplet_pads_DRYRUN_20260823_rzG.gds`
(`ASIC/submissions/nanosoc_eth_chiplet_pads_DRYRUN_20260823_rzG.md:4`). Every earlier
archive graded a retired 10-Aug stream and its verdicts do not transfer.

**Second evidence source, arrived today and not previously worked.**
`ASIC/imec_results/PadShorts/` — a separate imec ERC + circuit-extraction delivery,
run 24 Aug 15:53 on the same merged database. It contains the first device-level
electrical result this project has ever received. § 2.6 and § 5 below.

**Reading conventions used throughout.**
- **MEASURED** — a number read out of a named file in this repo, cited file:line or path.
- **INHERITED** — carried from a repo note or commit message; several such notes were
  refuted this week, so each is flagged.
- **NOT MEASURED** — no evidence either way. § 6 collects these; they are the dangerous ones.

**Coordinate conversion, MEASURED and verified.** imec's merged topcell adds a 20 um
seal-ring frame, so their die box is 1640 x 2040 against our 1600 x 2000. Every imec
coordinate maps to ours by **subtracting (20.0, 20.0) um**. Verified on
`VIA4.R.4:M5`: imec `(1233.42, 681.05)` (drc RVE `.txt`) against our
`(1213.42, 661.05)` (`ASIC/genus-innovus/scripts/pg_drc_post_route_edits.tcl:29-101`)
— exact to the nanometre. Use this when handing imec coordinates to a P&R session.

---

## 1. The three streams, and which one is which

This is the first thing to get straight; three different builds are being quoted
interchangeably and only one has ever been graded by the foundry.

| stream | exists as | our DRC total | design-owned geometry | imec-graded? | floating-gate defect |
|---|---|---|---|---|---|
| **rzG** `DRYRUN_20260823_rzG` | `ASIC/submissions/…_rzG.gds`, md5 `41a0baee…` | **750** | **14** | **YES, 24 Aug** | **YES — 14 PO.R.8** |
| **valid4** `gdsrun-20260824-valid4` | `ASIC/eth-chiplet/build/gdsrun-20260824-valid4/outputs/` | **741** | **4** | no | **UNKNOWN** |
| **valid4+EDIT** | **only** `/tmpdir/claude-74755/…/scratchpad/m8s3/arms2/comb/nanosoc_eth_chiplet_pads_logo.gds` | **738** | **1** | no | **UNKNOWN** |

MEASURED: `scripts/ci/drc_census.py` against `ASIC/genus-innovus/calibre_runs/drc_rzG_logo_0823`
(750), `…/drc_valid4_logo_0824` (741), `…/drc_combined_EDIT_0824` (738), and the
per-cell blocks at `…/nanosoc_eth_chiplet_pads.drc.summary:2242` in each.

Three consequences, and they set the shape of the whole week:

1. **valid4 is materially better than rzG on geometry** — it clears `G.4:M5i` 2,
   `G.4:M6i` 4, `M4.S.1` 1, `M5.W.1` 1, `M5.A.1` 1, `M9.W.1` 1 (ten results), leaving
   `VIA3.R.4:M4` 1, `VIA4.R.4:M5` 1, `M8.S.3` 2. The EDIT arm then clears three more,
   leaving **one**.
2. **Nobody has checked valid4 or the EDIT arm for the floating-gate defect, and our
   own DRC structurally cannot** — see § 4.2. That check requires either an imec
   round-trip or the new toolkit connectivity gate.
3. **The best stream lives in a session scratchpad** that no build system, no
   `ASIC/submissions/` entry and no git object references. `calibre_runs/` is
   gitignored (`.gitignore:23`); `build/` is gitignored (`.gitignore:207`).

---

## 2. Every non-zero result in the newest archive, with an owner

Owner vocabulary: **OURS-FIX** (actionable by a P&R iteration) / **OURS-WAIVE**
(ours, but the right answer is a written statement) / **VENDOR** (inside unmodifiable
vendor GDS) / **IMEC-WRAPPER** (an artefact of the cell imec build around ours) /
**SWITCH-ARTEFACT** (their deck ran with the wrong option) / **UNKNOWN**.

Total non-zero results across all delivered sections: **1,792**. All are assigned below;
nothing is waived by omission.

### 2.1 DRC — 641 results

Deck: the TSMC 65nm main DRC document and its 9M_6X1Z1U rule file (revision
withheld -- it encodes the deck revision this site licensed; quote it in
correspondence, not in a public repo), switch
`#DEFINE LP`, `// #DEFINE WLCSP_SEALRING` **commented out** (so the WLCSP seal-ring
derivation is off — this answers a long-standing switch ambiguity).
Runtime 4 min 36 s. Source: `design/reports/Final_Report_*.rpt:854-941` and
`drc/cali_drc_*.rpt`.

**Design-owned — topcell `nanosoc_eth_chiplet_pads_dummy_WithSealRing`, 29 results:**

| rule | n | owner | note |
|---|---|---|---|
| `PO.R.8` | **14** | **OURS-FIX** | **THE BLOCKER.** Real floating gates. Locations cluster in imec x[805.6,930.3] y[438.8,488.3] → **ours x[785.6,910.3] y[418.8,468.3]**, the cache way0/way1 region. 7 distinct sites, 2 markers each. |
| `G.4:M6i` | 4 | OURS-FIX | min-step M6, keep-out residue. **Already 0 on valid4.** |
| `G.4:M5i` | 2 | OURS-FIX | min-step M5, keep-out residue. **Already 0 on valid4.** |
| `M8.S.3` | 2 | OURS-FIX | 1.495 vs 1.500, same-net VDD. Fix proven (§ 4.3), **not in this stream**. |
| `VIA3.R.4:M4` | 1 | OURS-FIX | single-cut near a plate. **Still present on valid4 and on the EDIT arm — the last one standing.** |
| `M4.S.1` | 1 | OURS-FIX | 0.025 vs 0.100 against a vendor macro pin. **Already 0 on valid4.** |
| `VIA4.R.4:M5` | 1 | OURS-FIX | Fix proven (§ 4.3), not in this stream. |
| `M5.W.1` | 1 | OURS-FIX | sliver at ours (565.46, 478.00). **Already 0 on valid4.** |
| `M5.A.1` | 1 | OURS-FIX | same sliver as `M5.W.1`, same coordinate. **Already 0 on valid4.** |
| `M9.W.1` | 1 | OURS-FIX | VIA8 landing-pad tab. **Already 0 on valid4.** |
| `DRM.R.1` | 1 | OURS-WAIVE | whole-die informational reminder; the deck's own text says so. |

**Vendor-owned — 612 results, every one attributed to a specific TSMC IO cell with an
exact instance-count match.** MEASURED by dividing the archive's flattened count by
the unique count and matching against the as-built padring census
(`ASIC/submissions/padring_as_built_rzG_20260823/nanosoc_eth_chiplet_pads_as_built_pads.csv`):

| rule | n | flattened | placements | owning subcell | resolves to | owner |
|---|---|---|---|---|---|---|
| `ESD.23g` | 468 | 5616 | **12** | `SBC331_POSTVDD2POC_G` | 11 × `PVDD2DGZ_G` + 1 × `PVDD2POC_G` = 12 | **VENDOR** |
| `RM.WARN.2` | 100 | 600 | **6** | `SBC331_RES_04X22D11X47` | 6 × `PVDD1DGZ_G` | **VENDOR** |
| `RM.WARN.2` | 14 | 168 | **12** | `SBC331_POSTVDD2POC_G` | same 12 as above | **VENDOR** |
| `ESD.22g` | 28 | 1344 | **48** | `SBC331_POSTP` | 36 `PDDW16DGZ_G` + 9 `PDDW04DGZ_G` + 2 `PDUW16DGZ_G` + 1 `PDUW08DGZ_G` = 48 | **VENDOR** |
| `ESD.21g` | 2 | 144 | **72** | `SBC331_MOS_ESDN01_VDD2_RPO_095` | 48 signal IO + 12 `PVDD2DGZ_G` + 12 `PVSS2DGZ_G` = 72 | **VENDOR** |

Every divisor lands on an exact padring population. This is a complete, closed
attribution — there is no unattributed residue, which is the first time that has been
true on this project. `RM.WARN.2` is warning-class by its own name; the three `ESD.*`
are TSMC's own 2.5 V IO cells failing TSMC's own ESD rules and need a vendor waiver
line in the submission letter, not a fix.

**Side finding, MEASURED and it settles an open question.** The padring carries exactly
**one** `PVDD2POC_G` (as-built census above). Broker Q2 asked whether one per ring or
four is correct; the ring was converted to one and the conversion is confirmed as built.
The `ESD.23g` population is *not* reduced by that conversion, because the offending
subcell is also inside all 11 `PVDD2DGZ_G`.

### 2.2 BND — 943 results

Deck `T-000-CL-DR-017-C1 VER 1.4a1`, switches `#DEFINE PITCH_80_STAGGER`,
`#DEFINE with_AP`. `design/reports/Final_Report_*.rpt:762-792`.
**A sibling agent is analysing this section in depth — this is the one-line owner view only.**

| rule | n | where | owner |
|---|---|---|---|
| `PM.W.1` | 893 | 867 topcell + 26 in TSMC's `CORNER_B` | **IMEC-WRAPPER** — PM is a layer our stream does not contain at all (§ 3.4); it arrives with their seal ring |
| `AP.S.4` | 46 | topcell, perimeter | **OURS-WAIVE or OURS-FIX — sibling to rule.** Was 131 on 21 Aug, now 46 |
| `CB.W.1:P80_ST` | 2 | vendor `PAD70GU_SL`, `PAD70NU_SL` | **SWITCH-ARTEFACT** — see below |
| `CB.W.2:P80_ST` | 2 | same two cells | **SWITCH-ARTEFACT** |

**The switch artefact is now confirmed, not inferred.** The report's own switch table
(`Final_Report_*.rpt:31`) records `bnd / Pad_Pitch / Pitch_80_STAGGER`. Our ring is
70 um staggered. A 70 um pad master cannot satisfy a rule demanding CB length ≥ 75 um.
Broker Q7 asked them to re-run with `PITCH_70_STAGGER`; **they ran 80 again on 24 August.**
The question was either not received or not actioned.

### 2.3 custom_drc — 169 results

Deck `CUSTOM.TSMC_12-130NM.DRC.12a`, switches `#DEFINE MINIASIC_65NM`, `#DEFINE 9METALS`.
All 169 are imec's own advisory deck, all in the topcell.

| rule | n | owner | evidence |
|---|---|---|---|
| `IM.FLOAT.AP` | 86 | **OURS-WAIVE** | MEASURED: all 86 shapes lie inside imec x[320.0,1047.8] y[859.9,1180.1] — a single 728 × 320 um region, i.e. **the chip logo**. imec's own rule text says "Possibly it's a logo." |
| `IM.POLYIMIDE.1` | 82 | **OURS-WAIVE** | MEASURED: 82 shapes, one per bond-pad opening, bbox spans the full die perimeter. The rule is conditional on bumping; this part is **wirebond** (`custom_drc BEOL_option Wirebond`, `Final_Report:34`). State it in writing. |
| `IM.LOGO.R.1:WARN` | 1 | **OURS-WAIVE** | One whole-die marker. It fires because the design carries **no logo-recognition layer** — MEASURED: the logo-recognition layer and the LMARK layer are both absent from the stream (§ 3.4 census). The rule's own text says the recognition layer "is not a must have" and we do have a visible AP logo. |

**The logo warning has a second, load-bearing consequence.** Because 158/0 is absent,
the TSMC deck's `LOGO.S.1` / `LOGO.R.4` rules **cannot fire**. They reported 1000/1000
(both capped) on the 17-Aug archive and **zero** here. That zero is a measurement
change, not a fix — the repo note that the AP-only logo result is "vacuous" is
**CONFIRMED by imec's own advisory warning**. § 6.

### 2.4 Antenna — 204 rulechecks, **all zero, and the deck genuinely executed**

This is the section this project has been caught by before, so the coverage proof is
given in full. Four independent lines of evidence, all MEASURED:

1. **Runtime 16 min 17 s** (`ant/cali_ant_*.rpt:8`) — not a skipped deck.
2. **204 explicit zero-result records.** `ant/cali_ant_*.txt` lists every rulecheck by
   name with its count: `grep -c '\.rep 0$'` gives **204**, and `awk '/\.rep [1-9]/'`
   gives **nothing**. There are also 204 matching `.rep` stub files in `ant/`.
3. **The connectivity engine ran.** The same file's first record is
   `NET_AREA_RATIO_RDBS / 0 0 272` — the antenna ratio database was built.
4. **It ran over real transistors.** `DevCheck` on the same merged database reports
   **9,248,687 devices** (`Final_Report_*.rpt:739`), including `mn(nchpd_hvtsr)`
   1,993,728 and `mp(pchpu_hvtsr)` 1,993,728 — real SRAM bitcell pass-gates and
   pull-ups, i.e. the memory macros are real geometry too, not black boxes.

**Verdict: foundry antenna signoff over full standard-cell, IO, bond-pad and macro
geometry is MEASURED CLEAN on the rzG stream.** The long-standing "antenna signoff open
on standard-cell blindness" item is **CLOSED for this stream** and must be re-run on
whatever stream actually ships.

For calibration, the device count across the four archives shows exactly how much
context each run had — and why only this one and the 21-Aug run mean anything:

| archive | libraries merged | devices |
|---|---|---|
| 17 Aug | `tpbn65v` only | 6,420,952 |
| 18 Aug | `tcbn65lp` + `tphn65lpgv2od3_sl` | 8,599,725 |
| 21 Aug | all three | 9,245,277 |
| **24 Aug (rzG)** | **all three** | **9,248,687** |

### 2.5 Padring — 0 errors, 0 warnings, four sides

`padring/Padring_check.rpt:44-45`. Was **82 errors** on 21 August (one per bond pad).
The `_SL` bond-pad swap fixed it completely.

**Broker Q5 is answered affirmatively, with a number.** The archive's IP-tag CSV
(`design/reports/…csv`) lists `PAD70GU_SL` area **2170.375 um²** and `PAD70NU_SL` area
**4332.875 um²`. Those are exactly 25.0 × 86.815 and 25.0 × 173.315 — the LEF `SIZE`
values quoted in `docs/plans/BROKER_QUESTIONS_2026-08-19.md` under Q5. The `_SL`
masters exist in imec's `tpbn65v.gds` **and the merge populated them.** The acceptance
test that document proposed has passed.

### 2.6 ERC — two different runs, two different answers

**(a) CheckAll+ ERC: DID NOT EXECUTE, fourth run running.**
`erc/ERC_*.rpt` and `Final_Report_*.rpt:979` both end at
`[ Error ] - No labels found in topcell. At least power/ground labels are required.`
The topcell it checks is **their** wrapper `nanosoc_eth_chiplet_pads_dummy_WithSealRing`.

**MEASURED, and this narrows the defect to two separable halves.** A direct GDSII record
walk of `ASIC/submissions/…_rzG.gds` finds the topcell `nanosoc_eth_chiplet_pads`
carries **52 text records: 48 signal names, plus exactly one each of `VDD`, `VSS`,
`VDDIO`, `VSSIO`** — `VDD`/`VSS` on the M9 pin text layer, `VDDIO`/`VSSIO` on layer
**133/0** (M3 pin). Both layers are in imec's own layer map (`Final_Report_*.rpt:206,211`).

So: **the labels exist, they are on mapped layers, and there are four of them.** The
`[Error]` is literal about *their* topcell, one level above ours. Two defects, two
different owners:
- **IMEC-WRAPPER** — ask them to run ERC with `nanosoc_eth_chiplet_pads` as primary cell.
- **OURS** — four labels for a grid with 34 supply pads and multiple rail fragments is
  the bare minimum. Any fragment that is electrically separate gets no name at all.
  (The repo note recording a regression from 34 per-pad labels to 4 is **CONFIRMED
  MEASURED** at 4.)

**(b) `ASIC/imec_results/PadShorts/` — an ERC that DID run, today.**
Program ERC v1.1, extraction 24 Aug 15:53, same merged database
(`nanosoc_eth_chiplet_pads_dummy_WithSealRing_24Aug26.rpt:8`). This is new material and
carries the first electrical results this project has received.

| finding | n | owner | detail |
|---|---|---|---|
| **NO FLOATING PAD DETECTED** | — | PASS | all 82 pads reach something |
| **NO SHORT BETWEEN POWER AND GROUND PADS** | — | PASS | the one that would be fatal |
| pad-to-pad shorts | 30 | **expected** | MEASURED: all 30 are intra-rail. The extraction resolves exactly **four supply nets** (`…24Aug26.rpt:1454-1502`): PAD20 group (12 pads), PAD11 group (12), PAD30 group (6), PAD32 group (4) = 34 supply pads, matching the padring. No signal pad appears anywhere in the 2.8 MB shorts report. |
| `mppg` | 28 | **VENDOR** | "MOS connected to both power and ground" — same 28 devices and same footprint as `ESD.22g`, i.e. the IO ESD clamp, by design |
| `mnpg` | 10 | **VENDOR** | same pad region |
| **`floating.nxwell_float`** | **1** | **OURS-FIX** | **A floating N-well in the core.** imec (1061.76–1075.84, 299.635–301.565) → **ours (1041.76–1055.84, 279.635–281.565)**: 14.08 × 1.93 um, i.e. one standard-cell row about 23 poly pitches long, with no path to power. This is the geometric signature of the **stranded cells on a PG island** the repo already tracks — independent confirmation from the foundry side. |
| `npvss49`, `ppvdd49` | 0 | PASS | executed with zero results |
| **`floating.psub`** | **0, but `ERROR IN PATHCHK`** | **NOT MEASURED** | see below |
| `!!!!! ERROR Short Report did not match !!!!!` | 1 | **UNKNOWN** | an internal inconsistency in imec's own checker. Ask. |

**The `floating.psub` zero measures nothing, and the reason is our label count.**
`…_erc.txt` records `floating.psub / 0 0 3` followed by the literal line
`ERROR IN PATHCHK`, and the extraction report explains why:
`…24Aug26.rpt:1506` `Invalid PATHCHK request "GROUND": no GROUND nets present, operation aborted.`
and `:1512` `Net "PAD1" matches both LVS POWER NAME "PAD1" and LVS GROUND NAME "PAD1".`
Their harness injected its own `PAD1…PAD82` labels on layer 126 because our stream gave
it nothing else to work with, and with every net called `PADn` the rulefile could
classify none of them as GROUND. **Substrate-to-ground connectivity is therefore
unmeasured, and the cause is the same four-label gap as (a).** Fixing the labels
converts one aborted check into a real one.

### 2.7 Density — all checks zero; no density values delivered

161 density artefacts in `drc/` and `bnd/`. MEASURED: 38 contain only the RVE
zero-result stub line (`<topcell> 1000`), the other 123 are zero bytes. **None contains
a single density window value**, despite `README_for_archive` promising the format.
So: the density rulechecks passed, and we have no margin data. § 6.

### 2.8 Housekeeping results in the report

| item | value | owner |
|---|---|---|
| `CheckIPWM` | 5 IP families tagged: ARM `rf_sp_hdf` + `rom_via`, TSMC `tcbn65lp` 200a, `tpbn65v` 200b, `tphn65lpgv2od3_sl` 210a. Two flagged "latest version" | — |
| `CompareCells` | three libraries matched; `PAD70GU_SL`/`PAD70NU_SL` named as identical | — |
| **`*** Warning *** File … contain empty cells! SBC331_V7Z SBC331_V8Z`** | 2 | **UNKNOWN** | present in **all four** archives (`Final_Report_*.rpt:253-254` in each), so it is a property of imec's IO library import, not of our stream. Two VIA7/VIA8 array cells come out empty. Almost certainly benign, but nobody has asked. |
| `plots/` directory | **absent** | **IMEC** | `README_for_archive` promises a 1200 dpi image of the checked design. Missing from all four archives. It is the cheapest way to see a merge failure. Asked once (doc 55 Q2), still not delivered. |

---

## 3. Did the "clean" sections actually run?

A count of zero over checks that did not execute measures nothing, and this project has
been caught by that repeatedly. Each clean section is graded below.

| section | verdict | evidence |
|---|---|---|
| **Antenna** | **REAL PASS** | § 2.4 — four independent proofs |
| **Padring** | **REAL PASS** | ran on two named libraries, produced per-side verdicts, and returned 82 errors on the same design 3 days ago |
| **Density** | **REAL PASS, no values** | § 2.7 — 161 checks, all zero, no window data |
| **RVE truncation** | **NOT TRUNCATED — verified** | The per-deck result cap is **1000** (first line of every `.txt`). Highest unique count anywhere is `ESD.23g` 468; highest *flattened* count is `PM.W.1` at **971**. Nothing hit the cap. Contrast the 18-Aug archive where **21 separate rulechecks read exactly 1000** — that run was truncated wholesale and is worthless as evidence. **`PM.W.1` at 971/1000 is within 3 % of silent truncation**; if it grows, the report will lie. |
| **`CSR.*` / `SR.*` seal-ring** | **UNRESOLVED** | 17 Aug: `CSR.R.2:B` 104, `CSR.R.2:D` 91, `CSR.EN.8` 28. 21 and 24 Aug: **zero**. We cannot tell from the archive whether the corner work fixed them or whether the check went blind. INHERITED: a repo note argues imec's `CSR.R.1` zero is structurally blind because the seal ring is added before DRC empties the EMPTY_AREA derivation. **Do not book this as a fix.** § 6 |
| **`LUP.*` latch-up** | **COVERAGE UNKNOWN** | zero results, and there is **no way to tell from the archive whether the deck contains these rules**. imec archive a `.rep` stub per zero-result check for `ant` (204 of them) but only 8 for `drc`. § 6 |
| **`AP.EN.2` / `PM.EN.1`** | **CREDIBILITY IMPROVED, still unconfirmed** | Our own BND cannot see these (PM/CB/CB2/WBDMY are empty layers on our side — 187 of 205 rulechecks measure nothing). Post-merge, CB geometry demonstrably exists, because `CB.W.1`/`CB.W.2` fired inside `PAD70*_SL`. So the enclosure family *had* real geometry to check. Whether the rules are in their deck is still Broker Q6, unanswered. |
| **`ERC` (CheckAll+)** | **DID NOT RUN — fourth time** | § 2.6(a) |
| **`floating.psub`** | **DID NOT RUN** | § 2.6(b) — explicit `ERROR IN PATHCHK` |
| **`LOGO.*`** | **STRUCTURALLY INERT** | § 2.3 — 158/0 absent, confirmed by imec's own warning |
| **Layer-map coverage** | **REAL PASS** | MEASURED: a full GDSII record census of the rzG stream (`scripts/ci/gds_layer_census.py`) yields 46 distinct layer/datatype pairs. **Every one of them appears in imec's `LayerMapCadence` table** (`Final_Report_*.rpt:103-230`). No geometry we ship is being silently dropped. (Note for the future: imec's map has M1–M7 pin and M9 pin but **no M8 pin (138/0)**; we currently emit nothing there.) |

---

## 4. Where our signoff and imec disagree, and which to believe

### 4.1 On design geometry: they agree exactly, 15 rules for 15

MEASURED, our `ASIC/genus-innovus/calibre_runs/drc_rzG_logo_0823/nanosoc_eth_chiplet_pads.drc.summary`
(topcell block at `:2242`) against imec's `drc/cali_drc_*.rpt` (topcell block at `:96`):

`G.4:M5i` 2=2, `G.4:M6i` 4=4, `VIA3.R.4:M4` 1=1, `M4.S.1` 1=1, `VIA4.R.4:M5` 1=1,
`M5.W.1` 1=1, `M5.A.1` 1=1, `M8.S.3` 2=2, `M9.W.1` 1=1, `DRM.R.1` 1=1.

**Believe both.** Our local deck is a trustworthy predictor of imec's geometry verdict.
That is worth a great deal in the next seven days: we can iterate locally and only spend
imec round-trips on the things our deck cannot see.

### 4.2 On `PO.R.8`: they disagree, and our deck is the blind one

| | ours (rzG) | imec (rzG merged) |
|---|---|---|
| `PO.R.8` in the topcell | **0** | **14** |
| `PO.R.8` in memory leaf cells | **691** across 22 cells | **0** |

Both are correct given what each was shown, and the consequence is severe:

**Our DRC gate cannot detect this defect class, and the waiver actively hides it.**
`ASIC/genus-innovus/scripts/calibre/drc_waivers.yaml:60-62` declares
`PO.R.8-blackbox-context` with `expect_total: 691`, and `scripts/ci/drc_census.py:216`
hard-fails on any drift. In a black-boxed stream every macro pin looks floating, so a
genuinely unrouted macro pin is indistinguishable from the 691 artefacts. The waiver's
own withdrawal condition (`drc_waivers.yaml:180-181`) is "the foundry reports a non-zero
`PO.R.8` after importing cell layout" — **that condition has now fired**, and it fired
in the topcell rather than in the memory cells, which is a case the waiver text does not
cover.

**And the archives date the regression precisely.** The 21-Aug archive on the previous
stream reports **no `PO.R.8` at all**. It appeared between 21 and 23 August, in the rzG
P&R. That is independent corroboration of the diagnosed cause and it means the defect is
P&R-run-scoped, not inherent.

**Arithmetic worth handing to the three agents fixing it:** imec reports **14 markers at
7 distinct sites** (paired coordinates ~0.27 um apart). The diagnosis names **three**
macro pins. Whatever the fix, the acceptance test is 14 → 0, not 3 pins → routed.

### 4.3 On the post-route edits: our fix is real, and is not in anything imec has seen

`ASIC/genus-innovus/scripts/pg_drc_post_route_edits.tcl` makes two coordinate-guarded,
same-net, geometry-only edits (a 1-cut → 2-cut PG via at `(1213.42, 661.05)`, and a
10 nm M8 enclosure trim at two VIA8 sites). Measured effect 741 → 738, design-owned 4 → 1,
against a matched control.

Three independent proofs it is **not** in the rzG stream: the file's only commit is
`1c5519b` (24 Aug 15:38) and rzG streamed 23 Aug 19:24; `grep -rn pg_drc_post_route_edits`
across the repo returns **zero** hits, so nothing sources it; and both defects are still
measured present in rzG by us *and* by imec.

### 4.4 Where our signoff manifest is stale or contradicts disk

Found while cross-checking. Each is a live trap, not a cosmetic issue:

| location | claim | reality |
|---|---|---|
| `ci/signoff.yaml:1760` | "rzG has no `drc_run` at all yet" | `ASIC/eth-chiplet/build/gdsrun-20260823-rzG/work/drc_run/` exists, 177 files, populated 24 Aug 13:46 |
| `ci/signoff.yaml:2286-2299` | the rail target "DOES NOT EXIST AT HEAD", include is "WORKTREE ONLY" | `ASIC/genus-innovus/Makefile:1204` has the include at HEAD; file unmodified |
| `ci/signoff.yaml:2350-2354` | valid4 has no route manifest | `ASIC/eth-chiplet/build/gdsrun-20260824-valid4/reports/route_manifest.txt` exists, 24 Aug 13:52 — **which means `build-freshness` (gate: block) should now be red on every rzG-pinned stage** |
| `ci/signoff.yaml:3960` | EM "WIRED IN, NOT YET RUN" | a rail run has happened on valid4; it produced no J/Jmax number, so the *conclusion* survives |
| `docs/plans/CONVERGENCE_PLAN_2026-08-18.md:222` | corner rotation "not yet applied" | applied and committed (`d93331f`); `nanosoc_eth_chiplet_pads.io:23,47,78,101` already correct |
| `docs/verification/LINT_WAIVER_INVENTORY.md:157` | `UNDRIVEN` "Not waived" | `verif/lint/full/verilator_lint.py:74` waives it; the report renders `WAIVED 3 UNDRIVEN` |

**Also measured: there is no stored DRC verdict of any kind.** `drc_census.py` prints to
stdout and writes nothing. `build/signoff/` has no `drc/` directory. The only committed
signoff artefact is `build/signoff/signoff_report.json`, **dated 18 August**, whose own
"stages not run" list names `lec`, `lec-pnr`, `drc`, `ir-drop`. Our signoff pipeline has
never produced a graded verdict for the shipping lineage.

---

## 5. THE PUNCHLIST

Ranked by (a) blocks tapeout, (b) blocks silicon working, (c) reduces risk, (d) hygiene.
"Cost" is engineering effort, not wall-clock; imec round-trips are ~24 h and are called
out separately because they are the scarce resource.

### Tier (a) — BLOCKS TAPEOUT

---

**A1. `PO.R.8` × 14 — real floating gates on cache data bit 123**
*Root-caused today; three agents on it. Carried here, not re-diagnosed.*

- **What.** Three macro pins carry no metal (`way0`/`way1` `…_word_3_i` D[27], `way0` Q[27];
  nets `RAMCLD0WDATA[123]` / `RAMCLD0RDATA[123]`). The route stage's regwire repair ran
  `delete_routes -regular_wire_with_drc` then `route_eco -fix_drc`; the reroute failed,
  the nets stayed deleted, and a deleted net carries no DRC marker so the step scored
  itself a success.
- **Evidence.** imec `drc/cali_drc_*.rpt:102` = 14 in the topcell; 7 sites, ours
  x[785.6,910.3] y[418.8,468.3]. Absent from the 21-Aug archive → introduced by the rzG P&R.
- **Owner.** OURS-FIX. Three agents active.
- **Cost.** A P&R iteration plus a re-stream. The gate that catches it is toolkit `3a8c30a`.
- **If we ship without.** Cache data bit 123 is unwritable. Silicon manufactures and boots;
  the cache silently corrupts one bit in 32. TSMC will not catch it — `PO.R.8` is a DRC
  error they will ask us to waive, and we would be waiving a functional defect.
- **Acceptance test.** imec `PO.R.8` = 0 in the topcell. **14 → 0, not "3 pins routed".**

---

**A2. Decide the ship stream, and get *those exact bytes* graded by imec**

- **What.** Nothing currently on disk is both imec-graded and defect-free. rzG is graded
  and has A1. valid4 and valid4+EDIT are better on geometry but have never been graded and
  their A1 status is unknown (§ 4.2 — our deck cannot tell us).
- **Evidence.** § 1 table.
- **Owner.** OURS + one imec round-trip, minimum.
- **Cost.** One P&R (valid4 lineage + the A1 fix + the post-route edits) → stream → submit
  → ~24 h. Budget **two** round-trips; one to confirm A1 = 0, one for the final acceptance.
- **If we ship without.** We submit bytes no foundry deck has ever seen. Every earlier run
  in this project that skipped that step graded the wrong stream.
- **Deadline.** The last stream that can still get a round-trip must exist by **Friday 29 August.**

---

**A3. The best stream and the fixes that produce it exist only in a session scratchpad**

- **What.** The 738-result build is `/tmpdir/claude-74755/…/scratchpad/m8s3/arms2/comb/nanosoc_eth_chiplet_pads_logo.gds`.
  `pg_drc_post_route_edits.tcl` is committed but **unwired** — zero references repo-wide,
  not in `ASIC/eth-chiplet/hooks/post_route.tcl`, not in `power_plan.tcl`, not in any Makefile.
- **Evidence.** § 4.3. `calibre_runs/` gitignored at `.gitignore:23`; `build/` at `:207`.
- **Owner.** OURS-FIX.
- **Cost.** Half a day: wire the script into the route hook or as a restream step, re-run,
  and land the outputs somewhere that is not a temp directory.
- **If we ship without.** The scratchpad is deleted with the session and the only
  reproducible stream reverts to 750/14. This has happened before on this project.

---

**A4. The toolkit pin does not contain either gate that would have caught A1**

- **What.** MEASURED: superproject pins `ASIC/asic-toolkit` at `65d3320`. The working-tree
  submodule HEAD is `3a8c30a` on an **unpushed** branch, 2 commits ahead of origin, and
  `git merge-base --is-ancestor 9a982be 65d3320` is **false**. Six commits sit between.
  `3a8c30a` is the connectivity gate for the deleted-net defect; `9a982be` is the pre-fill
  hold-measurement fix.
- **Owner.** OURS-FIX.
- **Cost.** A push and a pin bump. Minutes. **The push is the part that keeps not happening**
  — a repo note records that chiplet submodule pins are routinely unpushed and the tree is
  not clonable from scratch.
- **If we ship without.** Any CI or fresh clone runs the flow *without* the gate that
  detects A1's failure mode, and re-measures hold 18 ps optimistically.

---

**A5. imec ran the wrong pad-pitch switch, again**

- **What.** `Final_Report_*.rpt:31` records `Pitch_80_STAGGER` on a 70 um staggered ring.
  Broker Q7 asked for `PITCH_70_STAGGER`; the 24 Aug run used 80.
- **Owner.** IMEC / SWITCH-ARTEFACT.
- **Cost.** An email. Zero engineering.
- **If we ship without.** Four `CB.W.*` results stand unexplained in the final acceptance
  report, inside vendor cells, and the correct pitch family is never actually checked. The
  *real* risk is not the 4 results — it is that a pitch-dependent rule we have not seen may
  be being skipped.

---

**A6. The submission bundle and the DDF**

- **What.** `docs/tapeout/55-imec-preliminary-gds-submission-checklist.md:354-366` lists
  13 gates (G1–G13) between what `package_submission.sh` produces and what the manual
  requires: three artefacts packaged that eptsmc will not use, a filename normalisation
  that **destroys stream identity** (G2 — the exact failure that previously hid two runs on
  one stream), no DDF and no slot for one (G3, manual §12), and the IP inventory the manual
  requires under §1.4(6) never produced (G4).
- **Owner.** OURS-FIX.
- **Cost.** One day. Mostly writing.
- **If we ship without.** The submission is incomplete or the returned archive is
  indistinguishable from an earlier one. G2 in particular has already cost this project a run.

---

**A7. Get the merge list for the FINAL run in writing (Broker Q8)**

- **What.** **The 24 Aug run answers Q8 for itself** — `Final_Report_*.rpt:69-72` names all
  three libraries — but the configuration is per-run operator choice and has differed on
  every run. 612 of the 641 DRC results and the entire antenna verdict depend on it.
- **Owner.** IMEC / broker.
- **Cost.** An email; commit `23f8cdb` already asks.
- **If we ship without.** A final acceptance run with a library dropped returns a clean-looking
  report that measured almost nothing.

---

**A8. BND `AP.S.4` × 46 and `PM.W.1` × 893 need a verdict**

- Sibling agent's section. One line here: 939 of the 943 BND results are unresolved between
  "imec's seal ring" and "ours", and BND is the one deck our own runs are structurally
  blind to (187 of 205 local rulechecks run over empty layers). Whatever the sibling
  concludes, **`AP.S.4` 46 is in our topcell** and needs either a fix or a written waiver
  before submission.

---

### Tier (b) — BLOCKS SILICON WORKING

---

**B1. A floating N-well in the core**

- **What.** MEASURED, first time: imec's ERC reports `floating.nxwell_float` = 1 at ours
  (1041.76–1055.84, 279.635–281.565) — 14.08 × 1.93 um, one standard-cell row.
- **Evidence.** `ASIC/imec_results/PadShorts/nanosoc_eth_chiplet_pads_dummy_WithSealRing_erc.txt`,
  `…24Aug26.rpt:16`.
- **Owner.** OURS-FIX. This is the foundry independently detecting the stranded-cells-on-a-PG-island
  condition the repo already tracks (18 cells, all fillers/decaps on the rzG lineage).
- **Cost.** Low — delete the stranded fillers or connect the island. The location is now exact.
- **If we ship without.** An unbiased N-well over ~14 um of a cell row. Latch-up and
  leakage exposure; not simulable, not catchable by any other check we run.

---

**B2. RTL → gate LEC has never passed, on any netlist**

- **What.** MEASURED by enumerating every `verdict.txt` under `ASIC/eth-chiplet/build`:
  the only RTL→gate legs are `full-20260814` (FAIL, 18,326 non-equivalent) and
  `gdsrun-20260821-slpads` (FAIL). The `PASS` rows are all `lec/pnr` or `lec/gate`.
- **The current failure.** `…/gdsrun-20260821-slpads/reports/lec/syn/verdict.txt`:
  `compare_points=5433 equivalent=5433 nonequivalent=0 unmapped_extra_golden=96 tool_exit_code=40 RESULT=FAIL`.
  All 96 are `u_tidechart/u_tidechart_controller/u_enum/root_port_cursor_r_reg[*]`.
  That netlist is md5 `a7076071823c…` — **byte-identical to the shipping rzG netlist**, so
  the pin is measuring the right thing.
- **Owner.** OURS.
- **Cost.** Either prove the 96 benign at `NUM_PORTS=1` and record the argument as a signed
  exception, or re-run LEC with the enum cursor black-boxed. Half a day for the former.
- **If we ship without.** No formal evidence that the manufactured logic implements the RTL.
  INHERITED (and plausible): a repo note argues the 96 are benign at `NUM_PORTS=1` and broken
  only at `>1`. **That argument is not written down anywhere a reviewer could check it.** Write it down.

---

**B3. Hold margin is 27 ps, not 45 ps — and the gate that says so is not pinned**

- **What.** The route gate measures **pre-fill** and is 18 ps optimistic. `9a982be`'s own
  message records pre-fill hold WNS −0.005 / TNS −0.032 / FEP 22 against streamed post-fill
  −0.023 / −0.042 / FEP 12 on valid4.
- **Owner.** OURS. Fix written, **unpinned** — see A4.
- **Cost.** Contained in A4.
- **If we ship without.** Every hold verdict for the rest of the week is 18 ps optimistic on
  a design already sitting at 13 hold FEP at −0.010.

---

**B4. D2D transmit constraints are committed and have never been consumed**

- **What.** MEASURED: `153025c` changed `ASIC/genus-innovus/inputs/constraints.sdc` and
  `tidelink_constraints.sdc` on 24 Aug 12:36. **Every** `outputs/…_syn.sdc` on disk — across
  slpads, rzG, valid4, valid7, holdeco, basepf — is the same file, mtime 21 Aug 21:16, md5
  `8a059920a206…`, and still contains 5 references to `D2D_TX_WORD_CLK_7`, the declaration
  `153025c` deleted. **No synthesis has run since the change.**
- The read-only probe (`ASIC/genus-innovus/scripts/probe_c2_constraints.tcl`, `f4ee1a4`)
  leaves **no artefact on disk** — its result exists only in a commit message.
- **[C2] option A** is still open. The `-asynchronous` clock-group cut is live at
  `ASIC/genus-innovus/inputs/constraints.sdc:292`; the ready patch
  `ASIC/genus-innovus/inputs/patches/c2-option-a-merge.patch` no longer applies cleanly
  (context drift), and ~1,184 endpoints stay unconstrained.
- **Owner.** OURS.
- **Cost.** The constraints are consumed for free by the A2 re-run — **provided the A2 run
  re-synthesises rather than seeding from the 21-Aug netlist.** [C2] option A is a day and
  is genuinely optional.
- **If we ship without.** The D2D transmit interface ships timed by constraints no tool has
  read, and 1,184 endpoints ship unconstrained. The D2D link is the whole point of the part.

---

**B5. The shipping netlist diverges from the FPGA-proven configuration**

- INHERITED, high confidence: the tapeout configuration ships ECC bypassed, CRC on, and FCSM
  recovery stripped; the FPGA-validated configuration is the opposite. Nothing has been
  re-validated in the shipped combination.
- **Owner.** OURS. **Cost:** a decision, plus a regression run if the answer is "change it".
- **If we ship without.** The silicon runs a configuration that has never been proven anywhere.
  **This is the single largest untested-configuration risk on the part** and it is not a DRC issue.

---

**B6. Known functional limitations, already decided — carried so they are not rediscovered**

The D2D wedge (one-shot re-ACK), the intermittent cross-die read that parks the port, the
N1 read-backstop suppression, and TideChart election dual-rooting are documented,
root-caused, and were accepted as ship-with-limitation. `docs/TAPEOUT_LIMITATION_D2D_PEER_WRITE.md`
and `docs/D2D_WEDGE_RECOVERY_DESIGN_2026-08-19.md`. **No action this week** unless the
A2 re-run makes an RTL change cheap, in which case N1 is the one worth taking.

---

### Tier (c) — REDUCES RISK

**C1. Power/ground labels: 4 → per-rail-fragment, and ask imec to run ERC on our topcell.**
Two separable defects (§ 2.6). The label fix is a stream-map change and is cheap; it converts
a fourth consecutive aborted ERC into a real one *and* un-aborts `floating.psub`. **Highest
value-per-hour item on the list.**

**C2. EM current density is `NOT_ANALYSED`.** MEASURED: `ASIC/genus-innovus/rail/work/gdsrun-20260824-valid4/verdict.json`
has `"em_analysed": false`, and the Voltus reports contain the literal line
`Minimum, Average, Maximum J/Jmax:` **with no numbers after it**. `gen_em_ict.py` exists and
is committed (`4ec9c44`); the ICT is wired (`census.txt:41-46`). Also: the EM-bearing run is
on **valid4**, which the ir-drop stage does not grade — the graded rzG census has no
`method.em_ict` line at all. Cost: a Voltus re-run. If we ship without: no electromigration
evidence on a part with 372 missing power vias.

**C3. IR drop misses the mean budget by 0.14 pp** (1.32 % worst). MEASURED and already
documented in `docs/plans/IR_DROP_PLAN_2026-08-24.md`. The **ir-drop stage is `gate: report`**
(`ci/signoff.yaml:2229`), so it can never block. Cost: a decision on whether 0.14 pp matters.

**C4. Vendor waiver letter for 612 ESD/RM results.** § 2.1 gives the complete attribution
with exact instance counts — that table *is* the letter. Cost: an hour. If we ship without:
612 unexplained results in the acceptance report and an avoidable question from the foundry.

**C5. Written waiver statements for the three custom_drc families** (86 float-AP = the logo,
82 polyimide = wirebond not bumped, 1 logo-layer warning). § 2.3. Cost: three paragraphs.

**C6. IO voltage is stated three ways.** `ASIC/asic-toolkit/tech/tsmc65/tech.tcl:97` says
2.50; the mmmc corners say 3.0/3.3/3.6 (`nanosoc_eth_chiplet_pads.mmmc:39,54,69`); the UPF
says 2.97/3.30/3.63; imec's deck ran `Flavor_voltage 1P2V_2P5V`. `tech.tcl:97` feeds the
mW→mA conversion in `pg_capacity.tcl`, so this is not cosmetic. Two repo docs argue opposite
sides. Cost: one measurement and one edit.

**C7. Ask for `plots/` and for the density window values.** Both promised by
`README_for_archive`, neither ever delivered. The 1200 dpi plot is the cheapest possible
detector of a merge failure.

**C8. Ask about `SBC331_V7Z` / `SBC331_V8Z` empty cells and about
`!!!!! ERROR Short Report did not match !!!!!`.** Two unexplained imec-side messages.
Cost: two lines in the same email.

---

### Tier (d) — HYGIENE

**D1.** Six stale or contradicted claims in `ci/signoff.yaml` and repo docs — § 4.4. Each one
is a landmine for the next person.
**D2.** `build-freshness` (gate: block) should now be red on every rzG-pinned stage, because
valid4's route manifest is newer. Either repin or accept a known-red gate deliberately.
**D3.** `scripts/ci/imec_rule_diff.py` exists, works, is **unwired** and has **no stored
output**. The rule-for-rule comparison in § 4.1 was done by hand for the third time. Wire it.
**D4.** No stored DRC verdict anywhere; `drc_census.py` is stdout-only; `build/signoff/` has
no `drc/`; the only committed signoff report is 18 August. Every proof in this document lives
in a gitignored directory on one host.
**D5.** `PM.W.1` flattened count is 971 against a 1000 cap. Add a census assertion that fails
when any flattened count exceeds ~90 % of the cap.
**D6.** `NODRIV` does not exist in HAL 22.03 — the real mnemonic is `UNDRIV`. The misspelling
is in 5 places (`verif/lint/full/hal_lint.sh:56`, `hal_report.py:105-107`,
`verif/lint/netlist/run.sh:57`, `merge_hal_rules.py:28`, `hal_rules.tcl:5`), so the never-waive
list guards a string HAL can never emit.
**D7.** `docs/verification/LINT_WAIVER_INVENTORY.md:157` says `UNDRIVEN` is "Not waived";
`verif/lint/full/verilator_lint.py:74` waives it. Fix the doc or the code.

---

## 6. NOT MEASURED — no evidence either way

These are more dangerous than anything in § 5, because nothing will surface them.

1. **`floating.psub` — substrate-to-ground connectivity.** Explicitly aborted
   (`ERROR IN PATHCHK`, `no GROUND nets present`). Fixed by C1.
2. **`CSR.*` / `SR.*` seal-ring, ~223 results in the 17-Aug run, now zero.** Cannot
   distinguish a fix from a blind check. § 3.
3. **`LUP.*` latch-up — coverage unknown.** Zero results, and the archive gives no way to
   tell whether the rules are in the deck. **Ask imec for the executed-rulecheck count, or
   for a `.rep` stub per zero-result check as they already provide for antenna.** This single
   request would close items 3, 4 and 5 at once.
4. **`AP.EN.2` / `PM.EN.1` passivation enclosure.** Broker Q6, unanswered. Materially more
   credible than before (CB geometry demonstrably present post-merge), still unproven.
5. **Whether imec's DRC deck contains every rule our deck contains.** Our run executes 1,926
   rulechecks; imec's report states no total.
6. **Whether valid4 or valid4+EDIT carry the A1 floating-gate defect.** § 4.2. Only an imec
   round-trip or the unpinned toolkit gate can answer this.
7. **Density margins.** All checks pass; no window values were delivered. We know we are
   inside the limits and nothing about how far.
8. **LVS.** Has never run on this design, at all, by anyone. imec do not run it for mini@sic.
   The PG connectivity state (53 opens / 711 dangling / 372 missing vias) is consequently
   unvalidated in both directions.
9. **The "315 undriven hierarchical ports" figure does not exist on disk.** MEASURED absence:
   an exhaustive search of every `.md/.py/.sh/.tcl/.txt/.json`, all build reports and both git
   logs finds no 315. The real nearby numbers are **221** `W,UNDRIV` in
   `build/lint/netlist/netlist_lint_report.txt:20` (on the shipping netlist md5 `a7076071…`)
   and Genus `check_design` reporting **20** undriven leaf pins / **6** undriven hierarchical
   pins / **336** constant hierarchical pins
   (`…/gdsrun-20260821-slpads/reports/syn_check_design.rep:22486`). **Whoever is carrying "315"
   should stop.** Note also that the HAL pass does not separate tie-offs (its `TIESUP` rule
   returned zero findings), and that `RAMCLD0WDATA[123]`/`RAMCLD0RDATA[123]` are **not** in
   any of these counts by construction — they are logically driven in `gate.v` and only
   physically open in the routed database, so no netlist-reading tool can ever see them.
10. **Verilator `UNDRIVEN` is code-suppressed to WAIVED** (`verif/lint/full/verilator_lint.py:74`,
    plus `lint_off UNDRIVEN` emitted on every generated blackbox), and **HAL `NODRIV` reads 0
    with no positive control** because the mnemonic does not exist (D6). Two of the three tools
    that could have caught an undriven net are non-functional for that purpose, and the third
    cannot see post-route wire deletion. **This is the measurement gap that let A1 through.**
11. **Nothing hashes the shipping stream into a signoff artefact.** `design_report.json`
    carries per-metric provenance but **no GDS md5** — it cannot tie itself to a stream. The
    rzG report was generated 17:55, before the 19:01 stream and before route finished at 19:03,
    with `single_revision: false` and `dirty_stages: ["cts","place"]`.

---

## 7. Before 1 September

### Must happen — no acceptable alternative

| by | item | why it cannot slip |
|---|---|---|
| **Mon 25** | **A1** floating gates fixed and the fix verified locally | everything downstream queues behind it |
| **Mon 25** | **A4** push the toolkit branch and bump the pin | five minutes, and it gates A1's own detector |
| **Mon 25** | **C1** PG labels; **A5/A7/C7/C8** one email to imec | all are hours, and the email needs their turnaround time |
| **Tue 26** | **A3** wire the post-route edits into the flow; **A2** build the candidate on the valid4 lineage | this is the stream that ships |
| **Wed 27** | **A2** submit the candidate for an imec round-trip | last date that leaves room for a second one |
| **Wed 27** | **B1** floating N-well cleared in the same P&R | free if done with A1; expensive as a separate run |
| **Thu 28** | **A6** submission bundle + DDF | paperwork, but G2 has already cost a run |
| **Fri 29** | imec result back: **`PO.R.8` = 0**, antenna re-confirmed, ERC executed | the acceptance gate |
| **Fri 29** | **A8** BND verdict recorded with the sibling's evidence | needed for the submission letter |
| **Sat 30** | **C4/C5** waiver letter (§ 2.1 and § 2.3 are already the content) | must accompany the submission |
| **Sun 31** | final stream frozen, hashed, and its provenance note written | |

### Should happen — real risk reduction, drop only under pressure

- **B4** — re-synthesise so the D2D constraints are actually consumed. Free if A2's P&R starts
  from synthesis rather than seeding the 21-Aug netlist. **Make that call on Monday**, because
  it changes A2's schedule, not its scope.
- **B2** — write down the LEC argument even if LEC still fails. An unexplained FAIL and an
  explained FAIL are very different things to hand a reviewer.
- **C2** — one Voltus EM run on whatever stream ships.
- **C6** — settle the IO voltage.
- Ask for the zero-result rulecheck list (§ 6 item 3). One line in Monday's email; closes three gaps.

### Can honestly slip past 1 September

- **[C2] option A** (1,184 endpoints). The patch no longer applies and the work is a day.
  It reduces timing risk on a part whose timing is already signed off at a known margin.
- **B5** — the ECC/CRC/FCSM divergence. It **cannot** be fixed this week without invalidating
  everything else, and it does not block manufacture. **Record it as a stated, accepted
  condition of the part rather than pretending it is closed.**
- **B6** — the D2D wedge family. Already accepted.
- **C3** — the 0.14 pp mean IR budget miss.
- All of **Tier (d)** except **D2** (the freshness gate will lie to you all week if you leave it).
- **LVS** (§ 6 item 8). Not obtainable in seven days and not required by the flow.

### The single-sentence version

**Fix the floating gates, land the fix in a build that is not a temp directory, push the
toolkit pin, add the power-ground labels, and spend two imec round-trips confirming the
bytes we actually send — everything else on this list is either already clean, someone
else's, or genuinely able to wait.**

---

## Appendix — broker question status after this archive

| Q | status | evidence |
|---|---|---|
| Q1 pad-ring corner discontinuity | superseded — `CSR.*` now reads zero, cause unresolved (§ 6) | |
| Q2 how many `PVDD2POC_G` | **acted on**: exactly 1 as built. Does not reduce `ESD.23g` | as-built pad census |
| Q3 untruncated by-cell DRC | **answered** — the 24-Aug by-cell section is complete, nothing truncated | `Final_Report:919-941` |
| Q4 min same-row bond pitch | still open — packaging, not blocking this submission | |
| Q5 `PAD70*_SL` masters | **ANSWERED (a)**, with areas 2170.375 / 4332.875 um² and padring 0/0 | § 2.5 |
| Q6 `AP.EN.2`/`PM.EN.1` post-merge | **still open**, credibility improved | § 3 |
| Q7 pitch 70 vs 80 | **still open — and they ran 80 again** | § 2.2 |
| Q8 final merge list | **answered for the 24-Aug run** (all three, `Final_Report:69-72`); **not for the final run** | A7 |
| new — deck switch set | **answered by the report itself**: `Cybershuttle`, `LP/ULP`, `1P2V_2P5V`, `14kA`, `No_WLCSP`, `Wirebond`, `9M_6X1Z1U`, WLCSP seal-ring off | `Final_Report:12-38` |
| new — zero-result rulecheck list | **ask** — closes three § 6 gaps at once | |
| new — run ERC with our topcell as primary | **ask** | § 2.6 |
| new — `SBC331_V7Z`/`V8Z`, "Short Report did not match", `plots/`, density values | **ask** | § 2.8, C7, C8 |
