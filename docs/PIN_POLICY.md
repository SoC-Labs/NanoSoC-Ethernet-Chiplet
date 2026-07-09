# Submodule pin policy

A wrapper repo is a claim about reproducibility. This one currently pins two of
its three components to **feature branches**, which weakens that claim. This
file records exactly what is pinned, why, and what has to happen before the pins
are safe.

## Current pins

| Submodule | Commit | Reachable from | Is that a default branch? |
|---|---|---|---|
| `nanosoc-multicore-system` | `9daaa59` | `origin/feature/eth-scratch-cycle3` | **No** — `master` has none of this |
| `tidelink` | `3f3de09` | `origin/integ/tidelink-soc` | **No** — 135 commits ahead of `origin/main` |
| `tidechart` | `b5102b2` | `origin/main` *and* `origin/add-subtree-and-irqc-axis` | Yes |

Nested inside `nanosoc-multicore-system`, and equally load-bearing:

| Nested submodule | Commit | Reachable from |
|---|---|---|
| `nanosoc_arch_tech` | `6f4d02a` | `origin/fix/d2d-generator-wrapper-gate` |
| `nanosoc_arch_tech/nanosoc_gen` | `6c4de46` | `origin/fix/d2d-passthrough-hready-and-wrapper-port-gate` |

So a clean checkout of this repo depends on **five** commits, of which **four
live only on feature branches.**

## Why this is a real risk, not a formality

A submodule gitlink names a *commit*, not a branch. So long as the commit is
reachable from **some** ref on the remote, `git submodule update --init
--recursive` works. It works today; I verified the whole chain resolves.

It stops working the moment anyone rebases or deletes one of those four
branches. That is not hypothetical — this exact chain was dangling once already
this week, because the parent was pushed and its submodule branches were not.

The `nanosoc_gen` pin is the sharpest edge. Commit `6c4de46` carries two things
without which this wrapper cannot work:

1. **The passthrough-`hready` fix.** Without it the SoC's bus matrix believes
   the off-die target is always ready, so TideLink can never insert a wait
   state and every multi-cycle read returns garbage. A die-to-die link is
   multi-cycle by nature; this is the single most load-bearing property of the
   port.
2. **The wrapper port gate**, which refuses to emit a chip/FPGA wrapper that
   silently drops a SoC port.

There is a sibling branch, `nanosoc_gen:fix/generator-defects-rollup`, that was
cut before that fix and **reverts it**. Merging it instead of
`integ/d2d-plus-generator-rollup` silently reintroduces the bug. The only guard
in the whole tree is
`nanosoc-multicore-system/cocotb/soc_d2d_loopback::outbound_slave_can_wait_state`.

> **Run `soc_d2d_loopback` on any `nanosoc_gen` merge.** If it goes red on
> `outbound_slave_can_wait_state`, someone has re-tied `hreadyout` high.

## What has to happen before these pins are stable

1. Land the D2D work on `nanosoc-multicore-system:master` (or agree, in writing,
   that this repo tracks a long-lived integration branch). `feature/eth-scratch-cycle3`
   is 17 commits ahead of `master` and `master` has none of it.
   **Not done.** The usual gate for landing on master is an FPGA regression on
   silicon, and that could not run — see the HW note below.
2. ~~Adopt `nanosoc_gen:integ/d2d-plus-generator-rollup`.~~ **DONE 2026-07-10.**
   `nanosoc_arch_tech` now points at it (`202a755` → `nanosoc_gen d9973b3`).
   The commit that held it up, `fix(toplevel): invert AHB directions for external
   target sockets (exp)`, was reviewed: **`(exp)` names the `exp` EXPANSION
   REGION, not "experimental"**. It fixes port directions for an interconnect
   target with no instance and no passthrough — Vivado 2024.1 refuses to
   back-propagate through the coerced ports, while simulators silently hide it.
   It cannot fire on `nanosoc_multicore_soc` (no `exp` target; every target has an
   instance or passthrough), which is exactly why the regenerated RTL is
   byte-identical. Verified before adopting: 1388 generator tests, four REAL
   wrapper cross-checks against the live SoC, byte-identical `nanosoc_multicore_soc.sv`,
   and `soc_d2d_loopback` 9/9 — including `outbound_slave_can_wait_state`, the only
   guard against that branch's original reversion of the `hreadyout` fix.
3. Merge `tidelink:integ/tidelink-soc` to `tidelink:main`, or accept the pin
   deliberately. It is 135 commits ahead and is plainly the live line — but it
   is not the default branch, and nothing says so from the outside.
   **Not done** — another repo's call.

Until (1) and (3), treat this repo as **pre-release**: it builds, but its
foundation can be pulled out from under it by someone with no idea it exists.

## Hardware validation status

The SoC bitstream for the pinned commit builds clean — **0 errors, WNS +0.400 ns**
on PYNQ-Z2. It has **not** been run on silicon: `pynq_z2_04_pl` is currently bound
to project `nanosoc-compute-system` (`bitstream_loaded: true, boot_validated: true`)
with a live build in flight, and deploying would have clobbered another
workstream mid-run. The board lease was released rather than take it.

So the D2D port is verified in **simulation only**. `soc_d2d_loopback` drives it
in both directions, with two mutation-verified tests — but no transaction has
crossed a real die boundary, and no chiplet exists to make one.

## Checking the chain

```sh
# every gitlink must be reachable from at least one remote ref
git submodule status --recursive
for m in nanosoc-multicore-system tidelink tidechart; do
  ( cd "$m" && git for-each-ref --contains HEAD refs/remotes | wc -l )
done   # each must be >= 1
```

A `0` means someone deleted or rewrote the branch and a fresh clone will fail.
