//-----------------------------------------------------------------------------
// bscan_tap — IEEE 1149.1 TAP controller: the 16-state test-access FSM
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
// The state machine of IEEE 1149.1-2001 Clause 6, nothing added and nothing
// removed. It owns no data path: it only publishes the phase strobes that the
// instruction register (`bscan_ir`) and the 76 boundary cells (`bscan_cell_*`)
// use to decide whether this TCK edge captures, shifts or updates.
//
// WHY the structure below, and what is load-bearing about it:
//
//   1. THE FIVE-TMS PROPERTY IS THE WHOLE POINT OF THE ENCODING. 1149.1
//      guarantees that TMS held high for five TCK edges reaches Test-Logic-
//      Reset from ANY state, which is how a tester with no knowledge of the
//      current state re-synchronises. That property is a property of the
//      TRANSITION TABLE, not of the reset pin, so it has to survive every
//      "tidy-up" of the case statement below. The worst-case chains are
//      written out in the table so a reviewer can re-check them without
//      redrawing the bubble diagram. Shift-DR is one of the five-edge cases:
//
//        SHIFT_DR -> EXIT1_DR -> UPDATE_DR -> SEL_DR -> SEL_IR -> TLR
//
//      Get SEL_IR's TMS=1 arc wrong (the usual slip is sending it to RTI, or
//      to SEL_DR, "so the scan columns are symmetric") and the chain becomes
//      unbounded: the tester can never recover the part, and on a bonded die
//      that is a dead JTAG port with no software workaround.
//
//   2. NEXT-STATE IS A FUNCTION OF (state, tms) ONLY. No hidden counters, no
//      enables, no gated TCK. A TAP that is anything other than a Moore
//      machine over 16 states cannot be checked against the standard's table
//      by inspection, and this one has to be, because there is no way to
//      re-spin it after tapeout.
//
//   3. EVERY OUTPUT IS A DECODE OF THE STATE FLOPS, NOT A SEPARATE FLOP.
//      Registering the strobes would delay them by one TCK and silently shear
//      the capture/shift/update phases apart from the state the tester thinks
//      it is in. One level of combinational decode off a flop is also
//      glitch-free by construction, which matters for `update_dr`/`update_ir`
//      because the wrapper consumes them on the FALLING TCK edge — half a
//      period after they settle.
//
//   4. `trst_n` IS ASYNCHRONOUS AND ACTIVE LOW. Per the chip-level plan it is
//      driven from `~SE`, so with boundary scan disabled (SE=0) the TAP sits
//      in Test-Logic-Reset permanently, `bscan_ir` holds IDCODE, `mode` is 0
//      and every ctl cell is transparent. That is the property that keeps
//      functional silicon bit-identical to today, and it is enforced here by
//      the reset being asynchronous: it does not need a TCK edge, and TCK is
//      not guaranteed to toggle at all in a functional application.
//
// TWO THINGS THE WRAPPER MUST DO, WHICH THIS MODULE CANNOT DO FOR ITSELF:
//
//   a) 1149.1 Clause 6.1.1 requires the INSTRUCTION REGISTER to be reset in
//      the Test-Logic-Reset STATE, not merely on the TRST_n PIN. `bscan_ir`
//      as specified in the interface contract has no `tlr` input, so the only
//      reset it can see is its `trst_n`. The wrapper must therefore wire
//        assign ir_trst_n = trst_n & ~tlr;
//      and feed THAT to bscan_ir. Without it, five TMS=1 edges land the TAP in
//      TLR while the held instruction stays whatever it was — a conformance
//      failure that a BSDL-driven tester will hit on its very first vector.
//      This is why `tlr` is exported at all; nothing inside this module uses it.
//
//   b) TDO must be retimed onto the FALLING edge of TCK (1149.1 Clause 4.4).
//      `tdo_enable` here is a plain state decode, so it rises half a TCK
//      BEFORE and falls half a TCK before the standard's enable window. See
//      the comment at the assignment.
//
// STATE ENCODING is fixed by the interface contract, and it is not arbitrary:
// bit [3] separates the DR half of the diagram from the IR half everywhere
// except UPDATE_DR (4'h8). Do not renumber — the contract's generator and the
// BSDL both quote these values.
//
// FULL TRANSITION TABLE (the authority for this implementation), and the
// hand-checked distance to TLR with TMS held high:
//
//   state        code   tms=0      tms=1       edges to TLR with tms=1
//   -----------  ----   ---------  ----------  -----------------------
//   TLR          4'h0   RTI        TLR         0  (already there)
//   RTI          4'h1   RTI        SEL_DR      3  SEL_DR,SEL_IR,TLR
//   SEL_DR       4'h2   CAP_DR     SEL_IR      2  SEL_IR,TLR
//   CAP_DR       4'h3   SHIFT_DR   EXIT1_DR    5  E1DR,UPDR,SELDR,SELIR,TLR
//   SHIFT_DR     4'h4   SHIFT_DR   EXIT1_DR    5  E1DR,UPDR,SELDR,SELIR,TLR
//   EXIT1_DR     4'h5   PAUSE_DR   UPDATE_DR   4  UPDR,SELDR,SELIR,TLR
//   PAUSE_DR     4'h6   PAUSE_DR   EXIT2_DR    5  E2DR,UPDR,SELDR,SELIR,TLR
//   EXIT2_DR     4'h7   SHIFT_DR   UPDATE_DR   4  UPDR,SELDR,SELIR,TLR
//   UPDATE_DR    4'h8   RTI        SEL_DR      3  SELDR,SELIR,TLR
//   SEL_IR       4'h9   CAP_IR     TLR         1  TLR
//   CAP_IR       4'hA   SHIFT_IR   EXIT1_IR    5  E1IR,UPIR,SELDR,SELIR,TLR
//   SHIFT_IR     4'hB   SHIFT_IR   EXIT1_IR    5  E1IR,UPIR,SELDR,SELIR,TLR
//   EXIT1_IR     4'hC   PAUSE_IR   UPDATE_IR   4  UPIR,SELDR,SELIR,TLR
//   PAUSE_IR     4'hD   PAUSE_IR   EXIT2_IR    5  E2IR,UPIR,SELDR,SELIR,TLR
//   EXIT2_IR     4'hE   SHIFT_IR   UPDATE_IR   4  UPIR,SELDR,SELIR,TLR
//   UPDATE_IR    4'hF   RTI        SEL_DR      3  SELDR,SELIR,TLR
//
// Maximum over all sixteen rows is 5, and TLR is absorbing under tms=1, so
// five edges suffice from every state. The two arcs that bound it are
// SEL_IR --1--> TLR (the only way in) and PAUSE_* --1--> EXIT2_* (the longest
// tail). Both are checked again in the case statement's inline comments.
//-----------------------------------------------------------------------------

module bscan_tap (
  input  wire tck,
  input  wire tms,
  input  wire trst_n,        // async; also driven low when bscan is disabled
  output wire tlr,           // in Test-Logic-Reset
  output wire capture_dr,
  output wire shift_dr,
  output wire update_dr,
  output wire capture_ir,
  output wire shift_ir,
  output wire update_ir,
  output wire select_ir,     // 1 while in the IR column of the state diagram
  output wire tdo_enable     // 1 in Shift-IR or Shift-DR only
);

  //---------------------------------------------------------------------------
  // State codes. Mandated by the interface contract; also quoted by the BSDL
  // and by the generated wrapper, so they are an interface, not a local choice.
  //---------------------------------------------------------------------------
  localparam logic [3:0] ST_TLR       = 4'h0;   // Test-Logic-Reset
  localparam logic [3:0] ST_RTI       = 4'h1;   // Run-Test/Idle
  localparam logic [3:0] ST_SEL_DR    = 4'h2;   // Select-DR-Scan
  localparam logic [3:0] ST_CAP_DR    = 4'h3;   // Capture-DR
  localparam logic [3:0] ST_SHIFT_DR  = 4'h4;   // Shift-DR
  localparam logic [3:0] ST_EXIT1_DR  = 4'h5;   // Exit1-DR
  localparam logic [3:0] ST_PAUSE_DR  = 4'h6;   // Pause-DR
  localparam logic [3:0] ST_EXIT2_DR  = 4'h7;   // Exit2-DR
  localparam logic [3:0] ST_UPDATE_DR = 4'h8;   // Update-DR
  localparam logic [3:0] ST_SEL_IR    = 4'h9;   // Select-IR-Scan
  localparam logic [3:0] ST_CAP_IR    = 4'hA;   // Capture-IR
  localparam logic [3:0] ST_SHIFT_IR  = 4'hB;   // Shift-IR
  localparam logic [3:0] ST_EXIT1_IR  = 4'hC;   // Exit1-IR
  localparam logic [3:0] ST_PAUSE_IR  = 4'hD;   // Pause-IR
  localparam logic [3:0] ST_EXIT2_IR  = 4'hE;   // Exit2-IR
  localparam logic [3:0] ST_UPDATE_IR = 4'hF;   // Update-IR

  logic [3:0] state_q;
  logic [3:0] state_d;

  //---------------------------------------------------------------------------
  // Next state. Plain `case` with a `default` — no `unique`/`priority`, because
  // those carry simulation-time assertion semantics that Genus 21.15 treats as
  // a synthesis pragma and that we do not want silently changing the decode.
  // The `default` arm is UNREACHABLE and known to be: all sixteen codes of a
  // 4-bit state are enumerated, so there is no illegal encoding for it to
  // catch, and it costs nothing in the synthesised logic. It is here so the
  // case stays complete-by-construction if the encoding is ever widened, and
  // because a next-state case with no default is the shape that turns a later
  // one-line edit into an inferred latch. Test-Logic-Reset is the only safe
  // landing to name.
  //---------------------------------------------------------------------------
  always_comb begin
    case (state_q)
      ST_TLR       : state_d = tms ? ST_TLR       : ST_RTI;
      ST_RTI       : state_d = tms ? ST_SEL_DR    : ST_RTI;
      // SEL_DR falls through to the IR column on tms=1 — this arc, together
      // with SEL_IR->TLR below, is what bounds the reset chain at five.
      ST_SEL_DR    : state_d = tms ? ST_SEL_IR    : ST_CAP_DR;
      ST_CAP_DR    : state_d = tms ? ST_EXIT1_DR  : ST_SHIFT_DR;
      ST_SHIFT_DR  : state_d = tms ? ST_EXIT1_DR  : ST_SHIFT_DR;
      ST_EXIT1_DR  : state_d = tms ? ST_UPDATE_DR : ST_PAUSE_DR;
      ST_PAUSE_DR  : state_d = tms ? ST_EXIT2_DR  : ST_PAUSE_DR;
      // Exit2 on tms=0 returns to SHIFT, not to CAPTURE: re-entering Capture
      // would reload the chain and destroy the data the tester paused to hold.
      ST_EXIT2_DR  : state_d = tms ? ST_UPDATE_DR : ST_SHIFT_DR;
      ST_UPDATE_DR : state_d = tms ? ST_SEL_DR    : ST_RTI;
      // The ONLY TMS-driven entry to Test-Logic-Reset in the whole diagram.
      ST_SEL_IR    : state_d = tms ? ST_TLR       : ST_CAP_IR;
      ST_CAP_IR    : state_d = tms ? ST_EXIT1_IR  : ST_SHIFT_IR;
      ST_SHIFT_IR  : state_d = tms ? ST_EXIT1_IR  : ST_SHIFT_IR;
      ST_EXIT1_IR  : state_d = tms ? ST_UPDATE_IR : ST_PAUSE_IR;
      ST_PAUSE_IR  : state_d = tms ? ST_EXIT2_IR  : ST_PAUSE_IR;
      ST_EXIT2_IR  : state_d = tms ? ST_UPDATE_IR : ST_SHIFT_IR;
      // Both Update states rejoin the DR column, never the IR column: that is
      // what makes UPDATE_IR three edges from TLR rather than a dead end.
      ST_UPDATE_IR : state_d = tms ? ST_SEL_DR    : ST_RTI;
      default      : state_d = ST_TLR;
    endcase
  end

  //---------------------------------------------------------------------------
  // State register. Asynchronous reset to Test-Logic-Reset, as 1149.1 requires
  // of TRST_n: the tester (and, here, the SE strap) must be able to force the
  // reset with TCK completely stopped.
  //
  // NOTE for constraints: the RELEASE of trst_n is asynchronous to tck. SE is a
  // static strap held for the whole test session, so in practice the release
  // happens long before the first TCK edge, but the recovery/removal arc is
  // still unconstrained. Either add a two-flop de-assertion synchroniser on
  // trst_n at the wrapper, or waive the arc explicitly in the SDC. Do not leave
  // it unstated.
  //---------------------------------------------------------------------------
  always_ff @(posedge tck or negedge trst_n) begin
    if (!trst_n)
      state_q <= ST_TLR;
    else
      state_q <= state_d;
  end

  //---------------------------------------------------------------------------
  // Phase strobes. One decode level off the state flops; asserted for the whole
  // TCK period the machine spends in the named state.
  //---------------------------------------------------------------------------
  assign tlr        = (state_q == ST_TLR);
  assign capture_dr = (state_q == ST_CAP_DR);
  assign shift_dr   = (state_q == ST_SHIFT_DR);
  assign update_dr  = (state_q == ST_UPDATE_DR);
  assign capture_ir = (state_q == ST_CAP_IR);
  assign shift_ir   = (state_q == ST_SHIFT_IR);
  assign update_ir  = (state_q == ST_UPDATE_IR);

  //---------------------------------------------------------------------------
  // `select_ir` — the IR column of the diagram, i.e. everything from
  // Select-IR-Scan through Update-IR. The wrapper uses it to steer the TDO mux
  // between the instruction register and the selected data register.
  //
  // Written as an explicit membership test rather than the one-liner the
  // mandated encoding permits (`state_q[3] & |state_q[2:0]`, since the IR
  // column is exactly 4'h9..4'hF). The one-liner is correct today and silently
  // wrong the moment anyone renumbers a state; the explicit form cannot rot,
  // and synthesis reduces the two to the same logic anyway.
  //---------------------------------------------------------------------------
  assign select_ir = (state_q == ST_SEL_IR)   | (state_q == ST_CAP_IR)   |
                     (state_q == ST_SHIFT_IR) | (state_q == ST_EXIT1_IR) |
                     (state_q == ST_PAUSE_IR) | (state_q == ST_EXIT2_IR) |
                     (state_q == ST_UPDATE_IR);

  //---------------------------------------------------------------------------
  // `tdo_enable` — implemented exactly as the interface contract specifies:
  // high in Shift-IR or Shift-DR and nowhere else.
  //
  // FLAGGED DEVIATION FROM 1149.1, DELIBERATELY LEFT AS THE CONTRACT ASKS:
  // Clause 4.4 wants the TDO driver enabled at the FALLING TCK edge after
  // entering a Shift state and disabled at the falling edge after leaving one.
  // This decode is a function of a rising-edge state register, so it turns TDO
  // on half a TCK early (harmless — the bus is otherwise idle) and off half a
  // TCK early (NOT harmless — the driver releases on the same rising edge at
  // which the tester samples the final bit of the scan, which is a race).
  //
  // The fix belongs in the wrapper, where the TDO output flop already has to be
  // negative-edge triggered:
  //     always_ff @(negedge tck or negedge trst_n)
  //       if (!trst_n) tdo_oe_q <= 1'b0; else tdo_oe_q <= tdo_enable;
  // That reshapes this signal into the standard's window without changing this
  // module's contract. Raised in the handover report; not silently altered here.
  //---------------------------------------------------------------------------
  assign tdo_enable = (state_q == ST_SHIFT_DR) | (state_q == ST_SHIFT_IR);

endmodule
