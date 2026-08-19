#!/usr/bin/env python3
"""gen_bscan.py -- emit the boundary-scan wrapper RTL and its BSDL from ONE ordering.

A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.

Contributors

David Mapstone (d.a.mapstone@soton.ac.uk)

Copyright 2026, SoC Labs (www.soclabs.org)

WHAT THIS DOES
--------------
Reads ``src/rtl/bscan/pad_table.json`` (48 signal pads, already in physical ring
order) and writes two files:

  * ``src/rtl/bscan/nanosoc_eth_chiplet_bscan.sv`` -- the generated 1149.1
    wrapper: TAP + IR + BYPASS + IDCODE + 76 boundary cells, chained TDI-first
    in ring order.
  * ``sys_desc/bscan/nanosoc_eth_chiplet_pads.bsdl`` -- the BSDL description of the
    same chain, numbered TDO-first as BSDL requires.

WHY ONE GENERATOR AND NOT TWO
-----------------------------
A boundary-scan register and its BSDL are the same object described twice. When
they are authored separately they drift, and the drift is invisible until a
board tester shifts a pattern into real silicon and gets nonsense back -- by
which time the die is bonded. So the cell ordering is derived exactly ONCE, in
``build_cells()``. The RTL is rendered from that list front-to-back (TDI first);
the BSDL is rendered from the SAME list with ``bsdl_num = N-1-tdi_index``. There
is no second ordering anywhere in this file, and no way to change one output's
order without changing the other's.

``--check`` re-renders in memory and diffs against what is on disk, exiting
non-zero on any drift. That is the CI gate: it makes "someone hand-edited the
generated RTL" a build failure rather than a silicon failure.

NAMING -- TWO DIFFERENT, BOTH CORRECT
-------------------------------------
The RTL wrapper names its ports after the PAD INSTANCE with ``uPAD_`` stripped
(``uPAD_QSPI_IO_0`` -> ``QSPI_IO_0_pin_in``). The BSDL names ports as the CHIP
sees them, from ``port``/``idx`` (``QSPI_IO(0)``). The instance name is unique
per pad; the top-level port base name is NOT (``QSPI_IO`` is 4 pads, ``TL_RX``
is 8), so it cannot be used for wrapper ports. ``scripts/insert_bscan_padring.py``
builds the instantiation with the same ``short(inst)`` rule -- the two must agree
or the splice will not elaborate.

DETERMINISM
-----------
No timestamps are emitted; the banner carries the SHA-256 of the input table
instead. Same input, same bytes out, always. (Do not run this under ``python -O``
-- the structural checks are ``assert`` statements and -O deletes them.)

Usage
-----
    gen_bscan.py                 # write both outputs
    gen_bscan.py --check         # regenerate to a temp location, diff, rc!=0 on drift
    gen_bscan.py --list          # print the derived cell ordering and exit
"""
from __future__ import annotations

import argparse
import difflib
import hashlib
import json
import pathlib
import sys

# ---------------------------------------------------------------------------
# Paths and fixed facts. Everything else is derived from the pad table.
# ---------------------------------------------------------------------------
ROOT = pathlib.Path(__file__).resolve().parent.parent
TABLE = ROOT / "src/rtl/bscan/pad_table.json"
RTL_OUT = ROOT / "src/rtl/bscan/nanosoc_eth_chiplet_bscan.sv"
BSDL_OUT = ROOT / "sys_desc/bscan/nanosoc_eth_chiplet_pads.bsdl"

MODULE = "nanosoc_eth_chiplet_bscan"
ENTITY = "nanosoc_eth_chiplet_pads"
GENERATOR = "scripts/gen_bscan.py"

IR_WIDTH = 4
EXPECTED_BOUNDARY_LENGTH = 76      # INTERFACE_CONTRACT.md section 1
EXPECTED_PAD_COUNT = 48
IDCODE_VALUE = 0x100005A1          # section 5. PLACEHOLDER -- see the banner text.
TCK_MAX_HZ = 10.0e6                # not yet characterised; declared so the BSDL parses

# Instruction encoding -- INTERFACE_CONTRACT.md section 4. SAMPLE and PRELOAD are
# one opcode (a merged SAMPLE_PRELOAD instruction) but 1149.1-2001 BSDL names them
# separately, so both appear against the same code.
INSTRUCTIONS = [
    ("EXTEST",  "0000"),
    ("SAMPLE",  "0001"),
    ("PRELOAD", "0001"),
    ("IDCODE",  "0010"),
    ("CLAMP",   "0011"),
    # HIGHZ IS DELIBERATELY NOT DECLARED. The opcode is still decoded by bscan_ir
    # and the wrapper still drives every OE cell from it, but 15 of the 48 pads
    # are pure outputs whose OEN is tied low in the pad ring: they have no control
    # cell, so nothing can tri-state them. Declaring HIGHZ while 15 system outputs
    # keep driving is a conformance claim the silicon does not honour, and a
    # tester would trust it -- the exact shape of failure this project keeps
    # recording. Better to not offer the instruction than to offer a broken one.
    #
    # TO MAKE IT REAL: give the 15 `output` pads an OE control cell each (chain
    # 76 -> 91), have insert_bscan_padring.py route their OEN from the register
    # instead of tielo, and put this line back. That also buys EXTEST the ability
    # to tri-state this die's outputs while the other die in the package is
    # tested, which is worth having -- it is scoped work, not a redesign.
]
BYPASS_PRIMARY = "1111"

# Cells per pad kind, ordered FROM TDI. INTERFACE_CONTRACT.md sections 1 and 6.
#   oe ctl -> data ctl -> obs
# open-drain gets NO data cell: its .I is a structural tie-low and the data is
# folded onto OEN. Driving .I on a wired-AND bus is a cross-die short.
ROLES = {
    "input":     ("obs",),
    "output":    ("data",),
    "bidir":     ("oe", "data", "obs"),
    "opendrain": ("oe", "obs"),
}

# The four pads the TAP is muxed onto when SE is high (section 7). Kept in step
# with scripts/insert_bscan_padring.py, which performs the actual mux.
TAP_TCK_PAD = "uPAD_SWDCK_I"
TAP_TMS_PAD = "uPAD_SWDIO_IO"
TAP_TDI_PAD = "uPAD_HOST_IO_0"
TAP_TDO_PAD = "uPAD_HOST_IO_1"
TAP_EN_PAD = "uPAD_SE_I"

BSDL_DIR = {"input": "in", "output": "out", "inout": "inout"}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def short(inst):
    """uPAD_QSPI_IO_0 -> QSPI_IO_0. Unique per pad; the port base name is not."""
    assert inst.startswith("uPAD_"), "pad instance %r does not start with uPAD_" % inst
    return inst[len("uPAD_"):]


def portref(pad):
    """BSDL port reference as the chip sees it: QSPI_IO(0), or NRST for a scalar."""
    return pad["port"] if pad["idx"] is None else "%s(%d)" % (pad["port"], pad["idx"])


def disable_level(pad):
    """The value on the wrapper's *_pad_oe that turns this pad's driver OFF.

    The pad ring re-applies its own inversion downstream of us:
        oe_inv True  -> .OEN(~pad_oe)  so pad_oe = 0 means OEN = 1 = disabled
        oe_inv False -> .OEN( pad_oe)  so pad_oe = 1 means OEN = 1 = disabled
    Every bidir on this die is oe_inv True and both open-drain I2C pads are
    oe_inv False, so a hardcoded constant would be right for 13 pads and exactly
    wrong for the 2 that sit on a shared wired-AND bus. Derive it, never assume.

    The same number is the BSDL `disval` for that pad's control cell, because the
    control cell's content IS pad_oe once mode=1. One derivation, two consumers.
    """
    assert pad["oe_net"], "pad %s has no OE net" % pad["inst"]
    return 0 if pad["oe_inv"] else 1


def sha256_of(path):
    return hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest()


# ---------------------------------------------------------------------------
# THE one ordering
# ---------------------------------------------------------------------------
def build_cells(table):
    """Return (pads_in_ring_order, cells_in_TDI_order).

    This is the single point at which chain order is decided. Both outputs are
    rendered from the returned list; nothing else may sort, reverse or regroup.
    """
    pads = sorted(table["pads"], key=lambda p: p["ring_index"])
    ports = table["ports"]

    assert len(pads) == EXPECTED_PAD_COUNT, \
        "expected %d signal pads, table has %d" % (EXPECTED_PAD_COUNT, len(pads))

    ring = [p["ring_index"] for p in pads]
    assert len(set(ring)) == len(ring), \
        "duplicate ring_index in pad table: two pads cannot occupy one ring slot"

    names = [short(p["inst"]) for p in pads]
    assert len(set(names)) == len(names), \
        "wrapper port prefixes collide: %s" % \
        sorted(n for n in names if names.count(n) > 1)

    for p in pads:
        inst, kind = p["inst"], p["kind"]
        assert kind in ROLES, "pad %s has unknown kind %r" % (inst, kind)
        assert p["port"] in ports, "pad %s names port %r absent from the port map" \
            % (inst, p["port"])
        w = ports[p["port"]]["width"]
        if p["idx"] is None:
            assert w == 1, "pad %s has no index but port %s is %d bits wide" \
                % (inst, p["port"], w)
        else:
            assert 0 <= p["idx"] < w, "pad %s index %d outside %s(%d bits)" \
                % (inst, p["idx"], p["port"], w)

        # Structural invariants per kind. These are what make the role table above
        # safe to apply blindly.
        if kind == "input":
            assert p["c_net"] and not p["i_net"] and not p["oe_net"], \
                "input pad %s should have .C only" % inst
        elif kind == "output":
            assert p["i_net"] and not p["c_net"] and not p["oe_net"], \
                "output pad %s should have .I only" % inst
        elif kind == "bidir":
            assert p["c_net"] and p["i_net"] and p["oe_net"], \
                "bidir pad %s needs .C, .I and OEN" % inst
        elif kind == "opendrain":
            # The non-negotiable rule, section 1 of the contract.
            assert p["i_net"] is None and p["i_tied"] == "tielo", \
                "OPEN-DRAIN VIOLATION: %s must keep .I a structural tie-low" % inst
            assert p["c_net"] and p["oe_net"], \
                "open-drain pad %s needs .C and an OEN data net" % inst

    cells = []
    for p in pads:
        for role in ROLES[p["kind"]]:
            cells.append({
                "tdi_index": len(cells),
                "role": role,
                "pad": p,
                "name": short(p["inst"]),
            })

    n = len(cells)
    assert n == EXPECTED_BOUNDARY_LENGTH, \
        ("boundary length is %d, expected %d. If the pad ring really changed, "
         "BOUNDARY_LENGTH, the BSDL and every tester pattern change with it -- "
         "update EXPECTED_BOUNDARY_LENGTH deliberately, not reflexively." % (n, EXPECTED_BOUNDARY_LENGTH))

    # Every pad covered exactly once, with exactly the roles its kind demands.
    seen = {}
    for c in cells:
        seen.setdefault(c["pad"]["inst"], []).append(c["role"])
    assert len(seen) == len(pads), "a pad in the table got no boundary cells"
    for p in pads:
        assert tuple(seen[p["inst"]]) == ROLES[p["kind"]], \
            "pad %s got roles %s, expected %s" % (p["inst"], seen[p["inst"]], ROLES[p["kind"]])

    # BSDL counts cell 0 at TDO; the RTL chains cell 0 at TDI. This is the ONLY
    # place the two numbering schemes are related.
    for c in cells:
        c["bsdl_num"] = n - 1 - c["tdi_index"]
    assert sorted(c["bsdl_num"] for c in cells) == list(range(n))

    return pads, cells


def pad_ports(pad):
    """Wrapper ports for one pad, in the order INTERFACE_CONTRACT.md section 6 lists."""
    s = short(pad["inst"])
    roles = ROLES[pad["kind"]]
    out = []
    if "obs" in roles:
        out.append(("input", s + "_pin_in"))
    if "data" in roles:
        out.append(("input", s + "_core_out"))
        out.append(("output", s + "_pad_out"))
    if "oe" in roles:
        out.append(("input", s + "_core_oe"))
        out.append(("output", s + "_pad_oe"))
    if "obs" in roles:
        out.append(("output", s + "_core_in"))
    return out


# ---------------------------------------------------------------------------
# Output A -- the SystemVerilog wrapper
# ---------------------------------------------------------------------------
RTL_BANNER = """\
//-----------------------------------------------------------------------------
// {module} -- IEEE 1149.1 boundary-scan register and TAP for the
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
// Generator : {gen}
// Input     : {table}
//             sha256 {sha}
// Regenerate: python3 {gen}
// Verify    : python3 {gen} --check      (CI gate; non-zero on drift)
//
// No timestamp is emitted on purpose: this file must be byte-reproducible from
// its input so that --check means "the RTL matches the pad table", not "the RTL
// was regenerated recently".
//-----------------------------------------------------------------------------
// WHY THIS FILE IS GENERATED
//
// This module and sys_desc/bscan/{entity}.bsdl are the same object
// described twice: a {n}-cell shift register threaded through the pad ring.
// Hand-authored, the two descriptions drift, and the drift only shows up when a
// board tester shifts a pattern into bonded silicon. So both are rendered from
// ONE ordering computed in {gen}: the RTL front-to-back from
// TDI, the BSDL from that same list reversed, because BSDL numbers cell 0 at TDO.
//
// CHAIN ORDER
//
//   TDI enters the cell of the pad with the LOWEST ring_index and leaves at the
//   highest. Within one pad the order from TDI is:  oe ctl -> data ctl -> obs.
//   Cells per pad kind (contract section 1):
//     input     ({n_in:2d} pads) -> 1 obs                       = {c_in:2d} cells
//     output    ({n_out:2d} pads) -> 1 data ctl                  = {c_out:2d} cells
//     bidir     ({n_bi:2d} pads) -> 1 oe ctl + 1 data ctl + obs = {c_bi:2d} cells
//     opendrain ({n_od:2d} pads) -> 1 oe ctl + 1 obs            = {c_od:2d} cells
//                                                       total = {n} cells
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
//   The {n_out} pure-output pads have their OEN tied low in the pad ring and get no
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
"""


def render_rtl(table, pads, cells, table_sha):
    kc = {k: sum(1 for p in pads if p["kind"] == k) for k in ROLES}
    L = []
    L.append(RTL_BANNER.format(
        module=MODULE, gen=GENERATOR, entity=ENTITY,
        table=TABLE.relative_to(ROOT), sha=table_sha, n=len(cells),
        n_in=kc["input"], n_out=kc["output"], n_bi=kc["bidir"], n_od=kc["opendrain"],
        c_in=kc["input"], c_out=kc["output"], c_bi=kc["bidir"] * 3, c_od=kc["opendrain"] * 2,
    ))
    L.append("")

    # ---- port list --------------------------------------------------------
    decls = []
    for p in pads:
        decls.append(("comment",
                      "// %-14s %-14s %-9s side=%-6s ring=%d"
                      % (short(p["inst"]), p["pad"], p["kind"], p["side"], p["ring_index"])))
        for d, nm in pad_ports(p):
            decls.append((d, nm))
    width = max(len(nm) for d, nm in decls if d != "comment")

    L.append("module %s #(" % MODULE)
    L.append("  // IEEE 1149.1 device identification register, contract section 5:")
    L.append("  //   {version[3:0], part[15:0], manufacturer[10:0], 1'b1}")
    L.append("  // PLACEHOLDER. SoC Labs holds no JEDEC manufacturer ID; 0x%03X is invented"
             % ((IDCODE_VALUE >> 1) & 0x7FF))
    L.append("  // and MUST be replaced with an assigned ID before tapeout.")
    L.append("  parameter logic [31:0] IDCODE_VALUE = 32'h%04X_%04X"
             % (IDCODE_VALUE >> 16, IDCODE_VALUE & 0xFFFF))
    L.append(") (")
    L.append("  // --- test access (contract section 7: muxed onto existing pads by SE) ---")
    for d, nm in (("input", "tck"), ("input", "tms"), ("input", "tdi"), ("input", "trst_n")):
        L.append("  %-6s wire %s," % (d, nm))
    L.append("  output wire tdo,")
    L.append("  output wire %-*s   // 1 only while shifting, so TDO can be muxed onto a pad"
             % (width + 1, "tdo_oe,"))
    L.append("")
    L.append("  // --- pad-side and core-side groups, one per signal pad, in ring order ---")
    for i, (d, nm) in enumerate(decls):
        last = (i == len(decls) - 1)
        if d == "comment":
            L.append("")
            L.append("  " + nm)
        else:
            L.append("  %-6s wire %s%s" % (d, nm, "" if last else ","))
    L.append(");")
    L.append("")

    n = len(cells)
    # ---- TAP + IR ---------------------------------------------------------
    L += [
        "  //---------------------------------------------------------------------------",
        "  // TAP controller and instruction register",
        "  //---------------------------------------------------------------------------",
        "  wire tlr;",
        "  wire capture_dr, shift_dr, update_dr;",
        "  wire capture_ir, shift_ir, update_ir;",
        "  wire select_ir, tdo_enable;",
        "",
        "  bscan_tap u_tap (",
        "    .tck        (tck),",
        "    .tms        (tms),",
        "    .trst_n     (trst_n),",
        "    .tlr        (tlr),",
        "    .capture_dr (capture_dr),",
        "    .shift_dr   (shift_dr),",
        "    .update_dr  (update_dr),",
        "    .capture_ir (capture_ir),",
        "    .shift_ir   (shift_ir),",
        "    .update_ir  (update_ir),",
        "    .select_ir  (select_ir),",
        "    .tdo_enable (tdo_enable)",
        "  );",
        "",
        "  wire ir_so;",
        "  wire sel_bypass, sel_idcode, sel_boundary;",
        "  wire ir_mode, ir_highz;",
        "",
        "  // IEEE 1149.1 Clause 6.1.1: the instruction register must be reset in the",
        "  // Test-Logic-Reset STATE, however that state was entered -- including via five",
        "  // TMS=1 clocks with trst_n never asserted. bscan_ir has no `tlr` input, so the",
        "  // reset is synthesised here. It releases on the same rising edge that leaves",
        "  // TLR, so nothing is held reset a cycle longer than the standard allows.",
        "  //",
        "  // Gating `mode`/`highz` with ~tlr (below) is NOT a substitute. That keeps the",
        "  // pads safe while in TLR, but the HELD INSTRUCTION survives, so a stale EXTEST",
        "  // resumes the moment the tester leaves TLR -- and the standard discovery",
        "  // sequence every boundary-scan tool opens with (reset, then shift DR expecting",
        "  // IDCODE) would clock out the 76-bit boundary register instead of the 32-bit",
        "  // ID, and mis-identify the part.",
        "  wire ir_trst_n = trst_n & ~tlr;",
        "",
        "  bscan_ir #(",
        "    .IR_WIDTH (%d)" % IR_WIDTH,
        "  ) u_ir (",
        "    .tck          (tck),",
        "    .trst_n       (ir_trst_n),",
        "    .capture_ir   (capture_ir),",
        "    .shift_ir     (shift_ir),",
        "    .update_ir    (update_ir),",
        "    .si           (tdi),",
        "    .so           (ir_so),",
        "    .sel_bypass   (sel_bypass),",
        "    .sel_idcode   (sel_idcode),",
        "    .sel_boundary (sel_boundary),",
        "    .mode         (ir_mode),",
        "    .highz        (ir_highz)",
        "  );",
        "",
        "  // Transparency made structural. bscan_ir has no `tlr` input, so reaching",
        "  // Test-Logic-Reset through five TMS=1 clocks (rather than through trst_n)",
        "  // would otherwise leave a previously loaded EXTEST driving the pads. 1149.1",
        "  // requires the test logic to be inactive in TLR, so force it here.",
        "  wire bsr_mode  = ir_mode  & trst_n & ~tlr;",
        "  wire bsr_highz = ir_highz & trst_n & ~tlr;",
        "",
        "  //---------------------------------------------------------------------------",
        "  // BYPASS (1 bit) and IDCODE (32 bits)",
        "  //---------------------------------------------------------------------------",
        "  // Every data register shifts ONLY while it is the selected one. shift_dr and",
        "  // capture_dr are TAP STATES, not selections: they are high in Shift-DR and",
        "  // Capture-DR whichever register is active. See the note on sel_boundary below",
        "  // for why that distinction is load-bearing.",
        "  logic bypass_q;",
        "  always_ff @(posedge tck or negedge trst_n) begin",
        "    if (!trst_n)                      bypass_q <= 1'b0;",
        "    else if (capture_dr & sel_bypass) bypass_q <= 1'b0;   // 1149.1: BYPASS captures 0",
        "    else if (shift_dr   & sel_bypass) bypass_q <= tdi;",
        "  end",
        "",
        "  logic [31:0] idcode_q;",
        "  always_ff @(posedge tck or negedge trst_n) begin",
        "    if (!trst_n)                      idcode_q <= IDCODE_VALUE;",
        "    else if (capture_dr & sel_idcode) idcode_q <= IDCODE_VALUE;",
        "    else if (shift_dr   & sel_idcode) idcode_q <= {tdi, idcode_q[31:1]};   // LSB first out",
        "  end",
        "",
        "  //---------------------------------------------------------------------------",
        "  // Boundary register: %d cells, TDI-first in physical ring order" % n,
        "  //---------------------------------------------------------------------------",
        "  // bsr_chain[i] is the scan input of cell i and the scan output of cell i-1,",
        "  // so bsr_chain[0] is TDI and bsr_chain[%d] is the far end of the chain." % n,
        "  wire [%d:0] bsr_chain;" % n,
        "  assign bsr_chain[0] = tdi;",
        "",
        "  wire bsr_capture_dr = capture_dr & sel_boundary;",
        "  wire bsr_shift_dr   = shift_dr   & sel_boundary;",
        "  wire bsr_update_dr  = update_dr  & sel_boundary;",
        "",
    ]

    # ---- the cells --------------------------------------------------------
    by_pad = {}
    for c in cells:
        by_pad.setdefault(c["pad"]["inst"], []).append(c)

    for p in pads:
        s = short(p["inst"])
        group = by_pad[p["inst"]]
        nums = ", ".join(str(c["tdi_index"]) for c in group)
        bnums = ", ".join(str(c["bsdl_num"]) for c in group)
        L.append("  //--- %s : %s  (%s, %s, ring %d) ---"
                 % (p["inst"], p["pad"], p["kind"], p["side"], p["ring_index"]))
        L.append("  //    chain cells %s (TDI order) = BSDL cells %s" % (nums, bnums))
        for c in group:
            i = c["tdi_index"]
            role = c["role"]
            iname = "u_bsc_%02d_%s_%s" % (i, s, role)
            if role == "obs":
                L += [
                    "  bscan_cell_obs %s (" % iname,
                    "    .tck        (tck),",
                    "    .trst_n     (trst_n),",
                    "    .capture_dr (bsr_capture_dr),",
                    "    .shift_dr   (bsr_shift_dr),",
                    "    .si         (bsr_chain[%d])," % i,
                    "    .pin_in     (%s_pin_in)," % s,
                    "    .so         (bsr_chain[%d])" % (i + 1),
                    "  );",
                ]
            else:
                if role == "oe":
                    fin, fout = s + "_core_oe", s + "_pad_oe_int"
                    L.append("  wire %s;" % fout)
                else:
                    fin, fout = s + "_core_out", s + "_pad_out"
                L += [
                    "  bscan_cell_ctl %s (" % iname,
                    "    .tck        (tck),",
                    "    .trst_n     (trst_n),",
                    "    .capture_dr (bsr_capture_dr),",
                    "    .shift_dr   (bsr_shift_dr),",
                    "    .update_dr  (bsr_update_dr),",
                    "    .mode       (bsr_mode),",
                    "    .si         (bsr_chain[%d])," % i,
                    "    .func_in    (%s)," % fin,
                    "    .func_out   (%s)," % fout,
                    "    .so         (bsr_chain[%d])" % (i + 1),
                    "  );",
                ]
                if role == "oe":
                    d = disable_level(p)
                    L.append("  // HIGHZ override. oe_inv=%s for this pad, so the pad ring takes"
                             % str(p["oe_inv"]).lower())
                    L.append("  // .OEN(%s%s_pad_oe) and 1'b%d is therefore 'driver off'."
                             % ("~" if p["oe_inv"] else "", s, d))
                    L.append("  assign %s_pad_oe = bsr_highz ? 1'b%d : %s_pad_oe_int;" % (s, d, s))
        if "obs" in ROLES[p["kind"]]:
            L.append("  assign %s_core_in = %s_pin_in;   // INTEST is not supported" % (s, s))
        L.append("")

    # ---- TDO --------------------------------------------------------------
    L += [
        "  //---------------------------------------------------------------------------",
        "  // TDO: select the active register, then retime onto the FALLING tck edge",
        "  //---------------------------------------------------------------------------",
        "  // 1149.1 requires TDO to change on the falling edge of TCK so that a tester",
        "  // sampling on the rising edge sees a settled value. The output enable is",
        "  // retimed with it for the same reason.",
        "  wire dr_tdo = sel_boundary ? bsr_chain[%d] :" % n,
        "                sel_idcode   ? idcode_q[0]   :",
        "                               bypass_q;",
        "",
        "  wire tdo_next = select_ir ? ir_so : dr_tdo;",
        "",
        "  logic tdo_q, tdo_oe_q;",
        "  always_ff @(negedge tck or negedge trst_n) begin",
        "    if (!trst_n) begin",
        "      tdo_q    <= 1'b0;",
        "      tdo_oe_q <= 1'b0;",
        "    end else begin",
        "      tdo_q    <= tdo_next;",
        "      tdo_oe_q <= tdo_enable;",
        "    end",
        "  end",
        "",
        "  assign tdo    = tdo_q;",
        "  assign tdo_oe = tdo_oe_q;",
        "",
        "endmodule",
        "",
    ]
    return "\n".join(L)


# ---------------------------------------------------------------------------
# Output B -- the BSDL
# ---------------------------------------------------------------------------
def bsdl_cell_entry(cell, cells):
    """One BOUNDARY_REGISTER entry plus a trailing comment.

    ccell cross-referencing scheme
    ------------------------------
    A BSDL `output3` cell must name the boundary cell that can disable its driver
    (`ccell`), the value in THAT cell which disables it (`disval`), and the pin
    state that results (`rslt`). Our scheme:

      bidir     : the data cell's ccell is the BSDL number of the SAME PAD's oe
                  cell. Those two cells are adjacent in the chain (oe then data,
                  from TDI), so in BSDL numbering the oe cell is data_num + 1.
                  We do not compute it that way -- we look it up by pad instance,
                  so the reference stays correct if the intra-pad order ever moves.
      opendrain : there is only ONE ctl cell and it drives OEN directly, so the
                  cell that carries the data IS the cell that disables the driver.
                  Its ccell points at itself. Cell = 1 releases the bus (Z, pulled
                  up); cell = 0 drives low. This is the standard merged open-drain
                  description.
      output    : a pure output pad has OEN tied low in the pad ring and no oe
                  cell exists, so there is no control cell to name. It is declared
                  `output2` (a driver that cannot be disabled), not `output3`.

    disval is never a literal here: it comes from disable_level(), which reads
    oe_inv out of the pad table.
    """
    p = cell["pad"]
    num = cell["bsdl_num"]
    ref = portref(p)
    tag = "%s %s" % (p["inst"], cell["role"])

    if cell["role"] == "obs":
        # BC_4 is observe-only: capture and shift, no update flop, no functional
        # path -- exactly what bscan_cell_obs is.
        return "%d (BC_4, %s, input, X)" % (num, ref), tag

    if cell["role"] == "data":
        if p["kind"] == "output":
            return "%d (BC_1, %s, output2, X)" % (num, ref), tag
        oe = next(c for c in cells
                  if c["pad"]["inst"] == p["inst"] and c["role"] == "oe")
        d = disable_level(p)
        return "%d (BC_1, %s, output3, X, %d, %d, Z)" % (num, ref, oe["bsdl_num"], d), tag

    # role == "oe"
    d = disable_level(p)
    if p["kind"] == "opendrain":
        return "%d (BC_1, %s, output3, %d, %d, %d, Z)" % (num, ref, d, num, d), tag
    # A control cell is not associated with a single pin in BSDL, hence `*`.
    # Its safe value is its disable value: a PRELOAD of safe values must leave
    # every driver off.
    return "%d (BC_1, *, control, %d)" % (num, d), tag


BSDL_BANNER = """\
--------------------------------------------------------------------------------
-- {entity}.bsdl -- IEEE 1149.1-2001 boundary-scan description
-- for the nanoSoC ethernet chiplet pad ring (TSMC 65LP, wirebond).
--
-- A joint work commissioned on behalf of SoC Labs, under Arm Academic Access
-- license.
--
-- Contributors
--
-- David Mapstone (d.a.mapstone@soton.ac.uk)
--
-- Copyright 2026, SoC Labs (www.soclabs.org)
--------------------------------------------------------------------------------
-- AUTO-GENERATED FILE - DO NOT EDIT DIRECTLY.
-- Generator : {gen}
-- Input     : {table}
--             sha256 {sha}
-- Regenerate: python3 {gen}
-- Verify    : python3 {gen} --check
--
-- This file and src/rtl/bscan/{module}.sv are rendered from ONE cell
-- ordering. The RTL chains cell 0 at TDI; BSDL numbers cell 0 at TDO, so the
-- numbering here is the reverse of the RTL's -- by construction, not by hand.
--
-- PORT NAMES: this file names the chip's PINS (QSPI_IO(0)). The RTL wrapper names
-- its ports after the PAD INSTANCE (QSPI_IO_0_pin_in) because the top-level port
-- base name is not unique per pad. Both are correct; they are different
-- namespaces, and neither is a bug.
--------------------------------------------------------------------------------
-- OPEN ITEMS -- this file is NOT yet fit to hand to a board-test house
--
--  1. PIN NUMBERS ARE PLACEHOLDERS. The bond map does not exist yet, so the
--     WIREBOND constant below maps every port to a TBD_* token. Replace all of
--     them with real pin/pad numbers before release.
--  2. NO POWER, GROUND OR ANALOG PINS ARE DECLARED. The pad table covers the {npads}
--     SIGNAL pads only. A released BSDL must also declare the supply pads as
--     `linkage bit`.
--  3. IDCODE IS A PLACEHOLDER. SoC Labs holds no JEDEC manufacturer ID.
--  4. HIGHZ CANNOT TRI-STATE THE {nout} PURE-OUTPUT PADS. Their OEN is tied low in
--     the pad ring and they have no control cell, so they are declared `output2`.
--     1149.1 expects HIGHZ to place ALL system outputs in an inactive drive
--     state; on this die it can only disable the {nbi} bidir and {nod} open-drain
--     pads, which are the ones that have an output enable at all. Declared here
--     rather than discovered on a tester.
--  5. THE TAP IS MUXED ONTO FUNCTIONAL PINS, not dedicated ones. See the
--     COMPLIANCE_PATTERNS attribute and the note above TAP_SCAN_IN.
--------------------------------------------------------------------------------
"""


def render_bsdl(table, pads, cells, table_sha):
    ports = table["ports"]
    by_inst = {p["inst"]: p for p in pads}
    n = len(cells)
    n_out = sum(1 for p in pads if p["kind"] == "output")

    L = []
    L.append(BSDL_BANNER.format(
        entity=ENTITY, gen=GENERATOR, table=TABLE.relative_to(ROOT), sha=table_sha,
        module=MODULE, npads=len(pads), nout=n_out,
        nbi=sum(1 for p in pads if p["kind"] == "bidir"),
        nod=sum(1 for p in pads if p["kind"] == "opendrain")))
    L.append("entity %s is" % ENTITY)
    L.append("  generic (PHYSICAL_PIN_MAP : string := \"WIREBOND\");")
    L.append("")
    L.append("  port (")
    pnames = list(ports.keys())
    w = max(len(x) for x in pnames)
    for i, nm in enumerate(pnames):
        d = BSDL_DIR[ports[nm]["dir"]]
        width = ports[nm]["width"]
        typ = "bit" if width == 1 else "bit_vector(%d downto 0)" % (width - 1)
        L.append("    %-*s : %-5s %s%s" % (w, nm, d, typ, "" if i == len(pnames) - 1 else ";"))
    L.append("  );")
    L.append("")
    L.append("  use STD_1149_1_2001.all;")
    L.append("")
    L.append("  attribute COMPONENT_CONFORMANCE of %s : entity is" % ENTITY)
    L.append("    \"STD_1149_1_2001\";")
    L.append("")

    # ---- pin map ----------------------------------------------------------
    L.append("  --  PLACEHOLDER PIN MAP. No bond map exists yet, so every pin is a TBD_*")
    L.append("  --  token rather than a number. Bus entries are listed leftmost-first, i.e.")
    L.append("  --  MSB down to LSB, matching the port's `N downto 0` range.")
    L.append("  attribute PIN_MAP of %s : entity is PHYSICAL_PIN_MAP;" % ENTITY)
    L.append("")
    L.append("  constant WIREBOND : PIN_MAP_STRING :=")
    entries = []
    for nm in pnames:
        width = ports[nm]["width"]
        if width == 1:
            entries.append("%s : TBD_%s" % (nm, nm))
        else:
            entries.append("%s : (%s)" % (nm, ", ".join(
                "TBD_%s_%d" % (nm, bit) for bit in range(width - 1, -1, -1))))
    for i, e in enumerate(entries):
        last = (i == len(entries) - 1)
        text = e if last else e + ","
        # Long bus entries are split across concatenated string literals: BSDL only
        # ever sees the concatenation, so the split point is free, and lines stay
        # inside the 132-column convention that older BSDL readers assume.
        chunks, cur = [], ""
        for tok in text.split(" "):
            if cur and len(cur) + 1 + len(tok) > 84:
                chunks.append(cur + " ")
                cur = tok
            else:
                cur = tok if not cur else cur + " " + tok
        chunks.append(cur)
        for j, ch in enumerate(chunks):
            L.append("    \"%s\"%s" % (ch, ";" if (last and j == len(chunks) - 1) else " &"))
    L.append("")

    # ---- TAP pins ---------------------------------------------------------
    tck_p, tms_p = by_inst[TAP_TCK_PAD], by_inst[TAP_TMS_PAD]
    tdi_p, tdo_p = by_inst[TAP_TDI_PAD], by_inst[TAP_TDO_PAD]
    en_p = by_inst[TAP_EN_PAD]
    L += [
        "  --  TAP PIN ASSIGNMENT -- READ THIS BEFORE USING THE FILE.",
        "  --",
        "  --  This die has NO dedicated TAP pads. The TAP is muxed onto four existing",
        "  --  functional pads, gated by the %s pad (contract section 7):" % en_p["port"],
        "  --      TCK   <- %-12s (%s)" % (portref(tck_p), tck_p["inst"]),
        "  --      TMS   <- %-12s (%s)" % (portref(tms_p), tms_p["inst"]),
        "  --      TDI   <- %-12s (%s)" % (portref(tdi_p), tdi_p["inst"]),
        "  --      TDO   -> %-12s (%s)" % (portref(tdo_p), tdo_p["inst"]),
        "  --      TRST* <- derived from %s internally; there is no TRST pin, so no" % en_p["port"],
        "  --               TAP_SCAN_RESET attribute is emitted.",
        "  --",
        "  --  Two consequences a tester must know:",
        "  --",
        "  --   a) TDI and TDO are ELEMENTS OF A BUS PORT (%s). VHDL attribute" % tdi_p["port"],
        "  --      specifications name whole signals, not bus elements, so the two",
        "  --      attributes below are attached to the bus port and the element is given",
        "  --      in this comment. A strict BSDL parser will read them as naming the",
        "  --      whole 7-bit port. THIS MUST BE RESOLVED BEFORE RELEASE, either by",
        "  --      dedicating scalar TAP pads or by splitting %s(0) and %s(1)" % (tdi_p["port"], tdi_p["port"]),
        "  --      out as scalar ports in this description.",
        "  --   b) All four of those pads still HAVE boundary cells in the chain below",
        "  --      (the length stays %d). But while %s = 1 the pad ring overrides them:" % (n, en_p["port"]),
        "  --      %s is forced to the TAP's TDO and %s / %s are forced" % (portref(tdo_p), portref(tms_p), portref(tdi_p)),
        "  --      input-only. EXTEST therefore CANNOT independently drive %s." % portref(tdo_p),
        "  --      Interconnect tests must treat that net as untestable from this die.",
        "  --   c) TMS rides on %s, an INOUT in functional mode. 1149.1 expects TMS on a"
        % tms_p["port"],
        "  --      dedicated input pin.",
        "  --",
        "  --  TAP_SCAN_IN and TAP_SCAN_OUT below both name %s. That is not a" % tdi_p["port"],
        "  --  copy-paste error -- it is consequence (a) above made visible: TDI is element",
        "  --  (%d) of that bus and TDO is element (%d), and VHDL cannot say so."
        % (tdi_p["idx"], tdo_p["idx"]),
        "  attribute TAP_SCAN_IN    of %-12s : signal is true;   -- element (%d) only"
        % (tdi_p["port"], tdi_p["idx"]),
        "  attribute TAP_SCAN_OUT   of %-12s : signal is true;   -- element (%d) only"
        % (tdo_p["port"], tdo_p["idx"]),
        "  attribute TAP_SCAN_MODE  of %-12s : signal is true;" % tms_p["port"],
        "  --  TCK frequency is NOT yet characterised; %.1f MHz below is a placeholder."
        % (TCK_MAX_HZ / 1.0e6),
        "  attribute TAP_SCAN_CLOCK of %-12s : signal is (%.1fe6, BOTH);"
        % (tck_p["port"], TCK_MAX_HZ / 1.0e6),
        "",
        "  --  %s is the compliance-enable pin: the test logic only exists while it is" % en_p["port"],
        "  --  high. With %s low the TAP is held in Test-Logic-Reset and the chip is" % en_p["port"],
        "  --  bit-for-bit its functional self.",
        "  attribute COMPLIANCE_PATTERNS of %s : entity is" % ENTITY,
        "    \"(%s) (1)\";" % en_p["port"],
        "",
    ]

    # ---- instructions -----------------------------------------------------
    assigned = {code for _, code in INSTRUCTIONS} | {BYPASS_PRIMARY}
    spare = [format(i, "0%db" % IR_WIDTH) for i in range(1 << IR_WIDTH)
             if format(i, "0%db" % IR_WIDTH) not in assigned]
    L.append("  attribute INSTRUCTION_LENGTH of %s : entity is %d;" % (ENTITY, IR_WIDTH))
    L.append("")
    L.append("  --  SAMPLE and PRELOAD share one opcode: the design implements the merged")
    L.append("  --  SAMPLE_PRELOAD instruction. Every unassigned opcode decodes to BYPASS,")
    L.append("  --  which is why they are all listed against it.")
    L.append("  attribute INSTRUCTION_OPCODE of %s : entity is" % ENTITY)
    iw = max(len(nm) for nm, _ in INSTRUCTIONS + [("BYPASS", "")])
    for nm, code in INSTRUCTIONS:
        L.append("    \"%-*s (%s),\" &" % (iw, nm, code))
    L.append("    \"%-*s (%s)\";" % (iw, "BYPASS", ", ".join([BYPASS_PRIMARY] + spare)))
    L.append("")
    L.append("  attribute INSTRUCTION_CAPTURE of %s : entity is" % ENTITY)
    L.append("    \"%s\";" % ("0" * (IR_WIDTH - 2) + "01"))
    L.append("")

    # ---- IDCODE -----------------------------------------------------------
    ver = format((IDCODE_VALUE >> 28) & 0xF, "04b")
    part = format((IDCODE_VALUE >> 12) & 0xFFFF, "016b")
    manuf = format((IDCODE_VALUE >> 1) & 0x7FF, "011b")
    assert int(ver + part + manuf + "1", 2) == IDCODE_VALUE, \
        "IDCODE field split does not recompose to the RTL parameter"
    assert IDCODE_VALUE & 1, "1149.1 requires IDCODE bit 0 to be 1"
    L += [
        "  --  Matches the IDCODE_VALUE parameter of %s (32'h%08X)." % (MODULE, IDCODE_VALUE),
        "  --  PLACEHOLDER: SoC Labs holds no JEDEC manufacturer ID. 0x%03X below is"
        % ((IDCODE_VALUE >> 1) & 0x7FF),
        "  --  invented and MUST be replaced with an assigned ID before tapeout.",
        "  attribute IDCODE_REGISTER of %s : entity is" % ENTITY,
        "    %-22s -- version 0x%X" % ("\"%s\" &" % ver, (IDCODE_VALUE >> 28) & 0xF),
        "    %-22s -- part number 0x%04X" % ("\"%s\" &" % part, (IDCODE_VALUE >> 12) & 0xFFFF),
        "    %-22s -- manufacturer 0x%03X (PLACEHOLDER)"
        % ("\"%s\" &" % manuf, (IDCODE_VALUE >> 1) & 0x7FF),
        "    %-22s -- required by IEEE 1149.1" % "\"1\";",
        "",
    ]

    # ---- boundary register ------------------------------------------------
    od = [p for p in pads if p["kind"] == "opendrain"]
    L += [
        "  attribute BOUNDARY_LENGTH of %s : entity is %d;" % (ENTITY, n),
        "",
        "  --  Cell 0 is the cell CLOSEST TO TDO, per BSDL. The RTL chains cell 0 at TDI,",
        "  --  so this list is the reverse of the RTL's instantiation order; both come",
        "  --  from one ordering in %s." % GENERATOR,
        "  --",
        "  --  Cell types and functions:",
        "  --    BC_4 / input    -- bscan_cell_obs: capture and shift only, no update",
        "  --                       flop and no functional path. Observe-only.",
        "  --    BC_1 / control  -- bscan_cell_ctl on a pad's output enable. `disval` is",
        "  --                       the value in this cell that turns the driver OFF, and",
        "  --                       is derived per pad from oe_inv in the pad table, not",
        "  --                       assumed: the pad ring inverts the enable for the",
        "  --                       bidirs and does not for the open-drain pads.",
        "  --    BC_1 / output3  -- bscan_cell_ctl driving a pad. `ccell` names the",
        "  --                       control cell that can disable it.",
        "  --    BC_1 / output2  -- a driver with NO control cell. The %d pure-output pads" % n_out,
        "  --                       have OEN tied low in the pad ring, so nothing can",
        "  --                       disable them and `output3` would be a lie.",
        "  --",
        "  --  OPEN-DRAIN (%s): one ctl cell, ccell pointing at" % ", ".join(portref(p) for p in od),
        "  --  ITSELF. On these pads .I is a hard tie-low and the DATA is folded onto",
        "  --  OEN, so the cell that carries the data IS the cell that disables the",
        "  --  driver: cell = 1 releases the wired-AND bus (Z, pulled up externally),",
        "  --  cell = 0 drives it low. There is no separate data cell to reference.",
        "  --",
        "  --  BRING-UP WARNING -- EXTEST PARKS I2C LOW. bscan_cell_ctl resets its update",
        "  --  flop to 0, and on these two pads 0 on the OEN cell means DRIVER ENABLED.",
        "  --  So entering EXTEST without first running PRELOAD holds SCL and SDA low and",
        "  --  wedges the bus for every other device on it. 1149.1 requires PRELOAD before",
        "  --  EXTEST, and a wired-AND bus takes no damage from it, but it surprises",
        "  --  people. Load safe values first.",
        "  attribute BOUNDARY_REGISTER of %s : entity is" % ENTITY,
    ]
    entries = [bsdl_cell_entry(c, cells) for c in sorted(cells, key=lambda c: c["bsdl_num"])]
    ew = max(len(e) for e, _ in entries)
    for i, (e, tag) in enumerate(entries):
        last = (i == len(entries) - 1)
        # Pad OUTSIDE the string literal: the concatenated BSDL string should carry
        # only the cell list, not columns of alignment spaces.
        if last:
            L.append("    \"%s\";  -- %s" % (e, tag))
        else:
            L.append("    %-*s &  -- %s" % (ew + 3, "\"%s,\"" % e, tag))
    L.append("")
    L.append("end %s;" % ENTITY)
    L.append("")
    return "\n".join(L)


# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------
def generate(table_path):
    table = json.loads(pathlib.Path(table_path).read_text())
    pads, cells = build_cells(table)
    sha = sha256_of(table_path)
    return pads, cells, render_rtl(table, pads, cells, sha), render_bsdl(table, pads, cells, sha)


def diff(path, want, label):
    have = path.read_text() if path.exists() else ""
    if have == want:
        return 0
    d = difflib.unified_diff(have.splitlines(True), want.splitlines(True),
                             fromfile="%s (on disk)" % label,
                             tofile="%s (regenerated)" % label, n=2)
    sys.stdout.writelines(d)
    if not path.exists():
        print("  (file does not exist)")
    return 1


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--table", default=str(TABLE), help="pad table JSON (default: %(default)s)")
    ap.add_argument("--rtl", default=str(RTL_OUT), help="wrapper output path")
    ap.add_argument("--bsdl", default=str(BSDL_OUT), help="BSDL output path")
    ap.add_argument("--check", action="store_true",
                    help="regenerate in memory, diff against the files on disk, "
                         "exit 1 on any drift (CI gate)")
    ap.add_argument("--list", action="store_true",
                    help="print the derived cell ordering and exit")
    args = ap.parse_args(argv)

    pads, cells, rtl, bsdl = generate(args.table)
    rtl_p, bsdl_p = pathlib.Path(args.rtl), pathlib.Path(args.bsdl)

    if args.list:
        print("%-4s %-4s %-6s %-16s %-14s %-9s %-6s %s"
              % ("TDI", "BSDL", "role", "pad instance", "chip port", "kind", "side", "ring"))
        for c in cells:
            p = c["pad"]
            print("%-4d %-4d %-6s %-16s %-14s %-9s %-6s %d"
                  % (c["tdi_index"], c["bsdl_num"], c["role"], p["inst"], portref(p),
                     p["kind"], p["side"], p["ring_index"]))
        print("\n%d cells over %d pads" % (len(cells), len(pads)))
        return 0

    if args.check:
        rc = diff(rtl_p, rtl, str(rtl_p)) | diff(bsdl_p, bsdl, str(bsdl_p))
        if rc:
            print("\nFAIL: generated boundary-scan output is out of date with %s.\n"
                  "      Run: python3 %s" % (args.table, GENERATOR), file=sys.stderr)
            return 1
        print("OK: %s and %s match %s (%d cells)"
              % (rtl_p.name, bsdl_p.name, pathlib.Path(args.table).name, len(cells)))
        return 0

    for p, text in ((rtl_p, rtl), (bsdl_p, bsdl)):
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text)
        print("wrote %s (%d lines)" % (p, text.count("\n")))
    kinds = {}
    for p in pads:
        kinds[p["kind"]] = kinds.get(p["kind"], 0) + 1
    print("  pads  : %d  %s" % (len(pads), kinds))
    print("  cells : %d  (TDI-first %s .. %s)"
          % (len(cells),
             "%s/%s" % (cells[0]["name"], cells[0]["role"]),
             "%s/%s" % (cells[-1]["name"], cells[-1]["role"])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
