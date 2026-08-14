# D2D wedge — silicon ILA EXONERATES the TideLink transport; the wedge is at the AXI-channel layer (NOT yet localized). Corrected 2026-08-13.

**From:** nanoSoC eth-chiplet integration (two-board KR260 silicon).
**Date:** 2026-08-13.
> ## ⚠️ LATEST — die_a ILA overturns the mechanism below (2026-08-13, end of day)
> A live die_a ILA (capture proven live: `sub_stall_ctr_r` sawtooths 1600..9630) froze the injected wedge:
> `ahb_sub_hreadyout=0`, **`sub_aw_accept=0`, `sub_wr_os_ctr=0`, `synth_b_pending=0`, `sub_axi_progress=0`.**
> The write **never reaches s_axi** — it is blocked at the AHB layer. This **REFUTES** both mechanisms this
> doc built toward: (a) the synth-B `||sub_axi_progress` arming-gap (the write is never counted, so that
> path is irrelevant) **and** (b) "die_a starves on a lost B" (H2-as-cause — `sub_wr_os_ctr=0` means no
> write is outstanding-awaiting-B). **The head-of-line age timer in §4.1 would have done nothing — DO NOT
> BUILD IT.** New lead (measured): a **bridge deadlock** — an override term holds `ahb_sub_hreadyout` low
> (`:1909`); candidates narrowed to **`wr_hold_r` (TL-002)** or `(ext_is_nonseq && !pipe_valid_r)` (both
> write-pipeline; `sub_err2_r` drives *high* so it's out; `rd_pipe_r` is read-path). Grounded: `:1828-1834`
> already documents a `wr_hold`-stuck hang whose `synth_b_pending` guard *this* state (`sub_wr_os_ctr=0`)
> defeats — same "prior fix's guard defeated by an unanticipated route" shape as Fix H. **Next:** one more
> ILA build probing the override terms (`wr_hold_r`/set/clr, `ext_is_nonseq`, `pipe_valid_r`, `rd_pipe_r`),
> combined with the die_b readback in one run. If it's `wr_hold_r`, TL-002 is implicated in the wedge it
> was meant to help. Everything below is the (now-superseded) path to this measurement.

**Status (current, 2026-08-13 — supersedes earlier drafts). THREE distinct failure modes:**
- **die_a wedges DETERMINISTICALLY** on one AW byte-0 CRC inject (both builds). **TL-035 has NO
  DEMONSTRATED EFFECT** (both arms wedge; the earlier "conversion" claim is RETRACTED — n=1, a baseline
  repeat flipped it). Keep TL-035 on hygiene grounds; do not sign as the fix, do not revert.
- The die_b `OBS_AXI` signature is **NONDETERMINISTIC but with mechanism meaning** — whether die_b's
  *inbound* bridge accepts the recovered AW decides which mode you get:
  1. **injected + `ini_aw`** (dominant, 4/5): `m_axi_awvalid=1/awready=0` at **`u_xhb_mng`** (AXI→AHB
     *inbound*, `:2543`) — the re-issued write not accepted toward die_b's AHB. **Open ownership fork**:
     `u_xhb_mng`'s `.hready` = `ahb_mng_hready`, an *input port* to tidelink — so the blocker may be die_b's
     **SoC AHB fabric, outside tidelink/XHB500** (§2). *(hazard-list/synth-B/Fix K are the OTHER bridge
     `u_xhb_sub` — not this stall.)*
  2. **injected + all-clean → H2, CONFIRMED (r3, n=1):** die_b **completes** the write (data lands
     byte-exact, `0xB0008000` at idx0..3), Region F legitimately clean, but the **B is lost on the RETURN
     path** and die_a starves. **"Lost B" is RESURRECTED for this subset** (it was only refuted for the
     `ini_aw` subset). Crux: synth-B (the return-B backstop, `u_xhb_sub` `:1857/1865/1873`) *should* rescue
     this — check whether it's in the r3 build and whether it fires (§1.5).
  3. **spontaneous (no inject):** die_a wedges under sustained load, die_b silent — candidate **die_a
     *outbound* `u_xhb_sub` soak-wedge** (§1.5).

**Relates to:** `AXI_DATANODE_RECOVERY_AMPLIFIER_SOUND_2026_08_01.md` +
`HANDOVER_AXI_DATANODE_2026_08_03.md` (synth-B / I5), and corrects the two intervening root-cause docs
(`ROOT_CAUSE_D2D_DELIVERY_WEDGE_2026_08_10`, `..._CORRECTED_2026_08_11`).

Rig: die_a = kr260_01 = 10.22.24.159 (initiator), die_b = kr260_02 = 10.22.24.153 (target).

---

## 0. Retraction (what the first draft got wrong)

The first draft of this doc claimed the ILA **confirmed a lost write response (B/HRESP)** and that
**"a CRC fired and recovery completed."** A peer (TL-035 hardware-validation session) flagged both, and
**I verified the corrections against the RTL — they are right:**

> *What this section retracts is the original **method** — inferring a lost B from transport-layer probes
> that cannot see the B channel. Lost-B itself is **not** dead: it was refuted only for the `ini_aw` draws,
> and is later **CONFIRMED for the all-clean draws** by proper die_b memory-readback evidence (§1.5, H2).*

1. **The 22 `dbg_*` probes observe the TideLink TRANSPORT, not the AXI channel nodes.** Trace:
   `obs_fcsm_state_o` → `Wlink.v:1132` → `tl2wl` (`wlink_tidelinktl`) = **`WlinkGenericFCSM_6`**, which
   carries `io_app_a2l_*` / `io_app_l2a_*` (the 48-bit serial transport). The probe set is
   transport-FCSM + a2l-replay + credit; **none observe the AW/W/B/AR/R AXI channel handshakes** — the
   layer that actually wedges. So the ILA cannot see, let alone confirm, a lost B.
2. **`dbg_cr_seen` is a CREDIT witness, not a CRC flag.** `WlinkGenericFCSM_6.v:90`: "master's CR(0x44)
   packets — `cr_pkt_seen_rx` latches." It is 1 on every healthy link since reset. The "CRC recovery
   completed" reading was wrong.
3. **The designed trigger `dbg_a2l_wedged` cannot fire at this wedge** (`axi_chiplet_controller.sv:2152`
   clears the stall counter on `app_rdy`, and `app_rdy=1` at the wedge). It read 0 across all 4096 → the
   harness logged "ILA capture timeout"; the frozen window came from a forced capture.

## 1. What the ILA capture DOES legitimately show (transport is exonerated)

Force-captured frozen wedge, 4096 constant samples, transport-layer probes:

| probe (transport layer) | value | meaning |
|---|---|---|
| `dbg_fcsm_state` | 4 | LINK_IDLE — transport NOT stuck in recovery |
| `dbg_a2l_full` | 0 | a2l replay buffer NOT full — no transport backpressure |
| `dbg_a2l_app_rdy` / `dbg_a2l_app_v` | 1 / 0 | transport ready, nothing being offered to it |
| `dbg_a2l_wptr` / `dbg_a2l_sack` | 2 / 1 | one-word gap — not a pointer-lap tear |
| `dbg_a2l_lnk_empty` | 1 | transport FIFO empty |
| `dbg_fe_rx_cred` | 0x1f | front-end RX credit full — NOT starved |
| `dbg_cr_seen` | 1 | credit (CR) exchange happened at bring-up (NOT a CRC/recovery flag) |

**Valid conclusion:** at the wedge the **TideLink transport is idle and healthy** — not stalled, not
backpressured, not credit-starved, not stuck in a recovery state, no pointer tear. This **refutes the
four transport-level flow-control theories** (a2l self-latch, FCSM state-7 NACK self-defeat, credit
starvation, mailbox tear) — those live in the layer the probes do cover.

**What it does NOT show:** which AXI channel is hung, and whether a write B was generated-and-lost,
never-generated, or returned as an error. Those handshakes are unobserved by this build.

## 1.5 SILICON READOUT — Arm B, 2026-08-13 (the localization)

A two-board A/B (TL-035 session) captured `OBS_AXI_NODES` across a single AW byte-0 CRC inject. Arm B =
`.tl033` build carrying **TL-035 Part-A+Part-B** (state-7 watchdog fix), md5-verified in the packaged IP.

```
pre_inject   die_a 0x21E0 = 0xad800000   (all-clean)
pre_inject   die_b 0x21E0 = 0xad800000   (all-clean)
-- single AW byte0/bit0 inject @ die_a, both dies fcsm=4/cal=1 pre-inject --
post_inject  die_b 0x21E0 = 0xad408020
post_inject  die_a          unreadable (PS wedged, ssh timeout — the symptom)
```
`0xad408020` decodes (verified both sides) to: **`ini_wedge_sticky={aw}` + `ini_stall_live={aw}`, tgt
clean, `b` clean on both faces, `resp_err=0` both.** Face-mapping resolved from RTL (below): `axi_tgt_0`
is an input subordinate (local PS ingress, `:271`); `axi_ini_0` is an output manager that re-issues the
incoming remote write into the **local** slave (`:314`); `role_is_master` and the `-flip` build do **not**
remap them. So die_b's `ini_aw` = **die_b re-issuing die_a's write into die_b's own memory, stuck at the
address phase.** The write crossed the link; its **AW never lands in die_b's memory.**

**Three conclusions:**
1. **"Lost B response" is REFUTED by positive contradiction** (not merely unsupported): a sustained `aw`
   wedge means the address phase never completed, so no B was ever due — incompatible with "write
   completed, B lost." Robust two ways: face-independent (channel = AW is unambiguous), and
   direction-resolved (die_b re-issue side).
2. **The Region F sampler is proven alive** for this path — the word *latched* `0xad800000→0xad408020`
   and was read through slow polling, impossible on a dead front-end (closes TL-039's "dead" branch for
   the aw path; the b-tap is inferred alive by structural identity, not directly exercised). This does
   **not** rehabilitate TL-009's `0xad800000` — that stays unsound by construction (§3 blind spot).
3. **TL-035 is present and does NOT prevent this wedge** → for this mode it is necessary-not-sufficient
   at best; do not sign it off as *the* wedge fix.

**Arm A (no-fix) readout — the "conversion" is RETRACTED (signature is nondeterministic):**
```
run  arm       die_b PRE      die_b POST     die_a    rc
1    tl035     0xad800000  -> 0xad408020     WEDGED   1   (ini_aw stuck)
1    baseline  0xad800000  -> 0xad800000     WEDGED   1   (all-clean)   <- first draw
1r   baseline  0xad800000  -> 0xad408020     WEDGED   1   (ini_aw stuck) <- REPEAT of same build
```
The baseline **repeat flipped to `ini_aw`**, so the die_b signature is a **per-run draw, not a property of
the build.** The "TL-035 converts never-reaches-AXI → stalls-at-AW" story is dead. What stands: die_a
wedges deterministically on both builds; TL-035 shows no effect on it.

**Decomposition (the nondeterminism is itself the clue).** die_a's wedge is deterministic while die_b's
signature varies ⇒ die_b's `ini_aw` stall is **not the sole cause** of the die_a wedge. Per-run outcomes,
distinguished by a cheap **die_b local-memory readback** (pre vs post inject, via `kr260_eth_soak_fwd.py
verify` on `shared_sram_0` — a link-free local read that survives die_a's hang):
- **H2** — injected marker LANDED on die_b ⇒ the write completed there, its **B was lost on the RETURN
  path** ⇒ *tidelink return-side* owns it (this is the only door still open for the "lost B" idea, for the
  all-clean draws only).
- **H1** — injected marker ABSENT ⇒ die_b never completed it ⇒ *die_b's SoC AHB fabric / `u_xhb_mng`* owns
  it (the `ahb_mng_hready`-low branch, §2).
- **H3** — only the resume-stream addrs changed, injected marker absent ⇒ the injected beat was **silently
  dropped** while die_b kept accepting later writes.
Peer has this wired for the remaining runs; the first all-clean draw gives the decisive byte.

**H2 CONFIRMED (r3 tl035, valid inject, n=1).** die_b post `0x21E0=0xad800000` (all-clean), die_a WEDGED,
and the die_b memory readback moved `idx0..3: 0xa5a5000X → 0xb000800X` (idx4..15 untouched). `0xB0008000`
is exactly the sweep's AW/byte0/bit0 pattern (`cov_errinject_sweep.py:266`), and the injected beat is
resume word 0 = idx0 — so **the injected, CRC-corrupted write's data landed byte-exact in die_b memory**
(+ 3 more), then die_a wedged. die_b received/accepted/completed the write; the **B was lost on the return
and die_a starved** (4-then-stop fits outstanding-write exhaustion). **The crux:** synth-B — the return-B
backstop on `u_xhb_sub` (`sub_wr_stuck_fire :1857 → synth_b_pending :1865 → s_axi_bvalid :1873`) — is
*designed to rescue exactly this* (sub_wr_os_ctr>0, B never returns, timer expires → inject synthetic B,
~2.6ms). die_a wedged persistently anyway, so either **(a)** synth-B isn't in the r3 build (→ it is the
untested fix) or **(b)** it's present but doesn't fire/rescue (→ a real AXIREC residual; may match the
earlier "synth-B present but insufficient" finding). A **die_a ILA** (`sub_wr_os_ctr`, `synth_b_pending`,
`sub_osr_ctr`, `s_axi` B handshake) splits (a)/(b). Caveats: "completed" is established for the landed
words, not the full stream; and *why* the B was lost is unshown (a separate return-path question, off the
fix's critical path — the head-of-line timer/firewall survive a lost B regardless of cause).

**Closing tally (8-run batch, re-extracted from per-run logs).** 6 valid injected runs: baseline 3× `ini_aw`,
tl035 2× `ini_aw` + 1× all-clean. **Memory readback, 3/3 injected runs with a readback show the write
LANDING** — on BOTH signatures and BOTH arms (`ini_aw`: CHANGED[0,1,2]; all-clean: CHANGED[0,1,2,3]);
both no-inject runs land nothing. This is the measured confirmation that **`ini_aw` is a secondary
observable** (write lands either way) and the injected failure is a **lost completion, not a lost write**.
TL-035: NO DEMONSTRATED EFFECT at n=6 (both arms wedge, both produce both signatures, write lands either
way) — keep on hygiene, don't sign as the fix, don't revert.

**A SECOND, DISTINCT wedge (spontaneous, no inject) — n=1.** On one baseline run the 200-beat soak failed
and die_a wedged (PING_DOWN) *before any inject ran*. Resolved observations:
- **Clean, not corrupt** (Q1): the failed words read `got=0x00000000` (POR-zeroed = never landed), not
  wrong bytes — the un-completed/clean class, not TL-001 data-integrity.
- **Different signature from the injected wedge** (Q3): die_b read **all-clean** (`0xad800000`), no
  wedge-sticky, `wedge=False`. So it does **NOT** share the injected wedge's `ini_aw` signature.
- **CRC involvement unmeasurable** (Q2): no injected CRC (6b precedes inject); a *natural* CRC is
  unobservable here (ECCCNT `0x2114` is the dead-tied counter, no other witness).

**Interpretation: two distinct failures mapping to the two bridges on the two dies.** The injected wedge
is die_b's *inbound* `u_xhb_mng` (`ini_aw`). The spontaneous one is die_a wedging under sustained load
with die_b silent — which fits die_a's *outbound* `u_xhb_sub` **soak-wedge**, the one the XHB500 comment
itself names (`:1515` "die_a PS SmartConnect saturates … on-silicon N-write soak hard-wedge"). die_b
all-clean is *expected* there — die_b's OBS taps are structurally blind to a die_a-side outbound wedge.
So the `u_xhb_sub` / hazard-list / synth-B / Fix K machinery (wrong bridge for the *injected* wedge) is
the **leading candidate for this *spontaneous* one**, and synth-B/Fix K (TL-003/005) are its candidate
fixes. Confirming it needs a **die_a ILA** (tgt face + `u_xhb_sub` hazard occupancy / `sub_wr_os_ctr` /
`synth_b_pending`) — die_b OBS is the wrong die. **Severity not bumped** (the earlier bump was conditional
on same-class + CRC-independent; Q3 says not-same-class, Q2 says CRC-independence untested). Logged as a
real observation: sustained writes alone stopped landing and wedged die_a with no sticky anywhere —
which TL-009's Region F ground truth would not have predicted. Caveat: "first miss at word 1" is early for
a 4-deep-fill soak, so `u_xhb_sub`-soak is a hypothesis pending the die_a ILA, not asserted.

## 2. Where the wedge is (localized) and what it is NOT

When the `ini_aw` signature is present, the wedge is die_b's re-issued write **not accepted at
`u_xhb_mng`** — `m_axi_awvalid=1 / m_axi_awready=0` (`axi_ini_0_aw_valid` OUT, `axi_ini_0_aw_ready` IN,
`:314/:315`, wired to `m_axi_aw*` at `tidelink_top.sv:2903-04`). It is **NOT** the transport layer (§1),
and **NOT** the AXIREC lost-completion/B family for these draws (§1.5).

> ⚠️ **CORRECTION (two XHB500 instances).** An earlier version of this section pinned the stall on the
> hazard-list / `sub_wr_os_ctr` / synth-B / Fix K machinery. **That machinery is on the OTHER bridge** and
> does not apply to this stall:
> - **`u_xhb_sub`** (`tidelink_top.sv:2456`, `xhb500_ahb_to_axi`, **outbound** — this die's PS→link, `s_axi`
>   side): hazard list, `sub_aw_accept = s_axi_awvalid&s_axi_awready` (`:1570`), synth-B, Fix K.
> - **`u_xhb_mng`** (`:2543`, `xhb500_axi_to_ahb`, **inbound** — remote write→die_b's local AHB, `m_axi`
>   side): `.awready(m_axi_awready)`, `.hready(ahb_mng_hready)` (`:2618`). **This is our stall.**
> Consequence: **synth-B / the hazard list cannot see this stall at all** (different bridge, opposite
> direction) — which is the strongest reason an independent **AXI-timeout/firewall** backstop (§4) is the
> only thing that can observe this class.

**Open ownership fork — resolve first.** `u_xhb_mng`'s AHB-side `hready` is `ahb_mng_hready`, an **input
port** to tidelink_top (`:313`) = the tidelink↔die_b-SoC boundary. At the wedge:
- `ahb_mng_hready` **LOW** ⇒ the blocker is **die_b's SoC AHB fabric/memory (nanosoc / eth-subsystem),
  outside tidelink and XHB500** — `u_xhb_mng` is just faithfully back-pressuring a downstream that never
  completes. Different subsystem, likely different owner/repo.
- `ahb_mng_hready` **HIGH** but `m_axi_awready` LOW ⇒ `u_xhb_mng`'s own AXI→AHB FSM is stuck (vendor
  XHB500, read-only) → wrapper workaround.
The cheap `die_b` memory readback (§1.5 H1/H2) front-runs this fork for the all-clean draws: marker landed
⇒ fabric completed it ⇒ return-path (tidelink); marker absent ⇒ fabric/`u_xhb_mng` never completed it.
Nondeterminism fits a timing race — whether a prior inbound beat is still draining on die_b's AHB when the
recovered AW arrives.

**Two distinct FCSM families — don't conflate them (TL-035/TL-036).** The AXI channels each have their
own FCSM — `base=axiaw` (0x80), `_1=axiw`, `_2=axib`, `_3=axiar`, `_4=axir`, at
`AXI4ToWlink.v:567/605/643/681` — separate from the transport `WlinkGenericFCSM_6` my probes observed.
The TL-035 state-7 NACK-watchdog self-defeat (sticky `socl_l7_real_crc_seen`) **is fixed in the
AXI-node FCSMs** but **still live in transport FCSM_6** (logged TL-036). So my transport `state=4`
observation says the *transport's* state-7 path isn't the mechanism here — it says **nothing** about the
*AXI-node* state-7 path, which is unobserved. Because TL-035 is fixed there, that path is a **weaker but
not-excluded** candidate; `0x21E0` (§3) plus, if needed, an AXI-node ILA is what settles it.

## 3. The cheap confirming read (do this before any fix)

**`OBS_AXI_NODES` — Region F slot 0.** I confirmed `tidelink_axinode_obs` (`u_axinode_obs`) is bound to
**real** ports at `axi_chiplet_controller.sv:3057-3078` — `tgt`/`ini` `aw/w/b/ar/r` valid+ready plus
`b_err`/`r_err` (`*_bits_resp[1]`), **zero tie-offs**, LIVE in V1+V2, no ILA required.

> ⚠️ **ADDRESS — DO NOT use `0x4403_21E0` on the eth-chiplet build.** That is the Z2/bare-link address
> and is **undecoded here**; reading `0x4403_xxxx` / `0x8403_xxxx` **hard-wedges the PS AXI bus** (same
> class as the no-touch list `0x8403`/`0xA400`/`0x8000`). On eth-chiplet the aperture is window
> `0x4_0000_0000` + SoC address, and the TideLink APB surfaces at SoC `0x2E03_2xxx` — so Region F is
> **SoC `0x2E03_21E0`**. Safest: `eth_tlapb_poke.py read 0x21E0` (it computes the window). (Credit: TL-035.)

**Decode — verified against `tidelink_axinode_obs.sv` (layout comment + the `always_ff` latch):**
```
[31:24] 0xAD presence marker (old/no-OBS images read 0 here)
[23]    data_nodes_healthy  = ~(|wedge) & ~tgt_resp_err & ~ini_resp_err
[22]    any_stall_live      = OR of the two live stall vectors
[21]    ini_resp_err_sticky   completed ini B/R handshake carried resp[1]
[20]    tgt_resp_err_sticky   completed tgt B/R handshake carried resp[1]
[19:15] ini_wedge_sticky  {r,ar,b,w,aw}  stalled (valid&!ready) >= 2^12 continuous cyc
[14:10] tgt_wedge_sticky  {r,ar,b,w,aw}
[ 9: 5] ini_stall_live    {r,ar,b,w,aw}  valid&!ready THIS cycle
[ 4: 0] tgt_stall_live    {r,ar,b,w,aw}
```
**How to read it at a wedge — and its blind spot:**
- A stuck WRITE shows as **`aw`/`w` wedge_sticky** set (tgt `[10]/[11]`, ini `[15]/[16]`) = write
  accepted but not draining. This is the positive signal to look for first.
- A returned-but-errored completion shows as **`resp_err_sticky`** (`[20]`/`[21]`).
- **Blind spot:** wedge/stall both need `valid & !ready`, so a B that is **never generated** (`b_valid=0`
  forever — the AXIREC lost-completion) produces **no `b` stall, no `b` wedge, no resp_err**, and can
  read `data_nodes_healthy=1` (ALL CLEAN) during a genuine PS hang. So **all-clean during a confirmed
  wedge does not mean "no wedge"** — it is equally consistent with a never-returned B *or* a suspect
  instrument (TL-039/TL-040: no test asserts the binding; the unit TB shrinks `WEDGE_LOG2` 12→4 behind a
  hand-written pass-through). TL-009's historical `0xad800000` "healthy → not an FC-node wedge" is exactly
  this unsound inference, and is amended on that ground alone.

**Resolving an all-clean word (in priority order):**
1. **die_b cross-check — instrument-independent, do this first.** die_b generates the B (the write data
   lands byte-exact), so read die_b's B-channel too: **die_b B completed/resp_err + die_a B clean ⇒ the B
   was generated and LOST ON THE RETURN PATH** before die_a's PS. This carries the "B existed" fact on
   die_b's reading and does **not** depend on die_a's sampler being alive.
2. **Validate die_a's sampler — but only with a LATCHING test.** Provoke a *known, sustained* (>2¹²
   continuous same-pattern) stall on an independent channel and confirm `wedge_sticky[19:10]` latches it.
   ⚠️ Do **not** try to prove liveness by polling the *combinational* `stall_live[9:0]`/`[22]` over slow
   (SSH-rate) reads — those pulse for ~ns and a ~1/s poll inspects ~10⁻⁸ of cycles, so a negative proves
   nothing (a zero-power test). The AW inject itself can't be the provocation — it's the DUT, and a
   never-driven B has no stall to catch.
3. **AXI-node ILA** — `mark_debug` on `axi_tgt_0_*`/`axi_ini_0_*` `aw/w/b` (the same ports
   `u_axinode_obs` reads) — the fallback if 1–2 don't settle it.

(TL-035 is running a two-board A/B and will send the `0x21E0` words — die_b pre/post-inject, then
die_a; die_b survives die_a's wedge.)

## 4. Fix direction (converged)

1. **[RTL root of the die_a wedge — injected wedge, confirmed] the synth-B *arming* gap for bufferable
   write streams.** (The spontaneous no-inject wedge's shape is UNKNOWN and held distinct until the die_a
   ILA — do not assume it shares this root.) Grounded in the RTL's own history: `:1513-1525` ("Fix H", 2026-08-01)
   documents this exact wedge — XHB500's EWR path takes bufferable writes 4-deep, a stuck write's B is
   "NEVER timed out → ahb_sub hangs with no backstop … where the errinject resume stream is 32 pipelined
   bufferable writes." Fix H (the `sub_wr_os_ctr` counter) fixed only the **first** of the two timer-reset
   terms at `:1667` (`!sub_axi_outstanding || sub_axi_progress`) — the false-idle. The **second term
   survives**: `sub_axi_progress = sub_r_done | sub_b_done` (`:1574`) still resets the age timer on any read
   or **sibling** write-B, so amid a mostly-succeeding stream the one stuck write's timer never expires and
   **synth-B never arms**. For bufferable writes the stall-based arming path is also dead (EWR retires
   early → `sub_ext_stalled` low). **Fix:** a **head-of-line (oldest-unretired) EWR age timer** that resets
   only when *that* write retires — independent of reads and sibling progress (a global "no write-B in N"
   counter has the same defect one level up). Wrapper-side, beside synth-B, no vendor IP. **Confirm before
   building** (die_a ILA): `synth_b_pending` never asserts *and* `sub_osr_ctr_r` is seen resetting on
   sibling `sub_b_done` — vs the alternative "arms but the synthetic B doesn't retire the PS," which needs
   a different fix.
2. **[FPGA survivability catch-all] AXI Firewall / AXI Timeout IP** (PL, PS HPM0 ↔ SoC AXI). Any
   never-completing transaction becomes a survivable PS bus-error — no JTAG-POR — and it is the **only**
   backstop that also covers the die_b-inbound `ini_aw` case, since synth-B lives on the other bridge
   (`u_xhb_sub`) and cannot observe `u_xhb_mng`.
3. **[secondary, lower priority] die_b inbound `u_xhb_mng` / ownership fork.** The `ini_aw` sticky is a
   *secondary observable* of how far the stream got (r3_baseline showed `ini_aw` **and** the write landed),
   not the die_a-wedge root. If a die_b ILA is ever spent, `ahb_mng_hready` LOW ⇒ die_b SoC AHB fabric
   (outside tidelink); HIGH ⇒ `u_xhb_mng` vendor FSM. Do **not** prioritize a die_b-only build over the
   die_a ILA.
4. **Scope note on TL-005/synth-B:** hw_proven on a **B-node byte-0** inject; `:1520-1522` documents the
   bufferable-stream case as known-unhandled, and the surviving `||sub_axi_progress` term shows it still is.
   "synth-B is present" is true; "synth-B covers this wedge" is not.
5. **[separate] §5.2 byte-1 wedge** (RX-framer desync) — distinct subsystem, still open.

## 5. The ILA method (still reusable, with the probe-set caveat)

The capture harness works end-to-end over JTAG through the PS deadlock (raw inject, NO POR,
force-capture): `scratchpad/ila_capture.tcl` + `scratchpad/ila_capture_run.sh`; bits at
`imp/fpga/output/_ila/` (+ `.ltx`); CSV at `scratchpad/ila_capture_run/ila_capture.csv`. **Caveat now
known:** this build's probe set is transport-only. To ILA the AXI layer, move the `mark_debug` taps to
the `axi_tgt_0_*` / `axi_ini_0_*` `aw/w/b` handshakes (the same ports `u_axinode_obs` reads) — but for a
first pass the `0x21E0` sticky word (§3) needs no rebuild at all.
