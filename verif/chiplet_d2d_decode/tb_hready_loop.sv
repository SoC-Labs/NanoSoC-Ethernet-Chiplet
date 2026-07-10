// Regression guard for the peer-aperture HREADY combinational cycle.
// A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
//
// Copyright 2026, SoC Labs (www.soclabs.org)
//
// `nanosoc_eth_chiplet.sv` used to feed `chiplet_d2d_decode`'s muxed `hready`
// straight back into TideLink's `ahb_sub_hready`. TideLink's `ahb_sub_hreadyout`
// reads that input combinationally, so the pair closed a cycle with no register
// in it, and it oscillated on back-to-back peer transfers.
//
// `tl_sub_stub` below reproduces TideLink's dependence exactly
// (tidelink_top.sv:1119, 1120, 1169). The testbench wires it the way the chiplet
// does and drives four back-to-back NONSEQ peer writes with no IDLE between
// them -- the memcpy pattern that activates the cycle.
//
//   default               -> uses `dph_peer` to break the cycle. Must PASS.
//   +define+NO_HREADY_FIX -> wires hready straight back, as the chiplet once did.
//                            VCS SPINS WITH SIMULATION TIME FROZEN. It does not
//                            error and it does not finish. Do not run in CI.
//
// There is no way to make the broken variant fail cleanly: a zero-delay loop
// means no timeout can fire, because no time passes. The guard is that the fixed
// variant completes and gets the right answers, and that removing the fix hangs.
//
// See docs/D2D_HREADY_LOOP.md.
`timescale 1ns/1ps

module tb_hready_loop;

    localparam int NBEATS = 4;

    reg clk = 1'b0;
    reg rstn = 1'b0;
    always #5 clk = ~clk;

    // AHB master side (stands in for the SoC's d2d_ahb_m). Driven on negedge so
    // nothing races the DUT's posedge sampling.
    reg  [31:0] haddr  = 32'h0;
    reg   [1:0] htrans = 2'b00;
    reg         hwrite = 1'b0;
    reg  [31:0] hwdata = 32'h0;

    wire [31:0] hrdata;
    wire        hready;
    wire        hresp;

    wire hsel_tx, hsel_fifo, hsel_ptp, hsel_tlapb, hsel_tcapb, hsel_peer;
    wire dph_peer;

    wire [31:0] hrdata_peer;
    wire        hreadyout_peer, hresp_peer;

    // The one line under test. With the fix, the peer never sees its own
    // hreadyout handed back as its hready.
`ifdef NO_HREADY_FIX
    wire hready_to_peer = hready;                       // the bug
`else
    wire hready_to_peer = dph_peer ? 1'b1 : hready;     // the fix
`endif

    chiplet_d2d_decode dut (
        .hclk(clk), .hresetn(rstn), .haddr(haddr), .htrans(htrans),
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
        .hclk(clk), .hresetn(rstn),
        .hsel(hsel_peer), .haddr(haddr), .htrans(htrans),
        .hwrite(hwrite), .hwdata(hwdata), .hready(hready_to_peer),
        .hrdata(hrdata_peer), .hreadyout(hreadyout_peer), .hresp(hresp_peer)
    );

    integer errors = 0;
    integer i;

    // Wait for the address phase currently on the bus to be accepted.
    task await_accept;
        begin
            forever begin
                @(posedge clk);
                if (hready) disable await_accept;
            end
        end
    endtask

    initial begin
        repeat (4) @(negedge clk);
        rstn = 1'b1;

        // Pipelined, back-to-back NONSEQ peer writes with no IDLE beat. While
        // beat i is in its DATA phase (dph_code == DPH_PEER), beat i+1 presents
        // its ADDRESS phase. That overlap is what closes the cycle.
        for (i = 0; i < NBEATS; i = i + 1) begin
            @(negedge clk);
            haddr  = 32'h2F00_0000 + (i << 2);
            htrans = 2'b10;                        // NONSEQ every beat
            hwrite = 1'b1;
            await_accept;                          // address phase committed
            @(negedge clk);
            hwdata = 32'hC0FF_EE00 + i;            // beat i's data phase
        end

        @(negedge clk);
        htrans = 2'b00;                            // IDLE; last data phase runs
        await_accept;
        repeat (4) @(posedge clk);

        for (i = 0; i < NBEATS; i = i + 1) begin
            if (u_peer.mem[i] !== (32'hC0FF_EE00 + i)) begin
                $display("FAIL: peer mem[%0d] = 0x%08x, expected 0x%08x",
                         i, u_peer.mem[i], 32'hC0FF_EE00 + i);
                errors = errors + 1;
            end
        end

        if (u_peer.write_count !== NBEATS) begin
            $display("FAIL: peer saw %0d writes, expected %0d", u_peer.write_count, NBEATS);
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS: %0d back-to-back peer writes completed and landed; no comb loop", NBEATS);
        else
            $display("FAIL: %0d error(s)", errors);
        $finish;
    end

    // Useless against a zero-delay loop (no time passes), but it catches a plain
    // stall if someone changes the stub.
    initial begin
        #100000;
        $display("FAIL: timed out (a plain stall). If instead simulation time is frozen, the HREADY cycle is back - see docs/D2D_HREADY_LOOP.md");
        $finish;
    end

endmodule


// A minimal AHB-Lite subordinate that reproduces the one thing about TideLink's
// `ahb_sub` that matters here: its `hreadyout` is a function of its `hready`.
//
//   ext_addr_phase = hsel & htrans[1] & hready              (tidelink_top.sv:1119)
//   ext_is_nonseq  = ext_addr_phase & (htrans == 2'b10)     (:1120)
//   hreadyout      = (ext_is_nonseq && !pipe_valid_r) ? 0 : raw   (:1169)
//
// `raw` stands for XHB500's own hreadyout, taken as always-accepting. The single
// wait state on each NONSEQ is TideLink's pipeline-fill cycle.
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
    integer    write_count = 0;

    wire raw_ready      = 1'b1;
    wire ext_addr_phase = hsel & htrans[1] & hready;
    wire ext_is_nonseq  = ext_addr_phase & (htrans == 2'b10);

    reg pipe_valid_r = 1'b0;
    assign hreadyout = (ext_is_nonseq && !pipe_valid_r) ? 1'b0 : raw_ready;
    assign hresp     = 1'b0;
    assign hrdata    = 32'h0;

    always @(posedge hclk or negedge hresetn) begin
        if (!hresetn) pipe_valid_r <= 1'b0;
        else          pipe_valid_r <= (ext_is_nonseq && !pipe_valid_r);
    end

    // Standard AHB address-phase capture: only when this subordinate is ready,
    // i.e. only when the bus is actually advancing.
    reg        dph_valid = 1'b0;
    reg        dph_write = 1'b0;
    reg [31:0] dph_addr  = 32'h0;

    always @(posedge hclk or negedge hresetn) begin
        if (!hresetn) begin
            dph_valid <= 1'b0;
            dph_write <= 1'b0;
            dph_addr  <= 32'h0;
        end else if (hreadyout) begin
            dph_valid <= hsel & htrans[1];
            dph_write <= hwrite;
            dph_addr  <= haddr;
        end
    end

    // Commit in the data phase, when hwdata is valid and the phase completes.
    always @(posedge hclk) begin
        if (hresetn && hreadyout && dph_valid && dph_write) begin
            mem[dph_addr[9:2]] <= hwdata;
            write_count        <= write_count + 1;
        end
    end
endmodule
