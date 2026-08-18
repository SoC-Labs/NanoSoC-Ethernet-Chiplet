# 13 — Logical equivalence checking

[← 11 Known issues](11-known-issues.md) · [index](00-index.md)

Conformal LEC on `nanosoc_eth_chiplet_pads`: what is compared against what, why that
pair and not another, how the verdict is made able to fail, and what is still not
verified.

Harness: `ASIC/genus-innovus/scripts/lec/`
(`README.md` there is the operating manual). Tool: `lec 22.10-s200` at
`$CDS_INSTALL/confrml/bin/lec`.

> Every number in §§1–5 was measured from `outputs/` as written by the run that
> finished 2026-08-06 17:45. Where something has not been run, it says so.
>
> **Amended 2026-08-17.** Two claims on this page were measured false and are corrected in
> place, each marked where it stands: §3's assertion that no standard-cell or IO Verilog
> exists on this site, and §7's assertion that the production comparison has never been
> run. Both LEC legs ran on 2026-08-08. §4's unreachable-point prediction, §6's "proposed,
> not applied", and §7 items 1–3 have been re-derived from the measurements rather than
> quietly restated — what changed is called out at each.
>
> ### ✅ AMENDED 2026-08-18 — THE JOINT IS NOW CLOSED. `lec-gate` PASSED.
>
> **This page's central negative finding has been resolved, and the resolution is the
> good kind.** Everything below about the 2026-08-08 legs remains accurate and should be
> read as history, not as current status.
>
> **1. `lec-gate` passed for the first time in this repository's history**, at
> **2026-08-17 23:38:35** — `build/full-20260814/reports/lec/gate/verdict.txt`.
> A whole-tree `find` for `verdict.txt` (including `genus-innovus/runs/*` and both
> `baseline_2026-08-0*` trees) turns up exactly **two** full-chip `gate` legs ever: the
> 08-08 `FAIL` and this one. Everything else is a `selftest_*` or a per-block `rtl_*` leg.
>
> **2. The chain now genuinely composes.** All three of tonight's legs cite the *same*
> middle file — `..._gate_power.v` `sha1=78bf7b97…` appears as the *revised* side of the
> `gate` leg and the *golden* side of both `pnr` and `audit-control`. So
> `gate.v ≡ gate_power.v ≡ pnr.v` holds over one consistent set of netlists. This is
> exactly the defect §7 describes: on 08-08 the two legs used **different**
> `gate_power.v` files (`431c06a5…`, 41,061,573 B, 08-07 17:43 for the `pnr` leg vs
> `664d76d7…`, 40,690,594 B, 08-08 17:14 for the `gate` leg), so they proved `A≡B` and
> `B'≡C` about two different middles and did not compose. **That is now fixed.**
>
> **3. What changed to make it pass was the harness, not the netlist.** The underlying
> exceptions are byte-identical to 08-08 — the same 4 revised-side PI points
> (`/VDD /VDDIO /VSS /VSSIO`) and the same `unreachable_golden=34 unreachable_revised=34`.
> The verdict schema gained two tolerances absent on 08-08:
> `extra_tolerated_pg_ports=R:PI:VDD,R:PI:VDDIO,R:PI:VSS,R:PI:VSSIO` and
> `unreachable_symmetric=34`. Read the pass as "the exceptions are now named and
> tolerated", not as "the exceptions went away".
>
> **4. Two honest caveats.** Compare-point counts differ between generations (61,375 /
> 61,534 on 08-08 vs **61,674** tonight), so this is a **different design revision** — it
> is not a re-verdict on the 08-08 netlists. And the **RTL→gate `lec-syn` leg was still
> running** when this was written, so the chain is closed only from `gate.v` downward.
> `syn_provenance` on all three legs records `ac1e1e9 (dirty=yes)`.
>
> **Do not read "Conformal printed PASS" as a pass anywhere on this page** — that is the
> precise error §7 exists to document. Both 08-08 legs printed `Compare Results: PASS`
> with `tool_exit_code=0` and both record `RESULT=FAIL`.

---

## 1. What was wrong

### `make lec` did not read the netlist we ship

Genus auto-writes `work/lec.dofile` during `syn_map`. Its two comparisons are:

```
read_design -verilog95 -golden  … fv/nanosoc_eth_chiplet_pads/fv_map.v.gz
read_design -verilog95 -revised … ../outputs/nanosoc_eth_chiplet_pads_gate.v
```

and then RTL against `fv_map`. **`outputs/nanosoc_eth_chiplet_pads_pnr.v` appears
nowhere in it.** That file is the one `write_stream` turns into GDS, and P&R put

| | `…_gate_power.v` | `…_pnr.v` | delta |
|---|---:|---:|---:|
| instances | 185,997 | 231,742 | **+45,745** |
| distinct cell types | 319 | 446 | +133 new, 6 gone |
| `DEL*` hold-repair delay cells | 0 | **10,555** | +10,555 |
| `CKBD0` clock buffers | 0 | 22,046 | +22,046 |
| `TIEH` / `TIEL` tie cells | 0 / 0 | 17 / 28 | +45 |
| bond pads (`PAD70GU`/`PAD70NU`) | 0 | 42 / 40 | +82 |

into it. Roughly one instance in five in the shipped netlist was created after the last
thing anybody checked, and 133 cell types in it appear in no netlist that was.

### The verdict could not fail

```make
lec:
	cd $(WORK_DIR)/; lec -xl -Dofile ./lec.dofile
```

The recipe has no status check, so whatever Conformal returns is discarded and `make`
reports success. The generated dofile is not blameless either — it defines

```tcl
proc is_pass {} { … regexp {Compare Results:\s+PASS} … }
```

uses it after the *first* of its two comparisons, and then ends `vpxmode` / `exit -f`
without consulting it again.

### And it disappears when you resume a flow

`work/lec.dofile` exists only after `make syn`, and `make clean` destroys it along with
`work/fv/`. The current `work/` — from a run resumed at `pnr_place` — has no
`lec.dofile` at all. A check that evaporates exactly when someone restarts mid-flow is
not a check.

---

## 2. What to compare against what

This is the only interesting design decision on the page, so here is the reasoning
rather than just the answer.

Four things could serve as the golden for the post-route netlist:

| Golden | What a pass proves | What a failure tells you |
|---|---|---|
| RTL | the whole chain, RTL → GDS netlist | *something* between RTL and GDS broke. Which tool? Unknown. |
| `fv_map` (Genus internal) | synthesis + P&R, via a Genus-private artefact | ditto, and it needs `work/fv/`, which `make clean` deletes |
| `…_gate.v` | P&R only | P&R broke it — but with 4 top-level ports and ~182k PG connections of noise |
| `…_gate_power.v` | **P&R only, cleanly** | **P&R broke it** |

### Why not RTL → post-route in one hop

It is tempting because it sounds like the strongest possible statement. It is actually
the *weakest useful* one, for three reasons.

**It re-verifies something already verified.** `make lec` (the existing target, once its
exit status is honoured) proves RTL ≡ `…_gate.v`. Folding that into a single RTL → P&R
run spends the expensive half of the compare re-doing work.

**It cannot localise.** A single non-equivalent point in an RTL → post-route run says
"synthesis or P&R broke this". Debugging then starts by *constructing* the intermediate
comparison you declined to run. Every hour of a multi-hour flat compare is spent
producing an answer you have to re-earn.

**It hides the interesting failure mode behind the boring one.** Genus is
mapping RTL onto gates: name changes, structural change, datapath rewriting, constant
propagation, unused-logic removal. Innovus is doing something far more constrained —
buffering, resizing, cloning clock nets, inserting delay cells — and it preserves
instance names while doing it. Mixed together, P&R's small, sharp, high-consequence
edits are debugged with the same machinery as synthesis's large, expected ones.

### The chain, and its tradeoff

```
   RTL  ──[ make lec ]──►  …_gate.v  ──[ make lec-gate ]──►  …_gate_power.v
                                                                   │
                                                       [ make lec-pnr ]
                                                                   ▼
                                                              …_pnr.v   ── write_stream ──► GDS
```

Each link isolates one transformation, so a failure names the tool that caused it. The
cost of a chain is that it is only as strong as its weakest link *and its joints*: a
chain proves `A ≡ B` and `B ≡ C`, which gives `A ≡ C` only if the `B` in both runs is
the same file. That is why `run_lec.sh` records size, mtime and **sha1** of both
netlists into `reports/lec/<tag>/inputs.txt` on every run — the joint is checkable
afterwards rather than assumed.

The other cost is wall-clock: two flat compares of a ~232k-instance, 55.5k-flop design
instead of one. Given that a flat compare is unavoidable anyway (see below), and given
that the second link is the *only* one anybody has ever run, that is the right trade.

### Why `…_gate_power.v` and not `…_gate.v`

Two netlists differing in ways that have nothing to do with logic will drown the finding
you care about.

| | `…_gate.v` | `…_gate_power.v` | `…_pnr.v` |
|---|---:|---:|---:|
| top-level ports | 23 | **27** | **27** |
| `.VDD`/`.VSS` connections | 6 | **159,692** | **182,399** |

`…_gate_power.v` and `…_pnr.v` have exactly the same boundary — the extra four ports
being `VDD`, `VDDIO`, `VSS`, `VSSIO` — and the same PG convention. Using `…_gate.v` would
make four top-level ports and every leaf supply connection into apparent findings.

It is also the same netlist as `…_gate.v`, written 10 seconds later from the same Genus
database with the power intent applied. Verified statically, not assumed:

- identical cell histograms — 319 cell types, identical counts, byte-identical listing;
- identical sequential instance-name sets — 55,516 names, 0 added, 0 removed.

`make lec-gate` turns "verified statically" into "verified by Conformal" and is the
reason that link is in the chain at all.

### The single most useful measurement on this page

The set of sequential instance names is **identical** between `…_gate.v` and `…_pnr.v`:
55,516 names, zero added, zero removed. So P&R cloned no registers, retimed nothing, and
removed no state — every one of the 45,745 added instances is combinational. Name-based
mapping (`set_mapping_method -sensitive`) therefore maps every state point 1:1, and the
comparison reduces to combinational cones. That is what makes a flat compare of this size
tractable at all.

### Flat, not hierarchical

Both netlists declare the same 29 modules, which normally invites a hierarchical
compare — far cheaper, and it localises failures for free. It is not available here.
CTS pushed cloned clock nets **through** module boundaries, so sub-module port lists
differ. `pnr.v`'s `eth_receivecontrol` carries `MTxClk_clone1`, `MRxClk_clone1`,
`MRxClk_clone2` and `n_1397` ports that `gate_power.v`'s does not.

The module boundaries are not comparable. The top-level boundary is. Hence flat, hence
hours.

---

## 3. Libraries

Ten Liberty files, the **same ten** `scripts/config.tcl` gives Genus and Innovus.
`run_lec.sh` greps `config.tcl` for `*.lib` basenames and refuses to run if the lists
have drifted — a memory-corner swap that reached synthesis but not LEC would otherwise
turn a macro into an accidental blackbox, which reads in the log exactly like a
legitimate one.

**Liberty, not Verilog.** `tcbn65lpwc.lib` carries a `function` attribute on every
combinational output and a full sequential description on every flop and latch — exactly
what LEC consumes. That is the right input for this tool; it is a choice, not a forced
move.

> **Corrected 2026-08-17.** This paragraph used to end *"There is no alternative anyway:
> the TSMC packages installed here are Front_End-only and ship no standard-cell or IO
> Verilog at all."* Both halves are false, and the error escaped this page — `Front_End`
> **is** the simulation package. The thing this site genuinely lacks is `Back_End`: GDS and
> the layout views, which is why §7 item 5 and the `gds-completeness` entry in
> `ci/signoff.yaml` are still correct.
>
> Measured with `ls`, 2026-08-17. **Locations below are given relative to the variables the
> flow already sets, never as absolute paths or release names** — this repository is public
> and the PDK is licensed to the site, so an inventory of what is installed here does not
> belong in it. `ls` your own installation.
>
> | model | where | size |
> |---|---|---|
> | standard cells | the standard-cell `_FE` package, `TSMCHOME/digital/Front_End/verilog/` | 3.7 MB, 844 modules |
> | standard cells, PG-pin variant | a `…_pwr.v` beside it, same directory | 3.9 MB |
> | IO drivers | the IO `_FE` package, same `Front_End/verilog/` position | 26 KB, 58 modules |
> | RAM macros | one directory per macro in the tree `$MEM_PATH` points into — all six carry a `<macro>.v` beside their `.lib` | 74–142 KB |
>
> Both `_FE` packages are the ones `scripts/config.tcl:85-86` already resolves under
> `$TSMC_65_HOME` to reach the NLDM. So the Verilog needs nothing installed, and no *package*
> skew is possible — it is the same package, not a parallel one.
>
> **A revision skew *inside* those packages is possible, and on this installation it exists.
> Check it before trusting a gate-level run.** Both packages have this shape:
>
> ```
> <package>/TSMCHOME/digital/Front_End/
>         timing_power_noise/NLDM/<A>/     <- the Liberty config.tcl reads
>         verilog/<B>/                     <- the simulation models
> ```
>
> `<A>` and `<B>` are release-revision directory names. **In both packages `<A>` carries the
> same revision as the enclosing package and `<B>` carries an older one** — so the Verilog is
> not the same release as the Liberty, for the standard cells and the IO alike. Two `ls`
> outputs are the whole test:
>
> ```sh
> # $p = the _FE package config.tcl:85 (IO) or :86 (standard cells) resolves to
> ls -d "$p"/TSMCHOME/digital/Front_End/timing_power_noise/NLDM/*/
> ls -d "$p"/TSMCHOME/digital/Front_End/verilog/*/
> ```
>
> Compare the two directory names; then `head` the `.v` file, whose own `Version:` header
> field agrees with `<B>` rather than `<A>`. A caveat, not a blocker — but a cell whose
> function or timing changed between those two releases would make a gate-level simulation
> disagree with STA for a reason that is not the design's.
>
> **The consequence is not on this page.** VCS `T-2022.06-SP2`, Xcelium `xrun` and
> Verilator 4.028 are all on `PATH` here, so **gate-level simulation of `…_pnr.v` against
> the 203 MB `_gate.sdf` is achievable on this site.** Several documents said or implied it
> was not; they are listed in §7's closing note.

### `-PG_PIN` — the setup detail that decides whether this works

The supplies in `tcbn65lpwc.lib` are `pg_pin()` groups, not `pin()` groups. Without
`read_library -liberty -PG_PIN`, Conformal creates no pins for them, and every
`.VDD(VDD)` in the netlist is a connection to a pin that does not exist. Measured:

```
// Error: HRC3.3: Undefined named port connection
//  Cannot find pin u_inv/VDD. No pin VDD is defined in module INVD1
```

`elaborate_design` aborts, `set_dofile_abort exit` fires, the process leaves with 6.

**This is why "just point `work/lec.dofile` at `pnr.v`" does not work.** That dofile
reads these same libraries without `-PG_PIN` and only survives because `…_gate.v`, the
netlist it was written for, has 6 PG connections in the whole file. Retargeting it would
have failed at elaboration — which, given the old recipe discarded the exit status, would
have looked like a pass.

### Memory macros are blackboxed — stated plainly

Twenty-one macro instances across eight types:

| macro | instances | | macro | instances |
|---|---:|---|---|---:|
| `flash_cache_data` | 8 | | `rom_via` | 1 |
| `rf_08k` | 4 | | `eth_rom_via` | 1 |
| `rf_16k` | 3 | | `rf_01k` | 1 |
| `flash_cache_tag` | 2 | | `rf_32k` | 1 |

All eight are `add_notranslate_modules -library -both`'d, exactly as Genus's own
generated dofile does. Liberty gives them pins and timing arcs but no logic function —
there is no way to express a 256×32 RAM in a `.lib`.

**What that verifies:** memory *connectivity*, completely. Every address, data,
write-enable, chip-enable and clock pin is a compare point; every `Q` output drives
compared logic. A swapped address bit, a dropped write enable or a rewired byte lane
fails the check.

**What it does not:** memory *behaviour*. The array is out of scope, and no reasonable
setup on this site would bring it in. Arm PIP behavioural models do exist
(`$MEM_BASE/<macro>/<macro>.v`, `ASIC/romlibs/*/…_via.v`) but
they are `reg [31:0] mem [0:255]` models with x-handling and timing checks: compiling
them needs Conformal GXL memory support, and putting the same model on both sides could
only ever prove the model equals itself.

### Bond pads have no model anywhere

`PAD70GU` (42) and `PAD70NU` (40) are created by `scripts/place_bondpads.tcl` during
`4_pnr_route` and exist only in `…_pnr.v`. There is **no `.lib` and no Verilog** for them
anywhere in this PDK install — but the reason is not the one this section used to give, and
the difference is worth six lines because it also says where the pads come from.

Run `grep -rl PAD70 "$TSMC_65_HOME"` (2026-08-17) and it returns **exactly one file**, a
**LEF**, in the `Back_End/lef/` subtree of the **bump/pad IO library's `_FE` package** — a
different library from the IO-driver one `config.tcl` reads. It defines `MACRO PAD70GU`,
`PAD70GU_SL`, `PAD70NU` and `PAD70NU_SL`.

So the pads have **a LEF abstract and nothing else**: that package ships only
`Back_End/{lef,milkyway,volcano}` and its documentation — no Liberty, no Verilog, no GDS.
That is the evidence for "physical-only", and it is now measured rather than inferred.

> Two superseded arguments, both wrong in the same way — each searched a tree the pads were
> never in. The original text said no `.lib` existed under `$TSMC_65_HOME/iolib` at all; that
> path is missing the `CMOS/LP/IO2.5V` segment, so it named nothing. The first correction to
> it (also 2026-08-17) fixed the path and found 126 `.lib` files with no `PAD70` among them —
> true, but irrelevant: bond pads come from the **bump/pad library**, not the IO-driver
> library `config.tcl` reads. The conclusion was right three times running; only the third
> argument supports it. If you are re-checking, grep the whole of `$TSMC_65_HOME` rather than
> the subtree you expect the answer to be in.
They are physical-only, written by Innovus with an empty connection list
(`PAD70GU BuPAD_HOST_IO_5 ();`), so they carry zero key points either way. Correct: bond
pads are LVS/DRC scope, not equivalence scope.

`scripts/lec/bondpad_stubs.v` declares them as empty modules rather than letting
`set_undefined_cell black_box` absorb them implicitly, so that `report_black_box` stays
readable — anything blackboxed that is not one of the eight macros is a missing library.
In the self-test run, `report_black_box` prints exactly one line.

### Nothing else needs a model

Every one of the 446 distinct cell types in `…_pnr.v` resolves to the standard-cell
Liberty, the IO Liberty, a macro Liberty, a design module, or the two bond pads.
`write_netlist` excluded physical-only cells: there are **no** `FILL*`, tap, `ANTENNA*`
or decap instances in the netlist. `TIEH` (17) and `TIEL` (28) are ordinary
`tcbn65lp` cells and are in `tcbn65lpwc.lib`.

---

## 4. Making the verdict real

Twice, from two independent sources, and they must agree with each other.

### In the dofile

`pnr_lec.do` does not trust any status word. After `compare` it reads the final state
back out of the tool and decides for itself:

```tcl
get_compare_points  -NONequivalent|-ABort|-NOtcompared|-EQuivalent -COunt
get_unmap_points    -EXTRA|-UNReachable|-NOTmapped  -GOLden|-REvised -COunt
get_exit_code
```

then prints a `LEC-VERDICT:` block and calls `exit 0` or `exit 1`.

Three behaviours were measured on `lec 22.10-s200` before relying on any of this:

| probe | result |
|---|---|
| `exit 7` from `tclmode` | process returns **7** — the status is ours to set |
| `exit -f` from `tclmode` | **`expected integer but got "-f"`**, dofile aborts. It works in Genus's dofile only because `vpxmode` precedes it — there it is the native `EXIT -Force`, not Tcl's `exit`. |
| `read_design` of a missing file with `set_dofile_abort exit` | dofile aborts, process returns **6** (bits 1\|2) |

So `set_dofile_abort exit` is on: a setup failure cannot reach the compare and report
nothing. Conformal's status bits are decoded and reported too (bit 0 internal error,
2 command error, 3 unmapped/extra PO, 4 non-equivalent, 5/6 abort).

### In the runner

`run_lec.sh` re-derives the verdict from the transcript. All of these must hold:

- transcript exists and is ≥ `LEC_MIN_LOG_LINES` (default 50) lines — a truncated log
  means the tool never got far enough to have verified anything;
- no line **starts with** `LEC-PREFLIGHT-FAIL`;
- no `is aborted at line` / `Error exit from dofile`;
- `LEC-VERDICT: RESULT=PASS` present;
- Conformal's own `Compare Results:` line says `PASS`;
- `lec` exited 0, and that does not contradict the `LEC-VERDICT` line;
- golden and revised unreachable key-point lists are **identical by name**.

> Two traps worth naming, both of which this project has already been bitten by.
> **Anchor the greps.** Conformal echoes every command into the transcript, so an
> unanchored search for `LEC-PREFLIGHT-FAIL` also matches the dofile's own
> `puts "LEC-PREFLIGHT-FAIL: …"` *source line* and fails every run — observed, and fixed
> by requiring the marker at start-of-line.
> **Do not grep for bare `Equivalent`.** It is a row *label* in the compare-summary
> table and is printed pass or fail. `ci/signoff.yaml` already carries this scar.

### Unreachable points: the rule, and why it is not "fail on any"

Reading the memory Liberty with `-PG_PIN` gives each blackboxed macro a `VDD` and a `VSS`
pin. A blackbox pin is bidirectional, so Conformal creates a tri-state key point for
each; a supply net drives nothing with a logic function, so both are *unreachable*. Two
per macro instance, on both sides, by construction — expect **42 per side** on the real
design.

"Unreachable" in Conformal means every path from the point to every output is blocked, so
the point provably cannot influence any compared output. A blanket fail is therefore not
the strict choice, it is the wrong one, and it would fire on every run for a reason that
has nothing to do with P&R. The rule that carries information:

| condition | verdict |
|---|---|
| any unreachable point that is **not** tri-state | **FAIL** — real logic became unreachable |
| tri-state unreachable counts **differ** between sides | **FAIL** — structural divergence |
| tri-state unreachable, same count, **same names** | reported, accepted |
| tri-state unreachable, same count, **different names** | **FAIL** — caught by the runner's name diff |

`LEC_STRICT_UNREACHABLE=1` restores a blanket fail for a reviewer who wants it.

> **The "42 per side" prediction was wrong, and both production legs hit the first row of
> that table.** Measured 2026-08-08, identically on both: `unreachable_tristate=0` and
> `unreachable_other=34` per side. The blackboxed macros contributed no unreachable key
> points at all. The 34 are **supply pads** — 6 `uPAD_VDD_*`, 12 `uPAD_VDDIO_*`,
> 4 `uPAD_VSS_*`, 12 `uPAD_VSSIO_*` — blackbox instances rather than tri-state pins, so
> the rule above classifies them as "real logic became unreachable" and fails. Their golden
> and revised name sets are identical: 34 each, diffed to empty (re-verified 2026-08-17
> from `lec_pnr_unreachable_{golden,revised}.rpt`). The reasoning behind the rule is sound;
> the population it was calibrated against was the wrong one. §7 item 1 records the repair.

### The harness is mutation-tested

`scripts/lec/run_lec.sh selftest` runs four small netlists shaped like the real ones —
PG ports on the module, PG pins on the leaves, a blackboxed macro, a blackboxed bond pad,
P&R-style buffer and delay-cell insertion — each declaring the answer it must produce.

| case | mutation | required | measured |
|---|---|---|---|
| `equivalent` | none (CTS buffer + 2 delay cells + pads) | pass | **pass** — 37 compare points, 37 equivalent |
| `nonequivalent` | one `ND2D1` → `NR2D1` | fail | **fail** — 1 non-equivalent, `FAIL:NONEQ`, exit 1 |
| `extra_state` | one extra flop + extra output | fail | **fail** — 2 extra unmapped, `FAIL:INCOMPLETE`, exit 1 |
| `missing_input` | revised netlist absent | fail | **fail** — preflight, no licence spent |

Ran in ~15 s, 4/4 as declared. Run it on any new host before believing a production
result: it exercises the same libraries, the same licence and the same invocation.

---

## 5. Wiring it into `make`

Add to `ASIC/genus-innovus/Makefile`:

```make
## Logical equivalence, post-P&R. Compares outputs/$(BLOCK)_gate_power.v (the
## synthesis netlist) against outputs/$(BLOCK)_pnr.v (the netlist that becomes
## GDS) — the ~45,700 instances CTS, optimisation and hold repair added, which
## `lec` (Genus's generated dofile) never reads. Hours, and takes a licence.
## Exits non-zero on abort, non-equivalence, unmapped points, or a short log.
lec-pnr:
	$(DESIGN_DIR)/scripts/lec/run_lec.sh pnr

## The other link in the chain: outputs/$(BLOCK)_gate.v vs _gate_power.v, i.e.
## the netlist `lec` proved against RTL vs the power-decorated one lec-pnr uses
## as its golden. Statically they are the same netlist; this verifies it.
lec-gate:
	$(DESIGN_DIR)/scripts/lec/run_lec.sh gate

## Mutation-tests the LEC harness itself in ~15 s: proves it passes an
## equivalent pair AND fails a one-gate mutation, an extra flop, and a missing
## netlist. Run this before trusting any lec-pnr result on a new host.
lec-selftest:
	$(DESIGN_DIR)/scripts/lec/run_lec.sh selftest

.PHONY: lec-pnr lec-gate lec-selftest
```

Nothing in `scripts/lec/` depends on `work/`, so these targets work on a tree where only
`outputs/` survives — including this one, where `work/` was resumed at `pnr_place` and
has no `lec.dofile`.

---

## 6. Reconciling with CI

`ci/signoff.yaml` already has a `lec` stage, and it is honest about its own scope:

```yaml
    # NOTE this compares RTL -> SYNTHESISED netlist (via Genus's fv_map). It
    # does NOT read outputs/*_pnr.v — there is no post-P&R LEC anywhere in the
    # repo, despite package_submission.sh's MANIFEST claiming otherwise.
```

and it declares the gap in `unsupported:`:

```yaml
  - id: post-pnr-lec
    reason: "The lec stage compares RTL to the SYNTHESISED netlist only. Nothing
             compares RTL (or the synth netlist) to outputs/*_pnr.v"
```

Three things follow.

> **Status corrected 2026-08-17. All three were applied; this section was written when they
> were proposals and never updated.** `ci/signoff.yaml` and `scripts/ci/` remain outside
> this page's file ownership, so what follows is now a *reading* of them, not a request.
> Verified by inspection today:
>
> | | state |
> |---|---|
> | (a) `lec-pnr` stage | **applied**, in the physical phase, with a `lec-selftest` stage placed before it exactly as §6 recommended below |
> | (b) `post-pnr-lec` in `unsupported:` | **removed** — no such id remains in the file |
> | (c) `package_submission.sh` MANIFEST item 6 | **rewritten**, and now names both stages and both scopes |
>
> **What was not applied is the `check:` block in (a) — and that is the right outcome.**
> The shipped stage carries no `check:` at all and leans on `run_lec.sh`'s exit status. Had
> the block below been adopted verbatim it would have failed every good run: it greps
> `verdict.txt` for `^LEC-VERDICT: RESULT=PASS`, and on an accepted-exception pass that
> line still reads `RESULT=FAIL` because the repair of 2026-08-09 lives in the runner, not
> the dofile. The runner's own `LEC-RUNNER: RESULT=PASS` is the line that carries the
> verdict. See §7 item 1. The block is left below as written so the trap is on the record.
>
> **One stale comment remains in `ci/signoff.yaml`, on the `lec` stage** — the NOTE quoted
> just above still says "there is no post-P&R LEC anywhere in the repo, despite
> package_submission.sh's MANIFEST claiming otherwise". Both clauses are now false, and the
> stage that refutes the first sits about sixty lines below it in the same file. Flagged
> here rather than fixed, per this page's file ownership.

**(a) Add a `lec-pnr` stage** after `lec` in the physical phase:

```yaml
  - id: lec-pnr
    phase: physical
    gate: block
    label: soclabs-pdk
    needs_implementation: true
    description: "Conformal LEC — SYNTHESIS netlist vs POST-P&R netlist (the one that becomes GDS)"
    # Reads outputs/ only; needs no work/ and no lec.dofile, so it survives a
    # resumed flow and `make clean`.
    run: make -C ASIC/genus-innovus lec-pnr
    # run_lec.sh already exits non-zero on abort / non-equivalence / unmapped
    # points / short log, and asserts its own verdict against Conformal's. This
    # check is the third, independent reader of the same evidence.
    check: |
      V=ASIC/genus-innovus/reports/lec/pnr/verdict.txt
      L=ASIC/genus-innovus/logs/lec_pnr.log
      test -s "$V" || { echo "no LEC verdict at $V"; exit 1; }
      test -s "$L" || { echo "no LEC transcript at $L"; exit 1; }
      grep -q '^LEC-VERDICT: RESULT=PASS' "$V" || {
        echo "post-P&R LEC did not pass:"; grep -E 'reason=|RESULT=' "$V"; exit 1; }
      grep -qE 'Compare Results:[[:space:]]+PASS' "$L" || {
        echo "Conformal's own verdict is not PASS"; grep -nE 'Compare Results:' "$L"; exit 1; }
    artifacts:
      - ASIC/genus-innovus/logs/lec_pnr.log
      - ASIC/genus-innovus/reports/lec/pnr/**
```

**(b) Delete the `post-pnr-lec` entry from `unsupported:`.** Leaving it there once the
stage exists makes the report understate itself, which is the mirror image of the problem
this whole page is about.

**(c) Fix `scripts/ci/package_submission.sh`.** Item 6 of the MANIFEST currently reads:

> `6. LOGICAL EQUIVALENCE (RTL vs post-P&R netlist) — confirm make lec has been run and passed for THIS netlist.`

`make lec` is RTL vs *synthesis* netlist. As written the manifest tells a fab broker the
shipped netlist has been equivalence-checked when it has not. It should name both stages
and both scopes.

Also worth adding while nearby: `make lec-selftest` in the RTL phase would catch harness
rot cheaply, but it needs `soclabs-pdk` (it reads `$TSMC_65_HOME` and takes a Conformal
licence), so it belongs in the physical phase immediately before `lec-pnr`.

---

## 7. What is still not verified

Ordered by how much it should worry you.

**1. The production comparison ran on 2026-08-08. It is stale, not absent.**

> *Corrected 2026-08-17. This item read "The production comparison has never been run",
> and item 3 read "`make lec-gate` has never been run either". Both were false when
> written, and both had been copied into other documents — see the closing note.*

Both legs completed, and both are logically clean:

| leg | golden → revised | compare points | equivalent | non-eq | abort | not-compared |
|---|---|---:|---:|---:|---:|---:|
| `pnr` | `…_gate_power.v` → `…_pnr.v` | 61,375 | 61,375 | 0 | 0 | 0 |
| `gate` | `…_gate.v` → `…_gate_power.v` | 61,534 | 61,534 | 0 | 0 | 0 |

Conformal's own line for the `pnr` leg is `6. Compare Results:   PASS`
(`ASIC/genus-innovus/lec_shadow/logs/lec_pnr.log:423`). Evidence: `lec_shadow/reports/lec/pnr/`
and `lec_gate_shadow/reports/lec/gate/`. The `gate` leg exercised `LEC_PG_PIN=revised` as
designed, so §2's static argument that `…_gate.v` ≡ `…_gate_power.v` is now confirmed by
Conformal rather than merely strong.

**Both archived `verdict.txt` files nonetheless say `RESULT=FAIL`, and neither says
anything about the design.** The unreachable rule expected tri-state points and got 34
non-tri-state ones per side — the supply pads, golden and revised name sets identical
(§4). The `gate` leg additionally failed on 4 extra revised primary inputs,
`VDD`/`VDDIO`/`VSS`/`VSSIO`, which *are* precisely the difference between those two
netlists (§2). Both were repaired in `run_lec.sh` on 2026-08-09 (`b6b2196`) as an
**accepted-exception pass**: the runner enumerates every `LEC-VERDICT: reason=` line and
overrides the FAIL only if it can re-verify each one benign from the reports — unreachable
lists identical by name, or, on the `gate` tag only, the extra revised PIs being exactly
those four supply ports. One unrecognised reason and the FAIL stands.

Two consequences, neither comfortable.

**The dofile was not changed, so `verdict.txt` still carries `LEC-VERDICT: RESULT=FAIL`
even on an accepted-exception pass.** The verdict is the `LEC-RUNNER: RESULT=PASS` line the
runner appends. Anything grepping `verdict.txt` for `^LEC-VERDICT: RESULT=PASS` fails a
good run — see the note in §6.

**Neither leg has been re-run since the repair,** so the two archived verdicts are stale
rather than wrong about the design. Nothing here has been re-measured under the fixed
rules.

**And the run does not cover the netlist we would ship.** Measured 2026-08-17:

| `_pnr.v` | sha1 | bytes | written |
|---|---|---:|---|
| the one the `pnr` leg compared | `45a6c089…` | 43,785,964 | 2026-08-08 12:12 |
| the one in `runs/latest/outputs/` | `7a8d6cdb…` | 41,953,539 | 2026-08-10 10:20 |

`ASIC/genus-innovus/outputs/` holds no netlists at all today; the run archiver moved them
under `runs/`. **So this item's original conclusion survives, for a different reason: the
correct statement about the `_pnr.v` we would ship is still "not equivalence-checked"** —
because the check has not been repeated on it, not because the check does not exist. That
distinction decides what to do next, which is why it is worth the paragraph.
`docs/tapeout/26-plan-to-submittable-gds.md:331` already records the same pairing gap.

**The chain's joint also fails, and §2 is why we can tell.** `run_lec.sh` records a sha1 of
both inputs on every run so the joint is checkable rather than assumed. Checked, it does
not hold: the `pnr` leg's golden `…_gate_power.v` is `431c06a5…` (41,061,573 bytes,
2026-08-07 17:43); the `gate` leg's revised `…_gate_power.v` is `664d76d7…` (40,690,594
bytes, 2026-08-08 17:14). Different files. `A ≡ B` and `B ≡ C` were each proved, of two
different `B`s, so they do not compose into `A ≡ C`. Re-running both legs against one
`outputs/` fixes this; nothing else does.

**2. Runtime and memory are measured, and the job is small.** The `pnr` leg cost
**412.54 s CPU, 405 s elapsed, 874.07 MB** (`lec_pnr.log`, immediately after the compare
summary). This item used to warn of a multi-hour, resource-marginal run; that is not what a
flat compare of 231,742 instances and 55,516 state points costs here, and §2's
name-identical state-point mapping is why. `LEC_THREADS`, `LEC_DIAG=0` and Conformal's
hierarchical or ECO flows remain untried, and on this evidence are not needed. Worth
knowing when scheduling: the `lec-pnr` stage in `ci/signoff.yaml` budgets
`timeout_s: 21600`, over fifty times the measured cost.

**3. The RTL → synthesis leg has still never completed.** With items 1 and 2 corrected this
is the weakest link in §2's chain, and nothing above covers it. The single attempt is
`ASIC/genus-innovus/runs/20260808T185931Z_stage1a-syn-place-cts/logs/eval/lec.log`. It read
the libraries, read and elaborated the golden `fv_map`, and then died:

```
// Error: Cannot open file '…/ASIC/genus-innovus/outputs/nanosoc_eth_chiplet_pads_gate.v'.
// Error: FIL1.2: Failed to open file
//  Design file not found
// 'dofile …/lec_rtl_shadow/work/./lec.dofile' is aborted at line 104
```

Genus's generated dofile hardcodes an absolute path into `outputs/`, and the run archiver
had relocated the netlist. A path failure, not an equivalence failure — but the consequence
is that **nothing has ever proved RTL ≡ `…_gate.v` for this design.** `lec_rtl_shadow/` has
an `outputs/` and a `work/` and no log or verdict of any kind. So "synthesis did not lose
logic" remains unevidenced here, and that is exactly the `GLO-34` class
`scripts/ci/package_submission.sh` warns a fab broker about. Do not let the corrections
above be read as closing it.

**4. Memory array behaviour is out of scope,** by design and permanently on this site.
Connectivity is checked; contents are not. See §3.

**5. Bond pads are not checked by anything here** — no model exists. They are LVS scope,
and [`ci/signoff.yaml`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ci/signoff.yaml) already records that LVS cannot run on
this site.

**6. The `X`/undriven modelling is deliberately conservative, and has now survived a
production run.** `set_undriven_signal 0` is *not* set — Genus sets it on the RTL side, but
here both sides are netlists and an undriven net that feeds logic in one and not the other
is a real finding, not something to flatten to 0. Both legs on 2026-08-08 reported **0
abort points** under that setting, so the conservatism costs nothing at this scale. If
aborts ever do appear this is still the first thing to look at, and loosening it remains a
decision to be argued in writing, not a quick fix.

**7. Equivalence is not timing.** LEC says the shipped netlist computes the same
function. It says nothing about whether the 10,555 hold-repair delay cells actually fixed
hold, or whether the design meets setup. That is STA, and
[`ci/signoff.yaml`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ci/signoff.yaml) lists `sta-signoff` as unsupported: ~~no Tempus
or PrimeTime is installed.~~

> **⚠ CORRECTED 2026-08-18.** The `ci/signoff.yaml` string quoted above is **false**, and
> restating it here without a flag propagated it. Measured today: **Tempus** is installed
> (`SSV_21.11.000`, `Tempus_Timing_Signoff_XL/_MP/_TSO` — 41 issued, **0 in use**) and
> **PrimeTime** is installed (`2022.12` — 204 issued, **0 in use**). Tempus 21.11 is
> version-matched to the `INNOVUS_21.11.000` that built this database.
>
> **The point being made here still stands**: LEC proves function, not timing, and signoff
> STA has not been run. But the reason is that it is **not wired**, not that the tools are
> missing. See `40-signoff-sta-plan.md`. The upstream `signoff.yaml` string is still
> uncorrected and will keep re-seeding this — flagged to its owner.

---

### Where these two errors had spread

Both corrected claims had been copied outward before anyone re-measured them, which is the
reason for correcting them loudly rather than editing them away. Swept and corrected
2026-08-17:

| document | what it said |
|---|---|
| `docs/tapeout/09-signoff-checklist.md` §6 | headed "DOES NOT EXIST"; also a pre-send checkbox asserting it |
| `docs/tapeout/10-tapeout-submission.md` §2, §5 item 6 | "There is no post-P&R LEC in this repository" |
| `docs/tapeout/11-known-issues.md` issue (i) | "No post-P&R logical equivalence exists", severity **high** |
| `docs/tapeout/24-d2d-link-physical-handover.md` §6 items 2–3 | "No post-P&R LEC"; and GLS listed as a gap with no note that it is reachable |
| `docs/tapeout/25-what-remains-explained.md` §5, §6(a) | "No post-P&R LEC" |
| `docs/tapeout/07-reading-reports.md` | logical equivalence listed among "checks this flow does not run at all" |
| `ASIC/genus-innovus/scripts/lec/README.md` | "the TSMC packages on this site are Front_End-only" |
| `ASIC/genus-innovus/scripts/lec/run_lec.sh` (comment) | same, as the justification for reading Liberty |

Two restatements were **left standing**, both outside this page's file ownership and both
flagged rather than edited:

- `ci/signoff.yaml`, the NOTE on the `lec` stage — "there is no post-P&R LEC anywhere in
  the repo, despite package_submission.sh's MANIFEST claiming otherwise". Both clauses are
  false; the `lec-pnr` stage that refutes the first is in the same file.
- `docs/tapeout/26-plan-to-submittable-gds.md` needed no correction — it was written after
  the runs and already records both the clean compare and the netlist-pairing gap.

---

[← 11 Known issues](11-known-issues.md) · [index](00-index.md)
