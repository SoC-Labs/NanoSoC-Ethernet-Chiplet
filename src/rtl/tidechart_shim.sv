//-----------------------------------------------------------------------------
// tidechart_shim — flattened-port wrapper for tidechart_controller
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
// WHY THIS EXISTS
//
// `tidechart_controller` presents three of its ports as SystemVerilog UNPACKED
// arrays, one element per link port:
//
//     input  wire [FC_DATA_W-1:0] tc_axis_rx_tdata   [NUM_PORTS]
//     output wire [FC_DATA_W-1:0] tc_axis_tx_tdata   [NUM_PORTS]
//     input  wire [4:0]           local_link_state_i [NUM_PORTS]
//
// The nanosoc_gen structural back-end emits module instances with a single
// PACKED dimension per port ([MSB:LSB] vectors); it has no representation for a
// second, unpacked dimension. A generated netlist therefore cannot bind to
// those three ports at all — there is no port-connection syntax the generator
// can produce that an unpacked-array port will accept.
//
// This shim is the boundary the generator instantiates instead. It re-exposes
// every tidechart_controller port 1:1 EXCEPT the three above, which it presents
// as flat PACKED vectors (`*_flat`), then unpacks them internally and hands the
// unpacked arrays to a `tidechart_controller` instance. No port direction or
// width changes other than the flattening; every parameter passes straight
// through to the instance.
//
// ORDERING CONVENTION (load-bearing — getting this backwards silently swaps
// link ports with no elaboration error):
//
//     element i  <->  flat[i*W +: W]
//     element 0  ==  flat[W-1 : 0]      (the LEAST-significant W bits)
//
//   where W = FC_DATA_W for the tdata vectors and W = 5 for the link-state
//   vector. This is the same little-end-first packing the generator uses when
//   it concatenates per-port signals, so a generated flat bus lines up with the
//   controller's element[0..NUM_PORTS-1] with no reordering.
//
// CONSTRAINT: the local_link_state width is a hard-coded [4:0] (5 bits) inside
// tidechart_controller — there is no parameter for it — so this shim hard-codes
// the same 5 in `local_link_state_i_flat`. If tidechart_controller ever
// parameterises that width, this literal must track it.
//-----------------------------------------------------------------------------

module tidechart_shim #(
    parameter NUM_PORTS        = 2,
    parameter DEVICE_CLASS     = 16'h0001,
    parameter FC_DATA_W        = 48,
    parameter APB_ADDR_W       = 8,
    parameter SYS_DATA_W       = 32,
    parameter ID_W             = 5,
    parameter PORT_W           = 3,
    parameter MAX_HOPS         = 8,
    parameter PUF_ENABLE       = 0,
    parameter PUF_NUM_WORDS    = 16,
    parameter INTERFACE_MAP    = 16'h0800,
    parameter COMPUTE_CLASS    = 8'h01,
    parameter DAP_PRESENT      = 0,
    parameter NUM_DEBUG_CORES  = 1,
    parameter ACCEL_COUNT      = 0,
    parameter SRAM_BLOCK_COUNT = 0
)(
    input  wire                          clk,
    input  wire                          resetn,

    // =========================================================================
    // Per-port AXI-Stream interface (from/to tidelink_top instances)
    //   tc_axis_rx_tdata / tc_axis_tx_tdata FLATTENED to packed *_flat vectors.
    // =========================================================================
    input  wire [NUM_PORTS-1:0]          tc_axis_rx_tvalid,
    input  wire [NUM_PORTS*FC_DATA_W-1:0] tc_axis_rx_tdata_flat,
    output wire [NUM_PORTS-1:0]          tc_axis_rx_tready,

    output wire [NUM_PORTS-1:0]          tc_axis_tx_tvalid,
    output wire [NUM_PORTS*FC_DATA_W-1:0] tc_axis_tx_tdata_flat,
    input  wire [NUM_PORTS-1:0]          tc_axis_tx_tready,

    input  wire [NUM_PORTS-1:0]          link_active,

    // =========================================================================
    // Congestion sideband (Phase 2 — from tidelink_top instances)
    //   local_link_state_i FLATTENED to a packed *_flat vector (5 bits/element).
    // =========================================================================
    input  wire [NUM_PORTS*5-1:0]        local_link_state_i_flat,
    input  wire [NUM_PORTS-1:0]          local_link_state_change_i,
    output wire [NUM_PORTS-1:0]          local_bcast_ack_o,

    // =========================================================================
    // APB Slave (own address space)
    // =========================================================================
    input  wire [APB_ADDR_W-1:0]         apb_paddr,
    input  wire                          apb_psel,
    input  wire                          apb_penable,
    input  wire                          apb_pwrite,
    input  wire [SYS_DATA_W-1:0]         apb_pwdata,
    output wire [SYS_DATA_W-1:0]         apb_prdata,
    output wire                          apb_pready,
    output wire                          apb_pslverr,

    // =========================================================================
    // Interrupt
    // =========================================================================
    output wire                          tidechart_irq,

    // =========================================================================
    // IRQC AXI-Stream Interfaces (Phase P4 — to/from ahb-chiplet-irqc)
    // =========================================================================
    output wire                          tc_to_irqc_tvalid_o,
    output wire [47:0]                   tc_to_irqc_tdata_o,
    input  wire                          tc_to_irqc_tready_i,
    output wire                          tc_to_irqc_tlast_o,

    input  wire                          irqc_to_tc_tvalid_i,
    input  wire [31:0]                   irqc_to_tc_tdata_i,
    output wire                          irqc_to_tc_tready_o
);

    // Local hard-coded link-state width; mirrors tidechart_controller's [4:0].
    localparam LINK_STATE_W = 5;

    // =========================================================================
    // Unpacked arrays presented to the tidechart_controller instance. These map
    // 1:1 onto its unpacked-array ports; the *_flat boundary vectors are sliced
    // in/out below.
    // =========================================================================
    wire [FC_DATA_W-1:0]    tc_axis_rx_tdata_arr   [NUM_PORTS];
    wire [FC_DATA_W-1:0]    tc_axis_tx_tdata_arr   [NUM_PORTS];
    wire [LINK_STATE_W-1:0] local_link_state_i_arr [NUM_PORTS];

    // =========================================================================
    // Flatten <-> unpack. Indexed part-selects keep element i on bits
    // [i*W +: W], i.e. element 0 in the LSBs (see ORDERING CONVENTION above).
    // =========================================================================
    genvar gi;
    generate
        for (gi = 0; gi < NUM_PORTS; gi = gi + 1) begin : g_port
            // Inputs: drive the unpacked arrays from the flat input vectors.
            assign tc_axis_rx_tdata_arr[gi] =
                       tc_axis_rx_tdata_flat[gi*FC_DATA_W +: FC_DATA_W];
            assign local_link_state_i_arr[gi] =
                       local_link_state_i_flat[gi*LINK_STATE_W +: LINK_STATE_W];

            // Output: pack the controller's unpacked tx array into the flat bus.
            assign tc_axis_tx_tdata_flat[gi*FC_DATA_W +: FC_DATA_W] =
                       tc_axis_tx_tdata_arr[gi];
        end
    endgenerate

    // =========================================================================
    // The wrapped controller. Every parameter passes through unchanged.
    // =========================================================================
    tidechart_controller #(
        .NUM_PORTS        (NUM_PORTS),
        .DEVICE_CLASS     (DEVICE_CLASS),
        .FC_DATA_W        (FC_DATA_W),
        .APB_ADDR_W       (APB_ADDR_W),
        .SYS_DATA_W       (SYS_DATA_W),
        .ID_W             (ID_W),
        .PORT_W           (PORT_W),
        .MAX_HOPS         (MAX_HOPS),
        .PUF_ENABLE       (PUF_ENABLE),
        .PUF_NUM_WORDS    (PUF_NUM_WORDS),
        .INTERFACE_MAP    (INTERFACE_MAP),
        .COMPUTE_CLASS    (COMPUTE_CLASS),
        .DAP_PRESENT      (DAP_PRESENT),
        .NUM_DEBUG_CORES  (NUM_DEBUG_CORES),
        .ACCEL_COUNT      (ACCEL_COUNT),
        .SRAM_BLOCK_COUNT (SRAM_BLOCK_COUNT)
    ) u_tidechart_controller (
        .clk                        (clk),
        .resetn                     (resetn),

        .tc_axis_rx_tvalid          (tc_axis_rx_tvalid),
        .tc_axis_rx_tdata           (tc_axis_rx_tdata_arr),
        .tc_axis_rx_tready          (tc_axis_rx_tready),

        .tc_axis_tx_tvalid          (tc_axis_tx_tvalid),
        .tc_axis_tx_tdata           (tc_axis_tx_tdata_arr),
        .tc_axis_tx_tready          (tc_axis_tx_tready),

        .link_active                (link_active),

        .local_link_state_i         (local_link_state_i_arr),
        .local_link_state_change_i  (local_link_state_change_i),
        .local_bcast_ack_o          (local_bcast_ack_o),

        .apb_paddr                  (apb_paddr),
        .apb_psel                   (apb_psel),
        .apb_penable                (apb_penable),
        .apb_pwrite                 (apb_pwrite),
        .apb_pwdata                 (apb_pwdata),
        .apb_prdata                 (apb_prdata),
        .apb_pready                 (apb_pready),
        .apb_pslverr                (apb_pslverr),

        .tidechart_irq              (tidechart_irq),

        .tc_to_irqc_tvalid_o        (tc_to_irqc_tvalid_o),
        .tc_to_irqc_tdata_o         (tc_to_irqc_tdata_o),
        .tc_to_irqc_tready_i        (tc_to_irqc_tready_i),
        .tc_to_irqc_tlast_o         (tc_to_irqc_tlast_o),

        .irqc_to_tc_tvalid_i        (irqc_to_tc_tvalid_i),
        .irqc_to_tc_tdata_i         (irqc_to_tc_tdata_i),
        .irqc_to_tc_tready_o        (irqc_to_tc_tready_o)
    );

endmodule
