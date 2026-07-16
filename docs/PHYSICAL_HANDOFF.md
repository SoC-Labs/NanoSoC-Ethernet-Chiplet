# Physical implementation handoff — `nanosoc_eth_chiplet`

What a physical implementation team needs to know that is **not** derivable from
the RTL alone. Everything here is verified against the source; where a claim is
unverified it says so.

**Entry point:** `make elab` builds the top under VCS with zero errors from a
clean tree. Every instance has all its ports connected exactly once.

---

## 1. Clock domains

Five clocks arrive at the chiplet boundary. Three of them are asynchronous to
each other and **the boundary between them is inside TideLink**, not in this
wrapper.

| Clock | Source | Drives | Notes |
|---|---|---|---|
| `sys_fclk` | board / PLL | the SoC's PRMU, which *generates* `sys_hclk` | the SoC exports `sys_hclk`/`sys_hresetn`/`sys_poresetn` as **outputs** |
| `sys_hclk` | **SoC output** | the whole AHB fabric, `chiplet_d2d_decode`, both APB bridges, `tidelink_top.hclk`, `tidechart_shim.clk` | not a boundary input — do not drive it |
| `rtc_clk` | board | SoC RTC / PTP | |
| `rmii_ref_clk` | ethernet PHY | RMII, 50 MHz | |
| `user_ref_clk` | board | Wlink PLL reference | **asynchronous to `sys_hclk`** |
| `pad_clk_rx` | **the far die** | TideLink's recovered RX datapath | **source-synchronous, asynchronous to everything** |
| `idelay_ref_clk` | board | 200 MHz `IDELAYCTRL` | **FPGA only.** On ASIC, `USE_IDELAY=0` makes the delay path a bit-exact passthrough — tie this off. |

`phc_clk` and `phc_resetn` on `tidelink_top` are tied to `sys_hclk`/`sys_hresetn`
in this integration. If the PHC is ever given its own clock, that becomes a real
CDC and this wrapper must change.

### The CDC crossings you own
- **`pad_clk_rx` → `sys_hclk`** — inside TideLink (`cdc_tear`, `phc_cdc`). TideLink
  ships a SpyGlass CDC signoff (`make -C cdc cdc` in that repo). Run it on the
  configuration you tape out, not on TideLink's defaults.
- **`user_ref_clk` → `sys_hclk`** — inside the Wlink chiplet controller.
- The wrapper itself introduces **no new CDC**: the decoder, both APB bridges and
  the TideChart shim are all in `sys_hclk`.

---

## 2. Reset topology

`poresetn` and `hresetn` are **not the same reset** and TideLink distinguishes
them. In this wrapper:

- `tidelink_top.poresetn` ← SoC `sys_poresetn` (power-on)
- `tidelink_top.hresetn` ← SoC `sys_hresetn` (AHB)
- `tidechart_shim.resetn` ← SoC `sys_hresetn`

`d2d_reset_o` is **not a reset, and is tied low by construction** — it is Wlink's RX
`in_error_state`, half of a cross-die "stop transmitting" backpressure handshake. It
cannot assert because the ECC syndrome checker is a deliberate, documented bring-up
bypass (`WlinkEccSyndrome.v:306-308` hardwires `corrupted = 1'h0`). It drives nothing,
and as of 2026-07-16 it is not a pad. **Implication for sign-off: this link runs with no
header ECC protection** (payload CRC is unaffected). See **STATUS_REGISTERS.md §4**;
raised upstream — the fix is a syndrome-polynomial audit, not a code change.

> **Open:** the reset ordering between `sys_poresetn`, `sys_hresetn` and the far
> die's power-up has not been analysed. Two dies powering up in an arbitrary
> order is a genuine hazard for a source-synchronous link.

---

## 3. Boundary classes

The generator's chip-wrapper backend **refuses to emit** unless every SoC port is
classified as bonded / tied / open / terminated. A chiplet `chip_boundary` spec
does not exist yet — it is the first thing to write.

The spec now exists: `sys_desc/chip_boundary/nanosoc_eth_chiplet.yaml`, checked by
`make chip-boundary` and emitted by `make chip-wrapper`.

```
  RTL ports  : 111  (377 bits)
  classified : 111  (bonded 59 / tied 21 / open 31)
  pads       : 46 pad cells
```

The check is not decorative. It was mutation-tested: dropping a port from the
spec, swapping `in:`/`out:` on the MDIO bidir pad, and mis-sizing `d2d_tx` from 8
to 4 bits each fail with the offending name. The generated wrapper
(`nanosoc_eth_chiplet_chip.v`, 59 chip nets) elaborates under VCS with zero
errors and no unconnected port on the chiplet instance.

> **Changed 2026-07-16: 50 → 46 pad cells.** The four link-status pads were unbonded;
> all four are register-readable over the TideLink config APB, which the SWJ-DP reaches
> independently of CPU state. See **STATUS_REGISTERS.md** and PIN_MAP.md §4c. Two of
> them could never have carried information anyway: `link_active` is the same net as
> `role_locked`, and `d2d_reset` is tied low by construction.

| Class | Ports |
|---|---|
| **PHY pads** (die-to-die) | `pad_clk_tx`, `pad_tx[7:0]`, `pad_clk_rx`, `pad_rx[7:0]` |
| **Straps** (per-die, set at the pad ring) | `role_strap_i`, `nego_priority_i[15:0]`, `mask_hs_bypass_i`, `apb_debug_unlock_i`, `puf_seed[15:0]`, `puf_ready` |
| **DFT** | `scan_mode`, `scan_asyncrst_ctrl`, `scan_clk`, `scan_shift`, `scan_in`, `scan_out`, plus the SoC's `sys_scanenable`, `sys_testmode` |
| **Status / observability** — **none of these is a pad** (see STATUS_REGISTERS.md) | `link_active_o`, `d2d_reset_o`, `role_is_master_o`, `role_locked_o`, `servo_locked_o`, `tl_ewma_credit_o[12:0]`, `tidechart_irq_o` |
| **I²C sideband** (open-drain) | `i2c_scl_i/o/t`, `i2c_sda_i/o/t` |
| **SoC pads** | everything else — RMII, MDIO, UARTs, QSPI, SPI, HOSTIO4, DAP/SWD, RTC/PTP |

The straps and DFT ports were tie-offs until recently. They are ports now
precisely because a chiplet cannot bring its link up without them, and because
a tied-off scan chain is a chip with no scan chain.

### Straps that must be set, and are not defaulted for you

- **`nego_priority_i`** — auto-negotiation priority, normally OTP or die UID.
  **Two dies both presenting `0` have no tiebreak.**
- **`role_strap_i`** — link role. TideLink's guide: natural autoneg never
  converges without latching `ROLE_CFG` bit[1].
- **TideChart `DEVICE_CLASS`** — parameter, defaults to `16'h0001`, which
  TideChart's README defines as the value that *reliably wins* the root election.
  **Every chiplet therefore boots claiming to be the host complex.** Strap the
  dies differently or the election is a coin-flip on the LFSR.
- **`NEGO_CFG_RESET`** — TideLink's RTL default is `7'h00` (autoneg off,
  SW-driven), *not* the `7'h61` its `INTEGRATION_GUIDE.md` §4.3 still claims.
  With `7'h00` the autoneg FSM parks in `ST_BYPASS`. Decide this deliberately.

---

## 4. Hard architectural constraints

These are properties of the design, not of the current implementation. A
physical team should know them because they bound what can change late.

### 4.1 The SoC's bus matrix is full — 16/16 slave slots
`d2d` took the sixteenth. Any new top-level target must sub-decode behind an
existing slot (the `ctrl_dbg_group` pattern) or displace something.

### 4.2 The peer aperture reaches exactly ONE remote 16 MB region
TideLink's address translator is an **8-rule CAM that matches only
`addr[31:24]`** and replaces the same byte; `addr[23:0]` passes through raw. The
chiplet's peer aperture is all of `0x2F`, i.e. one upper byte — so one rule, one
remote 16 MB region.

Die A therefore **cannot** reach both `shared_sram_0` (`0x2D`) and
`ipc_mailbox_0` (`0x23`) on die B through the aperture. The aperture is mapped
to `shared_sram_0`; the mailbox is reached by TideLink's **native doorbell**
(`DOORBELL` → the peer's `doorbell_irq`, which the SoC maps to `d2d_irq[0]` →
CPU0 NVIC `IRQ[10]`), not by a remote AHB write.

Consequence: `ipc_mailbox_0` in the SoC's `d2d_m` inbound target list is
**currently unreachable**. It is harmless, and it becomes reachable if the D2D
window is ever widened. See `docs/PEER_APERTURE_PROGRAMMING.md`.

### 4.3 The TX aperture is gated on `link_active`
A write to `0x2E000000` with the link down takes a clean two-cycle AHB ERROR
instead of hanging the SoC's matrix — TideLink's own guide calls this a wedge
hazard. The gate is in `chiplet_d2d_decode`, because the SoC has already
committed the transfer by the time it leaves `d2d_ahb_m`. Proven by
`verif/chiplet_d2d_decode/`, which also proves the APB bring-up region stays
reachable while the link is down.

### 4.4 `servo_locked` reports the wrong servo
The PHC takes one lock-status input for both servo sources and does not export
`servo_src_sel`. A chiplet running `SRC_SEL=0` (the reset default, the D2D
source) reports the **ethernet HA1588** servo's lock. `servo_locked_o` here is
TideLink's own servo lock, which is a different signal. See `D2D_PORT.md` §6f.

---

## 4.5 The filelist must not depend on tool declaration order

`tidelink/flists/tidelink_fpga.flist` at the pinned commit compiles the `deps/`
copy of `WlinkGenericFCReplayAddrSync_18` (no `obs_*` ports) **and** the local
override `WlinkGenericFCReplayV2_13`, which drives those ports. As shipped it
gives 7× `Error-[UPIMI-E]`.

The tempting fix is to append TideLink's own override and rely on VCS's "last
declaration wins". **Do not.** That makes the effective netlist a property of the
tool rather than of the filelist:

| Tool | Behaviour on a duplicate module |
|---|---|
| VCS | last declaration wins → you get the override |
| Verilator | duplicate module is an error |
| some Xcelium / Icarus modes | **first** declaration wins → you get the `deps/` copy |

The override is not cosmetic. It carries the **a2l ACK-ptr reset-skew fix**
(async-assert / sync-deassert of `w_reset` into `r_clk`). Its own header records
that an idealised single-clock simulation "resolves the demets cleanly and never
exposes it" — so **a green simulation does not prove the fix is even present**.
Lose it on silicon and it returns as the a2l 6-word / false-FULL wedge: the link
delivers a handful of writes and stops.

`flist/resolve_tidelink_flist.py` therefore **removes** the shadowed `deps/`
module and appends the override, leaving exactly one definition for any tool.
Verified: the resolved filelist contains one `AddrSync_18` (the override), and
the duplicate-definition warning on it is gone.

Audited: `AddrSync_18` was the **only** shadowed module. Every other file in
`src/rtl/local_overrides/` is compiled exactly once, from the override, with no
`deps/` twin. The eleven duplicate-definition warnings that remain are the *same
file* listed by two component flists (`cmsdk_ahb_to_apb.v`, `cmsdk_fpga_sram.v`,
the XHB500 helpers) — identical definitions, benign.

> **Upstream fix wanted:** swap the `deps/` path for the override in
> `tidelink_fpga.flist`, as its siblings `tidelink_fpga_v2` and
> `tidelink_a2l_replay_cdc` already do. Then delete the resolver.

---

## 5. Power intent

**Not done.** The SoC's UPF has no D2D domain — the generator residual reads
`domain ACCEL omitted`. A chiplet wants the link PHY in its own domain with
isolation and retention, so an unpowered link cannot corrupt the SoC's fabric.

This is gap **C3** in `nanosoc-multicore-system/docs/CHIPLET_INTEGRATION_PLAN.md`.

---

## 6. What has NOT been verified

Stated plainly so nobody builds on it:

- **No transaction has ever crossed a die boundary in THIS integration**, in
  simulation or on silicon. The SoC's D2D port is exercised against a memory
  model (`cocotb/soc_d2d_loopback`, 9/9, two tests mutation-verified). That is
  not the same thing.

  TideLink's own `tidelink_top_pair` env does pass 11/11 on the pinned commit,
  including the slave→master credit-return path (`test_04`) and sustained
  bilateral traffic past the 31-deep credit ring (`test_10`). So the link's
  logical datapath is proven between two `tidelink_top`s — just not between two
  chiplets. Note `test_06` is a weak guard (its assertion is also satisfied by
  bring-up residual); gate on `test_04` and `test_10`.

- **Simulation is blind to the reset-skew bug** the `AddrSync_18` override fixes
  (§4.5). Those green sims would be green with or without it. On silicon the
  exposure is on the a2l (TX) path — the same direction a chiplet uses to write
  the far die. This needs bench validation or a multi-clock / reset-skew
  testbench; it is not covered by anything that exists today.
- **The link has never been brought up in this integration.** Until the straps
  above were exposed, it could not be.
- ~~**Unconfirmed:** whether Wlink's SERDES packetiser carries `addr[31:24]`
  end-to-end.~~ **RESOLVED 2026-07-10: it does.** The address is packed as a
  64-bit field (36 significant bits) at
  `deps/axi-chiplet-controller/logical/wlink/AXI4ToWlink.v:395-399`, and the far
  die reconstructs it *from the received packet* (`l2a_data`), not from a base
  register (`AXI4ToWlink.v:401,450`). So `ahb_mng_haddr[31:24]` on die B reads
  `0x2D`. The Chisel (`AXI.scala:442-471`) agrees with the generated Verilog, and
  `AXI4ToWlink` is not shadowed by any local override. Note the peer aperture
  uses the **AXI** path (`WlinkGenericFCSM` on the AW channel) — it is *not* the
  FIFO/returner native path the doorbell uses, and the
  `WlinkGenericFCReplayAddrSync_18` reset-skew hazard is on the a2l replay path,
  not this one. To re-confirm in the pair sim, probe far-die
  `ahb_mng_haddr[31:24]` against post-CAM `ahb_sub_haddr[31:24]`.
- ~~**A combinational cycle on the peer aperture's `HREADY`.**~~ **FIXED
  2026-07-10.** `nanosoc_eth_chiplet.sv` fed `chiplet_d2d_decode`'s muxed `hready`
  back into TideLink's `ahb_sub_hready`, whose `ahb_sub_hreadyout` reads it
  combinationally (`tidelink_top.sv:1119,1169`) — back-to-back peer transfers
  oscillated. The decoder now exports a registered `dph_peer` and the top drives
  `hready_to_peer = dph_peer ? 1'b1 : d2d_ahb_m_hready`. Guarded by
  `verif/chiplet_d2d_decode/tb_hready_loop.sv`, mutation-tested. Audited: `ahb_sub`
  was the only TideLink port with the dependence. See `docs/D2D_HREADY_LOOP.md`.
  **A lint/CDC signoff on the integrated top is still owed** — it would have found
  this, and may find more.
- **No timing, area or power numbers** exist for the chiplet. The SoC alone
  closes at WNS +0.400 ns on a PYNQ-Z2 (xc7z020), which says nothing about ASIC.
- **No lint or CDC signoff** has been run on the integrated top.

---

## 7. Suggested first steps for the physical team

1. **Read the boundary spec and disagree with it.** It is written, checked and
   emits a wrapper that elaborates — but its *contents* are my judgement, not
   yours. In particular §3's four straps, and the four decisions recorded at the
   head of the YAML. `make chip-boundary` tells you the moment a change breaks
   coverage.
2. Write the `pin_map` (which pad cell, which side, which power domain). The
   boundary spec is tech-independent; the pin map is not.
3. Run lint and SpyGlass CDC on `nanosoc_eth_chiplet`, not on the components.
4. Resolve the reset-ordering question in §2 before committing to a pad ring.
5. Add the D2D power domain (§5).

### Getting the source

```sh
git clone https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet.git
cd NanoSoC-Ethernet-Chiplet
./scripts/bootstrap.sh
make chip-boundary        # sanity: python only, no EDA tools needed
```

The three components live on **SoTON's internal GitLab**, `git.soton.ac.uk`. They
are reached over **HTTPS**, so no SSH key is required — but you still need read
access to that GitLab, and it is not public. If the physical team is external,
mirror the three repos and repoint `.gitmodules`.

Do not use `git clone --recursive`: one submodule *inside* TideLink
(`deps/tidelink-phy`) is still declared over SSH at the commit we pin, and the
recursive clone dies there. `bootstrap.sh` rewrites that URL for the duration of
the fetch and then verifies nothing was skipped. Expect **42 submodules, 8 levels
deep**. `deps/tidelink-phy` contributes zero files to our build — it is the
unused PHY-v2 scaffold, and a duplicate of `deps/tidelink-gpio-phy` — so if your
mirror omits it, drop it from TideLink's `.gitmodules` rather than mirroring it.

Nothing in this repo is Arm-licensed IP; the vendor trees are referenced only
through `$CMSDK_DIR` / `$ARM_IP_LIBRARY_PATH` at build time.
