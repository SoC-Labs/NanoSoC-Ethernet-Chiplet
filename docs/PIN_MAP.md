# Pad / pin map — `nanosoc_eth_chiplet_chip`

**Status: TEMPLATE. This is the physical-implementation team's document to fill in.**

This file turns the machine-checked bonded-pad list into a structured pin map. The
columns that are *derivable from the RTL and the boundary spec* are pre-filled. The
columns that are *tech-specific choices only the physical team can make* are marked
`[TEAM DECISION]` and left blank on purpose.

- **Source of truth:** `sys_desc/chip_boundary/nanosoc_eth_chiplet.yaml`, validated by
  `make chip-boundary` (`scripts/check_chip_boundary.py`). That check cross-checks every
  bonded net's direction and width against the real RTL port list in
  `src/rtl/nanosoc_eth_chiplet.sv` and refuses to emit if anything is unclassified.
- **This document is downstream of that spec.** It does not add or remove pads. If you
  need to change what is bonded, change the YAML (it is reviewable) and re-run
  `make chip-boundary` — then reconcile this table.
- **Do not** invent pad-cell library names or pin/ball numbers here. Those belong to the
  physical team and the chosen technology; this template only reserves the columns.

---

## 0. Cross-check against `make chip-boundary`

The pad count below must stay in lock-step with the boundary checker. If a future port
change breaks the count, this line makes it visible.

```
$ make chip-boundary
  RTL ports  : 111  (377 bits)
  classified : 111  (bonded 59 / tied 21 / open 31 / terminated 0)
  pads       : 46 pad cells
  OK — every port accounted for exactly once
```

| Quantity | Expected | This document |
|---|---|---|
| Total RTL top ports | 111 | (all classified in the YAML, not all bonded) |
| Total port bits | 377 | — |
| **Bonded pad cells** | **46** | **46 rows across the tables below** |
| Bonded inner ports | 59 | 6 bidir×3 + 1 tri-out×2 + 39 single = 59 |
| Tied inputs (not bonded) | 21 | see §7 |
| Open outputs (not bonded) | 31 | see §7 |

> If `make chip-boundary` ever prints anything other than **46 pad cells / bonded 59**,
> a port was added, removed or re-classified. Update this map before tape-out and re-run
> the count.

> **Changed 2026-07-16: 50 → 46 pad cells.** The four link-status pads
> (`link_active`, `role_is_master`, `role_locked`, `d2d_reset`) were unbonded — all
> four are already readable over the TideLink config APB, which the SWJ-DP reaches
> independently of CPU state. See §4c and **docs/STATUS_REGISTERS.md**.

---

## 1. How to read the columns

| Column | Meaning |
|---|---|
| **Pad name** | Chip-level port name from the YAML (`chip_port`). Bus pads are one row; the width is in the Width column. |
| **Dir** | Pad kind: `In` (input), `Out` (output), `Bidir` (in/out/oe triplet), `Tri-out` (output + OE). |
| **Width** | Bits on this pad. A bus like `d2d_tx` is **8 physical pads sharing one pad-cell type** — the team still lays out 8 balls/bumps. |
| **Class** | Boundary class: `PHY` (die-to-die), `strap` (per-die), `DFT`, `status`, `I2C` (open-drain sideband), `SoC-func`. |
| **Sugg. domain** | *Suggested* functional power domain (see legend below). **Proposal only** — the UPF has no D2D domain yet (PHYSICAL_HANDOFF §5, gap C3). |
| **Pad cell type** | `[TEAM DECISION]` — pick per technology library (drive strength, level, slew, ESD, OD for I2C). |
| **Die side** | `[TEAM DECISION]` — which edge / which quadrant of the pad ring. |
| **Notes** | Inner RTL net(s), OE polarity, and anything load-bearing. |

**Suggested-domain legend** (grounded in RESET_ORDERING.md / PHYSICAL_HANDOFF.md; all are
proposals to ratify, not UPF facts):

| Code | Meaning | Evidence |
|---|---|---|
| `AON-CLK` | Always-on reference clock/reset — must be stable *before* `poresetn` deasserts. | RESET_ORDERING §3.1 |
| `AON-LINK` | Always-on link config/status — feeds the autoneg + I²C-slave config regs held by `poresetn`; `role_locked` survives a warm `hresetn`. | RESET_ORDERING §1, §3.3 |
| `D2D-PHY` | Dedicated die-to-die link-PHY domain — **wants its own domain with isolation + retention** so an unpowered link cannot corrupt the SoC fabric. **Does not exist in the UPF yet.** | PHYSICAL_HANDOFF §5 (gap C3) |
| `SoC-CORE` | SoC functional I/O — logic is in the `sys_hclk` / `sys_hresetn` domain. | PHYSICAL_HANDOFF §1 |

> **Every** pad additionally has a **pad-ring I/O supply / voltage** that is a separate
> `[TEAM DECISION]` (captured under Pad cell type). The `Sugg. domain` column is about the
> *functional* domain (isolation/retention intent), not the I/O rail.

---

## 2. Clocks & reset — 5 pads

| Pad name | Dir | Width | Class | Sugg. domain | Pad cell type | Die side | Notes |
|---|---|---|---|---|---|---|---|
| `sys_fclk` | In | 1 | SoC-func | `AON-CLK` | `[TEAM DECISION]` | `[TEAM DECISION]` | inner `sys_fclk`; free-running system clock, feeds SoC PRMU which *generates* `sys_hclk`. Must be stable before `poresetn` releases. |
| `nrst` | In | 1 | SoC-func | `AON-CLK` | `[TEAM DECISION]` | `[TEAM DECISION]` | inner `sys_sysresetn`; **active-low** external system reset. |
| `rtc_clk` | In | 1 | SoC-func | `AON-CLK` | `[TEAM DECISION]` | `[TEAM DECISION]` | inner `rtc_clk`; RTC / PTP reference. |
| `rmii_ref_clk` | In | 1 | SoC-func | `AON-CLK` | `[TEAM DECISION]` | `[TEAM DECISION]` | inner `rmii_ref_clk`; 50 MHz RMII reference from the PHY. |
| `user_ref_clk` | In | 1 | SoC-func | `AON-CLK` | `[TEAM DECISION]` | `[TEAM DECISION]` | inner `user_ref_clk`; Wlink PLL reference. **Asynchronous to `sys_hclk`** (CDC inside the Wlink controller). |

---

## 3. Die-to-die PHY — 4 pads  (see §6a for the timing constraint)

| Pad name | Dir | Width | Class | Sugg. domain | Pad cell type | Die side | Notes |
|---|---|---|---|---|---|---|---|
| `d2d_clk_tx` | Out | 1 | PHY | `D2D-PHY` | `[TEAM DECISION]` | `[TEAM DECISION]` | inner `pad_clk_tx`; **this die's forwarded TX clock**. Source-synchronous with `d2d_tx`. |
| `d2d_tx` | Out | 8 | PHY | `D2D-PHY` | `[TEAM DECISION]` | `[TEAM DECISION]` | inner `pad_tx[7:0]`; 8 TX lanes. Length/skew-match to `d2d_clk_tx`. |
| `d2d_clk_rx` | In | 1 | PHY | `D2D-PHY` | `[TEAM DECISION]` | `[TEAM DECISION]` | inner `pad_clk_rx`; **the FAR die's forwarded clock**. Source-synchronous, **asynchronous to everything on this die**; only toggles when the far die is powered and transmitting. |
| `d2d_rx` | In | 8 | PHY | `D2D-PHY` | `[TEAM DECISION]` | `[TEAM DECISION]` | inner `pad_rx[7:0]`; 8 RX lanes recovered against `d2d_clk_rx`. Length/skew-match to `d2d_clk_rx`. |

---

## 4. Die-to-die sideband, straps & status

### 4a. I²C sideband (open-drain) — 2 pads  (see §6c)

| Pad name | Dir | Width | Class | Sugg. domain | Pad cell type | Die side | Notes |
|---|---|---|---|---|---|---|---|
| `i2c_scl` | Bidir | 1 | I2C | `AON-LINK` | `[TEAM DECISION]` — **open-drain** | `[TEAM DECISION]` | inner `i2c_scl_i` / `i2c_scl_o` / `i2c_scl_t`. **OE active-low** (`_t`=1 ⇒ Hi-Z). Needs external pull-up; pad must never drive high. |
| `i2c_sda` | Bidir | 1 | I2C | `AON-LINK` | `[TEAM DECISION]` — **open-drain** | `[TEAM DECISION]` | inner `i2c_sda_i` / `i2c_sda_o` / `i2c_sda_t`. **OE active-low** (`_t`=1 ⇒ Hi-Z). Needs external pull-up. |

### 4b. Link bring-up straps (per-die) — 3 pads  (see §6b)

| Pad name | Dir | Width | Class | Sugg. domain | Pad cell type | Die side | Notes |
|---|---|---|---|---|---|---|---|
| `role_strap` | In | 1 | strap | `AON-LINK` | `[TEAM DECISION]` | `[TEAM DECISION]` | inner `role_strap_i`; link role select. **MUST differ per die** — see §6b. |
| `mask_hs_bypass` | In | 1 | strap | `AON-LINK` | `[TEAM DECISION]` | `[TEAM DECISION]` | inner `mask_hs_bypass_i`; opens the SW role-lock path. **Bench strap — interlock or drop for silicon** (RESET_ORDERING §3.3). |
| `apb_debug_unlock` | In | 1 | strap | `AON-LINK` | `[TEAM DECISION]` | `[TEAM DECISION]` | inner `apb_debug_unlock_i`; debug strap, opens the SW role-lock path. **Bench strap — interlock or drop for silicon.** |

### 4c. Link status / observability — 0 pads (was 4; unbonded 2026-07-16)

**There are no link-status pads.** All four are read over the TideLink config APB
instead. The full address table, bit positions and traps are in
**[STATUS_REGISTERS.md](STATUS_REGISTERS.md)**; the short form:

| Former pad | Now read at | Why it is not a pad |
|---|---|---|
| `link_active` | `0x2E032084` bit[1] | **Not independent status.** `tidelink_top.sv:2308` is `assign link_active = role_locked_o;` — the same net as `role_locked`. Two pads carried one bit. Its TX-aperture gating is an *internal* path (`tc_link_active` → `u_d2d_decode`) and is unaffected. |
| `role_is_master` | `0x2E032084` bit[0] | Register bit is `role_effective` — the **inverse** (0 = master). |
| `role_locked` | `0x2E032084` bit[1] | Same bit as `link_active`. |
| `d2d_reset` | `0x2E030234` bit[2] | **Tied low by construction** — the pad could never have asserted. See STATUS_REGISTERS.md §4. |

**Why this is safe.** The SWJ-DP's AHB-AP is a full bus initiator (matrix initiator
#3) whose decoder maps `0x2E000000-0x2FFFFFFF` unconditionally, and it runs on
free-running `SYS_HCLK` — `slcorem0p_prmu.v:91-93`: *"System HCLK needs to be
assigned to System Free-running Clock so other managers can still access bus when
CPU is sleeping."* So an external SWD debugger reads these with both cores halted or
sleeping, and in the cold-boot state where CPU0 is held in reset. The config window
at `0x2E03` is **not** gated by `link_active` (only the TX aperture at `0x2E00` is),
so it reads correctly with the link down — which is exactly when it is needed.

**Accepted gaps** (neither costs real information, but be aware):

1. With `sys_sysresetn` asserted the SWJ-DP is itself in reset, so the registers are
   unreadable where a pad would still be observable. Information-free in practice:
   `role_lock_reg` is forced to its POR value in that state anyway.
2. `dap_swj_enable = 0` — a **non-active die in a multi-chiplet package has no SWD at
   all**, so with its link down it would have no link-status visibility by any route.
   Not a concern while `chip.v` ties `dap_swj_enable = 1'b1`. **If a package ever
   straps a die 0, revisit this decision** — that is the one case where a bonded
   `role_locked` would earn its pad.

---

## 5. SoC functional pads

### 5a. CoreSight SWJ-DP (SWD / JTAG) — 5 pads

| Pad name | Dir | Width | Class | Sugg. domain | Pad cell type | Die side | Notes |
|---|---|---|---|---|---|---|---|
| `swd_clk` | In | 1 | SoC-func | `SoC-CORE` | `[TEAM DECISION]` | `[TEAM DECISION]` | inner `dap_swclktck`. |
| `swd_dio` | Bidir | 1 | SoC-func | `SoC-CORE` | `[TEAM DECISION]` | `[TEAM DECISION]` | inner `dap_swditms` / `dap_swdo` / `dap_swdoen`. **OE active-high.** |
| `jtag_tdi` | In | 1 | SoC-func | `SoC-CORE` | `[TEAM DECISION]` | `[TEAM DECISION]` | inner `dap_tdi`. |
| `jtag_tdo` | Tri-out | 1 | SoC-func | `SoC-CORE` | `[TEAM DECISION]` | `[TEAM DECISION]` | inner `dap_tdo` + OE `dap_ntdoen`. **OE active-low.** |
| `jtag_ntrst` | In | 1 | SoC-func | `SoC-CORE` | `[TEAM DECISION]` | `[TEAM DECISION]` | inner `dap_ntrst`; active-low JTAG reset. |

### 5b. DFT — 8 pads

| Pad name | Dir | Width | Class | Sugg. domain | Pad cell type | Die side | Notes |
|---|---|---|---|---|---|---|---|
| `scan_mode` | In | 1 | DFT | `SoC-CORE` | `[TEAM DECISION]` | `[TEAM DECISION]` | inner `scan_mode`; test-only. |
| `scan_asyncrst_ctrl` | In | 1 | DFT | `SoC-CORE` | `[TEAM DECISION]` | `[TEAM DECISION]` | inner `scan_asyncrst_ctrl`; test-only. |
| `scan_clk` | In | 1 | DFT | `SoC-CORE` | `[TEAM DECISION]` | `[TEAM DECISION]` | inner `scan_clk`; scan-shift clock. |
| `scan_shift` | In | 1 | DFT | `SoC-CORE` | `[TEAM DECISION]` | `[TEAM DECISION]` | inner `scan_shift`. |
| `scan_in` | In | 1 | DFT | `SoC-CORE` | `[TEAM DECISION]` | `[TEAM DECISION]` | inner `scan_in`; scan-chain input. |
| `scan_out` | Out | 1 | DFT | `SoC-CORE` | `[TEAM DECISION]` | `[TEAM DECISION]` | inner `scan_out`; scan-chain output. |
| `sys_scanenable` | In | 1 | DFT | `SoC-CORE` | `[TEAM DECISION]` | `[TEAM DECISION]` | inner `sys_scanenable`. |
| `sys_testmode` | In | 1 | DFT | `SoC-CORE` | `[TEAM DECISION]` | `[TEAM DECISION]` | inner `sys_testmode`. |

### 5c. UARTs — 4 pads

| Pad name | Dir | Width | Class | Sugg. domain | Pad cell type | Die side | Notes |
|---|---|---|---|---|---|---|---|
| `uart_rxd` | In | 1 | SoC-func | `SoC-CORE` | `[TEAM DECISION]` | `[TEAM DECISION]` | inner `uart_rxd`; network_core (CPU0) UART. |
| `uart_txd` | Out | 1 | SoC-func | `SoC-CORE` | `[TEAM DECISION]` | `[TEAM DECISION]` | inner `uart_txd`; network_core (CPU0) UART. |
| `cpu1_uart_rxd` | In | 1 | SoC-func | `SoC-CORE` | `[TEAM DECISION]` | `[TEAM DECISION]` | inner `chip_core_uart_rxd`; chip_core (CPU1) UART. |
| `cpu1_uart_txd` | Out | 1 | SoC-func | `SoC-CORE` | `[TEAM DECISION]` | `[TEAM DECISION]` | inner `chip_core_uart_txd`; chip_core (CPU1) UART. |

### 5d. Ethernet RMII + MDIO — 6 pads

| Pad name | Dir | Width | Class | Sugg. domain | Pad cell type | Die side | Notes |
|---|---|---|---|---|---|---|---|
| `phy_rmii_txd` | Out | 2 | SoC-func | `SoC-CORE` | `[TEAM DECISION]` | `[TEAM DECISION]` | inner `rmii_txd[1:0]`; RMII TX data. |
| `phy_rmii_tx_en` | Out | 1 | SoC-func | `SoC-CORE` | `[TEAM DECISION]` | `[TEAM DECISION]` | inner `rmii_tx_en`. |
| `phy_rmii_rxd` | In | 2 | SoC-func | `SoC-CORE` | `[TEAM DECISION]` | `[TEAM DECISION]` | inner `rmii_rxd[1:0]`; RMII RX data. |
| `phy_rmii_crs_dv` | In | 1 | SoC-func | `SoC-CORE` | `[TEAM DECISION]` | `[TEAM DECISION]` | inner `rmii_crs_dv`. |
| `phy_mdc` | Out | 1 | SoC-func | `SoC-CORE` | `[TEAM DECISION]` | `[TEAM DECISION]` | inner `mdc_pad_o`; MDIO management clock. |
| `mdio` | Bidir | 1 | SoC-func | `SoC-CORE` | `[TEAM DECISION]` | `[TEAM DECISION]` | inner `md_pad_i` / `md_pad_o` / `md_padoe_o`. **OE active-high.** Typically needs external pull-up. |

### 5e. QSPI flash — 3 pads

| Pad name | Dir | Width | Class | Sugg. domain | Pad cell type | Die side | Notes |
|---|---|---|---|---|---|---|---|
| `qspi_sclk` | Out | 1 | SoC-func | `SoC-CORE` | `[TEAM DECISION]` | `[TEAM DECISION]` | inner `qspi_sclk`. |
| `qspi_ncs` | Out | 1 | SoC-func | `SoC-CORE` | `[TEAM DECISION]` | `[TEAM DECISION]` | inner `qspi_csn`; active-low chip select. |
| `qspi_io` | Bidir | 4 | SoC-func | `SoC-CORE` | `[TEAM DECISION]` | `[TEAM DECISION]` | inner `qspi_io_i` / `qspi_io_o` / `qspi_io_e` (4-bit). **OE active-high**, per-bit. |

### 5f. PL022 SPI master — 4 pads

| Pad name | Dir | Width | Class | Sugg. domain | Pad cell type | Die side | Notes |
|---|---|---|---|---|---|---|---|
| `spi_sclk` | Out | 1 | SoC-func | `SoC-CORE` | `[TEAM DECISION]` | `[TEAM DECISION]` | inner `spi_sclk`. |
| `spi_mosi` | Out | 1 | SoC-func | `SoC-CORE` | `[TEAM DECISION]` | `[TEAM DECISION]` | inner `spi_mosi`. |
| `spi_miso` | In | 1 | SoC-func | `SoC-CORE` | `[TEAM DECISION]` | `[TEAM DECISION]` | inner `spi_miso`. |
| `spi_ss` | Out | 3 | SoC-func | `SoC-CORE` | `[TEAM DECISION]` | `[TEAM DECISION]` | inner `spi_ss[2:0]`; 3 slave selects. |

### 5g. HOSTIO4 host-access link — 1 pad

| Pad name | Dir | Width | Class | Sugg. domain | Pad cell type | Die side | Notes |
|---|---|---|---|---|---|---|---|
| `hostio4` | Bidir | 7 | SoC-func | `SoC-CORE` | `[TEAM DECISION]` | `[TEAM DECISION]` | inner `hostio4_p1_in` / `hostio4_p1_out` / `hostio4_p1_outen` (7-bit). **OE active-high.** |

### 5h. PTP 1PPS — 1 pad

| Pad name | Dir | Width | Class | Sugg. domain | Pad cell type | Die side | Notes |
|---|---|---|---|---|---|---|---|
| `phc_pps_out` | Out | 1 | SoC-func | `SoC-CORE` | `[TEAM DECISION]` | `[TEAM DECISION]` | inner `phc_pps_out`; 1-pulse-per-second output. |

---

## 6. Call-outs the physical team must not miss

### 6a. Die-to-die PHY is source-synchronous

The four PHY pads in §3 are **two source-synchronous groups**, and they are the only
pads with a hard clock-to-data matching requirement:

- **TX group:** `d2d_clk_tx` forwards *this die's* clock alongside `d2d_tx[7:0]`.
- **RX group:** `d2d_clk_rx` is *the far die's* forwarded clock, recovering `d2d_rx[7:0]`.
  It is **asynchronous to everything on this die** and only toggles when the far die is
  powered and transmitting (RESET_ORDERING §2).

Constraints (RESET_ORDERING §2, §3.2; PHYSICAL_HANDOFF §1):

1. **Length/skew-match each clock to its 8 data lanes** so clock-data skew stays inside
   the lane-checker sampling window. Treat `{d2d_clk_tx, d2d_tx[7:0]}` and
   `{d2d_clk_rx, d2d_rx[7:0]}` as matched bundles when placing pads and routing bumps.
2. **The recovered-RX-clock reset has exactly one release path: `role_locked`**, async-
   assert / sync-deassert *on `d2d_clk_rx`*. **The pad ring must NOT add any independent,
   power-on-driven early release** of the RX-domain reset — doing so re-opens the
   metastable-capture window that shows up as the silicon-only "slave fails to converge"
   30%-of-deploys signature.
3. The CDC `pad_clk_rx → sys_hclk` lives inside TideLink. Run TideLink's SpyGlass CDC
   signoff on the *taped-out* configuration, not on defaults (PHYSICAL_HANDOFF §1).
4. The D2D PHY wants its **own power domain with isolation + retention** so an unpowered
   link cannot corrupt the SoC fabric — this domain does **not** exist in the UPF yet
   (PHYSICAL_HANDOFF §5, gap C3). Sequencing rule: clocks stable → `poresetn` → `hresetn`,
   never `hresetn` first (RESET_ORDERING §3.1, §5).

### 6b. Straps that MUST differ per die

Two dies are physically identical; the pad ring / OTP is what makes them distinguishable.
Get this wrong and the auto-negotiation root election is a coin-flip on an LFSR that may
never converge (RESET_ORDERING §3.4). Per PHYSICAL_HANDOFF §3:

| Differentiator | Kind in *this* wrapper | What the team must do |
|---|---|---|
| `role_strap` (`role_strap_i`) | **Bonded pad** (§4b) | Strap **opposite values** on the two dies. This is currently the *only* per-die differentiator that is a real pad. |
| `nego_priority_i[15:0]` | **TIED `16'h0001` in the wrapper — NOT a pad** | Two dies presenting equal priority have **no tiebreak**. Production must source this from **OTP / a die UID / fuse bank** and strap the dies **asymmetrically**. Bonding 16 pads is the wrong answer; a fuse bank is the right one. (YAML head, decision 1.) |
| `DEVICE_CLASS` (TideChart) | **Parameter, not a port** — defaults `16'h0001` | `16'h0001` "reliably wins" the root election, so *every* die boots claiming to be the host complex. **Override the parameter per die** at the instance; this file cannot fix it. |
| `NEGO_CFG_RESET` (TideLink) | Parameter — RTL default `7'h00` (autoneg OFF, parks in `ST_BYPASS`) | Decide deliberately. Production intent is real autoneg (`7'h61`) so `role_locked` intrinsically waits for the far die (RESET_ORDERING §3.3). |

> **Bench-strap landmine:** `mask_hs_bypass` + `apb_debug_unlock` (§4b) let SW force-latch
> `role_locked` **with no autoneg handshake — while `d2d_clk_rx` is still dead**. That
> releases the RX-domain reset and both sides of the a2l CDC on a dead clock and produces a
> permanent, non-recoverable false-FULL wedge on silicon that **no simulation can see**
> (RESET_ORDERING §3.3, §4). For silicon: drop these straps in favour of real autoneg, or
> interlock the SW `ROLE_CFG` W1S behind an RX-clock-present detector (`clkfreq_check`).

### 6c. Open-drain I²C sideband

`i2c_scl` and `i2c_sda` (§4a) are the TideLink I²C sideband. The inner OE (`_t`) is a
**Hi-Z enable** — `_t = 1` means float — so the pad's drive-enable is **active-low** and
the pad must be a **true open-drain / open-collector** cell (drive low or Hi-Z, **never
drive high**) with an **external pull-up** on each net. Choose an OD-capable pad-cell type
and record the pull-up value with the board team.

### 6d. Checklist — what the physical team must decide

Per-pad (every row above), fill in:

- [ ] **Pad cell type** — library cell per net: drive strength, slew, level-shift, ESD;
      **open-drain** for `i2c_scl` / `i2c_sda`; consider pull-ups for `mdio`, I²C.
- [ ] **Die side / location** — edge and quadrant; keep the two D2D source-synchronous
      bundles (§6a) placed for skew match.
- [ ] **I/O supply / voltage** per pad rail.

Design-level decisions:

- [ ] **D2D power domain** — add the isolated/retained link-PHY domain to the UPF
      (PHYSICAL_HANDOFF §5 / gap C3). Ratify the `Sugg. domain` column or replace it.
- [ ] **Per-die strap plan** (§6b): `role_strap` values, `nego_priority_i` source (OTP/UID)
      and whether to bond it, `DEVICE_CLASS` override, `NEGO_CFG_RESET` value.
- [ ] **Bench-strap disposition** (§6b landmine): drop or interlock
      `mask_hs_bypass` / `apb_debug_unlock` for silicon.
- [x] ~~**`d2d_reset` wiring** (§4c): drives nothing / this die / cross-die?~~ **CLOSED
      2026-07-16 — the question is moot: `d2d_reset_o` is tied low by construction**
      (STATUS_REGISTERS.md §4), so it cannot drive anything anywhere. Now unbonded.
      RESET_ORDERING §3.5 is superseded on this point. The *real* issue it exposes is
      upstream: Wlink's RX error state is unreachable, so no ECC error recovery exists
      in either direction.
- [ ] **Reset/power sequencing**: clocks stable → `poresetn` → `hresetn` per die
      (RESET_ORDERING §5); no independent early release of the RX-domain reset.
- [ ] **Lint + SpyGlass CDC on the integrated top** (still owed — PHYSICAL_HANDOFF §6).
- [ ] **`idelay_ref_clk`** stays tied off on ASIC (`USE_IDELAY=0`) — it is FPGA-only.
- [ ] Re-run `make chip-boundary` and confirm **46 pad cells / bonded 59** before tape-out.
- [ ] **If any die in the package will be strapped `dap_swj_enable = 0`** (§4c), revisit
      the status-pad decision — such a die has no SWD, so with its link down it has no
      link-status visibility at all. Bonding `role_locked` alone would close that.

---

## 7. Not bonded — for reference (do not lay out pads for these)

These are classified in the YAML but are **not** pads. Listed so a reader coming from the
handoff §3 class table does not expect them on the ring.

**Tied inputs (21)** — driven to a constant inside the wrapper:
`idelay_ref_clk`, `sys_sysresetreq`, `dap_npotrst`, `dap_swj_enable`,
`network_core_pmuenable`, `chip_core_pmuenable`, `network_core_nmi`, `chip_core_nmi`,
`network_core_rxev`, `chip_core_rxev`, **`nego_priority_i` (`16'h0001`)**,
**`puf_seed` (`16'h0000`)**, **`puf_ready` (`1'b0`)**, and the held-idle `eth_ss_0_*`
AHB test-slave stimulus (`htrans`, `haddr`, `hwrite`, `hsize`, `hburst`, `hprot`,
`hwdata`, `hmastlock`).

**Open outputs (31)** — left unconnected:
`sys_poresetn`, `sys_hclk`, `sys_hresetn`, `eth_ss_0_hrdata`/`hready`/`hresp`,
the `network_core_*` and `chip_core_*` core-status group, `eth_irq`, `phc_pps_irq`,
`phc_alarm_irq`, **`tidechart_irq_o`**, `rtc_time_ptp_ns`/`sec`/`one_pps`,
`ha1588_servo_locked`, **`servo_locked_o`**, **`tl_ewma_credit_o[12:0]`**, and the
four former status pads **`link_active_o`**, **`role_is_master_o`**,
**`role_locked_o`**, **`d2d_reset_o`** (unbonded 2026-07-16 — see §4c).

> **Discrepancy to be aware of (spec vs. handoff §3 class table).** The
> PHYSICAL_HANDOFF §3 table is a *taxonomy over all 111 ports*, not the bonded-pad list.
> It lists `nego_priority_i[15:0]`, `puf_seed[15:0]`, `puf_ready` under **Straps** and
> `servo_locked_o`, `tl_ewma_credit_o[12:0]`, `tidechart_irq_o` under **Status /
> observability** — but the machine-checked YAML **ties** the first three and leaves the
> last three **open**, so **none of those six is a pad**. This pin map follows the YAML
> (the authoritative, `make chip-boundary`-checked source). Of §3's six "Straps", only
> **three** are bonded pads (`role_strap`, `mask_hs_bypass`, `apb_debug_unlock`); **as of
> 2026-07-16 NONE of its seven "Status" entries is bonded** — the last four
> (`link_active`, `role_is_master`, `role_locked`, `d2d_reset`) became register reads.
