# 33 — Decoupling the toolkit from genus-innovus: why the naive move fails

**Status:** analysis complete, change DEFERRED by decision. Nothing moved in the live tree.
**Date:** 2026-08-17
**Scope:** the physical inputs `ASIC/eth-chiplet/design.mk` still takes from the legacy flow — four
by declaration in `design.mk`, twelve once the actual in-flight move is counted.

**If you read one thing here, read *presence, content, provenance* at the end of the status
section.** Every check this document builds — link present, mode `120000`, not dangling, contract
9/10, `legacy-paths` 7/7 — passes on a symlink pointing at a **stale** file. A resolving symlink to
the old `constraints.sdc` serves the design without the D2D word-clock master fix while every gate
reads green. Presence is automated here; content and provenance are not. That is the same shape as
the antenna false-clean and the `elab-strict` false-green, reached independently.

## The claim this document corrects

The migration was scoped as "four lines in `design.mk` reach into the legacy flow; `git mv` the
files into the toolkit and repoint the four variables." The four lines are real:

    design.mk:189  FLOORPLAN_TCL  ?= $(LEGACY_ASIC_DIR)/scripts/floorplan.tcl
    design.mk:194  POWER_PLAN_TCL ?= $(LEGACY_ASIC_DIR)/scripts/power_plan.tcl
    design.mk:208  MMMC_FILE      ?= $(LEGACY_ASIC_DIR)/scripts/$(BLOCK).mmmc
    design.mk:211  IO_FILE        ?= $(LEGACY_ASIC_DIR)/scripts/$(BLOCK).io
    design.mk:69   LEGACY_ASIC_DIR := $(NANOSOC_ETH_CHIPLET_HOME)/ASIC/genus-innovus

They are not the coupling. They are the only part of the coupling written in Make, which is why
they are the only part that gets noticed.

## The real coupling: a `../scripts/` literal inside a shared lab submodule

The legacy flow does not find these files through a variable. It finds them through a hardcoded
relative path resolved against the tool's working directory — and the code holding that path is
**`ASIC/asic-flows`, a submodule shared lab-wide** (`SoC-Labs/ASIC-Flow.git`, branch `lpddr4-pll`).
It is invoked at `ASIC/genus-innovus/Makefile:364` as `$(INNOVUS) $(ASIC_FLOWS_DIR)/2_pnr_setup.tcl`.

Inventory of every literal that addresses the four migration targets:

| Site | Line | Statement |
|---|---|---|
| `ASIC/asic-flows/Cadence/2_pnr_setup.tcl` | 29 | `read_mmmc ../scripts/${block_name}.mmmc` |
| `ASIC/asic-flows/Cadence/2_pnr_setup.tcl` | 51 | `source ../scripts/floorplan.tcl` |
| `ASIC/asic-flows/Cadence/2_pnr_setup.tcl` | 52 | `source ../scripts/power_plan.tcl` |
| `ASIC/genus-innovus/scripts/floorplan.tcl` | 112 | `read_io_file ../scripts/nanosoc_eth_chiplet_pads.io` |
| `ASIC/genus-innovus/scripts/2b_pnr_place_eval.tcl` | 179 | `set EVP_MMMC ../scripts/${block_name}.mmmc` |
| `ASIC/genus-innovus/scripts/2b_pnr_place_eval.tcl` | 779 | `source ../scripts/floorplan.tcl` |
| `ASIC/genus-innovus/scripts/2b_pnr_place_eval.tcl` | 805 | `source ../scripts/power_plan.tcl` |
| `ASIC/genus-innovus/scripts/probe_pg_build.tcl` | 76 | `read_mmmc ../scripts/${block_name}.mmmc` |
| `ASIC/genus-innovus/scripts/probe_pg_build.tcl` | 124 | `source ../scripts/floorplan.tcl` |
| `ASIC/genus-innovus/scripts/probe_pg_build.tcl` | 168 | `source ../scripts/power_plan.tcl` |
| `ASIC/genus-innovus/scripts/probe_macros.tcl` | 30 | `read_mmmc ../scripts/${block_name}.mmmc` |

A `git mv` moves the files. It does not move these literals. The legacy flow then dies at
`2_pnr_setup`, which is the fallback the migration rule requires to keep working.

**Editing `asic-flows` is off the table** — it is shared collateral; the blast radius is every
design in the lab on this flow.

## `../scripts/` is a contract directory, not a legacy folder

Widening the grep past the four targets, the shared submodule demands ten entries from `../scripts/`:

    ${block_name}.mmmc   present      floorplan.tcl        present
    config.tcl           present      power_plan.tcl       present
    cts_setup.tcl        present      place_bondpads.tcl   present
    dft_setup.tcl        MISSING*     postplace.tcl        present
    preplace.tcl         present      route_setup.tcl      present

    * behind a conditional at 1_synthesis.tcl:59 — DFT is off, so it is never sourced.

`ASIC/genus-innovus/scripts/` (37 files) is the **contract directory that `asic-flows` is written
against**. That is the structural reason genus-innovus cannot be deleted while `asic-flows` is the
engine — it is not sentiment about a fallback.

Counted two ways, independently: **10 distinct files** demanded (above), across **41 `../scripts/`
literals, 13 of them live in `Cadence/`**. Both numbers describe the same surface — files versus
occurrences — and neither is a subset of the other's problem.

### Why no repointing can satisfy both flows

The literal `../scripts/X` encodes a layout assumption, not just a location: it presumes **all design
data sits in ONE directory, sibling to the run directory**. The toolkit contract deliberately fans
the same data across **five** (`floorplan/`, `power/`, `mmmc/`, `constraints/`, `config/`).

There is therefore no value of that literal that satisfies both flows at once. This is the point at
which the task stops being a repointing exercise: it is a change to a repository this project does
not own, and it needs an owner there. "The toolkit is the only flow" is a cross-repo task, not a
this-week one.

## Why the obvious proof cannot detect the breakage

The proposed acceptance test was: after repointing, `make -C ASIC/eth-chiplet` must resolve all four
paths and elaborate.

That test is blind to this failure. It exercises the **Make variables**. The breakage is in Tcl
`source` / `read_mmmc` statements resolved against the tool's CWD, executed by Innovus at the
`2_pnr_setup` stage — hours into a run. A green `make` here would have been a false pass, and the
failure would have surfaced exactly the way this project's failures characteristically surface.

Any acceptance test for this change has to resolve the paths **through the run directory as the tool
sees it**, not through Make.

## Option A — measured, not assumed

Move the files to the toolkit's contract paths; leave a tracked symlink at each old path.

Measured in a throwaway `git worktree` at `d6deeb8` (removed afterwards; live tree never touched):

1. **Destination is already declared by the toolkit.** `ASIC/asic-toolkit/mk/flow.mk:209-212`:

       FLOORPLAN_TCL  ?= $(ASIC_DIR)/floorplan/floorplan.tcl
       IO_FILE        ?= $(ASIC_DIR)/floorplan/$(BLOCK).io
       POWER_PLAN_TCL ?= $(ASIC_DIR)/power/power_plan.tcl
       MMMC_FILE      ?= $(ASIC_DIR)/mmmc/$(BLOCK).mmmc

   With `ASIC_DIR := $(CURDIR)` (`ASIC/eth-chiplet/Makefile:19`) these resolve to
   `ASIC/eth-chiplet/{floorplan,power,mmmc}/`. **So the correct end state deletes design.mk:189/194/
   208/211 outright rather than repointing them** — the toolkit default already points where the
   files would land. Four fewer lines, not four rewritten lines.

2. **Git stores symlinks, not copies.** After `git mv` + `ln -s`, all four old paths are mode
   `120000`. One content blob per file; no second instance of the duplicate-collateral problem.

3. **Two-hop resolution works.** The `legacy-paths` bridge symlinks `$(RUN_DIR)/scripts` →
   `$(LEGACY_ASIC_DIR)/scripts`; the new file symlinks sit inside that. From `WORK_DIR`, all four of
   `../scripts/*` resolve through dir-symlink → file-symlink → moved file.

4. **Tcl `source` follows the chain.** Verified with `tclsh` driving the real two-hop shape: the
   source succeeded, and a sourced file's own CWD-relative read (`floorplan.tcl:112`'s pattern)
   found its target — 128 lines read.

5. **`[info script]` still reports the legacy directory**, because Tcl resolves the directory
   symlink but not the final component. Anything computing paths from `[info script]` keeps seeing
   `genus-innovus/scripts`. Only `restream.tcl:86` and `selftest_route_gate.tcl:29` use that idiom,
   and neither is a moved file.

6. **Negative control.** Deleting the symlinks — i.e. the naive `git mv` — immediately breaks
   `../scripts/{floorplan.tcl,power_plan.tcl,*.mmmc}` and turns `read_io_file`'s target unreadable.
   The failure predicted above is the failure observed.

## What Option A does *not* buy

It relocates the bytes. It does **not** decouple the toolkit from genus-innovus, because
`floorplan.tcl:112` still says `../scripts/...`, so a toolkit run still needs the `legacy-paths`
bridge and therefore still needs `genus-innovus/scripts` to exist.

The clean lever already exists — `flow.mk:331-335` exports the four as environment variables:

    ASIC_MMMC_FILE   ASIC_FLOORPLAN_TCL   ASIC_IO_FILE   ASIC_POWER_PLAN_TCL

So `floorplan.tcl:112` can become compatible with both flows:

    if {[info exists ::env(ASIC_IO_FILE)]} {
        read_io_file $::env(ASIC_IO_FILE)
    } else {
        read_io_file ../scripts/nanosoc_eth_chiplet_pads.io
    }

Toolkit runs take the explicit path; legacy runs, which set no such variable, keep the literal.
**Untested** — this is a design proposal, unlike everything above it.

## Adjacent hazard: never export `ASIC_DIR`

All four physical inputs are derived from `$(ASIC_DIR)` (`flow.mk:209-212`), and:

    ASIC/asic-toolkit/mk/flow.mk:56    ASIC_DIR ?= $(CURDIR)
    ASIC/asic-toolkit/mk/flow.mk:313   export ASIC_DIR

`?=` takes the **environment**. So an `ASIC_DIR` exported by any parent make silently overrides the
`$(CURDIR)` default in every nested make that relies on it, and `flow.mk:313` propagates the winner
further down. `ASIC/eth-chiplet/Makefile:19` uses a hard `:=` and is immune; the toolkit's own
default is not.

The failure is not an error — it is four physical inputs quietly read from the wrong directory. Pass
it per-invocation (`$(MAKE) -C <dir> ASIC_DIR=<dir>`) or use a distinct variable name. This matters
most in combination with the next section: an inherited `ASIC_DIR` that lands on the toolkit's
example directory finds a complete, plausible, stale set of physical inputs and reports success.

**The committed root Makefile avoids this trap — record why, because the obvious next edit
reintroduces it.** Verified against `fd3085b:Makefile`:

    :49  ASIC_DIR        := $(CHIPLET_HOME)/ASIC/eth-chiplet     <- set, NOT exported (0 exports)
    :50  ASIC_DIR_LEGACY := $(CHIPLET_HOME)/ASIC/genus-innovus
    :144+ $(MAKE) -C $(ASIC_DIR) RUN_TAG=$(RUN_TAG) <stage>      <- passes RUN_TAG, never ASIC_DIR

The trap is the next commit, not this one: exporting `ASIC_DIR` so `scripts/ci` can see it is a
natural-looking change, and it is precisely the change that redirects `FLOORPLAN_TCL` and
`MMMC_FILE` into the stale example copy below, silently. If `scripts/ci` needs the value, give it
its own variable rather than exporting this one.

### One concept, two spellings

    ASIC/eth-chiplet/design.mk:69   LEGACY_ASIC_DIR
    <root Makefile> fd3085b:50      ASIC_DIR_LEGACY

Different files, no include relationship, so no parse-time collision — but two names for one concept
across the two halves of the same migration. Settle on one before the root Makefile lands; it is
free now and archaeology later.

## Landmine: the toolkit example is a stale divergent copy

`ASIC/asic-toolkit/examples/nanosoc_eth_chiplet/` already contains `floorplan/`, `power/`, `mmmc/`
and `constraints/` — the whole migration target, pre-populated at the exact paths `flow.mk:209-212`
defaults to. It is **tracked** (22 files in the toolkit submodule), so every fresh clone gets it.
All four physical inputs are diverged from the live ones:

| Contract path | example | live | |
|---|---|---|---|
| `power/power_plan.tcl` | 17,227 B | 38,053 B | DIVERGED — under half the design |
| `floorplan/floorplan.tcl` | 15,434 B | 24,504 B | DIVERGED |
| `mmmc/nanosoc_eth_chiplet_pads.mmmc` | 10,500 B | 12,146 B | DIVERGED |
| `floorplan/nanosoc_eth_chiplet_pads.io` | 7,079 B | 6,052 B | DIVERGED |

(Live sizes as of 2026-08-17; `power_plan.tcl` and `floorplan.tcl` were being edited concurrently,
so the live column drifts. The divergence does not.)

This is the duplicated-constraints problem already reported independently against
`examples/.../constraints/*.sdc`, but far larger: it covers every physical input. These are stale,
not variants — the example power plan is missing more than half the design. Anyone who points
`ASIC_DIR` at the example, inherits it via the export hazard above, or copies from it, gets a
complete and plausible set of inputs that are not the ones being taped out, **with no error raised**.

This is the failure mode most likely to produce a silently wrong chip for the next project that
adopts the toolkit. It should be deleted or neutered before the cutover.

## Status of the in-flight implementation — RESOLVED at `72febb7`

Option A was implemented independently in a session worktree (`agent-a402bee1222b2421b`), with a
destination layout matching `flow.mk:209-212` exactly. It briefly carried a merge hazard that is
worth keeping on the record, because the way it hid is reusable.

**The hazard (commit `a18825b`).** `git show --stat` reported *12 files changed, 0 insertions(+),
0 deletions(-)* — pure renames, no new files. Every contract entry was **absent** from
`ASIC/genus-innovus/scripts/` in that tree. The twelve symlinks that make the move safe existed only
in that worktree's **index**, staged (`A `) and uncommitted. Merging `a18825b` would have landed the
naive move documented above: the toolkit failing loudly at `make legacy-paths` (all seven asserted
paths moved) and the legacy flow failing silently inside Innovus.

**Why it hid.** `ls -la` in the worktree shows twelve correctly resolving symlinks. The working tree
was safe; the commit was not. Working-tree inspection is not evidence about a commit, and two
sessions independently read the safe state.

**The fix, verified here against the commit tree, not the working tree:**

- All 12 symlinks present at mode `120000` under `ASIC/genus-innovus/{scripts,inputs}/`.
- **No dangling links** — every target resolves to a path that exists inside tree `72febb7`.
  (Git stores a dangling symlink without complaint; that would have reproduced the original silent
  failure exactly, so it is worth checking separately from presence.)
- `asic-flows` contract: **9 of 10 resolve**. `dft_setup.tcl` remains absent — pre-existing,
  conditional at `1_synthesis.tcl:59`, DFT off. Not a regression.
- `legacy-paths` assert list: **all 7 resolve**.

`72febb7` also repairs six relative paths that the move exposed as only ever having worked by
accident — `constraints.sdc`'s four `source` lines, three in `config.tcl`, and the `.mmmc`'s
`../outputs/<BLOCK>_syn.sdc` — and lifts `cpf-patch` into `hooks/post_synth.tcl`. Reported by the
implementing session; not independently re-verified here.

**Merge the branch tip, not `a18825b`.**

### RESOLVED is true of the contract, NOT of the content

Every check built above — link present, mode `120000`, not dangling, contract resolves,
`legacy-paths` 7/7 — passes on a symlink pointing at a **stale file**. That is the one failure the
symlink design cannot catch, and the branch is carrying it.

Classifying all twelve moved files against the merge-base (`cd8b47d`), comparing `72febb7`'s copy to
the current `HEAD` copy:

| Class | Files | Meaning |
|---|---|---|
| **DIVERGED** | `constraints.sdc` | both sides edited since base — needs a real 3-way merge |
| **STALE** | `qspi_`, `tidelink_`, `ethernet_constraints.sdc` | identical to base; never received HEAD's edits |
| edited by `72febb7` | `floorplan.tcl`, `power_plan.tcl`, `place_bondpads.tcl`, `<BLOCK>.mmmc` | HEAD unchanged since base — take the branch |
| in sync | `i2c_constraints.sdc`, `<BLOCK>.upf`, `filler.tcl`, `<BLOCK>.io` | no action |

### The per-file view is the symptom; the cause is two commits

That table is the right *action* list and the wrong *diagnosis*. Resolving those four files to their
HEAD-side history collapses them to exactly two commits — the branch is not drifting per file, it is
reverting two identified fixes. One command shows it, over all twelve migrated paths:

    git log --oneline cd8b47d..HEAD -- <the 12 migrated paths>
      15b0501  ASIC/constraints: the D2D transmit word clocks never resolved their master
      2dca8ae  ASIC/qspi: the constrained clock ratio is a register's reset value, not the silicon

    15b0501   3 files, 587 insertions(+), 59 deletions(-)
                constraints.sdc           partially dropped (branch has its own path repair, not HEAD's)
                ethernet_constraints.sdc  dropped whole  (350 vs 561)
                tidelink_constraints.sdc  dropped whole  (470 vs 583)
    2dca8ae   1 file, 82 insertions(+)
                qspi_constraints.sdc      dropped whole  (123 vs 205)

So the DIVERGED file and two of the three STALE files are **the same commit**, partially and wholly
dropped. Prefer this query to a per-file diff: it names the cause rather than the symptom, cannot
miss a file, and yields a merge list — re-apply two reviewable commits — instead of four
independent-looking content problems. Note `15b0501` is not purely additive (59 deletions), so it
cannot be re-applied by appending.

**Why `15b0501` is the worst one to lose.** It lands on ground that was already soft: the writeback
census covers 5 of 33 clocks and none of the 16 D2D word clocks, so hold on those domains was
already fiction *and the gate read 20/20 green through it*. A branch that silently removes the
word-clock master resolution would therefore change no gate at all. Same failure mode as the symlink
case, compounded — presence is audited, content is not, and timing intent is not either.

**The merge window is closing, and that is the actionable part.** Two of the four "edited by
`72febb7`" files are dirty in the working tree right now — `floorplan.tcl` (+34, the fp1505 work)
and `power_plan.tcl` (+240). Both are currently safe to take from the branch *only* because HEAD has
not changed them since base. The moment either is committed, it moves into the DIVERGED row and
needs hand-merging against `72febb7`'s edits to the same file. The cost of this merge grows with
every hour the branch sits unmerged.

**Verification rule this implies — presence, content, provenance.** Three audits, not one, and only
the first is automated here:

1. **Presence** — does the path resolve? Every check in this document tests this. A resolving
   symlink to a stale file passes all of them.
2. **Content** — does the file match then-current HEAD? Not implied by presence.
3. **Provenance** — which commits touched these paths and are they all present? Not implied by
   content, and this is the one that actually caught the problem. Two of these files are byte-current
   *relative to base* and still wrong, because what went missing was a single commit's intent spread
   across three files. Only the commit-level query sees that.

For any relocated or rebuilt collateral, run `git log <base>..HEAD -- <the moved paths>` before
merging. A path resolving is not a path being current, and a path being current is not the change
being intact.

### Scope correction

The real in-flight set is **twelve files, not the four** in `design.mk`:

    scripts/ -> eth-chiplet/{floorplan,power,mmmc}/   floorplan.tcl, power_plan.tcl,
                                                      place_bondpads.tcl, filler.tcl,
                                                      <BLOCK>.io, <BLOCK>.mmmc
    inputs/  -> eth-chiplet/{constraints,config}/     constraints.sdc, ethernet_, i2c_,
                                                      qspi_, tidelink_constraints.sdc, <BLOCK>.upf

`place_bondpads.tcl` is a contract entry (`4_pnr_route.tcl:44`) and `filler.tcl` is in the
`legacy-paths` assert list, so both carry the same risk as the original four.

## Sequencing

Do this **after the gating run streams a verified GDS**, which is the moment genus-innovus can be
frozen. Reasons not to do it now, in order of severity:

1. `asic-flows` cannot be edited, so until `floorplan.tcl:112` carries the env-var fallback above,
   the move buys relocation without decoupling.
2. `floorplan.tcl` and `power_plan.tcl` are dirty from live sessions (+34 and +205 lines at the time
   of writing) and one is on the week's critical path. `git mv` would carry uncommitted work.
3. Ownership of `power_plan.tcl`'s edits is unattributable — the working tree is shared across
   sessions.

Order when it does happen: `.io` first (the `legacy-paths` assert list covers `scripts/$(BLOCK).io`,
so a mistake fails loudly at Make time), `.mmmc` last (three consumers, none asserted, all silent).
This is the reverse of the intuitive order.

## The trap that cost four sessions an evening: *which tree did you measure?*

With many sessions on one checkout plus per-session worktrees, a repository is not one state. It is
at least five, and a measurement is meaningless without naming which one it came from:

| Level | Probe that reads it | Who consumes it |
|---|---|---|
| main working tree | `grep`, `make -q`, `ls -la` | nobody — it holds every session's uncommitted edits |
| main `HEAD` | `git grep <rev>`, worktree at `HEAD` | **CI clones this** |
| worktree working dir | `ls -la`, `readlink`, `[ -L ]` | nobody |
| worktree index | `git status --porcelain` (`A `) | nobody |
| worktree commit | `git ls-tree`, `git show --stat` | **what a merge actually lands** |

Four measurements were taken here in one evening, none of them careless, and three were reported at
the wrong level:

- Symlinks reported present in `a18825b` — read from the worktree's **working dir** via `readlink`,
  reported as a property of the **commit**. The commit had none.
- Symlinks reported absent repo-wide via `git ls-files -s` — correct about **main's index**, taken
  as a refutation of the above. Main's index cannot see another worktree's index.
- `gate: block` targets in `ci/signoff.yaml` reported as **12 of 12 present** via `make -q` —
  correct about the **main working tree**, wrong about **HEAD**, where it is **11 of 12**:
  `rom-gds` → `make -C ASIC/genus-innovus romlibs-gds-check` does not exist, the rule living only in
  an uncommitted change. CI clones HEAD, so a local `make -q` "disproving" a CI failure proves
  nothing. **The HEAD number, 11 of 12, is the one that counts.**
- The same target reported absent by `git grep` at HEAD — correct, and the only one at the level
  that mattered.

Two cheap habits remove the whole class:

1. **State the level with the number.** "Present in the worktree's index" and "present in the
   commit" are different claims; only the second survives a merge.
2. **A probe that cannot produce a positive has not produced a negative.** This is the nastier
   failure, because a dead probe and a true negative are the same output: an empty result.

   It happened here. The first HEAD scan for `romlibs-gds-check` used a `\b`-anchored ERE that
   matched nothing **anywhere** — including the working tree, where the rule demonstrably exists at
   `ASIC/genus-innovus/Makefile:165`. It printed a clean "not found" for HEAD and was one step from
   being reported as confirmation. What caught it was a **known-good** control (`^romlibs-check:`,
   which must hit), not the known-bad one. Carry both: the known-bad shows the probe can say no, the
   known-good shows it can say yes. Only the second detects a dead probe.

The same shape appears in this document's own reasoning, and is worth naming. The prediction that
the `${PIPESTATUS[0]}` risk would surface as a **hard error under dash** was a plausible mechanism,
asserted without measurement. Measured, the reachable case is the opposite and worse: `ksh` has no
`PIPESTATUS`, so the subscript expands to empty, bare `exit` takes the pipeline's last status —
`tee`, always 0 — and a failing lint gate passes **silently green**. Plausible-but-unmeasured is the
same defect as the dead regex, wearing different clothes.

The `git show --stat` line is the fastest tell available: *12 files changed, 0 insertions(+)* cannot
describe a commit that adds twelve symlinks.

## Reproducing

    git worktree add --detach <scratch> HEAD
    # in the worktree: git mv the four files to floorplan/, power/, mmmc/
    # then ln -s ../../eth-chiplet/<dest> back at each old path
    # build the bridge: ln -sfn <worktree>/ASIC/genus-innovus/scripts <rundir>/scripts
    # from <rundir>/work:  test -r ../scripts/floorplan.tcl   etc.
    # drive a tclsh probe that sources through the chain -- tclsh needs `< /dev/null`

No Innovus licence is needed: every claim above is filesystem path resolution plus Tcl `source`
semantics, both reproducible with `tclsh`.
