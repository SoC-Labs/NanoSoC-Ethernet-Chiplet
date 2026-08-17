################################################################################
# reff_auto.tcl - the decisive experiment behind the resistance measurement.
#
# THE PROBLEM THIS SETTLES. Two independent ways of naming the ten core supply
# pads as voltage sources - XY coordinates, and pad-cell master - both ended the
# same way:
#
#     # Voltage Source Added/Total (%): 6/6 (100.00%)
#     ** ERROR: (VOLTUS_RAIL-5097): All nodes of net VDD are disconnected.
#     Circuit total   852191 nodes   1118378 resistors   332976 current sources
#                                                        0 VOLTAGE SOURCES
#
# The pads were matched (VDD.padcells lists all six) and the grid extracted
# beautifully - 852k nodes, 338903 of 339390 instances connected, 99.86%. What
# never happened is the attachment of a source to a node.
#
# TWO HYPOTHESES, and they have completely different consequences:
#
#   H1  TOOLING. The pad cells have no power-grid-library view. The PGV built
#       here is `techonly` - it models layers and vias, not the inside of a
#       cell - because no cell SPICE or cell GDS exists on this site. If a pad's
#       PG pin is only described inside its abstract, the extractor has no node
#       there and no source can bind to it. Consequence: measure from the grid
#       instead, and the number is still real.
#
#   H2  DESIGN. The pads genuinely do not reach the mesh in this database.
#       Consequence: that is a dead chip, and the most important finding on it.
#
# THE DISCRIMINATOR. Ask the tool to create the voltage sources ITSELF, on the
# grid, at the top via layer - which is exactly where the pads inject current
# into the mesh (pad -> AP -> RV -> M9 -> mesh). Nothing about a pad cell is
# involved, so H1 cannot cause a failure here.
#
#   If sources appear and a resistance report is produced, H1 is the cause: the
#   grid is drivable and measurable, and the measurement is "resistance from the
#   top-layer feed points", which is a slightly weaker claim than "from the
#   pads" because it excludes the pad-to-AP path. Say so with the number.
#
#   If sources STILL do not appear, H1 is refuted and H2 becomes the live
#   possibility, to be escalated rather than reported as a tool problem.
#
# Either way this is a diagnostic, and its result is reported as one.
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

set_db read_db_file_check false
read_db $DB
set_multi_cpu_usage -local_cpu 8

puts "\n##### REFFAUTO-BEGIN #####"

set_rail_analysis_mode \
    -method static -accuracy hd \
    -power_grid_libraries $PGV \
    -extraction_tech_file $QRC \
    -enable_reff_analysis true \
    -temperature 125 -verbosity true \
    -work_directory_name $WORK/reffauto_state \
    -tmp_directory_name  $WORK/reffauto_tmp

set_pg_nets -net VDD -voltage $VCORE
set_pg_nets -net VSS -voltage 0.0
set_rail_analysis_domain -domain_name PD_TOP -power_nets {VDD} -ground_nets {VSS}

# VDDIO/VSSIO remain excluded: not in the domain, not in set_pg_nets, no sources.
foreach net {VDD VSS} {
    set odir $WORK/ReffAuto_$net
    file delete -force $odir

    set_power_pads -reset
    # RV is the via between the top routing metal and the top aluminium the pads
    # land on, so a source on RV sits at the real injection point of the mesh.
    set_power_pads -net $net -auto_voltage_source_creation true -layer RV

    catch { report_resistance -net_name $net -threshold 0 -output_dir $odir } e

    set found ""
    foreach g [glob -nocomplain $odir/*/Reports/$net/$net.effr $odir/*/REFF/effr.rpt] {
        if {[file exists $g] && [file size $g] > 0} { set found $g ; break }
    }
    if {$found eq ""} {
        puts "REFFAUTO-FAIL $net : no non-empty effr artefact (tcl said '$e')"
    } else {
        puts "REFFAUTO-OK $net : $found ([file size $found] bytes)"
    }
    foreach rl [glob -nocomplain $odir/*/voltus_rail.log] {
        set fhv [open $rl r] ; set t [read $fhv] ; close $fhv
        foreach line [split $t "\n"] {
            if {[regexp {Voltage Source Added/Total|Circuit total|Instance logically connected|are disconnected|VOLTUS_RAIL-5097} $line]} {
                puts "  ASSERT $net | [string trim $line]"
            }
        }
    }
}
puts "##### REFFAUTO-END #####"
exit 0
