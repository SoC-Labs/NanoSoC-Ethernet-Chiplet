## Die size floorplan
create_floorplan -site core -die_size 1600 2000 50 50 50 50

## Place IOs
delete_io_fillers
read_io_file ../scripts/nanosoc_eth_chiplet_pads.io

add_io_fillers -cells PFILLER20_G -prefix FILLER -side n
add_io_fillers -cells PFILLER20_G -prefix FILLER -side e
add_io_fillers -cells PFILLER20_G -prefix FILLER -side s 
add_io_fillers -cells PFILLER20_G -prefix FILLER -side w 

add_io_fillers -cells PFILLER10_G -prefix FILLER -side n
add_io_fillers -cells PFILLER10_G -prefix FILLER -side e
add_io_fillers -cells PFILLER10_G -prefix FILLER -side s 
add_io_fillers -cells PFILLER10_G -prefix FILLER -side w 

add_io_fillers -cells PFILLER5_G -prefix FILLER -side n
add_io_fillers -cells PFILLER5_G -prefix FILLER -side e
add_io_fillers -cells PFILLER5_G -prefix FILLER -side s 
add_io_fillers -cells PFILLER5_G -prefix FILLER -side w 

add_io_fillers -cells PFILLER1_G -prefix FILLER -side n
add_io_fillers -cells PFILLER1_G -prefix FILLER -side e
add_io_fillers -cells PFILLER1_G -prefix FILLER -side s 
add_io_fillers -cells PFILLER1_G -prefix FILLER -side w 

add_io_fillers -cells PFILLER05_G -prefix FILLER -side n
add_io_fillers -cells PFILLER05_G -prefix FILLER -side e
add_io_fillers -cells PFILLER05_G -prefix FILLER -side s 
add_io_fillers -cells PFILLER05_G -prefix FILLER -side w 

add_io_fillers -cells PFILLER0005_G -prefix FILLER -side n
add_io_fillers -cells PFILLER0005_G -prefix FILLER -side e
add_io_fillers -cells PFILLER0005_G -prefix FILLER -side s 
add_io_fillers -cells PFILLER0005_G -prefix FILLER -side w 

## Place macros
unplace_obj -blocks
create_place_halo -halo_deltas {3.6 3.6 3.6 3.6} -all_macros


## Macro placement.
##
## Resolved by PATTERN, not by hardcoded hierarchical path. Genus runs with
## auto-ungroup ON (1_synthesis.tcl leaves `set_db auto_ungroup none`
## commented out), so the hierarchical name of a macro is a function of the
## tool's ungrouping decisions and MOVES when the RTL changes. This file
## previously hardcoded 21 full paths captured from one netlist; after an
## unrelated RTL change 6 of them no longer existed -- the ethmac one, and the
## five QSPI way1 macros, which lost their `gen_way1.` generate-block prefix.
##
## The failure mode is worth knowing: place_inst reports IMPTCM-162 "does not
## match any object in design", which reads as a stale floorplan rather than
## as a renamed instance, and it aborts 2_pnr_setup.tcl on the FIRST bad name
## so you fix them one slow Innovus run at a time.
##
## The patterns below key on the RTL-derived fragments (region names, cache
## way/word indices, macro type), which are stable, and ignore the separators
## and prefixes, which are not. place_macro insists on exactly one match.
proc place_macro {pattern x y orient} {
    # Filter to MACROS explicitly. `get_db insts <pattern>` matches every
    # instance, standard cells included, so a region-scoped glob like
    # *region_eth_scratch_rx_0* returns the macro plus ~50 leaf cells in the
    # same region. The base_class test is what makes the "exactly 1" check
    # meaningful. Done in Tcl rather than with -if so there is no doubt about
    # how a pattern and a predicate combine in this Innovus version.
    set hits {}
    foreach i [get_db insts $pattern] {
        if {[get_db $i .base_cell.base_class] eq "block"} { lappend hits $i }
    }
    if {[llength $hits] != 1} {
        error "place_macro: pattern '$pattern' matched [llength $hits] instances, expected exactly 1.\
               \n  Macro instance names change when Genus re-ungroups; re-run\
               \n  scripts/probe_macros.tcl to dump the current names, then fix the pattern."
    }
    set inst [get_db [lindex $hits 0] .name]
    place_inst $inst $x $y $orient
    set_db [get_db insts $inst] .place_status placed
    # Record the RESOLVED name for power_plan.tcl's split_row/select_obj.
    # power_plan.tcl used to carry its own hardcoded copy of these 21 paths and
    # it drifted: the same 6 names that went stale here (the ethmac RF and the
    # five QSPI way1 macros) were still stale there, so split_row silently ran
    # on 15 of 21 macros — six IMPTCM-165 "does not match any object" warnings
    # nobody was reading. Publishing the resolved list makes that impossible.
    lappend ::PLACED_MACROS $inst
}
set ::PLACED_MACROS {}

place_macro {*ethmac*bd_ram*u_rf} 1053.8000000000 1117.8100000000 R180
place_macro {*u_network_core*u_region_bootrom_0*rom_via*} 883.5350000000 1538.6000000000 MY
place_macro {*u_network_core*u_region_dmem_0*rf_16k*} 1058.6000000000 1360.4000000000 MY
place_macro {*region_eth_scratch_rx_0*} 590.2000000000 1338.8000000000 R0
place_macro {*region_eth_scratch_tx_0*} 1049.8000000000 1653.8000000000 MY
place_macro {*u_network_core*u_region_imem_0*rf_32k*} 290.8000000000 1513.4000000000 R0
place_macro {*way1_cache_ram_tag_ram_0_i} 911.2000000000 448.6900000000 MX
place_macro {*way0_cache_ram_tag_ram_0_i} 898.8000000000 382.0900000000 MX
place_macro {*way0_cache_ram_data_ram_0_word_2_i} 553.8000000000 460.4000000000 R0
place_macro {*way0_cache_ram_data_ram_0_word_3_i} 516.6000000000 370.0400000000 MX
place_macro {*way0_cache_ram_data_ram_0_word_0_i} 702.4000000000 280.0400000000 MX
place_macro {*way0_cache_ram_data_ram_0_word_1_i} 718.8000000000 325.0400000000 MX
place_macro {*way1_cache_ram_data_ram_0_word_2_i} 633.6000000000 507.2000000000 R0
place_macro {*way1_cache_ram_data_ram_0_word_3_i} 564.4000000000 415.0400000000 MX
place_macro {*way1_cache_ram_data_ram_0_word_0_i} 708.6000000000 190.0400000000 MX
place_macro {*way1_cache_ram_data_ram_0_word_1_i} 727.8000000000 235.0400000000 MX
place_macro {*u_chip_core*u_region_imem_0*rf_16k*} 1059.2000000000 203.9500000000 R180
place_macro {*u_shared_sram_0*rf_08k*} 1052.4000000000 500.7100000000 R180
place_macro {*u_chip_core*u_region_dmem_0*rf_08k*} 1050.4000000000 953.6000000000 R0
place_macro {*u_chip_core*u_region_bootrom_0*rom_via*} 1237.3350000000 735.4650000000 R180
place_macro {*u_tidelink*u_tidelink_fifo_u_fifo_mem_u_sram_u_rf} 230.6000000000 1220.0000000000 R0
