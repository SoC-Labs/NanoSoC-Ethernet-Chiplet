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
// MUTATION APPLIED HERE: the instantiation deleted, the module definition left behind. Genus
// leaves an unreferenced module in the netlist when its only instance is
// removed, so 'the module is present' alone does not mean the register is
// in the chip.
// -----------------------------------------------------------------------------
module nanosoc_eth_chiplet_bscan(tck, tms, tdi, trst_n, tdo, tdo_oe,
     NRST_I_pin_in, NRST_I_core_in, SWDCK_I_pin_in, SWDCK_I_core_in,
     CLK_I_pin_in, CLK_I_core_in, TEST_I_pin_in, TEST_I_core_in,
     SE_I_pin_in, SE_I_core_in, SWDIO_IO_pin_in, SWDIO_IO_core_out,
     SWDIO_IO_pad_out, SWDIO_IO_core_oe, SWDIO_IO_pad_oe,
     SWDIO_IO_core_in, HOST_IO_6_pin_in, HOST_IO_6_core_out,
     HOST_IO_6_pad_out, HOST_IO_6_core_oe, HOST_IO_6_pad_oe,
     HOST_IO_6_core_in, HOST_IO_5_pin_in, HOST_IO_5_core_out,
     HOST_IO_5_pad_out, HOST_IO_5_core_oe, HOST_IO_5_pad_oe,
     HOST_IO_5_core_in, HOST_IO_4_pin_in, HOST_IO_4_core_out,
     HOST_IO_4_pad_out, HOST_IO_4_core_oe, HOST_IO_4_pad_oe,
     HOST_IO_4_core_in, HOST_IO_3_pin_in, HOST_IO_3_core_out,
     HOST_IO_3_pad_out, HOST_IO_3_core_oe, HOST_IO_3_pad_oe,
     HOST_IO_3_core_in, HOST_IO_2_pin_in, HOST_IO_2_core_out,
     HOST_IO_2_pad_out, HOST_IO_2_core_oe, HOST_IO_2_pad_oe,
     HOST_IO_2_core_in, HOST_IO_1_pin_in, HOST_IO_1_core_out,
     HOST_IO_1_pad_out, HOST_IO_1_core_oe, HOST_IO_1_pad_oe,
     HOST_IO_1_core_in, HOST_IO_0_pin_in, HOST_IO_0_core_out,
     HOST_IO_0_pad_out, HOST_IO_0_core_oe, HOST_IO_0_pad_oe,
     HOST_IO_0_core_in, RMII_CRS_DV_pin_in, RMII_CRS_DV_core_in,
     RMII_MDIO_pin_in, RMII_MDIO_core_out, RMII_MDIO_pad_out,
     RMII_MDIO_core_oe, RMII_MDIO_pad_oe, RMII_MDIO_core_in,
     RMII_TX_EN_core_out, RMII_TX_EN_pad_out, RMII_TXD1_core_out,
     RMII_TXD1_pad_out, RMII_TXD0_core_out, RMII_TXD0_pad_out,
     RMII_RXD1_pin_in, RMII_RXD1_core_in, RMII_RXD0_pin_in,
     RMII_RXD0_core_in, RMII_REF_CLK_pin_in, RMII_REF_CLK_core_in,
     RMII_MDC_core_out, RMII_MDC_pad_out, QSPI_nCS_core_out,
     QSPI_nCS_pad_out, QSPI_SCLK_core_out, QSPI_SCLK_pad_out,
     QSPI_IO_3_pin_in, QSPI_IO_3_core_out, QSPI_IO_3_pad_out,
     QSPI_IO_3_core_oe, QSPI_IO_3_pad_oe, QSPI_IO_3_core_in,
     QSPI_IO_2_pin_in, QSPI_IO_2_core_out, QSPI_IO_2_pad_out,
     QSPI_IO_2_core_oe, QSPI_IO_2_pad_oe, QSPI_IO_2_core_in,
     QSPI_IO_1_pin_in, QSPI_IO_1_core_out, QSPI_IO_1_pad_out,
     QSPI_IO_1_core_oe, QSPI_IO_1_pad_oe, QSPI_IO_1_core_in,
     QSPI_IO_0_pin_in, QSPI_IO_0_core_out, QSPI_IO_0_pad_out,
     QSPI_IO_0_core_oe, QSPI_IO_0_pad_oe, QSPI_IO_0_core_in,
     TL_RX_0_pin_in, TL_RX_0_core_in, TL_RX_1_pin_in, TL_RX_1_core_in,
     TL_RX_2_pin_in, TL_RX_2_core_in, TL_RX_3_pin_in, TL_RX_3_core_in,
     TL_CLK_RX_pin_in, TL_CLK_RX_core_in, TL_RX_4_pin_in,
     TL_RX_4_core_in, TL_RX_5_pin_in, TL_RX_5_core_in, TL_RX_6_pin_in,
     TL_RX_6_core_in, TL_RX_7_pin_in, TL_RX_7_core_in, I2C_SCL_pin_in,
     I2C_SCL_core_oe, I2C_SCL_pad_oe, I2C_SCL_core_in, I2C_SDA_pin_in,
     I2C_SDA_core_oe, I2C_SDA_pad_oe, I2C_SDA_core_in,
     TL_TX_0_core_out, TL_TX_0_pad_out, TL_TX_1_core_out,
     TL_TX_1_pad_out, TL_TX_2_core_out, TL_TX_2_pad_out,
     TL_TX_3_core_out, TL_TX_3_pad_out, TL_CLK_TX_core_out,
     TL_CLK_TX_pad_out, TL_TX_4_core_out, TL_TX_4_pad_out,
     TL_TX_5_core_out, TL_TX_5_pad_out, TL_TX_6_core_out,
     TL_TX_6_pad_out, TL_TX_7_core_out, TL_TX_7_pad_out);
  input tck, tms, tdi, trst_n, NRST_I_pin_in, SWDCK_I_pin_in,
       CLK_I_pin_in, TEST_I_pin_in, SE_I_pin_in, SWDIO_IO_pin_in,
       SWDIO_IO_core_out, SWDIO_IO_core_oe, HOST_IO_6_pin_in,
       HOST_IO_6_core_out, HOST_IO_6_core_oe, HOST_IO_5_pin_in,
       HOST_IO_5_core_out, HOST_IO_5_core_oe, HOST_IO_4_pin_in,
       HOST_IO_4_core_out, HOST_IO_4_core_oe, HOST_IO_3_pin_in,
       HOST_IO_3_core_out, HOST_IO_3_core_oe, HOST_IO_2_pin_in,
       HOST_IO_2_core_out, HOST_IO_2_core_oe, HOST_IO_1_pin_in,
       HOST_IO_1_core_out, HOST_IO_1_core_oe, HOST_IO_0_pin_in,
       HOST_IO_0_core_out, HOST_IO_0_core_oe, RMII_CRS_DV_pin_in,
       RMII_MDIO_pin_in, RMII_MDIO_core_out, RMII_MDIO_core_oe,
       RMII_TX_EN_core_out, RMII_TXD1_core_out, RMII_TXD0_core_out,
       RMII_RXD1_pin_in, RMII_RXD0_pin_in, RMII_REF_CLK_pin_in,
       RMII_MDC_core_out, QSPI_nCS_core_out, QSPI_SCLK_core_out,
       QSPI_IO_3_pin_in, QSPI_IO_3_core_out, QSPI_IO_3_core_oe,
       QSPI_IO_2_pin_in, QSPI_IO_2_core_out, QSPI_IO_2_core_oe,
       QSPI_IO_1_pin_in, QSPI_IO_1_core_out, QSPI_IO_1_core_oe,
       QSPI_IO_0_pin_in, QSPI_IO_0_core_out, QSPI_IO_0_core_oe,
       TL_RX_0_pin_in, TL_RX_1_pin_in, TL_RX_2_pin_in, TL_RX_3_pin_in,
       TL_CLK_RX_pin_in, TL_RX_4_pin_in, TL_RX_5_pin_in,
       TL_RX_6_pin_in, TL_RX_7_pin_in, I2C_SCL_pin_in, I2C_SCL_core_oe,
       I2C_SDA_pin_in, I2C_SDA_core_oe, TL_TX_0_core_out,
       TL_TX_1_core_out, TL_TX_2_core_out, TL_TX_3_core_out,
       TL_CLK_TX_core_out, TL_TX_4_core_out, TL_TX_5_core_out,
       TL_TX_6_core_out, TL_TX_7_core_out;
  output tdo, tdo_oe, NRST_I_core_in, SWDCK_I_core_in, CLK_I_core_in,
       TEST_I_core_in, SE_I_core_in, SWDIO_IO_pad_out, SWDIO_IO_pad_oe,
       SWDIO_IO_core_in, HOST_IO_6_pad_out, HOST_IO_6_pad_oe,
       HOST_IO_6_core_in, HOST_IO_5_pad_out, HOST_IO_5_pad_oe,
       HOST_IO_5_core_in, HOST_IO_4_pad_out, HOST_IO_4_pad_oe,
       HOST_IO_4_core_in, HOST_IO_3_pad_out, HOST_IO_3_pad_oe,
       HOST_IO_3_core_in, HOST_IO_2_pad_out, HOST_IO_2_pad_oe,
       HOST_IO_2_core_in, HOST_IO_1_pad_out, HOST_IO_1_pad_oe,
       HOST_IO_1_core_in, HOST_IO_0_pad_out, HOST_IO_0_pad_oe,
       HOST_IO_0_core_in, RMII_CRS_DV_core_in, RMII_MDIO_pad_out,
       RMII_MDIO_pad_oe, RMII_MDIO_core_in, RMII_TX_EN_pad_out,
       RMII_TXD1_pad_out, RMII_TXD0_pad_out, RMII_RXD1_core_in,
       RMII_RXD0_core_in, RMII_REF_CLK_core_in, RMII_MDC_pad_out,
       QSPI_nCS_pad_out, QSPI_SCLK_pad_out, QSPI_IO_3_pad_out,
       QSPI_IO_3_pad_oe, QSPI_IO_3_core_in, QSPI_IO_2_pad_out,
       QSPI_IO_2_pad_oe, QSPI_IO_2_core_in, QSPI_IO_1_pad_out,
       QSPI_IO_1_pad_oe, QSPI_IO_1_core_in, QSPI_IO_0_pad_out,
       QSPI_IO_0_pad_oe, QSPI_IO_0_core_in, TL_RX_0_core_in,
       TL_RX_1_core_in, TL_RX_2_core_in, TL_RX_3_core_in,
       TL_CLK_RX_core_in, TL_RX_4_core_in, TL_RX_5_core_in,
       TL_RX_6_core_in, TL_RX_7_core_in, I2C_SCL_pad_oe,
       I2C_SCL_core_in, I2C_SDA_pad_oe, I2C_SDA_core_in,
       TL_TX_0_pad_out, TL_TX_1_pad_out, TL_TX_2_pad_out,
       TL_TX_3_pad_out, TL_CLK_TX_pad_out, TL_TX_4_pad_out,
       TL_TX_5_pad_out, TL_TX_6_pad_out, TL_TX_7_pad_out;
  wire tck, tms, tdi, trst_n, NRST_I_pin_in, SWDCK_I_pin_in,
       CLK_I_pin_in, TEST_I_pin_in, SE_I_pin_in, SWDIO_IO_pin_in,
       SWDIO_IO_core_out, SWDIO_IO_core_oe, HOST_IO_6_pin_in,
       HOST_IO_6_core_out, HOST_IO_6_core_oe, HOST_IO_5_pin_in,
       HOST_IO_5_core_out, HOST_IO_5_core_oe, HOST_IO_4_pin_in,
       HOST_IO_4_core_out, HOST_IO_4_core_oe, HOST_IO_3_pin_in,
       HOST_IO_3_core_out, HOST_IO_3_core_oe, HOST_IO_2_pin_in,
       HOST_IO_2_core_out, HOST_IO_2_core_oe, HOST_IO_1_pin_in,
       HOST_IO_1_core_out, HOST_IO_1_core_oe, HOST_IO_0_pin_in,
       HOST_IO_0_core_out, HOST_IO_0_core_oe, RMII_CRS_DV_pin_in,
       RMII_MDIO_pin_in, RMII_MDIO_core_out, RMII_MDIO_core_oe,
       RMII_TX_EN_core_out, RMII_TXD1_core_out, RMII_TXD0_core_out,
       RMII_RXD1_pin_in, RMII_RXD0_pin_in, RMII_REF_CLK_pin_in,
       RMII_MDC_core_out, QSPI_nCS_core_out, QSPI_SCLK_core_out,
       QSPI_IO_3_pin_in, QSPI_IO_3_core_out, QSPI_IO_3_core_oe,
       QSPI_IO_2_pin_in, QSPI_IO_2_core_out, QSPI_IO_2_core_oe,
       QSPI_IO_1_pin_in, QSPI_IO_1_core_out, QSPI_IO_1_core_oe,
       QSPI_IO_0_pin_in, QSPI_IO_0_core_out, QSPI_IO_0_core_oe,
       TL_RX_0_pin_in, TL_RX_1_pin_in, TL_RX_2_pin_in, TL_RX_3_pin_in,
       TL_CLK_RX_pin_in, TL_RX_4_pin_in, TL_RX_5_pin_in,
       TL_RX_6_pin_in, TL_RX_7_pin_in, I2C_SCL_pin_in, I2C_SCL_core_oe,
       I2C_SDA_pin_in, I2C_SDA_core_oe, TL_TX_0_core_out,
       TL_TX_1_core_out, TL_TX_2_core_out, TL_TX_3_core_out,
       TL_CLK_TX_core_out, TL_TX_4_core_out, TL_TX_5_core_out,
       TL_TX_6_core_out, TL_TX_7_core_out;
  wire tdo, tdo_oe, NRST_I_core_in, SWDCK_I_core_in, CLK_I_core_in,
       TEST_I_core_in, SE_I_core_in, SWDIO_IO_pad_out, SWDIO_IO_pad_oe,
       SWDIO_IO_core_in, HOST_IO_6_pad_out, HOST_IO_6_pad_oe,
       HOST_IO_6_core_in, HOST_IO_5_pad_out, HOST_IO_5_pad_oe,
       HOST_IO_5_core_in, HOST_IO_4_pad_out, HOST_IO_4_pad_oe,
       HOST_IO_4_core_in, HOST_IO_3_pad_out, HOST_IO_3_pad_oe,
       HOST_IO_3_core_in, HOST_IO_2_pad_out, HOST_IO_2_pad_oe,
       HOST_IO_2_core_in, HOST_IO_1_pad_out, HOST_IO_1_pad_oe,
       HOST_IO_1_core_in, HOST_IO_0_pad_out, HOST_IO_0_pad_oe,
       HOST_IO_0_core_in, RMII_CRS_DV_core_in, RMII_MDIO_pad_out,
       RMII_MDIO_pad_oe, RMII_MDIO_core_in, RMII_TX_EN_pad_out,
       RMII_TXD1_pad_out, RMII_TXD0_pad_out, RMII_RXD1_core_in,
       RMII_RXD0_core_in, RMII_REF_CLK_core_in, RMII_MDC_pad_out,
       QSPI_nCS_pad_out, QSPI_SCLK_pad_out, QSPI_IO_3_pad_out,
       QSPI_IO_3_pad_oe, QSPI_IO_3_core_in, QSPI_IO_2_pad_out,
       QSPI_IO_2_pad_oe, QSPI_IO_2_core_in, QSPI_IO_1_pad_out,
       QSPI_IO_1_pad_oe, QSPI_IO_1_core_in, QSPI_IO_0_pad_out,
       QSPI_IO_0_pad_oe, QSPI_IO_0_core_in, TL_RX_0_core_in,
       TL_RX_1_core_in, TL_RX_2_core_in, TL_RX_3_core_in,
       TL_CLK_RX_core_in, TL_RX_4_core_in, TL_RX_5_core_in,
       TL_RX_6_core_in, TL_RX_7_core_in, I2C_SCL_pad_oe,
       I2C_SCL_core_in, I2C_SDA_pad_oe, I2C_SDA_core_in,
       TL_TX_0_pad_out, TL_TX_1_pad_out, TL_TX_2_pad_out,
       TL_TX_3_pad_out, TL_CLK_TX_pad_out, TL_TX_4_pad_out,
       TL_TX_5_pad_out, TL_TX_6_pad_out, TL_TX_7_pad_out;
  wire [31:0] idcode_q;
  wire [76:0] bsr_chain;
  wire [3:0] u_ir_insn_q;
  wire [3:0] u_ir_shift_q;
  wire [3:0] u_tap_state_q;
  wire UNCONNECTED2579, UNCONNECTED2580, UNCONNECTED2581,
       UNCONNECTED2582, UNCONNECTED2583, UNCONNECTED2584,
       UNCONNECTED2585, UNCONNECTED2586;
  wire UNCONNECTED2587, UNCONNECTED2588, UNCONNECTED2589,
       UNCONNECTED2590, UNCONNECTED2591, UNCONNECTED2592,
       UNCONNECTED2593, UNCONNECTED2594;
  wire UNCONNECTED2595, UNCONNECTED2596, UNCONNECTED2597,
       UNCONNECTED2598, UNCONNECTED2599, UNCONNECTED2600,
       UNCONNECTED2601, UNCONNECTED2602;
  wire UNCONNECTED2603, UNCONNECTED2604, UNCONNECTED2605,
       UNCONNECTED2606, UNCONNECTED2607, UNCONNECTED2608,
       UNCONNECTED2609, UNCONNECTED2610;
  wire UNCONNECTED2611, UNCONNECTED2612, UNCONNECTED2613,
       UNCONNECTED2614, UNCONNECTED2615, UNCONNECTED2616,
       UNCONNECTED2617, UNCONNECTED2618;
  wire UNCONNECTED2619, UNCONNECTED2620, UNCONNECTED2621,
       UNCONNECTED2622, UNCONNECTED2623, UNCONNECTED2624,
       UNCONNECTED2625, UNCONNECTED2626;
  wire bsr_update_dr, bypass_q, capture_dr, cg_rc_gclk, cg_rc_gclk_668,
       cg_rc_gclk_670, cg_rc_gclk_673, cg_rc_gclk_676;
  wire cg_rc_gclk_681, ir_so, n_0, n_1, n_2, n_3, n_4, n_5;
  wire n_6, n_7, n_8, n_9, n_10, n_11, n_12, n_13;
  wire n_14, n_15, n_16, n_17, n_18, n_19, n_20, n_21;
  wire n_22, n_23, n_24, n_25, n_26, n_27, n_28, n_29;
  wire n_30, n_31, n_32, n_33, n_34, n_35, n_37, n_38;
  wire n_39, n_40, n_41, n_42, n_43, n_44, n_45, n_46;
  wire n_47, n_48, n_49, n_50, n_51, n_52, n_53, n_54;
  wire n_55, n_56, n_57, n_58, n_59, n_60, n_61, n_62;
  wire n_63, n_64, n_65, n_66, n_67, n_68, n_69, n_70;
  wire n_71, n_72, n_73, n_74, n_75, n_76, n_77, n_78;
  wire n_79, n_80, n_81, n_82, n_83, n_84, n_85, n_86;
  wire n_87, n_88, n_89, n_90, n_91, n_92, n_93, n_94;
  wire n_95, n_96, n_97, n_98, n_103, n_105, n_106, n_107;
  wire n_108, n_109, n_110, n_111, n_112, n_113, n_114, n_116;
  wire u_bsc_00_NRST_I_obs_dr_en, u_bsc_05_SWDIO_IO_oe_update_q,
       u_bsc_06_SWDIO_IO_data_update_q, u_bsc_08_HOST_IO_6_oe_update_q,
       u_bsc_09_HOST_IO_6_data_update_q,
       u_bsc_11_HOST_IO_5_oe_update_q,
       u_bsc_12_HOST_IO_5_data_update_q, u_bsc_14_HOST_IO_4_oe_update_q;
  wire u_bsc_15_HOST_IO_4_data_update_q,
       u_bsc_17_HOST_IO_3_oe_update_q,
       u_bsc_18_HOST_IO_3_data_update_q,
       u_bsc_20_HOST_IO_2_oe_update_q,
       u_bsc_21_HOST_IO_2_data_update_q,
       u_bsc_23_HOST_IO_1_oe_update_q,
       u_bsc_24_HOST_IO_1_data_update_q, u_bsc_26_HOST_IO_0_oe_update_q;
  wire u_bsc_27_HOST_IO_0_data_update_q,
       u_bsc_30_RMII_MDIO_oe_update_q,
       u_bsc_31_RMII_MDIO_data_update_q,
       u_bsc_33_RMII_TX_EN_data_update_q,
       u_bsc_34_RMII_TXD1_data_update_q,
       u_bsc_35_RMII_TXD0_data_update_q,
       u_bsc_39_RMII_MDC_data_update_q, u_bsc_40_QSPI_nCS_data_update_q;
  wire u_bsc_41_QSPI_SCLK_data_update_q,
       u_bsc_42_QSPI_IO_3_oe_update_q,
       u_bsc_43_QSPI_IO_3_data_update_q,
       u_bsc_45_QSPI_IO_2_oe_update_q,
       u_bsc_46_QSPI_IO_2_data_update_q,
       u_bsc_48_QSPI_IO_1_oe_update_q,
       u_bsc_49_QSPI_IO_1_data_update_q, u_bsc_51_QSPI_IO_0_oe_update_q;
  wire u_bsc_52_QSPI_IO_0_data_update_q, u_bsc_63_I2C_SCL_oe_update_q,
       u_bsc_65_I2C_SDA_oe_update_q, u_bsc_67_TL_TX_0_data_update_q,
       u_bsc_68_TL_TX_1_data_update_q, u_bsc_69_TL_TX_2_data_update_q,
       u_bsc_70_TL_TX_3_data_update_q, u_bsc_71_TL_CLK_TX_data_update_q;
  wire u_bsc_72_TL_TX_4_data_update_q, u_bsc_73_TL_TX_5_data_update_q,
       u_bsc_74_TL_TX_6_data_update_q, u_bsc_75_TL_TX_7_data_update_q,
       u_ir_cg_rc_gclk, u_ir_cg_rc_gclk_141, u_tap_n_34, update_ir;
  assign I2C_SDA_core_in = I2C_SDA_pin_in;
  assign I2C_SCL_core_in = I2C_SCL_pin_in;
  assign TL_RX_7_core_in = TL_RX_7_pin_in;
  assign TL_RX_6_core_in = TL_RX_6_pin_in;
  assign TL_RX_5_core_in = TL_RX_5_pin_in;
  assign TL_RX_4_core_in = TL_RX_4_pin_in;
  assign TL_CLK_RX_core_in = TL_CLK_RX_pin_in;
  assign TL_RX_3_core_in = TL_RX_3_pin_in;
  assign TL_RX_2_core_in = TL_RX_2_pin_in;
  assign TL_RX_1_core_in = TL_RX_1_pin_in;
  assign TL_RX_0_core_in = TL_RX_0_pin_in;
  assign QSPI_IO_0_core_in = QSPI_IO_0_pin_in;
  assign QSPI_IO_1_core_in = QSPI_IO_1_pin_in;
  assign QSPI_IO_2_core_in = QSPI_IO_2_pin_in;
  assign QSPI_IO_3_core_in = QSPI_IO_3_pin_in;
  assign RMII_REF_CLK_core_in = RMII_REF_CLK_pin_in;
  assign RMII_RXD0_core_in = RMII_RXD0_pin_in;
  assign RMII_RXD1_core_in = RMII_RXD1_pin_in;
  assign RMII_MDIO_core_in = RMII_MDIO_pin_in;
  assign RMII_CRS_DV_core_in = RMII_CRS_DV_pin_in;
  assign HOST_IO_2_core_in = HOST_IO_2_pin_in;
  assign HOST_IO_3_core_in = HOST_IO_3_pin_in;
  assign HOST_IO_4_core_in = HOST_IO_4_pin_in;
  assign HOST_IO_5_core_in = HOST_IO_5_pin_in;
  assign HOST_IO_6_core_in = HOST_IO_6_pin_in;
  assign SWDIO_IO_core_in = SWDIO_IO_pin_in;
  assign TEST_I_core_in = TEST_I_pin_in;
  assign CLK_I_core_in = CLK_I_pin_in;
  assign SWDCK_I_core_in = SWDCK_I_pin_in;
  assign NRST_I_core_in = NRST_I_pin_in;
  cg_RC_CG_MOD cg_RC_CG_HIER_INST0(.enable (u_bsc_00_NRST_I_obs_dr_en),
       .ck_in (tck), .ck_out (cg_rc_gclk), .test (1'b0));
  cg_RC_CG_MOD_1 cg_RC_CG_HIER_INST1(.enable
       (u_bsc_00_NRST_I_obs_dr_en), .ck_in (tck), .ck_out
       (cg_rc_gclk_668), .test (1'b0));
  cg_RC_CG_MOD_2 cg_RC_CG_HIER_INST2(.enable
       (u_bsc_00_NRST_I_obs_dr_en), .ck_in (tck), .ck_out
       (cg_rc_gclk_670), .test (1'b0));
  cg_RC_CG_MOD_3 cg_RC_CG_HIER_INST3(.enable (n_116), .ck_in (tck),
       .ck_out (cg_rc_gclk_673), .test (1'b0));
  cg_RC_CG_MOD_150 cg_RC_CG_HIER_INST4(.enable (bsr_update_dr), .ck_in
       (tck), .ck_out (cg_rc_gclk_676), .test (1'b0));
  cg_RC_CG_MOD_150_1 cg_RC_CG_HIER_INST5(.enable (bsr_update_dr),
       .ck_in (tck), .ck_out (cg_rc_gclk_681), .test (1'b0));
  cg_RC_CG_MOD_150_2 u_ir_cg_RC_CG_HIER_INST6(.enable (update_ir),
       .ck_in (tck), .ck_out (u_ir_cg_rc_gclk), .test (1'b0));
  cg_RC_CG_MOD_4 u_ir_cg_RC_CG_HIER_INST7(.enable (n_37), .ck_in (tck),
       .ck_out (u_ir_cg_rc_gclk_141), .test (1'b0));
  DFSND1 \idcode_q_reg[0] (.SDN (trst_n), .CP (cg_rc_gclk_673), .D
       (n_93), .Q (UNCONNECTED2579), .QN (idcode_q[0]));
  DFCNQD1 \idcode_q_reg[1] (.CDN (trst_n), .CP (cg_rc_gclk_673), .D
       (n_92), .Q (idcode_q[1]));
  DFCNQD1 \idcode_q_reg[2] (.CDN (trst_n), .CP (cg_rc_gclk_673), .D
       (n_90), .Q (idcode_q[2]));
  DFCNQD1 \idcode_q_reg[3] (.CDN (trst_n), .CP (cg_rc_gclk_673), .D
       (n_88), .Q (idcode_q[3]));
  DFCNQD1 \idcode_q_reg[4] (.CDN (trst_n), .CP (cg_rc_gclk_673), .D
       (n_87), .Q (idcode_q[4]));
  DFSNQD1 \idcode_q_reg[5] (.SDN (trst_n), .CP (cg_rc_gclk_673), .D
       (n_86), .Q (idcode_q[5]));
  DFCNQD1 \idcode_q_reg[6] (.CDN (trst_n), .CP (cg_rc_gclk_673), .D
       (n_85), .Q (idcode_q[6]));
  DFSNQD1 \idcode_q_reg[7] (.SDN (trst_n), .CP (cg_rc_gclk_673), .D
       (n_84), .Q (idcode_q[7]));
  DFSNQD1 \idcode_q_reg[8] (.SDN (trst_n), .CP (cg_rc_gclk_673), .D
       (n_83), .Q (idcode_q[8]));
  DFCNQD1 \idcode_q_reg[9] (.CDN (trst_n), .CP (cg_rc_gclk_673), .D
       (n_82), .Q (idcode_q[9]));
  DFSNQD1 \idcode_q_reg[10] (.SDN (trst_n), .CP (cg_rc_gclk_673), .D
       (n_81), .Q (idcode_q[10]));
  DFCNQD1 \idcode_q_reg[11] (.CDN (trst_n), .CP (cg_rc_gclk_673), .D
       (n_80), .Q (idcode_q[11]));
  DFCNQD1 \idcode_q_reg[12] (.CDN (trst_n), .CP (cg_rc_gclk_673), .D
       (n_79), .Q (idcode_q[12]));
  DFCNQD1 \idcode_q_reg[13] (.CDN (trst_n), .CP (cg_rc_gclk_673), .D
       (n_78), .Q (idcode_q[13]));
  DFCNQD1 \idcode_q_reg[14] (.CDN (trst_n), .CP (cg_rc_gclk_673), .D
       (n_77), .Q (idcode_q[14]));
  DFCNQD1 \idcode_q_reg[15] (.CDN (trst_n), .CP (cg_rc_gclk_673), .D
       (n_76), .Q (idcode_q[15]));
  DFCNQD1 \idcode_q_reg[16] (.CDN (trst_n), .CP (cg_rc_gclk_673), .D
       (n_75), .Q (idcode_q[16]));
  DFCNQD1 \idcode_q_reg[17] (.CDN (trst_n), .CP (cg_rc_gclk_673), .D
       (n_74), .Q (idcode_q[17]));
  DFCNQD1 \idcode_q_reg[18] (.CDN (trst_n), .CP (cg_rc_gclk_673), .D
       (n_73), .Q (idcode_q[18]));
  DFCNQD1 \idcode_q_reg[19] (.CDN (trst_n), .CP (cg_rc_gclk_673), .D
       (n_72), .Q (idcode_q[19]));
  DFCNQD1 \idcode_q_reg[20] (.CDN (trst_n), .CP (cg_rc_gclk_673), .D
       (n_71), .Q (idcode_q[20]));
  DFCNQD1 \idcode_q_reg[21] (.CDN (trst_n), .CP (cg_rc_gclk_673), .D
       (n_70), .Q (idcode_q[21]));
  DFCNQD1 \idcode_q_reg[22] (.CDN (trst_n), .CP (cg_rc_gclk_673), .D
       (n_69), .Q (idcode_q[22]));
  DFCNQD1 \idcode_q_reg[23] (.CDN (trst_n), .CP (cg_rc_gclk_673), .D
       (n_68), .Q (idcode_q[23]));
  DFCNQD1 \idcode_q_reg[24] (.CDN (trst_n), .CP (cg_rc_gclk_673), .D
       (n_67), .Q (idcode_q[24]));
  DFCNQD1 \idcode_q_reg[25] (.CDN (trst_n), .CP (cg_rc_gclk_673), .D
       (n_66), .Q (idcode_q[25]));
  DFCNQD1 \idcode_q_reg[26] (.CDN (trst_n), .CP (cg_rc_gclk_673), .D
       (n_65), .Q (idcode_q[26]));
  DFCNQD1 \idcode_q_reg[27] (.CDN (trst_n), .CP (cg_rc_gclk_673), .D
       (n_64), .Q (idcode_q[27]));
  DFSNQD1 \idcode_q_reg[28] (.SDN (trst_n), .CP (cg_rc_gclk_673), .D
       (n_63), .Q (idcode_q[28]));
  DFCNQD1 \idcode_q_reg[29] (.CDN (trst_n), .CP (cg_rc_gclk_673), .D
       (n_62), .Q (idcode_q[29]));
  DFCNQD1 \idcode_q_reg[30] (.CDN (trst_n), .CP (cg_rc_gclk_673), .D
       (n_61), .Q (idcode_q[30]));
  DFCNQD1 \idcode_q_reg[31] (.CDN (trst_n), .CP (cg_rc_gclk_673), .D
       (n_58), .Q (idcode_q[31]));
  DFNCND1 tdo_oe_q_reg(.CDN (trst_n), .CPN (tck), .D (n_42), .Q
       (tdo_oe), .QN (UNCONNECTED2580));
  SDFNCND1 tdo_q_reg(.CDN (trst_n), .CPN (tck), .D (ir_so), .SI (n_98),
       .SE (n_39), .Q (tdo), .QN (UNCONNECTED2581));
  SDFCNQD1 u_bsc_00_NRST_I_obs_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk), .D (NRST_I_pin_in), .SI (tdi), .SE (n_51), .Q
       (bsr_chain[1]));
  SDFCNQD1 u_bsc_01_SWDCK_I_obs_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk), .D (SWDCK_I_pin_in), .SI (bsr_chain[1]), .SE
       (n_51), .Q (bsr_chain[2]));
  SDFCNQD1 u_bsc_02_CLK_I_obs_dr_q_reg(.CDN (trst_n), .CP (cg_rc_gclk),
       .D (CLK_I_pin_in), .SI (bsr_chain[2]), .SE (n_51), .Q
       (bsr_chain[3]));
  SDFCNQD1 u_bsc_03_TEST_I_obs_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk), .D (TEST_I_pin_in), .SI (bsr_chain[3]), .SE
       (n_51), .Q (bsr_chain[4]));
  SDFCNQD1 u_bsc_04_SE_I_obs_dr_q_reg(.CDN (trst_n), .CP (cg_rc_gclk),
       .D (SE_I_pin_in), .SI (bsr_chain[4]), .SE (n_51), .Q
       (bsr_chain[5]));
  SDFCNQD1 u_bsc_05_SWDIO_IO_oe_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk), .D (SWDIO_IO_core_oe), .SI (bsr_chain[5]), .SE
       (n_51), .Q (bsr_chain[6]));
  DFNCND1 u_bsc_05_SWDIO_IO_oe_update_q_reg(.CDN (trst_n), .CPN
       (cg_rc_gclk_676), .D (bsr_chain[6]), .Q
       (u_bsc_05_SWDIO_IO_oe_update_q), .QN (UNCONNECTED2582));
  SDFCNQD1 u_bsc_06_SWDIO_IO_data_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk), .D (SWDIO_IO_core_out), .SI (bsr_chain[6]), .SE
       (n_51), .Q (bsr_chain[7]));
  DFNCND1 u_bsc_06_SWDIO_IO_data_update_q_reg(.CDN (trst_n), .CPN
       (cg_rc_gclk_676), .D (bsr_chain[7]), .Q
       (u_bsc_06_SWDIO_IO_data_update_q), .QN (UNCONNECTED2583));
  SDFCNQD1 u_bsc_07_SWDIO_IO_obs_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk), .D (SWDIO_IO_pin_in), .SI (bsr_chain[7]), .SE
       (n_51), .Q (bsr_chain[8]));
  SDFCNQD1 u_bsc_08_HOST_IO_6_oe_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk), .D (HOST_IO_6_core_oe), .SI (bsr_chain[8]), .SE
       (n_51), .Q (bsr_chain[9]));
  DFNCND1 u_bsc_08_HOST_IO_6_oe_update_q_reg(.CDN (trst_n), .CPN
       (cg_rc_gclk_676), .D (bsr_chain[9]), .Q (UNCONNECTED2584), .QN
       (u_bsc_08_HOST_IO_6_oe_update_q));
  SDFCNQD1 u_bsc_09_HOST_IO_6_data_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk), .D (HOST_IO_6_core_out), .SI (bsr_chain[9]), .SE
       (n_51), .Q (bsr_chain[10]));
  DFNCND1 u_bsc_09_HOST_IO_6_data_update_q_reg(.CDN (trst_n), .CPN
       (cg_rc_gclk_676), .D (bsr_chain[10]), .Q
       (u_bsc_09_HOST_IO_6_data_update_q), .QN (UNCONNECTED2585));
  SDFCNQD1 u_bsc_10_HOST_IO_6_obs_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk), .D (HOST_IO_6_pin_in), .SI (bsr_chain[10]), .SE
       (n_51), .Q (bsr_chain[11]));
  SDFCNQD1 u_bsc_11_HOST_IO_5_oe_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk), .D (HOST_IO_5_core_oe), .SI (bsr_chain[11]), .SE
       (n_51), .Q (bsr_chain[12]));
  DFNCND1 u_bsc_11_HOST_IO_5_oe_update_q_reg(.CDN (trst_n), .CPN
       (cg_rc_gclk_676), .D (bsr_chain[12]), .Q (UNCONNECTED2586), .QN
       (u_bsc_11_HOST_IO_5_oe_update_q));
  SDFCNQD1 u_bsc_12_HOST_IO_5_data_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk), .D (HOST_IO_5_core_out), .SI (bsr_chain[12]), .SE
       (n_51), .Q (bsr_chain[13]));
  DFNCND1 u_bsc_12_HOST_IO_5_data_update_q_reg(.CDN (trst_n), .CPN
       (cg_rc_gclk_676), .D (bsr_chain[13]), .Q
       (u_bsc_12_HOST_IO_5_data_update_q), .QN (UNCONNECTED2587));
  SDFCNQD1 u_bsc_13_HOST_IO_5_obs_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk), .D (HOST_IO_5_pin_in), .SI (bsr_chain[13]), .SE
       (n_51), .Q (bsr_chain[14]));
  SDFCNQD1 u_bsc_14_HOST_IO_4_oe_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk), .D (HOST_IO_4_core_oe), .SI (bsr_chain[14]), .SE
       (n_51), .Q (bsr_chain[15]));
  DFNCND1 u_bsc_14_HOST_IO_4_oe_update_q_reg(.CDN (trst_n), .CPN
       (cg_rc_gclk_676), .D (bsr_chain[15]), .Q (UNCONNECTED2588), .QN
       (u_bsc_14_HOST_IO_4_oe_update_q));
  SDFCNQD1 u_bsc_15_HOST_IO_4_data_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk), .D (HOST_IO_4_core_out), .SI (bsr_chain[15]), .SE
       (n_51), .Q (bsr_chain[16]));
  DFNCND1 u_bsc_15_HOST_IO_4_data_update_q_reg(.CDN (trst_n), .CPN
       (cg_rc_gclk_676), .D (bsr_chain[16]), .Q
       (u_bsc_15_HOST_IO_4_data_update_q), .QN (UNCONNECTED2589));
  SDFCNQD1 u_bsc_16_HOST_IO_4_obs_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk), .D (HOST_IO_4_pin_in), .SI (bsr_chain[16]), .SE
       (n_51), .Q (bsr_chain[17]));
  SDFCNQD1 u_bsc_17_HOST_IO_3_oe_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk), .D (HOST_IO_3_core_oe), .SI (bsr_chain[17]), .SE
       (n_51), .Q (bsr_chain[18]));
  DFNCND1 u_bsc_17_HOST_IO_3_oe_update_q_reg(.CDN (trst_n), .CPN
       (cg_rc_gclk_676), .D (bsr_chain[18]), .Q (UNCONNECTED2590), .QN
       (u_bsc_17_HOST_IO_3_oe_update_q));
  SDFCNQD1 u_bsc_18_HOST_IO_3_data_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk), .D (HOST_IO_3_core_out), .SI (bsr_chain[18]), .SE
       (n_51), .Q (bsr_chain[19]));
  DFNCND1 u_bsc_18_HOST_IO_3_data_update_q_reg(.CDN (trst_n), .CPN
       (cg_rc_gclk_676), .D (bsr_chain[19]), .Q
       (u_bsc_18_HOST_IO_3_data_update_q), .QN (UNCONNECTED2591));
  SDFCNQD1 u_bsc_19_HOST_IO_3_obs_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk), .D (HOST_IO_3_pin_in), .SI (bsr_chain[19]), .SE
       (n_51), .Q (bsr_chain[20]));
  DFCNQD1 u_bsc_20_HOST_IO_2_oe_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk), .D (n_89), .Q (bsr_chain[21]));
  DFNCND1 u_bsc_20_HOST_IO_2_oe_update_q_reg(.CDN (trst_n), .CPN
       (cg_rc_gclk_676), .D (bsr_chain[21]), .Q (UNCONNECTED2592), .QN
       (u_bsc_20_HOST_IO_2_oe_update_q));
  DFCNQD1 u_bsc_21_HOST_IO_2_data_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk), .D (n_91), .Q (bsr_chain[22]));
  DFNCND1 u_bsc_21_HOST_IO_2_data_update_q_reg(.CDN (trst_n), .CPN
       (cg_rc_gclk_676), .D (bsr_chain[22]), .Q
       (u_bsc_21_HOST_IO_2_data_update_q), .QN (UNCONNECTED2593));
  SDFCNQD1 u_bsc_22_HOST_IO_2_obs_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk), .D (HOST_IO_2_pin_in), .SI (bsr_chain[22]), .SE
       (n_51), .Q (bsr_chain[23]));
  DFCNQD1 u_bsc_23_HOST_IO_1_oe_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk), .D (n_94), .Q (bsr_chain[24]));
  DFNCND1 u_bsc_23_HOST_IO_1_oe_update_q_reg(.CDN (trst_n), .CPN
       (cg_rc_gclk_676), .D (bsr_chain[24]), .Q (UNCONNECTED2594), .QN
       (u_bsc_23_HOST_IO_1_oe_update_q));
  SDFCNQD1 u_bsc_24_HOST_IO_1_data_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk), .D (HOST_IO_1_core_out), .SI (bsr_chain[24]), .SE
       (n_51), .Q (bsr_chain[25]));
  DFNCND1 u_bsc_24_HOST_IO_1_data_update_q_reg(.CDN (trst_n), .CPN
       (cg_rc_gclk_676), .D (bsr_chain[25]), .Q (UNCONNECTED2595), .QN
       (u_bsc_24_HOST_IO_1_data_update_q));
  SDFCNQD1 u_bsc_25_HOST_IO_1_obs_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk), .D (HOST_IO_1_pin_in), .SI (bsr_chain[25]), .SE
       (n_51), .Q (bsr_chain[26]));
  DFCNQD1 u_bsc_26_HOST_IO_0_oe_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk_668), .D (n_95), .Q (bsr_chain[27]));
  DFNCND1 u_bsc_26_HOST_IO_0_oe_update_q_reg(.CDN (trst_n), .CPN
       (cg_rc_gclk_676), .D (bsr_chain[27]), .Q (UNCONNECTED2596), .QN
       (u_bsc_26_HOST_IO_0_oe_update_q));
  SDFCNQD1 u_bsc_27_HOST_IO_0_data_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk_668), .D (HOST_IO_0_core_out), .SI (bsr_chain[27]),
       .SE (n_51), .Q (bsr_chain[28]));
  DFNCND1 u_bsc_27_HOST_IO_0_data_update_q_reg(.CDN (trst_n), .CPN
       (cg_rc_gclk_676), .D (bsr_chain[28]), .Q
       (u_bsc_27_HOST_IO_0_data_update_q), .QN (UNCONNECTED2597));
  SDFCNQD1 u_bsc_28_HOST_IO_0_obs_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk_668), .D (HOST_IO_0_pin_in), .SI (bsr_chain[28]),
       .SE (n_51), .Q (bsr_chain[29]));
  SDFCNQD1 u_bsc_29_RMII_CRS_DV_obs_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk_668), .D (RMII_CRS_DV_pin_in), .SI (bsr_chain[29]),
       .SE (n_51), .Q (bsr_chain[30]));
  SDFCNQD1 u_bsc_30_RMII_MDIO_oe_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk_668), .D (RMII_MDIO_core_oe), .SI (bsr_chain[30]),
       .SE (n_51), .Q (bsr_chain[31]));
  DFNCND1 u_bsc_30_RMII_MDIO_oe_update_q_reg(.CDN (trst_n), .CPN
       (cg_rc_gclk_676), .D (bsr_chain[31]), .Q (UNCONNECTED2598), .QN
       (u_bsc_30_RMII_MDIO_oe_update_q));
  SDFCNQD1 u_bsc_31_RMII_MDIO_data_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk_668), .D (RMII_MDIO_core_out), .SI (bsr_chain[31]),
       .SE (n_51), .Q (bsr_chain[32]));
  DFNCND1 u_bsc_31_RMII_MDIO_data_update_q_reg(.CDN (trst_n), .CPN
       (cg_rc_gclk_676), .D (bsr_chain[32]), .Q
       (u_bsc_31_RMII_MDIO_data_update_q), .QN (UNCONNECTED2599));
  SDFCNQD1 u_bsc_32_RMII_MDIO_obs_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk_668), .D (RMII_MDIO_pin_in), .SI (bsr_chain[32]),
       .SE (n_51), .Q (bsr_chain[33]));
  SDFCNQD1 u_bsc_33_RMII_TX_EN_data_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk_668), .D (RMII_TX_EN_core_out), .SI (bsr_chain[33]),
       .SE (n_51), .Q (bsr_chain[34]));
  DFNCND1 u_bsc_33_RMII_TX_EN_data_update_q_reg(.CDN (trst_n), .CPN
       (cg_rc_gclk_676), .D (bsr_chain[34]), .Q (UNCONNECTED2600), .QN
       (u_bsc_33_RMII_TX_EN_data_update_q));
  SDFCNQD1 u_bsc_34_RMII_TXD1_data_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk_668), .D (RMII_TXD1_core_out), .SI (bsr_chain[34]),
       .SE (n_51), .Q (bsr_chain[35]));
  DFNCND1 u_bsc_34_RMII_TXD1_data_update_q_reg(.CDN (trst_n), .CPN
       (cg_rc_gclk_676), .D (bsr_chain[35]), .Q (UNCONNECTED2601), .QN
       (u_bsc_34_RMII_TXD1_data_update_q));
  SDFCNQD1 u_bsc_35_RMII_TXD0_data_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk_668), .D (RMII_TXD0_core_out), .SI (bsr_chain[35]),
       .SE (n_51), .Q (bsr_chain[36]));
  DFNCND1 u_bsc_35_RMII_TXD0_data_update_q_reg(.CDN (trst_n), .CPN
       (cg_rc_gclk_676), .D (bsr_chain[36]), .Q (UNCONNECTED2602), .QN
       (u_bsc_35_RMII_TXD0_data_update_q));
  SDFCNQD1 u_bsc_36_RMII_RXD1_obs_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk_668), .D (RMII_RXD1_pin_in), .SI (bsr_chain[36]),
       .SE (n_51), .Q (bsr_chain[37]));
  SDFCNQD1 u_bsc_37_RMII_RXD0_obs_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk_668), .D (RMII_RXD0_pin_in), .SI (bsr_chain[37]),
       .SE (n_51), .Q (bsr_chain[38]));
  SDFCNQD1 u_bsc_38_RMII_REF_CLK_obs_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk_668), .D (RMII_REF_CLK_pin_in), .SI (bsr_chain[38]),
       .SE (n_51), .Q (bsr_chain[39]));
  SDFCNQD1 u_bsc_39_RMII_MDC_data_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk_668), .D (RMII_MDC_core_out), .SI (bsr_chain[39]),
       .SE (n_51), .Q (bsr_chain[40]));
  DFNCND1 u_bsc_39_RMII_MDC_data_update_q_reg(.CDN (trst_n), .CPN
       (cg_rc_gclk_676), .D (bsr_chain[40]), .Q
       (u_bsc_39_RMII_MDC_data_update_q), .QN (UNCONNECTED2603));
  SDFCNQD1 u_bsc_40_QSPI_nCS_data_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk_668), .D (QSPI_nCS_core_out), .SI (bsr_chain[40]),
       .SE (n_51), .Q (bsr_chain[41]));
  DFNCND1 u_bsc_40_QSPI_nCS_data_update_q_reg(.CDN (trst_n), .CPN
       (cg_rc_gclk_681), .D (bsr_chain[41]), .Q
       (u_bsc_40_QSPI_nCS_data_update_q), .QN (UNCONNECTED2604));
  SDFCNQD1 u_bsc_41_QSPI_SCLK_data_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk_668), .D (QSPI_SCLK_core_out), .SI (bsr_chain[41]),
       .SE (n_51), .Q (bsr_chain[42]));
  DFNCND1 u_bsc_41_QSPI_SCLK_data_update_q_reg(.CDN (trst_n), .CPN
       (cg_rc_gclk_681), .D (bsr_chain[42]), .Q
       (u_bsc_41_QSPI_SCLK_data_update_q), .QN (UNCONNECTED2605));
  SDFCNQD1 u_bsc_42_QSPI_IO_3_oe_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk_668), .D (QSPI_IO_3_core_oe), .SI (bsr_chain[42]),
       .SE (n_51), .Q (bsr_chain[43]));
  DFNCND1 u_bsc_42_QSPI_IO_3_oe_update_q_reg(.CDN (trst_n), .CPN
       (cg_rc_gclk_681), .D (bsr_chain[43]), .Q
       (u_bsc_42_QSPI_IO_3_oe_update_q), .QN (UNCONNECTED2606));
  SDFCNQD1 u_bsc_43_QSPI_IO_3_data_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk_668), .D (QSPI_IO_3_core_out), .SI (bsr_chain[43]),
       .SE (n_51), .Q (bsr_chain[44]));
  DFNCND1 u_bsc_43_QSPI_IO_3_data_update_q_reg(.CDN (trst_n), .CPN
       (cg_rc_gclk_681), .D (bsr_chain[44]), .Q (UNCONNECTED2607), .QN
       (u_bsc_43_QSPI_IO_3_data_update_q));
  SDFCNQD1 u_bsc_44_QSPI_IO_3_obs_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk_668), .D (QSPI_IO_3_pin_in), .SI (bsr_chain[44]),
       .SE (n_51), .Q (bsr_chain[45]));
  SDFCNQD1 u_bsc_45_QSPI_IO_2_oe_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk_668), .D (QSPI_IO_2_core_oe), .SI (bsr_chain[45]),
       .SE (n_51), .Q (bsr_chain[46]));
  DFNCND1 u_bsc_45_QSPI_IO_2_oe_update_q_reg(.CDN (trst_n), .CPN
       (cg_rc_gclk_681), .D (bsr_chain[46]), .Q
       (u_bsc_45_QSPI_IO_2_oe_update_q), .QN (UNCONNECTED2608));
  SDFCNQD1 u_bsc_46_QSPI_IO_2_data_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk_668), .D (QSPI_IO_2_core_out), .SI (bsr_chain[46]),
       .SE (n_51), .Q (bsr_chain[47]));
  DFNCND1 u_bsc_46_QSPI_IO_2_data_update_q_reg(.CDN (trst_n), .CPN
       (cg_rc_gclk_681), .D (bsr_chain[47]), .Q (UNCONNECTED2609), .QN
       (u_bsc_46_QSPI_IO_2_data_update_q));
  SDFCNQD1 u_bsc_47_QSPI_IO_2_obs_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk_668), .D (QSPI_IO_2_pin_in), .SI (bsr_chain[47]),
       .SE (n_51), .Q (bsr_chain[48]));
  SDFCNQD1 u_bsc_48_QSPI_IO_1_oe_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk_668), .D (QSPI_IO_1_core_oe), .SI (bsr_chain[48]),
       .SE (n_51), .Q (bsr_chain[49]));
  DFNCND1 u_bsc_48_QSPI_IO_1_oe_update_q_reg(.CDN (trst_n), .CPN
       (cg_rc_gclk_681), .D (bsr_chain[49]), .Q
       (u_bsc_48_QSPI_IO_1_oe_update_q), .QN (UNCONNECTED2610));
  SDFCNQD1 u_bsc_49_QSPI_IO_1_data_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk_668), .D (QSPI_IO_1_core_out), .SI (bsr_chain[49]),
       .SE (n_51), .Q (bsr_chain[50]));
  DFNCND1 u_bsc_49_QSPI_IO_1_data_update_q_reg(.CDN (trst_n), .CPN
       (cg_rc_gclk_681), .D (bsr_chain[50]), .Q (UNCONNECTED2611), .QN
       (u_bsc_49_QSPI_IO_1_data_update_q));
  SDFCNQD1 u_bsc_50_QSPI_IO_1_obs_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk_668), .D (QSPI_IO_1_pin_in), .SI (bsr_chain[50]),
       .SE (n_51), .Q (bsr_chain[51]));
  SDFCNQD1 u_bsc_51_QSPI_IO_0_oe_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk_670), .D (QSPI_IO_0_core_oe), .SI (bsr_chain[51]),
       .SE (n_51), .Q (bsr_chain[52]));
  DFNCND1 u_bsc_51_QSPI_IO_0_oe_update_q_reg(.CDN (trst_n), .CPN
       (cg_rc_gclk_681), .D (bsr_chain[52]), .Q
       (u_bsc_51_QSPI_IO_0_oe_update_q), .QN (UNCONNECTED2612));
  SDFCNQD1 u_bsc_52_QSPI_IO_0_data_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk_670), .D (QSPI_IO_0_core_out), .SI (bsr_chain[52]),
       .SE (n_51), .Q (bsr_chain[53]));
  DFNCND1 u_bsc_52_QSPI_IO_0_data_update_q_reg(.CDN (trst_n), .CPN
       (cg_rc_gclk_681), .D (bsr_chain[53]), .Q (UNCONNECTED2613), .QN
       (u_bsc_52_QSPI_IO_0_data_update_q));
  SDFCNQD1 u_bsc_53_QSPI_IO_0_obs_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk_670), .D (QSPI_IO_0_pin_in), .SI (bsr_chain[53]),
       .SE (n_51), .Q (bsr_chain[54]));
  SDFCNQD1 u_bsc_54_TL_RX_0_obs_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk_670), .D (TL_RX_0_pin_in), .SI (bsr_chain[54]), .SE
       (n_51), .Q (bsr_chain[55]));
  SDFCNQD1 u_bsc_55_TL_RX_1_obs_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk_670), .D (TL_RX_1_pin_in), .SI (bsr_chain[55]), .SE
       (n_51), .Q (bsr_chain[56]));
  SDFCNQD1 u_bsc_56_TL_RX_2_obs_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk_670), .D (TL_RX_2_pin_in), .SI (bsr_chain[56]), .SE
       (n_51), .Q (bsr_chain[57]));
  SDFCNQD1 u_bsc_57_TL_RX_3_obs_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk_670), .D (TL_RX_3_pin_in), .SI (bsr_chain[57]), .SE
       (n_51), .Q (bsr_chain[58]));
  SDFCNQD1 u_bsc_58_TL_CLK_RX_obs_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk_670), .D (TL_CLK_RX_pin_in), .SI (bsr_chain[58]),
       .SE (n_51), .Q (bsr_chain[59]));
  SDFCNQD1 u_bsc_59_TL_RX_4_obs_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk_670), .D (TL_RX_4_pin_in), .SI (bsr_chain[59]), .SE
       (n_51), .Q (bsr_chain[60]));
  SDFCNQD1 u_bsc_60_TL_RX_5_obs_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk_670), .D (TL_RX_5_pin_in), .SI (bsr_chain[60]), .SE
       (n_51), .Q (bsr_chain[61]));
  SDFCNQD1 u_bsc_61_TL_RX_6_obs_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk_670), .D (TL_RX_6_pin_in), .SI (bsr_chain[61]), .SE
       (n_51), .Q (bsr_chain[62]));
  SDFCNQD1 u_bsc_62_TL_RX_7_obs_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk_670), .D (TL_RX_7_pin_in), .SI (bsr_chain[62]), .SE
       (n_51), .Q (bsr_chain[63]));
  SDFCNQD1 u_bsc_63_I2C_SCL_oe_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk_670), .D (I2C_SCL_core_oe), .SI (bsr_chain[63]), .SE
       (n_51), .Q (bsr_chain[64]));
  DFNCND1 u_bsc_63_I2C_SCL_oe_update_q_reg(.CDN (trst_n), .CPN
       (cg_rc_gclk_681), .D (bsr_chain[64]), .Q
       (u_bsc_63_I2C_SCL_oe_update_q), .QN (UNCONNECTED2614));
  SDFCNQD1 u_bsc_64_I2C_SCL_obs_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk_670), .D (I2C_SCL_pin_in), .SI (bsr_chain[64]), .SE
       (n_51), .Q (bsr_chain[65]));
  SDFCNQD1 u_bsc_65_I2C_SDA_oe_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk_670), .D (I2C_SDA_core_oe), .SI (bsr_chain[65]), .SE
       (n_51), .Q (bsr_chain[66]));
  DFNCND1 u_bsc_65_I2C_SDA_oe_update_q_reg(.CDN (trst_n), .CPN
       (cg_rc_gclk_681), .D (bsr_chain[66]), .Q
       (u_bsc_65_I2C_SDA_oe_update_q), .QN (UNCONNECTED2615));
  SDFCNQD1 u_bsc_66_I2C_SDA_obs_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk_670), .D (I2C_SDA_pin_in), .SI (bsr_chain[66]), .SE
       (n_51), .Q (bsr_chain[67]));
  SDFCNQD1 u_bsc_67_TL_TX_0_data_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk_670), .D (TL_TX_0_core_out), .SI (bsr_chain[67]),
       .SE (n_51), .Q (bsr_chain[68]));
  DFNCND1 u_bsc_67_TL_TX_0_data_update_q_reg(.CDN (trst_n), .CPN
       (cg_rc_gclk_681), .D (bsr_chain[68]), .Q
       (u_bsc_67_TL_TX_0_data_update_q), .QN (UNCONNECTED2616));
  SDFCNQD1 u_bsc_68_TL_TX_1_data_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk_670), .D (TL_TX_1_core_out), .SI (bsr_chain[68]),
       .SE (n_51), .Q (bsr_chain[69]));
  DFNCND1 u_bsc_68_TL_TX_1_data_update_q_reg(.CDN (trst_n), .CPN
       (cg_rc_gclk_681), .D (bsr_chain[69]), .Q
       (u_bsc_68_TL_TX_1_data_update_q), .QN (UNCONNECTED2617));
  SDFCNQD1 u_bsc_69_TL_TX_2_data_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk_670), .D (TL_TX_2_core_out), .SI (bsr_chain[69]),
       .SE (n_51), .Q (bsr_chain[70]));
  DFNCND1 u_bsc_69_TL_TX_2_data_update_q_reg(.CDN (trst_n), .CPN
       (cg_rc_gclk_681), .D (bsr_chain[70]), .Q
       (u_bsc_69_TL_TX_2_data_update_q), .QN (UNCONNECTED2618));
  SDFCNQD1 u_bsc_70_TL_TX_3_data_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk_670), .D (TL_TX_3_core_out), .SI (bsr_chain[70]),
       .SE (n_51), .Q (bsr_chain[71]));
  DFNCND1 u_bsc_70_TL_TX_3_data_update_q_reg(.CDN (trst_n), .CPN
       (cg_rc_gclk_681), .D (bsr_chain[71]), .Q
       (u_bsc_70_TL_TX_3_data_update_q), .QN (UNCONNECTED2619));
  SDFCNQD1 u_bsc_71_TL_CLK_TX_data_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk_670), .D (TL_CLK_TX_core_out), .SI (bsr_chain[71]),
       .SE (n_51), .Q (bsr_chain[72]));
  DFNCND1 u_bsc_71_TL_CLK_TX_data_update_q_reg(.CDN (trst_n), .CPN
       (cg_rc_gclk_681), .D (bsr_chain[72]), .Q
       (u_bsc_71_TL_CLK_TX_data_update_q), .QN (UNCONNECTED2620));
  SDFCNQD1 u_bsc_72_TL_TX_4_data_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk_670), .D (TL_TX_4_core_out), .SI (bsr_chain[72]),
       .SE (n_51), .Q (bsr_chain[73]));
  DFNCND1 u_bsc_72_TL_TX_4_data_update_q_reg(.CDN (trst_n), .CPN
       (cg_rc_gclk_681), .D (bsr_chain[73]), .Q
       (u_bsc_72_TL_TX_4_data_update_q), .QN (UNCONNECTED2621));
  SDFCNQD1 u_bsc_73_TL_TX_5_data_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk_670), .D (TL_TX_5_core_out), .SI (bsr_chain[73]),
       .SE (n_51), .Q (bsr_chain[74]));
  DFNCND1 u_bsc_73_TL_TX_5_data_update_q_reg(.CDN (trst_n), .CPN
       (cg_rc_gclk_681), .D (bsr_chain[74]), .Q
       (u_bsc_73_TL_TX_5_data_update_q), .QN (UNCONNECTED2622));
  SDFCNQD1 u_bsc_74_TL_TX_6_data_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk_670), .D (TL_TX_6_core_out), .SI (bsr_chain[74]),
       .SE (n_51), .Q (bsr_chain[75]));
  DFNCND1 u_bsc_74_TL_TX_6_data_update_q_reg(.CDN (trst_n), .CPN
       (cg_rc_gclk_681), .D (bsr_chain[75]), .Q
       (u_bsc_74_TL_TX_6_data_update_q), .QN (UNCONNECTED2623));
  SDFCNQD1 u_bsc_75_TL_TX_7_data_dr_q_reg(.CDN (trst_n), .CP
       (cg_rc_gclk_670), .D (TL_TX_7_core_out), .SI (bsr_chain[75]),
       .SE (n_51), .Q (bsr_chain[76]));
  DFNCND1 u_bsc_75_TL_TX_7_data_update_q_reg(.CDN (trst_n), .CPN
       (cg_rc_gclk_681), .D (bsr_chain[76]), .Q
       (u_bsc_75_TL_TX_7_data_update_q), .QN (UNCONNECTED2624));
  DFNCND1 \u_ir_insn_q_reg[0] (.CDN (n_40), .CPN (u_ir_cg_rc_gclk), .D
       (ir_so), .Q (u_ir_insn_q[0]), .QN (n_34));
  DFNSND1 \u_ir_insn_q_reg[1] (.SDN (n_40), .CPN (u_ir_cg_rc_gclk), .D
       (u_ir_shift_q[1]), .Q (UNCONNECTED2625), .QN (u_ir_insn_q[1]));
  DFNCND1 \u_ir_insn_q_reg[2] (.CDN (n_40), .CPN (u_ir_cg_rc_gclk), .D
       (u_ir_shift_q[2]), .Q (UNCONNECTED2626), .QN (u_ir_insn_q[2]));
  DFNCND1 \u_ir_insn_q_reg[3] (.CDN (n_40), .CPN (u_ir_cg_rc_gclk), .D
       (u_ir_shift_q[3]), .Q (u_ir_insn_q[3]), .QN (n_33));
  DFSNQD1 \u_ir_shift_q_reg[0] (.SDN (n_40), .CP (u_ir_cg_rc_gclk_141),
       .D (n_47), .Q (ir_so));
  DFCNQD1 \u_ir_shift_q_reg[1] (.CDN (n_40), .CP (u_ir_cg_rc_gclk_141),
       .D (n_45), .Q (u_ir_shift_q[1]));
  DFCNQD1 \u_ir_shift_q_reg[2] (.CDN (n_40), .CP (u_ir_cg_rc_gclk_141),
       .D (n_44), .Q (u_ir_shift_q[2]));
  DFCNQD1 \u_ir_shift_q_reg[3] (.CDN (n_40), .CP (u_ir_cg_rc_gclk_141),
       .D (n_43), .Q (u_ir_shift_q[3]));
  AO31D1 g4794__6260(.A1 (bypass_q), .A2 (n_52), .A3 (n_48), .B (n_97),
       .Z (n_98));
  CKMUX2D2 g4795__4319(.I0 (u_bsc_75_TL_TX_7_data_update_q), .I1
       (TL_TX_7_core_out), .S (n_103), .Z (TL_TX_7_pad_out));
  OAI22D1 g4796__8428(.A1 (n_48), .A2 (n_96), .B1 (n_52), .B2
       (idcode_q[0]), .ZN (n_97));
  CKND1 g4798(.I (bsr_chain[76]), .ZN (n_96));
  CKMUX2D2 g4800__5526(.I0 (u_bsc_74_TL_TX_6_data_update_q), .I1
       (TL_TX_6_core_out), .S (n_103), .Z (TL_TX_6_pad_out));
  CKMUX2D2 g4803__6783(.I0 (u_bsc_73_TL_TX_5_data_update_q), .I1
       (TL_TX_5_core_out), .S (n_103), .Z (TL_TX_5_pad_out));
  CKMUX2D2 g4806__3680(.I0 (u_bsc_72_TL_TX_4_data_update_q), .I1
       (TL_TX_4_core_out), .S (n_103), .Z (TL_TX_4_pad_out));
  CKMUX2D2 g4812__2802(.I0 (TL_TX_3_core_out), .I1
       (u_bsc_70_TL_TX_3_data_update_q), .S (n_57), .Z
       (TL_TX_3_pad_out));
  CKMUX2D2 g4815__1705(.I0 (TL_TX_2_core_out), .I1
       (u_bsc_69_TL_TX_2_data_update_q), .S (n_57), .Z
       (TL_TX_2_pad_out));
  CKMUX2D2 g4818__5122(.I0 (TL_TX_1_core_out), .I1
       (u_bsc_68_TL_TX_1_data_update_q), .S (n_57), .Z
       (TL_TX_1_pad_out));
  CKMUX2D2 g4821__8246(.I0 (TL_TX_0_core_out), .I1
       (u_bsc_67_TL_TX_0_data_update_q), .S (n_57), .Z
       (TL_TX_0_pad_out));
  AO221D1 g4824__7098(.A1 (n_57), .A2 (u_bsc_65_I2C_SDA_oe_update_q),
       .B1 (n_60), .B2 (I2C_SDA_core_oe), .C (n_56), .Z
       (I2C_SDA_pad_oe));
  AO221D1 g4828__6131(.A1 (n_57), .A2 (u_bsc_63_I2C_SCL_oe_update_q),
       .B1 (n_60), .B2 (I2C_SCL_core_oe), .C (n_56), .Z
       (I2C_SCL_pad_oe));
  IOA22D2 g4842__1881(.A1 (n_103), .A2 (QSPI_IO_0_core_out), .B1
       (n_103), .B2 (u_bsc_52_QSPI_IO_0_data_update_q), .ZN
       (QSPI_IO_0_pad_out));
  AO22D0 g4845__5115(.A1 (n_57), .A2 (u_bsc_51_QSPI_IO_0_oe_update_q),
       .B1 (QSPI_IO_0_core_oe), .B2 (n_60), .Z (QSPI_IO_0_pad_oe));
  IOA22D2 g4849__7482(.A1 (n_103), .A2 (QSPI_IO_1_core_out), .B1
       (n_103), .B2 (u_bsc_49_QSPI_IO_1_data_update_q), .ZN
       (QSPI_IO_1_pad_out));
  AO22D0 g4852__4733(.A1 (n_57), .A2 (u_bsc_48_QSPI_IO_1_oe_update_q),
       .B1 (QSPI_IO_1_core_oe), .B2 (n_60), .Z (QSPI_IO_1_pad_oe));
  IOA22D2 g4856__6161(.A1 (n_103), .A2 (QSPI_IO_2_core_out), .B1
       (n_103), .B2 (u_bsc_46_QSPI_IO_2_data_update_q), .ZN
       (QSPI_IO_2_pad_out));
  AO22D0 g4859__9315(.A1 (n_57), .A2 (u_bsc_45_QSPI_IO_2_oe_update_q),
       .B1 (QSPI_IO_2_core_oe), .B2 (n_60), .Z (QSPI_IO_2_pad_oe));
  IOA22D2 g4863__9945(.A1 (n_103), .A2 (QSPI_IO_3_core_out), .B1
       (n_103), .B2 (u_bsc_43_QSPI_IO_3_data_update_q), .ZN
       (QSPI_IO_3_pad_out));
  AO22D0 g4866__2883(.A1 (n_57), .A2 (u_bsc_42_QSPI_IO_3_oe_update_q),
       .B1 (QSPI_IO_3_core_oe), .B2 (n_60), .Z (QSPI_IO_3_pad_oe));
  CKMUX2D2 g4872__1666(.I0 (QSPI_nCS_core_out), .I1
       (u_bsc_40_QSPI_nCS_data_update_q), .S (n_57), .Z
       (QSPI_nCS_pad_out));
  CKMUX2D2 g4875__7410(.I0 (u_bsc_39_RMII_MDC_data_update_q), .I1
       (RMII_MDC_core_out), .S (n_103), .Z (RMII_MDC_pad_out));
  IOA22D2 g4881__6417(.A1 (n_103), .A2 (RMII_TXD0_core_out), .B1
       (n_103), .B2 (u_bsc_35_RMII_TXD0_data_update_q), .ZN
       (RMII_TXD0_pad_out));
  IOA22D2 g4884__5477(.A1 (n_103), .A2 (RMII_TXD1_core_out), .B1
       (n_103), .B2 (u_bsc_34_RMII_TXD1_data_update_q), .ZN
       (RMII_TXD1_pad_out));
  IOA22D2 g4887__2398(.A1 (n_103), .A2 (RMII_TX_EN_core_out), .B1
       (n_103), .B2 (u_bsc_33_RMII_TX_EN_data_update_q), .ZN
       (RMII_TX_EN_pad_out));
  CKMUX2D2 g4891__5107(.I0 (RMII_MDIO_core_out), .I1
       (u_bsc_31_RMII_MDIO_data_update_q), .S (n_57), .Z
       (RMII_MDIO_pad_out));
  MOAI22D0 g4894__6260(.A1 (n_103), .A2
       (u_bsc_30_RMII_MDIO_oe_update_q), .B1 (n_60), .B2
       (RMII_MDIO_core_oe), .ZN (RMII_MDIO_pad_oe));
  CKMUX2D2 g4899__4319(.I0 (u_bsc_27_HOST_IO_0_data_update_q), .I1
       (HOST_IO_0_core_out), .S (n_103), .Z (HOST_IO_0_pad_out));
  OAI21D1 g4902__8428(.A1 (n_103), .A2
       (u_bsc_26_HOST_IO_0_oe_update_q), .B (n_59), .ZN
       (HOST_IO_0_pad_oe));
  IND2D1 g4905__5526(.A1 (bsr_chain[26]), .B1 (n_51), .ZN (n_95));
  MOAI22D0 g4907__6783(.A1 (n_103), .A2
       (u_bsc_24_HOST_IO_1_data_update_q), .B1 (n_103), .B2
       (HOST_IO_1_core_out), .ZN (HOST_IO_1_pad_out));
  OAI21D0 g4910__3680(.A1 (n_103), .A2
       (u_bsc_23_HOST_IO_1_oe_update_q), .B (n_59), .ZN
       (HOST_IO_1_pad_oe));
  IND2D1 g4913__1617(.A1 (bsr_chain[23]), .B1 (n_51), .ZN (n_94));
  IND2D1 g4916__2802(.A1 (idcode_q[1]), .B1 (n_54), .ZN (n_93));
  CKAN2D2 g4917__1705(.A1 (n_57), .A2
       (u_bsc_21_HOST_IO_2_data_update_q), .Z (HOST_IO_2_pad_out));
  AN2XD1 g4921__5122(.A1 (n_54), .A2 (idcode_q[2]), .Z (n_92));
  NR2D0 g4922__8246(.A1 (n_103), .A2 (u_bsc_20_HOST_IO_2_oe_update_q),
       .ZN (HOST_IO_2_pad_oe));
  AN2XD1 g4925__7098(.A1 (n_51), .A2 (bsr_chain[21]), .Z (n_91));
  AN2XD1 g4927__6131(.A1 (n_54), .A2 (idcode_q[3]), .Z (n_90));
  AN2XD1 g4929__1881(.A1 (n_51), .A2 (bsr_chain[20]), .Z (n_89));
  AN2XD1 g4931__5115(.A1 (n_54), .A2 (idcode_q[4]), .Z (n_88));
  CKMUX2D2 g4932__7482(.I0 (u_bsc_18_HOST_IO_3_data_update_q), .I1
       (HOST_IO_3_core_out), .S (n_103), .Z (HOST_IO_3_pad_out));
  AN2XD1 g4935__4733(.A1 (n_54), .A2 (idcode_q[5]), .Z (n_87));
  MOAI22D0 g4937__6161(.A1 (n_103), .A2
       (u_bsc_17_HOST_IO_3_oe_update_q), .B1 (n_60), .B2
       (HOST_IO_3_core_oe), .ZN (HOST_IO_3_pad_oe));
  IND2D1 g4939__9315(.A1 (idcode_q[6]), .B1 (n_54), .ZN (n_86));
  AN2XD1 g4943__9945(.A1 (n_54), .A2 (idcode_q[7]), .Z (n_85));
  IND2D1 g4945__2883(.A1 (idcode_q[8]), .B1 (n_54), .ZN (n_84));
  CKMUX2D2 g4948__2346(.I0 (u_bsc_15_HOST_IO_4_data_update_q), .I1
       (HOST_IO_4_core_out), .S (n_103), .Z (HOST_IO_4_pad_out));
  IND2D1 g4949__1666(.A1 (idcode_q[9]), .B1 (n_54), .ZN (n_83));
  AN2XD1 g4953__7410(.A1 (n_54), .A2 (idcode_q[10]), .Z (n_82));
  MOAI22D0 g4954__6417(.A1 (n_103), .A2
       (u_bsc_14_HOST_IO_4_oe_update_q), .B1 (n_60), .B2
       (HOST_IO_4_core_oe), .ZN (HOST_IO_4_pad_oe));
  IND2D1 g4957__5477(.A1 (idcode_q[11]), .B1 (n_54), .ZN (n_81));
  AN2XD1 g4960__2398(.A1 (n_54), .A2 (idcode_q[12]), .Z (n_80));
  AN2XD1 g4963__5107(.A1 (n_54), .A2 (idcode_q[13]), .Z (n_79));
  CKMUX2D2 g4964__6260(.I0 (HOST_IO_5_core_out), .I1
       (u_bsc_12_HOST_IO_5_data_update_q), .S (n_57), .Z
       (HOST_IO_5_pad_out));
  AN2XD1 g4967__4319(.A1 (n_54), .A2 (idcode_q[14]), .Z (n_78));
  MOAI22D0 g4969__8428(.A1 (n_103), .A2
       (u_bsc_11_HOST_IO_5_oe_update_q), .B1 (n_60), .B2
       (HOST_IO_5_core_oe), .ZN (HOST_IO_5_pad_oe));
  AN2XD1 g4971__5526(.A1 (n_54), .A2 (idcode_q[15]), .Z (n_77));
  AN2XD1 g4975__6783(.A1 (n_54), .A2 (idcode_q[16]), .Z (n_76));
  AN2XD1 g4977__3680(.A1 (n_54), .A2 (idcode_q[17]), .Z (n_75));
  CKMUX2D2 g4980__1617(.I0 (HOST_IO_6_core_out), .I1
       (u_bsc_09_HOST_IO_6_data_update_q), .S (n_57), .Z
       (HOST_IO_6_pad_out));
  AN2XD1 g4981__2802(.A1 (n_54), .A2 (idcode_q[18]), .Z (n_74));
  AN2XD1 g4985__1705(.A1 (n_54), .A2 (idcode_q[19]), .Z (n_73));
  MOAI22D0 g4986__5122(.A1 (n_103), .A2
       (u_bsc_08_HOST_IO_6_oe_update_q), .B1 (n_60), .B2
       (HOST_IO_6_core_oe), .ZN (HOST_IO_6_pad_oe));
  AN2XD1 g4989__8246(.A1 (n_54), .A2 (idcode_q[20]), .Z (n_72));
  AN2XD1 g4992__7098(.A1 (n_54), .A2 (idcode_q[21]), .Z (n_71));
  AN2XD1 g4995__6131(.A1 (n_54), .A2 (idcode_q[22]), .Z (n_70));
  CKMUX2D2 g4996__1881(.I0 (SWDIO_IO_core_out), .I1
       (u_bsc_06_SWDIO_IO_data_update_q), .S (n_57), .Z
       (SWDIO_IO_pad_out));
  AN2XD1 g4999__5115(.A1 (n_54), .A2 (idcode_q[23]), .Z (n_69));
  AO22D0 g5001__7482(.A1 (n_57), .A2 (u_bsc_05_SWDIO_IO_oe_update_q),
       .B1 (SWDIO_IO_core_oe), .B2 (n_60), .Z (SWDIO_IO_pad_oe));
  AN2XD1 g5003__4733(.A1 (n_54), .A2 (idcode_q[24]), .Z (n_68));
  AN2XD1 g5007__6161(.A1 (n_54), .A2 (idcode_q[25]), .Z (n_67));
  AN2XD1 g5009__9315(.A1 (n_54), .A2 (idcode_q[26]), .Z (n_66));
  AN2XD1 g5012__9945(.A1 (n_54), .A2 (idcode_q[27]), .Z (n_65));
  AN2XD1 g5015__2883(.A1 (n_54), .A2 (idcode_q[28]), .Z (n_64));
  IND2D1 g5017__2346(.A1 (idcode_q[29]), .B1 (n_54), .ZN (n_63));
  AN2XD1 g5020__1666(.A1 (n_54), .A2 (idcode_q[30]), .Z (n_62));
  AN2XD1 g5023__7410(.A1 (n_54), .A2 (idcode_q[31]), .Z (n_61));
  CKND1 g5025(.I (n_60), .ZN (n_59));
  AN2XD1 g5026__6417(.A1 (n_103), .A2 (n_55), .Z (n_60));
  AN2XD1 g5027__5477(.A1 (n_54), .A2 (tdi), .Z (n_58));
  INVD3 g5028(.I (n_57), .ZN (n_103));
  CKAN2D2 g5029__2398(.A1 (n_40), .A2 (n_53), .Z (n_57));
  CKND1 g5030(.I (n_55), .ZN (n_56));
  ND4D1 g5032__5107(.A1 (n_40), .A2 (n_46), .A3 (n_34), .A4
       (u_ir_insn_q[1]), .ZN (n_55));
  AOI21D1 g5033__6260(.A1 (capture_dr), .A2 (n_108), .B (n_52), .ZN
       (n_116));
  MOAI22D0 g5034__4319(.A1 (n_105), .A2 (n_113), .B1 (n_49), .B2
       (n_34), .ZN (n_53));
  OR2D2 g5035__8428(.A1 (capture_dr), .A2 (n_52), .Z (n_54));
  INR4D0 g5036__5526(.A1 (u_tap_state_q[3]), .B1 (n_48), .B2
       (u_tap_state_q[1]), .B3 (n_109), .ZN (bsr_update_dr));
  OR3XD1 g5037__6783(.A1 (u_ir_insn_q[1]), .A2 (u_ir_insn_q[0]), .A3
       (n_113), .Z (n_52));
  IND2D1 g5038__3680(.A1 (u_ir_insn_q[1]), .B1 (u_ir_insn_q[0]), .ZN
       (n_105));
  OAI21D1 g5039__1617(.A1 (capture_dr), .A2 (n_48), .B (n_50), .ZN
       (u_bsc_00_NRST_I_obs_dr_en));
  CKND1 g5042(.I (n_51), .ZN (n_50));
  CKAN2D8 g5043__2802(.A1 (n_38), .A2 (n_49), .Z (n_51));
  CKND1 g5045(.I (n_49), .ZN (n_48));
  INR2XD0 g5046__1705(.A1 (u_ir_insn_q[1]), .B1 (n_113), .ZN (n_49));
  OR2XD1 g5048__5122(.A1 (n_41), .A2 (u_ir_shift_q[1]), .Z (n_47));
  NR2D0 g5050__8246(.A1 (u_ir_insn_q[2]), .A2 (u_ir_insn_q[3]), .ZN
       (n_46));
  CKND2D1 g5051__7098(.A1 (u_ir_insn_q[2]), .A2 (n_33), .ZN (n_113));
  INR2XD0 g5053__6131(.A1 (u_ir_shift_q[2]), .B1 (n_41), .ZN (n_45));
  INR2XD0 g5057__1881(.A1 (u_ir_shift_q[3]), .B1 (n_41), .ZN (n_44));
  INR2XD0 g5060__5115(.A1 (tdi), .B1 (n_41), .ZN (n_43));
  CKND2D1 g5061__7482(.A1 (n_41), .A2 (n_108), .ZN (n_42));
  OR3XD1 g5062__4733(.A1 (u_tap_state_q[3]), .A2 (n_1), .A3 (n_106), .Z
       (capture_dr));
  CKND2D1 g5063__6161(.A1 (n_37), .A2 (u_tap_state_q[0]), .ZN (n_41));
  AOI21D1 g5064__9315(.A1 (n_109), .A2 (u_tap_state_q[3]), .B (n_37),
       .ZN (n_39));
  OA21D1 g5065__9945(.A1 (n_111), .A2 (n_112), .B (trst_n), .Z (n_40));
  CKND1 g5066(.I (n_38), .ZN (n_108));
  NR2XD0 g5067__2883(.A1 (n_111), .A2 (n_110), .ZN (n_38));
  CKND1 g5068(.I (n_37), .ZN (u_tap_n_34));
  NR2XD0 g5069__2346(.A1 (n_107), .A2 (n_114), .ZN (update_ir));
  NR2XD0 g5070__1666(.A1 (n_107), .A2 (u_tap_state_q[2]), .ZN (n_37));
  OR2D1 g5071__7410(.A1 (u_tap_state_q[0]), .A2 (u_tap_state_q[2]), .Z
       (n_109));
  OR2XD1 g5072__6417(.A1 (u_tap_state_q[3]), .A2 (u_tap_state_q[0]), .Z
       (n_111));
  CKND2D1 g5073__5477(.A1 (u_tap_state_q[3]), .A2 (u_tap_state_q[1]),
       .ZN (n_107));
  ND2D1 g5074__2398(.A1 (n_35), .A2 (u_tap_state_q[0]), .ZN (n_106));
  CKND2D1 g5075__5107(.A1 (u_tap_state_q[0]), .A2 (u_tap_state_q[2]),
       .ZN (n_114));
  ND2D1 g5076__6260(.A1 (n_35), .A2 (n_1), .ZN (n_112));
  CKND2D1 g5077__4319(.A1 (n_1), .A2 (u_tap_state_q[2]), .ZN (n_110));
  DFCNQD1 bypass_q_reg(.CDN (trst_n), .CP (tck), .D (n_29), .Q
       (bypass_q));
  DFCNQD1 \u_tap_state_q_reg[0] (.CDN (trst_n), .CP (tck), .D (n_27),
       .Q (u_tap_state_q[0]));
  ND3D1 g3116__8428(.A1 (n_25), .A2 (capture_dr), .A3 (n_13), .ZN
       (n_32));
  OAI221D0 g3117__5526(.A1 (n_22), .A2 (n_21), .B1 (n_6), .B2 (n_15),
       .C (n_26), .ZN (n_31));
  OAI31D1 g3118__6783(.A1 (u_tap_state_q[3]), .A2 (n_114), .A3 (n_2),
       .B (n_28), .ZN (n_30));
  IAO21D1 g3119__3680(.A1 (capture_dr), .A2 (n_12), .B (n_24), .ZN
       (n_29));
  MAOI22D1 g3120__1617(.A1 (n_23), .A2 (n_16), .B1 (n_14), .B2 (n_7),
       .ZN (n_28));
  OAI22D1 g3121__2802(.A1 (n_20), .A2 (n_3), .B1 (n_11), .B2 (n_6), .ZN
       (n_27));
  OAI211D1 g3122__1705(.A1 (u_tap_state_q[2]), .A2 (n_9), .B (tms), .C
       (u_tap_state_q[3]), .ZN (n_26));
  MAOI22D1 g3123__5122(.A1 (n_18), .A2 (u_tap_state_q[2]), .B1 (n_0),
       .B2 (n_110), .ZN (n_25));
  MUX2ND0 g3124__8246(.I0 (bypass_q), .I1 (tdi), .S (n_17), .ZN (n_24));
  ND2D1 g3125__7098(.A1 (n_19), .A2 (n_6), .ZN (n_23));
  IOA21D1 g3126__6131(.A1 (n_111), .A2 (u_tap_state_q[1]), .B (n_19),
       .ZN (n_22));
  OAI22D1 g3127__1881(.A1 (n_4), .A2 (u_tap_state_q[1]), .B1 (tms), .B2
       (n_106), .ZN (n_21));
  AOI32D1 g3128__5115(.A1 (tms), .A2 (u_tap_n_34), .A3 (n_112), .B1
       (n_10), .B2 (n_8), .ZN (n_20));
  IND2D1 g3129__7482(.A1 (n_8), .B1 (n_111), .ZN (n_18));
  ND2D1 g3130__4733(.A1 (tms), .A2 (n_7), .ZN (n_19));
  NR2XD0 g3131__6161(.A1 (n_108), .A2 (n_12), .ZN (n_17));
  OAI21D1 g3132__9315(.A1 (n_1), .A2 (u_tap_state_q[2]), .B (n_110),
       .ZN (n_16));
  AOI21D1 g3133__9945(.A1 (n_114), .A2 (u_tap_state_q[1]), .B (n_11),
       .ZN (n_15));
  AOI21D1 g3134__2883(.A1 (n_112), .A2 (u_tap_state_q[3]), .B (n_5),
       .ZN (n_14));
  IND3D1 g3135__2346(.A1 (n_107), .B1 (n_114), .B2 (tms), .ZN (n_13));
  ND2D1 g3136__1666(.A1 (n_112), .A2 (n_109), .ZN (n_10));
  NR2D1 g3137__7410(.A1 (u_tap_state_q[0]), .A2 (u_tap_state_q[1]), .ZN
       (n_9));
  INR2D1 g3138__6417(.A1 (n_105), .B1 (n_113), .ZN (n_12));
  INR2D1 g3139__5477(.A1 (u_tap_state_q[0]), .B1 (n_112), .ZN (n_11));
  CKND1 g3140(.I (n_5), .ZN (n_6));
  AN2XD1 g3141__2398(.A1 (n_0), .A2 (u_tap_state_q[0]), .Z (n_4));
  NR2XD0 g3142__5107(.A1 (tms), .A2 (u_tap_state_q[3]), .ZN (n_8));
  CKND2D1 g3143__6260(.A1 (n_109), .A2 (n_114), .ZN (n_7));
  NR2XD0 g3144__4319(.A1 (tms), .A2 (n_0), .ZN (n_5));
  CKND1 g3147(.I (n_114), .ZN (n_3));
  CKND1 g3148(.I (tms), .ZN (n_2));
  DFCND1 \u_tap_state_q_reg[1] (.CDN (trst_n), .CP (tck), .D (n_31), .Q
       (u_tap_state_q[1]), .QN (n_1));
  DFCND1 \u_tap_state_q_reg[2] (.CDN (trst_n), .CP (tck), .D (n_32), .Q
       (u_tap_state_q[2]), .QN (n_35));
  DFCND1 \u_tap_state_q_reg[3] (.CDN (trst_n), .CP (tck), .D (n_30), .Q
       (u_tap_state_q[3]), .QN (n_0));
  AO22D2 g2(.A1 (QSPI_SCLK_core_out), .A2 (n_103), .B1
       (u_bsc_41_QSPI_SCLK_data_update_q), .B2 (n_57), .Z
       (QSPI_SCLK_pad_out));
  AO22D2 g5086(.A1 (TL_CLK_TX_core_out), .A2 (n_103), .B1
       (u_bsc_71_TL_CLK_TX_data_update_q), .B2 (n_57), .Z
       (TL_CLK_TX_pad_out));
endmodule

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
