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
// It implements the 46 bonded pads of the reviewed chip-boundary spec,
// sys_desc/chip_boundary/nanosoc_eth_chiplet.yaml, 1:1. That spec is the
// source of truth for WHAT is bonded; this file is the source of truth for
// WHICH PAD CELL each bond uses (a technology choice the YAML deliberately
// does not hold — see docs/PIN_MAP.md 1).
//
// `make chip-boundary` cross-checks the two. Do not add, remove or rename a
// pad here without changing the YAML: the check fails on any divergence.
//
// Pad-cell conventions (verified against the vendor model,
// tphn65lpgv2od3_sl/verilog/tphn65lpgv2od3_sl.v):
//   OEN : ACTIVE LOW output enable  -- `bufif0 (PAD, I, OEN)`; 0 drives, 1 = Hi-Z.
//   REN : ACTIVE LOW pull enable    -- `not (RE, REN)`; REN=0 arms the keeper.
//   PDDW* : weak pull-DOWN keeper   -- `bufif1 (C_buf, 1'b0, pull)`
//   PDUW* : weak pull-UP   keeper   -- `bufif1 (C_buf, 1'b1, pull)`
//
// Mapping an inner OE onto OEN therefore depends on the inner port's sense,
// which the YAML records per pad as `oe_polarity`:
//   oe_polarity: active_high (1 drives, e.g. qspi_io_e) -> .OEN(~oe)
//   oe_polarity: active_low  (0 drives, e.g. i2c_scl_t) -> .OEN( oe)
// Getting this backwards on the open-drain I2C makes the die drive the bus at
// exactly the moments it is supposed to release it, which breaks wired-AND
// arbitration and slave clock-stretching.
//-----------------------------------------------------------------------------

module nanosoc_eth_chiplet_pads (
  // ---- clocks + reset -------------------------------------------------
  input  wire           CLK,               // free-running system clock
  input  wire           NRST,              // external system reset (active low)
  input  wire           RTC_CLK,           // RTC / PTP reference
  input  wire           RMII_REF_CLK,      // 50 MHz RMII reference
  input  wire           USER_REF_CLK,      // Wlink PLL reference (async to sys_hclk)

  // ---- die-to-die PHY -------------------------------------------------
  output wire           TL_CLK_TX,
  output wire [7:0]     TL_TX,
  input  wire           TL_CLK_RX,
  input  wire [7:0]     TL_RX,

  // ---- TideLink I2C sideband (open-drain) -----------------------------
  inout  wire           I2C_SCL,
  inout  wire           I2C_SDA,

  // ---- link bring-up straps (per-die) ---------------------------------
  input  wire           ROLE_STRAP,        // MUST differ between the two dies
  input  wire           MASK_HS_BYPASS,
  input  wire           APB_DEBUG_UNLOCK,

  // ---- CoreSight SWJ-DP -----------------------------------------------
  input  wire           SWDCK,
  inout  wire           SWDIO,
  input  wire           JTAG_TDI,
  output wire           JTAG_TDO,
  input  wire           JTAG_NTRST,

  // ---- DFT -------------------------------------------------------------
  input  wire           SCAN_MODE,
  input  wire           SCAN_ASYNCRST_CTRL,
  input  wire           SCAN_CLK,
  input  wire           SCAN_SHIFT,
  input  wire           SCAN_IN,
  output wire           SCAN_OUT,
  input  wire           SE,                // sys_scanenable
  input  wire           TEST,              // sys_testmode

  // ---- UARTs -----------------------------------------------------------
  input  wire           UART_RXD,
  output wire           UART_TXD,
  input  wire           CPU1_UART_RXD,
  output wire           CPU1_UART_TXD,

  // ---- ethernet RMII + MDIO -------------------------------------------
  output wire [1:0]     RMII_TXD,
  output wire           RMII_TX_EN,
  input  wire [1:0]     RMII_RXD,
  input  wire           RMII_CRS_DV,
  output wire           RMII_MDC,
  inout  wire           RMII_MDIO,

  // ---- QSPI flash ------------------------------------------------------
  output wire           QSPI_SCLK,
  output wire           QSPI_nCS,
  inout  wire [3:0]     QSPI_IO,

  // ---- PL022 SPI master ------------------------------------------------
  output wire           SPI_SCLK,
  output wire           SPI_MOSI,
  input  wire           SPI_MISO,
  output wire [2:0]     SPI_SS,

  // ---- HOSTIO4 host-access link ---------------------------------------
  inout  wire [6:0]     HOSTIO4_P1,

  // ---- PTP 1PPS --------------------------------------------------------
  output wire           PHC_PPS_OUT
);


//------------------------------------
// internal wires

// Clocks and reset
wire       soc_sys_fclk;
wire       soc_sys_sysresetn;
wire       soc_rtc_clk;
wire       soc_rmii_ref_clk;
wire       soc_user_ref_clk;

// DFT
wire       soc_sys_scanenable;
wire       soc_sys_testmode;
wire       soc_scan_mode;
wire       soc_scan_asyncrst_ctrl;
wire       soc_scan_clk;
wire       soc_scan_shift;
wire       soc_scan_in;
wire       soc_scan_out;

// Serial Wire Debug / JTAG port signals
wire       soc_dap_swclktck;
wire       soc_dap_swditms;
wire       soc_dap_swdo;
wire       soc_dap_swdoen;
wire       soc_dap_tdi;
wire       soc_dap_tdo;
wire       soc_dap_ntdoen;
wire       soc_dap_ntrst;

// Link bring-up straps
wire       soc_role_strap;
wire       soc_mask_hs_bypass;
wire       soc_apb_debug_unlock;

// UARTs
wire       soc_uart_rxd;
wire       soc_uart_txd;
wire       soc_chip_core_uart_rxd;
wire       soc_chip_core_uart_txd;

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

wire       soc_md_pad_i;
wire       soc_mdc_pad_o;
wire       soc_md_pad_o;
wire       soc_md_padoe_o;

// SPI interface
wire       soc_spi_sclk;
wire       soc_spi_mosi;
wire       soc_spi_miso;
wire [2:0] soc_spi_ss;

// Tidelink interface
wire       soc_pad_clk_tx;
wire [7:0] soc_pad_tx;
wire       soc_pad_clk_rx;
wire [7:0] soc_pad_rx;
wire       soc_i2c_scl_i;
wire       soc_i2c_scl_o;
wire       soc_i2c_scl_t;
wire       soc_i2c_sda_i;
wire       soc_i2c_sda_o;
wire       soc_i2c_sda_t;

// PTP
wire       soc_phc_pps_out;


wire tielo = 1'b0;
wire tiehi = 1'b1;

nanosoc_eth_chiplet_chip u_nanosoc_eth_chiplet_chip (
    .sys_fclk(soc_sys_fclk),
    .sys_sysresetn(soc_sys_sysresetn),
    .rtc_clk(soc_rtc_clk),
    .rmii_ref_clk(soc_rmii_ref_clk),
    .user_ref_clk(soc_user_ref_clk),

    .pad_clk_tx(soc_pad_clk_tx),
    .pad_tx(soc_pad_tx),
    .pad_clk_rx(soc_pad_clk_rx),
    .pad_rx(soc_pad_rx),

    .i2c_scl_i(soc_i2c_scl_i),
    .i2c_scl_o(soc_i2c_scl_o),
    .i2c_scl_t(soc_i2c_scl_t),
    .i2c_sda_i(soc_i2c_sda_i),
    .i2c_sda_o(soc_i2c_sda_o),
    .i2c_sda_t(soc_i2c_sda_t),

    .role_strap_i(soc_role_strap),
    .mask_hs_bypass_i(soc_mask_hs_bypass),
    .apb_debug_unlock_i(soc_apb_debug_unlock),

    .dap_swclktck(soc_dap_swclktck),
    .dap_swditms(soc_dap_swditms),
    .dap_swdo(soc_dap_swdo),
    .dap_swdoen(soc_dap_swdoen),
    .dap_tdi(soc_dap_tdi),
    .dap_tdo(soc_dap_tdo),
    .dap_ntdoen(soc_dap_ntdoen),
    .dap_ntrst(soc_dap_ntrst),

    .scan_mode(soc_scan_mode),
    .scan_asyncrst_ctrl(soc_scan_asyncrst_ctrl),
    .scan_clk(soc_scan_clk),
    .scan_shift(soc_scan_shift),
    .scan_in(soc_scan_in),
    .scan_out(soc_scan_out),
    .sys_scanenable(soc_sys_scanenable),
    .sys_testmode(soc_sys_testmode),

    .uart_rxd(soc_uart_rxd),
    .uart_txd(soc_uart_txd),

    .chip_core_uart_rxd(soc_chip_core_uart_rxd),
    .chip_core_uart_txd(soc_chip_core_uart_txd),

    .rmii_txd(soc_rmii_txd),
    .rmii_tx_en(soc_rmii_tx_en),
    .rmii_rxd(soc_rmii_rxd),
    .rmii_crs_dv(soc_rmii_crs_dv),

    .mdc_pad_o(soc_mdc_pad_o),
    .md_pad_i(soc_md_pad_i),
    .md_pad_o(soc_md_pad_o),
    .md_padoe_o(soc_md_padoe_o),

    .qspi_sclk(soc_qspi_sclk),
    .qspi_csn(soc_qspi_csn),
    .qspi_io_i(soc_qspi_io_i),
    .qspi_io_o(soc_qspi_io_o),
    .qspi_io_e(soc_qspi_io_e),

    .spi_sclk(soc_spi_sclk),
    .spi_mosi(soc_spi_mosi),
    .spi_miso(soc_spi_miso),
    .spi_ss(soc_spi_ss),

    .hostio4_p1_in(soc_hostio4_p1_in),
    .hostio4_p1_out(soc_hostio4_p1_out),
    .hostio4_p1_outen(soc_hostio4_p1_outen),

    .phc_pps_out(soc_phc_pps_out)
);

 // --------------------------------------------------------------------------------
 // IO pad (TSMC 65nm specific Library mapping)
 // --------------------------------------------------------------------------------

// Power Pads
// Top
PVDD2POC_G uPAD_VDDIO_T_0();
PVDD2DGZ_G uPAD_VDDIO_T_1();
PVDD2DGZ_G uPAD_VDDIO_T_2();
PVSS2DGZ_G uPAD_VSSIO_T_0();
PVSS2DGZ_G uPAD_VSSIO_T_1();
PVSS2DGZ_G uPAD_VSSIO_T_2();
PVDD1DGZ_G uPAD_VDD_T_0();
PVDD1DGZ_G uPAD_VDD_T_1();
PVDD1DGZ_G uPAD_VDD_T_2();
PVSS1DGZ_G uPAD_VSS_T_0();
PVSS1DGZ_G uPAD_VSS_T_1();

// Bottom
PVDD2POC_G uPAD_VDDIO_B_0();
PVDD2DGZ_G uPAD_VDDIO_B_1();
PVDD2DGZ_G uPAD_VDDIO_B_2();
PVSS2DGZ_G uPAD_VSSIO_B_0();
PVSS2DGZ_G uPAD_VSSIO_B_1();
PVSS2DGZ_G uPAD_VSSIO_B_2();
PVDD1DGZ_G uPAD_VDD_B_0();
PVDD1DGZ_G uPAD_VDD_B_1();
PVDD1DGZ_G uPAD_VDD_B_2();
PVSS1DGZ_G uPAD_VSS_B_0();
PVSS1DGZ_G uPAD_VSS_B_1();

// Left
PVDD2POC_G uPAD_VDDIO_L_0();
PVDD2DGZ_G uPAD_VDDIO_L_1();
PVDD2DGZ_G uPAD_VDDIO_L_2();
PVSS2DGZ_G uPAD_VSSIO_L_0();
PVSS2DGZ_G uPAD_VSSIO_L_1();
PVSS2DGZ_G uPAD_VSSIO_L_2();

// Right
PVDD2POC_G uPAD_VDDIO_R_0();
PVDD2DGZ_G uPAD_VDDIO_R_1();
PVDD2DGZ_G uPAD_VDDIO_R_2();
PVSS2DGZ_G uPAD_VSSIO_R_0();
PVSS2DGZ_G uPAD_VSSIO_R_1();
PVSS2DGZ_G uPAD_VSSIO_R_2();


// --------------------------------------------------------------------------
// Clocks and reset
// Externally driven at all times -> no keeper (REN=1).
// --------------------------------------------------------------------------

PDDW04DGZ_G  uPAD_CLK_I (
    .C(soc_sys_fclk),
    .REN(tiehi),
    .I(tielo),
    .OEN(tiehi),
    .PAD(CLK)
   );

PDDW04DGZ_G  uPAD_NRST_I (
    .C(soc_sys_sysresetn),
    .REN(tiehi),
    .I(tielo),
    .OEN(tiehi),
    .PAD(NRST)
   );

PDDW04DGZ_G  uPAD_RTC_CLK_I (
    .C(soc_rtc_clk),
    .REN(tiehi),
    .I(tielo),
    .OEN(tiehi),
    .PAD(RTC_CLK)
   );

PDDW04DGZ_G uPAD_RMII_REF_CLK(
  .C(soc_rmii_ref_clk),
  .REN(tiehi),
  .I(tielo),
  .OEN(tiehi),
  .PAD(RMII_REF_CLK)
);

PDDW04DGZ_G  uPAD_USER_REF_CLK_I (
    .C(soc_user_ref_clk),
    .REN(tiehi),
    .I(tielo),
    .OEN(tiehi),
    .PAD(USER_REF_CLK)
   );

// --------------------------------------------------------------------------
// DFT
// Straps: pull-DOWN keepers so an unstrapped die boots functional, not in scan.
// SCAN_CLK is a clock -> no keeper.
// --------------------------------------------------------------------------

PDDW04DGZ_G  uPAD_SE_I (
    .C(soc_sys_scanenable),
    .REN(tielo),
    .I(tielo),
    .OEN(tiehi),
    .PAD(SE)
   );

PDDW04DGZ_G  uPAD_TEST_I (
    .C(soc_sys_testmode),
    .REN(tielo),
    .I(tielo),
    .OEN(tiehi),
    .PAD(TEST)
   );

PDDW04DGZ_G  uPAD_SCAN_MODE_I (
    .C(soc_scan_mode),
    .REN(tielo),
    .I(tielo),
    .OEN(tiehi),
    .PAD(SCAN_MODE)
   );

PDDW04DGZ_G  uPAD_SCAN_ASYNCRST_CTRL_I (
    .C(soc_scan_asyncrst_ctrl),
    .REN(tielo),
    .I(tielo),
    .OEN(tiehi),
    .PAD(SCAN_ASYNCRST_CTRL)
   );

PDDW04DGZ_G  uPAD_SCAN_CLK_I (
    .C(soc_scan_clk),
    .REN(tiehi),
    .I(tielo),
    .OEN(tiehi),
    .PAD(SCAN_CLK)
   );

PDDW04DGZ_G  uPAD_SCAN_SHIFT_I (
    .C(soc_scan_shift),
    .REN(tielo),
    .I(tielo),
    .OEN(tiehi),
    .PAD(SCAN_SHIFT)
   );

PDDW04DGZ_G  uPAD_SCAN_IN_I (
    .C(soc_scan_in),
    .REN(tielo),
    .I(tielo),
    .OEN(tiehi),
    .PAD(SCAN_IN)
   );

PDDW16DGZ_G  uPAD_SCAN_OUT_O (
    .C(),
    .REN(tiehi),
    .I(soc_scan_out),
    .OEN(tielo),
    .PAD(SCAN_OUT)
   );

// --------------------------------------------------------------------------
// Link bring-up straps
// Pull-DOWN keepers give a defined value if a strap is left open. NOTE:
// ROLE_STRAP MUST be strapped to OPPOSITE values on the two dies -- the keeper
// is a safety net, not the plan. Both dies at 0 POR nego_priority_reg to the
// same 16'h0001 and autoneg cannot break the tie (Bug N7; see
// axi_chiplet_controller.sv:678 and sys_desc/chip_boundary/*.yaml).
// --------------------------------------------------------------------------

PDDW04DGZ_G  uPAD_ROLE_STRAP_I (
    .C(soc_role_strap),
    .REN(tielo),
    .I(tielo),
    .OEN(tiehi),
    .PAD(ROLE_STRAP)
   );

PDDW04DGZ_G  uPAD_MASK_HS_BYPASS_I (
    .C(soc_mask_hs_bypass),
    .REN(tielo),
    .I(tielo),
    .OEN(tiehi),
    .PAD(MASK_HS_BYPASS)
   );

PDDW04DGZ_G  uPAD_APB_DEBUG_UNLOCK_I (
    .C(soc_apb_debug_unlock),
    .REN(tielo),
    .I(tielo),
    .OEN(tiehi),
    .PAD(APB_DEBUG_UNLOCK)
   );

// --------------------------------------------------------------------------
// CoreSight SWJ-DP
// SWDIO/TDI/NTRST take pull-UP keepers: SWD idles high, and NTRST is an
// active-low reset that must NOT assert when the pad is left open.
// dap_swdoen is active_high  -> OEN = ~oe
// dap_ntdoen is active_low   -> OEN =  oe   (already "not TDO enable")
// --------------------------------------------------------------------------

PDDW04DGZ_G  uPAD_SWDCK_I (
    .C(soc_dap_swclktck),
    .REN(tiehi),
    .I(tielo),
    .OEN(tiehi),
    .PAD(SWDCK)
   );

PDUW08DGZ_G  uPAD_SWDIO_IO (
    .C(soc_dap_swditms),
    .REN(tielo),
    .I(soc_dap_swdo),
    .OEN(~soc_dap_swdoen),
    .PAD(SWDIO)
   );

PDUW04DGZ_G  uPAD_JTAG_TDI_I (
    .C(soc_dap_tdi),
    .REN(tielo),
    .I(tielo),
    .OEN(tiehi),
    .PAD(JTAG_TDI)
   );

PDDW16DGZ_G  uPAD_JTAG_TDO_O (
    .C(),
    .REN(tiehi),
    .I(soc_dap_tdo),
    .OEN(soc_dap_ntdoen),
    .PAD(JTAG_TDO)
   );

PDUW04DGZ_G  uPAD_JTAG_NTRST_I (
    .C(soc_dap_ntrst),
    .REN(tielo),
    .I(tielo),
    .OEN(tiehi),
    .PAD(JTAG_NTRST)
   );

// --------------------------------------------------------------------------
// UARTs
// RXD takes a pull-UP keeper: UART idle is HIGH, and a pull-down would present
// a permanent start-bit / break to the receiver when the pad is left open.
// --------------------------------------------------------------------------

PDUW04DGZ_G uPAD_UART_RXD_I(
  .C(soc_uart_rxd),
  .REN(tielo),
  .I(tielo),
  .OEN(tiehi),
  .PAD(UART_RXD)
);

PDDW16DGZ_G uPAD_UART_TXD_O(
  .C(),
  .REN(tiehi),
  .I(soc_uart_txd),
  .OEN(tielo),
  .PAD(UART_TXD)
);

PDUW04DGZ_G uPAD_CPU1_UART_RXD_I(
  .C(soc_chip_core_uart_rxd),
  .REN(tielo),
  .I(tielo),
  .OEN(tiehi),
  .PAD(CPU1_UART_RXD)
);

PDDW16DGZ_G uPAD_CPU1_UART_TXD_O(
  .C(),
  .REN(tiehi),
  .I(soc_chip_core_uart_txd),
  .OEN(tielo),
  .PAD(CPU1_UART_TXD)
);

// --------------------------------------------------------------------------
// QSPI Pads
// qspi_io_e is active_high -> OEN = ~oe
// --------------------------------------------------------------------------

PDDW16DGZ_G uPAD_QSPI_SCLK (
  .C(),
  .REN(tiehi),
  .I(soc_qspi_sclk),
  .OEN(tielo),
  .PAD(QSPI_SCLK)
);
PDDW16DGZ_G uPAD_QSPI_nCS (
  .C(),
  .REN(tiehi),
  .I(soc_qspi_csn),
  .OEN(tielo),
  .PAD(QSPI_nCS)
);
PDDW16DGZ_G uPAD_QSPI_IO_0(
  .C(soc_qspi_io_i[0]),
  .REN(tiehi),
  .I(soc_qspi_io_o[0]),
  .OEN(~soc_qspi_io_e[0]),
  .PAD(QSPI_IO[0])
);
PDDW16DGZ_G uPAD_QSPI_IO_1(
  .C(soc_qspi_io_i[1]),
  .REN(tiehi),
  .I(soc_qspi_io_o[1]),
  .OEN(~soc_qspi_io_e[1]),
  .PAD(QSPI_IO[1])
);
PDDW16DGZ_G uPAD_QSPI_IO_2(
  .C(soc_qspi_io_i[2]),
  .REN(tiehi),
  .I(soc_qspi_io_o[2]),
  .OEN(~soc_qspi_io_e[2]),
  .PAD(QSPI_IO[2])
);
PDDW16DGZ_G uPAD_QSPI_IO_3(
  .C(soc_qspi_io_i[3]),
  .REN(tiehi),
  .I(soc_qspi_io_o[3]),
  .OEN(~soc_qspi_io_e[3]),
  .PAD(QSPI_IO[3])
);

// --------------------------------------------------------------------------
// PL022 SPI master
// --------------------------------------------------------------------------

PDDW16DGZ_G uPAD_SPI_SCLK_O(
  .C(),
  .REN(tiehi),
  .I(soc_spi_sclk),
  .OEN(tielo),
  .PAD(SPI_SCLK)
);

PDDW16DGZ_G uPAD_SPI_MOSI_O(
  .C(),
  .REN(tiehi),
  .I(soc_spi_mosi),
  .OEN(tielo),
  .PAD(SPI_MOSI)
);

PDDW04DGZ_G uPAD_SPI_MISO_I(
  .C(soc_spi_miso),
  .REN(tielo),
  .I(tielo),
  .OEN(tiehi),
  .PAD(SPI_MISO)
);

PDDW16DGZ_G uPAD_SPI_SS_0(
  .C(),
  .REN(tiehi),
  .I(soc_spi_ss[0]),
  .OEN(tielo),
  .PAD(SPI_SS[0])
);

PDDW16DGZ_G uPAD_SPI_SS_1(
  .C(),
  .REN(tiehi),
  .I(soc_spi_ss[1]),
  .OEN(tielo),
  .PAD(SPI_SS[1])
);

PDDW16DGZ_G uPAD_SPI_SS_2(
  .C(),
  .REN(tiehi),
  .I(soc_spi_ss[2]),
  .OEN(tielo),
  .PAD(SPI_SS[2])
);

// --------------------------------------------------------------------------
// HOSTIO4
// hostio4_p1_outen is active_high -> OEN = ~oe
// --------------------------------------------------------------------------

PDDW16DGZ_G uPAD_HOST_IO_0(
  .C(soc_hostio4_p1_in[0]),
  .REN(tiehi),
  .I(soc_hostio4_p1_out[0]),
  .OEN(~soc_hostio4_p1_outen[0]),
  .PAD(HOSTIO4_P1[0])
);

PDDW16DGZ_G uPAD_HOST_IO_1(
  .C(soc_hostio4_p1_in[1]),
  .REN(tiehi),
  .I(soc_hostio4_p1_out[1]),
  .OEN(~soc_hostio4_p1_outen[1]),
  .PAD(HOSTIO4_P1[1])
);

PDDW16DGZ_G uPAD_HOST_IO_2(
  .C(soc_hostio4_p1_in[2]),
  .REN(tiehi),
  .I(soc_hostio4_p1_out[2]),
  .OEN(~soc_hostio4_p1_outen[2]),
  .PAD(HOSTIO4_P1[2])
);

PDDW16DGZ_G uPAD_HOST_IO_3(
  .C(soc_hostio4_p1_in[3]),
  .REN(tiehi),
  .I(soc_hostio4_p1_out[3]),
  .OEN(~soc_hostio4_p1_outen[3]),
  .PAD(HOSTIO4_P1[3])
);

PDDW16DGZ_G uPAD_HOST_IO_4(
  .C(soc_hostio4_p1_in[4]),
  .REN(tiehi),
  .I(soc_hostio4_p1_out[4]),
  .OEN(~soc_hostio4_p1_outen[4]),
  .PAD(HOSTIO4_P1[4])
);

PDDW16DGZ_G uPAD_HOST_IO_5(
  .C(soc_hostio4_p1_in[5]),
  .REN(tiehi),
  .I(soc_hostio4_p1_out[5]),
  .OEN(~soc_hostio4_p1_outen[5]),
  .PAD(HOSTIO4_P1[5])
);

PDDW16DGZ_G uPAD_HOST_IO_6(
  .C(soc_hostio4_p1_in[6]),
  .REN(tiehi),
  .I(soc_hostio4_p1_out[6]),
  .OEN(~soc_hostio4_p1_outen[6]),
  .PAD(HOSTIO4_P1[6])
);

// --------------------------------------------------------------------------
// Ethernet RMII + MDIO
// md_padoe_o is active_high -> OEN = ~oe
// --------------------------------------------------------------------------

PDDW16DGZ_G uPAD_RMII_TXD0(
  .C(),
  .REN(tiehi),
  .I(soc_rmii_txd[0]),
  .OEN(tielo),
  .PAD(RMII_TXD[0])
);

PDDW16DGZ_G uPAD_RMII_TXD1(
  .C(),
  .REN(tiehi),
  .I(soc_rmii_txd[1]),
  .OEN(tielo),
  .PAD(RMII_TXD[1])
);

PDDW16DGZ_G uPAD_RMII_TX_EN(
  .C(),
  .REN(tiehi),
  .I(soc_rmii_tx_en),
  .OEN(tielo),
  .PAD(RMII_TX_EN)
);

PDDW04DGZ_G uPAD_RMII_RXD0(
  .C(soc_rmii_rxd[0]),
  .REN(tielo),
  .I(tielo),
  .OEN(tiehi),
  .PAD(RMII_RXD[0])
);

PDDW04DGZ_G uPAD_RMII_RXD1(
  .C(soc_rmii_rxd[1]),
  .REN(tielo),
  .I(tielo),
  .OEN(tiehi),
  .PAD(RMII_RXD[1])
);

PDDW04DGZ_G uPAD_RMII_CRS_DV(
  .C(soc_rmii_crs_dv),
  .REN(tielo),
  .I(tielo),
  .OEN(tiehi),
  .PAD(RMII_CRS_DV)
);

PDDW16DGZ_G uPAD_RMII_MDIO(
  .C(soc_md_pad_i),
  .REN(tiehi),
  .I(soc_md_pad_o),
  .OEN(~soc_md_padoe_o),
  .PAD(RMII_MDIO)
);

PDDW16DGZ_G uPAD_RMII_MDC(
  .C(),
  .REN(tiehi),
  .I(soc_mdc_pad_o),
  .OEN(tielo),
  .PAD(RMII_MDC)
);

// --------------------------------------------------------------------------
// PTP 1PPS
// --------------------------------------------------------------------------

PDDW16DGZ_G uPAD_PHC_PPS_OUT_O(
  .C(),
  .REN(tiehi),
  .I(soc_phc_pps_out),
  .OEN(tielo),
  .PAD(PHC_PPS_OUT)
);

// --------------------------------------------------------------------------
// Tidelink Pads
// --------------------------------------------------------------------------

PDDW16DGZ_G uPAD_TL_CLK_TX(
  .C(),
  .REN(tiehi),
  .I(soc_pad_clk_tx),
  .OEN(tielo),
  .PAD(TL_CLK_TX)
);
PDDW16DGZ_G uPAD_TL_TX_0(
  .C(),
  .REN(tiehi),
  .I(soc_pad_tx[0]),
  .OEN(tielo),
  .PAD(TL_TX[0])
);
PDDW16DGZ_G uPAD_TL_TX_1(
  .C(),
  .REN(tiehi),
  .I(soc_pad_tx[1]),
  .OEN(tielo),
  .PAD(TL_TX[1])
);
PDDW16DGZ_G uPAD_TL_TX_2(
  .C(),
  .REN(tiehi),
  .I(soc_pad_tx[2]),
  .OEN(tielo),
  .PAD(TL_TX[2])
);
PDDW16DGZ_G uPAD_TL_TX_3(
  .C(),
  .REN(tiehi),
  .I(soc_pad_tx[3]),
  .OEN(tielo),
  .PAD(TL_TX[3])
);
PDDW16DGZ_G uPAD_TL_TX_4(
  .C(),
  .REN(tiehi),
  .I(soc_pad_tx[4]),
  .OEN(tielo),
  .PAD(TL_TX[4])
);
PDDW16DGZ_G uPAD_TL_TX_5(
  .C(),
  .REN(tiehi),
  .I(soc_pad_tx[5]),
  .OEN(tielo),
  .PAD(TL_TX[5])
);
PDDW16DGZ_G uPAD_TL_TX_6(
  .C(),
  .REN(tiehi),
  .I(soc_pad_tx[6]),
  .OEN(tielo),
  .PAD(TL_TX[6])
);
PDDW16DGZ_G uPAD_TL_TX_7(
  .C(),
  .REN(tiehi),
  .I(soc_pad_tx[7]),
  .OEN(tielo),
  .PAD(TL_TX[7])
);
PDDW16DGZ_G uPAD_TL_CLK_RX(
  .C(soc_pad_clk_rx),
  .REN(tiehi),
  .I(tielo),
  .OEN(tiehi),
  .PAD(TL_CLK_RX)
);
PDDW16DGZ_G uPAD_TL_RX_0(
  .C(soc_pad_rx[0]),
  .REN(tiehi),
  .I(tielo),
  .OEN(tiehi),
  .PAD(TL_RX[0])
);
PDDW16DGZ_G uPAD_TL_RX_1(
  .C(soc_pad_rx[1]),
  .REN(tiehi),
  .I(tielo),
  .OEN(tiehi),
  .PAD(TL_RX[1])
);
PDDW16DGZ_G uPAD_TL_RX_2(
  .C(soc_pad_rx[2]),
  .REN(tiehi),
  .I(tielo),
  .OEN(tiehi),
  .PAD(TL_RX[2])
);
PDDW16DGZ_G uPAD_TL_RX_3(
  .C(soc_pad_rx[3]),
  .REN(tiehi),
  .I(tielo),
  .OEN(tiehi),
  .PAD(TL_RX[3])
);
PDDW16DGZ_G uPAD_TL_RX_4(
  .C(soc_pad_rx[4]),
  .REN(tiehi),
  .I(tielo),
  .OEN(tiehi),
  .PAD(TL_RX[4])
);
PDDW16DGZ_G uPAD_TL_RX_5(
  .C(soc_pad_rx[5]),
  .REN(tiehi),
  .I(tielo),
  .OEN(tiehi),
  .PAD(TL_RX[5])
);
PDDW16DGZ_G uPAD_TL_RX_6(
  .C(soc_pad_rx[6]),
  .REN(tiehi),
  .I(tielo),
  .OEN(tiehi),
  .PAD(TL_RX[6])
);
PDDW16DGZ_G uPAD_TL_RX_7(
  .C(soc_pad_rx[7]),
  .REN(tiehi),
  .I(tielo),
  .OEN(tiehi),
  .PAD(TL_RX[7])
);

// --------------------------------------------------------------------------
// TideLink I2C sideband -- OPEN DRAIN.
// PDUW* for the on-die pull-up keeper (the bus still wants its board pull-ups).
// i2c_*_t is oe_polarity: active_low -- "1 = float" -- and OEN is an active-low
// output enable, so OEN maps to _t DIRECTLY. Do NOT invert: `.OEN(~t)` drives
// the bus exactly when TideLink is releasing it, which breaks wired-AND
// arbitration and slave clock-stretching (axi_chiplet_controller.sv:3072).
// --------------------------------------------------------------------------

PDUW16DGZ_G uPAD_I2C_SCL(
  .C(soc_i2c_scl_i),
  .REN(tielo),
  .I(soc_i2c_scl_o),
  .OEN(soc_i2c_scl_t),
  .PAD(I2C_SCL)
);
PDUW16DGZ_G uPAD_I2C_SDA(
  .C(soc_i2c_sda_i),
  .REN(tielo),
  .I(soc_i2c_sda_o),
  .OEN(soc_i2c_sda_t),
  .PAD(I2C_SDA)
);

endmodule
