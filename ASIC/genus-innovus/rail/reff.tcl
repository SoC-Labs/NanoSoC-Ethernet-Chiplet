################################################################################
# reff.tcl - EFFECTIVE RESISTANCE of the core power grid.
#
# The first electrical measurement of power delivery this design has ever had.
#
# WHY THIS ONE FIRST. Effective resistance needs no switching activity, no
# power grid library for the cells, and no cell SPICE. It is a property of the
# metal that is drawn. It answers, in ohms, the question the RV-via count was
# standing in for and could not answer in principle: whether a 1600x2000 die at
# ~89% utilisation, fed by ten core supply pads that all sit on the TOP AND
# BOTTOM edges, has a grid that reaches the middle and the sides.
#
# THE PREDICTION UNDER TEST. Every core supply pad is on the top or bottom
# edge - six VDD and four VSS, confirmed from the database, none on the left or
# right. Current therefore has to travel laterally to reach the left and right
# core edges, and vertically to reach mid-height. If the grid is marginal, the
# worst effective resistance should appear far from y=0 and y=2000 - i.e. at
# mid-height - and worst of all in the left and right corners of that band.
# A flat map would refute the concern; a map that peaks where predicted
# localises the fix.
#
# WHAT IS DELIBERATELY EXCLUDED. VDDIO and VSSIO are NOT in the analysis
# domain, have NO voltage sources declared, and are named in -exclude_nets.
# They are distributed by pad abutment rather than by routing, so a resistance
# or rail number that includes them describes nothing - the tool would either
# find no path at all or bridge them through geometry that is not a grid.
# Their continuity is a separate measurement (see probe_pg_channels.tcl).
#
# COVERAGE, WHICH MUST BE CHECKED BEFORE ANY NUMBER IS BELIEVED. A resistance
# run that fails to attach to the grid reports FEW instances, not bad ones, and
# a rail run with poor coverage reports SMALL drops. The assertions at the end
# of this script exist because a green number from a run that measured nothing
# is the failure mode this project has hit before.
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

if {![file isdirectory $DB]}  { puts "FATAL: no DB at $DB"   ; exit 1 }
if {![file readable $QRC]}    { puts "FATAL: no QRC at $QRC" ; exit 1 }
if {![file readable $PGV]}    { puts "FATAL: no PGV at $PGV - run pgv.tcl first" ; exit 1 }
foreach f {VDD.pp VSS.pp} {
    if {![file readable $WORK/$f]} { puts "FATAL: missing $WORK/$f - run recon.tcl first" ; exit 1 }
}

# See recon.tcl for why this check is disabled and what it costs.
set_db read_db_file_check false
read_db $DB
set_multi_cpu_usage -local_cpu 8

puts "\n##### REFF-BEGIN #####"
puts "REFF insts : [llength [get_db insts]]"
puts "REFF core  : [get_db current_design .core_bbox]"
puts "REFF die   : [get_db current_design .bbox]"

########################################################################
# Instance coordinates, for the spatial join afterwards.
# Bulk attribute queries - a per-instance get_db loop over 339k objects
# costs minutes for the same answer.
########################################################################
if {![file exists $WORK/inst_xy.txt]} {
    set names [get_db insts .name]
    set locs  [get_db insts .location]
    puts "REFF names=[llength $names] locs=[llength $locs]"
    set fh [open $WORK/inst_xy.txt w]
    foreach n $names l $locs {
        lassign $l x y
        puts $fh "$n $x $y"
    }
    close $fh
    puts "REFF wrote $WORK/inst_xy.txt"
} else {
    puts "REFF reusing $WORK/inst_xy.txt"
}

########################################################################
# Analysis configuration.
#
# -method static is stated even though report_resistance computes no
# voltage: it keeps this run on the signoff-legal method and away from the
# era_* engines, whose grid-completion invents virtual follow-pins and vias
# and would bridge exactly the PG opens that make this measurement worth
# taking. -stream_file is likewise never used here; a large fraction of the
# metal in the streamed GDS is routing blockage streamed as conductor, which
# would flatter every number below.
########################################################################
set_rail_analysis_mode \
    -method static \
    -accuracy hd \
    -power_grid_libraries $PGV \
    -extraction_tech_file $QRC \
    -enable_reff_analysis true \
    -temperature 125 \
    -ignore_shorts false \
    -verbosity true \
    -work_directory_name $WORK/reff_state \
    -tmp_directory_name  $WORK/reff_tmp

# Declare the nets and their voltages. Without this the domain below is
# rejected with VOLTUS-1121 "VDD is not defined in PD_TOP" - and, as ever in
# this tool, report_resistance then prints **ERROR and returns success.
set_pg_nets -net VDD -voltage $VCORE
set_pg_nets -net VSS -voltage 0.0

# VDDIO and VSSIO are named in NEITHER the domain NOR set_pg_nets NOR the
# voltage sources. That is the exclusion, and it is deliberate: they carry no
# routing by construction, so including them yields a number about nothing.
set_rail_analysis_domain -domain_name PD_TOP -power_nets {VDD} -ground_nets {VSS}

# BY PAD CELL, NOT BY COORDINATE. The XY form reported "Voltage Source Added
# 6/6 (100.00%)" and then produced a circuit with ZERO voltage sources on every
# layer and VOLTUS_RAIL-5097 "All nodes of net VDD are disconnected" - because
# an XY source must land exactly on a node of the extracted grid and the tool
# neither snaps nor counts the failure.
#
# The pad cell files hold a BARE CELL NAME AND NOTHING ELSE. The manual shows
# '*' comment banners in its example, but this parser rejects them:
#   VOLTUS_RAIL_SMG-0041: Pad cell file ... line 1: Syntax error.
# so the explanation lives here instead of in the data file.
#
#   VDD.padcell -> PVDD1DGZ_G, the CORE supply pad: exactly 6 instances, all on
#                  the top and bottom edges.
#   VSS.padcell -> PVSS1DGZ_G, the core ground pad: exactly 4 instances, also
#                  top and bottom only.
# The IO supply pads are different masters entirely (PVDD2DGZ_G, PVDD2POC_G,
# PVSS2DGZ_G), so selecting by master cannot leak VDDIO/VSSIO into this domain.
# No package r/l/c is given - there is no package model for this part - so every
# number here is DIE-ONLY and excludes package and bond-wire drop.
set_power_pads -reset
set_power_pads -net VDD -format padcell -file $WORK/VDD.padcell
set_power_pads -net VSS -format padcell -file $WORK/VSS.padcell

########################################################################
# The measurement. Net by net, because the question "is the VDD grid sound"
# and the question "is the VSS grid sound" have different answers - there are
# six VDD pads and only four VSS pads, and the two meshes are not symmetric.
#
# -threshold 0 so that every instance is reported rather than only those above
# an arbitrary limit: the distribution is the result, not just the maximum.
########################################################################
#
# NEVER TRUST THE RETURN. The first attempt at this measurement wrapped
# report_resistance in a catch, got a clean return for both nets, and printed
# "REFF-OK VDD / REFF-OK VSS" - while the command had actually printed
# **ERROR (VOLTUS-1185, missing power grid library) and written no file at all.
# A catch tests whether Tcl raised; it does not test whether anything was
# measured. Assert the ARTEFACT.
#
foreach net {VDD VSS} {
    puts "\n--- report_resistance net=$net ---"
    set odir $WORK/Reff_$net
    set ofile $WORK/Reff_$net.rpt
    file delete -force $ofile
    catch {
        report_resistance -net_name $net \
            -threshold 0 \
            -output_dir $odir \
            -output_file $ofile
    } e

    # Search widely. The report does not land where -output_file suggests: it
    # appears as <odir>/<net>_<temp>C_reff_1/Reports/<net>/<net>.effr, with a
    # symlink at .../REFF/effr.rpt. And on the first successful-looking run that
    # file existed but was ZERO BYTES, which is the whole point of checking size
    # rather than existence.
    set found ""
    set cands [list $ofile]
    foreach g [glob -nocomplain $odir/*/Reports/$net/$net.effr $odir/*/REFF/effr.rpt \
                                $odir/$net.effr $odir/Reports/$net/$net.effr] {
        lappend cands $g
    }
    foreach cand $cands {
        if {[file exists $cand] && [file size $cand] > 0} { set found $cand ; break }
    }
    if {$found eq ""} {
        # Cast around the state directory before giving up, so the report says
        # what the tool DID write rather than only that the expected name is
        # absent.
        set glob [glob -nocomplain $odir/* $odir/*/* $odir/*/*/*]
        puts "REFF-FAIL $net : no non-empty effr artefact."
        puts "REFF-FAIL $net : tcl said '$e'"
        puts "REFF-FAIL $net : output_dir contains: $glob"
    } else {
        puts "REFF-OK $net : $found ([file size $found] bytes)"
    }

    # COVERAGE ASSERTIONS, from the solver's own log. "Voltage Source Added
    # 6/6 (100.00%)" is NOT sufficient - that line was printed on the run that
    # ended with zero voltage sources in the circuit. The number that matters is
    # the Voltage Sources column of the circuit profile; if it is 0 there is no
    # reference node and every resistance is meaningless.
    foreach rl [glob -nocomplain $odir/*/voltus_rail.log] {
        set fhv [open $rl r] ; set t [read $fhv] ; close $fhv
        foreach line [split $t "\n"] {
            if {[regexp {Voltage Source Added/Total} $line]} { puts "  ASSERT $net | [string trim $line]" }
            if {[regexp {Circuit total} $line]}              { puts "  ASSERT $net | [string trim $line]" }
            if {[regexp {Instance logically connected}  $line]} { puts "  ASSERT $net | [string trim $line]" }
            if {[regexp {disconnected}  $line]}             { puts "  ASSERT $net | [string trim $line]" }
            if {[regexp {VOLTUS_RAIL-5097} $line]}          { puts "  ASSERT $net | [string trim $line]" }
        }
    }
}

puts "\n##### REFF-END #####"
exit 0
