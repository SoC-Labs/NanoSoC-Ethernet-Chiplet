#!/usr/bin/env python3
"""gds_census.py - assert that REQUIRED geometry is PRESENT in a GDSII stream.

    gds_census.py derive  --run-dir <build> --scripts-dir <scripts> --out exp.json
    gds_census.py census  --gds <file.gds> [--json out.json]
    gds_census.py check   --gds <file.gds> --expect exp.json [--json out.json]
    gds_census.py diff    --a a.json --b b.json

WHY THIS EXISTS
===============

Every signoff deck this project runs - Calibre DRC, ANT, BND, and Innovus
check_drc - answers the same shape of question: does the geometry that IS here
break a rule? None of them answers the complementary one: is geometry that
MUST be here missing? A stream with an entire mask layer dropped, a bond pad
whose AP opening was exiled by a LEFOBS policy, a memory macro that arrived as
an M1-only shell, or a pad ring that a skipped stage never created, is CLEAN
under all four. It opens in a viewer, it streams, it passes.

That blind spot is stated in ASIC/genus-innovus/scripts/gdsmap_derive.py:

    "NOTHING IN DRC OR ANTENNA CATCHES IT -- both test whether present
     geometry breaks a rule, never whether required geometry is absent. This
     was found on 2026-08-13 only by comparing against a previously taped-out
     GDS."

The inverse error costs just as much. On 2026-08-17 a shape-count census showed
the bond pad structures holding zero shapes and that was read as a missing pad
ring; the pads were in fact present, correctly placed, and legitimately empty
(the PDK ships no back-end GDS for the pad library, so they are LEF-only black
boxes - ci/signoff.yaml `gds-completeness`). Absence wrongly diagnosed and
absence wrongly missed are the same missing instrument.

WHAT THIS IS NOT
================

It is not asic-flow-gds-census (KLayout, counts cells hierarchically, answers
"did that stage run"), and it is not asic-flow-gds-layer-census (counts shapes
per layer, answers "did that map edit do what it says"). Both MEASURE and
neither JUDGES: they print numbers a human compares. This one carries an
expectation derived from the design and returns an exit status. Where those two
already answer a question, this file defers to them rather than re-deriving it.

THE DERIVATION RULE
===================

An expected value that was typed in by hand is a number that will be right
once. Every assertion this tool makes carries a `source` string naming the file
the value came from, and `derive` reads that file. The sources are:

  die box            floorplan.tcl        `create_floorplan ... -die_size W H`
                                          (that file states it is the single
                                          source of truth, and that Innovus
                                          anchors the die at the origin)
  bond pad counts    place_bondpads.tcl   lengths of the *_pads_outer /
                                          *_pads_inner lists, times the
                                          `create_inst -cell <C>` of the loop
                                          that consumes each list
  corner cells       nanosoc_..._pads.io  (topleft|topright|bottomleft|
                                          bottomright) blocks, cell= attribute
  IO pad slots       nanosoc_..._pads.io  (inst ...) count per side
  layer numbers      <run>/work/tech/gdsout.stream.map   name -> number/datatype
  routing stack      preplace.tcl         `set_db design_top_routing_layer N`
  merged macros      <run>/reports/*_stream.rep   the -merge {...} argument of
                                          the write_stream that made this file
  top cell name      the same .rep        the `Design:` header line

Nothing else is asserted. Where a value could not be derived it is recorded in
`unasserted` with the reason, printed in the report, and DOES NOT affect the
exit status. A census that asserts a wrong number is worse than no census.

TRAPS THIS PARSER HANDLES, DO NOT SIMPLIFY THEM AWAY
====================================================

1. An SREF/AREF element carries no LAYER record. A parser that does not reset
   its current-layer state on one of them tallies the instance under whatever
   layer the previous element had. Measured on a real full-chip stream by
   asic-flow-gds-layer-census, that inflated a top cell from 50 text records to
   2,362,294. The `kind = REF` arm below is the guard.

2. An AREF is not one placement. Its COLROW record gives the array size, and
   the manufactured die contains all of them. Counting an AREF as 1 undercounts
   memory bit cells by three orders of magnitude.

3. Instance counts must be HIERARCHICAL. A pad placed once inside a cell that
   is itself placed 42 times is on the die 42 times. Direct SREF counts are
   also reported, because for a flat Innovus top cell they are the same number
   and a divergence between them is itself informative.

4. Innovus RE-ENCODES records when it merges a macro GDS, so byte or per-
   structure hash comparison against the standalone .gds2 reports 0 of 126
   structures identical on a CORRECT chip (ci/signoff.yaml `rom-gds`). The
   merged-macro assertion here compares per-structure, per-(layer,datatype)
   SHAPE COUNTS, which is invariant under re-encoding and was validated on
   three streams on 2026-08-13.

5. A PATH's XY is its centreline; its true extent is wider by half its WIDTH.
   Bounding boxes here are therefore computed from BOUNDARY and BOX elements
   only, and the die-box assertion reads the DIEAREA layer, which is a
   BOUNDARY. Do not extend the bbox code to PATH without adding the width.

NDA NOTE
========

Layer NUMBERS in the output and in a derived expectations file come from the
foundry stream-out map. Treat a census, and an expectations file, exactly as
you treat the GDS they describe. Expectations are written with layer NAMES
wherever the map supplies one, so a committed expectations file need not carry
foundry numbers - the run's own map resolves them at check time.

EXIT STATUS
===========

    0   every assertion passed
    1   at least one assertion FAILED
    2   the stream could not be measured, or an expectation could not be
        resolved. "We could not check" is never green.

Copyright (C) 2026, SoC Labs (www.soclabs.org)
"""

import argparse
import json
import os
import re
import struct
import sys
import time
from collections import Counter, defaultdict

# ---------------------------------------------------------------------------
# GDSII record types.
# ---------------------------------------------------------------------------
UNITS, ENDLIB, STRNAME, ENDSTR = 0x03, 0x04, 0x06, 0x07
BOUNDARY, PATH, SREF, AREF, TEXT = 0x08, 0x09, 0x0A, 0x0B, 0x0C
LAYER, DATATYPE, XY, ENDEL, SNAME = 0x0D, 0x0E, 0x10, 0x11, 0x12
COLROW, NODE, TEXTTYPE, BOX, BOXTYPE = 0x13, 0x15, 0x16, 0x2D, 0x2E
NODETYPE = 0x2A

GEOM = (BOUNDARY, PATH, BOX, NODE)
BOXY = (BOUNDARY, BOX)          # elements whose XY is the true extent

KIND_GEO, KIND_TXT, KIND_REF = 1, 2, 3


def _real8(b):
    """GDSII 8-byte excess-64 base-16 float."""
    e = b[0]
    sign = -1 if e & 0x80 else 1
    exp = (e & 0x7F) - 64
    return sign * int.from_bytes(b[1:8], "big") * (16.0 ** exp) / (1 << 56)


# ---------------------------------------------------------------------------
# Streaming record reader. Chunked, so a 313 MB stream never lands in memory
# whole and a skipped record body is never copied out of the buffer.
# ---------------------------------------------------------------------------
class RecordReader:
    # NOTE: the buffer is immutable `bytes`, not a bytearray, and a refill
    # REPLACES it rather than resizing it. That is deliberate: the yielded
    # bodies are memoryviews into this buffer, and a bytearray with a live
    # export cannot be resized ("BufferError: Existing exports of data"). A
    # memoryview onto the old bytes object simply stays valid.
    def __init__(self, path, chunk=1 << 22):
        self.fh = open(path, "rb")
        self.chunk = chunk
        self.buf = b""
        self.pos = 0
        self.records = 0

    def _need(self, n):
        if len(self.buf) - self.pos >= n:
            return True
        parts = [self.buf[self.pos:]]
        have = len(parts[0])
        self.pos = 0
        while have < n:
            data = self.fh.read(max(self.chunk, n - have))
            if not data:
                self.buf = b"".join(parts)
                return False
            parts.append(data)
            have += len(data)
        self.buf = b"".join(parts)
        return True

    def __iter__(self):
        while True:
            if not self._need(4):
                return
            buf = self.buf
            p = self.pos
            length = (buf[p] << 8) | buf[p + 1]
            rtype = buf[p + 2]
            if length < 4:
                # A GDSII file is padded to a 2048-byte block with NULs after
                # ENDLIB. That padding parses as length-0 records. Accept it
                # ONLY if what is left really is all zero - a length-0 record
                # in the middle of live data is a corrupt stream, and reading
                # a corrupt stream as a short one would under-count silently.
                self.buf = buf
                rest = buf[p:] + self.fh.read()
                if rest.strip(b"\x00"):
                    raise ValueError(
                        "malformed GDSII: record length %d at byte offset %d, "
                        "and the remainder is not NUL padding"
                        % (length, self.fh.tell() - len(rest)))
                return
            if rtype == ENDLIB:
                self.records += 1
                return
            if not self._need(length):
                raise ValueError("truncated GDSII: record claims %d bytes, "
                                 "file ended" % length)
            p = self.pos
            body = memoryview(self.buf)[p + 4:p + length]
            self.pos = p + length
            self.records += 1
            yield rtype, body

    def close(self):
        self.fh.close()


# ---------------------------------------------------------------------------
# The census itself.
# ---------------------------------------------------------------------------
def census(path, bbox_structs=frozenset(), bbox_all=False):
    """One streaming pass. Returns a plain-dict census.

    bbox_structs / bbox_all control the only expensive part: unpacking XY.
    Structures outside that set are counted but not measured, which keeps a
    full-chip pass to counting work only.
    """
    geo = defaultdict(Counter)     # struct -> Counter[(layer, dtype)]
    txt = defaultdict(Counter)
    place = defaultdict(Counter)   # struct -> Counter[master] (array-expanded)
    srefs = Counter()              # struct -> literal SREF/AREF element count
    bbox = {}                      # struct -> [x1, y1, x2, y2] in dbu
    laybox = defaultdict(dict)     # struct -> (l, d) -> [x1, y1, x2, y2]
    order = []
    dbu_per_um = None
    user_unit = None

    sname = None                   # structure being read
    kind = None                    # element kind
    lay = dt = None
    master = None
    colrow = 1
    xy = None
    want_xy = False

    rd = RecordReader(path)
    t0 = time.time()
    try:
        for rtype, body in rd:
            if rtype == LAYER:
                lay = struct.unpack(">h", body[:2])[0]
            elif rtype == XY:
                if want_xy:
                    n = len(body) // 4
                    xy = struct.unpack(">%di" % n, body)
            elif rtype in (DATATYPE, BOXTYPE, TEXTTYPE, NODETYPE):
                dt = struct.unpack(">h", body[:2])[0]
            elif rtype == ENDEL:
                if sname is not None:
                    if kind == KIND_GEO and lay is not None:
                        geo[sname][(lay, dt)] += 1
                        if xy is not None:
                            _grow(bbox, sname, xy)
                            _grow(laybox[sname], (lay, dt), xy)
                    elif kind == KIND_TXT and lay is not None:
                        txt[sname][(lay, dt)] += 1
                    elif kind == KIND_REF and master is not None:
                        # TRAP 2: an AREF is COLROW placements, not one.
                        place[sname][master] += colrow
                        srefs[sname] += 1
                kind = None
                lay = dt = None
                master = None
                xy = None
                want_xy = False
                colrow = 1
            elif rtype in GEOM:
                # TRAP 1: reset layer state on EVERY element start.
                kind, lay, dt, xy = KIND_GEO, None, None, None
                # TRAP 5: only BOUNDARY/BOX XY is the true extent.
                want_xy = (rtype in BOXY) and (bbox_all or sname in bbox_structs)
            elif rtype == TEXT:
                kind, lay, dt, want_xy = KIND_TXT, None, None, False
            elif rtype in (SREF, AREF):
                kind, lay, dt, want_xy = KIND_REF, None, None, False
                master = None
                colrow = 1
            elif rtype == SNAME:
                master = bytes(body).rstrip(b"\x00").decode("ascii", "replace")
            elif rtype == COLROW:
                c, r = struct.unpack(">hh", body[:4])
                colrow = max(1, c) * max(1, r)
            elif rtype == STRNAME:
                sname = bytes(body).rstrip(b"\x00").decode("ascii", "replace")
                order.append(sname)
                geo[sname], txt[sname], place[sname]      # materialise
            elif rtype == ENDSTR:
                sname = None
            elif rtype == UNITS:
                user_unit = _real8(bytes(body[0:8]))
                metres = _real8(bytes(body[8:16]))
                dbu_per_um = 1e-6 / metres if metres else None
    finally:
        rd.close()

    # Roots: structures nobody places.
    referenced = set()
    for m in place.values():
        referenced.update(m)
    roots = [s for s in order if s not in referenced]

    return {
        "file": os.path.abspath(path),
        "bytes": os.path.getsize(path),
        "records": rd.records,
        "seconds": round(time.time() - t0, 1),
        "dbu_per_um": dbu_per_um,
        "user_unit": user_unit,
        "order": order,
        "roots": roots,
        "geo": {s: dict(geo[s]) for s in order},
        "txt": {s: dict(txt[s]) for s in order},
        "place": {s: dict(place[s]) for s in order},
        "srefs": dict(srefs),
        "bbox": bbox,
        "laybox": {s: dict(v) for s, v in laybox.items()},
    }


def _grow(store, key, xy):
    xs = xy[0::2]
    ys = xy[1::2]
    b = store.get(key)
    if b is None:
        store[key] = [min(xs), min(ys), max(xs), max(ys)]
    else:
        b[0] = min(b[0], min(xs)); b[1] = min(b[1], min(ys))
        b[2] = max(b[2], max(xs)); b[3] = max(b[3], max(ys))


def hier_counts(c, root):
    """Placements of every master under `root`, array-expanded, memoised.

    A structure placed inside a structure placed 42 times is on the die 42
    times, and that is the number a pad-ring assertion is about.
    """
    memo = {}
    stack_guard = set()

    def walk(name):
        if name in memo:
            return memo[name]
        if name in stack_guard:      # cyclic hierarchy is not legal GDSII
            return Counter()
        stack_guard.add(name)
        total = Counter()
        for master, n in c["place"].get(name, {}).items():
            total[master] += n
            for sub, m in walk(master).items():
                total[sub] += n * m
        stack_guard.discard(name)
        memo[name] = total
        return total

    sys.setrecursionlimit(max(10000, sys.getrecursionlimit()))
    return walk(root)


def flat_totals(c):
    g, t = Counter(), Counter()
    for v in c["geo"].values():
        g.update(v)
    for v in c["txt"].values():
        t.update(v)
    return g, t


# ---------------------------------------------------------------------------
# JSON round-tripping. (layer, datatype) tuples become "L/D" strings.
# ---------------------------------------------------------------------------
def _enc(c):
    out = dict(c)
    out["geo"] = {s: {"%d/%d" % k: v for k, v in d.items()} for s, d in c["geo"].items()}
    out["txt"] = {s: {"%d/%d" % k: v for k, v in d.items()} for s, d in c["txt"].items()}
    out["laybox"] = {s: {"%d/%d" % k: v for k, v in d.items()}
                     for s, d in c["laybox"].items()}
    return out


def _dec(d):
    # `check --json` wraps the census next to its verdicts; `census --json`
    # writes it bare. Accept either, so a diff can be taken between a gate run
    # and a plain measurement without anyone having to remember which is which.
    if "census" in d and "geo" not in d:
        d = d["census"]

    def un(k):
        a, b = k.split("/")
        return (int(a), int(b))
    d = dict(d)
    d["geo"] = {s: {un(k): v for k, v in x.items()} for s, x in d["geo"].items()}
    d["txt"] = {s: {un(k): v for k, v in x.items()} for s, x in d["txt"].items()}
    d["laybox"] = {s: {un(k): v for k, v in x.items()} for s, x in d.get("laybox", {}).items()}
    return d


# ---------------------------------------------------------------------------
# DERIVE - build an expectations file out of the design, never out of a memory.
# ---------------------------------------------------------------------------
def parse_stream_map(path):
    """gdsout.stream.map -> {(NAME, OBJTYPES): (layer, datatype)} plus an index
    by layer name. Comment lines and the trailing PDK provenance are skipped."""
    rows = []
    with open(path) as fh:
        for line in fh:
            line = line.split("#", 1)[0].strip()
            if not line:
                continue
            f = line.split()
            if len(f) < 4:
                continue
            try:
                lay, dt = int(f[-2]), int(f[-1])
            except ValueError:
                continue
            rows.append({"name": f[0], "objtypes": f[1], "layer": lay, "datatype": dt})
    return rows


def map_lookup(rows, name, objtype):
    for r in rows:
        if r["name"] == name and objtype in r["objtypes"].split(","):
            return r["layer"], r["datatype"]
    return None


def parse_die_size(floorplan_tcl):
    """floorplan.tcl states that -die_size is the single source of truth and
    that Innovus anchors the die at the origin, so the box is (0,0)-(w,h).
    ASIC/genus-innovus/drc_project.mk already sed's this same line for the
    Calibre ChipWindow; matching the same anchored form keeps them one fact."""
    src = open(floorplan_tcl).read()
    m = re.search(r"^create_floorplan\b[^\n]*?-die_size\s+([0-9.]+)\s+([0-9.]+)",
                  src, re.M)
    if not m:
        return None
    return [0.0, 0.0, float(m.group(1)), float(m.group(2))]


def parse_bondpads(tcl):
    """place_bondpads.tcl -> {cell: (count, [list names])}.

    Each `set <x>_pads_<outer|inner> [list ...]` is consumed by exactly one
    `foreach pads $<x>_pads_<...> { create_inst -cell <CELL> ... }`. Read both
    and multiply; do not assume which cell goes with which ring."""
    src = open(tcl).read()
    lists = {}
    for m in re.finditer(r"set\s+(\w+)\s+\[list\s*\\?\s*(.*?)\]", src, re.S):
        names = [t for t in m.group(2).split() if t not in ("\\",)]
        lists[m.group(1)] = names
    used = defaultdict(list)
    for m in re.finditer(r"foreach\s+\w+\s+\$(\w+)\s*\{(.*?)\n\}", src, re.S):
        var, blk = m.group(1), m.group(2)
        cm = re.search(r"create_inst\s+-cell\s+(\S+)", blk)
        if not cm or var not in lists:
            continue
        used[cm.group(1)].extend(lists[var])
    return {cell: sorted(names) for cell, names in used.items()}


def parse_io_file(io):
    """The .io placement file -> corner cells and per-side pad slot counts."""
    src = open(io).read()
    corners = Counter(re.findall(r"cell=(\S+?)\s*\)", src))
    sides = {}
    for side in ("top", "bottom", "left", "right",
                 "topleft", "topright", "bottomleft", "bottomright"):
        m = re.search(r"\(\s*" + side + r"\s*\n(.*?)\n\s*\)", src, re.S)
        if m:
            sides[side] = len(re.findall(r"\(\s*inst\s", m.group(1)))
    return corners, sides


def parse_stream_rep(rep):
    """The write_stream -report_file header: design name, -merge list, -unit.

    This is the report of the very write_stream that produced the file under
    test, so the merge list is the run's own, not a copy of config.tcl that may
    have moved on."""
    src = open(rep).read()
    out = {}
    m = re.search(r"^#\s+Design:\s+(\S+)", src, re.M)
    if m:
        out["design"] = m.group(1)
    m = re.search(r"-merge\s*\{([^}]*)\}", src)
    if m:
        out["merge"] = m.group(1).split()
    m = re.search(r"-map_file\s+(\S+)", src)
    if m:
        out["map_file"] = m.group(1)
    m = re.search(r"-unit\s+(\d+)", src)
    if m:
        out["unit"] = int(m.group(1))
    out["lefobs_streamed"] = None    # filled in by the caller from the map
    return out


def parse_top_routing_layer(preplace_tcl):
    src = open(preplace_tcl).read()
    m = re.search(r"^\s*set_db\s+design_top_routing_layer\s+(\d+)", src, re.M)
    return int(m.group(1)) if m else None


def derive(args):
    run = args.run_dir
    scripts = args.scripts_dir
    exp = {"meta": {}, "top": {}, "structures": [], "layers": [],
           "structure_geometry": [], "merged": [], "unasserted": []}
    unassert = exp["unasserted"].append

    # --- the run's own stream report -------------------------------------
    reps = [os.path.join(run, "reports", f)
            for f in sorted(os.listdir(os.path.join(run, "reports")))
            if f.endswith("_stream.rep")] if os.path.isdir(os.path.join(run, "reports")) else []
    if args.stream_rep:
        reps = [args.stream_rep]
    if not reps:
        sys.exit("derive: no write_stream report under %s/reports. Without it "
                 "the merge list and the top cell name are not derivable; "
                 "point --stream-rep at the report of the run that made the "
                 "stream under test." % run)
    rep = parse_stream_rep(reps[-1])
    exp["meta"]["stream_rep"] = reps[-1]

    # --- stream-out map: layer NAMES -> numbers ---------------------------
    mapfile = args.stream_map or rep.get("map_file")
    if not mapfile or not os.path.exists(mapfile):
        sys.exit("derive: the stream-out map (%s) is not readable. Layer "
                 "numbers are only derivable from it." % mapfile)
    rows = parse_stream_map(mapfile)
    exp["meta"]["stream_map"] = mapfile
    objtypes = set()
    for r in rows:
        objtypes.update(r["objtypes"].split(","))
    lefobs = "LEFOBS" in objtypes
    exp["meta"]["lefobs_streamed"] = lefobs

    # --- top cell + die box ----------------------------------------------
    die = parse_die_size(os.path.join(scripts, "floorplan.tcl"))
    diearea = map_lookup(rows, "DIEAREA", "ALL")
    exp["top"] = {
        "name": rep.get("design"),
        "must_be_only_root": True,
        "source": "%s (Design: header)" % os.path.basename(reps[-1]),
    }
    if die and diearea:
        exp["top"]["die_box_um"] = die
        exp["top"]["die_box_layer"] = list(diearea)
        exp["top"]["die_box_tol_um"] = args.die_tol
        exp["top"]["die_box_source"] = ("floorplan.tcl create_floorplan -die_size, "
                                        "anchored at the origin; DIEAREA layer "
                                        "from the run's stream map")
    else:
        unassert("die box: -die_size not found in floorplan.tcl"
                 if not die else "die box: the stream map has no DIEAREA ALL row")

    # --- bond pads, from place_bondpads.tcl -------------------------------
    bp = parse_bondpads(os.path.join(scripts, "place_bondpads.tcl"))
    for cell, names in sorted(bp.items()):
        exp["structures"].append({
            "name": cell,
            "min_instances": len(names),
            "max_instances": len(names),
            "source": "place_bondpads.tcl: %d names across the lists its "
                      "create_inst -cell %s loops consume" % (len(names), cell),
        })

    # --- corner cells, from the .io file ----------------------------------
    ios = [f for f in os.listdir(scripts) if f.endswith(".io")]
    if len(ios) == 1:
        corners, sides = parse_io_file(os.path.join(scripts, ios[0]))
        for cell, n in sorted(corners.items()):
            exp["structures"].append({
                "name": cell, "min_instances": n, "max_instances": n,
                "source": "%s: %d (inst ... cell=%s) in the corner blocks"
                          % (ios[0], n, cell)})
        exp["meta"]["io_sides"] = sides
        pads = sum(v for k, v in sides.items() if k in ("top", "bottom", "left", "right"))
        bonded = sum(len(v) for v in bp.values())
        exp["meta"]["io_pad_slots"] = pads
        if pads != bonded:
            unassert("IO pad slots in %s (%d) != bond pads placed by "
                     "place_bondpads.tcl (%d). One pad per slot is the design "
                     "intent; this mismatch is reported, not asserted, because "
                     "which of the two files is wrong is not derivable here."
                     % (ios[0], pads, bonded))
    else:
        unassert("corner cells: expected exactly one .io in %s, found %d"
                 % (scripts, len(ios)))
    unassert("IO DRIVER cells: the .io file names INSTANCES (uPAD_*), and a GDS "
             "SREF names the MASTER, so a per-driver count is not derivable "
             "from the placement file. It IS derivable from the pnr netlist; "
             "not wired here.")

    # --- layers that a routed design cannot legally leave empty -----------
    top_layer = parse_top_routing_layer(os.path.join(scripts, "preplace.tcl"))
    if top_layer:
        for i in range(1, top_layer + 1):
            hit = map_lookup(rows, "M%d" % i, "NET")
            if hit:
                exp["layers"].append({
                    "layer_name": "M%d/NET" % i, "layer": hit[0], "datatype": hit[1],
                    "min_shapes": 1,
                    "source": "preplace.tcl design_top_routing_layer=%d, so the "
                              "router uses M1..M%d; an empty allowed metal layer "
                              "in a routed design is a dropped map row"
                              % (top_layer, top_layer)})
        for i in range(1, top_layer):
            hit = map_lookup(rows, "VIA%d" % i, "VIA")
            if hit:
                exp["layers"].append({
                    "layer_name": "VIA%d" % i, "layer": hit[0], "datatype": hit[1],
                    "min_shapes": 1,
                    "source": "preplace.tcl design_top_routing_layer=%d implies "
                              "VIA1..VIA%d are used" % (top_layer, top_layer - 1)})
    else:
        unassert("routing layers: design_top_routing_layer not found in "
                 "preplace.tcl, so the used stack is not derivable")
    unassert("M9 / AP / RV: above design_top_routing_layer. They carry pad-ring "
             "and PG geometry whose expected count is a floorplan result, not a "
             "derivable number. Reported by the census, not asserted.")
    unassert("FILL datatypes: EVR_METAL_FILL defaults to 0 (4b_pnr_route_eval.tcl), "
             "so an unfilled stream is correct and a fill floor would be a false "
             "alarm. Assert this only once fill is switched on.")
    unassert("filler / endcap / antenna-diode counts: a placement result, not a "
             "derivable expectation. asic-flow-gds-census already reports them.")

    # --- bond pad geometry, but ONLY if the map streams it ----------------
    for cell in sorted(bp):
        if lefobs:
            need = []
            for nm in ("M8", "M9", "AP"):
                hit = map_lookup(rows, nm, "LEFOBS")
                if hit:
                    need.append({"layer_name": nm, "layer": hit[0],
                                 "datatype": hit[1], "min_shapes": 1})
            if need:
                exp["structure_geometry"].append({
                    "structure": cell, "layers": need,
                    "source": "the stream map has LEFOBS rows, and a bond pad "
                              "declares its pad metal and AP opening as OBS "
                              "because nothing routes to it (gdsmap_derive.py). "
                              "With OBS streamed, an empty pad master means the "
                              "opening was dropped."})
        else:
            unassert("%s geometry: the stream map has NO LEFOBS row, so pad OBS "
                     "is not streamed at all and an EMPTY pad master is the "
                     "correct result for this map. Presence of the pad is still "
                     "asserted (instance count above); its shapes are not."
                     % cell)

    # --- merged macros ----------------------------------------------------
    for g in rep.get("merge", []):
        exp["merged"].append({
            "gds": g, "mode": "per_structure_shape_counts",
            "source": "the -merge list of the write_stream that produced the "
                      "stream under test (%s)" % os.path.basename(reps[-1])})
    if not rep.get("merge"):
        unassert("merged macros: the stream report carries no -merge argument")

    exp["meta"]["derived_at"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    exp["meta"]["scripts_dir"] = scripts
    exp["meta"]["run_dir"] = run
    with open(args.out, "w") as fh:
        json.dump(exp, fh, indent=2)
    print("expectations -> %s" % args.out)
    print("  top cell            %s" % exp["top"].get("name"))
    print("  die box             %s um" % exp["top"].get("die_box_um"))
    print("  structures asserted %d" % len(exp["structures"]))
    print("  layer floors        %d" % len(exp["layers"]))
    print("  merged macros       %d" % len(exp["merged"]))
    print("  UNASSERTED          %d" % len(exp["unasserted"]))
    return 0


# ---------------------------------------------------------------------------
# CHECK
# ---------------------------------------------------------------------------
class Report:
    def __init__(self):
        self.rows = []
        self.fails = 0
        self.errors = 0

    def add(self, verdict, section, text):
        self.rows.append((verdict, section, text))
        if verdict == "FAIL":
            self.fails += 1
        elif verdict == "ERROR":
            self.errors += 1

    def emit(self, unasserted):
        sec = None
        for verdict, section, text in self.rows:
            if section != sec:
                print("\n%s" % section)
                sec = section
            print("  %-5s %s" % (verdict, text))
        if unasserted:
            print("\nUNASSERTED (reported, does not affect exit status)")
            for u in unasserted:
                print("  ----  %s" % u)
        print("\n%s" % ("-" * 72))
        n = len(self.rows)
        print("%d assertions, %d failed, %d unmeasurable, %d unasserted"
              % (n, self.fails, self.errors, len(unasserted)))


def check(args):
    exp = json.load(open(args.expect))
    top = exp["top"].get("name")
    want_bbox = {top} | {s["structure"] for s in exp.get("structure_geometry", [])}

    try:
        c = census(args.gds, bbox_structs=want_bbox)
    except (OSError, ValueError) as e:
        print("ERROR  the stream could not be measured: %s" % e)
        return 2

    r = Report()
    dbu = c["dbu_per_um"] or 1000.0
    g_tot, t_tot = flat_totals(c)

    print("GDS STRUCTURAL CENSUS")
    print("  stream       %s" % c["file"])
    print("  %s bytes, %s records, %s structures, %.0f dbu/um, %.1f s"
          % ("{:,}".format(c["bytes"]), "{:,}".format(c["records"]),
             "{:,}".format(len(c["order"])), dbu, c["seconds"]))
    print("  geometry     %s shapes on %d layer/datatype pairs"
          % ("{:,}".format(sum(g_tot.values())), len(g_tot)))
    print("  text         %s labels on %d layer/datatype pairs"
          % ("{:,}".format(sum(t_tot.values())), len(t_tot)))
    print("  expectations %s" % os.path.abspath(args.expect))

    # ---- top cell -------------------------------------------------------
    S = "TOP CELL"
    if top is None:
        r.add("ERROR", S, "the expectations file names no top cell")
    elif top not in c["geo"]:
        r.add("FAIL", S, "structure '%s' is ABSENT from the stream" % top)
    else:
        r.add("PASS", S, "structure '%s' present" % top)
        if exp["top"].get("must_be_only_root"):
            if c["roots"] == [top]:
                r.add("PASS", S, "'%s' is the only root structure" % top)
            else:
                r.add("FAIL", S, "expected '%s' to be the only root; roots are %s"
                      % (top, c["roots"][:8] + (["..."] if len(c["roots"]) > 8 else [])))

    hier = hier_counts(c, top) if top in c["geo"] else Counter()

    if "die_box_um" in exp["top"] and top in c["geo"]:
        lay = tuple(exp["top"]["die_box_layer"])
        tol = exp["top"].get("die_box_tol_um", 0.01)
        want = exp["top"]["die_box_um"]
        box = c["laybox"].get(top, {}).get(lay)
        if box is None:
            r.add("FAIL", S, "NO geometry on the DIEAREA layer %d/%d in '%s' - "
                             "the die outline is absent from the stream"
                  % (lay[0], lay[1], top))
        else:
            got = [v / dbu for v in box]
            if max(abs(a - b) for a, b in zip(got, want)) <= tol:
                r.add("PASS", S, "die box %s um on DIEAREA %d/%d"
                      % (_fmtbox(got), lay[0], lay[1]))
            else:
                r.add("FAIL", S, "die box is %s um, expected %s um (tol %g)"
                      % (_fmtbox(got), _fmtbox(want), tol))
        own = c["bbox"].get(top)
        if own:
            o = [v / dbu for v in own]
            outside = (o[0] < want[0] - tol or o[1] < want[1] - tol
                       or o[2] > want[2] + tol or o[3] > want[3] + tol)
            r.add("FAIL" if outside else "PASS", S,
                  "top-cell own geometry %s um %s the die box"
                  % (_fmtbox(o), "REACHES OUTSIDE" if outside else "is inside"))

    # ---- structure presence and instance count --------------------------
    S = "STRUCTURE PRESENCE AND INSTANCE COUNT"
    for s in exp["structures"]:
        nm = s["name"]
        if nm not in c["geo"]:
            r.add("FAIL", S, "%-14s ABSENT - no such structure in the stream "
                             "(expected %s instances)  [%s]"
                  % (nm, s.get("min_instances"), s["source"]))
            continue
        n = hier.get(nm, 0)
        lo, hi = s.get("min_instances"), s.get("max_instances")
        ok = (lo is None or n >= lo) and (hi is None or n <= hi)
        direct = sum(v.get(nm, 0) for v in c["place"].values())
        note = "" if direct == n else "  (direct placements %d)" % direct
        shapes = sum(c["geo"][nm].values())
        r.add("PASS" if ok else "FAIL", S,
              "%-14s present, instanced %-5d (expected %s..%s), %d own shapes%s"
              % (nm, n, lo, hi, shapes, note))
        if not ok:
            r.rows[-1] = ("FAIL", S, r.rows[-1][2] + "\n           [%s]" % s["source"])

    # ---- layer floors ---------------------------------------------------
    S = "LAYER SHAPE FLOORS"
    for l in exp["layers"]:
        key = (l["layer"], l["datatype"])
        n = g_tot.get(key, 0)
        ok = n >= l.get("min_shapes", 1)
        r.add("PASS" if ok else "FAIL", S,
              "%-10s (%d/%d) %s shapes, floor %d"
              % (l.get("layer_name", ""), key[0], key[1],
                 "{:,}".format(n), l.get("min_shapes", 1)))
        if not ok:
            r.rows[-1] = ("FAIL", S, r.rows[-1][2] + "\n           [%s]" % l["source"])

    # ---- geometry inside named structures -------------------------------
    S = "GEOMETRY INSIDE NAMED STRUCTURES"
    for sg in exp.get("structure_geometry", []):
        nm = sg["structure"]
        if nm not in c["geo"]:
            r.add("FAIL", S, "%s ABSENT" % nm)
            continue
        for l in sg["layers"]:
            key = (l["layer"], l["datatype"])
            n = c["geo"][nm].get(key, 0)
            ok = n >= l.get("min_shapes", 1)
            r.add("PASS" if ok else "FAIL", S,
                  "%-14s %-4s (%d/%d) %d shapes, floor %d"
                  % (nm, l.get("layer_name", ""), key[0], key[1], n,
                     l.get("min_shapes", 1)))
            if not ok:
                r.rows[-1] = ("FAIL", S, r.rows[-1][2] + "\n           [%s]" % sg["source"])

    # ---- merged macros --------------------------------------------------
    S = "MERGED MACRO FIDELITY"
    for m in exp.get("merged", []):
        src = m["gds"]
        if not os.path.exists(src):
            r.add("ERROR", S, "%s: the merge source is not readable, so the "
                              "merge cannot be verified" % os.path.basename(src))
            continue
        try:
            ref = census(src)
        except (OSError, ValueError) as e:
            r.add("ERROR", S, "%s: %s" % (os.path.basename(src), e))
            continue
        missing, empty, differ, hierloss = [], [], [], []
        want_lay, got_lay = Counter(), Counter()
        for s in ref["order"]:
            if s not in c["geo"]:
                missing.append(s)
                want_lay.update(ref["geo"][s])
                continue
            want, got = ref["geo"][s], c["geo"][s]
            want_lay.update(want)
            got_lay.update({k: v for k, v in got.items()})
            if sum(want.values()) and not sum(got.values()):
                empty.append(s)
            elif want != got:
                differ.append((s, sum(want.values()), sum(got.values())))
            if ref["place"].get(s) != c["place"].get(s):
                hierloss.append(s)
        tag = os.path.basename(src)
        n = len(ref["order"])
        if missing or empty:
            r.add("FAIL", S, "%-24s %d/%d structures present, %d MISSING, "
                             "%d present-but-EMPTY%s"
                  % (tag, n - len(missing), n, len(missing), len(empty),
                     ("  e.g. " + ", ".join((missing or empty)[:3]))))
        elif differ:
            r.add("FAIL", S, "%-24s all %d structures present but %d have "
                             "different shape counts  e.g. %s"
                  % (tag, n, len(differ),
                     ", ".join("%s %d->%d" % d for d in differ[:3])))
        else:
            r.add("PASS", S, "%-24s all %d structures present, every "
                             "per-structure per-layer shape count identical"
                  % (tag, n))
        if hierloss:
            r.add("FAIL", S, "%-24s %d structures lost or changed their internal "
                             "placements  e.g. %s"
                  % (tag, len(hierloss), ", ".join(hierloss[:3])))

        # THE M1-ONLY-SHELL TEST. A real macro carries base layers (diffusion,
        # poly, contact) that no routing map ever emits; a LEF-derived shell
        # carries metal and nothing else. Compare the macro's own layer set in
        # the source against the SAME structures' layer set in the stream.
        lost = sorted(k for k in want_lay if k not in got_lay)
        if lost:
            r.add("FAIL", S, "%-24s %d layer/datatype pairs present in the "
                             "source macro are ABSENT from its structures in "
                             "the stream: %s%s"
                  % (tag, len(lost), lost[:6], " ..." if len(lost) > 6 else ""))
        else:
            r.add("PASS", S, "%-24s all %d source layer/datatype pairs survive "
                             "the merge (%s shapes) - real geometry, not an "
                             "M1-only shell"
                  % (tag, len(want_lay), "{:,}".format(sum(want_lay.values()))))

    r.emit(exp.get("unasserted", []))

    if args.json:
        with open(args.json, "w") as fh:
            json.dump({"census": _enc(c),
                       "hier": dict(hier),
                       "verdicts": [{"verdict": v, "section": s, "text": t}
                                    for v, s, t in r.rows]}, fh)
        print("census -> %s" % args.json)

    if r.errors:
        print("\nVERDICT: UNMEASURABLE - %d assertion(s) could not be evaluated. "
              "Not green." % r.errors)
        return 2
    if r.fails:
        print("\nVERDICT: FAIL - %d assertion(s) failed." % r.fails)
        return 1
    print("\nVERDICT: PASS")
    return 0


def _fmtbox(b):
    return "(%.3f,%.3f)-(%.3f,%.3f)" % tuple(b)


# ---------------------------------------------------------------------------
# CENSUS / DIFF
# ---------------------------------------------------------------------------
def do_census(args):
    try:
        c = census(args.gds, bbox_all=args.bbox_all)
    except (OSError, ValueError) as e:
        print("ERROR  %s" % e)
        return 2
    g, t = flat_totals(c)
    print("# %s" % c["file"])
    print("# bytes=%s records=%s structures=%s roots=%s dbu/um=%s seconds=%s"
          % ("{:,}".format(c["bytes"]), "{:,}".format(c["records"]),
             "{:,}".format(len(c["order"])), c["roots"][:4],
             c["dbu_per_um"], c["seconds"]))
    print("# geometry=%s text=%s"
          % ("{:,}".format(sum(g.values())), "{:,}".format(sum(t.values()))))
    if c["roots"]:
        h = hier_counts(c, c["roots"][0])
        print("\n### TOP 25 MASTERS BY HIERARCHICAL INSTANCE COUNT under %s"
              % c["roots"][0])
        for name, n in h.most_common(25):
            print("  %-28s %12s   own shapes %s"
                  % (name, "{:,}".format(n),
                     "{:,}".format(sum(c["geo"].get(name, {}).values()))))
        print("\n### EMPTY STRUCTURES THAT ARE INSTANCED (black boxes)")
        empties = [(nm, n) for nm, n in h.most_common()
                   if not sum(c["geo"].get(nm, {}).values())
                   and not c["place"].get(nm)]
        print("  %d of %d instanced masters carry no geometry and place nothing"
              % (len(empties), len(h)))
        for nm, n in empties[:15]:
            print("    %-28s x%s" % (nm, "{:,}".format(n)))
    print("\n### GEOMETRY BY LAYER/DATATYPE")
    for k, v in sorted(g.items()):
        print("  %5d/%-5d %12s" % (k[0], k[1], "{:,}".format(v)))
    print("\n### TEXT BY LAYER/DATATYPE")
    for k, v in sorted(t.items()):
        print("  %5d/%-5d %12s" % (k[0], k[1], "{:,}".format(v)))
    if args.json:
        json.dump(_enc(c), open(args.json, "w"))
        print("\n# -> %s" % args.json)
    return 0


def do_diff(args):
    a = _dec(json.load(open(args.a)))
    b = _dec(json.load(open(args.b)))
    ga, _ = flat_totals(a)
    gb, _ = flat_totals(b)
    print("A  %s" % a["file"])
    print("B  %s" % b["file"])
    print("\n### STRUCTURES")
    sa, sb = set(a["order"]), set(b["order"])
    print("  A=%d  B=%d  common=%d  A-only=%d  B-only=%d"
          % (len(sa), len(sb), len(sa & sb), len(sa - sb), len(sb - sa)))
    for tag, s in (("A-only", sa - sb), ("B-only", sb - sa)):
        if s:
            print("  %s: %s%s" % (tag, sorted(s)[:12],
                                  " ..." if len(s) > 12 else ""))
    print("\n### LAYER/DATATYPE PAIRS (shape counts)")
    keys = sorted(set(ga) | set(gb))
    for k in keys:
        x, y = ga.get(k, 0), gb.get(k, 0)
        if x == y:
            continue
        flag = "  <-- ONLY IN A" if not y else ("  <-- ONLY IN B" if not x else "")
        print("  %5d/%-5d  A=%12s  B=%12s  delta=%+d%s"
              % (k[0], k[1], "{:,}".format(x), "{:,}".format(y), y - x, flag))
    same = [k for k in keys if ga.get(k, 0) == gb.get(k, 0)]
    print("  (%d of %d layer/datatype pairs identical)" % (len(same), len(keys)))
    print("\n### PER-STRUCTURE SHAPE-COUNT DIFFERENCES (common structures)")
    diffs = []
    for s in sorted(sa & sb):
        x, y = sum(a["geo"][s].values()), sum(b["geo"][s].values())
        if x != y:
            diffs.append((s, x, y))
    print("  %d of %d common structures differ" % (len(diffs), len(sa & sb)))
    for s, x, y in sorted(diffs, key=lambda d: -abs(d[2] - d[1]))[:25]:
        print("    %-30s A=%10s  B=%10s  delta=%+d"
              % (s, "{:,}".format(x), "{:,}".format(y), y - x))
    ra = a["roots"][0] if a["roots"] else None
    rb = b["roots"][0] if b["roots"] else None
    if ra and rb:
        ha, hb = hier_counts(a, ra), hier_counts(b, rb)
        print("\n### HIERARCHICAL INSTANCE-COUNT DIFFERENCES")
        d = [(m, ha.get(m, 0), hb.get(m, 0))
             for m in sorted(set(ha) | set(hb)) if ha.get(m, 0) != hb.get(m, 0)]
        print("  %d of %d masters differ" % (len(d), len(set(ha) | set(hb))))
        for m, x, y in sorted(d, key=lambda t: -abs(t[2] - t[1]))[:25]:
            print("    %-30s A=%9s  B=%9s  delta=%+d"
                  % (m, "{:,}".format(x), "{:,}".format(y), y - x))
    return 0


# ---------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)

    d = sub.add_parser("derive", help="write an expectations file from the design")
    d.add_argument("--run-dir", required=True,
                   help="the build directory whose stream is under test")
    d.add_argument("--scripts-dir", required=True,
                   help="ASIC/genus-innovus/scripts")
    d.add_argument("--stream-rep", help="override the write_stream report")
    d.add_argument("--stream-map", help="override the stream-out map")
    d.add_argument("--die-tol", type=float, default=0.01, help="um")
    d.add_argument("--out", required=True)
    d.set_defaults(fn=derive)

    c = sub.add_parser("census", help="measure a stream, judge nothing")
    c.add_argument("--gds", required=True)
    c.add_argument("--json")
    c.add_argument("--bbox-all", action="store_true",
                   help="measure a bbox for every structure (slower)")
    c.set_defaults(fn=do_census)

    k = sub.add_parser("check", help="measure a stream and judge it")
    k.add_argument("--gds", required=True)
    k.add_argument("--expect", required=True)
    k.add_argument("--json")
    k.set_defaults(fn=check)

    f = sub.add_parser("diff", help="structurally compare two census JSONs")
    f.add_argument("--a", required=True)
    f.add_argument("--b", required=True)
    f.set_defaults(fn=do_diff)

    a = ap.parse_args()
    sys.exit(a.fn(a))


if __name__ == "__main__":
    main()
