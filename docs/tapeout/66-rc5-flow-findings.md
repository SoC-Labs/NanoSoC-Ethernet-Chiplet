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
