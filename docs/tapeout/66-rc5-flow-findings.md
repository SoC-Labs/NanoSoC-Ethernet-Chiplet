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

---

# STAGE-BY-STAGE TIMING VISIBILITY (F15-F18, 2026-08-31)

F1-F14 above answer *what happened*. F15-F18 answer *why nobody could see it
happening*, and close the hole. The subject is the same event: rc5 attempt 6's
post-CTS setup-recovery pass, which took hold from `+0.003 / 0 failing` to
`-0.700 / 8,718 failing` to buy 16 ps of setup, and did it without a single
line anywhere in the run saying a metric had regressed.

Every number below was re-derived from `ASIC/eth-chiplet/build/rc5vt-20260829`
by `scripts/ci/stage_timeline.py`, not copied from F12/F14. Where it disagrees
with them, the disagreement is stated.

## F15 — the 703 ps could not have been seen, and there are four structural reasons

The flow does produce a per-pass progression view. It is `report_qor`'s
snapshot table, written to `reports/qor_<stage>.rep`. Here it is, whole, for
rc5 attempt 7:

    snapshot                     setup WNS  sFEP   util%   insts    hold
    place_design                 -          -      77.79   190322   NO SUCH COLUMN
    opt_design_prects            0.002      0      79.11   204949   NO SUCH COLUMN
    ccopt_design                 0.076      0      80.67   209104   NO SUCH COLUMN
    opt_design_postcts           0.050      0      80.56   208654   NO SUCH COLUMN
    opt_design_postcts_hold      0.066      0      85.28   240065   NO SUCH COLUMN
    opt_design_postroute_hold    0.083      0      85.69   242845   NO SUCH COLUMN
    opt_design_postroute         0.105      0      85.84   243005   NO SUCH COLUMN

**1. It has no hold column.** Not a blank one — the column does not exist. Read
this table on its own and rc5 is a run whose setup WNS climbs monotonically
from +0.002 to +0.105 with zero failing endpoints throughout. Every hold number
in this document came from somewhere else. A pass that destroys hold to buy
setup appears in the flow's only progression view as an **improvement**.

**2. It keys rows by snapshot NAME, so a repeated pass adds nothing.** Attempt 6
ran a second `opt_design -post_cts` — the recovery pass. Its
`reports/qor_03_cts_opt.rep` ends at `opt_design_postcts_hold` — the same seven
snapshot rows with the same numbers that attempt 7 produced WITHOUT that pass
(only the wall-clock column differs). The row named
`opt_design_postcts` still holds the FIRST pass's +0.050. The pass that did the
damage is absent from the table that exists to show passes.

**3. `opt_design`'s own summary prints one mode, never both.** A `-hold` run
emits a Hold mode table and no setup; a plain run emits a Setup mode table and
no hold. Verified on all four of rc5's:
`..._preCTS.summary.gz`, `..._cts.summary.gz`, `..._routed_hold.summary.gz`,
`..._routed.summary.gz`. **A trade is invisible in either half by construction.**

**4. The unsuffixed `<prefix>.summary.gz` is last-writer-wins across DIFFERENT
COMMANDS.** `reports/nanosoc_eth_chiplet_pads_cts.summary.gz` contains, per its
own `#  Command:` line:

    attempt 7   opt_design -post_cts -hold      Density 85.282%
    attempt 6   opt_design -post_cts            Density 80.575%

Same filename, two different commands. F14 reads this as "the hold-repair cells
survive into the written database — cts.summary.gz density is 85.282% in
attempt 7 where it was 80.575% in attempt 6". The conclusion is right and the
reasoning is not: those are not the same measurement taken twice, they are two
different measurements sharing a name. `stage_timeline.py` files every opt
summary by the `Command:` line inside it and never by its name.

**And the evidence for the CTS hold pass does not survive the run.**
`4_route.tcl:985` runs `foreach __f [glob $REPORT_DIR/*_hold.summary*] { file
delete -force $__f }` before route's own hold pass, to stop
`pnr_opt_hold_summary` picking up a stale CTS summary. Correct intent; the
consequence is that `..._cts_hold.summary.gz` — the artefact proving hold closed
completely at CTS — **is gone from `reports/`**, and the only surviving copy is
the one `pnr_opt_hold_summary` made at 16:51 into `reports/hold_opt_03_cts_opt.rep`.
That project-side copy is load-bearing evidence. Do not remove it.

## F16 — the progression, every state, for rc5 as it stands

`scripts/ci/stage_timeline.py <run_dir>`. Fifteen states, ordered by each
report's own `Generated on:` clock — not by filename, not by mtime.

    state                        clock   setupWNS    setupTNS  sFEP |   holdWNS     holdTNS  hFEP | tranF capF |  insts    area  util% views
    00_pre_place                 13:29   -108.840 -1304257.875 25874 |    -0.757    -127.183  1124 |  6492   70 |       -       -      -   2/4
    01_place                     13:43   -156.086 -1894151.750 36259 |    -0.622     -36.817   526 | 78582 2089 |  190322 1579446  77.79  >=5
    01b_place_opt                14:07      0.002       0.000     0 |    -0.668     -39.160   710 |    96    0 |  204949 1593298  79.11   2/4
    02_cts                       16:21      0.076       0.000     0 |    -0.701   -1172.853  9122 |   108    0 |  209104 1609875  80.67  >=4
    cts_after_ccopt              16:23      0.076       0.000     0 |    -0.701   -1172.853  9122 |   108    0 |~ 209104 1609875  80.67  >=4  = prev
    cts_after_post_cts           16:39      0.050       0.000     0 |    -0.703   -1177.098  8893 |   108    0 |  208654 1608695  80.56  >=4
    cts_after_post_cts_hold      16:49      0.066       0.000     0 |     0.003       0.000     0 |   453    2 |  240065 1658540  85.28  >=4
    03_cts_opt                   16:50      0.066       0.000     0 |     0.003       0.000     0 |   453    2 |~ 240065 1658540  85.28   2/4  = prev
    route_post_cts_as_read       16:56      0.066       0.000     0 |     0.003       0.000     0 |   453    2 |~ 240065 1658540  85.28  >=5  = prev
    04_route                     17:13     -0.400     -53.022   315 |     0.003       0.000     0 |  3444    6 |~ 240065 1658540  85.28  >=5
    route_after_post_route_hold  17:37          -           -     - |         -           -     - |     -    - |  242845 1662823  85.69    -   << NOT MEASURED
    route_after_post_route       17:58          -           -     - |         -           -     - |     -    - |  243005 1664460  85.84    -   << NOT MEASURED
    05_route_opt                 17:58      0.105       0.000     0 |    -0.099      -2.585    66 |   195    0 |~ 243005 1664460  85.84   2/4
    06_post_fill                 18:14      0.105       0.000     0 |    -0.100      -2.596    66 |   195    0 |~ 243005 1664460  85.84  >=4

`= prev` is identical on every tracked metric — the same database measured
twice, not a new state. `~` is a scale figure carried forward from the last
state that measured one. `S/H` in `views` is a measured active set;
`>=N` is only the count of view names the report happens to mention, and is a
floor (F17).

**Which stages make things worse, and by how much.** Worst first, by the tool's
own ranking (a clean metric going dirty outranks any amount of an already-dirty
one getting worse; TNS is excluded from the ranking because it is unbounded):

| # | transition | what got worse | what got better |
|---|---|---|---|
| 1 | `route_post_cts_as_read` → `04_route` | setup **0 → 315 failing endpoints** (BROKE CLEAN), setup WNS **-466 ps** (+0.066 → -0.400), TNS 0 → -53.022 ns, max_tran 453 → 3444, max_cap 2 → 6 | nothing |
| 2 | `04_route` → `05_route_opt` | hold **0 → 66 failing endpoints** (BROKE CLEAN), hold WNS **-102 ps** (+0.003 → -0.099), hold TNS 0 → -2.585 ns | setup +505 ps, setup 315 → 0 FEP, max_tran 3444 → 195 |
| 3 | `00_pre_place` → `01_place` | setup WNS **-47,246 ps**, setup 25,874 → 36,259 FEP, max_tran 6,492 → 78,582 | hold +135 ps, hold 1,124 → 526 FEP |
| 4 | `cts_after_post_cts` → `cts_after_post_cts_hold` | max_tran 108 → 453, max_cap **0 → 2** (BROKE CLEAN) | hold +706 ps, hold **8,893 → 0 FEP**, setup +16 ps |
| 5 | `01b_place_opt` → `02_cts` | hold 710 → 9,122 FEP, hold TNS -39 → -1,173 ns, hold WNS -33 ps | setup +74 ps |
| 6 | `01_place` → `01b_place_opt` | hold 526 → 710 FEP, hold WNS -46 ps | setup +156,088 ps, setup 36,259 → 0 FEP |
| 7 | `cts_after_ccopt` → `cts_after_post_cts` | setup WNS **-26 ps**, hold -2 ps, hold TNS -4.245 ns | hold 9,122 → 8,893 FEP |
| 8 | `05_route_opt` → `06_post_fill` | hold -1 ps, hold TNS -0.011 ns | nothing (metal fill's cost, and it is 1 ps) |

Row 7 is worth a second look on its own: **`opt_design -post_cts`, the setup
pass, made setup WORSE by 26 ps** (0.076 → 0.050) and hold worse too. It is not
in F12 or F14 and no file in the run remarks on it.

**And the run's superseded attempt, which is where the headline lives.**
`attempt6-cts-evidence/` is a sequence in its own right and the tool reports it
separately rather than interleaving it:

    cts_after_post_cts_hold  →  cts_after_setup_recovery      opt_design -post_cts (2nd)
      hold_fep        0 ->    8718   WORSE by 8718 endpoints   <<< BROKE CLEAN
      hold_tns_ns 0.000 -> -1056.522 WORSE by 1056.522 ns
      hold_wns_ns 0.003 ->  -0.700   WORSE by 703 ps
      setup_wns_ns 0.066 ->  0.082   better by 16 ps
      >> BAD TRADE: bought 16 ps of setup by giving up 703 ps of hold.
         43.9 ps GIVEN per ps GAINED.

**703 ps, 8,718 endpoints, 16 ps, 43.9:1 — confirmed independently of F12.**

**One correction to F14.** F14 says route "repeats F12's mistake, one seventh
the size — 78 ps of hold and 64 endpoints". That 78 ps is
`-0.021 → -0.099`, and those two numbers come from **different instruments**:
`-0.021 / 2 violating` is `opt_design`'s own SI hold summary over the
optimiser's view set, `-0.099 / 66` is `report_timing_summary` under
simultaneous mode over the active analysis views. They cannot be subtracted.
The same-instrument measurement is `04_route → 05_route_opt`: **102 ps and 66
endpoints**, and it spans BOTH route optimisation passes, because the flow
emits nothing comparable between them. So route's trade is real and it is
larger than reported — but it **cannot be attributed to the setup pass alone
from anything this run wrote**. `ROUTE_OPT_SETUP_RECOVERY=false` remains the
experiment that would settle it.

**One stale file.** `logs/pnr_qor_after_post_hold_setup_recovery.rep` sits in
attempt 7's log directory between attempt 7's 16:23 and 16:49 files. Its tool
clock is **15:31:22** and it is md5-identical to
`attempt6-cts-evidence/pnr_qor_after_post_hold_setup_recovery.rep`. Attempt 7
overwrote its three neighbours and not it, because attempt 7 never produced
that state. Nothing in the directory says so, and it is the file describing the
worst state in the run. `stage_timeline.py` catches it from the clock alone,
refuses to splice it into the chain — splicing it invents two transitions no
tool ever performed — and names the tree it belongs to by md5.

## F17 — the streamed database is analysed over a NARROWER scope than every state before it

A WNS is the worst slack over the ACTIVE analysis views and no others. Nothing
in this flow records the active set at any state except
`reports/route_report_views.txt`, which covers two reports at the very end of
route. So it was measured: a copy of each of rc5's five saved databases was
loaded read-only and asked
`get_db analysis_views .is_active/.is_setup/.is_hold`.

| saved database | active setup views | active hold views |
|---|---|---|
| `..._fplan` | 2 — `default_analysis_view_setup`, **`typical_analysis_view`** | 4 — `default_analysis_view_hold`, `av_ml_libset_hold`, `av_ltfix_libset_hold`, **`typical_analysis_view`** |
| `..._placed` | 2 | 4 |
| `..._cts` | 2 | 4 |
| `..._route_preopt` | 2 | 4 |
| **`..._routed`** | **1** | **3** |

`typical_analysis_view` is active in BOTH roles from `init_design` onward
(`nanosoc_eth_chiplet_pads.mmmc:472`) and is dropped from both at
`4_route.tcl:1564`, which re-issues `set_analysis_view` from
`ROUTE_VIEWS_SETUP`/`ROUTE_VIEWS_HOLD`. That line runs **after**
`pnr_end_reports 05_route_opt` (:1117) and after the whole `06_post_fill`
report block (:1398-1408), and **before** `pnr_write_db routed` (:1894) and
`write_stream` (:2022). Consequences:

- `06_post_fill`'s `+0.105 / -0.100 / 66` — the numbers the route manifest
  quotes and the budget gate judges — were measured over **2 setup / 4 hold**.
- the same `reports/route_manifest.txt` records `views_setup
  default_analysis_view_setup` and `views_hold default_analysis_view_hold
  av_ltfix_libset_hold av_ml_libset_hold`, i.e. **1 setup / 3 hold**.
- **the manifest declares a scope its own numbers were not measured over.**
  Neither number is wrong; the pairing is.
- `hold_06_post_fill_<view>.rep` loops over `$ROUTE_VIEWS_HOLD`, so the fourth
  active hold view has no per-view report at all.

Measured impact on this run: **none that changes the verdict.**
`..._imp_timing_early.rep`, taken at 18:18 over the narrowed set, reports hold
WNS `-0.100` worst in `av_ml_libset_hold` — the same worst path and the same
number as `06_post_fill`'s. `typical_analysis_view` was not the worst view for
either check here. That is a measurement, not a guarantee, and it will not hold
on a run where the typical corner bites.

**A note on the view counts in F16's table.** `>=N` is the number of view names
a report mentions in its own generated-clock inference messages. It is a
**floor**: a view that provoked no message leaves no trace. Against the probe it
undercounts by exactly one at every state where both are available —
`01b_place_opt` names four and has five active. Read `>=4` as *at least four*,
never as *four*. `2/4` and `1/3` are measured.

**A note on "utilisation".** Three numbers on this run answer to that word:

    report_qor UTIL at opt_design_prects        79.11%   835,493 / 1,056,181
    report_place_density on the saved _placed    79.4%   838,801 / 1,056,181
    report_place_density on the saved _routed   100.0% 1,056,181 / 1,056,181

The third is 100% because fillers occupy every remaining site — post-fill
"utilisation" is a different quantity wearing the same name. And
`report_place_density` **changes its own numerator between states**: at
`_fplan` it prints `(stdcell_area + block_area) / alloc_area` = 1.561, at every
later state `stdcell_area / alloc_area`. The denominator, 1,056,181 um², is the
allocated row area and is not the core bbox (1,892,100 um²). Every utilisation
figure this tooling prints is quoted with its formula for that reason.

## F18 — what is emitted now, and what it would have shown before the 703 ps was buried

**`scripts/ci/stage_timeline.py`** — read-only, no tool launch, nothing written
into `reports/`. It imports `run_index.py`'s `parse_timing_summary` and
`parse_qor_snapshots` rather than reimplementing them, and reproduces
`gdsrun-20260826-rc1`'s eight per-stage setup WNS values exactly
(`--expect '04_route:setup_wns_ns=-0.273'` etc., rc 0). Run over 85 build
directories across both checkouts: no crash, no non-zero exit.

    scripts/ci/stage_timeline.py ASIC/eth-chiplet/build/rc5vt-20260829
    scripts/ci/stage_timeline.py <run> --json /tmp/timeline.json --quiet
    scripts/ci/stage_timeline.py <run> --expect 'cts_after_post_cts_hold:hold_fep=0'
    scripts/ci/stage_timeline.py --check-hooks

Design rules it follows, each because something here has already gone wrong the
other way:

- **Instruments are never mixed.** Three tools measure "hold WNS" in one run:
  `report_timing_summary` under simultaneous mode, `opt_design`'s own summary,
  and `report_qor` (which cannot). A delta is computed only between two values
  on the same channel; a cross-channel pair is printed as `NOT COMPARABLE` with
  both numbers, never subtracted. This is what caught the F14 arithmetic.
- **A delta that spans an unmeasured state says so.** `04_route → 05_route_opt`
  is annotated *"this delta SPANS 2 state(s) the flow did not measure:
  route_after_post_route_hold, route_after_post_route — so it cannot be
  attributed to one pass."*
- **A state the flow ran and did not measure still gets a row**, with `-` in the
  timing columns and `<< NOT MEASURED`. A gap you can see beats a paragraph
  saying there is one.
- **Ordering is by the tool's own clock.** Filenames lie (F15.4) and mtimes lie
  (`..._cts.summary.gz`'s mtime is 68 s after its own stamp).
- **Every scope is stated**: parasitics mode, view-set change and instrument
  change are flagged on the transition, not left for the reader to infer.

**Emission at the states the flow does not report.** `hooks/post_place.tcl`
(new) and `hooks/post_route.tcl` (extended) each write
`reports/stage_state_<id>.{txt,json}` carrying the timing triples on the
comparable channel via `pnr_qor_line`, the **active view set from the tool**,
an instance census, and `report_place_density`'s own line quoted verbatim:

- `01c_place_as_saved` — the database `pnr_write_db placed` writes. The last
  thing to measure the place stage ran **before** `add_tieoffs`
  (`steps/postplace.tcl` calls `pnr_end_reports 01b_place_opt` and then adds
  tie cells), so nothing describes what CTS actually receives.
- `07_streamed` — the database `write_stream` was called on, i.e. after
  `4_route.tcl:1564` narrowed the view set. This is the state F17 says has no
  measurement at all.

Both are wrapped in `try_step` (an error in a hook aborts the stage), both
assert on the artefact afterwards because Innovus exits 0 after fatal errors,
and neither adds an instance — the toolkit's `pnr_assert_no_geometry_added`
guard either side of `post_route` still passes. Cost is one timing update each;
`POST_PLACE_STATE_TIMING=0` / `POST_ROUTE_STATE_TIMING=0` skip it.

The emitter is **duplicated byte-for-byte** in the two hooks. A pinned hook
lives in `<run>/pinned/eth-chiplet/hooks/` and has no path to a library in
`scripts/`; a `source` would resolve in the working checkout and fail silently
in every pinned run, which is *flows read the worktree* for the sixth time.
`stage_timeline.py --check-hooks` diffs the two copies and exits 1 if they
drift — proven against a one-line edit and against a removed marker.

### What a reader would have seen, at 15:32 on 30 August

The recovery pass finished at 15:31:22. The QOR line the flow already printed
was:

    CTS: QOR after post-hold setup recovery | setup wns 0.082 ... | hold wns -0.700 ... fep 8718

— correct, complete, and one line in a 232 MB log with no verdict on it. The
next thing written was `cts_manifest.txt` saying `setup_wns_tns_fep 0.082`, and
`qor_03_cts_opt.rep`, which had no row for the pass at all. What the
progression report puts at the top of the page instead:

    WHAT GOT WORSE, WORST FIRST  (3 of 5 transitions regressed something)

     1. cts_after_post_cts_hold -> cts_after_setup_recovery   [cts]
        opt_design -post_cts  (2nd, recovery)
          hold_fep         0 ->  8718   WORSE by 8718 endpoints  <<< BROKE CLEAN
          hold_tns_ns  0.000 -> -1056.522  WORSE by 1056.522 ns
          hold_wns_ns  0.003 -> -0.700   WORSE by 703 ps
          setup_wns_ns 0.066 ->  0.082   better by 16 ps
          >> BAD TRADE: bought 16 ps of setup by giving up 703 ps of hold.
             43.9 ps GIVEN per ps GAINED.

Three things make that unmissable and none of them existed before: the pass has
a **state of its own** (`report_qor` gave it no row); setup and hold are on the
**same line from the same timing update**; and `BROKE CLEAN` fires on the
transition from zero failing endpoints to any, which is the one event in a P&R
flow that is never acceptable and never noise.

### Requested from the owners of files this work does not touch

1. **`hooks/pre_cts.tcl` / `hooks/post_cts.tcl`** — the CTS stage is four
   optimisation states and the two that matter most are the least reported.
   `pnr_qor_line` is already called around them; adding the same
   `stage_state_emit` record (active views + census, ~10 lines) would make
   `cts_after_post_cts_hold` and any recovery pass first-class states rather
   than log lines. The emitter block is in `hooks/post_place.tcl`, copyable.
2. **`design.mk` / `asic-toolkit`** — a hook-visible library directory pinned
   alongside `pinned/eth-chiplet/hooks/`, so the emitter can live in one place.
   Until then `--check-hooks` is the only thing holding the copies together.
3. **`asic-toolkit`** — `4_route.tcl` should emit a `pnr_qor_line` between the
   two `opt_design -post_route` passes (:1057-1068). Two lines. Without them
   route's hold regression can only ever be attributed to the pair, which is
   what F16 had to say about it.
4. **`asic-toolkit`** — `route_manifest.txt` records `views_setup`/`views_hold`
   from the knobs while its timing triples come from `06_post_fill`, measured
   before the narrowing. Either move the manifest's timing read after
   :1564, or record the view set that was actually active when the numbers were
   taken. Do not silently change the numbers; the pairing is the defect.

### Where the evidence lives, and how to redo it

`ASIC/eth-chiplet/build/rc5vt-20260829/index/` holds `views_<db>.txt` for all
five saved databases plus a `README.txt` with the exact method.
**`build/` is gitignored**, so those files are host-only — the numbers are
copied into F17 above for that reason. To regenerate: copy the databases out of
`work/` (copies, never the run's own), then one `innovus -stylus -no_gui` per
database — `read_db` **refuses a second call in the same session**
(IMPIMEX-7031) and **exits 0 after refusing**, so a loop inside one session
silently measures nothing. The probe asserted on the artefact and caught
exactly that on its first attempt.

---

# LOGIC EQUIVALENCE — rc5, and the two links either side of it

Everything below was measured on 2026-08-31 with Conformal LEC 22.10-s200 on this host,
against `ASIC/eth-chiplet/build/rc5vt-20260829/outputs/`. Every comparison ran in its own
scratch run tag (`build/rc5lec-*`), reading rc5's netlists and writing nothing into rc5's
own tree — so the evidence directories below are NOT where `ci/signoff.yaml`'s `lec-pnr`
row looks. Re-running the leg with `RUN_TAG=rc5vt-20260829 SYN_RUN_TAG=rc5vt-20260829`
puts it there; that is one command and it is the only thing between this evidence and a
green pipeline row.

## F19 — rc5's post-P&R netlist is verified equivalent, and BOTH verdicts say so

Two legs of the three-link chain ran to completion on rc5. Both pass, and both pass twice:
once by Conformal's own `Compare Results:` line and once by the harness's independently
computed `LEC-VERDICT: RESULT=`, which applies four rules Conformal's line does not have.

| leg | golden | revised | Conformal | harness | compare points | elapsed |
|---|---|---|---|---|---|---|
| `gate` | `_gate.v` | `_gate_power.v` | PASS | RESULT=PASS | 61,599 / 61,599 equivalent | 271 s, 852 MB |
| `pnr`  | `_gate_power.v` | `_pnr.v` | PASS | RESULT=PASS | 61,599 / 61,599 equivalent | 448 s, 924 MB |
| `syn`  | RTL, via Genus's dofile | `_gate.v` | see F22 | see F22 | see F22 | still running at time of writing |

`pnr` is the one that matters, and a whole-tree `grep -l 'LEC-VERDICT: tag=pnr'` over
every archived `verdict.txt` in the frozen checkout returns **five** — full-20260814,
fp1505, gdsrun-20260823-rzG, and rc1 under two run tags. That is the entire history of
this comparison before tonight. Its full census here, from `report_statistics` rather
than from the summary line:

    Primary inputs            56 / 56 mapped
    Tri-state (Z) key points  24 / 24 mapped
    Primary outputs           34 / 34 mapped, 34 equivalent
    Black-box key points      55 / 55 mapped, 55 equivalent
    State key points       61,513 / 61,510 mapped, 61,510 equivalent
                                    3 unmapped (unreachable), symmetric by name

    non-equivalent 0   inverted-equivalent 0   abort 0   not-compared 0
    not-mapped 0 golden / 0 revised   extra 0 golden / 0 revised
    tool exit code 0, no flags set

**The state-point count is independently corroborated.** A Liberty-classified census of
the netlist itself (F20) finds 58,505 flops + 3,007 integrated clock gates + 1 latch =
61,513 sequential cells, which is exactly what Conformal calls its state key points. The
two numbers come from different files by different methods and they agree, so neither is
reading a design the other is not.

### The comparison covers the PG netlist too, and that is now checked rather than assumed

The `pnr` leg reads `_pnr.v`. What LVS reads is `_pnr_pg.v`, written by a second
`write_netlist -include_pg` from the same database one second later, and nothing had ever
compared the two. Their flattened instance sets are **identical — 243,169 each, zero added,
zero deleted, zero substituted**, so the equivalence proved on `_pnr.v` transfers to the PG
netlist by construction rather than by assertion. (`_pnr_pg.v` also emits an empty module
declaration for every library cell it uses, ahead of the design; a flattener that treats
"is a defined module" as "is hierarchy" descends into all 3,400 of them and reports the
netlist as EMPTY. `scripts/ci/lec_cellswap.py` treats a module with no instances in it as a
leaf, which is what makes this comparison possible at all.)

`make lec-selftest` was run first on this host, as the toolkit's note asks: **all 10 cases
behaved as declared** — the equivalent pair passes, the one-gate mutation fails, the extra
flop fails, the missing and zero-length netlists fail, the dofile's own preflight fires,
the PG-decoration shape passes, the non-supply extra PI fails, the one-sided unreachable
point fails. Evidence in `build/rc5lec-self/reports/lec/selftest_*/`.

## F20 — WHAT THE TOOLS CHANGED: +48,299 cells, and every one of them combinational

"Equivalent" is a true sentence about rc5 and it is not the whole answer. Place, CTS,
post-route optimisation and hold repair rewrote 30% of the instance list. Classified from
the same ten Liberty files the comparison read (`scripts/ci/lec_cellswap.py`, new, below):

| class | `_gate_power.v` | `_pnr.v` | delta |
|---|---|---|---|
| FLOP | 58,505 | 58,505 | **0** |
| ICG (integrated clock gate) | 3,007 | 3,007 | **0** |
| LATCH | 1 | 1 | **0** |
| COMB | 133,357 | 181,574 | +48,217 |
| physical-only (bond pads) | 0 | 82 | +82 |
| **total leaf instances** | **194,870** | **243,169** | **+48,299** |

    7,859 instances deleted        56,158 added        21,579 substituted in place

**Nothing sequential was added, deleted, or moved between cell families.** Not one flop,
not one clock gate, not the single latch. That is the dangerous case and it did not happen.

### The clock gating — the most consequential swap, and it is large

**2,724 of rc5's 3,007 clock gates were substituted — 90.6% of them.** Every clock gate
Genus emitted is at MINIMUM DRIVE; place-and-route spreads them across seven drive points:

    838  CKLNQD1 -> CKLNQD6          194  CKLNQD1 -> CKLNQD3
    707  CKLNQD1 -> CKLNQD2          118  CKLNQD1 -> CKLNQD4
    431  CKLNQD1 -> CKLNQD16          33  CKLNQD1 -> CKLNQD12
    394  CKLNQD1 -> CKLNQD8            9  CKLHQD1 -> CKLHQD{2,3,6}

Read the direction: **synthesis emits 2,996 CKLNQD1 and 11 CKLHQD1 and nothing else**;
the routed netlist has 281 and 2 left at minimum drive. 431 gates went straight to D16.
Every substitution stays inside its family — `CKLNQD*`→`CKLNQD*`, `CKLHQD*`→`CKLHQD*` —
so no clock gate became a buffer and none changed its latch polarity. That is the
distinction that matters and it is why the census tests the FAMILY and not just the count:
mutant C below is exactly the case where it does not hold.

### The rest of the swaps

    17,132 of the 21,579 in-place substitutions change drive strength only
     4,447 change cell family, and NONE of them touches a sequential cell
           (largest: NR2XD1->NR2D1 663, AN2D2->AN2XD1 446, CKAN2D4->AN2D2 175)

     2,467 flops resized, family always preserved: DFCNQD2->DFCNQD1 682,
           DFCND2->DFCND1 293, SDFCNQD1->SDFCNQD0 251, DFCNQD4->DFCNQD2 186,
           DFCNQD1->DFCNQD4 172 -- P&R downsizes far more flops than it upsizes

### What was inserted, and what vanished

| | added | deleted | net |
|---|---|---|---|
| clock buffers (`CKB*`) | 33,378 | 319 | **+33,059** |
| clock inverters (`CKN*`) | 7,690 | 2,604 | +5,086 |
| data buffers (`BUFF*`) | 7,501 | 2,068 | +5,433 |
| inverters (`INV*`) | 3,564 | 1,833 | +1,731 |
| tie cells | 3,063 (3,038 `TIEL`, 25 `TIEH`) | 0 | +3,063 |
| delay cells | 94 (`DEL0` 33, `DEL02` 32, `DEL01` 12, `DEL005` 12, `DEL015` 5) | 0 | +94 |
| bond pads | 82 (`PAD70GU_SL` 42, `PAD70NU_SL` 40) | 0 | +82 |
| other combinational | 779 | 1,031 | −252 |

33,059 net clock buffers is the single largest thing that happened to this netlist, and it
is two things not one: CTS building a clock tree that synthesis had only 319 clock buffers
of, and hold repair. The two separate cleanly by drive strength — **18,324 of the additions
are `CKBD0`, the weakest clock buffer in the library**, which is not a tree driver but the
delay element Innovus reaches for on a data path that needs padding. For scale, the same
census on `gdsrun-20260823-rzG` — the rc4-lineage build — adds **+14,021** cells in total
and only **4,456** `CKBD0`. rc5 inserts three and a half times as much cell area in P&R as
the shipping lineage, and four times as many minimum-drive delay buffers, which is what
F12's CTS hold target looks like from the netlist side.

## F21 — the two links do not compare the same population, and the verdict cannot say so

The `pnr` leg compares **61,599** points, of which 3,008 are latch key points — the 3,007
clock gates and the one real latch.

The `syn` leg's FIRST comparison — Genus's own `fv_map` model against `_gate.v` — compares
**58,592**, and reports **3,010 unreachable state key points** instead of 3. Same design,
same libraries, one link apart. The 3,007-point difference is the entire clock-gating
population: Conformal's gated-clock remodelling (`Remodeled 50648 gated-clock DFF/DLAT(s)`)
folds each enable into the data cone of every flop the gate feeds, after which the ICG's
own latch provably cannot influence a compared output and is unmapped as unreachable.

**That is sound, and it is invisible.** The enable is still verified, inside 50,648 flops'
D-cones. But `LEC-VERDICT: unreachable_revised=3010` is the only trace of it, and nothing
anywhere says those 3,010 are the clock gating. A reader handed two green LEC runs has no
way to tell that one made the clock gates key points and one did not — and a chain
argument (`RTL ≡ gate`, `gate ≡ gate_power`, `gate_power ≡ pnr`, therefore `RTL ≡ pnr`) is
only as strong as its weakest link's population.

`scripts/ci/lec_cellswap.py --unreachable-report` now resolves every unmapped point back
to the cell it belongs to, so the difference is one line instead of an inference:

    rc5 pnr leg      1 (G) DFF FLOP:DFNCND1   2 (G) DFF FLOP:DFNSND1  (and the same 3 in R)
    a mutated pair   the same 3, PLUS 3,007 DLAT rows on ICG:CKLNQD*/CKLHQD*

### The three points that ARE unreachable in the clean run, named

    /u_..._u_tidelink/u_link_clk_div/byp_en_meta_r_reg/U$1
    /u_..._u_tidelink/u_link_clk_div/div_en_r_reg/U$1
    /u_..._u_tidelink/u_link_clk_div/byp_en_r_reg/U$1

All three are in the **link-clock divider**, symmetric on both sides, and "unreachable"
here means every path from them to every compared output is blocked. This is Conformal
independently confirming, from the netlist alone, what the divider's own note has claimed
since it was built: **the D2D rate knob exists and nothing observable depends on it.**
Three registers that cannot change any output are three registers the design does not use.

### Population is stable on an equivalent pair — measured, with a control

The 58,592-point shape also appeared in the two mutant runs (F24), which raised the
question of whether the population is content-dependent, mode-dependent or just noisy. A
control settles it: the SAME invocation mode (`lec-pair`), a byte-identical copy of
`_pnr.v` at a different path, run under the same machine load, gives **61,599 points, 3
unreachable, zero `Unmap unreachable keypoints` rows** — identical to the `pnr` leg. So on
an equivalent pair the full population is compared, and rc5's green result did verify all
61,599 points. The reduction is something Conformal does once the netlists differ; the
mechanism is not established here and is not needed for the conclusion.

## F22 — the "96 unmapped flops" story: the record says three reasons, not one

The claim in circulation is that a previous RTL→gate LEC "FAILED" only because of the
harness's unmapped-extras rule, while Conformal itself said PASS with zero non-equivalent
points. **Read the artefact, and that is not supportable.**
`build/gdsrun-20260821-slpads/reports/lec/syn/verdict.txt` records:

    compare_points=5433 equivalent=5433 nonequivalent=0 abort=0 notcompared=0
    unmapped_extra_golden=96
    unreachable_golden=446 unreachable_revised=319   unreachable_symmetric=-1
    tool_exit_code=40 flags=unmapped-or-extra-PO,abort-any-compare
    reason=96 extra unmapped point(s) that are not declared supply ports: ...
    reason=unreachable key points are not symmetric: 446 only in golden, 319 only in revised
    reason=tool abort/uncompared flag set (exit code 40)
    RESULT=FAIL

Three findings, and the third is **Conformal's own status word**: 40 = 0x28 = the
unmapped-or-extra-PO bit plus the abort/uncompared bit. The harness did not invent that
bit; it decoded it. "Conformal said PASS" is true only of the `Compare Results:` line,
which by design does not fail on unmapped points, on extra points, or on inverted-
equivalent points — which is the entire reason the harness computes a second verdict.

**And 5,433 is not the design.** The syn leg's counters come from the FINAL compare state
of Genus's composite dofile — `flow/verify/lec_syn_rewrite.tcl` says so in as many words —
and that dofile's second comparison is not a flat `compare` at all but
`run_hier_compare ... -dynamic_hierarchy`, dozens of sub-compares over a generated
sub-dofile. Whatever `get_compare_points` returns after that, it is not an aggregate over
a design with 61,513 sequential cells; 5,433 is under 9% of them. The same dofile's FIRST
comparison (`fv_map` → `_gate.v`) is flat and reports 58,592 points and PASS — measured on
rc5 tonight. `ci/signoff.yaml`'s `lec` row already documents the two-comparison structure
at length and requires at least two `Compare Results:` lines for exactly this reason;
nothing here changes it, and the population caveat in F21 applies to compare #1 as well.

### What the 96 flops actually are, and whether they matter

All 96 are `root_port_cursor_r_reg[0..31][0..2]` in
`u_tidechart/u_tidechart_controller/u_enum`, and **rc5 still deletes them**: `grep -c
root_port_cursor_r_reg` returns 0 in rc5's `_gate.v` and 0 in its `_pnr.v`, against 7
references in the live RTL. So the syn leg on rc5 should reproduce the same 96 when it
finishes.

The safety question is already settled elsewhere and is not reopened here: the removal is
safe at `NUM_PORTS=1`, which is what this chiplet ships, and is a real defect for anyone
instantiating the IP with more — proven by simulation with a `NUM_PORTS=2` control on
2026-08-24. The LEC-side correction is only this: **the FAIL had three causes and not one,
and one of the three is Conformal's own exit status.** Writing the whole verdict off as a
harness artefact would have discarded the asymmetric-unreachable finding (446 vs 319) with
it. Which of the three survive scrutiny is the next section, and the answer is two of them.

### Which of the three is a harness over-read — read the archived transcript, not the verdict

`build/gdsrun-20260821-slpads/logs/lec_syn.log` is 2.1 MB and settles the rest. That leg
**ran to completion**, and Conformal's verdict for the hierarchical RTL→`fv_map`
comparison is at line 15756:

    6. Compare Results:                       PASS
       Total Equivalent modules  = 49
    2. Incomplete verification:               0
       All primary outputs are mapped:        yes
       Not-mapped DFF/DLAT is detected:       no
       All compared points are compared:      yes

49 module pairs, 49 equivalent, zero non-equivalent, zero aborted. So the three reasons
sort into two kinds, and the distinction is the whole point of running two verdicts:

**Real, and exactly what the harness exists to surface.** `Total Equivalent modules = 49`
counts module pairs whose COMPARE POINTS were equivalent. It says nothing about unmapped
points — the `Processed N of 49 … EQ / NEQ / ABORT` tally has no column for them — so a
pair with 96 golden flops that have no counterpart at all is still counted equivalent, and
Conformal's own line would never have said otherwise. The 96, and the 446/319 unreachable
asymmetry, are findings that exist ONLY because a second verdict looked for them.

**An over-read.** The abort bit in exit code 40 is not. Two of the 49 sub-compares DID
abort — 1,382 points (1,377 DFF + 5 BBOX) on the SoC module and 1,214 on another — and
Conformal's own `analyze abort -compare` then RESOLVED every one of them: the follow-up
table on the same module reads 10,914 equivalent, zero abort, and the running tally never
leaves `ABORT: 0`. The exit-code bit is sticky across the session, so it records "an abort
happened at some point", which on a hierarchical leg is a normal step in the proof and not
a verdict. **`lec_rules.tcl`'s exit-code decode is sound for a flat compare and produces a
false FAIL on a hierarchical one.** That rule is engine-owned and was not touched here; it
is written down so the next reader does not re-derive it from the residual state.

That abort pass is also where the leg's runtime goes. Measured on slpads, compare #2 cost
4,868 s elapsed / 6,890 s CPU, and the single aborting SoC sub-compare accounts for 3,063 s
of it before `analyze abort` even starts. rc5's run reproduces the shape exactly: at the
time of writing it is at module pair 21 of 44, that pair reported 1,380 abort points
(1,375 DFF + 5 BBOX) after 3,568 s, and it is inside `analyze abort -compare`.

## F23 — rc4, the netlist that went to the foundry, now has equivalence evidence

`build/rc2-20260827`, `build/setupclose-20260829` (which holds
`nanosoc_eth_chiplet_pads_rc3setup_pnr.v`) and `build/rc4-20260829` each hold a post-P&R
netlist and **none of them has a `reports/lec/` directory of any kind**. The most recent
post-P&R proof in the tree before tonight was `gdsrun-20260826-rc1`.

Counted rather than estimated, rc1's proven netlist to rc4's:

    201,741 -> 204,395 leaf instances
    2,655 added   1 deleted   22 substituted in place   = 2,678 instance deltas
    added: 2,253 clock buffers (2,103 of them CKBD0) + 402 data buffers, nothing else
    deleted: one BUFFD16
    no flop, no clock gate, no latch, no logic-function cell added or removed

(The figure in circulation was ~1,799; the measured number is 2,678, and rc1→rc2 alone is
312.) That shape — thousands of minimum-drive clock buffers and nothing else — is a hold
ECO chain, and it predicts equivalence. **It was then verified rather than assumed:**

    golden  gdsrun-20260826-rc1/outputs/nanosoc_eth_chiplet_pads_pnr.v
    revised rc4-20260829/outputs/nanosoc_eth_chiplet_pads_rc4_pnr.v
    RESULT=PASS  61,599 / 61,599 equivalent, 0 non-equivalent, 0 abort,
                 0 not-compared, 0 not-mapped, 3 unreachable symmetric, exit code 0
    295 s, 900 MB.  Evidence: build/rc5lecrc4/reports/lec/rc1pnr-vs-rc4pnr/

rc1's own two legs are green — `gate` (`_gate.v` → `_gate_power.v`) and `pnr`
(`_gate_power.v` → `_pnr.v`), both 61,599/61,599 — so this closes the chain by
transitivity: **the netlist inside the rc4 stream is logically the netlist synthesis
produced.** The joint is checkable rather than assumed: rc1's `pnr` verdict names
`build/lecpnr-rc1-0826/outputs/..._pnr.v` as its revised side and this run read
`build/gdsrun-20260826-rc1/outputs/..._pnr.v` as its golden, and those two files are
md5-identical (`fd6284fcda9ac0a079a3a6d30f1142ee`). That is the first equivalence statement
of any kind about the tapeout candidate, and it was three hundred seconds of machine time
away the whole time.

Both netlists were read from the frozen main checkout and nothing was written to it.

## F24 — DISCRIMINATION: three mutants, on the real 243,169-instance netlist

A gate that passes a genuinely non-equivalent netlist is worse than no gate. The toolkit's
own self-test proves the harness can fail on a handful of hand-written toy netlists — tens
of key points, one module — and that is worth having, but it says nothing about this design
at this scale. So three deliberately broken copies of
rc5's actual post-P&R netlist were compared against rc5's actual synthesis netlist. Each
attacks a different rule, and each edit is verified to be the ONLY difference from the
original by `diff` before the run.

| mutant | the edit, one instance out of 243,169 | verdict | why it failed | elapsed |
|---|---|---|---|---|
| **A** logic | `ND2D1 g9249__2802` → `NR2D1` in `eth_receivecontrol` (same pins A1/A2/ZN) | **FAIL** | 1 non-equivalent point; tool exit 16 | 576 s |
| **B** deleted register | `DFCNQD1 \LatchedTimerValue_reg[7]` removed, `assign LatchedTimerValue[7] = n_255;` in its place | **FAIL** | 1 **not-mapped** golden DFF *and* 1 non-equivalent point; tool exit 24 | 750 s |
| **C** clock gate defeated | `CKLNQD6 RC_CGIC_INST` → `CKBD6` in `cg_RC_CG_MOD_4_15762`: gated clock becomes free-running, enable ignored | **FAIL** | 23 non-equivalent points *and* an asymmetric unreachable point; tool exit 16 | 1,529 s |

Every one of them names the right place. Mutant A's single non-equivalence is
`.../u_eth_top_maccontrol1_receivecontrol1/ReceivedPauseFrm_reg` — the module that was
edited. Mutant B's not-mapped point is `LatchedTimerValue_reg[7]` itself, the register that
was deleted, and the harness's rule 7 (not-mapped, no exception anywhere) fires on it
independently of the downstream non-equivalence. Mutant C's diagnosis is the clearest of
the three, because it shows how Conformal models clock gating at all:

    (G) MUX  .../u_eth_apb_to_wb_adr_r_reg[7]/U$1      <- enable folded into a recirculation mux
    (R) BUF  .../FE_OFC4710_u_ethmac_0_apb_paddr_7/U$1 <- no enable: the flop always loads

23 flops fed by that one clock gate, all 23 caught. **A defeated clock gate is caught as a
data-path difference**, which is precisely why F20's family test on clock gates is the
right test and a count of clock gates would not be.

The control described in F21 completes the proof in the other direction: the same harness,
the same mode, an UNMUTATED copy of the netlist → PASS over the full 61,599 points. The
gate distinguishes.

Mutants and control: `build/rc5lecmut{A,B,C}/`, `build/rc5lecctl/`. The three edits are
fully specified by the table above and each was `diff`ed against the original before its
run; the generator asserted each pattern was UNIQUE in the source before substituting, so
a mutant that silently failed to apply could not be mistaken for one that did. The
generator itself was a throwaway and is not committed — reproducing a mutant is three lines
of `sed` against the quoted text, and re-deriving it is cheaper than trusting a script
nobody has read.

## F25 — the LEC rows in `ci/signoff.yaml`: what was wrong, and what changed

**1. `lec-selftest` asserted exactly 9 cases; the harness runs 10.**
`flow/verify/run_lec.sh` makes nine `_case` invocations plus a stub-coverage assertion that
increments the same tally. So on the day the last genuinely-red case went green, this stage
would have gone red anyway on an off-by-one — and its message would have said "a case was
dropped" about a harness that had gained one. Fixed to 10, the four fixtures re-cut to
match, `prove` green in both directions. An exact count is still the right rule; it is the
second time it has been the stale half of a correct rule.

**2. `lec-selftest`'s prose predicted a red `pg_decoration` case. It is green.**
Re-measured on a seat tonight: all ten cases behave. The toolkit fixed the cause (the
self-test netlists declared the supplies `inout`, and Conformal derives five key points
from a bidirectional port; `write_hdl -pg` writes them as `input`) without widening any
tolerance. The stale paragraph is kept and dated rather than deleted.

**3. Two classifications the toolkit's own comments left open are now measured**, and are
recorded in the manifest because nothing else will hold them: `extra_state` comes back as
**extra** (`unmapped_extra_revised=2`), not not-mapped; `asym_unreachable` comes back as
**unreachable on one side** (`unreachable_golden=1 / revised=0`), so its reason is "not
symmetric", not "extra unmapped point". Both cases assert an alternation pending exactly
this measurement and can now be narrowed.

**4. The `vars:` header still said `lec` stays literal.** Its exemption was withdrawn on
2026-08-29 and the stage has read `@GRADED_BUILD@` ever since. Corrected — a pin recorded
in prose that the manifest no longer has is the same defect the paragraph is about.

**5. `lec-pnr` graded Conformal and never graded the harness.** Every clause read
`logs/lec_pnr.log`; nothing read `reports/lec/pnr/verdict.txt`. The `lec` row beside it
grades both. That asymmetry matters because F22 is a worked example of the two verdicts
disagreeing: `Compare Results: PASS`, 5,433 of 5,433 equivalent, `LEC: RESULT=FAIL` on 96
golden flops with no counterpart. A stage reading only the first line calls that verified.
`lec-pnr` now requires both, requires them to AGREE (a contradiction is its own named
failure), requires the verdict to name THIS leg and THIS build's `_pnr.v`, requires the
five no-exception counters to be present and zero — "not measured" is not zero — and
**prints the compare-point population and the unreachable split on the row**, because after
F21 a green row that does not say how large a population it verified is not a measurement.
Three new must-fail fixtures pin the new clauses: `fail-verdict-absent` (a perfect log with
no verdict beside it — the shape a killed runner leaves and the shape a stale log has
always had), `fail-harness-disagrees` (the same perfect log, and a verdict reporting 96
not-mapped flops), `fail-wrong-leg` (a complete, healthy, PASSING verdict from the `gate`
leg). All six cases pass `prove`, each failing for its own reason.

**6. New stage `lec-cellswap`, and `scripts/ci/lec_cellswap.py`.** F20 is not a report
anyone will re-derive by hand, and its three dangerous cases deserve a gate. The tool
flattens both netlists, classifies every cell **from Liberty** — `clock_gating_integrated_cell`,
`ff (...)`, `latch (...)`, and the library list comes from `lec-pnr`'s own
`reports/lec/pnr/inputs.txt` so there is no second copy of it to drift — and fails on
exactly three things: a sequential key point added or deleted, a sequential cell whose
family changes rather than its drive, and a cell no library and no stub file defines.
Everything else is reported. It is 30 s, needs no Conformal seat, and works on any pair of
netlists — including the ECO-only trees that can host no RTL-to-gate comparison at all.

It is deliberately NOT a substitute for the Conformal run and the stage says so: it
compares instance names and cell types and cannot see a rewired net, which is the thing
`lec-pnr` exists to catch.

`--selftest` runs ten cases in a second with no libraries and no licence — identical,
resize-only, buffer-added and stubbed-pad-added must pass; flop-deleted, flop-added,
ICG-defeated, flop-family-swapped, unknown-cell and empty-netlist must fail — and the
stage's `check:` asserts that tally before it reads the census, because a census produced
by a tool that has stopped discriminating is not evidence. The check also **re-derives the
sequential populations from the census's own class table rather than reading its `result`
field**; `ci/fixtures/lec-cellswap/fail-result-contradicts-census` is a census whose
`result` says PASS over a table that has lost a flop. The must-pass fixture is the REAL
census of `gdsrun-20260823-rzG`, computed from that build's two netlists with that build's
own libraries, paths scrubbed — not a synthetic file shaped like one.

The stage was also executed end to end on rc5's real netlists rather than only against its
fixtures — `run:` and `check:` extracted from the manifest verbatim, `@GRADED_BUILD@`
resolved to a tree holding rc5's two netlists, `lec-pnr`'s `inputs.txt` and its
`lec_stubs.v`. Both green, and the row reads:

    lec-cellswap: 194870 -> 243169 leaf instances (56158 added, 7859 deleted,
                  21579 substituted in place)
    lec-cellswap: sequential unchanged - FLOP 58505, ICG 3007, LATCH 1
    lec-cellswap: clock gates substituted: 2724 of 3007 - CKLNQD1->CKLNQD6 x838,
                  CKLNQD1->CKLNQD2 x707, CKLNQD1->CKLNQD16 x431, ...

A fixture proves a gate can fail. Running the manifest's own two blocks against the real
thing proves the gate is WIRED UP, which no fixture can, and which this pipeline has been
caught not being at least twice.

`signoff.py lint` is clean and `signoff.py prove` is 181 cases, 0 problems, with the new
stage's 5 and `lec-pnr`'s 6 among them.

## Evidence, and the one thing left to do

    build/rc5lec-self/reports/lec/selftest_*/     harness self-test, 10/10
    build/rc5lec-gate/reports/lec/gate/           _gate.v vs _gate_power.v   PASS
    build/rc5lec-pnr/reports/lec/pnr/             _gate_power.v vs _pnr.v    PASS
    build/rc5lec-pnr/reports/lec/pnr/cellswap.*   the cell-swap census
    build/rc5lec-syn/reports/lec/syn/             RTL vs _gate.v             (running)
    build/rc5lecctl/reports/lec/control-unmutated/  the population control   PASS
    build/rc5lecmut{A,B,C}/reports/lec/mut-*/     the three mutants          FAIL x3
    build/rc5lecrc4/reports/lec/rc1pnr-vs-rc4pnr/ rc1 -> rc4                 PASS

All of it is under `build/`, which is gitignored: **this evidence is host-only and will not
survive a clone**, which is a standing problem in this repo and not one solved here.

The one command outstanding is re-running the `pnr` leg with
`RUN_TAG=rc5vt-20260829 SYN_RUN_TAG=rc5vt-20260829` so the transcript and the verdict land
where `ci/signoff.yaml`'s `lec-pnr` and `lec-cellswap` rows read them. Nothing about the
result changes; only where it is filed.

---

## F26 — logic depth was never asked for, and rc5's deepest path meets timing by 91 ps

**Nothing in this flow surfaced logic depth at synthesis.** Genus has the command; it was
never called. The consequence is the one the CTS and route findings above keep circling:
the first anyone learns of a deep combinational cone is a timing failure hours later, in a
stage whose reports are 35 MB and whose remaining fix options are placement ones.

### What existed, and exactly why it cannot answer the question

Two things in `1_synthesis.tcl` carry any depth information at all:

    :1072  report_timing -max_paths 50 -nworst 5   -> syn_timing.rep
    :1075  report_qor -levels_of_logic             -> syn_qor.rep

`syn_qor.rep` gives ONE number per cost group — "No of gates on Critical Path" — for the
worst-**slack** path only. `syn_timing.rep` gives fifty full paths, also ordered by slack.
On rc5 those fifty span **36 to 85 levels of logic and 0 to 5 ps of slack**, and *nothing
in the report says which is which*. Depth is present in the file and absent from the
report.

And the fifty do not contain the deep path. rc5's deepest endpoint is

    90 levels   r2r_clk
      u_soc/u_network_core/...cortexm0plus...core_op_q_reg[8]/CP
      -> u_tidelink/u_tidelink_fifo_u_apb_regs_released_credits_acc_reg[14]/D
      MET, slack +91 ps

It is not among the fifty, and it could not be: the whole `r2r_clk` group sits inside 5 ps,
so a slack ranking is a coin toss among thousands of endpoints and this one has 91 ps to
spare. The worst-slack path (0 ps) is **63 levels** — 27 shallower than the deepest.
*That* is the path a reader of rc5's reports would have taken away as "the deep one".

Twelve endpoints reported in full at 84-89 levels have slack from **+3 ps to +128 ps**.
Every one of them is a path that passes today and has nothing left to give at CTS.

### `report_logic_levels_histogram` — 188 s, 109,257 endpoints, never run

Genus walks every timing endpoint and reports its depth whether or not it meets timing.
`grep -rn report_logic_levels` over the whole repository before this change: **zero hits.**

rc5, all cells counted, view `default_emulate_view` (WCCOM, ss 1.08 V 125 C), 109,257
endpoints:

     levels        endpoints
      0 -  9      82282   75.3%
     10 - 19       8384    7.7%
     20 - 29       5293    4.8%
     30 - 39       1541    1.4%
     40 - 49       2256    2.1%
     50 - 59        970    0.9%
     60 - 69       1290    1.2%
     70 - 79       6938    6.4%      <- 6.4% of the design is 70+ levels deep
     80 - 89        302    0.3%
     90 - 99          1    0.0%
                                     worst 90

### DEPTH versus LOAD, at design scale, in two numbers

The same command with `-skip_buffer -skip_inverter` re-counts the same 109,257 endpoints
without the drive:

    worst depth, buffers and inverters counted     90 levels
    worst depth, buffers and inverters NOT counted 80 levels

**10 of the deepest path's 90 levels (11%) are drive; 80 are structure.** Buffering is not
what makes this design deep, and no amount of sizing will shorten it. The non-buffer
histogram also shows 6,879 endpoints in a single 60-64 band — a large, flat population of
genuinely deep cones, not a handful of outliers.

Per path the same split is exact, because `synth_libcell_class.tsv` carries Genus's own
`is_buffer`/`is_inverter` for all 882 lib cells rather than a guess at TSMC's naming (a
regex cannot separate `CKND2`, a clock inverter, from `CKND2D2`, a clock NAND2). Over the
60 paths reported in full the buffer/inverter share of levels runs **0% to 24%, median
13%**.

### Depth by cost group — where the structural margin is, whatever the slack says

    worst  median       n  cost group
       90      68   15619  r2r_clk
       87      30     292  cg_enable_group_D2D_RX_WORD_CLK_0
       84      68     437  cg_enable_group_clk
       83      26    1170  r2r_D2D_RX_WORD_CLK_0
       82      26      39  r2r_mii_rx_clk
       73      71     129  QSPI_SCLK
       62      50     830  r2r_D2D_TX_WORD_CLK_0
                            (population: endpoints at >= 20 levels, 18,591 of 109,257)

`r2r_clk`'s **median** is 68 levels over 15,619 endpoints. This is not a design with one
long path; it is a design whose typical constrained path is deep. `QSPI_SCLK` at median 71
of a worst 73 is the same shape in miniature.

### The measurement validates itself

Two independent level counts appear in the report and they are reconciled rather than
mixed:

* on the twelve deepest endpoints, where `report_timing -to` returns the same path the
  histogram ranked, **tool − counted = 1, constant** — a definitional offset and nothing
  else. Sections 1 and 2 print the tool's number; sections 3 and 4 count combinational
  cells between the launch and capture elements.
* the counted number matches Genus's own third opinion: `syn_qor.rep` says the `r2r_clk`
  critical path has **63** gates, and the counter says **63** for that path.
* on the fifty slack-ordered paths the delta spreads −1 to +9, because there
  `report_timing` returns the *slowest* path to an endpoint and the histogram reports its
  *deepest*. Two of the fifty have a counted path **deeper** than the histogram's figure
  for the same endpoint, so **that figure is the tool's per-endpoint depth and not a
  guaranteed maximum.** The report says so on the line it prints it.

### PRIOR MEASUREMENT, CHECKED: "82 of ~100 levels are outside TideLink" — CONFIRMED, with the split moved

The 2026-08-08 note recorded the worst path as CM0+ `core_op_q_reg[3]` → TideLink
`released_credits_acc_reg[14]`, ~100 levels, of which ~18 were TideLink's.

rc5's deepest path is **the same two registers** — `core_op_q_reg[8]` →
`released_credits_acc_reg[14]` — at 89 counted levels, and it splits:

    60 levels  u_soc          (48 of them u_soc/u_network_core, the second CM0+)
    27 levels  u_tidelink     (16 in tidelink proper, 11 in u_tidelink_fifo)
     2 levels  (top)
    ----------------------------------------------------------------
    62 of 89 (70%) outside TideLink

Across all 60 paths reported in full, **3,380 of 3,921 levels (86.2%) are outside
TideLink**; TideLink owns 541 (13.8%).

**So the claim holds in substance and has drifted in detail.** The great majority of the
depth is still CPU and fabric, still not TideLink's to fix, and still not retimeable (it is
Arm IP). But TideLink's share of the *deepest single path* has gone from ~18% to 30%, and
the accumulator end of it is now 27 levels rather than ~18. Anyone quoting "82 of 100"
should quote the scope with it: it is 86% across the worst 60 paths and 70% on the single
deepest one.

### The load story is four nets

38 of the 60 paths trip a load or fanout threshold, and they largely trip the *same* one.
Four drivers are the heaviest-load stage on 27 of them:

     9 paths  u_soc/u_network_core/...cortexm0plus...core_mul_4962_43_g6205/ZN  CKND8   131.5 fF
     7 paths  u_soc/g87431/ZN                                                  INVD12  107.2 fF
     7 paths  u_soc/g129776/ZN                                                 CKND16  182.9 fF  fanout 55
     4 paths  u_soc/g293/ZN                                                    CKND12   65.1 fF

That is a small, concrete, flow-side list — and it is exactly the part of the problem that
placement CAN fix, which is why separating it from depth is worth the column.

### What is written now

`hooks/post_synth.tcl` sections 2a and 2b, and `scripts/ci/synth_depth_report.py`:

    synth_logic_levels.rep         every endpoint, every level
    synth_logic_levels_nobuf.rep   every endpoint, drive not counted
    synth_logic_levels_detail.rep  one row per endpoint: start, end, depth, cost group
    synth_deep_paths.rep           report_timing -to, the N deepest endpoints in full
    synth_libcell_class.tsv        882 lib cells: buffer/inverter/macro/sequential/pad/area
    synth_depth.rep                the report to read at 2am -- five sections, worst first
    synth_depth.json               the same numbers, for a gate or a diff

`synth_depth.rep`'s five sections are: the design-wide distribution with and without
drive; the deepest endpoints whether or not they meet timing; the worst paths by slack
each carrying its depth; per-path anatomy with a DEPTH / LOAD / DEPTH+LOAD verdict and the
numbers that produced it; and a hierarchy rollup at two depths. Every table states its
population, its analysis view, and whether buffers were counted. Synthesis clock-gate
wrappers (`cg_RC_CG_HIER_INST*`) are folded into their parent, and ungrouped hierarchy
(`u_a_u_b_u_c`) is split back apart — without that the rollup is one bucket wide and the
"whose cone is this" question cannot be answered at all.

**Cost, measured on rc5:** histograms 188 s, twelve deepest-endpoint path reports 4 s,
libcell table under 1 s. About 3.5 minutes on a 100-minute synthesis. `SYNTH_DEPTH_REPORTS=0`
turns it off and says in the log that the record now has a hole.

`scripts/ci/synth_depth_report.py --selftest` proves the classifier can reach all four
verdicts, that the level counter excludes the launch and capture elements, that the
hierarchy splitter dissolves both `_u_` and `_cg_RC_CG_` joins, that segmentation preserves
order and re-entry, that the class table overrides the name guess, and that a report over
zero paths **refuses (exit 2)** instead of printing an empty table.

---

## F27 — the macro-model gate, and the black box that no attribute-based check can see

**Measured, not argued: an unresolved module reaches the netlist, Genus exits 0, and
`is_black_box` is false on everything.**

### The gate that exists, and the three knobs that switch it off

`1_synthesis.tcl` guards black boxes in exactly two places, both at ELABORATE:

    :289  if {$SYN_STRICT && !$SYN_BLACKBOX_OK} { set_db hdl_error_on_blackbox true }
    :535  if {$unresolved && !$SYN_BLACKBOX_OK} { flow_fail ... }

Both fired for real during rc5 — `syn.log` and `syn.log1` are two aborted attempts, on
`u_nanosoc_eth_chiplet_chip` and on `u_xhb_sub`. The guard works. What it does not do is
survive its own configuration:

* `SYN_BLACKBOX_OK=1` disables **both** — the same variable is in both conditions;
* `SYN_STRICT=0` disables both too, because it un-sets the elaborate error *and* makes
  `flow_fail` advisory (`flow_utils.tcl:92-95`);
* `SYN_CHECKS=0` skips `check_design` entirely;
* and `try_step "unresolved" { set unresolved [check_design -unresolved -status] }` at
  :522 **swallows an exception**: `unresolved` was pre-set to 0 at :521, so a
  `check_design` that throws leaves 0, `[string is integer -strict 0]` is true, the
  "did not return a count" warning at :527 does not fire, and the gate passes having
  measured nothing. (`asic-toolkit`, not this run's to fix — see F28.)

### The demonstration, on real Genus, not a fixture

A two-module design whose only macro has no model anywhere, run with
`hdl_error_on_blackbox false` (what `SYN_BLACKBOX_OK=1` sets), Genus 21.15, the real
`tcbn65lpwc.lib`:

    elaborate rc                          = 0
    check_design -unresolved -status      = 1
    netlist written                       = 4734 bytes, containing `mystery_ram`
    Genus process exit                    = 0   ("Normal exit")
    get_db insts                          = 64
    get_db insts -if {.is_black_box}      = 0     <-- ZERO
    get_db insts -if {.is_macro}          = 0
    the unresolved module appears as      hinst u_mem (mystery_ram)

**An unresolved reference is not an inst and does not set `is_black_box`.** Every rule
written against instance attributes — including every rule in the first draft of this
gate — is blind to the single most obvious way to get a black box into a netlist.

### Why `is_black_box` is not the check either

On a **healthy** rc5 netlist:

    black-box instances                55
      21  the macros        (all 8 cell types: rf_01k/08k/16k/32k, flash_cache_data/_tag,
                             rom_via, eth_rom_via)
      34  the supply pads   (PVDD1DGZ_G, PVDD2DGZ_G, PVDD2POC_G, PVSS1DGZ_G, PVSS2DGZ_G)

Genus's definition is "timing is understood, function is not", which is precisely what a
RAM's Liberty and a supply pad's are. A gate on that attribute fires 55 times on a clean
design and is switched off within a day.

### What the gate is instead

A census with eight rules, applied in Tcl inside Genus (so the stage stops without needing
Python) and re-applied offline by `scripts/ci/synth_macro_gate.py`, which also
**cross-checks its verdict against the one the hook recorded** — two implementations that
disagree is itself reported, which is how drift between them is caught rather than hidden.

    R0  no unresolved reference survived to the end of synthesis
        (check_design -unresolved, run again AFTER syn_opt, as a post-condition on what
        is about to be written -- and treating a non-count as NOT MEASURED, not as zero)
    R1  every Liberty DESIGN_LIBS_MAX names was actually loaded
    R2  every macro cell's library was built from a file the design named
    R3  every macro model has timing arcs and non-zero area
    R4  every cell in the netlist is declared by a LEF place-and-route will read
    R5  every black-box instance is a macro, a pad, or a cell with no signal pins
    R6  the per-macro instance census matches the committed baseline   (offline only)
    R7  every macro model has at least one instance
    R9  the collateral synthesis does NOT read is readable: DESIGN_LIBS_MIN,
        DESIGN_LIBS_TYP, DESIGN_GDS_MERGE
    R8  (advisory) no two Liberty files share one library() name

**R4 matters more than it looks.** rc5 ran `SYN_MMMC=0`, and `read_physical` is guarded by
`if {($SYN_PLE || $SYN_ISPATIAL) && $SYN_MMMC}` (:453). The log confirms the other branch:
`SYN-WARN: SYN_PLE without SYN_MMMC: no LEF is read`. **Genus read zero LEFs**, so
`lib_cell.lef_inconsistent` is vacuous and synthesis can hand P&R a netlist full of cells
P&R has no physical view of. R4 scans the twelve LEF files P&R will open — about 10 MB,
one second — and asks the question at the stage where the answer is cheap. This is F7 one
stage earlier.

### rc5's verdict

    VERDICT: PASS   (0 hard, 1 advisory)

    cell                insts   arcs  pins       area  lef  library
    flash_cache_data        8    649    81      11337  yes  FLASH_CACHE_DATA_ss_1p08v_1p08v_125c
    rf_08k                  4    719   116      48045  yes  RF_LIB_08K_ss_1p08v_1p08v_125c
    rf_16k                  3    721   117      88941  yes  RF_LIB_16K_ss_1p08v_1p08v_125c
    flash_cache_tag         2    293    50       5485  yes  FLASH_CACHE_TAG_ss_1p08v_1p08v_125c
    eth_rom_via             1   1549   102       9836  yes  USERLIB_ss_1p08v_1p08v_125c
    rf_01k                  1    713   113      10465  yes  RF_LIB_01K_ss_1p08v_1p08v_125c
    rf_32k                  1    723   118     166997  yes  RF_LIB_32K_ss_1p08v_1p08v_125c
    rom_via                 1   1549   102       9836  yes  USERLIB_ss_1p08v_1p08v_125c
                           21

    unresolved references after syn_opt   0
    cells declared by the 12 LEFs P&R reads   969; netlist cells with no LEF   0
    black boxes   55, all 21 macro + 34 pad, none unexpected

### CORRECTION TO F7: it is 8 macro cell types, not 9

F7 records "macro LEF cells declared: 9 (expected 9)". The design instantiates **eight**.
The ninth is `sram_16k`, which `$MEM_BASE/*/*.lef` matches, which is not in
`DESIGN_LIBS_MAX`, `DESIGN_LEFS` or `DESIGN_GDS_MERGE`, and which has zero instances in
the netlist. F7's number is a count of LEFs a glob found, not a count of the design's
macros — the two happened to be reconcilable because the glob's extra cell is unused. Both
of F7's other numbers (21 patterns, 21 instances) are correct and are re-confirmed here
independently, from Genus rather than from a text walk of the netlist.

### NEW (advisory, R8): both boot ROMs declare the SAME Liberty library name

    library(USERLIB_ss_1p08v_1p08v_125c)   in romlibs/cc_rom/rom_via_ss_1p08v_1p08v_125c.lib
    library(USERLIB_ss_1p08v_1p08v_125c)   in romlibs/eth_rom/eth_rom_via_ss_1p08v_1p08v_125c.lib

Genus merges them into one library object whose `.files` is a two-element list. Both cells
are present and correct, so this is not a defect today — but **the database can no longer
say which file `rom_via` came from and which `eth_rom_via`**. F8 went to some trouble to
make synthesis, P&R and stream-out read the same ROM directory; this says that even so,
the per-cell mapping is not recoverable from the tool afterwards, and for a
*mask-programmed* macro that is exactly the question worth being able to ask.

The fix is one line in each of two files:

    ASIC/tech_wrappers/tsmc65/eth_rom.spec:19      libname = USERLIB
    ASIC/tech_wrappers/tsmc65/nanosoc_rom.spec:19  libname = USERLIB

Distinct names there give distinct library objects and restore per-cell provenance. It is
not free: `libname` is part of the compiler input, so both ROMs rebuild (~171 s each) and
both cache keys change. The RF and flash-cache macros already have distinct library names
(`RF_LIB_32K_...`, `FLASH_CACHE_TAG_...`); only the two ROMs collide.

It also cost a false alarm during development, worth recording as a method note: reading
`[lindex [get_db $lc .library.files] 0]` attributed both ROMs to whichever file was read
first and then reported the other as *never read* — a HARD R1 on a healthy design, in the
opposite direction from the defect the rule exists for.

### DISCRIMINATION — the gate is shown able to say no, twice over

**On real Genus output, against rc5's own post-syn_opt database** (`read_db` of this run's
`_syn_session`, the hook sourced unmodified, one input mutated per trial):

    control              nothing changed
                         VERDICT: PASS (0 hard)                                  hook rc=0

    missing_lib          DESIGN_LIBS_MAX also names sram_16k's Liberty, which
                         this run did not load
                         HARD R1  DESIGN_LIBS_MAX names .../sram_16k_ss_1p08v_1p08v_125c.lib
                                  and NO library in the database was built from it
                                                                                 hook rc=1

    missing_lef          rf_32k.lef removed from lef_file_list
                         HARD R4  cell rf_32k (1 instances) is in the netlist and is
                                  declared by NONE of the 11 LEFs place-and-route will
                                  read - P&R will black-box it                   hook rc=1

    no_lefs              every named LEF unreadable
                         HARD R4  LEF .../does_not_exist.lef is named by the flow and
                                  is not readable
                         HARD R4  NONE of the 1 LEFs the flow names is readable, so no
                                  cell in this netlist has been shown to have a
                                  physical view                                  hook rc=1

    missing_lef_ungated  as missing_lef, with SYNTH_MACRO_GATE=0
                         VERDICT: FAIL (1 hard)  *** NOT ENFORCED (SYNTH_MACRO_GATE=0) ***
                                                                                 hook rc=0

The no_lefs arm is the one that had to be fixed rather than merely written. Its first
draft reported "no LEF was readable, so LEF coverage was NOT MEASURED" as an ADVISORY and
then printed `PASS - ... every model with timing arcs, a named source and a LEF`. A LEF
the flow NAMES and cannot open is not unmeasured coverage; it is a stop four hours away.
It is now hard, and the pass line is assembled from what was actually measured so it
cannot name a check that did not run.

These four trials also carry three standing `SOFT R9` advisories, because the harness sets
`DESIGN_LIBS_MAX` and `lef_file_list` and not `DESIGN_LIBS_MIN`/`_TYP`/`DESIGN_GDS_MERGE`.
That is the intended behaviour and it is visible in every one of them: a check that did not
run says so by name. The full run, which sets all five lists, has one advisory (R8) and no
R9.


`missing_lib` and `missing_lef` are the F8 and F7 defects reproduced exactly: a
Liberty the design names and the tool never loaded, and a macro LEF that is absent in this
checkout. Both are caught at synthesis, in seconds, by the run's own inputs.

**On real Genus output, for the direction attributes cannot see:** the two-module
unresolved-macro design above, with the hook sourced over it —

    SYNVIS: unresolved references after syn_opt: 1
    HARD R0  1 unresolved reference(s) are STILL PRESENT after syn_opt and are about to be
             written into the netlist. They are invisible to is_black_box and absent from
             get_db insts, so nothing else here can see them. Candidates: u_mem (mystery_ram).
    hook rc = 1   (the stage stops)

**On mutated census data,** `scripts/ci/synth_macro_gate.py --selftest` — sixteen
mutations, each carrying exactly one defect, each required to fire exactly the named rule:

    a requested Liberty was never loaded                       -> R1
    a macro read from a source the design did not name         -> R2
    a macro model has no timing arcs (times as a wire)         -> R3
    a macro model has zero area                                -> R3
    a macro has a Liberty and no LEF                           -> R4
    a LEF the flow names is unreadable                         -> R4
    no LEF readable at all, but LEFs were named                -> R4
    a netlist cell no LEF declares                             -> R4
    an unexpected black box appears                            -> R5
    a black box with no lib_cell at all                        -> R5
    a memory lost two instances (synthesised into flops?)      -> R6
    the whole macro cell disappeared from the netlist          -> R6
    a macro model exists and has no instances                  -> R7
    an unresolved module reached the netlist                   -> R0
    the fast-corner Liberty for a macro is missing             -> R9
    a macro GDS is missing (an empty box at stream-out)        -> R9

plus: the clean census passes; two Liberty files under one library name is an ADVISORY and
not a failure; an absent, unparseable, key-less or zero-macro census **refuses (exit 2)
rather than passing**; a census with no LEF list prints `-- N of those advisories is a
check that DID NOT RUN` and `A PASS here does not cover: R4`; and a recorded finding this
script did not derive is reported as drift.

`R6` — the committed baseline in `scripts/ci/synth_macro_expect.json`, generated from
rc5 — is the one that catches the direction nothing else can: a memory that stops being a
macro. If a behavioural model wins over the Liberty the RAM is synthesised into
flip-flops, and there is no black box, no unresolved reference and no error. Checked
against rc5's real census with `rf_16k` dropped from 3 instances to 1:

    HARD  R6  macro rf_16k: baseline 3 instances, netlist 1
    HARD  R6  macro instance total: baseline 21, netlist 19
    rc=1

### Two latent traps found while proving the above, both now closed in the hook

* **`$REPORT_DIR` versus `$::REPORT_DIR`.** `flow_hook` sources a hook with
  `uplevel 1 [list source $path]` and is called from the top level, so today a bare
  `$REPORT_DIR` happens to resolve globally. One frame deeper it is a local lookup and the
  hook dies *after synthesis has finished*. Named explicitly, with a refusal that says
  which variable was unset.
* **`array set X {}` does not clear an array**, it merges an empty list into it. Sourced
  twice in one session, the second census would carry the first one's cells. All seven
  arrays are `array unset` first. This is not hypothetical: it is what the first run of
  the mutation harness did — the findings went to `::_find` while the report read a local
  `$_find`, and the gate printed **PASS, 0 findings** having found things. Every finding
  variable is now namespace-qualified on both the write and the read.

---

## F28 — what F26 and F27 leave open

Not fixed here, and each one is somebody else's file.

1. **`asic-toolkit` — `try_step` hides a thrown `check_design`.**
   `1_synthesis.tcl:521-533` pre-sets `unresolved` to 0, then calls `check_design
   -unresolved -status` inside `try_step`, which catches and warns. A throw therefore
   leaves 0, the "not a count" guard sees a valid integer, and the black-box gate passes
   having measured nothing. The fix is to initialise the variable to a non-integer
   sentinel so the existing guard fires — the hook's own R0 does exactly that and is the
   worked example. **Two lines.**

2. **`asic-toolkit` — one knob disables two independent gates.** `SYN_BLACKBOX_OK`
   appears in both :289 and :535. A design that genuinely instantiates a hard macro with
   no HDL view needs the *elaborate* error relaxed; it does not need the post-elaborate
   `check_design` gate switched off as well. Splitting them costs one variable.

3. **The boot ROM Liberty library names collide.** `libname = USERLIB` in both
   `ASIC/tech_wrappers/tsmc65/eth_rom.spec:19` and
   `ASIC/tech_wrappers/tsmc65/nanosoc_rom.spec:19`. Not this task's files, and changing
   them forces both ROMs to recompile and both cache keys to change — a deliberate act,
   not a drive-by. Until then the per-cell answer to "which ROM file did this cell come
   from" does not exist in the synthesis database, and R8 says so on every run.

4. **`ASIC/eth-chiplet/design.mk` — no `make` target reaches the two new scripts.**
   `hooks/post_synth.tcl` invokes both directly during synthesis, so a run gets them; a
   human wanting to re-read a finished run has to type
   `scripts/ci/synth_depth_report.py --reports-dir <run>/reports` and
   `scripts/ci/synth_macro_gate.py --run-dir <run>`. Two phony targets (`synth-depth`,
   `synth-macro-gate`) would make them discoverable. design.mk is another agent's file.

5. **`ci/signoff.yaml` — the macro gate is not a signoff stage.** It gates synthesis,
   which is the right place for it to *stop* a run, but a finished run's
   `synth_macro_gate.rep` is not read by anything. `signoff.py` has 24 stages and none
   of them asks whether the netlist it is signing off has a black box in it.

6. **The hook has never run inside a real synthesis.** Everything in F26 and F27 was
   measured by `read_db` of rc5's own `outputs/nanosoc_eth_chiplet_pads_syn_session` and
   sourcing the hook over it — the same database, the same netlist, but a restored session
   rather than a live one. The reports now in `build/rc5vt-20260829/reports/synth_*` carry
   a `synth_visibility_PROVENANCE.txt` saying exactly that. One path is genuinely
   untested: in a live run `$::lef_file_list` comes from the toolkit's `flow_collateral`;
   here it was taken from `work/nanosoc_eth_chiplet_pads_placed/libs/lef/`, the twelve LEFs
   Innovus actually opened. Same twelve files, different code path.

7. **`build/` is gitignored, so the evidence is host-only** — the same gap F7 and the
   `index/` note above record. The numbers are copied into F26 and F27 for that reason.

8. **The depth reports are not yet a gate, deliberately.** Nothing fails on a 90-level
   path. Setting a ratchet (say: the worst non-buffer depth may not increase) needs a
   baseline whose first value someone has to accept, and accepting 80 non-buffer levels as
   the standing figure is a decision, not a default. `synth_depth.json` carries everything
   such a ratchet would need.
