#!/usr/bin/env python3
"""
synth_depth_report.py -- make a synthesis netlist's LOGIC DEPTH readable, and
say which deep paths are deep because of DEPTH and which because of LOAD.

A joint work commissioned on behalf of SoC Labs, under Arm Academic Access
license.  Copyright 2026, SoC Labs (www.soclabs.org)

    scripts/ci/synth_depth_report.py --run-dir ASIC/eth-chiplet/build/<tag>
    scripts/ci/synth_depth_report.py --selftest

WHY THIS EXISTS
---------------
Nothing in this flow surfaced logic depth at synthesis. The first anyone learned
of a deep combinational cone was a timing failure hours later at route, in a
stage whose reports are 35 MB and whose fix options by then are placement ones.

Synthesis already knows. Genus has `report_logic_levels_histogram`, which walks
EVERY timing endpoint and reports its depth whether or not the path meets
timing, and `report_timing`, whose full path table carries per-stage delay,
load, fanout and cell type. Neither was called. This turns both into four
reports that a human can act on at 2am.

THE DISTINCTION THAT MATTERS, AND WHY IT IS NOT SLACK
-----------------------------------------------------
Two paths with identical slack need opposite fixes:

  DEPTH-BOUND   many small stages, delay spread evenly.  Fix in RTL: pipeline,
                retime, restructure the arithmetic.  Placement cannot help;
                CTS and route will make it WORSE, because every added stage of
                margin has to come from somewhere.
  LOAD-BOUND    few stages, one or two of them huge, or a third of the levels
                are buffers and inverters the tool inserted to drive a big net.
                Fix in the flow: size the driver, split the fanout, or let P&R
                do it with real placement. Depth is not the problem.

A slack-ordered report cannot tell these apart, and on this design it cannot
even find the deep paths: rc5's whole r2r_clk group sits between 0 and 3 ps of
slack, so `report_timing -max_paths 50` returns fifty paths that all met, none
of which is the deepest in the design.

WHAT EACH OUTPUT ANSWERS
------------------------
  synth_depth.rep      the 2am report. Five sections, each worst-first:
                         1  design-wide depth distribution, with and without
                            buffers/inverters -- the design-scale DEPTH vs LOAD
                            split in two lines
                         2  deepest endpoints, WHETHER OR NOT THEY MEET TIMING
                         3  worst paths by slack, each with its depth
                         4  per-path anatomy: levels, buffer levels, where the
                            delay actually is, and the verdict with its numbers
                         5  hierarchy rollup: who owns the depth
  synth_depth.json     the same numbers, machine-readable, for a gate or a diff

EVERY NUMBER CARRIES ITS SCOPE. A depth is meaningless without knowing whether
buffers were counted, which analysis view produced it, and how many endpoints
were in the population. Each table states all three in its header.

INPUTS (all under <run>/reports/, all optional except that at least one path
or endpoint source must parse -- otherwise this refuses rather than printing an
empty report that looks like coverage):

  synth_logic_levels.rep         report_logic_levels_histogram
  synth_logic_levels_nobuf.rep   ... -skip_buffer -skip_inverter
  synth_logic_levels_detail.rep  ... -details       (the endpoint table)
  synth_deep_paths.rep           report_timing -to <deepest endpoints>
  syn_timing.rep                 report_timing -max_paths N   (worst by slack)
  synth_libcell_class.tsv        cell -> is_buffer/is_inverter/is_macro/is_seq

The libcell class table is what makes the buffer count EXACT. Without it the
classifier falls back to a name regex, and every table that used it says so in
its header rather than quietly presenting a guess as a measurement.

EXIT CODES
  0  reports written
  2  refused: nothing measurable (no path source parsed, or a source parsed to
     zero rows). A depth report over zero paths is the failure mode this
     repository has a documented class of; it exits non-zero.
  3  bad usage
"""

from __future__ import annotations

import argparse
import json
import os
import re
import statistics
import sys
import tempfile
from pathlib import Path

# ---------------------------------------------------------------------------
# thresholds. Printed in the report so a reader can disagree with them.
# ---------------------------------------------------------------------------
DEEP_LEVELS = 40      # at or above this, "deep" -- a pipelining conversation
BI_FRACTION = 0.30    # buffers+inverters >= this fraction of levels -> LOAD
TOP3_SHARE = 0.40     # 3 slowest stages hold >= this of the data path -> LOAD
LOAD_HI_FF = 60.0     # a single stage driving >= this many fF -> LOAD
FANOUT_HI = 24        # a single stage with >= this fanout -> LOAD

# Fallback only, used when synth_libcell_class.tsv is absent. tcbn65lp spells a
# clock inverter CKND<n> and a clock NAND2 CKND2D<n>; the trailing drive suffix
# is what tells them apart, which is exactly why the tool's own attribute is
# preferred and its absence is reported.
BUF_RE = re.compile(r"^(BUFF?D\d|CKBD\d|DEL\d|BUFTD\d)")
INV_RE = re.compile(r"^(INVD\d|CKND\d+$|CKN\d)")


class Refuse(Exception):
    """Raised when the thing being measured is not present to be measured."""


# ---------------------------------------------------------------------------
# hierarchy
# ---------------------------------------------------------------------------
def canon_parts(inst_path: str) -> list[str]:
    """Split a Genus instance path into hierarchy components.

    Two separators, because synthesis produces both:

      '/'    surviving hierarchy
      '_u_'  hierarchy that ungrouping DISSOLVED. Genus joins the parent and
             child instance names with an underscore, so
             `u_ethmac_0_u_inner_u_ha1588_servo` is three levels, not one, and
             a rollup that treats it as one attributes the whole cone to the
             top wrapper.
      '.'    a generate-block scope, which Verilog already spells with a dot.

    THIS IS A HEURISTIC and the report says so. It mis-splits a module whose
    own name contains `_u_`. When the path report carries Genus's `module`
    column, that is used instead and the heuristic is not consulted.
    """
    out: list[str] = []
    for slash_part in inst_path.split("/"):
        for dot_part in slash_part.split("."):
            if not dot_part:
                continue
            # `_cg_RC_CG_` is the same ungrouping join, for the clock-gate
            # wrappers synthesis inserts. Split it too, so `bucket` can fold
            # them away instead of leaving `u_x_cg_RC_CG_HIER_INST3` as its own
            # rollup bucket holding one endpoint.
            out.extend(re.split(r"_(?=u_)|_(?=cg_RC_CG_)", dot_part))
    return out


def strip_common(paths: list[list[str]]) -> tuple[list[str], list[list[str]]]:
    """Drop the leading components every path shares; return them and the rest.

    A rollup keyed on `u_nanosoc_eth_chiplet_chip/u_soc/...` is one bucket wide.
    The shared prefix is reported once in the header instead.
    """
    if not paths:
        return [], []
    pref: list[str] = []
    for i in range(min(len(p) for p in paths)):
        c = paths[0][i]
        if all(p[i] == c for p in paths) and any(len(p) > i + 1 for p in paths):
            pref.append(c)
        else:
            break
    return pref, [p[len(pref):] for p in paths]


def owner_parts(inst_path: str) -> list[str]:
    """The hierarchy that CONTAINS a leaf instance, i.e. its path minus itself.

    `a/b/g10` is owned by `a/b`. Bucketing on the full path instead puts every
    gate in a bucket of its own, which is a rollup of one and tells nobody
    anything.
    """
    p = canon_parts(inst_path)
    return p[:-1] if len(p) > 1 else p


# Clock-gating wrappers are inserted BY synthesis, one per gated register bank.
# They are not design hierarchy and there are hundreds of them; left in, they
# turn a rollup into a list of buckets holding one endpoint each and bury the
# blocks a reader is looking for. Folded into their parent, and said so.
CG_WRAPPER = re.compile(r"^cg_RC_CG_(HIER_INST|MOD)")


def bucket(parts: list[str], depth: int) -> str:
    keep = [p for p in parts if not CG_WRAPPER.match(p)]
    if not keep:
        return "(top)"
    return "/".join(keep[:depth])


# ---------------------------------------------------------------------------
# libcell class table
# ---------------------------------------------------------------------------
class CellClass:
    """cell name -> is_buffer / is_inverter / is_macro / is_sequential."""

    def __init__(self, tsv: Path | None):
        self.exact = False
        self.src = "name regex (fallback -- synth_libcell_class.tsv absent)"
        self.buf: set[str] = set()
        self.inv: set[str] = set()
        self.macro: set[str] = set()
        self.seq: set[str] = set()
        if tsv and tsv.is_file():
            n = 0
            for line in tsv.read_text(errors="replace").splitlines():
                if not line.strip() or line.startswith("#"):
                    continue
                f = line.split("\t")
                if len(f) < 5:
                    continue
                cell = f[0]
                if f[1] == "1":
                    self.buf.add(cell)
                if f[2] == "1":
                    self.inv.add(cell)
                if f[3] == "1":
                    self.macro.add(cell)
                if f[4] == "1":
                    self.seq.add(cell)
                n += 1
            if n:
                self.exact = True
                self.src = f"{tsv.name} ({n} lib cells, from Genus attributes)"

    def is_bi(self, cell: str) -> bool:
        if self.exact:
            return cell in self.buf or cell in self.inv
        return bool(BUF_RE.match(cell) or INV_RE.match(cell))

    def is_macro(self, cell: str) -> bool:
        return cell in self.macro if self.exact else False


# ---------------------------------------------------------------------------
# report_timing full-detail parser
# ---------------------------------------------------------------------------
PATH_HDR = re.compile(
    r"^Path\s+(\d+):\s+(MET|VIOLATED)\s+\(([-\d]+)\s*ps\)\s+(.*?)\s+with\s+Pin\s+(\S+)"
)


def _num(tok: str):
    try:
        return float(tok)
    except ValueError:
        return None


def parse_timing_report(path: Path) -> list[dict]:
    """Parse Genus `report_timing` full output into per-path dicts.

    Row shape (default -fields): the last eleven whitespace-separated tokens are
    flags, arc, edge, cell, power_domain, fanout, load, transition, delay,
    arrival, instance_location; everything before them is the pin name, which
    contains no spaces but is long enough that a left-to-right split is wrong.
    Rows that do not have that shape are not data rows and are skipped -- and
    if NO row in a path has it, that path is dropped and counted, so a format
    change shows up as a count rather than as silence.
    """
    txt = path.read_text(errors="replace")
    chunks = re.split(r"(?m)^(?=Path\s+\d+:)", txt)
    paths: list[dict] = []
    malformed = 0
    ordinal = 0
    for ch in chunks:
        m = PATH_HDR.match(ch)
        if not m:
            continue
        rank, verdict, slack, check, endpin = m.groups()
        ordinal += 1
        d: dict = {
            # `report_timing -to <ep>` writes a fresh report per call, so every
            # appended block calls itself "Path 1". The ordinal is what makes a
            # row in this report findable in the file.
            "rank": ordinal,
            "tool_rank": int(rank),
            "met": verdict == "MET",
            "slack_ps": int(slack),
            "check": check.strip(),
            "endpoint": endpin,
            "source": path.name,
        }
        g = re.search(r"^\s*Group:\s*(\S+)", ch, re.M)
        d["group"] = g.group(1) if g else "?"
        s = re.search(r"^\s*Startpoint:\s*(?:\([RF]\)\s*)?(\S+)", ch, re.M)
        d["startpoint"] = s.group(1) if s else "?"
        e = re.search(r"^\s*Endpoint:\s*(?:\([RF]\)\s*)?(\S+)", ch, re.M)
        if e:
            d["endpoint"] = e.group(1)
        elif "->" in d["endpoint"]:
            # "<inst>/CP->D" -> "<inst>/D"
            head, _, cap = d["endpoint"].rpartition("->")
            d["endpoint"] = head[: head.rfind("/")].rsplit("->", 1)[0] + "/" + cap

        cl = re.findall(r"^\s*Clock:\s*(?:\([RF]\)\s*)?(\S+)", ch, re.M)
        d["launch_clock"] = cl[0] if cl else "?"
        d["capture_clock"] = cl[1] if len(cl) > 1 else d["launch_clock"]
        dp = re.search(r"^\s*Data Path:-\s*(\d+)", ch, re.M)
        d["data_path_ps"] = int(dp.group(1)) if dp else None

        rows = []
        for line in ch.splitlines():
            if not line.startswith(" ") or line.lstrip().startswith("#"):
                continue
            toks = line.rsplit(None, 11)
            if len(toks) != 12:
                continue
            pin = toks[0].strip()
            (flags, arc, edge, cell, pd, fanout, load, trans, delay,
             arrival, loc) = toks[1:]
            if not (loc.startswith("(") and loc.endswith(")")):
                continue
            rows.append({
                "pin": pin, "flags": flags, "arc": arc, "edge": edge,
                "cell": cell, "pd": pd,
                "fanout": _num(fanout), "load": _num(load),
                "trans": _num(trans), "delay": _num(delay),
                "arrival": _num(arrival),
            })
        if not rows:
            malformed += 1
            continue
        d["rows"] = rows
        paths.append(d)
    if malformed:
        for p in paths:
            p["_malformed_siblings"] = malformed
    return paths


def inst_of(pin: str) -> str:
    """'a/b/c/g10/ZN' -> 'a/b/c/g10'. The pin is the part after the last '/'."""
    return pin.rsplit("/", 1)[0] if "/" in pin else pin


def analyse_path(d: dict, cc: CellClass) -> dict:
    """Per-path depth, buffer share, delay distribution and verdict.

    Levels are counted EXACTLY, not by position: the launch element is the
    instance that owns the startpoint pin and the capture element is the
    instance that owns the endpoint pin, so their own rows are excluded however
    the report is formatted. Everything between them with a real timing arc is
    one level of combinational logic.
    """
    rows = d["rows"]
    launch = inst_of(d["startpoint"])
    capture = inst_of(d["endpoint"])
    levels = []
    for r in rows:
        if r["arc"] in ("-", ""):
            continue
        i = inst_of(r["pin"])
        if i == launch or i == capture:
            continue
        levels.append(r)

    delays = [r["delay"] or 0.0 for r in levels]
    total = sum(delays)
    n = len(levels)
    bi = sum(1 for r in levels if cc.is_bi(r["cell"]))
    macros = sum(1 for r in levels if cc.is_macro(r["cell"]))
    loads = [(r["load"] or 0.0, r) for r in levels]
    fos = [(r["fanout"] or 0.0, r) for r in levels]
    max_load = max(loads, key=lambda t: t[0]) if loads else None
    max_fo = max(fos, key=lambda t: t[0]) if fos else None
    top3 = sum(sorted(delays, reverse=True)[:3])

    a = {
        "levels": n,
        "buf_inv_levels": bi,
        "macro_levels": macros,
        "logic_levels": n - bi,
        "bi_frac": (bi / n) if n else 0.0,
        "stage_ps_total": round(total, 1),
        "stage_ps_median": round(statistics.median(delays), 1) if delays else 0.0,
        "stage_ps_max": round(max(delays), 1) if delays else 0.0,
        "top3_share": (top3 / total) if total else 0.0,
        "max_load_ff": round(max_load[0], 1) if max_load else 0.0,
        "max_fanout": int(max_fo[0]) if max_fo else 0,
    }
    a["worst_stage"] = ""
    if delays:
        w = max(levels, key=lambda r: r["delay"] or 0.0)
        a["worst_stage"] = f'{w["pin"]} ({w["cell"]}, {w["delay"]:.0f} ps)'
    if max_load:
        wl = max_load[1]
        a["worst_load_stage"] = f'{wl["pin"]} ({wl["cell"]}, {wl["load"]:.1f} fF)'
    else:
        a["worst_load_stage"] = ""

    load_reasons = []
    if a["bi_frac"] >= BI_FRACTION:
        load_reasons.append(f'{bi}/{n} levels are buf/inv ({a["bi_frac"]:.0%})')
    if a["top3_share"] >= TOP3_SHARE:
        load_reasons.append(f'3 slowest stages = {a["top3_share"]:.0%} of data path')
    if a["max_load_ff"] >= LOAD_HI_FF:
        load_reasons.append(f'a stage drives {a["max_load_ff"]:.0f} fF')
    if a["max_fanout"] >= FANOUT_HI:
        load_reasons.append(f'a stage fans out to {a["max_fanout"]}')
    deep = a["logic_levels"] >= DEEP_LEVELS

    if deep and load_reasons:
        a["verdict"] = "DEPTH+LOAD"
    elif deep:
        a["verdict"] = "DEPTH"
    elif load_reasons:
        a["verdict"] = "LOAD"
    else:
        a["verdict"] = "SHORT"
    a["verdict_because"] = "; ".join(load_reasons) if load_reasons else (
        f'{a["logic_levels"]} non-buffer levels, delay spread evenly '
        f'(3 slowest = {a["top3_share"]:.0%})' if deep else
        f'{a["logic_levels"]} non-buffer levels, no load outlier')
    a["fix"] = {
        "DEPTH": "RTL: pipeline / retime / restructure. P&R cannot shorten it.",
        "DEPTH+LOAD": "RTL first (depth), then drive. Both are real here.",
        "LOAD": "Flow: size the driver, split the fanout. Depth is not the problem.",
        "SHORT": "Neither deep nor load-bound -- this path is simply tight.",
    }[a["verdict"]]
    a["level_insts"] = [inst_of(r["pin"]) for r in levels]
    a["level_cells"] = [r["cell"] for r in levels]
    return a


def segment(level_insts: list[str], depth: int, pref_len: int) -> list[tuple[str, int]]:
    """Run-length encode the ordered owner buckets a path walks through.

    This is the answer to 'how much of this cone is whose': the path enters a
    block, spends N levels there, leaves, and may come back. A set would lose
    the ordering and the re-entry, both of which decide where a register goes.
    """
    segs: list[list] = []
    for inst in level_insts:
        b = bucket(owner_parts(inst)[pref_len:], depth)
        if segs and segs[-1][0] == b:
            segs[-1][1] += 1
        else:
            segs.append([b, 1])
    return [(a, b) for a, b in segs]


# ---------------------------------------------------------------------------
# report_logic_levels_histogram parsers
# ---------------------------------------------------------------------------
HIST_ROW = re.compile(r"^\|\s*(\d+)\s*->\s*(\d+)\s*\|\s*(\d+)\(\s*([\d.]+)\)\s*\|")
HIST_TOT = re.compile(r"^\|\s*(\d+)\(worst\)\s*\|\s*(\d+)\s*\|\s*total end points")
HIST_VIEW = re.compile(r"View:\s*'([^']+)'")


def parse_histogram(path: Path) -> dict | None:
    if not path.is_file():
        return None
    bars, worst, total, view = [], None, None, None
    for line in path.read_text(errors="replace").splitlines():
        m = HIST_ROW.match(line.strip())
        if m:
            bars.append({"lo": int(m.group(1)), "hi": int(m.group(2)),
                         "n": int(m.group(3)), "pct": float(m.group(4))})
            continue
        m = HIST_TOT.match(line.strip())
        if m:
            worst, total = int(m.group(1)), int(m.group(2))
            continue
        m = HIST_VIEW.search(line)
        if m:
            view = m.group(1)
    if not bars and worst is None:
        return None
    return {"file": path.name, "bars": bars, "worst_levels": worst,
            "endpoints": total, "view": view}


DETAIL_HDR = re.compile(r"^DETAIL REPORT\b")


def parse_detail(path: Path) -> list[dict]:
    """The `-details` endpoint table: startpoint, endpoint, levels, cost group.

    THIS is the population that a slack-ordered report cannot reach: every
    endpoint, with its depth, whether or not it meets timing.
    """
    if not path.is_file():
        return []
    rows, on = [], False
    for line in path.read_text(errors="replace").splitlines():
        if DETAIL_HDR.match(line):
            on = True
            continue
        if not on:
            continue
        s = line.strip()
        if not s or s.startswith("---") or s.startswith("*"):
            continue
        f = s.split()
        if len(f) < 4:
            continue
        try:
            lvl = int(f[2])
        except ValueError:
            continue
        rows.append({"startpoint": f[0], "endpoint": f[1], "levels": lvl,
                     "group": f[3]})
    return rows


# ---------------------------------------------------------------------------
# report writer
# ---------------------------------------------------------------------------
class Out:
    def __init__(self):
        self.L: list[str] = []

    def p(self, s: str = ""):
        self.L.append(s)

    def h(self, s: str):
        self.p()
        self.p(s)
        self.p("=" * len(s))

    def sh(self, s: str):
        self.p()
        self.p(s)
        self.p("-" * len(s))

    def text(self) -> str:
        return "\n".join(self.L) + "\n"


def elide(s: str, n: int) -> str:
    return s if len(s) <= n else s[: n - 3] + "..."


def build(run: Path, reports: Path, top: int, deep: int) -> tuple[str, dict]:
    cc = CellClass(reports / "synth_libcell_class.tsv")

    hist_all = parse_histogram(reports / "synth_logic_levels.rep")
    hist_nob = parse_histogram(reports / "synth_logic_levels_nobuf.rep")
    detail = parse_detail(reports / "synth_logic_levels_detail.rep")

    path_srcs = []
    for name in ("synth_deep_paths.rep", "syn_timing.rep", "syn_timing.map.rep"):
        f = reports / name
        if f.is_file():
            got = parse_timing_report(f)
            if got:
                path_srcs.append((name, got))

    if not path_srcs and not detail and not hist_all:
        raise Refuse(
            "no synthesis depth source parsed under " + str(reports) + "\n"
            "  looked for: synth_logic_levels.rep, synth_logic_levels_nobuf.rep,\n"
            "              synth_logic_levels_detail.rep, synth_deep_paths.rep,\n"
            "              syn_timing.rep\n"
            "  The first three are written by hooks/post_synth.tcl. A run made\n"
            "  before that hook existed has none of them; re-run synthesis, or\n"
            "  point --run-dir at a run that has them.")

    allp = [p for _, ps in path_srcs for p in ps]
    if path_srcs and not allp:
        raise Refuse("a path report was found but parsed to ZERO paths -- the "
                     "report format has changed; refusing to print an empty "
                     "table that would read as coverage")
    if detail == [] and (reports / "synth_logic_levels_detail.rep").is_file():
        raise Refuse("synth_logic_levels_detail.rep exists but parsed to ZERO "
                     "endpoints -- refusing rather than reporting no depth")

    for p in allp:
        p["a"] = analyse_path(p, cc)

    # one shared hierarchy frame for every table, so buckets are comparable
    frame = [owner_parts(inst_of(p["startpoint"])) for p in allp]
    frame += [owner_parts(inst_of(p["endpoint"])) for p in allp]
    frame += [owner_parts(inst_of(r["endpoint"])) for r in detail[:2000]]
    frame += [owner_parts(inst_of(r["startpoint"])) for r in detail[:2000]]
    pref, _ = strip_common([f for f in frame if f])
    pl = len(pref)

    o = Out()
    o.p("=" * 100)
    o.p("SYNTHESIS LOGIC DEPTH -- " + run.name)
    o.p("=" * 100)
    o.p(f"run          {run}")
    o.p(f"reports      {reports}")
    o.p(f"cell classes {cc.src}")
    o.p(f"hierarchy    common prefix stripped from every bucket: "
        f'{"/".join(pref) if pref else "(none)"}')
    if not cc.exact:
        o.p("             WARNING: buffer/inverter counts below are a NAME "
            "GUESS, not the tool's")
        o.p("             own attribute. tcbn65lp spells a clock inverter "
            "CKND<n> and a clock")
        o.p("             NAND2 CKND2D<n>; the guess can confuse them. Treat "
            "bi= columns as")
        o.p("             indicative until synth_libcell_class.tsv is present.")
    o.p("thresholds   deep >= %d non-buffer levels; LOAD if buf/inv >= %d%% of "
        "levels," % (DEEP_LEVELS, BI_FRACTION * 100))
    o.p("             or 3 slowest stages >= %d%% of the data path, or a stage "
        "drives >= %.0f fF," % (TOP3_SHARE * 100, LOAD_HI_FF))
    o.p("             or a stage fans out to >= %d." % FANOUT_HI)

    js: dict = {"run": str(run), "cell_class_source": cc.src,
                "hierarchy_prefix": pref, "thresholds": {
                    "deep_levels": DEEP_LEVELS, "bi_fraction": BI_FRACTION,
                    "top3_share": TOP3_SHARE, "load_hi_ff": LOAD_HI_FF,
                    "fanout_hi": FANOUT_HI}}

    # -- 1 ------------------------------------------------------------------
    o.h("1  DESIGN-WIDE DEPTH DISTRIBUTION")
    if not hist_all and not hist_nob:
        o.p("NOT MEASURED -- no report_logic_levels_histogram output in this run.")
        o.p("This is the only source that covers endpoints which MEET timing.")
    for label, h in (("all cells", hist_all),
                     ("buffers and inverters NOT counted", hist_nob)):
        if not h:
            continue
        o.sh(f"{label}   [{h['file']}]")
        o.p(f"view {h['view']}    endpoints {h['endpoints']}    "
            f"worst depth {h['worst_levels']} levels")
        for b in h["bars"]:
            bar = "#" * int(round(b["pct"] / 2))
            o.p(f"  {b['lo']:>4} - {b['hi']:<4} {b['n']:>8}  {b['pct']:>5.1f}%  {bar}")
    if hist_all and hist_nob and hist_all["worst_levels"] and hist_nob["worst_levels"]:
        d = hist_all["worst_levels"] - hist_nob["worst_levels"]
        o.p("")
        o.p(f"DEPTH vs LOAD, design scale: the worst path is "
            f"{hist_all['worst_levels']} levels with buffers counted and "
            f"{hist_nob['worst_levels']} without.")
        o.p(f"  {d} of its levels ({d / hist_all['worst_levels']:.0%}) are "
            f"drive, not logic. The remaining {hist_nob['worst_levels']} are "
            f"structural and only RTL moves them.")
    js["histogram_all"] = hist_all
    js["histogram_nobuf"] = hist_nob

    # -- 2 ------------------------------------------------------------------
    o.h("2  DEEPEST ENDPOINTS  (whether or not they meet timing)")
    if not detail:
        o.p("NOT MEASURED -- no synth_logic_levels_detail.rep.")
        o.p("Without it, the only paths visible are the ones that are already")
        o.p("failing or nearly failing, and a 90-level path with 140 ns of")
        o.p("slack -- the one that fails after CTS -- is invisible.")
    else:
        det = sorted(detail, key=lambda r: -r["levels"])
        o.p(f"population {len(detail)} endpoints "
            f"(threshold applied by the tool; see the report header)")
        o.p(f"worst {det[0]['levels']} levels    median of this population "
            f"{statistics.median([r['levels'] for r in detail]):.0f}")
        o.p("")
        o.p(f"{'lvl':>4}  {'group':<26}  endpoint")
        o.p(f"{'':>4}  {'':<26}  <- startpoint")
        seen: set[str] = set()
        shown = 0
        for r in det:
            if r["endpoint"] in seen:
                continue
            seen.add(r["endpoint"])
            o.p(f"{r['levels']:>4}  {elide(r['group'], 26):<26}  "
                f"{elide(r['endpoint'], 110)}")
            o.p(f"{'':>4}  {'':<26}  <- {elide(r['startpoint'], 107)}")
            shown += 1
            if shown >= top:
                break
        js["deepest_endpoints"] = det[:top]
        js["endpoint_population"] = len(detail)

        # depth by cost group -- a group whose worst is deep is a group whose
        # margin is structural, whatever its slack says today
        o.sh("depth by cost group   (worst / median / endpoints in this population)")
        bygrp: dict[str, list[int]] = {}
        for r in detail:
            bygrp.setdefault(r["group"], []).append(r["levels"])
        rows = sorted(bygrp.items(), key=lambda kv: -max(kv[1]))
        o.p(f"{'worst':>5} {'med':>5} {'n':>7}  cost group")
        for g, v in rows:
            o.p(f"{max(v):>5} {statistics.median(v):>5.0f} {len(v):>7}  {g}")
        js["depth_by_cost_group"] = {g: {"worst": max(v),
                                         "median": statistics.median(v),
                                         "n": len(v)} for g, v in rows}

    # -- 2b -----------------------------------------------------------------
    # TWO INDEPENDENT LEVEL COUNTS APPEAR IN THIS DOCUMENT and they must be
    # reconciled rather than quietly mixed: the tool's histogram number, and
    # the one this script derives by counting rows in a full path report. They
    # are not the same quantity and the difference has two separate causes:
    #
    #   a fixed definitional offset, which shows up as a CONSTANT delta on the
    #   same path; and
    #
    #   path selection -- the histogram reports a depth per ENDPOINT, while
    #   `report_timing` returns the worst-SLACK path to that endpoint. When the
    #   deepest path is not the slowest, the delta is larger, and that is
    #   information, not error.
    #
    # Reported per source file, because a report generated by `-to <deepest
    # endpoint>` isolates the first cause and a slack-ordered one does not.
    if detail and allp:
        by_ep: dict[str, int] = {}
        for r in detail:
            by_ep.setdefault(r["endpoint"], r["levels"])
        o.sh("level-count reconciliation  (tool histogram vs counted cells)")
        js["level_count_delta"] = {}
        for name, ps in path_srcs:
            ds = [(by_ep[p["endpoint"]] - p["a"]["levels"], p)
                  for p in ps if p["endpoint"] in by_ep]
            if not ds:
                o.p(f"{name}: no endpoint in common with the histogram -- "
                    f"unreconciled.")
                continue
            vals = sorted({d for d, _ in ds})
            js["level_count_delta"][name] = vals
            o.p(f"{name}: {len(ds)} endpoints in common, "
                f"tool - counted = {vals[0] if len(vals) == 1 else vals}")
            if len(vals) == 1:
                o.p(f"  CONSTANT. The two definitions differ by exactly "
                    f"{vals[0]} on the same path and by nothing else.")
            else:
                below = [d for d, _ in ds if d < vals[0] + 0]
                o.p(f"  spread {vals[0]}..{vals[-1]}. A delta above the "
                    f"definitional offset means the DEEPEST path to that")
                o.p(f"  endpoint is deeper than its SLOWEST one -- which is "
                    f"the whole reason section 2 exists.")
                neg = [(d, p) for d, p in ds if d < 1]
                if neg:
                    o.p(f"  {len(neg)} of {len(ds)} endpoints have a counted "
                        f"path DEEPER than the histogram's figure for them,")
                    o.p(f"  so that figure is the tool's per-endpoint depth and "
                        f"NOT a guaranteed maximum. Worst:")
                    for d, p in sorted(neg, key=lambda t: t[0])[:3]:
                        o.p(f"    tool {by_ep[p['endpoint']]:>3}  counted "
                            f"{p['a']['levels']:>3}  {elide(p['endpoint'], 78)}")
        o.p("")
        o.p("Sections 1 and 2 print the TOOL's number. Sections 3 and 4 print "
            "the count of")
        o.p("combinational cells between the launch and the capture element, "
            "which is the")
        o.p("number `report_qor -levels_of_logic` calls 'No of gates on "
            "Critical Path'.")

    # -- 3 ------------------------------------------------------------------
    o.h("3  WORST PATHS BY SLACK, WITH THEIR DEPTH")
    if not allp:
        o.p("NOT MEASURED -- no report_timing output parsed.")
    else:
        for name, ps in path_srcs:
            o.sh(f"{name}   ({len(ps)} paths)")
            o.p(f"{'#':>3} {'slack':>7} {'lvl':>4} {'log':>4} {'bi':>3} "
                f"{'top3':>5} {'maxfF':>6} {'maxFO':>5}  {'verdict':<11} "
                f"{'group':<20} endpoint")
            for p in sorted(ps, key=lambda p: p["slack_ps"])[:top]:
                a = p["a"]
                o.p(f"{p['rank']:>3} {p['slack_ps']:>7} {a['levels']:>4} "
                    f"{a['logic_levels']:>4} {a['buf_inv_levels']:>3} "
                    f"{a['top3_share']:>5.0%} {a['max_load_ff']:>6.1f} "
                    f"{a['max_fanout']:>5}  {a['verdict']:<11} "
                    f"{elide(p['group'], 20):<20} {elide(p['endpoint'], 70)}")
        js["paths"] = [{
            "source": p["source"], "rank": p["rank"], "slack_ps": p["slack_ps"],
            "group": p["group"], "met": p["met"],
            "startpoint": p["startpoint"], "endpoint": p["endpoint"],
            **{k: v for k, v in p["a"].items()
               if k not in ("level_insts", "level_cells")},
        } for p in allp]

    # -- 4 ------------------------------------------------------------------
    o.h("4  PATH ANATOMY  (deepest first) -- why each path is long")
    if not allp:
        o.p("NOT MEASURED.")
    else:
        for p in sorted(allp, key=lambda p: -p["a"]["levels"])[:top]:
            a = p["a"]
            o.p("")
            o.p(f"[{p['source']} path {p['rank']}]  {a['levels']} levels  "
                f"slack {p['slack_ps']} ps  {p['group']}  -> {a['verdict']}")
            o.p(f"  from  {p['startpoint']}")
            o.p(f"  to    {p['endpoint']}")
            o.p(f"  why   {a['verdict_because']}")
            o.p(f"  fix   {a['fix']}")
            o.p(f"  data path {a['stage_ps_total']:.0f} ps over {a['levels']} "
                f"levels, median stage {a['stage_ps_median']:.0f} ps, "
                f"worst {a['stage_ps_max']:.0f} ps")
            if a["worst_stage"]:
                o.p(f"  slowest stage  {elide(a['worst_stage'], 110)}")
            if a["worst_load_stage"]:
                o.p(f"  heaviest load  {elide(a['worst_load_stage'], 110)}")
            segs = segment(a["level_insts"], 2, pl)
            o.p("  walks through (levels per block, in order):")
            for chunk in _wrap("  ->  ".join(f"{b} x{n}" for b, n in segs),
                                92):
                o.p("      " + chunk)
            tot = {}
            for b, n in segs:
                tot[b] = tot.get(b, 0) + n
            o.p("  levels by block:")
            for b, n in sorted(tot.items(), key=lambda kv: -kv[1]):
                o.p(f"    {n:>4}  {n / a['levels']:>5.0%}  {b}")
            top1: dict[str, int] = {}
            for inst in a["level_insts"]:
                b = bucket(owner_parts(inst)[pl:], 1)
                top1[b] = top1.get(b, 0) + 1
            o.p("  levels by TOP-LEVEL block:")
            for b, n in sorted(top1.items(), key=lambda kv: -kv[1]):
                o.p(f"    {n:>4}  {n / a['levels']:>5.0%}  {b}")

    # -- 5 ------------------------------------------------------------------
    o.h("5  HIERARCHY ROLLUP -- who owns the depth")
    o.p("Two different questions, two tables. The first is 'whose endpoints are")
    o.p("deep' and covers every endpoint. The second is 'whose GATES the deep")
    o.p("paths are made of' and covers only the paths that were reported in")
    o.p("full -- a path can end in one block and be built almost entirely of")
    o.p("another's logic, which is exactly the case this design has.")
    if detail:
        for d in (1, 2):
            o.sh(f"endpoints owned, by block   (hierarchy depth {d}, "
                 f"synthesis clock-gate wrappers folded into their parent)")
            own: dict[str, list[int]] = {}
            for r in detail:
                b = bucket(owner_parts(inst_of(r["endpoint"]))[pl:], d)
                own.setdefault(b, []).append(r["levels"])
            rows = sorted(own.items(), key=lambda kv: (-max(kv[1]), -len(kv[1])))
            o.p(f"{'worst':>5} {'med':>5} {'n':>7}  block")
            for b, v in rows[:top]:
                o.p(f"{max(v):>5} {statistics.median(v):>5.0f} {len(v):>7}  {b}")
            if len(rows) > top:
                rest = rows[top:]
                o.p(f"{max(max(v) for _, v in rest):>5} {'':>5} "
                    f"{sum(len(v) for _, v in rest):>7}  "
                    f"... and {len(rest)} more blocks, worst-first order "
                    f"continues")
            if d == 2:
                js["endpoints_by_block"] = {b: {"worst": max(v), "n": len(v)}
                                            for b, v in own.items()}
    if allp:
        for d in (1, 2):
            o.sh(f"levels CONTRIBUTED, by block (hierarchy depth {d}), summed "
                 f"over the reported paths")
            contrib: dict[str, int] = {}
            tot = 0
            for p in allp:
                for inst in p["a"]["level_insts"]:
                    b = bucket(owner_parts(inst)[pl:], d)
                    contrib[b] = contrib.get(b, 0) + 1
                    tot += 1
            o.p(f"{'levels':>7} {'share':>6}  block            "
                f"(total {tot} levels over {len(allp)} paths)")
            for b, n in sorted(contrib.items(), key=lambda kv: -kv[1])[:top]:
                o.p(f"{n:>7} {n / tot:>6.1%}  {b}")
            js[f"levels_by_block_d{d}"] = contrib
            if d == 2:
                js["levels_by_block"] = contrib
                js["levels_total"] = tot
        o.p("")
        o.p("The depth-1 table is the one to read first: it says how much of "
            "the design's worst")
        o.p("logic depth belongs to each top-level block, which is the "
            "question 'whose cone is")
        o.p("this' actually asks. Depth 2 says which part of that block.")

    o.p("")
    o.p("=" * 100)
    return o.text(), js


def _wrap(s: str, w: int) -> list[str]:
    out, cur = [], ""
    for word in s.split(" "):
        if not word:
            continue
        if cur and len(cur) + 1 + len(word) > w:
            out.append(cur)
            cur = word
        else:
            cur = (cur + " " + word) if cur else word
    if cur:
        out.append(cur)
    return out or [""]


# ---------------------------------------------------------------------------
# selftest -- every table must be shown able to say "not measured", and every
# verdict must be shown reachable. A classifier that only ever says one thing
# is not a classifier.
# ---------------------------------------------------------------------------
FIX_HDR = """============================================================
  Generated by:           Genus(TM) Synthesis Solution 21.15
  Module:                 t
============================================================
"""


def _mk_path(rank, slack, group, start, end, stages):
    """stages: list of (inst, cell, fanout, load, delay)"""
    L = [f"Path {rank}: {'MET' if slack >= 0 else 'VIOLATED'} ({slack} ps) "
         f"Setup Check with Pin {end}/CP->D",
         f"          Group: {group}",
         f"     Startpoint: (R) {start}/CP",
         f"          Clock: (R) clk",
         f"       Endpoint: (R) {end}/D",
         f"          Clock: (R) clk",
         "      Data Path:-    9000",
         "#" + "-" * 60]
    arr = 0
    L.append(f"  {start}/CP  -  -  R  (arrival)  PD_TOP  4  -  120  0  0  (-,-)")
    L.append(f"  {start}/Q  -  CP->Q  R  DFCND1  PD_TOP  4  15.9  221  100  100  (-,-)")
    arr = 100
    for inst, cell, fo, load, dly in stages:
        arr += dly
        L.append(f"  {inst}/ZN  -  A1->ZN  R  {cell}  PD_TOP  {fo}  {load}  100 "
                 f" {dly}  {arr}  (-,-)")
    L.append(f"  {end}/D  -  -  R  DFCNQD1  PD_TOP  1  -  -  0  {arr}  (-,-)")
    L.append("#" + "-" * 60)
    return "\n".join(L)


def selftest() -> int:
    ok = True

    def check(desc, cond, extra=""):
        nonlocal ok
        print(f"  {'PASS' if cond else 'FAIL'}  {desc}" + (f"   {extra}" if extra else ""))
        if not cond:
            ok = False

    print("synth_depth_report --selftest")
    print("\n[A] refusals -- a report over nothing must exit non-zero")
    with tempfile.TemporaryDirectory() as td:
        run = Path(td) / "run"
        (run / "reports").mkdir(parents=True)
        try:
            build(run, run / "reports", 10, DEEP_LEVELS)
            check("empty run dir refuses", False, "it did NOT refuse")
        except Refuse as e:
            check("empty run dir refuses", True, str(e).splitlines()[0][:60])

        (run / "reports" / "syn_timing.rep").write_text(FIX_HDR + "\nno paths here\n")
        try:
            build(run, run / "reports", 10, DEEP_LEVELS)
            check("path report with zero paths refuses", False, "it did NOT refuse")
        except Refuse as e:
            check("path report with zero paths refuses", True,
                  str(e).splitlines()[0][:60])

        (run / "reports" / "syn_timing.rep").write_text(
            FIX_HDR + _mk_path(1, 5, "g", "b/a_reg", "b/b_reg",
                               [("b/g1", "ND2D1", 2, 10.0, 100)]))
        (run / "reports" / "synth_logic_levels_detail.rep").write_text(
            "DETAIL REPORT (Startpoint, Endpoint, Logic Level, Cost-Group)\n"
            "-----\n*\n")
        try:
            build(run, run / "reports", 10, DEEP_LEVELS)
            check("empty detail table refuses", False, "it did NOT refuse")
        except Refuse as e:
            check("empty detail table refuses", True, str(e).splitlines()[0][:60])

    print("\n[B] the classifier must be able to reach every verdict")
    cc = CellClass(None)
    cases = {
        # 60 small even stages, no buffers, no load -> DEPTH
        "DEPTH": [(f"blk/g{i}", "ND2D1", 2, 10.0, 100) for i in range(60)],
        # 6 stages, one enormous -> LOAD (top3 share)
        "LOAD": [("blk/g0", "ND2D1", 2, 10.0, 100)] * 5 +
                [("blk/gbig", "ND2D1", 40, 200.0, 5000)],
        # 90 stages of which 40 are buffers: 50 levels of real logic AND a
        # buffer fraction over the threshold -> both findings at once
        "DEPTH+LOAD": [(f"blk/g{i}", "BUFFD4" if i < 40 else "ND2D1", 2, 10.0, 100)
                       for i in range(90)],
        # 10 even stages -> SHORT
        "SHORT": [(f"blk/g{i}", "ND2D1", 2, 10.0, 100) for i in range(10)],
    }
    for want, stages in cases.items():
        txt = FIX_HDR + _mk_path(1, 5, "r2r_clk", "blk/a_reg", "blk/b_reg", stages)
        with tempfile.TemporaryDirectory() as td:
            f = Path(td) / "syn_timing.rep"
            f.write_text(txt)
            ps = parse_timing_report(f)
            got = analyse_path(ps[0], cc)["verdict"] if ps else "(no path parsed)"
        check(f"verdict {want} is reachable", got == want, f"got {got}")

    print("\n[C] level counting must exclude the launch and capture elements")
    txt = FIX_HDR + _mk_path(1, 5, "r2r_clk", "blk/a_reg", "blk/b_reg",
                             [(f"blk/g{i}", "ND2D1", 2, 10.0, 100) for i in range(7)])
    with tempfile.TemporaryDirectory() as td:
        f = Path(td) / "syn_timing.rep"
        f.write_text(txt)
        a = analyse_path(parse_timing_report(f)[0], CellClass(None))
    check("7 combinational stages count as 7 levels", a["levels"] == 7,
          f"got {a['levels']}")

    print("\n[D] hierarchy splitting must dissolve ungrouped names")
    check("clock-gate wrapper joins split too",
          canon_parts("u_a_cg_RC_CG_HIER_INST3/g1") ==
          ["u_a", "cg_RC_CG_HIER_INST3", "g1"],
          str(canon_parts("u_a_cg_RC_CG_HIER_INST3/g1")))
    check("and are folded out of a bucket",
          bucket(canon_parts("u_a_cg_RC_CG_HIER_INST3/g1")[:-1], 2) == "u_a",
          bucket(canon_parts("u_a_cg_RC_CG_HIER_INST3/g1")[:-1], 2))
    got = canon_parts("u_top_u_soc_u_soc/u_net/u_eth_0_u_inner_u_servo/g10")
    want = ["u_top", "u_soc", "u_soc", "u_net", "u_eth_0", "u_inner", "u_servo", "g10"]
    check("'_u_' joins are split back into levels", got == want, f"got {got}")
    got = canon_parts("a/gen_x.u_b/g1")
    check("generate scopes split on '.'", got == ["a", "gen_x", "u_b", "g1"],
          f"got {got}")

    print("\n[E] segmentation must preserve ORDER and re-entry")
    segs = segment(["A/x/g1", "A/x/g2", "B/y/g3", "A/x/g4"], 2, 0)
    check("a path that leaves a block and returns shows twice",
          segs == [("A/x", 2), ("B/y", 1), ("A/x", 1)], f"got {segs}")

    print("\n[F] the buffer count must change when the class table is supplied")
    with tempfile.TemporaryDirectory() as td:
        t = Path(td) / "synth_libcell_class.tsv"
        # declare ND2D1 a buffer -- absurd, but it proves the table is READ and
        # not silently ignored in favour of the name regex
        t.write_text("ND2D1\t1\t0\t0\t0\nBUFFD4\t0\t0\t0\t0\n")
        exact = CellClass(t)
    check("class table is read", exact.exact, exact.src)
    check("class table overrides the name guess",
          exact.is_bi("ND2D1") and not exact.is_bi("BUFFD4"))
    check("fallback guess disagrees with it (so the table matters)",
          not CellClass(None).is_bi("ND2D1") and CellClass(None).is_bi("BUFFD4"))

    print("\n[G] histogram parsing")
    with tempfile.TemporaryDirectory() as td:
        f = Path(td) / "h.rep"
        f.write_text(
            " ------\n| Number of Logic Levels |     Number(%)   | Histogram \n"
            " ------\n"
            "|        0  ->   18      |  90339(82.7)    | ***\n"
            "|       76  ->   94      |   1221( 1.1)    | *\n"
            " ------\n"
            "|       90(worst)       | 109257          | total end points\n"
            " ------\n  View: 'analysis_view:t/default_emulate_view'\n")
        h = parse_histogram(f)
    check("bars parsed", h and len(h["bars"]) == 2, str(h and len(h["bars"])))
    check("worst depth parsed", h and h["worst_levels"] == 90)
    check("endpoint count parsed", h and h["endpoints"] == 109257)
    check("view recorded", h and "default_emulate_view" in (h["view"] or ""))
    with tempfile.TemporaryDirectory() as td:
        f = Path(td) / "h.rep"
        f.write_text("nothing resembling a histogram\n")
        check("a non-histogram parses to None, not to zeros",
              parse_histogram(f) is None)

    print("\n[H] end to end on a synthetic run -- the report must contain the "
          "numbers")
    with tempfile.TemporaryDirectory() as td:
        run = Path(td) / "run"
        rep = run / "reports"
        rep.mkdir(parents=True)
        (rep / "synth_logic_levels.rep").write_text(
            "|       0  ->   18      |  90339(82.7)    | *\n"
            "|      90(worst)       | 109257          | total end points\n"
            "  View: 'analysis_view:t/v'\n")
        (rep / "synth_logic_levels_nobuf.rep").write_text(
            "|       0  ->   18      |  90339(82.7)    | *\n"
            "|      61(worst)       | 109257          | total end points\n"
            "  View: 'analysis_view:t/v'\n")
        (rep / "synth_logic_levels_detail.rep").write_text(
            "DETAIL REPORT (Startpoint, Endpoint, Logic Level, Cost-Group)\n"
            "-----\n"
            "u_a_u_cpu/x_reg[0]/CP u_a_u_tl/y_reg[14]/D  90 r2r_clk\n"
            "u_a_u_cpu/x_reg[1]/CP u_a_u_cpu/z_reg[2]/D  30 r2r_clk\n"
            "-----\n")
        (rep / "syn_timing.rep").write_text(
            FIX_HDR + _mk_path(1, 0, "r2r_clk", "u_a_u_cpu/x_reg[0]",
                               "u_a_u_tl/y_reg[14]",
                               [(f"u_a_u_cpu/g{i}", "ND2D1", 2, 10.0, 100)
                                for i in range(50)] +
                               [(f"u_a_u_tl/g{i}", "ND2D1", 2, 10.0, 100)
                                for i in range(12)]))
        txt, js = build(run, rep, 10, DEEP_LEVELS)
    check("worst depth 90 appears", "90" in txt)
    check("the design-scale DEPTH vs LOAD line is emitted",
          "DEPTH vs LOAD, design scale" in txt)
    check("the deep endpoint is listed", "y_reg[14]" in txt)
    check("levels-by-block rollup was produced", "levels_by_block" in js)
    check("the CPU block carries more levels than the TideLink block",
          max(js["levels_by_block"].items(), key=lambda kv: kv[1])[0].endswith("u_cpu"),
          str(js["levels_by_block"]))
    check("the path anatomy names both blocks",
          "u_cpu x50" in txt and "u_tl x12" in txt)

    print("\n" + ("SELFTEST PASS" if ok else "SELFTEST FAIL"))
    return 0 if ok else 1


# ---------------------------------------------------------------------------
def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[1],
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--run-dir", help="a flow run directory (has reports/)")
    ap.add_argument("--reports-dir", help="override <run>/reports")
    ap.add_argument("--out-dir", help="where to write (default: the reports dir)")
    ap.add_argument("--top", type=int, default=25, help="rows per table")
    ap.add_argument("--deep", type=int, default=None,
                    help="levels at or above which a path is 'deep'")
    ap.add_argument("--stdout", action="store_true", help="also print the report")
    ap.add_argument("--selftest", action="store_true")
    global DEEP_LEVELS
    a = ap.parse_args(argv)

    if a.selftest:
        return selftest()
    if not a.run_dir and not a.reports_dir:
        ap.error("--run-dir or --reports-dir is required")

    if a.deep is not None:
        DEEP_LEVELS = a.deep
    else:
        a.deep = DEEP_LEVELS

    run = Path(a.run_dir).resolve() if a.run_dir else Path(a.reports_dir).resolve().parent
    reports = Path(a.reports_dir).resolve() if a.reports_dir else run / "reports"
    if not reports.is_dir():
        print(f"REFUSED: {reports} is not a directory", file=sys.stderr)
        return 2
    out = Path(a.out_dir).resolve() if a.out_dir else reports
    out.mkdir(parents=True, exist_ok=True)

    try:
        txt, js = build(run, reports, a.top, a.deep)
    except Refuse as e:
        print("REFUSED: " + str(e), file=sys.stderr)
        return 2

    (out / "synth_depth.rep").write_text(txt)
    (out / "synth_depth.json").write_text(json.dumps(js, indent=1, default=str))
    if a.stdout:
        sys.stdout.write(txt)
    print(f"OK: {out/'synth_depth.rep'}")
    print(f"OK: {out/'synth_depth.json'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
