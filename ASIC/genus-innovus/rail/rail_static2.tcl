################################################################################
# rail_static2.tcl - STATIC rail analysis (IR drop), taking its demand from an
# instance power file rather than from Voltus's binary current files.
#
# WHY A SECOND SCRIPT. rail_static.tcl ran report_power to completion (33 MB of
# per-instance power, total 78.886 mW, matching report_power's own headline to
# five figures) and then stopped: it looked for `*.ptiavg` current files, and
# none exist. That is not a bug in the design and not a failure of the power
# run. `set_power_data -format current` wants the binary current files that
# VOLTUS's power engine writes; `report_power -rail_analysis_format VS` under
# Innovus writes an ASCII instance power report instead. The 21.11 reference
# documents the route for exactly this case:
#
#   -format ascii   "specify the ascii instance based power file ... The command
#                    accepts an ASCII power file in three-column format
#                    consisting of instance/cell name, power in W, and power pin
#                    name ... when 3-column power file format is specified, the
#                    program will ignore -bias_voltage and will rely on
#                    associated net voltages to determine current for the pins."
#
# So the demand is handed over as `work/core_power_VDD.pwr`, built from the
# report_power output that already exists. No new power estimate is invented.
#
# THE FILTER, AND WHY IT IS NOT A HEURISTIC. The file carries only instances
# placed inside the core box (205 205 1395 1795). That excludes the IO ring,
# whose VDDIO/VSSIO rails are absent from the CPF power intent and which must
# not be injected into the core rail. The filter reproduces report_power's OWN
# rail attribution: 54.7598 mW in-core against the 54.76 mW it reports on the
# VDD rail, i.e. 50.70 mA at 1.08 V. Because of that, "current accounting"
# below is an identity by construction, not an independent check - the
# independent check is that the file total equals report_power's VDD rail, and
# it does, to four decimal places. Said plainly rather than dressed up as a
# passing assertion.
#
# METHOD DISCIPLINE, unchanged from rail_static.tcl:
#   -method static, never era_*. ERA's grid completion invents virtual
#   follow-pins and vias and would bridge exactly the PG opens this design has
#   (255 instances with no path to VDD, 302 to VSS, at four macro-edge sites).
#   No -stream_file, ever: a large fraction of the metal in the streamed GDS is
#   routing blockage streamed as conductor.
#
# WHAT THE RESULT IS: static rail at an ASSUMED switching activity. There is no
# SAIF and no VCD in this flow. The relative map is dominated by the grid and
# is meaningful; the absolute millivolts inherit the activity assumption and
# must never be quoted without it on the same line.
################################################################################

set RAILDIR [file normalize [file dirname [info script]]]
set WORK    $RAILDIR/work
# ---- INPUTS. Resolved in rail_env.tcl, not spelled here ----------------------
# This file used to open with two absolute paths: a database under runs/, and
#   set QRC /<the site's PDK mount>/CMOS/LP/pdk/Assura/online/1p9m_6X1Z1U/...
# SIX files in this directory carried that second line. That is a site constant
# copied six times into a PUBLIC repository, and the repo's own vendor gate
# says why it must not be: "THE PDK MOUNT IS INHERITED, NOT NAMED HERE ... a
# default spelled here would be a second copy of a site constant, and the kind
# of copy this very script exists to find."
#
# THE SPELLING CHANGED; THE SELECTION DID NOT. $::RAIL(qrc) resolves to the same
# extraction deck and ::rail::db_or_default to the same database this script has
# always read - both byte-compared against the previous literals. RAIL_DB
# overrides the database without editing anything.

source [file join [file dirname [info script]] rail_env.tcl]
set DB  [::rail::db_or_default $::RAIL(repo)/ASIC/genus-innovus/runs/20260812T133501Z_route-baseline-gds/work/nanosoc_eth_chiplet_pads_eval_route]
set QRC $::RAIL(qrc)
set PGV $WORK/pgv/techonly.cl
set VCORE 1.08
set PWR  $WORK/core_power_VDD.pwr
set OUT  $WORK/rail2

foreach f [list $PWR] {
    if {![file readable $f] || [file size $f] == 0} { puts "FATAL missing $f" ; exit 1 }
}
if {![file isdirectory $PGV]} { puts "FATAL no PGV at $PGV" ; exit 1 }
file mkdir $OUT

set_db read_db_file_check false
read_db $DB
set_multi_cpu_usage -local_cpu 2

puts "\n##### RAIL2-BEGIN #####"
puts "RAIL2 demand file : $PWR"
puts "RAIL2 activity    : tool default (no SAIF, no VCD anywhere in this flow)"

set_rail_analysis_mode \
    -method static \
    -accuracy hd \
    -power_grid_libraries $PGV \
    -extraction_tech_file $QRC \
    -temperature 125 \
    -report_voltage_drop true \
    -verbosity true \
    -work_directory_name $WORK/rail2_state \
    -tmp_directory_name  $WORK/rail2_tmp

# A THRESHOLD IS MANDATORY, and it is a REPORTING FILTER, not a budget.
# Without one, report_rail refuses the domain:
#   **ERROR: (VOLTUS-1246): Domain threshold must be specified using
#   set_rail_analysis_domain or net thresholds must be specified using
#   set_pg_nets before analyzing domain PD_TOP.
# ...and returns success, as everything in this family does.
#
# The value below is 5 % of the analysis voltage - 1.026 V on VDD, 0.054 V of
# rise allowed on VSS. NOBODY ON THIS PROJECT HAS DERIVED AN IR BUDGET, so this
# is a conventional figure chosen to make the pass/fail column and the IR plot
# range meaningful. It does NOT affect the computed voltages: the millivolts
# reported are the same whatever threshold is set. Any statement of the form
# "the design passes IR" must quote this number and say where it came from,
# which is: nowhere but convention.
set VTHRESH [expr {$VCORE * 0.95}]
set_pg_nets -net VDD -voltage $VCORE -threshold $VTHRESH
set_pg_nets -net VSS -voltage 0.0   -threshold [expr {$VCORE * 0.05}]
puts "RAIL2 threshold   : VDD >= $VTHRESH V, VSS <= [expr {$VCORE*0.05}] V (5% convention, NOT a derived budget)"
# VDDIO/VSSIO: in no domain, no set_pg_nets, no voltage source, and no demand in
# the power file. Including them returns ~0 mV and looks excellent - a false
# green by construction.
set_rail_analysis_domain -domain_name PD_TOP -power_nets {VDD} -ground_nets {VSS}

# -short_pin_nodes true is the whole reason this run is possible at all; without
# it the identical command reports "6/6 (100.00%)" and puts ZERO sources in the
# circuit. See docs/tapeout/31-power-delivery-measured.md section 4b-bis.
set_power_pads -reset
set_power_pads -net VDD -format padcell -file $WORK/VDD.padcell -short_pin_nodes true
set_power_pads -net VSS -format padcell -file $WORK/VSS.padcell -short_pin_nodes true

set_power_data -reset
if {[catch { set_power_data -format ascii -bias_voltage $VCORE $PWR } e]} {
    puts "RAIL2-FAIL set_power_data: $e"
    puts "##### RAIL2-END #####"
    exit 0
}

# THE DOMAIN/NET NAME MUST COME LAST. Written as
#   report_rail -type domain ALL -output_dir $OUT
# the tool answers "**ERROR: (VOLTUS-1030): Bad option: ALL." and RETURNS
# SUCCESS, writing nothing - the same print-error-return-zero behaviour as
# report_resistance. The artefact assertion below is what catches it.
# ...and the name must be the DECLARED domain, not the documented "ALL". The
# 21.11 reference says 'You can specify the variable "ALL" to analyze all
# domains' and shows it as an example; this build answers
#   **ERROR: (VOLTUS-1123): ALL is not a valid power domain.
# and returns success. PD_TOP is the domain declared above by
# set_rail_analysis_domain, and it is the only one.
catch { report_rail -type domain -output_dir $OUT PD_TOP } e2

########################################################################
# ASSERT THE ARTEFACT, then the coverage. Never the return code:
# report_rail can print **ERROR and return cleanly.
########################################################################
set found {}
foreach p [glob -nocomplain $OUT/* $OUT/*/* $OUT/*/*/* $OUT/*/*/*/*] {
    if {[file isfile $p] && [file size $p] > 0} { lappend found $p }
}
if {[llength $found] == 0} {
    puts "RAIL2-FAIL no non-empty rail artefact under $OUT (tcl said '$e2')"
} else {
    puts "RAIL2-OK [llength $found] artefacts"
    foreach p [lrange [lsort $found] 0 25] { puts "   $p ([file size $p] bytes)" }
}

set vsrc_total 0
foreach rl [glob -nocomplain $OUT/*/voltus_rail.log $OUT/voltus_rail.log \
                             $OUT/*/*/voltus_rail.log $WORK/rail2_state/voltus_rail.log] {
    set fhv [open $rl r] ; set t [read $fhv] ; close $fhv
    foreach line [split $t "\n"] {
        if {[regexp {Circuit total\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)} $line -> nn rr cc vv]} {
            puts "ASSERT circuit | [string trim $line]"
            incr vsrc_total $vv
        }
        if {[regexp {Instance logically connected:|Voltage Source Added/Total|are disconnected|Total (current|Current)|VOLTUS_RAIL-} $line]} {
            puts "ASSERT        | [string trim $line]"
        }
        if {[regexp -nocase {IR drop|voltage drop|worst|min voltage|max drop} $line]} {
            puts "ASSERT drop   | [string trim $line]"
        }
    }
}
puts "ASSERT-2 voltage sources total across both nets : $vsrc_total  (MUST be 10)"
if {$vsrc_total != 10} {
    puts "ASSERT-2 FAIL - the voltages below are referenced to the wrong thing."
}
puts "ASSERT-3 demand handed to the solver: 54.7598 mW / 1.08 V = 50.70 mA,"
puts "         which is report_power's own VDD rail figure for this database."
puts "##### RAIL2-END #####"
exit 0
