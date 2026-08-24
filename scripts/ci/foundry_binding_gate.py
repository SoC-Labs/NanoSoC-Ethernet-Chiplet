#!/usr/bin/env python3
"""foundry_binding_gate - is every foundry review attached to a stream we hold?

    foundry_binding_gate.py --project ethchip [--block B] [--base URL] [--strict]

A foundry review is slow and expensive. One that cannot be attributed to a
specific set of bytes is not assurance - it is a document that LOOKS like
assurance, which is worse, because the archive's name always names a build.

This gate reads the ingest summaries already in the store and reports:

    BOUND    the review's own md5 matches a stream we hold
    UNBOUND  it does not, and the review describes something we cannot produce

It never re-derives the binding. `asic-flow-ingest-foundry` did that at ingest
time, against the Final Report's `md5sum(.gds*)` field, and wrote the result to
summary.json. This gate's job is to make an orphan VISIBLE, not to re-litigate
it - a check that recomputes what another tool decided will eventually disagree
with it, and then nobody knows which is right.

WHY IT DEFAULTS TO REPORT, NOT BLOCK

An unbound review is a bookkeeping failure, not a design failure: the design may
be perfectly good. Blocking on it would stall a tapeout for a filing error. But
`--strict` turns it blocking, which is what a submission gate should use - going
to a foundry with no review bound to the stream you are actually shipping is a
different and much worse proposition.

VACUITY

Zero returns found is NOT a pass. It means nothing has been ingested, which is
indistinguishable from "no reviews exist" and must never read as "all reviews
bind". The gate returns UNVERIFIED in that case and says which path it searched.
"""

import argparse
import json
import subprocess
import sys

DEFAULT_BASE = "http://mapstone-dev.ecs.soton.ac.uk:8082/artifactory"
RECORD_REPO = "asic-record"


def get(url):
    p = subprocess.run(["curl", "-sS", "-n", "--max-time", "120", "-w", "\n%{http_code}", url],
                       capture_output=True, text=True)
    if p.returncode != 0:
        return None, "curl exited %d" % p.returncode
    out = p.stdout.rsplit("\n", 1)
    code = out[1].strip() if len(out) > 1 else "000"
    return (out[0], None) if code == "200" else (None, "HTTP %s" % code)


def children(base, path):
    body, err = get("%s/api/storage/%s/%s" % (base, RECORD_REPO, path))
    if err:
        return []
    try:
        return [c["uri"].lstrip("/") for c in json.loads(body).get("children", [])]
    except (ValueError, KeyError):
        return []


def main():
    ap = argparse.ArgumentParser(description="report foundry reviews that bind to nothing")
    ap.add_argument("--project", required=True)
    ap.add_argument("--block", default="nanosoc_eth_chiplet_pads")
    ap.add_argument("--base", default=DEFAULT_BASE)
    ap.add_argument("--strict", action="store_true",
                    help="an unbound review fails the gate (use for a submission gate)")
    args = ap.parse_args()

    root = "%s/%s" % (args.project, args.block)
    found = []
    for run in children(args.base, root):
        for arch in children(args.base, "%s/%s/foundry" % (root, run)):
            body, err = get("%s/%s/%s/%s/foundry/%s/summary.json"
                            % (args.base, RECORD_REPO, root, run, arch))
            if err:
                found.append((run, arch, None, "summary.json unreadable: %s" % err))
                continue
            try:
                s = json.loads(body)
            except ValueError as exc:
                found.append((run, arch, None, "summary.json unparseable: %s" % exc))
                continue
            found.append((run, arch, bool(s.get("bound")), s))

    if not found:
        print("foundry-binding: UNVERIFIED - no ingest summaries under %s/%s" % (RECORD_REPO, root))
        print("foundry-binding:   Nothing has been ingested. That is NOT the same as")
        print("foundry-binding:   'every review binds', and must not be read as a pass.")
        return 3

    bound = [f for f in found if f[2] is True]
    unbound = [f for f in found if f[2] is False]
    broken = [f for f in found if f[2] is None]

    for run, arch, ok, s in found:
        if ok is None:
            print("  ?  %-14s %s   %s" % (run, arch[:52], s))
            continue
        claim = (s.get("foundry_claim") or {})
        print("  %s %-14s %s" % ("OK" if ok else "!!", run, arch[:52]))
        print("       claims %s  md5 %s" % (claim.get("gds_name"), claim.get("md5")))
        if not ok:
            print("       BINDS TO NOTHING - these verdicts describe a stream not in the store")
        if s.get("name_warning"):
            print("       WARNING %s" % s["name_warning"])

    print("foundry-binding: %d review(s): %d bound, %d UNBOUND, %d unreadable"
          % (len(found), len(bound), len(unbound), len(broken)))

    if broken:
        print("foundry-binding: FAIL - %d summary file(s) could not be read" % len(broken))
        return 2
    if unbound:
        verdict = "FAIL" if args.strict else "REPORT"
        print("foundry-binding: %s - %d review(s) attributable to no stream we hold."
              % (verdict, len(unbound)))
        print("foundry-binding:   A review that names a build but binds to nothing is not")
        print("foundry-binding:   evidence about that build.")
        return 2 if args.strict else 0
    print("foundry-binding: PASS - every review binds to a stream in the store")
    return 0


if __name__ == "__main__":
    sys.exit(main())
