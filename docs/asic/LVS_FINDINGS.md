# LVS — state of the flow, what it proves, and mutation coverage

**Measured 2026-08-17/18 on `nanosoc_eth_chiplet_pads` (TSMC 65LP), Calibre nmLVS
v2023.1_18.8.** Every number below comes from a run made for this document; none is
quoted from an earlier session. Absolute PDK paths are redacted as `<PDK>`.

Companion documents: `ASIC/lvs-flow/CONTRACT.md` (the spec), `ASIC/genus-innovus/lvs_project.mk`
(this project's values). Where those disagree with this file, this file is the measurement.

---

## 0. Headline

1. **LVS runs here.** `docs/tapeout/09-signoff-checklist.md` item 16 and
   `docs/tapeout/10-tapeout-submission.md` still say LVS "cannot be run here". That is
   **wrong** and is now disproved by seven runs. Front-End-only data is sufficient.
2. **The gate CAN fail — but only in one of the two configurations that ship today.**
   A planted miswire is **detected and named** when LVS runs against
   `<top>_lvs_pintext.gds`, and is **completely invisible** — byte-identical report —
   when it runs against `<top>_lvs.gds`. `make lvs_batch LVS_PG=1` selects the second.
3. **The current shipping stream cannot produce an LVS verdict at all.** `VDD` and `VSS`
   extract as one net, so the flow's own guard refuses to present a result (exit 6).
   ERC (sibling session) attributes the merge to four real M5 rail-to-rail shorts.
   **The `fp1505` variant does reach a verdict, and it is clean**: 325,189/325,189 instances,
   62,479/62,479 nets, 50/50 ports, no shorts, zero unmatched layout objects, with the whole
   residue being the 82 expected bond pads (§9.1). That is the run to quote today.
4. **A stale stream-out map is in the P&R path.** The map that produced the shipping
   stream is three days older than the generator that is supposed to produce it, and
   differs from what that generator emits today.

---

## 1. What the flow is, and which copy is live

| | path | status |
|---|---|---|
| **live** | `ASIC/lvs-flow/` | **tracked, and the one the Makefile uses** |
| fork | `ASIC/asic-flows/Mentor/LVS/` | **untracked working-tree copy — NOT on the live path** |

`ASIC/genus-innovus/lvs_project.mk` sets `LVS_FLOW_DIR ?= $(DESIGN_DIR)/../lvs-flow`, so
`ASIC/lvs-flow/` is what runs. The fork diverges in both directions (CONTRACT.md 91 lines,
README.md 56, `lvs.mk` 8, `lvs_pg_emit.tcl` 8, `run_lvs.sh` 4; `project.mk.example` is
renamed `project.mk.template` there).

**Every difference in the code files is cosmetic** — path strings in comments and help
text rewritten for a future promotion into the shared toolkit (`$(SOCLABS_ASIC_FLOW_DIR)/Mentor/LVS/`
instead of `../lvs-flow`), plus two comment examples in `lvs_pg_emit.tcl` that were
generalised away from concrete layer numbers. No logic differs. **Work on `ASIC/lvs-flow/`;
the fork is a promotion draft and should either be committed as such or deleted.**

## 2. How to run it

```sh
cd ASIC/genus-innovus
make lvs-preflight   # two layers of checks, no licence, no tool launched
make lvs_source      # v2lvs + SPICE assembly, still no Calibre licence
make lvs_batch       # the real run; verdict is in the report, NOT in $?
make lvs-report      # lifts the verdict out of the report
```

Inputs are overridable outright, which is how every run in this document was made:

```sh
make lvs_batch LVS_IN_DIR=<dir holding the GDS and _pnr.v> LVS_RUNDIR=<scratch>
make lvs_batch LVS_GDS=<some.gds> LVS_SRC_V=<some_pnr.v> LVS_RUNDIR=<scratch>
```

The runner's exit codes are meaningful and are **not** Calibre's: `0` CORRECT, `1`
INCORRECT, `6` NOT MEANINGFUL (a verdict was produced but is about the wrong thing).
Calibre exits 0 after errors — assert on artefacts, never on `$?`.

## 3. What it compares, and what a PASS excludes

The layout is the streamed GDS; the schematic is the **post-P&R** netlist
(`<top>_pnr.v`), which must come from the same database as the GDS.

Front-End-only PDKs ship no transistor CDL and no cell GDS for standard cells, IO and
pads, so those leaves are `LVS BOX`ed — pinned as black boxes on both sides so Calibre
matches them as instances instead of dissolving them. Measured on this design:
**884 cells boxed in 111 `LVS BOX` lines; 469 macro `.SUBCKT`s held back** for real
device-level comparison.

**A pass therefore proves:** every cell present, of the right type and count, and the
routed nets between them reconciled against the netlist. The eight hard macros
(4 register-file sizes, 2 flash-cache arrays, 2 boot ROMs) compare **all the way down to
transistors** — that part is real verification.

**A pass does NOT prove, all three by construction:**

- **cell interiors** — boxed leaves are black boxes;
- **pin-level wiring on boxed leaves** — *conditionally*; see §4, this is the finding;
- **the pad ring** — its cells are LEF-only; in the streams examined here the bond pads
  `PAD70GU`/`PAD70NU` are **empty structures (geom=0)**, so there is no pad-ring geometry
  to verify and pad-ring power connectivity is untested.

Quote results as **"clean modulo black boxes and modulo the pad ring"**. Never "signoff
clean". Full device-level LVS needs the foundry Back-End packages and is a foundry step.

---

## 4. THE FINDING: the flow compares the wrong layout file

Two PG-labelled streams exist beside each P&R run, and they are **not** equivalent:

| stream | total GDS text records | boxed-cell pin names |
|---|---|---|
| `<top>_lvs.gds` | 349,274 | **absent** |
| `<top>_lvs_pintext.gds` | 351,782 (**+2,508**) | present, on layers 131/135/136/137 |

`+2,508` is exactly the figure `scripts/4b_pnr_route_eval.tcl` records for enabling LEF
macro pin text. `lvs_project.mk` sets `LVS_PG_PIN_TEXT ?= 1` and explains at length why
this project needs it. **But `LVS_PG_PIN_TEXT` only affects the re-stream; it does not
affect which file `LVS_PG=1` selects.** `LVS_PG_GDS_OUT` defaults to `<top>_lvs.gds`, so
`make lvs_batch LVS_PG=1` compares against the pin-text-**off** stream — the filename does
not encode the setting that produced it, so a stale stream silently survives a config change.

Why it matters, measured: with boxed leaves carrying no pin names,
**633,398 isolated layout nets are deleted** before comparison, and the run reconciles
**62,483 nets** — the low number `lvs_project.mk` itself attributes to pin text being off.
The standard-cell routing is not compared at all.

**This is very likely the origin of the "four million unmatched objects" this project
recorded**, though not by the mechanism previously written down. See §6, trap 2.

## 5. Mutation coverage — proof the gate can fail, and where it cannot

**Method.** A real non-equivalence planted at the *design input* (the post-P&R Verilog),
so the whole pipeline is exercised, not a tool intermediate. In module `eth_receivecontrol`,
instance `AOI21D1 g9183__5526` — one definition, one instantiation, so it appears exactly
once in the flattened design — the `A1` and `B` nets were swapped:

```
   -  AOI21D1 g9183__5526 (.A1(n_128), .A2(n_88), .B(n_31),   .ZN(n_151), ...);
   +  AOI21D1 g9183__5526 (.A1(n_31),  .A2(n_88), .B(n_128),  .ZN(n_151), ...);
```

`AOI21` computes `ZN = !((A1 & A2) | B)`, so `A1`↔`B` is a **genuine non-equivalence**,
not a pin-symmetry permutation that graph isomorphism would legitimately absorb.

**Positive control on the mutation itself** (required, because one arm returns a null
result): the swap was confirmed present in the SPICE source Calibre actually read —
`Xg9183__5526 AOI21D1 $PINS A1=n_31 A2=n_88 B=n_128 …` versus `A1=n_128 … B=n_31` in the
control. The mutation reached the compare.

**Result — the two configurations disagree completely:**

| layout stream | control | mutant | verdict |
|---|---|---|---|
| `_lvs.gds` (pin text off) | INCORRECT | INCORRECT | **report byte-identical apart from CPU/elapsed time — MISS** |
| `_lvs_pintext.gds` (pin text on) | INCORRECT | INCORRECT | **DETECTED and named — CATCH** |

Against `_lvs_pintext.gds` the mutant report names the exact defect, with layout
coordinates, and the control report does not mention the instance at all
(`g9183`: 0 hits control, 3 hits mutant; `receivecontrol`: 0 vs 11):

```
X86/X4040(1040.800,1216.435) AOI21D1        …/Xg9183__5526  AOI21D1
  A2: X86/6946                                A2: …/n_88
  ZN: X86/6923                                ZN: …/n_151
  A1: X86/6942                             ** …/n_128 **
  B:  X86/6939                             ** …/n_31  **
  ** X86/6939 **                              A1: …/n_31
  ** X86/6942 **                              B:  …/n_128
```

with the corresponding net records:

```
 55  Net X86/6939   …/receivecontrol1/n_31    ** missing connection ** … Xg9183__5526:A1
 56  Net X86/6942   …/receivecontrol1/n_128   ** missing connection ** … Xg9183__5526:B
```

Attributable, not matching noise: **arbitrary matches are identical (1,046 nets / 72
instances) in both runs**, while matched instances fall 321,855 → 321,750 and unmatched
rise 1,307 → 1,412 (layout) and 1,417 → 1,522 (source).

**Removal verified:** the mutant file was restored to be byte-identical to the original
netlist (`cmp` clean) and re-run; see §9 for the result.

**Consequence.** Both arms return `INCORRECT`, because this design's expected end state is
INCORRECT (§6, trap 1 residue and the pad-ring residue). **So the verdict word alone is
not a gate.** A regression check must compare the *discrepancy detail*, not the banner.

## 6. The four traps, restated with evidence

Each one looks like a design defect and is not. All four were re-measured for this document.

### Trap 1 — cell Verilog must match the netlist's PG convention

The vendor ships two variants of the cell simulation Verilog. The `-e` stubs they produce
differ in pin count:

```
cell Verilog, plain variant  ->  .SUBCKT INVD1 I ZN
cell Verilog, PG variant     ->  .SUBCKT INVD1 I ZN VDD VSS
```

(The two variants sit side by side in the vendor's Front-End release; the PG one carries a
power suffix. `lvs_project.mk` selects it and says why.)

This netlist wires PG on the great majority of instances (**186,721 `.VDD(` and 186,719
`.VSS(` connections**), so the `_pwr` variant is required or Calibre rejects the whole
source with `Wrong pin count` and never reaches a compare. `lvs_project.mk` already selects
`_pwr`. **Fingerprint:** the source is rejected outright; there is no comparison at all.

Note the netlist is **mixed**: tool-inserted cells (`FE_OFC*`, `FE_OFN*`, `LTIE_*`, `CTS_*`)
carry no PG pins, e.g. `INVD1 FE_OFC3089_… (.I(…), .ZN(…));`. That asymmetry is the reason
`.GLOBAL` still has to rescue their supplies — see trap 4.

### Trap 2 — the layout must carry PG net text (a precondition, not a caveat)

A signoff GDS normally streams the special-route power grid **unnamed**, because the
foundry GDS-out map declares `NAME <layer>/PIN` and no `NAME <layer>/SPNET`. Measured, on
one P&R run's three streams, with the same scanner:

| stream | layer-139 (M9) PG text |
|---|---|
| `<top>.gds` (signoff, 2026-08-10) | **none** |
| `<top>_lvs.gds` (PG re-stream) | 2 — `VDD`, `VSS` |
| `<top>_lvs_pintext.gds` | 2 — `VDD`, `VSS` |

Worth exactly two text records, and they are the difference between a comparison and
nothing. **The current shipping stream does carry them** (2 records on 139/0) — the 08-13
derived map folded `NAME <layer>/SPNET` into the signoff stream, so this half of the
precondition is now satisfied without a separate re-stream. The *pin-text* half is not (§4).

**Fingerprint:** millions of unmatched layout devices concentrated in SRAM interiors.
Reproduced live in run A below — after transformation, **layout 2,056,213 nets vs source
62,486**, and **2,010,956 vs 17,268** MN devices, i.e. bitcells folded on the source side
and exploded on the layout side because supply-dependent recognition is disabled. The
mechanism is confirmed; note that in run A the *cause* of the missing supply is a short
(§7), not missing text.

> **Scanner caveat, recorded because it nearly fooled this analysis.** A first pass
> reported "0 text records" in the shipping GDS. That was a bug in the scanner (GDS record
> `0x0D` is `LAYER`, not `PATH`), not a property of the file. Every "0" needs a positive
> control; this one got three streams with known-different answers.

### Trap 3 — LEF obstruction streams as if it were real metal

A LEF `OBS` is a routing blockage, not manufactured metal, but foundry GDS-out maps put it
on the same GDS layer as real metal. Cells that are obstruction and nothing else tile a pad
ring and short every net reaching a pad.

**Status: fixed in the shipping stream, and the fix is only half-derived.** The shipping
stream contains **no LEF obstruction at all** — no `90xx` scratch layers, and
`PAD70GU`/`PAD70NU` are empty structures. So the 34 shorts this trap used to produce are
gone, and the single remaining short (§7) is **not** this trap.

But the map that produced it is stale, and that is a live defect — see §8.

### Trap 4 — no `.GLOBAL` name may be a hard macro's internal net

`.GLOBAL` is unscoped: it merges every net of that name in every `.SUBCKT`. Both boot ROMs
use `VSS` internally as a power-gated virtual ground, so `.GLOBAL VSS` fabricates a short
across the power gate — **in the source only**, which makes every symptom appear inside the
macro and invites the much worse conclusion that the vendor's GDS and CDL disagree.

This is why `LVS_GLOBAL_NETS = VDD VDDIO VSSIO`, with `VSS` deliberately absent.
**The preflight guard discriminates** — negative and positive control, both licence-free:

```
LVS_GLOBAL_NETS="VDD VDDIO VSSIO"        -> OK  no name is a macro internal
LVS_GLOBAL_NETS="VDD VSS VDDIO VSSIO"    -> **  A .GLOBAL NAME IS AN INTERNAL NET OF A HARD MACRO
                                              macro: rom_via / eth_rom_via
                                              net  : VSS -- used 514 time(s), NOT a port
                                              scope: rom_viaWDEC_64WL, rom_viaTILE_TOP
```

**Fingerprint:** a supply net whose *source* connection count exceeds the *layout's*.

**Known cost, do not lose it:** dropping `VSS` from `.GLOBAL` leaves the ~17k tool-inserted
instances that carry no PG pins with floating `<inst>/VSS` source nets, which inflates
source-side `Net VSS` and masks the VSS half of any real PG open. The proper fix is
project-local ROM CDL copies with the internal `VSS` renamed, then restoring `VSS` here.

---

## 7. The shipping stream cannot produce a verdict

**Run A** — layout `ASIC/eth-chiplet/build/full-20260814/outputs/nanosoc_eth_chiplet_pads.gds`
(08-17 13:52), schematic `…/nanosoc_eth_chiplet_pads_pnr.v` (08-17 13:52, same directory and
timestamp, so genuinely the same database):

```
RESULT: LVS NOT MEANINGFUL -- the layout has no GROUND net.   (exit 6)
   Invalid PATHCHK request "! GROUND": no GROUND nets present, operation aborted.
   No layout data for, specifically: VSS
```

Calibre reports **exactly one short, `VDD - VSS`** (tested against the cap: the shorts file
records the cap as 1000 and contains 1 record, so this is a true count, not a truncation).
With the two supplies merged Calibre keeps one name and drops the other, `VSS` ceases to
exist, and supply-dependent device recognition collapses — producing the trap-2 fingerprint
described above.

The flow is **right to refuse**: it ranks NOT MEANINGFUL above INCORRECT precisely so a
verdict about the wrong thing is not read as a design result.

**Cause — deferred to ERC, which isolated it.** A sibling session's ERC run (N65 ERC ships
*inside* the Calibre LVS deck, not as a separate file) attributes the merge to **four real
M5 rail-to-rail shorts**. That is a geometry defect, not an LVS artefact, and it is the
blocker for any LVS verdict on this stream.

Two hypotheses were tested here and **ruled out**, so nobody re-derives them:

- **Mis-placed PG labels.** Both labels sit on their own stripe — `VDD` at (191.0, 191.0) on
  an M9 stripe y 191.0–203.0 and an M8 stripe x 191.0–203.0; `VSS` at (175.0, 175.0) on
  y 175.0–187.0 / x 175.0–187.0. A 4 µm gap separates them. Not a labelling artefact.
- **RDL bridging.** Four of the five top-cell `AP` shapes do geometrically span both a VDD
  and a VSS M9 stripe. **This is overlap on a different layer, not a connection** — there
  are zero `RV` cuts in the top cell — and it was not confirmed as the mechanism. ERC's M5
  finding supersedes it. Recorded only so the overlap is not "rediscovered" as a cause.

## 8. A stale stream-out map is in the P&R path

`scripts/4b_pnr_route_eval.tcl` resolves the stream-out map by glob from
`ASIC/genus-innovus/work/tech/*.derived.map`, generated by `scripts/gdsmap_derive.py`.

```
shipping GDS                     2026-08-17 13:52
work/tech/…derived.map           2026-08-14 08:31      <- what actually streamed
scripts/gdsmap_derive.py         2026-08-17 19:04      <- edited AFTER the stream
```

Regenerating the map to scratch (never in place — a route is live) shows the generator no
longer produces the file on disk:

```
  stale map on disk                        | generator's output today
- M8  LEFPIN,PIN,NET,SPNET,VIA,LEFOBS  ...  | + M8  LEFPIN,PIN,NET,SPNET,VIA  ...
                                            | + M8  LEFOBS                    <+9000>
- M9  LEFPIN,PIN,NET,SPNET,VIA,LEFOBS  ...  | + M9  LEFPIN,PIN,NET,SPNET,VIA  ...
                                            | + M9  LEFOBS                    <+9000>
- AP  LEFPIN,PIN,NET,SPNET,VIA,LEFOBS  ...  | + AP  LEFPIN,PIN,NET,SPNET,VIA  ...
                                            | + AP  LEFOBS                    <+9000>
```
(layer/datatype values are vendor map data and are not reproduced here)

The script's `OBS_KEEP_ON_MASK` was emptied on 2026-08-17 (it had held `{M8, M9, AP}` on a
theory the script's own header now records as refuted), but **no map has been regenerated
since, so that decision has never reached a stream.** The stale map keeps `LEFOBS` on the
real mask layer *and datatype* for exactly the three layers a pad ring uses.

In this particular stream the consequence is nil — no LEF obstruction is streamed at all
(§6 trap 3). The defect is that **`make gdsmap` is not a dependency of the artefact that
consumes it in the archived build**, so map and stream can drift silently. Anyone quoting a
layer-dependent result (antenna, density, DRC) off this stream should check which map made it.

*Not actioned here:* regenerating the map in place would disturb a live route, and
stream-out is another lane's file. Flagged only.

## 9. Runs made for this document

All runs: `nanosoc_eth_chiplet_pads`, Calibre v2023.1_18.8, `-lvs -hier -64 -turbo`,
`< /dev/null`, verdict read from the report.

| # | layout | schematic | result |
|---|---|---|---|
| A | shipping `full-20260814/…pads.gds` | `full-20260814/…pads_pnr.v` | **exit 6 NOT MEANINGFUL** — supplies merged (§7) |
| B | `20260810…/…_lvs.gds` | that run's `_pnr.v` | INCORRECT; 321,803 matched, 1,359/1,469 unmatched, 618/618 unmatched nets, 50/50 ports |
| C | as B | **mutant** `_pnr.v` | INCORRECT; **report identical to B** — mutation missed |
| D | `20260810…/…_lvs_pintext.gds` | that run's `_pnr.v` | INCORRECT; 321,855 matched, 1,307/1,417 unmatched |
| E | as D | **mutant** `_pnr.v` | INCORRECT; 321,750 matched, 1,412/1,522 unmatched; **miswire named** |
| F | as D | mutation **removed** | INCORRECT; **0-line diff from D**; signature absent; 321,855 / 1,307 / 1,417 restored exactly |
| G | `fp1505/outputs/…pads.gds` (08-17 21:33) | `fp1505/…pads_pnr.v` (08-17 21:33) | **the clean run — see §9.1** |
| H | as D | as D, `LVS REPORT MAXIMUM ALL` | counts identical to D; report 159,108 → 462,160 lines |

### 9.1 The working run, on current data: `fp1505`

This is the run to quote. Layout and schematic are the same-timestamp pair from the
`fp1505` floorplan variant, the database a sibling session reports as free of the M5 shorts:

```
Ports:            50        50          0 unmatched        0 unmatched
Nets:          62479     62479          0 unmatched        0 unmatched
Total Inst:   325189    325189          0 unmatched       82 unmatched (source)
```

**Zero unmatched layout objects, zero unmatched nets, zero unmatched ports, and no shorts
file at all** (no shorts were found). The entire residue is **82 source-side bond pads —
42 `PAD70GU` + 40 `PAD70NU`** — which is the expected, documented cost of streaming without
pad obstruction, not a new defect.

The banner still reads `INCORRECT`, driven by the two structural residue classes
(non-identical signal pins and non-floating extra pins on boxed leaves, plus the 82 pads).
**That is the expected end state of a black-box LVS on a Front-End-only PDK, not a
failure** — which is exactly why the verdict word must not be the gate (§10.2).

Its error list is also strictly shorter than the other runs': no `Different numbers of
nets`, no `Different numbers of ports`, no `Connectivity errors`, no `Property errors`.

Caveat, unchanged: **637,417 isolated layout nets were deleted**, so this run is still the
pin-text-off configuration and does **not** compare standard-cell routing. Per §5 it would
not detect the planted miswire. To verify the fabric on this database, re-stream it with
`make lvs_pg_gds LVS_PG_PIN_TEXT=1` and compare against that stream.

## 10. Recommendations

1. **Make the layout selection encode its configuration.** Either name the re-stream
   output after the knob (`<top>_lvs_pintext.gds` when `LVS_PG_PIN_TEXT=1`) or have
   `lvs-preflight` assert that the selected GDS carries pin-name text when the project asks
   for it. Today a stale stream silently outlives the setting that should have replaced it.
   **Until then, run LVS with `LVS_GDS=<top>_lvs_pintext.gds` explicitly** — `LVS_PG=1`
   selects the stream that cannot see a miswire.
2. **Gate on the discrepancy detail, not the verdict word.** Both arms of the mutation
   returned `INCORRECT`. A CI check that keys on the banner would have passed the mutant.
   Compare unmatched-instance and unmatched-net counts against a recorded baseline.
3. **Know what the report cap does and does not truncate — tested, not assumed.** Re-running
   the identical comparison with `LVS REPORT MAXIMUM ALL` (run H) grew the report from
   **159,108 to 462,160 lines** while leaving **every summary count identical**
   (325,189-style totals, unmatched, ports, nets all unchanged). So the **counts quoted in
   this document are safe at the default cap**, and the **discrepancy detail is not** — about
   two thirds of the records are withheld. Uncap before reading individual records or
   concluding a class is empty. (An earlier draft of this file inferred from "every report
   stops at record 999" that the counts were capped; run H disproves that — the 999 is
   section numbering and is identical uncapped.)
4. **Fix the four M5 shorts, then re-run LVS on the shipping stream.** No LVS verdict about
   that stream means anything until the supplies separate.
5. **Correct the two docs that say LVS cannot run here** (`09-signoff-checklist.md` item 16,
   `10-tapeout-submission.md` §4.3), and `docs/index.md`.

## 11. What was NOT verified

- Cell interiors, and pin-level wiring on boxed leaves in the `_lvs.gds` configuration.
- The pad ring — bond pads are empty structures in every stream examined.
- Device-level comparison for standard cells, IO and pads: impossible without Back-End
  packages, and a foundry step.
- Whether `fp1505` is the right database to tape out — only that it reaches a clean LVS
  verdict. Its standard-cell routing is still uncompared (pin text off, §9.1).
- The AP/M9 overlap noted in §7 was not traced to a connection either way.
