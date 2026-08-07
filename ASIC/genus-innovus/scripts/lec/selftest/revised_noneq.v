//-----------------------------------------------------------------------------
// selftest/revised_noneq.v -- MUTANT. Must be caught.
// A joint work commissioned on behalf of SoC Labs, under Arm Academic
// Access license.
//
// Copyright (C) 2026, SoC Labs (www.soclabs.org)
//-----------------------------------------------------------------------------
// revised_pass.v with ONE gate changed:
//
//     ND2D1  ZN = !(A1 & A2)      ->     NR2D1  ZN = !(A1 | A2)
//
// Same pin names, same drive strength, same cell family, one instance out of
// six. This is the smallest realistic corruption -- the shape a bad ECO or a
// mis-set dont_touch would leave -- and the whole point of logical equivalence
// checking is to catch it.
//
// The harness MUST report FAIL and exit non-zero on this file. If it reports
// PASS, `make lec-pnr` is decoration and should be deleted rather than
// trusted: that is exactly the state `make lec` was in before this directory
// existed, where `exit -f`'s status was thrown away by the Makefile recipe and
// a non-equivalent result printed success.
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

  // vvv THE MUTATION vvv
  NR2D1   u_nd  (.A1(na), .A2(b), .ZN(nd), .VDD(VDD), .VSS(VSS));
  // ^^^ was ND2D1 ^^^

  DEL0    u_hold_0 (.I(nd),    .Z(nd_d1), .VDD(VDD), .VSS(VSS));
  DEL2    u_hold_1 (.I(nd_d1), .Z(nd_d2), .VDD(VDD), .VSS(VSS));

  DFCNQD1 u_ff (.D(nd_d2), .CP(clk_buf), .CDN(rstn), .Q(y), .VDD(VDD), .VSS(VSS));

  rf_01k u_mem (.Q(q), .CLK(clk_buf), .CEN(1'b0), .WEN(32'b0), .A(addr),
                .D(wdata), .EMA(3'b011), .EMAW(2'b01), .GWEN(1'b0),
                .RET1N(1'b1), .VDD(VDD), .VSS(VSS));

  PAD70GU BuPAD_a ();
  PAD70NU BuPAD_b ();

endmodule
