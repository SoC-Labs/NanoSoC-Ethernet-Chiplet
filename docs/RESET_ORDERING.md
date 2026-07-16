# Two-die reset ordering for the source-synchronous D2D link

Closes the open item in `docs/PHYSICAL_HANDOFF.md` §2:

> **Open:** the reset ordering between `sys_poresetn`, `sys_hresetn` and the far
> die's power-up has not been analysed. Two dies powering up in an arbitrary order
> is a genuine hazard for a source-synchronous link.

This is the analysis the physical / pad-ring team needs. It is written against the
RTL, with file:line evidence. **Scope:** what the pad ring and power-sequencing must
honour so the recovered-clock domain and the auto-negotiation FSM come up safely
**regardless of which die powers first**, and what breaks if they race.

---

## 1. There are three reset regimes, not two

TideLink deliberately distinguishes `poresetn` and `hresetn`, and adds a **third**
release condition — `role_locked` — that gates the link datapath. A physical team
that treats "reset" as one net will violate the property that keeps the link safe.

| Regime | Net(s) | Asserted by | What it holds | Clears the negotiated role? |
|---|---|---|---|---|
| **Power-on** | `poresetn` (→ `tidelink_top.poresetn`, `axi_chiplet_controller.poresetn`) | die power-up / POR | role-lock latch, autoneg + I²C-slave config regs, IDELAY, the recovered-RX-clock training-mode sync | **Yes** — "only a full power-on reset can change the role" (`axi_chiplet_controller.sv:12`) |
| **System / warm** | `hresetn` (→ `.hresetn`) | SoC `sys_hresetn` | AHB/APB fabric, app-side logic | **No** — "System reset (active-low, preserves role)" (`axi_chiplet_controller.sv:109`) |
| **Bring-up gate** | `role_locked` (autoneg output, or force-latched) | auto-neg handshake completing (or the bench straps) | the **whole Wlink datapath** and **both sides of the a2l ACK-ptr CDC** | — (it *is* the role signal) |

Evidence for the split:
- Ports: `tidelink_top.sv:129-130` (`hresetn` "Active-low reset", `poresetn`
  "Power-on reset"); `axi_chiplet_controller.sv:108-109`.
- Role-lock latch resets on `poresetn` **only** — `axi_chiplet_controller.sv:536-537`
  ("Reset only by poresetn (survives warm hresetn reset)"), latch flop at
  `:642` (`always_ff @(posedge apb_clk or negedge poresetn)`), set at `:732-736`.
- In this wrapper: `tidelink_top.poresetn ← sys_poresetn`,
  `tidelink_top.hresetn ← sys_hresetn` (`PHYSICAL_HANDOFF.md:47-48`).

### The `role_locked` gate is the safety mechanism
Both reset domains of the a2l (app-to-link) replay ACK-pointer CDC are held until
`role_locked` rises, so they release on the **same** bring-up event:

```
axi_chiplet_controller.sv:2681   wire wlink_por_reset = ~poresetn | ~role_locked;   // link / write side
axi_chiplet_controller.sv:2686   assign app_clk_reset = ~hresetn | ~role_locked;    // app  / read  side
```

The `~role_locked` term is the fix for asymmetric reset-RELEASE skew
(`:443-449`, `:2682-2685`): without it the app side (released by `hresetn`) and the
link side (released by `poresetn`) come out of reset at different times and the gray
ACK-pointer synchronizer desyncs. **This gate only works if `role_locked` itself
rises at a safe moment** — see §3.

---

## 2. The recovered-clock domain is clocked by the FAR die

`pad_clk_rx` is **source-synchronous, sourced by the other die**, and asynchronous
to everything on this die (`tidelink_top.sv:235`; `PHYSICAL_HANDOFF.md:25`). It only
toggles when the far die is powered **and** transmitting. Everything in the RX
datapath — the recovered clock `phy_link_rx_rx_link_clk_w` (exposed as
`link_rx_clk_o`, `axi_chiplet_controller.sv:3530`), the 8 lane checkers, the
gpio-phy register slave — lives in that domain.

Its reset is **not** a local power-on net. It is `role_locked`, synchronized
async-assert / sync-deassert **into the recovered RX clock**:

```
axi_chiplet_controller.sv:3542   always @(posedge phy_link_rx_rx_link_clk_w or negedge role_locked)
                                     // lane_checker reset: async-assert on role_locked
                                     // falling, sync-deassert through 2 FFs on the RX clock
tidelink_top.sv:981              .link_rx_rst_n (role_locked_o)   // gpio_phy regs slave, RX-clk domain
tidelink_top.sv:919-921          "rst_n is driven directly from role_locked ... NO inverter"
```

The comment at `axi_chiplet_controller.sv:3532-3540` records exactly why the sync
exists: wiring the apb-domain `role_locked` register straight to the RX-clock reset
tree let the 8 checkers deassert on different cycles → some lanes start mid-pattern
→ the silicon-only "slave fails to converge" signature, 30 % over 10 deploys. The
sync-deassert cannot complete **until the RX clock is actually toggling** — i.e. the
domain stays safely in reset while the far die is dark, and only leaves reset once
`pad_clk_rx` is live. That is the behaviour the pad ring must not defeat.

---

## 3. What the pad ring / power sequencing must honour

1. **Standard local sequencing.** On each die, `poresetn` stays asserted through
   power-up until this die's always-on clocks are stable (`hclk` from the SoC PRMU,
   `user_ref_clk` PLL), and is the **last** reset to deassert. `hresetn` deasserts
   **at or after** `poresetn` — never before it. (If `hresetn` releases first, the
   app side of the a2l CDC would try to leave reset while the link side is still
   held — the exact skew the `~role_locked` gate exists to catch, but do not lean on
   one safety net alone.)

2. **The recovered-RX-clock reset must have exactly one release path: `role_locked`.**
   The pad ring must **not** provide any independent, power-on-driven early release
   of the RX-domain reset. If a physical team adds a local async reset to those
   flops that deasserts on this die's `poresetn`, they break the "held until the RX
   clock is live" property and re-introduce the metastable-capture window.

3. **`role_locked` must not rise before the far die is transmitting.** This is the
   crux. `role_locked` gates both the RX-domain reset (§2) and both sides of the a2l
   CDC (§1). It is safe **only** if it is a true function of far-die presence:
   - **Production intent:** re-enable real auto-negotiation. `NEGO_CFG_RESET`
     defaults to `7'h00` (autoneg OFF → FSM parks in `ST_BYPASS`, SW drives
     bring-up) — `tidelink_top.sv:118-123`, `PHYSICAL_HANDOFF.md:105-107`. With
     `7'h61` the FSM only latches role-lock after the mask handshake with the peer,
     so `role_locked` intrinsically waits for the far die.
   - **Landmine — the current bench straps defeat this.** `tidelink_top.sv:2039-2040`
     ties `apb_debug_unlock_i = 1'b1` and `mask_hs_bypass_i = 1'b1`, which lets a SW
     `ROLE_CFG` W1S latch `role_locked` **without any autoneg handshake**
     (`:2032-2038`). Under those straps SW can force-lock the role — and thus release
     the RX-domain reset and the a2l CDC — **while `pad_clk_rx` is still dead.** For a
     die that must survive an arbitrary power-up order, either drop these straps in
     favour of real autoneg, **or** gate the SW bring-up recipe's `ROLE_CFG` W1S on an
     independent "RX clock present / far die alive" indication (TideLink ships a
     `clkfreq_check` on `pad_clk_rx` — `flists/tidelink_clkfreq_check.flist`). **Never
     latch role-lock on a dead RX clock.**

4. **Auto-neg root election needs a tiebreak set at the pad ring.** Two dies that
   power simultaneously and both present `nego_priority_i = 0` have **no tiebreak**,
   and TideChart's `DEVICE_CLASS` defaults to `16'h0001` — "the value that reliably
   wins", so *every* die boots claiming host (`PHYSICAL_HANDOFF.md:96-104`). The pad
   ring / OTP must strap `nego_priority_i` (and/or `role_strap_i`, `DEVICE_CLASS`)
   **differently on the two dies**, or the election is a coin-flip on the LFSR and
   may never converge — independent of reset ordering.

5. ~~**`d2d_reset_o` is an output; decide whether it is a cross-die reset.**~~
   **RESOLVED 2026-07-16 — the question was malformed. `d2d_reset_o` is NOT a reset,
   and it is TIED LOW BY CONSTRUCTION.** It is unbonded as of the same date
   (`PIN_MAP.md` §4c). There is no sequencing constraint here and nothing to
   synchronize; a reset loop is impossible because the signal cannot assert.

   `sb_reset_in` is tied `1'b0` and `sb_reset_out` drives `d2d_reset_o`
   (`tidelink_top.sv:2024-2025`), but `sb_reset_out` is Wlink's RX
   `in_error_state = (state == 2'h2)`, and that state has no entry edge —
   `WlinkRxLinkLayer.v:1305` writes `2'h2` only inside `else if (state == 2'h2)`, and
   reset forces `2'h0`.

   **The dead FSM branch is a symptom.** The cause is that the ECC syndrome checker is
   a deliberate, documented bring-up bypass — `WlinkEccSyndrome.v:306-308` hardwires
   `corrupted = 1'h0` because the Hamming(33,24) decoder mismatches the TX-side ECC
   polynomial and flagged every header corrupt at 25 MHz, blocking all traffic. With
   `corrupted` constant, the ERROR entry is dead code. Full detail:
   `STATUS_REGISTERS.md` §4.

   **The real issue this exposes is not reset ordering — it is that the link runs with
   no header ECC protection.** `sb_reset_out`/`sb_reset_in` is a cross-die "my receiver
   is in error, stop transmitting" handshake (`sb_reset_in`'s only consumer anywhere in
   Wlink is `lltx_io_enable`), and it is inert at both ends. Payload CRC still applies.
   The team already knew ECC detection was dead — `axi_chiplet_controller.sv:2549-2550`
   repurposed the dead ECC counter field to `SYNC_DETECTED_COUNTER`. Raised upstream,
   not fixed here: the real fix is a syndrome-polynomial audit against the TX-side ECC
   RTL with bench re-validation, and getting it wrong stops all link traffic.

   **Note for anyone looking for the software link reset:** it is **not** clearing
   `role_locked` — `role_lock_reg` is W1S with POR-only clear
   (`axi_chiplet_controller.sv:545`, `:645`). It is Wlink's `sw_reset`,
   `0x2E030208` bit[3], which drives `por_reset` into all three link clock domains.

6. **IDELAY reset (FPGA only).** `idelay_rst = ~poresetn` (`tidelink_top.sv:2248`);
   on ASIC `USE_IDELAY=0` makes the RX delay a bit-exact passthrough and this ties
   off (`PHYSICAL_HANDOFF.md:26`). No cross-die ordering constraint, listed for
   completeness.

---

## 4. Failure mode if they race

The canonical failure is **silent corruption of the a2l ACK-pointer synchronizer at
bring-up** — the same mechanism the `WlinkGenericFCReplayAddrSync_18` override fixes
(see `docs/PHYSICAL_HANDOFF.md` §4.5 and the item-1 flist patch), generalized to the
two-die case.

Sequence when the local die wins the power-up race (far die still dark, or
`role_locked` force-latched on a dead `pad_clk_rx`):

1. `pad_clk_rx` is not yet cleanly toggling, so the recovered-clock domain has no
   valid edges.
2. If `role_locked` is allowed to rise anyway (bench straps, §3.3), the RX-domain
   reset (`axi_chiplet_controller.sv:3542`) and both a2l CDC resets
   (`:2681`, `:2686`) deassert.
3. On the **first** real RX edges when the far die finally transmits, the RX-domain
   flops and the gray ACK-pointer synchronizer sample metastable / stale state.
4. The replay ACK pointer (`raddr` / `synced_ack`) latches a **lap-ahead** value —
   e.g. `0x1F` while the write pointer is `15` — so `a2l_full = 1` →
   `app_ready = 0` → the FCSM wedges (state 4) → **the local die's TX never emits**
   → the far die's RX FIFO is never written.
5. Because at bring-up no legitimate ACK follows (the guard clamps `w_inc`),
   `raddr` **never self-corrects** → a **permanent false-FULL wedge**: the link
   delivers a handful of writes (~6) and stops.

Properties that make this dangerous:
- **Invisible to simulation.** An idealised single-/coherent-clock sim resolves the
  demets cleanly and never exposes it (the override header says so verbatim,
  `WlinkGenericFCReplayAddrSync_18.v:100-101`; `PHYSICAL_HANDOFF.md:170-172`,
  `219-223`). A green sim proves nothing about reset ordering.
- **On the TX path a chiplet actually uses** to write the far die — the same
  direction as the peer aperture write (`PHYSICAL_HANDOFF.md:221`).
- A second, distinct symptom on the RX-training side: an un-synchronized lane-checker
  reset release yields the "slave fails to converge" 30 %-of-deploys signature
  (`axi_chiplet_controller.sv:3535-3540`).
- Plus the autoneg root-election coin-flip (§3.4) if both dies present equal priority.

**Net:** power sequencing that lets `role_locked` (hence the recovered-clock and
a2l-CDC reset releases) fire before `pad_clk_rx` is live produces a link that
bring-up-tests may pass in sim and then wedges on silicon, non-recoverably, after a
handful of words — the worst class of post-tapeout bug. Holding those releases behind
a genuine far-die-present condition (real autoneg, or an RX-clock-detect gate on the
SW recipe) is what makes the link safe **regardless of which die powers first.**

---

## 5. Concrete asks for the pad ring / power sequencing

- Deassert order per die: clocks stable → `poresetn` → `hresetn` (never `hresetn`
  before `poresetn`).
- Do **not** add any local/power-on early-release to the recovered-RX-clock reset
  tree; its only release is `role_locked`, sync-deasserted on `pad_clk_rx`.
- Gate `role_locked` on real far-die presence: production autoneg (`NEGO_CFG=7'h61`),
  or an RX-clock-detect (`clkfreq_check` on `pad_clk_rx`) guarding the SW `ROLE_CFG`
  W1S. Drop or interlock the `mask_hs_bypass`/`apb_debug_unlock` bench straps for
  silicon.
- Strap `nego_priority_i` (and `role_strap_i` / TideChart `DEVICE_CLASS`)
  **asymmetrically** on the two dies so the root election has a tiebreak.
- ~~Decide `d2d_reset_o` wiring; if cross-die, synchronize it and prove there is no
  reset loop.~~ **Moot — `d2d_reset_o` is tied low by construction and is now unbonded
  (§3.5, `STATUS_REGISTERS.md` §4).** Raise the underlying Wlink RX-error defect
  upstream instead.
- Owe a lint + SpyGlass CDC signoff on the integrated top with the taped-out
  configuration — it would independently flag any of the above
  (`PHYSICAL_HANDOFF.md:247-248, 251`).
