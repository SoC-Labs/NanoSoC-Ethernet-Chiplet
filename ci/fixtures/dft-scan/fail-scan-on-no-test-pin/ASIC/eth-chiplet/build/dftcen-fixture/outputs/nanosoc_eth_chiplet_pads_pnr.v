// -----------------------------------------------------------------------------
// FIXTURE -- not a build product. See ci/fixtures/dft-scan/README.md.
//
// Derived from the real post-route (Innovus) netlist of run rc5vt-20260829
//   ASIC/eth-chiplet/build/rc5vt-20260829/outputs/nanosoc_eth_chiplet_pads_pnr.v
// by extracting 290 integrated clock gates verbatim: each one's wrapper module
// definition and its instantiation, exactly as the netlist writer emitted them,
// line wrapping included. The other 2717 gates and everything that is not a
// clock gate are elided.
//
// WHY 290 AND NOT 3007. dft_icg_census.py refuses a netlist under 100 kB as
// too small to be a real one -- a guard against grading a truncated synthesis.
// 290 verbatim gates is the smallest extract that clears that floor.
//
// MUTATION APPLIED HERE: NONE. Verbatim extract; this is the netlist shape the census must read correctly.
// -----------------------------------------------------------------------------
module cg_RC_CG_MOD_271_16035 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD4 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_272_16036 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD4 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_273_16037 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;
   wire FE_OFN10254_n_293;
   wire FE_OFN10253_n_293;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKND1 FE_OFC10254_n_293 (.I(FE_OFN10253_n_293),
	.ZN(FE_OFN10254_n_293));
   CKND1 FE_OFC10253_n_293 (.I(enable),
	.ZN(FE_OFN10253_n_293));
   CKLNQD2 RC_CGIC_INST (.CP(ck_in),
	.E(FE_OFN10254_n_293),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_274_16038 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD2 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_275_16039 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD2 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_276_16040 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD1 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_277_16042 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD2 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_278_16043 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD2 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_279_16045 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD2 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_280_16047 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD6 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_281_16049 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD2 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_282_16051 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD2 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_283_16053 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD2 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_284_16054 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD2 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_285_16055 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD2 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_286_16057 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD2 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_287_16058 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD2 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_288_16062 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD4 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_289_16063 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD2 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_290_16064 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD1 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_292_16069 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD4 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_293_16070 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire FE_OFN195_n_105;
   wire LTIE_PD_TOP_LTIELO_NET;

   BUFFD1 FE_OFC195_n_105 (.I(enable),
	.Z(FE_OFN195_n_105));
   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD4 RC_CGIC_INST (.CP(ck_in),
	.E(FE_OFN195_n_105),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_294_16075 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD16 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_295_16076 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_296_16077 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_297_16078 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_298_16079 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_299_16080 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_300_16081 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD6 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_301_16082 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD6 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_302_16083 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD6 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_303_16084 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD6 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_304_16085 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD6 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_305_16086 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD6 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_306_16087 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD6 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_307_16088 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD6 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_308_16089 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD6 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_309_16090 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD16 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_310_16091 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD6 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_311_16092 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD6 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_312_16093 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD6 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_313_16094 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD6 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_314_16095 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_315_16096 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD1 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_322_16099 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD16 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_323_16100 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD16 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_324_16101 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD16 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_325_16102 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_326_16103 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD12 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_327_16104 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_328_16105 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_329_16106 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD16 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_330_16107 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD16 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_331_16108 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_332_16109 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD6 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_333_16110 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD2 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_334_16111 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD2 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_335_16112 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire FE_OFN261_n_431;
   wire LTIE_PD_TOP_LTIELO_NET;

   CKBD0 FE_OFC261_n_431 (.I(enable),
	.Z(FE_OFN261_n_431));
   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD2 RC_CGIC_INST (.CP(ck_in),
	.E(FE_OFN261_n_431),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_336_16113 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD2 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_337_16114 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;
   wire FE_OFN13699_n_445;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   BUFFD1 FE_OFC13699_n_445 (.I(enable),
	.Z(FE_OFN13699_n_445));
   CKLNQD2 RC_CGIC_INST (.CP(ck_in),
	.E(FE_OFN13699_n_445),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_338_16115 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD2 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_339_16116 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD1 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_340_16120 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD6 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_341_16121 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD6 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_342_16122 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD6 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_343_16123 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD6 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_354_16136 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD6 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_355_16137 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD4 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_356_16138 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD6 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_357_16139 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD3 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_358_16140 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD3 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_359_16141 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD2 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_360_16142 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD4 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_361_16143 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD2 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_362_16144 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD3 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_363_16145 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD2 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_364_16146 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD3 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_365_16147 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD1 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_366_16149 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_367_16150 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD12 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_368 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_369 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_370 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_371 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_372 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_373 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD6 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_374 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_375 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_376 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_377 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_378 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_379 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_380 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD16 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_381 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD6 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_382 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_383 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_384 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire FE_OFN140388_n;
   wire LTIE_PD_TOP_LTIELO_NET;

   CKBD1 FE_OFC2003_n_1389 (.I(enable),
	.Z(FE_OFN140388_n));
   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD16 RC_CGIC_INST (.CP(ck_in),
	.E(FE_OFN140388_n),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_385 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_386 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_387 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_388 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_389 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_390 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_391 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_392 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_393 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_394 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_395 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_396 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_397 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD6 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_398 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_399 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_400 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_401 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD6 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_402 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD16 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_403 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_404 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_405 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_406 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;
   wire FE_OFN5432_n_1394;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKND1 FE_OFC5432_n_1394 (.I(enable),
	.ZN(FE_OFN5432_n_1394));
   CKLNQD16 RC_CGIC_INST (.CP(ck_in),
	.E(FE_OFN5432_n_1394),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_407 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_408 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_409 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_410 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD16 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_411 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_412 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_413 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD12 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_414 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD16 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_415 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_416 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_417 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_418 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;
   wire FE_OFN5437_n_1397;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   BUFFD2 FE_OFC5437_n_1397 (.I(enable),
	.Z(FE_OFN5437_n_1397));
   CKLNQD16 RC_CGIC_INST (.CP(ck_in),
	.E(FE_OFN5437_n_1397),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_419 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_420 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_421 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_422 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;
   wire FE_OFN5442_n_1398;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   INVD2 FE_OFC5442_n_1398 (.I(enable),
	.ZN(FE_OFN5442_n_1398));
   CKLNQD16 RC_CGIC_INST (.CP(ck_in),
	.E(FE_OFN5442_n_1398),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_423 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_424 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_425 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_426 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_427 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD12 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_428 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_429 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_430 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD2 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_441 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD4 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_442 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD4 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_443 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD6 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_444 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD3 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_445 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD3 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_446 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD3 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_447 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD4 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_448 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD2 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_449 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD2 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_450 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD2 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_451 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD3 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_452 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD1 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_453 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD16 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_454 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_455 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_456 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_457 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD6 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_458 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_459 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD16 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_460 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_461 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_462 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_463 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD16 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_464 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_465 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_466 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_467 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD16 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_468 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_469 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_470 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD16 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_471 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;
   wire FE_OFN5504_n_1388;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKND2 FE_OFC5504_n_1388 (.I(enable),
	.ZN(FE_OFN5504_n_1388));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(FE_OFN5504_n_1388),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_472 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_473 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_474 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD16 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_475 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD16 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_476 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_477 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_478 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD16 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_479 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_480 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_481 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_482 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD16 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_483 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD12 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_484 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_485 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_486 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD12 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_487 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD12 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_488 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_489 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_490 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_491 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD12 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_492 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_493 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_494 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_495 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD16 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_496 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_497 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD12 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_498 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_499 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_500 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_501 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD16 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_502 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_503 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_504 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_505 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD12 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_506 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_507 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_508 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_509 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_510 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_511 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_512 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_513 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD16 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_514 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD16 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_515 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_516 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_517 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD1 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_316_16155 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD1 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_317_16157 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD1 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_318_16160 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD3 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_319_16162 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD2 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_321_16168 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD1 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_15758 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_1_15759 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD16 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_2_15760 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD1 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_3_15761 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD1 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_4_15762 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD6 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_5_15763 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD6 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_6_15764 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD6 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_7_15765 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD6 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_8_15766 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD6 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_9_15767 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD2 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_10_15768 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD16 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_11_15769 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD1 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_12_15770 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD6 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_13_15771 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD6 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_14_15772 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD6 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_15_15773 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire CTS_1;
   wire LTIE_PD_TOP_LTIELO_NET;

   CKBD0 CTS_cdb_buf_01302 (.I(ck_in),
	.Z(CTS_1));
   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD1 RC_CGIC_INST (.CP(CTS_1),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_16_15774 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD16 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_17_15775 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD6 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_18_15776 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD16 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_19_15777 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD16 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_20_15778 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD16 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_21_15779 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD16 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_22_15780 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD16 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_23_15781 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD16 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_24_15782 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD16 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_25_15783 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD16 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_26_15784 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD16 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_27_15785 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire FE_PHN54089_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_148;
   wire FE_PHN51051_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_148;
   wire FE_PHN37082_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_148;
   wire LTIE_PD_TOP_LTIELO_NET;

   CKBD1 FE_PHC54089_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_148 (.I(FE_PHN51051_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_148),
	.Z(FE_PHN54089_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_148));
   CKBD16 FE_PHC51051_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_148 (.I(FE_PHN37082_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_148),
	.Z(FE_PHN51051_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_148));
   CKBD0 FE_PHC37082_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_148 (.I(enable),
	.Z(FE_PHN37082_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_148));
   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD3 RC_CGIC_INST (.CP(ck_in),
	.E(FE_PHN54089_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_148),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_28_15786 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire FE_PHN47880_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_144;
   wire FE_PHN37261_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_144;
   wire LTIE_PD_TOP_LTIELO_NET;

   CKBD16 FE_PHC47880_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_144 (.I(FE_PHN37261_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_144),
	.Z(FE_PHN47880_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_144));
   BUFFD1 FE_PHC37261_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_144 (.I(enable),
	.Z(FE_PHN37261_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_144));
   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD3 RC_CGIC_INST (.CP(ck_in),
	.E(FE_PHN47880_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_144),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_29_15787 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD16 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_30_15788 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD16 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_31_15789 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD12 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_32_15790 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD16 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_33_15791 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD16 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_34_15792 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD16 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_35_15793 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD16 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_36_15794 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire FE_PHN47870_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_141;
   wire FE_PHN37242_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_141;
   wire LTIE_PD_TOP_LTIELO_NET;

   BUFFD4 FE_PHC47870_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_141 (.I(FE_PHN37242_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_141),
	.Z(FE_PHN47870_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_141));
   CKBD0 FE_PHC37242_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_141 (.I(enable),
	.Z(FE_PHN37242_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_141));
   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD3 RC_CGIC_INST (.CP(ck_in),
	.E(FE_PHN47870_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_141),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_37_15795 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire FE_PHN47869_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_138;
   wire FE_PHN37243_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_138;
   wire LTIE_PD_TOP_LTIELO_NET;

   BUFFD4 FE_PHC47869_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_138 (.I(FE_PHN37243_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_138),
	.Z(FE_PHN47869_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_138));
   CKBD0 FE_PHC37243_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_138 (.I(enable),
	.Z(FE_PHN37243_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_138));
   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD3 RC_CGIC_INST (.CP(ck_in),
	.E(FE_PHN47869_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_138),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_38_15796 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire FE_PHN47865_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_135;
   wire FE_PHN37369_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_135;
   wire LTIE_PD_TOP_LTIELO_NET;

   CKBD0 FE_PHC47865_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_135 (.I(FE_PHN37369_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_135),
	.Z(FE_PHN47865_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_135));
   CKBD0 FE_PHC37369_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_135 (.I(enable),
	.Z(FE_PHN37369_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_135));
   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD3 RC_CGIC_INST (.CP(ck_in),
	.E(FE_PHN47865_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_135),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_39_15797 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire FE_PHN47866_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_132;
   wire FE_PHN37395_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_132;
   wire LTIE_PD_TOP_LTIELO_NET;

   CKBD0 FE_PHC47866_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_132 (.I(FE_PHN37395_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_132),
	.Z(FE_PHN47866_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_132));
   BUFFD4 FE_PHC37395_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_132 (.I(enable),
	.Z(FE_PHN37395_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_132));
   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD2 RC_CGIC_INST (.CP(ck_in),
	.E(FE_PHN47866_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_132),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_40_15798 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire FE_PHN47856_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_129;
   wire FE_PHN37371_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_129;
   wire CTS_2;
   wire CTS_1;
   wire LTIE_PD_TOP_LTIELO_NET;

   CKBD1 FE_PHC47856_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_129 (.I(FE_PHN37371_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_129),
	.Z(FE_PHN47856_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_129));
   CKBD0 FE_PHC37371_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_129 (.I(enable),
	.Z(FE_PHN37371_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_129));
   DEL0 CTS_cdb_buf_01713 (.I(CTS_2),
	.Z(CTS_1));
   CKBD0 CTS_cdb_buf_01712 (.I(ck_in),
	.Z(CTS_2));
   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD6 RC_CGIC_INST (.CP(CTS_1),
	.E(FE_PHN47856_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_129),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_41_15799 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire FE_PHN47873_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_126;
   wire FE_PHN37303_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_126;
   wire LTIE_PD_TOP_LTIELO_NET;

   CKBD16 FE_PHC47873_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_126 (.I(FE_PHN37303_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_126),
	.Z(FE_PHN47873_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_126));
   CKBD0 FE_PHC37303_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_126 (.I(enable),
	.Z(FE_PHN37303_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_126));
   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD2 RC_CGIC_INST (.CP(ck_in),
	.E(FE_PHN47873_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_126),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_42_15800 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire CTS_1;
   wire LTIE_PD_TOP_LTIELO_NET;

   DEL0 CTS_cdb_buf_01706 (.I(ck_in),
	.Z(CTS_1));
   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD3 RC_CGIC_INST (.CP(CTS_1),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_43_15801 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire FE_PHN52282_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_120;
   wire FE_PHN51035_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_120;
   wire FE_PHN37062_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_120;
   wire LTIE_PD_TOP_LTIELO_NET;

   BUFFD4 FE_PHC52282_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_120 (.I(FE_PHN37062_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_120),
	.Z(FE_PHN52282_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_120));
   CKBD0 FE_PHC51035_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_120 (.I(FE_PHN52282_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_120),
	.Z(FE_PHN51035_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_120));
   CKBD0 FE_PHC37062_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_120 (.I(enable),
	.Z(FE_PHN37062_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_120));
   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD3 RC_CGIC_INST (.CP(ck_in),
	.E(FE_PHN51035_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_120),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_44_15802 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire FE_PHN52274_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_117;
   wire FE_PHN51031_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_117;
   wire FE_PHN47936_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_117;
   wire LTIE_PD_TOP_LTIELO_NET;

   CKBD0 FE_PHC52274_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_117 (.I(FE_PHN51031_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_117),
	.Z(FE_PHN52274_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_117));
   CKBD0 FE_PHC51031_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_117 (.I(FE_PHN47936_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_117),
	.Z(FE_PHN51031_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_117));
   CKBD0 FE_PHC47936_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_117 (.I(enable),
	.Z(FE_PHN47936_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_117));
   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD3 RC_CGIC_INST (.CP(ck_in),
	.E(FE_PHN52274_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_117),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_45_15803 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire FE_PHN50982_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_114;
   wire FE_PHN37050_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_114;
   wire LTIE_PD_TOP_LTIELO_NET;

   BUFFD4 FE_PHC50982_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_114 (.I(FE_PHN37050_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_114),
	.Z(FE_PHN50982_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_114));
   CKBD0 FE_PHC37050_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_114 (.I(enable),
	.Z(FE_PHN37050_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_114));
   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD3 RC_CGIC_INST (.CP(ck_in),
	.E(FE_PHN50982_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_114),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_46_15804 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire CTS_1;
   wire LTIE_PD_TOP_LTIELO_NET;

   DEL0 CTS_cdb_buf_01705 (.I(ck_in),
	.Z(CTS_1));
   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD3 RC_CGIC_INST (.CP(CTS_1),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_47_15805 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire CTS_1;
   wire LTIE_PD_TOP_LTIELO_NET;

   DEL0 CTS_cdb_buf_01704 (.I(ck_in),
	.Z(CTS_1));
   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD3 RC_CGIC_INST (.CP(CTS_1),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_48_15806 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire FE_PHN51013_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_105;
   wire FE_PHN47919_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_105;
   wire FE_PHN37068_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_105;
   wire LTIE_PD_TOP_LTIELO_NET;

   CKBD16 FE_PHC51013_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_105 (.I(FE_PHN47919_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_105),
	.Z(FE_PHN51013_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_105));
   CKBD0 FE_PHC47919_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_105 (.I(FE_PHN37068_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_105),
	.Z(FE_PHN47919_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_105));
   CKBD0 FE_PHC37068_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_105 (.I(enable),
	.Z(FE_PHN37068_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_105));
   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD4 RC_CGIC_INST (.CP(ck_in),
	.E(FE_PHN51013_u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_105),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_49_15807 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire CTS_1;
   wire LTIE_PD_TOP_LTIELO_NET;

   DEL0 CTS_cdb_buf_01703 (.I(ck_in),
	.Z(CTS_1));
   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD3 RC_CGIC_INST (.CP(CTS_1),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_50_15808 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD16 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_51_15809 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD16 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_52_15810 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD16 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_53_15811 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD16 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_54_15812 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_55_15813 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_56_15814 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD16 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_57_15815 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD16 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_58_15816 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD16 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_59_15817 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD16 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_60_15818 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD16 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_61_15819 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD16 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_62_15820 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD16 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_63_15821 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD8 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule
module cg_RC_CG_MOD_64_15822 (
	enable, 
	ck_in, 
	ck_out, 
	test, 
	VDD, 
	VSS);
   input enable;
   input ck_in;
   output ck_out;
   input test;
   inout VDD;
   inout VSS;

   // Internal wires
   wire LTIE_PD_TOP_LTIELO_NET;

   TIEL LTIE_PD_TOP_LTIELO (.ZN(LTIE_PD_TOP_LTIELO_NET));
   CKLNQD16 RC_CGIC_INST (.CP(ck_in),
	.E(enable),
	.Q(ck_out),
	.TE(LTIE_PD_TOP_LTIELO_NET),
	.VSS(VSS),
	.VDD(VDD));
endmodule

module nanosoc_eth_chiplet_pads (VDD, VSS);
   inout VDD;
   inout VSS;
   cg_RC_CG_MOD_271_16035 cg_RC_CG_HIER_INST271 (.enable(n_356),
	.ck_in(MRxClk_clone2),
	.ck_out(cg_rc_gclk),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_272_16036 cg_RC_CG_HIER_INST272 (.enable(n_350),
	.ck_in(MRxClk_clone2),
	.ck_out(cg_rc_gclk_1470),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_273_16037 cg_RC_CG_HIER_INST273 (.enable(n_293),
	.ck_in(MRxClk_clone2),
	.ck_out(cg_rc_gclk_1473),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_274_16038 cg_RC_CG_HIER_INST274 (.enable(n_292),
	.ck_in(MRxClk_clone2),
	.ck_out(cg_rc_gclk_1476),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_275_16039 cg_RC_CG_HIER_INST275 (.enable(n_291),
	.ck_in(MRxClk_clone2),
	.ck_out(cg_rc_gclk_1479),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_276_16040 cg_RC_CG_HIER_INST276 (.enable(n_290),
	.ck_in(MRxClk_clone2),
	.ck_out(cg_rc_gclk_1482),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_277_16042 cg_RC_CG_HIER_INST277 (.enable(n_142),
	.ck_in(MTxClk_clone1),
	.ck_out(cg_rc_gclk),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_278_16043 cg_RC_CG_HIER_INST278 (.enable(n_143),
	.ck_in(MTxClk_clone1),
	.ck_out(cg_rc_gclk_970),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_279_16045 cg_RC_CG_HIER_INST279 (.enable(n_2575),
	.ck_in(MTxClk),
	.ck_out(cg_rc_gclk),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_280_16047 cg_RC_CG_HIER_INST280 (.enable(n_128),
	.ck_in(Clk_clone2),
	.ck_out(cg_rc_gclk),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_281_16049 clkgen_cg_RC_CG_HIER_INST281 (.enable(clkgen_n_187),
	.ck_in(Clk_clone2),
	.ck_out(clkgen_cg_rc_gclk),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_282_16051 outctrl_cg_RC_CG_HIER_INST282 (.enable(MdcEn_n),
	.ck_in(Clk_clone2),
	.ck_out(outctrl_cg_rc_gclk),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_283_16053 shftrg_cg_RC_CG_HIER_INST283 (.enable(n_129),
	.ck_in(Clk_clone1),
	.ck_out(shftrg_cg_rc_gclk),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_284_16054 shftrg_cg_RC_CG_HIER_INST284 (.enable(shftrg_n_107),
	.ck_in(Clk_clone1),
	.ck_out(shftrg_cg_rc_gclk_467),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_285_16055 shftrg_cg_RC_CG_HIER_INST285 (.enable(MdcEn_n),
	.ck_in(Clk_clone2),
	.ck_out(shftrg_cg_rc_gclk_469),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_286_16057 cg_RC_CG_HIER_INST286 (.enable(n_502),
	.ck_in(MRxClk_clone2),
	.ck_out(cg_rc_gclk),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_287_16058 cg_RC_CG_HIER_INST287 (.enable(n_500),
	.ck_in(MRxClk_clone2),
	.ck_out(cg_rc_gclk_678),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_288_16062 rxcounters1_cg_RC_CG_HIER_INST288 (.enable(rxcounters1_n_636),
	.ck_in(MRxClk_clone2),
	.ck_out(rxcounters1_cg_rc_gclk),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_289_16063 rxcounters1_cg_RC_CG_HIER_INST289 (.enable(rxcounters1_n_638),
	.ck_in(MRxClk_clone2),
	.ck_out(rxcounters1_cg_rc_gclk_640),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_290_16064 rxcounters1_cg_RC_CG_HIER_INST290 (.enable(rxcounters1_n_641),
	.ck_in(MRxClk_clone2),
	.ck_out(rxcounters1_cg_rc_gclk_643),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_292_16069 cg_RC_CG_HIER_INST292 (.enable(n_219),
	.ck_in(MTxClk_clone1),
	.ck_out(cg_rc_gclk),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_293_16070 cg_RC_CG_HIER_INST293 (.enable(n_105),
	.ck_in(MTxClk_clone1),
	.ck_out(cg_rc_gclk_952),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_294_16075 cg_RC_CG_HIER_INST294 (.enable(n_723),
	.ck_in(CTS_2),
	.ck_out(cg_rc_gclk),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_295_16076 cg_RC_CG_HIER_INST295 (.enable(n_723),
	.ck_in(CTS_2),
	.ck_out(cg_rc_gclk_5814),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_296_16077 cg_RC_CG_HIER_INST296 (.enable(n_723),
	.ck_in(CTS_2),
	.ck_out(cg_rc_gclk_5816),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_297_16078 cg_RC_CG_HIER_INST297 (.enable(n_723),
	.ck_in(CTS_2),
	.ck_out(cg_rc_gclk_5818),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_298_16079 cg_RC_CG_HIER_INST298 (.enable(n_723),
	.ck_in(rtc_clk_clone8),
	.ck_out(cg_rc_gclk_5820),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_299_16080 cg_RC_CG_HIER_INST299 (.enable(state_next[2]),
	.ck_in(CTS_2),
	.ck_out(cg_rc_gclk_5822),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_300_16081 cg_RC_CG_HIER_INST300 (.enable(state_next[2]),
	.ck_in(CTS_2),
	.ck_out(cg_rc_gclk_5824),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_301_16082 cg_RC_CG_HIER_INST301 (.enable(state_next[2]),
	.ck_in(CTS_2),
	.ck_out(cg_rc_gclk_5826),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_302_16083 cg_RC_CG_HIER_INST302 (.enable(req_edge_rtc),
	.ck_in(CTS_2),
	.ck_out(cg_rc_gclk_5828),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_303_16084 cg_RC_CG_HIER_INST303 (.enable(req_edge_rtc),
	.ck_in(rtc_clk),
	.ck_out(cg_rc_gclk_5830),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_304_16085 cg_RC_CG_HIER_INST304 (.enable(req_edge_rtc),
	.ck_in(CTS_2),
	.ck_out(cg_rc_gclk_5832),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_305_16086 cg_RC_CG_HIER_INST305 (.enable(n_722),
	.ck_in(CTS_2),
	.ck_out(cg_rc_gclk_5834),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_306_16087 cg_RC_CG_HIER_INST306 (.enable(n_722),
	.ck_in(rtc_clk_clone8),
	.ck_out(cg_rc_gclk_5836),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_307_16088 cg_RC_CG_HIER_INST307 (.enable(n_722),
	.ck_in(rtc_clk_clone8),
	.ck_out(cg_rc_gclk_5838),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_308_16089 cg_RC_CG_HIER_INST308 (.enable(FE_OFN11246_n_584),
	.ck_in(rtc_clk_clone4),
	.ck_out(cg_rc_gclk_5840),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_309_16090 cg_RC_CG_HIER_INST309 (.enable(FE_OFN11246_n_584),
	.ck_in(rtc_clk_clone5),
	.ck_out(cg_rc_gclk_5842),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_310_16091 cg_RC_CG_HIER_INST310 (.enable(n_584),
	.ck_in(rtc_clk_clone6),
	.ck_out(cg_rc_gclk_5844),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_311_16092 cg_RC_CG_HIER_INST311 (.enable(n_721),
	.ck_in(CTS_2),
	.ck_out(cg_rc_gclk_5846),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_312_16093 cg_RC_CG_HIER_INST312 (.enable(n_721),
	.ck_in(CTS_2),
	.ck_out(cg_rc_gclk_5848),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_313_16094 cg_RC_CG_HIER_INST313 (.enable(n_721),
	.ck_in(CTS_2),
	.ck_out(cg_rc_gclk_5850),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_314_16095 cg_RC_CG_HIER_INST314 (.enable(n_1017),
	.ck_in(CTS_2),
	.ck_out(cg_rc_gclk_5852),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_315_16096 cg_RC_CG_HIER_INST315 (.enable(n_741),
	.ck_in(CTS_2),
	.ck_out(cg_rc_gclk_5855),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_322_16099 cg_RC_CG_HIER_INST322 (.enable(n_457),
	.ck_in(rtc_clk_in_clone11),
	.ck_out(cg_rc_gclk),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_323_16100 cg_RC_CG_HIER_INST323 (.enable(n_457),
	.ck_in(rtc_clk_in_clone6),
	.ck_out(cg_rc_gclk_5936),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_324_16101 cg_RC_CG_HIER_INST324 (.enable(n_457),
	.ck_in(rtc_clk_in_clone6),
	.ck_out(cg_rc_gclk_5938),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_325_16102 cg_RC_CG_HIER_INST325 (.enable(n_464),
	.ck_in(rtc_clk_in_clone1),
	.ck_out(cg_rc_gclk_5940),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_326_16103 cg_RC_CG_HIER_INST326 (.enable(n_456),
	.ck_in(rtc_clk_in_clone1),
	.ck_out(cg_rc_gclk_5943),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_327_16104 cg_RC_CG_HIER_INST327 (.enable(n_455),
	.ck_in(rtc_clk_in_clone11),
	.ck_out(cg_rc_gclk_5946),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_328_16105 cg_RC_CG_HIER_INST328 (.enable(n_430),
	.ck_in(rtc_clk_in_clone11),
	.ck_out(cg_rc_gclk_5949),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_329_16106 cg_RC_CG_HIER_INST329 (.enable(n_453),
	.ck_in(rtc_clk_in_clone11),
	.ck_out(cg_rc_gclk_5952),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_330_16107 cg_RC_CG_HIER_INST330 (.enable(n_452),
	.ck_in(rtc_clk_in_clone6),
	.ck_out(cg_rc_gclk_5955),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_331_16108 cg_RC_CG_HIER_INST331 (.enable(n_451),
	.ck_in(rtc_clk_in_clone1),
	.ck_out(cg_rc_gclk_5958),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_332_16109 cg_RC_CG_HIER_INST332 (.enable(n_450),
	.ck_in(rtc_clk_in_clone1),
	.ck_out(cg_rc_gclk_5961),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_333_16110 cg_RC_CG_HIER_INST333 (.enable(n_449),
	.ck_in(rtc_clk_in_clone1),
	.ck_out(cg_rc_gclk_5964),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_334_16111 cg_RC_CG_HIER_INST334 (.enable(n_448),
	.ck_in(rtc_clk_in_clone10),
	.ck_out(cg_rc_gclk_5967),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_335_16112 cg_RC_CG_HIER_INST335 (.enable(n_431),
	.ck_in(rtc_clk_in_clone1),
	.ck_out(cg_rc_gclk_5970),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_336_16113 cg_RC_CG_HIER_INST336 (.enable(n_446),
	.ck_in(rtc_clk_in_clone11),
	.ck_out(cg_rc_gclk_5973),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_337_16114 cg_RC_CG_HIER_INST337 (.enable(n_445),
	.ck_in(rtc_clk_in_clone11),
	.ck_out(cg_rc_gclk_5976),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_338_16115 cg_RC_CG_HIER_INST338 (.enable(n_444),
	.ck_in(rtc_clk_in_clone10),
	.ck_out(cg_rc_gclk_5979),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_339_16116 cg_RC_CG_HIER_INST339 (.enable(n_443),
	.ck_in(rtc_clk_in_clone10),
	.ck_out(cg_rc_gclk_5982),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_340_16120 cg_RC_CG_HIER_INST340 (.enable(n_614),
	.ck_in(clk_clone2),
	.ck_out(cg_rc_gclk),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_341_16121 cg_RC_CG_HIER_INST341 (.enable(n_614),
	.ck_in(clk_clone2),
	.ck_out(cg_rc_gclk_4547),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_342_16122 cg_RC_CG_HIER_INST342 (.enable(period_ld),
	.ck_in(clk_clone8),
	.ck_out(cg_rc_gclk_4549),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_343_16123 cg_RC_CG_HIER_INST343 (.enable(period_ld),
	.ck_in(clk_clone8),
	.ck_out(cg_rc_gclk_4551),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_354_16136 cg_RC_CG_HIER_INST354 (.enable(n_461),
	.ck_in(clk_clone2),
	.ck_out(cg_rc_gclk),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_355_16137 cg_RC_CG_HIER_INST355 (.enable(n_461),
	.ck_in(clk_clone3),
	.ck_out(cg_rc_gclk_3084),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_356_16138 cg_RC_CG_HIER_INST356 (.enable(n_462),
	.ck_in(clk),
	.ck_out(cg_rc_gclk_3087),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_357_16139 cg_RC_CG_HIER_INST357 (.enable(n_482),
	.ck_in(clk_clone2),
	.ck_out(cg_rc_gclk_3090),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_358_16140 cg_RC_CG_HIER_INST358 (.enable(n_491),
	.ck_in(clk_clone2),
	.ck_out(cg_rc_gclk_3092),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_359_16141 cg_RC_CG_HIER_INST359 (.enable(n_492),
	.ck_in(clk),
	.ck_out(cg_rc_gclk_3094),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_360_16142 cg_RC_CG_HIER_INST360 (.enable(int_valid),
	.ck_in(clk),
	.ck_out(cg_rc_gclk_3096),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_361_16143 cg_RC_CG_HIER_INST361 (.enable(n_479),
	.ck_in(clk),
	.ck_out(cg_rc_gclk_3099),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_362_16144 cg_RC_CG_HIER_INST362 (.enable(n_478),
	.ck_in(clk),
	.ck_out(cg_rc_gclk_3102),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_363_16145 cg_RC_CG_HIER_INST363 (.enable(n_477),
	.ck_in(clk),
	.ck_out(cg_rc_gclk_3105),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_364_16146 cg_RC_CG_HIER_INST364 (.enable(int_valid),
	.ck_in(clk),
	.ck_out(cg_rc_gclk_3108),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_365_16147 cg_RC_CG_HIER_INST365 (.enable(n_476),
	.ck_in(clk_clone2),
	.ck_out(cg_rc_gclk_3111),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_366_16149 cg_RC_CG_HIER_INST366 (.enable(n_1400),
	.ck_in(wrclk_clone1),
	.ck_out(cg_rc_gclk),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_367_16150 cg_RC_CG_HIER_INST367 (.enable(FE_OFN5445_n_1400),
	.ck_in(CTS_2),
	.ck_out(cg_rc_gclk_8606),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_368 cg_RC_CG_HIER_INST368 (.enable(FE_OFN5445_n_1400),
	.ck_in(CTS_2),
	.ck_out(cg_rc_gclk_8608),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_369 cg_RC_CG_HIER_INST369 (.enable(FE_OFN5445_n_1400),
	.ck_in(wrclk_clone3),
	.ck_out(cg_rc_gclk_8610),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_370 cg_RC_CG_HIER_INST370 (.enable(n_1266),
	.ck_in(wrclk),
	.ck_out(cg_rc_gclk_8612),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_371 cg_RC_CG_HIER_INST371 (.enable(FE_OFN8941_n_1266),
	.ck_in(wrclk_clone3),
	.ck_out(cg_rc_gclk_8614),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_372 cg_RC_CG_HIER_INST372 (.enable(FE_OFN8941_n_1266),
	.ck_in(CTS_2),
	.ck_out(cg_rc_gclk_8616),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_373 cg_RC_CG_HIER_INST373 (.enable(FE_OFN8941_n_1266),
	.ck_in(wrclk_clone3),
	.ck_out(cg_rc_gclk_8618),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_374 cg_RC_CG_HIER_INST374 (.enable(FE_OFN5425_n_1387),
	.ck_in(wrclk),
	.ck_out(cg_rc_gclk_8620),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_375 cg_RC_CG_HIER_INST375 (.enable(FE_OFN5425_n_1387),
	.ck_in(wrclk_clone3),
	.ck_out(cg_rc_gclk_8622),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_376 cg_RC_CG_HIER_INST376 (.enable(FE_OFN5425_n_1387),
	.ck_in(CTS_2),
	.ck_out(cg_rc_gclk_8624),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_377 cg_RC_CG_HIER_INST377 (.enable(FE_OFN5425_n_1387),
	.ck_in(wrclk_clone3),
	.ck_out(cg_rc_gclk_8626),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_378 cg_RC_CG_HIER_INST378 (.enable(FE_OFN5426_n_1388),
	.ck_in(wrclk),
	.ck_out(cg_rc_gclk_8628),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_379 cg_RC_CG_HIER_INST379 (.enable(FE_OFN5426_n_1388),
	.ck_in(CTS_2),
	.ck_out(cg_rc_gclk_8630),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_380 cg_RC_CG_HIER_INST380 (.enable(FE_OFN5426_n_1388),
	.ck_in(CTS_2),
	.ck_out(cg_rc_gclk_8632),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_381 cg_RC_CG_HIER_INST381 (.enable(FE_OFN5426_n_1388),
	.ck_in(wrclk_clone3),
	.ck_out(cg_rc_gclk_8634),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_382 cg_RC_CG_HIER_INST382 (.enable(FE_OFN5428_n_1389),
	.ck_in(wrclk),
	.ck_out(cg_rc_gclk_8636),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_383 cg_RC_CG_HIER_INST383 (.enable(FE_OFN5428_n_1389),
	.ck_in(wrclk_clone3),
	.ck_out(cg_rc_gclk_8638),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_384 cg_RC_CG_HIER_INST384 (.enable(FE_OFN5428_n_1389),
	.ck_in(CTS_2),
	.ck_out(cg_rc_gclk_8640),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_385 cg_RC_CG_HIER_INST385 (.enable(FE_OFN5428_n_1389),
	.ck_in(CTS_2),
	.ck_out(cg_rc_gclk_8642),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_386 cg_RC_CG_HIER_INST386 (.enable(n_1390),
	.ck_in(wrclk),
	.ck_out(cg_rc_gclk_8644),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_387 cg_RC_CG_HIER_INST387 (.enable(n_1390),
	.ck_in(wrclk_clone3),
	.ck_out(cg_rc_gclk_8646),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_388 cg_RC_CG_HIER_INST388 (.enable(n_1390),
	.ck_in(CTS_2),
	.ck_out(cg_rc_gclk_8648),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_389 cg_RC_CG_HIER_INST389 (.enable(n_1390),
	.ck_in(CTS_2),
	.ck_out(cg_rc_gclk_8650),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_390 cg_RC_CG_HIER_INST390 (.enable(FE_OFN5429_n_1391),
	.ck_in(wrclk_clone1),
	.ck_out(cg_rc_gclk_8652),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_391 cg_RC_CG_HIER_INST391 (.enable(FE_OFN5429_n_1391),
	.ck_in(wrclk_clone3),
	.ck_out(cg_rc_gclk_8654),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_392 cg_RC_CG_HIER_INST392 (.enable(FE_OFN5429_n_1391),
	.ck_in(CTS_2),
	.ck_out(cg_rc_gclk_8656),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_393 cg_RC_CG_HIER_INST393 (.enable(FE_OFN5429_n_1391),
	.ck_in(CTS_2),
	.ck_out(cg_rc_gclk_8658),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_394 cg_RC_CG_HIER_INST394 (.enable(n_1392),
	.ck_in(wrclk_clone1),
	.ck_out(cg_rc_gclk_8660),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_395 cg_RC_CG_HIER_INST395 (.enable(n_1392),
	.ck_in(CTS_2),
	.ck_out(cg_rc_gclk_8662),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_396 cg_RC_CG_HIER_INST396 (.enable(n_1392),
	.ck_in(CTS_2),
	.ck_out(cg_rc_gclk_8664),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_397 cg_RC_CG_HIER_INST397 (.enable(n_1392),
	.ck_in(wrclk_clone3),
	.ck_out(cg_rc_gclk_8666),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_398 cg_RC_CG_HIER_INST398 (.enable(n_1393),
	.ck_in(wrclk_clone1),
	.ck_out(cg_rc_gclk_8668),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_399 cg_RC_CG_HIER_INST399 (.enable(n_1393),
	.ck_in(wrclk_clone3),
	.ck_out(cg_rc_gclk_8670),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_400 cg_RC_CG_HIER_INST400 (.enable(n_1393),
	.ck_in(CTS_2),
	.ck_out(cg_rc_gclk_8672),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_401 cg_RC_CG_HIER_INST401 (.enable(n_1393),
	.ck_in(wrclk_clone3),
	.ck_out(cg_rc_gclk_8674),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_402 cg_RC_CG_HIER_INST402 (.enable(n_1265),
	.ck_in(wrclk_clone1),
	.ck_out(cg_rc_gclk_8676),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_403 cg_RC_CG_HIER_INST403 (.enable(n_1265),
	.ck_in(wrclk_clone3),
	.ck_out(cg_rc_gclk_8678),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_404 cg_RC_CG_HIER_INST404 (.enable(n_1265),
	.ck_in(CTS_2),
	.ck_out(cg_rc_gclk_8680),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_405 cg_RC_CG_HIER_INST405 (.enable(n_1265),
	.ck_in(wrclk_clone3),
	.ck_out(cg_rc_gclk_8682),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_406 cg_RC_CG_HIER_INST406 (.enable(FE_OFN5430_n_1394),
	.ck_in(wrclk_clone1),
	.ck_out(cg_rc_gclk_8684),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_407 cg_RC_CG_HIER_INST407 (.enable(FE_OFN5431_n_1394),
	.ck_in(wrclk_clone3),
	.ck_out(cg_rc_gclk_8686),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_408 cg_RC_CG_HIER_INST408 (.enable(FE_OFN5431_n_1394),
	.ck_in(CTS_2),
	.ck_out(cg_rc_gclk_8688),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_409 cg_RC_CG_HIER_INST409 (.enable(FE_OFN5431_n_1394),
	.ck_in(CTS_2),
	.ck_out(cg_rc_gclk_8690),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_410 cg_RC_CG_HIER_INST410 (.enable(n_1395),
	.ck_in(wrclk_clone1),
	.ck_out(cg_rc_gclk_8692),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_411 cg_RC_CG_HIER_INST411 (.enable(FE_OFN5434_n_1395),
	.ck_in(wrclk_clone3),
	.ck_out(cg_rc_gclk_8694),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_412 cg_RC_CG_HIER_INST412 (.enable(FE_OFN5434_n_1395),
	.ck_in(CTS_2),
	.ck_out(cg_rc_gclk_8696),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_413 cg_RC_CG_HIER_INST413 (.enable(FE_OFN5434_n_1395),
	.ck_in(CTS_2),
	.ck_out(cg_rc_gclk_8698),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_414 cg_RC_CG_HIER_INST414 (.enable(n_1396),
	.ck_in(wrclk_clone1),
	.ck_out(cg_rc_gclk_8700),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_415 cg_RC_CG_HIER_INST415 (.enable(FE_OFN5436_n_1396),
	.ck_in(CTS_2),
	.ck_out(cg_rc_gclk_8702),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_416 cg_RC_CG_HIER_INST416 (.enable(FE_OFN5436_n_1396),
	.ck_in(wrclk_clone3),
	.ck_out(cg_rc_gclk_8704),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_417 cg_RC_CG_HIER_INST417 (.enable(FE_OFN5436_n_1396),
	.ck_in(CTS_2),
	.ck_out(cg_rc_gclk_8706),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_418 cg_RC_CG_HIER_INST418 (.enable(n_1397),
	.ck_in(wrclk_clone1),
	.ck_out(cg_rc_gclk_8708),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_419 cg_RC_CG_HIER_INST419 (.enable(FE_OFN5439_n_1397),
	.ck_in(CTS_2),
	.ck_out(cg_rc_gclk_8710),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_420 cg_RC_CG_HIER_INST420 (.enable(FE_OFN5439_n_1397),
	.ck_in(CTS_2),
	.ck_out(cg_rc_gclk_8712),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_421 cg_RC_CG_HIER_INST421 (.enable(FE_OFN5439_n_1397),
	.ck_in(wrclk_clone3),
	.ck_out(cg_rc_gclk_8714),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_422 cg_RC_CG_HIER_INST422 (.enable(FE_OFN5440_n_1398),
	.ck_in(wrclk_clone1),
	.ck_out(cg_rc_gclk_8716),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_423 cg_RC_CG_HIER_INST423 (.enable(FE_OFN141303_FE_OFN5441_n_1398),
	.ck_in(CTS_2),
	.ck_out(cg_rc_gclk_8718),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_424 cg_RC_CG_HIER_INST424 (.enable(FE_OFN141303_FE_OFN5441_n_1398),
	.ck_in(CTS_2),
	.ck_out(cg_rc_gclk_8720),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_425 cg_RC_CG_HIER_INST425 (.enable(FE_OFN141303_FE_OFN5441_n_1398),
	.ck_in(wrclk_clone3),
	.ck_out(cg_rc_gclk_8722),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_426 cg_RC_CG_HIER_INST426 (.enable(n_1399),
	.ck_in(wrclk_clone1),
	.ck_out(cg_rc_gclk_8724),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_427 cg_RC_CG_HIER_INST427 (.enable(FE_OFN142322_n_1399),
	.ck_in(CTS_2),
	.ck_out(cg_rc_gclk_8726),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_428 cg_RC_CG_HIER_INST428 (.enable(FE_OFN142322_n_1399),
	.ck_in(CTS_2),
	.ck_out(cg_rc_gclk_8728),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_429 cg_RC_CG_HIER_INST429 (.enable(FE_OFN142322_n_1399),
	.ck_in(wrclk_clone3),
	.ck_out(cg_rc_gclk_8730),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_430 cg_RC_CG_HIER_INST430 (.enable(n_1276),
	.ck_in(rdclk),
	.ck_out(cg_rc_gclk_8732),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_441 cg_RC_CG_HIER_INST441 (.enable(n_463),
	.ck_in(clk_clone2),
	.ck_out(cg_rc_gclk),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_442 cg_RC_CG_HIER_INST442 (.enable(n_463),
	.ck_in(clk),
	.ck_out(cg_rc_gclk_3084),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_443 cg_RC_CG_HIER_INST443 (.enable(n_464),
	.ck_in(clk_clone2),
	.ck_out(cg_rc_gclk_3087),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_444 cg_RC_CG_HIER_INST444 (.enable(n_484),
	.ck_in(clk_clone2),
	.ck_out(cg_rc_gclk_3090),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_445 cg_RC_CG_HIER_INST445 (.enable(n_493),
	.ck_in(clk_clone2),
	.ck_out(cg_rc_gclk_3092),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_446 cg_RC_CG_HIER_INST446 (.enable(n_494),
	.ck_in(clk_clone2),
	.ck_out(cg_rc_gclk_3094),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_447 cg_RC_CG_HIER_INST447 (.enable(int_valid),
	.ck_in(clk_clone2),
	.ck_out(cg_rc_gclk_3096),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_448 cg_RC_CG_HIER_INST448 (.enable(n_481),
	.ck_in(clk_clone2),
	.ck_out(cg_rc_gclk_3099),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_449 cg_RC_CG_HIER_INST449 (.enable(n_480),
	.ck_in(clk_clone2),
	.ck_out(cg_rc_gclk_3102),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_450 cg_RC_CG_HIER_INST450 (.enable(n_479),
	.ck_in(clk_clone2),
	.ck_out(cg_rc_gclk_3105),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_451 cg_RC_CG_HIER_INST451 (.enable(int_valid),
	.ck_in(clk_clone2),
	.ck_out(cg_rc_gclk_3108),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_452 cg_RC_CG_HIER_INST452 (.enable(n_478),
	.ck_in(clk_clone2),
	.ck_out(cg_rc_gclk_3111),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_453 cg_RC_CG_HIER_INST453 (.enable(n_1399),
	.ck_in(wrclk_clone3),
	.ck_out(cg_rc_gclk),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_454 cg_RC_CG_HIER_INST454 (.enable(n_1399),
	.ck_in(wrclk_clone3),
	.ck_out(cg_rc_gclk_8606),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_455 cg_RC_CG_HIER_INST455 (.enable(n_1399),
	.ck_in(wrclk_clone1),
	.ck_out(cg_rc_gclk_8608),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_456 cg_RC_CG_HIER_INST456 (.enable(n_1399),
	.ck_in(wrclk_clone2),
	.ck_out(cg_rc_gclk_8610),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_457 cg_RC_CG_HIER_INST457 (.enable(n_1265),
	.ck_in(wrclk_clone3),
	.ck_out(cg_rc_gclk_8612),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_458 cg_RC_CG_HIER_INST458 (.enable(n_1265),
	.ck_in(wrclk_clone3),
	.ck_out(cg_rc_gclk_8614),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_459 cg_RC_CG_HIER_INST459 (.enable(n_1265),
	.ck_in(wrclk_clone1),
	.ck_out(cg_rc_gclk_8616),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_460 cg_RC_CG_HIER_INST460 (.enable(n_1265),
	.ck_in(wrclk_clone2),
	.ck_out(cg_rc_gclk_8618),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_461 cg_RC_CG_HIER_INST461 (.enable(FE_OFN5499_n_1386),
	.ck_in(wrclk_clone3),
	.ck_out(cg_rc_gclk_8620),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_462 cg_RC_CG_HIER_INST462 (.enable(FE_OFN5499_n_1386),
	.ck_in(wrclk_clone2),
	.ck_out(cg_rc_gclk_8622),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_463 cg_RC_CG_HIER_INST463 (.enable(FE_OFN5499_n_1386),
	.ck_in(wrclk_clone1),
	.ck_out(cg_rc_gclk_8624),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_464 cg_RC_CG_HIER_INST464 (.enable(FE_OFN5499_n_1386),
	.ck_in(wrclk_clone2),
	.ck_out(cg_rc_gclk_8626),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_465 cg_RC_CG_HIER_INST465 (.enable(FE_OFN5501_n_1387),
	.ck_in(wrclk_clone3),
	.ck_out(cg_rc_gclk_8628),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_466 cg_RC_CG_HIER_INST466 (.enable(FE_OFN5501_n_1387),
	.ck_in(wrclk_clone3),
	.ck_out(cg_rc_gclk_8630),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_467 cg_RC_CG_HIER_INST467 (.enable(FE_OFN5501_n_1387),
	.ck_in(wrclk_clone1),
	.ck_out(cg_rc_gclk_8632),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_468 cg_RC_CG_HIER_INST468 (.enable(FE_OFN5501_n_1387),
	.ck_in(wrclk_clone2),
	.ck_out(cg_rc_gclk_8634),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_469 cg_RC_CG_HIER_INST469 (.enable(FE_OFN5505_n_1388),
	.ck_in(wrclk_clone3),
	.ck_out(cg_rc_gclk_8636),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_470 cg_RC_CG_HIER_INST470 (.enable(FE_OFN5505_n_1388),
	.ck_in(wrclk_clone2),
	.ck_out(cg_rc_gclk_8638),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_471 cg_RC_CG_HIER_INST471 (.enable(FE_OFN5503_n_1388),
	.ck_in(wrclk_clone1),
	.ck_out(cg_rc_gclk_8640),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_472 cg_RC_CG_HIER_INST472 (.enable(FE_OFN5505_n_1388),
	.ck_in(wrclk_clone2),
	.ck_out(cg_rc_gclk_8642),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_473 cg_RC_CG_HIER_INST473 (.enable(n_1389),
	.ck_in(wrclk_clone3),
	.ck_out(cg_rc_gclk_8644),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_474 cg_RC_CG_HIER_INST474 (.enable(n_1389),
	.ck_in(wrclk_clone2),
	.ck_out(cg_rc_gclk_8646),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_475 cg_RC_CG_HIER_INST475 (.enable(n_1389),
	.ck_in(wrclk_clone1),
	.ck_out(cg_rc_gclk_8648),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_476 cg_RC_CG_HIER_INST476 (.enable(n_1389),
	.ck_in(wrclk_clone2),
	.ck_out(cg_rc_gclk_8650),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_477 cg_RC_CG_HIER_INST477 (.enable(FE_OFN5508_n_1390),
	.ck_in(wrclk_clone3),
	.ck_out(cg_rc_gclk_8652),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_478 cg_RC_CG_HIER_INST478 (.enable(FE_OFN5508_n_1390),
	.ck_in(wrclk_clone3),
	.ck_out(cg_rc_gclk_8654),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_479 cg_RC_CG_HIER_INST479 (.enable(FE_OFN5508_n_1390),
	.ck_in(wrclk_clone1),
	.ck_out(cg_rc_gclk_8656),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_480 cg_RC_CG_HIER_INST480 (.enable(FE_OFN5508_n_1390),
	.ck_in(wrclk_clone2),
	.ck_out(cg_rc_gclk_8658),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_481 cg_RC_CG_HIER_INST481 (.enable(n_1391),
	.ck_in(wrclk_clone3),
	.ck_out(cg_rc_gclk_8660),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_482 cg_RC_CG_HIER_INST482 (.enable(n_1391),
	.ck_in(wrclk_clone3),
	.ck_out(cg_rc_gclk_8662),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_483 cg_RC_CG_HIER_INST483 (.enable(n_1391),
	.ck_in(wrclk_clone1),
	.ck_out(cg_rc_gclk_8664),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_484 cg_RC_CG_HIER_INST484 (.enable(n_1391),
	.ck_in(wrclk_clone4),
	.ck_out(cg_rc_gclk_8666),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_485 cg_RC_CG_HIER_INST485 (.enable(n_1392),
	.ck_in(wrclk_clone3),
	.ck_out(cg_rc_gclk_8668),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_486 cg_RC_CG_HIER_INST486 (.enable(n_1392),
	.ck_in(wrclk_clone3),
	.ck_out(cg_rc_gclk_8670),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_487 cg_RC_CG_HIER_INST487 (.enable(n_1392),
	.ck_in(wrclk_clone1),
	.ck_out(cg_rc_gclk_8672),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_488 cg_RC_CG_HIER_INST488 (.enable(n_1392),
	.ck_in(wrclk_clone2),
	.ck_out(cg_rc_gclk_8674),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_489 cg_RC_CG_HIER_INST489 (.enable(n_1264),
	.ck_in(wrclk_clone3),
	.ck_out(cg_rc_gclk_8676),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_490 cg_RC_CG_HIER_INST490 (.enable(n_1264),
	.ck_in(wrclk_clone2),
	.ck_out(cg_rc_gclk_8678),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_491 cg_RC_CG_HIER_INST491 (.enable(n_1264),
	.ck_in(wrclk_clone1),
	.ck_out(cg_rc_gclk_8680),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_492 cg_RC_CG_HIER_INST492 (.enable(n_1264),
	.ck_in(wrclk_clone2),
	.ck_out(cg_rc_gclk_8682),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_493 cg_RC_CG_HIER_INST493 (.enable(FE_OFN5509_n_1393),
	.ck_in(wrclk_clone3),
	.ck_out(cg_rc_gclk_8684),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_494 cg_RC_CG_HIER_INST494 (.enable(FE_OFN5509_n_1393),
	.ck_in(wrclk_clone3),
	.ck_out(cg_rc_gclk_8686),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_495 cg_RC_CG_HIER_INST495 (.enable(FE_OFN5509_n_1393),
	.ck_in(wrclk_clone1),
	.ck_out(cg_rc_gclk_8688),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_496 cg_RC_CG_HIER_INST496 (.enable(FE_OFN5509_n_1393),
	.ck_in(wrclk_clone2),
	.ck_out(cg_rc_gclk_8690),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_497 cg_RC_CG_HIER_INST497 (.enable(n_1394),
	.ck_in(wrclk_clone3),
	.ck_out(cg_rc_gclk_8692),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_498 cg_RC_CG_HIER_INST498 (.enable(n_1394),
	.ck_in(wrclk_clone3),
	.ck_out(cg_rc_gclk_8694),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_499 cg_RC_CG_HIER_INST499 (.enable(n_1394),
	.ck_in(wrclk_clone1),
	.ck_out(cg_rc_gclk_8696),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_500 cg_RC_CG_HIER_INST500 (.enable(n_1394),
	.ck_in(wrclk_clone2),
	.ck_out(cg_rc_gclk_8698),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_501 cg_RC_CG_HIER_INST501 (.enable(n_1395),
	.ck_in(wrclk_clone3),
	.ck_out(cg_rc_gclk_8700),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_502 cg_RC_CG_HIER_INST502 (.enable(n_1395),
	.ck_in(wrclk_clone2),
	.ck_out(cg_rc_gclk_8702),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_503 cg_RC_CG_HIER_INST503 (.enable(n_1395),
	.ck_in(wrclk_clone1),
	.ck_out(cg_rc_gclk_8704),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_504 cg_RC_CG_HIER_INST504 (.enable(n_1395),
	.ck_in(wrclk_clone2),
	.ck_out(cg_rc_gclk_8706),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_505 cg_RC_CG_HIER_INST505 (.enable(FE_OFN5510_n_1396),
	.ck_in(wrclk_clone3),
	.ck_out(cg_rc_gclk_8708),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_506 cg_RC_CG_HIER_INST506 (.enable(FE_OFN5510_n_1396),
	.ck_in(wrclk_clone2),
	.ck_out(cg_rc_gclk_8710),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_507 cg_RC_CG_HIER_INST507 (.enable(FE_OFN5510_n_1396),
	.ck_in(wrclk_clone1),
	.ck_out(cg_rc_gclk_8712),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_508 cg_RC_CG_HIER_INST508 (.enable(FE_OFN5510_n_1396),
	.ck_in(wrclk_clone2),
	.ck_out(cg_rc_gclk_8714),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_509 cg_RC_CG_HIER_INST509 (.enable(FE_OFN5511_n_1397),
	.ck_in(wrclk_clone3),
	.ck_out(cg_rc_gclk_8716),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_510 cg_RC_CG_HIER_INST510 (.enable(FE_OFN5511_n_1397),
	.ck_in(wrclk_clone2),
	.ck_out(cg_rc_gclk_8718),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_511 cg_RC_CG_HIER_INST511 (.enable(FE_OFN5511_n_1397),
	.ck_in(wrclk_clone1),
	.ck_out(cg_rc_gclk_8720),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_512 cg_RC_CG_HIER_INST512 (.enable(FE_OFN5511_n_1397),
	.ck_in(wrclk_clone2),
	.ck_out(cg_rc_gclk_8722),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_513 cg_RC_CG_HIER_INST513 (.enable(n_1398),
	.ck_in(wrclk_clone3),
	.ck_out(cg_rc_gclk_8724),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_514 cg_RC_CG_HIER_INST514 (.enable(n_1398),
	.ck_in(wrclk_clone2),
	.ck_out(cg_rc_gclk_8726),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_515 cg_RC_CG_HIER_INST515 (.enable(n_1398),
	.ck_in(wrclk_clone1),
	.ck_out(cg_rc_gclk_8728),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_516 cg_RC_CG_HIER_INST516 (.enable(n_1398),
	.ck_in(wrclk_clone2),
	.ck_out(cg_rc_gclk_8730),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_517 cg_RC_CG_HIER_INST517 (.enable(n_1275),
	.ck_in(rdclk_clone1),
	.ck_out(cg_rc_gclk_8732),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_316_16155 cg_RC_CG_HIER_INST316 (.enable(n_56),
	.ck_in(clk),
	.ck_out(cg_rc_gclk),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_317_16157 cg_RC_CG_HIER_INST317 (.enable(n_57),
	.ck_in(clk),
	.ck_out(cg_rc_gclk),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_318_16160 cg_RC_CG_HIER_INST318 (.enable(n_50),
	.ck_in(dclk),
	.ck_out(cg_rc_gclk),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_319_16162 cg_RC_CG_HIER_INST319 (.enable(FE_OFN387_n),
	.ck_in(dclk),
	.ck_out(cg_rc_gclk),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_321_16168 cg_RC_CG_HIER_INST321 (.enable(FE_PHN53179_FE_OFN90_CTS_1),
	.ck_in(CTS_5),
	.ck_out(cg_rc_gclk),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_15758 cg_RC_CG_HIER_INST0 (.enable(n_16918),
	.ck_in(CTS_185),
	.ck_out(cg_rc_gclk),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_1_15759 cg_RC_CG_HIER_INST1 (.enable(n_16918),
	.ck_in(CTS_185),
	.ck_out(cg_rc_gclk_108885),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_2_15760 cg_RC_CG_HIER_INST2 (.enable(n_15880),
	.ck_in(rtc_clk_clone25),
	.ck_out(CTS_230),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_3_15761 cg_RC_CG_HIER_INST3 (.enable(n_15880),
	.ck_in(rtc_clk_clone26),
	.ck_out(CTS_228),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_4_15762 cg_RC_CG_HIER_INST4 (.enable(n_15879),
	.ck_in(CTS_170),
	.ck_out(cg_rc_gclk_108891),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_5_15763 cg_RC_CG_HIER_INST5 (.enable(n_15879),
	.ck_in(CTS_170),
	.ck_out(cg_rc_gclk_108893),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_6_15764 cg_RC_CG_HIER_INST6 (.enable(u_ethmac_0_u_inner_u_eth_top_wishbone_n_3997),
	.ck_in(CTS_168),
	.ck_out(cg_rc_gclk_108895),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_7_15765 cg_RC_CG_HIER_INST7 (.enable(u_ethmac_0_u_inner_u_eth_top_wishbone_n_3997),
	.ck_in(CTS_168),
	.ck_out(cg_rc_gclk_108897),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_8_15766 cg_RC_CG_HIER_INST8 (.enable(FE_PHN52874_FE_OFN125641_n_15064),
	.ck_in(rtc_clk_clone13),
	.ck_out(cg_rc_gclk_108899),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_9_15767 cg_RC_CG_HIER_INST9 (.enable(n_3200),
	.ck_in(CTS_222),
	.ck_out(CTS_108),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_10_15768 cg_RC_CG_HIER_INST10 (.enable(n_15878),
	.ck_in(CTS_188),
	.ck_out(cg_rc_gclk_108903),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_11_15769 cg_RC_CG_HIER_INST11 (.enable(n_15878),
	.ck_in(CTS_222),
	.ck_out(CTS_91),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_12_15770 cg_RC_CG_HIER_INST12 (.enable(n_15877),
	.ck_in(CTS_185),
	.ck_out(cg_rc_gclk_108907),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_13_15771 cg_RC_CG_HIER_INST13 (.enable(n_15877),
	.ck_in(CTS_185),
	.ck_out(cg_rc_gclk_108909),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_14_15772 cg_RC_CG_HIER_INST14 (.enable(n_15876),
	.ck_in(rtc_clk_clone13),
	.ck_out(cg_rc_gclk_108911),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_15_15773 cg_RC_CG_HIER_INST15 (.enable(n_15876),
	.ck_in(rtc_clk_clone27),
	.ck_out(CTS_237),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_16_15774 cg_RC_CG_HIER_INST16 (.enable(u_apb_periph_u_apb_timer_0_write_enable08),
	.ck_in(CTS_168),
	.ck_out(cg_rc_gclk_108915),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_17_15775 cg_RC_CG_HIER_INST17 (.enable(u_ethmac_0_u_inner_u_eth_rx_cksum_n_1989),
	.ck_in(CTS_241),
	.ck_out(cg_rc_gclk_108917),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_18_15776 cg_RC_CG_HIER_INST18 (.enable(\u_network_core_u_slcorem0p_integration_u_cortexm0plus_u_top_gen_dbg1.u_dbg_gen_dwt1.u_dwt_gen_for_wpt[1].gen_wpt_pres.dwt_comp_wr ),
	.ck_in(CTS_188),
	.ck_out(cg_rc_gclk_108919),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_19_15777 cg_RC_CG_HIER_INST19 (.enable(u_network_core_u_slcorem0p_integration_u_cortexm0plus_u_top_u_sys_u_core_n_8363),
	.ck_in(CTS_1),
	.ck_out(cg_rc_gclk_108921),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_20_15778 cg_RC_CG_HIER_INST20 (.enable(u_network_core_u_slcorem0p_integration_u_cortexm0plus_u_top_u_sys_u_core_n_2149),
	.ck_in(CTS_11),
	.ck_out(cg_rc_gclk_108923),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_21_15779 cg_RC_CG_HIER_INST21 (.enable(u_network_core_u_slcorem0p_integration_u_cortexm0plus_u_top_u_sys_u_core_n_2150),
	.ck_in(CTS_11),
	.ck_out(cg_rc_gclk_108925),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_22_15780 cg_RC_CG_HIER_INST22 (.enable(u_network_core_u_slcorem0p_integration_u_cortexm0plus_u_top_u_sys_u_core_n_2151),
	.ck_in(CTS_11),
	.ck_out(cg_rc_gclk_108927),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_23_15781 cg_RC_CG_HIER_INST23 (.enable(u_network_core_u_slcorem0p_integration_u_cortexm0plus_u_top_u_sys_u_core_n_2152),
	.ck_in(CTS_11),
	.ck_out(cg_rc_gclk_108929),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_24_15782 cg_RC_CG_HIER_INST24 (.enable(u_network_core_u_slcorem0p_integration_u_cortexm0plus_u_top_u_sys_u_core_n_2153),
	.ck_in(CTS_11),
	.ck_out(cg_rc_gclk_108931),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_25_15783 cg_RC_CG_HIER_INST25 (.enable(u_network_core_u_slcorem0p_integration_u_cortexm0plus_u_top_u_sys_u_core_n_2154),
	.ck_in(CTS_11),
	.ck_out(cg_rc_gclk_108933),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_26_15784 cg_RC_CG_HIER_INST26 (.enable(u_network_core_u_slcorem0p_integration_u_cortexm0plus_u_top_u_sys_u_core_n_2155),
	.ck_in(CTS_11),
	.ck_out(cg_rc_gclk_108935),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_27_15785 cg_RC_CG_HIER_INST27 (.enable(u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_148),
	.ck_in(CTS_216),
	.ck_out(CTS_97),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_28_15786 cg_RC_CG_HIER_INST28 (.enable(u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_144),
	.ck_in(CTS_216),
	.ck_out(CTS_90),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_29_15787 cg_RC_CG_HIER_INST29 (.enable(u_network_core_u_slcorem0p_integration_u_cortexm0plus_u_top_u_sys_u_core_n_2156),
	.ck_in(CTS_11),
	.ck_out(cg_rc_gclk_108941),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_30_15788 cg_RC_CG_HIER_INST30 (.enable(u_network_core_u_slcorem0p_integration_u_cortexm0plus_u_top_u_sys_u_core_n_2157),
	.ck_in(CTS_11),
	.ck_out(cg_rc_gclk_108943),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_31_15789 cg_RC_CG_HIER_INST31 (.enable(u_network_core_u_slcorem0p_integration_u_cortexm0plus_u_top_u_sys_u_core_n_2158),
	.ck_in(CTS_11),
	.ck_out(cg_rc_gclk_108945),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_32_15790 cg_RC_CG_HIER_INST32 (.enable(u_network_core_u_slcorem0p_integration_u_cortexm0plus_u_top_u_sys_u_core_n_2159),
	.ck_in(CTS_11),
	.ck_out(cg_rc_gclk_108947),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_33_15791 cg_RC_CG_HIER_INST33 (.enable(u_network_core_u_slcorem0p_integration_u_cortexm0plus_u_top_u_sys_u_core_n_2160),
	.ck_in(CTS_11),
	.ck_out(cg_rc_gclk_108949),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_34_15792 cg_RC_CG_HIER_INST34 (.enable(u_network_core_u_slcorem0p_integration_u_cortexm0plus_u_top_u_sys_u_core_n_2161),
	.ck_in(CTS_1),
	.ck_out(cg_rc_gclk_108951),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_35_15793 cg_RC_CG_HIER_INST35 (.enable(u_network_core_u_slcorem0p_integration_u_cortexm0plus_u_top_u_sys_u_core_n_2162),
	.ck_in(CTS_1),
	.ck_out(cg_rc_gclk_108953),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_36_15794 cg_RC_CG_HIER_INST36 (.enable(u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_141),
	.ck_in(CTS_216),
	.ck_out(CTS_83),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_37_15795 cg_RC_CG_HIER_INST37 (.enable(u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_138),
	.ck_in(CTS_216),
	.ck_out(CTS_76),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_38_15796 cg_RC_CG_HIER_INST38 (.enable(u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_135),
	.ck_in(CTS_216),
	.ck_out(CTS_69),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_39_15797 cg_RC_CG_HIER_INST39 (.enable(u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_132),
	.ck_in(CTS_216),
	.ck_out(CTS_62),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_40_15798 cg_RC_CG_HIER_INST40 (.enable(u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_129),
	.ck_in(rtc_clk_clone24),
	.ck_out(CTS_150),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_41_15799 cg_RC_CG_HIER_INST41 (.enable(u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_126),
	.ck_in(CTS_216),
	.ck_out(CTS_55),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_42_15800 cg_RC_CG_HIER_INST42 (.enable(u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_123),
	.ck_in(rtc_clk_clone24),
	.ck_out(CTS_143),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_43_15801 cg_RC_CG_HIER_INST43 (.enable(u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_120),
	.ck_in(CTS_216),
	.ck_out(CTS_48),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_44_15802 cg_RC_CG_HIER_INST44 (.enable(u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_117),
	.ck_in(CTS_216),
	.ck_out(CTS_41),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_45_15803 cg_RC_CG_HIER_INST45 (.enable(u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_114),
	.ck_in(CTS_216),
	.ck_out(CTS_34),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_46_15804 cg_RC_CG_HIER_INST46 (.enable(u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_111),
	.ck_in(rtc_clk_clone24),
	.ck_out(CTS_136),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_47_15805 cg_RC_CG_HIER_INST47 (.enable(u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_108),
	.ck_in(rtc_clk_clone24),
	.ck_out(CTS_129),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_48_15806 cg_RC_CG_HIER_INST48 (.enable(u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_105),
	.ck_in(CTS_216),
	.ck_out(CTS_27),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_49_15807 cg_RC_CG_HIER_INST49 (.enable(u_ethmac_0_u_inner_u_eth_top_wishbone_rx_fifo_n_102),
	.ck_in(rtc_clk_clone24),
	.ck_out(CTS_122),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_50_15808 cg_RC_CG_HIER_INST50 (.enable(u_ethmac_0_u_inner_u_eth_top_wishbone_tx_fifo_n_148),
	.ck_in(CTS_167),
	.ck_out(cg_rc_gclk_108983),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_51_15809 cg_RC_CG_HIER_INST51 (.enable(u_ethmac_0_u_inner_u_eth_top_wishbone_tx_fifo_n_144),
	.ck_in(CTS_167),
	.ck_out(cg_rc_gclk_108985),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_52_15810 cg_RC_CG_HIER_INST52 (.enable(u_ethmac_0_u_inner_u_eth_top_wishbone_tx_fifo_n_141),
	.ck_in(CTS_167),
	.ck_out(cg_rc_gclk_108987),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_53_15811 cg_RC_CG_HIER_INST53 (.enable(u_ethmac_0_u_inner_u_eth_top_wishbone_tx_fifo_n_138),
	.ck_in(CTS_167),
	.ck_out(cg_rc_gclk_108989),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_54_15812 cg_RC_CG_HIER_INST54 (.enable(u_ethmac_0_u_inner_u_eth_top_wishbone_tx_fifo_n_135),
	.ck_in(rtc_clk_clone5),
	.ck_out(cg_rc_gclk_108991),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_55_15813 cg_RC_CG_HIER_INST55 (.enable(u_ethmac_0_u_inner_u_eth_top_wishbone_tx_fifo_n_132),
	.ck_in(rtc_clk_clone5),
	.ck_out(cg_rc_gclk_108993),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_56_15814 cg_RC_CG_HIER_INST56 (.enable(u_ethmac_0_u_inner_u_eth_top_wishbone_tx_fifo_n_129),
	.ck_in(CTS_167),
	.ck_out(cg_rc_gclk_108995),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_57_15815 cg_RC_CG_HIER_INST57 (.enable(u_ethmac_0_u_inner_u_eth_top_wishbone_tx_fifo_n_126),
	.ck_in(CTS_167),
	.ck_out(cg_rc_gclk_108997),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_58_15816 cg_RC_CG_HIER_INST58 (.enable(u_ethmac_0_u_inner_u_eth_top_wishbone_tx_fifo_n_123),
	.ck_in(CTS_167),
	.ck_out(cg_rc_gclk_108999),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_59_15817 cg_RC_CG_HIER_INST59 (.enable(u_ethmac_0_u_inner_u_eth_top_wishbone_tx_fifo_n_120),
	.ck_in(CTS_167),
	.ck_out(cg_rc_gclk_109001),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_60_15818 cg_RC_CG_HIER_INST60 (.enable(u_ethmac_0_u_inner_u_eth_top_wishbone_tx_fifo_n_117),
	.ck_in(CTS_167),
	.ck_out(cg_rc_gclk_109003),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_61_15819 cg_RC_CG_HIER_INST61 (.enable(u_ethmac_0_u_inner_u_eth_top_wishbone_tx_fifo_n_114),
	.ck_in(rtc_clk_clone5),
	.ck_out(cg_rc_gclk_109005),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_62_15820 cg_RC_CG_HIER_INST62 (.enable(u_ethmac_0_u_inner_u_eth_top_wishbone_tx_fifo_n_111),
	.ck_in(CTS_167),
	.ck_out(cg_rc_gclk_109007),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_63_15821 cg_RC_CG_HIER_INST63 (.enable(u_ethmac_0_u_inner_u_eth_top_wishbone_tx_fifo_n_108),
	.ck_in(rtc_clk_clone5),
	.ck_out(cg_rc_gclk_109009),
	.VDD(VDD),
	.VSS(VSS));
   cg_RC_CG_MOD_64_15822 cg_RC_CG_HIER_INST64 (.enable(u_ethmac_0_u_inner_u_eth_top_wishbone_tx_fifo_n_105),
	.ck_in(CTS_167),
	.ck_out(cg_rc_gclk_109011),
	.VDD(VDD),
	.VSS(VSS));
endmodule
