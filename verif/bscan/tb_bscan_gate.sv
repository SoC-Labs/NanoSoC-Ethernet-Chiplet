//-----------------------------------------------------------------------------
// verif/bscan/tb_bscan_gate.sv -- IEEE 1149.1 boundary scan shifted through the
// REAL GATES of the routed nanosoc_eth_chiplet_pads netlist.
// A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
//
// Contributors: SoC Labs verification
// Copyright 2026, SoC Labs (www.soclabs.org)
//-----------------------------------------------------------------------------
// WHAT THIS IS, AND HOW IT DIFFERS FROM tb_bscan.sv
//
// tb_bscan.sv drives nanosoc_eth_chiplet_bscan directly: 152 wrapper ports, one
// per pad group, every one of them observable. That bench proves the RTL. It
// cannot prove that synthesis, placement, CTS and routing preserved any of it.
//
// This bench has ONE contact surface: the 48 signal pads of the taped-out chip.
// Everything below is reached the way a bench-top JTAG master reaches it --
// through the pad cells, through the SE mux, through the TCK tree that CTS
// built, through the sequential cells Genus mapped and Innovus placed. There
// are no hierarchical references into the design anywhere in this file. That is
// deliberate: a probe at u_dut...u_bsc_75_TL_TX_7_data_update_q would prove the
// flop exists, not that it is REACHABLE from the package.
//
// THE PIN FACTS EVERYTHING RESTS ON (contract section 7):
//
//   SE = 1          releases trst_n. SE = 0 is the functional default and holds
//                   the whole TAP in Test-Logic-Reset.
//   SWDCK        -> TCK
//   SWDIO        -> TMS      (pad OEN forced high while SE=1: no contention)
//   HOSTIO4_P1[0]-> TDI      (likewise)
//   HOSTIO4_P1[1]<- TDO      (pad OEN = ~tdo_oe while SE=1)
//
// NRST IS HELD LOW FOR THE ENTIRE RUN, and the functional clock is parked for
// all of it except a warm-up. Boundary scan exists to test a chip that does not
// boot, so this bench never lets the core be alive. Everything the chain puts
// on a pad here came out of an update flop clocked by TCK; nothing in the core
// could have produced it.
//
// WHY TDO IS LEFT FLOATING
//
// The TB puts no pull on HOSTIO4_P1[1]. An un-enabled TDO is then a real z, so
// "TDO is driven" and "TDO reads 0" are distinguishable, and every tick of the
// run carries a free 1149.1 hygiene check: TDO must be driven in Shift-IR and
// Shift-DR and tri-state everywhere else. TDO shares a bonded functional output
// driver, so a stuck enable is pad contention on a real board, not a detail.
//
// TIMING DISCIPLINE
//
// Zero-delay run (+nospecify +notimingcheck), so the only races are the ones
// this file creates. TMS/TDI are driven T_DRV after the falling edge of TCK and
// the DUT samples them on the rising edge, exactly as a TAP master drives them.
// TDO and the pads are sampled T_SMP BEFORE the rising edge -- late in the low
// phase, after everything the previous rising edge started has settled, clear of
// both edges. That point is correct whether the wrapper retimes TDO onto the
// falling edge (1149.1 style, which the RTL does) or drives it combinationally
// from the shift flop: in the first case it is the value the negedge flop
// loaded, in the second it is the same shift-flop bit.
//
// EVERY CHECK MUST BE ABLE TO FAIL. verif/bscan/README.md, section
// "Gate-level", records what breaks each test and what each one cannot
// discriminate.
//-----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_bscan_gate;

  //--------------------------------------------------------------------------
  // Contract constants. Section 4 instruction map, section 5 IDCODE.
  //--------------------------------------------------------------------------
  localparam int IR_W = 4;
  localparam logic [IR_W-1:0] I_EXTEST = 4'b0000;
  localparam logic [IR_W-1:0] I_SAMPLE = 4'b0001;   // SAMPLE_PRELOAD
  localparam logic [IR_W-1:0] I_IDCODE = 4'b0010;
  localparam logic [IR_W-1:0] I_CLAMP  = 4'b0011;
  localparam logic [IR_W-1:0] I_BYPASS = 4'b1111;

  // 32'h1000_1001 -- version 1, part 0x0001, manufacturer 0x000, LSB 1. The
  // contract prints a 36-bit literal SystemVerilog truncates; see README.md
  // "Contract ambiguities" #1. Override with +idcode=<8 hex digits>.
  localparam logic [31:0] IDCODE_INTENDED  = 32'h1000_1001;
  localparam logic [31:0] IDCODE_TRUNCATED = 32'h0000_05A1;
  logic [31:0] IDCODE_EXP = IDCODE_INTENDED;

  localparam int N_CELLS     = 76;   // contract section 1: 18 + 15 + 13*3 + 2*2
  localparam int MAXB        = 256;  // widest scan this bench performs
  localparam int BYPASS_NB   = 32;
  localparam int CHAIN_TRAIL = 96;   // T3 trailing bits = the delay search range
  localparam int CHAIN_NTOT  = N_CELLS + CHAIN_TRAIL;

  localparam time TCK_HALF = 25ns;   // 20 MHz TCK. Zero-delay run, so the number
                                     // only sets what a shift costs in sim time.
  localparam time T_DRV    =  5ns;   // TMS/TDI driven this long after negedge
  localparam time T_SMP    =  5ns;   // TDO/pads sampled this long before posedge
  localparam time T_SETTLE = 20ns;   // combinational settle for an untimed peek
  localparam time WATCHDOG = 500ms;

  localparam int WARM_CYCLES = 256;  // functional-clock cycles in reset, SE=0

  int SEED = 32'h6E5C_A401;          // +seed=N

  //--------------------------------------------------------------------------
  // THE CHAIN MAP.
  //
  // Derived from src/rtl/bscan/pad_table.json by contract section 6: TDI enters
  // the cell of the pad with the LOWEST ring_index, TDO leaves the highest, and
  // within one pad the order from TDI is  oe ctl -> data ctl -> obs. Chain index
  // 0 is nearest TDI, 75 nearest TDO. (BSDL numbers these the other way round.)
  //
  // run_gate.sh RE-DERIVES every list below from pad_table.json on each run and
  // refuses to compile if they have drifted, so these literals cannot silently
  // stop describing the ring the netlist was generated from.
  //--------------------------------------------------------------------------

  // The 15 plain-output pads: one data ctl cell each, and the only driven cells
  // observable at the package in EXTEST. HOSTIO4_P1[1]'s data cell is NOT among
  // them -- while SE=1 that pad's driver belongs to TDO.
  localparam int NOUT = 15;
  localparam int OUT_CELL [0:NOUT-1] = '{33,34,35,39,40,41,67,68,69,70,71,72,73,74,75};

  // The input-pad obs cells this bench can hold at a known value. NRST(0),
  // TEST(3) and SE(4) are constant for the whole run by construction; the other
  // 13 take fresh vectors.
  localparam int NIN = 16;
  localparam int IN_CELL [0:NIN-1] = '{0,3,4,29,36,37,38,54,55,56,57,58,59,60,61,62};

  // OE ctl cells. The 13 bidirs take OEN = ~pad_oe, so 0 tri-states them; the
  // two open-drain I2C pads take OEN = pad_oe DIRECTLY (contract section 1, the
  // wired-AND rule), so 1 tri-states those. Getting this backwards in a preload
  // would put a 16 mA push-pull driver onto a wired-AND bus.
  localparam int NBOE = 13;
  localparam int BIDIR_OE_CELL [0:NBOE-1] = '{5,8,11,14,17,20,23,26,30,42,45,48,51};
  localparam int I2C_OE_CELL   [0:1]      = '{63,65};

  // QSPI_IO[3:0], index = pin bit: the four bidirs whose oe AND data cells are
  // both reachable at the package.
  localparam int QSPI_OE_CELL   [0:3] = '{51,48,45,42};
  localparam int QSPI_DATA_CELL [0:3] = '{52,49,46,43};

  //--------------------------------------------------------------------------
  // The chip. 48 signal pads, 4 supplies, nothing else.
  //--------------------------------------------------------------------------
  logic tck_r   = 1'b0;
  logic tms_r   = 1'b1;
  logic tdi_r   = 1'b0;
  logic se_r    = 1'b0;      // boundary scan DISABLED: trst_n low
  logic tap_drv = 1'b0;      // TB releases SWDIO / HOSTIO4_P1[0] until it is safe
  logic clk_r   = 1'b0;
  bit   clk_en  = 1'b0;      // gates the functional clock generator
  bit   keep_clk= 1'b0;      // +clk: leave it running for the whole suite

  logic       rmii_crs_dv_r  = 1'b0;
  logic       rmii_ref_clk_r = 1'b0;
  logic [1:0] rmii_rxd_r     = 2'b00;
  logic       tl_clk_rx_r    = 1'b0;
  logic [7:0] tl_rx_r        = 8'h00;

  wire        SE           = se_r;
  wire        CLK          = clk_r;
  wire        TEST         = 1'b0;
  wire        NRST         = 1'b0;      // THE CORE IS DEAD FOR THE WHOLE RUN
  wire        SWDCK        = tck_r;
  wire        RMII_REF_CLK = rmii_ref_clk_r;
  wire [1:0]  RMII_RXD     = rmii_rxd_r;
  wire        RMII_CRS_DV  = rmii_crs_dv_r;
  wire        TL_CLK_RX    = tl_clk_rx_r;
  wire [7:0]  TL_RX        = tl_rx_r;
  wire        VDD          = 1'b1;
  wire        VDDIO        = 1'b1;
  wire        VSS          = 1'b0;
  wire        VSSIO        = 1'b0;

  // Bidirectional pads. Weak pulls model the board, exactly as the functional
  // gate bench does -- a floating inout is z, which is x at the first gate
  // downstream, and the design's own driver still wins whenever it drives.
  // HOSTIO4_P1[1] is the ONE deliberate exception: see the header.
  wire        SWDIO;
  wire [6:0]  HOSTIO4_P1;
  wire [3:0]  QSPI_IO;
  wire        RMII_MDIO;
  wire        I2C_SCL, I2C_SDA;

  // SWDIO can be taken as soon as the core is in reset -- its pad OEN is
  // ~soc_dap_swdoen, and reset leaves that tri-stated.
  //
  // HOSTIO4_P1[0] CANNOT. It is a functional bidir and the netlist's own reset
  // value ENABLES its driver, so a JTAG master that drove TDI onto it before SE
  // went high would be fighting a 16 mA output. MEASURED: the pad model prints
  // ++BUS CONFLICT++ on every TDI edge when the TB does exactly that. Its OEN is
  // forced high by the SE mux and only then, so the TB takes it on se_r and not
  // a moment sooner. This is a real-board sequencing rule, not a bench detail.
  assign SWDIO         = tap_drv ? tms_r : 1'bz;
  assign HOSTIO4_P1[0] = se_r    ? tdi_r : 1'bz;
  pullup (QSPI_IO[0]); pullup (QSPI_IO[1]); pullup (QSPI_IO[2]); pullup (QSPI_IO[3]);
  pullup (HOSTIO4_P1[2]); pullup (HOSTIO4_P1[3]); pullup (HOSTIO4_P1[4]);
  pullup (HOSTIO4_P1[5]); pullup (HOSTIO4_P1[6]);
  pullup (RMII_MDIO); pullup (I2C_SCL); pullup (I2C_SDA);

  wire        QSPI_SCLK, QSPI_nCS;
  wire [1:0]  RMII_TXD;
  wire        RMII_TX_EN, RMII_MDC;
  wire        TL_CLK_TX;
  wire [7:0]  TL_TX;

  wire        tdo = HOSTIO4_P1[1];

  nanosoc_eth_chiplet_pads u_dut (
    .SE           (SE),
    .CLK          (CLK),
    .TEST         (TEST),
    .NRST         (NRST),
    .SWDIO        (SWDIO),
    .SWDCK        (SWDCK),
    .QSPI_IO      (QSPI_IO),
    .QSPI_SCLK    (QSPI_SCLK),
    .QSPI_nCS     (QSPI_nCS),
    .HOSTIO4_P1   (HOSTIO4_P1),
    .RMII_REF_CLK (RMII_REF_CLK),
    .RMII_TXD     (RMII_TXD),
    .RMII_TX_EN   (RMII_TX_EN),
    .RMII_RXD     (RMII_RXD),
    .RMII_CRS_DV  (RMII_CRS_DV),
    .RMII_MDIO    (RMII_MDIO),
    .RMII_MDC     (RMII_MDC),
    .TL_CLK_TX    (TL_CLK_TX),
    .TL_TX        (TL_TX),
    .TL_CLK_RX    (TL_CLK_RX),
    .TL_RX        (TL_RX),
    .I2C_SCL      (I2C_SCL),
    .I2C_SDA      (I2C_SDA),
    .VDD          (VDD),
    .VDDIO        (VDDIO),
    .VSS          (VSS),
    .VSSIO        (VSSIO)
  );

  always #10 if (clk_en) clk_r = ~clk_r;    // 20 ns reference period

  //--------------------------------------------------------------------------
  // Pad accessors. Written out one case at a time, because the alternative is a
  // second copy of the pad table living in this file.
  //--------------------------------------------------------------------------
  function automatic string out_name(input int i);
    case (i)
      0: return "RMII_TX_EN";   1: return "RMII_TXD[1]"; 2: return "RMII_TXD[0]";
      3: return "RMII_MDC";     4: return "QSPI_nCS";    5: return "QSPI_SCLK";
      6: return "TL_TX[0]";     7: return "TL_TX[1]";    8: return "TL_TX[2]";
      9: return "TL_TX[3]";    10: return "TL_CLK_TX";  11: return "TL_TX[4]";
     12: return "TL_TX[5]";    13: return "TL_TX[6]";   14: return "TL_TX[7]";
      default: return "?";
    endcase
  endfunction

  function automatic logic out_pin(input int i);
    case (i)
      0: return RMII_TX_EN;   1: return RMII_TXD[1]; 2: return RMII_TXD[0];
      3: return RMII_MDC;     4: return QSPI_nCS;    5: return QSPI_SCLK;
      6: return TL_TX[0];     7: return TL_TX[1];    8: return TL_TX[2];
      9: return TL_TX[3];    10: return TL_CLK_TX;  11: return TL_TX[4];
     12: return TL_TX[5];    13: return TL_TX[6];   14: return TL_TX[7];
      default: return 1'bx;
    endcase
  endfunction

  function automatic string in_name(input int i);
    case (i)
      0: return "NRST";         1: return "TEST";         2: return "SE";
      3: return "RMII_CRS_DV";  4: return "RMII_RXD[1]";  5: return "RMII_RXD[0]";
      6: return "RMII_REF_CLK"; 7: return "TL_RX[0]";     8: return "TL_RX[1]";
      9: return "TL_RX[2]";    10: return "TL_RX[3]";    11: return "TL_CLK_RX";
     12: return "TL_RX[4]";    13: return "TL_RX[5]";    14: return "TL_RX[6]";
     15: return "TL_RX[7]";
      default: return "?";
    endcase
  endfunction

  // What the TB is HOLDING on that pin -- the value its obs cell must capture.
  function automatic logic in_val(input int i);
    case (i)
      0: return 1'b0;              // NRST, held low all run
      1: return 1'b0;              // TEST
      2: return 1'b1;              // SE, high whenever the TAP can be scanned
      3: return rmii_crs_dv_r;
      4: return rmii_rxd_r[1];     5: return rmii_rxd_r[0];
      6: return rmii_ref_clk_r;
      7: return tl_rx_r[0];        8: return tl_rx_r[1];
      9: return tl_rx_r[2];       10: return tl_rx_r[3];
     11: return tl_clk_rx_r;
     12: return tl_rx_r[4];       13: return tl_rx_r[5];
     14: return tl_rx_r[6];       15: return tl_rx_r[7];
      default: return 1'bx;
    endcase
  endfunction

  // vec bit b maps to IN_CELL[b+3] -- the first three obs cells are constants.
  task automatic drive_inputs(input logic [12:0] v);
    rmii_crs_dv_r  = v[0];
    rmii_rxd_r[1]  = v[1];
    rmii_rxd_r[0]  = v[2];
    rmii_ref_clk_r = v[3];
    tl_rx_r[0]     = v[4];
    tl_rx_r[1]     = v[5];
    tl_rx_r[2]     = v[6];
    tl_rx_r[3]     = v[7];
    tl_clk_rx_r    = v[8];
    tl_rx_r[4]     = v[9];
    tl_rx_r[5]     = v[10];
    tl_rx_r[6]     = v[11];
    tl_rx_r[7]     = v[12];
  endtask

  //--------------------------------------------------------------------------
  // Scoreboard
  //--------------------------------------------------------------------------
  int    checks = 0, fails = 0;
  int    t_total = 0, t_failed = 0;
  string cur_test = "(preamble)";
  int    cur_fails = 0;

  task automatic test_begin(input string name);
    cur_test = name; cur_fails = 0; t_total++;
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

  task automatic chk(input string what, input bit cond);
    checks++;
    if (!cond) begin
      fails++; cur_fails++;
      if (cur_fails <= 20)      $display("    FAIL: %s", what);
      else if (cur_fails == 21) $display("    ... further failures in this test suppressed");
    end
  endtask

  // One verdict standing for n comparisons: the detail is printed by the
  // caller, the count stays honest.
  task automatic chk_n(input string what, input bit cond, input int n);
    checks += n;
    if (!cond) begin
      fails++; cur_fails++;
      if (cur_fails <= 20)      $display("    FAIL: %s", what);
      else if (cur_fails == 21) $display("    ... further failures in this test suppressed");
    end
  endtask

  //--------------------------------------------------------------------------
  // JTAG primitives. Every edge below is a real edge on the SWDCK package pin.
  //--------------------------------------------------------------------------
  int  ncyc = 0;
  int  tdo_z_in_shift    = 0;  // TDO tri-stated while shifting  -> 1149.1 breach
  int  tdo_drv_off_shift = 0;  // TDO driven when it must not be -> pad contention
  int  tdo_hygiene_ticks = 0;
  bit  hygiene_on        = 1'b0;

  logic tdo_s;

  // ONE TCK CYCLE. Enter with TCK low, immediately after its falling edge.
  //   * TMS/TDI driven T_DRV into the low phase
  //   * TDO sampled T_SMP before the rising edge -- the value the DUT held for
  //     essentially the whole of this cycle
  //   * rising edge (DUT samples TMS/TDI and shifts), then falling edge
  // The sample therefore reports the state the TAP was IN during this cycle,
  // before this cycle's own edge advanced it.
  task automatic tick(input logic tms_v, input logic tdi_v = 1'b0,
                      input bit shifting = 1'b0);
    #(T_DRV);
    tms_r = tms_v;
    tdi_r = tdi_v;
    #(TCK_HALF - T_DRV - T_SMP);
    tdo_s = tdo;
    if (hygiene_on) begin
      tdo_hygiene_ticks++;
      if (shifting) begin
        if (tdo_s === 1'bz) begin
          tdo_z_in_shift++;
          if (tdo_z_in_shift <= 4)
            $display("      TDO-HYGIENE: TCK cycle %0d is a shift and TDO is tri-state", ncyc);
        end
      end else begin
        if (tdo_s !== 1'bz) begin
          tdo_drv_off_shift++;
          if (tdo_drv_off_shift <= 4)
            $display("      TDO-HYGIENE: TCK cycle %0d is not a shift and TDO reads %b",
                     ncyc, tdo_s);
        end
      end
    end
    #(T_SMP);
    tck_r = 1'b1;
    #(TCK_HALF);
    tck_r = 1'b0;
    ncyc++;
  endtask

  // 1149.1: five consecutive TMS=1 reach Test-Logic-Reset from any state.
  task automatic tap_reset();
    repeat (5) tick(1'b1);
    tick(1'b0);                       // TLR -> Run-Test/Idle
  endtask

  task automatic goto_shift_dr();     // from Run-Test/Idle
    tick(1'b1); tick(1'b0); tick(1'b0);
  endtask

  task automatic goto_shift_ir();     // from Run-Test/Idle
    tick(1'b1); tick(1'b1); tick(1'b0); tick(1'b0);
  endtask

  task automatic exit_to_rti();       // from Exit1-*
    tick(1'b1); tick(1'b0);
  endtask

  // Shift n bits LSB-first. dout[i] is what TDO held during the cycle that
  // shifted din[i] in, i.e. the pre-shift contents seen from the TDO end.
  task automatic shift_bits(input  logic [MAXB-1:0] din,
                            input  int              n,
                            output logic [MAXB-1:0] dout,
                            input  bit              last_tms);
    dout = '0;
    for (int i = 0; i < n; i++) begin
      tick((i == n-1) ? last_tms : 1'b0, din[i], 1'b1);
      dout[i] = tdo_s;
    end
  endtask

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

  // Full DR scan, Run-Test/Idle -> Run-Test/Idle, through Update-DR.
  task automatic scan_dr(input  logic [MAXB-1:0] din,
                         input  int              n,
                         output logic [MAXB-1:0] dout);
    goto_shift_dr();
    shift_bits(din, n, dout, 1'b1);
    exit_to_rti();
  endtask

  //--------------------------------------------------------------------------
  // Chain <-> shift order. din[j] lands at chain[N-1-j]; chain[c] emerges at
  // dout[N-1-c]. Same permutation both ways, which is why one helper serves.
  //--------------------------------------------------------------------------
  function automatic int shpos(input int c);
    return N_CELLS - 1 - c;
  endfunction

  function automatic logic [MAXB-1:0] chain_to_shift(input logic [N_CELLS-1:0] chain);
    logic [MAXB-1:0] r;
    r = '0;
    for (int c = 0; c < N_CELLS; c++) r[shpos(c)] = chain[c];
    return r;
  endfunction

  task automatic rnd_bits(output logic [MAXB-1:0] v, input int n);
    v = '0;
    for (int i = 0; i < n; i++) v[i] = $urandom_range(0, 1);
  endtask

  // An EXTEST preload skeleton with every OE cell set to the value that
  // TRI-STATES its pad, so nothing this bench loads can fight the board.
  function automatic logic [N_CELLS-1:0] safe_chain();
    logic [N_CELLS-1:0] c;
    c = '0;
    for (int i = 0; i < NBOE; i++) c[BIDIR_OE_CELL[i]] = 1'b0;  // OEN = ~oe
    for (int i = 0; i < 2;    i++) c[I2C_OE_CELL[i]]   = 1'b1;  // OEN =  oe
    return c;
  endfunction

  // Peek at the pads outside a tick, in the low phase, well clear of any edge.
  task automatic settle();
    #(T_SETTLE);
  endtask

  //==========================================================================
  // T0  SE = 0: THE TAP IS INERT.
  //
  //     The functional default, and the property the whole insertion is
  //     allowed to exist under. trst_n = SE, so with SE low the TAP is in
  //     Test-Logic-Reset and nothing on SWDCK/SWDIO/HOSTIO4_P1[0] may reach it.
  //     Drive a complete Shift-DR sequence at it and require HOSTIO4_P1[1] not
  //     to move: a TAP that answered would have taken the pad's driver.
  //
  //     What this does NOT check is the transparent-mode value of the pads.
  //     At the package, with the core in reset, that value is not specified by
  //     anything -- tb_bscan.sv's T1 owns transparency, where the core side is
  //     observable. See README.md, "Gate-level".
  //==========================================================================
  task automatic test0_se_low_inert();
    logic tdo_before;
    int   moved;

    test_begin("T0  SE=0: the TAP is inert and does not take HOSTIO4_P1[1]");
    settle();
    tdo_before = tdo;
    $display("      HOSTIO4_P1[1] with SE=0, core in reset: %b (observation, not a verdict)",
             tdo_before);

    moved = 0;
    goto_shift_dr();                      // would be Shift-DR IF the TAP were live
    for (int i = 0; i < 40; i++) begin
      tick(1'b0, $urandom_range(0, 1));
      if (tdo !== tdo_before) moved++;
    end
    tick(1'b1); tick(1'b1); tick(1'b0);   // unwind to something harmless
    chk_n($sformatf("40 Shift-DR cycles with SE=0 do not move HOSTIO4_P1[1] (%0d moved)", moved),
          moved == 0, 40);
    test_end();
  endtask

  //==========================================================================
  // T1  TAP RESET + IDCODE.  The one test that proves the TAP, the IR's
  //     reset-to-IDCODE and the whole TDO path work in real gates.
  //==========================================================================
  task automatic test1_reset_idcode();
    logic [IR_W-1:0] cap;
    logic [MAXB-1:0] din, dout;
    logic [31:0]     got, echo;

    test_begin("T1  TAP reset + IDCODE through the routed gates");

    // (a) Load BYPASS first, so "the DR is 32 bits of IDCODE" afterwards can
    //     ONLY be explained by a real reset. Without this the DR is already the
    //     ID register and the test proves nothing about reaching TLR.
    tap_reset();
    load_ir(I_BYPASS, cap);
    chk($sformatf("Capture-IR loads ...01 (1149.1 mandatory); got 4'b%b", cap),
        cap[1:0] === 2'b01);

    // (b) Park in Pause-DR -- deliberately awkward, and exactly five TMS=1 from
    //     Test-Logic-Reset (Exit2-DR, Update-DR, Select-DR, Select-IR, TLR).
    goto_shift_dr();
    // The TAP is IN Shift-DR during this tick -- TDO is legitimately driven for
    // it, so it is tagged as a shift cycle even though no data is being moved.
    tick(1'b1, 1'b0, 1'b1);       // -> Exit1-DR
    tick(1'b0);                   // -> Pause-DR
    repeat (5) tick(1'b1);        // five TMS=1 reach TLR from ANY state
    tick(1'b0);                   // TLR -> Run-Test/Idle

    // (c) 64 bits, not 32. The first 32 are the captured IDCODE; the second 32
    //     must echo what we shifted in, which proves the ID register is a real
    //     32-stage shift register in silicon and not a constant sat on TDO.
    rnd_bits(din, 64);
    scan_dr(din, 64, dout);
    got  = dout[31:0];
    echo = dout[63:32];

    $display("      IDCODE read back: 32'h%08h   (expected 32'h%08h)", got, IDCODE_EXP);
    chk($sformatf("IDCODE = 32'h%08h, expected 32'h%08h", got, IDCODE_EXP),
        got === IDCODE_EXP);
    chk($sformatf("IDCODE LSB must be 1 (1149.1); got %b", got[0]), got[0] === 1'b1);
    chk($sformatf("IDCODE version nibble = %h, expected %h", got[31:28], IDCODE_EXP[31:28]),
        got[31:28] === IDCODE_EXP[31:28]);
    chk($sformatf("ID register is 32 real stages: bits 32..63 echo TDI (got 32'h%08h, sent 32'h%08h)",
                  echo, din[31:0]), echo === din[31:0]);

    if (got !== IDCODE_EXP) begin
      if (got === {din[30:0], 1'b0})
        $display("      DIAGNOSIS: the DR behaved as a 1-bit BYPASS -- five TMS=1 did NOT reach TLR.");
      else if (got === IDCODE_TRUNCATED)
        $display("      DIAGNOSIS: the contract's TRUNCATED literal 32'h0000_05A1 (README #1).");
      else if (got === 32'h0000_0000 || got === 32'hFFFF_FFFF)
        $display("      DIAGNOSIS: a constant -- TDO is not connected to the ID register.");
      else if (^got === 1'bx)
        $display("      DIAGNOSIS: X on TDO -- the chain never left reset, or TCK is not arriving.");
    end
    test_end();
  endtask

  //==========================================================================
  // T2  BYPASS: the DR is exactly one stage.
  //==========================================================================
  task automatic test2_bypass();
    logic [MAXB-1:0] din, dout;
    int bad;

    test_begin("T2  BYPASS: TDI reappears delayed by exactly one TCK");
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
        if (bad <= 6) $display("      bit %0d: out=%b, expected din[%0d]=%b",
                               i, dout[i], i-1, din[i-1]);
      end
    chk_n($sformatf("BYPASS delay is exactly 1 TCK over %0d bits (%0d mismatches)",
                    BYPASS_NB-1, bad), bad == 0, BYPASS_NB-1);
    // A zero-stage bypass (TDO fed straight off TDI) gives dout == din. Name it
    // rather than leaving it to the loop above.
    chk("BYPASS is not zero-delay (out != in)",
        dout[BYPASS_NB-1:0] !== din[BYPASS_NB-1:0]);
    // Two stages is what the i=1 comparison catches; name that too, so a
    // two-stage failure reads as one thing and not as 31 mismatches.
    chk("BYPASS is not two-stage (the second bit out is din[0])", dout[1] === din[0]);
    test_end();
  endtask

  //==========================================================================
  // T3  CHAIN LENGTH == 76, ESTABLISHED BY SEARCH.
  //
  //     Shifting 76 bits and looking for them at offset 76 is a weak test: it
  //     passes for a 75-cell chain too, because the loop never looks anywhere
  //     else. So every alignment 1..96 is searched and EXACTLY ONE match, AT
  //     76, is required. Three independent patterns, because one PRBS that
  //     happened to be periodic would make several alignments match and that
  //     must not be mistaken for a broken chain.
  //==========================================================================
  task automatic test3_chain();
    logic [MAXB-1:0] din, dout;
    int    nmatch, d_found;
    bit    ok;

    test_begin("T3  chain integrity: the boundary register is exactly 76 cells");
    tap_reset();
    load_ir_q(I_SAMPLE);

    for (int rep = 0; rep < 3; rep++) begin
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
      $display("      pattern %0d: re-emerges at delay %0d (searched 1..%0d, %0d alignment(s) matched)",
               rep, d_found, CHAIN_NTOT - N_CELLS, nmatch);
      chk_n($sformatf("pattern %0d: the 76-bit pattern re-emerges after exactly 76 TCK (found %0d)",
                      rep, d_found), d_found == N_CELLS, N_CELLS);
      chk($sformatf("pattern %0d: exactly one alignment in 1..%0d matches (found %0d)",
                    rep, CHAIN_NTOT - N_CELLS, nmatch), nmatch == 1);
      if (d_found > 0 && d_found != N_CELLS)
        $display("      DIAGNOSIS: delay %0d means the chain has %0d cells, not %0d -- %0d cell(s) %s.",
                 d_found, d_found, N_CELLS,
                 (d_found > N_CELLS) ? d_found - N_CELLS : N_CELLS - d_found,
                 (d_found > N_CELLS) ? "extra" : "dropped");
      if (d_found < 0)
        $display("      DIAGNOSIS: the pattern never came back at ANY alignment in 1..%0d.",
                 CHAIN_NTOT - N_CELLS);
    end
    test_end();
  endtask

  //==========================================================================
  // T4  SAMPLE: the obs cells capture the real pins.
  //
  //     Each of the 16 reachable input-pad cells is checked INDIVIDUALLY at its
  //     own position in the shift-out stream, over four vectors including all-0
  //     and all-1. Then a per-pin walk: driving ONE pin must move exactly ONE
  //     cell, and it must be that pin's own. Two obs cells swapped between
  //     neighbouring pads survive the vector loop; they do not survive the walk.
  //==========================================================================
  task automatic test4_sample();
    logic [MAXB-1:0] din, dout, base_out, one_out;
    logic [12:0]     vec;
    int              bad, nmoved, moved_c, c;

    test_begin("T4  SAMPLE: input-pad cells capture the value held on the pin");
    tap_reset();

    for (int v = 0; v < 4; v++) begin
      case (v)
        0: vec = 13'h0000;
        1: vec = 13'h1FFF;
        default: vec = $urandom_range(0, 8191);
      endcase
      drive_inputs(vec);
      settle();

      // The instruction is reloaded per vector so that Capture-DR takes the
      // pins as they are AT THAT MOMENT: nothing carries over from the last
      // vector's shift.
      load_ir_q(I_SAMPLE);
      rnd_bits(din, N_CELLS);
      scan_dr(din, N_CELLS, dout);

      bad = 0;
      for (int i = 0; i < NIN; i++) begin
        c = IN_CELL[i];
        if (dout[shpos(c)] !== in_val(i)) begin
          bad++;
          if (bad <= 6)
            $display("      vec %0d: chain cell %0d (%s, obs) captured %b, the pin held %b",
                     v, c, in_name(i), dout[shpos(c)], in_val(i));
        end
      end
      chk_n($sformatf("vec %0d (13'h%04h): all %0d reachable obs cells captured their own pin (%0d wrong)",
                      v, vec, NIN, bad), bad == 0, NIN);
    end

    // Per-pin discrimination.
    drive_inputs(13'h0000);
    settle();
    load_ir_q(I_SAMPLE);
    rnd_bits(din, N_CELLS);
    scan_dr(din, N_CELLS, base_out);

    for (int b = 0; b < 13; b++) begin
      drive_inputs(13'b1 << b);
      settle();
      load_ir_q(I_SAMPLE);
      rnd_bits(din, N_CELLS);
      scan_dr(din, N_CELLS, one_out);

      nmoved = 0; moved_c = -1;
      for (int i = 0; i < NIN; i++) begin
        c = IN_CELL[i];
        if (one_out[shpos(c)] !== base_out[shpos(c)]) begin
          nmoved++;
          moved_c = c;
        end
      end
      chk($sformatf("driving only %s moves exactly its own cell %0d (moved %0d cell(s), last %0d)",
                    in_name(b+3), IN_CELL[b+3], nmoved, moved_c),
          (nmoved == 1) && (moved_c == IN_CELL[b+3]));
    end
    drive_inputs(13'h0000);
    test_end();
  endtask

  //==========================================================================
  // T5  EXTEST DRIVE, WITH THE CORE IN RESET.
  //
  //     Preload P, enter EXTEST, require all 15 output pads to read P; then
  //     preload ~P and require them to read ~P. Doing BOTH is what makes this
  //     impossible to pass by accident -- a bench that only ever loaded P could
  //     be reading a core output that happened to equal P, and with the core
  //     dead a stuck pad reads the same value whatever gets loaded.
  //==========================================================================
  logic [NOUT-1:0] p_out;

  task automatic preload_and_extest(input logic [N_CELLS-1:0] chain);
    logic [MAXB-1:0] dout;
    load_ir_q(I_SAMPLE);                       // PRELOAD: mode is still 0
    scan_dr(chain_to_shift(chain), N_CELLS, dout);
    load_ir_q(I_EXTEST);                       // mode -> 1 on Update-IR
    settle();
  endtask

  task automatic check_outputs(input string tag, input logic [NOUT-1:0] exp);
    int bad;
    bad = 0;
    for (int i = 0; i < NOUT; i++)
      if (out_pin(i) !== exp[i]) begin
        bad++;
        if (bad <= 6)
          $display("      %s: pad %s (chain cell %0d) reads %b, its update flop was loaded %b",
                   tag, out_name(i), OUT_CELL[i], out_pin(i), exp[i]);
      end
    chk_n($sformatf("%s: all %0d output pads driven from their update flops (%0d wrong)",
                    tag, NOUT, bad), bad == 0, NOUT);
  endtask

  task automatic test5_extest();
    logic [MAXB-1:0]    dout;
    logic [NOUT-1:0]    before_out;
    logic [N_CELLS-1:0] ch;
    int                 moved;

    test_begin("T5  EXTEST: output pads driven from the update flops, core in reset");
    tap_reset();

    // Snapshot the pads before anything is loaded. With NRST low and the
    // functional clock parked this is whatever the dead core leaves on them --
    // recorded, never asserted on, because a dead core's outputs are not a
    // specified value.
    settle();
    for (int i = 0; i < NOUT; i++) before_out[i] = out_pin(i);
    $display("      output pads before any EXTEST: %b   (core in reset; observation only)",
             before_out);

    // ---- pattern A --------------------------------------------------------
    p_out = 15'b010_1100_1010_0110;
    ch    = safe_chain();
    for (int i = 0; i < NOUT; i++) ch[OUT_CELL[i]] = p_out[i];

    // PRELOAD must not move a single pad: mode is still 0 under
    // SAMPLE_PRELOAD, and a preload that disturbs a live system is a hazard.
    load_ir_q(I_SAMPLE);
    scan_dr(chain_to_shift(ch), N_CELLS, dout);
    settle();
    moved = 0;
    for (int i = 0; i < NOUT; i++) if (out_pin(i) !== before_out[i]) moved++;
    chk_n($sformatf("PRELOAD under SAMPLE_PRELOAD moved no pad (%0d of %0d moved)", moved, NOUT),
          moved == 0, NOUT);

    load_ir_q(I_EXTEST);
    settle();
    check_outputs("EXTEST pattern A", p_out);

    // The functional clock is parked and stays parked, and the TAP now stands
    // still. An EXTEST value that decays is one that was never latched.
    #(200ns);
    check_outputs("EXTEST pattern A, 200 ns later with TCK idle", p_out);

    // ---- pattern B = ~A ---------------------------------------------------
    p_out = ~p_out;
    ch    = safe_chain();
    for (int i = 0; i < NOUT; i++) ch[OUT_CELL[i]] = p_out[i];
    preload_and_extest(ch);
    check_outputs("EXTEST pattern B = ~A", p_out);

    // ---- walking-1 over all 15, so no single pad can be stuck and hide ----
    for (int w = 0; w < NOUT; w++) begin
      p_out = '0;
      p_out[w] = 1'b1;
      ch = safe_chain();
      for (int i = 0; i < NOUT; i++) ch[OUT_CELL[i]] = p_out[i];
      preload_and_extest(ch);
      check_outputs($sformatf("EXTEST walking-1 at %s", out_name(w)), p_out);
    end

    // ---- the OE cells reach the real pad OEN logic ------------------------
    // QSPI_IO[3:0] are the four bidirs whose oe AND data cells are both
    // reachable at the package. Drive 4'b1010 with the OE cells asserted, then
    // release them and require the pins to fall back to the bench's weak
    // pull-ups. An OE cell that did nothing fails one of the two.
    ch = safe_chain();
    for (int i = 0; i < NOUT; i++) ch[OUT_CELL[i]] = 1'b0;
    for (int b = 0; b < 4; b++) begin
      ch[QSPI_OE_CELL[b]]   = 1'b1;               // OEN = ~oe -> the pad drives
      ch[QSPI_DATA_CELL[b]] = (b % 2) == 1;       // 4'b1010
    end
    preload_and_extest(ch);
    chk($sformatf("EXTEST drives QSPI_IO = 4'b1010 (got 4'b%b)", QSPI_IO),
        QSPI_IO === 4'b1010);

    for (int b = 0; b < 4; b++) ch[QSPI_OE_CELL[b]] = 1'b0;    // release
    preload_and_extest(ch);
    chk($sformatf("releasing the QSPI_IO oe cells hands the pins to the pull-ups (got 4'b%b)",
                  QSPI_IO), QSPI_IO === 4'b1111);

    // ---- and leaving EXTEST releases the pads -----------------------------
    // Test-Logic-Reset resets the instruction to IDCODE, mode drops, and the
    // pads stop reporting the update flops. With the core dead there is no
    // specified value to land on, so the assertion is that at least one pad
    // LEAVES the pattern -- which a stuck mode bit cannot do.
    ch = safe_chain();
    for (int i = 0; i < NOUT; i++) ch[OUT_CELL[i]] = 1'b1;
    preload_and_extest(ch);
    check_outputs("EXTEST all-ones, precondition for the release check", {NOUT{1'b1}});
    tap_reset();
    settle();
    moved = 0;
    for (int i = 0; i < NOUT; i++) if (out_pin(i) !== 1'b1) moved++;
    chk($sformatf("Test-Logic-Reset releases the pads from EXTEST (%0d of %0d pads left the pattern)",
                  moved, NOUT), moved > 0);
    if (moved == 0) begin
      $display("      DIAGNOSIS: every pad still carries the EXTEST pattern after TLR. Either");
      $display("                 the instruction did not reset to IDCODE, or the dead core");
      $display("                 drives all-ones -- compare the pre-EXTEST snapshot above.");
    end
    test_end();
  endtask

  //==========================================================================
  // Main
  //==========================================================================
  initial begin : watchdog_proc
    #(WATCHDOG);
    $display("");
    $display("BSCAN_GATE_SUMMARY: FAIL checks=%0d fails=%0d tests=%0d/%0d reason=WATCHDOG",
             checks, fails+1, t_total-t_failed, t_total);
    $display("tb_bscan_gate: WATCHDOG at %0t -- the bench hung. A hang is a FAILURE.", $time);
    $finish;
  end

  initial begin : main
    void'($value$plusargs("seed=%d",   SEED));
    void'($value$plusargs("idcode=%h", IDCODE_EXP));
    keep_clk = $test$plusargs("clk");
    void'($urandom(SEED));

    $display("=============================================================================");
    $display(" tb_bscan_gate -- IEEE 1149.1 boundary scan, ROUTED nanosoc_eth_chiplet_pads");
    $display("   TAP on the package pins: SE=1, SWDCK=TCK, SWDIO=TMS,");
    $display("   HOSTIO4_P1[0]=TDI, HOSTIO4_P1[1]=TDO.   NRST held LOW all run.");
    $display("   boundary cells=%0d  IR width=%0d  seed=%0d  expected IDCODE=32'h%08h",
             N_CELLS, IR_W, SEED, IDCODE_EXP);
    $display("   functional clock after warm-up: %s", keep_clk ? "RUNNING (+clk)" : "PARKED");
    $display("=============================================================================");

    // Power up with boundary scan DISABLED. trst_n = SE = 0 is asynchronous, so
    // it clears the TAP, the instruction register and all the update flops out
    // of their gate-level X without needing a TCK edge -- which is also how the
    // chip comes up on a board. The functional clock runs for WARM_CYCLES with
    // NRST low so the core's own reset settles the pad enables it owns; then it
    // is parked and the core is left dead for the rest of the run.
    se_r = 1'b0; tap_drv = 1'b0;
    clk_en = 1'b1;
    repeat (WARM_CYCLES) @(posedge clk_r);
    @(negedge clk_r);
    clk_en = keep_clk;
    if (!keep_clk) clk_r = 1'b0;
    #(100ns);

    // TB takes SWDIO / HOSTIO4_P1[0]. Both pads' OEN is forced high by the SE
    // mux once SE=1, and with the core in reset neither drives before that, so
    // there is nothing to contend with.
    tap_drv = 1'b1;
    tms_r   = 1'b1;
    tdi_r   = 1'b0;
    #(100ns);

    test0_se_low_inert();

    // SE = 1: trst_n released, TCK/TMS/TDI now belong to the TAP.
    se_r = 1'b1;
    #(100ns);
    hygiene_on = 1'b1;

    test1_reset_idcode();
    test2_bypass();
    test3_chain();
    test4_sample();
    test5_extest();

    hygiene_on = 1'b0;

    // TDO enable hygiene, accumulated over every tick taken with SE=1: driven in
    // Shift-IR / Shift-DR, tri-state everywhere else.
    test_begin("T6  TDO enable hygiene, accumulated over the whole run");
    chk_n($sformatf("TDO driven in every one of the shift cycles (%0d tri-stated)", tdo_z_in_shift),
          tdo_z_in_shift == 0, tdo_hygiene_ticks);
    chk($sformatf("TDO tri-state in every non-shift cycle (%0d driven)", tdo_drv_off_shift),
        tdo_drv_off_shift == 0);
    $display("      %0d TCK cycles judged", tdo_hygiene_ticks);
    test_end();

    // Leave the chip in the state it ships in: SE low, TAP in reset.
    se_r    = 1'b0;
    tap_drv = 1'b0;
    #(100ns);

    $display("");
    $display("=============================================================================");
    $display(" tests: %0d run, %0d failed        comparisons: %0d, %0d failed",
             t_total, t_failed, checks, fails);
    $display(" TCK cycles: %0d", ncyc);
    $display("BSCAN_GATE_SUMMARY: %s checks=%0d fails=%0d tests=%0d/%0d",
             (fails == 0) ? "PASS" : "FAIL", checks, fails, t_total - t_failed, t_total);
    $display("=============================================================================");
    $finish;
  end

endmodule
