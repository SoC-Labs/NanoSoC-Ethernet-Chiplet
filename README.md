# nanoSoC Ethernet Chiplet

The integration level for a nanoSoC ethernet chiplet: the multicore SoC, a
die-to-die link, and the chiplet-ID protocol that runs over it, wired side by
side.

```
                    nanosoc_eth_chiplet
  ┌────────────────────────────────────────────────────────────┐
  │                                                            │
  │   nanosoc_multicore_soc                                    │
  │     d2d_ahb_m ──┐                                          │
  │     d2d_ahb_s ◄─┼──┐                                       │
  │     d2d_irq   ◄─┼──┼──┐                                    │
  │     d2d_phc_* ◄─┼──┼──┼─┐                                  │
  │                 │  │  │ │                                  │
  │            ┌────▼──┴──┴─┴────┐        ┌──────────────┐     │
  │            │  d2d sub-decode │        │              │     │
  │            │  0x2E / 0x2F    ├───────►│ tidelink_top │     │
  │            └─────────────────┘        │              │     │
  │                                       │  tc_axis_*   │     │
  │                                       └──────┬───────┘     │
  │                                              │             │
  │                                      ┌───────▼──────────┐  │
  │                                      │ tidechart_       │  │
  │                                      │   controller     │  │
  │                                      └──────────────────┘  │
  │                                                            │
  └────────────────────────────────────────────────────────────┘
                              │ PHY pads
                              ▼  to the far die
```

**This repo owns the integration and nothing else.** It does not fork any of the
three components. It submodules them and wires them together — which is exactly
what TideChart's own README asks for:

> *"TideChart is a **peer** to TideLink — neither repo instantiates the other.
> The system integrator wires them side by side."*

---

## Why a wrapper and not a fork

`nanosoc-multicore-system` exposes a **link-agnostic** die-to-die port. Nothing
in the SoC names TideLink. That is deliberate: it is what lets the PHY be
swapped (`tidelink` → `axi-chiplet-controller` → a vendor PHY) without forking
the SoC. Forking would also inherit six submodules, a code generator, seventy
cocotb environments and a traceability spine — and permanently cut you off from
upstream fixes.

See `nanosoc-multicore-system/docs/D2D_PORT.md` for the port's full rationale.

## What the SoC gives us

| SoC boundary | What the wrapper does with it |
|---|---|
| `d2d_ahb_m_*` | one AHB manager carrying the 32 MB window `0x2E000000..0x2FFFFFFF`; the wrapper sub-decodes it into TideLink's four AHB subordinates plus an AHB→APB bridge |
| `d2d_ahb_s_*` | TideLink's `ahb_mng_*` masters in here; it becomes the SoC's 6th matrix initiator, reaching **only** shared SRAM and the IPC mailbox |
| `d2d_irq[15:0]` | `[7:0]` → CPU0's NVIC (data plane), `[15:8]` → CPU1's (link management) |
| `d2d_phc_*` | PHC hardware servo source 0 — the cross-die timebase |
| `phc_pps_out` | drives TideLink's `phc_pps` (no separate `d2d_phc_pps` port exists) |

## The window sub-map

Offsets are deliberately identical to TideLink's reference map (its local base
`0x44000000` → ours `0x2E000000`), so every address in TideLink's
`REGISTER_MAP.md`, its bring-up runbooks and its `python/tidelink` driver stays
valid after a single base substitution.

| Address | Size | `tidelink_top` port |
|---|---|---|
| `0x2E00_0000` | 16 KB | `ahb_tx_*` — TX aperture. **Wedge hazard**: a write with the link down hangs the bus. Gate it. |
| `0x2E01_0000` | 16 KB | `ahb_fifo_*` — local RX FIFO read window |
| `0x2E02_0000` | 16 B | `ahb_ptp_*` — PTP TX write port |
| `0x2E03_0000` | 8 KB | `apb_*` — Wlink chiplet-controller registers |
| `0x2E03_2000` | 8 KB | `apb_*` — TideLink config + PTP registers |
| `0x2E03_4000` | 8 KB | `apb_*` — address-translator config |
| `0x2F00_0000` | 16 MB | `ahb_sub_*` — peer aperture, address-translated to the far die |

Two signature mismatches the wrapper must absorb, both trivial:

- `tidelink_top.ahb_mng_hprot` is `[6:0]` (AHB5); `d2d_ahb_s_hprot` is `[3:0]`.
- `tidelink_top.ahb_mng_*` has no `hmastlock`; tie `d2d_ahb_s_hmastlock` low.

## Pinned components

| Submodule | Upstream | Pinned to |
|---|---|---|
| `nanosoc-multicore-system` | `soclabs/nanosoc-multicore-system` | `feature/eth-scratch-cycle3` |
| `tidelink` | `soclabs/tidelink` | `integ/tidelink-soc` |
| `tidechart` | `soclabs/tidechart` | `main` |

> ⚠️ **Two of the three pins are feature branches, not `main`.** The D2D port
> lives only on `feature/eth-scratch-cycle3` (17 commits ahead of the SoC's
> `master`, which has none of it), and TideLink's integration line
> `integ/tidelink-soc` is 135 commits ahead of its `main`. Submodule gitlinks
> reference commits rather than branches, so a recursive clone works today — but
> a rebase or branch deletion upstream will strand this repo. **Getting both onto
> their default branches is a prerequisite for calling this repo stable.**
> See `docs/PIN_POLICY.md`.

## Status

Scaffolding. Nothing here elaborates yet. The two genuine prerequisites are:

1. **`tidelink_top` has no sys_desc block description.** TideLink ships
   `sys_desc/tidelink.yaml`, but that describes the *inner* `tidelink` module,
   not the `tidelink_top` subsystem the wrapper instantiates.
2. **TideChart has no `sys_desc/` at all.** `soc_model` cannot instantiate
   `tidechart_controller` until `tidechart.yaml` (`gen: False`) exists.

Both are being written into `sys_desc/` here first; upstreaming them to their
own repos is the right long-term home.

---

*A joint work commissioned on behalf of SoC Labs, under Arm Academic Access
license. Copyright 2026, SoC Labs (www.soclabs.org).*
