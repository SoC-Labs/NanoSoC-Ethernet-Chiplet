#########################################
# Script : Power Planning 
# Tool : Cadence Innovus 
# Date : May 22, 2023
# Author : Srimanth Tenneti
######################################### 

### Connecting Global Nets
connect_global_net VDD -type pg_pin -pin_base_name VDD -inst_base_name * 
connect_global_net VDDIO -type pg_pin -pin_base_name VDDIO -inst_base_name * 
connect_global_net VSS -type pg_pin -pin_base_name VSS -inst_base_name * 
connect_global_net VSSIO -type pg_pin -pin_base_name VSSIO -inst_base_name * 
### Top and Bottom Metal Declartions
set_db add_rings_stacked_via_top_layer M9
set_db add_rings_stacked_via_bottom_layer M1 

### Adding Rings 
add_rings -nets {VDD VSS} -type core_rings -follow core -layer {top M9 bottom M9 left M8 right M8} -width {top 12 bottom 12 left 12 right 12} -spacing {top 4 bottom 4 left 4 right 4} -offset {top 2 bottom 2 left 2 right 2} -center 0 -threshold 0 -jog_distance 0 -snap_wire_center_to_grid none
route_special -connect {pad_pin pad_ring} \
            -layer_change_range { M1(1) AP(10) } \
            -block_pin_target nearest_target \
            -pad_pin_port_connect {all_port all_geom} \
            -pad_pin_target nearest_target -allow_jogging 1 \
            -crossover_via_layer_range { M1(1) AP(10) } \
            -nets { VDD } -allow_layer_change 1 \
            -pad_pin_width 1.63 -target_via_layer_range { M1(1) AP(10) }

route_special -connect {pad_pin pad_ring} \
            -layer_change_range { M1(1) AP(10) } \
            -block_pin_target nearest_target \
            -pad_pin_port_connect {all_port all_geom} \
            -pad_pin_target nearest_target -allow_jogging 1 \
            -crossover_via_layer_range { M1(1) AP(10) } \
            -nets { VSS } -allow_layer_change 1 \
            -pad_pin_width 1.5 -target_via_layer_range { M1(1) AP(10) }

### Adding Stripes 
set_db add_stripes_ignore_block_check true
set_db add_stripes_break_at none
set_db add_stripes_route_over_rows_only false
set_db add_stripes_rows_without_stripes_only false
set_db add_stripes_extend_to_closest_target none
set_db add_stripes_stop_at_last_wire_for_area false
set_db add_stripes_ignore_non_default_domains true
set_db add_stripes_trim_antenna_back_to_shape none
set_db add_stripes_spacing_type edge_to_edge
set_db add_stripes_spacing_from_block 0
set_db add_stripes_stripe_min_length stripe_width
set_db add_stripes_stacked_via_top_layer AP
set_db add_stripes_stacked_via_bottom_layer M1
set_db add_stripes_via_using_exact_crossover_size false
set_db add_stripes_split_vias false
set_db add_stripes_orthogonal_only true
set_db add_stripes_allow_jog { padcore_ring  block_ring }
set_db add_stripes_skip_via_on_pin {  standardcell }
set_db add_stripes_skip_via_on_wire_shape {  noshape   }
add_stripes -nets {VDD VSS} -layer M8 -direction vertical -width 3.6 -spacing 1.2 -set_to_set_distance 60 -extend_to all_domains -start_from left -start_offset 39.5 -stop_offset 0 -switch_layer_over_obs false -max_same_layer_jog_length 2 -pad_core_ring_top_layer_limit AP -pad_core_ring_bottom_layer_limit M1 -block_ring_top_layer_limit AP -block_ring_bottom_layer_limit M1 -use_wire_group 0 -snap_wire_center_to_grid none

deselect_obj -all

### Adding Stripes 
set_db add_stripes_ignore_block_check true
set_db add_stripes_break_at none
set_db add_stripes_route_over_rows_only false
set_db add_stripes_rows_without_stripes_only false
set_db add_stripes_extend_to_closest_target none
set_db add_stripes_stop_at_last_wire_for_area false
set_db add_stripes_ignore_non_default_domains true
set_db add_stripes_trim_antenna_back_to_shape none
set_db add_stripes_spacing_type edge_to_edge
set_db add_stripes_spacing_from_block 0
set_db add_stripes_stripe_min_length stripe_width
set_db add_stripes_stacked_via_top_layer AP
set_db add_stripes_stacked_via_bottom_layer M1
set_db add_stripes_via_using_exact_crossover_size false
set_db add_stripes_split_vias false
set_db add_stripes_orthogonal_only true
set_db add_stripes_allow_jog { padcore_ring  block_ring }
set_db add_stripes_skip_via_on_pin {  standardcell }
set_db add_stripes_skip_via_on_wire_shape {  noshape   }
add_stripes -nets {VDD VSS} -layer M9 -direction horizontal -width 3.6 -spacing 1.2 -set_to_set_distance 60 -extend_to all_domains -start_from left -start_offset 39.5 -stop_offset 0 -switch_layer_over_obs false -max_same_layer_jog_length 2 -pad_core_ring_top_layer_limit AP -pad_core_ring_bottom_layer_limit M1 -block_ring_top_layer_limit AP -block_ring_bottom_layer_limit M1 -use_wire_group 0 -snap_wire_center_to_grid none

deselect_obj -all


# connect Macros
select_obj [ list \
    u_nanosoc_eth_chiplet_chip_u_soc_u_soc/u_network_core/u_ethmac_0/u_inner_u_eth_top_wishbone_bd_ram_u_sram/u_rf \
    u_nanosoc_eth_chiplet_chip_u_soc_u_soc/u_network_core/u_region_bootrom_0_u_bootrom_u_rom_via \
    u_nanosoc_eth_chiplet_chip_u_soc_u_soc/u_network_core/u_region_dmem_0_u_sram_u_sram_gen_rf_16k.u_rf_sp_hdf \
    u_nanosoc_eth_chiplet_chip_u_soc_u_soc/u_network_core/u_region_eth_scratch_rx_0_u_sram_u_sram_gen_rf_08k.u_rf_sp_hdf \
    u_nanosoc_eth_chiplet_chip_u_soc_u_soc/u_network_core/u_region_eth_scratch_tx_0_u_sram_u_sram_gen_rf_08k.u_rf_sp_hdf \
    u_nanosoc_eth_chiplet_chip_u_soc_u_soc/u_network_core/u_region_imem_0_u_mem_u_sram_gen_rf_32k.u_rf_sp_hdf \
    u_nanosoc_eth_chiplet_chip_u_soc_u_soc/u_qspi_flash_0_u_top_ahb_qspi_u_cache_subsystem_gen_way1.u_way1_cache_ram_tag_ram_0_i \
    u_nanosoc_eth_chiplet_chip_u_soc_u_soc/u_qspi_flash_0_u_top_ahb_qspi_u_cache_subsystem_u_way0_cache_ram_tag_ram_0_i \
    u_nanosoc_eth_chiplet_chip_u_soc_u_soc/u_qspi_flash_0_u_top_ahb_qspi_u_cache_subsystem_u_way0_cache_ram_data_ram_0_word_2_i \
    u_nanosoc_eth_chiplet_chip_u_soc_u_soc/u_qspi_flash_0_u_top_ahb_qspi_u_cache_subsystem_u_way0_cache_ram_data_ram_0_word_3_i \
    u_nanosoc_eth_chiplet_chip_u_soc_u_soc/u_qspi_flash_0_u_top_ahb_qspi_u_cache_subsystem_u_way0_cache_ram_data_ram_0_word_0_i \
    u_nanosoc_eth_chiplet_chip_u_soc_u_soc/u_qspi_flash_0_u_top_ahb_qspi_u_cache_subsystem_u_way0_cache_ram_data_ram_0_word_1_i \
    u_nanosoc_eth_chiplet_chip_u_soc_u_soc/u_qspi_flash_0_u_top_ahb_qspi_u_cache_subsystem_gen_way1.u_way1_cache_ram_data_ram_0_word_2_i \
    u_nanosoc_eth_chiplet_chip_u_soc_u_soc/u_qspi_flash_0_u_top_ahb_qspi_u_cache_subsystem_gen_way1.u_way1_cache_ram_data_ram_0_word_3_i \
    u_nanosoc_eth_chiplet_chip_u_soc_u_soc/u_qspi_flash_0_u_top_ahb_qspi_u_cache_subsystem_gen_way1.u_way1_cache_ram_data_ram_0_word_0_i \
    u_nanosoc_eth_chiplet_chip_u_soc_u_soc/u_qspi_flash_0_u_top_ahb_qspi_u_cache_subsystem_gen_way1.u_way1_cache_ram_data_ram_0_word_1_i \
    u_nanosoc_eth_chiplet_chip_u_soc_u_soc/u_chip_core_u_region_imem_0_u_mem_u_sram_gen_rf_16k.u_rf_sp_hdf \
    u_nanosoc_eth_chiplet_chip_u_soc_u_soc/u_shared_sram_0_u_sram_u_sram_gen_rf_08k.u_rf_sp_hdf \
    u_nanosoc_eth_chiplet_chip_u_soc_u_soc/u_chip_core_u_region_dmem_0_u_mem_u_sram_gen_rf_08k.u_rf_sp_hdf \
    u_nanosoc_eth_chiplet_chip_u_soc_u_soc/u_chip_core_u_region_bootrom_0_u_bootrom_u_rom_via \
    u_nanosoc_eth_chiplet_chip_u_soc_u_tidelink/u_tidelink_fifo_u_fifo_mem_u_sram_u_rf \
]

split_row -selected

set_db add_stripes_ignore_block_check false
set_db add_stripes_break_at none
set_db add_stripes_route_over_rows_only false
set_db add_stripes_rows_without_stripes_only false
set_db add_stripes_extend_to_closest_target {ring stripe}
add_stripes -nets {VDD VSS} -layer M5 -direction horizontal -width 1 -spacing 0.5 -set_to_set_distance 15 -over_power_domain 1 -start_from bottom -start_offset 8 -stop_offset 0 -switch_layer_over_obs false -merge_stripes_value 500 -max_same_layer_jog_length 2 -pad_core_ring_top_layer_limit AP -pad_core_ring_bottom_layer_limit M1 -block_ring_top_layer_limit AP -block_ring_bottom_layer_limit M1 -use_wire_group 0 -snap_wire_center_to_grid none

deselect_obj -all

# Add END CAPS
add_endcaps -start_row_cap DCAP4 -end_row_cap DCAP4 -prefix ENDCAP

route_special -connect {pad_pin pad_ring} -layer_change_range { M1(1) AP(10) } -block_pin_target nearest_target -pad_pin_port_connect {all_port all_geom} -pad_pin_target nearest_target -allow_jogging 1 -crossover_via_layer_range { M1(1) AP(10) } -nets { VDD VSS } -allow_layer_change 1 -pad_pin_width 6 -target_via_layer_range { M1(1) AP(10) }
set_db route_special_via_connect_to_shape { padring stripe }
route_special -connect {block_pin core_pin floating_stripe} -layer_change_range { M1(1) AP(10) } -block_pin_target nearest_target -pad_pin_port_connect {all_port one_geom} -pad_pin_target nearest_target -core_pin_target first_after_row_end -floating_stripe_target {block_ring pad_ring ring stripe ring_pin block_pin followpin} -allow_jogging 1 -power_domains { PD_TOP } -crossover_via_layer_range { M1(1) AP(10) } -nets { VDD VSS } -allow_layer_change 1 -block_pin use_lef -target_via_layer_range { M1(1) AP(10) }

