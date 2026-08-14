> ## ✅ ROUND-2 ILA RESOLVES IT (2026-08-13) — conclusion CONFIRMED, original route WITHDRAWN
> **The conclusion "it is `wr_hold_r` (rank5), TL-002 implicated" is CONFIRMED by direct measurement.** The
> round-2 die_a ILA (hex-first, 43 probes, `dbg_wr_hold_r` etc. all `ILA_PROBE_OK`) froze:
> `dbg_wr_hold_r=1` every sample, `dbg_wr_hold_clr=0`, `dbg_ext_is_nonseq=0`, `dbg_pipe_valid_r=0`,
> `dbg_rd_pipe_r=0`, `sub_err1_r=sub_err2_r=0` — mux walk ranks1-4 all FALSE → **`wr_hold_r=1` is the sole
> low-driver of `ahb_sub_hreadyout`. Unambiguous.**
>
> **BUT the original *route* in this doc — "the current capture discriminates via the `sub_stall_ctr_r`
> sawtooth" — is WITHDRAWN. It was a hex-decode artifact** (base-10 parse of a hex ramp manufactured fake
> resets; re-decoded it is a clean +1/clock ramp, zero resets). The round-1 capture did **not** discriminate;
> round-2 did, by directly probing the terms. This was a **partial hit**: right answer (`wr_hold_r`), wrong
> route — and the predicted mechanism was measured FALSE (`ext_is_nonseq`=0 not 1, `pipe_valid_r`=0 not
> toggling). **Correct mechanism (measured):** `wr_hold_r` latched on the initial write presentation and
> holds *forever* — the PS is blocked so it presents no new nonseq (`ext_is_nonseq=0`); the closed loop is
> `wr_hold_r=1 → hreadyout low → no AW accept → sub_wr_os_ctr=0 → synth-B can't arm → wr_hold_clr never fires
> → wr_hold_r stays 1`. Measured end-to-end.
>
> **Confirmed-and-measured survivors:** `sub_stall_ctr_r` spanned `0..65536` this run → `sub_stall_expired`
> genuinely FIRES, yet `synth_b_pending=0` → the `& (sub_wr_os_ctr != 0)` guard is the decisive blocker
> (measured, not argued). In-run die_b readback: `b0008000..3` landed while `sub_aw_accept=0` → landed writes
> ≠ the wedge write, a **single-run fact**. **Cocotb test PROMOTED** to "reproduces THE silicon wedge
> mechanism" / regression lock — pending an alignment of its held-state asserts to the measured values
> (`ext_is_nonseq=0`, `pipe_valid_r=0`), not the sawtooth-era prediction. **Fix target:** clear `wr_hold_r`
> on a pre-accept AW abort/timeout (TL-042 class). **Status: n=1 frozen state (wedge 4/4); a second confirming
> capture + David's go gate the RTL fix.** Read the RTL logic below as correct; the *route* narrative is the
> withdrawn part.

# HANDBACK — die_a `u_xhb_sub` AHB→AXI wedge: `wr_hold_r` (TL-002) stuck HIGH via an AW-never-accepted deadlock. Diagnosed 2026-08-13. [SEE RETRACTION ABOVE]

**From:** nanoSoC eth-chiplet integration — diagnosis session on the die_a ILA capture your rig filed.
**Date:** 2026-08-13.
**Subsystem:** `tidelink` `u_xhb_sub`, the AHB→AXI **outbound** bridge on die_a (`s_axi` side), under the injected D2D write wedge.
**Witness you filed:** `dbg_ahb_sub_hreadyout = 0` — the PS-facing AHB `hreadyout` held low, output of the override-priority mux at `tidelink_top.sv:1909-1914` (dbg alias at `:1919`).

---

## 1. Verdict (one line)

The PS-facing `ahb_sub_hreadyout` is pinned low by **rank5 `wr_hold_r`** (the TL-002 peer-write data-phase hold) STUCK HIGH, because the injected write's **AW is never accepted onto `s_axi`** (`sub_aw_accept=0`) so neither of `wr_hold_r`'s two clear paths can ever fire — an AW-backpressured-before-first-accept deadlock the existing DEADLOCK GUARD (`:1822-1834`) was **not** built to cover. **Reproduced in unit sim (cocotb `tidelink_top_pair_v2`, 2 PASS), so it is a real RTL deadlock, not silicon-only.**

## 2. LEADING MECHANISM + the frozen values that ground it

**Mechanism.** `wr_hold_r` (`tidelink_top.sv:1913`, rank5 of the `ahb_sub_hreadyout` mux) is SET on the pure AHB front-end — `wr_hold_set = ext_is_nonseq & ahb_sub_hwrite & ~pipe_valid_r` (`:1836`) — which needs **no** `s_axi` accept. The injected transaction is a write, so the hold latches when the write NONSEQ is first presented. Both clear paths (`wr_hold_clr`, `:1837-1838`) are dead in the frozen state:
- **W-handshake clear** `s_axi_wvalid & s_axi_wready & s_axi_wlast` never fires because the AW was never accepted (`sub_aw_accept=0`), so no W beat ever crosses onto `s_axi`.
- **`synth_b_pending` guard clear** is dead because `synth_b_pending=0`, itself dead because `sub_wr_stuck_fire` (`:1868`) is gated on `sub_wr_os_ctr!=0`, and `sub_wr_os_ctr=0` (it only increments on `sub_aw_accept`, `:1672-1673`).

The DEADLOCK GUARD comment at `:1822-1834` explicitly covers **AW-accepted-but-W-`wready`-never-rises**; here the AW itself never accepts, so the very backstop meant to break the hang can never arm.

**Frozen values that ground it (all from your capture):**

| signal | value | why it grounds the mechanism |
|---|---|---|
| `dbg_ahb_sub_hreadyout` | `0` | WEDGE WITNESS — mux output (`:1909-1914`) held low |
| `sub_aw_accept` | `0` | AW never accepted onto `s_axi` (`= s_axi_awvalid & s_axi_awready`, `:1570`) — kills the W-handshake clear |
| `sub_wr_os_ctr` | `0` | zero outstanding writes (`:1526`, inc only on `sub_aw_accept`, `:1672-1673`) — kills the synth-B arm chain |
| `synth_b_pending` | `0` | synth-B never armed (`:1876`); so the `wr_hold_clr` guard term (`:1838`) cannot fire |
| `sub_wr_stuck_fire` | `0` | synth-B arming term never fired (`:1868`, gated on `sub_wr_os_ctr!=0`) |
| `sub_stall_ctr_r` | `1600..9630` SAWTOOTH | capture is LIVE — XHB500 completes beats underneath; the counter resets every completed beat (`:1646`) |
| `sub_stall_expired` | `0` | per-beat stall backstop not tripped (`:1551`) |
| `sub_osr_expired` | `0` | I5 outstanding-response backstop not tripped (`:1575`) |
| `dbg_fcsm_state` | `4` | LINK_IDLE — transport healthy; wedge is local to this bridge |
| `dbg_fe_rx_cred` / `dbg_a2l_app_rdy` | `31` / `1` | RX credit full, app-to-link ready — not a link fault |

**Confidence at diagnosis time: medium** — every other mux term is refuted by a frozen value and causal necessity leaves only rank5, but `wr_hold_r`'s **direct value was UNMEASURED** in the capture (`dbg_wr_hold_r`, `:1938`, is a Round-2 probe absent from this frozen window). The unit repro (§4) then raised it to confirmed.

## 3. What the capture KILLED (mechanism + the value that killed it)

- **rank1** `(sub_err1_r & ~synth_b_pending)` (`:1909`) drives the low witness — KILLED by `sub_err1_r=0`.
- **rank2** `(sub_err2_r & ~synth_b_pending)` (`:1910`) drives the witness — KILLED by inspection: it drives `1'b1` (HIGH), so it structurally cannot produce a LOW.
- **rank3** `(ext_is_nonseq && !pipe_valid_r)` (`:1911`) is the SUSTAINED gate — KILLED by the `sub_stall_ctr_r` sawtooth (4096 distinct values, never reaches 2^16): per `:1645-1646` the counter resets whenever `sub_ext_stalled=0`, which forces the rank3 term to 0 on every completed beat, so rank3 cannot be stuck HIGH the whole window (`pipe_valid_r` must go high each reset). Also `sub_stall_expired=0`.
- **rank4** `rd_pipe_r` (`:1912`) holds the witness low — KILLED: `rd_pipe_r` only sets on `!ahb_sub_hwrite` (`:1782`) and this is a write; it is also a one-cycle pulse (`:1785`) that cannot span the thousands-cycle sawtooth.
- **Default** `xhb_sub_hreadyout_raw` (`:1914`) is the sustained cause — KILLED: the sawtooth resets require `sub_stall_busy = !raw = 0`, i.e. raw pulses HIGH every beat, so an override term must be masking those high pulses.
- **synth-B `||sub_axi_progress` arming-gap** starves the backstop — KILLED by `sub_wr_os_ctr=0` and `sub_axi_progress=0`: no timer was ever running for an arming gap to affect.
- **"die_a starves waiting for a lost B" (H2-as-cause)** — KILLED by `sub_wr_os_ctr=0` AND `sub_aw_accept=0`: no outstanding write is awaiting a B; the write never reached `s_axi`.
- **`wr_hold_r`'s TL-002 guard actively RECOVERS here** — KILLED by `synth_b_pending=0` (the guard's only clear term, `:1838`): the guard cannot fire. This is not only consistent with, but necessary for, `wr_hold_r` being STUCK HIGH.

Closing argument the kills leave standing: on each cycle where `pipe_valid_r=1` AND raw pulses high (the counter-reset instant), rank3=0 and rank4=0, so the **only** term that can mask raw=1 back to 0 and keep the master stalled is rank5 `wr_hold_r`. die_a IS wedged (sustained `dbg_ahb_sub_hreadyout=0`), therefore `wr_hold_r` must be masking.

## 4. UNIT VERDICT — REPRODUCED

**Environment:** cocotb `tidelink_top_pair_v2`, VCS T-2022.06-SP2. **Ran: yes. Reproduced: YES.**

**Diff:** one new test file, `cocotb/tidelink_top_pair_v2/test_v2_awwedge_wrhold.py` (no RTL edits — the `dbg_wr_hold_r`/`dbg_wr_hold_clr`/`dbg_ahb_sub_hreadyout`/`dbg_pipe_valid_r` probes already exist at `tidelink_top.sv:1919-1943`). `run_bringup_full` + `wait_cr_crack`, then cocotb `Force(0)` on `dut.u_master.s_axi_awready` held from **before** the first accept, one EWR (`HPROT[2]=1`) write NONSEQ to `0x4000_0000`, sample the deadlock signature every hclk for 4000 cycles. Built `SIM_BUILD=sim_build_awwedge EXTRA_DEFINES=+define+TIDELINK_SUB_STALL_TIMEOUT_LOG2=8 +define+TIDELINK_SUB_OUTSTANDING_TIMEOUT_LOG2=10`.

**Evidence (TESTS=2 PASS=2 FAIL=0), over a 4000-cycle window past both backstops (2^10=1024, 2^8=256):**
- `wr_hold_r` HIGH all 4000 (`wrhold_lo=0`, `wrhold_hi=4000`)
- `ahb_sub_hreadyout` LOW all 4000 (`hro_hi=0`, `hro_lo=4000`)
- `sub_aw_accept=0`; `sub_wr_os_ctr=0`; `synth_b_pending=0`; `sub_wr_stuck_fire=0`; `sub_osr_expired=0`; `dbg_wr_hold_clr=0`; `sub_err1_r=0`; `pipe_valid_r` seen `={0}`.
- **Non-vacuity control** (`test_awwedge_control_no_force_completes`, identical write, no force): `sub_aw_accept=1`, `sub_wr_os_ctr=1`, `wr_hold_r` momentarily high then cleared (`wr_clr=1`, final `wr_hold_r=0`) — the write completes. So the deadlock is injection-specific, not a bench artifact.

Every spec `assert_signal` held → DEADLOCK REPRODUCED. `pipe_valid_r=0` during the wedge confirms **rank5 `wr_hold_r`** (not rank3) is the operative low-driver.

**One honest divergence from the silicon capture, logged not asserted:** `xhb_sub_hreadyout_raw` did **not** sawtooth in sim — it pulsed high once at EWR address-accept (clearing `pipe_valid_r`) then parked LOW for all 4000 cycles, because with `awready` forced low and a single in-flight write the XHB500 bridge waits to push an AW it can never push. This is benign — the master-facing `hreadyout` is still pinned low by `wr_hold_r` with both backstops provably unable to arm — and it was logged rather than hard-asserted, so the test does not falsely claim the full multi-write raw-sawtooth detail the silicon window showed. The **mechanism** (rank5 stuck via dead clears) is identical; only the underlying XHB500 raw activity differs (single forced write in sim vs a live multi-write stream on silicon).

## 5. NEXT RIG EXPERIMENT — probe set + trigger + pre-registered decision tree

**Trigger.** Arm the ILA on `dbg_ahb_sub_hreadyout==0` held low ≥ 1024 hclk under the **same** injected D2D write wedge that produced this capture (identical trigger to the witness run), but capture the Round-2 `wr_hold` probe set at `:1938-1943` that was ABSENT from the frozen capture.

**Probes.**
- `dbg_wr_hold_r` (`:1938`) — the direct, currently-unmeasured discriminator
- `dbg_wr_hold_clr` (`:1940`) — confirm neither clear path fires
- `dbg_wr_hold_set` (`:1939`) — confirm it pulsed to arm
- `dbg_pipe_valid_r` (`:1942`) — expect TOGGLING (sawtooth), not stuck low
- `dbg_ext_is_nonseq` (`:1941`) — expect stuck HIGH (master re-presents the held write NONSEQ)
- `dbg_rd_pipe_r` (`:1943`) — expect 0 (write path never sets it)
- **ADD** `s_axi_awvalid` / `s_axi_awready` (awready driven by `axi_tgt_0_aw_ready`, `:2901`) — to see WHICH channel is backpressured
- **ADD** `s_axi_wvalid` / `s_axi_wready` — to confirm no W beat lands

**Pre-registered decision tree.**
- **OUTCOME A (predicted):** `dbg_wr_hold_r=1` sustained, `dbg_wr_hold_clr=0`, `dbg_pipe_valid_r` toggling, `dbg_ext_is_nonseq=1` → CONFIRMS rank5 `wr_hold_r` is the gate. Then read the AW channel: `s_axi_awvalid=1 & s_axi_awready=0` sustained → root cause is **AW-FC-node backpressure before the first AW accept** — the deadlock the synth-B guard cannot cover. Only OUTCOME A is consistent with every value in the current frozen capture.
- **OUTCOME B:** `dbg_wr_hold_r=0` while `hreadyout` sustained low AND `dbg_pipe_valid_r` stuck LOW AND `dbg_ext_is_nonseq` stuck HIGH → rank3 IS sustained after all, which **contradicts** this capture's sawtooth → treat as a cross-capture inconsistency (different wedge instance), re-trigger.
- **OUTCOME C:** `dbg_wr_hold_set` pulsing but `dbg_wr_hold_r` never latches high → a reset path is firing; inspect `dbg_wr_hold_clr` for an unexpected assertion; rank5 refuted.
- **OUTCOME D:** `s_axi_awready` pulses 1 but `sub_aw_accept` stays 0 → sampling/CDC skew artifact; re-examine probe alignment.

## 6. FIX direction IF the mechanism holds — and the PRIOR-fix implication

The mechanism has held in unit sim, so treat the fix as live pending the OUTCOME-A silicon confirmation.

**Root class:** AW-channel-backpressured-**before-the-first-accept** deadlock. `wr_hold_r` can outlive an AW that never accepts, and every backstop that could break the hang is gated on state that only exists **after** an AW accept (`sub_wr_os_ctr!=0`).

**Fix options (wrapper-side, beside the existing hold/synth-B, no vendor IP change):**
1. **Clear `wr_hold_r` on a front-end abort / AW-side timeout** so the hold cannot outlive an unaccepted AW — add a clear term that does not depend on `sub_wr_os_ctr`/`synth_b_pending`.
2. **Arm an AW-side timeout** (analogous to synth-B but keyed on `s_axi_awvalid & !s_axi_awready` sustained) so a never-accepted AW eventually produces a survivable AHB ERROR rather than an unbounded `hreadyout`-low hang.

**PRIOR fix implicated — YES, TL-002.** `wr_hold_r` is the TL-002 peer-write data-phase hold, and it is the sustained gate here. Its DEADLOCK GUARD (`:1822-1834`, the `synth_b_pending` clear term added for the AW-accepted-but-`wready`-never-rises case) does **not** cover the AW-never-accepted case — the guard's own arming precondition (`sub_wr_os_ctr!=0`) is exactly what is missing. So this is the same shape as prior "a prior fix's guard defeated by an unanticipated route": TL-002's hold is being implicated in a wedge its own guard cannot reach. The fix must extend TL-002's clear logic to a pre-accept abort path; do **not** revert TL-002 (the guard is still correct for the case it was built for). No other TL-0xx (synth-B / TL-003 / TL-005 / TL-035) is on the critical path for this mode — synth-B lives on the same bridge but cannot arm without an AW accept, and TL-035 is transport-side.

## 7. FIX-REVIEW ACCEPTANCE CRITERIA (checklist for the incoming diff)

The RTL fix is the peer's; my role is review. A diff is approvable only if **all** hold:

1. **Breaks the deadlock:** an AW-never-accepted write clears `wr_hold_r` within a bounded time → the PS gets a *defined* response (AHB ERROR / completion), never an unbounded `hreadyout`-low hang.
2. **No premature clear (data integrity — the load-bearing one):** it must NOT clear `wr_hold_r` before a legitimate in-flight W lands. The new timeout must be **2¹⁶-order** (like synth-B, ~0.65 ms @100 MHz), orders past any legal AHB backpressure, so it **never** fires on a normal write. A too-short timeout re-introduces exactly the premature-completion-before-data-commits bug TL-002 exists to prevent — a *silent* regression.
3. **No new guard-defeated-by-route (the day's meta-lesson):** the new clear/arm condition must key on the **consequence** (`wr_hold_r` stuck + `hreadyout` low + AW unaccepted for N), NOT on state the wedge itself suppresses (`sub_wr_os_ctr!=0`, `synth_b_pending`). Verify the new condition **can actually assert** in the measured frozen state.
4. **Vendor IP untouched:** diff is in `tidelink_top` wrapper only — no edit to `xhb500`/`hazard_list.sv` (read-only under `/research/AAA/ip_library`).
5. **TL-002 not reverted:** the fix *extends* `wr_hold`'s clear logic; it does not remove the hold (still correct for the W-never-lands case).
6. **Healthy path unperturbed:** the non-vacuity control (normal write accepts + `wr_hold` clears) still passes; no throughput/latency change on normal writes.
7. **Regression test updated:** `test_v2_awwedge_wrhold.py` currently asserts `wr_hold_r` **stuck** (the deadlock). With the fix that inverts — the diff must add a *post-fix mode* asserting "deadlock breaks within N, PS sees a bounded ERROR," while keeping the pre-fix deadlock repro (e.g. behind `TIDELINK_DISABLE_*`).
8. **Survivability layering:** the RTL fix makes the wedge survivable *at the bridge*; the FPGA AXI-timeout/firewall stays as the independent belt-and-suspenders catch-all (separate change).
9. **Release-lever fan-out (the check that catches v1 on inspection):** the fix's release path must **not** assert any signal that appears in `wr_hold_clr` (`= W-last | synth_b_pending`, `:1826`). Grep the fan-out of *every* signal the fix sets. **v1 satisfied #2 (a legal 2¹⁶ timeout) and STILL broke TL-002** because it reused `synth_b_pending` as its lever — and `synth_b_pending` disables the hold *wholesale* for as long as it is high, timeout or no. #2 (magnitude) is necessary-not-sufficient; #9 (mechanism) is what actually protects the data phase.
10. **End-to-end resumption, not just `wr_hold` clear:** acceptance evidence must show `ahb_sub_hreadyout` **goes HIGH / the PS resumes** — clearing `wr_hold_r` alone is not enough (see the necessary-not-sufficient note below).

> ### ⚠ v2 is NECESSARY-BUT-NOT-SUFFICIENT — do NOT sign a fix on "die_a survives errinject"
> The round-2 capture proves a **second, independent hold** beneath `wr_hold_r`: `sub_stall_ctr_r` ramps a
> clean `0→65536`, so `sub_ext_stalled` is continuously high; with `ext_is_nonseq=0` (⇒ `sub_stall_fill=0`,
> `:1542`) and `err1=err2=0`, `sub_ext_stalled = !xhb_sub_hreadyout_raw` (`:1543/1549`) ⇒ **`raw`
> (rank6) is continuously 0.** So "`wr_hold_r` is the sole low-driver" is true of *mux priority* only —
> rank6 co-holds. **v2 clears rank5; a v2 bench run should STILL wedge (raw holds), which is EXPECTED, not
> a failed fix.** The remaining question is *why* `raw=0` (XHB500 stalling on the unaccepted AW — vendor-IP
> internal, read-only). A direct `xhb_sub_hreadyout_raw` probe is confirming it. **Regression-lock note:**
> forcing `s_axi_awready`/`wready` LOW to build the state wedges XHB500 unrecoverably (so it can never show
> post-fix resumption) — the canonical lock forces the **valids** (`awvalid`/`wvalid`) instead, keeping the
> bridge live. The peer's v2 test is that canonical lock; `test_v2_awwedge_wrhold.py` (this session's dogfood)
> hits the awready trap and is superseded.
