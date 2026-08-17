# 41 — Retiring `asic-flows`: the path, the blast radius, and what needs no shared-repo change

**Status:** assessment complete. No change landed by this document; the `asic-flows` submodule was
not modified, and every prototype below lives in a scratch tree.
**Date:** 2026-08-18
**Measurement level:** repository `HEAD` unless a line says otherwise. `ASIC/genus-innovus/Makefile`
is cited at **HEAD** line numbers, which differ from the working tree by ~95 lines — doc 33 cites the
working-tree numbers for the same statements. CI clones HEAD, so HEAD is the one that counts.

---

## The recommendation, first

**Do not change `asic-flows`. You do not need to, and the reason is stronger than "it is shared":
`asic-flows` is already not the engine that builds this chip.**

Three measurements, each independently reproducible:

| Question | Measured answer |
|---|---|
| Where is the shipping GDS? | `ASIC/eth-chiplet/build/full-20260814/outputs/nanosoc_eth_chiplet_pads.gds`, 313,424,880 B, 2026-08-17 13:52 — **the toolkit's build tree** |
| What is in `ASIC/genus-innovus/outputs/`? | `eval/` (empty, 08-13) and `romlibs/`. **No netlist. No GDS.** |
| When did `asic-flows` last drive a tool? | `ASIC/genus-innovus/work/innovus.log7`, **2026-08-13 22:57**. Nothing since. |

The shipping netlist carries the toolkit's own provenance block
(`reports/syn_manifest.txt`: `toolkit_git_sha 20bc972`), and the LEC dofile for the shipping run names
`…/build/full-20260814/outputs/nanosoc_eth_chiplet_pads_gate.v` as its revised design. Every artefact
under signoff came out of the toolkit.

So the terminal condition is **not** a migration. It is **reconciling the entry points with a
migration that already happened.**

### The blast radius, measured

The four targets that reach `asic-flows` are `syn`, `pnr_place`, `pnr_cts`, `pnr_route`
(`ASIC/genus-innovus/Makefile` at HEAD lines 113/114, 250/251, 255/256, 266/267; the variable is
defined once at line 25). Cross-referencing against every `make -C ASIC/genus-innovus <target>`
invocation in `ci/`, `.github/` and the root `Makefile` at HEAD:

```
targets CI actually invokes:  lec  lec-selftest  rail  rail-selftest
                              romlibs-check  romlibs-gds-check
targets that reach asic-flows: syn  pnr_place  pnr_cts  pnr_route
intersection:                  EMPTY
```

**No CI gate invokes any target that reaches `asic-flows`.** The only entry points that do are three
convenience forwarders in the root `Makefile` — `asic-syn` (:91), `asic-pnr` (:92), `asic-gds` (:93).

Retiring `asic-flows` is therefore: **5 lines in one Makefile, 3 forwarders in another, one
`.gitmodules` stanza.** Zero CI gates, zero RTL, zero design data.

### What is doable with no shared-repo change

Everything that is currently being asked for.

1. **The synthesis constraint that triggered this review needs no `asic-flows` edit.** The extension
   point already exists in the toolkit, in exactly the window that `asic-flows` lacks — see §5.1. It
   is verified, not proposed.
2. **Retirement itself is entirely project-side.** Every line that has to change is in this
   repository (§3).
3. The only thing that would need a shared-repo change is *keeping the legacy fallback at feature
   parity* — i.e. spending a change to a lab-shared, default-branch repo on a code path we intend to
   delete. That is the trade this document recommends against.

---

## 1. The toolkit's honest state

`STATUS.md` (snapshot 2026-08-17 18:22 UTC, commit `24b1939`) is unusually honest and I am not going
to re-quote it. Three corrections and one confirmation from measuring rather than reading.

### 1.1 `executed` is real, and it is the right word

The headline claim holds. Genus elaborated 597 files; Innovus placed, clocked, routed and streamed;
the artefacts exist with sizes and timestamps consistent with the narrative. `flow/genus/`,
`flow/innovus/`, `flow/steps/` and `tech/tsmc65/tech.tcl` have genuinely been driven by the tools they
were written for. The qualification `STATUS.md` puts on it — *one design, one node, one site, one
author* — is the correct qualification and it has not changed.

The `harvested` rung is where `examples/nanosoc_eth_chiplet/` sits, correctly: doc 33 measured all
four physical inputs there as diverged from the live ones, and gap 16 records that pointing `ASIC_DIR`
at it **builds a different chip without erroring**. `mk/flow.mk` now refuses an `ASIC_DIR` inside
`examples/`, which closes the reachable form of that trap.

### 1.2 CORRECTION — the `verified` rung rests partly on a check that cannot fail

`STATUS.md` § *Keeping this current* documents the parse check that is the **entire** verification
record for `tech/tech_api.tcl` (67 KB, the contract every tech pack implements), all of `templates/`,
and `flow/verify/klayout/`. Its core is:

```tcl
if {[catch {proc __t {} $b} e]} { puts "PARSE-FAIL $f: $e" } else { puts "ok       $f" }
```

**Tcl does not parse a proc body at definition time.** The body is stored as a string and compiled
lazily on first call, which never happens. Measured, with the documented one-liner run verbatim:

| Input | documented idiom | `info complete` |
|---|---|---|
| unclosed brace | **ok** | FAIL |
| unclosed quote | **ok** | FAIL |
| unclosed bracket | **ok** | FAIL |
| well-formed body | ok | ok |
| **`tech_api.tcl` truncated to 200 of 1,545 lines** | **ok** | **INCOMPLETE** |

The last row is the one that matters: a real toolkit file cut to 13 % of its length passes the check
the toolkit uses to call it `verified`. `info complete` distinguishes all five correctly, and is a
one-token substitution.

This does **not** invalidate `executed` — a tool ran those files. It does not invalidate the test
suite, `test/stage/run.sh` or the pytest suites, which are real. It invalidates the specific claim
"23 `.tcl` files parse", and therefore the only evidence behind several `verified` rows. **Fix the
one-liner before the next snapshot cites it again.** This is the same defect class as the repository's
own antenna false-clean and `elab-strict` false-green, and as `${PIPESTATUS[0]}` under `ksh`.

### 1.3 CORRECTION — provenance of the shipping netlist is not reconstructible

Three different toolkit SHAs are in play, and the ancestry is clean but the build is not:

```
20bc972  2026-08-14 08:01  built the shipping netlist   toolkit_git_dirty = YES
3910c18  2026-08-17 20:45  pinned at repo HEAD          on origin/main
d6c5f7e  2026-08-18 00:22  live checkout, 1 ahead       8 files dirty
```

`20bc972` → `3910c18` → `d6c5f7e` is linear (verified with `merge-base --is-ancestor` in both
directions), and the pin is genuinely on `origin/main`. So the committed lineage is intact and a
fresh clone gets code that contains the build code.

But `toolkit_git_dirty yes` means **the exact code that produced the shipping netlist cannot be
recovered from any SHA.** This is precisely the failure mode `STATUS.md`'s own 2026-08-08 entry
records as the thing the toolkit exists to prevent — the reference project's flow submodule carrying
uncommitted edits the working GDSII depended on. It has reproduced, on the toolkit, at the tapeout
artefact. It is item 2 in §4.

### 1.4 CONFIRMED — gap 8 paid out, and that is the strongest evidence the toolkit has

`STATUS.md` gap 17: `read_flist.tcl` issued one `set_db init_hdl_search_path` per `+incdir+`, and
`set_db` **replaces**. On the compute chiplet's flist — 41 `+incdir+`, 27 `-y`, 68 calls — exactly one
survived, costing that project 167 silent black boxes. This project's flist has one `+incdir+` and no
`-y`, so the defect was **unreachable here**.

That is the single most valuable data point about the toolkit's maturity, and it points the opposite
way from the rest of §1: a second consumer found in a day what a tapeout had not. The fix is in
`3910c18`, the pin. Note the ordering — the defect was found by a consumer that is *not* on the
`asic-flows` path at all.

---

## 2. Contention: who else depends on `asic-flows`

Surveyed across `/home/dam1n19/` (bounded to this account — other users' homes are not readable, so
this is not a machine-wide claim).

### 2.1 The consumer list is shorter than assumed

| Path | Project | Pin | Consumes the stage scripts? |
|---|---|---|---|
| `nanosoc-ethernet-chiplet/ASIC/asic-flows` | **this project** | `c2a46ee` (`lpddr4-pll`, dirty ×3) | **YES — the only one** |
| `NanoSoC-Compute-Chiplet/ASIC/asic-flows` | Compute-Chiplet | **vendored, no `.git`**, byte-identical to `b19e784` | **NO** |
| `NanoSoC-Hetrogeneous-Chiplet-Testing/deps/eth-chiplet/…` | het-testing | `b19e784` | inherits |
| `NanoSoC-Hetrogeneous-Chiplet-Testing/deps/compute-chiplet/…` | het-testing | vendored `b19e784` | inherits |
| `/home/dam1n19/ci/…/NanoSoC-Ethernet-Chiplet/ASIC/asic-flows` | GH Actions runner | `b19e784` | see §2.4 |

**Compute-Chiplet defines `ASIC_FLOWS_DIR` and never uses it again.** It runs its own stage scripts
(`scripts/synth_p0.tcl`, `pnr_p0_{place,cts,route}.tcl`), whose headers name the `b19e784` originals
they were forked from. Its entire dependency surface on ASIC-Flow is **one file** — `Cadence/procs.tcl`,
sourced via `SOCLABS_ASIC_FLOW_DIR` — and that file's blob is **unchanged across the whole repository
history**. A change to the Cadence stage scripts on `lpddr4-pll` cannot reach Compute-Chiplet: it is
vendored, not submoduled, so no gitlink bump exists to carry it.

### 2.2 `lpddr4-pll` is the trunk, not a fork

This is the part that raises the stakes rather than lowering them.

```
remotes/origin/HEAD -> origin/lpddr4-pll      <- the DEFAULT branch
origin/main tip 46c88d3, 2026-04-16           <- dormant four months
origin/main...lpddr4-pll  =  0 behind, 3 ahead, linear, no merges
```

Verified against the live remote (`git ls-remote --heads`, network reachable read-only): remote
`lpddr4-pll` == local == `c2a46ee`. **`c2a46ee` is already pushed.** So `lpddr4-pll` is not a
side-branch anyone opted into — it is what `git clone` gives you. Anything landed there is what every
future consumer of ASIC-Flow starts from.

### 2.3 There is an owner, and it is mostly not us

```
git shortlog -sne --all
    12  Daniel Newbrook <dwn1c21@soton.ac.uk>
     2  dam1n19 <dam1n19@soton.ac.uk>
```

14 commits, two authors, 2025-06-23 → 2026-08-17. **No `CODEOWNERS`, `MAINTAINERS`, `CONTRIBUTING`
or `LICENSE`.** File headers credit David Flynn and Srimanth Tenneti, neither of whom has ever
committed, so the header list is not a reviewer roster.

Newbrook is the de-facto owner (12 of 14, and the author of `b19e784`, which is what everyone else
is pinned to). The last two commits are ours. **A change here needs Newbrook's sign-off**, and the
honest framing for that request is "this modifies the default branch of a repo you own, to serve one
consumer, on a code path that consumer is retiring."

### 2.4 The one place a change propagates without a human

`/home/dam1n19/ci/home/actions-runner/_work/…/ASIC/asic-flows` is pinned at `b19e784`. If that runner
ever re-syncs the submodule from the superproject's gitlink it jumps straight to `c2a46ee`. That is
the only unattended propagation path found. It argues for changing the *superproject pin*
deliberately, never for assuming a runner is frozen.

---

## 3. The costed path

Ordered. Each step is independently valuable, independently revertible, and none is a precondition for
the chip.

### Step 0 — Unblock the synthesis constraint, project-side (do today)

**Change:** create `ASIC/eth-chiplet/hooks/pre_synth.tcl`.
**Blast radius:** this project, one new file, one flow. Nothing else can see it.
**Approval:** none beyond normal review.
**Test:** §5.1 — proven under `tclsh` with controls in both directions.
**Rollback:** `rm` the file. The hook is a no-op when absent, by construction.

**Decision point:** does the constraint belong on the shipping netlist? If yes, this is the only
correct location — `1b_synthesis_eval.tcl` writes to `outputs/eval` and is explicitly the A/B variant,
so a gate placed there guards a netlist nobody tapes out.

### Step 1 — Make the entry points name the real flow

**Change:** root `Makefile` `asic-syn` (:91), `asic-pnr` (:92), `asic-gds` (:93) currently forward to
the legacy flow, which has produced none of the shipping artefacts. Repoint them at
`ASIC/eth-chiplet`, or rename them `asic-syn-legacy` etc. and add toolkit-named equivalents.
**Blast radius:** this project. No CI gate calls these three (§ blast radius above), so the change is
observable only to a human typing `make asic-syn`.
**Approval:** chip owner — this is the moment the repo *declares* which flow is authoritative.
**Test:** `make -n` on each target must name a `$(ASIC_FLOW_DIR)/flow/…` script, not
`$(ASIC_FLOWS_DIR)/…`. Confirm `make -C ASIC/eth-chiplet env` still reports the same `BLOCK`,
`ASIC_DIR` and `HOOKS_DIR` it does today.
**Rollback:** revert one commit.

**Decision point:** this is the cheapest possible statement of intent and it is currently *false in
the tree* — someone following the root Makefile's help text runs a flow that last produced an
artefact on 08-13.

### Step 2 — Fix the gate that guards nothing

`ci/signoff.yaml:607` runs
`make -C ASIC/genus-innovus romlibs-gds-check ROM_GDS=$PWD/ASIC/genus-innovus/outputs/nanosoc_eth_chiplet_pads.gds`.
**That path does not exist**, and doc `ASIC_MIGRATION_BLOCKERS.md` §8 already records that the target
itself is uncommitted at HEAD. So the gate is broken twice over, and the ROM-content blocker recorded
in the memory notes is exactly the failure this gate exists to catch.
**Blast radius:** CI only.
**Rollback:** revert.

**Decision point:** point it at `ASIC/eth-chiplet/build/$(RUN_TAG)/outputs/…`, i.e. the stream that
actually ships. Do this before Step 3 — it is the gate that would notice if Step 3 broke something.

### Step 3 — Freeze, do not delete

**Change:** mark `syn`/`pnr_place`/`pnr_cts`/`pnr_route` in `ASIC/genus-innovus/Makefile` as
deprecated, with a line saying which toolkit target replaces each. Leave them runnable.
**Blast radius:** none — comments and an echo.
**Rollback:** trivial.

**Decision point:** this is where the "must be able to build a chip at every point" rule is honoured
honestly. The fallback stays *present* while §4's evidence is gathered. It is not a control (there is
no independent legacy copy of the design data — `design.mk:69` points the toolkit at
`genus-innovus` for floorplan, power plan, mmmc and io), but present-and-runnable is still worth more
than deleted.

### Step 4 — Retire

**Change:** delete the 5 `ASIC_FLOWS_DIR` lines, the 3 root forwarders, the `.gitmodules` stanza and
the gitlink.
**Blast radius:** this repository. Other consumers are pinned by SHA or vendored (§2.1) and are
unaffected by anything this repo does to its own gitlink.
**Approval:** chip owner. **Not** Newbrook — removing our submodule reference changes nothing in his
repository.
**Precondition:** §4.
**Rollback:** `git revert` restores the gitlink; the submodule re-clones from a public remote.

**Note the asymmetry that makes this safe:** retiring `asic-flows` *from this project* needs no
permission from anyone outside it. Retiring the **`genus-innovus` directory** is a different and much
larger change and is **not** in this plan — it is still the toolkit's data source, still hosts
`lec`/`rail`/`romlibs` (four of the six targets CI invokes), and is still the `../scripts/` contract
directory. **These two retirements have been conflated repeatedly. They have different blast radii,
different preconditions and different approvers.**

### Options evaluated and rejected

| Option | Verdict | Why |
|---|---|---|
| **(a) shim inside `asic-flows`** | **Not needed** | The window it would open is already open in the toolkit (§5.1). Cost is a change to the default branch of a lab-shared repo, needing an external owner's sign-off, to preserve parity on a path we are retiring. If it is ever done anyway, §5.2 gives the correct shape — and note the shape most people reach for is the wrong one. |
| **(b) symlink bridge as permanent** | **No** | It makes symlinks load-bearing for a lab-shared engine, and every check it passes (`120000`, non-dangling, contract 9/10, `legacy-paths` 7/7) also passes on a **stale** target — doc 33 measured `72febb7` doing exactly that. It also silently reverts `15b0501` and `2dca8ae`. Acceptable only as a transitional device, and the migration lane is parked. |
| **(c) fork `asic-flows`** | **No** | Forking a repository in order to delete it is backwards, and there are already two copies of these scripts in the lab (submodule + Compute-Chiplet's vendored `b19e784`). A third guarantees permanent divergence. |
| **(d) retire once proven** | **Yes** | Steps 0–4. The measurements say we are much closer than the framing assumed. |

---

## 4. What must be true before the fallback is deleted

The migration rule has been "the project must be able to build a chip at every point". That rule
**cannot** be discharged by diffing legacy against toolkit output, because there is no independent
legacy control — `design.mk:69` makes `genus-innovus` the toolkit's data source, so both flows have
always read one copy of every design file. `ASIC_MIGRATION_BLOCKERS.md` §3 reaches this independently:
constraint 1 can only ever have meant "something builds".

So the evidence that would actually justify Step 4:

1. **The gates that guard the shipping artefacts must read the shipping artefacts.**
   Status: **FALSE.** `ci/signoff.yaml:607` names a non-existent path in the legacy tree (Step 2).
   Until a gate is pointed at the stream that ships, a green board says nothing about it.

2. **A clean toolkit SHA must have built a shipping artefact.**
   Status: **FALSE.** `toolkit_git_sha 20bc972`, `toolkit_git_dirty yes` (§1.3). This is the strongest
   single argument for *not* deleting the fallback yet — not because the fallback would help, but
   because it is direct evidence that the toolkit's provenance discipline has not yet held under
   tapeout pressure.

3. **One reproduction run.** Same inputs, same clean toolkit SHA, twice, compared. `STATUS.md`
   question 3: eight run directories exist and **no two are a repeat** — every one moved a knob or a
   floorplan. Status: **NEVER DONE.** This is the measurement that converts "it ran" into "it is an
   engine", and it is a day of compute.

4. **The toolkit's own parse gate must be able to fail** (§1.2). Status: **FALSE** today, one-token
   fix. Cheap, and it is upstream of every `verified` claim anyone will cite in this decision.

5. **A second consumer.** Status: **PARTIALLY TRUE** and improving — gap 17 was found and fixed by
   the compute chiplet. This is the only item already trending the right way.

**We do not have the evidence.** But note what is missing: items 1–4 are all about the *toolkit's*
provenance and gate wiring, and **not one of them is made better by keeping `asic-flows`.** Keeping
the fallback is currently buying nothing except the ability to say a second path exists — a path that
has not run since 08-13, has no outputs, and shares all its design data with the flow it would
supposedly check.

The honest sequencing: **do Steps 0–3 now** (none of them delete anything), fix items 1, 2 and 4, run
item 3 once, and then Step 4 is a formality.

---

## 5. Prototypes — measured, not proposed

All prototyping was done in
`/tmpdir/claude-74755/…/scratchpad/{hookproof,flowshim}`, against a **copy** of `Cadence/`. The live
`ASIC/asic-flows` submodule was not modified (`git -C ASIC/asic-flows status` remains the same three
pre-existing entries: `M README.md`, `?? Mentor/`, `?? site.env.example`).

### 5.1 The extension point already exists in the toolkit — VERIFIED

`ASIC/asic-toolkit/flow/genus/1_synthesis.tcl`:

```
:499   elaborate $block_name
:933   flow_hook pre_synth        <-- the window asic-flows does not have
:949   syn_generic
:1015  flow_hook post_synth
```

`flow_hook` (`flow/common/flow_utils.tcl:302`) resolves `$ASIC_HOOKS_DIR/<name>.tcl`. Wiring
confirmed by running the real Make, not by reading it:

```
$ make -C ASIC/eth-chiplet env
  ASIC_FLOW_DIR   …/ASIC/asic-toolkit
  ASIC_DIR        …/ASIC/eth-chiplet
  HOOKS_DIR       …/ASIC/eth-chiplet/hooks          <- flow.mk:246, exported :374
```

`ASIC/eth-chiplet/hooks/` does not exist yet. Creating it is the whole change.

Behaviour, proven by extracting the `flow_hook` proc **verbatim** and driving it under `tclsh` with
controls on both directions:

| Case | Result |
|---|---|
| `ASIC_HOOKS_DIR` unset | returns 0, nothing recorded — *negative control* |
| dir set, `pre_synth.tcl` absent | returns 0, nothing recorded — the every-other-project case |
| hook present | returns 1, body ran, visible in caller's scope (`uplevel 1`), logged as `pre_synth(0s)` |
| hook raises | error **propagates**, stage aborts, `FLOW-FAIL` block naming file and error — *positive control on the fail path* |

That last row is the important one and it is strictly better than anything `asic-flows` can offer: a
failing hook **stops the run**, where a failed `source` in `asic-flows` is followed by Genus exiting 0
(`ASIC/genus-innovus/Makefile:19` documents this against itself). The hook is also recorded in the
stage manifest (`hooks_run`), so its participation is provenance, not folklore.

### 5.2 If a shared-engine hook is ever added anyway — the obvious shape is the wrong one

I prototyped the natural proposal first:

```tcl
if {[file exists ../scripts/pre_syn_hook.tcl]} { source ../scripts/pre_syn_hook.tcl }
```

It parses and it is inert for non-adopters. **It is still wrong for this codebase**, and the reason is
only visible from the repository's own history:

```
grep -rn "file exists"    Cadence/   ->  0 hits          (no such precedent, anywhere)
grep -rn "info commands"  Cadence/   ->  4 hits          (the sanctioned pattern)
```

All four are `if {[llength [info commands soclabs_setup_multi_cpu]]}`, introduced by `fc7636d`
("flow: route multi-CPU setup through the project hook, with a safe fallback"), whose own comment
states the contract: the proc is defined by the **project's** `scripts/config.tcl`, and projects that
have not adopted it keep the historical default *so the file stays runnable for every consumer*.

This also dissolves the "`config.tcl` is sourced at :15, too early for a hinst attribute" objection.
It is too early to *act*, but exactly right to **define**. Definition early, invocation late:

```tcl
# after read_sdc (:55), before syn_generic (:66)
if {[llength [info commands soclabs_pre_synthesis]]} {
    soclabs_pre_synthesis
}
```

Verified in scratch — Case A (proc undefined, i.e. every `b19e784`-pinned consumer): no hook, flow
unchanged. Case B (project defines it): hook called. File remains `info complete`.

Adopting the `file exists` form would invent a **second, competing** extension convention in a repo
that already has one, chosen by our own commit. If the change is ever made, make it this one.

### 5.3 A correction to the contract inventory

The audited contract is "10 entries from `../scripts/`". Re-measured, `Cadence/` has **14** raw
`../scripts/` occurrences, **13** non-comment (the 14th is a comment at `4_pnr_route.tcl:65`), naming
**10** distinct files — all three prior numbers confirmed.

But the contract has a **second directory** that the `../scripts/`-only grep could not see:

```
Cadence/1_synthesis.tcl:39: read_power_intent -module $block_name ../inputs/${block_name}.upf
```

So the contract is **11 entries across 2 directories**, not 10 across 1. It is already bridged —
`design.mk`'s `legacy-paths` creates `$(RUN_DIR)/{scripts,inputs}` — so nothing is broken today, and
`.upf` is one of the five files `legacy-paths` does **not** assert. Worth correcting because "10
entries in one directory" is the number every downstream doc repeats, and a future repointing exercise
scoped from it would miss the power intent entirely.

Whole-repo the literal count is **41** including one in the untracked `site.env.example`; tracked-only
it is **40**.

---

## 6. Reproducing

```sh
# 1. asic-flows is not the engine
ls -la ASIC/genus-innovus/outputs/                      # eval/ + romlibs/ only
find ASIC/genus-innovus -name 'innovus.log*' -printf '%TF %TT %p\n' | sort | tail -1
grep -E 'toolkit_git' ASIC/eth-chiplet/build/full-20260814/reports/syn_manifest.txt

# 2. blast radius: CI targets vs asic-flows targets
git grep -ho "make -C ASIC/genus-innovus [a-z0-9_-]*" HEAD -- ci/ .github/ Makefile \
  | sed 's/.*genus-innovus //' | sort -u
git grep -n 'ASIC_FLOWS_DIR' HEAD -- ASIC/

# 3. the parse gate cannot fail  (positive AND negative control)
head -200 ASIC/asic-toolkit/tech/tech_api.tcl > /tmp/mutant.tcl
tclsh <<'EOF'
foreach f {/tmp/mutant.tcl} {
  set fh [open $f r]; set b [read $fh]; close $fh
  puts "proc-idiom:    [expr {[catch {proc __t {} $b}] ? {FAIL} : {ok}}]"
  puts "info complete: [expr {[info complete $b] ? {complete} : {INCOMPLETE}}]"
}
EOF

# 4. the hook exists and is wired
make -C ASIC/eth-chiplet env | grep HOOKS_DIR
grep -n 'flow_hook pre_synth' ASIC/asic-toolkit/flow/genus/1_synthesis.tcl

# 5. the sanctioned hook convention
grep -rn 'info commands' ASIC/asic-flows/Cadence/     # 4
grep -rn 'file exists'   ASIC/asic-flows/Cadence/     # 0
```

No EDA licence is needed for any of it. Every claim above is filesystem state, `git` history, Make
variable expansion, or Tcl semantics under `tclsh` — and `tclsh` needs `< /dev/null` **except** when
you are feeding it a heredoc, where `< /dev/null` silently eats the script and prints nothing. That
mistake was made and caught while writing §1.2; it produces an empty result that looks exactly like a
clean pass.
