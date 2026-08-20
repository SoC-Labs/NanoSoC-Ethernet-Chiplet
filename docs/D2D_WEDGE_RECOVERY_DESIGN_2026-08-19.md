# D2D wedge — prevention and recovery design

**Status:** design, not landed. Post-tapeout except where noted.
**Date:** 2026-08-19. **Author:** rig/diagnosis session, consolidating a 16-agent diagnosis,
four research passes over primary specs, a cocotb reproduction, and two silicon experiments.

> **Rule of this document:** every claim is labelled MEASURED (observed in sim, on silicon, or read
> directly from RTL/spec text), or INFERRED. Anything not so labelled is a design proposal.

---

## 1. What is actually established

### MEASURED on silicon (kr260_01, instrumented bitstream, 2026-08-19)
- A **posted-write burst from a DMA into the `ahb_sub` peer path wedges the AHB port permanently.**
  Induced deliberately; recovered only by JTAG-POR.
- **`s_axi_awready` was HIGH in all 4096 captured samples**, the AW-node replay window was NOT full
  (`a2l_full=0`) and its ACK pointer kept advancing. **H1 is refuted ON THE AW NODE.**
- **H2 refuted** (`swi_enable=1`, `enable_app_clk_demet_io_out=1`). **State-7/watchdog path refuted**
  (`state`∈{4,5}, `socl_l7_wdog_cnt=0`). Sideband path not involved (`dbg_tx_hreadyout=1`).
- **die_b was idle and healthy throughout** — the peer does not cause this.
- **A serialised PS store stream CANNOT induce it** (65536 stores completed in 16.9 s, `a2l` flat).
  Only a master with multiple writes outstanding can.
- **The traffic class is the whole story:** the identical DMA induce **completes cleanly with
  `AWCACHE=0x0`** (→ `HPROT[2]=0`) and **wedges with `AWCACHE=0x3`** (→ `HPROT[2]=1`).

### MEASURED in simulation
- The **H1 mechanism reproduces dynamically**: freezing an FC node's ACK pointer walks the replay
  FIFO to full → `app_ready` drops → the write wedges, held for 26,001 observed cycles.
- The **wedge reproduces at the wrapper level** with the pre-TL-043 semantics, and — decisively —
  **compiling `wr_hold_r` out entirely does NOT fix it** (16387-cycle zero-run remains; ~6.8x slower
  wedge, not a fix). *A wrapper-only fix is therefore insufficient.*
- **A partial fix is actively dangerous:** with nothing holding the write data, anything that later
  restores `wready` delivers `0xBAD0BAD0` **at the correct address, with full byte strobes, answered
  OKAY**. Silent corruption is strictly worse than the hang it replaces.

### MEASURED in RTL
- **Both `ahb_sub` backstops are aggregate-progress timers.** `sub_stall_ctr_r` re-zeroes on any
  completed beat; `sub_osr_ctr_r` re-zeroes on `sub_axi_progress = sub_r_done | sub_b_done` — a bare
  OR with **no transaction identity**. A partially-draining stream starves both indefinitely, which
  **also disables the synth-B drain** (`sub_wr_stuck_fire` ANDs those expiries). One starvation mode,
  whole family. **Raising the thresholds cannot fix this — the counters never reach ANY threshold.**
- **The W channel is a SEPARATE FC node** (`wlink_axiwFC`, depth 32) from the AW node (depth 8).
  `grep -c` for timeout/timer/watchdog in its replay module returns **0**. Its own comment documents
  the failure chain by name: *"a2l_link_addr frozen -> a2l_full sticks -> app_ready=0 -> TX stall ->
  PS-bus wedge"*.
- **`HPROT[2]` is exactly the arming term.** `hprot[6]` is hardwired 0, so XHB500's
  `ewr <= hprot[2] & ~hprot[6]` reduces to `HPROT[2]`, and the same term gates `hazard_add`.

### ⚠ SUPERSEDED — the W-node capture RAN, and it REFUTES W-node starvation
**PROVENANCE OF THIS CAPTURE — deliberately left partly open, see below.** The second bitstream
**was** deployed (2026-08-19; raw at
`tidelink/imp/hw_gate/awready_ila_capture/results_wnode_2026_08_19/`, `TRIGGERED=1`, 50% trigger so it
brackets the onset, validity proven by `dbg_freerun_ctr` monotonic 4095/4096). **Independently
re-parsed from the raw CSV here.** Across 4096 samples:

| Signal | Measured | Consequence |
|---|---|---|
| **W-node `a2l_full`** | **0 / 4096** | **W-node starvation REFUTED** |
| **`s_axi_wready`** | **1 / 4096** | the W channel never stalls |
| `s_axi_awready` | 1 / 4096 | AW never stalls (re-confirms the first capture) |
| **`wr_hold_r`** | **0 in 4092 / 4096** | **the rank-5 holder deduced by the diagnosis was NOT holding** |
| `sub_wr_os_ctr` | **0 pre-onset → 4 post-onset** | hazard list **SATURATES** (`HAZARD_LIST_SIZE=4`) |
| `xhb_sub_hreadyout_raw` | 1×2061 → **0×2035** | goes low at onset |
| `ahb_sub_hreadyout` | 1×2055 → **0×2041** | follows, held |

**MEASURED causal order:** `sub_wr_os_ctr` reaches 4 (XHB500's hazard list saturates awaiting B
responses) → `xhb_sub_hreadyout_raw` → 0 → `ahb_sub_hreadyout` → 0, held.

**THE REAL MECHANISM IS XHB500 HAZARD-LIST SATURATION — a bridge RESPONSE-PATH problem, not a Wlink
credit problem.** The FC nodes are healthy throughout and the data crossed. This refutes both H1
(on either node) and the rank-5 `wr_hold_r` deduction. Caveat: refuted **for this induction path**
(DMA posted-burst overrun), not universally.

**The existing recovery is MEASURED-INERT — stated without any timing assumption.**
Leak witness at `0x8403_21F8`, **with its negative control**:

    BASELINE (healthy) : 0xB5000001   all stickies clear, raw = 1
    DURING WEDGE       : 0xB5000498   [10] stall-stuck fired, [8] write-backstop = 0, [4] hprot[2] = 1

The baseline is what makes the wedge word discriminating — without it, the wedge value proves nothing
about the instrument. Decode verified field-by-field against `tidelink_top.sv:1852-1882`; `[3:1]` = 4
matches the ILA's post-onset `sub_wr_os_ctr` exactly, so the two instruments corroborate.

**`[8] sub_wr_stuck_sticky` is SET-ONLY and clears solely on `!hresetn` (`:1856-1870`). `[8] = 0`
therefore means the write backstop has NEVER fired ONCE SINCE RESET** — no period count, no clock
assumption, no wedge-duration estimate required. And it is set by
`(sub_osr_expired | sub_stall_expired) & (sub_wr_os_ctr != 3'd0)`, with `os_ctr` pinned at 4
throughout, so the AND's second term held the whole time ⇒ **the EXPIRY ITSELF never happened.**
*(An earlier "~5,700 timeout periods" figure is WITHDRAWN — it required an assumed hclk and an
eyeballed wedge duration. The sticky argument above is strictly stronger and assumption-free.)*

⚠ **EVIDENCE GAP — narrowed, not closed.** The READER is now preserved two ways: the original
(`tidelink/pynq_host/scripts/rd21f8_ORIGINAL_2026-08-19.py`, recovered from volatile `/tmp` — it had
ALREADY been wiped from the board) and a maintained reconstruction (`rd21f8.py`) whose decode was
independently verified bit-identical to the original across both recorded values and 200k random
words. **But `0xB5000498` itself still has NO captured output on disk** — the reading survives only in
a session transcript. Re-running against a live wedge is the only way to close that, and capturing
the BASELINE alongside it is mandatory (the wedged word proves nothing about the instrument alone).

**⚠ THE ILA CAPTURE CANNOT REFUTE BACKSTOP STARVATION — DO NOT RE-DERIVE THAT REFUTATION.**
MEASURED from the capture's own free-run counter: 4095 increments across 4096 samples = exactly
1 tick/sample, so the window is **4096 hclk**. Both timeouts are 2^16 = 65536 hclk
(`SUB_STALL_TIMEOUT_LOG2` = `SUB_OUTSTANDING_TIMEOUT_LOG2` = 16). **Window / period = 4096 / 65536 =
1/16 EXACTLY, and that ratio is independent of hclk** — it holds without knowing the clock rate. The
window is therefore structurally too short to contain either a fire or a re-zero.

**Reconciliation, and it makes starvation OPERATIVE rather than refuted:** inside the window the
counters climb cleanly, which extrapolates to a fire at one period — yet the sticky says no fire has
ever occurred across a multi-second wedge. Those two facts reconcile **only** if the counters are
being re-zeroed OUTSIDE the observed window. So both defects are live simultaneously, which is
exactly the "two independent reasons" structure below. A refutation built on this same window has
already been retracted once; it must not be re-derived a third time.

Two independent reasons it cannot fire, so "fix the starvation" alone is insufficient:
1. Both timers re-zero on **unrelated** progress (§1, RTL).
2. **Even on expiry nothing fires for a write:** the direct ERROR path is deliberately read-only
   (F-1), and TL-037's branch requires `sub_wr_os_ctr == 0` while this wedge **pins it at 4**. The
   write path's only escape is synth-B — gated on the very expiry that starves.

### ⭐ THE REMAINING QUESTION DOES NOT GATE THE FIX — decouple these two decisions

**Fix K is RETIRED as this wedge's explanation** (it remains a real mechanism). MEASURED from the
same capture: `sub_wr_os_ctr` ramps 0→4 at onset (samples 2049..2060) then **never decrements across
all 2036 remaining samples**. It decrements on `sub_b_done = s_axi_bvalid & s_axi_bready`
(`tidelink_top.sv:1593`), which is **upstream of XHB500's internal bid matching**. Fix K's shape
requires that handshake to COMPLETE and the entry to then fail to free — zero decrements rules it out.

That leaves a clean binary, and **`s_axi_bvalid` has exactly two contributors**
(`:2003  s_axi_bvalid = s_axi_bvalid_ctrl | synth_b_pending`) with `synth_b_pending` measured 0
throughout, so there is no third case:
- **(i) `bvalid` never asserted** → trail leads into the Wlink B node (`WlinkGenericFCSM_2` /
  `WlinkGenericFCReplayV2_5`), which lives in **`local_overrides/` — NOT sourced by the ASIC flist.**
- **(ii) `bvalid` asserted, `bready` held low** → inside **vendor XHB500 RTL, which we do not modify.**

**⇒ WHICHEVER WAY THE BINARY FALLS, THE ROOT-CAUSE FIX CANNOT REACH THE ASIC, AND THE TIE-DOWN (§3)
REMAINS THE ONLY FIX THAT CAN.** Capture #3 is therefore valuable for *understanding* and for the
sim/FPGA line — **it must NOT be treated as a prerequisite for the tie-down decision.** Do not wait
on it.

#### Attribution of the board measurements — RESOLVED by execution record
**Both captures and the `0x21F8` reads were run by session `e31cf0db-becf-4762-a881-c1c17e74fb93`.**
Settled not by anyone's recollection but by the execution record plus an instrument clock:
`ila_capture_wnode.tcl` written 14:30:54Z; Vivado ssh'd to the board host 14:31:36Z / 14:31:57Z; the
arm log's own **Vivado-generated** stamp `Start of session at: Wed Aug 19 15:32:01 2026` (local =
14:32:01Z) falls exactly between them; board POR at 14:33:19Z; results read at 14:34:50Z. The tcl
carries that session's own idioms (`hands off until /tmp/do_capture`, "decide from CONTENT, not
status") and sets `TRIGGER_POSITION 2048` = the 50% position. `0x21F8` read over ssh at 15:02:59Z /
15:03:26Z. A third session (`f71950cb`) independently verified the decode.

> **⚠ LESSON — the reason this took four rounds to settle, and it will recur.**
> That session **sincerely denied running the W-node capture, to four separate parties**, because its
> context had been compacted past those actions. **Absence from context was reported as absence in
> fact.** A long-running session is not a reliable witness to its own history: memory of an action and
> the action are different things, and so are the absence of a memory and the absence of an action.
> A second session made the mirror error, reading another session's log entry as its own history.
> **Neither recollection nor its absence is evidence — check the execution record.** Cite session
> UUIDs, never short-names: `-32` demonstrably meant two different sessions six hours apart in one day.
> None of the technical conclusions were touched by any of this, for one reason only: each was
> re-derived from the raw CSV and the RTL rather than from testimony.

#### ⚠ BOTH "cheap discriminators" I proposed are DEAD ENDS — struck, with replacements
- **`0x2158` — STRUCK. Wrong node.** It observes the **TideLink sideband** FC node only
  (`axi_chiplet_controller.sv:2658-2666` → `u_wlink` → `Wlink.v:1910 TideLinkToWlink tl2wl` →
  `WlinkGenericFCSM_6` → `WlinkGenericFCReplayV2_13`). The AXI channels are a **different instance
  tree** (`axi2wl/wlink_axi{aw,w,b}FC`). It cannot discriminate anything about B at any price.
  (`REGISTER_MAP.md:352` also disagrees with the RTL on this offset — the RTL wins.)
- **`xhb_stall_ctr_w` sampling — STRUCK. Not readable.** Bits `[23:12]` of the obs word are a literal
  `12'h0`; only the saturation sticky `[10]` escapes the die. The counter never leaves.
- **REPLACEMENT for the B binary — `0x21E0` (Region F, marker `0xAD`), and it IS free.**
  `tidelink_axinode_obs` taps `.tgt_b_valid(axi_tgt_0_b_valid)` / `.tgt_b_ready(axi_tgt_0_b_ready)`
  (`axi_chiplet_controller.sv:3065-3066`), and those are exactly `s_axi_bvalid_ctrl` / `s_axi_bready`.
  **bit [2] = tgt_b live-stall, bit [12] = tgt_b wedge-sticky.**
  ⚠ **ONE-WAY TEST:** `[2]=1` or `[12]=1` **PROVES case (ii)** (bvalid asserted, bready held low →
  inside vendor XHB500). But `[2]=0 ∧ [12]=0` is **NO INFORMATION** — a never-driven B produces no
  stall and the word still reads "healthy". Only claim case (i) if a liveness check on the sampler
  succeeded first.
- **REPLACEMENT for the cadence — a free BRACKET, no ILA.** If `[10]=1 ∧ [8]=0 ∧ [9]=0` then
  `xhb_stall_ctr_w` hit `12'hFFF` at least once (≥4096 hclk with no re-zero) while `sub_stall_ctr_r`
  never reached 2^16 ⇒ **the re-zero interval is bracketed to [4096, 65536) hclk.** No clock rate
  assumed, no duration estimated. Report it as a bracket, never a point estimate.
- **⛔ `bnode_reg.py` — DO NOT RUN on the pair-onchip target.** It uses the **eth-chiplet** address map
  (`WINDOW=0x400000000`, `TLAPB=0x2E030000`) and would read an unmapped address here; and its `arm`
  path is a **WRITE** to the Wlink error injector that is MEASURED to cause a **HARD PS WEDGE**
  (`AXI_DATANODE_RECOVERY_GAP_2026_07_31.md:24`), ending the session. Reuse its offsets at
  `0x8403_xxxx`; never its script.

### Still NOT PROVEN
- **Branch C — XHB500 producing no write data — is now the LEADING open branch**, since the stall is
  demonstrably downstream of a healthy W channel.
### ✅ THROUGHPUT MEASURED 2026-08-20 — and it settles the full-vs-narrow question

**First, the magnitude's cause: `s_axi_bvalid` RETURNS ACROSS THE LINK — there is no local early-B.**
`AXI4ToWlink.v:435` `axi_tgt_b_valid = wlink_axibFC_io_app_l2a_valid` (the link-to-app face); B is its
own link channel (`data_id 0x82`) with separate TX/RX router ports. `synth_b_pending` is timeout-only
(2^16 hclk) so it is 0 on a healthy link. Measured B latency **220–234 hclk**, and the fix's cost is
**224.3 cycles/word** — i.e. **the per-word cost IS one link round trip.**

| arm | cyc/word INCR4 | cyc/word INCR16 | AWLEN | ewr | data |
|---|---|---|---|---|---|
| 1 — reverted (posted) | **3.00** | **2.25** | 3 / 15 | True | **CORRUPT** |
| 2 — **as landed** `[3:2]`→00 | **225.25** | **224.31** | 0 | False | **correct** |
| 3 — narrow `[2]`-only | 61.25 | 20.88 | 3 / 15 | False | **CORRUPT** |
| 4 — control `hprot=0` | 225.25 | 224.31 | 0 | False | correct |

**Cost of the fix: 75x (INCR4) / 100x (INCR16)** vs a posted burst ≈ **0.89 MB/s** at this bench's
50 MHz link config. **Control validated:** arm 4 was bit-identical across all three tie-down states
(`[901,898,898]` / `[3589,3588,3587]`), so the numbers are not void. Note arm 2 equals the control in
every cell — the fix behaving exactly as designed.

### 🔴 NEW DEFECT — THE MULTI-BEAT AXI BURST PATH IS BROKEN (corrupts, then wedges)
The narrow variant amortises as predicted (3.7x / 10.7x) **but is not a usable option**:
- **The first burst CORRUPTS** — beats 1..N-1 all deliver beat 0's payload (`0x5a000001` repeated):
  the `cap_done_r` / `d2d_ahb_m_hwdata_q` signature. That fix was validated **for the singles path
  only**; on the multi-beat path the defect is ALIVE.
- **The second burst WEDGES permanently** — HREADY never returns.
- **Arm 1 (fully reverted, posted) shows the SAME corruption and also wedges**, so this is a property
  of `AWLEN>0`, not of `ewr`.

⇒ The narrow variant does not merely enter untested territory, it enters **measurably broken**
territory: its 10.7x came from a burst that delivered wrong data and then hung the bus.
⇒ **This reframes the full tie-down: it is not just the safe choice, it actively forecloses a live
corruption-then-wedge on the burst path.**
#### This is a DISCLOSED RESIDUAL, now measured — not a surprise defect
The burst fix's own hardening note bounded itself in writing, and the bound held exactly where it said
(`imp/hw_gate/burst_fix_proto/BURST_FIX_HARDENING.md`, verified):
> *"DEPTH-1 SUFFICIENT for the validated (non-bufferable, `hprot=0`) peer-write path … **NOT covered
> (honest bound)**: the BUFFERABLE / EWR path (`hprot[2]=1`) … If a bufferable burst is ever a real
> traffic class, **that path must be re-measured before depth-1 is assumed there.**"*

**This measurement IS that "re-measured", and the answer is: broken.** `AWLEN>0` only arises on the
bufferable path the bound excluded. ⇒ **The burst fix is not wrong — its PRECONDITION is.** Extending
the hold past depth-1 is a design change carrying its own risk; enforcing `hprot[2]=0` (what the full
tie-down does) keeps the fix inside its validated envelope. Stated at full strength: **the full
tie-down is not the conservative option, it is the only option currently inside anyone's validated
envelope.**

⚠ **DO NOT MISREAD THE SIGNATURE.** The burst fix IS live in the measured arms (`hwdata_hold_r` 4,
`peer_wcon_r` 7, `w_beat_consumed` 8 at HEAD). `d2d_ahb_m_hwdata_q` still appears because post-fix it
survives as the **muxed output** — `:346  wire [31:0] d2d_ahb_m_hwdata_q = cap_done_r ? hwdata_hold_r
: d2d_ahb_m_hwdata;`. Seeing that name in the corruption signature does **NOT** mean the arm was on
pre-fix RTL. The obvious reading is the wrong one.

#### The throughput lever is LINK LATENCY — not the tie-down, not the outstanding count
Since the per-word cost **is** the B round trip, the cost is the semantics of **non-posted writes over
a link with that latency**, not an implementation inefficiency. Nobody can optimise it away in the
wrapper. And the tempting alternative — **pipeline several outstanding singles to amortise the round
trip while keeping `AWLEN=0` — CANNOT WORK**: non-bufferable writes are non-posted *by definition*,
so each must complete before the next issues. Allowing several in flight means making them bufferable,
which is exactly the `hprot[2]=1` path that saturates the hazard list, wedges, and now also corrupts
on `AWLEN>0`. **Do not spend a week on wrapper pipelining.**

⇒ A **THIRD precondition**, beyond the two named at the forcing site (revive the EWR guard and Fix-K):
**the wrapper's write-data hold must be fixed for `AWLEN>0`** before any HPROT relaxation is worth
pursuing.

**Caveats:** absolute numbers are this bench's link config only (50 MHz hclk); since the cost IS the B
round trip it tracks real link latency, and the D2D rate is stated three ways across the tree — the
RATIO is more robust than the absolute. Writes only; no read path. The corruption and wedge were
characterised, not root-caused.

- **Throughput cost** of the prevention layer (§3) — MEASURED, see above. Previously in progress
  (four arms: posted baseline / landed `[3:2]` / narrow `[2]`-only / an `hprot=0` control that must
  be identical across tie-down states or the run is void).
- **FPGA != ASIC configuration.** The A/B validates the EDIT on the FPGA vehicle; the tapeout ships
  ECC/CRC/FCSM settings the FPGA does not. It does not validate the tapeout configuration.
- **ARM B faulting (bounded AXI error) rather than hanging is NOT evidence that TL-037/N3/TL-043
  work.** The sticky that fired belongs to the synth-B drain, which PREDATES all three and is on the
  tapeout pin too; and TL-037's branch requires `sub_wr_os_ctr == 0` while this wedge pins it at 4,
  so it structurally cannot have fired. Test it as a null-result-expected control only.

---

## 2. Why this class of bug exists at all

The canonical NoC text (Dally & Towles) defines credit-based flow control and a full-text search for
credit **loss / corruption / errors returns ZERO hits**. On-chip, the credit channel is genuinely
reliable — shared reset domain, error-free wires. **Cross a die boundary — CDC, serialiser, framing,
independent resets — and that assumption dies silently while the protocol stays the same.**

The dividing line, from primary spec text:

| | Encoding | Lost update |
|---|---|---|
| **InfiniBand, PCIe** | **absolute cumulative** — receiving an update *assigns*, not accumulates | **self-heals** on the next update (IB re-advertises every 65,536 symbol times, ~0.009% of link bandwidth) |
| **Fibre Channel BB_Credit, Dally's NoC credits, TideLink** | **incremental** | **leaks permanently** |

Fibre Channel's own patent literature states our problem verbatim: *"lost credits are generally not
restored until a link reset or link offline event is triggered."* Their answer was **not** a protocol
redesign — it was a **periodic reconciliation checkpoint** (BB_SC): a marker every 2^N frames, count
arrivals between markers, reissue exactly the shortfall. **That is the cheapest retrofit shape for an
existing incremental protocol, and it is the model §4 follows.**

Two further results worth knowing before anyone proposes something more ambitious:
- **CHI has ZERO timeouts in 488 pages** and its only credit-resync path (`RUN→DEACT→STOP→ACT`) can
  itself hang waiting for credits the wedge destroyed. **AXI's only architected escape** is an
  implementation-defined **slave-side watchdog surfaced as SLVERR** (§A3.4.5). So a bridge-side
  timeout returning a legal error is not exotic — it is the only option the protocol contemplates.
- **A link retrain does not restore credits anyway** (PCIe: LinkUp stays asserted, FC init never
  re-runs). Reset-based thinking is the wrong axis entirely.

### The four rules this design obeys
1. **The relief/credit channel must be UNCREDITED and unconditionally accepted** — recovery traffic
   must never be gated by the congestion it exists to relieve.
2. **Put the timeout on the RECOVERY path, not just the data path.** CHI and CCIX both wait on
   credits the wedge already destroyed; CCIX bounds it and reports, CHI hangs.
3. **Arm watchdogs on PROGRESS OF THE OLDEST ITEM, never on message arrival or aggregate activity.**
   (US8151145B2 exists because the standard PCIe FC timeout *"cannot detect the case where UpdateFC
   packets are received, but the credit value returned never changes."* That is our exact defect.)
4. **Trigger on a CONJUNCTION** (backpressure AND no forward progress), require two consecutive
   observations, and recover in **TIERS** — silent correction → degrade with auto-restore → retrain →
   reset last.

---

## 3. Layer 1 — PREVENTION (validated, ready, next-run candidate)

Remove the traffic class that arms the mechanism, rather than recovering from it.

```verilog
// src/rtl/nanosoc_eth_chiplet.sv — the peer-path choke point
.ahb_sub_hprot ({2'b00, d2d_ahb_m_hprot[1:0]}),
```

- Sits **downstream of the bus matrix**, so it covers **all initiators** — both Cortex-M0+ cores, the
  DMA-250, the DAP, the debug bridge and the external backdoor. (An MPU would cover 2 of 5, is inert
  until firmware configures it, and costs a full SoC regeneration — assessed and rejected.)
- **MEASURED, sim:** 15/15 regression, directed proof (master requests `0x4/0x8/0xc`, TideLink
  receives `0x0`; `ewr` and `hazard_add` both go False; data still lands), and a **negative control
  that FAILS when reverted** — the test genuinely discriminates.
- **MEASURED, silicon:** the A/B in §1.
- **COUPLING — documented at the forcing site, must not rot:** this makes the bufferable/EWR guard
  and XHB500's Fix-K BID-correction **dead code**. That is a *stronger* property (the path cannot be
  constructed rather than being caught at runtime), but it makes this one line the sole protection.
  **If it is ever relaxed for throughput, those two must be revived first.**
- **✅ HARDWARE VALIDATED 2026-08-20 — the edit itself, not just its mechanism.** Matched-conditions
  A/B on `kr260-eth-chiplet` (the vehicle that instantiates this file), both dies `fcsm=4`, CAM
  programmed, arms differing by exactly the two fix hunks:
  **ARM B (pre-fix) 4 KB and 64 KB → AXI ERROR; ARM A (fix) 256 B..64 KB → ALL COMPLETED.**
  The obs plane confirms the MECHANISM, not just the outcome: `pipe_hprot_r[2]` B=1 / A=0 (the
  tie-down is in effect on silicon), `sub_wr_os_hwm` B=4 (saturated) / A=1 (cannot saturate),
  `sub_wr_stuck_sticky` B=1 / A=0, RegionF `data_healthy` B=0 / A=1.
  Evidence: `tidelink/imp/hw_gate/awready_ila_capture/results_ab_2026_08_20/AB_RESULT.md`
  (tidelink `fae6d250`). ⚠ An earlier ARM A run hung the board at a DIFFERENT link state
  (re-anchored) and is VOID, not a negative result — under matched conditions ARM A completes every
  size tested. Bring-up here is a marginal-eye lottery; only compare arms at `fcsm=4` on both dies.
- **⭐ THE CAPTURE MAKES THIS THE DIRECT FIX, not merely a prevention.** The measured mechanism is
  hazard-list saturation — and `hazard_add` is gated on `hprot[2]`. With `HPROT[2]` forced to 0 **no
  hazard entry is ever allocated**, so the list cannot saturate and the measured wedge becomes
  structurally impossible. This targets the mechanism that actually wedged silicon, not a hypothesis.
- **Open before landing:** throughput (peer bursts issue as AXI singles), and it changes the netlist
  so it needs a re-synth.

---

## 4. Layer 2 — RECOVERY (design; needs the W-node capture first)

### 4a. ⚠ RE-SCOPED BY THE CAPTURE — the root is the BRIDGE RESPONSE PATH, not W-node credit
The silicon capture (§1) refutes the W-node premise this subsection was written for. **Do not build a
W-node credit fix for this wedge** — `a2l_full=0` and `wready=1` throughout. The root is XHB500's
hazard list saturating at 4 while awaiting B responses. Layer 1 (§3) addresses this DIRECTLY and is
the recommended fix; the material below is retained only for the general credit-recovery case, which
remains a real latent hazard (the W node still has no timeout) but is **not** what wedged the silicon.

<details><summary>Retained: general credit-recovery design (not this wedge)</summary>

#### Making a credit window drain
Per §2, the cheapest correct retrofit is **periodic reconciliation**, not a protocol change:
a marker/re-ACK emitted on a **link-clock stall timeout**, so the peer responds either way — an ACK
advances the pointer, a NACK drives the revert path that already exists. Obeys rule 1 (the marker
must ride an uncredited path) and rule 2 (the marker's own timeout bounds the recovery).

**Known trap, MEASURED:** the existing re-ACK is a **one-shot that can never re-arm** — its clear
condition is dead in the wedged state. CHI's equivalent state machine is **re-armed on every retrain
by construction**, and its spec states the arming rule explicitly. Any re-ACK here must be periodic
by construction, not fired-once.

</details>

### 4b. Give `wr_hold_r` an escape that does not depend on the W handshake
*(Lower priority after the capture — `wr_hold_r` measured 0 in 4092/4096 samples, so it was not the
holder for this wedge. Retained because it remains a real hazard on other paths.)*
Its only exits today are the W handshake itself and `synth_b_pending` — and `synth_b_pending` is
starved (§1). Needs an **independent, progress-armed** timeout.

### 4c. Replace the starved timers (rule 3)
Age the **oldest outstanding transaction** — per-ID age, or a shared free-running counter plus a
per-entry deadline register and comparator. At depth ≤8 this is order 150–200 flops and
**structurally cannot be starved**. Published figures bound the ≤32 case at a few thousand µm².
**Do not "fix" this by raising `SUB_*_TIMEOUT_LOG2`.**

### 4d. The escalation ladder
| Rung | Owner | Action |
|---|---|---|
| 0 | RTL | independent forward progress per channel; credit updates outside the replay path |
| 1 | HW | per-channel stall timer + per-transaction response timer, **armed on progress** |
| 2 | HW | synthesise protocol-legal responses for every outstanding transaction, incl. partial bursts |
| 3 | HW | bounded AHB ERROR to the initiator |
| 4 | HW→SW | interrupt (not SError) so the system survives to run the handler |
| 5 | SW | stop issuing, drain, reset **only** the downstream endpoint, re-enable |
| 6 | SW | last resort: die POR |

**Rung 3 already works in our silicon (MEASURED, from the DMA-250 TRM):** on an AHB ERROR the DMA
cancels the remainder of the command, stops the channel, sets `STAT_STOPPED`/`STAT_ERR`, raises
`INT_ERR`, and is **restartable in software** — no reset required. Timeouts across rungs must be
co-tuned so each layer is strictly longer than the one beneath it.

---

## 5. What must be measured before any of §4 lands

1. **Run the W-node capture.** Bitstream is built and verified (both `a2l_full` nodes probed
   distinctly, `s_axi_wready/wvalid/wlast`, backstop counters, free-run clock control). Decide branch
   A (W window genuinely full) vs branch C (XHB500 produces no write data) — **they need different
   fixes.** Watch whether `sub_stall_ctr_r` **climbs** or **re-zeroes**: that single signal
   discriminates "a backstop fired and did not help" from "the backstop was starved".
2. **Measure the §3 throughput cost.**
3. **DO NOT raise `SUB_*_TIMEOUT_LOG2` — it is PROVABLY USELESS and will be the first thing tried.**
   MEASURED: the backstop never fired across ~5,700 timeout periods because the counters never reach
   ANY threshold. A larger threshold changes nothing.
4. **ASIC/FPGA split:** these `local_overrides` are NOT the ASIC sources, so Layer 2 as scoped does
   **not** reach the ASIC flow. Layer 1 (`nanosoc_eth_chiplet.sv`) DOES — it is in the shipping ASIC flist.
5. **Pin reconciliation cost — CORRECTED.** The lineages ARE divergent (13 main-only vs 14 ours-only
   commits) and the fate of the ours-only commits is a real decision. But the removed
   `link_clk_div_ratio_i` port is **NOT** a blocker: it is connected as a hardcoded `(3'd0)` at every
   vintage, so deleting the one instantiation line has **no functional loss** (the rate knob is inert
   on silicon regardless). Do not carry the port into a cost estimate as a merge blocker.
6. **Re-derive any timeout constant** before landing it; the existing "orders beyond a legitimate
   round trip" claim is a comment that was never measured, and the D2D link rate is stated three
   different ways in this tree.

---

## 6. Operational notes that cost real time today
- **An observability plane that shares fate with the wedged port is useless.** InfiniBand reserves an
  un-flow-controlled management channel (VL15) exactly so a wedged data channel never costs
  reachability. Whether ours survives a wedge **on the ASIC** is disputed between two analyses and is
  unresolved — resolve it before relying on any in-band diagnostic.
- **Always cite the BUILT commit.** Line anchors drift between the built and working trees; TL-043 is
  in the working tree and in no captured build.
- **NEVER read a value from a register without checking its marker first.** `0x2158` can be won by the
  V2 eye_shim path and return all-zeros with no marker (`tidelink_top.sv:1441`); `0x21F8` carries a
  `0xB5` marker for the same reason. **A missing marker means "instrument not answering", NEVER data.**
  Reading `0x2158`=0 as "B node empty" would be exactly the wrong conclusion. This project has burned
  itself twice on a convenient value from a register that was not actually decoding.
- **`grep -c` cannot see a forbidding comment.** A comment naming a port makes `grep -c` read it as
  connected. Anchor on `^\s*\.port`. This produced a wrong conclusion today until re-checked.
- **A 4096-sample ILA window is 1/16th of one backstop period.** Never conclude "the backstop did not
  fire" from a default-build capture.
- Multi-hour builds must be `setsid`-detached or a 1-hour cap truncates them mid-route; and this host
  runs concurrent Vivado jobs from other sessions — verify PIDs by working directory before killing.
