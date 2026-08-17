################################################################################
# pgv.tcl - generate the TECHONLY power grid library.
#
# WHY techonly AND NOTHING ELSE. Voltus builds a power grid library in three
# flavours: techonly (layer resistances and via models out of the extraction
# tech file), stdcells, and macros. The latter two require either cell SPICE
# netlists or cell GDS to model what happens inside a cell between its PG pin
# and its transistors. Neither exists on this site: the standard-cell and IO
# libraries here ship LEF abstracts and .lib timing only. So a cell-accurate
# PGV cannot be built, and every analysis that depends on one - notably all
# dynamic rail analysis - is permanently out of reach here, not merely unrun.
#
# WHAT techonly STILL BUYS. It models the GRID: the metal, the vias, and their
# resistances. That is enough for effective-resistance analysis of the network
# between the pads and the cell rails, and enough for static rail analysis in
# which each instance is treated as a current sink at its PG pin rather than as
# a modelled internal network. The limitation this leaves is real and must
# travel with every number: resistance INSIDE a cell or macro is not modelled,
# so drops are measured to the cell's rail connection and no further.
#
# Required by report_resistance too, not only by rail analysis: this Voltus
# refuses to set the rail analysis mode at all without -power_grid_libraries
# (VOLTUS-1185), so there is no PGV-free shortcut to the resistance number.
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

# The corner report_power priced this design at, and the corner the setup view
# resolves to. See docs/tapeout/31-power-delivery-measured.md for the four-way
# disagreement this number settles.
set VCORE 1.08

if {![file isdirectory $DB]} { puts "FATAL: no DB at $DB" ; exit 1 }
if {![file readable $QRC]}   { puts "FATAL: no QRC at $QRC" ; exit 1 }

set_db read_db_file_check false
read_db $DB
set_multi_cpu_usage -local_cpu 8

file mkdir $WORK/pgv

puts "\n##### PGV-BEGIN #####"
# -lef_layer_map is not optional in practice. Without it the generator stops with
# VOLTUS_LGEN-4123 and refuses to use its own auto-generated map, which is the
# correct instinct: at the top of this stack metal9->M9, VIA9->RV and metal10->AP,
# and a silent mis-mapping there would misprice precisely the layers that carry
# current in from the pads. The map is frozen in inputs/ with its provenance.
set_pg_library_mode \
    -cell_type techonly \
    -extraction_tech_file $QRC \
    -lef_layer_map $RAILDIR/inputs/lef_layermap.txt \
    -temperature 125 \
    -default_power_voltage $VCORE \
    -power_pins [list VDD $VCORE] \
    -ground_pins {VSS}

write_pg_library -out_dir $WORK/pgv

# ASSERT THE ARTEFACT, NOT THE EXIT CODE. report_resistance in this build
# prints **ERROR and returns cleanly, so a catch around it reports success on a
# run that produced nothing - which is exactly what happened on the first
# attempt at this measurement. Check for the file.
set cl $WORK/pgv/techonly.cl
if {[file exists $cl] && [file size $cl] > 0} {
    puts "PGV-OK   $cl ([file size $cl] bytes)"
} else {
    puts "PGV-FAIL no techonly.cl produced at $cl"
}
puts "##### PGV-END #####"
exit 0
