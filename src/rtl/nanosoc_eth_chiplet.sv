//-----------------------------------------------------------------------------
// nanosoc_eth_chiplet — structural integration top for the nanoSoC ethernet
// chiplet: the multicore SoC, a TideLink die-to-die link, and the TideChart
// chiplet-ID controller, wired side by side.
//
// A joint work commissioned on behalf of SoC Labs, under Arm Academic Access
// license.
//
// Contributors
//
// David Mapstone (d.a.mapstone@soton.ac.uk)
//
// Copyright 2026, SoC Labs (www.soclabs.org)
//-----------------------------------------------------------------------------
// This module owns the INTEGRATION and nothing else — it forks none of the
// three components, it instantiates them. Everything here is dictated by the
// three RTL boundaries; where this file makes a policy choice it says WHY.
//
// The SoC's die-to-die port is deliberately LINK-AGNOSTIC (nothing in the SoC
// names TideLink). All the TideLink-specific knowledge lives at THIS level:
//
//   * d2d_ahb_m  (SoC manager, the 32 MB window 0x2E000000..0x2FFFFFFF) is
//     sub-decoded by u_d2d_decode into TideLink's four AHB subordinates plus
//     two AHB->APB bridges. Address/control/write-data fan out DIRECTLY from
//     d2d_ahb_m to every slave; the decoder owns only the HSELs and the
//     data-phase response mux (see chiplet_d2d_decode.sv header).
//   * d2d_ahb_s  (SoC's 6th matrix initiator) is driven by TideLink's incoming
//     manager port ahb_mng — the remote die reaching shared SRAM + the mailbox.
//   * d2d_irq[15:0] gathers TideLink + TideChart interrupts: [7:0] land on
//     CPU0's NVIC (data plane), [15:8] on CPU1's (link management).
//   * d2d_phc_* is PHC hardware servo source 0 — the cross-die timebase.
//
// GEOMETRY (from the SoC's generated defaults and TideLink's RTL defaults):
//   SYS_ADDR_W = SYS_DATA_W = 32; TideLink RAM_ADDR_W = 14 (the tx/fifo
//   apertures are 16 KB, so their AHB address is haddr[13:0]); TideChart is
//   instantiated single-port (NUM_PORTS=1) with FC_DATA_W=48.
//-----------------------------------------------------------------------------

module nanosoc_eth_chiplet #(
    // TideLink GPIO-PHY lane count. RTL default is 8; kept as a chiplet param so
    // the PHY-pad boundary width tracks the instance parameter in one place.
    parameter NUM_PHY_LANES = 8
) (
    // =========================================================================
    // SoC boundary — EVERY nanosoc_multicore_soc port that is NOT d2d_* is
    // re-exported here 1:1 (same name, same width). The d2d_* ports are
    // consumed internally by the link and never reach this boundary.
    // SYS_ADDR_W = SYS_DATA_W = 32 (the SoC's generated defaults).
    // =========================================================================
    // -- System clock / reset --
    input  wire        sys_fclk,
    input  wire        sys_sysresetn,
    output wire        sys_poresetn,
    output wire        sys_hclk,
    output wire        sys_hresetn,
    input  wire        sys_scanenable,
    input  wire        sys_testmode,
    input  wire        sys_sysresetreq,
    // -- External AHB slave: testbench access to the ethernet subsystem --
    input  wire [31:0] eth_ss_0_haddr,
    input  wire  [1:0] eth_ss_0_htrans,
    input  wire        eth_ss_0_hwrite,
    input  wire  [2:0] eth_ss_0_hsize,
    input  wire  [2:0] eth_ss_0_hburst,
    input  wire  [3:0] eth_ss_0_hprot,
    input  wire [31:0] eth_ss_0_hwdata,
    input  wire        eth_ss_0_hmastlock,
    output wire [31:0] eth_ss_0_hrdata,
    output wire        eth_ss_0_hready,
    output wire        eth_ss_0_hresp,
    // -- CPU0 (network core) / CPU1 (chip core) sideband --
    input  wire        network_core_pmuenable,
    input  wire        chip_core_pmuenable,
    input  wire        network_core_nmi,
    output wire        network_core_txev,
    input  wire        network_core_rxev,
    output wire        network_core_lockup,
    output wire        network_core_sysresetreq,
    output wire        network_core_sleeping,
    output wire        network_core_sleepdeep,
    input  wire        chip_core_nmi,
    output wire        chip_core_txev,
    input  wire        chip_core_rxev,
    output wire        chip_core_lockup,
    output wire        chip_core_sysresetreq,
    output wire        chip_core_sleeping,
    output wire        chip_core_sleepdeep,
    // -- Debug access port (SWJ-DP / JTAG) --
    input  wire        dap_swclktck,
    input  wire        dap_swditms,
    output wire        dap_swdo,
    output wire        dap_swdoen,
    input  wire        dap_tdi,
    output wire        dap_tdo,
    output wire        dap_ntdoen,
    input  wire        dap_ntrst,
    input  wire        dap_npotrst,
    input  wire        dap_swj_enable,
    // -- RMII ethernet PHY --
    input  wire        rmii_ref_clk,
    output wire  [1:0] rmii_txd,
    output wire        rmii_tx_en,
    input  wire  [1:0] rmii_rxd,
    input  wire        rmii_crs_dv,
    // -- MDIO --
    input  wire        md_pad_i,
    output wire        mdc_pad_o,
    output wire        md_pad_o,
    output wire        md_padoe_o,
    // -- UARTs / CPU1 watchdog --
    input  wire        uart_rxd,
    output wire        uart_txd,
    input  wire        chip_core_uart_rxd,
    output wire        chip_core_uart_txd,
    output wire        chip_core_wdog_reset,
    // -- RTC / PTP time out --
    input  wire        rtc_clk,
    output wire [31:0] rtc_time_ptp_ns,
    output wire [47:0] rtc_time_ptp_sec,
    output wire        rtc_time_one_pps,
    // -- Ethernet / PHC interrupts + status --
    output wire        eth_irq,
    output wire        phc_pps_out,   // ALSO drives TideLink phc_pps internally
    output wire        phc_pps_irq,
    output wire        phc_alarm_irq,
    output wire        ha1588_servo_locked,
    // -- QSPI flash --
    output wire        qspi_sclk,
    output wire        qspi_csn,
    output wire  [3:0] qspi_io_o,
    input  wire  [3:0] qspi_io_i,
    output wire  [3:0] qspi_io_e,
    // -- PL022 SPI --
    output wire        spi_sclk,
    output wire        spi_mosi,
    input  wire        spi_miso,
    output wire  [2:0] spi_ss,
    // -- HOSTIO4 P1 --
    input  wire  [6:0] hostio4_p1_in,
    output wire  [6:0] hostio4_p1_out,
    output wire  [6:0] hostio4_p1_outen,

    // =========================================================================
    // TideLink GPIO-PHY pads — the die-to-die wire to the far die.
    // =========================================================================
    output wire                     pad_clk_tx,
    output wire [NUM_PHY_LANES-1:0] pad_tx,
    input  wire                     pad_clk_rx,
    input  wire [NUM_PHY_LANES-1:0] pad_rx,
    input  wire                     user_ref_clk,     // Wlink PLL reference clock
    input  wire                     idelay_ref_clk,   // 200 MHz IDELAYCTRL ref (FPGA IDELAY only)

    // =========================================================================
    // TideLink I2C sideband (open-drain tristate) + role strap.
    // =========================================================================
    input  wire        i2c_scl_i,
    output wire        i2c_scl_o,
    output wire        i2c_scl_t,
    input  wire        i2c_sda_i,
    output wire        i2c_sda_o,
    output wire        i2c_sda_t,
    input  wire        role_strap_i,

    // =========================================================================
    // Link bring-up straps.
    //
    // These were tie-offs. They are ports because a chiplet cannot bring its
    // link up without them, and because their values are a per-die decision the
    // integrator makes at the pad ring, not something this RTL should assume.
    //
    // `nego_priority_i` is the auto-negotiation priority, normally sourced from
    // OTP or a die UID. Two dies that both present 0 have no tiebreak.
    // `mask_hs_bypass_i` and `apb_debug_unlock_i` open the software-driven
    // role-lock path used during bring-up; both were held low, which shut it.
    // `puf_seed` / `puf_ready` come from TideChart's PUF sampler when enabled.
    // =========================================================================
    input  wire [15:0] nego_priority_i,
    input  wire        mask_hs_bypass_i,
    input  wire        apb_debug_unlock_i,
    input  wire [15:0] puf_seed,
    input  wire        puf_ready,

    // =========================================================================
    // DFT. Scan was tied off, which is correct for functional elaboration and
    // wrong for a chip. A production pad ring wires these to the scan
    // controller; leaving them internal would silently drop the chiplet's scan
    // chain on the floor.
    // =========================================================================
    input  wire        scan_mode,
    input  wire        scan_asyncrst_ctrl,
    input  wire        scan_clk,
    input  wire        scan_shift,
    input  wire        scan_in,
    output wire        scan_out,

    // =========================================================================
    // Link status / observability. Bring-up and silicon debug need these; a
    // physical team decides whether each becomes a pad, a test point, or a
    // register bit. They must not be invisible.
    // =========================================================================
    output wire        link_active_o,      // Wlink link layer is up
    output wire        d2d_reset_o,        // die-to-die reset out
    output wire        role_is_master_o,   // resolved link role
    output wire        role_locked_o,      // role latched
    output wire        servo_locked_o,     // TideLink PTP servo lock (NOT the PHC's; see D2D_PORT.md 6f)
    output wire [12:0] tl_ewma_credit_o,   // congestion telemetry
    output wire        tidechart_irq_o     // TideChart controller interrupt
);

    //=========================================================================
    // Internal nets
    //=========================================================================

    // --- D2D outbound: SoC manager d2d_ahb_m -> u_d2d_decode + slaves ---
    // Address/control/write-data are SoC outputs that fan out DIRECTLY to the
    // slaves; the decoder returns the muxed response (hrdata/hready/hresp).
    wire [31:0] d2d_ahb_m_haddr;
    wire  [1:0] d2d_ahb_m_htrans;
    wire        d2d_ahb_m_hwrite;
    wire  [2:0] d2d_ahb_m_hsize;
    wire  [2:0] d2d_ahb_m_hburst;
    wire  [3:0] d2d_ahb_m_hprot;
    wire [31:0] d2d_ahb_m_hwdata;
    wire [31:0] d2d_ahb_m_hrdata;   // u_d2d_decode -> SoC (muxed read data)
    wire        d2d_ahb_m_hready;   // u_d2d_decode -> SoC AND broadcast slave HREADY
    wire        d2d_ahb_m_hresp;    // u_d2d_decode -> SoC (muxed response)

    // Per-slave selects from the decoder.
    wire        hsel_tx, hsel_fifo, hsel_ptp, hsel_tlapb, hsel_tcapb, hsel_peer;

    // Per-slave data-phase responses back into the decoder.
    wire [31:0] hrdata_tx,    hrdata_fifo,    hrdata_ptp,    hrdata_tlapb,    hrdata_tcapb,    hrdata_peer;
    wire        hreadyout_tx, hreadyout_fifo, hreadyout_ptp, hreadyout_tlapb, hreadyout_tcapb, hreadyout_peer;
    wire        hresp_tx,     hresp_fifo,     hresp_ptp,     hresp_tlapb,     hresp_tcapb,     hresp_peer;

    // --- D2D inbound: TideLink ahb_mng -> SoC d2d_ahb_s ---
    wire [31:0] d2d_ahb_s_haddr;
    wire  [2:0] d2d_ahb_s_hburst;
    wire  [6:0] d2d_ahb_s_hprot;    // TideLink is AHB5 [6:0]; SoC takes [3:0]
    wire  [2:0] d2d_ahb_s_hsize;
    wire  [1:0] d2d_ahb_s_htrans;
    wire [31:0] d2d_ahb_s_hwdata;
    wire        d2d_ahb_s_hwrite;
    wire        d2d_ahb_s_hready;   // SoC -> TideLink (slave ready back to manager)
    wire [31:0] d2d_ahb_s_hrdata;   // SoC -> TideLink
    wire        d2d_ahb_s_hresp;    // SoC -> TideLink

    // --- Cross-die PHC servo source 0 ---
    wire [47:0] d2d_phc_seconds;
    wire [29:0] d2d_phc_nanoseconds;
    wire [47:0] d2d_phc_hw_cap_seconds;
    wire [29:0] d2d_phc_hw_cap_nanoseconds;
    wire [31:0] d2d_phc_hw_cap_sub_nanoseconds;
    wire        d2d_phc_hw_capture;
    wire        d2d_phc_hw_set_time;
    wire [47:0] d2d_phc_hw_set_seconds;
    wire [29:0] d2d_phc_hw_set_nanoseconds;
    wire        d2d_phc_hw_adj_valid;
    wire [31:0] d2d_phc_hw_adj_ns_incr_frac;

    // --- Interrupts ---
    wire [15:0] d2d_irq;
    // TideLink interrupt sources.
    wire        tl_released_credits_irq, tl_doorbell_irq, tl_packet_committed_irq;
    wire        tl_ptp_irq, tl_perf_irq, tl_wlink_irq;
    wire        tl_nego_error_irq, tl_train_fail_irq;
    wire        tl_i2c_nbsy_irq, tl_i2c_nrd_empty_irq;
    // TideChart interrupt source.
    wire        tc_tidechart_irq;

    // --- TideLink APB config bridge (0x2E03xxxx, 15-bit window) ---
    wire [14:0] tlapb_paddr;
    wire        tlapb_penable, tlapb_pwrite, tlapb_psel, tlapb_pready, tlapb_pslverr;
    wire  [3:0] tlapb_pstrb;
    wire  [2:0] tlapb_pprot;
    wire [31:0] tlapb_pwdata, tlapb_prdata;

    // --- TideChart APB config bridge (0x2E04xxxx, 12-bit window) ---
    wire [11:0] tcapb_paddr;
    wire        tcapb_penable, tcapb_pwrite, tcapb_psel, tcapb_pready, tcapb_pslverr;
    wire [31:0] tcapb_pwdata, tcapb_prdata;

    // --- TideChart AXI-Stream seam (single port; FC_DATA_W = 48) ---
    // Direction naming per TideLink: tc_axis_tx_* is TideChart -> TideLink,
    // tc_axis_rx_* is TideLink -> TideChart.
    wire        tc_tx_tvalid;   // TC -> TL
    wire [47:0] tc_tx_tdata;
    wire        tc_tx_tready;
    wire        tc_rx_tvalid;   // TL -> TC
    wire [47:0] tc_rx_tdata;
    wire        tc_rx_tready;
    // Congestion sideband.
    wire  [4:0] tc_local_link_state;   // TideLink quantised {starve,trend,level}
    wire        tc_link_state_change;
    wire        tc_bcast_ack;
    wire        tc_link_active;

    //=========================================================================
    // Link status to the boundary.
    //
    // `tc_link_active` is not merely observability: it also closes the TX
    // aperture in u_d2d_decode, so a link-down write to 0x2E000000 takes a bus
    // fault instead of wedging the SoC's matrix. Exporting it lets a bring-up
    // script see the same bit the hardware gate is using.
    //=========================================================================
    assign link_active_o   = tc_link_active;
    assign tidechart_irq_o = tc_tidechart_irq;

    //=========================================================================
    // The multicore SoC. Default parameters (SYS_ADDR_W=SYS_DATA_W=32, the
    // deployed memory map). Every non-d2d port maps straight to this boundary;
    // the d2d_* ports drive the link below.
    //=========================================================================
    nanosoc_multicore_soc u_soc (
        // System clock / reset
        .sys_fclk                       (sys_fclk),
        .sys_sysresetn                  (sys_sysresetn),
        .sys_poresetn                   (sys_poresetn),
        .sys_hclk                       (sys_hclk),
        .sys_hresetn                    (sys_hresetn),
        .sys_scanenable                 (sys_scanenable),
        .sys_testmode                   (sys_testmode),
        .sys_sysresetreq                (sys_sysresetreq),
        // External ethernet-subsystem AHB slave
        .eth_ss_0_haddr                 (eth_ss_0_haddr),
        .eth_ss_0_htrans                (eth_ss_0_htrans),
        .eth_ss_0_hwrite                (eth_ss_0_hwrite),
        .eth_ss_0_hsize                 (eth_ss_0_hsize),
        .eth_ss_0_hburst                (eth_ss_0_hburst),
        .eth_ss_0_hprot                 (eth_ss_0_hprot),
        .eth_ss_0_hwdata                (eth_ss_0_hwdata),
        .eth_ss_0_hmastlock             (eth_ss_0_hmastlock),
        .eth_ss_0_hrdata                (eth_ss_0_hrdata),
        .eth_ss_0_hready                (eth_ss_0_hready),
        .eth_ss_0_hresp                 (eth_ss_0_hresp),
        // D2D outbound manager (link window 0x2E/0x2F)
        .d2d_ahb_m_haddr                (d2d_ahb_m_haddr),
        .d2d_ahb_m_htrans               (d2d_ahb_m_htrans),
        .d2d_ahb_m_hwrite               (d2d_ahb_m_hwrite),
        .d2d_ahb_m_hsize                (d2d_ahb_m_hsize),
        .d2d_ahb_m_hburst               (d2d_ahb_m_hburst),
        .d2d_ahb_m_hprot                (d2d_ahb_m_hprot),
        .d2d_ahb_m_hwdata               (d2d_ahb_m_hwdata),
        .d2d_ahb_m_hmastlock            (),   // reduced slaves carry no hmastlock — unused
        .d2d_ahb_m_hrdata               (d2d_ahb_m_hrdata),
        .d2d_ahb_m_hready               (d2d_ahb_m_hready),
        .d2d_ahb_m_hresp                (d2d_ahb_m_hresp),
        // D2D inbound subordinate (remote die -> shared SRAM + mailbox)
        .d2d_ahb_s_haddr                (d2d_ahb_s_haddr),
        .d2d_ahb_s_htrans               (d2d_ahb_s_htrans),
        .d2d_ahb_s_hwrite               (d2d_ahb_s_hwrite),
        .d2d_ahb_s_hsize                (d2d_ahb_s_hsize),
        .d2d_ahb_s_hburst               (d2d_ahb_s_hburst),
        .d2d_ahb_s_hprot                (d2d_ahb_s_hprot[3:0]),  // AHB5 [6:0] -> AHB-Lite [3:0]
        .d2d_ahb_s_hwdata               (d2d_ahb_s_hwdata),
        .d2d_ahb_s_hmastlock            (1'b0),                  // ahb_mng has no hmastlock
        .d2d_ahb_s_hrdata               (d2d_ahb_s_hrdata),
        .d2d_ahb_s_hready               (d2d_ahb_s_hready),
        .d2d_ahb_s_hresp                (d2d_ahb_s_hresp),
        // D2D interrupts (assembled below)
        .d2d_irq                        (d2d_irq),
        // Cross-die PHC servo source 0
        .d2d_phc_seconds                (d2d_phc_seconds),
        .d2d_phc_nanoseconds            (d2d_phc_nanoseconds),
        .d2d_phc_hw_cap_seconds         (d2d_phc_hw_cap_seconds),
        .d2d_phc_hw_cap_nanoseconds     (d2d_phc_hw_cap_nanoseconds),
        .d2d_phc_hw_cap_sub_nanoseconds (d2d_phc_hw_cap_sub_nanoseconds),
        .d2d_phc_hw_capture             (d2d_phc_hw_capture),
        .d2d_phc_hw_set_time            (d2d_phc_hw_set_time),
        .d2d_phc_hw_set_seconds         (d2d_phc_hw_set_seconds),
        .d2d_phc_hw_set_nanoseconds     (d2d_phc_hw_set_nanoseconds),
        .d2d_phc_hw_adj_valid           (d2d_phc_hw_adj_valid),
        .d2d_phc_hw_adj_ns_incr_frac    (d2d_phc_hw_adj_ns_incr_frac),
        // CPU sideband
        .network_core_pmuenable         (network_core_pmuenable),
        .chip_core_pmuenable            (chip_core_pmuenable),
        .network_core_nmi               (network_core_nmi),
        .network_core_txev              (network_core_txev),
        .network_core_rxev              (network_core_rxev),
        .network_core_lockup            (network_core_lockup),
        .network_core_sysresetreq       (network_core_sysresetreq),
        .network_core_sleeping          (network_core_sleeping),
        .network_core_sleepdeep         (network_core_sleepdeep),
        .chip_core_nmi                  (chip_core_nmi),
        .chip_core_txev                 (chip_core_txev),
        .chip_core_rxev                 (chip_core_rxev),
        .chip_core_lockup               (chip_core_lockup),
        .chip_core_sysresetreq          (chip_core_sysresetreq),
        .chip_core_sleeping             (chip_core_sleeping),
        .chip_core_sleepdeep            (chip_core_sleepdeep),
        // Debug access port
        .dap_swclktck                   (dap_swclktck),
        .dap_swditms                    (dap_swditms),
        .dap_swdo                       (dap_swdo),
        .dap_swdoen                     (dap_swdoen),
        .dap_tdi                        (dap_tdi),
        .dap_tdo                        (dap_tdo),
        .dap_ntdoen                     (dap_ntdoen),
        .dap_ntrst                      (dap_ntrst),
        .dap_npotrst                    (dap_npotrst),
        .dap_swj_enable                 (dap_swj_enable),
        // RMII PHY
        .rmii_ref_clk                   (rmii_ref_clk),
        .rmii_txd                       (rmii_txd),
        .rmii_tx_en                     (rmii_tx_en),
        .rmii_rxd                       (rmii_rxd),
        .rmii_crs_dv                    (rmii_crs_dv),
        // MDIO
        .md_pad_i                       (md_pad_i),
        .mdc_pad_o                      (mdc_pad_o),
        .md_pad_o                       (md_pad_o),
        .md_padoe_o                     (md_padoe_o),
        // UARTs / CPU1 watchdog
        .uart_rxd                       (uart_rxd),
        .uart_txd                       (uart_txd),
        .chip_core_uart_rxd             (chip_core_uart_rxd),
        .chip_core_uart_txd             (chip_core_uart_txd),
        .chip_core_wdog_reset           (chip_core_wdog_reset),
        // RTC / PTP time
        .rtc_clk                        (rtc_clk),
        .rtc_time_ptp_ns                (rtc_time_ptp_ns),
        .rtc_time_ptp_sec               (rtc_time_ptp_sec),
        .rtc_time_one_pps               (rtc_time_one_pps),
        // Ethernet / PHC interrupts + status
        .eth_irq                        (eth_irq),
        .phc_pps_out                    (phc_pps_out),
        .phc_pps_irq                    (phc_pps_irq),
        .phc_alarm_irq                  (phc_alarm_irq),
        .ha1588_servo_locked            (ha1588_servo_locked),
        // QSPI flash
        .qspi_sclk                      (qspi_sclk),
        .qspi_csn                       (qspi_csn),
        .qspi_io_o                      (qspi_io_o),
        .qspi_io_i                      (qspi_io_i),
        .qspi_io_e                      (qspi_io_e),
        // PL022 SPI
        .spi_sclk                       (spi_sclk),
        .spi_mosi                       (spi_mosi),
        .spi_miso                       (spi_miso),
        .spi_ss                         (spi_ss),
        // HOSTIO4
        .hostio4_p1_in                  (hostio4_p1_in),
        .hostio4_p1_out                 (hostio4_p1_out),
        .hostio4_p1_outen               (hostio4_p1_outen)
    );

    //=========================================================================
    // D2D window sub-decoder. Owns the six HSELs and the data-phase response
    // mux; address/control fan out directly (below) from d2d_ahb_m_*.
    //=========================================================================
    chiplet_d2d_decode u_d2d_decode (
        .hclk           (sys_hclk),
        .hresetn        (sys_hresetn),
        .haddr          (d2d_ahb_m_haddr),
        .htrans         (d2d_ahb_m_htrans),
        .link_active_i      (tc_link_active),   // TX aperture closed while the link is down
        .hrdata         (d2d_ahb_m_hrdata),
        .hready         (d2d_ahb_m_hready),
        .hresp          (d2d_ahb_m_hresp),
        .hsel_tx        (hsel_tx),
        .hsel_fifo      (hsel_fifo),
        .hsel_ptp       (hsel_ptp),
        .hsel_tlapb     (hsel_tlapb),
        .hsel_tcapb     (hsel_tcapb),
        .hsel_peer      (hsel_peer),
        .hrdata_tx      (hrdata_tx),      .hreadyout_tx    (hreadyout_tx),    .hresp_tx    (hresp_tx),
        .hrdata_fifo    (hrdata_fifo),    .hreadyout_fifo  (hreadyout_fifo),  .hresp_fifo  (hresp_fifo),
        .hrdata_ptp     (hrdata_ptp),     .hreadyout_ptp   (hreadyout_ptp),   .hresp_ptp   (hresp_ptp),
        .hrdata_tlapb   (hrdata_tlapb),   .hreadyout_tlapb (hreadyout_tlapb), .hresp_tlapb (hresp_tlapb),
        .hrdata_tcapb   (hrdata_tcapb),   .hreadyout_tcapb (hreadyout_tcapb), .hresp_tcapb (hresp_tcapb),
        .hrdata_peer    (hrdata_peer),    .hreadyout_peer  (hreadyout_peer),  .hresp_peer  (hresp_peer)
    );

    //=========================================================================
    // AHB->APB bridge: TideLink config window (0x2E03xxxx). The top apb_paddr
    // is a 15-bit unified window (Wlink + FIFO/PTP + addr-translator regs), so
    // ADDRWIDTH=15. PCLKEN=1 runs the APB at HCLK. Slaves see the broadcast
    // HREADY (u_d2d_decode.hready); its response feeds back as *_tlapb.
    //=========================================================================
    cmsdk_ahb_to_apb #(.ADDRWIDTH(15)) u_tlapb_bridge (
        .HCLK       (sys_hclk),
        .HRESETn    (sys_hresetn),
        .PCLKEN     (1'b1),
        .HSEL       (hsel_tlapb),
        .HADDR      (d2d_ahb_m_haddr[14:0]),
        .HTRANS     (d2d_ahb_m_htrans),
        .HSIZE      (d2d_ahb_m_hsize),
        .HPROT      (d2d_ahb_m_hprot),
        .HWRITE     (d2d_ahb_m_hwrite),
        .HREADY     (d2d_ahb_m_hready),
        .HWDATA     (d2d_ahb_m_hwdata),
        .HREADYOUT  (hreadyout_tlapb),
        .HRDATA     (hrdata_tlapb),
        .HRESP      (hresp_tlapb),
        .PADDR      (tlapb_paddr),
        .PENABLE    (tlapb_penable),
        .PWRITE     (tlapb_pwrite),
        .PSTRB      (tlapb_pstrb),
        .PPROT      (tlapb_pprot),
        .PWDATA     (tlapb_pwdata),
        .PSEL       (tlapb_psel),
        .APBACTIVE  (),               // clock-gating hint — unused
        .PRDATA     (tlapb_prdata),
        .PREADY     (tlapb_pready),
        .PSLVERR    (tlapb_pslverr)
    );

    //=========================================================================
    // AHB->APB bridge: TideChart config window (0x2E04xxxx). TideChart's APB
    // register offset is narrow; ADDRWIDTH=12 covers the block. TideChart's APB
    // carries NO PSTRB/PPROT, so those bridge outputs are left open.
    //=========================================================================
    cmsdk_ahb_to_apb #(.ADDRWIDTH(12)) u_tcapb_bridge (
        .HCLK       (sys_hclk),
        .HRESETn    (sys_hresetn),
        .PCLKEN     (1'b1),
        .HSEL       (hsel_tcapb),
        .HADDR      (d2d_ahb_m_haddr[11:0]),
        .HTRANS     (d2d_ahb_m_htrans),
        .HSIZE      (d2d_ahb_m_hsize),
        .HPROT      (d2d_ahb_m_hprot),
        .HWRITE     (d2d_ahb_m_hwrite),
        .HREADY     (d2d_ahb_m_hready),
        .HWDATA     (d2d_ahb_m_hwdata),
        .HREADYOUT  (hreadyout_tcapb),
        .HRDATA     (hrdata_tcapb),
        .HRESP      (hresp_tcapb),
        .PADDR      (tcapb_paddr),
        .PENABLE    (tcapb_penable),
        .PWRITE     (tcapb_pwrite),
        .PSTRB      (),               // TideChart APB has no PSTRB
        .PPROT      (),               // TideChart APB has no PPROT
        .PWDATA     (tcapb_pwdata),
        .PSEL       (tcapb_psel),
        .APBACTIVE  (),               // clock-gating hint — unused
        .PRDATA     (tcapb_prdata),
        .PREADY     (tcapb_pready),
        .PSLVERR    (tcapb_pslverr)
    );

    //=========================================================================
    // TideLink drop-in chiplet interconnect. Defaults keep RAM_ADDR_W=14
    // (tx/fifo apertures are 16 KB -> haddr[13:0]). NUM_PHY_LANES passes to the
    // GPIO PHY pads.
    //=========================================================================
    tidelink_top #(.NUM_PHY_LANES(NUM_PHY_LANES)) u_tidelink (
        // Clocks / resets — all from the SoC clock/reset controller output.
        .hclk       (sys_hclk),
        .hresetn    (sys_hresetn),
        .poresetn   (sys_poresetn),
        .phc_clk    (sys_hclk),       // PHC shares the AHB clock in this build
        .phc_resetn (sys_hresetn),
        // ahb_sub — peer aperture (0x2F, address-translated). Full 32-bit haddr;
        // carries hburst/hprot; no hmastlock (reduced shape).
        .ahb_sub_hsel       (hsel_peer),
        .ahb_sub_haddr      (d2d_ahb_m_haddr),
        .ahb_sub_hburst     (d2d_ahb_m_hburst),
        .ahb_sub_hprot      (d2d_ahb_m_hprot),
        .ahb_sub_hsize      (d2d_ahb_m_hsize),
        .ahb_sub_htrans     (d2d_ahb_m_htrans),
        .ahb_sub_hwdata     (d2d_ahb_m_hwdata),
        .ahb_sub_hwrite     (d2d_ahb_m_hwrite),
        .ahb_sub_hready     (d2d_ahb_m_hready),
        .ahb_sub_hrdata     (hrdata_peer),
        .ahb_sub_hresp      (hresp_peer),
        .ahb_sub_hreadyout  (hreadyout_peer),
        // ahb_tx — TX aperture (0x2E00). RAM_ADDR_W haddr[13:0]; no hburst/hprot.
        .ahb_tx_hsel        (hsel_tx),
        .ahb_tx_haddr       (d2d_ahb_m_haddr[13:0]),
        .ahb_tx_htrans      (d2d_ahb_m_htrans),
        .ahb_tx_hsize       (d2d_ahb_m_hsize),
        .ahb_tx_hwrite      (d2d_ahb_m_hwrite),
        .ahb_tx_hwdata      (d2d_ahb_m_hwdata),
        .ahb_tx_hready      (d2d_ahb_m_hready),
        .ahb_tx_hrdata      (hrdata_tx),
        .ahb_tx_hresp       (hresp_tx),
        .ahb_tx_hreadyout   (hreadyout_tx),
        // ahb_fifo — local RX FIFO read window (0x2E01). Same reduced shape.
        .ahb_fifo_hsel      (hsel_fifo),
        .ahb_fifo_haddr     (d2d_ahb_m_haddr[13:0]),
        .ahb_fifo_htrans    (d2d_ahb_m_htrans),
        .ahb_fifo_hsize     (d2d_ahb_m_hsize),
        .ahb_fifo_hwrite    (d2d_ahb_m_hwrite),
        .ahb_fifo_hwdata    (d2d_ahb_m_hwdata),
        .ahb_fifo_hready    (d2d_ahb_m_hready),
        .ahb_fifo_hrdata    (hrdata_fifo),
        .ahb_fifo_hresp     (hresp_fifo),
        .ahb_fifo_hreadyout (hreadyout_fifo),
        // ahb_mng — incoming manager from the peer (drives SoC d2d_ahb_s).
        .ahb_mng_haddr      (d2d_ahb_s_haddr),
        .ahb_mng_hburst     (d2d_ahb_s_hburst),
        .ahb_mng_hprot      (d2d_ahb_s_hprot),
        .ahb_mng_hsize      (d2d_ahb_s_hsize),
        .ahb_mng_htrans     (d2d_ahb_s_htrans),
        .ahb_mng_hwdata     (d2d_ahb_s_hwdata),
        .ahb_mng_hwrite     (d2d_ahb_s_hwrite),
        .ahb_mng_hready     (d2d_ahb_s_hready),
        .ahb_mng_hrdata     (d2d_ahb_s_hrdata),
        .ahb_mng_hresp      (d2d_ahb_s_hresp),
        // apb — unified 15-bit config port from u_tlapb_bridge.
        .apb_paddr          (tlapb_paddr),
        .apb_penable        (tlapb_penable),
        .apb_pwrite         (tlapb_pwrite),
        .apb_pstrb          (tlapb_pstrb),
        .apb_pprot          (tlapb_pprot),
        .apb_pwdata         (tlapb_pwdata),
        .apb_psel           (tlapb_psel),
        .apb_prdata         (tlapb_prdata),
        .apb_pready         (tlapb_pready),
        .apb_pslverr        (tlapb_pslverr),
        // Scan / DFT — no scan in this integration; tie inactive, capture open.
        .scan_mode          (scan_mode),
        .scan_asyncrst_ctrl (scan_asyncrst_ctrl),
        .scan_clk           (scan_clk),
        .scan_shift         (scan_shift),
        .scan_in            (scan_in),
        .scan_out           (scan_out),
        // Wlink PLL reference clock (chiplet boundary).
        .user_ref_clk       (user_ref_clk),
        // GPIO PHY pads (chiplet boundary).
        .pad_clk_tx         (pad_clk_tx),
        .pad_tx             (pad_tx),
        .pad_clk_rx         (pad_clk_rx),
        .pad_rx             (pad_rx),
        .idelay_ref_clk     (idelay_ref_clk),
        // ahb_ptp — PTP TX write port (0x2E02). 4-bit register window.
        .ahb_ptp_hsel       (hsel_ptp),
        .ahb_ptp_haddr      (d2d_ahb_m_haddr[3:0]),
        .ahb_ptp_htrans     (d2d_ahb_m_htrans),
        .ahb_ptp_hsize      (d2d_ahb_m_hsize),
        .ahb_ptp_hwrite     (d2d_ahb_m_hwrite),
        .ahb_ptp_hwdata     (d2d_ahb_m_hwdata),
        .ahb_ptp_hready     (d2d_ahb_m_hready),
        .ahb_ptp_hrdata     (hrdata_ptp),
        .ahb_ptp_hresp      (hresp_ptp),
        .ahb_ptp_hreadyout  (hreadyout_ptp),
        // Cross-die PHC servo source 0.
        .phc_hw_capture             (d2d_phc_hw_capture),
        .phc_nanoseconds            (d2d_phc_nanoseconds),
        .phc_seconds                (d2d_phc_seconds),
        .phc_pps                    (phc_pps_out),   // SoC phc_pps_out drives the servo
        .phc_hw_cap_seconds         (d2d_phc_hw_cap_seconds),
        .phc_hw_cap_nanoseconds     (d2d_phc_hw_cap_nanoseconds),
        .phc_hw_cap_sub_nanoseconds (d2d_phc_hw_cap_sub_nanoseconds),
        .phc_hw_set_time            (d2d_phc_hw_set_time),
        .phc_hw_set_seconds         (d2d_phc_hw_set_seconds),
        .phc_hw_set_nanoseconds     (d2d_phc_hw_set_nanoseconds),
        .phc_hw_adj_valid           (d2d_phc_hw_adj_valid),
        .phc_hw_adj_ns_incr_frac    (d2d_phc_hw_adj_ns_incr_frac),
        .phc_locked_i               (1'b1),   // single-link deployment: PHC lock always granted
        // Servo status — SoC's PHC servo_locked input is owned by the ethernet
        // HA1588 servo (D2D_PORT.md §6f), so this TideLink status is left open.
        .servo_locked               (servo_locked_o),
        // Interrupt outputs.
        .released_credits_irq (tl_released_credits_irq),
        .doorbell_irq         (tl_doorbell_irq),
        .packet_committed_irq (tl_packet_committed_irq),
        .ptp_irq              (tl_ptp_irq),
        .perf_irq             (tl_perf_irq),
        .wlink_irq            (tl_wlink_irq),
        // TideChart AXI-Stream seam.
        .tc_axis_tx_tvalid    (tc_tx_tvalid),
        .tc_axis_tx_tdata     (tc_tx_tdata),
        .tc_axis_tx_tready    (tc_tx_tready),
        .tc_axis_rx_tvalid    (tc_rx_tvalid),
        .tc_axis_rx_tdata     (tc_rx_tdata),
        .tc_axis_rx_tready    (tc_rx_tready),
        // QoS priority hint — TideChart TC_QOS_CFG not wired in v1; fixed priority.
        .tc_qos_priority      (3'b000),
        // Congestion sideband to TideChart.
        .tl_local_link_state_o  (tc_local_link_state),
        .tl_link_state_change_o (tc_link_state_change),
        .tl_ewma_credit_o       (tl_ewma_credit_o),
        .tl_bcast_ack_i         (tc_bcast_ack),
        // Link status.
        .link_active            (tc_link_active),
        // Reset output — no consumer at this integration level.
        .d2d_reset_o            (d2d_reset_o),
        // Role selection (strap in; resolved role/lock outputs unused in v1).
        .role_strap_i           (role_strap_i),
        .role_is_master_o       (role_is_master_o),
        .role_locked_o          (role_locked_o),
        .apb_debug_unlock_i     (apb_debug_unlock_i),
        .mask_hs_bypass_i       (mask_hs_bypass_i),
        // Auto-negotiation.
        .nego_priority_i        (nego_priority_i),
        .puf_seed               (puf_seed),
        .puf_ready              (puf_ready),
        .nego_error_irq         (tl_nego_error_irq),
        .train_fail_irq         (tl_train_fail_irq),
        // I2C sideband pads (chiplet boundary).
        .i2c_scl_i              (i2c_scl_i),
        .i2c_scl_o              (i2c_scl_o),
        .i2c_scl_t              (i2c_scl_t),
        .i2c_sda_i              (i2c_sda_i),
        .i2c_sda_o              (i2c_sda_o),
        .i2c_sda_t              (i2c_sda_t),
        // I2C sideband AXI slave — no CPU-driven I2C master path in v1; drive all
        // inputs inactive (no transactions), leave all responses open.
        .s_i2c_axi_awvalid  (1'b0),
        .s_i2c_axi_awid     (2'b00),
        .s_i2c_axi_awaddr   (4'h0),
        .s_i2c_axi_awlen    (8'h00),
        .s_i2c_axi_awsize   (3'b000),
        .s_i2c_axi_awburst  (2'b00),
        .s_i2c_axi_awlock   (1'b0),
        .s_i2c_axi_awcache  (4'h0),
        .s_i2c_axi_awprot   (3'b000),
        .s_i2c_axi_awready  (),
        .s_i2c_axi_wvalid   (1'b0),
        .s_i2c_axi_wdata    (32'h0),
        .s_i2c_axi_wstrb    (4'h0),
        .s_i2c_axi_wlast    (1'b0),
        .s_i2c_axi_wready   (),
        .s_i2c_axi_bvalid   (),
        .s_i2c_axi_bid      (),
        .s_i2c_axi_bresp    (),
        .s_i2c_axi_bready   (1'b0),
        .s_i2c_axi_arvalid  (1'b0),
        .s_i2c_axi_arid     (2'b00),
        .s_i2c_axi_araddr   (4'h0),
        .s_i2c_axi_arlen    (8'h00),
        .s_i2c_axi_arsize   (3'b000),
        .s_i2c_axi_arburst  (2'b00),
        .s_i2c_axi_arlock   (1'b0),
        .s_i2c_axi_arcache  (4'h0),
        .s_i2c_axi_arprot   (3'b000),
        .s_i2c_axi_arready  (),
        .s_i2c_axi_rvalid   (),
        .s_i2c_axi_rid      (),
        .s_i2c_axi_rdata    (),
        .s_i2c_axi_rresp    (),
        .s_i2c_axi_rlast    (),
        .s_i2c_axi_rready   (1'b0),
        // I2C interrupts.
        .i2c_nbsy_irq       (tl_i2c_nbsy_irq),
        .i2c_nrd_empty_irq  (tl_i2c_nrd_empty_irq)
    );

    //=========================================================================
    // TideChart controller (via the flattening shim). Single link port
    // (NUM_PORTS=1) facing this one TideLink; FC_DATA_W=48 matches the seam.
    //=========================================================================
    tidechart_shim #(
        .NUM_PORTS (1),
        .FC_DATA_W (48)
    ) u_tidechart (
        .clk    (sys_hclk),
        .resetn (sys_hresetn),
        // AXI-Stream seam. rx = TideLink -> TideChart, tx = TideChart -> TideLink.
        .tc_axis_rx_tvalid          (tc_rx_tvalid),
        .tc_axis_rx_tdata_flat      (tc_rx_tdata),
        .tc_axis_rx_tready          (tc_rx_tready),
        .tc_axis_tx_tvalid          (tc_tx_tvalid),
        .tc_axis_tx_tdata_flat      (tc_tx_tdata),
        .tc_axis_tx_tready          (tc_tx_tready),
        .link_active                (tc_link_active),
        // Congestion sideband.
        .local_link_state_i_flat    (tc_local_link_state),
        .local_link_state_change_i  (tc_link_state_change),
        .local_bcast_ack_o          (tc_bcast_ack),
        // APB from u_tcapb_bridge (12-bit bridge PADDR sliced to APB_ADDR_W=8).
        .apb_paddr                  (tcapb_paddr[7:0]),
        .apb_psel                   (tcapb_psel),
        .apb_penable                (tcapb_penable),
        .apb_pwrite                 (tcapb_pwrite),
        .apb_pwdata                 (tcapb_pwdata),
        .apb_prdata                 (tcapb_prdata),
        .apb_pready                 (tcapb_pready),
        .apb_pslverr                (tcapb_pslverr),
        // Interrupt.
        .tidechart_irq              (tc_tidechart_irq),
        // Phase-P4 IRQC AXI-Stream pair — the ahb-chiplet-irqc block is NOT
        // present in this integration, so both streams are held idle: TC->IRQC
        // has no consumer (tready low), IRQC->TC has no producer (tvalid low).
        .tc_to_irqc_tvalid_o        (),
        .tc_to_irqc_tdata_o         (),
        .tc_to_irqc_tready_i        (1'b0),
        .tc_to_irqc_tlast_o         (),
        .irqc_to_tc_tvalid_i        (1'b0),
        .irqc_to_tc_tdata_i         (32'h0),
        .irqc_to_tc_tready_o        ()
    );

    //=========================================================================
    // D2D interrupt vector. [7:0] -> CPU0 NVIC (data plane), [15:8] -> CPU1 NVIC
    // (link management). Fixed assignment per the wrapper contract.
    //=========================================================================
    assign d2d_irq = {
        1'b0,                     // [15] reserved
        tc_tidechart_irq,         // [14] TideChart
        tl_i2c_nrd_empty_irq,     // [13]
        tl_i2c_nbsy_irq,          // [12]
        tl_perf_irq,              // [11]
        tl_train_fail_irq,        // [10]
        tl_nego_error_irq,        // [9]
        tl_wlink_irq,             // [8]
        4'b0000,                  // [7:4] reserved
        tl_ptp_irq,               // [3]
        tl_packet_committed_irq,  // [2]
        tl_released_credits_irq,  // [1]
        tl_doorbell_irq           // [0]
    };

endmodule
