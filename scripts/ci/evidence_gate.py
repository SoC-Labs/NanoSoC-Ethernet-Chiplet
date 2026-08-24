#!/usr/bin/env python3
"""evidence_gate.py - the CI verdict on an evidence report.

    python3 scripts/ci/evidence_gate.py build/evidence/<tag>/evidence_report.json
    python3 scripts/ci/evidence_gate.py --selftest

Exit 0 only when the report says SIGNED OFF and says it about a report this
program could actually read. Everything else is non-zero.

WHY A SEPARATE PROGRAM. `ci/signoff.yaml` collects artefacts with globs over
`build/**`, and in the LVS case the glob was measured EMPTY -- with a comment
three lines above saying that was deliberate, so an empty directory would
"collect nothing instead of failing the stage". That choice is defensible for a
preflight and it generalises into the failure this whole work item is about: an
absent artefact and a clean artefact rendered identically. This program is what
lets the signoff manifest gate on THE EVIDENCE BUNDLE instead of on a glob, so
a missing artefact is caught by the report generator -- which refuses to emit a
report citing a file it cannot find -- rather than by a glob that silently
matches nothing.

THE FOUR WAYS IT GOES RED, and each is a real shape:

  ABSENT     no report at that path. The build ran and evidenced nothing, or
             the path is wrong. Never a pass.
  UNREADABLE the file is there and is not a report -- truncated, half-written,
             or another schema. A parser that shrugs at this reports 0 gates
             and 0 failures, which reads exactly like success.
  NOT-CLEAN  the report is real and says FAIL or NOT-MEASURED. This is the
             ordinary red, and it is the one the current candidate gives.
  VACUOUS    the report is real, well-formed, says SIGNED OFF -- and contains
             no gates. Zero failures of zero checks. This project has shipped
             at least six zeros that measured nothing; a gate on a report must
             not become the seventh.

Copyright (C) 2026, SoC Labs (www.soclabs.org)
"""

import argparse
import json
import os
import sys

SCHEMA_PREFIX = "soclabs.evidence-report/"
MIN_GATES = 3   # a bundle with fewer than this is not a signoff, it is a note


def grade(path):
    """-> (rc, [lines]). rc 0 only for a readable, non-vacuous, signed-off report."""
    out = []
    if not os.path.isfile(path):
        return 2, ["ABSENT: no evidence report at %s" % path,
                   "  The build produced no evidence, or this is the wrong path.",
                   "  An absent report is not a clean report."]
    try:
        with open(path) as fh:
            d = json.load(fh)
    except (ValueError, OSError) as e:
        return 2, ["UNREADABLE: %s is not a parseable evidence report (%s)" % (path, e),
                   "  A parser that shrugs at this reports 0 gates and 0",
                   "  failures, which reads exactly like success."]
    if not isinstance(d, dict) or not str(d.get("schema", "")).startswith(SCHEMA_PREFIX):
        return 2, ["UNREADABLE: %s carries schema %r, not %s*"
                   % (path, d.get("schema"), SCHEMA_PREFIX),
                   "  Refusing to grade a document whose shape is not the one",
                   "  these rules are written against."]

    gates = d.get("gates") or []
    v = d.get("verdict") or {}
    counts = v.get("counts") or {}
    out.append("report   %s" % path)
    out.append("stream   %s" % (d.get("identity", {}) or {}).get("stream_md5", "?"))
    out.append("verdict  %s" % v.get("line", "(none)"))

    if len(gates) < MIN_GATES:
        out.append("VACUOUS: %d gate row(s), below the floor of %d. A report that"
                   % (len(gates), MIN_GATES))
        out.append("  graded almost nothing cannot certify anything, however green.")
        return 3, out

    # Every row must carry the fields that make it checkable. A row with a
    # verdict and no evidence and no scope is a claim, not a measurement.
    thin = [g["id"] for g in gates
            if g.get("verdict") == "PASS" and not g.get("measured_over")]
    if thin:
        out.append("VACUOUS: %d PASS row(s) do not say what they measured over: %s"
                   % (len(thin), ", ".join(thin)))
        return 3, out

    bad = counts.get("FAIL", 0), counts.get("NOT-MEASURED", 0)
    if not v.get("signed_off"):
        out.append("NOT CLEAN: %d FAIL, %d NOT-MEASURED." % bad)
        for g in gates:
            if g.get("verdict") in ("FAIL", "NOT-MEASURED"):
                out.append("  %-13s %-32s %s"
                           % (g["verdict"], g["id"],
                              (g.get("why") or g.get("got") or "")[:90]))
        return 1, out
    out.append("SIGNED OFF: %d gate row(s), every one measured." % len(gates))
    return 0, out


def selftest():
    """Both directions, over checked-in fixtures, plus the two shapes a naive
    grader gets wrong: an absent file and a well-formed empty one."""
    here = os.path.dirname(os.path.abspath(__file__))
    root = os.path.dirname(os.path.dirname(here))
    fx = os.path.join(root, "ci", "fixtures", "evidence-report")
    cases = [
        ("pass",              0, "a real report with every row measured"),
        ("fail-a-gate",       1, "one FAIL row -- the ordinary red"),
        ("fail-not-measured", 1, "no FAIL, one NOT-MEASURED: still not signed off"),
        ("vacuous-no-gates",  3, "SIGNED OFF over zero gates -- green and empty"),
        ("vacuous-thin-pass", 3, "a PASS row that does not say what it measured"),
        ("unreadable",        2, "well-formed JSON, wrong schema"),
        ("absent",            2, "no report at all"),
    ]
    bad = 0
    print("selftest, fixtures under %s" % fx)
    for name, want, why in cases:
        p = os.path.join(fx, name, "evidence_report.json")
        rc, _ = grade(p)
        ok = rc == want
        if not ok:
            bad += 1
        print("  %-20s want rc=%d  got rc=%d  %-4s (%s)"
              % (name, want, rc, "ok" if ok else "MISMATCH", why))
    print("\nselftest: %s" % ("OK" if not bad else "FAIL — %d case(s) wrong" % bad))
    return 0 if not bad else 1


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("report", nargs="?")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    if a.selftest:
        return selftest()
    if not a.report:
        ap.error("give a report path, or --selftest")
    rc, lines = grade(a.report)
    for l in lines:
        print(l)
    return rc


if __name__ == "__main__":
    sys.exit(main())
