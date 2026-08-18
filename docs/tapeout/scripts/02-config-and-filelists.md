# scripts/02 — Config and filelists: `config.tcl`, `read_flist.tcl`, `procs.tcl`

**What this page is for.** A line-by-line reference for the three files that make up the
*configuration layer* of the Cadence flow: everything the tool knows about this design
before a single command of real work runs. It quotes the actual lines with their line
numbers, explains what each construct does, and cites the Cadence manuals installed on
this machine for every tool command and attribute involved.

It is the companion to [01-flow-overview](../01-flow-overview.md) (what the stages *are*)
and [02-innovus-basics](../02-innovus-basics.md) (how to drive the tool interactively).
Those pages describe behaviour; **this page describes the source**. Where the two overlap
this page links rather than repeats.

Files covered, all under `ASIC/genus-innovus/scripts/`:

| file | lines | role |
|---|---|---|
| [`config.tcl`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/config.tcl) | 259 | every path, library, net name and CPU setting the flow uses |
| [`read_flist.tcl`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/read_flist.tcl) | 46 | recursive simulator-filelist parser that feeds `read_hdl` |
| [`procs.tcl`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/procs.tcl) | 25 | `expand_env` — the `${VAR}` / `$(VAR)` expander the parser depends on |

Tools: **Genus 21.1** for synthesis, **Innovus v21.11-s130_1** in Stylus mode for P&R.

---

## Contents

- [Why this layer is constrained: two interpreters, one file](#why-this-layer-is-constrained-two-interpreters-one-file)
- [A note on the manuals installed here](#a-note-on-the-manuals-installed-here)
- [`config.tcl`, block by block](#configtcl-block-by-block)
  - [L1–3 — the preamble](#l13-the-preamble)
  - [L5–67 — the `check_cpf` wrapper](#l567-the-check_cpf-wrapper)
  - [L69 — `hdl_file_list`](#l69-hdl_file_list)
  - [L71–86 — the library search path](#l7186-the-library-search-path)
  - [L88–112 — `syn_lib_list` and what a `.lib` is](#l88112-syn_lib_list-and-what-a-lib-is)
  - [L114–126 — block name, directories, top, SDC, DFT, PG nets](#l114126-block-name-directories-top-sdc-dft-pg-nets)
  - [L129–186 — the LEF list, and the local-override IO driver LEF](#l129186-the-lef-list-and-the-local-override-io-driver-lef)
  - [L188–207 — the GDS merge list](#l188207-the-gds-merge-list)
  - [L209 — the DRC ruledeck](#l209-the-drc-ruledeck)
  - [L211–260 — multi-CPU and `soclabs_setup_multi_cpu`](#l211260-multi-cpu-and-soclabs_setup_multi_cpu)
- [`read_flist.tcl` — the filelist parser](#read_flisttcl-the-filelist-parser)
- [`procs.tcl` — `expand_env`](#procstcl-expand_env)
- [What a reader must supply](#what-a-reader-must-supply)
- [Defects and divergences found while writing this page](#defects-and-divergences-found-while-writing-this-page)
- [Manual pages cited](#manual-pages-cited)

---

## Why this layer is constrained: two interpreters, one file

`config.tcl` is sourced by **both** tools:

| sourced by | tool | line |
|---|---|---|
| [`1_synthesis.tcl`](https://github.com/SoC-Labs/ASIC-Flow/blob/b19e7845448e641ea8353b19a59a77257907cb13/Cadence/1_synthesis.tcl) | Genus | `14: source ../scripts/config.tcl` |
| [`2_pnr_setup.tcl`](https://github.com/SoC-Labs/ASIC-Flow/blob/b19e7845448e641ea8353b19a59a77257907cb13/Cadence/2_pnr_setup.tcl) | Innovus | `14: source ../scripts/config.tcl` |
| `3_pnr_clock.tcl` | Innovus | (same, before its `soclabs_setup_multi_cpu` at line 16) |
| `4_pnr_route.tcl` | Innovus | (same, before its `soclabs_setup_multi_cpu` at line 15) |

Genus and Innovus are both Tcl, but they are **different Tcl interpreters with disjoint
command sets and disjoint attribute namespaces**. That imposes three rules on anything
written in this file:

1. **Only plain Tcl runs unconditionally.** `set`, `list`, `foreach`, `proc`, `expr`,
   `rename`, `info`, `catch` — these are core Tcl and exist in both. Everything else is
   a bet on which tool is reading.

2. **Any tool-specific command must be guarded before it is used**, and the guard must be
   the *plain-Tcl* `info commands`, not a `catch` around the call. `config.tcl` does this
   in exactly two places: the `check_cpf` wrapper (L51–52) and the distribution branch of
   `soclabs_setup_multi_cpu` (L247). Both are load-bearing, and both are verified against
   the manuals below: `check_cpf` does not appear anywhere in the Innovus Stylus Common UI
   command reference or user guide, and `set_distributed_hosts` does not appear anywhere in
   the Genus documentation.

3. **Tool-specific *attributes* are worse than commands**, because a bad `set_db` aborts
   the source. The file's own comment (L18–25) records this: `clp_treat_errors_as_warnings`
   is a Genus root attribute, and under Innovus a `set_db` on it fails with `IMPDBTCL-247`
   and takes the whole file down. The consequence is that this file **contains no `set_db`
   at all** — every setting is exported as a plain Tcl variable and applied by the stage
   script that knows which tool it is running under. That is why `2_pnr_setup.tcl` reads:

   ```tcl
   20: set_db init_power_nets $power_nets
   21: set_db init_ground_nets $ground_nets
   27: read_physical -lef $lef_file_list
   44: set_db design_process_node $process_node
   ```

   and `1_synthesis.tcl` reads:

   ```tcl
   20: set_db init_lib_search_path $lib_search_path_list
   22: set_db -verbose [get_db library_domains domain1] .library $syn_lib_list
   ```

   Same data, two different attribute names, applied on the correct side of the fence.
   (`init_power_nets`, `init_ground_nets` and `design_process_node` are all Stylus root
   attributes — **Innovus Stylus Common UI Text Command Reference — `init` and `design`
   Category Attributes, `TCRcom/init_Category_Attributes.html`,
   `TCRcom/design_Category_Attributes.html`**. Their Genus counterparts
   `init_power_nets` / `init_ground_nets` happen to share a spelling
   (`genus_attref/general.html`) but `init_lib_search_path` does not exist on the Innovus
   side and `init_lef_files` does not exist on the Genus side.)

The one exception is `proc` definitions, which are inert until called —
`soclabs_setup_multi_cpu` is *defined* under both tools and only *does* something
tool-specific when a stage script invokes it.

> **`IMPDBTCL-247` is in none of the three installed Innovus error-message references.**
> Absent from `EMRcom/` (Stylus, 21.10), from `innovuserrmsg/` (legacy, 21.10), and from
> the 16.13 tree at
> `$CDS_INSTALL/2016-17/RHELx86/INNOVUS_16.13.000/doc/innovuserrmsg/`. The claim in
> `config.tcl`'s comment is therefore not verifiable from the manuals on this box — it is
> an observation from a real run, and should be treated as such. `man IMPDBTCL-247` at a
> live `@innovus` prompt may still resolve it; see
> [02-innovus-basics](../02-innovus-basics.md#make-the-tool-document-itself).

---

## A note on the manuals installed here

Everything cited below was opened on this machine. Three things about the install are worth
knowing before you go looking yourself, because they cost time otherwise:

**Innovus ships TWO complete, parallel documentation sets, one per UI.** This is the trap.
Under `$INNOVUS_HOME/doc/` there are:

| set | directories | commands documented |
|---|---|---|
| **Stylus / Common UI** — *what this flow uses* | `TCRcom/` (1533 pages), `UGcom/` (76), `EMRcom/` (1992) | `set_multi_cpu_usage`, `set_distributed_hosts`, `read_physical`, `write_stream`, `connect_global_net`, `read_netlist`, `create_floorplan` … |
| legacy UI | `innovusTCR/` (2078), `innovusUG/` (76), `innovuserrmsg/` (1992) | `setMultiCpuUsage`, `setDistributeHost`, `streamOut`, `globalNetConnect`, `getDistributeHost`, `setStreamOutMode` … |

Neither set is a superset. Spot-checked in both directions: `create_floorplan.html`,
`read_netlist.html`, `write_stream.html` and `set_multi_cpu_usage.html` exist **only** under
`TCRcom/`; `streamOut.html`, `globalNetConnect.html` and `setMultiCpuUsage.html` exist
**only** under `innovusTCR/`. A handful of names (`init_design.html`) appear in both.

Both are Product Version 21.11 and both are complete. Picking the wrong one gives you a
page that describes the right *behaviour* under the wrong *option spellings* —
`-localCpu` vs `-local_cpu`, `-mapFile` vs `-map_file` — which is exactly the failure mode
[02-innovus-basics](../02-innovus-basics.md#stylus-not-legacy-common-ui) warns about for
pasted script snippets. **This flow is Stylus, so every Innovus citation on this page is to
`TCRcom/`, `UGcom/` or `EMRcom/`.** The legacy set is cited exactly twice below, both times
labelled, because it carries a statement its Common UI counterpart does not.

The two sets are not merely renamed copies. Measured differences that matter here:

- `set_multi_cpu_usage`'s `-remote_host` is described as "the number of **remote machines**"
  in `TCRcom/` and "the number of **clients**" in `innovusTCR/`.
- `TCRcom/set_multi_cpu_usage.html` **drops** the legacy page's warning that `-localCpu`
  "cannot be more than the number of CPUs available in the local computer". That caveat
  survives only in `UGcom/`'s prose.
- `EMRcom/NRDB-51.html` and `innovuserrmsg/NRDB-51.html` share a `SUMMARY` but give
  different remedy commands (`convert_special_to_routes` vs `convertSNetToNet`).
- Some message IDs exist in **neither** 21.x set; see the list at the
  [end of this page](#manual-pages-cited).

**Genus's references are chapter-per-file, not command-per-file.** `genus_comref/` has 31
files; `read_hdl` lives inside `inout.html`, `check_cpf` inside `advanced_lps.html`,
`set_multi_cpu_usage` inside `general.html`. Grep for the command name, do not `ls` for it.

Versions, as printed in the page headers:

| manual | version string on the page |
|---|---|
| Innovus **Stylus Common UI** Text Command Reference (`TCRcom/`) | Product Version 21.11, Last Updated in July 2021 |
| Innovus **Stylus Common UI** User Guide (`UGcom/`) | Product Version 21.11, Last Updated in July 2021 |
| Innovus **Stylus Common UI** Error Message Reference (`EMRcom/`) | Product Version 21.10, May 2021 |
| Innovus Text Command Reference / User Guide (legacy, `innovusTCR/`, `innovusUG/`) | Product Version 21.11, Last Updated in July 2021 |
| Innovus Error Message Reference (legacy, `innovuserrmsg/`) | Product Version 21.10, May 2021 |
| Genus Command Reference / Attribute Reference / Message Reference | Product Version 21.1, September 2022 |
| Genus Library Guide | Product Version 21.1, August 2021 |
| LEF/DEF Language Reference | Product Version 5.8, Last Updated in December 2021 |

---

## `config.tcl`, block by block

### L1–3 — the preamble

```tcl
1: source ../scripts/procs.tcl
3: set process_node 65
```

`procs.tcl` is pulled in first because `read_flist.tcl` needs `expand_env` and
`read_flist.tcl` is sourced later by `1_synthesis.tcl`, not by this file. Note the
**relative** path: it only resolves if the tool's CWD is `work/`. That is the same
constraint that makes `LOG_DIR ../logs` work, and it is why every stage `cd`s into `work/`
first — see [01-flow-overview](../01-flow-overview.md#the-four-stages).

`process_node` is consumed once, by `2_pnr_setup.tcl:44` (`set_db design_process_node
$process_node`).

> **Innovus Stylus Common UI Text Command Reference — `design_process_node`
> (`TCRcom/design_Category_Attributes.html`):** "`design_process_node
> ProcessTechnologyValue`. **Default: 90.** Data_type: int, read/write. Specifies the
> process technology value to set for all the applications. **Units in nanometers (nm).**"

So `65` is nanometres, and the tool's default is 90 nm — leaving it unset would silently
mis-model the process. The sibling attribute `design_tech_node` on the same page notes that
"The node value is normally automatically set by `read_physical` while loading the LEF
technology"; `design_process_node` is the explicit override.

It is *also* hardcoded a second time, as a literal, in
[`preplace.tcl:2`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/preplace.tcl)
(`set_db design_process_node 65`). Two sources of truth for the same attribute; changing
`config.tcl` alone would not change the effective value at placement time. Cosmetic today
(both say 65), a trap if the node ever changes.

---

### L5–67 — the `check_cpf` wrapper

This is the single most consequential block in the file and it deserves the space.

#### What `check_cpf` is

> **Genus Command Reference — `check_cpf` (`genus_comref/advanced_lps.html`):**
> "Checks the validity of the CPF rules against the RTL of the design. This enables
> designers to capture any violations of the low power intent of the design early in the
> design cycle. **If no low power rule check errors are detected, the command returns 1.
> If rule check errors are detected, the command returns 0.** In this case, you need to
> make the necessary changes to your CPF file before proceeding further with synthesis.
> To run this command you need to have access to Conformal® Low Power."

It sits between `apply_power_intent` and `commit_power_intent` in the shared synthesis
script — [`1_synthesis.tcl`](https://github.com/SoC-Labs/ASIC-Flow/blob/b19e7845448e641ea8353b19a59a77257907cb13/Cadence/1_synthesis.tcl):

```tcl
37: apply_power_intent
38: check_cpf -detail -license lpgxl > $LOG_DIR/syn_cpf_check.log
39: commit_power_intent
```

Both of those options are documented on the same page: `-detail` "Provides a detailed
report"; `-license string` "Specifies the Conformal license to be used for this command".
So is the redirection — `[> file]` is part of `check_cpf`'s own synopsis, with the option
table entry "`file` | Redirects the report to the specified file". That matters for the
wrapper: `>` and the filename arrive as ordinary arguments in `$args`, so passing them
straight through works. (`config.tcl`'s comment at L56–57 calls this "the call site
redirects stdout"; per the manual it is the command's own redirection option, not shell or
Tcl stdout redirection. The practical effect is the same and the comment's conclusion —
a `puts` on stdout would land in the log file — holds either way.)

#### What RCLP-203 is

> **Genus Message Reference — RCLP-203 (`genus_messages/RCLP_Error_Messages.html`):**
> "Low Power rule check did not finish successfully."
> *What's Next:* "Fix the errors before proceeding further or set the attribute
> `'clp_treat_errors_as_warnings'` appropriately."

It is filed under **Error** messages, not warnings. Genus has a root attribute governing
what an ERROR does to the script:

> **Genus Attribute Reference — `fail_on_error_mesg` (`genus_attref/general.html`):**
> "`fail_on_error_mesg {false | true}`, Default: false. Read-write root attribute. If set
> to true, Genus commands will fail (stop) whenever they produce an ERROR message. This
> behavior applies automatically to all commands implemented in C++. However, for a command
> implemented in Tcl, the attribute has no effect unless the command checks the value of
> this attribute to drive its behavior."

**Note the tension.** The command reference says `check_cpf` *returns 0* on rule-check
errors — a return value, not a raised error. The observed behaviour recorded in
`config.tcl` (L6–10) is that RCLP-203 **aborts the `-f` script**, which is what a raised
Tcl error does, and which is why a `catch` is the right tool. The manual does not document
`check_cpf` raising. Treat the manual's "returns 0" as an incomplete description of a
command that can both return a status *and* raise; the script's account is the one backed
by a real run.

#### What the file says, verbatim

```tcl
 5: # ── check_cpf must not abort the script ─────────────────────────────────────
 6: # 1_synthesis.tcl runs `check_cpf` between apply_power_intent and
 7: # commit_power_intent. On this design it reports 91 low-power rule errors and
 8: # raises RCLP-203, which ABORTS the -f script. Genus then drops to its
 9: # interactive prompt and, because an unattended run has stdin on /dev/null,
10: # exits 0 having written no netlist.
```

That exit-0 behaviour is the flow's defining hazard and is documented at length in
[01-flow-overview](../01-flow-overview.md#read-this-first-both-tools-exit-0-on-failure).
The `read_hdl` page names the escape hatch for the *general* case:

> **Genus Command Reference — `read_hdl` (`genus_comref/inout.html`):** "Use the
> `genus -abort_on_error -f <your script>` command to specify that Genus automatically
> quit if a script error is detected when reading in HDL files instead of holding at the
> `genus:root:>` prompt."

That converts the silent exit-0 into a real failure, but it does not make `check_cpf`
survivable — it makes it fatal *loudly*. The flow wants the opposite.

```tcl
18: # clp_treat_errors_as_warnings is the remedy the RCLP-203 text names. Do NOT
19: # reach for it: it is accepted by Genus but does NOT stop check_cpf raising on
20: # this design (verified — a run that set it aborted at the same line with the
21: # same four Severity: Error blocks), AND it is a Genus-only root attribute, so
22: # under Innovus it fails with IMPDBTCL-247 and takes this whole file down with
23: # it.
```

The "Genus-only root attribute" half is confirmed:

> **Genus Attribute Reference — `clp_treat_errors_as_warnings` (`genus_attref/inout.html`):**
> "`clp_treat_errors_as_warnings string`. Read-write root attribute. **Forces Conformal Low
> Power (CLP) to treat the specified error message IDs as warnings.**"

**This is a correction to the comment, and it is the most useful thing on this page.** The
attribute's type is **`string`**, and its documented semantics are *"the specified error
message IDs"* — it is a **filter list of CLP message IDs**, not a boolean switch. A run
that set it to `true` / `1` would be setting a message-ID list to the literal string
`true`, which matches nothing, which is exactly the observed "accepted by Genus but does
not stop check_cpf raising". The comment's *conclusion* (do not reach for it) still stands
for the portability reason — but its *reason* ("it does not work") is more precisely "it
was almost certainly not given the right kind of value". Two further caveats before anyone
tries again: the attribute acts on **CLP's** error IDs, whereas RCLP-203 is **Genus's own**
message about the check not finishing; and setting it here would still be a Genus-only
`set_db` in a file Innovus sources. *(Inference, from the attribute type and the RCLP-203
text; not re-run.)*

**There is also a third option the comment never mentions**, and it is on the same manual
page as `check_cpf` itself:

> **Genus Command Reference — `check_cpf` (`genus_comref/advanced_lps.html`):**
> "`-continue_on_error` — Allows the tool to continue when low power rule check errors are
> encountered."

A per-invocation option, no root attribute, no interpreter-portability problem. It cannot
be used *as written* because the call site is in
[`1_synthesis.tcl`](https://github.com/SoC-Labs/ASIC-Flow/blob/b19e7845448e641ea8353b19a59a77257907cb13/Cadence/1_synthesis.tcl), which lives in the
shared `asic-flows` submodule that other designs use — and the file says so at L45–46
("Set here, in the project's own config, rather than in the shared asic-flows
1_synthesis.tcl, which other designs use"). But the *wrapper* could inject it:

```tcl
proc check_cpf {args} { _check_cpf_unwrapped -continue_on_error {*}$args }
```

That would be the vendor-sanctioned form of the same intent, and it would let `check_cpf`
finish and report rather than abort-and-be-caught. **Not tested here** (running Genus is
out of scope for this page), and the current `catch` demonstrably works — but if anyone
revisits this block, `-continue_on_error` is the first thing to try.

#### The mechanism: why rename-and-wrap

```tcl
48: # Guarded on both sides: under Innovus check_cpf does not exist and a bare
49: # `rename` would itself abort the script. The second test makes re-sourcing
50: # idempotent.
51: if {[llength [info commands check_cpf]]
52:     && ![llength [info commands _check_cpf_unwrapped]]} {
53:     rename check_cpf _check_cpf_unwrapped
54:     proc check_cpf {args} {
55:         if {[catch {eval _check_cpf_unwrapped $args} msg]} {
59:             puts stderr "WARNING: check_cpf FAILED — continuing deliberately."
60:             puts stderr "WARNING:   $msg"
63:             return ""
64:         }
65:         return $msg
66:     }
67: }
```

Four separate design decisions, each worth naming:

**Renaming rather than editing the call site.** The call site is in another repository. A
`rename` in the config layer changes what the word `check_cpf` means for the rest of the
session without touching the file that says it. This is standard Tcl (`rename` is a core
command, not a Cadence one) and it is the only way to intercept a command from *outside*
the script that calls it.

**`info commands check_cpf` — the Innovus guard.** Verified: `check_cpf` appears in **no
file** under `$INNOVUS_HOME/doc/TCRcom/` or `$INNOVUS_HOME/doc/UGcom/` (the
Stylus set), nor in the legacy `innovusTCR/`. Under Innovus the command does not
exist, `info commands` returns the empty list, the whole `if` body is skipped, and nothing
tool-specific is executed. Without the guard, `rename check_cpf ...` would raise
`can't rename "check_cpf": command doesn't exist` and take down `config.tcl` for **all
three P&R stages**. The guard is not defensive style; it is the thing that lets one file
serve two tools.

**`![llength [info commands _check_cpf_unwrapped]]` — idempotence.** Re-sourcing
`config.tcl` in an interactive session (which
[02-innovus-basics](../02-innovus-basics.md#starting-a-session-and-loading-the-design)
tells you to do) would otherwise rename the *wrapper* to `_check_cpf_unwrapped`, producing
infinite recursion on the next call. One extra test, permanent immunity.

**`puts stderr`, not `puts`.** Because `check_cpf`'s own `> file` option has captured
stdout into `syn_cpf_check.log`, a plain `puts` would be written into the very file you
would only open if you already knew to look. stderr reaches the stage log.

#### What is being tolerated

The file enumerates it (L34–44) and the counts match the 2026-07 reference run exactly
(34 / 1 / 54 / 2 = 91):

| count | check | nature |
|---|---|---|
| 34× | `1801_REF_OBJ_NOT_FOUND` | UPF `connect_supply_net` names macro PG ports (`rf_sp_hdf` / cache RAM `VDD`,`VSS`) the liberty models do not expose |
| 54× + 1× | — | pad/macro PG pins with no `create_supply_port` or PG-pin attributes |
| 2× | `STRUCT_UNDRIVEN_PIN_MACRO` | **real**: QSPI flash-cache tag RAMs have an undriven `GWEN` (`u_qspi_flash_0/.../u_way{0,1}_cache_ram/tag_ram_0_i/GWEN`) |

The last two are a genuine RTL defect, present in the reference GDSII too, and belong in
`ahb_qspi`. See [16-open-defects](../16-open-defects.md).

---

### L69 — `hdl_file_list`

```tcl
69: set hdl_file_list ../scripts/read_flist.tcl
```

Note what this is: **not a filelist, a Tcl script**. `1_synthesis.tcl:26` does
`source $hdl_file_list`, and the "filelist" it sources is the recursive parser documented
[below](#read_flisttcl-the-filelist-parser). The indirection exists so that swapping the
RTL-reading strategy is a one-line change here.

---

### L71–86 — the library search path

```tcl
72: set io_lib_dir $::env(TSMC_65_HOME)/CMOS/LP/IO2.5V/iolib/STAGGERED/tphn65lpgv2od3_sl_<rev>_FE/TSMCHOME/digital/Front_End/timing_power_noise/NLDM/tphn65lpgv2od3_sl_<rev>/
73: set sc_lib_dir $::env(TSMC_65_HOME)/CMOS/LP/stclib/9-track/tcbn65lp-set/tcbn65lp_<rev>_FE/TSMCHOME/digital/Front_End/timing_power_noise/NLDM/tcbn65lp_<rev>
76: set rf_32k_dir $MEM_BASE/rf_32k
77: set rf_16k_dir $MEM_BASE/rf_16k/
80: set flash_cache_data_dir $MEM_BASE/flash_cache_data
83: set bootrom_dir $::env(NANOSOC_ETH_CHIPLET_HOME)/ASIC/romlibs/cc_rom
84: set eth_rom_dir $::env(NANOSOC_ETH_CHIPLET_HOME)/ASIC/romlibs/eth_rom
86: set lib_search_path_list "$io_lib_dir $sc_lib_dir $rf_32k_dir $rf_16k_dir $rf_08k_dir $rf_01k_dir $bootrom_dir $eth_rom_dir $flash_cache_data_dir $flash_cache_tag_dir"
```

Ten directories. The header comment at L71 ("please edit for your system") applies to the
first two only; L75 marks the memory directories "Automatically setup !Don't touch!".

Consumed by `1_synthesis.tcl:20`:

```tcl
20: set_db init_lib_search_path $lib_search_path_list
```

> **Genus Attribute Reference — `init_lib_search_path` (`genus_attref/general.html`):**
> "`init_lib_search_path Tcl_list`. Default: `{ . /install_path/build/tools.lnx86/lib/tech}`.
> Read-write root attribute. Specifies a list of UNIX directories that Genus should search
> to locate the technology libraries and LEF libraries. The "~" is supported."

So `syn_lib_list` (next block) can name **bare filenames**, and Genus resolves them against
this path. Note that `set_db` here *replaces* the default, dropping `.` and the tool's own
tech directory — harmless, because every name in `syn_lib_list` resolves under one of the
ten.

Two small facts about the layout:

- **`ASIC/romlibs/` is not a free choice of location.** `config.tcl` puts exactly that path
  on the search list, which is why `make romlibs-fetch` copies into it and
  `make romlibs-check` asserts on it. See
  [01-flow-overview](../01-flow-overview.md#make-romlibs-fetch).
- **Inconsistent trailing slashes.** L76 has none, L77–79 have one. The derived LEF/GDS
  paths at L164–171 concatenate `$dir/name`, so half of them come out with a doubled
  slash (`$MEM_BASE/rf_16k//rf_16k.lef`). POSIX collapses it;
  cosmetic only. All ten directories and all files derived from them were checked to exist
  on this host.

**`PHYS_IP` is *not* read by this layer.** It appears only inside a comment (L132). If a
`config.tcl` source fails on an unset `$::env`, `PHYS_IP` is not the cause.

---

### L88–112 — `syn_lib_list` and what a `.lib` is

```tcl
 89: set BASE_LIB tcbn65lpwc.lib
 90: set RF_32K_LIB rf_32k_ss_1p08v_1p08v_125c.lib
 91: set RF_LIB rf_16k_ss_1p08v_1p08v_125c.lib
 92: set RF_08K rf_08k_ss_1p08v_1p08v_125c.lib
 93: set RF_01K rf_01k_ss_1p08v_1p08v_125c.lib
 94: set ROM_LIB rom_via_ss_1p08v_1p08v_125c.lib
 95: set ETH_ROM_LIB eth_rom_via_ss_1p08v_1p08v_125c.lib
 96: set FLASH_DATA_LIB flash_cache_data_ss_1p08v_1p08v_125c.lib
 97: set FLASH_TAG_LIB flash_cache_tag_ss_1p08v_1p08v_125c.lib
 99: set IO_PAD_DRIVER tphn65lpgv2od3_slwc.lib
101: set syn_lib_list [list \
102:     $BASE_LIB \
...
112:     ]
```

#### What a `.lib` is

> **Innovus Stylus Common UI User Guide — "Preparing Timing Libraries", Data Preparation
> chapter (`UGcom/Data_Preparation.html`):** "Timing library files contain timing information
> in ASCII format for all of the standard cells, blocks and I/O pad cells. The Innovus
> software reads timing library format files (.tlf) or Technology Library format files
> (.lib). You do not need to translate timing library files before reading them into the
> software."

A `.lib` (Liberty) file is the **timing, power and electrical** model of a cell library:
per-cell pin directions, logic functions, delay and transition tables indexed by input
slew and output load, leakage and internal power, setup/hold constraints, and the
power/ground pin declarations (`pg_pin`) that low-power tools rely on. It says nothing
about geometry — that is LEF's job (next block). Genus supports the 2009.06 Liberty
attribute set; the per-attribute support matrix is
**Genus Library Guide — "Liberty Support" (`genus_library/liberty_support.html`)**, which
grades every attribute `S` (supported), `NS` (not supported) or `PS` (partially).

#### What `ss_1p08v_1p08v_125c` means

It is a **PVT corner** name, and on these memory libraries it is not just a filename
convention — it is the name of the operating-conditions group *inside* the file. Measured,
from `rf_01k_ss_1p08v_1p08v_125c.lib`:

```
 78:  nom_process         : 1;
 79:  nom_temperature     : 125.000;
 80:  nom_voltage         : 1.080;
153:  voltage_map (VDD, 1.08);
155:  operating_conditions(ss_1p08v_1p08v_125c) {
156:    process      : 1;
157:    temperature  : 125.000;
158:    voltage      : 1.080;
161:  default_operating_conditions : ss_1p08v_1p08v_125c;
```

Reading the name left to right:

| field | meaning |
|---|---|
| `ss` | **slow-slow** silicon: both NMOS and PMOS at the slow process corner. The pessimistic corner for setup timing. |
| `1p08v` (×2) | the compiler's two supply fields, here **1.08 V** for both. This library declares a single supply (`voltage_map (VDD, 1.08)`), so both fields carry the same number. 1.08 V is 1.20 V nominal −10 %. |
| `125c` | junction temperature **125 °C**. |

The sibling corners shipped alongside it show the convention holding:
`ss_1p08v_1p08v_m40c`, `tt_1p20v_1p20v_25c`, `ff_1p32v_1p32v_125c`,
`ff_1p32v_1p32v_m40c` — slow/typical/fast at 0.9×/1.0×/1.1× nominal, `m40c` = −40 °C.

**The TSMC libraries use a different naming scheme for the same corner.** Measured from
`tcbn65lpwc.lib`:

```
50:    nom_process : 1 ; /* SS SS_25 */
51:    nom_temperature : 125;
52:    nom_voltage : 1.08;
55:    operating_conditions("WCCOM"){ process : 1; temperature : 125; voltage : 1.08; }
```

`wc` = worst case, group name `WCCOM`, and it is **numerically the same corner** as
`ss_1p08v_1p08v_125c`. So `BASE_LIB` and the memory libs are consistent even though their
filenames look nothing alike. The IO driver library is deliberately different:
`tphn65lpgv2od3_slwc.lib` is `process : 1; temperature : 125; voltage : 3` — a 3.0 V IO
corner, correct for a pad library and expected to differ from the 1.08 V core.

This is a **single-corner synthesis**. Multi-corner analysis happens at P&R via
[`nanosoc_eth_chiplet_pads.mmmc`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/nanosoc_eth_chiplet_pads.mmmc),
read by `2_pnr_setup.tcl:24`.

#### How Genus consumes the list

```tcl
21: create_library_domain domain1
22: set_db -verbose [get_db library_domains domain1] .library $syn_lib_list
23: check_library > $LOG_DIR/syn_lib_check.log
```

> **Genus Command Reference — `create_library_domain` (`genus_comref/advanced_lps.html`):**
> "Creates the specified library domains. To use dedicated libraries with portions of the
> design, you must use this command before you read in any libraries for the specified
> library domains."

> **Genus Attribute Reference — `library` (library_domain attribute)
> (`genus_attref/library.html`):** "`library {{lib [lib]...} [{lib [lib]...}]...}`.
> Read-write library_domain attribute. Sets the target library for technology mapping for
> the specified library domain. … You can specify a single library or a Tcl list of library
> lists. Each library list is also a Tcl list. **Each library must be found in the library
> search path** … The first library in each list is considered the master library to which
> the content of the other libraries in that list is appended. … The information in the
> appended libraries overwrites the corresponding information in the master library.
> However, Genus fails on loading the libraries if the delay models in the appended
> libraries differ from the delay models in the master library."

**The grammar and the script disagree about nesting, and the manual does not resolve it.**
The documented value is a *list of braced groups*. `syn_lib_list` is a **flat** 10-element
list with no inner braces. By the letter of the grammar that is one group, making
`tcbn65lpwc.lib` the master and *appending* the nine others into it — which the same
paragraph says can make Genus "fail on loading the libraries if the delay models … differ",
and these ten libraries certainly do not all share a delay model. The manual gives no
example of a flat multi-library value, so it does not say which reading applies. Since the
design synthesises and maps to memory and pad cells correctly, the effective behaviour must
be the ten-independent-libraries reading. **Label: inference.** If you ever need certainty,
`logs/syn_lib_check.log` from a real `make syn` is where `check_library` records what it
actually loaded. (That log is not present in `logs/` on this host at the time of writing;
only the P&R logs are.)

One more consequence of the single flat domain: the 1.08 V core corner and the 3.0 V IO
corner are both target libraries in **`domain1`**. That is normal for a pad-ring design and
is what `create_library_domain` exists to *avoid* when you need genuinely separate library
sets per voltage island — this flow does not use that capability.

---

### L114–126 — block name, directories, top, SDC, DFT, PG nets

```tcl
114: set block_name nanosoc_eth_chiplet_pads
116: set LOG_DIR ../logs
117: set REPORT_DIR ../reports
118: set OUT_DIR ../outputs
120: set top_level_hdl $::env(NANOSOC_ETH_CHIPLET_HOME)/ASIC/tech_wrappers/tsmc65/nanosoc_eth_chiplet_pads.v
121: set constraints_file ../inputs/constraints.sdc
123: set DFT 0
125: set power_nets {VDD VDDACC VDDIO}
126: set ground_nets {VSS VSSIO}
```

`block_name` is the most-used variable in the flow — **53 references** across the stage
scripts, mostly as `${block_name}_something` filenames and as the argument to `read_db` /
`write_db`. `LOG_DIR` / `REPORT_DIR` / `OUT_DIR` account for another 59 between them. All
four are relative, hence the `cd work/` requirement.

`top_level_hdl` is read **separately** from the flist, at `1_synthesis.tcl:27`:

```tcl
27: read_hdl -define POWER_PINS $top_level_hdl
```

with its own `-define POWER_PINS`, which the flist-driven reads do not get. This is the
pad-ring wrapper; `POWER_PINS` is what makes it declare explicit supply ports. Note the
asymmetry with `read_flist.tcl`'s hardcoded `-define TIDELINK_PHY_V2` — the two `read_hdl`
call sites carry different macro sets, deliberately.

#### The DFT flag

```tcl
123: set DFT 0
```

Seven guarded uses across the stage scripts:

| script | line | guarded by `DFT == 1` |
|---|---|---|
| `1_synthesis.tcl` | 50–52 | `source ../scripts/dft_setup.tcl` |
| `1_synthesis.tcl` | 61–64 | `convert_to_scan`, `connect_scan_chains` |
| `1_synthesis.tcl` | 83–90 | scan reports, `write_dft_abstract_model`, `write_scandef` |
| `2_pnr_setup.tcl` | 33–35 | `read_def $OUT_DIR/$block_name.def` |

**`scripts/dft_setup.tcl` does not exist.** Verified absent from
`ASIC/genus-innovus/scripts/`. Setting `DFT 1` therefore does not enable scan; it aborts
synthesis at line 51 on a missing source. The whole scan path is dead code with a missing
dependency, not a feature waiting to be switched on.

#### The PG net declarations

```tcl
125: set power_nets {VDD VDDACC VDDIO}
126: set ground_nets {VSS VSSIO}
```

Three power domains' worth of supply names and two grounds. Consumed by
`2_pnr_setup.tcl:20–21` and by
[`probe_macros.tcl:28–29`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/probe_macros.tcl), both as
`set_db init_power_nets` / `init_ground_nets`:

> **Innovus Stylus Common UI Text Command Reference — `init_power_nets`,
> `init_ground_nets` (`TCRcom/init_Category_Attributes.html`):**
> "`init_power_nets list_of_power_nets`. **Default: `{}`.** Data_type: string, read/write.
> Specifies the list of global power nets used in the design. *Example:* the following
> command specifies VDD as the power net in the design: `set_db init_power_nets {VDD}`.
> *Related Commands:* `init_design`."
> — and identically for `init_ground_nets` ("Specifies the list of global ground nets used
> in the design", `set_db init_ground_nets {VSS}`).

The default is the empty list and the related command is `init_design`, which is why these
two `set_db` calls must precede `init_design` at `2_pnr_setup.tcl:38` — and they do, by 18
lines.

These names are what `init_design` treats as global supplies. They are *declarations*, not
connections — the actual pin-to-net binding is
[`power_plan.tcl`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/power_plan.tcl)'s four
`connect_global_net` calls (see the next block), and the physical routing is
`route_special`. See [04-power-plan](../04-power-plan.md).

Note `VDDACC` appears in `power_nets` but has no `connect_global_net` rule in
`power_plan.tcl` (which handles only `VDD`, `VDDIO`, `VSS`, `VSSIO`). Declared, not wired
by the global-net pass.

---

### L129–186 — the LEF list, and the local-override IO driver LEF

> **The quoted listing in this section predates `bf619f1` (2026-08-13).** It is kept as an
> accurate transcript of `config.tcl` as it stood, and the *reasoning* it annotates is
> unchanged and still correct. Two things in it have since moved: `IO_PAD_DRIVER_LEF` now
> reads `$::design_home/ASIC/tech_wrappers/tsmc65/generated/tphn65lpgv2od3_sl_9lm.patched.lef`
> — a build product generated from the read-only PDK, not a committed copy under
> `local_overrides/` — and the L129–186 line numbers have shifted with the rewritten comment
> block. Read this section for *why*; read `config.tcl` for *where*. See
> [29-private-tsmc-tech-repo](../29-private-tsmc-tech-repo.md) §2a.

#### The three kinds of LEF

LEF is the **physical abstract**: geometry, layers, routing rules. It is disjoint from
`.lib`, which carries timing. The flow uses all three flavours:

| kind | file here | what it contributes |
|---|---|---|
| **technology LEF** | `PRTF_EDI_N65_<stack>_RDL.<rev>.tlef` (L131) | process-level data with no cells in it: `LAYER` definitions for all 9 metals and their cuts, minimum width/spacing/area rules, `VIA` and `VIARULE GENERATE` rules, `SITE` definitions, `UNITS`, `MANUFACTURINGGRID`. Everything the router and the ring/stripe commands need to know about the *process*. |
| **cell (standard-cell) LEF** | `tcbn65lp_9lmT2.lef` (L133) | one `MACRO` per standard cell: `SIZE`, `SITE`, `SYMMETRY`, `PIN` shapes with layer geometry, and `OBS` obstructions. The placeable, routable abstract of each leaf cell. |
| **macro (block) LEF** | the 8 RF/ROM/flash-cache LEFs (L164–171), plus the two IO libraries (L134, L160) | same `MACRO` syntax, but for hard blocks: `CLASS BLOCK` or `CLASS PAD`, much larger, with pin ports on upper metals and large obstructions. |

> **Innovus Stylus Common UI Text Command Reference — `read_physical`
> (`TCRcom/read_physical.html`):** "Reads the physical library information. When this
> command is run, the physical library information is loaded into the database. Both LEF
> and OA are supported, but not simultaneously. … **If `-lef` is used, the technology LEF
> must be first specified.** This command is optional for Synthesis and STA, but is
> required for Implementation."
> — `-lefs lib1 [lib2] ...`: "Specifies the list of LEF files to be loaded. **The first LEF
> file must have the technology section present.** The file names are saved to the
> `init_lef_files` root attribute. This option cannot be combined with `-oa_ref_libs`."

`lef_file_list` (L173–186) obeys the ordering rule exactly: `TECH_LEF`, `BASE_LEF`, then
the IO and macro LEFs. Consumed by `2_pnr_setup.tcl:27` as `read_physical -lef
$lef_file_list`.

**Note the option name.** The Common UI synopsis is **`-lefs`** (plural); the script writes
`-lef`. The page's own prose is inconsistent with its own synopsis here — the description
paragraph says "If `-lef` is used" while the parameter table says `-lefs`. `-lef` is an
unambiguous prefix of `-lefs` (no other `read_physical` option starts with `-lef`), so
Innovus's option-abbreviation resolves it and the flow works. It is still an abbreviation
of an undocumented spelling; `-lefs` is the form the manual actually defines. *(Inference
on the abbreviation mechanism — the flow demonstrably runs, so it resolves.)*

The underlying attribute is `init_lef_files`, whose page gives the canonical example
tech-first, cells-second:

> **Innovus Stylus Common UI Text Command Reference — `init_lef_files`
> (`TCRcom/init_Category_Attributes.html`):** "`init_lef_files list_of_files`. Default:
> `{}`. Specifies the list of LEF files to be imported. This attribute cannot be used with
> `init_oa_ref_libs`. *Example:* `set_db init_lef_files {technology.lef stdcell.lef}`."

**One statement about LEF ordering exists only in the legacy manual**, and it is a live
constraint on the override strategy below, so it is quoted here with that label:

> **Innovus User Guide (LEGACY UI) — Importing and Exporting Designs
> (`innovusUG/Importing_and_Exporting_Designs.html`):** "Specify the LEF files to import.
> You must specify the technology LEF file first, then specify the standard cell LEF and
> block LEF in any order. … **If a cell is defined multiple times, Innovus reads the
> geometry information only from the first definition. For subsequent definitions, Innovus
> reads the antenna information only.**"
>
> The Stylus counterpart, `UGcom/Design_Import_and_Export_in_Stylus.html`, does **not**
> carry this sentence — searched, zero hits for "defined multiple times" anywhere in
> `UGcom/` or `TCRcom/`. Since it describes reader behaviour rather than UI syntax it
> should still apply, but it is undocumented on the Stylus side. *(Inference.)*

So it was checked: the bond-pad LEF (`tpbn65v_9lm.lef`, 34 macros, all `PAD*`) and the IO
driver LEF (72 macros, all `P*`) define **disjoint** macro sets — `comm -12` on their
`MACRO` name lists is empty. The TSMC original driver LEF is not on the list at all, only
the local copy. So there is no shadowed duplicate and the override's edits are the only
definition Innovus sees. *(Measured.)* If anyone ever adds the upstream driver LEF back
alongside the override, whichever comes **first** wins the geometry — and the fix silently
stops working.

#### The local override

```tcl
135: # LOCAL OVERRIDE of the TSMC IO driver LEF — three added lines, nothing else.
136: #
137: # The IO supply pads declare their supply pins as plain signal pins:
138: #     PIN VDDPST / DIRECTION INOUT ;      (PVDD2DGZ_G, PVDD2POC_G)
139: #     PIN VSSPST / DIRECTION INOUT ;      (PVSS2DGZ_G)
140: # with no `USE POWER ;` / `USE GROUND ;`. The liberty agrees — they are pin()
141: # groups, not pg_pin(). So `connect_global_net -type pg_pin` cannot match them,
142: # and the VDDIO/VSSIO global-net rules failed with IMPDB-1221.
160: set IO_PAD_DRIVER_LEF $::env(NANOSOC_ETH_CHIPLET_HOME)/ASIC/tech_wrappers/tsmc65/local_overrides/tphn65lpgv2od3_sl_9lm.lef
```

Every claim in that comment was checked against the manuals and against the files. All of
it holds.

**1 — `USE` is what classifies a LEF pin, and its default is SIGNAL.**

> **LEF/DEF 5.8 Language Reference — Macro Pin Statement (`lefdefref/LEFSyntax.html`):**
> ```
> [PIN pinName
>   [DIRECTION {INPUT | OUTPUT [TRISTATE] | INOUT | FEEDTHRU} ;]
>   [USE { SIGNAL | ANALOG | POWER | GROUND | CLOCK } ;]
> ```
> "`USE {ANALOG | CLOCK | GROUND | POWER | SIGNAL}` — Specifies how the pin is used. Pin
> use is required for timing analysis. **Default: SIGNAL.**"
> — `POWER`: "Pin is used for connectivity to the chip-level power distribution network."
> — `GROUND`: "Pin is used for connectivity to the chip-level ground distribution network."
> — `SIGNAL`: "Pin is used for regular net connectivity."

`DIRECTION INOUT ;` with no `USE` clause therefore means **`USE SIGNAL`**, by the language
definition. There is no "power-ish INOUT" fallback. The supply pins of these pads were, as
far as Innovus was concerned, signal pins.

**2 — `IMPDB-1221` is exactly the failure that produces.** The message is **not in either
21.10 Innovus error reference** — absent from `EMRcom/` (Stylus) and from
`innovuserrmsg/` (legacy); in both, `IMPDB-1220` and `IMPDB-1284` are its neighbours. It
*is* installed in the older tree on this box:

> **Innovus Error Message Reference (16.13) — IMPDB-1221
> (`$CDS_INSTALL/2016-17/RHELx86/INNOVUS_16.13.000/doc/innovuserrmsg/IMPDB-1221.html`):**
> "A global net connection rule was specified to connect `%s` pins with the name pattern
> `'%s'` to a global net. But the connections cannot be made because **there is no such
> `%s` pin with name matching the pattern in any cell.** Check the pin name pattern and
> make sure it is correct."

Read that against
[`power_plan.tcl:46–49`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/genus-innovus/scripts/power_plan.tcl):

```tcl
46: connect_global_net VDD   -type pg_pin -pin_base_name VDD    -inst_base_name *
47: connect_global_net VDDIO -type pg_pin -pin_base_name VDDPST -inst_base_name *
48: connect_global_net VSS   -type pg_pin -pin_base_name VSS    -inst_base_name *
49: connect_global_net VSSIO -type pg_pin -pin_base_name VSSPST -inst_base_name *
```

All four are the documented Stylus form:

> **Innovus Stylus Common UI Text Command Reference — `connect_global_net`
> (`TCRcom/connect_global_net.html`):**
> ```
> connect_global_net global_net_name
>   {{-type pg_pin  -pin_base_name pinNamePattern |
>     -type tie_hi [-pin_base_name pinNamePattern] |
>     -type tie_lo [-pin_base_name pinNamePattern]}
>    {{-single_inst | -sinst} instName |
>     [-inst_base_name instBasenamePattern] …}}
> ```
> "Adds a new global net connection to the specified global net. … Connecting pins in
> multiple instances, or pins in a region, to a global net: … `[-inst_base_name
> instBasenamePattern]`"
> — `-inst_base_name`: "Specifies the names of leaf instances for which pins are to be
> connected to the global net. You can use the wildcard (`*`) character to specify a pattern
> of instance basenames. An instance basename cannot contain the "/" character. **This
> parameter is used in conjunction with the `-type pg_pin` parameter**, or with the
> `-type tie_hi` or `-type tie_lo` parameters."

`-type pg_pin` restricts the search to **power/ground pins**. Its documented alternatives
are `tie_hi`, `tie_lo` and `net`, so `-type` selects a *class* of connection target, not a
name pattern — the name pattern is the separate `-pin_base_name` argument. A pin the LEF
classifies SIGNAL is not in the `pg_pin` set at all. Hence "no such pin … in any cell" — for
`VDDPST` and `VSSPST` specifically, while `VDD` and `VSS` on the core cells matched fine. The message is about the *class*, not the *name*, which is precisely why the
comment's next paragraph is the important one:

```tcl
150: # Verified, not assumed: correcting -pin_base_name alone is NOT sufficient.
151: # `connect_global_net VDDIO -type pg_pin -pin_base_name VDDPST` still raises
152: # IMPDB-1221 against a design loaded from the real DB, because the pin is not
153: # classified as power. The LEF has to say so.
```

The name in `-pin_base_name` was already right. Only the LEF can change the class.

There is a related Innovus escape hatch that is *not* applicable here but is worth knowing
exists, because it is the only supply-pin-classification override the tool offers:

> **Innovus Stylus Common UI Text Command Reference —
> `init_ignore_pg_pin_polarity_check` (`TCRcom/init_Category_Attributes.html`):**
> "Space separated list of leaf cell pin names to ignore polarity checking during
> `connect_global_net` and CPF operations. **Allows USE POWER pin to be connected to a USE
> GROUND net (or vice versa).** … The list of pin names is only checked for the case where a
> polarity check failed and then can be ignored and connected in spite of the polarity
> mismatch."

That relaxes **POWER-vs-GROUND polarity**, not SIGNAL-vs-POWER classification. A pin the
LEF calls SIGNAL never reaches the polarity check, because `-type pg_pin` has already
excluded it. There is no attribute that promotes a SIGNAL pin to POWER — which is the whole
reason the LEF had to be edited. *(Checked: this and `IMPDB-1220`'s
`init_ignore_pgpin_polarity_check` are the only polarity-override knobs in the reference.)*

**3 — `NRDB-51` explains what the router then did.**

> **Innovus Stylus Common UI Error Message Reference — NRDB-51 (`EMRcom/NRDB-51.html`):**
> "`%s %s` has no instance pin or special wire in its connectivity definition. `%s` with the
> same name will be routed but will not be connected to the empty `%s`."
> *Description:* "The root cause of this issue is that the net connectivity definition is
> incomplete. It may have the net name in the special net section but no instance pin or
> wire. If the net has connectivity in the regular net section it will have no target in
> the special net section and warn of the inconsistancey." [sic]
>
> (The legacy copy, `innovuserrmsg/NRDB-51.html`, has the identical `SUMMARY` and
> `DESCRIPTION` but names the legacy remedy commands — `convertSNetToNet`, `setAttribute`,
> `ecoRoute` — where the Stylus copy names `convert_special_to_routes`,
> `set_route_attributes` and `route_design_eco`. Use the Stylus ones.)

That is the mechanism the comment describes at L144–148: with the `connect_global_net`
rules failing, the `VDDIO`/`VSSIO` **SPECIAL_NETs stayed empty**, so the same-named
*regular* nets were routed instead — "will be routed but will not be connected". A supply
net routed as an ordinary signal net gets minimum-width wires threaded through the
periphery on signal layers, straight into the bond-pad M8/M9 blockages. 76 DRC violations,
every one a "Regular Wire" record on `VDDIO`/`VSSIO`, none on `VDD`/`VSS`. This is the same
class-of-failure as the empty-CPF/no-filler problem in
[06-fill-antenna-bondpads](../06-fill-antenna-bondpads.md): a warning nobody read, a
valid-looking GDSII, a broken die.

**4 — the diff is exactly three lines.** Verified against the read-only PDK source
(`$TSMC_65_HOME/CMOS/LP/IO2.5V/iolib/STAGGERED/tphn65lpgv2od3_sl_<rev>_FE/TSMCHOME/digital/Back_End/lef/tphn65lpgv2od3_sl_<rev>/mt_2/9lm/lef/tphn65lpgv2od3_sl_9lm.lef`):

```
10102a10103
>         USE POWER ;
10170a10172
>         USE POWER ;
10855a10858
>         USE GROUND ;
```

11182 lines upstream → 11185 local. Nothing else changed. The three insertions land where
the comment says they do:

| local line | macro | pin | inserted |
|---|---|---|---|
| 10103 | `PVDD2DGZ_G` | `VDDPST` | `USE POWER ;` |
| 10172 | `PVDD2POC_G` | `VDDPST` | `USE POWER ;` |
| 10858 | `PVSS2DGZ_G` | `VSSPST` | `USE GROUND ;` |

and all three macros are instantiated in the pad ring
([`nanosoc_eth_chiplet_pads.v:192–208`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/tech_wrappers/tsmc65/nanosoc_eth_chiplet_pads.v),
`uPAD_VDDIO_*` / `uPAD_VSSIO_*`). Each insertion sits immediately after `DIRECTION INOUT ;`
and before `PORT`, which is where the LEF grammar puts `USE`.

**5 — the copy-don't-edit rule.** L155–159 states it: `$TSMC_65_HOME` is read-only shared
collateral and is not modified. That half still stands.

**The rest of this rule has been superseded — do not repeat the pattern as written.** The
original instruction was to copy the vendor file into
`ASIC/tech_wrappers/tsmc65/local_overrides/`, point `config.tcl` at the copy, and `diff`
against upstream to re-apply after a PDK rev. That put a 414 kB verbatim vendor LEF into a
**public** repository, which TSMC's licence does not permit. The current rule is *ship the
transform, not the result*:

1. Commit a script that reads the vendor file from `$TSMC_65_HOME` and applies the delta by
   **exact-match anchor**, not by line number — here,
   `ASIC/tech_wrappers/tsmc65/scripts/patch_pad_lef.py`.
2. Write its output to a **gitignored** generated directory, and give it a `make` target
   (`make -C ASIC -f common.mk pad-lef`).
3. Pin the SHA-256 of both input and output, so a PDK rev fails loudly instead of being
   absorbed silently. That, not a `diff`, is the re-application procedure.
4. `scripts/ci/check_no_vendor_collateral.sh` enforces it, keyed on **content** — renaming
   or relocating a vendor copy does not evade it.

Landed in `bf619f1`. The same principle at process-node scale is
[29-private-tsmc-tech-repo](../29-private-tsmc-tech-repo.md) §3.

*This supersedes the destination only for **foundry/PDK** collateral. The repo-wide
`local_overrides/` convention for third-party **RTL** — `tidelink/src/rtl/local_overrides/`
and friends — is unaffected and still current.*

---

### L188–207 — the GDS merge list

```tcl
189: set RF32_GDS $rf_32k_dir/rf_32k.gds2
...
198: set gds_merge_list [list \
199:     ${RF32_GDS} \
...
207: ]
```

Eight files: the four register-file macros, two ROMs, and the two flash-cache RAMs. All
eight verified present. Used exactly once, at
[`4_pnr_route.tcl:60–64`](https://github.com/SoC-Labs/ASIC-Flow/blob/b19e7845448e641ea8353b19a59a77257907cb13/Cadence/4_pnr_route.tcl):

```tcl
60: write_stream $OUT_DIR/${block_name}.gds \
61:     -map_file $TSMC_65_HOME/CMOS/util/lef/PRTF_EDI_65nm_<rev>/PR_tech/Cadence/GdsOutMap/PRTF_EDI_N65_gdsout_6X1Z1U.<rev>.map \
62:     -lib_name DesignLib \
63:     -merge $gds_merge_list\
64:     -output_macros -unit 1000 -mode all
```

> **Innovus Stylus Common UI Text Command Reference — `write_stream`
> (`TCRcom/write_stream.html`):** "Creates a GDSII Stream file of the current database.
> Writes a summary of errors and warnings to the log file. You can use the `write_stream`
> command after the design is placed, but is most commonly used only after the design is
> routed (which may also include metal fill shapes)."
> — `-merge {listOfExternalGDSOASISFiles}`: "Specifies a single file or list of files to
> merge. Checks all merged files for name collisions, and generates a warning if any names
> are changed. … Compressed files are acceptable … **The Innovus software automatically
> creates blackboxes when merging and writing macro files. It ignores any cells in the merge
> files that are not used in the design.** … If you specify more than one file, separate the
> file names with spaces and enclose the list of file names in braces (`{}`) or double
> quotation marks."

At stream-out, Innovus writes the **routing and placement it produced** — wires, vias, and
instance placements — but for every referenced cell it can only emit an empty structure
unless real polygon data is merged in. `-merge` supplies that polygon data for the eight
memory macros, so they appear as full layout in the output GDS instead of empty cells.

Two further sentences from the same page pin down the rest of the behaviour:

> "If you do not specify `-output_macros`, LEFPIN and LEFOBS do not apply. **If you do
> specify `-output_macros` and LEFPIN and LEFOBS are not specified in the map file for the
> layers in the LEF macros, the GDSII structures for those macros will be empty.**"

> "You must specify all layers to stream out. Layers that are not specified in the map file
> are not included in the file created by this command."

Which is the mechanism behind the warning on the
[index page](../00-index.md): **`gds_merge_list` covers only the 8 memory macros.**
Standard cells (`tcbn65lp`), IO drivers (`tphn65lpgv2od3_sl`) and bond pads (`tpbn65v`) are
*not* in the list, because this site's PDK ships LEF and Liberty for them but no GDS. They
stream out as references with no polygons. Cell-level merge has to happen at the foundry —
see [10-tapeout-submission](../10-tapeout-submission.md).

The remaining options, all from the same page:

| in the script | manual |
|---|---|
| `-output_macros` | "Writes LEF abstract information such as LEF pin geometries and obstructions for macros. Writes one text label per port within a LEF macro pin plus one text label per shape for feedthrough pins. Specify this parameter to create GDSII output that contains the LEF macro structures as well as the design data." |
| `-mode all` | `-mode {ALL \| FILLONLY \| NOFILL \| NOINSTANCES}` — "Identifies the layers to write." `ALL` writes all layer information specified in the map file. |
| `-unit 1000` | `-unit {100 \| 200 \| 1000 \| 2000 \| 10000 \| 20000}` — "Specifies the resolution for values in the GDSII file." **"Default: Units specified in LEF file."** 1000 = 1 nm resolution, stated explicitly rather than inherited. |
| `-map_file …` | "Specifies the file used for layer mapping. **This file is required for successful stream out**, and is read by the next tool used in the design flow." Without it the tool writes a generic map "that you must customize for your design". |
| `-lib_name DesignLib` | "Specifies the library to convert to GDSII Stream format. **Default: DesignLib.**" — i.e. the flow states the default explicitly; this argument is redundant. |

---

### L209 — the DRC ruledeck

```tcl
209: set drc_ruledeck $TSMC_65_HOME/CMOS/util/MAIN_DRC_TopMu/CLN65S_<stack>.<rev>
```

An **absolute** path, not built from `$::env(TSMC_65_HOME)` like everything else in the
file — so a site with the PDK elsewhere gets a working synthesis and P&R and a broken
`make drc`. The file exists on this host (877 KB, dated 2024-01-19).

Used once, at `4_pnr_route.tcl:75–81`, inside an `if {[info exists ::env(CALIBRE_HOME)]}`
guard. As [01-flow-overview](../01-flow-overview.md#stage-4-make-pnr_route-innovus) notes,
that in-flow invocation is a no-op in practice — it passes only the ruledeck, whose
`LAYOUT PATH` / `LAYOUT PRIMARY` are placeholders. The working headless invocation is
`make drc`; see [12-calibre-drc](../12-calibre-drc.md).

---

### L211–260 — multi-CPU and `soclabs_setup_multi_cpu`

#### The three modes, per Cadence

> **Innovus Stylus Common UI User Guide — Accelerating the Design Process By Using
> Multiple-CPU Processing
> (`UGcom/Accelerating_the_Design_Process_By_Using_Multiple-CPU_Processing.html`):**
> - **Multi-threading** — "a job is divided into several threads, and multiple processors
>   in a single machine process them concurrently."
> - **Distributed processing** — "a job is processed by two or more networked computers
>   running concurrently."
> - **Super-threading** — "a job runs in the distributed processing mode but each
>   distributed job can also run threads, that is, one or more networked computers, each
>   with multiple processors, work concurrently to complete a job."
>
> And the command requirements, stated per mode: **"To run the software in multi-threading
> mode, the following command is required: `set_multi_cpu_usage`"**; **"To run the software
> in distributed processing mode, the following two commands are required:
> `set_distributed_hosts` … `set_multi_cpu_usage`"**; and the same two for Super-threading.

The same chapter's feature table lists what actually gets faster — in Stylus names, and for
this flow: `place_design`, `opt_design`, `ccopt_design`, `route_global_detail` /
`route_detail` / `route_design` / `route_eco`, `add_metal_fill`, `write_cap_table`,
`extract_rc`, and delay calculation. Note "Superthreading is supported for detailed routing
only" and "Superthreading options take precedence over multi-threading options."

#### The environment-driven defaults

```tcl
224: foreach {__v __default} {
225:     INNOVUS_LOCAL_CPU      14
226:     INNOVUS_DISTRIBUTED     0
227:     INNOVUS_REMOTE_HOSTS   {}
228:     INNOVUS_CPU_PER_REMOTE  6
229: } {
230:     if {[info exists ::env($__v)]} {
231:         set $__v $::env($__v)
232:     } elseif {![info exists $__v]} {
233:         set $__v $__default
234:     }
235: }
236: unset __v __default
```

A three-level precedence chain in nine lines, all plain Tcl and therefore safe under both
interpreters:

1. **environment wins** — `INNOVUS_LOCAL_CPU=8 make pnr`
2. **an already-set Tcl variable is preserved** — `![info exists $__v]` reads the variable
   *named by* `$__v`, so re-sourcing `config.tcl` in an interactive session does not stomp
   a value you set by hand
3. **otherwise the default**

`{}` in the literal list becomes an empty-string element, which is what
`llength $INNOVUS_REMOTE_HOSTS > 0` later tests. `unset` cleans up the loop variables so
they do not leak into the global namespace the stage scripts share.

The rationale in the comment is measured, not guessed:

```tcl
212: # The stage scripts used to hardcode `-local_cpu 8`. srv03335 has 16 physical
213: # cores (4 sockets x 4, no SMT), so that left half the machine idle. Licences
214: # are not the constraint: Innovus_CPU_Opt has 41 issued and typically 0 in use.
217: # Distribution onto a second host is OFF by default and should stay that way
218: # unless the extra host is on a fast link. Measured srv03335<->srv04936 is
219: # ~25 MB/s, i.e. ~37x slower than srv03335's local disk, so slaves spend
220: # longer fetching the design than they save working on it.
```

14 of 16 cores, leaving two for the OS and for whatever else the box is doing. The manual
backs the ceiling:

> **Innovus Stylus Common UI Text Command Reference — `set_multi_cpu_usage`
> (`TCRcom/set_multi_cpu_usage.html`):** "Specifies the number of threads to use for
> multi-threading, or the maximum number of computers to use for distributed processing, or
> the maximum number of computers and the number of threads to use for Superthreading. …
> **This command is required for multi-threading, distributed processing, and
> Superthreading.**"
> — `-local_cpu string`: "Specifies the number of CPUs on the local machine. This parameter
> is required for multi-threading. **Default: 1.**"

> **Innovus Stylus Common UI User Guide — Accelerating the Design Process
> (`UGcom/Accelerating_…html`):** "Note: The `-local_cpu` parameter limits the number of
> threads running concurrently. Although the software can create additional threaded jobs
> during run time, depending on the application in use, only the number of threads specified
> with this parameter are run at a given time. **If you ask for more threads than are
> available, the software issues a warning and runs with the maximum number of available
> threads.**"

So over-requesting is a warning, not a failure — but it is a warning, and per
[the index page's rule 2](../00-index.md) those are where the bodies are.

**Where the two UIs' manuals diverge, and it matters here.** The legacy page
(`innovusTCR/setMultiCpuUsage.html`) carries an explicit hard ceiling that the Stylus page
**drops**: "The number of specified threads cannot be more than the number of CPUs
available in the local computer. For example, given a computer with 8 CPUs, then the
following command will issue a warning …: `setMultiCpuUsage -localCpu 10`". Same behaviour,
documented in only one of the two sets. If you are checking whether `INNOVUS_LOCAL_CPU=32`
on a 16-core box is safe, `TCRcom/` alone will not tell you; `UGcom/`'s prose (quoted above)
will.

#### The proc

```tcl
241: proc soclabs_setup_multi_cpu {} {
242:     global INNOVUS_LOCAL_CPU INNOVUS_DISTRIBUTED
243:     global INNOVUS_REMOTE_HOSTS INNOVUS_CPU_PER_REMOTE
245:     set can_distribute [expr {$INNOVUS_DISTRIBUTED
246:                               && [llength $INNOVUS_REMOTE_HOSTS] > 0
247:                               && [llength [info commands set_distributed_hosts]] > 0}]
249:     if {$can_distribute} {
250:         set_distributed_hosts -ssh -add $INNOVUS_REMOTE_HOSTS
251:         set_multi_cpu_usage -local_cpu $INNOVUS_LOCAL_CPU \
252:                             -remote_host [llength $INNOVUS_REMOTE_HOSTS] \
253:                             -cpu_per_remote_host $INNOVUS_CPU_PER_REMOTE
256:     } else {
257:         set_multi_cpu_usage -local_cpu $INNOVUS_LOCAL_CPU
258:         puts "MULTICPU: local=$INNOVUS_LOCAL_CPU (distribution off)"
259:     }
260: }
```

Called by all four stage scripts (`1_synthesis.tcl:17`, `2_pnr_setup.tcl:16`,
`3_pnr_clock.tcl:16`, `4_pnr_route.tcl:15`), immediately after they source `config.tcl`.

**The three-way `can_distribute` guard is the two-interpreter rule in action**, and each
conjunct earns its place:

| conjunct | prevents |
|---|---|
| `$INNOVUS_DISTRIBUTED` | distributing when nobody asked |
| `[llength $INNOVUS_REMOTE_HOSTS] > 0` | `set_distributed_hosts -ssh -add {}` with no hosts, and `-remote_host 0` |
| `[llength [info commands set_distributed_hosts]] > 0` | **calling a command Genus does not have** |

That third one is verified in both directions:

- **`set_distributed_hosts` appears in no Genus HTML manual on this box** (searched the
  whole `$CDS_INSTALL/genus/doc` tree at depth 2). Genus has no distributed-processing
  command; the comment at L239–240 ("Degrades to local-only under Genus, which has no
  `set_distributed_hosts`") is exactly right.
- **`set_multi_cpu_usage` *does* exist in Genus** — and its option set is much smaller:

> **Genus Command Reference — `set_multi_cpu_usage` (`genus_comref/general.html`):**
> "`set_multi_cpu_usage [-local_cpu integer] [-verbose]` — Specifies the maximum number of
> active CPUs allowed to be used on one server. `-local_cpu integer` — Specifies the number
> of available local CPUs. **Default: 8.**"

**Two options, that is all.** No `-remote_host`, no `-cpu_per_remote_host`. So the guard is
load-bearing twice over: it stops the missing `set_distributed_hosts` call *and* it stops
`set_multi_cpu_usage` being handed two options Genus does not accept. The `else` branch
uses only `-local_cpu`, which is the intersection of the two tools' option sets — the one
form that is valid under both. Note also that Genus's default is **8** and Innovus's is
**1**, so calling this proc is not optional on the Innovus side if you want any
parallelism at all.

#### The distributed branch, option by option

> **Innovus Stylus Common UI Text Command Reference — `set_distributed_hosts`
> (`TCRcom/set_distributed_hosts.html`):**
> "Specifies the multiple-CPU processing configuration for distributed processing or
> Superthreading. The software finds hosts from the last `set_distributed_hosts` command
> specified before a distributed processing or Superthreading command starts. Use
> `get_distributed_hosts` to display the current settings. **This command is required for
> distributed processing and Superthreading.**"
> - "`-ssh` — Specifies a secure shell configuration."
> - "`-add string` — Adds the specified hosts to the rsh/ssh configuration. If you specify
>   more than one host, separate each host name with a space. **Each time you specify a
>   host, the software uses it to run one client process. To run more than one client
>   process on a host, specify it more than once.** For example, if you have two machines
>   that each has two CPUs and you want to use both CPUs in both machines, type a command
>   like the following: `set_distributed_hosts -rsh -add {machine1 machine2 machine1
>   machine2}`"

> **Innovus Stylus Common UI Text Command Reference — `set_multi_cpu_usage`
> (`TCRcom/set_multi_cpu_usage.html`):**
> - "`-remote_host integer` — Specifies the number of remote machines. This parameter is
>   required for distributed processing and Superthreading. **Default: 0.**"
> - "`-cpu_per_remote_host integer` — Specifies the number of CPUs on each of the remote
>   machines. This parameter is required for Superthreading. For Superthreading, you must
>   use this parameter in conjunction with the `-remote_host` parameter. **Default: 1.**"

Mapped onto the script:

| script | manual | why the value is right |
|---|---|---|
| `set_distributed_hosts -ssh -add $INNOVUS_REMOTE_HOSTS` | `-ssh`, `-add` | one client process per host *name listed* |
| `-local_cpu $INNOVUS_LOCAL_CPU` | "number of CPUs on the local machine", default 1 | threads on the master |
| `-remote_host [llength $INNOVUS_REMOTE_HOSTS]` | "number of remote machines", default 0 | an **integer**, not a list — the script correctly passes `llength`, not the list itself |
| `-cpu_per_remote_host $INNOVUS_CPU_PER_REMOTE` | "number of CPUs on each of the remote machines", default 1 | threads per remote machine — this is what makes it **Superthreading** rather than plain distribution |

**One subtlety in `-remote_host`, and the two manual sets disagree about it.** `TCRcom/`
says "the number of remote **machines**"; `innovusTCR/` says "the number of **clients**".
Those are the same number only when each host name appears once in `-add` — which is
exactly how the script builds it, so `[llength $INNOVUS_REMOTE_HOSTS]` is right today. But
`-add`'s own documented idiom for two client processes on one machine is to *repeat the
name*, and under that usage `llength` would count clients (2) while the machine count is 1.
If anyone ever puts a duplicated host in `INNOVUS_REMOTE_HOSTS`, this line becomes
ambiguous by the Stylus manual's own wording. *(Inference — the ambiguity is in the docs,
not observed in a run.)*

The manual's own Superthreading example is structurally identical to the script's:
`set_distributed_hosts -lsf -queue myLSFqueue` then
`set_multi_cpu_usage -remote_host 2 -cpu_per_remote_host 6` then `route_detail`. The script
uses `-ssh` instead of `-lsf` because this site has no queue manager in the loop.

Override syntax, from the comment:

```sh
INNOVUS_LOCAL_CPU=8 make pnr
INNOVUS_DISTRIBUTED=1 INNOVUS_REMOTE_HOSTS=srv04936 make pnr
```

Before turning distribution on, run `check_multi_cpu_usage` at a live prompt — its manual
page (`TCRcom/check_multi_cpu_usage.html`) is a worked example of what a healthy
distributed setup prints ("The distributed processing environment has been set up
correctly"). `get_multi_cpu_usage` and `get_distributed_hosts` report the current settings,
and `report_resource -verbose` is the memory/runtime counterpart — the UG chapter documents
its output format in full. All four exist in `TCRcom/` under their Stylus names.

---

## `read_flist.tcl` — the filelist parser

46 lines, sourced by `1_synthesis.tcl:26` via `$hdl_file_list`. It reads a
simulator-style filelist (`.flist`, the same files VCS and Xcelium consume) and turns it
into `read_hdl` calls. **It is Genus-only** — nothing sources it under Innovus.

Entry point, last line:

```tcl
46: read_filelist $::env(ASIC_FLIST)
```

`ASIC_FLIST` is exported by [`ASIC/common.mk`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/common.mk) as
`$(NANOSOC_ETH_CHIPLET_HOME)/flist/nanosoc_eth_chiplet_asic.flist`. No guard: if it is
unset, this line raises a Tcl "no such variable" error.

**Measured shape of what it actually parses** (this repo, this commit, resolving `-f`
recursively): **4 flists, 597 file entries — 412 `.v`, 182 `.sv`, 3 neither — plus 20
`+incdir+`, 8 `+libext+`, 3 `-f`, and 0 `-y`.**

### The dispatch

```tcl
 2: proc read_filelist {flist} {
 4:     set fh [open $flist r]
 5:     while {[gets $fh line] >= 0} {
 6:         set line [string trim $line]
```

A `while`/`gets` loop with `string trim`, then a `string match` ladder. Six branches:

#### Branch 1 — blank lines and `#` comments (L7–9)

```tcl
 7:         if {$line eq "" || [string match "#*" $line]} {
 9:             continue
```

#### Branch 2 — `//` comments (L10–12)

```tcl
10:         } elseif {[string match "//*" $line]} {
12:             continue
```

Both styles are needed: the generated flists use `#`, the hand-written ones use `//` (the
top-level `nanosoc_eth_chiplet_asic.flist` is entirely `//`-commented).

#### Branch 3 — `+incdir+` (L13–16)

```tcl
13:         } elseif {[string match "+incdir+*" $line]} {
15:             set incdir [expand_env [string range $line 8 end]]
16:             set_db init_hdl_search_path $incdir
```

`[string range $line 8 end]` strips the 8 characters of `+incdir+`.

> **Genus Attribute Reference — `init_hdl_search_path` (`genus_attref/inout.html`):**
> "`init_hdl_search_path string`. Default: `{ . }`. Read-write root attribute. Specifies a
> list of UNIX directories that Genus should search for files associated with the
> `read_hdl` command. The behavior is similar to the search path in UNIX. **In Verilog,
> this attribute directs the search of Verilog files specified with the `read_hdl` command
> and `` `include `` files specified in Verilog code.** … The "~" is supported."

That is the right attribute for the job — it is explicitly the one that resolves
`` `include ``.

**But `set_db` here *assigns*, it does not append.** The attribute is documented as "a
list of UNIX directories", and this line sets it to a single directory, discarding both
the `{ . }` default and every previous `+incdir+`. There are **20 `+incdir+` lines** across
the four flists, so at any moment only the most recent one is on the search path.

Why it works anyway: the flists interleave — each `+incdir+` sits immediately before the
files of the subsystem that needs it, and `read_hdl` fires inline as the parser walks. So
"last one wins" happens to coincide with "the right one is current". Measured from
`build/chip/flist/soc.flist`:

```
115: +incdir+.../ethernet-mac-ahb/src/rtl
116: +incdir+$IP_LIBRARY_ROOT/ip_library/OpenCores-EthMAC/rtl/verilog
117: +define+ETH_WISHBONE_B3
   … the EthMAC source files …
148: +incdir+.../ethernet-mac-ahb/src/rtl
149: +incdir+$IP_LIBRARY_ROOT/ip_library/OpenCores-HA1588/rtl/tsu
```

Note line 115 vs 148 — the *same* directory re-stated, because the emitter knows the
previous one has been displaced. That is the workaround for this bug, already present in
the generator. The latent failure is any file that needs an include from an earlier,
now-displaced `+incdir+`; and note that at line 116 the EthMAC files can no longer see
line 115's directory either. Contrast the `-y` branch four lines below, which *does*
`concat`. **Fix, if anyone wants it:**

```tcl
set_db init_hdl_search_path [concat [get_db init_hdl_search_path] $incdir]
```

*(Inference from the attribute semantics and the measured flist structure; not re-run
through Genus.)*

#### Branch 4 — `-y <dir>` (L17–20)

```tcl
17:         } elseif {[string match "-y *" $line]} {
19:             set libdir [expand_env [string range $line 3 end]]
20:             set_app_var search_path [concat [get_app_var search_path] $libdir]
```

`-y` is the simulator's *library directory* switch: "for any module you cannot find, look
for a file of that name in this directory". **This branch is dead code and would not work
if it were reached.**

- **Measured: there are 0 `-y` lines** in the four flists this flow parses.
- **`set_app_var` and `get_app_var` appear in no Genus manual on this box.** Searched every
  HTML file under `$CDS_INSTALL/genus/doc` to depth 2; zero hits, while a control search
  for `read_hdl` over the identical file set returns matches. They are Synopsys
  Design Compiler / PrimeTime commands, and `search_path` is a DC variable. This branch is
  a leftover from the Design Compiler ancestor of this script — as the `+libext+` branch's
  own comment ("DC uses search_path with define_design_lib") confirms.

If a `-y` line ever appeared in a flist, Genus would abort with an unknown-command error.
Genus's equivalent would be `init_hdl_search_path` plus explicit reads, or `read_hdl -f`.

#### Branch 5 — `+libext+` (L21–23)

```tcl
21:         } elseif {[string match "+libext+*" $line]} {
22:             # Skip libext directives (DC uses search_path with define_design_lib)
23:             continue
```

`+libext+` names the extensions a `-y` search should try. With no `-y` lines it is
meaningless, and skipping is correct. Measured: 8 `+libext+` lines, all skipped.

#### Branch 6 — `-f <flist>`: the recursion (L24–27)

```tcl
24:         } elseif {[string match "-f *" $line]} {
26:             set file [expand_env [string range $line 3 end]]
27:             read_filelist $file
```

Direct recursion, no depth limit and no cycle detection — a flist that `-f`-includes itself
(directly or via a loop) recurses until the Tcl stack blows. Measured depth here is 2:
the top flist includes `build/chip/flist/soc.flist`, `build/chip/flist/tidelink_asic.flist`
and `tidechart/flist/tidechart.flist`.

Note this is *the script's* recursion, not `read_hdl`'s. `read_hdl` has its own `-f`
("Specifies the name of the list file for reading files from the simulation environment"),
which the script does not use — presumably because `read_hdl -f` would not run
`expand_env` over `${VAR}` / `$(VAR)` paths.

#### Branch 7 — the fallthrough: plain files (L28–41)

```tcl
28:         } else {
30:             set file [expand_env $line]
38:             if {[string match "*.sv" $file] || [string match "*.v" $file]} {
39:                 read_hdl -define TIDELINK_PHY_V2 -language sv $file
40:             }
41:         }
```

> **Genus Command Reference — `read_hdl` (`genus_comref/inout.html`):**
> "`read_hdl file_list [-language {v2001 | v1995 | sv | vhdl}] [-library …] [-netlist]
> [-f filename] [-define macro=value]... file_list.....` — Loads one or more HDL files in
> the order given into memory. Files containing macro definitions should be loaded before
> the macros are used. … **If you do not specify either the v1995, v2001, sv or the vhdl
> option, the default language format is that specified by the `hdl_language` attribute.
> The default value for the `hdl_language` attribute is v2001.**"
> - "`-language` — Specifies the language of the HDL files. It can be any one of the
>   following: `sv`, `v1995`, `v2001` (default) and `vhdl`."
> - "`-define macro=value` — Defines a Verilog macro with the specified value, which is
>   equivalent to the `` `define macro value ``. You can also define a macro definition
>   list."

The manual's own example uses the same trick this script does —
`read_hdl -language sv file2_bhv.v`, an SV read of a `.v` file.

**Why both `.v` and `.sv` are read as SystemVerilog**, in the script's own words:

```tcl
31:             # Read BOTH .sv and .v as SystemVerilog. Several project ".v" leaves
32:             # (e.g. ethernet-subsystem-ahb/.../asic_lib/sram/sl_sram.v, the
33:             # DMA-250 SoC-Labs glue) use SV constructs — localparams inside a
34:             # generate scope, the '0 fill literal, initial $error — so strict
35:             # -language v2001 fails with VLOGPT-9. This mirrors the Fusion
36:             # Compiler read_design wrapper, which reads the whole SoC as one SV
37:             # language unit. SV is a Verilog-2001 superset for this codebase.
```

The default would be `v2001` (per the attribute default quoted above), and 412 of the 597
files are `.v`. Reading them as `v2001` fails on the SV-flavoured leaves. Reading them as
`sv` works because SystemVerilog is a superset — with the standard caveat that a few
identifiers reserved in SV but legal in Verilog-2001 (`bit`, `logic`, `do`, `final`,
`ref`…) would now be errors. That has not bitten this codebase.

The alternative Genus offers, and this script does not use, is
`hdl_set_vlog_file_extension` — per the same chapter, `hdl_set_vlog_file_extension -sv .v2
.v3` makes a *per-extension* language assignment. It would not help here, since the split
is within `.v`, not across extensions.

##### The filter silently drops everything that is not `.v` or `.sv`

This is the branch's real problem. The `if` at L38 has **no `else`**. Anything that reaches
the fallthrough and does not end in `.v` or `.sv` is discarded without a word. Measured,
there are exactly three such lines in the four flists:

```
+define+ETH_WISHBONE_B3
+define+TIDELINK_PHY_V2
.../tidelink/deps/tidelink-phy/rtl/tidelink_sync_word.svh
```

The `.svh` is an include header and arguably *should* be skipped (it is found via
`+incdir+`, not read directly) — but silently is the wrong way to skip it.

**The two `+define+` lines are a genuine synthesis/simulation divergence.**
`read_flist.tcl` has no `+define+` branch, so both fall through to L38, fail the extension
test, and vanish. One of them is compensated for: L39 hardcodes
`-define TIDELINK_PHY_V2` onto every `read_hdl`, which is why the flist's own
`+define+TIDELINK_PHY_V2` being dropped does not matter. **`ETH_WISHBONE_B3` has no such
compensation.** Consequences, traced through the RTL:

- `$IP_LIBRARY_ROOT/ip_library/OpenCores-EthMAC/rtl/verilog/eth_defines.v:320` has it
  **commented out** (`` //`define ETH_WISHBONE_B3 ``), so the only way to define it is from
  the command line — which is exactly what the flist line is for.
- It is `` `ifdef ``-guarded in 14 places across `eth_top.v` and `eth_wishbone.v`,
  including **`eth_top`'s port list**: `m_wb_cti_o` (Cycle Type Identifier) and
  `m_wb_bte_o` (Burst Type Extension) exist only when it is defined.
- The project wrapper
  `ethmac_ahb.v`
  declares those two wires **unconditionally** (L111–112) and feeds them into the
  Wishbone→AHB bridge **unconditionally** (L170–171,
  `.from_m_wb_cti_o(m_wb_cti_o)` / `.from_m_wb_bte_o(m_wb_bte_o)`), but connects them from
  `eth_top` only **inside** `` `ifdef ETH_WISHBONE_B3 `` (L223–226).
  `ethmac_subsystem_apb.v` has the identical shape (L266–267, L288–289, L336–337).

So: **VCS, which reads the same flist and honours `+define+`, builds a design in which
`m_wb_cti_o`/`m_wb_bte_o` are driven by the MAC. Genus, reading through
`read_flist.tcl`, builds one in which they are undriven inputs to the bridge.** The
simulated netlist and the synthesised netlist are not the same design. Whether it is
*harmful* is a separate question — Wishbone `cti == 3'b000` is "classic cycle", the bridge's
own formal harness assumes exactly that, and undriven-to-constant-0 lands on the benign
value — but "benign by luck" is not a property anyone verified on purpose. *(The undriven
consequence is inference from reading the RTL; Genus was not run for this page.
`make lec` is the check that would settle it — see [13-lec](../13-lec.md).)*

**Fix, both halves:**

```tcl
} elseif {[string match "+define+*" $line]} {
    lappend ::flist_defines [expand_env [string range $line 8 end]]
} else {
    set file [expand_env $line]
    if {[string match "*.sv" $file] || [string match "*.v" $file]} {
        read_hdl -define $::flist_defines -language sv $file
    } elseif {![string match "*.svh" $file] && ![string match "*.vh" $file]} {
        puts stderr "WARNING: read_flist: ignoring unrecognised entry: $line"
    }
}
```

The `-define` option "can also define a macro definition list", per the manual, so passing
an accumulated list is supported. **Not tested.** At minimum, the missing `else` should
warn: a filelist parser that drops lines it does not understand, in silence, in a flow
where both tools exit 0 on failure, is the wrong failure mode for this project.

#### Close

```tcl
43:     close $fh
```

Closes on the normal path only. An error inside the loop (an unset environment variable
from `expand_env`, a `read_hdl` failure) leaves the handle open — irrelevant in practice
since the process is about to die anyway.

---

## `procs.tcl` — `expand_env`

25 lines, one proc, sourced by `config.tcl:1`.

```tcl
 1: # Helper: expand ${VAR} and $(VAR) references to environment variable values.
 2: # The hand-maintained project flists use ${VAR}; the nanosoc_gen-emitted flists
 3: # (build_soc/flist/*.flist, which the ASIC flist -f-includes) use make-style
 4: # $(VAR). Support both so the generator's native filelists can be -f'd directly
 5: # (keeps the interconnect leaf list auto-in-sync instead of hand-inlined).
 6: proc expand_env {str} {
 7:     while {[regexp {\$\{(\w+)\}} $str -> varname]} {
 8:         if {[info exists ::env($varname)]} {
 9:             set pattern "\\$\\{${varname}\\}"
10:             regsub $pattern $str $::env($varname) str
11:         } else {
12:             error "Environment variable $varname is not set"
13:         }
14:     }
15:     while {[regexp {\$\((\w+)\)} $str -> varname]} {
...
23:     return $str
24: }
```

### Why two syntaxes

Not stylistic — two *producers*:

| syntax | produced by | example, measured |
|---|---|---|
| `${VAR}` | the hand-maintained project flists | `-f ${NANOSOC_ETH_CHIPLET_HOME}/build/chip/flist/tidelink_asic.flist`, `+incdir+${TIDELINK_HOME}/src/rtl` |
| `$(VAR)` | the `nanosoc_gen` generator's native flists | Makefile-style, emitted by the SoC generator |

The header states the payoff: supporting `$(VAR)` means the generator's own filelists can
be `-f`-included directly, so the interconnect leaf list stays auto-in-sync instead of
being hand-copied into a `${}`-syntax duplicate that drifts. That is the same reasoning
recorded in the top-level flist's own comments about the SoC's in-sync vs. flat flists.
The cost of *not* supporting both is a hand-maintained copy of a generated file — the
classic source of "the netlist is not what the generator emits".

Neither syntax is Tcl's. `$::env(VAR)` is Tcl; `${VAR}` and `$(VAR)` are shell and Make
respectively, and a Tcl script must expand them itself. There is no Genus or Innovus
command that does this — checked, and none is documented.

### Mechanics and edges

- **Loop, not one-shot.** `while [regexp …]` re-scans after each substitution, so multiple
  references in one line all get expanded, and a value that itself contains `${OTHER}` is
  expanded recursively. Terminates as long as no variable expands to a reference to itself.
- **`\w+` only.** Variable names are `[A-Za-z0-9_]+`. `${VAR-WITH-DASH}` or `${VAR.X}`
  would not match and would pass through untouched into a path that then fails to open.
- **Two independent passes.** `${}` first, then `$()`. Mixing both syntaxes in one line
  works.
- **`error`, not silence.** L12 / L20 raise
  `Environment variable <NAME> is not set` — a real Tcl error that propagates out of
  `read_filelist` and stops synthesis. This is the exact failure mode
  [`ASIC/common.mk`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ASIC/common.mk) documents for `TIDELINK_HOME` /
  `TIDECHART_HOME`: because the affected `-f` includes come *last* in the top flist, Genus
  reads the whole SoC first and dies ~10 minutes in, which reads like a link-stage problem
  rather than a missing export. `common.mk` exports both to prevent it.
- **Latent `regsub` hazard.** `regsub $pattern $str $::env($varname) str` puts the
  environment value in `regsub`'s *substitution* argument, where `&` means "the whole
  match" and `\1` means a capture group. A path containing `&` would be corrupted. No such
  path exists in this repo *(measured — all four flists resolve cleanly)*, but
  `regsub -- $pattern $str [string map {& \\& \\ \\\\} $::env($varname)] str`, or simply
  `string map`, would remove the hazard. **Not tested.**

---

## What a reader must supply

Every environment variable **this layer** dereferences. Variables read by the *stage*
scripts (`SOCLABS_ASIC_FLOW_DIR`, `CALIBRE_HOME`) are out of scope here and covered in
[01-flow-overview](../01-flow-overview.md#environment).

| variable | read at | mandatory? | failure mode if absent |
|---|---|---|---|
| `TSMC_65_HOME` | `config.tcl` L72, 73, 131, 133, 134 | **yes** | `config.tcl` dereferences `$::env(...)` directly, so sourcing raises a Tcl "no such variable" error at L72. Under Genus `-f` that drops to the prompt and **exits 0**; under Innovus `-files` it aborts the stage. Either way no netlist, no DB. |
| `NANOSOC_ETH_CHIPLET_HOME` | `config.tcl` L83, 84, 120, 160 | **yes** | identical, first at L83. Kills the ROM-lib, top-HDL and local-override-LEF paths. |
| `ASIC_FLIST` | `read_flist.tcl` L46 | **yes** (Genus only) | Tcl "no such variable" on the last line of `read_flist.tcl`, i.e. at `1_synthesis.tcl:26`. No RTL is read. Innovus never sources this file, so it does not matter for P&R. |
| `TIDELINK_HOME` | *inside* the flists, expanded by `expand_env` | **yes** (Genus only) | `error "Environment variable TIDELINK_HOME is not set"` — but raised **~10 minutes in**, after the entire SoC has been read, because the `-f` include that needs it comes last. Reads like a link-stage failure. |
| `TIDECHART_HOME` | *inside* the flists, expanded by `expand_env` | **yes** (Genus only) | same, same lateness. |
| `INNOVUS_LOCAL_CPU` | `config.tcl` L225 | no — defaults to `14` | none; the loop's `elseif` supplies the default. A value above the core count is a warning, and Innovus runs with the maximum available. |
| `INNOVUS_DISTRIBUTED` | `config.tcl` L226 | no — defaults to `0` | none. A non-numeric value would make the `expr` at L245 raise, since it is used as a boolean operand. |
| `INNOVUS_REMOTE_HOSTS` | `config.tcl` L227 | no — defaults to `{}` | none; empty disables distribution via the `llength > 0` guard. |
| `INNOVUS_CPU_PER_REMOTE` | `config.tcl` L228 | no — defaults to `6` | none; only read when distribution is on. |
| `PHYS_IP` | **commented out** at `config.tcl` L132 | **no** | none. Listed as required in older notes; this layer does not read it. |

`ASIC/common.mk` exports all of the mandatory ones with `?=`, so a shell that has run
`make` has them and a bare login shell does not. If `source ../scripts/config.tcl` dies on
`$::env`, that is what happened — see
[02-innovus-basics](../02-innovus-basics.md#starting-a-session-and-loading-the-design).

Beyond the environment, the layer also assumes these exist on disk. All were checked
present on this host at the time of writing:

- 10 Liberty files (2 TSMC, 6 memory-compiler, 2 ROM) resolvable from
  `lib_search_path_list`
- 12 LEF files, tech LEF first
- 8 macro GDS2 files for the stream-out merge
- `ASIC/tech_wrappers/tsmc65/nanosoc_eth_chiplet_pads.v` (the top)
- `ASIC/genus-innovus/inputs/constraints.sdc`
- the Calibre ruledeck at the hardcoded `$TSMC_65_HOME` path
- **not** `ASIC/genus-innovus/scripts/dft_setup.tcl` — absent, and only reachable if
  `DFT` is changed to 1

---

## Defects and divergences found while writing this page

Ordered by how much they could cost. None of these were fixed here; this page changes no
code.

| # | where | finding | evidence | status |
|---|---|---|---|---|
| 1 | `read_flist.tcl` L38–40 | **`+define+` lines are silently dropped.** `+define+ETH_WISHBONE_B3` never reaches Genus, so `eth_top`'s `m_wb_cti_o`/`m_wb_bte_o` are unconnected in synthesis while VCS, reading the same flist, drives them. Sim and synth build different designs. | measured (flist parse); RTL traced in `eth_top.v`, `eth_defines.v:320`, `ethmac_ahb.v` L111/170/223 | **inference** on the netlist effect; the dropped line is measured |
| 2 | `read_flist.tcl` L38–40 | The same `if` has **no `else`** — any unrecognised entry vanishes without a warning, in a flow where both tools exit 0 on failure. | measured | measured |
| 3 | `read_flist.tcl` L16 | `set_db init_hdl_search_path $incdir` **replaces** rather than appends. 20 `+incdir+` lines; only the most recent is live. Works today only because the generator restates directories. | measured; `genus_attref/inout.html` | measured |
| 4 | `config.tcl` L18–21 | The comment rejects `clp_treat_errors_as_warnings` as ineffective. The manual types it **`string`** — "the specified error message IDs" — so a boolean value would be a no-op by construction. The conclusion stands; the stated reason does not. | `genus_attref/inout.html` | manual vs. comment |
| 5 | `config.tcl` L27–28 | `check_cpf -continue_on_error` is a documented per-call option that does exactly what the wrapper's `catch` approximates, with no portability problem. Never mentioned. | `genus_comref/advanced_lps.html` | untested suggestion |
| 6 | `read_flist.tcl` L17–20 | The `-y` branch calls `set_app_var`/`get_app_var`, **which are in no Genus manual** — Design Compiler leftovers. Dead today (0 `-y` lines); would abort if ever reached. | measured (exhaustive doc search + control search) | measured |
| 7 | `config.tcl` L123 + `1_synthesis.tcl` L50–52 | `DFT 1` cannot work: **`scripts/dft_setup.tcl` does not exist.** | measured | measured |
| 8 | `config.tcl` L3 vs `preplace.tcl` L2 | `design_process_node` set twice, once from `$process_node` and once as the literal `65`. Two sources of truth. | measured | measured |
| 9 | `config.tcl` L209 | `drc_ruledeck` is absolute, not `$::env(TSMC_65_HOME)`-relative, unlike every other PDK path in the file. | measured | measured |
| 9b | `2_pnr_setup.tcl` L27 | `read_physical -lef` — the Stylus manual's parameter is **`-lefs`** (plural). `-lef` works only as an unambiguous abbreviation, and the same manual page's prose contradicts its own synopsis on this. Cosmetic, but `-lefs` is the documented spelling. | `TCRcom/read_physical.html` | manual vs. script |
| 10 | `config.tcl` L101–112 | `syn_lib_list` is a flat list where the attribute grammar wants braced groups. The manual does not document the flat case; under the literal grammar it would mean "master + 9 appended". | `genus_attref/library.html` | **inference** — check `logs/syn_lib_check.log` from a real `make syn` |
| 11 | `procs.tcl` L10, L18 | `regsub` puts the env value in the substitution argument, where `&` and `\N` are metacharacters. No affected path exists today. | measured (all 4 flists resolve) | latent |
| 12 | `config.tcl` L56–57 | Comment calls the log capture "the call site redirects stdout"; per the manual `> file` is `check_cpf`'s own documented option. Same effect, imprecise description. | `genus_comref/advanced_lps.html` | cosmetic |

**Everything the file claims about the LEF override checks out exactly** — the `USE`
default, `IMPDB-1221`'s meaning, `NRDB-51`'s consequence, the three-line diff, the three
macro/pin targets, and that all three macros are instantiated in the pad ring. That block
is the best-documented thing in the flow and it is right.

---

## Manual pages cited

Every page below was opened on this machine. Nothing here is quoted from memory.

**Genus** — `$CDS_INSTALL/genus/doc/`

| citation | file |
|---|---|
| Genus Command Reference — `check_cpf`, `commit_power_intent`, `create_library_domain` | `genus_comref/advanced_lps.html` |
| Genus Command Reference — `read_hdl`, `hdl_set_vlog_file_extension`, `read_libs` | `genus_comref/inout.html` |
| Genus Command Reference — `set_multi_cpu_usage`, `set_db` | `genus_comref/general.html` |
| Genus Attribute Reference — `init_lib_search_path`, `init_power_nets`, `init_ground_nets`, `fail_on_error_mesg` | `genus_attref/general.html` |
| Genus Attribute Reference — `init_hdl_search_path`, `clp_treat_errors_as_warnings` | `genus_attref/inout.html` |
| Genus Attribute Reference — `library` (library_domain), `default` (library_domain) | `genus_attref/library.html` |
| Genus Message Reference — RCLP-201/202/**203**/205/206 | `genus_messages/RCLP_Error_Messages.html` |
| Genus Library Guide — "Liberty Support" (2009.06 attribute support matrix) | `genus_library/liberty_support.html` |
| LEF/DEF 5.8 Language Reference — Macro Pin Statement, `USE`, `SUPPLYSENSITIVITY`, MACRO CLASS | `lefdefref/LEFSyntax.html` |

**Innovus — Stylus / Common UI** (`$INNOVUS_HOME/doc/`). These are the ones that
apply to this flow.

| citation | file |
|---|---|
| Stylus Common UI Text Command Reference — `set_multi_cpu_usage` | `TCRcom/set_multi_cpu_usage.html` |
| Stylus Common UI Text Command Reference — `set_distributed_hosts` | `TCRcom/set_distributed_hosts.html` |
| Stylus Common UI Text Command Reference — `write_stream` | `TCRcom/write_stream.html` |
| Stylus Common UI Text Command Reference — `connect_global_net` | `TCRcom/connect_global_net.html` |
| Stylus Common UI Text Command Reference — `read_physical` | `TCRcom/read_physical.html` |
| Stylus Common UI Text Command Reference — `init` Category Attributes (`init_power_nets`, `init_ground_nets`, `init_lef_files`, `init_ignore_pg_pin_polarity_check`) | `TCRcom/init_Category_Attributes.html` |
| Stylus Common UI Text Command Reference — `design` Category Attributes (`design_process_node`, `design_tech_node`) | `TCRcom/design_Category_Attributes.html` |
| Stylus Common UI Text Command Reference — `check_multi_cpu_usage` | `TCRcom/check_multi_cpu_usage.html` |
| Stylus Common UI User Guide — Accelerating the Design Process By Using Multiple-CPU Processing | `UGcom/Accelerating_the_Design_Process_By_Using_Multiple-CPU_Processing.html` |
| Stylus Common UI User Guide — Data Preparation ("Preparing Timing Libraries") | `UGcom/Data_Preparation.html` |
| Stylus Common UI Error Message Reference — NRDB-51 | `EMRcom/NRDB-51.html` |
| Stylus Common UI Error Message Reference — IMPDB-1220 (neighbour of the absent 1221) | `EMRcom/IMPDB-1220.html` |

**Innovus — legacy UI.** Cited only where the Stylus set omits something, and labelled as
legacy at each use site.

| citation | file | why the legacy page was needed |
|---|---|---|
| Innovus User Guide (legacy) — Importing and Exporting Designs | `innovusUG/Importing_and_Exporting_Designs.html` | the **"if a cell is defined multiple times … only the first definition"** rule; searched for and **not present** anywhere in `UGcom/` or `TCRcom/` |
| Innovus Text Command Reference (legacy) — `setMultiCpuUsage` | `innovusTCR/setMultiCpuUsage.html` | the explicit **"cannot be more than the number of CPUs available in the local computer"** ceiling, which `TCRcom/set_multi_cpu_usage.html` drops |
| Innovus Error Message Reference (legacy) — NRDB-51 | `innovuserrmsg/NRDB-51.html` | only to show the remedy-command naming differs between the two sets |
| Innovus **16.13** Error Message Reference — IMPDB-1221 | `$CDS_INSTALL/2016-17/RHELx86/INNOVUS_16.13.000/doc/innovuserrmsg/IMPDB-1221.html` | the page exists in **no** 21.x set, Stylus or legacy |

**Explicitly not found in any installed manual**, and therefore not cited as documented
anywhere above:

- `IMPDB-1221` — absent from `EMRcom/` **and** `innovuserrmsg/` (both 21.10); only the
  16.13 copy exists on this box
- `IMPDBTCL-247` — absent from `EMRcom/`, `innovuserrmsg/` **and** the 16.13 tree
- `IMPSP-5110` — absent from `EMRcom/` and `innovuserrmsg/` (it is real; `man IMPSP-5110` at
  a live prompt resolves it — see [02-innovus-basics](../02-innovus-basics.md))
- "a cell defined multiple times → first definition wins" — absent from the entire Stylus
  documentation set; legacy-only
- `set_app_var` / `get_app_var` — absent from the entire Genus documentation tree
- `set_distributed_hosts` — absent from the entire Genus documentation tree
- `check_cpf` — absent from the entire Innovus documentation, Stylus and legacy alike
- `-lef` as a `read_physical` parameter — the documented spelling is `-lefs`; `-lef`
  appears only in that page's prose, not in its synopsis or parameter table

---

Back to [00-index](../00-index.md) · [01-flow-overview](../01-flow-overview.md) ·
[02-innovus-basics](../02-innovus-basics.md). For what the *stage* scripts do with all of
this, read [03-floorplan](../03-floorplan.md) onward.
