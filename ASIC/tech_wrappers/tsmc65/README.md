# TSMC 65 nm (CLN65LP) — node-level findings

Things that are true about **the node, the PDK and the signoff tools**, not about
`nanosoc_eth_chiplet`. Every one of them cost at least half a day, several cost a day
and produced a confident wrong answer first, and none of them is discoverable by
reading a manual front to back.

The design-specific evidence — run directories, counts, the broker correspondence —
lives in [`docs/tapeout/`](../../../docs/tapeout/00-index.md), and page
[28](../../../docs/tapeout/28-drc-status-and-attribution.md) in particular. This page
is the part that survives the design: take it to the next chiplet on this node, or to
another site's CLN65LP install, and it should still be true.

> **Written 2026-08-13.** Every number below was measured on this site
> (`srv03335`), with Innovus 21.11-s130_1 and Calibre v2023.1_18.8, against
> `CLN65S_9M_6X1Z1U.26_2a` unless another deck is named. Where a claim is an
> inference rather than a measurement it says so, and says what would falsify it.

---

## 0. Citation policy — read before you edit this file

This repository is public. Foundry collateral under `/tsmc65pdk` and vendor IP under
`/research` are licensed to this site and **must not be reproduced here**: no SVRF
rule bodies, no LEF geometry, no layer/datatype tables, no cell dimensions lifted from
a vendor file.

So this page **cites and describes**. A rule is referred to by name plus the deck it
lives in — e.g. *`PO.R.8`, in
`$TSMC_65_HOME/CMOS/util/MAIN_DRC_TopMu/CLN65S_9M_6X1Z1U.26_2a`* — and what it
*means* is written out in ordinary words. Open the deck and search for the rule name if
you need the text; it is one `grep` away and it is not ours to republish. Do not record
line numbers into a vendor deck either — an accumulated list of them is a structural map
of the file, and it tells a reader exactly what to reconstruct and where.

Where a number is needed to make an argument land, **prefer a measurement of our own
design over a parameter of theirs — but only where the measurement does not hand over
the parameter**. That qualifier is the one that gets forgotten. A per-window density
maximum that sits a hair under the rule's threshold *states that threshold by
inference*, to as many significant figures as you print, and so it is redacted for
exactly the same reason the threshold itself is. Say which check failed and what it
cost us; do not print either number.

Both trees are read-only and shared. Nothing in this flow writes to either. If a fix
appears to need an edit there, copy the file into the project and point the flow at the
copy — see the patched IO driver LEF under `generated/` for the worked example.

---

## 1. The traps index

Seven things that look fine and are not. Each row is a **symptom you will actually
see**, not a rule you are supposed to already know.

| # | What you see | What it actually is | § |
|---|---|---|---|
| 1 | The PDK ships an Innovus stream-out map, so you use it | It is a mechanical transform of a **layout-editor** map and was never a signoff artefact. Cadence's own reference says the map must be customised. There is no converter, anywhere | [§2](#2-the-pdk-stream-out-map-is-not-a-signoff-map) |
| 2 | GDS streams, DRC runs, thousands of antenna and width results | LEF **obstruction** is being streamed as manufactured metal. 68.8% of all metal in our stream was phantom; it caused *all* 1,549 antenna results | [§3](#3-lef-obstruction-is-not-metal) |
| 3 | You fix trap 2 with a blanket "obstruction off the mask layers" policy | Bond-pad cells declare their **passivation opening and top metal as `OBS`**. A blanket policy silently deletes the openings — and nothing in the flow complains | [§3.3](#33-the-caveat-that-deserves-its-own-warning-bond-pad-openings-are-obs) |
| 4 | LEF macro pins stream, shapes and all | Their **names** do not, without an explicit `NAME <layer>/LEFPIN` row. Boxed leaves then extract with zero pins and LVS degrades to a cell census | [§4](#4-name-rows-what-streams-and-what-merely-appears-to) |
| 5 | Calibre reports `Result Count = 1` for a density check | It merged **thousands** of failing windows into one result. Ours reported 1 against 2,138 | [§5](#5-calibre-density-reporting-result-count--1-can-mean-2138) |
| 6 | A `.density` file looks like a full window map you can plot | It is a **failure list**. Nothing in it passed. Reading it as a survey inverts every conclusion you draw from it | [§5.2](#52-the-density-files-are-failure-lists--proven-three-ways) |
| 7 | Hundreds of DRC results inside a vendor macro ⇒ vendor defect | On a **black-box** GDS it is very likely an artefact of black-boxing. Checking the macro standalone cannot tell you which, because standalone *is* the black-box condition | [§6](#6-por8-and-what-a-black-box-gds-can-and-cannot-prove) |

And one that is not a trap but a habit — [§8](#8-method-what-would-this-look-like-if-i-were-wrong):
**several confident conclusions in this record were wrong because the test had no
control.** Three of them were wrong in a direction that blamed somebody else.

---

## 2. The PDK stream-out map is not a signoff map

### 2.1 Two file formats, one filename extension, different meanings

A Virtuoso layer map and an Innovus `GdsOutMap` look alike — four whitespace-separated
columns, layer name on the left, GDS number and datatype on the right — and they are
not the same kind of file.

| | column 2 is… | grammatically | answers |
|---|---|---|---|
| Virtuoso layer map | a **techPurpose** | an adjective | "what kind of shape did a human draw here?" |
| Innovus `GdsOutMap` | a **layerObjType** | a verb | "**which traversal** of the netlist and floorplan should manufacture geometry onto this layer?" |

That distinction is the whole finding. `NET`, `SPNET`, `PIN`, `LEFPIN` and `VIA` are
five different walks of the database that all emit metal; in a layout editor they are
one purpose, `drawing`, because a human drew all five with the same pen. `FILL` and
`VIAFILL` likewise collapse onto `dummy`. And `LEFOBS` — obstruction — collapses onto
**nothing at all**, because a layout editor has no concept of a routing blockage that
is not also a drawn shape.

The fan-out is therefore one-to-many and **cannot be computed**. It is a judgement per
object type. That is why TSMC ships a static file and not a script.

### 2.2 Innovus has a dedicated error for being handed the wrong one

`IMPOGDS-391` (`/eda/cadence/innovus/doc/innovuserrmsg/IMPOGDS-391.html`) exists for
exactly this mistake: an object type that is not legal for a layer, with the message
text volunteering that the map "maybe being a DFII/Virtuoso map file". The tool
anticipated the confusion. Its suggested remedies are (a) use the foundry map, or
(b) let `streamOut` emit a generic map with no `-mapFile` and edit that.

Note what remedy (a) does **not** say: that the foundry map is fit to sign off with.

### 2.3 The PDK's Innovus map declares its own provenance

Its trailer records that it was transformed from a Virtuoso layout-editor map
(`virtuoso_65nm_1P9M_6X1Z1U_24a.map`, dated Mar 30 2020). It is not lying about
itself, and nothing in it is wrong *for a layout editor* — in a layout editor,
drawing a blockage on the layer it blocks is the correct thing to do.

Cadence's `streamOut` reference and the *About the GDSII Stream or OASIS Map File*
section of the User Guide both say, in as many words, that you must customise the map
for your design. Cadence's own example map carries obstruction on a separate layer and
includes `NAME <layer>/NET`, `/SPNET` and `/LEFPIN` rows. **Customising is the
documented workflow, not a deviation from it.**

### 2.4 There is no converter

Looked for, and not found: in Innovus, in Virtuoso, in the PDK, and in TSMC's shipped
utilities. The conversion is not mechanical (§2.1), so it is unsurprising that nobody
ships one — but it is worth writing down that the search was done, because the
absence looks like something you failed to locate rather than something that does not
exist.

### 2.5 What this project does instead

`ASIC/genus-innovus/scripts/gdsmap_derive.py` **derives** the map from two read-only
foundry inputs (the PDK map, and the tech LEF that Innovus actually loaded). Read its
header: every deviation from the vendor row set is argued there, next to the code that
implements it, which is where such an argument cannot drift.

Two properties are worth copying to any other node:

- **The tech LEF is the authority for which layers exist**, not the Virtuoso techfile.
  The map's left column has to match the LEF the tool loaded. The MS Interoperability
  Guide warns the two can disagree.
- **The generator is gated by a parity test.** `make -C ASIC/genus-innovus gdsmap-parity`
  runs it in a mode that must reproduce TSMC's own row set exactly — 40 of 40 shared
  rows, the only permitted difference being two dead rows for metals above this 1P9M
  stack. It needs no licence, takes seconds, and it is what catches a PDK bump
  changing the map underneath the flow.

---

## 3. LEF obstruction is not metal

### 3.1 What it cost

A LEF `OBS` block is a **routing blockage** — "do not route here". It describes no
manufactured shape. The stock map routes it to the same GDS layer as real metal, and
`write_stream -output_macros` faithfully emits it, because on a Front-End-only PDK the
abstract is all there is.

Measured 2026-08-10, KLayout layer census over the whole stream:

| | µm² |
|---|---:|
| real metal | 3,318,443 |
| obstruction streamed as metal | **7,367,743** |
| total | 10,644,168 |

**7.37 mm² of phantom conductor — 68.8% of all metal in the GDS, and 2.30× the die
area.** On M7 the stream was 91.1% phantom.

Downstream, on the same routed database:

| result class | with obstruction on the mask layers | with it moved off |
|---|---:|---:|
| `A.R.8.3` antenna | **1,549**, all on one net | **0** of 714 rulechecks |
| `M*.W.3` pad blankets | ~1,300 | 0 |
| `CSR.R.1` corners | 56 | 0 |
| design-owned results | 1,577 | 491 |

The antenna number has a clean mechanism. The pad-ring cells that tile the die edge
have no pins and nothing but a full-footprint `OBS` block, so they streamed as a
**continuous band around the die** — 899,100 µm², which is exactly the die area minus
the inner rectangle they enclose. Calibre read that band as one 901,003 µm² floating
conductor and charged every plasma-charging ratio against it.

### 3.2 There is no correct foundry layer to move it to

The obvious fix — "put obstruction on the foundry's blockage purpose" — has no target.
TSMC's layout-editor purpose table defines **no blockage or obstruction purpose on any
layer**: zero hits for `blockage` across all 1,452 of its rows. That absence is *why*
the mechanical transform put `LEFOBS` on `drawing`. It was not a decision; it was the
only slot the source file had.

So the destination has to be invented. This project uses `<layer>+9000`, asserted free
of collisions, and the same base in both the stream-out generator and the LVS
re-stream script so the two agree. **Move, do not drop**: the geometry stays in the
GDS, stays inspectable, and stays recoverable if it turns out to matter. Dropping is
defensible for a *submission* stream, which arguably should carry no layer absent from
the foundry table — but that is a stripping step at the very end, not a reason to
destroy data on the way out of P&R.

### 3.3 The caveat that deserves its own warning: bond-pad openings are `OBS`

**This is the part that will bite the next person, and it is the reverse of everything
above.**

Bond-pad cells declare their **passivation opening and their top-level metal as `OBS`**,
not as pins. There is nothing perverse about that from the library's point of view — an
abstract's job is to tell the router where not to go, and a bond pad is a large keep-out
with a hole in it.

The consequence: a blanket "all `LEFOBS` moves to a scratch layer" policy **silently
removes the bond-pad openings from the stream**. No error, no warning, no changed
record count worth noticing. A chip cannot be bonded through a passivation opening that
is not on the mask.

It was caught only by **streaming a previously taped-out GDS through the same policy
and diffing the two** — i.e. by having a known-good artefact to compare against. There
is no self-check for this inside a single run: the stream is internally consistent
either way.

Practical rules that follow:

1. **Never apply an obstruction policy blindly across all cell classes.** Pad and
   bond-pad masters need separate treatment from core cells and routing blockages.
2. **Keep a taped-out GDS around as a control.** It is the only reference that catches
   a whole *category* of shape going missing, as opposed to a count moving.
3. **Diff structure-by-structure, not by total record count.** §7 explains why totals
   are blind here: the obstruction that dominated the stream by *area* was 0.2% of it
   by *record count*, because M2–M7 carried only 14 shapes each. Few shapes, enormous
   area. A record-count check would never have surfaced any of this.

### 3.4 And a hole the fix leaves open — say it in the same breath

Removing the obstruction removes the **only** pad-ring geometry a Front-End-only stream
has. The real spacer cells carry structured supply buses; the abstract flattened them
into one slab; with the slab gone there is nothing in its place.

**Pad-ring power connectivity is therefore not verified by LVS at all, and cannot be
without back-end cell GDS for the IO library.** A clean run after this fix says nothing
whatsoever about whether the IO supplies are correctly bussed around the ring. Do not
let a later green result be read as covering it.

---

## 4. `NAME` rows: what streams, and what merely appears to

### 4.1 `NAME <layer>/LEFPIN` is required, and its absence is silent

Without it, LEF macro pins stream their **shapes** — they are in the geometry row — and
not their **names**. Measured 2026-08-13: every IO structure in the tapeout GDS carried
`text=0`, while the corresponding M7 pin shapes were present and correct. The pins were
there. Nothing identified them.

Adding the rows fixed it exactly: the M7 pin-text layer went 0 → 25 records, one label
per M7 pin shape in the pad drivers, and +2,508 labels across all layers.

Why it matters beyond tidiness: a cell that is `LVS BOX`ed is compared as a primitive
**with pins**, matched by its pin signature. Calibre omits unnamed box-cell pins unless
they touch devices or texted ports (`LVS NETLIST UNNAMED BOX PINS`, SVRF manual), and a
Front-End-only leaf has neither. So both sides reduce to zero pins and the boxed leaves
match on **name and count only** — on one run, 323,162 instances "matched" without a
single standard-cell connection being compared. That is a cell census, not a netlist
comparison.

`NAME <layer>/SPNET` is the same story for the power grid, which otherwise streams
anonymous and leaves the ERC power/ground checks vacuous. It costs two text records
here, because `SPNET` writes one label per special net and this power plan special-routes
two.

### 4.2 Comma-separated `NAME` rows are legal — and all the evidence says otherwise

The geometry rows in every map use comma-separated object-type lists. The natural
question is whether `NAME` rows can too, so that several object types sharing one text
layer collapse into one row.

**Every available signal says no:**

- Across all 54 PDK stack maps: **648 `NAME` rows, 0 containing a comma.**
- The Innovus UG's syntax line for `NAME` rows is grammatically **singular** — "can be
  *a* composite layer name / object type".
- Cadence's own reference example writes one row per object type.
- `IMPOGDS-1556` exists specifically for a map line with the wrong number of fields.

**The parser accepts them anyway.** Verified 2026-08-13 on Innovus 21.11-s130_1 by
generating both forms, re-streaming the **same routed database**, and censusing both:

```
structures  2,579     = 2,579
geometry    3,587,844 = 3,587,844
text        351,775   = 351,775
M7 pin text 25        = 25
```

Byte-identical output apart from the GDSII timestamp. No `IMPOGDS-391`, `-392`, `-399`
or `-1556`.

Two things to take from this. First, the finding itself: 30 `NAME` rows collapse to 10,
and a future reader who "tidies" them apart is not fixing anything. Second, and more
useful — **the failure mode this had to rule out was the quiet one**: a row skipped with
no error and the labels simply absent. Which is why the test was a census and not "the
tool did not complain". See §7.

---

## 5. Calibre density reporting: `Result Count = 1` can mean 2,138

### 5.1 The merge

Calibre merges every failing window of a density check into **one** result. Measured on
our 2026-08-12 baseline:

| check | failing windows in the `.density` file | `TOTAL Result Count` in the summary |
|---|---:|---:|
| `M1.DN.1` | 784 | 1 |
| `M2.DN.1` | 853 | 1 |
| `M3.DN.1` | 866 | 2 |
| `M4.DN.1` | 970 | 4 |
| `M5.DN.1` | 1,195 | 5 |
| `M6.DN.1` | 1,955 | 1 |
| `M7.DN.1` | 2,138 | 1 |
| `M8.DN.1` | 1,876 | 1 |
| **total** | **10,637** | **16** |

A count-based gate scores a ten-thousand-window density failure as sixteen results —
i.e. as rounding error. That is how the largest real defect in this design stayed
invisible to CI for weeks. `scripts/ci/drc_census.py` therefore counts **windows**, not
results, and gates on core-only windows (see §5.3).

### 5.2 The `.density` files are FAILURE LISTS — proven three ways

The files are lists of `x1 y1 x2 y2 density` and they look like a full window map of the
die. They are not. They contain **only the windows that failed**, because the rule's
predicate selects the violating windows and the same selection is what gets printed
(`…/CLN65S_9M_6X1Z1U.26_2a:13721` for `M6.DN.1`; read it there).

Three independent proofs, all from our own runs:

1. **The lengths differ per layer, though the window geometry is identical.** Every
   file starts with the same first window, and `M1.DN.1` has 784 lines while
   `M7.DN.1` has 2,138. A full survey of a fixed die with a fixed window would give
   every layer the *same* number of lines.
2. **No window in any file reaches its own threshold.** Across `M1`–`M7` every
   listed maximum falls fractionally short of that layer's own bound, and none
   reaches or exceeds it. If these were all windows, some would pass.
3. **The ceiling tracks each layer's own threshold, not a global one.** `M8.DN.1`'s
   maximum sits just under a *different*, higher bound than the one `M1`–`M7` sit
   under. A printing artefact or a clamp would use one number; a failure list uses
   each rule's.

> Per-layer minimum-density thresholds and the measured per-window maxima redacted —
> TSMC licence forbids reproduction, and the maxima state the thresholds by
> inference. Source: the `Mx.DN.1` rules in the mini@sic rule deck. Re-read them
> there before acting on any density number.

Proof 3 is the one that closes it, and it is the one that needs no knowledge of the
rule text at all.

**Two separate sessions misread this format on the same day, in opposite directions** —
one reading the files as a full window map (and concluding density was fine because most
windows "passed"), the other reading a parser miss as a zero (and concluding a check
passed while its file listed failures). Both readings are self-consistent. Neither
survives proof 3.

### 5.3 The number that means something is *core-only*

A raw failing-window count does not separate a design defect from the IO abstraction,
and for the maximum-density family it is almost entirely the latter: one of our
maximum-density checks reported 8,026 failing windows of which **8,026 touched the pad
band and 0 were core-only**, at 92–100% metal — the 100%-fill obstruction slabs of §3.
Gating on the raw total charges ~56k pad-artefact windows to the design and buries the
minimum-density failures that are genuinely ours.

The pad band is **not one depth for all layers**. The IO driver row is one depth; the
bond pads reach further in and carry solid top-metal plates. Using a single inset for
every layer charged this design 324 top-metal windows that sit on the bond-pad blanket.
`drc_census.py` uses a deeper band for the top metals for exactly this reason.

### 5.4 Saturation cannot be detected the obvious way

When a check hits `DRC MAXIMUM RESULTS`, Calibre writes the **truncated** value into
*both* the count and the origcount fields. A `count < origcount` test therefore reports
a saturated check as complete. The only valid tests are:

- does any rulecheck equal the cap **exactly**; and
- does the log carry a `MAXIMUM RDB limit … reached` line.

Related, same family: `check_connectivity` stops at `Number of errors exceeds the limit
1000`, so open-net counts from a capped run are not measurements and must not be quoted.
A capped run has an unknown true count — it is not a pass and it is not a fail, it is
**not a measurement**, and a signoff gate should refuse to vouch for it either way.

---

## 6. `PO.R.8`, and what a black-box GDS can and cannot prove

### 6.1 The finding

Our chip reports **691 `PO.R.8` floating-gate results, every one inside Arm compiled
memories** whose real vendor GDS we merge. They are stable across twelve years of rule
revisions (identical under the 2012 and 2024 decks). For weeks the obvious reading held:
the layout is vendor IP, it is already present, so these are vendor defects and no
import will resolve them.

**That reading is wrong, and the control that breaks it is cheap.**

### 6.2 The control

Take a **previously taped-out GDS** — a full chip, with real standard-cell layout
throughout. Run the same deck on it four times, changing exactly one thing: which cell
is `LAYOUT PRIMARY`.

| `LAYOUT PRIMARY` | `PO.R.8` |
|---|---:|
| the full chip | 148 (146 in the top cell, 2 in one standard cell) |
| `rf_08k`, promoted | **80** |
| `rf_16k`, promoted | **82** |
| `rom_via`, promoted | **105** |

Now put all four contexts side by side. The macro geometry is equivalent in both files;
only what surrounds it differs:

| context | what surrounds the macro | `rf_08k` | `rf_16k` |
|---|---|---:|---:|
| our macro alone, as `LAYOUT PRIMARY` | nothing | 80 | 82 |
| inside **our** chip | LEF abstracts — metal only, no diffusion | 80 | 82 |
| the taped-out file's macro alone, as `LAYOUT PRIMARY` | nothing | 80 | 82 |
| inside the **taped-out** chip | real cell layout, with diffusion | **0** | **0** |

(Ours sum from the by-cell breakdown as 4 + 68 + 8 = 80 and 4 + 70 + 8 = 82.) In the
full-chip run those macros do not appear in the by-cell breakdown at all — cells with no
results are not listed.

Same GDS. Same deck. Same day. One knob. **Three of the four rows agree, and they are
the three that share the defect.**

### 6.3 What it means

`PO.R.8` asks whether a poly gate's net has a path to diffusion. Inside the macro, the
control-logic gates reach diffusion by going **out through the macro pins** into the
surrounding circuitry.

- Promote the macro to primary and everything outside it is absent. The nets dead-end.
  Every gate looks floating.
- Put the same macro inside a full chip with real standard-cell layout and the nets
  terminate on real diffusion. Zero results.
- Put it inside **our** chip, where the surrounding standard cells are LEF abstracts
  carrying metal only and no diffusion at all, and the nets dead-end again — at a
  different boundary, for the same reason.

Our 691 is the standalone condition wearing a different hat. It is an artefact of
shipping a black-box GDS, and it is the same artefact as the 148 above, not a vendor
defect.

**The inference, stated as an inference:** we expect these to clear when the IO and
standard-cell layout is imported. That has not been measured on *our* GDS, because we
cannot measure it here — no cell layout exists on this site. It would be falsified by an
import that supplies real cell layout and still reports 691.

### 6.4 The methodological point, which generalises past this rule

**Running a macro standalone cannot discriminate between "the macro is broken" and "the
macro is being checked out of context", because standalone *is* the out-of-context
condition.** The test has no control. It cannot come back negative.

This is not hypothetical. An earlier pass at this analysis ran exactly that test, got a
number matching the in-chip count, and read the match as confirmation that the
violations were inherent to the macro. It was comparing two contexts that **share the
defect** — rows 1 and 2 of the table above. The taped-out chip is the fourth row, and it
is the control that was missing.

This is not specific to `PO.R.8`. Any rule whose predicate traverses connectivity out of
the cell — floating gate, antenna ratio, latch-up, ERC, well tie — has the same property.
On a Front-End-only PDK, *every* such check is running in the black-box condition
whether you asked for it or not, and a zero from one is `NOT CHECKED`, not `CLEAN`.

The discriminating test is the one above: **the same file, at two different depths.**

### 6.5 The vendor-waiver question, corrected

The memory compiler release notes waive some density and `PATHCHK` categories in these
macros. They do **not** waive `PO.R.8`, and it is worth knowing why the search for one
fails.

The only `PO.R.8` waiver the vendor publishes is for a **standard-cell** library, not
the memory compilers — and its stated reason is that the rule is waived *at IP level
because it must be checked at chip level*. Which is the same statement as §6.3, arriving
from the vendor's side: the rule is not answerable about a cell in isolation.

So "get a waiver" was the wrong ask. The right one is "confirm this clears at chip level
after import", and the evidence to send with it is the §6.2 table.

---

## 7. Re-streaming, and why the census is the check

### 7.1 A map change needs no P&R re-run

A stream-out map cannot alter placement or routing. Re-running P&R to test one proves
nothing and produces a *different* database, so the A/B is no longer an A/B.

`read_db` + `write_stream` against the existing routed database takes **~84 seconds**:

```sh
make -C ASIC/genus-innovus restream          # new GDS from the existing routed DB
make -C ASIC/genus-innovus restream-census   # per-layer record counts
```

This turns "what does this map row actually do?" from a five-hour question into a
two-minute one, which is the difference between measuring it and guessing.

Beware the paired-variable trap the target documents: `restream` and `restream-census`
share the output-path variable. Override one and not the other and you will census the
wrong file, confidently.

### 7.2 The census is the only thing that catches a silently-skipped row

**"The tool did not complain" is not verification.** The failure mode that matters for
map changes is quiet: a row is not honoured, no message is emitted, and the labels are
simply absent from the stream. Every other symptom of that — a valid GDS, a completed
run, a plausible file size — looks like success.

So the check is a **census**, with reference numbers written down where the target that
produces them lives. Ours, on the current default map:

```
structures 2,579   geometry 3,587,844   text 351,775
pad-driver pin text: 25 records on each of the three driver pin layers
obstruction on the 9031–9074 scratch range: 6,631 records
```

The 25s are the sentinel: one label per pin shape in the pad drivers. **If they come
back 0, the `NAME <layer>/LEFPIN` rows are not being honoured** — and nothing else in
the flow would tell you.

The same asymmetry is why record counts alone are insufficient in the other direction
(§3.3): the obstruction that was 68.8% of the stream *by area* was 0.2% of it *by
record count*. **Census what the change was supposed to affect, on the axis it affects
it.**

---

## 8. Method: "what would this look like if I were wrong?"

This is the most transferable thing on the page, and the least technical.

Several conclusions in this record were held confidently and were wrong. They were not
wrong through carelessness — each was supported by real evidence, consistently
interpreted. They were wrong because **the test had no control**, so there was no
observation that could have come back and contradicted them.

| the confident conclusion | why it survived | what broke it |
|---|---|---|
| The 1,549 antenna results and the pad blankets are the packaging partner's problem | Every result really was on abstract geometry we did not author | Re-streaming with obstruction moved: 1,549 → **0**. They were ours |
| The floating conductor Calibre saw was our power mesh | Its area was ~28% of the die; a power mesh is about that | It was the pad-ring obstruction band. A mesh and a blanket are both big |
| `PO.R.8` is a vendor defect; no import resolves it | The vendor GDS is genuinely merged, and the counts are stable back to 2012 | The same macro at full-chip depth in a taped-out GDS: **zero** |
| The `.density` files map every window | They are plausible files full of plausible numbers | Their ceiling tracks each layer's *own* threshold |
| The `.density` files must be complete because a check "passed" while its file listed failures | A parser miss rendered as `0` | The miss was the bug; the file was right |

The common shape: **a single observation, interpreted, with nothing that could have
disagreed.** Three of the five assigned the fault to somebody else, which is the
direction in which a missing control is least likely to be noticed.

So, three habits worth more than any specific number above:

1. **Before believing a result, name the observation that would refute it.** If you
   cannot name one, you have not run a test — you have taken a reading.
2. **Change one thing against a fixed reference.** Same database, same file, same deck,
   one knob. The §6.2 table and the §3.1 A/B are both this, and both took under an hour.
3. **Ask whether your test can come back negative at all.** A standalone macro run
   cannot exonerate a macro. A run with no control cannot surprise you. Those are not
   experiments, however much output they produce.

And when you write it down: **record the prediction before the run**, so it can be
scored rather than rationalised afterwards. `ASIC/lvs-flow/lvs_pg_emit.tcl` does this
in its header and it is worth copying.

---

## 9. Where each of these lives in code

Findings tied to a script belong **in that script's header**, where they cannot drift
away from the thing they describe. This page is the durable, design-independent
account; these are the places the same facts are enforced.

| Finding | Enforced / argued in |
|---|---|
| Map derivation, object-type policy, parity test | `ASIC/genus-innovus/scripts/gdsmap_derive.py` (header + the policy table) |
| `make gdsmap`, `gdsmap-parity`, `restream`, `restream-census` and their reference numbers | `ASIC/genus-innovus/Makefile` |
| Which map the route stage streams with, and why it deviates | `ASIC/genus-innovus/scripts/4b_pnr_route_eval.tcl` |
| Obstruction and pin-text handling for the LVS stream; the pad-ring coverage hole | `ASIC/lvs-flow/lvs_pg_emit.tcl` |
| Density windows, saturation, owner attribution, the pad-band inset | `scripts/ci/drc_census.py` |
| Deck path, top cell, die box — derived, never typed twice | `ASIC/genus-innovus/drc_project.mk` |
| This design's measured DRC/ANT/BND status and its broker correspondence | `docs/tapeout/28-drc-status-and-attribution.md`, `docs/tapeout/27-broker-questions-SEND-NOW.md` |

**Portability note.** This page is deliberately written to be liftable into a
node-level pack (`ASIC/asic-toolkit/tech/tsmc65/`) with no edits beyond the file
paths in this table — it names no die size, no macro, no net name of this design. Its
§3 overlaps that pack's existing stream-out-map section; §§4–8 have no counterpart
there yet and are the parts most worth promoting.
