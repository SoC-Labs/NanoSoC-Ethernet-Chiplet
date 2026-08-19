#!/usr/bin/env python3
"""Grade the SUBMISSION artefact — the logo-merged stream — not the signoff one.

A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
Copyright 2026, SoC Labs (www.soclabs.org)

THE HOLE THIS CLOSES. The `drc` stage grades
build/<tag>/outputs/<block>.gds — the UN-LOGOED signoff artefact. The shuttle
logo is merged in a SEPARATE step producing a DIFFERENT FILE, deliberately, so
that a DRC count can never be quoted against the wrong stream. The consequence
nobody had wired: **no gate has ever graded a logo-merged stream**, and all logo
DRC evidence is gitignored (.gitignore ASIC/*/calibre_runs and build/), so a CI
clone finds nothing. That is how a submission bundle reached a broker carrying a
keep-out violation whose true count was never known.

Merging the logo takes design-owned results from roughly 140 to over 2000 on
this build, and the delta is exactly five checks:
    LOGO.S.1  +1000   (SATURATED at the hierarchical cap)
    LOGO.R.4  +1000   (SATURATED)
    AP.W.1.WB   +12
    AP.S.1.WB    +4
    AP.S.1.FC    +4
Both LOGO checks are capped in EVERY logoed stream built here, so their true
counts are unknown. Beware the `N (M)` form: N is hierarchical and M is flat, so
two runs that both read N=1000 differ only in flat multiplicity -- a change in M
alone is NOT an improvement. Do not quote either number as a measurement until
the deck is re-run with the cap raised.

WHAT THIS SCRIPT ADDS OVER `drc_census.py`, AND ONLY THIS. The census already
fails on any saturated rulecheck and on design-owned over budget, and it stays
the authority on the verdict — no grading logic is duplicated here. Two things it
cannot do on its own:

  1. AN ABSENT RUN MUST NOT READ AS CLEAN. A bundle can be assembled with no
     logo merge at all, and a stage that passes on a missing file waves exactly
     that through. No summary => refuse.

  2. AN UN-LOGOED STREAM MUST NOT PASS TRIVIALLY. Point a logo check at the
     signoff artefact and it finds no LOGO.* results and reads clean — the
     "zero that measured nothing" in its purest form. So this asserts, POSITIVELY,
     that the run graded a logo-merged file.

     The assertion is anchored on the layout the run RECORDS READING
     ('Layout Path(s):' in Calibre's own summary), NOT on LOGO violations being
     present. Asserting "LOGO results exist" would make a correctly FIXED logo
     fail — a gate that punishes the fix. This one keeps working the day the
     keep-out is finally reserved and the count goes to zero.

PROVEN THREE WAYS (`--self-test`), against real Calibre output rather than
fixtures:
    logoed + saturated   -> rc 1, census reasons quoted
    un-logoed signoff    -> rc 1, and the FIRST reason names the wrong-stream
    absent rundir        -> rc 1, naming un-run as distinct from clean

=============================================================================
GATE A — `logo-keepout`: DESIGNED, DELIBERATELY NOT LANDED. DO NOT WIRE IT.
=============================================================================
The obvious companion is a licence-free check that the shipping stream carries
no 158/0 (LOGO) geometry, which would catch a saturated keep-out with no Calibre
seat at all. It is NOT included, and the reason is a genuine open question rather
than effort:

    ASIC/genus-innovus/Makefile:804 asserts "The broker requires the 158/LOGO
    marker", and there is NO SOURCE for that claim anywhere in this repository.

If 158/0 is REQUIRED by the shuttle, a gate demanding its absence is not merely
useless, it is wrong, and it would fail every correct stream forever. That
question sits with the broker and is David's to answer. The shape it should take
once answered:

    presence  = count 158/0 polygons in the merged stream (klayout, no licence)
    required  -> assert >= 1, and assert the keep-out around it is clear
    forbidden -> assert == 0
Either way it needs the answer FIRST. Encoding today's guess would be a budget
set to the day's number, which is the failure this project keeps repeating.
"""
import glob
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CENSUS = os.path.join(ROOT, "scripts", "ci", "drc_census.py")


def grade(rundir):
    """Return (rc, [lines]). rc 0 only if the submission stream is genuinely clean."""
    out = []
    sums = sorted(glob.glob(os.path.join(rundir, "*.drc.summary")))
    if not sums:
        return 1, [f"no Calibre summary under {rundir}. The submission stream was "
                   f"never DRC'd — and an un-run check is not a clean one. The "
                   f"2026-08-17 16:56 bundle shipped with no logo merge at all; "
                   f"passing here on an absent file is how that happened."]
    txt = open(sums[0], errors="replace").read()

    m = re.search(r"^Layout Path\(s\):\s*(\S+)", txt, re.M)
    if not m:
        out.append("the summary records no 'Layout Path(s)', so WHICH stream was "
                   "graded cannot be established and this run is unattributable")
        layout = None
    else:
        layout = m.group(1)
        if not re.search(r"_logo[^/]*\.gds$", layout):
            out.append(
                f"this run graded {os.path.basename(layout)}, which is not a "
                f"logo-merged stream. The submission and signoff artefacts are "
                f"DIFFERENT FILES by design; grading the signoff one here finds no "
                f"LOGO.* results, reads clean, and measures nothing about what ships")

    r = subprocess.run([sys.executable, CENSUS, rundir],
                       capture_output=True, text=True, cwd=ROOT)
    blob = r.stdout + r.stderr
    if r.returncode != 0:
        reasons = [l.strip() for l in blob.splitlines()
                   if l.startswith("FAIL:") or l.lstrip().startswith("* ")]
        out.extend("census: " + x for x in reasons) or None
        if not reasons:
            out.append(f"drc_census.py exited {r.returncode} with no FAIL line — "
                       f"treat as unverified, not as a pass")
    if out:
        return 1, out
    return 0, [f"submission stream graded clean — {os.path.basename(layout)}"]


def self_test():
    """A gate that cannot fail is worthless; a gate that cannot pass is too."""
    cases = [
        ("logoed+saturated must REFUSE", 1,
         "ASIC/eth-chiplet/build/full-20260814/logo_variant_drc_20260817/jack/"
         "calibre_runs/drc_logo_flow", "SATURATED"),
        ("un-logoed must REFUSE, naming the wrong stream", 1,
         "ASIC/eth-chiplet/build/fp1505/work/drc_run", "not a logo-merged stream"),
        ("absent rundir must REFUSE, not read clean", 1,
         "/nonexistent/submission/rundir", "never DRC'd"),
    ]
    bad = 0
    for name, want_rc, rundir, want_txt in cases:
        rc, lines = grade(os.path.join(ROOT, rundir) if not rundir.startswith("/")
                          else rundir)
        blob = " ".join(lines)
        ok = (rc == want_rc) and (want_txt in blob)
        print(f"  {'ok  ' if ok else 'FAIL'}  {name}")
        if not ok:
            bad += 1
            print(f"        wanted rc={want_rc} and {want_txt!r}; got rc={rc}: {blob[:160]}")
    print()
    if bad:
        print(f"SELF-TEST FAILED — {bad} case(s) did not discriminate.")
        return 1
    print("SELF-TEST PASSED — refuses a saturated logo run, refuses an un-logoed "
          "stream by name, and refuses an absent one.")
    return 0


if __name__ == "__main__":
    if "--self-test" in sys.argv[1:]:
        sys.exit(self_test())
    rd = os.environ.get("SUBMISSION_DRC_RUNDIR") or (
        sys.argv[1] if len(sys.argv) > 1 else "")
    if not rd:
        print("usage: drc_submission_check.py <logo-merged calibre rundir>", file=sys.stderr)
        print("       or set SUBMISSION_DRC_RUNDIR; --self-test proves it discriminates",
              file=sys.stderr)
        sys.exit(2)
    rc, lines = grade(rd)
    for l in lines:
        print(("drc-submission: FAIL — " if rc else "drc-submission: ") + l)
    sys.exit(rc)
