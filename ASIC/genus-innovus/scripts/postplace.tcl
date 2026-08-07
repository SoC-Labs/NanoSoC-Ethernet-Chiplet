### Post-placement: pre-CTS optimisation, tie-offs, delay calculation.
# Sourced from 2_pnr_setup.tcl:64, after place_design and after the
# `report_end_step 01_place` at line 62 - so the 01_place reports describe the
# state BEFORE anything here runs. That is why the opt below writes its own.

### Pre-CTS optimisation ------------------------------------------------------
# The flow had NO optimisation between place_design and ccopt_design. Innovus
# opt_design appears only as -post_cts (3_pnr_clock.tcl:33-34) and
# -post_route -hold (4_pnr_route.tcl:33). Measured consequence, from this
# design's own baselines (baseline_2026-08-07/reports/timing_summary_*.rep):
#
#     snapshot        SETUP WNS         TNS      FEP    max_tran FEP
#     00_pre_place     -126.815  -3,830,180   39,526          11,317
#     01_place         -185.650  -5,908,965   57,293         156,197
#     02_cts             +0.001           0        0               0
#
# Placement costs 59 ns of setup and multiplies DRV endpoints 13.8x, and
# nothing repairs any of it before CTS. ccopt_design cleans it up, which is why
# this went unnoticed - but preplace.tcl sets place_global_timing_effort high,
# so PLACEMENT ITSELF is being driven by that timing graph. At TNS -5.9e6 ns a
# real 10 ns path with 0.1 ns of slack is numerically invisible: timing-driven
# placement is nominally on and effectively disabled.
#
# The dominant term is one gate - timing_01_place_late.rep:36, an OR2D1 on the
# TEST distribution net at fanout 11,009, trans 0.692, delay 190.365 ns. The
# same gate is 123.870 ns at pre-place, so spreading the cells across the
# 1190x1590 core added 66.5 ns to it. Nothing buffers it until CTS.
#
# Repairing DRV here also does it at 80.67% density rather than post-route at
# 92.17%, where recovery is documented to fail on max local density
# (docs/tapeout/16-open-defects.md, 19-timing-audit.md).
#
# NOT YET MEASURED ON THIS DESIGN. Expect +20-45 min at this stage. A/B it:
#     make pnr_place PRE_CTS_OPT=0     # previous behaviour
# Watch qor_01b_place_opt.rep against qor_01_place.rep (whose WNS/TNS/DRV
# columns are blank today precisely because no opt command ran to fill them).
set PRE_CTS_OPT [expr {[info exists ::env(PRE_CTS_OPT)] ? $::env(PRE_CTS_OPT) : 1}]

if {$PRE_CTS_OPT} {
    opt_design -pre_cts
    report_end_step 01b_place_opt $REPORT_DIR
} else {
    puts "postplace: PRE_CTS_OPT=0 - skipping opt_design -pre_cts"
}

### Tie-off cells -------------------------------------------------------------
# After the opt above, so cells it adds get tied off too.
set_db add_tieoffs_max_fanout 10
add_tieoffs -lib_cell {TIEL TIEH} -prefix LTIE

### Delay Calculation ---------------------------------------------------------
# NOTE: nothing consumes work/design.sdf. It is ~494 MB, written at placement
# against an IDEAL clock network, and sits next to the real post-route SDF
# (outputs/${block_name}_pnr.sdf, 4_pnr_route.tcl:71). Kept for now because it
# is pre-existing behaviour; a candidate for deletion once confirmed unused.
write_sdf design.sdf -ideal_clock_network
