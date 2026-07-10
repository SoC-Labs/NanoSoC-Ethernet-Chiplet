# nanoSoC Ethernet Chiplet

The integration level for a nanoSoC ethernet chiplet: the multicore SoC, a
die-to-die link, and the chiplet-ID protocol that runs over it, wired side by
side.

> **Implementing this chiplet? Start at [`docs/IMPLEMENTATION.md`](docs/IMPLEMENTATION.md)** —
> what is proven, what is yours to decide, and the gotchas that cost a day.

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

`chiplet_d2d_decode` resolves regions at **`haddr[19:16]`** granularity within
`0x2E`, and `haddr[24]` separates `0x2E` from `0x2F`:

| Address | Size | Decoded to |
|---|---|---|
| `0x2E00_0000` | 16 KB | `tidelink_top.ahb_tx_*` — TX aperture. **Wedge hazard**: a write with the link down hangs the bus. Gate it. |
| `0x2E01_0000` | 16 KB | `tidelink_top.ahb_fifo_*` — local RX FIFO read window |
| `0x2E02_0000` | 16 B | `tidelink_top.ahb_ptp_*` — PTP TX write port |
| `0x2E03_0000` | 32 KB | `tidelink_top.apb_*`, via `cmsdk_ahb_to_apb #(.ADDRWIDTH(15))` |
| `0x2E04_0000` | 4 KB | `tidechart_controller.apb_*`, via `cmsdk_ahb_to_apb #(.ADDRWIDTH(12))` |
| `0x2F00_0000` | 16 MB | `tidelink_top.ahb_sub_*` — peer aperture, address-translated to the far die |
| anything else in the window | — | two-cycle AHB **ERROR** (never OKAY-with-zeros) |

TideLink's own three register banks live **inside** that single 32 KB APB region,
selected by `apb_paddr[14:13]` in its RTL — not by this decoder:

| APB address | Bank |
|---|---|
| `0x2E03_0000` | Wlink chiplet-controller registers |
| `0x2E03_2000` | TideLink config + PTP registers |
| `0x2E03_4000` | address-translator config |

That is why `tidelink_top.apb_paddr` is 15-bit even though its `APB_ADDR_W`
parameter is 12 — a discrepancy that looks like a bug until you see the bank
decode.

Two signature mismatches the wrapper must absorb, both trivial:

- `tidelink_top.ahb_mng_hprot` is `[6:0]` (AHB5); `d2d_ahb_s_hprot` is `[3:0]`.
- `tidelink_top.ahb_mng_*` has no `hmastlock`; tie `d2d_ahb_s_hmastlock` low.

## Pinned components

| Submodule | Upstream | Pinned to |
|---|---|---|
| `nanosoc-multicore-system` | `soclabs/nanosoc-multicore-system` | `master` |
| `tidelink` | `soclabs/tidelink` | `integ/tidelink-soc` |
| `tidechart` | `soclabs/tidechart` | `main` |

> ⚠️ **One of the three pins is still a feature branch.** TideLink's integration
> line `integ/tidelink-soc` is 135 commits ahead of its `main`, and that pin is
> deliberately frozen at the commit this integration was built against. Submodule
> gitlinks name commits rather than branches, so a clone works today — but a
> rebase or branch deletion upstream will strand this repo.
>
> The SoC pin moved to `master` on 2026-07-10, once the D2D port was
> hardware-validated. Counting the two nested pins, **four of the five commits
> this repo depends on are now on default branches.** See `docs/PIN_POLICY.md`.

## Status

**It elaborates.** `make elab` builds `nanosoc_eth_chiplet` from a clean tree
with zero VCS errors, and every one of the six instances has all of its RTL ports
connected exactly once (114/114, 31/31, 25/25, 25/25, 165/165, 28/28).

```sh
git clone https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet.git
cd NanoSoC-Ethernet-Chiplet
./scripts/bootstrap.sh          # 42 submodules, 8 levels deep
source set_env.sh
make elab
```

Use `scripts/bootstrap.sh` rather than `git clone --recursive`. This repo's three
submodules are HTTPS, but one submodule *inside* TideLink — `deps/tidelink-phy`,
at the commit we pin — is still declared over SSH, so a plain recursive clone
dies there unless you hold SoTON SSH keys. `bootstrap.sh` rewrites that one URL
to HTTPS for the duration of the fetch, writes nothing to your git config, and
then checks that no submodule was silently skipped. It is idempotent, and it
repairs a half-finished clone.

If you would rather plain `git clone --recursive` simply worked, set the rewrite
once, globally:

```sh
git config --global url."https://git.soton.ac.uk/".insteadOf "git@git.soton.ac.uk:"
```

The real fix is one line in TideLink's own `.gitmodules`; this repo's TideLink
pointer is deliberately frozen, so it is worked around here instead.

What is here:

| | |
|---|---|
| `src/rtl/nanosoc_eth_chiplet.sv` | structural top, 93 boundary ports |
| `src/rtl/chiplet_d2d_decode.sv` | the window sub-decode, 28/28 self-checks, mutation-verified |
| `src/rtl/tidechart_shim.sv` | flattens TideChart's unpacked-array ports; bit-ordering proven, not asserted |
| `sys_desc/tidelink_top.yaml` | 165-port block description — TideLink ships one only for its *inner* module |
| `sys_desc/tidechart.yaml` | 28-port block description — TideChart had no `sys_desc/` at all |
| `docs/PIN_POLICY.md` | why four of five pins are feature branches, and what must change |
| `docs/G2_PAIR_SIM.md` | the nanoSoC↔nanoSoC gate, and a note that **two** wrapper repos exist |

Upstreaming the two YAMLs to `tidelink` and `tidechart` is the right long-term home.

### What is not done

- **No G2 pair sim.** The link has never carried a transaction between two dies.
  `soc_d2d_loopback` in the SoC drives the port against a memory model; that is
  not the same thing. See `docs/G2_PAIR_SIM.md`.
- **No silicon.** The SoC bitstream for the pinned commit builds clean
  (WNS +0.400 ns) but was never deployed — the board was in use by another
  project. `docs/PIN_POLICY.md` records this.
- **Two upstream flist bugs are worked around, not fixed**: `tidelink_fpga.flist`
  compiles a dep and an override that disagree on a port list (7× `UPIMI-E`), and
  the SoC's generated flists emit `$(VAR)` where VCS needs `${VAR}`.
- **`s_i2c_axi_*` is tied off**, so the CPUs cannot master TideLink's I2C
  sideband. If that is wanted it needs bridging to a SoC initiator.

---

*A joint work commissioned on behalf of SoC Labs, under Arm Academic Access
license. Copyright 2026, SoC Labs (www.soclabs.org).*
