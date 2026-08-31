#!/usr/bin/env python3
"""stage_timeline.py -- one comparable timing record per OPTIMISATION STATE.

    scripts/ci/stage_timeline.py ASIC/eth-chiplet/build/rc5vt-20260829
    scripts/ci/stage_timeline.py <run_dir> --json /tmp/timeline.json
    scripts/ci/stage_timeline.py <run_dir> --expect 'cts_after_post_cts_hold:hold_wns=0.003'

WHAT IT IS
----------
READ-ONLY, like `run_index.py`, whose parsers it imports rather than
re-implementing. Where `run_index.py` answers "which STAGE does this file
measure?", this answers the next question:

    WHAT DID EVERY OPTIMISATION STATE MEASURE, AND WHICH STATE MADE
    SOMETHING WORSE THAN THE STATE BEFORE IT?

A stage is not a state. `cts` is one stage and at least four states --
ccopt_design, opt_design -post_cts, opt_design -post_cts -hold, and (when
CTS_POST_HOLD_SETUP is on) a second opt_design -post_cts. A stage manifest is
written at the END and records the LAST of them, so a stage that closed hold
completely in the middle and threw it away at the end reports as if the middle
never happened. On rc5 attempt 6 the middle was `hold +0.003 / 0 failing` and
the end was `hold -0.700 / 8718 failing`, and no file in `reports/` said a
state had regressed.

WHY THE FLOW COULD NOT SHOW IT, IN FOUR STRUCTURAL FACTS
--------------------------------------------------------
1. `report_qor`'s snapshot table -- the only per-state progression view the
   flow produces -- HAS NO HOLD COLUMN. Its nine rc5 rows show setup WNS
   climbing 0.002 -> 0.105 and nothing else. `parse_qor_snapshots` in
   run_index.py names every column; `hold` is not among them.
2. `report_qor` keys rows by SNAPSHOT NAME. A second `opt_design -post_cts`
   does not add a tenth row -- rc5 attempt 6 ran one and its table ends at
   `opt_design_postcts_hold`, exactly as attempt 7's does. The pass that did
   the damage is absent from the table that exists to show passes.
3. `opt_design`'s own `.summary.gz` prints a Setup mode table OR a Hold mode
   table, never both: `-hold` runs emit hold only, plain runs setup only. A
   trade is invisible in either half.
4. The unsuffixed `<prefix>.summary.gz` is LAST-WRITER-WINS across commands.
   In rc5 attempt 7 `..._cts.summary.gz` contains `opt_design -post_cts -hold`;
   in attempt 6 the same filename contains `opt_design -post_cts`. This tool
   files every opt summary by the `#  Command:` line inside it, never by name.

WHAT IT EMITS
-------------
One row per state, all from the same instrument where one exists, with:

    setup WNS/TNS/FEP and hold WNS/TNS/FEP, overall and per path group
    DRV max_transition / max_capacitance / max_fanout WNS/TNS/FEP
    instances, cell area, utilisation
    the ACTIVE ANALYSIS VIEWS, with the basis for that claim
    the tool clock the state was measured at, and file:line for every number

...then the transitions between consecutive states, worst first, with a verdict
per metric and -- the point of the whole exercise -- the EXCHANGE RATE when a
state improves one metric by regressing another.

INSTRUMENTS ARE NEVER MIXED
---------------------------
Three different tools measure "hold WNS" in one run and they do not agree,
because they are not the same measurement:

    report_timing_summary   under timing_enable_simultaneous_setup_hold_mode,
                            over every ACTIVE analysis view.   channel `rts`
    opt_design summary      the optimiser's own view set, post-route with SI.
                            Hold mode `all` column.            channel `opt`
    report_qor snapshot     setup only; no hold column at all. channel `qor`

Every value carries its channel. A delta is only computed between two values on
the SAME channel; a cross-channel pair is reported as `NOT COMPARABLE` with
both numbers shown, never subtracted. rc5's route stage can only be described
that way, and saying so is the finding.

ANALYSIS VIEWS
--------------
"hold WNS -0.100" means nothing without the view set it was worst over. rc5
measures some states over five active views (2 setup / 4 hold, `typical_
analysis_view` active in BOTH roles) and others over four, and its route stage
re-issues `set_analysis_view` to a narrower set before it saves the database
and writes the manifest. Four bases are used, best first, and the basis is
always stated:

    tool_stated   the flow wrote the active set down (route_report_views.txt)
    db_probe      an <run>/index/views_<db>.txt from a read-only DB query
    check_timing  the View column of check_timing -verbose (SETUP views only)
    named_in_report  view names appearing in the report's own inference
                  messages. A FLOOR, not the set: a view that provoked no
                  message leaves no trace. Marked `>=`.

ORDERING, AND HOW A STALE STATE IS CAUGHT
-----------------------------------------
States are ordered by the TOOL-STATED `Generated on:` clock, not by filename
and not by mtime. A state whose clock precedes its predecessor's did not happen
in this sequence, and is reported as `OUT OF SEQUENCE` with the sequence it
does belong to named by md5 against any sibling evidence directory. rc5's
`logs/pnr_qor_after_post_hold_setup_recovery.rep` is such a file: byte-identical
to `attempt6-cts-evidence/`'s copy, clock 15:31, sitting between attempt 7's
16:23 and 16:49 files with nothing to say so.

WHAT IT DELIBERATELY DOES NOT DO
--------------------------------
No pass, no fail, no budget -- `signoff.py` judges. It does not launch a tool.
It writes nothing into `reports/`. Absent is `{"value": null, "why_absent": ...}`
and never a zero (evidence_report.py RULE 1).

Copyright 2026, SoC Labs (www.soclabs.org)
"""

import argparse
import gzip
import hashlib
import importlib.util
import json
import os
import re
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
SCHEMA = "soclabs.stage-timeline/1"


# ---------------------------------------------------------------------------
# run_index.py is the prior art for reading these files. Import it rather than
# copying its parsers: `parse_timing_summary` already handles the three tables,
# the absent-not-zero contract and the file:line convention, and
# `parse_qor_snapshots` already knows that an EMPTY report_qor cell is a
# measurement that was not taken rather than a zero.
# ---------------------------------------------------------------------------
def _load_run_index():
    path = os.path.join(HERE, "run_index.py")
    if not os.path.exists(path):
        sys.stderr.write("stage_timeline: %s not found -- this tool reuses its "
                         "parsers and will not duplicate them.\n" % path)
        sys.exit(2)
    spec = importlib.util.spec_from_file_location("run_index", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    for need in ("parse_timing_summary", "parse_qor_snapshots", "measured",
                 "absent", "num", "rel", "read_lines"):
        if not hasattr(mod, need):
            sys.stderr.write("stage_timeline: run_index.py has no %s(); the "
                             "prior art has moved. Not guessing.\n" % need)
            sys.exit(2)
    return mod


RI = _load_run_index()
measured, absent, num, rel = RI.measured, RI.absent, RI.num, RI.rel


# ---------------------------------------------------------------------------
# The state ladder.
#
# `key` is this tool's stable id. `phase` is the make target that ran it.
# `emits` records WHAT the flow writes for the state, which is the whole
# argument: a state with `emits: none` is one the flow cannot show you.
# ---------------------------------------------------------------------------
LADDER = [
    # key                          phase    label
    ("00_pre_place",               "place", "floorplan, before place_design"),
    ("01_place",                   "place", "place_design"),
    ("01b_place_opt",              "place", "opt_design -pre_cts"),
    ("01c_place_as_saved",         "place", "add_tieoffs -- the database CTS reads"),
    ("02_cts",                     "cts",   "ccopt_design (clock tree built)"),
    ("cts_after_ccopt",            "cts",   "ccopt_design, re-measured"),
    ("cts_after_post_cts",         "cts",   "opt_design -post_cts  (setup)"),
    ("cts_after_post_cts_hold",    "cts",   "opt_design -post_cts -hold"),
    ("cts_after_setup_recovery",   "cts",   "opt_design -post_cts  (2nd, recovery)"),
    ("03_cts_opt",                 "cts",   "end of CTS stage"),
    ("route_post_cts_as_read",     "route", "CTS database as route read it"),
    ("04_route",                   "route", "route_design -global_detail"),
    ("route_after_post_route_hold", "route", "opt_design -post_route -hold"),
    ("route_after_post_route",     "route", "opt_design -post_route (setup)"),
    ("05_route_opt",               "route", "end of route optimisation"),
    ("06_post_fill",               "route", "after fillers/metal fill"),
    ("07_streamed",                "route", "the database write_stream was called on"),
]
LADDER_ORDER = {k: i for i, (k, _, _) in enumerate(LADDER)}
LADDER_PHASE = {k: p for k, p, _ in LADDER}
LADDER_LABEL = {k: l for k, _, l in LADDER}

# `timing_summary_<token>.rep` -> state key. The eight the flow writes.
SUMMARY_TOKEN_STATE = {
    "00_pre_place": "00_pre_place", "01_place": "01_place",
    "01b_place_opt": "01b_place_opt", "02_cts": "02_cts",
    "03_cts_opt": "03_cts_opt", "04_route": "04_route",
    "05_route_opt": "05_route_opt", "06_post_fill": "06_post_fill",
}

# `pnr_qor_<slug>.rep`, written by pnr_qor_line, -> state key. These are the
# intra-stage states: same instrument as the stage summaries, so directly
# comparable with them, which is exactly why pnr_qor_line was written.
QOR_LINE_SLUG_STATE = {
    "after_ccopt_design": "cts_after_ccopt",
    "after_opt_design_post_cts": "cts_after_post_cts",
    "after_opt_design_post_cts_hold": "cts_after_post_cts_hold",
    "after_post_hold_setup_recovery": "cts_after_setup_recovery",
    "post_cts_as_read": "route_post_cts_as_read",
}

# report_qor snapshot name -> state key. Corroborated against the state's own
# setup WNS where the state has one; a disagreement is recorded, not averaged.
QOR_SNAPSHOT_STATE = {
    "place_design": "01_place",
    "opt_design_prects": "01b_place_opt",
    "ccopt_design": "02_cts",
    "opt_design_postcts": "cts_after_post_cts",
    "opt_design_postcts_hold": "cts_after_post_cts_hold",
    "opt_design_postroute_hold": "route_after_post_route_hold",
    "opt_design_postroute": "route_after_post_route",
}

# The `#  Command:` line inside an opt_design summary -> state key. Filed by
# COMMAND because the unsuffixed <prefix>.summary.gz is last-writer-wins: in
# rc5 attempt 7 ..._cts.summary.gz holds `-post_cts -hold`, in attempt 6 the
# same name holds `-post_cts`. Order matters -- longest match first.
OPT_COMMAND_STATE = [
    (re.compile(r"opt_design\b(?=.*\-pre_cts)"),                       "01b_place_opt"),
    (re.compile(r"opt_design\b(?=.*\-post_cts)(?=.*\-hold)"),          "cts_after_post_cts_hold"),
    (re.compile(r"opt_design\b(?=.*\-post_cts)"),                      "cts_after_post_cts"),
    (re.compile(r"opt_design\b(?=.*\-post_route)(?=.*\-hold)"),        "route_after_post_route_hold"),
    (re.compile(r"opt_design\b(?=.*\-post_route)(?=.*\-drv)"),         "route_after_post_route"),
    (re.compile(r"opt_design\b(?=.*\-post_route)"),                    "route_after_post_route"),
]

PATH_GROUPS = ["reg2reg", "reg2out", "in2reg", "in2out", "ClockGate", "Async"]
DRV_CHECKS = ["max_transition", "max_capacitance", "max_fanout"]


# ---------------------------------------------------------------------------
# Small readers. `read_lines` on a .gz, and the tool clock.
# ---------------------------------------------------------------------------
def read_text(path, limit=None):
    """Text of a report, transparently un-gzipped. Returns [] on any failure --
    the caller then records an absence naming the path, never a zero."""
    try:
        if path.endswith(".gz"):
            with gzip.open(path, "rt", errors="replace") as fh:
                data = fh.read(limit) if limit else fh.read()
        else:
            with open(path, "r", errors="replace") as fh:
                data = fh.read(limit) if limit else fh.read()
    except Exception:
        return []
    return data.split("\n")


_MON = {m: i + 1 for i, m in enumerate(
    "Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split())}


def tool_clock(lines, path):
    """The tool's own `#  Generated on:` stamp -> (iso, epoch).

    NOT mtime. mtime says when the bytes last landed; `Generated on:` says when
    the tool measured. rc5's `..._cts.summary.gz` has an mtime 68 s after its
    own stamp, and `logs/pnr_qor_after_post_hold_setup_recovery.rep` has an
    mtime from a run that overwrote its neighbours and not it. Ordering by mtime
    gets both wrong.
    """
    for i, ln in enumerate(lines[:40]):
        m = re.search(r"Generated on:\s*\w{3}\s+(\w{3})\s+(\d+)\s+"
                      r"(\d+):(\d+):(\d+)\s+(\d{4})", ln)
        if m:
            mon, day, hh, mm, ss, yr = m.groups()
            if mon in _MON:
                try:
                    ep = time.mktime((int(yr), _MON[mon], int(day), int(hh),
                                      int(mm), int(ss), 0, 0, -1))
                except Exception:
                    continue
                iso = "%s-%02d-%02dT%s:%s:%s" % (yr, _MON[mon], int(day), hh, mm, ss)
                return iso, ep, "%s:%d" % (path, i + 1), "tool-stated Generated on"
    # No stamp. mtime is the fallback and is labelled weak wherever it is used.
    try:
        ep = os.path.getmtime(path)
    except Exception:
        return None, None, None, "no Generated on: and no mtime"
    return (time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(ep)), ep,
            "%s (mtime)" % path, "file mtime -- WEAK, the tool stated no clock")


def md5_of(path):
    try:
        h = hashlib.md5()
        with open(path, "rb") as fh:
            for chunk in iter(lambda: fh.read(1 << 20), b""):
                h.update(chunk)
        return h.hexdigest()
    except Exception:
        return None


# ---------------------------------------------------------------------------
# Analysis views. Four bases, best first, and the basis always travels with
# the answer -- a hold number over one view is not the same measurement as one
# over four, and the reader must be able to see which they have.
# ---------------------------------------------------------------------------
def views_named_in(lines, path):
    """Views the report NAMES in its own inference messages. A FLOOR: a view
    that provoked no `Using master clock ... in view 'X'` line leaves no trace
    here, so this can undercount. Measured on rc5: it undercounts
    05_route_opt by one (check_timing over the same database lists
    typical_analysis_view; the summary does not name it)."""
    seen, first = {}, {}
    for i, ln in enumerate(lines):
        for m in re.finditer(r"in view '([^']+)'", ln):
            v = m.group(1)
            if v not in seen:
                seen[v] = True
                first[v] = i + 1
    return sorted(seen), first


def delaycalc_passes(lines):
    """`Total number of fetched objects` -- one per delay-calculation pass.
    Equals the active view count on a pre-route report; post-route with SI it
    is view_count x iterations, so it corroborates rather than proves."""
    return sum(1 for ln in lines if "Total number of fetched objects" in ln)


def read_route_report_views(run):
    """`reports/route_report_views.txt` -- the ONE place in the flow where the
    active view set is written down as a fact, and only for the route stage's
    last few reports plus the restored set."""
    p = os.path.join(run, "reports", "route_report_views.txt")
    if not os.path.exists(p):
        return None
    out = {"per_report": {}, "restored": None, "source": rel(p, run)}
    for i, ln in enumerate(read_text(p), 1):
        m = re.match(r"^(\S+\.\w+)\s+setup=\{([^}]*)\}\s+hold=\{([^}]*)\}", ln.strip())
        if m:
            out["per_report"][m.group(1)] = {
                "setup": m.group(2).split(), "hold": m.group(3).split(),
                "source": "%s:%d" % (rel(p, run), i)}
            continue
        m = re.match(r"^restored:\s*setup=\{([^}]*)\}\s*hold=\{([^}]*)\}", ln.strip())
        if m:
            out["restored"] = {"setup": m.group(1).split(),
                               "hold": m.group(2).split(),
                               "source": "%s:%d" % (rel(p, run), i)}
    return out


def read_db_probe(run):
    """`<run>/index/views_<dbtag>.txt`, if a read-only database probe has been
    run and left one. Format, one per line:  `<key> <value...>`, with
    ACTIVE_SETUP / ACTIVE_HOLD carrying a braced list. Absent is normal --
    this tool never launches Innovus."""
    d = os.path.join(run, "index")
    out = {}
    if not os.path.isdir(d):
        return out
    for fn in sorted(os.listdir(d)):
        m = re.match(r"^views_(\w+)\.txt$", fn)
        if not m:
            continue
        rec = {"source": rel(os.path.join(d, fn), run)}
        for ln in read_text(os.path.join(d, fn)):
            mm = re.match(r"^ACTIVE_(SETUP|HOLD)\s+(\d+)\s+\{([^}]*)\}", ln.strip())
            if mm:
                rec[mm.group(1).lower()] = mm.group(3).split()
        if "setup" in rec or "hold" in rec:
            out[m.group(1)] = rec
    return out


def read_check_timing_views(run, token):
    """The `View` column of `check_timing -verbose`. Innovus iterates the
    ACTIVE SETUP views, so this is a hard fact about the setup half and says
    nothing about hold. Only the pipe-bordered variant of the table has the
    column; the plain-text variant this flow emits pre-route does not."""
    p = os.path.join(run, "reports", "check_timing_%s.rep" % token)
    if not os.path.exists(p):
        return None
    seen = set()
    try:
        with open(p, "r", errors="replace") as fh:
            for ln in fh:
                if "|" not in ln:
                    continue
                cells = [c.strip() for c in ln.split("|")]
                if len(cells) < 5:
                    continue
                v = cells[-2]
                if re.match(r"^[A-Za-z][\w]*(_view|_hold|_setup|libset\w*)$", v):
                    seen.add(v)
    except Exception:
        return None
    return {"setup": sorted(seen), "source": rel(p, run) + " [View column]"} if seen else None


# ---------------------------------------------------------------------------
# opt_design's own summary. Its Hold-mode `all` column is the number every
# hold discussion on this project quotes, and it is NOT report_timing_summary.
# ---------------------------------------------------------------------------
def parse_opt_summary(path, run):
    """One `opt_design ... Final [SI Timing] Summary`.

    Returns the mode it printed (`setup` or `hold` -- never both, which is why
    a trade is invisible in one of these), the `all` column triple, the DRV
    Real/Total pairs, and Density. Files itself by the `#  Command:` line."""
    r = rel(path, run)
    lines = read_text(path)
    if not lines:
        return None
    out = {"file": r, "mode": None, "state": None, "command": None,
           "wns_ns": None, "tns_ns": None, "violating_paths": None,
           "all_paths": None, "density_pct": None, "si": False,
           "drv": {}, "source": r}
    iso, ep, csrc, cbasis = tool_clock(lines, r)
    out["clock"], out["clock_epoch"] = iso, ep
    out["clock_basis"] = cbasis

    for i, ln in enumerate(lines[:20]):
        m = re.search(r"#\s+Command:\s*(.+?)\s*$", ln)
        if m:
            out["command"] = m.group(1)
            out["command_source"] = "%s:%d" % (r, i + 1)
            for rx, st in OPT_COMMAND_STATE:
                if rx.search(m.group(1)):
                    out["state"] = st
                    break
            break
    out["si"] = any("Final SI Timing Summary" in ln for ln in lines[:40])

    for i, ln in enumerate(lines):
        m = re.match(r"^\|\s*(Setup|Hold) mode\s*\|", ln)
        if m:
            out["mode"] = m.group(1).lower()
            out["mode_source"] = "%s:%d" % (r, i + 1)
            for j in range(i, min(i + 8, len(lines))):
                cells = [c.strip() for c in lines[j].split("|")]
                if len(cells) < 3:
                    continue
                lab = cells[1]
                if lab.startswith("WNS"):
                    out["wns_ns"] = num(cells[2])
                    out["wns_source"] = "%s:%d [all column]" % (r, j + 1)
                elif lab.startswith("TNS"):
                    out["tns_ns"] = num(cells[2])
                elif lab.startswith("Violating"):
                    out["violating_paths"] = num(cells[2])
                elif lab.startswith("All Paths"):
                    out["all_paths"] = cells[2]
        m = re.match(r"^\|\s*(max_cap|max_tran|max_fanout|max_length)\s*\|"
                     r"\s*(\d+)\s*\((\d+)\)\s*\|\s*([-\d.]+)\s*\|"
                     r"\s*(\d+)\s*\((\d+)\)", ln)
        if m:
            out["drv"][m.group(1)] = {
                "real_nets": int(m.group(2)), "real_terms": int(m.group(3)),
                "worst": num(m.group(4)),
                "total_nets": int(m.group(5)), "total_terms": int(m.group(6)),
                "source": "%s:%d" % (r, i + 1),
                "note": "Real = violations the optimiser judged fixable; "
                        "Total = every violator. Two columns, two meanings."}
        m = re.match(r"^Density:\s*([\d.]+)%", ln)
        if m:
            out["density_pct"] = float(m.group(1))
            out["density_source"] = "%s:%d" % (r, i + 1)
    return out


# ---------------------------------------------------------------------------
# One state.
# ---------------------------------------------------------------------------
def blank_state(key, run):
    return {
        "state": key,
        "phase": LADDER_PHASE.get(key, "?"),
        "label": LADDER_LABEL.get(key, key),
        "ladder_order": LADDER_ORDER.get(key, 999),
        "clock": None, "clock_epoch": None, "clock_source": None,
        "clock_basis": None,
        "rts": None,          # channel: report_timing_summary
        "opt": [],            # channel: opt_design own summaries
        "qor": None,          # channel: report_qor snapshot row
        "views": None,
        "flags": [],
    }


def state_from_summary(key, path, run):
    """A state measured by report_timing_summary -- the comparable channel."""
    st = blank_state(key, run)
    r = rel(path, run)
    lines = read_text(path)
    parsed = RI.parse_timing_summary(path, os.path.abspath(run))
    iso, ep, csrc, cbasis = tool_clock(lines, r)
    st.update({"clock": iso, "clock_epoch": ep, "clock_source": csrc,
               "clock_basis": cbasis})

    m = parsed["metrics"]
    rts = {"file": r, "instrument": "report_timing_summary",
           "instrument_note":
               "run under timing_enable_simultaneous_setup_hold_mode "
               "(pnr_utils.tcl pnr_hold_summary), so setup and hold come from "
               "ONE timing update over every ACTIVE analysis view",
           "analysis": parsed["analysis"]}
    for ck in ("setup", "hold"):
        for f in ("wns_ns", "tns_ns", "fep"):
            rts["%s_%s" % (ck, f)] = m.get("%s_%s" % (ck, f))
        rts["%s_groups" % ck] = m.get("%s_groups" % ck)
    for c in DRV_CHECKS:
        for f in ("wns", "tns", "fep"):
            rts["drv_%s_%s" % (c, f)] = m.get("drv_%s_%s" % (c, f))
    st["rts"] = rts

    named, first = views_named_in(lines, r)
    st["views_named"] = {"views": named, "count": len(named),
                         "basis": "named_in_report",
                         "caveat": "FLOOR, not the set -- a view that provoked "
                                   "no inference message leaves no trace here",
                         "source": r}
    st["delaycalc_passes"] = delaycalc_passes(lines)
    return st


def state_from_qor_line(key, path, run):
    """`pnr_qor_<slug>.rep` -- pnr_qor_line's scratch report. SAME command and
    SAME mode as a stage summary (`report_timing_summary -checks {setup hold
    drv}` under simultaneous mode), so it is on the `rts` channel and is
    directly comparable with the stage summaries either side of it. That is
    the whole reason these intra-stage states can be read at all."""
    st = state_from_summary(key, path, run)
    st["rts"]["instrument_note"] += (
        "; emitted mid-stage by pnr_qor_line, not at a stage boundary")
    return st


# ---------------------------------------------------------------------------
# Building the timeline.
# ---------------------------------------------------------------------------
def collect(run, report_dirs=None, log_dirs=None):
    """Gather every state from one SEQUENCE of directories.

    A run directory is one sequence (reports/ + logs/). A sibling
    `attempt*-evidence` directory is another -- a superseded attempt kept
    deliberately, whose states are real measurements of a different
    configuration and must not be interleaved with the live ones."""
    run = os.path.abspath(run)
    rds = report_dirs if report_dirs is not None else [os.path.join(run, "reports")]
    lds = log_dirs if log_dirs is not None else [os.path.join(run, "logs")]
    rd, ld = rds[0], lds[0]
    states = {}
    notes = []
    unfiled = []

    # --- 1. the eight stage summaries ------------------------------------
    for d in rds:
        for fn in (sorted(os.listdir(d)) if os.path.isdir(d) else []):
            m = re.match(r"^timing_summary_(.+)\.rep$", fn)
            if not m:
                continue
            key = SUMMARY_TOKEN_STATE.get(m.group(1))
            if key is None:
                unfiled.append({"file": rel(os.path.join(d, fn), run),
                                "why": "timing_summary token '%s' is not in the "
                                       "state ladder" % m.group(1)})
                continue
            if key in states:
                continue
            states[key] = state_from_summary(key, os.path.join(d, fn), run)

    # --- 2. the intra-stage pnr_qor_line reports -------------------------
    for d in lds:
      for fn in (sorted(os.listdir(d)) if os.path.isdir(d) else []):
        m = re.match(r"^pnr_qor_(.+)\.rep$", fn)
        if not m:
            continue
        key = QOR_LINE_SLUG_STATE.get(m.group(1))
        p = os.path.join(d, fn)
        if key is None:
            unfiled.append({"file": rel(p, run),
                            "why": "pnr_qor slug '%s' is not in the state "
                                   "ladder" % m.group(1)})
            continue
        if key in states:
            # Two reports for one state. Keep the one that is not out of
            # sequence, and say both existed.
            notes.append("state %s has two reports: %s and %s"
                         % (key, states[key]["rts"]["file"], rel(p, run)))
            continue
        states[key] = state_from_qor_line(key, p, run)

    # --- 3. opt_design's own summaries, filed by COMMAND -----------------
    for base in rds:
        for fn in sorted(os.listdir(base)) if os.path.isdir(base) else []:
            if not fn.endswith(".summary.gz"):
                continue
            rec = parse_opt_summary(os.path.join(base, fn), run)
            if rec is None or rec["state"] is None:
                unfiled.append({"file": rel(os.path.join(base, fn), run),
                                "why": "no `#  Command:` line matching a known "
                                       "opt_design form; not filed by name"})
                continue
            states.setdefault(rec["state"], blank_state(rec["state"], run))
            states[rec["state"]]["opt"].append(rec)
    # ...and the copies pnr_opt_hold_summary made, which are the only surviving
    # record of any summary the route stage later deleted (4_route.tcl:985
    # unlinks reports/*_hold.summary* before route's own hold pass runs).
    for d in rds:
      for fn in (sorted(os.listdir(d)) if os.path.isdir(d) else []):
        m = re.match(r"^hold_opt_(.+)\.rep$", fn)
        if not m:
            continue
        p = os.path.join(d, fn)
        for rec in split_hold_opt_copy(p, run):
            if rec["state"] is None:
                continue
            states.setdefault(rec["state"], blank_state(rec["state"], run))
            have = {(o.get("command"), o.get("clock")) for o in states[rec["state"]]["opt"]}
            if (rec.get("command"), rec.get("clock")) not in have:
                rec["note"] = ("recovered from %s -- pnr_opt_hold_summary's copy. "
                               "The original was deleted by 4_route.tcl:985."
                               % rel(p, run))
                states[rec["state"]]["opt"].append(rec)

    # --- 4. report_qor snapshots: instances, area, utilisation -----------
    qor_rows, qor_files = {}, {}
    for d in rds:
      for fn in (sorted(os.listdir(d)) if os.path.isdir(d) else []):
        if not re.match(r"^qor_.+\.rep$", fn):
            continue
        rows = RI.parse_qor_snapshots(os.path.join(d, fn), run)
        for snap, row in rows.items():
            # Later files repeat earlier rows verbatim; keep the first sighting
            # and record that the row is cumulative history, not a measurement
            # this file took.
            if snap not in qor_rows:
                qor_rows[snap], qor_files[snap] = row, fn
    for snap, row in qor_rows.items():
        key = QOR_SNAPSHOT_STATE.get(snap)
        if key is None:
            continue
        states.setdefault(key, blank_state(key, run))
        states[key]["qor"] = {
            "snapshot": snap, "file": qor_files[snap], "row": row,
            "instrument": "report_qor -format text snapshot table",
            "instrument_note":
                "SETUP ONLY -- this table has no hold column, which is why a "
                "hold regression cannot appear in it. Columns per "
                "run_index.parse_qor_snapshots.",
        }

    # --- 3b. state records written by hooks/post_place.tcl and
    #         hooks/post_route.tcl ------------------------------------------
    # These carry what no report in the flow carries: the ACTIVE analysis view
    # set at the instant of the state, taken from the tool rather than inferred,
    # plus a census of the database as it was actually saved. Their timing
    # triples are on the `rts` channel (the hook takes them with pnr_qor_line,
    # i.e. report_timing_summary under simultaneous mode), so they compare
    # directly with every stage summary.
    for d in rds:
        for fn in (sorted(os.listdir(d)) if os.path.isdir(d) else []):
            m = re.match(r"^stage_state_(.+)\.json$", fn)
            if not m:
                continue
            path = os.path.join(d, fn)
            try:
                with open(path) as fh:
                    rec = json.load(fh)
            except Exception as e:
                unfiled.append({"file": rel(path, run),
                                "why": "stage_state json did not parse: %s" % e})
                continue
            key = rec.get("state") or m.group(1)
            st = states.setdefault(key, blank_state(key, run))
            st["hook_record"] = {"file": rel(path, run), "record": rec}
            if st.get("rts") is None and rec.get("setup", {}).get("wns_ns") is not None:
                r = rel(path, run)
                mk = lambda v, u: (absent("the hook recorded no value", [r])
                                   if v in (None, "N/A") else
                                   measured(num(v), r, u))
                st["rts"] = {
                    "file": r, "instrument": "report_timing_summary",
                    "instrument_note":
                        "recorded by a project hook via pnr_qor_line -- the same "
                        "command and mode as every timing_summary_<stage>.rep",
                    "analysis": {},
                    "setup_wns_ns": mk(rec["setup"]["wns_ns"], "ns"),
                    "setup_tns_ns": mk(rec["setup"]["tns_ns"], "ns"),
                    "setup_fep": mk(rec["setup"]["fep"], "paths"),
                    "hold_wns_ns": mk(rec.get("hold", {}).get("wns_ns"), "ns"),
                    "hold_tns_ns": mk(rec.get("hold", {}).get("tns_ns"), "ns"),
                    "hold_fep": mk(rec.get("hold", {}).get("fep"), "paths"),
                }
                for c in DRV_CHECKS:
                    dd = (rec.get("drv") or {}).get(c) or {}
                    for f, kk in (("wns", "wns"), ("tns", "tns"), ("fep", "fep")):
                        st["rts"]["drv_%s_%s" % (c, f)] = mk(dd.get(kk), "")
            av = rec.get("analysis_views") or {}
            if av.get("setup") is not None or av.get("hold") is not None:
                st["hook_views"] = {"setup": av.get("setup"),
                                    "hold": av.get("hold"),
                                    "source": rel(path, run),
                                    "basis": av.get("basis")}
            if rec.get("written") and not st.get("clock"):
                st["clock"] = rec["written"]
                st["clock_basis"] = ("the hook's own wall clock -- the tool "
                                     "stated none in this record")
                try:
                    st["clock_epoch"] = time.mktime(time.strptime(
                        rec["written"], "%Y-%m-%dT%H:%M:%S"))
                except Exception:
                    pass

    # --- 4b. a state with no report_timing_summary still HAPPENED --------
    # Take its clock from whatever did measure it, so it takes its true place
    # in the sequence and appears in the progression table as a row with empty
    # timing columns. A gap you can see is worth ten paragraphs saying there is
    # one.
    for key, st in states.items():
        if st.get("clock_epoch") or not st.get("opt"):
            continue
        best = min((o for o in st["opt"] if o.get("clock_epoch")),
                   key=lambda o: o["clock_epoch"], default=None)
        if best:
            st["clock"], st["clock_epoch"] = best["clock"], best["clock_epoch"]
            st["clock_source"] = best["file"]
            st["clock_basis"] = ("tool-stated Generated on, from the "
                                 "opt_design summary -- no report_timing_"
                                 "summary exists for this state")

    # --- 5. reconcile the opt summaries by CLOCK -------------------------
    # `opt_design -post_cts` and `opt_design -post_cts` are the same command
    # twice: the setup pass and, when CTS_POST_HOLD_SETUP is on, the recovery
    # pass. The command line cannot tell them apart -- only the clock can, and
    # only ONE of the two survives on disk anyway, because the unsuffixed
    # <prefix>.summary.gz is last-writer-wins. Send each record to whichever
    # candidate state's own clock it is nearest, and say so.
    AMBIG = {
        "cts_after_post_cts": ["cts_after_post_cts", "cts_after_setup_recovery"],
        "route_after_post_route": ["route_after_post_route"],
    }
    for key in list(states):
        keep = []
        for rec in states[key].get("opt", []):
            cands = AMBIG.get(key)
            if not cands or rec.get("clock_epoch") is None:
                keep.append(rec)
                continue
            best, bestd = key, None
            for c in cands:
                st = states.get(c)
                if not st or not st.get("clock_epoch"):
                    continue
                d = abs(st["clock_epoch"] - rec["clock_epoch"])
                if bestd is None or d < bestd:
                    best, bestd = c, d
            if best != key:
                rec["refiled_by_clock"] = (
                    "filed as %s by its `#  Command:` line, moved to %s because "
                    "its clock %s is %ds from that state's and further from "
                    "%s's. Two passes issue this identical command."
                    % (key, best, rec.get("clock"), int(bestd or 0), key))
                states.setdefault(best, blank_state(best, run))
                states[best]["opt"].append(rec)
            else:
                keep.append(rec)
        states[key]["opt"] = keep

    # ...and again, because reconciliation may have moved an opt summary onto
    # a state that had none when 4b ran.
    for key, st in states.items():
        if st.get("clock_epoch") or not st.get("opt"):
            continue
        best = min((o for o in st["opt"] if o.get("clock_epoch")),
                   key=lambda o: o["clock_epoch"], default=None)
        if best:
            st["clock"], st["clock_epoch"] = best["clock"], best["clock_epoch"]
            st["clock_source"] = best["file"]
            st["clock_basis"] = ("tool-stated Generated on, from the "
                                 "opt_design summary -- no report_timing_"
                                 "summary exists for this state")
    return run, states, notes, unfiled, {"rows": qor_rows, "files": qor_files}


def split_hold_opt_copy(path, run):
    """`hold_opt_<state>.rep` is pnr_opt_hold_summary's verbatim copy of one or
    more `*.summary.gz` files, each behind a `==== <path> ====` banner. Split
    and parse each as an opt summary."""
    lines = read_text(path)
    out, cur, curname = [], [], None
    for ln in lines + ["==== END ===="]:
        m = re.match(r"^====\s+(\S+)\s+====$", ln.strip())
        if m:
            if cur and curname:
                out.append(("\n".join(cur), curname))
            cur, curname = [], m.group(1)
            continue
        if curname:
            cur.append(ln)
    recs = []
    r = rel(path, run)
    for text, orig in out:
        lines2 = text.split("\n")
        rec = {"file": r, "recovered_from": orig, "mode": None, "state": None,
               "command": None, "wns_ns": None, "tns_ns": None,
               "violating_paths": None, "all_paths": None,
               "density_pct": None, "si": False, "drv": {}, "source": r}
        iso, ep, _, cbasis = tool_clock(lines2, r)
        rec["clock"], rec["clock_epoch"], rec["clock_basis"] = iso, ep, cbasis
        for ln in lines2[:20]:
            m = re.search(r"#\s+Command:\s*(.+?)\s*$", ln)
            if m:
                rec["command"] = m.group(1)
                for rx, st in OPT_COMMAND_STATE:
                    if rx.search(m.group(1)):
                        rec["state"] = st
                        break
                break
        rec["si"] = any("Final SI Timing Summary" in l for l in lines2[:40])
        for i, ln in enumerate(lines2):
            m = re.match(r"^\|\s*(Setup|Hold) mode\s*\|", ln)
            if m:
                rec["mode"] = m.group(1).lower()
                for j in range(i, min(i + 8, len(lines2))):
                    cells = [c.strip() for c in lines2[j].split("|")]
                    if len(cells) < 3:
                        continue
                    if cells[1].startswith("WNS"):
                        rec["wns_ns"] = num(cells[2])
                    elif cells[1].startswith("TNS"):
                        rec["tns_ns"] = num(cells[2])
                    elif cells[1].startswith("Violating"):
                        rec["violating_paths"] = num(cells[2])
                    elif cells[1].startswith("All Paths"):
                        rec["all_paths"] = cells[2]
            m = re.match(r"^Density:\s*([\d.]+)%", ln)
            if m:
                rec["density_pct"] = float(m.group(1))
        if rec["command"]:
            recs.append(rec)
    return recs


# ---------------------------------------------------------------------------
# Views, resolved per state, best basis first.
# ---------------------------------------------------------------------------
def resolve_views(run, states):
    rrv = read_route_report_views(run)
    probe = read_db_probe(run)
    # `check_timing_<token>.rep` tokens map 1:1 onto the stage-summary tokens.
    ct = {}
    for tok, key in SUMMARY_TOKEN_STATE.items():
        got = read_check_timing_views(run, tok)
        if got:
            ct[key] = got
    # Which saved database each state's numbers were taken over.
    #
    # `routed` is DELIBERATELY NOT MAPPED. It is the database the GDS was
    # streamed from, and its active view set is the NARROWED one -- 4_route.tcl
    # re-issues set_analysis_view between `06_post_fill`'s reports and
    # `pnr_write_db routed`. Measured on rc5: route_preopt has 2 setup / 4 hold
    # active, routed has 1 setup / 3 hold. Attaching the routed DB's view set to
    # 06_post_fill would state a scope those numbers were not measured over,
    # which is the defect this tool exists to catch, committed by the tool.
    # It is reported on its own in the ANALYSIS VIEWS section.
    DB_FOR_STATE = {
        "00_pre_place": "fplan",
        "01b_place_opt": "placed",     # the DB is one step later (add_tieoffs)
        "03_cts_opt": "cts",
        "05_route_opt": "route_preopt",
        "07_streamed": "routed",
    }
    for key, st in states.items():
        cands = []
        hv = st.get("hook_views")
        if hv:
            cands.append({
                "basis": "hook_record", "setup": hv.get("setup"),
                "hold": hv.get("hold"), "source": hv["source"],
                "note": "recorded live at the state by a project hook: %s"
                        % (hv.get("basis") or "get_db analysis_views")})
        db = DB_FOR_STATE.get(key)
        if db and db in probe:
            cands.append({
                "basis": "db_probe",
                "setup": probe[db].get("setup"), "hold": probe[db].get("hold"),
                "source": probe[db]["source"],
                "note": "read-only query of the saved database %s: "
                        "get_db analysis_views .is_active/.is_setup/.is_hold" % db})
        if key in ct:
            cands.append({
                "basis": "check_timing", "setup": ct[key]["setup"], "hold": None,
                "source": ct[key]["source"],
                "note": "check_timing -verbose iterates the ACTIVE SETUP views. "
                        "Says nothing about hold."})
        nm = st.get("views_named")
        if nm:
            cands.append({
                "basis": "named_in_report", "setup": None, "hold": None,
                "all_named": nm["views"], "count_floor": nm["count"],
                "source": nm["source"], "note": nm["caveat"]})
        st["views"] = {"candidates": cands,
                       "best": cands[0]["basis"] if cands else None}
        if not cands:
            st["views"] = absent(
                "no view evidence for state %s -- no db probe, no check_timing "
                "report and no report to read names out of" % key)
    if rrv:
        for st in states.values():
            if st["phase"] == "route":
                st.setdefault("route_view_note", rrv)
    return rrv, probe


# ---------------------------------------------------------------------------
# Sequencing, and the stale-state catch.
# ---------------------------------------------------------------------------
def sequence(run, states, extra_dirs):
    """Order by tool clock, and separate the states that did not happen in
    THIS sequence.

    A state whose tool clock runs backwards against the ladder is not part of
    the run in front of you: it is a survivor of an earlier attempt that the
    later attempt did not overwrite, because the later attempt did not produce
    that state at all. rc5's
    `logs/pnr_qor_after_post_hold_setup_recovery.rep` is exactly this -- clock
    15:31, sitting between attempt 7's 16:23 and 16:49 files, byte-identical to
    `attempt6-cts-evidence/`'s copy, and describing the single worst state in
    the whole run.

    Such a state is returned as an ORPHAN, never spliced into the chain.
    Splicing it produces two fictional transitions (01b_place_opt -> it, and
    it -> 02_cts) that no tool ever performed, and buries the two real ones.
    """
    have = [s for s in states.values() if s.get("clock_epoch")]
    have.sort(key=lambda s: (s["clock_epoch"], s["ladder_order"]))
    noclock = [s for s in states.values() if not s.get("clock_epoch")]

    # md5 index of every sibling evidence tree, so an orphan can be ATTRIBUTED
    # rather than merely doubted.
    sibs = {}
    for d in extra_dirs:
        if not os.path.isdir(d):
            continue
        for fn in os.listdir(d):
            pth = os.path.join(d, fn)
            if os.path.isfile(pth):
                h = md5_of(pth)
                if h:
                    sibs.setdefault(h, []).append(
                        os.path.join(os.path.basename(d), fn))

    # Walk the LADDER. A state whose clock is earlier than the newest clock
    # seen at a lower ladder position cannot belong to this sequence.
    by_ladder = sorted(have, key=lambda s: s["ladder_order"])
    newest = None
    for s in by_ladder:
        if newest is not None and s["clock_epoch"] < newest:
            s["flags"].append("OUT-OF-SEQUENCE")
        else:
            newest = s["clock_epoch"]

    chain, orphans = [], []
    for s in by_ladder:
        (orphans if "OUT-OF-SEQUENCE" in s["flags"] else chain).append(s)

    for s in orphans:
        f = s.get("rts", {}).get("file") if s.get("rts") else None
        if f:
            h = md5_of(os.path.join(run, f))
            if h and h in sibs:
                s["attributed_to"] = sibs[h]
            else:
                s["attributed_to"] = None

    # The chain is now in ladder order. Assert the clock agrees; if it does
    # not, the ladder is wrong for this flow and that is worth saying.
    for a, b in zip(chain, chain[1:]):
        if a["clock_epoch"] > b["clock_epoch"]:
            b["flags"].append("LADDER-ORDER-DISAGREES-WITH-CLOCK")
    return chain, orphans, noclock


# ---------------------------------------------------------------------------
# Metric access and deltas.
# ---------------------------------------------------------------------------
def mval(st, name):
    """A metric on the `rts` channel, or None. Never a zero for absent."""
    if not st.get("rts"):
        return None
    v = st["rts"].get(name)
    if isinstance(v, dict):
        return v.get("value")
    return v


def scale_of(st, chain):
    """Instances / area / utilisation for a state, and WHERE the number is
    from.

    `report_qor` writes a row only at an optimisation snapshot, so most states
    have none of their own. Carrying the last measured value forward is what a
    reader does anyway -- but a carried number is a statement about an EARLIER
    database, and anything added since is not in it. rc5's `06_post_fill` is
    the case that matters: 116,840 filler cells go in after the last
    `report_qor` row, so a carried 243,005 understates the streamed design by a
    third. Carried values are marked `~` and the source names the state.
    """
    q = st.get("qor")
    if q:
        r = q["row"]
        get = lambda c: (None if r[c].get("empty") else r[c].get("value"))
        d = get("util_pct")
        if d is None:
            for o in st.get("opt", []):
                if o.get("density_pct") is not None:
                    d = o["density_pct"]
                    break
        return {"instances": get("instances"), "area_um2": get("area_um2"),
                "util_pct": d, "carried_from": None,
                "source": "report_qor `%s` in %s" % (q["snapshot"], q["file"])}
    order = sorted(chain, key=lambda x: x["ladder_order"])
    prev = None
    for x in order:
        if x is st:
            break
        if x.get("qor"):
            prev = x
    if prev is None:
        return {"instances": None, "area_um2": None, "util_pct": None,
                "carried_from": None,
                "source": None,
                "why_absent": "no report_qor row for %s and none before it"
                              % st["state"]}
    got = scale_of(prev, chain)
    got["carried_from"] = prev["state"]
    got["source"] = "CARRIED from %s (%s)" % (prev["state"], got["source"])
    return got


# Direction of goodness for every metric this tool compares.
#   +1 : bigger is better (WNS, TNS -- both are slacks)
#   -1 : bigger is worse  (FEP, violator counts)
METRIC_DIR = {
    "setup_wns_ns": +1, "setup_tns_ns": +1, "setup_fep": -1,
    "hold_wns_ns": +1, "hold_tns_ns": +1, "hold_fep": -1,
    "drv_max_transition_fep": -1, "drv_max_capacitance_fep": -1,
    "drv_max_fanout_fep": -1,
}
METRIC_UNIT = {k: ("ns" if k.endswith("_ns") else "eps") for k in METRIC_DIR}


def transitions(ordered, chain=None):
    """Consecutive same-channel deltas, with a verdict per metric and the
    exchange rate when a state buys one metric with another."""
    out = []
    usable = [s for s in ordered if s.get("rts")]
    pos = {id(s): i for i, s in enumerate(ordered)}
    for a, b in zip(usable, usable[1:]):
        skipped = [x["state"] for x in ordered[pos[id(a)] + 1:pos[id(b)]]]
        t = {"from": a["state"], "to": b["state"],
             "from_clock": a["clock"], "to_clock": b["clock"],
             "phase": b["phase"], "label": b["label"],
             "metrics": {}, "worse": [], "better": [], "flags": [],
             "spans_unmeasured_states": skipped}
        for m, direction in METRIC_DIR.items():
            va, vb = mval(a, m), mval(b, m)
            if va is None or vb is None:
                t["metrics"][m] = {"from": va, "to": vb, "delta": None,
                                   "verdict": "NOT MEASURED at one end"}
                continue
            d = vb - va
            if abs(d) < 5e-4 and m.endswith("_ns"):
                verdict = "same"
            elif d == 0:
                verdict = "same"
            elif d * direction > 0:
                verdict = "better"
            else:
                verdict = "WORSE"
            rec = {"from": va, "to": vb, "delta": d, "verdict": verdict}
            if m.endswith("_fep") and va == 0 and vb > 0:
                rec["broke_clean"] = True
                t["flags"].append("BROKE-CLEAN:%s" % m)
            t["metrics"][m] = rec
            if verdict == "WORSE":
                t["worse"].append(m)
            elif verdict == "better":
                t["better"].append(m)

        # Comparability. Two states measured over different view sets are not
        # the same measurement, and a delta between them is a difference of
        # instruments as much as of design.
        na = a.get("views_named", {}).get("count")
        nb = b.get("views_named", {}).get("count")
        if na is not None and nb is not None and na != nb:
            t["flags"].append("VIEW-COUNT-CHANGED:%s->%s" % (na, nb))
        pa = (a["rts"]["analysis"].get("parasitics") or {}).get("value")
        pb = (b["rts"]["analysis"].get("parasitics") or {}).get("value")
        if pa != pb:
            t["flags"].append("PARASITICS-CHANGED:%s->%s" % (pa, pb))

        # The exchange rate. Only meaningful when setup and hold moved in
        # opposite directions -- that is a decision the flow made, not noise.
        sw = t["metrics"].get("setup_wns_ns", {}).get("delta")
        hw = t["metrics"].get("hold_wns_ns", {}).get("delta")
        if sw is not None and hw is not None and sw * hw < 0 \
                and (abs(sw) > 5e-4 or abs(hw) > 5e-4):
            gain, loss = (sw, hw) if sw > 0 else (hw, sw)
            gname, lname = ("setup", "hold") if sw > 0 else ("hold", "setup")
            gps, lps = gain * 1000.0, -loss * 1000.0
            ratio = (lps / gps) if abs(gps) > 1e-9 else None
            t["trade"] = {
                "gained": gname, "gained_ps": round(gps, 1),
                "paid": lname, "paid_ps": round(lps, 1),
                "ratio_paid_per_gained": (round(ratio, 1) if ratio is not None
                                          else None),
                "verdict": ("LOSS" if (ratio is not None and ratio > 1.0)
                            else "gain"),
                "text": "bought %.0f ps of %s by giving up %.0f ps of %s"
                        % (gps, gname, lps, lname),
            }

        # Scale: what it cost in cells and area.
        ch = chain if chain is not None else ordered
        sa, sb = scale_of(a, ch), scale_of(b, ch)
        t["scale"] = {
            "insts_from": sa["instances"], "insts_to": sb["instances"],
            "area_from": sa["area_um2"], "area_to": sb["area_um2"],
            "util_from": sa["util_pct"], "util_to": sb["util_pct"],
            "source_from": sa["source"], "source_to": sb["source"],
            "carried_from": [sa.get("carried_from"), sb.get("carried_from")],
        }
        out.append(t)
    return out


def severity(t):
    """Worst first, for a reader with thirty seconds.

    TNS IS EXCLUDED. It is unbounded -- rc5's pre-place setup TNS is
    -1,304,257 ns -- so any delta on it swamps every other metric and the
    ranking degenerates into "which state ran earliest". WNS in picoseconds
    and endpoint counts are bounded and are what a decision is judged on.

    A clean metric going dirty outranks any amount of an already-dirty metric
    getting worse, and a timing endpoint outranks a DRV pin: shipping with 66
    failing hold endpoints is a different kind of fact from shipping with two
    more max_cap pins.
    """
    s = 0.0
    for f in t["flags"]:
        if f.startswith("BROKE-CLEAN:"):
            m = f.split(":", 1)[1]
            s += 1e9 if m in ("setup_fep", "hold_fep") else 1e6
    for m in t["worse"]:
        d = t["metrics"][m]["delta"]
        if d is None or m.endswith("_tns_ns"):
            continue
        if m.endswith("_ns"):
            s += abs(d) * 1000.0          # picoseconds of slack lost
        elif m.endswith("_fep"):
            s += abs(d) * (100.0 if m in ("setup_fep", "hold_fep") else 1.0)
    return s


# ---------------------------------------------------------------------------
# Rendering. One table, worst first, every number carrying its scope.
# ---------------------------------------------------------------------------
# WNS is quoted in picoseconds because that is the unit a timing decision is
# argued in; TNS stays in nanoseconds because it is unbounded (rc5's pre-place
# setup TNS is -1,304,258 ns) and "589,893,875 ps worse" tells a reader nothing.
def metric_line(name, r, word):
    a, b, d = r["from"], r["to"], r["delta"]
    tail = ""
    if r.get("broke_clean"):
        tail = "   <<< BROKE CLEAN: 0 failing endpoints -> %d" % int(b)
    if name.endswith("_tns_ns"):
        return "%-26s %12.3f -> %12.3f   %s by %.3f ns%s" % (
            name, a, b, word, abs(d), tail)
    if name.endswith("_ns"):
        return "%-26s %12.3f -> %12.3f   %s by %.0f ps%s" % (
            name, a, b, word, abs(d) * 1000.0, tail)
    return "%-26s %12d -> %12d   %s by %d endpoints%s" % (
        name, int(a), int(b), word, int(abs(d)), tail)


def f_ns(v, w=9):
    return ("%*s" % (w, "-")) if v is None else ("%*.3f" % (w, v))


def f_int(v, w=7):
    return ("%*s" % (w, "-")) if v is None else ("%*d" % (w, int(v)))


def f_pct(v, w=6):
    return ("%*s" % (w, "-")) if v is None else ("%*.2f" % (w, v))


def render_regressions(w, trans, indent=" "):
    bad = sorted([t for t in trans if t["worse"]], key=severity, reverse=True)
    if not bad:
        w("%sNO STATE MADE ANY TRACKED METRIC WORSE.\n\n" % indent)
        return
    w("%sWHAT GOT WORSE, WORST FIRST  (%d of %d transitions regressed something)\n\n"
      % (indent, len(bad), len(trans)))
    for n, t in enumerate(bad, 1):
        w("%s%2d. %-28s -> %-28s  [%s]\n"
          % (indent, n, t["from"], t["to"], t["phase"]))
        w("%s    %s\n" % (indent, t["label"]))
        for m in sorted(t["worse"],
                        key=lambda k: -abs(t["metrics"][k]["delta"] or 0)):
            w("%s      %s\n" % (indent, metric_line(m, t["metrics"][m], "WORSE")))
        for m in sorted(t["better"],
                        key=lambda k: -abs(t["metrics"][k]["delta"] or 0)):
            w("%s      %s\n" % (indent, metric_line(m, t["metrics"][m], "better")))
        if t.get("trade"):
            tr = t["trade"]
            if tr["verdict"] == "LOSS":
                w("%s      >> BAD TRADE: %s.  %s ps GIVEN per ps GAINED.\n"
                  % (indent, tr["text"], tr["ratio_paid_per_gained"]))
            else:
                w("%s      >> trade: %s  (%s ps given per ps gained)\n"
                  % (indent, tr["text"], tr["ratio_paid_per_gained"]))
        sc = t["scale"]
        if sc["util_from"] is not None and sc["util_to"] is not None \
                and (sc["util_from"] != sc["util_to"]
                     or sc["insts_from"] != sc["insts_to"]):
            carried = [c for c in sc["carried_from"] if c]
            w("%s      scale: utilisation %.2f%% -> %.2f%%   instances %s -> %s%s\n"
              % (indent, sc["util_from"], sc["util_to"],
                 sc["insts_from"], sc["insts_to"],
                 ("   (~carried from %s)" % ", ".join(carried)) if carried else ""))
        if t.get("spans_unmeasured_states"):
            w("%s      !! this delta SPANS %d state(s) the flow did not measure: %s\n"
              % (indent, len(t["spans_unmeasured_states"]),
                 ", ".join(t["spans_unmeasured_states"])))
            w("%s         so it cannot be attributed to one pass.\n" % indent)
        for f in t["flags"]:
            if not f.startswith("BROKE-CLEAN"):
                w("%s      !! %s -- the two states are NOT the same measurement\n"
                  % (indent, f))
        w("\n")


def same_metrics(a, b):
    """True when two states report identical numbers on every tracked metric.
    Two such states are ONE state measured twice -- a stage boundary summary
    re-taken a minute after the intra-stage one, or a database written and read
    back. Saying so is worth a column: it turns "why are there thirteen rows"
    into "there are nine states and four confirmations"."""
    if not (a.get("rts") and b.get("rts")):
        return False
    for m in list(METRIC_DIR) + ["drv_max_transition_wns", "drv_max_capacitance_wns"]:
        va, vb = mval(a, m), mval(b, m)
        if va is None and vb is None:
            continue
        if va is None or vb is None or abs(va - vb) > 5e-6:
            return False
    return True


def views_cell(s):
    """What to print in the `views` column.

    Prefer a MEASURED active set -- a hook record taken at the state, or a
    read-only probe of the database it was saved to -- over the count of names
    the report happens to mention, which is only a floor. The prefix says which
    it is: `2/4` is measured (setup/hold), `>=4` is the floor.
    """
    v = s.get("views") or {}
    for c in (v.get("candidates") or []):
        if c["basis"] in ("hook_record", "db_probe") and c.get("setup") is not None:
            return "%d/%d" % (len(c["setup"] or []), len(c["hold"] or []))
    nm = s.get("views_named") or {}
    return (">=%d" % nm["count"]) if nm.get("count") is not None else "  -"


def render_table(w, chain, indent="  "):
    w("%s%-28s %-6s %s %s %s | %s %s %s | %s %s | %s %s %s %s\n"
      % (indent, "state", "clock",
         " setupWNS", "   setupTNS", " sFEP",
         "  holdWNS", "    holdTNS", " hFEP",
         "tranF", " capF", " insts", " area(um2)", " util%", "views"))
    w("%s%s\n" % (indent, "-" * 126))
    prev = None
    for s in chain:
        if not s.get("rts"):
            sc = scale_of(s, chain)
            c = "~" if sc.get("carried_from") else " "
            w("%s%-28s %-6s %s %s %s | %s %s %s | %s %s |%s%s %s %s %5s   %s\n"
              % (indent, s["state"], (s["clock"] or "")[11:16],
                 f_ns(None), f_ns(None, 11), f_int(None, 5),
                 f_ns(None), f_ns(None, 11), f_int(None, 5),
                 f_int(None, 5), f_int(None, 5),
                 c, f_int(sc["instances"], 7), f_int(sc["area_um2"], 10),
                 f_pct(sc["util_pct"]), views_cell(s),
                 "<< NOT MEASURED (no report_timing_summary)"))
            prev = None
            continue
        sc = scale_of(s, chain)
        c = "~" if sc.get("carried_from") else " "
        mark = "  = prev" if (prev is not None and same_metrics(prev, s)) else ""
        w("%s%-28s %-6s %s %s %s | %s %s %s | %s %s |%s%s %s %s %5s%s\n"
          % (indent, s["state"], (s["clock"] or "")[11:16],
             f_ns(mval(s, "setup_wns_ns")), f_ns(mval(s, "setup_tns_ns"), 11),
             f_int(mval(s, "setup_fep"), 5),
             f_ns(mval(s, "hold_wns_ns")), f_ns(mval(s, "hold_tns_ns"), 11),
             f_int(mval(s, "hold_fep"), 5),
             f_int(mval(s, "drv_max_transition_fep"), 5),
             f_int(mval(s, "drv_max_capacitance_fep"), 5),
             c, f_int(sc["instances"], 7), f_int(sc["area_um2"], 10),
             f_pct(sc["util_pct"]), views_cell(s), mark))
        prev = s


def render(b, superseded, stream=sys.stdout):
    w = stream.write
    run, chain, orphans = b["run"], b["chain"], b["orphans"]
    trans, rrv, probe = b["transitions"], b["route_report_views"], b["db_probe"]
    tag = os.path.basename(run.rstrip("/"))
    bar = "=" * 118

    w("%s\n" % bar)
    w(" TIMING PROGRESSION  --  %s\n" % tag)
    w(" %d states in sequence, %d orphan, %d transitions.  Ordered by the tool's\n"
      % (len(chain), len(orphans), len(trans)))
    w(" own `Generated on:` clock, not by filename and not by mtime.\n")
    w("%s\n\n" % bar)

    render_regressions(w, trans)

    w("%s\n" % bar)
    w(" EVERY STATE IN SEQUENCE\n")
    w("   channel: report_timing_summary under timing_enable_simultaneous_setup_hold\n")
    w("   _mode -- setup and hold from ONE timing update over every ACTIVE view.\n")
    w("   WNS/TNS in ns. sFEP/hFEP/tranFEP/capFEP are failing-endpoint counts.\n")
    w("%s\n" % bar)
    render_table(w, chain)
    w("\n  `views` : `S/H` is a MEASURED active set (setup views / hold views) -- from\n")
    w("            a hook record taken at the state, or a read-only probe of the\n")
    w("            database it was saved to.\n")
    w("            `>=N` is only the count of view names the report itself mentions:\n")
    w("            a FLOOR, because a view that provoked no inference message leaves\n")
    w("            no trace. On this run the floor undercounts by one wherever both\n")
    w("            are available. See ANALYSIS VIEWS below.\n")
    w("  `= prev` : identical on every tracked metric -- the same database measured\n")
    w("             twice, not a new state.\n")
    w("  `~`      : instances/area/util CARRIED FORWARD from the last state that\n")
    w("             measured them. report_qor writes a row only at an optimisation\n")
    w("             snapshot, so anything added since is NOT in the number.\n")
    for k, v in sorted((b.get("manifest_scale") or {}).items()):
        w("             %-14s the run's own %s records total_insts %s%s\n"
          % (k + ":", v["file"], v["total_insts"],
             ("  (of which %s fillers)" % v["fillers"]) if v.get("fillers") else ""))
    w("\n")

    # ---- orphans -----------------------------------------------------------
    if orphans:
        w("%s\n" % bar)
        w(" STATES THAT DID NOT HAPPEN IN THIS SEQUENCE\n")
        w("   Their tool clock runs backwards against the ladder, so a later attempt\n")
        w("   overwrote their neighbours and not them -- because it never produced\n")
        w("   this state at all. They are NOT spliced into the chain above.\n")
        w("%s\n" % bar)
        for o in orphans:
            w("  %-28s clock %s   %s\n"
              % (o["state"], o["clock"], (o.get("rts") or {}).get("file", "?")))
            att = o.get("attributed_to")
            w("      %s\n" % ("byte-identical to " + ", ".join(att) if att else
                              "no sibling copy found -- provenance unresolved"))
            w("      setup %s / %s / %s     hold %s / %s / %s\n"
              % (mval(o, "setup_wns_ns"), mval(o, "setup_tns_ns"),
                 mval(o, "setup_fep"), mval(o, "hold_wns_ns"),
                 mval(o, "hold_tns_ns"), mval(o, "hold_fep")))
        w("\n")

    # ---- states with no comparable measurement -----------------------------
    gap = [s for s in (chain + b["noclock"]) if not s.get("rts")]
    allstates = list(b["states"].values())
    gap += [s for s in allstates if not s.get("rts") and s not in gap]
    if gap:
        w("%s\n" % bar)
        w(" STATES THE FLOW RAN AND DID NOT MEASURE COMPARABLY\n")
        w("   No report_timing_summary exists for these, so they cannot appear in\n")
        w("   the table above and no delta can be computed across them.\n")
        w("%s\n" % bar)
        for s in sorted(gap, key=lambda x: x["ladder_order"]):
            w("  %-30s %s\n" % (s["state"], s["label"]))
            q = s.get("qor")
            if q:
                r = q["row"]
                w("      report_qor `%s` [%s]\n" % (q["snapshot"], q["file"]))
                w("        setup WNS %-8s  util %-7s  insts %-8s  area %s um2\n"
                  % (r["wns_ns"]["raw"] or "-", r["util_pct"]["raw"] or "-",
                     r["instances"]["raw"] or "-", r["area_um2"]["raw"] or "-"))
                w("        hold: ABSENT. report_qor's snapshot table HAS NO HOLD\n")
                w("              COLUMN -- that is why a hold regression cannot\n")
                w("              appear in the flow's only progression view.\n")
            for o in s.get("opt", []):
                w("      opt_design %s-mode summary [%s]\n" % (o["mode"], o["file"]))
                w("        WNS %-8s TNS %-9s violating %-6s density %s%%\n"
                  % (o["wns_ns"], o["tns_ns"], o["violating_paths"],
                     o["density_pct"]))
                w("        command: %s\n" % (o["command"] or "?"))
                w("        NOT COMPARABLE with the table above: different\n")
                w("        instrument, %s, and this table prints the %s mode ONLY\n"
                  % ("with SI" if o.get("si") else "no SI", o["mode"]))
                w("        (opt_design never prints setup and hold together, so a\n")
                w("         trade is invisible in either half).\n")
                if o.get("note"):
                    w("        %s\n" % o["note"])
            if not q and not s.get("opt"):
                w("      NOTHING measured this state at all.\n")
            w("\n")

    # ---- superseded sequences ---------------------------------------------
    snaps = [x for x in superseded if x.get("is_snapshot")]
    if snaps:
        w("%s\n" % bar)
        w(" EVIDENCE TREES THAT ARE SNAPSHOTS OF THE SEQUENCE ABOVE (not reprinted)\n")
        w("%s\n" % bar)
        for x in snaps:
            w("  %-30s %d states, every one identical in id AND tool clock to a\n"
              % (x["name"], len(x["chain"])))
            w("  %-30s state already above -- a provenance copy, not a second run.\n" % "")
        w("\n")
    for x in [y for y in superseded if not y.get("is_snapshot")]:
        w("%s\n" % bar)
        w(" SUPERSEDED SEQUENCE: %s\n" % x["name"])
        w("   %d state(s) here exist nowhere else in this run:\n" % len(x["novel"]))
        for st, ck in x["novel"]:
            w("     %-30s %s\n" % (st, ck))
        for ln in (x.get("readme") or []):
            if ln.strip():
                w("   %s\n" % ln.strip())
        w("%s\n\n" % bar)
        render_regressions(w, x["transitions"], indent="  ")
        render_table(w, x["chain"], indent="   ")
        w("\n")

    # ---- the flow's own progression view, and what it cannot say ----------
    qtab = b.get("qor_table") or {"rows": {}, "files": {}}
    if qtab["rows"]:
        w("%s\n" % bar)
        w(" WHAT THE FLOW'S OWN PROGRESSION VIEW SHOWS  (report_qor snapshot table)\n")
        w("   This is the only per-pass progression the flow produces. Read it on\n")
        w("   its own and the run looks monotonic.\n")
        w("%s\n" % bar)
        w("   %-30s %-10s %-8s %-9s %-12s %s\n"
          % ("snapshot", "setup WNS", "sFEP", "util%", "insts", "hold"))
        w("   %s\n" % ("-" * 92))
        order = sorted(qtab["rows"].items(),
                       key=lambda kv: LADDER_ORDER.get(
                           QOR_SNAPSHOT_STATE.get(kv[0], ""), 500))
        for snap, row in order:
            w("   %-30s %-10s %-8s %-9s %-12s %s\n"
              % (snap, row["wns_ns"]["raw"] or "-", row["feps"]["raw"] or "-",
                 row["util_pct"]["raw"] or "-", row["instances"]["raw"] or "-",
                 "NO SUCH COLUMN"))
        w("\n   THE TABLE HAS NO HOLD COLUMN. Every hold number in this report came\n")
        w("   from somewhere else. A pass that destroys hold to buy setup shows in\n")
        w("   this table as an IMPROVEMENT.\n")
        # (e) a state the flow ran that this table cannot show, because the
        #     snapshot NAME was already taken by an earlier pass.
        missing = []
        for st in b["chain"] + b["orphans"]:
            if st.get("qor"):
                continue
            want = [k for k, v in QOR_SNAPSHOT_STATE.items() if v == st["state"]]
            if want and want[0] in qtab["rows"]:
                missing.append((st["state"], want[0]))
        for stname, snap in missing:
            w("\n   AND IT HAS NO ROW FOR `%s`.\n" % stname)
            w("   report_qor keys its rows by SNAPSHOT NAME. `%s` is already\n" % snap)
            w("   taken by the earlier pass that issued the same command, so a\n")
            w("   repeat does not add a row -- it adds nothing at all. The pass ran;\n")
            w("   the flow's progression table does not know it happened.\n")
        w("\n")

    # ---- analysis views ----------------------------------------------------
    w("%s\n" % bar)
    w(" ANALYSIS VIEWS\n")
    w("   A hold WNS worst over one view is not the same measurement as one worst\n")
    w("   over four. Every claim below carries the basis it rests on.\n")
    w("%s\n" % bar)
    if probe:
        w("  read-only database probe -- get_db analysis_views .is_active/.is_setup/\n")
        w("  .is_hold. This is the definitive active set for the saved state:\n")
        for db in sorted(probe):
            w("    %-14s setup(%d)  %s\n"
              % (db, len(probe[db].get("setup", [])),
                 " ".join(probe[db].get("setup", []))))
            w("    %-14s hold (%d)  %s\n"
              % ("", len(probe[db].get("hold", [])),
                 " ".join(probe[db].get("hold", []))))
    else:
        w("  NO database probe present (<run>/index/views_<db>.txt absent). This\n")
        w("  tool does not launch Innovus; without a probe the active set is only\n")
        w("  bounded from below by the names each report happens to mention.\n")
    if rrv:
        w("\n  the flow's own record -- %s.\n" % rrv["source"])
        w("  This is the ONLY place the flow writes an active view set down, and it\n")
        w("  covers the route stage's last reports only:\n")
        for fn, v in sorted(rrv["per_report"].items()):
            w("    %-50s setup(%d) hold(%d)\n"
              % (fn, len(v["setup"]), len(v["hold"])))
        if rrv["restored"]:
            w("    set_analysis_view restored to:\n")
            w("      setup(%d) %s\n" % (len(rrv["restored"]["setup"]),
                                        " ".join(rrv["restored"]["setup"])))
            w("      hold (%d) %s\n" % (len(rrv["restored"]["hold"]),
                                        " ".join(rrv["restored"]["hold"])))
    # The one check that catches a manifest declaring a scope its own numbers
    # were not measured over.
    if probe.get("routed") and rrv and rrv.get("restored"):
        pr = probe["routed"]
        rs = rrv["restored"]
        w("\n  SCOPE CHECK -- the streamed database against the states before it\n")
        w("    the saved `routed` database (the one the GDS came from):\n")
        w("      setup(%d) %s\n" % (len(pr.get("setup", [])),
                                    " ".join(pr.get("setup", []))))
        w("      hold (%d) %s\n" % (len(pr.get("hold", [])),
                                    " ".join(pr.get("hold", []))))
        if probe.get("route_preopt"):
            pp = probe["route_preopt"]
            lost_s = [v for v in pp.get("setup", []) if v not in pr.get("setup", [])]
            lost_h = [v for v in pp.get("hold", []) if v not in pr.get("hold", [])]
            if lost_s or lost_h:
                w("    the `route_preopt` database, saved EARLIER IN THE SAME STAGE,\n")
                w("    had setup(%d) hold(%d). Between the two saves the stage\n"
                  % (len(pp.get("setup", [])), len(pp.get("hold", []))))
                w("    re-issued set_analysis_view and DROPPED:\n")
                if lost_s:
                    w("      from setup: %s\n" % " ".join(lost_s))
                if lost_h:
                    w("      from hold : %s\n" % " ".join(lost_h))
                w("    Every timing number the stage reported BEFORE that line --\n")
                w("    including 06_post_fill, which is what the stage manifest and\n")
                w("    the budget gate quote -- was measured over the WIDER set.\n")
                w("    The manifest's own views_setup/views_hold keys record the\n")
                w("    NARROWER one. Neither number is wrong; the pairing is.\n")
    w("\n  per state, view names the report itself mentions, against the probe:\n")
    w("    the report's own names are a FLOOR. A view that provoked no inference\n")
    w("    message leaves no trace, and on this run that is exactly what happens:\n")
    w("    every pre-narrowing state has FIVE active views and several reports\n")
    w("    name only four. Read `>=4` as `at least four`, never as `four`.\n")
    w("    %-28s %-6s %-8s %s\n" % ("state", "floor", "passes", "probe (setup/hold)"))
    for s in chain + orphans:
        nm = s.get("views_named")
        if not nm:
            continue
        pv = None
        for st_key, dbtag in (("00_pre_place", "fplan"),
                              ("01b_place_opt", "placed"),
                              ("03_cts_opt", "cts"),
                              ("05_route_opt", "route_preopt"),
                              ("07_streamed", "routed")):
            if s["state"] == st_key and dbtag in probe:
                pv = "%d/%d  (%s)" % (len(probe[dbtag].get("setup", [])),
                                      len(probe[dbtag].get("hold", [])), dbtag)
        w("    %-28s >=%-4d %-8d %s\n"
          % (s["state"], nm["count"], s.get("delaycalc_passes") or 0,
             pv or "-- no saved database corresponds to this state"))
    w("\n")

    # ---- housekeeping ------------------------------------------------------
    if b["notes"] or b["unfiled"]:
        w("%s\n" % bar)
        w(" NOTES\n")
        w("%s\n" % bar)
        for n in b["notes"]:
            w("  %s\n" % n)
        for u in b["unfiled"]:
            w("  unfiled: %-58s %s\n" % (u["file"], u["why"]))
        w("\n")



def read_manifest_scale(run, report_dirs):
    """`<phase>_manifest.txt` -- `total_insts`, and `filler_insts` where the
    stage counted them. This is the ONLY count in the run that includes the
    fillers added after the last report_qor snapshot, and it is written at the
    END of a stage, so it describes that stage's LAST state and no other."""
    out = {}
    LAST_STATE = {"place": "01b_place_opt", "cts": "03_cts_opt",
                  "route": "06_post_fill"}
    for d in report_dirs:
        if not os.path.isdir(d):
            continue
        for fn in sorted(os.listdir(d)):
            m = re.match(r"^(place|cts|route)_manifest\.txt$", fn)
            if not m:
                continue
            tot = fil = None
            for ln in read_text(os.path.join(d, fn)):
                mm = re.match(r"^total_insts\s+(\d+)", ln)
                if mm and tot is None:
                    tot = int(mm.group(1))
                mm = re.match(r"^filler_insts\s+(\d+)", ln)
                if mm:
                    fil = int(mm.group(1))
            if tot is not None:
                out[LAST_STATE[m.group(1)]] = {
                    "file": rel(os.path.join(d, fn), run),
                    "total_insts": tot, "fillers": fil}
    return out


# ---------------------------------------------------------------------------
def build(run, extra_dirs, report_dirs=None, log_dirs=None):
    run, states, notes, unfiled, qtab = collect(run, report_dirs, log_dirs)
    rrv, probe = resolve_views(run, states)
    chain, orphans, noclock = sequence(run, states, extra_dirs)
    for s in noclock:
        s["flags"].append("NO-CLOCK")
    trans = transitions(chain, chain)
    return {"run": run, "states": states, "chain": chain, "orphans": orphans,
            "noclock": noclock, "transitions": trans, "notes": notes,
            "unfiled": unfiled, "route_report_views": rrv, "db_probe": probe,
            "qor_table": qtab,
            "manifest_scale": read_manifest_scale(
                run, report_dirs if report_dirs is not None
                else [os.path.join(run, "reports")])}


def build_superseded(run, evidence_dirs):
    """Each `attempt*-evidence` directory is a SEQUENCE IN ITS OWN RIGHT: a
    superseded attempt kept on purpose. Its states are real measurements of a
    different configuration, so they get their own chain and their own
    regression list, and are never mixed with the live one."""
    out = []
    for d in evidence_dirs:
        if not os.path.isdir(d):
            continue
        # These trees are flat: timing_summary_*, pnr_qor_*, qor_* and the
        # opt summaries all sit side by side.
        b = build(run, [], report_dirs=[d], log_dirs=[d])
        if not b["chain"]:
            continue
        b["name"] = os.path.basename(d.rstrip("/"))
        readme = os.path.join(d, "README.txt")
        b["readme"] = (read_text(readme)[:3] if os.path.exists(readme) else None)
        out.append(b)
    return out


def classify_superseded(live, superseded):
    """An `attempt*-evidence` tree is one of two things and they need saying
    apart. Either it holds states this run no longer has -- a genuinely
    superseded attempt, whose numbers are the only record of a configuration
    that was tried -- or it is a snapshot of the live sequence kept for
    provenance, in which case reprinting it is noise.

    Decided on the states themselves: same state id AND same tool clock means
    the same measurement, not a second one."""
    livekeys = {(x["state"], x["clock"]) for x in live["chain"] + live["orphans"]}
    for x in superseded:
        mine = {(y["state"], y["clock"]) for y in x["chain"] + x["orphans"]}
        x["novel"] = sorted(k for k in mine if k not in livekeys)
        x["is_snapshot"] = not x["novel"]
    return superseded


def to_json(b, superseded):
    def seq(x):
        return {
            "states": x["chain"] + x["orphans"] + x["noclock"],
            "transitions": x["transitions"],
            "regressions_worst_first": sorted(
                [{"from": t["from"], "to": t["to"], "worse": t["worse"],
                  "better": t["better"], "flags": t["flags"],
                  "trade": t.get("trade"), "severity": severity(t)}
                 for t in x["transitions"] if t["worse"]],
                key=lambda r: -r["severity"]),
            "orphan_states": [{"state": o["state"], "clock": o["clock"],
                               "file": (o.get("rts") or {}).get("file"),
                               "attributed_to": o.get("attributed_to")}
                              for o in x["orphans"]],
        }
    doc = {
        "schema": SCHEMA,
        "run_dir": b["run"],
        "generated": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "generator": "scripts/ci/stage_timeline.py",
        "reuses": "scripts/ci/run_index.py parse_timing_summary/parse_qor_snapshots",
        "sequence": seq(b),
        "superseded_sequences": {x["name"]: seq(x) for x in superseded},
        "route_report_views": b["route_report_views"],
        "db_probe": b["db_probe"],
        "notes": b["notes"],
        "unfiled": b["unfiled"],
    }
    return doc



HOOK_BEGIN = "# ---- BEGIN shared state-record emitter"
HOOK_END = "# ---- END shared state-record emitter"


def _hook_block(path):
    """The emitter block out of one hook file, or None and why not."""
    try:
        lines = open(path, errors="replace").read().split("\n")
    except Exception as e:
        return None, "unreadable: %s" % e
    a = b = None
    for i, ln in enumerate(lines):
        if a is None and ln.startswith(HOOK_BEGIN):
            a = i
        elif a is not None and ln.startswith(HOOK_END):
            b = i
            break
    if a is None:
        return None, "no line starting `%s`" % HOOK_BEGIN
    if b is None:
        return None, "`%s` with no matching `%s`" % (HOOK_BEGIN, HOOK_END)
    return lines[a:b + 1], None


def check_hooks():
    """The two hooks carry the same emitter by hand, because a pinned hook has
    no path to a library in scripts/. Nothing stops them drifting except this."""
    root = os.path.dirname(os.path.dirname(HERE))
    hd = os.path.join(root, "ASIC", "eth-chiplet", "hooks")
    files = [os.path.join(hd, "post_place.tcl"), os.path.join(hd, "post_route.tcl")]
    blocks = {}
    rc = 0
    for f in files:
        blk, why = _hook_block(f)
        if blk is None:
            sys.stdout.write("  %-60s NO BLOCK: %s\n" % (rel(f, root), why))
            rc = 1
        else:
            blocks[f] = blk
            sys.stdout.write("  %-60s %d lines\n" % (rel(f, root), len(blk)))
    if len(blocks) == 2:
        a, b = [blocks[f] for f in files]
        if a == b:
            sys.stdout.write("  IDENTICAL -- the two copies have not drifted.\n")
        else:
            rc = 1
            sys.stdout.write("  DRIFTED. The two copies differ:\n")
            import difflib
            for ln in list(difflib.unified_diff(
                    a, b, os.path.basename(files[0]),
                    os.path.basename(files[1]), lineterm=""))[:80]:
                sys.stdout.write("    %s\n" % ln)
    return rc


def main():
    ap = argparse.ArgumentParser(
        description="Per-optimisation-state timing record and progression.")
    ap.add_argument("run_dir", nargs="?", default=".")
    ap.add_argument("--json", metavar="PATH",
                    help="also write the machine-readable record here")
    ap.add_argument("--also", action="append", default=[], metavar="DIR",
                    help="an extra evidence directory to md5-match orphans "
                         "against (repeatable). Sibling *-evidence dirs are "
                         "picked up automatically.")
    ap.add_argument("--expect", action="append", default=[], metavar="EXPR",
                    help="cross-check, e.g. 'cts_after_post_cts_hold:hold_wns_ns=0.003'. "
                         "Exits 1 on disagreement.")
    ap.add_argument("--quiet", action="store_true",
                    help="suppress the human report (use with --json)")
    ap.add_argument("--no-superseded", action="store_true",
                    help="do not read sibling attempt*-evidence directories")
    ap.add_argument("--check-hooks", action="store_true",
                    help="compare the duplicated state-record emitter in "
                         "ASIC/eth-chiplet/hooks/post_place.tcl and "
                         "post_route.tcl and exit 1 if they have drifted. "
                         "run_dir is ignored.")
    a = ap.parse_args()

    if a.check_hooks:
        return check_hooks()

    run = os.path.abspath(a.run_dir)
    if not os.path.isdir(run):
        sys.stderr.write("no such run directory: %s\n" % run)
        return 2

    extra = list(a.also)
    for fn in sorted(os.listdir(run)):
        p = os.path.join(run, fn)
        if os.path.isdir(p) and re.match(r"^attempt.*evidence$", fn):
            extra.append(p)

    b = build(run, extra)
    superseded = build_superseded(run, extra) if not a.no_superseded else []
    superseded = classify_superseded(b, superseded)

    if not a.quiet:
        render(b, superseded)

    if a.json:
        with open(a.json, "w") as fh:
            json.dump(to_json(b, superseded), fh, indent=2, default=str)
        sys.stderr.write("wrote %s\n" % a.json)

    rc = 0
    if a.expect:
        by = {s["state"]: s for s in b["chain"] + b["orphans"] + b["noclock"]}
        for x in superseded:
            for s2 in x["chain"] + x["orphans"]:
                by.setdefault("%s/%s" % (x["name"], s2["state"]), s2)
        sys.stdout.write("\n  CROSS-CHECK\n")
        for e in a.expect:
            try:
                where, rhs = e.split(":", 1)
                metric, want = rhs.split("=", 1)
                want = float(want)
            except ValueError:
                sys.stdout.write("    %-56s MALFORMED\n" % e)
                rc = 1
                continue
            got = mval(by[where], metric) if where in by else None
            ok = got is not None and abs(got - want) < 5e-4
            sys.stdout.write("    %-30s %-22s expected %9s  got %9s  %s\n"
                             % (where, metric, want, got,
                                "OK" if ok else "MISMATCH"))
            if not ok:
                rc = 1
    return rc


if __name__ == "__main__":
    sys.exit(main())
