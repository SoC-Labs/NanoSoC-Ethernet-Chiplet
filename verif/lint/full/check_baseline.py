#!/usr/bin/env python3
"""Baseline ratchet for the full-design lint.

Compares authored findings per (zone, code) against a recorded baseline, and --
when a change-unit manifest is supplied -- asserts the delta is the one the CU
declared.

Why per (zone, code) and never on totals: a total masks a swap. A tidechart fix
that removes 78 findings while a soc regression adds 3 nets out to -75 and looks
like progress.

A RATCHET IS ONE-SIDED, SO IT BANKS A BROKEN MEASUREMENT AS PROGRESS
  This gate only ever asks "did any (zone, code) GROW?". Every other outcome is
  an improvement, and an improvement is a pass. That makes the collapse of the
  measurement itself indistinguishable from the design getting better, which was
  measured on 2026-08-17 against the real 3024-finding report:

    * every authored finding re-tiered to third-party  ->  "improved
      soc-generated CMPCONST 2 -> 0 / no authored regression", exit 0
    * a findings file with an empty findings list      ->  the same, exit 0

  The first is not a contrived mutation. It is precisely the tiering flip
  zones.py's own module docstring is written about: a source tree reached
  through a symlink arrives spelled as something that carries a different prefix.
  That docstring worries about the direction that reddens the gate (vendor files
  tiering AUTHORED). The direction that greens it had no guard at all.

  So: a run that produces no authored finding while the baseline records some is
  a NULL RESULT and exits 2 (untrustworthy), not 0. `--record` refuses to write
  an empty baseline for the same reason — an empty ratchet can never fail again.

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


def load_findings(path):
    """The finding list, or a (rc, message) pair describing why there isn't one.

    Broken out so a malformed or missing artefact reports itself as an
    UNTRUSTWORTHY MEASUREMENT (exit 2) instead of raising, which the caller
    scored as exit 1 — "the design regressed" — and sent someone to look for a
    lint finding that was never reported.
    """
    try:
        d = json.load(open(path))
    except (OSError, ValueError) as e:                       # noqa: PERF203
        return None, f"cannot read the findings artefact {path}: {e}"
    fs = d.get("findings") if isinstance(d, dict) else d
    if not isinstance(fs, list):
        return None, f"{path} carries no 'findings' list — this is not a report"
    return fs, None


def counts(path):
    """Authored DESIGN findings, keyed (zone, code)."""
    fs, err = load_findings(path)
    if err:
        raise ValueError(err)
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
    ap.add_argument("--allow-empty", action="store_true",
                    help="permit --record to write a baseline with no authored "
                         "findings. An empty ratchet can never fail again, so "
                         "this must be asked for explicitly.")
    a = ap.parse_args()

    fs, err = load_findings(a.findings)
    if err:
        print(f"   FLOW ERROR: {err}")
        return 2
    try:
        cur = counts(a.findings)
    except ValueError as e:                                  # noqa: BLE001
        print(f"   FLOW ERROR: {e}")
        return 2

    if a.record:
        if not cur and not a.allow_empty:
            print(f"   REFUSING to record an EMPTY baseline from {a.findings}\n"
                  f"   ({len(fs)} finding(s) parsed, 0 of them authored DESIGN "
                  f"findings).\n"
                  f"   A baseline with no entries cannot be regressed against, so "
                  f"recording one\n   disarms this gate permanently. If the run "
                  f"really is clean, pass --allow-empty.")
            return 2
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

    # NULL-RESULT GUARD, before any comparison. See the module docstring: the
    # ratchet's only question is "did anything grow?", so the disappearance of
    # every authored finding scores as an improvement and passes. Two ways that
    # happens without a single line of RTL changing — the tool died early, or
    # tiering re-labelled our own files as vendor IP — and both then read as the
    # design having got better.
    if base and not cur:
        print(f"   NULL RESULT — {len(fs)} finding(s) parsed from {a.findings}, "
              f"but NONE of them\n   are authored DESIGN findings, while the "
              f"baseline records {sum(base.values())} across\n   "
              f"{len(base)} (zone, code) pair(s). A full-design lint that says "
              f"nothing at all about\n   our own RTL has not measured it clean; "
              f"it has failed to measure it.\n"
              f"   Look first at tiering (verif/lint/full/zones.py) and at "
              f"whether the tool\n   actually completed. This is NOT a pass and "
              f"NOT a regression.")
        return 2

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

    # State the SCALE of what was compared. Without it the reader cannot tell a
    # two-line table drawn from 1090 authored findings from the same two lines
    # drawn from none, and those are the two cases this gate must not conflate.
    print(f"   scale     : {sum(cur.values())} authored DESIGN finding(s) over "
          f"{len(cur)} (zone, code) pair(s); baseline {sum(base.values())} over "
          f"{len(base)}")
    zeroed = [(z, c) for (z, c), b, n in improvements if n == 0]
    if zeroed:
        print(f"   NOTE      : {len(zeroed)} pair(s) went to ZERO "
              f"({', '.join(f'{z}/{c}' for z, c in sorted(zeroed))}).\n"
              f"               Either a real fix — then re-record the baseline so "
              f"the ratchet holds\n               the new floor — or the "
              f"measurement stopped reaching that code. The\n               "
              f"ratchet cannot tell those apart; do not bank it unread.")

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
