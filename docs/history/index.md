# History — dated records and correspondence

**Nothing in this directory is current reference material.** Every file is either a
message sent to someone on a given date, or a record of what one campaign measured
on one night. They are kept because the measurements are real and the reasoning is
often still useful — but a claim here is only true as of its date, and several have
since been overturned.

If you want to know what is true *now*, go to [`../design/`](../design/),
[`../verification/`](../verification/), [`../asic/`](../asic/) or
[`../bringup/`](../bringup/). For the live die-to-die wedge picture, start at
[`../debug/`](../debug/) — it carries the supersession chain.

## Correspondence with the TideLink developer

Read a thread top to bottom; the later message usually retracts part of the earlier
one.

| Thread | Files, in order |
|---|---|
| AXI data-node recovery ("axirec") | [`REPLY_AXIREC_RECONCILE_2026_08_03.md`](REPLY_AXIREC_RECONCILE_2026_08_03.md) → [`DEV_MESSAGE_AXIREC_RECONCILE_2026_08_04.md`](DEV_MESSAGE_AXIREC_RECONCILE_2026_08_04.md) → [`REPLY_AXIREC_RECONCILE_2026_08_04.md`](REPLY_AXIREC_RECONCILE_2026_08_04.md). The 08-04 message supersedes an 08-03 one that is not in this repo. Related proposal: [`PROPOSAL_AUTO_ANCHOR_RTL_2026_08_04.md`](PROPOSAL_AUTO_ANCHOR_RTL_2026_08_04.md). |
| a2l ACK-pointer CDC self-latch | [`DEV_MESSAGE_A2L_SELFLATCH_SILICON_2026_08_09.md`](DEV_MESSAGE_A2L_SELFLATCH_SILICON_2026_08_09.md) → [`REPLY_TL027_A2L_ETHCHIPLET_2026_08_10.md`](REPLY_TL027_A2L_ETHCHIPLET_2026_08_10.md) |
| the D2D write wedge | [`DEV_MESSAGE_D2D_WEDGE_ROOT_CAUSE_CORRECTED_2026_08_11.md`](DEV_MESSAGE_D2D_WEDGE_ROOT_CAUSE_CORRECTED_2026_08_11.md) → [`DEV_MESSAGE_D2D_WEDGE_ILA_CONFIRMED_2026_08_13.md`](DEV_MESSAGE_D2D_WEDGE_ILA_CONFIRMED_2026_08_13.md). Both are steps in the chain indexed at [`../debug/`](../debug/); neither is the current answer. |
| general silicon feedback | [`TIDELINK_SILICON_FEEDBACK.md`](TIDELINK_SILICON_FEEDBACK.md), [`DEV_MESSAGE_TIDELINK_RX_STALL_2026_08_10.md`](DEV_MESSAGE_TIDELINK_RX_STALL_2026_08_10.md), [`DEV_MESSAGE_TIDELINK_CI_FINDINGS_2026_08_06.md`](DEV_MESSAGE_TIDELINK_CI_FINDINGS_2026_08_06.md) |
| session consolidation | [`TIDELINK_D2D_SESSION_HANDBACK_2026-08-17.md`](TIDELINK_D2D_SESSION_HANDBACK_2026-08-17.md) |

## Bring-up campaign records

| File | What it records |
|---|---|
| [`I1_FCSM_BRINGUP_REGRESSION.md`](I1_FCSM_BRINGUP_REGRESSION.md) | 07-30: a recovery fix that broke link bring-up. **Resolved** — see the next row. |
| [`I1_RESOLVED_HANDOVER_2026_07_31.md`](I1_RESOLVED_HANDOVER_2026_07_31.md) | 07-31: two bring-up *sequencing* bugs, not timing. Link comes up cold with the recovery FCSM in place. |
| [`OVERNIGHT_WORKLOG.md`](OVERNIGHT_WORKLOG.md) | 07-27/28: first cross-die IPC mailbox pass; both inbound D2D targets proven. |
| [`OVERNIGHT_HW_CAMPAIGN_2026-08-05.md`](OVERNIGHT_HW_CAMPAIGN_2026-08-05.md) | 08-05/06: cross-die write half-closed, remainder root-caused. |
| [`COVERAGE_GATES_RUN_2026-08-06.md`](COVERAGE_GATES_RUN_2026-08-06.md) | 08-06: coverage gate campaign **deferred**, not run — the rig would not hold a POR. |
| [`HW_LOOP_RESULTS_2026-08-08.md`](HW_LOOP_RESULTS_2026-08-08.md) | 08-08: a bad-eye night. Every delivery-dependent test failed for link reasons, not logic ones. |
| [`SYSVAL_RUN_RESULTS_2026-08-08.md`](SYSVAL_RUN_RESULTS_2026-08-08.md) | 08-08: what the system-validation suite built, and its first silicon run. |
| [`VALIDATION_UNBLOCK_PLAN_2026-08-08.md`](VALIDATION_UNBLOCK_PLAN_2026-08-08.md) | 08-08: the blocker→tests map behind that campaign. |
| [`CAMPAIGN_THREE_UNLOCK_2026-08-09.md`](CAMPAIGN_THREE_UNLOCK_2026-08-09.md) | 08-09: index to the three-unlock FPGA campaign and its handovers. |

## A caution about hardware verdicts here

Several of these records were taken on a rig whose link margin varies night to
night. A test that failed on a bad-eye evening is not evidence of a logic defect,
and the campaign docs generally say which kind of night it was. Check that before
quoting a failure.
