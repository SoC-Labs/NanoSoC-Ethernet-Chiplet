#!/usr/bin/env python3
"""dft_icg_census.py -- census the test-enable pin of every integrated clock gate.

A joint work commissioned on behalf of SoC Labs, under Arm Academic Access
license.

Contributors

David Mapstone (d.a.mapstone@soton.ac.uk)

Copyright 2026, SoC Labs (www.soclabs.org)

WHY THIS EXISTS AT ALL

A scan chain cannot shift through a clock gate whose test-enable is 0. During
shift the gate's FUNCTIONAL enable is whatever the shifting logic happens to
produce, so the clock reaches those flops arbitrarily or not at all. The chain
then reads short, or freezes, or -- worst -- shifts correctly on the run where
somebody looks.

Nothing in the synthesis or P&R flow notices this. Genus does not warn: tying a
CGIC test pin low is a legal netlist. Innovus does not warn. `report_scan_chains`
reports the chains it was ASKED to build, not the chains that can shift. The
defect is therefore silent by construction, which is the same shape as the one
scripts/ci/bscan_syn_verdict.py exists for, and it gets the same treatment:
read the ARTEFACT, never the exit status of the tool that made it.

MEASURED on the rc5 virtual-tapeout netlist (rc5vt-20260829), 2026-08-31:

    cg_* instantiations found: 3007
        3007  .test(1'b0)

Every integrated clock gate in the shipping-lineage design is hard-tied off.
That is correct for a design with no scan -- and it is the first thing that must
change for a design with scan. This script is how you tell the difference
without reading 683,000 lines of netlist.

WHAT IT CHECKS

  1. The netlist exists and is large enough to be a real netlist.
  2. Every clock-gate instance is found -- both the Genus wrapper form
     (`cg_RC_CG_MOD_* u (... .test(X) ...)`) and a directly instantiated
     library cell (`CKLNQD1 u (.E(..), .CP(..), .TE(X), .Q(..))`).
  3. What drives each test/TE pin, bucketed into: tied low, tied high, or a net.
  4. Under --require-scan, that ZERO are tied low and that the driving net is
     the expected shift-enable.

A netlist with no clock gates at all is UNVERIFIED (exit 2), not a pass. That
case is real: it is what you get when you point this at the wrong file.

EXIT CODES

  0  measured, and the requested condition holds
  1  measured, and it does not -- the defect is present
  2  could not measure (no netlist, no clock gates, unparseable) -- UNVERIFIED,
     which is NOT a pass. Fix the invocation, not the design.

USAGE

  scripts/ci/dft_icg_census.py --netlist <gate.v>
  scripts/ci/dft_icg_census.py --netlist <gate.v> --require-scan --shift-enable scan_en
  scripts/ci/dft_icg_census.py --selftest      # prove this script can fail
"""
from __future__ import annotations

import argparse
import re
import sys
import tempfile
from pathlib import Path

# A clock gate reaches us in one of two shapes. The wrapper is what Genus emits
# for `cg_RC_CG_MOD_*`; the bare cell is what you get if someone instantiated
# the library cell directly or the wrapper was ungrouped.
WRAPPER_RE = re.compile(r"\b(cg_[A-Za-z0-9_]*)\s+(\\?\S+?)\s*\(([^;]*?)\)\s*;")
BARECELL_RE = re.compile(r"\b(CKLN[A-Z0-9]*|CKLNQ[A-Z0-9]*)\s+(\\?\S+?)\s*\(([^;]*?)\)\s*;")
TEST_PIN_RE = re.compile(r"\.(?:test|TE)\s*\(\s*([^)]*?)\s*\)")

MIN_NETLIST_BYTES = 100_000


def classify(driver: str) -> str:
    """Bucket a test-pin connection. The distinction that matters is
    tied-low (cannot shift) versus a net (might be able to)."""
    d = driver.strip()
    if re.fullmatch(r"1'b0|1'B0|0|1'h0", d):
        return "tied_low"
    if re.fullmatch(r"1'b1|1'B1|1|1'h1", d):
        return "tied_high"
    if d == "":
        return "unconnected"
    return "net"


CG_MODULE_DEF_RE = re.compile(r"\bmodule\s+cg_[A-Za-z0-9_]*\s*\(.*?\bendmodule\b")


def census(text: str):
    """Return (rows, buckets). One row per clock-gate instance.

    A wrapper and the library cell inside its module DEFINITION are the same
    clock gate, so counting both double-counts every gate in the design. The
    wrapper is the instantiated object, so the definitions are stripped before
    bare cells are looked for. (This script's own --selftest caught that bug;
    the case is still in there as `clean, --require-scan`.)
    """
    flat = re.sub(r"\s+", " ", text)
    outside_defs = CG_MODULE_DEF_RE.sub(" ", flat)
    rows = []
    for regex, shape, corpus in (
        (WRAPPER_RE, "wrapper", flat),
        (BARECELL_RE, "bare_cell", outside_defs),
    ):
        for match in regex.finditer(corpus):
            mod, inst, conns = match.group(1), match.group(2), match.group(3)
            # A wrapper's own module DECLARATION also matches the instantiation
            # shape. Declarations carry a bare port list (no dots), so the
            # absence of any `.pin(` is the discriminator.
            if "." not in conns:
                continue
            m = TEST_PIN_RE.search(conns)
            driver = m.group(1) if m else ""
            rows.append(
                {
                    "shape": shape,
                    "module": mod,
                    "inst": inst,
                    "driver": driver,
                    "bucket": classify(driver) if m else "no_test_pin",
                }
            )
    buckets: dict[str, int] = {}
    for r in rows:
        buckets[r["bucket"]] = buckets.get(r["bucket"], 0) + 1
    return rows, buckets


def report(rows, buckets, require_scan: bool, shift_enable: str | None) -> int:
    print("clock-gate instances found: %d" % len(rows))
    if not rows:
        print("UNVERIFIED: no clock gates in this netlist.")
        print("            Either this is not a gate netlist, or the clock-gate")
        print("            naming differs from cg_*/CKLN*. Nothing was measured,")
        print("            which is not a pass.")
        return 2

    for bucket in sorted(buckets, key=lambda b: -buckets[b]):
        print("  %6d  %s" % (buckets[bucket], bucket))

    # Show the distinct drivers, capped -- a healthy scan netlist has one.
    drivers: dict[str, int] = {}
    for r in rows:
        drivers[r["driver"]] = drivers.get(r["driver"], 0) + 1
    print("distinct test-pin drivers: %d" % len(drivers))
    for d, n in sorted(drivers.items(), key=lambda kv: -kv[1])[:8]:
        print("  %6d  .test(%s)" % (n, d if d else "<absent>"))

    tied_low = buckets.get("tied_low", 0)
    no_pin = buckets.get("no_test_pin", 0)

    if not require_scan:
        print()
        print("CENSUS ONLY (no --require-scan): %d of %d clock gates are tied low, "
              "%d have no test connection at all." % (tied_low, len(rows), no_pin))
        if tied_low or no_pin:
            print("  For a design with NO scan chain this is expected and correct.")
            print("  For a design WITH scan it means those flops cannot shift.")
        if no_pin and not tied_low:
            print("  NOTE: an ABSENT .test() is the same defect wearing different")
            print("  clothes. Innovus drops the connection once the constant is")
            print("  propagated, so a post-route netlist shows `no_test_pin` where")
            print("  the post-synthesis one showed .test(1'b0). A checker that")
            print("  greps only for 1'b0 reads the post-route netlist as clean.")
        return 0

    rc = 0
    print()
    if tied_low:
        print("FAIL: %d of %d clock gates have their test-enable tied low."
              % (tied_low, len(rows)))
        print("      Those flops cannot be shifted. The scan chains through them")
        print("      will not work, and no tool will say so.")
        for r in [x for x in rows if x["bucket"] == "tied_low"][:5]:
            print("        %s (%s)" % (r["inst"], r["module"]))
        if tied_low > 5:
            print("        ... and %d more" % (tied_low - 5))
        rc = 1
    if no_pin:
        print("FAIL: %d clock-gate instances have no test pin connected at all."
              % no_pin)
        rc = 1
    if shift_enable:
        wrong = [r for r in rows
                 if r["bucket"] == "net" and shift_enable not in r["driver"]]
        if wrong:
            print("FAIL: %d clock gates are driven by a net that is not '%s'."
                  % (len(wrong), shift_enable))
            for r in wrong[:5]:
                print("        %s <- %s" % (r["inst"], r["driver"]))
            rc = 1
    if rc == 0:
        print("OK: all %d clock gates take their test-enable from a net%s."
              % (len(rows), " matching '%s'" % shift_enable if shift_enable else ""))
    return rc


# --------------------------------------------------------------------------
# Self-test. A gate is only real if it can fail, and this one's whole job is to
# notice a single token. So it has to be shown noticing it, and shown NOT
# raising an alarm on the clean case.
# --------------------------------------------------------------------------
CLEAN = """
module cg_RC_CG_MOD_1(enable, ck_in, ck_out, test);
  input enable, ck_in, test;
  output ck_out;
  CKLNQD1 RC_CGIC_INST(.E (enable), .CP (ck_in), .TE (test), .Q (ck_out));
endmodule
module top(a);
  cg_RC_CG_MOD_1 g0(.enable (e0), .ck_in (c), .ck_out (o0), .test (scan_en));
  cg_RC_CG_MOD_1 g1(.enable (e1), .ck_in (c), .ck_out (o1), .test (scan_en));
  cg_RC_CG_MOD_1 g2(.enable (e2), .ck_in (c), .ck_out (o2), .test (scan_en));
endmodule
"""
DIRTY = CLEAN.replace(".test (scan_en));\n  cg_RC_CG_MOD_1 g2", ".test (1'b0));\n  cg_RC_CG_MOD_1 g2")
WRONGNET = CLEAN.replace("g2(.enable (e2), .ck_in (c), .ck_out (o2), .test (scan_en))",
                         "g2(.enable (e2), .ck_in (c), .ck_out (o2), .test (some_other_net))")


def selftest() -> int:
    cases = [
        ("clean, --require-scan", CLEAN, True, "scan_en", 0),
        ("one gate tied low", DIRTY, True, "scan_en", 1),
        ("one gate on the wrong net", WRONGNET, True, "scan_en", 1),
        ("tied low, census only", DIRTY, False, None, 0),
        ("no clock gates at all", "module top(a); endmodule", False, None, 2),
    ]
    bad = 0
    for name, text, req, se, want in cases:
        rows, buckets = census(text)
        print("--- selftest: %s (expect exit %d) ---" % (name, want))
        got = report(rows, buckets, req, se)
        if got != want:
            print("  ** SELFTEST FAIL: got %d, wanted %d" % (got, want))
            bad += 1
        else:
            print("  ok")
        print()
    if bad:
        print("SELFTEST FAILED: %d of %d cases wrong." % (bad, len(cases)))
        return 1
    print("SELFTEST OK: %d cases, including %d that must go red."
          % (len(cases), sum(1 for c in cases if c[4] == 1)))
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--netlist", help="gate netlist (.v) to census")
    ap.add_argument("--require-scan", action="store_true",
                    help="fail if any clock gate is tied off (use once DFT is on)")
    ap.add_argument("--shift-enable",
                    help="name that must appear in every test-pin driver")
    ap.add_argument("--selftest", action="store_true",
                    help="prove this script can fail, then exit")
    args = ap.parse_args()

    if args.selftest:
        return selftest()
    if not args.netlist:
        print("UNVERIFIED: --netlist is required (or --selftest).")
        return 2

    p = Path(args.netlist)
    if not p.is_file():
        print("UNVERIFIED: no such netlist: %s" % p)
        return 2
    if p.stat().st_size < MIN_NETLIST_BYTES:
        print("UNVERIFIED: %s is %d bytes -- too small to be a gate netlist."
              % (p, p.stat().st_size))
        print("            Synthesis probably did not get far enough to judge.")
        return 2

    print("netlist: %s (%.1f MB)" % (p, p.stat().st_size / 1e6))
    rows, buckets = census(p.read_text(errors="replace"))
    return report(rows, buckets, args.require_scan, args.shift_enable)


if __name__ == "__main__":
    sys.exit(main())
