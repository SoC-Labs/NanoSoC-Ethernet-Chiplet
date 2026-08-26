#-----------------------------------------------------------------------------
# dump_io_file.tcl - recover the as-built padring from an EXISTING routed DB
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
#
# Copyright 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# This is the RETROFIT path. New runs get these files for free from
# ASIC/eth-chiplet/hooks/post_route.tcl, which the toolkit fires straight after
# write_stream -- no extra licence, no second DB read. Use this script only to
# recover the padring from a run that finished BEFORE that hook existed, or from
# an archived database.
#
# It is a thin wrapper on purpose: the export logic lives in the hook and is
# sourced from there, so there is exactly one implementation of it in the tree.
#
#   IO_DB=<repo>/ASIC/eth-chiplet/build/<run>/work/<block>_routed \
#   IO_OUT=<dir> \
#   innovus -stylus -no_gui -files ASIC/genus-innovus/scripts/dump_io_file.tcl \
#           < /dev/null
#
# The stdin redirect matters: on any error Innovus drops to its prompt and holds
# a licence until it is killed.
#
# Verify whatever it produces against the stream it claims to describe:
#   python3 scripts/xcheck_io_vs_gds.py <stream.gds> <...as_built_pads.csv>
#-----------------------------------------------------------------------------

set db_path ""
if {[info exists ::env(IO_DB)]} { set db_path $::env(IO_DB) }
if {$db_path eq "" || ![file isdirectory $db_path]} {
    puts "IO_DUMP_FAIL reason=IO_DB-unset-or-missing value=$db_path"
    exit 1
}
set out_dir [pwd]
if {[info exists ::env(IO_OUT)] && [string length $::env(IO_OUT)]} {
    set out_dir $::env(IO_OUT)
}
file mkdir $out_dir

puts "IO_DUMP reading $db_path"
read_db $db_path
set block_name [get_db current_design .name]
puts "IO_DUMP design=$block_name"

# The hook expects the flow's helpers and $OUT_DIR in scope. Outside the flow
# they do not exist, so stand them up before sourcing it. try_step must keep
# the hook's contract -- catch, warn, carry on -- or a failed export here would
# look like a clean run.
if {[info commands say]  eq ""} { proc say  {args} { puts "IO_DUMP: [join $args { }]" } }
if {[info commands warn] eq ""} { proc warn {args} { puts "IO_DUMP_WARN: [join $args { }]" } }
if {[info commands try_step] eq ""} {
    proc try_step {label body} {
        if {[catch {uplevel 1 $body} msg]} { warn "'$label' skipped: $msg" ; return 0 }
        return 1
    }
}
set OUT_DIR $out_dir

source [file join [file dirname [info script]] .. .. eth-chiplet hooks post_route.tcl]

puts "IO_DUMP_DONE out=$out_dir"
exit
