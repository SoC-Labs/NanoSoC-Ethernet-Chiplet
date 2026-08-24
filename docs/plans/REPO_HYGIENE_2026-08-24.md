# Repo hygiene plan — 2026-08-24

**Status:** DRAFT for owner review. Nothing in this plan has been executed.
Every command below is for the OWNER to run. This session was read-only.

**Measured:** 2026-08-24 20:30–22:10 on `feat/padring-boundary-scan`,
superproject HEAD `38da410`. Several peer sessions were mutating the tree
throughout, so `git status` drifted DURING the audit — items marked
**[VOLATILE]** must be re-checked immediately before acting.

**Method note.** Every claim below is labelled MEASURED (I ran the command and
quote its output) or INFERRED. Two widely-repeated beliefs about this repo were
tested and **refuted** — see "Corrections" at the foot. Do not act on the old
versions of those beliefs.

---

## LATE UPDATE — 22:05, DURING this audit. Read this first.

**A peer session pushed while I was measuring.** This changes the top of the
plan. Re-measured and verified against the live remote at 22:03:

| | at 20:40 | at 22:03 |
|---|---|---|
| superproject HEAD | `38da410` | `25e7606` |
| `origin/feat/padring-boundary-scan` | `23f8cdb` | **`38da410`** |
| commits unpushed on this branch | 6 | **1** (`25e7606`) |
| toolkit pin | `2e0cda6` | `2e0cda6` (unchanged) |
| is `2e0cda6` on the toolkit remote? | NO | **STILL NO** |

**Consequence — this is the headline finding of the whole audit:**

```
$ git ls-tree 38da410 ASIC/asic-toolkit      # 38da410 is now the PUBLISHED tip
160000 commit 2e0cda6d1588831594043b03058bad9542845baf   ASIC/asic-toolkit
```

The superproject commit that pins the toolkit to an unpublished commit **is now
on origin**. So the broken pin is no longer a local hazard that a push would
create — **it is published, and `git clone --recursive` of this project from
GitHub fails right now, for everybody.**

P0-2 (push the superproject) is therefore largely DONE and was done by someone
else. **P0-1 (push the toolkit branch) is now the single most urgent item in
this document, and it is one command.** It repairs the published state:

```bash
git -C ASIC/asic-toolkit push origin fix/tcl-parse-gate-both-directions
```

Nothing blocks it: the toolkit repository has **no pre-push hook** (measured).
Until it runs, the public remote is in a state no one can clone.

**This is also a live demonstration of the tree's volatility** — every
**[VOLATILE]** marker below should be taken literally. Re-measure before acting.


---

## P0 — COULD LOSE WORK. Do these first.

### P0-1. [ESCALATED 22:05 — the broken pin is now PUBLISHED] The toolkit pin does not resolve on its remote → a fresh recursive clone FAILS
**MEASURED.** Of 43 submodules (recursive), exactly **one** pin is unreachable:

| | |
|---|---|
| Submodule | `ASIC/asic-toolkit` |
| Pinned by superproject HEAD | `2e0cda6d1588831594043b03058bad9542845baf` |
| On the live remote? | **NO** — re-checked 21:55, still absent |
| Live remote tips | `cadbd3b` (fix/tcl-parse-gate-both-directions), `573fdd0`, `56f8749` (main) |
| Gap | pin is **exactly 1 commit** ahead of `cadbd3b`, which IS published |
| That commit | `2e0cda6 scripts: publish a stream and bind a foundry return, both by checksum` (dam1n19, 19:55 today) |

The superproject's HEAD commit `38da410` ("artifact flow: publish, bind foundry
returns, and stop leaking streams") moved the pin onto a toolkit commit that was
never pushed. This is the exact trap the project has hit before: the pin is
correct on this disk and unresolvable everywhere else.

**Note the correction to a claim in circulation:** toolkit commits `9a982be`,
`3a8c30a` and `cadbd3b` ARE published — verified individually. Only `2e0cda6`,
the one actually pinned, is not. "The toolkit commits are pushed" is true of
three of the four and false of the one that matters.

**Fix (one command, no guard in the way — the toolkit has NO pre-push hook; MEASURED):**
```bash
git -C ASIC/asic-toolkit push origin fix/tcl-parse-gate-both-directions
```
**Risk of doing it:** very low. It fast-forwards a branch by one commit.
**Risk of NOT doing it:** a fresh `git clone --recursive` of this project fails
outright, and every downstream consumer pinning this superproject inherits the
failure. The chip cannot be rebuilt from source by anyone but this host.
**Owner action:** none needed from other sessions — but see P0-2, do them together.

---

### P0-2. [SUPERSEDED 22:05 — a peer pushed these; see LATE UPDATE] Superproject commits unpushed — and the pre-push hook does NOT block them
**MEASURED, and this refutes the standing belief.** I ran the hook read-only,
feeding it the real ref line, without pushing:

```
printf 'refs/heads/feat/padring-boundary-scan <local> refs/heads/... <remote>\n' \
  | ASIC/asic-toolkit/hooks/pre-push origin <url>
```

**Hook exit status: 0.** Its own words:

> `backlog  143 pre-existing finding(s) in the tree being pushed - already on origin, NOT charged to this push.`
> `They are still published. Nothing here refuses them and nothing here fixes them`
>
> `warning  untracked, non-ignored files match - this push does NOT publish them,`
> `and one git add -A would. This is a warning, not a refusal`

The hook was deliberately narrowed on 2026-08-18 from "is this repo clean?" to
"does this push make it WORSE?". Its header documents the reasoning: the old
behaviour was unpassable and was being spent through `VENDOR_CHECK_BYPASS`.
**The "58 commits refused by a vendor hook" memory is STALE.** Today's work is
off-machine-able right now.

What is unpushed: **6 commits** on `feat/padring-boundary-scan`
(`origin/...` is at `23f8cdb`), including `8040bf5`, `828d53c`, `14ac4c5`,
`baede37`, `38da410`. Across all local branches, 18 commits are on no remote.

**Fix:**
```bash
# do P0-1 FIRST, so the pin resolves once the superproject lands
git -C ASIC/asic-toolkit push origin fix/tcl-parse-gate-both-directions
git push origin feat/padring-boundary-scan
```
**Risk of doing it:** low. The hook passes. Push the BRANCH, not `--all`, and do
not use `--no-verify`.
**Risk of NOT doing it:** today's tapeout work — the pinfix candidate, the
stream-level macro pin gate, the artifact flow — exists on one disk.

**[VOLATILE]** Re-run the ahead-count before pushing; peers commit continuously.

---

### P0-3. Six tags are local-only, including the archival provenance tags
**MEASURED.** Remote has 2 tags; local has 8. Unpushed:

```
archive/baseline-gds-provenance-a497249
gdsrun-20260819
pgfix-island-feed-20260818
pre-asic-flow-migration
rescue/asic-migration-caller-rewire
rescue/asic-migration-legacy-symlinks
```

Two are named `rescue/` and one `archive/` — i.e. they exist precisely to
survive. They do not currently survive anything.

**Fix (after P0-2, and one at a time so a single rejection is legible):**
```bash
for t in archive/baseline-gds-provenance-a497249 gdsrun-20260819 \
         pgfix-island-feed-20260818 pre-asic-flow-migration \
         rescue/asic-migration-caller-rewire rescue/asic-migration-legacy-symlinks; do
  git push origin "refs/tags/$t"
done
```
**Risk of doing it:** low; tags are immutable additions. Confirm each tag's
commit is itself pushed first, or the push carries its whole history.
**Risk of NOT doing it:** the named recovery points for the ASIC-flow migration
are unrecoverable off this host.

---

### P0-4. The submission candidate is NOT backed up anywhere off this host
**MEASURED, md5-bound.**

| Artefact | md5 | Size |
|---|---|---|
| `ASIC/submissions/nanosoc_eth_chiplet_pads_DRYRUN_20260824_pinfix.gds` | `3215cbe15fa373b4112fb6631b2c660d` | 302,611,140 B |
| `ASIC/eth-chiplet/build/pinfix-20260824/logo_orig/nanosoc_eth_chiplet_pads_logo.gds` | `3215cbe1…` **identical** | 302,611,140 B |

Both copies are on this one filesystem, and both are gitignored
(`ASIC/submissions/**/*.gds`, and `build/` swallows the build tree).

**Artifactory IS live and reachable** — `http://mapstone-dev.ecs.soton.ac.uk:8082/artifactory`
returned `ping http=200`, three repos exist (`asic-candidate`, `asic-record`,
`asic-release`). `asic-candidate` holds exactly **3** streams (MEASURED via AQL):

```
gdsrun-20260823-armA2/stream/nanosoc_eth_chiplet_pads.gds.zst  md5 7e74c65b
gdsrun-20260823-rzG/stream/nanosoc_eth_chiplet_pads.gds.zst    md5 76541c3f
gdsrun-20260824-valid4/stream/nanosoc_eth_chiplet_pads.gds.zst md5 522e08d6
```

**The pinfix candidate — the one actually being submitted — is not among them.**
Streams are stored zstd-compressed at ~31 MB from ~290 MB (9.6x), so publishing
is cheap.

**Fix:** publish the pinfix stream to `asic-candidate` using the project's own
publish path. **OWNERSHIP: the publish scripts and `ci/signoff.yaml` belong to
another session** — do not hand-roll a `curl PUT` around them. Ask that session
to publish `3215cbe1`, or run their documented entry point.
Note `ASIC/eth-chiplet/build/pinfix-20260824/ARMS.txt` records that
`asic-flow-publish` **refuses** this tree because it has no `route_manifest.txt`
— and that the refusal is correct and is what caught the arm confusion. So this
needs the flow owner, not a workaround.
**Risk of doing it:** none, if done through the sanctioned path.
**Risk of NOT doing it:** one disk failure loses the 1 September submission.

---

### P0-5. Load-bearing LVS evidence exists ONLY in an ephemeral tmpdir
**MEASURED.** This session's scratchpad is **71 GB** at
`/tmpdir/claude-74755/-home-dam1n19-SoCLabs-nanosoc-ethernet-chiplet/056e79f3-.../scratchpad/`.
It is a tmpdir: a reboot or a cleanup reclaims it.

Two full Calibre LVS runs live there and **nowhere else**:

| Run | Path | Size | Written |
|---|---|---|---|
| baseline | `…/scratchpad/lvs/run/` | 1.9 GB | 2026-08-23 19:42 |
| pinfix | `…/scratchpad/lvs_pinfix/run/` | 1.9 GB | 2026-08-24 20:20 |

Each contains `nanosoc_eth_chiplet_pads.lvs.rep` (~1.8 MB), `calibre_lvs.log`
(~3.5 MB), `calibre_erc.sum` (~51 KB), `innovus.log`, the LVS deck and the
`svdb/`. **The small, load-bearing subset is only ~6.6 MB per run** once the
`.cdl` netlists (47 MB + 35 MB) and `svdb/` are excluded.

I confirmed by search that the ONLY LVS reports inside the repo build trees are
`ASIC/eth-chiplet/build/gdsrun-20260824-valid4/work/erc_run/{nanosoc_eth_chiplet_pads.lvs.rep,calibre_lvs.log}`
— a different run. The two above are unique.

**Fix — copy the small subset somewhere durable BEFORE anything else tonight:**
```bash
SP=/tmpdir/claude-74755/-home-dam1n19-SoCLabs-nanosoc-ethernet-chiplet/056e79f3-fe0e-4f4f-967e-7114c63f4ebd/scratchpad
DEST=$HOME/SoCLabs/lvs-evidence-20260824   # any path OUTSIDE /tmpdir
mkdir -p "$DEST"/{lvs,lvs_pinfix}
for r in lvs lvs_pinfix; do
  cp -a "$SP/$r/run"/{*.lvs.rep,*.lvs.rep.ext,calibre_lvs.log,calibre_erc.sum,calibre_erc.db,v2lvs.log,innovus.log,*.svrf,*.deck} "$DEST/$r/" 2>/dev/null
done
du -sh "$DEST"   # expect ~13 MB total
```
Then have the flow owner publish them to `asic-record`, which already holds
1,616 items (MEASURED) and is the intended home for exactly this.

**Risk of doing it:** none — it is a copy.
**Risk of NOT doing it:** the report that identified a tapeout-blocking defect a
day before the foundry found it is one reboot from gone, and it is the only
evidence that the defect was known and characterised.

**This is a CATEGORY, not one incident** — see the inventory in P0-6.

---

### P0-6. Evidence-in-scratchpads: the category, with an inventory
**MEASURED.** Beyond the two LVS runs, this one session's scratchpad holds
large tool-output trees that are candidate unique evidence:

```
2.5G  m8s3/          1.9G  eco/           1.3G  via/
1.3G  pgab/          1.3G  freewins/      943M  eco7/
850M  agent-m9neck/  677M  pgflow/        657M  pgfarm_area/
655M  pgfarm_{land,hz3,fv,dn,ctl}/        515M  pgfarm_tlA/
514M  pgfarm_{rzE,rzC2}/  513M  pgfarm_rzG/
```

plus hand-written analyses at the top level, e.g.
`AGENT1_calibre_vs_innovus.md` (31 KB), `AGENT2_pg_fixes_no_eco.md` (35 KB),
`AGENT3_dummy_fill.md` (21 KB), `AGENT4_bnd_gap.md` (18 KB),
`50-bnd-and-logo-checks-BACKUP.md` (23 KB).

Several of these correspond to results the project treats as settled
(M8.S.3 cleared by via-master clone; VIA4.R.4 by re-cutting; the m9-neck
finding). The *conclusions* are in memory and docs; the *proofs* are here.

**And there are other sessions' scratchpads**: 5 git worktrees are registered
into two other sessions' tmpdirs (see P3-1), so this session's 71 GB is not the
whole picture.

**Fix:** a sweep, owner-driven, one directory at a time:
```bash
# for each candidate: is there an equivalent inside the repo?
find /tmpdir/claude-74755/-home-dam1n19-SoCLabs-nanosoc-ethernet-chiplet \
     -maxdepth 4 -name '*.md' -newermt '2026-08-17' -size +4k 2>/dev/null
```
Rescue the `.md` analyses and the small `.rpt`/`.sum`/`.json` verdicts; leave the
multi-GB Innovus databases — those are reproducible, the reports are not.
**Risk of NOT doing it:** the project keeps re-deriving results it already has.

---

## P1 — BLOCKS OR ENDANGERS THE 1 SEPTEMBER SUBMISSION

### P1-1. `post_route.tcl` is untracked but cited by 29 tracked files
**MEASURED.** `ASIC/eth-chiplet/hooks/post_route.tcl` (16 KB, modified today
12:40) does not exist in a fresh clone, yet tracked documents reference it,
including:

```
docs/plans/TAPEOUT_PUNCHLIST_2026-08-24.md
docs/plans/ASIC_BUILD_FLOW_PLAN_2026-08-24.md
docs/tapeout/56-core-pin-check-stdcell-geometry-not-tested.md
ASIC/genus-innovus/scripts/dump_io_file.tcl
```

This is the project's own documented seam for post-route flow logic. Commit
`1c5519b` ("power plan: clear M8.S.3 x2 and VIA4.R.4 x1 on the ROUTED DB —
signoff DRC 741 → 738") depends on this class of edit.

**This is almost certainly a live session's in-progress work (mtime today).**
**Do not commit it on their behalf.** Ask whoever owns the post-route DRC work
to land it.
**Risk of NOT doing it:** the tapeout punchlist instructs a reader to run a file
that CI and a fresh clone do not have. The 738 DRC result is not reproducible.

---

### P1-2. Untracked flow/verification work — classify before touching
**MEASURED** (25 untracked paths, newest first; mtimes are today unless shown).
`refs=` is how many other files mention the basename.

| Path | mtime | refs | Read |
|---|---|---|---|
| `scripts/ci/accept_stream.py` | 19:12 | 1 (self) | **ACTIVE — publish-flow session.** Matches HEAD `38da410` and toolkit `2e0cda6`. **ASK, do not commit.** |
| `scripts/rig/eth_chiplet/*` (9 files) | 10:17–18:24 | — | Rig/bringup tooling, coherent set with a README. Looks finished; ask the bringup session. |
| `verif/lint/netlist/{run.sh,selftest.sh,README.md,fixtures/*}` | 17:14–17:30 | 5 | Netlist-lint gate with fixtures + selftest. Looks finished. **Hook warns it carries vendor-shaped strings — see P1-3.** |
| `ASIC/eth-chiplet/hooks/post_route.tcl` | 12:40 | **29** | See P1-1. Highest value. |
| `ASIC/genus-innovus/scripts/dump_io_file.tcl` | 12:20 | 3 | Pairs with `scripts/xcheck_io_vs_gds.py`; both cited by the tracked `ASIC/submissions/padring_as_built_rzG_20260823/README.md`. |
| `scripts/xcheck_io_vs_gds.py` | created 12h06 | 3 refs | As above — **a tracked README already cites both.** Commit as a pair. |
| `ASIC/logos/{logo_gds_lint.py,repair_logo_seam.py}` | 08-22 | 1–2 | Orphaned. `repair_logo_seam.py` is referenced **only by `.gitignore`**, which documents a script the repo does not contain. |
| `docs/asic/TOOLKIT_GUIDE.md` | 08-20 | — | 24 KB doc. Hook flags 2 lines as absolute site paths. |
| `docs/plans/GDS_RUN_PLAN_2026-08-19.md` | 08-19 | — | Hook flags line 81 (LEF/Liberty keyword + number). |
| `docs/plans/CROSSDIE_READ_DIAGNOSIS_PLAN.md` | 13:18 | — | Today's diagnosis plan. |
| `LAUNCH_CARD_2026-08-19.md` | 08-19 | — | Root-level launch card; stale by 5 days. |
| `ASIC/gls-netlist/bench/eth_chiplet_fp1505_forced.json` | 08-19 | 5 | **Cited by the tracked `ASIC/gls-netlist/Makefile`.** Commit with that Makefile's change. |

**The safe general command** — never `git add -A` in this tree:
```bash
git add -- <one explicit path>          # never -A, never .
git commit -m "..." -- <the same paths> # pathspec-limited: does NOT take the shared index
```
The pathspec on `git commit` is the important half. A bare `git commit` here
takes whatever peers have staged.

**Owner must ask another session before committing:** `accept_stream.py`,
`post_route.tcl`, `scripts/rig/eth_chiplet/*`, `verif/lint/netlist/*`.
**Safe for the owner to land alone** (orphaned, cited by already-tracked files,
no peer mtime today): the `dump_io_file.tcl` + `xcheck_io_vs_gds.py` pair, the
two `ASIC/logos/` scripts, and `eth_chiplet_fp1505_forced.json`.

---

### P1-3. Three untracked files carry vendor-shaped strings the hook names
**MEASURED — quoted from the hook's own warning block:**

```
docs/asic/TOOLKIT_GUIDE.md:390             path          absolute site path
docs/asic/TOOLKIT_GUIDE.md:391             path          absolute site path
docs/plans/GDS_RUN_PLAN_2026-08-19.md:81   value.lef     an upper-case LEF/Liberty keyword on a line carrying a multi-significant-figure number
verif/lint/netlist/run.sh:72               ident         revision-coded vendor release name
verif/lint/netlist/run.sh:72               path          absolute site path
verif/lint/netlist/run.sh:73               ident         revision-coded vendor release name
verif/lint/netlist/run.sh:73               path          absolute site path
verif/lint/netlist/run.sh:74               path          absolute site path
```

Today these are **warnings** because a push does not publish untracked files.
**The moment anyone `git add`s them they become blocking findings** — the hook
charges an added file for every line of it. This repository is PUBLIC.

**Fix before adding any of them:**
```bash
ci/check-vendor-collateral.sh          # full report and the per-kind remedy
```
Resolve each line (parameterise the site path, drop the vendor release string)
or add an allowlist entry **with a reason**. Do not add them blind.
**Risk of NOT doing it:** a well-meaning commit publishes a TSMC release
identifier to a public GitHub repo.

---

### P1-4. Collectors that point at paths nothing writes — a class
**MEASURED, with a correction.** I tested every `ASIC|build|verif|scripts|docs`
path in `ci/signoff.yaml` for existence. Most apparent misses are **false
alarms** — they are relative to `ASIC/eth-chiplet`, and resolve correctly:
`build/fp1505/outputs/…gds`, `build/fp1505/work/drc_run`,
`build/full-20260814/romlibs`, `build/gdsrun-20260823-rzG/romlibs` all EXIST.

**Genuinely broken — four repo-root-relative paths under one run tag:**

```
L1735  ASIC/eth-chiplet/build/gdsrun-20260823-rzG/work/lvs_run/**
L2004  ASIC/eth-chiplet/build/gdsrun-20260823-rzG/work/erc_run/run_erc.log
L2021  ASIC/eth-chiplet/build/gdsrun-20260823-rzG/work/erc_run/**
L2049  ASIC/eth-chiplet/build/gdsrun-20260823-rzG/work/bnd_run/**
L2099  ASIC/eth-chiplet/build/gdsrun-20260823-rzG/work/drc_logo_run/**
```

The parent `…/gdsrun-20260823-rzG/work/` **does** exist and contains `drc_run/`
— but `lvs_run/`, `erc_run/`, `bnd_run/` and `drc_logo_run/` were never created.
The LVS that matters ran into a tmpdir instead (P0-5).

`signoff.yaml` itself is candid about the LVS one:

> `The preflight launches no tool and writes no log of its own, so there is`
> `nothing here that it produces. LVS_RUNDIR is where the FULL run would`
> `write; globbed rather than named so an empty directory collects nothing`
> `instead of failing the stage.`

So it is deliberate for `lvs`, and the design consequence is that **a stage can
be green while collecting nothing**. Whether the other three are deliberate is
for the flow owner to say.

**OWNERSHIP: `ci/signoff.yaml` belongs to another session — report, do not edit.**
Hand them this list.
**Risk of NOT doing it:** signoff collects no evidence for LVS/ERC/BND/logo-DRC
and reports success, which is how "green verdicts read the wrong stream" keeps
recurring.

---

## P2 — SPACE. ~180 GB is reclaimable in principle; be careful which.

**Measured totals:**

| Path | Size |
|---|---|
| `ASIC/genus-innovus/runs/` (42 runs) | **63 GB** |
| `ASIC/eth-chiplet/build/` (34 trees) | **38 GB** |
| session scratchpad (tmpdir, this session) | **71 GB** |
| `.git/lost-found/other` | **2.7 GB** |
| `ASIC/genus-innovus/baseline_2026-08-0{6,7}` | 4.9 GB |
| root `build/` | 4.0 GB |
| `ASIC/submissions/` | 1.5 GB |
| `tidelink/` | 13 GB |
| `.git` total (objects only 307 MB) | 4.9 GB |

### P2-1. MUST KEEP — bound by md5, not by name
- `ASIC/eth-chiplet/build/pinfix-20260824/` (3.2 GB) — **the submission**.
  `logo_orig/…logo.gds` md5 `3215cbe1` is byte-identical to the submitted
  stream. **Read `ARMS.txt` before touching anything in here.** Two arm names
  are actively misleading: `_orig` is the FIX (original *routing* restored),
  `_ctl` is the control, and `logo_out/` (md5 `29b5ff1b`) is the **rejected**
  ECO arm despite the name. I verified all four arm md5s against ARMS.txt and
  they match: `ctl 4d8f23c5`, `orig 8688e874`, `eco 09c4ff93`, `blkg 574dcb60`.
- `ASIC/eth-chiplet/build/gdsrun-20260823-rzG/` (1.8 GB) — published to
  Artifactory AND is the tree the foundry return is bound to.
- `ASIC/eth-chiplet/build/gdsrun-20260823-armA2/`, `gdsrun-20260824-valid4/` —
  both published as candidates; keep until their returns are closed.
- `ASIC/submissions/` (1.5 GB, 5 streams) — keep. The `.md` notes are tracked,
  the streams are deliberately not.

### P2-2. Safe-to-delete candidates — verify each is unbound first
`ASIC/genus-innovus/runs/` is the biggest single win at 63 GB, and the
`.gitignore` says each run is "self-describing, reproducible from the git SHA in
MANIFEST.txt". The runs are dated 2026-08-07 → 08-12, i.e. **all predate the
current lineage**, and the shipping lineage was re-synthesised on 08-21.

**Do not delete by date.** Bind first:
```bash
# 1. list every stream md5 currently published or submitted
find ASIC/submissions -name '*.gds' -exec md5sum {} +   > /tmp/keep.md5
# 2. md5 every GDS in the runs tree (slow; run once, overnight)
find ASIC/genus-innovus/runs -name '*.gds' -exec md5sum {} + > /tmp/runs.md5
# 3. anything in runs.md5 whose md5 appears in keep.md5 is BOUND — keep it
cut -d' ' -f1 /tmp/keep.md5 | grep -Ff - /tmp/runs.md5
```
Only delete a run directory if **no** GDS inside it matches a kept md5 **and**
no `ASIC/submissions/*.md` note names that run tag.
**Risk of doing it wrong:** this project has twice bound the wrong artefact by
directory name. The md5 step is not optional.
**Risk of NOT doing it:** 63 GB, and 42 stale runs make the real lineage harder
to find — which is itself a correctness risk near a tapeout.

### P2-3. `.git/lost-found/other` — 2.7 GB
**MEASURED.** This is `git fsck --lost-found` output: dangling blobs written to
disk. 2.7 GB of them, plus a 12 KB `commit/` directory.
```bash
ls .git/lost-found/commit    # inspect these FIRST — dangling commits may be recoverable work
```
The `other/` blobs are almost certainly old GDS/database blobs. **Do not
`git gc`** while peer sessions are live — it can race their object writes.
Inspect `commit/` for anything worth rescuing, then this is reclaimable during a
quiet window.

### P2-4. Do NOT reclaim
- `ASIC/tech_wrappers/tsmc65/local_overrides/` — the `.gitignore` records that
  archived Innovus databases hold **absolute** symlinks through this path and
  `read_db` aborts with IMPIMEX-7023 without it.
- the read-only lab-shared vendor IP trees (see CLAUDE.md for the exact paths) — read-only by policy.

---

## P3 — TIDINESS

### P3-1. 21 registered worktrees, 5 inside OTHER sessions' tmpdirs
**MEASURED** via `.git/worktrees/*/gitdir`. **All 21 resolve to a live path — none
are stale**, so `git worktree prune` would currently remove nothing.

- 11 `.claude/worktrees/agent-*` — harness worktrees. Three are from 08-07 and
  0 commits ahead of main (`a187aac5`, `a1c44806`, `a96f3583`) → almost certainly
  abandoned. The rest are 50–207 commits ahead of main and dated 08-17/08-18.
- 3 sibling run-trees outside the repo: `/home/dam1n19/SoCLabs/gds-run-20260819`,
  `…/gds-run-20260820`, `…/gds-run-20260820b`.
- 2 wedge arms: `/home/dam1n19/SoCLabs/ab_wedge_2026-08-20/arm{A,B}`.
- **5 inside two peer sessions' scratchpads** (`2f9eb573-…`, `f4b0d7c7-…`):
  `pgfix-run-458d108`, `pgfix-wt`, `rewrite-clean`, `route-clean-557fd33`,
  and notably **`pushwt`** — a worktree someone created to attempt a push.

**These 5 belong to live sessions. Do not prune, do not delete.** They also mean
peer sessions hold work in tmpdirs subject to the same loss risk as P0-5.
**Owner action:** ask the two peer sessions to land or copy out their worktrees.

`.git/worktrees` is 927 MB and `.git/modules` 1.1 GB — both follow from the
above; neither is independently reclaimable.

### P3-2. Submodule working trees are dirty
**MEASURED.**
- `tidelink`: untracked `dut_src.f` and `imp/hw_gate/tl042_recovery_proto/`.
  Also **32 commits on no remote**, across ~20 local branches with names like
  `evidence/d2d-wedge-captures-2026-08-19` and
  `exec/gds-critical-tl037-n3-2026-08-17`. The pin itself resolves (it is
  `origin/main` = tag `v0.90`), so a fresh clone works — but that named
  *evidence* branch is local-only.
- `nanosoc-multicore-system`: ` M ahb_qspi` — a nested submodule pointer moved.
  Its pin still resolves; this is an uncommitted pointer bump.

Neither blocks a clone. Both are work that is not off-machine.
**Owner action:** ask the TideLink owner whether
`evidence/d2d-wedge-captures-2026-08-19` should be pushed. It is named evidence
and it is not backed up.

### P3-3. Abandoned local branches
`docs/62-power-plan-answer`, `docs/tapeout-56-core-pin-eco-not-tested`,
`fix/migration-rebased`, `proposal/peer-write-burst-corruption` have no upstream.
`rom-content-gates` tracks `origin/fix/tag-ram-gwen` and is
**[ahead 4, behind 184]** — a mis-set upstream, worth correcting or deleting.
Low value; do last, and only after confirming with peers.

---

## Corrections to beliefs currently in circulation

1. **"The superproject cannot push; a vendor hook refuses ~58 commits."**
   **REFUTED, measured 2026-08-24.** The hook exits **0**. It was rewritten on
   08-18 to charge only what a push *adds*. There are **18** unpushed commits
   across all branches (6 on the current one), not 58, and nothing is blocking
   them.
2. **"The toolkit commits are pushed."** **Partly false.** `9a982be`, `3a8c30a`,
   `cadbd3b` are published; **`2e0cda6`, the commit the superproject pins, is
   not.** That single gap breaks fresh recursive clones.
3. **"`ci/signoff.yaml` collects from empty build paths" (as a general claim).**
   **Mostly false.** Most such paths are relative to `ASIC/eth-chiplet` and
   resolve. **Four** genuinely do not, all under `gdsrun-20260823-rzG/work/`,
   and the LVS one is documented as intentional.
4. **`ASIC/eth-chiplet/build/` is 38 GB, but `ASIC/genus-innovus/runs/` is 63 GB**
   — the larger space item is the one not mentioned in the brief.

---

## Suggested order of execution

```
1. P0-1  push the toolkit branch  <-- NOW URGENT   (~1 min, repairs a PUBLISHED broken pin)
2. P0-5  copy LVS evidence out of tmpdir            (~1 min, zero risk)
3. P0-2  push `25e7606`, the 1 remaining commit     (~1 min, hook passes)
4. P0-3  push the six tags                          (~2 min)
5. P0-4  ask flow owner to publish stream 3215cbe1  (needs another session)
6. P1-1  ask post-route owner to land post_route.tcl(needs another session)
7. P1-3  run ci/check-vendor-collateral.sh BEFORE adding any untracked file
8. P1-2  land the safe orphans (io/logo/gls pairs)
9. P1-4  hand the four broken collector paths to the signoff owner
10. P2   space, md5-bound, in a quiet window
```

Steps 1–4 are ~6 minutes and remove every identified way to lose work.

---

## Appendix A — The evidence-reachability problem, precisely

**The brief asked which gitignore rules cause it and what the minimal safe
change is. MEASURED answer: it is essentially ONE rule.**

### A.1 The dominant rule
`.gitignore:207` is a bare, unanchored `build/`. Because it has no leading
slash, it matches a directory named `build` **at any depth**. `git check-ignore -v`
attributes all of the following to that single line:

```
.gitignore:207:build/   ASIC/eth-chiplet/build/pinfix-20260824/reports/…
.gitignore:207:build/   ASIC/eth-chiplet/build/gdsrun-20260823-rzG/work/drc_run/…
.gitignore:207:build/   build/rom_verify/…
.gitignore:207:build/   build/signoff/rom-content/build/rom_verify/…
```

So one rule hides: the whole 38 GB `ASIC/eth-chiplet/build/` tree — **including
every `reports/` and every `work/*_run/` directory inside every run** — plus the
ROM verification evidence and the signoff stage outputs.

### A.2 What the other suspected rules actually cost
Much less than assumed:

| Rule | What it hides | Measured |
|---|---|---|
| `ASIC/*/reports` (L83) | `ASIC/genus-innovus/reports`, `ASIC/sta/reports` | **only 6.3 MB, 68 files** |
| `ASIC/*/calibre_runs` (L112) | Calibre DBs | large, regenerable |
| `ASIC/genus-innovus/rail/work/` (L102) | **vendor `DCCURRENTDENSITY` values** | **MUST STAY IGNORED** |
| `ASIC/genus-innovus/rail/inputs/*.ict` | vendor-derived EM models | **MUST STAY IGNORED** |

Of the 68 files under the two `reports/` dirs, **55 are under 64 KB** — i.e. the
human-readable verdicts are small and cheap to keep. The bulk is elsewhere.

### A.3 Why a blanket un-ignore is NOT the answer
Three independent reasons, all measured:
1. `build/` holds **38 GB**, including ~290 MB GDS streams per run.
2. `rail/work/` and `rail/inputs/*.ict` reproduce **foundry current-density
   limits verbatim**. This repository is PUBLIC. Un-ignoring anything that
   sweeps them in is a licence breach, not an untidiness.
3. The pre-push hook would then charge every newly-added line (P1-3).

### A.4 The recommended answer: publish, don't track
**Artifactory is live and is already doing this job.** MEASURED:
`asic-record` holds **1,616 items**, organised as
`ethchip/<top>/<stream-name>/foundry/Archive_…/{drc,ant,erc}` — i.e. the foundry
returns are already bound to their stream. `asic-candidate` holds the streams
themselves, zstd-compressed at ~9.6x.

The gap is not that evidence *cannot* be stored; it is that **locally-run
evidence is not being published to the store that exists**. The two LVS runs in
P0-5 should land in `asic-record` under the stream they measured, bound by the
stream's md5 — not committed to git.

**Minimal in-repo change, if any is wanted at all:** do NOT touch `build/`.
Instead adopt one narrow negation for a dedicated evidence directory, using the
same technique the file already uses successfully at `!/ci/fixtures/**/build/`
(negate the DIRECTORY so git descends into it):

```gitignore
# Small, hand-curated verdicts a gate must be able to read in a fresh clone.
# Directory negation, not a file glob: git does not descend into an excluded
# directory, so !.../evidence/*.json would re-include nothing.
!ASIC/eth-chiplet/build/*/evidence/
```

and have each stage drop its few-KB verdict JSON there. That keeps 38 GB and all
vendor-derived collateral excluded while making the *verdicts* clonable.

**Ownership:** the `.gitignore` is shared, but the stage-writes-evidence half is
flow work — **the flow/report owner should decide**, since it interacts with
`ci/signoff.yaml` collectors (P1-4).

---

## Appendix B — Commands NOT to run in this tree

Recorded because each has caused a measured incident here:

```bash
git add -A            # takes peers' in-progress files; the hook's own warning calls this out
git add .             # same
git commit            # bare: commits the WHOLE shared index, including peers' staged work
git gc                # races concurrent object writes from ~12 live sessions
git worktree prune    # all 21 registrations currently resolve; 5 belong to live peer sessions
git push --no-verify  # bypasses the vendor guard; the guard currently PASSES, so there is no reason
```

Use pathspec-limited forms instead:
```bash
git add -- path/to/one/file
git commit -m "msg" -- path/to/one/file
```

---

## Appendix C — Working-tree snapshot re-taken at 22:04 [VOLATILE]

The set grew from 25 untracked / 11 modified (20:40) to **34 untracked / 12
modified** in 84 minutes. The delta is one peer session working right now.

### C.1 ACTIVE PEER WORK — do not commit, do not move, do not delete
All created between 21:56 and 22:03, i.e. **while this audit was being written**:

```
22:02  scripts/ci/route_message_census.py                                  (20K)
22:02  ci/fixtures/route-message-census/fail-unrouted-net-only/…log
22:01  docs/plans/BLACKBOX_DETECTION_2026-08-24.md                         (20K)
22:01  ci/fixtures/route-message-census/PROVENANCE.md
22:00  ci/fixtures/route-message-census/not-measured-abort/…log
21:59  ci/fixtures/route-message-census/{pass,fail-unrouted-net,fail-open-nets}/…log
21:56  docs/plans/END_TO_END_EVIDENCE_FLOW_2026-08-24.md                   (12K)
21:53  docs/TIDELINK_FREEZE_SIGNOFF_PACK.md                          (modified)
```

This is a coherent, in-flight change: a route-message census gate with a full
pass/fail fixture set and a provenance note. It belongs to the session that owns
the end-to-end flow and report design. **It is not abandoned and it is not the
owner's to land.**

`docs/plans/REPO_HYGIENE_2026-08-24.md` (this file, 22:03) is mine — untracked
by design; the owner asked to review before committing.

### C.2 Revised ownership call for the untracked set

| Group | Verdict |
|---|---|
| route-message-census + BLACKBOX/END_TO_END docs (7 paths) | **ASK — active peer, minutes old** |
| `scripts/ci/accept_stream.py` | **ASK — publish-flow session** |
| `ASIC/eth-chiplet/hooks/post_route.tcl` | **ASK — but chase it; 29 tracked files cite it (P1-1)** |
| `scripts/rig/eth_chiplet/*` (9 files) | ASK — bringup session; set looks complete |
| `verif/lint/netlist/*` (5 files) | ASK — and run the vendor check first (P1-3) |
| `dump_io_file.tcl` + `xcheck_io_vs_gds.py` | **SAFE for owner** — a tracked README already cites both |
| `ASIC/logos/{logo_gds_lint,repair_logo_seam}.py` | **SAFE for owner** — orphaned since 08-22; `.gitignore` already names one |
| `ASIC/gls-netlist/bench/eth_chiplet_fp1505_forced.json` | **SAFE for owner** — the tracked `Makefile` change cites it |
| `LAUNCH_CARD_2026-08-19.md`, `docs/plans/GDS_RUN_PLAN_2026-08-19.md`, `docs/asic/TOOLKIT_GUIDE.md` | Owner's call — 5 days old, stale, vendor-flagged (P1-3) |

### C.3 Modified files, unchanged from the 20:40 reading except one
`docs/TIDELINK_FREEZE_SIGNOFF_PACK.md` became modified at 21:53 (peer).
The other 9 plus the 2 submodule pointers are as described in P1-2 / P3-2.

**Operational consequence:** any `git add -A` or bare `git commit` run in the
next few hours captures a peer's half-finished census gate. The pathspec-limited
forms in Appendix B are not a style preference here; they are the only safe
forms while this many sessions are live.

---

## Appendix D — Sibling worktrees OUTSIDE the repo: complete enumeration

**MEASURED** from `.git/worktrees/*/gitdir`. There are **21 registered
worktrees** and **all 21 resolve to a live path** — `git worktree prune` would
currently remove nothing. `gds-run-20260820b` is not the only one; there are
five external run-trees plus five inside peer sessions' tmpdirs.

### D.1 External run-trees — 24.4 GB total, all stale since 08-21

| Path | Size | Dirty | Newest file | Largest stream (md5) |
|---|---|---|---|---|
| `/home/dam1n19/SoCLabs/gds-run-20260819` | 5.4 GB | 5 | 2026-08-21 13:36 | `b1441d78` …pads.gds (302M) |
| `/home/dam1n19/SoCLabs/gds-run-20260820` | 2.7 GB | 2 | 2026-08-21 00:48 | `4f027235` …pads.gds (301M) |
| `/home/dam1n19/SoCLabs/gds-run-20260820b` | **7.4 GB** | 1 | 2026-08-21 22:14 | `82749625` …pads.gds (294M) |
| `/home/dam1n19/SoCLabs/ab_wedge_2026-08-20/armA` | 4.5 GB | 2 | 2026-08-20 12:57 | — (FPGA bitstreams) |
| `/home/dam1n19/SoCLabs/ab_wedge_2026-08-20/armB` | 4.5 GB | 2 | 2026-08-20 12:57 | — (FPGA bitstreams) |

`gds-run-20260820b` additionally holds three more ~255–260 MB streams:
`…_stockmap.gds` (`486ac289`), `…_stockmap_logo.gds` (`37e74fe2`),
`…_m3label.gds` (`d86df179`).

**None of these md5s matches any of the five streams in `ASIC/submissions/`, and
none matches the three published to `asic-candidate`.** They are unbound
experiments. All are ≥3 days stale.

**Before reclaiming any of them**, note each is a *registered git worktree* with
uncommitted changes (1–5 files each). Deleting the directory leaves a stale
registration and loses those edits. The correct sequence, per tree:
```bash
git -C <path> status --porcelain          # inspect the 1-5 dirty files FIRST
git -C <path> stash list                  # and any stashes
# only then, and only if nothing is wanted:
git worktree remove <path>                # NOT rm -rf: this deregisters cleanly
```
**Risk of doing it:** the dirty files are unreviewed; two of these trees were
used for the 08-20/08-21 stockmap and m3label experiments.
**Risk of not:** 24.4 GB, and five extra copies of the tree for a future reader
to mistake for the live one.

### D.2 Worktrees inside LIVE peer sessions' scratchpads — DO NOT TOUCH

```
1.6G  dirty=1  …/2f9eb573-…/scratchpad/pgfix-run-458d108
643M  dirty=0  …/2f9eb573-…/scratchpad/pgfix-wt
121M  dirty=0  …/2f9eb573-…/scratchpad/route-clean-557fd33
 14M  dirty=0  …/2f9eb573-…/scratchpad/rewrite-clean
5.2M  dirty=0  …/f4b0d7c7-…/scratchpad/pushwt
```

Two distinct peer sessions. These are **inside tmpdirs**, so they carry the same
loss exposure as P0-5 — and `pgfix-run-458d108` has an uncommitted change.
**Owner action:** ask sessions `2f9eb573` and `f4b0d7c7` to land or copy out
their worktrees before anything reclaims `/tmpdir`.

### D.3 The 11 harness worktrees
`.claude/worktrees/agent-*`, all live registrations. Three (`a187aac5`,
`a1c44806`, `a96f3583`) are dated 2026-08-07 and are **0 commits ahead of
main** — abandoned, safe to remove with `git worktree remove` after a
`status --porcelain` check. The other eight are 50–207 commits ahead and dated
08-17/08-18; leave them.

---

## What this audit did NOT establish

Stated plainly so nobody reads absence as clearance:

- **Two background searches did not report before this session ended** — a wide
  sweep for stray copies beyond `/home/dam1n19/SoCLabs`, and a deeper
  orphaned-work sweep across *all* `/tmpdir/claude-*` session scratchpads. What
  is in Appendix D and P0-6 is what I measured directly. **Other sessions'
  scratchpads were not inventoried for orphaned evidence** — only their
  registered worktrees were found. Given this session's scratchpad alone holds
  71 GB and two unique LVS runs, assume the others hold comparable material.
- **`ASIC/genus-innovus/runs/` (63 GB, 42 runs) was not md5-bound.** P2-2 gives
  the procedure; it needs an overnight run to execute.
- **No duplicate-source dedup was attempted.** Confirmed the scale only:
  `cache_ram.v` has **21 copies in 3 distinct md5s**, named by **6** different
  flists. Any dedup must be driven from the flists, never from filenames.
- **`.git/lost-found/commit` (12 KB) was not inspected** for recoverable
  dangling commits. Worth five minutes before the 2.7 GB `other/` is reclaimed.
