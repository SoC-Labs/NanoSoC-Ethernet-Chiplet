# Calibre DRC for `nanosoc_eth_chiplet_pads`

Full write-up: [`docs/tapeout/12-calibre-drc.md`](../../../../docs/tapeout/12-calibre-drc.md)

```sh
make drc                              # from ASIC/genus-innovus/ — the normal way
make drc GDS=some/other.gds           # check a different stream
make drc-census                       # count and gate what that run produced
```

**Run it through `make`.** The scripts here no longer carry a copy of the
design's identity — the top cell, die box and foundry deck come from the one
manifest, [`../../drc_project.mk`](../../drc_project.mk), and the Makefile
passes them in. `run_drc.sh` invoked bare will tell you which variable is
missing rather than quietly checking the wrong thing. To drive it without
`make`, export them yourself:

```sh
BLOCK=nanosoc_eth_chiplet_pads \
DIE_XLB=0.0 DIE_YLB=0.0 DIE_XRT=1600.0 DIE_YRT=2000.0 \
FOUNDRY_DECK=$TSMC_65_HOME/CMOS/util/MAIN_DRC_TopMu/$FOUNDRY_DECK_NAME \
    ./scripts/calibre/run_drc.sh some/other.gds
```

Headless. No `$DISPLAY`, no GUI packages, no runset.

## Files

| File | Purpose |
|---|---|
| `tsmc65_minisic_header.svrf.in` | **template** for the project-owned switch/environment block. `@@TOPCELL@@` and `@@XLB@@`/`@@YLB@@`/`@@XRT@@`/`@@YRT@@` are substituted at splice time — SVRF cannot expand a variable inside a cell name, so it cannot be deferred to Calibre |
| `make_project_deck.sh` | substitutes the template, splices the foundry rule bodies below their own `/* SWITCH DEFINITION END */`, md5-checks the spliced body against the read-only foundry deck, and refuses to emit a deck with any placeholder left unfilled |
| `nanosoc_eth_chiplet_pads.drc.rules` | the OLD project-owned SVRF wrapper: supplies layout, top cell and output paths, then `INCLUDE`s the TSMC deck. No longer the default — kept for `DRC_DECK=…` A/B runs against foundry switch defaults |
| `run_drc.sh` | preflight + headless `calibre -drc -hier` driver; asserts the deck's `LAYOUT PRIMARY` equals `$BLOCK`, and summarises violations at the end |

## Environment

| Variable | Default |
|---|---|
| `BLOCK` | **required** — from `drc_project.mk`. Asserted against the deck's `LAYOUT PRIMARY` |
| `DIE_XLB` `DIE_YLB` `DIE_XRT` `DIE_YRT` | **required** by `make_project_deck.sh` — from `drc_project.mk`, which reads them out of `scripts/floorplan.tcl` |
| `FOUNDRY_DECK` | **required** by `make_project_deck.sh` — from `drc_project.mk` |
| `DRC_GDS` | `../outputs/$BLOCK.gds` |
| `DRC_RUNDIR` | `../work/drc_run` |
| `DRC_CPUS` | `8` |
| `DRC_NOWAIT` | unset — queue for a licence. Set `1` to fail fast. |

## Two things not to break

**1. `DRC ICSTATION YES` must stay, and must stay in the wrapper.** The TSMC deck sets
`LAYOUT PATH` / `LAYOUT PRIMARY` / `DRC RESULTS DATABASE` / `DRC SUMMARY REPORT` itself,
using placeholder strings (`"GDSFILENAME"`, `"TOPCELLNAME"`). Without `DRC ICSTATION YES`
those duplicates are a hard error:

```
ERROR: Error SPC1 on line N of <deck> - superfluous specification statement: layout primary.
```

With it, duplicates are tolerated and the top-level file wins. That is the entire trick.

**2. The foundry deck is read-only.** `/tsmc65pdk` is shared lab collateral. This flow
`INCLUDE`s it and never copies or edits it. If you ever need different `#DEFINE` switches
(density, seal ring, DFM), that requires a project-owned copy and an explicit decision —
do not edit upstream.

## Gotchas

- The TSMC deck writes ~170 `*.density` / `*.rep` files into the **current directory**.
  `run_drc.sh` `cd`s into `DRC_RUNDIR` first; do not run the deck from the design root.
- The top cell is hard-coded in the deck. SVRF expands environment variables in file
  paths but **not** in cell names, so `LAYOUT PRIMARY "$VAR"` silently does not work.
- `calibre` exiting `0` means the run finished, not that the design is clean. Read the
  summary.
