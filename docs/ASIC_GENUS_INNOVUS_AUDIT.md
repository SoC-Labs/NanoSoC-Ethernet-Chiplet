# ASIC/genus-innovus — audit and retirement plan

Owner: session f8-delegate (this document). Measured 2026-08-17 against HEAD
`2dca8ae` plus the two unpushed migration worktrees. **UNTRACKED and uncommitted
by instruction.** Companion: [`ASIC_MIGRATION_BLOCKERS.md`](ASIC_MIGRATION_BLOCKERS.md)
(8a, method + collision evidence) and `docs/tapeout/33-toolkit-legacy-decoupling.md`
(f9, the `../scripts/` contract).

---

## 1. The headline: the deliverable is not a deletion

The task was framed as "when is `asic-toolkit` the only flow actually TRUE".
The answer is not gated on deleting `ASIC/genus-innovus`, and planning a
deletion is planning the wrong thing. Two measurements say so.

**(1) `ASIC/genus-innovus/scripts/` is a contract directory, not a legacy
folder.** `ASIC/asic-flows` — a *lab-shared* submodule
(`SoC-Labs/ASIC-Flow.git`, branch `lpddr4-pll`) — sources design collateral
through hardcoded `../scripts/` literals resolved against the Innovus CWD.
Verified: 13 live literals in `ASIC/asic-flows/Cadence/*.tcl`, naming 10
entries. Nine are present; `dft_setup.tcl` is absent but conditional at
`1_synthesis.tcl:59` with DFT off, so it is never sourced.

**(2) The toolkit consumes genus-innovus as its data source.**
`ASIC/eth-chiplet/design.mk:69` sets `LEGACY_ASIC_DIR` and points 14+ variables
at it — floorplan, power plan, mmmc, io, upf, constraints, bondpads, DRC deck.
On HEAD the toolkit does not own its own collateral; it reads the legacy tree
byte-for-byte through a documented symlink bridge (`legacy-paths`).

So on HEAD, `rm -rf ASIC/genus-innovus` does not retire a parallel flow. It
deletes the design data *both* flows run on.

### What the migration worktrees change, and what they do not

`a18825b` (worktree `agent-a402bee1222b2421b`) sets out to invert (2): 12
`git mv`s move the collateral into
`ASIC/eth-chiplet/{floorplan,power,mmmc,constraints,config}/`, with symlinks
left at the old paths so both flows keep resolving.

**The symlinks are not in the commit.** Corrected 2026-08-17 after f9 caught an
error in the first version of this section — I tested the worktree's *working
directory*, where the symlinks are present and resolve, and attributed that to
the commit. Re-measured against the commit itself:

- `git show --stat a18825b` → **12 files changed, 0 insertions(+), 0 deletions(-)**.
  A pure rename set. A commit that added 12 symlinks could not have zero insertions.
- `git ls-tree -r a18825b` → `floorplan.tcl`, `power_plan.tcl`,
  `place_bondpads.tcl`, `filler.tcl`, `<BLOCK>.mmmc`, `<BLOCK>.io` are **absent**
  from `ASIC/genus-innovus/scripts/`. No mode-120000 entries.
- `git status --porcelain` in the worktree → 12 paths staged `A `, **index only,
  uncommitted**: six under `scripts/` and six under `inputs/`
  (4 sub-SDCs + `constraints.sdc` + the `.upf`). f9's count of 6+6 is right; my
  earlier "four moved entries" undercounted.

This also answers 8a's non-reproduction: they measured **main** (`git ls-files -s`,
zero tracked symlinks in the repo — correct), while the symlinks live in a
**different worktree's index**, which main's index cannot see. All three
measurements agree; they were taken at three different levels.

So the reconciliation of f9's "cannot be moved" and e6's "already moved" stands,
but conditionally:

> **The contract survives the move IF AND ONLY IF the staged symlinks are
> committed.** As things stand that protection exists only in one session's
> index. Treat committing them as a **merge precondition**, not a detail.

**Merging `a18825b` as it is breaks both flows** — and the legacy half is worse
than "silent". A missing Tcl `source` does raise; what swallows it is that
**Genus and Innovus exit 0 after a failed script**, which this repo documents
against itself at `ASIC/genus-innovus/Makefile:19` and `:206`. So the diagnostic
is not absent, it is *discarded*: Tcl error inside the tool, exit 0, green
`make`. (8a's refinement; call it exit-0, not silent.)

That compounds with a gap 8a found in the assert list: **`legacy-paths` covers
only 7 of the 12 moved files.** Verified — it asserts `scripts/{$(BLOCK).io,
filler.tcl}` and the five `inputs/*.sdc`, and does **not** assert
`floorplan.tcl`, `power_plan.tcl`, `place_bondpads.tcl`, `<BLOCK>.mmmc` or
`<BLOCK>.upf`. Those five are precisely the ones consumed later, at tool
runtime, by the exit-0 path above. `legacy-paths` is a bridge self-check, not a
migration safety net, and must not be cited as one.

The toolkit half breaks *loudly*, which is the better half: at `a18825b`,
`design.mk:69` still defines `LEGACY_ASIC_DIR` and `legacy-paths` still exists
at `:512` asserting seven files —
`scripts/{$(BLOCK).io,filler.tcl}` and `inputs/{constraints,qspi,tidelink,ethernet,i2c}_constraints.sdc`
— and **all seven are absent from the a18825b tree**. (e6's report that
`LEGACY_ASIC_DIR` and the bridge are deleted describes the *staged second
commit*, not `a18825b`.)

Once committed, the symlinks become load-bearing infrastructure for a
*lab-shared* engine. e6's summary — "deleting genus-innovus now deletes
symlinks, not design data" — is right about the data and wrong about the
consequence: deleting them breaks `asic-flows`' contract.

### Step 1a is SATISFIED at `72febb7` — verified independently

f9 committed the staged symlinks as `72febb7` ("keep the legacy paths alive as
symlinks…"), branch tip of `worktree-agent-a402bee1222b2421b`.

**`72febb7` is NOT on the shipping branch, and nothing below is a live defect.**
Checked because the escalation could be misread as one: `git merge-base
--is-ancestor 72febb7 HEAD` → **no**. Branch `fix/tag-ram-gwen` at `5245456`
carries zero mode-120000 entries, no `ASIC/eth-chiplet/constraints/`, and the
current 205-line `qspi_constraints.sdc`. The park is intact and the work is
correctly quarantined in a worktree. **Everything in this section is a
merge-time risk.** What is time-critical is the rising *cost* of the merge, not
a defect in what ships today.

Re-measured against the **commit tree**, not the working tree:

- `git show --stat 72febb7` → 21 files, **823 insertions(+)** — the stat line
  that was `0 insertions` at `a18825b`.
- 12 entries at **mode 120000** in `git ls-tree -r 72febb7`, six under
  `scripts/`, six under `inputs/`.
- **Zero dangling.** Every link target resolves to a path that exists *inside
  tree `72febb7`* — checked by reading each link blob and resolving it against
  the tree's own path set, not the filesystem. f9 is right that this needs
  checking separately: git stores a dangling symlink without complaint, and a
  dangling set would have reproduced the original silent failure exactly.
- `asic-flows` contract 9/10; `dft_setup.tcl` still absent, pre-existing and
  conditional, not a regression.
- `design.mk` `legacy-paths` assert list: **7/7 resolve.**

### But the fallback is not a control, and `72febb7` ships a stale file

Two things follow that the plan has to state plainly.

**The legacy tree was never an independent fallback.** 8a's warning — that
symlinking the legacy paths at the toolkit copies stops genus-innovus being an
independent flow — points at a real risk but dates it wrongly. On HEAD there is
already exactly **one** copy of each file: `design.mk` sets
`FLOORPLAN_TCL ?= $(LEGACY_ASIC_DIR)/…` and the bridge's own comment says the
live files are "consumed BYTE FOR BYTE with no edit anywhere". Both flows have
always read the same bytes. `72febb7` does not create the coupling, it
**inverts its direction**: before, a legacy-side edit silently changed the
toolkit; after, a toolkit-side edit silently changes legacy. The copy count is
one either way.

That matters for the "build a chip at every point" constraint. The fallback
satisfies it only in the sense that *something runs* — it is a mirror, not a
control, and it cannot be used to attribute a regression to the migration.

**And the second failure mode is live at the tip.** 8a found the a402bee
collateral splits into stale files and edited files. I checked the one that
matters at the commit level:

| `qspi_constraints.sdc` | lines | md5 |
|---|---|---|
| `cd8b47d` (branch base) | 123 | `d1398b6e…` |
| `2dca8ae` (current HEAD) | 205 | `c2375c83…` |
| **`72febb7`** `eth-chiplet/constraints/` | **123** | **`d1398b6e…`** |

`72febb7` carries the **stale** pre-`2dca8ae` file, byte-identical to the branch
base. It never received `2dca8ae` (the QSPI C3 open-decision work). Because the
legacy path is now a symlink at that copy, **both flows would silently serve
pre-`2dca8ae` QSPI constraints** — and no gate in §3 can see it, because every
file present, readable and non-dangling is exactly what those gates check.

This is a staleness problem, not an edit conflict, and it is why 8a's
resume-as-*rebuild-from-then-current-HEAD, copy-not-move* is the right shape.

### It is not per-file drift. The branch reverts two identified commits.

f9 generalised the qspi finding to all 12 moved files; I reproduced their
classification independently (base `cd8b47d`, branch `72febb7`, HEAD — now
`5245456`, it moved again mid-audit):

| bucket | n | files |
|---|---|---|
| DIVERGED | 1 | `constraints.sdc` |
| STALE | 3 | `qspi_`, `tidelink_`, `ethernet_constraints.sdc` |
| branch-edited | 4 | `floorplan.tcl`, `power_plan.tcl`, `place_bondpads.tcl`, `<BLOCK>.mmmc` |
| in sync | 4 | `i2c_`, `<BLOCK>.upf`, `filler.tcl`, `<BLOCK>.io` |

Resolving those four non-synced files to their HEAD-side history collapses them
to **exactly two commits the branch does not have**:

- **`15b0501` — "the D2D transmit word clocks never resolved their master".**
  587 insertions across **three** files. `constraints.sdc` 495→699 (branch 542:
  it has its own relative-path repair and is missing HEAD's ~204 lines — the
  DIVERGED case, needing a hand 3-way merge, not a fast-forward);
  `tidelink_constraints.sdc` 470→583 (branch 470, drops it whole);
  `ethernet_constraints.sdc` 350→561 (branch 350, drops it whole).
- **`2dca8ae` — "the constrained clock ratio is a register's reset value, not
  the silicon".** `qspi_constraints.sdc` 123→205 (branch 123, drops it whole).

So the risk is not drift, it is **silent reversion of two identified constraint
fixes**, one of them a D2D word-clock master resolution spanning three files.
That lands on already-soft ground: the writeback census covers 5 of 33 clocks
and none of the 16 D2D word clocks, so hold on those domains was fiction
*before* anything was reverted — and the gate still read 20/20 green. Merging
the branch's constraints wholesale would remove the fix and change no gate.

**Restate step 1b in commit terms, not file terms.** Per-file diffing finds the
symptom; `git log <base>..HEAD -- <migrated paths>` names the cause, in one
command, as a reviewable list of commits to re-apply or 3-way merge. It is
cheaper and it cannot miss a file.

**And the window is closing** (f9's point, verified): of the four branch-edited
files, `floorplan.tcl` and `power_plan.tcl` are **dirty in main right now**.
They are cheap to take from the branch only while HEAD hasn't touched them since
base. The moment either commits they move into DIVERGED and need hand-merging
against the branch's edits to the same file — and these are the two most
actively-edited physical files in the project. HEAD moved from `2dca8ae` to
`5245456` during this audit, so this is not hypothetical. The merge cost grows
per hour; this changes the decision from "when convenient" to "before 58
commits".

### The real terminal condition

> `ASIC/genus-innovus/` may be removed when `ASIC/asic-flows` is no longer the
> engine for any flow this repo must be able to run — **not** when the last
> file has been moved out of it.

Until then the directory must keep existing and keep offering those nine names.
That is a decision about retiring the *fallback*, which is David's call and is
explicitly out of scope this week ("must be able to build a chip at every
point"). Everything below is written to that condition.

---

## 2. Classification

106 files reference `genus-innovus` (57 non-`.md`, 49 `.md`). In the non-`.md`
files there are 193 reference lines: **121 are comments/prose** and ~72 are
outside comments — and even that over-counts, because it catches Python
docstrings, `echo` strings and heredoc text. The load-bearing set is small.

This matters for the plan: the dominant failure mode of retirement here is not
a broken build, it is **~121 provenance citations becoming confidently wrong**.
Most cite legacy files *by line number* (`config.tcl:127`, `drc_project.mk:62`).
e6's rule — rewire pages that INSTRUCT, leave pages that RECORD — is the right
one and I am adopting it unchanged.

### (a) MUST REPOINT — toolkit needs it, currently reads legacy

| file | site | status |
|---|---|---|
| `scripts/ci/asic_stage_report.sh` | `:30` `ASIC_DIR="${ASIC_DIR:-…}"` | done on `fd3085b`; **NO-OP defect open — §3** |
| `scripts/ci/package_submission.sh` | `:24` same | done on `fd3085b`; **NO-OP defect open — §3** |
| `ci/signoff.yaml` | 20 executable refs, 7 stages | done on `fd3085b` |
| `.github/workflows/asic-gds.yml` | `:79` env, `:245-246` upload globs | done on `fd3085b` |
| `Makefile` | `:39` `ASIC_DIR` | done on `fd3085b` (1a) |
| `ASIC/klayout-drc/Makefile` | `:16` `DESIGN_DIR` | **OPEN** — not in either worktree |
| `ASIC/klayout-drc/scripts/run_drc.sh` | `:45` `DEFAULT_GDS` | **OPEN** — not in either worktree |
| `verif/lint/full/prove_fix.sh` | `:170,180,211` exec `run_lec.sh` | **OPEN** |
| `verif/lint/full/selftest_prove.sh` | `:57,92,138,157` mirrors the path into a sandbox | **OPEN** |

The last four are the residue. The two `verif/lint/full` scripts are the
awkward pair: the lint *prover* shells out to a genus-innovus script, so lint's
self-verification inherits the legacy tree's lifetime.

### (b) LEGACY-ONLY — dies with the flow

`ASIC/genus-innovus/{Makefile, drc_project.mk, lvs_project.mk}`, the stage
drivers (`2b_pnr_place_eval.tcl`, `4b_pnr_route_eval.tcl`, `restream.tcl`,
`probe_*.tcl`, `rail/*`), `provenance.spec`, `scripts/compare_syn.sh`.
`scripts/ci/overnight_20260809.sh` (already retired on `fd3085b`).
Also `.gitignore:22,104,105` and `runs/` — note `runs/*/config/` holds snapshot
copies of the calibre scripts and is gitignored; the 4.8 GB of baselines are
separately frozen at `/home/dam1n19/SoCLabs/_cutover_freeze_2026-08-17/`.

### (c) DUAL — must serve both flows until cutover

- **`ASIC/genus-innovus/scripts/` itself** — the nine contract names, real
  files or symlinks. The class-(c) item of record. f9's proposed exit (env-var
  with `../scripts/` literal as fallback, using `flow.mk:331-335`'s
  `ASIC_MMMC_FILE`/`ASIC_FLOORPLAN_TCL`/`ASIC_IO_FILE`/`ASIC_POWER_PLAN_TCL`)
  is **untested** and cannot be tested by `make`; see §4.
- `ASIC/eth-chiplet/design.mk` `LEGACY_ASIC_DIR` + `legacy-paths` bridge —
  deleted on `a18825b`, correct once the inversion lands (f9 owns).
- `ASIC/common.mk`, `ASIC/rom_gate.mk`, `ASIC/rom_build.mk`.
- `scripts/ci/new_run.sh` — still drives the legacy flow deliberately.

### (d) SUBMODULE — record, do not change

- `ASIC/asic-flows` — **the blocker**. Lab-shared; editing it has lab-wide
  blast radius. Off the table.
- `nanosoc-multicore-system/syn/asic/common.mk`, `tidelink/docs/BUG_REGISTRY.yaml`.
- `ASIC/asic-toolkit/examples/nanosoc_eth_chiplet/` — a **stale divergent copy**
  of the same collateral (`floorplan.tcl` 15,434 B vs live 24,504 B). A decoy
  that will be mistaken for the real thing. Should be deleted or marked, but it
  is submodule content — record it for the toolkit's owner.

---

## 3. Gates that cannot fail — measured, not inferred

Asked to flag class-(a) items that resolve to a missing path and **no-op rather
than fail**. Two found, both reproduced.

**3.1 `scripts/ci/asic_stage_report.sh` — a clean report for a directory that
does not exist.**

```
$ ASIC_DIR=/tmp/does-not-exist bash scripts/ci/asic_stage_report.sh route
exit=0
### ASIC stage: `route`
_no baseline to compare against_
| metric | this run | baseline | delta |
| setup WNS (ns) | n/a | n/a |  |
… every row n/a
```

Exit 0, well-formed markdown. Rendered into a CI summary or PR comment after a
toolkit run whose `ASIC_DIR` was not repointed, this reads as a *report*, not an
error. `fd3085b` repoints the default but does not add an existence guard.

**3.2 `scripts/ci/package_submission.sh` — an exit-0 tapeout bundle containing
nothing.**

Against a directory holding a single 7-byte file named like the GDS:

```
exit=0
  + nanosoc_eth_chiplet_pads.gds
  ! MISSING nanosoc_eth_chiplet_pads_pnr.v
  ! MISSING nanosoc_eth_chiplet_pads_pnr.sdf
  ! MISSING nanosoc_eth_chiplet_pads_syn.sdc
== …/nanosoc_eth_chiplet_pads_d6deeb8-dirty_20260817T185209Z.zip (4.0K) ==
```

The zip: the 7-byte "GDS", a MANIFEST, nothing else. Correctly named with the
git SHA and ready to send.

Two compounding causes. The script fail-closes only on GDS *presence* (`-s`),
never on the completeness of the deliverable set — it prints `! MISSING` and
proceeds. And `reports/` was copied by
`[ -d "$REP" ] && cp -rp … && echo`, whose failure is exempt from `set -e`
because it is not the last command of the `&&` list: an absent `reports/` left
**no trace at all**, not even a warning.

The MANIFEST is scrupulous about declaring what the *design* lacks, which makes
this worse — it cannot declare a file that was never copied, because it only
hashes what reached the staging dir. A thinner bundle yields a shorter, still
perfectly self-consistent manifest.

**This defect survives `fd3085b`** (that commit changes only the header/path
region; lines 43-47 are untouched). Fix prepared as a patch against `fd3085b`'s
version — completeness tracking plus a `SUBMISSION_GATE=report` escape matching
the existing `ROM_GDS_GATE=report` idiom — at:

```
<scratchpad>/package_submission_completeness_gate.patch
```

Handed to e6, who owns the submission bundle. **Not applied to the main
checkout**: my first attempt collided with `fd3085b`'s edit to the same hunk and
was reverted.

A guard for 3.1 is prepared the same way, at
`<scratchpad>/asic_stage_report_rundir_guard.patch`. `fd3085b` *documents* this
exact failure mode in a comment ("would have produced a full, well-formed table
of `n/a` for a run that completed perfectly") but does not guard it.

Both patches: apply cleanly to `fd3085b` (`patch --dry-run`), `bash -n` clean,
and re-tested against the cases that produced the defects —

| case | before | after |
|---|---|---|
| incomplete bundle | exit 0, 4 KB zip | **exit 1**, 4 deliverables named (incl. `reports/`) |
| incomplete + `SUBMISSION_GATE=report` | — | exit 0, warns |
| **complete** bundle (negative control) | exit 0 | **exit 0**, 5 artefacts — no false positive |
| stage report, missing run dir | exit 0, full `n/a` table | **exit 1**, names `ASIC_DIR`/`RUN_TAG` |

**3.3 signoff.yaml target sweep.** All 14 stages plus the `check:` blocks
resolved against the real make databases. In committed HEAD exactly one stage
named a target no makefile defines — `romlibs-gds-check`, stage 8 (rom-gds).
**e6's report is confirmed: that stage can never have run.** No other stage is
broken; the two "absent" script paths a path-scan flags (`scripts/lec/run_lec.sh`,
`scripts/run_calibre_lvs.sh`) are both inside comments — false positives.

One merge hazard: the defect is being fixed **two different ways at once**.
`fd3085b` repoints signoff.yaml to `romlibs-verify-gds`; someone in the main
checkout has *added* a `romlibs-gds-check` target at
`ASIC/genus-innovus/Makefile:165` (uncommitted, delegating to
`romlibs-verify-gds`). Both are sound and they do not textually conflict, but
after merge one is redundant. Pick one — the `fd3085b` side is the better
choice, since the added target is a legacy-tree indirection that would itself
need retiring.

**Qualification (8a, and it corrects the emphasis above): that is not licence
to delete the local forwarder now.** While the migration is parked, the
uncommitted forwarder at `genus-innovus/Makefile:165` is the *only* thing making
that stage runnable — main's `ci/signoff.yaml:303` still issues the broken call.
And `fd3085b`'s replacement routes `romlibs-check` through
`ASIC/eth-chiplet/design.mk` + `RUN_TAG`, so it cannot land ahead of the
migration. **Retire the forwarder *with* `fd3085b`, never before it.** Read as
"redundant, drop it", this note would send the stage back to dying on "No rule
to make target".

Also note stage 8's input, `ASIC/genus-innovus/outputs/nanosoc_eth_chiplet_pads.gds`,
does not currently exist. That path is fail-closed (`romlibs-verify-gds` exits 1
on a missing or empty `ROM_GDS`), so it is a red stage, not a silent one.

---

## 4. The one remaining blocker, and why it is not mine to clear this week

Handed over by e6: `ASIC/genus-innovus/scripts/calibre/` was **not** migrated,
so `DRC_SCRIPT` is deliberately unset on `a18825b`.

State right now: 4 tracked files modified and 2 untracked generators
(`make_project_deck.sh`, `make_project_header.py`), all uncommitted, under
active edit by another session.

**I did not move it, and I recommend nobody does this week.** Moving files
another session is mid-edit on, in a 15-session shared working tree, is the
highest-risk action available. It also cannot be sequenced safely until that
session's work is committed — and 8a's §2 trap applies directly: `git diff
--name-only` reports a rename by its *destination*, so the naive collision
check returns empty precisely when rename *sources* are dirty. Use
`git diff --name-status -M … | awk '{print $2}'`.

Sequencing: calibre migrates **after** the calibre session commits, and after
the gating run, not before.

### A warning about how this gets verified

f9's, and I re-checked the shape myself: the `../scripts/` literals resolve at
**Innovus runtime, hours into a run**. No `make -n`, no target-existence sweep,
and none of the gate evidence quoted in either worktree can see breakage here.
`make -C ASIC/eth-chiplet check` passing is not evidence about this contract.
Use f9's licence-free tclsh resolution recipe in
`docs/tapeout/33-toolkit-legacy-decoupling.md`.

And per e6: **do not gate the cutover on equivalence to the legacy flow.** It
is not measurable — `baseline_08-06` and `08-07` differ by 16% instance count
and 151.8 ns TNS yet both report an identical *saturated* 1000/318/680
connectivity triple.

---

## 5. Plan

**This week — no deletions, and no merge.** f8 killed the merge task on 8a's
analysis and chose **park-both**. Nothing lands until 58's gating run is off the
legacy design files; the resume is a *rebuild from then-current HEAD as
copy-not-move*, not a rebase. Steps 1 and 1a below are therefore for **whoever
resumes the migration**, not for this week. They are duplicated in
`ASIC_MIGRATION_BLOCKERS.md` §8 so they survive the park.

1. *(on resume)* Land the migration. Resolve the double-fix in §3.3 at merge
   time, honouring the ordering qualification there.
1a. ~~*(on resume, precondition)* Commit the 12 staged symlinks.~~
   **SATISFIED at `72febb7`** — verified independently against the commit tree:
   12 mode-120000 entries, zero dangling, contract 9/10, `legacy-paths` 7/7
   (§1). The hazard was real: merging `a18825b` alone breaks the toolkit loudly
   and legacy silently. Do not merge at `a18825b`; merge at the tip or later.
1b. *(NEW precondition — and it is time-critical, not resume-time)*
   **Re-apply the two commits the branch reverts.** `git log cd8b47d..HEAD --`
   over the 12 migrated paths names them exactly: `15b0501` (D2D transmit word
   clocks, 587 insertions across `constraints.sdc` + `tidelink_` + `ethernet_`)
   and `2dca8ae` (QSPI clock ratio). `constraints.sdc` is DIVERGED and needs a
   hand 3-way merge; the other three can be taken from HEAD. Nothing in §3
   catches any of it — a resolving symlink to a reverted file passes every gate
   in this document (§1).
   **Re-apply as commits, not as line edits.** `15b0501` is not purely
   additive — 587 insertions *and 59 deletions* — so a reviewer working from
   "the branch is missing some lines" will reconstruct it wrong (f9).
   **Time-critical:** `floorplan.tcl` and `power_plan.tcl` are dirty in main
   now. While HEAD hasn't touched them since base they are a clean take from the
   branch; the moment either commits they become DIVERGED too. HEAD moved twice
   during this audit. Recommend f8 treat the merge as **before 58 commits**,
   not "when convenient" — this is the one item where parking has a rising
   cost rather than a flat one.
2. ~~Commit `include …rom_build.mk` in `ASIC/common.mk`.~~ **RESOLVED — and it
   is a worked example of §6, so it is kept rather than deleted.**
   e6 raised it; I confirmed it absent from committed `ASIC/common.mk` at
   HEAD `2dca8ae` (19:15) and reported it as blocking. It landed 46 minutes
   later in `c444f10` (20:01) and now sits at line 648, with `ASIC/common.mk`
   clean. f8 re-measured at a later HEAD, found it present, and concluded it
   "was never a blocker" — that conclusion is wrong, but their *measurement* is
   correct, and so was mine. The fact changed between them.
   Separately, 58 hit the same item because a `grep | head -2` stopped at two
   comment mentions before reaching line 648 — a real error, and independent of
   this report.
3. Apply the §3.2 completeness gate (patch handed to e6). A bad bundle must not
   be indistinguishable from a good one at the exit status **before** anything
   is packaged for a shuttle.
4. Add an existence guard to `asic_stage_report.sh` (§3.1). Small; unowned.
5. Close the four open class-(a) items: `ASIC/klayout-drc/{Makefile,scripts/run_drc.sh}`
   and `verif/lint/full/{prove_fix.sh,selftest_prove.sh}`.
6. Mark or delete the stale toolkit example collateral (§2d) so it cannot be
   mistaken for live.

**Not this week — the actual retirement, gated on David's decision to stop
supporting the `asic-flows` fallback.**

7. Migrate `scripts/calibre/` once its session lands (§4).
8. Prove f9's env-var exit for the `../scripts/` contract, via tclsh, not make.
9. Retire `asic-flows` as an engine. Only then does `ASIC/genus-innovus/`
   become a directory of symlinks and dead drivers, and only then is deleting
   it a no-op rather than a breaking change.
10. Sweep the ~121 prose citations last, when the paths they cite have stopped
    moving. Rewriting them earlier produces confidently-wrong line numbers —
    the failure e6 correctly refused to introduce.

**Definition of done for "asic-toolkit is the only flow":** step 9. Everything
before it is preparation, and steps 1-6 are what the clean-GDS goal actually
needs.

---

## 6. How this audit was corrected, and the rule that falls out

Five factual errors were made across four sessions producing this finding and
its companions. **Every one was caught by a peer rather than by its author**,
including all of mine. None was sloppiness — each was a *correct reading taken
at the wrong level*:

| error | level read | level that mattered |
|---|---|---|
| symlinks "satisfy the contract at `a18825b`" (mine) | worktree working dir | the commit |
| "zero symlinks anywhere" (8a) | main's index | another worktree's index |
| "all 12 signoff targets exist" (f9) | main working tree | HEAD, which CI clones |
| 12 files "re-added with divergent content" (8a) | through the links — `diff` follows them | the link blobs |
| "the branch reverts constraints" read as shipping-branch breakage (mine) | the worktree branch | `fix/tag-ram-gwen` |

The mechanical traps behind them, worth knowing before touching relocated
collateral: `git show <rev>:<path>` on a mode-120000 entry returns the **link
text**, not content; `diff`/`cmp` **follow** symlinks; a worktree has **its own
index**, invisible to main; and a link resolving says nothing about the
**currency** of what it resolves to.

**The level axis includes TIME, and that is the sixth instance.** The
`rom_build.mk` item in §5.2 is the worked example: absent from committed
`ASIC/common.mk` at `2dca8ae` (19:15), present at `c444f10` (20:01), 26 commits
landing on the branch in between. Two sessions measured it 46 minutes apart,
both correctly, and reached opposite conclusions — one of which ("it was never a
blocker") retro-attributes an error that was not made. **In this repo `HEAD` is
not a stable referent**, so a claim carrying only a command and a tree level is
still under-specified: it needs the **commit SHA and the clock time** it was
taken at. Every measurement in this document is stamped for that reason.

**The rule (8a's, and it is the transferable output):** exchange the *command
and the level*, not the conclusion. Every correction tonight landed because
someone posted the exact invocation and the other person could run it somewhere
else. A conclusion cannot be re-levelled; an invocation can.

Two corollaries this audit earned:

- **Carry a control through the same probe.** A known-good and a known-bad
  target run through the identical check turns "we disagree" into "we measured
  different things" in one command.
  8a's extension, which is the more useful half: a control is also what
  separates a **null result from a clean bill**. A check whose corpus can be
  empty goes green for the same reason a check that genuinely passes goes green.
  That is not a hypothetical here — it is the shape of the `legacy-paths` gap
  above (7 of 12 asserted, green either way), of both §3 NO-OPs, and of HAL's
  zero-CLKDMN result elsewhere in this repo. Any gate that can pass by having
  nothing to look at needs a control, or it is decoration.
- **A commit that is supposed to ADD something and reports zero insertions is
  not doing it.** `git show --stat a18825b` → `12 files changed, 0 insertions(+),
  0 deletions(-)`. Both 8a and I ran that command early and read it as
  confirmation of a clean pure rename — which it is. Neither of us registered
  that it simultaneously proves *no symlink is in the commit*, because a symlink
  blob is content and would have appeared as an insertion. One output, two
  questions, and we each asked only the first.

Companion write-ups: `ASIC_MIGRATION_BLOCKERS.md` §9-§10 (8a) and
`docs/tapeout/33-toolkit-legacy-decoupling.md` (f9).
