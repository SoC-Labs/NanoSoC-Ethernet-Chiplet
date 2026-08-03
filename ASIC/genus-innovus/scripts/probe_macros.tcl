#-----------------------------------------------------------------------------
# probe_macros.tcl — dump every macro instance's hierarchical name
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
#
# Copyright 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# Diagnostic for floorplan.tcl's place_macro patterns. Genus runs with
# auto-ungroup ON, so macro instance names move when the RTL changes; if
# place_macro reports "matched 0 instances", run this to see what the names
# actually are now, then fix the pattern.
#
# Replicates 2_pnr_setup.tcl up to init_design and stops. Writes no DB.
#
#   cd ASIC/genus-innovus/work
#   TSMC_65_HOME=/tsmc65pdk/65 \
#   NANOSOC_ETH_CHIPLET_HOME=<repo> \
#   innovus -stylus -files ../scripts/probe_macros.tcl < /dev/null
#
# The env vars matter: they are exported by ASIC/common.mk, so a bare shell
# does not have them and config.tcl dies on $::env(TSMC_65_HOME). Redirecting
# stdin matters too — on any error Innovus drops to its prompt and would
# otherwise sit there until killed.
#
# Result: ../logs/macro_insts.txt
#-----------------------------------------------------------------------------
source ../scripts/config.tcl
set_multi_cpu_usage -local_cpu 8
set_db init_power_nets $power_nets
set_db init_ground_nets $ground_nets
read_mmmc ../scripts/${block_name}.mmmc
read_physical -lef $lef_file_list
read_netlist $OUT_DIR/${block_name}_gate_power.v
init_design
set fh [open ../logs/macro_insts.txt w]
foreach i [get_db insts -if {.base_cell.base_class == block}] {
    puts $fh "[get_db $i .name]  ->  [get_db $i .base_cell.name]"
}
close $fh
puts "PROBE_DONE count=[llength [get_db insts -if {.base_cell.base_class == block}]]"
exit
