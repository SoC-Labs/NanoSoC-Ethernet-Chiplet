# Boundary-scan interface contract — nanosoc_eth_chiplet

**This file is the single source of truth for module interfaces.** Every module below is
implemented independently. Do not invent, rename, reorder or "improve" any port. If a port
seems wrong, say so in your report — do not silently change it.

Target: IEEE 1149.1-2001, EXTEST/SAMPLE/PRELOAD/BYPASS/IDCODE/HIGHZ/CLAMP.
Technology: TSMC 65LP, `tcbn65lp`. Plain synthesisable SystemVerilog — **no vendor cells,
no DesignWare instantiation, no `initial` blocks, no `#` delays** in RTL.

---

## 0. House style (match the existing repo)

- File header: `//---` rule, module name + one-line purpose, "A joint work commissioned on
  behalf of SoC Labs, under Arm Academic Access license.", Contributors, `Copyright 2026,
  SoC Labs (www.soclabs.org)`, then a `//---` rule and a WHY commentary block.
- Comment the *why*, not the *what*. Explain non-obvious structure.
- `always_ff @(posedge clk or negedge rst_n)` style; active-low async resets named `*_n`.
- Two-space indent, ports one per line, aligned.

---

## 1. Pad table — the data everything derives from

`src/rtl/bscan/pad_table.json`, produced by `scripts/gen_pad_table.py` from the padring RTL
and the Innovus `.io` file. **48 signal pads**, already sorted into physical ring order
(clockwise: top L→R, right T→B, bottom R→L, left B→T).

```
ports : { <top_port_name>: {dir, width} }
pads  : [ { inst, cell, kind, pad, port, idx, c_net, i_net, oe_net, oe_inv,
            ren, i_tied, ring_index, side } ]
```

`kind` is one of:

| kind | count | meaning | BSR cells |
|---|---:|---|---:|
| `input` | 18 | `OEN` tied high; only `.C` used | 1 obs |
| `output` | 15 | `OEN` tied low; `.C()` left open | 1 ctl |
| `bidir` | 13 | `OEN` driven by `oe_net` (invert per `oe_inv`) | 1 obs + 2 ctl |
| `opendrain` | 2 | **I²C only.** `.I` hard-tied low, `.OEN` driven by the DATA net | 1 obs + 1 ctl |

**Total = 76 cells.**

### ⚠ The open-drain rule — non-negotiable

The two I²C pads (`uPAD_I2C_SCL`, `uPAD_I2C_SDA`) are open-drain built from a push-pull
cell: `.I` is hard-tied `1'b0` and the data is folded onto `.OEN`, so "send 1" tri-states
and an external pull-up makes the high. This is a wired-AND bus.

**Never drive `.I` on these two pads.** A 16 mA push-pull driver on a wired-AND bus is a
cross-die short that no tool warns about. `scripts/check_chip_boundary.py` already asserts
that `.I` must remain a structural tie-low and will fail the build if it is not. So an
open-drain pad gets exactly **one obs cell** (on `.C`) and **one ctl cell** (on the `oe_net`),
and `.I` stays `tielo`.

---

## 2. `bscan_cell.sv` — the two cell primitives

Both cells are clocked by `tck` and shift on `shift_dr`. Capture and shift share one flop
(standard mux-D), with a separate update flop on the falling edge of `tck` for ctl cells.

### 2a. `bscan_cell_obs` — observe-only (input pads, and the input half of bidirs)

```systemverilog
module bscan_cell_obs (
  input  wire tck,          // test clock
  input  wire trst_n,       // async reset, active low
  input  wire capture_dr,   // 1 = load pin_in on the next tck rising edge
  input  wire shift_dr,     // 1 = shift (takes priority over capture)
  input  wire si,           // scan in
  input  wire pin_in,       // the value observed at the pad
  output wire so            // scan out (combinational from the shift flop)
);
```

Behaviour: on `posedge tck`, if `shift_dr` load `si`, else if `capture_dr` load `pin_in`,
else hold. `so` is the flop output. No update flop, no functional path — this cell only
watches.

### 2b. `bscan_cell_ctl` — capture / update / drive (outputs, and the driving half of bidirs)

```systemverilog
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
```

Behaviour: shift/capture flop as above but captures `func_in`. The update flop loads from
the shift flop on the **falling** edge of `tck` when `update_dr` is high — this is required
by 1149.1 so the driven value does not glitch mid-shift. `func_out = mode ? update_q : func_in`.

**`mode` must be 0 whenever the TAP is not in EXTEST/CLAMP/HIGHZ**, so normal operation is
bit-for-bit unchanged. Reset (`trst_n` low) must clear the update flop and force `mode`
transparent at the wrapper level.

---

## 3. `bscan_tap.sv` — the 1149.1 TAP controller

```systemverilog
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
```

The standard 16-state FSM. States, and the encoding to use:

```
TLR=4'h0 RTI=4'h1 SEL_DR=4'h2 CAP_DR=4'h3 SHIFT_DR=4'h4 EXIT1_DR=4'h5
PAUSE_DR=4'h6 EXIT2_DR=4'h7 UPDATE_DR=4'h8 SEL_IR=4'h9 CAP_IR=4'hA
SHIFT_IR=4'hB EXIT1_IR=4'hC PAUSE_IR=4'hD EXIT2_IR=4'hE UPDATE_IR=4'hF
```

Requirements:
- State advances on **`posedge tck`** per `tms`.
- Five consecutive `tms=1` must reach TLR from any state — verify this in your own reasoning.
- `trst_n` low forces TLR asynchronously.
- `update_dr`/`update_ir` are asserted **in** the Update state; the wrapper uses them on the
  falling `tck` edge.

## 4. `bscan_ir.sv` — instruction register and decode

```systemverilog
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
  output wire sel_boundary,  // EXTEST | SAMPLE_PRELOAD. NOT clamp -- see the table.
  output wire mode,          // drive the boundary register onto the pads
  output wire highz          // tri-state all outputs
);
```

Instruction encoding (IR_WIDTH = 4):

| Instruction | Code | `sel_*` | `mode` | `highz` |
|---|---|---|---|---|
| `EXTEST` | `4'b0000` | boundary | 1 | 0 |
| `SAMPLE_PRELOAD` | `4'b0001` | boundary | 0 | 0 |
| `IDCODE` | `4'b0010` | idcode | 0 | 0 |
| `CLAMP` | `4'b0011` | bypass | 1 | 0 |
| `HIGHZ` | `4'b0100` | bypass | 0 | 1 |
| `BYPASS` | `4'b1111` | bypass | 0 | 0 |
| *(all others)* | — | bypass | 0 | 0 |

- `capture_ir` must load `IR_WIDTH'b01` into the low two bits (1149.1 mandates `...01`).
- On `trst_n` low the instruction resets to **IDCODE**.
- The instruction takes effect on `update_ir`; the shift register is separate from the
  held instruction.

## 5. IDCODE

32-bit, `{version[3:0], part[15:0], manuf[10:0], 1'b1}`.

Use `32'h0000_05A1` as a **placeholder base** and parameterise it:
`parameter logic [31:0] IDCODE_VALUE = 32'h1_0000_05A1;` — version 1, part `0x0000`,
manufacturer `0x2D0>>1`. **Flag in your report that SoC Labs has no JEDEC manufacturer ID
and this must be assigned before tapeout.** LSB must be 1.

---

## 6. Top wrapper — `nanosoc_eth_chiplet_bscan.sv` (GENERATED, do not hand-write)

Generated by `scripts/gen_bscan.py` from `pad_table.json`. Interface:

```systemverilog
module nanosoc_eth_chiplet_bscan (
  // --- test access ---
  input  wire tck,
  input  wire tms,
  input  wire tdi,
  input  wire trst_n,
  output wire tdo,
  output wire tdo_oe,        // 1 only while shifting, so TDO can be muxed onto a pad

  // --- 48 pad-side and core-side buses, one group per pad ---
  //  For every pad P:
  //    input  wire P_pin_in     (pads with an obs cell)  -- from the pad's .C
  //    input  wire P_core_out   (pads with a data ctl)   -- from the core
  //    output wire P_pad_out    (pads with a data ctl)   -- to the pad's .I
  //    input  wire P_core_oe    (bidir/opendrain)        -- from the core
  //    output wire P_pad_oe     (bidir/opendrain)        -- to the pad's OEN logic
  //    output wire P_core_in    (pads with an obs cell)  -- to the core (= P_pin_in;
  //                                                        INTEST is not supported)
);
```

Chain order: **TDI enters the cell of the pad with the LOWEST `ring_index`**; TDO leaves the
highest. Within one pad the order from TDI is: `oe ctl` → `data ctl` → `obs`.

BSDL numbers cells with **0 closest to TDO**, i.e. the reverse of the TDI-first order. The
generator must emit both the RTL and the BSDL from this one ordering so they cannot disagree.

---

## 7. Chip-level pin strategy — NO NEW PADS

The TAP is muxed onto existing pads, gated by the `SE` pad, which is currently bonded and
drives nothing at all (its core-side net is `UNCONNECTED2828` in the shipping netlist).

| TAP signal | Comes from | When `SE = 1` |
|---|---|---|
| `TCK`  | `SWDCK` pad | SWD clock is stolen by the TAP |
| `TMS`  | `SWDIO` pad (input side) | |
| `TDI`  | `HOSTIO4_P1[0]` (input side) | |
| `TDO`  | `HOSTIO4_P1[1]` (output side, enabled by `tdo_oe`) | |
| `TRST_n` | `SE` (**not** `~SE`) | `trst_n` is active-low, so `SE=0` holds the TAP in Test-Logic-Reset and `SE=1` releases it. An earlier revision of this table said `~SE`, which would have held the TAP in reset exactly when boundary scan was wanted. |

`SE = 0` is the functional default: `trst_n = 0` holds the TAP in TLR, the instruction resets
to IDCODE, `mode = 0`, and every ctl cell is transparent. **Normal operation must be
bit-identical to today.** That property is the single most important thing to preserve, and
the testbench must prove it.

`TEST` is left completely alone — it already drives `CGBYPASS`/`RSTBYPASS` and coupling
boundary scan to it would change functional reset behaviour.
