# NanoSoC Ethernet Chiplet

Working documentation for the NanoSoC Ethernet Chiplet — a TSMC 65 nm LP chiplet built at
[SoC Labs](https://soclabs.org), carrying an Arm Cortex-M0 subsystem, an Ethernet MAC, QSPI
flash cache and the TideLink die-to-die interconnect.

This site documents **this** design on **this** site: real paths, real message IDs, and
numbers measured from real runs. Where something has not been verified, it says so.

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

    [KR260 bench runbook →](KR260_BENCH_RUNBOOK.md)

- **What is still broken**

    ---

    Open defects, known issues, and the things that have been ruled out — read before
    promising anyone a date.

    [Open defects →](tapeout/16-open-defects.md)

</div>

---

## The design

| | |
|---|---|
| **Top cell** | `nanosoc_eth_chiplet_pads` |
| **Process** | TSMC 65 nm LP, 9 metal (`9M_6X1Z1U`) |
| **Die** | 1600 × 2000 µm |
| **Standard cells** | `tcbn65lp`, 9-track |
| **IO / bond pads** | `tphn65lpgv2od3_sl` drivers, `tpbn65v` staggered pads |
| **Tools** | Genus (synthesis) → Innovus 21.11-s130_1, stylus mode (P&R) → Calibre (DRC) |

---

## Four things to know before you start

**Exit status lies.** Genus and Innovus both exit `0` after printing an error and doing
nothing. Three P&R stages once "passed" in under a minute because `-f` is not a valid
stylus argument. Every stage target asserts on an **artefact**, never on `$?` — preserve
that discipline in anything you add. Both tools do accept `-abort_on_error`, which the flow
does not currently use; see the [script reference](tapeout/scripts/00-index.md).

**Warnings are where the bodies are.** `IMPSP-5110` reads like noise. It meant a GDSII
shipped with **zero filler cells** and 95,568 free-site gaps.

**The GDS is not self-contained.** `gds_merge_list` merges only the memory macros.
Standard cells, IO drivers and bond pads are empty references, because this site's PDK
ships LEF and liberty but no GDS or CDL for them. Every DRC number this flow produces is a
routing/PG check, **not signoff DRC**, and LVS cannot run here at all.

**Hold timing does not close, and never has.** The headline "WNS +0.079, 0 failing
endpoints" is **setup only**. Post-route hold is −1.167 ns WNS across 96,545 violating
paths, and the July baseline has it too. See [open defects](tapeout/16-open-defects.md).

---

## How this site is organised

| Section | What it holds |
|---|---|
| [Tapeout guide](tapeout/00-index.md) | Driving the Cadence flow, stage by stage, through to a submission bundle |
| [Script reference](tapeout/scripts/00-index.md) | Line-by-line annotation of the flow scripts against the Cadence manuals |
| **Design** | Pin map, power domains, reset ordering, register maps, physical handoff |
| **Verification** | CDC, lint and elaboration findings; the G2 testbench and coverage record |
| **Cross-die and TideLink** | The die-to-die link: debug plans, root causes, silicon feedback |
| **Bring-up** | KR260 bench wiring and runbooks, FCSM bring-up regression, campaign logs |
| **Correspondence** | Foundry and collaborator exchanges, proposals, upstreaming notes |

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
