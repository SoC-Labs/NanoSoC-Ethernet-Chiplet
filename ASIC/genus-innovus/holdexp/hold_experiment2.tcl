# v2. Two fixes over v1:
#   - set_interactive_constraint_modes: without it, ANY SDC command applied
#     interactively fails with TCLCMD-1048 "constraints are specified but no
#     constraint mode is enabled interactively". v1 silently failed all four.
#   - target [get_clocks clk], not [get_pins CLK] (TCLCMD-917: no such pin).
#
# v1's BEFORE report already proved the mechanism arithmetically:
#     Src Latency: capture 0.000, launch -1.108  ->  Slack -1.086
#   symmetric capture would give required 5.452 vs arrival 5.474 -> +0.022
# This run confirms it in the timer, including any OCV/CRPR second-order effects
# that hand arithmetic would miss.
source ../scripts/config.tcl

read_db ../baseline_2026-08-06/work/nanosoc_eth_chiplet_pads_cts
set_db timing_analysis_type ocv

proc holdslack {tag} {
    set f "../reports/holdexp2_${tag}.rpt"
    catch {report_timing -early -max_paths 1 > $f}
    set slack "NOT-FOUND" ; set cap "?" ; set lau "?"
    if {[file exists $f]} {
        set fh [open $f]
        while {[gets $fh line] >= 0} {
            if {[regexp {Slack:=\s+([-0-9.]+)} $line -> s]}                { set slack $s }
            if {[regexp {Src Latency:\+\s+([-0-9.]+)\s+([-0-9.]+)} $line -> c l]} {
                set cap $c ; set lau $l
            }
        }
        close $fh
    }
    puts "HOLDEXP2 $tag: slack=$slack  src_latency capture=$cap launch=$lau"
}

puts "#### BEFORE ####"
holdslack before

puts "#### ENABLING INTERACTIVE CONSTRAINT MODE ####"
if {[catch {set_interactive_constraint_modes [all_constraint_modes -active]} e]} {
    puts "HOLDEXP2: set_interactive_constraint_modes FAILED: $e"
}

puts "#### APPLYING FIX: mirror -min source latency onto -max ####"
foreach {edge tr val} {
    early rise -1.07637
    late  rise -1.07637
    early fall -1.10823
    late  fall -1.10823
} {
    if {[catch {set_clock_latency -source -$edge -max -$tr $val [get_clocks clk]} e]} {
        puts "HOLDEXP2: FAILED -$edge -max -$tr : $e"
    } else {
        puts "HOLDEXP2: applied -source -$edge -max -$tr $val"
    }
}
catch {set_interactive_constraint_modes {}}

puts "#### AFTER ####"
holdslack after
puts "#### HOLDEXP2 DONE ####"
exit
