# 45 — Measured project status, 2026-08-18

> **This page is a measurement, not a summary.** Every claim is tagged **[MEASURED]** with the command and
> artefact that produced it, or **[INHERITED]** with the document it came from. Things I could not measure are
> recorded as **[UNMEASURED]** rather than inherited — an honest unknown is worth more than a borrowed fact.
>
> **Measured 2026-08-18, 14:20–15:15, at `HEAD = 98d1d7e` on branch `fix/tag-ram-gwen`.**
> HEAD moved under me mid-measurement (`8ad9f3b → 98d1d7e`); readings are timestamped where it matters.
>
> **Numbers carry a build name and are not comparable across builds.** `fp1505` and `full-20260814` share a
> netlist byte-for-byte and differ only in floorplan and route, and **Calibre returns the same 837 on both.**
>
> No Genus, Innovus, Voltus, Calibre, Quantus or Conformal run was launched to produce this page.

## Read this first — what changed the picture

1. **The shipping stream moved to `fp1505` today, and its route stage never finished.** The GDS exists only
   because `write_stream` ran ~10 s before Innovus died on a Tcl bug. **No route gate has ever rendered a
   verdict on the stream the project intends to ship.** The bug is already fixed at the current toolkit pin, so
   this is a re-run, not a redesign. → §2.4
2. **The stream was built by a toolkit with no recoverable revision** — a frozen copy in another session's
   scratchpad, `toolkit_git_sha = n/a`, not a git repo. → §2.4
3. **`build/signoff/signoff_report.md` is the most misleading artefact in the repo.** It stamps a 12-day-old
   commit header (191 commits behind) over rows spanning Aug 7 → Aug 18, because nothing expires a
   `status.json`. Two of its PASS rows are known false. → §3.3
4. **There is still no end-to-end RTL→netlist equivalence proof**, and the blocking `lec` gate reports green
   over the wrong half of a truncated log. → §3.5
5. **The stale-index trap is armed right now.** A bare `git commit` would revert six paths, including the
   toolkit pin set by `17385f8` — the very commit I was asked to confirm had landed. → §1.3

### Where the chip actually stands

| | state |
|---|---|
| **Clonable?** | Yes — all five pins are live-reachable today. But four are bare feature-branch tips (§1.2). |
| **Elaborates from its own pin?** | **Yes**, with a control that fails (§1.4). |
| **Signed off?** | **No.** `signoff.py`'s own verdict is `NOT SIGNED OFF`. DRC, ir-drop and lec-selftest are genuinely red; `rom-content` is red for a wiring reason (§3.2). |
| **Reproducible?** | **No.** Every build in the tree records `project_git_dirty = yes`, and the shipping build's stages do not share a toolkit revision (§2.5). |
| **Biggest single risk** | The `lec` gate's false green (§3.5), because it is the one that would catch a synthesis-level defect and it currently cannot. |

## 1. Git, pins and reproducibility

### 1.1 Branch state

| Fact | Value | Level | Command |
|---|---|---|---|
| Local `HEAD` | `98d1d7e` | worktree/HEAD | `git rev-parse HEAD` |
| `origin/fix/tag-ram-gwen` | `17385f8` | **live remote** | `git ls-remote origin refs/heads/fix/tag-ram-gwen` |
| Relationship | HEAD is **6 commits ahead**; `17385f8` IS an ancestor | HEAD | `git merge-base --is-ancestor 17385f8 HEAD` → 0 |
| `origin/main` | `8e6d043`, dated **2026-08-07** | live remote | `git ls-remote origin` |
| main vs branch | branch is a strict superset, **169 commits ahead** | HEAD | `git rev-list --count origin/main..HEAD` |

[MEASURED] **The push landed and nothing has moved on it since** — `17385f8` is still exactly the remote tip. But
**six commits made after it (14:04–14:26 today) are unpushed.** They are not lost work; they are simply not
what a clone gets.

[MEASURED] **`origin/main` has not moved since 2026-08-07.** The entire tapeout effort exists only on
`fix/tag-ram-gwen`. Anyone cloning the default branch gets an 11-day-old chip.

[MEASURED] **The unpushed six do not change RTL.** `git diff --stat 17385f8 HEAD -- src/rtl` is empty, and
`HEAD:src/rtl/nanosoc_eth_chiplet.sv` and `17385f8:src/rtl/nanosoc_eth_chiplet.sv` are the same blob
`6989db8`. They touch `ci/signoff.yaml`, the DRC/LEC fixtures (moved `full-20260814` → `fp1505`),
`scripts/ci/package_submission.sh`, `ASIC/genus-innovus/rail/rail_gate.py`, `ASIC/rom_gate.mk` and two hook/check
scripts. So the *gates* on the remote are one generation behind the gates in this worktree.

### 1.2 Submodule pins — recorded, checked out, and reachable

All five pins measured at three levels. `git ls-tree -r HEAD` for the record, `git submodule status` for the
checkout, and — after `git -C <sub> fetch --prune` — a **live `ls-remote` + `merge-base --is-ancestor` against
every head the remote actually advertises**. A SHA match is not reachability; a cached tracking ref is not a
live one. Both traps are avoided here.

| Submodule | Pin @HEAD | Checkout matches | Reachable on a LIVE remote | On the default branch? |
|---|---|---|---|---|
| `tidelink` | `b8f86b8` | yes | **yes** — tip of `refs/heads/feat/link-clk-divider` | **no** (`origin/main`: NO) |
| `tidechart` | `7a6dc35` | yes | **yes** — tip of `refs/heads/fix/tidechart-h-dupdecl` | **no** |
| `nanosoc-multicore-system` | `d6c8173` | yes | **yes** — tip of `refs/heads/dma250-ctxram-shrink` | **no** (`origin/master`: NO) |
| `ASIC/asic-flows` | `c2a46ee` | yes | **yes** — tip of `refs/heads/lpddr4-pll` | **yes** (its declared branch) |
| `ASIC/asic-toolkit` | `d556a12` | yes | **yes** — tip of `refs/heads/fix/tcl-parse-gate-both-directions` | **no** (declares `branch = main`) |

[MEASURED] **All five pins are clonable today** — this is an improvement on the documented history of unpushed
pins. But **four of five are the bare tip of a short-lived feature branch**, and nothing else references them.
A branch delete or a force-push on any of those four makes this chip unclonable, with no warning. Only
`asic-flows` sits on a branch the superproject actually declares.

[MEASURED] **`ASIC/asic-toolkit` declares `branch = main` in `.gitmodules` but is pinned off `main`.** A
`git submodule update --remote` would silently move it to a different commit than the one that is pinned.

### 1.3 The stale-index trap — FIRED, live right now

The shared `.git/index` (no `GIT_INDEX_FILE` set; `.git/index` mtime 2026-08-18 14:26:45) holds **six paths at
older content than `HEAD`**. Proven without moving any ref, by writing the index to a tree object and diffing:

```
$ git write-tree                       # writes an object only; moves no ref
a4ceab21c09b0d8e1be094ab4897d854a9ca7965
$ git diff --name-status a4ceab2 HEAD
M  ASIC/asic-toolkit
M  ASIC/genus-innovus/inputs/ethernet_constraints.sdc
M  ASIC/sta/sta_gate.py
M  docs/tapeout/25-what-remains-explained.md
M  docs/tapeout/26-plan-to-submittable-gds.md
M  src/rtl/nanosoc_eth_chiplet.sv
```

Each of those six index blobs is **byte-identical to the version at a specific earlier commit** — the signature
of a stale snapshot, not of new staged work:

| Path | Index blob equals version at | HEAD version set by |
|---|---|---|
| `ASIC/asic-toolkit` | `dc315bd` (pin `5094a84`) | `17385f8` (pin `d556a12`) |
| `ASIC/genus-innovus/inputs/ethernet_constraints.sdc` | `15b0501` (08-17) | `cd954fd` |
| `ASIC/sta/sta_gate.py` | `8099410` | `e566338` |
| `docs/tapeout/25-…md` | `735d04a` | `d828785` |
| `docs/tapeout/26-…md` | `735d04a` | `d828785` |
| `src/rtl/nanosoc_eth_chiplet.sv` | `c91c5f9` | `a47403d` |

[MEASURED] **A bare `git commit` from this worktree right now would revert all six**, including the
`asic-toolkit` gitlink from `d556a12` back to `5094a84` — undoing `17385f8`, the very commit the owner asked
me to confirm had landed. It renders in `git status` as an unremarkable `MM`. **Anyone committing here must use
a private `GIT_INDEX_FILE` and verify with `git diff --name-status <parent> <sha>` afterwards.**

### 1.4 Would a fresh recursive clone elaborate?

Constructed the equivalent rather than trusting the worktree: `git archive HEAD src/rtl flist verif/lint`, plus
`git -C tidelink archive <recorded pin>` and the same for `tidechart`, into a clean directory. Confirmed the
extracted top is HEAD's and not the dirty worktree's — `md5 c838b180…` (= `git show HEAD:…`) vs the worktree's
`3c022900…`.

Blackbox stubs for `nanosoc_multicore_soc`, `cmsdk_ahb_to_apb`, `tidechart_controller` and `tidelink_top` were
generated **from the pinned sources** with the repo's own `verif/lint/gen_bbox.py`, which preserves real port
names, directions and widths. The seam under test is therefore exactly the wrapper-to-submodule port contract.

```
verilator --lint-only -Wall --top-module nanosoc_eth_chiplet \
   src/rtl/{nanosoc_eth_chiplet,chiplet_d2d_decode,tidechart_shim}.sv \
   stubs/{nanosoc_multicore_soc,cmsdk_ahb_to_apb,tidechart_controller,tidelink_top_PIN}.sv
```

| Run | tidelink stub from | Result |
|---|---|---|
| **Experiment** | recorded pin `b8f86b8` | **exit 0 — 0 errors, 0 warnings. ELABORATES.** |
| **Control** | previous pin `2c2f8d4` | **exit 1 — `%Error: …nanosoc_eth_chiplet.sv:803: Pin not found: 'link_clk_div_ratio_i'`** |

[MEASURED] **The control fires, on exactly the port that matters** — so the green is discriminating, not a
check that cannot fail. `2c2f8d4`'s `tidelink_top` has no `link_clk_div_ratio_i` (`grep -c` → 0); `b8f86b8`'s
declares it at line 364 and wires it to the divider at line 2827.

[MEASURED] The same holds for a clone of the **pushed** tip: `17385f8` records identical pins for all five
submodules and the identical `src/rtl` blob, so a clone of `origin/fix/tag-ram-gwen` elaborates the same way.

**Scope limits, stated honestly:**
- [MEASURED] This proves the **wrapper-level port contract**, not a full-hierarchy elaboration. The SoC,
  TideLink internals, TideChart internals and CMSDK cells are blackboxed.
- [MEASURED] **A fresh clone cannot render the full flist without first running the SoC generator.**
  `flist/nanosoc_eth_chiplet.flist` requires `${CHIPLET_SOC_VCS_FLIST}` (= `$(BUILD)/soc_vcs.f`, `Makefile:28`),
  flattened from the SoC's own flist, which `-f`-includes 11 `build_soc/…` paths. `build_soc/` is **not tracked
  at the SoC pin** (`git ls-tree -r <pin> | grep -c '^build_soc/'` → 0), and no `nanosoc_multicore_soc.v/.sv`
  is tracked there either. Running it from a clean env fails closed and says so:
  `flist_resolve: unset variable ${CHIPLET_SOC_VCS_FLIST}`.
- [MEASURED] Elaboration also requires the lab-shared vendor IP trees via `ARM_IP_LIBRARY_PATH` / `CMSDK_DIR`,
  which are outside the repo. A clone on a host without them cannot elaborate at all.
- [UNMEASURED] I did not run a full-hierarchy elaboration from the pristine tree; that needs the generator and
  the vendor trees, and a synthesis/sim seat I was asked not to take.
## 2. Builds

There are **three** build roots, not one. Searching the wrong one is a documented way to reach a confident wrong
answer, so all three are named here.

| Root | Contents | Status |
|---|---|---|
| `ASIC/eth-chiplet/build/` | 14 dirs, newest 2026-08-18 14:24 | **the live root** |
| `ASIC/genus-innovus/runs/` | 40 run dirs; ~30 carry a netlist or stream | legacy engine, **dead since 08-14** |
| `ASIC/genus-innovus/baseline_2026-08-0{6,7}/`, `lec*_shadow/` | 5 dirs, 2 GDS, 5 netlists | historical |

[MEASURED] `ls -la ASIC/genus-innovus/outputs/` — holds only `eval/` (empty) and `romlibs/`. **No netlist, no
stream.** Any gate still pointing there is measuring nothing (see §3).
[MEASURED] `ASIC/genus-innovus/runs/{latest,last}` both symlink to `20260812T144334Z_route-baseline-gds-nonstrict`
— **stale by 6 days.**

### 2.1 Stage completion, netlist and stream

Stage completion determined from artefacts (`reports/<stage>_manifest.txt`, `work/*_placed|_cts|_routed`,
`route_gate.txt`), never from a README.

| Build | du | syn | place | cts | route | netlist | stream |
|---|---|---|---|---|---|---|---|
| **fp1505** | 1.7G | — | ✔ | ✔ | **CRASHED** | none of its own (`_pnr.v` only) | **`…pads.gds` 312,343,330 B, md5 `ea1c52d7…`** |
| **full-20260814** | 3.6G | ✔ | ✔ | ✔ | ✔ but **gate HARD-FAILED** | `…_gate.v` `f567c9c0…`, `…_gate_power.v` `1e2eab3f…` | `…pads.gds` 313,424,880 B, md5 `af2e06b2…` |
| m5off5 | 1.7G | symlink | ✔ | ✔ | ✔ | → `default/` | `2ad902ce…` |
| m5off6 | 1.6G | symlink | ✔ | ✔ | ✔ | → `default/` | `143bea0b…` |
| macro-move | 1.6G | symlink | ✔ | ✔ | ✔ | → `default/` | `8d76fbcc…` |
| default | 1.1G | ✔ | ✔ | ✔ | ✗ | `…_gate_power.v` `63127ad6…` | **absent** |
| knobs-live | 1020M | ✗ | ✗ (resumed off `default`) | ✔ | ✔ | — | `2f8414e3…` |
| padfix | 377M | ✔ only | ✗ | ✗ | ✗ | `6656dc17…` (**orphan — never placed**) | absent |
| **gate1** | 47M | **RUNNING NOW** | — | — | — | absent | absent |
| gate1-aborted-sdc-20260818 | 55M | aborted | — | — | — | absent | absent |
| **resyn-20260818** | 38M | **RUNNING NOW** | — | — | — | absent | absent |
| gls | 13M | ROM-readback GLS sandbox, not an implementation build | | | | | |
| pipetest-dry / -list | 24K / 0 | CI dry-run; all `result.json` are `"status":"unverified","dry_run":true` | | | | | |

### 2.2 `build/gate1` — YES, it exists, and it is running

[MEASURED] `ls -ld ASIC/eth-chiplet/build/gate1` → exists (2026-08-18 14:24). **`outputs/` is empty**; a Genus
run is live inside it (PBS worker dirs at 14:52, `logs/syn.log` still growing). `resyn-20260818` is likewise
live. **Two synthesis seats are held right now** — anyone planning EDA work should assume that.

### 2.3 Which build is the shipping GDS

[MEASURED] **No script defaults to a build.** `scripts/ci/package_submission.sh:72-83` refuses and exits 1 with
`FAIL: no build named — set RUN_TAG=<build>` ("there is deliberately no default"). The flow's own fallback,
`ASIC/asic-toolkit/mk/flow.mk:127` `RUN_TAG ?= default`, resolves to `build/default`, **which has no GDS**.

The decision is made in the signoff manifest:

| Decider | File:line | Value |
|---|---|---|
| **DRC** | `ci/signoff.yaml:1250` | `make -C ASIC/eth-chiplet drc RUN_TAG=fp1505` |
| **ROM-in-GDS** | `ci/signoff.yaml:677` | `ROM_GDS=…/build/fp1505/outputs/nanosoc_eth_chiplet_pads.gds` |
| **rail/IR** | `ASIC/genus-innovus/rail_project.mk:54` | `RAIL_RUN_TAG ?= fp1505` |
| **post-P&R LEC** | `ci/signoff.yaml:1069` | `RUN_TAG=fp1505 SYN_RUN_TAG=full-20260814` |
| **synthesis LEC** | `ci/signoff.yaml:773` | `RUN_TAG=full-20260814` |
| **STA** | `ASIC/sta/run_sta.sh:6-9` | "Defaults to the completed full-20260814 route. Deliberately NOT fp1505" |
| the decision, stated | `ci/signoff.yaml:468-470` | "fp1505 is the promoted place-and-route build" |

[MEASURED] **The shipping stream is `ASIC/eth-chiplet/build/fp1505/outputs/nanosoc_eth_chiplet_pads.gds`
(md5 `ea1c52d7c848a2770a4e44d11555bdc6`, 312,343,330 B, 2026-08-17 21:33:09)** — hashed independently as a
control. But **the netlist and the timing under signoff are `full-20260814`'s.**

### 2.4 Two findings that bear on whether fp1505 can ship

**(a) [MEASURED] fp1505's route stage never finished.** `reports/route_manifest.txt` and `route_gate.txt` are
both absent (`ls` → No such file), while `full-20260814` has both. `work/innovus.log5` ends:

```
@file 1625: set have_pgv [route_power_via_census …]
**ERROR: (IMPSE-110): … 4_route.tcl line 1625: bad option "-layer_range\s*\{([^\}]*)\}": must be -all, …
**ERROR: (IMPSYT-6692): … script processing was stopped.
```

A Tcl bug — `regexp` without `--`, so Tcl read the pattern as an option. `write_stream` had already run at
21:32:58, so **the GDS exists but no route gate has ever rendered a verdict on it.**

**(b) [MEASURED] fp1505 was built by a toolkit that is not the pinned submodule and is not durable.** Its
provenance records `toolkit_git_sha = n/a`, and `work/innovus.cmd5` sources `4_route.tcl` from **another
session's scratchpad** under `/tmpdir/…/926cdba6-…/scratchpad/toolkit-frozen/`. That directory still exists but
`git -C … rev-parse HEAD` → `fatal: not a git repository` — **there is no recoverable revision for the code that
produced the shipping stream.**

The good news: the bug is already fixed at the current pin.

| copy | line | text |
|---|---|---|
| frozen (built fp1505) | 369 | `if {[regexp {-layer_range\s*\{([^\}]*)\}} $line -> r]}` |
| **pinned `d556a12`** | 371 | `if {[regexp -- {-layer_range\s*\{([^\}]*)\}} $line -> r]}` |

[MEASURED] **Re-running fp1505's route with the pinned toolkit should complete and produce the missing gate.**
That is the cheapest route to a stream whose route stage has actually been judged.

### 2.5 Provenance

[MEASURED] **Every stage of every build records `project_git_dirty = yes`.** Not one build in this repo was
produced from a clean tree.

[MEASURED] **The shipping netlist's stages do not share a toolkit revision** — `full-20260814` synthesis ran at
toolkit `20bc972`, its place/cts/route at `9feeca9`. This is the documented "shipping GDS is unreproducible"
condition, still true.

[MEASURED] Builds with **no provenance block at all**: `gate1`, `gate1-aborted-sdc-20260818`, `resyn-20260818`,
`gls`, `pipetest-list`.

### 2.6 Netlist lineages

[MEASURED] `fp1505` has **no gate netlist of its own**. Its place stage read `full-20260814`'s by absolute path,
recorded by hash in `place_provenance.txt` (`sha256 d2019afd…be50c`, 40,394,900 B) and re-verified live as
byte-identical today. So "same netlist, differs only in floorplan and route" is **confirmed by identity, not
coincidence.**

Exactly two lineages exist: the `default` lineage (`63127ad6…`) feeding `default`/`knobs-live`/`macro-move`/
`m5off5`/`m5off6`, and the `full-20260814` lineage (`1e2eab3f…`) feeding `full-20260814`/`fp1505`. `padfix`'s
netlist is a third, orphaned — no build ever placed it.
## 3. Signoff — the verdicts, and what each green actually measured

### 3.0 How the driver is actually invoked

[MEASURED] `python3 scripts/ci/signoff.py --help` → verbs are
`list, expand, provenance, run, report, prove, lint`. **There is no "default mode":** `run` requires explicit
stage ids or a selector (`rtl` / `physical` / `all`). **16 stages, 9 declared coverage gaps.**

[MEASURED] `ci/signoff.yaml` in the worktree is **identical to HEAD** (`git diff HEAD -- ci/signoff.yaml` empty).
It was dirty at the start of this session and was committed mid-task by a concurrent session in `f0dde6e`
(HEAD moved `8ad9f3b → 98d1d7e` underneath us). **Do not describe it as dirty.**

### 3.1 Per-stage verdicts, measured today

Stages whose `run:` would launch Genus, Innovus, Voltus, Calibre or Conformal were **not launched** (per the
standing constraint and the live seats). For those, the stage's own `check:` was evaluated against the existing
transcript/census — which is what the gate itself grades.

| stage | gate | verdict | classification |
|---|---|---|---|
| chip-boundary | block | **PASS** | REAL PASS — 111 ports / 111 classified, 23 pad cells |
| lint | block | **PASS** | REAL PASS — 6 Verilator passes incl. 2 loop-detection sanity proofs |
| elab | block | **PASS** | REAL PASS — 213 modules, reached link |
| elab-strict | block | **RUNNING** at time of measurement | — (its stored PASS is a stale killed run, see §3.3) |
| cdc | report | **FAIL** (report-only) | real fail |
| regress | block | **PASS** | ⚠ **REAL PASS over a 6-testcase population** — see §3.4 |
| rom-selftest | block | **PASS** | REAL PASS — 25 mutation cases |
| rom-content | block | **FAIL** | ⚠ **RED FOR A WIRING REASON — see §3.2** |
| rom-gds | block | **PASS** | REAL PASS — 1024 words extracted from the real 312 MB stream |
| lec | block | **PASS** | ⚠ **NOT an RTL→netlist proof — see §3.5** |
| lec-selftest | block | **FAIL** | confirmed RED — check input absent |
| lec-pnr | block | **PASS** | REAL PASS — 61,674 points, 0 abort |
| lvs-preflight | report | **PASS** (4.1 s) | ⚠ premise refuted, scope redefined — see §3.6 |
| drc | block | **FAIL** | REAL FAIL — 140 design-owned > budget 0; 6159 density windows > 0 |
| ir-drop | report | **FAIL_HARD** | REAL FAIL — 351,211 instances, 99.86% coverage, 330 unpowered |
| ir-drop-selftest | block | **PASS** | REAL PASS — 29 cases incl. a positive control |

[MEASURED] `signoff.py prove` → **70 cases over 14 checks, 0 problems.** Every case behaved: must-pass green,
must-fail red. [MEASURED] `signoff.py lint` → manifest clean, **9/9 gaps "still real"**.

**The brief's premise was substantially wrong, and that should be said plainly.** This manifest is well
hardened — a three-state PASS/FAIL/UNVERIFIED model, enforced `needs_implementation` globs, `check:`
post-conditions on 14 of 16 stages, and `prove` requiring both must-pass *and* must-fail fixtures.
**No stage was found green because its input was missing.** The defects below are subtler than that.

### 3.2 `rom-content` is RED for a wiring reason, not a ROM reason

[MEASURED] The stage's two halves resolve `ROMLIBS_DIR` to **different trees**:

| half | command | resolves `ROMLIBS_DIR` to |
|---|---|---|
| `run:` | `make -C ASIC/genus-innovus romlibs-check` | `$(ROM_RUN_DIR)` (`ASIC/genus-innovus/Makefile:129`) |
| `check:` | `make -C ASIC -f common.mk rom-vars` | `…/ASIC/romlibs` (`ASIC/common.mk:434`) |

[MEASURED] Running the identical check via `common.mk` makes it **PASS** (eth_rom 512 words, cc_rom 512 words).
The two ROM trees hold **byte-identical macros** (md5 match on the `.rcf`). **No ROM is wrong — the gate as
wired cannot pass.** This is the single blocking red that is a false alarm, and it is cheap to fix.

### 3.3 Stale-wins reporting — the systemic one

[MEASURED] `signoff.py report` renders a header of
**`Commit 3f3e6c3c… — WORKING TREE DIRTY · 2026-08-06T14:56:42Z`** while its rows span **Aug 7 → Aug 18**.

`cmd_report` globs `build/signoff/*/status.json` with **no freshness, commit or mtime check**, and stamps one
provenance header from a separate file. **Nothing expires a `status.json`.** Measured consequences:

- [MEASURED] The stamped commit `3f3e6c3` is **not an ancestor of HEAD** and is **191 commits behind**.
- [MEASURED] `lec-selftest`'s **PASS row is from 2026-08-07** (`status.json` mtime) and is **false today**.
- [MEASURED] `elab-strict`'s PASS row is the **3605.4 s killed run** — the documented false-green-on-timeout.
- [MEASURED] The report's own verdict is **`NOT SIGNED OFF — 1 blocking stage FAILED`**, and it lists `lec`,
  `lec-pnr`, `drc`, `ir-drop` under **"Stages not run in this session"**.

**A reader who opens `build/signoff/signoff_report.md` today gets a 12-day-old header over a mixed-age body.**
That is the most misleading artefact in the repository right now, and it is misleading by construction rather
than by neglect.

### 3.4 `regress` is green over 6 testcases, and the relevant tests are excluded

[MEASURED] `verif/g2_soc_pair/Makefile: MODULE ?= test_g2_soc_pair` — **only that module runs.**
`test_peer_burst_corruption.py` (1 cocotb test) and `test_peer_burst_adversarial.py` (8) sit in the same
directory, are **not in `MODULE`**, and are **untracked in git**.

**The suite is green while the tests for the known peer-write burst-corruption defect never execute** — and
being untracked, they are also absent from every clone. This is a green that is true and useless.

### 3.5 The `lec` gate's PASS is not an RTL→netlist proof

Two independent measurements converge, and they disagree on one number in a way that is itself informative.

- [MEASURED] The `syn` leg (RTL → `_gate.v`) has **no `verdict.txt`**; its log ends mid-compare on the 21st
  sub-compare. Only the second half (`fv_map → gate.v`) completed. The gate `re.search`es for the **first**
  `Compare Results:` line — which belongs to the half that is **not** the RTL comparison. Replaying the gate's
  own check code against the real log returns **PASS**.
- [MEASURED] The gate reports **58,672 compare points**, while the `gate` and `pnr` legs both report
  **61,674**. A different population is a different comparison.

[UNRESOLVED] 58,672 is also the point count recorded for the **audit-mutant** fixture. I did not establish
whether that is coincidence or the gate grading the wrong transcript entirely. **Either way, there is no
end-to-end RTL→netlist equivalence proof, and the blocking gate reports green.** This is the highest-value
thing on this page to fix.

[MEASURED] Two corrections to standing concerns: the **08-08 broken joint is repaired** for the current chain
(`_gate_power.v` md5 `1e2eab3f…` is the same file on both sides), and `gate.v`/`gate_power.v` are same-run,
same-minute, same module count (3029), differing only by PG decoration.

### 3.6 The four named re-checks

| # | item | measured state |
|---|---|---|
| 1 | **DRC gate RUN_TAG** | **`fp1505`.** Directory exists; the Calibre summary header names that exact stream; the GDS mtime (08-17 21:33) predates the run (08-18 11:27). Budgets are **0**, not the day's number. **Not a null pass — and not green** (140 design-owned, 6159 density). ⚠ But **nothing pins fp1505 as the shipping build**: `package_submission.sh` refuses to default, and the rom-gds gate itself prints *"this stream is NOT declared to be the one that ships (`ROM_GDS_SHIPS=no`)"*. |
| 2 | **`lec-selftest`** | **Confirmed RED.** Its check input `…/full-20260814/logs/lec_selftest_summary.log` **does not exist** → immediate FAIL. Only **7 of 9** case logs present. The three discriminator cases that did run behaved correctly. Any PASS on display is the **stale Aug-7 `status.json`**, which predates the three-state driver. |
| 3 | **LVS preflight** | **Premise refuted.** It **PASSES in 4.1 s**, on a redefined scope: Back-End packages are *not* required for stdcells/IO/pads, Front-End Verilog suffices; 8 macro CDLs resolve, 469 `.SUBCKT`s, all 7 deck placeholders present. Its self-declared limit is *"clean modulo black boxes and modulo the pad ring"*. ⚠ It has **no `check:`**, collected **0 artefacts** (its declared log pattern matched nothing), and still points `LVS_RUN` at the **08-10** build. |
| 4 | **`ASIC/genus-innovus/outputs/`** | **Largely closed.** 4 hits, all in `ci/signoff.yaml`, none in `scripts/ci/`. Lines 636, 1018, 1191 are **comments documenting the repointing away**. Only line 1735 is live — a *fallback* glob in `io-rail-ir-drop`'s `refuted_by`, whose primary glob returns **7 real CPFs**. The dir exists but holds only `eval/` and `romlibs/`. **Not a null pass.** |

### 3.7 The gap-tracking layer has its own null result

[MEASURED] Three gap probes — `gds-completeness`, `lvs`, `dynamic-ir-drop` — all run `find ${TSMC_65_HOME} …`.
**`TSMC_65_HOME` is UNSET** in the shell the linter spawns, so `find` defaults to `.` (the repo root). They exit
1, and **1 is the status the code treats as authoritative** ("still real").

The *conclusion* is right — a control against the real PDK mount also returns 1 — **but it is right by luck.**
If the Back-End packages were ever installed, **these probes could never notice.** Unfalsifiable while appearing
checked: exactly the defect the manifest's own comment describes for `io-rail-ir-drop`.

[MEASURED] **And one gap's stated reason is now simply false.** `sta-signoff` says *"No Tempus or PrimeTime
installed"*, and its probe is `command -v tempus`. Measured:

```
$ command -v tempus              -> not on PATH
$ head -1 ASIC/sta/reports/timing_summary.rpt
#  Generated by:      Cadence Tempus 21.11-s131_1     (written 2026-08-18 13:05)
```

**Tempus is installed and ran a real timing analysis today.** The probe tests PATH visibility in a bare shell,
not whether signoff STA was performed, so `lint` reports "still real" for a gap whose stated reason is dead.
The gap may still be real *in substance* — §4.5 shows single-corner physics, a contradictory SI flag and
unmeasured hold coverage — **but for entirely different reasons than the one recorded, and the probe would
never tell the difference.**

### 3.8 Two stages cannot be shown able to fail

[MEASURED] `cdc` and `lvs-preflight` have **no `check:` at all**, so `prove` skips them — that is why the run
covers **14 checks over 16 stages**. Neither is demonstrated able to fail. Both are `gate: report`, so neither
blocks, but neither should be quoted as evidence either.
## 4. The physical numbers, each with its build named

> **`fp1505` and `full-20260814` share a netlist byte-for-byte** (§2.6). Calibre returns the **same 837** on both.
> A number without its build is not a number, and 837 does **not** distinguish these two builds.

### 4.0 Summary

| # | item | **[fp1505]** (promoted stream) | **[full-20260814]** (netlist + timing) |
|---|---|---|---|
| DRC | raw / post-waiver / design-owned | **837 / 146 / 140** | **837 / 146 / 140** |
| DRC | density windows (core, gated) | **6159** | **6149** |
| ERC | — | **UNMEASURED** | **UNMEASURED** |
| LVS | — | **UNMEASURED** | **UNMEASURED** |
| IR | worst / p99 / mean | **1.3889% / 1.3574% / 1.1797%**, **330 disconnected** | **UNMEASURED** (empty results dir) |
| STA | setup / hold | not run (refused by name) | **−0.810 / −399.949 / 1475** and **−0.037 / −2.446 / 438** |
| LEC | — | pnr leg **PASS** | gate+pnr **PASS**; **RTL→gate has NO verdict** |
| ROM | at the reticle | **512/512 both ROMs, 0 differing** | no surviving evidence |
| Antenna | — | in-tool 0; **no Calibre run exists** | Calibre 0/714; **not signoff** |

### 4.1 DRC

[MEASURED] Calibre's own total line, read directly from both summaries:

```
$ grep -n 'TOTAL DRC Results Generated' …/build/{fp1505,full-20260814}/work/drc_run/…drc.summary
fp1505          :2296: TOTAL DRC Results Generated:     837 (4428)
full-20260814   :2296: TOTAL DRC Results Generated:     837 (4428)
```

fp1505's run is **today**, 2026-08-18 11:32; full-20260814's is 2026-08-17 18:09.

| | fp1505 | full-20260814 |
|---|---|---|
| raw | 837 | 837 |
| post-waiver | 146 | 146 |
| **design-owned** | **140** | **140** |
| vendor-memory | 697 (691 waived, **6 retained as a positive control**) | 697 |
| io-pad-abstract | 0 | 0 |
| **density windows (core-only, gated)** | **6159** of 12817 | **6149** of 12805 |

[MEASURED] **Not capped.** Declared cap is `Maximum Results/RuleCheck: 1000`; the largest single rulecheck is
691. No rulecheck sits at the cap, so the truncation trap (Calibre writing the capped value into both count
fields) did not fire. **This run is a measurement.** Two further independent executions reproduce 837 (4428).

[MEASURED] **The identical totals are real, and the composition underneath is not identical.** Per-rule counts
differ between the builds (a metal-4 density check 8 vs 5, metal-5 3 vs 5, an M8 width check 2 vs 3, an M9
width check 2 vs 1). **Density (6159 vs 6149) is the only headline number that separates them.**

[MEASURED] **The 140 is a FLOOR, not a total.** 424 cell masters carry no transistor geometry in the stream, so
rules between top-level routing and a cell's internal geometry cannot fire. Read it as "clean in the layers we
actually have".

> ⚠ *Method note:* my own first pass summed rulechecks across the whole file and got **1674 — exactly double**,
> because the summary contains two statistics sections (top-level at line 260 and `BY CELL` at line 2192).
> Calibre's own `TOTAL DRC Results Generated` line is the authority. A parser that does not know where a report's
> sections end will silently double a number and look plausible.

### 4.2 ERC — UNMEASURED

[MEASURED] No ERC artefact exists for either current build. The only ERC runs on disk are **four from
2026-08-10**, against a build that no longer ships, each reporting `TOTAL ERC RuleCheck Results Generated: 0 (0)`
over 6 executed checks.

[MEASURED] **That zero measures nothing.** All six checks are transistor-level constructs (gate-to-supply,
floating-well, substrate). With no standard-cell transistors in the stream they are structurally incapable of
firing. **ERC is not a stage in `ci/signoff.yaml` at all.**

### 4.3 LVS — UNMEASURED, and the one build ever measured came back INCORRECT

[MEASURED] No LVS artefact exists for `fp1505` or `full-20260814`; neither build has an `_lvs.gds`. The only
LVS on disk is four runs from **2026-08-10** against a retired build. All four report **INCORRECT**.

Best configuration: ports 50/0/0, nets 62,483/0/0, **instances 323,162 matched / 0 unmatched-layout / 82
unmatched-source** — the 82 being bond pads, each `** missing instance **`.

[MEASURED] **It is black-box LVS, not transistor LVS.** The box file carries 111 `LVS BOX` directives covering
884 unique cells — every standard cell, IO driver, clamp and bond pad. Only 8 hard macros carry real SPICE and
real layout. **~62% of matched instances (199,027 of 323,162) matched on name and count only.**

[MEASURED] **The clean net column covers ~2.7% of the design** — 62,483 of 2,307,216 source nets survived to be
compared; 633,398 isolated layout nets and 230,605 source nets were deleted first. In the pin-text variant,
which gives the boxes pins, 268,171 nets are compared and **16,848 fail**. `Layout Component Type: … (0 pins)`
matches **745 of 745**. **The perfect-looking run is the blind one.**

[MEASURED] **No transistor netlist exists on this machine** for standard cells, IO or pads — the installed
vendor packages are front-end releases. Memory macros do have CDL, plus two project-built ROM CDL+GDS pairs.

[MEASURED] ⚠ **A live contradiction, dated today 14:56.** `build/signoff/lvs-preflight/` now reports
`LVS PREFLIGHT: OK — both layers clean` (`status.json` `rc:0, passed:true`) on a **redefined scope** ("does NOT
require foundry Back-End packages … Front-End simulation Verilog is sufficient"). This contradicts the older
preflight logs (`== LVS BLOCKED ==`) and `ci/signoff.yaml`'s own `unsupported:` declaration that full-chip LVS
will not run here. **It also still points `LVS_RUN` at the 08-10 build.** The honest phrasing is the preflight's
own: *clean modulo black boxes and modulo the pad ring* — never *signoff clean*.

### 4.4 IR drop (Voltus)

**[fp1505] — MEASURED, verdict `FAIL_HARD`.** From `ASIC/genus-innovus/rail/work/fp1505/verdict.json`
(2026-08-18 00:29), per-instance artefact `results/PD_TOP_125C_avg_1/Reports/VDD_VSS_div.iv` (38.4 MB).

| metric | value |
|---|---|
| worst effective collapse | **15.0 mV = 1.3889%** of 1.08 V |
| p99 / p99.9 / p95 / p50 | **1.3574%** / 1.3722% / 1.3398% / 1.2398% |
| mean | **1.1797%** — **over its 1.0% budget** |
| VDD droop worst | 6.32 mV (0.5852%) |
| VSS rise worst | 8.89 mV (0.8231%) |
| **`iv_disconnected`** | **330 instances with no path to a supply rail** (limit 0) |
| population | 350,718 of 351,211 analysed (99.86%); 350,388 iv_rows + 330 disconnected = 350,718 — **consistent, not capped** |

Three failures: **`pg.disconnected` (330, HARD)** — a functional defect, those cells do not power up;
**`em.current_density` = NOT_ANALYSED (advisory)** — no EM models supplied, so Voltus disabled the analysis and
completed anyway; **`budget.eff_mean_pct` 1.1797% > 1.0%**. Only **69.35% of chip power is attributable**
(24.13 mW unattributed); the IO rails are excluded by construction, being absent from the CPF.

**[full-20260814] — UNMEASURED.** `verdict.json` records `run.completed=False`, `fatal=no_rail_artefact`,
`vsrc_found=-1`; the `results/` directory is **empty**. The solve never produced output. There is no IR number
for this build.

### 4.5 STA — parasitics ARE now loaded; this changed today

**Build: `full-20260814` only.** `ASIC/sta/run_sta.sh` refuses `fp1505` by name. Run 2026-08-18 13:02→13:07.

| | WNS | TNS | violating endpoints |
|---|---|---|---|
| **Setup** | **−0.810** | **−399.949** | **1475** (reg2reg 1344 + clock-gating 131) |
| **Hold** | **−0.037** | **−2.446** | **438** (reg2reg 427 + gating 8 + reg2out 3) |

Cross-check: `analysis_coverage.rpt` independently gives 1344 + 131 = 1475.

[MEASURED] **The "signoff STA ran with ZERO parasitics" finding is SUPERSEDED.** The banners differ literally:

| run | banner |
|---|---|
| current `ASIC/sta/reports/timing_summary_hold.rpt` | `# Parasitics Mode: SPEF/RCDB` |
| baseline `ASIC/sta/reports_baseline_20260818_noSPEF/…` (00:30) | `# Parasitics Mode: No SPEF/RCDB` + `ERROR (IMPESI-2016): no coupling capacitance found` |

The manifest agrees: baseline `step.extract_parasitics = FAILED`; current `= ok` with a **322 MB SPEF** on disk.
The RC-free baseline was −0.368 / −60.572 / 462 setup and −0.006 / −0.069 / 79 hold — **loading RC roughly
doubled setup WNS and multiplied hold endpoints ~5.5×.**

**Three caveats that bound the new numbers:**
1. [MEASURED] **Single-corner physics wearing three corner names.** All three RC corners are given the *same*
   best-corner extraction tech file; the log references only the best corner. The setup view resolves to the
   worst corner, so **the setup number was extracted with optimistic RC.**
2. [MEASURED] `step.write_parasitics = FAILED` — only the best-corner SPEF landed; 2,224 nets per corner are
   listed missing.
3. [MEASURED] **`si_analysis = off` in the manifest while the report banner claims `Signoff Settings: SI On`.**
   Contradictory — **do not claim SI closure.** `step.report_analysis_coverage_hold = FAILED`, so **hold
   coverage is unmeasured.**

### 4.6 LEC — the 08-08 broken joint is repaired; a new hole opened at the top

| leg | golden → revised | verdict | when |
|---|---|---|---|
| `syn` [full-20260814] | RTL → `_gate.v` | **NO VERDICT — run died mid-compare** | 08-17 23:25 → 08-18 00:11 |
| `gate` [full-20260814] | `_gate.v` → `_gate_power.v` | **PASS** 61674/61674 | 08-17 23:38 |
| `pnr` [full-20260814] | `_gate_power.v` → `_pnr.v` | **PASS** 61674/61674 | 08-17 18:11 |
| **`pnr` [fp1505]** | full-20260814 `_gate_power.v` → fp1505 `_pnr.v` | **PASS** 61674/61674 | **08-18 11:43** |
| audit-control / audit-mutant | — | PASS / **FAIL by design** (8 non-eq) | 08-17 23:38/23:39 |

[MEASURED] **The middle-file defect is FIXED.** The chain composes over one consistent set —
`_gate_power.v` md5 `1e2eab3f…` is the *same file* on both sides of the joint.

[MEASURED] **Correction to the standing account of the 08-08 legs.** They are confirmed non-composing (sha1
`664d76d7…` vs `431c06a5…`, 370,979 B and 23h31m apart) — **and both computed `RESULT=FAIL`**, not "passed
perfectly about two different middles". Conformal printed `Compare Results: PASS` while the verdict was FAIL.

[MEASURED] ⚠ **The new hole, and the gate is blind to it.** The `syn` leg has **no `verdict.txt`**; its log ends
mid-compare on the 21st sub-compare, and only the *second* half (`fv_map → gate.v`) completed. The CI `lec` gate
— `gate: block`, described as "RTL vs SYNTHESISED netlist equivalence" — `re.search`es for the **first**
`Compare Results:` line, which belongs to the half that is **not** the RTL comparison. Replaying the gate's own
check code against the real log returns **PASS**. **There is no end-to-end RTL→netlist proof, and the blocking
gate reports green.**

[MEASURED] Every real verdict is gitignored (`.gitignore:25 build/`, `:125 ASIC/*/lec_*shadow/`). `git ls-files`
returns 41 LEC-ish files — harness, CI fixtures and `docs/tapeout/13-lec.md`, **none a real verdict**.

### 4.7 ROM at the reticle — MEASURED and PASSING, on the un-logoed stream

[MEASURED] Against `ASIC/eth-chiplet/build/fp1505/outputs/nanosoc_eth_chiplet_pads.gds` (sha256 `12079d69…`,
312,343,330 B) — the recorded stream hash and `mtime_ns` were independently re-measured and reproduce exactly,
so the evidence describes the file on disk today.

| ROM | words compared | differing | verdict |
|---|---|---|---|
| **eth_rom** | 512 | **0** | pass (2026-08-18T11:20:22Z) |
| **cc_rom** | 512 | **0** | pass (2026-08-18T11:21:12Z) |

**Three corrections to the standing story:**
1. [MEASURED] **The verified build is `fp1505`, not `full-20260814`.** No artefact naming full-20260814's stream
   survives. `build/rom_verify/*_gds.*` is a **single mutable slot** — an earlier run was overwritten at 12:20
   today.
2. [MEASURED] ⚠ **The verified file is the un-logoed signoff stream** (`class: signoff, ships: no`).
   `package_submission.sh` ships a **logo-merged** stream. **No `fp1505` logo-merged stream exists, and no ROM
   extraction has ever run against any logo-merged stream on any build.** If submission is made from a
   logo-merged `fp1505`, ROM-at-reticle for the shipping file is **UNMEASURED** — one `make`, ~46 s, no licence.
   The gate already refuses to grade a `*_logo*` filename, so it cannot be silently graded green.
3. [MEASURED] The evidence was produced by the toolkit's extractor (39,225 B), **not** by
   `scripts/ci/rom_gds_bits.py` (2,252 B). **The two differ.**

[MEASURED] **The submission bundle carries zero ROM proof** — the evidence is gitignored and outside `$ASIC_DIR`,
and `package_submission.sh` itself prints `ROM stream verification: NOT COLLECTED`.

[MEASURED] The sim/silicon divergence is confirmed — `eth_ss_bootrom.sv` differs from the ASIC code file in
**172/512 words** — but it is a property of the **simulation slot**, hash-scoped and allow-listed, documented in
`docs/tapeout/44-eth-rom-sim-divergence.md`. `cc_rom` is clean 512/512. **It does not touch the reticle result.**

### 4.8 Antenna — the count is 0, and it is not an antenna signoff

[MEASURED] **[full-20260814]** Calibre antenna summary (exec 2026-08-17 15:39):
`TOTAL DRC RuleChecks Executed: 714` / `TOTAL DRC Results Generated: 0 (0)`. Zero nonzero rulechecks, empty
`BY CELL` section, all 204 `.rep` files 30 bytes (bare header). Not capped.
**[fp1505] — there is no Calibre antenna run at all.**

[MEASURED] **The obvious "deck is dead" theory is refuted, and the zero is still not a pass.** An earlier run on
an 08-10 build reported **1549** results across 48 rulechecks with an identical diffusion population — so the
deck *can* fire. But **all three diffusion layers report population 0**, and the rules that fired are
floating-metal accumulation rules whose ratios are taken against source-drain area. With 424 cell masters
carrying no transistor geometry, **standard-cell gate area — the thing antenna damage actually threatens — is
absent from the stream.** Six antenna runs exist; five report 0 and one reports 1549, **on different builds**.
The 1549→0 move compares two designs, not a controlled experiment.

[MEASURED] Secondary, in-tool: the router's own `check_process_antenna` reports `No Violations Found` for both
builds. That is a **router-level** check, not signoff.

**Status: OPEN.** `ci/signoff.yaml` declares `antenna-signoff` a coverage gap in its own words. Report this as
*"0 in the layers we have, antenna signoff not performed"* — never as an antenna pass.
## 5. RTL, and the flist that actually builds

> The tree carries **many copies of the same source**. 19 separate tidelink checkouts are reachable from
> `/home/dam1n19/SoCLabs`, and 337 files match the FCSM/FCReplayV2 names. **Only the flist says which one
> builds.** Every path below was traced from the flist synthesis actually reads.

### 5.1 The flist chain

[MEASURED] Both flows read the same top file:
`flist/nanosoc_eth_chiplet_asic.flist` — via `ASIC/eth-chiplet/design.mk:144` → `asic-toolkit/mk/flow.mk:377`
(`export ASIC_FLIST`) → `flow/genus/1_synthesis.tcl:480` → `read_flist.tcl:261-266` `read_filelist $ASIC_FLIST`.

[MEASURED] It `-f`-includes **two generated flists**, both **gitignored** (`.gitignore:25 build/`) and therefore
host-only:

| Generator (root `Makefile:431-434`) | Input | Output |
|---|---|---|
| `flist/flatten_soc_flist.py` | `nanosoc-multicore-system/flist/nanosoc_multicore_asic.flist` | `build/chip/flist/soc.flist` (421 lines) |
| `flist/resolve_tidelink_flist.py` | `tidelink/flists/`**`tidelink_top_full_asic_v2.flist`** | `build/chip/flist/tidelink_asic.flist` (192 lines) |

[MEASURED] **V2 is confirmed as the ship config.** The generator names `tidelink_top_full_asic_v2.flist` and
never `tidelink_top_full_asic.flist` — adding RTL to the V1 file changes nothing in the netlist.

[MEASURED] Fully resolved: **599 source lines, 594 unique paths, 0 missing files, 0 unexpanded `${VAR}`.**
Roots: 263 SoC, 138 vendor IP (read-only), 136 `tidelink/deps`, 27 `tidelink/src`, 22
`tidelink/src/rtl/local_overrides`, 9 tidechart, 3 chiplet `src/rtl`, 1 generated pad wrapper.

[MEASURED] `TIDELINK_HOME` is set unconditionally in `set_env.sh:31` to the in-repo submodule, so none of the
other 18 checkouts can leak in — **0 of 599 lines resolve outside it.**

### 5.2 FCSM and FCReplayV2 — what the ASIC build actually takes

Only two directories are authoritative: `tidelink/deps/axi-chiplet-controller/logical/wlink` (23 files) and
`tidelink/src/rtl/local_overrides` (11). The other 273 copies (Vivado-packaged `imp/fpga/**`) and 9 test-local
copies are read by **no** ASIC flist.

23 lines in the resolved shipping list match the two families:

| Taken from `local_overrides` | Taken from `deps` |
|---|---|
| FCReplayV2_1, _3, _5, _12, _13; FCSM_6; (FCReplayAddrSync_18, via the resolver) | FCReplayV2 (base), _2, _4, _6, _7, _8, _9, _10, _11, _14, _15; FCSM_5 |

**[MEASURED] The finding that matters: FCSM, FCSM_1, _2, _3, _4 are taken from `deps/` — and a hardened
override exists for every one of them, unused.**

```
tidelink/flists/tidelink_fpga_v2.flist:304-308          -> src/rtl/local_overrides/WlinkGenericFCSM{,_1,_2,_3,_4}.v
tidelink/flists/tidelink_top_full_asic_v2.flist:315-319 -> deps/axi-chiplet-controller/logical/wlink/WlinkGenericFCSM{,_1,_2,_3,_4}.v
```

The overrides carry the SoC Labs XHB500 FC-node hardening (min-CR/CRACK emit gates, sticky-NACK bring-up
forgive, state-7 NACK watchdog, periodic re-ACK). **Every FPGA build carries them; the shipping ASIC netlist
carries pristine vendor nodes.** This is written into the two flists, not a build accident — the resolver's
`SHADOWED` map touches only `WlinkGenericFCReplayAddrSync_18.v`.

This is the byte-level confirmation of the "ASIC netlist diverges from FPGA-proven" concern. **It is a
deliberate-looking divergence with no recorded decision behind it that I could find.** [UNMEASURED] whether
anyone intended it.

### 5.3 The link-clock divider — in the netlist, inert in silicon

[MEASURED] **In the netlist path: YES.**
`build/chip/flist/tidelink_asic.flist` → `tidelink/src/rtl/tidelink_link_clk_div.sv` (resolved line 581),
from `tidelink_top_full_asic_v2.flist:411`.

[MEASURED] **Driven: NO.** Using the anchored grep — the unanchored one is the documented trap, because the
`DO NOT ADD` guard comment contains the port name (naive `grep -c` → 4; real connections → 1):

```
$ grep -rn '^\s*\.link_clk_div_ratio_i' src/rtl/
src/rtl/nanosoc_eth_chiplet.sv:838:        .link_clk_div_ratio_i (3'd0),
```

The chain: tie-off `3'd0` → `tidelink_top` instantiated without `LINK_RATE_REGS_PRESENT`, which defaults to
`1'b0` (`tidelink_top.sv:258`) → the `g_link_rate_absent` arm elaborates
(`assign link_ratio_sel_w = link_clk_div_ratio_i;`, :2984) → `.ratio_i (link_ratio_sel_w)` (:2872).
**`ratio_i` is a constant.** `tidelink_link_rate_regs` is compiled but sits inside
`if (LINK_RATE_REGS_PRESENT)` and is **never instantiated** — an unreferenced module, not logic.

[MEASURED] `tidelink_link_rate_regs.sv` is in the flist **only because of uncommitted work**: the flist line is
worktree-only and the file itself is untracked in the submodule. **A fresh clone at the pin gets the divider but
not the register bank.**

### 5.4 The pin is clean; the submodule content is not

[MEASURED] `git submodule status` shows tidelink's SHA matching HEAD — but `git -C tidelink status --short`
shows **17 modified tracked files and 7 untracked**, including:

- `src/rtl/tidelink_top.sv` — **+170/−7 lines**
- `flists/tidelink_top_full_asic_v2.flist` — **modified** (the shipping flist itself)
- `src/rtl/tidelink_link_rate_regs.sv` — **untracked**

**A fresh recursive clone at the recorded pin builds a different netlist from what this worktree builds today,
even though the SHA agrees.** My elaboration test in §1.4 used the *pin* and passed; that result says nothing
about the dirty worktree.

### 5.5 Uncommitted chiplet RTL

[MEASURED] `git diff --stat HEAD -- src/rtl/` → `chiplet_d2d_decode.sv +81`, `nanosoc_eth_chiplet.sv +43`.

- **`chiplet_d2d_decode.sv` — a real, uncommitted RTL fix.** Adds five intra-block offset qualifiers and ANDs
  them into the subordinate selects, closing a decode alias where the 64 KB `haddr[19:16]` block select was
  wider than the truncated address each subordinate receives (e.g. `0x2E03_8000` previously landed on the same
  APB register as `0x2E03_0000`). `a_dflt` becomes the complement, so unmapped offsets take the existing
  two-cycle AHB ERROR. **This fix is in no build and on no remote.**
- **`nanosoc_eth_chiplet.sv` — comment-only.** The `.link_clk_div_ratio_i (3'd0)` connection is already at HEAD.

### 5.6 Two duplicate-basename hazards in the resolved list

[MEASURED] `phc_ahb.sv` appears **twice with different content** (`dab40c45…` under
`nanosoc-multicore-system/ptp-hardware-clock-ahb/src/rtl/`, `2de19a4e…` under
`nanosoc-multicore-system/src/rtl/wrappers/`). **Both are compiled.** Which definition wins is a property of the
tool, not the flist — the precise failure mode `resolve_tidelink_flist.py` was written to prevent elsewhere.
This one is **not** handled.

[MEASURED] `cmsdk_ahb_to_sram.v` and `cmsdk_apb_slave_mux.v` are each listed via two different vendor-IP paths
(one through a `latest`-style alias, one through the pinned release). `md5sum` shows both pairs byte-identical
today — benign now, and it stops being benign the moment the alias moves.
## 6. What landed in the last 24 hours

[MEASURED] `git log --since='24 hours ago'` → **120 commits**, all by `dam1n19`, 2026-08-17 18:53 → 2026-08-18 14:26.
Classified by the paths each commit touches (script in §8.3). The class *is* the verdict.

| class | count | meaning |
|---|---:|---|
| **FIX** | 45 | changes design, constraint or flow behaviour |
| **EVIDENCE** | 41 | builds, repairs or proves a gate / fixture / measurement |
| **DOC** | 22 | documentation only |
| **PIN** | 12 | submodule pointer only |

The dominant theme is unmistakable and worth stating plainly: **41 evidence commits and a large share of the 45
fixes are gates being repaired because they could not fail.** That is the healthiest possible use of a day, and
it also means most "green" results older than today should be treated as unproven until re-run.

### FIX — 45

- `98d1d7e` ASIC/checks: catch a floorplan move that shorts VDD to VSS, seconds after the grid instead of hours after the route
- `85d86ce` ASIC/rail: refuse to judge a negative control, instead of failing for its injected fault
- `fbb0e99` ASIC/rom: land the stream-out ROM gate, so a gate:block stage stops naming a target that is absent
- `cd954fd` ASIC/constraints: three comments asserted a value was a library index point
- `b0892e0` asic: generate the design report after every stage
- `a47403d` tidelink: bump the pin onto the link-clock divider, and reconnect the port
- `6959b99` ASIC/hooks: "no query matched" has two causes, and only one of them is a defect
- `c91c5f9` fix(chiplet): the tie-off made HEAD unelaboratable from its own pin — take it off
- `3257f11` ci/signoff: move the DRC gate onto the tree it grades, and prove LVS must not follow
- `7771db3` ASIC/rail: the mean budget's flat distribution is a placement artefact, and the battery could not fail on the mean
- `7c93060` Makefile: point the ASIC entry points at the flow that actually builds this chip
- `621ee96` ASIC/genus-innovus: freeze the four legacy-engine targets, and say what the fallback is not
- `7f7c1be` ASIC: the last four files that spelled a library release, resolved not renamed
- `4326e13` ASIC: the PDK paths named which deck revision this site bought, in a public repo
- `0230bce` ASIC: protect the D2D link-clock mux through synthesis, via the toolkit hooks
- `68fab6f` docs: correct the numbers that were true when written and are not true now
- `e566338` ASIC/sta: the independent hold number is 79, not 7, and it points the other way from setup
- `194a0cb` ASIC/rail: track padconn.py, the pad-to-mesh proof that owes the tool nothing
- `8099410` ASIC/sta: run the first signoff STA this design has ever had, and name what still blocks it
- `db1f4bc` ci: declare the whole ladder in one file, including the checks nobody has run
- `ed6d027` DRC: PO.R.8 is a black-boxing artefact after all, so waive it by cell
- `6308094` fix(chiplet): tie link_clk_div_ratio_i explicitly — clears the only authored lint red
- `56147db` ASIC/eth-chiplet: retire the TCLCMD-917 exemption, because its cause is gone
- `927f853` ASIC/genus-innovus: adopt three stage-script changes left uncommitted since 08-14
- `9d2d79f` ASIC/constraints: bind or die on the divider enables — the guard had the defect it guards against
- `f8df605` ASIC/constraints: stop the pad multicycle selecting power and ground pins
- `c7462a2` ASIC/constraints: pin the link divider's divided leg inert, at the pin that gates it
- `ee93ef6` ASIC/constraints: record why the TX group survives the link-clock divider
- `de8f985` floorplan: warn, at the coordinates, that a macro move can short VDD to VSS
- `b34f55f` ASIC/constraints: C2 - merge the transmit group, it is not asynchronous to clk
- `979f26e` power_plan: the M5 offset mechanism, and two wrong explanations removed
- `4d89253` floorplan: move rf_32k off the placement phase that shorts VDD to VSS
- `7ea8dfc` ASIC/eth-chiplet: consolidate the manifest, and close the ROM write-write race
- `17fbb2a` docs/tapeout: correct two measured-false claims, without publishing a PDK inventory
- `15b0501` ASIC/constraints: the D2D transmit word clocks never resolved their master
- `d6deeb8` rom: wire the toolkit's ROM readback gate to this chip, from the depth already declared
- `2dca8ae` ASIC/qspi: the constrained clock ratio is a register's reset value, not the silicon
- `309a9a5` ASIC/calibre: the wire-bond deck is site configuration, and its pitch option was never set
- `6d46729` ASIC/ROM: emit the content hash every stage manifest reads, instead of a second implementation of it
- `58e53be` submodule: record the flow branch, and why two pointers must not be bumped
- `d1460b3` ASIC/genus-innovus: point the PG probe at a database that has a pad ring
- `6719a54` vendor: redact licence-server disclosure, untrack the broker letter
- `2f75ee2` ASIC/rail: reconnaissance for the first electrical measurement of this design's power delivery
- `664d8f8` route: make multi-cut via effort sweepable, and say what it is suspected of
- `1d9443a` gitignore: the Voltus rail work tree, its stray probe log, and 11 fixtures it was hiding

### EVIDENCE — 41

- `3801144` scripts/ci: resolve the submission bundle from the build tree that holds a stream
- `f0dde6e` ci/fixtures: move the drc and lec-pnr fixtures onto fp1505, so check_proof discriminates again
- `4334525` ci: measure whether a flagged number is the PDK's, instead of judging it by eye
- `79dc32c` ci/signoff: point the ROM-stream and LEC gates at the artefacts that ship
- `cdbca39` verif/lint: two concurrent runs corrupt each other's blackbox stubs
- `a5cdf14` ASIC/rail: measure a voltage, and gate on it
- `7c2433e` verif/lint/full: the HAL report cut two tables off without saying so
- `e9dc36b` ci/signoff: the LEC gate's negative grep was dead code — real transcripts say so
- `652bb20` verif/lint/full: the flist "staleness" guard tested existence, not freshness
- `39cc848` verif/lint: re-land the gen_bbox portless-stub fix, reverted by a stale snapshot
- `26fa211` scripts/ci: restore signoff.py — the previous commit reverted it by accident
- `86e8ebf` ci/signoff: four blocking gates had no proof they could fail — they do now
- `854fb0c` ci/signoff: a coverage gap whose probe FAILS was being read as "still real"
- `cc1bc48` ci/signoff: the `lint` stage never linted the file its description is about
- `65c2c3d` cdc: measure the flow instead of quoting it, and settle where the CRC bug lives
- `8a7ca93` lint: waivers that carry an argument, and a reader that holds them to the design
- `6066354` verif/lint: the blackbox generator could emit a portless stub and exit 0
- `e128c86` verif/lint/full: `set -e` + pipefail made the HAL half unreachable
- `550b80d` verif/lint/full: the harness that proves a gate can fail could not fail itself
- `f1bfc39` verif/lint/full: HAL reported a clean design from a run the wall clock killed
- `24b819d` verif/lint/full: verilator's exit status was printed and then read by nothing
- `82e00d2` verif/lint/full: the ratchet banked a collapsed measurement as an improvement
- `8843536` verif/lint: a pass that never ran was reporting itself clean, twice over
- `3727fce` docs/tapeout: audit every make target ci/signoff.yaml names, and probe HEAD not the disk
- `2e6592b` package_submission: fail closed on an incomplete bundle, and let the logo stream be the one that ships
- `29d7894` ci/fixtures: a real abort DOES emit the tally block — I measured a fixture, not HAL
- `67a157e` scripts/ci: pin bash for stage commands, or PIPESTATUS silently passes
- `5245456` scripts/cdc: match ICGs by enable net too, or the audit under-counts by 56%
- `3a4964c` ci/fixtures: pin the kill guard, and fix the pass fixture it broke
- `c444f10` scripts/ci: ask whether a file reproduces vendor text, not whether it ends in .lef
- `c29eea0` verif: connect the gates that could not fail, and correct the record
- `2831176` verif/lint: tier by the path Verilator actually prints, and keep the evidence
- `bcde995` cdc: the chiplet gets a CDC setup for the first time, and a measured baseline
- `08a4b35` ci/signoff: assert the HAL run FINISHED, not merely that it started
- `9b1b0ce` verif/elab-strict: a killed run is a failure, not zero multiple-driver nets
- `0061066` rom: read the boot-ROM bits out of the streamed GDS, and find that they are wrong
- `6bb12f1` scripts/rig: the TL-042 v2 NO-HARM harness, and the D2D session handback
- `6bf261a` cdc: the chiplet's own SpyGlass setup, and two checks that keep a waiver honest
- `d77ce84` verif/cdc: a stage that was green by construction, over a report that hid 7300 findings
- `d2f08d0` drc: waive what the back-end decision makes permanent, and account for all 837
- `a01904c` ci/fixtures: the evidence that proves a signoff check can actually fail

### DOC — 22

- `d828785` docs/tapeout: mark 25 and 26 stale, and point at the sources that cannot rot
- `15c58a9` docs/tapeout: record the repaired migration branch, and why each conflict went the way it did
- `735d04a` docs: write site locations as variables, not as an inventory of the licensed PDK
- `c7b9c1e` docs/tapeout: renumber the fp1505 DRC page to 43 — a concurrent session took 42
- `9c11365` ASIC/rail: the 330 unpowered instances are stranded row islands, not an extraction artefact
- `6d2d957` DRC: the fp1505 number, uncapped — 837 raw / 146 waived, and DRC cannot see what fp1505 fixes
- `567bee4` LVS: the flow works, and in one of its two configurations it cannot fail
- `4c9b14d` docs/tapeout: asic-flows is already not the engine, so retiring it is project-side
- `43167ce` docs/tapeout/32: record the redaction's acceptance test, not just that it happened
- `ac74bae` docs/tapeout/38: fix the check in this document, which had this document's bug
- `c2c7a52` docs/tapeout/38: two more ways to measure the wrong thing, both from tonight
- `1e88115` docs/tapeout/38: a submodule pin check that compares SHAs is blind
- `7415463` docs: antenna is a null result, not a clean one - and say why
- `1ec7896` docs: the genus-innovus retirement is gated on a lab-shared submodule
- `203a608` docs: record why the asic-toolkit migration is parked, and the traps that hid it
- `71dbe59` docs/tapeout: the toolkit's legacy pointers are a shared submodule's contract
- `914bd8e` docs/tapeout: restore 35-drc-layer-map-blindness, which my previous commit deleted
- `1e55ac7` docs/tapeout: split_row PG anchoring — one mechanism, five macros, and no gate
- `aa1314b` docs/tapeout: the DRC gate can only see layers the deck maps a rule to
- `d1812af` docs/tapeout/32: the rail-short defect, with both of my wrong versions kept
- `a3233b3` docs/tapeout: the two content gates for gate1, ready to run
- `c596542` docs/tapeout/24: name the mitigation Genus actually has, and the real ICG count

### PIN — 12

- `17385f8` submodule: roll the toolkit onto the pin whose vendor gate can tell the two apart
- `dc315bd` submodule: bump asic-toolkit 508b189 -> 5094a84, so help-all finds design-report
- `8ad9f3b` submodule: bump asic-toolkit 381236c -> 531c4f2, so `ident` charges a revision
- `c150cdd` submodule: bump asic-toolkit 9528348 -> 381236c, the pre-push scoping fix
- `2da3240` submodule: bump tidelink e21e274 -> 2c2f8d4, onto live origin/main, with no RTL in it
- `514003a` submodule: roll the toolkit onto the pin whose gates were proved in both directions
- `3fba15a` submodule: restore the asic-toolkit pointer my previous commit reverted
- `7b9de15` submodule: re-apply the toolkit pin bump, reverted by a stale snapshot
- `d8ee889` submodule: roll the toolkit onto the pin that carries the ladder and the pin check
- `ee20607` submodule: roll the toolkit onto a pin that a clone can actually resolve
- `31c6af1` submodule: bump asic-flows fc7636d -> c2a46ee, now that the commit exists on its remote
- `e4cd30b` submodule: bump asic-toolkit 9feeca9 -> 24b1939 (ROM gate, LEC rules, CTS fix)

## 7. Documented claims that are now false

Named, with the document and the measurement that falsifies each.

### 7.1 `docs/tapeout/00-index.md:17` — the vendor guard's path and trigger

> Claim: "`ci/check-vendor-collateral.sh` enforces this on every commit and every push."

[MEASURED] **Both halves are wrong for this repository.**
- `ls ci/check-vendor-collateral.sh` → **No such file.** That path exists only inside the `ASIC/asic-toolkit`
  and `nanosoc-multicore-system` submodules. This repo's guard is `scripts/ci/check_no_vendor_collateral.sh`.
- `ls .git/hooks/ | grep -v '\.sample$'` → **empty. No local hook enforces anything at commit time.**
- Real enforcement is `.github/workflows/vendor-guard.yml`, whose own header says it runs "on every push and
  every pull request" — i.e. **at push time on GitHub, never locally.**

Consequence: a commit containing vendor collateral meets no resistance locally. The index tells a reader they
are protected one step earlier than they are — on a page whose whole subject is not publishing licensed
collateral.

### 7.2 "No Tempus or PrimeTime installed" — `ci/signoff.yaml`, gap `sta-signoff`

[MEASURED] **False.** `ASIC/sta/reports/timing_summary.rpt` (2026-08-18 13:05) begins
`# Generated by: Cadence Tempus 21.11-s131_1`. Tempus is installed and ran a real analysis today. The gap's
`refuted_by` probe (`command -v tempus`) tests PATH visibility in a bare shell and cannot see it. Detail and
the correct residual framing in §3.7.

### 7.3 "Signoff STA ran with ZERO parasitics"

[MEASURED] **Superseded today.** The current run reports `# Parasitics Mode: SPEF/RCDB` with a 322 MB SPEF on
disk and `step.extract_parasitics = ok`; the RC-free run is preserved alongside as an explicit baseline
directory. Quantus succeeded. **But** the extraction is single-corner physics wearing three corner names, so
the setup number is optimistic — §4.5.

### 7.4 "The LEC chain joint is broken" (the 08-08 vintage)

[MEASURED] **Repaired for the current chain** — `_gate_power.v` md5 `1e2eab3f…` is the same file on both sides
of the joint, and `gate.v`/`gate_power.v` are same-run, same-minute, same module count.
[MEASURED] **And the old account needs a correction of its own:** both 08-08 legs computed `RESULT=FAIL`, not
"passed perfectly about two different middles". Conformal printed `Compare Results: PASS` while the verdict was
FAIL. **A new and different hole has opened at the top of the chain — §3.5.**

### 7.5 "The shipping GDS is `full-20260814`"

[MEASURED] **Superseded today.** `ci/signoff.yaml:468-470` records the promotion of `fp1505`, and the DRC,
ROM-in-GDS and rail gates now name it. **But the move is not consummated:** the netlist and STA under signoff
are still `full-20260814`'s, fp1505's route never completed (§2.4), and the rom-gds gate itself still prints
`ROM_GDS_SHIPS=no`.

### 7.6 "The boot ROMs are verified at the reticle in `full-20260814`"

[MEASURED] **The verified build is now `fp1505`** — no artefact naming full-20260814's stream survives, and
`build/rom_verify/*_gds.*` is a **single mutable slot** that was overwritten at 12:20 today. The result itself
is good (512/512, 0 differing, both ROMs) — but it is against the **un-logoed** stream, and **no logo-merged
stream has ever had its ROMs extracted** (§4.7).

### 7.7 `docs/tapeout/25` and `26`

[MEASURED] Both were marked **STALE** today by `d828785` and now carry banners pointing at live sources.
**They are correctly labelled** — noted only so a reader does not re-derive the staleness.
## 8. Method, and what I could not measure

### 8.1 Which tree level each number came from

Five levels disagree in this repo routinely. Every claim above names one:

| level | how it was read | used for |
|---|---|---|
| **live remote** | `git ls-remote`, and `merge-base --is-ancestor` after `fetch --prune` | branch tip, all five pin reachability |
| **HEAD** | `git ls-tree -r HEAD`, `git show HEAD:<path>` | recorded pins, RTL under test, doc claims |
| **index** | `git ls-files -s`, `git write-tree` + diff | the stale-entry audit in §1.3 |
| **worktree** | `ls`, `md5sum`, `grep` on files | build artefacts, reports, dirty submodule content |
| **pristine reconstruction** | `git archive HEAD` + `git -C <sub> archive <pin>` into a clean dir | the §1.4 elaboration test |

The elaboration test deliberately used the **pristine reconstruction**, not the worktree, because the worktree's
tidelink submodule is dirty (§5.4) and would have answered a different question.

### 8.2 Controls carried

A result with no control is not a measurement here. Three were carried:

1. **§1.4 elaboration** — the same Verilator command against the *previous* tidelink pin `2c2f8d4` fails with
   `Pin not found: 'link_clk_div_ratio_i'`. The green discriminates.
2. **§2.4 fp1505 route crash** — `full-20260814` was checked for the same two artefacts and **has** both, so the
   absence on fp1505 is a real difference, not a path mistake.
3. **§2.3 stream identity** — both GDS files were hashed independently of the build inventory; the hashes agree.

### 8.3 Reproducing the commit classification in §6

```sh
git log --since='24 hours ago' --pretty='%h%x01%s' | while IFS=$'\x01' read h s; do
  paths=$(git show --name-only --pretty= "$h")
  # PIN  = only submodule gitlinks;  DOC = only docs/
  # FIX  = touches src/rtl, ASIC constraints/scripts/eth-chiplet/rom/sta/rail, or a Makefile
  # EVIDENCE = otherwise touches ci/, verif/ or scripts/
done
```

### 8.4 What I did NOT measure, recorded as unknown

An unmeasured item recorded as unknown is worth more than an inherited one recorded as fact. These are unknown:

- **[UNMEASURED] Full-hierarchy elaboration from a pristine clone.** §1.4 proves the wrapper-to-submodule port
  contract only. A real one needs the SoC generator run and the vendor IP trees, plus a seat I was asked not to
  take.
- **[UNMEASURED] Whether the FCSM `deps`-vs-`local_overrides` divergence (§5.2) was intended.** The flists state
  it unambiguously; I found no decision record either way.
- **[UNMEASURED] Whether re-running fp1505's route on the pinned toolkit actually completes.** The Tcl fix is
  present at the pin (§2.4) and the failure mode is fully explained, but I did not launch Innovus to confirm —
  two synthesis seats were already held.
- **[UNMEASURED] Anything requiring Genus, Innovus, Voltus, Calibre, Quantus or Conformal to be launched.** All
  physical numbers in §4 come from reports already on disk. Where no report exists, §4 says so rather than
  inferring.
- **[UNMEASURED] The two live builds.** `gate1` and `resyn-20260818` were synthesising while this was written;
  their outputs did not exist yet and any statement about them would be stale on arrival.

### 8.5 Standing hazards for the next session

1. **The index is armed** (§1.3). Use a private `GIT_INDEX_FILE`; never `git add -A`; verify with
   `git diff --name-status <parent> <sha>` *after* committing.
2. **Six commits are unpushed** and `origin/main` is 11 days stale (§1.1).
3. **Two synthesis seats are held** (§2.2).
4. **Four of five submodule pins are bare feature-branch tips** (§1.2) — one branch delete makes this chip
   unclonable.
5. **An uncommitted RTL fix sits in `chiplet_d2d_decode.sv`** (§5.5), in no build and on no remote.
