#!/usr/bin/env python3
"""Baseline ratchet for the full-design lint.

Compares authored findings per (zone, code) against a recorded baseline, and --
when a change-unit manifest is supplied -- asserts the delta is the one the CU
declared.

Why per (zone, code) and never on totals: a total masks a swap. A tidechart fix
that removes 78 findings while a soc regression adds 3 nets out to -75 and looks
like progress.

    check_baseline.py --findings f.json --baseline b.json [--cu cu.yaml]
    check_baseline.py --findings f.json --baseline b.json --record

Copyright 2026, SoC Labs (www.soclabs.org)
"""
import os
import sys
import json
import argparse
import collections

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

FLOW = {"UNPACKED", "ASSIGNDLY", "STMTDLY", "INITIALDLY", "REALCVT"}
WAIVED = {"UNUSED", "UNDRIVEN", "DECLFILENAME", "SYNCASYNCNET",
          "VARHIDDEN", "UNSIGNED", "BLKSEQ"}


def counts(path):
    """Authored DESIGN findings, keyed (zone, code)."""
    d = json.load(open(path))
    fs = d["findings"] if isinstance(d, dict) else d
    out = collections.Counter()
    for f in fs:
        if f.get("tier") != "authored":
            continue
        code = f.get("code") or f.get("rule")
        if code in FLOW or code in WAIVED:
            continue
        # Direction-aware pin classification: a waived dangling output is not a
        # design finding, an empty/omitted input is.
        if code in ("PINCONNECTEMPTY", "PINMISSING") and f.get("pin_dir") == "output":
            continue
        out[(f.get("zone", "?"), code)] += 1
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--findings", required=True)
    ap.add_argument("--baseline", required=True)
    ap.add_argument("--cu")
    ap.add_argument("--record", action="store_true")
    ap.add_argument("--tool", default="verilator", choices=["verilator", "hal"],
                    help="which tool's findings file this is; selects the "
                         "matching half of a per-tool lint_delta")
    a = ap.parse_args()

    cur = counts(a.findings)

    if a.record:
        os.makedirs(os.path.dirname(a.baseline), exist_ok=True)
        json.dump({f"{z}|{c}": n for (z, c), n in sorted(cur.items())},
                  open(a.baseline, "w"), indent=1)
        print(f"recorded {sum(cur.values())} authored findings -> {a.baseline}")
        return 0

    if not os.path.exists(a.baseline):
        print(f"no baseline at {a.baseline} — run with --record first")
        return 2
    base = collections.Counter(
        {tuple(k.split("|", 1)): v for k, v in json.load(open(a.baseline)).items()})

    regressions, improvements = [], []
    for key in set(base) | set(cur):
        d = cur.get(key, 0) - base.get(key, 0)
        if d > 0:
            regressions.append((key, base.get(key, 0), cur.get(key, 0)))
        elif d < 0:
            improvements.append((key, base.get(key, 0), cur.get(key, 0)))

    for (z, c), b, n in sorted(improvements):
        print(f"   improved  {z:<14} {c:<18} {b} -> {n}")
    for (z, c), b, n in sorted(regressions):
        print(f"   REGRESSED {z:<14} {c:<18} {b} -> {n}")

    rc = 0
    if regressions:
        print(f"\n   {len(regressions)} (zone, code) pair(s) increased — "
              f"a lint fix must not add findings elsewhere")
        rc = 1

    # If a CU declared a delta, hold it to it. A fix that clears more than it
    # claimed is not automatically good news -- it usually means the edit was
    # broader than the manifest says, which is what G0 exists to catch.
    if a.cu:
        import yaml
        want = (yaml.safe_load(open(a.cu)).get("expect") or {}).get("lint_delta") or {}
        # A manifest may declare deltas per tool:  lint_delta: {verilator: {...},
        # hal: {...}}.  A flat mapping is read as verilator-only, for
        # compatibility. This matters: UELCIT / ULRELE / POOBID are HAL codes and
        # do not appear in the Verilator findings at all, so a flat manifest that
        # names one used to fail G1 by construction, however good the fix --
        # measured on C1 (the highest-return change unit in the plan).
        tool = a.tool
        if any(k in want for k in ("verilator", "hal")):
            want = want.get(tool) or {}
        elif tool != "verilator":
            want = {}
        producible = {f.get("code") or f.get("rule")
                      for f in (json.load(open(a.findings)).get("findings")
                                if isinstance(json.load(open(a.findings)), dict)
                                else json.load(open(a.findings)))}
        unknown = [c for c in want if c not in producible and want[c] != 0]
        if unknown:
            print(f"   MANIFEST ERROR: lint_delta names code(s) {unknown} that the "
                  f"'{tool}' report cannot produce. Move them under the right tool.")
            rc = 1
            want = {c: v for c, v in want.items() if c not in unknown}
        if want:
            got = collections.Counter()
            for (z, c), b, n in improvements + regressions:
                got[c] += cur.get((z, c), 0) - base.get((z, c), 0)
            for code, exp in want.items():
                if got.get(code, 0) != exp:
                    print(f"   DECLARED DELTA MISMATCH {code}: "
                          f"manifest says {exp:+d}, measured {got.get(code, 0):+d}")
                    rc = 1
            if rc == 0:
                print(f"   declared delta matched: {want}")
    if rc == 0 and not regressions:
        print("   no authored regression")
    return rc


if __name__ == "__main__":
    sys.exit(main())
