# AXI data-node recovery gap — CONFIRMED on silicon by error injection (2026-07-31)

**TL;DR:** I1 (SELF_ARM + FIX-E) resolved **link bring-up** — the pair reaches fcsm=4 and
carries *clean* D2D traffic byte-exact. But the **AXI data-node traffic recovery is still
ABSENT**: a single injected bit-error on the B (write-response) node **hard-wedges the
initiator die**, JTAG-POR-only. **The shipped build already contains the recovery-capable
FCSMs** (flist points FCSM 0–4 at `local_overrides`, gate=8, full `socl_reack`/watchdog
logic) — so this is *recovery present but **ineffective*** for this failure mode, NOT
recovery-stripped; I1 (a bring-up fix) did not address it. (This corrects
`CROSS_DIE_WEDGE_ROOTCAUSE.md`, now stale: it says the AXI nodes ship the deps stripped
copies; I1 re-pointed them to local_overrides.) The "1000-beat soak clean" result was a
clean-BER window (no bit-errors occurred), so nothing to recover from.

## The experiment
`kr260_eth_xfer.py --mode errinject --node B --seed 0xBEEF --stream 32` on die_a, over the
live SELF_ARM link (bitstream `34b006c`, both dies fcsm=4). It uses the Wlink error injector
`0x2E03_003C` (`[7:0]DataID [15:8]Byte [18:16]Bit [24]Enable`; B node DataID=0x82) to flip
one bit on the write-response path, then resumes a short deterministic write stream sampling
Region F (`0x2E03_21E0`) per beat.

## Result (silicon, attended, JTAG-POR-recovered)
| Die | Role | Outcome |
|---|---|---|
| **die_a** (10.22.24.159) | initiator (peer-writes) | **HARD WEDGE** — the injected/corrupted write hung the AXI path with no return; the PS bus (and SSH) went unresponsive. Timeout, not a graceful Region-F trip. JTAG-POR required. |
| **die_b** (10.22.24.153) | receiver (local reads) | **HEALTHY** — `SWI_LANE=0x05890000` fcsm=4, Region F `0xAD800000` data_healthy=1, **wedge-sticky tgt/ini=0x00**, no sticky STATUS faults. |

The wedge is on the **initiator's** side (its master waits forever for the corrupted B
response). die_b's Region F stayed clean because it only did local reads; die_a's Region F
would show the sticky but die_a is unreadable once wedged (the hang precedes any read).

## Interpretation
- **Bring-up: RESOLVED.** SELF_ARM (role-lock self-latch) + FIX-E (bilateral training
  release) bring the link up reliably with the recovery FCSM in place. Confirmed repeatedly
  (fcsm=4 both dies, regress 7/8, 1000-beat clean soak).
- **Error recovery on the AXI data path: NOT resolved.** A single bit-error on an AXI data
  node still produces the unrecoverable wedge. `OBS_FC_CREDIT`/`SWI_LANE[31:17]` observe only
  the sideband FCSM_6, so ordinary soak health never sees the AXI-node stall — which is why a
  clean soak passes while a bit-error wedges.
- These are **orthogonal**: I1 was a bring-up *sequencing* fix; this is the flow-control
  *recovery* gap from `CROSS_DIE_WEDGE_ROOTCAUSE.md`. Do not conflate "link up + clean soak
  passes" with "the wedge is fixed."

## Recommendation (tidelink dev)
The AXI data-node FCSM recovery (`SOCL_L7`/`socl_reack`/watchdog on the 5 `WlinkGenericFCSM
{,_1..4}` copies) is still the open item — this errinject test is the **reproducible
on-silicon proof** and the acceptance gate. A fix must make an injected bit-error on **each**
AXI node (AW/W/B/AR/R) recover (traffic resumes byte-exact, Region F healthy) instead of
wedge. Suggested regression: `errinject` per node × several bits, expecting exit 0
(recovery-present) not a hard wedge.

## Reproduce
```
# link up first (bringup_pair_release.sh). Then, ATTENDED, JTAG-POR staged:
KR260_HOST=ubuntu@10.22.24.159 KR260_XFER_NODE=B KR260_XFER_SEED=0xBEEF \
  bash kr260_eth_run.sh xfer_errinject
#   exit 0 = recovery present ;  hard wedge/timeout = recovery ABSENT (today's result)
# recover: ssh mapstone-dev 'curl --unix-socket /run/fpgahub/fpgahub.sock -X POST
#   http://localhost/api/v1/targets/kr260_01/reset -d {"method":"default","confirm":true}'
```
