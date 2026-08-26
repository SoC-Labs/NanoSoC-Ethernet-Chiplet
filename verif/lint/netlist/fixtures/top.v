// Gate-netlist-shaped top: structural instances only
module top (input clk, input [7:0] addr, output [31:0] dout, output spare);
  wire [31:0] q;
  MY_SRAM u_sram (
    .CLK (clk),
    .A   (addr[3:0]),   // WIDTH MISMATCH: 4 bits into an 8-bit port
    .Q   (q),
    .CEN ()             // EMPTY: explicitly unconnected input
                        // WEN entirely OMITTED from the port list
  );
  assign dout = q;
  // 'spare' is never driven
endmodule
