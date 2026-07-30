# I1 FCSM recovery fix breaks KR260 link bring-up (silicon finding, 2026-07-30)

**For the TideLink developer.** The I1 flow-control-recovery fix on `main`
(`b98b944`, "re-point AXI FCSM 0-4 to local_overrides + tune state-2 CRACK gate"),
which lowers `SOCL_L7_MIN_CRACK_EMITS` 32 → 8 and points the 5 AXI data-plane FCSMs
at the recovery-capable `local_overrides` copies, **prevents the TideLink d2d link
from coming up on the KR260 eth-chiplet pair.** It trades the sustained-traffic
wedge for a link-bring-up failure.

This is the opposite failure mode from what it fixes, so it must not ship as-is.

## What was tested (all on the two-board KR260 eth-chiplet bench, 2026-07-29/30)

The bring-up criterion is `SWI_LANE_STATUS @ 0x2E03_2108`: `cr_seen`, `crack_seen`,
`calibration_done`, and `fcsm` reaching **4 (LINK_IDLE)**, bilateral, over the
`eth_ss_0` backdoor. `cr_seen`/`crack_seen` are the FCSM **credit / CRACK handshake**
signals (the same CRACK emits that `SOCL_L7_MIN_CRACK_EMITS` gates in state 2) — NOT
PHY clock recovery.

| Build | AXI FCSM 0-4 source | Result on silicon |
|---|---|---|
| **baseline `0ed6d46`** (V2, pre-I1) | `deps/` (recovery-stripped) | **LINK UP** — `cr_seen=1 crack_seen=1 cal_done=1 fcsm=4`, both dies. Proven **3×** (initial M1, + two A/B re-confirms today). Wedges under sustained traffic (the original bug). |
| full merge **`969a0c9`** (origin/main) | `local_overrides/` recovery, gate=8 | **LINK DOWN** — `cr_seen=0 crack_seen=0 cal_done=0`, fcsm stuck 0/1, both dies. |
| minimal **`90fe6cc`** (I1 cherry-picked onto the proven base `809f038`, autoneg/`tidelink_top` byte-identical to baseline) | `local_overrides/` recovery, gate=8 | **LINK DOWN** — identical `cr_seen=0 crack_seen=0`, both dies. |
| **mix**: `90fe6cc` die_a + `0ed6d46` die_b | die_a recovery / die_b deps | **LINK DOWN** — the recovery-FCSM die_a stays `cr_seen=0 fcsm=0`; the deps die_b gets to `fcsm=1` then stalls waiting on the master. |

**Two independent recovery-FCSM builds fail identically; three deps-FCSM runs pass —
on the same two boards, same ribbon, same deploy flow.** The recovery FCSM RTL is the
only common differentiator.

## What was ruled out (with evidence)

- **Physical / ribbon.** Baseline links up FCSM=4 on these exact boards, repeatedly,
  including immediately before and after the failing runs. Ribbon is fine.
- **PHY submodules.** `deps/tidelink-phy 5c76e76` and `deps/tidelink-gpio-phy 6ee8418`
  are byte-identical (pin + working tree) between baseline and the failing builds.
- **`DEVICE_CLASS` strap** (the eth-chiplet G1 batch-prep). die_a is strapped class=1,
  which equals the RTL default — a no-op — yet die_a still fails. Not the strap.
- **Autoneg / `tidelink_top`.** In `90fe6cc` these are **byte-identical** (SHA
  `5080ec0`) to the M1-proven baseline. (An earlier hypothesis that the merge's
  autoneg "Option A" delta was the cause was a confound — the minimal build with
  baseline autoneg fails the same way.)
- **Timing.** `90fe6cc` closes at **WNS = +0.304 ns (setup met)**; hold ≈ −22 ns, the
  same pre-existing hold violation the working baseline ships with. Not a timing regression.
- **My cherry-pick being incomplete.** The *full dev-authored merge* (`969a0c9`, with
  every I1 companion) fails identically to the minimal extraction. So it is the I1 FCSM
  RTL itself, as authored, not a missing companion file.

## The ask

The recovery-capable FCSM override must **bring up the link AND recover under traffic**
at the KR260 silicon ratio (link_clk:app_clk ≈ 40 ns). Today:
- gate=32 → documented to **stall** FCSM state 2 at silicon ratio;
- gate=8 → **never establishes** the initial CR/CRACK handshake (`cr_seen=0`);
- deps (no recovery) → handshakes + FCSM=4, but no traffic recovery.

The `tidelink_fcsm_silicon_ratio` cocotb suite reports PASS at gate=8, so there is a
**sim/silicon gap**: sim does not reproduce the initial-handshake failure the KR260 sees.

## RTL root-cause (analysis complete)

The FSM `always` block is **byte-identical** (override `WlinkGenericFCSM.v:685-703` vs
deps `:608-626`). The only bring-up-relevant difference is the **combinational
state-exit gates**:

| Transition | deps (links up) | local_overrides (fails) |
|---|---|---|
| state 1→2 (CR) | leave on **first peer CR/CRACK seen** (`deps:244`) | also needs `socl_l6_cr_emit_gate_ok` = **≥32 of THIS node's own CR emits** (`local:312-313`) |
| state 2→3 (CRACK) | leave on **first peer CRACK seen** (`deps:252`) | needs peer CRACK **AND** `socl_l7_crack_emit_gate_ok` = **≥8 own CRACK emits** (`local:292,316-321`) |

The emit counters increment only on `auto_tx_out_advance & sop` (once per CR/CRACK
packet this node actually **transmits**), reset on state change (`local:818-838`). The
recovery regs (`socl_reack`, watchdog, forgive) act only in states ≥4 and **cannot**
affect 0→3, so they are not the blocker. The two gate `localparam`s are the whole story:
`SOCL_L6_MIN_CR_EMITS=32` (`local:64`, never lowered) and `SOCL_L7_MIN_CRACK_EMITS=8`
(`local:76`, lowered from 32 by I1).

**Decisive fact — the threshold number is NOT the cause.** The sideband node
`WlinkGenericFCSM_6.v` carries the **identical gate logic at 32/32** and brings up fine on
silicon (`_6.v:189,192`). The discriminator is **structural**: the five AXI FC nodes
(AW/W/B/AR/R) are time-multiplexed onto **one shared serial link** in `AXI4ToWlink`, so
each accrues emits ~5× slower and all five must complete their bilateral CR→CRACK→IDLE
handshake **simultaneously under contention**, while `FCSM_6` is a single dedicated node.

**Root cause:** gating state-exit on a fixed count of *this node's own transmitted
packets* has two opposing failure edges and no fixed count satisfies both across the five
contended nodes at the 40 ns link:app ratio:
- **32** → a node can't transmit 32 CR/CRACK before its peer node satisfies its gate,
  sees this node, and **leaves the state (stops emitting)** → documented state-2 stall.
- **8** → the emit window is only 8 packets; the peer's RX LinkLayer framer needs many
  symbols to byte-align after reset (the gate's very purpose, `_6.v:15-70`), so 8 packets
  fly past **before the peer latches even one** → `cr_seen=0/crack_seen=0`, never leaves
  state 0/1, `cal_done` never asserts.

The deps version has **no** emit gate — each node emits CR until peer-seen, then CRACK
until peer-CRACK-seen: an open-ended, self-terminating-on-peer-seen window exactly as long
as needed, so all five converge regardless of ratio/contention.

## Suggested fix (for the TideLink dev)

1. **Do not gate the *initial* handshake on a fixed self-emit count.** Keep the deps exit
   condition for first bring-up (leave state 1 on peer-CR-seen; state 2 on peer-CRACK-seen),
   and arm the min-emit hold + recovery **only after LINK_IDLE is first reached.** The hook
   already exists: `socl_l7_reached_link_data` latches sticky on `state==5` (`local:999-1005`)
   and already disarms `socl_l7_bringup_forgive` (`local:295-299`). Reuse it to force
   `socl_l6_cr_emit_gate_ok`/`socl_l7_crack_emit_gate_ok` **true until first LINK_IDLE** →
   bring-up becomes bit-identical to the proven deps path while recovery still arms for the
   traffic phase. This directly resolves the "trades the wedge for a bring-up failure" tradeoff.
2. If a minimum CR/CRACK hold is genuinely needed for the peer's RX byte-align, make it
   **time/cycle-based, not transmit-count-based**, and still release on peer-seen — a
   self-transmit count is throttled ~5× by the shared-link multiplex and can't serve five
   contended nodes deadlock-free.
3. **Threshold retune alone will not fix it** — `FCSM_6` proves 32 works on a single node;
   any retune must be validated per-node under the 5-way multiplex, not on one pair.

## Why sim passed but silicon failed (sim gap)

- The cited `cocotb/tidelink_fcsm_silicon_ratio/` suite **does not exist in the tree** — it
  is referenced only in RTL comments (`local:71`) and docs. The "PASS at gate=8" claim is
  not reproducible here (nearest real env: `cocotb/tidelink_error_injection`).
- Substantively, a silicon-ratio TB that proves "recovery fires under injected ACK-loss on
  an idealized single pair" does **not** model the four things that make the fixed-count
  gate fail: (1) RX LinkLayer byte-align/hunt latency after reset; (2) the 5-way multiplex
  of the AXI FC nodes onto one link; (3) asynchronous reset-release + clock phase between
  two real dies (the finish-first race); (4) calibrator/`cal_done` coupling. A real
  two-die, multiplexed, async-reset, RX-align-latency pair TB is needed before re-shipping.

## Doc nit found during analysis
`flists/tidelink_fpga_v2.flist` (FCSM region ~277-282) now points FCSM 0–4 at
`local_overrides` but still carries a stale "reverted to deps" comment.

## Silicon validation of candidate fixes — BOTH FALSIFIED

Two RTL fixes were built into full KR260 bitstreams and tested on the bench. Both
produced the **byte-identical failure signature** as the unmodified I1
(`SWI_LANE_STATUS=0x00100000`, `cr_seen=0 crack_seen=0 cal_done=0 fcsm=0`, both dies):

| Candidate fix | tidelink commit | Hypothesis | Silicon result |
|---|---|---|---|
| **v1** — ungate the state-1/2 emit gates (`(~socl_l7_reached_link_data) \| count≥thr`) until first LINK_DATA | `0853c4c` | emit-count gate stalls the muxed AXI handshake | **FALSIFIED** — link still down. (Edit verified present in the packaged IP + both synth copies.) |
| **v2** — flip the 5 AXI nodes' `out_prepend_swi_disable_crc` reset default `1'h1`→`1'h0` (CRC-ON, matching the working `FCSM_6`/deps) | `6d85c68` | CRC-off TX framing breaks the RX CR/CRACK detect | **FALSIFIED** — link still down, identical signature. |

**Interpretation.** Neither the emit-count gate **nor** the CRC-default is the (sole)
cause. The recovery-override FCSM breaks the CR handshake in some way beyond these two —
and the **identical, unchanged failure signature** across the unmodified I1, v1, and v2
suggests the local-override AXI FCSM simply never gets the initial CR exchange going
(`cr_seen` never so much as flickers), i.e. the break is in logic that runs **before/at**
the state-1 CR emit, not in the exit gating or the CRC format.

**Remaining candidates (for the dev)** — the still-unaddressed `local_overrides` vs
`deps` FCSM diffs, in rough priority:
1. The **state-1 CR emit content / selection** itself (`FC.scala` ~459-486 region) — what
   the node actually drives onto the link in state 1, beyond the gate. If the recovery
   override changes the emitted CR word/format, the (shared) RX never latches it.
2. The extra recovery **state/regs** (`socl_l7_*`, `socl_reack_*`, the added `always`
   blocks) — verify none of them gates TX-enable or the CR emit in states 0–3 at reset.
3. `isNotExpPacket_l7` / `socl_l7_crack_release` feedback into `send_nack_req` /
   emit-select during bring-up.

**Method note for the dev:** each of these is a full FPGA rebuild + two-board bench cycle
to test (≈1.5 h build + POR/deploy/bringup). The two most obvious candidates (gate, CRC)
are now **empirically eliminated on silicon** — start from the state-1 CR emit content.
The cleanest path is likely a targeted two-die, multiplexed, async-reset, RX-align sim
(which does not exist — see the sim-gap section) so candidates can be triaged without a
board cycle each.

## Board / repo state left behind
- Both KR260 boards restored to the **working baseline (`0ed6d46`)** bitstream, leases
  released. The wedge-prone-but-functional link is what's deployed.
- tidelink branch `integ/i1-fcsm-on-proven` records the whole attempt:
  `90fe6cc` (I1-on-proven) → `0853c4c` (fix v1, emit-gate ungate) → `6d85c68` (fix v2,
  AXI CRC-on). Parent pin currently `e8bbcc8` → tidelink `6d85c68`.
  **Do NOT build/deploy any of these for bench use — the link will not come up.** The
  next rebuild for actual use should pin back to a deps-FCSM base (e.g. `0ed6d46`/`809f038`)
  until the dev lands a working recovery FCSM.
- Preserved bitstreams on disk: `imp/fpga/output/kr260-eth-chiplet{,-flip}.{baseline-0ed6d46,i1-90fe6cc,fixed-969a0c9}/`.
