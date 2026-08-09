# System-Level Validation Suite — build + first silicon run (2026-08-08)

Follow-on to `docs/SYSTEM_VALIDATION_HOLES_REPORT_2026-08-08.md` (the holes) and
`docs/SYSVAL_TEST_BUILD_SPEC_2026-08-08.md` (the 8-agent build spec). This records what was
**built** and the outcome of running it on the KR260 pair.

## What was built (in the repo, tracked + deployable)
- `tidelink/pynq_host/scripts/eth_sysval_board.py` — board-side primitives: marker-gated `obs`
  (`0x21E0`/`0x21F8`/`0x21E8` + fcsm/cal), `write`/`verify` (delivery-keyed), `seed_local`, and the
  chunked cross-die `read_chunk`.
- `tidelink/pynq_host/scripts/kr260_sysval.py` — dev-host orchestrator (the new regression):
  T1 provenance → T2 obs-probe → T2b good-eye canary → T3 delivery soak → T10 cross-die READ soak
  → T6 endurance. Wedge-safe: die-local verify, Region-F gate between read chunks (CC-5), JTAG-POR
  staging on wedge, marker-gated obs (never PASS/FAIL on an absent obs word), good-eye retry loop.

## Silicon run (2c249ec bits = 1febd59-equivalent; 4 bring-ups this evening)

| Test | Verdict | Notes |
|---|---|---|
| T1 provenance | **PASS** | board `eth_sysval_board.py` sha256 == repo, both dies |
| T2 obs-probe | **PASS** | both dies FCSM=4, cal=1, Region-F present+healthy, witness present |
| T2b good-eye canary | **PASS** | 8/8 byte-exact cross-die write |
| T3 delivery soak | **PASS** | **128/128 byte-exact**, delivery-keyed (die_b local verify) |
| T10 cross-die READ | **FAIL** | read-back over the link errored (bus-error class: `rc≠0`, immediate) |
| T6 endurance | wedge/SKIP | eye wedged pushing past ~128–264 writes; POR staged |

`eye_present=False` on this bitstream — the `0x21E8` WINSCAN_EYE marker (`0x25`) is not present, so the
suite correctly cannot gate on the eye register and uses the canary write as the practical eye gate
(the obs stayed honest — no false eye reading).

## Findings

1. **The honest-regression backbone is proven on silicon.** Provenance, marker-gated obs, the
   good-eye gate, and the **delivery-keyed** 128-write soak all PASS — and the suite does *not*
   false-green: T10/T6 correctly FAIL when the link can't carry the data (the exact H1 hole the
   suite closes).
2. **New result — cross-die READ is *more* eye-sensitive than writes.** On this evening's marginal
   eyes the READ back-path errors (bus-error class) *while the 128-write delivery still lands*.
   Writes tolerate a marginal eye further than reads do. This reinforces report §2.2/H2 (the read/
   R-return path is the weak channel) and the TL-009 reliability priority.
3. **The eye is a per-bring-up lottery, and it drifted worse this evening.** The morning run hit a
   good eye (2576/2576 writes, no wedge); every evening bring-up drew a marginal eye (~128–264 write
   capacity, read fails). So a green *read* run needs a good-eye draw — which is exactly what the
   reliability track (a2l CDC port to make a bad eye survivable + the RX-word-clock constraint +
   RX-eye work) is meant to make deterministic.

## Harness properties demonstrated
Good-eye retry (re-bring-up with a fresh eye draw until the canary lands), wedge-safety (die-local
verify can't wedge; read chunked ≤50 with a Region-F gate between chunks; JTAG-POR staged on wedge),
delivery-keyed verdicts (no config-only false-green), marker-gated obs, self-cleaning (leases revoked
each run; die_a POR-recovered).

## What remains (per the build spec)
- **To get T10/T6 green:** a good-eye bring-up (lottery) or the reliability fixes landing. Re-run the
  suite on a good-eye draw (or after the a2l CDC port) — the read soak is ready.
- **Attended Tier-1 (built as spec, not yet wired/run):** injector-liveness (CRC-free), DECERR
  confinement, error-response propagation, recovery-after-wedge gate, delivery-keyed reliability
  sweep — all wedge-prone/attended; run in dedicated blocks.
- **Regression integration:** wire T1/T3 as default-ON gates in `kr260_eth_regress.py` and invert its
  data-plane default (H1) — a careful edit to the shared file, staged next.
- **Tier-2 backlog (needs rebuild/firmware/re-strap/PHY):** ASIC-config negctrl sim, TideChart Tier-1
  sim, PTP two-die sync, TideChart HW election, ethernet MAC frame, on-die M0 firmware, cross-die
  IRQ→ISR. Two sim gates (ASIC negctrl, TideChart Tier-1) need no silicon — actionable in parallel.

Rig left clean: both boards up, leases revoked, die_a recovered.
