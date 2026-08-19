//-----------------------------------------------------------------------------
// nanosoc_eth_chiplet_bscan -- IEEE 1149.1 boundary-scan register and TAP for the
// nanoSoC ethernet chiplet pad ring.
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
// AUTO-GENERATED FILE - DO NOT EDIT DIRECTLY.
// Generator : scripts/gen_bscan.py
// Input     : src/rtl/bscan/pad_table.json
//             sha256 440b714a821ca214dc9d3d9c36552c3b0e2abb010ec6d225ab6085373c9e7ea7
// Regenerate: python3 scripts/gen_bscan.py
// Verify    : python3 scripts/gen_bscan.py --check      (CI gate; non-zero on drift)
//
// No timestamp is emitted on purpose: this file must be byte-reproducible from
// its input so that --check means "the RTL matches the pad table", not "the RTL
// was regenerated recently".
//-----------------------------------------------------------------------------
// WHY THIS FILE IS GENERATED
//
// This module and sys_desc/bscan/nanosoc_eth_chiplet_pads.bsdl are the same object
// described twice: a 76-cell shift register threaded through the pad ring.
// Hand-authored, the two descriptions drift, and the drift only shows up when a
// board tester shifts a pattern into bonded silicon. So both are rendered from
// ONE ordering computed in scripts/gen_bscan.py: the RTL front-to-back from
// TDI, the BSDL from that same list reversed, because BSDL numbers cell 0 at TDO.
//
// CHAIN ORDER
//
//   TDI enters the cell of the pad with the LOWEST ring_index and leaves at the
//   highest. Within one pad the order from TDI is:  oe ctl -> data ctl -> obs.
//   Cells per pad kind (contract section 1):
//     input     (18 pads) -> 1 obs                       = 18 cells
//     output    (15 pads) -> 1 data ctl                  = 15 cells
//     bidir     (13 pads) -> 1 oe ctl + 1 data ctl + obs = 39 cells
//     opendrain ( 2 pads) -> 1 oe ctl + 1 obs            =  4 cells
//                                                       total = 76 cells
//
// PORT NAMES ARE PER PAD INSTANCE, NOT PER TOP-LEVEL PORT
//
//   uPAD_QSPI_IO_0 -> QSPI_IO_0_pin_in, QSPI_IO_0_core_out, ...
//   The top-level port base name is not unique (QSPI_IO is 4 pads, TL_RX is 8,
//   TL_TX is 8, HOSTIO4_P1 is 7), so using it would collide. The BSDL, which
//   describes the chip's PINS rather than its pad instances, correctly uses
//   QSPI_IO(0) instead. Neither is a bug; they are different namespaces.
//   scripts/insert_bscan_padring.py builds the instantiation with the same rule.
//
// THE OPEN-DRAIN RULE (contract section 1) -- NON-NEGOTIABLE
//
//   uPAD_I2C_SCL and uPAD_I2C_SDA are open-drain built from a push-pull cell:
//   .I is hard-tied 1'b0 and the DATA is folded onto .OEN, so "send 1" tri-states
//   and an external pull-up makes the high. This wrapper therefore emits NO
//   *_core_out / *_pad_out port and NO data cell for those two pads. A 16 mA
//   push-pull driver on a wired-AND bus is a cross-die short that no tool warns
//   about.
//
// HIGHZ IS APPLIED HERE, NOT IN THE CELL
//
//   bscan_cell_ctl cannot implement HIGHZ: a primitive cannot tell an OE bit from
//   a data bit. So HIGHZ is an override downstream of each OE cell's func_out,
//   and the disabled value is DERIVED PER PAD from oe_inv, because the pad ring
//   re-applies its own inversion: oe_inv pads take .OEN(~pad_oe) so 0 disables;
//   the two open-drain pads take .OEN(pad_oe) so 1 disables. One hardcoded
//   polarity would enable every driver on half the ring.
//
//   The 15 pure-output pads have their OEN tied low in the pad ring and get no
//   OE cell, so HIGHZ CANNOT tri-state them. That is a known deviation from
//   1149.1's HIGHZ requirement and it is recorded in the BSDL as well.
//
// FUNCTIONAL TRANSPARENCY IS THE PROPERTY THAT MATTERS
//
//   With the SE pad low, trst_n is low: the TAP sits in Test-Logic-Reset, the
//   instruction resets to IDCODE, mode is 0 and every ctl cell is transparent
//   (func_out = func_in). Normal operation must be bit-identical to the design
//   without boundary scan. mode and highz are additionally gated with trst_n and
//   ~tlr at this level so that transparency is structural, not a property of the
//   instruction decoder being correct.
//
// WHY THE BOUNDARY REGISTER'S capture/shift/update ARE GATED WITH sel_boundary
//
//   shift_dr is a TAP STATE, not a register selection: it is high in Shift-DR
//   whichever DR is selected. Ungated, a BYPASS or IDCODE shift would also clock
//   the boundary chain and destroy data preloaded for EXTEST or CLAMP. CLAMP in
//   particular selects BYPASS as the DR while the boundary register must HOLD its
//   preloaded drive values, so its update must not fire either. BYPASS and IDCODE
//   are gated the same way, for the same reason and for quiet unselected logic.
//-----------------------------------------------------------------------------


module nanosoc_eth_chiplet_bscan #(
  // IEEE 1149.1 device identification register, contract section 5:
  //   {version[3:0], part[15:0], manufacturer[10:0], 1'b1}
  // PLACEHOLDER. SoC Labs holds no JEDEC manufacturer ID; 0x2D0 is invented
  // and MUST be replaced with an assigned ID before tapeout.
  parameter logic [31:0] IDCODE_VALUE = 32'h1000_05A1
) (
  // --- test access (contract section 7: muxed onto existing pads by SE) ---
  input  wire tck,
  input  wire tms,
  input  wire tdi,
  input  wire trst_n,
  output wire tdo,
  output wire tdo_oe,                 // 1 only while shifting, so TDO can be muxed onto a pad

  // --- pad-side and core-side groups, one per signal pad, in ring order ---

  // NRST_I         NRST           input     side=top    ring=3
  input  wire NRST_I_pin_in,
  output wire NRST_I_core_in,

  // SWDCK_I        SWDCK          input     side=top    ring=4
  input  wire SWDCK_I_pin_in,
  output wire SWDCK_I_core_in,

  // CLK_I          CLK            input     side=top    ring=5
  input  wire CLK_I_pin_in,
  output wire CLK_I_core_in,

  // TEST_I         TEST           input     side=top    ring=6
  input  wire TEST_I_pin_in,
  output wire TEST_I_core_in,

  // SE_I           SE             input     side=top    ring=7
  input  wire SE_I_pin_in,
  output wire SE_I_core_in,

  // SWDIO_IO       SWDIO          bidir     side=top    ring=9
  input  wire SWDIO_IO_pin_in,
  input  wire SWDIO_IO_core_out,
  output wire SWDIO_IO_pad_out,
  input  wire SWDIO_IO_core_oe,
  output wire SWDIO_IO_pad_oe,
  output wire SWDIO_IO_core_in,

  // HOST_IO_6      HOSTIO4_P1[6]  bidir     side=right  ring=17
  input  wire HOST_IO_6_pin_in,
  input  wire HOST_IO_6_core_out,
  output wire HOST_IO_6_pad_out,
  input  wire HOST_IO_6_core_oe,
  output wire HOST_IO_6_pad_oe,
  output wire HOST_IO_6_core_in,

  // HOST_IO_5      HOSTIO4_P1[5]  bidir     side=right  ring=18
  input  wire HOST_IO_5_pin_in,
  input  wire HOST_IO_5_core_out,
  output wire HOST_IO_5_pad_out,
  input  wire HOST_IO_5_core_oe,
  output wire HOST_IO_5_pad_oe,
  output wire HOST_IO_5_core_in,

  // HOST_IO_4      HOSTIO4_P1[4]  bidir     side=right  ring=19
  input  wire HOST_IO_4_pin_in,
  input  wire HOST_IO_4_core_out,
  output wire HOST_IO_4_pad_out,
  input  wire HOST_IO_4_core_oe,
  output wire HOST_IO_4_pad_oe,
  output wire HOST_IO_4_core_in,

  // HOST_IO_3      HOSTIO4_P1[3]  bidir     side=right  ring=20
  input  wire HOST_IO_3_pin_in,
  input  wire HOST_IO_3_core_out,
  output wire HOST_IO_3_pad_out,
  input  wire HOST_IO_3_core_oe,
  output wire HOST_IO_3_pad_oe,
  output wire HOST_IO_3_core_in,

  // HOST_IO_2      HOSTIO4_P1[2]  bidir     side=right  ring=21
  input  wire HOST_IO_2_pin_in,
  input  wire HOST_IO_2_core_out,
  output wire HOST_IO_2_pad_out,
  input  wire HOST_IO_2_core_oe,
  output wire HOST_IO_2_pad_oe,
  output wire HOST_IO_2_core_in,

  // HOST_IO_1      HOSTIO4_P1[1]  bidir     side=right  ring=22
  input  wire HOST_IO_1_pin_in,
  input  wire HOST_IO_1_core_out,
  output wire HOST_IO_1_pad_out,
  input  wire HOST_IO_1_core_oe,
  output wire HOST_IO_1_pad_oe,
  output wire HOST_IO_1_core_in,

  // HOST_IO_0      HOSTIO4_P1[0]  bidir     side=right  ring=23
  input  wire HOST_IO_0_pin_in,
  input  wire HOST_IO_0_core_out,
  output wire HOST_IO_0_pad_out,
  input  wire HOST_IO_0_core_oe,
  output wire HOST_IO_0_pad_oe,
  output wire HOST_IO_0_core_in,

  // RMII_CRS_DV    RMII_CRS_DV    input     side=right  ring=26
  input  wire RMII_CRS_DV_pin_in,
  output wire RMII_CRS_DV_core_in,

  // RMII_MDIO      RMII_MDIO      bidir     side=right  ring=27
  input  wire RMII_MDIO_pin_in,
  input  wire RMII_MDIO_core_out,
  output wire RMII_MDIO_pad_out,
  input  wire RMII_MDIO_core_oe,
  output wire RMII_MDIO_pad_oe,
  output wire RMII_MDIO_core_in,

  // RMII_TX_EN     RMII_TX_EN     output    side=right  ring=28
  input  wire RMII_TX_EN_core_out,
  output wire RMII_TX_EN_pad_out,

  // RMII_TXD1      RMII_TXD[1]    output    side=right  ring=29
  input  wire RMII_TXD1_core_out,
  output wire RMII_TXD1_pad_out,

  // RMII_TXD0      RMII_TXD[0]    output    side=right  ring=30
  input  wire RMII_TXD0_core_out,
  output wire RMII_TXD0_pad_out,

  // RMII_RXD1      RMII_RXD[1]    input     side=right  ring=31
  input  wire RMII_RXD1_pin_in,
  output wire RMII_RXD1_core_in,

  // RMII_RXD0      RMII_RXD[0]    input     side=right  ring=34
  input  wire RMII_RXD0_pin_in,
  output wire RMII_RXD0_core_in,

  // RMII_REF_CLK   RMII_REF_CLK   input     side=right  ring=35
  input  wire RMII_REF_CLK_pin_in,
  output wire RMII_REF_CLK_core_in,

  // RMII_MDC       RMII_MDC       output    side=right  ring=36
  input  wire RMII_MDC_core_out,
  output wire RMII_MDC_pad_out,

  // QSPI_nCS       QSPI_nCS       output    side=bottom ring=44
  input  wire QSPI_nCS_core_out,
  output wire QSPI_nCS_pad_out,

  // QSPI_SCLK      QSPI_SCLK      output    side=bottom ring=45
  input  wire QSPI_SCLK_core_out,
  output wire QSPI_SCLK_pad_out,

  // QSPI_IO_3      QSPI_IO[3]     bidir     side=bottom ring=46
  input  wire QSPI_IO_3_pin_in,
  input  wire QSPI_IO_3_core_out,
  output wire QSPI_IO_3_pad_out,
  input  wire QSPI_IO_3_core_oe,
  output wire QSPI_IO_3_pad_oe,
  output wire QSPI_IO_3_core_in,

  // QSPI_IO_2      QSPI_IO[2]     bidir     side=bottom ring=49
  input  wire QSPI_IO_2_pin_in,
  input  wire QSPI_IO_2_core_out,
  output wire QSPI_IO_2_pad_out,
  input  wire QSPI_IO_2_core_oe,
  output wire QSPI_IO_2_pad_oe,
  output wire QSPI_IO_2_core_in,

  // QSPI_IO_1      QSPI_IO[1]     bidir     side=bottom ring=50
  input  wire QSPI_IO_1_pin_in,
  input  wire QSPI_IO_1_core_out,
  output wire QSPI_IO_1_pad_out,
  input  wire QSPI_IO_1_core_oe,
  output wire QSPI_IO_1_pad_oe,
  output wire QSPI_IO_1_core_in,

  // QSPI_IO_0      QSPI_IO[0]     bidir     side=bottom ring=51
  input  wire QSPI_IO_0_pin_in,
  input  wire QSPI_IO_0_core_out,
  output wire QSPI_IO_0_pad_out,
  input  wire QSPI_IO_0_core_oe,
  output wire QSPI_IO_0_pad_oe,
  output wire QSPI_IO_0_core_in,

  // TL_RX_0        TL_RX[0]       input     side=left   ring=56
  input  wire TL_RX_0_pin_in,
  output wire TL_RX_0_core_in,

  // TL_RX_1        TL_RX[1]       input     side=left   ring=57
  input  wire TL_RX_1_pin_in,
  output wire TL_RX_1_core_in,

  // TL_RX_2        TL_RX[2]       input     side=left   ring=58
  input  wire TL_RX_2_pin_in,
  output wire TL_RX_2_core_in,

  // TL_RX_3        TL_RX[3]       input     side=left   ring=59
  input  wire TL_RX_3_pin_in,
  output wire TL_RX_3_core_in,

  // TL_CLK_RX      TL_CLK_RX      input     side=left   ring=62
  input  wire TL_CLK_RX_pin_in,
  output wire TL_CLK_RX_core_in,

  // TL_RX_4        TL_RX[4]       input     side=left   ring=63
  input  wire TL_RX_4_pin_in,
  output wire TL_RX_4_core_in,

  // TL_RX_5        TL_RX[5]       input     side=left   ring=64
  input  wire TL_RX_5_pin_in,
  output wire TL_RX_5_core_in,

  // TL_RX_6        TL_RX[6]       input     side=left   ring=65
  input  wire TL_RX_6_pin_in,
  output wire TL_RX_6_core_in,

  // TL_RX_7        TL_RX[7]       input     side=left   ring=66
  input  wire TL_RX_7_pin_in,
  output wire TL_RX_7_core_in,

  // I2C_SCL        I2C_SCL        opendrain side=left   ring=67
  input  wire I2C_SCL_pin_in,
  input  wire I2C_SCL_core_oe,
  output wire I2C_SCL_pad_oe,
  output wire I2C_SCL_core_in,

  // I2C_SDA        I2C_SDA        opendrain side=left   ring=68
  input  wire I2C_SDA_pin_in,
  input  wire I2C_SDA_core_oe,
  output wire I2C_SDA_pad_oe,
  output wire I2C_SDA_core_in,

  // TL_TX_0        TL_TX[0]       output    side=left   ring=71
  input  wire TL_TX_0_core_out,
  output wire TL_TX_0_pad_out,

  // TL_TX_1        TL_TX[1]       output    side=left   ring=72
  input  wire TL_TX_1_core_out,
  output wire TL_TX_1_pad_out,

  // TL_TX_2        TL_TX[2]       output    side=left   ring=73
  input  wire TL_TX_2_core_out,
  output wire TL_TX_2_pad_out,

  // TL_TX_3        TL_TX[3]       output    side=left   ring=74
  input  wire TL_TX_3_core_out,
  output wire TL_TX_3_pad_out,

  // TL_CLK_TX      TL_CLK_TX      output    side=left   ring=77
  input  wire TL_CLK_TX_core_out,
  output wire TL_CLK_TX_pad_out,

  // TL_TX_4        TL_TX[4]       output    side=left   ring=78
  input  wire TL_TX_4_core_out,
  output wire TL_TX_4_pad_out,

  // TL_TX_5        TL_TX[5]       output    side=left   ring=79
  input  wire TL_TX_5_core_out,
  output wire TL_TX_5_pad_out,

  // TL_TX_6        TL_TX[6]       output    side=left   ring=80
  input  wire TL_TX_6_core_out,
  output wire TL_TX_6_pad_out,

  // TL_TX_7        TL_TX[7]       output    side=left   ring=81
  input  wire TL_TX_7_core_out,
  output wire TL_TX_7_pad_out
);

  //---------------------------------------------------------------------------
  // TAP controller and instruction register
  //---------------------------------------------------------------------------
  wire tlr;
  wire capture_dr, shift_dr, update_dr;
  wire capture_ir, shift_ir, update_ir;
  wire select_ir, tdo_enable;

  bscan_tap u_tap (
    .tck        (tck),
    .tms        (tms),
    .trst_n     (trst_n),
    .tlr        (tlr),
    .capture_dr (capture_dr),
    .shift_dr   (shift_dr),
    .update_dr  (update_dr),
    .capture_ir (capture_ir),
    .shift_ir   (shift_ir),
    .update_ir  (update_ir),
    .select_ir  (select_ir),
    .tdo_enable (tdo_enable)
  );

  wire ir_so;
  wire sel_bypass, sel_idcode, sel_boundary;
  wire ir_mode, ir_highz;

  // IEEE 1149.1 Clause 6.1.1: the instruction register must be reset in the
  // Test-Logic-Reset STATE, however that state was entered -- including via five
  // TMS=1 clocks with trst_n never asserted. bscan_ir has no `tlr` input, so the
  // reset is synthesised here. It releases on the same rising edge that leaves
  // TLR, so nothing is held reset a cycle longer than the standard allows.
  //
  // Gating `mode`/`highz` with ~tlr (below) is NOT a substitute. That keeps the
  // pads safe while in TLR, but the HELD INSTRUCTION survives, so a stale EXTEST
  // resumes the moment the tester leaves TLR -- and the standard discovery
  // sequence every boundary-scan tool opens with (reset, then shift DR expecting
  // IDCODE) would clock out the 76-bit boundary register instead of the 32-bit
  // ID, and mis-identify the part.
  wire ir_trst_n = trst_n & ~tlr;

  bscan_ir #(
    .IR_WIDTH (4)
  ) u_ir (
    .tck          (tck),
    .trst_n       (ir_trst_n),
    .capture_ir   (capture_ir),
    .shift_ir     (shift_ir),
    .update_ir    (update_ir),
    .si           (tdi),
    .so           (ir_so),
    .sel_bypass   (sel_bypass),
    .sel_idcode   (sel_idcode),
    .sel_boundary (sel_boundary),
    .mode         (ir_mode),
    .highz        (ir_highz)
  );

  // Transparency made structural. bscan_ir has no `tlr` input, so reaching
  // Test-Logic-Reset through five TMS=1 clocks (rather than through trst_n)
  // would otherwise leave a previously loaded EXTEST driving the pads. 1149.1
  // requires the test logic to be inactive in TLR, so force it here.
  wire bsr_mode  = ir_mode  & trst_n & ~tlr;
  wire bsr_highz = ir_highz & trst_n & ~tlr;

  //---------------------------------------------------------------------------
  // BYPASS (1 bit) and IDCODE (32 bits)
  //---------------------------------------------------------------------------
  // Every data register shifts ONLY while it is the selected one. shift_dr and
  // capture_dr are TAP STATES, not selections: they are high in Shift-DR and
  // Capture-DR whichever register is active. See the note on sel_boundary below
  // for why that distinction is load-bearing.
  logic bypass_q;
  always_ff @(posedge tck or negedge trst_n) begin
    if (!trst_n)                      bypass_q <= 1'b0;
    else if (capture_dr & sel_bypass) bypass_q <= 1'b0;   // 1149.1: BYPASS captures 0
    else if (shift_dr   & sel_bypass) bypass_q <= tdi;
  end

  logic [31:0] idcode_q;
  always_ff @(posedge tck or negedge trst_n) begin
    if (!trst_n)                      idcode_q <= IDCODE_VALUE;
    else if (capture_dr & sel_idcode) idcode_q <= IDCODE_VALUE;
    else if (shift_dr   & sel_idcode) idcode_q <= {tdi, idcode_q[31:1]};   // LSB first out
  end

  //---------------------------------------------------------------------------
  // Boundary register: 76 cells, TDI-first in physical ring order
  //---------------------------------------------------------------------------
  // bsr_chain[i] is the scan input of cell i and the scan output of cell i-1,
  // so bsr_chain[0] is TDI and bsr_chain[76] is the far end of the chain.
  wire [76:0] bsr_chain;
  assign bsr_chain[0] = tdi;

  wire bsr_capture_dr = capture_dr & sel_boundary;
  wire bsr_shift_dr   = shift_dr   & sel_boundary;
  wire bsr_update_dr  = update_dr  & sel_boundary;

  //--- uPAD_NRST_I : NRST  (input, top, ring 3) ---
  //    chain cells 0 (TDI order) = BSDL cells 75
  bscan_cell_obs u_bsc_00_NRST_I_obs (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .si         (bsr_chain[0]),
    .pin_in     (NRST_I_pin_in),
    .so         (bsr_chain[1])
  );
  assign NRST_I_core_in = NRST_I_pin_in;   // INTEST is not supported

  //--- uPAD_SWDCK_I : SWDCK  (input, top, ring 4) ---
  //    chain cells 1 (TDI order) = BSDL cells 74
  bscan_cell_obs u_bsc_01_SWDCK_I_obs (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .si         (bsr_chain[1]),
    .pin_in     (SWDCK_I_pin_in),
    .so         (bsr_chain[2])
  );
  assign SWDCK_I_core_in = SWDCK_I_pin_in;   // INTEST is not supported

  //--- uPAD_CLK_I : CLK  (input, top, ring 5) ---
  //    chain cells 2 (TDI order) = BSDL cells 73
  bscan_cell_obs u_bsc_02_CLK_I_obs (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .si         (bsr_chain[2]),
    .pin_in     (CLK_I_pin_in),
    .so         (bsr_chain[3])
  );
  assign CLK_I_core_in = CLK_I_pin_in;   // INTEST is not supported

  //--- uPAD_TEST_I : TEST  (input, top, ring 6) ---
  //    chain cells 3 (TDI order) = BSDL cells 72
  bscan_cell_obs u_bsc_03_TEST_I_obs (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .si         (bsr_chain[3]),
    .pin_in     (TEST_I_pin_in),
    .so         (bsr_chain[4])
  );
  assign TEST_I_core_in = TEST_I_pin_in;   // INTEST is not supported

  //--- uPAD_SE_I : SE  (input, top, ring 7) ---
  //    chain cells 4 (TDI order) = BSDL cells 71
  bscan_cell_obs u_bsc_04_SE_I_obs (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .si         (bsr_chain[4]),
    .pin_in     (SE_I_pin_in),
    .so         (bsr_chain[5])
  );
  assign SE_I_core_in = SE_I_pin_in;   // INTEST is not supported

  //--- uPAD_SWDIO_IO : SWDIO  (bidir, top, ring 9) ---
  //    chain cells 5, 6, 7 (TDI order) = BSDL cells 70, 69, 68
  wire SWDIO_IO_pad_oe_int;
  bscan_cell_ctl u_bsc_05_SWDIO_IO_oe (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .update_dr  (bsr_update_dr),
    .mode       (bsr_mode),
    .si         (bsr_chain[5]),
    .func_in    (SWDIO_IO_core_oe),
    .func_out   (SWDIO_IO_pad_oe_int),
    .so         (bsr_chain[6])
  );
  // HIGHZ override. oe_inv=true for this pad, so the pad ring takes
  // .OEN(~SWDIO_IO_pad_oe) and 1'b0 is therefore 'driver off'.
  assign SWDIO_IO_pad_oe = bsr_highz ? 1'b0 : SWDIO_IO_pad_oe_int;
  bscan_cell_ctl u_bsc_06_SWDIO_IO_data (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .update_dr  (bsr_update_dr),
    .mode       (bsr_mode),
    .si         (bsr_chain[6]),
    .func_in    (SWDIO_IO_core_out),
    .func_out   (SWDIO_IO_pad_out),
    .so         (bsr_chain[7])
  );
  bscan_cell_obs u_bsc_07_SWDIO_IO_obs (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .si         (bsr_chain[7]),
    .pin_in     (SWDIO_IO_pin_in),
    .so         (bsr_chain[8])
  );
  assign SWDIO_IO_core_in = SWDIO_IO_pin_in;   // INTEST is not supported

  //--- uPAD_HOST_IO_6 : HOSTIO4_P1[6]  (bidir, right, ring 17) ---
  //    chain cells 8, 9, 10 (TDI order) = BSDL cells 67, 66, 65
  wire HOST_IO_6_pad_oe_int;
  bscan_cell_ctl u_bsc_08_HOST_IO_6_oe (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .update_dr  (bsr_update_dr),
    .mode       (bsr_mode),
    .si         (bsr_chain[8]),
    .func_in    (HOST_IO_6_core_oe),
    .func_out   (HOST_IO_6_pad_oe_int),
    .so         (bsr_chain[9])
  );
  // HIGHZ override. oe_inv=true for this pad, so the pad ring takes
  // .OEN(~HOST_IO_6_pad_oe) and 1'b0 is therefore 'driver off'.
  assign HOST_IO_6_pad_oe = bsr_highz ? 1'b0 : HOST_IO_6_pad_oe_int;
  bscan_cell_ctl u_bsc_09_HOST_IO_6_data (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .update_dr  (bsr_update_dr),
    .mode       (bsr_mode),
    .si         (bsr_chain[9]),
    .func_in    (HOST_IO_6_core_out),
    .func_out   (HOST_IO_6_pad_out),
    .so         (bsr_chain[10])
  );
  bscan_cell_obs u_bsc_10_HOST_IO_6_obs (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .si         (bsr_chain[10]),
    .pin_in     (HOST_IO_6_pin_in),
    .so         (bsr_chain[11])
  );
  assign HOST_IO_6_core_in = HOST_IO_6_pin_in;   // INTEST is not supported

  //--- uPAD_HOST_IO_5 : HOSTIO4_P1[5]  (bidir, right, ring 18) ---
  //    chain cells 11, 12, 13 (TDI order) = BSDL cells 64, 63, 62
  wire HOST_IO_5_pad_oe_int;
  bscan_cell_ctl u_bsc_11_HOST_IO_5_oe (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .update_dr  (bsr_update_dr),
    .mode       (bsr_mode),
    .si         (bsr_chain[11]),
    .func_in    (HOST_IO_5_core_oe),
    .func_out   (HOST_IO_5_pad_oe_int),
    .so         (bsr_chain[12])
  );
  // HIGHZ override. oe_inv=true for this pad, so the pad ring takes
  // .OEN(~HOST_IO_5_pad_oe) and 1'b0 is therefore 'driver off'.
  assign HOST_IO_5_pad_oe = bsr_highz ? 1'b0 : HOST_IO_5_pad_oe_int;
  bscan_cell_ctl u_bsc_12_HOST_IO_5_data (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .update_dr  (bsr_update_dr),
    .mode       (bsr_mode),
    .si         (bsr_chain[12]),
    .func_in    (HOST_IO_5_core_out),
    .func_out   (HOST_IO_5_pad_out),
    .so         (bsr_chain[13])
  );
  bscan_cell_obs u_bsc_13_HOST_IO_5_obs (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .si         (bsr_chain[13]),
    .pin_in     (HOST_IO_5_pin_in),
    .so         (bsr_chain[14])
  );
  assign HOST_IO_5_core_in = HOST_IO_5_pin_in;   // INTEST is not supported

  //--- uPAD_HOST_IO_4 : HOSTIO4_P1[4]  (bidir, right, ring 19) ---
  //    chain cells 14, 15, 16 (TDI order) = BSDL cells 61, 60, 59
  wire HOST_IO_4_pad_oe_int;
  bscan_cell_ctl u_bsc_14_HOST_IO_4_oe (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .update_dr  (bsr_update_dr),
    .mode       (bsr_mode),
    .si         (bsr_chain[14]),
    .func_in    (HOST_IO_4_core_oe),
    .func_out   (HOST_IO_4_pad_oe_int),
    .so         (bsr_chain[15])
  );
  // HIGHZ override. oe_inv=true for this pad, so the pad ring takes
  // .OEN(~HOST_IO_4_pad_oe) and 1'b0 is therefore 'driver off'.
  assign HOST_IO_4_pad_oe = bsr_highz ? 1'b0 : HOST_IO_4_pad_oe_int;
  bscan_cell_ctl u_bsc_15_HOST_IO_4_data (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .update_dr  (bsr_update_dr),
    .mode       (bsr_mode),
    .si         (bsr_chain[15]),
    .func_in    (HOST_IO_4_core_out),
    .func_out   (HOST_IO_4_pad_out),
    .so         (bsr_chain[16])
  );
  bscan_cell_obs u_bsc_16_HOST_IO_4_obs (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .si         (bsr_chain[16]),
    .pin_in     (HOST_IO_4_pin_in),
    .so         (bsr_chain[17])
  );
  assign HOST_IO_4_core_in = HOST_IO_4_pin_in;   // INTEST is not supported

  //--- uPAD_HOST_IO_3 : HOSTIO4_P1[3]  (bidir, right, ring 20) ---
  //    chain cells 17, 18, 19 (TDI order) = BSDL cells 58, 57, 56
  wire HOST_IO_3_pad_oe_int;
  bscan_cell_ctl u_bsc_17_HOST_IO_3_oe (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .update_dr  (bsr_update_dr),
    .mode       (bsr_mode),
    .si         (bsr_chain[17]),
    .func_in    (HOST_IO_3_core_oe),
    .func_out   (HOST_IO_3_pad_oe_int),
    .so         (bsr_chain[18])
  );
  // HIGHZ override. oe_inv=true for this pad, so the pad ring takes
  // .OEN(~HOST_IO_3_pad_oe) and 1'b0 is therefore 'driver off'.
  assign HOST_IO_3_pad_oe = bsr_highz ? 1'b0 : HOST_IO_3_pad_oe_int;
  bscan_cell_ctl u_bsc_18_HOST_IO_3_data (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .update_dr  (bsr_update_dr),
    .mode       (bsr_mode),
    .si         (bsr_chain[18]),
    .func_in    (HOST_IO_3_core_out),
    .func_out   (HOST_IO_3_pad_out),
    .so         (bsr_chain[19])
  );
  bscan_cell_obs u_bsc_19_HOST_IO_3_obs (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .si         (bsr_chain[19]),
    .pin_in     (HOST_IO_3_pin_in),
    .so         (bsr_chain[20])
  );
  assign HOST_IO_3_core_in = HOST_IO_3_pin_in;   // INTEST is not supported

  //--- uPAD_HOST_IO_2 : HOSTIO4_P1[2]  (bidir, right, ring 21) ---
  //    chain cells 20, 21, 22 (TDI order) = BSDL cells 55, 54, 53
  wire HOST_IO_2_pad_oe_int;
  bscan_cell_ctl u_bsc_20_HOST_IO_2_oe (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .update_dr  (bsr_update_dr),
    .mode       (bsr_mode),
    .si         (bsr_chain[20]),
    .func_in    (HOST_IO_2_core_oe),
    .func_out   (HOST_IO_2_pad_oe_int),
    .so         (bsr_chain[21])
  );
  // HIGHZ override. oe_inv=true for this pad, so the pad ring takes
  // .OEN(~HOST_IO_2_pad_oe) and 1'b0 is therefore 'driver off'.
  assign HOST_IO_2_pad_oe = bsr_highz ? 1'b0 : HOST_IO_2_pad_oe_int;
  bscan_cell_ctl u_bsc_21_HOST_IO_2_data (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .update_dr  (bsr_update_dr),
    .mode       (bsr_mode),
    .si         (bsr_chain[21]),
    .func_in    (HOST_IO_2_core_out),
    .func_out   (HOST_IO_2_pad_out),
    .so         (bsr_chain[22])
  );
  bscan_cell_obs u_bsc_22_HOST_IO_2_obs (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .si         (bsr_chain[22]),
    .pin_in     (HOST_IO_2_pin_in),
    .so         (bsr_chain[23])
  );
  assign HOST_IO_2_core_in = HOST_IO_2_pin_in;   // INTEST is not supported

  //--- uPAD_HOST_IO_1 : HOSTIO4_P1[1]  (bidir, right, ring 22) ---
  //    chain cells 23, 24, 25 (TDI order) = BSDL cells 52, 51, 50
  wire HOST_IO_1_pad_oe_int;
  bscan_cell_ctl u_bsc_23_HOST_IO_1_oe (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .update_dr  (bsr_update_dr),
    .mode       (bsr_mode),
    .si         (bsr_chain[23]),
    .func_in    (HOST_IO_1_core_oe),
    .func_out   (HOST_IO_1_pad_oe_int),
    .so         (bsr_chain[24])
  );
  // HIGHZ override. oe_inv=true for this pad, so the pad ring takes
  // .OEN(~HOST_IO_1_pad_oe) and 1'b0 is therefore 'driver off'.
  assign HOST_IO_1_pad_oe = bsr_highz ? 1'b0 : HOST_IO_1_pad_oe_int;
  bscan_cell_ctl u_bsc_24_HOST_IO_1_data (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .update_dr  (bsr_update_dr),
    .mode       (bsr_mode),
    .si         (bsr_chain[24]),
    .func_in    (HOST_IO_1_core_out),
    .func_out   (HOST_IO_1_pad_out),
    .so         (bsr_chain[25])
  );
  bscan_cell_obs u_bsc_25_HOST_IO_1_obs (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .si         (bsr_chain[25]),
    .pin_in     (HOST_IO_1_pin_in),
    .so         (bsr_chain[26])
  );
  assign HOST_IO_1_core_in = HOST_IO_1_pin_in;   // INTEST is not supported

  //--- uPAD_HOST_IO_0 : HOSTIO4_P1[0]  (bidir, right, ring 23) ---
  //    chain cells 26, 27, 28 (TDI order) = BSDL cells 49, 48, 47
  wire HOST_IO_0_pad_oe_int;
  bscan_cell_ctl u_bsc_26_HOST_IO_0_oe (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .update_dr  (bsr_update_dr),
    .mode       (bsr_mode),
    .si         (bsr_chain[26]),
    .func_in    (HOST_IO_0_core_oe),
    .func_out   (HOST_IO_0_pad_oe_int),
    .so         (bsr_chain[27])
  );
  // HIGHZ override. oe_inv=true for this pad, so the pad ring takes
  // .OEN(~HOST_IO_0_pad_oe) and 1'b0 is therefore 'driver off'.
  assign HOST_IO_0_pad_oe = bsr_highz ? 1'b0 : HOST_IO_0_pad_oe_int;
  bscan_cell_ctl u_bsc_27_HOST_IO_0_data (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .update_dr  (bsr_update_dr),
    .mode       (bsr_mode),
    .si         (bsr_chain[27]),
    .func_in    (HOST_IO_0_core_out),
    .func_out   (HOST_IO_0_pad_out),
    .so         (bsr_chain[28])
  );
  bscan_cell_obs u_bsc_28_HOST_IO_0_obs (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .si         (bsr_chain[28]),
    .pin_in     (HOST_IO_0_pin_in),
    .so         (bsr_chain[29])
  );
  assign HOST_IO_0_core_in = HOST_IO_0_pin_in;   // INTEST is not supported

  //--- uPAD_RMII_CRS_DV : RMII_CRS_DV  (input, right, ring 26) ---
  //    chain cells 29 (TDI order) = BSDL cells 46
  bscan_cell_obs u_bsc_29_RMII_CRS_DV_obs (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .si         (bsr_chain[29]),
    .pin_in     (RMII_CRS_DV_pin_in),
    .so         (bsr_chain[30])
  );
  assign RMII_CRS_DV_core_in = RMII_CRS_DV_pin_in;   // INTEST is not supported

  //--- uPAD_RMII_MDIO : RMII_MDIO  (bidir, right, ring 27) ---
  //    chain cells 30, 31, 32 (TDI order) = BSDL cells 45, 44, 43
  wire RMII_MDIO_pad_oe_int;
  bscan_cell_ctl u_bsc_30_RMII_MDIO_oe (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .update_dr  (bsr_update_dr),
    .mode       (bsr_mode),
    .si         (bsr_chain[30]),
    .func_in    (RMII_MDIO_core_oe),
    .func_out   (RMII_MDIO_pad_oe_int),
    .so         (bsr_chain[31])
  );
  // HIGHZ override. oe_inv=true for this pad, so the pad ring takes
  // .OEN(~RMII_MDIO_pad_oe) and 1'b0 is therefore 'driver off'.
  assign RMII_MDIO_pad_oe = bsr_highz ? 1'b0 : RMII_MDIO_pad_oe_int;
  bscan_cell_ctl u_bsc_31_RMII_MDIO_data (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .update_dr  (bsr_update_dr),
    .mode       (bsr_mode),
    .si         (bsr_chain[31]),
    .func_in    (RMII_MDIO_core_out),
    .func_out   (RMII_MDIO_pad_out),
    .so         (bsr_chain[32])
  );
  bscan_cell_obs u_bsc_32_RMII_MDIO_obs (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .si         (bsr_chain[32]),
    .pin_in     (RMII_MDIO_pin_in),
    .so         (bsr_chain[33])
  );
  assign RMII_MDIO_core_in = RMII_MDIO_pin_in;   // INTEST is not supported

  //--- uPAD_RMII_TX_EN : RMII_TX_EN  (output, right, ring 28) ---
  //    chain cells 33 (TDI order) = BSDL cells 42
  bscan_cell_ctl u_bsc_33_RMII_TX_EN_data (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .update_dr  (bsr_update_dr),
    .mode       (bsr_mode),
    .si         (bsr_chain[33]),
    .func_in    (RMII_TX_EN_core_out),
    .func_out   (RMII_TX_EN_pad_out),
    .so         (bsr_chain[34])
  );

  //--- uPAD_RMII_TXD1 : RMII_TXD[1]  (output, right, ring 29) ---
  //    chain cells 34 (TDI order) = BSDL cells 41
  bscan_cell_ctl u_bsc_34_RMII_TXD1_data (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .update_dr  (bsr_update_dr),
    .mode       (bsr_mode),
    .si         (bsr_chain[34]),
    .func_in    (RMII_TXD1_core_out),
    .func_out   (RMII_TXD1_pad_out),
    .so         (bsr_chain[35])
  );

  //--- uPAD_RMII_TXD0 : RMII_TXD[0]  (output, right, ring 30) ---
  //    chain cells 35 (TDI order) = BSDL cells 40
  bscan_cell_ctl u_bsc_35_RMII_TXD0_data (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .update_dr  (bsr_update_dr),
    .mode       (bsr_mode),
    .si         (bsr_chain[35]),
    .func_in    (RMII_TXD0_core_out),
    .func_out   (RMII_TXD0_pad_out),
    .so         (bsr_chain[36])
  );

  //--- uPAD_RMII_RXD1 : RMII_RXD[1]  (input, right, ring 31) ---
  //    chain cells 36 (TDI order) = BSDL cells 39
  bscan_cell_obs u_bsc_36_RMII_RXD1_obs (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .si         (bsr_chain[36]),
    .pin_in     (RMII_RXD1_pin_in),
    .so         (bsr_chain[37])
  );
  assign RMII_RXD1_core_in = RMII_RXD1_pin_in;   // INTEST is not supported

  //--- uPAD_RMII_RXD0 : RMII_RXD[0]  (input, right, ring 34) ---
  //    chain cells 37 (TDI order) = BSDL cells 38
  bscan_cell_obs u_bsc_37_RMII_RXD0_obs (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .si         (bsr_chain[37]),
    .pin_in     (RMII_RXD0_pin_in),
    .so         (bsr_chain[38])
  );
  assign RMII_RXD0_core_in = RMII_RXD0_pin_in;   // INTEST is not supported

  //--- uPAD_RMII_REF_CLK : RMII_REF_CLK  (input, right, ring 35) ---
  //    chain cells 38 (TDI order) = BSDL cells 37
  bscan_cell_obs u_bsc_38_RMII_REF_CLK_obs (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .si         (bsr_chain[38]),
    .pin_in     (RMII_REF_CLK_pin_in),
    .so         (bsr_chain[39])
  );
  assign RMII_REF_CLK_core_in = RMII_REF_CLK_pin_in;   // INTEST is not supported

  //--- uPAD_RMII_MDC : RMII_MDC  (output, right, ring 36) ---
  //    chain cells 39 (TDI order) = BSDL cells 36
  bscan_cell_ctl u_bsc_39_RMII_MDC_data (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .update_dr  (bsr_update_dr),
    .mode       (bsr_mode),
    .si         (bsr_chain[39]),
    .func_in    (RMII_MDC_core_out),
    .func_out   (RMII_MDC_pad_out),
    .so         (bsr_chain[40])
  );

  //--- uPAD_QSPI_nCS : QSPI_nCS  (output, bottom, ring 44) ---
  //    chain cells 40 (TDI order) = BSDL cells 35
  bscan_cell_ctl u_bsc_40_QSPI_nCS_data (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .update_dr  (bsr_update_dr),
    .mode       (bsr_mode),
    .si         (bsr_chain[40]),
    .func_in    (QSPI_nCS_core_out),
    .func_out   (QSPI_nCS_pad_out),
    .so         (bsr_chain[41])
  );

  //--- uPAD_QSPI_SCLK : QSPI_SCLK  (output, bottom, ring 45) ---
  //    chain cells 41 (TDI order) = BSDL cells 34
  bscan_cell_ctl u_bsc_41_QSPI_SCLK_data (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .update_dr  (bsr_update_dr),
    .mode       (bsr_mode),
    .si         (bsr_chain[41]),
    .func_in    (QSPI_SCLK_core_out),
    .func_out   (QSPI_SCLK_pad_out),
    .so         (bsr_chain[42])
  );

  //--- uPAD_QSPI_IO_3 : QSPI_IO[3]  (bidir, bottom, ring 46) ---
  //    chain cells 42, 43, 44 (TDI order) = BSDL cells 33, 32, 31
  wire QSPI_IO_3_pad_oe_int;
  bscan_cell_ctl u_bsc_42_QSPI_IO_3_oe (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .update_dr  (bsr_update_dr),
    .mode       (bsr_mode),
    .si         (bsr_chain[42]),
    .func_in    (QSPI_IO_3_core_oe),
    .func_out   (QSPI_IO_3_pad_oe_int),
    .so         (bsr_chain[43])
  );
  // HIGHZ override. oe_inv=true for this pad, so the pad ring takes
  // .OEN(~QSPI_IO_3_pad_oe) and 1'b0 is therefore 'driver off'.
  assign QSPI_IO_3_pad_oe = bsr_highz ? 1'b0 : QSPI_IO_3_pad_oe_int;
  bscan_cell_ctl u_bsc_43_QSPI_IO_3_data (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .update_dr  (bsr_update_dr),
    .mode       (bsr_mode),
    .si         (bsr_chain[43]),
    .func_in    (QSPI_IO_3_core_out),
    .func_out   (QSPI_IO_3_pad_out),
    .so         (bsr_chain[44])
  );
  bscan_cell_obs u_bsc_44_QSPI_IO_3_obs (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .si         (bsr_chain[44]),
    .pin_in     (QSPI_IO_3_pin_in),
    .so         (bsr_chain[45])
  );
  assign QSPI_IO_3_core_in = QSPI_IO_3_pin_in;   // INTEST is not supported

  //--- uPAD_QSPI_IO_2 : QSPI_IO[2]  (bidir, bottom, ring 49) ---
  //    chain cells 45, 46, 47 (TDI order) = BSDL cells 30, 29, 28
  wire QSPI_IO_2_pad_oe_int;
  bscan_cell_ctl u_bsc_45_QSPI_IO_2_oe (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .update_dr  (bsr_update_dr),
    .mode       (bsr_mode),
    .si         (bsr_chain[45]),
    .func_in    (QSPI_IO_2_core_oe),
    .func_out   (QSPI_IO_2_pad_oe_int),
    .so         (bsr_chain[46])
  );
  // HIGHZ override. oe_inv=true for this pad, so the pad ring takes
  // .OEN(~QSPI_IO_2_pad_oe) and 1'b0 is therefore 'driver off'.
  assign QSPI_IO_2_pad_oe = bsr_highz ? 1'b0 : QSPI_IO_2_pad_oe_int;
  bscan_cell_ctl u_bsc_46_QSPI_IO_2_data (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .update_dr  (bsr_update_dr),
    .mode       (bsr_mode),
    .si         (bsr_chain[46]),
    .func_in    (QSPI_IO_2_core_out),
    .func_out   (QSPI_IO_2_pad_out),
    .so         (bsr_chain[47])
  );
  bscan_cell_obs u_bsc_47_QSPI_IO_2_obs (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .si         (bsr_chain[47]),
    .pin_in     (QSPI_IO_2_pin_in),
    .so         (bsr_chain[48])
  );
  assign QSPI_IO_2_core_in = QSPI_IO_2_pin_in;   // INTEST is not supported

  //--- uPAD_QSPI_IO_1 : QSPI_IO[1]  (bidir, bottom, ring 50) ---
  //    chain cells 48, 49, 50 (TDI order) = BSDL cells 27, 26, 25
  wire QSPI_IO_1_pad_oe_int;
  bscan_cell_ctl u_bsc_48_QSPI_IO_1_oe (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .update_dr  (bsr_update_dr),
    .mode       (bsr_mode),
    .si         (bsr_chain[48]),
    .func_in    (QSPI_IO_1_core_oe),
    .func_out   (QSPI_IO_1_pad_oe_int),
    .so         (bsr_chain[49])
  );
  // HIGHZ override. oe_inv=true for this pad, so the pad ring takes
  // .OEN(~QSPI_IO_1_pad_oe) and 1'b0 is therefore 'driver off'.
  assign QSPI_IO_1_pad_oe = bsr_highz ? 1'b0 : QSPI_IO_1_pad_oe_int;
  bscan_cell_ctl u_bsc_49_QSPI_IO_1_data (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .update_dr  (bsr_update_dr),
    .mode       (bsr_mode),
    .si         (bsr_chain[49]),
    .func_in    (QSPI_IO_1_core_out),
    .func_out   (QSPI_IO_1_pad_out),
    .so         (bsr_chain[50])
  );
  bscan_cell_obs u_bsc_50_QSPI_IO_1_obs (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .si         (bsr_chain[50]),
    .pin_in     (QSPI_IO_1_pin_in),
    .so         (bsr_chain[51])
  );
  assign QSPI_IO_1_core_in = QSPI_IO_1_pin_in;   // INTEST is not supported

  //--- uPAD_QSPI_IO_0 : QSPI_IO[0]  (bidir, bottom, ring 51) ---
  //    chain cells 51, 52, 53 (TDI order) = BSDL cells 24, 23, 22
  wire QSPI_IO_0_pad_oe_int;
  bscan_cell_ctl u_bsc_51_QSPI_IO_0_oe (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .update_dr  (bsr_update_dr),
    .mode       (bsr_mode),
    .si         (bsr_chain[51]),
    .func_in    (QSPI_IO_0_core_oe),
    .func_out   (QSPI_IO_0_pad_oe_int),
    .so         (bsr_chain[52])
  );
  // HIGHZ override. oe_inv=true for this pad, so the pad ring takes
  // .OEN(~QSPI_IO_0_pad_oe) and 1'b0 is therefore 'driver off'.
  assign QSPI_IO_0_pad_oe = bsr_highz ? 1'b0 : QSPI_IO_0_pad_oe_int;
  bscan_cell_ctl u_bsc_52_QSPI_IO_0_data (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .update_dr  (bsr_update_dr),
    .mode       (bsr_mode),
    .si         (bsr_chain[52]),
    .func_in    (QSPI_IO_0_core_out),
    .func_out   (QSPI_IO_0_pad_out),
    .so         (bsr_chain[53])
  );
  bscan_cell_obs u_bsc_53_QSPI_IO_0_obs (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .si         (bsr_chain[53]),
    .pin_in     (QSPI_IO_0_pin_in),
    .so         (bsr_chain[54])
  );
  assign QSPI_IO_0_core_in = QSPI_IO_0_pin_in;   // INTEST is not supported

  //--- uPAD_TL_RX_0 : TL_RX[0]  (input, left, ring 56) ---
  //    chain cells 54 (TDI order) = BSDL cells 21
  bscan_cell_obs u_bsc_54_TL_RX_0_obs (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .si         (bsr_chain[54]),
    .pin_in     (TL_RX_0_pin_in),
    .so         (bsr_chain[55])
  );
  assign TL_RX_0_core_in = TL_RX_0_pin_in;   // INTEST is not supported

  //--- uPAD_TL_RX_1 : TL_RX[1]  (input, left, ring 57) ---
  //    chain cells 55 (TDI order) = BSDL cells 20
  bscan_cell_obs u_bsc_55_TL_RX_1_obs (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .si         (bsr_chain[55]),
    .pin_in     (TL_RX_1_pin_in),
    .so         (bsr_chain[56])
  );
  assign TL_RX_1_core_in = TL_RX_1_pin_in;   // INTEST is not supported

  //--- uPAD_TL_RX_2 : TL_RX[2]  (input, left, ring 58) ---
  //    chain cells 56 (TDI order) = BSDL cells 19
  bscan_cell_obs u_bsc_56_TL_RX_2_obs (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .si         (bsr_chain[56]),
    .pin_in     (TL_RX_2_pin_in),
    .so         (bsr_chain[57])
  );
  assign TL_RX_2_core_in = TL_RX_2_pin_in;   // INTEST is not supported

  //--- uPAD_TL_RX_3 : TL_RX[3]  (input, left, ring 59) ---
  //    chain cells 57 (TDI order) = BSDL cells 18
  bscan_cell_obs u_bsc_57_TL_RX_3_obs (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .si         (bsr_chain[57]),
    .pin_in     (TL_RX_3_pin_in),
    .so         (bsr_chain[58])
  );
  assign TL_RX_3_core_in = TL_RX_3_pin_in;   // INTEST is not supported

  //--- uPAD_TL_CLK_RX : TL_CLK_RX  (input, left, ring 62) ---
  //    chain cells 58 (TDI order) = BSDL cells 17
  bscan_cell_obs u_bsc_58_TL_CLK_RX_obs (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .si         (bsr_chain[58]),
    .pin_in     (TL_CLK_RX_pin_in),
    .so         (bsr_chain[59])
  );
  assign TL_CLK_RX_core_in = TL_CLK_RX_pin_in;   // INTEST is not supported

  //--- uPAD_TL_RX_4 : TL_RX[4]  (input, left, ring 63) ---
  //    chain cells 59 (TDI order) = BSDL cells 16
  bscan_cell_obs u_bsc_59_TL_RX_4_obs (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .si         (bsr_chain[59]),
    .pin_in     (TL_RX_4_pin_in),
    .so         (bsr_chain[60])
  );
  assign TL_RX_4_core_in = TL_RX_4_pin_in;   // INTEST is not supported

  //--- uPAD_TL_RX_5 : TL_RX[5]  (input, left, ring 64) ---
  //    chain cells 60 (TDI order) = BSDL cells 15
  bscan_cell_obs u_bsc_60_TL_RX_5_obs (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .si         (bsr_chain[60]),
    .pin_in     (TL_RX_5_pin_in),
    .so         (bsr_chain[61])
  );
  assign TL_RX_5_core_in = TL_RX_5_pin_in;   // INTEST is not supported

  //--- uPAD_TL_RX_6 : TL_RX[6]  (input, left, ring 65) ---
  //    chain cells 61 (TDI order) = BSDL cells 14
  bscan_cell_obs u_bsc_61_TL_RX_6_obs (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .si         (bsr_chain[61]),
    .pin_in     (TL_RX_6_pin_in),
    .so         (bsr_chain[62])
  );
  assign TL_RX_6_core_in = TL_RX_6_pin_in;   // INTEST is not supported

  //--- uPAD_TL_RX_7 : TL_RX[7]  (input, left, ring 66) ---
  //    chain cells 62 (TDI order) = BSDL cells 13
  bscan_cell_obs u_bsc_62_TL_RX_7_obs (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .si         (bsr_chain[62]),
    .pin_in     (TL_RX_7_pin_in),
    .so         (bsr_chain[63])
  );
  assign TL_RX_7_core_in = TL_RX_7_pin_in;   // INTEST is not supported

  //--- uPAD_I2C_SCL : I2C_SCL  (opendrain, left, ring 67) ---
  //    chain cells 63, 64 (TDI order) = BSDL cells 12, 11
  wire I2C_SCL_pad_oe_int;
  bscan_cell_ctl u_bsc_63_I2C_SCL_oe (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .update_dr  (bsr_update_dr),
    .mode       (bsr_mode),
    .si         (bsr_chain[63]),
    .func_in    (I2C_SCL_core_oe),
    .func_out   (I2C_SCL_pad_oe_int),
    .so         (bsr_chain[64])
  );
  // HIGHZ override. oe_inv=false for this pad, so the pad ring takes
  // .OEN(I2C_SCL_pad_oe) and 1'b1 is therefore 'driver off'.
  assign I2C_SCL_pad_oe = bsr_highz ? 1'b1 : I2C_SCL_pad_oe_int;
  bscan_cell_obs u_bsc_64_I2C_SCL_obs (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .si         (bsr_chain[64]),
    .pin_in     (I2C_SCL_pin_in),
    .so         (bsr_chain[65])
  );
  assign I2C_SCL_core_in = I2C_SCL_pin_in;   // INTEST is not supported

  //--- uPAD_I2C_SDA : I2C_SDA  (opendrain, left, ring 68) ---
  //    chain cells 65, 66 (TDI order) = BSDL cells 10, 9
  wire I2C_SDA_pad_oe_int;
  bscan_cell_ctl u_bsc_65_I2C_SDA_oe (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .update_dr  (bsr_update_dr),
    .mode       (bsr_mode),
    .si         (bsr_chain[65]),
    .func_in    (I2C_SDA_core_oe),
    .func_out   (I2C_SDA_pad_oe_int),
    .so         (bsr_chain[66])
  );
  // HIGHZ override. oe_inv=false for this pad, so the pad ring takes
  // .OEN(I2C_SDA_pad_oe) and 1'b1 is therefore 'driver off'.
  assign I2C_SDA_pad_oe = bsr_highz ? 1'b1 : I2C_SDA_pad_oe_int;
  bscan_cell_obs u_bsc_66_I2C_SDA_obs (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .si         (bsr_chain[66]),
    .pin_in     (I2C_SDA_pin_in),
    .so         (bsr_chain[67])
  );
  assign I2C_SDA_core_in = I2C_SDA_pin_in;   // INTEST is not supported

  //--- uPAD_TL_TX_0 : TL_TX[0]  (output, left, ring 71) ---
  //    chain cells 67 (TDI order) = BSDL cells 8
  bscan_cell_ctl u_bsc_67_TL_TX_0_data (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .update_dr  (bsr_update_dr),
    .mode       (bsr_mode),
    .si         (bsr_chain[67]),
    .func_in    (TL_TX_0_core_out),
    .func_out   (TL_TX_0_pad_out),
    .so         (bsr_chain[68])
  );

  //--- uPAD_TL_TX_1 : TL_TX[1]  (output, left, ring 72) ---
  //    chain cells 68 (TDI order) = BSDL cells 7
  bscan_cell_ctl u_bsc_68_TL_TX_1_data (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .update_dr  (bsr_update_dr),
    .mode       (bsr_mode),
    .si         (bsr_chain[68]),
    .func_in    (TL_TX_1_core_out),
    .func_out   (TL_TX_1_pad_out),
    .so         (bsr_chain[69])
  );

  //--- uPAD_TL_TX_2 : TL_TX[2]  (output, left, ring 73) ---
  //    chain cells 69 (TDI order) = BSDL cells 6
  bscan_cell_ctl u_bsc_69_TL_TX_2_data (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .update_dr  (bsr_update_dr),
    .mode       (bsr_mode),
    .si         (bsr_chain[69]),
    .func_in    (TL_TX_2_core_out),
    .func_out   (TL_TX_2_pad_out),
    .so         (bsr_chain[70])
  );

  //--- uPAD_TL_TX_3 : TL_TX[3]  (output, left, ring 74) ---
  //    chain cells 70 (TDI order) = BSDL cells 5
  bscan_cell_ctl u_bsc_70_TL_TX_3_data (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .update_dr  (bsr_update_dr),
    .mode       (bsr_mode),
    .si         (bsr_chain[70]),
    .func_in    (TL_TX_3_core_out),
    .func_out   (TL_TX_3_pad_out),
    .so         (bsr_chain[71])
  );

  //--- uPAD_TL_CLK_TX : TL_CLK_TX  (output, left, ring 77) ---
  //    chain cells 71 (TDI order) = BSDL cells 4
  bscan_cell_ctl u_bsc_71_TL_CLK_TX_data (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .update_dr  (bsr_update_dr),
    .mode       (bsr_mode),
    .si         (bsr_chain[71]),
    .func_in    (TL_CLK_TX_core_out),
    .func_out   (TL_CLK_TX_pad_out),
    .so         (bsr_chain[72])
  );

  //--- uPAD_TL_TX_4 : TL_TX[4]  (output, left, ring 78) ---
  //    chain cells 72 (TDI order) = BSDL cells 3
  bscan_cell_ctl u_bsc_72_TL_TX_4_data (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .update_dr  (bsr_update_dr),
    .mode       (bsr_mode),
    .si         (bsr_chain[72]),
    .func_in    (TL_TX_4_core_out),
    .func_out   (TL_TX_4_pad_out),
    .so         (bsr_chain[73])
  );

  //--- uPAD_TL_TX_5 : TL_TX[5]  (output, left, ring 79) ---
  //    chain cells 73 (TDI order) = BSDL cells 2
  bscan_cell_ctl u_bsc_73_TL_TX_5_data (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .update_dr  (bsr_update_dr),
    .mode       (bsr_mode),
    .si         (bsr_chain[73]),
    .func_in    (TL_TX_5_core_out),
    .func_out   (TL_TX_5_pad_out),
    .so         (bsr_chain[74])
  );

  //--- uPAD_TL_TX_6 : TL_TX[6]  (output, left, ring 80) ---
  //    chain cells 74 (TDI order) = BSDL cells 1
  bscan_cell_ctl u_bsc_74_TL_TX_6_data (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .update_dr  (bsr_update_dr),
    .mode       (bsr_mode),
    .si         (bsr_chain[74]),
    .func_in    (TL_TX_6_core_out),
    .func_out   (TL_TX_6_pad_out),
    .so         (bsr_chain[75])
  );

  //--- uPAD_TL_TX_7 : TL_TX[7]  (output, left, ring 81) ---
  //    chain cells 75 (TDI order) = BSDL cells 0
  bscan_cell_ctl u_bsc_75_TL_TX_7_data (
    .tck        (tck),
    .trst_n     (trst_n),
    .capture_dr (bsr_capture_dr),
    .shift_dr   (bsr_shift_dr),
    .update_dr  (bsr_update_dr),
    .mode       (bsr_mode),
    .si         (bsr_chain[75]),
    .func_in    (TL_TX_7_core_out),
    .func_out   (TL_TX_7_pad_out),
    .so         (bsr_chain[76])
  );

  //---------------------------------------------------------------------------
  // TDO: select the active register, then retime onto the FALLING tck edge
  //---------------------------------------------------------------------------
  // 1149.1 requires TDO to change on the falling edge of TCK so that a tester
  // sampling on the rising edge sees a settled value. The output enable is
  // retimed with it for the same reason.
  wire dr_tdo = sel_boundary ? bsr_chain[76] :
                sel_idcode   ? idcode_q[0]   :
                               bypass_q;

  wire tdo_next = select_ir ? ir_so : dr_tdo;

  logic tdo_q, tdo_oe_q;
  always_ff @(negedge tck or negedge trst_n) begin
    if (!trst_n) begin
      tdo_q    <= 1'b0;
      tdo_oe_q <= 1'b0;
    end else begin
      tdo_q    <= tdo_next;
      tdo_oe_q <= tdo_enable;
    end
  end

  assign tdo    = tdo_q;
  assign tdo_oe = tdo_oe_q;

endmodule
