# 01 — Flow Overview

**What this page is for.** This is the map of the `nanosoc_eth_chiplet_pads` ASIC flow:
the four stages, the `make` target that runs each, the shared `asic-flows` script each
target invokes, the project-local `scripts/*.tcl` that script sources, and the artefacts
each one leaves behind. It also covers the resume model — all three P&R stages share a
single Innovus database, so they must run in order but any one of them can be re-invoked
to pick up where the flow stopped — and the one trap that has cost this project the most
time: **both Genus and Innovus exit 0 when they fail.**

Everything here is TSMC 65nm, Genus for synthesis, Innovus `v21.11-s130_1` in
STYLUS/Common-UI mode for P&R, Calibre for DRC. All commands are run from
`ASIC/genus-innovus/`.

Sibling pages: [00-index](00-index.md) ·
[02-innovus-basics](02-innovus-basics.md) ·
[03-floorplan](03-floorplan.md) ·
[04-power-plan](04-power-plan.md) ·
[05-place-cts-route](05-place-cts-route.md) ·
[06-fill-antenna-bondpads](06-fill-antenna-bondpads.md) ·
[07-reading-reports](07-reading-reports.md) ·
[08-debugging](08-debugging.md) ·
[09-signoff-checklist](09-signoff-checklist.md) ·
[10-tapeout-submission](10-tapeout-submission.md) ·
[11-known-issues](11-known-issues.md)

---

## READ THIS FIRST: both tools exit 0 on failure

This is not a footnote. It is the single most important fact about driving this flow.

**Genus.** When its `-f` script hits a fatal error, Genus prints `Encountered problems
processing file`, drops to its interactive prompt, reads EOF from `/dev/null`, and
**exits zero**. `make pnr_all` used to sail straight past a dead synthesis into
place-and-route on a netlist that was never written.

**Innovus.** Hand it an argument it does not accept and it prints a *usage message* and
**exits zero**. It never ran your script at all. Three P&R stages once "passed" in under
a minute this way, and the only symptom was a missing GDS at the end of a night's run.

Consequence, and the design rule for this Makefile: **every stage target asserts on an
artefact on disk, never on `$?`.** See [`Makefile`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/Makefile):

| target | assertion |
|---|---|
| `syn` | `test -s outputs/nanosoc_eth_chiplet_pads_gate_power.v` |
| `pnr_place` | `test -d work/nanosoc_eth_chiplet_pads` |
| `pnr_cts` | `test -s reports/timing_summary_03_cts_opt.rep` |
| `pnr_route` | `test -s outputs/nanosoc_eth_chiplet_pads.gds` |

If you add a stage, add an artefact assertion with it. A green `make` here means an
artefact exists; it never means "the tool returned success", because the tool always does.

### `-files`, not `-f`

```
INNOVUS := innovus -stylus -files          # correct
innovus -stylus -f <script>                # WRONG — silently does nothing
```

Every one of the three stage scripts in `asic-flows` carries a header line saying
`run: innovus -stylus -f <script>`. **That header is wrong.** `-f` is legacy-UI only.
Stylus/Common UI rejects it with

```
**ERROR: (IMPSYT-468): Unknown argument -f
```

then prints usage and exits 0 — so `make` records the stage as passed and moves on to the
next one. The Makefile's `INNOVUS` variable exists precisely to keep this correct in one
place.

Note the asymmetry: **`-f` is right for Genus.** `make syn` runs
`genus -f .../1_synthesis.tcl` and that is correct — `-f` is Genus's own script flag. The
`-files` rule applies only to Innovus in Stylus mode.

---

## The four stages

```
make syn  ->  make pnr_place  ->  make pnr_cts  ->  make pnr_route  ->  [ make drc ]
 Genus         Innovus            Innovus           Innovus              Calibre
```

`make pnr_all` = `syn pnr_place pnr_cts pnr_route`, unattended, multi-hour.

All four `cd` into `work/` before launching the tool.
That is not cosmetic: [`scripts/config.tcl`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/config.tcl)
defines `LOG_DIR ../logs`, `REPORT_DIR ../reports`, `OUT_DIR ../outputs` as **relative**
paths, and every stage script begins with `source ../scripts/config.tcl`. Launch the tool
from anywhere else and the sources fail or the outputs land somewhere unexpected.

### Measured stage timings

From two real runs on `srv03335` (16 physical cores; `INNOVUS_LOCAL_CPU` defaults to 14
in `config.tcl`):

| stage | wall time |
|---|---|
| `syn` | ~1–2 h |
| `pnr_place` | ~20 min |
| `pnr_cts` | ~53 min |
| `pnr_route` | ~2–3.5 h |
| **place → GDSII** | **~4.5–5 h** |

`pnr_route` is the long pole, and inside it the long pole is post-route optimisation and
hold repair (`opt_design -post_route -hold`), not the router itself. Budget accordingly:
a routing or hold experiment is a half-day, which is exactly why the snapshot DBs below
exist.

---

### Stage 1 — `make syn` (Genus)

```
cd work/ ; genus -f ../../asic-flows/Cadence/1_synthesis.tcl -log ../logs/syn_logs
make cpf-patch
```

Prerequisite targets: `setup_dirs`, `asic-flist` (re-renders the generated sub-flists via
the top-level Makefile), `romlibs-check` (fails fast if the ROM `.lib`/`.lef` files are
absent — Genus would otherwise die inside `set_db` with `Cannot open file
'rom_via_ss_1p08v_1p08v_125c.lib'`).

Script: [`1_synthesis.tcl`](https://github.com/SoC-Labs/ASIC-Flow/blob/b19e7845448e641ea8353b19a59a77257907cb13/Cadence/1_synthesis.tcl).
It sources:

| sourced | what it provides |
|---|---|
| [`scripts/config.tcl`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/config.tcl) | block name, all library/LEF/GDS paths, `soclabs_setup_multi_cpu`, the `check_cpf` wrapper |
| [`scripts/procs.tcl`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/procs.tcl) | `expand_env` — expands `${VAR}` and `$(VAR)` in flists (sourced *by* config.tcl) |
| [`scripts/read_flist.tcl`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/read_flist.tcl) | the RTL, via `$hdl_file_list` |
| `scripts/dft_setup.tcl` | only if `DFT == 1`; **`DFT` is 0** in config.tcl, so the whole scan path is off — and no such file exists in `scripts/` today |

It reads `../inputs/nanosoc_eth_chiplet_pads.upf` (power intent) and
`../inputs/constraints.sdc`, elaborates
`ASIC/tech_wrappers/tsmc65/nanosoc_eth_chiplet_pads.v` as the top, marks all `uPAD*`
cells `dont_touch`, then runs `syn_generic` / `syn_map` / `syn_opt` at high effort.

**Artefacts** (all under `outputs/`, plus reports):

- `nanosoc_eth_chiplet_pads_gate.v` — plain gate netlist
- `nanosoc_eth_chiplet_pads_gate_power.v` — **PG netlist; this is what P&R reads**
- `nanosoc_eth_chiplet_pads_gate1.cpf` — CPF power intent, consumed by `2_pnr_setup.tcl`
- `nanosoc_eth_chiplet_pads_gate2.upf` — UPF power intent
- `nanosoc_eth_chiplet_pads_gate.sdf`, `..._syn.sdc`
- `reports/syn_{area,timing,gates,power}.rep`
- `logs/syn_{lib,cpf,pow}_check.log`
- `work/lec.dofile` (input to `make lec`), `work/nanosoc_eth_chiplet_pads_syn_session` (a Genus DB)

**Post-step: `make cpf-patch`.** `syn` runs this automatically. Genus's
`write_power_intent -cpf` cannot translate this design's UPF supply commands, so the CPF
it writes contains only `create_power_domain -name PD_TOP -default` — no power net, no
ground net. Innovus reads that at `2_pnr_setup.tcl:40` and every filler pass then dies
with `IMPSP-5110: No supply-net names for Power Domain 'PD_TOP'`, `add_fillers` reports
"For 0 new insts", and the die ships with no base-layer fill and no ANTENNA diodes —
silently, with a valid-looking GDSII. `cpf-patch` inserts the `create_power_nets` /
`create_ground_nets` / `update_power_domain` statements before `end_design`. It is
idempotent. See [06-fill-antenna-bondpads](06-fill-antenna-bondpads.md) and
[11-known-issues](11-known-issues.md).

Also note (documented at length in `config.tcl`): `check_cpf` raises `RCLP-203` on this
design and would abort the `-f` script, so `config.tcl` wraps it in a `catch`. Full detail
still goes to `logs/syn_cpf_check.log`; the failure is echoed to stderr. This is
pre-existing and matches the 2026-07 reference run's error counts exactly.

---

### Stage 2 — `make pnr_place` (Innovus)

```
cd work/ ; innovus -stylus -files ../../asic-flows/Cadence/2_pnr_setup.tcl
```

Script: [`2_pnr_setup.tcl`](https://github.com/SoC-Labs/ASIC-Flow/blob/b19e7845448e641ea8353b19a59a77257907cb13/Cadence/2_pnr_setup.tcl). In order:

1. `source ../scripts/config.tcl`, `soclabs_setup_multi_cpu`
2. `set_db init_power_nets {VDD VDDACC VDDIO}` / `init_ground_nets {VSS VSSIO}`
3. `read_mmmc ../scripts/nanosoc_eth_chiplet_pads.mmmc` — the MMMC view set
   (`default_analysis_view_setup` / `_hold`, `typical_analysis_view`, …)
4. `read_physical -lef $lef_file_list` — tech LEF, `tcbn65lp` std cells, TSMC IO,
   the **patched** IO driver LEF (generated, see §above), the six RF/ROM/flash-cache macro LEFs
5. `read_netlist ../outputs/nanosoc_eth_chiplet_pads_gate_power.v`
6. `init_design`, then `read_power_intent -cpf ../outputs/..._gate1.cpf` + `commit_power_intent`
7. `source ../scripts/floorplan.tcl` → die/core box, IO placement from
   `nanosoc_eth_chiplet_pads.io`, IO fillers, macro placement — see [03-floorplan](03-floorplan.md)
8. `source ../scripts/power_plan.tcl` → `connect_global_net`, core rings, stripes,
   `route_special` — see [04-power-plan](04-power-plan.md)
9. `source $env(SOCLABS_ASIC_FLOW_DIR)/Cadence/procs.tcl` → `report_intermediate_step` /
   `report_end_step`
10. `report_intermediate_step 00_pre_place`
11. `source ../scripts/preplace.tcl` → congestion/timing effort, uniform density,
    legalisation gap
12. **`place_design`**
13. `report_end_step 01_place`
14. `source ../scripts/postplace.tcl` → `write_sdf design.sdf -ideal_clock_network`,
    `add_tieoffs -lib_cell {TIEL TIEH}`
15. `write_db nanosoc_eth_chiplet_pads`

**Artefacts:** `work/nanosoc_eth_chiplet_pads/` (the shared DB), `work/design.sdf`,
`reports/timing_summary_00_pre_place.rep`, `reports/timing_summary_01_place.rep`,
`reports/timing_01_place_{early,late}.rep`, `reports/power_01_place.rep`,
`reports/qor_01_place.rep`.

`SOCLABS_ASIC_FLOW_DIR` **must** be exported (step 9 sources through it). It is set by
[`ASIC/common.mk`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/common.mk); nothing else in the repo sets it. Running the
script by path without that export aborts the stage.

---

### Stage 3 — `make pnr_cts` (Innovus)

```
cd work/ ; innovus -stylus -files ../../asic-flows/Cadence/3_pnr_clock.tcl
```

Script: [`3_pnr_clock.tcl`](https://github.com/SoC-Labs/ASIC-Flow/blob/b19e7845448e641ea8353b19a59a77257907cb13/Cadence/3_pnr_clock.tcl).

1. `source ../scripts/config.tcl`, `soclabs_setup_multi_cpu`
2. **`read_db nanosoc_eth_chiplet_pads`** — picks up exactly what stage 2 wrote
3. `source .../procs.tcl`
4. `source ../scripts/cts_setup.tcl` → **first statement writes the `_placed` snapshot**
   (see below), then `set_db cts_delay_cells {DEL*}`
5. `create_clock_tree_spec -out_file design_clk.spec`
6. **`ccopt_design`**
7. `report_intermediate_step 02_cts`
8. `opt_design -post_cts` then `opt_design -post_cts -hold`
9. `report_end_step 03_cts_opt`
10. `write_db nanosoc_eth_chiplet_pads`

**Artefacts:** the updated shared DB, `work/nanosoc_eth_chiplet_pads_placed/` (snapshot),
`work/design_clk.spec`, `reports/timing_summary_02_cts.rep`,
`reports/timing_summary_03_cts_opt.rep` (**the target's assertion**),
`reports/timing_0{2,3}_*_{early,late}.rep`, `reports/power_03_cts_opt.rep`,
`reports/qor_03_cts_opt.rep`.

`cts_setup.tcl` deliberately leaves `cts_buffer_cells` / `cts_inverter_cells` commented
out — see its own comment and [05-place-cts-route](05-place-cts-route.md).

---

### Stage 4 — `make pnr_route` (Innovus)

```
cd work/ ; innovus -stylus -files ../../asic-flows/Cadence/4_pnr_route.tcl
```

Script: [`4_pnr_route.tcl`](https://github.com/SoC-Labs/ASIC-Flow/blob/b19e7845448e641ea8353b19a59a77257907cb13/Cadence/4_pnr_route.tcl). This is the
stage that emits the GDSII.

1. `source ../scripts/config.tcl`, `read_db nanosoc_eth_chiplet_pads`, `source .../procs.tcl`
2. If `CALIBRE_HOME` is set, source Calibre's `cal_enc.tcl`
3. `source ../scripts/route_setup.tcl` → **first statement writes the `_cts` snapshot**,
   then clock-net extra spacing, multi-cut via effort, timing-driven + SI-driven route,
   `timing_analysis_type ocv`
4. **`route_design -global_detail`**
5. `report_intermediate_step 04_route`
6. **`opt_design -post_route -hold`** ← the long pole
7. `report_end_step 05_route_opt`
8. `write_db nanosoc_eth_chiplet_pads`
9. `source ../scripts/place_bondpads.tcl` → which first sources
   [`scripts/filler.tcl`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/filler.tcl) (filler + ANTENNA
   diodes, *after* routing — see [06-fill-antenna-bondpads](06-fill-antenna-bondpads.md)),
   then creates the `PAD70GU`/`PAD70NU` staggered bond pads
10. `check_drc`, `check_filler`, `check_connectivity`, `check_process_antenna` → `reports/`
11. Timing reports across analysis views
12. **`write_stream ../outputs/nanosoc_eth_chiplet_pads.gds`** with the TSMC GDS-out map
    and `-merge $gds_merge_list` (the macro GDS2s)
13. `report_area`, `report_power`
14. `write_netlist ../outputs/..._pnr.v`, `write_sdf ../outputs/..._pnr.sdf`
15. `write_db nanosoc_eth_chiplet_pads` (again — this is the final DB)
16. If `CALIBRE_HOME` is set, `exec calibre -drc -hier -turbo 8 $drc_ruledeck`

**Artefacts:** `outputs/nanosoc_eth_chiplet_pads.gds` (**the assertion**),
`outputs/..._pnr.v`, `outputs/..._pnr.sdf`,
`reports/timing_summary_04_route.rep`, `reports/timing_summary_05_route_opt.rep`,
`reports/nanosoc_eth_chiplet_pads_imp_{drc,filler,connectivity,antenna}.rep`,
`reports/..._imp_{area,power}.rep`, `reports/..._imp_timing_*.rep`, and the final DB.

Two things to know about this stage:

- The `timing_full_*.mtarpt` files are written to the **current directory**, i.e.
  `work/`, not `reports/` — the script uses a bare relative path for those.
- The in-script Calibre run at step 16 is a no-op in practice (it passes only the
  ruledeck, whose `LAYOUT PATH` / `LAYOUT PRIMARY` are placeholders). Use `make drc`,
  which drives Calibre through a project-owned wrapper deck that resolves both. See
  [09-signoff-checklist](09-signoff-checklist.md).
- This stage needs `ASIC/asic-flows` at **`b19e784` or later**. The earlier revision stops
  after routing and writes no stream at all — the failure mode is a clean-looking log and
  no GDS.

---

## The resume model: one DB, three stages

All three Innovus stages read and write the **same** database name, `nanosoc_eth_chiplet_pads`,
inside `work/`:

```
pnr_place :                              ... write_db nanosoc_eth_chiplet_pads
pnr_cts   : read_db nanosoc_eth_chiplet_pads ... write_db nanosoc_eth_chiplet_pads
pnr_route : read_db nanosoc_eth_chiplet_pads ... write_db nanosoc_eth_chiplet_pads
```

Two consequences:

1. **They must run in order and cannot be parallelised.** Each one's input is the previous
   one's output.
2. **Any stage can be re-invoked to resume.** The state lives in `work/`, not in `make`.
   If `pnr_cts` fell over, fix the cause and run `make pnr_cts` again — it re-reads the
   post-place DB and carries on. There is no stamp file to clear and no need to re-run
   placement.

`make status` (below) tells you where a part-finished flow stopped.

### The snapshot DBs, and why they exist

Because every stage writes the same name, each stage **overwrites the previous state**.
Without intervention, only the final post-route DB survives, and any experiment on CTS,
routing or hold repair costs a full re-run from placement (~4.5–5 h) instead of a resume
(~1 h). Two snapshots fix that:

| snapshot | written by | at what point | contains |
|---|---|---|---|
| `nanosoc_eth_chiplet_pads_placed` | [`cts_setup.tcl`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/cts_setup.tcl), first line | sourced by `3_pnr_clock.tcl` immediately after its `read_db` | exactly the **post-place** state |
| `nanosoc_eth_chiplet_pads_cts` | [`route_setup.tcl`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/route_setup.tcl), first line | sourced by `4_pnr_route.tcl` immediately after its `read_db` | exactly the **post-CTS** state |
| `nanosoc_eth_chiplet_pads` | every stage | end of each stage | the **latest** state — post-place, then post-CTS, then post-route |

The placement is deliberate: each snapshot is taken by the *consuming* stage, right after
it loads the DB and before it changes anything, so the snapshot is guaranteed to be the
clean hand-off state rather than "whatever the producing stage happened to leave".

Cost is trivial — the three DBs on disk today are 47 MB (`_placed`), 57 MB (`_cts`) and
61 MB (current). Disk is not the constraint here; a 5-hour re-run is.

To open a snapshot instead of the live DB, see
[02-innovus-basics](02-innovus-basics.md#loading-a-snapshot-instead-of-the-final-db).

---

## Housekeeping targets

### `make status`

The fastest way to see where a part-finished flow stopped. It reads **artefacts on disk**,
not stamp files, so it is honest about a flow that half-ran:

```
$ make status
== nanosoc_eth_chiplet_pads ==
  STAGE          OK   ARTEFACT
  flist          yes  .../build/chip/flist/soc.flist
  romlibs        yes  .../ASIC/romlibs/cc_rom/rom_via.lef
  syn            yes  .../outputs/nanosoc_eth_chiplet_pads_gate_power.v
  place          yes  .../reports/timing_summary_01_place.rep
  cts            yes  .../reports/timing_summary_03_cts_opt.rep
  route          --   .../reports/timing_summary_05_route_opt.rep
  gds            --   .../outputs/nanosoc_eth_chiplet_pads.gds
  pnr-netlist    --   .../outputs/nanosoc_eth_chiplet_pads_pnr.v
  drc            --   .../work/drc_run
```

(Illustrative — run it for the real state.) It is cheap and touches no tool licence.

### `make help`

The default goal. Bare `make` used to run `setup_dirs` — just `mkdir` — and report success
having done nothing recognisable; it now prints the target list, the ordering rule, and
the two env vars the flow needs (`TSMC_65_HOME`, `SOCLABS_ASIC_FLOW_DIR`, both exported by
[`common.mk`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/common.mk)).

### `make clean` vs `make distclean`

| target | removes | keeps |
|---|---|---|
| `clean` | `work/` and `logs/` — the rerunnable intermediates, including all three DBs | **`outputs/` and `reports/`** — a finished GDS and its sign-off reports survive |
| `distclean` | `work/`, `logs/`, `outputs/`, `reports/` | nothing — **this deletes the GDS** |

`distclean` prints what it is about to destroy (including the GDS and its size) before
doing it. `clean` forces a full P&R re-run from `make pnr_place`, but leaves synthesis
outputs intact, so you do not pay the Genus hour again.

### `make romlibs-fetch`

Copies the built ROM libraries (`cc_rom/`, `eth_rom/`) into `ASIC/romlibs/` from a
reference tree, then re-runs `romlibs-check`.

```
make romlibs-fetch                       # from the default ROMLIBS_REF
make romlibs-fetch ROMLIBS_REF=<path>    # from somewhere else
```

**This exists because the ROM libraries cannot be rebuilt on `srv03335`.** Every Arm
memory compiler on this host starts up and prints `Available generators are: .` — it
lists none, so it cannot emit a `.lib`. `common.mk` documents the investigation at length
(it is not the install copy, not NFS, not the JRE; the same install worked here on
27 Apr 2026, before the RHEL 8.8 → 8.10 upgrade). Until an admin fixes it, fetching a
pre-built tree is the only route. `ASIC/romlibs/` is not a free choice of location —
`config.tcl` puts exactly that path on `lib_search_path_list`.

The four files Genus actually needs, and that `romlibs-check` / `romlibs-verify` assert on:

```
ASIC/romlibs/cc_rom/rom_via_ss_1p08v_1p08v_125c.lib
ASIC/romlibs/cc_rom/rom_via.lef
ASIC/romlibs/eth_rom/eth_rom_via_ss_1p08v_1p08v_125c.lib
ASIC/romlibs/eth_rom/eth_rom_via.lef
```

### Other targets worth knowing

| target | what it does |
|---|---|
| `make gui` | Innovus **with the design loaded** — see [02-innovus-basics](02-innovus-basics.md) |
| `make pnr_setup` | Innovus interactive in `work/`, **empty session** (no config, no DB) |
| `make asic-flist` | re-render the generated sub-flists (delegates to the top-level Makefile, which sources the `set_env.sh` scripts in dependency order) |
| `make cpf-patch` | repair the Genus-written CPF; idempotent; run automatically by `syn` |
| `make romlibs-check` | assert the four ROM files exist, with an explanation if not |
| `make drc` | Calibre DRC on the built GDS, headless, via the project's wrapper deck |
| `make lec` | Conformal LEC on the dofile synthesis wrote |
| `make syn_norun` | Genus interactive in `work/` |

`GDS` is `?=`, so DRC can be pointed at a stream built elsewhere:
`make drc GDS=/path/to/other.gds`.

---

## Environment

`ASIC/common.mk` exports everything the flows need, with `?=` throughout so a sourced
`set_env.sh` or a CI export still wins. The ones that bite if missing:

| var | default | why it matters |
|---|---|---|
| `TSMC_65_HOME` | `$TSMC_65_HOME` | every std-cell / IO / tech-LEF path in `config.tcl` hangs off it. Group-shared PDK, **read-only** |
| `PHYS_IP` | `$PHYS_IP` | Arm phys-IP. **Read-only** |
| `SOCLABS_ASIC_FLOW_DIR` | `<repo>/ASIC/asic-flows` | stages 2–4 `source` through it; nothing else sets it |
| `NANOSOC_ETH_CHIPLET_HOME` | repo root | `config.tcl` builds the ROM-lib, top-HDL and patched-IO-LEF paths from it |
| `TIDELINK_HOME`, `TIDECHART_HOME` | repo subdirs | without them Genus reads the whole SoC and *then* dies at the end of `read_flist.tcl`, ~10 min in |
| `CALIBRE_HOME` | unset | if set, `4_pnr_route.tcl` sources Calibre's Tcl and runs `exec calibre` at the end |
| `INNOVUS_LOCAL_CPU` | `14` | `set_multi_cpu_usage -local_cpu`. Distribution is off by default and should stay off — the measured inter-host link is ~25 MB/s |

Never write under `$TSMC_65_HOME/**` or `$IP_LIBRARY_ROOT/**`. Where the flow needed a fix in
vendor collateral — the IO driver LEF, which declares its supply pins without
`USE POWER ;` / `USE GROUND ;` — the fix is applied to a **generated copy**:
`patch_pad_lef.py` reads the vendor file from `$TSMC_65_HOME`, inserts three lines, and
writes `ASIC/tech_wrappers/tsmc65/generated/`, which is gitignored and rebuilt by
`make -C ASIC -f common.mk pad-lef`. `config.tcl` points there. That deviation is
documented in `config.tcl` itself. See [04-power-plan](04-power-plan.md) for why it
mattered (76 DRC violations from VDDIO/VSSIO being routed as ordinary signal nets).

**Follow the pattern, not the old location.** This repository is public and TSMC's licence
forbids reproducing their collateral, so the rule for any future vendor-file fix is *ship
the transform, not the result* — commit a script that derives the patched file from the
read-only PDK, and gitignore its output. A verbatim copy of this LEF was committed here
until `bf619f1`, under `ASIC/tech_wrappers/tsmc65/local_overrides/`; that is what the older
descriptions elsewhere in these docs are referring to, and it is no longer the live path.
See [29-private-tsmc-tech-repo](29-private-tsmc-tech-repo.md) §2a.
