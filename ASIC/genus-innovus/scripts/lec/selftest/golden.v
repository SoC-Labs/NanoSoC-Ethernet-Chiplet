//-----------------------------------------------------------------------------
// selftest/golden.v -- stands in for outputs/<block>_gate_power.v
// A joint work commissioned on behalf of SoC Labs, under Arm Academic
// Access license.
//
// Copyright (C) 2026, SoC Labs (www.soclabs.org)
//-----------------------------------------------------------------------------
// Shaped like the real synthesis netlist, in every respect that could break
// the LEC setup:
//   * VDD / VSS as INOUT ports on the module      (as Genus writes with power
//                                                  intent applied)
//   * .VDD (VDD) / .VSS (VSS) on every leaf cell  (159,692 of them in the real
//                                                  gate_power.v -- the pins are
//                                                  pg_pin groups in
//                                                  tcbn65lpwc.lib, not
//                                                  ordinary pins, so whether
//                                                  Conformal accepts these
//                                                  connections is the single
//                                                  biggest setup risk)
//   * a compiled memory macro instanced from Liberty and blackboxed
//   * Cadence-style `.PIN (net)` spacing
//
// Deliberately tiny otherwise: the point is to exercise the harness, not the
// design.
//-----------------------------------------------------------------------------

module lecmini (a, b, clk, rstn, addr, wdata, y, q, VDD, VSS);
  input          a, b, clk, rstn;
  input  [7:0]   addr;
  input  [31:0]  wdata;
  output         y;
  output [31:0]  q;
  inout          VDD, VSS;

  wire na, nd;

  INVD1   u_inv (.I (a), .ZN (na), .VDD (VDD), .VSS (VSS));
  ND2D1   u_nd  (.A1 (na), .A2 (b), .ZN (nd), .VDD (VDD), .VSS (VSS));
  DFCNQD1 u_ff  (.D (nd), .CP (clk), .CDN (rstn), .Q (y), .VDD (VDD), .VSS (VSS));

  rf_01k u_mem (.Q (q), .CLK (clk), .CEN (1'b0), .WEN (32'b0), .A (addr),
                .D (wdata), .EMA (3'b011), .EMAW (2'b01), .GWEN (1'b0),
                .RET1N (1'b1), .VDD (VDD), .VSS (VSS));

endmodule
