// -----------------------------------------------------------------------------
// FIXTURE -- not a build product. See ci/fixtures/dft-scan/README.md.
//
// Derived from the real post-route (Innovus) netlist of run rc5vt-20260829
//   ASIC/eth-chiplet/build/rc5vt-20260829/outputs/nanosoc_eth_chiplet_pads_pnr.v
// by extracting 200 integrated clock gates verbatim: each one's wrapper module
// definition and its instantiation, exactly as the netlist writer emitted them,
// line wrapping included. The other 2807 gates and everything that is not a
// clock gate are elided.
//
// WHY 200 AND NOT 3007. dft_icg_census.py refuses a netlist under 100 kB as
// too small to be a real one -- a guard against grading a truncated synthesis.
// 200 verbatim gates is the smallest extract that clears that floor.
//
// MUTATION APPLIED HERE: 90 of the 290 clock gates present in the post-synthesis netlist are absent here. Nothing else changed.
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
endmodule
