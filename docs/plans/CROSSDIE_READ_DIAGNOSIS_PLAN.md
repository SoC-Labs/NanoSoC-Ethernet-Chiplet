# Cross-die read intermittency — diagnosis plan

**Status:** POST-SUBMISSION. Nothing here changes the tapeout; the RTL is frozen at
`5e8bdb5a` (`v0.90`) and no fix is folding in. This plan exists so the defect is
understood before anyone relies on the path, and so the next person does not
re-derive six runs' worth of evidence.

**Written 2026-08-24. EVIDENCE BASE COLLAPSED THE SAME DAY — read this box first.**

> ## ⚠⚠ THE FAILURES THIS PLAN WAS WRITTEN TO DIAGNOSE ARE LARGELY NOT DUT FAILURES
>
> The six sysval runs behind §1 were taken through a harness that **relabels an ssh
> transport failure as a data mismatch.** Verified from the archive and the source:
>
> ```
> sysval_a{4,5,6}.json   detail = 'read mismatch @100: '     <- out[:80] is EMPTY
>
> kr260_sysval.py:58   ... 2>/dev/null            remote stderr discarded
>                :60   return rc, out.strip()     ssh stderr discarded
>                :238  if rc != 0 or "READCHUNK" not in out:   rc=255 -> "read mismatch"
>                      no ControlMaster: a FRESH ssh connection per board call
> board sshd:          maxstartups 10:30:100, logingracetime 120  (~30% reset past 10 pending)
> ```
>
> A real mismatch prints `READCHUNK ... got0x.. exp0x..` and exits 1, so `out` would be
> non-empty. **Empty output with non-zero rc is a command that never ran.**
>
> **Discriminating experiment** — same bus traffic, differing only in connection churn:
> fresh-ssh-per-call **3 PASS / 3 FAIL**; one reused connection **6 PASS / 0 FAIL**,
> 128 words byte-exact. Plus 108 chunked readbacks across 9 bring-ups with **zero** read
> failures, and a chunk sweep **24/24 at CHUNK ∈ {30, 50, 100, 128}**.
>
> **§3 and H3 are dead twice over** — once on the arithmetic, once because CHUNK=128 has
> zero mid-read seams and passed 24/24. **H1 and H2 lose their motivating observations**
> entirely; nothing in §1 requires a link or CDC explanation any more.
>
> **WHAT SURVIVES, and it is worth more than the rest of this plan:**
> - **The single capture in which the obs word CHANGED** — `0xB5000001 → 0xB5000600`,
>   bit[9] 0→1, bit[0] 1→0. **An ssh reset cannot fabricate a changed register value.**
>   That read succeeded and returned different bits, so one genuine park may have
>   occurred. **Re-take it with a fixed harness; do not discard it.**
> - **The TL-027 `w_inc` CDC defect**, proven in simulation independent of any hardware
>   run. Mechanism real; **causation to these field failures withdrawn.**
> - **Everything in §2 (CRC), §7 (write-only workaround) and §8 (instrumentation).**
>
> **THE ONLY EXPERIMENT WORTH RUNNING FIRST IS E0.** Everything below it is suspended
> until the instrument is sound.

**Original evidence base (now suspect):** six system-validation runs on the frozen
pin, 2026-08-21/22, archived at `~/SoCLabs/RESCUE_2026-08-22/evidence/`.

---

## 1. What is actually observed

| run | cross-die WRITE | cross-die READ |
|---|---|---|
| frozen | PASS | **PASS — 128/128 byte-exact** |
| d1 | PASS | **PASS — 128/128 byte-exact** |
| a4 | PASS | FAIL — `mismatch @100` |
| a5 | PASS | FAIL — `mismatch @100` |
| a6 | PASS | FAIL — `mismatch @100` |
| d2 | PASS | FAIL — Region-F fault *after* all 128 reads |

**⚠ Every FAIL row above has an empty detail string — see the box at the top. The three
`mismatch @100` rows are ssh resets, not data mismatches, and the two `beat 1024` rows are
a fixed connection ordinal with the same signature. The table is retained as a record of
what was believed, not as evidence.**

**Writes 6/6. Reads 2/6 fully clean.** When reads work they are byte-perfect, so
this is not a systematic data-path defect. `d2` returned all 128 words correctly
and *then* faulted, which is a third behaviour distinct from both PASS and
mismatch.

**Scope:** cross-die reads over the D2D link only. Local memory, the ethernet
datapath, the CPUs and PTP do not traverse it. `NANOSOC_D2D_PEER_BASE` has zero
consumers in shipping firmware — the only exercisers are rig scripts.

---

## 2. ⚠ Every measurement above was taken in the WRONG CRC configuration

This is the first thing to fix and it invalidates nothing, but it reframes
everything.

```
rig  (tidelink_fpga_v2.flist -> local_overrides/WlinkGenericFCSM_4.v)   disable_crc <= 1'h1   CRC OFF
ASIC (tidelink_top_full_asic_v2.flist -> deps/WlinkGenericFCSM_4.v)     disable_crc <= 1'h0   CRC ON
```

With `disable_crc=1` a corrupted read packet is **committed silently** — there is
no NACK, no counter, no flag. So the `mismatch @100` observations are consistent
with wire corruption that the rig is structurally unable to report, and the
silicon will behave *differently* because it will detect and NACK the same event.

**No experiment below should be trusted until the rig is put into the shipping CRC
configuration.** Run attended, with a POR staged: the RTL warns this can NACK-wedge
on a marginal eye, which is itself informative.

---

## 3. The clue nobody has chased

`CHUNK=30` passed 128/128 clean. `CHUNK=50` gave 1 PASS / 3 FAIL. **Same
addresses, same data, same total count — only the grouping differs.**

Neither leading hypothesis explains that. A stuck ACK pointer has no reason to
care about host chunk geometry; nor does a marginal eye. What *does* change per
chunk is the seam: each `read_chunk` is a separate board invocation that
**reprograms the CAM** (`CTRL=0 -> RULE0 -> CTRL=1`) and re-crosses a Region-F
gate.

**~~Start here.~~ REFUTED 2026-08-24, by its own arithmetic.** The hypothesis
predicts a per-seam failure rate, so failures must rise with the number of seams.
The data runs the other way: `CHUNK=30` has **~4 seams and PASSED**; `CHUNK=50`
has **~2 seams and FAILED**. Fewer seams, more failure. Rescuing it needs a
second fitted parameter on two data points, which is a curve, not a hypothesis.

**What is still worth doing is E3, but as a positive control rather than a test**
— see below. The seam remains the only variable that demonstrably correlates with
outcome, and that correlation is still unexplained; it is the *mechanism* that is
dead, not the observation.

---

## 4. Ordered experiments, by discriminating power per hour

### E0 — FIX THE HARNESS *(blocking; everything else is suspended behind it)*
Three changes to `tidelink/pynq_host/scripts/kr260_sysval.py`, none of them RTL:

1. **Keep stderr.** `board()` at `:60` returns `rc, out.strip()` and drops `err`; the
   remote `2>/dev/null` at `:58` drops the board's stderr as well. Both are where the
   diagnosis lives.
2. **Separate transport from data.** `:238` conflates `rc != 0` with
   `"READCHUNK" not in out`. `rc == 124` is already special-cased as a timeout —
   **`rc == 255` must be too**, and must never be recorded as a mismatch.
3. **Add `ControlMaster`/`ControlPersist`.** One connection per board per run instead of
   one per call. This alone converted 3 PASS / 3 FAIL into 6 PASS / 0 FAIL.

Then **re-run the 08-21 corpus**, and apply the same check to **T6 endurance** — 2 of 8
archived runs "failed at beat 1024", a fixed connection ordinal.

**Until E0 lands, a sysval red is not evidence.** A sysval *green* still is: this failure
mode destroys results, it does not fabricate byte-exact ones.

### E1 — Region-F witness during a live failure *(highest value, nobody has one)*
Read Region-F (`0x2E03_21E0`) at the moment of failure, not after recovery.
`wedge_tgt[14:10]` / `wedge_ini[19:15]` decode as `{r, ar, b, w, aw}` — they name
**which channel stalled**.

- AR or R lights up → the read FC node is implicated; the a2l hypothesis survives.
- Nothing lights up → a2l is refuted and the search moves to the PHY/eye.

**Verified against RTL 2026-08-24** — `tidelink_axinode_obs.sv:66-69` packs
`[14:10] tgt_wedge_sticky {r,ar,b,w,aw}` and `[19:15] ini_wedge_sticky`, exactly
as decoded above, plus `[23] data_healthy` and an `8'hAD` presence marker in
`[31:24]`. **Check the marker first**: absent marker means the read path itself
failed, and the zeros are not evidence of health.

**Companion word, and a trap in it.** `0x2E03_21F8` carries the XHB/read-path
stickies: `[0] xhb_sub_hreadyout_raw`, `[9] sub_err_sticky` (read backstop fired),
`[10] xhb_stall_stuck_sticky`. **Bit[10] sets DETERMINISTICALLY on the first
cross-die read** — a ~460 us round trip simply exceeds the sticky's 4096-hclk
threshold — while data returns correct and bit[9] stays 0. So `0xb5000401` is a
**HEALTHY** word, and at least one investigation has read bit[10] as a wedge and
called a working port parked. **Only bit[9] high, or bit[0] low-and-stuck,
discriminates.** (`rd21f8_eth.py:31` already labels it "PRESSURE, not deadlock".)

Every failure so far has been recorded `(no-obs)`, meaning the diagnostic plane
did not answer — note that Region-F shares a bus-matrix port with the peer
aperture, so a wedge takes the instrument with it. **Capture over SWD**, which
carries a bounded AHB timeout and returns an error rather than hanging.

### E2 — per-node CRC counters *(one APB read each)*
`0x2E03_1420` (R), `0x2E03_1320` (AR).

- Non-zero → corruption on the wire → eye/link.
- Zero → data left the far side intact and something downstream mangled it.

**This is the cleanest link-vs-logic separator available.** Only meaningful once
§2 is done — the counters only count when CRC is enabled on that node.

### E3 — CAM seam: run the POSITIVE CONTROL first
With §3's mechanism refuted, the ordering inverts. **Before testing whether the
seam causes failures, test whether it CAN**: deliberately reprogram the CAM
mid-chunk and try to corrupt a read on demand.

- Cannot corrupt on purpose → the seam cannot be the mechanism in the field
  either, and §3 closes for good.
- Can corrupt on purpose → *then* run the one-shot-CAM soak, which is now a
  meaningful test rather than a fishing trip.

**Verify the instrument before the DUT.** This is cheap and it is the only step
here that can close a hypothesis rather than merely fail to confirm it.

### E4 — deliberate eye variation
Sweep the link margin and measure read and write pass rates separately. If reads
degrade while writes hold, the asymmetry is eye-related. If reads fail at the same
rate on a good eye, it is logic.

This attacks the confound that makes all current evidence ambiguous: the
hardened/raw FC-node split is **perfectly confounded** with the write/read split,
so today's data cannot distinguish "reads use unhardened nodes" from "reads are
more eye-sensitive".

### E5 — the tearing test in simulation *(hours, no board)*
The a2l self-heal (`w_inc = 1'b1`) fixes a torn CDC delivery: `WavMultibitSync.v:31`
`we = w_inc & w_ready`, so an update arriving while `!w_ready` is dropped and never
retried. The existing bench **already has independent `app_clk` and `link_clk`**
(`cocotb/tidelink_a2l_replay_cdc/tb_top.sv:4-5`) and already exposes
`tb_synced_ack`.

Drive `link_ack_addr` to change while `w_ready` is low; check whether it ever
reaches `a2l_link_addr_app_clk`.

**This settles whether the a2l mechanism can produce this signature at all** — and
it settles it for `_1`/`_3`/`_5`, which ship today with that half of the fix
unproven. Worth doing regardless of the read question.

---

## 5. Hypotheses, and what kills each

| # | Hypothesis | Killed by |
|---|---|---|
| H1 | a2l CDC self-latch on the unhardened AR/R nodes | E1 showing no AR/R wedge; E5 showing the mechanism cannot produce a *mismatch* |
| H2 | Link/eye marginality, reads more sensitive than writes | E2 zero CRC counts; E4 showing no eye correlation |
| H3 | CAM reprogram at the chunk seam | **DEAD** — seam count and failure run in opposite directions (§3) |
| H4 | Harness artefact (invocation boundary, not silicon) | E3, plus running the soak as one invocation |

**H1 and H2 have both lost their motivating observations (see the box at the top); the signatures they were invoked to explain were transport.** H1 was already the least supported and the most cited. It predicts a *wedge*;
the dominant observed signature is a *mismatch*, three times. Of the three
signatures only "link down" fits it.

---

## 6. What would make this urgent

**⚠ CORRECTED 2026-08-24. The original line here — "nothing on a shipping path
reads cross-die" — was FALSE, and it was load-bearing in a tapeout
recommendation.** The evidence behind it established that no shipping firmware
*currently issues* a cross-die read. The claim it was used to support was that no
shipping-path master *can*. Those are different claims:

```
multicore_ahb_interconnect.v      _DMAC_0_M -> ..., _D2D, ...
multicore_matrix_decode_DMAC_0_M  0x2e000000-0x2fffffff -> MI12
chiplet_d2d_decode.sv:200         hsel_peer = xfer & a_peer     <- NO hwrite term
chiplet_d2d_decode.sv:228         hsel_peer ? DPH_PEER          <- read data returned
```

**The matrix decodes by address bits and never by symbol.** A programmable master
(DMA-250) reaches the peer aperture, and reads select it exactly as writes do.
So the correct statement is: **a live programmable path exists that no
configuration prevents; no caller happens to use it today.** `NANOSOC_D2D_PEER_BASE`
having zero firmware consumers is a fact about today's callers, not about
reachability. A doc bug probably seeded the error —
`nanosoc_multicore_addrmap.h:482` claims "Only CPU0 can reach it" and the
generated RTL contradicts its own header.

**Reachability is a property of the address decode, not of the symbol table.**

It is still not urgent *today* — no diagnosis can change the taped-out RTL, and
the intermittency has never been observed via a firmware-initiated read. It
becomes blocking if any of these change:

- The het eth↔compute pair becomes a v1 deliverable (it has never run anywhere,
  and the dies do not share an address map).
- Cross-die DAP debug lands — every DHCSR check is a peer read.
- Firmware acquires a cross-die reader. Note
  `firmware/apps/default_slave_error_walk/main.c:241` already probes `0x2F000000`
  believing it a reserved hole that should DECERR; on this chiplet that is a live
  cross-die read. **Fix or mark chiplet-unsafe regardless of this plan.**

---

## 7. The supported workaround, which costs nothing

`docs/design/SYSTEM_APP_TRANSPARENT_BRIDGE.md:127-136` already specifies the
boundary as **write-only**: push body, push descriptor, push doorbell, push the
consumer index back. The receiver reads its **own local SRAM**. Nobody pulls.

Cross-die writes are 6/6 reliable. Any protocol built on far-side push avoids this
defect entirely, and that is the documented architecture rather than a workaround
invented after the fact.

---

## 8. Instrumentation gaps to close first

- **Set `SYSVAL_JSON_OUT` on every run.** The 08-21 corpus existed only in session
  scratch and was one `rm -rf` from gone; it is now archived at
  `~/SoCLabs/RESCUE_2026-08-22/evidence/`. Do not repeat that.
- **Split the harness's failure classes.** `kr260_sysval.py:238` collapses a SIGBUS
  kill (`rc != 0`) and a data mismatch (`rc == 1`) into one message, and reports the
  *chunk start* rather than the failing index. Two lines of change turn the next
  four failures into a diagnosis instead of another ambiguous log.
- **Print `regf_raw`, not `witness_raw`, on a Region-F fault** (`:243-244`) — the
  current code discards the one field that names the wedged channel.
- **⚠ BUILD PROVENANCE IS FAIL-OPEN — do not trust a "built from the freeze"
  stamp without checking the manifest.** `tidelink/fpga/scripts/build_provenance.tcl:76`
  reads:

  ```tcl
  if { ![catch { exec git -C $root status --porcelain } st] && [string trim $st] ne "" } {
      set dirty "-dirty"
  }
  ```

  In a worktree whose `deps/*` are symlinks, `git status` exits **128**
  (`error: expected submodule path 'deps/axi-chiplet-controller' not to be a
  symbolic link`). The `catch` swallows it, the `&&` short-circuits, and
  **failure-to-evaluate is written out as CLEAN, silently, with no warning.**

  Measured 2026-08-24 — same commit, opposite verdicts:

  | tree | `git status` | stamped |
  |---|---|---|
  | `hostio-wt/tidelink` | rc=128 | `git_dirty: false` ❌ |
  | `nanosoc-ethernet-chiplet/tidelink` | rc=0, 2 untracked | `git_dirty: true` ✅ |

  The worst instance found: `imp/fpga/output/kr260-pair-onchip` (2026-07-24)
  stamps `source_commit: "unknown"` **and** `git_dirty: false` — a build whose
  commit git could not determine, recorded clean. `tl_git_sha:72` returns
  `"unknown"` on rev-parse failure and then runs the dirty check anyway.

  **There is no genuinely-clean `5e8bdb5a` eth-chiplet FPGA build on this host;
  the honest ones are dirty at the same commit.** Fix is two lines — score the
  `catch` as dirty, and force dirty when the SHA is indeterminate. Owned by
  tidelink (`rev2/hygiene`).
