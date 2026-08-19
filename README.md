# nanoSoC Ethernet Chiplet

A TSMC 65 nm LP **chiplet**: an Arm Cortex-M0+ SoC with an Ethernet MAC and a PTP
hardware clock, plus a **die-to-die link** that lets a CPU on this die read and
write memory on a *different* die in the same package.

This repository is the **integration level**. It owns the wiring and nothing else:
the three functional blocks are Git submodules, unforked, pinned to specific
commits, and connected by three small SystemVerilog modules in `src/rtl/`.

> **New here?** Read this page, then
> [`docs/design/IMPLEMENTATION.md`](docs/design/IMPLEMENTATION.md) — what is proven,
> what is still yours to decide, and the handful of facts that cost a day if you
> learn them the hard way.

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

---

## The three submodules

| Submodule | What it is | What it does here |
|---|---|---|
| `nanosoc-multicore-system` | the SoC — two Cortex-M0+ cores, AHB matrix, Ethernet MAC, QSPI flash cache, PHC/PTP block, DMA | provides a **link-agnostic** die-to-die port (`d2d_ahb_m`, `d2d_ahb_s`, `d2d_irq`, `d2d_phc_*`). Nothing in the SoC names TideLink. |
| `tidelink` | the die-to-die interconnect — AHB/AXI bridges, a credit-based flow-control layer, an address translator (CAM) and a serial PHY | carries transactions across the package. Exposes four AHB subordinates plus an APB register file, and one AHB manager pointing back into the SoC. |
| `tidechart` | the chiplet-identity / role-election protocol | decides which die is master and hands out chiplet IDs. It is a **peer** to TideLink — neither instantiates the other; this repo wires them side by side. |

Two further submodules carry the backend flow rather than design content:
`ASIC/asic-toolkit` (the current Genus/Innovus flow engine, shared across the lab)
and `ASIC/asic-flows` (its predecessor).

### Why a wrapper and not a fork

The SoC's D2D port is deliberately link-agnostic, so the PHY can be swapped
(`tidelink` → `axi-chiplet-controller` → a vendor PHY) without forking the SoC.
Forking would also inherit six submodules, a code generator, seventy cocotb
environments and a traceability spine — and permanently cut you off from upstream
fixes. See `nanosoc-multicore-system/docs/D2D_PORT.md` for the port's rationale.

---

## Getting a working tree

```sh
git clone https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet.git
cd NanoSoC-Ethernet-Chiplet
./scripts/bootstrap.sh          # every submodule, recursively
source set_env.sh               # source it; do not execute it
```

Use `scripts/bootstrap.sh`, **not** `git clone --recursive`. One submodule nested
inside TideLink (`deps/tidelink-phy`) is declared over SSH at the commit we pin, so
a plain recursive clone dies there unless you hold SoTON SSH keys. `bootstrap.sh`
rewrites that one URL to HTTPS for the duration of the fetch, writes nothing to your
git config, checks that no submodule was silently skipped, and repairs a
half-finished clone. If you would rather plain recursive clones worked, set the
rewrite globally, once:

```sh
git config --global url."https://git.soton.ac.uk/".insteadOf "git@git.soton.ac.uk:"
```

`set_env.sh` exports only the component roots (`TIDELINK_HOME`, `TIDECHART_HOME`,
`NANOSOC_MULTICORE_HOME`, …) that the flists resolve against. It deliberately does
**not** source the submodules' own env scripts — each mutates `PATH` and points
vendor-IP variables at the shared lab tree, and chaining three of them produces an
environment nobody can reason about. Submodule flows are invoked through their own
Makefiles instead.

## Build and simulate

`make help` lists every target, grouped. The ones you need first:

| Command | What it does | Needs |
|---|---|---|
| `make check` | the licence-free gate: no vendor collateral tracked, boundary spec covers every RTL port exactly once, Verilator lint | nothing |
| `make elab` | structurally elaborate `nanosoc_eth_chiplet` | VCS |
| `make regress` | every data-plane simulation proof, as one pass/fail table | VCS |
| `make lint` | Verilator structural lint over the wrapper RTL | nothing |
| `make cdc` | structural clock-domain-crossing pass over the integrated top | Xcelium/HAL |
| `make elab-strict` | strict ASIC-elaboration gate — catches synthesis blockers a simulator hides | Xcelium/HAL |
| `make chip-boundary` | check the pad/boundary spec against the real RTL port list | nothing |
| `make bscan` | regenerate the boundary-scan register and BSDL, splice into the pad ring | nothing (VCS for `bscan-sim`) |

Start with `make check`. If that is red, nothing downstream is meaningful.

## Where the ASIC flow lives

Two flows sit side by side. **`ASIC/eth-chiplet/` is the current one** (driven by the
`ASIC/asic-toolkit` submodule); `ASIC/genus-innovus/` is the legacy flow, kept
because it still holds run history and some checks. Both are reached from the top
Makefile, the legacy one through `-legacy` suffixes:

```sh
make asic            # the flow's own help, listing every stage it offers
make asic-status     # which stages have run in this build directory
make asic-syn        # synthesis (Genus) -> gate netlist, SDC, reports
make asic-pnr        # place + CTS + route (Innovus). Multi-hour.
make asic-gds        # syn + place + cts + route, end to end, unattended
make asic-drc        # Calibre DRC over the GDS this build produced
make asic-lvs-pre    # LVS input preflight — no licence, no long run
```

Never run a backend flow before? Read [`docs/tapeout/`](docs/tapeout/00-index.md)
first: it is a from-scratch guide to this project's Genus/Innovus flow, its scripts
line by line, and how to read the reports it produces.

## What this repo owns

| Path | |
|---|---|
| `src/rtl/nanosoc_eth_chiplet.sv` | the structural top |
| `src/rtl/chiplet_d2d_decode.sv` | the D2D window sub-decode; self-checking and mutation-verified |
| `src/rtl/tidechart_shim.sv` | flattens TideChart's unpacked-array ports |
| `src/rtl/bscan/` | generated boundary-scan register, TAP and instruction register |
| `sys_desc/` | chip boundary spec, plus block descriptions for `tidelink_top` and `tidechart_controller` |
| `flist/` | the simulation and ASIC file lists |
| `verif/` | this repo's own testbenches and gates |
| `cdc/` | chiplet-level SpyGlass CDC setup |
| `ASIC/` | backend flows, tech wrappers and signoff decks |
| `scripts/` | bootstrap, boundary and pad-ring checks, CI gates, rig tooling |

## The D2D address window

The SoC hands the wrapper one 32 MB window, `0x2E00_0000..0x2FFF_FFFF`.
`chiplet_d2d_decode` resolves it at `haddr[19:16]` within `0x2E`, with `haddr[24]`
separating `0x2E` from `0x2F`:

| Address | Size | Decoded to |
|---|---|---|
| `0x2E00_0000` | 16 KB | `tidelink_top.ahb_tx_*` — TX aperture. **Wedge hazard**: a write with the link down hangs the bus. Gate it. |
| `0x2E01_0000` | 16 KB | `tidelink_top.ahb_fifo_*` — local RX FIFO read window |
| `0x2E02_0000` | 16 B | `tidelink_top.ahb_ptp_*` — PTP TX write port |
| `0x2E03_0000` | 32 KB | `tidelink_top.apb_*`, via `cmsdk_ahb_to_apb #(.ADDRWIDTH(15))` |
| `0x2E04_0000` | 4 KB | `tidechart_controller.apb_*`, via `cmsdk_ahb_to_apb #(.ADDRWIDTH(12))` |
| `0x2F00_0000` | 16 MB | `tidelink_top.ahb_sub_*` — peer aperture, address-translated to the far die |
| anything else in the window | — | two-cycle AHB **ERROR**, never OKAY-with-zeros |

Offsets are deliberately identical to TideLink's reference map (its local base
`0x4400_0000` → ours `0x2E00_0000`), so every address in TideLink's own register
map, runbooks and Python driver stays valid after one base substitution.

TideLink's three register banks live *inside* that single 32 KB APB region, selected
by `apb_paddr[14:13]` in TideLink's RTL rather than by this decoder — `0x2E03_0000`
chiplet controller, `0x2E03_2000` config + PTP, `0x2E03_4000` address translator.
That is why `tidelink_top.apb_paddr` is 15-bit even though its `APB_ADDR_W`
parameter is 12: it looks like a bug until you see the bank decode.

Two signature mismatches the wrapper absorbs, both trivial:
`tidelink_top.ahb_mng_hprot` is `[6:0]` (AHB5) while `d2d_ahb_s_hprot` is `[3:0]`;
and `ahb_mng_*` has no `hmastlock`, so `d2d_ahb_s_hmastlock` is tied low.

## Status

- **It elaborates.** `make elab` builds the top from a clean tree with zero VCS
  errors, and every instance has all of its RTL ports connected exactly once.
- **Hardware-validated on FPGA.** The design runs as a two-board KR260 pair. The
  die-to-die link comes up bilaterally (FCSM = 4) and carries cross-die memory
  transfers in both directions. See
  [`docs/bringup/KR260_BENCH_RUNBOOK.md`](docs/bringup/KR260_BENCH_RUNBOOK.md).
- **Not yet fabricated.** The ASIC is in backend implementation for a GDS
  submission. Backend state lives in [`docs/tapeout/`](docs/tapeout/00-index.md)
  and [`docs/asic/`](docs/asic/).
- **Two-die simulation exists.** `verif/g2_soc_pair/` runs two real SoC dies across
  one TideLink; `verif/g2_peer_aperture/` is the smaller link-only pair bench.

### Known open items

- **A cross-die write can wedge the bus.** Under injected error or sustained
  traffic, `ahb_sub_hreadyout` can latch low with no timeout. Root-caused,
  partially fixed, still open — the investigation chain is in
  [`docs/debug/`](docs/debug/).
- **Pins drift.** Submodule gitlinks name commits, not branches, and this
  checkout's submodules are not all on their default branches. Check a pin against
  the live remote before trusting it — see
  [`docs/design/PIN_POLICY.md`](docs/design/PIN_POLICY.md).
- **`s_i2c_axi_*` is tied off**, so the CPUs cannot master TideLink's I2C sideband.
  Bridging it to a SoC initiator is unstarted.
- **Two upstream flist bugs are worked around, not fixed**: `tidelink_fpga.flist`
  compiles a dep and an override that disagree on a port list, and the SoC's
  generated flists emit `$(VAR)` where VCS needs `${VAR}`.

---

## Where to go next

| If you are… | Read |
|---|---|
| implementing this chiplet physically | [`docs/design/IMPLEMENTATION.md`](docs/design/IMPLEMENTATION.md), then [`docs/design/PHYSICAL_HANDOFF.md`](docs/design/PHYSICAL_HANDOFF.md) |
| new to backend ASIC flow | [`docs/tapeout/00-index.md`](docs/tapeout/00-index.md) — a from-scratch guide to this project's flow |
| bringing up the boards | [`docs/bringup/`](docs/bringup/) — KR260 runbook, board wiring, host tooling |
| writing or fixing RTL here | [`CONTRIBUTING.md`](CONTRIBUTING.md), then [`docs/verification/`](docs/verification/) |
| chasing the die-to-die wedge | [`docs/debug/`](docs/debug/) — start at its index for the supersession chain |
| looking up what an old session concluded | [`docs/history/`](docs/history/) — dated records and correspondence, **not** current reference |

The full documentation set is published from `docs/` with MkDocs
(`pip install -r docs/requirements.txt && mkdocs serve`).

---

*A joint work commissioned on behalf of SoC Labs, under Arm Academic Access
license. Copyright 2026, SoC Labs (www.soclabs.org).*
