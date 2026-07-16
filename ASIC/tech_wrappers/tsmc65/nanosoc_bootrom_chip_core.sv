//------------------------------------------------------------------------------------
// Auto-generated synthesizable Bootrom
//
// Generated from bootrom_gen.py
//
// A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
//
// Contributors
//
// David Flynn (d.w.flynn@soton.ac.uk)
// David Mapstone (d.a.mapstone@soton.ac.uk)
//    Date:    (omitted for reproducible builds)
// Copyright (c) 2021-5, SoC Labs (www.soclabs.org)
//------------------------------------------------------------------------------------
module nanosoc_bootrom_chip_core (
    input  logic clk,
    input  logic en,
    input  logic [11-1:0] word_addr,
    output logic [32-1:0] out_data
);

rom_via u_rom_via(
    .CLK(clk),
    .CEN(~en),
    .A(word_addr),
    .Q(out_data),
    // Tie offs
    .EMA(3'b010),
    .TEN(1'b1),
    .BEN(1'b1),
    .TCEN(1'b0),
    .TA(11'd0),
    .TQ(32'd0),
    .PGEN(1'b0),
    .KEN(1'b1),
    //unconnected
    .CENY(),
    .AY()
);

endmodule
