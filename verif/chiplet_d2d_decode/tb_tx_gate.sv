// Focused check of the TX-aperture wedge gate in chiplet_d2d_decode.
// With link_active_i=0, a TX-aperture access must assert NO hsel and take the
// two-cycle AHB ERROR from the internal default responder. With it high, the
// access must select the TX slave as before.
`timescale 1ns/1ps
module tb;
    reg clk = 0, rstn = 0, link = 0;
    reg [31:0] haddr = 32'h0;
    reg  [1:0] htrans = 2'b00;
    wire [31:0] hrdata; wire hready, hresp;
    wire hsel_tx, hsel_fifo, hsel_ptp, hsel_tlapb, hsel_tcapb, hsel_peer;
    integer errs = 0;
    always #5 clk = ~clk;

    chiplet_d2d_decode dut (
        .hclk(clk), .hresetn(rstn), .haddr(haddr), .htrans(htrans),
        .link_active_i(link),
        .hrdata(hrdata), .hready(hready), .hresp(hresp),
        .hsel_tx(hsel_tx), .hsel_fifo(hsel_fifo), .hsel_ptp(hsel_ptp),
        .hsel_tlapb(hsel_tlapb), .hsel_tcapb(hsel_tcapb), .hsel_peer(hsel_peer),
        .hrdata_tx(32'hAAAA0000), .hreadyout_tx(1'b1), .hresp_tx(1'b0),
        .hrdata_fifo(32'h0), .hreadyout_fifo(1'b1), .hresp_fifo(1'b0),
        .hrdata_ptp(32'h0), .hreadyout_ptp(1'b1), .hresp_ptp(1'b0),
        .hrdata_tlapb(32'h0), .hreadyout_tlapb(1'b1), .hresp_tlapb(1'b0),
        .hrdata_tcapb(32'h0), .hreadyout_tcapb(1'b1), .hresp_tcapb(1'b0),
        .hrdata_peer(32'h0), .hreadyout_peer(1'b1), .hresp_peer(1'b0)
    );

    task chk(input string what, input bit cond);
        begin
            if (!cond) begin $display("FAIL %s", what); errs++; end
            else            $display("ok   %s", what);
        end
    endtask

    initial begin
        repeat (2) @(posedge clk); rstn = 1;
        @(posedge clk); #1;

        // --- link UP: TX aperture selects the TX slave ---
        link = 1; haddr = 32'h2E00_0004; htrans = 2'b10;
        #1; chk("link up: hsel_tx asserted", hsel_tx === 1'b1);
        @(posedge clk); #1; htrans = 2'b00;
        chk("link up: no ERROR (hresp low)", hresp === 1'b0);
        @(posedge clk); #1;

        // --- link DOWN: TX aperture must NOT select, and must fault ---
        link = 0; haddr = 32'h2E00_0004; htrans = 2'b10;
        #1;
        chk("link down: hsel_tx DEASSERTED", hsel_tx === 1'b0);
        chk("link down: no other hsel",
            {hsel_fifo,hsel_ptp,hsel_tlapb,hsel_tcapb,hsel_peer} === 5'b0);
        @(posedge clk); #1; htrans = 2'b00;
        chk("link down: ERR1 hready=0 hresp=1", (hready===1'b0) && (hresp===1'b1));
        @(posedge clk); #1;
        chk("link down: ERR2 hready=1 hresp=1", (hready===1'b1) && (hresp===1'b1));
        @(posedge clk); #1;
        chk("link down: back to idle OKAY", (hready===1'b1) && (hresp===1'b0));

        // --- link DOWN must NOT affect the other regions ---
        haddr = 32'h2E01_0000; htrans = 2'b10; #1;
        chk("link down: fifo still selectable", hsel_fifo === 1'b1);
        @(posedge clk); #1; htrans = 2'b00;
        haddr = 32'h2F00_0000; htrans = 2'b10; #1;
        chk("link down: peer still selectable", hsel_peer === 1'b1);
        @(posedge clk); #1; htrans = 2'b00;
        haddr = 32'h2E03_0000; htrans = 2'b10; #1;
        chk("link down: tlapb still selectable (bring-up MUST work)", hsel_tlapb === 1'b1);
        @(posedge clk); #1; htrans = 2'b00;

        @(posedge clk);
        $display("\n%s (errors=%0d)", (errs==0) ? "PASS" : "FAIL", errs);
        $finish;
    end
endmodule
