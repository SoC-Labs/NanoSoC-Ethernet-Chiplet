# Overnight autonomous worklog (2026-07-27/28)

Autonomous run working through the four plan docs, prioritizing safe live-hardware
validation first. Boards kr260_01 (die_a) / kr260_02 (die_b), link up (FCSM=4).
Recovery if a board wedges: `ssh mapstone-dev 'fpgahub board reset kr260_0X --yes'`.

## Results log

### P1 — cross-die IPC mailbox (`ipc_mailbox_0` @ 0x23, the untested 2nd inbound target) — ✅ PASS
- die_a `mbox_send`: CAM `0x2F->0x23`, wrote slot0 data `[0xC0FFEE01..04]` + `SLOT0_CTRL=MSG_VALID` via the peer aperture.
- die_b `mbox_recv` (local read of `0x2300_0000`): data `[0xC0FFEE01..04]`, `SLOT0_CTRL=0x1` (MSG_VALID=1). **PASS.**
- Both boards alive (no wedge). Both inbound D2D targets (`shared_sram_0` 0x2D + `ipc_mailbox_0` 0x23) now proven on silicon.
- Tool: `kr260_eth_xfer.py --mode mbox_send|mbox_recv` (+ `kr260_eth_run.sh xfer_mbox_*`).

<!-- subsequent results appended below as each phase completes -->

### P2 — reverse direction (die_b -> die_a SRAM) — ✅ PASS
- die_b `xfer_send` (payload 0xB2A0FEED): CAM `0x2F->0x2D`, peer write; die_a `xfer_recv`: `shared_sram_0[0x2D001000]=0xB2A0FEED`. **PASS.**
- The slave->master direction (flagged by TideLink's own harness) works on silicon. No wedge. No code change needed — the tool is board-symmetric.
- Note: `recv` print label is a generic "die_a to die_b"; cosmetic, made direction-agnostic in P3 edit.

### P3 — multi-word soak + credit/health observability — ✅ PASS
- `kr260_eth_xfer.py --mode soak` (die_a): 2000 write+readback beats cycling a 16-word window over the link.
- **iters=2000, mismatches=0, FCSM_min=4, cal held, sticky faults=0x0** (no OVERRUN/UNDERRUN/MASTER_ERROR), CREDIT_COUNT steady 4096, OBS_FC_CREDIT=0xFC00001F (fe_rx_credit_max=31). No wedge.
- The data plane is intact under sustained traffic and the link stays healthy — first characterisation numbers off the credit/fault registers.
- Tool: `kr260_eth_xfer.py --mode soak --iters N` (+ `kr260_eth_run.sh xfer_soak`, `KR260_XFER_ITERS`).

### P4 — TideChart (chiplet identity/routing bootstrap) — ⚠️ PARTIAL (register plane PASS; election needs RTL work)
- **T0 register plane — PASS** on both dies: `DEVICE_CLASS=0x0001`, `PORT_COUNT=1`, `local_id=0x1F`, `is_root=0`, `TC_ERROR=0`. Tool: new `kr260_tidechart.py` (+ `kr260_eth_run.sh tc_*`).
- **Election — DUAL-ROOT observed.** Async `elect` on both dies: both `is_root=1`, different random_ids (die_a 0x57A2, die_b 0xAA98), each `BEST_CLAIM`=its own → neither saw the peer's claim.
  - **Root cause is orchestration, not (proven) a packet bug:** the election window = `election_timeout` cycles (max 16-bit ≈ 1.3 ms @ ~50 MHz apb_clk), but two async SSH `elect` commands start *seconds* apart, so the windows never overlap and each self-elects on timeout. Added `--sync-at` (wall-clock synchronized start) but NTP skew vs a ≤1.3 ms window makes it unreliable.
  - **Finding:** `reset` (TC_CTRL[3]) does NOT clear `election_done` (stayed 1 after reset) — reset semantics differ from the spec/plan.
- **Conclusion:** clean election-convergence testing needs RTL-level work — a POR-fresh state + either a wider election-timeout field or the **G1 deterministic DEVICE_CLASS strap** (die_a<die_b), which also needs a rebuild. Documented in ../verification/TIDECHART_TEST_PLAN.md (G1/G-VERIF). Not resolvable via register pokes; parked for a rebuild session.

### P5+ — regression runner (this task)
- Consolidating P1-P4 + the M1 link/transfer tests into a repeatable suite (`kr260_eth_regress.py`) so they re-run on every design iteration.

### Regression runner — ✅ kr260_eth_regress.py (10/10 on a clean deploy)
- Consolidates every cross-die test into one repeatable, CI-friendly suite: deploy -> fresh link bring-up -> backdoor -> role -> sram_fwd/rtt/rev -> mailbox -> soak -> tidechart. PASS/FAIL table + non-zero exit on any gating failure + `--json`.
- `--deploy` reflashes both dies from the latest build first (the design-iteration flow); without it, the runner only *verifies* the live link (never re-brings-up — that hazard wedged die_a).
- Validated end-to-end: `python3 kr260_eth_regress.py --deploy --soak-iters 1000` -> **10/10 PASS**, both boards healthy.
- **Bug caught + fixed:** re-running bring-up on a live link (LL_SWRESET) desyncs it and hangs the sender's peer writes -> die_a wedged. Recovered via the per-target POR API (group `board reset` breaks on the `kr260_01_pl` topology member). Both saved to memory.
- Run on a design iteration: `python3 tidelink/pynq_host/scripts/kr260_eth_regress.py --deploy` (or `make -C tidelink/fpga regress_eth_chiplet KR260_PASSWORD=...`).

### Repeatability run — 🔴 found an INTERMITTENT PEER-READ WEDGE (the suite doing its job)
- 3× reflash+regression (3000-beat soak). Iter 1: link/backdoor/role/sram_fwd PASS, then **sram_rtt (peer read-round-trip) wedged BOTH boards**; iters 2-3 couldn't deploy.
- **Finding:** cross-die WRITES are reliable (sram_fwd/mailbox/reverse/soak-writes always pass); the **peer READ round-trip intermittently hangs** and wedges the PS (no software timeout). The single earlier run got lucky (10/10); repeating it exposed the flake — exactly what a regression is for.
- **Recovery:** POR both via the per-target API (group `board reset` breaks on `kr260_01_pl`). die_b's first POR failed (transient cable-not-found from back-to-back POR); **retry succeeded** — POR one board at a time, retry on transient. Both back.
- **Fix (committed 13d578b):** soak is now WRITE-ONLY + health by default; regression's `sram_rtt` is non-gating + opt-in (`--include-peer-read`). The default suite is wedge-safe (writes + local reads + health only).
- **Root-cause hypothesis:** the read-return path (g2 sim needed `local_overrides/tidelink_top.sv`) is not robust on silicon. Prerequisite to fix before cross-die *debug* (which is poll/read-heavy) is dependable.

### Agents: cross-die debug + interrupts (user request)
- **SWD debug over tidelink** → concrete first-PR roadmap in [../design/CROSS_DIE_DEBUG_PLAN.md](../design/CROSS_DIE_DEBUG_PLAN.md): sim-prototype via `soc_d2d_loopback` first (proves negative today, positive after the 0b regen — no bitstream); 0b YAML edit + 0c REMOTE_DBG_EN gate; host `dbg_halt` mode; validation ladder. CoreSight-accepts-inbound risk retired. **Peer-read-wedge is a prerequisite risk** (debug is poll-heavy).
- **Cross-die interrupts** → new [../design/CROSS_DIE_INTERRUPTS.md](../design/CROSS_DIE_INTERRUPTS.md): full d2d_irq[15:0]→NVIC map; the **IPC mailbox doorbell** (P1 already exercised the write) is the general-purpose cross-die IRQ — `mbox_recv` now reads `irq_status @ 0x2300_0028` to prove the source latched (firmware-free). TideLink doorbell/packet/PTP/TideChart mapped; all sources PS-observable, ISR delivery needs firmware (item #8).

### CORRECTION + refined finding — the wedge is broader than peer-reads (2nd run)
- The "wedge-safe" run (soak write-only, no peer readback) **still wedged both boards** — this time at **sram_rev (a WRITE, die_b->die_a)**, not a peer read. So the earlier "peer-read-only" conclusion was too narrow.
- **Refined finding: the cross-die DATA PATH is intermittently unstable on silicon.** The link comes up (FCSM=4) and the first transfer (sram_fwd) reliably passes, but a *subsequent* cross-die access — read OR write, either direction — **intermittently hangs and wedges the PS**. Sometimes all pass (the one 10/10 run); sometimes the 2nd cross-die op wedges. Classic first-silicon link/credit-flow instability (candidates: credit-return path, forwarded-clock RX calibration drift, the residual −2.9/−3.3 ns setup).
- **Response (committed):** the DEFAULT regression is now **die-local + CI-safe** (deploy, link-up FCSM=4, backdoor boot-ROM, role strap, TideChart register plane — none push data across the link). The cross-die transfers (sram/mailbox/soak) are **`--data-plane` opt-in, ATTENDED ONLY**. This is the honest state: register-plane/link-up is a reliable repeatable gate; the cross-die data plane is not yet CI-stable.
- Recovered both boards again via one-at-a-time per-target POR (8 s gap avoids the cable race). **Stopping board-hammering; the intermittent wedge needs an RTL/timing root-cause, not more POR cycles.**

### ROOT CAUSE FOUND — intermittent cross-die wedge → [../debug/CROSS_DIE_WEDGE_ROOTCAUSE.md](../debug/CROSS_DIE_WEDGE_ROOTCAUSE.md)
- **The silicon build ships the UPSTREAM (recovery-stripped) FCSM on the 5 AXI data-plane FC nodes (AW/W/B/AR/R); only the TideLink sideband node (FCSM_6) keeps the SoC-Labs recovery logic** (`socl_reack` + state-7 watchdog + L9b/L9c gap-reanchor). A 2026-07-11 flist revert (`tidelink_fpga_v2.flist:276-295`) reverted FCSM 0–4 to upstream to get the link to LINK_IDLE at the 40 ns silicon ratio — which stripped recovery from the data nodes.
- So a single bit error / dropped ACK on an AXI data node has **no recovery → permanent wedge → PS AXI hang**. Trigger = **one-shot calibration + marginal eye + drift** (`SWI_FORCE_RECAL` exists but the FSM never drives it): first transfer (fresh eye) passes; subsequent transfers progressively likely to sample one bit wrong. Exactly matches the symptom.
- Also confirmed: the `rd_pipe_r` read-completion guard is NOT in the silicon `tidelink_top` (reads ≥ as fragile); `SUB_STALL_TIMEOUT` can't catch a lost response beat (parks XHB with hreadyout high → hard hang, no SIGBUS).
- **Fix path:** (1) restore FCSM 0–4 recovery with the min-CRACK gate scaled for the 40 ns ratio [rebuild]; (2) host interim — poll per-node Wlink FC regs (B=0x1200, R=0x1400) between transfers, FLUSH/re-cal on stuck-FIFO/rising-CRC; (3) quiesce before CAM writes; (4) port the read guard.
- Gates cross-die SWD debug (poll-heavy over the same nodes). Diagnosis doc has the PS-observable per-node registers for the next attended session.

### SWD-debug sim-prototype — ✅ PROVEN (parallel work while the tidelink FCSM fix is addressed)
- `soc_d2d_loopback` (VCS+cocotb), isolated + fully reverted (submodule untouched). Stage 1: existing suite 9/9 PASS (dbg window DECERRs today). Stage 2 (0b edit + `make soc`): far-core dbg reachable over d2d_m — 2/2 PASS, **CPU1 CPUID=0x410CC601** over the link (CoreSight-accepts-inbound risk retired). Details in [../design/CROSS_DIE_DEBUG_PLAN.md](../design/CROSS_DIE_DEBUG_PLAN.md).
- Also built `fc_health` (per-node Wlink FC diagnostic, committed) for validating the incoming FCSM fix, and the TideLink silicon-feedback handover doc.
