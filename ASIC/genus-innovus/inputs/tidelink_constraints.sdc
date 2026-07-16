# Chiplet Interface
create_clock -name "D2D_RX_CLK_0" -period "$EXTCLK_PERIOD"  -waveform "0 [expr $EXTCLK_PERIOD/2]" [get_ports TL_CLK_RX]

set_input_delay 1 -clock [get_clocks "D2D_RX_CLK_0"] [get_ports TL_RX[*]]

create_generated_clock -name "D2D_TX_CLK_0" -source [get_pins u_nanosoc_eth_chiplet_chip/u_soc/u_tidelink/u_chiplet_controller/u_wlink/pad_clk_tx] -divide_by 1 [get_ports TL_CLK_TX]

set_output_delay 0.8 -clock [get_clocks "D2D_TX_CLK_0"] [get_ports TL_TX[*]]
