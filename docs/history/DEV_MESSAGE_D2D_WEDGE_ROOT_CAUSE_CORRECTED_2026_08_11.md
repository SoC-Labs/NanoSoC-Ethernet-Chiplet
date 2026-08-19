# To the TideLink dev — CORRECTED root cause of the D2D `rc=124` write-wedge: it's an RTL recovery/flow-control logic bug, NOT the RX-word clock/skew

**From:** nanoSoC eth-chiplet integration (two-board KR260 silicon).
**Date:** 2026-08-11.
**Supersedes** `../debug/ROOT_CAUSE_D2D_DELIVERY_WEDGE_2026_08_10.md` (which blamed the unconstrained
recovered RX word clock / a mailbox CDC pointer-tear). A second, 4-agent independent assessment —
after building and HW-testing the RX-word-clock fix — **refutes that for the wedge** and re-derives it.
**TL;DR:** The RX-word `create_generated_clock` fix was built (8 lanes, verified in-netlist) and it did
**not** close the `rc=124` write-wedge. Three independent angles then showed the wedge is **not skew,
not the clock, not the mailbox CDC** — it is an **RTL recovery/flow-control logic bug on the TX
(`io_tx_clk`) side**, POR-recoverable and clock-immune. Strongest single cause: the **FCSM state-7
NACK-watchdog self-defeat** (sticky `socl_l7_real_crc_seen`), which also **unifies R1 (errinject) and
R2 (soak) as one bug**. The fix is **RTL, not a constraint**. Keep the RX-word constraint on the **ASIC**
side (it's functional there) — on FPGA it is diagnostic-only.

Rig: die_a = kr260_01 = 10.22.24.159 (initiator), die_b = kr260_02 = 10.22.24.153 (target).

---

## 1. What I built, and the result that triggered the re-assessment

To test the 08-10 root-cause theory I added the RX-word `create_generated_clock` (`[4c]` block,
all 8 lanes `gpiorx0..7_word_clk`, mirroring your validated `kr260-pair-nptp` TL-028 block) to both
eth-chiplet FPGA timing XDCs, rebuilt the pair, and re-soaked. In-netlist it's real: 8/8 clocks,
**12,980 registers now timed, setup MET**. HW result over 6 bring-ups: the **`rc=124` 128-write
wedge PERSISTED** — 3 of 4 canary-good runs still wedged (~1/4 pass, unchanged). So the constraint is
**necessary-not-sufficient at best**, which is what set off the re-assessment.

## 2. Three independent angles agree: the wedge is NOT skew / NOT the RX-word clock / NOT the mailbox CDC

- **Single-bit pointers can't tear.** The `WavMultibitSync` crossing pointers are `wptr`/`rptr` —
  **1 bit each, 2-FF synced** (inherently gray, skew-immune). The only multi-bit thing crossing is the
  4–6-bit payload (`mem_0/mem_1`), read ≥2 clocks after the pointer toggles (~160 ns settle margin on a
  /16 clock). Your own silicon obs already recorded **"CDC faithful, IN=mem_0=mem_1=OUT=31"** — the
  mailbox transported faithfully; it did not tear. (Your RTL note: *"the fifth successive fix aimed at
  this module to fail the same way"* — the defect is **outside** the mailbox.)
- **Wrong clock domain — the airtight reason the constraint couldn't touch the wedge.** The wedging a2l
  ACK mailbox (`link_addr_to_app_clk` in `WlinkGenericFCReplayV2_1/_3/_5`) crosses **`io_tx_clk →
  io_app_clk`**. The recovered RX word clock (`io_rx_clk`) — the net I constrained — only clocks the
  **l2a RX receive FIFOs / ack_nack_fifo write**. It never clocks `app_ready`. So the RX-word constraint
  physically **cannot** move the wedge, exactly as observed.
- **The FPGA constraint is physically inert (DCP forensics).** In BOTH pre- and post-fix routed
  checkpoints the RX-word net is already driven by a **BUFGCE onto the GLOBAL_CLOCK spine**, skew
  **~0.07–0.16 ns** — identical. The BUFG is instantiated in RTL (`WavD2DGpioRx_v2.v:681`).
  "Unconstrained" meant **untimed** (no clock object → ~13k regs dropped from analysis), **not** routed
  on fabric. So on **FPGA** the `create_generated_clock` is a **timing-model** change only; it does not
  re-route or re-skew anything. (**On ASIC it IS functional** — CTS needs the SDC to build the tree.)
  Corollary: my "framing improved 4/6 vs 0/6" claim is **suspect** — with the physical net unchanged,
  that is most likely **eye variation** between the 20:47 and 23:14 sessions, not the fix.

**Net:** the RX-word constraint's real value was **diagnostic** — it proved the mailbox capture holds,
closing the skew theory. It is a genuine **ASIC** fix (keep it) and an **FPGA** no-op for the wedge.

## 3. The re-derived wedge cause (RTL logic, TX side) — ranked

**#1 (strongest, ~75–80%) — FCSM state-7 NACK-watchdog SELF-DEFEAT.** `WlinkGenericFCSM_4.v`:
`socl_l7_wdog_force_clear = (wdog_cnt==THRESHOLD) & ~socl_l7_real_crc_seen` (:303-305), and
`socl_l7_real_crc_seen` latches 1 on the **first** real CRC (sticky to POR, :1010-1017) **and pins
`wdog_cnt=0`** (:1024-1025). So after the first CRC the recovery watchdog is **double-killed**. Wedge
sequence: marginal eye (or an injected CRC) → `real_crc_seen=1` (watchdog dead) → occasionally the
recovery packet itself is lost → `send_nack_req` sticks → FCSM pinned in state 5/6/7 →
`auto_tx_out_advance` never fires → link stops draining the app FIFO → **`a2l_full=1` is CORRECT
backpressure** → `app_ready=0` → die_a's PS AXI store can't drain → no B/HREADY → mmap store blocks →
60 s ssh timeout → **`rc=124`**. Fits every fact (framing-helps/wedge-unchanged = clock lowers the CRC
*rate* but can't touch the *deadlock*; 8-vs-128-vs-256 monotonic; POR-only recovery; zero corruption;
sim can't reproduce because clean sim never loses the recovery packet).
**This UNIFIES R1 and R2:** `cov_errinject_sweep` wedges die_a on the **first AW inject on a good eye** —
one deliberate CRC, no skew, no bad eye. R1 (injected CRC) and R2 (natural CRC on a marginal eye) are
the **same** recovery-deadlock, differing only in how the CRC arrives.

**#2 (~15%) — credit-return / credit-underflow starvation.** `fe_tx_credit_max` is re-zeroed by the
post-CR enable-dip (`_fe_tx_credit_max_in_T = ~en_ff2_rx_demet`, `WlinkGenericFCSM.v:218,810-814`): the
peer jams at the first pktnum lap and stops ACKing → `a2l_full=1` legitimately. Same observable, also
clock-immune / POR-recoverable; likely a co-conspirator with #1. (Your registry's "TL-033 =
credit-underflow" is this family.)

**#3 (demoted) — mailbox reset-coherence deadlock.** The reset-parity coherence gate you wrote in
`WavMultibitSync_18` + `WlinkGenericFCReplayAddrSync_18` lives **only on the sideband nodes `V2_12/_13`**;
the active write-path nodes `V2_1/_3/_5` still use the plain mailbox. A mid-stream single-domain reset
(de-anchor) *can* land the ping-pong in `w_ready=0 & r_ready=0`, which continuous-`w_inc` **can't**
escape. One angle rates this the wedge; two rate it a **bring-up** pathology that self-heals mid-burst.
Either way it's worth porting `_18` onto `_1/_3/_5` — low-risk hygiene — but it's not the leading soak
cause.

All three are RTL, none is skew, none is a constraint fix, and none is TL-009/027/032 (which are present
and effective — they closed the ~6-word bring-up cap, HW-proven 08-09 — but address different sub-cases).

## 4. What to KEEP vs what to change

- **KEEP:** the a2l self-heal on `_1/_3/_5` (works). The RX-word `[4c]` constraint **on the ASIC SDC**
  (functional — this is the same fix already drafted for the ASIC RX-word gen-clock). The `[4c]` block
  on the eth-chiplet FPGA XDCs is harmless and diagnostically true (it makes the timer honest), but note
  in its comment that it's an ASIC fix / FPGA no-op — I've drafted it there.
- **CHANGE (the wedge fix, RTL):** un-stick the state-7 watchdog — make `socl_l7_real_crc_seen`
  non-sticky (drop the `& ~socl_l7_real_crc_seen` gating from both `wdog_cnt` and `wdog_force_clear`) so
  the watchdog fires during a real-CRC recovery stall, plus the state-7 exit on
  `(auto_tx_out_advance | wdog_force_clear)`. This is exactly my staged **TL-033 + §6**
  (`scratchpad/plan_a2l_r1_fcsm.md`), which I **stashed** before these builds — so the tested bits
  **lack** it (consistent with the wedge). Reconcile with your registry's TL-033/TL-035 numbering.

## 5. How to confirm — cheapest first, definitive last

1. **One good-eye CRC inject (one rig session, no rebuild).** `cov_errinject_sweep` already wedges die_a
   on the first AW inject on a good eye. Run it explicitly as the A/B: if a good-eye link wedges on a
   single injected CRC identically to the soak wedge, the **recovery-deadlock is confirmed and the
   CDC/clock story is excluded** — and R1≡R2 is proven.
2. **Causal build (one rebuild).** Un-stick the watchdog (TL-033 + §6) → rebuild → re-soak. If the
   `rc=124` rate collapses, #1 is causally confirmed.
3. **Definitive silicon ILA (the method is PROVEN on this die).** `FPGA_INSERT_DEBUG_CORE=1` on die_a
   only (the 2026-08-02 recovery capture used exactly this: 28 probes, 4096 samples, read over KR260
   JTAG via mapstone-dev `hw_server` — **JTAG reads die_a while its PS is deadlocked**, which mmap/APB
   cannot). Minimal decisive probes (~30 bits) on the **AW a2l node + its FCSM + credit**:
   - a2l `V2_1`: `app_ready`, `app_valid`, `a2l_full`, `a2l_app_addr[3:0]`, `a2l_link_addr[3:0]`,
     `a2l_link_addr_app_clk[3:0]`, `fifo_io_rbin_ptr[3:0]`, `link_ack_update`, `link_ack_addr[3:0]`,
     `a2l_ack_valid`, `link_revert`.
   - FCSM: `state[2:0]`, `send_nack_req`, `socl_l7_wdog_cnt`, `socl_l7_real_crc_seen`,
     `socl_l7_wdog_force_clear`, `auto_tx_out_advance`, `crcCorruptSeen`, `isNackPacket`.
   - credit: `fe_rx_credit_max[7:0]`, `fe_tx_credit_max[7:0]`.
   **Trigger** on a *permanent*-stall dwell bit (a saturating counter of `app_valid & ~app_ready`,
   reset on progress), position 50%, so the ~3/4 clean soaks (normal transient `app_ready=0`) never
   false-trigger. **Orthogonal decision tree** (frozen values at the trigger):
   - `a2l_full=1` + `a2l_link_addr_app_clk` a lap-ahead 0x1f-class phantom + mailbox `r_data=0x1f` →
     mailbox tear (skew) — *predicted absent*.
   - `a2l_full=1` + ACKs advancing but `a2l_ack_valid=0` + `a2l_link_addr` frozen → a2l self-latch (logic).
   - `a2l_full=0` + FCSM stuck state-7 + `real_crc_seen=1` + `wdog_cnt=0` + `auto_tx_out_advance` flat →
     **FCSM watchdog-dead (#1) — predicted.**
   - FCSM idle + `credit_max=0` never replenishing → credit starvation (#2).
   Capture protocol: arm the JTAG ILA (survives PS deadlock), loop POR→deploy→bringup→arm→`write 128`;
   at p≈1/4 one triggered capture lands within ~6–10 cycles.

## 6. Provenance / artifacts / rig state

- Bits tested (wedge-persists): `imp/fpga/output/_calwrap_rxwc8/` (8-lane) and `_calwrap_rxwc/`
  (lane-0), + `_calwrap_r2/` (calwrap, no RX-word). All verified: calwrap + a2l self-heal `_1/_3/_5`
  (10–11 TL-027 markers) + (rxwc) the 8 gpiorx clocks. flist `tidelink_fpga_v2.flist`.
- **TL-033 (watchdog revive) is stashed** in my submodule working tree (`stash@{0}`); the §6 state-7-exit
  spec is `scratchpad/plan_a2l_r1_fcsm.md`.
- Rig clean, leases released. The eth-chiplet ILA flow: `fpga/build_design.tcl` STEP 8.5
  (`FPGA_INSERT_DEBUG_CORE=1`, not defaulted on this target), `fpga/insert_debug_core.tcl`; readback
  adapts `pynq_host/scripts/phc_ila_capture.{sh,tcl}` to die_a JTAG cable `XFL1MHS3ZB1P` at 2 MHz.

## 6.5. UPDATE (2026-08-11 PM) — confirm-path step 2 done: TL-033+§6 is REFUTED as the fix

I built and HW-tested the TL-033+§6 candidate (watchdog revive + state-7 exit on
`auto_tx_out_advance | socl_l7_wdog_force_clear`, all 5 recovery FCSMs, verified §6 in the packaged
IP). On a **good eye** (both dies FCSM=4 / cal=1), a **single AW byte-0 CRC inject STILL wedged
die_a** (PS AXI deadlock → JTAG-POR). Conclusions:
- **CONFIRMED:** the wedge is **deterministic on one good-eye AW CRC** — not eye/clock/lottery, and
  **R1 (errinject) ≡ R2 (soak)** (a single injected CRC reproduces the soak wedge). This is the
  clean silicon A/B that excludes the CDC/clock story for the wedge.
- **REFUTED:** the FCSM state-7 NACK-watchdog self-defeat is **not the fix** (TL-033+§6 doesn't close
  it) — so it's either not the mechanism, or an incomplete fix. **Off-rig fix guessing has now failed
  twice** (RX-word clock, then TL-033+§6).
- **NEW CLUE — check ECC-enable first (cheap):** byte-0 wedges **despite** the ECC-restore RTL
  (`local_overrides/WlinkEccSyndrome.v`) being compiled. In sim, byte-0 recovers byte-exact **with
  ECC on**. So on silicon either **ECC is disabled at runtime** (a config/enable bit — cf. the
  tapeout "ships ECC bypassed" note; a config fix, not RTL) **or** the recovery stall is deeper
  (Angle A's mailbox reset-coherence port `_18`→`_1/_3/_5`, or `fe_tx_credit_max` re-zero).

**Given two failed off-rig fixes, the ILA (step 3) is now the right move — do not blind-build a
third.** One cheap pre-ILA check: confirm ECC is actually enabled at runtime on die_b (the AW
decoder). Staged refuted-fix bits: `imp/fpga/output/_tl033/`.

## 6.6. UPDATE (2026-08-12) — die_a ILA is BUILT, STAGED, and ready to capture

The definitive diagnostic is built. `axi_chiplet_controller.sv` now carries 11 `mark_debug`
decision-tree probes (via the codebase's `dbg_*` alias-wire idiom — no functional perturbation) +
a permanent-stall trigger `dbg_a2l_wedged` (a saturating counter of `app_valid & ~app_ready`,
cleared on any `app_ready` progress, latching at ~2^12 ≈ 82 µs; transient backpressure never fires).
Built die_a with `FPGA_INSERT_DEBUG_CORE=1` (setup MET +1.008), `.ltx` emitted with all probes:
`dbg_fcsm_state`(3), `dbg_a2l_full`, `dbg_a2l_wptr`(5), `dbg_a2l_sack`(5), `dbg_cr_seen`,
`dbg_fe_rx_cred`(8), `dbg_a2l_app_rdy`, `dbg_a2l_app_v`, `dbg_a2l_lnk_empty`, `dbg_a2l_rreset`,
`dbg_a2l_wedged`(trigger). Staged: `imp/fpga/output/_ila/{tidelink.bit,.bin,tidelink_design_wrapper.ltx}`.
die_b runs the matching (functionally identical, no core) `imp/fpga/output/_tl033/kr260-eth-chiplet-flip/`.

**Capture procedure (attended, ~1 rig window):**
1. Deploy die_a = `_ila` bits (fpgautil, PS-side) + die_b = `_tl033` flip; bring up a good eye
   (both FCSM=4/cal=1); confirm the 8-word canary passes.
2. On mapstone-dev: `open_hw_manager` → `connect_hw_server` → open die_a JTAG target
   (cable `XFL1MHS3ZB1P`), **`set_property PARAM.FREQUENCY 2000000`** (the 2 MHz workaround for the
   Vivado dbg_hub corrupted-readback bug) → `current_hw_device` → `set_property PROBES.FILE
   .../_ila/tidelink_design_wrapper.ltx` → `refresh_hw_device`.
3. Set trigger `dbg_a2l_wedged == 1'b1`, position 50%, depth 4096; `run_hw_ila` (arm). JTAG arming
   is independent of the PS, so it survives the wedge.
4. Fire the deterministic wedge: `cov_errinject_sweep.py --nodes AW --wsoak 0` (one AW CRC inject).
5. `wait_on_hw_ila` → `upload_hw_ila_data` → `write_hw_ila_data -csv_file capture.csv`.

**Decision tree on the frozen values (`dbg_a2l_wedged=1`):**
- `dbg_a2l_full=1` + `dbg_a2l_sack` lap-ahead (0x1f-class) while `dbg_a2l_wptr` behind → **mailbox tear**
- `dbg_a2l_full=1` + `dbg_a2l_wptr` frozen (+ `lnk_empty`/`rreset` context) → **a2l self-latch**
- `dbg_fcsm_state==7` + `dbg_cr_seen=1` → **FCSM state-7 deadlock** (note: TL-033+§6 already refuted the
  watchdog-revive fix, so a state-7 finding means the exit/credit interaction, not the dead watchdog)
- `dbg_fcsm_state` idle + `dbg_fe_rx_cred==0` → **credit starvation**

(Skipped as too-risky-to-plumb before the build: `a2l_ack_valid`/`send_nack_req`/`wdog_cnt`/
`auto_tx_out_advance` — they'd need new cross-domain obs ports; the wired set discriminates all four.)

## 6.7. RESOLVED (2026-08-13) — silicon ILA: the wedge is a LOST WRITE RESPONSE, not a flow-control stall

The die_a ILA captured the frozen wedge state (raw AW CRC inject, NO POR, force-captured over JTAG;
4096 samples, all constant). Decoded probe values AT THE WEDGE:

| probe | value | verdict |
|---|---|---|
| `dbg_a2l_full` | **0** | a2l NOT full — no backpressure |
| `dbg_a2l_app_rdy` | **1** | app_ready HIGH — a2l ready, not stalled |
| `dbg_fcsm_state` | **4** | LINK_IDLE — NOT stuck in state-7 recovery |
| `dbg_fe_rx_cred` | **0x1f** | credit full — NOT starved |
| `dbg_a2l_lnk_empty` | 1 | a2l FIFO empty |
| `dbg_a2l_wptr` / `dbg_a2l_sack` | 2 / 1 | one-word gap — NOT a 0x1f lap-ahead tear |
| `dbg_cr_seen` | 1 | a CRC WAS seen (the inject fired + recovery ran) |
| `dbg_a2l_app_v` / `dbg_tx_*valid` | 0 | no write reaching the a2l or the AHB-TX adapter |
| `dbg_tx_hready` / `dbg_tx_hreadyout` | 1 / 1 | AHB-TX adapter idle + ready |

**All four candidate mechanisms are REFUTED by silicon.** At the wedge the entire TideLink a2l / FCSM /
credit / mailbox subsystem is **idle and fully healthy** — and `cr_seen=1` shows the CRC fired and the
recovery COMPLETED (FCSM back to idle-4, a2l drained empty, credit restored). Yet die_a is hung.

**Root cause = a LOST WRITE RESPONSE (B/HRESP completion) on the PS-return path.** The write's data
went out and was CRC'd; TideLink recovered cleanly to idle; but the write's completion was never
returned to the PS, so the PS AXI write channel hangs forever waiting for it. No new write is offered
to the a2l (`app_v=0`) because the PS master is blocked on that outstanding one. This is exactly the
`AXI_DATANODE_RECOVERY_AMPLIFIER_SOUND_2026_08_01` / 2026-08-02 finding — **"I5 fires, HRESP doesn't
propagate"** — now CONFIRMED on silicon for the current design.

**Therefore the correct fix is on the write-RESPONSE / outstanding-completion path (the I5 backstop —
generate/propagate the B-response after a CRC-recovery; don't let I5 disarm on a mismatched/late B),
NOT any flow-control / clock / CDC change.** Every off-rig fix attempted (RX-word clock, TL-033+§6
watchdog, and the never-needed mailbox set_bus_skew) targeted the wrong subsystem — the ILA proves that
subsystem is idle at the wedge. See the AXIREC recovery thread for the I5/HRESP fix candidates
(track expected BID / hold the outstanding-response until a correct B; do not clear on B *arrival* alone).

Capture artifacts: `scratchpad/ila_capture_run/ila_capture.csv` (4096-sample frozen state),
`scratchpad/{ila_capture.tcl,ila_capture_run.sh}` (the working JTAG capture harness).

## 7. Asks

1. **Confirm the numbering** — is my TL-033 (un-stick state-7 watchdog) == your registry's TL-035, and
   is the credit-underflow your TL-033? I'll adopt your registry.
2. **Decide the confirm path** — I can run the **good-eye single-CRC inject** now (cheap, no rebuild),
   and/or build **TL-033 + §6** and re-soak. Say go and I'll drive either.
3. **The ILA** (definitive) needs the `mark_debug` taps added to the active `V2_1`/FCSM nodes (several
   are already hoisted as `obs_*`) + a die_a-only debug build + an attended JTAG capture — your call on
   whether to go straight there or do (1)/(2) first.
4. **Keep the RX-word gen-clock on the ASIC SDC** (functional there); it's the same fix as the drafted
   ASIC RX-word block.
