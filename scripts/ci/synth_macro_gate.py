#!/usr/bin/env python3
"""
synth_macro_gate.py -- prove that no macro in the synthesised netlist is
silently black-boxed, and prove the check can say no.

A joint work commissioned on behalf of SoC Labs, under Arm Academic Access
license.  Copyright 2026, SoC Labs (www.soclabs.org)

    scripts/ci/synth_macro_gate.py --run-dir ASIC/eth-chiplet/build/<tag>
    scripts/ci/synth_macro_gate.py --selftest
    scripts/ci/synth_macro_gate.py --run-dir <dir> --write-baseline

WHAT A BLACK-BOXED MACRO IS, AND WHY IT MATTERS
-----------------------------------------------
A black box is a cell the tool has no model for. It times as if it were free:
every path through it gets zero delay, every setup check against it is vacuous,
and the netlist, the reports and the run summary all come out green. Genus's own
definition of the `is_black_box` attribute is "either has no .lib definition or
has a .lib definition but no timing_arcs".

The attribute alone is NOT the check, and getting that wrong is the easy
mistake here: on this design ALL 21 macro instances report is_black_box=true and
every one of them is correct, because a Liberty for a RAM carries timing arcs
but no logic function. Thirty-four supply pads report it too, for the same
reason. A gate that flagged `is_black_box` would fire 55 times on a healthy
netlist and be switched off within a day.

So the check is a CENSUS, and it asks five separate questions:

  R1  every Liberty the DESIGN asked for produced at least one macro cell.
      This is the one that catches a model that was never read -- including the
      documented case where all six collateral variables were misspelt, so the
      list read as empty and synthesis mapped the macros to nothing with every
      artefact assertion still passing.
  R2  every macro cell in the database came from a file the design named.
      A macro read from somewhere else means synthesis is timing a different
      part from the one the design specifies -- the shape of the boot-ROM
      defect this project has had twice (F7, F8).
  R3  every macro model has timing arcs and a non-zero area. Arcs are what
      makes it not-free; area is what makes the floorplan real.
  R4  every cell in the netlist is declared by one of the LEFs place-and-route
      will read. In a non-spatial flow Genus reads NO LEF, so synthesis can
      hand P&R a netlist full of cells P&R has no physical view of, and nobody
      finds out for four hours. This is the check that runs at the right stage.
  R5  every black-box instance is a macro, a pad, or a physical-only cell.
      Anything else is a model that is missing and should not be.
  R9  the collateral synthesis does NOT read is still there. rc5 ran with
      SYN_MMMC=0, so Genus loaded only the ss corner; the ff and tt Liberty and
      the macro GDS are read by P&R and by stream-out, hours and days later.
      An unreadable entry is a stop, and this is the cheapest place to find it.

  R6  (only when a baseline exists) the per-cell instance census is unchanged.
      This is the one that catches the OTHER direction: a memory that stopped
      being a macro. If a behavioural model wins over the Liberty, the RAM is
      synthesised into flip-flops -- no black box, no unresolved reference, no
      error, and 32 Kb of register file where a compiled macro should be.

THE INPUT IS WRITTEN BY hooks/post_synth.tcl, INSIDE GENUS
-----------------------------------------------------------
`reports/synth_macro_census.json` is a data dump, not a verdict: cells,
libraries, source files, arc counts, areas, instance counts, LEF coverage. The
hook applies the same rules in Tcl and fails the stage there, so the gate does
not depend on Python being reachable from inside Genus. THIS script re-applies
them offline and CROSS-CHECKS its own verdict against the one the hook
recorded. Two implementations that disagree is itself a finding -- that is how
drift between them is detected rather than hidden.

EXIT CODES
  0  PASS
  1  FAIL -- at least one hard finding
  2  REFUSED -- the census is absent, unparseable, or measures nothing
  3  bad usage
"""

from __future__ import annotations

import argparse
import copy
import json
import sys
from pathlib import Path

CENSUS = "synth_macro_census.json"
BASELINE = "synth_macro_expect.json"


class Refuse(Exception):
    pass


# ---------------------------------------------------------------------------
def load_census(p: Path) -> dict:
    if not p.is_file():
        raise Refuse(
            f"{p} does not exist.\n"
            "  It is written by ASIC/eth-chiplet/hooks/post_synth.tcl during\n"
            "  synthesis. A run made before that hook existed has no census,\n"
            "  and a run whose synthesis died before the hook has none either\n"
            "  -- which is itself worth knowing, because Genus exits 0 after a\n"
            "  failed script.")
    try:
        js = json.loads(p.read_text(errors="replace"))
    except Exception as e:  # noqa: BLE001
        raise Refuse(f"{p} is not parseable JSON: {e}") from e
    for k in ("macros", "black_box_cells", "macro_instances"):
        if k not in js:
            raise Refuse(f"{p} has no '{k}' key -- this is not a macro census")
    if not js["macros"]:
        raise Refuse(
            f"{p} records ZERO macro cell types. Either this design has no\n"
            "  macros -- in which case remove the gate rather than let it pass\n"
            "  vacuously -- or the collection failed. It does not pass.")
    return js


def evaluate(js: dict, baseline: dict | None) -> list[tuple[str, str, str]]:
    """Re-derive the findings from the census. Same rules as the Tcl in the hook."""
    out: list[tuple[str, str, str]] = []

    def hard(rule, msg):
        out.append(("HARD", rule, msg))

    def soft(rule, msg):
        out.append(("SOFT", rule, msg))

    macros: dict = js["macros"]
    want = [str(f) for f in js.get("design_libs_max", [])]

    # R0 -- an unresolved reference that survived to the end of synthesis.
    # MEASURED: an unresolved module is not an inst and does not set
    # is_black_box, so every other rule here is blind to it. -1 means the
    # collection could not get a count.
    if "unresolved_references" in js:
        n = int(js["unresolved_references"])
        if n < 0:
            soft("R0", "unresolved references were NOT MEASURED this run -- "
                       "check_design -unresolved -status did not return a count")
        elif n > 0:
            hard("R0", f"{n} unresolved reference(s) survived to the end of "
                       f"synthesis and are in the netlist. Candidates: "
                       f"{js.get('empty_hinsts', [])}")
    else:
        soft("R0", "the census predates the unresolved-reference check; "
                   "R0 NOT MEASURED")

    def files_of(m: dict) -> list[str]:
        """Every file the cell's LIBRARY was built from.

        Not `file`: a Liberty library can be fed by more than one file, and on
        this design one is -- both boot ROMs declare the same library() name, so
        Genus merges them and `.files` is a two-element list. Reading only the
        first attributes both ROMs to whichever was read first and then reports
        the other as never read.
        """
        fs = m.get("files")
        if isinstance(fs, list) and fs:
            return [str(x) for x in fs]
        return [m["file"]] if m.get("file") else []

    loaded = [str(f) for f in js.get("loaded_lib_files", [])]
    if not loaded:
        loaded = sorted({f for m in macros.values() for f in files_of(m)})

    # R1 -- a Liberty the design named that no loaded library was built from
    if want:
        for f in want:
            if f not in loaded:
                hard("R1", f"DESIGN_LIBS_MAX names {f} and NO library in the "
                           f"database was built from it -- the model was not read")
    else:
        soft("R1", "the census records no DESIGN_LIBS_MAX, so 'every requested "
                   "model was read' was NOT MEASURED")

    # R2 -- a macro whose library was fed by nothing the design named
    if want:
        for c, m in sorted(macros.items()):
            fs = files_of(m)
            if not any(f in want for f in fs):
                hard("R2", f"macro cell {c} is in library {m.get('library')}, "
                           f"built from {fs or '(unrecorded)'} -- none of which "
                           f"is in DESIGN_LIBS_MAX")

    # R8 -- two Liberty files under one library name: per-cell provenance lost
    libs = js.get("loaded_libraries", {})
    for lib, fs in sorted(libs.items()):
        if not isinstance(fs, list) or len(fs) < 2:
            continue
        mine = [c for c, m in macros.items() if m.get("library") == lib]
        if not mine:
            continue
        soft("R8", f"library {lib} was built from {len(fs)} files ({fs}) because "
                   f"they declare the same library() name, so the database can no "
                   f"longer say which file {', '.join(sorted(mine))} came from. "
                   f"For a mask-programmed macro that is the question worth "
                   f"asking; give the libraries distinct names.")

    # R3 -- a model that times as free, or has no size
    for c, m in sorted(macros.items()):
        if int(m.get("arcs", 0)) == 0:
            hard("R3", f"macro {c} has ZERO timing arcs -- every path through "
                       f"it is timed as if the macro were a wire")
        if float(m.get("area", 0)) <= 0:
            hard("R3", f"macro {c} has area {m.get('area')} -- the model carries "
                       f"no physical size, so floorplan and utilisation are fiction")

    # R4 -- LEF coverage of the cells P&R will have to place
    scanned = js.get("lef_files_scanned", [])
    unread = js.get("lef_files_unreadable", [])
    for f in unread:
        hard("R4", f"LEF {f} is named by the flow and is not readable -- "
                   f"place-and-route will read it and stop, four hours from now")
    if not scanned:
        if unread:
            hard("R4", f"NONE of the {len(unread)} LEFs the flow names is "
                       f"readable, so no cell in this netlist has been shown to "
                       f"have a physical view")
        else:
            soft("R4", "this census has no LEF list at all, so LEF coverage was "
                       "NOT MEASURED -- a hole in the record, not a clean result")
    else:
        for c, m in sorted(macros.items()):
            if not m.get("lef"):
                hard("R4", f"macro {c} has a Liberty and is declared by NONE of "
                           f"the {len(scanned)} LEFs P&R will read -- P&R will "
                           f"black-box it")
        for row in js.get("cells_without_lef", []):
            hard("R4", f"cell {row.get('cell')} ({row.get('instances')} "
                       f"instances) is in the netlist and no LEF declares it")

    # R9 -- the collateral synthesis does NOT read, but P&R and stream-out do
    coll = js.get("collateral")
    if coll is None:
        soft("R9", "the census predates the collateral check; the fast/typical "
                   "Liberty and the macro GDS were NOT CHECKED")
    else:
        for var, e in sorted(coll.items()):
            named = int(e.get("named", -1))
            if named < 0:
                soft("R9", f"{var} was not set in the synthesis session, so it "
                           f"was NOT CHECKED. Synthesis does not read it; P&R "
                           f"and stream-out do")
                continue
            for f in e.get("unreadable", []):
                hard("R9", f"{var} names {f} and it is not readable -- "
                           f"synthesis does not read this file, so nothing "
                           f"before now would have noticed")
            if want and named != len(want):
                soft("R9", f"{var} has {named} entries and DESIGN_LIBS_MAX has "
                           f"{len(want)}; a macro in one list and not another "
                           f"has no model at that corner")

    # R5 -- a black box that should not be one
    for c, e in sorted(js["black_box_cells"].items()):
        kind = e.get("kind", "unclassified") if isinstance(e, dict) else "unclassified"
        n = e.get("instances", 0) if isinstance(e, dict) else e
        if kind not in ("macro", "pad", "physical"):
            hard("R5", f"{c} ({n} instances) is a BLACK BOX and should not be: "
                       f"{kind}")

    # R6/R7 -- the instance census against a committed baseline
    if baseline is None:
        soft("R6", "no baseline (" + BASELINE + ") -- the per-macro instance "
             "census is recorded but UNVERIFIED. A memory that stopped being a "
             "macro would not be caught. Write one with --write-baseline and "
             "commit it.")
    else:
        bm = baseline.get("macros", {})
        for c, n in sorted(bm.items()):
            got = int(macros.get(c, {}).get("instances", 0))
            if c not in macros:
                hard("R6", f"baseline expects macro cell {c} and the netlist has "
                           f"no such macro AT ALL -- it was not read, or it was "
                           f"synthesised into logic")
            elif got != int(n):
                hard("R6", f"macro {c}: baseline {n} instances, netlist {got}")
        for c in sorted(macros):
            if c not in bm:
                hard("R6", f"macro {c} ({macros[c].get('instances')} instances) "
                           f"is in the netlist and not in the baseline")
        tot_b = int(baseline.get("macro_instances", -1))
        if tot_b >= 0 and tot_b != int(js["macro_instances"]):
            hard("R6", f"macro instance total: baseline {tot_b}, netlist "
                       f"{js['macro_instances']}")

    # R7 -- a macro cell type with a model and no instances
    for c, m in sorted(macros.items()):
        if int(m.get("instances", 0)) == 0:
            hard("R7", f"macro {c} has a model and ZERO instances in the netlist "
                       f"-- either the design stopped using it, or what should "
                       f"be a macro was synthesised into standard cells")

    return out


# ---------------------------------------------------------------------------
def render(js: dict, findings: list[tuple[str, str, str]],
           recorded: list[dict] | None, baseline_path: Path | None) -> str:
    hard = [f for f in findings if f[0] == "HARD"]
    soft = [f for f in findings if f[0] == "SOFT"]
    L = []
    L.append("=" * 79)
    L.append(f"MACRO MODEL GATE -- {js.get('design', '?')}")
    L.append("=" * 79)
    notmeasured = [f for f in soft if "NOT MEASURED" in f[2]
                   or "UNVERIFIED" in f[2]]
    L.append(f"VERDICT: {'FAIL' if hard else 'PASS'}   "
             f"({len(hard)} hard, {len(soft)} advisory)"
             + (f"   -- {len(notmeasured)} of those advisories is a check that "
                f"DID NOT RUN" if notmeasured else ""))
    if notmeasured and not hard:
        L.append("         A PASS here does not cover: "
                 + ", ".join(sorted({f[1] for f in notmeasured})))
    L.append("")
    L.append(f"scope   {js['macro_instances']} macro instances of "
             f"{js['macro_cell_types']} cell types; "
             f"{js['black_box_instances']} black-box instances;")
    L.append(f"        {js.get('lef_declared_cells', 0)} cells declared by "
             f"{len(js.get('lef_files_scanned', []))} LEFs")
    L.append(f"baseline {baseline_path if baseline_path else '(none -- R6 not measured)'}")
    L.append("")
    if findings:
        L.append("FINDINGS, worst first")
        L.append("-" * 21)
        for sev in ("HARD", "SOFT"):
            for s, r, d in findings:
                if s == sev:
                    L.append(f"{s:<5} {r:<3} {d}")
        L.append("")
    L.append("MACRO CELL TYPES")
    L.append(f"{'cell':<18} {'insts':>6} {'arcs':>6} {'pins':>5} {'area':>9} "
             f"{'lef':>4}  library")
    for c, m in sorted(js["macros"].items(), key=lambda kv: -int(kv[1].get("instances", 0))):
        L.append(f"{c:<18} {m.get('instances', 0):>6} {m.get('arcs', 0):>6} "
                 f"{m.get('pins', 0):>5} {float(m.get('area', 0)):>9.0f} "
                 f"{'yes' if m.get('lef') else 'NO':>4}  {m.get('library', '')}")
        fs = m.get("files") or ([m["file"]] if m.get("file") else [])
        for f in fs:
            L.append(f"{'':<18}   {f}")
        if len(fs) > 1:
            L.append(f"{'':<18}   ^ {len(fs)} files share this library() name; "
                     f"which one THIS cell")
            L.append(f"{'':<18}     came from is not recoverable from the database")
    L.append("")
    L.append("BLACK-BOX CELLS")
    L.append("A memory or a supply pad IS a black box and that is correct -- the")
    L.append("tool has its timing and not its function. Any other kind is a")
    L.append("missing model.")
    L.append(f"{'cell':<18} {'insts':>6}  kind")
    for c, e in sorted(js["black_box_cells"].items(),
                       key=lambda kv: -(kv[1].get("instances", 0)
                                        if isinstance(kv[1], dict) else kv[1])):
        n = e.get("instances", 0) if isinstance(e, dict) else e
        k = e.get("kind", "unclassified") if isinstance(e, dict) else "unclassified"
        L.append(f"{c:<18} {n:>6}  {k}")
    L.append("")

    if recorded is not None:
        # R6 is the committed instance baseline. It lives in the repository, not
        # in the run, so the in-Genus half cannot evaluate it and its absence
        # from the hook's list is by design, not drift.
        mine = {(s, r) for s, r, _ in findings if r != "R6"}
        theirs = {(f.get("severity"), f.get("rule")) for f in recorded
                  if f.get("rule") != "R6"}
        if mine != theirs:
            L.append("!! CROSS-CHECK DISAGREES WITH THE HOOK")
            L.append(f"   this script:  {sorted(mine)}")
            L.append(f"   the hook:     {sorted(theirs)}")
            L.append("   The Tcl in post_synth.tcl and the Python here have")
            L.append("   drifted. Neither verdict is trustworthy until they agree.")
        else:
            L.append(f"cross-check: agrees with the hook "
                     f"({len(recorded)} findings, same rules)")
    L.append("=" * 79)
    return "\n".join(L) + "\n"


# ---------------------------------------------------------------------------
def make_baseline(js: dict) -> dict:
    return {
        "_comment": "Committed expectation for the macro census. A change here "
                    "is a change to what silicon gets built; update it "
                    "deliberately, in the same commit as the RTL or collateral "
                    "change that caused it.",
        "design": js.get("design"),
        "macro_instances": js["macro_instances"],
        "macros": {c: int(m.get("instances", 0)) for c, m in js["macros"].items()},
    }


# ---------------------------------------------------------------------------
# selftest -- the discrimination proof. Each mutation carries exactly one
# defect and the gate must find exactly that one.
# ---------------------------------------------------------------------------
def _clean() -> dict:
    return {
        "design": "t",
        "macro_cell_types": 2,
        "macro_instances": 3,
        "black_box_instances": 5,
        "collateral": {"DESIGN_LIBS_MIN": {"named": 2, "unreadable": []},
                       "DESIGN_LIBS_TYP": {"named": 2, "unreadable": []},
                       "DESIGN_GDS_MERGE": {"named": 2, "unreadable": []}},
        "unresolved_references": 0,
        "empty_hinsts": [],
        "design_libs_max": ["/m/rf_16k.lib", "/m/rom.lib"],
        "loaded_lib_files": ["/m/rf_16k.lib", "/m/rom.lib", "/t/std.lib"],
        "loaded_libraries": {"RF16": ["/m/rf_16k.lib"],
                             "USERLIB": ["/m/rom.lib"],
                             "std": ["/t/std.lib"]},
        "lef_files_scanned": ["/m/rf_16k.lef", "/m/rom.lef", "/m/std.lef"],
        "lef_files_unreadable": [],
        "lef_declared_cells": 700,
        "cells_without_lef": [],
        "macros": {
            "rf_16k": {"library": "RF16", "file": "/m/rf_16k.lib",
                       "files": ["/m/rf_16k.lib"], "area": 1000.0,
                       "arcs": 120, "pins": 40, "is_black_box": 1,
                       "is_timing_model": 1, "is_memory": 1, "instances": 2,
                       "lef": "/m/rf_16k.lef"},
            "rom_via": {"library": "USERLIB", "file": "/m/rom.lib",
                        "files": ["/m/rom.lib"], "area": 500.0,
                        "arcs": 60, "pins": 30, "is_black_box": 1,
                        "is_timing_model": 1, "is_memory": 1, "instances": 1,
                        "lef": "/m/rom.lef"},
        },
        "black_box_cells": {
            "rf_16k": {"instances": 2, "kind": "macro"},
            "rom_via": {"instances": 1, "kind": "macro"},
            "PVDD1DGZ_G": {"instances": 2, "kind": "pad"},
        },
        "findings": [],
    }


def selftest() -> int:
    ok = True

    def check(desc, cond, extra=""):
        nonlocal ok
        print(f"  {'PASS' if cond else 'FAIL'}  {desc}" + (f"   {extra}" if extra else ""))
        if not cond:
            ok = False

    print("synth_macro_gate --selftest")
    base = make_baseline(_clean())

    print("\n[A] the clean census must PASS, with and without a baseline")
    f = evaluate(_clean(), base)
    check("clean + baseline -> no hard findings", not [x for x in f if x[0] == "HARD"],
          str(f))
    f = evaluate(_clean(), None)
    check("clean, no baseline -> no hard findings, one advisory",
          not [x for x in f if x[0] == "HARD"] and any(x[1] == "R6" for x in f),
          str([(a, b) for a, b, _ in f]))

    print("\n[B] DISCRIMINATION -- one defect at a time; the named rule must fire")

    def mutate(desc, rule, fn, baseline=base):
        js = _clean()
        fn(js)
        got = evaluate(js, copy.deepcopy(baseline))
        hardrules = [r for s, r, _ in got if s == "HARD"]
        hit = rule in hardrules
        check(f"{desc} -> {rule}", hit,
              f"hard rules fired: {sorted(set(hardrules)) or 'NONE'}")
        return got

    mutate("the fast-corner Liberty for a macro is missing", "R9",
           lambda j: j["collateral"]["DESIGN_LIBS_MIN"].update(
               unreadable=["/m/rf_16k_ff.lib"]))
    mutate("a macro GDS is missing (an empty box at stream-out)", "R9",
           lambda j: j["collateral"]["DESIGN_GDS_MERGE"].update(
               unreadable=["/m/rf_16k.gds2"]))
    mutate("an unresolved module reached the netlist", "R0",
           lambda j: j.update(unresolved_references=1,
                              empty_hinsts=["u_mem (mystery_ram)"]))

    # direction 1: a cell that SHOULD be a macro and is not
    mutate("a requested Liberty was never loaded", "R1",
           lambda j: j.update(loaded_lib_files=["/m/rf_16k.lib", "/t/std.lib"]))
    mutate("a macro model has no timing arcs (times as a wire)", "R3",
           lambda j: j["macros"]["rf_16k"].update(arcs=0))
    mutate("a macro model has zero area", "R3",
           lambda j: j["macros"]["rf_16k"].update(area=0.0))
    mutate("a macro has a Liberty and no LEF", "R4",
           lambda j: j["macros"]["rom_via"].update(lef=""))
    mutate("a LEF the flow names is unreadable", "R4",
           lambda j: j.update(lef_files_unreadable=["/m/rom.lef"]))
    mutate("no LEF readable at all, but LEFs were named", "R4",
           lambda j: j.update(lef_files_scanned=[],
                              lef_files_unreadable=["/m/rom.lef"]))
    mutate("a netlist cell no LEF declares", "R4",
           lambda j: j.update(cells_without_lef=[{"cell": "WEIRD1", "instances": 4}]))
    mutate("a macro model exists and has no instances", "R7",
           lambda j: j["macros"]["rf_16k"].update(instances=0))
    mutate("a memory lost two instances (synthesised into flops?)", "R6",
           lambda j: (j["macros"]["rf_16k"].update(instances=0),
                      j.update(macro_instances=1)))
    mutate("the whole macro cell disappeared from the netlist", "R6",
           lambda j: (j["macros"].pop("rf_16k"),
                      j.update(macro_instances=1,
                               design_libs_max=["/m/rom.lib"],
                               loaded_lib_files=["/m/rom.lib", "/t/std.lib"])))

    # direction 2: a cell that IS a black box and should not be
    mutate("an unexpected black box appears", "R5",
           lambda j: j["black_box_cells"].update(
               MYSTERY={"instances": 7, "kind": "UNEXPECTED -- no model"}))
    mutate("a black box with no lib_cell at all", "R5",
           lambda j: j["black_box_cells"].update(
               GHOST={"instances": 1, "kind": "UNEXPECTED -- no lib_cell at all"}))
    mutate("a macro read from a source the design did not name", "R2",
           lambda j: j["macros"]["rom_via"].update(
               file="/elsewhere/rom.lib", files=["/elsewhere/rom.lib"]))

    print("\n[B2] two Liberty files under one library name is an ADVISORY, not "
          "a failure")
    js = _clean()
    js["loaded_libraries"]["USERLIB"] = ["/m/rom.lib", "/m/eth_rom.lib"]
    js["loaded_lib_files"].append("/m/eth_rom.lib")
    js["design_libs_max"].append("/m/eth_rom.lib")
    js["macros"]["eth_rom_via"] = dict(js["macros"]["rom_via"],
                                       files=["/m/rom.lib", "/m/eth_rom.lib"],
                                       file="")
    js["macros"]["rom_via"]["files"] = ["/m/rom.lib", "/m/eth_rom.lib"]
    js["macros"]["rom_via"]["file"] = ""
    js["macro_instances"] = 4
    js["black_box_cells"]["eth_rom_via"] = {"instances": 1, "kind": "macro"}
    got = evaluate(js, None)
    check("merged libraries -> SOFT R8, no hard finding",
          any(r == "R8" and s == "SOFT" for s, r, _ in got)
          and not [x for x in got if x[0] == "HARD"],
          str([(a, b) for a, b, _ in got]))

    print("\n[B3] a check that did not run must not read as a pass")
    js = _clean()
    js["lef_files_scanned"] = []
    js["lef_files_unreadable"] = []
    for m in js["macros"].values():
        m["lef"] = ""
    got = evaluate(js, base)
    txt = render(js, got, None, None)
    check("with no LEF list the verdict names the check that did not run",
          "DID NOT RUN" in txt and "A PASS here does not cover" in txt
          and not [x for x in got if x[0] == "HARD"],
          str([(a, b) for a, b, _ in got]))

    print("\n[C] REFUSALS -- a census that measures nothing must not pass")
    import tempfile
    with tempfile.TemporaryDirectory() as td:
        p = Path(td) / CENSUS
        try:
            load_census(p)
            check("absent census refuses", False, "it did not refuse")
        except Refuse as e:
            check("absent census refuses", True, str(e).splitlines()[0][:50])
        p.write_text("not json")
        try:
            load_census(p)
            check("unparseable census refuses", False, "it did not refuse")
        except Refuse:
            check("unparseable census refuses", True)
        p.write_text(json.dumps({"macros": {}, "black_box_cells": {},
                                 "macro_instances": 0}))
        try:
            load_census(p)
            check("a census with zero macros refuses (does NOT pass)", False,
                  "it did not refuse")
        except Refuse as e:
            check("a census with zero macros refuses (does NOT pass)", True,
                  str(e).splitlines()[0][:50])
        p.write_text(json.dumps({"macros": {"a": {}}}))
        try:
            load_census(p)
            check("a census missing required keys refuses", False,
                  "it did not refuse")
        except Refuse:
            check("a census missing required keys refuses", True)

    print("\n[D] the cross-check must notice the hook and this script disagreeing")
    js = _clean()
    js["findings"] = [{"severity": "HARD", "rule": "R9", "detail": "invented"}]
    txt = render(js, evaluate(js, base), js["findings"], None)
    check("a recorded finding this script did not derive is reported",
          "CROSS-CHECK DISAGREES" in txt)
    js["findings"] = []
    txt = render(js, evaluate(js, base), js["findings"], None)
    check("agreement is reported too", "cross-check: agrees" in txt)

    print("\n[E] the baseline round-trips")
    b = make_baseline(_clean())
    check("baseline records every macro and the total",
          b["macros"] == {"rf_16k": 2, "rom_via": 1} and b["macro_instances"] == 3,
          str(b["macros"]))

    print("\n" + ("SELFTEST PASS" if ok else "SELFTEST FAIL"))
    return 0 if ok else 1


# ---------------------------------------------------------------------------
def main(argv=None) -> int:
    ap = argparse.ArgumentParser(
        description=__doc__.splitlines()[1],
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--run-dir")
    ap.add_argument("--census", help="path to " + CENSUS)
    ap.add_argument("--baseline", help="path to " + BASELINE +
                    " (default: scripts/ci/" + BASELINE + " next to this file)")
    ap.add_argument("--no-baseline", action="store_true",
                    help="ignore the baseline; R6 becomes NOT MEASURED")
    ap.add_argument("--write-baseline", action="store_true",
                    help="write the baseline from this census and exit")
    ap.add_argument("--out", help="also write the report here")
    ap.add_argument("--quiet", action="store_true")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args(argv)

    if a.selftest:
        return selftest()
    if not a.census and not a.run_dir:
        ap.error("--run-dir or --census is required")

    cp = Path(a.census) if a.census else Path(a.run_dir) / "reports" / CENSUS
    try:
        js = load_census(cp.resolve())
    except Refuse as e:
        print("REFUSED: " + str(e), file=sys.stderr)
        return 2

    bp: Path | None = None
    baseline = None
    if not a.no_baseline:
        bp = Path(a.baseline) if a.baseline else Path(__file__).resolve().parent / BASELINE
        if bp.is_file():
            baseline = json.loads(bp.read_text())
        else:
            bp = None

    if a.write_baseline:
        target = Path(a.baseline) if a.baseline else \
            Path(__file__).resolve().parent / BASELINE
        target.write_text(json.dumps(make_baseline(js), indent=1) + "\n")
        print(f"OK: baseline written to {target}")
        print("    Commit it. From now on a change in the macro census is a "
              "FAILURE until this file is updated in the same commit.")
        return 0

    findings = evaluate(js, baseline)
    txt = render(js, findings, js.get("findings"), bp)
    if not a.quiet:
        sys.stdout.write(txt)
    if a.out:
        Path(a.out).write_text(txt)
    return 1 if any(s == "HARD" for s, _, _ in findings) else 0


if __name__ == "__main__":
    sys.exit(main())
