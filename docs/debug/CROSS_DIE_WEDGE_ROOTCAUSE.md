# Cross-die data-path intermittent wedge — root cause (2026-07-29)


> **SUPERSEDED — the root cause stated here was disproven.** Measured 2026-07-29.
> The claim "the silicon build ships the UPSTREAM (recovery-stripped) FCSM on the five
> AXI data-plane FC nodes" was corrected on 2026-07-31: the flist points FCSM 0–4 at
> `local_overrides`, so recovery is **present but ineffective**, not stripped — see
> `AXI_DATANODE_RECOVERY_GAP_2026_07_31.md`. The wedge investigation continued through
> `ROOT_CAUSE_D2D_DELIVERY_WEDGE_2026_08_10.md` (also superseded) to the current head,
> `DIAGNOSE_AHB_SUB_HREADYOUT_FROZEN0_tidelink_die_a_u_xhb_sub.md`. Kept for the
> symptom description and the two-path disambiguation, which are still accurate.

## Symptom
Two-board KR260 eth-chiplet. TideLink link brings up reliably (FCSM=4, cal_done=1,
bilateral). The **first** cross-die transfer after bring-up reliably passes, but a
**subsequent** cross-die access — read OR write, either direction — **intermittently
hangs and wedges the PS AXI bus** (no software timeout; JTAG-POR to recover).
Sometimes all transfers in a run pass; a write-only 2000-beat soak passed once.

## Root cause (high confidence, RTL-evidenced)

**The silicon build ships the UPSTREAM (recovery-stripped) FCSM on the five AXI
data-plane FC nodes; only the TideLink sideband node keeps the SoC-Labs recovery
logic.** A single bit error / dropped ACK / pktnum gap on an AXI data node therefore
has **no recovery path** → the node stops emitting, its FC response channel never
returns → the far side's `B` (write) or `R` (read) beat never comes back → the PS
`M_AXI_GP0` SmartConnect saturates → the whole PL slave set wedges.

### The two paths (the key disambiguation)
The peer-window transfer (`0x2F001000 → CAM 0x2F→0x2D → die_b shared_sram_0`) rides
the **AXI transport**, NOT the TideLink FIFO/returner sideband:
```
ahb_sub → CAM → XHB500 AHB→AXI → Wlink AXI FC nodes (AW/W/B/AR/R) → PHY
        → die_b WL2AXI → ahb_mng → shared_sram
```
- AXI FC nodes = `WlinkGenericFCSM` / `_1` / `_2` / `_3` / `_4` (AW/W/B/AR/R),
  `tidelink/deps/axi-chiplet-controller/logical/wlink/AXI4ToWlink.v:529-681`.
- `CREDIT_COUNT`(0x200C)/`RELEASE_THRESHOLD`(0x2004)/`OBS_FC_CREDIT`(0x219C) and the
  returner are the **separate sideband** path (FCSM_6). The soak's `CREDIT_COUNT=4096`
  (= idle FIFO) confirms the peer window doesn't use it — **so RELEASE_THRESHOLD
  tuning cannot affect this wedge.**

### The evidence
The FPGA V2 flist deliberately reverts FCSM 0–4 to `deps/` (upstream) and keeps only
FCSM_6 as an override — `tidelink/flists/tidelink_fpga_v2.flist:276-295`. The
2026-07-11 revert note explains why: the `local_overrides` FCSM copies carried a
"min-CRACK-emit gate" that **stalled the FCSM in state 2 at the 40 ns silicon ratio**
(no LINK_IDLE), so they were reverted to upstream to get the link up — which stripped
the recovery features from the data nodes. The packaged silicon IP
(`tidelink/imp/fpga/eth_chiplet_ip/src/`, repackaged 2026-07-24) matches: AXI FCSMs
are the 1159-line upstream (`socl_reack`/watchdog/`l9b` = 0); FCSM_6 is the full
override.

Missing on the shipped AXI nodes (present only on FCSM_6):
| Mechanism | What it does | Ref (FCSM_6) |
|---|---|---|
| `socl_reack` | sustained ACK-loss recovery (else `fe_rx_ptr` never advances, ring fills, `fe_rx_is_full` latches → **permanent wedge**) | `local_overrides/WlinkGenericFCSM_6.v:649-706` |
| `socl_l7_wdog` | state-7 (SEND_NACK) stuck-NACK watchdog | `:127-186` |
| `socl_l9b/l9c` | isolated pktnum-gap re-anchor (vs NACK→replay storm) | `:200-208,506-534` |

The PS-wedge mechanism itself is documented at
`tidelink/src/rtl/local_overrides/tidelink_top.sv:1957-1962` ("BVALID never returns
… PS7 M_AXI_GP0 SmartConnect saturates … wedges until power-cycle").

### The trigger — one-shot calibration + marginal eye
The calibrator latches `calibrated_once_q` on first `S_DONE` and permanently gates
off re-trigger; only `SWI_FORCE_RECAL` (W1P, POR-default 0, never driven by the FSM)
can re-cal (`tidelink/src/rtl/local_overrides/tidelink_phy_align_calibrator_v2.sv:14-40`).
So the sampling point is frozen at bring-up. FCSM_6 notes repeatedly that "the real
data blocker is the marginal EYE". Hence: the **first** transfer (eye freshly centred)
passes; jitter/thermal drift makes each **subsequent** transfer more likely to sample
one bit wrong; that single error on a no-recovery AXI node wedges. The write-only soak
passing is just a clean BER window (no bit error landed), not proof of recovery.

## Confirmed hypotheses (ranked)
1. **Credit/ACK stall — CONFIRMED**, but on the AXI FC-node credit ring
   (`fe_rx_ptr`/`fe_rx_is_full`, FCSM_6:561-591), which on silicon has no `socl_reack`
   backstop. The returner/RELEASE_THRESHOLD sideband is not involved.
2. **Calibration drift — CONFIRMED as the intermittency trigger** (one-shot cal, no
   drift tracking, marginal eye).
3. **Read-return fix absent — CONFIRMED**: the `rd_pipe_r` read-completion guard exists
   only in `local_overrides/tidelink_top.sv:1168-1194`; the silicon build resolves
   `tidelink_top` via the base V2 copy (`rd_pipe_r` count 0) — reads are ≥ as fragile
   as writes, matching the observed peer-read wedge.
4. **`SUB_STALL_TIMEOUT` backstop doesn't save it** (`tidelink_top.sv:1313-1419`): it
   only counts while `xhb_sub_hreadyout_raw==0`; a lost response beat parks XHB500 with
   `hreadyout` high → invisible → hard hang (why there's no clean SIGBUS).
5. **CAM reprogram mid-flight — plausible secondary**: the CAM is combinational
   (`tl_addr_trans_cam.sv:50-93`) and the address is latched once, so an in-flight
   transaction is immune — but a replace-byte glitch coinciding with an address latch
   could misroute. All wedging runs contained CAM reprograms + direction changes.

## Diagnostics for the next ATTENDED bench session
`OBS_FC_CREDIT`(0x219C) and `SWI_LANE_STATUS[31:17]` observe **FCSM_6 (sideband) only**
— they do NOT see the AXI nodes that wedge. Read the per-node Wlink FC registers
directly (poll BETWEEN transfers, before a hang), `REGISTER_MAP.md:448-471`:
- **B node (write wedge):** `0x1200+0x20` CRC-error count; `0x1200+0x10` Ack/Nack FIFO
  full/half/empty; `0x1200+0x08` TX-FC-FIFO empty.
- **R node (read wedge):** same offsets at base `0x1400`.
- AR/AW/W: bases `0x1300 / 0x1000 / 0x1100`.
A rising CRC count → bit error (drift/eye); a stuck non-empty Ack/Nack FIFO → credit/ACK
stall. Also watch `SYNC_DET`(0x2114 [31:16] `sync_detected_cnt`) + `lane_fault` for drift.

## Fix path (most → least impactful)
1. **Restore FCSM 0–4 recovery** (`socl_reack` + state-7 wdog + L9b/L9c) with the
   min-CRACK-emit gate threshold **scaled for the 40 ns silicon ratio** (fixing the very
   thing that forced the 2026-07-11 revert, `tidelink_fpga_v2.flist:276-282`). This
   removes the wedge's *permanence* — a bit error becomes a recoverable retry.
2. **Host interim (no rebuild):** poll the per-node FC registers between transfers; on a
   stuck FIFO / rising CRC, issue link FLUSH / `SWI_FORCE_RECAL` and retry rather than
   letting the transaction wedge the bus. Keep transfers short; re-cal between bursts.
3. **Quiesce the link before CAM RULE writes**; add a settle delay.
4. **Port the read-completion guard** (`rd_pipe_r`) into the base V2 `tidelink_top` read
   path, or confirm the base version holds `hreadyout` low until the AXI `R` beat.

## Impact on other work
- **Cross-die SWD debug (`../design/CROSS_DIE_DEBUG_PLAN.md`) is gated on fix #1** — it is
  poll-heavy over these exact AXI nodes, so it would inherit the wedge. Fix #1 is a
  prerequisite for dependable G3.
- The regression's cross-die data-plane is `--data-plane` opt-in (attended) until #1
  lands; the die-local default suite is unaffected (it doesn't cross the link).

## Unverified (needs silicon/scope)
Whether the wedge is a CRC/pktnum error vs a silently-dropped ACK (needs the per-node
reads above); whether `SUB_STALL_TIMEOUT` ever trips (needs an ILA on
`xhb_sub_hreadyout_raw`); final confirmation the KR260 bitstream was built from the
2026-07-24 `eth_chiplet_ip` package (check the synth/bitstream log).
