//-----------------------------------------------------------------------------
// verif/bscan/tb_bscan.sv -- self-checking bench for nanosoc_eth_chiplet_bscan,
// the IEEE 1149.1 boundary-scan wrapper around the 48-pad chiplet padring.
// A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
//
// Contributors: SoC Labs verification
// Copyright 2026, SoC Labs (www.soclabs.org)
//-----------------------------------------------------------------------------
// WHY THIS BENCH IS SHAPED THE WAY IT IS
//
// 1. THE ONE TEST THAT MATTERS IS T1.
//    Boundary scan is inserted between the core and every pad on a chip that
//    already works. The failure mode that ends the tapeout is not "EXTEST is
//    broken" -- it is "the functional path through the wrapper is not
//    bit-identical to today". So T1 drives random vectors on every core-side
//    port with the TAP disabled (trst_n=0, the SE=0 default of contract
//    section 7) and demands a combinational, bit-exact response -- including
//    with TCK stopped dead, which is the only way to prove the functional path
//    is not accidentally clocked.
//
// 2. NO PORT NAMES ARE WRITTEN HERE.
//    The wrapper is generated from pad_table.json and its port list is 150-odd
//    names wide. tb_bscan_pads.svh (from gen_tb_pads.py, same JSON) supplies the
//    declarations, the instantiation and the chain map; the body below is
//    written generically over ring-ordered arrays. One table, one derivation --
//    the TB cannot drift from the ring order the RTL was generated with.
//
// 3. EVERY EDGE IS A REAL JTAG EDGE.
//    TMS/TDI are driven on the FALLING edge of TCK, exactly as a TAP master
//    drives them; the DUT samples them on the rising edge. TDO (and, where a
//    cycle-accurate view is needed, pad_out/pad_oe) is read through clocking
//    block `cb` with a #1step (preponed) input skew at the rising edge -- the
//    value the DUT held for the whole of that cycle. That sample point is
//    correct whether the wrapper retimes TDO onto the falling edge (1149.1
//    style) or drives it combinationally from the shift flop, and it races with
//    neither. The only `#` in the checking path is COMB_SETTLE, used in T1/T7
//    where there is deliberately NO clock edge to synchronise to -- a settle for
//    a purely combinational, clockless path, parked 4 ns clear of any TCK edge.
//
// 4. EVERY CHECK MUST BE ABLE TO FAIL.
//    Each test names the single RTL change that should break it; the list lives
//    in verif/bscan/README.md under "Mutation tests" and is the gate on whether
//    a green here means anything. The final line reports the number of
//    comparisons actually performed, and run.sh refuses to call a run green if
//    that number is implausibly small -- a suite that measured nothing is not a
//    pass.
//-----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_bscan;

  //--------------------------------------------------------------------------
  // Contract constants. Section 4 instruction map, section 5 IDCODE.
  //--------------------------------------------------------------------------
  localparam int IR_W = 4;
  localparam logic [IR_W-1:0] I_EXTEST = 4'b0000;
  localparam logic [IR_W-1:0] I_SAMPLE = 4'b0001;  // SAMPLE_PRELOAD
  localparam logic [IR_W-1:0] I_IDCODE = 4'b0010;
  localparam logic [IR_W-1:0] I_CLAMP  = 4'b0011;
  localparam logic [IR_W-1:0] I_HIGHZ  = 4'b0100;
  localparam logic [IR_W-1:0] I_BYPASS = 4'b1111;

  // Contract section 5 spells the value two ways and they disagree. The prose is
  // "version 1, part 0x0000, manufacturer 0x2D0>>1" over placeholder base
  // 32'h0000_05A1, which is IDCODE = 32'h1000_05A1. The literal it prints,
  // 32'h1_0000_05A1, is a 36-bit constant: SystemVerilog truncates it to
  // 32'h0000_05A1 and the version nibble is silently LOST. This bench expects
  // the intended value and, on mismatch, says which of the two it saw. See
  // README.md "Contract ambiguities" #1. Override with +idcode=<8 hex digits>.
  localparam logic [31:0] IDCODE_INTENDED  = 32'h1000_05A1;
  localparam logic [31:0] IDCODE_TRUNCATED = 32'h0000_05A1;
  logic [31:0] IDCODE_EXP = IDCODE_INTENDED;

  localparam int  MAXB        = 512;    // widest scan this bench performs
  localparam int  BYPASS_NB    = 24;    // T4 bits shifted through the bypass stage
  localparam int  CHAIN_TRAIL  = 96;    // T5 trailing bits, so the delay search has room
  localparam int  CHAIN_NTOT   = 76 + CHAIN_TRAIL;
  localparam time TCK_HALF    = 5ns;    // 100 MHz TCK
  localparam time COMB_SETTLE = 1ns;    // see note 3 in the header
  localparam time WATCHDOG    = 50ms;   // a hang must not read as a pass

  int NRAND = 200;                      // T1 random vectors (+nrand=N)
  int SEED  = 32'hB5CA_0001;            // (+seed=N)

  //--------------------------------------------------------------------------
  // Test access port
  //--------------------------------------------------------------------------
  logic tck    = 1'b0;
  logic tck_en = 1'b1;
  logic tms    = 1'b1;
  logic tdi    = 1'b0;
  logic trst_n = 1'b0;   // boundary scan DISABLED -- the functional default
  wire  tdo;
  wire  tdo_oe;

  // free-running TCK; tck_en=0 parks it low so T1 can prove the functional
  // path works with no clock at all.
  always begin
    #(TCK_HALF);
    if (tck_en) tck = ~tck;
  end

  // Pad arrays, chain map and the DUT instantiation -- generated from
  // src/rtl/bscan/pad_table.json by gen_tb_pads.py. Regenerated by run.sh on
  // every run, so a pad-table edit cannot leave this bench testing a stale ring.
  `include "tb_bscan_pads.svh"

  // Preponed sample of everything read cycle-accurately. See header note 3.
  default clocking cb @(posedge tck);
    default input #1step;
    input tdo;
    input tdo_oe;
    input pad_out;
    input pad_oe;
    input core_in;
  endclocking

  logic                tdo_s, tdo_oe_s;
  logic [N_PADS-1:0]   pad_out_s, pad_oe_s;

  //--------------------------------------------------------------------------
  // Scoreboard
  //--------------------------------------------------------------------------
  int    checks  = 0;      // individual comparisons performed
  int    fails   = 0;
  int    t_total = 0, t_failed = 0;
  string cur_test;
  int    cur_fails;

  task automatic test_begin(input string name);
    cur_test  = name;
    cur_fails = 0;
    t_total++;
    $display("");
    $display("--- %s", name);
  endtask

  task automatic test_end();
    if (cur_fails == 0) $display("    PASS  %s", cur_test);
    else begin
      t_failed++;
      $display("    FAIL  %s   (%0d failing comparison(s))", cur_test, cur_fails);
    end
  endtask

  // one comparison
  task automatic chk(input string what, input bit cond);
    checks++;
    if (!cond) begin
      fails++; cur_fails++;
      if (cur_fails <= 15)      $display("    FAIL: %s", what);
      else if (cur_fails == 16) $display("    ... further failures in this test suppressed");
    end
  endtask

  // one verdict that stands for `n` comparisons (hot loops: the detail is
  // printed by the caller, the count stays honest).
  task automatic chk_n(input string what, input bit cond, input int n);
    checks += n;
    if (!cond) begin
      fails++; cur_fails++;
      if (cur_fails <= 15)      $display("    FAIL: %s", what);
      else if (cur_fails == 16) $display("    ... further failures in this test suppressed");
    end
  endtask

  //--------------------------------------------------------------------------
  // JTAG primitives
  //--------------------------------------------------------------------------
  int ncyc = 0;
  int tdo_oe_low_in_shift = 0;   // 1149.1: TDO must be enabled while shifting

  // One TCK cycle: drive TMS/TDI on the falling edge, DUT samples on the rising
  // edge, and we take the preponed value of everything the DUT drove during the
  // cycle at that same rising edge.
  task automatic tick(input logic tms_v, input logic tdi_v = 1'b0);
    @(negedge tck);
    tms = tms_v;
    tdi = tdi_v;
    @(cb);
    tdo_s     = cb.tdo;
    tdo_oe_s  = cb.tdo_oe;
    pad_out_s = cb.pad_out;
    pad_oe_s  = cb.pad_oe;
    ncyc++;
  endtask

  // 1149.1: five consecutive TMS=1 reach Test-Logic-Reset from any state.
  task automatic tap_reset();
    repeat (5) tick(1'b1);
    tick(1'b0);            // TLR -> Run-Test/Idle
  endtask

  task automatic goto_shift_dr();     // from Run-Test/Idle
    tick(1'b1);                       // Select-DR-Scan
    tick(1'b0);                       // Capture-DR
    tick(1'b0);                       // Shift-DR
  endtask

  task automatic goto_shift_ir();     // from Run-Test/Idle
    tick(1'b1);                       // Select-DR-Scan
    tick(1'b1);                       // Select-IR-Scan
    tick(1'b0);                       // Capture-IR
    tick(1'b0);                       // Shift-IR
  endtask

  task automatic exit_to_rti();       // from Exit1-*
    tick(1'b1);                       // Update-*
    tick(1'b0);                       // Run-Test/Idle
  endtask

  // Shift n bits LSB-first. dout[i] is what TDO held during the cycle that
  // shifted din[i] in -- i.e. the pre-shift contents seen from the TDO end.
  // last_tms=1 leaves via Exit1-*; last_tms=0 stays in Shift-*.
  task automatic shift_bits(input  logic [MAXB-1:0] din,
                            input  int              n,
                            output logic [MAXB-1:0] dout,
                            input  bit              last_tms);
    dout = '0;
    for (int i = 0; i < n; i++) begin
      tick((i == n-1) ? last_tms : 1'b0, din[i]);
      dout[i] = tdo_s;
      if (tdo_oe_s !== 1'b1) tdo_oe_low_in_shift++;
    end
  endtask

  // Load an instruction. Returns the IR capture value shifted out on the way in
  // (1149.1 mandates the low two bits are 2'b01 -- contract section 4).
  task automatic load_ir(input logic [IR_W-1:0] instr, output logic [IR_W-1:0] cap);
    logic [MAXB-1:0] din, dout;
    din = '0;
    din[IR_W-1:0] = instr;
    goto_shift_ir();
    shift_bits(din, IR_W, dout, 1'b1);
    cap = dout[IR_W-1:0];
    exit_to_rti();
  endtask

  task automatic load_ir_q(input logic [IR_W-1:0] instr);
    logic [IR_W-1:0] cap;
    load_ir(instr, cap);
  endtask

  // Full DR scan from Run-Test/Idle back to Run-Test/Idle (through Update-DR).
  task automatic scan_dr(input  logic [MAXB-1:0] din,
                         input  int              n,
                         output logic [MAXB-1:0] dout);
    goto_shift_dr();
    shift_bits(din, n, dout, 1'b1);
    exit_to_rti();
  endtask

  //--------------------------------------------------------------------------
  // Helpers
  //--------------------------------------------------------------------------
  task automatic rnd_pads(output logic [N_PADS-1:0] v);
    v = {$urandom(), $urandom()};
  endtask

  task automatic rnd_bits(output logic [MAXB-1:0] v, input int n);
    v = '0;
    for (int i = 0; i < n; i++) v[i] = $urandom_range(0, 1);
  endtask

  // chain[c] (c=0 nearest TDI)  <->  shift order (bit 0 shifted first).
  // After N_CELLS shifts, din[j] lands at chain index N_CELLS-1-j.
  function automatic logic [MAXB-1:0] chain_to_shiftin(input logic [MAXB-1:0] chain);
    logic [MAXB-1:0] r;
    r = '0;
    for (int j = 0; j < N_CELLS; j++) r[j] = chain[N_CELLS-1-j];
    return r;
  endfunction

  function automatic logic [MAXB-1:0] chain_to_shiftout(input logic [MAXB-1:0] chain);
    logic [MAXB-1:0] r;
    r = '0;
    for (int k = 0; k < N_CELLS; k++) r[k] = chain[N_CELLS-1-k];
    return r;
  endfunction

  //--------------------------------------------------------------------------
  // T1  FUNCTIONAL TRANSPARENCY -- the one that matters
  //--------------------------------------------------------------------------
  // Compare the whole pad boundary against the core side, combinationally.
  task automatic check_transparent(input string tag);
    int bad;
    bad = 0;
    for (int p = 0; p < N_PADS; p++) begin
      if (MASK_HAS_DATA[p] && (pad_out[p] !== core_out[p])) begin
        bad++;
        if (bad <= 4) $display("      %s: pad[%0d] %s (%s): pad_out=%b core_out=%b",
                               tag, p, pad_name(p), "data", pad_out[p], core_out[p]);
      end
      if (MASK_HAS_OE[p] && (pad_oe[p] !== core_oe[p])) begin
        bad++;
        if (bad <= 4) $display("      %s: pad[%0d] %s (%s): pad_oe=%b core_oe=%b",
                               tag, p, pad_name(p), "oe", pad_oe[p], core_oe[p]);
      end
      if (MASK_HAS_OBS[p] && (core_in[p] !== pin_in[p])) begin
        bad++;
        if (bad <= 4) $display("      %s: pad[%0d] %s (%s): core_in=%b pin_in=%b",
                               tag, p, pad_name(p), "obs", core_in[p], pin_in[p]);
      end
    end
    // 28 data + 15 oe + 33 obs = 76 signal comparisons per vector.
    chk_n($sformatf("%s: %0d of 76 boundary signals not transparent", tag, bad),
          bad == 0, 76);
  endtask

  task automatic drive_pads_random();
    rnd_pads(core_out);
    rnd_pads(core_oe);
    rnd_pads(pin_in);
  endtask

  task automatic test1_transparency();
    test_begin("T1  functional transparency with boundary scan DISABLED (trst_n=0)");
    trst_n = 1'b0;
    tck_en = 1'b1;

    // (a) TCK running, and TMS/TDI wiggling randomly: a disabled TAP must be
    //     unwakeable, so none of that may reach the functional path.
    for (int v = 0; v < NRAND; v++) begin
      @(negedge tck);
      drive_pads_random();
      tms = $urandom_range(0, 1);
      tdi = $urandom_range(0, 1);
      #(COMB_SETTLE);
      check_transparent($sformatf("vec %0d mid-low-phase", v));
      chk($sformatf("vec %0d: tdo_oe must stay 0 while bscan is disabled", v),
          tdo_oe === 1'b0);
      @(posedge tck);          // and it must survive a TCK edge unchanged
      #(COMB_SETTLE);
      check_transparent($sformatf("vec %0d after posedge tck", v));
    end

    // (b) corners
    @(negedge tck); core_out = '0;  core_oe = '0;  pin_in = '0;
    #(COMB_SETTLE); check_transparent("all-zero");
    @(negedge tck); core_out = '1;  core_oe = '1;  pin_in = '1;
    #(COMB_SETTLE); check_transparent("all-one");

    // (c) TCK STOPPED. If any part of the functional path were clocked by TCK
    //     -- a mux-D cell wired the wrong way round, an accidental flop -- the
    //     pads would freeze here. This is the sub-test that proves the path is
    //     genuinely combinational.
    @(negedge tck);
    tck_en = 1'b0;             // parks TCK low
    for (int v = 0; v < 32; v++) begin
      drive_pads_random();
      #(COMB_SETTLE);
      check_transparent($sformatf("tck-stopped vec %0d", v));
    end
    tck_en = 1'b1;
    test_end();
  endtask

  //--------------------------------------------------------------------------
  // T2  TAP RESET
  //--------------------------------------------------------------------------
  task automatic test2_tap_reset();
    logic [IR_W-1:0] cap;
    logic [MAXB-1:0] din, dout;
    logic [31:0]     got;

    test_begin("T2  TAP reset: 5x TMS=1 reaches Test-Logic-Reset, instruction = IDCODE");
    trst_n = 1'b1;
    tap_reset();

    // Put something OTHER than IDCODE in the IR, so "the DR is 32 bits of
    // IDCODE" afterwards can only be explained by a real reset.
    load_ir(I_BYPASS, cap);
    chk($sformatf("Capture-IR loads ...01 (1149.1 mandatory); got 4'b%b", cap),
        cap[1:0] === 2'b01);

    // Walk to an arbitrary, deliberately awkward state: Pause-DR.
    goto_shift_dr();
    tick(1'b1);                // Exit1-DR
    tick(1'b0);                // Pause-DR   <-- arbitrary start state

    repeat (5) tick(1'b1);     // must reach Test-Logic-Reset from ANY state
    tick(1'b0);                // TLR -> Run-Test/Idle

    // If TLR was reached AND the IR reset to IDCODE, the DR is now the 32-bit
    // ID register. If it were not, the DR would still be the 1-bit BYPASS.
    rnd_bits(din, 32);
    scan_dr(din, 32, dout);
    got = dout[31:0];
    chk($sformatf("after 5x TMS=1 the DR is IDCODE: got 32'h%08h, expected 32'h%08h",
                  got, IDCODE_EXP), got === IDCODE_EXP);
    if (got !== IDCODE_EXP) begin
      if (got === {din[30:0], 1'b0}) begin
        $display("      DIAGNOSIS: the DR behaved as a 1-bit BYPASS register -- the");
        $display("                 instruction did NOT reset to IDCODE on entering TLR.");
        $display("                 bscan_ir has no tlr input in contract section 4; the");
        $display("                 wrapper must gate the IR's reset with the TAP's tlr");
        $display("                 output. See README.md ambiguity #2.");
      end
      if (got === IDCODE_TRUNCATED) begin
        $display("      DIAGNOSIS: got the contract's TRUNCATED literal 32'h0000_05A1 --");
        $display("                 see README.md ambiguity #1 (version nibble lost).");
      end
    end
    test_end();
  endtask

  //--------------------------------------------------------------------------
  // T3  IDCODE SHIFT-OUT
  //--------------------------------------------------------------------------
  task automatic test3_idcode();
    logic [MAXB-1:0] din, dout;
    logic [31:0]     got, echo;

    test_begin("T3  IDCODE: 32 bits out of DR after reset, LSB=1");
    trst_n = 1'b1;
    tap_reset();

    // 64 bits, not 32. The first 32 are the captured IDCODE; the second 32 must
    // be the bits WE shifted in, which proves the ID register is a real 32-stage
    // shift register and not a 32-bit constant muxed onto TDO.
    rnd_bits(din, 64);
    scan_dr(din, 64, dout);
    got  = dout[31:0];
    echo = dout[63:32];

    $display("      IDCODE read back: 32'h%08h   (expected 32'h%08h)", got, IDCODE_EXP);
    chk($sformatf("IDCODE LSB must be 1 (1149.1); got %b", got[0]), got[0] === 1'b1);
    chk($sformatf("IDCODE = 32'h%08h, expected 32'h%08h", got, IDCODE_EXP),
        got === IDCODE_EXP);
    chk($sformatf("ID register is 32 stages: bits 32..63 echo TDI (got 32'h%08h, sent 32'h%08h)",
                  echo, din[31:0]), echo === din[31:0]);
    chk($sformatf("IDCODE version nibble = %h (0 means the contract's 36-bit literal was truncated)",
                  got[31:28]), got[31:28] === IDCODE_EXP[31:28]);
    if (got !== IDCODE_EXP && got === IDCODE_TRUNCATED) begin
      $display("      DIAGNOSIS: 32'h0000_05A1 is what SystemVerilog makes of the contract's");
      $display("                 32'h1_0000_05A1 -- a 36-bit literal truncated into 32 bits.");
      $display("                 The version nibble is gone. See README.md ambiguity #1.");
    end
    test_end();
  endtask

  //--------------------------------------------------------------------------
  // T4  BYPASS
  //--------------------------------------------------------------------------
  task automatic test4_bypass();
    logic [MAXB-1:0] din, dout;
    int bad;

    test_begin("T4  BYPASS: DR is exactly one stage (TDI reappears one TCK later)");
    trst_n = 1'b1;
    tap_reset();
    load_ir_q(I_BYPASS);

    rnd_bits(din, BYPASS_NB);
    scan_dr(din, BYPASS_NB, dout);

    chk($sformatf("Capture-DR loads 0 into BYPASS (1149.1); first bit out = %b", dout[0]),
        dout[0] === 1'b0);
    bad = 0;
    for (int i = 1; i < BYPASS_NB; i++)
      if (dout[i] !== din[i-1]) begin
        bad++;
        if (bad <= 4) $display("      bit %0d: out=%b expected din[%0d]=%b",
                               i, dout[i], i-1, din[i-1]);
      end
    chk_n($sformatf("BYPASS delay is exactly 1 TCK over %0d bits (%0d mismatches)", BYPASS_NB-1, bad),
          bad == 0, BYPASS_NB-1);
    // A 0-stage bypass (TDO fed straight from TDI) would give dout==din. Say so
    // explicitly rather than leaving it to the loop.
    chk("BYPASS is not zero-delay (out != in)", dout[BYPASS_NB-1:0] !== din[BYPASS_NB-1:0]);
    test_end();
  endtask

  //--------------------------------------------------------------------------
  // T5  CHAIN INTEGRITY / LENGTH == 76
  //--------------------------------------------------------------------------
  task automatic test5_chain();
    logic [MAXB-1:0] din, dout, walk;
    int    nmatch, d_found, bad, wbad;
    bit    ok;

    test_begin("T5  chain integrity: the boundary register is exactly 76 cells");
    trst_n = 1'b1;
    tap_reset();
    load_ir_q(I_SAMPLE);

    chk($sformatf("pad table geometry: N_CELLS=%0d, contract section 1 says 76", N_CELLS),
        N_CELLS == 76);

    // (a) Pseudo-random pattern, then SEARCH for the delay at which it
    //     reappears. Asserting "it comes back after 76" is weak -- it passes for
    //     a 75-cell chain too if you only look at offset 76. Searching every
    //     alignment and demanding EXACTLY ONE, AT 76, is what pins the length.
    rnd_bits(din, CHAIN_NTOT);
    scan_dr(din, CHAIN_NTOT, dout);

    nmatch = 0; d_found = -1;
    for (int d = 1; d <= CHAIN_NTOT - N_CELLS; d++) begin
      ok = 1;
      for (int j = 0; j < N_CELLS; j++)
        if (dout[d+j] !== din[j]) begin ok = 0; break; end
      if (ok) begin
        nmatch++;
        if (d_found < 0) d_found = d;
      end
    end
    $display("      PRBS re-emerges at delay %0d (searched 1..%0d, %0d alignment(s) matched)",
             d_found, CHAIN_NTOT - N_CELLS, nmatch);
    chk($sformatf("the 76-bit pattern re-emerges after exactly 76 TCK (found %0d)", d_found),
        d_found == N_CELLS);
    chk($sformatf("exactly one alignment matches (found %0d)", nmatch), nmatch == 1);
    if (d_found >= 0 && d_found != N_CELLS) begin
      $display("      DIAGNOSIS: delay %0d means the chain has %0d cells, not %0d -- %0d cell(s) %s.",
               d_found, d_found, N_CELLS,
               (d_found > N_CELLS) ? d_found - N_CELLS : N_CELLS - d_found,
               (d_found > N_CELLS) ? "duplicated/extra" : "dropped");
    end

    // (b) walking-1 through every one of the 76 positions: catches a single cell
    //     stuck at 0 or 1, or a cell whose si/so is crossed, which a PRBS with
    //     the right length could still slide past.
    wbad = 0;
    for (int p = 0; p < N_CELLS; p++) begin
      walk = '0;
      walk[p] = 1'b1;
      scan_dr(walk, 2*N_CELLS, dout);
      for (int j = 0; j < N_CELLS; j++)
        if (dout[N_CELLS+j] !== walk[j]) begin
          wbad++;
          if (wbad <= 6)
            $display("      walking-1 at %0d: out bit %0d = %b, expected %b",
                     p, j, dout[N_CELLS+j], walk[j]);
        end
    end
    chk_n($sformatf("walking-1 through all %0d cells (%0d bit mismatches)", N_CELLS, wbad),
          wbad == 0, N_CELLS*N_CELLS);
    test_end();
  endtask

  //--------------------------------------------------------------------------
  // T6  SAMPLE
  //--------------------------------------------------------------------------
  task automatic test6_sample();
    logic [MAXB-1:0] din, dout, exp_chain, exp_out;
    int bad, p, c;

    test_begin("T6  SAMPLE: every cell captures its own signal, in ring order");
    trst_n = 1'b1;
    tap_reset();
    load_ir_q(I_SAMPLE);

    for (int v = 0; v < 6; v++) begin
      @(negedge tck);
      drive_pads_random();          // held stable across Capture-DR and the shift

      exp_chain = '0;
      for (int c = 0; c < N_CELLS; c++) begin
        p = CELL_PAD[c];
        case (CELL_TYPE[c])
          CELL_OBS : exp_chain[c] = pin_in[p];
          CELL_DATA: exp_chain[c] = core_out[p];
          default  : exp_chain[c] = core_oe[p];
        endcase
      end
      exp_out = chain_to_shiftout(exp_chain);

      rnd_bits(din, N_CELLS);
      scan_dr(din, N_CELLS, dout);

      bad = 0;
      for (int k = 0; k < N_CELLS; k++)
        if (dout[k] !== exp_out[k]) begin
          c = N_CELLS - 1 - k;      // chain index (0 nearest TDI)
          bad++;
          if (bad <= 6)
            $display("      vec %0d: shift-out bit %0d = chain cell %0d = pad[%0d] %s %s: got %b expected %b",
                     v, k, c, CELL_PAD[c], pad_name(CELL_PAD[c]), cell_name(c),
                     dout[k], exp_out[k]);
        end
      chk_n($sformatf("vec %0d: all %0d cells captured the right signal (%0d wrong)",
                      v, N_CELLS, bad), bad == 0, N_CELLS);
    end
    test_end();
  endtask

  //--------------------------------------------------------------------------
  // T7  EXTEST DRIVE
  //--------------------------------------------------------------------------
  logic [MAXB-1:0] p_chain, p_shift;   // shared with T10
  logic [N_PADS-1:0] p_data, p_oe;

  // Build a preload pattern that differs from the functional value on EVERY
  // controllable pad, so "the pads changed" and "the pads did not change" are
  // both unambiguous.
  task automatic build_preload();
    int p;
    p_chain = '0;
    p_data  = '0;
    p_oe    = '0;
    for (int c = 0; c < N_CELLS; c++) begin
      p = CELL_PAD[c];
      case (CELL_TYPE[c])
        CELL_OBS : p_chain[c] = $urandom_range(0, 1);
        CELL_DATA: begin p_chain[c] = ~core_out[p]; p_data[p] = ~core_out[p]; end
        default  : begin p_chain[c] = ~core_oe[p];  p_oe[p]   = ~core_oe[p];  end
      endcase
    end
    p_shift = chain_to_shiftin(p_chain);
  endtask

  task automatic check_driven_from_update(input string tag);
    int bad;
    bad = 0;
    for (int p = 0; p < N_PADS; p++) begin
      if (MASK_HAS_DATA[p] && (pad_out[p] !== p_data[p])) begin
        bad++;
        if (bad <= 4) $display("      %s: pad[%0d] %s pad_out=%b, update flop holds %b (core_out=%b)",
                               tag, p, pad_name(p), pad_out[p], p_data[p], core_out[p]);
      end
      if (MASK_HAS_OE[p] && (pad_oe[p] !== p_oe[p])) begin
        bad++;
        if (bad <= 4) $display("      %s: pad[%0d] %s pad_oe=%b, update flop holds %b (core_oe=%b)",
                               tag, p, pad_name(p), pad_oe[p], p_oe[p], core_oe[p]);
      end
    end
    chk_n($sformatf("%s: all 43 driven signals come from the update flops (%0d wrong)", tag, bad),
          bad == 0, 43);
  endtask

  task automatic test7_extest();
    logic [MAXB-1:0] dout;
    int bad;

    test_begin("T7  EXTEST: pads driven from the update flops, core ignored");
    trst_n = 1'b1;
    tap_reset();

    @(negedge tck);
    drive_pads_random();
    build_preload();

    // Preload through SAMPLE_PRELOAD. mode is still 0 here, so this must NOT
    // move a single pad -- PRELOAD that disturbs the pads is a live-system hazard.
    load_ir_q(I_SAMPLE);
    scan_dr(p_shift, N_CELLS, dout);
    #(COMB_SETTLE);
    check_transparent("after PRELOAD, before EXTEST");

    // Now switch to EXTEST: mode=1.
    load_ir_q(I_EXTEST);
    @(negedge tck); #(COMB_SETTLE);
    check_driven_from_update("EXTEST");

    // ...and the core must now be ignored. Drive a completely fresh core vector;
    // the pads must not move at all.
    @(negedge tck);
    rnd_pads(core_out);
    rnd_pads(core_oe);
    #(COMB_SETTLE);
    check_driven_from_update("EXTEST after the core changed");

    // The observe path is unaffected: INTEST is not supported, so core_in still
    // follows pin_in even in EXTEST (contract section 6).
    bad = 0;
    for (int p = 0; p < N_PADS; p++)
      if (MASK_HAS_OBS[p] && (core_in[p] !== pin_in[p])) begin
        bad++;
        if (bad <= 4) $display("      EXTEST: pad[%0d] %s core_in=%b pin_in=%b",
                               p, pad_name(p), core_in[p], pin_in[p]);
      end
    chk_n($sformatf("EXTEST leaves the observe path transparent (%0d wrong)", bad), bad == 0, 33);

    // And leaving EXTEST must hand the pads straight back to the core.
    tap_reset();
    @(negedge tck); #(COMB_SETTLE);
    check_transparent("after leaving EXTEST via TLR");
    test_end();
  endtask

  //--------------------------------------------------------------------------
  // T8  OPEN-DRAIN SAFETY  (contract section 1 -- "non-negotiable")
  //--------------------------------------------------------------------------
  task automatic test8_opendrain();
    logic [MAXB-1:0] dout, a_chain, b_chain, a_shift, b_shift;
    logic [N_PADS-1:0] oe_a, oe_b;
    int   ncell, ndata, obs_c, oe_c, p2;
    logic v;

    test_begin("T8  open-drain I2C pads: no data path at all, EXTEST reaches only the OE");
    trst_n = 1'b1;

    // (a) STRUCTURAL, over the generated chain map. An open-drain pad gets one
    //     obs cell and one oe ctl cell -- and NO data cell, because .I is a
    //     structural tie-low. A data cell here is a 16 mA push-pull driver on a
    //     wired-AND bus: a cross-die short no tool warns about.
    //     (The absence of the *ports* is gated statically by gen_tb_pads.py,
    //     which fails the build if the wrapper declares I2C_*_pad_out /
    //     I2C_*_core_out. A running TB cannot see a port it does not connect.)
    for (int p = 0; p < N_PADS; p++) begin
      if (!MASK_OPENDRAIN[p]) continue;
      ncell = 0; ndata = 0; obs_c = -1; oe_c = -1;
      for (int c = 0; c < N_CELLS; c++)
        if (CELL_PAD[c] == p) begin
          ncell++;
          if (CELL_TYPE[c] == CELL_DATA) ndata++;
          if (CELL_TYPE[c] == CELL_OBS)  obs_c = c;
          if (CELL_TYPE[c] == CELL_OE)   oe_c  = c;
        end
      chk($sformatf("%s has exactly 2 BSR cells (got %0d)", pad_name(p), ncell), ncell == 2);
      chk($sformatf("%s has NO data cell (got %0d)", pad_name(p), ndata), ndata == 0);
      chk($sformatf("%s has an obs cell (chain %0d) and an oe ctl cell (chain %0d)",
                    pad_name(p), obs_c, oe_c), (obs_c >= 0) && (oe_c >= 0));
      chk($sformatf("%s owns no core_out/pad_out port group", pad_name(p)),
          MASK_HAS_DATA[p] === 1'b0);
      chk($sformatf("%s owns core_oe/pad_oe", pad_name(p)), MASK_HAS_OE[p] === 1'b1);
    end

    // (b) DYNAMIC. Two EXTEST preloads that differ ONLY in the two I2C OBS bits
    //     must leave pad_oe identical: the observe cell has no drive path.
    //     Two that differ ONLY in the two I2C OE bits must flip pad_oe.
    tap_reset();
    @(negedge tck);
    drive_pads_random();

    a_chain = '0; b_chain = '0; oe_a = '0; oe_b = '0;
    for (int c = 0; c < N_CELLS; c++) begin
      p2 = CELL_PAD[c];
      v  = $urandom_range(0, 1);
      a_chain[c] = v;
      b_chain[c] = v;
      if (MASK_OPENDRAIN[p2] && CELL_TYPE[c] == CELL_OBS) b_chain[c] = ~v;  // obs differs
      if (CELL_TYPE[c] == CELL_OE) begin
        oe_a[p2] = a_chain[c];
        oe_b[p2] = b_chain[c];
      end
    end
    a_shift = chain_to_shiftin(a_chain);
    b_shift = chain_to_shiftin(b_chain);

    load_ir_q(I_SAMPLE);
    scan_dr(a_shift, N_CELLS, dout);
    load_ir_q(I_EXTEST);
    @(negedge tck); #(COMB_SETTLE);
    for (int p = 0; p < N_PADS; p++)
      if (MASK_OPENDRAIN[p])
        chk($sformatf("%s: EXTEST preload A drives pad_oe=%b (loaded %b)",
                      pad_name(p), pad_oe[p], oe_a[p]), pad_oe[p] === oe_a[p]);

    // flip only the obs bits
    load_ir_q(I_SAMPLE);
    scan_dr(b_shift, N_CELLS, dout);
    load_ir_q(I_EXTEST);
    @(negedge tck); #(COMB_SETTLE);
    for (int p = 0; p < N_PADS; p++)
      if (MASK_OPENDRAIN[p])
        chk($sformatf("%s: flipping ONLY the obs cell must not move pad_oe (got %b, still expect %b)",
                      pad_name(p), pad_oe[p], oe_b[p]), pad_oe[p] === oe_b[p]);

    // and the OE cell must genuinely control it: invert the loaded OE bits.
    a_chain = b_chain;
    for (int c = 0; c < N_CELLS; c++)
      if (MASK_OPENDRAIN[CELL_PAD[c]] && CELL_TYPE[c] == CELL_OE) begin
        a_chain[c] = ~b_chain[c];
        oe_a[CELL_PAD[c]] = ~oe_b[CELL_PAD[c]];
      end
    a_shift = chain_to_shiftin(a_chain);
    load_ir_q(I_SAMPLE);
    scan_dr(a_shift, N_CELLS, dout);
    load_ir_q(I_EXTEST);
    @(negedge tck); #(COMB_SETTLE);
    for (int p = 0; p < N_PADS; p++)
      if (MASK_OPENDRAIN[p])
        chk($sformatf("%s: the OE ctl cell does control pad_oe (got %b, expect %b)",
                      pad_name(p), pad_oe[p], oe_a[p]), pad_oe[p] === oe_a[p]);

    // and the pad-side observe path is untouched throughout.
    for (int p = 0; p < N_PADS; p++)
      if (MASK_OPENDRAIN[p])
        chk($sformatf("%s: core_in still follows pin_in in EXTEST", pad_name(p)),
            core_in[p] === pin_in[p]);

    tap_reset();
    test_end();
  endtask

  //--------------------------------------------------------------------------
  // T9  TAP HYGIENE -- tdo_oe is 1 in Shift-IR / Shift-DR ONLY (contract sec 3)
  //--------------------------------------------------------------------------
  // Matters at chip level: TDO is muxed onto the HOSTIO4_P1[1] output driver
  // (contract section 7). tdo_oe stuck high would contend with the functional
  // driver on a bonded pad.
  task automatic step_expect_oe(input logic tms_v, input string state, input logic exp_oe);
    tick(tms_v);
    chk($sformatf("tdo_oe in %s = %b, expected %b", state, tdo_oe_s, exp_oe),
        tdo_oe_s === exp_oe);
  endtask

  task automatic test9_tdo_oe();
    test_begin("T9  tdo_oe asserted in Shift-IR / Shift-DR only (contract section 3)");
    trst_n = 1'b1;
    tap_reset();                                     // ends in Run-Test/Idle

    // tick #k reports the state DURING cycle k, i.e. before that cycle's edge.
    step_expect_oe(1'b1, "Run-Test/Idle", 1'b0);     // -> Select-DR
    step_expect_oe(1'b0, "Select-DR-Scan", 1'b0);    // -> Capture-DR
    step_expect_oe(1'b0, "Capture-DR", 1'b0);        // -> Shift-DR
    step_expect_oe(1'b0, "Shift-DR", 1'b1);          // -> Shift-DR
    step_expect_oe(1'b1, "Shift-DR", 1'b1);          // -> Exit1-DR
    step_expect_oe(1'b0, "Exit1-DR", 1'b0);          // -> Pause-DR
    step_expect_oe(1'b1, "Pause-DR", 1'b0);          // -> Exit2-DR
    step_expect_oe(1'b1, "Exit2-DR", 1'b0);          // -> Update-DR
    step_expect_oe(1'b0, "Update-DR", 1'b0);         // -> Run-Test/Idle

    step_expect_oe(1'b1, "Run-Test/Idle", 1'b0);     // -> Select-DR
    step_expect_oe(1'b1, "Select-DR-Scan", 1'b0);    // -> Select-IR
    step_expect_oe(1'b0, "Select-IR-Scan", 1'b0);    // -> Capture-IR
    step_expect_oe(1'b0, "Capture-IR", 1'b0);        // -> Shift-IR
    step_expect_oe(1'b0, "Shift-IR", 1'b1);          // -> Shift-IR
    step_expect_oe(1'b1, "Shift-IR", 1'b1);          // -> Exit1-IR
    step_expect_oe(1'b1, "Exit1-IR", 1'b0);          // -> Update-IR
    step_expect_oe(1'b0, "Update-IR", 1'b0);         // -> Run-Test/Idle
    step_expect_oe(1'b0, "Run-Test/Idle", 1'b0);

    chk($sformatf("tdo_oe never dropped during a shift (%0d violations across the run)",
                  tdo_oe_low_in_shift), tdo_oe_low_in_shift == 0);
    tap_reset();
    test_end();
  endtask

  //--------------------------------------------------------------------------
  // T10  "EXACTLY FIVE" -- completes T2 with the one observable that can tell
  //      a real TLR from four TMS=1. Needs EXTEST, so it runs after T7.
  //--------------------------------------------------------------------------
  // With EXTEST active the pads are driven from the update flops; TLR resets the
  // instruction to IDCODE, mode drops, and the pads snap back to the core. That
  // transition is directly visible on pad_out, so we can see WHICH tick reset
  // the TAP -- which no DR/IR read can tell us, because every route back to a
  // DR read passes through TLR itself.
  task automatic test10_exactly_five();
    logic [MAXB-1:0] dout;
    int bad;

    test_begin("T10 five TMS=1 reset the TAP and four do NOT (observed on the pads)");
    trst_n = 1'b1;
    tap_reset();

    @(negedge tck);
    drive_pads_random();
    build_preload();                       // p_data/p_oe differ from the core everywhere

    load_ir_q(I_SAMPLE);
    scan_dr(p_shift, N_CELLS, dout);       // update flops <= P
    load_ir_q(I_EXTEST);
    @(negedge tck); #(COMB_SETTLE);
    check_driven_from_update("T10 precondition");

    // Re-enter the DR column and put P back into the SHIFT register too, so the
    // Update-DR we pass through on the way to TLR reloads the SAME value and
    // cannot be mistaken for a reset.
    //
    // Then park in PAUSE-DR, not Shift-DR. Both are 5 TMS=1 from
    // Test-Logic-Reset -- Pause-DR goes Exit2-DR, Update-DR, Select-DR,
    // Select-IR, TLR -- so Pause-DR is just as much a worst case. But in
    // Shift-DR the first TMS=1 tick is itself still a SHIFT cycle: the chain
    // would take one more bit of TDI before leaving, Update-DR would then load
    // P-shifted-by-one, and half the pads would move for a reason that has
    // nothing to do with the reset. Pause-DR holds the chain still.
    goto_shift_dr();
    shift_bits(p_shift, N_CELLS, dout, 1'b1);   // last bit exits to Exit1-DR
    tick(1'b0);                                 // Exit1-DR -> Pause-DR

    // tick #w samples the pads DURING cycle w, i.e. after w-1 TMS=1 steps.
    for (int w = 1; w <= 5; w++) begin
      tick(1'b1);
      bad = 0;
      for (int p = 0; p < N_PADS; p++) begin
        if (MASK_HAS_DATA[p] && (pad_out_s[p] !== p_data[p])) bad++;
        if (MASK_HAS_OE[p]   && (pad_oe_s[p]  !== p_oe[p]))   bad++;
      end
      chk_n($sformatf("after %0d TMS=1 the TAP is still in EXTEST (%0d pads already released)",
                      w-1, bad), bad == 0, 43);
    end

    // the 6th tick reports the state after the 5th TMS=1: Test-Logic-Reset.
    tick(1'b0);
    bad = 0;
    for (int p = 0; p < N_PADS; p++) begin
      if (MASK_HAS_DATA[p] && (pad_out_s[p] !== core_out[p])) bad++;
      if (MASK_HAS_OE[p]   && (pad_oe_s[p]  !== core_oe[p]))  bad++;
    end
    chk_n($sformatf("after 5 TMS=1 the TAP IS in Test-Logic-Reset and the pads are released (%0d still driven)",
                    bad), bad == 0, 43);
    if (bad != 0) begin
      $display("      DIAGNOSIS: entering TLR must reset the instruction to IDCODE, which");
      $display("                 drops mode. bscan_ir (contract section 4) has no tlr");
      $display("                 input -- the wrapper must gate its reset with the TAP's");
      $display("                 tlr output. See README.md ambiguity #2.");
    end

    tap_reset();
    test_end();
  endtask

  //--------------------------------------------------------------------------
  // Main
  //--------------------------------------------------------------------------
  initial begin : watchdog_proc
    #(WATCHDOG);
    $display("");
    $display("BSCAN_SUMMARY: FAIL checks=%0d fails=%0d tests=%0d/%0d reason=WATCHDOG",
             checks, fails+1, t_total-t_failed, t_total);
    $display("tb_bscan: WATCHDOG at %0t -- the bench hung. A hang is a FAILURE, not a pass.",
             $time);
    $finish;
  end

  initial begin : main
    void'($value$plusargs("seed=%d",   SEED));
    void'($value$plusargs("nrand=%d",  NRAND));
    void'($value$plusargs("idcode=%h", IDCODE_EXP));
    void'($urandom(SEED));

    $display("=============================================================================");
    $display(" tb_bscan -- IEEE 1149.1 boundary scan, nanosoc_eth_chiplet_bscan");
    $display("   pads=%0d  boundary cells=%0d  IR width=%0d", N_PADS, N_CELLS, IR_W);
    $display("   seed=%0d  nrand=%0d  expected IDCODE=32'h%08h", SEED, NRAND, IDCODE_EXP);
    $display("=============================================================================");

    core_out = '0; core_oe = '0; pin_in = '0;
    trst_n   = 1'b0;
    repeat (4) @(negedge tck);

    test1_transparency();
    test2_tap_reset();
    test3_idcode();
    test4_bypass();
    test5_chain();
    test6_sample();
    test7_extest();
    test8_opendrain();
    test9_tdo_oe();
    test10_exactly_five();

    // Finish where the chip lives: bscan off, pads transparent.
    trst_n = 1'b0;
    @(negedge tck);
    drive_pads_random();
    #(COMB_SETTLE);
    test_begin("T11 final: pads transparent again once trst_n returns low");
    check_transparent("post-suite");
    chk("tdo_oe low with bscan disabled", tdo_oe === 1'b0);
    test_end();

    $display("");
    $display("=============================================================================");
    $display(" tests: %0d run, %0d failed        comparisons: %0d, %0d failed",
             t_total, t_failed, checks, fails);
    $display(" TCK cycles: %0d", ncyc);
    $display("BSCAN_SUMMARY: %s checks=%0d fails=%0d tests=%0d/%0d",
             (fails == 0) ? "PASS" : "FAIL", checks, fails, t_total - t_failed, t_total);
    $display("=============================================================================");
    $finish;
  end

endmodule
