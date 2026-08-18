# 55 — IMEC preliminary-GDS submission: checklist, covering mail, and how to read the report back

[← 48 IMEC signoff results](48-imec-signoff-results-analysis.md) · [index](00-index.md) ·
[50 BND and LOGO checks](50-bnd-and-logo-checks.md) · [52 Padring GDS check](52-padring-gds-check.md) ·
[10 Tapeout submission](10-tapeout-submission.md)

> Written 2026-08-18 for a submission intended to go out **2026-08-19**. Every manual
> reference was verified against the 03/2026 mini@sic manual in this site's PDK
> documentation directory (`$TSMC_65_HOME/doc/`) at the section and page cited. Where this
> page says the manual is *silent*, that is a measured absence with a stated control — §1.4.
>
> **No library revision codes, deck release codes, or GDS layer/datatype numbers appear
> here.** The repository is public and the vendor-collateral hook treats a
> family-plus-revision string as an inventory disclosure. Family names are public and used
> freely; the revisions and phantom-view paths the covering mail needs live in the untracked
> file named in §5.1.

---

## 0. Read this first: the two spent runs were not the same check

The working assumption going into this page was that both foundry runs measured the same
thing twice. **That is half right, and the half that is wrong is the most useful finding
here.** Both ran against the same retired 2026-08-10 stream (md5 `7f621496…`, unchanged
between them), but **IMEC replaced a different set of libraries each time**, and neither
time was it the right set.

From the `Libraries used for replacement :` block of each run's `Final_Report_*.rpt`:

| Run | Libraries replaced | `CompareCells` outcome |
|---|---|---|
| **17 Aug** | the **bond-pad** library only (family `tpbn65v`) | **"No identical cell names found!"** — matched **nothing** |
| **18 Aug** | the **IO-driver** library (`tphn65lpgv2od3_sl`) **and the standard-cell** library (`tcbn65lp`) | matched both: 14 IO/corner/filler cells, and the full standard-cell set |

Three consequences, each checkable:

1. **The 17-Aug run replaced one library and matched none of it.** Every count in that
   report that depends on cell interiors is a zero that measured nothing.
2. **The 18-Aug run was a genuine advance, not a repeat.** Real standard-cell diffusion was
   present for the first time. The device census went **6,420,952 → 8,599,725** (+33.9%),
   `PO.R.8` went **691 → 0** — the controlled result that closes
   [39](39-po-r8-resolved.md)'s black-boxing theory — and 157 rule categories fired for the
   first time. The `_dummy` in that archive's name is IMEC's pipeline naming, and the topcell
   is literally `..._dummy_dummy_WithSealRing`: they filled an already-filled derivative.
   The uniform **+160 nm per side** frame offset the coordinates show is visible directly in
   the header — the boundary grew `1640 × 2040` → `1640.32 × 2040.32`.
3. **The bond-pad library has never been successfully replaced, in either run.** It is
   absent from the 18-Aug replacement list entirely — the string `tpbn65v` appears **zero**
   times in that report (control: `tcbn65lp` appears three times). So `PM.*` results, the
   padring check and the whole bond-pad story remain structurally unmeasured after two runs.

**A likely single cause, worth one question rather than a guess.** Both archives declare
`#DEFINE PITCH_80_STAGGER` (three occurrences across the two), but this design uses **70 µm
staggered pad parts** — `PAD70GU`/`PAD70NU`, whose names are independently verified present
and correctly counted in the submitted stream ([52](52-padring-gds-check.md) §5). An
80 µm-pitch pad library would not contain 70 µm-pitch cell names, which would produce
exactly the "No identical cell names found!" we saw. `PAD80` appears nowhere in either
archive (control: `PAD70` is findable in both), so this is a strong inference, not a proof —
and it is Q2 in §7.

**What this changes for tomorrow:** the goal is not merely "send a newer file". It is to
send a newer file **and get all three libraries replaced in one pass, in the right order**.
That is a request we have to make explicitly, because two runs of not making it have now
cost two runs.

---

## 1. What IMEC actually asks for

### 1.1 There is no "Dry Run GDS" submission path — there are two deliveries

The repo has been reasoning about a "Dry Run vs Final GDS" choice the manual does not offer.

Per **§1.4(4)–(7)** there are exactly **two GDS deliveries from us**:

| Delivery | When | Cleanliness required |
|---|---|---|
| **Preliminary GDS** | ASAP, and at least **2 weeks before** the Europractice deadline (§1.4(4)) | **None.** Need not be DRC/ANT/BND clean; need not contain dummy filling, though it may (§1.4(4), §6.4) |
| **Final GDS** | **before** the Europractice deadline (§1.4(7)) | Must be DRC/ANT/BND clean **after** import of black-box back-ends **and** dummy filling (§6.5) |

The **"dry run"** the manual names is **not ours to send**. Per §1.4(6) it is a *TSMC-side
database check that IMEC initiates on our behalf*, after our preliminary GDS has been through
their import-and-decks loop, using the tape-out forms. Their sequence is:

1. we upload the preliminary GDS;
2. eptsmc **import** the layouts of our black-box TSMC IP, **run the decks** (DRC, ANT, BND),
   and send us the results;
3. eptsmc fill out the tape-out forms and **start a dry run at TSMC** (a database check, not
   a submission);
4. once the deck results are clean, the dry run is OK, and we have approved the tape-out form
   contents, final submission can proceed.

**So what goes out tomorrow is a preliminary GDS**, by the same route as the final one
(FTP + DDF, §12). Both August runs were this same preliminary loop. There is no separate
dry-run submission we have missed.

### 1.2 The order is IMPORT, then FILL, then decks — and it is load-bearing

§6.5 requires the final GDS to be clean *after import of the back-ends of black-box IP (if
any) and dummy filling* — import named first, fill second. §1.4(6) describes the preliminary
loop as **import → decks**, with fill not part of it at all, adding that they *recommend* we
fill at our side but it is not mandatory.

§7.1 supplies the precondition that closes the loop: eptsmc **will only run dummy filling on
a design already clean except for those violations that dummy filling itself solves**
(density, TCDDMY, max-OD-space), and only if we have not blanketed the design in fill-blocking
layers.

Read together: **a preliminary GDS cannot meet the precondition for their fill service.** The
18-Aug pass inverted the order — fill applied to an already-filled derivative of an
incompletely-imported stream — which is why its most valuable result (the standard-cell
import) arrived tangled up with 157 untriaged new categories and an unexplained CSR growth.
The covering mail must state the order explicitly (§5.2).

### 1.3 The requirements, itemised

Anything marked **[us]** is our obligation, not theirs.

| # | Requirement | Manual |
|---|---|---|
| R1 | Preliminary GDS must contain **all the CAD layers you will use** | §1.4(4), §6.4 |
| R2 | Std cells / IO / bond pads may be placed as **black boxes**; eptsmc import the real layouts | §7 (p.24) |
| R3 | **No seal ring in our GDS.** TSMC adds it; the area it takes is free | §6.1 |
| R4 | Origin ideally at the **lower-left corner of the design without seal ring** | §6.1 |
| R5 | **All four corners must have an empty triangle.** Cleaning `CSR.x.x` is *mandatory even when you have not added a seal ring*, or TSMC rejects the submission | §6.2 |
| R6 | Define the chip boundary with **metal layers**, not the P&R boundary layer; remove stray text layers outside the boundary | §6.2 |
| R7 | eptsmc run **DRC / ANT / BND only**. They do **not** run LVS | §7.1 |
| R8 | **ERC is ours to run and clean** **[us]** | §7.1 |
| R9 | LVS is ours; black-box LVS is acceptable, and foundry support has an application note for it | §7.1 |
| R10 | **Calibre is the signoff tool** and the only one eptsmc use; in a disagreement Calibre prevails | §7.1 |
| R11 | Antenna violations are **never acceptable** | §6.5 |
| R12 | The BND deck **must be run even if the pads are not TSMC's or the die is only probed** | §6.5 |
| R13 | Width / spacing / area / enclosure violations are the class TSMC will **certainly not** waive | §6.5 |
| R14 | Tell them **every IP used**: exact library families **and the complete path to the phantom view**, plus which SRAM/OTP macros **[us]** | §1.4(6) |
| R15 | Tell them **backlapping** (default 7 mils) and packaging intent; supply an on-scale bonding diagram if they package **[us]** | §1.4(6) |
| R16 | Deck switches for a wire-bond mini@sic: seal-ring switch **off**, wire-bond **on**, full-chip **on**, chip window set to the real die box (it becomes the tape-out window on the tape-out form) | §10 |
| R17 | Upload to **IMEC FTP** per the Design Delivery Form's instructions; **fill in and email the DDF to eptsmc after uploading** **[us]** | §12, §1.4(4) |
| R18 | Waivers: request the template from eptsmc; each needs zoom-in/zoom-out snapshots, severity as a deviation from the rule, and a justification | §6.5 |
| R19 | 65nm block is 1 mm², no shrink, min dimension 1 mm, max aspect 4:1, max 6 mm²; area beyond one block is chargeable per 0.1 mm² | §6.1 |

### 1.4 What the manual does **not** require — measured absences, each with a control

Each of these is something the repo has been treating as an obligation.

| Claimed obligation | Verdict | Control |
|---|---|---|
| A required **GDS file name** | **No such requirement** anywhere in the manual | `naming` matches elsewhere (library-naming figure captions), so the search was live |
| A required **top-cell name** | **No such requirement.** IMEC rename the topcell themselves anyway — theirs read `nanosoc_eth_chiplet_pads_dummy_WithSealRing` | as above |
| The chip must carry a **logo** | **The manual never mentions a logo at all** | `sealring` matches 17 times in the same file |
| A **fill statement** as a named artefact | **No such artefact.** A sentence in the covering mail is all that is needed | `statement` matches once, in the fill-script tutorial |
| An **"IP merge" deadline class** | **No such class.** There is exactly one "Europractice deadline"; §6.3's "merge" is IMEC merging designs on a shuttle — a chip-boundary and packaging topic, not a schedule one | `deadline` matches 5 times, `merge` 5 times; every hit read |
| A stream **format or compression** choice | Not mentioned; GDSII assumed throughout | `oasis` returns nothing while `tar.gz` matches in the same file |

**The deadline, now settled.** [48](48-imec-signoff-results-analysis.md) §0 records that David
has confirmed the **Final GDS date directly: 1 September**, and that the "Aug 18 IP-merge
cutoff" scenario is moot — consistent with §1.4/§6.3, which contain no such class. Deriving
from §1.4(4), the preliminary-GDS guideline (deadline − 2 weeks) fell on **18 August**. A
19 August preliminary is therefore **one day past the guideline but ~13 days inside the hard
deadline**. The residual scheduling question is not the date but the *turnaround* — Q1 in §7.

---

## 2. Which stream, and in what form

### 2.1 Which stream

Another lane is producing it, so this is specified by **property, not by tag**:

- [ ] From the **toolkit lineage** — `ASIC/eth-chiplet/build/<tag>/outputs/` — not from
      `ASIC/genus-innovus`, the retired engine that produced the stream both spent runs measured.
- [ ] **Route actually completed** for that build. `fp1505`'s did not
      ([45](45-measured-status-2026-08-18.md)); a stream can exist because `write_stream` ran
      even though route never finished.
- [ ] Built **after** the pad-corner rotation fix (`d93331f`). That fix is committed in
      `ASIC/genus-innovus/scripts/nanosoc_eth_chiplet_pads.io`, which is what
      `design.mk`'s `IO_FILE` points the toolkit build at, and the three live build trees
      already carry the corrected `R270/R0/R90/R180`. **Hazard, not a blocker:** a third copy
      at `ASIC/asic-toolkit/examples/nanosoc_eth_chiplet/floorplan/` still holds the old
      values — confirm the build read the fixed one rather than assuming it.
- [ ] Its **md5 recorded before upload**, with build tag, repo commit and dirty state.

### 2.2 In what form

| Property | Value | Why |
|---|---|---|
| Fill | **Unfilled** | §1.4(4) permits it; §7.1's precondition for their fill service cannot be met by a preliminary stream |
| Seal ring | **Absent** | R3 |
| Std cells, IO drivers, bond pads | **Black-box cell references** | R2 — the supported model, not a shortcut |
| Memory macros | **8 compiled macros, real vendor GDS merged** | we hold their back-ends; flag them as **not for replacement** |
| Origin / die | lower-left at (0,0), 1600 × 2000 µm | R4 |
| **Logo** | **Do not merge one. Send the un-logoed signoff stream.** | §2.3 |

### 2.3 The logo decision, and why it is "none" for this submission

Easy to get wrong, because [50](50-bnd-and-logo-checks.md) records a genuine fix that is
easy to over-read.

- Merging the **marker-tagged** logo (full or text-only) takes design-owned DRC from 140 to
  **2161**, with `LOGO.S.1` and `LOGO.R.4` each **saturated at the 1000-result cap** — their
  true counts have never been measured in any logoed stream built here
  (`scripts/ci/drc_submission_check.py`). Both IMEC archives confirm the saturation
  independently, and real library geometry did not move it. The often-quoted
  "5497 → 1134 improvement" is **not** one: both runs read the cap; only flat multiplicity moved.
- The **AP-only** variant (`LOGO_AP_ONLY=1`, default since 2026-08-18) drops the marker layer
  and takes `LOGO.S.1`/`LOGO.R.4` to a **real, uncapped zero**. That part is solid, reproduced
  twice, and IMEC's own `custom_drc` says the marker layer is "not a must have".
- **But AP-only is not clean.** It keeps the AP artwork, and the artwork is illegal on AP
  independent of placement: `AP.W.1.WB` ×12, `AP.S.1.WB` ×4, `AP.S.1.FC` ×4 — **20 real,
  unsaturated** results, exactly the "+20" the AP-only tooling reports. These are **width and
  spacing** violations, the class §6.5 says TSMC will *certainly not* waive (R13).
- **And it has never been merged into the shipping lineage.** No AP-only merged stream exists
  in any toolkit build tree — only the two superseded jack and text variants under
  `full-20260814/logo_variant_drc_20260817/`.

Every available variant puts real width/spacing violations into the stream; the manual asks
for no logo at all. For a **preliminary** GDS the logo buys nothing and costs either two
unreadable saturated counts or twenty never-waivable ones.

**Decision: no logo.** Do not set `SUBMIT_GDS`. This also keeps a cross-engine trap off
tomorrow's critical path — `make logo` lives in the retired engine's Makefile and writes to
*its* `outputs/` by default, so merging a toolkit stream means overriding both `GDS` and the
output path, and the result lands in a single mutable slot with no stream identity in its name.

**Carry into the Final GDS instead:** repair the AP geometry in the artwork, reserve a
routing-free keep-out for the mark plus its halo in the floorplan, and re-validate against a
full-library-merge check.

---

## 3. What must be true before sending

### 3.1 Identity — the lesson of the two spent runs

- [ ] `md5sum` of the exact uploaded file, recorded in the run log **and** quoted in the mail.
- [ ] Build tag and repo commit recorded beside it.
- [ ] **The uploaded filename distinguishes this stream from the last one** (a date or build
      tag in the name). Not a manual requirement (§1.4) — ours, because IMEC name the returned
      archive after the file we send, and two submissions with the same name yield two archives
      nobody can tell apart. See G2 in §4.

### 3.2 Structure — licence-free, run these

- [ ] `python3 scripts/check_padring_gds.py --gds <stream>` — 12 pad/corner/bond-pad families
      present, at expected counts, per-side order correct. This passed against the exact GDS
      IMEC checked ([52](52-padring-gds-check.md) §5), which is what makes it a trustworthy
      control rather than an untested script.
- [ ] Layer-map coverage check ([49](49-layer-map-coverage-check.md)) — every layer the stream
      carries is in the declared map, and every CAD layer we use is present (**R1**). Closes
      the doc-35 blindness where a census reads zero because the layer was never mapped.
- [ ] Pad-corner rotation confirmed in the *build's own* `scripts/` copy, not just in the
      source (§2.1).
- [ ] No stray text or marker geometry outside the chip boundary (**R6**).
- [ ] Exactly one top cell, no undefined references.

### 3.3 The corner trap — do not report a zero here

**A local `CSR.R.1` of 0 on a black-box stream is a false zero.** The corner cells stream as
empty structures, contribute nothing to the deck's `EXTENT`-derived boundary, and leave no
geometry to violate ([26](26-plan-to-submittable-gds.md) §2.3). With their obstruction
streamed onto the mask layers the same database reports **56**.

- [ ] Do **not** write "CSR.R.1 = 0" in the covering mail. State the measured 56, say it
      returns at their import, and ask Q3.
- [ ] Know what the rotation fix does **not** buy: `PCORNER_G` is a uniform solid block that
      is geometrically identical under all four rotations, so the fix clears IMEC's mechanical
      padring orientation error but **cannot** clear `CSR.R.1`, which is a placement/keep-out
      problem gated on an outstanding ESD ruling.

### 3.4 Decks, stated honestly rather than re-run

Nothing here blocks the send — a preliminary GDS need not be clean (§1.4(4)). But each must be
**stated**, because an omission reads as a pass:

- [ ] DRC: quote the run directory and the design-owned / vendor-macro split.
- [ ] **Antenna: state that it has never been run against the foundry antenna deck.** The
      signoff deck contains no antenna rulechecks at all — its only `AN.*` check is a
      differential-pair matching rule — so the "0 across every rulecheck" figure in
      `docs/DRC_WAIVER_INVENTORY.md` is a zero that measured nothing. R11 gives antenna no
      waiver route, so do not let it look covered. (IMEC's own antenna pass is real, but it is
      against the retired stream.)
- [ ] BND: quote the measured result **and the pad pitch our parts require** — see Q2/Q4.
- [ ] ERC (**R8**, ours): [51](51-erc-pg-labels.md)'s fix partially lands on `fp1505` —
      VDD/VSS label, VDDIO/VSSIO still do not. Say which state this stream is in; do not claim
      it closed.
- [ ] LVS: black-box LVS ran 2026-08-10 and returned **LVS INCORRECT**, unresolved. Say so —
      the older "never run" phrasing is now wrong in the direction of sounding better.
- [ ] ROM content verification re-run against **this** stream, with line 1 of the log naming
      that same file (the evidence slot is a single mutable file with no stream identity in its name).
- [ ] `PO.R.8`: **now closed** — 691 → 0 under the 18-Aug full standard-cell merge. Report it
      as resolved rather than as a waiver request.

### 3.5 Metadata that must accompany the upload (R14, R15, R17)

- [ ] **DDF filled in and emailed to eptsmc after the upload completes.** *No Design Delivery
      Form exists anywhere in this repository* — searched, with a control (the same search
      finds `package_submission.sh`). Obtain it from eptsmc **before** the upload.
- [ ] IP inventory: all three library families **with revisions and the complete path to each
      phantom view** (R14 asks for the path, not just the name), plus the 8 memory macros by
      name, explicitly flagged as already carrying real merged GDS and **not** to be replaced.
- [ ] Backlapping (default 7 mils) and packaging intent stated.

---

## 4. `scripts/ci/package_submission.sh` — audit

The script is careful and well-defended. Every gap below is about **audience**: it assembles a
*hand-off bundle for whoever holds the foundry data*, which is a different deliverable from *a
preliminary GDS upload to eptsmc*. It is not broken; it is aimed elsewhere. **No changes made
in this pass.**

| # | Gap | Evidence |
|---|---|---|
| G1 | **Packages three artefacts IMEC will not use, and treats them as mandatory.** `*_pnr.v`, `*_pnr.sdf`, `*_syn.sdc` are declared deliverables whose absence fails the completeness gate. Per R7 eptsmc ask only for the layout and run no LVS. The SDF alone is ~360 MB | the `MISSING+=()` gate; manual §7.1 |
| G2 | **Normalises the filename to `nanosoc_eth_chiplet_pads.gds`, destroying stream identity.** No manual rule requires this (§1.4). IMEC name the returned archive after the submitted file, so identical names produce indistinguishable archives — the exact failure that hid two runs on one stream | the `cp -p "$GDS" "$STAGE/$BLOCK.gds"` step |
| G3 | **No DDF, and no slot for one.** R17 makes it the one mandatory accompanying document; the repo has no copy | manual §12; repo-wide search, with control |
| G4 | **The IP inventory R14 demands is not produced.** `MANIFEST.txt` names the three families in prose but gives no revisions, no phantom-view paths, and does not list the 8 memory macros. Given §0, the manifest is also the natural place to say *which* libraries must be replaced — the field IMEC got wrong twice | manual §1.4(6) vs MANIFEST item 1 |
| G5 | **Backlapping and packaging (R15) never stated** | manual §1.4(6) |
| G6 | **Collects Innovus reports, not the Calibre DRC/ANT/BND summaries** — and R10/R7 make Calibre the only evidence eptsmc act on. MANIFEST item 4 admits the reports are `check_drc` over an incomplete stream, which is honest, but leaves the bundle with no signoff-grade deck evidence at all | `cp -rp "$REP"`; MANIFEST item 4 |
| G7 | **`MANIFEST.txt` cites the retired engine as source of truth.** Item 1 points at `gds_merge_list` in `ASIC/genus-innovus/scripts/config.tcl`, but the shipping lineage is the toolkit. A provenance error in the one file the recipient is told to read | MANIFEST heredoc item 1 |
| G8 | **Nothing verifies the top cell inside the stream.** The file is renamed on the way in but the top-cell name is never checked or recorded, and "one top cell, no undefined references" is never asserted | no GDS-reading step in the script |
| G9 | **The completeness gate cannot discriminate.** It tests existence and non-emptiness only; a truncated or structurally wrong stream passes. `check_padring_gds.py`, the layer-map coverage check and `drc_submission_check.py` all exist and none is wired in | the gate block |
| G10 | **`SUBMIT_GDS` is handled well but ungoverned.** The override is loud and refuses to fall back — correct. But nothing runs `drc_submission_check.py`, so a logo-merged stream carrying two saturated LOGO counts can be packaged silently | `SUBMIT_GDS` block vs `scripts/ci/drc_submission_check.py` |
| G11 | **The CI caller is still broken.** `.github/workflows/asic-gds.yml` pins `ASIC_DIR: ASIC/genus-innovus` (line 79), whose `outputs/` has never held a stream, so the packaging step exits 1 on every run. The script's own header identifies this; the workflow was never updated | workflow line 79 vs script header |
| G12 | **ROM evidence still not collected** — correctly declared as a gap in MANIFEST item 7, still a gap | MANIFEST item 7 |
| G13 | **Wrong delivery shape.** The output is a zip for a "submission desk". R17 wants the GDS on IMEC FTP and the DDF by email | manual §12 |

**Verdict for tomorrow:** use `package_submission.sh` to produce the *internal* record — it is
good at provenance, hashes and declaring gaps — and upload the **stream alone** to the FTP with
the DDF by mail. Do not send the zip as the submission.

---

## 5. The covering mail

### 5.1 Where the strings that cannot live here are kept

The three replacement library **families** are `tcbn65lp` (standard cells),
`tphn65lpgv2od3_sl` (IO drivers) and `tpbn65v` (bond pads). Their **revision codes** and the
complete phantom-view paths R14 requires are in the untracked
`docs/tapeout/27-broker-questions-SEND-NOW.md` — untracked deliberately, for the reason
[27](27-broker-correspondence-NOT-TRACKED.md) gives: this repository is public, and an
inventory of revisions is commercial information about the site. Fill them in from there; do
not copy them back into a tracked file.

### 5.2 What the mail must say

1. **This is a preliminary GDS** for `nanosoc_eth_chiplet_pads` on the 65LP mini@sic,
   wire-bond, die 1600 × 2000 µm, origin lower-left, **no seal ring** (§6.1).
2. **The exact filename and its md5**, plus a sentence saying this stream is **new** and
   supersedes the 2026-08-10 stream both previous runs checked. **Ask them to quote the md5 of
   the file they check** in their report.
3. **All three replacement libraries**, with revisions and the complete phantom-view path each
   (**R14**) — and, given §0, say plainly: *the previous two runs replaced the pad library
   alone (matching nothing) and then the IO and standard-cell libraries without the pads;
   please replace all three in this pass.* Name the 8 memory macros as **already merged, not
   for replacement**.
4. **The stream is unfilled** and carries no seal ring. One sentence; no separate artefact is
   required (§1.4).
5. **The order, explicitly: IMPORT all three black-box libraries first, then dummy filling if
   you are running it, then the DRC / ANT / BND decks** — per §1.4(6) and §6.5. Note that a
   preliminary stream cannot meet §7.1's precondition for their fill service, so we expect
   import-then-decks and are content for fill to wait.
6. **Our pad parts are 70 µm staggered** (`PAD70GU`/`PAD70NU`); both previous reports declared
   an 80 µm pitch switch. Ask them to confirm the pitch and the matching pad library (Q2).
7. **Backlapping 7 mils (default) and the packaging intent** (**R15**).
8. **What we already know is not clean**, stated rather than discovered: the corner `CSR.x.x`
   position (§3.3), antenna never run against the foundry deck, black-box LVS returning
   INCORRECT, and the PG-label ERC state. §1.4(4) means none of this blocks a preliminary GDS
   — but an omission reads as a pass.
9. **The DDF accompanies the upload** (**R17**).

---

## 6. Reading the returned report — before any count

**This is the section that matters most.** The 17-Aug run's replacement matched nothing, and
every FEOL number in it is therefore a zero that measured nothing. A report can be read cover
to cover and look reassuring while having checked no transistor at all.

**Read all six of these before a single violation count.** All live near the top of
`design/reports/Final_Report_*.rpt`.

| # | What to read | Where | Good | Bad — and what it means |
|---:|---|---|---|---|
| 1 | **`Gds-file :` / `Layout Path(s):` and the md5** | report header | names the file we uploaded, with our md5 | names an older file, or a `_dummy` derivative of a previous submission → the run measured a stream we did not send. **Stop.** Everything downstream is about a different chip |
| 2 | **`Libraries used for replacement :`** | report header | **three** paths: standard cells, IO drivers, **and bond pads** | fewer than three, or a family/revision we did not name. 17 Aug listed one; 18 Aug listed two, neither the pads. Any FEOL number for an unreplaced family is void |
| 3 | **`CompareCells`** — one block **per replaced library** | after the header | `Identical cell names:` followed by a real list | **`No identical cell names found!`** → that library matched **nothing**. Our padframe names and counts are independently verified correct ([52](52-padring-gds-check.md) §5), so this is their side, not ours |
| 4 | **`DevCheck` → `Total number of devices:`** | after CompareCells | **millions.** 6,420,952 with pads only; 8,599,725 with std cells + IO | zero or a few thousand → nothing was imported |
| 5 | **The declared `#DEFINE` set, per deck** | each deck's header | full-chip on, chip window = our die box, seal-ring switch off, **70 µm staggered pitch** | `PITCH_80_STAGGER` (what both runs declared) → wrong pad geometry basis. §11 says CSR and floating-gate counts differ between us and them for exactly this reason |
| 6 | **`Topcell :` and `Boundary :`** | report header | one `_WithSealRing` suffix; boundary = our die + their seal-ring frame | `_dummy_dummy_` → they filled an already-filled derivative. A boundary that grew again (e.g. `1640 → 1640.32`) is a second frame offset, i.e. a re-run on their own output |

**Only now read the counts. And when you do:**

- `N (M)` is **hierarchical (flat)**. It is *not* count (capped).
- **Calibre caps at 1000 and writes the truncated value into *both* fields.** Any rulecheck
  reading exactly 1000 is **saturated**: the true count is unknown and unbounded above. It is
  not "1000 violations".
- A **0** is meaningful only if the layer it inspects carries geometry in the checked stream.
  `PM.W.1` reads zero on our streams because there is no pad-metal geometry to measure, not
  because the pad metal is legal ([50](50-bnd-and-logo-checks.md) Part A).
- A count that **grew** between runs may be a merge artefact rather than a new defect: several
  of the 157 newly-firing categories in the 18-Aug archive are capped and plausibly
  duplication noise, untriaged either way.
- Before treating any category as clean, **name what it ran over.**

---

## 7. Still open with the broker

Pruned against the manual — every question it already answers has been removed. Long-form
drafts remain in the untracked `docs/tapeout/27-broker-questions-SEND-NOW.md`; this is the
residue that genuinely needs an answer.

| # | Question | Why it survived the manual | Urgency |
|---:|---|---|---|
| **Q1** | **Turnaround, not the date.** The Final GDS date (1 September) is confirmed. What we need instead: **how long does your import-and-decks loop take**, what is the **cut-off for a revised stream**, and does a 19 August preliminary still leave room for a second corrected pass before 1 September? | §1.4(4) gives a "2 weeks before" guideline but no turnaround figure, and we have now spent two loops without a usable result | **High** — it sets how many attempts remain |
| **Q2** | **Which bond-pad library will you use, and at what pad pitch?** Two runs, and the pad library has been replaced once (matching nothing) and then omitted. Our parts are **70 µm staggered**; both your reports declare an **80 µm** pitch switch. Please confirm the pitch and use the matching library — and replace **all three** libraries in one pass | The manual says they import our black boxes (§7) but nothing about what happens when the match fails. This is the defect that made an entire report's FEOL numbers meaningless | **Highest** — without it the next report is untrustworthy too |
| **Q3** | **Die corners: what must be empty, to what dimension, for this process — and which remedy do you accept?** (remove the corner cells and backfill; a chamfer at your import; or move the pad ring inward). If the cells go, how do we keep VDDIO/VSSIO/VDD/VSS ring continuity and the ESD arrangement? Note the rotation fix is applied but cannot clear this — the cell is geometrically identical under all four rotations | §6.2 makes cleaning `CSR.x.x` mandatory and rejection-grade but gives no dimension for this process and lists no accepted remedies | **High** — the one rejection-grade item visible from here |
| **Q4** | **Send your exact deck switch set, and a fuller by-cell breakdown for CSR.** §10 settles the seal-ring, wire-bond, full-chip and chip-window switches, so only the ambiguous ones remain: the low-power flavour switch, the WLCSP seal-ring switch (active as shipped, and it changes the seal-ring/CSR derivation for a wire-bond design), mixed-scheme, and low-density checking. Separately, **~800 of 804 `CSR.R.2:D`, 644 of 644 `CSR.R.2:B` and 96 of 96 `CSR.EN.8` hits are unattributed** — your report truncates before naming the cells. Please send the full attribution | §10 gives a worked example for a different node and says the rest follow "similarly"; §11 confirms switch differences drive count disagreements. The attribution gap is in their output, not the manual | **High** — currently the largest open DRC item |
| **Q5** | **Is your import a structure-level replacement or a merge?** Our pad structures are placed but empty. Should they stay empty, or carry their LEF obstruction geometry? Would anything left inside them be discarded, or duplicated against what you import? | §7 establishes the black-box model but not what happens to content inside a black-boxed structure. Bears directly on Q2 | Medium |
| **Q6** | **The bond-pad deck command file named in §1.4(5) is not in our installation.** Please supply it, or confirm the revision we hold is what you accept for a 70 µm staggered wire-bond ring | §1.4(5) names the document; it is simply absent here. **Route to foundry support, not eptsmc** | Medium |
| **Q7** | **What is the actual seal-ring width for this process?** §6.1 gives it only as a symbol with a worked example at a different value | Needed to state packaged die size and finalise the bonding diagram | Medium |
| **Q8** | **`PVDD2POC_G` — "multiple cells in digital domain".** We instantiate it once per side (4 total), all on the same VDDIO net. Is this cell expected **once per ring**? No POC datasheet is available to us | New in the 18-Aug archive; not addressed anywhere in the manual | Medium |
| **Q9** | **Confirm the area and seat.** 3.2 mm² against a 1 mm² block (§6.1), aspect 1:1.25, inside the 6 mm² ceiling. Confirm the extra-area charge is applied and the seat booked | §6.1 gives the mechanism, not our invoice | Administrative — **route to sales/PO** |

**Removed as answered — do not ask these.** Whether a seal ring goes in our GDS (§6.1 — no);
whether black-box submission is supported and who imports (§7 — supported, they do); whether
the preliminary GDS must be clean (§1.4(4), §6.4 — no); which decks they run and whether LVS is
among them (§7.1 — DRC/ANT/BND, no LVS); whether dummy fill is mandatory on our side
(§1.4(6), §7.1 — no, but their service has a precondition); why `PO.R.8` fires on black boxes
(§11 — **and it is now empirically closed at 0 under a real merge, so drop the waiver request
entirely**); that `LUP.6` only appears after their import (§7); whether a logo is required
(never mentioned); whether a filename or top-cell name is imposed (never mentioned); and
whether an "IP merge" changes the deadline (no such class — §6.3 is about chip boundaries; the
date is confirmed as 1 September).

**Three mailboxes, per §1.3 of the manual.** Submission questions (Q1–Q5, Q7, Q8) to the
tape-out submission address; the deck-delivery item (Q6) and the black-box LVS application note
to foundry support; Q9 to sales/PO. Do not let the PDK requests queue behind the submission thread.

---

## Related

- [48 — IMEC signoff results analysis](48-imec-signoff-results-analysis.md) — what the two runs did and did not measure
- [50 — BND and LOGO checks](50-bnd-and-logo-checks.md) — the BND comparison and the AP-only logo measurement
- [52 — Padring GDS check](52-padring-gds-check.md) — the CompareCells surprise, and the local check that clears our side
- [49 — Layer-map coverage check](49-layer-map-coverage-check.md) — the pre-Calibre layer census
- [26 — Plan to a submittable GDS](26-plan-to-submittable-gds.md) — exit criteria, and the corner-check trap
- [10 — Tapeout submission](10-tapeout-submission.md) — the bundle and the broader hand-off questions
- [45 — Measured status 2026-08-18](45-measured-status-2026-08-18.md) — what is actually signed off

---

[← 48 IMEC signoff results](48-imec-signoff-results-analysis.md) · [index](00-index.md)
