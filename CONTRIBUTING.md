# Working in this repo

This repository is routinely worked on by **many sessions at once** — a dozen or
more concurrent agents and humans, sharing one checkout, committing to the same
branch within minutes of each other. Almost everything below follows from that
one fact. Read it before your first commit.

---

## 1. The shared index will revert somebody's work

`.git/index` is shared by every session using this checkout. It is the single
most common cause of lost work here: on 2026-08-18 the branch carried **nine**
commits whose subject was some form of *"restore X, reverted by a stale
snapshot"*, in one night.

It fails in **two directions**, and most people only know about the first.

### Direction 1 — your commit reverts THEM

`git read-tree HEAD` snapshots a tree. If HEAD moves before you commit — another
session lands a commit in the gap — your index still describes the **old** HEAD,
so committing it records every path added since as **deleted**. The files on
disk are untouched; only their tracked state is destroyed, which is why nobody
notices until someone's work has vanished from HEAD.

The obvious check misses it: `git diff --cached --name-status` compares the index
against **HEAD**, and relative to your stale snapshot nothing looks staged. It
prints clean while the damage is already loaded.

### Direction 2 — their commit reverts YOU

This one is not in most people's discipline, and it needs no careless committer.

The shared index was populated by another session at an **earlier HEAD**, so it
holds that HEAD's blobs. You commit correctly from a private index; HEAD now
carries your new content; **the shared index still carries your pre-commit
blob**. The next person to commit from the shared index — with a perfectly
ordinary explicit pathspec — restores the old content and reverts you.

Measured **five times in one session** — see the table below. Immediately after
committing a **+81 / −14** change:

```
$ git diff --cached --stat -- <the paths I had just committed>
 ... | 65 ++------
 ... | 30 +----
 2 files changed, 14 insertions(+), 81 deletions(-)
```

The exact inverse of what had just landed, sitting primed. It renders in
`git status` as an unremarkable `MM`, which reads as *"I have unstaged edits"*,
not as *"a reversal of my commit is loaded"*.

Two shapes:

| what you committed | how the stale index shows it |
|---|---|
| a **newly tracked** file | staged **deletion** (`D `) — the index lacks it |
| an **already tracked** file you modified | staged **modification** (`M `) holding the old blob |

**It is not theoretical and it is not rare.** Five commits in one session, every
one of them correct and explicitly pathspec'd, each left a reversal of itself
primed in the shared index:

| the commit | what was primed against it |
|---|---|
| an audit doc (new file) | `D` — staged deletion of all 563 lines |
| a klayout fix (+81 / −14) | `M` — 14 insertions / 81 deletions, the exact inverse |
| **this page** (new file) | `D` — a deletion of the file documenting the hazard |
| LVS inputs (+58) | `M` — 58 deletions |
| an LVS repoint (+96 / −53) | `M` — 53 insertions / 96 deletions, the inverse |

The third row is the point: step 4 caught a primed reversal of the very commit
that introduced step 4, minutes after it was written. All five were repaired
with a path-scoped `git reset`, and in every case the other sessions' staged
entries were still intact afterwards. **A clean `git show --stat` is not the end
of the job** — that check looks backwards at what you wrote, and this hazard is
in front of you.

Corroborating (measured by other sessions the same day, not by the author of
this page): three sessions each reported a stale index carrying **different**
blob hashes for the same file over the course of one day, and it later measured
clean. That is the index moving repeatedly, which is what this mechanism
predicts.

---

## 2. The commit discipline — all four steps

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

2. **`git diff --cached --name-status` as the LAST step before committing**, not
   an earlier one. Run earlier it tells you nothing.

3. **`git diff --name-status "$BEFORE" "$SHA"` AFTER the commit.** This is the
   one that catches the stale-snapshot case, because it compares two commits
   rather than the index against a moving HEAD. Confirm the file list is exactly
   what you intended and there are no `D` lines you did not mean. Equivalently
   `git show --stat --diff-filter=D "$SHA"` should be empty.

4. **`git diff --cached --name-status -- <the paths you just committed>`.**
   If your paths appear **at all**, a reversal of your commit is primed in the
   shared index. Repair it, path-scoped:

   ```bash
   git reset -q HEAD -- path/one path/two
   git diff --cached --name-only            # confirm OTHER sessions' staged work survived
   ```

   `git reset` with a pathspec syncs only your entries. Never run a bare
   `git reset`, `git checkout .` or `git stash` here — those are shared-state
   operations and will destroy another session's staged work.

---

## 3. Say which level a measurement came from

The same concurrency means the repo is **several disagreeing states at once**:

> main's index · main's working tree · main at HEAD (what CI clones) ·
> a worktree's working dir · a worktree's index · a specific commit's tree

On 2026-08-18 four sessions auditing one migration produced **five** factual
errors. None was sloppiness — every one was a *correct reading taken at the
wrong level*, and every one was caught by a peer rather than its author.

**The level axis includes TIME.** `HEAD` is not a stable referent here; 26
commits landed on one branch in a single evening. A claim carrying only a command
and a tree level is still under-specified — stamp it with the **commit SHA and
the clock time**. Never assert a property of a whole session from one point in
time.

Mechanical traps worth knowing before you measure:

- `git show <rev>:<path>` on a **mode-120000** entry returns the **link text**,
  not the target's content.
- `diff` and `cmp` **follow** symlinks — comparing "two files" can silently
  compare one file with itself.
- A worktree has **its own index**, invisible to `git ls-files` in main.
- `git status` / `git diff --name-only` report a rename by its **destination**,
  so the naive collision check returns empty precisely when rename *sources* are
  dirty. Use `git diff --name-status -M | awk '{print $2}'`.
- A symlink **resolving** says nothing about the **currency** of what it resolves
  to. Presence, content and provenance are three separate audits.
- Cached tracking refs lie. To ask whether something is pushed, ask the remote:
  `git ls-remote origin refs/heads/<branch>`, not `git rev-list @{u}..HEAD`.

**When you disagree with another session, exchange the command and the level —
never the conclusion.** A conclusion cannot be re-levelled by the person
receiving it; an invocation can. Carry a control through the same probe: a
known-good and a known-bad input turns *"we disagree"* into *"we measured
different things"* in one command. A control is also what separates a **null
result from a clean bill** — a check whose corpus can be empty goes green for
exactly the same reason a check that genuinely passes goes green.

The worked examples behind this section are in
[`docs/ASIC_GENUS_INNOVUS_AUDIT.md`](docs/ASIC_GENUS_INNOVUS_AUDIT.md) §6.

---

## 4. Other things that bite

- **Never modify anything under the shared IP library trees** — the roots behind
  `$IP_LIBRARY_ROOT`, `$ARM_IP_LIBRARY_PATH` and the physical-IP equivalent.
  They are lab-wide vendor collateral and edits corrupt builds across the whole
  lab. Read access is fine and expected; if a fix seems to need a change there,
  copy the file into the project tree, rewire the flist to the local copy, and
  document the deviation. Refer to these locations **by variable, never by
  absolute path** — a pre-commit check enforces this, because a literal path is
  an inventory of which PDK and IP this site is licensed for.
- **`ASIC/asic-flows` is a shared submodule** (`SoC-Labs/ASIC-Flow.git`). Changes
  there have lab-wide blast radius and are not yours to make from this repo.
- **Don't `git add -A`.** Ever. Someone else's half-finished edit is always in
  the tree.
- **Re-list before you quote a number.** A run directory or `calibre_runs/`
  listing from earlier in your own session is a guess, not a fact.
