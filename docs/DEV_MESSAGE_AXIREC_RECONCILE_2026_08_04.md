# To the TideLink dev — the KR260 eth-chiplet "wedge" is the deskew re-anchor gate (SOLVED), not the AXI recovery

**From:** nanoSoC eth-chiplet integration (two-board KR260 FPGA silicon). **Date:** 2026-08-04.
**Supersedes** my 2026-08-03 message (which framed this as "the AXI recovery fix doesn't hold" —
that was a mis-attribution; see below). **TL;DR:** the cross-die-write wedge is the deskew
never anchoring after bring-up — exactly your Z2 §3 chain, on the eth-chiplet. A SYNC pulse
fixes it on silicon. One RTL follow-up + one genuinely-open recovery question.

## What was actually happening (root-caused on silicon)
Your `HANDOVER_Z2_PICKUP_2026_07_30.md` §3 was the key. On the eth-chiplet, after
`bringup_pair_release.sh` reaches fcsm=4 / cal=1 / cr=1, the deskew corrector is **not
anchored**: `EPOCH_STATUS 0x2E03_2140 bit0 (reanchored)=0` on **both** dies, and R8
(`0x2100`)=0 (no SYNC beacon). We ship `EPOCH_ANCHOR_EN=0 ⇒ SYNC_REANCHOR_EN=1`
(`WavD2DGpio_v2.v:159/846`), which only re-anchors on a live SYNC beacon. The winscan
`WS_FINALIZE` anchor gate fires **during the scan, before both dies are up, so it times out
and releases** (`ws_anchor_timeout_q`). Result: words never reassemble → the peer-write never
lands (die_b SRAM = garbage) → no B response → the initiator hangs. Every "wedge" we chased
was this, not the B-response path.

## The fix (silicon-demonstrated, host-side, no rebuild)
After bring-up, emit SYNC then release, on both dies:
```
write R8 0x2E03_2100 = 0x1C  (insert_en[2]+force_always[3]+robust[4])
wait ~0.4s → write 0x00       (release — never carry data with force_always; it deletes words)
```
`reanchored` goes **0→1 and latches** after release. Then, from a clean POR on the pair:
- cross-die write lands byte-exact (`0xC0FFEE01`, PASS both directions), initiator stays alive;
- **300-beat and 200-beat soaks: 0 mismatches, FCSM_min=4, no sticky faults.**

This is the "1000-beat soak clean" behaviour restored. The complete working recipe is
`deploy → bringup_pair_release.sh → SYNC-anchor pulse → data`.

## Ask #1 — fold the anchor into bring-up (RTL)
The manual pulse should be automatic. I've drafted a one-shot post-link-up SYNC burst
(`AUTO_ANCHOR_EN`, default-OFF param like `SELF_ARM_TRAIN_EN`, OR'd into the `swi_sync_*_in`
ports at `axi_chiplet_controller.sv:6455/6461/6470`, fired on `sync_obs_fcsm_state_1==3'd4`
after a dwell, one-shot per episode) — full patch + safety notes in
`docs/PROPOSAL_AUTO_ANCHOR_RTL_2026_08_04.md`. The one thing needing your call is the
`force_always`-over-live-data race (your R4 word-deleter): the pulse must complete before the
app's first D2D write — I gate it on link-up before app traffic, but you may want an explicit
`~sop` gate. Would value your review before I build/bench it.

## Ask #2 — the one genuinely-open recovery question
Re-tested your B-response recovery correctly this time (my earlier "injector no-op" was
directional: the errinject arms `0x003C` on die_a, the *initiator*, which never TRANSMITS the
B response — DataID 0x82 — so it corrupted nothing). Arming the injector on **die_b** (the
B-sender), then writing from die_a, **does** fire and **hard-wedges die_a** — the `synth_b`
recovery does not save a persistently-corrupted B (the injector stays armed → every retry's B
is re-corrupted). That matches your open §5.2. Two questions:
1. Is the recovery meant to cover a *persistently*-corrupted B, or only a lost/single one? If
   the former, it isn't firing on our build — is CRC-checking a build/runtime precondition we're
   missing (your docs stress "CRC-on")?
2. Should the errinject harness inject on the **target** die for B/R nodes (it currently always
   runs on the initiator)? Happy to add a `--inject-on-peer` mode.

## Rig
Boards left clean + anchored (both fcsm=4, reanchored=1), leases released. Build =
`integ/fix-on-selfarm` (855096a + your 3 recovery commits cherry-picked). Host tools:
`force_sync.py` (arm/release/read R8+EPOCH), `epoch_diag.py`, `bnode_reg.py` (die_b inject +
die_a B-CRC/RegionF). Redeploy ~2 min/board — glad to run any sequence you want.
