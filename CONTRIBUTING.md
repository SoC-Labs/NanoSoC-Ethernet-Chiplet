# Working in this repo

Start here if you are about to make your first change.

Two things make this repo different from most, and both are covered below.
**Section 1** is the ordinary workflow. **Section 2 onward is a set of hazards
that come from many sessions sharing one checkout** — a dozen or more concurrent
agents and humans committing to the same branch within minutes of each other.
Read section 1 to get moving; read section 3 *before your first commit*, because
the shared `.git/index` is the single most common cause of lost work here.

---

## 1. Getting set up and making a change

```sh
./scripts/bootstrap.sh          # every submodule, recursively — not `clone --recursive`
source set_env.sh               # source it; do not execute it
make check                      # licence-free gate: vendor-check + chip-boundary + lint
```

`make help` lists every target grouped by purpose. The gates you will actually use:

| Command | What it proves | Needs |
|---|---|---|
| `make check` | no vendor collateral is tracked; the boundary spec covers every RTL port exactly once; Verilator lint is clean | nothing |
| `make elab` | the integration top elaborates with every port connected once | VCS |
| `make regress` | every data-plane simulation proof, as one pass/fail table | VCS |
| `make cdc` / `make elab-strict` | CDC and strict-elaboration gates | Xcelium/HAL |
| `make asic-status` | which backend stages have run in this build directory | nothing |

### The change loop

1. **Branch.** Never work directly on the default branch.
2. **Make the change**, and keep it scoped. This repo is the *integration* level:
   if the fix belongs in `tidelink`, `tidechart` or `nanosoc-multicore-system`,
   make it there and roll the pin — do not fork the file into `src/rtl/`.
   `src/rtl/local_overrides/` exists for the case where you genuinely must
   deviate from a submodule or from vendor IP; document the deviation.
3. **Clean the directory this bench actually builds into, and prove the clean
   took.** `rm -rf build sim_build*` — check with `ls -d` which of those exist
   rather than assuming, because it differs per bench. Then confirm
   `recompiling module <your dut>` in the log. Treat `up to date` on the
   simulator binary as a **failed clean**, not a convenience: flist RTL is not a
   make dependency, so nothing else will tell you. One stale `simv` once cost
   four commits to land a change whose RTL was correct the whole time.
4. **Show red-to-green in one session, on one build.** The bug's regression test
   must fail before your change and pass after. An already-red test that stays
   red is not evidence.
5. **Run the OWNING integration gate**, not just the test you care about — the
   whole default `MODULE` set, or you will not see what you broke. Isolated-bench
   evidence and a peer sign-off are necessary and never sufficient.
6. **Commit** using the discipline in section 3. Whoever lands, runs the gate —
   not the reviewer, not the prototype's author.

### Rules that hold regardless

- **A fix and its guard are separate commits, each gated on its own — and the
  combined state gets its own gate run.** Two independently-green changes are not
  a green composite.
- **Declare what your prototype harness forced.** Every `force` or tie-off in a
  proto bench is a premise the integration may not supply. Name the shared signals
  your correctness depends on staying stable, so the next person changing that
  logic knows what they are standing on.
- **Red means revert, and the revert message carries the diagnosis** — what you
  ruled out, and with which command. Before you attribute a red to a component,
  re-derive it from a build you have proven fresh.
- **This is an active tapeout repo.** Comment and documentation edits are free.
  Behaviour changes to a script, Makefile or RTL module are not: gate them.
- **Never modify anything under the shared IP library trees** — the roots behind
  `$IP_LIBRARY_ROOT`, `$ARM_IP_LIBRARY_PATH` and the physical-IP equivalent. They
  are lab-wide vendor collateral and edits corrupt builds across the whole lab.
  Read access is fine and expected. If a fix seems to need a change there, copy
  the file into the project tree, rewire the flist to the local copy, and document
  the deviation. Refer to these locations **by variable, never by absolute path** —
  a pre-commit check enforces this, because a literal path is an inventory of
  which PDK and IP this site is licensed for.
- **`ASIC/asic-flows` and `ASIC/asic-toolkit` are shared submodules.** Changes
  there have lab-wide blast radius and are not yours to make from this repo.

---

## 2. Concurrency hazards — read before your first commit

> Everything from here on follows from one fact: **many sessions share this
> checkout, including one `.git/index`.**

### 2.1 Say which level a measurement came from

The repo is **several disagreeing states at once**:

> main's index · main's working tree · main at HEAD (what CI clones) ·
> a worktree's working dir · a worktree's index · a specific commit's tree

On 2026-08-18 four sessions auditing one migration produced **five** factual errors.
None was sloppiness — every one was a *correct reading taken at the wrong level*,
and every one was caught by a peer rather than its author.

**The level axis includes TIME.** `HEAD` is not a stable referent here; 26 commits
landed on one branch in a single evening. Stamp a claim with the **commit SHA and
the clock time**.

Mechanical traps worth knowing before you measure:

- `git show <rev>:<path>` on a **mode-120000** entry returns the **link text**,
  not the target's content.
- `diff` and `cmp` **follow** symlinks — comparing "two files" can silently
  compare one file with itself.
- A worktree has **its own index**, invisible to `git ls-files` in main.
- `git status` / `git diff --name-only` report a rename by its **destination**, so
  the naive collision check returns empty precisely when rename *sources* are
  dirty. Use `git diff --name-status -M | awk '{print $2}'`.
- A symlink **resolving** says nothing about the **currency** of what it resolves
  to. Presence, content and provenance are three separate audits.
- Cached tracking refs lie. To ask whether something is pushed, ask the remote:
  `git ls-remote origin refs/heads/<branch>`, not `git rev-list @{u}..HEAD`.
- **Re-list before you quote a number.** A run directory or `calibre_runs/`
  listing from earlier in your own session is a guess, not a fact.

**When you disagree with another session, exchange the command and the level —
never the conclusion.** A conclusion cannot be re-levelled by the person receiving
it; an invocation can. Carry a control through the same probe: a known-good and a
known-bad input turns *"we disagree"* into *"we measured different things"* in one
command. A control is also what separates a **null result from a clean bill** — a
check whose corpus can be empty goes green for exactly the same reason a check that
genuinely passes goes green.

Worked examples: [`docs/asic/ASIC_GENUS_INNOVUS_AUDIT.md`](docs/asic/ASIC_GENUS_INNOVUS_AUDIT.md) §6.

### 2.2 The shared index will revert somebody's work

`.git/index` is shared by every session using this checkout. On 2026-08-18 the
branch carried **nine** commits in one night whose subject was some form of
*"restore X, reverted by a stale snapshot"*.

It fails in **two directions**, and most people only know about the first.

**Direction 1 — your commit reverts THEM.** `git read-tree HEAD` snapshots a tree.
If HEAD moves before you commit, your index still describes the **old** HEAD, so
committing it records every path added since as **deleted**. The files on disk are
untouched; only their tracked state is destroyed, which is why nobody notices until
someone's work has vanished from HEAD. The obvious check misses it:
`git diff --cached --name-status` compares the index against **HEAD**, and relative
to your stale snapshot nothing looks staged.

**Direction 2 — their commit reverts YOU.** This needs no careless committer. The
shared index was populated by another session at an **earlier HEAD**, so it holds
that HEAD's blobs. You commit correctly from a private index; HEAD now carries your
new content; **the shared index still carries your pre-commit blob**. The next
person to commit from it — with a perfectly ordinary explicit pathspec — restores
the old content and reverts you.

It renders in `git status` as an unremarkable `MM`, which reads as *"I have
unstaged edits"*, not as *"a reversal of my commit is loaded"*:

| what you committed | how the stale index shows it |
|---|---|
| a **newly tracked** file | staged **deletion** (`D `) — the index lacks it |
| an **already tracked** file you modified | staged **modification** (`M `) holding the old blob |

Measured five times in one session — every one of those commits correct and
explicitly pathspec'd, each leaving a reversal of itself primed, including the
commit that first documented this hazard. All five were repaired with a path-scoped
`git reset` without disturbing other sessions' staged entries. **A clean
`git show --stat` is not the end of the job**: it looks backwards at what you wrote,
and this hazard is in front of you.

### 2.3 The commit discipline — all four steps

Steps 1–3 protect other people from you. **Step 4 protects you from the next
person.** Do not skip it because your commit verified clean.

1. **Build the index and commit from it in ONE shell invocation.** Never across
   two — the gap is the whole vulnerability.

   ```bash
   BEFORE=$(git rev-parse HEAD)
   export GIT_INDEX_FILE=$(mktemp)      # never the shared index
   git read-tree "$BEFORE"
   git add -- path/one path/two          # explicit FILE paths; never -A, never .
   git commit -F msg.txt
   SHA=$(git rev-parse HEAD); unset GIT_INDEX_FILE
   ```

2. **`git diff --cached --name-status` as the LAST step before committing**, not an
   earlier one. Run earlier it tells you nothing.

3. **`git diff --name-status "$BEFORE" "$SHA"` AFTER the commit.** This is the one
   that catches the stale-snapshot case, because it compares two commits rather
   than the index against a moving HEAD. Confirm the file list is exactly what you
   intended and there are no `D` lines you did not mean. Equivalently
   `git show --stat --diff-filter=D "$SHA"` should be empty.

4. **`git diff --cached --name-status -- <the paths you just committed>`.** If your
   paths appear **at all**, a reversal of your commit is primed in the shared
   index. Repair it, path-scoped:

   ```bash
   git reset -q HEAD -- path/one path/two
   git diff --cached --name-only            # confirm OTHER sessions' staged work survived
   ```

   `git reset` with a pathspec syncs only your entries.

**Never run a bare `git reset`, `git checkout .`, `git stash` or `git add -A`
here.** Those are shared-state operations and will destroy another session's staged
work. Someone else's half-finished edit is always in the tree.

**Verify against your own commit's parent** (`git diff <sha>^ <sha>`), never
`HEAD~1`. Other sessions commit while your simulation runs; `HEAD~1` is routinely a
stranger's commit, and a revert against it is a silent no-op.

---

## 3. Where things are documented

| | |
|---|---|
| the design, pins, power, reset, registers | [`docs/design/`](docs/design/) |
| lint, CDC, elaboration, testbench architecture | [`docs/verification/`](docs/verification/) |
| backend flow audits, constraints, DRC/LVS inventories | [`docs/asic/`](docs/asic/) |
| the from-scratch Genus/Innovus guide | [`docs/tapeout/`](docs/tapeout/00-index.md) |
| KR260 bench and board bring-up | [`docs/bringup/`](docs/bringup/) |
| the die-to-die wedge investigation | [`docs/debug/`](docs/debug/) |
| active plans | [`docs/plans/`](docs/plans/) |
| dated records and correspondence — **not** current reference | [`docs/history/`](docs/history/) |
