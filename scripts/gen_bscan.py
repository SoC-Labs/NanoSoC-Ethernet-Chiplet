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

# IDENTITY IS NOT HARDCODED. It is read from the pad table's `design` block by
# load_design(), so a second chiplet needs no edit to this file -- only its own
# table. The module-level names below are placeholders that load_design()
# overwrites before anything uses them; they exist so the module still imports.
MODULE = None
ENTITY = None
GENERATOR = "scripts/gen_bscan.py"

IR_WIDTH = 4
# DERIVED, never literals. eth is 76 cells over 48 pads; compute is 80 over 62.
# A hardcoded expectation is how a silently-dropped pad passes review, so these
# come from the table and the assert compares the chain built here against the
# count the parser independently derived from the ring.
EXPECTED_BOUNDARY_LENGTH = None
EXPECTED_PAD_COUNT = None
IDCODE_VALUE = None                # bound from the pad table by load_design()
JEDEC_ALLOC = None                 # {"bank": n, "code": n} once JEDEC assigns one; see
                                   # check_idcode_manufacturer(). None => the manufacturer
                                   # field must be 0, the one value JEP106 can never issue.
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
TAP_TCK_PAD = None
TAP_TMS_PAD = None
TAP_TDI_PAD = None
TAP_TDO_PAD = None
TAP_EN_PAD = None

BSDL_DIR = {"input": "in", "output": "out", "inout": "inout"}

# The BSDL port clause and the pad -> port-reference map it implies. Both are
# built once by bsdl_port_model() and bound here by load_design(); nothing else
# may decide what a port is called in the BSDL. See bsdl_port_model() for why
# the two TAP data pins are not simply bits of their bus.
BSDL_PORT_DECLS = []
BSDL_PORT_REFS = {}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def short(inst):
    """uPAD_QSPI_IO_0 -> QSPI_IO_0. Unique per pad; the port base name is not."""
    assert inst.startswith("uPAD_"), "pad instance %r does not start with uPAD_" % inst
    return inst[len("uPAD_"):]


def portref(pad):
    """BSDL port reference for one pad: QSPI_IO(0), NRST, or -- for a TAP data pin
    peeled out of its bus by bsdl_port_model() -- the scalar HOSTIO4_P1_0.

    The map is consulted rather than recomputed so that the port CLAUSE and every
    reference to it come from one derivation. The fallback is the plain chip-port
    form, used only before load_design() has run.
    """
    ref = BSDL_PORT_REFS.get((pad["port"], pad["idx"]))
    if ref is not None:
        return ref
    return pad["port"] if pad["idx"] is None else "%s(%d)" % (pad["port"], pad["idx"])


def pin_token(port, idx):
    """Placeholder physical-pin token for one pad.

    Keyed on the CHIP's port and bit, NEVER on the BSDL port name. That is the
    whole point: bsdl_port_model() may rename a pin's port in the description, and
    when it does, the physical pin it maps to must not move.
    """
    return "TBD_%s" % port if idx is None else "TBD_%s_%d" % (port, idx)


def bsdl_port_model(table):
    """Derive the BSDL port clause from the chip's port map. Returns (decls, refs).

    WHY THIS EXISTS -- THE MUXED-TAP PROBLEM
    ----------------------------------------
    This die has no dedicated JTAG pads: TDI and TDO are bits 0 and 1 of the 7-bit
    functional port HOSTIO4_P1 (INTERFACE_CONTRACT.md section 7). BSDL is a subset
    of VHDL, and a VHDL attribute specification names a whole signal -- there is no
    legal way to write

        attribute TAP_SCAN_IN of HOSTIO4_P1(0) : signal is true;

    An earlier revision therefore attached TAP_SCAN_IN *and* TAP_SCAN_OUT to the
    whole bus, which does not merely lose the index: it asserts that all seven pins
    are TDI and all seven are simultaneously TDO. A parser that accepts it is told
    something false about the die.

    THE FIX: the two TAP bits are declared as SCALAR ports named <PORT>_<bit>, and
    the bus keeps the rest. Bits are NOT renumbered -- HOSTIO4_P1 becomes
    (6 downto 2), not (4 downto 0) -- so a BSDL index still means the same physical
    bit it means in the chip's Verilog, and PIN_MAP still binds every one of them
    to the pin token it had before, because pin_token() is keyed on the chip port.
    The divergence is confined to a port NAME appearing in this description; the
    binding a board tester actually uses (PIN_MAP -> physical pin) is unchanged.

    decls : ordered [{name, dir, msb, lsb, pins}]  -- msb None means a scalar port,
            pins are the physical-pin tokens leftmost-first for PIN_MAP_STRING.
    refs  : {(chip_port, idx): "<reference used everywhere in the BSDL>"}
    """
    ports = table["ports"]
    by_inst = {p["inst"]: p for p in table["pads"]}

    # Only the two TAP DATA pins need peeling. TCK/TMS are attributed the same way
    # and would need the same treatment, so they are collected here too rather than
    # assumed scalar -- on this die they are, on the next one they may not be.
    peel = {}
    for inst in (TAP_TCK_PAD, TAP_TMS_PAD, TAP_TDI_PAD, TAP_TDO_PAD):
        pad = by_inst[inst]
        if pad["idx"] is not None:
            peel.setdefault(pad["port"], set()).add(pad["idx"])

    decls, refs = [], {}

    def scalar(name, direction, port, idx):
        assert name not in ports, \
            ("peeling %s(%d) out of its bus wants the scalar port name %r, which is "
             "already a port of this chip. Rename one of them." % (port, idx, name))
        decls.append({"name": name, "dir": direction, "msb": None, "lsb": None,
                      "pins": [pin_token(port, idx)]})
        refs[(port, idx)] = name

    for nm, spec in ports.items():
        direction, width = BSDL_DIR[spec["dir"]], spec["width"]
        if width == 1:
            decls.append({"name": nm, "dir": direction, "msb": None, "lsb": None,
                          "pins": [pin_token(nm, None)]})
            refs[(nm, None)] = nm
            continue

        cut = peel.get(nm, set())
        rest = [b for b in range(width - 1, -1, -1) if b not in cut]
        if rest:
            # A single `msb downto lsb` port can only describe a contiguous run. A
            # TAP pin in the MIDDLE of a bus would need several sub-vectors and a
            # naming rule for them; refuse rather than emit a description whose bit
            # numbering silently stops matching the chip's.
            assert rest[0] - rest[-1] == len(rest) - 1, \
                ("TAP pins %s of %s leave a non-contiguous remainder %s. This "
                 "generator only splits a bus at its ends; splitting it in the "
                 "middle needs a naming rule that does not exist yet."
                 % (sorted(cut), nm, rest))
        if len(rest) > 1:
            decls.append({"name": nm, "dir": direction, "msb": rest[0], "lsb": rest[-1],
                          "pins": [pin_token(nm, b) for b in rest]})
            for b in rest:
                refs[(nm, b)] = "%s(%d)" % (nm, b)
        elif len(rest) == 1:
            scalar("%s_%d" % (nm, rest[0]), direction, nm, rest[0])
        for b in sorted(cut, reverse=True):
            scalar("%s_%d" % (nm, b), direction, nm, b)

    assert len(refs) == sum(s["width"] for s in ports.values()), \
        "the BSDL port model lost or duplicated a pin"
    assert sum(len(d["pins"]) for d in decls) == len(refs), \
        "the BSDL port model lost or duplicated a physical pin token"
    return decls, refs


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


def check_idcode_manufacturer(idcode, jedec):
    """Refuse an IDCODE whose manufacturer field impersonates somebody.

    WHY THIS IS A HARD GATE AND NOT A COMMENT
    -----------------------------------------
    IDCODE[11:1] is not a free 11-bit number. It is a JEDEC JEP106 identity, packed
    as (continuation_count << 7) | code7, with JEP106's odd-parity bit stripped. Any
    value with code7 in 1..126 therefore NAMES A REAL COMPANY -- if not today's
    assignee then tomorrow's, because JEDEC keeps issuing into these banks.

    This design learned that the expensive way. Its first placeholder, 0x2D0, was
    picked to be meaningless; it decodes to continuation count 5, code 0x50, which
    JEP106 has assigned to Neterion Inc. Silicon carrying it does not announce
    "no vendor" -- scan-chain tools print that company's name, and a tool that keys
    a device description off IDCODE can load the wrong one with no error at all.

    So there are exactly two acceptable states, and this function enforces them:

      * NO ALLOCATION HELD -> the manufacturer field must be 0x000. JEP106 identity
        codes run 1..126, so code 0 is not assigned today and CANNOT be assigned
        later. It is invalid rather than reserved, which is the point: tools render
        it "<invalid>"/unknown and stop, instead of impersonating anyone. This is
        also what OpenTitan and rocket-chip ship while unallocated.
      * AN ALLOCATION HELD -> the pad table's `design.jedec` block records the bank
        and code JEDEC issued, and the manufacturer field is DERIVED from them here.
        Recording the allocation is then the only way to get a non-zero field, so a
        second invented number cannot be typed in by accident.

    Note the failure mode this deliberately does NOT try to prevent: an unallocated
    slot in a populated bank is not a safe placeholder either. Bank index 5 is
    126/126 assigned, and every bank fills over time -- "unused today" is not a
    property you can rely on for the life of a die.
    """
    manuf = (idcode >> 1) & 0x7FF
    if jedec is None:
        assert manuf == 0, (
            "IDCODE manufacturer field is 0x%03X, but this design records no JEDEC "
            "allocation. 0x%03X decodes to JEP106 continuation count %d, code 0x%02X "
            "-- a slot JEDEC either has assigned or may assign, i.e. another company's "
            "identity. Either set the manufacturer field to 0 (the value JEP106 can "
            "never issue) or add a `jedec` block to the pad table's `design` section "
            "recording the bank and code actually assigned to you. "
            "See docs/bscan/JEDEC_ID_REQUEST.md."
            % (manuf, manuf, (manuf >> 7) & 0xF, manuf & 0x7F))
        return None

    bank, code = jedec["bank"], jedec["code"]
    assert 1 <= bank <= 16, \
        "JEP106 bank %r is outside 1..16; the IDCODE carries the count in 4 bits" % bank
    assert 1 <= code <= 126, \
        ("JEP106 identity code 0x%02X is outside 1..126. Code 0 is never issued and "
         "0x7F is the continuation escape -- if JEDEC gave you a byte with its parity "
         "bit set, strip the parity bit before recording it here." % code)
    want = ((bank - 1) << 7) | code
    assert manuf == want, \
        ("IDCODE manufacturer field is 0x%03X but the recorded JEDEC allocation "
         "(bank %d, code 0x%02X) packs to 0x%03X. The packing is "
         "((bank - 1) << 7) | code, with JEP106's odd-parity bit stripped."
         % (manuf, bank, code, want))
    return jedec


def idcode_notes():
    """The sentences that must travel with this IDCODE, wherever it is written down.

    One derivation, two renderers: the wrapper RTL prints these as `//` comments and
    the BSDL as `--` comments, so the die and its description can never disagree
    about whether the number is real.
    """
    manuf = (IDCODE_VALUE >> 1) & 0x7FF
    part = (IDCODE_VALUE >> 12) & 0xFFFF
    if JEDEC_ALLOC is None:
        out = [
            "MANUFACTURER FIELD IS A DECLARED PLACEHOLDER, NOT AN ALLOCATION. SoC Labs "
            "holds no JEDEC JEP106 manufacturer ID. The field is set to 0x%03X, which "
            "JEP106 can never assign to anyone: its identity codes run 1..126, so code "
            "0 is permanently unissuable." % manuf,
            "That is deliberate. It makes this device ANNOUNCE that it is unidentified "
            "rather than impersonate a company. A tester will see the manufacturer "
            "render as \"<invalid>\" or unknown, and IDCODE-keyed lookup will find "
            "nothing and stop -- which is the correct outcome. An invented-but-valid "
            "field would instead resolve to whoever owns it and could silently select "
            "another part's description.",
        ]
    else:
        out = ["Manufacturer field 0x%03X is JEDEC JEP106 bank %d, code 0x%02X, assigned "
               "to this organisation." % (manuf, JEDEC_ALLOC["bank"], JEDEC_ALLOC["code"])]
    if part == 0:
        out.append(
            "THE PART NUMBER FIELD IS ALSO A PLACEHOLDER (0x%04X). It does not "
            "distinguish this die from any other, including the compute chiplet sharing "
            "its package. Assign a real part number before release." % part)
    out.append("See docs/bscan/JEDEC_ID_REQUEST.md for what to change once an ID is held.")
    return out


def sha256_of(path):
    """SHA-256 of a file, stamped into the generated RTL and BSDL."""
    return hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest()


# ---------------------------------------------------------------------------
# THE one ordering
# ---------------------------------------------------------------------------
def load_design(table):
    """Bind this module's identity from the table's `design` block.

    Everything design-specific enters here and nowhere else. gen_pad_table.py
    wrote the block; this reads it. Two tools, one source of truth.
    """
    global MODULE, ENTITY, IDCODE_VALUE, EXPECTED_BOUNDARY_LENGTH, EXPECTED_PAD_COUNT
    global TAP_TCK_PAD, TAP_TMS_PAD, TAP_TDI_PAD, TAP_TDO_PAD, TAP_EN_PAD
    global BSDL_PORT_DECLS, BSDL_PORT_REFS, JEDEC_ALLOC
    d = table.get("design")
    if not d:
        sys.exit("ERROR: pad table has no `design` block -- regenerate it with "
                 "scripts/gen_pad_table.py (it is the tool that writes it).")
    MODULE, ENTITY = d["module"], d["block"]
    IDCODE_VALUE = int(str(d["idcode"]), 0)
    EXPECTED_BOUNDARY_LENGTH = d["boundary_length"]
    EXPECTED_PAD_COUNT = len(table["pads"])
    t = d["tap"]
    TAP_TCK_PAD, TAP_TMS_PAD = t["tck"], t["tms"]
    TAP_TDI_PAD, TAP_TDO_PAD = t["tdi"], t["tdo"]
    TAP_EN_PAD = t["en"]
    assert IDCODE_VALUE & 1, "IEEE 1149.1 requires IDCODE bit 0 == 1"
    # `jedec` is OPTIONAL and absent until an ID is bought. Absent means the guard
    # demands a zero manufacturer field; present means it derives one. Either way the
    # number cannot be invented.
    JEDEC_ALLOC = check_idcode_manufacturer(IDCODE_VALUE, d.get("jedec"))
    # Must follow the TAP binding above: the port clause depends on which pads the
    # TAP is muxed onto. Affects the BSDL only -- the wrapper RTL names its ports
    # after the pad INSTANCE and never consults this.
    BSDL_PORT_DECLS, BSDL_PORT_REFS = bsdl_port_model(table)
    return d


def build_cells(table):
    """Return (pads_in_ring_order, cells_in_TDI_order).

    This is the single point at which chain order is decided. Both outputs are
    rendered from the returned list; nothing else may sort, reverse or regroup.
    """
    load_design(table)
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
    """Render the boundary-scan wrapper RTL as one string."""
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
    # Same sentences as the BSDL emits, from one derivation. The die and its
    # description must not disagree about whether this number identifies anyone.
    for note in idcode_notes():
        L += wrap_comment(note, "  // ", "  // ", width=78)
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
--  3. {idcode_headline}
--  4. HIGHZ CANNOT TRI-STATE THE {nout} PURE-OUTPUT PADS. Their OEN is tied low in
--     the pad ring and they have no control cell, so they are declared `output2`.
--     1149.1 expects HIGHZ to place ALL system outputs in an inactive drive
--     state; on this die it can only disable the {nbi} bidir and {nod} open-drain
--     pads, which are the ones that have an output enable at all. Declared here
--     rather than discovered on a tester.
--  5. THE TAP IS MUXED ONTO FUNCTIONAL PINS, not dedicated ones, and two of
--     them are bits of a bus that this description splits into scalars so the
--     TAP attributes can name them. See COMPLIANCE_PATTERNS, the note above
--     TAP_SCAN_IN, and the DESIGN_WARNING at the end of the file.
--------------------------------------------------------------------------------
"""


def wrap_comment(text, first, cont, width=79):
    """Wrap prose into comment lines, `first` prefixing the first line.

    Used for both outputs -- `--  ` for the BSDL, `  // ` for the wrapper RTL -- so
    that shared prose (the IDCODE notes) is laid out once and cannot drift.

    Generated prose names ports, and port names change per die, so a hand-laid-out
    comment block goes ragged the moment a name gets longer. Wrap it instead.
    Whitespace is collapsed -- never use this for a line whose layout is the point
    (the TAP table, an example of BSDL syntax); those are emitted literally.
    """
    lines, cur, pre = [], "", first
    for word in text.split():
        if cur and len(pre) + len(cur) + 1 + len(word) > width:
            lines.append(pre + cur)
            cur, pre = word, cont
        else:
            cur = word if not cur else cur + " " + word
    lines.append(pre + cur)
    return lines


def bsdl_text(text, indent, width=84):
    """Emit prose as concatenated BSDL string literals, `indent` spaces deep.

    BSDL only ever sees the concatenation, so the split point is free -- but the
    trailing space has to stay ON the chunk or the joined string runs words
    together. Lines stay inside the 132-column convention older readers assume.
    """
    chunks, cur = [], ""
    for tok in text.split(" "):
        if cur and len(cur) + 1 + len(tok) > width:
            chunks.append(cur + " ")
            cur = tok
        else:
            cur = tok if not cur else cur + " " + tok
    chunks.append(cur)
    return ["%s\"%s\"%s" % (" " * indent, ch, ";" if j == len(chunks) - 1 else " &")
            for j, ch in enumerate(chunks)]


def render_bsdl(table, pads, cells, table_sha):
    """Render the BSDL description of the same register as one string."""
    decls = BSDL_PORT_DECLS
    by_inst = {p["inst"]: p for p in pads}
    tck_p, tms_p = by_inst[TAP_TCK_PAD], by_inst[TAP_TMS_PAD]
    tdi_p, tdo_p = by_inst[TAP_TDI_PAD], by_inst[TAP_TDO_PAD]
    en_p = by_inst[TAP_EN_PAD]
    # The TAP pads that are bits of a bus, and so had to be peeled into scalar
    # ports by bsdl_port_model(). Empty on a die with dedicated TAP pads.
    split = [q for q in (tck_p, tms_p, tdi_p, tdo_p) if q["idx"] is not None]
    n = len(cells)
    n_out = sum(1 for p in pads if p["kind"] == "output")

    L = []
    L.append(BSDL_BANNER.format(
        entity=ENTITY, gen=GENERATOR, table=TABLE.relative_to(ROOT), sha=table_sha,
        module=MODULE, npads=len(pads), nout=n_out,
        idcode_headline=(
            "IDCODE IDENTIFIES NO MANUFACTURER. SoC Labs holds no JEDEC\n"
            "--     JEP106 allocation, so the manufacturer field carries 0x%03X -- the one\n"
            "--     code JEP106 can never issue. See the note above IDCODE_REGISTER."
            % ((IDCODE_VALUE >> 1) & 0x7FF)
            if JEDEC_ALLOC is None else
            "IDCODE manufacturer field is JEP106 bank %d code 0x%02X, assigned.\n"
            "--     See the note above IDCODE_REGISTER."
            % (JEDEC_ALLOC["bank"], JEDEC_ALLOC["code"])),
        nbi=sum(1 for p in pads if p["kind"] == "bidir"),
        nod=sum(1 for p in pads if p["kind"] == "opendrain")))
    L.append("entity %s is" % ENTITY)
    L.append("  generic (PHYSICAL_PIN_MAP : string := \"WIREBOND\");")
    L.append("")
    L.append("  port (")
    # bsdl_port_model() decided this list, including the split that peels the TAP
    # data pins out of their bus. Nothing is recomputed here.
    w = max(len(d["name"]) for d in decls)
    for i, d in enumerate(decls):
        typ = "bit" if d["msb"] is None else \
              "bit_vector(%d downto %d)" % (d["msb"], d["lsb"])
        L.append("    %-*s : %-5s %s%s"
                 % (w, d["name"], d["dir"], typ, "" if i == len(decls) - 1 else ";"))
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
    L.append("  --  MSB down to LSB, matching each port's declared range.")
    if split:
        L.append("  --  The TBD_ tokens are keyed on the CHIP's port and bit, so a TAP pin")
        L.append("  --  split out of its bus below still maps to the pin it always did.")
    L.append("  attribute PIN_MAP of %s : entity is PHYSICAL_PIN_MAP;" % ENTITY)
    L.append("")
    L.append("  constant WIREBOND : PIN_MAP_STRING :=")
    entries = []
    for d in decls:
        if d["msb"] is None:
            entries.append("%s : %s" % (d["name"], d["pins"][0]))
        else:
            entries.append("%s : (%s)" % (d["name"], ", ".join(d["pins"])))
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
    def chip_pin(pad):
        """How the chip's own Verilog port list names this pad: HOSTIO4_P1[0]."""
        return pad["port"] if pad["idx"] is None else "%s[%d]" % (pad["port"], pad["idx"])

    # THE GUARD THAT MAKES THE OLD BUG UNREPEATABLE. A BSDL TAP attribute names a
    # whole signal. If any of these four resolved to a bus element, the file would
    # be claiming that EVERY bit of that bus is that TAP pin -- which is exactly
    # what this description used to say about TDI and TDO. bsdl_port_model() peels
    # them into scalars so that this holds; assert it rather than trust it.
    for attr, pad in (("TAP_SCAN_CLOCK", tck_p), ("TAP_SCAN_MODE", tms_p),
                      ("TAP_SCAN_IN", tdi_p), ("TAP_SCAN_OUT", tdo_p)):
        assert "(" not in portref(pad), \
            ("%s would be attributed to %s, which is a bus ELEMENT. A VHDL attribute "
             "specification cannot name one, and naming the whole bus instead declares "
             "every pin of it to be %s." % (attr, portref(pad), attr))
    assert portref(tdi_p) != portref(tdo_p), \
        "TDI and TDO resolve to the same BSDL port; one pin cannot be both"

    L += [
        "  --  TAP PIN ASSIGNMENT -- READ THIS BEFORE USING THE FILE.",
        "  --",
    ]
    L += wrap_comment(
        "This die has NO dedicated TAP pads. The TAP is muxed onto four existing "
        "functional pads, gated by the %s pad (contract section 7):" % en_p["port"],
        "  --  ", "  --  ")
    rw = max(len(portref(q)) for q in (tck_p, tms_p, tdi_p, tdo_p))
    iw = max(len(q["inst"]) for q in (tck_p, tms_p, tdi_p, tdo_p))
    for role, arrow, pad in (("TCK", "<-", tck_p), ("TMS", "<-", tms_p),
                             ("TDI", "<-", tdi_p), ("TDO", "->", tdo_p)):
        L.append("  --      %-5s %s %-*s  %-*s  chip pin %s"
                 % (role, arrow, rw, portref(pad), iw + 2,
                    "(%s)" % pad["inst"], chip_pin(pad)))
    L += [
        "  --      TRST* <- derived from %s internally; there is no TRST pin, so no" % en_p["port"],
        "  --               TAP_SCAN_RESET attribute is emitted.",
        "  --",
    ]

    if split:
        buses = sorted({q["port"] for q in split})
        resid = [d for d in decls if d["name"] in buses]
        names = " and ".join(sorted(portref(q) for q in split))
        L.append("  --  WHY THE PORT CLAUSE SPLITS %s" % ", ".join(buses))
        L.append("  --")
        L += wrap_comment(
            "%s are bits of the chip's %s port, not pins of their own. BSDL is a subset "
            "of VHDL, and a VHDL attribute specification names a WHOLE signal, so"
            % (names, ", ".join(buses)), "  --  ", "  --  ")
        L.append("  --      attribute TAP_SCAN_IN of %s(%d) : signal is true;"
                 % (tdi_p["port"], tdi_p["idx"]))
        L += wrap_comment(
            "cannot be written at all. Attributing the whole bus instead -- which an "
            "earlier revision of this file did, for TAP_SCAN_IN and TAP_SCAN_OUT both "
            "-- does not merely lose the index. It declares every pin of that bus to be "
            "TDI, and every pin of it to be TDO, at the same time. That is false, and a "
            "tool that believes it will shift scan data at innocent pins.",
            "  --  ", "  --  ")
        L.append("  --")
        L += wrap_comment(
            "So those bits are declared in the port clause above as SCALAR ports named "
            "<PORT>_<bit>, and the bus keeps the remainder. NOTHING ABOUT THE DIE MOVES:",
            "  --  ", "  --  ")
        L += wrap_comment(
            "PIN_MAP binds each split-out scalar to the same physical pin the bus entry "
            "used to carry, and a board tester binds nets through PIN_MAP, not through "
            "port names -- so its netlist binding is bit-for-bit unchanged.",
            "  --    * ", "  --      ")
        for d in resid:
            L += wrap_comment(
                "%s keeps its bit numbering, (%d downto %d) -- deliberately NOT "
                "renumbered to (%d downto 0) -- so a BSDL index still means the bit the "
                "chip's Verilog means by it."
                % (d["name"], d["msb"], d["lsb"], d["msb"] - d["lsb"]),
                "  --    * ", "  --      ")
        L += wrap_comment(
            "the boundary register below names those pins by the same new names. The "
            "chain, its length and its order are untouched.",
            "  --    * ", "  --      ")
        L.append("  --")
        L += wrap_comment(
            "The one thing that DOES diverge is the port NAME: the chip's Verilog port "
            "list still declares %s. That divergence is recorded here and in the "
            "DESIGN_WARNING at the end of this file."
            % ", ".join("%s[%d:0]" % (d["name"], d["msb"]) for d in resid),
            "  --  ", "  --  ")
        L.append("  --")

    L.append("  --  DEVIATIONS FROM IEEE 1149.1 A TESTER MUST KNOW")
    L.append("  --")
    L += wrap_comment(
        "THIS DEVICE IS NOT 1149.1-COMPLIANT WITH %s = 0. There is no TAP at all until "
        "%s is driven high. COMPLIANCE_PATTERNS below is the standard mechanism for "
        "saying so, and it is the only reason this description may claim conformance "
        "at all." % (en_p["port"], en_p["port"]), "  --   a) ", "  --      ")
    L += wrap_comment(
        "THE TAP PINS CARRY BOUNDARY CELLS. All four muxed pads still have their cells "
        "in the chain below (the length stays %d). 1149.1 does not permit that for a "
        "dedicated TAP pin, and a BSDL rule checker will say so -- but the cells ARE in "
        "the silicon, and a description that hid them would be the worse lie. While "
        "%s = 1 the pad ring overrides those pads: %s is forced to the TAP's TDO, and "
        "%s / %s are forced input-only, so EXTEST CANNOT independently drive any of the "
        "four. Treat their nets as untestable from this die."
        % (n, en_p["port"], portref(tdo_p), portref(tms_p), portref(tdi_p)),
        "  --   b) ", "  --      ")

    # 1149.1 wants TCK/TMS/TDI on inputs and TDO on an output. These pads are
    # functional I/O, so some of them are declared inout -- derive WHICH rather
    # than asserting a die-specific list in prose.
    dirs = {d["name"]: d["dir"] for d in decls}
    offdir = [(portref(q), dirs[portref(q)])
              for q, want in ((tck_p, "in"), (tms_p, "in"), (tdi_p, "in"), (tdo_p, "out"))
              if dirs[portref(q)] != want]
    if offdir:
        L += wrap_comment(
            "%s ARE DECLARED %s. 1149.1 expects dedicated, unidirectional TAP pins; "
            "these are bidirectional functional pads. Declaring them `in`/`out` here "
            "would contradict the output3 cells they carry in the boundary register "
            "below." % (", ".join(nm for nm, _ in offdir),
                        ", ".join(sorted({d for _, d in offdir}))),
            "  --   c) ", "  --      ")

    # A compliance-enable pin is not a system pin, so BSDL expects it to carry no
    # boundary cell. Ours does, because SE is a real bonded pad in the ring and the
    # register was built over every pad uniformly. Derive whether that is the case
    # rather than asserting it -- on a die whose enable pin is not a scanned pad,
    # this deviation simply does not exist and should not be printed.
    en_cells = [c["bsdl_num"] for c in cells if c["pad"]["inst"] == TAP_EN_PAD]
    if en_cells:
        L += wrap_comment(
            "THE COMPLIANCE-ENABLE PIN CARRIES A BOUNDARY CELL. %s is named by "
            "COMPLIANCE_PATTERNS and is also cell %s of the boundary register below. "
            "BSDL treats a compliance-enable pin as a non-system pin and expects it to "
            "have no cell, so a rule checker will flag this. It is reported, not "
            "hidden: the cell is in the silicon. Observing %s is in fact useful -- it "
            "lets a tester confirm the pin it is holding high is the pin the die sees "
            "-- but %s must be held at its compliance value throughout, so the cell "
            "must never be used to drive it."
            % (en_p["port"], ", ".join(str(x) for x in en_cells),
               en_p["port"], en_p["port"]),
            "  --   d) ", "  --      ")

    L += [
        "  attribute TAP_SCAN_IN    of %-12s : signal is true;" % portref(tdi_p),
        "  attribute TAP_SCAN_OUT   of %-12s : signal is true;" % portref(tdo_p),
        "  attribute TAP_SCAN_MODE  of %-12s : signal is true;" % portref(tms_p),
        "  --  TCK frequency is NOT yet characterised; %.1f MHz below is a placeholder."
        % (TCK_MAX_HZ / 1.0e6),
        "  attribute TAP_SCAN_CLOCK of %-12s : signal is (%.1fe6, BOTH);"
        % (portref(tck_p), TCK_MAX_HZ / 1.0e6),
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
        "  --",
    ]
    for note in idcode_notes():
        L += wrap_comment(note, "  --  ", "  --  ")
    L += [
        "  attribute IDCODE_REGISTER of %s : entity is" % ENTITY,
        "    %-22s -- version 0x%X" % ("\"%s\" &" % ver, (IDCODE_VALUE >> 28) & 0xF),
        "    %-22s -- part number 0x%04X" % ("\"%s\" &" % part, (IDCODE_VALUE >> 12) & 0xFFFF),
        "    %-22s -- manufacturer 0x%03X %s"
        % ("\"%s\" &" % manuf, (IDCODE_VALUE >> 1) & 0x7FF,
           "(JEP106 bank %d code 0x%02X)" % (JEDEC_ALLOC["bank"], JEDEC_ALLOC["code"])
           if JEDEC_ALLOC else "(UNALLOCATED PLACEHOLDER -- see above)"),
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

    # ---- design warning ---------------------------------------------------
    # THE LAST FIELD IN THE FILE AND THE ONLY ONE A HUMAN IS SHOWN. Comments above
    # are for whoever opens the file; DESIGN_WARNING survives parsing and test tools
    # put it in front of the operator, so every way this description can hurt a
    # bring-up engineer is repeated here in the shortest words that will carry it.
    # BSDL puts design_warning last, immediately before `end`.
    warn = [
        "NOT A COMPLIANT 1149.1 DEVICE UNLESS %s = 1. There are no dedicated TAP "
        "pads on this die: the TAP is muxed onto functional pads and does not "
        "exist while %s = 0 (see COMPLIANCE_PATTERNS)." % (en_p["port"], en_p["port"]),
    ]
    if split:
        warn.append(
            "%s are declared here as scalar ports but are bits %s of the chip's %s "
            "port -- a VHDL attribute cannot name a bus element, so the TAP pins are "
            "split out. PIN_MAP binds them to the same physical pins either way, and "
            "the remaining bits are NOT renumbered."
            % (" and ".join(sorted(portref(q) for q in split)),
               " and ".join(str(q["idx"]) for q in sorted(split, key=lambda q: q["idx"])),
               ", ".join(sorted({q["port"] for q in split}))))
    warn.append(
        "The four TAP pins (%s) still carry boundary-scan cells, and while %s = 1 "
        "the pad ring overrides those pads. EXTEST cannot independently drive them; "
        "treat their nets as untestable from this die."
        % (", ".join(portref(q) for q in (tck_p, tms_p, tdi_p, tdo_p)), en_p["port"]))
    if [c for c in cells if c["pad"]["inst"] == TAP_EN_PAD]:
        warn.append(
            "%s is the compliance-enable pin AND has a boundary-scan cell, which BSDL "
            "does not expect. Hold %s at its compliance value throughout; never drive "
            "that cell." % (en_p["port"], en_p["port"]))
    warn.append(
        "HIGHZ IS NOT IMPLEMENTED. %d output pads have no output-enable cell and no "
        "instruction can tri-state them." % n_out)
    if JEDEC_ALLOC is None:
        warn.append(
            "IDCODE DOES NOT IDENTIFY A MANUFACTURER. SoC Labs holds no JEDEC JEP106 "
            "allocation, so the manufacturer field is set to 0x%03X -- a code JEP106 "
            "can never issue -- and the part number field is 0x%04X. Your tools will "
            "report the manufacturer as invalid or unknown; that is correct and "
            "intended, not a fault. Do not identify this device by its IDCODE."
            % ((IDCODE_VALUE >> 1) & 0x7FF, (IDCODE_VALUE >> 12) & 0xFFFF))
    else:
        warn.append(
            "IDCODE manufacturer field 0x%03X is JEP106 bank %d code 0x%02X."
            % ((IDCODE_VALUE >> 1) & 0x7FF, JEDEC_ALLOC["bank"], JEDEC_ALLOC["code"]))
    warn.append(
        "PIN NUMBERS ARE PLACEHOLDERS (TBD_*) and no power, ground or analog pins "
        "are declared. This file is not yet fit for production board test.")

    L.append("  attribute DESIGN_WARNING of %s : entity is" % ENTITY)
    L += bsdl_text(" ".join(warn), indent=4)
    L.append("")
    L.append("end %s;" % ENTITY)
    L.append("")
    return "\n".join(L)


# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------
def generate(table_path):
    """Build the register from a pad table; return (pads, cells, rtl, bsdl)."""
    table = json.loads(pathlib.Path(table_path).read_text())
    pads, cells = build_cells(table)
    sha = sha256_of(table_path)
    return pads, cells, render_rtl(table, pads, cells, sha), render_bsdl(table, pads, cells, sha)


def diff(path, want, label):
    """Print a unified diff of `path` against `want`; return 1 if they differ."""
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
    """Generate, or with --check verify, the wrapper RTL and BSDL."""
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
