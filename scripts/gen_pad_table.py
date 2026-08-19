#!/usr/bin/env python3
"""
gen_pad_table.py — parse a pad ring into the machine-readable table everything
else in the boundary-scan flow derives from.

A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.

Contributors

David Mapstone (d.a.mapstone@soton.ac.uk)

Copyright 2026, SoC Labs (www.soclabs.org)

WHAT THIS IS

The one place a pad ring is READ. Every other tool in the boundary-scan flow --
the wrapper generator, the BSDL writer, the pad-ring splicer, the testbench
generator -- consumes this table and never re-parses Verilog. That is deliberate:
four parsers of the same file drift, and the drift surfaces as a chain that
shifts the wrong number of bits on bonded silicon.

DESIGN-AGNOSTIC BY CONSTRUCTION

Nothing about a particular chiplet is baked in. Paths, block name and the TAP pin
choice all arrive as arguments, and the pad CELL TYPES are discovered from the
ring itself rather than hardcoded -- the eth chiplet uses four driver cell types
and the compute chiplet uses five (it has PDUW04DGZ_G, which eth does not). A
hardcoded tuple silently drops a pad; a pattern does not.

The emitted table carries a `design` block naming the block, the module to
generate, the TAP pads and the IDCODE. Downstream tools read their identity from
there rather than being told twice, so there is exactly one place to change when
a second chiplet adopts the flow.

TWO .io DIALECTS, BOTH REAL

Innovus `write_io_file` output is not spelled consistently across this lab:

    eth      (top            ...  offset=150      space=55
    compute  ( top           ...  offset = 137    space = 60

Both are accepted. This is a parser that has to read what the tools actually
wrote, not what a style guide says they should have.

Usage
-----
    gen_pad_table.py --padring <pads.v> --io <ring.io> --block <name> \
                     --tap-en/-tck/-tms/-tdi/-tdo <uPAD_...> [--idcode 0x...] \
                     [--module <name>] [-o pad_table.json]

Reads the pad-ring Verilog and the Innovus .io; writes ONE JSON table.
Exit: 0 table written; non-zero (via sys.exit with a message) if the ring has
no signal pads, the .io lacks a side block, a named TAP pad is not a signal pad
in this ring, or the ring has already been spliced by insert_bscan_padring.py.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter

# Driver-cell name prefixes. TSMC 65 IO libraries spell a signal pad
# PD{D,U}W<drive>DGZ_G; PDIDGZ / PDO* appear in other members of the family.
# Supply (PVDD*/PVSS*), corner (PCORNER*) and bond (PAD70*) cells are NOT
# signal pads and must never enter the chain.
SIGNAL_CELL_PREFIXES = ("PDDW", "PDUW", "PDIDGZ", "PDO")

# Sides in the order a clockwise chain visits them, and whether the .io lists
# that side in the opposite order to the chain direction.
SIDES = (("top", False), ("right", True), ("bottom", True), ("left", False))


def strip_comments(s: str) -> str:
    """Remove /* */ and // comments so the regex parsers never match commented RTL."""
    s = re.sub(r"/\*.*?\*/", "", s, flags=re.S)
    return re.sub(r"//[^\n]*", "", s)


def discover_signal_cells(src: str) -> tuple[str, ...]:
    """Find the driver cell types this ring actually instantiates."""
    found = {c for c, _ in re.findall(r"\b(P[A-Z0-9_]+)\s+(u\w+)\s*\(", src)
             if c.startswith(SIGNAL_CELL_PREFIXES)}
    if not found:
        sys.exit("ERROR: no signal pad cells found — is --padring pointing at a pad ring?")
    return tuple(sorted(found))


def parse_ports(src: str, block: str) -> dict:
    """Port name -> direction for the pad-ring module `block`."""
    hm = re.search(r"module\s+%s\s*\((.*?)\n\s*\)\s*;" % re.escape(block), src, re.S)
    if not hm:
        sys.exit("ERROR: no module %s in the pad ring" % block)
    ports = {}
    for d, rng, nm in re.findall(
            r"\b(input|output|inout)\b\s+(?:wire|reg|logic)?\s*(\[[^\]]*\])?\s*(\w+)", hm.group(1)):
        w = 1
        if rng:
            a, b = re.findall(r"(\d+)", rng)[:2]
            w = abs(int(a) - int(b)) + 1
        ports[nm] = {"dir": d, "width": w}
    return ports


def parse_pads(src: str, signal_cells: tuple[str, ...]) -> list[dict]:
    """One record per signal pad: instance, cell, the C/I/OEN/REN nets and the PAD port."""
    pads = []
    for cell, inst, body in re.findall(r"\b(P[A-Z0-9_]+)\s+(u\w+)\s*\((.*?)\)\s*;", src, re.S):
        if cell not in signal_cells:
            continue

        def get(p):
            """Net bound to port `p` of this pad instance, or "" if unbound."""
            m = re.search(r"\.%s\s*\(\s*(.*?)\s*\)" % p, body, re.S)
            return (m.group(1).strip() if m else "")

        C, I, OEN, REN, PAD = (get(x) for x in ("C", "I", "OEN", "REN", "PAD"))
        base = re.sub(r"\[.*", "", PAD)
        im = re.search(r"\[(\d+)\]", PAD)

        oe_net, oe_inv = None, False
        if OEN not in ("tielo", "tiehi", ""):
            oe_inv = OEN.startswith("~")
            oe_net = OEN.lstrip("~").strip()

        # An open-drain pad folds its DATA onto OEN and hard-ties .I low, because
        # it sits on a wired-AND bus. It must never be given a data-drive cell:
        # a push-pull driver there is a cross-die short no tool warns about.
        if I == "tielo" and oe_net and C:
            kind = "opendrain"
        elif oe_net:
            kind = "bidir"
        elif OEN == "tiehi":
            kind = "input"
        elif OEN == "tielo":
            kind = "output"
        else:
            kind = "UNKNOWN"

        pads.append(dict(inst=inst, cell=cell, kind=kind, pad=PAD, port=base,
                         idx=int(im.group(1)) if im else None,
                         c_net=C or None,
                         i_net=(I if I not in ("tielo", "tiehi") else None),
                         oe_net=oe_net, oe_inv=oe_inv, ren=REN,
                         i_tied=(I if I in ("tielo", "tiehi") else None)))
    return pads


def parse_ring_order(io_path: str) -> list[tuple[str, str]]:
    """Return [(side, inst)] in clockwise order: top L->R, right T->B, bottom R->L, left B->T."""
    iof = open(io_path).read()
    ring = []
    for side, reverse in SIDES:
        # `(top` and `( top ` are both in the wild -- see the module docstring.
        m = re.search(r"\(\s*%s\b[^\n]*\n(.*?)\n\s*\)" % side, iof, re.S)
        if not m:
            sys.exit("ERROR: no '%s' side block in %s" % (side, io_path))
        names = re.findall(r'inst\s+name="([^"]+)"', m.group(1))
        ring += [(side, n) for n in (reversed(names) if reverse else names)]
    return ring


def main() -> int:
    """Parse the ring, order it by the .io, and write the pad table."""
    ap = argparse.ArgumentParser()
    ap.add_argument("--padring", required=True,
                    help="the PRISTINE pad-ring Verilog to parse (pre-splice)")
    ap.add_argument("--record-padring",
                    help="path to RECORD in the table as the ring to splice. Defaults to "
                         "--padring. These differ whenever the table is regenerated from a "
                         "pristine copy recovered out of git: you parse the temporary file "
                         "but must record the repo path, or a fresh clone gets a table "
                         "pointing at somebody's /tmp.")
    ap.add_argument("--io", required=True, help="the Innovus .io giving physical ring order")
    ap.add_argument("--block", required=True, help="pad-ring module name, e.g. foo_chiplet_pads")
    ap.add_argument("--module", help="wrapper module to generate (default: <block minus _pads>_bscan)")
    ap.add_argument("--tap-en", required=True, help="pad instance enabling boundary scan, e.g. uPAD_SE_I")
    ap.add_argument("--tap-tck", required=True, help="pad instance carrying TCK")
    ap.add_argument("--tap-tms", required=True, help="pad instance carrying TMS")
    ap.add_argument("--tap-tdi", required=True, help="pad instance carrying TDI")
    ap.add_argument("--tap-tdo", required=True, help="pad instance carrying TDO")
    ap.add_argument("--idcode", default="0x100005A1",
                    help="32-bit JTAG IDCODE. PLACEHOLDER until a JEDEC ID is assigned.")
    ap.add_argument("-o", "--out", default="pad_table.json",
                    help="where to write the pad table (default: pad_table.json)")
    args = ap.parse_args()

    src = strip_comments(open(args.padring).read())

    # REFUSE TO PARSE AN ALREADY-SPLICED RING.
    #
    # After insert_bscan_padring.py runs, the pad cells no longer touch the core
    # nets -- they touch the register's pad-side nets. Re-parsing then yields a
    # table whose c_net/i_net/oe_net are `bsp_*` instead of `soc_*`, and the next
    # generator run would build a wrapper wired to itself. Everything downstream
    # would still elaborate, still lint, still pass the cell count, and be wrong.
    #
    # The table is derived ONCE from the pristine ring and committed. If it needs
    # regenerating, recover the unspliced ring first (git show / git checkout).
    if re.search(r"\b\w*_bscan\s+\w+\s*\(", src):
        sys.exit(
            "ERROR: %s already has a boundary-scan register spliced into it.\n"
            "       The pad table must be derived from the PRISTINE pad ring --\n"
            "       parsing a spliced ring captures the register's own nets and\n"
            "       silently produces a wrapper wired to itself.\n"
            "       Recover the original first, e.g.\n"
            "         git show <commit-before-splice>:%s > /tmp/pristine_pads.v\n"
            "       and pass that as --padring." % (args.padring, args.padring))

    signal_cells = discover_signal_cells(src)
    ports = parse_ports(src, args.block)
    pads = parse_pads(src, signal_cells)

    ring = parse_ring_order(args.io)
    order = {n: i for i, (_, n) in enumerate(ring)}
    side_of = {n: s for s, n in ring}
    for p in pads:
        p["ring_index"] = order.get(p["inst"], 10_000)
        p["side"] = side_of.get(p["inst"], "?")
    pads.sort(key=lambda p: p["ring_index"])

    tap = {k: getattr(args, "tap_" + k) for k in ("en", "tck", "tms", "tdi", "tdo")}
    known = {p["inst"] for p in pads}
    for role, inst in tap.items():
        if inst not in known:
            sys.exit("ERROR: --tap-%s '%s' is not a signal pad in this ring" % (role, inst))

    module = args.module or (re.sub(r"_pads$", "", args.block) + "_bscan")

    # Cell budget, DERIVED. Never a literal: eth is 76 and compute is 80, and a
    # hardcoded expectation is how a silently-dropped pad passes review.
    k = Counter(p["kind"] for p in pads)
    cells = k["input"] + k["output"] + 3 * k["bidir"] + 2 * k["opendrain"]

    out = {
        "design": {
            "block": args.block,
            "module": module,
            "padring": args.record_padring or args.padring,
            "io_file": args.io,
            "tap": tap,
            "idcode": args.idcode,
            "boundary_length": cells,
            "signal_cells": list(signal_cells),
        },
        "ports": ports,
        "pads": pads,
    }
    json.dump(out, open(args.out, "w"), indent=1)

    print("pad ring   : %s" % args.block)
    print("signal pads: %d   %s" % (len(pads), dict(k)))
    print("cell types : %s" % ", ".join(signal_cells))
    print("by side    : %s" % dict(Counter(p["side"] for p in pads)))
    unplaced = [p["inst"] for p in pads if p["ring_index"] == 10_000]
    unknown = [p["inst"] for p in pads if p["kind"] == "UNKNOWN"]
    print("unplaced   : %s" % (unplaced or "none"))
    print("unknown    : %s" % (unknown or "none"))
    print("BSR cells  : %d  (in + out + bidir*3 + opendrain*2)" % cells)
    print("wrote %s" % args.out)
    if unplaced or unknown:
        print("REFUSING: every pad must be placed and classified", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
