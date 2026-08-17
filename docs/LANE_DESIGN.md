# Lanes — running static checks alongside a multi-hour backend run

**Status:** two prerequisites landed (§3, §4); the rest is specified here and
not yet implemented. **Date:** 2026-08-17.

A *lane* is an independent line of work that runs concurrently with the
place-and-route flow: a lint run, a CDC run, an elaboration check, a ROM verify.
Today the only safe way to run one is to wait for the backend to finish, because
three separate mechanisms let a lane and the backend corrupt each other silently.
This document says what those mechanisms are, which two have been fixed, and
exactly how to build the rest.

Every claim here was measured on this host on 2026-08-17. Where a measurement
contradicts something previously believed, the contradiction is called out.

---

## 1. What a lane must guarantee

In priority order, because they conflict:

1. **A lane can never damage the backend run.** A five-hour route that is
   destroyed at hour four by a lint job is worse than no lint at all.
2. **A lane can never silently lose its own verdict.** A lane that reports
   "0 failed" having measured nothing is the failure mode this whole flow is
   built against — see the doctrine at the top of
   `ASIC/asic-toolkit/ci/lib.sh`.
3. **A lane's failure must not propagate into the backend's exit status.** A red
   lint must produce a red *report*, not a dead route.
4. **A lane must be able to say "I could not run".** Missing evidence is not a
   pass.

Point 4 already has an implementation. `ci/lib.sh` defines five statuses, and
one of them — `ci_unverified` — exists precisely for "the evidence is MISSING
rather than bad". It counts as a failure, deliberately. Confirmed working:

```
$ CI_VERDICT_DIR=… ci_init; ci_pass g.a ok; ci_unverified g.b "spyglass not on PATH"; ci_exit lane
  ok g.a  ok
UNVERIFIED  g.b  spyglass not on PATH
CI-GATE: UNVERIFIED id=g.b detail=spyglass not on PATH
lane: 1 passed, 1 failed, 0 warned
exit=1
```

It prints on stderr, emits the machine-readable `CI-GATE:` line, records
`UNVERIFIED` into `verdicts.tsv`, increments `CI_FAIL`, and turns `ci_exit`
red. **A lane whose tool is unavailable must call `ci_unverified`, not
`ci_skip`.** `ci_skip` is for a gate that did not *apply*; a gate whose tool was
missing did apply and did not run.

---

## 2. The three isolation defects

| # | Defect | Shared resource | Status |
|---|---|---|---|
| D1 | Two lanes sharing `CI_VERDICT_DIR` erase each other's verdicts | `verdicts.tsv` | **guard landed**, convention still to adopt |
| D3 | A lane regenerating the ASIC sub-flists truncates a file Genus is reading | `build/chip/flist/*.flist` | **specified, not implemented** (§5) |
| D4 | `.NOTPARALLEL:` serialises every target in the project | make's job graph | **structural fix landed** (§4) |

---

## 3. D1 — verdict isolation (landed)

### The defect

`ci_init` truncates `$CI_VERDICT_DIR/verdicts.tsv` unless `CI_APPEND=1`, and
`_ci_record` is an unlocked `>>` append. Both are correct for **one** process
writing **one** file, which is what the serial tier ladder in `ci/tier.sh` is —
it calls `ci_init` once and then exports `CI_APPEND=1` so every script it calls
appends instead of starting over (`ci/tier.sh:117,121`).

They are not correct for two concurrent lanes. Whichever calls `ci_init` second
erases the first one's records and *nothing reports it*. A new driver that
forgets `CI_APPEND` loses records with no error at all.

### The fix, and why it is not in `lib.sh`

**Each lane sets its own `CI_VERDICT_DIR`.** `ci_init`'s truncate is then
correctly scoped to a file that lane alone owns, and no lock is needed anywhere.
The convention already exists in the toolkit —
`ci/check-vendor-collateral.sh:201-207` appends `/vendor` to whatever directory
it inherited and sets `CI_APPEND=0`, for exactly this reason. It is simply not
enforced.

### What did land in `lib.sh`

An enforcement guard, so the failure is loud instead of silent. `ci_init` now
stamps an `owner` file beside `verdicts.tsv` (lane, pid, host, the pid's start
time, timestamp). A process that finds a **live foreign owner** refuses to
truncate and fails a gate:

```
CI-VERDICT-COLLISION /…/build/<tag>/ci/verdicts.tsv
  it is owned by lane backend-route (pid 2964371 on srv03335), which is STILL RUNNING.
  Truncating it would delete that lane's evidence and it would
  report "0 failed" having measured nothing. NOT truncating.
  Give each lane its own directory:  CI_VERDICT_DIR=<run>/ci/<lane>
FAIL  ci.verdict.collision  lane 'static-lint' found … owned by live lane 'backend-route' …
```

The gate line lands in the shared file, so the collision is visible from **both**
sides rather than only to the loser. The other lane's records survive intact.

Design notes that matter if you touch it:

- **Liveness is pid + host + start time**, read from field 22 of
  `/proc/<pid>/stat`. pid alone is not an identity: the owner file outlives the
  run that wrote it, pids are recycled, and a stale owner whose number came round
  again would fail every later run of that tag for no reason. A guard that cries
  wolf gets deleted, and a deleted guard protects nothing. Verified: a dead pid,
  a live pid with a mismatched start time, and an owner on another host all
  proceed normally.
- **A different host is not judged.** The verdict directory can be on NFS; we
  cannot test liveness of a pid on another machine, so we do not guess.
- **The owner file is never cleaned up.** Removing it would need an `EXIT` trap,
  and `lib.sh` is *sourced* — installing a trap here would silently replace the
  caller's own. `ci/static-checks.sh:43` has one, and it is what removes its
  scratch directory. Liveness is what is tested, not existence, so a stale file
  costs nothing.
- **Appends are not guarded, deliberately.** `_ci_record` writes one short line
  to a file opened `O_APPEND`; that is a single `write()` far under `PIPE_BUF`
  and the kernel does not interleave it. Two lanes appending produce a readable
  mixture, never a torn line. Only the truncate destroys evidence.
- **`CI_APPEND=1` returns before the guard**, so the existing `tier.sh` →
  `assert-stage.sh` parent/child pattern is completely unaffected. Verified.

No existing function signature changed. `ci/tier.sh`, `ci/assert-stage.sh` and
`ci/static-checks.sh` were read and are unaffected. Full toolkit shell suite is
green.

---

## 4. D4 — removing the blanket serialisation (landed in the toolkit)

`ASIC/eth-chiplet/design.mk:477` sets a bare `.NOTPARALLEL:`, which serialises
**every target in the project**, including lanes that share nothing with the
backend. Its justification (`design.mk:472-476`) was correct and narrow:

> `all: syn place cts route` has no ordering barrier, so `make -j all` is free to
> start place while syn is still elaborating — and `place` depends on
> `cpf-patch`, which reads a file `syn` has not written yet.

That is true. `all:` in `mk/flow.mk` stated four prerequisites and no ordering
between them; serial make happens to run them left to right, which is why it
looked correct for as long as nobody passed `-j`.

**Scoped `.NOTPARALLEL: <targets>` is GNU Make 4.4. This host has 4.2.1**
(measured), where `.NOTPARALLEL` takes no arguments and serialises the whole
makefile. So the fix is structural instead:

```make
all:
	@$(MAKE) syn
	@$(MAKE) place
	@$(MAKE) cts
	@$(MAKE) route
```

Recipe lines run in sequence by definition, in every make, at every `-j`. The
four stages stay ordered and nothing else loses its parallelism. `$(MAKE)` marks
each line recursive, so `make -n all` still descends into all four stages with
`-n` propagated rather than printing four lines it never expands.

### Blast radius, measured

- **`make -n all` still expands all four stages** and writes nothing to disk
  (verified: no `build/` directory is created). Output grows by 10 lines: one
  `make <stage>` echo per stage, plus `dirs` and `check-quiet` re-expanding per
  sub-make.
- **`ASIC/asic-toolkit/test/shell/t_flow_mk_guards.sh` needs no change.** It
  covers `distclean`, `clean`, `env` and the resume model — it never invokes
  `all`. 18/18 green after the change.
- **`t_scaffold.sh:106-107` is the test that does cover it** —
  `scaffold.make.no-warnings` runs `make -n` over 20 targets including `all` and
  requires zero warnings on stderr. **It needs no change**; 19/19 green.
- **`t_documented_commands.sh:109` explicitly skips `make*all`** (needs a tool
  and a seat). No change.
- Full suite re-run after both changes: `t_assert_stage_gates` 43/0,
  `t_capability` 23/0, `t_documented_commands` 8/0, `t_flow_mk_guards` 18/0,
  `t_harness` 13/0, `t_scaffold` 19/0, `t_static_gates` 16/0.
- **The destructive guards still fire.** Verified individually:
  `RUN_TAG=` → refused at `flow.mk:109` before any `rm` is composed;
  `RUN_TAG=a/b` → refused at `:117`; `BUILD_DIR=` → refused at `:144`;
  `RUN_TAG=m1_m8` → composes exactly `rm -rf "<asic>/build/m1_m8"`.
- **The resume model is unchanged.** `place`, `cts` and `route` never depended on
  each other — only on `dirs`/`check-quiet` and the project's own additions — so
  the change cannot affect them. Verified with `make -n`:
  `make cts RUN_TAG=x IN_RUN_TAG=y` runs 1 × `3_cts.tcl` and 0 × place/syn;
  `make place SYN_RUN_TAG=z` runs 1 × `2_place.tcl` and 0 × syn.

### One real behaviour change

`dirs`, `check-quiet` and the project's `syn place cts route:` prerequisites
(`design.mk:657` — `legacy-paths pad-lef rom-ensure`) now run **once per stage**
instead of once per `make all`, because each stage is its own make process.

This is acceptable, and mostly already the case:

- These are exactly the semantics of the documented resume workflow, where a
  user runs `make place` then `make cts` as separate invocations. Nothing new is
  being asked of them.
- `design.mk:653-654` already states the requirement for `pad-lef`:
  *"Idempotent and licence-free, so hanging it off every stage costs nothing."*
- **`check-quiet` measured at ~61 s** against the real project on this host, so
  `make all` gains roughly three extra minutes of contract checking against a
  multi-hour run. It is licence-free. Re-validating the design contract
  immediately before each multi-hour stage is arguably worth more than the three
  minutes.

If that ever becomes unwelcome, the fix is a stamp file under `$(RUN_DIR)`, not
a return to prerequisite ordering.

### Follow-up for the user (one line, not done here)

`.NOTPARALLEL:` at `ASIC/eth-chiplet/design.mk:477` **becomes removable** once
this toolkit change is in place, together with its now-stale justification
comment at `:472-476`. That file is not owned by this change, so it was left
alone. Removing it is what actually buys the project its parallelism back;
until then the toolkit fix is correct but dormant.

---

## 5. D3 — the flist regeneration race (verified, NOT implemented)

### The chain, end to end

1. **`flist/nanosoc_eth_chiplet_asic.flist`** is `RTL_FLIST`
   (`ASIC/eth-chiplet/design.mk:138`). It `-f`-includes two **generated** files:
   - `:35` → `build/chip/flist/soc.flist` (56 691 bytes as of this writing)
   - `:60` → `build/chip/flist/tidelink_asic.flist` (22 795 bytes)

2. **Those two files are written with plain shell redirection**, at
   `Makefile:326-329`:

   ```make
   python3 "$(CHIPLET_HOME)/flist/flatten_soc_flist.py" \
       "$${NANOSOC_MULTICORE_HOME}/flist/nanosoc_multicore_asic.flist" > "$(CHIPLET_SOC_ASIC_FLIST)"
   python3 "$(CHIPLET_HOME)/flist/resolve_tidelink_flist.py" \
       "$${TIDELINK_HOME}/flists/tidelink_top_full_asic_v2.flist" > "$(CHIPLET_TL_ASIC_FLIST)"
   ```

   `>` truncates **on open** — before python has read its input, let alone
   produced a byte of output. The file is empty for the whole of python's run.

3. **`asic-flist` is phony and is a prerequisite of `syn` in three places**, so
   every synthesis invocation re-renders both files unconditionally:
   - `ASIC/eth-chiplet/design.mk:658` — `syn: asic-flist romlibs-check`
     (declared phony at `:470`, recipe at `:540`)
   - `ASIC/genus-innovus/Makefile:208` — `syn: setup_dirs asic-flist romlibs-check`
   - `ASIC/genus-innovus/Makefile:253` — `syn_eval: setup_dirs asic-flist romlibs-check`

   All three delegate to the root `Makefile:317` target.

4. **`verif/lint/full/run.sh:72-75` is the fourth writer** — it calls
   `make -C "$CHIPLET_HOME" asic-flist` when either generated file is absent.

5. **The reader holds the file open for the whole RTL read.**
   `ASIC/asic-toolkit/flow/common/read_flist.tcl` opens the flist at `:58` and
   then calls `read_hdl` on each source file *inside* the `while {[gets $fh …]}`
   loop (`:84`), recursing into `-f` includes at `:82`, and only closes at `:87`.
   So `soc.flist` is held open, and read incrementally, across **every
   `read_hdl` it names** — minutes, not milliseconds.

### Why it is silent

If the file is truncated while Tcl sits at offset *N*, the next buffer fill at
offset *N* returns zero bytes. `gets` reports EOF, the loop exits cleanly,
`close` succeeds, and synthesis proceeds with the subset of files read so far.

The only guard in `read_flist.tcl` is `$::flist_files == 0` (`:104`), and it does
**not** fire — a partial read has a non-zero count. Genus then elaborates a
design whose missing modules become empty black boxes.

### Reproduced

A Tcl reader with `read_flist.tcl`'s exact structure (open, `gets` loop with slow
work inside, close), over a 113 KB / 3000-line file, against a writer that
truncates on open and then computes for four seconds before emitting — which is
precisely `python3 … > out`:

```
=== A: '>' truncates ON OPEN, then the renderer computes for 4s before writing ===
READER SAW 114 LINE(S) of 3000

=== B: same timing, but atomic '> tmp && mv' ===
READER SAW 3000 LINE(S) of 3000
```

**114 of 3000 files, no error, exit 0.** That is the defect exactly.

Note the earlier attempts that did *not* reproduce it, because they are the trap
for anyone re-testing this: with a file smaller than Tcl's 4 KB channel buffer,
or with a writer fast enough to restore identical bytes before the reader
resumes, case A reads all 3000 lines and looks clean. The race needs a
realistically large file **and** a renderer that is slow between truncate and
write. Both are true of the real thing.

### Is atomic write (`> tmp && mv`) a sufficient cheap mitigation?

**It fully fixes this mechanism, and it is worth landing on its own — but it is
not the whole fix.**

What it fixes: `rename(2)` is atomic within a filesystem and does not touch an
already-open file descriptor. The reader keeps the old inode and reads it
complete to the end; a reader that opens after the rename gets the complete new
file. Nobody ever observes a partial file. Case B above demonstrates this
directly.

What it does **not** fix:

1. **The two files are not atomic as a set.** `read_flist.tcl` opens
   `soc.flist` (parent `:35`), reads every file it names — minutes — and only
   then opens `tidelink_asic.flist` (parent `:60`). A regeneration landing in
   that gap gives you render A's SoC and render B's TideLink. Both halves are
   individually complete and the combination may be a configuration that has
   never existed anywhere.
2. **It does not stop the content changing under a run at all**, only from being
   *partial*. Line `Makefile:329` is the single line that selects V1 vs V2
   TideLink PHY (`Makefile:310-316`); the two carry same-named modules and can
   never co-compile. A lane rendering against a different `TIDELINK_HOME` or a
   different `deps/tidelink-phy` commit silently changes what the backend builds.
3. **It leaves four writers with no owner.** The real problem is that "who
   renders the flist" is undefined, not that the write is non-atomic.

**Recommendation: land both.** Atomic write is two lines and removes the silent
short-read today; the preflight below removes the class.

### The fix to implement — a shared serial preflight

Render once, before any lane forks; every runner then **asserts** rather than
regenerates.

**Files and lines to change. None of these are owned by this change; do not
apply them from here.**

| File | Line(s) | Change |
|---|---|---|
| `Makefile` | 326-329 | Render to `$@.tmp.$$$$` and `mv` into place. Keeps the `\|\|` failure path: a failed python leaves the tmp file and the old flist intact. Add `asic-flist` to a `.PHONY` line (42-44) — it is phony by accident today, only because no file of that name exists. |
| `Makefile` | after 329 | New target `asic-flist-check`: asserts both generated files exist and are non-empty, and does **not** render. This is what runners call. |
| `Makefile` | new | New target `preflight`: `asic-flist` plus anything else lanes share. This is the single serial step a lane driver runs *before* forking. |
| `ASIC/eth-chiplet/design.mk` | 658 | `syn: asic-flist romlibs-check` → `syn: asic-flist-check romlibs-check`. Ownership of rendering moves out of the stage. |
| `ASIC/genus-innovus/Makefile` | 208, 253 | Same substitution for `syn` and `syn_eval`. |
| `verif/lint/full/run.sh` | 72-75 | Replace the conditional `make … asic-flist` with a hard assertion that both files exist, failing with "run `make preflight` first". |
| `verif/cdc/run.sh`, `verif/elab_strict/run.sh` | — | Check for the same pattern; both reference `asic-flist` in comments (`:51`, `:61`) and must not acquire the regenerating behaviour. |

Two properties the preflight must have, or it is not a fix:

- **It runs to completion before the first lane starts.** Not "first one wins" —
  serial, in the driver, with its exit status gating the fork.
- **The runners must not fall back to rendering.** A runner that renders "just in
  case" reintroduces the whole defect. The assertion must fail loudly and name
  `make preflight`.

Once rendering has one owner, the `-f`-include set is stable for the life of the
run and the two-file consistency problem in (1) disappears with it.

### A comment/code mismatch worth fixing while you are there

`verif/lint/full/run.sh:69-70` says the sub-flists are regenerated "here so a
stale render cannot silently change what gets linted". The code at `:72-75` only
renders them **when they are absent** — a stale render is exactly what it does
*not* protect against. Under the preflight model the comment becomes correct for
a different reason (the preflight owns freshness), so rewrite it rather than
deleting it.

---

## 6. The lane wrapper

One script, `ASIC/asic-toolkit/scripts/asic-flow-lane`, modelled directly on
`scripts/asic-flow-lock` — which is a working advisory-`flock` implementation
with the right defaults already argued out in its header, and should be reused
rather than reimplemented.

```
asic-flow-lane <lane-name> [--require <capability label>] -- <command> [args...]
```

### Behaviour, in order

1. **Resolve the lane's directory** (§7) and `export CI_LANE=<lane-name>`,
   `CI_VERDICT_DIR=<run>/ci/<lane-name>`. This is the D1 convention; with it,
   the collision guard in §3 never fires and each lane truncates only its own
   file.

2. **Liveness lock.** `flock --nonblock` on `<build>/lanes/<lane-name>.lock`,
   opened `>>` not `>`. The append matters and `asic-flow-lock` explains why: a
   contender opening `O_TRUNC` wipes the holder's record before it has even
   failed to take the lock, so the error message loses the one fact it existed to
   carry. On failure to acquire, the lane is **already running** — record
   `ci_skip lane.<name>.already-running` with the holder's identity and exit 0.
   Do not queue by default, for the reason `asic-flow-lock` gives: a job that
   silently blocks for four hours looks exactly like a job doing four hours of
   work.

   Note the scope limit, inherited: `flock` over NFS is unreliable, so the lock
   protects users sharing a filesystem on one host. Two hosts sharing a build
   directory need a per-host `BUILD_DIR`, not a better lock.

3. **Capability probe.** `ci/capability.sh --require <label>` if `--require` was
   given. That script already derives labels from a project-declared
   `ci-capability.conf` and reports only the gaps blocking the label asked for.
   On a gap: `ci_unverified lane.<name>.capability "<the gap capability.sh
   named>"` and exit 0. **`ci_unverified`, not `ci_skip`** — §1.4. A lane that is
   legitimately not expected on a host should be declared absent in the
   capability conf, at which point the driver never launches it.

4. **Run the command**, with stdin from `/dev/null`. Every EDA invocation in this
   flow already does this and `mk/flow.mk:417-419` says why: a tool that hits an
   error drops to its prompt, holds a licence seat and waits forever.

5. **Verdict from artefacts, not exit status.** The rule the whole toolkit is
   built on (`mk/flow.mk:13-18`): Genus and Innovus both exit 0 after printing an
   error and doing nothing. Each lane declares the artefact that proves it ran —
   `build/lint/full/verilator_report.txt`, `hal_report.txt` — and the wrapper
   uses `ci_assert_file` on it. A lane whose artefact is absent or zero bytes is
   `UNVERIFIED`. `ci_assert_file` already distinguishes those two cases, because
   a zero-byte artefact is the shape a tool leaves when it opened its output and
   died, and it satisfies every `test -e` in the world.

6. **Always exit 0.** The verdict is in `verdicts.tsv`; the process status is not
   the product.

   Be precise about what this buys, because it is easy to overclaim: GNU Make
   does **not** kill sibling jobs when one recipe fails — it prints "waiting for
   unfinished jobs", lets them finish, and then fails. So a red lint would not by
   itself terminate a running route. What it *would* do is stop make launching
   anything further, fail the whole invocation, and — the real hazard — cause a
   CI runner or a shell driver to kill the process group. Exiting 0 removes all
   three. The cost is that nothing fails until the status renderer (§9) reads the
   verdicts, which is why that renderer is not optional.

### What the wrapper must not do

- **No `EXIT` trap installed in `ci/lib.sh`.** The wrapper owns its own trap;
  `lib.sh` is sourced and must not replace a caller's (see §3).
- **No writing into another lane's directory**, including for diagnostics.
- **No rendering of shared inputs.** That is the preflight's job (§5), and a
  lane that renders "just in case" is defect D3 returning.

---

## 7. Directory layout

```
<BUILD_DIR>/
  lanes/                          # locks live BESIDE the run dirs, so `make clean`
    backend.lock                  #   cannot delete a lock out from under a holder
    lint-full.lock                #   (the reason asic-flow-lock places them here)
    cdc.lock
  <RUN_TAG>/                      # = RUN_DIR, one per backend run
    work/ logs/ reports/ outputs/ # unchanged, backend-only
    ci/
      owner                       # written by ci_init: lane, pid, host, starttime, ts
      verdicts.tsv                # the ladder's own verdicts (tier.sh, unchanged)
      lint-full/
        owner
        verdicts.tsv              # CI_VERDICT_DIR for that lane
      cdc/
        owner
        verdicts.tsv
```

Rules:

- **One directory per lane, under the run it belongs to.** This is the entirety
  of the D1 fix; everything in §3 is only enforcement of it.
- **`ci/verdicts.tsv` stays where it is.** `ci/tier.sh:114` and
  `ci/assert-stage.sh:89` both default to `$RUN_DIR/ci`, and the serial ladder is
  a legitimate single owner of it. Do not move it to `ci/backend/` — that breaks
  every existing consumer for no gain.
- **Lane output artefacts stay where the lane already puts them**
  (`build/lint/full/…`). Only the *verdict* moves under the run. A lane's report
  is about the RTL; its verdict is about this run.
- **Locks are outside `RUN_DIR`.** `make clean` empties the run's work area, and
  a lock inside it would be deleted while held.

---

## 8. Licence pools

**The brief this work was scoped from states that "SpyGlass sits on the Synopsys
daemon entirely, so the static lane and backend lane draw on disjoint licence
servers". That is not true of this repository's static lane, and the correction
changes the failure model.**

Measured on this host, 2026-08-17:

| Lane | Tool | Binary | Licence variable | Server |
|---|---|---|---|---|
| backend | Genus, Innovus | `genus`, `innovus` | `CDS_LIC_FILE` | (see `$CDS_LIC_FILE`) |
| static | Verilator | `/usr/bin/verilator` | *none* | — |
| static | HAL | the Xcelium `hal` binary under `$XCELIUM_HOME/tools/bin`, via `xrun -hal` | `CDS_LIC_FILE` | (see `$CDS_LIC_FILE`) |
| (CDC, elsewhere) | SpyGlass | **not installed on this host** | `SNPSLMD_LICENSE_FILE` | (see `$SNPSLMD_LICENSE_FILE`) |

`verif/lint/full/run.sh` runs **Verilator and HAL** — see `hal_lint.sh:30`
(`XRUN="${XRUN:-<xcelium>/tools/bin/xrun}"`) and `:136`
(`"$XRUN" -sv -hal -elaborate`). SpyGlass appears in this repo only in CDC
documentation and in TideLink's flow; it is not what the static lane invokes
here.

So **the static lane and the backend lane sit on the same licence server.**

The conclusion that contention is a non-issue still holds, but for a different
reason — the *features* are disjoint, and each carries 41 seats. Sampled with
`lmstat -a`:

```
(lmstat -a output redacted. It listed the Genus, Innovus, Xcelium and Conformal
feature names with this site's seat entitlement and in-use counts. Seat counts
are commercial information about the licensee, not a property of the design, so
they are not reproduced in a tracked file. Re-run `lmstat -a` against
$CDS_LIC_FILE if you need the current picture.)
```

The point the numbers were making survives without them: there was ample
headroom on every feature this flow needs, so licence contention was not the
reason a stage was slow.

Note `Innovus_CPU_Opt` at 2/41 — the pools are not literally idle at all times,
they are merely nowhere near contended. A lane taking an Xcelium seat cannot
starve a Genus or Innovus seat.

**What the correction changes:** the Cadence licence server named by
`$CDS_LIC_FILE` is a **single point of failure shared by both lanes**. A licence-server outage or a network partition
fails the static lane and the backend run together, so a green static lane is not
independent evidence that the backend's environment is healthy. Two consequences
for the design:

- **Do not model lanes as licence-independent.** The capability probe (§6.3) must
  run per lane, at lane start, and `asic-flow-doctor` already opens a TCP
  connection to each licence server — `ci/capability.sh` delegates to it for
  `kind: doctor`, so this is wiring, not new code.
- **A lane that cannot reach the licence server is `UNVERIFIED`, not failed.**
  It is missing evidence, and conflating it with a lint error will send somebody
  to the RTL for an infrastructure problem.

Verilator needs no licence at all, which makes `--verilator-only` the correct
degraded mode when the Cadence pool is unreachable.

---

## 9. The unified status renderer

`ci/lib.sh` already has `ci_summary_table`, but it reads **one**
`verdicts.tsv`. With per-lane directories there are *n*, so add
`ci/lanes-summary.sh`:

```
ci/lanes-summary.sh <run-dir>          # markdown to $CI_SUMMARY_FILE or stdout
ci/lanes-summary.sh <run-dir> --exit   # ...and exit non-zero if any lane is red
```

- **Discovery is the directory listing**, `<run>/ci/*/verdicts.tsv` plus
  `<run>/ci/verdicts.tsv` for the ladder. The lane's identity is its directory
  name; its metadata is the `owner` file beside it, which already carries lane,
  pid, host and start timestamp.
- **The record grammar does not change.** Four tab-separated fields — timestamp,
  status, gate id, detail — as `_ci_record` writes them. Gate ids are already
  namespaced `<tier>.<subject>[.<detail>]` and are meant to be grepped across
  runs, so do not rewrite them per lane.
- **A lane directory with no `verdicts.tsv` is `UNVERIFIED`, not absent.** A lane
  that was launched and produced no verdict file is the exact case this whole
  document exists to make visible. `ci_summary_table` already has the right
  instinct for the single-file case — it prints *"no gates recorded — the tier
  did not run"* rather than an empty table — and the renderer must keep that and
  make it red.
- **A lane still holding its lock is `RUNNING`**, rendered as such and not as a
  pass. Reuse the §3 liveness test (pid + host + start time) rather than
  inventing a second one.
- **This is where a lane failure finally becomes an exit status**, since the
  wrapper never propagates one (§6.6). `--exit` is what CI keys on.

---

## 10. Order of work

1. **Remove `.NOTPARALLEL:`** from `ASIC/eth-chiplet/design.mk:477` and its stale
   comment at `:472-476`. One line; the §4 toolkit change makes it safe, and
   nothing else in this list buys anything until it is gone.
2. **Atomic write** at `Makefile:326-329`. Two lines; removes the silent
   short-read immediately (§5).
3. **The preflight** and the runner assertions (§5 table). This is the real D3
   fix and the largest single piece.
4. **`asic-flow-lane`** (§6), reusing `asic-flow-lock`'s lock handling verbatim.
5. **`ci/lanes-summary.sh`** (§9). Until this exists, lanes that never propagate
   an exit status are invisible to CI — do not ship 4 without 9.
6. **Shell tests** for 4 and 5 under `ASIC/asic-toolkit/test/shell/`, following
   `t_flow_mk_guards.sh`'s pattern: assert the property, then **mutate the guard
   away and assert the check goes red**. A lane test that cannot fail is worth
   less than no test, and this suite's whole character is that every guard has a
   mutation proof next to it.

---

## Appendix — what was changed to produce this document

Both changes are in the **`ASIC/asic-toolkit` submodule**, which is a separate
repository shared with other projects. They are working-tree edits, uncommitted.

- `ASIC/asic-toolkit/ci/lib.sh` — the verdict-collision guard (§3). Adds
  `CI_LANE`, `_ci_host`, `_ci_starttime`, `_ci_owner_alive`, and a pre-truncate
  check in `ci_init`. No existing function signature changed.
- `ASIC/asic-toolkit/mk/flow.mk` — `all:` as a recipe (§4).

Nothing in this repository was changed except the addition of this file.
