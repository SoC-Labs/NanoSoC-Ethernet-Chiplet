# Link status registers — reading chiplet status without pads

**This file replaces four pads.** On 2026-07-16 the link-status pads (`link_active`,
`role_is_master`, `role_locked`, `d2d_reset`) were unbonded — 50 → 46 pad cells — because
every one of them is already a readable bit in the TideLink config APB. The visibility
was never missing; it was undocumented. This is that documentation.

Everything below was verified against the **pinned** TideLink submodule (`3f3de09`,
`nanosoc-ethernet-chiplet/tidelink`), not the standalone `~/SoCLabs/tidelink` clone —
those trees are on different commits and `tidelink_top.sv`, `Wlink.v` and
`axi_chiplet_controller.sv` differ between them. `set_env.sh:31` points `TIDELINK_HOME`
at the submodule, so the submodule is what elaborates.

---

## 1. The address table

All addresses are what the **SoC's `d2d_ahb_m` manager port** issues — i.e. what CPU0,
CPU1, the DMAC or an SWD debugger writes into a load/store.

| Signal (former pad) | Address | Bit | Notes |
|---|---|---|---|
| `role_locked_o` | `0x2E032084` | [1] | `role_status.locked` |
| `link_active_o` | `0x2E032084` | [1] | **Same bit** — see §3 |
| `role_is_master_o` | `0x2E032084` | [0] | `role_status.effective_role` — **INVERTED**: 0 = master |
| `d2d_reset_o` | `0x2E030234` | [2] | Wlink `LinkStatus.in_error_state` — **always 0**, see §4 |
| `servo_locked_o` | `0x2E03205C` | [0] | `SERVO_STATUS`. TideLink's PTP servo, **not** the ethernet HA1588 servo |
| `tl_ewma_credit_o` | `0x2E0320F8` | [12:0] | `PERF_CONG_STATE`. Requires perf enabled — see §5 |

Adjacent bits worth knowing:

| What | Address | Bit |
|---|---|---|
| Wlink TX lanes active | `0x2E030234` | [3] |
| Wlink RX data valid | `0x2E030234` | [4] |
| **Software link reset** (write 1) | `0x2E030208` | [3] |
| `sb_reset_in` SW override value | `0x2E030234` | [0] |
| `sb_reset_in` SW override select | `0x2E030234` | [1] |
| `PERF_CTRL` — bit[0] enables perf | `0x2E0320A0` | [4:0] |
| `PERF_ID` — presence gate, reads `0x5046_0100` | `0x2E0320FC` | [31:0] |

### How the address decodes

```
0x2E032084
  haddr[24]    = 0        -> the 0x2E aperture           (chiplet_d2d_decode.sv:113)
  haddr[19:16] = 4'h3     -> hsel_tlapb                  (chiplet_d2d_decode.sv:136)
  haddr[14:0]  = 0x2084   -> u_tlapb_bridge PADDR        (nanosoc_eth_chiplet.sv:537)
  paddr[14:13] = 2'b01    -> TideLink regs               (tidelink_top.sv:706-708)
  paddr[8:5]   = 4'h4     -> Region 4 (role)             (tidelink_apb_regs.sv:186)
  paddr[4:2]   = 3'h1     -> region4 slot 1              (axi_chiplet_controller.sv:952)
```

**This window is readable with the link DOWN.** The `tx_open = link_active_i` gate in
`chiplet_d2d_decode.sv:131` applies **only** to the TX aperture (`blk == 4'h0`). `a_tlapb`
carries no `tx_open` term, and the APB registers are reset by `hresetn`, not by
`role_locked`. That is the whole point — these bits are needed precisely when the link is
not up.

---

## 2. Reading these without a CPU

The CoreSight SWJ-DP's AHB-AP is a full bus initiator (matrix initiator #3), and its
per-initiator decoder maps `0x2E000000-0x2FFFFFFF` unconditionally
(`multicore_matrix_decode_DAP_SS_0_M.v:548-550`). It is clocked by free-running
`SYS_HCLK`, and `slcorem0p_prmu.v:91-93` says why in as many words:

> System HCLK needs to be assigned to System Free-running Clock so other managers can
> still access bus when CPU is sleeping.

So an external SWD debugger reads every address in §1 with **both cores halted or
sleeping**, and in the cold-boot state where CPU0 is held in reset. `dbgen`/`spiden` are
tied high and are not address-selective; the DAP address translator rewrites only top-byte
`0xE0`, so `0x2E` passes through untouched.

**Where this does not hold:**

1. **`sys_sysresetn` asserted** — the SWJ-DP is itself in reset (`DPRESETn` ← `poresetn`),
   so nothing is readable. A pad would still be observable here. In practice this costs no
   information: `role_lock_reg` is forced to its POR value in that state anyway.
2. **During a CPU1-originated reset pulse** (SYSRESETREQ / lockup / watchdog) there is an
   8-cycle `RESET_STRETCH` window where the AHB-AP is reset. CPU1 software can transiently
   knock out the debugger's own access path.
3. **`dap_swj_enable = 0`** — a non-active die in a multi-chiplet package has **no SWD at
   all**. With its link also down, such a die has no link-status visibility by any route.
   Not a concern while `chip.v` ties it `1'b1`. **This is the one scenario that would
   justify bonding `role_locked` again** — see PIN_MAP.md §4c.

---

## 3. `link_active` and `role_locked` are the same net

`tidelink_top.sv:2308`:

```systemverilog
assign link_active = role_locked_o;
```

That is the sole driver of the `link_active` output. It is not an independent link-layer
status: there is no separate "link is up" indication anywhere in this design — role-lock
*is* the up indication. The chiplet then fanned it to `link_active_o` (`:357`) while also
exporting `role_locked_o` (`:734`) — two pads, one bit.

Its use as the TX-aperture gate (`u_d2d_decode.link_active_i`) is an **internal** path and
was never affected by the pad.

---

## 4. `d2d_reset_o` is tied low — because ECC checking is deliberately bypassed

**Do not use this bit. It can never be 1.** It is also not a reset — the name misleads.

### What it actually is

`sb_reset_out`/`sb_reset_in` is a cross-die **backpressure handshake**, not a reset
distribution network. A die raises `sb_reset_out` when its receiver is in an error state;
the peer's `sb_reset_in` gates off its link-layer transmitter — `lltx_io_enable =
swi_lltx_enable & ~swi_sb_reset_in_muxed`, the *only* consumer of `sb_reset_in` anywhere in
Wlink. Meaning: *"my receiver is confused, stop talking so we can retrain."*

This integration ties `.sb_reset_in(1'b0)` (`tidelink_top.sv:2024`), so this die ignores a
peer's indication regardless.

### Why it can never assert — the root cause

`d2d_reset_o` ← `sb_reset_out` ← `llrx.io_in_error_state` = `(state == 2'h2)`. That state
is unreachable: `WlinkRxLinkLayer.v:1305` writes `2'h2` only inside
`else if (state == 2'h2)` — a self-loop with no entry edge — and reset forces `2'h0`.

**But the self-loop is a symptom, not the cause.** The cause is upstream of it, in
`deps/axi-chiplet-controller/logical/wlink/WlinkEccSyndrome.v:306-308`:

```verilog
// The Hamming(33,24) decoder above flags every header as corrupted on
// the bench at 25 MHz — even with CRC errors driven to zero by SLEW
// FAST + DRIVE 8. cr_pkt traffic survives the channel (CRC clean) but
// never reaches the FCSM because ecc_check_corrupted gates is_short_pkt.
// Bypass: accept ph_in as-is, never flag corruption, never claim correction.
// Real fix is to audit the syndrome polynomial vs the TX-side ECC RTL.
assign corrected_ph = ph_in;
assign corrected = 1'h0;
assign corrupted = 1'h0;
```

**The ECC syndrome checker is a deliberate, documented bring-up bypass.** Because
`ecc_check_corrupted` is a constant 0, the FSM's ERROR entry — Chisel
`when(ecc_check.corrupted & io.swi_ecc_corrupt_errs){ nstate := ERROR }` — is dead code,
and firrtl eliminated it. That is faithful generation of a design where the feature is off,
not a generator defect. (`swi_ecc_corrupt_errs` is also an undriven `Input` in
`Wlink.scala`, so the ERROR entry was gated off independently of the stub.)

### So: is there any ECC error detection?

**No — and the team already knew.** The `obs_ecc_corrupted_cnt` / `obs_ecc_corrected_cnt`
counters exist and are wired through a synchronizer (`axi_chiplet_controller.sv:1721-1724`),
but they count a signal that is constant 0. `axi_chiplet_controller.sv:2549-2550` says so
outright and **repurposed that register field to `SYNC_DETECTED_COUNTER`**, noting the ECC
fields are "DEAD/0". So this is a known, accepted trade-off, not an undiscovered defect.

Net: this link runs **without ECC protection on the packet header**. CRC still covers the
payload — the bypass comment notes cr_pkt traffic is CRC-clean — so this is a loss of
header-corruption *detection*, not of all integrity checking.

### Why this was NOT fixed here

Not a code change. The real fix, per the bypass comment, is to **audit the Hamming(33,24)
syndrome polynomial against the TX-side ECC RTL and re-validate on a 25 MHz bench**. Get it
wrong and every header is flagged corrupt, `is_short_pkt` is gated off, and **no traffic
reaches the FCSM at all** — the link stops working entirely. That is exactly the failure
that caused the bypass. It needs hardware in the loop, and it is upstream vendor IP.

Patching the FSM self-loop would be a **no-op**: with `corrupted` tied to 0, an ERROR entry
condition can never fire.

**Status: raise upstream.** The pin is deliberately frozen (PIN_POLICY.md).

### How the link actually resets

Not via `d2d_reset_o`, and **not** by clearing `role_locked` — `role_lock_reg` is W1S with
**POR-only clear** (`axi_chiplet_controller.sv:545` says so; its only `<= 1'b0` is under
`!poresetn` at `:645`, and post-lock ROLE_CFG writes are gated on `!role_locked`). The real
paths are:

1. **`sw_reset`** — `0x2E030208` bit[3]. Drives `por_reset` into all three link clock
   domains (`Wlink.v:2430-2439`). **This is the software link reset.**
2. **`poresetn`** — clears `role_lock_reg`, and hence `wlink_por_reset = ~poresetn |
   ~role_locked` and `app_clk_reset = ~hresetn | ~role_locked`.

---

## 5. `tl_ewma_credit_o` is permanently zero

**Do not use this bit either, and do not trust `PERF_ID` as a presence gate.** An
off-by-one between two files kills the whole perf register region:

- `tidelink_apb_regs.sv:540` drives `perf_reg_region = apb_region[1:0]` (raw), where
  `apb_region = paddr[8:5]`.
- `perf_reg_write` is gated to `apb_region` 5..7 (`:536-537`), so when a write is live
  `apb_region[1:0]` ∈ {`01`,`10`,`11`} — **never `00`**.
- `tidelink_perf.sv:437` writes `perf_enable_r` **only** under
  `perf_reg_write && perf_reg_region == 2'b00`. Unreachable.
- `perf_enable_r` resets to 0 (`:432`) and `ewma_q_r` only advances under
  `perf_active = perf_enable_r & ~perf_freeze_r` (`:120`, `:365`).

`tidelink_perf.sv:53` documents the port as `00=Region5, 01=Region6, 10=Region7`
(offset-from-5); the driver passes the raw value. Producer and consumer disagree by one.

Consequences:

| | |
|---|---|
| `perf_enable_r` | Can never be set. EWMA never advances. `tl_ewma_credit_o` ≡ 0. |
| `PERF_CONG_STATE` | Actually at `0x2E0320D8`, not the `0x20F8` in the docs |
| `PERF_ID` | Region 7 falls through to `default:` → reads `0x0`. **Any bring-up script gating on `PERF_ID == 0x5046_0100` fails before it reaches the telemetry.** |
| `src/sw/tidelink_perf.h` | Bit definitions also disagree with the RTL: header says `FREEZE`=bit3 / `CLEAR_COUNTERS`=bit1; RTL uses bit1=freeze, bit2=clear_counters, bit3=clear_TS, bit4=irq_en. Writing the header's `FREEZE` mask would set `clear_TS`. |

**Why it escaped testing:** `cocotb/tidelink_perf_congestion` compiles only
`tidelink_perf.sv` — `tidelink_apb_regs.sv` is never elaborated. The test hardcodes
`REGION5 = 0b00` and pokes `perf_reg_region` directly, so it encodes the *module's*
convention and passes while the integration is broken.

### Status: FIXED and IN THE PIN as of 2026-07-16

Everything in §5 above describes the **historical** bug, kept because it explains why the
old addresses and SW headers were wrong and why nothing caught it. **The pin now carries
the fix**, so `PERF_CONG_STATE` answers at `0x2E0320F8` (not `0x20D8`) and `PERF_ID` at
`0x2E0320FC` reads `0x5046_0100`. **The EWMA still reads 0 until software enables perf** —
write `PERF_CTRL` bit[0] at `0x2E0320A0` — because `ewma_q_r` only advances under
`perf_active`. That is correct behaviour, not the bug.

Fixed on tidelink branch **`fix/perf-region-decode`** (2026-07-16), two commits:

1. `tidelink_apb_regs.sv` → `assign perf_reg_region = apb_region[1:0] - 2'b01;`, which
   restores writes *and* realigns all three readback regions to the documented
   `0x0A0`/`0x0C0`/`0x0E0` map. Adds `cocotb/tidelink_apb_regs/test_perf_region_decode.py`
   covering the seam between the two files, and brings `perf_reg_*` out to `tb_top`.
   **Mutation-verified on clean rebuilds:** 3 of its 4 tests fail against the raw-index
   form and all 4 pass with the fix; the 4th is a bounds guard for the subtraction and
   correctly passes either way. Existing bench 49/49, no regression.
2. `src/sw/tidelink_perf.{h,c}` — the PERF_CTRL bit definitions were rotated by one
   against the RTL (writing `FREEZE` would have cleared the timestamps; `CLEAR_COUNTERS`
   would have frozen the block), `irq_enable` was missing, and `0x0F8` was misnamed
   `DBG_SCRATCH` — it is `PERF_CONG_STATE`, and the read-only address the old
   `tl_perf_set_scratch()` wrote into the void.

Both landed on tidelink `main` and the chiplet pin was rolled to carry them, gated on a
full `make regress` (4/4: decode_tx_gate, decode_hready_loop, g2_peer_aperture,
g2_soc_pair) and a clean-rebuild `make elab` (0 errors). See PIN_POLICY.md.

`tl_ewma_credit_o` is classified `open`, so nothing bonded depends on it either way.

---

## 6. Traps

1. **`role_status[0]` is inverted.** The register field is `role_effective`;
   `role_is_master = ~role_effective` (`axi_chiplet_controller.sv:591-594`). A mirror or SW
   header that copies the bit straight across reports the role backwards.
2. **`0x2E032084` is mirrored at `0x2E033084`.** `APB_ADDR_W = 12`, so
   `tl_apb_paddr = apb_paddr[11:0]` (`tidelink_top.sv:818`) drops `paddr[12]` — a
   don't-care inside the TideLink region. The Wlink region does **not** share this (it gets
   the full `apb_paddr[12:0]`).
3. **`servo_locked_o` is TideLink's servo, not the ethernet one.** `ha1588_servo_locked` is
   the ethernet HA1588 servo. The PHC reports only one of them regardless of
   `SERVO_CTRL.SRC_SEL` — PHYSICAL_HANDOFF.md §4.4. Neither was trusted enough to bond.
4. **Read the pinned submodule, not `~/SoCLabs/tidelink`.** Line numbers and semantics
   differ. A quick tell you are in the right tree: `.sb_reset_in(1'b0)` is at
   `tidelink_top.sv:2024` (the pin) vs `:2218` (the standalone clone); RESET_ORDERING.md
   cites the former.

---

## 7. Bring-up quick reference

```c
#define D2D_TLAPB_BASE      0x2E030000u

#define WLINK_LINK_ENABLE_RESET  (D2D_TLAPB_BASE + 0x0208u)  /* bit3 = sw_reset (W1) */
#define WLINK_LINK_STATUS        (D2D_TLAPB_BASE + 0x0234u)
#define TL_ROLE_STATUS           (D2D_TLAPB_BASE + 0x2084u)
#define TL_SERVO_STATUS          (D2D_TLAPB_BASE + 0x205Cu)

/* Is the link up? (role-lock IS the up indication — see section 3) */
bool link_up      = (rd32(TL_ROLE_STATUS) >> 1) & 1u;

/* Which role did we resolve to? NOTE the inversion. */
bool is_master    = !((rd32(TL_ROLE_STATUS)) & 1u);

/* Wlink lane activity — genuinely independent of role-lock, unlike link_active. */
bool tx_active    = (rd32(WLINK_LINK_STATUS) >> 3) & 1u;
bool rx_valid     = (rd32(WLINK_LINK_STATUS) >> 4) & 1u;

/* Reset the link layer in software. */
wr32(WLINK_LINK_ENABLE_RESET, rd32(WLINK_LINK_ENABLE_RESET) | (1u << 3));

/* Congestion telemetry. Enable perf FIRST — the EWMA only advances while
 * perf_active is high, so it reads 0 on a disabled block (section 5). */
#define TL_PERF_CTRL       (D2D_TLAPB_BASE + 0x20A0u)  /* bit0 = enable      */
#define TL_PERF_ID         (D2D_TLAPB_BASE + 0x20FCu)  /* 0x50460100         */
#define TL_PERF_CONG_STATE (D2D_TLAPB_BASE + 0x20F8u)  /* [12:0] ewma credit */

if (rd32(TL_PERF_ID) == 0x50460100u) {          /* presence gate */
    wr32(TL_PERF_CTRL, rd32(TL_PERF_CTRL) | 1u);       /* enable perf */
    uint32_t ewma = rd32(TL_PERF_CONG_STATE) & 0x1FFFu;
}

/* DO NOT USE — tied 0 by a deliberate upstream ECC bypass (section 4):
 *   (rd32(WLINK_LINK_STATUS) >> 2) & 1u      // in_error_state / d2d_reset
 */
```

For a die whose link will not come up, `tx_active` / `rx_valid` at `0x2E030234` are the
most informative bits available, because they are the only ones here that are *not*
downstream of role-lock.
