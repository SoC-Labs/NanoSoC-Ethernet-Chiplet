// =============================================================================
// tb_pair.sv — two cross-wired `tidelink_top` dies with the DATA PLANE wired up.
// A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
//
// Copyright 2026, SoC Labs (www.soclabs.org)
// =============================================================================
// Structure is lifted from `tidelink/cocotb/tidelink_top_pair/tb_top.sv` — same
// two dies, same `pad_skid` pad cross-wiring, same straps, same shared `hclk`.
// The difference is the point of the whole thing:
//
//   that testbench TIES OFF `ahb_sub` and `ahb_mng`.
//
// Those are the two ports the peer aperture rides on, so it can prove the link
// trains and a doorbell crosses, but it cannot prove a MEMORY TRANSACTION
// crosses. Here:
//
//   * die A's `ahb_sub` is driven from cocotb  — this stands in for the SoC's
//     `d2d_ahb_m` port arriving through `chiplet_d2d_decode`'s `hsel_peer`.
//   * die B's `ahb_mng` drives `ahb_probe_mem` — a zero-wait AHB-Lite memory
//     that also LATCHES the address it was presented with.
//
// That latch is the experiment. Die A writes `0x2F00_xxxx`; TideLink's CAM must
// rewrite the upper byte to `0x2D`; the packetiser must carry it; die B's
// manager must re-present `0x2D00_xxxx`. `docs/PEER_APERTURE_PROGRAMMING.md` §8.1
// establishes that by reading the Chisel and the generated Verilog. This
// establishes it by simulating a transaction, which is not the same thing.
//
// Deliberately NOT modelled here:
//   * `chiplet_d2d_decode` — it only generates selects; putting it in the path
//     would drag in an AHB-to-APB bridge for the two APB banks and prove nothing
//     new. Its wedge gate is proven at unit level in `verif/chiplet_d2d_decode`.
//   * the two `nanosoc_multicore_soc` instances — an AHB master model stands in
//     for CPU0. Swapping them in is the remaining step of G2; the addressing and
//     bring-up do not change.
//
// As in the upstream tb, NOTHING here generates a clock or a reset: `hclk`,
// `ref_clk`, `poresetn`, `hresetn` and the two POR gates are driven from cocotb,
// so a test can skew one die's reset against the other.
// =============================================================================
`timescale 1ns/1ps

module tb_pair #(
`ifdef TB_TOP_SKID_BITS
    parameter int SKID_BITS = `TB_TOP_SKID_BITS,
`else
    parameter int SKID_BITS = 0,
`endif
`ifdef TB_TOP_BYPASS_AUTONEG
    parameter int BYPASS_AUTONEG = `TB_TOP_BYPASS_AUTONEG,
`else
    parameter int BYPASS_AUTONEG = 1,
`endif
    parameter int SYS_ADDR_W    = 32,
    parameter int SYS_DATA_W    = 32,
    parameter int RAM_ADDR_W    = 14,
    parameter int RAM_DATA_W    = 32,
    parameter int APB_ADDR_W    = 12,
    parameter int FC_DATA_W     = 48,
    parameter int NUM_PHY_LANES = 8,
    parameter logic [31:0] M_PAIR_BASE = 32'h4403_2000,
    parameter logic [31:0] S_PAIR_BASE = 32'h4403_2000
);

    // ---------------------------------------------------------------------
    // Clocks and resets — all cocotb-driven (see header).
    // ---------------------------------------------------------------------
    logic hclk     = 1'b0;
    logic ref_clk  = 1'b0;
    logic poresetn = 1'b0;
    logic hresetn  = 1'b0;

    // Per-die POR gates. Holding one die in reset is how a test asks "what does
    // die A do when there is nothing at the far end?".
    logic m_por_gate = 1'b1;
    logic s_por_gate = 1'b1;
    wire  m_poresetn_w = poresetn & m_por_gate;
    wire  m_hresetn_w  = hresetn  & m_por_gate;
    wire  s_poresetn_w = poresetn & s_por_gate;
    wire  s_hresetn_w  = hresetn  & s_por_gate;

    // ---------------------------------------------------------------------
    // Straps. NEGO_CFG_RESET is 7'h00, not the 7'h61 the integration guide
    // claims, so autoneg parks in ST_BYPASS at POR and the link is brought up
    // from software over APB. mask_hs_bypass_i / apb_debug_unlock_i must be 1 or
    // the APB writes that do that are refused.
    // ---------------------------------------------------------------------
    logic m_apb_debug_unlock = 1'b1;
    logic s_apb_debug_unlock = 1'b1;
    logic m_mask_hs_bypass   = 1'b1;
    logic s_mask_hs_bypass   = 1'b1;

    // ---------------------------------------------------------------------
    // PHY pads, cross-wired through pad_skid (SKID_BITS=0 => passthrough).
    // An in-reset die's pad drive is squashed to 0 by the peer's POR gate so it
    // cannot X-poison the live die.
    // ---------------------------------------------------------------------
    wire                     m_pad_clk_tx, s_pad_clk_tx;
    wire [NUM_PHY_LANES-1:0] m_pad_tx,     s_pad_tx;
    wire                     m_pad_clk_tx_skid, s_pad_clk_tx_skid;
    wire [NUM_PHY_LANES-1:0] m_pad_tx_skid,     s_pad_tx_skid;

    pad_skid #(.SKID_BITS(SKID_BITS), .LANES(NUM_PHY_LANES)) u_skid_m2s (
        .pad_clk_in (m_pad_clk_tx),      .pad_data_in (m_pad_tx),
        .pad_clk_out(m_pad_clk_tx_skid), .pad_data_out(m_pad_tx_skid));

    pad_skid #(.SKID_BITS(SKID_BITS), .LANES(NUM_PHY_LANES)) u_skid_s2m (
        .pad_clk_in (s_pad_clk_tx),      .pad_data_in (s_pad_tx),
        .pad_clk_out(s_pad_clk_tx_skid), .pad_data_out(s_pad_tx_skid));

    // ---------------------------------------------------------------------
    // APB config ports (cocotb-driven), one per die.
    // ---------------------------------------------------------------------
    logic        m_apb_psel = 1'b0, m_apb_penable = 1'b0, m_apb_pwrite = 1'b0;
    logic [14:0] m_apb_paddr  = 15'h0;
    logic  [3:0] m_apb_pstrb  = 4'hF;
    logic  [2:0] m_apb_pprot  = 3'h0;
    logic [31:0] m_apb_pwdata = 32'h0;
    wire  [31:0] m_apb_prdata;
    wire         m_apb_pready, m_apb_pslverr;

    logic        s_apb_psel = 1'b0, s_apb_penable = 1'b0, s_apb_pwrite = 1'b0;
    logic [14:0] s_apb_paddr  = 15'h0;
    logic  [3:0] s_apb_pstrb  = 4'hF;
    logic  [2:0] s_apb_pprot  = 3'h0;
    logic [31:0] s_apb_pwdata = 32'h0;
    wire  [31:0] s_apb_prdata;
    wire         s_apb_pready, s_apb_pslverr;

    // ---------------------------------------------------------------------
    // Die A `ahb_sub` — the peer aperture. Driven from cocotb.
    // hprot is 4 bits on the subordinate port (it is 7 on the manager).
    // ---------------------------------------------------------------------
    logic        m_sub_hsel   = 1'b0;
    logic [31:0] m_sub_haddr  = 32'h0;
    logic  [2:0] m_sub_hburst = 3'h0;
    logic  [3:0] m_sub_hprot  = 4'h0;
    logic  [2:0] m_sub_hsize  = 3'b010;   // word
    logic  [1:0] m_sub_htrans = 2'b00;    // IDLE
    logic [31:0] m_sub_hwdata = 32'h0;
    logic        m_sub_hwrite = 1'b0;
    wire  [31:0] m_sub_hrdata;
    wire         m_sub_hresp, m_sub_hreadyout;

    // DO NOT write `m_sub_hready = m_sub_hreadyout` here. TideLink's
    // `ahb_sub_hreadyout` depends COMBINATIONALLY on `ahb_sub_hready`:
    //
    //   ext_addr_phase    = ahb_sub_hsel & ahb_sub_htrans[1] & ahb_sub_hready;
    //   ext_is_nonseq     = ext_addr_phase & (htrans == 2'b10);
    //   ahb_sub_hreadyout = (ext_is_nonseq && !pipe_valid_r) ? 1'b0
    //                                                        : xhb_sub_hreadyout_raw;
    //                                                     (tidelink_top.sv:1119,1120,1169)
    //
    // so hready=1 -> hreadyout=0 -> hready=0 -> hreadyout=1 -> ... a zero-delay
    // loop. VCS spins at 100% CPU with simulation time frozen; it does not error.
    //
    // Tying hready high is what TideLink's own pair tb does, and it is safe HERE
    // because this master asserts hsel only during its address phase and holds
    // the address across wait states. It does mean this tb does not model the
    // chiplet's own hready feedback path — see docs/D2D_HREADY_LOOP.md, which
    // records that `nanosoc_eth_chiplet.sv` DOES close this loop on back-to-back
    // peer transfers.
    wire         m_sub_hready = 1'b1;

    // ---------------------------------------------------------------------
    // Die B `ahb_mng` — what the far die re-issues into its local fabric.
    // These are OUTPUTS of tidelink_top; the memory drives the three inputs.
    // ---------------------------------------------------------------------
    wire [31:0] s_mng_haddr;
    wire  [2:0] s_mng_hburst;
    wire  [6:0] s_mng_hprot;
    wire  [2:0] s_mng_hsize;
    wire  [1:0] s_mng_htrans;
    wire [31:0] s_mng_hwdata;
    wire        s_mng_hwrite;
    wire        s_mng_hready;
    wire [31:0] s_mng_hrdata;
    wire        s_mng_hresp;

    // The observation point. `probe_*` are read by cocotb.
    wire [31:0] probe_last_haddr;
    wire [31:0] probe_last_hwdata;
    wire [31:0] probe_write_count;
    wire [31:0] probe_read_count;

    ahb_probe_mem #(.MEM_WORDS(4096)) u_probe_mem (
        .hclk       (hclk),
        .hresetn    (s_hresetn_w),
        .haddr      (s_mng_haddr),
        .htrans     (s_mng_htrans),
        .hwrite     (s_mng_hwrite),
        .hsize      (s_mng_hsize),
        .hwdata     (s_mng_hwdata),
        .hrdata     (s_mng_hrdata),
        .hready     (s_mng_hready),
        .hresp      (s_mng_hresp),
        .last_haddr (probe_last_haddr),
        .last_hwdata(probe_last_hwdata),
        .write_count(probe_write_count),
        .read_count (probe_read_count));

    // ---------------------------------------------------------------------
    // Link status + interrupts, exposed for cocotb.
    // ---------------------------------------------------------------------
    wire m_link_active, s_link_active;
    wire m_d2d_reset_o, s_d2d_reset_o;
    wire m_role_is_master, s_role_is_master;
    wire m_role_locked,    s_role_locked;
    wire m_doorbell_irq,   s_doorbell_irq;
    wire m_released_credits_irq, s_released_credits_irq;
    wire m_packet_committed_irq, s_packet_committed_irq;
    wire m_ptp_irq, s_ptp_irq, m_perf_irq, s_perf_irq, m_wlink_irq, s_wlink_irq;
    wire m_nego_error_irq, s_nego_error_irq;
    wire m_i2c_nbsy_irq, s_i2c_nbsy_irq;
    wire m_i2c_nrd_empty_irq, s_i2c_nrd_empty_irq;

    // ---------------------------------------------------------------------
    // I2C sideband: open-drain wired-AND with pull-ups, as upstream.
    // ---------------------------------------------------------------------
    wire m_i2c_scl_o, m_i2c_scl_t, m_i2c_sda_o, m_i2c_sda_t;
    wire s_i2c_scl_o, s_i2c_scl_t, s_i2c_sda_o, s_i2c_sda_t;
    wire i2c_scl = (m_i2c_scl_t ? 1'b1 : m_i2c_scl_o) & (s_i2c_scl_t ? 1'b1 : s_i2c_scl_o);
    wire i2c_sda = (m_i2c_sda_t ? 1'b1 : m_i2c_sda_o) & (s_i2c_sda_t ? 1'b1 : s_i2c_sda_o);

    // =====================================================================
    // Die A — master
    // =====================================================================
    tidelink_top #(
        .SYS_ADDR_W        (SYS_ADDR_W),
        .SYS_DATA_W        (SYS_DATA_W),
        .RAM_ADDR_W        (RAM_ADDR_W),
        .RAM_DATA_W        (RAM_DATA_W),
        .APB_ADDR_W        (APB_ADDR_W),
        .FC_DATA_W         (FC_DATA_W),
        .NUM_PHY_LANES     (NUM_PHY_LANES),
        .TIDELINK_PAIR_BASE(M_PAIR_BASE)
    ) u_master (
        .hclk(hclk), .hresetn(m_hresetn_w), .poresetn(m_poresetn_w),

        .pad_clk_tx(m_pad_clk_tx), .pad_tx(m_pad_tx),
        .pad_clk_rx(s_pad_clk_tx_skid & s_por_gate),
        .pad_rx    (s_pad_tx_skid & {NUM_PHY_LANES{s_por_gate}}),

        .apb_psel(m_apb_psel), .apb_paddr(m_apb_paddr), .apb_penable(m_apb_penable),
        .apb_pwrite(m_apb_pwrite), .apb_pstrb(m_apb_pstrb), .apb_pprot(m_apb_pprot),
        .apb_pwdata(m_apb_pwdata), .apb_prdata(m_apb_prdata),
        .apb_pready(m_apb_pready), .apb_pslverr(m_apb_pslverr),

        // The port under test.
        .ahb_sub_hsel(m_sub_hsel), .ahb_sub_haddr(m_sub_haddr),
        .ahb_sub_hburst(m_sub_hburst), .ahb_sub_hprot(m_sub_hprot),
        .ahb_sub_hsize(m_sub_hsize), .ahb_sub_htrans(m_sub_htrans),
        .ahb_sub_hwdata(m_sub_hwdata), .ahb_sub_hwrite(m_sub_hwrite),
        .ahb_sub_hready(m_sub_hready), .ahb_sub_hrdata(m_sub_hrdata),
        .ahb_sub_hresp(m_sub_hresp), .ahb_sub_hreadyout(m_sub_hreadyout),

        // Die A's manager is idle (die B's subordinate is tied off).
        .ahb_mng_haddr(), .ahb_mng_hburst(), .ahb_mng_hprot(), .ahb_mng_hsize(),
        .ahb_mng_htrans(), .ahb_mng_hwdata(), .ahb_mng_hwrite(),
        .ahb_mng_hready(1'b1), .ahb_mng_hrdata(32'h0), .ahb_mng_hresp(1'b0),

        // TX aperture / FIFO / PTP: unused here.
        .ahb_tx_hsel(1'b0), .ahb_tx_haddr({RAM_ADDR_W{1'b0}}), .ahb_tx_htrans(2'b00),
        .ahb_tx_hsize(3'h0), .ahb_tx_hwrite(1'b0), .ahb_tx_hwdata(32'h0),
        .ahb_tx_hready(1'b1), .ahb_tx_hrdata(), .ahb_tx_hresp(), .ahb_tx_hreadyout(),
        .ahb_fifo_hsel(1'b0), .ahb_fifo_haddr({RAM_ADDR_W{1'b0}}), .ahb_fifo_htrans(2'b00),
        .ahb_fifo_hsize(3'h0), .ahb_fifo_hwrite(1'b0), .ahb_fifo_hwdata(32'h0),
        .ahb_fifo_hready(1'b1), .ahb_fifo_hrdata(), .ahb_fifo_hresp(), .ahb_fifo_hreadyout(),
        .ahb_ptp_hsel(1'b0), .ahb_ptp_haddr(4'h0), .ahb_ptp_htrans(2'b00),
        .ahb_ptp_hsize(3'h0), .ahb_ptp_hwrite(1'b0), .ahb_ptp_hwdata(32'h0),
        .ahb_ptp_hready(1'b1), .ahb_ptp_hrdata(), .ahb_ptp_hresp(), .ahb_ptp_hreadyout(),

        .phc_clk(hclk), .phc_resetn(hresetn),
        .phc_nanoseconds(30'h0), .phc_seconds(48'h0), .phc_pps(1'b0),
        .phc_hw_cap_seconds(48'h0), .phc_hw_cap_nanoseconds(30'h0),
        .phc_hw_cap_sub_nanoseconds(32'h0), .phc_locked_i(1'b1),
        .phc_hw_capture(), .phc_hw_set_time(), .phc_hw_set_seconds(),
        .phc_hw_set_nanoseconds(), .phc_hw_adj_valid(), .phc_hw_adj_ns_incr_frac(),
        .servo_locked(),

        .role_strap_i(1'b0),
        .role_is_master_o(m_role_is_master), .role_locked_o(m_role_locked),
        .apb_debug_unlock_i(m_apb_debug_unlock), .mask_hs_bypass_i(m_mask_hs_bypass),
        .nego_priority_i(16'h8000), .puf_seed(16'hA5A5), .puf_ready(1'b1),
        .nego_error_irq(m_nego_error_irq),

        .scan_mode(1'b0), .scan_asyncrst_ctrl(1'b0), .scan_clk(1'b0),
        .scan_shift(1'b0), .scan_in(1'b0), .scan_out(),
        .user_ref_clk(ref_clk), .idelay_ref_clk(1'b0),

        .tc_axis_tx_tvalid(1'b0), .tc_axis_tx_tdata({FC_DATA_W{1'b0}}), .tc_axis_tx_tready(),
        .tc_axis_rx_tvalid(), .tc_axis_rx_tdata(), .tc_axis_rx_tready(1'b1),
        .tc_qos_priority(3'h0),

        .tl_local_link_state_o(), .tl_link_state_change_o(), .tl_ewma_credit_o(),
        .tl_bcast_ack_i(1'b0),

        .link_active(m_link_active), .d2d_reset_o(m_d2d_reset_o),

        .i2c_scl_i(i2c_scl), .i2c_scl_o(m_i2c_scl_o), .i2c_scl_t(m_i2c_scl_t),
        .i2c_sda_i(i2c_sda), .i2c_sda_o(m_i2c_sda_o), .i2c_sda_t(m_i2c_sda_t),

        .s_i2c_axi_awvalid(1'b0), .s_i2c_axi_awid(2'b00), .s_i2c_axi_awaddr(4'h0),
        .s_i2c_axi_awlen(8'h00), .s_i2c_axi_awsize(3'h0), .s_i2c_axi_awburst(2'b00),
        .s_i2c_axi_awlock(1'b0), .s_i2c_axi_awcache(4'h0), .s_i2c_axi_awprot(3'h0),
        .s_i2c_axi_awready(),
        .s_i2c_axi_wvalid(1'b0), .s_i2c_axi_wdata(32'h0), .s_i2c_axi_wstrb(4'h0),
        .s_i2c_axi_wlast(1'b0), .s_i2c_axi_wready(),
        .s_i2c_axi_bvalid(), .s_i2c_axi_bid(), .s_i2c_axi_bresp(), .s_i2c_axi_bready(1'b1),
        .s_i2c_axi_arvalid(1'b0), .s_i2c_axi_arid(2'b00), .s_i2c_axi_araddr(4'h0),
        .s_i2c_axi_arlen(8'h00), .s_i2c_axi_arsize(3'h0), .s_i2c_axi_arburst(2'b00),
        .s_i2c_axi_arlock(1'b0), .s_i2c_axi_arcache(4'h0), .s_i2c_axi_arprot(3'h0),
        .s_i2c_axi_arready(),
        .s_i2c_axi_rvalid(), .s_i2c_axi_rid(), .s_i2c_axi_rdata(), .s_i2c_axi_rresp(),
        .s_i2c_axi_rlast(), .s_i2c_axi_rready(1'b1),
        .i2c_nbsy_irq(m_i2c_nbsy_irq), .i2c_nrd_empty_irq(m_i2c_nrd_empty_irq),

        .released_credits_irq(m_released_credits_irq), .doorbell_irq(m_doorbell_irq),
        .packet_committed_irq(m_packet_committed_irq), .ptp_irq(m_ptp_irq),
        .perf_irq(m_perf_irq), .wlink_irq(m_wlink_irq)
    );

    // =====================================================================
    // Die B — slave. Its `ahb_mng` drives the probe memory; its `ahb_sub` is
    // tied off (we only prove A -> B here; B -> A is symmetric by construction).
    // =====================================================================
    tidelink_top #(
        .SYS_ADDR_W        (SYS_ADDR_W),
        .SYS_DATA_W        (SYS_DATA_W),
        .RAM_ADDR_W        (RAM_ADDR_W),
        .RAM_DATA_W        (RAM_DATA_W),
        .APB_ADDR_W        (APB_ADDR_W),
        .FC_DATA_W         (FC_DATA_W),
        .NUM_PHY_LANES     (NUM_PHY_LANES),
        .TIDELINK_PAIR_BASE(S_PAIR_BASE)
    ) u_slave (
        .hclk(hclk), .hresetn(s_hresetn_w), .poresetn(s_poresetn_w),

        .pad_clk_tx(s_pad_clk_tx), .pad_tx(s_pad_tx),
        .pad_clk_rx(m_pad_clk_tx_skid & m_por_gate),
        .pad_rx    (m_pad_tx_skid & {NUM_PHY_LANES{m_por_gate}}),

        .apb_psel(s_apb_psel), .apb_paddr(s_apb_paddr), .apb_penable(s_apb_penable),
        .apb_pwrite(s_apb_pwrite), .apb_pstrb(s_apb_pstrb), .apb_pprot(s_apb_pprot),
        .apb_pwdata(s_apb_pwdata), .apb_prdata(s_apb_prdata),
        .apb_pready(s_apb_pready), .apb_pslverr(s_apb_pslverr),

        .ahb_sub_hsel(1'b0), .ahb_sub_haddr(32'h0), .ahb_sub_hburst(3'h0),
        .ahb_sub_hprot(4'h0), .ahb_sub_hsize(3'h0), .ahb_sub_htrans(2'b00),
        .ahb_sub_hwdata(32'h0), .ahb_sub_hwrite(1'b0), .ahb_sub_hready(1'b1),
        .ahb_sub_hrdata(), .ahb_sub_hresp(), .ahb_sub_hreadyout(),

        // The observation point.
        .ahb_mng_haddr(s_mng_haddr), .ahb_mng_hburst(s_mng_hburst),
        .ahb_mng_hprot(s_mng_hprot), .ahb_mng_hsize(s_mng_hsize),
        .ahb_mng_htrans(s_mng_htrans), .ahb_mng_hwdata(s_mng_hwdata),
        .ahb_mng_hwrite(s_mng_hwrite),
        .ahb_mng_hready(s_mng_hready), .ahb_mng_hrdata(s_mng_hrdata),
        .ahb_mng_hresp(s_mng_hresp),

        .ahb_tx_hsel(1'b0), .ahb_tx_haddr({RAM_ADDR_W{1'b0}}), .ahb_tx_htrans(2'b00),
        .ahb_tx_hsize(3'h0), .ahb_tx_hwrite(1'b0), .ahb_tx_hwdata(32'h0),
        .ahb_tx_hready(1'b1), .ahb_tx_hrdata(), .ahb_tx_hresp(), .ahb_tx_hreadyout(),
        .ahb_fifo_hsel(1'b0), .ahb_fifo_haddr({RAM_ADDR_W{1'b0}}), .ahb_fifo_htrans(2'b00),
        .ahb_fifo_hsize(3'h0), .ahb_fifo_hwrite(1'b0), .ahb_fifo_hwdata(32'h0),
        .ahb_fifo_hready(1'b1), .ahb_fifo_hrdata(), .ahb_fifo_hresp(), .ahb_fifo_hreadyout(),
        .ahb_ptp_hsel(1'b0), .ahb_ptp_haddr(4'h0), .ahb_ptp_htrans(2'b00),
        .ahb_ptp_hsize(3'h0), .ahb_ptp_hwrite(1'b0), .ahb_ptp_hwdata(32'h0),
        .ahb_ptp_hready(1'b1), .ahb_ptp_hrdata(), .ahb_ptp_hresp(), .ahb_ptp_hreadyout(),

        .phc_clk(hclk), .phc_resetn(hresetn),
        .phc_nanoseconds(30'h0), .phc_seconds(48'h0), .phc_pps(1'b0),
        .phc_hw_cap_seconds(48'h0), .phc_hw_cap_nanoseconds(30'h0),
        .phc_hw_cap_sub_nanoseconds(32'h0), .phc_locked_i(1'b1),
        .phc_hw_capture(), .phc_hw_set_time(), .phc_hw_set_seconds(),
        .phc_hw_set_nanoseconds(), .phc_hw_adj_valid(), .phc_hw_adj_ns_incr_frac(),
        .servo_locked(),

        .role_strap_i(1'b1),
        .role_is_master_o(s_role_is_master), .role_locked_o(s_role_locked),
        .apb_debug_unlock_i(s_apb_debug_unlock), .mask_hs_bypass_i(s_mask_hs_bypass),
        .nego_priority_i(16'h7FFF), .puf_seed(16'h5A5A), .puf_ready(1'b1),
        .nego_error_irq(s_nego_error_irq),

        .scan_mode(1'b0), .scan_asyncrst_ctrl(1'b0), .scan_clk(1'b0),
        .scan_shift(1'b0), .scan_in(1'b0), .scan_out(),
        .user_ref_clk(ref_clk), .idelay_ref_clk(1'b0),

        .tc_axis_tx_tvalid(1'b0), .tc_axis_tx_tdata({FC_DATA_W{1'b0}}), .tc_axis_tx_tready(),
        .tc_axis_rx_tvalid(), .tc_axis_rx_tdata(), .tc_axis_rx_tready(1'b1),
        .tc_qos_priority(3'h0),

        .tl_local_link_state_o(), .tl_link_state_change_o(), .tl_ewma_credit_o(),
        .tl_bcast_ack_i(1'b0),

        .link_active(s_link_active), .d2d_reset_o(s_d2d_reset_o),

        .i2c_scl_i(i2c_scl), .i2c_scl_o(s_i2c_scl_o), .i2c_scl_t(s_i2c_scl_t),
        .i2c_sda_i(i2c_sda), .i2c_sda_o(s_i2c_sda_o), .i2c_sda_t(s_i2c_sda_t),

        .s_i2c_axi_awvalid(1'b0), .s_i2c_axi_awid(2'b00), .s_i2c_axi_awaddr(4'h0),
        .s_i2c_axi_awlen(8'h00), .s_i2c_axi_awsize(3'h0), .s_i2c_axi_awburst(2'b00),
        .s_i2c_axi_awlock(1'b0), .s_i2c_axi_awcache(4'h0), .s_i2c_axi_awprot(3'h0),
        .s_i2c_axi_awready(),
        .s_i2c_axi_wvalid(1'b0), .s_i2c_axi_wdata(32'h0), .s_i2c_axi_wstrb(4'h0),
        .s_i2c_axi_wlast(1'b0), .s_i2c_axi_wready(),
        .s_i2c_axi_bvalid(), .s_i2c_axi_bid(), .s_i2c_axi_bresp(), .s_i2c_axi_bready(1'b1),
        .s_i2c_axi_arvalid(1'b0), .s_i2c_axi_arid(2'b00), .s_i2c_axi_araddr(4'h0),
        .s_i2c_axi_arlen(8'h00), .s_i2c_axi_arsize(3'h0), .s_i2c_axi_arburst(2'b00),
        .s_i2c_axi_arlock(1'b0), .s_i2c_axi_arcache(4'h0), .s_i2c_axi_arprot(3'h0),
        .s_i2c_axi_arready(),
        .s_i2c_axi_rvalid(), .s_i2c_axi_rid(), .s_i2c_axi_rdata(), .s_i2c_axi_rresp(),
        .s_i2c_axi_rlast(), .s_i2c_axi_rready(1'b1),
        .i2c_nbsy_irq(s_i2c_nbsy_irq), .i2c_nrd_empty_irq(s_i2c_nrd_empty_irq),

        .released_credits_irq(s_released_credits_irq), .doorbell_irq(s_doorbell_irq),
        .packet_committed_irq(s_packet_committed_irq), .ptp_irq(s_ptp_irq),
        .perf_irq(s_perf_irq), .wlink_irq(s_wlink_irq)
    );

    // ---------------------------------------------------------------------
    // Autoneg bypass escape hatch, same as upstream. Inert at the default
    // BYPASS_AUTONEG=1, where the link is brought up from software over APB.
    // ---------------------------------------------------------------------
`define M_CTRL u_master.u_chiplet_controller
`define S_CTRL u_slave.u_chiplet_controller
    initial begin
        if (BYPASS_AUTONEG == 0) begin
            force `M_CTRL.nego_cfg_reg     = 7'h61;
            force `M_CTRL.nego_train_cfg_r = 16'h00F1;
            force `S_CTRL.nego_cfg_reg     = 7'h61;
            force `S_CTRL.nego_train_cfg_r = 16'h00F1;
            force `M_CTRL.nego_priority_reg = 16'h0001;
            force `S_CTRL.nego_priority_reg = 16'h0002;
            #5000;
            release `M_CTRL.nego_cfg_reg;      release `M_CTRL.nego_train_cfg_r;
            release `S_CTRL.nego_cfg_reg;      release `S_CTRL.nego_train_cfg_r;
            release `M_CTRL.nego_priority_reg; release `S_CTRL.nego_priority_reg;
        end
    end

`ifdef DUMP_FSDB
    initial begin
        $dumpfile("waves.vcd");
        $dumpvars(0, tb_pair);
    end
`endif

endmodule


// =============================================================================
// ahb_probe_mem — zero-wait AHB-Lite subordinate that remembers what it saw.
//
// Sits on die B's `ahb_mng`, which is a MANAGER port: there is no `hsel`, so a
// transfer is selected by `htrans[1]` (NONSEQ/SEQ) alone.
//
// `last_haddr` is the whole point: it is the address die B's fabric is actually
// presented with, after the CAM rewrote the upper byte on die A and the
// packetiser carried it across. A test asserts it equals 0x2D......, and — the
// part that makes the test mean something — that it does NOT equal 0x2F.......
// =============================================================================
`timescale 1ns/1ps

module ahb_probe_mem #(
    parameter int MEM_WORDS = 4096
) (
    input  wire        hclk,
    input  wire        hresetn,
    input  wire [31:0] haddr,
    input  wire  [1:0] htrans,
    input  wire        hwrite,
    input  wire  [2:0] hsize,
    input  wire [31:0] hwdata,
    output wire [31:0] hrdata,
    output wire        hready,
    output wire        hresp,
    output wire [31:0] last_haddr,
    output wire [31:0] last_hwdata,
    output wire [31:0] write_count,
    output wire [31:0] read_count
);
    localparam int IDX_W = $clog2(MEM_WORDS);

    logic [31:0] mem [0:MEM_WORDS-1];

    // Address phase -> data phase pipeline. Zero wait states, so every address
    // phase is accepted and retired on the next clock.
    logic [31:0] addr_q;
    logic        write_q;
    logic        active_q;

    logic [31:0] last_haddr_q, last_hwdata_q, wr_cnt_q, rd_cnt_q;

    wire sel = htrans[1];   // NONSEQ or SEQ

    always_ff @(posedge hclk or negedge hresetn) begin
        if (!hresetn) begin
            addr_q   <= 32'h0;
            write_q  <= 1'b0;
            active_q <= 1'b0;
        end else begin
            addr_q   <= haddr;
            write_q  <= hwrite;
            active_q <= sel;
        end
    end

    always_ff @(posedge hclk or negedge hresetn) begin
        if (!hresetn) begin
            last_haddr_q  <= 32'h0;
            last_hwdata_q <= 32'h0;
            wr_cnt_q      <= 32'h0;
            rd_cnt_q      <= 32'h0;
        end else if (active_q) begin
            // Latch in the DATA phase, when hwdata is valid.
            last_haddr_q <= addr_q;
            if (write_q) begin
                mem[addr_q[IDX_W+1:2]] <= hwdata;
                last_hwdata_q          <= hwdata;
                wr_cnt_q               <= wr_cnt_q + 32'd1;
            end else begin
                rd_cnt_q <= rd_cnt_q + 32'd1;
            end
        end
    end

    assign hrdata      = mem[addr_q[IDX_W+1:2]];
    assign hready      = 1'b1;
    assign hresp       = 1'b0;
    assign last_haddr  = last_haddr_q;
    assign last_hwdata = last_hwdata_q;
    assign write_count = wr_cnt_q;
    assign read_count  = rd_cnt_q;
endmodule
