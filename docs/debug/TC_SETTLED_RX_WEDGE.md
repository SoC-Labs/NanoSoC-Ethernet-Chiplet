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

**First, what the G1 data-mode gate already fixed.** `tl_data_mode_o` is landed
on both sides — `tidelink_top.sv` exports it and the chiplet consumes it
(`nanosoc_eth_chiplet.sv:398` `wire tc_data_mode`, `:897` `.tl_data_mode_o`,
`:985` `.link_active(tc_data_mode)`). `tidelink/docs/TIDECHART_G1_SEQUENCING_CONTRACT.md`
§3.2 still says "NOT APPLIED — different repo/owner"; **that is stale, it has
landed.** So the naive "20 µs of boot skew" trigger is *not* available: release is
gated on a bilateral link milestone and the two dies release ~320 ns apart.

**What it does not fix: the strobe gates RELEASE, not ARMING.**
`ELECTION_TIMEOUT_DEFAULT = 16'd4096` cycles (`tidechart_election_fsm.sv:43`),
≈20 µs at 200 MHz, runtime-overridable via `TC_TIMEOUT`.

1. Die A's software arms `TC_CTRL[0]`. Data mode arrives; A is released, runs
   `ST_WAIT_LINKS → ST_CLAIM_TX`, floods its claim.
2. A's quiescence timeout expires → **A enters `ST_SETTLED`**. A is now root,
   silent, and deaf.
3. Die B's software arms `TC_CTRL[0]` **any time more than ~20 µs later**. Data
   mode is long since high and the strobe is monotonic by construction, so B is
   released at once, reaches `ST_CLAIM_TX`, and floods its claim to A.
4. That beat lands on A in `ST_SETTLED` → §1 → **die A's entire FC receive
   channel is permanently wedged.**

On the shipping die arming is **not** synchronised and cannot be — no firmware
arms it at all, so it is debugger- or host-driven per die. A >20 µs skew between
two independently-driven arms is the normal case, not the corner.

Two paths survive the G1 gate entirely: the peer **restarting** its election
(i.e. **the prescribed dual-root recovery action wedges the peer's link**), and a
corrupted FC beat whose `[45:32]` decodes as the election subtype — on a link
with documented framing history.

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
  chiplet ships `NUM_PORTS=1` (`src/rtl/nanosoc_eth_chiplet.sv:967`). There is no
  link-down-after-settle test, no re-election-on-link-loss test, and no
  corrupted-claim test.
- **The one test that gets closest deliberately avoids it.**
  `tidelink/cocotb/tidechart_tidelink_pair/test_tc_pair_election_datamode.py`
  PASSES and proves `PKT_EXT` CLAIMs cross the real link in **both** directions
  (README G2 CLOSED) — so the trigger packet demonstrably exists and demonstrably
  arrives. But it arms **both** dies pre-data-mode, so both sit in `ST_LISTEN`
  when the claims land. A claim arriving at a peer already in `ST_SETTLED` is
  precisely the case no test creates.
  *(An earlier revision of this doc said no `PKT_EXT` had ever crossed the link.
  That was read off the README's superseded G2 section; G1/G2 were closed on
  2026-07-19. The correction matters in the direction of MORE confidence, not
  less — the transport works, so the beat does arrive.)*
- **No assertions.** `tidechart/` contains zero `assert`/`cover property`.

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

## 6. DEMONSTRATED IN SIMULATION — 2026-08-10

**The structural argument in §1–§2 is confirmed.** Test:
`tidelink/cocotb/tidechart_tidelink_pair/test_tc_pair_late_claim.py`, on the
existing two-die pair bench (real TideLink pair, real `tl_data_mode_o` gate).

It brings the pair to data mode with **neither** election armed, then:
* **Phase 1** arms die A only → A's CLAIM lands on **die B in `ST_IDLE`**;
* **Phase 2** arms die B → B's CLAIM lands on **die A in `ST_SETTLED`**.

| victim | UNFIXED | FIXED |
|---|---|---|
| die_b @ `ST_IDLE` | 6937 beat-cycles presented, **0 handshaken**, `rx_idle` 126/7063 | 2 presented, **1 handshaken**, `rx_idle` 7061/7063 |
| die_a @ `ST_SETTLED` | 21939 presented, **0 handshaken**, `rx_idle` 125/22064 | 2 presented, **1 handshaken**, `rx_idle` 22062/22064 |
| verdict | **FAIL (WEDGE)** | **PASS** |

Two things the experiment changed about the write-up above:

* **`ST_IDLE` is the more important case, and it was not in the original
  analysis.** An *un-armed* die wedges on a peer's claim just as a settled one
  does — and un-armed is the shipping die's **permanent** state, because no
  firmware arms TideChart. This is the likelier field failure.
* **The two are not equally recoverable.** The `ST_IDLE` wedge **self-clears** if
  that die is later armed (it enters `ST_LISTEN` and drains the stuck beat —
  visible in phase 2, where die_b shows `xfer=1`). The `ST_SETTLED` wedge does
  not: nothing leaves `ST_SETTLED` except `restart`, which also wipes the route
  table.

The test carries a **vacuity guard** that fails loudly if no ELECTION beat was
presented to the victim. That guard fired twice during development and prevented
two false greens — once when `device_strap` was floating (below), once before the
health metric was corrected.

**A bench defect had to be fixed first.** `tb_tc_pair.sv` never connected
`tidechart_shim.device_strap`, added by tidechart's I6 dual-root hardening
(`3005d11`). It floated, so `own_random_r = {device_strap, lfsr[7:0]}` was X, the
claim TX word was X-poisoned, and the X propagated into the **Wlink FCSM state
register** — which is why `PairTB.fcsm_state()` returned −1 and
`test_tc_pair_election_datamode` failed. With the strap wired (master `8'h00`,
slave `8'h01`) both sibling tests pass again.

**Still not covered:** the shipping `NUM_PORTS=1` configuration (this bench is
`NUM_PORTS=2`) and the corrupted-beat trigger.

---

## 7. Provenance

Found by adversarial review during HAL error triage, then verified link by link
against the RTL. The `TERMST` lint error that led here was real but benign, and
is fixed separately (`state_next = restart ? ST_IDLE : ST_SETTLED;`, LEC
equivalent 242/242).

Everything in §1 and §3 was confirmed by direct inspection. The trigger sequence
in §2 was a structural argument from that code; **§6 has since demonstrated it in
simulation, in both directions, with a before/after mutation.** It is no longer a
hypothesis.

**FIX APPLIED** — `tidechart/src/rtl/tidechart_election_fsm.sv`: drain (accept and
discard) a presented claim in `ST_IDLE`, `ST_WAIT_LINKS` and `ST_SETTLED`.
`ST_LISTEN` consumes; `ST_CLAIM_TX` is excluded because its stall is bounded by
`flood_complete` and draining there would discard a real claim. Change unit:
`verif/lint/full/fixes/B1-tidechart-rx-drain-wedge.yaml`. Lint delta measured at
**zero** on both the fixed and unfixed file. LEC is expected **non-equivalent** —
`claim_rx_accept` now asserts in three more states, which is the point.

**What the fix does NOT do:** it does not close the protocol gap. A drained claim
is discarded, so the outcome is a benign dual-root instead of a hard wedge.
Deciding what a non-listening node *should* do about a late claim (ignore /
re-elect / NACK) remains open, and is TideChart's to make.

**Still open on the TideLink side:** there is no RX stall watchdog in
`tidelink_fc_adapter` (there is a TX one, added for a proven silicon wedge). The
drain fixes this instance; the watchdog would bound the class. Raised with the
TideLink owner in `../history/DEV_MESSAGE_TIDELINK_RX_STALL_2026_08_10.md`.
