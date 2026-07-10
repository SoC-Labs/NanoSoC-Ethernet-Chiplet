// =============================================================================
// tb_g2_soc_pair.sv — "full G2": TWO real `nanosoc_eth_chiplet` dies cross-wired
// through the TideLink GPIO-PHY pads, proving a transaction crosses from die A's
// D2D peer window into die B's REAL `shared_sram_0`.
//
// A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
//
// Copyright 2026, SoC Labs (www.soclabs.org)
// =============================================================================
// This is the step `verif/g2_peer_aperture` deferred. That testbench stands an
// AHB master model in for CPU0 and an `ahb_probe_mem` in for the far die's
// fabric; it proves the LINK carries a translated transaction, but not that the
// transaction originates in a real SoC and terminates in a real SoC's SRAM.
//
// Here both ends are the shipping integration top `nanosoc_eth_chiplet`, which
// bundles, per die:
//
//     nanosoc_multicore_soc  ->  chiplet_d2d_decode  ->  tidelink_top
//                                                            |  ahb_mng
//                                                            v
//                                        (that die's own) d2d_ahb_s -> shared_sram_0
//
// so the far die's `ahb_mng` already drives its OWN SoC's inbound D2D port. No
// probe memory is needed: die B's real `shared_sram_0` (reachable from the
// inbound port at 0x2D000000, see soc_d2d_loopback) is the observation point.
//
// The address arithmetic falls out for free. TideLink's CAM rewrites
// `addr[31:24]` 0x2F -> 0x2D (verif/g2_peer_aperture). The SoC's inbound D2D
// port routes 0x2D to `shared_sram_0`. So die A's peer write to 0x2F00_1000
// lands, untouched but for the upper byte, in die B's shared SRAM at 0x2D00_1000.
//
// FIRMWARE-FREE, exactly as soc_d2d_loopback: CPU0 is the boot-gated secondary
// and is never released; CPU1 runs its stage-0 bootrom, finds no BOOT table in
// the unprogrammed flash model and halts on the magic mismatch. Both cores leave
// the bus free. Every stimulus — link bring-up over APB, the peer write, the
// read-back — is driven by an EXTERNAL master on each die's `eth_ss_0` port,
// which reaches the 0x2E/0x2F D2D window through the eth subsystem passthrough.
//
// Nothing here forks any of the three components; it instantiates the wrapper
// twice and joins the pads. The pad cross-wire, the `pad_skid`, the I2C wired-AND
// and the straps are lifted from `verif/g2_peer_aperture/tb_pair.sv`.
// =============================================================================
`timescale 1ns/1ps

module tb_g2_soc_pair #(
`ifdef TB_TOP_SKID_BITS
    parameter int SKID_BITS = `TB_TOP_SKID_BITS,
`else
    parameter int SKID_BITS = 0,
`endif
    parameter int NUM_PHY_LANES = 8,
    parameter     FCLK_PERIOD_NS = 20,   // 50 MHz application/AHB clock
    parameter     REF_PERIOD_NS  = 8     // 125 MHz Wlink PLL reference
);

    // ---------------------------------------------------------------------
    // Shared clocks. Generated in-tb (as soc_d2d_loopback does) so a cocotb
    // test drives transactions synchronous to `sys_fclk` without owning a
    // clock. `ref_clk` is the Wlink PLL reference, shared by both dies.
    // ---------------------------------------------------------------------
    reg sys_fclk = 1'b0;
    always #(FCLK_PERIOD_NS/2.0) sys_fclk = ~sys_fclk;

    reg ref_clk = 1'b0;
    always #(REF_PERIOD_NS/2.0) ref_clk = ~ref_clk;

    // Per-die system reset. Separate so a test can skew one die's reset against
    // the other (the far-die-in-reset wedge case). Both follow the same POR
    // sequence by default; cocotb may override either.
    reg a_sysresetn = 1'b0;
    reg b_sysresetn = 1'b0;
    initial begin
        a_sysresetn = 1'b0;
        b_sysresetn = 1'b0;
        #200;
        a_sysresetn = 1'b1;
        b_sysresetn = 1'b1;
    end

    // Per-die "pad drive enabled" gates. A die held in reset must not X-poison
    // the live die through the pads; squash its pad drive to 0. Default 1.
    reg a_pad_en = 1'b1;
    reg b_pad_en = 1'b1;

    // =====================================================================
    // PHY pads, cross-wired through pad_skid (SKID_BITS=0 => passthrough),
    // exactly as tb_pair.sv.
    // =====================================================================
    wire                     a_pad_clk_tx, b_pad_clk_tx;
    wire [NUM_PHY_LANES-1:0] a_pad_tx,     b_pad_tx;
    wire                     a_pad_clk_tx_skid, b_pad_clk_tx_skid;
    wire [NUM_PHY_LANES-1:0] a_pad_tx_skid,     b_pad_tx_skid;

    pad_skid #(.SKID_BITS(SKID_BITS), .LANES(NUM_PHY_LANES)) u_skid_a2b (
        .pad_clk_in (a_pad_clk_tx),      .pad_data_in (a_pad_tx),
        .pad_clk_out(a_pad_clk_tx_skid), .pad_data_out(a_pad_tx_skid));

    pad_skid #(.SKID_BITS(SKID_BITS), .LANES(NUM_PHY_LANES)) u_skid_b2a (
        .pad_clk_in (b_pad_clk_tx),      .pad_data_in (b_pad_tx),
        .pad_clk_out(b_pad_clk_tx_skid), .pad_data_out(b_pad_tx_skid));

    // =====================================================================
    // I2C sideband: open-drain wired-AND with pull-ups, as tb_pair.sv.
    // =====================================================================
    wire a_i2c_scl_o, a_i2c_scl_t, a_i2c_sda_o, a_i2c_sda_t;
    wire b_i2c_scl_o, b_i2c_scl_t, b_i2c_sda_o, b_i2c_sda_t;
    wire i2c_scl = (a_i2c_scl_t ? 1'b1 : a_i2c_scl_o) & (b_i2c_scl_t ? 1'b1 : b_i2c_scl_o);
    wire i2c_sda = (a_i2c_sda_t ? 1'b1 : a_i2c_sda_o) & (b_i2c_sda_t ? 1'b1 : b_i2c_sda_o);

    // =====================================================================
    // Per-die eth_ss_0 external AHB master ports (cocotb-driven). Reaches the
    // top matrix through the eth subsystem `system` passthrough, hence the D2D
    // window (link bring-up APB @0x2E03xxxx, peer aperture @0x2F......) and
    // shared_sram_0 (@0x2D......) without firmware.
    // =====================================================================
    // -- Die A --
    reg  [31:0] a_eth_ss_0_haddr  = 32'h0;
    reg   [1:0] a_eth_ss_0_htrans = 2'b00;
    reg         a_eth_ss_0_hwrite = 1'b0;
    reg   [2:0] a_eth_ss_0_hsize  = 3'b010;
    reg   [2:0] a_eth_ss_0_hburst = 3'b000;
    reg   [3:0] a_eth_ss_0_hprot  = 4'h0;
    reg  [31:0] a_eth_ss_0_hwdata = 32'h0;
    reg         a_eth_ss_0_hmastlock = 1'b0;
    wire [31:0] a_eth_ss_0_hrdata;
    wire        a_eth_ss_0_hready;
    wire        a_eth_ss_0_hresp;
    // -- Die B --
    reg  [31:0] b_eth_ss_0_haddr  = 32'h0;
    reg   [1:0] b_eth_ss_0_htrans = 2'b00;
    reg         b_eth_ss_0_hwrite = 1'b0;
    reg   [2:0] b_eth_ss_0_hsize  = 3'b010;
    reg   [2:0] b_eth_ss_0_hburst = 3'b000;
    reg   [3:0] b_eth_ss_0_hprot  = 4'h0;
    reg  [31:0] b_eth_ss_0_hwdata = 32'h0;
    reg         b_eth_ss_0_hmastlock = 1'b0;
    wire [31:0] b_eth_ss_0_hrdata;
    wire        b_eth_ss_0_hready;
    wire        b_eth_ss_0_hresp;

    // =====================================================================
    // Per-die SoC boundary observability (unused nets are named so cocotb can
    // read them and so the elaborator does not warn on open outputs).
    // =====================================================================
    // -- Die A --
    wire        a_sys_poresetn, a_sys_hclk, a_sys_hresetn;
    wire        a_network_core_txev, a_network_core_lockup, a_network_core_sysresetreq;
    wire        a_network_core_sleeping, a_network_core_sleepdeep;
    wire        a_chip_core_txev, a_chip_core_lockup, a_chip_core_sysresetreq;
    wire        a_chip_core_sleeping, a_chip_core_sleepdeep;
    wire        a_dap_swdo, a_dap_swdoen, a_dap_tdo, a_dap_ntdoen;
    wire  [1:0] a_rmii_txd;  wire a_rmii_tx_en;
    wire        a_mdc_pad_o, a_md_pad_o, a_md_padoe_o;
    wire        a_uart_txd, a_chip_core_uart_txd, a_chip_core_wdog_reset;
    wire [31:0] a_rtc_time_ptp_ns;  wire [47:0] a_rtc_time_ptp_sec;  wire a_rtc_time_one_pps;
    wire        a_eth_irq, a_phc_pps_out, a_phc_pps_irq, a_phc_alarm_irq, a_ha1588_servo_locked;
    wire        a_spi_sclk, a_spi_mosi;  wire [2:0] a_spi_ss;
    wire  [6:0] a_hostio4_p1_out, a_hostio4_p1_outen;
    wire        a_scan_out;
    wire        a_link_active_o, a_d2d_reset_o, a_role_is_master_o, a_role_locked_o;
    wire        a_servo_locked_o;  wire [12:0] a_tl_ewma_credit_o;  wire a_tidechart_irq_o;
    // -- Die B --
    wire        b_sys_poresetn, b_sys_hclk, b_sys_hresetn;
    wire        b_network_core_txev, b_network_core_lockup, b_network_core_sysresetreq;
    wire        b_network_core_sleeping, b_network_core_sleepdeep;
    wire        b_chip_core_txev, b_chip_core_lockup, b_chip_core_sysresetreq;
    wire        b_chip_core_sleeping, b_chip_core_sleepdeep;
    wire        b_dap_swdo, b_dap_swdoen, b_dap_tdo, b_dap_ntdoen;
    wire  [1:0] b_rmii_txd;  wire b_rmii_tx_en;
    wire        b_mdc_pad_o, b_md_pad_o, b_md_padoe_o;
    wire        b_uart_txd, b_chip_core_uart_txd, b_chip_core_wdog_reset;
    wire [31:0] b_rtc_time_ptp_ns;  wire [47:0] b_rtc_time_ptp_sec;  wire b_rtc_time_one_pps;
    wire        b_eth_irq, b_phc_pps_out, b_phc_pps_irq, b_phc_alarm_irq, b_ha1588_servo_locked;
    wire        b_spi_sclk, b_spi_mosi;  wire [2:0] b_spi_ss;
    wire  [6:0] b_hostio4_p1_out, b_hostio4_p1_outen;
    wire        b_scan_out;
    wire        b_link_active_o, b_d2d_reset_o, b_role_is_master_o, b_role_locked_o;
    wire        b_servo_locked_o;  wire [12:0] b_tl_ewma_credit_o;  wire b_tidechart_irq_o;

    // =====================================================================
    // Per-die QSPI flash. Unprogrammed => CPU1 stage-0 reads 0xFF for the
    // BOOT-table magic and halts, keeping the bus free. Same tri-state bridge
    // and flash model as soc_d2d_loopback.
    // =====================================================================
    // -- Die A --
    wire       a_qspi_sclk, a_qspi_csn;
    wire [3:0] a_qspi_io_o, a_qspi_io_e, a_qspi_io_i;
    wire [3:0] a_spi_io;
    // -- Die B --
    wire       b_qspi_sclk, b_qspi_csn;
    wire [3:0] b_qspi_io_o, b_qspi_io_e, b_qspi_io_i;
    wire [3:0] b_spi_io;

    genvar gi;
    generate
        for (gi = 0; gi < 4; gi = gi + 1) begin : g_qspi_iobuf
            assign a_spi_io[gi] = a_qspi_io_e[gi] ? a_qspi_io_o[gi] : 1'bz;
            assign b_spi_io[gi] = b_qspi_io_e[gi] ? b_qspi_io_o[gi] : 1'bz;
        end
    endgenerate
    assign a_qspi_io_i = a_spi_io;
    assign b_qspi_io_i = b_spi_io;

    // =====================================================================
    // Die A — link MASTER (role_strap_i = 0). nego_priority high so it wins the
    // tiebreak; puf_seed distinct from die B.
    // =====================================================================
    nanosoc_eth_chiplet #(.NUM_PHY_LANES(NUM_PHY_LANES)) u_dieA (
        .sys_fclk            (sys_fclk),
        .sys_sysresetn       (a_sysresetn),
        .sys_poresetn        (a_sys_poresetn),
        .sys_hclk            (a_sys_hclk),
        .sys_hresetn         (a_sys_hresetn),
        .sys_scanenable      (1'b0),
        .sys_testmode        (1'b0),
        .sys_sysresetreq     (1'b0),

        .eth_ss_0_haddr      (a_eth_ss_0_haddr),
        .eth_ss_0_htrans     (a_eth_ss_0_htrans),
        .eth_ss_0_hwrite     (a_eth_ss_0_hwrite),
        .eth_ss_0_hsize      (a_eth_ss_0_hsize),
        .eth_ss_0_hburst     (a_eth_ss_0_hburst),
        .eth_ss_0_hprot      (a_eth_ss_0_hprot),
        .eth_ss_0_hwdata     (a_eth_ss_0_hwdata),
        .eth_ss_0_hmastlock  (a_eth_ss_0_hmastlock),
        .eth_ss_0_hrdata     (a_eth_ss_0_hrdata),
        .eth_ss_0_hready     (a_eth_ss_0_hready),
        .eth_ss_0_hresp      (a_eth_ss_0_hresp),

        .network_core_pmuenable (1'b0),
        .chip_core_pmuenable    (1'b0),
        .network_core_nmi       (1'b0),
        .network_core_txev      (a_network_core_txev),
        .network_core_rxev      (1'b0),
        .network_core_lockup    (a_network_core_lockup),
        .network_core_sysresetreq(a_network_core_sysresetreq),
        .network_core_sleeping  (a_network_core_sleeping),
        .network_core_sleepdeep (a_network_core_sleepdeep),
        .chip_core_nmi          (1'b0),
        .chip_core_txev         (a_chip_core_txev),
        .chip_core_rxev         (1'b0),
        .chip_core_lockup       (a_chip_core_lockup),
        .chip_core_sysresetreq  (a_chip_core_sysresetreq),
        .chip_core_sleeping     (a_chip_core_sleeping),
        .chip_core_sleepdeep    (a_chip_core_sleepdeep),

        .dap_swclktck        (1'b0),
        .dap_swditms         (1'b1),
        .dap_swdo            (a_dap_swdo),
        .dap_swdoen          (a_dap_swdoen),
        .dap_tdi             (1'b0),
        .dap_tdo             (a_dap_tdo),
        .dap_ntdoen          (a_dap_ntdoen),
        .dap_ntrst           (1'b1),
        .dap_npotrst         (a_sysresetn),
        .dap_swj_enable      (1'b1),

        .rmii_ref_clk        (1'b0),
        .rmii_txd            (a_rmii_txd),
        .rmii_tx_en          (a_rmii_tx_en),
        .rmii_rxd            (2'b0),
        .rmii_crs_dv         (1'b0),
        .md_pad_i            (1'b1),
        .mdc_pad_o           (a_mdc_pad_o),
        .md_pad_o            (a_md_pad_o),
        .md_padoe_o          (a_md_padoe_o),

        .uart_rxd            (1'b1),
        .uart_txd            (a_uart_txd),
        .chip_core_uart_rxd  (1'b1),
        .chip_core_uart_txd  (a_chip_core_uart_txd),
        .chip_core_wdog_reset(a_chip_core_wdog_reset),

        .rtc_clk             (sys_fclk),
        .rtc_time_ptp_ns     (a_rtc_time_ptp_ns),
        .rtc_time_ptp_sec    (a_rtc_time_ptp_sec),
        .rtc_time_one_pps    (a_rtc_time_one_pps),

        .eth_irq             (a_eth_irq),
        .phc_pps_out         (a_phc_pps_out),
        .phc_pps_irq         (a_phc_pps_irq),
        .phc_alarm_irq       (a_phc_alarm_irq),
        .ha1588_servo_locked (a_ha1588_servo_locked),

        .qspi_sclk           (a_qspi_sclk),
        .qspi_csn            (a_qspi_csn),
        .qspi_io_o           (a_qspi_io_o),
        .qspi_io_i           (a_qspi_io_i),
        .qspi_io_e           (a_qspi_io_e),

        .spi_sclk            (a_spi_sclk),
        .spi_mosi            (a_spi_mosi),
        .spi_miso            (1'b0),
        .spi_ss              (a_spi_ss),

        .hostio4_p1_in       (7'h0),
        .hostio4_p1_out      (a_hostio4_p1_out),
        .hostio4_p1_outen    (a_hostio4_p1_outen),

        // --- TideLink PHY pads (cross-wired below) ---
        .pad_clk_tx          (a_pad_clk_tx),
        .pad_tx              (a_pad_tx),
        .pad_clk_rx          (b_pad_clk_tx_skid & b_pad_en),
        .pad_rx              (b_pad_tx_skid & {NUM_PHY_LANES{b_pad_en}}),
        .user_ref_clk        (ref_clk),
        .idelay_ref_clk      (1'b0),

        // --- I2C sideband + role strap ---
        .i2c_scl_i           (i2c_scl),
        .i2c_scl_o           (a_i2c_scl_o),
        .i2c_scl_t           (a_i2c_scl_t),
        .i2c_sda_i           (i2c_sda),
        .i2c_sda_o           (a_i2c_sda_o),
        .i2c_sda_t           (a_i2c_sda_t),
        .role_strap_i        (1'b0),          // die A drives the link (master)

        // --- Link bring-up straps ---
        .nego_priority_i     (16'h8000),
        .mask_hs_bypass_i    (1'b1),
        .apb_debug_unlock_i  (1'b1),
        .puf_seed            (16'hA5A5),
        .puf_ready           (1'b1),

        // --- DFT ---
        .scan_mode           (1'b0),
        .scan_asyncrst_ctrl  (1'b0),
        .scan_clk            (1'b0),
        .scan_shift          (1'b0),
        .scan_in             (1'b0),
        .scan_out            (a_scan_out),

        // --- Status / observability ---
        .link_active_o       (a_link_active_o),
        .d2d_reset_o         (a_d2d_reset_o),
        .role_is_master_o    (a_role_is_master_o),
        .role_locked_o       (a_role_locked_o),
        .servo_locked_o      (a_servo_locked_o),
        .tl_ewma_credit_o    (a_tl_ewma_credit_o),
        .tidechart_irq_o     (a_tidechart_irq_o)
    );

    // =====================================================================
    // Die B — link SLAVE (role_strap_i = 1). nego_priority low; puf_seed distinct.
    // Its `ahb_mng` drives its own SoC's inbound D2D port, so the observation
    // point is die B's REAL shared_sram_0 (reachable at 0x2D...... from inbound).
    // =====================================================================
    nanosoc_eth_chiplet #(.NUM_PHY_LANES(NUM_PHY_LANES)) u_dieB (
        .sys_fclk            (sys_fclk),
        .sys_sysresetn       (b_sysresetn),
        .sys_poresetn        (b_sys_poresetn),
        .sys_hclk            (b_sys_hclk),
        .sys_hresetn         (b_sys_hresetn),
        .sys_scanenable      (1'b0),
        .sys_testmode        (1'b0),
        .sys_sysresetreq     (1'b0),

        .eth_ss_0_haddr      (b_eth_ss_0_haddr),
        .eth_ss_0_htrans     (b_eth_ss_0_htrans),
        .eth_ss_0_hwrite     (b_eth_ss_0_hwrite),
        .eth_ss_0_hsize      (b_eth_ss_0_hsize),
        .eth_ss_0_hburst     (b_eth_ss_0_hburst),
        .eth_ss_0_hprot      (b_eth_ss_0_hprot),
        .eth_ss_0_hwdata     (b_eth_ss_0_hwdata),
        .eth_ss_0_hmastlock  (b_eth_ss_0_hmastlock),
        .eth_ss_0_hrdata     (b_eth_ss_0_hrdata),
        .eth_ss_0_hready     (b_eth_ss_0_hready),
        .eth_ss_0_hresp      (b_eth_ss_0_hresp),

        .network_core_pmuenable (1'b0),
        .chip_core_pmuenable    (1'b0),
        .network_core_nmi       (1'b0),
        .network_core_txev      (b_network_core_txev),
        .network_core_rxev      (1'b0),
        .network_core_lockup    (b_network_core_lockup),
        .network_core_sysresetreq(b_network_core_sysresetreq),
        .network_core_sleeping  (b_network_core_sleeping),
        .network_core_sleepdeep (b_network_core_sleepdeep),
        .chip_core_nmi          (1'b0),
        .chip_core_txev         (b_chip_core_txev),
        .chip_core_rxev         (1'b0),
        .chip_core_lockup       (b_chip_core_lockup),
        .chip_core_sysresetreq  (b_chip_core_sysresetreq),
        .chip_core_sleeping     (b_chip_core_sleeping),
        .chip_core_sleepdeep    (b_chip_core_sleepdeep),

        .dap_swclktck        (1'b0),
        .dap_swditms         (1'b1),
        .dap_swdo            (b_dap_swdo),
        .dap_swdoen          (b_dap_swdoen),
        .dap_tdi             (1'b0),
        .dap_tdo             (b_dap_tdo),
        .dap_ntdoen          (b_dap_ntdoen),
        .dap_ntrst           (1'b1),
        .dap_npotrst         (b_sysresetn),
        .dap_swj_enable      (1'b1),

        .rmii_ref_clk        (1'b0),
        .rmii_txd            (b_rmii_txd),
        .rmii_tx_en          (b_rmii_tx_en),
        .rmii_rxd            (2'b0),
        .rmii_crs_dv         (1'b0),
        .md_pad_i            (1'b1),
        .mdc_pad_o           (b_mdc_pad_o),
        .md_pad_o            (b_md_pad_o),
        .md_padoe_o          (b_md_padoe_o),

        .uart_rxd            (1'b1),
        .uart_txd            (b_uart_txd),
        .chip_core_uart_rxd  (1'b1),
        .chip_core_uart_txd  (b_chip_core_uart_txd),
        .chip_core_wdog_reset(b_chip_core_wdog_reset),

        .rtc_clk             (sys_fclk),
        .rtc_time_ptp_ns     (b_rtc_time_ptp_ns),
        .rtc_time_ptp_sec    (b_rtc_time_ptp_sec),
        .rtc_time_one_pps    (b_rtc_time_one_pps),

        .eth_irq             (b_eth_irq),
        .phc_pps_out         (b_phc_pps_out),
        .phc_pps_irq         (b_phc_pps_irq),
        .phc_alarm_irq       (b_phc_alarm_irq),
        .ha1588_servo_locked (b_ha1588_servo_locked),

        .qspi_sclk           (b_qspi_sclk),
        .qspi_csn            (b_qspi_csn),
        .qspi_io_o           (b_qspi_io_o),
        .qspi_io_i           (b_qspi_io_i),
        .qspi_io_e           (b_qspi_io_e),

        .spi_sclk            (b_spi_sclk),
        .spi_mosi            (b_spi_mosi),
        .spi_miso            (1'b0),
        .spi_ss              (b_spi_ss),

        .hostio4_p1_in       (7'h0),
        .hostio4_p1_out      (b_hostio4_p1_out),
        .hostio4_p1_outen    (b_hostio4_p1_outen),

        // --- TideLink PHY pads (cross-wired below) ---
        .pad_clk_tx          (b_pad_clk_tx),
        .pad_tx              (b_pad_tx),
        .pad_clk_rx          (a_pad_clk_tx_skid & a_pad_en),
        .pad_rx              (a_pad_tx_skid & {NUM_PHY_LANES{a_pad_en}}),
        .user_ref_clk        (ref_clk),
        .idelay_ref_clk      (1'b0),

        // --- I2C sideband + role strap ---
        .i2c_scl_i           (i2c_scl),
        .i2c_scl_o           (b_i2c_scl_o),
        .i2c_scl_t           (b_i2c_scl_t),
        .i2c_sda_i           (i2c_sda),
        .i2c_sda_o           (b_i2c_sda_o),
        .i2c_sda_t           (b_i2c_sda_t),
        .role_strap_i        (1'b1),          // die B follows (slave)

        // --- Link bring-up straps ---
        .nego_priority_i     (16'h7FFF),
        .mask_hs_bypass_i    (1'b1),
        .apb_debug_unlock_i  (1'b1),
        .puf_seed            (16'h5A5A),
        .puf_ready           (1'b1),

        // --- DFT ---
        .scan_mode           (1'b0),
        .scan_asyncrst_ctrl  (1'b0),
        .scan_clk            (1'b0),
        .scan_shift          (1'b0),
        .scan_in             (1'b0),
        .scan_out            (b_scan_out),

        // --- Status / observability ---
        .link_active_o       (b_link_active_o),
        .d2d_reset_o         (b_d2d_reset_o),
        .role_is_master_o    (b_role_is_master_o),
        .role_locked_o       (b_role_locked_o),
        .servo_locked_o      (b_servo_locked_o),
        .tl_ewma_credit_o    (b_tl_ewma_credit_o),
        .tidechart_irq_o     (b_tidechart_irq_o)
    );

    // =====================================================================
    // Per-die QSPI flash models (unprogrammed).
    // =====================================================================
    sst26vf064b u_flash_a (.SCK(a_qspi_sclk), .SIO(a_spi_io), .CEb(a_qspi_csn));
    defparam u_flash_a.I0.Tbe  = 1_000;
    defparam u_flash_a.I0.Tse  = 1_000;
    defparam u_flash_a.I0.Tsce = 1_000;
    defparam u_flash_a.I0.Tpp  = 1_000;
    defparam u_flash_a.I0.Tws  = 1_000;

    sst26vf064b u_flash_b (.SCK(b_qspi_sclk), .SIO(b_spi_io), .CEb(b_qspi_csn));
    defparam u_flash_b.I0.Tbe  = 1_000;
    defparam u_flash_b.I0.Tse  = 1_000;
    defparam u_flash_b.I0.Tsce = 1_000;
    defparam u_flash_b.I0.Tpp  = 1_000;
    defparam u_flash_b.I0.Tws  = 1_000;

`ifdef DUMP_FSDB
    initial begin
        $dumpfile("waves.vcd");
        $dumpvars(0, tb_g2_soc_pair);
    end
`endif

endmodule
