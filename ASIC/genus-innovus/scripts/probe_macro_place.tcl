# Where is the dmem rf_16k actually placed, and at what orientation?
# The M4-SHORT analysis transforms a chip coordinate into macro-local space, so
# a wrong origin or orientation makes the answer meaningless.
set db ../runs/20260808T100330Z_route-setupopt/work/nanosoc_eth_chiplet_pads_eval_route
read_db $db
puts "\n##### PLACE-BEGIN #####"
foreach i [get_db insts -if {.name == *u_region_dmem_0*rf_16k*}] {
    puts "INST [get_db $i .name]"
    puts "  base_cell   [get_db $i .base_cell.name]"
    puts "  orient      [get_db $i .orient]"
    puts "  location    [get_db $i .location]"
    puts "  bbox        [get_db $i .bbox]"
}
puts "##### PLACE-END #####"
exit 0
