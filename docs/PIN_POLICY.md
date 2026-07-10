# Submodule pin policy

A wrapper repo is a claim about reproducibility. This file records exactly what
is pinned, why, and what has to happen before the pins are safe.

**Status 2026-07-10: four of the five pins are now on default branches.** Only
`tidelink` still lives on a feature branch, and that pin is deliberately frozen
(see below).

## Current pins

| Submodule | Commit | Reachable from | Is that a default branch? |
|---|---|---|---|
| `nanosoc-multicore-system` | `1560fa2` | `origin/master` | **Yes** |
| `tidelink` | `3f3de09` | `origin/integ/tidelink-soc` | **No** — 135 commits ahead of `origin/main` |
| `tidechart` | `b5102b2` | `origin/main` *and* `origin/add-subtree-and-irqc-axis` | Yes |

Nested inside `nanosoc-multicore-system`, and equally load-bearing:

| Nested submodule | Commit | Reachable from | Default branch? |
|---|---|---|---|
| `nanosoc_arch_tech` | `202a755` | `origin/main` | **Yes** |
| `nanosoc_arch_tech/nanosoc_gen` | `d9973b3` | `origin/main` | **Yes** |

So a clean checkout of this repo depends on **five** commits, of which **one
lives only on a feature branch** — `tidelink`.

### How the other four got there (2026-07-10)

The D2D work was landed with a three-repo merge train, inner to outer:
`nanosoc_gen` `main` fast-forwarded to `d9973b3`; `nanosoc_arch_tech` `main` took
a real merge of `fix/d2d-generator-wrapper-gate`; the SoC's `master`
fast-forwarded to `1560fa2` after hardware validation on `pynq_z2_03`.

Note what was *not* done. `nanosoc_arch_tech`'s `main` carried ten
compute-system / M4 / Zephyr commits touching `sys_desc/subsystems/cpu/*` and
`regions/sram` — files this SoC consumes. Adopting them would have changed
generated RTL and invalidated the bitstream that had just been validated on
silicon. So the branches were merged **into** each submodule's `main`, making the
pinned commits main-reachable, and the SoC's pins were left byte-identical. Same
RTL, same validation, no feature-branch dependency. Prefer this whenever a pin
must become "safe" without re-qualifying the hardware.

### tidelink stays frozen, on purpose

`3f3de09` is the commit the integration was built and elaborated against. Rolling
it forward is a separate exercise with its own bring-up cost, and is owned
elsewhere. Until it lands on `origin/main`, this repo is one upstream rebase away
from being stranded — see the risk section below.

## Why this is a real risk, not a formality

A submodule gitlink names a *commit*, not a branch. So long as the commit is
reachable from **some** ref on the remote, `git submodule update --init
--recursive` works. It works today; I verified the whole chain resolves.

It stops working the moment anyone rebases or deletes the branch a pin depends
on. That is not hypothetical — this exact chain was dangling once already,
because the parent was pushed and its submodule branches were not. Since
2026-07-10 the only remaining exposure is `tidelink:integ/tidelink-soc`.

The `nanosoc_gen` pin used to be the sharpest edge (it is now on `main`, so the
rebase risk is gone, but the *content* risk below still matters). `d9973b3`
carries two things without which this wrapper cannot work:

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

1. ~~Land the D2D work on `nanosoc-multicore-system:master`.~~ **DONE 2026-07-10.**
   `master` = `1560fa2`, gated on a full FPGA regression on `pynq_z2_03`
   (28 of 31 tests pass deterministically across three runs; the two non-passes
   are z2_03's physical eth-TX egress fault and the pre-existing intermittent
   `ipc_rpc` IRQ-delivery gap, neither caused by D2D). This repo's pin was moved
   to `master` and re-proven with `make elab` (0 errors, clean build) and
   `make chip-boundary` (111/111 ports).
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

Until (3), treat this repo as **pre-release**: it builds, but one of its five
foundation commits can still be pulled out from under it by someone with no idea
it exists.

## Hardware validation status

**The SoC carrying the D2D port has run on silicon.** Bitstream builds clean
(0 errors, WNS +0.400 ns on PYNQ-Z2) and a full FPGA regression ran three times
on `pynq_z2_03`: 28 of 31 tests pass deterministically, `preflight` (the INFRA
gate) passes every run. The three non-passes are all accounted for and none is
caused by D2D — `eth_tsu_watermark` is that board's physical eth-TX egress fault
(`eth_mac_loopback` passes), `ipc_rpc` is a pre-existing intermittent
IRQ-delivery gap (`ipc_sock` passes on the same mailbox), and
`phc_servo_control` flaps SKIP/PASS by design because its status bit is driven by
the live HA1588 ethernet servo. D2D was independently exonerated twice:
`d2d_irq` is tied `16'h0` in the FPGA wrapper, and the D2D commits moved no
pre-existing NVIC bit.

**But no transaction has ever crossed a real die boundary.** `soc_d2d_loopback`
drives the SoC's D2D *port* in both directions against a memory model, with two
mutation-verified tests. That proves the port, not the link. The pair sim
(`docs/G2_PAIR_SIM.md`) is what would prove the link, and it does not exist yet.

## Checking the chain

```sh
# every gitlink must be reachable from at least one remote ref
git submodule status --recursive
for m in nanosoc-multicore-system tidelink tidechart; do
  ( cd "$m" && git for-each-ref --contains HEAD refs/remotes | wc -l )
done   # each must be >= 1
```

A `0` means someone deleted or rewrote the branch and a fresh clone will fail.

## Known-benign duplicate module definitions (checked 2026-07-10)

`make elab` emits 11 `Warning-[OPD] Override previous declaration`. Six are the
same file listed twice on the flist. The other five are genuinely two *different*
files defining the same module:

| Module | Copy A | Copy B |
|---|---|---|
| `cmsdk_apb_slave_mux` | `BP210/.../cmsdk_apb_slave_mux.v` | `latest/Corstone-101/.../cmsdk_apb_slave_mux.v` |
| `xhb500_flop` / `_or` / `_sync` / `_xor` | `xhb500/generated/xhb_chiplet_mst/...` | `xhb500/generated/xhb_chiplet_slv/...` |

**All five pairs are byte-identical today** (`cmp` clean), so whichever copy the
compiler binds, the RTL is the same. This is recorded, not fixed, because it is a
latent trap rather than a live bug: regenerate `xhb500` with different `mst`/`slv`
parameters, or let the two Arm IP releases drift, and the wrong copy binds
silently — and *which* copy binds is tool-dependent (VCS takes the last
declaration, Verilator errors, some Xcelium/Icarus modes take the first).

This is the same failure mode `flist/resolve_tidelink_flist.py` exists to prevent
for `WlinkGenericFCReplayAddrSync_18`, where the two copies do **not** match and
the `deps/` one lacks the a2l reset-skew fix. The earlier audit that concluded
"`AddrSync_18` is the only shadowed module" was scoped to TideLink's own flist;
across the *integrated* elaboration there are five more, all currently harmless.

If you tighten this, do it flist-side. `/research/AAA/ip_library/**` is shared,
read-only, lab-wide collateral — never edit it.
