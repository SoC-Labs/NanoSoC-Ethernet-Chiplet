#!/usr/bin/env python3
"""fp_guard.py - catch floorplan-adjustment damage from the floorplan text alone.

WHAT THIS IS FOR
================
Moving a macro in ASIC/genus-innovus/scripts/floorplan.tcl can create three
defects that this flow currently only discovers after a full place-and-route
plus signoff - hours later, and in two of the three cases only via a Voltus
solve or by reading `check_connectivity` among hundreds of informational lines:

  FP-SHORT     a top-level M5 PG stripe landing inside another region's stripe
               of the OPPOSITE net -> a rail-to-rail VDD/VSS short.
  FP-CORRIDOR  a macro halo stopping one or two standard-cell rows short of the
               core boundary or of the next halo -> a walled-in strip that
               admits cells but cannot be legalised (IMPSP-2021 / IMPSP-2040),
               non-deterministically, depending on where the netlist wants a
               repeater.
  FP-ISLAND    a narrow `split_row` row island with no vertical supply stripe
               crossing it -> `route_special -core_pin_target
               first_after_row_end` has nothing in the row to tie to and every
               cell on the island is left with no metal path to a rail.

This script computes all three from ARITHMETIC over the floorplan and power-plan
definitions plus the macro LEF SIZE records. It runs in well under a second, it
takes NO EDA licence and it needs no database - so it can be run by whoever is
editing the coordinate, before any tool starts.

It is NOT a substitute for the in-session confirmation. `checks/check_fp_pg.tcl`
runs against the real post-power-plan database at the `post_powerplan` hook and
measures the same three things off the actual geometry. Use this one to decide a
coordinate; use that one to gate the run.

HOW FAR THE ARITHMETIC WAS PROVED
=================================
Against the two databases on disk (ASIC/eth-chiplet/build/{full-20260814,fp1505}):

  * the reconstructed post-`split_row` row structure is EXACT - 2223 rows and
    48 distinct x-segments, zero differences against the `DefRow` records
    Innovus wrote into `work/..._fplan/..fp.gz`;
  * the predicted rail-to-rail shorts for the 1506.12 floorplan are the four
    that `check_drc` reports on the shipping stream, to the coordinate:
    (844.500, 1546.600)-(912.900, 1546.620) and the same at y 1561.600,
    1576.600, 1591.600, each 0.020 um tall;
  * the same computation on the 1505.60 floorplan predicts none, which is what
    that build measures.

WHY THE RULE RECORDED IN floorplan.tcl IS NOT ENOUGH ON ITS OWN
===============================================================
floorplan.tcl records `short <=> (1538.60 - y) mod P in (0.5, 2.5)`. That phase
condition is NECESSARY, not sufficient: `way1_w2` sits at D mod P = 2.25 - inside
the window - against `chip_imem_rf16k` and does not short, because the two
ladders share neither a y range nor an x range. A detector built on the scalar
alone fires on pairs that cannot meet. This script tests the phase AND the two
extents, which is what makes a clean result mean something.

MECHANISM, so the numbers below can be argued with
==================================================
`power_plan.tcl` calls `split_row -selected` over the placed macros and then
`add_stripes` for M5, which RE-ANCHORS PER REGION. Each region's ladder runs at

    VDD  [a + F + kP,        a + F + kP + W      ]
    VSS  [a + F + kP + W + S, a + F + kP + 2W + S]

with `a` the region anchor - measured to be the macro's own bottom edge - and
F/W/S/P read out of the M5 `add_stripes` call. A horizontal M5 stripe is then
extended in x (`-extend_to_closest_target {ring stripe}`) until it covers the
nearest SAME-NET vertical M8 stripe beyond each end, which is what gives a
macro's ladder reach far outside its own footprint: the four shorts are at
x 844.5-912.9, between a macro at x 290.8 and one at x 883.5.

Two ladders therefore short where all three of these hold:
    the y spans of a VDD stripe of one and a VSS stripe of the other overlap,
    the x extents (after M8-snap) overlap,
    and the design is built - i.e. the pair is not screened out by either extent.

EXIT CODES
==========
    0   measured, no hard finding
    1   measured, at least one HARD finding
    2   NOT MEASURED - an input could not be resolved. This is deliberately not
        0: a check that could not read its own inputs must never look like a
        pass. See docs/tapeout on the "a zero that measured nothing" class.

USAGE
=====
    fp_guard.py                                   # defaults resolve in-repo
    fp_guard.py --move net_imem_rf32k=1506.12     # what-if a macro move
    fp_guard.py --selftest                        # prove it fires and stays quiet
    fp_guard.py --json out.json

`--move` takes the label printed in the macro table (or any unique substring of
the resolved instance name), so a coordinate can be tried without editing the
shared floorplan.
"""

import argparse
import fnmatch
import glob
import json
import math
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
# checks/ -> scripts/ -> genus-innovus/ -> ASIC/ -> repo root
REPO = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))

DEF_FLOORPLAN = os.path.join(REPO, "ASIC/genus-innovus/scripts/floorplan.tcl")
DEF_POWERPLAN = os.path.join(REPO, "ASIC/genus-innovus/scripts/power_plan.tcl")


class NotMeasured(Exception):
    """Raised whenever an input cannot be resolved. Never downgraded to a pass."""


# ---------------------------------------------------------------------------
# 1. Reading the project's own files
# ---------------------------------------------------------------------------

def read_joined(path):
    """File text with Tcl backslash-continuations folded onto one line."""
    if not os.path.isfile(path):
        raise NotMeasured("no such file: %s" % path)
    with open(path) as fh:
        return re.sub(r"\\\s*\n\s*", " ", fh.read())


def strip_comments(text):
    return "\n".join(l for l in text.splitlines() if not l.lstrip().startswith("#"))


def parse_floorplan(path):
    """die box, core box, place halo and every place_macro coordinate."""
    raw = read_joined(path)
    txt = strip_comments(raw)
    fp = {}

    m = re.search(r"^\s*set\s+CORE_TO_IO\s+([0-9.]+)", txt, re.M)
    if not m:
        raise NotMeasured("floorplan.tcl: no `set CORE_TO_IO <n>`")
    fp["core_to_io"] = float(m.group(1))

    m = re.search(r"create_floorplan\b[^\n]*?-die_size\s+([0-9.]+)\s+([0-9.]+)", txt)
    if not m:
        raise NotMeasured("floorplan.tcl: no `create_floorplan ... -die_size <w> <h>`")
    fp["die"] = (float(m.group(1)), float(m.group(2)))

    # The pad-driver height that sets the core inset. floorplan.tcl states it
    # once, in the runtime cross-check beside create_floorplan, and enforces it
    # against .core_bbox - so that literal is the file's own source of truth and
    # is read rather than assumed.
    m = re.search(r"set\s+_expect\s+\[expr\s*\{\s*([0-9.]+)\s*\+\s*\$CORE_TO_IO\s*\}\]", txt)
    if not m:
        raise NotMeasured(
            "floorplan.tcl: cannot find the `set _expect [expr {<pad_h> + $CORE_TO_IO}]`\n"
            "  cross-check beside create_floorplan. That literal is where the core\n"
            "  inset comes from; without it the core box would have to be guessed.")
    fp["pad_h"] = float(m.group(1))

    inset = fp["pad_h"] + fp["core_to_io"]
    fp["core"] = (inset, inset, fp["die"][0] - inset, fp["die"][1] - inset)

    m = re.search(r"create_place_halo\b[^\n]*?-halo_deltas\s*\{\s*([0-9.]+)\s+([0-9.]+)"
                  r"\s+([0-9.]+)\s+([0-9.]+)\s*\}", txt)
    if not m:
        raise NotMeasured("floorplan.tcl: no `create_place_halo -halo_deltas {l b r t}`")
    fp["halo"] = tuple(float(g) for g in m.groups())

    macros = []
    for m in re.finditer(r"^\s*place_macro\s+\{([^}]*)\}\s+([-0-9.]+)\s+([-0-9.]+)\s+(\w+)",
                         txt, re.M):
        macros.append({"pattern": m.group(1).strip(),
                       "x": float(m.group(2)),
                       "y": float(m.group(3)),
                       "orient": m.group(4)})
    if not macros:
        raise NotMeasured("floorplan.tcl: no place_macro lines parsed")
    fp["macros"] = macros
    return fp


def expand_splices(txt, line):
    """Substitute `{*}$VAR` from the file's own `set VAR [list ...]`.

    The M5 call reaches its anchor through `{*}$_m5_anchor` so that
    EVP_M5_ABS_START can swap `-start_from/-start_offset` for `-start` in one
    place. Without this the option scan below reads a bare `{*}$_m5_anchor` and
    reports the offset as missing - which is how this script spent an afternoon
    exiting 2 on a power plan it understands perfectly well.
    """
    for var in set(re.findall(r"\{\*\}\$\{?(\w+)\}?", line)):
        m = re.search(r"^\s*set\s+%s\s+\[list\s+([^\]]*)\]" % re.escape(var), txt, re.M)
        if not m:
            raise NotMeasured(
                "power_plan.tcl: an add_stripes call splices {*}$%s, and there is no\n"
                "  `set %s [list ...]` in the same file to expand it from. The option\n"
                "  list cannot be read, so nothing here was checked." % (var, var))
        line = re.sub(r"\{\*\}\$\{?%s\}?" % re.escape(var), m.group(1), line)
    return line


def parse_add_stripes(txt, layer):
    """The one GRID add_stripes call for <layer>, as a dict of its options.

    A grid call is the one that repeats: it carries -set_to_set_distance. The
    island-feed calls in power_plan.tcl place a single set each at a derived
    -start and are matched by feed_sets() instead, so they are excluded here
    rather than making the layer ambiguous.
    """
    hits = [l for l in txt.splitlines()
            if re.match(r"\s*add_stripes\b", l) and re.search(r"-layer\s+%s\b" % layer, l)]
    grid = [l for l in hits if re.search(r"-set_to_set_distance\s+\S", l)]
    if len(grid) != 1:
        raise NotMeasured("power_plan.tcl: expected exactly 1 repeating `add_stripes -layer %s` "
                          "(one carrying -set_to_set_distance), found %d among %d add_stripes "
                          "calls on that layer" % (layer, len(grid), len(hits)))
    line = expand_splices(txt, grid[0])
    out = {"_line": line}
    for key in ("width", "spacing", "set_to_set_distance", "start_offset"):
        m = re.search(r"-%s\s+(\S+)" % key, line)
        if not m:
            raise NotMeasured("power_plan.tcl: -%s missing from the %s add_stripes"
                              % (key, layer))
        out[key] = m.group(1)
    for key in ("direction", "start_from"):
        m = re.search(r"-%s\s+(\S+)" % key, line)
        out[key] = m.group(1) if m else None
    return out


def resolve_tcl_scalar(txt, expr, what):
    """Resolve a literal, or a `$VAR` whose `set VAR <literal>` is in the same file."""
    expr = expr.strip()
    try:
        return float(expr)
    except ValueError:
        pass
    m = re.match(r"^\$\{?(\w+)\}?$", expr)
    if not m:
        raise NotMeasured("power_plan.tcl: cannot resolve %s from '%s'" % (what, expr))
    var = m.group(1)
    sets = re.findall(r"^\s*set\s+%s\s+([0-9.]+)\s*$" % re.escape(var), txt, re.M)
    if len(sets) != 1:
        raise NotMeasured("power_plan.tcl: `set %s <n>` appears %d times; %s is ambiguous"
                          % (var, len(sets), what))
    val = float(sets[0])
    # An environment override of the same knob changes the answer, so it is read
    # here too rather than silently ignored.
    envm = re.search(r"info exists ::env\((\w+)\)[^\n]*set\s+%s\s+\$::env\(\1\)" % re.escape(var), txt)
    if envm and os.environ.get(envm.group(1), "").strip():
        val = float(os.environ[envm.group(1)])
    return val


def parse_powerplan(path):
    txt = strip_comments(read_joined(path))
    pp = {}
    if not re.search(r"^\s*split_row\s+-selected", txt, re.M):
        raise NotMeasured(
            "power_plan.tcl has no `split_row -selected`.\n"
            "  Every check in this script rests on the M5 ladder being re-anchored\n"
            "  per row region, which is what that command sets up. Without it the\n"
            "  model does not describe this power plan and a clean result would be\n"
            "  meaningless. Re-derive the model before removing this guard.")
    pp["split_row"] = True

    if os.environ.get("EVP_M5_ABS_START", "").strip():
        raise NotMeasured(
            "EVP_M5_ABS_START is set in the environment. That replaces the per-region\n"
            "  M5 -start_offset with one die-absolute ladder, and every model in this\n"
            "  script - the short phase arithmetic above all - describes the per-region\n"
            "  form. A result computed now would not describe the run.\n"
            "  (It is also measured THREE TIMES WORSE: docs/tapeout/42, 330 -> 990\n"
            "  stranded instances, 55 -> 305 functional, plus a new M1 short.)")
    m5 = parse_add_stripes(txt, "M5")
    if m5["direction"] != "horizontal":
        raise NotMeasured("the M5 add_stripes is -direction %s; this model assumes horizontal"
                          % m5["direction"])
    pp["m5"] = {"W": resolve_tcl_scalar(txt, m5["width"], "M5 -width"),
                "S": resolve_tcl_scalar(txt, m5["spacing"], "M5 -spacing"),
                "P": resolve_tcl_scalar(txt, m5["set_to_set_distance"], "M5 -set_to_set_distance"),
                "F": resolve_tcl_scalar(txt, m5["start_offset"], "M5 -start_offset"),
                "start_from": m5["start_from"]}

    m8 = parse_add_stripes(txt, "M8")
    if m8["direction"] != "vertical":
        raise NotMeasured("the M8 add_stripes is -direction %s; this model assumes vertical"
                          % m8["direction"])
    pp["m8"] = {"W": resolve_tcl_scalar(txt, m8["width"], "M8 -width"),
                "S": resolve_tcl_scalar(txt, m8["spacing"], "M8 -spacing"),
                "P": resolve_tcl_scalar(txt, m8["set_to_set_distance"], "M8 -set_to_set_distance"),
                "F": resolve_tcl_scalar(txt, m8["start_offset"], "M8 -start_offset"),
                "start_from": m8["start_from"]}

    # Does this power plan carry the island feed, and is it switched on? The
    # block is recognised by the proc it cannot run without, not by a comment.
    pp["feed"] = bool(re.search(r"^\s*proc\s+pg_feed_atrisk\b", txt, re.M))
    off = os.environ.get("EVP_NO_PG_ISLAND_FEED", "").strip()
    pp["feed_disabled"] = bool(off and off != "0" and off.lower() != "false")
    m = re.search(r"^\s*set\s+_pif_marg\s+([0-9.]+)", txt, re.M)
    pp["feed_margin"] = float(m.group(1)) if m else 0.8
    m = re.search(r"^\s*set\s+_pif_maxw\s+([0-9.]+)", txt, re.M)
    pp["feed_maxw"] = float(m.group(1)) if m else 60.0
    return pp


# ---------------------------------------------------------------------------
# 2. Macro identity and size
#
# The place_macro patterns are globs against instance names that Genus chooses,
# and floorplan.tcl documents at length that those names MOVE. So the pattern ->
# master mapping is taken from the flow's own netlist-derived artefact
# (reports/place_macro_insts.rep) rather than guessed from the pattern text.
# ---------------------------------------------------------------------------

def find_macro_map(explicit):
    if explicit:
        if not os.path.isfile(explicit):
            raise NotMeasured("--macro-map %s does not exist" % explicit)
        return explicit
    cands = glob.glob(os.path.join(REPO, "ASIC/*/build/*/reports/place_macro_insts.rep"))
    cands += glob.glob(os.path.join(REPO, "ASIC/*/runs/*/reports/place_macro_insts.rep"))
    cands = [c for c in cands if os.path.getsize(c) > 0]
    if not cands:
        raise NotMeasured(
            "no place_macro_insts.rep found under ASIC/*/build/*/reports/.\n"
            "  That file maps each macro INSTANCE to its LEF master and is written by\n"
            "  every `make place`. The place_macro patterns cannot be turned into macro\n"
            "  sizes without it, and guessing the master from the pattern text is exactly\n"
            "  the drift floorplan.tcl warns about.\n"
            "  Produce one with `make place`, or point at an existing run:\n"
            "      fp_guard.py --macro-map <run>/reports/place_macro_insts.rep")
    return max(cands, key=os.path.getmtime)


def load_macro_map(path):
    pairs = []
    with open(path) as fh:
        for line in fh:
            m = re.match(r"\s*(\S+)\s+->\s+(\S+)\s*$", line)
            if m:
                pairs.append((m.group(1), m.group(2)))
    if not pairs:
        raise NotMeasured("%s has no '<instance> -> <master>' lines" % path)
    return pairs


_LEF_CACHE = {}


def lef_sizes(dirs):
    """{master: (w, h)} from every LEF SIZE record found under <dirs>.

    Cached: --selftest evaluates four floorplans and the LEF trees do not move
    between them, and a run directory holds one libs/lef per saved database.
    """
    key = tuple(dirs)
    if key in _LEF_CACHE:
        return _LEF_CACHE[key]
    sizes = {}
    for d in dirs:
        for lef in glob.glob(os.path.join(d, "**", "*.lef"), recursive=True):
            cur = None
            try:
                with open(lef, errors="ignore") as fh:
                    for line in fh:
                        m = re.match(r"\s*MACRO\s+(\S+)", line)
                        if m:
                            cur = m.group(1)
                            continue
                        m = re.match(r"\s*SIZE\s+([0-9.]+)\s+BY\s+([0-9.]+)\s*;", line)
                        if m and cur:
                            sizes.setdefault(cur, (float(m.group(1)), float(m.group(2))))
                            cur = None
            except OSError:
                continue
    _LEF_CACHE[key] = sizes
    return sizes


def lef_site(dirs, name="core"):
    for d in dirs:
        for lef in glob.glob(os.path.join(d, "**", "*.lef"), recursive=True):
            try:
                with open(lef, errors="ignore") as fh:
                    hit = False
                    for line in fh:
                        if re.match(r"\s*SITE\s+%s\s*$" % re.escape(name), line):
                            hit = True
                            continue
                        if hit:
                            m = re.match(r"\s*SIZE\s+([0-9.]+)\s+BY\s+([0-9.]+)\s*;", line)
                            if m:
                                return float(m.group(1)), float(m.group(2))
            except OSError:
                continue
    return None


def label_for(pattern, inst):
    """A short stable handle for a macro, for the report and for --move."""
    tail = inst.split("/")[-1]
    tail = re.sub(r"^u_", "", tail)
    tail = re.sub(r"[.]u_rf_sp_hdf$|[.]u_rf$", "", tail)
    tail = re.sub(r"_u_sram_gen_", "_", tail)
    tail = re.sub(r"_u_(sram|mem|bootrom|rf)$", "", tail)
    return tail[-46:]


def resolve_macros(fp, macro_map, sizes):
    insts = [i for i, _ in macro_map]
    master_of = dict(macro_map)
    out, problems = [], []
    for mac in fp["macros"]:
        hits = fnmatch.filter(insts, mac["pattern"])
        if len(hits) != 1:
            problems.append("pattern '%s' matched %d instances in the macro map"
                            % (mac["pattern"], len(hits)))
            continue
        inst = hits[0]
        master = master_of[inst]
        if master not in sizes:
            problems.append("no LEF SIZE for master '%s' (instance %s)" % (master, inst))
            continue
        w, h = sizes[master]
        out.append({"label": label_for(mac["pattern"], inst),
                    "inst": inst, "master": master, "pattern": mac["pattern"],
                    "x": mac["x"], "y": mac["y"], "orient": mac["orient"],
                    "w": w, "h": h})
    if problems:
        raise NotMeasured("could not resolve every macro:\n    " + "\n    ".join(problems) +
                          "\n  Re-run `make place` so place_macro_insts.rep matches this "
                          "netlist,\n  or pass --macro-map for the run you mean.")
    if len(out) != len(fp["macros"]):
        raise NotMeasured("resolved %d of %d macros" % (len(out), len(fp["macros"])))
    return out


# ---------------------------------------------------------------------------
# 3. The model
# ---------------------------------------------------------------------------

def ladder(anchor, height, m5):
    """Every VDD/VSS pair whose full 2W+S span fits inside [anchor, anchor+height]."""
    W, S, P, F = m5["W"], m5["S"], m5["P"], m5["F"]
    out, k = [], 0
    while True:
        v = anchor + F + k * P
        if v + 2 * W + S > anchor + height + 1e-9:
            break
        out.append({"k": k,
                    "VDD": (v, v + W),
                    "VSS": (v + W + S, v + 2 * W + S)})
        k += 1
    return out


def vertical_sets(core, m8):
    """x spans of the vertical M8 VDD and VSS stripes, from the M8 add_stripes."""
    x0 = core[0] + m8["F"] if m8["start_from"] != "right" else core[0]
    vdd, vss, k = [], [], 0
    while True:
        b = x0 + k * m8["P"]
        if b > core[2]:
            break
        vdd.append((b, b + m8["W"]))
        vss.append((b + m8["W"] + m8["S"], b + 2 * m8["W"] + m8["S"]))
        k += 1
    return {"VDD": vdd, "VSS": vss}


def x_extent(net, x1, x2, vsets):
    """Where a horizontal stripe of <net> spanning [x1,x2] reaches after
    -extend_to_closest_target {ring stripe}: out to the far edge of the nearest
    same-net vertical stripe beyond each end."""
    left = [s for s, _ in vsets[net] if s <= x1]
    right = [e for _, e in vsets[net] if e >= x2]
    return (max(left) if left else x1, min(right) if right else x2)


def overlap(a, b):
    return min(a[1], b[1]) - max(a[0], b[0])


def check_short(macros, m5, m8, core, guard, vsets=None):
    """FP-SHORT: rail-to-rail M5 between two re-anchored ladders."""
    if vsets is None:
        vsets = vertical_sets(core, m8)
    reg = []
    for mac in macros:
        hx = (mac["x"] - HALO_L, mac["x"] + mac["w"] + HALO_R)
        reg.append({"m": mac,
                    "lad": ladder(mac["y"], mac["h"], m5),
                    "x": {n: x_extent(n, hx[0], hx[1], vsets) for n in ("VDD", "VSS")}})
    shorts, margins, pairs = [], [], 0
    for i in range(len(reg)):
        for j in range(i + 1, len(reg)):
            A, B = reg[i], reg[j]
            pairs += 1
            for hi, lo, hn, ln in ((A, B, "VDD", "VSS"), (B, A, "VDD", "VSS")):
                ox = overlap(hi["x"][hn], lo["x"][ln])
                if ox <= 0:
                    continue
                for sa in hi["lad"]:
                    for sb in lo["lad"]:
                        oy = overlap(sa[hn], sb[ln])
                        # >= 0, not > 0. Two stripe edges landing exactly on top of
                        # one another is still a rail-to-rail short; Innovus reports
                        # it with a ZERO-HEIGHT marker, which is the shape of a
                        # defect that reads as a rounding artefact and gets waived.
                        # floorplan.tcl records the naive "-20 nm" repair landing
                        # precisely there.
                        if oy > -1e-9:
                            shorts.append({
                                "vdd": hi["m"]["label"], "vss": lo["m"]["label"],
                                "x1": max(hi["x"][hn][0], lo["x"][ln][0]),
                                "y1": max(sa[hn][0], sb[ln][0]),
                                "x2": min(hi["x"][hn][1], lo["x"][ln][1]),
                                "y2": min(sa[hn][1], sb[ln][1]),
                                "h": max(oy, 0.0),
                                "kind": ("overlap" if oy > 1e-9
                                         else "COINCIDENT EDGE (zero-height marker)")})
                        elif oy > -guard - 1e-9:
                            margins.append({"vdd": hi["m"]["label"], "vss": lo["m"]["label"],
                                            "clearance": abs(oy) if oy else 0.0,
                                            "y": sa[hn][0], "x1": max(hi["x"][hn][0], lo["x"][ln][0]),
                                            "x2": min(hi["x"][hn][1], lo["x"][ln][1])})
    return shorts, margins, pairs


# The phase census is the "how close are we" number. It is reported for every
# pair whose ladders can physically meet, so the shipping floorplan's luck is
# visible as a number instead of as a comment.
def phase_census(macros, m5, m8, core, worst=12):
    vsets = vertical_sets(core, m8)
    rows = []
    for i in range(len(macros)):
        for j in range(len(macros)):
            if i == j:
                continue
            A, B = macros[i], macros[j]
            la, lb = ladder(A["y"], A["h"], m5), ladder(B["y"], B["h"], m5)
            if not la or not lb:
                continue
            ay = (la[0]["VDD"][0], la[-1]["VSS"][1])
            by = (lb[0]["VDD"][0], lb[-1]["VSS"][1])
            if overlap(ay, by) <= 0:
                continue
            ax = x_extent("VDD", A["x"] - HALO_L, A["x"] + A["w"] + HALO_R, vsets)
            bx = x_extent("VSS", B["x"] - HALO_L, B["x"] + B["w"] + HALO_R, vsets)
            if overlap(ax, bx) <= 0:
                continue
            best = None
            for sa in la:
                for sb in lb:
                    o = overlap(sa["VDD"], sb["VSS"])
                    if best is None or o > best:
                        best = o
            d = (A["y"] - B["y"]) % m5["P"]
            rows.append({"vdd": A["label"], "vss": B["label"],
                         "D_mod_P": d, "clearance": (abs(best) if best else 0.0)})
    rows.sort(key=lambda r: r["clearance"])
    return rows[:worst], len(rows)


# ---------------------------------------------------------------------------
# 4. Rows: reconstruct what `split_row -selected` leaves behind
# ---------------------------------------------------------------------------

def build_rows(macros, core, site):
    sw, rh = site
    cx1, cy1, cx2, cy2 = core

    def up(v):
        return cx1 + math.ceil((v - cx1) / sw - 1e-9) * sw

    def dn(v):
        return cx1 + math.floor((v - cx1) / sw + 1e-9) * sw

    halos = [(m["label"], m["x"] - HALO_L, m["y"] - HALO_B,
              m["x"] + m["w"] + HALO_R, m["y"] + m["h"] + HALO_T) for m in macros]
    rows = {}
    y = cy1
    while y + rh <= cy2 + 1e-9:
        cuts = sorted((h[1], h[3]) for h in halos if h[2] < y + rh - 1e-9 and h[4] > y + 1e-9)
        free = [(cx1, cx2)]
        for a, b in cuts:
            nf = []
            for s, e in free:
                if b <= s or a >= e:
                    nf.append((s, e))
                    continue
                if a > s:
                    nf.append((s, dn(a)))
                if b < e:
                    nf.append((up(b), e))
            free = nf
        keep = [(round(s, 4), round(e, 4)) for s, e in free if e - s >= sw - 1e-9]
        if keep:
            rows[round(y, 4)] = keep
        y = round(y + rh, 6)
    return rows


def coverage(rows, y, a, b):
    if y not in rows:
        return 0.0
    tot = 0.0
    for s, e in rows[y]:
        o = min(e, b) - max(s, a)
        if o > 0:
            tot += o
    return tot / (b - a)


def check_corridor(rows, site, min_len):
    """FP-CORRIDOR: wide strips one or two rows tall, walled above and below."""
    rh = site[1]
    ys = sorted(rows)
    found = []
    for idx, y in enumerate(ys):
        for a, b in rows[y]:
            if b - a < min_len:
                continue
            below = coverage(rows, round(y - rh, 4), a, b)
            above = coverage(rows, round(y + rh, 4), a, b)
            if below < 0.5 and above < 0.5:
                found.append({"y": y, "rows": 1, "x1": a, "x2": b, "len": b - a,
                              "cov_below": below, "cov_above": above})
            elif below < 0.5 and coverage(rows, round(y + rh, 4), a, b) >= 0.5 \
                    and coverage(rows, round(y + 2 * rh, 4), a, b) < 0.5:
                found.append({"y": y, "rows": 2, "x1": a, "x2": b, "len": b - a,
                              "cov_below": below, "cov_above": coverage(rows, round(y + 2 * rh, 4), a, b)})
    return found


def check_island(rows, core, m8, max_w, keep_clear=False, vsets=None):
    """FP-ISLAND: narrow row segments with no same-net vertical stripe crossing,
    whose ends are macro halos rather than the core boundary - so
    `-core_pin_target first_after_row_end` has nothing to reach."""
    if vsets is None:
        vsets = vertical_sets(core, m8)
    seen = {}
    for y, segs in rows.items():
        for a, b in segs:
            seen.setdefault((a, b), []).append(y)
    out = []
    for (a, b), ys in sorted(seen.items()):
        w = b - a
        if w > max_w:
            continue
        at_core = abs(a - core[0]) < 1e-6 or abs(b - core[2]) < 1e-6
        miss = [n for n in ("VDD", "VSS")
                if not any(min(e, b) - max(s, a) > 0 for s, e in vsets[n])]
        rec = {"x1": a, "x2": b, "w": w, "rows": len(ys),
               "y1": min(ys), "y2": max(ys), "no_stripe": miss,
               "at_core": at_core,
               "risk": bool(miss) and not at_core}
        if rec["risk"] or keep_clear:
            out.append(rec)
    return out


def feed_sets(islands, m8, margin):
    """The island-feed x coordinates power_plan.tcl derives at run time.

    This is the arithmetic half of the block in power_plan.tcl marked
    `PG ISLAND FEED`, kept here so the coordinate can be checked before any tool
    starts. THE TWO MUST AGREE: power_plan.tcl reads the rows out of the
    database and this reads them out of the floorplan text, and if they ever
    disagree the run's own log prints its numbers under `POWER-PLAN: island
    feed` for a direct diff.

    One M8 set is VDD [x, x+W] and VSS [x+W+S, x+2W+S]. For both halves to
    overlap an island [a, b] by at least m,

        x in [a + m - W,  b - m - W - S]

    which is non-empty exactly when b - a >= S + 2m. The fewest sets that cover
    every island is the classic interval-stabbing greedy - stab the interval
    that ENDS first - and each set then goes at the LEFT END of its group's
    intersection, because every island is bounded on its right by the macro halo
    that made it and an M5 rung TERMINATES on the feed stripe's edge. See the
    `PG ISLAND FEED` comment in power_plan.tcl: the middle of the window is
    0.2 um further right and puts seven M1/M3 vias into a macro blockage.
    """
    W, S = m8["W"], m8["S"]
    ivs, too_narrow = [], []
    for isl in islands:
        a, b = isl["x1"], isl["x2"]
        m = min(margin, (b - a - S) / 2.0 - 0.05)
        if m < 0.05:
            too_narrow.append(isl)
            continue
        ivs.append((a + m - W, b - m - W - S, isl))
    ivs.sort(key=lambda t: t[1])
    out = []
    while ivs:
        p = ivs[0][1]
        grp = [t for t in ivs if t[0] - 1e-9 <= p <= t[1] + 1e-9]
        keep = {id(t) for t in grp}
        ivs = [t for t in ivs if id(t) not in keep]
        lo = max(t[0] for t in grp)
        hi = min(t[1] for t in grp)
        x = math.ceil(lo * 10.0 - 1e-6) / 10.0
        if x > hi:
            x = lo
        out.append({"x": x, "lo": lo, "hi": hi, "islands": [t[2] for t in grp]})
    return out, too_narrow


# ---------------------------------------------------------------------------
# 5. Report
# ---------------------------------------------------------------------------

HALO_L = HALO_B = HALO_R = HALO_T = 0.0   # set from the floorplan in main()


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--floorplan", default=DEF_FLOORPLAN)
    ap.add_argument("--power-plan", default=DEF_POWERPLAN)
    ap.add_argument("--macro-map", default=None,
                    help="a run's reports/place_macro_insts.rep (default: newest in-tree)")
    ap.add_argument("--lef-dir", action="append", default=[],
                    help="extra directory to scan for LEF SIZE records (repeatable)")
    ap.add_argument("--move", action="append", default=[], metavar="LABEL=Y",
                    help="what-if: override one macro's y (repeatable)")
    ap.add_argument("--guard", type=float, default=0.25,
                    help="report VDD-VSS clearances below this as marginal (um)")
    ap.add_argument("--island-max-width", type=float, default=60.0)
    ap.add_argument("--corridor-min-length", type=float, default=20.0)
    ap.add_argument("--strict-corridor", action="store_true",
                    help="make FP-CORRIDOR findings hard (default: warn)")
    ap.add_argument("--strict-island", action="store_true",
                    help="make FP-ISLAND findings hard (default: warn)")
    ap.add_argument("--no-feed", action="store_true",
                    help="model the power plan WITHOUT its island feed - the A/B leg, "
                         "and what EVP_NO_PG_ISLAND_FEED=1 would build")
    ap.add_argument("--json", default=None)
    ap.add_argument("--quiet", action="store_true")
    ap.add_argument("-v", "--verbose", action="store_true",
                    help="also list the narrow row segments that CLEARED, and why")
    ap.add_argument("--selftest", action="store_true",
                    help="run the known-bad / known-good pair and assert both directions")
    args = ap.parse_args(argv)

    if args.selftest:
        return selftest(args)

    try:
        return run(args)
    except NotMeasured as e:
        print("FP-GUARD: NOT MEASURED")
        for line in str(e).splitlines():
            print("  " + line)
        print("\n  Exit code 2. This is not a pass: nothing was checked.")
        return 2


def run(args, capture=False):
    global HALO_L, HALO_B, HALO_R, HALO_T
    fp = parse_floorplan(args.floorplan)
    pp = parse_powerplan(args.power_plan)
    HALO_L, HALO_B, HALO_R, HALO_T = fp["halo"]

    mmap_path = find_macro_map(args.macro_map)
    macro_map = load_macro_map(mmap_path)

    lef_dirs = list(args.lef_dir)
    if os.environ.get("MEM_LIB_ROOT"):
        lef_dirs.append(os.environ["MEM_LIB_ROOT"])
    lef_dirs.append(os.path.join(REPO, "ASIC/romlibs"))
    lef_dirs.append(os.path.dirname(os.path.dirname(mmap_path)))  # <run>/ - has work/*/libs/lef
    lef_dirs = [d for d in lef_dirs if os.path.isdir(d)]
    sizes = lef_sizes(lef_dirs)
    if not sizes:
        raise NotMeasured("no LEF SIZE records found under:\n    " + "\n    ".join(lef_dirs) +
                          "\n  Set MEM_LIB_ROOT or pass --lef-dir.")

    macros = resolve_macros(fp, macro_map, sizes)

    for mv in args.move:
        if "=" not in mv:
            raise NotMeasured("--move wants LABEL=Y, got '%s'" % mv)
        lab, val = mv.split("=", 1)
        hit = [m for m in macros if lab == m["label"] or lab in m["inst"] or lab in m["pattern"]]
        if len(hit) != 1:
            raise NotMeasured("--move '%s' matched %d macros; labels are:\n    %s"
                              % (lab, len(hit), "\n    ".join(m["label"] for m in macros)))
        hit[0]["y"] = float(val)
        hit[0]["moved"] = True

    site = lef_site(lef_dirs) or (0.2, 1.8)
    core = fp["core"]
    m5, m8 = pp["m5"], pp["m8"]

    rows = build_rows(macros, core, site)
    corridors = check_corridor(rows, site, args.corridor_min_length)

    # The islands as the GRID alone leaves them - the defect this detector is
    # for, and what its self-test asserts on.
    grid_vsets = vertical_sets(core, m8)
    prefeed_all = check_island(rows, core, m8, args.island_max_width,
                               keep_clear=True, vsets=grid_vsets)
    prefeed = [i for i in prefeed_all if i["risk"]]

    # Then the feed power_plan.tcl derives, if this power plan carries it. The
    # feed sets are folded into the vertical grid BEFORE FP-SHORT is computed,
    # not after: an M5 stripe runs out to the nearest same-net vertical stripe
    # past each end, so adding a vertical set SHORTENS M5 extents and changes
    # which ladders can meet. Checking the shorts against the old grid would be
    # checking a power plan that is not the one being built.
    feed, feed_narrow = [], []
    if pp.get("feed") and not pp.get("feed_disabled") and not getattr(args, "no_feed", False):
        feed, feed_narrow = feed_sets(prefeed, m8, pp.get("feed_margin", 0.8))
    vsets = {n: list(grid_vsets[n]) for n in grid_vsets}
    for f in feed:
        vsets["VDD"].append((f["x"], f["x"] + m8["W"]))
        vsets["VSS"].append((f["x"] + m8["W"] + m8["S"], f["x"] + 2 * m8["W"] + m8["S"]))
    for n in vsets:
        vsets[n].sort()

    shorts, margins, pairs = check_short(macros, m5, m8, core, args.guard, vsets=vsets)
    census, census_n = phase_census(macros, m5, m8, core)
    all_narrow = check_island(rows, core, m8, args.island_max_width,
                              keep_clear=True, vsets=vsets)
    islands = [i for i in all_narrow if i["risk"]]

    res = {"floorplan": args.floorplan, "power_plan": args.power_plan,
           "macro_map": mmap_path, "core": core, "site": site,
           "m5": m5, "m8": m8, "macros": len(macros), "pairs_compared": pairs,
           "shorts": shorts, "marginal": margins, "phase_census": census,
           "phase_census_pairs": census_n,
           "corridors": corridors, "islands": islands,
           "islands_prefeed": prefeed,
           "feed": feed, "feed_present": bool(pp.get("feed")),
           "feed_disabled": bool(pp.get("feed_disabled") or getattr(args, "no_feed", False)),
           "feed_unfeedable": feed_narrow,
           "narrow_segments": all_narrow}

    hard = bool(shorts)
    if args.strict_corridor and corridors:
        hard = True
    if args.strict_island and islands:
        hard = True
    res["verdict"] = "FAIL" if hard else "PASS"

    if capture:
        return res

    if not args.quiet:
        emit(res, args)
    if args.json:
        with open(args.json, "w") as fh:
            json.dump(res, fh, indent=2)
    return 1 if hard else 0


def emit(r, args):
    p = print
    p("=" * 78)
    p("FP-GUARD - floorplan-adjustment pre-flight   (arithmetic only, no EDA licence)")
    p("=" * 78)
    p("  floorplan   %s" % r["floorplan"])
    p("  power plan  %s" % r["power_plan"])
    p("  macro map   %s" % r["macro_map"])
    p("  core box    (%.1f, %.1f) (%.1f, %.1f)   site %.1f x %.1f" %
      (r["core"][0], r["core"][1], r["core"][2], r["core"][3], r["site"][0], r["site"][1]))
    p("  M5 ladder   W=%g S=%g P=%g F=%g (%s)" %
      (r["m5"]["W"], r["m5"]["S"], r["m5"]["P"], r["m5"]["F"], r["m5"]["start_from"]))
    p("  M8 verticals W=%g S=%g P=%g F=%g (%s)" %
      (r["m8"]["W"], r["m8"]["S"], r["m8"]["P"], r["m8"]["F"], r["m8"]["start_from"]))
    p("  %d macros resolved, %d macro pairs compared" % (r["macros"], r["pairs_compared"]))

    p("")
    p("-- FP-SHORT  rail-to-rail VDD/VSS on the re-anchored M5 ladders  [HARD] ------")
    if r["shorts"]:
        p("  %d predicted rail-to-rail short(s):" % len(r["shorts"]))
        for s in r["shorts"]:
            p("     (%9.3f, %9.3f) (%9.3f, %9.3f)  h=%.3f   %s VDD x %s VSS   %s"
              % (s["x1"], s["y1"], s["x2"], s["y2"], s["h"], s["vdd"], s["vss"], s["kind"]))
    else:
        p("  none  (over %d pairs whose ladders can physically meet)" % r["phase_census_pairs"])
    if r["marginal"]:
        p("  [warn] %d stripe pair(s) within the %.3f um guard band. Not a short today;"
          % (len(r["marginal"]), args.guard))
        p("  a macro nudge of that size makes it one, silently:")
        for m in r["marginal"]:
            p("     clearance %.4f um at y=%.3f, x %.1f..%.1f   %s VDD / %s VSS"
              % (m["clearance"], m["y"], m["x1"], m["x2"], m["vdd"], m["vss"]))

    p("")
    p("-- phase margin census: the closest ladder pairs that CAN meet ---------------")
    p("     %-30s %-30s %8s %10s" % ("VDD ladder", "VSS ladder", "D mod P", "clearance"))
    for c in r["phase_census"]:
        p("     %-30s %-30s %8.3f %10.3f" % (c["vdd"][:30], c["vss"][:30],
                                             c["D_mod_P"], c["clearance"]))
    p("     (%d ordered pairs share both a y range and an x range)" % r["phase_census_pairs"])

    p("")
    p("-- FP-CORRIDOR  walled-in 1-2 row strips -> IMPSP-2021  [%s] ----------"
      % ("HARD" if args.strict_corridor else "warn"))
    if r["corridors"]:
        for c in r["corridors"]:
            p("     y=%9.3f  %d row(s)  x=[%.1f, %.1f]  len=%.1f  coverage below %.2f above %.2f"
              % (c["y"], c["rows"], c["x1"], c["x2"], c["len"], c["cov_below"], c["cov_above"]))
    else:
        p("     none longer than %.1f um" % args.corridor_min_length)

    p("")
    p("-- FP-ISLAND  split_row islands with no supply stripe crossing  [%s] --"
      % ("HARD" if args.strict_island else "warn"))
    p("     %d row segment(s) <= %.1f um wide were examined; %d left at risk by the"
      " M8 grid alone; %d after the island feed."
      % (len(r["narrow_segments"]), args.island_max_width,
         len(r["islands_prefeed"]), len(r["islands"])))
    if not r["feed_present"]:
        p("     [warn] this power plan carries NO island feed. The islands below are the")
        p("            330-instance / 55-functional defect of docs/tapeout/42, unfixed.")
    elif r["feed_disabled"]:
        p("     [warn] EVP_NO_PG_ISLAND_FEED is set - the feed is present but SWITCHED OFF.")
    for f in r["feed"]:
        p("     feed set x=%8.3f  VDD %.3f-%.3f  VSS %.3f-%.3f   feeds %d island(s), window [%.3f, %.3f]"
          % (f["x"], f["x"], f["x"] + r["m8"]["W"],
             f["x"] + r["m8"]["W"] + r["m8"]["S"],
             f["x"] + 2 * r["m8"]["W"] + r["m8"]["S"],
             len(f["islands"]), f["lo"], f["hi"]))
    for i in r["feed_unfeedable"]:
        p("     [warn] x=[%8.1f,%8.1f] w=%6.2f is narrower than one VDD+VSS set; no single"
          " set can feed it." % (i["x1"], i["x2"], i["w"]))
    for i in (r["narrow_segments"] if args.verbose else r["islands"]):
        if i["risk"]:
            p("     AT RISK  x=[%8.1f,%8.1f] w=%6.2f %3d row(s) y %.1f..%.1f  no vertical %s stripe"
              % (i["x1"], i["x2"], i["w"], i["rows"], i["y1"], i["y2"], "+".join(i["no_stripe"])))
        else:
            why = "ends on the core boundary (the ring is the target)" if i["at_core"] \
                  else "crossed by a vertical stripe of both supplies"
            p("     cleared  x=[%8.1f,%8.1f] w=%6.2f %3d row(s) y %.1f..%.1f  %s"
              % (i["x1"], i["x2"], i["w"], i["rows"], i["y1"], i["y2"], why))
    if not args.verbose:
        p("     (re-run with --verbose to see the cleared segments and why)")

    p("")
    p("VERDICT: %s" % r["verdict"])
    p("=" * 78)


# ---------------------------------------------------------------------------
# 6. Self-test - the check proves itself in both directions
#
# A gate nobody has watched fail is not a gate. This drives the detector over a
# coordinate pair whose ANSWER IS ON DISK: y=1506.12 for the network imem rf_32k
# is the floorplan that streamed build/full-20260814, which check_drc reports
# with four `Special Wire of Net VSS & Special Wire of Net VDD (M5)` records;
# y=1505.60 is build/fp1505, which reports none.
# ---------------------------------------------------------------------------

EXPECTED_BAD = [(844.500, 1546.600, 912.900, 1546.620),
                (844.500, 1561.600, 912.900, 1561.620),
                (844.500, 1576.600, 912.900, 1576.620),
                (844.500, 1591.600, 912.900, 1591.620)]
SELFTEST_MACRO = "region_imem_0_rf_32k"
SELFTEST_FALLBACK = "rf_32k"


def selftest(args):
    """Drive the detector over coordinates whose ANSWER IS ON DISK.

    A gate nobody has watched fail is not a gate, and a battery that quietly
    stops running cases still exits 0 - so this prints a tally and names every
    case, in the shape ci/signoff.yaml's other *-selftest stages assert on.

    The three subjects are all one number: the y of the network imem rf_32k in
    floorplan.tcl, at x = 290.8. The shorts it creates are at x = 844.5, 550 um
    away, which is the whole reason a placement diff cannot clear a macro move.
    """
    print("FP-GUARD SELF-TEST")
    print("  subject : network imem rf_32k y, in floorplan.tcl (x = 290.8)")
    print("  1506.12 -> build/full-20260814; its check_drc reports 4 rail-to-rail M5 shorts")
    print("  1505.60 -> build/fp1505;        its check_drc reports 0")
    print("  1506.10 -> the naive '-20 nm' repair; floorplan.tcl records that this lands")
    print("             EXACTLY on the interval edge, where the two stripe edges become")
    print("             coincident - still a short, with a zero-height marker")
    print("  1503.40 -> the pre-2026-08-13 coordinate: no short, but the orphan corridor")
    print("             along the whole core top that made the legalizer fail")
    print("")

    try:
        base = argparse.Namespace(**vars(args))
        base.selftest = False

        def once(_no_feed=False, **moves):
            a = argparse.Namespace(**vars(base))
            a.move = ["%s=%s" % (k, v) for k, v in moves.items()]
            a.no_feed = _no_feed
            return run(a, capture=True)

        bad = once(**{SELFTEST_FALLBACK: 1506.12})
        # The four coordinates below were measured by check_drc on a build whose
        # power plan had NO island feed. A feed set is a same-net vertical
        # target, and an M5 stripe stops at the FIRST one past its end, so with
        # the feed those same four shorts are 21 um shorter. Asserting the
        # historical numbers therefore has to be done against the historical
        # power plan - hence _no_feed - and the feed's own effect on that
        # floorplan is asserted separately below.
        bad_nofeed = once(_no_feed=True, **{SELFTEST_FALLBACK: 1506.12})
        good = once(**{SELFTEST_FALLBACK: 1505.60})
        edge = once(**{SELFTEST_FALLBACK: 1506.10})
        old_fp = once(**{SELFTEST_FALLBACK: 1503.40, "region_eth_scratch_tx_0": 1633.80})
    except NotMeasured as e:
        print("  NOT MEASURED: %s" % e)
        print("\n  Exit code 2 - the self-test could not run, so it proves nothing.")
        return 2

    cases = []

    def case(name, ok, detail):
        cases.append((name, ok, detail))
        print("  %-34s %s   %s" % (name, "PASS" if ok else "FAIL", detail))

    # -- FP-SHORT, both directions --------------------------------------------
    case("short_fires_on_1506.12", len(bad["shorts"]) == 4,
         "predicted %d rail-to-rail shorts, expected 4" % len(bad["shorts"]))
    got = sorted((round(x["x1"], 3), round(x["y1"], 3), round(x["x2"], 3), round(x["y2"], 3))
                 for x in bad_nofeed["shorts"])
    coords_ok = len(got) == len(EXPECTED_BAD) and all(
        all(abs(a - b) < 0.0011 for a, b in zip(w, h)) for w, h in zip(EXPECTED_BAD, got))
    case("short_coords_match_check_drc", coords_ok,
         "; ".join("(%.3f, %.3f) (%.3f, %.3f)" % h for h in got) if got else "no coordinates")
    case("island_feed_creates_no_short_on_1506.12", len(bad["shorts"]) == len(bad_nofeed["shorts"]),
         "the feed neither adds nor hides a short on the known-bad floorplan: %d with, %d without"
         % (len(bad["shorts"]), len(bad_nofeed["shorts"])))
    case("short_quiet_on_1505.60", not good["shorts"],
         "predicted %d rail-to-rail shorts, expected 0 over %d pairs that can meet"
         % (len(good["shorts"]), good["phase_census_pairs"]))
    case("short_quiet_on_1503.40", not old_fp["shorts"],
         "the pre-08-13 coordinate did not short either, and is not reported as one")
    zero = [x for x in edge["shorts"] if x["h"] < 1e-9]
    case("short_catches_coincident_edge", len(edge["shorts"]) == 4 and len(zero) == 4,
         "1506.10: %d shorts, %d of them zero-height (expected 4 and 4)"
         % (len(edge["shorts"]), len(zero)))

    # -- the check is not vacuous ---------------------------------------------
    case("compared_something", good["pairs_compared"] > 0 and good["phase_census_pairs"] > 0,
         "%d macro pairs compared, %d ordered pairs share a y and an x range"
         % (good["pairs_compared"], good["phase_census_pairs"]))

    # -- FP-CORRIDOR, both directions -----------------------------------------
    # The corridor that made the legalizer fail ran along the core top. It is
    # present at the pre-08-13 coordinates and absent at today's.
    top_old = [c for c in old_fp["corridors"] if c["y"] > 1780]
    top_new = [c for c in good["corridors"] if c["y"] > 1780]
    case("corridor_fires_on_pre_0813", len(top_old) == 1,
         ("y=%.1f, %d row, x=[%.1f, %.1f] len=%.1f, %.0f%% of it has no row beneath"
          % (top_old[0]["y"], top_old[0]["rows"], top_old[0]["x1"], top_old[0]["x2"],
             top_old[0]["len"], 100 * (1 - top_old[0]["cov_below"])))
         if top_old else "no core-top corridor found at 1503.40 / 1633.80")
    case("corridor_quiet_after_repair", not top_new,
         "no core-top corridor at today's coordinates")

    # -- FP-ISLAND: the three controls in docs/tapeout/42 s3e must stay quiet --
    CONTROLS = ((1390.6, 1395.0), (1024.0, 1055.6), (205.0, 227.0))
    SITES = ((1051.8, 1055.0), (1034.2, 1055.6), (1043.2, 1055.6),
             (869.2, 907.6), (879.8, 895.2))
    risky = {(round(i["x1"], 1), round(i["x2"], 1)) for i in good["islands_prefeed"]}
    examined = {(round(i["x1"], 1), round(i["x2"], 1)) for i in good["narrow_segments"]}
    case("island_controls_stay_quiet",
         all(c in examined and c not in risky for c in CONTROLS),
         "the 3 segments docs/tapeout/42 s3e records as stranding nobody were examined "
         "and cleared")
    case("island_known_sites_fire", all(x in risky for x in SITES),
         "all 5 sites docs/tapeout/42 records as stranding cells are reported")

    # -- FP-ISLAND, the repair: the feed must clear every one of them ----------
    # Without this case the two above would still pass on a power plan whose
    # feed does nothing, because they both read the PRE-feed view.
    case("island_feed_present", good["feed_present"] and not good["feed_disabled"],
         "power_plan.tcl carries the island feed and it is enabled")
    case("island_feed_clears_every_site",
         good["feed_present"] and not good["islands"],
         "%d island(s) left at risk after %d derived feed set(s) at x = %s"
         % (len(good["islands"]), len(good["feed"]),
            ", ".join("%.3f" % f["x"] for f in good["feed"]) or "-"))
    case("island_feed_adds_no_short", not good["shorts"],
         "FP-SHORT recomputed WITH the feed sets folded into the vertical grid: %d short(s)"
         % len(good["shorts"]))

    npass = sum(1 for _, ok, _ in cases if ok)
    nfail = len(cases) - npass
    print("")
    print("  %d passed, %d failed, %d cases" % (npass, nfail, len(cases)))
    print("SELF-TEST: %s" % ("PASS - the detector fires on every known-bad input and "
                             "stays quiet on every known-good one"
                             if nfail == 0 else
                             "FAIL - %d case(s) did not discriminate" % nfail))
    return 0 if nfail == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
