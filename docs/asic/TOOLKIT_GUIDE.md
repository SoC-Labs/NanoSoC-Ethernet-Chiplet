# Running this project from a fresh clone

A from-nothing guide to how this repository is driven: what the ASIC toolkit is,
which makefile owns which decision, and the order to run things in. It assumes you
have never run any of it. Every command below was checked against the tree on
2026-08-20.

> **Freshness, 2026-09-09.** The LVS section and trap 10 were re-checked against the
> tree today and carry what changed since: LVS now runs, `make lvs` works, and the PG
> knobs are set in `design.mk`. **The rest of this page has not been re-verified since
> 2026-08-20** — stage timings, run tags and the pipeline ladder in particular predate
> three weeks of work. Treat an unverified line as a starting point and confirm it with
> `make -C ASIC/eth-chiplet help` / `status` / `env`, which report the tree as it is.

Read [`docs/tapeout/00-index.md`](../tapeout/00-index.md) after this for the
tool-level detail — floorplan, power plan, how to read a report. This page is the
map; that one is the terrain.

---

## The mental model, in one paragraph

The chip is `nanosoc_eth_chiplet_pads` — a pad ring wrapped around
`nanosoc_eth_chiplet`, which is itself a thin wrapper wiring three submodules
together. The **ASIC toolkit** (`ASIC/asic-toolkit`, a git submodule) is a
*generic* Genus → Innovus → Calibre engine that knows nothing about this chip. It
learns about this chip from exactly one file: `ASIC/eth-chiplet/design.mk`. The
top-level `Makefile` is a set of gates plus pass-throughs into that flow. Nothing
else drives the tools.

```
you type            make asic-syn                 (repo root)
                        │
root Makefile           └─ make -C ASIC/eth-chiplet syn
                              │
ASIC/eth-chiplet/Makefile     ├─ include design.mk        ← THIS design
                              │     └─ include ../common.mk  ← paths, PDK, env
                              └─ include $(ASIC_FLOW_DIR)/mk/flow.mk  ← the engine
                                    │
toolkit engine                      └─ genus -f flow/genus/1_synthesis.tcl
```

### Who owns what

| File / dir | Owns | You edit it when |
|---|---|---|
| `Makefile` (root) | RTL gates, generated flists, pass-throughs into both ASIC flows | you add a repo-level gate |
| `ASIC/eth-chiplet/design.mk` | **this design's contract** with the toolkit: block name, flist, floorplan, MMMC, stage prerequisites, ratchets, project-only stages (DRC/LVS/LEC/ROM) | you change what the chip *is* |
| `ASIC/common.mk` | environment shared by both ASIC flows — repo roots, IP paths, PDK resolution, clock period | you add a project constant or a site path |
| `ASIC/asic-toolkit/` | the engine: stage Tcl, checks, reports, make targets, tech packs | **never** — it is a shared lab submodule |
| `ASIC/genus-innovus/` | the *frozen legacy flow* — but also still the live home of the floorplan, power plan, MMMC, `.io` file, LVS setup and the padring GDS check | you change the floorplan or power plan |
| `ASIC/eth-chiplet/hooks/` | project Tcl spliced into named points of a toolkit stage | you need one extra command at a seam |
| `ASIC/eth-chiplet/overrides/` | a toolkit step file replaced **wholesale** | last resort — see Traps |
| `ci-pipeline.conf` | the full check ladder, in dependency order | you add a check to the ladder |
| `ci/signoff.yaml` | what "signed off" means for this design, with fixtures | you change a signoff gate |

The point of `design.mk` pointing at `ASIC/genus-innovus/scripts/*` rather than
copying those files is that a copy drifts silently and a pointer cannot. That is
why the "legacy" directory cannot simply be deleted.

---

## Day one: from `git clone` to a green gate

```sh
git clone https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet.git
cd NanoSoC-Ethernet-Chiplet

make bootstrap          # 42 submodules, 8 levels deep. NOT git clone --recursive
source set_env.sh       # source it, do not execute it
make hooks              # install the vendor-collateral pre-commit/pre-push guards
make check              # vendor-check + chip-boundary + lint. No licence needed.
```

Four notes, each of which costs an hour if you learn it the hard way:

- **`make bootstrap`, not `git clone --recursive`.** One submodule nested inside
  TideLink is declared over SSH at the commit we pin; a plain recursive clone dies
  there. `bootstrap.sh` rewrites that URL to HTTPS for the duration of the fetch,
  writes nothing to your git config, and then *verifies* nothing was skipped —
  `git submodule update` exits 0 having silently skipped a submodule.
- **`source set_env.sh`.** It exports only the component roots (`TIDELINK_HOME`,
  `TIDECHART_HOME`, `NANOSOC_MULTICORE_HOME`, …) that the flists dereference. It
  deliberately does *not* source the submodules' own env scripts. The ASIC flows do
  not need it at all — `ASIC/common.mk` defines the same roots with `?=`, so a
  sourced `set_env.sh` wins and an unsourced shell still works.
- **`make hooks` can legitimately fail** if the toolkit pin predates the installer.
  If it does, run `make vendor-check` by hand before any commit that adds a file.
- **`make check` is the floor.** If it is red, nothing downstream means anything.

Bare `make` prints help and starts nothing. `make help` is the grouped target list.

---

## The ladder, in the order you should climb it

### 1. Free gates — no licence, work in a fresh clone

```sh
make vendor-check     # no TSMC collateral tracked in this PUBLIC repo
make chip-boundary    # boundary spec covers every RTL port exactly once
make lint             # Verilator structural lint over the wrapper RTL
make check            # all three
```

### 2. Simulation and structural gates — need a tool seat

```sh
make elab             # structurally elaborate the top under VCS
make regress          # every data-plane proof, as one pass/fail table (ARGS=--quick)
make elab-strict      # ASIC-elaboration gate: blockers a simulator hides (Xcelium/HAL)
make cdc              # structural clock-domain-crossing pass
```

`make elab` sources three `set_env.sh` scripts in dependency order — this repo, then
the SoC, then TideLink — because TideLink defaults `CMSDK_DIR` with `:=` and the
SoC's choice has to win. It also *regenerates* the two sub-flists, which is why you
never hand-edit them.

### 3. Prove the ASIC contract before spending a licence hour

```sh
make -C ASIC/eth-chiplet check     # is this project's contract complete?   (<1s)
make -C ASIC/eth-chiplet doctor    # can this MACHINE run the flow?         (<5s)
make -C ASIC/eth-chiplet env       # every variable the tools will see
make -C ASIC/eth-chiplet help      # the flow's own help
```

`check` validates every path `design.mk` declares and tells you which variable
overrides each one. `doctor` checks tools on `PATH`, licence servers that actually
answer, CPU count, free disk, and `DISPLAY`. Today on `srv03335` both pass, with two
advisories: one of the two Cadence licence servers does not resolve, and `DISPLAY`
is unset so `make gui` will refuse (batch runs are fine).

---

## The ASIC flow itself

Four stages. Each reads what the last one wrote; they share one Innovus database, so
they must run in order — but any one can be re-invoked to resume.

| # | Command (repo root) | Direct form | Tool | Wall time |
|---|---|---|---|---|
| 1 | `make asic-syn` | `make -C ASIC/eth-chiplet syn` | Genus | ~1–2 h |
| 2 | `make asic-pnr` runs 2–4 | `make -C ASIC/eth-chiplet place` | Innovus | ~20 min |
| 3 | | `make -C ASIC/eth-chiplet cts` | Innovus | ~50 min |
| 4 | | `make -C ASIC/eth-chiplet route` | Innovus | ~2–3.5 h |
| — | `make asic-gds` | `make -C ASIC/eth-chiplet all` | both | multi-hour, unattended |

Measured on a 16-core host for ~189,000 instances. `route` is the long pole, and
inside it the long pole is post-route optimisation and hold repair, not the router.

`syn` has two extra prerequisites this design adds in `design.mk`: `asic-flist`
(re-renders the generated sub-flists) and `romlibs-check` (builds *this run's* boot
ROMs and verifies them word-for-word against the firmware). `place` depends on
`cpf-patch`. You do not invoke those yourself.

### Where a run writes

Everything lands under one directory per run:

```
ASIC/eth-chiplet/build/$(RUN_TAG)/
├── work/       the Innovus databases: _placed, _cts, _routed
├── logs/       tool logs
├── reports/    manifests, timing, DRC census, design_report.json
├── outputs/    _gate_power.v, _syn.sdc, _pnr.v, .gds
└── romlibs/    the boot ROMs this run was built against
```

`RUN_TAG` defaults to `default`. Two runs never collide, so an experiment is cheap:

```sh
make -C ASIC/eth-chiplet all   RUN_TAG=baseline
make -C ASIC/eth-chiplet cts   RUN_TAG=trial IN_RUN_TAG=baseline CTS_ROUTE_TYPE=1
make -C ASIC/eth-chiplet route RUN_TAG=trial

diff ASIC/eth-chiplet/build/{baseline,trial}/reports/route_manifest.txt
```

`IN_RUN_TAG` says which run to read the input database from; `SYN_RUN_TAG` does the
same for the netlist, CPF and SDC. The input run is read-only by construction. Every
knob's resolved value is recorded in that run's manifest, so a run is reproducible
from its own report directory — this is the mechanism, use it rather than editing a
file in place and losing the baseline.

Command-line variables propagate into sub-makes, so `make asic-syn RUN_TAG=fp1505`
from the repo root reaches the flow.

### While it is running, and after

```sh
make asic-status                                   # which stages have run, from disk
make -C ASIC/eth-chiplet status RUN_TAG=fp1505
make -C ASIC/eth-chiplet design-report RUN_TAG=fp1505    # -> reports/design_report.json
make -C ASIC/eth-chiplet design-report-show RUN_TAG=fp1505
make -C ASIC/eth-chiplet signoff-report RUN_TAG=fp1505   # -> reports/signoff_report.{txt,json}
```

`status` reads artefacts on disk, not exit codes. `design-report` is where chip
numbers come from — never re-`awk` a `.rep` file yourself; the report carries
per-metric provenance. `signoff-report` is this project's addition: stream identity
and md5, every non-zero rulecheck grouped by family with saturation flags, density
tables, post-route timing, ROM verdicts, and — the part a broker report cannot give
you — an explicit **NOT RUN** list.

### Knobs

```sh
make -C ASIC/eth-chiplet help-knobs   # every knob per stage, and what it costs
make -C ASIC/eth-chiplet help-all     # every target
```

There are ~30 per stage (`SYN_*`, `PLACE_*`, `CTS_*`, `ROUTE_*`). Set them on the
command line for an experiment; put them in `design.mk` only when they are what this
chip *is*.

### Cleaning

`make clean` drops `work/` and `logs/` for one run and **keeps** the GDS.
`make distclean` deletes the whole run tag, GDS included.

---

## Verification and signoff — separate runs, separate seats

**`make all` is `syn → place → cts → route` and nothing else.** No LEC, no LVS, no
Calibre DRC. What `route` runs in-flow is Innovus's own `check_drc`,
`check_connectivity` and `check_filler` — geometry checks against the geometry
Innovus knows about, which is not signoff. The route script says so itself, writes a
gaps file naming LVS and post-P&R equivalence as NOT RUN, and ends by telling you to
run `make lec-pnr`.

So: run these yourself, or run one of the two ladders below — `ci-pipeline.conf`
declares `lec-selftest`, `lec-pnr`, `lvs-preflight` and `lvs-fullchip`, and
`ci/signoff.yaml` declares its own set with explicit run tags. The stage targets
never chain into them; the ladders do. Each takes its own licence.

```sh
make -C ASIC/eth-chiplet drc          # signoff DRC (Calibre) on the built GDS
make -C ASIC/eth-chiplet drc-census   # THE VERDICT — no tool, seconds
make -C ASIC/eth-chiplet lvs-help     # the full nmLVS flow and every resolved value
make -C ASIC/eth-chiplet lvs-preflight  # LVS input check, no licence, no long run
make -C ASIC/eth-chiplet lvs-pg-gds   # re-stream a PG/pin-LABELLED GDS. REQUIRED FIRST.
make -C ASIC/eth-chiplet lvs-batch    # the run itself (alias: make lvs)
make -C ASIC/eth-chiplet lec-selftest # mutation-test the LEC harness (~1 min)
make -C ASIC/eth-chiplet lec-pnr      # synthesis netlist vs the routed one
make -C ASIC/eth-chiplet conn-check   # check_connectivity with its 1000 cap lifted
make -C ASIC/eth-chiplet fp-pg-check  # FP-SHORT/ISLAND/CORRIDOR on the post-PG DB
make asic-padring-gds GDS=<path>      # padframe name/count/order (legacy dir)
```

### LVS: it runs, it is cheap, and the verdict is not the result

Older notes in this tree say full-chip LVS "cannot be run here". That is wrong and has
been since 2026-08-23. Black-box LVS on the current design costs **~4 minutes** —
101 s of Innovus, ~2.5 GB — so it is affordable per design iteration, not a
once-a-tapeout event.

Two things make it work, and both are now defaults rather than things you must know:

- **LVS reads a different stream from the one you tape out.** A signoff GDS carries no
  supply text and no pin names, so Calibre finds no POWER net and boxed cells extract
  with zero pins. `lvs-pg-gds` re-streams the *same routed database*, read-only, with
  SPNET and LEFPIN text added. `flow/verify/restream.tcl` is the **wrong** tool — it
  only swaps a map and cannot synthesise those rows.
- **`LVS_PG` and `LVS_PG_PIN_TEXT` are set in `design.mk`** (§8), along with
  `LVS_PG_MAP_IN`, `LVS_PG_MERGE_GDS` and `LVS_PG_DB`. Before that they defaulted off,
  and `make lvs` dispatched to a runner whose argument contract it did not match — so
  it exited 2 without running. Both fixed in `14fd96c`.

- **`VSS` is in `.GLOBAL`, and the ROM CDLs are derived copies.** `design.mk` renames the
  boot ROMs' internal virtual ground to `VSS_ROMVIRT` before LVS reads them, which is what
  makes `.GLOBAL VSS` safe. The two are inseparable — `VSS` without the rename fabricates
  a short across both ROMs' power gates. Landed in `5c04870`; see trap 10 for why it
  matters more than a missing name.

**Read the reconciliation, never the verdict.** `INCORRECT` is the expected end state:
the 82 bond pads have no CDL anywhere and never will. What tells you the run was good
is the reconciliation. Measured on `rc4-20260829`, the submitted design, 2026-09-09:

| | pre-fix | rc4, post-fix |
|---|---|---|
| distinct orphan `/VSS` source nets | 18,031 | **0** |
| report size | 24 MB | 580 KB |
| `lvs-missing-connection` | — | **PASS** |
| ports | — | 52 / 52 |

**Orphan `/VSS` is the primary discriminator, not the matched counts.** Before `5c04870`
the gate's sign was inverted — a *stranded* ground pin matched a phantom one-pin net
while a *correctly connected* one mismatched — so the older reference figures from
`gdsrun-20260823-rzG` (269,824 nets, 325,099 instances, 52/52 ports) were measured by a
gate that could not see the thing they were being used to reassure about. Quote rc4's
numbers, not those.

**And validate the counting method before quoting the zero.** Run your exact counting
command against a *pre-fix* report first: it should return the large number there
(36,062 lines / 18,031 distinct) and zero on the new run. Without that control, a zero is
indistinguishable from a pattern that silently stopped matching — the same failure as a
`grep -c` that counts a summary token once and reports 0 for 26. State the number the
check cannot produce, then demonstrate it can.

Coverage arriving makes the verdict *worse* and the reconciliation *better*; a rise in
`INCORRECT` counts is the gate starting to see, not a regression. Do not read the
`INCORRECT NETS` list itself — it truncates at exactly DISC# 1000.

The critical distinction: **`drc` produces the evidence, `drc-census` reaches the
verdict.** Calibre exits 0 on a clean *run*, not a clean *result*, and a count read
off the summary is blind to density and to any check that saturated its result cap.
The same shape applies everywhere here — run the gate, then read the census.

`lec-selftest` before trusting any `lec-pnr` result on a new host: it proves the gate
can fail as well as pass. Several gates in this tree have historically been unable to
fail; that is why the selftests exist.

**Full-chip LVS will not run on this site, and that is declared as permanent rather
than pending.** There is no CDL or GDS for `tcbn65lp`, `tphn65lpgv2od3` or `tpbn65v`
anywhere — one 92-byte `unit.cdl` in the whole PDK. They ship only in the Back-End
packages, which will not be obtained. `lvs-fullchip` therefore carries
`status not-applicable` in the ladder, with a `refuted_by` probe that re-tests the
claim on every `signoff.py lint`, so the gap reopens by itself if a BE package ever
lands. Black-box LVS does work here today and is what to use.

There are five LEC targets, answering five different questions: `lec` (RTL vs the
synthesis netlist), `lec-syn` (RTL vs `_gate.v`, through the dofile Genus wrote),
`lec-gate` (`_gate.v` vs `_gate_power.v`), `lec-pnr` (synthesis vs post-P&R) and
`lec-pair` (any two netlists by path). Note that the two ladders point at different
directories — the pipeline's LEC entries name `ASIC/genus-innovus/outputs/`, while
`signoff.yaml` names `ASIC/eth-chiplet` run tags. They are not judging the same
netlists.

---

## The two ladders

Individual targets are for when you know what you want. There are two drivers that
run *everything*:

### `ci-pipeline.conf` — the check ladder

```sh
make asic-pipeline           # every declared check, in order, PAST failures, then collate
make asic-pipeline-resume    # only the stages that have not passed
make -C ASIC/eth-chiplet pipeline-dry    # the plan, nothing executed
make -C ASIC/eth-chiplet pipeline-list   # the ladder as declared
make -C ASIC/eth-chiplet pipeline-lint   # validate the ladder, run nothing
make -C ASIC/eth-chiplet flow-state      # collate every verdict + the artefact it came from
```

`pipeline` is not `all` renamed. `all` is syn→place→cts→route and stops at the first
failure; `pipeline` runs the whole declared ladder and deliberately continues past
failures. The 25 declared stages, in phase order:

- **rtl** — chip-boundary, lint, elab, elab-strict, cdc, regress, rom-selftest, rom-content
- **synth** — syn
- **pnr** — place, cts, route
- **physical** — rom-gds, drc, erc, lvs-preflight, metal-fill, lvs-fullchip, antenna, vendor-geometry
- **equiv** — lec-selftest, lec-pnr
- **power** — sta-signoff, ir-drop

Every stage is either measured or explicitly declared. A stage that has never run
appears as `UNVERIFIED`, which blocks — rather than as an absence, which reads as a
pass. Note that the ROM gates sit *ahead* of synthesis on purpose: synthesis bakes
ROM content into the netlist, and this project has streamed a GDS carrying a random
`eth_rom` for exactly that reason.

### `ci/signoff.yaml` — what "signed off" means

```sh
python3 scripts/ci/signoff.py list        # stages, gates, host requirement
python3 scripts/ci/signoff.py run <sel>   # run stage(s) and collect artefacts
python3 scripts/ci/signoff.py report      # collate into one report
python3 scripts/ci/signoff.py prove       # every check against must-pass AND must-fail fixtures
python3 scripts/ci/signoff.py lint        # manifest self-check
```

`prove` is the one to know. It answers "can this gate fail at all?" for every
fixture-backed stage in both directions. Run it before you trust a green.

Each stage in `signoff.yaml` has a `check:` block that re-reads the evidence rather
than trusting the exit code, and those blocks explicitly test for **vacuity** — e.g.
`classified == ports` is trivially true when both are 0, so a run that parsed no
ports agrees with itself perfectly. That is not a pass.

---

## Where to make each kind of change

| You want to… | Edit |
|---|---|
| change a clock period, die size, memory macro, PDK root | `ASIC/common.mk` |
| change the block name, flist, defines, stage prerequisites, ratchets | `ASIC/eth-chiplet/design.mk` |
| move a macro, change the die box, change halos | `ASIC/genus-innovus/scripts/floorplan.tcl` |
| change rings, stripes, risers, endcaps | `ASIC/genus-innovus/scripts/power_plan.tcl` |
| change corners or analysis views | `ASIC/genus-innovus/scripts/nanosoc_eth_chiplet_pads.mmmc` |
| change pad placement | `ASIC/genus-innovus/scripts/nanosoc_eth_chiplet_pads.io` |
| add constraints | the SDC list in `design.mk` §5 — **order is significant** |
| add one command at a stage seam | `ASIC/eth-chiplet/hooks/` (`pre_synth`, `post_synth`, `post_powerplan` exist) |
| add RTL to the chip | the flist — and read Trap 1 below first |
| change the engine's behaviour | a knob, or a hook. Not the toolkit. |

---

## Traps

These are the ones that have actually cost time here.

1. **Adding RTL to `tidelink/flists/tidelink_top_full_asic.flist` puts nothing in the
   chip.** The ASIC build reads a *generated* flist: `make asic-flist` resolves
   `tidelink_top_full_asic_V2` into `build/chip/flist/tidelink_asic.flist`, and the
   ASIC flist `-f`-includes only that. **V2 is the ship configuration**; V1 reaches
   nothing here.

2. **Genus and Innovus both exit 0 after printing an error and doing nothing.** Three
   P&R stages once "passed" in under a minute because `-f` is not a valid Stylus
   argument. Every stage target in the toolkit asserts on an *artefact on disk*. If
   you extend the flow, keep that discipline. (Note the asymmetry: `-f` is correct
   for Genus; Innovus in Stylus mode needs `-files`.)

3. **`make -n` and `make -q` are not target-existence probes in this tree.** GNU make
   runs recursive `$(MAKE)` lines even under `-n`/`-t`/`-q`, so the pass-throughs
   really enter the ASIC flows and can take a licence seat. To ask what exists, read
   the makefile or run `make -pRrq < /dev/null`, which only parses.

4. **`make distclean RUN_TAG=` and `BUILD_DIR=` are guarded, but understand why.**
   `?=` defaults an *undefined* variable, not an empty one, and `rm -rf $(RUN_DIR)`
   with an empty tag would take every run in the project. The flow refuses these
   explicitly. Do not remove those guards.

5. **The toolkit ships an `examples/nanosoc_eth_chiplet/` that sits at exactly the
   default paths.** An `ASIC_DIR` pointed at it resolves every variable
   successfully and builds a chip — the *wrong* chip, silently, with a full set of
   reports. The engine refuses it explicitly for that reason.

6. **`overrides/filler.tcl` is active in this project**, and an override replaces the
   engine's step file *wholesale* — the toolkit's copy is not sourced at all.
   `make check` warns about it. If you touch it: `cts_setup` must still end with
   `set_db timing_analysis_type ocv` or hold analysis for the whole design becomes
   fiction, and `filler` must still run `check_drc` between its two `add_fillers`
   passes or the repair pass is silently inert.

7. **A green verdict may have read the wrong stream, or measured nothing.** Both have
   happened here repeatedly. Before quoting any pass, check *what it ran over*: the
   `read:` line in `run_attest.py`, the stream md5 in `signoff-report`, the derived-
   layer witnesses. A check whose input was empty reports zero and looks clean.

8. **The toolkit's own README says "nothing in this repository has ever been
   executed."** That caution is stale as it applies here — this flow built the
   shipping GDS (`ASIC/eth-chiplet/build/full-20260814/outputs/…`) and the shipping
   netlist carries its provenance block. Read `ASIC/asic-toolkit/STATUS.md` for the
   component-by-component state rather than the headline.

9. **Never write into the shared vendor IP trees** — the two roots
   `ASIC/common.mk` exports as `$ARM_IP_LIBRARY_PATH` and `$PHYS_IP`.
   These are lab-wide shared vendor IP trees.
   If a fix appears to need one, copy the file into the project tree, point the flist
   at the local copy, and document the deviation.

10. **A fix can land on one ASIC path and not the other, and the live path is the one
    that loses.** `ASIC/genus-innovus/lvs_project.mk` is included *only* by the legacy
    Makefile; `ASIC/eth-chiplet/design.mk` is what the toolkit flow reads. A value set
    in the first reaches nothing in the second. This has now happened seven times in
    the LVS configuration alone — `BONDPAD_CELLS`, the supply names, and the five PG
    knobs were each right and unreachable before being carried across.

    **Live example, as of 2026-09-09.** The `.GLOBAL VSS` root fix of 2026-08-27 landed
    on the legacy path and not on the toolkit one:

    ```
    lvs_project.mk:261   LVS_GLOBAL_NETS ?= VDD VDDIO VSS VSSIO   ← VSS present
    design.mk:383        LVS_GLOBAL_NETS ?= VDD VDDIO VSSIO       ← VSS absent
    ```

    That matters more than a missing name. With `VSS` out of `.GLOBAL`, ~18,000 phantom
    one-pin `/VSS` source nets appear, and **the check's sign inverts**: a *stranded*
    ground pin exactly matches a phantom net while a *correctly connected* one
    mismatches. Measured — a deliberately stranded database returned PASS and the
    affected cell vanished from the report. Breaking a power pin made LVS cleaner.

    Do not "fix" this by adding `VSS` alone. The reason it was excluded is sound: both
    boot ROMs use `VSS` internally as a power-gated virtual ground (their real supplies
    are `VDDE`/`VSSE`), so `.GLOBAL VSS` fabricates a short across the power gate,
    source-side only. The enabling half is project-local ROM CDLs with the internal net
    renamed — `LVS_ROM_CDL_DIR` on the legacy path. Both halves together, or neither.

    **The general check**, before trusting any LVS or DRC number from `ASIC/eth-chiplet`:
    diff the two files for the setting you care about. `make lvs-help` prints every
    resolved value, and the resolved value is the only thing that settles it.

---

## A first week that actually teaches you the flow

**Day 1** — `make bootstrap`, `source set_env.sh`, `make check`, then
`make -C ASIC/eth-chiplet check doctor env`. Read the `env` output until you can say
where each variable came from. Nothing here costs a licence.

**Day 2** — `make elab`, then `make regress ARGS=--quick`. You now know the design
compiles and its data plane works.

**Day 3** — `make -C ASIC/eth-chiplet syn RUN_TAG=learn1`. One to two hours. Then
read `build/learn1/reports/syn_manifest.txt` line by line and
`make -C ASIC/eth-chiplet design-report RUN_TAG=learn1`.

**Day 4** — `make -C ASIC/eth-chiplet place RUN_TAG=learn1`, then `cts`. Read
`place_manifest.txt` and `cts_latency_writeback.rep`. Open
[`docs/tapeout/03-floorplan.md`](../tapeout/03-floorplan.md) and
[`04-power-plan.md`](../tapeout/04-power-plan.md) alongside them.

**Day 5** — `route`, overnight. Next morning: `status`, `design-report`,
`drc` → `drc-census`, `signoff-report`. Then run
`python3 scripts/ci/signoff.py prove` and watch gates fail on their must-fail
fixtures — that is the single most useful hour in this whole list, because it shows
you which greens in this project mean something.

**Then** — pick one knob from `help-knobs`, re-run one stage into a new `RUN_TAG`
with `IN_RUN_TAG` pointing at `learn1`, and diff the two manifests. That is the
working loop for every experiment from then on.

---

*A joint work commissioned on behalf of SoC Labs, under Arm Academic Access
license. Copyright 2026, SoC Labs (www.soclabs.org).*
