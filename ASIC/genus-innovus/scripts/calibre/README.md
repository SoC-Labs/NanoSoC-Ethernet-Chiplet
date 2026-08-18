# Calibre DRC / BND / ERC for `nanosoc_eth_chiplet_pads`

Full write-up: [`docs/tapeout/12-calibre-drc.md`](../../../../docs/tapeout/12-calibre-drc.md)
(core DRC), [`docs/tapeout/50-bnd-and-logo-checks.md`](../../../../docs/tapeout/50-bnd-and-logo-checks.md)
(BND and the LOGO keep-out rules — what they are, why they are separate decks
from core DRC, and the IMEC signoff comparison), and
[`docs/tapeout/51-erc-pg-labels.md`](../../../../docs/tapeout/51-erc-pg-labels.md)
(power/ground text-label ERC).

```sh
make drc                              # from ASIC/genus-innovus/ — the normal way
make drc GDS=some/other.gds           # check a different stream
make drc-census                       # count and gate what that run produced
make bnd                              # bond-pad / seal-ring BEOL — a SEPARATE deck
make erc                              # power/ground TEXT LABELS present?
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
| `nanosoc_eth_chiplet_pads.bnd.rules` | project-owned SVRF wrapper for the **BND** (wire-bond pad-ring) deck — a different foundry rule family from DRC, see the write-up. Sets `#DEFINE PITCH_70_STAGGER` (this design's PAD70GU/PAD70NU cells; see the file's own header for the evidence and the `PITCH_OPTION.ERROR.1` "fabricated clean" failure mode it fixed) |
| `run_bnd.sh` | same shape as `run_drc.sh`, for the BND deck. No `make_project_deck.sh` splice needed — the BND wrapper sets no foundry default this design must override, so a plain `INCLUDE` suffices |
| `run_erc.sh` | standalone Calibre ERC driver — does the GDS carry power/ground TEXT LABELS? Needs no post-P&R netlist or leaf-cell CDLs (drives Calibre with a throwaway empty source), and folds in a licence-free klayout structural cross-check because the two signals can disagree — see the script header and doc 51 |

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
| `BND_FOUNDRY_DECK` | **required** by `run_bnd.sh` — from `drc_project.mk` (`PDK_BND_DECK`, resolved by `pdk_paths.sh bnd-ruledeck`) |
| `BND_GDS` | `../outputs/$BLOCK.gds` |
| `BND_RUNDIR` | `../work/bnd_run` |
| `BND_CPUS` | `8` |
| `BND_NOWAIT` | unset — queue for a licence. Set `1` to fail fast. |
| `BND_DECK` | run this deck file instead of the project wrapper — switch A/B experiments only, never signoff |
| `ERC_GDS` | `../outputs/$BLOCK.gds` |
| `ERC_RUNDIR` | `../work/erc_run` |

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
