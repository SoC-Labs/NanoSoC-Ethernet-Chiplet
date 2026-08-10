# TideChart ST_SETTLED starves the shared FC RX channel — cross-die receive wedge

**Status: OPEN. Found 2026-08-10 while triaging a HAL `*E,TERMST` lint error on
`tidechart_election_fsm`. The lint error itself was benign and is now fixed; this
is what was underneath it.**

**Severity: HIGH.** One election-subtype FC beat arriving at a die whose election
FSM has settled permanently stalls that die's **entire cross-die receive path** —
not just TideChart. No fault is required to trigger it: ~20 µs of boot skew
between two independently-booting dies is enough. There is no
hardware-autonomous recovery.

---

## 1. Mechanism

Every link below was verified by reading the RTL. `file:line` is given for each.

### 1.1 `ST_SETTLED` never accepts on the RX channel

`claim_rx_accept` is defaulted to 0 every cycle
(`tidechart/src/rtl/tidechart_election_fsm.sv:290`, also :282, :304) and is
asserted in exactly **one** place — `:370`, inside `ST_LISTEN`. The `ST_SETTLED`
datapath arm (`:409-420`) assigns `election_done`, `is_root`, `uplink_*` and
nothing else. So in `ST_SETTLED`, `claim_rx_accept` is permanently 0.

`tidechart/src/rtl/tidechart_controller.sv:473` wires it straight to the
crossbar: `.claim_rx_accept (elect_rx_accept)`.

### 1.2 The crossbar routes election beats to that dead accept, unconditionally

`tidechart/src/rtl/tidechart_crossbar.sv:208-218`:

```systemverilog
wire [13:0] rx_sub_acc = tc_axis_rx_tdata[gi][45:32];
wire        is_elect   = (rx_sub_acc == SUBTYPE_ELECTION);

assign tc_axis_rx_tready[gi] =
    (is_elect) ? elect_rx_accept[gi] :        // <-- FIRST arm, wins the priority
    (is_puf_rsp && ...) ? puf_rx_tready :
    ...
```

**`is_elect` is decoded from the wire subtype alone.** It carries no
qualification on election-FSM state, and it is the *first* arm of the priority
mux — so enum, the link-state agent and PUF are all locked out of that port too.
Result: `tc_axis_rx_tready` is stuck at 0 for as long as the beat is presented.

### 1.3 Nothing buffers it

`src/rtl/tidechart_shim.sv` is a pure combinational flattener —
`tc_axis_rx_tready` is an `output wire` connected directly at `:190`, and the
file contains **zero `always` blocks**. No skid buffer, no FIFO. The stall
passes straight through.

### 1.4 The stall reaches a SHARED channel

`tidelink/src/rtl/tidelink_fc_adapter.sv:666` — for an ext packet the RX FSM
leaves `RX_ADDR_PHASE` only on `tc_axis_rx_tready && !puf_rsp_valid_r`. So
`rx_state_r` never returns to `RX_IDLE`. And `:622-624`:

```systemverilog
wire rx_accept = tl_fc_l2a_valid & (rx_state_r == RX_IDLE) & ~rx_pending_r;
assign tl_fc_l2a_accept = rx_accept;
```

`tl_fc_l2a_accept` is therefore permanently deasserted.

**This is the blast radius.** `tl_fc_l2a` is shared — `:612-619` decodes it into
three destinations:

| packet type | destination |
|---|---|
| `PKT_FIFO_DATA` | the **D2D RX data FIFO** |
| `PKT_EXT` | TideChart |
| everything else | the **FC sideband APB config path** |

One undrainable election beat kills all three. This is not a TideChart-internal
stall; it is the die's whole cross-die receive path.

### 1.5 The asymmetry that gives the game away

The same adapter already carries a **TX** stall watchdog, added as the "Bug-A
wedge-mechanism fix (2026-06-11)" because an unbounded stall here was a proven
silicon wedge. There is no RX equivalent:

```
grep -c tx_stall tidelink/src/rtl/tidelink_fc_adapter.sv  ->  10
grep -c rx_stall tidelink/src/rtl/tidelink_fc_adapter.sv  ->   0
```

The lesson was learned on TX and never applied to RX.

---

## 2. Trigger — no fault required

`ELECTION_TIMEOUT_DEFAULT = 16'd4096` cycles
(`tidechart_election_fsm.sv:43`), ≈20 µs at 200 MHz, runtime-overridable via
`TC_TIMEOUT`.

1. Link reaches data mode (FCSM ≥ 4).
2. Die A's software writes `TC_CTRL[0]`; A runs `ST_IDLE → ST_WAIT_LINKS →
   ST_CLAIM_TX` and floods its claim.
3. **There is no cross-die synchronisation of election start.** Die B has not
   written `TC_CTRL[0]` yet.
4. A's quiescence timeout expires → **A enters `ST_SETTLED`**. A is now root,
   silent, and deaf.
5. Die B's software writes `TC_CTRL[0]` more than 20 µs later → B reaches
   `ST_CLAIM_TX` and unconditionally floods its claim to A.
6. That beat lands on A in `ST_SETTLED` → §1 → **die A's entire FC receive
   channel is permanently wedged.**

Other paths to the same place: the peer restarting its election (i.e. **the
prescribed dual-root recovery action wedges the peer's link**), a peer-side
reset or watchdog, or a corrupted FC beat whose `[45:32]` decodes as the
election subtype — on a link with documented framing history.

---

## 3. Recovery on the SHIPPING die

Verified against the generated chip wrapper and the interconnect decoders, not
against the FPGA build.

| Path | Status |
|---|---|
| Local CPU0/CPU1 firmware write to `TC_CTRL[3]` | Path exists and is link-independent — but **no firmware calls it.** `tidechart/src/sw/tidechart.h` has zero includers anywhere in the tree |
| **SWD** (`dap_swclktck`/`dap_swditms`) | **Bonded** — `build/chip/rtl/nanosoc_eth_chiplet_chip.v:36-37`. Reaches the D2D window. **Works** |
| **HOSTIO4** (`hostio4_p1_in[6:0]`) | **Bonded** — `:55`. **Works** |
| `eth_ss_0` chiplet backdoor | **TIED OFF in silicon** — `:129-131` (`htrans 2'b00`, `haddr 32'd0`, …). The KR260 bring-up path **does not exist on the die** |
| Remote die over TideLink | **Structurally impossible.** The `D2D_M` initiator decoder exposes only `MI4` (mailbox) and `MI6` (shared SRAM); a CPU initiator exposes `MI0`–`MI12`. The D2D window (`MI12`) is not in its port list at all |
| Hardware-autonomous (timeout / link-down) | **None exists.** `ST_SETTLED` ignores `link_active`; there is no RX stall watchdog |

**Net:** a wedged deployed pair recovers only via an attached debugger (SWD or
HOSTIO4) or a power cycle. Those are bench instruments, not field recovery.

Two further traps found while tracing this:

- **`start` is ignored in `ST_SETTLED`** — it is sampled only in `ST_IDLE`. So a
  "re-elect" from software on a settled die is a silent no-op, and any helper
  that waits on `election_done` returns instantly with a stale result.
- **`TC_CTRL[3]` drives both `election_restart` and `rt_clear`.** You cannot
  re-arm the election without wiping the route table.

---

## 4. Why no gate caught this

- **Lint cannot see it.** It is not a width, driver, or structural error. HAL's
  `TERMST` pointed at the same state for an unrelated reason and was benign.
- **No test exercises it.** Every TideChart testbench runs `NUM_PORTS=2`; the
  chiplet ships `NUM_PORTS=1` (`src/rtl/nanosoc_eth_chiplet.sv:967`). The only
  `NUM_PORTS=1` environment, `verif/g2_soc_pair`, never injects an election beat
  into a settled FSM. There is no link-down-after-settle test, no
  re-election-on-link-loss test, and no corrupted-claim test.
- **No assertions.** `tidechart/` contains zero `assert`/`cover property`.
- **It has never crossed the wire.** `tidelink/cocotb/tidechart_tidelink_pair/README.md`
  records that no TideChart `PKT_EXT` has ever been observed traversing the real
  link — so the exact packet that triggers this has never been exchanged in
  simulation or on silicon.

---

## 5. Candidate fixes

Not yet evaluated for equivalence or area; listed with the trade-off each makes.

| # | Fix | Effect | Risk |
|---|---|---|---|
| **A** | Qualify `is_elect` in the crossbar with the election FSM being in a state that can accept — fall through to the other arms otherwise | Election beats stop hijacking the port when nobody is listening | Changes crossbar arbitration; needs care that a legitimate claim during `ST_LISTEN` is unaffected |
| **B** | Consume-and-drop election beats in `ST_SETTLED` (assert `claim_rx_accept` and discard) | Smallest change; keeps the channel draining | Silently discards a peer's claim — acceptable only if a settled node is *meant* to ignore claims. Decide that deliberately |
| **C** | Add the missing **RX stall watchdog**, mirroring the TX one | Bounds *every* RX stall, not just this one | Does not fix the root cause; defines a drop/error policy on timeout |

**A and C are complementary** — A removes this instance, C bounds the class. B is
the cheapest but encodes a protocol decision that should be made explicitly.

Whatever is chosen, the two dies also need an answer to the underlying protocol
gap: **election start is not synchronised across the link**, and a settled node
has no defined response to a late claim.

---

## 6. The test that settles it

At the shipping `NUM_PORTS=1`: settle the election, inject one election-subtype
beat, then watch `tl_fc_l2a_accept` and the D2D RX data FIFO. If the mechanism is
as described, `tl_fc_l2a_accept` goes low and stays low, and a subsequent
cross-die write never lands.

That is a short cocotb test in `verif/g2_soc_pair`, and it is the single
highest-value missing test in the tree — it exercises the shipping
configuration, the shared channel, and the cross-die path in one go.

---

## 7. Provenance

Found by adversarial review during HAL error triage, then verified link by link
against the RTL. The `TERMST` lint error that led here was real but benign, and
is fixed separately (`state_next = restart ? ST_IDLE : ST_SETTLED;`, LEC
equivalent 242/242).

Everything in §1 and §3 was confirmed by direct inspection. The trigger sequence
in §2 is a structural argument from that code, **not yet demonstrated in
simulation** — §6 is the experiment that would demonstrate it, and it should be
run before this is treated as certain.
