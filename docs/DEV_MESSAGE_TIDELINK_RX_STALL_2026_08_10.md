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

## Trigger — and what the G1 data-mode gate does and does not fix

**Your `tl_data_mode_o` contract fix is landed on both sides.** `tidelink_top.sv` exports it,
and the chiplet consumes it — `nanosoc_eth_chiplet.sv:398/:897/:985` declare `tc_data_mode`,
take it off `tidelink_top`, and feed it to the shim's `link_active`. So
`TIDECHART_G1_SEQUENCING_CONTRACT.md` §3.2 ("NOT APPLIED — different repo/owner") is **stale;
that swap has landed.** Thank you — it does close dual-root, and it also removes what would
otherwise have been the dominant trigger for the bug below.

It does not close this one, because **the data-mode strobe gates RELEASE, not ARMING**:

`tl_data_mode_o` is a bilateral link milestone, so the two dies release within ~320 ns of each
other (your own bench measures exactly that). But `election_start` (`TC_CTRL[0]`) is still an
independent software write per die, and `ELECTION_TIMEOUT_DEFAULT = 16'd4096` ≈ **20 µs at
200 MHz** (`tidechart_election_fsm.sv:43`). So:

1. Die A's software arms `TC_CTRL[0]`. Data mode arrives, A is released, floods, times out
   after ~20 µs, enters `ST_SETTLED`.
2. Die B's software arms `TC_CTRL[0]` **any time more than ~20 µs later** — B is released
   immediately (data mode is long since high, and the strobe is monotonic by construction, as
   your §3.1 establishes), reaches `ST_CLAIM_TX`, and unconditionally floods its claim at A.
3. That beat lands on a settled A → A's entire FC receive path wedges.

On the shipping die, arming is **not** synchronised and cannot be: no firmware arms it at all
(`tidechart/src/sw/tidechart.h` has zero includers), so arming is debugger- or host-driven per
die. A >20 µs skew between two independently-driven arms is the *normal* case, not the corner.
The G1 gate made the release deterministic; it left the arm free-running.

Two further routes survive G1 entirely:

* **Re-election.** `TC_CTRL[3]` on one die after both have settled floods a claim at a settled
  peer — that is the trigger, exactly. Note this is also the prescribed recovery for dual-root,
  so on a dual-rooted pair the recovery action wedges the peer.
* **A corrupted beat** whose `[45:32]` decodes as `SUBTYPE_ELECTION`, on a link with documented
  framing history.

(TideChart `3005d11 fix(election): harden root election against dual-root (I6–I9)` is also in
the tree; the `ST_SETTLED` accept gap survives it, because the gap is in what a settled FSM
does with a *late* claim, not in how it converges.)

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

## UPDATE — DEMONSTRATED IN SIMULATION, on your own pair bench

Since the first draft of this message we ran the experiment. **The wedge
reproduces**, in both directions, on `cocotb/tidechart_tidelink_pair` with a real
TideLink pair and the real `tl_data_mode_o` gate. New test:
`test_tc_pair_late_claim.py` (yours to keep or move — it is a variant of your
`test_tc_pair_election_datamode.py`).

| victim | UNFIXED | FIXED |
|---|---|---|
| die_b @ `ST_IDLE` | 6937 ELECTION beat-cycles presented, **0 handshaken**, `rx_idle` 126/7063 | 2 presented, **1 handshaken**, `rx_idle` 7061/7063 |
| die_a @ `ST_SETTLED` | 21939 presented, **0 handshaken**, `rx_idle` 125/22064 | 2 presented, **1 handshaken**, `rx_idle` 22062/22064 |
| verdict | **FAIL (WEDGE)** | **PASS** |

`rx_idle` is your `u_fc_adapter.rx_state_r == RX_IDLE`. Collapsing to ~0 is the
adapter stuck in `RX_ADDR_PHASE`, which is exactly `tl_fc_l2a_accept` dead.

**One correction to this message's own framing:** the un-armed (`ST_IDLE`) case
matters more than the settled one, and we had missed it. An un-armed die wedges
identically — and un-armed is the shipping die's *permanent* state, since no
firmware arms TideChart. The two differ in recoverability: the `ST_IDLE` wedge
self-clears if that die is later armed (it enters `ST_LISTEN` and drains the stuck
beat); the `ST_SETTLED` one does not.

**We have fixed the root cause in TideChart** — drain (accept and discard) in the
non-listening states. That closes this instance. **ASK #1 below still stands**,
because the drain does not bound the class: any future `PKT_EXT` consumer with a
ready that can stall re-opens it, and your RX path still has no timeout.

### Two things in YOUR tree that we changed, and you should take

1. **`tb_tc_pair.sv` never connected `tidechart_shim.device_strap`.** TideChart's
   I6 dual-root hardening (`3005d11`) added that port; the bench never wired it,
   so it floated. `own_random_r = {device_strap, lfsr[7:0]}` was X, the claim TX
   word was X-poisoned, and **the X propagated into the Wlink FCSM state
   register** — which is why `PairTB.fcsm_state()` returns −1 and
   `test_tc_pair_election_datamode` **fails** at HEAD. We wired master `8'h00` /
   slave `8'h01` per the FSM's documented convention; both sibling tests
   (`test_tc_pair_smoke`, `test_tc_pair_election_datamode`) pass again.
2. **The bench Makefile assumes tidelink is a SIBLING of the chiplet repo.**
   `CHIPLET_HOME ?= $(realpath $(TIDELINK_HOME)/../nanosoc-ethernet-chiplet)`
   resolves empty when tidelink is used as a **submodule** of that repo (the
   shipping arrangement), and the build dies with
   `No rule to make target '/src/rtl/tidechart_shim.sv'`. We worked around it with
   an explicit `CHIPLET_HOME=` on the command line rather than edit your default.

## Status of the evidence — please read this before acting

**Every RTL fact above was confirmed by direct inspection** at the HEADs named at the top,
and the `file:line` references are current.

**The trigger sequence WAS a structural argument from that code; it is now demonstrated in
simulation** — see the UPDATE above, with a before/after mutation in both directions. It has
**not** been reproduced on silicon, and we are not asking you to merge anything blind.

What still weakens confidence, in fairness:

- **Not reproduced on silicon.** The FPGA bitstreams would need a TideChart in the block
  design; per your own G1 contract §3.3 no KR260 BD instantiates `tidechart_shim`, and the IP
  needs re-packaging before the `tl_data_mode_o` pin is even connectable.
- **Not covered in the shipping configuration.** This bench is `NUM_PORTS=2`; the chiplet
  ships `NUM_PORTS=1` (`src/rtl/nanosoc_eth_chiplet.sv:967`). The mechanism is not
  port-count-dependent as far as we can see, but we have not shown that.
- **The corrupted-beat trigger is untested** — only the arming-skew and un-armed paths were
  exercised.
- **TideChart contains zero `assert`/`cover property`**, so nothing would catch a regression
  of this in the future beyond the one new test.

## What we would like back

Not agreement with our analysis — a decision on ASK #1. The drain we landed in TideChart
closes this instance; whether the adapter should also **bound the class** with an RX watchdog
is your call, and the "TX class, unbounded on RX" argument stands on its own regardless of
what TideChart does. If you would rather see it reproduced at `NUM_PORTS=1` or on silicon
first, say so and we will queue that instead.

Full internal analysis, with the per-link derivation: `docs/TC_SETTLED_RX_WEDGE.md`.
