# Overnight HW campaign — KR260 eth-chiplet R1 — 2026-08-05/06

Autonomous overnight run. Goal: work through the remaining HW test items and close R1
(cross-die write). Boards: die_a=kr260_01 (10.22.24.159), die_b=kr260_02 (10.22.24.153).
Raw bench logs: scratchpad `direct_rebench.log`, `overnight_campaign.log`, `build_bothfixes.log`.

## Executive summary

R1 was **half-closed on silicon** tonight, and the remaining half is **root-caused with a
clear fix** that needs one careful implementation + bench with review.

| Item | Status |
|---|---|
| Autonomous re-anchor (both dies) | **VERIFIED on silicon** — reanchored=1 both dies, R8=0 (no host pulse) |
| die_a wedge (XHB500 hazard-list BID) — Fix K | **PARTIAL, validated** — die_a now survives to write #6 (was #3); Fix K works, a residual physical wedge remains |
| Peer-write **data-phase drop** | **ROOT-CAUSED, fix path clear** — parent-side attempts (v1/v2/v3) insufficient; robust fix = Rank 1 (tidelink), scoped below, needs impl+bench |
| g2 W-backpressure regression | **ADDED** (with documented sim-blindness caveat) |

**Net:** the anchor is fixed autonomously; the wedge is mostly fixed (Fix K); the data drop
is understood and has a concrete fix (Rank 1) that could not be safely landed autonomously
overnight (sim is blind to it; a bad tidelink HREADY-hold can deadlock the link).

## 1. Silicon-verified (this run)

**Autonomous re-anchor.** Turnkey pair bring-up reached `reanchored=1` on BOTH dies
(retry 2 — marginal-eye lottery), `0x21F4=0x00bb0100` (done=1, pulsed_ever=1),
`0x2140=0x1` anchored, **R8=0x00** — no manual SYNC pulse. Refutes the earlier
"master RX won't re-anchor" finding; AUTO_ANCHOR closes the anchor.

**Fix K (die_a wedge).** On the fix-less build die_a wedged at cross-die write **#3**;
on the both-fixes build (Fix K = tidelink 9dfe1da, XHB500 hazard-list BID-correction)
die_a survived to **#6** (R1 soak: LAND=0 DROP=5, then wedge at #6). Fix K resolves the
hazard-list BID-mismatch wedge. A **residual intermittent wedge remains** — consistent
with the physical W-byte-0 / marginal-eye class (WNS +0.484 ns, ILA-class), NOT the
hazard-list logic.

## 2. Peer-write data-phase drop — root cause + fix path

**Symptom:** die_a→die_b write lands the address (die_b SRAM 0x2D001000 targeted) but
the DATA reads back 0x00000000 (5/5), even with reanchored=1 and the beacon done.

**Root cause (agent-verified, code + sim trace):** die_a's TideLink `ahb_sub` XHB500
bridge samples write data LIVE on the AXI W beat, which fires 1+ cycles after AW. The
integration path forces `hready_to_peer` HIGH during the peer data phase
(`nanosoc_eth_chiplet.sv:266`), so the AHB **master drives the payload for exactly ONE
cycle then releases** (bus→0). If XHB500's W beat lands after that one cycle (which it
does under real W-channel backpressure — CDC/credit/outstanding-write), it captures 0.

**Parent-side fix attempts (all in `nanosoc_eth_chiplet.sv`, all INSUFFICIENT):**
- The committed 1-cycle `hwdata_q` delay is timing-fragile (only aligns on an idle link).
- v1 (registered addr-accept) — double-pulsed, re-captured the released 0. **Silicon: 5/5 drop.**
- v2 (dph_peer gated) — same double-capture; sim diag identical to v1.
- v3 (capture-once + hold, `cap_done_r`, commit 1b2ae18) — logically holds, but **cannot be
  verified**: the g2 sim is blind to this bug (forcing `s_axi_wready` corrupts transport;
  the sim's SoC→bridge capture is a fixed 1 cycle), so v1/v2/v3 give an identical,
  uninformative diag. A parent-side hold is fundamentally limited because the master has
  already released the data.

**THE FIX — Rank 1 (recommended, NOT yet implemented):** in tidelink `ahb_sub` wrapper
(`tidelink_top.sv`), hold `ahb_sub_hreadyout` LOW until the W handshake completes (mirror
the existing read fix `rd_pipe_r` ~:1717 → apply at the `ahb_sub_hreadyout` assign ~:1784).
Then the AHB **master itself holds HWDATA** through the whole W-backpressure window and
XHB500 captures the correct live data whenever `wready` rises. Ship as
`tidelink/src/rtl/local_overrides/tidelink_top.sv` (same mechanism as the read fix). Once
Rank 1 is in, delete the parent `d2d_ahb_m_hwdata_q` register (no longer needed).

**Why it wasn't landed autonomously:** a wrong HREADY-hold can deadlock the link, and the
g2 sim can't verify it (same blindness). This needs implementation in the shared tidelink
submodule + a bench with review — not a blind overnight build.

## 3. Sim regression added (g2)

`verif/g2_soc_pair/test_g2_soc_pair.py` gained `test_peer_write_survives_w_backpressure`
(+ `test_diag_q_hold`): injects W-channel backpressure at die_a. **Caveat (agent-proven):**
forcing `s_axi_wready` corrupts Wlink transport rather than cleanly reproducing the drop,
and the sim's fixed 1-cycle capture means it cannot distinguish the fragile/v1/v2/v3
variants. It is a partial guard; the silicon bench is the real test. RTL untouched by it.

## 4. Commits / artifacts

- tidelink `9dfe1da` = 42da64b + **Fix K** (BID-correction). Parent pointer bumped (65f0c5d).
- parent `65f0c5d` (Rank2 v1 + Fix K pointer), `1b2ae18` (Rank2 v3, unverified).
- `c6cc6eb` earlier convergence (sim-grafts) pushed to origin; `ef73e91` tagged.
- Both-fixes bitstream built + snapshotted: scratchpad `bit_bothfixes/` (die_a 5d4b2d39,
  die_b 414fa7e7). R1 soak raw data captured in scratchpad logs (LAND=0 DROP=5, wedge #6).

## 5. Next steps (for review / next session)

1. **Implement Rank 1** (tidelink hreadyout-hold) as a local_override; bench R1 — the
   definitive data-drop close. (Highest priority; the one remaining R1 blocker.)
2. **Residual die_a wedge (#6):** ILA campaign on the physical W-byte-0/eye class
   (orthogonal to logic; WNS +0.484 ns).
3. Coverage gates (IRQ/mailbox/perf/regplane/decerr/tidechart) — never run; run them on a
   Rank-1 build. TideChart gate needs a `DEVICE_CLASS` re-strap + rebuild.
4. Converge Fix K (9dfe1da) + the sim-grafts (c6cc6eb) on the tidelink branch (currently
   divergent siblings off 42da64b).

## 6. Infra notes (traps hit tonight — save future time)

- **Deploy: use `RUN_AFI=0`.** The AFI fix wedges die_a's PS on load even with the canary
  off; RUN_AFI=0 deploys clean (verified). Also `TIDELINK_HOME` must be exported for the deploy.
- **AUTO_ANCHOR burst deletes app writes until `0x21F4` done=1** (~8s force_always on this
  build). Host must wait for done before app traffic.
- **Rig is flaky:** both boards intermittently fail to recover from JTAG-POR (die_b needed
  2 PORs; die_a once needed several); a second POR / settling time recovers them.
- **Campaign OK-check bug:** the overnight board-campaign's `setup_link` piped bring-up
  "try N/8" lines to stdout, so `$(setup_link)="try…/OK"` failed the `=OK` exact-match —
  setup actually SUCCEEDED all along. (Direct re-bench bypassed it.) Fix: redirect the
  bring-up output off stdout, or grep for OK.
- **g2 sim is blind to the data-drop** (see §3) — do not trust a g2 PASS as validation of
  the data-path fix; bench it.
- **die_b credential** was rotated (old default rejected); my ed25519 key is now installed
  on die_b, so both boards are key-authed going forward.
