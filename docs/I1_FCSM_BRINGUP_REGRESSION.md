# I1 FCSM recovery fix breaks KR260 link bring-up (silicon finding, 2026-07-30)

**For the TideLink developer.** The I1 flow-control-recovery fix on `main`
(`b98b944`, "re-point AXI FCSM 0-4 to local_overrides + tune state-2 CRACK gate"),
which lowers `SOCL_L7_MIN_CRACK_EMITS` 32 → 8 and points the 5 AXI data-plane FCSMs
at the recovery-capable `local_overrides` copies, **prevents the TideLink d2d link
from coming up on the KR260 eth-chiplet pair.** It trades the sustained-traffic
wedge for a link-bring-up failure.

This is the opposite failure mode from what it fixes, so it must not ship as-is.

## What was tested (all on the two-board KR260 eth-chiplet bench, 2026-07-29/30)

The bring-up criterion is `SWI_LANE_STATUS @ 0x2E03_2108`: `cr_seen`, `crack_seen`,
`calibration_done`, and `fcsm` reaching **4 (LINK_IDLE)**, bilateral, over the
`eth_ss_0` backdoor. `cr_seen`/`crack_seen` are the FCSM **credit / CRACK handshake**
signals (the same CRACK emits that `SOCL_L7_MIN_CRACK_EMITS` gates in state 2) — NOT
PHY clock recovery.

| Build | AXI FCSM 0-4 source | Result on silicon |
|---|---|---|
| **baseline `0ed6d46`** (V2, pre-I1) | `deps/` (recovery-stripped) | **LINK UP** — `cr_seen=1 crack_seen=1 cal_done=1 fcsm=4`, both dies. Proven **3×** (initial M1, + two A/B re-confirms today). Wedges under sustained traffic (the original bug). |
| full merge **`969a0c9`** (origin/main) | `local_overrides/` recovery, gate=8 | **LINK DOWN** — `cr_seen=0 crack_seen=0 cal_done=0`, fcsm stuck 0/1, both dies. |
| minimal **`90fe6cc`** (I1 cherry-picked onto the proven base `809f038`, autoneg/`tidelink_top` byte-identical to baseline) | `local_overrides/` recovery, gate=8 | **LINK DOWN** — identical `cr_seen=0 crack_seen=0`, both dies. |
| **mix**: `90fe6cc` die_a + `0ed6d46` die_b | die_a recovery / die_b deps | **LINK DOWN** — the recovery-FCSM die_a stays `cr_seen=0 fcsm=0`; the deps die_b gets to `fcsm=1` then stalls waiting on the master. |

**Two independent recovery-FCSM builds fail identically; three deps-FCSM runs pass —
on the same two boards, same ribbon, same deploy flow.** The recovery FCSM RTL is the
only common differentiator.

## What was ruled out (with evidence)

- **Physical / ribbon.** Baseline links up FCSM=4 on these exact boards, repeatedly,
  including immediately before and after the failing runs. Ribbon is fine.
- **PHY submodules.** `deps/tidelink-phy 5c76e76` and `deps/tidelink-gpio-phy 6ee8418`
  are byte-identical (pin + working tree) between baseline and the failing builds.
- **`DEVICE_CLASS` strap** (the eth-chiplet G1 batch-prep). die_a is strapped class=1,
  which equals the RTL default — a no-op — yet die_a still fails. Not the strap.
- **Autoneg / `tidelink_top`.** In `90fe6cc` these are **byte-identical** (SHA
  `5080ec0`) to the M1-proven baseline. (An earlier hypothesis that the merge's
  autoneg "Option A" delta was the cause was a confound — the minimal build with
  baseline autoneg fails the same way.)
- **Timing.** `90fe6cc` closes at **WNS = +0.304 ns (setup met)**; hold ≈ −22 ns, the
  same pre-existing hold violation the working baseline ships with. Not a timing regression.
- **My cherry-pick being incomplete.** The *full dev-authored merge* (`969a0c9`, with
  every I1 companion) fails identically to the minimal extraction. So it is the I1 FCSM
  RTL itself, as authored, not a missing companion file.

## The ask

The recovery-capable FCSM override must **bring up the link AND recover under traffic**
at the KR260 silicon ratio (link_clk:app_clk ≈ 40 ns). Today:
- gate=32 → documented to **stall** FCSM state 2 at silicon ratio;
- gate=8 → **never establishes** the initial CR/CRACK handshake (`cr_seen=0`);
- deps (no recovery) → handshakes + FCSM=4, but no traffic recovery.

The `tidelink_fcsm_silicon_ratio` cocotb suite reports PASS at gate=8, so there is a
**sim/silicon gap**: sim does not reproduce the initial-handshake failure the KR260 sees.

## RTL root-cause hypothesis

_(RTL-level analysis of `local_overrides/WlinkGenericFCSM.v` vs the `deps/` version —
the state-2 CRACK-emit gate and the CR/CRACK handshake — is in progress; appended below
once complete.)_

## Board / repo state left behind
- Both KR260 boards restored to the **working baseline (`0ed6d46`)** bitstream, leases
  released. The wedge-prone-but-functional link is what's deployed.
- tidelink branch `integ/i1-fcsm-on-proven` (`90fe6cc`) and parent pin (`99192a2`)
  document the attempt — **do NOT build/deploy for bench use; the link will not come up.**
- Preserved bitstreams: `imp/fpga/output/kr260-eth-chiplet{,-flip}.{baseline-0ed6d46,i1-90fe6cc,fixed-969a0c9}/`.
