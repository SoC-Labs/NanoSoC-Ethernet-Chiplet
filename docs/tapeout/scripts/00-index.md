# Flow Script Reference

> **Status — which of these scripts still build the chip.** These pages annotate
> `ASIC/genus-innovus/scripts/`. Since 2026-08-13 the *stage drivers* (synthesis, place,
> CTS, route) come from the `ASIC/asic-toolkit` submodule instead, driven from
> `ASIC/eth-chiplet/`. The **design inputs are still these files**: `ASIC/eth-chiplet/design.mk`
> points `FLOORPLAN_TCL`, `POWER_PLAN_TCL`, `BONDPADS_TCL`, `MMMC_FILE`, `IO_FILE`,
> `POWER_INTENT`, `SDC_FILES` and `DRC_SCRIPT` at `ASIC/genus-innovus/` (see `LEGACY_ASIC_DIR`,
> `design.mk:69`). So pages 04–07 here describe live inputs; the stage-driver material in
> pages 01–03 describes the engine that has been superseded — read it for the *why*, and
> check `design.mk` before assuming a variable still resolves here.
> Background: [33](../33-toolkit-legacy-decoupling.md), [41](../41-retiring-asic-flows.md).

Line-by-line annotation of every script in the Cadence Genus + Innovus flow under
`ASIC/genus-innovus/`, with each command referred to the installed Cadence manual for
the tool version actually in use.

This is the **mechanical companion** to the [tapeout guide](../00-index.md). That guide
explains the concepts and the operational method; these pages explain what each line of
each script literally does, why it is there, and — where they disagree — how the script
departs from the manual.

---

## Which manual these pages cite

The flow runs Innovus in **stylus (Common UI)** mode. That matters more than it sounds:
the Common UI and the legacy UI are different command sets with separate manuals, both
installed on this site.

| Set | Path | Use |
|---|---|---|
| **Common UI (stylus)** | `$INNOVUS_HOME/doc/TCRcom/`, `UGcom/` | **The one this flow uses** |
| Legacy UI | `$INNOVUS_HOME/doc/innovusTCR/`, `innovusUG/` | Different commands; cited only to prove an absence |
| Genus | `$CDS_INSTALL/genus/doc/genus_comref/`, `genus_attref/`, `genus_lowpower/` | Synthesis stage |
| Messages | `$INNOVUS_HOME/doc/EMRcom/`, `innovuserrmsg/` | Message IDs — **selective**, many IDs have no page |

`innovusTCR/create_floorplan.html` does not exist; `TCRcom/create_floorplan.html` does.
If you are reading a page that cites the legacy tree for a command this flow calls, that
citation is wrong.

Every page cites only manual entries that were opened and read. Where a message ID has no
installed page — `IMPSP-5110`, `IMPDB-1221` and others are in this category — the pages say
so and fall back to the message catalogue or run-log text rather than inventing a
reference. Tool version: **Innovus 21.11-s130_1**. The installed *message* reference is
21.10, one version behind the tool.

---

## Pages

| # | Page | Scripts covered |
|---|---|---|
| 01 | [Stage scripts and Makefile](01-stage-scripts-and-makefile.md) | `Makefile`, `common.mk`, and the four `asic-flows/Cadence/*_pnr_*.tcl` stages — **start here for how it hangs together** |
| 02 | [Config and filelists](02-config-and-filelists.md) | `config.tcl`, `read_flist.tcl`, `procs.tcl` |
| 03 | [MMMC, SDC and power intent](03-mmmc-sdc-and-power-intent.md) | `*.mmmc`, `inputs/*.sdc`, `.upf`, `.cpf` |
| 04 | [Floorplan and IO](04-floorplan-and-io.md) | `floorplan.tcl`, `*.io`, `preplace.tcl`, `postplace.tcl`, `probe_macros.tcl` |
| 05 | [Power plan](05-power-plan.md) | `power_plan.tcl` |
| 06 | [CTS and route](06-cts-and-route.md) | `cts_setup.tcl`, `route_setup.tcl`, and the CTS/route commands in the stage scripts |
| 07 | [Filler and bond pads](07-filler-and-bondpads.md) | `filler.tcl`, `place_bondpads.tcl`, stream-out |
| 08 | [Portability refactor](08-portability-refactor.md) | Not a script page — what a second SoC would have to write, and a ranked plan |

Read **01** first regardless of what you came for. The stage graph, the `read_db`/`write_db`
resume model and the `cwd = work/` convention are assumed by every other page.

---

## Defects these pages surfaced

Writing the annotation turned up a number of things that were not previously recorded.
They are documented in full on the pages listed, and are collected here because several
are actionable independently of the documentation.

Items marked **[verified]** were confirmed directly against the repository, the logs or
the LEF, not merely inferred from reading the script.

### Silently ineffective

- **`+define+` lines are dropped by `read_flist.tcl`.** **[verified]** The parser has no
  `+define+` branch, so `+define+ETH_WISHBONE_B3` in `build/chip/flist/soc.flist:117` never
  reaches Genus, while VCS — reading the same flist — honours it. `eth_defines.v:320` has
  the `` `define `` commented out, so the command line is the only source. It gates live
  logic in `eth_top.v` and `eth_wishbone.v`: **synthesis and simulation build different
  designs.** `TIDELINK_PHY_V2` is honoured only because it is hardcoded onto the `read_hdl`
  line — the same bug, patched once for one define instead of fixed in the mechanism.
  See [02](02-config-and-filelists.md).
- **`set_route_attributes -nets clk` has never matched anything.** **[verified]** The logs
  carry `NRDB-537) Cannot find net clk` in every run. `clk` is an SDC clock object, not a
  net; the manual's form is `-nets @CLOCK`. Clock nets have had no extra routing spacing,
  despite the `### Clock Net Spacing` heading. See [06](06-cts-and-route.md).
- **`create_clock_tree_spec -out_file` writes a spec nothing loads.** The manual states
  "The file is not executed"; the flow never sources it and `ccopt_design` regenerates it
  internally. Editing `work/design_clk.spec` by hand does nothing. See
  [06](06-cts-and-route.md).
- **`-pad_pin_width 6`** (`power_plan.tcl:166`) matches no pin in the IO LEF, whose PG
  pad-pin widths are `{1.5 1.56 1.63 1.84 2.505 3.0 3.7 3.725 3.75 4.0 4.5 22.0 53.0}`.
  Neighbouring passes use 1.63 and 1.5, which are exactly the M1/M2 finger widths of
  `PVDD1DGZ_G` VDD and `PVSS1DGZ_G` VSS — which is why those passes are split. See
  [05](05-power-plan.md).
- `set_db init_hdl_search_path` **replaces rather than appends**, so of 20 `+incdir+`
  lines only one is ever live. See [02](02-config-and-filelists.md).
- The `-y` branch of `read_flist.tcl` calls `set_app_var`/`get_app_var` — **[verified]**
  Synopsys DC commands that exist in no Cadence manual. Dead only because the flist chain
  currently has no `-y` lines. See [02](02-config-and-filelists.md).

### Constraints

- **`rmii_ref_clk` gets 0.35 ns of hold uncertainty.** **[verified]**
  `ethernet_constraints.sdc:24` calls `set_clock_uncertainty` **unqualified**, so it lands
  on hold as well as setup. `constraints.sdc:61-64` deliberately splits these for `EXTCLK`
  and `SWDCLK` (`-setup 0.35` / `-hold 0.05`) with an explicit rationale calling the hold
  value a signoff margin. The third clock never got the fix — and it is where post-route
  hold now hurts. This removes 0.30 ns of fictitious hold requirement from the rmii domain;
  it is not a fix for the design-wide hold failure. See
  [03](03-mmmc-sdc-and-power-intent.md) and [16](../16-open-defects.md).
- **`set_clock_groups -asynchronous` supersedes the earlier exceptions.** **[verified]**
  `$EXTCLK` and `$SWDCLK` land in different groups at `constraints.sdc:126`, making all
  paths between them false — which renders the four `set_multicycle_path` lines at 70-73
  and the inter-clock uncertainty at 66-67 dead. Not harmful, but they read as live.
- **24 of 26 macro `connect_supply_net` lines in the UPF name an instance path that does
  not exist.** The macros are connected only by `power_plan.tcl`'s global net rules.
  `check_cpf` logs it; nothing reads that log.

### Never run

- **No PG verification command appears anywhere in the flow.** **[verified]** Neither
  `check_power_vias`, `check_pg_shorts`, `check_design -type power_intent` nor
  `check_endcaps` is invoked in the project scripts or the stage scripts — on a design with
  **329 unexplained PG opens** ([15](../15-pg-opens-analysis.md)). Two API traps to avoid
  on the first attempt: it is `check_power_vias`, not `verify_power_via`, and
  `-type power_intent`, not `-type power`. See [05](05-power-plan.md).
- **Metal fill is absent entirely.** **[verified]** No fill or density command in
  `scripts/`, `asic-flows/` or the Makefile — while the tech LEF already carries
  `MINIMUMDENSITY`/`DENSITYCHECKWINDOW` for every layer — with different floors, caps and
  window sizes for the thin metals, the upper metals and AP (values not reproduced — TSMC
  licence). The in-tree nanoSoC 28-pin ancestor flow *does* run `add_metal_fill` for this
  same PDK. See [07](07-filler-and-bondpads.md).
- **`DFT 1` cannot work.** **[verified]** `1_synthesis.tcl:51` sources
  `../scripts/dft_setup.tcl` under `if {$DFT == 1}`, and that file exists nowhere in the
  tree. Four more `DFT == 1` branches sit across the stage scripts. See
  [01](01-stage-scripts-and-makefile.md).

### The exit-0 trap has a documented cure

Both tools accept **`-abort_on_error`** and **`-batch`**, and neither is used.

> `-abort_on_error` — Exits if an error is detected at any point. If any Tcl command
> returns TCL_ERROR to the top level, or any `Error (XXX): ...` message occurs, the process
> will exit. — *Innovus Text Command Reference, `innovus`*

Genus's manual names this flow's exact failure mode: *"Use the `genus -abort_on_error -f
<your script>` command to specify that Genus automatically quit if a script error is
detected when reading in HDL files instead of holding at the `genus:root:>` prompt."*

Between them these address the root cause of three separately-documented workarounds: the
`test -s` artefact assertions, the `-f` versus `-files` silent pass, and the `env -u
CALIBRE_HOME` hang that holds a Cadence seat.

!!! warning "Do not enable this blind"
    `-abort_on_error` exits on *any* `Error (XXX)` message, and this design deliberately
    tolerates several — the `check_cpf` wrapper at `config.tcl:51-67` exists specifically
    to swallow 91 pre-existing low-power rule errors so synthesis can proceed. Enabling
    abort-on-error could undo exactly the tolerance the flow depends on. Try it one stage
    at a time, and keep the artefact assertions as defence in depth.

### Duplication worth removing

- **The 82 bond-pad names in `place_bondpads.tcl` are exactly the `.io` ring order
  de-interleaved by parity.** **[verified]** `*_outer` is the even-indexed entries and
  `*_inner` the odd, exact on all four sides. That *is* the stagger mechanism — and nothing
  documents it, so the lists go stale undetectably if the `.io` file changes. See
  [07](07-filler-and-bondpads.md).
- The `.io` file's header claims it is `Auto-generated by nanosoc_gen SoCPadRingBackend`,
  but its own `Design:` field names a **different chip**, and nothing regenerates it. It is
  hand-maintained. See [04](04-floorplan-and-io.md).
- `power_plan.tcl` contains one 19-line `set_db` block written **twice**, byte-identical.

### Corrections to existing pages

- `create_relative_floorplan`'s placement triple is `{ref_edge y_offset obj_edge}`, not
  `{left centre right}`.
- `PAD70NU`'s obstruction is five shapes spanning −14…+44 µm, not the single
  `RECT 0 0 30 171` recorded in `floorplan.tcl`.
- `add_stripes_ignore_block_check`'s documented polarity is the reverse of its name;
  [04-power-plan](../04-power-plan.md) describes it backwards.
- The 95,568 free-sites / 5.9 % pair quoted for the filler failure is arithmetically
  inconsistent — 95,568 sites is ~1.7 % of core; 5.9 % matches the fill *area*.

---

## Conventions

- Quoted line numbers refer to the file **as committed**, and are given as `file.tcl:NN`.
- Manual citations name the manual and the page file, e.g.
  *Innovus Text Command Reference — `add_stripes` (`TCRcom/add_stripes.html`)*.
- Numbers described as measured come from real runs on `srv03335`. Anything inferred is
  labelled as inference.
- Where a number was read from `ASIC/genus-innovus/work/` it may reflect a run that was
  still in progress; those are flagged in place.
