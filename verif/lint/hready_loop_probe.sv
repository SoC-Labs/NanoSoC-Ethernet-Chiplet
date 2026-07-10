//-----------------------------------------------------------------------------
// hready_loop_probe — synthesizable static-lint harness for the peer-aperture
// HREADY combinational cycle (docs/D2D_HREADY_LOOP.md).
//
// A joint work commissioned on behalf of SoC Labs, under Arm Academic Access
// license.
//
// Copyright 2026, SoC Labs (www.soclabs.org)
//-----------------------------------------------------------------------------
// The sim guard verif/chiplet_d2d_decode/tb_hready_loop.sv proves the fix by
// RUNNING transactions. Verilator 4.028 cannot parse that file (event controls
// in tasks / initial blocks), and a static loop check does not need to run
// anything anyway. This file is the STATIC counterpart: pure structural RTL
// (no initial, no @, no #delay) that closes the same peer HREADY feedback the
// integration top closes, so `verilator --lint-only` can hunt the cycle with
// UNOPTFLAT.
//
// tl_sub_stub reproduces the one property of TideLink's ahb_sub that creates the
// hazard: hreadyout is a COMBINATIONAL function of hready (tidelink_top.sv:1119,
// 1169). This is exactly what a body-less blackbox stub CANNOT model, which is
// why linting the wrapper against stubs does not surface the bug and this
// behavioural probe is required.
//
// Three wirings, selected by +define (see verif/lint/run.sh):
//   (none)                -> shipped fix:  hready_to_peer = dph_peer ? 1 : hready
//   +define+NO_HREADY_FIX -> the bug:      hready_to_peer = hready
//   +define+STRUCT_TIE    -> structural:   hready_to_peer = 1'b1
//
// RESULT (documented in docs/LINT_FINDINGS.md):
//   NO_HREADY_FIX -> UNOPTFLAT fires   (the class is detected)
//   shipped fix   -> UNOPTFLAT fires   (the fix is a DYNAMIC/state-mux break;
//                                       `hready` is still a static fan-in, and a
//                                       conservative static checker cannot see
//                                       the mutual exclusion of the two selects)
//   STRUCT_TIE    -> clean             (no `hready` fan-in at all)
//-----------------------------------------------------------------------------
`timescale 1ns/1ps

module hready_loop_probe (
    input  wire        hclk,
    input  wire        hresetn,
    input  wire [31:0] haddr,
    input  wire  [1:0] htrans,
    input  wire        hwrite,
    input  wire [31:0] hwdata,
    output wire [31:0] hrdata,
    output wire        hready,
    output wire        hresp
);
    wire hsel_tx, hsel_fifo, hsel_ptp, hsel_tlapb, hsel_tcapb, hsel_peer;
    wire dph_peer;
    wire [31:0] hrdata_peer;
    wire        hreadyout_peer, hresp_peer;

`ifdef NO_HREADY_FIX
    wire hready_to_peer = hready;                     // the bug (old wiring)
`elsif STRUCT_TIE
    wire hready_to_peer = 1'b1;                       // structural tie (no hready fan-in)
`else
    wire hready_to_peer = dph_peer ? 1'b1 : hready;   // the shipped fix (dynamic break)
`endif

    chiplet_d2d_decode dut (
        .hclk(hclk), .hresetn(hresetn), .haddr(haddr), .htrans(htrans),
        .link_active_i(1'b1),
        .hrdata(hrdata), .hready(hready), .hresp(hresp),
        .hsel_tx(hsel_tx), .hsel_fifo(hsel_fifo), .hsel_ptp(hsel_ptp),
        .hsel_tlapb(hsel_tlapb), .hsel_tcapb(hsel_tcapb), .hsel_peer(hsel_peer),
        .dph_peer(dph_peer),
        .hrdata_tx   (32'h0), .hreadyout_tx   (1'b1), .hresp_tx   (1'b0),
        .hrdata_fifo (32'h0), .hreadyout_fifo (1'b1), .hresp_fifo (1'b0),
        .hrdata_ptp  (32'h0), .hreadyout_ptp  (1'b1), .hresp_ptp  (1'b0),
        .hrdata_tlapb(32'h0), .hreadyout_tlapb(1'b1), .hresp_tlapb(1'b0),
        .hrdata_tcapb(32'h0), .hreadyout_tcapb(1'b1), .hresp_tcapb(1'b0),
        .hrdata_peer (hrdata_peer), .hreadyout_peer(hreadyout_peer), .hresp_peer(hresp_peer)
    );

    tl_sub_stub u_peer (
        .hclk(hclk), .hresetn(hresetn),
        .hsel(hsel_peer), .haddr(haddr), .htrans(htrans),
        .hwrite(hwrite), .hwdata(hwdata), .hready(hready_to_peer),
        .hrdata(hrdata_peer), .hreadyout(hreadyout_peer), .hresp(hresp_peer)
    );
endmodule

// A minimal AHB-Lite subordinate whose hreadyout is a combinational function of
// its hready, reproducing tidelink_top.sv:1119,1169.
module tl_sub_stub (
    input  wire        hclk,
    input  wire        hresetn,
    input  wire        hsel,
    input  wire [31:0] haddr,
    input  wire  [1:0] htrans,
    input  wire        hwrite,
    input  wire [31:0] hwdata,
    input  wire        hready,
    output wire [31:0] hrdata,
    output wire        hreadyout,
    output wire        hresp
);
    reg [31:0] mem [0:255];
    wire raw_ready      = 1'b1;
    wire ext_addr_phase = hsel & htrans[1] & hready;
    wire ext_is_nonseq  = ext_addr_phase & (htrans == 2'b10);

    reg pipe_valid_r;
    assign hreadyout = (ext_is_nonseq && !pipe_valid_r) ? 1'b0 : raw_ready;
    assign hresp     = 1'b0;
    assign hrdata    = 32'h0;

    always @(posedge hclk or negedge hresetn)
        if (!hresetn) pipe_valid_r <= 1'b0;
        else          pipe_valid_r <= (ext_is_nonseq && !pipe_valid_r);

    reg        dph_valid;
    reg        dph_write;
    reg [31:0] dph_addr;
    always @(posedge hclk or negedge hresetn)
        if (!hresetn) begin dph_valid <= 1'b0; dph_write <= 1'b0; dph_addr <= 32'h0; end
        else if (hreadyout) begin dph_valid <= hsel & htrans[1]; dph_write <= hwrite; dph_addr <= haddr; end

    always @(posedge hclk)
        if (hresetn && hreadyout && dph_valid && dph_write)
            mem[dph_addr[9:2]] <= hwdata;
endmodule
