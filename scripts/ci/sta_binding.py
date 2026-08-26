#!/usr/bin/env python3
"""
Is there a signoff-STA result, did it finish, and does it belong to THIS build?

A joint work commissioned on behalf of SoC Labs, under Arm Academic Access
license.  Copyright 2026, SoC Labs (www.soclabs.org)

WHY THIS IS A SEPARATE THING FROM sta_gate.py
---------------------------------------------
ASIC/sta/sta_gate.py grades TIMING QUALITY: derate, extraction, coverage, WNS,
failing endpoints.  It is mutation-proven and it is the right grader for that
question.  It asks exactly one question this project has already been burned
by, though, and it does not ask it:

    WHICH BUILD ARE THESE NUMBERS ABOUT?

Measured 2026-08-26: sta_gate.py's `check()` never reads the manifest's
`sta_db` key.  Its selftest is 1 baseline + 22 mutation arms and not one of
them is a wrong-build arm.  So every property it asserts is a property of
whatever report set it is pointed at, and a report set from a build seven
routes old satisfies all of them exactly as well as the right one.

That is not hypothetical.  Signoff STA ran six times on 17-18 August; all six
recorded

    sta_db = .../build/full-20260814/work/...

because nothing ever pointed the harness at a newer build, and nothing
anywhere noticed.  A timing verdict attributed to the wrong die is worse than
no timing verdict, because it is quoted.

So the split is:

    sta_binding.py   which build is this, and is it a finished run     (block)
    sta_gate.py      does that build's timing close                    (report)

which is the same division ci/signoff.yaml's ir-drop stage already makes
between its own census provenance checks and rail_gate.py's millivolts, and
the same division signoff.py makes between UNVERIFIED (indicts the run) and
FAIL (indicts the design).

RULES, inherited from sta_gate.py's header because the failure modes are the
same family:

  R1  Missing, empty or unparseable evidence is a FAILURE, never a pass.
  R4  No tool exit code is consulted.  Only artefacts.
  R5  (new here)  The evidence must NAME the thing it is evidence about, and
      the name must be checked against the thing under judgement -- not
      against itself.

USAGE
  sta_binding.py --reports <dir> --build-tag <tag> [--build-root <dir>]
  sta_binding.py --selftest
"""

import argparse
import os
import re
import shutil
import sys
import tempfile

# The routed database the P&R flow writes, and the only database a signoff STA
# of this design may have read.  Named rather than pattern-matched: "a
# directory under work/" also describes the placed and the CTS databases, and
# timing one of those and calling it signoff is precisely the substitution
# this file exists to refuse.
ROUTED_DB_NAME = "nanosoc_eth_chiplet_pads_routed"

# Every Tempus report carries this header block.  The SI state is read from
# HERE and from nowhere else -- see the SI note below.
_SIGNOFF_SETTINGS = re.compile(r"^#\s*Signoff Settings:\s*(?P<state>.+?)\s*$", re.M)

# route_manifest.txt is `key<spaces>value`, not `key = value`.
_ROUTE_DATE = re.compile(r"^date\s+(?P<d>\d{4}-\d{2}-\d{2})[ T](?P<t>\d{2}:\d{2}:\d{2})", re.M)


class Result:
    """Same three-bucket shape as sta_gate.py's, so the two read alike."""

    def __init__(self):
        self.failures = []
        self.warnings = []
        self.facts = {}

    def fail(self, code, msg):
        self.failures.append((code, msg))

    def warn(self, code, msg):
        self.warnings.append((code, msg))

    def fact(self, k, v):
        self.facts[k] = v

    @property
    def ok(self):
        return not self.failures


def parse_kv(path, sep="="):
    """`key = value` per line.  Returns {} for absent or unreadable."""
    if not os.path.isfile(path):
        return {}
    out = {}
    with open(path, errors="replace") as fh:
        for line in fh:
            if sep not in line:
                continue
            k, _, v = line.partition(sep)
            out[k.strip()] = v.strip()
    return out


def _iso(s):
    """'2026-08-26T09:56:24' or '2026-08-26 09:56:24' -> comparable tuple."""
    m = re.match(r"(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2}):(\d{2})", s or "")
    return tuple(int(g) for g in m.groups()) if m else None


def si_state_from_headers(reports_dir):
    """
    The SI state, read off the REPORT HEADERS.

    CORRECTED 2026-08-26 and this is the whole point of the function.  Until
    that date the harness recorded `si_analysis = off` in its manifest, on the
    reasoning that make_sta_mmmc.py strips the `-si` library sections for
    IMPESI-3490.  Measured on gdsrun-20260826-rc1: every Tempus report header
    in that run reads `Signoff Settings: SI On`, and the update_timing step
    logs two SI iterations before it.  Tempus does SI-aware delay calculation
    from the coupling capacitance in the Quantus SPEF; what stripping `-si`
    costs is the characterised noise models, which is a different claim.

    A manifest is a record of what a script BELIEVED.  A report header is a
    record of what the tool DID.  When they disagree the header wins, and a
    grader that reads the manifest for this is repeating the defect it is
    supposed to catch -- the same shape as a probe reporting a tool absent
    because it is not on PATH.

    Returns (state_string_or_None, number_of_report_files_carrying_a_header).
    """
    if not os.path.isdir(reports_dir):
        return None, 0
    states, seen = set(), 0
    for name in sorted(os.listdir(reports_dir)):
        if not name.endswith((".rpt", ".log")):
            continue
        p = os.path.join(reports_dir, name)
        if not os.path.isfile(p):
            continue
        try:
            with open(p, errors="replace") as fh:
                head = fh.read(200000)
        except OSError:
            continue
        for mo in _SIGNOFF_SETTINGS.finditer(head):
            states.add(mo.group("state"))
            seen += 1
    if not states:
        return None, 0
    return ", ".join(sorted(states)), seen


def check(reports_dir, build_tag, build_root, r):
    r.fact("build_tag", build_tag)
    r.fact("reports_dir", reports_dir)

    man_path = os.path.join(reports_dir, "sta_manifest.txt")

    # -- 1 -- IS THERE A RESULT AT ALL? ------------------------------------
    # Absence is not a pass.  It is the state this project was in for the
    # whole of the tapeout up to 2026-08-26: a working STA harness, a licence
    # sitting idle, and no stage that would go red for want of a run.
    if not os.path.isdir(reports_dir):
        r.fail("STA_NOT_RUN",
               f"no STA report directory at {reports_dir}. This candidate has "
               f"NOT been timed. Signoff STA is not optional evidence that can "
               f"be gathered later -- a release candidate with no timing result "
               f"is not a release candidate.")
        return r
    if not os.path.isfile(man_path):
        r.fail("STA_NOT_RUN",
               f"no sta_manifest.txt in {reports_dir}. The directory exists but "
               f"carries no run record, so nothing here can be attributed to a "
               f"run. If the launcher refused the database (it declines one "
               f"whose files changed in the last 20 minutes, to avoid reading a "
               f"live route) then STA has not happened yet and this is correct.")
        return r

    man = parse_kv(man_path)
    if not man:
        r.fail("MANIFEST_EMPTY", f"manifest parsed to zero keys: {man_path}")
        return r

    # -- 2 -- DID IT FINISH? -----------------------------------------------
    # `sta_finished` is written by the last line of run_signoff_sta.tcl. A
    # report set without it came from a run that was killed, ran out of
    # licence or died mid-analysis, and its reports are a prefix of a result.
    if "sta_finished" not in man:
        r.fail("RUN_INCOMPLETE",
               "manifest has no sta_finished key: the run did not reach the end "
               "of its own script. Partial reports read exactly like complete "
               "ones -- report_timing_summary writes a well-formed file whether "
               "or not the analysis after it ever happened.")
    else:
        r.fact("sta_finished", man["sta_finished"])

    # A failed read_db is the one step failure that makes every later number
    # meaningless rather than merely incomplete: the design is not in memory,
    # so the reports describe nothing.  Every OTHER step failure is a quality
    # question and belongs to sta_gate.py, not here -- this stage must not
    # start duplicating that grader's verdict or the two will disagree.
    if man.get("step.read_db") == "FAILED":
        r.fail("DESIGN_NOT_LOADED",
               "step.read_db = FAILED: the database never loaded, so every "
               "report in this directory was produced with no design in memory.")

    # -- 3 -- WHICH BUILD?  THE LOAD-BEARING ONE. ---------------------------
    db = man.get("sta_db")
    if not db:
        r.fail("DB_UNRECORDED",
               "manifest has no sta_db key, so this report set does not say "
               "which database it read. Unattributable evidence cannot be bound "
               "to a candidate, and binding is the entire job of this check.")
        return r
    r.fact("sta_db", db)

    norm = os.path.normpath(db)
    if os.path.basename(norm) != ROUTED_DB_NAME:
        r.fail("DB_NOT_ROUTED",
               f"sta_db ends in {os.path.basename(norm)!r}, not {ROUTED_DB_NAME!r}. "
               f"Signoff STA must read the ROUTED database. A placed or "
               f"post-CTS database times with estimated interconnect and "
               f"reports better numbers than the die has.")

    # The string test.  Runs everywhere, including in a fixture sandbox where
    # no build tree exists, which is what makes this arm provable.
    want_frag = os.sep + build_tag + os.sep
    if want_frag not in norm + os.sep:
        got = _tag_in(norm, build_root)
        r.fail("WRONG_BUILD",
               f"this report set was produced from build {got or 'an unrecognised path'}, "
               f"not from {build_tag}.\n"
               f"      sta_db = {db}\n"
               f"  Six STA runs on 17-18 August all read the same stale build and "
               f"nothing noticed, because the only thing that ever named a build "
               f"was a default inside the launcher. A timing number attributed to "
               f"the wrong die gets quoted; it does not get caught downstream.")
        return r

    # The identity test.  STRENGTHENS the string test when the build tree is
    # present, and is silent when it is not -- so a passing fixture is never
    # mistaken for a passing measurement.  Two paths can carry the same tag and
    # be different directories (a symlinked or relocated build), and two
    # different strings can be the same directory.
    expect = os.path.join(build_root, build_tag, "work", ROUTED_DB_NAME)
    if os.path.isdir(expect):
        if not os.path.isdir(norm):
            r.fail("DB_GONE",
                   f"sta_db names {db}, which no longer exists, while "
                   f"{expect} does. The report set cannot be re-derived and its "
                   f"provenance cannot be confirmed against anything.")
        elif os.path.realpath(norm) != os.path.realpath(expect):
            r.fail("WRONG_BUILD",
                   f"sta_db carries the tag {build_tag} but resolves elsewhere:\n"
                   f"      sta_db  -> {os.path.realpath(norm)}\n"
                   f"      expected-> {os.path.realpath(expect)}")
        else:
            r.fact("db_identity", "realpath-confirmed against the build tree")
    else:
        r.warn("DB_ABSENT_HERE",
               f"{expect} is not on this host, so the build binding rests on the "
               f"path string alone. That is the weaker of the two tests.")

    # -- 4 -- IS IT NEWER THAN THE ROUTE IT CLAIMS TO HAVE READ? -----------
    # The string test above is defeated by copying an old reports directory
    # into the pinned location and by hand-editing one line.  This is not:
    # a run cannot have read a database that did not exist when it started.
    rm = os.path.join(build_root, build_tag, "reports", "route_manifest.txt")
    if not os.path.isfile(rm):
        r.fail("NO_FINISHED_ROUTE",
               f"no {rm}. That file is written at the END of the route stage, so "
               f"its absence means this build's route never finished -- there is "
               f"nothing legitimate for an STA result to have been derived from. "
               f"A half-written database has work/ and no manifest.")
    else:
        mo = _ROUTE_DATE.search(open(rm, errors="replace").read())
        route_t = _iso(f"{mo.group('d')}T{mo.group('t')}") if mo else None
        sta_t = _iso(man.get("sta_started", ""))
        if route_t is None:
            r.warn("ROUTE_DATE_UNPARSED",
                   f"{rm} carries no parseable date line; the ordering test is "
                   f"skipped, so the build binding rests on the path alone.")
        elif sta_t is None:
            r.fail("STA_START_UNRECORDED",
                   "manifest has no parseable sta_started, so this run cannot be "
                   "ordered against the route it claims to describe.")
        elif sta_t < route_t:
            r.fail("PREDATES_ROUTE",
                   f"the STA run started {man.get('sta_started')} and the route it "
                   f"names finished {mo.group('d')}T{mo.group('t')}. A run cannot "
                   f"have read a database written after it started: these reports "
                   f"belong to an earlier route of the same tag, or they were "
                   f"copied in from elsewhere.")
        else:
            r.fact("ordering", f"STA {man.get('sta_started')} after route "
                               f"{mo.group('d')}T{mo.group('t')}")

    # -- 5 -- SI STATE, FROM THE HEADERS ------------------------------------
    state, seen = si_state_from_headers(reports_dir)
    if state is None:
        r.fail("NO_TOOL_HEADER",
               f"not one report in {reports_dir} carries a `Signoff Settings:` "
               f"header. Every Tempus report emits one, so either these files "
               f"did not come from Tempus or they were truncated before the "
               f"analysis banner. Either way the SI state of this run is "
               f"unknown, and the manifest must not be used to supply it.")
    else:
        r.fact("signoff_settings", f"{state}  (in {seen} report section(s))")
        # Recorded as a divergence, NOT as a verdict: which of the two is right
        # is sta_gate.py's and the harness's business.  What matters here is
        # that a reader is never handed the manifest's belief on its own.
        claimed = man.get("si_analysis")
        if claimed and "off" in claimed.lower() and "SI On" in state:
            r.warn("SI_RECORD_DIVERGES",
                   f"the manifest records si_analysis = {claimed!r} while the "
                   f"report headers read {state!r}. The headers are the "
                   f"measurement. This run predates the harness correction of "
                   f"2026-08-26; the key is now si_noise_libs.")

    # -- 6 -- HOLD COVERAGE, SURFACED RATHER THAN SWALLOWED -----------------
    # Not a failure of THIS gate: it is a declared gap in ci/signoff.yaml with
    # its own refutation probe.  It is reported here because this is the one
    # place a reader is already looking at what the run did and did not do.
    if man.get("step.report_analysis_coverage_hold") == "FAILED" or \
            not os.path.isfile(os.path.join(reports_dir, "analysis_coverage_hold.rpt")):
        r.warn("HOLD_COVERAGE_UNMEASURED",
               "this run produced no hold-side analysis coverage. The late-only "
               "coverage report lists no early check types at all, so the "
               "untested-check census below is a SETUP census being read as if "
               "it were the whole design. See the sta-hold-coverage gap.")
    return r


def _tag_in(path, build_root):
    """The build tag a path appears to name, for the error message only."""
    parts = os.path.normpath(path).split(os.sep)
    root = os.path.basename(os.path.normpath(build_root))
    if root in parts:
        i = parts.index(root)
        if i + 1 < len(parts):
            return parts[i + 1]
    return None


def emit(r):
    if r.facts:
        print("MEASURED")
        for k, v in r.facts.items():
            print(f"  {k:22s} {v}")
        print()
    for c, m in r.warnings:
        print(f"WARN  [{c}] {m}")
    for c, m in r.failures:
        print(f"FAIL  [{c}] {m}")
    print()
    print("BINDING: PASS" if r.ok else f"BINDING: FAIL ({len(r.failures)} failure(s))")


# ---------------------------------------------------------------------------
# SELF-TEST -- the part that proves this check can fail.
#
# Same doctrine as ASIC/sta/sta_gate.py --selftest and
# ASIC/genus-innovus/rail/rail_gate.py --selftest: a gate that has not been
# shown to reject a specific wrong thing has not been shown to do anything.
# Every arm below is a way THIS PROJECT has actually been misled, not an
# invented mutation:
#
#   wrong build      six runs, 17-18 August, all reading full-20260814
#   no result        27 signoff stages and not one that times anything
#   unfinished       a killed run leaves well-formed partial reports
#   copied-in        a reports directory moved into the pinned path
#   not routed       a placed database times optimistically and loads fine
# ---------------------------------------------------------------------------
TAG = "gdsrun-20260826-rc1"

GOOD_MANIFEST = """\
sta_tool = tempus
sta_tool_version = 21.11
sta_db = {root}/{tag}/work/nanosoc_eth_chiplet_pads_routed
sta_started = 2026-08-26T09:56:24
step.read_db = ok
design_name = nanosoc_eth_chiplet_pads
clock_count = 52
sta_finished = 2026-08-26T10:08:20
"""

GOOD_ROUTE_MANIFEST = """\
date                     2026-08-26 05:28:45
runtime_s                4200
stage                    route
run_tag                  gdsrun-20260826-rc1
"""

# The banner Tempus prints above every report and again in the log.  Pinned
# verbatim so a tool upgrade that reworded it breaks this selftest rather than
# silently turning the SI read into a no-op.
GOOD_REPORT = """\
#################################################################################
# Design Name: nanosoc_eth_chiplet_pads
# Analysis Mode: MMMC OCV
# Parasitics Mode: SPEF/RCDB
# Signoff Settings: SI On
#################################################################################
# SETUP                   WNS       TNS   FEP
 View : ALL             0.012     0.000     0
"""


def _mk(tmp, manifest=GOOD_MANIFEST, route=GOOD_ROUTE_MANIFEST,
        report=GOOD_REPORT, tag=TAG, make_db=True):
    """Build a throwaway tree: <base>/build/<tag>/... plus a reports dir."""
    base = tempfile.mkdtemp(dir=tmp)
    root = os.path.join(base, "build")
    if make_db:
        os.makedirs(os.path.join(root, tag, "work", ROUTED_DB_NAME))
    os.makedirs(os.path.join(root, tag, "reports"), exist_ok=True)
    if route is not None:
        with open(os.path.join(root, tag, "reports", "route_manifest.txt"), "w") as fh:
            fh.write(route)
    reps = os.path.join(base, "sta", tag, "reports")
    if manifest is not None:
        os.makedirs(reps, exist_ok=True)
        with open(os.path.join(reps, "sta_manifest.txt"), "w") as fh:
            fh.write(manifest.format(root=root, tag=tag))
    if report is not None:
        os.makedirs(reps, exist_ok=True)
        with open(os.path.join(reps, "timing_summary.rpt"), "w") as fh:
            fh.write(report)
    return reps, root


def selftest():
    tmp = tempfile.mkdtemp(prefix="sta_binding_selftest_")
    passed = failed = 0
    try:
        reps, root = _mk(tmp)
        r = check(reps, TAG, root, Result())
        if r.ok:
            print("ok    baseline PASSES")
            passed += 1
        else:
            print(f"BROKEN baseline FAILS: {r.failures}")
            failed += 1

        # A directory that exists but was never written into.  Distinct from
        # "no directory": the pinned path is created by the launcher before
        # the tool runs, so this is what a licence refusal leaves behind.
        empty, root2 = _mk(tmp, manifest=None, report=None)
        os.makedirs(empty, exist_ok=True)

        cases = [
            ("no STA at all -- the state this repo shipped in",
             dict(manifest=None, report=None), "STA_NOT_RUN"),

            ("manifest parses to nothing",
             dict(manifest="\n\n\n"), "MANIFEST_EMPTY"),

            ("run killed before its last line",
             dict(manifest=GOOD_MANIFEST.replace(
                 "sta_finished = 2026-08-26T10:08:20", "")), "RUN_INCOMPLETE"),

            ("the database never loaded",
             dict(manifest=GOOD_MANIFEST.replace(
                 "step.read_db = ok", "step.read_db = FAILED")), "DESIGN_NOT_LOADED"),

            ("report set does not say what it read",
             dict(manifest=GOOD_MANIFEST.replace(
                 "sta_db = {root}/{tag}/work/nanosoc_eth_chiplet_pads_routed", "")),
             "DB_UNRECORDED"),

            # THE LOAD-BEARING ARM.  This is the exact shape of all six
            # historical runs: a complete, well-formed, internally consistent
            # report set about a different die.
            ("A DIFFERENT BUILD (the 17-18 August failure, verbatim)",
             dict(manifest=GOOD_MANIFEST.replace(
                 "sta_db = {root}/{tag}/work/nanosoc_eth_chiplet_pads_routed",
                 "sta_db = {root}/full-20260814/work/nanosoc_eth_chiplet_pads_routed")),
             "WRONG_BUILD"),

            ("a different build whose tag is a PREFIX of the right one",
             dict(manifest=GOOD_MANIFEST.replace(
                 "sta_db = {root}/{tag}/work/nanosoc_eth_chiplet_pads_routed",
                 "sta_db = {root}/{tag}-eco/work/nanosoc_eth_chiplet_pads_routed")),
             "WRONG_BUILD"),

            ("the placed database, not the routed one",
             dict(manifest=GOOD_MANIFEST.replace(
                 "work/nanosoc_eth_chiplet_pads_routed",
                 "work/nanosoc_eth_chiplet_pads_placed")), "DB_NOT_ROUTED"),

            ("reports copied in from an earlier route of the same tag",
             dict(manifest=GOOD_MANIFEST.replace(
                 "sta_started = 2026-08-26T09:56:24",
                 "sta_started = 2026-08-25T22:10:00")), "PREDATES_ROUTE"),

            ("the route never finished",
             dict(route=None), "NO_FINISHED_ROUTE"),

            ("no start time, so nothing can be ordered",
             dict(manifest=GOOD_MANIFEST.replace(
                 "sta_started = 2026-08-26T09:56:24", "")), "STA_START_UNRECORDED"),

            ("reports carry no tool banner",
             dict(report="# SETUP  WNS TNS FEP\n View : ALL 0.012 0.000 0\n"),
             "NO_TOOL_HEADER"),
        ]

        for name, kw, want in cases:
            # `is None` would be wrong here: a case that passes neither key
            # also reads as None, and the no-STA arm would then swallow every
            # other arm's tree.  Ask whether the key was GIVEN.
            if kw.get("manifest", "x") is None and kw.get("report", "x") is None:
                reps_c, root_c = empty, root2
            else:
                reps_c, root_c = _mk(tmp, **kw)
            rr = check(reps_c, TAG, root_c, Result())
            codes = [c for c, _ in rr.failures]
            if rr.ok:
                print(f"BROKEN {name!r}: PASSED a mutant it must reject")
                failed += 1
            elif want not in codes:
                print(f"BROKEN {name!r}: failed with {codes}, expected {want}")
                failed += 1
            else:
                print(f"ok    rejects: {name}  [{want}]")
                passed += 1

        # Two POSITIVE controls beyond the baseline.  A check that says no to
        # everything is not a gate either, and both of these are shapes that
        # MUST still pass or the gate would be unusable in CI.
        reps_w, root_w = _mk(tmp, make_db=False)          # build tree not on this host
        rw = check(reps_w, TAG, root_w, Result())
        if rw.ok and any(c == "DB_ABSENT_HERE" for c, _ in rw.warnings):
            print("ok    passes on a host with no build tree, and SAYS the "
                  "binding is string-only  [DB_ABSENT_HERE]")
            passed += 1
        else:
            print(f"BROKEN absent-build-tree control: ok={rw.ok} "
                  f"failures={[c for c, _ in rw.failures]}")
            failed += 1

        reps_h, root_h = _mk(tmp, manifest=GOOD_MANIFEST +
                             "si_analysis = off (mmmc -si stripped for IMPESI-3490)\n")
        rh = check(reps_h, TAG, root_h, Result())
        if rh.ok and any(c == "SI_RECORD_DIVERGES" for c, _ in rh.warnings):
            print("ok    reads SI from the HEADER and reports the manifest's "
                  "disagreement  [SI_RECORD_DIVERGES]")
            passed += 1
        else:
            print(f"BROKEN SI-header control: ok={rh.ok} "
                  f"warnings={[c for c, _ in rh.warnings]}")
            failed += 1
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    print(f"\nSELFTEST: {passed} passed, {failed} broken")
    return 0 if failed == 0 else 1


def main():
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--reports", help="the STA report directory for the build under judgement")
    ap.add_argument("--build-tag", help="the build this candidate is (e.g. gdsrun-YYYYMMDD-xx)")
    ap.add_argument("--build-root", default="ASIC/eth-chiplet/build",
                    help="directory holding the per-build trees")
    ap.add_argument("--selftest", action="store_true",
                    help="mutation-test this check itself")
    args = ap.parse_args()

    if args.selftest:
        return selftest()
    if not args.reports or not args.build_tag:
        ap.error("--reports and --build-tag are both required (or use --selftest)")

    r = check(args.reports, args.build_tag, args.build_root, Result())
    emit(r)
    return 0 if r.ok else 1


if __name__ == "__main__":
    sys.exit(main())
