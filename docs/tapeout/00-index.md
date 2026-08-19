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

The numbering is the order pages were written, not a reading order. Read the groups.

### The flow, stage by stage — start here

| # | Page | What it covers |
|---|---|---|
| 01 | [Flow overview](01-flow-overview.md) | The four stages, make targets, artefacts, resume model, measured timings |
| 02 | [Innovus basics](02-innovus-basics.md) | Interactive sessions, `get_db`, `-help` / `help` / `man`, the GUI |
| 03 | [Floorplan](03-floorplan.md) | Die vs core geometry, `CORE_TO_IO`, macro placement, halos |
| 04 | [Power plan](04-power-plan.md) | Power intent, rings, stripes, `route_special`, the filler trap |
| 05 | [Place, CTS, route](05-place-cts-route.md) | Placement, clock tree, routing, optimisation phases, density |
| 06 | [Fill, antenna, bond pads](06-fill-antenna-bondpads.md) | Filler cells, ANTENNA diodes, the staggered bond ring |
| 22 | [Synthesis flow notes](22-synthesis-flow-notes.md) | The *why* behind `1b_synthesis_eval.tcl` — measurements and tool traps |
| 23 | [P&R flow notes](23-pnr-flow-notes.md) | The *why* behind the `2b`/`3b`/`4b` eval stages and `pnr_utils.tcl` |

### Reading it, debugging it, signing it off

| # | Page | What it covers |
|---|---|---|
| 07 | [Reading reports](07-reading-reports.md) | Every report file, what good looks like, what to grep for |
| 08 | [Debugging](08-debugging.md) | Method, illustrated by real defects found in this design |
| 09 | [Signoff checklist](09-signoff-checklist.md) | What must be true before you submit, and where each check can run |
| 10 | [Tapeout submission](10-tapeout-submission.md) | The bundle, and the questions to settle with your broker |
| 11 | [Known issues](11-known-issues.md) | Open problems on this design, and what has been ruled out |
| 12 | [Calibre DRC](12-calibre-drc.md) | The working headless invocation, and why the in-flow one never ran |
| 13 | [LEC](13-lec.md) | Post-P&R equivalence — the harness, and what its runs did and did not prove |

### Audits of the 2026-08 baseline runs — point-in-time

These measured the `ASIC/genus-innovus` runs of 2026-08-05 → 08-08. **The mechanisms they
explain are the value; the counts are stale.** Each carries a status banner naming what it
measured and where the current number lives.

| # | Page | What it covers |
|---|---|---|
| 14 | [DRC triage](14-drc-triage.md) | 102 violations classified and root-caused; the fill-stage ordering fix |
| 15 | [PG opens analysis](15-pg-opens-analysis.md) | Evidence and ranked hypotheses — root cause later found, see 36 and 42 |
| 16 | [Open defects](16-open-defects.md) | Hold source latency, DRV, GWEN, and other findings of that run |
| 17 | [Silent no-ops](17-silent-noops.md) | Eight commands that ran, logged nothing alarming, and did nothing |
| 18 | [Message census](18-message-census.md) | Every message ID this design raises, counted and diagnosed |
| 19 | [Timing audit](19-timing-audit.md) | R1–R14: constraint and timing-integrity findings, from in-flow analysis |
| 20 | [Synthesis audit](20-synthesis-audit.md) | The Genus side, measured |
| 21 | [Physical audit](21-physical-audit.md) | P1–P14: floorplan, PG, vias, rows, fill, pad ring |
| 24 | [D2D link handover](24-d2d-link-physical-handover.md) | The D2D link's physical-implementation gaps, handed to the P&R side |
| 25 | [What remains, explained](25-what-remains-explained.md) | The physical-verification picture in prose — counts superseded |

### Where the project stands

| # | Page | What it covers |
|---|---|---|
| 45 | [Measured status, 2026-08-18](45-measured-status-2026-08-18.md) | Whole-project status, every claim tagged MEASURED / INHERITED / UNMEASURED |
| 26 | [Plan to a submittable GDS](26-plan-to-submittable-gds.md) | The route to a shuttle-acceptable stream — **stale**, several steps removed by decision |
| 37 | [Signoff stage/target audit](37-signoff-stage-target-audit.md) | What `ci/signoff.yaml` actually invokes, and which stages short-circuit before running |
| 46 | [Why gate1 aborted](46-why-gate1-aborted.md) | The synthesis abort, and why re-running does not help |
| 53 | [Gate-promotion plan](53-gate-promotion-plan.md) | From report-only stages to blocking gates: criteria, order, IMEC-tool parity map |

### DRC, ERC, and what the checks can actually see

| # | Page | What it covers |
|---|---|---|
| 28 | [DRC status and attribution](28-drc-status-and-attribution.md) | Every DRC/ANT/BND result, decomposed by who owns it |
| 43 | [DRC on `fp1505`](43-drc-fp1505.md) | The uncapped Calibre run, like-for-like against the shipping stream |
| 39 | [`PO.R.8` resolved](39-po-r8-resolved.md) | Why 691 of 837 results are a black-boxing artefact, and the cell-scoped waiver |
| 35 | [DRC layer-map blindness](35-drc-layer-map-blindness.md) | The deck can only report on layers its own map names — a standing property |
| 49 | [Layer-map coverage check](49-layer-map-coverage-check.md) | `check-layer-map-coverage`, which closes the doc-35 blind spot |
| 50 | [BND and LOGO checks](50-bnd-and-logo-checks.md) | The bond-pad/seal-ring BEOL deck and the LOGO keep-out rules, both as real flows |
| 51 | [Calibre ERC: PG labels](51-erc-pg-labels.md) | The ERC flow built after IMEC's "No labels found in topcell" |
| 52 | [Padring GDS check](52-padring-gds-check.md) | The broker's CompareCells/Padringcheck surprise, and the local check for its class |

### Power delivery, PG and IR drop

| # | Page | What it covers |
|---|---|---|
| 30 | [IR-drop gate design](30-ir-drop-gate-design.md) | The paper design for a rail-analysis gate; nothing in it was executed |
| 31 | [Power delivery measured](31-power-delivery-measured.md) | The long record of method, traps and numbers |
| 32 | [The IR-drop stage](32-ir-drop-stage.md) | The stage as wired into the flow: what it measures, refuses, and cannot see |
| 36 | [`split_row` PG anchoring](36-split-row-pg-anchoring-hazard.md) | One mechanism behind several separately-worked problems |
| 59 | [The four M5 VDD–VSS shorts](59-macro-placement-pg-short-window.md) | Where they are, and what moves them |
| 42 | [Stranded cells on PG islands](42-stranded-cells-pg-islands.md) | 330 instances with no supply path, 55 of them functional — real, not an artefact |
| 47 | [PG island feed fragility](47-pg-island-feed-fragility.md) | The feed fix works, on 0.4 µm of margin, ungated |
| 54 | [`check_fp_pg` vs the toolkit census](54-fp-pg-vs-macro-stripe-census.md) | What each PG/floorplan check measures, and why they are not redundant |
| 56 | [`-core_pin_check_stdcell_geometry`](56-core-pin-check-stdcell-geometry-not-tested.md) | The prepared falsifiable test of candidate fix 4 — **not run** |
| 60 | [`pgfix-A` run record](60-pgfix-a-run-record.md) | The provenance set, stated before the run |
| 61 | [Power intent never adapted](61-power-intent-never-adapted.md) | The `.upf` describes a different design; `check_cpf` has said so on every run |

### Timing, equivalence and content

| # | Page | What it covers |
|---|---|---|
| 40 | [Signoff STA](40-signoff-sta-plan.md) | The first independent signoff STA, and where it disagrees with Innovus in-flow |
| 34 | [Content gates runbook](34-content-gates-gate1-runbook.md) | ROM bits at the reticle, and LEC — both ready to run against a new stream |
| 44 | [eth ROM sim/silicon divergence](44-eth-rom-sim-divergence.md) | Why the `sim_divergence` WARN is declared and deliberate, not a defect |
| 57 | [CPU0 boot on the routed netlist](57-cpu0-boot-on-the-routed-netlist.md) | The first unforced, CRC-verified gate-level boot of **both** cores on `fp1505`, timed rung by rung; why two shipped assertions on `chip_core_remap_ctrl_w` were false reds; and the replacement signoff stage for one that passes a published `RESULT FAIL` today |

### Toolkit, submodules and infrastructure

| # | Page | What it covers |
|---|---|---|
| 29 | [Private TSMC tech repo](29-private-tsmc-tech-repo.md) | Not built — and superseded by a toolkit that carries no foundry data at all |
| 33 | [Toolkit/legacy decoupling](33-toolkit-legacy-decoupling.md) | Why the naive move fails; presence, content, provenance |
| 38 | [Submodule pin-check trap](38-submodule-pin-check-trap.md) | A SHA comparison cannot see a dirty submodule |
| 41 | [Retiring `asic-flows`](41-retiring-asic-flows.md) | The blast radius, and why no shared-repo change is needed |

### Broker and IMEC correspondence

| # | Page | What it covers |
|---|---|---|
| 27 | `27-broker-questions-SEND-NOW.md` | The questions only the broker or fab can answer. **Untracked and gitignored on purpose** — it names vendor library revisions. Present in a working checkout, absent from a fresh clone; see 58 |
| 48 | [IMEC signoff results](48-imec-signoff-results-analysis.md) | Their DRC/ERC/antenna results cross-checked against ours, with GDS provenance |
| 55 | [IMEC submission checklist](55-imec-preliminary-gds-submission-checklist.md) | What eptsmc require, which stream to send, the pre-send gate, and how to read the report back |
| 58 | [Broker correspondence](58-broker-correspondence-untracked.md) | Why the letter itself is deliberately not tracked here |

### Supporting material

- [Script reference](scripts/00-index.md) — every line of every flow script, annotated
- [`evidence/46-pg-island-feed-predictions.md`](evidence/46-pg-island-feed-predictions.md) —
  predictions recorded *before* the island-feed fix ran, so the result could not be fitted afterwards
- [`evidence/57-cpu0-boot-verdicts.md`](evidence/57-cpu0-boot-verdicts.md) —
  the four CPU0-boot verdict files verbatim, because the build directories they came from
  are gitignored and two of them were overwritten within three hours of being read

**Pages 22 and 23 are companions to the evaluation scripts.** Those scripts are written
to be read by someone learning the flow, so their comments explain *what each stage
does*; the notes files hold the *why* — the measurements, the one-off findings and the
tool behaviours that cost someone a day. A script comment saying "(Note 7.)" means
page 22 for synthesis, page 23 for P&R.

> **Pages 07–25 describe the 2026-08-05 → 08-08 runs on the `ASIC/genus-innovus` engine.**
> The shipping stream is now built by `ASIC/eth-chiplet` + `ASIC/asic-toolkit` into
> `ASIC/eth-chiplet/build/`. Each of those pages carries a status banner saying what it
> measured and where the current number lives; do not quote one without reading it.

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
a routing/PG check, **not signoff DRC**; only **black-box** LVS can run here, never
transistor-level. See [10](10-tapeout-submission.md) and
[`docs/asic/LVS_FINDINGS.md`](../asic/LVS_FINDINGS.md).

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

**Where the numbers on these pages come from.** Pages 07–25 measured the
`ASIC/genus-innovus` runs of 2026-08-05 → 08-08. Since 2026-08-13 the P&R engine that
builds the shipping stream is `ASIC/eth-chiplet` driven by the `ASIC/asic-toolkit`
submodule, and its builds live in `ASIC/eth-chiplet/build/` — `fp1505` and
`full-20260814` are the two that matter. `ASIC/genus-innovus` is still where the Calibre
DRC/ERC/BND/LOGO decks and the `make` targets for them live, so a command prefixed
`make <target>` in these pages usually still runs from there. **A number without a build
name is not comparable to anything.**

The geometry is stable: `CORE_TO_IO` was raised 50 → 70 µm to clear the inner staggered
bond pads, which shrank the core from 1230×1630 to 1190×1590 and required re-placing 17 of
the 21 macros; see [03](03-floorplan.md) for the dependency chain.

**Hold timing.** The historic headline on this page — "WNS −1.167 ns, TNS −66,212 ns,
96,545 violating paths" — was a clock source-latency asymmetry in the hold view, not real
skew, and the OCV-ordering fix in `scripts/cts_setup.tcl` closed it: see
[23 note 1](23-pnr-flow-notes.md) and [16 item 1](16-open-defects.md). Two caveats before
anyone quotes a hold number as closed: an independent signoff tool on the same database
finds **eleven times the hold violations Innovus in-flow reports**
([40 §5.4](40-signoff-sta-plan.md)), and the D2D TX word domain is still unconstrained, so
part of the design is not being timed at all ([24](24-d2d-link-physical-handover.md)).

**Open before submission** — read [45](45-measured-status-2026-08-18.md),
[09](09-signoff-checklist.md) and [11](11-known-issues.md) before promising anyone a date:

- **cell-level GDS merge** — must happen at the foundry; the stream we produce is not a
  complete chip ([10](10-tapeout-submission.md))
- **metal density fill** — declared the foundry's (`METAL_FILL_OWNER=foundry`,
  `ROUTE_METAL_FILL=0`). A declaration is not an agreement, and nothing in this flow
  re-checks the handoff ([09 item 15](09-signoff-checklist.md))
- **LVS** — black-box only. Clean on `fp1505`; the shipping stream cannot reach a verdict
  because `VDD`/`VSS` extract as one net ([`docs/asic/LVS_FINDINGS.md`](../asic/LVS_FINDINGS.md))
- **logical equivalence** — still the check most worth running, because a previous build
  silently lost a datapath to Genus unused-logic removal. There is still no end-to-end
  RTL→netlist proof, and the blocking `lec` gate has read green over the wrong half of a
  truncated log ([45 §3.5](45-measured-status-2026-08-18.md), runbook in [34](34-content-gates-gate1-runbook.md))
- **seal ring and scribe** — not in the design data
- **PG supply islands** — the PG opens are root-caused (`split_row` row anchoring,
  [36](36-split-row-pg-anchoring-hazard.md) / [42](42-stranded-cells-pg-islands.md)) and the
  feed fix is landed, but it survives on 0.4 µm of margin and nothing gates it
  ([47](47-pg-island-feed-fragility.md))
- **the pad ring as the foundry sees it** — IMEC's tools found no TSMC IO cells or bond pads
  in the submitted stream, and all four pad corners are 180° from correct
  ([52 §7](52-padring-gds-check.md)). The check that catches this is now a blocking gate and
  is deliberately RED on `fp1505` until the stream is re-cut ([53 §1](53-gate-promotion-plan.md))

---

## Conventions in these pages

- Commands shown as `make <target>` run from `ASIC/genus-innovus/` — that is where the
  Calibre DRC/ERC/BND/LOGO targets live. The P&R flow itself is driven from
  `ASIC/eth-chiplet/` (`make -C ASIC/eth-chiplet all RUN_TAG=<tag>`).
- Commands shown at a `@innovus` prompt assume you have sourced `config.tcl` and
  `read_db`'d a design — see [02](02-innovus-basics.md).
- Message IDs (`IMPSP-5110`, `GLO-34`) are quoted verbatim so they are greppable in logs.
- Numbers quoted as "measured" come from real runs on `srv03335` and are reproducible;
  anything inferred rather than observed is labelled as such.
