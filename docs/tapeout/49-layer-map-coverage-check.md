# 49 — Closing the layer-map blind spot: `check-layer-map-coverage`

**Status:** built 2026-08-18, PROMOTED to a blocking gate 2026-08-18 (promotion-order row
#2, `docs/tapeout/53-gate-promotion-plan.md` §1). `make layer-map-check` is wired ahead of
`make drc` in `ASIC/genus-innovus/Makefile`, and **`LAYER_MAP_STRICT` now defaults to `1`**
— an allow-list (`ASIC/genus-innovus/scripts/layer_map_allowlist.txt`, §"The allow-list"
below) closes the `$(GDSMAP)`-only false-positive gap this doc originally used to justify
defaulting to advisory-only. Clean (zero UNEXPLAINED findings) on the IMEC-matched
reference stream under both real foundry archives, and on both current chiplet builds
under `$(GDSMAP)` + the allow-list alone (no foundry report needed for a clean default
run). See §"Strict-mode validation and decision" for the full evidence.

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
3. **zero or more allow-lists**, via `--allow-list FILE` — same 4-column shape, but never
   counted as coverage (see §"The allow-list" below).

and reports findings in three disjoint buckets:

* **UNMAPPED, POPULATED, UNEXPLAINED** — a `(layer, datatype)` the stream carries real
  shapes on that *no* supplied `--map`/`--imec-report` names **and** no `--allow-list`
  entry accounts for. This is the actual risk, and the only bucket that fails the check.
* **UNMAPPED, POPULATED, EXPECTED** — same as above, except a supplied `--allow-list`
  entry names it as a known, already-sourced gap (typically a front-end/vendor-drawn
  layer `$(GDSMAP)` was never meant to declare). Printed for visibility, never fails.
* **MAPPED, EMPTY** — a `(layer, datatype)` a map declares that this particular stream
  happens not to populate. Informational only: most of these are ordinary (a seal-ring
  or dummy-fill layer this run's stream never touches).

```
check-layer-map-coverage <file.gds> --map FILE [--map FILE ...] \
                          [--imec-report FILE ...] [--allow-list FILE ...] \
                          [--min-count N] [--json OUT]
```

Exit 0 = no UNMAPPED, POPULATED, UNEXPLAINED finding (an EXPECTED/allow-listed finding
never sets this). Exit 1 = at least one UNEXPLAINED finding. Exit 2 = usage/input error
(no map given, a file unreadable, the census itself failed).

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

Three knobs:

* `LAYER_MAP_EXTRA=<file> [<file> ...]` — extra map(s)/report(s) to union in. The recipe
  auto-detects an IMEC report (`grep`s for `LayerMapCadence`) vs a plain map file, so one
  variable covers both `--map` and `--imec-report`.
* `LAYER_MAP_ALLOWLIST=<file> [<file> ...]` (default
  `ASIC/genus-innovus/scripts/layer_map_allowlist.txt`) — allow-list file(s), passed as
  `--allow-list`. Never counted as coverage; only reclassifies an already-unmapped,
  already-populated pair from UNEXPLAINED to EXPECTED. Set to empty
  (`LAYER_MAP_ALLOWLIST=`) to see the old, undifferentiated finding with no allow-list
  applied — useful for confirming what the allow-list is actually doing (see
  §"Strict-mode validation and decision").
* `LAYER_MAP_STRICT=0|1` (**default `1`** as of this promotion) — `1` fails `make drc` on
  any UNMAPPED, POPULATED, **UNEXPLAINED** finding (an EXPECTED/allow-listed finding never
  triggers this); `0` prints the finding and does not fail the build.

**`ASIC/asic-toolkit/mk/checks.mk`** — a standalone `make layer-map-check` for any
toolkit-driven consumer, `LAYER_MAP_FILE` / `LAYER_MAP_EXTRA` again naming the source(s).
With neither set it prints `SKIP` and exits 0 rather than claiming a check that never had
an input — the toolkit is tech-agnostic, so it ships no default map of its own.

### Why `$(GDSMAP)` alone is not a complete map — and how the allow-list closes that

`$(GDSMAP)` — this project's own derived stream-out map, regenerated fresh from the PDK
by `make gdsmap` on every run — only declares the layers **Innovus itself constructs**:
routing metal, vias, AP, pin-name text, the die outline. A full chiplet stream also
carries **pre-drawn** geometry merged in from vendor library GDS (standard cells, macros,
bond pads) on front-end mask layers — `NW`, `OD`, `PO`, `PP`, `NP`, `CO` — plus dummy-fill,
LOGO and SRAM-marker layers, and `$(GDSMAP)` was never meant to name any of those;
Innovus does not draw them, it only passes them through.

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
as a full-chip coverage verdict, with no way to tell "known gap" from "nobody has looked
at this", would report 24 "findings" on **every good build, every time** — which is
exactly the "gate that cannot discriminate" failure mode [doc 35](35-drc-layer-map-blindness.md)
and the PO.R.8 episode (doc 39) both already document for this project. That is the
problem `LAYER_MAP_STRICT` defaulting to `0` used to work around.

#### The allow-list

`ASIC/genus-innovus/scripts/layer_map_allowlist.txt` names exactly the `(layer,
datatype)` pairs above — by real name, sourced from the real foundry `LayerMapCadence`
table (`ASIC/imec_results/Archive_.../design/reports/Final_Report_*.rpt`, identical in
both the 17Aug26 and 18Aug26 archives) — as EXPECTED to be unmapped when only `$(GDSMAP)`
is supplied. It is a plain 4-column `name category stream# dataType` table, the same
shape `--map` reads, but consumed differently by `check-layer-map-coverage`: an
allow-list row is **never** counted as coverage (it does not add to "mapped"), it only
reclassifies an already-unmapped, already-populated pair from UNEXPLAINED to EXPECTED —
see §"FORMATS" in the script's own header for the exact mechanism.

Every row is sourced from an **observed population**, not the Makefile's prose list of
categories — the file's own header documents the exact commands and the two real runs
(both current chiplet builds, and the IMEC-matched reference GDS against this project's
own current derived map) that produced each of the 27 rows. One category the Makefile
comment used to name — **seal ring (`162/0`, `SEALRING/drawing`)** — is deliberately
**not** in the allow-list: neither current build nor the reference GDS has ever been
observed to populate it (both IMEC archives show it `MAPPED, EMPTY`). Adding a row for a
layer nobody has measured populated would be exactly the "a zero that measured nothing"
mistake this project has been burned by before; if a future full-merge stream does
populate `162/0`, the check will correctly report it UNEXPLAINED until someone measures
it and adds a properly-sourced row.

`LAYER_MAP_ALLOWLIST` in the Makefile passes this file as `--allow-list` by default, so
`make layer-map-check`/`make drc` gets a discriminating check even with no
`LAYER_MAP_EXTRA` supplied — see §"Strict-mode validation and decision" for the full
proof this is safe to gate on.

---

## Validation

### 1. The IMEC-matched reference GDS — both real foundry archives agree

`ASIC/genus-innovus/runs/20260811T103338Z_fill-verify/prev_outputs/nanosoc_eth_chiplet_pads_logo_full_L300.gds`
is byte-identical (md5 `7f6214965501c911bd65069378ae911d`) to the file IMEC's CheckAll+
run graded. We now have **two** real foundry drops to check it against:

* **Archive 1** — `Archive_..._merged_dummyWithSealRing_17Aug26_15u14` (pad-only merge).
  `LayerMapCadence` parses to **81 rows**.
* **Archive 2** — `Archive_..._dummy_merged_dummyWithSealRing_18Aug26_19u28` (full
  standard-cell + pad merge — more real geometry was present when IMEC built this one).
  `LayerMapCadence` parses to **95 rows** (14 more than archive 1: `NT_N`, `OD_25`
  drawing/ovrdrv, `RPO`, `PSUB2`, `RPDMY`, `RH`, `SDI`, `text`/drawing, `M5`/`M6`/`M7`
  pin, `M1`/boundary, `ESDIMP`).

Running the tool with **just archive 1's** report as the map:

```
81 mapped (layer,datatype) row(s) from 1 source(s)
51 pair(s) both mapped and carrying shapes - covered
UNMAPPED, POPULATED, UNEXPLAINED: none.
```

Running it with **just archive 2's** report:

```
95 mapped (layer,datatype) row(s) from 1 source(s)
51 pair(s) both mapped and carrying shapes - covered
UNMAPPED, POPULATED, UNEXPLAINED: none.
```

**The two archives agree completely on this file.** Both report the identical
`51 covered`, zero unmapped, zero populated-elsewhere-only-in-one. Archive 2's 14 extra
rows are all layers this particular reference stream does not populate (they land in
`MAPPED, EMPTY` on archive 2's run and are simply absent from archive 1's, since archive
1 never declared them at all) — its fuller standard-cell+pad merge does **not** reveal
any layer usage archive 1's report failed to validate; it only adds declarations for
layers this file happens not to use. On the one file this project can cross-check
byte-for-byte against a real foundry read, both drops give the same clean verdict.

The real foundry table, on the exact file IMEC checked, accounts for every populated
layer in the stream — front-end and back-end alike — with no help needed from this
project's own derived map. Adding `$(GDSMAP)` on top changes nothing about that verdict.

Running it with **only** `$(GDSMAP)` (no foundry table) reproduces the same 24–27-line
front-end/library "finding" described above — consistent with the caveat, not a
contradiction of it. Adding `--allow-list ASIC/genus-innovus/scripts/layer_map_allowlist.txt`
on top of `$(GDSMAP)`-only turns that same run into **zero UNEXPLAINED, 27 EXPECTED**
(the 24 rows this build's own outputs populate, plus `150/9`, `150/10` and `158/0`/LOGO,
which only this LOGO+dummy-merged reference stream populates) — and the cross-check is
exact: `$(GDSMAP)`'s 24 native rows + the allow-list's 27 rows = the same **51** pairs
both real IMEC archives independently cover. The allow-list is not a guess at what the
foundry table would say; on the one file checkable both ways, it names precisely the
foundry table's complement.

### 2. The current builds — `$(GDSMAP)` + allow-list alone, no foundry report needed

Both `nanosoc_eth_chiplet_pads.gds` builds present on this host —
`ASIC/eth-chiplet/build/full-20260814/outputs/` and `ASIC/eth-chiplet/build/fp1505/outputs/`
— were censused (≈51 s each, no licence, no geometry built — the GDSII record stream is
read directly). Two diffs were run for each:

**With the real IMEC report unioned in** (as before, `build/<tag>/work/tech/gdsout.stream.map`
+ archive 1's report):

```
full-20260814: 140 mapped rows, 49 covered, UNMAPPED POPULATED UNEXPLAINED: none
fp1505:        133 mapped rows, 49 covered, UNMAPPED POPULATED UNEXPLAINED: none
```

**With `$(GDSMAP)` (each build's own derived map) + the allow-list ALONE — no foundry
report** — the mode `LAYER_MAP_STRICT=1` now gates on by default:

```
full-20260814: 52 mapped rows, 27 allow-listed, 25 covered, UNEXPLAINED: none
fp1505:        52 mapped rows, 27 allow-listed, 25 covered, UNEXPLAINED: none
```

Both builds produced the **identical 24-row unmapped/populated set** (same layers, same
shape counts, byte for byte) before the allow-list was applied, and both go to zero
UNEXPLAINED findings after it — every one of the 24 rows the allow-list needed for a real
build was already in it, sourced from these same two runs. The full, end-to-end wired
`make -C ASIC/genus-innovus layer-map-check` target (not just the standalone script) was
run against both builds' real GDS and confirmed `RC=0` for both — see
§"Strict-mode validation and decision".

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

## Strict-mode validation and decision

`docs/tapeout/53-gate-promotion-plan.md` §1 sets the bar for promoting this check from
`report` to a real gate: `LAYER_MAP_EXTRA` (or, as landed, a sourced allow-list) fed a
real foundry layer table across ≥1 full-merge build, an explicit allow-list for the
vendor-drawn layers, and a `check:` predicate that distinguishes "unmapped, expected
(vendor-drawn)" from "unmapped, populated, unexplained" — never a bare unmapped count.

**Evidence gathered 2026-08-18:**

1. `check-layer-map-coverage` now emits three disjoint buckets (UNEXPLAINED / EXPECTED /
   MAPPED-EMPTY) instead of one, and only UNEXPLAINED sets exit 1 — see §"The tool" above.
2. `ASIC/genus-innovus/scripts/layer_map_allowlist.txt` names all 27 (layer, datatype)
   pairs ever observed populated-and-unmapped across every real run performed for this
   promotion (both current chiplet builds, and the IMEC-matched reference GDS against
   this project's own current derived map) — every row traceable to a real command and a
   real foundry name, none guessed. Seal ring (`162/0`) is deliberately excluded: never
   observed populated, so not allow-listed (see §"The allow-list").
3. Both real foundry archives (17Aug26 pad-only merge, 18Aug26 full standard-cell+pad
   merge) agree completely on the IMEC-matched reference GDS: zero unmapped either way,
   archive 2's fuller merge adds no new populated-layer coverage archive 1 lacked (§1
   above).
4. Both current builds (`fp1505`, `full-20260814`) report **zero UNEXPLAINED** findings
   under `$(GDSMAP)` + the allow-list alone — no foundry report needed for a clean
   default `make drc` run — confirmed both via the standalone script and via the real,
   fully wired `make -C ASIC/genus-innovus layer-map-check` target (§2 above).
5. **The mechanism was proven to actually discriminate**, not just always pass: removing
   any one row from the allow-list (tested with the two `CO` rows, `30/0`/`30/11`) and
   re-running against a real build turns that layer straight back into an UNEXPLAINED
   finding and the check's exit code back to 1 — and, run through the real Makefile
   target with `LAYER_MAP_ALLOWLIST=` (empty), `make layer-map-check` genuinely FAILS
   under `LAYER_MAP_STRICT=1`, exactly as it should on a source that no longer explains
   what it is looking at. A gate that can only ever pass is not a gate; this one can both
   pass on real good input and fail on a deliberately degraded one.
6. Cross-check: on the reference GDS, `$(GDSMAP)`'s 24 natively-covered rows + the
   allow-list's 27 rows = 51 — exactly the count both real IMEC archives independently
   report as fully covered. The allow-list was not tuned to make a finding disappear; it
   names precisely the complement a real foundry table also names, on the one file this
   project can check both ways.

**Decision: `LAYER_MAP_STRICT` is flipped from `0` to `1`** in
`ASIC/genus-innovus/Makefile` (comment there cites this section). The promotion criteria
in doc 53 §1 are met: a real foundry table was cross-checked across two independent
archives with no disagreement, an allow-list exists for every observed vendor-drawn gap
with each entry sourced from a real measurement (never a guess), the check's own output
now discriminates EXPECTED from UNEXPLAINED rather than reporting a bare count, and the
mechanism was shown capable of genuinely failing, not merely capable of passing. What
strict mode does **not** yet cover: a layer this project has genuinely never populated in
any run to date (seal ring is the known example) would, correctly, still fail as
UNEXPLAINED the first time it appears — that is the gate working as designed, not a gap
in this validation.

---

## Related

* [35 — DRC layer-map blindness](35-drc-layer-map-blindness.md) — the standing property
  this closes, and the LEFOBS incident in the opposite direction
* [39 — `PO.R.8` resolved](39-po-r8-resolved.md) — another instance of a black-boxing
  artefact that a naive gate would have reported as a defect
* [53 — Gate-hardening plan](53-gate-promotion-plan.md) — promotion-order row #2, the
  promotion criteria this doc's strict-mode decision satisfies
* [12 — Calibre DRC](12-calibre-drc.md) — the project deck header, and why a spliced
  deck is the only form that can set the real die box
* `ASIC/asic-toolkit/scripts/asic-flow-gds-layer-census` — the census this tool consumes
* `ASIC/genus-innovus/scripts/gdsmap_derive.py` — derives `$(GDSMAP)`, and documents why
  its own row set stops at what Innovus constructs
* `ASIC/genus-innovus/scripts/layer_map_allowlist.txt` — the allow-list itself, with the
  exact commands and runs behind every row's empirical basis
