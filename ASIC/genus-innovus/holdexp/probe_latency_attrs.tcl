# Find a RELIABLE way to read back the -min source latency ccopt applied, so the
# production fix can DERIVE the mirrored -max instead of hardcoding numbers that
# change with every clock tree. Pure discovery: reads nothing, writes nothing.
source ../scripts/config.tcl
read_db ../baseline_2026-08-06/work/nanosoc_eth_chiplet_pads_cts
set_db timing_analysis_type ocv

puts "#### CLOCKS ####"
foreach c [get_db clocks] { puts "  [get_db $c .name]" }

set c [get_db clocks clk]
if {[llength $c] != 1} { set c [lindex [get_db clocks] 0] }
puts "#### probing object: [get_db $c .name] ####"

puts "#### attribute listing forms ####"
foreach form {.? .??} {
    if {![catch {set r [get_db $c $form]} e]} {
        puts "FORM $form OK, [llength $r] entries"
        foreach a $r { if {[string match -nocase *latency* $a]} { puts "   LATENCY-ATTR: $a" } }
    } else { puts "FORM $form ERR: $e" }
}

puts "#### candidate attribute names ####"
foreach a {source_latency latency source_latency_early_rise source_latency_late_rise
           source_latency_early_fall source_latency_late_fall
           source_latency_min_early_rise source_latency_max_early_rise
           clock_source_latency source_insertion_delay insertion_delay} {
    if {![catch {set v [get_db $c .$a]} e]} { puts "  ATTR .$a = '$v'" }
}

puts "#### report_clock_timing ####"
foreach t {latency summary skew} {
    if {![catch {redirect ../reports/probe_clk_$t.rpt { report_clock_timing -type $t }} e]} {
        puts "  report_clock_timing -type $t OK"
    } else { puts "  report_clock_timing -type $t ERR: $e" }
}

puts "#### get_clock_info / all_clocks style ####"
foreach cmd {"get_clock_info" "report_clocks" "report_clock_latency"} {
    if {[llength [info commands $cmd]]} { puts "  command EXISTS: $cmd" } \
    else { puts "  command absent: $cmd" }
}
puts "#### PROBE DONE ####"
exit
