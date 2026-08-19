# Firmware CDC contract — EthMAC `MODER` and the HA1588 timestamp-queue resets

**Status:** investigation complete, contract drafted, **NOT YET SATISFIED BY THE FIRMWARE**.
**Date:** 2026-08-17
**Scope:** the two CDC exposures that survived the chiplet-level analysis in
`cdc/nanosoc_eth_chiplet.sgdc` §9a (MODER) and the `Reset_sync02` note in
`ha1588.v:99-116` (PTP timestamp-queue reset).

---

## 0. Verdict, first

The proposal on the table was: *both exposures close with a firmware discipline
rather than an RTL change, therefore no RTL change needs to enter the N1 batched
netlist.* That proposal rested on an unverified assumption — that firmware only
writes these registers while the MAC is stopped.

**The assumption is false, in shipped code, on both exposures.** Two independent
static audits of every call site in the tree found:

| | call sites audited | SAFE | UNSAFE (MAC running) | UNKNOWN |
|---|---|---|---|---|
| **Exposure 1** — `rx_q_rst` / `tx_q_rst` | 18 (13 direct + 5 call chains through `ptp_slave_tsu_reinit`) | 3 | **11** | 4 |
| **Exposure 2** — `MODER` | ~89 write statements across 16 files | ~69 | **11** | 9 |

**These are live exposures reachable today, not theoretical ones.** In particular:

* `FW/apps/ptp_slave/main.c:766` pulses `rx_q_rst` *immediately after a
  twelve-iteration loop whose entire purpose is to observe the RX timestamp queue
  filling from live grandmaster traffic.* The firmware proves to itself that the
  MII-domain write pointer is advancing, and then asynchronously clears it.
* `FW/apps/ptp_slave/ptp_slave.c:710-711` (`ptp_slave_tsu_reinit`) is the
  **steady-state self-heal path**. It fires after five consecutive timestamp
  misses, with the MAC running and the link up. If the `aclr`-vs-`wrclk` race is
  the mechanism that broke the queue, the recovery re-triggers it.
* `FW/apps/eth_netapp/netapp_eth_port.c:331/:333` flips `MODER.FULLD` on a
  running MAC after an up-to-3-second window in which the link came up and real
  frames were received. This is in the **only shipped product** in the tree
  (`eth_netapp_*`), and it is behind `#ifndef NETAPP_SIM` — i.e. it exists on
  silicon and is absent from every simulation build.

And a hardware fact that breaks the proposal on its own terms, independent of any
firmware audit:

> ### The RX timestamp unit is not gated by `MODER.RXEN` at all.
>
> `ethmac_subsystem_apb.v:461-463` taps the **raw MII pads**:
> ```verilog
> .rx_gmii_clk    (mrx_clk_pad_i),
> .rx_gmii_ctrl   (mrxdv_pad_i),
> .rx_gmii_data   ({4'b0, mrxd_pad_i}),
> ```
> not the RXEN-gated `MRxDV_Lb`. `mrx_clk` is free-running
> (`rmii_to_mii.v:277-282`, `mrx_clk <= ~mrx_clk` unconditionally). So clearing
> `RXEN` stops the MAC's receiver but does **not** stop the RX TSU from parsing
> and enqueueing. *"Stop the MAC, then reset the queue" is not a sufficient
> precondition for `rx_q_rst`.* It is sufficient for `tx_q_rst`, whose
> `tx_gmii_ctrl` is `mtxen_pad_o`, a MAC output.
>
> This is not a novel reading. The firmware author already knew, and wrote it
> down at `FW/apps/ptp_tsu_loopdiag/main.c:301-302`:
> *"Re-arm MAC RX so the link partner's frames keep flowing (**the TSU doesn't
> need the MAC**, but keep conditions ptp_slave-like)."* What was never drawn
> from it is the consequence for `q_rst`.

The contract in §4 is therefore **firmware-only for `tx_q_rst`, for every MODER
bit, and for the msgid masks — but firmware alone cannot close `rx_q_rst` on a
live link.** §4.3 gives the strongest precondition firmware *can* offer and names
the residual honestly.

**Recommended decision input for N1.** The firmware fixes in §5 are real work but
small, and they require no RTL change. They retire:

* **10 of the 11 UNSAFE MODER sites** outright (§5.4-§5.6). The eleventh is the
  host-driven debug proxy (§5.7), which can be bounded but not made compliant —
  a calling convention cannot bind a caller that is not in the binary.
* **all 11 UNSAFE queue sites** and all 4 UNKNOWN ones into the C3 sequence
  (§5.1-§5.3), which leaves exactly **one named residual**: a `Q_RST` issued on
  the recovery path while PTP frames are arriving on a live link.

That residual is a narrow removal-timing window, not a deterministic failure —
§4.0 derives why (the write pointer's D input equals its reset value unless
`wrreq` is high at the release edge), and puts the per-call probability at order
1e-9 at a 1 Hz Sync rate. **Its consequence, if it does fire, is a corrupted
gray write pointer and therefore a silently wrong timestamp fed to the servo —
bad time, not a visible fault.** Only the RTL fix in §6.4 closes it.

---

## 1. What the hardware actually does

All line numbers below are the RTL that the ASIC flist compiles
(`build/chip/flist/soc.flist:131,143,150-155`). Vendor RTL is read-only under
`${ARM_IP_LIBRARY_PATH}/`.

### 1.1 Path abbreviations used in this document

| prefix | expands to |
|---|---|
| `FW/` | `nanosoc-multicore-system/firmware/` |
| `SW/` | `nanosoc-multicore-system/ethernet-subsystem-ahb/ethernet-mac-ahb/src/sw/` |
| `HA/` | `nanosoc-multicore-system/ethernet-subsystem-ahb/ethernet-mac-ahb/src/rtl/ha1588_patches/` |
| `SS/` | `nanosoc-multicore-system/ethernet-subsystem-ahb/ethernet-mac-ahb/src/rtl/` |
| `IP/` | `${ARM_IP_LIBRARY_PATH}/OpenCores-EthMAC/rtl/verilog/` |

### 1.2 Clock domains and the real ratio

| domain | source | period | free-running? |
|---|---|---|---|
| fabric / register (`clk`, `wb_clk_i`, `pclk`) | `CLK` pad | **10 ns (100 MHz)** — `ASIC/genus-innovus/inputs/constraints.sdc:61,478` | yes |
| `rmii_ref_clk` | `RMII_REF_CLK` pad | 20 ns (50 MHz) | yes |
| `mrx_clk` / `mtx_clk` | `rmii_to_mii` ÷2 | **40 ns (25 MHz)** — `ethernet_constraints.sdc:41-42` | **yes** |

`rmii_mode_speed` is hard-tied to `1'b1` at
`nanosoc-multicore-system/build_soc/rtl/nanosoc_multicore_soc.sv:923`, so the MII
clocks are always 25 MHz on this part. (The `rmii_to_mii` shim *can* run 10 Mbps
at 2.5 MHz — `rmii_to_mii.v:17-23` — which would multiply every frame-time number
below by 10. It is not reachable in this chip.)

**Ratio: 1 fabric cycle = 10 ns; 1 MII cycle = 40 ns; 4:1.**

### 1.3 Exposure 1 — the timestamp-queue reset

```
SW/ha1588.c:136       HA1588_REG(ha, HA1588_RX_TSU_CTRL) = HA1588_TSU_CTRL_Q_RST;  <- fabric write
HA/reg.v:242          wire rxq_rst = reg_40[1];                                     <- stored level
HA/reg.v:355          assign rx_q_rst_out = rxq_rst_d2 && !rxq_rst_d3;              <- 1-cycle EDGE, clk
HA/ha1588.v:107-111   rx_q_rst_combined <= rx_q_rst;                                <- re-reg on clk
HA/tsu.v:645          ptp_queue queue ( .aclr(q_rst), ... )                         <- ASYNC CLEAR
```

`aclr` is a **10 ns pulse in the fabric domain**, asserted asynchronously against a
40 ns domain and **released at an arbitrary phase of `mrx_clk`**.

`aclr` asynchronously clears **45 flops per queue** (`ADDR_W=4`):

| flops | width | clock domain |
|---|---|---|
| `wr_bin`, `wr_gray` (`ptp_queue.v:48-56`) | 5 + 5 | **`wrclk` = MII** |
| `rd_gray_wr1`, `rd_gray_wr2` (`ptp_queue.v:102-110`) | 5 + 5 | **`wrclk` = MII** |
| `rd_bin`, `rd_gray` (`ptp_queue.v:71-79`) | 5 + 5 | `rdclk` = fabric |
| `wr_gray_rd1`, `wr_gray_rd2` (`ptp_queue.v:88-96`) | 5 + 5 | `rdclk` = fabric |
| `usedw_max_r` (`ptp_queue.v:159-164`) | 5 | `rdclk` = fabric |

The 25 `rdclk` flops are **not** a CDC: `rdclk` is `clk` (`HA/reg.v:352`,
`assign rx_q_rd_clk_out = clk;`) — the same domain the pulse is generated in, so
removal is an ordinary timed arc. **The exposure is the 20 flops clocked by
`mrx_clk` / `mtx_clk`.**

The RTL says so itself, at `HA/ha1588.v:104-106`:

> *"Cross-domain async-reset deassertion to gmii_clk remains a known CDC
> limitation of the OpenCores queue interface (Reset_sync02)."*

### 1.4 Exposure 2 — MODER into the MII domains

`MODER` is three byte-lane registers clocked on the fabric clock
(`IP/eth_registers.v:405-430`, `.Clk(Clk)` = `wb_clk_i`). Reset value from
`IP/eth_defines.v:213-215` is `0x0000A000` — **RXEN and TXEN clear at cold
reset**. (The SystemRDL model in the standalone `ethernet-mac-ahb` clone states
`0x1E000`; where the two disagree, `eth_defines.v` is what was taped out.)

Consumption in the MII domains:

| bit | signal | how it crosses | verdict |
|---|---|---|---|
| `[0] RXEN` | `r_RxEn` | `IP/eth_top.v:734-738` — **1-FF sample on `mrx_clk`, gated by `if(~mrxdv_pad_i)`** | **least bad.** The single flop is a metastability risk, but its only consumer is `MRxDV_Lb = ... mrxdv_pad_i & RxEnSync` (`:598`) and the update is gated to the inter-frame gap, so while `RxEnSync` could be settling, `mrxdv_pad_i` is 0 and the AND masks it. This is a defensible structure and the `sgdc` §9a framing under-credits it. |
| `[1] TXEN` | `r_TxEn` | into `eth_wishbone` / TX BD engine, fabric-side | not a MII-domain crossing |
| `[7] LOOPBCK` | `r_LoopBck` | **`IP/eth_top.v:598,601,604` — COMBINATIONAL mux select into `mrx_clk`, no synchroniser, no mask.** Also `:934` into `eth_macstatus` | **worst.** Flipping it re-sources `MRxDV_Lb`, `MRxErr_Lb` and `MRxD_Lb[3:0]` instantaneously. `eth_rxethmac` samples those on `mrx_clk`; a flip inside its setup/hold window can drive the RX state machine metastable, and even without metastability it splices two unrelated nibble streams. |
| `[10] FULLD` | `r_FullD` | **combinational, unsynchronised, into BOTH MII domains**: `IP/eth_top.v:614` (`eth_txethmac.FullD`, `mtx_clk`), `:674` `TxCarrierSense = ~r_FullD & …`, `:698` `Collision = ~r_FullD & …`, `:726` `Transmitting = ~r_FullD & …`, `:934` (`eth_macstatus`, both MII clocks) | **bad.** Toggling it mid-transmission changes carrier-sense/collision/deferral semantics under a running CSMA/CD state machine. |
| `[5] PRO`, `[13] CRCEN`, `[15] PAD`, `[16] RECSMALL` | via `eth_rxaddrcheck` / `eth_rxethmac` / `eth_txethmac` | combinational, unsynchronised | same class; only ever written before enable in this tree (see §3.2) |

### 1.5 The upstream convention this design should already be following

The OpenCores Ethernet IP Core Specification, Rev 1.19 (2002-11-27),
`${ARM_IP_LIBRARY_PATH}/OpenCores-EthMAC/doc/eth_speci.pdf`, **page 9**,
immediately below Table 4 (the MODER register), states:

> **NOTE: Registers should not be changed after the TXEN or RXEN bits is set.**

That is the "stop then reconfigure" convention, it is documented upstream, and it
is exactly the contract in §4.1. **The firmware in this repository does not follow
it.** It is not a novel constraint invented to rescue a CDC report; it is the
vendor's own stated usage rule, and the CDC report is the consequence of ignoring
it.

The HA1588 upstream has **no** equivalent statement. Its `doc/TSU MEMORY MAP.csv`
documents `TSU_SET_RXRST` only as *"0->1"* — the edge semantics, nothing about
when it is legal to issue. **The queue-reset contract in §4.2/§4.3 is new and has
no upstream precedent to lean on.**

### 1.6 Is there already a safe-sequence helper in the driver?

**No.** Verified across both copies of the driver
(`SW/ethmac.h` and `FW/apps/eth_netapp/driver/ethmac.h` — byte-identical in the
MODER region, differing only in comment wording and three added prototypes):

* `ethmac_enable` / `ethmac_disable` / `ethmac_set_loopback` /
  `ethmac_set_full_duplex` / `ethmac_set_half_duplex` /
  `ethmac_set_promiscuous` (`ethmac.h:114-153`) are **bare read-modify-writes**.
  None reads back, none waits, none checks state.
* `ethmac_init` (`SW/ethmac.c:20-28`) writes only `TX_BD_NUM`. It never touches
  MODER — so an app that does not explicitly write `MODER = 0` inherits whatever
  the previous image left there.
* `ha1588_rx_queue_reset` / `ha1588_tx_queue_reset` (`SW/ha1588.c:131-153`) pulse
  the bit with no precondition and no delay.
* `ptp_slave_tsu_reinit` (`FW/apps/ptp_slave/ptp_slave.c:705-713`) is the closest
  thing to a helper, and its ordering is **backwards** for CDC purposes: it
  resets the queues *first* and programs the msgid masks *second*. The safe order
  is mask-to-zero → wait → reset → restore mask (§4.3).

---

## 2. Call-site audit — Exposure 1 (`rx_q_rst` / `tx_q_rst`)

Verdict key: **SAFE** = MAC stopped *and* the relevant TSU write side provably
quiescent. **UNSAFE** = MAC running / TSU write side live. **UNKNOWN** = not
determinable statically, with the reason given.

| # | site | function | MODER state | TSU write side | verdict |
|---|---|---|---|---|---|
| 1 | `FW/apps/eth_tsu_watermark/main.c:166` | `main`, one-shot | STOPPED (`MODER = 0u` at `:125`) | PHY in internal loopback, TXEN=0, wire isolated; **msgid mask programmed at `:167`, i.e. AFTER the reset — correct order** | **SAFE (cold boot)** / UNKNOWN on warm SWD reload (§2.1) |
| 2 | `FW/apps/ptp_tsu_loopdiag/main.c:204` (rx) | `main`, one-shot | STOPPED (`MODER = 0u` at `:158` inside `mac_bringup`) | PHY unconfigured; masks programmed at `:206-207`, after | **SAFE (cold boot)** / UNKNOWN warm |
| 3 | `FW/apps/ptp_tsu_loopdiag/main.c:205` (tx) | as above | STOPPED | as above | **SAFE (cold boot)** / UNKNOWN warm |
| 4 | `FW/apps/ptp_slave/main.c:597` (rx) | `main`, one-shot | UNKNOWN — RXEN/TXEN are clear at cold reset and nothing before `:597` sets them (`:565`, `:566`, `:576` are OR-of-other-bits), **but the app never writes `MODER = 0`** | UNKNOWN — `ha1588_rtc_reset()` at `:595` does not clear the msgid mask | **UNKNOWN** (§2.1) |
| 5 | `FW/apps/ptp_slave/main.c:598` (tx) | as above | as above | as above | **UNKNOWN** |
| 6 | `FW/apps/ptp_slave/main.c:652` (rx) | `main`, one-shot | as above (RXEN first set at `:656`) | as above, **plus** a PHY soft-reset at `:640-641` and a forced-loopback write at `:648-650` immediately before — the PHY-sourced REF_CLK, hence `mrx_clk`, is bouncing across the `aclr` | **UNKNOWN**, and the worst of the UNKNOWNs |
| 7 | `FW/apps/ptp_slave/main.c:653` (tx) | as above | as above | as above | **UNKNOWN** |
| 8 | **`FW/apps/ptp_slave/main.c:766`** | `main`, one-shot, end of init | **RUNNING** — `MODER \|= RXEN\|TXEN` at `:656` and `:701`, `ethmac_enable` at `:730`; nothing clears them | **PROVABLY LIVE.** The block at `:755-767` is a twelve-iteration loop that polls `RX_TSU_STAT` depth for ~20 s specifically to watch it climb from grandmaster Sync traffic, then calls the reset | **UNSAFE — worst site in the tree** |
| 9 | **`FW/apps/ptp_slave/ptp_slave.c:710` (rx)** — chain A | `ptp_slave_tsu_reinit` ← `main.c:747` | **RUNNING** (`ethmac_enable` at `main.c:730`, 17 lines earlier) | link is up by construction (this call is explicitly placed *after* PHY init "now that the LINK IS UP") | **UNSAFE** |
| 10 | **`FW/apps/ptp_slave/ptp_slave.c:711` (tx)** — chain A | as above | **RUNNING** | TXEN set → TX TSU write side live | **UNSAFE** |
| 11 | **`FW/apps/ptp_slave/ptp_slave.c:710/711`** — chain B | ← `tsu_reinit_try` (`ptp_slave.c:378`) ← `apply_servo` (`:950`) ← `ptp_slave_process_frame` ← `main.c:995` **main loop** | **RUNNING** | live | **UNSAFE — steady-state recovery path.** Fires on `PTP_TSU_REINIT_STREAK`=5 consecutive t3 misses, rate-capped to one per 60 s |
| 12 | **`FW/apps/ptp_slave/ptp_slave.c:710/711`** — chain C | ← `tsu_reinit_try` (`ptp_slave.c:872`, `FOLLOW_UP` branch) ← main loop | **RUNNING** | live | **UNSAFE — steady-state recovery path** |
| 13 | **`FW/apps/ptp_slave/ptp_slave.c:710/711`** — chain D | ← `ptp_service_init` (`FW/apps/ptp_slave/ptp_service.c:106`) ← `FW/apps/eth_netapp/main.c:1209` | **RUNNING** — `netapp_eth_create` (`main.c:1189`) calls `ethmac_enable` at `netapp_eth_port.c:314`, 20 lines earlier | live. `ptp_service.c:102-105` *states* the invariant that the PHY is already up | **UNSAFE.** Affects `eth_netapp_demo_ptp` / `_swd` |
| 14 | **`FW/apps/ptp_slave/ptp_slave.c:710/711`** — chain E | ← `ptp_service_rx` (`ptp_service.c:134`) ← `netapp_eth_poll` (`netapp_eth_port.c:188`/`:254`) ← PicoTCP device poll ← main loop | **RUNNING** | live, steady state | **UNSAFE** |
| 15 | **`FW/apps/ptp_tsu_loopdiag/main.c:298,299`** | `main`, phase-C entry | **RUNNING** (`MODER \|= RXEN\|TXEN` at `:137` via the phase-B loop at `:256-257`; `:303` re-ORs) | live, **and** an AN-restart is issued at `:295-297`, so `mrx_clk` is glitching across the `aclr` | **UNSAFE** |
| 16 | **`FW/apps/ptp_tsu_loopdiag/main.c:323`** | `main`, pre-C1 | **RUNNING** (`:303`) | link-up confirmed by an 8 s `BMSR` poll at `:305-310`; grandmaster streaming Sync at 1 Hz (`:285-289`) | **UNSAFE** |
| 17 | **`FW/apps/ptp_tsu_loopdiag/main.c:330`** | `main`, between C1 and C2 | **RUNNING** (`:303`) | **PROVABLY LIVE** — loop C1 (`:324-329`) sampled non-zero `RX_TSU_STAT` depth into `m1` | **UNSAFE** |
| 18 | **`FW/apps/ptp_tsu_loopdiag/main.c:338`** | `main`, between C2 and C3 | **RUNNING** (`:303`) | **PROVABLY LIVE** — loop C2 sampled depth into `m2` | **UNSAFE** |

**No other writer of `Q_RST` exists.** A repo-wide grep for
`queue_reset|Q_RST|TSU_CTRL` finds only `SW/ha1588.c:136,151` and the sites above
(plus cocotb benches). No interrupt handler reaches any of them —
`ETHMAC_IRQHandler` is a weak no-op (`SW/ethmac.c:346-349`) that nothing
overrides, and `ptp_slave` installs no NVIC handlers at all.

### 2.1 Why four sites are UNKNOWN rather than SAFE

Sites 4-7 (`ptp_slave/main.c:597,598,652,653`) are reached before the app's first
`MODER |= RXEN|TXEN`. On a cold power-on they are genuinely quiescent: MODER
resets to `0x0000A000` and the msgid masks reset to 0 (`HA/reg.v:143,149`), and a
zero mask means `ptp_msgid_mask[int_data[11:8]]` (`HA/ptp_parser.v:226,229`) never
matches, so `ptp_found` never asserts and `wrreq` is dead.

They are **not** SAFE, because:

1. `ptp_slave/main.c` **never writes `MODER = <value>`** — the only bare
   assignment in the file is the debug-proxy read-modify-write at `:470`. Compare
   `eth_tsu_watermark/main.c:125` and `ptp_tsu_loopdiag/main.c:158`, which both do
   `MODER = 0u` and are therefore warm-start-safe.
2. `ha1588_rtc_reset()` (`SW/ha1588.h:137-140`) writes only `RTC_CTRL`. **It does
   not clear the msgid masks.**
3. `pynq/scripts/openocd/cpu0_run_imem.tcl` performs halt → `load_image` → set
   SP/PC → resume, with **no system reset**. The `ptp_slave_swd` target
   (`ptp_slave/CMakeLists.txt:34-47`) is launched exactly this way.

So on any SWD warm relaunch, `ptp_slave` can begin executing with RXEN/TXEN still
set from the previous image and the RX msgid mask still `0x03` — i.e. with the RX
TSU actively enqueueing grandmaster Syncs at the instant of `:597`. Static reading
cannot distinguish the two cases. **Verdict UNKNOWN, and the fix (§5.1) is a
one-line `MODER = 0u`.**

The same warm-restart caveat downgrades sites 1-3 from unconditional SAFE to
"SAFE on cold boot". Those apps *do* clear MODER, so their MAC state is
determined; only the retained msgid mask is uncontrolled, and both apps program
the mask *after* the reset, which is the correct order.

---

## 3. Call-site audit — Exposure 2 (`MODER`)

Approximately 89 write statements across 16 files in the chiplet firmware build.
Roughly 69 are provably STOPPED-before — the standard shape is
`MODER = 0u;` → OR in the config bits → `|= RXEN|TXEN` last, which is exactly
contract C1 and which eight of the ten diagnostic apps already follow. Those are
not reproduced individually; **the table below is the non-SAFE remainder.** The
full enumeration is reproducible with:

```
grep -rn 'MODER' --include=*.c --include=*.h nanosoc-multicore-system/firmware \
     nanosoc-multicore-system/ethernet-subsystem-ahb | grep -v MIIMODER
grep -rn 'ethmac_enable\|ethmac_disable\|ethmac_set_loopback\|ethmac_set_full_duplex\|ethmac_set_half_duplex\|ethmac_set_promiscuous' \
     --include=*.c nanosoc-multicore-system/
```

### 3.1 UNSAFE — MAC provably running

| # | site | bits changed | evidence MAC is running | datapath live? | verdict |
|---|---|---|---|---|---|
| A | **`FW/apps/eth_netapp/netapp_eth_port.c:331`** `ethmac_set_full_duplex` | **FULLD** | `ethmac_enable` at `:314`; only MDIO calls intervene (`:325` scan, `:327` init) | **YES — up to 3 s.** `ethmac_phy_init(..., 3000U)` polls for auto-neg + link-up with RXEN\|TXEN asserted, RX ring armed (`:291-295`), promiscuous under `NETAPP_PTP` (`:311`) | **UNSAFE — shipped product.** `#ifndef NETAPP_SIM` (`:324-336`) means it exists on silicon and in no sim build |
| B | **`FW/apps/eth_netapp/netapp_eth_port.c:333`** `ethmac_set_half_duplex` | **FULLD** | as above | as above | **UNSAFE — shipped product** |
| C | **`FW/apps/eth_netapp/netapp_eth_port.c:227`** `MODER \|= RXEN` (copy-based RX, default build) | RXEN | `ethmac_enable` at `:314`, before `pico_device_init` at `:347`; **nothing in `eth_netapp/` ever clears RXEN or TXEN** | **YES — continuously.** Top of `netapp_eth_poll`, the steady-state receive path, run every PicoTCP tick (~1 kHz) for the life of the product | **UNSAFE by the letter of the contract; value-neutral in the steady state** (§3.3) |
| D | **`FW/apps/eth_netapp/netapp_eth_port.c:173`** `MODER \|= RXEN` (`NETAPP_ZEROCOPY_RX` build) | RXEN | as above | as above | as above |
| E | **`FW/apps/eth_loopback_diag/main.c:293`** `ethmac_set_loopback(&eth, 0)` | **LOOPBCK** | RXEN\|TXEN set at `:266`, re-set by `loopback_round` at `:195`; nothing clears them | **YES** — a complete loopback frame has just traversed the datapath | **UNSAFE.** This is the exact combinational mux flip of `IP/eth_top.v:598` on a running receiver |
| F | **`FW/apps/eth_loopback_diag/main.c:191`** `MODER &= ~(RXEN\|TXEN)` (2nd call of `loopback_round`, via `:327`) | RXEN, TXEN | set at `:195`, re-asserted at `:325` | **YES** — MAC has been RX-enabled on the real RMII since `:293` while the PHY was soft-reset (`:303`), polled (`:305-310`) and forced into 100FD loopback (`:317`) | **UNSAFE** |
| G | **`FW/apps/eth_mac_loopback/main.c:181`** `MODER &= ~(RXEN\|TXEN)` | RXEN, TXEN | `ethmac_enable` at `:243`; **on iterations k≥1 of the retry loop `:252-255` it is the previous iteration's own `:185` that set them** | **YES for k≥1** — the previous iteration transmitted (`:190`) and received (`:192-216`). `loopback_round` returns on the *first* received BD, so the TX BD may still be draining: this is a **disable potentially mid-frame** | **UNSAFE.** Loop note: this site is RUNNING on *every* iteration including k=0; there is no "safe first iteration" |
| H | **`FW/apps/ptp_slave/main.c:465-475`** debug-proxy `MODER` RMW | **RXEN, TXEN, LOOPBCK** (`DBGP_MODER_WMASK`, `:192-194`) | dispatched from the steady-state main loop at `:1020-1029`, long after `ethmac_enable` at `:730`. **By construction it only ever executes with the MAC running** | **YES** | **UNSAFE, and completely ungated** (§3.4) |
| J | **`FW/apps/ptp_tsu_loopdiag/main.c:233`** `ethmac_set_loopback(&eth, 0)` | **LOOPBCK** | phase A ran `loopback_round` (`:215-216`), whose `:137` sets RXEN\|TXEN; nothing clears them before `:233` | **YES** — a complete loopback frame has just traversed the datapath and the queues were drained at `:228-229` | **UNSAFE.** Same combinational mux flip as site E |
| K | **`FW/apps/ptp_tsu_loopdiag/main.c:134`** `MODER &= ~(RXEN\|TXEN)` | RXEN, TXEN | inside `loopback_round`; the phase-B call at `:253` is `for (k = 0; k < 5u; k++)`, so on k≥1 the enables come from the previous iteration's own `:137`. k=0 is covered by `ethmac_enable` at `:250` | **YES for k≥1** | **UNSAFE.** Loop note: RUNNING on every iteration, including k=0 |
| L | **`FW/apps/eth_ptp_capture_liveness/main.c:178`** `MODER &= ~(RXEN\|TXEN)` | RXEN, TXEN | inside `loopback_round`; called from `for (k = 0; k < 3u && !looped; k++)` at `:265-267`. k=0 enables come from `ethmac_enable` at `:260`; k≥1 from the previous iteration's `:181` | **YES for k≥1** | **UNSAFE.** Same disable-possibly-mid-frame shape as site G |

Also present but outside the chiplet firmware build: the same
`enable → phy_init → set_full/half_duplex` pattern at
`nanosoc-multicore-system/ethernet-subsystem-ahb/firmware/eth_app/common/eth_ss_picotcp_port.c:143,152,160,162`.
That tree is the ancestor of `netapp_eth_port.c` and is not compiled into any
chiplet target, but **the defect is replicated, so fixing one copy is not
sufficient**.

### 3.2 UNKNOWN — apps that never initialise MODER

| # | site | why UNKNOWN |
|---|---|---|
| U1-U4 | `FW/apps/eth_tx_scope/main.c:91,93,96,97` | The **only** diag app that does not write `MODER = 0` before its RMWs (contrast `eth_rx_live:51`, `eth_rx_diag:60`, `eth_phyrx_diag:75`, `eth_ping_responder:67`, `eth_phy_link:51`, `eth_phy_regs:50`, `eth_mac_loopback:140`, `eth_loopback_diag:222`). `ethmac_init` writes only `TX_BD_NUM`. Its only target is `eth_tx_scope_swd`, a DAP-load-without-reset target, so a prior image's RXEN\|TXEN routinely survive into it. If they do, `:96` clears LOOPBCK on a running MAC. |
| U5-U8 | `FW/apps/eth_netapp/netapp_eth_port.c:301,302,311,314` | `netapp_eth_create` never writes `MODER = 0`. Cold reset ⇒ STOPPED; any warm restart without a MAC reset (`eth_netapp_gdb_swd`, `eth_netapp_tftp`) ⇒ possibly RUNNING, in which case `:314` is not a rising edge and the MAC's internal RX-BD pointer is not reset while the software cursor is reset to 0 at `:340`. |
| U9 | `FW/apps/eth_perf_bench/main.c:196` | `MAC_ITERS` consecutive same-value writes to MODER. No bit changes value (the word written is the word read at `:193`), and the loop is state-invariant, so this is benign at the register-value level. But the app performs no MAC bring-up at all and pokes whatever MODER holds. If RXEN was 1, this is a burst of write strobes to MODER with the MII datapath live. Flagged, not cleared. |

### 3.3 Why site C/D (the netapp poll path) is a special case

`netapp_eth_port.c:227` executes `g_eth.regs->MODER |= ETHMAC_MODER_RXEN_Msk;`
roughly a thousand times a second with the MAC running. That is a flat violation
of the contract's letter. But in the steady state **RXEN is already 1**, so the
read-modify-write puts the same value back and **no MODER output bit transitions**
— no CDC event is launched. Nothing else writes MODER concurrently (CPU0 is
single-threaded, no ISR touches it), so the read-modify-write cannot tear.

The hazard is latent, not active:

* if RXEN is ever actually 0 when this runs (the case the code's own comment at
  `:223-224` is defending against), the write **is** a real `RXEN 0→1` with the RX
  datapath live — which `RxEnSync`'s inter-frame-gap gate (§1.4) does handle;
* the moment anyone adds another bit to this RMW, it becomes an unsynchronised
  mid-run change with no such protection.

**Verdict: UNSAFE-by-letter, benign-in-practice today, and trivially fixable** —
make the write conditional (§5.4). That converts ~1000 pointless MODER writes per
second into approximately zero and removes the latent case entirely.

### 3.4 The debug proxy (site H) is a hole the contract cannot close from inside

`FW/apps/ptp_slave/main.c` implements a host-driven register proxy (protocol
documented at `:115-168`, executor `dbg_proxy_exec` at `:447-541`). The MODER
write path is:

```c
case DBGP_OP_WRITE32:
    if (addr == NANOSOC_ETHMAC_BASE) {
        uint32_t moder = (eth->regs->MODER & ~DBGP_MODER_WMASK)
                       | (wdata & DBGP_MODER_WMASK);
        eth->regs->MODER = moder;                       /* main.c:465-470 */
```

The **only** guard is `addr == NANOSOC_ETHMAC_BASE` plus the bit mask. There is no
MAC-state check, no TSU-quiesce, no queue-empty precondition, no interlock with
`ptp_slave_tsu_reinit`. `DBGP_MODER_WMASK` is
`RXEN | TXEN | LOOPBCK` — **including the one bit (LOOPBCK) that reaches the RX
datapath combinationally**. The dispatcher runs once per main-loop iteration
(~10 kHz per the comment at `:121`), so a host can flip `LOOPBCK` on a running
receiver at any moment it chooses.

`DBGP_OP_MDIO_WRITE` (`:490-509`) is arguably worse for exposure 1: it lets the
host toggle PHY `BMCR.LOOPBACK`, bouncing the link and glitching the
PHY-sourced REF_CLK — hence `mrx_clk`/`mtx_clk`, the queue's `wrclk` — at
arbitrary times relative to any in-flight `aclr`.

**A caller-side precondition cannot cover a host-driven write.** §4.5 states this
as explicit non-coverage and §5.7 specifies the only realistic mitigation
(gate the proxy).

---

## 4. The contract

### 4.0 Why a firmware precondition closes anything at all

This is the load-bearing argument and it should be checkable, so here it is
explicitly.

`aclr` asynchronously forces `wr_bin`/`wr_gray` to 0. Assertion is safe by
construction — an async clear is dominant and needs no clock edge. The hazard is
**removal/recovery**: at the first `wrclk` edge after `aclr` releases, the flop
must resolve, and it can go metastable *only if its D input differs from the
reset value it is being released from*.

From `ptp_queue.v:45`:

```verilog
wire [ADDR_W:0] wr_bin_next = wr_bin + (wrreq & ~wrfull);
```

With `aclr` holding `wr_bin = 0`, `wr_bin_next` evaluates to `0 + wrreq`.
Therefore:

* **`wrreq == 0` at the release edge ⇒ D = 0 = the reset value ⇒ no transition ⇒
  no recovery/removal hazard at all.** The flop settles to 0 whichever way the
  race resolves.
* `wrreq == 1` at the release edge ⇒ D = 1 ≠ 0 ⇒ genuine removal violation on
  `wr_bin[0]` / `wr_gray[0]`, which can propagate a **gray-code-inconsistent**
  pointer into `wr_gray_rd1/rd2` and hence into `rdusedw` and `rdempty`.

The same argument covers `rd_gray_wr1/rd_gray_wr2` (`ptp_queue.v:102-110`): their
D inputs are `rd_gray` / `rd_gray_wr1`, both held at 0 by the same `aclr` and kept
at 0 afterwards because `rd_bin_next = rd_bin + (rdreq & ~rdempty)` and `rdempty`
is asserted on an empty queue. They are benign unconditionally.

So the **entire** precondition reduces to one sentence:

> **`wrreq` must be 0 across the `aclr` release edge.**

and `wrreq` is `q_wr_en && !q_wr_full` = `ptp_found && int_eop_d1`
(`HA/tsu.v:636`, instantiated at `:645-647`) — a one-`gmii_clk` pulse at the end of a frame the parser
classified as a timestampable PTP event.

**Failure mode if the precondition is violated:** not a hang. A corrupted write
pointer makes `rdusedw = wr_bin_in_rd - rd_bin` (`ptp_queue.v:142`) report a
depth the queue does not have. Firmware then dequeues garbage, or the queue never
reads empty. In `ptp_slave` that is **a silently wrong timestamp fed to the
servo** — bad time, not a visible fault. That is why it matters despite being a
narrow window.

**Residual probability if violated anyway:** the release edge must land inside the
~0.5 ns recovery window of a `wrclk` edge at which `wrreq` is high. `wrreq` is
high for one MII period (40 ns) per timestamped frame. At a 1 Hz Sync rate the
per-reset-call probability is order 1e-9; under a queue-fill stress bench
(`eth_tsu_watermark`, `ptp_tsu_loopdiag` phase C) it rises by the frame rate.
**Low, but the consequence is silent bad time and the recovery path re-rolls the
dice every 60 s.**

### 4.1 Contract C1 — MODER and the EthMAC configuration registers

> **C1.** `MODER`, `CTRLMODER`, `MAC_ADDR0`, `MAC_ADDR1`, `PACKETLEN`, `COLLCONF`,
> `IPGT`, `IPGR1`, `IPGR2` and `TX_BD_NUM` **shall only be written while
> `MODER.RXEN == 0` and `MODER.TXEN == 0`.**
>
> This restates the OpenCores specification, Rev 1.19 p.9: *"Registers should not
> be changed after the TXEN or RXEN bits is set."*
>
> The single exception is the write that clears `RXEN`/`TXEN` themselves, and the
> write that sets them, which must be the **last** MODER write of a configuration
> sequence.

**Required sequence for any runtime reconfiguration** (duplex change on link
renegotiation, loopback entry/exit, promiscuity change, MAC address change):

```
1.  moder = MODER;                                   /* snapshot            */
2.  MODER = moder & ~(RXEN | TXEN);                  /* stop                */
3.  wait >= T_QUIESCE                                /* see 4.4             */
4.  MODER = (desired config, RXEN|TXEN still clear)  /* reconfigure         */
5.  MODER = (desired config) | RXEN | TXEN;          /* start — last write  */
```

Step 3 is not optional. Clearing `RXEN` does not stop an in-flight frame:
`RxEnSync` (`IP/eth_top.v:734-738`) only updates while `mrxdv_pad_i` is low, so
the MAC continues receiving until the current frame ends, and `eth_rxethmac` then
has to finish writing it out through the DMA.

### 4.2 Contract C2 — `tx_q_rst`

> **C2.** `TX_TSU_CTRL.Q_RST` shall only be pulsed while `MODER.TXEN == 0` and
> `T_QUIESCE` has elapsed since it was cleared.

This is **sufficient**, because the TX TSU's `tx_gmii_ctrl` is `mtxen_pad_o`
(`SS/ethmac_subsystem_apb.v:469`), a MAC output. With `TXEN` clear and no
transmission in flight, `int_valid` is dead, `ptp_found` cannot assert, and
`wrreq` is 0 across the release edge — the §4.0 condition holds.

### 4.3 Contract C3 — `rx_q_rst` (the one firmware cannot fully close)

> **C3.** `RX_TSU_CTRL.Q_RST` shall only be pulsed when **all** of:
>
> * **C3a.** `RX_TSU_STAT[31:24]` (the RX msgid mask) has been written to `0x00`,
>   **and** `T_FRAME_MAX` has elapsed since that write; **and**
> * **C3b.** `MODER.RXEN == 0` (so the MAC's receiver is not concurrently
>   consuming the same stream); **and**
> * **C3c.** the RX msgid mask is restored **after** the `Q_RST` pulse, with at
>   least `T_MASK_GAP` between the pulse and the restore.

**C3a is the operative clause and C3b is hygiene, not protection.** As established
in §0 and §1.3, `MODER.RXEN` does not gate the RX TSU — the tap is the raw pad.
The only firmware-reachable lever on `wrreq` is the message-ID mask, because
`ptp_msgid_mask[int_data[11:8]]` (`HA/ptp_parser.v:226,229`) gates `ptp_event`,
which gates `ptp_found`, which gates `wrreq`. A zero mask means no frame is ever
classified and `wrreq` is dead.

**The residual, stated plainly.** `ptp_msgid_mask` is itself an unsynchronised
`sys_fclk → mrx_clk` crossing (`cdc/nanosoc_eth_chiplet.sgdc` §9d; the
"quasi-static" comment at `HA/ptp_parser.v:41-45` is precisely the assumption
firmware violates). Writing the mask to 0 while a frame is mid-header can make
`ptp_event` metastable, which is a smaller version of the same hazard. And the
mask is sampled at `int_cnt == 4/5` — early in the frame — with `ptp_event`
latched from there, so a frame already past its header **will** still write at
`eop` regardless of the mask. Hence the `T_FRAME_MAX` wait in C3a.

**Therefore: C3 reduces the exposure by making `wrreq` dead for the whole reset
window, but it does not eliminate the class.** A `Q_RST` issued while PTP frames
are arriving on the wire cannot be made unconditionally safe from firmware. If an
unconditional guarantee is required, it needs one of:

* an RTL change — a 2-FF async-assert/sync-deassert reset bridge into the
  `gmii_clk` domain in front of `ptp_queue.aclr` (~10 flops, the standard
  `Reset_sync02` fix), which is what the `ha1588.v:99-116` comment is pointing at;
  **or**
* an operational precondition outside firmware's control — link down, PHY in
  isolate/power-down, or a network known to be silent.

### 4.4 Timing constants, grounded in the real clock ratio

| symbol | value | derivation |
|---|---|---|
| `T_FAB` | **10 ns** | fabric clock 100 MHz (`constraints.sdc:61,478`) |
| `T_MII` | **40 ns** | 25 MHz (`ethernet_constraints.sdc:41-42`, RMII ÷2) |
| `T_FRAME_MAX` | **≥ 125 µs** | 1522-byte max frame + 8-byte preamble/SFD = 3060 nibbles × 40 ns = 122.4 µs. Round up. **Assumes `MODER.HUGEN` is clear** — it is, at reset (`eth_defines.v:214`) and no firmware sets it. If HUGEN were ever set, 64 KB frames make this 5.3 ms. |
| `T_QUIESCE` | **≥ 250 µs** | `T_FRAME_MAX` + inter-packet gap (96 bit times = 0.96 µs) + margin for the RX DMA to drain the frame into SRAM. 250 µs is ~2× `T_FRAME_MAX`; it costs nothing at bring-up and covers the DMA tail without needing a bus-idle poll. |
| `T_MASK_GAP` | **≥ 1 µs** | needs only ≥ 2 `T_MII` (80 ns) so the write-domain flops take at least one clean edge after `aclr` release before `wrreq` can be re-armed. 1 µs is a comfortable, easily-expressed round number. |
| `aclr` pulse width | 10 ns (1 `T_FAB`) | `HA/reg.v:355` produces a 1-cycle edge; `HA/ha1588.v:107-111` re-registers it. This is ~250× a typical 65 nm minimum async-reset pulse width, so the clear always lands. **Pulse width is not the problem; release phase is.** |

**There is no hardware handshake and none can be added without an RTL change.**
Nothing in `MIISTATUS`, `INT_SOURCE` or the TSU status registers reports "MAC
receiver idle". `TX_TSU_STAT`/`RX_TSU_STAT` report queue depth, not write-side
activity. **Delay-based quiescence is the only mechanism available**, which is why
`T_QUIESCE` is specified generously rather than as a poll.

### 4.5 What the contract explicitly does NOT cover

1. **`MODER.LOOPBCK` is not a run/stop bit and does not get an easier rule — it
   gets a harder one.** It is a test-mode bit, but its consumption path
   (`IP/eth_top.v:598,601,604`) is the *least* protected of any MODER bit:
   combinational into the `mrx_clk` datapath with no synchroniser and no masking
   AND term, unlike `RxEnSync`. C1 applies to it in full, and there is no
   "it's only a test mode" relaxation. Sites E (`eth_loopback_diag:293`) and H
   (the debug proxy) are both LOOPBCK sites.

2. **Any register written by an interrupt handler cannot rely on a caller-side
   precondition, and this contract offers none.** Today no ISR writes MODER or the
   queue-reset bits — `ETHMAC_IRQHandler` is a weak no-op (`SW/ethmac.c:346-349`)
   with no overrider anywhere in the tree, `netapp_eth_poll` is a PicoTCP device
   callback dispatched from the main loop (not from `SysTick_Handler`, which only
   increments `pico_ms_tick`, `eth_netapp/main.c:201-204`), and `ptp_slave`
   installs no NVIC handlers at all. **If that ever changes, C1-C3 become
   unenforceable for that path** and the register would need either a critical
   section around the whole stop/reconfigure/start sequence or an RTL
   synchroniser. §6 proposes a CI check that would catch the change.

3. **Host-driven writes.** The `ptp_slave` debug proxy (§3.4) and the SWD/DAP
   path can write MODER at any time. A contract expressed as a firmware calling
   convention cannot bind them. §5.7 specifies the mitigation; it is a
   restriction, not a proof.

4. **The `reg_2c → u_rtc.time_adj` window** (`sgdc` §9c) and the
   **`reg_44`/`reg_64` msgid masks** (`sgdc` §9d) are adjacent software contracts
   in the same IP. C3a happens to constrain the RX mask during a queue reset, but
   this document does **not** state a general contract for either. They remain
   open.

5. **Warm restart.** Every "SAFE (cold boot)" verdict in §2 assumes a system
   reset. The SWD relaunch path performs none. C1-C3 are preconditions on a
   *sequence*; they say nothing about what state the previous image left behind.
   §5.1 addresses this with an explicit `MODER = 0u`, which is a fix, not a
   contract clause.

6. **`MODER.TX_BD_NUM` interaction.** `r_TxEn`/`r_RxEn` are gated by `TX_BD_NUM`
   (`IP/eth_registers.v:917-918`). Changing `TX_BD_NUM` therefore changes the
   effective enables without any MODER write. C1 lists `TX_BD_NUM` for this
   reason, but no firmware in this tree writes it outside `ethmac_init`, so it is
   not audited above.

---

## 5. Specified firmware changes

These are specifications, not patches. Each is precise enough to hand to the
driver owner. **All of them land in the `nanosoc-multicore-system` submodule, not
in this repository** — which is itself worth flagging for ownership.

### 5.1 Add the missing MODER initialisation (closes 4 UNKNOWN queue sites + 4 UNKNOWN MODER sites)

**`FW/apps/ptp_slave/main.c`** — two insertions.

(a) Immediately before line 565 (`ethmac_set_full_duplex(&eth);`), i.e. before the
first MODER read-modify-write:

```c
/* Warm-restart safety: the SWD relaunch path (cpu0_run_imem.tcl) performs no
 * system reset, so MODER can carry over from the previous image and every
 * MODER access in this file is an OR-of-other-bits. Force a known-stopped MAC
 * before any config RMW. FIRMWARE_CDC_CONTRACT.md C1. */
eth.regs->MODER = 0u;
```

(b) Immediately after line 595 (`ha1588_rtc_reset(&ha);`) and before the queue
resets at `:597-598`. `ha` is already initialised at `:594`, so this drops
straight in:

```c
/* ha1588_rtc_reset() writes RTC_CTRL only — it does NOT clear the TSU msgid
 * masks, which also survive an SWD warm restart. A non-zero mask means the RX
 * TSU write side is LIVE at :597 (the tap is the raw MII pad, not RXEN-gated).
 * Kill it and wait one max frame time. FIRMWARE_CDC_CONTRACT.md C3a. */
ha1588_rx_set_msgid_mask(&ha, 0x00u);
ha1588_tx_set_msgid_mask(&ha, 0x00u);
ETHMAC_DELAY_US(250);   /* T_QUIESCE + T_FRAME_MAX */
```

The existing mask programming at `:599-600` already sits after the resets, which
is the correct order and needs no change.

Same one-line `MODER = 0u;` addition, for the same reason:

* **`FW/apps/eth_tx_scope/main.c`** — before line 91.
* **`FW/apps/eth_netapp/netapp_eth_port.c`** — before line 301.

### 5.2 Fix the ordering inside `ptp_slave_tsu_reinit` (closes queue sites 9-14)

**`FW/apps/ptp_slave/ptp_slave.c:705-713`.** Current body resets the queues and
*then* programs the masks. Required body:

```c
void ptp_slave_tsu_reinit(ha1588_t *ha, ethmac_t *eth)
{
    /* CDC contract C2/C3 (FIRMWARE_CDC_CONTRACT.md):
     * ptp_queue.aclr is an ASYNC clear of 20 flops in the free-running
     * mrx_clk/mtx_clk domain, released at an arbitrary phase. It is only safe
     * when wrreq is 0 across the release edge. wrreq = ptp_found && eop, and
     * ptp_found is gated by the msgid mask -- so kill the mask FIRST, wait a
     * max frame time for any frame already past its header to finish, THEN
     * pulse the reset, THEN restore the mask.
     * NOTE: MODER.RXEN does NOT gate the RX TSU (the tap is the raw MII pad,
     * ethmac_subsystem_apb.v:461-463), so stopping the MAC is necessary
     * hygiene but is NOT sufficient. A reset issued while PTP frames are
     * arriving retains a narrow residual -- see contract C3. */
    uint32_t moder = eth->regs->MODER;

    ha1588_rx_set_msgid_mask(ha, 0x00u);          /* C3a: kill wrreq (RX)     */
    ha1588_tx_set_msgid_mask(ha, 0x00u);
    eth->regs->MODER = moder & ~(ETHMAC_MODER_RXEN_Msk | ETHMAC_MODER_TXEN_Msk);
    ETHMAC_DELAY_US(250);                          /* T_QUIESCE + T_FRAME_MAX  */

    ha1588_rx_queue_reset(ha);                     /* C2/C3: the aclr pulses   */
    ha1588_tx_queue_reset(ha);

    ETHMAC_DELAY_US(1);                            /* C3c: T_MASK_GAP          */
    ha1588_rx_set_msgid_mask(ha, PTP_TSU_RX_MSGID_MASK);
    ha1588_tx_set_msgid_mask(ha, PTP_TSU_TX_MSGID_MASK);

    eth->regs->MODER = moder;                      /* C1: restore, enables last*/
}
```

**This is a signature change** (`ethmac_t *eth` added) affecting four call sites:
`ptp_slave.c:332` (via `tsu_reinit_try`), `ptp_slave.c:378`, `ptp_slave.c:872`,
`FW/apps/ptp_slave/main.c:747`, and `FW/apps/ptp_slave/ptp_service.c:106`. The
`ptp_slave_ctx_t` does not currently carry an `ethmac_t*`; either add one or pass
it through `tsu_reinit_try`.

**Cost:** ~251 µs of blocked receive per re-init. On the recovery path that fires
at most once per 60 s (`PTP_TSU_REINIT_HOLD_SEC`), so ~4 ppm duty. Acceptable.

### 5.3 Route the remaining direct queue resets through the helper (closes sites 8, 15-18)

Replace the bare `ha1588_rx_queue_reset` / `ha1588_tx_queue_reset` pairs with
`ptp_slave_tsu_reinit(&ha, &eth)` at:

* **`FW/apps/ptp_slave/main.c:766`** — the site with proven-live evidence. The
  surrounding block already knows the queue is filling; it must stop it first.
* **`FW/apps/ptp_tsu_loopdiag/main.c:298-299`**, **`:323`**, **`:330`**, **`:338`**.
  These are a diagnostic app, but sites `:330` and `:338` are also the **cleanest
  reproduction points** for the hazard: loops C1/C2 record the pre-reset queue
  depth into `m1`/`m2`, so a bench run with and without the fix gives a direct
  before/after. Consider keeping one unfixed variant behind a `#define` for
  exactly that purpose.

The two already-correct sites — `eth_tsu_watermark/main.c:166` and
`ptp_tsu_loopdiag/main.c:204-205` — need only the msgid-mask-first ordering to
become unconditionally compliant; their MAC state is already correct.

### 5.4 Make the netapp poll-path MODER write conditional (closes sites C, D)

**`FW/apps/eth_netapp/netapp_eth_port.c:227`** (copy path) and **`:173`**
(zerocopy path). Replace:

```c
g_eth.regs->MODER |= ETHMAC_MODER_RXEN_Msk;
```

with:

```c
/* CDC contract C1: never write MODER on a running MAC. In the healthy steady
 * state RXEN is already set, so the old unconditional RMW put back the same
 * value ~1000x/s for nothing. Read first and write only on the transition the
 * belt-and-braces re-assert actually exists for. */
if (!(g_eth.regs->MODER & ETHMAC_MODER_RXEN_Msk))
    g_eth.regs->MODER |= ETHMAC_MODER_RXEN_Msk;
```

This is strictly cheaper (one read replaces one read + one write, ~1000 times a
second) and removes the latent case entirely. It does **not** need the full
stop/wait/start sequence, because the only transition it can now perform is
`RXEN 0→1`, which is the one MODER transition that *is* protected — by
`RxEnSync`'s inter-frame-gap gate (§1.4).

### 5.5 Fix the duplex-after-link-up sequence (closes sites A, B — shipped product)

**`FW/apps/eth_netapp/netapp_eth_port.c:324-336`.** The MAC must not be enabled
before auto-negotiation resolves. Move `ethmac_enable(&g_eth)` from `:314` to
*after* the `#ifndef NETAPP_SIM` block, and set duplex while stopped:

```c
    /* MAC stays STOPPED across PHY bring-up: MODER.FULLD reaches the mtx_clk
     * CSMA/CD state machine combinationally (eth_top.v:614,674,698,726) with no
     * synchroniser, so it must not move on a running MAC.
     * FIRMWARE_CDC_CONTRACT.md C1. */
#ifndef NETAPP_SIM
    int phy_addr = ethmac_phy_scan(&g_eth);
    if (phy_addr >= 0) {
        if (ethmac_phy_init(&g_eth, (uint32_t)phy_addr, 3000U) == 0) {
            if (ethmac_phy_link_is_fullduplex(&g_eth, (uint32_t)phy_addr) == 1)
                ethmac_set_full_duplex(&g_eth);
            else
                ethmac_set_half_duplex(&g_eth);
        }
    }
#endif
    ethmac_enable(&g_eth);      /* C1: enables are the LAST MODER write */
```

`ethmac_phy_scan` / `_init` / `_link_is_fullduplex` are MDIO-only
(`MIIADDRESS`/`MIICOMMAND`/`MII*_DATA`) and work perfectly well with the MAC
stopped, so this reordering costs nothing. It also removes the up-to-3-second
window in which the ring is armed and promiscuous while duplex is still at the
half-duplex default.

**Replicate the identical change** at
`ethernet-subsystem-ahb/firmware/eth_app/common/eth_ss_picotcp_port.c:143,152-163`
(same defect, different tree, not in the chiplet build).

### 5.6 Fix the loopback-exit and disable-mid-frame sites (closes E, F, G, J, K, L)

**Loopback-exit on a running MAC** (sites E and J). Wrap in the C1 sequence —
clear `RXEN|TXEN`, `ETHMAC_DELAY_US(250)`, clear `LOOPBCK`, re-enable:

* **`FW/apps/eth_loopback_diag/main.c:293`**. This also fixes site F as a side
  effect, because `:325`'s "ensure RXEN|TXEN" then becomes a real `0→1` edge
  instead of a no-op — and the algorithm's own comment at `:186-190` *depends* on
  that edge, which it currently does not get.
* **`FW/apps/ptp_tsu_loopdiag/main.c:233`**.

**Disable-possibly-mid-frame inside `loopback_round`** (sites G, K, L). All three
are copies of the same routine. In each, poll `ethmac_tx_bd_done()` for the TX
descriptor *before* the disable — the function currently returns on the first
*received* BD, so the transmitter may still be draining — then insert
`ETHMAC_DELAY_US(250)` between the disable and the re-enable:

* **`FW/apps/eth_mac_loopback/main.c:181`** → `:185`
* **`FW/apps/ptp_tsu_loopdiag/main.c:134`** → `:137`
* **`FW/apps/eth_ptp_capture_liveness/main.c:178`** → `:181`

These three are near-identical forks of `eth_loopback_diag`'s `loopback_round`
(`:191`/`:195`). **Factoring them into one shared helper is the change that
prevents the next fork from reintroducing the defect**, and it is what the CI
check in §6.1 can then key on.

### 5.7 Gate the debug proxy (mitigates site H)

**`FW/apps/ptp_slave/main.c:465-475`.** Either:

* **(a)** narrow `DBGP_MODER_WMASK` (`:192-194`) to `RXEN | TXEN` only, removing
  `LOOPBCK` — the bit with no synchroniser — from the host's reach; **or**
* **(b)** apply the full C1 sequence inside `dbg_proxy_exec`: stop, wait
  `T_QUIESCE`, apply the masked bits, restart. This blocks the ~10 kHz proxy loop
  for 250 µs per MODER write, which is acceptable for a debug path.

(a) is the smaller change and removes the worst bit. (b) is the correct one.
**Neither makes the proxy contract-*compliant* in the sense of §4.5.3** — a host
that can write MODER at all is outside the contract's reach; these only bound the
damage.

### 5.8 Add the helper the driver is missing

**`SW/ethmac.h`** — add, next to `ethmac_enable`/`ethmac_disable`:

```c
/**
 * Stop the MAC and wait for it to become quiescent.
 *
 * MANDATORY before any MODER / CTRLMODER / MAC_ADDR / PACKETLEN / COLLCONF /
 * IPG* / TX_BD_NUM write. OpenCores spec Rev 1.19 p.9: "Registers should not be
 * changed after the TXEN or RXEN bits is set."
 *
 * Clearing RXEN does not stop an in-flight frame: RxEnSync (eth_top.v:734-738)
 * only updates while MRxDV is low, so reception continues to the end of the
 * current frame. T_QUIESCE = 250 us covers a 1522-byte frame at 25 MHz MII
 * (122.4 us) plus IPG plus the RX DMA tail.
 *
 * Returns the MODER value as it was before the stop, for ethmac_start().
 * See FIRMWARE_CDC_CONTRACT.md.
 */
uint32_t ethmac_stop_and_quiesce(ethmac_t *eth);

/** Re-apply a config word and set RXEN|TXEN as the LAST MODER write. */
void ethmac_start(ethmac_t *eth, uint32_t moder_cfg);
```

Then re-express `ethmac_set_loopback`, `ethmac_set_full_duplex`,
`ethmac_set_half_duplex` and `ethmac_set_promiscuous` in terms of them, and
**mark the raw RMW forms deprecated** rather than deleting them (several diag apps
legitimately call them with the MAC provably stopped, and forcing a 250 µs stall
into those would slow the benches for nothing). The deprecation is what the CI
check in §6.1 keys on.

**Both copies of the driver must change** (`SW/ethmac.h` and
`FW/apps/eth_netapp/driver/ethmac.h`); they are byte-identical in this region
today and must not diverge. **Better still: delete the copy and make
`eth_netapp` include the canonical one**, which is a separate cleanup this audit
recommends on its own merits.

---

## 6. Enforcement

A contract nobody checks decays, and this one has already decayed once — the
upstream spec has said "do not change registers after TXEN/RXEN is set" since
2002 and eight sites in this tree do it anyway. Three mechanisms, ranked by what
is actually achievable before N1.

### 6.1 CI grep gate — **achievable now, zero RTL risk, recommended**

Add `scripts/ci/check_firmware_cdc_contract.py`:

* Scan the firmware tree for (i) writes to `MODER` (direct `->MODER` assignment,
  `|=`, `&=`, and calls to the deprecated raw driver helpers) and (ii) calls to
  `ha1588_rx_queue_reset` / `ha1588_tx_queue_reset` / literal `Q_RST` writes.
* Require each hit to be either:
  * inside a function whose body also contains `ethmac_stop_and_quiesce` (§5.8) or
    `ptp_slave_tsu_reinit` (§5.2); **or**
  * annotated with a `/* CDC-CONTRACT-OK: <reason> */` comment on the preceding
    line; **or**
  * listed in `ci/fixtures/firmware_cdc_allowlist.yaml` with a justification and
    an owner.
* Fail on any unannotated hit. Emit the current 16 UNSAFE/UNKNOWN sites as the
  seed allowlist so the gate goes green on day one and **can only shrink**.

Wire it into `ci/signoff.yaml` as a new `rtl`-phase row, `gate: report` initially
— the same treatment `cdc` gets, and for the same stated reason ("gating it today
would gate on a known-nonzero baseline"). Promote to `gate: block` when the
allowlist is empty. It runs at the `chip-boundary` rung of `ci-ladder.yml`
(python-only, no EDA licence, no submodule build), so it costs seconds.

**Caveat, stated up front:** the firmware lives in the `nanosoc-multicore-system`
submodule. The gate reads across the submodule boundary (submodules are
bootstrapped at rung 2), but **the fixes land in a different repository**, so a
red gate here is a cross-repo ticket, not a local edit. That is a real friction
and it should be acknowledged when the gate is proposed, not discovered later.

### 6.2 Debug-build driver assertion — **achievable, catches what grep cannot**

A grep cannot see the dynamic case (site C's "RXEN might be 0 at runtime", or a
warm restart's inherited MODER). Add to `SW/ethmac.h`:

```c
#ifdef ETHMAC_CDC_CONTRACT_CHECK
#define ETHMAC_ASSERT_STOPPED(eth) do {                                   \
    uint32_t _m = (eth)->regs->MODER;                                     \
    if (_m & (ETHMAC_MODER_RXEN_Msk | ETHMAC_MODER_TXEN_Msk))             \
        ethmac_cdc_contract_violation(__FILE__, __LINE__, _m);            \
} while (0)
#else
#define ETHMAC_ASSERT_STOPPED(eth) ((void)0)
#endif
```

Place it at the head of every config-register writer and of
`ha1588_*_queue_reset`. `ethmac_cdc_contract_violation` logs file/line/MODER to
UART and bumps a counter in the status mirror (see `STATUS_REGISTERS.md`) —
**it must not trap**, or a debug build becomes unusable on a running link. Cost in
production builds: zero (the macro compiles out). Cost in debug builds: one AHB
read per config write.

Add `-DETHMAC_CDC_CONTRACT_CHECK` to one CI-built firmware variant so the counter
is exercised by the existing regression rather than only by hand.

### 6.3 Bench-side SVA — **achievable, but sim-only**

There is no `assert property` anywhere in `src/rtl` or
`ethernet-subsystem-ahb/src/rtl` today, so this is new infrastructure. It does
**not** have to touch the netlist: put the checker in a separate file bound into
the existing cocotb/UVM benches only.

```systemverilog
// bind onto the eth subsystem in sim only — NOT in the synthesis flist
property p_loopbck_stable_while_running;
  @(posedge wb_clk_i) disable iff (wb_rst_i)
    (r_RxEn || r_TxEn) |-> $stable(r_LoopBck);
endproperty
property p_qrst_only_when_wrreq_idle;
  @(posedge mrx_clk_pad_i) $rose(rx_q_rst_combined) |-> !q_wr_en;
endproperty
```

The second one is the direct encoding of §4.0's precondition and would have
flagged `ptp_tsu_loopdiag:330` in the very first bench run that exercised it.

### 6.4 What is NOT realistic before N1

An **RTL synchroniser** — the 2-FF async-assert/sync-deassert reset bridge in
front of `ptp_queue.aclr`, and a 2-FF sync on `r_LoopBck` into `mrx_clk` — is the
*correct* fix and would close both exposures unconditionally, including the
residual in C3 and the host-driven writes in §4.5.3. It is ~10-20 flops. But it is
an RTL change into the N1 batched netlist against a fixed date, and the framing of
this task is explicitly to avoid that. **This document does not recommend it for
N1; it records that the firmware route leaves a named residual that only the RTL
route closes, so the decision is made with both halves visible.**

---

## 7. Cross-references

| document | relationship |
|---|---|
| `cdc/nanosoc_eth_chiplet.sgdc` §9a | the MODER finding this audit was commissioned against. **Its conclusion — "the firmware in this repository already breaks it" — is confirmed**, with 8 specific sites. Its framing under-credits `RxEnSync` (§1.4 here) and does not mention that the RX TSU bypasses `RXEN` entirely (§0 here). |
| `cdc/nanosoc_eth_chiplet.sgdc` §9b | the *other* `ptp_queue` finding — the unenabled 128-bit capture flop at `reg.v:403/461`. Different mechanism, not covered here, still open. |
| `cdc/nanosoc_eth_chiplet.sgdc` §9d | `reg_44`/`reg_64` msgid masks. C3a leans on the mask being writable at runtime, which is exactly the crossing §9d flags. Interaction noted in §4.3; not resolved. |
| `HA/ha1588.v:99-116` | the RTL's own `Reset_sync02` acknowledgement — the primary source for exposure 1. |
| `${ARM_IP_LIBRARY_PATH}/OpenCores-EthMAC/doc/eth_speci.pdf` p.9 | the upstream "stop then reconfigure" note. C1 is a restatement of it. |
| `../verification/CDC_WAIVER_INVENTORY.md` | neither exposure currently carries a waiver; `cdc/waiver.swl` contains no `Reset_sync*` or `ptp_queue` entry. If C1-C3 are adopted and enforced, **that is the justification a `cdc_false_path` on these paths would need** — but not before §5 lands. |
