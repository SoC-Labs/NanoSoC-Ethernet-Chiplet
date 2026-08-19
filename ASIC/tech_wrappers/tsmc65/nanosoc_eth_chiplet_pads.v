//-----------------------------------------------------------------------------
// Top-Level Pad implementation for TSMC65nm
// A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
//
// Contributors
//
// David Flynn (d.w.flynn@soton.ac.uk)
// Daniel Newbrook (d.newbrook@soton.ac.uk)
//
// Copyright 2021-6, SoC Labs (www.soclabs.org)
//-----------------------------------------------------------------------------
//
// Abstract : TSMC65 pad ring for nanosoc_eth_chiplet_chip.
//
// This ring is the SYNTHESIS TOP (ASIC/genus-innovus/scripts/config.tcl).
//
// It implements the 23 bonded pads of the chip-boundary spec,
// sys_desc/chip_boundary/nanosoc_eth_chiplet.yaml, 1:1. That spec is the source
// of truth for WHAT is bonded; this file is the source of truth for WHICH PAD
// CELL each bond uses — a technology choice the YAML deliberately does not hold
// (docs/design/PIN_MAP.md 1).
//
// `make chip-boundary` cross-checks the two and fails on any divergence. Do not
// add, remove or rename a pad here without changing the YAML first.
//
// WHAT IS NOT BONDED, and why it is not a defect: the v1 pad budget gives up the
// scan chain, both UARTs, the PL022 SPI, the JTAG TAP and the PTP 1PPS, and it
// shares one pad between sys_fclk / rtc_clk / user_ref_clk. Every one of those
// inner ports is TIED or OPEN in the spec — driven by a reviewed constant in the
// generated wrapper, not left floating here. The inner RTL keeps its ports, so a
// later revision can mux the scan chain onto functional pads without touching
// nanosoc_eth_chiplet.sv. See the ties/opens sections of the YAML for the
// per-signal reasoning.
//
// Pad-cell conventions (verified against the vendor model,
// tphn65lpgv2od3_sl/verilog/tphn65lpgv2od3_sl.v):
//   OEN : ACTIVE LOW output enable  -- `bufif0 (PAD, I, OEN)`; 0 drives, 1 = Hi-Z.
//   REN : ACTIVE LOW pull enable    -- `not (RE, REN)`; REN=0 arms the keeper.
//   PDDW* : weak pull-DOWN keeper   -- `bufif1 (C_buf, 1'b0, pull)`
//   PDUW* : weak pull-UP   keeper   -- `bufif1 (C_buf, 1'b1, pull)`
//
// Mapping an inner OE onto OEN depends on the inner port's sense, which the YAML
// records per pad as `oe_polarity`:
//   oe_polarity: active_high (1 drives, e.g. qspi_io_e) -> .OEN(~oe)
//   oe_polarity: active_low  (0 drives, e.g. i2c_scl_t) -> .OEN( oe)
//-----------------------------------------------------------------------------

module nanosoc_eth_chiplet_pads (
  input  wire           SE,
  input  wire           CLK, // input
  input  wire           TEST, // input
  input  wire           NRST,  // active low reset
  inout  wire           SWDIO,
  input  wire           SWDCK,

  inout  wire [3:0]     QSPI_IO,
  output wire           QSPI_SCLK,
  output wire           QSPI_nCS,

  inout  wire [6:0]     HOSTIO4_P1,

  input  wire           RMII_REF_CLK,
  output wire [1:0]     RMII_TXD,
  output wire           RMII_TX_EN,
  input  wire [1:0]     RMII_RXD,
  input  wire           RMII_CRS_DV,
  inout  wire           RMII_MDIO,
  output wire           RMII_MDC,

  // Tidelink interface
  output wire           TL_CLK_TX,
  output wire [7:0]     TL_TX,
  input  wire           TL_CLK_RX,
  input  wire [7:0]     TL_RX,

  // Tidelink I2C sideband (open-drain). The autoneg FSM IS this bus -- it
  // claims the peer by driving a START condition and writing a claim byte
  // (tidelink_autoneg.sv:5-11), so the link cannot come up without these two.
  inout  wire           I2C_SCL,
  inout  wire           I2C_SDA
);


//------------------------------------
// internal wires
wire     soc_sys_fclk;
wire     soc_sys_sysresetn;
wire     soc_sys_scanenable;
wire     soc_sys_testmode;

// Serial Wire Debug port signals
wire     soc_dap_swclktck;
wire     soc_dap_swditms;
wire     soc_dap_swdo;
wire     soc_dap_swdoen;

// QSPI signals
wire       soc_qspi_sclk;
wire       soc_qspi_csn;
wire [3:0] soc_qspi_io_o;
wire [3:0] soc_qspi_io_i;
wire [3:0] soc_qspi_io_e;

// Host IO signals
wire [6:0] soc_hostio4_p1_in;
wire [6:0] soc_hostio4_p1_out;
wire [6:0] soc_hostio4_p1_outen;

// RMII interface
wire [1:0] soc_rmii_txd;
wire       soc_rmii_tx_en;
wire [1:0] soc_rmii_rxd;
wire       soc_rmii_crs_dv;
wire       soc_rmii_ref_clk;

wire       soc_md_pad_i;
wire       soc_mdc_pad_o;
wire       soc_md_pad_o;
wire       soc_md_padoe_o;

// Tidelink interface
wire soc_pad_clk_tx;
wire [7:0] soc_pad_tx;
wire soc_pad_clk_rx;
wire [7:0] soc_pad_rx;
wire soc_i2c_scl_i;
wire soc_i2c_scl_o;
wire soc_i2c_scl_t;
wire soc_i2c_sda_i;
wire soc_i2c_sda_o;
wire soc_i2c_sda_t;


wire tielo = 1'b0;
wire tiehi = 1'b1;

// rtc_clk and user_ref_clk are NOT connected here: the generated wrapper aliases
// both onto its own sys_fclk port (`.rtc_clk (sys_fclk)  // tied`), per the
// ALIASED CLOCKS block in the boundary spec. All three therefore share uPAD_CLK_I.
nanosoc_eth_chiplet_chip u_nanosoc_eth_chiplet_chip (
  .sys_fclk         (soc_sys_fclk),
  .sys_sysresetn    (soc_sys_sysresetn),
  .rmii_ref_clk     (soc_rmii_ref_clk),

  .pad_clk_tx       (soc_pad_clk_tx),
  .pad_tx           (soc_pad_tx),
  .pad_clk_rx       (soc_pad_clk_rx),
  .pad_rx           (soc_pad_rx),

  .i2c_scl_i        (soc_i2c_scl_i),
  .i2c_scl_o        (soc_i2c_scl_o),
  .i2c_scl_t        (soc_i2c_scl_t),
  .i2c_sda_i        (soc_i2c_sda_i),
  .i2c_sda_o        (soc_i2c_sda_o),
  .i2c_sda_t        (soc_i2c_sda_t),

  .dap_swclktck     (soc_dap_swclktck),
  .dap_swditms      (soc_dap_swditms),
  .dap_swdo         (soc_dap_swdo),
  .dap_swdoen       (soc_dap_swdoen),

  .sys_scanenable   (soc_sys_scanenable),
  .sys_testmode     (soc_sys_testmode),

  .rmii_txd         (soc_rmii_txd),
  .rmii_tx_en       (soc_rmii_tx_en),
  .rmii_rxd         (soc_rmii_rxd),
  .rmii_crs_dv      (soc_rmii_crs_dv),

  .mdc_pad_o        (soc_mdc_pad_o),
  .md_pad_i         (soc_md_pad_i),
  .md_pad_o         (soc_md_pad_o),
  .md_padoe_o       (soc_md_padoe_o),

  .qspi_sclk        (soc_qspi_sclk),
  .qspi_csn         (soc_qspi_csn),
  .qspi_io_i        (soc_qspi_io_i),
  .qspi_io_o        (soc_qspi_io_o),
  .qspi_io_e        (soc_qspi_io_e),

  .hostio4_p1_in    (soc_hostio4_p1_in),
  .hostio4_p1_out   (soc_hostio4_p1_out),
  .hostio4_p1_outen (soc_hostio4_p1_outen)
);

//-----------------------------------------------------------------------------
// IO pads (TSMC 65nm library mapping)
//-----------------------------------------------------------------------------

// Power Pads
//
// The four supply rails are declared as internal wires, not module ports:
// the UPF owns the supply boundary (upf:7-21 create_supply_port/net for
// these exact names; Genus emits matching `input`/`wire` VDD/VDDIO/VSS/VSSIO
// in <block>_gate_power.v, read by Innovus at 2b_pnr_place_eval.tcl:531).
// Ports here would double-own that boundary; wires just mirror it.
//
// NAMES ARE LOAD-BEARING: UPF binds nets to pads by instance pattern
// (`connect_supply_net VDDIO -ports {uPAD_VDDIO_*/VDDPST}`, upf:92-95), so
// renaming a net/instance here silently unbinds it.
//
// Cell-to-pin mapping (verified against tphn65lpgv2od3_sl.v):
//   PVDD2POC_G, PVDD2DGZ_G -> .VDDPST  IO supply (POC's only port)
//   PVSS2DGZ_G             -> .VSSPST  IO ground
//   PVDD1DGZ_G             -> .VDD     core supply
//   PVSS1DGZ_G             -> .VSS     core ground
// Each is a lone `inout` with a self-connected `tran` (sim no-op); wiring
// them just states ring connectivity in the source for LVS.
wire VDDIO;   // IO   supply -- 12 pads
wire VSSIO;   // IO   ground -- 12 pads
wire VDD;     // core supply --  6 pads
wire VSS;     // core ground --  4 pads

// PVDD2POC_G is the ring's power-on-control anchor cell. Padring convention
// (MiniASIC user guide p.32-33 item 6) requires exactly ONE per power domain
// that contains a functional digital IO cell -- this design has exactly one
// domain (PD_TOP, see docs/tapeout/62). Kept on side T; sides B/L/R use the
// plain PVDD2DGZ_G IO-supply cell instead (same VDDPST/VDDIO pin binding,
// same 25x135um footprint -- a like-for-like swap, not a ring edit).
// Rationale for siting on T specifically, and everything this does NOT
// change, is in docs/tapeout/63-pvdd2poc-single-instance-fix.md.
// Top
PVDD2POC_G uPAD_VDDIO_T_0 (.VDDPST (VDDIO));
PVDD2DGZ_G uPAD_VDDIO_T_1 (.VDDPST (VDDIO));
PVDD2DGZ_G uPAD_VDDIO_T_2 (.VDDPST (VDDIO));
PVSS2DGZ_G uPAD_VSSIO_T_0 (.VSSPST (VSSIO));
PVSS2DGZ_G uPAD_VSSIO_T_1 (.VSSPST (VSSIO));
PVSS2DGZ_G uPAD_VSSIO_T_2 (.VSSPST (VSSIO));
PVDD1DGZ_G uPAD_VDD_T_0   (.VDD    (VDD));
PVDD1DGZ_G uPAD_VDD_T_1   (.VDD    (VDD));
PVDD1DGZ_G uPAD_VDD_T_2   (.VDD    (VDD));
PVSS1DGZ_G uPAD_VSS_T_0   (.VSS    (VSS));
PVSS1DGZ_G uPAD_VSS_T_1   (.VSS    (VSS));

// Bottom
PVDD2DGZ_G uPAD_VDDIO_B_0 (.VDDPST (VDDIO));
PVDD2DGZ_G uPAD_VDDIO_B_1 (.VDDPST (VDDIO));
PVDD2DGZ_G uPAD_VDDIO_B_2 (.VDDPST (VDDIO));
PVSS2DGZ_G uPAD_VSSIO_B_0 (.VSSPST (VSSIO));
PVSS2DGZ_G uPAD_VSSIO_B_1 (.VSSPST (VSSIO));
PVSS2DGZ_G uPAD_VSSIO_B_2 (.VSSPST (VSSIO));
PVDD1DGZ_G uPAD_VDD_B_0   (.VDD    (VDD));
PVDD1DGZ_G uPAD_VDD_B_1   (.VDD    (VDD));
PVDD1DGZ_G uPAD_VDD_B_2   (.VDD    (VDD));
PVSS1DGZ_G uPAD_VSS_B_0   (.VSS    (VSS));
PVSS1DGZ_G uPAD_VSS_B_1   (.VSS    (VSS));

// Left
PVDD2DGZ_G uPAD_VDDIO_L_0 (.VDDPST (VDDIO));
PVDD2DGZ_G uPAD_VDDIO_L_1 (.VDDPST (VDDIO));
PVDD2DGZ_G uPAD_VDDIO_L_2 (.VDDPST (VDDIO));
PVSS2DGZ_G uPAD_VSSIO_L_0 (.VSSPST (VSSIO));
PVSS2DGZ_G uPAD_VSSIO_L_1 (.VSSPST (VSSIO));
PVSS2DGZ_G uPAD_VSSIO_L_2 (.VSSPST (VSSIO));

// Right
PVDD2DGZ_G uPAD_VDDIO_R_0 (.VDDPST (VDDIO));
PVDD2DGZ_G uPAD_VDDIO_R_1 (.VDDPST (VDDIO));
PVDD2DGZ_G uPAD_VDDIO_R_2 (.VDDPST (VDDIO));
PVSS2DGZ_G uPAD_VSSIO_R_0 (.VSSPST (VSSIO));
PVSS2DGZ_G uPAD_VSSIO_R_1 (.VSSPST (VSSIO));
PVSS2DGZ_G uPAD_VSSIO_R_2 (.VSSPST (VSSIO));

//---------------------------------------------------------------------------
// BOUNDARY-SCAN REGISTER (IEEE 1149.1). Generated wiring, see
// src/rtl/bscan/INTERFACE_CONTRACT.md and scripts/insert_bscan_padring.py.
//
// Sits between the core instance and the pad cells. With the SE pad low --
// the functional default -- the TAP is held in Test-Logic-Reset, every cell
// is transparent, and this chip behaves exactly as it did before.
//---------------------------------------------------------------------------
wire bsp_nrst_i_in;
wire bsp_swdck_i_in;
wire bsp_clk_i_in;
wire bsp_test_i_in;
wire bsp_se_i_in;
wire bsp_swdio_io_in;
wire bsp_swdio_io_out;
wire bsp_swdio_io_oe;
wire bsp_host_io_6_in;
wire bsp_host_io_6_out;
wire bsp_host_io_6_oe;
wire bsp_host_io_5_in;
wire bsp_host_io_5_out;
wire bsp_host_io_5_oe;
wire bsp_host_io_4_in;
wire bsp_host_io_4_out;
wire bsp_host_io_4_oe;
wire bsp_host_io_3_in;
wire bsp_host_io_3_out;
wire bsp_host_io_3_oe;
wire bsp_host_io_2_in;
wire bsp_host_io_2_out;
wire bsp_host_io_2_oe;
wire bsp_host_io_1_in;
wire bsp_host_io_1_out;
wire bsp_host_io_1_oe;
wire bsp_host_io_0_in;
wire bsp_host_io_0_out;
wire bsp_host_io_0_oe;
wire bsp_rmii_crs_dv_in;
wire bsp_rmii_mdio_in;
wire bsp_rmii_mdio_out;
wire bsp_rmii_mdio_oe;
wire bsp_rmii_tx_en_out;
wire bsp_rmii_txd1_out;
wire bsp_rmii_txd0_out;
wire bsp_rmii_rxd1_in;
wire bsp_rmii_rxd0_in;
wire bsp_rmii_ref_clk_in;
wire bsp_rmii_mdc_out;
wire bsp_qspi_ncs_out;
wire bsp_qspi_sclk_out;
wire bsp_qspi_io_3_in;
wire bsp_qspi_io_3_out;
wire bsp_qspi_io_3_oe;
wire bsp_qspi_io_2_in;
wire bsp_qspi_io_2_out;
wire bsp_qspi_io_2_oe;
wire bsp_qspi_io_1_in;
wire bsp_qspi_io_1_out;
wire bsp_qspi_io_1_oe;
wire bsp_qspi_io_0_in;
wire bsp_qspi_io_0_out;
wire bsp_qspi_io_0_oe;
wire bsp_tl_rx_0_in;
wire bsp_tl_rx_1_in;
wire bsp_tl_rx_2_in;
wire bsp_tl_rx_3_in;
wire bsp_tl_clk_rx_in;
wire bsp_tl_rx_4_in;
wire bsp_tl_rx_5_in;
wire bsp_tl_rx_6_in;
wire bsp_tl_rx_7_in;
wire bsp_i2c_scl_in;
wire bsp_i2c_scl_oe;
wire bsp_i2c_sda_in;
wire bsp_i2c_sda_oe;
wire bsp_tl_tx_0_out;
wire bsp_tl_tx_1_out;
wire bsp_tl_tx_2_out;
wire bsp_tl_tx_3_out;
wire bsp_tl_clk_tx_out;
wire bsp_tl_tx_4_out;
wire bsp_tl_tx_5_out;
wire bsp_tl_tx_6_out;
wire bsp_tl_tx_7_out;
wire bscan_tdo;
wire bscan_tdo_oe;
wire bscan_en = bsp_se_i_in;   // SE pad, pad-side: works with the core dead
wire bsp_host_io_1_out_muxed = bscan_en ? bscan_tdo    : bsp_host_io_1_out;
wire bsp_host_io_1_oe_muxed = bscan_en ? bscan_tdo_oe : bsp_host_io_1_oe;

nanosoc_eth_chiplet_bscan u_nanosoc_eth_chiplet_bscan (
  .tck     (bsp_swdck_i_in),
  .tms     (bsp_swdio_io_in),
  .tdi     (bsp_host_io_0_in),
  .trst_n  (bscan_en),   // SE low => TAP held in reset
  .tdo     (bscan_tdo),
  .tdo_oe  (bscan_tdo_oe),
  .NRST_I_pin_in (bsp_nrst_i_in),
  .NRST_I_core_in (soc_sys_sysresetn),
  .SWDCK_I_pin_in (bsp_swdck_i_in),
  .SWDCK_I_core_in (soc_dap_swclktck),
  .CLK_I_pin_in (bsp_clk_i_in),
  .CLK_I_core_in (soc_sys_fclk),
  .TEST_I_pin_in (bsp_test_i_in),
  .TEST_I_core_in (soc_sys_testmode),
  .SE_I_pin_in (bsp_se_i_in),
  .SE_I_core_in (soc_sys_scanenable),
  .SWDIO_IO_pin_in (bsp_swdio_io_in),
  .SWDIO_IO_core_in (soc_dap_swditms),
  .SWDIO_IO_core_out (soc_dap_swdo),
  .SWDIO_IO_pad_out (bsp_swdio_io_out),
  .SWDIO_IO_core_oe (soc_dap_swdoen),
  .SWDIO_IO_pad_oe (bsp_swdio_io_oe),
  .HOST_IO_6_pin_in (bsp_host_io_6_in),
  .HOST_IO_6_core_in (soc_hostio4_p1_in[6]),
  .HOST_IO_6_core_out (soc_hostio4_p1_out[6]),
  .HOST_IO_6_pad_out (bsp_host_io_6_out),
  .HOST_IO_6_core_oe (soc_hostio4_p1_outen[6]),
  .HOST_IO_6_pad_oe (bsp_host_io_6_oe),
  .HOST_IO_5_pin_in (bsp_host_io_5_in),
  .HOST_IO_5_core_in (soc_hostio4_p1_in[5]),
  .HOST_IO_5_core_out (soc_hostio4_p1_out[5]),
  .HOST_IO_5_pad_out (bsp_host_io_5_out),
  .HOST_IO_5_core_oe (soc_hostio4_p1_outen[5]),
  .HOST_IO_5_pad_oe (bsp_host_io_5_oe),
  .HOST_IO_4_pin_in (bsp_host_io_4_in),
  .HOST_IO_4_core_in (soc_hostio4_p1_in[4]),
  .HOST_IO_4_core_out (soc_hostio4_p1_out[4]),
  .HOST_IO_4_pad_out (bsp_host_io_4_out),
  .HOST_IO_4_core_oe (soc_hostio4_p1_outen[4]),
  .HOST_IO_4_pad_oe (bsp_host_io_4_oe),
  .HOST_IO_3_pin_in (bsp_host_io_3_in),
  .HOST_IO_3_core_in (soc_hostio4_p1_in[3]),
  .HOST_IO_3_core_out (soc_hostio4_p1_out[3]),
  .HOST_IO_3_pad_out (bsp_host_io_3_out),
  .HOST_IO_3_core_oe (soc_hostio4_p1_outen[3]),
  .HOST_IO_3_pad_oe (bsp_host_io_3_oe),
  .HOST_IO_2_pin_in (bsp_host_io_2_in),
  .HOST_IO_2_core_in (soc_hostio4_p1_in[2]),
  .HOST_IO_2_core_out (soc_hostio4_p1_out[2]),
  .HOST_IO_2_pad_out (bsp_host_io_2_out),
  .HOST_IO_2_core_oe (soc_hostio4_p1_outen[2]),
  .HOST_IO_2_pad_oe (bsp_host_io_2_oe),
  .HOST_IO_1_pin_in (bsp_host_io_1_in),
  .HOST_IO_1_core_in (soc_hostio4_p1_in[1]),
  .HOST_IO_1_core_out (soc_hostio4_p1_out[1]),
  .HOST_IO_1_pad_out (bsp_host_io_1_out),
  .HOST_IO_1_core_oe (soc_hostio4_p1_outen[1]),
  .HOST_IO_1_pad_oe (bsp_host_io_1_oe),
  .HOST_IO_0_pin_in (bsp_host_io_0_in),
  .HOST_IO_0_core_in (soc_hostio4_p1_in[0]),
  .HOST_IO_0_core_out (soc_hostio4_p1_out[0]),
  .HOST_IO_0_pad_out (bsp_host_io_0_out),
  .HOST_IO_0_core_oe (soc_hostio4_p1_outen[0]),
  .HOST_IO_0_pad_oe (bsp_host_io_0_oe),
  .RMII_CRS_DV_pin_in (bsp_rmii_crs_dv_in),
  .RMII_CRS_DV_core_in (soc_rmii_crs_dv),
  .RMII_MDIO_pin_in (bsp_rmii_mdio_in),
  .RMII_MDIO_core_in (soc_md_pad_i),
  .RMII_MDIO_core_out (soc_md_pad_o),
  .RMII_MDIO_pad_out (bsp_rmii_mdio_out),
  .RMII_MDIO_core_oe (soc_md_padoe_o),
  .RMII_MDIO_pad_oe (bsp_rmii_mdio_oe),
  .RMII_TX_EN_core_out (soc_rmii_tx_en),
  .RMII_TX_EN_pad_out (bsp_rmii_tx_en_out),
  .RMII_TXD1_core_out (soc_rmii_txd[1]),
  .RMII_TXD1_pad_out (bsp_rmii_txd1_out),
  .RMII_TXD0_core_out (soc_rmii_txd[0]),
  .RMII_TXD0_pad_out (bsp_rmii_txd0_out),
  .RMII_RXD1_pin_in (bsp_rmii_rxd1_in),
  .RMII_RXD1_core_in (soc_rmii_rxd[1]),
  .RMII_RXD0_pin_in (bsp_rmii_rxd0_in),
  .RMII_RXD0_core_in (soc_rmii_rxd[0]),
  .RMII_REF_CLK_pin_in (bsp_rmii_ref_clk_in),
  .RMII_REF_CLK_core_in (soc_rmii_ref_clk),
  .RMII_MDC_core_out (soc_mdc_pad_o),
  .RMII_MDC_pad_out (bsp_rmii_mdc_out),
  .QSPI_nCS_core_out (soc_qspi_csn),
  .QSPI_nCS_pad_out (bsp_qspi_ncs_out),
  .QSPI_SCLK_core_out (soc_qspi_sclk),
  .QSPI_SCLK_pad_out (bsp_qspi_sclk_out),
  .QSPI_IO_3_pin_in (bsp_qspi_io_3_in),
  .QSPI_IO_3_core_in (soc_qspi_io_i[3]),
  .QSPI_IO_3_core_out (soc_qspi_io_o[3]),
  .QSPI_IO_3_pad_out (bsp_qspi_io_3_out),
  .QSPI_IO_3_core_oe (soc_qspi_io_e[3]),
  .QSPI_IO_3_pad_oe (bsp_qspi_io_3_oe),
  .QSPI_IO_2_pin_in (bsp_qspi_io_2_in),
  .QSPI_IO_2_core_in (soc_qspi_io_i[2]),
  .QSPI_IO_2_core_out (soc_qspi_io_o[2]),
  .QSPI_IO_2_pad_out (bsp_qspi_io_2_out),
  .QSPI_IO_2_core_oe (soc_qspi_io_e[2]),
  .QSPI_IO_2_pad_oe (bsp_qspi_io_2_oe),
  .QSPI_IO_1_pin_in (bsp_qspi_io_1_in),
  .QSPI_IO_1_core_in (soc_qspi_io_i[1]),
  .QSPI_IO_1_core_out (soc_qspi_io_o[1]),
  .QSPI_IO_1_pad_out (bsp_qspi_io_1_out),
  .QSPI_IO_1_core_oe (soc_qspi_io_e[1]),
  .QSPI_IO_1_pad_oe (bsp_qspi_io_1_oe),
  .QSPI_IO_0_pin_in (bsp_qspi_io_0_in),
  .QSPI_IO_0_core_in (soc_qspi_io_i[0]),
  .QSPI_IO_0_core_out (soc_qspi_io_o[0]),
  .QSPI_IO_0_pad_out (bsp_qspi_io_0_out),
  .QSPI_IO_0_core_oe (soc_qspi_io_e[0]),
  .QSPI_IO_0_pad_oe (bsp_qspi_io_0_oe),
  .TL_RX_0_pin_in (bsp_tl_rx_0_in),
  .TL_RX_0_core_in (soc_pad_rx[0]),
  .TL_RX_1_pin_in (bsp_tl_rx_1_in),
  .TL_RX_1_core_in (soc_pad_rx[1]),
  .TL_RX_2_pin_in (bsp_tl_rx_2_in),
  .TL_RX_2_core_in (soc_pad_rx[2]),
  .TL_RX_3_pin_in (bsp_tl_rx_3_in),
  .TL_RX_3_core_in (soc_pad_rx[3]),
  .TL_CLK_RX_pin_in (bsp_tl_clk_rx_in),
  .TL_CLK_RX_core_in (soc_pad_clk_rx),
  .TL_RX_4_pin_in (bsp_tl_rx_4_in),
  .TL_RX_4_core_in (soc_pad_rx[4]),
  .TL_RX_5_pin_in (bsp_tl_rx_5_in),
  .TL_RX_5_core_in (soc_pad_rx[5]),
  .TL_RX_6_pin_in (bsp_tl_rx_6_in),
  .TL_RX_6_core_in (soc_pad_rx[6]),
  .TL_RX_7_pin_in (bsp_tl_rx_7_in),
  .TL_RX_7_core_in (soc_pad_rx[7]),
  .I2C_SCL_pin_in (bsp_i2c_scl_in),
  .I2C_SCL_core_in (soc_i2c_scl_i),
  .I2C_SCL_core_oe (soc_i2c_scl_o),
  .I2C_SCL_pad_oe (bsp_i2c_scl_oe),
  .I2C_SDA_pin_in (bsp_i2c_sda_in),
  .I2C_SDA_core_in (soc_i2c_sda_i),
  .I2C_SDA_core_oe (soc_i2c_sda_o),
  .I2C_SDA_pad_oe (bsp_i2c_sda_oe),
  .TL_TX_0_core_out (soc_pad_tx[0]),
  .TL_TX_0_pad_out (bsp_tl_tx_0_out),
  .TL_TX_1_core_out (soc_pad_tx[1]),
  .TL_TX_1_pad_out (bsp_tl_tx_1_out),
  .TL_TX_2_core_out (soc_pad_tx[2]),
  .TL_TX_2_pad_out (bsp_tl_tx_2_out),
  .TL_TX_3_core_out (soc_pad_tx[3]),
  .TL_TX_3_pad_out (bsp_tl_tx_3_out),
  .TL_CLK_TX_core_out (soc_pad_clk_tx),
  .TL_CLK_TX_pad_out (bsp_tl_clk_tx_out),
  .TL_TX_4_core_out (soc_pad_tx[4]),
  .TL_TX_4_pad_out (bsp_tl_tx_4_out),
  .TL_TX_5_core_out (soc_pad_tx[5]),
  .TL_TX_5_pad_out (bsp_tl_tx_5_out),
  .TL_TX_6_core_out (soc_pad_tx[6]),
  .TL_TX_6_pad_out (bsp_tl_tx_6_out),
  .TL_TX_7_core_out (soc_pad_tx[7]),
  .TL_TX_7_pad_out (bsp_tl_tx_7_out)
);



// Clock, Reset and Serial Wire Debug ports
PDDW04DGZ_G uPAD_SE_I (
  .C   (bsp_se_i_in),
  .REN (tielo),
  .I   (tielo),
  .OEN (tiehi),
  .PAD (SE)
);

// Also feeds the wrapper's rtc_clk and user_ref_clk (aliased in the spec).
PDDW04DGZ_G uPAD_CLK_I (
  .C   (bsp_clk_i_in),
  .REN (tiehi),
  .I   (tielo),
  .OEN (tiehi),
  .PAD (CLK)
);

PDDW04DGZ_G uPAD_TEST_I (
  .C   (bsp_test_i_in),
  .REN (tielo),
  .I   (tielo),
  .OEN (tiehi),
  .PAD (TEST)
);

PDDW04DGZ_G uPAD_NRST_I (
  .C   (bsp_nrst_i_in),
  .REN (tiehi),
  .I   (tielo),
  .OEN (tiehi),
  .PAD (NRST)
);

// dap_swdoen is oe_polarity: active_high -> OEN = ~oe
PDUW08DGZ_G uPAD_SWDIO_IO (
  .C   (bsp_swdio_io_in),
  .REN (tielo),
  .I   (bsp_swdio_io_out),
  .OEN ((bscan_en ? tiehi : ~bsp_swdio_io_oe)),
  .PAD (SWDIO)
);

PDDW04DGZ_G uPAD_SWDCK_I (
  .C   (bsp_swdck_i_in),
  .REN (tielo),
  .I   (tielo),
  .OEN (tiehi),
  .PAD (SWDCK)
);

// QSPI Pads
PDDW16DGZ_G uPAD_QSPI_SCLK (
  .C   (),
  .REN (tiehi),
  .I   (bsp_qspi_sclk_out),
  .OEN (tielo),
  .PAD (QSPI_SCLK)
);

PDDW16DGZ_G uPAD_QSPI_nCS (
  .C   (),
  .REN (tiehi),
  .I   (bsp_qspi_ncs_out),
  .OEN (tielo),
  .PAD (QSPI_nCS)
);

// qspi_io_e is oe_polarity: active_high -> OEN = ~oe
PDDW16DGZ_G uPAD_QSPI_IO_0 (
  .C   (bsp_qspi_io_0_in),
  .REN (tiehi),
  .I   (bsp_qspi_io_0_out),
  .OEN (~bsp_qspi_io_0_oe),
  .PAD (QSPI_IO[0])
);

PDDW16DGZ_G uPAD_QSPI_IO_1 (
  .C   (bsp_qspi_io_1_in),
  .REN (tiehi),
  .I   (bsp_qspi_io_1_out),
  .OEN (~bsp_qspi_io_1_oe),
  .PAD (QSPI_IO[1])
);

PDDW16DGZ_G uPAD_QSPI_IO_2 (
  .C   (bsp_qspi_io_2_in),
  .REN (tiehi),
  .I   (bsp_qspi_io_2_out),
  .OEN (~bsp_qspi_io_2_oe),
  .PAD (QSPI_IO[2])
);

PDDW16DGZ_G uPAD_QSPI_IO_3 (
  .C   (bsp_qspi_io_3_in),
  .REN (tiehi),
  .I   (bsp_qspi_io_3_out),
  .OEN (~bsp_qspi_io_3_oe),
  .PAD (QSPI_IO[3])
);

// Host IO Pads (hostio4_p1_outen is oe_polarity: active_high -> OEN = ~oe)
PDDW16DGZ_G uPAD_HOST_IO_0 (
  .C   (bsp_host_io_0_in),
  .REN (tiehi),
  .I   (bsp_host_io_0_out),
  .OEN ((bscan_en ? tiehi : ~bsp_host_io_0_oe)),
  .PAD (HOSTIO4_P1[0])
);

PDDW16DGZ_G uPAD_HOST_IO_1 (
  .C   (bsp_host_io_1_in),
  .REN (tiehi),
  .I   (bsp_host_io_1_out_muxed),
  .OEN (~bsp_host_io_1_oe_muxed),
  .PAD (HOSTIO4_P1[1])
);

PDDW16DGZ_G uPAD_HOST_IO_2 (
  .C   (bsp_host_io_2_in),
  .REN (tiehi),
  .I   (bsp_host_io_2_out),
  .OEN (~bsp_host_io_2_oe),
  .PAD (HOSTIO4_P1[2])
);

PDDW16DGZ_G uPAD_HOST_IO_3 (
  .C   (bsp_host_io_3_in),
  .REN (tiehi),
  .I   (bsp_host_io_3_out),
  .OEN (~bsp_host_io_3_oe),
  .PAD (HOSTIO4_P1[3])
);

PDDW16DGZ_G uPAD_HOST_IO_4 (
  .C   (bsp_host_io_4_in),
  .REN (tiehi),
  .I   (bsp_host_io_4_out),
  .OEN (~bsp_host_io_4_oe),
  .PAD (HOSTIO4_P1[4])
);

PDDW16DGZ_G uPAD_HOST_IO_5 (
  .C   (bsp_host_io_5_in),
  .REN (tiehi),
  .I   (bsp_host_io_5_out),
  .OEN (~bsp_host_io_5_oe),
  .PAD (HOSTIO4_P1[5])
);

PDDW16DGZ_G uPAD_HOST_IO_6 (
  .C   (bsp_host_io_6_in),
  .REN (tiehi),
  .I   (bsp_host_io_6_out),
  .OEN (~bsp_host_io_6_oe),
  .PAD (HOSTIO4_P1[6])
);

// RMII Pads
PDDW04DGZ_G uPAD_RMII_REF_CLK (
  .C   (bsp_rmii_ref_clk_in),
  .REN (tiehi),
  .I   (tielo),
  .OEN (tiehi),
  .PAD (RMII_REF_CLK)
);

PDDW16DGZ_G uPAD_RMII_TXD0 (
  .C   (),
  .REN (tiehi),
  .I   (bsp_rmii_txd0_out),
  .OEN (tielo),
  .PAD (RMII_TXD[0])
);

PDDW16DGZ_G uPAD_RMII_TXD1 (
  .C   (),
  .REN (tiehi),
  .I   (bsp_rmii_txd1_out),
  .OEN (tielo),
  .PAD (RMII_TXD[1])
);

PDDW16DGZ_G uPAD_RMII_TX_EN (
  .C   (),
  .REN (tiehi),
  .I   (bsp_rmii_tx_en_out),
  .OEN (tielo),
  .PAD (RMII_TX_EN)
);

PDDW04DGZ_G uPAD_RMII_RXD0 (
  .C   (bsp_rmii_rxd0_in),
  .REN (tielo),
  .I   (tielo),
  .OEN (tiehi),
  .PAD (RMII_RXD[0])
);

PDDW04DGZ_G uPAD_RMII_RXD1 (
  .C   (bsp_rmii_rxd1_in),
  .REN (tielo),
  .I   (tielo),
  .OEN (tiehi),
  .PAD (RMII_RXD[1])
);

PDDW04DGZ_G uPAD_RMII_CRS_DV (
  .C   (bsp_rmii_crs_dv_in),
  .REN (tielo),
  .I   (tielo),
  .OEN (tiehi),
  .PAD (RMII_CRS_DV)
);

// md_padoe_o is oe_polarity: active_high -> OEN = ~oe
PDDW16DGZ_G uPAD_RMII_MDIO (
  .C   (bsp_rmii_mdio_in),
  .REN (tiehi),
  .I   (bsp_rmii_mdio_out),
  .OEN (~bsp_rmii_mdio_oe),
  .PAD (RMII_MDIO)
);

PDDW16DGZ_G uPAD_RMII_MDC (
  .C   (),
  .REN (tiehi),
  .I   (bsp_rmii_mdc_out),
  .OEN (tielo),
  .PAD (RMII_MDC)
);

// Tidelink Pads (TX = outputs, RX = inputs)
PDDW16DGZ_G uPAD_TL_CLK_TX (
  .C   (),
  .REN (tiehi),
  .I   (bsp_tl_clk_tx_out),
  .OEN (tielo),
  .PAD (TL_CLK_TX)
);

PDDW16DGZ_G uPAD_TL_TX_0 (
  .C   (),
  .REN (tiehi),
  .I   (bsp_tl_tx_0_out),
  .OEN (tielo),
  .PAD (TL_TX[0])
);

PDDW16DGZ_G uPAD_TL_TX_1 (
  .C   (),
  .REN (tiehi),
  .I   (bsp_tl_tx_1_out),
  .OEN (tielo),
  .PAD (TL_TX[1])
);

PDDW16DGZ_G uPAD_TL_TX_2 (
  .C   (),
  .REN (tiehi),
  .I   (bsp_tl_tx_2_out),
  .OEN (tielo),
  .PAD (TL_TX[2])
);

PDDW16DGZ_G uPAD_TL_TX_3 (
  .C   (),
  .REN (tiehi),
  .I   (bsp_tl_tx_3_out),
  .OEN (tielo),
  .PAD (TL_TX[3])
);

PDDW16DGZ_G uPAD_TL_TX_4 (
  .C   (),
  .REN (tiehi),
  .I   (bsp_tl_tx_4_out),
  .OEN (tielo),
  .PAD (TL_TX[4])
);

PDDW16DGZ_G uPAD_TL_TX_5 (
  .C   (),
  .REN (tiehi),
  .I   (bsp_tl_tx_5_out),
  .OEN (tielo),
  .PAD (TL_TX[5])
);

PDDW16DGZ_G uPAD_TL_TX_6 (
  .C   (),
  .REN (tiehi),
  .I   (bsp_tl_tx_6_out),
  .OEN (tielo),
  .PAD (TL_TX[6])
);

PDDW16DGZ_G uPAD_TL_TX_7 (
  .C   (),
  .REN (tiehi),
  .I   (bsp_tl_tx_7_out),
  .OEN (tielo),
  .PAD (TL_TX[7])
);

PDDW16DGZ_G uPAD_TL_CLK_RX (
  .C   (bsp_tl_clk_rx_in),
  .REN (tiehi),
  .I   (tielo),
  .OEN (tiehi),
  .PAD (TL_CLK_RX)
);

PDDW16DGZ_G uPAD_TL_RX_0 (
  .C   (bsp_tl_rx_0_in),
  .REN (tiehi),
  .I   (tielo),
  .OEN (tiehi),
  .PAD (TL_RX[0])
);

PDDW16DGZ_G uPAD_TL_RX_1 (
  .C   (bsp_tl_rx_1_in),
  .REN (tiehi),
  .I   (tielo),
  .OEN (tiehi),
  .PAD (TL_RX[1])
);

PDDW16DGZ_G uPAD_TL_RX_2 (
  .C   (bsp_tl_rx_2_in),
  .REN (tiehi),
  .I   (tielo),
  .OEN (tiehi),
  .PAD (TL_RX[2])
);

PDDW16DGZ_G uPAD_TL_RX_3 (
  .C   (bsp_tl_rx_3_in),
  .REN (tiehi),
  .I   (tielo),
  .OEN (tiehi),
  .PAD (TL_RX[3])
);

PDDW16DGZ_G uPAD_TL_RX_4 (
  .C   (bsp_tl_rx_4_in),
  .REN (tiehi),
  .I   (tielo),
  .OEN (tiehi),
  .PAD (TL_RX[4])
);

PDDW16DGZ_G uPAD_TL_RX_5 (
  .C   (bsp_tl_rx_5_in),
  .REN (tiehi),
  .I   (tielo),
  .OEN (tiehi),
  .PAD (TL_RX[5])
);

PDDW16DGZ_G uPAD_TL_RX_6 (
  .C   (bsp_tl_rx_6_in),
  .REN (tiehi),
  .I   (tielo),
  .OEN (tiehi),
  .PAD (TL_RX[6])
);

PDDW16DGZ_G uPAD_TL_RX_7 (
  .C   (bsp_tl_rx_7_in),
  .REN (tiehi),
  .I   (tielo),
  .OEN (tiehi),
  .PAD (TL_RX[7])
);

// TideLink I2C sideband -- OPEN DRAIN, built structurally since the library
// has no open-drain pad cell (tphn65lpgv2od3_sl has 0 open_drain hits). Key
// points:
//   - I2C is wired-AND: these pads must NEVER drive high.
//   - i2c_*_t is oe_polarity active_low ("1 = float"), and OEN is an
//     active-low output enable, so OEN maps to _t DIRECTLY. Do NOT invert to
//     ~t: that would drive the bus exactly when TideLink means to release it,
//     breaking wired-AND arbitration and slave clock-stretching.
//   - .I is tied low on purpose: send 1 -> OEN=1 -> tristate -> external
//     pull-up gives the high; send 0 -> OEN=0 -> pad drives .I (hard 0) ->
//     low. This makes "never drive high" structural rather than an RTL
//     invariant that scan/ECO could break.
//   - REN is active-low (`not (RE, REN)`), so tielo ARMS the pad's internal
//     weak pull-up keeper. Keep it as a bus-keeper only -- the real ~2.2k
//     pull-ups belong on the PCB, do not "tidy" REN to tiehi.
PDUW16DGZ_G uPAD_I2C_SCL (
  .C   (bsp_i2c_scl_in),
  .REN (tielo),
  .I   (tielo),
  .OEN (bsp_i2c_scl_oe),
  .PAD (I2C_SCL)
);

PDUW16DGZ_G uPAD_I2C_SDA (
  .C   (bsp_i2c_sda_in),
  .REN (tielo),
  .I   (tielo),
  .OEN (bsp_i2c_sda_oe),
  .PAD (I2C_SDA)
);

endmodule
