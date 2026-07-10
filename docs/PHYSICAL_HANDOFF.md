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

`d2d_reset_o` is TideLink's die-to-die reset **output**. It is now a boundary
port. Whether it drives anything on this die is an integration decision that has
not been made.

> **Open:** the reset ordering between `sys_poresetn`, `sys_hresetn` and the far
> die's power-up has not been analysed. Two dies powering up in an arbitrary
> order is a genuine hazard for a source-synchronous link.

---

## 3. Boundary classes

The generator's chip-wrapper backend **refuses to emit** unless every SoC port is
classified as bonded / tied / open / terminated. A chiplet `chip_boundary` spec
does not exist yet — it is the first thing to write.

| Class | Ports |
|---|---|
| **PHY pads** (die-to-die) | `pad_clk_tx`, `pad_tx[7:0]`, `pad_clk_rx`, `pad_rx[7:0]` |
| **Straps** (per-die, set at the pad ring) | `role_strap_i`, `nego_priority_i[15:0]`, `mask_hs_bypass_i`, `apb_debug_unlock_i`, `puf_seed[15:0]`, `puf_ready` |
| **DFT** | `scan_mode`, `scan_asyncrst_ctrl`, `scan_clk`, `scan_shift`, `scan_in`, `scan_out`, plus the SoC's `sys_scanenable`, `sys_testmode` |
| **Status / observability** | `link_active_o`, `d2d_reset_o`, `role_is_master_o`, `role_locked_o`, `servo_locked_o`, `tl_ewma_credit_o[12:0]`, `tidechart_irq_o` |
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

## 5. Power intent

**Not done.** The SoC's UPF has no D2D domain — the generator residual reads
`domain ACCEL omitted`. A chiplet wants the link PHY in its own domain with
isolation and retention, so an unpowered link cannot corrupt the SoC's fabric.

This is gap **C3** in `nanosoc-multicore-system/docs/CHIPLET_INTEGRATION_PLAN.md`.

---

## 6. What has NOT been verified

Stated plainly so nobody builds on it:

- **No transaction has ever crossed a die boundary**, in simulation or on
  silicon. The SoC's D2D port is exercised against a memory model
  (`cocotb/soc_d2d_loopback`, 9/9, two tests mutation-verified). That is not the
  same thing.
- **The link has never been brought up in this integration.** Until the straps
  above were exposed, it could not be.
- **Unconfirmed:** whether Wlink's SERDES packetiser carries `addr[31:24]`
  end-to-end. The CAM makes the address `0x2D` on die A; if the packetiser
  windows the address, `0x2D` never arrives at die B. This is the single most
  load-bearing unknown in the data plane and it is a Chisel-generated black box.
- **No timing, area or power numbers** exist for the chiplet. The SoC alone
  closes at WNS +0.400 ns on a PYNQ-Z2 (xc7z020), which says nothing about ASIC.
- **No lint or CDC signoff** has been run on the integrated top.

---

## 7. Suggested first steps for the physical team

1. Write the chiplet `chip_boundary` + `pin_map`. The port gate will tell you
   the moment you miss one.
2. Run lint and SpyGlass CDC on `nanosoc_eth_chiplet`, not on the components.
3. Resolve the reset-ordering question in §2 before committing to a pad ring.
4. Add the D2D power domain (§5).
5. Decide the four straps in §3. They are cheap to get wrong and expensive to
   discover.
