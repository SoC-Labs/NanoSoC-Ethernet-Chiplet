# 12 — Calibre DRC

[← 11 Known issues](11-known-issues.md) · [index](00-index.md)

Calibre DRC had **never run to completion on this design**. This page is the working
invocation, why the previous three attempts all failed, and — importantly — what the
result does and does not mean once it does run.

> Commands prefixed `make <target>` run from `ASIC/genus-innovus/`.
> Verified on `srv03335` against **Calibre v2023.1_18.8** on 2026-08-06.

---

## TL;DR

```sh
make drc                     # headless, no X display needed
```

or, without make:

```sh
ASIC/genus-innovus/scripts/calibre/run_drc.sh
```

Results land in `ASIC/genus-innovus/work/drc_run/`:

| File | What it is |
|---|---|
| `nanosoc_eth_chiplet_pads.drc.summary` | human-readable; per-rulecheck counts |
| `nanosoc_eth_chiplet_pads.drc.results` | ASCII results database; feeds RVE |
| `calibre_drc.log` | full transcript |
| `*.density`, `*.rep` | ~170 auxiliary files the TSMC deck writes into the run directory |

To view results interactively: `calibre -rve -drc work/drc_run/nanosoc_eth_chiplet_pads.drc.results`

---

## Why it never worked

Three independent faults, all on the same code path.

### 1. The rule deck ships with placeholders, not variables

Lines 230–235 of `/tsmc65pdk/65/CMOS/util/MAIN_DRC_TopMu/CLN65S_9M_6X1Z1U.26_2a`:

```svrf
LAYOUT SYSTEM GDSII
LAYOUT PATH "GDSFILENAME"
LAYOUT PRIMARY "TOPCELLNAME"

DRC RESULTS DATABASE "DRC_RES.db"
DRC SUMMARY REPORT "DRC.rep"  // HIER
```

`GDSFILENAME` and `TOPCELLNAME` are **literal strings**. TSMC expects you to supply the
real values. Nothing substitutes them — not the shell, not Innovus, not Tcl. Point
Calibre at this deck as-is and you get:

```
ERROR: Failure to open input file GDSFILENAME for read access.
```

because Calibre is looking for a file *named* `GDSFILENAME` in the current directory.

The flow made this exact mistake. `ASIC/asic-flows/Cadence/4_pnr_route.tcl:58` has:

```tcl
set GDSFILENAME $OUT_DIR/${block_name}.gds
```

That sets a **Tcl** variable. The SVRF deck never sees it. The two `GDSFILENAME`s are
unrelated strings that happen to be spelled the same — a coincidence that has cost this
project three failed DRC attempts.

The 0-byte `work/DRC_RES.db` in the tree is the fossil: Calibre got far enough to create
the results database named on line 234, then died opening the layout.

### 2. The `source` of `cal_enc.tcl` needs Tk

The other `CALIBRE_HOME`-guarded block in `4_pnr_route.tcl` sources
`$CALIBRE_HOME/shared/pkgs/icv/tools/queryenc/cal_enc.tcl`, which fails with
`(IMPSE-110) ... can't find package Tk 8.0` under a non-GUI Innovus.

### 3. The failure held a Cadence seat

`exec` raising a Tcl error aborted the script *before* its final `exit`, so Innovus
dropped to an interactive prompt and held a licence indefinitely.

**All three are avoided by not running DRC from inside Innovus at all.** The Makefile
now runs `pnr_route` under `env -u CALIBRE_HOME`, so neither block fires, and DRC is a
separate target. `ASIC/asic-flows/` is a shared submodule and is deliberately not
modified.

---

## The wrapper deck

`ASIC/genus-innovus/scripts/calibre/nanosoc_eth_chiplet_pads.drc.rules` is a small
project-owned SVRF file that supplies the real values and then `INCLUDE`s the foundry
deck. **The foundry deck is never copied, patched or `sed`-ed** — `/tsmc65pdk` is shared,
lab-wide collateral and stays read-only.

```svrf
DRC ICSTATION YES                    // <-- load-bearing, see below

LAYOUT PATH    "$DRC_GDS"
LAYOUT SYSTEM  GDSII
LAYOUT PRIMARY "nanosoc_eth_chiplet_pads"

DRC RESULTS DATABASE "nanosoc_eth_chiplet_pads.drc.results" ASCII
DRC SUMMARY REPORT   "nanosoc_eth_chiplet_pads.drc.summary" REPLACE HIER
DRC MAXIMUM RESULTS 1000

INCLUDE "/tsmc65pdk/65/CMOS/util/MAIN_DRC_TopMu/CLN65S_9M_6X1Z1U.26_2a"
```

### `DRC ICSTATION YES` is what makes this legal — do not remove it

The obvious version of this file does **not** work. SVRF normally rejects a
specification statement given twice, and the foundry deck sets all of these again:

```
ERROR: Error SPC1 on line 5 of <deck> - superfluous specification statement: layout primary.
```

Measured, both orderings, with and without `-turbo`:

| Wrapper contains | Result |
|---|---|
| spec statements, then `INCLUDE` | **SPC1 error** |
| `INCLUDE`, then spec statements | **SPC1 error** |
| spec statements + `DRC ICSTATION YES`, then `INCLUDE` | **works** |

`DRC ICSTATION YES` puts Calibre in the mode Calibre Interactive itself uses: duplicate
specification statements are tolerated and **the top-level rule file wins**. This was
found by diffing a working Calibre Interactive run against a failing hand-written one and
bisecting the difference; deleting that single line from the working deck reproduces
SPC1 exactly.

### Environment variables expand in paths, but not in cell names

`LAYOUT PATH "$DRC_GDS"` and `INCLUDE "$DRC_DECK"` expand. `LAYOUT PRIMARY "$DRC_TOPCELL"`
does **not** — SVRF expands environment variables in *file path* strings only. Tested:
with `$DRC_TOPCELL` set correctly, Calibre still reported

```
ERROR: Specified primary cell $DRC_TOPCELL is not located within the input layout database.
```

So the top cell is hard-coded in the deck. `run_drc.sh` reads it back out of the deck and
reports it before launching, because Calibre only discovers a mismatch *after* reading
the whole 415 MB stream.

---

## The top cell

`nanosoc_eth_chiplet_pads` — confirmed by parsing the GDS hierarchy directly rather than
trusting the file name. Of 2,485 structures, exactly **one** is referenced by nothing:

```
total cells: 2485
TOP CELLS (1):
    nanosoc_eth_chiplet_pads
```

There are **no unresolved references**: 2,484 distinct structures are referenced and all
2,484 are defined. A previous reference run got this wrong — its expanded deck named
`nanosoc_eth_chiplet.gds` (the pre-pads stream) against top cell
`nanosoc_eth_chiplet_pads`, which is not a cell in that file, hence its 0-byte database.

---

## Alternative: the Calibre Interactive runset

`calibre -gui -drc -batch -runset <runset>` also works, **including headless with
`DISPLAY` unset** — verified end-to-end against the real TSMC deck. It solves the
placeholder problem the same way, by generating `_CLN65S_9M_6X1Z1U.26_2a_` in the run
directory containing exactly the wrapper pattern above.

The wrapper deck is preferred because it is version-controlled, greppable, reviewable in
a diff, and does not depend on the GUI packages. But if you need Calibre Interactive
(e.g. to drive RVE), the runset path is sound.

---

## What this DRC covers — read this before quoting a number

The GDS is **not a complete chip**, so a clean-ish DRC result here is not signoff.
Measured from the stream:

| Content | Present? |
|---|---|
| Routing, PG, vias (2,821,993 via instances) | yes |
| Memory macros / ROMs (672 structures, 559,196 shapes) | yes — real transistor geometry |
| Standard cells | **no device geometry** |
| IO drivers, bond pads | **no device geometry** |
| Seal ring (layer 162), passivation `CB` (76), polyimide `PM` (5) | **absent — not in the GdsOutMap at all** |
| Metal fill | **absent — `add_metal_fill` is nowhere in this flow** |

`gds_merge_list` (`scripts/config.tcl:198`) merges only the 8 memory macros. Front-end
layers are correspondingly sparse — 10,109 `OD` and 12,854 `PO` shapes across the whole
die, which is a memory-macro count, not a 150k-instance-design count.

Consequences for reading the report:

- **Front-end rules** (OD/PO/CO/NW/implant, latch-up, ESD) are checked against almost
  nothing. Passing them means nothing.
- **Density rules will fail** and should. The deck has `#DEFINE CHECK_LOW_DENSITY` and
  `#DEFINE FULL_CHIP` on, and there is no fill.
- **Seal ring rules will fail.** The deck has `#DEFINE WLCSP_SEALRING` on and the design
  has no seal ring.
- The deck's switches cannot be changed from the wrapper. SVRF has no `#UNDEF`, and the
  foundry deck `#DEFINE`s these unconditionally. Turning them off needs a project-owned
  *copy* of the deck — a separate decision, and one to take with your broker, not
  unilaterally.

What *is* meaningful here is the back-end geometry: metal width/space/enclosure, via
rules, antenna, and offgrid. That is a real check of what P&R produced.

---

## Runtime and licences

`-turbo 8` on a 16-core host. Calibre takes one `calibre` licence plus turbo licences;
`run_drc.sh` queues for a licence by default rather than failing (`DRC_NOWAIT=1` to fail
fast instead).

The deck contains **1,904 rulechecks**. Runtime on the real 415 MB stream is **not
measured** — see below.

---

## What is still unproven

Honesty section, in the spirit of the rest of this guide.

- **The full run has never completed.** Everything above was validated against the real
  TSMC deck using a small synthetic layout, which exercises deck compilation, all four
  specification overrides, layout reading, and results writing — 1,904 rulechecks
  executed, exit 0 — but not the 415 MB stream.
- **Runtime and peak memory are unknown.** Budget hours, and watch RSS on the first run.
- **The violation count is unknown**, and `DRC MAXIMUM RESULTS 1000` will cap per-check
  reporting. Raise it to `ALL` only once the totals are known to be sane; an uncapped
  ASCII database on a design with no fill can be very large.
- **Antenna signoff** using the foundry antenna deck is still not wired up.
- **LVS** cannot run on this site at all — see [09](09-signoff-checklist.md).
