# NanoSoC Ethernet Chiplet — Innovus & Tapeout Guide

A working guide to driving the Cadence flow in this repository and getting a GDSII you
can actually submit. It documents **this** design on **this** site — real paths, real
message IDs, real numbers measured from real runs — not generic Innovus tutorial
material. Where something has not been verified, it says so.

> **A note on paths and release names.** This repository is **public**, and TSMC's
> collateral is licensed to this site — an absolute mount point plus a revision-coded
> release directory together form an *inventory* of what the site holds, which the
> licence does not permit publishing. So these pages write site locations as the
> variable the flow already defines (`$TSMC_65_HOME`, `$MEM_BASE`, `$PHYS_IP`,
> `$IP_LIBRARY_ROOT`, `$CDS_INSTALL`, `$INNOVUS_HOME`) and replace vendor release codes
> with `<rev>`. **These are redactions, not real shell variables** — resolve them against
> your own installation with `ls`, or use
> `ASIC/tech_wrappers/tsmc65/scripts/pdk_paths.sh`, which globs the release directory
> rather than naming it. `ci/check-vendor-collateral.sh` enforces this on every commit
> and every push.

**Design:** `nanosoc_eth_chiplet_pads` — TSMC 65nm LP, 9 metal (`9M_6X1Z1U`),
die 1600 × 2000 µm, `tcbn65lp` standard cells, `tphn65lpgv2od3_sl` IO, `tpbn65v`
staggered bond pads.
**Tools:** Genus (synthesis) → Innovus 21.11-s130_1 in **stylus** mode (P&R) → Calibre (DRC).

---

## Read this in one of two ways

**"I need a GDSII this week."** → [01](01-flow-overview.md) → [09](09-signoff-checklist.md)
→ [11](11-known-issues.md) → [10](10-tapeout-submission.md). That is the shortest path
from nothing to a hand-off bundle, plus an honest account of what is still open.

**"I want to actually understand the tool."** → read in order. [02](02-innovus-basics.md)
is the highest-value page: it teaches the interactive session, `get_db`, and the three
self-documentation commands that make Innovus stop being opaque.

---

## Pages

| # | Page | What it covers |
|---|---|---|
| 01 | [Flow overview](01-flow-overview.md) | The four stages, make targets, artefacts, resume model, measured timings |
| 02 | [Innovus basics](02-innovus-basics.md) | Interactive sessions, `get_db`, `-help` / `help` / `man`, the GUI |
| 03 | [Floorplan](03-floorplan.md) | Die vs core geometry, `CORE_TO_IO`, macro placement, halos |
| 04 | [Power plan](04-power-plan.md) | Power intent, rings, stripes, `route_special`, the filler trap |
| 05 | [Place, CTS, route](05-place-cts-route.md) | Placement, clock tree, routing, optimisation phases, density |
| 06 | [Fill, antenna, bond pads](06-fill-antenna-bondpads.md) | Filler cells, ANTENNA diodes, the staggered bond ring |
| 07 | [Reading reports](07-reading-reports.md) | Every report file, what good looks like, what to grep for |
| 08 | [Debugging](08-debugging.md) | Method, illustrated by real defects found in this design |
| 09 | [Signoff checklist](09-signoff-checklist.md) | What must be true before you submit |
| 10 | [Tapeout submission](10-tapeout-submission.md) | The bundle, and the questions to settle with your broker |
| 11 | [Known issues](11-known-issues.md) | Open problems on this design, and what has been ruled out |
| 12 | [Calibre DRC](12-calibre-drc.md) | The working headless invocation, and why the in-flow one never ran |
| 13 | [LEC](13-lec.md) | Post-P&R equivalence — the harness, and what its two 2026-08-08 runs did and did not prove |
| 14 | [DRC triage](14-drc-triage.md) | The 102 surviving violations, classified and root-caused |
| 15 | [PG opens analysis](15-pg-opens-analysis.md) | Evidence and ranked hypotheses for the unexplained opens |
| 16 | [Open defects](16-open-defects.md) | The hold-timing defect, DRV, GWEN, and other live findings |
| 17 | [Silent no-ops](17-silent-noops.md) | Eight commands that ran, logged nothing alarming, and did nothing |
| 18 | [Message census](18-message-census.md) | Every message ID this design raises, counted and diagnosed |
| 19 | [Timing audit](19-timing-audit.md) | R1–R14: constraint and timing-integrity findings |
| 20 | [Synthesis audit](20-synthesis-audit.md) | The Genus side, measured |
| 21 | [Physical audit](21-physical-audit.md) | P1–P14: floorplan, PG, vias, rows, fill, pad ring |
| 22 | [Synthesis flow notes](22-synthesis-flow-notes.md) | The *why* behind `1b_synthesis_eval.tcl` — measurements and tool traps |
| 23 | [P&R flow notes](23-pnr-flow-notes.md) | The *why* behind the `2b`/`3b`/`4b` eval stages and `pnr_utils.tcl` |
| 24 | [D2D link handover](24-d2d-link-physical-handover.md) | The D2D link's physical-implementation gaps, handed to the P&R side |
| 25 | [What remains, explained](25-what-remains-explained.md) | The physical-verification picture, in prose |
| 26 | [Plan to a submittable GDS](26-plan-to-submittable-gds.md) | The route from here to something a shuttle will accept |
| 27 | [Broker questions](27-broker-questions-SEND-NOW.md) | The questions only the broker/fab can answer |
| 28 | [DRC status and attribution](28-drc-status-and-attribution.md) | Every DRC/ANT/BND result, decomposed by who owns it |
| 39 | [`PO.R.8` resolved](39-po-r8-resolved.md) | Why 691 of 837 DRC results are a black-boxing artefact, how that was proved, and the cell-scoped waiver built on it |
| 43 | [DRC on `fp1505`](43-drc-fp1505.md) | The uncapped Calibre run over the short-free build, like-for-like against the shipping stream, and every check classified measured / unmeasurable |
| 44 | [eth ROM sim/silicon divergence](44-eth-rom-sim-divergence.md) | Why the eth `sim_divergence` WARN is a declared, deliberate divergence and not a defect, and why regenerating the slot would be a false green |
| 45 | [Measured status, 2026-08-18](45-measured-status-2026-08-18.md) | A freshly measured, whole-project status: git and pin reachability, the build inventory, every signoff verdict with what it actually measured, the physical numbers with their build named, and the flist that really builds |
| 48 | [IMEC signoff results analysis](48-imec-signoff-results-analysis.md) | Cross-check of IMEC's foundry DRC/ERC/antenna results against our own local Calibre checks, with GDS provenance, root causes, and a prioritized punch list |
| 49 | [Layer-map coverage check](49-layer-map-coverage-check.md) | `check-layer-map-coverage`: diffs a GDS's actual layer/datatype census against a declared layer map before any Calibre run, closing the doc-35 blind spot; validated against a real IMEC foundry report |
| 50 | [BND and LOGO checks](50-bnd-and-logo-checks.md) | The bond-pad/seal-ring BEOL deck, consolidated into `make bnd` and compared rule-by-rule against IMEC's real report; the LOGO keep-out rules, three ad hoc experiments consolidated into `make drc-logo-check`, and the measured AP-only fix |
| 51 | [Calibre ERC: power/ground labels](51-erc-pg-labels.md) | The standalone ERC flow (`run_erc.sh`) built after IMEC's "No labels found in topcell" signoff error; what ERC checks here vs. historically; measured validation against IMEC's own GDS and against `fp1505`/`full-20260814` |
| 52 | [Padring GDS check](52-padring-gds-check.md) | The broker's CompareCells/Padringcheck surprise, and the local GDS-level check that would have caught its class |
| 53 | [Gate-promotion plan](53-gate-promotion-plan.md) | Phased plan from four report-only gates to a trustworthy blocking system: promotion criteria, new orientation/CSR/PVDD2POC gates, sequencing, and the full IMEC-tool parity map |
| 54 | [`check_fp_pg.tcl` vs. the toolkit's macro-stripe census](54-fp-pg-vs-macro-stripe-census.md) | What each PG/floorplan check actually measures, worked geometry showing they are not redundant, integration-robustness comparison, and today's live status: the toolkit gate is not disabled, it is unproven and was actively blocking |
| 55 | [IMEC preliminary-GDS submission checklist](55-imec-preliminary-gds-submission-checklist.md) | What eptsmc actually require (verified section by section, including what they do *not*), which stream to send and in what form, the pre-send gate, the covering mail, and the six things to read in the returned report before any violation count — plus the `package_submission.sh` gap list and the pruned broker questions |

*(29–38, 40–42, 46–47 exist but are not yet listed here.)*

**Pages 22 and 23 are companions to the evaluation scripts.** Those scripts are written
to be read by someone learning the flow, so their comments explain *what each stage
does*; the notes files hold the *why* — the measurements, the one-off findings and the
tool behaviours that cost someone a day. A script comment saying "(Note 7.)" means
page 22 for synthesis, page 23 for P&R.

> **Pages 11–21 describe the 2026-08-06 run.** The 08-07 run closed hold and regressed
> setup — see [23](23-pnr-flow-notes.md) note 1 before quoting any timing number here.

---

## Four things to know before you start

**1. Exit status lies.** Genus and Innovus both exit `0` after printing an error and
doing nothing. Three P&R stages once "passed" in under a minute because `-f` is not a
valid stylus argument — the tool printed a usage message and exited zero, and the only
symptom was a missing GDS hours later. Every stage target in the Makefile therefore
asserts on an **artefact**, never on `$?`. Preserve that discipline in anything you add.

**2. Warnings are where the bodies are.** `IMPSP-5110` reads like noise. It meant a
GDSII shipped with **zero filler cells** and 95,568 free-site gaps. Read the warnings you
do not recognise, and use `man <MSGID>` — the logs literally tell you to and almost
nobody does.

**3. The GDS is not self-contained.** `gds_merge_list` merges only the 8 memory macros.
Standard cells, IO drivers and bond pads are empty references, because this site's PDK
ships LEF and liberty but no GDS or CDL for them. Every DRC number this flow produces is
a routing/PG check, **not signoff DRC**, and LVS cannot run here at all. See
[10](10-tapeout-submission.md).

**4. Experiments are cheap if you use the snapshots.** The flow writes `_placed` and
`_cts` databases specifically so you can resume rather than re-run 5 hours from
placement. Load one, change one thing, measure. See [02](02-innovus-basics.md).

---

## Before you trust any signoff number: the node-level traps

The pages here describe **this design**. A separate page describes **the node** — the
PDK, the stream-out map and the signoff tools — and it is where the traps live that
will follow you to the next chip on TSMC 65:

### → [`ASIC/tech_wrappers/tsmc65/README.md`](../../ASIC/tech_wrappers/tsmc65/README.md) — §1 is a seven-row traps index

Referred to by name rather than by count, because counts drift and names do not:

- **the PDK stream-out map** is a transform of a *layout-editor* map and was never a
  signoff artefact;
- **LEF obstruction streamed as metal** — it was 68.8% of all metal in our GDS and
  caused every antenna result;
- **bond-pad openings are declared `OBS`**, so the blanket fix for the previous trap
  silently deletes them;
- **`NAME <layer>/LEFPIN`** — without it, macro pins stream their shapes and not their
  names, and boxed leaves extract with no pins at all;
- **Calibre density `Result Count = 1`** can mean thousands of failing windows, and the
  `.density` files are *failure lists*, not window maps;
- **`PO.R.8` inside vendor memories** is an artefact of black-boxing, not a vendor
  defect — and checking the macro standalone cannot tell you which;
- **"the tool did not complain" is not verification** — census the stream.

That page closes with the habit underneath all seven: *what would this look like if I
were wrong?* Three of the conclusions it corrects were wrong in the direction of
blaming somebody else.

---

## State of the design

As of **2026-08-06**, the flow runs unattended end-to-end and produces a filled,
timing-closed GDSII. `CORE_TO_IO` was raised 50 → 70 µm to clear the inner staggered bond
pads, which shrank the core from 1230×1630 to 1190×1590 and required re-placing 17 of the
21 macros; see [03](03-floorplan.md) for the full dependency chain.

**HOLD TIMING DOES NOT CLOSE, and never has.** `report_timing_summary` emits no hold
section at all — the headline "WNS +0.079, 0 failing endpoints" is **setup only**, and
the tool's own closing line is labelled `timing.setup.wns`. The hold numbers are
**WNS −1.167 ns, TNS −66,212 ns, 96,545 violating paths**, sitting in the stage log
where nothing was reading them. The baseline is the same (−1.149, 93,078), so the
July GDSII has it too. Root cause and proposed fix: [16](16-open-defects.md).

**Not done, and not close to done** — read [09](09-signoff-checklist.md) and
[11](11-known-issues.md) before promising anyone a tapeout date:

- cell-level GDS merge (must happen at the foundry)
- metal density fill — `add_metal_fill` appears nowhere in this flow
- LVS — never run, and cannot run on this site
- logical equivalence (`make lec`) — **the check most worth running**, because a previous
  build silently lost an entire datapath to Genus unused-logic removal
- seal ring and scribe — not in the design data
- 329 PG opens — unexplained, two hypotheses already falsified

---

## Conventions in these pages

- Commands shown as `make <target>` run from `ASIC/genus-innovus/`.
- Commands shown at a `@innovus` prompt assume you have sourced `config.tcl` and
  `read_db`'d a design — see [02](02-innovus-basics.md).
- Message IDs (`IMPSP-5110`, `GLO-34`) are quoted verbatim so they are greppable in logs.
- Numbers quoted as "measured" come from real runs on `srv03335` and are reproducible;
  anything inferred rather than observed is labelled as such.
