# S01 — Stage scripts and Makefile: line-by-line reference

**What this page is for.** This is the annotated source of the driver. Every meaningful line
of `ASIC/genus-innovus/Makefile` and of the four `ASIC/asic-flows/Cadence/*.tcl` stage
scripts, quoted with its own line number, explained, and cited to the Cadence manual
installed on this site. Where the script disagrees with the manual — or with its own header
comment — that is called out explicitly.

**What this page is not.** It does not teach floorplanning, CTS or DRC. The conceptual
pages do that and this page links to them rather than repeating them:

[00-index](../00-index.md) ·
[01-flow-overview](../01-flow-overview.md) ·
[02-innovus-basics](../02-innovus-basics.md) ·
[03-floorplan](../03-floorplan.md) ·
[04-power-plan](../04-power-plan.md) ·
[05-place-cts-route](../05-place-cts-route.md) ·
[06-fill-antenna-bondpads](../06-fill-antenna-bondpads.md) ·
[07-reading-reports](../07-reading-reports.md) ·
[08-debugging](../08-debugging.md) ·
[09-signoff-checklist](../09-signoff-checklist.md) ·
[11-known-issues](../11-known-issues.md) ·
[12-calibre-drc](../12-calibre-drc.md) ·
[13-lec](../13-lec.md) ·
[16-open-defects](../16-open-defects.md)

Read [01-flow-overview](../01-flow-overview.md) first if you want the shape of the flow.
Come here when you want to know what a specific line does and whether it is right.

---

## Contents

- [Manual sources, and how they are cited](#manual-sources-and-how-they-are-cited)
- [1. How it hangs together](#1-how-it-hangs-together)
  - [1.1 The stage graph](#11-the-stage-graph)
  - [1.2 What each stage reads and writes](#12-what-each-stage-reads-and-writes)
  - [1.3 The `read_db` / `write_db` resume model](#13-the-read_db-write_db-resume-model)
  - [1.4 The `cwd = work/` convention](#14-the-cwd-work-convention)
  - [1.5 Where control passes between the toolkit and the project](#15-where-control-passes-between-the-toolkit-and-the-project)
  - [1.6 There are two files called `procs.tcl`](#16-there-are-two-files-called-procstcl)
- [2. `1_synthesis.tcl` — Genus](#2-1_synthesistcl-genus)
- [3. `2_pnr_setup.tcl` — Innovus, floorplan to placement](#3-2_pnr_setuptcl-innovus-floorplan-to-placement)
- [4. `3_pnr_clock.tcl` — Innovus, CTS](#4-3_pnr_clocktcl-innovus-cts)
- [5. `4_pnr_route.tcl` — Innovus, route to GDSII](#5-4_pnr_routetcl-innovus-route-to-gdsii)
- [6. `procs.tcl` — the reporting helpers](#6-procstcl-the-reporting-helpers)
- [7. The Makefile](#7-the-makefile)
  - [7.1 Header, variables, defaults](#71-header-variables-defaults)
  - [7.2 Preflight targets](#72-preflight-targets)
  - [7.3 `cpf-patch`](#73-cpf-patch)
  - [7.4 `syn`](#74-syn)
  - [7.5 The LEC targets](#75-the-lec-targets)
  - [7.6 `INNOVUS := innovus -stylus -files`](#76-innovus-innovus-stylus-files)
  - [7.7 The three P&R stage targets](#77-the-three-pr-stage-targets)
  - [7.8 `gui` and `pnr_setup`](#78-gui-and-pnr_setup)
  - [7.9 Calibre DRC and LVS targets](#79-calibre-drc-and-lvs-targets)
  - [7.10 `status`, `clean`, `distclean`, `help`](#710-status-clean-distclean-help)
- [8. `common.mk` — only the parts this Makefile uses](#8-commonmk-only-the-parts-this-makefile-uses)
- [9. Divergence index](#9-divergence-index)
- [10. Things not found in the installed manuals](#10-things-not-found-in-the-installed-manuals)

---

## Manual sources, and how they are cited

Everything cited below was opened on this machine. Nothing is quoted from memory.

| Short form used here | Path under `$CDS_INSTALL/` | Title on the page | Version on the page |
|---|---|---|---|
| **Stylus TCR** | `innovus/doc/TCRcom/<cmd>.html` | Innovus Stylus Common UI Text Command Reference | 21.11, July 2021 |
| **Stylus UG** | `innovus/doc/UGcom/<Chapter>.html` | Innovus Stylus Common UI User Guide | 21.11 |
| **Legacy TCR** *(name-mapping only — not a reference for this flow)* | `innovus/doc/innovusTCR/<cmd>.html` | Innovus Text Command Reference | 21.11, July 2021 |
| **CPF Reference** | `innovus/doc/cpf_ref/reference.html` | CPF Reference | — |
| **Genus ComRef** | `genus/doc/genus_comref/<chapter>.html` | Genus Command Reference | 21.1, September 2022 |
| **Genus AttRef** | `genus/doc/genus_attref/<chapter>.html` | Genus Attribute Reference | 21.1, September 2022 |
| **Genus UG** | `genus/doc/genus_user/intro.html` | Genus User Guide (Introduction) | — |

Two things about the doc install that matter and are easy to get wrong:

**`innovusTCR/` and `innovusUG/` are the LEGACY-UI editions. This flow is Stylus, so the
manuals it needs are `TCRcom/` and `UGcom/`.** The two sets are a different command
vocabulary, not two renderings of the same one. `innovusTCR/` is one HTML file per *native*
command name; `TCRcom/` (1,533 files) is one per *Common UI* command name. Verified by
testing both directories for the same names:

| Command | `innovusTCR/` (legacy) | `TCRcom/` (Stylus) |
|---|---|---|
| `create_floorplan` | — | **yes** |
| `read_db` | — | **yes** |
| `write_db` | — | **yes** |
| `route_design` | — | **yes** |
| `check_drc` | — | **yes** |
| `floorPlan` | **yes** | — |
| `restoreDesign` | **yes** | — |
| `saveDesign` | **yes** | — |
| `globalDetailRoute` | **yes** | — |

Every Stylus command this flow uses resolves in `TCRcom/` and **none** of them resolves in
`innovusTCR/`. So if you grep `innovusTCR/` for a command in these scripts and find nothing,
that does not mean the command is undocumented — you are in the wrong manual. Conversely,
the legacy edition is the only place the native names are documented, which is useful when
you are reading an old log or a pre-Stylus script: `restoreDesign` ↔ `read_db`,
`saveDesign` ↔ `write_db`, `globalDetailRoute` ↔ `route_design`, `floorPlan` ↔
`create_floorplan`, `addFiller` ↔ `add_fillers`, `sroute` ↔ `route_special`.

**Nothing in these four stage scripts is legacy-UI-only.** Every command they issue has a
current Common UI page, and this document cites the Common UI page in every case. The one
place a legacy page was consulted at all was to confirm the `restoreDesign` ↔ `read_db`
correspondence above; it is not used as a reference for any behaviour claim.

Note that a command missing from `innovusTCR/` is *not* automatically a Stylus command —
`verifyGeometry`, for instance, is in neither directory under that name. Absence from one
tree proves nothing on its own; check the other before concluding anything.

**Genus manuals here are 21.1; the Genus binary is 21.15-s080_1.** The version string is in
every artefact Genus writes (`outputs/nanosoc_eth_chiplet_pads_gate1.cpf`, first comment
block). Innovus is better matched: manuals 21.11, binary `21.11-s130_1`. Where a Genus
option behaves differently from the 21.1 page, this document says so and marks the
observation as measured.

---

## 1. How it hangs together

### 1.1 The stage graph

```
                     ASIC/genus-innovus/Makefile        <- the driver (this repo)
                                 |
        +------------+-----------+-----------+-------------+
        |            |           |           |             |
      syn        pnr_place    pnr_cts    pnr_route       drc / lvs / lec*
        |            |           |           |             |
      GENUS       INNOVUS     INNOVUS     INNOVUS       CALIBRE / CONFORMAL
        |            |           |           |
   1_synthesis  2_pnr_setup  3_pnr_clock  4_pnr_route     <- ASIC/asic-flows/Cadence
        |            |           |           |               (SHARED submodule)
        |            |           |           |
        +---- source ../scripts/*.tcl -------+             <- ASIC/genus-innovus/scripts
                                                              (PROJECT-OWNED)

  config.tcl        every stage, first line
  read_flist.tcl    stage 1 only, via $hdl_file_list
  floorplan.tcl     stage 2      -> docs/tapeout/03
  power_plan.tcl    stage 2      -> docs/tapeout/04
  preplace.tcl      stage 2
  postplace.tcl     stage 2
  cts_setup.tcl     stage 3      -> writes the _placed snapshot
  route_setup.tcl   stage 4      -> writes the _cts snapshot
  place_bondpads.tcl stage 4     -> sources filler.tcl  -> docs/tapeout/06


  DATA FLOW

  RTL + UPF ──GENUS──> _gate_power.v ──┐
                       _gate1.cpf ─────┤
                       (+ _gate.v, _gate2.upf, _gate.sdf, _syn.sdc, lec.dofile)
                                       │
                                       v
  LEF + MMMC ──────────────> INNOVUS: init_design ──> floorplan ──> power ──> place
                                       │
                                       │  write_db nanosoc_eth_chiplet_pads
                                       v
                             INNOVUS: read_db ──> ccopt ──> post-CTS opt
                                       │  write_db nanosoc_eth_chiplet_pads
                                       v
                             INNOVUS: read_db ──> route ──> post-route hold opt
                                                ──> filler ──> bond pads
                                                ──> checks ──> write_stream
                                                ──> _pnr.v, _pnr.sdf, write_db
```

`lec*` sits off to one side deliberately: `make lec` consumes `work/lec.dofile`, which
**synthesis** writes, so it depends on `syn` and not on any P&R stage. `make lec-pnr`
depends on stage 4. See [13-lec](../13-lec.md).

### 1.2 What each stage reads and writes

| Stage | make target | Script | Reads | Writes (headline) |
|---|---|---|---|---|
| 1 | `syn` | `1_synthesis.tcl` | `$ASIC_FLIST` RTL, `../inputs/*.upf`, `../inputs/constraints.sdc`, `.lib` × 10 | `outputs/*_gate.v`, `*_gate_power.v`, `*_gate1.cpf`, `*_gate2.upf`, `*_gate.sdf`, `*_syn.sdc`, `work/lec.dofile`, `work/*_syn_session` |
| 2 | `pnr_place` | `2_pnr_setup.tcl` | `*_gate_power.v`, `*_gate1.cpf`, `scripts/*.mmmc`, 12 LEFs | `work/nanosoc_eth_chiplet_pads/` (DB), `work/design.sdf`, `reports/timing_summary_0{0,1}_*` |
| 3 | `pnr_cts` | `3_pnr_clock.tcl` | that DB | same DB updated, `work/*_placed/` snapshot, `work/design_clk.spec`, `reports/*_0{2,3}_*` |
| 4 | `pnr_route` | `4_pnr_route.tcl` | that DB | same DB updated, `work/*_cts/` snapshot, `outputs/*.gds`, `outputs/*_pnr.v`, `outputs/*_pnr.sdf`, `reports/*_imp_*`, `reports/*_0{4,5}_*`, `work/timing_full_*.mtarpt` |

### 1.3 The `read_db` / `write_db` resume model

All three Innovus stages use the **same** database directory name inside `work/`:

```
2_pnr_setup.tcl:66                                write_db $block_name
3_pnr_clock.tcl:19  read_db $block_name    ...    write_db $block_name
4_pnr_route.tcl:18  read_db $block_name    ...    write_db $block_name   (twice: :37 and :73)
```

The Stylus TCR is explicit that this is the intended pairing: `read_db` "Reads a saved
database created by `write_db` in a previous session. It auto-detects the database type and
loads it" (**Stylus TCR — `read_db`**, `TCRcom/read_db.html`). `write_db` "Writes the
complete design database in the native Innovus DB format if `<out_dir>` is given" and "You
can write a design to the same location from which you read the design. The new data will
overwrite the previous data" (**Stylus TCR — `write_db`**, `TCRcom/write_db.html`).

Consequences, both load-bearing:

1. **The stages cannot be parallelised and must run in order.** Each one's input is the
   previous one's output, and `read_db` will not load a second DB into a live session:
   "Innovus does not support loading another DB while a design is already in memory"
   (**Stylus TCR — `read_db`**).
2. **Any stage can be re-invoked to resume.** State lives in `work/`, not in `make`. There
   are no stamp files.

Because every stage writes the same name, only the newest state would survive. The two
project-side snapshot writes exist to fix that — `cts_setup.tcl:9` writes
`${block_name}_placed` and `route_setup.tcl:12` writes `${block_name}_cts`, each taken by
the *consuming* stage immediately after its `read_db` and before it changes anything.
Measured today: 47 MB (`_placed`), 57 MB (`_cts`), 47 MB (current). Detail in
[02-innovus-basics](../02-innovus-basics.md#loading-a-snapshot-instead-of-the-final-db) and
[08-debugging](../08-debugging.md#resuming-from-a-snapshot-db).

Note what the flow does **not** save. `write_db` is called bare, so neither `-timing_graph`
nor `-rc_extract` is passed, and the manual warns that "the state of the DB after `read_db`
depends on what was written, and you may need to repeat RC extraction, timing analysis, etc.
if that data was not saved" (**Stylus TCR — `read_db`**). Every stage therefore rebuilds
the timing graph after loading. That is a deliberate-looking trade (disk vs CPU) but it is
not documented anywhere in the scripts, and `-timing_graph` would remove minutes from each
resume.

### 1.4 The `cwd = work/` convention

Every tool invocation `cd`s into `work/` first. This is not cosmetic. `config.tcl` defines

```tcl
116  set LOG_DIR ../logs
117  set REPORT_DIR ../reports
118  set OUT_DIR ../outputs
```

as **relative** paths, and every stage script opens with `source ../scripts/config.tcl`.
Launch a tool anywhere else and the very first `source` fails.

The Makefile honours this with `cd $(WORK_DIR)/;` at the head of each recipe line, and — correctly — uses **absolute** paths in the assertion lines that follow, because make runs each
recipe line in its own shell so the `cd` does not persist.

> **TRAP — `cd x; cmd`, not `cd x && cmd`.**
> All four stage recipes (`Makefile:122, 197, 202, 232`) separate the `cd` from the tool with
> a semicolon. If `work/` does not exist, `cd` fails, the shell carries on, and the tool
> launches in `ASIC/genus-innovus/` — where `../scripts/config.tcl` resolves to
> `ASIC/scripts/config.tcl`, which does not exist. The tool then fails and, per the whole
> theme of this flow, exits 0. `pnr_place` is protected because it depends on `setup_dirs`;
> `pnr_cts` and `pnr_route` have **no prerequisites at all** and are exposed. In practice
> `work/` always exists by the time you run them, which is why this has never been seen —
> it is a latent trap, not an observed failure.

Two more relative-path effects worth knowing:

- `work/lec.dofile`, `work/design_clk.spec`, `work/design.sdf` and the four
  `work/timing_full_*.mtarpt` files are written with **bare** relative names, so they land in
  `work/` and `make clean` deletes them. On the 2026-08-05 baseline the four `.mtarpt` files
  alone were **853 MB** (100 MB + 378 MB + 100 MB + 274 MB).
- There are **two different `LOG_DIR`s**: make's (`$(DESIGN_DIR)/logs`, absolute) and
  Tcl's (`../logs`, relative to `work/`). They resolve to the same directory. They are not
  the same variable and nothing keeps them in sync.

### 1.5 Where control passes between the toolkit and the project

`ASIC/asic-flows` is a **shared submodule** that other SoC Labs designs build from. The four
stage scripts in it are generic; everything design-specific is reached by `source`:

| From | Line | Sources | Owned by |
|---|---|---|---|
| `1_synthesis.tcl` | 14 | `../scripts/config.tcl` | project |
| `1_synthesis.tcl` | 26 | `$hdl_file_list` = `../scripts/read_flist.tcl` | project |
| `1_synthesis.tcl` | 51 | `../scripts/dft_setup.tcl` | **does not exist** (dead: `DFT` is 0) |
| `2_pnr_setup.tcl` | 14, 46, 47, 54, 64 | `config.tcl`, `floorplan.tcl`, `power_plan.tcl`, `preplace.tcl`, `postplace.tcl` | project |
| `2_pnr_setup.tcl` | 49 | `$env(SOCLABS_ASIC_FLOW_DIR)/Cadence/procs.tcl` | toolkit |
| `3_pnr_clock.tcl` | 14, 22 | `config.tcl`, `cts_setup.tcl` | project |
| `3_pnr_clock.tcl` | 20 | toolkit `procs.tcl` | toolkit |
| `4_pnr_route.tcl` | 13, 26, 39 | `config.tcl`, `route_setup.tcl`, `place_bondpads.tcl` | project |
| `4_pnr_route.tcl` | 19 | toolkit `procs.tcl` | toolkit |
| `4_pnr_route.tcl` | 22 | `$CALIBRE_HOME/.../cal_enc.tcl` | Mentor install |

Note the asymmetry: project scripts are reached by the **relative** path `../scripts/…`
(hence the `cwd = work/` rule), while the toolkit's own `procs.tcl` is reached through the
**environment variable** `SOCLABS_ASIC_FLOW_DIR`. That variable is exported by
`ASIC/common.mk:87` and by nothing else in the repo. Passing the stage script by path is
therefore not enough — without the export, stage 2 aborts on line 49.

**The one-way rule.** Fixes go project-side. `filler.tcl`'s move out of `route_setup.tcl`,
the OCV reordering in `cts_setup.tcl`, the `check_cpf` wrapper in `config.tcl`, the
`CALIBRE_HOME` suppression in the Makefile — all are project-side changes to avoid patching
a submodule that other designs build from. That is stated explicitly at `Makefile:229-230`.

### 1.6 There are two files called `procs.tcl`

This catches people. They are unrelated:

| Path | Defines | Sourced by |
|---|---|---|
| `ASIC/genus-innovus/scripts/procs.tcl` | `expand_env` — expands `${VAR}` and `$(VAR)` in flists | `config.tcl:1`, i.e. **every** stage |
| `ASIC/asic-flows/Cadence/procs.tcl` | `report_intermediate_step`, `report_end_step` | stages 2, 3, 4, explicitly by env path |

If a stage dies with `invalid command name "report_end_step"`, you sourced the wrong one —
or `SOCLABS_ASIC_FLOW_DIR` is unset.

---

## 2. `1_synthesis.tcl` — Genus

Full path: `ASIC/asic-flows/Cadence/1_synthesis.tcl` (96 lines).
Invoked by `make syn` as `genus -f <script> -log ../logs/syn_logs`, from `work/`.

Where this section says "observed", the evidence is
`ASIC/genus-innovus/baseline_2026-08-05/logs/syn_logs.log7` — a complete run. That log's
`@file(1_synthesis.tcl) N:` prefixes are **one lower** than today's line numbers, because the
`soclabs_setup_multi_cpu` refactor added a line. Line numbers quoted below are the current
file's.

### 2.1 Header (lines 1-13)

```tcl
  5  # run: genus -f 1_synthesis.tcl
```

> **HEADER COMMENT vs MANUAL.** `-f` is not in the documented Genus invocation syntax:
>
> ```
> genus [-abort_on_error] [-batch] [-del_scale 10]
> [-disable_user_startup] [-execute command]+ [-files string]+ ...
> ```
>
> (**Genus UG — Invoking Genus**, `genus_user/intro.html`). The same page says "You can
> abbreviate the options for the genus command as long as there are no ambiguities with
> other options", and `-files` is the only option beginning with `f`, so `-f` is a legal
> unambiguous abbreviation of `-files`. The header is therefore *usable* but not literal —
> and this is exactly why the Innovus headers, which copy the same idiom, are wrong
> (Innovus does not abbreviate; see [§7.6](#76-innovus-innovus-stylus-files)).
> It also omits the `-log` the Makefile always passes.

### 2.2 Configuration and CPU setup (lines 14-17)

```tcl
 14  source ../scripts/config.tcl
 15
 16  # Must follow the source: soclabs_setup_multi_cpu is defined in config.tcl.
 17  soclabs_setup_multi_cpu
```

`config.tcl` sets `block_name`, all library/LEF/GDS paths, the relative output dirs, and —
critically — wraps `check_cpf` in a `catch` so that a rule-check failure cannot abort the
`-f` script. That wrapper is documented at length in `config.tcl` itself and in
[11-known-issues §f](../11-known-issues.md).

`soclabs_setup_multi_cpu` is a proc in `config.tcl`, not a tool command. It calls
`set_multi_cpu_usage -local_cpu $INNOVUS_LOCAL_CPU` (default 14), and under Innovus with
`INNOVUS_DISTRIBUTED=1` also `set_distributed_hosts -ssh -add …`. Both commands are
documented: `set_multi_cpu_usage` "Specifies the number of threads to use for
multi-threading… This command is required for multi-threading, distributed processing, and
Superthreading" (**Stylus TCR — `set_multi_cpu_usage`**, `TCRcom/set_multi_cpu_usage.html`);
`set_distributed_hosts` "Specifies the multiple-CPU processing configuration for distributed
processing or Superthreading" (**Stylus TCR — `set_distributed_hosts`**). The proc guards on
`[info commands set_distributed_hosts]` because Genus has no such command, so under Genus it
degrades to local-only — which is why one proc can serve both tools.

**Artefact:** the log line `MULTICPU: local=14 (distribution off)`.

### 2.3 Library setup (lines 19-23)

```tcl
 20  set_db init_lib_search_path $lib_search_path_list
 21  create_library_domain domain1
 22  set_db -verbose [get_db library_domains domain1] .library $syn_lib_list
 23  check_library > $LOG_DIR/syn_lib_check.log
```

- `init_lib_search_path` is a "Read-write root attribute. Specifies a list of UNIX
  directories that Genus should search to locate the technology libraries and LEF libraries",
  default `{ . /install_path/build/tools.lnx86/lib/tech}` (**Genus AttRef — General**,
  `genus_attref/general.html`). `set_db` **replaces** it, so the tool's own tech directory
  and `.` are dropped. That is fine here because every entry in `$syn_lib_list` lives in one
  of the ten directories listed, but it means a bare library name that used to resolve from
  `.` will stop resolving.
- `create_library_domain domain1` — "Creates the specified library domains. To use dedicated
  libraries with portions of the design, you must use this command **before you read in any
  libraries** for the specified library domains" (**Genus ComRef — Advanced Low Power**,
  `genus_comref/advanced_lps.html`). The ordering here is correct: domain first, then the
  `.library` assignment on line 22. The manual's own example is the same two-step
  (`create_library_domain dom1` then `set_db [get_db library_domains dom1] .library lib1.lib`).
- Line 22 assigns all ten `.lib` files — `tcbn65lpwc`, four RF sizes, the IO driver, two
  ROMs, two flash-cache macros — as the domain's `library` attribute. `-verbose` makes Genus
  echo the assignment.
- `check_library` "Allows you to check specific information in the loaded libraries with
  regards to level shifters, isolation cells, and state retention cells. The report also
  lists the unusable cells. … Without any options specified, this command lists the number of
  level shifters, isolation cells, and state retention cells available in each of the
  library domains" (**Genus ComRef — Advanced Low Power**).

**Artefacts:** `logs/syn_lib_check.log` (1,969 bytes on the baseline). This is the file that
tells you a library did not load — see [08-debugging](../08-debugging.md).

> **NOTE — this is the line that fails when the ROM libs are missing.** `set_db` on line 22
> is where Genus opens each `.lib`, so an absent `rom_via_ss_1p08v_1p08v_125c.lib` kills the
> run here, seconds in, with `Cannot open file`. That is precisely why the Makefile has
> `romlibs-check` as a `syn` prerequisite ([§7.2](#72-preflight-targets)).

### 2.4 RTL read and elaborate (lines 25-28)

```tcl
 26  source $hdl_file_list
 27  read_hdl -define POWER_PINS $top_level_hdl
 28  elaborate $block_name
```

- Line 26 sources `../scripts/read_flist.tcl` (via `$hdl_file_list`, set in `config.tcl:69`),
  which walks `$::env(ASIC_FLIST)` recursively and issues one
  `read_hdl -define TIDELINK_PHY_V2 -language sv <file>` per source file. `read_hdl` "Loads
  one or more HDL files in the order given into memory" and `-define macro=value` "Defines a
  Verilog macro with the specified value, which is equivalent to the `define macro value"
  (**Genus ComRef — Input and Output**, `genus_comref/inout.html`). Note the manual's caveat
  on `-define`: "If this option is specified, `-language` option is ignored." The project
  wrapper passes both `-define` and `-language sv`; per the manual the `-language` is
  ignored, and SystemVerilog parsing works anyway because `hdl_language` defaults to
  something that accepts it. Marked **inferred** — not separately verified.
- Line 27 reads the pad-level wrapper `ASIC/tech_wrappers/tsmc65/nanosoc_eth_chiplet_pads.v`
  with `POWER_PINS` defined, which is what exposes the PG pins on the IO cells.
- `elaborate $block_name` — "Creates a design hierarchy consisting of a top-level design and
  its referenced subdesigns… It also performs semantic checking, sequential register
  (flops/latches) inferencing, and high-level HDL optimizations. Instances of undefined
  modules or entities are marked as unresolved" (**Genus ComRef — Elaboration and
  Synthesis**, `genus_comref/synthesis.html`). Naming the top explicitly matters: without it
  "it elaborates all the modules not instantiated by any other module as top-level and
  elaborates them all".

The same page notes `hdl_error_on_latch` and `hdl_error_on_blackbox` attributes that would
turn inferred latches and blackboxes into errors. Neither is set by this flow. Given the
history of silently-lost logic recorded in [00-index](../00-index.md), `hdl_error_on_blackbox`
is worth considering.

**Observed:** on the baseline, lines 26-28 take from log line 247 to 936 — the bulk of the
early runtime.

### 2.5 Power intent (lines 30-39)

```tcl
 31  read_power_intent -module $block_name ../inputs/${block_name}.upf
 ...
 37  apply_power_intent
 38  check_cpf -detail -license lpgxl > $LOG_DIR/syn_cpf_check.log
 39  commit_power_intent
```

- `read_power_intent` reads the IEEE-1801 (UPF) file and syntax-checks it.
- `apply_power_intent` "Applies the power intent that was previously read in from power
  intent file(s)" and carries an important ordering warning: "You should not execute any
  command (such as `update_names` or `ungroup`) that can cause changes in the name of the
  design objects **before** you apply the power intent file(s). Otherwise, the
  `apply_power_intent` command may not find some design objects" (**Genus ComRef — Advanced
  Low Power**). The script is compliant: nothing between `elaborate` and
  `apply_power_intent` renames anything.
- `check_cpf` "Checks the validity of the CPF rules against the RTL of the design… If no low
  power rule check errors are detected, the command returns 1. If rule check errors are
  detected, the command returns 0. … To run this command you need to have access to
  Conformal Low Power" (**Genus ComRef — Advanced Low Power**). `-detail` "Provides a
  detailed report"; `-license string` "Specifies the Conformal license to be used for this
  command" — hence `lpgxl`.
- `commit_power_intent` "Inserts level-shifter logic and isolation logic as requested based
  on the rules specified in previously read in power intent file(s)" (**Genus ComRef —
  Advanced Low Power**). On this design it inserts nothing: observed `CPI-502` "No isolation
  rules defined", `CPI-503` "No level shifter rules defined", `CPI-517`/`CPI-518` both
  "0 … inserted". It is not a no-op though — it is what binds every instance to `PD_TOP`.

> **DIVERGENCE — `check_cpf` has a documented `-continue_on_error`, and the flow does not use it.**
> The manual lists `-continue_on_error`: "Allows the tool to continue when low power rule
> check errors are encountered" (**Genus ComRef — Advanced Low Power**, `check_cpf`). Instead,
> `config.tcl:51-67` renames `check_cpf` and wraps it in a Tcl `catch`.
> Observed on the baseline (log lines 1065-1074): `check_cpf` raises `RCLP-203`, and the
> wrapper prints `WARNING: check_cpf FAILED — continuing deliberately.` followed by
> `WARNING:   0` — the caught message is the literal string `0`, i.e. the command's return
> value, not a diagnostic. So the wrapper's second WARNING line carries no information.
> Whether `-continue_on_error` would have avoided the wrapper entirely is **untested** — no
> tool may be launched for this document, and `config.tcl`'s own note records that the
> adjacent remedy `clp_treat_errors_as_warnings` was tried and did *not* stop the raise. It
> is the obvious first experiment for whoever next has a Genus seat.

### 2.6 Preserving the pads (line 42)

```tcl
 42  set_dont_touch [get_cells -hierarchical -filter {name =~ "uPAD*"}]
```

`set_dont_touch` "Prevents the specified object from being modified during optimization.
However, the specified object can be moved during optimization" — and, importantly, "This
command does not work on unmapped or unresolved objects" (**Genus ComRef — SDC Commands**,
`genus_comref/sdc_commands.html`). The `uPAD*` instances are instances of library cells from
the TSMC IO liberty, which is loaded at line 22, so they are resolved at this point and the
command bites. Placing it *before* `syn_generic` is what keeps the pad ring out of
optimisation.

**Observed:** log line 1095 shows the command executing with no error and no warning.

### 2.7 Power-structure check (line 44)

```tcl
 44  check_power_structure -detail -license lpgxl > $LOG_DIR/syn_pow_check.log
```

"Verifies whether the low power cells in the design conform to the rules and specifications
in the loaded CPF file… To run this command you need to have access to Conformal Low Power"
(**Genus ComRef — Advanced Low Power**).

> **DIVERGENCE — the manual makes a stage selector mandatory; the script omits it.**
> The documented synopsis is
> ```
> check_power_structure [-design design] [-isolation] [-level_shifter] [-retention]
> [-all] [-lp_only] [-nwell_analysis]
> {-pre_synthesis | -post_synthesis | -post_pg} ...
> ```
> The braces (not brackets) around `{-pre_synthesis | -post_synthesis | -post_pg}` mark that
> group as required. The script passes none of them. **Observed:** the command ran anyway,
> took a Conformal license (`Using Conformal version $CDS_INSTALL/confrml/bin/lec.`), wrote
> `./.clp/RC.upf`, and produced a 112,105-byte `logs/syn_pow_check.log`. So either the tool
> defaults the stage or the manual's braces overstate the requirement. Either way the
> **flow is not saying which stage it is checking**, and the report's meaning depends on
> that. Worth pinning down with `-post_synthesis` (the script runs it after
> `commit_power_intent` but before `syn_generic`, so `-pre_synthesis` is arguably the honest
> label). This command also has its own `-continue_on_error` — "Allows the tool to continue
> when low power rule check errors are encountered. This is not a default option."

**Artefact:** `logs/syn_pow_check.log`. Its head is 38 × `1801_SUPPLY_CSN_MISSING_FOR_MACRO`
warnings — the macro PG pins the UPF never `connect_supply_net`s. Cross-referenced in
[11-known-issues](../11-known-issues.md).

### 2.8 Constraints and DFT (lines 47-52)

```tcl
 47  read_sdc $constraints_file
 ...
 50  if {$DFT == 1} {
 51      source ../scripts/dft_setup.tcl
 52  }
```

`$constraints_file` is `../inputs/constraints.sdc`. `DFT` is **0** in `config.tcl:123`, and
`scripts/dft_setup.tcl` **does not exist** in the repo. So this branch is unreachable, and
would fail immediately if `DFT` were flipped. Every other `DFT == 1` branch in the flow
(lines 61-64 and 83-90 here; `2_pnr_setup.tcl:33-35, 58-60`; `3_pnr_clock.tcl:36-38`) is
equally untested. Treat the whole scan path as unimplemented, not as an option.

**Observed at line 47:** `TIM-316` and `TIM-317` warnings — SDC from/to points on pad pins
that are not valid timing start/endpoints. Related to
[16-open-defects §5](../16-open-defects.md).

### 2.9 Effort and synthesis (lines 55-66)

```tcl
 55  set_db syn_generic_effort high
 56  set_db syn_map_effort high
 57
 58  syn_generic
 59  syn_map
 ...
 66  syn_opt
```

Both are documented root attributes, and their defaults matter:

| Attribute | Values | **Default** | Set here | Net effect |
|---|---|---|---|---|
| `syn_generic_effort` | `none low medium high express` | **medium** | `high` | real change |
| `syn_map_effort` | `none low medium high` | **high** | `high` | **no-op** |
| `syn_opt_effort` | `none low medium high extreme` | **high** | *not set* | default `high` |

(**Genus AttRef — Synthesis**, `genus_attref/synthesis.html`.) So of the two lines, only 55
changes anything. There is also a single `syn_global_effort` root attribute — default `none`
— which "overrides the individual settings of the `syn_generic_effort`, `syn_map_effort` and
`syn_opt_effort` attributes" if set; the flow does not use it, which is correct, because
setting it would silently override the per-phase values.

The three commands:

- `syn_generic` "Takes an elaborated and fully constrained design as input and synthesizes it
  into a netlist of generic gates by doing high-level RTL and datapath optimizations"
  (**Genus ComRef — Elaboration and Synthesis**). The same page recommends running
  `check_design` and `check_timing_intent` first — this flow runs neither.
- `syn_map` "Maps a design from generic gates to a technology library while optimizing for
  best performance, power and area", including "Selective ungrouping of modules… controlled
  via the `auto_ungroup` attribute". Line 34 is the commented-out
  `#set_db auto_ungroup none` that would turn ungrouping off; it is left off, so the netlist
  is heavily ungrouped. That is why post-P&R LEC must be flat — see
  [13-lec §Flat, not hierarchical](../13-lec.md).
- `syn_opt` "Takes a mapped design as input and incrementally optimizes timing, area and
  power. Without specifying the spatial or physical flow options, `syn_opt` will do pure
  logical optimization".

**Observed runtime split** (baseline log line numbers): `syn_generic` 1135→1871,
`syn_map` 1871→3895, `syn_opt` 3899→4499. `syn_map` dominates.

### 2.10 Reports (lines 69-72)

```tcl
 69  report_area   > $REPORT_DIR/syn_area.rep
 70  report_timing > $REPORT_DIR/syn_timing.rep
 71  report_gates  > $REPORT_DIR/syn_gates.rep
 72  report_power  > $REPORT_DIR/syn_power.rep
```

Four Genus reports redirected into `reports/`. All four are documented in **Genus ComRef —
Analysis** (`genus_comref/analysis.html`). `report_timing` with no options gives the single
worst path only. Contents and how to read them: [07-reading-reports §Genus reports](../07-reading-reports.md).

### 2.11 Netlist and power-intent writeout (lines 74-77)

```tcl
 74  write_hdl > $OUT_DIR/${block_name}_gate.v
 75  write_hdl -pg > $OUT_DIR/${block_name}_gate_power.v
 76  write_power_intent -cpf -design $block_name -base_name $OUT_DIR/${block_name}_gate
 77  write_power_intent -design $block_name -base_name $OUT_DIR/${block_name}_gate
```

`write_hdl` "Generates … A structural netlist using mapped logic"; `-pg` "Adds the power and
ground nets to the netlist, where PG pins, net connections have come through 1801, UPF files"
(**Genus ComRef — Input and Output**). So line 74 is the plain netlist and line 75 is the PG
netlist — and **line 75's output is the one P&R reads** (`2_pnr_setup.tcl:30`). Line 74's
output is what `make lec` proves against RTL. That split is the root of the LEC gap
documented in [13-lec](../13-lec.md).

`write_power_intent` "writes out an updated power intent file reflecting the changes in
either the IEEE 1801-2009 standard or in CPF format", with `[-1801 | -cpf]` defaulting to
`-1801` (**Genus ComRef — Advanced Low Power**). So line 76 emits CPF and line 77 emits UPF.

> **DIVERGENCE — `-base_name` silently gets a counter appended, and the flow depends on it.**
> The manual says only: "`-base_name string` — Specifies the path and basename for the
> generated file." Both lines pass the identical base name
> `../outputs/nanosoc_eth_chiplet_pads_gate`. **Observed** (baseline log 4600-4617):
> ```
> Written power intent information in ../outputs/nanosoc_eth_chiplet_pads_gate1.cpf
> Written power intent information in ../outputs/nanosoc_eth_chiplet_pads_gate2.upf
> ```
> Genus appended `1` and `2`. This is the same no-overwrite convention as its log files
> (`syn_logs.log`, `.log1`, `.log2`, …, which is why the Makefile's error hint globs
> `syn_logs.log*`), and it is not documented on the `-base_name` option. **It is
> load-bearing:** `2_pnr_setup.tcl:40` hardcodes `${block_name}_gate1.cpf`. Add a third
> `write_power_intent`, reorder these two lines, or re-run synthesis into a non-empty
> `outputs/`, and the number moves and stage 2 reads the wrong file or none. `-overwrite`
> ("Allows to overwrite any existing files") exists and is not used.

The same manual page explains *why* the CPF needs patching afterwards: "If there are any
errors or warnings given during `read_power_intent`, the power intent written out may not be
same as the power intent read", and "All unsupported commands and commands that are not
applicable to synthesis are written out as they were entered. All unsupported options of
supported commands are skipped." Genus is even blunter in the log:

```
Writing CPF for a design with 1801 power intent or writing 1801 for a design
withn CPF power intent is not suitable for production and is currently
unsupported. Output power intent file can be incomplete or corrupted.
```

followed by dozens of `Unable to translate command 'create_supply_net' … from 1801 to CPF
format.` The resulting `_gate1.cpf` is 730 bytes and, before patching, contains only
`create_power_domain -name PD_TOP -default`. See [§7.3](#73-cpf-patch) and
[04-power-plan §1](../04-power-plan.md).

### 2.12 SDF (line 79)

```tcl
 79  write_sdf -timescale ns > $OUT_DIR/${block_name}_gate.sdf
```

> **TRAP — `-timescale` does not do what the name suggests.** The manual: "`-timescale
> {ps | ns}` — Specifies a multiplier to the delay values used in the SDF file. **This
> option does not change the timescale setting of the SDF file.** The delay values are
> scaled, but the units are the same." (**Genus ComRef — Input and Output**, `write_sdf`.)
> So this line scales the numbers without relabelling them. If a downstream simulator reads
> this SDF assuming the header's units, it gets delays off by 1000×. Nothing in this repo
> currently consumes `_gate.sdf` (300 MB on the baseline), so no harm has been done — but do
> not assume it is correct if you start using it.

**Observed at this line:** `WSDF-104` — "Default value for `-setuphold` has changed from
`split` to `merge_always`. Specify `-setuphold split` to preserve the behavior of the
previous release." The flow does not specify it, so the new default applies.

### 2.13 The LEC dofile (line 81)

```tcl
 81  write_do_lec -revised_design $OUT_DIR/${block_name}_gate.v -no_lp -top ${block_name} -logfile $LOG_DIR/lec.log > lec.dofile
```

"Writes a script and verification information that can by used Conformal Logical Equivalence
Checking tool to compare the specified golden and revised designs" (**Genus ComRef — Input
and Output**). Options used:

- `-revised_design <file>` — the revised side is `outputs/…_gate.v`.
- **`-golden_design` is not passed, and its default is `rtl`** — "write_do_lec will access
  the `hdl_filelist` attribute to use the same set of files that were read into Genus".
- `-no_lp` — "Prevents verification of power intent information." Observed consequence:
  `CFM-649` "Skip writing LP related commands in the dofile. This might result in
  non-equivalence."

**Observed** (`CFM-2`, baseline log 4672-4673): "The composite dofile 'lec.dofile' includes
two compare operations: rtl-to-fv_map and fv_map-to-revised. The 'fv_map' netlist was
automatically written in the verification directory during the syn_map command."

That single log line is the proof behind the Makefile's `lec` caveat: the dofile chains
RTL → `fv_map` → `_gate.v` and **never reads `_pnr.v`**. See [§7.5](#75-the-lec-targets) and
[13-lec](../13-lec.md).

> **DIVERGENCE — the option is spelled `-log_file`, the script writes `-logfile`.**
> The documented syntax is `[-log_file file]`, described as "Specifies the name of the
> Conformal LEC logfile" (**Genus ComRef — Input and Output**, `write_do_lec`). The script
> passes `-logfile`. **Observed:** Genus accepted it silently (baseline log 4667, no
> complaint). This is presumably the same abbreviation/alias tolerance that makes `genus -f`
> work. It is not a bug today; it is a spelling that no manual sanctions, and it will break
> the day the parser tightens.

Note the redirect target: `> lec.dofile`, a **bare relative path**, so it lands in `work/` —
which is exactly where `make lec` looks (`Makefile:145`) and exactly what `make clean`
deletes.

### 2.14 DFT reports (lines 83-90)

Dead under `DFT == 0`. `report_scan_chains`, `report_scan_setup`, `report_scan_registers`,
`write_dft_abstract_model`, `write_dft_atpg_other_vendor -mentor`, `write_scandef` are all
documented in **Genus ComRef — DFT** (`genus_comref/dft.html`). The `_44pin` suffixes in the
filenames are hardcoded and are a leftover from a different design.

### 2.15 SDC, session, exit (lines 92-96)

```tcl
 92  write_sdc > $OUT_DIR/${block_name}_syn.sdc
 94  write_db ${block_name}_syn_session
 96  exit
```

- `write_sdc` writes the post-synthesis constraints (51,819 bytes). Nothing downstream reads
  it — P&R gets its constraints from the MMMC's `create_constraint_mode`, which points at
  `../inputs/constraints.sdc`. It is a debug artefact.
- `write_db` here is **Genus's** `write_db`, not Innovus's — different command, different
  manual (**Genus ComRef — Input and Output**). It writes a Genus session directory
  `work/nanosoc_eth_chiplet_pads_syn_session`, which `make syn_norun` can reload.
- `exit` is what makes the run unattended. Note the file has **no trailing newline** after
  `exit` — harmless in Tcl, but `cat` output will run into your prompt.

---

## 3. `2_pnr_setup.tcl` — Innovus, floorplan to placement

Full path: `ASIC/asic-flows/Cadence/2_pnr_setup.tcl` (70 lines).
Invoked by `make pnr_place` as `innovus -stylus -files <script>`, from `work/`.

### 3.1 Header (lines 1-13)

```tcl
  5  # run: innovus -stylus -f 2_pnr_setup.tcl
```

> **THE HEADER IS WRONG.** `-f` is not a valid Innovus argument in Stylus mode. The
> Stylus User Guide's own worked example is
> ```
> innovus -stylus -files run.tcl
> ```
> and the log excerpt that follows it shows `#@ Processing -files option` (**Stylus UG —
> Getting Started**, `UGcom/Getting_Started.html`). A grep of the *entire* installed Innovus
> documentation tree — both `TCRcom/` (Stylus) and `innovusTCR/`/`innovusUG/` (legacy) —
> finds **no occurrence of `innovus -f`** anywhere. Passing `-f` produces
> `**ERROR: (IMPSYT-468): Unknown argument -f`, a usage message, and **exit status 0**, so
> `make` records the stage as passed. This is the single most expensive mistake in this
> flow's history: three P&R stages "ran" in under a minute and the only symptom was a
> missing GDS hours later. The Makefile pins the correct form in one place —
> [§7.6](#76-innovus-innovus-stylus-files).
>
> The same wrong header is repeated verbatim in `3_pnr_clock.tcl:5` and `4_pnr_route.tcl:4`,
> both of which additionally name the **wrong script** (`2_pnr_setup.tcl`).

### 3.2 Config, CPU, banner (lines 14-17)

```tcl
 14  source ../scripts/config.tcl
 16  soclabs_setup_multi_cpu
 17  puts "Starting PnR Flow ..."
```

Same `config.tcl` as Genus reads — which is why anything tool-specific in that file must be
guarded (`config.tcl` documents this at length; an unguarded Genus-only attribute there fails
under Innovus with `IMPDBTCL-247` and takes the whole file down).

### 3.3 Global PG nets (lines 20-21)

```tcl
 20  set_db init_power_nets $power_nets
 21  set_db init_ground_nets $ground_nets
```

`$power_nets` = `{VDD VDDACC VDDIO}`, `$ground_nets` = `{VSS VSSIO}` (`config.tcl:125-126`).

These are `init` category root attributes: `init_power_nets` "Specifies the list of global
power nets used in the design", default `{}`; `init_ground_nets` likewise
(**Stylus TCR — init Category Attributes**, `TCRcom/init_Category_Attributes.html`).

They are set here — before `read_mmmc` — because that is the order `init_design` demands:
"You must use the following commands in the order shown below before calling `init_design`.
`set_db` to set various init root attributes as desired. **Normally `init_power_nets` and
`init_ground_nets` are set here.**" (**Stylus TCR — `init_design`**, `TCRcom/init_design.html`).
Setting them after `init_design` would have no effect on domain creation.

These two lines are why `PD_TOP` gets rows and why `connect_global_net` in
`power_plan.tcl` has something to bind to. `VDDACC` is declared but this design has no
accelerator domain; it is inherited from the toolkit's template.

### 3.4 MMMC (line 24)

```tcl
 24  read_mmmc ../scripts/${block_name}.mmmc
```

"Reads in the Multi-Mode, Multi-Corner (MMMC) file… When the `read_mmmc` command is run, the
MMMC file is read and processed. The majority of elements in the MMMC control file is saved
in the MMMC caching attributes. **Except for the library sets defined by the first
`set_analysis_view` command, no data is loaded into the database.**" (**Stylus TCR —
`read_mmmc`**, `TCRcom/read_mmmc.html`). The manual lists the mandatory minimum content —
one each of `create_library_set`, `create_rc_corner`, `create_timing_condition`,
`create_delay_corner`, `create_constraint_mode`, `create_analysis_view`, `set_analysis_view`
— and `scripts/nanosoc_eth_chiplet_pads.mmmc` satisfies all seven.

What it defines (grepped from the file): 3 library sets, 3 RC corners, 3 timing conditions,
4 delay corners, 1 constraint mode, **5 analysis views**, and

```
198  set_analysis_view -setup [list default_analysis_view_setup typical_analysis_view] \
                       -hold [list default_analysis_view_hold typical_analysis_view]
```

Only 3 of the 5 views are ever activated. `typical_analysis_view_setup` and
`typical_analysis_view_hold` (lines 193-194 of the MMMC) are defined and never referenced by
anything in the flow. That is dead configuration, and it is easy to mistake for the views
that `4_pnr_route.tcl:48` switches to (it uses plain `typical_analysis_view`).

### 3.5 Physical libraries (line 27)

```tcl
 27  read_physical -lef $lef_file_list
```

"Reads the physical library information… Both LEF and OA are supported, but not
simultaneously. **If `-lef` is used, the technology LEF must be first specified.** …This
command is optional for Synthesis and STA, but is required for Implementation."
(**Stylus TCR — `read_physical`**, `TCRcom/read_physical.html`.)

`$lef_file_list` (`config.tcl:173-186`) puts `$TECH_LEF` first, satisfying that rule, then
`tcbn65lp` std cells, the TSMC bond-pad LEF, the **patched IO driver LEF**, and the
eight macro LEFs. That LEF — the TSMC IO LEF with three added `USE POWER ;` /
`USE GROUND ;` lines, generated at build time from the read-only PDK into
`ASIC/tech_wrappers/tsmc65/generated/` rather than committed — is documented in `config.tcl` and
[04-power-plan §2.1](../04-power-plan.md). Without it, `connect_global_net -type pg_pin`
cannot match `VDDPST`/`VSSPST` and the IO supplies get routed as ordinary signals.

> **NOTE — the documented option is `-lefs`, plural.** The manual's synopsis and both of its
> examples use `-lefs`; `read_physical -lef` is what the script writes. Innovus's Stylus
> parser accepts unambiguous prefixes, and `-lef` is a prefix of `-lefs` only, so this works —
> confirmed by the fact that every run has loaded its LEFs. Cosmetic, but it means grepping
> the manual for the exact string in the script finds nothing.

Also note the manual's constraint: "This option can only be used before `init_design` or
`read_db`." The script complies. After `init_design`, adding LEFs requires `-add_lefs`.

### 3.6 Netlist (line 30) and scan DEF (lines 33-35)

```tcl
 30  read_netlist $OUT_DIR/${block_name}_gate_power.v
 33  if {$DFT == 1} {
 34      read_def $OUT_DIR/$block_name.def
 35  }
```

`read_netlist` "Reads in a Verilog structural netlist… During the Design step, the design is
loaded into the database with `read_netlist`. After issuing this command, the database
objects are populated… Full error checking is performed on the design details. This includes,
but is not limited to, unresolved references, port mismatches, and empty modules."
(**Stylus TCR — `read_netlist`**, `TCRcom/read_netlist.html`.)

Note it reads `_gate_power.v` — the **PG** netlist from `1_synthesis.tcl:75`, not `_gate.v`.

> **DEAD CODE, and it would not work.** The `read_def` at line 34 is guarded on `DFT == 1`,
> which is never true. If it were, it would fire **before** `init_design` (line 38), and the
> manual says "`read_def` can be used at any step **after importing a design**"
> (**Stylus TCR — `read_def`**, `TCRcom/read_def.html`). The netlist is read but the design
> is not initialised at that point. The documented way to load a scan DEF at this stage is
> `read_netlist -def <file>`. Untestable here (no tool launches), so marked **inferred**.

### 3.7 `init_design` (line 38)

```tcl
 38  init_design
```

The single most consequential line in the stage. "Initializes the database and ensures that
the tool is ready for full execution… `init_design` to step through the defined MMMC objects,
the netlist objects, and the power intent data to build up the full representation of the
design." It also, per the same page:

- "Initializes the default bounding box of square size with 70% utilization"
- "Creates default rows, the site of row depends on the height of the cell used in the netlist"
- "Creates track in the box based on the tech LEF"

and runs four sub-steps: Power Domain Creation → Bind Power Domains to Timing Conditions →
Constraint Loading (this is when the SDC is actually read) → Active View Setting
(**Stylus TCR — `init_design`**).

Afterwards, the door closes: "Reading new design data (netlist) and new physical data
(LEF/OA) incremental updates is not allowed. After the first `init_design` is completed,
these steps are effectively disabled."

The default 70%-utilisation square box it creates is immediately thrown away by
`floorplan.tcl`, which sets the real 1600 × 2000 µm die — see [03-floorplan](../03-floorplan.md).

### 3.8 Power intent, again (lines 40-42)

```tcl
 40  read_power_intent -cpf $OUT_DIR/${block_name}_gate1.cpf
 42  commit_power_intent
```

`read_power_intent` "Reads-in power intent file and do syntax check", `-cpf` selects CPF
format (**Stylus TCR — `read_power_intent`**, `TCRcom/read_power_intent.html`).
`commit_power_intent` "Commits IEEE1801 power intent specifications for the design for use in
verification and implementation" (**Stylus TCR — `commit_power_intent`**).

Two things about these two lines:

> **DIVERGENCE — the manual puts `read_power_intent` BEFORE `init_design`; this script puts it after.**
> The `init_design` page's ordered prerequisite list is:
> `set_db` init attributes → `read_mmmc` → `read_physical` → `read_netlist` →
> `read_power_intent` ("The files are read in and various error checks are done, but **no
> power_domain objects are created until `init_design` is called**") → `init_design`. Its
> worked example puts `read_power_intent -cpf design.cpf` on the line above `init_design`.
> This script inverts that: `init_design` at 38, `read_power_intent` at 40,
> `commit_power_intent` at 42. It works — every run since the flow existed has done it this
> way — but it means `init_design`'s "Power Domain Creation" sub-step ran with no power
> intent at all, and the domain is created later by `commit_power_intent` instead. Whether
> that is behaviourally identical is **not established** and cannot be tested here. It is a
> plausible contributor to the `PD_TOP` supply-net weirdness in
> [04-power-plan §1](../04-power-plan.md), and worth a controlled experiment.

**Row rebuild.** `commit_power_intent`'s `-keep_rows` option exists because "By default, rows
are recreated based on the power domain information. The new rows might not match the
original rows." The script does not pass `-keep_rows` — correctly, because `floorplan.tcl`
has not run yet, so there are no rows worth keeping. Move this call after the floorplan and
you silently lose the row structure.

**This is the line that reads the patched CPF.** `${block_name}_gate1.cpf` — the `1` comes
from Genus's counter ([§2.11](#211-netlist-and-power-intent-writeout-lines-74-77)), and the
`create_power_nets` / `create_ground_nets` / `update_power_domain` statements in it come from
`make cpf-patch` ([§7.3](#73-cpf-patch)). Without the patch this line loads a domain with no
supply nets and every filler pass later dies with `IMPSP-5110`.

### 3.9 Process node (line 44)

```tcl
 44  set_db design_process_node $process_node
```

`$process_node` is `65` (`config.tcl:3`). The attribute: "Specifies the process technology
value to set for all the applications. Units in nanometers (nm). **Default: 90**"
(**Stylus TCR — design Category Attributes**, `TCRcom/design_Category_Attributes.html`).

So this is a real change from the default. But note the position: it is set **after**
`init_design`, so everything `init_design` did — row creation, track creation, constraint
loading — used the 90 nm default. Whether that matters is **not established**. Note also that
`preplace.tcl:2` sets the identical attribute again (`set_db design_process_node 65`), so the
value is set twice by two different files, one shared and one project-owned.

There is a separate, more modern `design_tech_node` enum attribute on the same page which
"is normally automatically set by `read_physical` while loading the LEF technology". Its
value list is all FinFET nodes (N12…N3, S11…S3) — nothing for 65 nm — so
`design_process_node` is the right knob here.

### 3.10 Floorplan and power plan (lines 46-47)

```tcl
 46  source ../scripts/floorplan.tcl
 47  source ../scripts/power_plan.tcl
```

Control passes to the project. Die/core box, IO placement from
`nanosoc_eth_chiplet_pads.io`, IO fillers, macro placement, halos →
[03-floorplan](../03-floorplan.md). Global net connections, core rings, M8/M9/M5 stripes,
`route_special`, endcaps → [04-power-plan](../04-power-plan.md). Not repeated here.

### 3.11 Reporting helpers and the pre-place snapshot (lines 49-52)

```tcl
 49  source $env(SOCLABS_ASIC_FLOW_DIR)/Cadence/procs.tcl
 52  report_intermediate_step 00_pre_place $REPORT_DIR
```

The only use of `SOCLABS_ASIC_FLOW_DIR` inside a script. See
[§1.5](#15-where-control-passes-between-the-toolkit-and-the-project) and
[§6](#6-procstcl-the-reporting-helpers).

`00_pre_place` is taken **after** the power plan, so it is a floorplanned-but-unplaced
timing snapshot. It is the baseline against which `01_place` is read.

### 3.12 Placement (lines 54-62)

```tcl
 54  source ../scripts/preplace.tcl
 56  place_design
 58  if {$DFT == 1} {
 59      reorder_scan
 60  }
 62  report_end_step 01_place $REPORT_DIR
```

`preplace.tcl` (11 lines) sets five attributes; all are `place`-category root attributes
settable via `set_db` as the `place_design` page directs:

| Line | Attribute | Value | Note |
|---|---|---|---|
| 2 | `design_process_node` | 65 | duplicate of `2_pnr_setup.tcl:44` |
| 3 | `place_global_cong_effort` | `auto` | |
| 4 | `place_global_timing_effort` | `high` | |
| 7 | `place_global_uniform_density` | `true` | |
| 8 | `place_detail_legalization_inst_gap` | `2` | |
| 11 | `place_design_floorplan_mode` | `false` | named on the `place_design` page as the prototyping switch |

`place_design` "Places standard cells based on the global settings for placement, RC
extraction, timing analysis, and early global routing. It also relieves the congestion and
reorders the scan cells… **By default, `place_design` performs timing-driven placement with
scan reordering**, except during prototyping… If there are no timing constraints,
`place_design` assumes non-timing-driven mode." (**Stylus TCR — `place_design`**,
`TCRcom/place_design.html`.) Constraints are loaded (by `init_design`), so this is
timing-driven.

> **DEAD CODE — `reorder_scan` would not work as written either.** Guarded on `DFT == 1`.
> The manual: "Use this command after running placement **with the ignore scan connection
> attribute (`place_global_ignore_scan true`)**, and after specifying the scan chain or
> loading scan chain information in the DEF or TDF files" (**Stylus TCR — `reorder_scan`**,
> `TCRcom/reorder_scan.html`). Neither precondition is set anywhere in this flow. And since
> `place_design` already reorders scan by default, calling `reorder_scan` straight after it
> is redundant unless that default was disabled. **Inferred**, untestable.

**Artefacts:** `reports/timing_summary_01_place.rep` (the `status` probe for the place
stage), `timing_01_place_{early,late}.rep`, `power_01_place.rep`, `qor_01_place.rep`.
Measured from `qor_01_place.rep`: 184,372 instances, 1,609,582 µm², 80.67 % density,
`place_design` wall time 0:17:49.

### 3.13 Post-place and DB write (lines 64-68)

```tcl
 64  source ../scripts/postplace.tcl
 66  write_db $block_name
 68  exit
```

`postplace.tcl` is four lines:

```tcl
  2  write_sdf design.sdf -ideal_clock_network
  3  set_db add_tieoffs_max_fanout 10
  4  add_tieoffs -lib_cell {TIEL TIEH} -prefix LTIE
```

- The `write_sdf` writes **494 MB** into `work/design.sdf` with an ideal clock network — a
  pre-CTS SDF that nothing in this repo consumes, deleted by `make clean`.
- `add_tieoffs` inserts the TIEL/TIEH cells for constant-driven pins, capped at fanout 10.
  Detail in [05-place-cts-route](../05-place-cts-route.md).

`write_db $block_name` is the hand-off. `exit` closes the seat.

---

## 4. `3_pnr_clock.tcl` — Innovus, CTS

Full path: `ASIC/asic-flows/Cadence/3_pnr_clock.tcl` (45 lines).
Invoked by `make pnr_cts`.

### 4.1 Header (lines 1-13)

```tcl
  2  # Place and route setup script for Cadence Innovus
  5  # run: innovus -stylus -f 2_pnr_setup.tcl
```

> **HEADER COMMENT IS WRONG TWICE.** Line 2 calls this a "setup script" — copied from
> stage 2; this is the CTS stage. Line 5 has both the invalid `-f`
> ([§3.1](#31-header-lines-1-13)) **and the wrong filename** — it names `2_pnr_setup.tcl`.
> Copy `-f` from here and you will not even run the script you think you are running.
> `4_pnr_route.tcl:4` repeats the identical error.

### 4.2 Load and helpers (lines 14-22)

```tcl
 14  source ../scripts/config.tcl
 16  soclabs_setup_multi_cpu
 17  puts "Starting CTS Flow ..."
 19  read_db $block_name
 20  source $env(SOCLABS_ASIC_FLOW_DIR)/Cadence/procs.tcl
 22  source ../scripts/cts_setup.tcl
```

`read_db $block_name` picks up exactly what stage 2 wrote. `config.tcl` is re-sourced first
because `$block_name` and the library paths live there — this is also why `make pnr_setup`
(bare `innovus -stylus`) cannot `read_db` and `make gui` can
([§7.8](#78-gui-and-pnr_setup)).

`cts_setup.tcl` does three things, in this order:

1. **Line 9: `write_db ${block_name}_placed`** — the post-place snapshot, taken here rather
   than in stage 2 so that it is guaranteed to be the clean hand-off state.
2. **Line 24: `set_db cts_delay_cells {DEL*}`**. Lines 20 and 22
   (`cts_buffer_cells`/`cts_inverter_cells`) are commented out **deliberately**; the file's
   own header explains that constraining CCOpt's cell choice is a physical change to evaluate
   on its own. Measured for reference in that header: the clock tree used 41,228 `CKBD0`,
   5,648 `CKND0`, 3,126 `CKBD1` and 3,290 `BUFFD1`. The Stylus UG's CTS quick-start does
   recommend setting these (`set_db cts_buffer_cells {…}` / `cts_inverter_cells {…}`,
   **Stylus UG — Clock Tree Synthesis**, `UGcom/Clock_Tree_Synthesis.html`), so this is a
   knowing deviation, not an oversight.
3. **Line 72: `set_db timing_analysis_type ocv`** — moved here from `route_setup.tcl`. The
   40-line comment above it is the diagnosis of the hold defect: enabling OCV *after* ccopt
   left the capture side of every hold check with no `-max` source latency. Full write-up in
   [16-open-defects §1](../16-open-defects.md). Do not move it back.

### 4.3 Clock tree specification (line 25)

```tcl
 25  create_clock_tree_spec -out_file design_clk.spec
```

"Creates a clock tree network with associated skew groups and other clock tree synthesis
(CTS) configuration settings… When you run this command, one skew group will be created for
each SDC clock in each constraint mode." And on `-out_file`: "Writes this clock tree
specification script file in Stylus Common UI format. This is an optional parameter…
**The file is not executed.** To execute the file, run the following:
`create_clock_tree_spec -out_file spec.tcl` / `source spec.tcl`" (**Stylus TCR —
`create_clock_tree_spec`**, `TCRcom/create_clock_tree_spec.html`).

The User Guide is even plainer: "To write the specification to a file, **instead of just
applying it immediately in memory**, add the `-out_file` parameter. This example writes the
specification to a file and then loads the specification: `create_clock_tree_spec -out_file
ccopt.spec` / `source ccopt.spec`" (**Stylus UG — Clock Tree Synthesis**), and its
quick-start shows the three-line idiom with the second and third lines commented out:

```
create_clock_tree_spec
#create_clock_tree_spec -out_file ccopt.spec
#source ccopt.spec
```

> **DIVERGENCE — the spec is written and never loaded, so `ccopt_design` regenerates it.**
> The script uses `-out_file` and does **not** `source` the result. Per the manual, the
> in-memory specification is therefore not created by this line. **Observed** in
> `work/innovus.log3`:
> ```
> 1087  @file 25: create_clock_tree_spec -out_file design_clk.spec
> ...
> 10361 (ccopt_design): CTS Engine: auto. Used Spec: CCOPT spec from create_ccopt_clock_tree_spec.
> 10362 (ccopt_design): create_ccopt_clock_tree_spec
> 10363 Creating clock tree spec for modes (timing configs): default_constraint_mode
> ```
> — i.e. `ccopt_design` ran the spec creation **a second time**, internally, because nothing
> had been loaded. The 1.9 MB `work/design_clk.spec` on disk is therefore a *documentation
> artefact only*; the tree that was actually built came from ccopt's own regeneration.
>
> Practical consequences: (a) the spec-creation work is done twice, once wasted;
> (b) if you hand-edit `design_clk.spec`, **nothing reads it** — a real trap, and the UG
> notes "It is not recommended to edit the specification file generated by the
> `create_clock_tree_spec -out_file filename`" anyway; (c) the file *is* still useful,
> because "The specification file that is generated records the reasons for the constraint
> settings… In case the `-out_file` parameter is not specified, no information about the
> reasons for constraint settings will be stored."
>
> If the intent is to inspect *and* apply, add `source design_clk.spec` on line 26. If the
> intent is only to inspect, the current form is defensible but should say so.

**Observed warnings at this line** (`innovus.log3:1118-1125`), all worth knowing:
`IMPCCOPT-2248` ×3 — "CCOpt does not support module port clocks" for `QSPI_SCLK`,
`mii_rx_clk`, `mii_tx_clk`; `IMPCCOPT-4144` ×2 — SDC clocks `D2D_TX_CLK_0` and `QSPI_SCLK_o`
sourced on input pins.

### 4.4 CTS and post-CTS optimisation (lines 28-40)

```tcl
 28  ccopt_design
 30  report_intermediate_step 02_cts $REPORT_DIR
 33  opt_design -post_cts
 34  opt_design -post_cts -hold
 36  if {$DFT == 1} {
 37      reorder_scan -clock_aware true
 38  }
 40  report_end_step 03_cts_opt $REPORT_DIR
```

- `ccopt_design` "Performs clock concurrent optimization (CCOpt) on the current loaded design
  in Innovus. CCOpt optimizes both the clock tree and the datapath to meet global timing
  constraints" (**Stylus TCR — `ccopt_design`**, `TCRcom/ccopt_design.html`). It is called
  bare — no `-report_dir`, so its own timing reports default to `./timingReports`, i.e.
  `work/timingReports/`, which exists on disk and which nothing else in the flow reads.
  `-check_cts_config` ("Checks that all the prerequisites for running clock tree synthesis
  are fulfilled without actually doing CTS") is a cheap sanity gate this flow does not use.
- `opt_design -post_cts` "Performs timing optimization on a design whose clock tree has been
  created. By default, `-post_cts` repairs design rule violations and setup violations."
  `opt_design -post_cts -hold` adds "Corrects hold violations" (**Stylus TCR —
  `opt_design`**, `TCRcom/opt_design.html`). Two separate calls, setup then hold — the
  conventional order.
- The `-hold` documentation carries a note this flow depends on: "You need to use the
  `add_fillers_cells` attribute to identify the filler cells. The `opt_design` command will
  remove filler cells that have been identified with the `add_fillers_cells` attribute at the
  beginning of optimization and add them back at the end." At this point in the flow no
  fillers exist yet, so nothing is removed. That is by design — see
  [06-fill-antenna-bondpads §2](../06-fill-antenna-bondpads.md).

Note the asymmetry with stage 4, which runs **only** `opt_design -post_route -hold` and never
a plain `-post_route`. Discussed in [§5.6](#56-post-route-optimisation-lines-31-35).

**Artefacts:** `reports/timing_summary_02_cts.rep`,
`reports/timing_summary_03_cts_opt.rep` (**the `pnr_cts` target's assertion**),
`timing_0{2,3}_*_{early,late}.rep`, `power_03_cts_opt.rep`, `qor_03_cts_opt.rep`,
`work/nanosoc_eth_chiplet_pads_placed/`, `work/design_clk.spec`, `work/timingReports/`.

### 4.5 Write and exit (lines 42-44)

```tcl
 42  write_db $block_name
 44  exit
```

Overwrites the post-place DB with the post-CTS state. The `_placed` snapshot from
`cts_setup.tcl:9` is what makes that non-destructive.

---

## 5. `4_pnr_route.tcl` — Innovus, route to GDSII

Full path: `ASIC/asic-flows/Cadence/4_pnr_route.tcl` (84 lines).
Invoked by `make pnr_route` as
`env -u CALIBRE_HOME innovus -stylus -files <script>`.
This is the stage that emits the GDSII, and the longest — 2 to 3.5 hours.

### 5.1 Header (lines 1-12)

```tcl
  1  # Place and route setup script for Cadence Innovus
  4  # run: innovus -stylus -f 2_pnr_setup.tcl
 12  #-----------------------------------------------------------------------------
```

> **HEADER COMMENT ERRORS, THREE OF THEM.** (i) Line 1 is missing the opening
> `#---…` banner rule that the other three scripts have — the block is bottom-terminated
> only. (ii) Line 1 calls this a "setup script"; it is the route/stream stage. (iii) Line 4
> repeats the invalid `-f` **and** the wrong filename. See [§3.1](#31-header-lines-1-13).
> And at line 16, `puts "Starting CTS Flow ..."` — copied from stage 3; this stage is not CTS.

### 5.2 Load and helpers (lines 13-19)

```tcl
 13  source ../scripts/config.tcl
 15  soclabs_setup_multi_cpu
 16  puts "Starting CTS Flow ..."
 18  read_db $block_name
 19  source $env(SOCLABS_ASIC_FLOW_DIR)/Cadence/procs.tcl
```

Identical pattern to stage 3.

### 5.3 The Calibre Tcl source (lines 21-23)

```tcl
 21  if {[info exists ::env(CALIBRE_HOME)]} {
 22      source [file join $::env(CALIBRE_HOME) shared pkgs icv tools queryenc cal_enc.tcl]
 23  }
```

Sources Mentor's query-encryption Tcl into the Innovus interpreter, which is what lets
`calibre` be driven from inside the session.

> **BROKEN ON THIS SITE, AND SUPPRESSED BY THE MAKEFILE.** `CALIBRE_HOME` is always set here
> (`<mentor install>/calibre`), so the guard always passes, and the `source` then fails with
> `IMPSE-110 … can't find package Tk 8.0`. The Makefile therefore runs this stage under
> `env -u CALIBRE_HOME` ([§7.7](#77-the-three-pr-stage-targets)). Fixed project-side rather
> than by editing the shared submodule. Full account in
> [12-calibre-drc §Why it never worked](../12-calibre-drc.md).

### 5.4 Route setup (line 26)

```tcl
 26  source ../scripts/route_setup.tcl
```

`route_setup.tcl` (45 lines, mostly comment) does four things:

| Line | Statement | What it is |
|---|---|---|
| 12 | `write_db ${block_name}_cts` | the **post-CTS snapshot** (57 MB) |
| 15 | `set_route_attributes -nets clk -preferred_extra_space_tracks 2` | extra spacing on the main clock net |
| 18 | `set_db route_design_detail_use_multi_cut_via_effort medium` | multi-cut via effort |
| 21 | `set_db route_design_with_timing_driven 1` | timing-driven routing |
| 24 | `set_db route_design_with_si_driven 1` | SI-driven routing |

The last two are exactly the two attributes the `route_design` page names: "To turn on
timing-driven routing, run the following route category attribute before running
`route_design`: `set_db route_design_with_timing_driven 1`. To turn on SI-driven routing:
`set_db route_design_with_si_driven 1`" (**Stylus TCR — `route_design`**,
`TCRcom/route_design.html`). The same page adds that the settings are persisted: "the
software stores the mode settings in the `.mode` file. If you restore the design and run
`route_design` again, it honors these settings."

> **REDUNDANT-BUT-HARMLESS.** The same page also says `route_design` "is a super command that
> handles the setting of NanoRoute variables so that it is run in timing-driven mode then
> sets them back postRoute. **It runs SMART routing by default; that is, it runs in both
> timing- and signal integrity-driven mode by default.**" So lines 21 and 24 restate the
> default for `route_design`. They are not pointless — the manual notes the *other* routing
> commands are not timing- or SI-driven by default, and the persisted `.mode` file makes the
> intent explicit for anyone resuming from the DB.

Two deliberate absences in this file, both documented in its own header: OCV is **not** set
here (moved to `cts_setup.tcl`, see [§4.2](#42-load-and-helpers-lines-14-22)), and
`filler.tcl` is **not** sourced here (moved to `place_bondpads.tcl`, see
[§5.7](#57-first-db-write-fillers-and-bond-pads-lines-37-39)).

### 5.5 Routing (line 29)

```tcl
 29  route_design -global_detail
```

"Runs routing or postroute via or wire optimization using the NanoRoute router. If you
specify this command without any arguments, it runs global and detailed routing."
`-global_detail`: "Runs timing-driven and SI-driven global and detailed routing.
**Note: `-global_detail` is the default value for this command.**" (**Stylus TCR —
`route_design`**.) So the flag is explicit-but-default. Fine.

The page also notes `route_design` "runs a placement check prior to routing and displays a
warning message if the placement is not clean", and recommends `check_design -type route`
beforehand — which this flow does not run.

### 5.6 Post-route optimisation (lines 31-35)

```tcl
 31  report_intermediate_step 04_route $REPORT_DIR
 33  opt_design -post_route -hold
 35  report_end_step 05_route_opt $REPORT_DIR
```

`opt_design -post_route`: "Performs timing optimization on a design whose routing is
complete. By default, `-post_route` repairs design rule violations, glitch Violations and
setup violations on Base & SI Delay." `-hold`: "Corrects hold violations."
(**Stylus TCR — `opt_design`**.)

> **ASYMMETRY WORTH KNOWING — there is no plain `opt_design -post_route`.** Stage 3 runs
> `opt_design -post_cts` and then `opt_design -post_cts -hold` (two passes, setup then hold).
> Stage 4 runs **only** the `-hold` form. Per the manual, `-post_route -hold` still repairs
> DRVs and setup as part of `-post_route`'s defaults, so it is not that setup is skipped —
> but it is a single combined pass rather than the staged one used post-CTS, and it is the
> pass that dominates the stage's runtime. This is where the ~45,700 CTS/opt/hold-repair
> instances and the surviving DRV violations come from; see
> [05-place-cts-route §7](../05-place-cts-route.md) and
> [16-open-defects §2](../16-open-defects.md).

### 5.7 First DB write, fillers and bond pads (lines 37-39)

```tcl
 37  write_db $block_name
 39  source ../scripts/place_bondpads.tcl
```

The DB is written **before** fillers and bond pads, then again at line 73 after everything.
So a crash between the two leaves a routed, optimised, unfilled DB — recoverable.

`place_bondpads.tcl:29` sources `filler.tcl` first, then creates the `PAD70GU`/`PAD70NU`
staggered ring. The ordering is load-bearing and both files say so at length: filler must run
**after** `opt_design -post_route -hold` so that `-check_drc`/`-fix_drc` has real routing and
the ANTENNA diodes see real antennas, and hold repair is not carving buffers out of already
filled rows. Full treatment, including the `IMPSP-9082` / `IMPSP-5217` finding, in
[06-fill-antenna-bondpads](../06-fill-antenna-bondpads.md).

### 5.8 The four checks (lines 41-44)

```tcl
 41  check_drc               -out_file $REPORT_DIR/${block_name}_imp_drc.rep
 42  check_filler            -out_file $REPORT_DIR/${block_name}_imp_filler.rep
 43  check_connectivity      -out_file $REPORT_DIR/${block_name}_imp_connectivity.rep
 44  check_process_antenna   -out_file $REPORT_DIR/${block_name}_imp_antenna.rep
```

All four are Stylus commands with per-command pages:

- `check_drc` "Checks for DRC violations and creates violation markers in the design database
  that can be seen on the GUI and browsed with the Violation Browser… **The `check_drc`
  command checks only the placed instances. It skips checking the DRC for unplaced
  instances.**" (**Stylus TCR — `check_drc`**, `TCRcom/check_drc.html`). No `-limit`, so no
  cap on markers; no `-check_only`, so everything.
- `check_filler` "Checks for locations that are missing filler cells, **after adding the
  cells with the `add_fillers` command**. … If you run this command without any parameters,
  it reports the total number of sites in the core area that are missing filler cells."
  (**Stylus TCR — `check_filler`**, `TCRcom/check_filler.html`.) The "after `add_fillers`"
  clause is why line 42 must come after line 39.
- `check_connectivity` — run bare apart from `-out_file`, so the default `-type all` applies
  and both regular and special nets are checked. This is the report that carries the 329 PG
  opens in [11-known-issues §a](../11-known-issues.md) and
  [15-pg-opens-analysis](../15-pg-opens-analysis.md).
- `check_process_antenna` "Verifies process antenna effect (PAE) and maximum floating area
  violations. **Before running this command, make sure that process antenna or maximum
  floating area keywords are specified in the LEF file and the signal nets are routed.**"
  (**Stylus TCR — `check_process_antenna`**, `TCRcom/check_process_antenna.html`.) Run
  without `-detailed`, so the report is summary-level.

Reading all four: [07-reading-reports](../07-reading-reports.md).

### 5.9 The timing report block (lines 46-56)

```tcl
 46  report_timing -output_format gtd -max_paths 10000 -path_exceptions all -early > timing_full_default_early.mtarpt
 47  report_timing -output_format gtd -max_paths 10000 -path_exceptions all -late  > timing_full_default_late.mtarpt
 48  set_analysis_view -setup [list typical_analysis_view] -hold [list typical_analysis_view]
 49  report_timing -late  > $REPORT_DIR/${block_name}_imp_timing_typical_late.rep
 50  report_timing -early > $REPORT_DIR/${block_name}_imp_timing_typical_early.rep
 51  report_timing -output_format gtd -max_paths 10000 -path_exceptions all -early > timing_full_typical_early.mtarpt
 52  report_timing -output_format gtd -max_paths 10000 -path_exceptions all -late  > timing_full_typical_late.mtarpt
 53
 54  set_analysis_view -setup [list default_analysis_view_setup typical_analysis_view] -hold [list default_analysis_view_hold typical_analysis_view]
 55  report_timing -late  > $REPORT_DIR/${block_name}_imp_timing_late.rep
 56  report_timing -early > $REPORT_DIR/${block_name}_imp_timing_early.rep
```

Options, all from **Stylus TCR — `report_timing`** (`TCRcom/report_timing.html`):

- `-early | -late` — "Generates the timing report for early paths (hold checks) or late paths
  (setup checks). **Default: -late**".
- `-max_paths integer` — "Reports the specified number of worst paths in the design,
  regardless of the endpoint. This is useful, but **can be time consuming if a large number
  of paths are requested**. **Default: worst path**". 10,000 is a large number.
- `-output_format {text | csv | gtd}` — "Generates detailed timing report in machine-readable
  format."
- `-path_exceptions {applied | ignored | all}` — "Includes information of path exceptions
  applied and considered for the reported path."

`set_analysis_view` "Defines the analysis views to use for setup and hold analysis and
optimization… **When the `set_analysis_view` command is issued, it will cause a full timing
reset. During a timing reset, all the interconnect parasitics, delays, and timing slacks will
be recalculated.**" (**Stylus TCR — `set_analysis_view`**, `TCRcom/set_analysis_view.html`.)

> **COST NOTE — two full timing resets, and 853 MB of reports nobody reads.**
> Lines 48 and 54 each trigger a complete re-timing of a routed, extracted, ~230 k-instance
> design, at the very end of a multi-hour stage. That is deliberate — the flow wants the
> typical-corner numbers and then wants the multi-view state restored before `write_db` — but
> it is not free and it is not commented.
>
> The four `.mtarpt` files are written with **bare relative paths**, so they land in `work/`
> rather than `reports/`. Measured on the 2026-08-05 baseline: 100 MB + 378 MB + 100 MB +
> 274 MB = **853 MB**, and `make clean` deletes all of it. If these are wanted, redirect them
> into `$REPORT_DIR`; if they are not, drop the four lines and save both the disk and the
> `-max_paths 10000` runtime.
>
> Also note line 54 restores the **same** view set the MMMC's own `set_analysis_view`
> established (`nanosoc_eth_chiplet_pads.mmmc:198`) — so the final DB is saved in the
> original multi-view state, which is correct and easy to break.

### 5.10 The dead `GDSFILENAME` assignment (line 58)

```tcl
 58  set GDSFILENAME $OUT_DIR/${block_name}.gds
```

> **DEAD, AND THE CAUSE OF A LONG-STANDING FAILURE.** Nothing reads this variable.
> `write_stream` on line 60 uses the literal path, not `$GDSFILENAME`. Its only intended
> consumer was the `exec calibre` at line 76 — but the TSMC deck's
> `LAYOUT PATH "GDSFILENAME"` is a **literal SVRF placeholder string**, not a variable
> reference, so a Tcl variable of that name is invisible to it. Calibre therefore looked for
> a file called literally `GDSFILENAME` and died. That is why the in-flow Calibre step has
> never produced a result in any run of this design. Full account in
> [12-calibre-drc](../12-calibre-drc.md); the working entry point is `make drc`
> ([§7.9](#79-calibre-drc-and-lvs-targets)).

### 5.11 GDSII stream-out (lines 60-64)

```tcl
 60  write_stream $OUT_DIR/${block_name}.gds \
 61      -map_file $TSMC_65_HOME/CMOS/util/lef/PRTF_EDI_65nm_<rev>/PR_tech/Cadence/GdsOutMap/PRTF_EDI_N65_gdsout_6X1Z1U.<rev>.map \
 62      -lib_name DesignLib \
 63      -merge $gds_merge_list\
 64      -output_macros -unit 1000 -mode all
```

"Creates a GDSII Stream file of the current database. Writes a summary of errors and warnings
to the log file. You can use the `write_stream` command after the design is placed, but is
most commonly used only after the design is routed" (**Stylus TCR — `write_stream`**,
`TCRcom/write_stream.html`). Option by option:

- `-map_file` — "Specifies the file used for layer mapping. **This file is required for
  successful stream out**, and is read by the next tool used in the design flow." Hardcoded
  to the TSMC PDK map. Note this is the one absolute PDK path baked into a *shared* script
  rather than into `config.tcl`; a design on a different PDK must edit the submodule.
- `-lib_name DesignLib` — "Specifies the library to convert to GDSII Stream format.
  **Default: DesignLib**". So this is the default, stated explicitly.
- `-merge $gds_merge_list` — "Specifies a single file or list of files to merge. Checks all
  merged files for name collisions, and generates a warning if any names are changed."
  `$gds_merge_list` (`config.tcl:198-207`) is exactly **8 macro GDS2 files**: `rf_32k`,
  `rf_16k`, `rf_08k`, `rf_01k`, `rom_via`, `eth_rom_via`, `flash_cache_data`,
  `flash_cache_tag`. **Nothing else.** Standard cells, IO drivers and bond pads are not
  merged, because this site's PDK ships LEF and liberty but no GDS for them. That is the
  "the GDS is not self-contained" point in [00-index](../00-index.md) and
  [10-tapeout-submission](../10-tapeout-submission.md).
- `-output_macros` — "Writes LEF abstract information such as LEF pin geometries and
  obstructions for macros… **Note: LEFPIN and LEFOBS apply only when you specify this
  parameter. If you specify this parameter and LEFPIN and LEFOBS are not specified in the map
  file for the layers in the LEF macros the GDSII structures for those macros will be
  empty.**" Checked: the TSMC map file does carry `LEFPIN,LEFOBS` on 19 layer lines
  (M1–M9 and others), so the pairing is correct and the macro pin/obstruction geometry does
  get written.
- `-unit 1000` — "Specifies the resolution for values in the GDSII file. Choose 100, 200,
  1000, 2000, 10000, or 20000. **Default: Units specified in LEF file**." 1000 = 1 nm
  database units.
- `-mode all` — the documented enum is `{ALL | FILLONLY | NOFILL | NOINSTANCES}`, spelled in
  **upper case** on the manual page. The script uses lower case and it works (every run has
  streamed). Cosmetic mismatch only.

**Artefact:** `outputs/nanosoc_eth_chiplet_pads.gds` — **the `pnr_route` target's
assertion**. 463 MB on the 2026-08-05 baseline.

Note the line continuation on line 63: `-merge $gds_merge_list\` has **no space before the
backslash**. Tcl handles it, but it is one keystroke from being a variable named
`gds_merge_list\` — worth fixing on sight.

### 5.12 Final reports and netlists (lines 66-73)

```tcl
 66  report_area  > $REPORT_DIR/${block_name}_imp_area.rep
 67  report_power > $REPORT_DIR/${block_name}_imp_power.rep
 70  write_netlist $OUT_DIR/${block_name}_pnr.v
 71  write_sdf -min_view default_analysis_view_hold -typical_view typical_analysis_view -max_view default_analysis_view_setup $OUT_DIR/${block_name}_pnr.sdf
 73  write_db $block_name
```

- `write_netlist` is called with **no options at all** beyond the filename
  (**Stylus TCR — `write_netlist`**, `TCRcom/write_netlist.html`). In particular neither
  `-include_pg` nor `-include_phys_insts` is passed, so the defaults decide what PG and which
  physical cells appear. This is the netlist `make lec-pnr` compares against
  `_gate_power.v`; the boundary and PG conventions that make that comparison valid are
  analysed in [13-lec §Why `…_gate_power.v`](../13-lec.md). 60 MB on the baseline.
- `write_sdf` here is **Innovus's**, not Genus's. The three view options map the MMMC views
  onto the SDF triplet: `-min_view` "Uses the early delay from the specified analysis view to
  populate the SDF min slot", `-max_view` "Uses the late delay… to populate the SDF max
  slot", `-typical_view` "Uses the **late** delay from the specified analysis view to
  populate the SDF typ slot" (**Stylus TCR — `write_sdf`**, `TCRcom/write_sdf.html`). Note
  that typ takes the *late* delay, not a typical one — that is the tool's definition, not a
  script bug, but it surprises people. 595 MB on the baseline.
- `write_db` — the final DB, saved with the multi-view analysis state restored by line 54.

### 5.13 The in-flow Calibre block (lines 75-83)

```tcl
 75  if {[info exists ::env(CALIBRE_HOME)]} {
 76      exec calibre \
 77      -drc \
 78      -hier \
 79      -turbo 8 \
 80      $drc_ruledeck
 81  }
 83  exit
```

> **THIS BLOCK IS THE REASON `make pnr_route` UNSETS `CALIBRE_HOME`.** Three separate
> problems, all verified and all recorded in the Makefile at lines 206-230:
>
> 1. It passes only the rule deck. `calibre -drc` has no command-line layout/topcell
>    override, and the deck's `LAYOUT PATH "GDSFILENAME"` / `LAYOUT PRIMARY "TOPCELLNAME"`
>    are literal placeholders — so Calibre errors with
>    `Failure to open input file GDSFILENAME for read access.`
> 2. A failing `exec` raises a Tcl error, which **aborts the script before its `exit` on
>    line 83**. Innovus then drops to an interactive prompt and sits there holding a Cadence
>    seat. `make` never returns. Seen on both the 2026-08-05 and 2026-08-06 runs — three
>    occurrences in the former's log — presenting as "a completed 4.5-hour flow that looks
>    like it hung".
> 3. `-turbo 8` is hardcoded, ignoring `DRC_CPUS`.
>
> Everything of value happens **before** line 75, so suppressing the block loses nothing.
> The working DRC path is `make drc` — [§7.9](#79-calibre-drc-and-lvs-targets) and
> [12-calibre-drc](../12-calibre-drc.md).

---

## 6. `procs.tcl` — the reporting helpers

Full path: `ASIC/asic-flows/Cadence/procs.tcl` (13 lines). Sourced by stages 2, 3, 4.

```tcl
  1  proc report_intermediate_step {name REPORT_DIR} {
  2      report_timing_summary > $REPORT_DIR/timing_summary_${name}.rep
  3      report_timing -late  > $REPORT_DIR/timing_${name}_late.rep
  4      report_timing -early > $REPORT_DIR/timing_${name}_early.rep
  5  }
  6
  7  proc report_end_step {name REPORT_DIR} {
  8      report_timing_summary > $REPORT_DIR/timing_summary_${name}.rep
  9      report_timing -late  > $REPORT_DIR/timing_${name}_late.rep
 10      report_timing -early > $REPORT_DIR/timing_${name}_early.rep
 11      report_power > $REPORT_DIR/power_${name}.rep
 12      report_qor -format text -out_file $REPORT_DIR/qor_${name}.rep
 13  }
```

`report_end_step` is `report_intermediate_step` plus power and QoR. The naming convention
(`00_pre_place`, `01_place`, `02_cts`, `03_cts_opt`, `04_route`, `05_route_opt`) is what makes
the reports sort chronologically and what `make status` probes.

Commands:

- `report_timing_summary` "Generates reports that provide details summarized by the violation
  type - setup, hold, or DRV… `-checks {setup | hold | drv}` … **Default: setup hold drv**"
  (**Stylus TCR — `report_timing_summary`**, `TCRcom/report_timing_summary.html`). Note the
  documented default includes **hold**, which makes the missing hold section in these reports
  a genuine anomaly rather than an expected omission — see
  [16-open-defects §1](../16-open-defects.md) and
  [07-reading-reports §`report_timing_summary`](../07-reading-reports.md). Neither
  `-expand_views` nor `-checks` is passed here.
- `report_timing -late`/`-early` with no `-max_paths`, so **one path each** (default is
  "worst path"). These files are one-path reports, not surveys.
- `report_power`, bare (**Stylus TCR — `report_power`**).

> **DIVERGENCE — `report_qor -format text` is not a documented value.** The installed page
> gives `[-format {html json}]` only (**Stylus TCR — `report_qor`**, `TCRcom/report_qor.html`).
> **Observed:** it works and produces a plain-text table — `reports/qor_01_place.rep` is a
> pipe-delimited row with WNS/TNS/FEPS/DRV/POWER/UTIL/INSTS/AREA/DRC/WALL columns. So the
> manual's enumeration is incomplete for this build, not the script wrong. Worth knowing if
> you ever try `-format json` expecting parity.
>
> Second-order: this proc is called at `01_place`, `03_cts_opt` and `05_route_opt`, and
> `report_qor` accumulates rows across the session — see
> [07-reading-reports §Trap](../07-reading-reports.md) before comparing two runs' QoR files.

The `REPORT_DIR` argument is passed explicitly rather than read from the global, which is
correct Tcl hygiene and means these procs are reusable.

---

## 7. The Makefile

Full path: `ASIC/genus-innovus/Makefile` (482 lines). This is the driver.

### 7.1 Header, variables, defaults

> **THE HEADER COMMENT IS COMPLETELY WRONG.** Lines 2 and 12-21:
>
> ```make
>   2  # nanosoc-multicore-system / syn/asic/genus_innovus/Makefile
>  12  # Flat Fusion Compiler P&R flow for the multicore SoC top. All stage logic
>  13  # (fc_init -> fc_synth -> fc_cts -> fc_route -> fc_signoff -> fc_drc ->
>  14  # fc_abstract, + fusion_lib / fc / fc_all / gui) lives in the
>  15  # soclabs-asic-flow toolkit (syn/asic/_flow). This Makefile is a thin shim:
>  16  # it sets DESIGN_DIR, pulls in the project's design-scoped common.mk, then
>  17  # includes the toolkit.
>  20  #   make syn
>  21  #   make help                        # toolkit target list
> ```
>
> None of that describes this file. It is **not** a Fusion Compiler flow (it is Genus +
> Innovus + Calibre), the stage logic does **not** live in a toolkit (it is all inline
> below), there is no `fc_*` target anywhere in it, it does **not** include any toolkit, and
> the path in line 2 is the pre-migration location in a different repository. The comment was
> copied from the Fusion Compiler Makefile and never updated. Only `make help` and `make syn`
> survive from the usage block, and `make help` is this file's own target, not a toolkit's.
> Treat lines 12-21 as noise.

```make
 24  DESIGN_DIR := $(CURDIR)
 25  include $(CURDIR)/../common.mk
 27  ASIC_FLOWS_DIR:= $(DESIGN_DIR)/../asic-flows/Cadence
 28  REPORT_DIR := $(DESIGN_DIR)/reports
 29  LOG_DIR := $(DESIGN_DIR)/logs
 30  OUT_DIR := $(DESIGN_DIR)/outputs
 31  WORK_DIR := $(DESIGN_DIR)/work
```

All absolute (`:=` off `$(CURDIR)`), which is what lets the assertion lines work after the
recipe's `cd`. See [§1.4](#14-the-cwd-work-convention) for the two-`LOG_DIR` wrinkle.

```make
 35  BLOCK := nanosoc_eth_chiplet_pads
 38  GDS   ?= $(OUT_DIR)/$(BLOCK).gds
```

`BLOCK` must match `config.tcl:114`'s `block_name`; nothing enforces that. `GDS` is `?=` so
DRC can be pointed at a stream built elsewhere: `make drc GDS=/path/to/other.gds`.

```make
 42  DRC_RULEDECK ?= $TSMC_65_HOME/CMOS/util/MAIN_DRC_TopMu/CLN65S_<stack>.<rev>
 43  DRC_RUNSET   := $(WORK_DIR)/calibre_drc.runset
 44  DRC_RUNDIR   := $(WORK_DIR)/drc_run
 50  ROMLIBS_REF ?= /home/dwn1c21/SoC-Labs/TAPEOUT/2026july/.../ASIC/romlibs
 54  .DEFAULT_GOAL := help
```

`.DEFAULT_GOAL := help` is a small but real usability fix, explained in situ at lines 52-53:
bare `make` used to run `setup_dirs` — just `mkdir` — and report success having done nothing
recognisable.

```make
 56  setup_dirs:
 57      mkdir -p $(REPORT_DIR)
 ...
 60      mkdir -p $(WORK_DIR)
```

> **NOT `.PHONY`.** `setup_dirs`, `syn`, `syn_norun` and `pnr_setup` are all missing from
> `.PHONY` declarations, unlike `pnr_place`/`pnr_cts`/`pnr_route`/`drc`/`lec*`/`status`/
> `clean`/`distclean`/`help`. A file or directory named `setup_dirs` or `syn` in
> `ASIC/genus-innovus/` would make them no-ops. Low probability, trivial fix.

### 7.2 Preflight targets

```make
 66  .PHONY: asic-flist
 67  asic-flist:
 68      $(MAKE) -C $(NANOSOC_ETH_CHIPLET_HOME) --no-print-directory asic-flist
```

Delegates to the top-level Makefile, which sources the three `set_env.sh` scripts in
dependency order. The comment at lines 62-65 is explicit that this Makefile "deliberately
does not try to reproduce that". Regenerated **every run**, so the TideLink V2 / SoC selection
cannot go stale — worth the seconds it costs.

```make
 73  .PHONY: romlibs-check
 74  romlibs-check:
 75      @$(MAKE) -C $(DESIGN_DIR)/.. -f common.mk --no-print-directory romlibs-verify || { ... }
```

Delegates to `common.mk`'s `romlibs-verify` ([§8](#8-commonmk-only-the-parts-this-makefile-uses)),
and on failure prints the build command and the two reasons it will not work here. This
guards `1_synthesis.tcl:22` — the `set_db … .library` line where a missing ROM `.lib` kills
the run ([§2.3](#23-library-setup-lines-19-23)).

### 7.3 `cpf-patch`

```make
104  cpf-patch:
105      @cpf=$(OUT_DIR)/$(BLOCK)_gate1.cpf; \
106      test -s "$$cpf" || { echo "FAIL: no CPF at $$cpf — did synthesis run?"; exit 1; }; \
107      if grep -q 'create_power_nets' "$$cpf"; then \
108          echo "OK: CPF already carries its supply nets"; \
109      else \
110          grep -q 'end_design' "$$cpf" || { echo "FAIL: $$cpf has no end_design — unexpected format"; exit 1; }; \
111          sed -i 's/^end_design/create_ground_nets -nets VSS\ncreate_power_nets -nets VDD\n\nupdate_power_domain -name PD_TOP -primary_power_net VDD -primary_ground_net VSS\n\nend_design/' "$$cpf"; \
112          grep -q 'update_power_domain' "$$cpf" || { echo "FAIL: CPF patch did not apply"; exit 1; }; \
113          echo "OK: patched $$cpf with VDD/VSS supply nets (add_fillers needs them)"; \
114      fi
```

Three guards (input exists, format recognised, patch applied) and an idempotence check on
line 107. All good practice.

**The Makefile's central claim here is that this cannot be fixed with an Innovus command, and
the manuals prove it.** Two pages, side by side:

| | Innovus Tcl `update_power_domain` | CPF `update_power_domain` |
|---|---|---|
| Manual | **Stylus TCR — `update_power_domain`** (`TCRcom/update_power_domain.html`) | **CPF Reference** (`cpf_ref/reference.html`) |
| Purpose | "Renames a power domain or changes its structure." | "Specifies implementation aspects of the specified power domain." |
| Options | `-add_block_box`, `-core_to_{bottom,left,right,top}`, `-default_tech_site`, `-disjoint_hinst_box_list`, `-first_row_site_index`, `-gap_sides`/`-gap_edges`, `-last_row_site_index`, `-power_extend_sides`/`-power_extend_edges`, `-row_flip`, `-row_pattern_site`, `-row_space_type`, `-row_spacing` | `-instances`, `-boundary_ports`, and the required group `{ -primary_power_net net \| -primary_ground_net net \| -equivalent_power_nets … \| -pmos_bias_net … }` |
| `-primary_power_net`? | **absent** | **present** |

So `-primary_power_net` / `-primary_ground_net` are CPF statements and there is no Innovus Tcl
equivalent. The file is what has to be repaired, which is exactly what the patch does — and
exactly what the 2026-07 operator did by hand mid-session, which is why that run has fillers.
The patched file is 730 bytes and is reproduced in [04-power-plan §1.4](../04-power-plan.md).

`create_power_nets` and `create_ground_nets` are likewise real CPF commands:
"Specifies or creates a list of power nets. **Even if this net exists in the RTL or the
netlist, it still must be declared through this command if the net is referenced in other CPF
commands.**" (**CPF Reference — `create_power_nets`**.) That sentence is the whole
justification for inserting them before `update_power_domain`.

> **SMALL RISK — `sed -i` on a tool-generated file.** The patch edits `outputs/*_gate1.cpf`
> in place. It is idempotent and guarded, but it means the file on disk no longer matches
> what Genus wrote, and a re-run of `make syn` regenerates it *and* re-patches it (the `syn`
> recipe calls `cpf-patch` on line 123). The alternative — writing a patched copy under a
> different name and pointing `2_pnr_setup.tcl:40` at it — is not available without editing
> the shared submodule, which is the constraint this whole design works under.

### 7.4 `syn`

```make
121  syn: setup_dirs asic-flist romlibs-check
122      cd $(WORK_DIR)/; genus -f $(ASIC_FLOWS_DIR)/1_synthesis.tcl -log $(LOG_DIR)/syn_logs
123      @$(MAKE) --no-print-directory cpf-patch
124      @test -s $(OUT_DIR)/$(BLOCK)_gate_power.v || { \
125          echo "FAIL: synthesis produced no netlist at $(OUT_DIR)/$(BLOCK)_gate_power.v"; \
126          echo "      Genus exits 0 on a failed script — look for the real error with:"; \
127          echo "        grep -nE 'Encountered problems|^Error|not set' $(LOG_DIR)/syn_logs.log*"; \
128          exit 1; }
129      @echo "OK: netlist $(OUT_DIR)/$(BLOCK)_gate_power.v"
```

Three things here.

**`-f` is correct for Genus** — it is an unambiguous abbreviation of the documented `-files`
(**Genus UG — Invoking Genus**), unlike Innovus. See
[§2.1](#21-header-lines-1-13).

**`-log $(LOG_DIR)/syn_logs`** — "`-log prefix` — Specifies either the full log and command
file names or the prefix for both the `.log` and `.cmd` files. The `.log` file contains the
normal logging output, the `.cmd` file contains the TCL commands that were executed."
(**Genus UG — Invoking Genus**.) Genus's `-overwrite` option — "Allows overwriting of the
default and specified log files" — is **not** passed, so Genus increments:
`syn_logs.log`, `.log1`, `.log2`, … The 2026-08-05 baseline has `.log` through `.log7`. That
is why the error hint on line 127 globs `syn_logs.log*` and not a fixed name. Same convention
as the `_gate1.cpf` numbering ([§2.11](#211-netlist-and-power-intent-writeout-lines-74-77)).

**The artefact assertion is not belt-and-braces.** The comment at lines 116-120 is the whole
discipline of this Makefile: "when its `-f` script fails, Genus prints 'Encountered problems
processing file', drops to its interactive prompt, reads EOF and exits ZERO."

> **DIVERGENCE — the tool has documented options for exactly this, and the flow uses neither.**
> `genus -abort_on_error` — "Specifies that Genus must exit if a script error is found"
> — and `genus -batch` — "Exits after processing the scripts specified with the `-files`
> option" (**Genus UG — Invoking Genus**). The `read_hdl` page repeats the advice in the
> imperative: "Use the `genus -abort_on_error -f <your script>` command to specify that Genus
> automatically quit if a script error is detected when reading in HDL files instead of
> holding at the `genus:root:>` prompt" (**Genus ComRef — Input and Output**).
>
> The artefact assertion should stay regardless — it catches "wrote nothing" as well as
> "errored" — but `-abort_on_error -batch` would turn a silent exit-0 into a real non-zero
> exit and stop the flow at the point of failure rather than at the end of the recipe. It
> would also interact with `config.tcl`'s `check_cpf` wrapper: that wrapper exists precisely
> because a `check_cpf` failure aborts the `-f` script, and under `-abort_on_error` the
> semantics of "abort" may change. **Untested — no tool may be launched for this document.**
> Worth a single 2-hour experiment.

### 7.5 The LEC targets

```make
144  lec:
145      cd $(WORK_DIR)/; lec -xl -Dofile ./lec.dofile
156  lec-pnr:
157      $(DESIGN_DIR)/scripts/lec/run_lec.sh pnr
162  lec-gate:
163      $(DESIGN_DIR)/scripts/lec/run_lec.sh gate
169  lec-selftest:
170      $(DESIGN_DIR)/scripts/lec/run_lec.sh selftest
```

`make lec` runs the dofile **synthesis** wrote, so it depends on `syn` and not on P&R — and
the comment at 134-143 documents both of its flaws honestly:

1. It compares `fv_map` against `outputs/$(BLOCK)_gate.v` and never reads `_pnr.v`.
   **Corroborated by the manual and the log**: `-golden_design` defaults to `rtl`
   (**Genus ComRef — `write_do_lec`**), and Genus itself said so at run time —
   `CFM-2`: "The composite dofile 'lec.dofile' includes two compare operations: rtl-to-fv_map
   and fv_map-to-revised."
2. The generated dofile ends `exit -f` and this recipe checks nothing, so a NON-EQUIVALENT
   result still reports success.

Note the contrast in discipline: `lec` has **no artefact assertion at all**, which is exactly
what the rest of the file forbids. That is deliberate — it is a legacy target kept for
comparison — but it is the one place the rule is broken, and the comment says so. `lec-pnr`,
`lec-gate` and `lec-selftest` delegate to `scripts/lec/run_lec.sh`, which enforces the verdict
twice. Full treatment: [13-lec](../13-lec.md).

### 7.6 `INNOVUS := innovus -stylus -files`

```make
193  INNOVUS := innovus -stylus -files
```

One variable, three users, one place to be right. The 19-line comment above it (lines
174-192) is the flow's most valuable single block of documentation, and it is correct:

- **`-files`, not `-f`.** Confirmed against the manual: the Stylus UG's worked example is
  `innovus -stylus -files run.tcl` and the log excerpt shows `#@ Processing -files option`
  (**Stylus UG — Getting Started**). A grep of the whole installed Innovus doc tree finds no
  `innovus -f` anywhere, in either UI's manual.
- **The three stage script headers are wrong** and say `-f`. See
  [§3.1](#31-header-lines-1-13).
- **`-f` fails silently:** `**ERROR: (IMPSYT-468): Unknown argument -f`, usage, exit 0.
- **`b19e784` or later** is required for `asic-flows`, because the earlier revision stops
  after routing and writes no stream.

### 7.7 The three P&R stage targets

```make
196  pnr_place: setup_dirs
197      cd $(WORK_DIR)/; $(INNOVUS) $(ASIC_FLOWS_DIR)/2_pnr_setup.tcl
198      @test -d $(WORK_DIR)/$(BLOCK) || { \
199          echo "FAIL: placement wrote no DB at $(WORK_DIR)/$(BLOCK)"; exit 1; }

201  pnr_cts:
202      cd $(WORK_DIR)/; $(INNOVUS) $(ASIC_FLOWS_DIR)/3_pnr_clock.tcl
203      @test -s $(REPORT_DIR)/timing_summary_03_cts_opt.rep || { \
204          echo "FAIL: CTS wrote no post-opt timing summary — stage did not complete."; exit 1; }

231  pnr_route:
232      cd $(WORK_DIR)/; env -u CALIBRE_HOME $(INNOVUS) $(ASIC_FLOWS_DIR)/4_pnr_route.tcl
233      @test -s $(OUT_DIR)/$(BLOCK).gds \
234          && echo "OK: GDSII ... ($$(du -h ... | cut -f1))" \
235          || { echo "FAIL: no GDSII at $(OUT_DIR)/$(BLOCK).gds"; ... exit 1; }

244  pnr_all: syn pnr_place pnr_cts pnr_route
```

**Assertion choice is thoughtful and each one is the right artefact:**

| Target | Assertion | Why that one |
|---|---|---|
| `pnr_place` | `test -d work/$(BLOCK)` | the DB is a **directory**, so `-d` not `-s` |
| `pnr_cts` | `test -s reports/timing_summary_03_cts_opt.rep` | written by `report_end_step 03_cts_opt`, the **last** thing before `write_db` — so it proves the stage finished, not just started |
| `pnr_route` | `test -s outputs/$(BLOCK).gds` | the deliverable |

`pnr_cts` deliberately does **not** assert on the DB: the DB already exists from `pnr_place`,
so `test -d` would pass on a CTS stage that did nothing. Choosing a *stage-specific, late*
artefact is the whole point.

**`env -u CALIBRE_HOME`** on line 232 is the suppression of `4_pnr_route.tcl`'s two broken
Calibre blocks ([§5.3](#53-the-calibre-tcl-source-lines-21-23),
[§5.13](#513-the-in-flow-calibre-block-lines-75-83)). `env -u` unsets the variable for that
one process, so the `[info exists ::env(CALIBRE_HOME)]` guards both evaluate false. It is the
minimum-blast-radius fix: nothing else in the environment changes, no shared file is edited,
and the Calibre targets that *do* work are unaffected because they run in separate recipes.

**`pnr_all`** is a plain prerequisite list, so `make -j` would try to run them concurrently
and corrupt the DB. Nothing prevents that — `.NOTPARALLEL:` is absent. In practice nobody
runs this with `-j`, but it costs one line to make it safe.

### 7.8 `gui` and `pnr_setup`

```make
247  pnr_setup:
248      cd $(WORK_DIR)/; innovus -stylus
```

Bare interactive session, no config, no DB. Note it invokes `innovus -stylus` directly rather
than `$(INNOVUS)` — correct, because `$(INNOVUS)` ends in `-files` and would need a script.

```make
255  gui:
260      @test -n "$$DISPLAY" || { ... }
267      @xdpyinfo >/dev/null 2>&1 || { ... }
278      @test -d $(WORK_DIR)/$(BLOCK) || { ... }
287      @printf '%s\n' \
288          'source ../scripts/config.tcl' \
289          'read_db $(BLOCK)' \
290          'if {[catch {gui_show} e]} { puts stderr "WARNING: gui_show failed: $$e" }' \
291          'puts "== $(BLOCK) loaded, GUI shown — this is the last-written DB =="' \
292          > $(WORK_DIR)/open_db.tcl
293      cd $(WORK_DIR)/; $(INNOVUS) open_db.tcl
```

Four checks before it launches anything, each guarding a real failure mode:

1. `DISPLAY` unset — a ThinLinc desktop's `DISPLAY` does not reach a VS Code Remote-SSH
   terminal.
2. `DISPLAY` set but no X server answers — probed with `xdpyinfo`, not just `test -n`,
   because a malformed value like `12.0` (missing leading colon) passes `-n` and Innovus then
   drops to no-window mode with only a warning (`IMPSYT-1507`). The `case` at 271-275
   even detects that specific malformation and suggests `export DISPLAY=:$$DISPLAY`.
3. No saved DB.
4. `gui_show` wrapped in `catch` so a GUI failure does not kill the session.

**`gui_show` is required, not decoration.** "Opens the Innovus main window… If you started the
Innovus software with the `innovus -no_gui` command, you can use `gui_show` to pop up the main
window." (**Stylus TCR — `gui_show`**, `TCRcom/gui_show.html`.) The Makefile's comment at
280-286 records the measured behaviour that motivates it: launched with `-files`, Innovus
creates its main window but never **maps** it — `xwininfo` reports `Map State: IsUnMapped`
and `xprop` reports no `WM_STATE` — so the session looks like a plain text console. An
explicit `gui_show` moves it `IsUnMapped -> IsViewable`. The manual does not document that
`-files` suppresses mapping; this is a measured site fact.

The generated `open_db.tcl` is the reason `gui` works where `pnr_setup` does not: `read_db`
alone fails because `$block_name` and every library path live in `config.tcl`. Also see
[02-innovus-basics §The GUI](../02-innovus-basics.md#the-gui-and-why-it-looks-like-it-did-not-open).

### 7.9 Calibre DRC and LVS targets

```make
316  $(DRC_RUNSET): | setup_dirs
317      @printf '%s\n' \
318          '// GENERATED by ASIC/genus-innovus/Makefile — edits will be overwritten.' \
319          'drc.rulesFile.value = "$(DRC_RULEDECK)"' \
320          'drc.runDir.value = "$(DRC_RUNDIR)"' \
321          'drc.layout.layoutFile.value = "$(GDS)"' \
322          'drc.layout.topCell.value = "$(BLOCK)"' \
323          'cmn.turboCommand.runHow.value = "multi"' \
324          > $@
```

A real file target with an **order-only** prerequisite (`| setup_dirs`) — correct, because
`setup_dirs` is always out of date and a normal prerequisite would regenerate the runset every
time. The comment at 298-315 explains the two bugs this fixes: `make drc` used to run a bare
`calibre -gui` with no runset at all, and layout/top cell used to be set independently and
drifted apart (the reference run named `nanosoc_eth_chiplet.gds` against top cell
`nanosoc_eth_chiplet_pads`, which is not a cell in that file — hence its 0-byte `DRC_RES.db`).
Deriving both from `$(GDS)`/`$(BLOCK)` in one place makes disagreement impossible.

```make
328  drc-preflight:
329      @test -s $(GDS) || { ... }
331      @test -r $(DRC_RULEDECK) || { ... needs the $TSMC_65_HOME mount and group tsmc65pdkgrp. }
362  drc: drc-preflight
363      DRC_GDS=$(GDS) DRC_RUNDIR=$(DRC_RUNDIR) DRC_CPUS=$(DRC_CPUS) \
364          $(DESIGN_DIR)/scripts/calibre/run_drc.sh
```

`drc` is the target that works: headless, no X, no runset, project-owned wrapper deck that
`INCLUDE`s the foundry deck rather than copying or patching it. The 20-line comment at
338-360 is the definitive account of why the in-flow Calibre never ran, and the caveat about
what the numbers mean (macro-only geometry: 10,109 OD and 12,854 PO shapes die-wide, no
standard-cell/IO/bond-pad devices, no seal ring, no fill). Do not quote a DRC number without
reading it. Full page: [12-calibre-drc](../12-calibre-drc.md) and
[14-drc-triage](../14-drc-triage.md).

`drc_gui` / `drc_batch` (lines 389-397) are the runset-driven fallbacks.

`lvs-preflight` / `lvs` (375-385) are expected to **fail today** and to say exactly why: every
TSMC package installed here is Front End (`_FE`), so there is no transistor netlist for the
standard cells, IO drivers or bond pads. That is procurement, not engineering. The target
turns green by itself the day the `_BE` packages land.

> **ORDERING WART.** `.PHONY: drc_gui` is declared at line 367, but the `drc_gui` recipe is
> at 389 — with the `lvs-preflight` comment block and the `lvs` targets interleaved between.
> Valid make, confusing to read. Purely cosmetic.

### 7.10 `status`, `clean`, `distclean`, `help`

```make
417  status:
418      @echo "== $(BLOCK) =="
419      @printf '  %-14s %-4s %s\n' STAGE OK ARTEFACT
420      @for spec in \
421          "flist:$(NANOSOC_ETH_CHIPLET_HOME)/build/chip/flist/soc.flist" \
422          "romlibs:$(ROMLIBS_DIR)/cc_rom/rom_via.lef" \
423          "syn:$(OUT_DIR)/$(BLOCK)_gate_power.v" \
424          "place:$(REPORT_DIR)/timing_summary_01_place.rep" \
425          "cts:$(REPORT_DIR)/timing_summary_03_cts_opt.rep" \
426          "route:$(REPORT_DIR)/timing_summary_05_route_opt.rep" \
427          "gds:$(GDS)" \
428          "pnr-netlist:$(OUT_DIR)/$(BLOCK)_pnr.v" \
429          "drc:$(DRC_RUNDIR)" ; do \
430          stage=$${spec%%:*}; path=$${spec#*:}; \
431          if [ -s "$$path" ] || [ -d "$$path" ]; then \
432              printf '  %-14s %-4s %s\n' "$$stage" "yes" "$$path"; \
```

**This is artefact probing, not stamp files, and that is the point.** Nine probes, each the
same artefact its stage target asserts on, so `status` and the stage assertions cannot
disagree. It touches no licence and takes milliseconds. It is the fastest way to see where a
part-finished flow stopped.

Two details:

- The `stage:path` packing with `${spec%%:*}` / `${spec#*:}` works because no path contains a
  colon. Fine on this site; would break on a Windows-style path.
- `[ -s "$$path" ] || [ -d "$$path" ]` — the `-d` arm exists for `drc:$(DRC_RUNDIR)`, which is
  a directory. **Consequence: an empty `work/drc_run/` reports `yes`.** A DRC run that
  created its directory and then died looks complete. Minor, but it is the one probe in the
  list that can lie.
- The `route` probe is `timing_summary_05_route_opt.rep` — written by
  `report_end_step 05_route_opt` at `4_pnr_route.tcl:35`, i.e. *before* the stream-out. So
  `route: yes` + `gds: --` is a meaningful and expected intermediate state, not a
  contradiction.

```make
441  clean:
443      rm -rf $(WORK_DIR) $(LOG_DIR)
448  distclean:
449      @echo "about to remove work/ logs/ outputs/ reports/ — including:"
450      @test -s $(GDS) && echo "  !! $(GDS) ($$(du -h $(GDS) | cut -f1))" || true
451      @du -sh $(OUT_DIR) $(REPORT_DIR) 2>/dev/null | sed 's/^/  /' || true
452      rm -rf $(WORK_DIR) $(LOG_DIR) $(OUT_DIR) $(REPORT_DIR)
```

`clean` keeps `outputs/` and `reports/`, so a finished GDS and its sign-off reports survive;
it costs a full P&R re-run but not the Genus hour. `distclean` prints what it is about to
destroy, with the GDS size, before doing it — a courtesy that has probably saved a run.

Note what `clean` takes with `work/`: all three DBs, `lec.dofile`, `design.sdf` (494 MB),
`design_clk.spec` (1.9 MB), `work/timingReports/`, and the 853 MB of `.mtarpt` files.

`help` (455-482) prints the target list, the ordering rule, the resume advice, and the two
env vars the flow needs, with their resolved values.

---

## 8. `common.mk` — only the parts this Makefile uses

Full path: `ASIC/common.mk` (363 lines). Included at `Makefile:25`. Most of it serves the
Synopsys DC/RTLA/Fusion-Compiler flows and is **inert** for Genus + Innovus: `TARGET_LIB`,
`LINK_LIBS`, `MEM_DB_*`, `TF_FILE`, `MW_REF_LIB`, `RTLA_RM_PATH`, `DB_*`, `TLUPLUS_*`,
`CLK_*`, `FC_DIE_*`, `PDK_PACK`, `DESIGN_MODE`, `MEM_LEFS`, `MEM_DBS_*` — none of these are
read by `config.tcl` or by any Cadence script. Do not "fix" them expecting the Cadence flow to
change.

What the Cadence flow actually consumes:

| `common.mk` line | Export | Consumed by | If missing |
|---|---|---|---|
| 25 | `NANOSOC_ETH_CHIPLET_HOME` | `config.tcl:83,84,120,160`; `Makefile:68,421` | ROM-lib, top-HDL and patched-IO-LEF paths all break |
| 79 | `TSMC_65_HOME` (`$TSMC_65_HOME`) | `config.tcl:72,73,131,133,134` | every std-cell / IO / tech-LEF path breaks |
| 80 | `PHYS_IP` (`$PHYS_IP`) | `config.tcl:132` (commented-out alternative only) | nothing today |
| 87 | `SOCLABS_ASIC_FLOW_DIR` | `2_pnr_setup.tcl:49`, `3_pnr_clock.tcl:20`, `4_pnr_route.tcl:19` | stages 2-4 abort on the `source` |
| 109 | `ASIC_FLIST` | `read_flist.tcl:46` (`$::env(ASIC_FLIST)`) | synthesis reads no RTL |
| 60-61 | `TIDELINK_HOME`, `TIDECHART_HOME` | inside the flists | **Genus reads the whole SoC, then dies at the END of `read_flist.tcl` ~10 min in** — reads as a link-stage problem |
| 33-52, 65 | `ARM_IP_LIBRARY_PATH`, `ETH_SS_HOME`, `CMSDK_DIR`, `ARM_CORTEXM0PLUS_IP_PATH`, … | the flists' `${VAR}` references, expanded by `expand_env` | RTL paths do not resolve; with `ARM_CORTEXM0PLUS_IP_PATH` specifically, "the flist parser silently drops the cores" |
| 278 | `ROMLIBS_DIR` | `Makefile:410,411,422`; must equal `config.tcl:83,84` | ROM libs land where Genus never looks |
| 337-343 | `romlibs-verify` target | `Makefile:75` | no ROM preflight |

Two design decisions in `common.mk` worth carrying forward:

**`?=` everywhere, never `:=` for environment.** Lines 22-23 explain why: an earlier `:=` won
over a correctly sourced `set_env.sh` and "silently retargeting every derived path below…
at `/home/dam1n19/SoCLabs` — a directory that just happens to exist, so nothing failed
loudly." The `CHIPLET_HOME_DEFAULT` on line 24 is computed from
`$(dir $(lastword $(MAKEFILE_LIST)))/..`, i.e. relative to `common.mk` itself, so it is
correct wherever the tree is checked out.

**`romlibs-preflight` probes capability, not paths.** Lines 298-311 run
`$(ROM_COMPILER) -help` and parse `Available generators are:`. A working install lists its
generators; the one on this host lists none. That is a capability probe rather than a
`test -x`, and it is the pattern the rest of this flow's preflights should copy. The
40-line comment above it (lines 216-248) is the full investigation: not the install copy, not
NFS, not the JRE — the same install generated `rf_01k` here on 27 Apr 2026, before the
RHEL 8.8 → 8.10 upgrade. Escalation, not engineering.

---

## 9. Divergence index

Everything flagged above, in one table. "Manual" = the installed page disagrees with the
script. "Comment" = the script's own header/comment is wrong. "Dead" = unreachable or
inert code. Severity is this page's judgement.

| # | Where | Kind | Severity | Summary |
|---|---|---|---|---|
| 1 | `2_pnr_setup.tcl:5`, `3_pnr_clock.tcl:5`, `4_pnr_route.tcl:4` | Comment | **High** | Headers say `innovus -stylus -f <script>`. `-f` is not documented anywhere in the installed Innovus docs; the Stylus UG shows `-files`. `-f` prints usage and exits 0. Stages 3 and 4 also name the **wrong script**. |
| 2 | `3_pnr_clock.tcl:25` | Manual | **High** | `create_clock_tree_spec -out_file` writes the spec but "The file is not executed"; nothing `source`s it, so `ccopt_design` regenerates the spec internally (observed in `innovus.log3:10361-10363`). The 1.9 MB `design_clk.spec` is documentation only, and hand-editing it does nothing. |
| 3 | `Makefile:12-21` | Comment | **High** | The header describes a Fusion Compiler toolkit shim. This is a Genus+Innovus Makefile with all logic inline, no `fc_*` targets and no toolkit include. Wholly wrong; also has the pre-migration path. |
| 4 | `1_synthesis.tcl:76-77` | Manual | **Medium** | `-base_name` silently gains a counter (`_gate1.cpf`, `_gate2.upf`) — undocumented, and `2_pnr_setup.tcl:40` hardcodes the `1`. `-overwrite` exists and is unused. |
| 5 | `2_pnr_setup.tcl:38-42` | Manual | **Medium** | `init_design`'s documented prerequisite order puts `read_power_intent` **before** `init_design`; the script puts it after. Works, but `init_design`'s power-domain sub-step ran with no intent. |
| 6 | `Makefile:122` | Manual | **Medium** | The exit-0 trap has documented remedies — `genus -abort_on_error` and `genus -batch` — and the flow uses neither, relying on the artefact assertion alone. |
| 7 | `1_synthesis.tcl:38` | Manual | **Medium** | `check_cpf` has a documented `-continue_on_error`; the flow instead wraps the command in a Tcl `catch` in `config.tcl`. The wrapper's diagnostic prints the literal string `0`. |
| 8 | `1_synthesis.tcl:44` | Manual | **Medium** | `check_power_structure`'s synopsis makes `{-pre_synthesis \| -post_synthesis \| -post_pg}` mandatory; the script supplies none. It ran anyway (observed), so the report's stage is unstated. |
| 9 | `4_pnr_route.tcl:58` | Dead | **Medium** | `set GDSFILENAME` is read by nothing. Its intended consumer, the SVRF deck, treats `GDSFILENAME` as a literal placeholder string, which is why the in-flow Calibre has never worked. |
| 10 | `4_pnr_route.tcl:21-23, 75-81` | Broken | **Medium** | Both `CALIBRE_HOME` blocks fail here — `IMPSE-110` (no Tk 8.0) and a failing `exec` that aborts the script before `exit`, leaving Innovus at an interactive prompt holding a seat. Suppressed by `env -u CALIBRE_HOME`. |
| 11 | `1_synthesis.tcl:79` | Manual | **Low** | `write_sdf -timescale ns` scales the delay values but, per the manual, "does not change the timescale setting of the SDF file". Nothing consumes this SDF today. |
| 12 | `1_synthesis.tcl:81` | Manual | **Low** | Option is `-log_file`; the script writes `-logfile`. Accepted silently (observed). |
| 13 | `procs.tcl:12` | Manual | **Low** | `report_qor -format text` is not in the documented enum `{html json}`. It works (observed) — the manual is incomplete, not the script wrong. |
| 14 | `4_pnr_route.tcl:46-52` | Cost | **Low** | Four `.mtarpt` files (853 MB measured) written to `work/` with bare relative paths, then deleted by `make clean`. Plus two full timing resets from the two `set_analysis_view` calls. |
| 15 | `2_pnr_setup.tcl:27` | Manual | **Low** | Option is `-lefs`; the script writes `-lef`. Accepted as an unambiguous prefix. |
| 16 | `4_pnr_route.tcl:64` | Manual | **Low** | `-mode all`; the documented enum is upper case `{ALL \| FILLONLY \| NOFILL \| NOINSTANCES}`. Accepted. |
| 17 | `2_pnr_setup.tcl:44` + `preplace.tcl:2` | Duplication | **Low** | `design_process_node 65` set twice, in two different files, and both **after** `init_design` (which therefore used the default 90). |
| 18 | `2_pnr_setup.tcl:33-35, 58-60`; `3_pnr_clock.tcl:36-38`; `1_synthesis.tcl:50-52, 83-90` | Dead | **Low** | Every `DFT == 1` branch. `DFT` is 0; `scripts/dft_setup.tcl` does not exist; the `read_def` would fire before `init_design`; `reorder_scan`'s documented prerequisite `place_global_ignore_scan true` is never set. |
| 19 | `Makefile:122,197,202,232` | Robustness | **Low** | `cd $(WORK_DIR)/;` uses `;` not `&&`, so a failed `cd` launches the tool in the wrong directory. `pnr_cts` and `pnr_route` have no `setup_dirs` prerequisite. |
| 20 | `Makefile:56,121,131,247` | Robustness | **Low** | `setup_dirs`, `syn`, `syn_norun`, `pnr_setup` are not `.PHONY`. |
| 21 | `Makefile:244` | Robustness | **Low** | `pnr_all` has no `.NOTPARALLEL:`; `make -j pnr_all` would corrupt the shared DB. |
| 22 | `Makefile:429` | Reporting | **Low** | The `drc` probe uses `-d`, so an empty `work/drc_run/` reports `yes`. |
| 23 | `Makefile:144-145` | Discipline | **Low** | `make lec` is the only stage-like target with **no** artefact assertion, so a NON-EQUIVALENT verdict reports success. Documented in situ; `lec-pnr` fixes it. |
| 24 | `4_pnr_route.tcl:1, 16`; `3_pnr_clock.tcl:2` | Comment | **Low** | Stage 4's banner is missing its opening rule and calls itself a "setup script"; both stage 3 and stage 4 `puts "Starting CTS Flow ..."`. |
| 25 | `4_pnr_route.tcl:63` | Style | **Low** | `-merge $gds_merge_list\` — no space before the line-continuation backslash. |
| 26 | `nanosoc_eth_chiplet_pads.mmmc:193-194` | Dead | **Low** | `typical_analysis_view_setup` / `_hold` are defined and never activated by any `set_analysis_view` in the flow. |

---

## 10. Things not found in the installed manuals

Stated explicitly, because absence is itself information.

**Message IDs with no page in `innovuserrmsg/`** (1,992 files, checked individually):
`IMPSP-5110`, `IMPSYT-468`, `IMPSYT-1507`, `IMPTCM-162`, `IMPDBTCL-247`, `IMPDB-1221`,
`IMPSE-110`, `IMPCCOPT-2248`. Every one of these appears in this project's logs and in the
sibling docs. The reference does have `NRDB-51` and `IMPCCOPT-4144`. So `man <MSGID>` inside
the tool remains the primary source for most of the IDs this flow actually hits — the HTML
reference is a partial subset.

**`innovus -f`** — no occurrence anywhere in `TCRcom/`, `UGcom/`, `innovusTCR/` or
`innovusUG/`. Only `-files` is documented, and only in **Stylus UG — Getting Started**.

**Genus `-f`** — not in the invocation synopsis either; it is an unambiguous abbreviation of
`-files` under the documented rule "You can abbreviate the options for the genus command as
long as there are no ambiguities with other options" (**Genus UG — Invoking Genus**).

**`write_do_lec -logfile`** — the documented spelling is `-log_file`. The script's spelling
appears in no manual page but is accepted by the tool.

**`report_qor -format text`** — `text` appears in no value list on the installed
`report_qor` page, which gives only `{html json}`. The tool accepts it.

**`write_power_intent -base_name` counter suffixes** — the numeric suffix Genus appends
(`_gate1.cpf`, `_gate2.upf`) is not mentioned on the `-base_name` option, on the
`write_power_intent` page, or anywhere in `genus_comref/`. It is inferred from the observed
log lines and from the identical convention Genus uses for `-log` prefixes.

**`-files` suppressing GUI window mapping** — the Makefile's measured claim (window created
but `IsUnMapped`, no `WM_STATE`, fixed by an explicit `gui_show`) has no counterpart in the
`gui_show` page or in **Stylus UG — Getting Started**. Site-measured, not documented.

**`check_power_structure` defaulting its stage selector** — the manual makes
`{-pre_synthesis | -post_synthesis | -post_pg}` mandatory and says nothing about a default.
The observed behaviour (runs and reports without one) is undocumented.

---

## Related pages

- [01-flow-overview](../01-flow-overview.md) — the map: stages, targets, artefacts, timings
- [02-innovus-basics](../02-innovus-basics.md) — interactive sessions, `get_db`, snapshots, the GUI
- [03-floorplan](../03-floorplan.md) / [04-power-plan](../04-power-plan.md) — what
  `floorplan.tcl` and `power_plan.tcl` do
- [05-place-cts-route](../05-place-cts-route.md) — what `place_design`, `ccopt_design`,
  `route_design` and `opt_design` do to this design
- [06-fill-antenna-bondpads](../06-fill-antenna-bondpads.md) — `filler.tcl` and
  `place_bondpads.tcl`
- [07-reading-reports](../07-reading-reports.md) — every report file this page names
- [08-debugging](../08-debugging.md) — the method, including "exit status lies"
- [11-known-issues](../11-known-issues.md) / [16-open-defects](../16-open-defects.md) — the
  live defects several of these lines cause or expose
- [12-calibre-drc](../12-calibre-drc.md) — why `4_pnr_route.tcl`'s Calibre block never worked
- [13-lec](../13-lec.md) — what `write_do_lec` produces and why it is not enough
