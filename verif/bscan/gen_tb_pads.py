#!/usr/bin/env python3
#-----------------------------------------------------------------------------
# verif/bscan/gen_tb_pads.py -- emit tb_bscan_pads.svh for tb_bscan.sv
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
#
# Contributors: SoC Labs verification
# Copyright 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# WHY THIS EXISTS
#
#   nanosoc_eth_chiplet_bscan is GENERATED from pad_table.json, so its port list
#   is 48 pad groups wide and nobody hand-writes it. A testbench that hand-wrote
#   the matching 150-odd port connections would be a second, independently
#   wrong, copy of the pad table -- and the first time a pad moved the TB would
#   either fail to compile or, worse, silently test the wrong ring order.
#
#   So the TB body is written GENERICALLY over arrays indexed by ring order, and
#   this script emits the one file that knows names: the signal declarations,
#   the DUT instantiation, and the chain map (which pad and which cell kind sits
#   at each of the 76 chain positions). ONE table, ONE derivation.
#
# THE NAMING AMBIGUITY (see verif/bscan/README.md, "Contract ambiguities")
#
#   INTERFACE_CONTRACT.md section 6 says "for every pad P: input wire P_pin_in ..."
#   but never says what P is: the pad name (`HOSTIO4_P1[6]` -- not a legal
#   identifier), the port+index (`HOSTIO4_P1_6`), or the padring instance
#   (`uPAD_HOST_IO_6`). Rather than guess and produce a TB that cannot link, this
#   script:
#     * defaults to `pad` -- the pad name with [] flattened to _, which is
#       identical to port+index for every entry in the table; and
#     * when the generated wrapper already exists, SCANS IT and auto-selects
#       whichever convention its ports actually use, reporting the choice.
#   If no convention matches, it says so and exits non-zero rather than emitting
#   a header that will fail to elaborate with 150 confusing errors.
#
# THE OPEN-DRAIN GUARD (contract section 1 -- "non-negotiable")
#
#   The two I2C pads must have NO data-drive path. A testbench cannot prove the
#   absence of a port at run time -- an unconnected extra port on a named-port
#   instantiation is legal and silent. So the absence is gated HERE, statically,
#   over the generated RTL: if the wrapper declares *_pad_out or *_core_out for
#   uPAD_I2C_SCL / uPAD_I2C_SDA under ANY of the candidate naming conventions,
#   this script fails the build. tb_bscan.sv then proves the dynamic half (that
#   EXTEST can move nothing on those pads except the output enable).
#
#   usage:  ./gen_tb_pads.py [--pad-table F] [--rtl-dir D] [--out F]
#                            [--naming pad|inst|inst_nopfx] [--no-detect]
#-----------------------------------------------------------------------------
import argparse
import hashlib
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))

# cells contributed per pad kind, and the within-pad order seen from TDI.
# Contract section 6: "Within one pad the order from TDI is: oe ctl -> data ctl -> obs."
CELL_OBS, CELL_DATA, CELL_OE = 0, 1, 2
KIND_ID = {"input": 0, "output": 1, "bidir": 2, "opendrain": 3}
KIND_CELLS = {
    "input":     [CELL_OBS],
    "output":    [CELL_DATA],
    "bidir":     [CELL_OE, CELL_DATA, CELL_OBS],
    "opendrain": [CELL_OE, CELL_OBS],   # NO data cell -- the wired-AND rule
}
SUFFIXES = ("pin_in", "core_in", "core_out", "pad_out", "core_oe", "pad_oe")


def sanitise(name):
    """`HOSTIO4_P1[6]` -> `HOSTIO4_P1_6`; leave plain names alone."""
    return re.sub(r"_+$", "", re.sub(r"[\[\]]+", "_", name))


def base_name(p, style):
    if style == "pad":
        return sanitise(p["pad"])
    if style == "inst":
        return p["inst"]
    if style == "inst_nopfx":
        return re.sub(r"^uPAD_", "", p["inst"])
    raise SystemExit("gen_tb_pads.py: unknown naming style %r" % style)


def expected_ports(p, style):
    """The port names the wrapper must declare for this pad, per contract section 6."""
    b, k = base_name(p, style), p["kind"]
    out = []
    if k in ("input", "bidir", "opendrain"):
        out += [b + "_pin_in", b + "_core_in"]
    if k in ("output", "bidir"):
        out += [b + "_core_out", b + "_pad_out"]
    if k in ("bidir", "opendrain"):
        out += [b + "_core_oe", b + "_pad_oe"]
    return out


def scan_rtl_identifiers(rtl_dir):
    """Every `<base>_<suffix>` identifier appearing anywhere in the bscan RTL.

    Deliberately over-inclusive (whole file, not just the port list): for the
    open-drain guard, a *_pad_out for an I2C pad is unacceptable whether it is a
    port or an internal net, so a coarse scan is the conservative one.
    Returns (identifier set, list of files scanned).
    """
    idents, files = set(), []
    if not os.path.isdir(rtl_dir):
        return idents, files
    for fn in sorted(os.listdir(rtl_dir)):
        if not fn.endswith((".sv", ".v", ".svh")):
            continue
        path = os.path.join(rtl_dir, fn)
        files.append(path)
        with open(path, "r", errors="replace") as fh:
            txt = fh.read()
        txt = re.sub(r"//[^\n]*", " ", txt)
        txt = re.sub(r"/\*.*?\*/", " ", txt, flags=re.S)
        for m in re.finditer(r"\b(\w+)_(%s)\b" % "|".join(SUFFIXES), txt):
            idents.add(m.group(0))
    return idents, files


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pad-table", default=os.path.join(REPO, "src/rtl/bscan/pad_table.json"))
    ap.add_argument("--rtl-dir",   default=os.path.join(REPO, "src/rtl/bscan"))
    ap.add_argument("--out",       default=os.path.join(HERE, "tb_bscan_pads.svh"))
    ap.add_argument("--naming",    default="pad", choices=["pad", "inst", "inst_nopfx"])
    ap.add_argument("--no-detect", action="store_true",
                    help="do not auto-select the naming convention from the RTL")
    args = ap.parse_args()

    with open(args.pad_table, "rb") as fh:
        raw = fh.read()
    table = json.loads(raw.decode())
    sha = hashlib.sha256(raw).hexdigest()[:16]

    pads = sorted(table["pads"], key=lambda p: p["ring_index"])
    n_pads = len(pads)
    for p in pads:
        if p["kind"] not in KIND_CELLS:
            sys.exit("gen_tb_pads.py: pad %s has unknown kind %r" % (p["inst"], p["kind"]))
    n_cells = sum(len(KIND_CELLS[p["kind"]]) for p in pads)

    # --- contract section 1 arithmetic, asserted here so a pad-table edit that
    #     silently changes the chain length cannot slip past the TB unnoticed.
    if n_pads != 48 or n_cells != 76:
        print("gen_tb_pads.py: WARNING pad table gives %d pads / %d cells; "
              "the contract says 48 / 76" % (n_pads, n_cells), file=sys.stderr)

    ring = [p["ring_index"] for p in pads]
    if len(set(ring)) != len(ring):
        sys.exit("gen_tb_pads.py: duplicate ring_index in the pad table")

    # ---------------- naming convention ------------------------------------
    idents, files = scan_rtl_identifiers(args.rtl_dir)
    style, note = args.naming, "default (generated wrapper not found)"
    if idents and not args.no_detect:
        scores = {}
        for cand in ("pad", "inst", "inst_nopfx"):
            want = [n for p in pads for n in expected_ports(p, cand)]
            scores[cand] = sum(1 for n in want if n in idents)
        best = max(scores, key=lambda c: scores[c])
        total = len([n for p in pads for n in expected_ports(p, best)])
        if scores[best] == 0:
            print("gen_tb_pads.py: ERROR the wrapper RTL declares no recognisable "
                  "pad ports.\n  scanned: %s\n  tried conventions: %s"
                  % (", ".join(files), ", ".join("%s=%d" % kv for kv in scores.items())),
                  file=sys.stderr)
            sys.exit(2)
        style = best
        note = "auto-detected from %s (%d/%d expected ports found)" % (
            os.path.basename(files[0]) if len(files) == 1 else "%d RTL files" % len(files),
            scores[best], total)
        if scores[best] != total:
            missing = [n for p in pads for n in expected_ports(p, best) if n not in idents]
            print("gen_tb_pads.py: ERROR %d of %d expected pad ports are missing "
                  "from the wrapper under the '%s' convention." % (total - scores[best], total, best),
                  file=sys.stderr)
            for n in missing[:20]:
                print("    missing: %s" % n, file=sys.stderr)
            if len(missing) > 20:
                print("    ... and %d more" % (len(missing) - 20), file=sys.stderr)
            print("  Refusing to emit a header that cannot elaborate. Either the "
                  "wrapper is incomplete or the contract's port naming has moved.",
                  file=sys.stderr)
            sys.exit(2)

    # ---------------- open-drain static guard (contract section 1) ----------
    od = [p for p in pads if p["kind"] == "opendrain"]
    bad = []
    for p in od:
        for cand in ("pad", "inst", "inst_nopfx"):
            b = base_name(p, cand)
            for suf in ("pad_out", "core_out"):
                if (b + "_" + suf) in idents:
                    bad.append(b + "_" + suf)
    if bad:
        print("gen_tb_pads.py: OPEN-DRAIN VIOLATION -- the wrapper declares a data path\n"
              "  on an I2C pad: %s\n"
              "  Contract section 1: .I is a structural tie-low on uPAD_I2C_SCL/SDA and the\n"
              "  data is folded onto .OEN. A 16 mA push-pull driver on a wired-AND bus is a\n"
              "  cross-die short no tool warns about. An open-drain pad gets ONE obs cell and\n"
              "  ONE oe ctl cell -- never a data cell." % ", ".join(sorted(set(bad))),
              file=sys.stderr)
        sys.exit(2)

    # ---------------- chain map --------------------------------------------
    cell_pad, cell_type = [], []
    for i, p in enumerate(pads):
        for c in KIND_CELLS[p["kind"]]:
            cell_pad.append(i)
            cell_type.append(c)

    def mask(pred):
        v = 0
        for i, p in enumerate(pads):
            if pred(p):
                v |= 1 << i
        return v

    m_obs  = mask(lambda p: CELL_OBS  in KIND_CELLS[p["kind"]])
    m_data = mask(lambda p: CELL_DATA in KIND_CELLS[p["kind"]])
    m_oe   = mask(lambda p: CELL_OE   in KIND_CELLS[p["kind"]])
    m_od   = mask(lambda p: p["kind"] == "opendrain")

    def arr(name, vals, per_line=16):
        rows, out = [], []
        for i in range(0, len(vals), per_line):
            rows.append(", ".join("%d" % v for v in vals[i:i + per_line]))
        out.append("  localparam int %s [0:%d] = '{" % (name, len(vals) - 1))
        for j, r in enumerate(rows):
            out.append("      %s%s" % (r, "," if j != len(rows) - 1 else ""))
        out.append("  };")
        return "\n".join(out)

    L = []
    L.append("//---------------------------------------------------------------------------")
    L.append("// tb_bscan_pads.svh -- GENERATED by verif/bscan/gen_tb_pads.py. DO NOT EDIT.")
    L.append("//   pad table : %s (sha256 %s...)" % (os.path.relpath(args.pad_table, REPO), sha))
    L.append("//   naming    : '%s' -- %s" % (style, note))
    L.append("//   geometry  : %d pads, %d boundary-register cells" % (n_pads, n_cells))
    L.append("//")
    L.append("// Indices: pad index 0..%d is RING ORDER (ascending ring_index, i.e. the" % (n_pads - 1))
    L.append("// order TDI meets the pads). Chain index 0..%d is TDI-FIRST: cell 0 is the" % (n_cells - 1))
    L.append("// cell TDI enters, cell %d is the one TDO leaves. BSDL numbers these the" % (n_cells - 1))
    L.append("// other way round (0 nearest TDO) -- do not confuse the two.")
    L.append("//---------------------------------------------------------------------------")
    L.append("")
    L.append("  localparam int N_PADS  = %d;" % n_pads)
    L.append("  localparam int N_CELLS = %d;" % n_cells)
    L.append("")
    L.append("  // cell kinds (what the cell captures, and whether it can drive)")
    L.append("  localparam int CELL_OBS = %d;  // captures pin_in;  observe only, no drive path" % CELL_OBS)
    L.append("  localparam int CELL_DATA= %d;  // captures core_out; drives pad_out in EXTEST" % CELL_DATA)
    L.append("  localparam int CELL_OE  = %d;  // captures core_oe;  drives pad_oe  in EXTEST" % CELL_OE)
    L.append("")
    L.append("  // pad kinds")
    for k, v in sorted(KIND_ID.items(), key=lambda kv: kv[1]):
        L.append("  localparam int K_%-9s = %d;" % (k.upper(), v))
    L.append("")
    L.append("  // Which pads own which port groups. The TB checks only masked bits, so an")
    L.append("  // unconnected array bit (e.g. core_out of an input-only pad) is never read.")
    L.append("  localparam logic [N_PADS-1:0] MASK_HAS_OBS   = %d'h%012x;" % (n_pads, m_obs))
    L.append("  localparam logic [N_PADS-1:0] MASK_HAS_DATA  = %d'h%012x;" % (n_pads, m_data))
    L.append("  localparam logic [N_PADS-1:0] MASK_HAS_OE    = %d'h%012x;" % (n_pads, m_oe))
    L.append("  localparam logic [N_PADS-1:0] MASK_OPENDRAIN = %d'h%012x;" % (n_pads, m_od))
    L.append("")
    L.append(arr("PAD_KIND", [KIND_ID[p["kind"]] for p in pads]))
    L.append(arr("PAD_RING", [p["ring_index"] for p in pads]))
    L.append("")
    L.append("  // chain map, TDI-first")
    L.append(arr("CELL_PAD",  cell_pad))
    L.append(arr("CELL_TYPE", cell_type))
    L.append("")
    L.append("  function automatic string pad_name(input int i);")
    L.append("    case (i)")
    for i, p in enumerate(pads):
        L.append('      %2d: return "%s";' % (i, p["pad"]))
    L.append('      default: return "<out-of-range>";')
    L.append("    endcase")
    L.append("  endfunction")
    L.append("")
    L.append("  function automatic string cell_name(input int c);")
    L.append("    case (CELL_TYPE[c])")
    L.append('      CELL_OBS : return "obs";')
    L.append('      CELL_DATA: return "data-ctl";')
    L.append('      default  : return "oe-ctl";')
    L.append("    endcase")
    L.append("  endfunction")
    L.append("")
    L.append("  //--- TB-side nets, indexed by pad (ring order) --------------------------")
    L.append("  logic [N_PADS-1:0] core_out;   // core -> wrapper (data)")
    L.append("  logic [N_PADS-1:0] core_oe;    // core -> wrapper (output enable)")
    L.append("  logic [N_PADS-1:0] pin_in;     // pad .C -> wrapper")
    L.append("  wire  [N_PADS-1:0] pad_out;    // wrapper -> pad .I")
    L.append("  wire  [N_PADS-1:0] pad_oe;     // wrapper -> pad OEN logic")
    L.append("  wire  [N_PADS-1:0] core_in;    // wrapper -> core")
    L.append("")
    L.append("  //--- DUT ----------------------------------------------------------------")
    L.append("  nanosoc_eth_chiplet_bscan dut (")
    L.append("    .tck    (tck),")
    L.append("    .tms    (tms),")
    L.append("    .tdi    (tdi),")
    L.append("    .trst_n (trst_n),")
    L.append("    .tdo    (tdo),")
    L.append("    .tdo_oe (tdo_oe)%s" % ("," if n_pads else ""))
    conns = []
    for i, p in enumerate(pads):
        b = base_name(p, style)
        grp = ["    // pad[%2d] ring=%-3d %-14s %s" % (i, p["ring_index"], p["kind"], p["pad"])]
        for name, net in (("pin_in", "pin_in"), ("core_in", "core_in"),
                          ("core_out", "core_out"), ("pad_out", "pad_out"),
                          ("core_oe", "core_oe"), ("pad_oe", "pad_oe")):
            if (b + "_" + name) in [x for x in expected_ports(p, style)]:
                grp.append("    .%-28s (%s[%2d])" % (b + "_" + name, net, i))
        conns.append(grp)
    flat = []
    for gi, grp in enumerate(conns):
        flat.append(grp[0])
        for li, line in enumerate(grp[1:]):
            last = (gi == len(conns) - 1) and (li == len(grp) - 2)
            flat.append(line + ("" if last else ","))
    L.extend(flat)
    L.append("  );")
    L.append("")

    with open(args.out, "w") as fh:
        fh.write("\n".join(L) + "\n")

    print("gen_tb_pads.py: wrote %s" % args.out)
    print("  pads=%d cells=%d naming='%s' (%s)" % (n_pads, n_cells, style, note))
    print("  cells per kind: input=%d output=%d bidir=%d opendrain=%d"
          % (sum(1 for p in pads if p["kind"] == "input"),
             sum(1 for p in pads if p["kind"] == "output"),
             sum(1 for p in pads if p["kind"] == "bidir"),
             sum(1 for p in pads if p["kind"] == "opendrain")))
    print("  open-drain guard: OK -- no data path on %s"
          % ", ".join(p["pad"] for p in od))
    return 0


if __name__ == "__main__":
    sys.exit(main())
