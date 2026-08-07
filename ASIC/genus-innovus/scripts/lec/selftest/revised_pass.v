//-----------------------------------------------------------------------------
// selftest/revised_pass.v -- stands in for outputs/<block>_pnr.v, EQUIVALENT
// A joint work commissioned on behalf of SoC Labs, under Arm Academic
// Access license.
//
// Copyright (C) 2026, SoC Labs (www.soclabs.org)
//-----------------------------------------------------------------------------
// golden.v after a plausible pass of P&R:
//   * a CTS clock buffer between the clock port and the flop  (the real
//     netlist gained 22,046 CKBD0 alone)
//   * two hold-repair delay cells on the data path            (the real
//     netlist gained 10,555 DEL* cells that NOTHING in this repo verified
//     before this harness existed)
//   * bond-pad cells that exist only post-route, instanced with an empty
//     connection list exactly as Innovus writes them
//   * Innovus `.PIN(net)` spacing rather than Genus's `.PIN (net)`
//
// Logically identical to golden.v. The harness MUST pass this. If it does
// not, the setup is rejecting legitimate P&R decoration and would have to be
// fixed before any verdict from it meant anything.
//-----------------------------------------------------------------------------

module lecmini (a, b, clk, rstn, addr, wdata, y, q, VDD, VSS);
  input          a, b, clk, rstn;
  input  [7:0]   addr;
  input  [31:0]  wdata;
  output         y;
  output [31:0]  q;
  inout          VDD, VSS;

  wire na, nd, nd_d1, nd_d2, clk_buf;

  CKBD0   u_cts_buf (.I(clk), .Z(clk_buf), .VDD(VDD), .VSS(VSS));

  INVD1   u_inv (.I(a), .ZN(na), .VDD(VDD), .VSS(VSS));
  ND2D1   u_nd  (.A1(na), .A2(b), .ZN(nd), .VDD(VDD), .VSS(VSS));

  DEL0    u_hold_0 (.I(nd),    .Z(nd_d1), .VDD(VDD), .VSS(VSS));
  DEL2    u_hold_1 (.I(nd_d1), .Z(nd_d2), .VDD(VDD), .VSS(VSS));

  DFCNQD1 u_ff (.D(nd_d2), .CP(clk_buf), .CDN(rstn), .Q(y), .VDD(VDD), .VSS(VSS));

  rf_01k u_mem (.Q(q), .CLK(clk_buf), .CEN(1'b0), .WEN(32'b0), .A(addr),
                .D(wdata), .EMA(3'b011), .EMAW(2'b01), .GWEN(1'b0),
                .RET1N(1'b1), .VDD(VDD), .VSS(VSS));

  PAD70GU BuPAD_a ();
  PAD70NU BuPAD_b ();

endmodule
