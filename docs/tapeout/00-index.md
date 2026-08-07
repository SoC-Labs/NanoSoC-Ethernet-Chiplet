# NanoSoC Ethernet Chiplet — Innovus & Tapeout Guide

A working guide to driving the Cadence flow in this repository and getting a GDSII you
can actually submit. It documents **this** design on **this** site — real paths, real
message IDs, real numbers measured from real runs — not generic Innovus tutorial
material. Where something has not been verified, it says so.

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
| 13 | [LEC](13-lec.md) | Post-P&R equivalence — the check nothing here previously performed |
| 14 | [DRC triage](14-drc-triage.md) | The 102 surviving violations, classified and root-caused |
| 15 | [PG opens analysis](15-pg-opens-analysis.md) | Evidence and ranked hypotheses for the unexplained opens |
| 16 | [Open defects](16-open-defects.md) | The hold-timing defect, DRV, GWEN, and other live findings |

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
