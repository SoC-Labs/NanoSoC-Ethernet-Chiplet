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

### Clock Net Spacing
set_route_attributes -nets clk -preferred_extra_space_tracks 2

### Multi Cut Via Effort 
set_db route_design_detail_use_multi_cut_via_effort medium

### Timing Driven Route
set_db route_design_with_timing_driven 1 

### SI Driven Route 
set_db route_design_with_si_driven 1 

### Timing Analysis Type 
set_db timing_analysis_type ocv

source ../scripts/filler.tcl