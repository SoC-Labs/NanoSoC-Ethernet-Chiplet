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
    txt = d.get("drc_summary")
    if txt is None:
        return NOT_MEASURED, "no <block>.drc.summary: Calibre DRC has not run on this build"
    cap = _CAP.search(txt)
    if not cap:
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
    capn = int(cap.group(1))
    ex = _EXECUTED.search(txt)
    if not ex:
        return NOT_MEASURED, "the summary has no `TOTAL DRC RuleChecks Executed` line"
    if int(ex.group(1)) == 0:
        return NOT_MEASURED, ("0 rulechecks executed. Every count in this report is "
                              "zero because nothing ran, which agrees with every "
                              "budget and measures nothing.")
    rows = _RULECHECK.findall(txt)
    if not rows:
        return NOT_MEASURED, f"{ex.group(1)} rulechecks executed and zero RULECHECK rows parsed"
    sat = sorted(n for n, c in rows if int(c) >= capn)
    if sat:
        return NOT_MEASURED, ("%d rulecheck(s) SATURATED the %d-result cap (%s): a "
                              "capped count is not a count."
                              % (len(sat), capn, ", ".join(sat[:4])))
    rc = d.get("drc_census_rc")
    if rc is None:
        return NOT_MEASURED, "scripts/ci/drc_census.py did not run"
    verdict = (d.get("drc_census_out") or "").strip().splitlines()
    tail = [l for l in verdict if l.startswith(("FAIL:", "PASS:"))]
    if not tail:
        return NOT_MEASURED, "drc_census printed no PASS:/FAIL: verdict line"
    if rc != 0:
        return FAIL, "; ".join(l.strip() for l in tail)[:300]
    nonzero = sum(1 for _n, c in rows if int(c) > 0)
    return PASS, ("%s  [%d of %d rulechecks non-zero, cap %d, none saturated]"
                  % (tail[0].strip()[:180], nonzero, len(rows), capn))


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
        ("the census reports a design-owned violation", "drc_inject", FAIL),
        ("the result cap header is missing", "drc_nocap", NOT_MEASURED),
        ("a rulecheck saturated its cap", "drc_saturate", NOT_MEASURED),
        ("zero rulechecks executed", "drc_zero", NOT_MEASURED),
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
    if name == "drc_inject":
        t = d.get("drc_summary") or ""
        return mut(d, drc_summary=t, drc_census_rc=1,
                   drc_census_out="FAIL: 1 design-owned results > budget 0.")
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
    d["drc_summary"] = read(drc / f"{BLOCK}.drc.summary")
    if d["drc_summary"] is not None:
        p = subprocess.run([sys.executable, str(HERE / "drc_census.py"), str(drc)],
                           capture_output=True, text=True, cwd=str(ROOT),
                           stdin=subprocess.DEVNULL, timeout=1800)
        d["drc_census_rc"] = p.returncode
        d["drc_census_out"] = (p.stdout or "") + (p.stderr or "")
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
        ("drc-clean", "is Calibre DRC clean?", lambda x: probe_drc(x)),
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
        for spec in CONTROLS[rid]:
            cname, how, wanted = spec
            try:
                mutated = how(d) if callable(how) else apply_named_mutation(how, d, required)
                cv, cd = probe(mutated)
            except Exception as e:                            # noqa: BLE001
                cv, cd = "ERROR", repr(e)
            ok = (cv == wanted)
            controls.append({"control": cname, "wanted": wanted, "got": cv,
                             "flipped": ok, "detail": cd[:200]})
            if not ok:
                blind.append(f"{cname}: wanted {wanted}, got {cv}")
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
