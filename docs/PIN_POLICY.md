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
   that this repo tracks a long-lived integration branch).
2. Land `nanosoc_gen:integ/d2d-plus-generator-rollup` — which reconciles the
   rollup's 7 commits with the 2 D2D generator fixes — and roll `nanosoc_arch_tech`
   onto it. That branch is pushed and verified (1388 tests, byte-identical RTL,
   `soc_d2d_loopback` 9/9), but **not yet adopted**: it pulls in
   `fix(toplevel): invert AHB directions for external target sockets (exp)`,
   which its own author marked experimental and which touches the machinery
   `d2d_ahb_s` depends on. It wants a human review.
3. Merge `tidelink:integ/tidelink-soc` to `tidelink:main`, or accept the pin
   deliberately. It is 135 commits ahead and is plainly the live line — but it
   is not the default branch, and nothing says so from the outside.

Until (1)–(3), treat this repo as **pre-release**: it builds, but its foundation
can be pulled out from under it by someone with no idea this repo exists.

## Checking the chain

```sh
# every gitlink must be reachable from at least one remote ref
git submodule status --recursive
for m in nanosoc-multicore-system tidelink tidechart; do
  ( cd "$m" && git for-each-ref --contains HEAD refs/remotes | wc -l )
done   # each must be >= 1
```

A `0` means someone deleted or rewrote the branch and a fresh clone will fail.
