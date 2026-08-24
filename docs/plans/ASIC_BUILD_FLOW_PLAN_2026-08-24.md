# ASIC build flow — design and implementation plan

**Date:** 2026-08-24 · **Status:** plan; implementation not started · **Owner:** toolkit + project

Goal: one command produces a complete, reproducible, self-describing ASIC build — lint through
GDS, with every stage's evidence, provenance and verdict collated into a machine record, and the
publishable artifacts pushed to Artifactory.

Everything marked MEASURED was established on this tree on 2026-08-23/24.

---

## 0. The finding that shapes the whole plan

**Almost nothing here needs building. Three of the four subsystems already exist and are
unwired.** MEASURED:

| Subsystem | State |
|---|---|
| **Stage orchestration** | `ci-pipeline.conf` + `ASIC/asic-toolkit/ci/pipeline.sh` — full DAG with `after` edges, `--only`/`--from`/`--resume`, dependency-aware skipping that emits UNVERIFIED rather than silently passing. **Points at the retired `genus-innovus` paths.** |
| **Hook seams** | `flow_hook` in `flow/common/flow_utils.tcl:302` — 10 named seams, optional, announced, abort-capable, and **recorded into `::flow(hooks)` so they land in the manifest**. Project uses 4 of 10. |
| **Per-stage provenance** | `flow/common/provenance.tcl` → `reports/<stage>_{manifest,provenance}.txt`, schema 1, with the `UNVERIFIED:<reason>` convention. Runs on every run. |
| **Artifact store** | Artifactory 7.161.11 on mapstone-dev, rootless podman + PostgreSQL 16. Live. |

So this plan is mostly **repair and connect**, not build. The genuinely new code is the build-record
collator and the publish client.

---

## 1. The 10 hook seams (the plug-in contract)

MEASURED from `grep -rn 'flow_hook ' ASIC/asic-toolkit/flow/`:

| Stage | Seams |
|---|---|
| synthesis | `pre_synth` :933 · `post_synth` :1015 |
| place | `pre_floorplan` :805 · `post_powerplan` :879 · `pre_place` :1297 · `post_place` :1332 |
| cts | `pre_cts` :996 · `post_cts` :1328 |
| route | `pre_route` :820 · `post_route` :1735 |

Contract, from `flow_utils.tcl:268-283`: **optional** (absent is not an error), **announced**
(prints path + runtime), **able to abort** (an error stops the stage deliberately — wrap advisory
work in your own `catch`), **recorded** (`::flow(hooks)` → manifest).

Project hooks live in `$(ASIC_DIR)/hooks` (`flow.mk:246` → `ASIC/eth-chiplet/hooks/`). Four exist
today: `pre_synth`, `post_synth`, `post_powerplan`, `post_route`.

**Design rule: the toolkit provides the machinery; the project supplies policy via hooks.** A hook
must never contain logic another chiplet would also need — that belongs in the toolkit.

---

## 2. Where the code goes

### Toolkit (`ASIC/asic-toolkit/`) — generic, chiplet-agnostic

```
flow/common/record.tcl          NEW  flow_record_artifact, flow_record_stage
scripts/asic-flow-collate       NEW  per-stage JSON -> collated build record
scripts/asic-flow-publish       NEW  compress + PUT to Artifactory + verify digest
scripts/asic-flow-gdshash       NEW  raw sha256 + normalised layout hash
ci/pipeline.sh                  FIX  (paths only, see §5)
flow/common/provenance.tcl      EXTEND  schema 1 -> 2 (see §4)
```

### Project (`ASIC/eth-chiplet/hooks/`) — policy only

```
post_synth.tcl      EXISTS  + record the netlist artifact
post_route.tcl      EXISTS  + record the stream, hash it, publish
post_place.tcl      NEW     record placement QoR
post_cts.tcl        NEW     record clock QoR
```

---

## 3. The run directory

One structural change matters more than the rest. MEASURED: `signoff.yaml` declares four in-build
evidence paths and **three of the four exist in no build directory at all** — DRC lives in
`ASIC/genus-innovus/calibre_runs/` (51 hand-named dirs), ERC in `erc_runs/`, IR-drop in
`rail/work/`, STA in `ASIC/sta/`, GLS in `build/gls-netlist/`. All *outside* every build.

That is the mechanism behind the "verdict read the wrong stream" class. Fix: a `signoff/`
directory **inside** the run.

```
build/<run-tag>/
  config/          FROZEN COPY of scripts+inputs (cp -a, ~1.65 MB) -- NOT a symlink
  outputs/         netlists, SDC, SDF, the stream
  reports/         tool-native reports (unchanged -- 23 signoff.yaml globs depend on this)
  signoff/         NEW: drc/ lvs/ erc/ antenna/ ir-drop/ sta/ gls/ -- evidence inside the run
  record/          NEW: stages/NN-<id>.json, build.json, artifacts/<name>.prov.json
  publish/         NEW: hardlinks of what goes to Artifactory (saves 302 MB/publish)
  logs/  work/  romlibs/
```

`config/` replacing the symlink is the single highest-leverage change in this document. MEASURED:
`scripts/` and `inputs/` are symlinks into the live shared tree in **23 of 27** run dirs, one
pointing into another session's scratchpad. That is why the toolkit SHA can move *within* one run
(`gdsrun-20260822-allfix`: 3 project + 3 toolkit commits across its 3 stages).

---

## 4. Provenance schema 2

Keep everything in schema 1 — especially `UNVERIFIED:<reason>` — and add:

```
prov.schema                              2
prov.gds.sha256                          <raw bytes>
prov.gds.layout_sha256                   UNVERIFIED:gds-canonical-not-implemented
prov.gds.bytes                           308602016
prov.sdc.sourced.<n>.{path,sha256}       every SOURCED sdc, not just the top
prov.flist.generated.<n>.{path,sha256}   every -f included flist
prov.design.git_sha_at_read              <captured at INPUT-READ time>
```

Four defects this closes, all MEASURED:

1. **Nothing hashes the shipping GDS.** `route_manifest.txt` records `gds_bytes` — a *size*.
   `grep gds_sha256` over the provenance writer returns nothing.
2. **Sourced SDCs are never fingerprinted.** `docs/bscan/RUN_INPUT_DIFF.md` §7 documents a case
   where `bscan_constraints.sdc` changed the netlist structure and was invisible to the manifest.
3. **Generated flists are unhashed.** The recorded flist hash covers only the top file; the
   `-f`-included generated ones are regenerated before every synth.
4. **`git_sha` is captured at run END.** In the documented case the recorded SHA was timestamped
   80 minutes *after* that run read its RTL.

Two hashes, always, because a GDS embeds its write wall-clock in `BGNLIB` and all 2,573 `BGNSTR`
records: the raw digest answers *"is this the file I shipped"*, the normalised one answers
*"is this the same layout"*. `layout_sha256` does not exist yet and must ship as UNVERIFIED until
it does — never as a silent omission.

---

## 5. Repairing the pipeline DAG

`ci-pipeline.conf` has the structure and the wrong paths. MEASURED defects:

| Stage | Defect |
|---|---|
| `drc`, `rom-gds`, `lec-pnr` | name `ASIC/genus-innovus/outputs/nanosoc_eth_chiplet_pads.gds` — **does not exist** (only `*_logo.gds` variants do) |
| `erc` | needs `@ROOT@/scripts/erc/run_erc.sh` — **`scripts/erc/` does not exist**; the real runner is `ASIC/genus-innovus/scripts/calibre/run_erc.sh` |
| `metal-fill` | passes `EVR_METAL_FILL=1`, the **legacy** knob; the toolkit's is `ROUTE_METAL_FILL`. Silent no-op reporting success |
| `sta-signoff`, `ir-drop` | **no `run` command at all** |

Roughly 20 lines. Also: `make asic-pipeline` always runs in `build/default`, a shared mutable
directory on a box with concurrent sessions — it must take a run tag.

---

## 6. Two one-line fixes worth doing first

1. **`syn` is the only stage without `< /dev/null`** (`flow.mk:456`). Place, CTS and route all
   have it, and the file carries a comment explaining why. So the **1 h 40 m stage is the one that
   can park at a Genus prompt holding a licence seat overnight**.
2. **`.gitignore` protects `ASIC/submissions/` only one level deep.**
   `ASIC/submissions/<subdir>/foo.gds` matches no rule, and
   `padring_as_built_rzG_20260823/` is already uncovered. In a **public** repo.

---

## 7. Git strategy — an orphan ref, not a branch directory

The obvious design (`docs/runs/*.json` on the working branch) was TESTED in a throwaway repo and
**fails here**: plumbing with a private index correctly avoided absorbing 69 foreign staged paths,
but left the record staged as a *deletion* in the shared index, and the next concurrent bare
`git commit` silently deleted it. With 22 worktrees and a permanently-armed index that is the
expected case, not a race.

Use an orphan ref — `refs/build-records/eth-chiplet` — that no worktree checks out. Verified:
foreign work untouched, no phantom deletion, records survive a concurrent commit, disjoint
history. `git diff <ref>~1 <ref>` is the changelog. Build commits with
`hash-object`/`update-index`/`commit-tree` + a compare-and-swap `update-ref`.

Two gotchas recorded during the test: `mktemp -u` (git rejects a zero-byte index file), and
**plumbing bypasses hooks** — so the recipe must re-implement the vendor guard itself and must
never touch `VENDOR_CHECK_BYPASS`.

Only `record/` is committed (~365 KB raw, ~60 KB in git). **Push is off by default**: the
superproject is public, and whether build telemetry should be world-readable is the owner's call.

---

## 8. Artifactory layout

Five repos, because retention and permissions are only settable per repo:

```
asic-gds-release/     keep forever, admin-write     foundry submissions
asic-gds-candidate/   90 days,      CI-write        gdsrun-* candidates
asic-netlists/        180 days                      gate.v, pnr.v, SDF, SDC
asic-reports/         2 years                       the small, high-value JSON
asic-logs/            30 days                       raw tool stdout
```

Run tag sits **above** stage, so one build is one contiguous subtree — browsable in the GUI and
deletable in one call. Store `zstd -19` (290 MB -> ~22 MB, MEASURED 13.1x). Carry `RAW.sha256`
beside every stream.

**Open decision — OSS vs JCR.** Artifactory OSS has **no properties and no AQL** (feature matrix:
*"Search …, AQL, searchable properties — JCR only (not available in OSS or CE)"*), and `?list&deep=1`
is Pro. So under OSS, **path convention is the only index**. JFrog Container Registry is also free,
also self-hosted, also supports Generic repos, and *does* have properties + AQL — but it is a free
JFrog EULA, not AGPL. This decision changes the layout and must be settled before the repos are built.

**Retention is external in either case.** OSS has no cleanup policies (Enterprise X/+), and generic
local repos have no TTL field in any tier. A nightly cron deletes `asic-gds-candidate/**` subtrees
older than 90 days, and must never be pointed at `asic-gds-release` — enforce with repo permissions,
not with care.

---

## 9. Triggering — Artifactory cannot, GitHub already can

**Artifactory cannot trigger builds.** Webhooks, Groovy plugins and Workers are all Pro X or above;
the Event service runs but its only surface is the Webhooks API. JFrog publishes the exact recipe
("Trigger a GitHub Action using a Custom Webhook") and it requires Pro X. Email is OSS's only
outbound channel.

Invert the arrow: **CI triggers the build and pushes to Artifactory.** All five workflows in this
repo are already `workflow_dispatch` (MEASURED), and `asic-gds.yml` takes `runner`, `from_stage`
and `clean` inputs — GitHub's UI gives a literal button.

**Blocker: no GitHub Actions runner is installed on srv03335.** No runner directory, no
`Runner.Listener` process. Every `runs-on: [self-hosted, …]` job would queue forever. The
`gitlab-runner` that *is* running belongs to `dwn1c21`.

Also: `asic-gds.yml` sets `ASIC_DIR: ASIC/genus-innovus` — **the CI GDS workflow drives the retired
flow**, while the shipping GDS is built by hand through `ASIC/eth-chiplet`.

**Long stages must not run inside a CI job.** Launch detached under `setsid` and poll
`flow_state.json`; cancelling the workflow then does not kill a 4-hour route.

---

## 10. Measured runtimes — budget the flow against these, not the docs

| Stage | Wall | Note |
|---|---|---|
| synthesis | 90–110 min | n=9 |
| place | 40–70 min | n=16 |
| CTS | 47–76 min | n=16 |
| route (incl. fill + stream) | 46–80 min | n=14 |
| **syn -> route** | **4.2–4.7 h** | |
| logo merge | **~23 min** | INFERRED from mtimes — **writes no timer**, should get one |
| `write_stream` | **12 s** | for 308 MB |
| Calibre DRC | **5 min** | *not* 25 — 1386 is CPU, 315 is REAL |
| Calibre antenna | **23 min** | *not* 75 — 4495 is CPU, 1401 is REAL |
| LEC RTL<->synth | **82 min** | the long pole in LEC |
| LEC synth<->P&R | 6.5 min | |
| signoff STA (Tempus) | 6 min | |
| IR drop | 7 min | |
| elab-strict | 44 min | longest RTL gate |

`docs/asic/TOOLKIT_GUIDE.md` quotes place ~20 min and route 2–3.5 h. Both are wrong in opposite
directions. Use the manifests.

---

## 11. Gaps that must be represented, never dropped

Every one of these gets a stage slot with `status: not_run` and a `refuted_by` probe, so a reader
can never mistake "not run" for "passed":

- **SPICE bootrom** — ABSENT. No `.sp`/`.spi`/`.cir`/`.scs` anywhere. But every ingredient exists:
  `eth_rom_via.cdl` + `rom_via.cdl` (1.5 MB each, real transistors, **programmed with the actual
  firmware**), BSIM4 models for 5 PTV corners, and **Spectre_XPS with 41 free licences**. A harness
  job, not procurement. Caveat: `VDDE`/`VSSE` with body-bias `VNW`/`VPW` and power-gating — a deck
  must tie the wells and drive the gating control or the array will not read.
- **`run_ant.sh`** — referenced by a tracked Calibre deck (`ant.rules:4`), **does not exist**.
- **Metal fill** — implemented but `ROUTE_METAL_FILL` defaults 0. **No shipped stream has been
  filled.**
- **`sta-signoff`** — declared *"No Tempus or PrimeTime installed"*. **False.** Tempus is at
    installed and resolved via `$TEMPUS_BIN` in `ASIC/sta/site.env`; a full signoff STA has already run
  (346,456 instances, real Quantus extraction, `sta_wall_seconds = 341`). The probe is
  `command -v tempus`, which fails only because it is not on the default PATH. The true gap is
  *unwired, with two broken legs* (`step.write_parasitics = FAILED`, `si_analysis = off`).
- **Structurally unreachable on this site** (do not plan work): full-chip LVS, foundry antenna over
  real cell geometry, base-layer/density DRC, dynamic IR drop. One root cause — the PDK ships
  Front-End packages only. Consequence: **every geometry number this project produces is a floor,
  not a total.**

---

## 12. Implementation order

**P0 — one-liners, no design risk**
1. `< /dev/null` on `syn`
2. recursive `.gitignore` globs for `ASIC/submissions/`
3. push toolkit `3ca1160` (or resolve the branch divergence — see below)

**P1 — the record (toolkit)**
4. `flow/common/record.tcl`: `flow_record_artifact`, `flow_record_stage`
5. `scripts/asic-flow-gdshash`: raw + normalised
6. provenance schema 2
7. project hooks call into them

**P2 — the run directory**
8. `config/` frozen copy replacing the symlink
9. `signoff/` inside the run
10. `scripts/asic-flow-collate` -> `record/build.json`

**P3 — orchestration**
11. repair `ci-pipeline.conf` paths; add a run tag
12. install a GitHub Actions runner
13. repoint `asic-gds.yml` at `ASIC/eth-chiplet`

**P4 — publish**
14. `scripts/asic-flow-publish`; create the five repos; nightly retention cron

---

## 13. Open decisions

1. **Toolkit branch.** Checked out `fix/tcl-parse-gate-both-directions` @ `3ca1160` — off-remote,
   dirty, 23 behind / 13 ahead of `origin/main`, while the superproject pins `65d3320`. Three
   different states. New work must not be built on a branch that exists nowhere but this disk.
2. **OSS vs JCR** (§8) — changes the repo layout and whether the index is queryable.
3. **Push build records?** The superproject is public.
