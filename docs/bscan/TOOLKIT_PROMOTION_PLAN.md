<!--
  docs/bscan/TOOLKIT_PROMOTION_PLAN.md
  A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.

  Copyright 2026, SoC Labs (www.soclabs.org)
-->
# Promoting the boundary-scan flow into `nanoSoC-ASIC-Toolkit`

**Status: PREPARED, NOT APPLIED.** Nothing in `ASIC/asic-toolkit/` has been touched by
this work. This document is the reviewable patch set: what moves, where, why, what it
costs existing consumers, and in what order — to be executed once the submodule is clean.

**Measured 2026-08-19/20**, against:

| tree | state |
|---|---|
| `nanosoc-ethernet-chiplet` | `feat/padring-boundary-scan`, boundary-scan paths **clean and committed** |
| `ASIC/asic-toolkit` worktree | `8e23478` on `fix/tcl-parse-gate-both-directions` |
| superproject's recorded pin | `55eb607` — **pin drift**, `git submodule status` reports `+` |
| toolkit dirt | 10 entries: 6 modified tracked, 4 **untracked** paths (`flow/power/`, `flow/verify/check_fp_pg.tcl`, `test/power/`, `test/verify/check_fp_pg.test`) |

Every count below has a date on it. Re-measure before quoting — the toolkit's own
`PROMOTION_FROM_NANOSOC_ETH.md` §6 makes that point and it applies to this page too.

---

## 0. Two premises re-measured before anything is built on them

`PROMOTION_FROM_NANOSOC_ETH.md` opens by correcting a wrong premise that nearly shipped as
a gate, and draws the general lesson: **the premise of a gate is itself a thing that must
be measured.** Two premises this work was commissioned with did not survive measurement.

### 0.1 The `DFT` switch is not dead in the way the backlog says

The brief states, and `MIGRATION_NANOSOC_ETH.md:1621` records, that *"`1_synthesis.tcl:51`
sources `../scripts/dft_setup.tcl`, which exists nowhere in the tree."*

**That describes the LEGACY flow, and the file it names no longer exists.**
`ASIC/genus-innovus/scripts/1_synthesis.tcl` is absent from this repository — the legacy
directory retains `config.tcl`, `floorplan.tcl`, the eval scripts and the Calibre wrappers,
but not the synthesis stage. The backlog item is describing a file that has already been
retired.

What the **toolkit** does today, measured:

| where | behaviour |
|---|---|
| `mk/flow.mk:259` | `DFT_SETUP_TCL ?=` — empty default |
| `mk/flow.mk:373` | exported as `ASIC_DFT_SETUP_TCL` |
| `flow/genus/1_synthesis.tcl:136-137` | reads `::DFT` (default 0) and the env var |
| `flow/genus/1_synthesis.tcl:910-918` | `if {$DFT}` → if `DFT_SETUP_TCL` is empty or missing, **`die` with an actionable message naming the variable and what the file must declare** |
| `flow/genus/1_synthesis.tcl:984-990` | `convert_to_scan` / `connect_scan_chains` / `report_scan_chains` |
| `flow/genus/1_synthesis.tcl:1184-1190` | `report_scan_setup`, `report_scan_registers`, `write_dft_abstract_model`, `write_scandef` |
| `flow/innovus/3_cts.tcl:1323` | `if {[info exists ::DFT] && $::DFT}` |
| `scripts/asic-flow-check:384` | `optional(... "DFT_SETUP_TCL" ... "no scan insertion")` |

So `DFT=1` does abort — but by **an explicit `die` that names the missing variable**, not by
sourcing a path that does not exist. There is no `dft_setup.tcl` anywhere in the tree and no
template for one (`find . -name 'dft_setup*'` → empty), so the switch is **unimplemented but
honest**, not broken. The distinction matters, because "broken switch" argues for deletion
and "unimplemented switch with a good refusal" argues for leaving it alone. See §3.3.

**And the more important point: `DFT` is INTERNAL SCAN.** `convert_to_scan` and
`connect_scan_chains` stitch mission-mode flops into shift chains. Boundary scan is a
*separate register at the pad boundary* that shares neither mechanism nor collateral with
it. `asic-flow-check` already spells this correctly — *"no scan insertion"*. Conflating the
two is the single most likely way this promotion goes wrong.

### 0.2 "35 scenarios today" is 34 scenarios and a README — and the number is load-bearing

`ls test/stage/scenarios/` returns 35 entries. `find test/stage/scenarios -name '*.tcl' |
wc -l` returns **34**, and `test/MUTATION_COVERAGE` declares `stage-scenarios 34`.

This is not pedantry. `test/shell/t_mutation_inventory.sh:162-164` counts the `.tcl` files
and asserts equality **in both directions** — a scenario added without bumping the
declaration turns the whole toolkit suite red for every consumer. See §6.1, where this is
the single largest migration risk in the set.

---

## 1. What is being promoted, and the evidence for it

A complete IEEE 1149.1 boundary-scan flow, proven end to end on this chiplet and validated
read-only against a second consumer.

**End to end on eth**, `RUN_TAG=bscan-probe`: RTL → synthesis → place → CTS → route →
GDS. `ASIC/eth-chiplet/build/bscan-probe/outputs/` holds a 35.3 MB post-synthesis netlist
(14:06), a 42.4 MB post-route netlist (18:57) and a 311 MB stream. The gate-level bench
reports `BSCAN_GATE_SUMMARY: PASS checks=5063 fails=0 tests=7/7` against the **routed**
netlist.

**Two honest caveats that must travel with the 7/7 claim**, both already stated in
`verif/bscan/README.md` and neither visible from the summary line:

- 4,372 of the 5,063 comparisons are T6's per-tick TDO-enable checks, so the 4,000 floor in
  `run_gate.sh` is a *"the bench reached the end"* test, not a stimulus-depth test.
- **Only 5 of the 7 tests are mutation-proven.** T0 (TAP inert at SE=0) and T6 (TDO
  hygiene) are not discriminated by the measured mutation table. "7/7" is literally true
  with 5 backed by evidence — and a toolkit that publishes the number without the
  qualifier is doing the thing this project keeps finding in other people's greens.

The RTL sibling measures `BSCAN_SUMMARY: PASS checks=40136 fails=0 tests=11/11`.

**The second consumer has already paid out, which is the whole argument.**
`PROMOTION_FROM_NANOSOC_ETH.md` §1 rests its case on the compute chiplet finding a
`read_flist.tcl` defect *structurally unreachable on eth*. The same shape repeated here,
during this work, at commit `5be5ccf`:

> `insert_bscan_padring.py` still emitted `nanosoc_eth_chiplet_bscan %s (` after the
> identity refactor. It **elaborated on eth — right name by accident** — and failed on
> compute with `Unknown module type: nanosoc_eth_chiplet_bscan`. A hardcoded name is
> invisible to the design it was hardcoded for.

Read-only cross-validation against the compute chiplet, nothing written there, its pad ring
confirmed untouched:

| | eth | compute |
|---|---:|---:|
| signal pads | 48 | 62 |
| driver cell types | 4 | 5 (`PDUW04DGZ_G`) |
| in / out / bidir / opendrain | 18/15/13/2 | 24/29/9/0 |
| boundary cells | 76 | 80 |
| wrapper ports = splice connections | 158/158 | 166/166 |

Compute exercises paths eth cannot: five driver types instead of four, and **zero
open-drain pads**, so the wired-AND special case is proven *absent-safe* rather than merely
present-correct. Its I²C pads are genuine tristates where eth folds data onto `OEN` with
`.I` tied low; the classifier distinguishes the two idioms, which is the thing that stops a
16 mA push-pull driver being placed on a wired-AND bus.

---

## 2. File-by-file mapping

### 2.1 The RTL primitives — and the one structural problem in this whole plan

**The design-agnosticism claim, verified.** Grepping the three primitives for every
design, vendor, node and site identifier returns **two hits, both in comments**:

- `bscan_cell.sv:13` — *"These two cells are the most replicated logic in the chiplet: 76 instances"*
- `bscan_ir.sv:81` — names `nanosoc_eth_chiplet_bscan.sv` as the file holding the DR mux

No hits in executable code. No vendor cell names, no `tcbn65lp`, no absolute paths. The
claim holds; the two comments are a five-minute edit.

**But the toolkit has nowhere to put them.** Measured: the toolkit ships **eleven** `.v`/`.sv`
files and **not one is design RTL**:

| file(s) | what |
|---|---|
| `flow/verify/gls/rom_readback_tb.sv` | a testbench |
| `tech/tsmc65/lec/selftest/*.v` (9) | LEC self-test stubs — deliberately trivial |
| `test/stage/project/rtl/stubchip.v` | *"Never parsed"* — exists so the flist gate has something to count |

Every top-level directory in the toolkit is **tooling that reads or writes a project**:
`flow/` the Tcl engine, `mk/` the make fragments, `scripts/` the `asic-flow-*` CLIs,
`templates/` the scaffold, `test/`, `ci/`, `tech/` the process abstraction, `examples/` a
worked project. `bscan_cell.sv` is the first thing that would be **part of the consumer's
netlist and on their reticle**. `README.md:26` states the contract as *"You never edit the
toolkit; it never writes into your source tree."* RTL that lands in the shipping netlist is
a category the contract does not currently have.

**Recommendation: a new top-level `ip/`, argued rather than assumed.**

```
ip/bscan/bscan_cell.sv          ip/bscan/bscan_ir.sv
ip/bscan/bscan_tap.sv           ip/bscan/INTERFACE_CONTRACT.md
```

The argument, and the two alternatives with their costs:

- **`flow/dft/rtl/` — rejected.** `flow/` is documented as the engine, sourced by Genus and
  Innovus, that a project never reads directly. RTL there would be the only thing in the
  tree a *simulator* and a *foundry* care about, filed under the directory whose defining
  property is that the project never touches it.
- **`templates/rtl/bscan/` — rejected, and the rejection is measurable.**
  `scripts/asic-flow-init:152` walks the **entire** `templates/` tree and installs every
  file into `<project>/asic/`. Filing the primitives there means each consumer gets a
  **private copy** — which is a fork, three chiplets deep, of the exact leaf logic whose
  value is being identical everywhere. This repository already carries a standing lesson
  about duplicate copies of one source.
- **`ip/` — recommended.** A distinct top level makes the ownership and licensing question
  *visible*, which is the right outcome for RTL that reaches a reticle, and it leaves the
  four existing categories describing exactly what they describe today.

**This is the one item that needs an owner's paragraph before it moves**, structurally the
same call `PROMOTION_FROM_NANOSOC_ETH.md` §2 defers on `rom_gds_bits.py`. It is not a
vendor-collateral question — the RTL is entirely this project's own — it is a question of
whether the toolkit becomes an IP supplier as well as a flow engine. Everything else in
this plan can land without it.

**Stays project-side:** `src/rtl/bscan/pad_table.json` and
`src/rtl/bscan/nanosoc_eth_chiplet_bscan.sv` — both generated, both per-die.

### 2.2 The five Python tools → `scripts/asic-flow-bscan-*`

Direct fit with the existing convention. All five are option-only (zero positional
arguments across the set), none reads `os.environ` or `CHIPLET_HOME`.

| source | destination | blockers to fix in the move |
|---|---|---|
| `scripts/gen_pad_table.py` (269 ln) | `scripts/asic-flow-bscan-table` | **zero** design identifiers in code. Drop the `--idcode` default `"0x10001001"` — a second die that omits the flag silently inherits eth's identity |
| `scripts/gen_bscan.py` (1500 ln) | `scripts/asic-flow-bscan-gen` | **worst offender.** `RTL_OUT`/`BSDL_OUT` default to `__file__`-relative paths *containing the design name* (`:74-75`), and `make bscan-gen` calls it **with no arguments**, so the defaults are the live path. Also `assert inst.startswith("uPAD_")` (`:157`) and design prose baked into both emitted banners |
| `scripts/insert_bscan_padring.py` (228 ln) | `scripts/asic-flow-bscan-splice` | **hard blocker at `:211`** — the insertion anchor regex names a specific TSMC cell *and* a specific pad instance: `PDDW04DGZ_G\s+uPAD_SE_I`. The fallback still assumes `PD[DU]W\d+DGZ_G` + `uPAD_`. On a ring matching neither, `anchor` is `None` and `:214` raises `AttributeError` — an uncaught crash, not a diagnosed error |
| `scripts/bscan_syn_verdict.py` (248 ln) | `scripts/asic-flow-bscan-verdict` | clean of design names. Delete the dead `if False:` block at `:225-230`. `expect_seq` at `:116` hardcodes the TAP shape (`+32+1+4+8+2`, where 8 is `2*IR_WIDTH`) — fine today, silently wrong if `IR_WIDTH` ever becomes configurable |
| `scripts/bscan_bsdl_crosscheck.py` (1948 ln) | `scripts/asic-flow-bscan-bsdl-check` | **cleanest of the five.** Three required inputs, no defaults that resolve to this repo, both module names read from the artefacts. Only `"SoC Labs"` in two warning strings |

`gen_bscan.py`'s 1500 lines are **~53% artefact emission, not logic** (95-line RTL banner +
250-line renderer + 52-line BSDL banner + 395-line renderer); 56.9% of its bytes are string
literals. There is no embedded pad table and no template file to extract — worth knowing
before anyone proposes "just externalise the templates".

**Normalise the executable bits on the way**: `gen_bscan.py` and `bscan_bsdl_crosscheck.py`
are `755`, the other three `644`, though all five carry a shebang. Harmless while the
Makefile calls `python3 <script>`; not harmless once they are on `scripts/` beside 25
executables.

**Technology, not design — the real portability surface.** Already tabular and liftable
into a tech pack: `SIGNAL_CELL_PREFIXES`, `SIDES`, `ROLES`, `BSDL_DIR`, `_OUT_PINS`,
`_CLOCK_PINS`, `_ASYNC_PINS`. **Scattered inline and harder**: the pad-cell port vocabulary
`.C`/`.I`/`.OEN`/`.REN`/`.PAD` plus `tielo`/`tiehi` (across the table generator and the
splicer), the `tcbn65lp` flop regexes `\.CP`/`\.CPN`/`(?:S?DF|EDF|QDF)` in the verdict
script, `VDD`/`VSS`/`SI`/`SE`/`D` in the crosscheck, and `"WIREBOND"` as the BSDL physical
pin map. **Promote the tabular half into `tech/<TECH>/` now; leave the inline half inline
and say so** — a half-done tech pack that looks complete is worse than an honest one.

### 2.3 The benches → `flow/verify/bscan/`

Exact precedent: `flow/verify/gls/` already holds a testbench (`rom_readback_tb.sv`),
generators (`gen_netlist_tb.py`, `gen_rom_shim.py`, `pg_complete.py`) and runners
(`run_gls_rom.sh`, `run_gls_netlist.sh`), driven from `mk/gls.mk` with a `GLS_*` knob
namespace and a `*-selftest` mutation target. Boundary scan is the same shape.

| source | destination | note |
|---|---|---|
| `verif/bscan/gen_tb_pads.py` (346 ln) | `flow/verify/bscan/gen_tb_pads.py` | **most promotable file in the set.** One executable design hit — `:303` hardcodes `nanosoc_eth_chiplet_bscan` *even though the table it just parsed carries `design.module`*. One-line fix. Also `:149`'s `if n_pads != 48 or n_cells != 76` warning → table-derived |
| `verif/bscan/tb_bscan.sv` (965 ln) | `flow/verify/bscan/tb_bscan.sv` | **zero design identifiers in code** — the DUT is instantiated inside the generated `.svh`. Fix `N_CELLS == 76` at `:488` to read the generated header |
| `verif/bscan/run.sh` (182 ln) | `flow/verify/bscan/run_bscan_rtl.sh` | one real binding: the module-name grep at `:84`. No absolute paths; `CHIPLET_HOME` derived at `:45` |
| `verif/bscan/run_gate.sh` (462 ln) | `flow/verify/bscan/run_bscan_gate.sh` | **promote the machinery, leave the wiring** — see below |
| `verif/bscan/tb_bscan_gate.sv` (1009 ln) | `templates/verif/tb_bscan_gate.sv.in` **+ the eth copy stays** | inherently per-die: `:219` instantiates `nanosoc_eth_chiplet_pads` with a **hand-written 28-port connection list**, plus six literal chain-index arrays. Its *shape* ports; its content cannot |
| `verif/bscan/README.md` (459 ln) | split | ~⅔ is doctrine that ports unchanged (*"why the verdict is not just `$?`"*, the `_pnr_pg.v` shadowing trap, the PG-completion deviation, *"a zero that measured nothing"*) → `flow/verify/bscan/README.md`. ~⅓ is eth fact → stays |
| `verif/bscan/build/`, `build_gate/` | **neither** | build artefacts, 2.1 MB and 222 MB |

**`run_gate.sh` carries four reusable guards worth more than the runner:**

1. **The library-shadowing guard** (step 2) — catches the `_pnr_pg.v` trap that produced a
   clean run over an all-`z` design.
2. **PG-completion with a non-zero assertion** (step 3) — refuses `pg_complete.py`'s
   cheerful `0`.
3. **The chain-map drift guard** (step 1) — re-derives every hand-written TB literal from
   `pad_table.json` on each run and exits 2 on drift. *This is the pattern that makes a
   per-die testbench safe*, and it is the transferable idea in the whole file.
4. **`rm -rf $BUILD` on every run** — the stale-build trap, closed by construction.

It also reads `MEM_BASE`/`TSMC_65_HOME`/`PHYS_IP` out of `ASIC/common.mk` with `sed` rather
than hardcoding them, documented at `:87-93` as *"this repository is public, and an absolute
mount paired with a revision-coded release directory is together an inventory of what this
site is licensed to hold."* That reasoning belongs in the toolkit verbatim — it is exactly
`VENDOR_COLLATERAL.md`'s position, independently arrived at.

Per-die and belonging in config: the `MEM_V`/`ROMLIBS`/`bondpad_stubs`/`PROBE_OUT`
collateral block, and the 16-entry pad-name list at `:209-211`.

**One cross-cutting fact the toolkit must publish, because it is invisible and green:**
neither testbench uses `$fatal`, `$error` or `$stop`. Both terminate on `$finish` after
printing a summary line, so **`simv` exits 0 on failure** and the shell runner is the sole
adjudicator (four conjuncts: summary line present, verdict `PASS` with `fails=0`,
`tests=N/N` with N ≥ floor, `checks ≥` floor). Deliberate and documented — but anyone
wiring `tb_bscan*.sv` into a different runner without reimplementing all four gets a
permanently green gate.

### 2.4 The fixtures — and why they cannot land in the toolkit's `ci/`

**The toolkit has no `check_proof` mechanism.** `must_pass`/`must_fail` and the
partial-repo-tree sandbox belong to `scripts/ci/signoff.py` + `ci/signoff.yaml`, both of
which are **project-side**. The toolkit's `ci/` holds `pipeline.sh`, `assert-stage.sh`,
`tier.sh`, `capability.sh` and three unrelated fixture sets (`equivalence`, `tcl-good`,
`tcl-bad`). Dropping `ci/fixtures/boundary-scan/` into the toolkit's `ci/fixtures/` would
orphan it: nothing there can run it.

| source | destination |
|---|---|
| `ci/fixtures/boundary-scan/{pass,fail-*}` (9 planted files, ~331 KB) | `test/fixtures/bscan/` |
| `ci/fixtures/boundary-scan/README.md` | `test/fixtures/bscan/README.md` |
| *(new)* | `test/python/test_bscan_verdict.py` |
| `ci/fixtures/boundary-scan/PROPOSED_STANZA.yaml` | **stays project-side — and should be cut down first** |

The fixtures are excellent and worth keeping: all nine are trimmed extracts of the real
Genus 21.15 netlist of 2026-08-19, each carrying **at most one** mutation named in its own
header, ~331 KB instead of 8 × 35 MB. They map cleanly onto `test/python/`, which is
already the home of *"programs that take text files in and produce a verdict, so they are
testable exactly and exhaustively with no PDK, no licence and no EDA tool"* — and whose
`conftest.py` supplies the `mutant()`/`mutate()` contract that makes the proof able to fail.

**The defect to fix before promotion, not after.** The stanza's `check:` block
**re-implements** the verdict in inline Python and, in doing so, **re-introduces hardcoding
that the underlying script had already avoided**:

- `scripts/bscan_syn_verdict.py` locates the netlist by **glob** (`out.glob("*_pads_gate.v")`)
  with `--build` required — it never needs the design string at all.
- The stanza hardcodes `ASIC/eth-chiplet/build/bscan-probe/outputs/nanosoc_eth_chiplet_pads_gate.v`
  as a Python **string literal** in `check:`, again in `run:` as `--build`, again in
  `needs_implementation:`, and a fourth time as the shape of all eight fixture trees.

The numeric expectations **do** port — `design.boundary_length` (76 here, 80 on compute),
`design.module` and `len(pads)` all come from the table, exactly as advertised. The **paths
do not**, and the mis-port **fails green**: the stanza itself documents this as GDS_RUN_PLAN
G13 — repoint `check:` at a new tag while the fixtures still name `bscan-probe` and every
fixture becomes a fixture-shaped hole that shadows nothing, so the pass case reads the real
netlist and passes, and **the fail cases read the same real netlist and also pass**. `prove`
then reports a gate that cannot fail as eight green rows.

**So: slim the stanza's `check:` to invoking `asic-flow-bscan-verdict` and grading its exit
code plus the vacuity arm.** That deletes three of the four hardcoded paths, removes a
second implementation of one assertion, and makes the fixture trees portable by generation
rather than by `git mv`. Keep the vacuity arm inline — it is the part that has to be
readable in the manifest.

Also worth stating plainly, because two artefacts are involved: the stanza gates the
**synthesis** netlist (`…_gate.v`) while `run_gate.sh` simulates the **routed** netlist
(`…_pnr.v`). A shared toolkit must not let "the boundary-scan gate" name one file
ambiguously.

### 2.5 Make, templates, docs — the new files

| new file | why |
|---|---|
| `mk/bscan.mk` | modelled on `mk/gls.mk`: a `BSCAN_*` knob namespace, `bscan-vars`, `bscan-collateral`, `bscan-sim`, `bscan-gate`, `bscan-selftest`. Wired as `$(call asic_flow_optional,bscan)` |
| `templates/bscan.mk.in` | the third-consumer contract — §4 |
| `templates/constraints/30_bscan.sdc.in` | the *shape* of `bscan_constraints.sdc`. The eth file itself stays project-side |
| `test/python/test_bscan_verdict.py` | drives `test/fixtures/bscan/` through the verdict tool, with a mutation proof |
| `test/stage/scenarios/bsr_optimised_away.tcl` | §5 |
| `flow/genus/1_synthesis.tcl` §13b | the survival assertion — §3.2 |
| `docs/source/howto/add-boundary-scan.md` | the discovery path, beside `verify-a-boot-rom.md` |

### 2.6 Confirmed to stay project-side

- The `Makefile` config block (`BSCAN_BLOCK`, `BSCAN_MODULE`, `BSCAN_PADRING`, `BSCAN_IO`,
  `BSCAN_TABLE`, `BSCAN_TAP`, `BSCAN_IDCODE`, `BSCAN_PRISTINE`) — eight variables, not
  seven; `BSCAN_MODULE` and `BSCAN_TABLE` are in the block and in the contract.
- `ASIC/genus-innovus/inputs/bscan_constraints.sdc` — names the `SE` port, the `swdclk`
  clock and the `u_nanosoc_eth_chiplet_bscan` instance. Irreducibly per-die.
- `src/rtl/bscan/pad_table.json`, `src/rtl/bscan/nanosoc_eth_chiplet_bscan.sv`,
  `sys_desc/bscan/nanosoc_eth_chiplet_pads.bsdl` — generated.
- `verif/bscan/tb_bscan_gate.sv` — per-die (a template of its shape is promoted).

---

## 3. The knob contract

### 3.1 Recommendation: **keep it knob-free.** Add no `BSCAN` and no `BSCAN_SETUP_TCL`.

The evidence is unusually direct. `ASIC/eth-chiplet/build/bscan-probe/` is a complete
run — synthesis through GDS — produced with:

- `ASIC/eth-chiplet/config/design_config.tcl:237` → `set DFT 0`
- `ASIC/eth-chiplet/design.mk:222` → `DFT_SETUP_TCL ?=` (empty)
- **not one line changed in `ASIC/asic-toolkit/`**

`bscan-probe` is an ordinary `RUN_TAG`, nothing more. The boundary-scan register reached the
reticle through the two doors the toolkit already has:

1. **the flist** — `flist/nanosoc_eth_chiplet_asic.flist:108-111` lists the three primitives
   and the generated wrapper as four ordinary RTL files;
2. **the pad ring** — read as `TOP_HDL`, which instantiates the wrapper.

That is the whole integration. A knob would add a switch whose only job is to enable
something that is already enabled by being present in the design, and the toolkit has
measured that failure mode: `mk/flow.mk:1025-1048` rejects conditional fragment inclusion
because *"it makes a gate's existence depend on parse order"* and produces *"a SILENT
no-op — no error, no warning, no targets — which is this toolkit's own signature defect
class."* A `BSCAN=0` default would recreate exactly that: a project with the RTL in its
flist, the register in its netlist, and a toolkit switch quietly saying it has no boundary
scan.

**A second, sharper reason.** The failure this flow exists to catch is *the register being
deleted*. A knob that can be left at 0 is a knob that turns the catcher off, and the thing
being caught is silent by construction — `set_case_analysis 0 [get_ports SE]` makes the
register unreachable and unobservable, at which point Genus deleting all 76 cells is
**correct constant propagation**: no error, no warning, exit 0, green log, no boundary scan
in silicon. A gate for that must not have an off switch that looks like a default.

### 3.2 What promotion *should* add to the engine: one assertion, no knob

`flow/genus/1_synthesis.tcl` §13a already asks **"did the pad ring survive synthesis?"**,
for a defect that shipped three tapeout builds running (82 pad instances named, 82 present
before, 48 after, 34 supply pads silently deleted, green run summary). Boundary-scan
deletion is the *same question about a different structure, with the same silence*.

Add **§13b, immediately after §13a**, in the same shape: if the design declares a
boundary-scan wrapper module, assert it is still instantiated after `syn_opt`. Sourced from
`BSCAN_MODULE` — read from `design.mk` or the pad table, empty meaning "this design does not
have one", exactly as `BONDPADS_TCL` and `POWER_INTENT` already behave (`mk/flow.mk:253-258`).
**Empty is not a knob**: it is the toolkit's existing "this design does not have one"
idiom, and unlike a `BSCAN=0` it cannot be left at a default that suppresses a real feature,
because a design with no wrapper module has nothing to name.

This is also the answer to *"promote a contract as an executable check that can go red, not
as a paragraph in `docs/tapeout/`"*: the eth project's version of this assertion currently
lives at the bottom of `bscan_constraints.sdc` as a raw `error` in project SDC. That works
and should stay — but it is one project's copy of a general post-condition, and the next
consumer will not know to write it.

### 3.3 Should promotion resolve the dead `DFT` switch? **No — and yes, in that order.**

**No, it must not be coupled to it.** `DFT` is internal scan (`convert_to_scan`,
`connect_scan_chains`, `write_scandef`). Boundary scan shares no collateral, no
insertion point and no report with it. Folding one into the other would give consumers a
single switch that means two unrelated things, and would make the boundary-scan flow
inherit `DFT`'s untested `if {$DFT}` branches in `1_synthesis.tcl` and `3_cts.tcl:1323`.

**Yes, it should be closed in the same patch series, separately.** Per §0.1 the switch is
not broken — it refuses honestly — but leaving an unimplemented `DFT` beside a live,
working boundary-scan capability is precisely the naming trap that costs somebody a day.
Minimum viable close, in ascending cost:

1. **Correct the backlog entry.** `MIGRATION_NANOSOC_ETH.md:1621` describes a file that no
   longer exists. Restate it against the toolkit's actual behaviour, or it will keep
   generating work like this brief.
2. **Disambiguate in `asic-flow-check`.** `:384` says *"no scan insertion"*. Extend to
   *"no scan insertion (internal scan chains; boundary scan does not use this)"*. One line,
   reaches every consumer who runs `make check`.
3. **Do not delete the switch.** It has a working refusal, four real report targets and a
   CTS branch. Deleting it would remove the only scaffolding a consumer who *does* want
   internal scan would build on, to fix a problem that is a comment.

Promotion should carry (1) and (2). Implementing internal scan is out of scope and should
stay on the backlog, honestly labelled.

---

## 4. What a third consumer supplies

Two things, and the identity half is already solved: `pad_table.json`'s `design` block is
the contract, written once by the table generator and read by everything downstream.
Measured on eth:

```json
"design": {
  "block": "nanosoc_eth_chiplet_pads",
  "module": "nanosoc_eth_chiplet_bscan",
  "padring": "ASIC/tech_wrappers/tsmc65/nanosoc_eth_chiplet_pads.v",
  "io_file": "ASIC/genus-innovus/scripts/nanosoc_eth_chiplet_pads.io",
  "tap": { "en": "uPAD_SE_I", "tck": "uPAD_SWDCK_I", "tms": "uPAD_SWDIO_IO",
           "tdi": "uPAD_HOST_IO_0", "tdo": "uPAD_HOST_IO_1" },
  "idcode": "0x10001001",
  "boundary_length": 76,
  "signal_cells": ["PDDW04DGZ_G","PDDW16DGZ_G","PDUW08DGZ_G","PDUW16DGZ_G"]
}
```

`boundary_length` and `signal_cells` are **derived from the ring, never declared** — that
was the point of `7a83014`, because a literal `76`/`48` is how a dropped pad passes review.
A third consumer supplies the other eight fields, which is what the template below asks for.

### `templates/bscan.mk.in` — ready to drop in

```make
#-----------------------------------------------------------------------------
# asic/bscan.mk - IEEE 1149.1 boundary scan for @BLOCK@
#
# Scaffolded by asic-flow-init. `-include`d by design.mk, like lvs.mk and
# rom.mk: a design with no boundary scan DELETES THIS FILE and everything else
# still works.
#
# WHAT THIS BUYS YOU, and what it costs if you skip it. The boundary-scan
# register's only stimulus is the TAP, and the TAP's enable is one pad. Put a
# `set_case_analysis` on that pad -- which is the normal, correct thing to do to
# a strapped mode pin, and which your constraints may already do -- and the
# whole register becomes unreachable and unobservable. Synthesis then deletes
# every boundary cell, the TAP and the instruction register, and that is CORRECT
# constant propagation, not a tool defect. No error. No warning. Exit 0. A green
# log, a netlist, an SDC, an SDF, and no boundary scan in silicon.
#
# There is no ECO for that after the reticle is cut. Every gate below exists
# because no exit status anywhere in this flow can see it.
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
#
# EVERY DECLARATION BELOW IS COMMENTED OUT, and that is deliberate -- it is
# mk/rom.mk's convention, not mk/lvs.mk's. `make check` treats a live
# `<<FILL IN>>` marker as BLOCKING, so a scaffold carrying one is red from the
# moment it is created. LVS can afford that because every tapeout needs LVS.
# Boundary scan is genuinely optional, and a fresh scaffold must not be red for
# a feature the project has not yet decided it wants.
#
# The targets still exist unconfigured, and they REFUSE BY NAME rather than
# saying "No rule to make target" -- see mk/flow.mk's note on why the fragment
# include is unconditional. Uncomment what you need; delete this file if this
# die has no boundary scan.
#-----------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# 1. IDENTITY. Eight values, and they are the ONLY per-design configuration.
#    The tools are design-agnostic; this file is where your die is named.
# ---------------------------------------------------------------------------

# The pad-ring module -- the one that instantiates the IO cells. Normally the
# same as BLOCK. The register is spliced INTO this file, between the core and
# the pads, so it must be the padded top level and not the core.
BSCAN_BLOCK    ?= @BLOCK@

# The Innovus .io placement map. Read for RING ORDER only -- the boundary
# register must shift in physical order or a tester's vectors mean nothing.
# Both Innovus dialects are accepted: `(top` and `( top`, `offset=N` and
# `offset = N`. Two chiplets in this lab write it differently.
BSCAN_IO       ?= $(IO_FILE)

#   BSCAN_MODULE   ?= <the wrapper module the generator will EMIT and the pad
#                      ring will instantiate. It does not exist yet; you are
#                      naming it. Convention: <block minus _pads>_bscan>
#
#   BSCAN_PADRING  ?= <your hand-written pad-ring .v, repo-relative. THE SPLICER
#                      EDITS THIS FILE IN PLACE. It is idempotent and has a
#                      --check mode, but it is your source tree: commit first>
#
#   BSCAN_TABLE    ?= <where the generated pad table lands, e.g.
#                      src/rtl/bscan/pad_table.json. Everything downstream reads
#                      THIS, not the variables above -- the table is the
#                      contract and this file only seeds it>

# ---------------------------------------------------------------------------
# 2. THE FIVE TAP PADS, by PAD INSTANCE NAME as your ring spells them.
#
#    MUX THEM ONTO PADS THAT ARE ALREADY BONDED. Five new bonds for test access
#    is a package change; five reused ones are free. Look for pads that are
#    bonded and driving nothing -- on the reference design the enable was a pad
#    that was bonded, dangling, and reported as UNCONNECTED in the netlist.
#
#    THE ENABLE PAD MUST NOT BE CASE-ANALYSED ANYWHERE IN YOUR SDC. See the
#    header. If it currently is, that line and this file cannot both be right.
# ---------------------------------------------------------------------------
#   BSCAN_TAP_EN   ?= <pad instance driving the boundary-scan enable>
#   BSCAN_TAP_TCK  ?= <pad instance carrying TCK>
#   BSCAN_TAP_TMS  ?= <pad instance carrying TMS>
#   BSCAN_TAP_TDI  ?= <pad instance carrying TDI>
#   BSCAN_TAP_TDO  ?= <pad instance carrying TDO>

# ---------------------------------------------------------------------------
# 3. IDCODE. NO DEFAULT, DELIBERATELY.
#
#    32 bits: [31:28] version, [27:12] part, [11:1] JEP106 manufacturer,
#    [0] always 1.
#
#    LEAVE THE MANUFACTURER FIELD 0x000 UNLESS YOU HOLD A JEDEC ALLOCATION.
#    0x000 is the one code JEP106 can never issue, so a die carrying it
#    announces that it is unidentified. A plausible-looking made-up value does
#    not: the reference design shipped 0x2D0 for a while, which decodes to
#    JEP106 bank 6 code 0x50 -- an identifier belonging to a real company.
#    The generator REFUSES a non-zero manufacturer field unless the pad table
#    records a real allocation.
#
#   BSCAN_IDCODE   ?= <0xVVPPPPPM -- manufacturer 0x000 unless allocated>
#
#    There is NO default here on purpose. The reference design's own value is a
#    valid 32-bit number that would be silently inherited by any die that forgot
#    to set this, and two dice answering the same IDCODE on one chain is a
#    debug session nobody enjoys.

# ---------------------------------------------------------------------------
# 4. THE PRISTINE COMMIT -- the subtle one. Read this before you set it.
#
#    The table is parsed from your pad ring's PRE-SPLICE state. After splicing,
#    the pad cells no longer touch the core nets, so re-parsing the live ring
#    yields a table wired to the REGISTER ITSELF. That table still elaborates,
#    still lints, still counts the right number of cells -- and is wrong. The
#    next generator run then builds a wrapper wired to itself.
#
#    So `bscan-table` recovers the ring from a commit that predates the splice
#    and parses THAT, while recording the live repo path. The generator also
#    REFUSES outright to parse an already-spliced ring, so this is belt and
#    braces -- but the refusal is what you will hit first if this is wrong.
#
#    Before your first splice, any commit containing the ring will do (HEAD is
#    fine). After it, pin the last commit before the splice landed and LEAVE IT.
#
#   BSCAN_PRISTINE ?= <commit-ish whose pad ring predates the splice>

# ---------------------------------------------------------------------------
# 5. VERIFICATION -- optional, and each has an honest default.
# ---------------------------------------------------------------------------

# Simulator for the two benches. The benches print a summary line and $finish;
# they NEVER $fatal. simv exits 0 on failure BY DESIGN and the runner is the
# only adjudicator. Do not wire the testbenches into anything else without
# reimplementing all four conjuncts of its verdict.
BSCAN_SIM              ?= vcs

# Floors. A bench that ran and compared nothing exits the same way as one that
# passed, so both benches refuse below a floor. Raise them as your bench grows;
# never lower one to make a run green.
BSCAN_MIN_CHECKS       ?= 30000
BSCAN_GATE_MIN_CHECKS  ?= 4000

# The routed netlist the gate-level bench drives, and the collateral it needs
# to elaborate a whole chip. Empty means `make bscan-gate` refuses and says so,
# which is the honest answer -- it is not a skip and not a pass.
BSCAN_GATE_NETLIST     ?=
BSCAN_GATE_COLLATERAL  ?=

# ---------------------------------------------------------------------------
# 6. The engine. Nothing below this line is yours to edit.
# ---------------------------------------------------------------------------
include $(ASIC_FLOW_DIR)/mk/bscan.mk
```

Add one line to `templates/design.mk.in`, beside the existing two:

```make
-include $(ASIC_DIR)/bscan.mk
```

---

## 5. The stage-test scenario

**None of the 34 scenarios exercises DFT or boundary scan** — confirmed. Adding one is
straightforward *provided* §13b (§3.2) lands, because a scenario with no engine-side gate
to trip would test nothing.

**And there is a bonus, which is arguably the better reason to do this.** §13a — the
pad-ring survival gate, written for a defect that shipped three tapeout builds running —
**has no failing-direction scenario either.** The `syn.*` gate ids in `test/stage/run.sh`
are `contract.no-sdc`, `gate.clock-lost-in-sdc`, `gate.error-census`, `gate.no-clocks`,
`gate.no-netlist`, `gate.no-syn-sdc`, `sdc`. There is no `syn.gate.pad-deleted`.

The reason is in the stub. `test/stage/stubs/eda_stubs.tcl:874-878`:

```tcl
proc get_cells {args} {
    stub_record get_cells $args
    # Only used by the dont_touch pass, which asserts a non-empty match.
    return [list cell:pad0 cell:pad1]
}
```

It returns a non-empty list **for every pattern**, so `syn_missing_io_insts`
(`1_synthesis.tcl:609-625`, which probes `get_cells $nm` then
`get_cells -hierarchical -filter`) can never report anything missing. **The comment is
stale**: `get_cells` is no longer only used by the `dont_touch` pass, and its staleness is
what hides the hole. That is `STATUS.md` gap 18's shape exactly — *"an unused knob in a test
harness is a promise of coverage that does not exist"* — one level along.

So the work is: make `get_cells` pattern-aware against a scenario-declared absent set, add
**one** knob, and both gates become testable.

**Stub change** — extend the documented block at `eda_stubs.tcl:127`, and add to the second
`array set ::scn`:

```tcl
# --- structures synthesis can delete -----------------------------------------
# syn_missing  instance/cell name patterns get_cells must report as ABSENT, as a
#              Tcl list. The healthy value is {} and get_cells then behaves as
#              before. This is how a DELETED-BY-SYNTHESIS fault is expressed:
#              the name resolved before syn_generic and does not resolve after,
#              which is the exact signature of both section 13a (34 supply pads,
#              three tapeout builds) and section 13b (the boundary-scan
#              register). Nothing else in the harness could express it, because
#              get_cells returned a non-empty list for every pattern.
syn_missing          {}
```

```tcl
proc get_cells {args} {
    stub_record get_cells $args
    # The queried name is the last bare argument (`get_cells $nm`) or the body of
    # a -filter (`name =~ "$nm"`). Both forms are used by syn_missing_io_insts.
    set want [stub_get_cells_name $args]
    foreach pat $::scn(syn_missing) {
        if {[string match $pat $want]} { return {} }
    }
    return [list cell:pad0 cell:pad1]
}
```

**`test/stage/scenarios/bsr_optimised_away.tcl`** — new, in house style (a comment that
says what the fault IS and why it is invisible, then one `stub_scn`):

```tcl
# The boundary-scan register was DELETED BY SYNTHESIS, and everything reported
# success.
#
# The register's only stimulus is the TAP, and the TAP's enable is one strapped
# pad. `set_case_analysis 0` on that pad -- the normal, correct treatment of a
# static mode pin, which a project's own 20_exceptions.sdc may already carry --
# makes the entire register unreachable and unobservable. At that point deleting
# every boundary cell, the TAP and the instruction register is not a tool defect:
# it is CORRECT constant propagation. Genus prints nothing, exits 0, writes a
# netlist, an SDC and an SDF, and the die has no boundary scan.
#
# NO EXIT STATUS ANYWHERE IN THE FLOW CAN SEE THIS, which is why section 13b
# asserts the instance is still there after syn_opt rather than trusting the run.
#
# The same knob drives the pad-ring case (section 13a): a name that resolved
# before syn_generic and does not resolve afterwards. Two gates, one signature.
stub_scn syn_missing {u_*_bscan}
```

**`test/stage/run.sh`** — one line in the `--- synthesis ---` block (a scenario file that
`run.sh` never names is caught by `inventory.stage-scenarios.referenced`, so this is not
optional):

```sh
fail_case syn.gate.bsr-deleted syn bsr_optimised_away.tcl \
    "boundary-scan register was DELETED by synthesis"
```

**`test/MUTATION_COVERAGE`** — `stage-scenarios 34` → `35`, in the same commit. This is not
bookkeeping; see §6.1.

**The paired positive control.** `run.sh`'s section A already runs every stage on the
healthy project, and `test/stage/project/` declares no `BSCAN_MODULE`, so §13b takes the
"this design does not have one" branch and stays silent. Add the control the toolkit's own
doctrine requires — *"a gate proven only to fire is a gate that may fire on everything"* —
by declaring a wrapper module in the stage project and asserting §13b reports **intact** on
the pass path. Without it, the scenario proves the gate can go red and not that it can go
green.

**While the stub is open, add the sibling case** — `syn.gate.pad-deleted` with
`stub_scn syn_missing {uPAD_*}` — and take §13a's count from 0 to 1. It is three lines and
it closes a hole in a gate written for a defect that has already shipped.

---

## 6. Migration risk for existing toolkit consumers

The answer is **not** "nothing, it is purely additive". Four risks are real; three are
demonstrable rather than hypothetical, and one is a hard red.

### 6.1 HARD RED — the scenario count breaks every consumer's test suite

`test/MUTATION_COVERAGE` declares `stage-scenarios 34`.
`test/shell/t_mutation_inventory.sh:162-164` counts `test/stage/scenarios/*.tcl` and fails
**in both directions**, with this message on the additive side:

> *"scenario files under test/stage/scenarios: 35, declared 34. 1 proof(s) were ADDED and
> test/MUTATION_COVERAGE was not updated. That is not a defect — it is an unreviewed change
> to what this suite claims to prove. Read the new case, then bump the number."*

Adding the scenario without bumping the number **turns the toolkit's test suite red for
every consumer on the next pull.** Mitigation is one line in the same commit. It is called
out first because it is invisible from the diff of the scenario itself, and because the
toolkit is currently carrying a live instance of exactly this: `MUTATION_COVERAGE`'s own
header records that `tcl-mutation-cases` went 24→25 in commit `9528348` without the
declaration moving, *"so `inventory.tcl-cases` has been red ever since, on every branch that
carries that commit."* The declared value is now 26, so it has since been reconciled — but
the incident is the proof that this failure mode is not theoretical here.

The sibling assertion `inventory.stage-scenarios.referenced` requires every scenario file to
be named by `run.sh`; the `fail_case` line in §5 satisfies it.

### 6.2 REAL — `mk/bscan.mk` makes new target names exist for every consumer

`mk/flow.mk:1107` — `$(call asic_flow_optional,bscan)` — would define `bscan`, `bscan-check`,
`bscan-sim` and friends in **every** project that includes `mk/flow.mk`, whether or not it
has a pad ring. That is the deliberate design (`:1015-1048` explains why the include is
unconditional: a project with no table gets the fragment's own named refusal instead of
`No rule to make target`). Two consequences:

- **A project that already owns a target of that name loses it silently.** `mk/flow.mk`
  documents this as measured, not theoretical: *"Measured on a consuming project that owns
  `rom-vars` and `rom-compiler-stage`: including `mk/rom.mk` here made the toolkit's recipes
  win both, silently."* GNU make prints `overriding recipe for target X` and keeps the last
  one. The escape hatch exists — `ASIC_FLOW_SKIP_MK := bscan` — and `mk/bscan.mk` must
  document it at the top, as `rom.mk` does.
- **`mk/bscan.mk` must open with `ifndef BSCAN_MK_INCLUDED`.** `rom.mk` and `rom_bind.mk`
  have this guard; `gls.mk` and `gls_netlist.mk` do **not**, and the latter's header tells
  projects to include it directly. Do not add a fifth fragment to the unguarded half.

**For this project specifically, the collision is near-miss and worth naming.** The
`bscan-*` targets live in the **repo-root `Makefile`**, which does *not* include
`mk/flow.mk` — it forwards to `ASIC/eth-chiplet` via `asic-syn` and friends. So there is no
make-level override. But the eth tree would then have `make bscan-check` at the root and
`make -C ASIC/eth-chiplet bscan-check` under the toolkit, doing different things, with
**nothing anywhere warning** — an include guard cannot see across make invocations. Decide
which one wins and delete the other in the same series.

### 6.3 REAL BUT BOUNDED — `templates/bscan.mk.in` changes what new projects scaffold

`scripts/asic-flow-init:152` walks the **entire** `templates/` tree and installs every file
found. Adding `templates/bscan.mk.in` therefore changes the scaffold for every project
created after the change. Bounded, because:

- `install_one` **skips an existing destination** unless `--force` (`:135-141`), so
  re-running init on an existing project cannot clobber anything.
- `-include $(ASIC_DIR)/bscan.mk` is the same opt-out shape as `lvs.mk` and `rom.mk`: a
  project with no boundary scan deletes the file.

**The trap inside this one, which the first draft of §4 walked straight into.**
`scripts/asic-flow-check:161` is `MARKER = re.compile(r"<<\s*FILL\s+IN")`, and
`placeholders()` splits its hits into *blocking* and *deferred* by
`DEFERRED_DIRS = ("calibre",)` and `DEFERRED_FILES = ("run_lvs.sh", "run_drc.sh")` (`:158-159`).
A new `bscan.mk` is in neither, so **live `<<FILL IN>>` markers in it would make `make check`
fail on every freshly scaffolded project** — for a feature that project may not want.

The toolkit already has two conventions here and they differ, measured:

| template | `<<FILL IN>>` count | effect on a fresh `make check` |
|---|---:|---|
| `templates/design.mk.in` | 12 | blocking — correct, the flow cannot run without them |
| `templates/lvs.mk.in` | 4 | blocking — defensible, every tapeout needs LVS |
| `templates/rom.mk.in` | **0** | not blocking; the table is **commented out** with `<...>` placeholders |

`bscan.mk.in` must follow **`rom.mk.in`**, which is why the template in §4 is commented out
throughout. The targets still exist and still refuse by name when unconfigured, which is the
property that matters; what is given up is a red `make check`, which for an optional feature
was never the right signal.

Two tests must be checked against the new file rather than assumed:
`test/shell/t_scaffold.sh` (asserts no unsubstituted `@WORD@` survives — the §4 template uses
only `@BLOCK@`) and `test/shell/t_documented_commands.sh` (runs the README's commands
verbatim in a throwaway project, and `make check` on a fresh scaffold is one of them).

### 6.4 REAL BUT SMALL — everything else is genuinely inert, and here is why

| addition | why it cannot affect an existing consumer |
|---|---|
| `scripts/asic-flow-bscan-*` | new filenames, no collision with the 25 existing `asic-flow-*`; nothing invokes them unless `mk/bscan.mk` targets are called |
| `flow/verify/bscan/` | `flow/` files are sourced by name; nothing sources these |
| `ip/bscan/*.sv` | not on any flist unless a project lists them |
| `test/fixtures/bscan/`, `test/python/test_bscan_verdict.py` | `test/python/` is collected by pytest — additive, and `conftest.py`'s `mutant()` copies the toolkit with `ignore_patterns(".git","test","__pycache__")`, so the new fixtures do not bloat the ~2.1 MB / ~30 ms copy |
| `templates/constraints/30_bscan.sdc.in` | scaffolded into new projects only; sorts after `20_exceptions.sdc`, which is where a boundary-scan block belongs |
| §13b in `1_synthesis.tcl` | guarded on a declared wrapper module; empty ⇒ the branch is not entered. Same idiom as `BONDPADS_TCL`/`POWER_INTENT` |

**The one thing in §6.4 that deserves a second look** is §13b, because it is the only
change inside a stage script that every consumer runs. It is guarded, but a guard is a
claim: `test/stage/run.sh` section A must confirm the healthy path stays byte-identical for
a project that declares no wrapper. That is the positive control in §5, and it is the
reason it is not optional.

### 6.5 A housekeeping defect worth fixing on the way

`verif/bscan/build/` and `verif/bscan/build_gate/` are ignored by **different and
asymmetric** mechanisms:

- `build/` → the repo's `.gitignore:163` pattern `build/`
- `build_gate/` → **only** by a self-ignoring stamp, `printf '*\n' > "$BUILD/.gitignore"`,
  written by `run_gate.sh:164` **on every run** — and that `.gitignore` is itself untracked

The ignore is a side effect of running the script. Delete `:164`, or create `build_gate/`
any other way, and **222 MB appears in `git status`**. A shared toolkit must name the build
directories in a real `.gitignore` rather than relying on a script to plant its own cover.

---

## 7. Ordering

**Precondition, and it is not negotiable:** `ASIC/asic-toolkit` is currently `+`-prefixed
(pin drift) on `fix/tcl-parse-gate-both-directions` with four untracked paths in no commit
anywhere. A peer session owns tonight's GDS run and has asked that nothing be pinned or
pushed. **Nothing below starts until that is untangled.** The gate for "untangled" is the
toolkit's own:

```sh
PINS_EXPECT_MIN=<n> ASIC/asic-toolkit/ci/check-pins.sh
```

with `pins.pinned` and `pins.worktree` both green. Note `PINS_EXPECT_MIN` must be set — per
`PROMOTION_FROM_NANOSOC_ETH.md` §5, without it a tree that has lost its submodules passes
every gate by having nothing to check.

Then, in this order. Steps 1–3 are one PR each against the toolkit; nothing in this project
changes until step 7.

1. **Vendor scan first, in a fresh clone, before the test suite.** `ci/check-vendor-collateral.sh`
   by hand — the toolkit has **no git hooks installed on itself** (`core.hooksPath` is
   superproject-only), and the suite writes a deliberately vendor-shaped `tech/faketech/`
   that produces hundreds of false findings if scanned afterwards. The five Python tools
   carry TSMC pad-cell and `tcbn65lp` names (§2.2); this scan is the check that they are
   *shape* references and not transcribed collateral.

2. **Land the tools and the benches — no engine change, no make change.**
   `scripts/asic-flow-bscan-*`, `flow/verify/bscan/`, `test/fixtures/bscan/`,
   `test/python/test_bscan_verdict.py`, with the §2.2/§2.3 fixes applied (the `gen_bscan.py`
   path defaults, the splicer's anchor regex, `gen_tb_pads.py:303`, `tb_bscan.sv:488`,
   `run.sh:84`, the dead `if False:` block, the executable bits). **Purely additive by
   §6.4** — every existing consumer is unaffected, and this step is independently useful
   even if steps 4–6 stall.

3. **Land §13b and the stage scenario together, in one commit, with the count bump.**
   `1_synthesis.tcl` §13b + the `syn_missing` stub knob + `bsr_optimised_away.tcl` + the
   `fail_case` line + **`stage-scenarios 34 → 35`** + the pass-path positive control. These
   cannot be split: the scenario without the gate tests nothing, and the scenario without
   the count bump is §6.1. Add the `syn.gate.pad-deleted` sibling here too — the stub work
   is already done and §13a is currently untested.

4. **Land `mk/bscan.mk` and `templates/bscan.mk.in`.** Separate PR, because this is the
   only step that changes behaviour for existing consumers (§6.2, §6.3). Include the
   `ifndef BSCAN_MK_INCLUDED` guard and the `ASIC_FLOW_SKIP_MK` note.

5. **Run the toolkit's own suite, all layers, and read the greens.**
   `test/shell/run.sh`, `pytest test/python`, `test/stage/run.sh`,
   `ci/check-vacuous-gates.sh`. Specifically confirm `inventory.stage-scenarios` and
   `inventory.stage-scenarios.referenced` are green — they are the two this work can break.

6. **The `ip/bscan/` decision.** Everything above lands without it. Promoting the RTL needs
   the paragraph in §2.1 from the chip owner — not because of vendor collateral, but
   because it makes the toolkit an IP supplier. Until then the primitives stay in
   `src/rtl/bscan/` and the compute chiplet copies them, which is a known, stated fork
   rather than an accidental one.

7. **Only then, this project.** Re-point the repo-root `Makefile` at
   `asic-flow-bscan-*`, resolve the duplicate `bscan-check` (§6.2), slim
   `PROPOSED_STANZA.yaml`'s `check:` to invoking the promoted tool (§2.4), splice it into
   `ci/signoff.yaml`, then:

   ```sh
   scripts/ci/signoff.py lint
   scripts/ci/signoff.py prove boundary-scan
   scripts/ci/signoff.py run   boundary-scan
   ```

   `prove` is the step that matters — it runs the check against all eight fixtures in both
   directions and is the only thing that can tell a working gate from a fixture-shaped hole.

8. **Bump the submodule pin, push both, in that order.** Toolkit first — a pin that is not
   on a remote is not reachable, and this project has a standing record of pins that were
   never pushed.

**Do not promote step 7 before step 2.** A project-side edit that depends on a toolkit
change which has not landed is the pin-drift state this plan is waiting on, recreated
deliberately.

---

## 8. Open items, stated rather than buried

- **`ip/` needs an owner's decision** (§2.1). One paragraph unblocks it.
- **`scripts/check_chip_boundary.py` got *harder* to promote, and the toolkit does not know.**
  It is Tier-2 item 3a in `PROMOTION_FROM_NANOSOC_ETH.md` — *"a second consumer has asked
  for this by name"* — assessed there as needing *"five `HERE`-relative paths, two
  module-name regexes and `PARAMS`"* turned into arguments. It now has **three** module-name
  regexes: this work added `:183`, `re.search(r"nanosoc_eth_chiplet_bscan\s+(\w+)\s*\(...")`,
  to follow the boundary-register indirection. `make bscan-check` calls it. **The toolkit's
  assessment of that item is stale and should be corrected in the same series**, or whoever
  picks it up will size it from a number that was true on 2026-08-17.
- **`bscan_syn_verdict.py:116`** hardcodes the TAP shape as `+32+1+4+8+2`. Correct today;
  a silent false-FAIL on a good netlist the day `IR_WIDTH` becomes configurable. Derive it
  or assert `IR_WIDTH == 4`.
- **T0 and T6 are not mutation-proven** (§1). Either discriminate them or stop quoting 7/7
  without the qualifier.
- **The tech-pack split is half-done by design** (§2.2). Promote the tabular half; say out
  loud that the inline half is inline, so the next consumer sizes it correctly.
