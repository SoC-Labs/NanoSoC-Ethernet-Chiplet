#!/usr/bin/env python3
"""Pre-P&R floorplan hazard checker.  No EDA tool, no licence, seconds to run.

Copyright 2026, SoC Labs (www.soclabs.org)

Why
---
Four distinct floorplan-induced defects were each found only AFTER a 2.5-hour
place/CTS/route run on 2026-08-21/22.  Every one of them was derivable in
seconds from `floorplan.tcl` + the macro LEFs + `power_plan.tcl`.  This closes
that gap: it parses those three inputs as TEXT (no `get_db`, no Innovus, no
Calibre) and reports which macros trip which hazard class, with the arithmetic
and the smallest clearing move.

The four classes, all established by measurement on 2026-08-21/22 -- see
`docs/` and commit 78dac42 -- and NOT re-derived here:

  1  M9 TAP-FLOOR STRADDLE -> METAL SHORT.  Vertical M4 PG taps are pinned to
     the M9 ladder at absolute y = core_y_lo + start_offset + k*pitch.  A
     Y-flipped (MX / R180) data macro whose TOP edge lands inside one of those
     bands shorts to the tap.  Proven both ways in 78dac42.

  2  M9 STRIPE-BAND STRADDLE -> M9.W.1 minimum width.  Same geometry, any
     orientation, either edge.  Two macros violate at HEAD.

  3  PIN-GRID PHASE COLLISION -> M4.S.2.1 wide-metal spacing.  A top-level M4
     riser and a macro's own 0.35um M4 PG pin merge into one polygon when their
     x offset is below the pin width; the union then exceeds the wide-metal
     width breakpoint and the pin's (previously legal) gap to the macro's
     internal M4 obstruction becomes a violation.

  4  MACRO EDGE IN A LIVE SIGNAL CHANNEL -> Regular Wire DRC.  This entry used
     to read "NOT statically derivable" and argue it from channel width.  That
     is refuted for one half of the class and still true for the other, so the
     class is now split and each half says which it is.

     4a MACRO PIN EDGE OFF THE ESCAPE-LAYER TRACK GRID.  STATICALLY DERIVABLE,
        and detected here.  A macro whose cell obstructs its cut layers over
        100% of its footprint can only be reached PLANAR: the router carries
        the pin out on the metal beneath the topmost obstructed cut layer and
        makes its first layer change OUTSIDE the footprint.  That first via has
        to land on a track of the escape metal -- whose preferred direction is
        parallel to the pin edge, so its tracks are spaced along the escape
        normal -- and its cut has to clear the macro's own cut obstruction by
        the cut layer's spacing.  Whether it can is decided by ONE number: the
        PHASE of the pin edge against the escape layer's track grid.  Placement
        y sets that phase; the track pitch, the track origin, the cut extent
        and the cut spacing are all read out of the technology LEF at run time.
        Three files this script already opens, no router, no routed database.

        Half a pitch off grid, the first track outside the footprint is too
        close for the cut, so the cheapest legal escape costs an extra track --
        and a pin that does not find one takes the last track INSIDE the
        footprint, where the cut layer is obstructed.  That is 5 stage-owned
        DRC violations on 2026-08-25, found one hour into a 2h38m route.  See
        commit 2cd12a4 and the CLASS 4a section below.

     4b THE REST OF CLASS 4: a macro edge moving into a channel a previous
        router has already filled.  STILL NOT DERIVABLE, and nothing here
        claims to detect it.  See the CLASS 4 section for what is reported
        instead (a channel census and, with --against, a differential).

     WHY THE OLD TEXT WAS WRONG, AND WHERE IT IS STILL RIGHT.  It argued from
     CHANNEL WIDTH: the 2026-08-21 case moved into a channel that got WIDER,
     8.64 -> 12.74 um, so no channel-narrowing metric can predict it.  That
     argument is correct and it is still the whole reason 4b is undetectable.
     It was never an argument about 4a, which does not look at the channel at
     all -- it looks at the pin edge and the track grid, neither of which the
     old reasoning mentions.  Width was the wrong question, not an
     unanswerable one.

Detection quality -- read this before trusting a green
------------------------------------------------------
  class 1  RELIABLE   exact arithmetic, reproduces both proven cases
  class 2  RELIABLE   exact arithmetic, reproduces both current violators and
                      both of the fixes that were actually applied (-1.100um,
                      -1.150um) to the micron
  class 3  OVER-APPROXIMATING.  Reproduces 4/4 of the macros that produced the
                      22 M4.S.2.1 markers in the 2026-08-17 signoff DRC (no
                      false negatives), but also flags pairs that produced
                      none.  Treat a class-3 flag as "re-measure on the PG
                      probe", not as "this will fail".
  class 4a RELIABLE   exact arithmetic on the escape layer's track grid, all of
                      it read from the technology LEF at run time.  Proven in
                      both directions against three PINNED revisions: the one
                      before the defect (0 flagged), the one that carried it
                      (exactly the 2 macros whose pins failed), and the one
                      that fixed it (0 flagged).  See --selftest section 4a.
  class 4b NOT DETECTED.  Reported as a channel census and (with --against) a
                      differential, both labelled.  Do not read either as a
                      class-4 verdict.

Vacuity
-------
This repository has been bitten repeatedly by checks that measured nothing and
passed.  Every stage here emits an explicit census (macros parsed, patterns
resolved, LEFs read, bands computed, pin pairs and macro pairs tested) and the
run exits 2 -- NOT 0 -- if any of them is zero, or if an input cannot be
resolved.  Exit 0 means the geometry was measured and is clean.

How it is invoked
-----------------
It runs by itself, as a prerequisite of `place`.  Until 2026-08-25 it ran
nowhere: no make target, no `.mk`, no workflow -- measured by grep, the only
references to this file in the whole tree were a comment in floorplan.tcl, a
vendor-guard allowlist entry and its own fixture README.  ASIC/floorplan-hazards.mk
is the wiring, and it names this file's inputs explicitly so the gate reads the
same floorplan and power plan the stage is about to source.

    make -C ASIC/eth-chiplet floorplan-hazards            # ~3 s
    make -C ASIC/eth-chiplet floorplan-hazards-selftest   # both directions
    make -C ASIC/eth-chiplet place                        # runs the gate first

Usage
-----
    # MEM_BASE and TSMC_65_HOME must be set: run under the project environment
    # (ASIC/common.mk exports both), or pass --lef / --tech-lef explicitly --
    # which really does replace them, and is exercised by a test.
    scripts/ci/check_floorplan_hazards.py                     # check the worktree
    scripts/ci/check_floorplan_hazards.py --selftest          # ground-truth validation
    scripts/ci/check_floorplan_hazards.py --floorplan git:78dac42^
    scripts/ci/check_floorplan_hazards.py --against git:78dac42^   # differential
    scripts/ci/check_floorplan_hazards.py --json out.json
    scripts/ci/check_floorplan_hazards.py --strict            # class 3 fails too

What fails the gate, and why not everything does
------------------------------------------------
A gate that is red for a reason everybody already knows is benign gets ignored,
and then it is not a gate.  This one had that problem the day it was wired in:
class 3 is OVER-APPROXIMATING by its own header, it stands at 8 on a clean
worktree, and it was making the whole run exit 1.

So the classes are split by what their flags MEAN, not by how bad the DRC would
be:

    HARD (exit 1)      class 1, class 2, class 4a -- exact arithmetic, no false
                       positives observed, each one reproduces a defect that
                       really happened and each one prints the move that clears
                       it.  A flag here is a thing to fix before P&R.
    ADVISORY (exit 0)  class 3 -- reproduces every real marker but also flags
                       pairs that produced none.  Printed in full, counted in
                       the summary, and named in the verdict line, but it does
                       not fail the run on its own.  `--strict` promotes it.
    NOT A VERDICT      class 4b -- a census, never a pass or a fail.

The advisory count is in the verdict line and in the JSON, so a build record
cannot quote a PASS without also carrying the number of advisories it passed
with.

Exit codes
    0   measured, no HARD hazard.  Class-3 advisories may be present and are
        named in the verdict line; `--strict` makes them fail too.
    1   measured, at least one HARD hazard (class 1, class 2 or class 4a)
    2   could not measure (missing input, zero census, cross-check failed)
"""
from __future__ import annotations

import argparse
import bisect
import itertools
import json
import math
import re
import subprocess
import sys
import time
from bisect import bisect_left
import os
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]

DEF_FLOORPLAN = REPO / "ASIC/genus-innovus/scripts/floorplan.tcl"
DEF_POWERPLAN = REPO / "ASIC/genus-innovus/scripts/power_plan.tcl"

# Where macro LEFs live.  READ ONLY -- /research is lab-shared vendor collateral.
#
# SITE PATHS COME FROM THE ENVIRONMENT AND HAVE NO DEFAULT (2026-08-22). They were
# hardcoded here, which broke two things at once: this gate only ran on one host,
# and the literals are vendor site paths in a PUBLIC repository -- the vendor guard
# charges them as `absolute site path`, correctly.
#
# A DEFAULT WOULD NOT HAVE FIXED IT. The first attempt kept the old paths as
# os.environ.get() fallbacks; the guard refused that too, and was right to -- a
# default is still the literal, published in the source. So there is no default:
# the two variables are required, and their values live in the environment
# (ASIC/common.mk exports TSMC_65_HOME) or in the caller's site config.
# LOOKED UP WHEN A GLOB IS ACTUALLY NEEDED, NOT AT IMPORT (2026-08-25).  These
# two were resolved at module scope, which broke the escape hatch the message
# below advertises: `--lef` / `--tech-lef` supply the libraries directly and make
# the globs unreachable, but the import had already refused before argparse ran.
# So `--help` refused too.  Both are now resolved inside the glob builders, which
# the caller only reaches when it did NOT pass the file.
#
# The exit code is 2, not 1.  "I could not measure" and "I measured and found a
# hazard" are different answers and this file's own contract distinguishes them;
# a missing site variable is the first, and it was exiting as the second.
def _site(var, what):
    v = os.environ.get(var)
    if not v:
        print(
            f"{__file__}: {var} is not set.\n"
            f"  It must point at {what}.\n"
            f"  Source the project environment (ASIC/common.mk exports both, and\n"
            f"  `make -C ASIC/eth-chiplet floorplan-hazards` enters through it),\n"
            f"  or pass the libraries explicitly with --lef / --tech-lef.\n"
            f"  Exiting 2.  A check that cannot read its inputs has not passed.",
            file=sys.stderr)
        raise SystemExit(2)
    return v.rstrip("/")


def lef_globs():
    return [
        f'{_site("MEM_BASE", "the precompiled macro-LEF root for this process node")}/*/*.lef',
        str(REPO / "ASIC/romlibs/*/*.lef"),
    ]


def tech_lef_globs():
    return [
        str(REPO / "ASIC/eth-chiplet/build/*/work/*/libs/lef/PRTF_EDI_N65_*.tlef"),
        f'{_site("TSMC_65_HOME", "the group-shared PDK mount")}'
        f"/CMOS/util/lef/PRTF_EDI_65nm_*/PRTF_EDI_N65_*_RDL*.tlef",
    ]
NETLIST_GLOBS = [
    str(REPO / "ASIC/eth-chiplet/build/*/outputs/*_gate_power.v"),
]

# The core box this design is MEASURED to have.  floorplan.tcl computes it from
# the die size and CORE_TO_IO; we recompute it the same way and cross-check
# against this.  A mismatch is a hard stop, not a warning -- every band in the
# report is anchored on core_y_lo.
CORE_BOX_EXPECTED = (205.0, 205.0, 1395.0, 1795.0)

MFG_GRID = 0.005          # LEF MANUFACTURINGGRID, cross-checked against the tech LEF
ELIDE = 52                   # display width for elided instance names
Y_FLIPPED = {"MX", "R180"}   # orientations that mirror in Y
X_FLIPPED = {"MY", "R180"}   # orientations that mirror in X


# --------------------------------------------------------------------------
# small helpers
# --------------------------------------------------------------------------
class Vacuous(Exception):
    """Raised when the checker cannot measure what it claims to measure."""


def read_source(spec: str) -> tuple[str, str]:
    """Read a Tcl input.  `git:<rev>` reads that revision of the SAME path.

    Returns (text, provenance).  Provenance goes in the report -- a number
    whose input is not named is not evidence.
    """
    if spec.startswith("git:"):
        raise Vacuous("read_source: git: specs are resolved by read_tcl_pair")
    p = Path(spec)
    if not p.is_file():
        raise Vacuous(f"input does not exist: {p}")
    return p.read_text(), f"{p} (mtime {time.strftime('%Y-%m-%d %H:%M', time.localtime(p.stat().st_mtime))})"


def read_tcl_pair(fp_spec: str, pp_spec: str) -> tuple[str, str, str, str]:
    """Resolve the floorplan / power_plan pair, honouring `git:<rev>`."""
    def one(spec, repo_rel):
        if spec.startswith("git:"):
            rev = spec[4:]
            r = subprocess.run(["git", "-C", str(REPO), "show", f"{rev}:{repo_rel}"],
                               capture_output=True, text=True)
            if r.returncode != 0 or not r.stdout.strip():
                raise Vacuous(f"git show {rev}:{repo_rel} produced nothing "
                              f"(rc={r.returncode}): {r.stderr.strip()[:200]}")
            sha = subprocess.run(["git", "-C", str(REPO), "rev-parse", "--short", rev],
                                 capture_output=True, text=True).stdout.strip()
            return r.stdout, f"git:{rev} ({sha}):{repo_rel}"
        return read_source(spec)

    fp_txt, fp_prov = one(fp_spec, "ASIC/genus-innovus/scripts/floorplan.tcl")
    pp_txt, pp_prov = one(pp_spec, "ASIC/genus-innovus/scripts/power_plan.tcl")
    return fp_txt, fp_prov, pp_txt, pp_prov


def joined_lines(text: str) -> list[str]:
    """Tcl line continuations folded, so `-die_size` can be found on one line.

    `##` comment lines are NOT stripped -- a trailing `;## comment` on a
    place_macro line is normal in this file and the place_macro regex stops at
    the orientation token, so it is harmless.  But a line that BEGINS with `#`
    or `##` is a comment and must never be parsed as a command.
    """
    out, buf = [], ""
    for raw in text.split("\n"):
        buf += raw
        if buf.endswith("\\"):
            buf = buf[:-1] + " "
            continue
        out.append(buf)
        buf = ""
    if buf:
        out.append(buf)
    return out


def is_command(line: str) -> bool:
    s = line.lstrip()
    return bool(s) and not s.startswith("#")


def snap(v: float, grid: float) -> float:
    return round(round(v / grid) * grid, 6)


CUT_LAYER_RE = re.compile(r"^(VIA\d+|CO|CONT)$")


def is_cut_layer(name: str) -> bool:
    """Name-shape test, used while STREAMING a macro LEF (before the tech LEF's
    layer table is in scope).  It is only ever a shortlist: everything it
    selects is cross-checked against the technology LEF's own TYPE CUT before
    any arithmetic is done on it -- see escape_geometry()."""
    return bool(CUT_LAYER_RE.match(name.upper()))


# --------------------------------------------------------------------------
# floorplan.tcl
# --------------------------------------------------------------------------
PLACE_MACRO = re.compile(
    r"^\s*place_macro\s+\{([^}]*)\}\s+([-\d.eE+]+)\s+([-\d.eE+]+)\s+(\w+)")


def parse_floorplan(text: str) -> dict:
    lines = joined_lines(text)
    cmds = [l for l in lines if is_command(l)]

    m = re.search(r"^\s*set\s+CORE_TO_IO\s+([\d.]+)", "\n".join(cmds), re.M)
    if not m:
        raise Vacuous("floorplan: no `set CORE_TO_IO` found")
    core_to_io = float(m.group(1))

    die = None
    for l in cmds:
        mm = re.search(r"^\s*create_floorplan\b.*?-die_size\s+([\d.]+)\s+([\d.]+)", l)
        if mm:
            die = (float(mm.group(1)), float(mm.group(2)))
            break
    if die is None:
        raise Vacuous("floorplan: no `create_floorplan ... -die_size <w> <h>` found")

    # The IO-driver height that sets the core inset.  Taken from floorplan.tcl's
    # OWN runtime cross-check (`set _expect [expr {135.0 + $CORE_TO_IO}]`) so
    # that this script and the flow cannot disagree about it.
    mm = re.search(r"set\s+_expect\s+\[expr\s*\{\s*([\d.]+)\s*\+\s*\$CORE_TO_IO\s*\}\]", text)
    if not mm:
        raise Vacuous("floorplan: cannot find the `_expect` inset expression "
                      "(135.0 + $CORE_TO_IO); the core box cannot be derived")
    pad_h = float(mm.group(1))
    inset = pad_h + core_to_io
    core = (inset, inset, die[0] - inset, die[1] - inset)

    macros = []
    for l in cmds:
        mm = PLACE_MACRO.match(l)
        if mm:
            macros.append({
                "pattern": mm.group(1).strip(),
                "x": float(mm.group(2)),
                "y": float(mm.group(3)),
                "orient": mm.group(4),
            })

    place_halo = None
    for l in cmds:
        mm = re.search(r"create_place_halo\b.*?-halo_deltas\s+\{([^}]*)\}", l)
        if mm:
            place_halo = [float(v) for v in mm.group(1).split()]
    route_halo = None
    for l in cmds:
        mm = re.search(r"create_route_halo\b", l)
        if mm:
            sp = re.search(r"-space\s+([\d.]+)", l)
            bl = re.search(r"-bottom_layer\s+(\w+)", l)
            tl = re.search(r"-top_layer\s+(\w+)", l)
            route_halo = {
                "space": float(sp.group(1)) if sp else None,
                "bottom_layer": bl.group(1) if bl else None,
                "top_layer": tl.group(1) if tl else None,
            }

    return {
        "core_to_io": core_to_io,
        "pad_height": pad_h,
        "die": die,
        "core": core,
        "macros": macros,
        "place_halo": place_halo,
        "route_halo": route_halo,
    }


# --------------------------------------------------------------------------
# power_plan.tcl
# --------------------------------------------------------------------------
def parse_power_plan(text: str) -> list[dict]:
    out = []
    for l in joined_lines(text):
        if not is_command(l) or "add_stripes" not in l:
            continue
        if not re.match(r"^\s*add_stripes\b", l):
            continue

        def opt(k, cast=float):
            mm = re.search(re.escape(k) + r"\s+([-\w.]+)", l)
            return cast(mm.group(1)) if mm else None

        nets = re.search(r"-nets\s+\{([^}]*)\}", l)
        out.append({
            "nets": nets.group(1).split() if nets else [],
            "layer": opt("-layer", str),
            "direction": opt("-direction", str),
            "width": opt("-width"),
            "spacing": opt("-spacing"),
            "pitch": opt("-set_to_set_distance"),
            "start_offset": opt("-start_offset"),
            "start": opt("-start"),
            "number_of_sets": opt("-number_of_sets", int),
            "raw": l.strip()[:160],
        })
    return out


def m9_bands(stripes: list[dict], core: tuple) -> tuple[list[dict], dict]:
    """The absolute y bands the M9 ladder occupies inside the core.

    Derivation (QUOTED from power_plan.tcl, MEASURED against 78dac42's
    commit message):  first band lower edge = core_y_lo + start_offset,
    band height = -width, then the set's second stripe at +width+spacing,
    the whole set repeating every -set_to_set_distance.
    """
    cand = [s for s in stripes
            if s["layer"] == "M9" and s["direction"] == "horizontal"
            and s["pitch"] and s["width"] and s["start_offset"] is not None]
    if len(cand) != 1:
        raise Vacuous(f"power_plan: expected exactly 1 horizontal M9 add_stripes "
                      f"with a pitch and a start_offset, found {len(cand)}")
    s = cand[0]
    y0, y1 = core[1], core[3]
    bands = []
    k = 0
    while True:
        base = y0 + s["start_offset"] + k * s["pitch"]
        if base > y1:
            break
        bands.append({"lo": round(base, 6), "hi": round(base + s["width"], 6),
                      "set": k, "slot": 0, "net": (s["nets"] or ["?"])[0]})
        if s["spacing"] is not None:
            b2 = base + s["width"] + s["spacing"]
            if b2 <= y1:
                bands.append({"lo": round(b2, 6), "hi": round(b2 + s["width"], 6),
                              "set": k, "slot": 1,
                              "net": (s["nets"] or ["?", "?"])[1] if len(s["nets"]) > 1 else "?"})
        k += 1
    return bands, s


# --------------------------------------------------------------------------
# LEF
# --------------------------------------------------------------------------
def lef_macro_names(path: Path) -> list[str]:
    """Cheap header scan: which MACROs does this LEF define?

    Kept separate from the full parse so a 6 MB vendor LEF that nothing in this
    floorplan uses is never fully read.
    """
    out = []
    try:
        with path.open(errors="replace") as fh:
            for line in fh:
                if line.startswith("MACRO "):
                    out.append(line.split()[1])
    except OSError:
        return []
    return out


def parse_macro_lef(path: Path, want: set[str] | None = None) -> dict[str, dict]:
    """Streaming LEF parse -> {cell: geometry}.

    Line-oriented on purpose.  A `PIN x ... END x` regex with re.DOTALL over a
    multi-megabyte vendor LEF is quadratic; rf_32k.lef alone took 14 s that way.
    """
    cells: dict[str, dict] = {}
    cur = None            # current MACRO dict
    skip = False          # current MACRO is not wanted
    pin = None            # (name, use) of the PIN being read
    in_obs = False
    layer = None
    with path.open(errors="replace") as fh:
        for raw in fh:
            s = raw.strip()
            if not s or s.startswith("#"):
                continue
            if s.startswith("MACRO "):
                name = s.split()[1]
                skip = bool(want) and name not in want
                cur = None if skip else {
                    "cell": name, "w": None, "h": None,
                    "pg": {"POWER": [], "GROUND": []},
                    "pg_pin_names": {}, "obs_m4_x": [], "lef": str(path),
                    # class 4a: cut layers this cell obstructs over its WHOLE
                    # footprint, and the extent of its signal ports per layer.
                    "obs_cut_full": set(), "sig": {}}
                pin, in_obs, layer = None, False, None
                continue
            if cur is None:
                continue
            if s == "END" or s.startswith("END "):
                # bare END closes a PORT (or the OBS block); `END <name>`
                # closes the PIN or the MACRO of that name.
                parts = s.split()
                if len(parts) == 1:
                    in_obs, layer = False, None
                elif pin is not None and parts[1] == pin[0]:
                    pin, layer = None, None
                elif parts[1] == cur["cell"]:
                    cur["obs_m4_x"] = sorted(set(cur["obs_m4_x"]))
                    cells[cur["cell"]] = cur
                    cur, pin, in_obs, layer = None, None, False, None
                continue
            if s.startswith("SIZE ") and cur["w"] is None:
                p = s.replace(";", "").split()
                cur["w"], cur["h"] = float(p[1]), float(p[3])
                continue
            if s.startswith("PIN "):
                # [name, PG use or None, USE class].  LEF's default USE is
                # SIGNAL, and these vendor LEFs do leave it off some pins, so
                # the third slot starts at SIGNAL rather than at None -- a pin
                # with no USE line is a signal pin, not an unclassified one.
                pin = [s.split()[1], None, "SIGNAL"]
                in_obs, layer = False, None
                continue
            if s.startswith("OBS"):
                pin, in_obs, layer = None, True, None
                continue
            if pin is not None and s.startswith("USE "):
                u = s.replace(";", "").split()[1].upper()
                pin[2] = u
                if u in ("POWER", "GROUND"):
                    pin[1] = u
                    cur["pg_pin_names"].setdefault(u, []).append(pin[0])
                continue
            if s.startswith("LAYER "):
                layer = s.replace(";", "").split()[1]
                continue
            if s.startswith("RECT ") and layer:
                v = [float(x) for x in s.replace(";", "").split()[1:5]]
                if in_obs:
                    if layer == "M4":
                        cur["obs_m4_x"].append((v[0], v[2]))
                    elif is_cut_layer(layer) and cur["w"] and cur["h"]:
                        # A cut obstruction covering the WHOLE footprint is what
                        # makes class 4a apply: no layer change is possible
                        # anywhere inside, so the pin must be carried out planar
                        # and the first via has to sit outside the edge.
                        if (v[0] <= MFG_GRID and v[1] <= MFG_GRID
                                and v[2] >= cur["w"] - MFG_GRID
                                and v[3] >= cur["h"] - MFG_GRID):
                            cur["obs_cut_full"].add(layer)
                elif pin is not None:
                    if pin[1] and layer == "M4":
                        cur["pg"][pin[1]].append((v[0], v[1], v[2], v[3]))
                    if pin[2] in ("SIGNAL", "CLOCK") and layer.upper().startswith("M"):
                        # Aggregated, not stored per rect: class 4a needs only
                        # the extent of the signal ports on each layer and how
                        # many distinct pins reach it, and these vendor LEFs
                        # carry thousands of port rects per macro.
                        d = cur["sig"].setdefault(layer, {
                            "pins": set(), "rects": 0,
                            "xlo": v[0], "xhi": v[2], "ylo": v[1], "yhi": v[3]})
                        d["pins"].add(pin[0])
                        d["rects"] += 1
                        d["xlo"] = min(d["xlo"], v[0]); d["xhi"] = max(d["xhi"], v[2])
                        d["ylo"] = min(d["ylo"], v[1]); d["yhi"] = max(d["yhi"], v[3])
    return cells


def parse_tech_lef(path: Path) -> dict:
    txt = path.read_text(errors="replace")
    out = {"tech_lef": str(path)}
    mm = re.search(r"DATABASE\s+MICRONS\s+(\d+)", txt)
    out["db_microns"] = int(mm.group(1)) if mm else None
    mm = re.search(r"MANUFACTURINGGRID\s+([\d.]+)", txt)
    out["mfg_grid"] = float(mm.group(1)) if mm else None
    mm = re.search(r"^SITE\s+core\s*\n\s*SIZE\s+([\d.]+)\s+BY\s+([\d.]+)", txt, re.M)
    if mm:
        out["site_x"], out["site_y"] = float(mm.group(1)), float(mm.group(2))

    # M4 SPACINGTABLE -> the wide-metal breakpoint and its spacing.
    blk = re.search(r"^LAYER M4$(.*?)^END M4$", txt, re.M | re.S)
    if blk:
        st = re.search(r"SPACINGTABLE\s*\n?\s*PARALLELRUNLENGTH([^;]*);", blk.group(1))
        if st:
            body = st.group(1)
            prl_line, *width_rows = re.split(r"\bWIDTH\b", body)
            prls = [float(v) for v in prl_line.split()]
            rows = []
            for r in width_rows:
                vals = [float(v) for v in r.split()]
                rows.append((vals[0], vals[1:]))
            out["m4_prl_table"] = {"prl": prls, "rows": rows}
            # narrow spacing = the row covering a 0.35um line at long PRL
            def sp_for(width):
                best = rows[0][1][-1]
                for w0, vals in rows:
                    if width >= w0 - 1e-9:
                        best = vals[-1]
                return best
            narrow = sp_for(0.35)
            wide_w, wide_s = None, None
            for w0, vals in rows:
                if w0 > 0.35 and vals[-1] > narrow + 1e-9:
                    wide_w, wide_s = w0, vals[-1]
                    break
            out["m4_narrow_spacing"] = narrow
            out["m4_wide_width"] = wide_w
            out["m4_wide_spacing"] = wide_s
        pm = re.search(r"\n\s*PITCH\s+([\d.]+)", blk.group(1))
        if pm:
            out["m4_pitch"] = float(pm.group(1))

    # ---- the routing grid and the cut rules, for class 4a -----------------
    #
    # NOTHING BELOW IS A LITERAL IN THIS FILE.  Every number class 4a works
    # with -- track pitch, track origin, cut extent, cut spacing -- is read
    # here, out of the licensed technology LEF, on a host that has one.  That
    # is not only the vendor rule; it is also what makes the check portable to
    # another metal stack without an edit.
    out["layers"] = {}
    for m in re.finditer(r"^LAYER\s+(\w+)\s*\n(.*?)^END\s+\1", txt, re.M | re.S):
        name, body = m.group(1), m.group(2)
        d = {}
        mm = re.search(r"TYPE\s+(\w+)", body)
        d["type"] = mm.group(1).upper() if mm else ""
        mm = re.search(r"DIRECTION\s+(\w+)", body)
        d["dir"] = mm.group(1).upper() if mm else ""
        mm = re.search(r"\n\s*PITCH\s+([\d.]+)", body)
        d["pitch"] = float(mm.group(1)) if mm else None
        mm = re.search(r"\n\s*OFFSET\s+([\d.]+)", body)
        d["offset"] = float(mm.group(1)) if mm else None
        # The strictest arm of the cut-spacing rule that can apply at the edge
        # of a footprint-wide cut obstruction.  Such an obstruction IS a dense
        # cut array, so the adjacent-cut arm is the one the router's own marker
        # names ("Adjacent Cut Spacing"); the parallel-overlap arm is carried in
        # a PROPERTY string on this node.  Taking the max of the arms present is
        # the conservative reading and it is the one that reproduces the
        # measured case.
        arms = [float(v) for v in
                re.findall(r"^\s*SPACING\s+([\d.]+)\s+ADJACENTCUTS", body, re.M)]
        arms += [float(v) for v in
                 re.findall(r"SPACING\s+([\d.]+)\s+PARALLELOVERLAP", body)]
        mm = re.search(r"^\s*SPACING\s+([\d.]+)\s*;", body, re.M)
        if mm:
            arms.append(float(mm.group(1)))
        d["spacing"] = max(arms) if arms else None
        d["spacing_arms"] = len(arms)
        out["layers"][name] = d

    # The cut extent, taken from the technology LEF's OWN single-cut via
    # masters rather than from any rule table: a via master is what the router
    # will actually instantiate, so its cut is the one that has to clear the
    # obstruction.
    out["cut_size"] = {}
    out["cut_masters"] = 0
    for m in re.finditer(r"^VIA\s+(\S+)\s+DEFAULT\s*$(.*?)^END\s+\1\s*$",
                         txt, re.M | re.S):
        nm, body = m.group(1), m.group(2)
        if not nm.endswith("_1cut"):
            continue
        out["cut_masters"] += 1
        for lm in re.finditer(
                r"LAYER\s+(\w+)\s*;\s*RECT\s+([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)",
                body):
            lname = lm.group(1)
            if out["layers"].get(lname, {}).get("type") != "CUT":
                continue
            x0, y0, x1, y1 = (float(v) for v in lm.groups()[1:])
            ext = round(max(x1 - x0, y1 - y0), 4)
            out["cut_size"][lname] = max(out["cut_size"].get(lname, 0.0), ext)
    return out


# --------------------------------------------------------------------------
# netlist -> full hierarchical macro instance paths
# --------------------------------------------------------------------------
def netlist_macro_instances(path: Path, macro_cells: set[str], top_hint: str) -> list[tuple[str, str]]:
    """(hierarchical instance path, cell) for every macro, as `get_db insts` sees it.

    Parsed as text: Genus writes `module\\n  <name>(` for long headers, and
    instance names may be escaped (`\\foo.bar `).  Walking the module graph from
    the top reproduces the SAME names place_macro's glob matches -- which is the
    whole point: the patterns key on hierarchy fragments (`u_network_core`,
    `u_chip_core`) that a flattened leaf name does not carry.
    """
    txt = path.read_text(errors="replace")
    parts = re.split(r"(?m)^module\s+", txt)
    bodies: dict[str, str] = {}
    for p in parts[1:]:
        m = re.match(r"\s*([A-Za-z_\\][^\s(]*)", p)
        if not m:
            continue
        end = p.find("\nendmodule")
        bodies[m.group(1)] = p[: end if end >= 0 else len(p)]
    if not bodies:
        raise Vacuous(f"netlist: no modules parsed out of {path}")

    inst_re = re.compile(r"(?m)^\s{2,}([A-Za-z_][A-Za-z0-9_$]*)\s+(\\?[^\s(]+)\s*\(")
    defined = set(bodies)
    edges: dict[str, list[tuple[str, str]]] = {}
    for name, body in bodies.items():
        es = []
        for cell, inst in inst_re.findall(body):
            if cell in defined or cell in macro_cells:
                es.append((cell, inst.rstrip()))
        edges[name] = es

    top = top_hint if top_hint in bodies else None
    if top is None:
        # the module nothing else instantiates
        used = {c for es in edges.values() for c, _ in es}
        roots = [m for m in bodies if m not in used]
        if len(roots) != 1:
            raise Vacuous(f"netlist: cannot identify the top module "
                          f"({len(roots)} candidates: {roots[:5]})")
        top = roots[0]

    out: list[tuple[str, str]] = []
    seen_depth = 0

    def walk(mod, path_parts, depth):
        nonlocal seen_depth
        seen_depth = max(seen_depth, depth)
        if depth > 40:
            raise Vacuous("netlist: hierarchy walk exceeded depth 40 (cycle?)")
        for cell, inst in edges.get(mod, []):
            pp = path_parts + [inst]
            if cell in macro_cells:
                out.append(("/".join(pp), cell))
            else:
                walk(cell, pp, depth + 1)

    walk(top, [], 0)
    return out


def glob_to_re(pat: str) -> re.Pattern:
    """Innovus `get_db insts <glob>`: * matches anything, including `/`."""
    return re.compile("^" + ".*".join(re.escape(p) for p in pat.split("*")) + "$")


# --------------------------------------------------------------------------
# geometry
# --------------------------------------------------------------------------
def placed_box(mac, cell):
    w, h = cell["w"], cell["h"]
    # R90/R270 are not used by this floorplan; refuse rather than guess.
    if mac["orient"] in {"R90", "R270", "MX90", "MY90"}:
        raise Vacuous(f"orientation {mac['orient']} rotates the macro; this "
                      f"checker only handles R0/R180/MX/MY")
    return (mac["x"], mac["y"], mac["x"] + w, mac["y"] + h)


def placed_pg_pins(cell, x, orient, pin_width):
    """Absolute x of every PG pin rect of exactly `pin_width`, per USE class.

    Each entry is (x_lo, gap_left, gap_right) where the gaps are to the macro's
    OWN internal M4 obstruction -- in the PLACED frame, so an MY/R180 mirror
    swaps them.
    """
    w = cell["w"]
    iv = cell["obs_m4_x"]
    lo_edges = [a for a, _ in iv]
    hi_edges = sorted(b for _, b in iv)
    out = {"POWER": [], "GROUND": []}
    for use, rects in cell["pg"].items():
        for (a, b, c, d) in rects:
            if abs((c - a) - pin_width) > 1e-9:
                continue
            i = bisect_left(lo_edges, c - 1e-9)
            gr = (lo_edges[i] - c) if i < len(lo_edges) else 99.0
            j = bisect_left(hi_edges, a + 1e-9)
            gl = (a - hi_edges[j - 1]) if j > 0 else 99.0
            if orient in X_FLIPPED:
                a2, gl2, gr2 = w - c, gr, gl
            else:
                a2, gl2, gr2 = a, gl, gr
            out[use].append((round(x + a2, 6), round(gl2, 4), round(gr2, 4)))
    return {k: sorted(set(v)) for k, v in out.items()}


def adjacent_pairs(placed, max_gap):
    """Vertically adjacent, x-overlapping macro pairs, nearest neighbour only.

    "Adjacent" = no third macro's box lies between them over the shared x span,
    and the channel is at most `max_gap` (derived from the M5 ladder pitch --
    see the caller; two macros further apart than that have a whole PG stripe
    set between them and share no riser).
    """
    pairs = []
    for A, B in itertools.combinations(placed, 2):
        lo, hi = (A, B) if A["box"][1] <= B["box"][1] else (B, A)
        gap = hi["box"][1] - lo["box"][3]
        xov = min(lo["box"][2], hi["box"][2]) - max(lo["box"][0], hi["box"][0])
        if xov <= 0 or gap < 0 or gap > max_gap:
            continue
        x1, x2 = max(lo["box"][0], hi["box"][0]), min(lo["box"][2], hi["box"][2])
        blocked = False
        for C in placed:
            if C is lo or C is hi:
                continue
            if C["box"][2] <= x1 or C["box"][0] >= x2:
                continue
            if C["box"][1] >= lo["box"][3] - 1e-9 and C["box"][3] <= hi["box"][1] + 1e-9:
                blocked = True
                break
        if blocked:
            continue
        pairs.append({"lower": lo, "upper": hi, "gap": round(gap, 4),
                      "xov": round(xov, 4), "x1": round(x1, 4), "x2": round(x2, 4)})
    return pairs


def min_pin_offset(lo_x, hi_x, x1, x2, pin_width, wide_width, dx=0.0):
    """Smallest merging + wide-making same-net pin offset over the shared x span.

    `lo_x` / `hi_x` are {net: sorted list of absolute pin x}.  `dx` shifts the
    UPPER macro, which is how the clearing-move search works without rebuilding
    any lists.
    """
    worst = None
    tested = 0
    lo_lim, hi_lim = x1 - pin_width, x2
    for net in ("POWER", "GROUND"):
        A = lo_x.get(net) or []
        B = hi_x.get(net) or []
        if not A or not B:
            continue
        for b in B:
            v = b + dx
            if not (lo_lim <= v <= hi_lim):
                continue
            j = bisect.bisect_left(A, v)
            for k in (j - 1, j):
                if not (0 <= k < len(A)):
                    continue
                tested += 1
                d = abs(v - A[k])
                if d <= 1e-9 or d >= pin_width - 1e-9:
                    continue                      # coincident, or no merge
                if pin_width + d <= wide_width + 1e-9:
                    continue                      # merges but stays narrow
                if worst is None or d < worst["offset"]:
                    worst = {"net": net, "offset": round(d, 4),
                             "union_width": round(pin_width + d, 4),
                             "x_lower": round(A[k], 4), "x_upper": round(v, 4)}
    return worst, tested


def smallest_clearing_dx(lo_x, hi_x, x1, x2, pin_width, wide_width, site_x, limit=8.4):
    """Smallest |dx| on the site grid, applied to the UPPER macro, that clears.

    Brute force over the site grid: the pin lattice is quasi-periodic with two
    sub-phases per 4.2um period plus an irregular break at the macro centre, so
    closed-form phase arithmetic gets this wrong.
    """
    steps = int(round(limit / site_x))
    for n in range(1, steps + 1):
        for dx in (-n * site_x, n * site_x):
            w, _ = min_pin_offset(lo_x, hi_x, x1 + min(dx, 0.0), x2 + max(dx, 0.0),
                                  pin_width, wide_width, dx)
            if w is None:
                return round(dx, 4)
    return None


def in_band_strict(y, bands):
    """Strictly inside a band.

    An edge exactly ON a band boundary counts as CLEAR.  That is not a
    convenience: it is the resolution this project actually accepted on
    2026-08-21 -- net_imem_rf32k moved -1.100 to put its bottom edge on 1504.500
    and net_dmem_rf16k -1.150 to put its top edge on 1624.500, both exactly the
    band's lower boundary.  A coincident edge is still reported separately (see
    the COINCIDENT note in the report) because floorplan.tcl:384 records a
    coincident-edge case on the M5 ladder that was still a short.
    """
    return any(b["lo"] + 1e-9 < y < b["hi"] - 1e-9 for b in bands)


def band_status(y, bands, mfg=MFG_GRID):
    """0 = strictly clear of every M9 band, 1 = coincident with a boundary,
    2 = strictly inside one.

    The three are NOT interchangeable.  A coincident edge is accepted -- it is
    the resolution 78dac42 took -- but floorplan.tcl:384 records a coincident
    edge on the M5 ladder that was still a short, so where a choice exists it is
    the second preference and not the first.
    """
    worst = 0
    for b in bands:
        if abs(y - b["lo"]) < mfg / 2 or abs(y - b["hi"]) < mfg / 2:
            worst = max(worst, 1)
        elif b["lo"] < y < b["hi"]:
            return 2
    return worst


def clearing_dy(edge_y, bands, other_edge_y, mfg=MFG_GRID):
    """Smallest dy that takes BOTH edges of the macro out of every band."""
    cands = []
    for b in bands:
        if b["lo"] < edge_y < b["hi"]:
            cands += [-(edge_y - b["lo"]), (b["hi"] - edge_y)]
    cands = sorted(set(snap(c, mfg) for c in cands), key=abs)
    for dy in cands:
        if not in_band_strict(edge_y + dy, bands) and \
           not in_band_strict(other_edge_y + dy, bands):
            return dy
    for n in range(1, int(60 / mfg)):
        for dy in (-n * mfg, n * mfg):
            if not in_band_strict(edge_y + dy, bands) and \
               not in_band_strict(other_edge_y + dy, bands):
                return round(dy, 4)
    return None


def escape_geometry(cell, tech):
    """Class 4a, placement-independent half: for ONE macro CELL, which layer a
    signal pin has to escape on, which cut it changes layer through, and which
    edge of the footprint its ports sit on.

    Always returns a dict, never None, and always with a `status`.  A cell the
    class does not apply to is REPORTED as such rather than dropped -- the whole
    point of the census is that "0 flagged" and "0 examined" must not look the
    same.
    """
    g = {"cell": cell["cell"], "status": None, "cut_layer": None, "escape": None,
         "axis": None, "pitch": None, "offset": None, "cut": None,
         "spacing": None, "edges": [], "extent": None, "pitches": None,
         "pins": 0, "cuts_obstructed": sorted(cell["obs_cut_full"])}

    cuts = []
    for c in sorted(cell["obs_cut_full"]):
        mm = re.search(r"(\d+)$", c)
        if not mm:
            continue
        if tech["layers"].get(c, {}).get("type") != "CUT":
            raise Vacuous(f"{cell['cell']}: its OBS section obstructs {c} over the "
                          f"whole footprint, but the technology LEF does not declare "
                          f"{c} TYPE CUT -- one of the two files is not the one this "
                          f"design is built from")
        cuts.append((int(mm.group(1)), c))
    if not cuts:
        g["status"] = "no cut layer obstructed over the whole footprint"
        return g

    # The escape layer is the routing metal UNDER the topmost obstructed cut:
    # no layer change is possible anywhere inside the footprint, so the pin has
    # to be carried out on that metal and via up outside the edge.
    n, cut_layer = max(cuts)
    escape = "M%d" % n
    g["cut_layer"], g["escape"] = cut_layer, escape

    lay = tech["layers"].get(escape) or {}
    if lay.get("pitch") is None:
        raise Vacuous(f"technology LEF declares no track pitch for {escape}, the "
                      f"escape layer of {cell['cell']}; class 4a cannot be evaluated")
    cut = tech["cut_size"].get(cut_layer)
    if cut is None:
        raise Vacuous(f"technology LEF has no single-cut via master on {cut_layer}, "
                      f"so the cut extent {cell['cell']} must clear is unknown")
    spacing = (tech["layers"].get(cut_layer) or {}).get("spacing")
    if spacing is None:
        raise Vacuous(f"technology LEF gives no cut spacing on {cut_layer}; class 4a "
                      f"would be comparing against nothing")
    g["pitch"] = lay["pitch"]
    g["offset"] = lay.get("offset") or 0.0
    g["cut"], g["spacing"] = cut, spacing

    # Tracks run ALONG the layer's preferred direction, so they are spaced along
    # the perpendicular -- which is the direction the pin escapes in.  A
    # horizontal escape layer therefore constrains the y edges of the footprint.
    g["axis"] = "y" if lay.get("dir") == "HORIZONTAL" else "x"

    sig = cell["sig"].get(escape)
    if not sig:
        g["status"] = f"no signal port on {escape}"
        return g
    g["pins"] = len(sig["pins"])
    lo, hi = ((sig["ylo"], sig["yhi"]) if g["axis"] == "y" else (sig["xlo"], sig["xhi"]))
    extent = cell["h"] if g["axis"] == "y" else cell["w"]
    g["extent"] = extent
    g["pitches"] = round(extent / g["pitch"], 4)
    edges = []
    if lo <= MFG_GRID:
        edges.append(0.0)
    if hi >= extent - MFG_GRID:
        edges.append(extent)
    if not edges:
        g["status"] = (f"signal ports on {escape} span {lo}..{hi} and touch neither "
                       f"{g['axis']} edge of 0..{extent}")
        return g
    g["edges"] = edges
    g["status"] = "ok"
    return g


def escape_track_check(m, g, bands, mfg=MFG_GRID):
    """Class 4a, placed half: for ONE placed macro, is the FIRST via outside the
    footprint able to sit on a track and still clear the cut obstruction?

    One result per footprint edge the signal ports sit on.  Every result is
    returned, legal or not -- the caller prints them all and flags the ones that
    are not, so a clean run still shows what it measured.
    """
    out = []
    box = m["box"]
    pitch, off, cut, spacing = g["pitch"], g["offset"], g["cut"], g["spacing"]
    flipped = m["orient"] in (Y_FLIPPED if g["axis"] == "y" else X_FLIPPED)
    lo_g, hi_g = ((box[1], box[3]) if g["axis"] == "y" else (box[0], box[2]))
    for loc in g["edges"]:
        local = (g["extent"] - loc) if flipped else loc
        edge = round(lo_g + local, 6)
        outward = 1 if edge >= (lo_g + hi_g) / 2 else -1

        # The first track strictly OUTSIDE the footprint, and the gap it leaves
        # between the cut it would carry and the macro's cut obstruction.
        k = (edge - off) / pitch
        if outward > 0:
            t = (math.floor(k + 1e-9) + 1) * pitch + off - edge
        else:
            t = edge - ((math.ceil(k - 1e-9) - 1) * pitch + off)
        t = round(t, 6)
        clearance = round(t - cut / 2, 6)
        legal = clearance >= spacing - 1e-9

        nearest = round(k) * pitch + off
        phase = round(edge - nearest, 6)

        moves = []
        if abs(phase) > 1e-9:
            first = snap(-phase, mfg)
            second = snap(-phase + (pitch if phase > 0 else -pitch), mfg)
            # Deterministic order: smallest move first, and on a tie -- which is
            # exactly what a half-pitch phase gives -- the one that moves the
            # macro UP, then filtered below by whether it keeps the macro clear
            # of the M9 bands.  On 2026-08-25 both macros were half a pitch off
            # and both were moved the positive way for that reason.
            cands = {first, second}
            if g["axis"] == "y" and bands:
                # Rank by what the move does to the M9 bands FIRST and by size
                # second: a re-phasing move that walks an edge into a stripe band
                # has traded a class-4a flag for a class-1 short, and one that
                # lands it exactly ON a boundary has taken the second-best
                # answer when a strictly clear one was the same distance away.
                # MEASURED: on the 2026-08-25 worktree this is the difference
                # between prescribing +0.100 on the network-core rf_32k, which
                # lands its edge exactly on a band boundary, and -0.100, which
                # clears the band by a whole track.
                def rank(d):
                    return (max(band_status(box[1] + d, bands),
                                band_status(box[3] + d, bands)), abs(d), -d)
                moves = sorted(cands, key=rank)
            else:
                moves = sorted(cands, key=lambda d: (abs(d), -d))

        out.append({
            "id": m["id"], "macro": m["leaf"], "inst": m["inst"],
            "pattern": m["pattern"], "cell": m["cell"], "orient": m["orient"],
            "axis": g["axis"], "escape": g["escape"], "cut_layer": g["cut_layer"],
            "pitch": pitch, "offset": off, "cut": cut, "spacing": spacing,
            "edge": round(edge, 4), "outward": outward,
            "first_track": t, "clearance": clearance, "legal": legal,
            "phase": phase, "next_track": round(t + pitch, 6),
            "next_clearance": round(t + pitch - cut / 2, 6),
            "moves": moves,
            ("min_move_y" if g["axis"] == "y" else "min_move_x"):
                (moves[0] if moves else None),
        })
    return out


def leaf_of(path: str) -> str:
    return path.split("/")[-1].lstrip("\\").rstrip()


def elide(s: str, n: int) -> str:
    """Middle-elide.  Both ends of these names carry identity -- the region at
    the front (`u_region_imem_0...`) and the way/word index at the back
    (`...way0_..._word_3_i`) -- so truncating either end loses the macro."""
    if len(s) <= n:
        return s
    head = (n - 1) // 4          # tail-weighted: the way/word index lives there
    return s[:head] + "…" + s[-(n - 1 - head):]


# --------------------------------------------------------------------------
# report
# --------------------------------------------------------------------------
class Report:
    def __init__(self):
        self.lines = []
        self.census = {}
        self.findings = []

    def p(self, s=""):
        self.lines.append(s)

    def h(self, s):
        self.p()
        self.p(s)
        self.p("-" * len(s))

    def finding(self, cls, sev, macro, detail, **kw):
        self.findings.append(dict(cls=cls, severity=sev, macro=macro, detail=detail, **kw))


def run(args) -> tuple[int, Report, dict]:
    R = Report()
    t0 = time.time()

    fp_txt, fp_prov, pp_txt, pp_prov = read_tcl_pair(args.floorplan, args.power_plan)
    fp = parse_floorplan(fp_txt)
    stripes = parse_power_plan(pp_txt)

    # ---- inputs / provenance -------------------------------------------
    R.h("INPUTS")
    R.p(f"  floorplan   {fp_prov}")
    R.p(f"  power_plan  {pp_prov}")

    # ---- LEFs (header scan now, full parse only for the cells we place) --
    lef_paths = []
    if args.lef:
        lef_paths = [Path(p) for p in args.lef]
    else:
        globs = lef_globs()
        for g in globs:
            lef_paths += sorted(Path("/").glob(g.lstrip("/")))
    cell_lef = {}
    for p in lef_paths:
        for name in lef_macro_names(p):
            cell_lef.setdefault(name, p)
    if not cell_lef:
        raise Vacuous(f"no macro LEF parsed (searched {globs})")
    R.p(f"  macro LEFs  {len(cell_lef)} cells declared across {len(lef_paths)} files")

    tech = {}
    tl = Path(args.tech_lef) if args.tech_lef else None
    if tl is None:
        for g in tech_lef_globs():
            hits = sorted(Path("/").glob(g.lstrip("/")))
            if hits:
                tl = hits[0]
                break
    if tl is None or not tl.is_file():
        raise Vacuous("no tech LEF found; the M4 wide-metal breakpoint and the "
                      "site grid cannot be derived.  Pass --tech-lef.")
    tech = parse_tech_lef(tl)
    for k in ("m4_wide_width", "m4_wide_spacing", "m4_narrow_spacing", "site_x", "mfg_grid"):
        if tech.get(k) is None:
            raise Vacuous(f"tech LEF {tl}: could not derive {k}")
    R.p(f"  tech LEF    {tl}")
    # The narrow-width threshold is NOT written as a literal here: it is a PDK table
    # axis value, and this file is published. Everything printed on this line is read
    # from the licensed tech LEF at run time on a host that has it.
    R.p(f"              M4 parallel-run table: narrow spacing {tech['m4_narrow_spacing']}, "
        f"wide breakpoint {tech['m4_wide_width']}um -> spacing {tech['m4_wide_spacing']}")
    R.p(f"              SITE core {tech['site_x']} x {tech.get('site_y')}, "
        f"MANUFACTURINGGRID {tech['mfg_grid']}")
    if abs(tech["mfg_grid"] - MFG_GRID) > 1e-9:
        raise Vacuous(f"tech LEF MANUFACTURINGGRID {tech['mfg_grid']} != {MFG_GRID}")

    # ---- netlist: resolve place_macro patterns to cells -----------------
    nl = Path(args.netlist) if args.netlist else None
    if nl is None:
        hits = []
        for g in NETLIST_GLOBS:
            hits += list(Path("/").glob(g.lstrip("/")))
        hits = [h for h in hits if h.is_file()]
        if not hits:
            raise Vacuous("no gate netlist found; place_macro patterns cannot be "
                          "resolved to cells.  Pass --netlist.")
        nl = max(hits, key=lambda p: p.stat().st_mtime)
    insts = netlist_macro_instances(nl, set(cell_lef), "nanosoc_eth_chiplet_pads")
    R.p(f"  netlist     {nl}")
    R.p(f"              mtime {time.strftime('%Y-%m-%d %H:%M', time.localtime(nl.stat().st_mtime))}, "
        f"{len(insts)} macro instances")

    # ---- census (a zero here is a FAILURE, never a pass) ----------------
    if not fp["macros"]:
        raise Vacuous("zero place_macro lines parsed out of the floorplan; "
                      "there is nothing to check")
    R.census["macros_in_floorplan"] = len(fp["macros"])
    R.census["macro_lef_cells_declared"] = len(cell_lef)
    R.census["netlist_macro_instances"] = len(insts)

    # resolve patterns first, then read only the LEFs we actually need
    resolved, unresolved = [], []
    for mac in fp["macros"]:
        rx = glob_to_re(mac["pattern"])
        hits = [(p, c) for p, c in insts if rx.match(p)]
        if len(hits) != 1:
            unresolved.append((mac["pattern"], len(hits)))
            continue
        resolved.append((mac, hits[0][0], hits[0][1]))
    R.census["patterns_resolved"] = len(resolved)
    R.census["patterns_unresolved"] = len(unresolved)
    if unresolved:
        R.h("PATTERN RESOLUTION FAILED")
        for pat, n in unresolved:
            R.p(f"  '{pat}' matched {n} macro instances, expected exactly 1")
        raise Vacuous(f"{len(unresolved)} place_macro pattern(s) did not resolve "
                      f"against {nl}; nothing downstream would be measured")

    want = {c for _, _, c in resolved}
    cells = {}
    for cn in sorted(want):
        cells.update(parse_macro_lef(cell_lef[cn], want))
    missing = want - set(cells)
    if missing:
        raise Vacuous(f"LEF geometry missing for placed cells: {sorted(missing)}")
    R.census["macro_lef_cells_read"] = len(cells)

    placed = []
    for mac, path, cellname in resolved:
        cell = cells[cellname]
        placed.append({
            "pattern": mac["pattern"], "inst": path, "cell": cellname,
            "leaf": leaf_of(path),
            "x": mac["x"], "y": mac["y"], "orient": mac["orient"],
            "box": placed_box(mac, cell), "lefobj": cell,
        })
    placed.sort(key=lambda m: (m["box"][1], m["box"][0]))
    for i, m in enumerate(placed, 1):
        m["id"] = f"M{i:02d}"
        m["short"] = f"{m['id']} {elide(m['leaf'], ELIDE)}"

    # ---- core box, cross-checked ---------------------------------------
    core = fp["core"]
    R.h("GEOMETRY")
    R.p(f"  CORE_TO_IO {fp['core_to_io']}, die {fp['die'][0]} x {fp['die'][1]}, "
        f"IO inset {fp['pad_height']} + {fp['core_to_io']} = {fp['pad_height']+fp['core_to_io']}")
    R.p(f"  core box   ({core[0]},{core[1]})-({core[2]},{core[3]})   "
        f"[cross-check vs MEASURED {CORE_BOX_EXPECTED}: "
        f"{'OK' if all(abs(a-b) < 1e-6 for a, b in zip(core, CORE_BOX_EXPECTED)) else 'MISMATCH'}]")
    if not all(abs(a - b) < 1e-6 for a, b in zip(core, CORE_BOX_EXPECTED)):
        raise Vacuous(f"derived core box {core} != measured {CORE_BOX_EXPECTED}; "
                      f"every band below is anchored on core_y_lo, so nothing "
                      f"here would be trustworthy")

    bands, m9 = m9_bands(stripes, core)
    first = [b for b in bands if b["slot"] == 0]
    second = [b for b in bands if b["slot"] == 1]
    R.census["m9_bands_total"] = len(bands)
    R.census["m9_bands_first"] = len(first)
    R.census["m9_bands_second"] = len(second)
    R.p(f"  M9 ladder  width {m9['width']} spacing {m9['spacing']} pitch {m9['pitch']} "
        f"start_offset {m9['start_offset']} nets {m9['nets']}")
    R.p(f"             band k(slot0) = [{core[1]}+{m9['start_offset']}+{m9['pitch']}k, "
        f"+{m9['width']}]  -> first {first[0]['lo']}..{first[0]['hi']}, "
        f"{len(first)} of them inside the core")
    R.p(f"             slot1 (the second stripe of each set, +{m9['width']}+{m9['spacing']}) "
        f"-> {second[0]['lo']}..{second[0]['hi']} ... {len(second)} of them")
    R.p(f"  halos      place {fp['place_halo']}  route {fp['route_halo']}")

    if not bands:
        raise Vacuous("zero M9 bands computed inside the core box")

    # ---- the macro census: exactly what was examined --------------------
    R.h("MACROS EXAMINED")
    R.p(f"  {'id':<5}{'instance (middle-elided)':<{ELIDE+2}}{'cell':<18}{'orient':<7}"
        f"{'x':>10}{'y':>10}{'x2':>10}{'y2':>10}")
    for m in placed:
        R.p(f"  {m['id']:<5}{elide(m['leaf'], ELIDE):<{ELIDE+2}}{m['cell']:<18}{m['orient']:<7}"
            f"{m['box'][0]:>10.3f}{m['box'][1]:>10.3f}{m['box'][2]:>10.3f}{m['box'][3]:>10.3f}")
    R.p("  place_macro pattern -> the one instance it resolved to (exactly 1 each,")
    R.p("  same rule place_macro itself enforces):")
    for m in placed:
        R.p(f"      {m['id']} {m['pattern']:<46} {m['inst']}")

    # ---- placed pin lists ----------------------------------------------
    PIN_W = 0.350
    pin_rects = 0
    for m in placed:
        m["pins"] = placed_pg_pins(m["lefobj"], m["x"], m["orient"], PIN_W)
        m["pinx"] = {k: [v[0] for v in vals] for k, vals in m["pins"].items()}
        pin_rects += sum(len(v) for v in m["pins"].values())
    R.census["pg_pins_035_placed"] = pin_rects
    if pin_rects == 0:
        raise Vacuous(f"zero {PIN_W}um M4 PG pins across {len(placed)} macros; "
                      f"class 3 would examine nothing")

    # =====================================================================
    # CLASS 1 / 2 -- macro edge inside an M9 stripe band
    # =====================================================================
    R.h("CLASS 1 / 2 -- MACRO EDGE INSIDE AN M9 STRIPE BAND")
    R.p("  RELIABLE.  Exact arithmetic on the band grid derived above.")
    R.p("  class 1 = Y-flipped (MX/R180) macro TOP edge in a band -> METAL SHORT")
    R.p("  class 2 = any other edge in a band                     -> M9.W.1 min width")
    R.p("  An edge exactly ON a band boundary is treated as CLEAR (that is the")
    R.p("  resolution 78dac42 accepted: -1.100 / -1.150 land on 1504.500 / 1624.500)")
    R.p("  but is still listed below as COINCIDENT.")
    edges_tested = 0
    c12, coincident = [], []
    for m in placed:
        for edge, ev, other in (("bottom", m["box"][1], m["box"][3]),
                                ("top", m["box"][3], m["box"][1])):
            edges_tested += 1
            for b in bands:
                if abs(ev - b["lo"]) < MFG_GRID / 2 or abs(ev - b["hi"]) < MFG_GRID / 2:
                    coincident.append((m, edge, ev, b))
                    continue
                if not (b["lo"] < ev < b["hi"]):
                    continue
                yflip = m["orient"] in Y_FLIPPED
                cls = 1 if (yflip and edge == "top") else 2
                dy = clearing_dy(ev, bands, other)
                c12.append({
                    "cls": cls, "id": m["id"], "macro": m["leaf"],
                    "pattern": m["pattern"],
                    "inst": m["inst"], "cell": m["cell"],
                    "orient": m["orient"], "edge": edge, "edge_y": round(ev, 4),
                    "band": [b["lo"], b["hi"]], "band_set": b["set"], "band_slot": b["slot"],
                    "band_net": b["net"], "min_move_y": dy,
                    "into_band": round(min(ev - b["lo"], b["hi"] - ev), 4),
                })
    R.census["macro_edges_tested"] = edges_tested
    R.p(f"  examined: {edges_tested} macro edges x {len(bands)} bands "
        f"= {edges_tested*len(bands)} tests")
    if not c12:
        R.p("  RESULT: clean -- no macro edge lands strictly inside any M9 band.")
    for m, edge, ev, b in coincident:
        R.p(f"  [COINCIDENT] {m['id']} {m['leaf']}: {edge} edge {ev} sits ON band "
            f"boundary {b['lo']}..{b['hi']} -- accepted, see floorplan.tcl:384")
    for f in sorted(c12, key=lambda f: (f["cls"], f["edge_y"])):
        R.p("")
        R.p(f"  [CLASS {f['cls']}] {f['id']}  {f['macro']}  ({f['cell']}, {f['orient']})")
        R.p(f"      {f['edge']} edge y = {f['edge_y']}")
        R.p(f"      band set {f['band_set']} slot {f['band_slot']} (net {f['band_net']}) "
            f"= {f['band'][0]}..{f['band'][1]}   "
            f"[{core[1]} + {m9['start_offset']} + {m9['pitch']}*{f['band_set']}"
            f"{' + ' + str(m9['width']) + ' + ' + str(m9['spacing']) if f['band_slot'] else ''}]")
        R.p(f"      inside the band by {f['into_band']} um")
        R.p(f"      SMALLEST CLEARING MOVE: dy = {f['min_move_y']:+.3f} um "
            f"(both edges clear of every band afterwards)")
        if f["cls"] == 1:
            R.p("      CONSEQUENCE: metal short to the M4 tap pinned on this band.")
        else:
            R.p("      CONSEQUENCE: M9.W.1 minimum-width marker at this edge.")
        R.finding(f["cls"], "FAIL", f["macro"], f, inst=f["inst"], id=f["id"])

    # =====================================================================
    # CLASS 3 -- pin-grid phase collision
    # =====================================================================
    R.h("CLASS 3 -- PIN-GRID PHASE COLLISION (M4.S.2.1 wide-metal spacing)")
    R.p("  OVER-APPROXIMATING -- see the header.  A flag means 'measure this on")
    R.p("  the PG probe before you run P&R', not 'this will fail'.")
    wide_w = tech["m4_wide_width"]
    R.p(f"  merge window : 0 < |offset| < {PIN_W} um   (both shapes {PIN_W} um wide)")
    R.p(f"  wide window  : {PIN_W} + |offset| > {wide_w} um  "
        f"(M4 SPACINGTABLE breakpoint; spacing then rises "
        f"{tech['m4_narrow_spacing']} -> {tech['m4_wide_spacing']})")

    m5 = [s for s in stripes if s["layer"] == "M5" and s["pitch"]]
    if not m5:
        raise Vacuous("power_plan: no M5 add_stripes with a -set_to_set_distance; "
                      "the channel-adjacency bound cannot be derived")
    max_gap = 2 * m5[0]["pitch"]
    R.p(f"  adjacency    channel <= 2 x the M5 ladder pitch "
        f"({m5[0]['pitch']} um, power_plan.tcl) = {max_gap} um, and no third")
    R.p(f"               macro between the two over the shared x span")

    pairs = adjacent_pairs(placed, max_gap)
    R.census["macro_pairs_tested"] = len(pairs)
    if not pairs:
        raise Vacuous("zero vertically-adjacent x-overlapping macro pairs; "
                      "class 3 and the channel census would examine nothing")
    pin_tests = 0
    c3 = []
    for pr in pairs:
        w, n = min_pin_offset(pr["lower"]["pinx"], pr["upper"]["pinx"],
                              pr["x1"], pr["x2"], PIN_W, wide_w)
        pin_tests += n
        pr["worst"] = w
        if w:
            c3.append(pr)
    R.census["pin_pairs_tested"] = pin_tests
    R.p(f"  examined: {len(pairs)} adjacent macro pairs, {pin_tests} nearest-neighbour "
        f"pin-pair tests")
    if pin_tests == 0:
        raise Vacuous("zero pin pairs tested across {} macro pairs".format(len(pairs)))
    if not c3:
        R.p("  RESULT: clean -- no adjacent pair puts a same-net pin pair in the window.")
    for pr in sorted(c3, key=lambda p: p["worst"]["offset"]):
        w = pr["worst"]
        dx = smallest_clearing_dx(pr["lower"]["pinx"], pr["upper"]["pinx"],
                                  pr["x1"], pr["x2"], PIN_W, wide_w, tech["site_x"])
        R.p("")
        R.p(f"  [CLASS 3] {pr['lower']['id']} {pr['lower']['leaf']}")
        R.p(f"        ->  {pr['upper']['id']} {pr['upper']['leaf']}")
        R.p(f"      channel gap {pr['gap']} um, x-overlap {pr['xov']} um "
            f"({pr['x1']} .. {pr['x2']})")
        R.p(f"      net {w['net']}: pin at x={w['x_lower']} (lower) vs x={w['x_upper']} "
            f"(upper), offset {w['offset']} um")
        R.p(f"      -> shapes MERGE ({w['offset']} < {PIN_W}) and the union is "
            f"{w['union_width']} um > {wide_w} um, so the wide-metal spacing "
            f"{tech['m4_wide_spacing']} applies")
        if dx is None:
            R.p(f"      SMALLEST CLEARING MOVE: none found within +/-8.4 um on the "
                f"{tech['site_x']} um site grid")
        else:
            R.p(f"      SMALLEST CLEARING MOVE: dx = {dx:+.3f} um on "
                f"{pr['upper']['id']} (site grid {tech['site_x']} um)")
        R.finding(3, "WARN", f"{pr['lower']['leaf']} -> {pr['upper']['leaf']}",
                  {"gap": pr["gap"], "xov": pr["xov"], **w, "min_move_x": dx,
                   "pattern": pr["upper"]["pattern"]},
                  id=f"{pr['lower']['id']}->{pr['upper']['id']}",
                  lower=pr["lower"]["inst"], upper=pr["upper"]["inst"])

    # -- diagnostic: which pins can even be made illegal by a merge -------
    R.p("")
    R.p("  CONTEXT (placement-independent, from the LEFs): PG pins whose gap to the")
    R.p("  macro's OWN internal M4 obstruction is already below the wide-metal")
    R.p(f"  spacing {tech['m4_wide_spacing']} um.  These are the pins that CAN produce a")
    R.p("  marker once something merges with them; the marker's width is that gap.")
    R.p("  Verified against the 2026-08-17 signoff DRC: marker at (737.905..738.060,")
    R.p("  279.450..289.760) = way1_word_1 VDD pin right edge 10.105 to OBS column")
    R.p("  10.260 = 0.155 um, exactly this census.")
    crit_total = 0
    for cname in sorted({m["cell"] for m in placed}):
        c = cells[cname]
        gaps = []
        for use, rects in c["pg"].items():
            for (a, b, cc, d) in rects:
                if abs((cc - a) - PIN_W) > 1e-9:
                    continue
                lo_e = [x for x, _ in c["obs_m4_x"]]
                hi_e = sorted(y for _, y in c["obs_m4_x"])
                i = bisect_left(lo_e, cc - 1e-9)
                gr = (lo_e[i] - cc) if i < len(lo_e) else 99.0
                j = bisect_left(hi_e, a + 1e-9)
                gl = (a - hi_e[j - 1]) if j > 0 else 99.0
                g = min(gl, gr)
                if g < tech["m4_wide_spacing"] - 1e-9:
                    gaps.append(round(g, 4))
        crit_total += len(gaps)
        R.p(f"      {cname:<18} {len(gaps):>4} critical pins   gaps {sorted(set(gaps))}")
    R.census["wide_metal_critical_pins"] = crit_total

    # =====================================================================
    # CLASS 4a -- macro pin edge off the escape-layer track grid
    # =====================================================================
    R.h("CLASS 4a -- MACRO PIN EDGE OFF THE ESCAPE-LAYER TRACK GRID")
    R.p("  RELIABLE.  Exact arithmetic; every operand -- track pitch, track")
    R.p("  origin, cut extent, cut spacing -- is read from the technology LEF at")
    R.p("  run time, so nothing about the process is fixed in this file.")
    R.p("  A cell that obstructs a cut layer over 100% of its footprint can only")
    R.p("  be reached PLANAR, so the first layer change has to sit OUTSIDE the")
    R.p("  edge, on a track of the escape metal, with its cut clear of the")
    R.p("  macro\'s own cut obstruction.  Whether that is possible is decided by")
    R.p("  the PHASE of the pin edge against the track grid -- and placement is")
    R.p("  what sets the phase.")
    R.p("")
    R.p("  PER CELL (from the LEFs alone; placement plays no part in this table):")

    geo, cells_obstructed = {}, 0
    for cname in sorted({m["cell"] for m in placed}):
        g = escape_geometry(cells[cname], tech)
        geo[cname] = g
        if g["cut_layer"]:
            cells_obstructed += 1
        if g["status"] != "ok":
            R.p(f"      {cname:<18} does not apply: {g['status']}")
            continue
        frac = abs(g["pitches"] - round(g["pitches"])) > 1e-9
        R.p(f"      {cname:<18} obstructs {' '.join(g['cuts_obstructed'])}"
            f" -> escapes on {g['escape']}, first via on {g['cut_layer']}")
        R.p(f"      {'':<18} {g['pins']} signal pins on the "
            f"{'low' if 0.0 in g['edges'] else 'high'} {g['axis']} edge; footprint "
            f"{g['extent']} = {g['pitches']} escape pitches"
            + ("  <-- NOT an integer, so a mirrored placement inverts the "
               "pin-edge phase" if frac else ""))

    rows, c4a, tested_pins = [], [], 0
    for m in placed:
        g = geo[m["cell"]]
        if g["status"] != "ok":
            continue
        for r in escape_track_check(m, g, bands):
            rows.append(r)
            tested_pins += g["pins"]
            if not r["legal"]:
                c4a.append(r)
    R.census["cut_obstructed_cells"] = cells_obstructed
    R.census["escape_edges_tested"] = len(rows)
    R.census["escape_pins_tested"] = tested_pins

    R.p("")
    R.p(f"  examined: {len(rows)} placed macro edges carrying {tested_pins} signal pins")
    R.p("")
    R.p(f"  {'id':<5}{'instance (middle-elided)':<{ELIDE+2}}{'or':<6}"
        f"{'pin edge':>11}{'phase':>8}{'1st trk':>9}{'clear':>8}{'need':>7}  verdict")
    for r in sorted(rows, key=lambda r: (r["legal"], r["edge"])):
        R.p(f"  {r['id']:<5}{elide(r['macro'], ELIDE):<{ELIDE+2}}{r['orient']:<6}"
            f"{r['edge']:>11.3f}{r['phase']:>+8.3f}{r['first_track']:>9.3f}"
            f"{r['clearance']:>8.3f}{r['spacing']:>7.3f}  "
            f"{'ok' if r['legal'] else 'CLASS 4a'}")
    if not c4a:
        R.p("  RESULT: clean -- every pin edge is on its escape layer\'s track grid,")
        R.p("  so the first track outside each footprint takes a legal via.")

    for r in sorted(c4a, key=lambda r: r["edge"]):
        R.p("")
        R.p(f"  [CLASS 4a] {r['id']}  {r['macro']}  ({r['cell']}, {r['orient']})")
        R.p(f"      pin edge {r['axis']} = {r['edge']}, escaping "
            f"{'outward/up' if r['outward'] > 0 else 'outward/down'}")
        R.p(f"      escape layer {r['escape']} (pitch {r['pitch']}, origin "
            f"{r['offset']}), first via on {r['cut_layer']} "
            f"(cut {r['cut']}, clearance rule {r['spacing']})")
        R.p(f"      the pin edge is {r['phase']:+.3f} um off the {r['escape']} track grid")
        R.p(f"      first track outside = {r['first_track']:.3f} um away -> the cut "
            f"clears the obstruction by {r['clearance']:.3f} < {r['spacing']}  ILLEGAL")
        R.p(f"      cheapest LEGAL escape = {r['next_track']:.3f} um away "
            f"(clearance {r['next_clearance']:.3f}), one extra track out and in the")
        R.p("      wrong track phase relative to every other route in the channel")
        R.p(f"      SMALLEST CLEARING MOVE: d{r['axis']} = "
            + " or ".join("%+.3f" % d for d in r["moves"]) + " um")
        R.p("      CONSEQUENCE: a pin that does not find the extra track takes the")
        R.p(f"      last track INSIDE the footprint, where {r['cut_layer']} is "
            f"obstructed -> CUTSPACING + Cut Short + Metal Short.")
        R.finding("4a", "FAIL", r["macro"], r, inst=r["inst"], id=r["id"])

    # -- cross-check: a class-1/2 clearing move can CREATE a class-4a hazard --
    xnote = []
    by_id = {q["id"]: q for q in placed}
    for f in c12:
        m = by_id.get(f["id"])
        g = geo.get(m["cell"]) if m else None
        if m is None or g is None or g["status"] != "ok" or f["min_move_y"] is None:
            continue
        dy = f["min_move_y"]
        moved = dict(m, box=(m["box"][0], m["box"][1] + dy,
                             m["box"][2], m["box"][3] + dy))
        for r in escape_track_check(moved, g, bands):
            if not r["legal"]:
                xnote.append((f, g, r))
    if xnote:
        R.p("")
        R.p("  CROSS-CHECK -- a class-1/2 clearing move can CREATE a class-4a hazard.")
        R.p("  clearing_dy snaps to the MANUFACTURING grid, which is finer than the")
        R.p("  escape-layer track grid, so a move that clears an M9 band can leave the")
        R.p("  pin edge off phase.  This is not hypothetical: it is how two macros in")
        R.p("  this design got off grid in the first place.")
        for f, g, r in xnote:
            R.p(f"      {f['id']} {f['macro']}: the class-{f['cls']} move "
                f"dy={f['min_move_y']:+.3f} leaves the {g['escape']} pin edge "
                f"{r['phase']:+.3f} off grid (clearance {r['clearance']:.3f} "
                f"< {r['spacing']})")
            both = ", ".join("%+.3f" % (f["min_move_y"] + d) for d in r["moves"])
            R.p(f"          a dy that clears BOTH: {both}")

    # =====================================================================
    # CLASS 4b -- channel census (NOT a class-4 detector)
    # =====================================================================
    R.h("CLASS 4b -- MACRO EDGE IN A LIVE SIGNAL CHANNEL")
    R.p("  NOT STATICALLY DERIVABLE, and this section does not claim to detect it.")
    R.p("  The 2026-08-21 case (way0_word_3 top 426.40 -> 422.30, five Regular Wire")
    R.p("  violations incl. a VIA3 Cut Short) moved into a channel that got WIDER,")
    R.p("  8.64 -> 12.74 um.  No channel-narrowing metric can predict that.  What")
    R.p("  decided it was where the PREVIOUS router had already put wires, which")
    R.p("  lives in the routed DB -- not in floorplan.tcl, the LEFs or power_plan.")
    R.p("")
    R.p("  READ THAT NARROWLY.  It is an argument about CHANNEL WIDTH, and it holds.")
    R.p("  It is not an argument about that move\'s OTHER consequence -- the pin edge")
    R.p("  it left off the escape track grid -- which class 4a above derives exactly")
    R.p("  and which is what actually produced those five violations.")
    R.p("")
    ph = fp["place_halo"][0] if fp["place_halo"] else None
    rh = fp["route_halo"]["space"] if fp["route_halo"] else None
    R.p(f"  What IS exact: place halo {ph} um/side, route halo {rh} um/side "
        f"({fp['route_halo']['bottom_layer']}..{fp['route_halo']['top_layer']}).")
    R.p("  A channel narrower than 2x the place halo admits no standard cell at all;")
    R.p("  a channel narrower than 2x the route halo admits no signal route.")
    R.p("")
    R.p(f"  {'lower':<6}{'upper':<7}{'gap':>8}{'-2*place':>10}{'-2*route':>10}  note")
    hard = []
    for pr in sorted(pairs, key=lambda p: p["gap"]):
        rp = round(pr["gap"] - 2 * ph, 3) if ph else None
        rr = round(pr["gap"] - 2 * rh, 3) if rh else None
        note = ""
        if rr is not None and rr <= 0:
            note = "ROUTE HALOS OVERLAP - no signal route fits"
            hard.append((pr, note))
        elif rp is not None and rp <= 0:
            note = "place halos overlap - no standard cell fits"
            hard.append((pr, note))
        R.p(f"  {pr['lower']['id']:<6}{pr['upper']['id']:<7}"
            f"{pr['gap']:>8.2f}{rp:>10.2f}{rr:>10.2f}  {note}")
    R.census["channels_measured"] = len(pairs)
    for pr, note in hard:
        R.finding(4, "WARN", f"{pr['lower']['leaf']} -> {pr['upper']['leaf']}",
                  {"gap": pr["gap"], "note": note,
                   "place_halo": ph, "route_halo": rh},
                  id=f"{pr['lower']['id']}->{pr['upper']['id']}")

    # -- differential ------------------------------------------------------
    diff = []
    if args.against:
        rtxt, rprov, _, _ = read_tcl_pair(args.against, args.power_plan)
        ref = parse_floorplan(rtxt)
        refmap = {m["pattern"]: m for m in ref["macros"]}
        R.p("")
        R.p(f"  DIFFERENTIAL vs {rprov}")
        R.p("  Edges that moved INTO space that was macro interior before.  This is a")
        R.p("  CHANGE detector, not a defect detector -- but on 2026-08-21 exactly one")
        R.p("  entry of this kind (way0_word_3, top -4.100) produced the five Regular")
        R.p("  Wire violations, on a design whose two previous runs had zero.")
        for m in placed:
            r = refmap.get(m["pattern"])
            if not r:
                R.p(f"      {m['id']} {elide(m['leaf'],ELIDE):<{ELIDE+2}} NEW (absent from the reference)")
                continue
            dx, dy = round(m["x"] - r["x"], 4), round(m["y"] - r["y"], 4)
            if dx == 0 and dy == 0:
                continue
            cell = m["lefobj"]
            edges = []
            if dy < 0:
                edges.append(("top", round(r["y"] + cell["h"], 3),
                              round(m["y"] + cell["h"], 3), dy))
            if dy > 0:
                edges.append(("bottom", round(r["y"], 3), round(m["y"], 3), dy))
            tag = "  <-- edge moved into the channel" if edges else ""
            R.p(f"      {m['id']} {elide(m['leaf'],ELIDE):<{ELIDE+2}} dx {dx:+.3f}  dy {dy:+.3f}{tag}")
            for e, was, now, d in edges:
                R.p(f"          {e} edge {was} -> {now} ({d:+.3f} um into "
                    f"previously-open channel)")
                diff.append({"macro": m["leaf"], "edge": e, "was": was, "now": now, "delta": d})
                R.finding(4, "INFO", m["leaf"],
                          {"edge": e, "was": was, "now": now, "delta": d,
                           "note": "edge moved into previously-open channel"},
                          id=m["id"])
        R.census["differential_edges_into_channel"] = len(diff)

    # =====================================================================
    # SUMMARY
    # =====================================================================
    R.h("CENSUS  (a zero in any row below is a FAILURE, not a pass)")
    for k, v in R.census.items():
        R.p(f"  {k:<34} {v}")
    zero = [k for k, v in R.census.items()
            if v == 0 and k not in ("patterns_unresolved",
                                    "differential_edges_into_channel")]
    if zero:
        raise Vacuous("census rows are zero: " + ", ".join(zero))

    n1 = sum(1 for f in R.findings if f["cls"] == 1)
    n2 = sum(1 for f in R.findings if f["cls"] == 2)
    n3 = sum(1 for f in R.findings if f["cls"] == 3)
    n4a = sum(1 for f in R.findings if f["cls"] == "4a")
    n4w = sum(1 for f in R.findings if f["cls"] == 4 and f["severity"] == "WARN")
    R.h("SUMMARY")
    R.p(f"  class 1   METAL SHORT (M9 tap floor)             : {n1}   [RELIABLE]      HARD")
    R.p(f"  class 2   M9.W.1 min width (band straddle)       : {n2}   [RELIABLE]      HARD")
    R.p(f"  class 3   M4.S.2.1 pin-grid phase collision      : {n3}   "
        f"[OVER-APPROXIMATING] ADVISORY")
    R.p(f"  class 4a  pin edge off the escape track grid     : {n4a}   [RELIABLE]      HARD")
    R.p(f"  class 4b  live-channel Regular Wire              : n/a [NOT DETECTED] "
        f"({n4w} halo-overlap channels, {len(diff)} changed edges)")

    # THE FAIL POLICY.  See the header section "What fails the gate, and why not
    # everything does".  Hard classes are exact and each prints the move that
    # clears it; class 3 is over-approximating by its own header and would make
    # this gate permanently red for a reason everybody already knows is benign,
    # which is how the last gate here died.  --strict promotes it.
    hard = n1 + n2 + n4a
    advisory = n3
    rc = 1 if (hard or (advisory and args.strict)) else 0
    R.p("")
    if rc and hard:
        verdict = (f"FAIL   ({hard} hard: class 1={n1}, 2={n2}, 4a={n4a}"
                   + (f"; {advisory} class-3 advisories)" if advisory else ")"))
    elif rc:
        verdict = f"FAIL   (--strict: {advisory} class-3 advisories, 0 hard)"
    elif advisory:
        verdict = (f"PASS   (0 hard; {advisory} class-3 ADVISORIES, listed above -- "
                   f"re-run with --strict to gate on them)")
    else:
        verdict = "PASS   (0 hard, 0 advisory)"
    R.p(f"  VERDICT: {verdict}")
    R.p(f"           measured in {time.time()-t0:.1f}s, no EDA licence used")

    js = {
        "verdict": "FAIL" if rc else "PASS",
        "hard": hard, "advisory": advisory, "strict": bool(args.strict),
        "policy": "hard = class 1, 2, 4a; advisory = class 3; class 4b is a census",
        "counts": {"1": n1, "2": n2, "3": n3, "4a": n4a, "4b_halo": n4w},
        "floorplan": fp_prov, "power_plan": pp_prov,
        "core_box": core, "census": R.census, "findings": R.findings,
        "elapsed_s": round(time.time() - t0, 2),
    }
    return rc, R, js


# --------------------------------------------------------------------------
# ground-truth self-test
# --------------------------------------------------------------------------
FIXTURE = REPO / "ci/fixtures/floorplan-hazards/baseline-78dac42"
FIXTURE_4A = REPO / "ci/fixtures/floorplan-hazards/class4a-2cd12a4"

# The two macros commit 2cd12a4 re-phased.  They are the class-4a ground truth:
# both were half an M3 pitch off grid on FIXTURE_4A, both are on grid at HEAD,
# and both were clear on FIXTURE (which predates the move that knocked the first
# of them off).  Named, not counted -- see selftest section 4a.
CLASS4A_GROUND_TRUTH = ("way0_cache_ram_data_ram_0_word_3_i",
                        "way1_cache_ram_data_ram_0_word_0_i")


def selftest(args) -> int:
    """Validate against the four cases established on 2026-08-21/22.

    If any assertion below fails, the checker is wrong.  Do NOT adjust the
    expectations -- they come from commit 78dac42's own measurements and from
    ASIC/genus-innovus/calibre_runs/drc_toolkit_20260817/*.drc.results.
    """
    cases = []

    def collect(label, fp_spec, pp_spec=None, against=None):
        # THE POWER PLAN IS PINNED WITH THE FLOORPLAN, not inferred from the
        # label.  A pinned floorplan read against a live power plan is not a
        # pinned arm: the M9 band grid every class-1/2 number is anchored on
        # would drift out from under it.
        a = argparse.Namespace(**vars(args))
        a.floorplan = fp_spec
        a.power_plan = pp_spec or args.power_plan
        a.against = against
        a.json = None
        a.strict = False
        rc, rep, js = run(a)
        cases.append((label, rc, js))
        return js

    print("GROUND-TRUTH VALIDATION")
    print("=" * 72)
    ok = True

    if not (FIXTURE / "floorplan.tcl").is_file():
        print(f"FAIL  fixture missing: {FIXTURE/'floorplan.tcl'}")
        return 2

    if not (FIXTURE_4A / "floorplan.tcl").is_file():
        print(f"FAIL  fixture missing: {FIXTURE_4A/'floorplan.tcl'}")
        return 2

    base = collect("baseline-78dac42^", str(FIXTURE / "floorplan.tcl"),
                   str(FIXTURE / "power_plan.tcl"))
    bad4a = collect("class4a-2cd12a4^", str(FIXTURE_4A / "floorplan.tcl"),
                    str(FIXTURE_4A / "power_plan.tcl"))
    head = collect("worktree", args.floorplan)

    def tags_of(js, cls):
        """Set of macro tokens named by findings of this class."""
        s = set()
        for f in js["findings"]:
            if f["cls"] == cls:
                for part in f["macro"].split(" -> "):
                    s.add(part)
        return s

    def has(tags, token):
        return any(token in t for t in tags)

    def check(desc, good, detail=""):
        nonlocal ok
        print(f"  [{'PASS' if good else 'FAIL'}] {desc}")
        if detail:
            print(f"         {detail}")
        if not good:
            ok = False

    print("\n1. CLASS 1 -- baseline (78dac42^) must flag way0_word_3")
    print("   ground truth: commit 78dac42 -- 'Exactly two did: way0_word_3")
    print("   (top 426.40 vs 424.500) and way1_word_0 (top 246.40 vs 244.500)'")
    b1 = tags_of(base, 1)
    check("baseline class-1 flags way0_..._word_3_i",
          has(b1, "way0_cache_ram_data_ram_0_word_3_i"), f"got {sorted(b1)}")
    check("baseline class-1 flags way1_..._word_0_i (the second proven case)",
          has(b1, "way1_cache_ram_data_ram_0_word_0_i"))
    check("baseline class-1 flags EXACTLY those two", len(b1) == 2)

    print("\n2. CLASS 2 -- the PINNED baseline must flag net imem rf_32k and net dmem rf_16k")
    print("   ground truth: those two were moved -1.100 and -1.150 on 2026-08-21 to")
    print("   put their edges exactly on the band boundaries 1504.500 / 1624.500.")
    print("   THE ARM IS THE PINNED BASELINE, NOT THE WORKTREE.  It was the worktree")
    print("   until 2026-08-25, and it had been red since the day the defect was")
    print("   fixed -- five FAIL lines in a selftest, for a repair.  An expectation")
    print("   that goes red when the thing it describes is REPAIRED is not ground")
    print("   truth, it is a countdown; the arm belongs on the revision that carries")
    print("   the defect, and the worktree gets the opposite assertion.")
    h2 = tags_of(base, 2)
    check("baseline class-2 flags the network-core rf_32k",
          has(h2, "u_region_imem_0_u_mem_u_sram_gen_rf_32k"), f"got {sorted(h2)}")
    check("baseline class-2 flags the network-core rf_16k",
          has(h2, "u_region_dmem_0_u_sram_u_sram_gen_rf_16k"))
    check("baseline class-2 flags EXACTLY those two", len(h2) == 2)
    fixes = {f["macro"]: f["detail"]["min_move_y"]
             for f in base["findings"] if f["cls"] == 2}
    for token, want in (("rf_32k", -1.100), ("rf_16k", -1.150)):
        got = next((v for k, v in fixes.items() if token in k), None)
        check(f"smallest clearing move for {token}: want {want:+.3f}",
              got is not None and abs(got - want) < 1e-6,
              f"got {got if got is None else format(got, '+.3f')}")
    check("worktree class 2 is now 0 -- the fix landed and has stayed landed",
          not tags_of(head, 2), f"got {sorted(tags_of(head, 2))}")

    print("\n3. CLASS 3 -- the pairs that produced the 22 M4.S.2.1 markers")
    print("   ground truth: ASIC/genus-innovus/calibre_runs/drc_toolkit_20260817/")
    print("   nanosoc_eth_chiplet_pads.drc.results -- 28 M4.S.2.1 markers, of which")
    print("   22 are the 0.155um-wide family, on way1_word_1 x13, way1_word_3 x6,")
    print("   way0_word_2 x2, way1_word_2 x1.  78dac42 took that family 22 -> 2.")
    b3 = tags_of(base, 3)
    for token in ("way1_cache_ram_data_ram_0_word_1_i",
                  "way1_cache_ram_data_ram_0_word_3_i",
                  "way0_cache_ram_data_ram_0_word_2_i",
                  "way1_cache_ram_data_ram_0_word_2_i"):
        check(f"baseline class-3 covers {token}", has(b3, token))
    n3h = len([f for f in head["findings"] if f["cls"] == 3])
    check("worktree still flags residual class-3 hazard (22 -> 2, not 0)", n3h > 0,
          f"{n3h} pairs flagged")
    npairs_b = base["census"]["macro_pairs_tested"]
    n3b = len([f for f in base["findings"] if f["cls"] == 3])
    print(f"         over-approximation on the baseline: {n3b} of {npairs_b} "
          f"adjacent pairs flagged; 4 of them carry the 22 real markers.")

    print("\n4a. CLASS 4a -- the escape-track-grid check, proven in BOTH directions")
    print("   ground truth: commit 2cd12a4.  flash_cache_data obstructs its cut")
    print("   layers over 100% of its footprint, so a pin is reachable only planar")
    print("   and the first via has to land outside the pin edge, on an M3 track,")
    print("   clear of the macro's own cut obstruction.  Two macros sat half a pitch")
    print("   off that grid; two pins took the last track INSIDE the footprint, where")
    print("   the cut layer is obstructed.  Five Regular Wire violations, one hour")
    print("   into a 2h38m route.  The fix was +0.100 on each.")
    print("   THREE PINNED ARMS, and the assertions are BY MACRO, never by total --")
    print("   a total would rot the moment an unrelated macro is fixed or added.")

    b4 = tags_of(bad4a, "4a")
    g4 = tags_of(head, "4a")
    p4 = tags_of(base, "4a")
    for tok in CLASS4A_GROUND_TRUTH:
        check(f"KNOWN-BAD  (2cd12a4^) flags {tok}", has(b4, tok), f"got {sorted(b4)}")
    for tok in CLASS4A_GROUND_TRUTH:
        check(f"KNOWN-GOOD (worktree, post-fix) does NOT flag {tok}", not has(g4, tok))
    for tok in CLASS4A_GROUND_TRUTH:
        check(f"KNOWN-GOOD (78dac42^, pre-defect) does NOT flag {tok}", not has(p4, tok))

    d4 = {f["macro"]: f["detail"] for f in bad4a["findings"] if f["cls"] == "4a"}
    for tok in CLASS4A_GROUND_TRUTH:
        det = next((v for k, v in d4.items() if tok in k), None)
        check(f"{tok[:34]}: the pin edge is exactly HALF a track pitch off",
              det is not None and abs(abs(det["phase"]) - det["pitch"] / 2) < 1e-9,
              "" if det is None else f"phase {det['phase']:+.3f} against pitch {det['pitch']}")
        check(f"{tok[:34]}: the first track outside is illegal by the LEF's own rule",
              det is not None and det["clearance"] < det["spacing"],
              "" if det is None else
              f"clearance {det['clearance']} against the cut rule {det['spacing']}")
        check(f"{tok[:34]}: prescribed move is +0.100, which is what 2cd12a4 applied",
              det is not None and abs(det["min_move_y"] - 0.100) < 1e-9,
              "" if det is None else f"got {det['min_move_y']:+.3f}")

    # The 78dac42^ arm is pinned by NAME so it is exact rather than merely "0":
    # there IS one class-4a flag there and it is not one of the two under test.
    check("78dac42^ arm: its only class-4a flag is the eth_scratch_tx rf_08k, which",
          bool(p4) and all("eth_scratch_tx" in x for x in p4),
          f"pre-dates every macro move in this history -- got {sorted(p4)}")

    print("   LIVE (information, not an assertion -- pinning the worktree's own")
    print("   findings is the mistake section 2 records):")
    for f in head["findings"]:
        if f["cls"] == "4a":
            d = f["detail"]
            print(f"         {f['id']} {f['macro'][-46:]:<46} edge {d['edge']:>9.3f} "
                  f"phase {d['phase']:+.3f} clearance {d['clearance']:.3f} "
                  f"< {d['spacing']}  -> d{d['axis']} {d['min_move_y']:+.3f}")

    print("\n4b. CLASS 4b -- must be reported as NOT DETECTED, never as a verdict")
    n4f = [f for f in head["findings"] if f["cls"] == 4 and f["severity"] == "FAIL"]
    check("no class-4b finding is rated FAIL", not n4f)
    hard_present = any(f["cls"] in (1, 2, "4a") for f in head["findings"])
    check("the verdict follows the HARD classes only (1, 2, 4a)",
          head["verdict"] == ("FAIL" if hard_present else "PASS"),
          f"verdict={head['verdict']} hard={head['hard']} advisory={head['advisory']}")

    print("\n5. VACUITY -- every census row must be non-zero")
    for label, rc, js in cases:
        zeros = [k for k, v in js["census"].items()
                 if v == 0 and k not in ("patterns_unresolved",
                                         "differential_edges_into_channel")]
        check(f"{label}: {len(js['census'])} census rows, no zeros", not zeros,
              f"zeros={zeros}" if zeros else
              ", ".join(f"{k}={v}" for k, v in js["census"].items()))

    print("\n5b. VACUITY GUARDS -- a mutilated input must exit 2, never 0")
    print("    Fixtures under ci/fixtures/floorplan-hazards/vacuity-*.")
    for name, why in (
            ("vacuity-no-macros", "every place_macro commented out"),
            ("vacuity-stale-pattern", "one pattern renamed so it matches 0 instances"),
            ("vacuity-wrong-die", "die resized so the derived core box is wrong")):
        f = FIXTURE.parent / name / "floorplan.tcl"
        if not f.is_file():
            check(f"{name} fixture present", False, f"missing {f}")
            continue
        a = argparse.Namespace(**vars(args))
        a.floorplan, a.against, a.json, a.selftest = str(f), None, None, False
        try:
            _rc, _rep, js = run(a)
            check(f"{name} ({why}) refuses to measure", False,
                  f"it returned verdict {js['verdict']} instead of exiting 2")
        except Vacuous as e:
            check(f"{name} ({why}) refuses to measure", True, str(e)[:110])

    print("\n5c. FAIL POLICY -- class 3 must not fail alone, --strict must make it")
    print("    Proven on a REAL input rather than asserted.  Every class-1/2/4a move")
    print("    the worktree run prescribes is applied AT ONCE to a scratch floorplan,")
    print("    which should take the hard count to zero and leave the class-3")
    print("    advisories where they were.  That one run proves three things: the")
    print("    prescriptions are collectively real, a clean-of-hard design PASSES")
    print("    with advisories outstanding, and --strict turns the same input red.")
    hard_moves = []
    for f in head["findings"]:
        d = f.get("detail", {})
        if f["cls"] in (1, 2, "4a") and d.get("min_move_y") is not None:
            hard_moves.append((d["pattern"], "dy", d["min_move_y"]))
    if not hard_moves:
        print("    NOT MEASURED: the worktree carries no hard finding with a move, so")
        print("    there is nothing to clear here.  That is not a pass for the policy.")
        print("    Re-run this selftest against a revision that carries one.")
    else:
        js0, e0 = run_moved(args, hard_moves, strict=False)
        js1, e1 = run_moved(args, hard_moves, strict=True) if not e0 else (None, e0)
        check("the prescribed hard moves all apply and the run still measures",
              js0 is not None, e0 or "")
        if js0 is not None:
            check("applying every hard prescription at once takes hard to 0",
                  js0["hard"] == 0,
                  f"hard={js0['hard']} counts={js0['counts']}")
            check("class-3 advisories survive that (so the input is a real test)",
                  js0["advisory"] > 0, f"advisory={js0['advisory']}")
            check("default: 0 hard + advisories present -> PASS",
                  js0["verdict"] == "PASS", f"verdict={js0['verdict']}")
        if js1 is not None:
            check("--strict: the SAME input -> FAIL",
                  js1["verdict"] == "FAIL" and js1["hard"] == 0,
                  f"verdict={js1['verdict']} hard={js1['hard']}")

    print("\n6. DISCRIMINATION -- can the checker stop saying FAIL?")
    print("   A gate that only ever fails has not been shown to measure anything.")
    print("   Each suggested move is applied ON ITS OWN and the floorplan re-checked;")
    print("   the finding it was suggested for must disappear.  That also proves the")
    print("   suggested move is a real fix and not a number.")
    check("baseline verdict is FAIL", base["verdict"] == "FAIL")
    for f in head["findings"]:
        d = f.get("detail", {})
        if f["cls"] in (1, 2, "4a") and d.get("min_move_y") is not None:
            axis, delta = "dy", d["min_move_y"]
        elif f["cls"] in (3, "4a") and d.get("min_move_x") is not None:
            axis, delta = "dx", d["min_move_x"]
        else:
            continue
        res = apply_move(args, d["pattern"], axis, delta, f["cls"], f["macro"])
        check(f"class {f['cls']} {f['id']}: {axis}={delta:+.3f} clears it", res is True,
              "" if res is True else str(res))

    print("   ...and on the PINNED known-bad arm, where the answer is recorded")
    print("   history: 2cd12a4 applied exactly these two moves and the re-route went")
    print("   5 violations -> 0 against a matched rip-only control that still showed 5.")
    for f in bad4a["findings"]:
        d = f.get("detail", {})
        if f["cls"] != "4a" or d.get("min_move_y") is None:
            continue
        if not any(tok in f["macro"] for tok in CLASS4A_GROUND_TRUTH):
            continue
        res = apply_move(args, d["pattern"], "dy", d["min_move_y"], "4a", f["macro"],
                         str(FIXTURE_4A / "floorplan.tcl"),
                         str(FIXTURE_4A / "power_plan.tcl"))
        check(f"class 4a {f['id']} on 2cd12a4^: dy={d['min_move_y']:+.3f} clears it",
              res is True, "" if res is True else str(res))

    print("\n" + "=" * 72)
    print("SELFTEST: " + ("PASS" if ok else "FAIL"))
    return 0 if ok else 1


def _apply_moves(text: str, moves) -> tuple[str, list]:
    """Rewrite place_macro coordinates in floorplan TEXT.  Returns the new text
    and the patterns that were not found (never a silent no-op)."""
    lines = text.split("\n")
    missing = []
    for pattern, axis, delta in moves:
        hit = False
        for i, l in enumerate(lines):
            m = PLACE_MACRO.match(l)
            if not m or m.group(1).strip() != pattern:
                continue
            x, y = float(m.group(2)), float(m.group(3))
            if axis == "dy":
                y = round(y + delta, 4)
            else:
                x = round(x + delta, 4)
            lines[i] = re.sub(r"^(\s*place_macro\s+\{[^}]*\})\s+[-\d.eE+]+\s+[-\d.eE+]+",
                              lambda mo, x=x, y=y: f"{mo.group(1)} {x:.6f} {y:.6f}", l)
            hit = True
            break
        if not hit:
            missing.append(pattern)
    return "\n".join(lines), missing


def run_moved(args, moves, fp_spec=None, pp_spec=None, strict=None):
    """Apply moves to a SCRATCH copy of a floorplan and re-run the whole check.

    Returns (js, error).  Nothing in the repository is written: the scratch
    floorplan goes to a temporary directory, and the power plan is read from
    wherever the caller says -- which for a pinned arm must be that arm's own.
    """
    import tempfile
    fp_spec = fp_spec or args.floorplan
    pp_spec = pp_spec or args.power_plan
    text = read_tcl_pair(fp_spec, pp_spec)[0]
    text, missing = _apply_moves(text, moves)
    if missing:
        return None, f"pattern(s) not found in the floorplan: {missing}"
    a = argparse.Namespace(**vars(args))
    a.against, a.json, a.selftest = None, None, False
    a.power_plan = pp_spec
    if strict is not None:
        a.strict = strict
    d = Path(tempfile.mkdtemp(prefix="fphz-"))
    (d / "floorplan.tcl").write_text(text)
    a.floorplan = str(d / "floorplan.tcl")
    try:
        _rc, _rep, js = run(a)
    except Vacuous as e:
        return None, f"VACUOUS after the move: {e}"
    return js, None


def apply_move(args, pattern, axis, delta, cls, macro, fp_spec=None, pp_spec=None):
    """Apply one suggested move to a scratch copy and re-run; True if it cleared."""
    js, err = run_moved(args, [(pattern, axis, delta)], fp_spec, pp_spec)
    if err:
        return err
    still = [f for f in js["findings"] if f["cls"] == cls and macro in f["macro"]]
    if still:
        return f"still flagged: {still[0]['detail']}"
    return True


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--floorplan", default=str(DEF_FLOORPLAN),
                    help="floorplan.tcl, or git:<rev> for that revision of it")
    ap.add_argument("--power-plan", default=str(DEF_POWERPLAN),
                    help="power_plan.tcl, or git:<rev>")
    ap.add_argument("--netlist", help="gate netlist for place_macro pattern resolution "
                                      "(default: newest under ASIC/eth-chiplet/build/*/outputs)")
    ap.add_argument("--lef", action="append", help="macro LEF (repeatable)")
    ap.add_argument("--tech-lef", help="technology LEF (SITE grid, M4 SPACINGTABLE)")
    ap.add_argument("--against", help="reference floorplan for the class-4 differential "
                                      "(path or git:<rev>)")
    ap.add_argument("--json", help="write the machine-readable report here")
    ap.add_argument("--strict", action="store_true",
                    help="make class-3 advisories fail the run as well "
                         "(default: only class 1, 2 and 4a fail)")
    ap.add_argument("--selftest", action="store_true",
                    help="run the ground-truth validation and exit")
    args = ap.parse_args(argv)

    if args.selftest:
        try:
            return selftest(args)
        except Vacuous as e:
            print(f"SELFTEST COULD NOT MEASURE: {e}", file=sys.stderr)
            return 2

    try:
        rc, rep, js = run(args)
    except Vacuous as e:
        print("check_floorplan_hazards: COULD NOT MEASURE", file=sys.stderr)
        print(f"  {e}", file=sys.stderr)
        print("  Exiting 2.  A check that measures nothing must not pass.", file=sys.stderr)
        return 2
    print("\n".join(rep.lines))
    if args.json:
        Path(args.json).write_text(json.dumps(js, indent=2))
        print(f"\n  json -> {args.json}")
    return rc


if __name__ == "__main__":
    sys.exit(main())
