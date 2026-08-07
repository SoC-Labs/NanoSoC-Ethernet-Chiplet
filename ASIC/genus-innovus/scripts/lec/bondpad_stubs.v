//-----------------------------------------------------------------------------
// bondpad_stubs.v -- empty module declarations for the TSMC bond-pad cells
// A joint work commissioned on behalf of SoC Labs, under Arm Academic
// Access license.
//
// Copyright (C) 2026, SoC Labs (www.soclabs.org)
//-----------------------------------------------------------------------------
// PAD70GU / PAD70NU are the staggered bond-pad cells that
// scripts/place_bondpads.tcl instantiates with `create_inst -cell PAD70GU ...`
// during 4_pnr_route. They appear in outputs/<block>_pnr.v (42 + 40 = 82
// instances) and in NEITHER synthesis netlist -- P&R created them.
//
// They are PHYSICAL-ONLY cells. Innovus writes them with an empty connection
// list:
//     PAD70GU BuPAD_HOST_IO_5 ();
// and they carry no logic: they are the RDL/bond openings that the IO driver
// cells (PDDW*/PVDD*/PVSS*) connect up to through the pad ring geometry.
//
// They exist in the LEF (tpbn65v_9lm.lef) only. There is NO liberty and NO
// Verilog model for them anywhere in this PDK install -- verified: no .lib file
// exists under $TSMC_65_HOME/iolib at all, and PAD70GU is absent from
// tphn65lpgv2od3_slwc.lib. So Conformal cannot be given a model, only a
// declaration.
//
// `set_undefined_cell black_box` in pnr_lec.do would blackbox them implicitly,
// but implicit blackboxing is indistinguishable in the log from a cell we
// FORGOT to give a library for -- which is exactly the failure mode this whole
// exercise exists to stop. Declaring them here makes the intent explicit and
// keeps report_black_box readable: anything blackboxed that is NOT one of
// these two and not a memory macro is a setup bug.
//
// Zero ports means zero key points, so these contribute nothing to the compare
// either way. That is correct: there is nothing here for LEC to verify. Bond
// pads are LVS/DRC scope, not logical-equivalence scope.
//-----------------------------------------------------------------------------

module PAD70GU ();
endmodule

module PAD70NU ();
endmodule
