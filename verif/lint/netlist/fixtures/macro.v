// Header-only stub, exactly what gen_macro_bbox.py-style blackboxing produces
module MY_SRAM (CLK, A, Q, CEN, WEN);
  input        CLK;
  input  [7:0] A;
  output [31:0] Q;
  input        CEN;
  input        WEN;
endmodule
