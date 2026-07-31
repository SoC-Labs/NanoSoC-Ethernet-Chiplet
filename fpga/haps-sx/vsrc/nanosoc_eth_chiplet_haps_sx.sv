//-----------------------------------------------------------------------------
// nanosoc_eth_chiplet_haps_sx — HAPS-SX VU19P board top
// A joint work commissioned on behalf of SoC Labs, under Arm Academic Access
// license.
//
// Contributors
//
// David Mapstone (d.a.mapstone@soton.ac.uk)
//
// Copyright 2026, SoC Labs (www.soclabs.org)
//-----------------------------------------------------------------------------
// Board top for the single-die eth-chiplet on a Synopsys HAPS-SX VU19P 1F
// (XCVU19P-FSVA3824). Synthesised by ProtoSynthesis (protocompiler_s); Vivado
// does placement, routing and the bitstream.
//
// WHY THIS IS NOT tidelink/fpga/vivado_ip/nanosoc_eth_chiplet_vivado_wrapper.v
//
// That wrapper is a Vivado IP-Integrator boundary: it carries X_INTERFACE_INFO
// attributes for IPI inference, exports the eth_ss_0 AHB slave as a PS
// backdoor, and hard-codes the KR260 "M1" posture (RMII idle, MAC in internal
// loopback, QSPI/SPI/hostio tied off). None of that applies here — HAPS-SX has
// no PS to be a backdoor, ProtoSynthesis needs no IPI metadata, and the whole
// point of this target is to bring the real RMII/UART/QSPI pads out. So this
// file instantiates nanosoc_eth_chiplet DIRECTLY and owns the board decisions
// itself. Neither submodule is forked or modified.
//
// BOARD I/O NOTE (1.8 V)
//
// Every user I/O bank on the HAPS-SX is supplied at 1.8 V, so every pad below
// is LVCMOS_18 (LVDS_18 for the differential clock) — see the .cob. Whether a
// 3.3 V peripheral can be plugged straight into a PMOD depends on whether the
// board carries on-board level translators between the FPGA and the connector;
// that is a BENCH question and does not change one line of this file or the
// constraints. See README.md §"I/O voltage".
//
// D2D PHY POSTURE
//
// Phase 1 is single-die with the GPIO-PHY looped back INTERNALLY (TX nets fed
// straight to the RX nets), mirroring tidelink/fpga/targets/pynq-z2-loopback.
// The link trains against itself, so TideLink and TideChart are exercised
// without a peer, a ribbon, or a second board. Set PHY_LOOPBACK = 0 to promote
// the pads to real pins for a two-die build (they then need a .cob assignment
// and, at 8 lanes + clock each way, an HT3 slot rather than a PMOD).
//-----------------------------------------------------------------------------

`timescale 1ns/1ps

module nanosoc_eth_chiplet_haps_sx #(
    // TideLink GPIO-PHY lane count — tracks the chiplet parameter.
    parameter NUM_PHY_LANES = 8,

    // 1 = loop the d2d PHY back inside the FPGA (phase 1, single die).
    // 0 = promote pad_* to real board pins (needs .cob entries).
    parameter PHY_LOOPBACK  = 1,

    // MMCM programming. GCLK0 arrives at 100 MHz by default (board PLL,
    // reconfigurable via ConfPro-SX). VCO = 100 / DIVCLK * MULT = 1200 MHz.
    //   sys_fclk    = 1200 / 48 = 25 MHz  <- matches the Pynq-proven firmware
    //   phy_ref_pre = 1200 / 48 = 25 MHz  -> /8 in fabric -> 3.125 MHz PHY clock
    //
    // Change SYS_CLK_DIV to 24.000 for a 50 MHz system clock once 25 MHz is
    // proven (rebuild firmware with a matching NANOSOC_SYS_CLK_FREQ_HZ).
    //
    // NO 200 MHz IDELAY reference is generated. tidelink_top's USE_IDELAY
    // parameter defaults to 1'b0, which makes tidelink_idelay_rx a pure
    // combinational passthrough — the clock would drive nothing. (It is also
    // 7-series IDELAYE2 only; this is UltraScale+, so it could not be enabled
    // here anyway.) idelay_ref_clk is tied off at the chiplet instance.
    parameter real GCLK0_PERIOD_NS = 10.000,
    parameter real CLKFB_MULT      = 12.000,
    parameter integer DIVCLK_DIV   = 1,
    parameter real SYS_CLK_DIV     = 48.000,
    parameter real PHY_REF_DIV     = 48.000
)(
    // -- Global clock: GCLK0 differential pair (LVDS_18, 100 MHz default) ----
    input  wire        gclk0_p,
    input  wire        gclk0_n,

    // -- Reset: push-button PB1, active low ---------------------------------
    input  wire        pb1_rst_n,

    // -- RMII ethernet PHY (LAN8720) ----------------------------------------
    input  wire        phy_rmii_ref_clk,   // 50 MHz sourced BY the PHY
    input  wire        phy_rmii_crs_dv,
    input  wire  [1:0] phy_rmii_rxd,
    output wire  [1:0] phy_rmii_txd,
    output wire        phy_rmii_tx_en,
    output wire        phy_mdc,
    inout  wire        phy_mdio,
    output wire        phy_mdio_dir,       // external translator direction (1 = FPGA drives)
    output wire        phy_nrst,

    // -- Debug UART (CPU0 / network core) -----------------------------------
    input  wire        uart_rxd,
    output wire        uart_txd,

    // -- Serial Wire Debug — SoC-400 SWJ-DP ---------------------------------
    input  wire        swd_clk,
    inout  wire        swd_dio,

    // -- QSPI flash: the board's on-board W25Q32FW (1.8 V, 4 MB) -------------
    output wire        qspi_sclk,
    output wire        qspi_ncs,
    inout  wire  [3:0] qspi_io,

    // -- HOSTIO4 7-pin host interface (PMOD3, 3.3 V) ------------------------
    //    [0] IOREQ1  [1] IOREQ2  [2] IOACK  [3..6] IODATA[0..3]
    inout  wire  [6:0] hostio4_p1,

    // -- Status LEDs (4 red + 4 green) --------------------------------------
    output wire  [7:0] led,

    // -- PHC 1 PPS scope probe point ----------------------------------------
    output wire        phc_pps_out
);

    //=========================================================================
    // Clock generation
    //
    // GCLK0 is an LVDS pair from the board's dedicated PLL. IBUFDS -> MMCM ->
    // BUFG per output. The RMII reference clock is a SEPARATE, asynchronous
    // domain sourced by the PHY; it gets its own BUFG and is declared
    // asynchronous to sys_fclk in the FDC.
    //=========================================================================
    wire gclk0_ibuf;
    wire mmcm_fb, mmcm_locked;
    wire sys_fclk_raw, phy_ref_pre_raw;
    wire sys_fclk, phy_ref_pre, user_ref_clk;

    IBUFDS u_gclk0_ibufds (
        .I  (gclk0_p),
        .IB (gclk0_n),
        .O  (gclk0_ibuf)
    );

    MMCME4_BASE #(
        .CLKIN1_PERIOD    (GCLK0_PERIOD_NS),
        .DIVCLK_DIVIDE    (DIVCLK_DIV),
        .CLKFBOUT_MULT_F  (CLKFB_MULT),
        .CLKOUT0_DIVIDE_F (SYS_CLK_DIV),
        .CLKOUT1_DIVIDE   (PHY_REF_DIV)
    ) u_mmcm (
        .CLKIN1   (gclk0_ibuf),
        .CLKFBIN  (mmcm_fb),
        .CLKFBOUT (mmcm_fb),
        .CLKOUT0  (sys_fclk_raw),
        .CLKOUT1  (phy_ref_pre_raw),
        .LOCKED   (mmcm_locked),
        .PWRDWN   (1'b0),
        .RST      (~pb1_rst_n)
    );

    BUFG u_bufg_sys  (.I (sys_fclk_raw),    .O (sys_fclk));
    BUFG u_bufg_phyp (.I (phy_ref_pre_raw), .O (phy_ref_pre));

    //=========================================================================
    // TideLink GPIO-PHY reference clock: 25 MHz / 8 = 3.125 MHz
    //
    // This divider is NOT optional and the rate is NOT arbitrary. The KR260
    // eth-chiplet target — the only configuration this PHY is proven in —
    // takes a 25 MHz clk_wiz output through exactly this /8 counter to give
    // user_ref_clk = 3.125 MHz. An earlier revision of this file fed the PHY
    // 100 MHz straight from the MMCM, i.e. 32x the proven rate, and place &
    // route could not close (WNS -4.45 ns, TNS -495 ns concentrated in the
    // link domain).
    //
    // tidelink_phy_clk_div2 is REUSED from the KR260 target rather than
    // reimplemented, for two reasons: it keeps one definition of the divider,
    // and the constraint patterns in our timing XDC
    // (*phy_clk_div*div_cnt_reg[2]/C and *phy_clk_div*u_div_bufg*/O) are
    // written against its internal names — a local copy with different names
    // would silently fail to match and leave the clock underived again.
    // The Makefile adds it to the source list via --extra.
    //=========================================================================
    tidelink_phy_clk_div2 u_phy_clk_div (
        .clk_in  (phy_ref_pre),
        .clk_out (user_ref_clk)
    );

    wire rmii_ref_clk;
    BUFG u_bufg_rmii (.I (phy_rmii_ref_clk), .O (rmii_ref_clk));

    //=========================================================================
    // Reset
    //
    // PB1 is a mechanical, active-low button; gate it with MMCM lock and
    // synchronise the RELEASE into sys_fclk. Assertion stays asynchronous so a
    // press works even if the clock has stopped.
    //=========================================================================
    wire async_rst_n = pb1_rst_n & mmcm_locked;

    reg [3:0] rst_sync;
    always @(posedge sys_fclk or negedge async_rst_n) begin
        if (!async_rst_n) rst_sync <= 4'b0000;
        else              rst_sync <= {rst_sync[2:0], 1'b1};
    end
    wire sys_sysresetn = rst_sync[3];

    //=========================================================================
    // Bidirectional pads
    //
    // Xilinx IOBUF convention: T = 1 -> Hi-Z. The chiplet exposes ACTIVE-HIGH
    // output enables (md_padoe_o, dap_swdoen, qspi_io_e), so each is inverted
    // into T.
    //=========================================================================
    wire md_pad_i, md_pad_o, md_padoe_o;
    IOBUF u_mdio_iobuf (
        .IO (phy_mdio),
        .I  (md_pad_o),
        .O  (md_pad_i),
        .T  (~md_padoe_o)
    );
    // Drives an external 1.8 V<->3.3 V translator's DIR pin when one is fitted.
    // Harmless (an unread output) when the PHY is wired directly.
    assign phy_mdio_dir = md_padoe_o;

    wire dap_swdo, dap_swdoen, dap_swditms;
    IOBUF u_swd_iobuf (
        .IO (swd_dio),
        .I  (dap_swdo),
        .O  (dap_swditms),
        .T  (~dap_swdoen)
    );

    wire [3:0] qspi_io_o, qspi_io_i, qspi_io_e;
    genvar gi;
    generate
        for (gi = 0; gi < 4; gi = gi + 1) begin : g_qspi_iobuf
            IOBUF u_iobuf (
                .IO (qspi_io[gi]),
                .I  (qspi_io_o[gi]),
                .O  (qspi_io_i[gi]),
                .T  (~qspi_io_e[gi])
            );
        end
    endgenerate

    //=========================================================================
    // RMII
    //
    // There is deliberately NO rmii_to_mii bridge here. In this generation of
    // the SoC the bridge lives INSIDE the ethernet subsystem
    // (build_soc/rtl/ethernet_ss_ahb_rmii.sv instantiates rmii_to_mii, and the
    // SoC flist already compiles amba_wb_bridges/src/rtl/rmii_to_mii.v). The
    // chiplet boundary is therefore RMII, not MII, and the PHY pads wire
    // straight through to it.
    //
    // The older Pynq-Z2 multicore flow DID instantiate rmii_to_mii in its board
    // wrapper. Do not copy that pattern here — it would put two bridges back to
    // back and leave the MII nets dangling.
    //=========================================================================

    // The LAN8720 breakout normally self-resets through an RC. Hold it released
    // and let the SoC reset tree settle first.
    assign phy_nrst = sys_sysresetn;

    //=========================================================================
    // HOSTIO4 — 7-pin host interface on PMOD3 (bank 83, 3.3 V, SLR0)
    //
    // nanosoc_ss_hostio4 is strapped FT1248MODE = 0 at the SoC level, i.e.
    // EXTIO mode, which maps the uniform P1[6:0] tristate bundle onto the
    // HOSTIO4 wire protocol:
    //
    //     P1[0]  IOREQ1     SoC -> host   (OUTEN tied 1 in the SoC)
    //     P1[1]  IOREQ2     SoC -> host   (OUTEN tied 1)
    //     P1[2]  IOACK      host -> SoC   (OUTEN tied 0; asynchronous)
    //     P1[3]  IODATA[0]  bidirectional
    //     P1[4]  IODATA[1]  bidirectional
    //     P1[5]  IODATA[2]  bidirectional
    //     P1[6]  IODATA[3]  bidirectional
    //
    // Four 8-bit AXI streams are multiplexed over that: channel 0 TX/RX is
    // conventionally stdout/stdin, channel 1 TX/RX a data stream.
    //
    // Every pin gets an IOBUF because the SoC drives a per-bit output enable
    // and four of the seven genuinely turn around. The SoC's OUTEN is
    // ACTIVE HIGH; Vivado's IOBUF T is active-high tristate, hence the invert.
    //
    // Host side: the validated driver is the RP2040/RP2350 PIO implementation
    // in nanosoc_arch_tech/rtl/hostio4/rpi-pico-pio. A Pico is 3.3 V, which
    // matches PMOD3 (bank 83, measured 3.3 V) — connect directly, no level
    // shifting, and share GND on PMOD pin 5/11.
    //=========================================================================
    wire [6:0] hostio4_p1_in;
    wire [6:0] hostio4_p1_out;
    wire [6:0] hostio4_p1_outen;

    genvar gh;
    generate
        for (gh = 0; gh < 7; gh = gh + 1) begin : g_hostio4_iobuf
            IOBUF u_iobuf (
                .IO (hostio4_p1[gh]),
                .I  (hostio4_p1_out[gh]),
                .O  (hostio4_p1_in[gh]),
                .T  (~hostio4_p1_outen[gh])
            );
        end
    endgenerate

    //=========================================================================
    // SYSRESETREQ self-loop
    //
    // Either core can request a system reset (SCB->AIRCR, or an SWD `reset`).
    // OR the two, synchronise, and hold off until a startup counter has
    // expired — without the guard the design can latch a reset request that is
    // still settling out of power-up and never leave reset.
    //=========================================================================
    wire network_core_sysresetreq, chip_core_sysresetreq;
    wire sysresetreq_any = network_core_sysresetreq | chip_core_sysresetreq;

    reg  [1:0] sysresetreq_sync;
    reg  [9:0] startup_cnt;
    reg        startup_done;

    always @(posedge sys_fclk or negedge sys_sysresetn) begin
        if (!sys_sysresetn) begin
            sysresetreq_sync <= 2'b00;
            startup_cnt      <= 10'd0;
            startup_done     <= 1'b0;
        end else begin
            sysresetreq_sync <= {sysresetreq_sync[0], sysresetreq_any};
            if (!startup_done) begin
                if (&startup_cnt) startup_done <= 1'b1;
                else              startup_cnt  <= startup_cnt + 1'b1;
            end
        end
    end

    wire sys_sysresetreq = sysresetreq_sync[1] & startup_done;

    //=========================================================================
    // D2D GPIO-PHY: internal loopback (PHY_LOOPBACK = 1)
    //=========================================================================
    wire                     pad_clk_tx;
    wire [NUM_PHY_LANES-1:0] pad_tx;
    wire                     pad_clk_rx;
    wire [NUM_PHY_LANES-1:0] pad_rx;

    generate
        if (PHY_LOOPBACK) begin : g_phy_loopback
            assign pad_clk_rx = pad_clk_tx;
            assign pad_rx     = pad_tx;
        end else begin : g_phy_pads
            // Promote to board pins here for a two-die build. Left
            // deliberately undriven so an unconfigured PHY_LOOPBACK=0 build
            // fails loudly at elaboration rather than training against noise.
        end
    endgenerate

    //=========================================================================
    // Status / observability
    //=========================================================================
    wire sys_hclk, sys_hresetn, sys_poresetn;
    wire network_core_lockup, chip_core_lockup;
    wire eth_irq, phc_pps_irq, phc_alarm_irq, ha1588_servo_locked;
    wire link_active_o, d2d_reset_o, role_is_master_o, role_locked_o;
    wire servo_locked_o, tidechart_irq_o;
    wire [12:0] tl_ewma_credit_o;
    wire chip_core_uart_txd, chip_core_wdog_reset;

    //=========================================================================
    // The chiplet
    //
    // CHIPLET_IS_NETLIST selects how the instance is parameterised:
    //   * undefined (the DEFAULT, direct-Vivado flow): u_chiplet is RTL, so
    //     pass NUM_PHY_LANES explicitly.
    //   * defined (the ProtoCompiler export-netlist flow, fpga/haps-sx-pc):
    //     u_chiplet is a POST-ELABORATION .vm netlist whose parameters are
    //     baked away — a named override would fail Synth 8-7136 "parameter
    //     does not exist", so instantiate with no override.
    // NUM_PHY_LANES defaults to 8 in both the board top and the chiplet, so the
    // two forms are functionally identical; the guard only satisfies Vivado's
    // parameter-existence check against the flattened netlist.
    //=========================================================================
`ifdef CHIPLET_IS_NETLIST
    nanosoc_eth_chiplet u_chiplet (
`else
    nanosoc_eth_chiplet #(
        .NUM_PHY_LANES (NUM_PHY_LANES)
    ) u_chiplet (
`endif
        // -- Clock / reset --
        .sys_fclk                 (sys_fclk),
        .sys_sysresetn            (sys_sysresetn),
        .sys_poresetn             (sys_poresetn),
        .sys_hclk                 (sys_hclk),
        .sys_hresetn              (sys_hresetn),
        .sys_scanenable           (1'b0),
        .sys_testmode             (1'b0),
        .sys_sysresetreq          (sys_sysresetreq),

        // -- External AHB slave (PS backdoor on KR260; unused here) --
        // Tied off EXPLICITLY. Leaving these floating would let synthesis
        // resolve htrans/hwrite to X and inject phantom transfers into the
        // ethernet subsystem's matrix port. Vivado happens to tie unconnected
        // inputs low; Synplify is not obliged to.
        .eth_ss_0_haddr           (32'h0000_0000),
        .eth_ss_0_htrans          (2'b00),          // IDLE
        .eth_ss_0_hwrite          (1'b0),
        .eth_ss_0_hsize           (3'b010),
        .eth_ss_0_hburst          (3'b000),
        .eth_ss_0_hprot           (4'b0011),
        .eth_ss_0_hwdata          (32'h0000_0000),
        .eth_ss_0_hmastlock       (1'b0),
        .eth_ss_0_hrdata          (),
        .eth_ss_0_hready          (),
        .eth_ss_0_hresp           (),

        // -- Core sideband --
        // PMUENABLE MUST be 1: it enables each core's cm0p_ik_pmu (PRMU), which
        // generates HCLK/HRESETn. Tied to 0, the cores never clock out of reset
        // (the heartbeat still runs, since it's on sys_fclk, so the board looks
        // alive while the CPUs are dead). 1'b1 matches the proven KR260 wrapper.
        .network_core_pmuenable   (1'b1),
        .chip_core_pmuenable      (1'b1),
        .network_core_nmi         (1'b0),
        .network_core_txev        (),
        .network_core_rxev        (1'b0),
        .network_core_lockup      (network_core_lockup),
        .network_core_sysresetreq (network_core_sysresetreq),
        .network_core_sleeping    (),
        .network_core_sleepdeep   (),
        .chip_core_nmi            (1'b0),
        .chip_core_txev           (),
        .chip_core_rxev           (1'b0),
        .chip_core_lockup         (chip_core_lockup),
        .chip_core_sysresetreq    (chip_core_sysresetreq),
        .chip_core_sleeping       (),
        .chip_core_sleepdeep      (),

        // -- SWJ-DP: pure SWD, JTAG tied off --
        .dap_swclktck             (swd_clk),
        .dap_swditms              (dap_swditms),
        .dap_swdo                 (dap_swdo),
        .dap_swdoen               (dap_swdoen),
        .dap_tdi                  (1'b0),
        .dap_tdo                  (),
        .dap_ntdoen               (),
        .dap_ntrst                (1'b1),
        .dap_npotrst              (sys_sysresetn),
        .dap_swj_enable           (1'b1),           // single chiplet on the SWD bus

        // -- RMII: straight to the PHY pads. The RMII<->MII bridge is INSIDE
        //    the ethernet subsystem, so this boundary is RMII.
        .rmii_ref_clk             (rmii_ref_clk),
        .rmii_txd                 (phy_rmii_txd),
        .rmii_tx_en               (phy_rmii_tx_en),
        .rmii_rxd                 (phy_rmii_rxd),
        .rmii_crs_dv              (phy_rmii_crs_dv),

        // -- MDIO --
        .md_pad_i                 (md_pad_i),
        .mdc_pad_o                (phy_mdc),
        .md_pad_o                 (md_pad_o),
        .md_padoe_o               (md_padoe_o),

        // -- UARTs / watchdog --
        .uart_rxd                 (uart_rxd),
        .uart_txd                 (uart_txd),
        .chip_core_uart_rxd       (1'b1),           // idle high
        .chip_core_uart_txd       (chip_core_uart_txd),
        .chip_core_wdog_reset     (chip_core_wdog_reset),

        // -- RTC / PTP --
        .rtc_clk                  (sys_fclk),
        .rtc_time_ptp_ns          (),
        .rtc_time_ptp_sec         (),
        .rtc_time_one_pps         (),

        // -- Interrupts / status --
        .eth_irq                  (eth_irq),
        .phc_pps_out              (phc_pps_out),
        .phc_pps_irq              (phc_pps_irq),
        .phc_alarm_irq            (phc_alarm_irq),
        .ha1588_servo_locked      (ha1588_servo_locked),

        // -- QSPI flash (on-board W25Q32FW) --
        .qspi_sclk                (qspi_sclk),
        .qspi_csn                 (qspi_ncs),
        .qspi_io_o                (qspi_io_o),
        .qspi_io_i                (qspi_io_i),
        .qspi_io_e                (qspi_io_e),

        // -- PL022 SPI (no board device yet) --
        .spi_sclk                 (),
        .spi_mosi                 (),
        .spi_miso                 (1'b0),
        .spi_ss                   (),

        // -- HOSTIO4 (PMOD3, via the IOBUFs above) --
        .hostio4_p1_in            (hostio4_p1_in),
        .hostio4_p1_out           (hostio4_p1_out),
        .hostio4_p1_outen         (hostio4_p1_outen),

        // -- TideLink GPIO-PHY --
        .pad_clk_tx               (pad_clk_tx),
        .pad_tx                   (pad_tx),
        .pad_clk_rx               (pad_clk_rx),
        .pad_rx                   (pad_rx),
        .user_ref_clk             (user_ref_clk),
        // USE_IDELAY defaults to 0 in tidelink_top, making tidelink_idelay_rx
        // a combinational passthrough — this input drives nothing. Tied off
        // rather than fed a real clock, so no phantom 200 MHz domain appears
        // in the timing graph.
        .idelay_ref_clk           (1'b0),

        // -- I2C sideband: no board device; hold released --
        .i2c_scl_i                (1'b1),
        .i2c_scl_o                (),
        .i2c_scl_t                (),
        .i2c_sda_i                (1'b1),
        .i2c_sda_o                (),
        .i2c_sda_t                (),

        // -- Link straps --
        // Single die in loopback: role_strap 0 (die_a). nego_priority must be
        // NON-ZERO or two ends have no tiebreak — irrelevant in loopback but
        // set so a promoted two-die build starts from a sane value.
        .role_strap_i             (1'b0),
        .nego_priority_i          (16'h0001),
        .mask_hs_bypass_i         (1'b0),
        .apb_debug_unlock_i       (1'b0),
        .puf_seed                 (16'h0000),
        .puf_ready                (1'b0),

        // -- DFT --
        .scan_mode                (1'b0),
        .scan_asyncrst_ctrl       (1'b0),
        .scan_clk                 (1'b0),
        .scan_shift               (1'b0),
        .scan_in                  (1'b0),
        .scan_out                 (),

        // -- Link observability --
        .link_active_o            (link_active_o),
        .d2d_reset_o              (d2d_reset_o),
        .role_is_master_o         (role_is_master_o),
        .role_locked_o            (role_locked_o),
        .servo_locked_o           (servo_locked_o),
        .tl_ewma_credit_o         (tl_ewma_credit_o),
        .tidechart_irq_o          (tidechart_irq_o)
    );

    //=========================================================================
    // Status LEDs — 8 of them (4 red R0..R3, 4 green G0..G3).
    //
    // Read across the room. Reds are "something to look at", greens are
    // "healthy". led[7] blinks whenever the system clock is alive, so a dark
    // board and a stuck board are never confused.
    //
    //   led[0] R0  system out of reset
    //   led[1] R1  network core in HardFault lockup      (bad)
    //   led[2] R2  chip core in HardFault lockup         (bad)
    //   led[3] R3  chip core watchdog fired              (bad)
    //   led[4] G0  sys_hclk ALIVE (CPU-clock liveness) — was d2d link active
    //   led[5] G1  d2d role locked
    //   led[6] G2  UART TX activity (stretched)
    //   led[7] G3  heartbeat (~1.5 Hz at 25 MHz)
    //=========================================================================
    localparam integer HEARTBEAT_BIT = 24;   // 25 MHz / 2^24 ~= 1.5 Hz toggle
    localparam integer STRETCH_BIT   = 21;

    reg [HEARTBEAT_BIT:0] heartbeat_cnt;
    always @(posedge sys_fclk or negedge sys_sysresetn) begin
        if (!sys_sysresetn) heartbeat_cnt <= {(HEARTBEAT_BIT+1){1'b0}};
        else                heartbeat_cnt <= heartbeat_cnt + 1'b1;
    end

    // sys_hclk liveness probe (repurposes led[4], formerly d2d link-active).
    // The heartbeat above is on sys_fclk, which keeps toggling even when the PMU
    // releases sys_hresetn but never starts sys_hclk — so it cannot distinguish
    // "CPU clock alive" from "core frozen out of reset". This counter is clocked
    // by sys_hclk itself: if led[4] blinks, the PMU-generated CPU clock really
    // oscillates (so a silent UART is a firmware/startup fault); if led[4] stays
    // dark while led[0] (sys_hresetn) is lit, reset is released but the clock is
    // dead — i.e. the PRMU clock-gen, not just PMUENABLE, is the remaining bug.
    reg [HEARTBEAT_BIT:0] hclk_hb_cnt;
    always @(posedge sys_hclk or negedge sys_hresetn) begin
        if (!sys_hresetn) hclk_hb_cnt <= {(HEARTBEAT_BIT+1){1'b0}};
        else              hclk_hb_cnt <= hclk_hb_cnt + 1'b1;
    end

    // Stretch UART TX edges to something an eye can see.
    reg                 uart_txd_q;
    reg [STRETCH_BIT:0] uart_act_cnt;
    always @(posedge sys_fclk or negedge sys_sysresetn) begin
        if (!sys_sysresetn) begin
            uart_txd_q   <= 1'b1;
            uart_act_cnt <= {(STRETCH_BIT+1){1'b0}};
        end else begin
            uart_txd_q <= uart_txd;
            if (uart_txd_q != uart_txd)
                uart_act_cnt <= {(STRETCH_BIT+1){1'b1}};
            else if (|uart_act_cnt)
                uart_act_cnt <= uart_act_cnt - 1'b1;
        end
    end

    //=========================================================================
    // Debug ILA taps (re-added for SWD bring-up debug). The ILA core is inserted
    // post-synth by build_vivado.tcl and read over the onboard FT232H JTAG (no
    // external probe, no VTref). SWD focus: dbg_swd_* show whether the external
    // SWD probe reaches the DAP and which way the pad is driven --
    //   dbg_swd_clk = incoming SWCLK, dbg_swd_tms = SWDIO-in (dap_swditms),
    //   dbg_swd_o = SWDIO-out (dap_swdo), dbg_swd_oen = DAP drive-enable.
    // Sampled on sys_fclk (always alive). dbg_hclk_cnt = sys_hclk liveness.
    //=========================================================================
    (* mark_debug = "true" *) wire       dbg_uart_txd  = uart_txd;
    (* mark_debug = "true" *) wire       dbg_uart_rxd  = uart_rxd;
    (* mark_debug = "true" *) wire       dbg_swd_clk   = swd_clk;
    (* mark_debug = "true" *) wire       dbg_swd_tms   = dap_swditms;
    (* mark_debug = "true" *) wire       dbg_swd_o     = dap_swdo;
    (* mark_debug = "true" *) wire       dbg_swd_oen   = dap_swdoen;
    (* mark_debug = "true" *) wire       dbg_hresetn   = sys_hresetn;
    (* mark_debug = "true" *) wire       dbg_poresetn  = sys_poresetn;
    (* mark_debug = "true" *) wire       dbg_net_lock  = network_core_lockup;
    (* mark_debug = "true" *) wire       dbg_chip_lock = chip_core_lockup;
    (* mark_debug = "true" *) wire [7:0] dbg_hclk_cnt  = hclk_hb_cnt[7:0];

    assign led[0] = sys_hresetn;
    assign led[1] = network_core_lockup;
    assign led[2] = chip_core_lockup;
    assign led[3] = chip_core_wdog_reset;
    assign led[4] = hclk_hb_cnt[HEARTBEAT_BIT]; // was link_active_o (d2d): sys_hclk liveness
    assign led[5] = role_locked_o;
    assign led[6] = |uart_act_cnt;
    assign led[7] = heartbeat_cnt[HEARTBEAT_BIT];

endmodule
