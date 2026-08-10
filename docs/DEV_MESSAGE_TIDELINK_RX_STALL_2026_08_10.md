# To the TideLink dev — the FC adapter has no RX stall watchdog, and `tl_fc_l2a` is shared three ways

**From:** nanoSoC eth-chiplet integration (lint/RTL-audit session, 2026-08-10).
**Repo HEADs this was read against:** `tidelink` @ `28409f5`, `tidechart` @ `f298d73`.
**Related, but DIFFERENT bugs — do not conflate:** TL-009 a2l CDC self-latch
(`DEV_MESSAGE_A2L_SELFLATCH_SILICON_2026_08_09.md`), the anchor/eye-margin lottery,
and the AXI data-node recovery gap. This is a fourth, structurally distinct mechanism.

---

## TL;DR — the root cause is NOT in TideLink, but one real defect here is

Found while triaging an unrelated HAL `*E,TERMST` lint error on TideChart's election FSM.
The *root cause* is in **`tidechart`** (a settled election FSM permanently deasserts its
RX accept, and the crossbar routes election beats to it unconditionally). That half is
being raised with TideChart separately.

**What is yours, and is independently actionable regardless of what TideChart does:**

`tidelink_fc_adapter.sv` has a **TX** stall watchdog — added as the "Bug-A wedge-mechanism
fix (2026-06-11)", because an unbounded stall there was a proven silicon wedge — and **no
RX equivalent**. Meanwhile `tl_fc_l2a` is a **shared** channel feeding three destinations.
So *any* one destination that stops asserting ready takes down the other two, forever, with
no timeout and no error.

```
grep -c tx_stall tidelink/src/rtl/tidelink_fc_adapter.sv  ->  10
grep -c rx_stall tidelink/src/rtl/tidelink_fc_adapter.sv  ->   0
```

The class of bug you already fixed on TX is unbounded on RX. TideChart is merely the first
peripheral found that can hold ready low forever — the exposure is architectural, not
TideChart-specific.

---

## ASK #1 (the one that matters) — bound the RX stall, mirroring TX

### The mechanism, in your file

`tidelink/src/rtl/tidelink_fc_adapter.sv`:

```systemverilog
// :622-624
wire rx_accept = tl_fc_l2a_valid & (rx_state_r == RX_IDLE) & ~rx_pending_r;
assign tl_fc_l2a_accept = rx_accept;
```

`tl_fc_l2a_accept` requires `rx_state_r == RX_IDLE`. And the only exit from
`RX_ADDR_PHASE` for an ext packet is:

```systemverilog
// :666 (and the mirrored clause in the rx_pending_r clear at :636-638)
end else if (rx_is_ext) begin
    if (tc_axis_rx_tready && !puf_rsp_valid_r)
        rx_state_next = RX_IDLE;
end
```

There is no timeout, no drop path, and no error escape. If `tc_axis_rx_tready` stays low,
`rx_state_r` never returns to `RX_IDLE`, so `tl_fc_l2a_accept` is deasserted **permanently**.

### Why that is a whole-die outage, not a TideChart-local stall

`:612-619` decodes `tl_fc_l2a` into three destinations:

| `rx_pkt_type` | destination | consequence when blocked |
|---|---|---|
| `PKT_FIFO_DATA` | D2D RX **data FIFO** | all inbound cross-die data stops |
| `PKT_EXT` | TideChart | (the blocker itself) |
| everything else | FC **sideband APB** config path | you cannot reconfigure your way out |

One undrainable ext beat kills all three, **including the sideband path you would use to
recover**. That is the part that makes this severity-HIGH rather than a peripheral nuisance.

### What we'd suggest

A direct mirror of the TX watchdog: a counter armed whenever `rx_state_r != RX_IDLE`
and the active target's ready is low, expiring to a defined policy. The policy is your
call and is the real design decision — the options we can see:

- **drop the beat** and return to `RX_IDLE` (keeps the channel live; loses one packet),
- **drop + sticky error status bit** so software can see it happened,
- **drop + raise an FC error/interrupt** so it is not silent.

Our preference is drop + sticky status at minimum: a silent drop on a link with documented
framing history will be very hard to debug later. But the policy belongs to you.

There is also a **narrower** variant worth considering on its own merits: gate the ext-packet
path so that a `PKT_EXT` destination that is not ready cannot block `PKT_FIFO_DATA` and the
sideband APB. That decouples the blast radius even if the watchdog never fires. It is more
invasive than the watchdog, so we mention it as a second-order option, not the ask.

---

## ASK #2 (small) — confirm the shared-channel decode is intended

`tl_fc_l2a` fanning out to data FIFO + TideChart + sideband APB with a single shared
`accept` is what turns a peripheral backpressure into a total receive outage. We are
reading this as a deliberate area/pin trade-off rather than an oversight, but we would
rather ask than assume. If it *is* deliberate, the watchdog in ASK #1 is the mitigation
and there is nothing further; if it is not, the decouple is the better fix.

---

## What is NOT yours — raised with TideChart separately

For completeness, so you can see the whole chain and judge how much the watchdog buys you:

1. **`tidechart_election_fsm.sv`** — `claim_rx_accept` is defaulted to 0 every cycle
   (`:282`, `:290`, `:304`) and asserted in exactly one place, `:370`, inside `ST_LISTEN`.
   The `ST_SETTLED` arm (`:409-420`) assigns `election_done`, `is_root`, `uplink_*` and
   nothing else — so a settled FSM holds its accept low forever.
2. **`tidechart_crossbar.sv:209-215`** — `is_elect` is decoded from the wire subtype
   **alone**, with no qualification on election-FSM state, and it is the **first** arm of
   the `tc_axis_rx_tready` priority mux. So a settled node's dead accept also locks out
   enum, link-state broadcast and PUF on that port.
3. **`src/rtl/tidechart_shim.sv`** (ours, the eth-chiplet) — pure combinational flattener,
   zero `always` blocks, no skid buffer. The stall propagates straight through to you. We
   have looked at absorbing it here; a skid buffer in the shim would defer the wedge by
   exactly one beat, not prevent it, so it is not a fix.

TideChart fixing (1) or (2) removes *this* trigger. It does not bound the class — any future
`PKT_EXT` consumer with a ready that can stall re-opens it. That is why ASK #1 stands on its
own and we would not want it closed as "fixed in TideChart".

---

## Trigger — no fault required

`ELECTION_TIMEOUT_DEFAULT = 16'd4096` cycles ≈ **20 µs at 200 MHz**
(`tidechart_election_fsm.sv:43`, runtime-overridable via `TC_TIMEOUT`). Election start is
**not synchronised across the link**. So:

1. Link reaches data mode (FCSM ≥ 4).
2. Die A's software writes `TC_CTRL[0]`; A floods its claim, times out, enters `ST_SETTLED`.
3. Die B's software writes `TC_CTRL[0]` **>20 µs later**, reaches `ST_CLAIM_TX`, and
   unconditionally floods its claim at A.
4. That beat lands on a settled A → A's entire FC receive path wedges.

Other routes to the same place: the peer restarting its election, a peer-side reset or
watchdog, or a corrupted beat whose `[45:32]` decodes as the election subtype.

**Note the interaction with the dual-root behaviour already observed on silicon:** both dies
settling independently is exactly the precondition, and the prescribed recovery for dual-root
— restart the election — is itself the "late claim at a settled peer" that triggers this. The
recovery action is a trigger. (TideChart `3005d11 fix(election): harden root election against
dual-root (I6–I9)` is in the tree; the `ST_SETTLED` accept gap survives it, since the gap is
in what a settled FSM does with a late claim, not in how it converges.)

---

## Recovery on the SHIPPING eth-chiplet die — there is none that is autonomous

Verified against the generated chip wrapper and the interconnect decoders:

| Path | Status |
|---|---|
| Local CPU firmware writing `TC_CTRL[3]` | Path exists and is link-independent — but **no firmware calls it**; `tidechart/src/sw/tidechart.h` has zero includers in the tree |
| SWD (`dap_swclktck`/`dap_swditms`) | **Bonded, works** (`build/chip/rtl/nanosoc_eth_chiplet_chip.v:36-37`) |
| HOSTIO4 (`hostio4_p1_in[6:0]`) | **Bonded, works** (`:55`) |
| `eth_ss_0` chiplet backdoor | **TIED OFF in silicon** (`:129-131`) — the KR260 bring-up path does not exist on the die |
| Remote die over TideLink | **Structurally impossible** — the `D2D_M` initiator decoder exposes only `MI4` (mailbox) and `MI6` (shared SRAM); the D2D window `MI12` is not in its port list |
| Hardware-autonomous | **None** — `ST_SETTLED` ignores `link_active`, and there is no RX stall watchdog |

A wedged deployed pair recovers only via an attached debugger or a power cycle. Those are
bench instruments, not field recovery. This is the argument for the watchdog being in
hardware rather than handled in software.

Two adjacent traps found while tracing, both TideChart's: `start` is sampled only in
`ST_IDLE`, so a software "re-elect" on a settled die is a silent no-op and anything waiting
on `election_done` returns instantly with a stale result; and `TC_CTRL[3]` drives both
`election_restart` and `rt_clear`, so you cannot re-arm without wiping the route table.

---

## Status of the evidence — please read this before acting

**Every RTL fact above was confirmed by direct inspection** at the HEADs named at the top,
and the `file:line` references are current.

**The trigger sequence is a structural argument from that code. It has NOT been demonstrated
in simulation or on silicon.** We are sending it now rather than after the experiment because
the recovery picture (no autonomous escape on shipping silicon) makes it worth your eyes
early, but it should not be treated as certain, and we are not asking you to merge anything
blind.

Two things that specifically weaken confidence, in fairness:

- **No TideChart `PKT_EXT` has ever been observed traversing the real link.**
  `tidelink/cocotb/tidechart_tidelink_pair/README.md` records this. The exact packet that
  triggers the chain has never been exchanged in sim or on silicon — so there may be a
  reason upstream that it never arrives in this state that we have not found.
- **No test covers the shipping configuration.** Every TideChart bench runs `NUM_PORTS=2`;
  the chiplet ships `NUM_PORTS=1` (`src/rtl/nanosoc_eth_chiplet.sv:967`). The only
  `NUM_PORTS=1` environment, `verif/g2_soc_pair`, never injects an election beat into a
  settled FSM. TideChart also contains zero `assert`/`cover property`.

## The experiment that settles it

At the shipping `NUM_PORTS=1`: settle the election, inject one election-subtype beat, then
watch `tl_fc_l2a_accept` and the D2D RX data FIFO. If the mechanism is as described,
`tl_fc_l2a_accept` goes low and stays low, and a subsequent cross-die write never lands.

We are planning this as a short cocotb test in `verif/g2_soc_pair` (ours to write — it is our
integration and our shipping config). We will send the result either way, including if it
refutes this. If you would rather see it before spending time on the watchdog, say so and we
will hold; if you want the watchdog anyway on the "TX class, unbounded on RX" argument alone,
that is also a reasonable read and we would not argue with it.

Full internal analysis, with the per-link derivation: `docs/TC_SETTLED_RX_WEDGE.md`.
