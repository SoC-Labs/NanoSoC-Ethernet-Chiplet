# Reply — TL-027 patch is correct, but the durability gap is the PARENT PIN, the two "consolidated" branches have FORKED, and your TL-032 calibrator fix makes me retract my R2 verdict

**To:** TideLink dev.
**From:** nanoSoC eth-chiplet integration (two-board KR260 silicon).
**Re:** `TL027_A2L_ETHCHIPLET_HANDOFF.md` + `0001-fix-TL-027-…patch` (2026-08-10).
**TL;DR:** The re-point is right and the a2l self-latch fix is **already committed in my
submodule build** (`8104b1e`) — so it was live in the 128/128 HW result; sign-off criterion is
met and reproducible supervised. But two of the handoff's mechanics are stale, the real durability
gap is the **parent submodule pin** (not my working tree), and your build line and mine have
**forked into two `integ/tidelink-consolidated-*` branches, neither pushed**. Your **TL-032
calibrator wrap-stitch (`3f037c0`) is in your line but NOT in the build I HW-validated**, and it
invalidates my "R2 = eye-drift" call — I'm retracting that pending a retest. Also: **our TL-0xx
numbering has collided.**

Rig map unchanged: die_a = kr260_01 = 10.22.24.159 (initiator); die_b = kr260_02 = 10.22.24.153.

---

## 1. The a2l self-latch fix — CONFIRMED wired + HW-proven (your sign-off criterion is met)

Verified in my submodule (`nanosoc-ethernet-chiplet/tidelink`):
- `WlinkGenericFCReplayV2_{1,3,5}.v` present with the 3-part fix (15/15/16 markers);
- **both** `flists/tidelink_fpga_v2.flist` and `flists/tidelink_top_full_asic_v2.flist` re-point
  `_1/_3/_5` → `local_overrides`, and it's **committed** (`8104b1e`), reachable from HEAD;
- that is the build that gave **T3 128/128 writes + T10 128/128 reads byte-exact, no ~6-word
  wedge**. So the self-latch fix was genuinely live, not a no-op, in my result.

I can reproduce the A/B supervised (FIXED sustains; deps-reverted wedges at ~6 words) whenever you
want it independently witnessed.

## 2. Two corrections to the handoff's mechanics (both verified)

- **"the re-point exists there uncommitted (the dev's local work)"** — not so. In my submodule
  it's **committed** at `8104b1e`. `git status` shows the flists clean; the only dirty files are my
  state-7-watchdog FCSM edits (your TL-035 Part-A — see §5).
- **"`git am` the 0001 patch"** — it **will not apply** onto my HEAD (`28409f5`): the patch's
  removed-context lines (`-…/deps/…WlinkGenericFCReplayV2_1.v`) no longer exist there — they're
  already `local_overrides`. A cherry-pick of `1037a63` conflicts/empties for the same reason.
  The outcome is already achieved on my line; don't re-apply.

## 3. The REAL durability gap: the parent submodule pin (not the working tree)

- The eth-chiplet parent (branch `fix/tag-ram-gwen`) records submodule pin **`235d758`**.
- `235d758` is an ancestor of my HEAD but **predates the re-point** — I read its flist directly:
  at `235d758` the nodes still point `_1/_3/_5` at the **unfixed `deps/`**.
- **So a clean `git submodule update` / fresh CI checks out `235d758` and ships the fix as a
  no-op again.** That is the durability hole, and it lives at the parent pin, not in my working
  tree. Fix = **bump the parent pin** to a commit containing `8104b1e`. Two gates on that:
  (a) the parent is mid-work on the concurrent `fix/tag-ram-gwen` branch; (b) my submodule HEAD
  `28409f5` is **unpushed** — a from-scratch clone can't resolve it. Both must be handled before
  the pin bump is durable off this host.

## 4. The forked "consolidated" branches — please reconcile to ONE pushed tip

There are **two** `integ/tidelink-consolidated-*` branches, forked at common ancestors
`1112d63`/`9210dc5`, **neither pushed to a remote**:

| | my submodule (what the FPGA build consumes) | your `tidelink-consolidated` |
|---|---|---|
| branch | `integ/…-2026-08-**09**` | `integ/…-2026-08-**07**` |
| tip | `28409f5` | `1037a63` |
| a2l re-point | `8104b1e` ✓ | `1037a63` ✓ (equivalent) |
| **unique content** | header-ECC restore (`1aaed00`)*, `cf0f1ab` (TL-006/TL-020), **lint + sysval drivers + docs chain** | **`3f037c0` (your TL-032 calibrator wrap-stitch)** |

(*`1aaed00` is on both; the uniquely-mine items are `cf0f1ab` + the lint/sysval/docs commits.)

Both re-point identically, so the self-latch fix is on both lines. But each carries substantive
work the other lacks — most importantly **your `3f037c0` is NOT in the build I HW-validated**, and
my lint/sysval/docs + `cf0f1ab` are not on your line. **These need merging into one tip, pushed,
before the parent pin can be durably bumped.** They don't conflict on the re-point; `3f037c0`
touches the calibrator + registry + a new test, which come across cleanly. Your call on merge
direction — I'd suggest merging both ways to a single pushed `integ/tidelink-consolidated` and
retiring the dated variants.

## 5. TL-0xx numbering has COLLIDED — let's adopt your registry

Your `BUG_REGISTRY.yaml` and my local labels disagree:

| bug | your (consolidated) label | my local label |
|---|---|---|
| calibrator wrap-straddle stitch | **TL-032** | (none — new to me) |
| a2l revert-aware guard (rewind `a2l_link_addr` on `link_revert`) | (folded into TL-027?) | **TL-032** |
| state-7 NACK watchdog dead after first CRC | **TL-035** | **TL-033** |
| credit-underflow BUG-002 | TL-033 | (none) |

So **your TL-035 == my TL-033**, and our TL-032/033 mean different things. You own the registry —
**I'll adopt your numbering** (TL-035 = watchdog; my "a2l revert-aware guard" I'll re-file under
whatever number you assign, or fold into TL-027 if that's where it belongs). Flagging so we stop
talking past each other.

## 6. Your TL-032 (`3f037c0`) makes me RETRACT "R2 = eye-drift"

I previously reported R2 (T6 endurance wedge, variable beat 768 vs ~1024) as **eye-drift, not
RTL**, on the reasoning "variable beat ⇒ physical, not a fixed RTL boundary." **`3f037c0`'s own
finding kills that reasoning** — the drop lottery is *"PRIMARILY DIGITAL, not an analog eye,"* and
a per-POR digital calibrator lottery produces variable behaviour too. **And my R2 build did not
contain `3f037c0`** (it's not on my line). So:
- I'm **withdrawing** the "R2 = eye-drift, not RTL" attribution as premature.
- Caveat the other way: `3f037c0` as described targets **bring-up-time** drop-to-`(0,0)` (your
  TL-001 class), while R2 wedges **mid-soak** at a variable beat — so it may be necessary-not-
  sufficient for R2. **Question:** do you expect the wrap-stitch to touch a *mid-soak* endurance
  wedge (e.g. a marginally-promoted straddling eye losing lock as the free-running phase drifts
  across the wrap), or only the per-POR bring-up drop? Either way I'll **re-run T6 endurance on a
  build that includes `3f037c0`** before re-attributing R2.

## 7. Agreements / open reconciliations

- **TL-035 (state-7 watchdog):** agreed — Part-B (§6 state-7-exit) must NOT ship without the
  **die_b AW-FCSM ILA** during the inject dwell. My Part-A (the watchdog-revive edits to
  `WlinkGenericFCSM{,_1,_2,_3,_4}.v`) is sitting **uncommitted in my submodule working tree**; I'm
  holding it per that gate rather than landing it blind. Say the word and I'll build the ILA and
  run the attended capture (capture `state`, `send_nack_req`, `socl_l7_wdog_cnt`,
  `auto_tx_out_advance`).
- **R1 errinject:** still expected to wedge die_a on the first AW inject (silicon-only — does not
  reproduce in the a2l unit bench *or* the fuller `tidelink_axi_datanode_recovery` FCSM env across
  4 configs incl. `ASIC_MIRROR=1`). Agreed it's TL-035's ILA to characterize, not a self-latch
  blocker.
- **TL-028 (RX-word gen-clock):** your `3f037c0` note says "ASIC SDC applies the RX-word gen-clock,
  FPGA XDC doesn't." That **conflicts with my open item** that flagged the /16 recovered RX word
  clock as unconstrained (~27% of the chiplet untimed, no `create_generated_clock`). Which build /
  SDC were you reading? If the ASIC SDC already applies it, my open item is narrower than I thought
  (FPGA-only, low-leverage vs the `USE_SHARED_CAP_BUFG` hoist you mention). Let's reconcile before
  either of us re-times anything.

## Net / asks

1. **Merge the two `integ/tidelink-consolidated-*` tips to one pushed commit** (yours has
   `3f037c0`; mine has `cf0f1ab` + lint/sysval/docs + the equivalent re-point). Then I bump the
   eth-chiplet parent pin to it (gated on `fix/tag-ram-gwen`).
2. **Don't rely on `git am`/cherry-pick of `1037a63`** into my submodule — already achieved.
3. **Confirm the TL-0xx numbering** (I'll adopt your registry).
4. **`3f037c0` vs R2:** tell me whether to expect it to touch mid-soak endurance; I'll retest T6 on
   a build that includes it regardless.
5. **TL-035 ILA:** ready to build + run attended on your go.

## Rig / provenance

Boards clean, leases released. HW-validated build = my submodule `28409f5`
(`integ/tidelink-consolidated-2026-08-09`) = a2l self-latch fix wired (`8104b1e`) + data-mode
election gate + CPU0 firmware IMEM-bake — but **without `3f037c0`**. Supporting:
`docs/DEV_MESSAGE_A2L_SELFLATCH_SILICON_2026_08_09.md` (my prior handover),
`scratchpad/plan_a2l_r1_fcsm.md` (§6 state-7-exit spec). Happy to rebuild with `3f037c0` folded in
and re-run delivery + endurance + errinject on your word.
