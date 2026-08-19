// -----------------------------------------------------------------------------
// FIXTURE — not a build product. See ci/fixtures/boundary-scan/README.md.
//
// Derived from the real synthesised netlist
//   ASIC/eth-chiplet/build/bscan-probe/outputs/nanosoc_eth_chiplet_pads_gate.v
//   Cadence Genus(TM) Synthesis Solution 21.15-s080_1, 2026-08-19 14:06:34 BST
// by extracting the nanosoc_eth_chiplet_bscan module verbatim, its instantiation
// verbatim, and the instantiation block of each of the 48 pad cells named in
// src/rtl/bscan/pad_table.json.  Everything else in the 35 MB original is
// irrelevant to this gate and is elided.
//
// MUTATION APPLIED HERE: the entire nanosoc_eth_chiplet_bscan module and its instantiation deleted, which is
// exactly what Genus does when SE is case-analysed to a constant: the
// register is unreachable and unobservable, so removing it is correct
// constant propagation and the synthesis log stays green.
// -----------------------------------------------------------------------------
module nanosoc_eth_chiplet_pads ();
  PDDW04DGZ_G uPAD_NRST_I(.REN (1'b1), .I (1'b0), .OEN (1'b1), .PAD
       (NRST), .C (bsp_nrst_i_in));
  PDDW04DGZ_G uPAD_SWDCK_I(.REN (1'b0), .I (1'b0), .OEN (1'b1), .PAD
       (SWDCK), .C (bsp_swdck_i_in));
  PDDW04DGZ_G uPAD_CLK_I(.REN (1'b1), .I (1'b0), .OEN (1'b1), .PAD
       (CLK), .C (bsp_clk_i_in));
  PDDW04DGZ_G uPAD_TEST_I(.REN (1'b0), .I (1'b0), .OEN (1'b1), .PAD
       (TEST), .C (bsp_test_i_in));
  PDDW04DGZ_G uPAD_SE_I(.REN (1'b0), .I (1'b0), .OEN (1'b1), .PAD (SE),
       .C (bsp_se_i_in));
  PDUW08DGZ_G uPAD_SWDIO_IO(.REN (1'b0), .I (bsp_swdio_io_out), .OEN
       (n_16599), .PAD (SWDIO), .C (bsp_swdio_io_in));
  PDDW16DGZ_G uPAD_HOST_IO_6(.REN (1'b1), .I (bsp_host_io_6_out), .OEN
       (n_16592), .PAD (HOSTIO4_P1[6]), .C (bsp_host_io_6_in));
  PDDW16DGZ_G uPAD_HOST_IO_5(.REN (1'b1), .I (bsp_host_io_5_out), .OEN
       (n_16591), .PAD (HOSTIO4_P1[5]), .C (bsp_host_io_5_in));
  PDDW16DGZ_G uPAD_HOST_IO_4(.REN (1'b1), .I (bsp_host_io_4_out), .OEN
       (n_16590), .PAD (HOSTIO4_P1[4]), .C (bsp_host_io_4_in));
  PDDW16DGZ_G uPAD_HOST_IO_3(.REN (1'b1), .I (bsp_host_io_3_out), .OEN
       (n_16589), .PAD (HOSTIO4_P1[3]), .C (bsp_host_io_3_in));
  PDDW16DGZ_G uPAD_HOST_IO_2(.REN (1'b1), .I (bsp_host_io_2_out), .OEN
       (n_16588), .PAD (HOSTIO4_P1[2]), .C (bsp_host_io_2_in));
  PDDW16DGZ_G uPAD_HOST_IO_1(.REN (1'b1), .I (bsp_host_io_1_out_muxed),
       .OEN (n_16587), .PAD (HOSTIO4_P1[1]), .C (bsp_host_io_1_in));
  PDDW16DGZ_G uPAD_HOST_IO_0(.REN (1'b1), .I (bsp_host_io_0_out), .OEN
       (n_16584), .PAD (HOSTIO4_P1[0]), .C (bsp_host_io_0_in));
  PDDW04DGZ_G uPAD_RMII_CRS_DV(.REN (1'b0), .I (1'b0), .OEN (1'b1),
       .PAD (RMII_CRS_DV), .C (bsp_rmii_crs_dv_in));
  PDDW16DGZ_G uPAD_RMII_MDIO(.REN (1'b1), .I (bsp_rmii_mdio_out), .OEN
       (n_16597), .PAD (RMII_MDIO), .C (bsp_rmii_mdio_in));
  PDDW16DGZ_G uPAD_RMII_TX_EN(.REN (1'b1), .I (bsp_rmii_tx_en_out),
       .OEN (1'b0), .PAD (RMII_TX_EN), .C (UNCONNECTED2716));
  PDDW16DGZ_G uPAD_RMII_TXD1(.REN (1'b1), .I (bsp_rmii_txd1_out), .OEN
       (1'b0), .PAD (RMII_TXD[1]), .C (UNCONNECTED2715));
  PDDW16DGZ_G uPAD_RMII_TXD0(.REN (1'b1), .I (bsp_rmii_txd0_out), .OEN
       (1'b0), .PAD (RMII_TXD[0]), .C (UNCONNECTED2714));
  PDDW04DGZ_G uPAD_RMII_RXD1(.REN (1'b0), .I (1'b0), .OEN (1'b1), .PAD
       (RMII_RXD[1]), .C (bsp_rmii_rxd1_in));
  PDDW04DGZ_G uPAD_RMII_RXD0(.REN (1'b0), .I (1'b0), .OEN (1'b1), .PAD
       (RMII_RXD[0]), .C (bsp_rmii_rxd0_in));
  PDDW04DGZ_G uPAD_RMII_REF_CLK(.REN (1'b1), .I (1'b0), .OEN (1'b1),
       .PAD (RMII_REF_CLK), .C (bsp_rmii_ref_clk_in));
  PDDW16DGZ_G uPAD_RMII_MDC(.REN (1'b1), .I (bsp_rmii_mdc_out), .OEN
       (1'b0), .PAD (RMII_MDC), .C (UNCONNECTED2713));
  PDDW16DGZ_G uPAD_QSPI_nCS(.REN (1'b1), .I (bsp_qspi_ncs_out), .OEN
       (1'b0), .PAD (QSPI_nCS), .C (UNCONNECTED2712));
  PDDW16DGZ_G uPAD_QSPI_SCLK(.REN (1'b1), .I (bsp_qspi_sclk_out), .OEN
       (1'b0), .PAD (QSPI_SCLK), .C (UNCONNECTED2711));
  PDDW16DGZ_G uPAD_QSPI_IO_3(.REN (1'b1), .I (bsp_qspi_io_3_out), .OEN
       (n_16596), .PAD (QSPI_IO[3]), .C (bsp_qspi_io_3_in));
  PDDW16DGZ_G uPAD_QSPI_IO_2(.REN (1'b1), .I (bsp_qspi_io_2_out), .OEN
       (n_16595), .PAD (QSPI_IO[2]), .C (bsp_qspi_io_2_in));
  PDDW16DGZ_G uPAD_QSPI_IO_1(.REN (1'b1), .I (bsp_qspi_io_1_out), .OEN
       (n_16594), .PAD (QSPI_IO[1]), .C (bsp_qspi_io_1_in));
  PDDW16DGZ_G uPAD_QSPI_IO_0(.REN (1'b1), .I (bsp_qspi_io_0_out), .OEN
       (n_16593), .PAD (QSPI_IO[0]), .C (bsp_qspi_io_0_in));
  PDDW16DGZ_G uPAD_TL_RX_0(.REN (1'b1), .I (1'b0), .OEN (1'b1), .PAD
       (TL_RX[0]), .C (bsp_tl_rx_0_in));
  PDDW16DGZ_G uPAD_TL_RX_1(.REN (1'b1), .I (1'b0), .OEN (1'b1), .PAD
       (TL_RX[1]), .C (bsp_tl_rx_1_in));
  PDDW16DGZ_G uPAD_TL_RX_2(.REN (1'b1), .I (1'b0), .OEN (1'b1), .PAD
       (TL_RX[2]), .C (bsp_tl_rx_2_in));
  PDDW16DGZ_G uPAD_TL_RX_3(.REN (1'b1), .I (1'b0), .OEN (1'b1), .PAD
       (TL_RX[3]), .C (bsp_tl_rx_3_in));
  PDDW16DGZ_G uPAD_TL_CLK_RX(.REN (1'b1), .I (1'b0), .OEN (1'b1), .PAD
       (TL_CLK_RX), .C (bsp_tl_clk_rx_in));
  PDDW16DGZ_G uPAD_TL_RX_4(.REN (1'b1), .I (1'b0), .OEN (1'b1), .PAD
       (TL_RX[4]), .C (bsp_tl_rx_4_in));
  PDDW16DGZ_G uPAD_TL_RX_5(.REN (1'b1), .I (1'b0), .OEN (1'b1), .PAD
       (TL_RX[5]), .C (bsp_tl_rx_5_in));
  PDDW16DGZ_G uPAD_TL_RX_6(.REN (1'b1), .I (1'b0), .OEN (1'b1), .PAD
       (TL_RX[6]), .C (bsp_tl_rx_6_in));
  PDDW16DGZ_G uPAD_TL_RX_7(.REN (1'b1), .I (1'b0), .OEN (1'b1), .PAD
       (TL_RX[7]), .C (bsp_tl_rx_7_in));
  PDUW16DGZ_G uPAD_I2C_SCL(.REN (1'b0), .I (1'b0), .OEN
       (bsp_i2c_scl_oe), .PAD (I2C_SCL), .C (bsp_i2c_scl_in));
  PDUW16DGZ_G uPAD_I2C_SDA(.REN (1'b0), .I (1'b0), .OEN
       (bsp_i2c_sda_oe), .PAD (I2C_SDA), .C (bsp_i2c_sda_in));
  PDDW16DGZ_G uPAD_TL_TX_0(.REN (1'b1), .I (bsp_tl_tx_0_out), .OEN
       (1'b0), .PAD (TL_TX[0]), .C (UNCONNECTED2718));
  PDDW16DGZ_G uPAD_TL_TX_1(.REN (1'b1), .I (bsp_tl_tx_1_out), .OEN
       (1'b0), .PAD (TL_TX[1]), .C (UNCONNECTED2719));
  PDDW16DGZ_G uPAD_TL_TX_2(.REN (1'b1), .I (bsp_tl_tx_2_out), .OEN
       (1'b0), .PAD (TL_TX[2]), .C (UNCONNECTED2720));
  PDDW16DGZ_G uPAD_TL_TX_3(.REN (1'b1), .I (bsp_tl_tx_3_out), .OEN
       (1'b0), .PAD (TL_TX[3]), .C (UNCONNECTED2721));
  PDDW16DGZ_G uPAD_TL_CLK_TX(.REN (1'b1), .I (bsp_tl_clk_tx_out), .OEN
       (1'b0), .PAD (TL_CLK_TX), .C (UNCONNECTED2717));
  PDDW16DGZ_G uPAD_TL_TX_4(.REN (1'b1), .I (bsp_tl_tx_4_out), .OEN
       (1'b0), .PAD (TL_TX[4]), .C (UNCONNECTED2722));
  PDDW16DGZ_G uPAD_TL_TX_5(.REN (1'b1), .I (bsp_tl_tx_5_out), .OEN
       (1'b0), .PAD (TL_TX[5]), .C (UNCONNECTED2723));
  PDDW16DGZ_G uPAD_TL_TX_6(.REN (1'b1), .I (bsp_tl_tx_6_out), .OEN
       (1'b0), .PAD (TL_TX[6]), .C (UNCONNECTED2724));
  PDDW16DGZ_G uPAD_TL_TX_7(.REN (1'b1), .I (bsp_tl_tx_7_out), .OEN
       (1'b0), .PAD (TL_TX[7]), .C (UNCONNECTED2725));
endmodule
