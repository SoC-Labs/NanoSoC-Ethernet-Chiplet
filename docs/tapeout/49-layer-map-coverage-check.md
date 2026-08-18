# 49 — Closing the layer-map blind spot: `check-layer-map-coverage`

**Status:** built and validated 2026-08-18. `make layer-map-check` is wired ahead of
`make drc` in `ASIC/genus-innovus/Makefile`, advisory by default (see `LAYER_MAP_STRICT`
below). Clean on the IMEC-matched reference stream and on both current chiplet builds.

---

## The blind spot this closes

[Doc 35](35-drc-layer-map-blindness.md) measured a standing property of every DRC number
this project has ever quoted: Calibre can only report on a `(layer, datatype)` pair the
rule deck's own layer map assigns a name to. A shape sitting on a number the deck never
mapped is invisible to it — not clean, **unmeasured** — and the census this repo already
had (`asic-flow-gds-layer-census`, counts shapes per layer/datatype) never got diffed
against any declared map to catch that. Doc 35 again:

> Nothing in this repo checks that agreement. `scripts/ci/drc_census.py` counts results
> and attributes them by owning cell; it cannot count what was never mapped. A real
> object on an unmapped number would produce the same clean census as this annotation
> does.

Two real incidents are the same bug pointed in opposite directions:

| | LEFOBS (2026-08-10) | doc 35's `108/0` (2026-08-17) |
|---|---|---|
| what happened | a non-manufacturing layer got mapped **onto** real metal | a real layer sat on a number the deck maps **no rule to** |
| symptom | 1,549 phantom antenna violations | a correct-looking silent zero |
| direction | falsely **full** | falsely **empty** |

Both come from the GdsOutMap and the deck's layer table disagreeing about what is
manufacturable, with nothing checking that they agree. This page is that check.

---

## What a "layer map" actually is, for anyone new to this

A GDSII file does not store layer *names*. Every shape carries two small integers, a
**stream number** and a **datatype**, e.g. `39/60`. Whether that pair means "ninth-level
drawn metal" or "seal ring" or nothing at all is not in the GDS — it is a separate lookup
table, agreed between whoever wrote the GDS and whoever reads it back:

* Innovus's `write_stream -map_file` uses one such table (a **GdsOutMap**) to decide
  which stream number to draw *its own* routing, vias and pin labels on.
* A Calibre DRC/LVS/ERC deck uses a — usually much larger — table of its own to decide
  which stream number means which mask layer, so it knows which rules apply to which
  shapes.

These are two **independently-maintained** tables that happen to need to agree. Nobody
enforces that they do. If a shape lands on a number the DRC deck's table has no entry
for, the deck cannot see it: not "sees it and finds it clean" — genuinely blind to it,
the same as if the shape did not exist. **A real defect sitting entirely on an unmapped
layer would produce a clean Calibre run and nobody would know**, because a clean run and
an unmeasured one produce byte-identical output.

---

## The tool

`ASIC/asic-toolkit/scripts/check-layer-map-coverage` (Python 3, no dependencies, same
scripting convention as its sibling `asic-flow-gds-layer-census`). It takes:

1. **a census** — it runs `asic-flow-gds-layer-census` itself and reads its `--json`
   output. GDSII parsing is not repeated here; that script's header documents a real
   parsing trap (an SREF/AREF record inheriting the previous element's layer and being
   mistallied) and the fix belongs in one place.
2. **one or more maps**, via `--map FILE` (a GdsOutMap-shaped file: whitespace-separated
   `techLayer techPurpose stream# dataType`) and/or `--imec-report FILE` (a foundry
   `Final_Report_*.rpt`; the tool locates the `LayerMapCadence` table inside it and reads
   just that section).

and reports two disjoint findings:

* **UNMAPPED, POPULATED** — a `(layer, datatype)` the stream carries real shapes on that
  *no* supplied map names. This is the actual risk and is what fails the check.
* **MAPPED, EMPTY** — a `(layer, datatype)` a map declares that this particular stream
  happens not to populate. Informational only: most of these are ordinary (a seal-ring
  or dummy-fill layer this run's stream never touches).

```
check-layer-map-coverage <file.gds> --map FILE [--map FILE ...] \
                          [--imec-report FILE ...] [--min-count N] [--json OUT]
```

Exit 0 = no unmapped, populated finding. Exit 1 = at least one. Exit 2 = usage/input
error (no map given, a file unreadable, the census itself failed).

### Why there is no committed reference layer-number table

A `(layer, datatype)` ↔ mask-name table is foundry collateral — the exact class of fact
`ASIC/genus-innovus/scripts/gdsmap_derive.py` already declines to reproduce ("Real
layer/datatype pairs are not reproduced here — TSMC licence forbids it"), that the
`restream-census` Makefile target declines to reproduce ("the number/datatype table is
TSMC's, it is not reproduced in this repository"), and that
`ASIC/asic-toolkit/test/stage/project/tech/faketech/pdk/faketech.map` goes as far as
inventing numbers above 100 for rather than use real ones, because "this file is
committed to a public repository". This tool follows the same rule: it reads a map from
wherever you point it and writes none of those numbers into a new committed file.
`--imec-report` exists precisely so a fresh foundry drop becomes a coverage check with
no manual transcription step — and no second, hand-typed copy of the table that can
silently drift from the report it was copied out of.

---

## Wiring

**`ASIC/genus-innovus/Makefile`** — the flow that has actually produced every GDS this
project has shipped. `make drc` now depends on `make layer-map-check`, so the finding is
on screen before Calibre starts, not discovered afterwards while reading a summary that
cannot tell you what it never had a rule for:

```
make -C ASIC/genus-innovus drc
#  -> layer-map-check runs first (regenerates $(GDSMAP) via 'make gdsmap', diffs it
#     against the current $(GDS)), prints its finding, THEN run_drc.sh launches Calibre
```

Two knobs:

* `LAYER_MAP_EXTRA=<file> [<file> ...]` — extra map(s)/report(s) to union in. The recipe
  auto-detects an IMEC report (`grep`s for `LayerMapCadence`) vs a plain map file, so one
  variable covers both `--map` and `--imec-report`.
* `LAYER_MAP_STRICT=0|1` (default `0`) — `0` prints the finding and does not fail the
  build; `1` fails `make drc` on any UNMAPPED, POPULATED finding.

**`ASIC/asic-toolkit/mk/checks.mk`** — a standalone `make layer-map-check` for any
toolkit-driven consumer, `LAYER_MAP_FILE` / `LAYER_MAP_EXTRA` again naming the source(s).
With neither set it prints `SKIP` and exits 0 rather than claiming a check that never had
an input — the toolkit is tech-agnostic, so it ships no default map of its own.

### The default (`$(GDSMAP)`-only) mode is real, but it is not a complete check — read this before trusting a bare pass

`$(GDSMAP)` — this project's own derived stream-out map, regenerated fresh from the PDK
by `make gdsmap` on every run — only declares the layers **Innovus itself constructs**:
routing metal, vias, AP, pin-name text, the die outline. A full chiplet stream also
carries **pre-drawn** geometry merged in from vendor library GDS (standard cells, macros,
bond pads) on front-end mask layers — `NW`, `OD`, `PO`, `PP`, `NP`, `CO` — plus dummy-fill,
seal-ring, LOGO and SRAM-marker layers, and `$(GDSMAP)` was never meant to name any of
those; Innovus does not draw them, it only passes them through.

Measured directly, running the tool with **only** `$(GDSMAP)` against the current
`full-20260814` build:

```
24 unmapped, populated layer(s), including:
    30/0   geometry=92,375   (CO — contact-cut, front-end, real geometry)
    17/0   geometry=12,648   text=206   (PO)
     6/0   geometry=9,900    text=209   (OD)
   149/0                     text=20,390 (PO pin-name labels)
```

None of that is a defect. It is `$(GDSMAP)`'s own declared scope working exactly as
built — those layers are foundry library content this map was never asked to name, and
Calibre's real signoff deck (spliced from the read-only foundry deck, not from
`$(GDSMAP)`) has its own complete declarations for them. Treating a `$(GDSMAP)`-only run
as a full-chip coverage verdict would report 24 "findings" on **every good build,
every time** — which is exactly the "gate that cannot discriminate" failure mode
[doc 35](35-drc-layer-map-blindness.md) and the PO.R.8 episode (doc 39) both already
document for this project. That is why `LAYER_MAP_STRICT` defaults to `0`: it is
deliberately advisory until it is given a source complete enough to gate on.

Supply `LAYER_MAP_EXTRA` with a foundry/IMEC report for the layers `$(GDSMAP)` cannot
speak to — see the validation below for what that looks like on a real file.

---

## Validation

### 1. The IMEC-matched reference GDS

`ASIC/genus-innovus/runs/20260811T103338Z_fill-verify/prev_outputs/nanosoc_eth_chiplet_pads_logo_full_L300.gds`
is byte-identical (md5 `7f6214965501c911bd65069378ae911d`) to the file IMEC's CheckAll+
run graded in
`ASIC/imec_results/.../design/reports/Final_Report_..._17Aug26_15u14.rpt`, whose
`LayerMapCadence` section (lines 91–208) is a real foundry-derived
techLayer/techPurpose/stream#/dataType table — 81 rows once parsed.

Running the tool with **just that report** as the map:

```
81 mapped (layer,datatype) row(s) from 1 source(s)
51 pair(s) both mapped and carrying shapes - covered
UNMAPPED, POPULATED: none.
```

**Zero unmapped, populated layers.** The real foundry table, on the exact file IMEC
checked, accounts for every populated layer in the stream — front-end and back-end
alike — with no help needed from this project's own derived map. This is the honest
validation result: nothing was manufactured to make a finding here, and the tool says so
plainly. Adding `$(GDSMAP)` on top changes nothing about that verdict (it only adds
entries that were already going to be `MAPPED, EMPTY` — the LEFOBS-scratch range and the
project's own pin-text convention, neither of which this reference stream happens to
populate).

Running it with **only** `$(GDSMAP)` (no foundry table) reproduces the same 24–27-line
front-end/library "finding" described above — consistent with the caveat, not a
contradiction of it.

### 2. The current builds

Both `nanosoc_eth_chiplet_pads.gds` builds present on this host —
`ASIC/eth-chiplet/build/full-20260814/outputs/` and `ASIC/eth-chiplet/build/fp1505/outputs/`
— were censused (≈51 s each, no licence, no geometry built — the GDSII record stream is
read directly) and diffed against their own run's derived map
(`build/<tag>/work/tech/gdsout.stream.map`) unioned with the same IMEC report:

```
full-20260814: 140 mapped rows, 49 covered, UNMAPPED POPULATED: none
fp1505:        133 mapped rows, 49 covered, UNMAPPED POPULATED: none
```

Both clean. Neither current build has introduced a layer the combined map/report
coverage cannot account for.

### What this does and does not prove

It proves the **stream's own layer usage** — every `(layer, datatype)` pair actually
drawn — is named by a real, independently-sourced table, on the one file this project can
cross-check against an authoritative foundry read of the same bytes, and on both current
builds. It does not re-run Calibre and does not replace `make drc-census` (doc
`scripts/ci/drc_census.py`, which judges what a completed Calibre run *found*). This
tool answers the prior question — could the deck used for that run even have *seen* what
was there — for a cost of about a minute and no licence, and it is meant to be read
**before** the Calibre run it precedes, not after.

---

## Related

* [35 — DRC layer-map blindness](35-drc-layer-map-blindness.md) — the standing property
  this closes, and the LEFOBS incident in the opposite direction
* [39 — `PO.R.8` resolved](39-po-r8-resolved.md) — another instance of a black-boxing
  artefact that a naive gate would have reported as a defect
* [12 — Calibre DRC](12-calibre-drc.md) — the project deck header, and why a spliced
  deck is the only form that can set the real die box
* `ASIC/asic-toolkit/scripts/asic-flow-gds-layer-census` — the census this tool consumes
* `ASIC/genus-innovus/scripts/gdsmap_derive.py` — derives `$(GDSMAP)`, and documents why
  its own row set stops at what Innovus constructs
