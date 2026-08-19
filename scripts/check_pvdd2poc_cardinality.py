#!/usr/bin/env python3
"""Report how many `PVDD2POC_G` pad-ring cells this design instantiates.

Copyright 2026, SoC Labs (www.soclabs.org)

Why this exists
----------------
IMEC's foundry padring checker (archive 2, the first archive whose merge
substituted real TSMC pad-ring geometry rather than pad-only content --
`ASIC/imec_results/Archive_..._dummy_merged_dummyWithSealRing_18Aug26_19u28/
padring/Padring_check.rpt`) reports:

    Error-padringcheck, multiple PVDD2POC cells in digital domain

against a design that SUMMARY confirms has exactly one declared power domain
("Number of power domains: 1, Domain 0 is DIGITAL"). This design instantiates
`PVDD2POC_G` FOUR times -- once per side of the pad ring
(`ASIC/tech_wrappers/tsmc65/nanosoc_eth_chiplet_pads.v`, one per T/B/L/R
group), all four wired to the same `VDDIO` net.

Best-evidenced read so far (`CONVERGENCE_PLAN_2026-08-18.md` §8, "New:
PVDD2POC"; `docs/tapeout/53-gate-promotion-plan.md` §2): Calibre likely wants
this domain-boundary/anchor cell ONCE PER RING, not once per side -- but this
is UNCONFIRMED. No TSMC POC-cell datasheet is on this site to say what the
cell's actual anchor semantics are, or whether "one per ring" is even the
right reading. See docs/tapeout/53's item 8 in the retrospective table:
"Ambiguous / needs external input."

What this script does, and does not do
---------------------------------------
This is NOT a fix, and it does not decide the design question. It is a
cheap, license-free, standalone VISIBILITY check: parse the pad ring's own
Verilog source, count the `PVDD2POC_G` instances, and print the count
clearly next to what IMEC's convention plausibly wants -- so that if someone
adds a fifth one, or "fixes" this unilaterally by converting instances to
`PVDD2DGZ_G` without a broker/vendor answer, that change is visible rather
than silent. The script never edits `nanosoc_eth_chiplet_pads.v` and never
recommends converting any instance -- doc 53 §2 is explicit: "**Do not**
silently convert the other three to `PVDD2DGZ_G` without that confirmation."

Source of truth
----------------
`ASIC/tech_wrappers/tsmc65/nanosoc_eth_chiplet_pads.v` is authoritative for
CELL TYPE. Neither `ASIC/genus-innovus/scripts/place_bondpads.tcl` nor
`ASIC/genus-innovus/scripts/nanosoc_eth_chiplet_pads.io` names a cell type at
all for these instances -- both only place/order instance NAMES
(`uPAD_VDDIO_T_0`, ...) that pads.v then binds to a specific pad-library
cell (verified by reading both: neither file contains the string "POC"
anywhere). So this script parses pads.v (the same file
`check_padring_gds.py`/`check_chip_boundary.py` already treat as
authoritative for cell-to-instance binding) and cross-checks, informationally
only, that every `uPAD_VDDIO_<side>_0` name it finds also appears in the .io
floorplan file and in place_bondpads.tcl's per-side lists -- so a rename that
desyncs the three sources is visible too, the same class of check
`check_padring_gds.py`'s docstring already establishes for the rest of the
pad ring.

Usage
-----
    check_pvdd2poc_cardinality.py [--pads-v PATH] [--expect N] [--json OUT]

Exit status
-----------
    0  the measured PVDD2POC_G count matches --expect (default: today's
       known-correct count, 4) and every instance is wired to the same net
       and cross-referenced in the .io/tcl sources. Still UNCONFIRMED by any
       vendor authority -- a 0 exit means "nothing has drifted since this
       baseline was recorded", not "this is correct".
    1  drift: the count moved (either direction), a PVDD2POC_G instance is
       wired to a different net than the others, or a `uPAD_VDDIO_*_0` name
       is missing from the .io file or place_bondpads.tcl.
    2  usage / internal error (pads.v missing, unreadable, or the regex found
       nothing at all -- the parser itself is stale, not a design fact).
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path

EXIT_OK = 0
EXIT_DRIFT = 1
EXIT_USAGE = 2

HERE = Path(__file__).resolve().parent.parent
PADS_V = HERE / "ASIC" / "tech_wrappers" / "tsmc65" / "nanosoc_eth_chiplet_pads.v"
IO_FILE = HERE / "ASIC" / "genus-innovus" / "scripts" / "nanosoc_eth_chiplet_pads.io"
BONDPAD_TCL = HERE / "ASIC" / "genus-innovus" / "scripts" / "place_bondpads.tcl"

# Today's measured, on-disk count -- see the docstring above and
# docs/tapeout/53-gate-promotion-plan.md §2. This is a BASELINE for drift
# detection, not an endorsement: doc 53 explicitly withholds judgment on
# whether 4 or 1 is correct pending broker/vendor input.
DEFAULT_EXPECT = 1

# The cell this design instantiates once per side as the IO-supply anchor,
# and its sibling -- the "plain" IO-supply pad every side otherwise uses.
# Cell-to-pin mapping per nanosoc_eth_chiplet_pads.v:203 (verified there
# against tphn65lpgv2od3_sl.v): both bind their sole port to `.VDDPST`.
TARGET_CELL = "PVDD2POC_G"
SIBLING_CELL = "PVDD2DGZ_G"

INST_RE = re.compile(
    r"^\s*(PVDD2POC_G|PVDD2DGZ_G)\s+(\S+)\s*\(\s*\.VDDPST\s*\(\s*(\S+?)\s*\)\s*\)\s*;",
    re.M)


class SourceError(Exception):
    """The pad ring's own sources are missing, unreadable, or the parser
    found nothing -- a stale parser, not a design fact."""


def strip_comments(src: str) -> str:
    """Remove /* */ and // comments before regex-parsing RTL."""
    src = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
    return re.sub(r"//[^\n]*", "", src)


def parse_vddio_instances(path: Path) -> list[tuple[str, str, str]]:
    """Return [(cell, instance, net), ...] for every PVDD2POC_G/PVDD2DGZ_G
    instantiation in the pad ring source, in file order."""
    if not path.is_file():
        raise SourceError(f"pad ring source not found at {path}")
    src = strip_comments(path.read_text())
    out = [(m.group(1), m.group(2), m.group(3)) for m in INST_RE.finditer(src)]
    if not out:
        raise SourceError(
            f"parsed zero {TARGET_CELL}/{SIBLING_CELL} instances from {path} -- "
            f"the regex is stale or the file was restructured")
    return out


def side_of(inst_name: str) -> str:
    """uPAD_VDDIO_T_0 -> 'T'. Falls back to the raw name if the convention
    ever changes, so an unparsed side shows up as itself rather than as a
    silent 'unknown'."""
    m = re.match(r"uPAD_VDDIO_([TBLR])_\d+$", inst_name)
    return m.group(1) if m else inst_name


def cross_check_sources(target_insts: list[str]) -> list[str]:
    """Informational cross-check: does every PVDD2POC_G instance NAME also
    appear in the .io floorplan file and in place_bondpads.tcl? Those two
    files carry no cell type, so they cannot confirm cell IDENTITY -- only
    that the anchor INSTANCE the .v file names is one the floorplan and the
    bond-pad placer both still know about. A name missing from either is the
    signature of a rename that desynced the sources, the same failure class
    check_padring_gds.py's docstring documents for the rest of the ring.
    Returns a list of problem strings; empty means clean.
    """
    problems: list[str] = []
    io_text = IO_FILE.read_text() if IO_FILE.is_file() else None
    tcl_text = BONDPAD_TCL.read_text() if BONDPAD_TCL.is_file() else None
    if io_text is None:
        problems.append(f"{IO_FILE} not found -- cannot cross-check instance names")
    if tcl_text is None:
        problems.append(f"{BONDPAD_TCL} not found -- cannot cross-check instance names")
    for name in target_insts:
        if io_text is not None and f'name="{name}"' not in io_text:
            problems.append(f"{name}: not found in {IO_FILE.name} "
                             f"(floorplan and pads.v have desynced)")
        if tcl_text is not None and name not in tcl_text:
            problems.append(f"{name}: not found in {BONDPAD_TCL.name} "
                             f"(bond-pad placement and pads.v have desynced)")
    return problems


def main() -> int:
    """Count the PVDD2POC cells in the pad ring and compare against --expect."""
    ap = argparse.ArgumentParser(description=__doc__,
                                  formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--pads-v", type=Path, default=PADS_V,
                     help=f"pad-ring Verilog source (default: {PADS_V})")
    ap.add_argument("--expect", type=int,
                     default=int(os.environ.get("PVDD2POC_EXPECT_COUNT", DEFAULT_EXPECT)),
                     help=f"expected/baseline instance count (default: {DEFAULT_EXPECT}, "
                          f"env PVDD2POC_EXPECT_COUNT)")
    ap.add_argument("--json", type=Path, help="also write a JSON report here")
    a = ap.parse_args()

    try:
        insts = parse_vddio_instances(a.pads_v)
    except SourceError as e:
        print(f"USAGE ERROR: {e}")
        return EXIT_USAGE

    target = [(inst, net) for cell, inst, net in insts if cell == TARGET_CELL]
    sibling = [(inst, net) for cell, inst, net in insts if cell == SIBLING_CELL]
    count = len(target)
    nets = sorted({net for _inst, net in target})
    by_side = {side_of(inst): (inst, net) for inst, net in target}

    print(f"source          : {a.pads_v}")
    print(f"{TARGET_CELL:<16}: {count} instance(s) found")
    for side in ("T", "B", "L", "R"):
        if side in by_side:
            inst, net = by_side[side]
            print(f"  side {side}          {inst:<20} -> .VDDPST({net})")
        else:
            print(f"  side {side}          (none)")
    print(f"{SIBLING_CELL:<16}: {len(sibling)} instance(s) found (context only, not gated)")
    print()

    problems: list[str] = []

    if count != a.expect:
        problems.append(
            f"DRIFT: {count} {TARGET_CELL} instance(s) found, baseline is {a.expect}. "
            f"Something changed the pad ring's power-domain-anchor cell count since "
            f"this baseline was recorded -- update docs/tapeout/53-gate-promotion-plan.md "
            f"AND re-confirm with the broker/vendor before accepting a new baseline.")
    if len(nets) > 1:
        problems.append(
            f"{TARGET_CELL} instances are wired to DIFFERENT nets: {nets} "
            f"(expected exactly one net -- today, VDDIO)")
    if count == 0:
        problems.append(f"0 {TARGET_CELL} instances -- either they were removed "
                         f"outright (a real design change, not this script's business "
                         f"to bless) or the parser is stale")

    xcheck_problems = cross_check_sources([inst for inst, _net in target])
    problems.extend(xcheck_problems)

    verdict = "PASS" if not problems else "DRIFT-DETECTED"
    ok = not problems

    print("--- IMEC finding this check tracks -------------------------------")
    print("Archive 2 Padring_check.rpt: \"Error-padringcheck, multiple PVDD2POC")
    print("cells in digital domain\" against a design with exactly 1 power domain")
    print("(same report's SUMMARY: \"Number of power domains: 1, Domain 0 is")
    print("DIGITAL\"). Best-evidenced (UNCONFIRMED) read: Calibre likely expects")
    print("this anchor cell ONCE PER RING, not once per side. No TSMC POC-cell")
    print("datasheet is on this site to confirm or refute that reading.")
    print(f"MEASURED HERE: {count} instances found, 1 expected per that")
    print("(unconfirmed) IMEC convention -- UNCONFIRMED, see")
    print("docs/tapeout/53-gate-promotion-plan.md §2 and")
    print("CONVERGENCE_PLAN_2026-08-18.md §8 \"New: PVDD2POC\".")
    print("This script does NOT decide 1 vs 4 and does NOT convert any instance")
    print(f"to {SIBLING_CELL} -- that needs broker/vendor confirmation first.")
    print()

    if problems:
        print(f"{verdict}:")
        for p in problems:
            print(f"  * {p}")
    else:
        print(f"{verdict}: {count} {TARGET_CELL} instance(s), matches the recorded "
              f"baseline ({a.expect}), all wired to {nets[0] if nets else '?'}, "
              f"names cross-check clean against the .io/tcl sources. Still "
              f"UNCONFIRMED against any vendor authority -- visibility only.")

    if a.json:
        report = {
            "source": str(a.pads_v),
            "target_cell": TARGET_CELL,
            "sibling_cell": SIBLING_CELL,
            "count": count,
            "expect": a.expect,
            "instances": [{"name": inst, "net": net} for inst, net in target],
            "nets": nets,
            "sibling_count": len(sibling),
            "problems": problems,
            "verdict": verdict,
            "confirmed": False,
            "reference": "docs/tapeout/53-gate-promotion-plan.md#2, "
                         "CONVERGENCE_PLAN_2026-08-18.md#8",
        }
        a.json.parent.mkdir(parents=True, exist_ok=True)
        a.json.write_text(json.dumps(report, indent=2) + "\n")
        print(f"\nJSON report: {a.json}")

    return EXIT_OK if ok else EXIT_DRIFT


if __name__ == "__main__":
    sys.exit(main())
