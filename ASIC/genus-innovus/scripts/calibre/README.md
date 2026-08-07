# Calibre DRC for `nanosoc_eth_chiplet_pads`

Full write-up: [`docs/tapeout/12-calibre-drc.md`](../../../../docs/tapeout/12-calibre-drc.md)

```sh
make drc                    # from ASIC/genus-innovus/
./scripts/calibre/run_drc.sh          # equivalent, no make
./scripts/calibre/run_drc.sh some/other.gds   # check a different stream
```

Headless. No `$DISPLAY`, no GUI packages, no runset.

## Files

| File | Purpose |
|---|---|
| `nanosoc_eth_chiplet_pads.drc.rules` | project-owned SVRF wrapper: supplies layout, top cell and output paths, then `INCLUDE`s the TSMC deck |
| `run_drc.sh` | preflight + headless `calibre -drc -hier` driver; summarises violations at the end |

## Environment

| Variable | Default |
|---|---|
| `DRC_GDS` | `../outputs/nanosoc_eth_chiplet_pads.gds` |
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
