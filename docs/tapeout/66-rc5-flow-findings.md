# rc5 virtual tapeout — flow findings

    status   LIVE. Appended as the run produces them.
    run      rc5vt-20260829, worktree /home/dam1n19/SoCLabs/rc5vt-20260829
    branch   flow/rc5-virtual-tapeout
    purpose  Validate the flow end to end. NOT a submission — rc4
             (md5 6b0833c4216bdb683ed2427cd0deba75) is the 1 September candidate
             and is already published. A RED result here is the product.

Findings are numbered in the order the run surfaced them. Each records what was
measured, not what was inferred.

---

## F1 — `make all` does not build its own firmware prerequisite

**Measured.** A clean worktree, all 44 submodules at their pinned commits,
preflight green. `make all` reached the ROM stage and stopped:

    FAIL: .../stage0_bootrom.hex not built — build firmware first:
          make -C .../nanosoc-multicore-system firmware
    make[3]: *** [ASIC/common.mk:433: eth-bintxt] Error 1

The message is honest and even names the remedy, but `all:` (`mk/flow.mk:637`,
`syn -> place -> cts -> route`) declares no firmware dependency. So the
documented one-command flow cannot run from a clean checkout.

**Cost if it had failed later:** none here — it stopped in seconds. That is the
fail-fast ordering working, and is worth preserving.

**Fix:** make the ROM stage depend on the firmware target, or have `all:`
declare it. Either way the dependency should be in the graph, not in a
diagnostic string.

---

## F2 — `make firmware` is a SILENT NO-OP in a clean tree, and exits 0

**This is the more serious one, because nothing reports it.**

**Measured.** Running the remedy F1 names produced **zero** `.hex` and zero
`.elf` files and returned **exit code 0**. The cause is one informational line:

    -- nanosoc-multicore-system: nanosoc_memmap.cmake not found in
       .../build_soc/firmware - skipping firmware/ targets.

CMake treats the missing generated input as informational, skips every firmware
target, reports "Configuring done / Generating done", and exits clean. The build
directory is created, so a later check for "did the build run" also passes.

`build_soc/` is produced by `make soc` in the same Makefile. **`firmware` does
not depend on `soc`.** The working sequence is:

    make -C nanosoc-multicore-system soc
    make -C nanosoc-multicore-system firmware      # 48 hex/elf, boot ROM present

**A SPECULATION OF MINE THAT WAS WRONG, recorded because it changes the
severity.** On first inspection the main tree's `build_soc/firmware/nanosoc_memmap.cmake`
is a symlink dated 18 August, and I suggested it had been created by hand — which
would have meant the design was unbuildable from clean anywhere. It was not:
`make soc` creates that symlink itself, and did so in the worktree at 20:46. The
18 August date merely records when `soc` last ran in the main tree. The design IS
reproducible from clean; it just needs a step nothing declares.

**Fix:** `firmware:` should depend on `soc`, and the "skipping firmware/ targets"
path should be a hard error when the caller asked for firmware. A build that is
asked to produce a binary and produces nothing must not exit 0.

---

## Class note

F1 and F2 are the same defect wearing different clothes: **an undeclared
dependency, discovered only because the artefact was checked rather than the
exit code.** F2 in particular is this project's signature failure — the third
instance in one day, after `git submodule update` printing two `fatal:` lines
and returning 0, and the Tcl parse gate reporting all 32 files unbalanced
because a helper script was missing.

---

## F3 — POSITIVE: the boot ROM reproduces byte-for-byte after six weeks

The first hard reproducibility result on this project, and it is a good one.

**Measured.** `make soc && make firmware` in a clean worktree, from the pinned
submodule commits, produced a stage-0 boot ROM identical to the copy the main
tree has been carrying since 17 July:

    527b1c9e3a20f03ef7b41063fc7f59c6   worktree, built 2026-08-29 from clean
    527b1c9e3a20f03ef7b41063fc7f59c6   main tree, built 2026-07-17

**Why it matters.** rc4's ROM content descends from that July binary. The
standing concern was that it survived only as an artefact in one working
directory and could not be regenerated — the same shape as the two hold-corner
definitions. It can: the toolchain, the sources and the generated memory map
compose to the same bytes six weeks later.

This is a POSITIVE control for F2 as well. It shows the silent no-op was purely
a missing dependency, not a broken or non-deterministic build.

**A CHALLENGE TO THIS FINDING, RAISED AND RESOLVED.** A peer review noted that
"from the pinned submodule commits" composes badly with the `pins.reachable`
failure: the toolkit pin `c6ce42d` is on no remote, so anything said to be
reproducible "from the pins" might be reproducible on this disk only.

Checked, and it does not apply here. The firmware is built by cmake and
arm-none-eabi-gcc inside `nanosoc-multicore-system`; the ASIC toolkit is not in
that path. The only reference to it in that Makefile (:261) feeds a
`vendor-check-sync` target that is explicitly written to skip when absent, and
the path it computes is missing in BOTH the worktree and the main checkout. The
pin F3 actually depends on -- `nanosoc-multicore-system` at f60449b491d5 -- IS
on its remote, contained in `origin/dma250-ctxram-shrink`.

So F3 is reproducible by someone else. What the unpushed toolkit pin blocks is
recreating this WORKTREE to re-run the ASIC flow, which is a different and still
open problem. The two findings should be read together, but they do not overlap.

**Scope, stated so it is not over-read.** This covers the stage-0 boot ROM
only, on one machine, with the toolchain currently installed. It says nothing
about the other 47 firmware artefacts, and nothing about whether the ASIC flow
downstream of it is reproducible.

---

## F6 — the floorplan-hazard gate now refuses on the SHIPPED lineage's own netlist

**This one is about rc4, not just rc5.**

rc5's synthesis completed and the flow then stopped at the pre-P&R floorplan gate:

    check_floorplan_hazards: COULD NOT MEASURE
      2 place_macro pattern(s) did not resolve against ..._gate_power.v
      Exiting 2.  A check that measures nothing must not pass.

That refusal is correct behaviour and exactly the discipline this project has been
building. The problem is what it refuses on.

**Isolated by experiment.** Running the same checker with the same floorplan against
**rc1's own netlist** produces the identical failure, same two patterns. So it is not
rc5's netlist:

    rc5 netlist  -> 2 patterns unresolved
    rc1 netlist  -> 2 patterns unresolved      <- the SHIPPED lineage

**And everything else is identical.** rc1's pinned floorplan and rc5's pinned floorplan
are the same file (md5 7731a050be86, 21 place_macro patterns, zero differing lines).
The macro instances are the same: 21 in each netlist, and a set-difference of the
(cell, instance) pairs is EMPTY both ways. `check_floorplan_hazards.py` has no commits
after 2026-08-25 16:32, which is before rc1 ran.

**Yet rc1's stored report says `verdict = PASS`, `hard = 0`, `netlist_macro_instances = 21`,
written 2026-08-26 02:36.**

So a gate that guarded the shipping floorplan passed on 26 August and refuses on the same
inputs today, through something that is neither the checker file, the floorplan, nor the
netlist. Two readings, and they need different responses:

  (a) it was passing VACUOUSLY before and is now correctly refusing -- in which case the
      rc1/rc4 lineage never had a real floorplan-hazard result; or
  (b) something in its environment has regressed -- in which case the gate is broken now.

**Either way the rc1/rc4 floorplan-hazard PASS is not currently reproducible**, and that
is worth knowing two days before tapeout. It does not by itself indicate a defect in the
silicon: the hazard classes it grades were separately clean on rc1, and rc4 is
DRC-identical to the lineage it descends from.

**NOT BYPASSED.** rc5 is stopped at this gate. Overriding a check that refuses to measure
is precisely the move this project's discipline exists to prevent, so it waits for a
decision rather than an `EVP_*` escape hatch.

---

## F7 — F6 RESOLVED: the gate's ROM LEFs came from a gitignored directory, so it only ever worked in one checkout

**Answer to F6: NEITHER reading (a) nor (b). rc1 was not vacuous, and the gate has not
regressed. The gate is correct and was correct; its LEF *search path* was not portable.**

### The two patterns are the two boot ROMs

`check_floorplan_hazards.py` resolves each `place_macro` glob against a hierarchical
walk of the gate netlist, and that walk only emits an instance as a *macro* if some
LEF it read declared that cell (`netlist_macro_instances(..., macro_cells, ...)`,
`if cell in macro_cells`). Instrumenting the resolver on rc5's netlist:

    macro cells declared by the LEFs found : 7      (expected 9)
    macro instances found in the netlist   : 19     (expected 21)
    place_macro patterns                   : 21
      BAD  n=0   *u_network_core*u_region_bootrom_0*rom_via*
      BAD  n=0   *u_chip_core*u_region_bootrom_0*rom_via*
      OK   n=1   x19

The two unresolved patterns are exactly the two boot ROMs, and the two missing cells
are exactly `rom_via` and `eth_rom_via`. Nothing else is involved.

### Why the cells were missing

`lef_globs()` looked in two places: `$MEM_BASE/*/*.lef`, and `<repo>/ASIC/romlibs/*/*.lef`.

**`ASIC/romlibs` is gitignored** — `.gitignore:200`, `git ls-files ASIC/romlibs` returns
nothing. It is a compiled output that exists in the checkout it was built in and nowhere
else: not in a git worktree, not in a fresh clone, not in CI.

rc1 ran in the main checkout, where that directory happens to exist, so the ROM cells were
declared, all 21 patterns resolved and the gate measured. rc5 runs from the
`rc5vt-20260829` git worktree, where the path does not exist at all. Same checker, same
floorplan, same netlist content — different filesystem.

Meanwhile the *flow* had already moved on. `ASIC/rom_build.mk` compiles both ROM macros
**per run** into `$(RUN_DIR)/romlibs`, `ASIC/eth-chiplet/design.mk:692` exports
`ROMLIBS_DIR` pointing at it, and `config/design_config.tcl:101-107` gives that variable
first precedence when it builds `DESIGN_LEFS`. rc5's preflight even prints
`OK: this run's ROMs are staged and pinned (.../build/rc5vt-20260829/romlibs)`.
So Genus and Innovus read this run's ROM LEFs while the hazard gate was still looking for
a shared directory the run does not use — and in a worktree, does not have.

This is the *"clean checkout builds different silicon"* class again, in its milder form:
the flow reads the worktree, and a check that hardcodes a path outside the run's own
inputs is measuring a different design from the one being built.

### Proof, both directions

Supplying the run's own ROM LEFs explicitly with `--lef`, changing nothing else:

    21/21 patterns resolved, 21 netlist macro instances, 9 macro LEF cells declared
    VERDICT: PASS  (0 hard, 8 class-3 advisories)

### Reading (a) is refuted by rc1's own stored census

rc1's `reports/floorplan_hazards.json` records `patterns_resolved: 21`,
`patterns_unresolved: 0`, `macro_lef_cells_declared: 9`, `netlist_macro_instances: 21`,
`macro_edges_tested: 42`, `escape_pins_tested: 1994`. A vacuous run cannot produce those
numbers — the checker raises before writing JSON when anything is unresolved, which is
why rc5 produced no JSON at all. **The rc1/rc4 lineage did have a real floorplan-hazard
result covering all 21 macros.** rc4's shipped floorplan is not implicated.

### The fix (not an override)

`scripts/ci/check_floorplan_hazards.py`, `lef_globs()` now searches, in precedence order:

    $MEM_BASE/*/*.lef
    $ROMLIBS_DIR/*/*.lef        <- NEW: this run's own compiled ROMs, when set
    <repo>/ASIC/romlibs/*/*.lef <- kept as the fallback for a shared-tree run

`cell_lef` records cells with `setdefault`, so the run's ROMs win over the shared drop —
the same precedence `design_config.tcl` gives them, so the gate now reads the two macros
the flow actually places rather than whichever copy a shared directory happens to hold.

Two smaller defects fixed alongside, both of which cost time here:

* **The failure printed almost none of what it knew.** `main()` discards `Report.lines`
  on a `Vacuous` and prints only the exception, so `PATTERN RESOLUTION FAILED` and the
  per-pattern hit counts were assembled and thrown away. The exception now carries the
  failing patterns, the instance and declared-cell counts, and the LEF globs searched.
* **`globs` was unbound when `--lef` was given**, so the "no macro LEF parsed" refusal
  would have raised `NameError` instead of refusing cleanly. Bound in both arms.

### Verification

* `--selftest` (all six sections, including the discrimination arm that proves each
  suggested move clears the finding it was suggested for): **PASS**
* Without `ROMLIBS_DIR`: still refuses, now naming the two patterns, the 19/21 instance
  count, the 7/9 cell count and the globs it searched.
* `make floorplan-hazards` through the real entry point with rc5's pins: **PASS**,
  `reports/floorplan_hazards.json` written.
* **rc5's result is substantively identical to rc1's**: every one of the 18 census rows
  equal, `counts` equal (`1:0, 2:0, 3:8, 4a:0, 4b_halo:3`), and the set-difference of
  (class, macro) findings is EMPTY in both directions.

### NOTHING WAS OVERRIDDEN

No `EVP_*` escape hatch, no `--strict` relaxation, no gate skipped. The hard classes
(1, 2, 4a) are measured and zero on rc5's real inputs. The 8 class-3 entries are the same
over-approximating advisories rc1 carried and shipped with.

### What this leaves open

The gate has never run in CI or in a fresh clone, because it *could not* — it would have
refused there for this reason every time. That it passed for weeks is evidence about one
directory on one host, not about the check. Any future "this gate passes" claim should
name the checkout it passed in.

---

## F8 — the same defect a second time: the MMMC also read the gitignored ROM directory, so P&R and synthesis were never reading the same ROM

**Found by relaunching after F7. Forty seconds into the place stage:**

    **ERROR: (TCLCMD-995): Can not open file
      '<repo>/ASIC/romlibs/cc_rom/rom_via_ss_1p08v_1p08v_125c.lib' for library set
    **ERROR: (TCLCMD-995): Can not open file
      '<repo>/ASIC/romlibs/eth_rom/eth_rom_via_ss_1p08v_1p08v_125c.lib' for library set
    **ERROR: (IMPSE-110): File '.../nanosoc_eth_chiplet_pads.mmmc' line 56: errors out.
    make: *** [flow.mk:498: place] Error 1

`nanosoc_eth_chiplet_pads.mmmc:24-25` set the two boot-ROM directories from
`$design_home/ASIC/romlibs` — the same gitignored path F7 was about, absent in this
worktree.

### This is not just F7 again in a second file. It is a live inconsistency

Three files decide where the boot ROMs come from, and **only two of them had been
migrated to the per-run build**:

| file | resolves ROMs from | used by |
|---|---|---|
| `scripts/config.tcl:156-162` | `$ROMLIBS_DIR`, else shared | **synthesis** (Genus) |
| `config/design_config.tcl:101-107` | `$ROMLIBS_DIR`, else `DESIGN_HOME`, else `NANOSOC_ETH_CHIPLET_HOME` | **synthesis** (`DESIGN_LEFS`/`DESIGN_LIBS_*`) |
| `scripts/*.mmmc:24-25` | `$design_home/ASIC/romlibs`, **no override** | **P&R** (`read_mmmc`) |

So in every run to date on the main checkout, Genus read the run's own freshly compiled
ROM Liberty and Innovus read the shared drop. That is precisely the split the per-run ROM
build was introduced to close — `config.tcl`'s own comment says the macros "are MASK
PROGRAMMED", that the shared drop "shipped holding something else", and that the override
exists so "synthesis, P&R and stream-out read the SAME build". P&R was never included.

**It has been harmless so far, and that is measurable rather than assumed.** The shared
and per-run Liberty for `rom_via` differ in 8 lines, all of them one timestamp
(`Creation Date` / `date`); the LEFs differ only in the `-code_file` path inside a
configuration comment. Same compiler, same `.bintxt`, same bits. The defect is that
nothing in the flow was checking that, and the two directories are free to diverge —
which for a mask-programmed ROM is the failure mode this project has already had twice.

In a worktree the same defect is not harmless at all: it is a hard stop.

### Fix

`ASIC/genus-innovus/scripts/nanosoc_eth_chiplet_pads.mmmc` (and the run's pinned copy,
kept identical):

* `ROMLIBS_DIR` first, `$design_home/ASIC/romlibs` as the fallback — the same precedence
  `config.tcl` and `design_config.tcl` use, so all three now agree;
* a `file isdirectory` check on each ROM directory that errors with the path it computed
  and the variable that produced it, instead of surfacing ten lines later as an
  unattributable "cannot open file" from inside `read_mmmc`;
* **it prints which source it used** — `mmmc: boot ROM macros from <dir> (ROMLIBS_DIR --
  this run's own ROM build)`. Without that line no artefact of the run records which of
  the two directories was opened, because the macros' only textual difference is a
  comment.

`$::env` is used rather than a `config.tcl` global, matching the existing reasoning at the
top of the file: the MMMC is loaded by `read_mmmc`, not `source`d, so config.tcl globals
may not be in scope.

`scripts/checks/fp_guard.py` had the identical `os.path.join(REPO, "ASIC/romlibs")`
assumption in its LEF search and got the same precedence. It is not on the flow's path
today (only referenced from a comment in `post_powerplan.tcl`), so it was latent.

### Verified

Both arms evaluated in `tclsh` against the real filesystem: with `ROMLIBS_DIR` set it
prints the run's romlibs and continues; unset, it raises the named error. Both copies pass
the run's own `tcl_complete.tcl` balance check and are byte-identical to each other.
Place relaunched and got past `read_mmmc`.

### Class

Third instance today of *flows read the worktree*: a path that is correct in one checkout
and absent in every other, discovered only because rc5 is the first run executed outside
the checkout that happens to contain it. rc5 was commissioned to validate the flow end to
end; two blocking defects in the first hour, both invisible to every previous run, is
that validation working.
