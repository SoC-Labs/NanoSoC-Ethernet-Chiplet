# LVS flow — interface contract

**This file is the spec. `run_lvs.sh`, `lvs.mk` and the docs are all built against
it. Do not change a name or a default here without changing all three.**

Target: a Calibre nmLVS flow that is (a) runnable on this host today, (b) free of
site-specific paths, so it can be promoted into the shared `SoC-Labs/ASIC-Flow`
toolkit as a `Mentor/` flow and reused by any project on any PDK.

---

## 1. The environment contract

Every input is an environment variable. The runner hard-codes **no** paths.
A project supplies these from its own Makefile; nothing else is needed.

### Required — no default, fail loudly if unset

| Variable | Meaning |
|---|---|
| `LVS_DECK` | Foundry LVS rule deck (e.g. TSMC `calibre.lvs`). Read-only; never edited in place. |
| `LVS_GDS` | The layout: streamed GDSII. |
| `LVS_TOP` | Top cell name. Must exist in both the GDS and the netlist. |
| `LVS_SRC_V` | The schematic: **post-P&R** Verilog netlist (`write_netlist` output). |
| `LVS_RUNDIR` | Run directory. All outputs land here; the runner `cd`s into it. |

### Required for leaf-cell resolution

| Variable | Meaning |
|---|---|
| `STDCELL_VLOG` | Space-separated standard-cell **simulation Verilog** (Front-End view). |
| `IO_VLOG` | Space-separated IO-driver simulation Verilog. May be empty for a macro. |
| `MACRO_CDLS` | Space-separated **real transistor CDLs** for hard macros (SRAM, ROM, …). May be empty. |

### Optional — sane defaults

| Variable | Default | Meaning |
|---|---|---|
| `LVS_SOURCE_ADDED` | *(empty)* | Foundry `source.added` primitive stubs, passed to `v2lvs -lsp`. |
| `LVS_POWER` | `VDD` | Power net name(s), substituted for the deck's `POWER_NAME` placeholder. |
| `LVS_GROUND` | `VSS` | Ground net name(s), substituted for `GROUND_NAME`. |
| `BONDPAD_CELLS` | *(empty)* | Pin-less bump/pad cells needing an empty `.SUBCKT` stub. |
| `LVS_BOX_LEAF` | `1` | `1` = black-box FE-only leaves. `0` = raw compare (diagnostic only). |
| `LVS_BOX_EXCLUDE_RE` | `^(ANTENNA\|DCAP\|GDCAP\|GFILL\|OD25DCAP)` | Physical-only cells to leave **unboxed** so they flatten away. |
| `LVS_TURBO` | `nproc` | Calibre `-turbo` CPU count. |
| `LVS_SOURCE_ONLY` | `0` | `1` = stop after source prep and deck build; do not launch Calibre or take a licence. |
| `LVS_NOWAIT` | `0` | `0` = queue for a Calibre licence; `1` = fail fast if none is free. Matches `run_drc.sh`. |
| `V2LVS` / `CALIBRE` | `v2lvs` / `calibre` | Tool binaries, for hosts where they are not on `PATH`. |

Both tool binaries are required even in `--check` / `--source-only` mode. Checking
for a binary takes no licence, and `v2lvs` ships inside the Calibre install, so a
host with one and not the other is not a real configuration.

---

## 2. Artefacts produced in `$LVS_RUNDIR`

| File | What it is |
|---|---|
| `${LVS_TOP}_libs.cdl` | `v2lvs -e` output: one empty `.SUBCKT` per leaf cell. |
| `${LVS_TOP}_design.cdl` | `v2lvs` output: the translated design. |
| `${LVS_TOP}_lvs_src.cdl` | The assembled SPICE source Calibre actually reads. |
| `${LVS_TOP}_lvs_box.svrf` | The generated `LVS BOX` block. |
| `${LVS_TOP}_calibre_lvs.deck` | The rewritten (project-local) copy of the foundry deck. |
| `${LVS_TOP}.lvs.rep` | The LVS report — **the verdict lives here**. |
| `calibre_lvs.log` | Full transcript. |
| `v2lvs.log` | Translation log. First place to look when a leaf cell will not resolve. |
| `svdb/` | Calibre's database, for RVE. |

The runner `cd`s into `$LVS_RUNDIR` before step 1, so tool droppings land here
rather than in the invoker's working directory.

---

## 3. Pipeline — the six steps, and why each exists

1. **`v2lvs -e` on the cell libraries** → empty `.SUBCKT` stubs.
   `-e` emits a stub per module without translating instances. Needed because
   scan-flops and IO cells use UDP-based models that `v2lvs` would otherwise
   drop, giving `No matching .SUBCKT` at compare time.

2. **`v2lvs` on the design** → the translated netlist.
   `-l` for library Verilog (referenced, not redefined), `-s` for macro CDLs
   (gives `v2lvs` the subckt **pin order**), `-lsp` for `source.added`.

3. **Assemble one SPICE deck**: `.GLOBAL` supplies, then pin-less bond-pad
   stubs, then libs + design, then the real macro CDLs.
   Batch Calibre LVS accepts **SPICE source only** — `SOURCE SYSTEM VERILOG`
   is Calibre Interactive-only and the deck rejects it with `INP1`.

4. **Rewrite the foundry deck's placeholders** into a local copy.
   TSMC ships `lvs_top`, `lvs_top.gds`, `lvs_top.cdl`, `lvs.rep`, `POWER_NAME`
   and `GROUND_NAME` as **literal strings**. Substitute, never `INCLUDE`+
   override — a duplicate spec statement is a hard `SPC1` error.
   **Then assert every substitution landed**, so foundry deck drift fails
   loudly instead of silently running against the wrong file.

5. **Splice in the `LVS BOX` block.** See §4.
   It must go in the SVRF region (after `LVS GROUND NAME`), **not** at
   end-of-file — the deck's tail is embedded TVF/Tcl and rejects SVRF there.

6. **Run `calibre -lvs -hier -64 -turbo`, then parse the report.**
   Calibre's exit status is not a verdict. Read `${LVS_TOP}.lvs.rep`.

---

## 4. Why `LVS BOX` — the load-bearing idea

Academic PDKs ship **Front-End only**: liberty, LEF and simulation Verilog, but
no transistor CDL and no cell GDS. Both sides of the comparison are therefore
device-less for standard cells, IO and pads.

Left alone, Calibre **auto-flattens** the empty layout frames. The layout ends up
with zero standard-cell instances while the source keeps all of them, and the
entire digital fabric mis-compares — an artifact of the missing data, not a
design error.

`LVS BOX` pins each leaf as a boundary black box on **both** sides, so Calibre
matches them as instances rather than dissolving them.

Measured on the archived `nanosoc_compute_chiplet_pads` run (2026-08-06), after
boxing: **598,334 / 598,334 instances matched, zero unmatched on either side**.

> Provenance note. That reference script's own footer quotes different figures
> ("554,108 → 2, ports 63 → 2") for the before/after. Those describe an
> **intermediate iteration**, not the archived result, and the archived report
> does not support them. Quote the report, never a script comment.

Two refinements the box list depends on:

- **Bond pads** (LEF-only bumps, no model at all) get a pin-less empty
  `.SUBCKT` in step 3, or the source will not even read.
- **Physical-only cells** (fill, decap, antenna diodes) are in the GDS but not
  in `write_netlist` output. They must be *excluded* from the box list so their
  frames auto-flatten and match the netlist's absence of them. Boxing them
  instead leaves them as unmatched layout instances.

Macros with real CDL (SRAM, ROM) are **never** boxed — they compare to
transistors, which is real verification.

---

## 5. What a pass means, and what it does not

Black-box LVS proves the **instance-level** picture: every cell present, of the
right type, in the right count, and the routed nets between them reconciled
against the netlist.

Be careful about claiming more. On a PDK with no cell GDS, a boxed layout cell
may carry no recognised pin shapes at all, so Calibre can match the instance
while still reporting *non-floating extra pins* against the source stub's pins.
That is what the archived compute-chiplet run shows — its entire INCORRECT
OBJECTS section is that single class, on boxed leaves. So **pin-level**
connectivity on boxed leaves is weakly checked at best; do not advertise "every
port wired as the netlist says".

It does **not** prove cell interiors — those are black boxes by construction.
Full signoff LVS needs the foundry Back-End packages (transistor CDL + cell GDS).
Never claim a boxed run as signoff, and never suppress a discrepancy with
`LVS IGNORE PORTS` to manufacture a `CORRECT`.

---

## 6. Expected residual discrepancy classes

Two classes are artifacts of an FE-only PDK rather than design errors. Neither
may be masked (no `LVS IGNORE PORTS`, no bulk-check suppression) — document them.

**a. Non-floating extra pins on boxed leaves.** The source stub declares pins;
the boxed layout frame has none Calibre recognises, so it reports the source
pins as extra. This is the class that actually drives the archived
compute-chiplet verdict — its INCORRECT OBJECTS section contains this and
nothing else. Counts there are capped by `LVS REPORT MAXIMUM 1000`.

**b. PG net naming — only if your P&R emitted no PG.** `write_netlist` without
`-include_pwr_gnd`, plus a stream carrying no PG text, leaves the layout supply
grid unnamed so it cannot equate to the source's global supplies. Fix on the P&R
side and re-emit; out of scope here.

Check (b) applies before citing it: in the archived compute-chiplet report
`VDD`/`VSS` are correspondence points and PG is *not* the discrepancy driver,
despite that script's footer claiming it is.

## 6b. Cell Verilog must match the netlist's PG convention

If the P&R netlist wires `.VDD`/`.VSS` on cell instances, the `-e` stubs must
declare those pins or Calibre rejects the whole source with `Wrong pin count`
and never reaches a compare. Vendors ship both variants — TSMC's tcbn65lp
release has `tcbn65lp.v` (no PG ports) beside `tcbn65lp_pwr.v` (`module INVD1
(I, ZN, VDD, VSS)`). Pick the one matching your netlist, per library: an IO
library whose pad instances carry no PG pins needs the plain variant even when
the standard cells need `_pwr`.

---

## 7. Style rules

- Comments concise. Explain **why**, not what the line does.
- Audience: an engineer new to ASIC backend flows. Name the concept, then move on.
- No site paths, no project names, no `dam1n19`/`dwn1c21` home directories in
  anything under `ASIC/lvs-flow/`. Projects supply paths; the flow supplies logic.
- `set -u` and `set -o pipefail`. Fail loudly with an actionable message.
- Never modify `$LVS_DECK` or anything under `/tsmc65pdk` or
  `/research/AAA/{ip,phys_ip}_library` — those are read-only lab collateral.
