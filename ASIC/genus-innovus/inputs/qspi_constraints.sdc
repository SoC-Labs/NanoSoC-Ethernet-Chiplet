# QSPI CLocks
create_generated_clock -name "QSPI_SCLK" -source [get_ports CLK] -divide_by 2 [get_pins u_nanosoc_eth_chiplet_chip/u_soc/u_soc/u_qspi_flash_0/u_top_ahb_qspi/u_qspi_clock_div/QSPI_SCLK_i]
create_generated_clock -name "QSPI_SCLK_o" -source [get_pins u_nanosoc_eth_chiplet_chip/u_soc/u_soc/u_qspi_flash_0/u_top_ahb_qspi/u_qspi_clock_div/QSPI_SCLK_i] -divide_by 1 [get_ports QSPI_SCLK]

set_input_delay -min 0  -clock "QSPI_SCLK" [get_ports {QSPI_IO[*]}]
set_input_delay -max 1  -clock "QSPI_SCLK" [get_ports {QSPI_IO[*]}]

set_output_delay -min 0 -clock "QSPI_SCLK_o" [get_ports {QSPI_IO[*]}]
set_output_delay -max 1 -clock "QSPI_SCLK_o" [get_ports {QSPI_IO[*]}]
