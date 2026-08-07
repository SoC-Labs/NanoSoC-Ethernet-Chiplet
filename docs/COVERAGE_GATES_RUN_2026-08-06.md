# Coverage gates — run attempt 2026-08-06 (DEFERRED)

**Outcome: not run.** The `coverage/` gate campaign was attempted (after fixing the
`setup_link` OK-check bug documented in `OVERNIGHT_HW_CAMPAIGN_2026-08-05.md` §6). It was
blocked by the same rig instability that recurred all night: **die_a would not recover from
JTAG-POR** across two full setup attempts (~46 min of fruitless POR-ing), then recovered on a
later fresh POR + settle. The rig is too flaky tonight for a reliable unattended gate sweep.

## Why this is deferred, not abandoned

1. **Rig flakiness.** Both boards cycle stuck→recover on POR (die_b needed 2 PORs earlier;
   die_a stuck here, recovered later). An unattended gate sweep that POR-recovers between
   wedge-prone gates spends most of its time fighting the rig.
2. **Most gates are data-drop-blocked.** The write-dependent gates (`cov_mbox_doorbell_irq`,
   `cov_mbox_irq_source`, `cov_decerr_confine`, `cov_axinode_wedge_gate`, `cov_errinject_sweep`)
   exercise cross-die writes/mailbox — which drop until **Rank 1** lands (see
   `tidelink/docs/HANDOVER_RANK1_PEERWRITE_DATADROP_2026-08-06.md`). Running them now would just
   reconfirm the drop.
3. **TideChart election** (`cov_tidechart_election`) is BLOCKED regardless — needs a
   `DEVICE_CLASS` re-strap + rebuild.

## Recommendation: run the gates in the Rank 1 bench session

Run the full `coverage/` sweep **alongside the Rank 1 bench** — one rig cycle covers both, the
write-dependent gates become meaningful (writes land post-Rank-1), and an attended session can
nurse the flaky POR recovery. The data-drop-independent gates that would give first-time data
are: `cov_regplane_sweep` (APB register-plane), `cov_obs_health_gate`, `cov_perf_thresholds`,
`cov_ps_irq_observe`, `cov_auto_anchor_verify` (should PASS — anchor is validated).

**Recipe (proven this session):** deploy `RUN_AFI=0` (export `TIDELINK_HOME`), turnkey
bring-up until `reanchored=1` both dies, wait `0x21F4` done=1, then
`KR260_PASSWORD=… python3 coverage/cov_<gate>.py`. The campaign script
(`scratchpad/overnight_campaign.sh`, OK-check now fixed) automates it once the rig is stable.

Rig left clean: both boards up, all leases released.
