## Snapshot the POST-CTS database before routing touches it.
##
## Every stage script ends with `write_db $block_name` — the same name — so each
## stage overwrites the last and only the final post-route DB survives. That
## makes any experiment on routing or hold repair cost a full re-run from
## placement (~5h) instead of resuming (~1h). This file is sourced by
## 4_pnr_route.tcl immediately after its `read_db`, so the design here is
## exactly the post-CTS state. 109MB per snapshot; disk is not the constraint.
##
##   resume from here:  cd work && innovus -stylus
##                      source ../scripts/config.tcl ; read_db ${block_name}_cts
write_db ${block_name}_cts

### Clock Net Spacing — REMOVED, it never did anything.
#
# The line was:
#     set_route_attributes -nets clk -preferred_extra_space_tracks 2
# and every run answered:
#     #WARNING (NRDB-537) Cannot find net clk
# because the top-level port is `CLK`, uppercase. Lowercase `clk` exists only
# inside sub-modules. So no clock net has ever received the intended 2 tracks.
#
# Fixing the NAME would not fix the intent: `CLK` is the pad's port net, ONE of
# 20 clock nets. The other 19 belong to the tree CTS built, and this command
# runs after CTS, too late to influence how they were routed.
#
# The router names what is actually in control:
#     Unshielded; Preferred extra space: 1; Mask Constraint: 0; Source: cts_route_type.
# i.e. ccopt's own auto-created route types give 0-1 tracks, and
# `[NR-eGR] There are 20 clock nets ( 0 with NDR )` confirms no non-default rule
# exists anywhere. The lever is cts_route_type, set in cts_setup.tcl BEFORE CTS:
#     create_route_type -name clk_rt ...        # verify options with -help
#     set_db cts_route_type_leaf/top/trunk clk_rt
# That changes clock tree ROUTING and therefore timing, so it is a change to
# evaluate on its own — see the same argument for cts_buffer_cells in
# cts_setup.tcl. Not yet done.

### Multi Cut Via Effort — OVERRIDABLE, because it is the prime suspect for the
### VIA3 signoff class and has never been swept.
#
# `medium` was the only setting in this file carrying no reason for its value.
# Everything else here is argued or was deleted with an explanation; this was a
# bare assignment, so treat it as an unexamined default rather than a decision.
#
# WHAT IT IS SUSPECTED OF. Calibre on the shipping stream reports 23
# VIA3.R.2__VIA3.R.3 results, 17 of them design-owned, plus 2 VIA3.R.4:M4. Both
# rules require a REDUNDANT VIA3 once the connecting metal passes a width
# threshold -- read the rule text and the threshold off the deck on your own
# install; they are the foundry's and are deliberately not reproduced here.
#
# Single-cut vias on wide metal is precisely what multi-cut via effort governs:
# `high` makes NanoRoute work harder to place the second cut where the rule
# demands one. See docs/asic/DRC_WAIVER_INVENTORY.md § 5 item 2.
#
# THE DEFAULT IS DELIBERATELY UNCHANGED. Raising it is a QoR change — more cuts
# means more area pressure and a different detail-route result — and no route
# has been run at `high` on this design, so shipping it as the default would be
# swapping a measured 19 results for an unmeasured everything-else. Sweep it
# first, exactly as power_plan.tcl's M5 offset was swept before anyone touched
# the shipped value:
#
#     EVR_MULTICUT_VIA_EFFORT=high  make ...      (route stage)
#
# and read VIA3.R.2__VIA3.R.3 out of the next Calibre summary with
# `scripts/ci/drc_census.py <rundir>`. The read-back at 4b:775-779 already
# prints the value each run, so a setting that does not take is visible rather
# than silent — which is the failure mode this whole flow is written against.
opt EVR_MULTICUT_VIA_EFFORT medium
set_db route_design_detail_use_multi_cut_via_effort $EVR_MULTICUT_VIA_EFFORT

### Timing Driven Route
set_db route_design_with_timing_driven 1 

### SI Driven Route 
set_db route_design_with_si_driven 1 

### Timing Analysis Type
## MOVED to cts_setup.tcl, where it now runs BEFORE ccopt. Setting it here was
## the hold bug: ccopt had already written its source-latency back with min/max
## unseparated, emitting -min only for the hold view, and turning OCV on at THIS
## point split min from max with nothing on the max side. The capture clock of
## every hold check then used 0 instead of -1.076, costing the design 96,545
## fictional violating paths and ~37,000 hold buffers. Full diagnosis, evidence
## and the rejected alternatives are in cts_setup.tcl.
##
## Re-setting it here is harmless (same value) but pointless, so it is left out
## rather than duplicated — if you are looking for where OCV is enabled, it is
## cts_setup.tcl.

# filler.tcl deliberately NOT sourced here. This file is sourced by
# 4_pnr_route.tcl BEFORE route_design, so sourcing filler here inserted filler
# cells before there was any routing: add_fillers -check_drc -fix_drc then had
# nothing to check against ("Found no DRC violations to fix"), the ANTENNA
# diodes went in before any antenna existed, and post-route hold repair had to
# carve its ~66,000 buffers back out of filled rows. Filler now runs from
# place_bondpads.tcl, after opt_design -post_route -hold.