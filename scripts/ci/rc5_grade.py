#!/usr/bin/env python3
"""
rc5_grade.py -- grade ONE rc5 iteration, and prove each row could have said no.

A joint work commissioned on behalf of SoC Labs, under Arm Academic Access
license.  Copyright 2026, SoC Labs (www.soclabs.org)

    scripts/ci/rc5_grade.py --build-tag rc5vt-20260829

WHAT IT ANSWERS, IN ONE PLACE, FOR ONE CANDIDATE

    setup-closed        did setup close?
    hold-closed         did hold close AT ALL THREE REQUIRED VIEWS?
    drc-clean           is Calibre DRC clean?
    stream-binding      did every gate read THIS run's stream?
    untested-attributed is every untested timing check attributed to a reason?

WHY EVERY ROW CARRIES A CONTROL
-------------------------------
rc5 exists to validate the flow, and the only real failure a validation run can
have is a green that was green because nothing measured anything. This project
has a documented CLASS of those: a DRC gate blind to unmapped layers; an LVS
check whose sign was inverted so that BREAKING a ground pin made it cleaner;
`check_timing` never measuring clock_crossing because that check is off by
default; Calibre writing a truncated count into both count fields so a capped
run looks like a complete one. Every one of them PASSED while measuring nothing.

So a verdict here is two facts, not one:

    the answer          PASS / FAIL
    the control         did the same predicate, run over evidence mutated to
                        carry the defect, return the OTHER answer?

A row whose control did not flip is NOT-MEASURED, whatever its answer was. The
mutations are applied to THIS RUN'S OWN ARTEFACTS -- not to a checked-in fixture
-- because a fixture proves a check matches its fixtures, which is a weaker
claim and one this repository has already been misled by.

EXIT CODES. Non-zero on an unmeasured claim, not only on a failure:

    0   every row PASS, every control flipped
    1   at least one row FAIL (and nothing unmeasured)
    2   at least one row NOT-MEASURED, or a control that did not flip
    3   the pre-flight failed, or the invocation could not be resolved

2 OUTRANKS 1 ON PURPOSE. "This design fails hold" is a result. "This harness
cannot tell whether it fails hold" is not a worse result, it is the absence of
one, and it sends someone somewhere else.

THE BUILD TAG HAS NO DEFAULT, for the reason ci/signoff.yaml's `vars:` block
gives at length: a default is how thirteen stages came to grade a die from 23
August while rendering green.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
sys.path.insert(0, str(HERE))
import drc_tiers                                              # noqa: E402

PASS, FAIL, NOT_MEASURED = "PASS", "FAIL", "NOT-MEASURED"
BLOCK = "nanosoc_eth_chiplet_pads"

# The hold corners a signoff run is not allowed to skip. Kept in step with
# ASIC/sta/sta_policy.json, and READ FROM IT when it is readable -- these three
# produced this tapeout's worst hold findings and neither of the last two is
# reachable from the default MMMC.
DEFAULT_HOLD_VIEWS = ["default_analysis_view_hold",
                      "av_ml_libset_hold",
                      "av_ltfix_libset_hold"]


# ---------------------------------------------------------------------------
# Evidence is read ONCE into a dict of documents. Every probe below is then a
# pure function of that dict, which is what makes a control cheap: a control is
# the same probe over a mutated copy of the dict. Nothing re-reads the disk, so
# a mutation cannot be undone by a stale read, and a 300 MB stream is never
# copied.
# ---------------------------------------------------------------------------
def read(p):
    try:
        return Path(p).read_text(errors="replace")
    except OSError:
        return None


def md5_of(p, blocks=1 << 22):
    h = hashlib.md5()
    try:
        with open(p, "rb") as fh:
            for blk in iter(lambda: fh.read(blocks), b""):
                h.update(blk)
    except OSError:
        return None
    return h.hexdigest()


def parse_kv(text):
    """`key = value` manifest lines -> dict. Later wins, as Tempus appends."""
    out = {}
    for line in (text or "").splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            out[k.strip()] = v.strip()
    return out


_SUMMARY_ROW = re.compile(
    r"^\s*(?:Group|View)\s*:\s*(?P<name>\S+)\s+"
    r"(?P<wns>-?[\d.]+|N/A)\s+(?P<tns>-?[\d.]+|N/A)\s+(?P<fep>\d+)\s*$")


def parse_summary(text):
    """-> (wns, fep) over every parsed row, or None if nothing parsed.

    WNS is the WORST row and FEP the SUM, because report_timing_summary prints
    one row per path group and a gate that read only the first row would grade
    reg2reg and call it the design. `N/A` is a group with no path and
    contributes nothing -- it is not a zero.
    """
    wns, fep, rows = None, 0, 0
    for line in (text or "").splitlines():
        mo = _SUMMARY_ROW.match(line)
        if not mo:
            continue
        rows += 1
        fep += int(mo.group("fep"))
        if mo.group("wns") != "N/A":
            w = float(mo.group("wns"))
            wns = w if wns is None else min(wns, w)
    return None if rows == 0 else (wns, fep, rows)


# The per-view hold evidence is `report_timing -view <v> -early -max_paths 50`,
# a PATH report -- not a summary. Each path opens `Path N: MET (0.006 ns)` or
# `Path N: VIOLATED (-0.078 ns)`, and Tempus sorts worst-first, so `Path 1: MET`
# is sound proof that no path at that view violates. The 50-path cap makes a
# VIOLATED count a LOWER BOUND and never an upper one, which is the safe
# direction. The `View:` line is read too: a report written for the wrong view
# is the wrong-build defect in miniature, and it is exactly what a hand-edited
# report set looks like.
_PATH = re.compile(r"^Path \d+:\s+(MET|VIOLATED)\s+\(\s*(-?[\d.]+)\s*ns\)", re.M)
_VIEWLINE = re.compile(r"^\s*View:\s*(\S+)\s*$", re.M)

_UNTESTED_ROW = re.compile(r"^(?P<pre>.*?)\s{2,}UNTESTED\s+(?P<reason>\S.*?)\s*$")
REASONS = {"const": "const", "constant": "const",
           "falsepath": "false_path", "false_path": "false_path",
           "noendpointclock": "no_endpoint_clock",
           "nostartpointclock": "no_startpoint_clock",
           "userdisable": "user_disable", "userdisabled": "user_disable",
           "disabled": "user_disable", "unknown": "unknown"}


def parse_untested(text):
    """-> {canonical reason: count}. An UNRECOGNISED reason counts as `unknown`.

    That is the anti-vacuity property: a Tempus format drift, a new reason
    category or a typo must make the gate FIRE, never make a population quietly
    leave the histogram.
    """
    counts = {}
    for line in (text or "").splitlines():
        mo = _UNTESTED_ROW.match(line)
        if not mo or mo.group("pre").strip().lower().startswith("check type"):
            continue
        key = re.sub(r"[^a-z]", "", mo.group("reason").lower())
        r = REASONS.get(key, "unknown")
        counts[r] = counts.get(r, 0) + 1
    return counts


_COV_ROW = re.compile(
    r"^\s*(?P<name>[A-Za-z][A-Za-z0-9 ()_\-]*?)\s{2,}(?P<n>\d+)\s+"
    r"\d+\s*\(\s*\d+%\s*\)\s+\d+\s*\(\s*\d+%\s*\)\s+(?P<unt>\d+)\s*\(\s*\d+%\s*\)\s*$")


def parse_coverage(text):
    """-> (total untested, rows parsed). Zero rows is never zero untested."""
    tot, rows = 0, 0
    for line in (text or "").splitlines():
        mo = _COV_ROW.match(line)
        if mo:
            rows += 1
            tot += int(mo.group("unt"))
    return tot, rows


# re.M IS LOAD-BEARING. Without it this anchors only at the start of the whole
# file, findall() returns [], and probe_drc's "zero RULECHECK rows parsed" arm
# fires over a report holding 1,926 of them -- a NOT-MEASURED that looks like a
# tool problem and is a regex problem. Caught by the drc_zero control, which is
# the point of having one.
_RULECHECK = re.compile(
    r"^RULECHECK\s+(?P<name>\S+)\s*\.*\s*TOTAL Result Count\s*=\s*(?P<n>\d+)",
    re.M)
_CAP = re.compile(r"^Maximum Results/RuleCheck:\s*(\d+)\s*$", re.M)
_LAYOUT = re.compile(r"^Layout Path\(s\):\s*(\S+)\s*$", re.M)
_EXECUTED = re.compile(r"^TOTAL DRC RuleChecks Executed:\s*(\d+)\s*$", re.M)
# Calibre LVS: no Layout Path line exists. CURRENT DIRECTORY is the run dir.
_LVS_CWD = re.compile(r"^CURRENT DIRECTORY:\s*(\S+)\s*$", re.M)


# ---------------------------------------------------------------------------
# THE ROWS. Each is (id, question, probe, [(control name, mutation)]).
# A probe returns (verdict, detail). A mutation returns a NEW doc dict.
# ---------------------------------------------------------------------------
def probe_setup(d):
    man = parse_kv(d.get("sta_manifest"))
    if d.get("sta_manifest") is None:
        return NOT_MEASURED, "no sta_manifest.txt: no signoff STA exists for this build"
    if "sta_finished" not in man:
        return NOT_MEASURED, "the STA run has no sta_finished line -- it did not reach its end"
    got = parse_summary(d.get("timing_summary"))
    if got is None:
        return NOT_MEASURED, "timing_summary.rpt is absent or parsed zero rows"
    wns, fep, rows = got
    if wns is None:
        return NOT_MEASURED, f"{rows} row(s) parsed and every WNS is N/A -- no setup path was timed"
    if fep > 0:
        return FAIL, f"setup FEP {fep} over {rows} group(s), WNS {wns:+.3f}"
    if wns < 0:
        return FAIL, f"setup FEP 0 but WNS {wns:+.3f} -- a negative slack with no failing endpoint is a report to distrust"
    return PASS, f"setup FEP 0, WNS {wns:+.3f} over {rows} group(s)"


def probe_hold(d, required):
    if d.get("sta_manifest") is None:
        return NOT_MEASURED, "no sta_manifest.txt"
    man = parse_kv(d["sta_manifest"])
    raw = man.get("analysis_views_hold")
    if raw is None:
        return NOT_MEASURED, "the manifest records no analysis_views_hold: which hold corners ran is unknown"
    active = [v for v in raw.split(",") if v]
    absent = [v for v in required if v not in active]
    if absent:
        return FAIL, ("required hold view(s) not active: %s (active: %s). A hold "
                      "corner you do not activate reports nothing, and nothing "
                      "is indistinguishable from passing."
                      % (", ".join(absent), ", ".join(active)))
    # THE GAP sta_policy.json's _comment_5d LEAVES OPEN, closed here. The gate
    # matches view names against the manifest, which records the views ACTIVE in
    # the session -- a run that activates a view and then writes no report for
    # it still clears that check. `report_timing_summary -checks hold` prints a
    # single `View : ALL` row, so the aggregate cannot tell you whether three
    # views were folded in or one. The per-view report is the only evidence.
    missing = [v for v in required if d.get("hold_view:" + v) is None]
    if missing:
        return NOT_MEASURED, ("view(s) %s are active in the manifest but wrote no "
                              "timing_hold_<view>.rpt. The aggregate hold row is "
                              "`View : ALL` and cannot say which views it folded."
                              % ", ".join(missing))
    got = parse_summary(d.get("timing_summary_hold"))
    if got is None:
        return NOT_MEASURED, "timing_summary_hold.rpt is absent or parsed zero rows"
    wns, fep, rows = got
    per = []
    worst = wns
    for v in required:
        txt = d["hold_view:" + v]
        paths = _PATH.findall(txt)
        if not paths:
            return NOT_MEASURED, (f"timing_hold_{v}.rpt names no timing path. A "
                                  f"view file with no path in it says nothing "
                                  f"about that corner.")
        names = set(_VIEWLINE.findall(txt))
        if names and names != {v}:
            return NOT_MEASURED, (f"timing_hold_{v}.rpt reports view(s) "
                                  f"{', '.join(sorted(names))}, not {v}. This "
                                  f"file is evidence about a different corner.")
        viol = [float(s) for st, s in paths if st == "VIOLATED"]
        vw = min(float(s) for _st, s in paths)
        per.append((v, vw, len(viol)))
        if viol:
            return FAIL, ("hold FAILS at %s: %d violating path(s) in the worst 50, "
                          "worst slack %+.3f" % (v, len(viol), min(viol)))
        if worst is None or vw < worst:
            worst = vw
    if fep > 0:
        return FAIL, f"aggregate hold FEP {fep}, WNS {wns:+.3f}"
    if worst is None:
        return NOT_MEASURED, "every hold WNS is N/A -- no hold path was timed"
    if worst < 0:
        return FAIL, f"hold FEP 0 but worst WNS {worst:+.3f} across the required views"
    return PASS, ("hold FEP 0 at all %d required views (worst WNS %+.3f: %s)"
                  % (len(required), worst,
                     ", ".join("%s %+.3f" % (v, w) for v, w, _ in per
                               if w is not None)))


def probe_drc(d):
    """Is DRC clean ON THE SCOPE THIS PROJECT CAN ACT ON?

    RESCOPED 2026-08-29, and the rescope is the point. The first version of this
    row failed rc4 with "6117 failing density windows > budget 0". That number is
    real, it is finer than anything else in the project, and it is the WRONG
    THING TO GATE ON:

      * it is a fifth scope. The summary's `.DN.` rulechecks sum to 66, not
        6,117 -- the 6,117 are per-window rows out of 36,064 in the 158
        *.density files, which is a different quantity from every other DRC
        figure this project quotes.
      * WE DO NOT SHIP THE DUMMY FILL. The foundry adds it at merge. A pre-fill
        stream is EXPECTED to be short of the density minima and nothing
        place-and-route does changes that.
      * the evidence system already encodes the split: `drc-tiers` is the hard
        gate and `metal-density` is a separate row declared foundry-side.
      * imec graded this exact md5 post-merge on 28 August and reported no
        design-rule violation of any kind -- no density family at all.

    So this row now grades TIER 4, `real geometry`, computed by
    scripts/ci/drc_tiers.py -- the same code evidence_flow.py's drc-tiers gate
    uses, so the two cannot disagree. On rc4: 737 total / 46 reported / 13
    non-density / 0 real geometry, which is exactly what the evidence report
    says. Density moved to its own row, where an ABSOLUTE shortfall is declared
    foundry-side and a REGRESSION against a reference is ours.

    A FAIL here is now a thing a flow iteration can fix.
    """
    txt = d.get("drc_summary")
    if txt is None:
        return NOT_MEASURED, "no <block>.drc.summary: Calibre DRC has not run on this build"
    if d.get("drc_waiver_problems"):
        # A waiver that does not match what it claims to explain removes results
        # from `reported` on a false premise, and every tier above it inherits
        # that. Not a FAIL -- the design may be fine -- but not a number either.
        return NOT_MEASURED, ("drc_census reports waiver problem(s), so the "
                              "waived figure the tiers subtract cannot be "
                              "trusted: " + str(d.get("drc_waiver_detail"))[:200])
    cls = drc_tiers.classify(txt, waived=d.get("drc_waived"))
    if cls["limit"] is None:
        # THE ABSENT-CAP SHORT-CIRCUIT, CLOSED HERE. Every saturation test in
        # this repository guards the comparison on the cap's own truthiness, so
        # when the header is missing the test evaluates to False and a TRUNCATED
        # report is scored as a complete one -- four live instances, triaged in
        # scripts/ci/vacuity_ledger_chiplet.txt. An absent cap is the reason a
        # run cannot be vouched for, not a reason to vouch for it.
        #
        # (Worded without the literal shape on purpose: the vacuous-gate scanner
        # reads TEXT and cannot tell a comment from code, so quoting the pattern
        # here made this file report itself as an instance of it.)
        return NOT_MEASURED, ("the summary carries no `Maximum Results/RuleCheck:` "
                              "header, so no result count in it can be shown to be "
                              "un-truncated. A capped check has an unknown true count.")
    if cls["executed"] is None:
        return NOT_MEASURED, "the summary has no `TOTAL DRC RuleChecks Executed` line"
    if cls["executed"] == 0:
        return NOT_MEASURED, ("0 rulechecks executed. Every count in this report is "
                              "zero because nothing ran, which agrees with every "
                              "budget and measures nothing.")
    if cls["total"] is None:
        return NOT_MEASURED, "the summary has no `TOTAL DRC Results Generated` trailer"
    if cls["total"] > 0 and not cls["checks"]:
        return NOT_MEASURED, (f"{cls['total']} results generated and zero RULECHECK "
                              f"rows parsed from the MAIN section")
    if cls["saturated"] is None:
        return NOT_MEASURED, ("the summary declares no result cap, so no count in "
                              "it can be shown to be un-truncated")
    if cls["saturated"]:
        return NOT_MEASURED, ("%d rulecheck(s) SATURATED the %d-result cap (%s): a "
                              "capped count is not a count."
                              % (len(cls["saturated"]), cls["limit"],
                                 ", ".join(cls["saturated"][:4])))
    tup = ("%s/%s/%s/%s total/reported/non-density/real-geometry"
           % (cls["total"], cls["reported"], cls["non_density"], cls["real_geometry"]))
    rg = cls["real_geometry"]
    if rg is None:
        return NOT_MEASURED, "the real-geometry tier could not be computed"
    if rg > 0:
        return FAIL, ("%d real-geometry result(s): %s  [%s]"
                      % (rg, ", ".join("%s=%d" % kv
                                       for kv in sorted(cls["real_geometry_checks"].items()))[:200],
                         tup))
    return PASS, ("real geometry 0  [%s; %d non-density are dummy-fill markers "
                  "and advisories, density is graded in its own row]"
                  % (tup, cls["non_density"]))


def probe_density(d):
    """PRE-FILL metal density: measured always, gated only against a reference.

    THE ABSOLUTE NUMBER IS NOT OURS. We stream without dummy fill; the foundry
    adds it at merge; imec's post-merge grade of this exact md5 reported no
    density family. So "6,117 core windows short" is the expected state of a
    pre-fill stream and failing on it would send an rc5 loop chasing something
    place-and-route structurally cannot fix.

    A REGRESSION IS OURS. If rc5 is worse than rc4 on the same windows, that is
    a placement or power-plan change eating routing resource, and it is
    actionable now rather than after a merge. So the row's question is the
    comparison, and WITHOUT A REFERENCE IT IS NOT-MEASURED -- named that way so
    the absence of a baseline cannot read as a pass.

    THE POPULATION CONTROL IS THE VALUABLE PART. A density check that silently
    measures nothing is the exact failure this project keeps hitting: 187 of 205
    local BND rulechecks run over empty layers, the DRC gate was blind to
    unmapped layers, and a capped Calibre run writes its truncated value into
    both count fields. So an empty window set is NOT-MEASURED, never clean.
    """
    raw = d.get("density")
    if raw is None:
        return NOT_MEASURED, "no density census: drc_census.py did not run over this rundir"
    if not raw:
        return NOT_MEASURED, ("the rundir holds no *.density file at all. Nothing "
                              "was windowed, so there is no population to be short "
                              "on -- that is not a clean density result.")
    # THE GATED POPULATION IS THE BACK-END ONE, and it is drc_census.py's own
    # split, imported rather than re-derived: front-end OD./PO. windows are
    # artefacts of an abstract-cell stream (PO.DN.2 alone is 22,670 of them) and
    # counting them here would have been a sixth scope in a file written to stop
    # there being a fifth.
    dens = drc_tiers.back_end_density(raw)
    if not dens:
        return NOT_MEASURED, ("%d density file(s), and NOT ONE back-end check has "
                              "a failing window. On a pre-fill stream that is not "
                              "a clean result, it is a census that found nothing "
                              "to measure." % len(raw))
    windows = sum(f for f, _c, _cap in dens.values())
    core = sum(c for _f, c, _cap in dens.values())
    if windows == 0:
        # POPULATION CONTROL. Files present, every one of them empty.
        return NOT_MEASURED, ("%d density file(s) and ZERO window rows in any of "
                              "them. A density check over an empty window set "
                              "agrees with every budget and measures nothing."
                              % len(raw))
    capped = sorted(k for k, (_f, _c, cap) in dens.items() if cap)
    if capped:
        return NOT_MEASURED, ("density output TRUNCATED for %s: a capped window "
                              "count is not a count (set `DRC MAXIMUM RESULTS "
                              "DENSITY ALL` in the deck header)."
                              % ", ".join(capped[:4]))
    base = d.get("density_baseline")
    scope = ("%d core-only failing window(s) of %d, across %d check(s) -- PRE-FILL, "
             "foundry-cleared at merge" % (core, windows, len(dens)))
    if base is None:
        return NOT_MEASURED, (scope + ". NO REFERENCE: the absolute shortfall is "
                              "expected and is not ours to fix, so this row grades "
                              "a REGRESSION and needs a baseline. Pass "
                              "--baseline-drc-run <the previous candidate's "
                              "Calibre rundir>.")
    base = drc_tiers.back_end_density(base)
    worse, gone = [], []
    for k, (_f, c, _cap) in sorted(dens.items()):
        b = base.get(k)
        if b is None:
            if c:
                worse.append("%s +%d (check absent from the reference)" % (k, c))
            continue
        if c > b[1]:
            worse.append("%s %d -> %d (+%d)" % (k, b[1], c, c - b[1]))
    for k in sorted(base):
        if k not in dens:
            gone.append(k)
    base_core = sum(c for _f, c, _cap in base.values())
    delta = core - base_core
    if worse:
        return FAIL, ("density REGRESSED against the reference on %d check(s): %s. "
                      "Total core windows %d -> %d (%+d). An absolute shortfall is "
                      "the foundry's; getting worse is ours."
                      % (len(worse), "; ".join(worse[:4]), base_core, core, delta))
    return PASS, (scope + "; no check is worse than the reference (total core "
                  "%d -> %d, %+d)%s"
                  % (base_core, core, delta,
                     ("; %d check(s) present in the reference and absent here: %s"
                      % (len(gone), ", ".join(gone[:4]))) if gone else ""))


def probe_binding(d):
    """Did every gate read a stream THIS build produced?"""
    want_md5 = d.get("stream_md5")
    want_path = d.get("stream_path")
    build_dir = d.get("build_dir")
    if not want_md5:
        return NOT_MEASURED, f"the graded stream is not on disk: {want_path}"
    seen, foreign, unnamed = [], [], []
    # EACH TOOL NAMES ITS INPUT DIFFERENTLY, and using one regex for all three
    # was the first draft's bug: Calibre LVS writes no `Layout Path(s):` at all
    # -- its LAYOUT NAME is `svdb/<block>.sp`, the EXTRACTED netlist, because LVS
    # compares netlists and not layouts. A single-pattern binder therefore
    # reported LVS as "names no artefact" forever, which is a NOT-MEASURED that
    # looks like a missing report and is a missing pattern. LVS is bound through
    # its run directory instead, and the report below says so rather than
    # implying LVS was md5-bound to the stream when it was not.
    for label, key, pat in (("calibre-drc", "drc_summary", _LAYOUT),
                            ("calibre-antenna", "ant_summary", _LAYOUT),
                            ("calibre-lvs", "lvs_report", _LVS_CWD)):
        txt = d.get(key)
        if txt is None:
            unnamed.append(f"{label}: no report")
            continue
        mo = pat.search(txt)
        if not mo:
            unnamed.append(f"{label}: report names no input path")
            continue
        p = mo.group(1)
        seen.append((label, p))
        if build_dir and not os.path.abspath(p).startswith(os.path.abspath(build_dir) + os.sep):
            foreign.append(f"{label} read {p}, which is not under {build_dir}")
    man = parse_kv(d.get("sta_manifest"))
    db = man.get("sta_db")
    if db is None:
        unnamed.append("tempus: the STA manifest records no sta_db")
    else:
        seen.append(("tempus", db))
        if build_dir and not os.path.abspath(db).startswith(
                os.path.abspath(os.path.dirname(build_dir.rstrip("/"))) + os.sep):
            foreign.append(f"tempus timed {db}, which is outside this build tree")
    if foreign:
        return FAIL, "; ".join(foreign)[:400]
    if unnamed:
        return NOT_MEASURED, ("%d gate(s) name no artefact to bind: %s"
                              % (len(unnamed), "; ".join(unnamed)[:300]))
    # The tier-1 geometry gate must have read the SHIPPED stream itself, byte for
    # byte -- not a sibling of it. LVS deliberately reads the PG-text variant, so
    # it is bound to the build and not to the md5, and that difference is
    # reported rather than smoothed over.
    drc_path = dict(seen).get("calibre-drc")
    if drc_path and os.path.abspath(drc_path) != os.path.abspath(want_path):
        return FAIL, (f"Calibre DRC read {drc_path}, not the graded stream "
                      f"{want_path}")
    return PASS, ("%d gate(s) bound; DRC read the graded stream md5 %s; others "
                  "read siblings under this build (%s)"
                  % (len(seen), want_md5[:12],
                     ", ".join(f"{l}:{os.path.basename(p)}" for l, p in seen)))


def probe_untested(d):
    cov = d.get("coverage")
    if cov is None:
        return NOT_MEASURED, "no analysis_coverage.rpt"
    total, rows = parse_coverage(cov)
    if rows == 0:
        return NOT_MEASURED, "analysis_coverage.rpt parsed zero check-type rows"
    if total == 0:
        return NOT_MEASURED, ("the coverage table reports 0 untested checks over "
                              f"{rows} check types. On this design 169,356 checks "
                              "are PulseWidth alone; a zero here is a report to "
                              "distrust, not a clean sheet.")
    enum = d.get("untested_enum")
    if enum is None:
        return FAIL, (f"{total} untested checks and no enumeration. Run "
                      f"scripts/ci/sta_untested_reasons.tcl. An unattributed "
                      f"untested check cannot be told from one that would fail.")
    counts = parse_untested(enum)
    if not counts:
        return NOT_MEASURED, "the enumeration parsed zero rows"
    got = sum(counts.values())
    if got != total:
        return FAIL, (f"the enumeration accounts for {got} of {total} untested "
                      f"checks; {abs(total - got)} are in neither column")
    unknown = counts.get("unknown", 0)
    mix = ", ".join(f"{k}={v}" for k, v in sorted(counts.items()))
    if unknown:
        return FAIL, f"{unknown} untested check(s) carry no recognised reason ({mix})"
    return PASS, f"{total} untested, all attributed: {mix}"


# ---------------------------------------------------------------------------
# CONTROLS. Each mutates the document set to carry a defect this project has
# actually shipped, and names the answer the probe must then give.
# ---------------------------------------------------------------------------
def mut(d, **kw):
    n = dict(d)
    n.update(kw)
    return n


def _bump_fep(text, to=7):
    """Turn the last column of every summary row into a failing endpoint count."""
    out = []
    for line in (text or "").splitlines():
        mo = _SUMMARY_ROW.match(line)
        out.append(re.sub(r"(\d+)\s*$", str(to), line) if mo else line)
    return "\n".join(out) + "\n"


# A control is (name, how, wanted[, kind]).
#
#   kind "flip"        the mutation carries a defect and the probe MUST return a
#                      different answer. Every row needs at least one, and a row
#                      with none is NOT-MEASURED however green it looked.
#   kind "insensitive" the mutation carries something the row is DELIBERATELY not
#                      about, and the probe must return the SAME answer. These
#                      exist because a rescope that only renames a scope is
#                      indistinguishable from one that changed it: drc-clean must
#                      be provably unmoved by a density-only change, or "density
#                      is graded elsewhere" is a claim and not a fact.
#
# `wanted = None` ON AN INSENSITIVITY CONTROL MEANS "whatever this row said
# unmutated". Writing PASS there instead was wrong and measurably so: against an
# older baseline rc4's density genuinely REGRESSES, the row's true answer is
# FAIL, and an improve-one-check mutation correctly left it FAIL -- whereupon a
# control hard-coded to expect PASS declared the row unable to discriminate. An
# insensitivity control asserts that the answer did not MOVE, which is a
# different statement from asserting what the answer is.
CONTROLS = {
    "setup-closed": [
        ("a failing setup endpoint",
         lambda d: mut(d, timing_summary=_bump_fep(d.get("timing_summary"))), FAIL),
        ("the setup report is gone",
         lambda d: mut(d, timing_summary=None), NOT_MEASURED),
        ("the run never finished",
         lambda d: mut(d, sta_manifest=(d.get("sta_manifest") or "").replace(
             "sta_finished", "sta_x")), NOT_MEASURED),
    ],
    "hold-closed": [
        ("a failing hold endpoint at one required view", "hold_view_fail", FAIL),
        ("one required hold view silently dropped", "hold_view_drop", FAIL),
        ("a required view is active but wrote no report", "hold_view_blind",
         NOT_MEASURED),
    ],
    "drc-clean": [
        # THE ONE THAT MATTERS AFTER THE RESCOPE. A real-geometry violation is a
        # non-density, non-dummy-fill rulecheck with a non-zero count -- exactly
        # the class a place-and-route iteration can introduce and fix.
        ("a real-geometry violation appears", "drc_real_violation", FAIL),
        # THE RESCOPE ITSELF, ASSERTED. Density moved out of this row; a
        # density-only change must therefore move nothing here. If this control
        # ever flips, density has crept back into the hard verdict.
        ("a density-only violation must NOT move this row", "drc_density_only",
         None, "insensitive"),
        ("the result cap header is missing", "drc_nocap", NOT_MEASURED),
        ("a rulecheck saturated its cap", "drc_saturate", NOT_MEASURED),
        ("zero rulechecks executed", "drc_zero", NOT_MEASURED),
        ("a waiver does not match what it claims", "drc_waiver_bad", NOT_MEASURED),
    ],
    "density-pre-fill": [
        # THE POPULATION CONTROL. Files present, every one empty -- a density
        # check that measured nothing, which is the failure mode this project
        # keeps hitting and the reason this row is worth having at all.
        ("every density file is empty", "dens_empty", NOT_MEASURED),
        ("the rundir holds no density file at all", "dens_no_files", NOT_MEASURED),
        ("a check gets WORSE than the reference", "dens_regress", FAIL),
        # A row that failed on any change would be a regression detector in name
        # only, and on a pre-fill stream it would be red forever.
        ("a check gets BETTER than the reference must not make it worse",
         "dens_improve", None, "insensitive"),
        ("density output was truncated", "dens_capped", NOT_MEASURED),
        ("no reference to compare against", "dens_no_baseline", NOT_MEASURED),
    ],
    "stream-binding": [
        ("a gate read another build's stream", "bind_foreign", FAIL),
        ("a gate's report names no layout path", "bind_unnamed", NOT_MEASURED),
    ],
    "untested-attributed": [
        ("an untested check carries an unrecognised reason", "unt_unknown", FAIL),
        ("the enumeration is short of its own total", "unt_short", FAIL),
        ("the enumeration is gone", "unt_gone", FAIL),
        ("the coverage table cannot be read", "unt_blind", NOT_MEASURED),
    ],
}


def _inject_rulecheck(text, name, n):
    """Add a RULECHECK row to the MAIN section, and move the trailer with it."""
    # ANCHOR ON A LINE START. `"RULECHECK "` occurs INSIDE the section header
    # itself ("--- RULECHECK RESULTS STATISTICS"), so searching for the bare word
    # inserted the line into the middle of the header, destroyed it, and left
    # main_section() finding only the BY CELL section -- the control then read
    # PASS and reported "this row cannot fail". Caught by the control's own
    # wanted/got, which is the argument for declaring what a control must return
    # rather than just running it.
    marker = "--- RULECHECK RESULTS STATISTICS"
    i = text.index(marker)
    j = text.index("\nRULECHECK ", i) + 1
    line = "RULECHECK %s %s TOTAL Result Count = %d   (%d)\n" % (
        name, "." * max(1, 40 - len(name)), n, n)
    out = text[:j] + line + text[j:]
    return re.sub(r"^(TOTAL DRC Results Generated:\s+)(\d+)",
                  lambda mo: mo.group(1) + str(int(mo.group(2)) + n),
                  out, count=1, flags=re.M)


def _dens(d, fn):
    """Rebuild the density census through fn(check, failing, core, capped)."""
    src = d.get("density") or {}
    return mut(d, density={k: fn(k, *v) for k, v in src.items()})


def apply_named_mutation(name, d, required):
    if name == "hold_view_fail":
        # Flip the WORST path of the LAST required view to VIOLATED. The last one
        # deliberately: av_ltfix_libset_hold is the corner that measured -0.159
        # on three RMII transmit endpoints and is invisible in the aggregate row,
        # so a control that only ever mutated the default view would prove the
        # gate can see the corner it never needed help seeing.
        v = required[-1]
        txt = d.get("hold_view:" + v) or ""
        return mut(d, **{"hold_view:" + v: _PATH.sub(
            lambda mo: "Path 1: VIOLATED (-0.159 ns)", txt, count=1)})
    if name == "hold_view_drop":
        man = d.get("sta_manifest") or ""
        return mut(d, sta_manifest=re.sub(
            r"^(analysis_views_hold = ).*$",
            lambda mo: mo.group(1) + required[0], man, flags=re.M))
    if name == "hold_view_blind":
        return mut(d, **{"hold_view:" + required[-1]: None})
    if name == "drc_real_violation":
        # M3.S.1 is a metal spacing rule: not `.DN.`, not a dummy-fill marker,
        # not advisory -- so it lands in tier 4 and nothing else.
        return mut(d, drc_summary=_inject_rulecheck(d.get("drc_summary") or "",
                                                    "M3.S.1", 3))
    if name == "drc_density_only":
        # Bump an existing density rulecheck by 500. Tier 4 must not move.
        return mut(d, drc_summary=re.sub(
            r"^(RULECHECK \S+\.DN\.\S* \.+ TOTAL Result Count = )(\d+)",
            lambda mo: mo.group(1) + str(int(mo.group(2)) + 500),
            d.get("drc_summary") or "", count=1, flags=re.M))
    if name == "drc_waiver_bad":
        return mut(d, drc_waiver_problems=True,
                   drc_waiver_detail="fixture: a waiver claims a cell that is "
                                     "not in the BY CELL section")
    if name == "dens_empty":
        return _dens(d, lambda k, f, c, cap: (0, 0, cap))
    if name == "dens_no_files":
        return mut(d, density={})
    # EVERY DENSITY MUTATION PICKS ITS TARGET FROM THE BACK-END POPULATION, which
    # is the population the row grades. The first cut picked the largest check in
    # the RAW census -- PO.DN.2, 22,670 windows -- which is front-end, which the
    # probe filters out, so three controls mutated something the row is designed
    # not to see and reported it as "this row cannot fail". A control that
    # perturbs the wrong population is not a weaker control, it is a false one.
    if name in ("dens_capped", "dens_regress", "dens_improve"):
        be = drc_tiers.back_end_density(d.get("density") or {})
        if not be:
            return mut(d, density={})            # nothing to perturb; row is blind anyway
        if name == "dens_capped":
            k0 = sorted(be)[0]
            return _dens(d, lambda k, f, c, cap: (f, c, True if k == k0 else cap))
        k0 = max(be, key=lambda k: be[k][1])
        if name == "dens_regress":
            return _dens(d, lambda k, f, c, cap:
                         (f + 25, c + 25, cap) if k == k0 else (f, c, cap))
        return _dens(d, lambda k, f, c, cap:
                     (max(0, f - 25), max(0, c - 25), cap) if k == k0 else (f, c, cap))
    if name == "dens_no_baseline":
        return mut(d, density_baseline=None)
    if name == "drc_nocap":
        return mut(d, drc_summary=re.sub(r"^Maximum Results/RuleCheck:.*$", "",
                                         d.get("drc_summary") or "", flags=re.M))
    if name == "drc_saturate":
        t = d.get("drc_summary") or ""
        cap = _CAP.search(t)
        n = cap.group(1) if cap else "100000"
        return mut(d, drc_summary=re.sub(
            r"^(RULECHECK\s+\S+\s*\.*\s*TOTAL Result Count\s*=\s*)\d+",
            lambda mo: mo.group(1) + n, t, count=1, flags=re.M))
    if name == "drc_zero":
        return mut(d, drc_summary=re.sub(
            r"^(TOTAL DRC RuleChecks Executed:\s*)\d+", r"\g<1>0",
            d.get("drc_summary") or "", flags=re.M))
    if name == "bind_foreign":
        return mut(d, drc_summary=re.sub(
            r"^(Layout Path\(s\):\s*).*$",
            r"\g<1>/somewhere/else/build/full-20260814/outputs/x.gds",
            d.get("drc_summary") or "", flags=re.M))
    if name == "bind_unnamed":
        return mut(d, ant_summary=re.sub(r"^Layout Path\(s\):.*$", "",
                                         d.get("ant_summary") or "", flags=re.M))
    if name == "unt_unknown":
        return mut(d, untested_enum=re.sub(
            r"UNTESTED(\s+)False Path", r"UNTESTED\1Reason Tempus Invented",
            d.get("untested_enum") or "", count=1))
    if name == "unt_short":
        lines = (d.get("untested_enum") or "").splitlines()
        keep = [l for l in lines if not _UNTESTED_ROW.match(l)][:20]
        rows = [l for l in lines if _UNTESTED_ROW.match(l)]
        return mut(d, untested_enum="\n".join(keep + rows[:-1]) + "\n")
    if name == "unt_gone":
        return mut(d, untested_enum=None)
    if name == "unt_blind":
        return mut(d, coverage="Analysis Coverage Report\n  (no data)\n")
    raise KeyError(name)


# ---------------------------------------------------------------------------
def collect(args):
    """Read every artefact once. Returns (docs, notes)."""
    tag = args.build_tag
    build_root = Path(args.build_root)
    build = build_root / tag
    notes = []
    d = {"build_dir": str(build), "build_tag": tag}

    stream = Path(args.stream) if args.stream else None
    if stream is None:
        # A build writes several streams (the shipped one, an LVS PG-text
        # variant, a pre-logo one). Prefer the exact conventional name, then a
        # _logo one, and REFUSE to choose between equals rather than guess.
        outs = sorted((build / "outputs").glob("*.gds")) if (build / "outputs").is_dir() else []
        exact = [p for p in outs if p.name == f"{BLOCK}.gds"]
        logo = [p for p in outs if p.name.endswith("_logo.gds")]
        cand = exact or logo or [p for p in outs if "_lvs" not in p.name]
        if len(cand) == 1:
            stream = cand[0]
        elif len(cand) > 1:
            notes.append("REFUSING TO CHOOSE a stream: %d candidates under %s "
                         "(%s). Pass --stream." %
                         (len(cand), build / "outputs",
                          ", ".join(p.name for p in cand)))
        else:
            notes.append(f"no .gds under {build}/outputs")
    d["stream_path"] = str(stream) if stream else None
    d["stream_md5"] = md5_of(stream) if stream and stream.is_file() else None

    rep = Path(args.sta_reports) if args.sta_reports else ROOT / "ASIC/sta/work" / tag / "reports"
    d["sta_reports"] = str(rep)
    d["sta_manifest"] = read(rep / "sta_manifest.txt")
    d["timing_summary"] = read(rep / "timing_summary.rpt")
    d["timing_summary_hold"] = read(rep / "timing_summary_hold.rpt")
    d["coverage"] = read(rep / "analysis_coverage.rpt")
    d["untested_enum"] = read(rep / "analysis_coverage_untested.rpt")
    required = list(args.hold_views)
    for v in required:
        d["hold_view:" + v] = read(rep / f"timing_hold_{v}.rpt")

    drc = Path(args.drc_run) if args.drc_run else build / "work" / "drc_run"
    d["drc_run"] = str(drc)
    sp = drc_tiers.summary_path(str(drc)) if drc.is_dir() else None
    d["drc_summary"] = read(sp) if sp else None
    if d["drc_summary"] is not None:
        # drc_census is still run, but its EXIT STATUS is no longer the verdict:
        # it folds density into that rc, and density is a different question
        # (see probe_drc). What is taken from it is the waived figure the tiers
        # subtract and its waiver-consistency finding, both of which are about
        # the rulecheck scope this row does grade.
        pr = subprocess.run([sys.executable, str(HERE / "drc_census.py"), str(drc)],
                            capture_output=True, text=True, cwd=str(ROOT),
                            stdin=subprocess.DEVNULL, timeout=1800)
        out = (pr.stdout or "") + (pr.stderr or "")
        d["drc_census_rc"] = pr.returncode
        d["drc_census_out"] = out
        mo = re.search(r"less waived\s+:\s+(\d+)", out)
        d["drc_waived"] = int(mo.group(1)) if mo else None
        mo = re.search(r"FAIL: (\d+) waiver problem\(s\)", out)
        d["drc_waiver_problems"] = bool(mo)
        d["drc_waiver_detail"] = mo.group(0) if mo else ""
        try:
            d["density"], d["die_box"] = drc_tiers.density_windows(
                str(drc), args.pad_inset)
        except Exception as e:                                # noqa: BLE001
            notes.append("density census failed on %s: %r" % (drc, e))
            d["density"] = None
    base = args.baseline_drc_run or os.environ.get("RC5_DENSITY_BASELINE") or ""
    if base.strip():
        if not Path(base).is_dir():
            notes.append("--baseline-drc-run %s is not a directory; the density "
                         "row will render NOT-MEASURED rather than skip its "
                         "comparison" % base)
        else:
            try:
                d["density_baseline"], _ = drc_tiers.density_windows(
                    base, args.pad_inset)
                d["density_baseline_run"] = base
            except Exception as e:                            # noqa: BLE001
                notes.append("baseline density census failed on %s: %r" % (base, e))
    ant = Path(args.antenna_run) if args.antenna_run else None
    if ant is None:
        cands = sorted((ROOT / "ASIC/genus-innovus/calibre_runs").glob(f"ant_*{tag.split('-')[0]}*"))
        ant = cands[0] if len(cands) == 1 else None
    d["ant_summary"] = read(ant / f"{BLOCK}.ant.summary") if ant else None
    lvs = Path(args.lvs_report) if args.lvs_report else build / "lvs_run" / f"{BLOCK}.lvs.rep"
    t = read(lvs)
    # LVS reports run to megabytes; only the header carries the Layout Path.
    d["lvs_report"] = "\n".join((t or "").splitlines()[:80]) if t else None
    return d, notes


def grade(d, required):
    rows = [
        ("setup-closed", "did setup close?", lambda x: probe_setup(x)),
        ("hold-closed", "did hold close at all %d required views?" % len(required),
         lambda x: probe_hold(x, required)),
        ("drc-clean", "is Calibre DRC clean on the scope this flow owns?",
         lambda x: probe_drc(x)),
        ("density-pre-fill",
         "is pre-fill metal density no worse than the reference?",
         lambda x: probe_density(x)),
        ("stream-binding", "did every gate read THIS run's stream?",
         lambda x: probe_binding(x)),
        ("untested-attributed",
         "is every untested timing check attributed to a reason?",
         lambda x: probe_untested(x)),
    ]
    out = []
    for rid, question, probe in rows:
        verdict, detail = probe(d)
        controls, blind = [], []
        n_flip_ok = n_flip = 0
        for spec in CONTROLS[rid]:
            cname, how, wanted = spec[0], spec[1], spec[2]
            kind = spec[3] if len(spec) > 3 else "flip"
            try:
                mutated = how(d) if callable(how) else apply_named_mutation(how, d, required)
                cv, cd = probe(mutated)
            except Exception as e:                            # noqa: BLE001
                cv, cd = "ERROR", repr(e)
            want = verdict if (kind == "insensitive" and wanted is None) else wanted
            ok = (cv == want)
            if kind == "flip":
                n_flip += 1
                n_flip_ok += 1 if ok else 0
            controls.append({"control": cname, "kind": kind, "wanted": want,
                             "got": cv, "flipped": ok, "detail": cd[:200]})
            if not ok:
                blind.append(f"{cname}: wanted {want}, got {cv}")
        # AN INSENSITIVITY CONTROL IS NOT EVIDENCE OF DISCRIMINATION. A row whose
        # only satisfied controls are the ones asserting it does NOT react has
        # been shown to be inert, not to be a gate.
        if n_flip_ok == 0:
            blind.append("no control of kind `flip` returned the other answer "
                         f"({n_flip} declared) — nothing shows this row can "
                         "change its mind")
        if blind:
            # A row whose control did not flip has not been shown to measure
            # anything, whatever it said. The ANSWER is kept beside the
            # verdict so the reader can see what was overridden and why.
            out.append({"id": rid, "question": question,
                        "verdict": NOT_MEASURED,
                        "detail": ("the check could not be shown to discriminate: "
                                   + "; ".join(blind)),
                        "answer_if_trusted": verdict, "answer_detail": detail,
                        "controls": controls})
        else:
            out.append({"id": rid, "question": question, "verdict": verdict,
                        "detail": detail, "controls": controls})
    return out


PREFLIGHT = [
    # Ordered cheapest-first, and every one of them is BLOCKING. A harness that
    # cannot be shown to discriminate cannot grade a candidate; running the rows
    # anyway would produce exactly the kind of green this file exists to prevent.
    ("mutation-coverage", [sys.executable, "scripts/ci/check_mutation_coverage.py"]),
    ("manifest-lint", [sys.executable, "scripts/ci/signoff.py", "lint"]),
    ("build-freshness", [sys.executable, "scripts/ci/build_freshness.py"]),
    # ONLINE, NOT --offline. Against a stale remote-tracking cache the only sound
    # verdict for "not an ancestor of any ref" is UNVERIFIED -- it cannot tell
    # "never pushed" from "pushed since this cache was written" -- and an
    # unanswerable question is not a pass. Costs a fetch of 44 submodules,
    # measured at about three minutes.
    ("pins-reachable", ["ASIC/asic-toolkit/ci/check-pins.sh"]),
    ("vacuous-gates", ["scripts/ci/vacuity_scan.sh"]),
    ("vendor-collateral", ["scripts/ci/check_no_vendor_collateral.sh"]),
    ("gates-can-fail", [sys.executable, "scripts/ci/signoff.py", "prove"]),
]


def preflight(args):
    """Run the blocking pre-flight. -> (ok, rows)."""
    rows = []
    env = dict(os.environ)
    env["SIGNOFF_GRADED_BUILD"] = args.build_tag
    env["SIGNOFF_BUILD_ROOT"] = str(args.build_root)
    # The toolkit's ci/lib.sh defaults its verdict directory to <tree>/ci-verdicts,
    # so check-pins.sh writes into the REPOSITORY ROOT unless told otherwise --
    # untracked clutter in a tree several sessions are committing from, and one
    # more thing for a `git add -A` to sweep up. Pinned under build/, which is
    # gitignored, and per-lane so two lanes cannot truncate each other's evidence.
    env.setdefault("CI_VERDICT_DIR", str(ROOT / "build" / "ci-verdicts"))
    for name, cmd in PREFLIGHT:
        # THE VENDOR GUARD'S VERBATIM-TEXT HALF SILENTLY SKIPS WITHOUT
        # $TSMC_65_HOME AND THE SCRIPT STILL EXITS 0 -- a documented instance of
        # exactly the class this harness exists to catch. So the step is BLOCKED
        # rather than run when the variable is unset: a green from a check that
        # skipped half of itself is worse than no check.
        #
        # The value is NOT written here. It is a site path, this repository is
        # public, and hardcoding one is what scripts/ci/check_no_vendor_collateral.sh
        # itself refuses -- it blocked this very commit for that line. Export it.
        if name == "vendor-collateral" and not env.get("TSMC_65_HOME", "").strip():
            rows.append({"id": name, "rc": 1, "seconds": 0.0, "verdict": "BLOCKED",
                         "detail": "TSMC_65_HOME is unset. The guard's "
                                   "verbatim-text half silently skips without it "
                                   "and still exits 0, so this would be a green "
                                   "from a check that ran half of itself. Export "
                                   "it (the site value is in ASIC/sta/site.env's "
                                   "neighbourhood, not in this repository)."})
            continue
        if name in args.skip_preflight:
            rows.append({"id": name, "rc": None, "verdict": "SKIPPED",
                         "detail": "skipped by --skip-preflight"})
            continue
        t0 = time.time()
        try:
            p = subprocess.run(cmd, cwd=str(ROOT), env=env, capture_output=True,
                               text=True, stdin=subprocess.DEVNULL,
                               timeout=args.preflight_timeout)
            rc, out = p.returncode, (p.stdout or "") + (p.stderr or "")
        except FileNotFoundError as e:
            rc, out = 127, str(e)
        except subprocess.TimeoutExpired:
            rc, out = 124, f"timed out after {args.preflight_timeout}s"
        last = [l for l in out.strip().splitlines() if l.strip()]
        rows.append({"id": name, "rc": rc, "seconds": round(time.time() - t0, 1),
                     "verdict": "ok" if rc == 0 else "BLOCKED",
                     "detail": (last[-1][:200] if last else "(no output)")})
    return all(r["rc"] == 0 for r in rows if r["rc"] is not None), rows


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--build-tag", default=os.environ.get("SIGNOFF_GRADED_BUILD"),
                    help="the build under judgement. NO DEFAULT; also read from "
                         "$SIGNOFF_GRADED_BUILD.")
    ap.add_argument("--build-root",
                    default=os.environ.get("SIGNOFF_BUILD_ROOT")
                    or str(ROOT / "ASIC/eth-chiplet/build"))
    ap.add_argument("--stream", help="the GDS under judgement (default: this build's)")
    ap.add_argument("--sta-reports", help="default ASIC/sta/work/<tag>/reports")
    ap.add_argument("--drc-run", help="default <build>/work/drc_run")
    ap.add_argument("--antenna-run")
    ap.add_argument("--baseline-drc-run",
                    help="the PREVIOUS candidate's Calibre rundir. Pre-fill "
                         "metal density is graded as a REGRESSION against it, "
                         "never as an absolute: we do not ship the dummy fill, "
                         "the foundry adds it at merge, and imec's post-merge "
                         "grade of this lineage reports no density family at "
                         "all. Without it the density row is NOT-MEASURED, "
                         "which is the honest answer and not a skip. Also read "
                         "from $RC5_DENSITY_BASELINE.")
    ap.add_argument("--pad-inset", type=float, default=135.0,
                    help="pad band excluded from the CORE window count "
                         "(default 135 um, drc_census.py's own default)")
    ap.add_argument("--lvs-report")
    ap.add_argument("--hold-views", nargs="+", default=None,
                    help="required hold views (default: from ASIC/sta/sta_policy.json)")
    ap.add_argument("--json", help="write the machine-readable verdict here too")
    ap.add_argument("--skip-preflight", nargs="*", default=None,
                    metavar="STEP", help="pre-flight steps to skip; bare flag "
                    "skips ALL and is recorded in the output as having done so")
    ap.add_argument("--preflight-timeout", type=int, default=2400)
    args = ap.parse_args()

    if not args.build_tag:
        print("rc5-grade: --build-tag is required and has NO DEFAULT. A default "
              "is how thirteen signoff stages came to grade a die from 23 August "
              "while rendering green.", file=sys.stderr)
        return 3
    # `--skip-preflight` bare means all of them; with names, just those. Either
    # way the skip is RECORDED in the json as a SKIPPED row rather than omitted,
    # because a pre-flight nobody ran and a pre-flight that passed must not
    # render the same.
    if args.skip_preflight is None:
        args.skip_preflight = []
    elif not args.skip_preflight:
        args.skip_preflight = [n for n, _ in PREFLIGHT]
    unknown = [s for s in args.skip_preflight if s not in {n for n, _ in PREFLIGHT}]
    if unknown:
        print("rc5-grade: --skip-preflight names no such step: %s. Known: %s"
              % (", ".join(unknown), ", ".join(n for n, _ in PREFLIGHT)),
              file=sys.stderr)
        return 3

    if args.hold_views is None:
        try:
            pol = json.loads((ROOT / "ASIC/sta/sta_policy.json").read_text())
            args.hold_views = pol.get("required_hold_views") or DEFAULT_HOLD_VIEWS
        except Exception:                                      # noqa: BLE001
            args.hold_views = DEFAULT_HOLD_VIEWS

    t0 = time.time()
    pf_ok, pf_rows = preflight(args)
    d, notes = collect(args)
    rows = grade(d, args.hold_views)

    nfail = sum(1 for r in rows if r["verdict"] == FAIL)
    nun = sum(1 for r in rows if r["verdict"] == NOT_MEASURED)
    verdict = (PASS if not nfail and not nun else
               (NOT_MEASURED if nun else FAIL))
    if not pf_ok:
        verdict = "PREFLIGHT-BLOCKED"

    print(f"rc5-grade  build={args.build_tag}  "
          f"stream={os.path.basename(d.get('stream_path') or '-')}  "
          f"md5={(d.get('stream_md5') or '-')[:12]}")
    print(f"{'PRE-FLIGHT':<22}{'':<14}{'':<10}")
    for r in pf_rows:
        print(f"  {r['id']:<20}{r['verdict']:<14}{'':<10}{r['detail'][:80]}")
    print(f"{'ROW':<22}{'VERDICT':<14}{'CONTROL':<10}DETAIL")
    for r in rows:
        n_ok = sum(1 for c in r["controls"] if c["flipped"])
        print(f"  {r['id']:<20}{r['verdict']:<14}{n_ok}/{len(r['controls']):<8}"
              f"{r['detail'][:96]}")
        if r["verdict"] == NOT_MEASURED and "answer_if_trusted" in r:
            print(f"  {'':<20}{'':<14}{'':<10}(it said {r['answer_if_trusted']}: "
                  f"{r['answer_detail'][:70]})")
    for n in notes:
        print(f"  note: {n}")
    print(f"VERDICT: {verdict}  ({nfail} fail, {nun} not-measured, "
          f"{sum(1 for r in rows for c in r['controls'] if not c['flipped'])} "
          f"blind control(s), {round(time.time() - t0)}s)")

    doc = {"schema": "soclabs.rc5-grade/1", "build_tag": args.build_tag,
           "build_root": str(args.build_root),
           "stream": d.get("stream_path"), "stream_md5": d.get("stream_md5"),
           "sta_reports": d.get("sta_reports"), "drc_run": d.get("drc_run"),
           "density_baseline_run": d.get("density_baseline_run"),
           "required_hold_views": args.hold_views,
           "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
           "preflight": pf_rows, "preflight_ok": pf_ok,
           "rows": rows, "notes": notes, "verdict": verdict}
    out = Path(args.json) if args.json else (
        ROOT / "build" / "rc5-grade" / f"{args.build_tag}.json")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(doc, indent=2) + "\n")
    print(f"json: {out}")

    if not pf_ok:
        return 3
    if nun:
        return 2
    if nfail:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
