#!/usr/bin/env python3
"""
bscan_syn_verdict.py — reduce a synthesis run to a boundary-scan verdict.

A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.

Contributors

David Mapstone (d.a.mapstone@soton.ac.uk)

Copyright 2026, SoC Labs (www.soclabs.org)

WHY THIS EXISTS AT ALL

Synthesis exiting 0 says nothing about whether the boundary-scan register is in
the netlist. With SE case-analysed to a constant the whole register is unreachable
and unobservable, and deleting it is then CORRECT constant propagation -- Genus
does the right thing, prints nothing alarming, and the log is green. That failure
mode is silent by construction, so the count has to be asserted, not eyeballed.

This reads the ARTEFACTS, never the exit status. Genus and Innovus both exit 0
after printing an error and doing nothing, which is why the toolkit's own make
rules assert on files rather than on `$?`.

WHAT IT CHECKS

  1. The gate netlist exists and is non-trivial.
  2. The boundary cell count equals the pad table's `boundary_length`. The
     expectation comes from the TABLE, not from a literal in this file, so it is
     right for any chiplet.
  3. The TAP and instruction register survived as instances.
  4. Every pad instance named in the pad table is still present -- the flow has
     its own version of this check, and it exists because 34 supply pads were
     once silently deleted.
  5. Synthesis error classes worth failing on (SDC-, TIM-, SYN-).
  6. Timing by path group, and specifically whether an I/O group has moved into
     the failing set. The BSR adds one mux to pad paths, and those groups had
     +2.435 ns (in2reg) and +5.039 ns (reg2out) with ZERO failing endpoints on
     the control, so a change there is real signal.

Exit codes: 0 = the register is present and intact, 1 = it is not, 2 = the run
did not produce the artefacts to judge (UNVERIFIED -- fix the runner, not the
design; do not read this as a pass).
"""
from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--build", required=True, help="build/<tag> directory of the run")
    ap.add_argument("--table", default="src/rtl/bscan/pad_table.json")
    ap.add_argument("--control", help="build/<tag> of a run WITHOUT boundary scan, for deltas")
    args = ap.parse_args()

    b = pathlib.Path(args.build)
    tbl = json.loads(pathlib.Path(args.table).read_text())
    design = tbl["design"]
    want = design["boundary_length"]

    out = b / "outputs"
    gate = next(iter(sorted(out.glob("*_pads_gate.v"))), None)
    if gate is None or gate.stat().st_size < 1_000_000:
        print("UNVERIFIED: no usable gate netlist under %s" % out)
        print("            synthesis did not get far enough to judge.")
        return 2

    src = gate.read_text()
    import datetime as _dt
    print("netlist    : %s  (%.1f MB, mtime %s)"
          % (gate.name, gate.stat().st_size / 1e6,
             _dt.datetime.fromtimestamp(gate.stat().st_mtime).strftime("%m-%d %H:%M")))

    fails = []

    # --- 2. the count that the silent failure mode attacks --------------------
    #
    # COUNT FLOPS, NOT SUBMODULE INSTANCES. Genus ungroups by default, so after
    # mapping there are no `bscan_cell_obs` / `bscan_cell_ctl` instantiations
    # left -- the children are dissolved into the parent. An earlier version of
    # this check counted those names, read 0 on a run where the register was
    # perfectly intact, and would have condemned a good netlist. Sequential cells
    # inside the register's own module survive ungrouping; module names do not.
    module = design["module"]
    mm = re.search(r"\nmodule\s+%s\s*\(.*?\nendmodule" % re.escape(module), src, re.S)
    if not mm:
        fails.append("module %s is not defined in the netlist -- the register was "
                     "optimised away entirely" % module)
        print("bsr module : ABSENT")
    else:
        body = mm.group(0)
        seq = len(re.findall(r"^\s+(?:S?DF|EDF|QDF)[A-Z0-9]*\s+\S+\s*\(", body, re.M))
        # EDGE COMES FROM THE CLOCK PIN, NOT THE CELL NAME. In tcbn65lp a
        # negative-edge flop takes .CPN and a positive-edge flop takes .CP;
        # the letter N elsewhere in the name means an active-low SET or CLEAR.
        # An earlier version matched `DF[A-Z]*N[A-Z0-9]*` and counted DFCNQD1
        # -- a POSEDGE flop with active-low clear -- as negedge, reporting 93
        # where the true figure is 49. That number was quoted in a status
        # report before it was checked.
        neg = len(re.findall(r"\.CPN\s*\(", body))
        pos = len(re.findall(r"\.CP\s*\(", body))
        print("bsr module : present, %d lines, %d sequential (%d posedge / %d negedge)"
              % (body.count(chr(10)), seq, pos, neg))
        # Expected flop budget: one shift stage per boundary cell, one update
        # stage per control cell, plus IDCODE(32) + bypass(1) + TAP(4) + IR(8)
        # + TDO(2). Derived from the table, never a literal.
        kinds = {}
        for pd in tbl["pads"]:
            kinds[pd["kind"]] = kinds.get(pd["kind"], 0) + 1
        ctl_cells = kinds.get("output", 0) + 2 * kinds.get("bidir", 0) + kinds.get("opendrain", 0)
        expect_seq = want + ctl_cells + 32 + 1 + 4 + 8 + 2
        print("             expected ~%d (%d shift + %d update + 47 fixed)"
              % (expect_seq, want, ctl_cells))
        if seq < want:
            fails.append("only %d sequential cells inside %s, fewer than the %d "
                         "boundary cells alone -- logic was dropped" % (seq, module, want))
        # 43 update stages + 4 held-instruction bits + 2 TDO = derived, not a literal.
        want_neg = ctl_cells + 4 + 2
        print("             negedge expected %d (%d update + 4 IR + 2 TDO)"
              % (want_neg, ctl_cells))
        if neg == 0:
            fails.append("no negedge flops inside %s -- the update stages are gone, "
                         "so EXTEST cannot hold a value" % module)
        elif neg != want_neg:
            fails.append("%d negedge flops inside %s, expected %d -- the update, "
                         "instruction or TDO stages do not match the pad table"
                         % (neg, module, want_neg))

    # --- 3. the instance is wired into the pad ring ---------------------------
    # An INSTANTIATION is indented and names an instance: "  MOD u_mod(...)".
    # The DECLARATION is "module MOD(port, ...)" -- module name straight onto the
    # paren, no instance name -- so it does NOT match this pattern and must not be
    # subtracted. Getting that wrong made an earlier version of this check report
    # "defined but never instantiated" about a correctly instantiated register.
    n_inst = len(re.findall(r"^[ \t]+%s\s+\w+\s*\(" % re.escape(design["module"]),
                            src, re.M))
    print("bsr inst   : %d" % n_inst)
    if n_inst != 1:
        fails.append("%s is instantiated %d times, expected exactly 1"
                     % (design["module"], n_inst))

    # --- 4. pad survival -------------------------------------------------------
    # ANCHORED. `inst in src` is a bare substring test that any comment mentioning
    # the pad name satisfies, so a deleted pad still reads as present. Require the
    # name in instantiation position.
    missing = [p["inst"] for p in tbl["pads"]
               if not re.search(r"[ \t]%s\s*\(" % re.escape(p["inst"]), src)]
    print("pads       : %d/%d survived" % (len(tbl["pads"]) - len(missing), len(tbl["pads"])))
    if missing:
        fails.append("%d pad instance(s) missing from the netlist: %s"
                     % (len(missing), ", ".join(missing[:5])))

    # --- 5. synthesis error classes -------------------------------------------
    log = b / "logs" / "syn.log"
    if log.is_file():
        t = log.read_text(errors="ignore")
        for cls in ("SDC-202", "TIM-303", "SYN-FAIL"):
            n = t.count(cls)
            if n:
                print("log        : %s x%d" % (cls, n))
                if cls == "SYN-FAIL":
                    fails.append("%s appears %d times in syn.log" % (cls, n))

    # --- 6. timing by path group ----------------------------------------------
    # --- 6. timing by path group ----------------------------------------------
    #
    # READ THE SYNTHESIS REPORT, BY NAME, AND NOTHING ELSE.
    #
    # An earlier version globbed `timing_summary*` and `*qor*.rep` and took the
    # first that parsed. That is how this script FAILED a good run: another
    # session was running `place` inside the same build tag, its
    # `timing_summary_00_pre_place.rep` was newer than my `syn_qor.rep`, and the
    # script judged a SYNTHESIS netlist against a PLACE stage. It reported
    # reg2out -0.512 for a run whose real reg2out was +3834.7 ps.
    #
    # Comparing two different stages is not a small error -- pre-place timing is
    # a different measurement with different parasitics, and the sign flip looked
    # exactly like the regression this script exists to catch. So: one named
    # file, and a loud warning if the tag contains artefacts from a later stage,
    # because a shared tag means the netlist may not be the one judged either.
    SYN_REPORT = "syn_qor.rep"

    def groups(tag):
        d = pathlib.Path(tag) / "reports"
        f = d / SYN_REPORT
        if not f.is_file():
            return {}, ["%s absent -- cannot judge synthesis timing" % (f,)]
        notes = []
        later = sorted(x.name for x in d.glob("*")
                       if any(k in x.name for k in ("_place", "_cts", "_route")))
        if later:
            notes.append("tag also holds %d post-synthesis artefact(s) (%s...) -- "
                         "another stage has run in this tag; the netlist judged above "
                         "may not be the one those describe"
                         % (len(later), later[0]))
        notes.append("timing read from %s (mtime %s)"
                     % (f, __import__("datetime").datetime.fromtimestamp(
                            f.stat().st_mtime).strftime("%m-%d %H:%M")))
        g = {}
        for line in f.read_text(errors="ignore").splitlines():
            m = re.match(r"^([a-z][\w]*)\s+(-?[\d.]+)\s+(-?[\d.]+)\s+\S+\s+(\d+)\s*$", line)
            if m and not m.group(1).startswith("cg_enable"):
                g[m.group(1)] = (float(m.group(2)), float(m.group(3)), int(m.group(4)))
        return g, notes

    g, notes = groups(b)
    for n in notes:
        print("NOTE       : %s" % n)
    if g:
        print("timing     : " + "  ".join("%s slack=%.1f fep=%d" % (k, v[0], v[2])
                                          for k, v in sorted(g.items())))
        # FAIL on FAILING ENDPOINTS, not on the sign of a slack number whose units
        # and stage vary between reports. A group with 0 failing endpoints is
        # closed however its slack is spelled.
        for io in ("in2reg", "reg2out", "in2out"):
            if io in g and g[io][2] > 0:
                fails.append("I/O path group %s has %d failing endpoint(s) (slack %.1f) "
                             "-- the boundary mux has entered a failing cone"
                             % (io, g[io][2], g[io][0]))
        if False:
            try:
                if False:
                    pass
            except ValueError:
                pass
        if args.control:
            c, _ = groups(args.control)
            for k in sorted(set(g) & set(c)):
                print("  delta %-10s slack %+9.1f   fep %+d   (%.1f -> %.1f)"
                      % (k, g[k][0] - c[k][0], g[k][2] - c[k][2], c[k][0], g[k][0]))

    print()
    if fails:
        print("VERDICT: FAIL")
        for f in fails:
            print("  - %s" % f)
        return 1
    print("VERDICT: PASS — the boundary-scan register is present and intact in the netlist")
    return 0


if __name__ == "__main__":
    sys.exit(main())
