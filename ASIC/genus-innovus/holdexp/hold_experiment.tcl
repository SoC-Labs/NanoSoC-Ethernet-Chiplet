# Does supplying the missing -max source latency fix the hold failure?
#
# Runs on the PREVIOUS run's post-CTS snapshot (baseline_2026-08-06), so it does
# not touch the flow currently executing in work/. Reproduces what
# route_setup.tcl does (enable OCV), measures hold, applies the candidate fix,
# measures again. ~30 min instead of a 5-hour re-run.
#
# Predicts: hold WNS moves from about -1.1 to about -0.1 if the missing -max
# source latency really is the cause. If it barely moves, the theory is dead.
source ../scripts/config.tcl

set SNAP ../baseline_2026-08-06/work/nanosoc_eth_chiplet_pads_cts
read_db $SNAP

# route_setup.tcl:27 — this is what activates the min/max split post-CTS.
set_db timing_analysis_type ocv

proc holdslack {tag} {
    set f "../reports/holdexp_${tag}.rpt"
    if {[catch {report_timing -early -max_paths 1 > $f} e]} {
        puts "HOLDEXP $tag: report FAILED: $e" ; return
    }
    set fh [open $f]
    set slack "?" ; set cap "?" ; set lau "?"
    while {[gets $fh line] >= 0} {
        if {[regexp {Slack Time\s+([-0-9.]+)} $line -> s]} { set slack $s }
    }
    close $fh
    puts "HOLDEXP $tag: slack=$slack   (full report $f)"
}

puts "#### BEFORE: OCV on, latency as ccopt left it ####"
holdslack before

puts "#### APPLYING CANDIDATE FIX: mirror -min source latency onto -max ####"
# Values are exactly what ccopt wrote for the -min side (log: pnr_run_core70).
# Hardcoded ON PURPOSE — this is a one-shot experiment, not the production fix.
foreach {edge tr val} {
    early rise -1.07637   late rise -1.07637
    early fall -1.10823   late fall -1.10823
} {
    if {[catch {set_clock_latency -source -$edge -max -$tr $val [get_pins CLK]} e]} {
        puts "HOLDEXP: set_clock_latency -$edge -max -$tr FAILED: $e"
    } else {
        puts "HOLDEXP: applied -source -$edge -max -$tr $val"
    }
}

puts "#### AFTER ####"
holdslack after

puts "#### HOLDEXP DONE ####"
exit
