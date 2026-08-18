# 35 — The DRC gate can only see layers the deck maps a rule to

**Status:** measured 2026-08-17 on the shipping stream. Harmless as the stream stands.
Recorded because it is a *standing property* of every DRC number this project quotes,
not a defect in one run.

---

## The measurement

An independent geometric census — klayout, reading the GDS directly, deliberately not
asking Calibre — of the four 74 µm corner stress-relief keep-outs on
`ASIC/eth-chiplet/build/full-20260814/outputs/nanosoc_eth_chiplet_pads.gds`:

| | |
|---|---|
| layers with geometry inside the keep-outs | **exactly one: `108/0`** |
| area inside the four 74×74 squares | **21,904 µm² = 4 × 74², i.e. all four filled completely** |
| area inside the four chamfer triangles | **10,952 µm², precisely half** |

`108/0` is **`DIEAREA`** — line 23 of the derived gdsout map under
`ASIC/genus-innovus/work/tech/`. Confirmed by measurement rather than by reading the
map and stopping there: its merged area is **3,200,000.0 µm²** with bbox
**(0,0;1600,2000)** — the die box to the micron. It is the die-outline annotation, it
covers the corners by construction, and it is not drawn metal.

So `CSR.R.1 = 0` across all 197 rulechecks (see doc 28) **stands**: every metal, via, AP
and dummy layer is empty in the corners, established independently of the deck.

## The finding is not the layer

Calibre reported zero in the corners partly because **the deck maps no rule to layer
108**. A boundary or annotation layer sitting inside a reject-level keep-out is
*invisible* to the DRC gate.

This is the LEFOBS episode running in reverse:

| | LEFOBS (2026-08-10) | this |
|---|---|---|
| what happened | a NON-manufacturing object was mapped **onto** real metal layers | an object sits on a number the deck **ignores** |
| symptom | 1,549 phantom antenna violations, 773 pad blankets, 56 corner CSRs | silence |
| direction of error | falsely **full** | potentially falsely **empty** |

Both come from the same unchecked assumption: **that the GdsOutMap and the deck's layer
table agree about what is manufacturable.** Nothing in this repo checks that agreement.
`scripts/ci/drc_census.py` counts results and attributes them by owning cell; it cannot
count what was never mapped. A real object on an unmapped number would produce the same
clean census as this annotation does.

## What to tell the broker

Do **not** say "nothing is in the corners". A foundry layer dump will show `108/0`, and
being contradicted on our own submission is an expensive way to spend credibility.

> The corners are clean of manufacturing layers, and the stream carries a die-outline
> annotation there.

Include the **4 × 74² exactness** — filling each corner square completely, exactly half
in the triangle. That is the detail which makes it self-evidently an outline rather than
a leak, so the answer is already in the bundle when they ask.

## How to re-check after any map change

Two things, neither expensive:

1. **Census the stream's layers against the deck's mapped set.** Any layer carrying
   geometry that the deck maps no rule to is unmeasured — not clean. Built 2026-08-18:
   `make -C ASIC/genus-innovus layer-map-check` — see [doc 49](49-layer-map-coverage-check.md).
   It runs before `make drc` now, diffs `asic-flow-gds-layer-census`'s output against
   `$(GDSMAP)` (and, when given `LAYER_MAP_EXTRA`, a foundry/IMEC report too), and is
   what item 1 here used to mean before it existed.
2. **Re-run the corner census** if the map, the floorplan or the pad ring moves.

Method note, because the obvious approach does not finish: a
`RecursiveShapeIterator` per layer over this 313 MB / 400-plus-master hierarchy ran
**53 minutes without completing**. `Layout#clip` to the region of interest first, then
iterate the clipped cells, does the same job in **8 seconds** — it performs the spatial
restriction in C++ and hands back a small hierarchy. Flush your output, too: a batch
klayout script that buffers tells you nothing while it runs.

## Related

- doc 49 — Layer-map coverage check (the tool built to do exactly what "How to re-check
  after any map change" above describes, validated against a real IMEC foundry report)
- doc 28 — DRC status and attribution (the `CSR.R.1` = 0 result and its positive control)
- doc 12 — Calibre DRC (how the project deck header clears the two switches the wrapper
  cannot reach; without those, every boundary-derived check measures a synthetic outline)
