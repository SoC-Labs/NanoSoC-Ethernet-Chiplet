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
- **Conclusion:** clean election-convergence testing needs RTL-level work — a POR-fresh state + either a wider election-timeout field or the **G1 deterministic DEVICE_CLASS strap** (die_a<die_b), which also needs a rebuild. Documented in docs/TIDECHART_TEST_PLAN.md (G1/G-VERIF). Not resolvable via register pokes; parked for a rebuild session.

### P5+ — regression runner (this task)
- Consolidating P1-P4 + the M1 link/transfer tests into a repeatable suite (`kr260_eth_regress.py`) so they re-run on every design iteration.

### Regression runner — ✅ kr260_eth_regress.py (10/10 on a clean deploy)
- Consolidates every cross-die test into one repeatable, CI-friendly suite: deploy -> fresh link bring-up -> backdoor -> role -> sram_fwd/rtt/rev -> mailbox -> soak -> tidechart. PASS/FAIL table + non-zero exit on any gating failure + `--json`.
- `--deploy` reflashes both dies from the latest build first (the design-iteration flow); without it, the runner only *verifies* the live link (never re-brings-up — that hazard wedged die_a).
- Validated end-to-end: `python3 kr260_eth_regress.py --deploy --soak-iters 1000` -> **10/10 PASS**, both boards healthy.
- **Bug caught + fixed:** re-running bring-up on a live link (LL_SWRESET) desyncs it and hangs the sender's peer writes -> die_a wedged. Recovered via the per-target POR API (group `board reset` breaks on the `kr260_01_pl` topology member). Both saved to memory.
- Run on a design iteration: `python3 tidelink/pynq_host/scripts/kr260_eth_regress.py --deploy` (or `make -C tidelink/fpga regress_eth_chiplet KR260_PASSWORD=...`).
