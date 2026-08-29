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

**Scope, stated so it is not over-read.** This covers the stage-0 boot ROM
only, on one machine, with the toolchain currently installed. It says nothing
about the other 47 firmware artefacts, and nothing about whether the ASIC flow
downstream of it is reproducible.
