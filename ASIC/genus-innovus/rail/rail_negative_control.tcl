################################################################################
# rail_negative_control.tcl - a DELIBERATELY BROKEN rail solve, so that the gate
# can be shown rejecting a real run and not only a doctored file.
#
# WHY THIS EXISTS AS A SEPARATE SCRIPT. rail_gate.py is already mutation-tested
# two ways: a 22-case battery over synthetic censuses, and ci/fixtures/ir-drop/,
# whose must-fail cases are cut down from real artefacts. Both of those feed the
# gate FILES. Neither shows that a genuinely broken TOOL RUN - one where Voltus
# itself completed, wrote a full artefact set and reported success - is caught.
# That is the failure this project actually had: a solve with zero voltage
# sources in the circuit that printed "Voltage Source Added/Total: 6/6
# (100.00%)" and was believed for a week.
#
# WHAT IS BROKEN, AND ONLY THIS. The two set_power_pads calls omit
# `-short_pin_nodes true`. Nothing else differs from rail_run.tcl: same
# database, same PGV, same demand file, same method, same threshold. The option
# defaults to FALSE, and at the default a techonly PGV gives a pad cell no
# internal nodes for a source to bind to - so the circuit ends up with NO
# voltage sources while every message about pads still reads like success.
#
# WHY THE FAULT IS NOT A KNOB IN rail_run.tcl. A production stage that can be
# told to produce a wrong answer is one environment variable away from producing
# one by accident, and the accident would look exactly like a passing run. The
# fault lives in its own file, writes to its own tag, and is never on the path
# `make rail` takes.
#
# EXPECTED RESULT: the run completes, Voltus reports success, artefacts are
# written - and rail_gate.py returns FAIL_HARD on vsrc.count. If it ever returns
# PASS, the gate is not a gate.
################################################################################

source [file join [file dirname [info script]] rail_env.tcl]
::rail::require_db

set OUT    $::RAIL(out)
set CENSUS $OUT/census.txt
set PGV    $OUT/pgv/techonly.cl
set PWR    $OUT/core_power_VDD.pwr

# This script does not build a PGV or run report_power: it is a control for the
# SOLVE, so it reuses the real run's inputs unchanged. Anything else would vary
# two things at once and prove nothing about either.
foreach f [list $PWR] {
    if {![file readable $f] || [file size $f] == 0} {
        puts "NEGCTL-FATAL missing $f - link it from the real run's output first"
        exit 1
    }
}
if {![file isdirectory $PGV]} { puts "NEGCTL-FATAL no PGV at $PGV" ; exit 1 }

set fcen [open $CENSUS w]
proc cen {k v} { global fcen ; puts $fcen "$k=$v" ; flush $fcen ; puts "CENSUS $k=$v" }

::rail::banner
puts "\n##### NEGCTL-BEGIN #####"
puts "NEGCTL this run is DELIBERATELY BROKEN: -short_pin_nodes is omitted."

cen stage.script      [file tail [info script]]
cen stage.negative_control true
cen stage.fault       "set_power_pads -format padcell without -short_pin_nodes true (option default is FALSE)"
cen db.path           $::RAIL(db)
cen method.rail       static
cen method.era        false
cen method.stream_file none
cen method.pgv_cell_type techonly
cen method.accuracy   hd
cen method.activity   assumed_tool_default_no_saif_no_vcd
cen method.package_model none

set_db read_db_file_check false
read_db $::RAIL(db)
set_multi_cpu_usage -local_cpu $::RAIL(cpu)
cen design.name      [get_db current_design .name]
cen db.insts_total   [llength [get_db insts]]

set vdd_pads [get_db insts -if ".base_cell.name == $::RAIL(vdd_pad_master)"]
set vss_pads [get_db insts -if ".base_cell.name == $::RAIL(vss_pad_master)"]
cen pads.vdd_count   [llength $vdd_pads]
cen pads.vss_count   [llength $vss_pads]
cen pads.expect_vsrc [expr {[llength $vdd_pads] + [llength $vss_pads]}]

# Copy the demand accounting straight out of the real run's census, so the gate
# judges this control on the ONE thing that differs.
set src $::RAIL(work)/[::rail::opt_env RAIL_REF_TAG fp1505]/census.txt
if {[file readable $src]} {
    set fh [open $src r]
    foreach line [split [read $fh] "\n"] {
        if {[regexp {^(power\.|demand\.|coverage\.|inst_xy)} $line]} { puts $fcen $line }
    }
    close $fh
    flush $fcen
}

set RESULTS $OUT/results
set_rail_analysis_mode \
    -method static -accuracy hd \
    -power_grid_libraries $PGV \
    -extraction_tech_file $::RAIL(qrc) \
    -temperature $::RAIL(temp) \
    -report_voltage_drop true -verbosity true \
    -work_directory_name $OUT/state -tmp_directory_name $OUT/tmp
set VTH_LO [expr {$::RAIL(vcore) * (1.0 - $::RAIL(vthresh_frac))}]
set_pg_nets -net VDD -voltage $::RAIL(vcore) -threshold $VTH_LO
set_pg_nets -net VSS -voltage 0.0 -threshold [expr {$::RAIL(vcore) * $::RAIL(vthresh_frac)}]
set_rail_analysis_domain -domain_name PD_TOP -power_nets {VDD} -ground_nets {VSS}

set fh [open $OUT/VDD.padcell w] ; puts $fh $::RAIL(vdd_pad_master) ; close $fh
set fh [open $OUT/VSS.padcell w] ; puts $fh $::RAIL(vss_pad_master) ; close $fh
set_power_pads -reset
# ---- THE FAULT. `-short_pin_nodes true` is missing from both lines. ----------
set_power_pads -net VDD -format padcell -file $OUT/VDD.padcell
set_power_pads -net VSS -format padcell -file $OUT/VSS.padcell
# -----------------------------------------------------------------------------

set_power_data -reset
catch { set_power_data -format ascii -bias_voltage $::RAIL(vcore) $PWR } e1
catch { report_rail -type domain -output_dir $RESULTS PD_TOP } e2

set found {}
foreach p [glob -nocomplain $RESULTS/* $RESULTS/*/* $RESULTS/*/*/* $RESULTS/*/*/*/*] {
    if {[file isfile $p] && [file size $p] > 0} { lappend found $p }
}
cen artefacts.count [llength $found]
foreach k {iv_combined main_vdd main_vss} { set A($k) "" }
foreach p $found {
    set t [file tail $p]
    if {[string match "VDD_VSS*.iv" $t]} { set A(iv_combined) $p }
    if {$t eq "VDD.main.rpt"}            { set A(main_vdd) $p }
    if {$t eq "VSS.main.rpt"}            { set A(main_vss) $p }
}
foreach k [lsort [array names A]] { cen artefact.$k $A($k) }

set vsrc_total 0
foreach rl [glob -nocomplain $RESULTS/*/voltus_rail.log $RESULTS/voltus_rail.log \
                             $OUT/state/voltus_rail.log] {
    set fhv [open $rl r] ; set t [read $fhv] ; close $fhv
    foreach line [split $t "\n"] {
        if {[regexp {Circuit total\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)} $line -> nn rr cc vv]} {
            puts "NEGCTL circuit | [string trim $line]"
            incr vsrc_total $vv
        }
        if {[regexp {Voltage Source Added/Total} $line]} {
            puts "NEGCTL claim   | [string trim $line]   <- printed on runs with NONE"
        }
    }
}
cen solve.voltage_sources $vsrc_total
cen power.configured_voltage $::RAIL(vcore)
cen result.completed true
close $fcen
puts "\nNEGCTL voltage sources in circuit: $vsrc_total (the real run has [llength [concat $vdd_pads $vss_pads]])"
puts "NEGCTL now run rail_gate.py against $CENSUS. It MUST return FAIL_HARD."
puts "##### NEGCTL-END #####"
exit 0
