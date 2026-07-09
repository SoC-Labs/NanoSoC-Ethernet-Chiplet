//-----------------------------------------------------------------------------
// chiplet_d2d_decode — AHB-Lite sub-decoder for the nanoSoC D2D window
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
// `nanosoc_multicore_soc` exports one AHB manager port (`d2d_ahb_m_*`) carrying
// the 32 MB die-to-die window 0x2E000000..0x2FFFFFFF off-module. In a CHIPLET
// build this decoder splits that window into the four `tidelink_top` AHB
// subordinates, a TideLink APB bridge and a TideChart APB bridge — and answers
// every hole in the window with a hard AHB ERROR rather than OKAY-with-zeros.
//
// WHY the shape below, not a plain address comparator:
//
//   1. No HSEL exists at this boundary. `d2d_ahb_m` is an INITIATOR port; the
//      SoC's bus matrix has already folded its own decode into HTRANS
//      (`d2d_ahb_m_htrans = d2d_hsel ? d2d_htrans : 2'b00`). So a non-IDLE
//      HTRANS arriving here *is* the "this transfer is for the D2D window"
//      qualifier. htrans[1] == 1 for NONSEQ(2'b10)/SEQ(2'b11), 0 for
//      IDLE(2'b00)/BUSY(2'b01) — i.e. htrans[1] is exactly "a real transfer".
//
//   2. AHB-Lite is pipelined: HRDATA/HREADYOUT/HRESP land one phase AFTER the
//      HADDR that selected the slave. Muxing the responses with the live
//      address-phase decode returns the WRONG slave whenever two beats overlap.
//      So the winning select is captured into a data-phase register on every
//      cycle the bus is ready, and the response mux is driven from THAT — the
//      one non-negotiable correctness rule for an AHB decoder.
//
//   3. A stray pointer into an unmapped offset must fault, not vanish. The
//      internal default responder reproduces the same two-cycle ERROR the SoC's
//      top-level default slave used to raise for 0x2E/0x2F (see the sibling
//      `nanosoc_d2d_idle_slave.v`). Returning OKAY+zeros here would silently
//      swallow the access — the exact debugging trap this design rejects.
//
// Region map (decoded on HADDR; haddr[24] splits 0x2E from 0x2F):
//
//   haddr[24]==1                        -> peer   0x2F000000  16 MB (ahb_sub)
//   haddr[24]==0 & haddr[19:16]==4'h0   -> tx     0x2E000000        (ahb_tx)
//   haddr[24]==0 & haddr[19:16]==4'h1   -> fifo   0x2E010000        (ahb_fifo)
//   haddr[24]==0 & haddr[19:16]==4'h2   -> ptp    0x2E020000        (ahb_ptp)
//   haddr[24]==0 & haddr[19:16]==4'h3   -> tlapb  0x2E030000        (tidelink APB)
//   haddr[24]==0 & haddr[19:16]==4'h4   -> tcapb  0x2E040000        (tidechart APB)
//   anything else in the window         -> internal default: two-cycle ERROR
//
// CONSTRAINT: address/control/write-data fan out to the slaves DIRECTLY from the
// top level. This module owns only the HSELs and the response mux; it never sees
// HWDATA/HWRITE/HSIZE/HBURST and must not need them.
//
// Response timing for the default responder (AHB-Lite requires two cycles so the
// master can cancel its pipelined address phase):
//
//   cycle 0   addr phase accepted   hready=1
//   cycle 1   ERR1                  hready=0 hresp=1
//   cycle 2   ERR2                  hready=1 hresp=1   (master samples ERROR)
//
//-----------------------------------------------------------------------------

module chiplet_d2d_decode (
    input  wire        hclk,
    input  wire        hresetn,
    // From the SoC's d2d_ahb_m manager port (no hsel)
    input  wire [31:0] haddr,
    input  wire  [1:0] htrans,
    // Response back to the SoC
    output wire [31:0] hrdata,
    output wire        hready,
    output wire        hresp,
    // Per-slave selects (address phase)
    output wire        hsel_tx,
    output wire        hsel_fifo,
    output wire        hsel_ptp,
    output wire        hsel_tlapb,
    output wire        hsel_tcapb,
    output wire        hsel_peer,
    // Per-slave responses (data phase)
    input  wire [31:0] hrdata_tx,   input wire hreadyout_tx,   input wire hresp_tx,
    input  wire [31:0] hrdata_fifo, input wire hreadyout_fifo, input wire hresp_fifo,
    input  wire [31:0] hrdata_ptp,  input wire hreadyout_ptp,  input wire hresp_ptp,
    input  wire [31:0] hrdata_tlapb,input wire hreadyout_tlapb,input wire hresp_tlapb,
    input  wire [31:0] hrdata_tcapb,input wire hreadyout_tcapb,input wire hresp_tcapb,
    input  wire [31:0] hrdata_peer, input wire hreadyout_peer, input wire hresp_peer
);

    //-------------------------------------------------------------------------
    // Address-phase decode
    //
    // Pure-address region membership first, then gate with htrans[1] to form the
    // outgoing HSELs. haddr[24] alone separates the two 16 MB apertures; inside
    // 0x2E the 64 KB block index haddr[19:16] selects the port. A well-behaved
    // AHB decoder keeps HSEL asserted through wait states (the address phase is
    // held), so HSEL is NOT gated by hready — only by htrans[1].
    //-------------------------------------------------------------------------
    wire        xfer   = htrans[1];             // NONSEQ/SEQ; a real transfer
    wire        in_2e  = ~haddr[24];            // 0x2E aperture
    wire [3:0]  blk    =  haddr[19:16];         // 64 KB block within 0x2E

    wire a_tx    = in_2e & (blk == 4'h0);
    wire a_fifo  = in_2e & (blk == 4'h1);
    wire a_ptp   = in_2e & (blk == 4'h2);
    wire a_tlapb = in_2e & (blk == 4'h3);
    wire a_tcapb = in_2e & (blk == 4'h4);
    wire a_peer  = haddr[24];                   // all of 0x2F is the peer window
    wire a_dflt  = in_2e & (blk >  4'h4);       // 0x2E050000..0x2E0FFFFF: unmapped

    assign hsel_tx    = xfer & a_tx;
    assign hsel_fifo  = xfer & a_fifo;
    assign hsel_ptp   = xfer & a_ptp;
    assign hsel_tlapb = xfer & a_tlapb;
    assign hsel_tcapb = xfer & a_tcapb;
    assign hsel_peer  = xfer & a_peer;
    wire   sel_dflt   = xfer & a_dflt;          // internal-only: default responder

    //-------------------------------------------------------------------------
    // Data-phase select capture
    //
    // Encode the winning address-phase select and register it on every ready
    // cycle. Only ONE code can be set because the regions are mutually exclusive
    // by construction (a_peer on haddr[24], the rest on distinct blk values).
    // Updating solely when `hready` is high is what pipelines the select into the
    // data phase — this is the register whose absence is the classic AHB decode
    // bug the header warns about.
    //-------------------------------------------------------------------------
    localparam [2:0] DPH_NONE  = 3'd0,
                     DPH_TX    = 3'd1,
                     DPH_FIFO  = 3'd2,
                     DPH_PTP   = 3'd3,
                     DPH_TLAPB = 3'd4,
                     DPH_TCAPB = 3'd5,
                     DPH_PEER  = 3'd6,
                     DPH_DFLT  = 3'd7;

    wire [2:0] aph_code = hsel_tx    ? DPH_TX    :
                          hsel_fifo  ? DPH_FIFO  :
                          hsel_ptp   ? DPH_PTP   :
                          hsel_tlapb ? DPH_TLAPB :
                          hsel_tcapb ? DPH_TCAPB :
                          hsel_peer  ? DPH_PEER  :
                          sel_dflt   ? DPH_DFLT  :
                                       DPH_NONE;

    reg [2:0] dph_code;
    always @(posedge hclk or negedge hresetn) begin
        if (!hresetn)      dph_code <= DPH_NONE;
        else if (hready)   dph_code <= aph_code;   // advance only when bus ready
    end

    //-------------------------------------------------------------------------
    // Internal default responder (two-cycle AHB-Lite ERROR)
    //
    // dph_code holds DPH_DFLT across BOTH error cycles (it cannot advance while
    // hready is low), so a single bit distinguishes them. INVARIANT: dph_code can
    // only change to DPH_DFLT on an edge where hready==1, and that same edge
    // clears err2 — hence the first DFLT cycle is always err1 (hready=0) and the
    // next is always err2 (hready=1). No separate FSM state is needed.
    //-------------------------------------------------------------------------
    reg dflt_err2;
    always @(posedge hclk or negedge hresetn) begin
        if (!hresetn)    dflt_err2 <= 1'b0;
        else if (hready) dflt_err2 <= 1'b0;   // entering a fresh data phase
        else             dflt_err2 <= 1'b1;   // held low last cycle -> now err2
    end

    wire in_dflt      = (dph_code == DPH_DFLT);
    wire dflt_hready  = dflt_err2;             // 0 in err1, 1 in err2
    wire dflt_hresp   = in_dflt;               // ERROR across both cycles

    //-------------------------------------------------------------------------
    // Response mux — driven by the DATA-PHASE code, never the live decode.
    // DPH_NONE (idle bus) returns ready+OKAY+zeros so the SoC never stalls on a
    // dead window.
    //-------------------------------------------------------------------------
    reg [31:0] hrdata_r;
    reg        hready_r;
    reg        hresp_r;

    always @(*) begin
        case (dph_code)
            DPH_TX:    begin hrdata_r = hrdata_tx;    hready_r = hreadyout_tx;    hresp_r = hresp_tx;    end
            DPH_FIFO:  begin hrdata_r = hrdata_fifo;  hready_r = hreadyout_fifo;  hresp_r = hresp_fifo;  end
            DPH_PTP:   begin hrdata_r = hrdata_ptp;   hready_r = hreadyout_ptp;   hresp_r = hresp_ptp;   end
            DPH_TLAPB: begin hrdata_r = hrdata_tlapb; hready_r = hreadyout_tlapb; hresp_r = hresp_tlapb; end
            DPH_TCAPB: begin hrdata_r = hrdata_tcapb; hready_r = hreadyout_tcapb; hresp_r = hresp_tcapb; end
            DPH_PEER:  begin hrdata_r = hrdata_peer;  hready_r = hreadyout_peer;  hresp_r = hresp_peer;  end
            DPH_DFLT:  begin hrdata_r = 32'h0;        hready_r = dflt_hready;     hresp_r = dflt_hresp;  end
            default:   begin hrdata_r = 32'h0;        hready_r = 1'b1;            hresp_r = 1'b0;        end
        endcase
    end

    assign hrdata = hrdata_r;
    assign hready = hready_r;
    assign hresp  = hresp_r;

endmodule
