# Rough DRC with KLayout — the laptop parallel to Calibre

`ASIC/genus-innovus` `make drc` is **signoff**: Calibre, the real TSMC deck, 1,904
rulechecks, a licence and a lab machine. This directory is the **second opinion**:
one open-source binary, one generated deck of 156 checks, one GDS, no licence, no PDK
mount, no X display. A window of the die takes seconds to a minute on a laptop, and it
tells you whether the router obeyed its own tech file.

It is not signoff and it never will be. Read [What it does not
check](#what-it-does-not-check) before quoting a number from it.

> Verified on `srv03335`, KLayout 0.30.10, against
> `runs/20260810T065131Z_honest-full-pnr2/outputs/nanosoc_eth_chiplet_pads.gds`
> (298 MB, 2,459 cells) — the same stream `calibre_runs/drc_track2` ran on, so the two
> results are directly comparable.

---

## TL;DR

On the lab server, once, to build the deck:

```sh
cd ASIC/klayout-drc
make deck                       # reads /tsmc65pdk, writes decks/ (gitignored)
```

Anywhere, to run it:

```sh
make drc CLIP=650,300,700,350                   # one window, all layers — ~1 min
make drc CLIP=600,250,750,400 ONLY=M4,VIA3      # one window, two layers — 14 s
make drc                                        # whole die — hours, >7 GB, see below
make compare                                    # counts next to Calibre's
```

To take it home:

```sh
make pack BOX=600,250,750,400   # tarball: deck + GDS window + runner
```

then on the laptop, with only `klayout` installed — no PDK, no licence:

```sh
./run_drc.sh nanosoc_eth_chiplet_pads_clip.gds
klayout <gds> -m <rundir>/<tag>.lyrdb            # markers in the browser
```

A 150 µm window is 5.6 MB (9 MB for the whole tarball); a 50 µm window is 0.6 MB.

---

## Why it is generated and not written by hand

Two reasons, and the second is load-bearing.

**The numbers stay honest.** Every constraint comes out of
`PRTF_EDI_N65_9M_6X1Z1U_RDL.24a.tlef` — the same tech LEF Innovus routed against
(`scripts/config.tcl:123`) — and the GDS layer numbers come out of
`PRTF_EDI_N65_gdsout_6X1Z1U.24a.map`, the same map `write_stream` used
(`asic-flows/Cadence/4_pnr_route.tcl:61`). So this deck asks *did the router obey its
own tech file*, not *does this match what someone typed into a `.drc` six months ago*.
If the metal stack changes, `make deck` again.

**No foundry numbers are committed.** `/tsmc65pdk` is NDA collateral. The generated deck
contains TSMC dimensions, so `decks/` is `.gitignore`d. `scripts/gen_deck.py` holds no
rule values at all — it is pure structure, and it is the thing that gets reviewed in a
diff.

The foundry tech LEF is read-only and is never copied, patched or `sed`-ed — same rule
the Calibre wrapper deck follows.

### ⚠ The generated deck is foundry-derived data

`make pack` produces a tarball containing the deck **and** the design. Both are
controlled: the deck is TSMC's dimensions, the GDS is ours. Carrying either off a
licensed machine is a decision for you and the broker, not something this flow can make
for you. The scripts will not stop you; the warning is printed and it is deliberate.

---

## What it checks

Generated per routing layer (M1–M9, AP) and per cut layer (VIA1–VIA8, RV):

**Rule names ending `~` are approximations that over-report. Do not count them; use
them to decide where to look.**

| Rule | From LEF | Status |
|---|---|---|
| `<L>.W.1` min width | `WIDTH` | exact |
| `<L>.S.1` min space | `SPACINGTABLE` row 0 | exact |
| `<L>.A.1` min area | `AREA` | exact |
| `<L>.A.2` min enclosed area | `MINENCLOSEDAREA` | exact |
| `<L>.G.4` min step | `LEF57_MINSTEP` | exact for `MAXEDGES 1` |
| `<L>.GRID` off manufacturing grid | `MANUFACTURINGGRID` | exact |
| `<L>.ANGLE` non-orthogonal edge | — | exact |
| `VIAn.S.1` cut space | `SPACING` | exact |
| `VIAn.R.0:<M>` cut not covered by metal | — | exact |
| `VIAn.R.2:<M>` cut enclosure | `VIARULE … ENCLOSURE` | exact |
| `<L>.S.2~…` width/run-length-dependent space | `SPACINGTABLE PARALLELRUNLENGTH` | **over-reports** |
| `<L>.S.EOL~` end-of-line space | `LEF57_SPACING` | **over-reports** |

Three of these are worth explaining, because the obvious implementation of each is
wrong.

**Via enclosure is one-sided.** The LEF says `ENCLOSURE 0.040 0` — the overhang is
required on **one pair of opposite sides only**. A plain all-round enclosure check flags
every legal via on a minimum-width wire. The deck shrinks the metal anisotropically and
asks for containment in the x-shrunk layer *or* the y-shrunk layer, which is exactly the
rule.

**Min step is about consecutive short edges.** `MINSTEP 0.09 MAXEDGES 1` is violated
only when **two** edges shorter than the rule are consecutive; a lone short edge is an
ordinary minimum-width wire end and is legal. Flagging every short edge would bury the
report. The deck widens each short edge outwards into a thin band, lengthened by one
dbu at each end, so two consecutive bands overlap at their shared corner and nowhere
else — `merged(2)`, the doubly-covered area, is then exactly one marker per illegal
step. Validated on a synthetic layout carrying one true violation and three legal
lookalikes: 3 short edges, 1 marker, at the right coordinate.

**Width-dependent spacing needs the run length too — and still over-reports.** A
`PARALLELRUNLENGTH` cell says *two shapes whose wider one is ≥ W and which run parallel
for ≥ RL must be S apart*. Drop the run length and "two 5 µm stripes side by side"
becomes "any two shapes within 1.5 µm of each other": measured on one 150 µm window,
**175 markers without the run length and 0 with it**. So the deck applies both
conditions (`space(projection, projection_limits(RL, nil)) < S & width(projection) >
W`), emitting one check per distinct spacing value, anchored at the (width, run length)
corner where that value first becomes required — which the table's monotonicity makes
exact rather than merely conservative.

It is still wrong. Measured on a guarded 50 µm window: this deck's **`M1.S.2~` = 82**
against Calibre's **`M1.S.2` = 0 die-wide** on the same stream. The likely cause is that
the width condition is evaluated on the merged layer, so a polygon that is wide
*somewhere* reads as wide where it faces its neighbour, while TSMC measures the width
local to that edge pair. **Unresolved.** The check earned its keep — it is what surfaced
the M4 spacing family — but the number it prints is not a violation count.

---

## What it does not check

The GDS is not a complete chip — [docs/tapeout/12-calibre-drc.md](../../docs/tapeout/12-calibre-drc.md)
sets that out and every word of it applies here. On top of that, this deck is a subset
of the foundry deck by construction:

| Not checked | Why |
|---|---|
| Front-end (OD/PO/CO/NW/implant, latch-up, ESD, antenna) | not in the tech LEF, and the stream has almost no device geometry anyway |
| **Density** (`M*.DN.*`) | in the LEF, but meaningless before fill — and there is no fill in this flow |
| Seal ring, `CSR.*` | not in the stream at all |
| Slotting / `MAXWIDTH` (`M*.W.3`) | needs the slot rules, which are deck-only |
| `MINIMUMCUT` (`VIA*.R.4…6`) | needs cut-count-versus-wire-width logic not modelled here |
| Cut spacing variants (`ADJACENTCUTS`, `PARALLELOVERLAP`) | only the plain `SPACING` is taken |
| Connectivity, shorts, opens, LVS | needs a netlist; KLayout can do it, this deck does not |

**A clean KLayout run does not mean a clean Calibre run.** It means the back-end
geometry is consistent with the tech file. That is a real and useful statement — it is
most of what P&R can get wrong on its own — and it is a much smaller statement than
signoff.

### The AP datatype warning — checked, benign

The Calibre summary carries a line that looks alarming:

```
Layer 74 contains unmapped objects and is the source layer of LAYER MAP == 74 DATATYPE == 10.
```

Innovus streams `AP` to **74/0** (`…gdsout_6X1Z1U.24a.map`), while the TSMC deck has both
`LAYER APi 74` and `LAYER MAP 74 DATATYPE 10`. The obvious reading — that AP geometry is
invisible to signoff — is **wrong**, and it was checked rather than assumed:

- `74/10` is **absent** from the stream; all 12 AP shapes are at `74/0`, in
  `nanosoc_eth_chiplet_pads`, `PAD70NU`, `PAD70GU` and two via cells.
- Calibre's own geometry warnings name `layer APi … in cell PAD70NU` — so the bare
  `LAYER APi 74` statement picks up `74/0`.
- `AP.*` checks return results: `AP.R.1 = 1`, `AP.W.2.WB = 2`.

So the warning is the datatype-10 MAP statement finding nothing to map, and it is
harmless here. Recorded because the general mechanism is real — **a datatype mismatch
between the GdsOutMap and a rule deck silently checks nothing** — and because this deck
reads its layer numbers from the same map file, which is what makes the two tools
comparable in the first place.

---

## Runtime and memory — windows, not whole dies

Measured on `srv03335` (16 cores), against the 298 MB stream:

| Scope | Threads | Wall clock | Peak RSS |
|---|---|---|---|
| 150 µm window, `ONLY=M4,VIA3` | 8 | **14 s** | small |
| 50 µm window, all layers | 4 | **58 s** | small |
| whole die, all layers | 8 | **hours** — see below | **> 7 GB** |

**Work windows, not whole dies.** The full-die run is a server job: it was still going
past 50 minutes at over 7 GB resident. A laptop can do it in principle and should not
try. Two ways to stay in the seconds-to-a-minute range, and they compose:

```sh
make drc CLIP=650,300,700,350          # one window
make drc ONLY=M4,VIA3                  # one metal and the via under it
```

`ONLY=` also lets you cover the whole die in several short runs instead of one long
one — the deck has 156 checks across 10 metals and 9 cut layers, and most triage only
ever cares about two of them.

Hierarchical (`deep`) mode is on by default. `make drc-flat` turns it off; flat is the
reference behaviour, so **if deep and flat disagree, distrust the deep result**. On a
clipped window the two are the same speed — a clipped window has little repetition left
to exploit — so this is a full-die knob.

Clip at the deck (`CLIP=…`), not afterwards. Intersecting each layer with a box after
loading still makes deep mode walk the whole hierarchy first: **minutes for a 150 µm
window, against 14 s** with `source.inplace_clip`.

### Clip artefacts, and the guard

A clip **cuts wires**. A cut wire has a raw end: it is narrow, it is small in area, and
a via under a metal that used to continue past the window now has no enclosure. All
artefacts of the window, none of them defects. The deck therefore drops markers inside a
2 µm frame at the clip boundary (`-rd guardwidth=`, `0` to disable).

It is not a small correction. Same 50 µm window, same layers, same 4 threads, 58 s
either way — guard off (a standalone clipped GDS) against guard on (`CLIP=` on the full
stream):

| check | no guard | guard | artefacts |
|---|---:|---:|---:|
| `M1.A.1` | 79 | 0 | 79 |
| `M2.A.1` | 35 | 0 | 35 |
| `M1.W.1` | 31 | 0 | 31 |
| `VIA2.R.2:M2` | 27 | 0 | 27 |
| `VIA1.R.2:M1` / `:M2` | 26 / 26 | 0 / 0 | 52 |
| `M2.W.1` | 22 | 0 | 22 |
| `M3.W.1`, `M3.A.1`, `M4.W.1`, `M4.A.1`, `VIA3.R.2:M4` | 26 | 0 | 26 |
| **total, all checks** | **1039** | **465** | **574 (55 %)** |

**Every single width, area and via-enclosure marker in that window was the cut edge.**
Without the guard the report is more artefact than signal.

The guard only applies when the **deck** does the clipping. `make clip` writes a
standalone window GDS for carrying to another machine; run the deck on that and it sees
a whole layout and guards nothing. Prefer `CLIP=` whenever you have the full stream.

---

## Files

| | |
|---|---|
| `scripts/gen_deck.py` | tech LEF + GdsOutMap → deck. Committed; holds no rule values. |
| `scripts/run_drc.sh` | the runner. No PDK, no licence. This is what goes on the laptop. |
| `scripts/compare_calibre.py` | KLayout counts next to a Calibre summary, by rule family |
| `scripts/clip_gds.rb` | cut a carryable window out of the 298 MB stream |
| `decks/` | generated deck — **gitignored, foundry-derived** |
| `work/<tag>/` | `.lyrdb` markers, `.counts` sidecar, log |

## Reading the results

`<tag>.lyrdb` is a marker database. Open it over the layout:

```sh
klayout <gds> -m work/<tag>/<tag>.lyrdb
```

which gives you the same click-a-violation-and-zoom-to-it loop as Calibre RVE, without
Calibre.

`<tag>.counts` is a two-column `rule<TAB>count` sidecar, which is what `make compare`
reads. Parsing counts back out of the XML would be silly.

`make compare` groups by **family** (`<layer>.<class>`), not by exact rule name. The two
tools decompose the same constraint differently — TSMC's `M4.S.2.1` against this deck's
`M4.S.2`/`M4.S.3` — so equal totals per family is the strongest claim the naming can
support. Equal counts are not the goal and should not be expected. What matters is that
nothing KLayout finds is invisible to Calibre without an explanation.

## What is still unproven

Honesty section, in the spirit of `docs/tapeout/`.

- **No full-die KLayout run has completed.** Everything measured above is windows. The
  one full-die attempt was still running past 50 minutes at 7.3 GB. Until one finishes,
  `make compare` has only been exercised on scoped runs, and the die-wide correlation
  between the two tools is **unknown**.
- **Two check families over-report and are unresolved**, both marked `~`:
  `<L>.S.2~…` (width-dependent spacing — 82 against Calibre's 0 die-wide, see above) and
  `<L>.S.EOL~` (end-of-line — `WITHIN`/`PARALLELEDGE` not modelled, factor unmeasured).
  Everything not marked `~` agreed with Calibre on the one window checked, but agreeing
  at zero is weak evidence.
- **No check has been confirmed against a known-real violation.** The exact checks read
  zero where Calibre reads zero. None of them has yet caught something Calibre also
  caught, which is the test that would actually prove them.
- **`deep` versus `flat` has not been diffed.** On a clipped window they take the same
  time, so there was no reason to; on the full die neither has finished. A surprising
  deep result deserves a `make drc-flat` before you act on it.
- **Nothing here has run on an actual laptop.** It has run headless on the lab server
  with no PDK and no licence in the environment, which is the same code path — but the
  memory figures are the ones to watch on a 16 GB machine, and they are the reason the
  advice is "windows, not whole dies".
