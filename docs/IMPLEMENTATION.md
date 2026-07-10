# Physical implementation — start here

The entry point for the physical implementation team. It says what the chiplet
**is**, what is **proven**, what is **yours to decide**, and the handful of
non-obvious facts that will cost you a day if you learn them the hard way. Every
claim links to the doc that backs it.

## What this is

`nanosoc_eth_chiplet` = a `nanosoc_multicore_soc` (two Cortex-M0+ cores, ethernet
subsystem, PHC/PTP) + `tidelink_top` (the die-to-die link) + a TideChart shim,
wired together so a CPU on one die can reach memory on another die over an
8-lane source-synchronous link. It is the shipping integration top; the bonded
chip is `nanosoc_eth_chiplet_chip`.

## Get the source and sanity-check it

```sh
git clone https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet.git
cd NanoSoC-Ethernet-Chiplet
./scripts/bootstrap.sh      # 42 submodules, 8 levels deep — NOT `git clone --recursive`
source set_env.sh
make check                  # chip-boundary + lint — no EDA license needed
make elab                   # full structural elaboration — needs VCS
```

`scripts/bootstrap.sh` rather than `git clone --recursive` because one submodule
*inside* TideLink is still declared over SSH; the script rewrites it to HTTPS for
the fetch. See the README.

## What is proven

| Claim | How | Where |
|---|---|---|
| The top wires together consistently | `make elab` — 0 VCS errors, every port connected once | — |
| Every top port is bonded / tied / open exactly once | `make chip-boundary` — 111 ports, 50 pad cells | `PIN_MAP.md` |
| No combinational loops / latches / width bugs in our RTL | `make lint` (Verilator) | `LINT_FINDINGS.md` |
| **A memory transaction crosses between two REAL SoCs over the link** | `verif/g2_soc_pair` — die A `0x2F00_1000` → die B's real `shared_sram_0` `0x2D00_1000`, payload intact, CAM-off control | `G2_SOC_PAIR_STATUS.md` |
| The link trains between two real SoCs, firmware-free | same env, STAGE 1 | `G2_SOC_PAIR_STATUS.md` |
| The address survives the link end-to-end | RTL trace + G2 sim | `PEER_APERTURE_PROGRAMMING.md §8` |

This is simulation. There is **no silicon and no timing/area/power** — see "open".

## The two integration adapters TideLink's `ahb_sub` required

Both were found by driving the real path (a real SoC master through the real
decode into TideLink) and both are in `nanosoc_eth_chiplet.sv`. Neither is
optional; a chiplet without them wedges or silently drops peer-write data. If you
refactor the peer path, keep them and re-run `verif/g2_soc_pair` +
`verif/chiplet_d2d_decode`.

1. **HREADY comb-loop break** (`hready_to_peer`). TideLink's `ahb_sub_hreadyout`
   depends combinationally on its `ahb_sub_hready` input, which fed back through
   the decode into a zero-register loop. Broken by withholding the peer's own
   HREADY contribution while it owns the data phase. `D2D_HREADY_LOOP.md`.
2. **Write-data alignment** (`d2d_ahb_m_hwdata_q`, 1-cycle delay). TideLink
   pipelines the `ahb_sub` address but samples write data live and sequences AW
   then W a cycle later, so a compliant AHB master's data is gone by the W beat.
   `G2_SOC_PAIR_STATUS.md` (Milestone 2 finding: RESOLVED).

## Document map

| Doc | For |
|---|---|
| `PHYSICAL_HANDOFF.md` | the original handoff: clock domains, reset topology, boundary classes, hard architectural constraints |
| `PIN_MAP.md` | the 50 bonded pads as a fill-in template |
| `POWER_DOMAINS.md` | the D2D power-domain analysis + recommendation (single domain for v1) |
| `RESET_ORDERING.md` | two-die reset ordering for the source-synchronous link |
| `PEER_APERTURE_PROGRAMMING.md` | how a CPU programs the CAM and reaches the peer; the bring-up register sequence |
| `D2D_HREADY_LOOP.md` | the HREADY comb loop and its fix |
| `G2_SOC_PAIR_STATUS.md` | the two-real-SoC proof + the write-data fix |
| `LINT_FINDINGS.md` | lint tooling, the sanity harness, triaged findings |
| `PIN_POLICY.md` | which submodule pins are on default branches vs frozen |
| `patches/` | prepared upstream fixes (TideLink flist, nanosoc_gen `$()→${}`) — not applied |
| `UPSTREAMING_BLOCK_YAMLS.md` | where the two block-description YAMLs belong upstream |

## Yours to decide (open items)

- **Pin map**: pad-cell types, die sides, ball/bump assignment. `PIN_MAP.md`.
- **Power domains**: confirm single-domain for v1 or justify a split. `POWER_DOMAINS.md`.
- **Two-die reset ordering**: the pad-ring / power-sequencing asks. `RESET_ORDERING.md`.
- **Per-die straps**: `role_strap` is the only per-die differentiator while
  `nego_priority_i` is tied — decide whether to fuse it. `PIN_MAP.md`, `PHYSICAL_HANDOFF.md §3`.
- **CDC signoff**: a first structural CDC pass is done (`verif/cdc/run.sh`, HAL
  22.03 via `xrun -hal`) — 14 multi-clock instances, all component-internal, none
  at the wrapper boundary. To *complete* it, add a clock/reset constraints file
  (declare `sys_hclk` / `user_ref_clk` / `pad_clk_rx` and their async relations)
  and re-run for the full `CLKDMN` analysis. `CDC_FINDINGS.md`.
- **Lint**: `make lint` (Verilator) covers our wrapper RTL — no non-waived
  findings. `LINT_FINDINGS.md`.
- **TideLink pin**: `tidelink` is frozen on a feature branch; roll it to `main`
  and apply `patches/0001` upstream. `PIN_POLICY.md`.
- **Peer READ round-trip**: the peer **write** path is proven; a peer **read**
  currently returns 0 because TideLink's `ahb_sub` completes the transfer when it
  accepts the AXI read *address*, before the read *data* returns over the link.
  The primary direction (write, then doorbell IRQ) works; remote reads need a
  TideLink-side hold-until-`rvalid` or a chiplet-side read-completion gate.
  `G2_SOC_PAIR_STATUS.md` "read round-trip".

## Load-bearing gotchas

- **The bench straps can defeat the CDC gate.** `apb_debug_unlock_i` /
  `mask_hs_bypass_i` let software force `role_locked` on a dead recovered clock —
  the path to the a2l 6-word false-FULL wedge, **invisible in single-clock sim**.
  Decide their production defaults. `RESET_ORDERING.md §3`.
- **`link_active_o` is not "link carries data"** — it is `role_locked_o` renamed.
  It also gates the TX aperture internally; isolate it to 0 if you split domains.
- **`ROLE_CFG` survives `hresetn` but not `poresetn`; the CAM survives neither.**
  Re-program the CAM after any warm reset. Matters for retention if you split
  domains. `PEER_APERTURE_PROGRAMMING.md §2`, `POWER_DOMAINS.md`.
- **The peer aperture reaches exactly one remote 16 MB region** (`0x2F`→`0x2D`).
  The mailbox is reached by TideLink's native doorbell, not a remote AHB write.
  `PHYSICAL_HANDOFF.md §4.2`.
- **`make elab` does not evaluate the netlist** — it linked a combinational loop
  cleanly for a month. `make lint` and the `verif/` sims are the real checks.

## Suggested first steps

1. `./scripts/bootstrap.sh && source set_env.sh && make check` — confirm a clean
   tree. Then `make elab` if you have VCS.
2. Read `PHYSICAL_HANDOFF.md`, then `RESET_ORDERING.md`, then `POWER_DOMAINS.md`
   — in that order; each builds on the last.
3. Start `PIN_MAP.md` (pad cells + sides) and settle the power-domain decision.
4. Run your lint/CDC signoff on `nanosoc_eth_chiplet`, not on the components.
5. Resolve the reset-ordering and strap-default questions before committing a pad
   ring.
