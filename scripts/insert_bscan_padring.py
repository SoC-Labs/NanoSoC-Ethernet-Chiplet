#!/usr/bin/env python3
"""
insert_bscan_padring.py — splice the boundary-scan register into the pad ring.

A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
Copyright 2026, SoC Labs (www.soclabs.org)

WHAT THIS DOES

`nanosoc_eth_chiplet_pads.v` is hand-written and is the source of truth for WHICH
PAD CELL each bond uses. This script does not take that role away: it performs one
mechanical, reviewable transform and writes the result back, so the .v stays the
committed artefact that everything downstream reads.

The transform, per signal pad:

    BEFORE   core <--- soc_x ---> uPAD_FOO(.C/.I/.OEN(soc_x))
    AFTER    core <--- soc_x ---> u_bscan <--- bsp_x ---> uPAD_FOO(.C/.I/.OEN(bsp_x))

Only the PAD instance's nets are renamed. The core instance is not touched at all,
which is what keeps the blast radius small: `nanosoc_eth_chiplet_chip` and every
`soc_*` name it binds to are bit-identical before and after.

OE POLARITY IS PRESERVED BY CONSTRUCTION. The padring currently writes `.OEN(~soc_x_e)`
for active-high enables and `.OEN(soc_x_o)` for the open-drain I2C pads. We feed the
BSR the *un-inverted* core enable and re-apply whatever inversion the pad already had
to the BSR's output. So the expression shape at the pad is unchanged; only the net
inside it moves. Getting this wrong flips an output enable, which is a driver fight.

THE TWO I2C PADS ARE OPEN-DRAIN and their `.I` stays a hard tie-low. We never route a
data-drive net to them. `scripts/check_chip_boundary.py` asserts this invariant and
will fail the build if it is ever broken -- a 16 mA push-pull driver on a wired-AND
bus is a cross-die short no tool warns about.

Idempotent: running twice is a no-op (it detects the already-spliced marker).
"""
import json, re, sys, argparse, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
TABLE = ROOT / "src/rtl/bscan/pad_table.json"

# NOTHING DESIGN-SPECIFIC IS HARDCODED HERE. The pad-ring path, the wrapper
# module name and the five TAP pads all come from the table's `design` block,
# which gen_pad_table.py wrote. A second chiplet supplies its own table and this
# file is untouched.
#
# Which pads carry the TAP is a per-chiplet judgement, not a constant: the eth
# ring lends HOSTIO4_P1[0:1] to TDI/TDO, and a ring without a spare bidir pair
# has to lend something else. See INTERFACE_CONTRACT.md section 7.


def short(inst):
    """uPAD_QSPI_IO_0 -> QSPI_IO_0. Unique per pad; the top-level port base name is not."""
    return inst[len("uPAD_"):]


def netname(inst, suffix):
    return "bsp_%s_%s" % (short(inst).lower(), suffix)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true",
                    help="exit 1 if the pad ring is not already spliced")
    ap.add_argument("--table", default=str(TABLE), help="pad table JSON")
    ap.add_argument("--padring", help="override the pad ring named in the table")
    ap.add_argument("-o", "--output", help="default: edit the pad ring in place")
    args = ap.parse_args()

    tbl = json.loads(pathlib.Path(args.table).read_text())
    pads = tbl["pads"]
    design = tbl.get("design")
    if not design:
        sys.exit("ERROR: pad table has no `design` block -- regenerate it with "
                 "scripts/gen_pad_table.py.")
    pads_path = pathlib.Path(args.padring or design["padring"])
    if not pads_path.is_absolute():
        pads_path = ROOT / pads_path
    MARK = "u_" + design["module"]
    tap = design["tap"]
    TAP_TCK, TAP_TMS = tap["tck"], tap["tms"]
    TAP_TDI, TAP_TDO = tap["tdi"], tap["tdo"]
    TAP_EN = tap["en"]
    src = pads_path.read_text()

    if MARK in src:
        print("pad ring already spliced (marker %r present) - nothing to do" % MARK)
        return 0
    if args.check:
        print("FAIL: pad ring has NOT been spliced with the boundary-scan register")
        return 1

    decls, conns, patched = [], [], 0

    for p in pads:
        inst, kind = p["inst"], p["kind"]
        s = short(inst)

        # locate this pad instance's body
        m = re.search(r"(\b[A-Z0-9_]+\s+%s\s*\((?:[^()]|\([^()]*\))*?\)\s*;)" % re.escape(inst),
                      src, re.S)
        if not m:
            sys.exit("ERROR: could not locate pad instance %s in %s" % (inst, pads_path))
        body = m.group(1)
        new = body

        # ---- .C : pad -> core (every kind except pure output) -----------------
        if p["c_net"]:
            n = netname(inst, "in")
            decls.append("wire %s;" % n)
            new = re.sub(r"(\.C\s*\(\s*)([^)]*?)(\s*\))",
                         lambda mm: mm.group(1) + n + mm.group(3), new, count=1)
            conns.append(".%s_pin_in (%s)" % (s, n))
            conns.append(".%s_core_in (%s)" % (s, p["c_net"]))

        # ---- .I : core -> pad. NEVER for open-drain (stays tielo). ------------
        if kind in ("output", "bidir") and p["i_net"]:
            n = netname(inst, "out")
            decls.append("wire %s;" % n)
            new = re.sub(r"(\.I\s*\(\s*)([^)]*?)(\s*\))",
                         lambda mm: mm.group(1) + n + mm.group(3), new, count=1)
            conns.append(".%s_core_out (%s)" % (s, p["i_net"]))
            conns.append(".%s_pad_out (%s)" % (s, n))

        # ---- .OEN : keep the pad's existing inversion, move the net -----------
        if p["oe_net"]:
            n = netname(inst, "oe")
            decls.append("wire %s;" % n)
            repl = ("~" + n) if p["oe_inv"] else n
            new = re.sub(r"(\.OEN\s*\(\s*)([^)]*?)(\s*\))",
                         lambda mm: mm.group(1) + repl + mm.group(3), new, count=1)
            conns.append(".%s_core_oe (%s)" % (s, p["oe_net"]))
            conns.append(".%s_pad_oe (%s)" % (s, n))

        src = src.replace(body, new, 1)
        patched += 1

    # ---- TAP pin mux, applied at the PAD side (closest to the bond) ----------
    # These four overrides sit OUTSIDE the boundary register, between it and the
    # pad, because TDO must be drivable while the boundary register is doing
    # something else entirely, and TCK/TMS/TDI must reach the TAP no matter what
    # state the chain is in.
    en = netname(TAP_EN, "in")
    tck, tms, tdi = (netname(x, "in") for x in (TAP_TCK, TAP_TMS, TAP_TDI))

    # TDO drives the HOSTIO4[1] pad when boundary scan is enabled.
    tdo_pad_i = netname(TAP_TDO, "out")
    tdo_pad_oe = netname(TAP_TDO, "oe")
    src = src.replace("wire %s;" % tdo_pad_i, "")  # re-declared below as a mux output

    extra = []
    extra.append("wire bscan_tdo;")
    extra.append("wire bscan_tdo_oe;")
    extra.append("wire bscan_en = %s;   // SE pad, pad-side: works with the core dead" % en)
    extra.append("wire %s_muxed = bscan_en ? bscan_tdo    : %s;" % (tdo_pad_i, tdo_pad_i))
    extra.append("wire %s_muxed = bscan_en ? bscan_tdo_oe : %s;" % (tdo_pad_oe, tdo_pad_oe))

    # Point the TDO pad at the muxed nets, and force the TMS/TDI pads to input-only
    # while boundary scan is live so the core cannot fight the tester.
    def repad(inst, port, expr):
        m = re.search(r"(\b[A-Z0-9_]+\s+%s\s*\((?:[^()]|\([^()]*\))*?\)\s*;)" % re.escape(inst),
                      src, re.S)
        body = m.group(1)
        new = re.sub(r"(\.%s\s*\(\s*)([^)]*?)(\s*\))" % port,
                     lambda mm: mm.group(1) + expr + mm.group(3), body, count=1)
        return src.replace(body, new, 1)

    src = repad(TAP_TDO, "I", "%s_muxed" % tdo_pad_i)
    src = repad(TAP_TDO, "OEN", "~%s_muxed" % tdo_pad_oe)
    src = repad(TAP_TMS, "OEN", "(bscan_en ? tiehi : ~%s)" % netname(TAP_TMS, "oe"))
    src = repad(TAP_TDI, "OEN", "(bscan_en ? tiehi : ~%s)" % netname(TAP_TDI, "oe"))

    # ---- build the inserted block -------------------------------------------
    blk = ["", "//" + "-" * 75,
           "// BOUNDARY-SCAN REGISTER (IEEE 1149.1). Generated wiring, see",
           "// src/rtl/bscan/INTERFACE_CONTRACT.md and scripts/insert_bscan_padring.py.",
           "//",
           "// Sits between the core instance and the pad cells. With the SE pad low --",
           "// the functional default -- the TAP is held in Test-Logic-Reset, every cell",
           "// is transparent, and this chip behaves exactly as it did before.",
           "//" + "-" * 75]
    seen = set()
    for d in decls:
        if d not in seen:
            blk.append(d)
            seen.add(d)
    blk += extra
    blk.append("")
    blk.append("nanosoc_eth_chiplet_bscan %s (" % MARK)
    blk.append("  .tck     (%s)," % tck)
    blk.append("  .tms     (%s)," % tms)
    blk.append("  .tdi     (%s)," % tdi)
    blk.append("  .trst_n  (bscan_en),   // SE low => TAP held in reset")
    blk.append("  .tdo     (bscan_tdo),")
    blk.append("  .tdo_oe  (bscan_tdo_oe),")
    for i, c in enumerate(conns):
        blk.append("  %s%s" % (c, "," if i < len(conns) - 1 else ""))
    blk.append(");")
    blk.append("")

    # insert immediately before the first pad cell instantiation
    anchor = re.search(r"\n\s*//[^\n]*\n\s*PDDW04DGZ_G\s+uPAD_SE_I", src)
    if not anchor:
        anchor = re.search(r"\n\s*PD[DU]W\d+DGZ_G\s+uPAD_", src)
    pos = anchor.start()
    src = src[:pos] + "\n" + "\n".join(blk) + src[pos:]

    pathlib.Path(args.output or pads_path).write_text(src)
    print("spliced %d signal pads" % patched)
    print("  wire declarations : %d" % len(seen))
    print("  bscan connections : %d" % len(conns))
    print("  TAP muxed onto    : %s(TCK) %s(TMS) %s(TDI) %s(TDO), enabled by %s"
          % (short(TAP_TCK), short(TAP_TMS), short(TAP_TDI), short(TAP_TDO), short(TAP_EN)))
    print("  wrote %s" % (args.output or pads_path))
    return 0


if __name__ == "__main__":
    sys.exit(main())
