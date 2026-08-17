#!/usr/bin/env python3
"""Assert ci/MUTATION_COVERAGE against ci/signoff.yaml.

A joint work commissioned on behalf of SoC Labs, under Arm Academic Access
license.  Copyright 2026, SoC Labs (www.soclabs.org)

WHY THIS EXISTS
    ci/MUTATION_COVERAGE declares which signoff gates are proven able to fail.
    A declared number that nothing executes is exactly the defect the ledger
    itself warns about: `signoff.py prove` prints "N problem(s): 0" and exits 0
    whether it ran 48 cases or 4, because deleting a must_fail fixture also
    deletes the case that would have noticed. The count has to live somewhere
    that is not derived from the run, and then be asserted.

    Red in BOTH directions, per the same doctrine as
    ASIC/asic-toolkit/test/MUTATION_COVERAGE:

      fewer than declared   a proof was dropped; something is now unproven and
                            the suite would not otherwise have said so.
      more than declared    a proof was added and nobody reviewed it. Not a
                            defect, but not a silent pass either.

    It also catches the shape `prove` cannot report on at all: a stage with NO
    `check:`, whose whole verdict is a process exit status. Those stages never
    appear in prove's case list, so prove's green line says nothing about them.

USAGE
    scripts/ci/check_mutation_coverage.py          # exits 1 on any mismatch
"""
import re
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.exit("check_mutation_coverage: PyYAML required (pip install pyyaml)")

ROOT = Path(__file__).resolve().parents[2]
LEDGER = ROOT / "ci" / "MUTATION_COVERAGE"
MANIFEST = ROOT / "ci" / "signoff.yaml"


def as_list(v):
    if v is None:
        return []
    return v if isinstance(v, list) else [v]


def read_ledger():
    """Parse `key value` rows, ignoring comments and blank lines."""
    rows = {}
    for line in LEDGER.read_text().splitlines():
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        parts = line.split()
        rows[parts[0]] = parts[1:]
    return rows


def main():
    if not LEDGER.exists():
        sys.exit(f"check_mutation_coverage: no ledger at {LEDGER}")
    ledger = read_ledger()
    manifest = yaml.safe_load(MANIFEST.read_text())
    stages = manifest.get("stages", [])

    pending = set(ledger.pop("pending-undeclared", []))
    scalars = {"blocking-unproven", "report-unproven",
               "must-fail-cases-total", "stages-with-check"}
    declared = {k: int(v[0]) for k, v in ledger.items() if k in scalars}
    per_stage = {k: int(v[0]) for k, v in ledger.items() if k not in scalars}

    problems, notes = [], []
    proven, blocking_unproven, report_unproven = {}, [], []

    for s in stages:
        sid = s["id"]
        gate = s.get("gate", "block")
        if not s.get("check"):
            (blocking_unproven if gate == "block" else report_unproven).append(sid)
            continue
        proof = s.get("check_proof") or {}
        must_pass = as_list(proof.get("must_pass"))
        must_fail = as_list(proof.get("must_fail"))
        missing = [f for f in must_pass + must_fail if not (ROOT / f).is_dir()]
        if missing or not must_pass or not must_fail:
            if sid in pending:
                notes.append(f"{sid}: UNDECLARED (pending, owned by another session) — "
                             f"{len(missing)} fixture(s) absent; not proven, not gated here")
            else:
                problems.append(
                    f"{sid}: has a check: but its proof is incomplete — "
                    + (f"{len(missing)} fixture(s) do not exist: {', '.join(missing[:3])}"
                       if missing else "needs BOTH a must_pass and a must_fail"))
            continue
        proven[sid] = len(must_fail)

    # --- per-stage must_fail counts
    for sid, n in sorted(proven.items()):
        if sid in pending:
            notes.append(f"{sid}: UNDECLARED (pending, owned by another session) — "
                         f"{n} must_fail case(s); add a row when that work lands")
            continue
        if sid not in per_stage:
            problems.append(
                f"{sid}: proven with {n} must_fail case(s) but has NO row in "
                f"ci/MUTATION_COVERAGE. A gate nobody reviewed is how a decorative "
                f"gate gets in — add the row.")
        elif per_stage[sid] != n:
            direction = ("a proof was DROPPED" if n < per_stage[sid]
                         else "a proof was ADDED and this ledger was not updated")
            problems.append(f"{sid}: ledger says {per_stage[sid]} must_fail case(s), "
                            f"manifest has {n} — {direction}")
    for sid in per_stage:
        if sid not in proven:
            problems.append(f"{sid}: ci/MUTATION_COVERAGE has a row for it, but the "
                            f"manifest has no such proven stage (renamed or removed?)")

    # --- the aggregate claims
    counted = {
        "blocking-unproven": len(blocking_unproven),
        "report-unproven": len(report_unproven),
        "must-fail-cases-total": sum(n for s, n in proven.items() if s not in pending),
        "stages-with-check": len([s for s in proven if s not in pending]),
    }
    for key, actual in counted.items():
        if key not in declared:
            problems.append(f"ci/MUTATION_COVERAGE has no `{key}` row")
        elif declared[key] != actual:
            problems.append(f"{key}: ledger says {declared[key]}, manifest has {actual}")

    # --- report
    print("SIGNOFF GATE COVERAGE — can each gate actually fail?\n")
    print(f"  {'stage':<20}{'gate':<9}{'coverage'}")
    print("  " + "-" * 58)
    by_id = {s["id"]: s for s in stages}
    for s in stages:
        sid, gate = s["id"], s.get("gate", "block")
        if sid in proven:
            tag = f"PROVEN — {proven[sid]} must_fail case(s)"
            if sid in pending:
                tag += "  [undeclared, pending]"
        elif s.get("check"):
            tag = "INCOMPLETE — check: present, fixtures missing"
        else:
            tag = "RC-ONLY — no check:, verdict is an exit status"
        print(f"  {sid:<20}{gate:<9}{tag}")
    print()
    if blocking_unproven:
        print(f"  {len(blocking_unproven)} BLOCKING stage(s) with no proof they can fail: "
              f"{', '.join(blocking_unproven)}")
        print("    These decide signoff and nothing demonstrates a bad result would "
              "make them red.")
    if report_unproven:
        print(f"  {len(report_unproven)} report-only stage(s) unproven: "
              f"{', '.join(report_unproven)}")
    for n in notes:
        print(f"  note: {n}")

    if problems:
        print("\nMUTATION COVERAGE LEDGER IS STALE:")
        for p in problems:
            print(f"  - {p}")
        print("\nci/MUTATION_COVERAGE is a claim about what this pipeline proves. "
              "Update it deliberately; that edit is the review.")
        return 1
    print("\nci/MUTATION_COVERAGE agrees with ci/signoff.yaml.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
