# 13 — Logical equivalence checking

[← 11 Known issues](11-known-issues.md) · [index](00-index.md)

Conformal LEC on `nanosoc_eth_chiplet_pads`: what is compared against what, why that
pair and not another, how the verdict is made able to fail, and what is still not
verified.

Harness: `ASIC/genus-innovus/scripts/lec/`
(`README.md` there is the operating manual). Tool: `lec 22.10-s200` at
`/eda/cadence/confrml/bin/lec`.

> Every number on this page was measured from `outputs/` as written by the run that
> finished 2026-08-06 17:45. Where something has not been run, it says so.

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
what LEC consumes. There is no alternative anyway: the TSMC packages installed here are
Front_End-only and ship no standard-cell or IO Verilog at all.

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
(`/research/precompiled_mems/TSMC65/<macro>/<macro>.v`, `ASIC/romlibs/*/…_via.v`) but
they are `reg [31:0] mem [0:255]` models with x-handling and timing checks: compiling
them needs Conformal GXL memory support, and putting the same model on both sides could
only ever prove the model equals itself.

### Bond pads have no model anywhere

`PAD70GU` (42) and `PAD70NU` (40) are created by `scripts/place_bondpads.tcl` during
`4_pnr_route` and exist only in `…_pnr.v`. There is **no `.lib` and no Verilog** for them
anywhere in this PDK install — no `.lib` file exists under `$TSMC_65_HOME/iolib` at all.
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

Three things follow. **These are proposed, not applied — `ci/signoff.yaml` and
`scripts/ci/` are outside this change's file ownership.**

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
rot cheaply, but it needs `soclabs-pdk` (it reads `/tsmc65pdk` and takes a Conformal
licence), so it belongs in the physical phase immediately before `lec-pnr`.

---

## 7. What is still not verified

Ordered by how much it should worry you.

**1. The production comparison has never been run.** Everything above is a harness that
is proven to work on small netlists shaped like the real ones and proven to read the real
libraries. `run_lec.sh pnr` on the 53 MB netlist has *not* been executed — it is a
multi-hour licensed run. **A green self-test is not a green design.** Until `make lec-pnr`
has been run and passed, the correct statement about `outputs/…_pnr.v` remains "not
equivalence-checked".

**2. Runtime and memory are unmeasured.** A flat compare of 231,742 instances with 55,516
state points is a large job. If it aborts on resources, the levers are `LEC_THREADS`,
`LEC_DIAG=0`, and — if aborts appear — Conformal's hierarchical or ECO flows, none of
which have been tried here.

**3. `make lec-gate` has never been run either,** and its `LEC_PG_PIN=revised` mode
(Liberty read with PG pins for the revised side only, because `…_gate.v` has no PG
connections) is untested. The static evidence that `…_gate.v` ≡ `…_gate_power.v` is
strong — identical cell histograms, identical instance-name sets, same Genus DB, 10
seconds apart — but it is static evidence, not a proof.

**4. Memory array behaviour is out of scope,** by design and permanently on this site.
Connectivity is checked; contents are not. See §3.

**5. Bond pads are not checked by anything here** — no model exists. They are LVS scope,
and [`ci/signoff.yaml`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ci/signoff.yaml) already records that LVS cannot run on
this site.

**6. The `X`/undriven modelling is deliberately conservative and untested at scale.**
`set_undriven_signal 0` is *not* set — Genus sets it on the RTL side, but here both sides
are netlists and an undriven net that feeds logic in one and not the other is a real
finding, not something to flatten to 0. If the production run reports aborts, this is the
first thing to look at, and loosening it is a decision to be argued in writing, not a
quick fix.

**7. Equivalence is not timing.** LEC says the shipped netlist computes the same
function. It says nothing about whether the 10,555 hold-repair delay cells actually fixed
hold, or whether the design meets setup. That is STA, and
[`ci/signoff.yaml`](https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/blob/main/ci/signoff.yaml) lists `sta-signoff` as unsupported: no Tempus
or PrimeTime is installed.

---

[← 11 Known issues](11-known-issues.md) · [index](00-index.md)
