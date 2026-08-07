//-----------------------------------------------------------------------------
// selftest/revised_extra.v -- MUTANT. Must be caught.
// A joint work commissioned on behalf of SoC Labs, under Arm Academic
// Access license.
//
// Copyright (C) 2026, SoC Labs (www.soclabs.org)
//-----------------------------------------------------------------------------
// revised_pass.v plus STATE AND A PORT THAT THE GOLDEN DOES NOT HAVE: one
// extra flop, and one extra primary output driven by it.
//
// Every gate that golden.v has is still present and still correct, so a
// checker that only looks for non-equivalent compare points reports PASS on
// this file. It is wrong to: the revised netlist has a key point with no
// counterpart, which in the real flow is what a spurious P&R-inserted
// register, a retimed pipeline stage, or (much more likely) comparing the
// WRONG PAIR OF NETLISTS looks like.
//
// This is the case that justifies failing on unmapped / extra / unreachable
// points and not only on non-equivalence. The harness MUST exit non-zero.
//-----------------------------------------------------------------------------

module lecmini (a, b, clk, rstn, addr, wdata, y, y2, q, VDD, VSS);
  input          a, b, clk, rstn;
  input  [7:0]   addr;
  input  [31:0]  wdata;
  output         y;
  output         y2;      // <-- extra primary output
  output [31:0]  q;
  inout          VDD, VSS;

  wire na, nd, nd_d1, nd_d2, clk_buf, nb;

  CKBD0   u_cts_buf (.I(clk), .Z(clk_buf), .VDD(VDD), .VSS(VSS));

  INVD1   u_inv (.I(a), .ZN(na), .VDD(VDD), .VSS(VSS));
  ND2D1   u_nd  (.A1(na), .A2(b), .ZN(nd), .VDD(VDD), .VSS(VSS));

  DEL0    u_hold_0 (.I(nd),    .Z(nd_d1), .VDD(VDD), .VSS(VSS));
  DEL2    u_hold_1 (.I(nd_d1), .Z(nd_d2), .VDD(VDD), .VSS(VSS));

  DFCNQD1 u_ff (.D(nd_d2), .CP(clk_buf), .CDN(rstn), .Q(y), .VDD(VDD), .VSS(VSS));

  // vvv EXTRA STATE -- no counterpart in golden.v vvv
  INVD1   u_inv_b (.I(b), .ZN(nb), .VDD(VDD), .VSS(VSS));
  DFCNQD1 u_ff_extra (.D(nb), .CP(clk_buf), .CDN(rstn), .Q(y2),
                      .VDD(VDD), .VSS(VSS));
  // ^^^ EXTRA STATE ^^^

  rf_01k u_mem (.Q(q), .CLK(clk_buf), .CEN(1'b0), .WEN(32'b0), .A(addr),
                .D(wdata), .EMA(3'b011), .EMAW(2'b01), .GWEN(1'b0),
                .RET1N(1'b1), .VDD(VDD), .VSS(VSS));

  PAD70GU BuPAD_a ();
  PAD70NU BuPAD_b ();

endmodule
