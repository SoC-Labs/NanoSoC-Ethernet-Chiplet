# Root-cause assessment — the KR260 D2D "delivery collapse" is an unconstrained recovered-RX-word-clock CDC deadlock, NOT an eye/thermal day


> **SUPERSEDED — the mechanism below was built, tested on hardware, and did not fix the
> wedge.** Measured 2026-08-10. The RX-word `create_generated_clock` fix was
> implemented across 8 lanes and verified in-netlist; the `rc=124` write-wedge
> survived it. See `../history/DEV_MESSAGE_D2D_WEDGE_ROOT_CAUSE_CORRECTED_2026_08_11.md`
> for the re-derivation, and note that *that* document was in turn overturned by the
> 2026-08-13 die_a ILA. Current head of the chain:
> `DIAGNOSE_AHB_SUB_HREADYOUT_FROZEN0_tidelink_die_a_u_xhb_sub.md`.
> The negative result is the durable content: the wedge is not RX-word-clock skew.

**Date:** 2026-08-10. **Method:** five independent agents, each attacking the failure from a different angle, instructed to be adversarial toward the orchestrator's preliminary "bad-eye day" conclusion. **Trigger:** the user challenged that conclusion, suspecting clock skew or a hardware defect.

## TL;DR — the verdict

The user was right and the "eye/thermal" framing was wrong. **All five angles converge on a single root cause: the recovered /16 RX word clock on the D2D link has NO timing constraint (`create_generated_clock`), which leaves a multi-bit pointer CDC skew-unbounded. A per-POR recovered-clock phase lottery decides whether a given bring-up lands inside the unbounded capture margin.** When it lands outside, the sustained (128-word) transfer laps the shallow replay FIFO enough times to latch a torn "lap-ahead" pointer → false-FULL → `app_ready=0` → the initiator's AXI store burst **hangs (rc=124)**.

- **It is a WEDGE (a clean AXI hang), not data corruption** — 6/6 soak failures are rc=124 timeouts, zero miscompares. An eye/bit-error cannot stall the bus; it would land wrong data and fail `verify`. This single fact refutes "bad eye" as the soak root cause.
- **NOT a hardware defect** — thermal throttle and marginal power rails are positively excluded by live sensor data; the two boards are electrically symmetric twins.
- **NOT a config/harness change** — repo, harness, deploy/AFI path, and the tested bits are provably identical to the 08-09 run; the test methodology is sound.
- **NOT primarily eye/thermal** — the "eye" was never actually measured (the winscan eye marker never reads back; "good/bad eye" is a canary proxy). Temperature is at most a second-order contributor and is not required to explain the data.

**Highest-leverage action:** add the missing RX-word-clock constraint + bounded CDC skew, rebuild, re-soak — a one-build-cycle fix-and-confirm.

---

## The question

On 2026-08-09 the pair produced a good-eye burst: 128/128 cross-die writes + 128/128 reads byte-exact. On 2026-08-10, across ~30 bring-ups in three separate efforts, the same class of test could not sustain even a 128-write soak: the link re-anchors (FCSM=4 + deskew locked), an 8-word canary passes on ~half the bring-ups, but the 128-write soak wedges (rc=124), so the endurance test never starts. **Both** the "calwrap" bits (with the 3f037c0 calibrator fix) **and** the exact 08-09 a2l-only baseline bits failed today — so it is environmental/rig/hardware, not bitstream logic. The orchestrator called it a "bad-eye day"; the user challenged that.

## Method — five independent adversarial angles

| # | Angle | Mandate |
|---|---|---|
| 1 | Temporal forensics | What *changed* between the 08-09 success and today? |
| 2 | Clock-skew / CDC mechanism | Does an unconstrained recovered-clock / CDC path explain "trains + 8-word OK + 128-word wedge"? |
| 3 | Failure-signature forensics | Is the 128-soak a timeout-*wedge* (hang) or a data-*corruption*? Determinism, asymmetry. |
| 4 | Hardware/board-defect isolation | Live read-only probes: thermal, power rails, dmesg, die_a-vs-die_b asymmetry. |
| 5 | Methodology / provenance audit | Is any of the "regression" an artifact — short timeout, sudo corruption, bad deploy, wrong baseline? |

Deliberately, only 2 of 5 chased the clock-skew/hardware hypotheses directly; the other 3 independently characterized the failure so the synthesis is evidence-driven, not confirmation-biased.

## The decisive evidence

### 1. The failure fingerprint: WEDGE, not corruption (Angle 3)
Across all four campaigns, every 128-write soak failure is identical: `write wedged (rc=124)` — a 60 s SSH timeout with the store burst never returning. **Zero** data mismatches; when the soak completes it is `128/128 byte-exact`. The write is a bulk burst of MMIO stores to the peer aperture (`0x2F001000`); rc=124 means the AXI write channel stopped returning HREADY/B-response, i.e. **a flow-control / credit / CDC deadlock on the initiator D2D path**. An eye/bit-error cannot produce this — a corrupted word still completes the bus cycle and lands wrong, which `verify` flags. That is never seen. Corroborating: half the bring-ups **spontaneously fell out of FCSM=4 within seconds of a clean re-anchor, with zero traffic applied** (idle de-anchor = a wandering recovered clock), and the corruption that *does* appear (only at canary) is **framing/pointer slips** — an off-by-4-word pointer slip (`word 0 slot held word 4's value`), byte-lane marker drops — not amplitude noise.

### 2. The mechanism, with RTL + timing evidence (Angle 2)
1. **The recovered RX word clock is a free-running /16 divider with NO timing constraint.** `WavD2DGpioRx_v2.v:681` (`BUFG` on `~count[3]`). The FPGA timing XDC constrains the *TX* word clock (`kr260_eth_chiplet_tidelink_timing.xdc:328`) but **not the RX**. The routed report proves it: `check_timing no_clock`, ~8998 pins rooted on `gpiorx_0/…/count_reg[3]/Q` — the entire RX link-layer, deskew, calibrator, and **l2a return-path FIFOs run on an untimed, un-skew-bounded net**, feeding the B-response/R-data return path into die_a (the wedge direction).
2. **A multi-bit pointer CDC on that domain tears into a "lap-ahead phantom."** The replay full-flag (`WlinkGenericFCReplayV2_1.v:75`, `a2l_full` wrap-bit compare; `:121` `app_ready=~a2l_full`) crosses through a 2-slot mailbox `WavMultibitSync_18`. Correct sampling needs a bounded pointer-vs-data-slot skew — unconstrained when the writer is the untimed RX clock. The RTL documents the exact silicon failure: *"after ~6 A→B words the app-side synced ACK wedges at raddr=0x1f (a full lap ahead of wbin=15) → false-full … DEADLOCK: the writer can't push"* (`WavMultibitSync_18.v:50–71`).
3. **The 8-vs-128 boundary is the FIFO depth.** The shallowest replay FIFO (`_1`/`_5`) is **8-deep**. The 8-word canary fills it exactly once (the tear rarely fires); a 128-word soak **laps it 16×**, re-arming the skew-exposed mailbox each lap → the tear eventually latches the 0x1f lap-ahead phantom → deadlock.

### 3. Why 08-09 passed on the *same bits* (Angles 2 + 5)
This is not a routing regression: the 08-09 baseline has the **identical** untimed hole (`no_clock`, same `count_reg[3]` fanout). Same bits ⇒ identical static routing skew. What is re-drawn every bring-up is the **recovered clock's phase** — an explicit *"per-carrier-session lottery, mod 16"* (`WavD2DGpioRx_v2.v:261–267`). With the CDC capture margin unbounded (Vivado never timed it), whether a phase draw lands in the safe window is chance. 08-09 drew a phase that held for a one-shot 128W+128R; today's ~30 draws land outside. **This is the canonical "worked yesterday, fails today, same bits" of an unconstrained CDC — a fixed structural gap sampled by a per-POR phase lottery. Temperature is not required.**

### 4. Hardware defect positively excluded (Angle 4)
Live read-only sensor sweep of both boards: PS/PL die temps 32–36 °C (throttle is ~85 °C+), every PS/PL/GTR/DDR rail nominal and **stable** under sampling (no droop/ripple), dmesg byte-identically clean, both PL `operating`, both fans driven. The two KR260s are electrically symmetric twins. **Thermal throttle and marginal power rail — the two *real* hardware causes the user rightly wanted separated from "signal eye" — are both directly excluded.** The frequent reboots are the POR cadence, not crashes. The only physical element not instrumentable from the PS is the J21 ribbon signal margin — but the clean-hang-not-corruption signature argues against ribbon degradation too (a degraded lane gives scattered miscompares, not a threshold-then-hang).

### 5. The methodology is sound; the baseline story needed correcting (Angle 5)
- **rc=124 is a genuine wedge, not a short timeout.** A working 128-write path completes in a few seconds (a full sysval — T1+T2+T2b+T3(128W)+T10(50R) — ran in 24.7 s); the 60 s budget is ~10–20× the real time. rc=124 = a full 60 s with no return = a real bus hang.
- **The baseline bits are genuine** — `_a2lonly_ab/**` is sha256-identical to the 08-09 snapshot. "Identical bits → worse today" cleanly points to a physical/clock delta.
- **Correction to the orchestrator's framing:** the 08-09 run was **not** a clean sustained pass. Its own artifact (`run_categoryA_goodeye.log`) shows T3 128/128 + T10 128/128 PASS **but T6 endurance FAIL at beat 768**, overall `kr260_sysval FAIL`, and it took 2 eye-tries to land the canary. So today is a **marginal worsening of an already-marginal link**, not a fall from a clean baseline — exactly what a per-POR CDC phase lottery predicts.
- Harness exonerated: deploy+AFI+FCSM=4 succeeded on 100% of ~30 bring-ups; the `sudo -S` stdout-corruption bug is inactive on this path (clean parsed diagnostics). One latent nit: add `-p ''` to `kr260_sysval.py board()` defensively.

## Ranked root-cause hypotheses (synthesis)

| Rank | Hypothesis | Verdict | Weight of evidence |
|---|---|---|---|
| **1** | **Clock-skew / CDC on the unconstrained recovered RX word clock** | **CONFIRMED (~80–90%)** | Angle 2 (RTL+timing+FIFO-depth), Angle 3 (wedge-not-corruption, idle de-anchor, framing slips), Angle 1 (systematic, one die failed FCSM=4), Angle 5 (rc=124 real, same-bits-worse) |
| 2 | Physical eye / framing lottery (secondary) | Contributor to the *canary-FAIL* half of bring-ups only | Angles 2, 3 — but traces to the *same* unconstrained recovered-clock phase draw |
| 3 | Config / harness / "what changed" | Refuted as a driver | Angles 1, 5 — nothing changed; harness sound; bits sha-identical |
| 4 | Hardware defect (thermal / power / bad board) | Refuted (thermal + power *positively* excluded) | Angle 4 — symmetric twins; only J21 ribbon uninstrumented, and the failure mode argues against it |
| 5 | Methodology artifact | Refuted (~90% no artifact) | Angle 5 — rc=124 is a real hang, deploy/AFI clean, baseline valid |

**The eye and CDC-skew workstreams overlap because both are downstream of the one missing RX-word-clock constraint** — which is why constraining it is the single highest-leverage action.

## Corrections to the record (intellectual honesty)
1. "Bad-eye day" was an **inference, not a measurement** — the winscan eye marker never reads back on this rig. The real driver is a digital CDC deadlock.
2. "08-09 was a clean 128/128 pass" **overstated** it — that run failed endurance at beat 768 and needed 2 eye-tries. The link was already marginal; today is worse, not a cliff.
3. The user's **clock-skew hypothesis is validated**; the **hardware-defect hypothesis is largely excluded** (except an uninstrumented ribbon, itself argued against by the failure mode).

## Recommended actions (in priority order)

1. **Fix-and-confirm (one build cycle, dispositive):** add the RX-word `create_generated_clock` (mirror the TX-word constraint onto `gpiorx_0/count_reg[3]/Q`, /16) + a bounded `set_max_delay`/`set_bus_skew` on the mailbox pointer-demet and mem-slot→`r_data` paths + an async `set_clock_groups`; rebuild the pair; re-soak across multiple bring-ups. If bounding the RX-word CDC skew makes the 128-soak robust across bring-ups, clock-skew/CDC is confirmed as the driver. This is the FPGA twin of the RX-word-clock constraint already drafted for the ASIC side (`d2d-rx-word-clock-unconstrained`).
2. **Definitive silicon proof (attended ILA):** probe `WavMultibitSync_18` `wptr`/`rptr`/synced-`wptr`/`raddr`/`r_data` and `a2l_full`/`app_ready` during a live 128-wedge. Decisive signature: `raddr` latches a lap-ahead (0x1f-class) value while the true write pointer is behind, driving `a2l_full=1`/`app_ready=0` with no real backlog — the torn-pointer CDC deadlock, cleanly separated from credit-starve or eye.
3. **Cheap hardware cross-checks (rule out the last physical unknown):** role-swap (make die_b the initiator) — if the wedge follows the initiator *role*, it's logic not board; and reseat the J21 ribbon.
4. **Latent hygiene:** add `-p ''` to `kr260_sysval.py` `board()`.

## What this means
- **R2 (the endurance/soak "wedge") is not an a2l/calibrator RTL bug and not a bad-eye day — it is the missing RX-word-clock constraint.** The retraction of "R2 = eye-drift" stands, but the correct home is the **clock-constraint** fix, not "wait for a better eye."
- **`3f037c0` remains a no-regression** (confirmed separately) and is orthogonal to this.
- This is the same open item flagged in `d2d-rx-word-clock-unconstrained` ("resolve 2026-08-10") — now positively implicated as the D2D delivery-wedge root cause, on both FPGA and ASIC.
