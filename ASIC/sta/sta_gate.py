#!/usr/bin/env python3
"""
Signoff-STA gate for nanosoc_eth_chiplet_pads.

WHY THIS EXISTS IN THIS SHAPE
-----------------------------
Four gates were found on this project that could not fail. The failure modes
were all the same family:

  * the gate checked internal consistency and never checked COVERAGE, so it
    read 20/20 green while 16 of 33 clocks were never analysed at all;
  * the budget was set to whatever the day's number happened to be, so the
    gate could only ever confirm the present;
  * an unparseable or missing report was treated as "nothing to complain
    about" rather than as a failure.

So this gate is built to the opposite rules, and they are enforced by
`--selftest`, which mutates a known-good artefact set one property at a time
and asserts the gate rejects every mutant. A gate that has not been shown to
fail has not been shown to do anything.

RULES
  R1  Missing, empty or unparseable evidence is a FAILURE, never a pass.
  R2  Budgets come from an explicit, committed policy (--policy), never from
      the run being judged. A budget equal to the measured value is itself
      reported, because that is the signature of a budget back-fitted to the
      day's number.
  R3  Coverage is checked separately from quality. "All analysed paths pass"
      is worthless if half the design was not analysed.
  R4  The tool's exit code is never consulted. Only artefacts.

USAGE
  sta_gate.py --reports ASIC/sta/reports [--policy ASIC/sta/sta_policy.json]
  sta_gate.py --selftest
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

# ---------------------------------------------------------------------------
# Policy defaults.
#
# These are ACCEPTANCE THRESHOLDS, not observations. They are deliberately set
# to what a signed-off chip must satisfy (zero failing endpoints), NOT to the
# design's current state (setup FEP ~1429-1444). The gate is therefore
# expected to FAIL on today's design, and that is correct behaviour: the
# design does not close timing. A gate tuned to pass today would be the fifth
# gate that cannot discriminate.
# ---------------------------------------------------------------------------
DEFAULT_POLICY = {
    "setup_fep_budget": 0,
    "hold_fep_budget": 0,
    # CLOCK COVERAGE. Two numbers, and they do not measure the same thing.
    #
    # expected_sdc_clock_count is the PINNED quantity and the only one a run is
    # graded against: how many clocks the SDC defines. 26 since commit 153025c
    # deleted seven D2D_TX_WORD_CLK declarations that never resolved a master.
    # `get_db clocks` returns one object per SDC clock PER DISTINCT ACTIVE
    # ANALYSIS VIEW, so the gate cross-foots
    #     clock_count == expected_sdc_clock_count * |active setup U active hold|
    # using the view lists the same manifest records.
    #
    # DISTINCT, NOT "setup entries + hold entries". A view named in BOTH roles
    # is ONE view and contributes ONE set of clock objects. This matters here:
    # the project mmmc's own set_analysis_view line names typical_analysis_view
    # in both lists. MEASURED 2026-09-01, Tempus 21.11, read-only copy of
    # rc6full-20260831's routed database:
    #     setup{A}      hold{B,C,D}        4 distinct -> 104
    #     setup{A,E}    hold{B,C,D,E}      5 distinct -> 130   <- 6 list entries
    #     setup{A,E}    hold{B,C,D}        5 distinct -> 130   <- 5 list entries
    #     setup{A,E,F}  hold{B,C,D,G}      7 distinct -> 182
    # The middle pair is the falsifying one: six list entries and five list
    # entries give the SAME count, so the count follows distinct views.
    "expected_sdc_clock_count": 26,
    #
    # expected_clock_count grades THIS POLICY, not a run. It must equal
    # expected_sdc_clock_count * the number of distinct views the two
    # required_*_views lists name, and the gate says POLICY_INCONSISTENT if it
    # does not -- so an editor who lengthens required_hold_views and forgets
    # this number gets told the rule instead of a mystery CLOCK_COUNT on every
    # subsequent run. It is NOT compared against a run's clock_count: doing
    # that made the required-view lists a CEILING as well as a floor, which
    # contradicts their own documentation, because a run that activates a
    # sixth view reports 156 and would have failed.
    "expected_clock_count": 104,
    # The untested population is gated on `unknown`, NEVER on the total: see
    # parse_untested_reasons(). None disables the arm; 0 is the requirement.
    "untested_unknown_budget": 0,
    "require_qrc_all_rc_corners": True,
    "require_spef_min_bytes": 1_000_000,
    "require_cppr": "both",
    "require_analysis_type": "ocv",
    "require_derate": {
        "derate_data_early": 0.95,
        "derate_data_late": 1.05,
        "derate_clk_early": 0.97,
        "derate_clk_late": 1.03,
    },
    # Signing off on one setup corner and one hold corner is a decision, not a
    # default. Named here so that if the view set silently shrinks, the gate
    # notices. Empty list disables the check.
    "required_setup_views": ["default_analysis_view_setup"],
    # Three hold views, matching ASIC/sta/sta_policy.json. Listing only
    # default_analysis_view_hold let a run drop the two corners that produced
    # this tapeout's worst hold findings -- av_ml_libset_hold (FF/1.32V/125C)
    # measured -0.078 on 22 endpoints and av_ltfix_libset_hold (PVT-corrected
    # -40C IO) measured -0.159 on 3 -- and still clear the gate. A hold corner
    # you do not activate reports nothing, and nothing is indistinguishable
    # from passing. This built-in default is the one a caller gets with no
    # --policy, so it must not be weaker than the file.
    "required_hold_views": [
        "default_analysis_view_hold",
        "av_ml_libset_hold",
        "av_ltfix_libset_hold",
    ],
}


class Result:
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


def parse_manifest(path, r):
    """Manifest is `key = value` per line. Missing file is fatal (R1)."""
    if not os.path.isfile(path):
        r.fail("MANIFEST_MISSING", f"no manifest at {path}")
        return {}
    m = {}
    with open(path, errors="replace") as fh:
        for line in fh:
            if "=" not in line:
                continue
            k, _, v = line.partition("=")
            m[k.strip()] = v.strip()
    if not m:
        r.fail("MANIFEST_EMPTY", f"manifest parsed to zero keys: {path}")
    return m


# Matches the "View : ALL   -0.715  -354.123  1429" summary rows that Innovus
# and Tempus both emit, and the "WNS (ns): / Violating Paths:" table form.
_ROW = re.compile(
    r"^\s*View\s*:\s*(?P<view>\S+)\s+"
    r"(?P<wns>-?\d+\.\d+)\s+(?P<tns>-?\d+\.\d+)\s+(?P<fep>\d+)\s*$"
)


def parse_timing_summary(path, r, want=("setup", "hold")):
    """
    Return {'setup': (wns,fep), 'hold': (wns,fep)} or {} on failure.
    `want` names the sections this particular file is required to contain.

    Unparseable is a FAILURE (R1). This is the exact spot where a gate can
    quietly become a no-op: if the report format shifts by one column and the
    regex stops matching, "no violations found" and "no data found" look
    identical unless you insist on positive evidence.
    """
    if not os.path.isfile(path):
        r.fail("SUMMARY_MISSING", f"no timing summary at {path}")
        return {}
    text = open(path, errors="replace").read()
    if not text.strip():
        r.fail("SUMMARY_EMPTY", f"timing summary is empty: {path}")
        return {}

    out = {}
    section = None
    for line in text.splitlines():
        s = line.strip()
        up = s.upper()
        if up.startswith("# SETUP") or up.startswith("SETUP MODE"):
            section = "setup"
            continue
        if up.startswith("# HOLD") or up.startswith("HOLD MODE"):
            section = "hold"
            continue
        if up.startswith("# DRV"):
            section = "drv"
            continue
        if section in ("setup", "hold"):
            mo = _ROW.match(line)
            if mo and mo.group("view").upper() == "ALL":
                out[section] = (float(mo.group("wns")), int(mo.group("fep")))

    for want_sec in want:
        if want_sec not in out:
            r.fail(
                "SUMMARY_UNPARSED",
                f"could not extract a '{want_sec}' View:ALL row from {path}. "
                "Refusing to treat an unreadable report as a clean one.",
            )
    return out


def parse_analysis_coverage(path, r):
    """
    Tempus report_analysis_coverage: counts of Met / Violated / Untested
    checks. 'Untested' is the number that matters here — it is the direct
    measurement of the coverage hole that the in-flow gates cannot see.
    """
    if not os.path.isfile(path):
        r.fail("COVERAGE_MISSING", f"no analysis coverage report at {path}")
        return None
    text = open(path, errors="replace").read()
    if not text.strip():
        r.fail("COVERAGE_EMPTY", f"analysis coverage report is empty: {path}")
        return None

    # Tempus emits a per-check-type TABLE, not a single total:
    #
    #   Check Type            No. of   Met          Violated     Untested
    #                         Checks
    #   ClockPeriod           42       4 (9%)       0 (0%)       38 (90%)
    #   DataCheckSetup        69       0 (0%)       0 (0%)       69 (100%)
    #
    # so the untested figure is the SUM of the last column. An earlier version
    # of this parser looked for a single "Untested <n>" and matched the header
    # word instead, which would have reported 0 untested on a report showing
    # ~57,800. Sum the rows, and require at least one row to have parsed.
    row = re.compile(
        r"^\s*(?P<name>[A-Za-z][A-Za-z0-9 ()_\-]*?)\s{2,}"
        r"(?P<n>\d+)\s+"
        r"(?P<met>\d+)\s*\(\s*\d+%\s*\)\s+"
        r"(?P<vio>\d+)\s*\(\s*\d+%\s*\)\s+"
        r"(?P<unt>\d+)\s*\(\s*\d+%\s*\)\s*$"
    )
    total_unt = 0
    rows = 0
    per_type = {}
    for line in text.splitlines():
        mo = row.match(line)
        if not mo:
            continue
        rows += 1
        u = int(mo.group("unt"))
        total_unt += u
        if u:
            per_type[mo.group("name").strip()] = (u, int(mo.group("n")))

    if rows == 0:
        r.fail(
            "COVERAGE_UNPARSED",
            f"parsed zero check-type rows from {path}. A coverage report that "
            "cannot be read is not evidence of coverage.",
        )
        return None

    if per_type:
        worst = sorted(per_type.items(), key=lambda kv: -kv[1][0])[:4]
        r.fact("untested_by_type", ", ".join(f"{k}={v[0]}/{v[1]}" for k, v in worst))
    r.fact("coverage_rows", rows)
    return total_unt


# ---------------------------------------------------------------------------
# THE UNTESTED CHECKS, ENUMERATED.
#
# rc2, rc3fix and rc4 each carry 57,955 UNTESTED timing checks with zero
# violated -- the same number on all three -- and until 2026-08-29 nobody had
# ever looked at what they were. This gate USED TO FAIL on `untested > 0`, which
# sounds strict and measures nothing: the number cannot be zero on this design
# (169,356 PulseWidth checks alone), so the arm could only ever be overridden or
# the whole stage demoted to `gate: report`. It was demoted. A gate everyone must
# ignore is a gate that has stopped existing.
#
# THE NUMBER IS NOT THE FINDING. THE REASON SET IS. Tempus attributes every
# untested check to a CLOSED set, and the members are not equivalent:
#
#   false_path, user_disable      DECISIONS. Somebody wrote an SDC exception.
#                                 Auditable, and their COUNT MOVING is the
#                                 signal, not their existence.
#   const                         the endpoint is tied off; no path to time.
#   no_endpoint_clock,            A CONSTRAINT HOLE. Nobody decided this; a
#   no_startpoint_clock           clock is simply undefined at one end.
#   unknown                       Tempus declines to say. THIS MUST BE ZERO:
#                                 a check the tool would not perform and cannot
#                                 attribute is indistinguishable from a check
#                                 that would have failed.
#
# MEASURED ON rc4's OWN DATABASE, 2026-08-29, first enumeration ever made:
#   43,200  no_endpoint_clock   (all PulseWidth, on CDN async-reset pins)
#    9,642  const
#    5,113  false_path
#   ------
#   57,955  == the total in analysis_coverage.rpt, exactly. Zero unknown.
#
# ANY REASON STRING THIS PARSER DOES NOT RECOGNISE COUNTS AS `unknown`. That is
# the anti-vacuity property and it is deliberate: a Tempus format change, a new
# reason category, or a typo in the table below must make this gate FIRE, never
# make a population quietly vanish from the histogram. The alternative -- drop
# what you cannot classify -- is how a coverage report comes to describe less
# than it measured.
# ---------------------------------------------------------------------------
UNTESTED_REASONS = ("const", "false_path", "no_endpoint_clock",
                    "no_startpoint_clock", "user_disable", "unknown")

# Tempus prints prose in the Reason column ("No endpoint clock"), not the
# canonical id. Matched case-insensitively on the squeezed string.
_REASON_ALIASES = {
    "const": "const",
    "constant": "const",
    "falsepath": "false_path",
    "false_path": "false_path",
    "noendpointclock": "no_endpoint_clock",
    "no_endpoint_clock": "no_endpoint_clock",
    "nostartpointclock": "no_startpoint_clock",
    "no_startpoint_clock": "no_startpoint_clock",
    "userdisable": "user_disable",
    "userdisabled": "user_disable",
    "user_disable": "user_disable",
    "disabled": "user_disable",
    "unknown": "unknown",
}

# The detail row: "<CheckType>   UNTESTED   <Reason>" at the end of a record.
# Anchored on the literal UNTESTED so a wrapped pin name (these run to 140
# characters and Tempus wraps them) cannot be mistaken for a check type.
_UNTESTED_ROW = re.compile(
    r"^(?P<pre>.*?)\s{2,}UNTESTED\s+(?P<reason>\S.*?)\s*$")


def _canon_reason(s):
    key = re.sub(r"[^a-z]", "", s.lower())
    return _REASON_ALIASES.get(key, "unknown")


def parse_untested_reasons(path, r):
    """{canonical_reason: count} from report_analysis_coverage -verbose untested.

    Returns None when the file is absent -- the CALLER decides whether that is
    acceptable, because with zero untested checks there is nothing to enumerate
    and an absent file is then correct. An unreadable or unparseable file is a
    FAILURE here and never None: "the enumeration could not be read" and "there
    was nothing to enumerate" are opposite findings.
    """
    if not os.path.isfile(path):
        return None
    text = open(path, errors="replace").read()
    if not text.strip():
        r.fail("UNTESTED_ENUM_EMPTY",
               f"the untested enumeration is an empty file: {path}")
        return {}
    counts = {}
    for line in text.splitlines():
        mo = _UNTESTED_ROW.match(line)
        if not mo:
            continue
        # The summary table also carries the word UNTESTED as a COLUMN HEADING.
        # A heading has no reason text after it that survives canonicalisation
        # to a known id, so it would land in `unknown` and fire the gate for no
        # reason. Skip the header explicitly rather than by luck.
        if mo.group("pre").strip().lower().startswith("check type"):
            continue
        reason = _canon_reason(mo.group("reason"))
        counts[reason] = counts.get(reason, 0) + 1
    if not counts:
        r.fail("UNTESTED_ENUM_UNPARSED",
               f"parsed zero untested rows from {path}. An enumeration that "
               "cannot be read is not evidence of a reason set.")
    return counts


def check(reports_dir, policy, r):
    man_path = os.path.join(reports_dir, "sta_manifest.txt")
    man = parse_manifest(man_path, r)

    # --- run actually completed -------------------------------------------
    if man and "sta_finished" not in man:
        r.fail(
            "RUN_INCOMPLETE",
            "manifest has no sta_finished key: the STA run did not reach the "
            "end. Partial reports must not be read as results.",
        )
    for k, v in man.items():
        if k.startswith("step.") and v == "FAILED":
            r.fail("STEP_FAILED", f"{k} = FAILED ({man.get(k + '.error', '?')})")
        if k == "fatal":
            r.fail("RUN_FATAL", v)

    # --- analysis mode ----------------------------------------------------
    if policy.get("require_cppr"):
        got = man.get("timing_analysis_cppr")
        if got != policy["require_cppr"]:
            r.fail("CPPR", f"timing_analysis_cppr = {got!r}, require {policy['require_cppr']!r}")
    if policy.get("require_analysis_type"):
        got = man.get("timing_analysis_type")
        if got != policy["require_analysis_type"]:
            r.fail("ANALYSIS_TYPE", f"timing_analysis_type = {got!r}, require {policy['require_analysis_type']!r}")

    # --- derate re-issued -------------------------------------------------
    # Not "is a derate set somewhere" but "is THIS derate set", because the
    # routed DB persists derate for typical_delay_corner only and inheriting
    # it silently drops OCV from both signoff corners.
    for key, want in (policy.get("require_derate") or {}).items():
        raw = man.get(key)
        if raw is None:
            r.fail("DERATE_MISSING", f"manifest has no {key}: OCV derate was not re-issued")
            continue
        try:
            got = float(raw)
        except ValueError:
            r.fail("DERATE_UNPARSED", f"{key} = {raw!r} is not a number")
            continue
        if abs(got - float(want)) > 1e-9:
            r.fail("DERATE_VALUE", f"{key} = {got}, require {want}")

    # --- extraction quality ----------------------------------------------
    if policy.get("require_qrc_all_rc_corners"):
        qrc_keys = {k: v for k, v in man.items() if k.startswith("extract.qrc_set.")}
        if not qrc_keys:
            r.fail("QRC_NO_EVIDENCE", "manifest records no extract.qrc_set.* keys")
        for k, v in sorted(qrc_keys.items()):
            if v != "yes":
                r.fail("QRC_MISSING", f"{k} = {v}: RC corner has no QRC deck, extraction is cap-table only")

    # --- SPEF actually written -------------------------------------------
    min_bytes = policy.get("require_spef_min_bytes", 0)
    if min_bytes:
        spef_keys = {k: v for k, v in man.items() if k.startswith("spef.") and k.endswith(".bytes")}
        if not spef_keys:
            if man.get("step.extract_parasitics") == "skipped_by_request":
                r.warn("SPEF_SKIPPED", "extraction skipped by request; SPEF not checked")
            else:
                r.fail("SPEF_NONE", "no SPEF was written for any RC corner")
        for k, v in sorted(spef_keys.items()):
            try:
                n = int(v)
            except ValueError:
                r.fail("SPEF_UNPARSED", f"{k} = {v!r}")
                continue
            if n < min_bytes:
                r.fail("SPEF_TOO_SMALL", f"{k} = {n} bytes, require >= {min_bytes}. A truncated SPEF times as an optimistic design.")

    # --- view set has not silently shrunk ---------------------------------
    # RUNS BEFORE THE CLOCK CHECK, because the clock check cross-foots against
    # the number of DISTINCT views collected here. Union, not sum: a view named
    # in both roles is one view.
    active_views = set()
    views_recorded = False
    for role, key in (("setup", "required_setup_views"), ("hold", "required_hold_views")):
        want = policy.get(key) or []
        raw = man.get(f"analysis_views_{role}")
        if raw is None:
            if want:
                r.fail("VIEWS_MISSING", f"manifest has no analysis_views_{role}")
            continue
        got = [x for x in raw.split(",") if x]
        if got:
            active_views.update(got)
            views_recorded = True
        r.fact(f"views_{role}", got)
        for v in want:
            if v not in got:
                r.fail("VIEW_ABSENT", f"required {role} view {v!r} not active (active: {got})")

    # --- clock coverage ---------------------------------------------------
    # What this arm detects is a CLOCK that vanished between P&R and STA. What
    # it must NOT detect is a deliberate change to the view set -- that is what
    # the required-view lists above are for, and pinning an absolute product of
    # the two made every extra corner look like a missing clock. So the
    # expectation is derived per run from the active view count, and the pinned
    # per-view number is the thing held constant.
    n_sdc    = policy.get("expected_sdc_clock_count")
    want_abs = policy.get("expected_clock_count")

    # (a) POLICY SELF-CHECK. Not about the run at all: the two pinned numbers
    #     must agree with the required view lists they are derived from.
    if n_sdc and want_abs:
        req = set(policy.get("required_setup_views") or []) | \
              set(policy.get("required_hold_views") or [])
        if req and want_abs != n_sdc * len(req):
            r.fail("POLICY_INCONSISTENT",
                   f"expected_clock_count = {want_abs} but the policy requires "
                   f"{len(req)} distinct view(s) at {n_sdc} clocks each = "
                   f"{n_sdc * len(req)}. Change both or neither.")

    # (b) THE RUN CHECK.
    if n_sdc or want_abs:
        raw = man.get("clock_count")
        if raw is None:
            r.fail("CLOCKS_MISSING", "manifest has no clock_count")
        else:
            try:
                got = int(raw)
            except ValueError:
                r.fail("CLOCKS_UNPARSED", f"clock_count = {raw!r}")
                got = None
            if got is not None:
                r.fact("clock_count", got)
                if n_sdc and views_recorded:
                    r.fact("active_view_count", len(active_views))
                    expect = n_sdc * len(active_views)
                    if got != expect:
                        r.fail("CLOCK_COUNT",
                               f"clock_count = {got}, expected {expect} "
                               f"({n_sdc} SDC clocks x {len(active_views)} distinct "
                               f"active view(s)). A clock that vanished between P&R "
                               f"and STA is a whole timing domain nobody is checking.")
                elif want_abs and got != want_abs:
                    # No per-view pin, or the manifest recorded no view lists:
                    # fall back to the absolute number rather than skip the arm.
                    r.fail("CLOCK_COUNT",
                           f"clock_count = {got}, expected {want_abs}. A clock that "
                           f"vanished between P&R and STA is a whole timing domain "
                           f"nobody is checking.")

    # --- coverage ---------------------------------------------------------
    untested = parse_analysis_coverage(os.path.join(reports_dir, "analysis_coverage.rpt"), r)
    if untested is not None:
        r.fact("untested_checks", untested)
        enum_path = os.path.join(reports_dir, "analysis_coverage_untested.rpt")
        reasons = parse_untested_reasons(enum_path, r)
        if untested == 0:
            pass                       # nothing to enumerate; absence is correct
        elif reasons is None:
            # THE REPLACEMENT FOR `untested > 0`. Not "there are untested
            # checks" -- there always are -- but "there are untested checks and
            # nobody has said what they are".
            r.fail("UNTESTED_UNENUMERATED",
                   f"{untested} timing checks are UNTESTED and no enumeration "
                   f"exists at {os.path.basename(enum_path)}. Run "
                   f"scripts/ci/sta_untested_reasons.tcl against this build. An "
                   f"unenumerated coverage hole cannot be told apart from a "
                   f"population of checks that would have failed.")
        elif reasons:
            total = sum(reasons.values())
            r.fact("untested_by_reason",
                   ", ".join(f"{k}={v}" for k, v in sorted(reasons.items())))
            if total != untested:
                # THE CROSS-FOOT. A reason list that does not add up to its own
                # total has enumerated some other population, and the shortfall
                # is exactly the part nobody has looked at.
                r.fail("UNTESTED_ENUM_SHORT",
                       f"the enumeration accounts for {total} untested checks "
                       f"but analysis_coverage.rpt reports {untested}. "
                       f"{abs(untested - total)} check(s) are in neither column "
                       f"of this evidence.")
            unknown = reasons.get("unknown", 0)
            budget = policy.get("untested_unknown_budget", 0)
            if budget is not None and unknown > budget:
                r.fail("UNTESTED_UNKNOWN_REASON",
                       f"{unknown} untested check(s) carry a reason this gate "
                       f"does not recognise (budget {budget}). Recognised: "
                       f"{', '.join(UNTESTED_REASONS)}. A check the tool "
                       f"declined to perform AND declined to attribute is "
                       f"indistinguishable from one that would have failed.")
            for kind in ("no_endpoint_clock", "no_startpoint_clock"):
                if reasons.get(kind):
                    # A constraint hole is not a decision. Reported, not failed:
                    # 43,200 of rc4's 57,955 are this, all PulseWidth on CDN
                    # pins, and failing on it today would only get the row muted
                    # again. The COUNT is the tripwire.
                    r.warn("UNTESTED_CONSTRAINT_HOLE",
                           f"{reasons[kind]} untested check(s) are {kind} — "
                           f"nobody decided these; a clock is simply undefined "
                           f"at one end of the check.")

    # --- quality ----------------------------------------------------------
    # Tempus splits these across two files: report_timing_summary -checks setup
    # and -checks hold. Asking one invocation for both is REFUSED
    # (TCLCMD-1130) and it then quietly produces a setup-only report that looks
    # complete. So a hold row missing from timing_summary.rpt is normal, and
    # the hold file is the place to look — but if NEITHER file yields a hold
    # row, that is still a failure, because a design with no hold analysis is
    # exactly how hold ships unexamined.
    summary = parse_timing_summary(
        os.path.join(reports_dir, "timing_summary.rpt"), r, want=("setup",)
    )
    hold_path = os.path.join(reports_dir, "timing_summary_hold.rpt")
    if os.path.isfile(hold_path):
        summary.update(
            parse_timing_summary(hold_path, r, want=("hold",))
        )
    else:
        r.fail(
            "HOLD_SUMMARY_MISSING",
            f"no {os.path.basename(hold_path)}. Tempus reports setup and hold "
            "in separate invocations; without the hold one there is no hold "
            "analysis at all.",
        )
    for mode, bkey in (("setup", "setup_fep_budget"), ("hold", "hold_fep_budget")):
        if mode not in summary:
            continue
        wns, fep = summary[mode]
        r.fact(f"{mode}_wns", wns)
        r.fact(f"{mode}_fep", fep)
        budget = policy.get(bkey)
        if budget is None:
            continue
        if fep > budget:
            r.fail(f"{mode.upper()}_FEP", f"{mode} FEP {fep} > budget {budget} (WNS {wns})")
        # R2: a budget that exactly equals the measured value is the
        # signature of a threshold back-fitted to the day's number.
        if budget != 0 and fep == budget:
            r.warn("BUDGET_BACKFITTED", f"{bkey} ({budget}) exactly equals the measured {mode} FEP. A budget set to the day's number cannot detect a regression.")

    return r


def emit(r, fmt="text"):
    if fmt == "json":
        print(json.dumps({
            "pass": r.ok,
            "failures": [{"code": c, "message": m} for c, m in r.failures],
            "warnings": [{"code": c, "message": m} for c, m in r.warnings],
            "facts": r.facts,
        }, indent=2))
        return
    if r.facts:
        print("MEASURED")
        for k, v in r.facts.items():
            print(f"  {k:24s} {v}")
        print()
    for c, m in r.warnings:
        print(f"WARN  [{c}] {m}")
    for c, m in r.failures:
        print(f"FAIL  [{c}] {m}")
    print()
    print("GATE: PASS" if r.ok else f"GATE: FAIL ({len(r.failures)} failure(s))")


# ---------------------------------------------------------------------------
# SELF-TEST — the part that proves this gate can fail.
# ---------------------------------------------------------------------------
GOOD_MANIFEST = """\
sta_tool = tempus
sta_db = /somewhere/nanosoc_eth_chiplet_pads_routed
step.read_db = ok
step.extract_parasitics = ok
design_name = nanosoc_eth_chiplet_pads
clock_count = 104
analysis_views_setup = default_analysis_view_setup
analysis_views_hold = default_analysis_view_hold,av_ml_libset_hold,av_ltfix_libset_hold
timing_analysis_type = ocv
timing_analysis_cppr = both
derate_data_early = 0.95
derate_data_late = 1.05
derate_clk_early = 0.97
derate_clk_late = 1.03
extract.qrc_set.default_rc_corner_worst = yes
extract.qrc_set.default_rc_corner_best = yes
extract.qrc_set.default_rc_corner_typical = yes
spef.default_rc_corner_worst.bytes = 250000000
spef.default_rc_corner_best.bytes = 250000000
spef.default_rc_corner_typical.bytes = 250000000
sta_finished = 2026-08-18T02:00:00
"""

# Real Tempus emits setup and hold in SEPARATE files; a combined request is
# refused (TCLCMD-1130). The fixtures mirror that split.
GOOD_SUMMARY = """\
# SETUP                   WNS       TNS   FEP
 View : ALL             0.012     0.000     0
"""

GOOD_HOLD_SUMMARY = """\
# HOLD                    WNS     TNS   FEP
 View : ALL             0.004    0.000     0
"""

# Verbatim column layout of a real Tempus 21.11 report_analysis_coverage,
# with the untested column zeroed. Pinning the REAL format here means a
# future format drift breaks the selftest rather than silently turning the
# coverage check into a no-op.
GOOD_COVERAGE = """\
    -------------------------------------------------------------------------------------------
                                   TIMING CHECK COVERAGE SUMMARY
    -------------------------------------------------------------------------------------------
     Check Type                      No. of   Met              Violated         Untested
                                     Checks
    -------------------------------------------------------------------------------------------
    Clock Gating Setup             2         2 (100%)         0 (0%)           0 (0%)
    ClockPeriod                    42        42 (100%)        0 (0%)           0 (0%)
    Recovery                       43399     43399 (100%)     0 (0%)           0 (0%)
    Setup                          68318     68318 (100%)     0 (0%)           0 (0%)
    -------------------------------------------------------------------------------------------
"""

# The real thing, as measured on nanosoc_eth_chiplet_pads 2026-08-17.
MEASURED_COVERAGE = """\
     Check Type                      No. of   Met              Violated         Untested
                                     Checks
    Clock Gating Setup             2         2 (100%)         0 (0%)           0 (0%)
    ClockPeriod                    42        4 (9%)           0 (0%)           38 (90%)
    DataCheckSetup                 69        0 (0%)           0 (0%)           69 (100%)
    ExternalDelay (Late)           15        7 (46%)          0 (0%)           8 (53%)
    Library Clock Gating Setup     6004      2961 (49%)       41 (0%)          3002 (50%)
    PulseWidth                     169686    120151 (70%)     0 (0%)           49535 (29%)
    Recovery                       43399     40558 (93%)      0 (0%)           2841 (6%)
    Setup                          68318     65598 (96%)      421 (0%)         2299 (3%)
    TimeBorrow                     1         1 (100%)         0 (0%)           0 (0%)
"""


# The untested enumeration, in the VERBATIM column layout Tempus 21.11 emits for
# `report_analysis_coverage -verbose untested -sort reason`, captured from the
# rc4 database on 2026-08-29. Pin names are elided; the Reason column is not,
# because the Reason column is the measurement.
def _enum(pairs):
    """Build an enumeration report with `n` rows of each (check_type, reason)."""
    head = ("    ----------------------------------------------------------\n"
            "     Pin                Reference Pin      Check Type"
            "         Slack        Reason\n"
            "    ----------------------------------------------------------\n")
    body = []
    for i, (check, reason, n) in enumerate(pairs):
        for j in range(n):
            body.append("    some/inst_%d_%d/D\n" % (i, j))
            body.append("                                 some/inst_%d_%d/CP ^\n" % (i, j))
            body.append("                                 %-26s UNTESTED     %s\n"
                        % (check, reason))
    return head + "".join(body)


# Adds up to MEASURED_COVERAGE's 57,955 in the same 3-reason mix rc4 measured,
# scaled down 1000x so the selftest stays instant. The gate cross-foots the
# enumeration against the coverage table, so the two fixtures below are a
# MATCHED PAIR and the scaled coverage table exists for that reason.
ENUM_COVERAGE = """\
     Check Type                      No. of   Met              Violated         Untested
                                     Checks
    PulseWidth                     200       157 (78%)        0 (0%)           43 (21%)
    Setup                          100       95 (95%)         0 (0%)           5 (5%)
    Recovery                       100       90 (90%)         0 (0%)           10 (10%)
"""
GOOD_ENUM = _enum([("PulseWidth", "No endpoint clock", 43),
                   ("Recovery", "const", 10),
                   ("Setup", "False Path", 5)])


def _mk(tmp, manifest=GOOD_MANIFEST, summary=GOOD_SUMMARY, coverage=GOOD_COVERAGE,
        hold_summary=GOOD_HOLD_SUMMARY, enum=None):
    d = tempfile.mkdtemp(dir=tmp)
    if enum is not None:
        with open(os.path.join(d, "analysis_coverage_untested.rpt"), "w") as fh:
            fh.write(enum)
    with open(os.path.join(d, "sta_manifest.txt"), "w") as fh:
        fh.write(manifest)
    if hold_summary is not None:
        with open(os.path.join(d, "timing_summary_hold.rpt"), "w") as fh:
            fh.write(hold_summary)
    if summary is not None:
        with open(os.path.join(d, "timing_summary.rpt"), "w") as fh:
            fh.write(summary)
    if coverage is not None:
        with open(os.path.join(d, "analysis_coverage.rpt"), "w") as fh:
            fh.write(coverage)
    return d


def selftest():
    """
    Mutation test. Each case perturbs exactly one property of a known-good
    artefact set and asserts the gate rejects it with the expected code.
    If the baseline does not PASS, or any mutant does not FAIL, the gate is
    broken and this returns non-zero.
    """
    tmp = tempfile.mkdtemp(prefix="sta_gate_selftest_")
    passed = failed = 0
    try:
        # Baseline must PASS — otherwise every later "FAIL" is meaningless,
        # because a gate that fails everything is as useless as one that
        # passes everything.
        r = check(_mk(tmp), dict(DEFAULT_POLICY), Result())
        if r.ok:
            print("ok    baseline PASSES")
            passed += 1
        else:
            print(f"BROKEN baseline FAILS: {r.failures}")
            failed += 1

        # SECOND POSITIVE CONTROL, and it is the one that keeps the untested
        # arms honest. The baseline above has ZERO untested checks, so it would
        # pass with the enumeration code deleted. This one has 58 untested
        # checks, every one accounted for by a recognised reason, and it must
        # PASS -- otherwise the gate is back to failing on `untested > 0` under
        # a new name.
        r = check(_mk(tmp, coverage=ENUM_COVERAGE, enum=GOOD_ENUM),
                  dict(DEFAULT_POLICY), Result())
        if r.ok:
            print("ok    baseline PASSES with 58 untested checks, all attributed")
            passed += 1
        else:
            print(f"BROKEN an accounted-for untested population FAILS: {r.failures}")
            failed += 1

        # THIRD POSITIVE CONTROL, and it is the one the 2026-09-01 clock-count
        # rewrite exists for. sta_policy.json's own text says the required-view
        # lists are "a floor and never a ceiling" -- a run that activates MORE
        # views must still pass. Under the old absolute `expected_clock_count`
        # pin it did not: five active views report 130 and the gate demanded
        # 104, so the cheapest way to make a five-corner run green was to drop
        # a corner. This case fails if that regresses.
        r = check(_mk(tmp, manifest=GOOD_MANIFEST
                      .replace("clock_count = 104", "clock_count = 130")
                      .replace("analysis_views_setup = default_analysis_view_setup",
                               "analysis_views_setup = default_analysis_view_setup,"
                               "typical_analysis_view")),
                  dict(DEFAULT_POLICY), Result())
        if r.ok:
            print("ok    baseline PASSES with a FIFTH view active (130 = 26 x 5)")
            passed += 1
        else:
            print(f"BROKEN a run with more views than required FAILS: {r.failures}")
            failed += 1

        cases = [
            ("missing manifest", dict(manifest=None), "MANIFEST_MISSING"),
            ("empty manifest", dict(manifest="\n\n"), "MANIFEST_EMPTY"),
            ("run did not finish",
             dict(manifest=GOOD_MANIFEST.replace("sta_finished = 2026-08-18T02:00:00", "")),
             "RUN_INCOMPLETE"),
            ("a step failed",
             dict(manifest=GOOD_MANIFEST.replace("step.read_db = ok", "step.read_db = FAILED")),
             "STEP_FAILED"),
            ("CPPR off",
             dict(manifest=GOOD_MANIFEST.replace("timing_analysis_cppr = both", "timing_analysis_cppr = none")),
             "CPPR"),
            ("analysis type not ocv",
             dict(manifest=GOOD_MANIFEST.replace("timing_analysis_type = ocv", "timing_analysis_type = single")),
             "ANALYSIS_TYPE"),
            ("derate not re-issued (the read_db trap)",
             dict(manifest=GOOD_MANIFEST.replace("derate_clk_late = 1.03", "")),
             "DERATE_MISSING"),
            ("derate silently weakened",
             dict(manifest=GOOD_MANIFEST.replace("derate_data_late = 1.05", "derate_data_late = 1.00")),
             "DERATE_VALUE"),
            ("an RC corner lost its QRC deck",
             dict(manifest=GOOD_MANIFEST.replace(
                 "extract.qrc_set.default_rc_corner_worst = yes",
                 "extract.qrc_set.default_rc_corner_worst = no")),
             "QRC_MISSING"),
            ("SPEF truncated",
             dict(manifest=GOOD_MANIFEST.replace(
                 "spef.default_rc_corner_worst.bytes = 250000000",
                 "spef.default_rc_corner_worst.bytes = 412")),
             "SPEF_TOO_SMALL"),
            ("clocks vanished between P&R and STA",
             dict(manifest=GOOD_MANIFEST.replace("clock_count = 104", "clock_count = 17")),
             "CLOCK_COUNT"),
            # The derived form has to be able to fail UPWARDS too, or it is
            # just "any multiple of 26 is fine". Four active views and a count
            # that belongs to five is a clock population that changed.
            ("clock count stops tracking the active view set",
             dict(manifest=GOOD_MANIFEST.replace("clock_count = 104", "clock_count = 130")),
             "CLOCK_COUNT"),
            # The policy grading ITSELF. An editor who lengthens
            # required_hold_views and leaves expected_clock_count alone gets
            # told the rule here, instead of a CLOCK_COUNT on every run after.
            ("the policy's clock arithmetic contradicts its own view lists",
             dict(policy={"expected_clock_count": 130}),
             "POLICY_INCONSISTENT"),
            ("setup view silently dropped",
             dict(manifest=GOOD_MANIFEST.replace(
                 "analysis_views_setup = default_analysis_view_setup",
                 "analysis_views_setup = typical_analysis_view")),
             "VIEW_ABSENT"),
            # The setup side had a mutation and the hold side did not, so the
            # half of the view check that guards the three hold corners was
            # never proven able to fire.
            ("hold view silently dropped",
             dict(manifest=GOOD_MANIFEST.replace(
                 "analysis_views_hold = default_analysis_view_hold,"
                 "av_ml_libset_hold,av_ltfix_libset_hold",
                 "analysis_views_hold = default_analysis_view_hold")),
             "VIEW_ABSENT"),
            # THE UNTESTED POPULATION. Five arms, and the shape of the set is
            # the argument: `untested > 0` is NOT one of them, because on this
            # design it is always true and a gate that is always red is a gate
            # that gets muted. What must fail is an untested population nobody
            # has ACCOUNTED FOR.
            ("untested checks present and never enumerated (the real 57,955)",
             dict(coverage=MEASURED_COVERAGE), "UNTESTED_UNENUMERATED"),
            ("a single check type goes untested, unenumerated",
             dict(coverage=GOOD_COVERAGE.replace(
                 "ClockPeriod                    42        42 (100%)        0 (0%)           0 (0%)",
                 "ClockPeriod                    42        4 (9%)           0 (0%)           38 (90%)")),
             "UNTESTED_UNENUMERATED"),
            # A reason string outside the closed set. This is the arm the whole
            # enumeration exists for: an unattributed untested check.
            ("an untested check carries an unrecognised reason",
             dict(coverage=ENUM_COVERAGE,
                  enum=_enum([("PulseWidth", "No endpoint clock", 43),
                              ("Recovery", "const", 10),
                              ("Setup", "Something Tempus Invented", 5)])),
             "UNTESTED_UNKNOWN_REASON"),
            # The enumeration is real but describes a smaller population than
            # the coverage table counts -- the shortfall is the part nobody
            # looked at, and it is invisible to any per-row check.
            ("the enumeration does not add up to its own total",
             dict(coverage=ENUM_COVERAGE,
                  enum=_enum([("PulseWidth", "No endpoint clock", 40),
                              ("Recovery", "const", 10),
                              ("Setup", "False Path", 5)])),
             "UNTESTED_ENUM_SHORT"),
            ("the enumeration is present but unreadable",
             dict(coverage=ENUM_COVERAGE,
                  enum="Analysis Coverage Report\n  (no rows)\n"),
             "UNTESTED_ENUM_UNPARSED"),
            ("coverage report missing", dict(coverage=None), "COVERAGE_MISSING"),
            ("coverage report unreadable",
             dict(coverage="Analysis Coverage Report\n  (no data)\n"),
             "COVERAGE_UNPARSED"),
            ("coverage table format drifts (columns change)",
             dict(coverage=GOOD_COVERAGE.replace("(100%)", "pct100")),
             "COVERAGE_UNPARSED"),
            ("timing summary missing", dict(summary=None), "SUMMARY_MISSING"),
            ("timing summary format drifted",
             dict(summary="# SETUP\n  something something 0\n# HOLD\n  nothing\n"),
             "SUMMARY_UNPARSED"),
            ("setup does not close",
             dict(summary=GOOD_SUMMARY.replace(
                 " View : ALL             0.012     0.000     0",
                 " View : ALL            -0.759  -309.637  1444")),
             "SETUP_FEP"),
            ("hold does not close (measured: Tempus finds 79, in-flow found 7)",
             dict(hold_summary=GOOD_HOLD_SUMMARY.replace(
                 " View : ALL             0.004    0.000     0",
                 " View : ALL            -0.006   -0.069    79")),
             "HOLD_FEP"),
            ("hold summary absent entirely",
             dict(hold_summary=None), "HOLD_SUMMARY_MISSING"),
        ]

        for name, kw, want_code in cases:
            kw2 = dict(kw)
            pol = dict(DEFAULT_POLICY)
            pol.update(kw2.pop("policy", {}))
            if kw2.get("manifest") is None and "manifest" in kw2:
                d = tempfile.mkdtemp(dir=tmp)  # no manifest at all
                if kw2.get("summary", GOOD_SUMMARY) is not None:
                    open(os.path.join(d, "timing_summary.rpt"), "w").write(GOOD_SUMMARY)
                if kw2.get("coverage", GOOD_COVERAGE) is not None:
                    open(os.path.join(d, "analysis_coverage.rpt"), "w").write(GOOD_COVERAGE)
            else:
                d = _mk(tmp, **kw2)
            rr = check(d, pol, Result())
            codes = [c for c, _ in rr.failures]
            if rr.ok:
                print(f"BROKEN {name!r}: gate PASSED a mutant it must reject")
                failed += 1
            elif want_code not in codes:
                print(f"BROKEN {name!r}: failed but with {codes}, expected {want_code}")
                failed += 1
            else:
                print(f"ok    rejects: {name}  [{want_code}]")
                passed += 1
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    print(f"\nSELFTEST: {passed} passed, {failed} broken")
    return 0 if failed == 0 else 1


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--reports", help="directory holding sta_manifest.txt and the reports")
    ap.add_argument("--policy", help="JSON file overriding the acceptance thresholds")
    ap.add_argument("--format", choices=("text", "json"), default="text")
    ap.add_argument("--selftest", action="store_true", help="mutation-test the gate itself")
    args = ap.parse_args()

    if args.selftest:
        return selftest()

    if not args.reports:
        ap.error("--reports is required (or use --selftest)")

    policy = dict(DEFAULT_POLICY)
    if args.policy:
        if not os.path.isfile(args.policy):
            print(f"FAIL [POLICY_MISSING] no policy file at {args.policy}")
            return 2
        policy.update(json.load(open(args.policy)))

    r = check(args.reports, policy, Result())
    emit(r, args.format)
    return 0 if r.ok else 1


if __name__ == "__main__":
    sys.exit(main())
