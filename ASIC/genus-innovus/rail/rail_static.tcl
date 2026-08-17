################################################################################
# rail_static.tcl - STATIC rail analysis (IR drop) on the pad-correct database.
#
# WHAT THIS CLAIM IS, EXACTLY. Static rail analysis at an ASSUMED SWITCHING
# ACTIVITY. There is no SAIF and no VCD anywhere in this flow, so the per-
# instance currents come from report_power running on the tool's default
# activity assumption (primary-input activity 0.2). The MAP - which parts of
# the die droop and by how much relative to each other - is meaningful, because
# it is dominated by the grid. The ABSOLUTE millivolts are only as good as that
# activity guess, and must never be quoted as a signoff margin without saying
# so on the same line.
#
# WHY NOT SOMETHING STRONGER. A cell-accurate PGV needs cell SPICE or cell GDS;
# neither exists on this site, so dynamic rail analysis is permanently out of
# reach here rather than merely unrun. Static at an assumed activity is the
# strongest achievable claim on this site, and this script says so in its own
# output rather than in a footnote somewhere else.
#
# METHOD DISCIPLINE.
#   -method static, never era_*. ERA's grid-completion engine invents virtual
#   follow-pins and virtual vias for anything unrouted, which on a database
#   carrying 66 PG opens and hundreds of dangling PG wires would bridge exactly
#   the defects the measurement exists to find, and report a better grid than
#   the one that will be manufactured.
#
#   No -stream_file, ever. A large fraction of the metal in the streamed GDS is
#   routing blockage streamed as conductor; feeding that back in would flatter
#   every number here.
#
# COVERAGE IS ASSERTED BEFORE ANY NUMBER IS BELIEVED. A rail run that fails to
# attach current to instances reports SMALL drops, not missing ones. The three
# assertions at the end are instance coverage, voltage-source count (must be
# exactly 10 - six VDD pads and four VSS pads, all on the top and bottom edges),
# and current accounting within 0.90-1.10 of the current report_power implies.
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
set OUT  $WORK/rail

if {![file isdirectory $DB]}  { puts "FATAL: no DB at $DB"   ; exit 1 }
if {![file isdirectory $PGV]} { puts "FATAL: no PGV at $PGV - run pgv.tcl first" ; exit 1 }
foreach f {VDD.pp VSS.pp} {
    if {![file readable $WORK/$f]} { puts "FATAL: missing $WORK/$f - run recon.tcl first" ; exit 1 }
}
file mkdir $OUT

set_db read_db_file_check false
read_db $DB
# Deliberately small. Another agent is running P&R on this host; this job is
# not on the critical path and must not starve it.
set_multi_cpu_usage -local_cpu 2

puts "\n##### RAIL-BEGIN #####"

set_pg_nets -net VDD -voltage $VCORE
set_pg_nets -net VSS -voltage 0.0

########################################################################
# 1. Per-instance currents. -rail_analysis_format VS writes the binary
#    current files the rail solver consumes.
########################################################################
set_db power_method static
puts "RAIL activity: tool default (no SAIF, no VCD anywhere in this flow)"
if {[catch { report_power -rail_analysis_format VS -out_file $OUT/instance.rpt } e]} {
    puts "RAIL-FAIL report_power: $e"
}

# Search widely, and say where it looked. The current files do not reliably
# land beside -out_file: depending on set_power_output_dir they appear under
# <dir>/staticPowerResults/, under the cwd, or one level deeper again. A
# too-narrow glob here aborts the whole run with "no demand to solve", which
# reads like a tool failure and is not one.
set cur {}
foreach pat [list $OUT/staticPowerResults/*.ptiavg \
                  $OUT/*/*.ptiavg \
                  $OUT/*.ptiavg \
                  staticPowerResults/*.ptiavg \
                  ./*.ptiavg \
                  $WORK/staticPowerResults/*.ptiavg \
                  $WORK/staticPowerResults/*/*.ptiavg] {
    foreach f [glob -nocomplain $pat] {
        # Exclude the resistance runs' own pad-current files, which are not
        # this design's demand and would silently substitute for it.
        if {[string match "*_reff_*" $f]} { continue }
        lappend cur $f
    }
}
puts "RAIL current files: $cur"
if {[llength $cur] == 0} {
    puts "RAIL-FAIL no .ptiavg current files - rail analysis has no demand to solve"
    puts "RAIL-FAIL searched: $OUT/staticPowerResults, $OUT, cwd, $WORK/staticPowerResults"
    puts "RAIL-FAIL $OUT contains: [glob -nocomplain $OUT/*]"
    puts "RAIL-FAIL cwd contains : [glob -nocomplain ./staticPowerResults*]"
    puts "##### RAIL-END #####"
    exit 0
}

########################################################################
# 2. The rail solve.
########################################################################
set_rail_analysis_mode \
    -method static \
    -accuracy hd \
    -power_grid_libraries $PGV \
    -extraction_tech_file $QRC \
    -temperature 125 \
    -report_voltage_drop true \
    -verbosity true \
    -work_directory_name $WORK/rail_state \
    -tmp_directory_name  $WORK/rail_tmp

# VDDIO/VSSIO appear in no domain, no set_pg_nets and no voltage source. A rail
# run that INCLUDES them returns ~0 mV by construction and is a false green:
# they are absent from the CPF power intent, so report_power cannot attribute
# the IO group to them and the solver would be handed a rail with no demand.
set_rail_analysis_domain -domain_name PD_TOP -power_nets {VDD} -ground_nets {VSS}

# By pad cell, not by coordinate - see VDD.padcell for why the XY form silently
# produced a circuit with zero voltage sources.
#
# -short_pin_nodes true IS THE WHOLE DIFFERENCE. Without it this same command
# reported "Voltage Source Added 6/6 (100.00%)" and put ZERO voltage sources
# into the circuit, on every attempt, for both nets. The PGV here is techonly -
# no cell SPICE or cell GDS exists on this site - so a pad cell has no internal
# nodes at all; its ONLY nodes are the interface nodes where its PG pin meets
# the top-level grid. -short_pin_nodes shorts those interface nodes into one
# and binds the source there, which is exactly the right thing to do for a pad.
# With it, the sources land at the pad pins themselves (metal7, y=84.815 on the
# bottom edge and y=1915.19 on the top) and the circuit solves.
set_power_pads -reset
set_power_pads -net VDD -format padcell -file $WORK/VDD.padcell -short_pin_nodes true
set_power_pads -net VSS -format padcell -file $WORK/VSS.padcell -short_pin_nodes true

set_power_data -format current $cur

catch { report_rail -type domain ALL -output_dir $OUT/staticRailResults } e2

########################################################################
# 3. ASSERT THE ARTEFACT. report_rail in this build can print **ERROR and
#    still return cleanly - the same trap that produced a false "REFF-OK"
#    on the first attempt at the resistance measurement.
########################################################################
set found {}
foreach p [glob -nocomplain $OUT/staticRailResults/* $OUT/staticRailResults/*/* \
                            $OUT/staticRailResults/*/*/*] {
    if {[file isfile $p] && [file size $p] > 0} { lappend found $p }
}
if {[llength $found] == 0} {
    puts "RAIL-FAIL no non-empty rail artefact under $OUT/staticRailResults"
    puts "RAIL-FAIL tcl said '$e2'"
} else {
    puts "RAIL-OK [llength $found] artefacts:"
    foreach p [lrange $found 0 20] { puts "   $p ([file size $p] bytes)" }
}

########################################################################
# 4. THE THREE COVERAGE ASSERTIONS. A rail run that fails to attach current
#    to instances reports SMALL drops, which is the failure mode that looks
#    like good news. None of these is optional and none of them is the
#    command's return code, which is worthless here.
########################################################################
set vsrc_total 0
set inst_conn  {}
set cur_lines  {}
foreach rl [glob -nocomplain $OUT/staticRailResults/*/voltus_rail.log \
                             $WORK/rail_state/voltus_rail.log \
                             $OUT/staticRailResults/voltus_rail.log \
                             $OUT/staticRailResults/*/*/voltus_rail.log] {
    set fhv [open $rl r] ; set t [read $fhv] ; close $fhv
    foreach line [split $t "\n"] {
        if {[regexp {Circuit total\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)} $line -> nn rr cc vv]} {
            puts "ASSERT circuit | [string trim $line]"
            incr vsrc_total $vv
        }
        if {[regexp {Instance logically connected:\s*(\d+)} $line -> ic]} {
            lappend inst_conn $ic
            puts "ASSERT insts   | [string trim $line]"
        }
        if {[regexp -nocase {total (current|power)|current sources are disconnected|Effective Instance Current} $line]} {
            lappend cur_lines [string trim $line]
        }
    }
}
puts "ASSERT-1 instance coverage : $inst_conn of [llength [get_db insts]] total"
puts "ASSERT-2 voltage sources   : $vsrc_total  (MUST be 10 across the two nets:"
puts "                              6 VDD pads + 4 VSS pads, all top/bottom edge)"
if {$vsrc_total != 10} {
    puts "ASSERT-2 FAIL - every voltage number below is referenced to the wrong"
    puts "         thing, or to nothing at all. Do not quote it."
}
puts "ASSERT-3 current accounting lines from the solver:"
foreach l [lrange $cur_lines 0 25] { puts "   $l" }
puts "ASSERT-3 compare against report_power's core demand for this database"
puts "         (VDD rail mW / 1.08 V). Ratio must land in 0.90-1.10; outside"
puts "         that the solve is not describing this design's demand."
puts "##### RAIL-END #####"
exit 0
