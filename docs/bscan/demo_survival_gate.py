#!/usr/bin/env python3
"""
demo_survival_gate.py -- the survival gate's counting and verdict logic, run
against the two REAL netlists on disk, so that the gate has been watched to fail.

A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.

Contributors

David Mapstone (d.a.mapstone@soton.ac.uk)

Copyright 2026, SoC Labs (www.soclabs.org)

WHAT THIS IS, AND WHAT IT IS NOT

The gate itself (docs/bscan/survival_gate.tcl) runs INSIDE Genus and counts
DATABASE OBJECTS -- `get_db insts -if {.name == <glob>}`. That query cannot be
run here: there is no Genus, and there is no licence to spend on proving a
count.

What CAN be run here is everything downstream of the query: the derivation of
the expectation from the design's own artefact, the comparison, the vacuity
arms, the ungroup-tolerance diagnostic and the verdict. This script reimplements
exactly that logic and substitutes ONE thing -- it counts instances by parsing
the written netlist instead of asking the database. The two counts are the same
population (the gate runs before write_hdl; write_hdl writes what the database
holds), but they are not the same measurement, and the difference is stated in
DELETION_GUARD_DESIGN.md under "HOW THIS GUARD CAN STILL BE FOOLED".

Run:  python3 docs/bscan/demo_survival_gate.py
      (from the repository root; add --verbose to list every missing name)
"""
from __future__ import annotations

import argparse
import fnmatch
import json
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TABLE = os.path.join(REPO, "src/rtl/bscan/pad_table.json")
NETLISTS = {
    "bscan-probe":  "ASIC/eth-chiplet/build/bscan-probe/outputs/nanosoc_eth_chiplet_pads_gate.v",
    "bscan-probe2": "ASIC/eth-chiplet/build/bscan-probe2/outputs/nanosoc_eth_chiplet_pads_gate.v",
}

# ---------------------------------------------------------------------------
# THE INSTANCE SCANNER
#
# write_hdl WRAPS LINES, and it wraps them at a column, so whether an instance's
# cell type and instance name land on the same line depends on HOW LONG THE NAME
# IS -- which is precisely what ungrouping changes. A line-anchored regex is
# therefore a measurement whose sensitivity varies with the defect it is looking
# for. Normalise whitespace across the whole file first, then match.
#
# An INSTANCE is `CELLTYPE instname (`. A module DECLARATION is `module NAME(`
# with the name straight onto the paren and no instance name, so it does not
# match this shape and is not subtracted. Escaped identifiers (`\name[0] `) are
# admitted because the TAP state register is written that way.
# ---------------------------------------------------------------------------
INST = re.compile(r"([A-Za-z][A-Za-z0-9_]*)\s+(\\?[A-Za-z_][A-Za-z0-9_\[\]\.\\$/]*)\s*\(")


def scan_instances(path):
    with open(path, errors="replace") as fh:
        src = fh.read()
    if not src.strip():
        return None, "file is empty"
    if src.rstrip().splitlines()[-1].strip() != "endmodule":
        # A killed write_hdl leaves a file that opens, greps and looks like a
        # netlist. Every absence measured in it is the writer's, not the design's.
        return None, "does not end in `endmodule` -- the writer was interrupted"
    flat = re.sub(r"\s+", " ", src)
    return [(c, n.lstrip("\\")) for c, n in INST.findall(flat)], None


def match_count(names, pattern):
    return [n for n in names if fnmatch.fnmatchcase(n, pattern)]


# ---------------------------------------------------------------------------
# THE CLAIMS -- derived from src/rtl/bscan/pad_table.json, never typed here.
# This is the Python mirror of the manifest in
# docs/bscan/survival_manifest.eth-chiplet.tcl.
# ---------------------------------------------------------------------------
def build_claims(table_path):
    with open(table_path) as fh:
        tbl = json.load(fh)
    design, pads = tbl["design"], tbl["pads"]
    kinds = {}
    for p in pads:
        kinds[p["kind"]] = kinds.get(p["kind"], 0) + 1

    # One SHIFT stage per boundary cell, one UPDATE stage per CONTROL cell.
    # boundary_length is the chain length the design declares; the control
    # population is what the pad kinds imply. 76 + 43 = 119 on this chiplet.
    boundary = design["boundary_length"]
    ctl = kinds.get("output", 0) + 2 * kinds.get("bidir", 0) + kinds.get("opendrain", 0)
    prov = "%s: boundary_length=%d + control cells=%d (out %d + 2*bidir %d + od %d)" % (
        os.path.relpath(table_path, REPO), boundary, ctl,
        kinds.get("output", 0), kinds.get("bidir", 0), kinds.get("opendrain", 0))

    claims = [
        dict(label="boundary-scan shift and update flops",
             pattern="*u_bsc_*_reg", minimum=boundary + ctl, source=prov),
        # Subsumes the pad-ring question for the pads the table names. The
        # count is len(pads), never the literal 48.
        dict(label="pad instances named by the pad table",
             pattern=None, names=[p["inst"] for p in pads],
             minimum=len(pads),
             source="%s: %d entries in `pads`" % (os.path.relpath(table_path, REPO), len(pads))),
    ]
    return tbl, claims


def evaluate(claim, names, verbose=False):
    """Returns (ok, found, detail-lines). Mirrors survive_assert in the Tcl."""
    detail = []
    if claim.get("names"):
        present = set(names)
        missing = [n for n in claim["names"] if n not in present]
        found = len(claim["names"]) - len(missing)
        if missing:
            detail.append("missing: %s%s" % (", ".join(missing[:8]),
                                             " ..." if len(missing) > 8 else ""))
        return found >= claim["minimum"], found, detail

    hits = match_count(names, claim["pattern"])
    found = len(hits)

    # --- THE UNGROUP-TOLERANCE DIAGNOSTIC ---------------------------------
    # Instance names survive ungrouping; they are PREFIXED by the path of the
    # hierarchy that was dissolved. A pattern not written to tolerate that
    # prefix reads 0 on a perfectly intact register. Before reporting a
    # shortfall, re-count with a leading `*` and say if that is the difference.
    if found < claim["minimum"] and not claim["pattern"].startswith("*"):
        alt = len(match_count(names, "*" + claim["pattern"]))
        if alt > found:
            detail.append("PATTERN IS NOT UNGROUP-TOLERANT: %d matched as written, "
                          "%d matched with a leading `*`. Genus ungrouped the "
                          "enclosing hierarchy and prefixed every instance name "
                          "with its path. Fix the pattern, not the design."
                          % (found, alt))
    if verbose and hits:
        detail.append("e.g. %s" % ", ".join(sorted(hits)[:3]))
    return found >= claim["minimum"], found, detail


def run(tag, path, claims, verbose=False):
    print("=" * 78)
    print("RUN %s" % tag)
    print("    %s" % path)
    full = os.path.join(REPO, path)
    if not os.path.isfile(full):
        print("    UNVERIFIED: no netlist. This indicts the RUN, not the design.")
        return 2
    names_pairs, err = scan_instances(full)
    if err:
        print("    UNVERIFIED: %s" % err)
        return 2
    names = [n for _, n in names_pairs]
    print("    %d instances parsed, %.1f MB" % (len(names), os.path.getsize(full) / 1e6))
    print()

    hard = []
    for c in claims:
        # --- VACUITY ARM, before any comparison -------------------------------
        if not isinstance(c["minimum"], int) or c["minimum"] <= 0:
            hard.append("claim '%s' declares a minimum of %r, so 'found >= expected' "
                        "is satisfied by an EMPTY design" % (c["label"], c["minimum"]))
            print("    [VACUOUS] %-42s min=%r" % (c["label"], c["minimum"]))
            continue
        ok, found, detail = evaluate(c, names, verbose)
        print("    [%s] %-42s %d / %d" % ("ok  " if ok else "FAIL", c["label"], found, c["minimum"]))
        print("             derived from %s" % c["source"])
        for d in detail:
            print("             %s" % d)
        if not ok:
            hard.append("%s: %d instance(s) present, at least %d required (%s)"
                        % (c["label"], found, c["minimum"], c["source"]))
    print()
    if hard:
        print("    VERDICT: FAIL -- %d hard failure(s)" % len(hard))
        for h in hard:
            print("      - %s" % h)
        return 1
    print("    VERDICT: PASS")
    return 0



# ---------------------------------------------------------------------------
# MUTATION PROOFS -- can each arm of the gate be made to fire?
#
# The main run above shows the gate passing one netlist and failing another.
# That proves it discriminates on ONE axis. These mutations prove the other
# arms are load-bearing too: a gate whose vacuity check has never been seen to
# fire is a gate whose vacuity check may not exist.
# ---------------------------------------------------------------------------
def selftest(verbose=False):
    tbl, base = build_claims(TABLE)
    good = os.path.join(REPO, NETLISTS["bscan-probe"])
    bad  = os.path.join(REPO, NETLISTS["bscan-probe2"])
    names_good = [n for _, n in scan_instances(good)[0]]
    names_bad  = [n for _, n in scan_instances(bad)[0]]
    results = []

    def probe(desc, claim, names, expect_ok, want_detail=None):
        if not isinstance(claim["minimum"], int) or claim["minimum"] <= 0:
            ok, found, detail = False, 0, ["VACUOUS: minimum=%r" % claim["minimum"]]
        else:
            ok, found, detail = evaluate(claim, names, verbose)
        hit = (ok == expect_ok)
        if want_detail is not None:
            hit = hit and any(want_detail in d for d in detail)
        results.append((hit, desc, found, claim["minimum"], detail))

    # M1 -- the expectation is zero. `0 >= 0` is true and measures nothing.
    probe("M1 vacuous expectation (boundary_length=0) must NOT pass",
          dict(base[0], minimum=0), names_good, expect_ok=False)

    # M2 -- a pattern nobody has ever seen match. Must fail, not shrug.
    probe("M2 pattern that matches nothing must NOT pass",
          dict(base[0], pattern="*u_no_such_thing_*"), names_good, expect_ok=False)

    # M3 -- THE FALSE-FAIL THIS PROJECT ALREADY SHIPS. A pattern anchored at the
    # module boundary reads 119 on the run where Genus kept the hierarchy and 0
    # on the run where it ungrouped -- and 0 looks exactly like deletion.
    probe("M3 non-ungroup-tolerant pattern still passes the INTACT netlist",
          dict(base[0], pattern="u_bsc_*_reg"), names_good, expect_ok=True)
    probe("M3 non-ungroup-tolerant pattern on the UNGROUPED netlist self-diagnoses",
          dict(base[0], pattern="u_bsc_*_reg"), names_bad, expect_ok=False,
          want_detail="NOT UNGROUP-TOLERANT")

    # M4 -- one pad deleted from the table's name list must be caught by name.
    probe("M4 a pad the table names but the netlist lacks must NOT pass",
          dict(base[1], names=base[1]["names"] + ["uPAD_DOES_NOT_EXIST"],
               minimum=len(base[1]["names"]) + 1), names_good, expect_ok=False)

    # M5 -- the healthy control. If this fails, every red above is meaningless.
    probe("M5 CONTROL: the real claim on the real intact netlist passes",
          base[0], names_good, expect_ok=True)

    print("=" * 78)
    print("MUTATION PROOFS")
    for hit, desc, found, minimum, detail in results:
        print("    [%s] %-62s %d/%d" % ("ok  " if hit else "MISS", desc, found, minimum))
        for d in detail:
            print("             %s" % d)
    bad_n = sum(1 for r in results if not r[0])
    print()
    print("    %d/%d mutation proofs behaved as specified" % (len(results) - bad_n, len(results)))
    return 1 if bad_n else 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--verbose", action="store_true")
    ap.add_argument("--selftest", action="store_true",
                    help="run the mutation proofs instead of the two netlists")
    args = ap.parse_args()

    if args.selftest:
        return selftest(args.verbose)

    tbl, claims = build_claims(TABLE)
    print("expectation source : %s" % os.path.relpath(TABLE, REPO))
    print("design             : block=%s module=%s boundary_length=%d pads=%d"
          % (tbl["design"]["block"], tbl["design"]["module"],
             tbl["design"]["boundary_length"], len(tbl["pads"])))
    print("claims             : %d (no count below is written in this file)" % len(claims))
    print()

    rc = {tag: run(tag, path, claims, args.verbose) for tag, path in NETLISTS.items()}

    print("=" * 78)
    print("EXPECTED: bscan-probe PASS (rc 0), bscan-probe2 FAIL (rc 1)")
    print("ACTUAL  : bscan-probe rc=%d, bscan-probe2 rc=%d" % (rc["bscan-probe"], rc["bscan-probe2"]))
    good = rc["bscan-probe"] == 0 and rc["bscan-probe2"] == 1
    print("DEMONSTRATION: %s" % ("the gate discriminates" if good
                                 else "THE GATE DOES NOT DISCRIMINATE"))
    return 0 if good else 1


if __name__ == "__main__":
    sys.exit(main())
