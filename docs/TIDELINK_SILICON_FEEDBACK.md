# TideLink — silicon feedback from the eth-chiplet KR260 bring-up

**From:** nanoSoC eth-chiplet integration (two-board KR260, first silicon, 2026-07).
**To:** the TideLink development agent/team.
**What this is:** findings from driving TideLink on real silicon that are not visible
in sim-only work, plus a couple of doc corrections. The consumer drives bring-up +
cross-die transfers **PS-side over the `eth_ss_0` backdoor** (no firmware): tools
`tidelink/pynq_host/scripts/kr260_eth_{bringup,xfer}.py`, `kr260_eth_regress.py`.

**TL;DR:** the link comes up reliably (FCSM=4, bilateral), but the **cross-die data
path intermittently wedges the PS AXI bus** — and the fix is the FCSM 0–4 threshold
item you already flagged as deferred. It is now the top blocker for reliable
cross-die operation on shipped silicon. Details + a bounded fix below.

Full root-cause analysis: `docs/CROSS_DIE_WEDGE_ROOTCAUSE.md` (in the eth-chiplet repo).

---

## 🔴 P1 — FCSM 0–4 recovery is stripped on silicon; the deferred threshold fix is the blocker

### Symptom (silicon-observed, reproducible)
Two KR260 dies, link up (FCSM=4, cal_done=1, cr/crack seen). The **first** cross-die
transfer after bring-up reliably passes; a **subsequent** cross-die access — read OR
write, either direction — **intermittently hangs and wedges the PS AXI bus** (no
software timeout; JTAG-POR to recover). Sometimes a whole run passes; a write-only
2000-beat soak passed once cleanly. Reproduce with repeated
`kr260_eth_regress.py --deploy --data-plane` (it wedged on ~2 of 3 repeats).

### Root cause
The shipped FPGA build resolves the **five AXI data-plane FC nodes** (AW/W/B/AR/R =
`WlinkGenericFCSM{,_1,_2,_3,_4}`) to the **`deps` upstream copies, which are
recovery-stripped** (`socl_reack` / state-7 watchdog / L9b/L9c = 0). Only the
sideband node `WlinkGenericFCSM_6` keeps the SoC-Labs recovery logic. So a single bit
error / dropped ACK on an AXI data node has **no recovery**: `fe_rx_ptr` never
advances → credit ring fills → `fe_rx_is_full` latches → the sender stops → the far
side's `B` (write) / `R` (read) beat never returns → PS `M_AXI_GP0` SmartConnect
saturates → PL slaves wedge (the mechanism is documented in
`src/rtl/local_overrides/tidelink_top.sv:1957-1962`).

### Why it's stripped — and this is your deferred item
- `c2b2d51` (Jul 4) *"xhb500: harden 5 AXI FC nodes (lite A-E + CRC-off) for silicon
  window"* ported the full recovery set (A L7 NACK-forgive, B L6 min-CR-emit, **C L7
  min-CRACK-emit**, D state-7 watchdog, E periodic re-ACK) onto the AXI nodes.
- `74d0d52` (Jul 11) *"re-resolve FCSM 0-4 toward deps"* **reverted the flist** to the
  stripped `deps` copies, for one stated reason: Fix C's gate
  `SOCL_L7_MIN_CRACK_EMITS = 8'd32` — *"at the 40 ns silicon ratio the FCSM never
  reaches 32 CRACK emits, stalls in state 2, never reaches LINK_IDLE, and both data
  directions read all-zeros."* That commit says verbatim: **"The L7 hardening, if
  wanted, needs its threshold fixed for the silicon ratio — a separate item."**

That "separate item" is what's biting silicon now. It is **not fixed anywhere else**:
the standalone clone is on `feat/txgen-v1-integration` (txgen/autoneg); the only
branch touching these files, `fix/word-window`, adds eyescan/PRBS instrumentation.

### The bounded fix (this is a threshold tune, not a rewrite)
The recovery code + watchdog + re-ACK are all present in the five
`src/rtl/local_overrides/WlinkGenericFCSM{,_1,_2,_3,_4}.v`. The only blocker is one
gate:
```
src/rtl/local_overrides/WlinkGenericFCSM*.v:65   localparam [7:0] SOCL_L7_MIN_CRACK_EMITS = 8'd32;   // AXI nodes
                                          :278   wire socl_l7_crack_emit_gate_ok = (socl_l7_crack_emit_count >= SOCL_L7_MIN_CRACK_EMITS);
src/rtl/local_overrides/WlinkGenericFCSM_6.v:192  parameter [7:0]  SOCL_L7_MIN_CRACK_EMITS = 8'd32;   // sideband (kept, works)
```
1. **Scale `SOCL_L7_MIN_CRACK_EMITS` for the 40 ns ratio** in the five AXI-node files so
   state 2 clears to LINK_IDLE *and* the recovery still arms (too low weakens Fix C;
   too high re-stalls — this is the one part needing care).
2. **Re-point the flists** — `flists/tidelink_fpga_v2.flist` (FCSM 0–4) **and both ASIC
   flists** — back at `local_overrides` (undo `74d0d52`'s revert, but with the fixed
   threshold).
3. **Validate in the silicon-faithful sim tier** (`sim[silicon_data]` — the exact tier
   that caught the state-2 stall): confirm it reaches LINK_IDLE (no all-zeros) AND that
   the recovery fires under injected ACK-loss / pktnum-gap. The
   `cocotb/tidelink_error_injection` env looks like the right harness.

**Subtlety to resolve:** FCSM_6 (sideband) carries the *same* 32 threshold and works on
silicon, while the AXI data nodes stall. Understand why the sideband reaches 32 CRACK
emits at 40 ns but the data nodes don't — the corrected value must let the data nodes
clear without breaking the sideband's proven behaviour (or the two want different
thresholds).

---

## 🟠 P2 — should-fix, same rebuild

- **`rd_pipe_r` read-completion guard is absent from the base V2 `tidelink_top`.** It
  exists only in `src/rtl/local_overrides/tidelink_top.sv:1168-1194`; the shipped build
  resolves `tidelink_top` via the base V2 copy (`rd_pipe_r` count 0). On silicon a peer
  READ was one of the two observed wedge points — reads are ≥ as fragile as writes.
  Port the guard forward, or confirm the base version holds `hreadyout` low until the
  AXI `R` beat returns.

- **One-shot calibration is a silicon liability.** `calibrated_once_q` latches on first
  `S_DONE` and permanently gates re-trigger; `SWI_FORCE_RECAL` (W1P) exists but the FSM
  never drives it (`src/rtl/local_overrides/tidelink_phy_align_calibrator_v2.sv:14-40`).
  The sampling point is frozen at bring-up, so jitter/thermal **eye drift** after lock
  is the intermittency trigger for P1 (first transfer OK, later ones progressively more
  likely to sample a bit wrong). Consider a re-cal trigger / drift tracking. Your
  `fix/word-window` eyescan/PRBS instrument is the right tool to characterise the eye
  margin here.

- **Observability gap — the OBS registers don't see the nodes that wedge.**
  `OBS_FC_CREDIT` (0x219C) and `SWI_LANE_STATUS[31:17]` are wired from **FCSM_6
  (sideband) only**, not the AXI data nodes that actually hang. Silicon debug currently
  has to read the raw Wlink per-node FC registers (`REGISTER_MAP.md:448-471`): B=`0x1200`,
  R=`0x1400`, AR=`0x1300`, AW=`0x1000`, W=`0x1100` (CRC-error count `+0x20`, Ack/Nack
  FIFO `+0x10`, TX-FC-FIFO `+0x08`). **Please surface an aggregate data-node health
  field in an APB status reg** (a rising CRC count or a stuck Ack/Nack FIFO would
  immediately pin the failing channel).

- **`SUB_STALL_TIMEOUT` doesn't catch this wedge class.** `tidelink_top.sv:1313-1419`
  (`SUB_STALL_TIMEOUT_LOG2=16`) only counts while `xhb_sub_hreadyout_raw==0`. A wedge
  that parks XHB500 with `hreadyout` high (response beat lost mid-transaction) is
  invisible to it — hence the hard hang with no SIGBUS. Consider extending the backstop
  to cover an outstanding-but-unanswered response.

---

## 🟡 P3 — TideChart (never sim'd; silicon findings)
The election/enum path is "Planned" in the VPLAN (never simulated). On silicon:
- Both dies ship `DEVICE_CLASS = 0x0001` (`src/rtl/nanosoc_eth_chiplet.sv:796`, shim
  default, no per-die override) → **non-deterministic dual-root election** (each die
  self-elects with its own random_id; neither sees the peer's claim under async start).
- `force_root` (`TC_CTRL[2]`) is decoded/stored but **never consumed** — the documented
  software override doesn't work (`tidechart_apb_regs.sv:317-319`; election FSM has no
  force input).
- `reset` (`TC_CTRL[3]`) does **not clear `election_done`** (observed on silicon).
- Default `election_timeout` (256 cyc) is shorter than the D2D round-trip.

Recommend: per-die `DEVICE_CLASS` strap (die_a < die_b) for deterministic grandmaster;
wire `force_root` into the election FSM; fix `reset` to clear election state; document
that `election_timeout` must be widened for a real link. Full test plan:
`docs/TIDECHART_TEST_PLAN.md`.

---

## 🟢 Positive / doc corrections
- **PS-side bring-up over the `eth_ss_0` backdoor works with no firmware and no SWD** —
  role-lock / cal-poll / to-data-mode / FCSM=4, plus cross-die SRAM + mailbox transfers,
  all driven from the host. This validates `D2D_PORT.md §3` on silicon.
- **Backdoor window address:** on the built bitstream it is the **HPM0_FPD high aperture
  at PS phys `0x4_0000_0000`** (`tidelink.hwh` MEMRANGE), NOT the `0x8000_0000` in the
  tcl comments / notes. Please correct the docs (SoC addr `A` is reached at
  `0x4_0000_0000 + A`).

---

## How to reproduce + diagnose on silicon
1. Bring the link up on both boards (`kr260_eth_bringup.py --bringup`, concurrent).
2. Run `kr260_eth_regress.py --deploy --data-plane` **repeatedly** — it intermittently
   wedges (recover with the per-target POR API on mapstone-dev, not the group
   `board reset`).
3. To pin the cause, poll the per-node Wlink FC regs (above) **between** transfers,
   before a hang: rising CRC → bit error (drift/eye, supports the calibration item);
   stuck Ack/Nack FIFO non-empty → credit/ACK stall (supports the FCSM-recovery item).

## References
- Commits: `c2b2d51` (harden 5 AXI FC nodes), `74d0d52` (the revert = root cause),
  `65e13af` (L9b/L9c onto FCSM_6).
- Files: `src/rtl/local_overrides/WlinkGenericFCSM{,_1,_2,_3,_4,_6}.v`,
  `flists/tidelink_fpga_v2.flist:276-295`, `src/rtl/local_overrides/tidelink_top.sv`
  (`rd_pipe_r`, PS-wedge note), `src/rtl/tidelink_top.sv:1313-1419` (SUB_STALL_TIMEOUT),
  `src/rtl/local_overrides/tidelink_phy_align_calibrator_v2.sv`.
- Consumer analysis + tools (eth-chiplet repo): `docs/CROSS_DIE_WEDGE_ROOTCAUSE.md`,
  `docs/CROSS_DIE_INTERRUPTS.md`, `docs/CROSS_DIE_DEBUG_PLAN.md`,
  `tidelink/pynq_host/scripts/kr260_eth_{bringup,xfer,regress}.py`.
