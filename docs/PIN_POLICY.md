# Submodule pin policy

A wrapper repo is a claim about reproducibility. This file records exactly what
is pinned, why, and what has to happen before the pins are safe.

**Status 2026-07-16: all five pins are on default branches. The risk this file tracks
is closed.** `tidelink` was the last hold-out; its pin was rolled to pick up two
perf-block fixes and `tidelink:main` was fast-forwarded and pushed, so the pin is
main-reachable — see "The 2026-07-16 tidelink roll" below. `tidechart` and
`nanosoc-multicore-system` were also rolled the same day (both "gated green").

## Current pins

| Submodule | Commit | Reachable from | Is that a default branch? |
|---|---|---|---|
| `nanosoc-multicore-system` | `84b8617` | `origin/master` | **Yes** |
| `tidelink` | `43c3d7c` | `origin/main` *and* `origin/integ/tidelink-soc` | **Yes** |
| `tidechart` | `585e042` | `origin/main` | **Yes** |

> **All three top-level pins are now reachable from a default branch, verified by the
> chain check below** (`refs >= 1` and on `origin/main`/`origin/master` for each).
> `tidelink:main` was fast-forwarded `3f3de09 -> 43c3d7c` and **pushed** on
> 2026-07-16. The feature-branch dependency this document was written to track is
> **closed**.

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

### ~~tidelink stays frozen, on purpose~~ — superseded 2026-07-16

`3f3de09` was the commit the integration was built and elaborated against, and it was
held deliberately. That changed on 2026-07-16; see the next section.

### The 2026-07-16 tidelink roll: `3f3de09` -> `43c3d7c`

Rolled to pick up two fixes to the perf register block, plus the V2 ASIC flist commit.
`43c3d7c` = `3f3de09` + three commits:

| Commit | What |
|---|---|
| `e6f0254` | `fix(apb)`: perf region decode off by one — PERF_CTRL writes were dead |
| `a094999` | `fix(sw)`: PERF_CTRL bits rotated; `0x0F8` is CONG_STATE, not scratch |
| `43c3d7c` | `flists`: make `tidelink_top_full_asic_v2` elaborate — V2 is the ship config |

**Why this roll was cheap, unlike the one the old text feared.** `origin/main` was a
strict *ancestor* of `3f3de09` (0 commits unique to main, 135 unique to
`integ/tidelink-soc`), so fast-forwarding `main` adopts the integration line **without
changing a single built artifact** — the RTL was already what the pin builds. That is
the same "make the pin main-reachable without re-qualifying the hardware" pattern used
for the other four pins on 2026-07-10. Only the three commits above are new RTL/SW.

**Gated on:**
- `make elab` — 0 errors on a **clean rebuild** (`rm -rf build/elab` first; VCS
  incremental compile reports "no re-compilation is necessary" and will happily
  re-link a stale `simv` against changed RTL, so an incremental pass proves nothing).
- `make regress` — 4/4 PASS: `decode_tx_gate`, `decode_hready_loop`,
  `g2_peer_aperture`, `g2_soc_pair` (the two-real-SoC pair sim).
- `make chip-boundary` — 111 ports, 46 pad cells, all classified.
- tidelink `cocotb/tidelink_apb_regs`: 49/49 existing + 4/4 new
  `test_perf_region_decode`, mutation-verified (3 of the 4 fail against the old form).

**Blast radius of the fix.** One line of RTL (`perf_reg_region` in
`tidelink_apb_regs.sv`) plus SW headers. It makes PERF_CTRL writes reachable, which
were previously dead — so perf can now be enabled, where before `perf_enable_r` was
stuck at 0. No existing behaviour depended on the dead path. See
`docs/STATUS_REGISTERS.md` §5.

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
3. ~~Merge `tidelink:integ/tidelink-soc` to `tidelink:main`, or accept the pin
   deliberately.~~ **DONE 2026-07-16.** `tidelink:main` was fast-forwarded to
   `43c3d7c` and pushed. A pure fast-forward — `origin/main` was a strict ancestor of
   the pin, so no content decision was involved and no built artifact changed; only
   the three commits in the roll section above are new.

**All three items are now closed, and the stranding risk this document exists to track
is gone:** every pin resolves from a default branch, so a fresh
`git submodule update --init --recursive` cannot be broken by someone rebasing or
deleting a feature branch. Re-run the chain check below after any pin change.

The repo's remaining caveats are about *hardware*, not pins — see "Hardware validation
status" below and PHYSICAL_HANDOFF §6.

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

**But no transaction has ever crossed a real die boundary ON SILICON.**
`soc_d2d_loopback` drives the SoC's D2D *port* in both directions against a memory
model, with two mutation-verified tests — that proves the port, not the link.

~~The pair sim is what would prove the link, and it does not exist yet.~~ **It
exists and it passes** (superseded 2026-07-16): `verif/g2_soc_pair` instantiates the
shipping `nanosoc_eth_chiplet` twice, cross-wires the PHY pads, and crosses a
transaction from die A's D2D window into die B's real `shared_sram_0` — both
directions, plus an 8-word burst. It is part of `make regress`. See
`G2_SOC_PAIR_STATUS.md` (`G2_PAIR_SIM.md` is the older design note).

So the link's datapath is proven **in simulation between two real SoC dies**. The
gap that remains is **hardware**: no die-to-die transaction has run on silicon, and
the sim's bring-up uses the bench straps rather than real auto-negotiation
(`NEGO_CFG_RESET = 7'h00`), so the production bring-up sequence is also unproven.
Simulation is additionally blind to the a2l reset-skew bug the `AddrSync_18`
override fixes — those green sims would be green either way (PHYSICAL_HANDOFF §6).

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
