# ASIC migration to asic-toolkit — why the lane is parked

**Status: PARKED.** Decided 2026-08-17. Nothing from either migration worktree
is to land until 58's gating run is off the legacy design files.

All measurements in this document were taken 2026-08-17 against **HEAD =
`2dca8ae`** on `fix/tag-ram-gwen`, with 58 mid-flight on the gating run. The
dirty-file facts are a snapshot of a shared checkout with ~15 live sessions in
it; **re-measure before acting on them.** The structural findings (§2, §3, §5)
do not expire.

The goal this serves: `ASIC/asic-toolkit` becomes the only flow in the repo.
The governing rule from `ASIC/asic-toolkit/MIGRATION_NANOSOC_ETH.md` still
holds — **the project must be able to build a chip at every point in the
migration** — and it is the rule the parked work breaks.

## 1. What is parked

Two orphaned worktrees, two halves of one migration, both based on `cd8b47d`
(an ancestor of HEAD, so both rebase forward in principle):

| Worktree | Commit | Content |
|---|---|---|
| `.claude/worktrees/agent-a402bee1222b2421b` | `a18825b` | 12 files, `git mv` of the design data into the toolkit's contract layout. Plus **uncommitted** working-tree changes — see §3. |
| `.claude/worktrees/agent-a7f381ef513bb530b` | `fd3085b` | 31 files, +832/−366. Rewires every caller (root Makefile, both CI orchestrators, `scripts/ci` wrappers, docs). Clean tree. |

Ordering constraint, if they ever do land: `fd3085b` rewires callers to
`ASIC/eth-chiplet/{constraints,floorplan,mmmc,power}`, **all four absent in
HEAD** (only `config/` exists). It must not land before the `a402bee` half, or
the toolkit path points at nothing.

## 2. THE TRAP: destination paths don't collide, source paths do

**This is the finding most likely to be re-lost.** A reviewer checking whether
the two changesets are safe to merge will reach for the obvious test:

```sh
comm -12 <(git diff --name-only cd8b47d a18825b | sort) \
         <(git status --porcelain | awk '{print $NF}' | sort -u)
```

It returns **empty**, and empty is wrong. `git diff --name-only` reports a
rename by its **destination**, so this compares the new `ASIC/eth-chiplet/…`
paths — which of course nobody has dirty, because they don't exist yet in HEAD.
The files at risk are the ones the rename **leaves**. Test those instead:

```sh
git diff --name-status -M cd8b47d a18825b | awk '{print $2}' | sort   # $2 = OLD path
```

Against that list, five of `a18825b`'s twelve rename sources were dirty in the
shared checkout, and **four are on the protect list for 58's gating run**:

```
ASIC/genus-innovus/inputs/constraints.sdc
ASIC/genus-innovus/inputs/ethernet_constraints.sdc
ASIC/genus-innovus/inputs/tidelink_constraints.sdc
ASIC/genus-innovus/scripts/floorplan.tcl
ASIC/genus-innovus/scripts/power_plan.tcl
```

The `a402bee` **uncommitted** set collides on seven, adding
`ASIC/eth-chiplet/design.mk` and `ASIC/genus-innovus/scripts/config.tcl`.

I made this exact mistake on the first pass and reported "no collisions" before
catching it. Anyone re-running the safety check should assume the naive form is
the one they typed.

## 3. The `a402bee` working tree is a stale rewrite, not extra work to preserve

The uncommitted changes in that worktree were described as work to capture into
the commit. They are not.

**Mechanism (corrected).** They restore the 12 legacy paths as **symlinks**, not
as copies — all 12 are staged mode `120000`, e.g.
`ASIC/genus-innovus/scripts/floorplan.tcl` → `../../eth-chiplet/floorplan/floorplan.tcl`.
An earlier revision of this section described them as re-added regular files with
divergent content; that was a measurement artifact — `diff`/`cmp` follow symlinks,
so a comparison against HEAD silently read the *eth-chiplet* copy. The line counts
below are real; what they measure is the toolkit-side file, seen through the link.
(Symlink discovery: 38, path corrected by f9. See §8.)

**Two distinct problems, previously conflated:**

- **Stale, not edited.** `inputs/qspi_constraints.sdc` resolves to a copy that is
  **byte-identical to `cd8b47d`** at 123 lines against HEAD's 205. It never
  received `2dca8ae`. The entire C3 open-decision block — recording that the QSPI
  `-divide_by 2` ratio is a register reset value and not silicon — is simply
  missing, and via the symlink **both** flows would serve the pre-`2dca8ae`
  constraint.
- **Edited, not stale.** Five toolkit-side copies differ from their `cd8b47d`
  sources by **237 lines in total** — `constraints/constraints.sdc` 59,
  `floorplan/floorplan.tcl` 59, `mmmc/…pads.mmmc` 52,
  `floorplan/place_bondpads.tcl` 47, `power/power_plan.tcl` 20. These are real,
  undocumented edits made in that worktree.

**Consequence — corrected, and the correction matters more than the original
claim.** An earlier revision said the symlinks make `genus-innovus` *stop being*
an independent fallback. That was wrong on the date: **it never was one** (via
38). On HEAD, `ASIC/eth-chiplet/design.mk` already reads the legacy tree
directly —

```
 69: LEGACY_ASIC_DIR := $(NANOSOC_ETH_CHIPLET_HOME)/ASIC/genus-innovus
189: FLOORPLAN_TCL   ?= $(LEGACY_ASIC_DIR)/scripts/floorplan.tcl
194: POWER_PLAN_TCL  ?= $(LEGACY_ASIC_DIR)/scripts/power_plan.tcl
271: SDC_FILES       := $(LEGACY_ASIC_DIR)/inputs/constraints.sdc
```

— so there has only ever been **one copy of each file**, read by both flows. The
symlinks do not create the coupling, they **invert its direction**: before, a
legacy-side edit silently changed the toolkit; after, a toolkit-side edit
silently changes legacy. The `qspi` case is the second kind.

This *strengthens* the warning rather than softening it. Had independence died at
the symlinks, it could be recovered by not symlinking. Since it never existed,
**constraint 1 can only mean "something builds"** — it has never meant "we retain
an independent control to attribute a regression against." Anyone planning to
diff legacy against toolkit output to isolate a migration regression should know
there is nothing to diff.

Any rebuild therefore takes content **from HEAD**, never from a worktree.

**Status on the branch (checked at tip `5245456`):** none of this has landed.
`fix/tag-ram-gwen` still carries the 205-line C3 version of
`inputs/qspi_constraints.sdc`, zero mode-`120000` entries, and no
`ASIC/eth-chiplet/{constraints,floorplan,mmmc,power}`. The park is intact — see
§9 for why a report of "live at the tip" is about a different branch.

Note also that `a18825b`'s own message claims "Pure rename, no content change".
That is true of the commit and **false of the commit plus its working tree**.

## 4. `a18825b` alone also breaks the governing rule

Setting the working tree aside: `a18825b` is a pure rename, so it *deletes*
`genus-innovus`' `floorplan.tcl`, `power_plan.tcl`, the SDCs and the `.mmmc`.
At that commit the fallback flow cannot build a chip. Neither half alone, nor
both together, satisfies the constraints as written.

## 5. The real coupling: `../scripts/` inside a shared lab submodule

Found by f9 from the caller side; independently re-measured here. `git mv`
breaks the legacy Tcl **regardless of what `design.mk` says**, because the flow
scripts address the project's design data by a hardcoded relative literal.

- **41** `../scripts/` literals in `ASIC/asic-flows` overall.
- **13** of them live (non-comment) in `ASIC/asic-flows/Cadence/` — the tool
  path the legacy flow actually runs.
- Four name files `a18825b` renames away:

| Literal | Live refs in `Cadence/` | Renamed by `a18825b`? |
|---|---|---|
| `../scripts/floorplan.tcl` | 1 (`2_pnr_setup.tcl:51`) | yes |
| `../scripts/power_plan.tcl` | 1 (`2_pnr_setup.tcl:52`) | yes |
| `../scripts/place_bondpads.tcl` | 1 (`4_pnr_route.tcl:44`) | yes |
| `../scripts/${block_name}.mmmc` | 1 (`2_pnr_setup.tcl:29`) | yes |
| `../scripts/config.tcl` | 4 | no — stays put |

The deeper problem is the *shape*, not the count. `../scripts/` presumes the
design data sits in **one directory** that is a sibling of the run directory —
the flow runs `cd $(WORK_DIR); genus -f …`, so `../scripts/` resolves relative to
the work directory. The toolkit's contract layout deliberately fans that data out
across `{config,constraints,floorplan,mmmc,power}/`.

**Qualification (added after measurement).** An earlier revision said this "is not
fixable by repointing a variable". Too strong — it is *already bridged*.
`design.mk`'s `legacy-paths` target (:512) creates
`$(RUN_DIR)/{scripts,inputs}` as symlinks to `$(LEGACY_ASIC_DIR)/{scripts,inputs}`,
which is exactly what lets the literal keep resolving under the toolkit. The
accurate statement is that **the bridge is why `genus-innovus` cannot be deleted**:
the literal is satisfied by pointing it back at the legacy tree, so retiring that
tree requires changing the shared submodule, not the project. The coupling is
real; it is currently paid for with a symlink rather than unsolved.

And `ASIC/asic-flows` is **shared lab collateral** —
`https://github.com/SoC-Labs/ASIC-Flow.git`, branch `lpddr4-pll`, shared with
other projects. Changing those literals is a change to a shared repository, not
a project-side edit, and it needs its own owner and its own review. It was dirty
locally when measured (`M README.md`, untracked `Mentor/`, `site.env.example`).

## 6. What a correct rebuild looks like

When the park lifts, the `a402bee` half is **rebuilt from then-current HEAD**,
not rebased:

1. **Copy, not move.** `genus-innovus` keeps a working set until the legacy flow
   is genuinely retired. Nothing is deleted this week; `genus-innovus` is the
   fallback and 58 is on it.
2. **Take content from HEAD**, never from the parked worktree — §3 is why.
3. **Land only when the protect-list files are quiescent**, and re-run the §2
   source-path collision test at that moment, not from this document's snapshot.
4. **Settle the `../scripts/` question first** (§5). Until the shared submodule
   is dealt with, a copy is the only layout where both flows work.

## 7. Correction to the vendor-bypass record

`fd3085b` was committed using `VENDOR_CHECK_BYPASS` without authorisation.
Whether to accept that bypass is David's call; this section only fixes the
evidence offered for it.

The figure in circulation — *"121 `$TSMC_65_HOME` hits before and after"* — **does
not reproduce.** Measured `cd8b47d` → `fd3085b`: **126 → 127** matching lines.

The +1 is fully explained and benign. A documentation sentence naming the
`$TSMC_65_HOME` mount and the `tsmc65pdkgrp` unix group was **re-wrapped across two
lines** by the `ASIC_DIR` rewrite, so one matching line became two. Same tokens,
no foundry value, no geometry, no new file. **Net new disclosure: zero.** The
conclusion the bypass rested on holds; the number quoted for it does not.

**Carry this caveat with it:** the above is a hand census of the diff, **not the
gate's verdict**. `asic-toolkit`'s `ci/check-vendor-collateral.sh` (at `8ed82b6`)
only offers its line-scoped mode as `--new-lines-only`, which requires
`--staged`; staging was not authorised for this session. Its `--rev` mode is
file-scoped and returns 645+ findings that are overwhelmingly pre-existing site
paths in `ASIC/common.mk` and the workflows — it cannot answer "what did this
commit add". Getting the gate's own word requires someone authorised to stage.

## 8. Merge-time notes for whoever resumes

**`romlibs-gds-check` is being fixed two ways at once.** Both fixes address the
same real defect — `ci/signoff.yaml` invoked a target no makefile in this repo
ever defined, so the stage could only ever have died with *"No rule to make
target"*. Measured state:

| Where | What it does |
|---|---|
| `ci/signoff.yaml:303` (main, committed) | still calls `make -C ASIC/genus-innovus romlibs-gds-check` — the broken call |
| `ASIC/genus-innovus/Makefile` (main, **uncommitted**) | adds a `romlibs-gds-check` target that forwards to `romlibs-verify-gds`, passing `ROM_GDS`/`ROM_GDS_GATE` |
| `fd3085b` `ci/signoff.yaml:284` | deletes the indirection entirely: `make -C ASIC -f common.mk romlibs-verify-gds` |

They do not textually conflict, but one becomes redundant. At merge time, prefer
the `fd3085b` side — the added target is a legacy-tree indirection that would
need retiring anyway (via 38).

**Do not read that as licence to delete the local target now.** While the
migration is parked, the uncommitted forwarder is the only thing that makes that
signoff stage runnable at all; `fd3085b`'s replacement also routes `romlibs-check`
through `ASIC/eth-chiplet/design.mk` and `RUN_TAG`, so it cannot land ahead of
the migration. Retire the forwarder *with* `fd3085b`, not before it.

**Symlinks — RESOLVED, and they exist in no mergeable form.** Three sessions
measured this at three different levels and got three different answers; all
three were locally correct. The reconciliation:

| Level | Result |
|---|---|
| Main checkout, `git ls-files -s` | **zero** tracked symlinks in the whole repository |
| Main checkout, `ASIC/` on disk (excluding run/build output) | exactly **one**: `tech_wrappers/tsmc65/local_overrides/…lef` → `../generated/…patched.lef`, the local-override pattern working as intended |
| Commit `a18825b` (`git ls-tree -r`) | **absent** — 12 files changed, 0 insertions, 0 deletions; no `120000` entry anywhere |
| The `a402bee` worktree's **index** | **12 staged symlinks**, mode `120000`, at the legacy paths |

A worktree carries its own index, which is why `git ls-files` in the main
checkout cannot see them. They are hand-staged compensating links, not per-run
tool output — but they live **only** in that index: not in main, and not in the
commit.

So the accurate statement is **not** "don't treat them as disposable residue".
It is that **staging them is a merge precondition**. Merging `a18825b` as it
stands breaks both flows at once — the toolkit loudly (`design.mk`'s legacy-paths
assertion names 7 files, all absent from that tree) and the legacy flow silently,
at Innovus runtime, via the `../scripts/` literals in §5. And even *with* the
links, §3 applies: what they point at is stale in one file and edited in five.

## 9. Verification log — two hand-off claims, re-run independently

Both were taken from another session and re-measured here rather than accepted.
Both **confirm**, and re-running them found a gap neither statement mentioned.

**(a) `a18825b` breaks the toolkit loudly — CONFIRMED.** `design.mk:69` still
defines `LEGACY_ASIC_DIR`; `legacy-paths` at `:512` asserts **7** files readable
through the bridge. All 7 are absent from that tree, so the target fails.

**THE GAP: the assertion covers only 7 of the 12 files the rename moves.** These
five are **not** asserted:

```
scripts/floorplan.tcl        scripts/power_plan.tcl
scripts/place_bondpads.tcl   scripts/nanosoc_eth_chiplet_pads.mmmc
inputs/nanosoc_eth_chiplet_pads.upf
```

So `legacy-paths` is not a safety net for the migration — it catches the SDC/`.io`/
`filler.tcl` set and lets the floorplan, power plan, bondpads, MMMC and power
intent through untested. Those are precisely the files consumed later, at tool
runtime.

**(b) The legacy flow breaks silently — CONFIRMED, by a mechanism worth naming.**
It is not that a missing `source` is quiet; Tcl raises on it. It is that
**the tools exit 0 after a failed script.** The repo documents this against
itself:

```
ASIC/genus-innovus/Makefile:19   # 17-silent-noops — both Genus and Innovus exit 0 after failing.
ASIC/genus-innovus/Makefile:206  ## The artefact test is not belt-and-braces: Genus exits ZERO on a failed script,
```

Combined with the gap above: for the five unasserted files, a18825b produces a
Tcl error inside the tool, an exit status of 0, and a green make. That is the
silence — not an absent diagnostic, but a discarded one.

**A resolving symlink defeats every check we have.** 38 verified `72febb7` as
12 mode-`120000` entries, zero dangling, contract 9/10, legacy-paths 7/7 — all
green, while `qspi_constraints.sdc` resolved to stale content. Link-resolution
checks cannot see staleness. On resume, **diff rebuilt collateral against
then-current HEAD per file**, do not merely check that it resolves (38's step 1b).

**Where `72febb7` actually is.** It was reported as "live at the tip". It is the
tip of **`worktree-agent-a402bee1222b2421b`** (parent `a18825b`), and it is *not*
an ancestor of `fix/tag-ram-gwen` (tip `5245456` when checked). Its lineage is off
`cd8b47d` and never contained `2dca8ae`, which is *why* its `qspi` resolves to
123-line content byte-identical to the base — not a regression introduced there,
but the base it was branched from. That confirms §6 (rebuild from then-current
HEAD, do not rebase) rather than contradicting it, and the staleness remains a
rebuild-time concern, correctly quarantined in a parked branch.

## 10. Provenance

- §1, §2, §4, §7 and the §9 re-verifications measured in this session.
- §3 is joint: the divergence was measured here, the **symlink mechanism** came
  from 38 (path) and f9 (correcting 38's attribution to the commit), and the
  **"never independent"** correction is 38's.
- §5 originated with f9 (caller side); the inventory here is an independent
  re-measurement, and the `legacy-paths` bridge qualification was added after
  measurement corrected an overreach of mine.
- §8's symlink reconciliation is 38's path plus f9's correction; §9's assertion
  gap and exit-0 mechanism were found here while re-running 38's two claims.

**Correction history — read this before trusting any single measurement.** Five
attribution errors were made and caught across three sessions in one evening, and
**every one was a locally-correct measurement read at the wrong level**:

| Error | Caught by |
|---|---|
| `readlink` in a worktree's working directory attributed to the commit | f9 |
| `git diff --name-only` compared against destinations, reporting "no collisions" | self, on re-check |
| `diff`/`cmp` followed symlinks, attributing toolkit content to a legacy path | 38 |
| `make -q` treated as a proof of target existence | f9 |
| `72febb7` reported "live at the tip" — it is a parked worktree branch, not `fix/tag-ram-gwen` | self |

Not one was caught by the session that made it. The practical rules that fall out:
`git show` on a mode-`120000` entry returns **link text**, not content; `diff` and
`cmp` **follow** links; a worktree has **its own index**, invisible to
`git ls-files` in the main checkout; a rename is reported by its **destination**,
so a collision check must test old paths (§2); and a symlink that **resolves**
still tells you nothing about whether its target is current (§9).

Two cheap probes that would each have caught an error above before it travelled
(both via 38):

- **Carry a control through the same probe.** Every dispute here collapsed the
  moment someone ran a known-good *and* a known-bad input through the identical
  check. A probe that only ever sees the suspect case cannot tell you it works.
- **Read the `--stat` line.** `git show --stat a18825b` says *12 files changed,
  0 insertions(+), 0 deletions(-)* — the signature of a pure rename. Any commit
  that is supposed to **add** something and reports zero insertions is not doing
  it. That single line settles "are the symlinks in the commit or only in the
  worktree" without resolving anything.

**The transferable output: exchange the command and the level, not the
conclusion.** A conclusion cannot be re-levelled by whoever receives it; an
invocation can be re-run somewhere else. Every correction here landed because
someone posted the exact command. Companion write-ups:
`ASIC_GENUS_INNOVUS_AUDIT.md` §6 (38) and f9's doc 33 — the three
triangulate rather than duplicate.
- `fd3085b` also already contains the root-Makefile rewiring (+135/−15:
  `ASIC_DIR` → `ASIC/eth-chiplet`, `ASIC_DIR_LEGACY`, the
  `pnr_place`/`pnr_cts`/`pnr_route`/`pnr_all` → `place`/`cts`/`route`/`all`
  aliases, `asic-legacy-gds`). That work was separately assigned to another
  session by hand; if the migration resumes, check for duplication before
  writing it twice.
