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
// MUTATION APPLIED HERE: EVERY sequential cell deleted from the module, AND the pad table
// regenerated with boundary_length=0 and an empty pad list. Under a naive
// 'found >= expected' this reads 0 >= 0 and 0/0 pads survived, and passes
// having measured nothing. THIS IS THE CASE THE GATE EXISTS FOR.
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
  AO22D2 g2(.A1 (QSPI_SCLK_core_out), .A2 (n_103), .B1
       (u_bsc_41_QSPI_SCLK_data_update_q), .B2 (n_57), .Z
       (QSPI_SCLK_pad_out));
  AO22D2 g5086(.A1 (TL_CLK_TX_core_out), .A2 (n_103), .B1
       (u_bsc_71_TL_CLK_TX_data_update_q), .B2 (n_57), .Z
       (TL_CLK_TX_pad_out));
endmodule

module nanosoc_eth_chiplet_pads ();
  nanosoc_eth_chiplet_bscan u_nanosoc_eth_chiplet_bscan(.tck
       (bsp_swdck_i_in), .tms (bsp_swdio_io_in), .tdi
       (bsp_host_io_0_in), .trst_n (bsp_se_i_in), .tdo (bscan_tdo),
       .tdo_oe (bscan_tdo_oe), .NRST_I_pin_in (bsp_nrst_i_in),
       .NRST_I_core_in (soc_sys_sysresetn), .SWDCK_I_pin_in
       (bsp_swdck_i_in), .SWDCK_I_core_in (soc_dap_swclktck),
       .CLK_I_pin_in (bsp_clk_i_in), .CLK_I_core_in (soc_sys_fclk),
       .TEST_I_pin_in (bsp_test_i_in), .TEST_I_core_in
       (soc_sys_testmode), .SE_I_pin_in (bsp_se_i_in), .SE_I_core_in
       (UNCONNECTED2708), .SWDIO_IO_pin_in (bsp_swdio_io_in),
       .SWDIO_IO_core_out (soc_dap_swdo), .SWDIO_IO_pad_out
       (bsp_swdio_io_out), .SWDIO_IO_core_oe (soc_dap_swdoen),
       .SWDIO_IO_pad_oe (bsp_swdio_io_oe), .SWDIO_IO_core_in
       (soc_dap_swditms), .HOST_IO_6_pin_in (bsp_host_io_6_in),
       .HOST_IO_6_core_out (soc_hostio4_p1_out[6]), .HOST_IO_6_pad_out
       (bsp_host_io_6_out), .HOST_IO_6_core_oe
       (soc_hostio4_p1_outen[6]), .HOST_IO_6_pad_oe (bsp_host_io_6_oe),
       .HOST_IO_6_core_in (soc_hostio4_p1_in[6]), .HOST_IO_5_pin_in
       (bsp_host_io_5_in), .HOST_IO_5_core_out (soc_hostio4_p1_out[5]),
       .HOST_IO_5_pad_out (bsp_host_io_5_out), .HOST_IO_5_core_oe
       (soc_hostio4_p1_outen[6]), .HOST_IO_5_pad_oe (bsp_host_io_5_oe),
       .HOST_IO_5_core_in (soc_hostio4_p1_in[5]), .HOST_IO_4_pin_in
       (bsp_host_io_4_in), .HOST_IO_4_core_out (soc_hostio4_p1_out[4]),
       .HOST_IO_4_pad_out (bsp_host_io_4_out), .HOST_IO_4_core_oe
       (soc_hostio4_p1_outen[6]), .HOST_IO_4_pad_oe (bsp_host_io_4_oe),
       .HOST_IO_4_core_in (soc_hostio4_p1_in[4]), .HOST_IO_3_pin_in
       (bsp_host_io_3_in), .HOST_IO_3_core_out (soc_hostio4_p1_out[3]),
       .HOST_IO_3_pad_out (bsp_host_io_3_out), .HOST_IO_3_core_oe
       (soc_hostio4_p1_outen[6]), .HOST_IO_3_pad_oe (bsp_host_io_3_oe),
       .HOST_IO_3_core_in (soc_hostio4_p1_in[3]), .HOST_IO_2_pin_in
       (bsp_host_io_2_in), .HOST_IO_2_core_out
       (UNCONNECTED_HIER_Z1597), .HOST_IO_2_pad_out
       (bsp_host_io_2_out), .HOST_IO_2_core_oe
       (UNCONNECTED_HIER_Z1598), .HOST_IO_2_pad_oe (bsp_host_io_2_oe),
       .HOST_IO_2_core_in (soc_hostio4_p1_in[2]), .HOST_IO_1_pin_in
       (bsp_host_io_1_in), .HOST_IO_1_core_out (soc_hostio4_p1_out[1]),
       .HOST_IO_1_pad_out (bsp_host_io_1_out), .HOST_IO_1_core_oe
       (UNCONNECTED_HIER_Z1599), .HOST_IO_1_pad_oe (bsp_host_io_1_oe),
       .HOST_IO_1_core_in (UNCONNECTED2709), .HOST_IO_0_pin_in
       (bsp_host_io_0_in), .HOST_IO_0_core_out (soc_hostio4_p1_out[0]),
       .HOST_IO_0_pad_out (bsp_host_io_0_out), .HOST_IO_0_core_oe
       (UNCONNECTED_HIER_Z1600), .HOST_IO_0_pad_oe (bsp_host_io_0_oe),
       .HOST_IO_0_core_in (UNCONNECTED2710), .RMII_CRS_DV_pin_in
       (bsp_rmii_crs_dv_in), .RMII_CRS_DV_core_in (soc_rmii_crs_dv),
       .RMII_MDIO_pin_in (bsp_rmii_mdio_in), .RMII_MDIO_core_out
       (soc_md_pad_o), .RMII_MDIO_pad_out (bsp_rmii_mdio_out),
       .RMII_MDIO_core_oe (soc_md_padoe_o), .RMII_MDIO_pad_oe
       (bsp_rmii_mdio_oe), .RMII_MDIO_core_in (soc_md_pad_i),
       .RMII_TX_EN_core_out (soc_rmii_tx_en), .RMII_TX_EN_pad_out
       (bsp_rmii_tx_en_out), .RMII_TXD1_core_out (soc_rmii_txd[1]),
       .RMII_TXD1_pad_out (bsp_rmii_txd1_out), .RMII_TXD0_core_out
       (soc_rmii_txd[0]), .RMII_TXD0_pad_out (bsp_rmii_txd0_out),
       .RMII_RXD1_pin_in (bsp_rmii_rxd1_in), .RMII_RXD1_core_in
       (soc_rmii_rxd[1]), .RMII_RXD0_pin_in (bsp_rmii_rxd0_in),
       .RMII_RXD0_core_in (soc_rmii_rxd[0]), .RMII_REF_CLK_pin_in
       (bsp_rmii_ref_clk_in), .RMII_REF_CLK_core_in (soc_rmii_ref_clk),
       .RMII_MDC_core_out (soc_mdc_pad_o), .RMII_MDC_pad_out
       (bsp_rmii_mdc_out), .QSPI_nCS_core_out (soc_qspi_csn),
       .QSPI_nCS_pad_out (bsp_qspi_ncs_out), .QSPI_SCLK_core_out
       (soc_qspi_sclk), .QSPI_SCLK_pad_out (bsp_qspi_sclk_out),
       .QSPI_IO_3_pin_in (bsp_qspi_io_3_in), .QSPI_IO_3_core_out
       (soc_qspi_io_o[3]), .QSPI_IO_3_pad_out (bsp_qspi_io_3_out),
       .QSPI_IO_3_core_oe (soc_qspi_io_e[3]), .QSPI_IO_3_pad_oe
       (bsp_qspi_io_3_oe), .QSPI_IO_3_core_in (soc_qspi_io_i[3]),
       .QSPI_IO_2_pin_in (bsp_qspi_io_2_in), .QSPI_IO_2_core_out
       (soc_qspi_io_o[2]), .QSPI_IO_2_pad_out (bsp_qspi_io_2_out),
       .QSPI_IO_2_core_oe (soc_qspi_io_e[3]), .QSPI_IO_2_pad_oe
       (bsp_qspi_io_2_oe), .QSPI_IO_2_core_in (soc_qspi_io_i[2]),
       .QSPI_IO_1_pin_in (bsp_qspi_io_1_in), .QSPI_IO_1_core_out
       (soc_qspi_io_o[1]), .QSPI_IO_1_pad_out (bsp_qspi_io_1_out),
       .QSPI_IO_1_core_oe (soc_qspi_io_e[1]), .QSPI_IO_1_pad_oe
       (bsp_qspi_io_1_oe), .QSPI_IO_1_core_in (soc_qspi_io_i[1]),
       .QSPI_IO_0_pin_in (bsp_qspi_io_0_in), .QSPI_IO_0_core_out
       (soc_qspi_io_o[0]), .QSPI_IO_0_pad_out (bsp_qspi_io_0_out),
       .QSPI_IO_0_core_oe (soc_qspi_io_e[3]), .QSPI_IO_0_pad_oe
       (bsp_qspi_io_0_oe), .QSPI_IO_0_core_in (soc_qspi_io_i[0]),
       .TL_RX_0_pin_in (bsp_tl_rx_0_in), .TL_RX_0_core_in
       (soc_pad_rx[0]), .TL_RX_1_pin_in (bsp_tl_rx_1_in),
       .TL_RX_1_core_in (soc_pad_rx[1]), .TL_RX_2_pin_in
       (bsp_tl_rx_2_in), .TL_RX_2_core_in (soc_pad_rx[2]),
       .TL_RX_3_pin_in (bsp_tl_rx_3_in), .TL_RX_3_core_in
       (soc_pad_rx[3]), .TL_CLK_RX_pin_in (bsp_tl_clk_rx_in),
       .TL_CLK_RX_core_in (soc_pad_clk_rx), .TL_RX_4_pin_in
       (bsp_tl_rx_4_in), .TL_RX_4_core_in (soc_pad_rx[4]),
       .TL_RX_5_pin_in (bsp_tl_rx_5_in), .TL_RX_5_core_in
       (soc_pad_rx[5]), .TL_RX_6_pin_in (bsp_tl_rx_6_in),
       .TL_RX_6_core_in (soc_pad_rx[6]), .TL_RX_7_pin_in
       (bsp_tl_rx_7_in), .TL_RX_7_core_in (soc_pad_rx[7]),
       .I2C_SCL_pin_in (bsp_i2c_scl_in), .I2C_SCL_core_oe
       (soc_i2c_scl_o), .I2C_SCL_pad_oe (bsp_i2c_scl_oe),
       .I2C_SCL_core_in (soc_i2c_scl_i), .I2C_SDA_pin_in
       (bsp_i2c_sda_in), .I2C_SDA_core_oe (soc_i2c_sda_o),
       .I2C_SDA_pad_oe (bsp_i2c_sda_oe), .I2C_SDA_core_in
       (soc_i2c_sda_i), .TL_TX_0_core_out (soc_pad_tx[0]),
       .TL_TX_0_pad_out (bsp_tl_tx_0_out), .TL_TX_1_core_out
       (soc_pad_tx[1]), .TL_TX_1_pad_out (bsp_tl_tx_1_out),
       .TL_TX_2_core_out (soc_pad_tx[2]), .TL_TX_2_pad_out
       (bsp_tl_tx_2_out), .TL_TX_3_core_out (soc_pad_tx[3]),
       .TL_TX_3_pad_out (bsp_tl_tx_3_out), .TL_CLK_TX_core_out
       (soc_pad_clk_tx), .TL_CLK_TX_pad_out (bsp_tl_clk_tx_out),
       .TL_TX_4_core_out (soc_pad_tx[4]), .TL_TX_4_pad_out
       (bsp_tl_tx_4_out), .TL_TX_5_core_out (soc_pad_tx[5]),
       .TL_TX_5_pad_out (bsp_tl_tx_5_out), .TL_TX_6_core_out
       (soc_pad_tx[6]), .TL_TX_6_pad_out (bsp_tl_tx_6_out),
       .TL_TX_7_core_out (soc_pad_tx[7]), .TL_TX_7_pad_out
       (bsp_tl_tx_7_out));
endmodule
