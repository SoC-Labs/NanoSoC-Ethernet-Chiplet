#!/usr/bin/env python3
"""
Assert that every SIGNAL pin of every placed macro has routing metal on it,
measured in the STREAMED GDS rather than in the router's own database.

WHY THIS EXISTS
---------------
On 2026-08-23 the foundry rejected our merged stream with 14 PO.R.8 floating
gates. Three macro pins had shipped with NO METAL ON ANY LAYER:

    ...u_way0_cache_ram_data_ram_0_word_3_i   D[27], Q[27]
    ...u_way1_cache_ram_data_ram_0_word_3_i   D[27]

Nets RAMCLD0WDATA[123] / RAMCLD0RDATA[123]: cache data bit 123 unwritable on
both ways. Every DRC and connectivity gate we own passed that stream, because
a gate sitting behind a LEF-abstract driver is indistinguishable, to all of
them, from a gate sitting behind no driver at all. Only the merged stream --
where the macro's real transistors meet our real routing -- can tell them
apart, and by then the GDS is at the broker.

This closes that hole on our side. It intersects the PLACED macro LEF pin
rectangles against the metal actually present in the stream, and fails if any
signal pin is bare.

WHAT IT MEASURES, PRECISELY
---------------------------
A pin is CONNECTED if metal that does NOT belong to the macro itself overlaps
one of that pin's LEF port rectangles, with strictly positive area, ON THE SAME
LAYER as the port rectangle. Two sources of such metal are counted:

  WIRE  shapes drawn directly in the top-level cell (PATH, BOUNDARY, BOX)
  VIA   metal inside SREF'd masters placed in the top cell -- via cut cells
        carry their own landing pads, and write_stream emits them as
        references, not as flattened geometry

The macro's OWN pin metal is deliberately not counted. Memories ARE merged by
write_stream (unlike std cells and pads, which ship as empty shells), so the
macro structure contains its real pin shapes; counting them would make every
pin trivially "have metal" and the check vacuous. The question is strictly:
did OUR router put something on it.

    - Routing here is overwhelmingly GDS PATH (2.6M records), not BOUNDARY. A
      checker that walked only BOUNDARY would call the whole die bare. PATH
      width, PATHTYPE and BGNEXTN/ENDEXTN are all honoured.
    - Vias are SREFs. 2.33M of the top cell's references are via masters. A
      checker ignoring SREFs reports a pin reached by a via drop as bare.
      Masters are flattened (recursively, memoised) and placed.
    - Metal FILL is a different datatype -- routing is datatype 0, FILL is
      datatype 1, and M8/M9 use 40/41 and 60/61. Fill is excluded: a fill shape
      lying over a pin is not a connection.
    - LAYER IS MATCHED. A wire on M7 crossing above an M1/M2/M3 pin does not
      connect it. Targets are indexed per (gds layer, datatype) and a shape is
      only ever tested against targets on its own layer.
    - Only layers some pin actually declares a port on are scanned (M1-M4 for
      the cache macros), so the scan stays cheap.

KNOWN LIMITS (read before trusting a PASS)
------------------------------------------
    - Signal and power routing share a layer/datatype in the stream map (NET
      and SPNET both map to e.g. 31/0), so a signal pin buried under a power
      strap reads as connected. That cannot manufacture the defect this hunts
      -- "no metal on any layer" is unambiguous -- but it is why this is a
      floating-gate gate and not an LVS.
    - Non-Manhattan PATH segments fall back to a bounding box, which is
      permissive. The run prints the count.

HOW TO RUN
----------
    scripts/ci/gds_macro_pin_connected.py <stream.gds> --run <rundir>

        --run DIR       build run the stream came from; supplies the macro
                        placements (work/.../*.fp.gz), the GDS layer map
                        (work/tech/gdsout.stream.map) and the netlist that
                        resolves instance -> cell.
        --all-macros    check all 21 placed macros, not just the flash cache.
        --macros A,B    restrict to these cell types (default: the cache pair).
        --lef-root DIR  extra dir to search for <cell>/<cell>.lef (repeatable).
        --no-srefs      do not resolve SREF masters; count only top-level wire
                        metal. Use to size how much the via path contributes.
        --json FILE     full result, including every bare pin's coordinates.
        --quiet         summary line only.

    Exit 0 = every signal pin in scope has metal. Exit 1 = at least one bare
    pin. Exit 2 = could not measure, which is NOT a pass: an unresolvable LEF,
    placement or database scale aborts rather than silently narrowing scope.

    Pins are reported in two buckets. BARE means no metal of any kind, from any
    source, on any port layer -- that is the real defect. VIA-ONLY means reached
    by via landing metal with no top-level wire; it is reported for information
    and does not fail the gate.

MEASURED ON rzG  (see PROOF)
----------------------------
ASIC/submissions/nanosoc_eth_chiplet_pads_DRYRUN_20260823_rzG.gds
md5 41a0baee9343e10cb2c5f8b8fe1a4e50, run gdsrun-20260823-rzG, cache scope:

    FAIL -- 3 bare of 648 signal pins on the 8 flash_cache_data instances;
    the 2 flash_cache_tag instances are clean (100/100). 0 via-only.

The 3 are exactly D[27] and Q[27] on way0 word_3 and D[27] on way1 word_3 --
the set the foundry found, reached independently (LEF against stream, versus
their PO.R.8 on the merged database).

PROOF, BOTH DIRECTIONS
----------------------
A gate that cannot fail is not a gate; one that cannot pass is not one either.
Recorded 2026-08-24 by mutating a copy of the rzG stream, changing nothing else:

  FAILS on the real defect      rzG as shipped -> exit 1, 3 bare.

  PASSES when metal is present  splice M1 BOUNDARY rects over exactly those 3
                                pins -> exit 0, 0 bare of 648.

  LAYER MATCHING IS REAL        splice the same rects on M7 instead -> still
                                exit 1, still the same 3 bare. An unrelated
                                wire crossing above a pin does not connect it.
                                (A real false-pass mode: an independent checker
                                built the same day hit it via an M7 wire at
                                y=422.1.)

  SREF RESOLUTION IS REAL       splice an SREF to a via master over the 3 pins
                                -> exit 0. Via landing metal counts, so a
                                via-contacted pin is never misreported bare.

  AND ON UNMODIFIED DATA        the other 6 flash_cache_data instances report 0
                                bare of 81 each and both tag instances 0 of 50,
                                in the same pass -- a PASS is reachable on real
                                silicon data.

Reproduce every mutation with:  --selftest-suite OUT_DIR

DEPENDENCY-FREE on purpose: a plain GDSII record walk in the standard library.
No KLayout, no Calibre, no licence, no layout database. A 300 MB stream costs a
few minutes and a few hundred MB of RAM, so it runs in CI and can be handed to
the broker to run on their side of the merge.
"""
import argparse
import glob
import gzip
import json
import math
import os
import re
import struct
import sys
from bisect import bisect_left
from collections import Counter, defaultdict

# ---------------------------------------------------------------- GDS records
R_UNITS, R_BGNSTR, R_STRNAME, R_ENDSTR = 0x03, 0x05, 0x06, 0x07
R_BOUNDARY, R_PATH, R_SREF, R_AREF, R_TEXT = 0x08, 0x09, 0x0A, 0x0B, 0x0C
R_LAYER, R_DATATYPE, R_WIDTH, R_XY, R_ENDEL = 0x0D, 0x0E, 0x0F, 0x10, 0x11
R_SNAME, R_STRANS, R_MAG, R_ANGLE = 0x12, 0x1A, 0x1B, 0x1C
R_PATHTYPE, R_BGNEXTN, R_ENDEXTN = 0x21, 0x30, 0x31
R_BOX, R_BOXTYPE, R_NODE = 0x2D, 0x2E, 0x15

GRID = 5000               # spatial-hash cell in db units (1 dbu = 1 nm here)
MASTER_SHAPE_CAP = 4000   # a master with more metal than this is a merged
                          # macro or ROM, not a via; its interior is not our
                          # routing and must not count as a connection


def die(msg):
    sys.stderr.write("gds_macro_pin_connected: ERROR: %s\n" % msg)
    sys.exit(2)


def gds_real(b):
    """Decode an 8-byte GDSII real.

    NOT an IEEE double -- GDSII uses excess-64 base-16: bit 7 of byte 0 is the
    sign, bits 0-6 the exponent biased by 64, bytes 1-7 a 56-bit fraction.
    Reading these with '>d' silently yields garbage (the UNITS record then
    decodes to ~8e-33 metres per db unit instead of 1e-9), which downstream
    looks like a hang rather than an error.
    """
    sign = -1.0 if b[0] & 0x80 else 1.0
    exp = (b[0] & 0x7F) - 64
    mant = int.from_bytes(b[1:8], "big")
    return sign * mant / float(1 << 56) * (16.0 ** exp)


def read_units(path):
    """-> db units per micron, from the stream's own UNITS record."""
    with open(path, "rb") as f:
        chunk = f.read(65536)
    off = 0
    while off + 4 <= len(chunk):
        ln, rt, _d = struct.unpack(">HBB", chunk[off:off + 4])
        if ln < 4:
            break
        if rt == R_UNITS and off + 20 <= len(chunk):
            meters = gds_real(chunk[off + 12:off + 20])
            if not meters:
                die("UNITS record in %s has zero metres-per-dbu" % path)
            dbu = 1.0 / (meters * 1e6)
            # Every sane stream is 100..100000 dbu/um. A wild value means we
            # mis-decoded, and every coordinate downstream would be junk.
            if not (100.0 <= dbu <= 100000.0):
                die("implausible database scale %g dbu/um from %s -- refusing "
                    "to measure with a mis-decoded UNITS record" % (dbu, path))
            return dbu
        off += ln
    die("no UNITS record found in %s" % path)


# ------------------------------------------------------------------ stream map
def read_stream_map(path):
    """LEF layer name -> set of (gds layer, datatype) carrying ROUTED metal.

    Rows are '<lefname> <purposes> <num> <dt>'. Keep only rows whose purpose
    list mentions NET; drop FILL rows, because fill over a pin is not contact.
    """
    routing = defaultdict(set)
    with open(path) as f:
        for line in f:
            line = line.split("#", 1)[0].strip()
            if not line:
                continue
            p = line.split()
            if len(p) < 4:
                continue
            purposes = p[1].upper().split(",")
            if "FILL" in purposes or "NET" not in purposes:
                continue
            try:
                routing[p[0].upper()].add((int(p[-2]), int(p[-1])))
            except ValueError:
                continue
    if not routing:
        die("no routing rows parsed from stream map %s" % path)
    return routing


# ------------------------------------------------------------------ floorplan
def read_floorplan(path):
    """-> {leaf instance: (orient, llx_um, lly_um)} from an Innovus .fp[.gz]."""
    op = gzip.open if path.endswith(".gz") else open
    out = {}
    with op(path, "rt", errors="replace") as f:
        for line in f:
            if not line.startswith("Block:"):
                continue
            p = line.split()
            if len(p) < 5:
                continue
            try:
                out[p[1].rsplit("/", 1)[-1]] = (p[2].upper(),
                                                float(p[3]), float(p[4]))
            except ValueError:
                continue
    if not out:
        die("no 'Block:' placements parsed from %s" % path)
    return out


# -------------------------------------------------------------------- netlist
def read_inst_cells(path, wanted):
    """-> {instance: cell} from the P&R netlist.

    Instance names may be Verilog escaped identifiers (they contain '.'),
    written as '\\name ' -- backslash prefix, whitespace terminator.
    """
    want, found = set(wanted), {}
    pat = re.compile(r"(?m)^\s*([A-Za-z_][A-Za-z0-9_$]*)\s+\\?(\S+)\s*\(")
    with open(path, errors="replace") as f:
        for m in pat.finditer(f.read()):
            if m.group(2) in want:
                found.setdefault(m.group(2), m.group(1))
    return found


# A dangling net, as Innovus names one. The name alone is a CONVENTION and
# conventions lie, so every candidate is then required to occur exactly twice
# in the netlist -- one `wire` declaration and one port binding. A net with a
# second terminal is not dangling however it is spelled.
_DANGLING_NAME = re.compile(r"^UNCONNECTED\d+$")
_INST_HEAD = re.compile(r"(?m)^\s*([A-Za-z_][A-Za-z0-9_$]*)\s+\\?(\S+)\s*\(")


def _balanced(txt, open_at):
    """Text between txt[open_at] == '(' and its matching ')'. None if unclosed."""
    depth = 0
    for i in range(open_at, len(txt)):
        c = txt[i]
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return txt[open_at + 1:i]
    return None


def read_unconnected_ports(path, lef_pins_by_inst):
    """-> {instance: {lef_pin_name: net_or_empty}} for ports left DANGLING.

    WHY THIS EXISTS. `bare` means "our router put no metal on it". That is the
    right question for a pin the netlist CONNECTS -- the cache-macro defect of
    23 August was exactly that -- and it is the wrong question for a pin the
    netlist deliberately leaves open. A ROM's address-mirror outputs have no
    net at all: there is nothing to route, and a gate that demands metal on
    them is asking the router to invent a wire.

    So this reads what the netlist says, per pin, and lets the caller separate
    "no metal on a connected pin" (a defect) from "no metal on a pin with no
    net" (a design decision, which is then judged on its own terms).

    ERRS TOWARDS UNKNOWN. A port whose expression cannot be mapped bit-for-bit
    onto the LEF's pin names -- a constant like 9'd0, a bus written by name, a
    width that disagrees -- is dropped from BOTH return values, so it reads as
    `unmapped` rather than as either verdict. Only an exact match adjudicates,
    and an unmapped bare pin stays a defect.

    Returns (dangling, mapped): both {instance: {lef_pin: net}}. `mapped` is
    every pin whose bit-mapping succeeded; `dangling` is the subset with no
    other terminal.
    """
    txt = open(path, errors="replace").read()
    want = set(lef_pins_by_inst)
    out, candidates = {}, set()
    for m in _INST_HEAD.finditer(txt):
        inst = m.group(2)
        if inst not in want:
            continue
        body = _balanced(txt, m.end() - 1)
        if body is None:
            continue
        lefpins, res = lef_pins_by_inst[inst], {}
        for pm in re.finditer(r"\.(\w+)\s*\(", body):
            expr = _balanced(body, pm.end() - 1)
            if expr is None:
                continue
            port, expr = pm.group(1), expr.strip()
            if expr.startswith("{") and expr.endswith("}"):
                nets = [x.strip() for x in expr[1:-1].split(",")]
            else:
                nets = [expr]
            # LEF bit names for this port, MSB first -- a Verilog concatenation
            # is written MSB first and the two have to be lined up, not zipped
            # in whatever order the set iterates.
            bits = sorted((int(x) for p in lefpins
                           for x in re.findall(r"^%s\[(\d+)\]$"
                                               % re.escape(port), p)),
                          reverse=True)
            if not bits and len(nets) == 1:
                res[port] = nets[0]
            elif len(bits) == len(nets):
                for j, n in enumerate(nets):
                    res["%s[%d]" % (port, bits[j])] = n
            else:
                for j, n in enumerate(nets):
                    res["%s[?%d]" % (port, j)] = n
        out[inst] = res
        candidates |= {v for v in res.values() if _DANGLING_NAME.match(v)}
    # THE CONTROL on the naming convention: count every occurrence of each
    # candidate name in the whole file. Exactly two -- declaration plus the one
    # binding -- is the only count that means "no other terminal".
    occ = Counter()
    for m in re.finditer(r"\bUNCONNECTED\d+\b", txt):
        if m.group(0) in candidates:
            occ[m.group(0)] += 1
    dangling, mapped = {}, {}
    for inst, res in out.items():
        keep = {p: n for p, n in res.items() if "[?" not in p}
        mapped[inst] = keep
        dangling[inst] = {p: n for p, n in keep.items()
                          if n == "" or (_DANGLING_NAME.match(n)
                                         and occ.get(n) == 2)}
    return dangling, mapped


# ------------------------------------------------------------------------ LEF
def parse_lef(path):
    """-> {MACRO: {'size': (w,h), 'pins': {pin: {'use','dir','ports'}}}}

    ports is [(LAYERNAME, x1, y1, x2, y2)] in macro-local microns.
    """
    macros, cur, pin, layer, poly = {}, None, None, None, 0
    with open(path, errors="replace") as f:
        for raw in f:
            line = raw.split("#", 1)[0].strip()
            if not line:
                continue
            t = line.split()
            k = t[0].upper()
            if k == "MACRO" and len(t) > 1:
                cur, pin = t[1], None
                macros[cur] = {"size": None, "pins": {}}
            elif cur is None:
                continue
            elif k == "SIZE" and len(t) > 3:
                try:
                    macros[cur]["size"] = (float(t[1]), float(t[3]))
                except ValueError:
                    pass
            elif k == "PIN" and len(t) > 1:
                pin, layer = t[1], None
                macros[cur]["pins"][pin] = {"use": "SIGNAL", "dir": "",
                                            "ports": []}
            elif k == "END" and len(t) > 1 and pin is not None and t[1] == pin:
                pin, layer = None, None
            elif pin is not None:
                if k == "USE" and len(t) > 1:
                    macros[cur]["pins"][pin]["use"] = t[1].rstrip(";").upper()
                elif k == "DIRECTION" and len(t) > 1:
                    macros[cur]["pins"][pin]["dir"] = t[1].rstrip(";").upper()
                elif k == "LAYER" and len(t) > 1:
                    layer = t[1].rstrip(";").upper()
                elif k == "POLYGON":
                    poly += 1
                elif k == "RECT" and layer is not None:
                    v = [x for x in t[1:] if x != ";"]
                    try:
                        x1, y1, x2, y2 = (float(v[0]), float(v[1]),
                                          float(v[2]), float(v[3]))
                    except (IndexError, ValueError):
                        continue
                    macros[cur]["pins"][pin]["ports"].append(
                        (layer, min(x1, x2), min(y1, y2),
                         max(x1, x2), max(y1, y2)))
    if poly:
        sys.stderr.write("warning: %d POLYGON port(s) in %s not consumed\n"
                         % (poly, path))
    return macros


def find_lef(cell, roots):
    for r in roots:
        for cand in (os.path.join(r, cell, cell + ".lef"),
                     os.path.join(r, cell + ".lef")):
            if os.path.isfile(cand):
                return cand
        hits = sorted(glob.glob(os.path.join(r, "*", cell + ".lef")))
        if hits:
            return hits[0]
    return None


# -------------------------------------------------------------------- placing
ORIENT = {
    "R0": lambda x, y: (x, y),      "N":  lambda x, y: (x, y),
    "R90": lambda x, y: (-y, x),    "W":  lambda x, y: (-y, x),
    "R180": lambda x, y: (-x, -y),  "S":  lambda x, y: (-x, -y),
    "R270": lambda x, y: (y, -x),   "E":  lambda x, y: (y, -x),
    "MY": lambda x, y: (-x, y),     "FN": lambda x, y: (-x, y),
    "MX": lambda x, y: (x, -y),     "FS": lambda x, y: (x, -y),
    "MX90": lambda x, y: (y, x),    "FW": lambda x, y: (y, x),
    "MY90": lambda x, y: (-y, -x),  "FE": lambda x, y: (-y, -x),
}


def placer(orient, w, h, llx, lly):
    """-> f(x, y): macro-local microns to top-level microns.

    DEF semantics: orient about the origin, then translate so the ORIENTED
    bounding box has its lower-left corner at (llx, lly).
    """
    fn = ORIENT.get(orient.upper())
    if fn is None:
        die("unhandled orientation %r" % orient)
    cs = [fn(0, 0), fn(w, 0), fn(0, h), fn(w, h)]
    ox = llx - min(c[0] for c in cs)
    oy = lly - min(c[1] for c in cs)
    return lambda x, y: (fn(x, y)[0] + ox, fn(x, y)[1] + oy)


def _rects_from_path(pts, width, pathtype, bgn, end):
    """Expand a PATH centreline into axis-aligned rectangles."""
    out, nonman, hw = [], 0, width // 2
    if hw <= 0:
        return out, 0
    n = len(pts) // 2
    for i in range(n - 1):
        x1, y1 = pts[2 * i], pts[2 * i + 1]
        x2, y2 = pts[2 * i + 2], pts[2 * i + 3]
        e0 = e1 = 0
        if pathtype in (1, 2):
            e0, e1 = (hw if i == 0 else 0), (hw if i == n - 2 else 0)
        elif pathtype == 4:
            e0, e1 = (bgn if i == 0 else 0), (end if i == n - 2 else 0)
        if y1 == y2:
            lo, hi = (x1 - e0, x2 + e1) if x1 <= x2 else (x2 - e1, x1 + e0)
            out.append((lo, y1 - hw, hi, y1 + hw))
        elif x1 == x2:
            lo, hi = (y1 - e0, y2 + e1) if y1 <= y2 else (y2 - e1, y1 + e0)
            out.append((x1 - hw, lo, x1 + hw, hi))
        else:
            nonman += 1
            out.append((min(x1, x2) - hw, min(y1, y2) - hw,
                        max(x1, x2) + hw, max(y1, y2) + hw))
    return out, nonman


def _xform(x1, y1, x2, y2, dx, dy, refl, ang, mag):
    """Place a local rect: reflect about X, scale, rotate, translate."""
    a = (ang or 0.0) % 360.0
    out = []
    for px, py in ((x1, y1), (x2, y1), (x2, y2), (x1, y2)):
        if refl:
            py = -py
        if mag and mag != 1.0:
            px, py = px * mag, py * mag
        if a == 90.0:
            px, py = -py, px
        elif a == 180.0:
            px, py = -px, -py
        elif a == 270.0:
            px, py = py, -px
        elif a:
            r = math.radians(a)
            c, s = math.cos(r), math.sin(r)
            px, py = px * c - py * s, px * s + py * c
        out.append((px + dx, py + dy))
    xs = [p[0] for p in out]
    ys = [p[1] for p in out]
    return (int(min(xs)), int(min(ys)), int(max(xs)), int(max(ys)))


# ------------------------------------------------------- master (SREF) library
def collect_masters(gds, top, exclude, layers):
    """Gather geometry and child references of every non-top structure.

    -> {name: {'rects': [(ld,x1,y1,x2,y2)], 'refs': [...], 'over': bool}}.
    `over` marks a structure whose metal on `layers` exceeds MASTER_SHAPE_CAP:
    a merged macro or ROM rather than a via. Those are dropped -- their interior
    is the vendor's own metal, not our routing.
    """
    out = {}
    cur = rec = None
    elem = lay = dt = None
    width = pathtype = bgn = end = 0
    sname, reflect, angle, mag = None, 0, 0.0, 1.0
    unpack = struct.unpack
    fmts = {}

    with open(gds, "rb", buffering=1 << 20) as f:
        read = f.read
        while True:
            head = read(4)
            if len(head) < 4:
                break
            ln, rt, _d = unpack(">HBB", head)
            if ln < 4:
                break
            body = read(ln - 4)

            if rt == R_STRNAME:
                cur = body.rstrip(b"\x00").decode("ascii", "replace")
                rec = None if (cur == top or cur in exclude) else \
                    out.setdefault(cur, {"rects": [], "refs": [], "over": False})
            elif rt == R_ENDSTR:
                cur = rec = None
            elif rec is None:
                continue
            elif rt == R_BOUNDARY or rt == R_PATH or rt == R_BOX:
                elem = rt
                lay = dt = None
                width = pathtype = bgn = end = 0
            elif rt == R_SREF:
                elem = rt
                sname, reflect, angle, mag = None, 0, 0.0, 1.0
            elif rt == R_AREF or rt == R_TEXT or rt == R_NODE:
                elem = None
            elif rt == R_LAYER:
                lay = unpack(">h", body[:2])[0]
            elif rt == R_DATATYPE or rt == R_BOXTYPE:
                dt = unpack(">h", body[:2])[0]
            elif rt == R_WIDTH:
                width = unpack(">i", body[:4])[0]
            elif rt == R_PATHTYPE:
                pathtype = unpack(">h", body[:2])[0]
            elif rt == R_BGNEXTN:
                bgn = unpack(">i", body[:4])[0]
            elif rt == R_ENDEXTN:
                end = unpack(">i", body[:4])[0]
            elif rt == R_SNAME:
                sname = body.rstrip(b"\x00").decode("ascii", "replace")
            elif rt == R_STRANS:
                reflect = unpack(">H", body[:2])[0] & 0x8000
            elif rt == R_ANGLE:
                angle = gds_real(body[:8])
            elif rt == R_MAG:
                mag = gds_real(body[:8])
            elif rt == R_XY and elem is not None:
                if elem == R_SREF:
                    if sname and len(body) >= 8:
                        x, y = unpack(">ii", body[:8])
                        rec["refs"].append((sname, x, y, bool(reflect),
                                            angle, mag))
                    elem = None
                    continue
                ld = (lay, dt)
                if ld not in layers:
                    elem = None
                    continue
                if rec["over"]:
                    continue
                if len(rec["rects"]) >= MASTER_SHAPE_CAP:
                    rec["over"] = True
                    rec["rects"] = []
                    continue
                n = len(body) >> 2
                fm = fmts.get(n)
                if fm is None:
                    fm = fmts[n] = ">%di" % n
                v = unpack(fm, body)
                if elem == R_PATH:
                    rs, _nm = _rects_from_path(v, abs(width), pathtype, bgn, end)
                    for r in rs:
                        rec["rects"].append((ld,) + r)
                else:
                    xs, ys = v[0::2], v[1::2]
                    rec["rects"].append((ld, min(xs), min(ys),
                                         max(xs), max(ys)))
            elif rt == R_ENDEL:
                elem = None

    return {k: v for k, v in out.items() if not v["over"]}


def flatten_master(name, lib, memo, depth=0):
    """-> [(ld, x1, y1, x2, y2)] for a master, resolving child SREFs."""
    if name in memo:
        return memo[name]
    if depth > 8 or name not in lib:
        memo[name] = []
        return memo[name]
    memo[name] = []                        # cycle guard
    rects = list(lib[name]["rects"])
    for child, dx, dy, refl, ang, mag in lib[name]["refs"]:
        for ld, x1, y1, x2, y2 in flatten_master(child, lib, memo, depth + 1):
            rects.append((ld,) + _xform(x1, y1, x2, y2, dx, dy, refl, ang, mag))
    memo[name] = rects
    return rects


# ------------------------------------------------------------------ main scan
def build_index(targets):
    """Sparse two-level index per layer: sorted rows, sorted cols in each row.

    Routing wires are long, thin, and mostly nowhere near a macro pin. A dense
    cell walk over the macro region costs thousands of empty lookups per wire;
    bisecting only the OCCUPIED cells keeps the worst wire to a few probes.
    """
    index = {}
    for ld, rects in targets.items():
        g = defaultdict(list)
        for (x1, y1, x2, y2, uid) in rects:
            for gx in range(x1 // GRID, x2 // GRID + 1):
                for gy in range(y1 // GRID, y2 // GRID + 1):
                    g[(gx, gy)].append((x1, y1, x2, y2, uid))
        if not g:
            continue
        gxs = [c[0] for c in g]
        gys = [c[1] for c in g]
        rows = {}
        for gy in set(gys):
            cols = sorted(c[0] for c in g if c[1] == gy)
            rows[gy] = (cols, [g[(cx, gy)] for cx in cols])
        index[ld] = (min(gxs), min(gys), max(gxs), max(gys), sorted(rows), rows)
    return index


def _tester(sink):
    add = sink.add

    def test(meta, x1, y1, x2, y2):
        gminx, gminy, gmaxx, gmaxy, rowkeys, rows = meta
        ax = x1 // GRID
        if ax > gmaxx:
            return
        bx = x2 // GRID
        if bx < gminx:
            return
        ay = y1 // GRID
        if ay > gmaxy:
            return
        by = y2 // GRID
        if by < gminy:
            return
        j = bisect_left(rowkeys, ay)
        nr = len(rowkeys)
        while j < nr:
            gy = rowkeys[j]
            if gy > by:
                break
            cols, cells = rows[gy]
            i = bisect_left(cols, ax)
            nc = len(cols)
            while i < nc:
                if cols[i] > bx:
                    break
                for (tx1, ty1, tx2, ty2, uid) in cells[i]:
                    # strictly positive overlap; abutment is not contact
                    if x1 < tx2 and tx1 < x2 and y1 < ty2 and ty1 < y2:
                        add(uid)
                i += 1
            j += 1
    return test


def scan_stream(gds, top, targets, master_rects, want_srefs):
    """Single pass over the top cell. -> (wire_hits, via_hits, stats)."""
    index = build_index(targets)
    wire, via = set(), set()
    test_wire = _tester(wire)
    test_via = _tester(via)
    stats = {"shapes": 0, "nonmanhattan": 0, "top_found": False, "paths": 0,
             "boundaries": 0, "boxes": 0, "srefs": 0, "srefs_expanded": 0}

    # Byte-keyed master lookup avoids decoding 2.3M SREF names.
    mb = {}
    if want_srefs:
        for name, rects in master_rects.items():
            if rects:
                mb[name.encode("ascii", "replace")] = rects

    unpack = struct.unpack
    fmts = {}
    cur = None
    elem = lay = dt = None
    width = pathtype = bgn = end = 0
    cur_master, reflect, angle, mag = None, 0, 0.0, 1.0
    in_top = False

    with open(gds, "rb", buffering=1 << 20) as f:
        read = f.read
        while True:
            head = read(4)
            if len(head) < 4:
                break
            ln, rt, _d = unpack(">HBB", head)
            if ln < 4:
                break
            body = read(ln - 4)

            if rt == R_XY:
                if elem is None or not in_top:
                    continue
                if elem == R_SREF:
                    if cur_master is not None and len(body) >= 8:
                        dx, dy = unpack(">ii", body[:8])
                        stats["srefs_expanded"] += 1
                        simple = (not reflect) and (not angle) and \
                                 (mag == 1.0 or not mag)
                        for ld, mx1, my1, mx2, my2 in cur_master:
                            meta = index.get(ld)
                            if meta is None:
                                continue
                            if simple:
                                test_via(meta, mx1 + dx, my1 + dy,
                                         mx2 + dx, my2 + dy)
                            else:
                                test_via(meta, *_xform(mx1, my1, mx2, my2,
                                                       dx, dy, bool(reflect),
                                                       angle, mag))
                    elem = None
                    continue
                meta = index.get((lay, dt))
                if meta is None:
                    elem = None
                    continue
                n = len(body) >> 2
                fm = fmts.get(n)
                if fm is None:
                    fm = fmts[n] = ">%di" % n
                v = unpack(fm, body)
                stats["shapes"] += 1
                if elem == R_PATH:
                    stats["paths"] += 1
                    hw = abs(width) >> 1
                    if not hw:
                        continue
                    if n == 4:                    # 2-point path: the 99% case
                        x1, y1, x2, y2 = v
                        e0 = e1 = 0
                        if pathtype == 1 or pathtype == 2:
                            e0 = e1 = hw
                        elif pathtype == 4:
                            e0, e1 = bgn, end
                        if y1 == y2:
                            if x1 <= x2:
                                test_wire(meta, x1 - e0, y1 - hw, x2 + e1, y1 + hw)
                            else:
                                test_wire(meta, x2 - e1, y1 - hw, x1 + e0, y1 + hw)
                        elif x1 == x2:
                            if y1 <= y2:
                                test_wire(meta, x1 - hw, y1 - e0, x1 + hw, y2 + e1)
                            else:
                                test_wire(meta, x1 - hw, y2 - e1, x1 + hw, y1 + e0)
                        else:
                            stats["nonmanhattan"] += 1
                            test_wire(meta, min(x1, x2) - hw, min(y1, y2) - hw,
                                      max(x1, x2) + hw, max(y1, y2) + hw)
                    else:
                        rs, nm = _rects_from_path(v, abs(width), pathtype,
                                                  bgn, end)
                        stats["nonmanhattan"] += nm
                        for r in rs:
                            test_wire(meta, *r)
                else:
                    if elem == R_BOUNDARY:
                        stats["boundaries"] += 1
                    else:
                        stats["boxes"] += 1
                    xs, ys = v[0::2], v[1::2]
                    test_wire(meta, min(xs), min(ys), max(xs), max(ys))
            elif rt == R_LAYER:
                lay = unpack(">h", body[:2])[0]
            elif rt == R_DATATYPE or rt == R_BOXTYPE:
                dt = unpack(">h", body[:2])[0]
            elif rt == R_BOUNDARY or rt == R_PATH or rt == R_BOX:
                elem = rt
                lay = dt = None
                width = pathtype = bgn = end = 0
            elif rt == R_ENDEL:
                elem = None
            elif rt == R_SNAME:
                cur_master = mb.get(body.rstrip(b"\x00")) if in_top else None
            elif rt == R_SREF:
                elem = R_SREF
                cur_master, reflect, angle, mag = None, 0, 0.0, 1.0
                if in_top:
                    stats["srefs"] += 1
            elif rt == R_STRANS:
                reflect = unpack(">H", body[:2])[0] & 0x8000
            elif rt == R_ANGLE:
                angle = gds_real(body[:8])
            elif rt == R_MAG:
                mag = gds_real(body[:8])
            elif rt == R_WIDTH:
                width = unpack(">i", body[:4])[0]
            elif rt == R_PATHTYPE:
                pathtype = unpack(">h", body[:2])[0]
            elif rt == R_BGNEXTN:
                bgn = unpack(">i", body[:4])[0]
            elif rt == R_ENDEXTN:
                end = unpack(">i", body[:4])[0]
            elif rt == R_AREF or rt == R_TEXT or rt == R_NODE:
                elem = None
            elif rt == R_STRNAME:
                cur = body.rstrip(b"\x00").decode("ascii", "replace")
                in_top = (cur == top)
                if in_top:
                    stats["top_found"] = True
            elif rt == R_ENDSTR:
                cur, in_top = None, False

    return wire, via, stats


# ------------------------------------------------------------------- mutation
def _rec(rtype, dtype, payload=b""):
    return struct.pack(">HBB", 4 + len(payload), rtype, dtype) + payload


def splice(gds, out_gds, top, boundaries=(), srefs=()):
    """Copy `gds` to `out_gds`, inserting elements into the top structure.

    boundaries: [(layer, datatype, x1, y1, x2, y2)] in db units.
    srefs:      [(sname, x, y)] in db units.
    They go immediately before the top structure's ENDSTR, a legal position for
    an element, and nothing else in the file changes.
    """
    blob = b""
    for lay, dt, x1, y1, x2, y2 in boundaries:
        xy = b"".join(struct.pack(">ii", px, py) for px, py in
                      ((x1, y1), (x2, y1), (x2, y2), (x1, y2), (x1, y1)))
        blob += (_rec(R_BOUNDARY, 0x00)
                 + _rec(R_LAYER, 0x02, struct.pack(">h", lay))
                 + _rec(R_DATATYPE, 0x02, struct.pack(">h", dt))
                 + _rec(R_XY, 0x03, xy) + _rec(R_ENDEL, 0x00))
    for name, x, y in srefs:
        nb = name.encode("ascii")
        if len(nb) % 2:
            nb += b"\x00"
        blob += (_rec(R_SREF, 0x00) + _rec(R_SNAME, 0x06, nb)
                 + _rec(R_XY, 0x03, struct.pack(">ii", x, y))
                 + _rec(R_ENDEL, 0x00))

    cur, wrote = None, False
    with open(gds, "rb", buffering=1 << 20) as f, \
            open(out_gds, "wb", buffering=1 << 20) as o:
        while True:
            head = f.read(4)
            if len(head) < 4:
                break
            ln, rt, _d = struct.unpack(">HBB", head)
            if ln < 4:
                o.write(head)
                break
            body = f.read(ln - 4)
            if rt == R_STRNAME:
                cur = body.rstrip(b"\x00").decode("ascii", "replace")
            if rt == R_ENDSTR and cur == top and not wrote:
                o.write(blob)
                wrote = True
            o.write(head)
            o.write(body)
    if not wrote:
        die("splice: never found ENDSTR of top structure %r" % top)
    return out_gds


# ----------------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser(
        description="Assert placed-macro signal pins have routing metal in a GDS.")
    ap.add_argument("gds")
    ap.add_argument("--run", required=True)
    ap.add_argument("--top", default=None)
    ap.add_argument("--macros", default="flash_cache_data,flash_cache_tag")
    ap.add_argument("--all-macros", action="store_true")
    ap.add_argument("--lef-root", action="append", default=[])
    ap.add_argument("--no-srefs", action="store_true")
    ap.add_argument("--json", default=None)
    ap.add_argument("--quiet", action="store_true")
    ap.add_argument("--selftest-suite", metavar="DIR", default=None,
                    help="write the mutation streams that prove this gate "
                         "both directions, then say how to run them")
    a = ap.parse_args()

    run = os.path.abspath(a.run)
    if not os.path.isdir(run):
        die("no such run dir: %s" % run)

    fps = (sorted(glob.glob(os.path.join(run, "work", "*_routed", "*.fp.gz"))) or
           sorted(glob.glob(os.path.join(run, "work", "*", "*.fp.gz"))))
    if not fps:
        die("no floorplan (*.fp.gz) under %s/work/" % run)
    fp = fps[-1]

    smap = os.path.join(run, "work", "tech", "gdsout.stream.map")
    if not os.path.isfile(smap):
        die("no stream map at %s" % smap)

    nets = sorted(glob.glob(os.path.join(run, "outputs", "*_pnr.v")))
    if not nets:
        die("no P&R netlist (outputs/*_pnr.v) under %s" % run)
    netlist = nets[0]
    top = a.top or os.path.basename(netlist).rsplit("_pnr.v", 1)[0]

    # Site paths come from the environment, never hardcoded: this repo is
    # public and the guard rejects an absolute site path in tracked content.
    # MEM_LIB_ROOT is exported by ASIC/common.mk like every other flow variable.
    _mem = os.environ.get("MEM_LIB_ROOT", "")
    lef_roots = list(a.lef_root) + ([_mem] if _mem else []) + [
                                    os.path.join(run, "romlibs")]

    routing_layers = read_stream_map(smap)
    placements = read_floorplan(fp)
    inst_cell = read_inst_cells(netlist, placements.keys())
    dbu = read_units(a.gds)

    wanted = None if a.all_macros else set(
        x.strip() for x in a.macros.split(",") if x.strip())

    lef_cache, targets = {}, defaultdict(list)
    pin_meta, scope, missing = {}, [], []
    macro_cells = set()
    uid = 0
    for inst, (orient, llx, lly) in sorted(placements.items()):
        cell = inst_cell.get(inst)
        if cell is None or (wanted is not None and cell not in wanted):
            continue
        if cell not in lef_cache:
            p = find_lef(cell, lef_roots)
            lef_cache[cell] = parse_lef(p).get(cell) if p else None
        m = lef_cache[cell]
        if m is None:
            missing.append((inst, cell))
            continue
        if not m["size"]:
            die("LEF macro %s has no SIZE" % cell)
        macro_cells.add(cell)
        w, h = m["size"]
        place = placer(orient, w, h, llx, lly)
        n_sig = 0
        for pinname, pd in sorted(m["pins"].items()):
            if pd["use"] != "SIGNAL":
                continue
            n_sig += 1
            uid += 1
            pin_meta[uid] = (inst, cell, pinname, pd["dir"], [])
            for lname, x1, y1, x2, y2 in pd["ports"]:
                lds = routing_layers.get(lname.upper())
                if not lds:
                    continue
                ax, ay = place(x1, y1)
                bx, by = place(x2, y2)
                X1, X2 = sorted((ax, bx))
                Y1, Y2 = sorted((ay, by))
                pin_meta[uid][4].append((lname, X1, Y1, X2, Y2))
                q = (int(round(X1 * dbu)), int(round(Y1 * dbu)),
                     int(round(X2 * dbu)), int(round(Y2 * dbu)), uid)
                for ld in lds:
                    targets[ld].append(q)
        scope.append((inst, cell, n_sig))

    for inst, cell in missing[:10]:
        sys.stderr.write("warning: no LEF for cell %s (inst %s)\n" % (cell, inst))
    if not pin_meta:
        die("no signal pins in scope -- nothing measured, which is not a pass")

    master_rects = {}
    if not a.no_srefs:
        lib = collect_masters(a.gds, top, macro_cells, set(targets))
        memo = {}
        for name in lib:
            r = flatten_master(name, lib, memo)
            if r:
                master_rects[name] = r

    wire, via, stats = scan_stream(a.gds, top, targets, master_rects,
                                   not a.no_srefs)
    if not stats["top_found"]:
        die("top structure %r not present in %s" % (top, a.gds))

    connected = wire | via
    bare = sorted(u for u in pin_meta if u not in connected)
    viaonly = sorted(u for u in pin_meta if u in via and u not in wire)

    # WHAT THE NETLIST SAYS about each bare pin. Read only for the instances
    # that actually contributed pins, and only used to LABEL a bare pin -- it
    # never removes one from the census, and a pin it cannot map stays
    # unlabelled. See read_unconnected_ports.
    lef_pins_by_inst = defaultdict(set)
    for _u, (i, c, p, _d, _o) in pin_meta.items():
        lef_pins_by_inst[i].add(p)
    try:
        dangling, mapped = read_unconnected_ports(netlist,
                                                  dict(lef_pins_by_inst))
    except (OSError, ValueError) as e:            # never fail the census on this
        sys.stderr.write("warning: could not read the netlist for dangling "
                         "ports (%s); bare pins will read `unmapped`\n" % e)
        dangling, mapped = {}, {}
    label = {}
    for u, (i, _c, p, _d, _o) in pin_meta.items():
        if p in dangling.get(i, {}):
            label[u] = "dangling:%s" % (dangling[i][p] or "(no net)")
        elif p in mapped.get(i, {}):
            label[u] = "net:%s" % mapped[i][p]
        else:
            label[u] = "unmapped"
    n_bare_dangling = sum(1 for u in bare if label[u].startswith("dangling:"))

    per_inst = defaultdict(lambda: [0, 0])
    for u, (inst, _c, _p, _d, _o) in pin_meta.items():
        per_inst[inst][0] += 1
        if u not in connected:
            per_inst[inst][1] += 1

    total = len(pin_meta)
    if not a.quiet:
        print("stream      : %s" % a.gds)
        print("run         : %s" % run)
        print("top         : %s   (%g dbu/um)" % (top, dbu))
        print("macros      : %d instance(s), %d signal pin(s)" % (len(scope), total))
        print("layers      : %s" % ", ".join("%d/%d" % ld for ld in sorted(targets)))
        print("wire shapes : %d (%d PATH, %d BOUNDARY, %d BOX), non-Manhattan %d"
              % (stats["shapes"], stats["paths"], stats["boundaries"],
                 stats["boxes"], stats["nonmanhattan"]))
        print("srefs       : %d in top, %d metal-bearing masters, %d expanded"
              % (stats["srefs"], len(master_rects), stats["srefs_expanded"]))
        print("")
        for inst, cell, _n in sorted(scope):
            t, b = per_inst[inst]
            print("  %-4s %3d/%-3d connected  %-17s %s"
                  % ("BARE" if b else "ok", t - b, t, cell, inst))
        print("")
        if viaonly:
            print("VIA-ONLY (via landing metal, no top-level wire) -- informational:")
            for u in viaonly:
                i, _c, p, d, _o = pin_meta[u]
                print("  %s %s [%s]" % (i, p, d or "?"))
            print("")
        if bare:
            print("BARE SIGNAL PINS -- no metal of any kind on any port layer:")
            for u in bare:
                i, _c, p, d, ports = pin_meta[u]
                print("  %s %s [%s]" % (i, p, d or "?"))
                for lname, X1, Y1, X2, Y2 in ports:
                    print("      %-3s  (%.4f %.4f) (%.4f %.4f) um"
                          % (lname, X1, Y1, X2, Y2))

    verdict = "PASS" if not bare else "FAIL"
    print("%s: %d bare of %d signal pins on %d placed macro(s)%s"
          % (verdict, len(bare), total, len(scope),
             ", %d via-only" % len(viaonly) if viaonly else ""))

    if a.json:
        with open(a.json, "w") as f:
            json.dump({
                "verdict": verdict, "stream": a.gds, "run": run, "top": top,
                "dbu_per_um": dbu, "bare_count": len(bare),
                "via_only_count": len(viaonly), "pin_count": total,
                "srefs_resolved": not a.no_srefs,
                "netlist": os.path.relpath(netlist, run),
                "bare_netlist_dangling": n_bare_dangling,
                "bare_netlist_driven_or_unmapped": len(bare) - n_bare_dangling,
                "instances": [{"instance": i, "cell": c, "pins": per_inst[i][0],
                               "bare": per_inst[i][1]}
                              for i, c, _n in sorted(scope)],
                "bare_pins": [{"instance": pin_meta[u][0], "cell": pin_meta[u][1],
                               "pin": pin_meta[u][2], "direction": pin_meta[u][3],
                               "netlist": label[u],
                               "ports": [{"layer": l, "llx": x1, "lly": y1,
                                          "urx": x2, "ury": y2}
                                         for l, x1, y1, x2, y2 in pin_meta[u][4]]}
                              for u in bare],
                "via_only_pins": [{"instance": pin_meta[u][0],
                                   "pin": pin_meta[u][2]} for u in viaonly],
                "stats": stats,
            }, f, indent=2)

    if a.selftest_suite:
        d = a.selftest_suite
        os.makedirs(d, exist_ok=True)
        if not bare:
            sys.stderr.write("selftest-suite: this stream has no bare pins; "
                             "run it on one that does (rzG)\n")
        else:
            pos, neg, srf = [], [], []
            for u in bare:
                for lname, X1, Y1, X2, Y2 in pin_meta[u][4]:
                    q = (int(round(X1 * dbu)), int(round(Y1 * dbu)),
                         int(round(X2 * dbu)), int(round(Y2 * dbu)))
                    for ld in sorted(routing_layers.get(lname.upper(), ())):
                        pos.append((ld[0], ld[1]) + q)     # same layer: PASS
                        break
                    for ld in sorted(routing_layers.get("M7", ())):
                        neg.append((ld[0], ld[1]) + q)     # wrong layer: FAIL
                        break
                    srf.append(((X1 + X2) / 2.0, (Y1 + Y2) / 2.0))
                    break
            splice(a.gds, os.path.join(d, "pos_same_layer.gds"), top,
                   boundaries=pos)
            splice(a.gds, os.path.join(d, "neg_wrong_layer_M7.gds"), top,
                   boundaries=neg)
            vm = max(master_rects, key=lambda k: len(master_rects[k])) \
                if master_rects else None
            if vm:
                splice(a.gds, os.path.join(d, "pos_via_sref.gds"), top,
                       srefs=[(vm, int(round(cx * dbu)), int(round(cy * dbu)))
                              for cx, cy in srf])
            sys.stderr.write(
                "selftest-suite written to %s\n"
                "  pos_same_layer.gds      must PASS (0 bare)\n"
                "  neg_wrong_layer_M7.gds  must FAIL with the SAME %d bare\n"
                "%s" % (d, len(bare),
                        "  pos_via_sref.gds        must PASS (via metal counts,"
                        " master %s)\n" % vm if vm else ""))

    return 1 if bare else 0


if __name__ == "__main__":
    sys.exit(main())
