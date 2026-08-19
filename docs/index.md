# NanoSoC Ethernet Chiplet

Working documentation for the NanoSoC Ethernet Chiplet — a TSMC 65 nm LP chiplet built at
[SoC Labs](https://soclabs.org), carrying an Arm Cortex-M0 subsystem, an Ethernet MAC, a
QSPI flash cache and the TideLink die-to-die interconnect.

This site documents **this** design on **this** site: real paths, real message IDs, and
numbers measured from real runs. Where something has not been verified, it says so — and
where a page has been overtaken by a later measurement, it says that too, at the top.

---

## If you have never done backend ASIC before

"Backend" is everything between *a design that simulates correctly* and *a file the
factory can build*. It is a pipeline of four tool stages, each consuming the last one's
output. Nothing here is conceptually hard; almost all of the difficulty is that the tools
report success in ways that do not mean success.

| Stage | Tool here | Input → output | The one-line idea |
|---|---|---|---|
| **Synthesis** | Genus 21.15 | RTL (`.sv`) → gate netlist (`.v`) | Turn `always @(posedge clk)` into actual flip-flops and gates from a vendor cell library |
| **Floorplan + power** | Innovus 21.11 | netlist → placed macros, power grid | Decide where the big memories sit and lay a metal mesh that feeds every cell |
| **Place + CTS + route** | Innovus 21.11 | → routed database | Put every gate somewhere, build a clock tree that reaches them all at once, then wire it up |
| **Fill, stream, verify** | Innovus + Calibre | → GDSII + verdicts | Emit the mask file, then check it against the foundry's geometric rules |

Three vocabulary items that recur everywhere and are rarely defined:

- **GDSII** (or "the stream", or "the GDS") — the file format that holds the final
  polygons. It is what gets submitted.
- **Signoff** — the set of checks that must pass before submission: DRC (geometry rules),
  LVS (layout matches the netlist), STA (timing), antenna, density, ERC.
- **A gate** — in this repository, a scripted pass/fail assertion in `ci/signoff.yaml`,
  not a logic gate. "The route gate is red" means a check failed, not that a transistor
  is broken.

**Then read [Four things to know before you start](tapeout/00-index.md#four-things-to-know-before-you-start).**
Those four items are the difference between this flow being tractable and it silently
lying to you for a week. The first one — *exit status lies* — is not a figure of speech:
both Genus and Innovus exit `0` after printing an error and doing nothing.

---

## Start here

<div class="grid cards" markdown>

- **Driving the flow**

    ---

    The four Cadence stages, what each produces, how to resume a part-finished run, and
    what must be true before you submit.

    [Tapeout guide →](tapeout/00-index.md)

- **Understanding the scripts**

    ---

    Every line of every flow script, annotated and referred to the Cadence manual for the
    tool version actually installed.

    [Script reference →](tapeout/scripts/00-index.md)

- **Bringing up silicon**

    ---

    Bench wiring, the KR260 runbook, and the bring-up regression record for the
    packaged parts.

    [KR260 bench runbook →](bringup/KR260_BENCH_RUNBOOK.md)

- **What is still broken**

    ---

    Open defects, known issues, and the things that have been ruled out — read before
    promising anyone a date.

    [Measured project status →](tapeout/45-measured-status-2026-08-18.md)

</div>

**A suggested first week.** [Flow overview](tapeout/01-flow-overview.md) →
[Innovus basics](tapeout/02-innovus-basics.md) (the highest-value page: it teaches the
interactive session and `get_db`, which is what makes the tool stop being opaque) →
[Reading reports](tapeout/07-reading-reports.md) →
[Debugging](tapeout/08-debugging.md) → [Signoff checklist](tapeout/09-signoff-checklist.md).

---

## The design

| | |
|---|---|
| **Top cell** | `nanosoc_eth_chiplet_pads` |
| **Process** | TSMC 65 nm LP, 9 metal (`9M_6X1Z1U`) |
| **Die** | 1600 × 2000 µm |
| **Standard cells** | `tcbn65lp`, 9-track |
| **IO / bond pads** | `tphn65lpgv2od3_sl` drivers, `tpbn65v` staggered pads |
| **Memories** | 8 compiled macros (register files, two boot ROMs, flash-cache data and tag) |
| **Tools** | Genus (synthesis) → Innovus 21.11-s130_1, stylus mode (P&R) → Calibre (DRC/ERC/LVS), Voltus (rail), Tempus (signoff STA), Conformal (LEC) |
| **Submission** | mini@sic shuttle via the imec broker; Final GDS date **1 September 2026** |

**Which build are you looking at?** The P&R engine moved on 2026-08-13. The shipping
lineage is `ASIC/eth-chiplet/build/` — `fp1505` and `full-20260814` are the two builds
that matter. `ASIC/genus-innovus/` still holds the Calibre decks and their `make` targets,
and the older `baseline_2026-08-0*` directories there are what most audit pages measured.
**A number quoted without a build name is not comparable to anything.**

---

## What is proven, and what is open

Honest as of the last measured status ([45](tapeout/45-measured-status-2026-08-18.md),
2026-08-18). Anything not listed here has not been checked, which is not the same as fine.

**Measured and holding**

- The flow runs end to end and produces a GDSII.
- Calibre DRC runs uncapped on the shipping lineage. 837 raw results, 146 after a
  cell-scoped waiver, 140 design-owned — identical on `fp1505` and `full-20260814`
  ([43](tapeout/43-drc-fp1505.md)). 691 of the 837 are a black-boxing artefact, proved
  rather than assumed ([39](tapeout/39-po-r8-resolved.md)).
- Black-box LVS reaches a **clean** verdict on `fp1505` ([`LVS_FINDINGS`](asic/LVS_FINDINGS.md)).
- Both boot ROMs hold the intended firmware in the streamed GDS, checked at the reticle
  ([34](tapeout/34-content-gates-gate1-runbook.md)).
- CPU0 leaves reset and fetches its own mask ROM on the routed netlist
  ([57](tapeout/57-cpu0-boot-on-the-routed-netlist.md)).
- The PG-island root cause is found and the feed fix is landed and screened
  ([42](tapeout/42-stranded-cells-pg-islands.md), [47](tapeout/47-pg-island-feed-fragility.md)).

**Open, and load-bearing**

- **The GDS is not self-contained.** It carries our routing, our power grid and the memory
  macros' polygons; standard cells, IO drivers and bond pads are empty references, because
  this site's PDK ships LEF and liberty but no GDS or CDL for them. So every local DRC
  number is a routing/PG check, **not signoff DRC**, and transistor-level LVS cannot run
  here at all ([10](tapeout/10-tapeout-submission.md)).
- **The pad ring, as the foundry's tools see it, is wrong.** IMEC's check found no TSMC IO
  cells or bond pads in the submitted stream, and all four pad corners are 180° from
  correct ([52](tapeout/52-padring-gds-check.md)).
- **There is no end-to-end RTL→netlist equivalence proof**, and the blocking `lec` gate has
  read green over the wrong half of a truncated log
  ([45 §3.5](tapeout/45-measured-status-2026-08-18.md)).
- **Timing is an accepted open item, not a closed one.** The historical "−1.167 ns hold WNS
  across 96,545 paths" was a clock source-latency artefact and is fixed, but an independent
  signoff tool on the same database finds eleven times the hold violations Innovus reports
  in-flow ([40 §5.4](tapeout/40-signoff-sta-plan.md)), and the D2D TX word domain is still
  unconstrained ([24](tapeout/24-d2d-link-physical-handover.md)).
- **Metal density fill is contracted out** (`METAL_FILL_OWNER=foundry`). That is a
  declaration made in our own Makefile; nothing in the flow re-checks that the broker
  accepted it ([09 item 15](tapeout/09-signoff-checklist.md)).
- **The shipping stream is not reproducible.** Every build in the tree records
  `project_git_dirty = yes`, and the stages of the shipping build do not share one toolkit
  revision ([45 §2.5](tapeout/45-measured-status-2026-08-18.md)).

**The habit this project runs on:** before repeating a green verdict, check *what stream
or run it read*. Four separate "passes" have been traced to checks that measured a
superseded stream, and one to a check that measured nothing at all.

---

## How this site is organised

| Section | What it holds |
|---|---|
| [Tapeout guide](tapeout/00-index.md) | Driving the Cadence flow stage by stage, the audits, the DRC/PG/IR findings, and the broker correspondence |
| [Script reference](tapeout/scripts/00-index.md) | Line-by-line annotation of the flow scripts against the Cadence manuals |
| **Design** | Pin map, power domains, reset ordering, register maps, physical handoff |
| **Verification** | CDC, lint and elaboration findings; the G2 testbench and coverage record |
| **Cross-die and TideLink** | The die-to-die link: debug plans, root causes, silicon feedback |
| **Bring-up** | KR260 bench wiring and runbooks, FCSM bring-up regression, campaign logs |
| **Correspondence** | Foundry and collaborator exchanges, proposals, upstreaming notes |

Node-level traps — the ones that follow you to the *next* chip on TSMC 65 rather than
belonging to this design — live in
[`ASIC/tech_wrappers/tsmc65/README.md`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/tech_wrappers/tsmc65/README.md),
whose §1 is a seven-row index of them.

---

## Building these docs

```bash
pip install -r docs/requirements.txt
mkdocs serve          # live preview on http://127.0.0.1:8000
mkdocs build          # static site into site/
```

The site is MkDocs + Material, configured in `mkdocs.yml` at the repository root and built
on Read the Docs via `.readthedocs.yaml`. No submodule checkout is needed — the docs are
plain Markdown in this repository, and the RTD build deliberately skips submodules so a
docs build cannot fail on a credential it should not need.
