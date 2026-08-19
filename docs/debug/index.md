# The die-to-die wedge investigation

One long-running defect dominates this directory: **a cross-die write can leave
`ahb_sub_hreadyout` latched low with no timeout, wedging the initiator die's bus
until a JTAG power-on reset.** It has been re-root-caused several times, and each
round left a document behind. Read the chain in order, or you will act on a
mechanism that a later measurement disproved.

## The chain, newest first

| Doc | Date | Verdict |
|---|---|---|
| [`DIAGNOSE_AHB_SUB_HREADYOUT_FROZEN0_tidelink_die_a_u_xhb_sub.md`](DIAGNOSE_AHB_SUB_HREADYOUT_FROZEN0_tidelink_die_a_u_xhb_sub.md) | 08-19 | **Current head.** The holder is `wr_hold_r`, starved by the **W-channel** flow-control node — a separate, unprobed node from the AW one earlier rounds instrumented. |
| [`BUGREPORT_AHB_SUB_HREADYOUT_HOLD_2026_08_19.md`](BUGREPORT_AHB_SUB_HREADYOUT_HOLD_2026_08_19.md) | 08-19 | The rig-side ILA capture the above answers. Frozen state: `hreadyout=0`, `awready` HIGH, a2l not full. |
| [`WEDGE_FIX_DESIGN_2026-08-18.md`](WEDGE_FIX_DESIGN_2026-08-18.md) | 08-18 | Design for a periodic re-ACK plus a data-safety guard. Design only — not landed. |
| [`WEDGE_REGRESSION_BENCH_2026-08-18.md`](WEDGE_REGRESSION_BENCH_2026-08-18.md) | 08-18 | The gate a candidate fix must pass: reproduces the wedge deterministically and is demonstrated to fail without the fix and pass with it. |
| [`XHB500_DOWNSTREAM_ASSESSMENT_2026-08-18.md`](XHB500_DOWNSTREAM_ASSESSMENT_2026-08-18.md) | 08-18 | The downstream half — what a full fix must do beyond clearing the TideLink-side latch. |
| [`DIAGNOSE_XHB500_RAW_HREADYOUT_LOW.md`](DIAGNOSE_XHB500_RAW_HREADYOUT_LOW.md) | 08-18 | Static trace inside the XHB500 bridge: a **second, independent** hold beneath `wr_hold_r`. Clearing `wr_hold_r` alone does not unwedge. |
| [`DIAGNOSE_HREADYOUT_LOW_u_xhb_sub.md`](DIAGNOSE_HREADYOUT_LOW_u_xhb_sub.md) | 08-13 | Round-2 ILA **confirms** `wr_hold_r` is the sole low-driver. Its own predicted *route* to that answer was withdrawn as a hex-decode artefact — right answer, wrong reasoning. |
| [`../history/DEV_MESSAGE_D2D_WEDGE_ILA_CONFIRMED_2026_08_13.md`](../history/DEV_MESSAGE_D2D_WEDGE_ILA_CONFIRMED_2026_08_13.md) | 08-13 | ILA exonerates the TideLink transport; the wedge is at the AXI-channel layer. Its own §4.1 head-of-line age timer is explicitly marked **do not build**. |
| [`../history/DEV_MESSAGE_D2D_WEDGE_ROOT_CAUSE_CORRECTED_2026_08_11.md`](../history/DEV_MESSAGE_D2D_WEDGE_ROOT_CAUSE_CORRECTED_2026_08_11.md) | 08-11 | Blamed an RTL recovery/flow-control bug on the TX side. **Overturned** by the 08-13 ILA. |
| [`ROOT_CAUSE_D2D_DELIVERY_WEDGE_2026_08_10.md`](ROOT_CAUSE_D2D_DELIVERY_WEDGE_2026_08_10.md) | 08-10 | **Superseded.** Blamed the unconstrained recovered RX word clock. The fix was built and tested on hardware; the wedge survived it. |
| [`AXI_DATANODE_RECOVERY_GAP_2026_07_31.md`](AXI_DATANODE_RECOVERY_GAP_2026_07_31.md) | 07-31 | Recovery on the AXI data nodes is **present but ineffective** for this failure mode — not stripped. Corrects the doc below. |
| [`CROSS_DIE_WEDGE_ROOTCAUSE.md`](CROSS_DIE_WEDGE_ROOTCAUSE.md) | 07-29 | **Superseded.** Claimed the build ships recovery-stripped flow-control state machines. Kept for the symptom description and the two-path disambiguation, which still hold. |

## Separate mechanisms — do not conflate

- [`TC_SETTLED_RX_WEDGE.md`](TC_SETTLED_RX_WEDGE.md) — **OPEN, HIGH.** A TideChart
  election beat arriving at a die whose election FSM has settled stalls that die's
  *entire* cross-die receive path. No fault is needed to trigger it; boot skew is
  enough. Structurally distinct from the write wedge above.

## Reading rule

A document in this directory states what was measured *on the day it was written*.
Where a later measurement overturned it, the top of the file says so. If a doc has
no such header, it has not been contradicted — it has also not necessarily been
re-confirmed.
