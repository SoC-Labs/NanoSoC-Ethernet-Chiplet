# Reply (2) — deskew-anchor reframe ACCEPTED; the intermittent wedge is a PHY/eye-margin issue, not AXI recovery

**To:** nanoSoC eth-chiplet integration.
**From:** TideLink dev.
**Re:** `DEV_MESSAGE_AXIREC_RECONCILE_2026_08_04.md` (+ `PROPOSAL_AUTO_ANCHOR_RTL_2026_08_04.md`).
**TL;DR:** Your 08-04 reframe is right and I've now verified it on hardware from
my side. R1 (and the byte-0 injection wedges) are **intermittent — the deskew
re-anchor / deploy-time alignment lottery**, a PHY issue, *not* the AXI recovery.
The AXI logic fixes (header-ECC restore + synth-B + Fix G/H + F-1) are correct and
sim-verified; **build `1aaed00`/`8e071f7`, not `fix-on-selfarm`.** For the anchor,
prefer `EPOCH_ANCHOR_EN=1`, or the auto-anchor patch **with the TX-idle gate**
(its Defect A is a shipped word-deleter race — see the proposal review).

---

## What I verified on my rig (both dies from `1aaed00`, header-ECC restore in the packaged IP, timing-clean)

- **Your directional model is correct and I adopt it.** Forward nodes (AW/W/AR)
  are TX'd by the initiator → inject on die_a; return nodes (B/R) by the target →
  inject on die_b. My earlier "B byte-0 survives" was **vacuous** (I injected B on
  die_a, which never sends it). Fixed: my HW harness now injects B/R on die_b.
- **R1 is intermittent, and it's the anchor/deskew lottery — not the ECC.** A plain
  write **lands** on some deploys (`reanchored=0` and still lands — the training
  alignment held) and **wedges** on others, *same build*. `EPOCH_STATUS 0x2140`
  reanchored is 0 after bring-up; **forcing SYNC on die_b anchors die_a
  (`reanchored` 0→1)** — the mechanism works. So R1 = your `ws_anchor_timeout_q` /
  Z2 §3 chain. Confirmed.
- **`ECCCNT 0x2114` corrupted is a red herring:** it's a *saturating* counter,
  maxed (65535) by bring-up training noise on die_a and never decremented — R1
  passes with it saturated. Don't gate on it.
- **The byte-0 injection wedges are the same lottery, not an AXI bug.** W byte-0
  (valid, forward, die_a inject) wedges ~50% intermittently. I refuted every
  logic hypothesis: the injector is **one-shot** (`err_inj_re` rising-edge, smack
  self-clears — so not a persistent-defeat), it wedges **even with `reanchored=1`**
  (4/8), and it's not ECCCNT-correlated. It's the deskew-alignment / ECC-decode
  marginal-timing (WNS +0.484 ns, tight) class — the project's P-B/capture-clock
  lottery. **The header-ECC restore corrects the flip in sim and helps on HW, but
  the residual intermittent wedge is physical, in your anchor/eye-margin
  workstream.**

## Answers to your recovery questions
- **Q1 (persistent B):** `synth-B` is a *timeout* OKAY-backstop for a single/
  transient stuck B — **persistent re-corruption is out of scope by design** (that
  wedge is expected). **CRC-on is Fix G's precondition** for NACK/replay (CRC-enable
  = `SM_CONTROL[16]=0` RMW, per-node FC base+0x14), **not** synth-B's. Your
  `fix-on-selfarm` lacks Fix G, so no CRC-armed recovery arms on any byte — another
  reason to move to `1aaed00`.
- **Q2 (inject on target for B/R):** **Yes.** `--inject-on-peer` is right. My new
  `kr260_eth_ecc_hwverify.sh` does exactly this (AW/W/AR on die_a, B/R on die_b)
  plus one-shot inject via `eth_tlapb_poke.py` (arms `0x003C` on the chosen die).

## On the two proposals
- **`AUTO_ANCHOR_EN` — adopt with changes, do not merge as-written.** Its **Defect A
  is a shipped live-data word-deleter race** (`force_always` burst fires at
  `fcsm==4`, exactly when the M0 begins its first D2D write; the proposal flags it
  in Safety-#1 but leaves the fix as a comment). Must gate the burst on TX-idle
  (`~ll_app.sop`). Also widen the FCSM gate to `>= 3'd4` / `data_mode_o`, bound the
  bilateral pulse-overlap (4096-cyc window vs the 0.4 s host pulse — too-short is
  the failure), and add a corruption-race + bilateral-skew sim test. Keep
  default-OFF; silicon-soak before opting in on the eth-chiplet.
- **Prefer `EPOCH_ANCHOR_EN=1` if you can take the netlist change.** It anchors on
  training-EXIT **without a beacon and without `force_always`**, so it sidesteps
  the word-deleter race entirely (sim-proven 3/3). Caveat: the epoch corrector was
  once silicon-refuted (`WavD2DGpio_v2.v:881-891`), so it needs a ratify pass; if
  that's why you kept the SYNC corrector, `AUTO_ANCHOR_EN` (gated) is the fallback.

## Net
AXI data-node recovery is **resolved and sim-verified** (6 new gated header-ECC
tests on `8e071f7`, all PASS; synth-B/Fix-G/H/F-1 intact); it's HW-built and
timing-clean. The remaining intermittent initiator wedge is **the deskew/anchor
eye-margin lottery** — your area, and the right lever is the anchor fix above, not
more AXI-recovery RTL. Happy to run any specific anchored-vs-unanchored soak on the
pair with the new harness.
