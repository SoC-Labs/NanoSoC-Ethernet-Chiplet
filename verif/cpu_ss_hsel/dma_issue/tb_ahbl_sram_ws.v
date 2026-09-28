// Scratch AHB-Lite SRAM for the cpu_ss_hsel DMA-issue measurement.
// Word transfers only. Wait states per region, set at run time from cocotb:
// ws_lo for HADDR[15]==0 (source region), ws_hi for HADDR[15]==1 (destination region).
module tb_ahbl_sram_ws (
    input  wire        HCLK, HRESETn, HSEL,
    input  wire [31:0] HADDR,
    input  wire [1:0]  HTRANS,
    input  wire        HWRITE,
    input  wire [2:0]  HSIZE,
    input  wire [31:0] HWDATA,
    input  wire        HREADY,
    output wire [31:0] HRDATA,
    output wire        HREADYOUT,
    output wire        HRESP
);
  reg [31:0] mem [0:16383];
  reg  [3:0] ws_lo = 4'd0, ws_hi = 4'd0;
  reg        busy, wr_q;
  reg  [3:0] ws_cnt;
  reg [13:0] idx_q;
  wire active = HSEL & HREADY & HTRANS[1];
  assign HREADYOUT = !busy || (ws_cnt == 4'd0);
  assign HRDATA    = mem[idx_q];
  assign HRESP     = 1'b0;
  always @(posedge HCLK or negedge HRESETn) begin
    if (!HRESETn) begin
      busy <= 1'b0; wr_q <= 1'b0; ws_cnt <= 4'd0; idx_q <= 14'd0;
    end else if (HREADYOUT) begin
      if (busy && wr_q) mem[idx_q] <= HWDATA;       // data phase completes this edge
      if (active) begin
        busy <= 1'b1; wr_q <= HWRITE; idx_q <= HADDR[15:2];
        ws_cnt <= HADDR[15] ? ws_hi : ws_lo;
      end else begin
        busy <= 1'b0;
      end
    end else begin
      ws_cnt <= ws_cnt - 4'd1;
    end
  end
endmodule
