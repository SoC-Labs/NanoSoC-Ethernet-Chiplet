# Calibre LVS — a portable flow

Layout-versus-schematic signoff for a digital ASIC, driven entirely by environment
variables, so the same runner works on any project and any PDK. No file here hard-codes a
site path, a PDK path or a design — projects supply paths, the flow supplies logic.
[`CONTRACT.md`](./CONTRACT.md) is the spec and is authoritative over this file; designs
are named below only to say where a measurement came from.

**Written for someone who has never run a backend signoff flow.** If you have, skip to
[Quick start](#3-quick-start) and [Porting](#7-porting-to-a-new-project-or-pdk).

| | |
|---|---|
| [`CONTRACT.md`](./CONTRACT.md) | the interface spec. Variables, artefacts, pipeline. Read it before changing anything. |
| [`run_lvs.sh`](./run_lvs.sh) | the runner. Six steps, no paths, no make. |
| [`lvs.mk`](./lvs.mk) | includable make fragment: targets + the environment plumbing. |
| [`project.mk.example`](./project.mk.example) | a worked project file — the one file here that carries concrete paths. |
| [`runset_lvs.template`](./runset_lvs.template) | the Calibre **Interactive** alternative. See [Batch or Interactive](#6-batch-or-interactive). |

---

## 1. What LVS is, and why it exists

Two descriptions of the same chip, compared for equality.

- **Layout** is the GDSII you send to the foundry: polygons on numbered layers. Calibre
  *extracts* a circuit from it — a transistor wherever diffusion crosses poly, a
  connection wherever metal and vias touch.
- **Schematic** is the intended circuit. In a digital flow **nobody draws a schematic**.
  The schematic is the **gate-level Verilog netlist** the place-and-route tool writes,
  mechanically translated to SPICE. "Schematic" is just the name Calibre gives the
  reference side.

LVS reports whether those two circuits are the same graph. That is the only check in the
whole flow that proves the polygons implement the netlist. Static timing analysis, power
analysis and gate-level simulation all *assume* it. DRC only asks whether the polygons
are manufacturable, not whether they are the right polygons. So LVS is what catches a
net routed to the wrong pin, a cell the router deleted, a supply grid stitched to the
wrong rail, a hand ECO that shorted two nets — failures that are invisible everywhere
else and fatal in silicon.

Jargon, once each:

| Term | Meaning |
|---|---|
| **deck** / rule file | the foundry's SVRF program: how to turn layers into devices and connectivity. Read-only; never edited in place. |
| **SVRF** | Calibre's rule language. `LAYOUT PATH`, `LVS BOX`, … |
| **TVF** | Tcl-embedded SVRF. A deck whose first line is `#!tvf` is a Tcl program that emits SVRF. Matters — see [Troubleshooting](#9-troubleshooting). |
| **CDL** | the SPICE netlist dialect LVS reads on the source side. |
| **`v2lvs`** | Calibre's Verilog→CDL translator. Ships with Calibre. |
| **leaf cell** | bottom of the hierarchy: a standard cell (`INVD2`), an IO driver, a bond pad. |
| **hard macro** | a pre-built block dropped in whole — SRAM, ROM, PLL. |
| **FE / BE views** | *front-end*: liberty, LEF, simulation Verilog — enough to synthesise and place. *back-end*: transistor CDL and cell GDS — what LVS needs to see inside a cell. |
| **RVE** | Calibre's results viewer: click a discrepancy, jump to the coordinate in the layout. |
| **`svdb/`** | Calibre's extracted database. RVE reads it; it is large. |

---

## 2. Where LVS sits in the backend flow

```
   RTL ──► synthesis ──► gate netlist          (no physical data yet)
                              │
                              ▼
             P&R:  floorplan ─► place ─► CTS ─► route ─► ECO
                              │
                    ┌─────────┴──────────┐
          write_stream          write_netlist
                    │                    │
                    ▼                    ▼
                  GDS                 Verilog
                    │                    │
              ┌─────┴─────┐              │
             DRC         LVS ◄───────────┘
```

DRC and LVS are **signoff**: the last gates before tapeout. DRC checks the layout against
the foundry's geometry rules. LVS checks it against your netlist.

### The source netlist must be the post-P&R one

This is the single most common newcomer mistake, and it produces a spectacular,
completely meaningless failure.

The synthesis netlist is not the netlist that got built. Between synthesis and stream-out,
P&R **changes the netlist**:

- **CTS** (clock tree synthesis) inserts hundreds or thousands of clock buffers and
  inverters that did not exist at synthesis.
- **Optimisation and ECO** resize cells, clone drivers, insert hold-fix buffers, delete
  redundant logic, and rename the nets around every edit.
- **Physical-only insertion** adds filler, decap and antenna cells that appear in the GDS
  and in no netlist at all.

So `LVS_SRC_V` must be the `write_netlist` output taken from **the same P&R database, at
the same moment**, as the `write_stream` that produced `LVS_GDS`. Only that pair can
match. Feed the pre-CTS synthesis netlist and LVS will report thousands of unmatched
instances, every one of which is real and every one of which is correct.

The corollary: **re-run an ECO, re-emit both.** A GDS from one run and a netlist from the
previous one is the same bug in slower motion.

---

## 3. Quick start

Everything is an environment variable ([`CONTRACT.md`](./CONTRACT.md) §1). Nothing else is
needed and nothing else is read.

### With make

```sh
cp lvs-flow/project.mk.example  <your-design>/lvs_project.mk   # then edit the paths
# add to the END of your Makefile's variable section:
#     include $(DESIGN_DIR)/lvs_project.mk

make lvs-preflight    # do all my inputs exist? no tool, no licence, seconds
make lvs_source       # v2lvs + SPICE assembly, then stop. Still no licence.
make lvs              # the real run. Takes a Calibre licence and hours.
make lvs-report       # the verdict, lifted out of the report
make lvs-rve          # results viewer on the svdb (needs a real X display)
```

`make lvs-help` prints every resolved value — use it when a path looks wrong.

### Without make

```sh
export LVS_DECK=<pdk>/Calibre/lvs/calibre.lvs
export LVS_GDS=<outputs>/<top>.gds
export LVS_SRC_V=<outputs>/<top>_pnr.v          # POST-P&R. See §2.
export LVS_TOP=<top>
export LVS_RUNDIR=$PWD/lvs_run
export STDCELL_VLOG="<stdcell sim verilog>"
export IO_VLOG="<io sim verilog>"               # may be empty for a macro
export MACRO_CDLS="<sram.cdl> <rom.cdl>"        # may be empty

LVS_SOURCE_ONLY=1 ./run_lvs.sh   # iterate the source prep with no licence
./run_lvs.sh                     # the full run
```

**Always run the source-only pass first.** The first two failures in
[Troubleshooting](#9-troubleshooting) are visible in its output. Both otherwise cost you a
licence seat and an hour of extraction to discover something `v2lvs` could have told you
in ten seconds.

---

## 4. Front-end-only PDKs, and the `LVS BOX` answer

### The problem

Academic and university-programme PDKs ship **front-end only**: liberty, LEF, simulation
Verilog. No transistor CDL, and no cell GDS. You can synthesise, place, route and stream —
and then you cannot do LVS in the textbook way, because *neither side of the comparison
contains any devices for standard cells*:

- **Source side**: `v2lvs` has only a behavioural Verilog model of `INVD2`, so it emits an
  empty `.SUBCKT` — a name and some pins.
- **Layout side**: the cell GDS was never merged into the stream, so each placed cell is
  an empty frame.

Left alone, Calibre does the reasonable thing with an empty layout cell: it **flattens it
away**. The layout then contains zero standard-cell instances while the source still has
every one of them, and the entire digital fabric mis-compares.

This is not hypothetical. A 2026-05-21 run of the `ethernet_ss_ahb` macro with no boxing
reached a comparison and matched **nothing**:

| | Layout | Source |
|---|---:|---:|
| Ports matched | 0 | 0 |
| Ports unmatched | 0 | **665** |
| Nets unmatched | **26,619** | **40,538** |
| Instances unmatched | **51,908** | **38,618** |

Instance counts before reduction: 5,670,993 layout against 38,618 source; 3,757,088 layout
`MN` transistors against **0** in the source. Verdict `INCORRECT`, with *Different numbers
of ports / nets / instances* and *Connectivity errors*. Every one of those numbers is an
artifact of missing PDK data. Not one is a design error.

### The answer

`LVS BOX <cell> …` tells Calibre to treat a cell as a **boundary black box on both sides**:
do not look inside, do not flatten, compare it as a component. The digital fabric then
compares as instances and interconnect rather than as transistors.

Why this is legitimate and not cheating:

- It is **symmetric**. The same cell is boxed on the layout side and the source side. You
  are not suppressing a difference; you are declining to compare data that does not exist
  in either input.
- It is **declared**, in a generated file you can read
  (`${LVS_TOP}_lvs_box.svrf`) and diff.
- It changes **what** is verified, not **whether** the verification is honest. Contrast
  `LVS IGNORE PORTS`, which hides a real mismatch to manufacture a pass. Never do that.
- **Macros with real CDL are never boxed.** SRAM and ROM compare down to transistors, and
  that part of the run is full-strength verification.

Same design, before and after boxing (from the driving script's issue log for
`nanosoc_compute_chiplet_pads`):

| | unboxed | boxed |
|---|---:|---:|
| Unmatched source nets | 554,108 | 2 |
| Unmatched ports | 63 | 2 |
| Instances matched | — | **598,334 / 598,334**, 0 unmatched either side |

Those residual 2s are the PG-naming item of §6. They are gone in the archived report of
the final 2026-08-06 run, which shows **0 unmatched on both sides in every row** — `VDD`,
`VSS` and `CLK` all became correspondence points. Expect the pair to reappear on a design
whose supplies do not resolve; expect zero when they do.

### Two refinements the box list depends on

**Bond pads must get a pin-less stub.** LEF-only bumps have no Verilog and no CDL at all,
so the netlist instances a cell nothing defines. Result: thousands of `No matching
".SUBCKT"`, and the source is rejected before any comparison. Step 3 of the pipeline emits
`.SUBCKT PAD…` / `.ENDS` for each name in `BONDPAD_CELLS`. An empty subcircuit is the
faithful schematic view of a bump: it carries no connectivity.

**Physical-only cells must be excluded from the box list.** Filler, decap and antenna
diodes are inserted by P&R and streamed into the GDS, but `write_netlist` does not emit
them — the source has zero. Box them and they survive as unmatched *layout* instances
(measured on the same design: `ANTENNA` = 68,842, `DCAP4` = 5,530). Leave them unboxed and
their empty frames flatten away, which matches the source's absence of them exactly. That
is what `LVS_BOX_EXCLUDE_RE` is for.

---

## 5. Reading the report

**Calibre's exit status is not a verdict.** It exits 0 on a clean run that compared
`INCORRECT`. The verdict lives in `${LVS_RUNDIR}/${LVS_TOP}.lvs.rep` and nowhere else.

### The three outcomes

| Outcome | How you recognise it | What it means |
|---|---|---|
| **CORRECT** | ASCII banner `CORRECT` under `OVERALL COMPARISON RESULTS` | The two circuits are the same graph, within whatever you boxed. |
| **INCORRECT** | banner `INCORRECT`, followed by `Error:` / `Warning:` class lines | The comparison ran and found differences. Now find out which kind. |
| **never compared** | no report, or a report with no comparison block; log ends `Circuit Extraction subprocess terminated abnormally` | A setup failure. Nothing was verified. This is the outcome people misread as a pass. |

The third is real and looks like this — a 2026-06-02 run of `tidelink_top`:

```
//  Calibre subprocess (3387128) terminated normally, exit code = 4
//  Circuit Extraction subprocess terminated abnormally.
```

with the wrapper's summary reading `calibre exit: 4` and `RESULT: indeterminate — Calibre
may not have completed comparison`. **Treat any non-verdict as a failure**, and make your
wrapper say so.

### Reading order

1. **`OVERALL COMPARISON RESULTS`** — the banner, then the list of `Error:` and `Warning:`
   classes. The class list tells you what kind of problem you have before you read a
   single discrepancy.
2. **`CELL SUMMARY`** — which cells compared incorrectly.
3. **`INITIAL NUMBERS OF OBJECTS`** — layout column against source column, `*` marking a
   row where they differ. Read this before anything else: a gross asymmetry here is a
   setup problem, not a design bug.
4. **`NUMBERS OF OBJECTS AFTER TRANSFORMATION`** — the same counts after Calibre's
   reduction and hierarchy matching.
5. **the Matched/Unmatched table** under `INFORMATION AND WARNINGS` — the actual
   scoreboard, four columns: matched layout, matched source, unmatched layout, unmatched
   source.
6. **`INCORRECT OBJECTS`** — the numbered discrepancy list, with layout coordinates you
   can paste into a layout viewer or click in RVE. Capped by `LVS REPORT MAXIMUM`; if you
   see exactly 20 or exactly 1000, there are probably more.
7. **`o Statistics:`** — how many nets Calibre *deleted* before comparing. Read it before
   you believe a clean net count. See [Known limitations](#8-known-limitations).

### Real mismatch or artifact

| Signature | Reading |
|---|---|
| A handful of unmatched nets/instances, scattered, each with a plausible instance path | **Real.** Start at the first discrepancy; the rest are usually downstream of it. |
| Unmatched counts in the hundreds of thousands, one-sided | **Artifact.** Setup, not design. Something did not resolve — see [Troubleshooting](#9-troubleshooting). |
| Whole cell *types* unmatched, all of one family | **Artifact.** A library was not passed, or a cell class was boxed that should not be. |
| Only power/ground nets unmatched, bulk pins flagged, signal pins clean | **Artifact.** PG naming — [`CONTRACT.md`](./CONTRACT.md) §6, fixed on the P&R side. |
| Ports differ but nets and instances match | Usually a **naming** difference (bus notation, case) rather than a wiring error. |

**Warnings you can pass over.** `LVS BOX cell "<name>" not located or not allowed` means a
name in the box list is not instanced in this design — the list is generated from the
whole library. The 2026-08-06 run carried 518 of these and they were all benign.

### A worked example: what a real completed run looks like

`nanosoc_compute_chiplet_pads`, 2026-08-06, Calibre v2023.1_18.8, boxed. The box list was
112 `LVS BOX` lines naming 884 cells, generated from the 902 `.SUBCKT` stubs `v2lvs -e`
produced, minus the physical-only families, plus the two bond pads.

| | Layout | Source |
|---|---:|---:|
| Ports, initial | 3 | 66 |
| Nets, initial | 3,116,202 | 2,847,928 |
| Instances, initial (total) | 7,362,744 | 7,330,011 |
| Ports, after transformation | 3 | 3 |
| Nets, after transformation | 32,354 | 32,354 |
| Instances, after transformation (total) | **598,334** | **598,334** |
| **Unmatched, every row** | **0** | **0** |

Zero unmatched objects on either side — and the verdict is still **`INCORRECT`**. That is
not a contradiction, and understanding why is the most useful thing in this document.

The remaining errors are *pin* errors, not *matching* errors: 508 numbered discrepancies,
all of class `INSTANCES OF CELLS WITH NON-FLOATING EXTRA PINS`, plus 362 blocks of
`COMPONENT TYPES WITH NON-IDENTICAL SIGNAL PINS` that all read like this:

```
Layout Component Type:  XOR4D0 (0 pins)
No Extra Pins.

Source Component Type:  XOR4D0 (5 pins): a1 a2 a3 a4 z
Source Extra Pins:      a1 a2 a3 a4 z
```

The source stub declares five pins. The layout box declares **none** — because with no
cell GDS there is no pin geometry to declare. So every boxed leaf compares as a component
with no terminals, and Calibre correctly reports that the source side has pins the layout
side does not.

**Two takeaways.** First: when the boxed cells carry no layout pins at all, a `CORRECT`
banner is not reachable — so judge the run by the object counts and the discrepancy
*classes*, and say so explicitly when you report it. Second: read the statistics block,
because it says what that pinless box actually cost —

```
   623948 isolated layout nets were deleted.
   220395 layout nets had all their pins removed and were deleted.
   576003 source nets had all their pins removed and were deleted.
   148 nets and 1010 instances were matched arbitrarily.
```

See [Known limitations](#8-known-limitations).

---

## 6. Batch or Interactive

Two ways to drive the same Calibre. They are not rivals; use both.

| | **batch** ([`run_lvs.sh`](./run_lvs.sh)) | **Interactive** ([`runset_lvs.template`](./runset_lvs.template)) |
|---|---|---|
| Source format | SPICE only — you run `v2lvs` first | accepts `SOURCE SYSTEM VERILOG` directly; Calibre runs `v2lvs` for you |
| Foundry deck | must be copied and rewritten (placeholder substitution) | used **unmodified**; the runset supplies the paths |
| Extra SVRF (`LVS BOX`) | spliced into the deck copy, and it must land in the SVRF region | `Setup → Include SVRF Commands`, no splicing |
| RVE | launch separately against `svdb/` | one click, and it stays attached |
| Reviewable in a diff | **yes** — one shell script, greppable, version-controlled | partly: the GUI rewrites the file and drops your comments |
| Reproducible without a GUI | **yes** — no X, no GUI packages | `-batch` works headless, but you still need the Interactive package |
| Good for | CI, regression, tapeout records, handing to someone else | first bring-up on a new PDK, and triaging a failure visually |

The honest summary: **Interactive is better at exploring, batch is better at proving.**
Interactive skips the entire `v2lvs` step that causes most of
[Troubleshooting](#9-troubleshooting), and RVE beats reading a 13,574-line report. But a
runset is a GUI state file — press Save and your comments are gone — whereas a shell
script is a reviewable artefact that will still run in three years on a machine with no
display.

Both read the same `${LVS_TOP}_lvs_box.svrf`, so a box list debugged in one works in the
other.

```sh
calibre -gui -lvs -batch -runset runset_lvs   # headless
calibre -gui -lvs        -runset runset_lvs   # GUI + RVE
```

---

## 7. Porting to a new project or PDK

The flow logic never changes. Only the values do. Work down this list; the tags say what
triggers a change.

### New design, same PDK — `[PROJECT]`

| Variable | Note |
|---|---|
| `LVS_TOP` | must exist in **both** the GDS and the netlist, spelled identically |
| `LVS_GDS` | from `write_stream` |
| `LVS_SRC_V` | from `write_netlist`, same database, same moment (§2) |
| `LVS_RUNDIR` | anywhere writable; expect gigabytes of `svdb/` |
| `MACRO_CDLS` | every hard macro this design instances that ships a real CDL |
| `BONDPAD_CELLS` | only if the floorplan places bumps/pads with no model |
| `LVS_POWER` / `LVS_GROUND` | the design's actual rails, IO rails included |

### New PDK or new library release — `[PDK]`

| Variable | What to check |
|---|---|
| `LVS_DECK` | the foundry LVS deck. **Confirm the placeholder substitutions still land** — the runner asserts this, so deck format drift fails loudly instead of silently running against the wrong file. |
| `LVS_SOURCE_ADDED` | the deck's `source.added` primitives, if the PDK ships one |
| `STDCELL_VLOG`, `IO_VLOG` | the simulation Verilog for the new libraries |
| `LVS_BOX_EXCLUDE_RE` | **the one that bites.** The default matches `ANTENNA`, `DCAP`, `GDCAP`, `GFILL`, `OD25DCAP` — TSMC-ish names. Another vendor calls them `FILLER*`, `TAPCELL*`, `WELLTAP*`, `ANTENNA_*`. Get this wrong and you get unmatched layout instances in the tens of thousands. |
| `LVS_BOX_LEAF` | leave at `1` for a front-end-only PDK. If the new PDK ships **back-end** views — transistor CDL and cell GDS — set `0` and do real signoff LVS. |

To find the right exclude pattern on a new PDK: run once, and read which cell families
appear as unmatched **layout** instances with zero source instances. Those are your
physical-only cells. Confirm by grepping the P&R netlist — a genuine physical-only cell
appears exactly zero times.

### Never changes — `[FLOW]`

The six-step pipeline, the artefact names, `run_lvs.sh`, `lvs.mk`, this file. If porting
seems to need a change to any of them, it is a contract change: update
[`CONTRACT.md`](./CONTRACT.md) first, then all three.

### Also never changes: the read-only rule

`$LVS_DECK` and everything under the PDK and the shared IP libraries are **read-only lab
collateral**. The flow copies and rewrites; it never edits in place. If a fix seems to
require editing vendor collateral, copy the file into the project tree, point the flow at
the copy, and document the deviation.

---

## 8. Known limitations

**A boxed run is not signoff. Never present it as one.**

- **Cell interiors are unverified by construction.** Every boxed cell is a black box. If a
  standard cell's layout were wrong, this flow could not tell you. Full signoff LVS needs
  the foundry back-end packages — transistor CDL and cell GDS — and then you set
  `LVS_BOX_LEAF=0`.
- **On a PDK with no cell GDS at all, the boxes have no pins, and most of the netlist is
  deleted before comparison.** This is stronger than "cell interiors are unverified", and
  it is the limitation to quote. Measured on the 2026-08-06 run: 576,003 source nets and
  220,395 layout nets had all their pins removed and were deleted, leaving 32,354 nets
  compared out of an initial 2.8–3.1 million. What survived is what still had pins: the
  three top-level ports and the nets touching the SRAM macros' real devices. The 598,334
  matched instances are a match of cell type and count, not of the wiring between them.
  A further 148 nets and 1,010 instances were *matched arbitrarily* by ambiguity
  resolution.
- **So state the result precisely.** "Every leaf instance in the GDS is present in the
  netlist and vice versa, with no unmatched objects, and the SRAM macros compare to
  transistors" is true and worth having. "LVS is clean" is not.
- **PG net naming is an open item** ([`CONTRACT.md`](./CONTRACT.md) §6). `write_netlist`
  without `-include_pwr_gnd` emits no supplies and the stream carries no PG text, so the
  layout supply grid can be unnamed and unable to equate to the source's global
  `VDD`/`VSS`. It surfaces as unmatched PG nets plus bulk-pin flags on macro transistors —
  a *labelling* artifact, not a connectivity error. The fix is on the P&R side: re-emit
  with `write_netlist -include_pwr_gnd -phys` and drop the `.GLOBAL`. **Do not mask it**
  with `LVS IGNORE PORTS` or bulk-check suppression.
- **`LVS_BOX_LEAF=0` is a diagnostic, not a mode.** It exists so you can see the raw
  mis-compare and confirm the boxing is doing what you think. On a front-end-only PDK it
  will never produce a useful verdict.
- **No CI gate ships with this flow.** Runtime is hours and it takes a licence seat.

---

## 9. Troubleshooting

Everything **above the line** is a setup failure: the run never reaches a comparison, so
nothing was verified. Everything **below the line** did compare, and the numbers are
misleading rather than absent. The first two are visible in the `make lvs_source`
artefacts before you take a licence.

### `Cell <X> is referenced but not defined.` → exit 4, no comparison

```
ERROR: Cell XOR3D2 is referenced but not defined.
ERROR: Cell OAI222D2 is referenced but not defined.
…
//  Calibre subprocess (…) terminated normally, exit code = 4
//  Circuit Extraction subprocess terminated abnormally.
```

**Cause.** The `v2lvs -e` library pass did not happen, or did not cover every library. The
design CDL references leaf cells nothing defines.

**Why `-e` specifically.** `-e` emits an empty `.SUBCKT` per module *without translating
instances*. Plain `v2lvs` silently drops cells whose models are UDP-based — scan flops and
IO cells, mostly — and you find out at compare time.

**Fix.** Pass every cell library in `STDCELL_VLOG` and `IO_VLOG`; step 1 of the pipeline
does the rest. Verified case: a 2026-06-02 `tidelink_top` run, **370** of these errors, no
comparison.

**Check yourself:** every leaf name in the design CDL must appear as a `.SUBCKT` in
`${LVS_TOP}_libs.cdl` or in one of `MACRO_CDLS`.

### `No matching .SUBCKT for "<PAD…>"` → `Source could not be read`

**Cause.** Bond pads and bumps that P&R places directly. They are LEF-only `CLASS BLOCK`
cells — top-metal shapes, no pins, no Verilog, no CDL — so the netlist instances them and
nothing defines them. Thousands of errors, and the source is rejected outright: no
comparison at all.

**Fix.** List them in `BONDPAD_CELLS`. Step 3 emits `.SUBCKT <cell>` / `.ENDS` — a
*pin-less* stub, which is the faithful schematic view of a bump.

### `Error SPC1 … superfluous specification statement`

**Cause.** You wrapped the foundry deck in `INCLUDE` and then re-declared `LAYOUT PRIMARY`
/ `SOURCE PRIMARY` / `LVS REPORT` to override the deck's own. SVRF has no override-wins
rule: a duplicate specification statement is a hard error.

**Fix.** Copy the deck and **substitute** the placeholders (step 4). Then *assert every
substitution landed*, so a deck that changed its placeholder lines fails loudly instead of
quietly running against `lvs_top.gds`.

### `Error INP1 … superfluous or invalid input object: VERILOG`

```
ERROR: Error INP1 on line 897 of SVRF generated from TVF - superfluous or invalid
input object: VERILOG.
```

**Cause.** `SOURCE SYSTEM VERILOG` in a batch run. Batch Calibre LVS accepts **SPICE
source only**; Verilog source is a Calibre Interactive feature.

**Fix.** Either pre-translate with `v2lvs` (what this flow does) or switch to the
Interactive runset (which is exactly what it is for). Verified case: 2026-06-02,
`tidelink_top`.

### `TVF2 invalid command name`

**Cause.** SVRF appended at end-of-file to a deck whose tail is embedded TVF. A deck
starting `#!tvf` is a Tcl program; SVRF lines dropped into its Tcl region are parsed as Tcl
commands and die. The measured deck for the 2026-08-06 run is 22,900 lines, and everything
from line 22,883 on is `tvf::SETLAYER` Tcl.

**Fix.** Splice `LVS BOX` into the **SVRF region**. Step 5 puts it immediately after
`LVS GROUND NAME` — line 1,127 of that deck, with the box block at 1,129.

---

### Mass unmatched **source** nets and ports

**Symptom.** Unmatched source nets in the hundreds of thousands; unmatched ports in the
tens; layout instance count near zero for standard cells.

**Cause.** The front-end-only auto-flatten artifact —
[§4](#4-front-end-only-pdks-and-the-lvs-box-answer). Empty layout cells were flattened
away, so the layout has no standard cells and the source has all of them.

**Fix.** `LVS_BOX_LEAF=1` (the default). If it is already 1, check that
`${LVS_TOP}_lvs_box.svrf` exists, is non-empty, and actually landed in the run deck
(`grep -c '^LVS BOX' ${LVS_TOP}_calibre_lvs.deck`). A box block that silently failed to
splice looks identical to no boxing at all.

### Unmatched **layout** instances of fill / decap / antenna cells

**Symptom.** Tens of thousands of unmatched layout instances, all from one or two cell
families, zero of them in the source.

**Cause.** Physical-only cells were **boxed** instead of excluded. Boxing preserves them on
the layout side; the source never had them.

**Fix.** Widen `LVS_BOX_EXCLUDE_RE` to cover the family so its frames auto-flatten.
Verified case: `ANTENNA` = 68,842 and `DCAP4` = 5,530 unmatched layout instances until they
were excluded; after excluding, 598,334 / 598,334 instances with zero unmatched.

### Unmatched PG nets, macro bulk pins flagged

**Symptom.** A small number of unmatched nets, all power/ground; missing `VDD`/`VSS` layout
ports; macro transistors flagged on their bulk (`b:`) pin while gate, source and drain
match.

**Cause.** [`CONTRACT.md`](./CONTRACT.md) §6 — the layout supply grid has no name to match
against.

**Fix.** P&R side, and out of scope for this flow: re-emit with
`write_netlist -include_pwr_gnd -phys` and drop the `.GLOBAL`. Document it; do not mask it.

### `LVS BOX cell "<name>" not located or not allowed`

Benign. A boxed name is not instanced in this design — the list is generated from the whole
library, not from the netlist. Look in `calibre_erc.sum` and the transcript; the 2026-08-06
run carried 518 of them and all were harmless.

---

## 10. Provenance

Every measured figure above comes from one of three archived runs on this site. All were
run with Calibre v2023.1_18.8. Paths are relative to each repository root.

| Run | Date | Where |
|---|---|---|
| Completed, boxed — `nanosoc_compute_chiplet_pads` | 2026-08-06 | compute-chiplet repo, `ASIC/chiplet-pads/work/lvs_run/` — `nanosoc_compute_chiplet_pads.lvs.rep`, `…_lvs_box.svrf`, `…_calibre_lvs.deck`, `calibre_erc.sum`. Before/after-boxing figures come from the issue log at the foot of `ASIC/chiplet-pads/scripts/run_lvs.sh`. |
| Aborted, no comparison — `tidelink_top` | 2026-06-02 | tidelink repo, `syn/asic/calibre/` — `reports/10_calibre_lvs.rep`, `logs/calibre_lvs.log`, `make_lvs_*.log` |
| Completed, unboxed — `ethernet_ss_ahb` | 2026-05-21 | ethernet-subsystem repo, `syn/asic/calibre/reports/lvs_summary.rep` |

The Calibre Interactive runset key names in
[`runset_lvs.template`](./runset_lvs.template) are taken from the installed Calibre
distribution and from a SoC Labs 44-pin TSMC 65 nm tapeout runset of February 2024. The
one exception is flagged in the template itself.
