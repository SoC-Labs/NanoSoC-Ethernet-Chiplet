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

---

## Numbering note

F7 and F8 above were written by the session driving the rc5 run itself, in
parallel with these. The findings below continue from F9 and cover the FIXES for
F1, F2, F4 and F5, one new defect found while proving them, and what a clean
checkout now does. They were written against `88b05f6`; the two sets do not
overlap — F7/F8 are about the floorplan gate and the MMMC, F9-F12 about the
dependency graph.

---

## F9 — the four undeclared prerequisites are now edges in the graph

**What was wrong.** Four of `syn`'s inputs are generated or external and none of
them is in the repository. Exactly one of the four was declared:

    boot-ROM firmware      NOT declared   -> F1, the ROM stage stopped
    build_soc/ memory map  NOT declared   -> F2, and it failed SILENTLY
    chip wrapper RTL       NOT declared   -> F4, unresolved top instance
    XHB500 crossbar RTL    NOT declared   -> F5, unresolved module, minutes in
    generated sub-flists   declared       (`syn: asic-flist`, and it worked)

The one that was declared is the one that never bit. That is the whole finding.

**What changed.** Prerequisite-only rules, no recipes touched:

    ASIC/eth-chiplet/design.mk:1455   syn: flow-preflight asic-flist chip-wrapper romlibs-check
    ASIC/eth-chiplet/design.mk:1337   chip-wrapper:  delegates to the root make
    ASIC/common.mk:496                eth-bintxt cc-bintxt: firmware-ensure
    ASIC/common.mk:468                firmware-ensure:  build if absent, then ASSERT
    nanosoc-multicore-system/Makefile:139   firmware: $(NANOSOC_MEMMAP_CMAKE)

**Proved, not asserted.** The make database now reads (`make -pRrq` on a goal
that does not exist, so nothing runs):

    syn: dirs check-quiet legacy-paths pad-lef rom-ensure flow-preflight \
         asic-flist chip-wrapper romlibs-check
    eth-bintxt: firmware-ensure
    cc-bintxt:  firmware-ensure

`firmware-ensure` is a prerequisite of BOTH code-file targets on purpose: make
updates any target at most once per invocation, so `make -j` runs one firmware
build and not two. Measured — `make -f common.mk rom-bintxt` printed
`OK: boot-ROM firmware present` exactly once and both code files came back
`unchanged, mtime preserved`.

**The ROM path is covered twice, and both routes lead to the firmware.**
`syn -> romlibs-check -> rom-run -> rom-run-stage -> rom-bintxt` and the cheap
per-stage guard `rom-ensure -> (only if the run has no staged ROMs) -> rom-run`
both arrive at `eth-bintxt`/`cc-bintxt`.

---

## F10 — a build that produces nothing can no longer exit 0

**The F2 defect, reproduced first.** With
`build_soc/firmware/nanosoc_memmap.cmake` renamed away, in an isolated build
tree (`NANOSOC_BUILD_TAG=-f2proof`, so nothing live was touched):

    cmake --preset gcc-m0plus-le        rc=0
      -- nanosoc-multicore-system: nanosoc_memmap.cmake not found in
         .../build_soc/firmware - skipping firmware/ targets.
    cmake --build --preset gcc-m0plus-le   rc=0
    hex=0  elf=0

**The same state, after the fix.** Same renamed-away memory map, same isolated
build tag:

    $ NANOSOC_BUILD_TAG=-f2proof make firmware
    [firmware] nanosoc_memmap.cmake is absent, so CMake would SKIP every firmware
               target and still exit 0. Generating it: make soc
    ... 1m25s ...
    OK: firmware built — 140 hex, 123 elf, stage-0 boot ROM present

**TWO INDEPENDENT DEFENCES, because one of them is a promise made by the thing
that lied.**

1. `firmware: $(NANOSOC_MEMMAP_CMAKE)` — a FILE prerequisite, not the phony
   `soc`. Absent, it is generated; present, nothing happens. The phony would
   re-render `build_soc/` on every firmware build, rewriting the SoC RTL under
   whatever is reading it and undoing a deliberate `soc_model_fpga` render.
2. `nanosoc-multicore-system/Makefile:139` then ASSERTS the stage-0 boot ROM hex
   and a non-zero `.elf` count, and `ASIC/common.mk:468` asserts BOTH hex files
   again after calling it. The callee's exit code is not the caller's verdict.

**The assertion was proved to fail.** Pointed at a stand-in whose `firmware`
target prints "configuring done / generating done" and exits 0:

    == boot-ROM firmware is not built — building it now ==
    [fake] configuring done / generating done
    FAIL: the firmware build reported success and left no .../stage0_bootrom.hex
          A CMake configure that SKIPS the firmware subtree exits 0 and writes
          nothing — look in the log above for 'skipping firmware/ targets'.
    make: *** [common.mk:470: firmware-ensure] Error 1

and to pass, with a stand-in that writes the two files. Both directions, on the
same target, on the same day.

**A POSITIVE, and a third reproduction of F3.** The regenerated `build_soc/` was
compared file-by-file against the copy that was there: 332 files, **329
byte-identical**; the 3 that differ are `interconnect/*/logs/*.log`, differing in
their `Run Date` line and a "Deleting the ... file" section. The boot ROM built
out of that fully regenerated memory map is again
`527b1c9e3a20f03ef7b41063fc7f59c6` — the 17 July bytes, now reproduced from a
regenerated SoC render rather than an existing one. `build_soc/` was restored
from a byte-verified snapshot afterwards.

---

## F11 — the crossbar's absence fails in seconds now, and names the remedy

**Why it took minutes before.** `make asic-flist` sources
`tidelink/set_env.sh`, which generates the XHB500 RTL from the tracked
`deps/xhb500/configs` when it is absent — and when it CANNOT (no
`XHB500_IP_DIR`, no generator, python outside [3.7,3.11)) it prints `[ERROR]`
and **returns 1 into a `source` whose status nothing checked**. The flist was
then written with ~150 paths that do not exist, and the first thing to notice
was Genus, minutes later, naming a MODULE rather than the missing dependency.

**THE 195 MB IS NOT VENDORED IN AND MUST NOT BE.** It is licensed Arm IP and
this repository is public. Only the ~8 KB of generator configs is tracked, which
is correct. The fix is to fail early and say so.

**Three changes, all in the make layer:**

1. `Makefile:621` — after rendering, `asic-flist` checks that every file the two
   generated flists name EXISTS, prints the first five that do not, and fails
   with `make preflight` as the pointer to the remedy.
2. `Makefile:558`+ — each flist is rendered to a `.tmp` and moved only if the
   renderer succeeded AND wrote something. `python3 ... > $@` truncates the
   target before python runs, so a renderer that dies used to leave a
   zero-length flist behind: present, readable, describing no design. Under
   `.ONESHELL` with the default `.SHELLFLAGS` the recipe would not even have
   stopped — only the LAST command's status is the recipe's status. The move is
   also content-preserving (`cmp` first), so a target that runs before every
   `syn` no longer bumps an mtime on a run where nothing changed.
3. `ASIC/common.mk:757` — `flow-preflight`, below.

**The preflight.** `make preflight` at the repo root, `make flow-preflight`
inside the ASIC flow, and a prerequisite of `syn`. **0.6 seconds**, no licence,
no writes. It checks, and prints the fixing command for every line that fails:

    foundry / IP      TSMC_65_HOME, the resolved tech LEF and GDS-out map,
                      PHYS_IP, the Arm target library, CMSDK, Cortex-M0+,
                      the three memory-macro LEFs
    licensed / submodule   XHB500 crossbar RTL (both bridge leaves),
                      tidelink-phy
    generated         build_soc memory map, both boot-ROM hex files, the chip
                      wrapper RTL, both generated sub-flists
    host tools        python3, cmake, arm-none-eabi-gcc
    the flist itself  every file named by flist/nanosoc_eth_chiplet_asic.flist
                      and by each flist it -f-includes — 603 files today

**TWO CLASSES, and the distinction is load-bearing.** `NEEDED` (nothing here can
produce it) is fatal. `PENDING` (a declared prerequisite of `syn` builds it) is
reported and is NOT fatal — preflight is an unordered sibling of the targets
that produce those, so failing on them would be a race that fails a build make
was about to fix. The flist walk applies the same rule: a missing path under
`build/` counts as PENDING, anything else as a failure.

**It walks two levels and says so.** If a level-2 flist ever gains its own `-f`
include, the walk reports `PARTIAL ... nested -f include(s) NOT walked` and
fails, rather than quietly measuring less than it claims.

**Proved in both directions**, by overriding paths on the command line — no
files moved:

    make preflight                                      -> PREFLIGHT: OK, rc 0
    ... TSMC_65_HOME=/nonexistent-pdk XHB500_GEN_DIR=... -> 4 MISSING, rc 2
    ... CHIP_TL_FLIST=<a flist naming 2 absent files>    -> "2 of 3 listed
                                                            files absent", rc 2
    PATH without arm-none-eabi-gcc, hex absent           -> MISSING, rc 2
    PATH without arm-none-eabi-gcc, hex present          -> "not needed here"

The XHB500 failure prints what to do:

    MISSING XHB500 crossbar RTL    .../tidelink/deps/xhb500/generated
            The Arm XHB-500 bridge RTL is LICENSED and is deliberately not
            in this repository (it is public); only the ~8 KB of generator
            configs under tidelink/deps/xhb500/configs is tracked. Absent,
            synthesis elaborates for minutes and then dies naming a MODULE,
            not this. Regenerate it from the tracked configs:
              export XHB500_IP_DIR=<Arm XHB-500 root: the dir holding logical/generate>
              source .../tidelink/set_env.sh

**NOT FIXED, and it is the one thing here that is still only a message.**
`tidelink/set_env.sh` is in a submodule this change does not own, so its
`_generate_xhb500` failure still returns into a `source` nobody checks. The
preflight and the flist check catch the CONSEQUENCE in seconds; they do not
repair the CAUSE. `tidelink/site.env` is also absent in this worktree, so
`XHB500_IP_DIR` and `CMSDK_DIR` come from the environment or not at all — the
generated tree survives here only because it was copied in by hand.

---

## F12 — the chip wrapper stamps a wall-clock time into the RTL it emits

Found while proving F4, and it is small but it invalidates a hash.

**Measured.** `scripts/check_chip_boundary.py --emit` writes

    // Generated: 2026-08-30 13:29:47

into `build/chip/rtl/nanosoc_eth_chiplet_chip.v`. Two fresh emits, 39 seconds
apart, differ in that line and in NOTHING else — same 8622 bytes, same 179
lines, `diff` reports exactly one changed line — and hash differently
(`1b5524ab...` vs `50983e0c...`).

The emitter is otherwise content-preserving: with the file present and the
design unchanged it does not rewrite it, and the mtime survives. So the churn
happens only on a FRESH emit — which is exactly what a clean checkout does.

**Consequences.**
  * The md5 of this file is not the identity of the design it describes. Any
    provenance record that hashes it will differ per checkout while the RTL is
    the same. This run's `PRE_RUN_MANIFEST.txt:21` records
    `chip wrapper 6d41c9c56168230f975e15311c6dd51c`; proving F4 required
    deleting and re-emitting the file, so that value is now stale. The RTL it
    names is unchanged — the A/B diff above is the proof of what a re-emit can
    and cannot change.
  * Same class as the GDS write-clock finding: a generated artefact that carries
    the time it was generated cannot be compared by hash.

**Not fixed here.** `scripts/check_chip_boundary.py` is outside the makefiles
this change owns, and another session is working in that directory. The fix is
one line — drop the timestamp, or move it out of the emitted file — and it
should be taken with the LEC/provenance work rather than folded into a build
change.

---

## What a clean checkout does now

    make preflight        0.6 s. Lists every missing input at once, with the
                          command that fixes each. Fails only on what this
                          repository cannot produce.
    make all              syn's prerequisites now render the chip wrapper and
                          the sub-flists, build the firmware (and the SoC memory
                          map it needs) and build the ROMs — or stop within
                          seconds naming the exact remedy.

The four defects were four different failure DISTANCES from the cause: F1
stopped in seconds with the right message, F4 and F5 stopped minutes in with the
wrong one, and F2 did not stop at all. They are one defect: **an input the build
does not declare is an input nobody renders**, and the only reason three of them
were survivable is that someone had run the tool by hand in this working
directory.

---

## F9 — the CTS hold target that ran is 0.080, not the 0.100 its own rationale derives

`hooks/pre_cts.tcl` devotes a section to the value of the CTS hold target:

    #   CTS hold target   0.100     route hold target 0.080 (design.mk)   (:92)
    # HOLD DECREASES DOWNSTREAM, SETUP INCREASES.
    # WHY 0.100 AT CTS. It is the route target plus the degradation the flow's own
    # stage table above shows between the end of CTS and the end of fill: 03_cts_opt
    # -0.003 to 06_post_fill -0.012 is 9 ps, rounded up to the next 10 ps.   (:111)

`design.mk:1103` ships `CTS_OPT_HOLD_TARGET ?= 0.080`, and rc5's own log confirms what
took:

    CTS: opt_hold_target_slack = 0.08 (was 0.0)

So the asymmetry the hook argues for — **ask CTS for more hold than route, because
post-route hold repair is blunt and expensive** — is not what rc5 runs. CTS and route are
asked for the same 0.080, and the 9 ps of measured CTS→fill degradation the rationale is
built on is not budgeted for anywhere.

This is not a bug in either file; each is internally consistent. It is that the run's
configuration and the run's documented reasoning are two different numbers, and only the
log says which one executed. Recorded because rc5's hold result will be quoted later, and
it is a measurement of **0.080 at CTS with a 0.080 route target**, not of the ladder
`pre_cts.tcl` describes. Whichever value is right, the two files should be made to agree
before this experiment is repeated.

**Not changed mid-run.** Editing it now would make rc5 measure a third thing and would
invalidate the manifest the run started under.

---

## F10 — rc5's hold numbers are against FOUR hold views; rc1's were against two

From rc5's own `pre_cts` hook output, which prints this precisely so the comparison cannot
be made silently:

    CTS: ACTIVE HOLD VIEWS  (4): typical_analysis_view default_analysis_view_hold
                                 av_ml_libset_hold av_ltfix_libset_hold
    CTS: ACTIVE SETUP VIEWS (2): typical_analysis_view default_analysis_view_setup

rc1 ran with two hold views. `pre_cts.tcl` states the consequence up front: "a hold target
met in one view says nothing about the other two", and the endpoint population — hence the
area cost — differs between them.

**Therefore rc5's hold WNS/FEP are NOT directly comparable to rc1's.** rc5 is being graded
by a stricter examiner. A rc5 hold number that looks worse than rc1's may be the same
silicon measured against more corners. Any comparison in either direction has to say which
view set it is over. This is the mmmc gap the 2026-08-28 timing audit opened being closed,
and it landed between rc1 and rc5.

---

## F11 — MEASUREMENT 1 ANSWERED: extreme effort makes the useful-skew pass RUN for the first time, and it finds nothing

**Answer: still 0 skewed sinks — but for a completely different reason than before, and the
metric `pre_cts.tcl` chose to test this could never have told them apart.**

### The knobs took

    CTS: design_flow_effort = extreme (was standard)
    CTS: opt_skew_ccopt = extreme (was standard)
    CTS: opt_hold_target_slack = 0.08 (was 0.0)
    CTS: opt_setup_target_slack = 0.0749 (was 0.0)
    CTS: pre_cts set 4 attribute(s)

and ccopt behaved measurably differently as a result. Three attributes appear as
non-default in rc5's ccopt log and are **absent from rc1's**:

    ccopt_cluster_when_starting_skew_adjustment: true (default: false)
    cts_manage_local_overskew: true (default: false)
    cts_approximate_balance_buffer_output_of_leaf_drivers_that_meet_skew_target: true (default: false)

GigaOpt was invoked with `-usefulSkew ... -ensureReclusterForSkew -usefulSkew`; rc1's
invocation carries `-usefulSkew` once and never reaches the pass.

### THE TWO LOG LINES ARE NOT THE SAME LINE, AND THAT IS THE FINDING

`pre_cts.tcl:39-41` builds its whole case on this quotation from rc1:

    Found 0 advancing pin insertion delay (0.000% of 58618 clock tree sinks)
    Found 0 delaying pin insertion delay (0.000% of 58618 clock tree sinks)

In rc1 that line sits at **log line 78**, inside `CCOpt::Phase::PreparingToBalance`, before
any clustering has happened. It is a **census of insertion-delay adjustments already
present on entry**. It is not a report of what CTS scheduled, and it cannot become one: it
is printed before the work.

rc5 emits that same line, in the same place, also 0 (line 1018). **And then, 4,286 lines
later, it emits something rc1 never emitted at all:**

    Useful skew: advancing
    ======================
    Found 0 advances (0.000% of 58611 clock tree sinks)

    Useful skew: delaying
    =====================
    Found 0 delays (0.000% of 58611 clock tree sinks)

`grep -c "Found .* advances\|Found .* delays"` over rc1's ccopt log returns **0**. The
useful-skew pass did not run in rc1. In rc5 it ran, and reported zero candidates in both
directions.

### What that changes

* **The hypothesis is refuted.** `pre_cts.tcl` argued that CCOpt "simply does very little
  of it at the default effort" and that the lever "has never been pulled". The lever has
  now been pulled. The pass runs, examines 58,611 sinks, and schedules nothing.
* **rc1's zero measured nothing.** It was a pre-balance census that would have read 0
  whatever effort was set — as rc5 demonstrates by reading 0 on the very same line while
  the tool goes on to do demonstrably different work. Another instance of the project's
  *"a zero that measured nothing"* class, and this one was load-bearing for a design change.
* **rc5's zero is a real negative.** The pass ran and declined. That is evidence about the
  design, not about the configuration.

### Why zero, most likely — LABELLED AS HYPOTHESIS, NOT MEASURED

Setup was already closed entering CTS (`01b_place_opt` setup WNS **+0.002**, 0 failing
endpoints). CCOpt's useful skew advances and delays sinks to move *setup* slack between
adjacent stages; with no failing setup endpoint there is no slack to redistribute and every
candidate move is rejected. If that is right, useful skew is not a lever for this design's
hold problem at all — the two are only coupled through setup, and setup is not the
constraint. **Not tested here.** The experiment that would test it is a CTS run at extreme
effort against a database that still carries failing setup.

### What is NOT claimed

That extreme effort was wasted. It also enabled the three clustering attributes above and
produced a materially different tree — `skew_group clk` skew 1.541 (rc1: 1.676),
`D2D_RX_CLK_0` 0.545 (rc1: 0.441), and different insertion delays throughout. Whether that
tree is better is a question for the hold and setup numbers, not for this section.

---

## F12 — MEASUREMENT 2 ANSWERED, IN TWO HALVES: the CTS hold target works completely, and rc5's own setup-recovery pass then deletes the repair

**This is the most consequential result of the run and it needs both halves stated
together, because either one alone is misleading.**

### Half one: the hold target works, and it works better than anyone projected

`opt_design -post_cts -hold` with `opt_hold_target_slack = 0.080`, from the tool's own
`opt_design Final Summary`:

    Hold mode           all      reg2reg   reg2cgate  default
    WNS (ns):          0.003      0.003      0.082      0.083
    TNS (ns):          0.000      0.000      0.000      0.000
    Violating Paths:     0          0          0          0
    All Paths:       1.09e+05   1.02e+05     3009       4575
    Density: 85.282%

**Hold closed completely at CTS: WNS +0.003, TNS 0.000, ZERO violating paths out of
109,000 — against FOUR active hold views.** It entered the pass at -0.703 / 8,893 failing.

rc1, for contrast, reached -0.003 / 43 failing against TWO hold views. rc5 is positive,
has no failing endpoints at all, and is graded by a stricter examiner (F10).

The price is visible and was paid in area: density 79.105% (preCTS) → **85.282%**, i.e.
**+6.18 points** of standard-cell density spent on hold repair. `pre_cts.tcl` said this
cost was "a projection and not a number". It is now a number.

### Half two: the recovery pass then throws all of it away

`hooks/post_cts.tcl`'s setup-recovery pass — the one thing in that file that is "NOT A
RESTORE", added for rc5 — ran next, with the hold target still set (`opt_hold_target_slack
0.08` is in its own attribute dump). Straight from the log, two consecutive QOR lines:

    CTS: QOR after opt_design -post_cts -hold   | setup  0.066 / 0 | hold  +0.003 /    0
    CTS: QOR after post-hold setup recovery     | setup  0.082 / 0 | hold  -0.700 / 8718

**It bought 16 ps of setup and gave back 703 ps of hold and 8,718 endpoints.**

And it did not merely fail to preserve the repair — it *removed the cells*:

    density after opt_design -post_cts -hold   85.282%
    density after the setup-recovery pass      80.575%

Nearly all of the +6.18 points of hold-repair area was ripped out. The hold state handed
to route is -0.700 / 8,718, essentially identical to the -0.703 / 8,893 that existed
*before* the hold pass ran. The hold pass's ~25 minutes and 6 density points bought
nothing that survived the same stage.

### Why the rationale did not transfer, and why the file said so

`design.mk:1105-1130` derives the recovery pass from a measurement taken **at route**:

> at route, a heavy hold pass took setup from +0.010 to -0.023 AND introduced 6 real
> max_capacitance and 2 real max_transition endpoints where there had been none, and the
> setup pass run after it put setup back to +0.025, **kept the hold repair**, and returned
> both DRV counts to zero for 12 cells and 8 min 15 s.

At route the setup pass kept the hold repair. **At CTS it does not.** The same file
already flagged the risk in as many words:

> NOT MEASURED AT CTS. Every one of those numbers is post-route. No run on this design has
> ever issued a second `opt_design -post_cts`.

rc5 is the run that measures it. The answer is that the move is actively harmful at CTS,
and by a margin of roughly 44:1 in picoseconds against 8,718 endpoints to nothing.

The plausible mechanism — **hypothesis, not measured here** — is that at CTS the design is
pre-route with estimated parasitics and cells can still move freely, so the setup pass
legalises and re-optimises across the whole core and treats the hold buffers as free area
to reclaim; at route the placement is frozen and detail-routed, so the same pass can only
resize a handful of cells and physically cannot delete 4.7 points of density.

### The consequence for this run

Route is running on the **post-recovery** database, so rc5's route result is a measurement
of a design with -0.700 / 8,718 hold entering route, not of the hold-clean database the
CTS target produced. That makes rc5's answer to measurement 3 a test of the configuration
as staged — which is worth having — but it is *not* a test of "what does route do when CTS
hands it closed hold". That experiment has not been run.

### THE FIX, AND WHY IT IS NOT BEING APPLIED MID-RUN

Disable the recovery pass at CTS (`post_cts.tcl` gates it on `CTS_OPT_HOLD_TARGET` being
non-empty, and `design.mk` documents setting it to 0 for the stock two-pass order), keeping
it at route where it is measured to help. The hold pass alone leaves setup at +0.066 with
zero failing setup endpoints — there is nothing for the recovery pass to recover.

Not changed now: rc5 started under a staged manifest, and editing a pinned hook mid-flight
would make the run measure a third configuration and invalidate its own provenance. The
change belongs to the next run, with this section as its justification.

---

## F13 — MEASUREMENT 3, FIRST ATTEMPT: route hard-failed at a PRE-route gate, on a path that exists only because of F12

Route ran for 3 minutes and refused before routing anything:

    ROUTE-FAIL: clock source latency is asymmetric by 0.84 ns between
    ROUTE-FAIL: the capture and launch sides of the worst hold path.
    ROUTE-FAIL: That makes every hold number in this run fiction.
    ROUTE-FAIL: FIX CTS, NOT ROUTE.
    ROUTE-FAIL: strict mode is set - stopping here.

### What the gate actually looked at

`reports/nanosoc_eth_chiplet_pads_srclat_precheck.rep`, from
`report_timing -early -max_paths 1 -path_type full_clock`:

    Path 1: VIOLATED (-0.700 ns) Early Output Delay Assertion
                   View: av_ltfix_libset_hold        Group: rmii_ref_clk
             Startpoint: (R) .../u_rmii_to_mii/rmii_txd_reg[1]/CP    Clock: rmii_ref_clk
               Endpoint: (R) RMII_TXD[1]                             Clock: rmii_ref_clk

                           Capture       Launch
             Clock Edge:+    0.000        0.000
            Src Latency:+    0.000       -0.840
            Net Latency:+    0.000 (P)    0.794 (P)
           Output Delay:-   -2.000

**The endpoint is a primary output port, not a register.** There is no capture clock
*network*: the capture reference is a `set_output_delay -min -2.000 -clock rmii_ref_clk`
assertion, so `Src Latency` and `Net Latency` on the capture side are 0.000 by
construction. The 0.84 ns is the launch clock's own `-source` latency measured against
nothing, not skew between two clock paths.

### The gate's taxonomy has three categories and this path is in none of them

`flow/innovus/4_route.tcl:810-865` classifies the worst early path as:

| case | action |
|---|---|
| cross-clock (launch clock name != capture clock name) | do **not** gate on delta; test only the zero-signature |
| same clock, delta > `ROUTE_SRCLAT_TOL` | **FAIL** |
| same clock, symmetric | pass |

Here both ends print `Clock: rmii_ref_clk` — the output delay is *referenced* to that clock
— so `srclat_xclk` is false and the path takes the same-clock branch and fails.

The file's own comments show it has already been burned once by exactly this shape of
mistake, and it says so: a cross-clock path "can never pass a 50 ps tolerance - on ANY
database, however good ... A perfectly healthy run, permanently blocked by a gate reading a
number that was never skew." A **port endpoint** is the same problem one category over, and
it was not anticipated. Note too that `route_srclat_zero` would also have fired here
("capture lost it"), for a zero that is structural rather than a writeback defect.

### But the gate is NOT simply wrong, and this run is not going to pretend it is

Two things are true at once:

1. Its *diagnosis* is misdirected for this path. "FIX CTS" cannot help an output-delay
   assertion, and "every hold number in this run is fiction" does not follow.
2. There may still be a real constraint question underneath — whether the RMII output
   budget should be computed against a clock reference that carries -0.840 ns of source
   latency on the launch side and none on the capture side is an **SDC** question, and it
   has not been answered here.

So the gate was **not patched, not relaxed and not bypassed.** `ROUTE_HOLD_SANITY=0` exists
and was not used.

### The decisive observation: this path is a symptom of F12

`report_timing -early -max_paths 1` returns whatever the single worst early path happens to
be. From the QOR tables, hold in the `reg2out` group was:

    after opt_design -post_cts        reg2out  -0.703 / 3 failing
    after opt_design -post_cts -hold  reg2out  +0.083 / 0 failing   <- CLOSED
    after the setup-recovery pass     reg2out  -0.700 / 3 failing   <- reverted

**With the F12 recovery pass disabled, `reg2out` is +0.083 and the worst early path is an
ordinary internal `reg2reg` path at +0.003**, whose launch and capture source latencies are
the same number because both ends sit on the same clock network. The gate would then have a
symmetric path to look at and would pass on its own terms.

That is the experiment attempt 7 runs: fix the defect that is proven (F12) rather than the
one that is arguable (this one), and see whether the gate clears itself.

### Still a real latent defect

Whatever attempt 7 shows, the gate will misfire on any design whose worst early path is an
I/O delay assertion. The fix belongs in `asic-toolkit` (`ASIC/asic-toolkit` is a submodule
pinned at `c6ce42d`, so it is not this run's to change): add a fourth category — endpoint is
a primary output/input, identified by the `Delay Assertion` marker on the `Path N:` line —
and treat it like the cross-clock case: report the number, do not gate on it, and skip the
zero-signature test, because a zero capture source latency is structural there.

---

## F14 — F12 PROVEN BY CONTROLLED EXPERIMENT, and the flow reaches GDS

Attempt 7 re-ran **cts → route** from the same placed database with one thing changed:
`CTS_POST_HOLD_SETUP=0` on the make command line. It is a documented knob
(`post_cts.tcl:90`, `design.mk:1126` uses `?=`). **No pinned file was edited, no gate was
patched, relaxed or bypassed**, and the preflight's byte-identity check on every pinned
input passed unchanged.

### Everything before the recovery pass reproduced bit for bit

    stage                       attempt 6                    attempt 7
    02_cts                setup 0.076/0  hold -0.701/9122   IDENTICAL
    after ccopt_design    setup 0.076/0  hold -0.701/9122   IDENTICAL
    after -post_cts       setup 0.050/0  hold -0.703/8893   IDENTICAL
    after -post_cts -hold setup 0.066/0  hold +0.003/   0   IDENTICAL

The useful-skew result reproduced too: the pass ran, `Found 0 advances` / `Found 0 delays`
of 58,611 sinks. **F11 is deterministic.**

### The single variable, and its effect

    03_cts_opt   attempt 6 (recovery pass ON)   setup +0.082/0   hold -0.700/8718
    03_cts_opt   attempt 7 (recovery pass OFF)  setup +0.066/0   hold +0.003/   0
                                                CTS-WARN: CTS_POST_HOLD_SETUP=0 -
                                                no setup recovery after the CTS hold pass.

Same inputs, one knob, 16 ps of setup against 703 ps of hold and 8,718 endpoints. **F12 is
no longer an inference from two adjacent measurements; it is a controlled result.** The
hold-repair cells survive into the written database — `cts.summary.gz` density is 85.282%
in attempt 7 where it was 80.575% in attempt 6.

For the first time on this design, CTS handed route a database with **zero failing setup
endpoints and zero failing hold endpoints**.

### F13 cleared itself, exactly as predicted

    ROUTE: clock source latency symmetric to 0.0 ns - hold view is sane

The worst early path is now internal, and symmetric:

    Path 1: MET (0.003 ns) Hold Check ... u_tidelink/u_link_clk_div/byp_en_r_reg/D
                           Capture       Launch
            Src Latency:+   -1.222       -1.222

The attempt-6 refusal was a symptom of F12, not a property of the design. Fixing the proven
defect cleared the arguable one without touching it.

**The underlying gate defect is still real and still worth fixing**, and attempt 7 supplies
the diagnosis in one line. The two gates that ask this question select paths differently:

    CTS gate 3   (3_cts.tcl:1213)  report_timing -early ... \
                                     -from [all_registers -clock_pins] \
                                     -to   [all_registers -data_pins]     <- reg2reg only
    route gate   (4_route.tcl:815) report_timing -early -max_paths 1 -path_type full_clock
                                                                          <- ANY path

That is why, in attempt 6, CTS gate 3 said *"hold path source latency symmetric to
0.0000 ns"* and the route gate 3½ hours later said *"asymmetric by 0.84 ns ... FIX CTS"* —
about the same database. **The fix is to give the route probe the same `-from`/`-to`
restriction the CTS probe already has.** It belongs in `asic-toolkit` (submodule, pinned at
`c6ce42d`), so it is not this run's to land.

## MEASUREMENT 3 ANSWERED: route completes and produces a GDS, then hard-fails its budget gate

    == STAGE route starting 2026-08-30T16:55:10 ==
    == STAGE route FAILED  2026-08-30T18:25:31 ==   (90 min)

**Route did all of its work.** It produced `work/..._routed`, `outputs/..._pnr.v`,
`..._pnr_pg.v` and a 341 MB `outputs/nanosoc_eth_chiplet_pads.gds`. rc5 therefore went
**RTL → GDS end to end**, which was the run's purpose.

### Where it beats rc1 outright

| | rc1 | rc5 attempt 7 |
|---|---|---|
| `check_drc` | **could not be measured** — no `Total Violations` trailer, "its count of 0 is not evidence of anything" | **0 violations, positively attested** (`drc_attested clean-sentinel`) |
| unrouted nets | 1 net with no global route (`...RAMCLD0WDATA_123`) | **0 net(s) have incomplete routes** |
| declined open nets | 4 | none |
| router-message gate | FAILED | **clean over 6 session logs** |
| setup at post-fill | +0.009 / 0 | **+0.105 / 0** |

The bit-123 net that has sunk earlier runs is routed. (Every `RAMCLD0WDATA_123` string in
rc5's log is inside echoed Tcl — `@file NNNN: #` — not a router message.)

### Why it still hard-failed

    ROUTE-FAIL: signoff budgets exceeded:
      380 missing power vias over {M1 AP} > budget 0
          (M3->M4 16, M4->M5 192, M5->M6 106, M6->M7 45, M7->M8 1, M8->M9 3, M9->AP 1; VDD VSS)
      PG opens 51            > budget 0  (IMPVFC-200)
      dangling PG wires 727  > budget 0  (IMPVFC-94)
      hold FEP 66            > budget 0  (WNS -0.100)
      max_transition FEP 195 > budget 0  (worst -6.023)
    ROUTE-FAIL: strict mode is set - stopping here.

`51 opens / 727 dangling` are the standing PG known-bad this project already carries
(rc4's evidence record names exactly those two numbers). The PG-via count and the two
timing rows are the actionable items.

### The route stage repeats F12's mistake, one seventh the size

`ROUTE_OPT_MODE hold_then_setup`, `ROUTE_OPT_SETUP_RECOVERY true`:

    04_route (after detail route)          hold  +0.003 /  0
    opt_design -post_route -hold  17:37    hold  -0.021 /  2   density 85.688%
    opt_design -post_route        17:58    setup +0.105 /  0   density 85.843%
    05_route_opt                           hold  -0.099 / 66
    06_post_fill                           hold  -0.100 / 66

**Route's setup-recovery pass cost 78 ps of hold and 64 endpoints** — the same trade as
F12, 7x smaller because the placement is frozen and detail-routed (which is the mechanism
F12 hypothesised). `ROUTE_OPT_SETUP_RECOVERY=false` is the obvious next experiment: hold
was `+0.003 / 0` entering route_opt and the whole 66-endpoint hold failure is downstream of
that one pass. Setup at 04_route was -0.400/315, though, so unlike CTS there IS real setup
work to do here — this is a trade, not a free win, and it has not been measured.

### Utilisation against the wall

    preCTS   79.105%      (rc1 75.384%)
    cts      85.282%      (rc1 77.516%)  <- includes the hold repair that rc1 never kept
    routed   85.843%      (rc1 77.784%)

The projection was 88.9-90.8% against a ~92.2% wall. **Measured 85.8%**, about 6.4 points
of headroom. Utilisation was never the constraint in this run, and the +6.2 points the CTS
hold repair costs are affordable — which is the one thing `pre_cts.tcl` said it could not
know in advance.

---

## rc5 SCORECARD

| question | answer |
|---|---|
| **1. Does CTS finally schedule useful skew?** | **No — 0 of 58,611 sinks, twice, deterministically.** But the pass RAN for the first time (rc1 never invoked it), so this is a real negative about the design rather than an unmeasured configuration. The metric the hypothesis was built on could not have distinguished the two cases. |
| **2. Does the CTS hold target work?** | **Yes, completely: -0.703/8893 → +0.003 with ZERO failing endpoints in every group, against four hold views, for +6.2 density points.** It was then deleted by rc5's own post-CTS setup-recovery pass; disabling that one knob keeps it. |
| **3. Does route close with no manual ECO?** | **No, but it completes.** Routing, DRC and connectivity are clean — better than rc1 on all three. It hard-fails a 5-item signoff budget: 380 PG vias, the standing 51 opens / 727 dangling, hold 66 FEP, max_transition 195 FEP. No manual ECO was applied and none was needed to reach the gate. |
| **utilisation** | 85.8% routed vs a ~92.2% wall. Not the constraint. |
| **flow end to end** | **RTL → GDS, 341 MB stream, no manual intervention in any stage.** Two blocking defects fixed on the way (F7, F8), one experiment corrected (F12), no guard bypassed. |
