#-----------------------------------------------------------------------------
# check_conn_uncapped.tcl -- re-run connectivity checks with the caps OFF.
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access
# license. Copyright (C) 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# WHY THIS EXISTS. check_connectivity has its OWN error/warning limits, separate
# from `set_message -no_limit` (which config.tcl already sets, and which does
# NOT cover it). The default is 1000, and on this design the check hits it:
#
#     run.log:45459  Error Limit = 1000; Warning Limit = 50
#     run.log:45470  **WARN: (IMPVFC-3): Verify Connectivity stopped:
#                    Number of errors exceeds the limit 1000
#     run.log:45475  337 Problem(s) (IMPVFC-200)
#
# So 337 is a LOWER BOUND from an aborted check, not a total -- and the run that
# produced the tapeout stream never finished verifying its own connectivity.
# The uncapped call exists (4b_pnr_route_eval.tcl, EVR_UNCAP_CHECKS=1, limit
# 200000) but only on the eval path; the production route stage goes through
# ../asic-flows/Cadence/4_pnr_route.tcl:48, which calls it bare. asic-flows is a
# shared submodule, so the fix lives here instead.
#
# READ-ONLY on the database: read_db only, never write_db. Safe to run against a
# tapeout DB without perturbing it.
#
# Usage (all paths via env, no site paths in this file):
#     CONN_DB=<routed db dir> CONN_REPORT_DIR=<dir> [CONN_LIMIT=200000] \
#       innovus -stylus -files scripts/check_conn_uncapped.tcl < /dev/null
#-----------------------------------------------------------------------------

proc cc_say {msg} { puts "INFO: \[check_conn\] $msg" }
proc cc_die {msg} { puts "FAIL: \[check_conn\] $msg" ; exit 1 }

foreach {var name} {CONN_DB db CONN_REPORT_DIR report_dir} {
    if {![info exists ::env($var)] || $::env($var) eq ""} { cc_die "set $var" }
    set $name $::env($var)
}
set limit [expr {[info exists ::env(CONN_LIMIT)] ? $::env(CONN_LIMIT) : 200000}]

if {![file isdirectory $db]} { cc_die "no database at $db" }
file mkdir $report_dir

cc_say "database : $db  (read-only; no write_db is issued)"
cc_say "limit    : $limit  (default check_connectivity limit is 1000)"

read_db $db
set block [get_db current_design .name]
cc_say "design   : $block"

# -error/-warning raise the check's own caps. Without both, the run still stops
# early and the totals below are lower bounds rather than counts.
set rep $report_dir/${block}_conn_uncapped.rep
check_connectivity -error $limit -warning $limit -out_file $rep

# Report the totals back out of the log the tool just wrote, so the verdict is
# derived from the artefact rather than from whatever scrolled past.
if {![file exists $rep]} { cc_die "check_connectivity produced no $rep" }
cc_say "report   : $rep"
cc_say "done. Compare against the capped run before quoting any count."
exit 0
