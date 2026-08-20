//-----------------------------------------------------------------------------
// bscan_ir — IEEE 1149.1 instruction register: shift, update and decode
//
// A joint work commissioned on behalf of SoC Labs, under Arm Academic Access
// license.
//
// Contributors
//
// David Mapstone (d.a.mapstone@soton.ac.uk)
//
// Copyright 2026, SoC Labs (www.soclabs.org)
//-----------------------------------------------------------------------------
// Two registers and a decode table. The SHIFT register is what the tester sees
// on TDI/TDO; the HELD register is what the rest of the chip obeys. Keeping
// them separate is the entire reason 1149.1 has an Update-IR state: while a new
// instruction is being clocked in, the pads must go on behaving according to
// the OLD one. Merge the two and every intermediate bit pattern of the shift
// becomes a live instruction — on this die that means EXTEST (4'b0000) and
// HIGHZ (4'b0100) are transiently entered on the way to almost any other code,
// so the boundary register would start driving the pads mid-shift.
//
// WHY the specific choices below:
//
//   1. RESET INSTRUCTION IS IDCODE, NOT BYPASS. 1149.1 Clause 5.1.1: a part
//      that implements IDCODE must select it at reset, so that a tester walking
//      an unknown chain can read the chain's identity before it knows anything
//      else. `mode`=0 and `highz`=0 fall out of that, which is exactly the
//      state functional silicon needs (see the SE strap note below).
//
//   2. CAPTURE LOADS ...01, NOT THE HELD INSTRUCTION. Clause 6.1.2 fixes the
//      two least-significant bits at 2'b01 so that a tester shifting a known
//      pattern out of an unknown chain can find the register boundaries and
//      count devices. The upper bits are design-specific status; we have no
//      status worth reporting, so they capture 0. Capturing the current
//      instruction instead (a common "improvement") breaks chain discovery.
//
//   3. THE HELD REGISTER LOADS ON THE FALLING TCK EDGE. This mirrors the update
//      flop of `bscan_cell_ctl` and it is required for the same reason: `mode`
//      and `highz` reach the pad output enables, and changing a pad's drive
//      state on the same edge that clocks the scan chain is how you get a
//      contention glitch on a shared bus. Loading at the rising edge that ENDS
//      Update-IR would also work functionally (the strobe is still high at that
//      edge), but it puts a pad-enable change on the tester's sampling edge.
//      Note this departs from the repo's usual all-posedge house style; it is a
//      1149.1 requirement, not a preference.
//
//   4. SHIFT BEFORE CAPTURE IN THE PRIORITY LADDER. The TAP never asserts both
//      (Capture-IR and Shift-IR are different states), so the order is a
//      belt-and-braces choice matching the one the interface contract mandates
//      for the boundary cells. Consistency here is worth more than the gate.
//
// SHIFT DIRECTION: TDI enters at the MSB and TDO leaves from the LSB, so the
// FIRST bit the tester shifts in ends up in bit 0. That is the 1149.1
// convention and it is the one the BSDL INSTRUCTION_OPCODE strings assume; get
// it backwards and every opcode in the table is bit-reversed.
//
//-----------------------------------------------------------------------------
// THE INSTRUCTION IS NOT RESET BY THE TEST-LOGIC-RESET *STATE* — WRAPPER ACTION
// REQUIRED.
//
// Clause 6.1.1 requires the instruction register to be reset whenever the TAP
// is IN Test-Logic-Reset, however it got there — including via five TMS=1
// edges, with TRST_n never asserted. This module's interface (fixed by the
// contract) has no `tlr` input, so it physically cannot see that. The wrapper
// must close the gap by folding the TAP's `tlr` output into this module's
// reset:
//
//     assign ir_trst_n = trst_n & ~tlr;
//     bscan_ir u_ir (.trst_n (ir_trst_n), ...);
//
// It deasserts on the same rising edge that leaves TLR, so nothing is held in
// reset a cycle too long. Without it, a BSDL-driven tester's opening
// five-TMS-1 resync leaves whatever instruction was last loaded in force —
// a conformance failure on the very first vector, and if that instruction was
// EXTEST it is a conformance failure with the pads under scan control.
//-----------------------------------------------------------------------------
// IDCODE — the register lives in the GENERATED WRAPPER, not here.
//
// This module only says WHEN the IDCODE register is selected (`sel_idcode`);
// the 32 bits themselves are a parallel-load shift register in
// `nanosoc_eth_chiplet_bscan.sv`, because that is where the DR mux and the
// chain ordering live. The value the generator must use, per section 5 of the
// interface contract:
//
//     parameter logic [31:0] IDCODE_VALUE = 32'h1000_1001;
//        // {version[3:0]=4'h1, part[15:0]=16'h0001, manuf[10:0]=11'h000, 1'b1}
//
//   * WRITE EIGHT HEX DIGITS. An earlier contract revision wrote the literal as
//     `32'h1_0000_05A1` — NINE digits, 36 bits crammed into a 32-bit literal,
//     which truncates and silently loses the version nibble. The bench's
//     mutation M9 exists to catch exactly that.
//   * THE MANUFACTURER FIELD IS 0x000 ON PURPOSE. IDCODE[11:1] is a packed
//     JEDEC JEP106 identity, (continuation_count << 7) | code7, so any code in
//     1..126 names a real company. This design previously carried 0x2D0, which
//     decodes to JEP106 bank 6 code 0x50 — assigned to Neterion Inc. Code 0 is
//     the one value JEP106 can never issue, so it is the only placeholder that
//     impersonates nobody; tools render it "<invalid>" and stop.
//   * SOC LABS HAS NO ASSIGNED JEDEC MANUFACTURER ID. 0x2D0 is a placeholder
//     and part number 0x0000 is a placeholder. Both MUST be replaced with a
//     real JEDEC assignment before tapeout: an unassigned ID collides with
//     whatever real vendor owns that code, and on a multi-drop board scan chain
//     a tester will bind the wrong BSDL to this die. This is a tapeout gate,
//     not a nicety.
//   * The LSB must remain 1 — that is how a tester distinguishes a 32-bit
//     IDCODE register from a 1-bit BYPASS register when it does not yet know
//     what is in the chain.
//-----------------------------------------------------------------------------

module bscan_ir #(
  parameter int IR_WIDTH = 4
) (
  input  wire tck,
  input  wire trst_n,
  input  wire capture_ir,
  input  wire shift_ir,
  input  wire update_ir,
  input  wire si,
  output wire so,
  output wire sel_bypass,
  output wire sel_idcode,
  output wire sel_boundary,  // EXTEST | SAMPLE_PRELOAD | CLAMP-with-boundary
  output wire mode,          // drive the boundary register onto the pads
  output wire highz          // tri-state all outputs
);

  //---------------------------------------------------------------------------
  // Opcodes. Sized to IR_WIDTH so a wider IR (spare codes for a future
  // internal-scan or debug instruction) needs no edit here: the defined codes
  // zero-extend and BYPASS stays all-ones, which 1149.1 Clause 8.4 requires
  // precisely so that a broken or unpowered device in a chain — whose TDI
  // floats high — degrades to BYPASS rather than to something that drives pins.
  // IR_WIDTH must be >= 4 for the codes to remain distinct; 4 is the shipping
  // value and the one the BSDL will declare.
  //---------------------------------------------------------------------------
  localparam logic [IR_WIDTH-1:0] INSN_EXTEST         = 'h0;
  localparam logic [IR_WIDTH-1:0] INSN_SAMPLE_PRELOAD = 'h1;
  localparam logic [IR_WIDTH-1:0] INSN_IDCODE         = 'h2;
  localparam logic [IR_WIDTH-1:0] INSN_CLAMP          = 'h3;
  localparam logic [IR_WIDTH-1:0] INSN_HIGHZ          = 'h4;
  localparam logic [IR_WIDTH-1:0] INSN_BYPASS         = {IR_WIDTH{1'b1}};

  // The mandated capture pattern: zeros above, 2'b01 in the bottom two bits.
  localparam logic [IR_WIDTH-1:0] IR_CAPTURE = {{(IR_WIDTH-2){1'b0}}, 2'b01};

  logic [IR_WIDTH-1:0] shift_q;   // what the tester is clocking through
  logic [IR_WIDTH-1:0] insn_q;    // what the chip currently obeys

  //---------------------------------------------------------------------------
  // Shift register: rising edge, async reset. Reset value is cosmetic — the
  // register is always either captured or fully shifted before it is used — but
  // leaving it X hands the netlist simulation an X that propagates onto `so`
  // and out of TDO, which wastes an afternoon on the bench every time.
  //---------------------------------------------------------------------------
  always_ff @(posedge tck or negedge trst_n) begin
    if (!trst_n)
      shift_q <= IR_CAPTURE;
    else if (shift_ir)
      shift_q <= {si, shift_q[IR_WIDTH-1:1]};
    else if (capture_ir)
      shift_q <= IR_CAPTURE;
  end

  // Combinational out of the shift flop. The wrapper owns the negative-edge
  // TDO output flop (1149.1 Clause 4.4), so retiming must NOT be duplicated
  // here — doing it twice costs a whole TCK of chain length and the BSDL's
  // declared register lengths stop matching the silicon.
  assign so = shift_q[0];

  //---------------------------------------------------------------------------
  // Held instruction: falling edge of TCK while Update-IR is asserted. See
  // point 3 in the header for why this one flop breaks the house style.
  //
  // Reset selects IDCODE. With the chip-level SE strap at 0 the wrapper holds
  // trst_n low permanently, so this register is IDCODE for the entire life of a
  // functional part: sel_boundary=0, mode=0, highz=0, every ctl cell
  // transparent, functional behaviour bit-identical to a chip with no boundary
  // scan in it at all. That property is the one the testbench has to prove.
  //---------------------------------------------------------------------------
  always_ff @(negedge tck or negedge trst_n) begin
    if (!trst_n)
      insn_q <= INSN_IDCODE;
    else if (update_ir)
      insn_q <= shift_q;
  end

  //---------------------------------------------------------------------------
  // Decode. One packed vector so the table reads like the specification table
  // it is transcribed from, and so no arm can accidentally leave a signal to an
  // implicit prior value.
  //
  //                      sel_bypass ----+
  //                      sel_idcode ----|+
  //                    sel_boundary ----||+
  //                            mode ----|||+
  //                           highz ----||||+
  //                                     vvvvv
  //---------------------------------------------------------------------------
  logic [4:0] dec;

  always_comb begin
    case (insn_q)
      INSN_EXTEST         : dec = 5'b00110;  // boundary reg, driving the pads
      INSN_SAMPLE_PRELOAD : dec = 5'b00100;  // boundary reg, pads functional
      INSN_IDCODE         : dec = 5'b01000;  // 32-bit ID reg in the wrapper
      INSN_CLAMP          : dec = 5'b10010;  // BYPASS in chain, pads held by BSR
      INSN_HIGHZ          : dec = 5'b10001;  // BYPASS in chain, all pads off
      INSN_BYPASS         : dec = 5'b10000;
      // 1149.1 Clause 8.4: every unimplemented opcode must behave as BYPASS.
      // Not a defensive nicety — a tester that guesses a private opcode must
      // not be able to put the pads under scan control by accident.
      default             : dec = 5'b10000;
    endcase
  end

  assign {sel_bypass, sel_idcode, sel_boundary, mode, highz} = dec;

endmodule
