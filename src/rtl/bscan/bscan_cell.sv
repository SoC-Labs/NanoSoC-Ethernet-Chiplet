//-----------------------------------------------------------------------------
// bscan_cell — IEEE 1149.1 boundary-scan cell primitives (observe / control)
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
// These two cells are the most replicated logic in the chiplet: 76 instances
// (18 input + 15 output + 13 bidir x3 + 2 open-drain x2), one per boundary-scan
// register bit, and every ctl instance sits IN SERIES with a functional pad
// path. Both the area and the added functional delay are therefore paid 76
// times over, which drives every structural decision below.
//
// WHY the shape below:
//
//   1. ONE capture/shift element, not two. 1149.1 permits capture and shift to
//      share a flop because the two are mutually exclusive TAP states. The D
//      input is then a plain 2:1 mux (scan-in vs the observed value) — exactly
//      the structure inside a mux-D scan flop — so the intent is spelled out as
//      a separate `*_d` mux and a separate `*_en` load term rather than buried
//      in a behavioural priority chain. Genus should read that as one
//      SEDF*/SDF*-class sequential cell (mux-D flop with load enable); the
//      fallback mapping is MUX2 + enabled DF, still one flop. Written as a
//      three-way behavioural case it would instead invite a per-cell hold
//      feedback mux on top of the data mux — 76 gates bought for nothing.
//
//   2. SHIFT BEATS CAPTURE. `shift_dr` is the select of the D mux and the first
//      term of the enable, so a cell that ever saw both strobes at once keeps
//      shifting rather than dropping a pad value into the middle of the chain.
//      The TAP never asserts both; the priority is here because the boundary
//      register is a 76-bit serial chain and a single cell that captured
//      mid-shift would corrupt one bit silently — presenting as a stuck pad,
//      not as a control bug, and costing a bring-up day to find.
//
//   3. The update flop clocks on the FALLING edge of tck. This is the whole
//      reason 1149.1 splits the cell into two stages. The shift stage advances
//      on the rising edge, so an update stage on the same edge would sample its
//      own input exactly as that input changes, and — far worse — the pad would
//      then follow the shift register bit by bit while the chain is being
//      loaded, toggling every driven pin of the chip once per TCK. Taking the
//      update half a cycle later means the value handed to the pad changes only
//      while the shift stage is quiet, so each pad sees exactly one clean
//      transition per Update-DR. On this die that is not merely tidy: the two
//      I2C pads are a wired-AND bus and the bidir OE bits gate 16 mA drivers
//      into a package that a second die also drives.
//
//   4. RESET LEAVES EVERY CELL TRANSPARENT. `func_out` is a mux, never a gate
//      in the functional data flow: with `mode` low it is `func_in`
//      combinationally, so the functional cost of instrumenting a pad is one
//      MUX2 of delay and nothing else. `trst_n` additionally clears `update_q`
//      so the value parked behind that mux is 0 rather than X from power-up —
//      otherwise a gate-level or post-layout sim propagates X onto every driven
//      pad the instant EXTEST is entered, and `mode` is the only thing between
//      an unknown and the pad ring.
//
//   5. `trst_n` clears the shift stage as well. 1149.1 does not require that,
//      but the obs cell's port list carries `trst_n` and has no update flop, so
//      the shift stage is the only thing it can possibly reset — and an unreset
//      chain reads back X in GLS until the first Capture-DR, which makes the
//      very first thing anyone does with this ring (shift a known pattern in,
//      watch it come out) unreadable. A DFCN-class flop instead of a DF-class
//      one, 76 times, is the price; determinism in gate sim is worth it.
//
// Deliberately NOT here: no INTEST return path (the wrapper ties `core_in`
// straight to `pin_in`), and no HIGHZ term — HIGHZ is a wrapper-level override
// on the OE cells, because a primitive cannot tell an OE bit from a data bit.
//-----------------------------------------------------------------------------

// Two modules share this file by contract (§2), so the filename cannot match
// both. Silence only that Verilator check; it has no effect on synthesis.
/* verilator lint_off DECLFILENAME */

//-----------------------------------------------------------------------------
// bscan_cell_obs — observe-only cell: input pads, and the input half of bidirs.
// Watches the pad and can be shifted; it drives nothing back into the design.
//-----------------------------------------------------------------------------
module bscan_cell_obs (
  input  wire tck,          // test clock
  input  wire trst_n,       // async reset, active low
  input  wire capture_dr,   // 1 = load pin_in on the next tck rising edge
  input  wire shift_dr,     // 1 = shift (takes priority over capture)
  input  wire si,           // scan in
  input  wire pin_in,       // the value observed at the pad
  output wire so            // scan out (combinational from the shift flop)
);

  // Mux-D shift/capture element. `dr_d` is the scan mux (si vs observed data)
  // and `dr_en` is the load enable; holding is the absence of a load, not a
  // third mux input. See WHY note 1 — this pairing is what Genus maps to a
  // single mux-D flop.
  wire dr_d  = shift_dr ? si : pin_in;
  wire dr_en = shift_dr | capture_dr;

  logic dr_q;

  always_ff @(posedge tck or negedge trst_n) begin
    if (!trst_n)    dr_q <= 1'b0;
    else if (dr_en) dr_q <= dr_d;
  end

  assign so = dr_q;

endmodule

//-----------------------------------------------------------------------------
// bscan_cell_ctl — capture / update / drive cell: output pads, the driving half
// of bidirs, and the OE bit of an open-drain pad. Two stages: the shift flop on
// the rising tck edge, the update flop on the falling one.
//-----------------------------------------------------------------------------
module bscan_cell_ctl (
  input  wire tck,
  input  wire trst_n,
  input  wire capture_dr,
  input  wire shift_dr,
  input  wire update_dr,    // 1 = copy shift flop into the update flop
  input  wire mode,         // 1 = drive from update flop (EXTEST); 0 = functional
  input  wire si,
  input  wire func_in,      // the functional value from the core
  output wire func_out,     // to the pad: mode ? update_q : func_in
  output wire so
);

  // Stage 1 — identical mux-D element to bscan_cell_obs, but capturing the
  // core-side value: on an output cell the interesting datum is what the design
  // is driving, not what the pad reads back.
  wire dr_d  = shift_dr ? si : func_in;
  wire dr_en = shift_dr | capture_dr;

  logic dr_q;
  logic update_q;

  always_ff @(posedge tck or negedge trst_n) begin
    if (!trst_n)    dr_q <= 1'b0;
    else if (dr_en) dr_q <= dr_d;
  end

  // Stage 2 — NEGEDGE tck by 1149.1 mandate, not by preference. Sampling the
  // shift stage half a cycle after it moves keeps the pad quiet while the chain
  // is loading, and keeps this flop's setup window clear of its own D changing.
  // The async clear is what makes reset transparency real rather than nominal:
  // update_q is 0, not X, before the first Update-DR ever happens.
  always_ff @(negedge tck or negedge trst_n) begin
    if (!trst_n)        update_q <= 1'b0;
    else if (update_dr) update_q <= dr_q;
  end

  // The one gate in the functional path. `mode` is held low by the TAP outside
  // EXTEST/CLAMP/HIGHZ, so functional silicon behaviour is this mux and nothing
  // more.
  assign func_out = mode ? update_q : func_in;

  assign so = dr_q;

endmodule

/* verilator lint_on DECLFILENAME */
